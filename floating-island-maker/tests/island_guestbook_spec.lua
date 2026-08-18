package.path = "scripts/?.lua;" .. package.path

local UserProfileService = require("UserProfileService")
local IslandGuestbook = require("IslandGuestbook")

local originalLookup, originalCloud = GetUserNickname, clientCloud
local target = { ownerId = "owner-7", islandId = "island-a", name = "风铃空岛" }
assert(IslandGuestbook.ActivityKey(target)
        == "island3d_guestbook_activity_v2_1967027423_1436318100",
    "activity keys must remain deterministic across client runtimes")

local longText = "\1  你好\n" .. string.rep("界", 90) .. "\127"
local sanitized = IslandGuestbook.SanitizeText(longText)
assert(utf8.len(sanitized) == 80 and not sanitized:find("\n", 1, true)
    and not sanitized:find("\1", 1, true),
    "guestbook text must remove controls and truncate at 80 UTF-8 characters")
assert(IslandGuestbook.SanitizeText("坏\255字") == "坏字",
    "malformed UTF-8 bytes must be dropped safely")

local oldItems = {
    { targetOwnerId = "elsewhere", targetIslandId = "island-z", text = "保留", createdAt = 3 },
    { targetOwnerId = target.ownerId, targetIslandId = target.islandId,
        text = "旧留言", createdAt = 2, authorId = "spoofed" },
}
local savedPayload, savedActivity, savedActivityKey, saveDescription
clientCloud = {
    userId = 99,
    GetRankList = function() end,
    Get = function(_, key, events)
        assert(key == IslandGuestbook.OUTBOX_KEY)
        events.ok({ [key] = { schema = IslandGuestbook.OUTBOX_SCHEMA, items = oldItems } })
        events.error(-9, "duplicate callback")
    end,
    BatchSet = function()
        local builder = {}
        function builder:Set(key, value)
            assert(key == IslandGuestbook.OUTBOX_KEY); savedPayload = value; return self
        end
        function builder:SetInt(key, value)
            savedActivityKey, savedActivity = key, value; return self
        end
        function builder:Save(description, events)
            saveDescription = description
            events.ok()
            events.error(-8, "duplicate callback")
        end
        return builder
    end,
}
local postOk, postError = 0, 0
assert(IslandGuestbook.Post(target, longText, {
    ok = function(record, source)
        postOk = postOk + 1
        assert(source == "cloud" and record.targetOwnerId == target.ownerId)
    end,
    error = function() postError = postError + 1 end,
}))
assert(postOk == 1 and postError == 0 and saveDescription == "空岛留言"
    and savedActivityKey == IslandGuestbook.ActivityKey(target)
    and savedActivity == savedPayload.items[1].createdAt,
    "posting must commit the outbox and activity score and settle once")
assert(#savedPayload.items == 2 and savedPayload.items[1].text == sanitized,
    "posting upserts the target's one message while preserving other targets")
assert(savedPayload.items[1].authorId == nil,
    "outbox payloads do not carry a trusted-looking author identity")

local fullOutbox, scoreWrites = {}, {}
for index = 1, IslandGuestbook.MAX_OUTBOX_ENTRIES do
    fullOutbox[index] = {
        targetOwnerId = "archive-owner", targetIslandId = "archive-" .. index,
        text = "旧留言", createdAt = index,
    }
end
clientCloud = {
    userId = 99,
    GetRankList = function() end,
    Get = function(_, key, events) events.ok({ [key] = { items = fullOutbox } }) end,
    BatchSet = function()
        local builder = {}
        function builder:Set() return self end
        function builder:SetInt(key, value) scoreWrites[key] = value; return self end
        function builder:Save(_, events) events.ok() end
        return builder
    end,
}
local newestTarget = { ownerId = "owner-8", islandId = "new-island" }
assert(IslandGuestbook.Post(newestTarget, "新的留言", { ok = function() end }))
assert((scoreWrites[IslandGuestbook.ActivityKey(newestTarget)] or 0) > 0
    and scoreWrites[IslandGuestbook.ActivityKey({
        ownerId = "archive-owner", islandId = "archive-1" })] == 0,
    "evicting an old outbox message must clear its stale island activity score")

local many = {}
for index = 1, IslandGuestbook.MAX_OUTBOX_ENTRIES + 5 do
    many[index] = {
        targetOwnerId = "owner", targetIslandId = "island-" .. index,
        text = "留言" .. index, createdAt = index,
    }
