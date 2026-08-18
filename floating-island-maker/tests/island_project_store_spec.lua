package.path = "scripts/?.lua;" .. package.path

local Store = require("IslandProjectStore")
local IslandLayout = require("IslandLayout")
local TerrainCatalog = require("IslandTerrainCatalog")

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
end

local terrainList = TerrainCatalog.List()
assert(#terrainList >= 2, "terrain persistence tests require the authored terrain choices")
local alternateTerrainId = terrainList[2].id
local alternateTerrain = assert(TerrainCatalog.Get(alternateTerrainId))
local alternateCamera = alternateTerrain.camera or alternateTerrain.defaultCamera or {}
local alternateTarget = alternateCamera.target or {}

local legacy = {
    schema = "island-project/v2", revision = 4, updatedAt = 40, name = "旧空岛",
    instances = { { id = 1, assetId = "builtin:adventure:meadow-cottage" } },
}
local collection = Store.Normalize(legacy, nil, 100)
assert(collection.schema == Store.SCHEMA, "legacy save must migrate to a collection")
assert(#collection.items == 1 and Store.GetActive(collection).name == "旧空岛", "legacy island content survives migration")
assert(Store.GetActive(collection).terrainId == TerrainCatalog.DEFAULT_ID
    and Store.GetActive(collection).terrain.preset == TerrainCatalog.DEFAULT_ID,
    "legacy saves without terrain metadata use the current three-island terrain")
local interactionCollection = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "saved",
    exploreFavorites = { ["sample:town"] = true, ignored = false },
    exploreLikes = { ["sample:nature"] = true },
    items = { { islandId = "saved", name = "收藏测试", instances = {} } },
}, nil, 101)
assert(interactionCollection.exploreFavorites["sample:town"] == true
    and interactionCollection.exploreFavorites.ignored == nil
    and interactionCollection.exploreLikes["sample:nature"] == true,
    "exploration favorites and likes survive normalized workspace persistence")

local explicitUnlocks = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "unlock-map",
    rewardUnlocks = {
        ["terrain:" .. alternateTerrainId] = true,
        ignoredFalse = false,
        ignoredString = "true",
        [42] = true,
    },
    items = { { islandId = "unlock-map", name = "解锁记录", instances = {} } },
}, nil, 102)
assert(explicitUnlocks.rewardUnlocks["terrain:" .. alternateTerrainId] == true
    and explicitUnlocks.rewardUnlocks["42"] == true
    and explicitUnlocks.rewardUnlocks.ignoredFalse == nil
    and explicitUnlocks.rewardUnlocks.ignoredString == nil,
    "reward unlock persistence keeps only explicit true flags and canonical string keys")
local unlockRevision = explicitUnlocks.revision
local unlocked, changed = Store.UnlockReward(explicitUnlocks, "terrain:another", 103)
assert(unlocked and changed and Store.IsRewardUnlocked(explicitUnlocks, "terrain:another")
    and explicitUnlocks.revision == unlockRevision + 1 and explicitUnlocks.updatedAt == 103,
    "unlocking a reward persists it and touches the collection exactly once")
local unlockedAgain, changedAgain = Store.UnlockReward(explicitUnlocks, "terrain:another", 104)
assert(unlockedAgain and changedAgain == false and explicitUnlocks.revision == unlockRevision + 1
    and explicitUnlocks.updatedAt == 103,
    "unlocking an already granted reward is idempotent and does not touch persistence metadata")
local reloadedUnlocks = Store.Normalize(explicitUnlocks, nil, 105)
assert(Store.IsRewardUnlocked(reloadedUnlocks, "terrain:another"),
    "reward unlocks survive collection normalization and reload")
assert(not Store.IsRewardUnlocked(reloadedUnlocks, "")
    and not Store.UnlockReward(reloadedUnlocks, "   ", 106),
    "empty reward keys are rejected rather than polluting the persisted map")

local uiDismissals = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "ui-dismissals",
    uiDismissals = {
        ["terrain-picker-intro/v1"] = true,
        ignoredFalse = false,
        ignoredString = "true",
    },
    items = { { islandId = "ui-dismissals", name = "提示记录", instances = {} } },
}, nil, 106.1)
assert(Store.IsUIDismissed(uiDismissals, "terrain-picker-intro/v1")
    and not Store.IsUIDismissed(uiDismissals, "ignoredFalse")
    and not Store.IsUIDismissed(uiDismissals, "ignoredString"),
    "UI dismissals keep only explicit true flags during normalization")
local uiDismissalRevision = uiDismissals.revision
local dismissed, dismissalChanged = Store.DismissUI(
    uiDismissals, "terrain-picker-intro/v2", 106.2)
assert(dismissed and dismissalChanged
    and Store.IsUIDismissed(uiDismissals, "terrain-picker-intro/v2")
    and uiDismissals.revision == uiDismissalRevision + 1,
    "dismissing a UI hint persists it and touches the collection exactly once")
