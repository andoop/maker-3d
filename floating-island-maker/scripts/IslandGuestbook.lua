---@diagnostic disable: undefined-global

-- Distributed guestbook built only from clientCloud primitives.
--
-- Each visitor owns one bounded outbox and upserts at most one message per
-- target island. The activity integer makes those outboxes discoverable via a
-- ranking read. A rank item's userId is the trusted author identity; author
-- fields inside the value payload are deliberately ignored.

local IslandGuestbook = {}
local UserProfileService = require("UserProfileService")

IslandGuestbook.OUTBOX_KEY = "island3d_guestbook_outbox_v1"
IslandGuestbook.ACTIVITY_KEY = "island3d_guestbook_activity_v2"
IslandGuestbook.OUTBOX_SCHEMA = "island-guestbook-outbox/v1"
IslandGuestbook.MAX_TEXT_CHARACTERS = 80
IslandGuestbook.MAX_OUTBOX_ENTRIES = 24
IslandGuestbook.MAX_OUTBOX_INPUT_ENTRIES = 96
IslandGuestbook.MAX_MESSAGES = 100
IslandGuestbook.RANK_PAGE_SIZE = 100

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

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
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

function IslandGuestbook.SanitizeText(value)
    local source = tostring(value or "")
    local result, index, count, pendingSpace = {}, 1, 0, false
    while index <= #source and count < IslandGuestbook.MAX_TEXT_CHARACTERS do
        local width = ValidUtf8Width(source, index)
        if width then
            local byte = source:byte(index)
            local isWhitespace = byte == 9 or byte == 10 or byte == 13 or byte == 32
            if isWhitespace then
                pendingSpace = count > 0
            elseif byte >= 32 and byte ~= 127 then
                -- Only commit an internal space if there is still room for the
                -- character after it. Leading/trailing whitespace therefore
                -- never consumes the visible 80-character allowance.
                if pendingSpace and count + 1 < IslandGuestbook.MAX_TEXT_CHARACTERS then
                    result[#result + 1] = " "
                    count = count + 1
                end
                pendingSpace = false
                result[#result + 1] = source:sub(index, index + width - 1)
                count = count + 1
            end
            index = index + width
        else
            -- Drop malformed UTF-8 bytes rather than forwarding them to UI or
            -- persisting a value another client cannot decode.
            index = index + 1
        end
    end
    return table.concat(result)
end

local function LimitedId(value)
    local text = tostring(value or "")
    text = text:gsub("[%z\1-\31\127]", ""):match("^%s*(.-)%s*$") or ""
    return text:sub(1, 120)
end

local function NormalizeTarget(target)
    target = type(target) == "table" and target or {}
    local ownerId = LimitedId(target.ownerId or target.targetOwnerId)
    local islandId = LimitedId(target.islandId or target.publicationId or target.targetIslandId)
    if ownerId == "" or islandId == "" then return nil end
    return {
        ownerId = ownerId,
        islandId = islandId,
        name = IslandGuestbook.SanitizeText(target.name or "空岛"),
    }
end

function IslandGuestbook.TargetKey(target)
    local clean = NormalizeTarget(target)
    return clean and (clean.ownerId .. "\31" .. clean.islandId) or nil
end

-- Every island owns an independent activity ranking. A single global ranking
-- would make quiet islands lose messages as soon as 100 people leave newer
-- notes elsewhere. Two deterministic hashes keep the cloud score key short
-- while making accidental cross-island collisions negligibly unlikely.
function IslandGuestbook.ActivityKey(target)
    local key = IslandGuestbook.TargetKey(target)
    if not key then return nil end
    local first, second = 216613626, 1315423911
    for index = 1, #key do
        local byte = key:byte(index)
        -- Products stay well below 2^53, so integer and double-backed Lua
        -- runtimes derive exactly the same cloud key.
        first = (first * 65599 + byte) % 2147483647
        second = (second * 8191 + byte + index) % 2147483629
    end
    return IslandGuestbook.ACTIVITY_KEY .. "_" .. tostring(first) .. "_" .. tostring(second)
end

local function Timestamp()
    local ok, rawValue = pcall(os.time)
    ---@type number
    local value = 0
    if ok then
        local parsed = tonumber(rawValue)
        if parsed then value = parsed end
    end
    if value ~= value or value == math.huge or value == -math.huge then value = 0 end
    return math.max(1, math.floor(value))
end

local function Decode(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" or value == "" then return nil end
    local json = rawget(_G, "cjson")
    if not json or type(json.decode) ~= "function" then return nil end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == "table" and result or nil
end

local function ExtractValue(container)
    if type(container) ~= "table" then return nil end
    return Decode(container[IslandGuestbook.OUTBOX_KEY])
end

local function ExtractOutbox(value)
    value = Decode(value)
    if type(value) ~= "table" then return {} end
    local items = type(value.items) == "table" and value.items or value
    return type(items) == "table" and items or {}
end

local function NormalizeMessage(source)
    if type(source) ~= "table" then return nil end
    local target = NormalizeTarget(source)
    local text = IslandGuestbook.SanitizeText(source.text)
    if not target or text == "" then return nil end
    local createdAt = tonumber(source.createdAt) or 0
    if createdAt ~= createdAt or createdAt == math.huge or createdAt == -math.huge then createdAt = 0 end
    return {
        targetOwnerId = target.ownerId,
        targetIslandId = target.islandId,
        text = text,
        createdAt = math.max(0, math.floor(createdAt)),
    }
end

local function NormalizeOutbox(value)
    local items, byTarget = {}, {}
    for index, source in ipairs(ExtractOutbox(value)) do
        if index > IslandGuestbook.MAX_OUTBOX_INPUT_ENTRIES then break end
        local item = NormalizeMessage(source)
        if item then
            local key = item.targetOwnerId .. "\31" .. item.targetIslandId
            local previous = byTarget[key]
            if not previous or item.createdAt >= previous.createdAt then byTarget[key] = item end
        end
    end
    for _, item in pairs(byTarget) do items[#items + 1] = item end
    table.sort(items, function(first, second)
        if first.createdAt ~= second.createdAt then return first.createdAt > second.createdAt end
        local firstKey = first.targetOwnerId .. "\31" .. first.targetIslandId
        local secondKey = second.targetOwnerId .. "\31" .. second.targetIslandId
        return firstKey < secondKey
    end)
    while #items > IslandGuestbook.MAX_OUTBOX_ENTRIES do table.remove(items) end
    return items
end

local function GetCloud(requireWrite)
    local cloud = rawget(_G, "clientCloud")
    if not cloud or type(cloud.GetRankList) ~= "function" then return nil end
    if requireWrite and (type(cloud.Get) ~= "function" or type(cloud.BatchSet) ~= "function") then return nil end
    return cloud
end

function IslandGuestbook.IsOnline()
    return GetCloud(false) ~= nil
end

function IslandGuestbook.Post(target, text, callbacks)
    local cleanTarget = NormalizeTarget(target)
    local cleanText = IslandGuestbook.SanitizeText(text)
    local finish = Once(function(name, ...)
        Dispatch(callbacks, name, ...)
    end)
    if not cleanTarget then finish("error", "留言目标无效", "invalid_target"); return false end
    if cleanText == "" then finish("error", "请输入留言内容", "empty_text"); return false end

    local cloud = GetCloud(true)
    if not cloud then finish("error", "留言功能暂不可用", "offline"); return false end
    local authorId = UserProfileService.CurrentUserId()
    if not authorId then finish("error", "暂时无法识别当前玩家", "missing_user"); return false end
    if authorId == cleanTarget.ownerId then
        finish("error", "不能给自己的空岛留言", "self_message")
        return false
    end
    local activityKey = IslandGuestbook.ActivityKey(cleanTarget)

    local readSettled
    readSettled = Once(function(values, failed, code, reason)
        if failed then
            finish("error", "留言记录读取失败：" .. tostring(reason or code or "未知错误"), code or "read_failed")
            return
        end
        local existing = type(values) == "table" and values[IslandGuestbook.OUTBOX_KEY] or nil
        local items = NormalizeOutbox(existing)
        local targetKey = cleanTarget.ownerId .. "\31" .. cleanTarget.islandId
        local nextItems = {}
        for _, item in ipairs(items) do
            local itemKey = item.targetOwnerId .. "\31" .. item.targetIslandId
            if itemKey ~= targetKey then nextItems[#nextItems + 1] = item end
        end
        local record = {
            targetOwnerId = cleanTarget.ownerId,
            targetIslandId = cleanTarget.islandId,
            text = cleanText,
            createdAt = Timestamp(),
        }
        nextItems[#nextItems + 1] = record
        nextItems = NormalizeOutbox(nextItems)
        local payload = { schema = IslandGuestbook.OUTBOX_SCHEMA, items = nextItems }
        local retainedTargets, evictedTargets = {}, {}
        for _, item in ipairs(nextItems) do
            retainedTargets[item.targetOwnerId .. "\31" .. item.targetIslandId] = true
        end
        for _, item in ipairs(items) do
            local itemKey = item.targetOwnerId .. "\31" .. item.targetIslandId
            if itemKey ~= targetKey and not retainedTargets[itemKey] then
                evictedTargets[#evictedTargets + 1] = item
            end
        end

        local saveSettled = Once(function(success, saveCode, saveReason)
            if success then finish("ok", Copy(record), "cloud")
            else
                finish("error", "留言保存失败："
                    .. tostring(saveReason or saveCode or "未知错误"), saveCode or "save_failed")
            end
        end)
        local started, startError = pcall(function()
            local batch = cloud:BatchSet()
                :Set(IslandGuestbook.OUTBOX_KEY, payload)
                :SetInt(activityKey, record.createdAt)
            -- A bounded outbox can evict an old island. Clear that island's
            -- ranking score in the same atomic write so stale authors cannot
            -- occupy its top-100 window without a matching message payload.
            for _, evicted in ipairs(evictedTargets) do
                batch:SetInt(IslandGuestbook.ActivityKey(evicted), 0)
            end
            batch:Save("空岛留言", {
                    ok = function() saveSettled(true) end,
                    error = function(saveCode, saveReason)
                        saveSettled(false, saveCode, saveReason)
                    end,
                    timeout = function() saveSettled(false, "timeout", "请求超时") end,
                })
        end)
        if not started then saveSettled(false, "start_failed", startError) end
    end)

    local started, startError = pcall(function()
        cloud:Get(IslandGuestbook.OUTBOX_KEY, {
            ok = function(values) readSettled(values, false) end,
            error = function(code, reason) readSettled(nil, true, code, reason) end,
            timeout = function() readSettled(nil, true, "timeout", "请求超时") end,
        })
    end)
    if not started then
        readSettled(nil, true, "start_failed", startError)
        return false
    end
    return true
end

local function ExtractRankOutbox(item)
    if type(item) ~= "table" then return {} end
    for _, container in ipairs({ item.score, item.values, item.value, item }) do
        local payload = ExtractValue(container)
        if payload then return NormalizeOutbox(payload) end
    end
    return {}
end

function IslandGuestbook.Load(target, callbacks)
    local cleanTarget = NormalizeTarget(target)
    local finish = Once(function(name, ...)
        Dispatch(callbacks, name, ...)
    end)
    if not cleanTarget then finish("error", "留言目标无效", "invalid_target"); return false end
    local cloud = GetCloud(false)
    if not cloud then finish("error", "留言功能暂不可用", "offline"); return false end
    local activityKey = IslandGuestbook.ActivityKey(cleanTarget)

    local rankSettled
    rankSettled = Once(function(rankList, failed, code, reason)
        if failed then
            finish("error", "留言板读取失败：" .. tostring(reason or code or "未知错误"), code or "read_failed")
            return
        end

        local messages, authorIds, seenAuthors = {}, {}, {}
        for rankIndex, item in ipairs(type(rankList) == "table" and rankList or {}) do
            if rankIndex > IslandGuestbook.RANK_PAGE_SIZE then break end
            if #messages >= IslandGuestbook.MAX_MESSAGES then break end
            local rawAuthorId = UserProfileService.ExtractUserId(item)
            local authorId = UserProfileService.UserKey(rawAuthorId)
            if authorId and not seenAuthors[authorId] then
                local newest
                for _, source in ipairs(ExtractRankOutbox(item)) do
                    if source.targetOwnerId == cleanTarget.ownerId
                        and source.targetIslandId == cleanTarget.islandId
                        and (not newest or source.createdAt >= newest.createdAt) then
                        newest = source
                    end
                end
                if newest then
                    -- The author is always taken from the ranking envelope,
                    -- never from mutable data in the visitor's outbox.
                    seenAuthors[authorId] = true
                    authorIds[#authorIds + 1] = rawAuthorId
                    messages[#messages + 1] = {
                        authorId = authorId,
                        nickname = UserProfileService.FallbackNickname(authorId),
                        text = newest.text,
                        createdAt = newest.createdAt,
                        isMe = authorId == UserProfileService.CurrentUserId(),
                    }
                end
            end
        end
        table.sort(messages, function(first, second)
            if first.createdAt ~= second.createdAt then return first.createdAt > second.createdAt end
            return first.authorId < second.authorId
        end)

        UserProfileService.Resolve(authorIds, {
            ok = function(profiles, _, identitySource)
                for _, message in ipairs(messages) do
                    local profile = profiles[UserProfileService.UserKey(message.authorId)]
                    if profile then
                        message.nickname = profile.nickname
                        message.avatar = Copy(profile.avatar)
                    else
                        message.avatar = UserProfileService.BuildAvatar(message.nickname)
                    end
                end
                finish("ok", messages, "cloud", identitySource)
            end,
        })
    end)

    local started, startError = pcall(function()
        cloud:GetRankList(activityKey, 0, IslandGuestbook.RANK_PAGE_SIZE, {
            ok = function(rankList) rankSettled(rankList, false) end,
            error = function(code, reason) rankSettled(nil, true, code, reason) end,
            timeout = function() rankSettled(nil, true, "timeout", "请求超时") end,
        }, IslandGuestbook.OUTBOX_KEY)
    end)
    if not started then
        rankSettled(nil, true, "start_failed", startError)
        return false
    end
    return true
end

IslandGuestbook.NormalizeOutbox = NormalizeOutbox
IslandGuestbook.Copy = Copy

return IslandGuestbook