end
local bounded = IslandGuestbook.NormalizeOutbox(many)
assert(#bounded == IslandGuestbook.MAX_OUTBOX_ENTRIES
    and bounded[1].createdAt == IslandGuestbook.MAX_OUTBOX_ENTRIES + 5,
    "visitor outboxes must retain only a bounded newest set")
local hostile = {}
for index = 1, IslandGuestbook.MAX_OUTBOX_INPUT_ENTRIES + 1 do
    hostile[index] = {
        targetOwnerId = "owner", targetIslandId = "hostile-" .. index,
        text = "留言", createdAt = index,
    }
end
assert(IslandGuestbook.NormalizeOutbox(hostile)[1].createdAt
        == IslandGuestbook.MAX_OUTBOX_INPUT_ENTRIES,
    "normalization must cap work even if a malformed cloud payload is oversized")

UserProfileService.ResetCache()
GetUserNickname = function(options)
    local results = {}
    for _, userId in ipairs(options.userIds) do
        results[#results + 1] = { userId = userId, nickname = "岛友" .. tostring(userId) }
    end
    options.onSuccess(results)
end
local rankCall
clientCloud = {
    userId = "22",
    GetRankList = function(_, key, start, count, events, extraKey)
        rankCall = { key, start, count, extraKey }
        events.ok({
            {
                userId = 11,
                score = { [IslandGuestbook.OUTBOX_KEY] = { items = {
                    { targetOwnerId = target.ownerId, targetIslandId = target.islandId,
                        text = "第一条", createdAt = 8, authorId = "evil" },
                    { targetOwnerId = target.ownerId, targetIslandId = target.islandId,
                        text = "更新后", createdAt = 12 },
                } } },
            },
            {
                userId = 22,
                score = { [IslandGuestbook.OUTBOX_KEY] = { items = {
                    { targetOwnerId = target.ownerId, targetIslandId = target.islandId,
                        text = "我也来过", createdAt = 20, authorId = "evil-2" },
                } } },
            },
            {
                userId = 33,
                score = { [IslandGuestbook.OUTBOX_KEY] = { items = {
                    { targetOwnerId = "other-owner", targetIslandId = target.islandId,
                        text = "不属于这里", createdAt = 99 },
                } } },
            },
        })
        events.error(-1, "duplicate rank callback")
    end,
}
local loadOk, loadError, loaded = 0, 0
assert(IslandGuestbook.Load(target, {
    ok = function(messages, source)
        loadOk, loaded = loadOk + 1, messages
        assert(source == "cloud")
    end,
    error = function() loadError = loadError + 1 end,
}))
assert(rankCall[1] == IslandGuestbook.ActivityKey(target) and rankCall[2] == 0
    and rankCall[3] == IslandGuestbook.RANK_PAGE_SIZE
    and rankCall[4] == IslandGuestbook.OUTBOX_KEY,
    "guestbook reads the activity ranking with the outbox as an extra field")
assert(IslandGuestbook.ActivityKey(target) ~= IslandGuestbook.ActivityKey({
        ownerId = target.ownerId, islandId = "island-b" }),
    "each island must have an independent activity ranking")
assert(loadOk == 1 and loadError == 0 and #loaded == 2,
    "loading filters the requested island and settles exactly once")
assert(loaded[1].authorId == "22" and loaded[1].isMe and loaded[1].nickname == "岛友22"
    and loaded[2].authorId == "11" and loaded[2].text == "更新后",
    "messages are newest-first, resolve nicknames, and trust rank userId over payload authorId")
assert(loaded[1].avatar and loaded[1].avatar.src == nil,
    "guestbook avatars use generated initials rather than a fictional account avatar API")

clientCloud = nil
local offlineCount = 0
assert(not IslandGuestbook.Load(target, {
    error = function(message, code)
        offlineCount = offlineCount + 1
        assert(code == "offline" and message:find("暂不可用", 1, true))
    end,
}))
assert(offlineCount == 1, "offline reads must fail once without throwing")

clientCloud = { userId = target.ownerId, Get = function() end, GetRankList = function() end,
    BatchSet = function() end }
local selfCount = 0
assert(not IslandGuestbook.Post(target, "给自己留言", {
    error = function(_, code) selfCount = selfCount + 1; assert(code == "self_message") end,
}))
assert(selfCount == 1, "owners cannot create visitor messages on their own guestbook")

GetUserNickname, clientCloud = originalLookup, originalCloud
UserProfileService.ResetCache()

print("island-guestbook-spec: ok")
