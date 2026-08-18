---@diagnostic disable: undefined-global

-- Shared TapTap player identity lookup.
--
-- Nicknames belong to the account system and must always be resolved through
-- GetUserNickname.  The service deliberately does not invent an avatar URL:
-- UI can render the returned initials and stable colour with UI.Avatar.

local UserProfileService = {}

UserProfileService.NICKNAME_BATCH_SIZE = 100
UserProfileService.MAX_NICKNAME_CHARACTERS = 24
-- The exploration panel can be opened while Maker's lobby/account bridge is
-- still warming up. game96 normally reaches its leaderboard much later, after
-- a completed round. Retry that short startup window instead of permanently
-- turning the first -1 response into a "player + id" label.
UserProfileService.REQUEST_TIMEOUT_SECONDS = 35
UserProfileService.STARTUP_RETRY_DELAYS = { 0.6, 1.2, 2.4 }

local AVATAR_COLORS = {
    { 238, 111, 102, 255 },
    { 238, 154, 76, 255 },
    { 220, 177, 69, 255 },
    { 102, 177, 111, 255 },
    { 69, 169, 163, 255 },
    { 83, 144, 210, 255 },
    { 112, 119, 204, 255 },
    { 157, 105, 197, 255 },
    { 207, 104, 157, 255 },
}

local nicknameCache_ = {}
local requestClock_, nextRequestId_ = 0, 0
local pendingRequests_, scheduledTasks_ = {}, {}
local nextTaskId_ = 0
local lastDiagnostic_ = {}

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
end

local function Dispatch(callbacks, name, ...)
    local callback = callbacks and callbacks[name]
    if callback then callback(...) end
end

local function Once(callback)
    local called = false
    return function(...)
        if called then return false end
        called = true
        if callback then callback(...) end
        return true
    end
end

local function Log(message)
    print("[game124][identity] " .. tostring(message))
end

local function Schedule(delay, callback)
    nextTaskId_ = nextTaskId_ + 1
    local id = nextTaskId_
    scheduledTasks_[id] = {
        deadline = requestClock_ + math.max(0, tonumber(delay) or 0),
        callback = callback,
    }
    return id
end

local function UserKey(userId)
    if userId == nil then return nil end
    local key = tostring(userId):match("^%s*(.-)%s*$") or ""
    if key == "" then return nil end

    -- Maker's JSON bridge decodes account IDs as Lua numbers, so an integer
    -- userId may arrive as "679301503.0" while the rank envelope supplied
    -- "679301503". Normalize only plain integral decimal forms; opaque/string
    -- IDs keep their exact value.
    local integer, zeroes = key:match("^([+-]?%d+)%.(0+)$")
    if integer ~= nil and zeroes ~= nil then key = integer end
    if key:sub(1, 1) == "+" then key = key:sub(2) end
    if key:match("^-?%d+$") then
        local sign, digits = key:match("^(-?)(%d+)$")
        digits = tostring(digits or ""):gsub("^0+", "")
        if digits == "" then digits = "0" end
        if sign == "-" and digits ~= "0" then key = "-" .. digits else key = digits end
    end
    return key
end

local function ExtractUserId(value)
    if type(value) ~= "table" then return value end
    return value.userId or value.user_id or value.userID or value.player
        or value.playerId or value.uid
end

local function ValidUtf8Width(text, index)
    local first = text:byte(index)
    if not first then return nil end
    if first < 0x80 then return 1 end

    local second, third, fourth = text:byte(index + 1), text:byte(index + 2), text:byte(index + 3)
    local function Continuation(byte) return byte and byte >= 0x80 and byte <= 0xBF end
    if first >= 0xC2 and first <= 0xDF and Continuation(second) then return 2 end
    if first >= 0xE0 and first <= 0xEF and Continuation(second) and Continuation(third) then
        if first == 0xE0 and second < 0xA0 then return nil end
        if first == 0xED and second > 0x9F then return nil end
        return 3
    end
    if first >= 0xF0 and first <= 0xF4
        and Continuation(second) and Continuation(third) and Continuation(fourth) then
        if first == 0xF0 and second < 0x90 then return nil end
        if first == 0xF4 and second > 0x8F then return nil end
        return 4
    end
    return nil