local dismissedAgain, dismissalChangedAgain = Store.DismissUI(
    uiDismissals, "terrain-picker-intro/v2", 106.3)
assert(dismissedAgain and dismissalChangedAgain == false
    and uiDismissals.revision == uiDismissalRevision + 1,
    "dismissing an already hidden UI hint is idempotent")
assert(Store.IsUIDismissed(Store.Normalize(uiDismissals, nil, 106.4),
        "terrain-picker-intro/v2")
    and not Store.DismissUI(uiDismissals, "   ", 106.5),
    "UI dismissals survive reload and reject empty keys")

local grandfatheredTerrain = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "legacy-terrain",
    items = { {
        islandId = "legacy-terrain", name = "旧版地形空岛", terrainId = alternateTerrainId,
        instances = {},
    } },
}, nil, 107)
assert(Store.IsRewardUnlocked(grandfatheredTerrain, "terrain:" .. alternateTerrainId),
    "old collections grandfather every non-default terrain already referenced by an island")
local grandfatheredLegacyProject = Store.Normalize({
    schema = "island-project/v2", name = "更早版本空岛", terrainId = alternateTerrainId,
    instances = {},
}, nil, 107.5)
assert(Store.IsRewardUnlocked(grandfatheredLegacyProject, "terrain:" .. alternateTerrainId),
    "single-project legacy saves receive the same in-use terrain grandfathering")
local explicitLockedTerrain = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "explicit-lock",
    rewardUnlocks = {},
    items = { {
        islandId = "explicit-lock", name = "显式锁定", terrainId = alternateTerrainId,
        instances = {},
    } },
}, nil, 108)
assert(not Store.IsRewardUnlocked(explicitLockedTerrain, "terrain:" .. alternateTerrainId),
    "an explicit reward unlock map is respected and never receives grandfathered flags")
local defaultWithoutUnlock = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "default-terrain",
    items = { {
        islandId = "default-terrain", name = "经典三岛", terrainId = TerrainCatalog.DEFAULT_ID,
        instances = {},
    } },
}, nil, 108.5)
assert(not Store.IsRewardUnlocked(defaultWithoutUnlock, "terrain:" .. TerrainCatalog.DEFAULT_ID),
    "the store records grants only and does not encode the product policy that the default terrain is free")

local renamedDefault = Store.Normalize({
    schema = "island-project/v2", revision = 0, updatedAt = 1, name = "我的" .. "海" .. "岛", instances = {},
}, nil, 1)
assert(Store.GetActive(renamedDefault).name == "我的空岛",
    "the legacy generated default name must migrate to the new empty-island terminology")

local defaultCollection = Store.Normalize(nil, nil, 109)
local defaultCreated = Store.Create(defaultCollection, "默认地形", 110)
assert(defaultCreated.terrainId == TerrainCatalog.DEFAULT_ID,
    "new islands default to the current three-island terrain")

