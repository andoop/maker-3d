package.path = "scripts/?.lua;" .. package.path

FILE_WRITE, FILE_READ = 1, 2

local files, encoded, sequence, writeCount = {}, {}, 0, 0

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
end

cjson = {
    encode = function(value)
        sequence = sequence + 1
        local key = "json:" .. tostring(sequence)
        encoded[key] = Copy(value)
        return key
    end,
    decode = function(value)
        assert(encoded[value], "unknown encoded value: " .. tostring(value))
        return Copy(encoded[value])
    end,
}

fileSystem = {
    CreateDir = function() return true end,
    FileExists = function(_, path) return files[path] ~= nil end,
}

File = function(path, mode)
    local object = {}
    function object:IsOpen() return true end
    function object:WriteString(value)
        writeCount = writeCount + 1
        files[path] = value
    end
    function object:ReadString() return files[path] end
    function object:Close() end
    return object
end

local BuilderStorage = require("BuilderStorage")
local island = { schema = "island-project/v2", instances = { { id = 1, assetId = "builtin:adventure:meadow-cottage" } } }
local library = { schema = "model-library/v1", items = { { assetId = "user:1:model" } } }

clientCloud = nil
local islandSource, librarySource
assert(BuilderStorage.SaveIsland(island, { ok = function(source) islandSource = source end }))
assert(BuilderStorage.SaveModelLibrary(library, { ok = function(source) librarySource = source end }))
assert(islandSource == "local" and librarySource == "local", "offline saves must use local storage")
local legacySerializations, legacyWrites = sequence, writeCount
assert(BuilderStorage.SaveIsland(island))
assert(sequence == legacySerializations + 1 and writeCount == legacyWrites + 1,
    "unversioned legacy snapshots must never be suppressed by the identity cache")

local loaded
BuilderStorage.LoadWorkspace(function(payload) loaded = payload end)
assert(loaded and loaded.source == "local", "offline workspace source")
assert(loaded.island.instances[1].assetId == "builtin:adventure:meadow-cottage", "offline island roundtrip")
assert(loaded.library.items[1].assetId == "user:1:model", "offline library roundtrip")

local islands = {
    schema = "island-collection/v1", revision = 1, updatedAt = 10, activeId = "island-a",
    items = { { schema = "island-project/v2", islandId = "island-a", name = "A岛", instances = island.instances } },
}
assert(BuilderStorage.SaveIsland(islands))
local unchangedSerializations, unchangedWrites = sequence, writeCount
assert(BuilderStorage.SaveIsland(islands))
assert(sequence == unchangedSerializations and writeCount == unchangedWrites,
    "an unchanged versioned snapshot must reuse its successful local persistence")

islands.items[1].name = "真正修改后的空岛"
islands.revision, islands.updatedAt = 2, 11
assert(BuilderStorage.SaveIsland(islands))
assert(sequence == unchangedSerializations + 1 and writeCount == unchangedWrites + 1,
    "a revisioned content edit must still serialize and write")

-- Market sync completion currently changes this top-level flag without
-- advancing the collection revision. The identity fast path must still persist
-- it so a restart cannot resurrect an already-completed cloud retry.
local syncSerializations, syncWrites = sequence, writeCount
islands.marketSyncPending = true
assert(BuilderStorage.SaveIsland(islands))
assert(sequence == syncSerializations + 1 and writeCount == syncWrites + 1,
    "a same-revision sync-state change must not be skipped")
syncSerializations, syncWrites = sequence, writeCount
islands.marketSyncPending = false
assert(BuilderStorage.SaveIsland(islands))
assert(sequence == syncSerializations + 1 and writeCount == syncWrites + 1,
    "same-revision cloud-sync completion must be persisted locally")
loaded = nil
BuilderStorage.LoadWorkspace(function(payload) loaded = payload end)
assert(loaded.island.schema == "island-collection/v1" and loaded.island.activeId == "island-a",
    "multi-island collection roundtrip")