end

local function LimitedUtf8(value, maximum)
    local source = tostring(value or "")
    local result, index, count = {}, 1, 0
    while index <= #source and count < maximum do
        local width = ValidUtf8Width(source, index)
        if width then
            local byte = source:byte(index)
            if byte >= 32 and byte ~= 127 then
                result[#result + 1] = source:sub(index, index + width - 1)
                count = count + 1
            elseif byte == 9 or byte == 10 or byte == 13 then
                result[#result + 1] = " "
                count = count + 1
            end
            index = index + width
        else
            index = index + 1
        end
    end
    return table.concat(result):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

local function FallbackNickname(userId)
    return UserKey(userId) and "云岛旅人" or "游客"
end

local function SafeNickname(value, userId)
    local nickname = LimitedUtf8(value, UserProfileService.MAX_NICKNAME_CHARACTERS)
    return nickname ~= "" and nickname or FallbackNickname(userId)
end

local function FirstCharacter(text)
    text = tostring(text or "")
    local index = 1
    while index <= #text do
        local width = ValidUtf8Width(text, index)
        if width then
            local character = text:sub(index, index + width - 1)
            if not character:match("%s") then
                return width == 1 and string.upper(character) or character
            end
            index = index + width
        else
            index = index + 1
        end
    end
    return "?"
end

local function StableColor(text)
    local hash = 2166136261
    for index = 1, #text do
        -- Keep the arithmetic below 2^53 so Lua's number representation is
        -- deterministic even in runtimes where integer operations differ.
        hash = (hash * 16777619 + text:byte(index)) % 2147483647
    end
    return Copy(AVATAR_COLORS[(hash % #AVATAR_COLORS) + 1])
end

local function BuildProfile(userId, nickname)
    local key = UserKey(userId) or ""
    local safeNickname = SafeNickname(nickname, key ~= "" and key or nil)
    return {
        userId = key,
        nickname = safeNickname,
        avatar = UserProfileService.BuildAvatar(safeNickname),
    }
end

function UserProfileService.CurrentUserId()
    local cloud = rawget(_G, "clientCloud")
    return UserKey(cloud and cloud.userId)
end

function UserProfileService.FallbackNickname(userId)
    return FallbackNickname(userId)
end

-- Returns UI.Avatar-compatible props. There is intentionally no `src` field:
-- the runtime currently exposes nickname lookup, not an account-avatar API.
function UserProfileService.BuildAvatar(nickname, size)
    local safeNickname = SafeNickname(nickname, nil)
    return {
        name = safeNickname,
        initials = FirstCharacter(safeNickname),
        backgroundColor = StableColor(safeNickname),
        size = size or "md",
        shape = "circle",
        showBorder = true,
    }
end

function UserProfileService.GetCached(userId)
    local key = UserKey(userId)
    if not key then return BuildProfile(nil, nil) end
    return BuildProfile(key, nicknameCache_[key])
end

local function ApplyNicknameResponse(response, seen)
    local resolved = 0
    -- This deliberately follows Maker's documented/runtime contract and the
    -- working game96 path: an array of { userId, nickname } records.
    for _, info in ipairs(type(response) == "table" and response or {}) do
        local key = type(info) == "table" and UserKey(info.userId) or nil
        local nickname = type(info) == "table"
            and LimitedUtf8(info.nickname, UserProfileService.MAX_NICKNAME_CHARACTERS) or ""
        if key and seen[key] and nickname ~= "" then
            resolved = resolved + 1
            nicknameCache_[key] = nickname
            Log("nickname resolved userId=" .. key)
        end
    end
    return resolved
end

-- Resolve a deduplicated set of player IDs. Calls are serialised in batches of
-- at most 100. `ok(byId, ordered, source)` fires exactly once even when the
-- account API is absent, throws, omits records, or invokes duplicate callbacks.
-- byId is always keyed by tostring(userId), avoiding number/string mismatches.
function UserProfileService.Resolve(userIds, callbacks)
    userIds = type(userIds) == "table" and userIds or {}
    local orderedIds, originalIds, seen = {}, {}, {}
    for _, userId in ipairs(userIds) do
        local key = UserKey(userId)
        if key and not seen[key] then
            seen[key] = true
            orderedIds[#orderedIds + 1] = key
            originalIds[key] = userId
        end
    end

    local source = "account"
    local hadFailure, lookupAvailable = false, false
    local expired, timeoutId = false, nil
    local diagnostic = {
        requested = #orderedIds,
        resolved = 0,
        attempts = 0,
        errors = {},
        status = "pending",
    }
    lastDiagnostic_ = diagnostic
    local complete = Once(function()
        if timeoutId then pendingRequests_[timeoutId] = nil end
        local byId, ordered = {}, {}
        for _, key in ipairs(orderedIds) do
            local profile = BuildProfile(key, nicknameCache_[key])
            byId[key] = profile
            ordered[#ordered + 1] = profile
        end
        if #orderedIds == 0 then source = "empty"
        elseif not lookupAvailable then source = "fallback"
        elseif hadFailure then source = "partial" end
        diagnostic.status = source
        diagnostic.resolved = 0
        for _, key in ipairs(orderedIds) do
            if nicknameCache_[key] ~= nil then diagnostic.resolved = diagnostic.resolved + 1 end
        end
        if diagnostic.resolved < diagnostic.requested then
            Log("nickname resolve finished source=" .. source
                .. " requested=" .. tostring(diagnostic.requested)
                .. " resolved=" .. tostring(diagnostic.resolved))
        end
        Dispatch(callbacks, "ok", byId, ordered, source)
    end)

    if #orderedIds == 0 then complete(); return true end

    nextRequestId_ = nextRequestId_ + 1
    timeoutId = nextRequestId_
    pendingRequests_[timeoutId] = {
        deadline = requestClock_ + UserProfileService.REQUEST_TIMEOUT_SECONDS,
        timeout = function()
            expired, hadFailure = true, true
            diagnostic.errors[#diagnostic.errors + 1] = "timeout"
            Log("nickname request timed out after "
                .. tostring(UserProfileService.REQUEST_TIMEOUT_SECONDS) .. "s")
            complete()
        end,
    }

    local cursor = 1
    local function FetchNext()
        if expired then return end
        if cursor > #orderedIds then complete(); return end
        local first = cursor
        local last = math.min(#orderedIds, first + UserProfileService.NICKNAME_BATCH_SIZE - 1)
        cursor = last + 1
        local batchIds = {}
        for index = first, last do
            local key = orderedIds[index]
            -- Preserve the rank-list value exactly like game96. Maker's own
            -- UserInfo bridge accepts number/string and performs normalization.
            batchIds[#batchIds + 1] = originalIds[key]
        end

        local settleBatch = Once(function(nicknames, failed)
            if failed then hadFailure = true end
            diagnostic.resolved = diagnostic.resolved + ApplyNicknameResponse(nicknames, seen)
            FetchNext()
        end)

        local function Attempt(attempt)
            if expired then return end
            diagnostic.attempts = diagnostic.attempts + 1
            local lookup = type(GetUserNickname) == "function" and GetUserNickname or nil
            lookupAvailable = lookupAvailable or type(lookup) == "function"

            local function RetryOrFinish(reason, errorCode)
                diagnostic.errors[#diagnostic.errors + 1] = tostring(errorCode or reason)
                local delay = UserProfileService.STARTUP_RETRY_DELAYS[attempt]
                if delay and not expired then
                    Log("nickname bridge not ready (" .. tostring(errorCode or reason)
                        .. "), retry=" .. tostring(attempt) .. " delay=" .. tostring(delay))
                    Schedule(delay, function() Attempt(attempt + 1) end)
                else
                    Log("nickname batch failed: " .. tostring(errorCode or reason))
                    settleBatch(nil, true)
                end
            end

            if type(lookup) ~= "function" then
                RetryOrFinish("lookup-unavailable")
                return
            end

            local attemptSettled = Once(function(kind, payload)
                if expired then return end
                if kind == "success" then
                    local resolved = ApplyNicknameResponse(payload, seen)
                    diagnostic.resolved = diagnostic.resolved + resolved
                    if resolved == 0 and #batchIds > 0 then
                        RetryOrFinish("empty-response")
                    else
                        -- Names were applied above; avoid applying the same
                        -- response twice in settleBatch.
                        settleBatch(nil, false)
                    end
                else
                    local code = payload
                    -- -1 is Maker's documented "bridge/internal not ready"
                    -- error. A timeout (-2) has already spent its network
                    -- window, so do not start another long request.
                    if code == -1 or code == nil then RetryOrFinish("onError", code)
                    else
                        diagnostic.errors[#diagnostic.errors + 1] = tostring(code)
                        Log("nickname batch onError=" .. tostring(code))
                        settleBatch(nil, true)
                    end
                end
            end)

            local started, startError = pcall(function()
                lookup({
                    userIds = batchIds,
                    onSuccess = function(nicknames) attemptSettled("success", nicknames) end,
                    onError = function(errorCode) attemptSettled("error", errorCode) end,
                })
            end)
            if not started then
                diagnostic.errors[#diagnostic.errors + 1] = "pcall:" .. tostring(startError)
                Log("nickname lookup threw: " .. tostring(startError))
                settleBatch(nil, true)
            end
        end

        Attempt(1)
    end

    FetchNext()
    return true
end

-- Account callbacks are normally prompt, but a platform/network interruption
-- must not leave an exploration list or guestbook loading forever. main.lua
-- advances this tiny request clock once per frame; timed-out requests complete
-- with fallback nicknames and ignore any duplicate late completion.
function UserProfileService.Update(timeStep)
    local delta = tonumber(timeStep) or 0
    if delta ~= delta or delta == math.huge or delta == -math.huge then delta = 0 end
    requestClock_ = requestClock_ + math.max(0, math.min(delta, 1))
    local readyTasks = {}
    for id, task in pairs(scheduledTasks_) do
        if requestClock_ >= (tonumber(task.deadline) or requestClock_) then
            readyTasks[#readyTasks + 1] = { id = id, callback = task.callback }
        end
    end
    table.sort(readyTasks, function(first, second) return first.id < second.id end)
    for _, task in ipairs(readyTasks) do
        if scheduledTasks_[task.id] then
            scheduledTasks_[task.id] = nil
            task.callback()
        end
    end
    local expired = {}
    for id, request in pairs(pendingRequests_) do
        if requestClock_ >= (tonumber(request.deadline) or requestClock_) then
            expired[#expired + 1] = { id = id, timeout = request.timeout }
        end
    end
    for _, request in ipairs(expired) do
        if pendingRequests_[request.id] then
            pendingRequests_[request.id] = nil
            request.timeout()
        end
    end
end

function UserProfileService.GetLastDiagnostic()
    return Copy(lastDiagnostic_)
end

function UserProfileService.ResolveNames(userIds, callbacks)
    return UserProfileService.Resolve(userIds, {
        ok = function(byId, ordered, source)
            local names = {}
            for key, profile in pairs(byId) do names[key] = profile.nickname end
            Dispatch(callbacks, "ok", names, ordered, source)
        end,
    })
end

function UserProfileService.ResetCache()
    nicknameCache_ = {}
    pendingRequests_, scheduledTasks_ = {}, {}
    lastDiagnostic_ = {}
    requestClock_, nextRequestId_, nextTaskId_ = 0, 0, 0
end

UserProfileService.Copy = Copy
UserProfileService.UserKey = UserKey
UserProfileService.ExtractUserId = ExtractUserId

return UserProfileService