local second = Store.Create(collection, "第二座空岛", 110, alternateTerrainId)
assert(#collection.items == 2 and collection.activeId == second.islandId, "create activates a distinct island")
assert(#second.instances == 0, "new island starts empty")
assert(second.terrainId == alternateTerrainId and second.terrain.preset == alternateTerrainId,
    "new island persists its selected terrain in both the business and compatibility fields")
assert(second.environment.timeOfDay == 9.5 and second.environment.autoTime == true,
    "new islands must start with a bright automatic day/night cycle")
assert(second.camera.radius == (alternateCamera.radius or (alternateTerrain.overview or {}).radius or 118)
    and second.camera.target[1] == (alternateTarget[1] or alternateTarget.x or (alternateTerrain.overview or {}).x or 0)
    and second.camera.target[3] == (alternateTarget[3] or alternateTarget.z or (alternateTerrain.overview or {}).z or 7),
    "new world camera opens on its selected terrain overview")

local oldTriple = Store.Normalize({
    schema = Store.SCHEMA, activeId = "old", items = { {
        islandId = "old", name = "旧三岛", instances = { { id = 1, x = -22, z = 12 } },
        terrain = { preset = "storybook-triple-archipelago", groundY = 0.42 },
        camera = { radius = 61, target = { 0, -1, 3.5 } },
    } },
}, nil, 115)
local migrated = Store.GetActive(oldTriple)
assert(migrated.terrain.preset == IslandLayout.TERRAIN_PRESET
    and migrated.terrainId == TerrainCatalog.DEFAULT_ID
    and migrated.instances[1].x == -44 and migrated.instances[1].z == 24,
    "old three-island models migrate to the doubled island centres")
assert(migrated.camera.radius == 122 and migrated.camera.target[3] == 7,
    "old three-island camera migrates exactly once")
local migratedTwice = Store.GetActive(Store.Normalize(oldTriple, nil, 116))
assert(migratedTwice.instances[1].x == -44 and migratedTwice.instances[1].z == 24,
    "old three-island coordinates migrate exactly once")
local topLevelLegacy = Store.GetActive(Store.Normalize({
    schema = "island-project/v2", terrainId = "storybook-triple-archipelago",
    instances = { { id = 1, x = 3, z = 4 } },
}, nil, 116.5))
assert(topLevelLegacy.terrainId == TerrainCatalog.DEFAULT_ID
    and topLevelLegacy.instances[1].x == 6 and topLevelLegacy.instances[1].z == 8,
    "top-level legacy terrain aliases receive the same one-time coordinate migration")

local unknownTerrain = Store.GetActive(Store.Normalize({
    schema = "island-project/v2", terrainId = "not-a-real-terrain", instances = {},
}, nil, 117))
assert(unknownTerrain.terrainId == TerrainCatalog.DEFAULT_ID
    and unknownTerrain.terrain.preset == TerrainCatalog.DEFAULT_ID,
    "unknown terrain identifiers safely fall back to the current three-island terrain")

local renamed = assert(Store.Rename(collection, second.islandId, "  松风岛  ", 120))
assert(renamed.name == "松风岛", "rename trims island names")
renamed.camera = { theta = 9, phi = 9, radius = 9, target = { 9, 9, 9 } }
renamed = assert(Store.SetTerrain(collection, second.islandId, alternateTerrainId, 120.5))
assert(renamed.terrainId == alternateTerrainId and renamed.terrain.preset == alternateTerrainId
    and renamed.camera.radius == (alternateCamera.radius or (alternateTerrain.overview or {}).radius or 118),
    "changing terrain canonicalizes its metadata and resets the terrain overview camera")
assert(Store.SetPublished(collection, second.islandId, true, 121), "an owned island can be marked public")
assert(collection.marketSyncPending and Store.Summaries(collection)[1].published,
    "publishing is persisted and exposed to the island manager")

local worldUpdate = Store.Get(collection, second.islandId)
local updatedCopy = { islandId = worldUpdate.islandId, name = worldUpdate.name, instances = worldUpdate.instances }
renamed = assert(Store.Put(collection, updatedCopy, 122))
assert(renamed.published,
    "routine world snapshots must not erase an island's publication state")
assert(renamed.terrainId == alternateTerrainId and renamed.terrain.preset == alternateTerrainId,
    "routine world snapshots without terrainId must not erase the island terrain")

assert(Store.SetActive(collection, collection.items[1].islandId, 122.5),
    "test setup can move focus away from the updated project")
local activationRevision = collection.revision
local reactivated = assert(Store.Put(collection, Copy(renamed), 122.6))
assert(collection.activeId == renamed.islandId
    and collection.revision == activationRevision + 1,
    "an identical inactive project snapshot must still preserve Put's activation semantics")
renamed = reactivated

local detachedRepeat = Copy(renamed)
local repeatRevision, repeatUpdatedAt = collection.revision, collection.updatedAt
local repeated = assert(Store.Put(collection, detachedRepeat, 123))
assert(repeated == renamed
    and collection.revision == repeatRevision and collection.updatedAt == repeatUpdatedAt,
    "an unchanged detached world snapshot must reuse the stored project without another deep copy")

detachedRepeat.instances[#detachedRepeat.instances + 1] = {
    id = 3, assetId = "builtin:adventure:lotus-pond",
}
local modified = assert(Store.Put(collection, detachedRepeat, 124))
assert(modified ~= renamed and #modified.instances == 1
    and modified.instances[1].id == 3 and collection.revision == repeatRevision + 1,
    "a real same-metadata snapshot edit must still be copied into the collection")
renamed = modified

renamed.instances[1] = { id = 2, assetId = "builtin:adventure:highland-watch" }
local duplicate = assert(Store.Duplicate(collection, renamed.islandId, 130))
assert(duplicate.islandId ~= renamed.islandId and duplicate.name:find("副本"), "duplicate has its own identity")
assert(duplicate.instances[1].assetId == "builtin:adventure:highland-watch", "duplicate preserves models")
assert(duplicate.terrainId == alternateTerrainId, "duplicate preserves the selected terrain")
assert(not duplicate.published, "a copied island must be reviewed before it can be published")

assert(Store.Delete(collection, duplicate.islandId, 140), "duplicate can be deleted")
assert(#collection.items == 2 and Store.GetActive(collection), "deleting active island selects another")
assert(Store.Delete(collection, collection.items[2].islandId, 150), "second island can be deleted")
local deleted, reason = Store.Delete(collection, collection.items[1].islandId, 160)
assert(not deleted and reason:find("至少"), "the last island cannot be deleted")

local summaries = Store.Summaries(collection)
assert(#summaries == 1 and summaries[1].active, "directory summaries expose active island")
assert(summaries[1].terrainId == TerrainCatalog.DEFAULT_ID
    and summaries[1].terrainName == TerrainCatalog.Get(TerrainCatalog.DEFAULT_ID).name,
    "directory summaries expose canonical terrain identity and presentation name")

print("island-project-store-spec: ok")
