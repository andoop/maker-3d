package.path = "scripts/?.lua;" .. package.path

local UserProfileService = require("UserProfileService")

local originalLookup, originalCloud = GetUserNickname, clientCloud

local ids = {}
for index = 1, 205 do ids[index] = index end
local calls, active, maxActive = {}, 0, 0
GetUserNickname = function(options)
    active = active + 1
    maxActive = math.max(maxActive, active)
    calls[#calls + 1] = #options.userIds
    local results = {}
    for _, userId in ipairs(options.userIds) do
        if userId % 2 == 0 then results[#results + 1] = { userId = userId, nickname = "昵称" .. userId } end
    end
    active = active - 1
    options.onSuccess(results)
end

UserProfileService.ResetCache()
local completionCount, resolved, ordered, source = 0
assert(UserProfileService.Resolve(ids, { ok = function(byId, profiles, resultSource)
    completionCount, resolved, ordered, source = completionCount + 1, byId, profiles, resultSource
end }))
assert(table.concat(calls, ",") == "100,100,5" and maxActive == 1,
    "nickname lookup must use serial batches of at most 100 users")
assert(completionCount == 1 and #ordered == 205 and source == "account",
    "a complete batched lookup must settle exactly once")
assert(resolved["2"].nickname == "昵称2" and resolved["1"].nickname == "玩家 1"
    and resolved[2] == nil,
    "identity maps must use string keys and retain fallback names for omitted records")

UserProfileService.ResetCache()
local secondCalls, partialCompletion = 0, 0
GetUserNickname = function(options)
    secondCalls = secondCalls + 1
    if secondCalls == 1 then
        options.onSuccess({ { userId = options.userIds[1], nickname = "第一批" } })
        options.onError(-2)
    else
        error("lookup startup failed")
    end
end
local partial
assert(UserProfileService.Resolve(ids, { ok = function(byId, _, resultSource)
    partialCompletion, partial, source = partialCompletion + 1, byId, resultSource
end }))
assert(secondCalls == 3 and partialCompletion == 1 and source == "partial",
    "duplicate callbacks and thrown batches must still advance and complete only once")
assert(partial["1"].nickname == "第一批" and partial["101"].nickname == "玩家 101",
    "failed nickname batches keep useful fallback profiles")

UserProfileService.ResetCache()
GetUserNickname = nil
local delayedCount, delayedSource, delayedProfile = 0
assert(UserProfileService.Resolve({ "88", 88, nil }, { ok = function(byId, list, resultSource)
    delayedCount, delayedSource = delayedCount + 1, resultSource
    delayedProfile = byId["88"]
    assert(#list == 1)
end }))
assert(delayedCount == 0, "an early missing bridge must wait instead of freezing a fallback name")
GetUserNickname = function(options)
    options.onSuccess({ { userId = options.userIds[1], nickname = "稍后就绪昵称" } })
end
UserProfileService.Update(0.61)
assert(delayedCount == 1 and delayedSource == "account"
    and delayedProfile.nickname == "稍后就绪昵称",
    "an account bridge that appears after startup must resolve without reopening the panel")

UserProfileService.ResetCache()
local warmupCalls, warmupProfile = 0, nil
GetUserNickname = function(options)
    warmupCalls = warmupCalls + 1
    if warmupCalls == 1 then options.onError(-1)
    else options.onSuccess({ { userId = options.userIds[1], nickname = "大厅就绪昵称" } }) end
end
assert(UserProfileService.Resolve({ 66 }, {
    ok = function(byId) warmupProfile = byId["66"] end,
}))
assert(warmupProfile == nil and warmupCalls == 1,
    "Maker -1 must keep the identity request pending while the lobby bridge warms up")
UserProfileService.Update(0.59)
assert(warmupCalls == 1 and warmupProfile == nil, "startup retry must respect its delay")
UserProfileService.Update(0.02)
assert(warmupCalls == 2 and warmupProfile.nickname == "大厅就绪昵称",
    "a transient Maker -1 must automatically recover to the real nickname")
local warmupDiagnostic = UserProfileService.GetLastDiagnostic()
assert(warmupDiagnostic.status == "account" and warmupDiagnostic.resolved == 1
    and warmupDiagnostic.attempts == 2,
    "nickname diagnostics must expose a recovered startup retry")

UserProfileService.ResetCache()
local emptyCalls, emptyProfile, emptySource = 0, nil, nil
GetUserNickname = function(options)
    emptyCalls = emptyCalls + 1
    options.onSuccess({})
end
assert(UserProfileService.Resolve({ 67 }, { ok = function(byId, _, resultSource)
    emptyProfile, emptySource = byId["67"], resultSource
end }))
for _ = 1, 43 do UserProfileService.Update(0.1) end
assert(emptyCalls == 4 and emptyProfile.nickname == "玩家 67" and emptySource == "partial",
    "a persistently empty account response must stop retrying and report a partial fallback")

UserProfileService.ResetCache()
local stalledOptions, timeoutCount, timeoutSource
GetUserNickname = function(options) stalledOptions = options end
assert(UserProfileService.Resolve({ 77 }, { ok = function(byId, _, resultSource)
    timeoutCount, timeoutSource = (timeoutCount or 0) + 1, resultSource
    assert(byId["77"].nickname == "玩家 77")
end }))
for _ = 1, 349 do UserProfileService.Update(0.1) end
assert(timeoutCount == nil, "a live nickname request must keep waiting before its deadline")
UserProfileService.Update(0.2)
assert(timeoutCount == 1 and timeoutSource == "partial",
    "a stalled account callback must finish with a fallback profile after the timeout")
stalledOptions.onSuccess({ { userId = 77, nickname = "迟到昵称" } })
assert(timeoutCount == 1, "a late account callback must not complete a timed-out request twice")

clientCloud = { userId = 42 }
assert(UserProfileService.CurrentUserId() == "42", "current identity is normalized to a string key")
local avatarA = UserProfileService.BuildAvatar("云朵旅人")
local avatarB = UserProfileService.BuildAvatar("云朵旅人")
assert(avatarA.initials == "云" and avatarA.src == nil and avatarA.name == "云朵旅人",
    "avatar props use the nickname's first character and never invent an image URL")
assert(table.concat(avatarA.backgroundColor, ",") == table.concat(avatarB.backgroundColor, ","),
    "the same nickname must always receive the same avatar colour")

GetUserNickname, clientCloud = originalLookup, originalCloud
UserProfileService.ResetCache()

print("user-profile-service-spec: ok")