-- A cloud failure after a successful local write is a degraded success, not a
-- total save failure.
local cloudSaveAttempts = 0
clientCloud = {
    Get = function() end,
    Set = function(_, _, _, events)
        cloudSaveAttempts = cloudSaveAttempts + 1
        events.error(-1, "offline")
    end,
}
local fallbackSource, fallbackError
local retrySerializations, retryWrites = sequence, writeCount
assert(BuilderStorage.SaveIsland(islands, {
    ok = function(source, warning) fallbackSource, fallbackError = source, warning end,
    error = function(message) error("local fallback incorrectly failed: " .. tostring(message)) end,
}))
assert(fallbackSource == "local" and tostring(fallbackError):find("offline"), "cloud failure must report local fallback")
assert(BuilderStorage.SaveIsland(islands))
assert(sequence == retrySerializations and writeCount == retryWrites and cloudSaveAttempts == 2,
    "unchanged local persistence may be skipped, but a failed cloud save must retry")

-- Cloud workspace values override local values when the batch read succeeds.
local cloudIsland = { schema = "island-project/v2", revision = 2, updatedAt = 20, instances = { { id = 9, assetId = "builtin:adventure:highland-watch" } } }
local cloudLibrary = { schema = "model-library/v1", revision = 2, updatedAt = 20, items = { { assetId = "user:9:cloud-model" } } }
local cloudClient = {
    Get = function() end,
    Set = function() end,
    BatchGet = function()
        local builder = { keys = {} }
        function builder:Key(key) self.keys[#self.keys + 1] = key; return self end
        function builder:Fetch(events)
            events.ok({
                island3d_island_v2 = cloudIsland,
                island3d_model_library_v2 = cloudLibrary,
            }, {})
        end
        return builder
    end,
}
clientCloud = cloudClient
loaded = nil
BuilderStorage.LoadWorkspace(function(payload) loaded = payload end)
assert(loaded and loaded.source == "cloud", "cloud workspace source")
assert(loaded.islandSource == "cloud" and loaded.librarySource == "cloud", "per-resource cloud source")
assert(loaded.island.instances[1].id == 9, "cloud island wins")
assert(loaded.library.items[1].assetId == "user:9:cloud-model", "cloud library wins")

-- If the last cloud save failed, a newer local revision must not be replaced by
-- the older cloud copy on the next startup.
clientCloud = nil
local newerLocalIsland = { schema = "island-project/v2", revision = 7, updatedAt = 70,
    instances = { { id = 77, assetId = "builtin:adventure:lotus-pond" } } }
assert(BuilderStorage.SaveIsland(newerLocalIsland))
clientCloud = cloudClient
loaded = nil
BuilderStorage.LoadWorkspace(function(payload) loaded = payload end)
assert(loaded and loaded.islandSource == "local", "newer local island source")
assert(loaded.island.instances[1].id == 77, "newer local island wins over stale cloud")

clientCloud = nil
local newerLocalLibrary = {
    schema = "model-library/v1", revision = 8, updatedAt = 80,
    marketSyncPending = true,
    items = { { assetId = "user:77:offline-model" } },
}
assert(BuilderStorage.SaveModelLibrary(newerLocalLibrary))
clientCloud = cloudClient
loaded = nil
BuilderStorage.LoadWorkspace(function(payload) loaded = payload end)
assert(loaded and loaded.librarySource == "local", "newer local model library source")
assert(loaded.library.items[1].assetId == "user:77:offline-model", "newer local model library wins over stale cloud")
assert(loaded.library.marketSyncPending == true, "pending market sync survives local conflict resolution")

-- A broken/weak network may never invoke any SDK callback. The frame-driven
-- watchdog must still unblock startup with the local snapshot, and a late
-- callback must not replace data after the fallback has completed.
local hangingEvents
clientCloud = {
    Get = function() end,
    Set = function() end,
    BatchGet = function()
        local builder = {}
        function builder:Key() return self end
        function builder:Fetch(events) hangingEvents = events end
        return builder
    end,
}
loaded = nil
BuilderStorage.LoadWorkspace(function(payload) loaded = payload end)
assert(loaded == nil, "the watchdog should not pre-empt a healthy short request")
BuilderStorage.Update(BuilderStorage.WORKSPACE_WATCHDOG_SECONDS - 0.01)
assert(loaded == nil, "the workspace request should retain its full deadline")
BuilderStorage.Update(0.02)
assert(loaded and loaded.source == "local" and tostring(loaded.error):find("本地工作区"),
    "a missing cloud callback must fall back locally instead of trapping startup")
local watchdogPayload = loaded
hangingEvents.ok({ island3d_island_v2 = cloudIsland })
assert(loaded == watchdogPayload, "late cloud completion must not race the watchdog result")
BuilderStorage.ResetPendingLoads()

print("storage-spec: ok")
