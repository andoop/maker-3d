package.path = "scripts/?.lua;" .. package.path

local IslandLayout = require("IslandLayout")
local PortalNetwork = require("IslandPortalNetwork")
local PortalTransitionCoordinator = require("PortalTransitionCoordinator")
local ProjectStore = require("IslandProjectStore")
local TerrainCatalog = require("IslandTerrainCatalog")

local PORTAL_ASSET_ID = "builtin:compose:test-cloud-portal"
local PORTAL_ASSET = {
    assetId = PORTAL_ASSET_ID,
    versionId = "1.0.0",
    bounds = {
        min = { -1.0, 0, -0.45 },
        max = { 1.0, 2.8, 0.45 },
        size = { 2.0, 2.8, 0.9 },
    },
}
local MARKER_ASSET = {
    assetId = "builtin:compose:test-marker",
    versionId = "1.0.0",
    bounds = {
        min = { -0.5, 0, -0.5 },
        max = { 0.5, 1, 0.5 },
        size = { 1, 1, 1 },
    },
}
local assets = {
    [PORTAL_ASSET_ID] = PORTAL_ASSET,
    [MARKER_ASSET.assetId] = MARKER_ASSET,
}

local function ResolveAsset(assetId)
    return assets[tostring(assetId or "")]
end

local function ResolveLayout(terrainId)
    return IslandLayout.Resolve(terrainId)
end

local function Project(id, instances)
    return {
        schema = "island-project/v2",
        version = 2,
        islandId = id,
        name = "空岛 " .. id,
        terrainId = TerrainCatalog.DEFAULT_ID,
        terrain = { preset = TerrainCatalog.DEFAULT_ID, groundY = 0.42 },
        revision = 0,
        updatedAt = 0,
        instances = instances or {},
    }
end

local function Collection()
    return {
        schema = ProjectStore.SCHEMA,
        version = 1,
        revision = 0,
        updatedAt = 0,
        activeId = "a",
        items = {
            Project("a", {
                { id = 1, assetId = PORTAL_ASSET_ID, versionId = "1.0.0",
                    x = 0, y = 0, z = -16, rotationY = 0, scale = 1 },
            }),
            Project("b", {
                { id = 1, assetId = MARKER_ASSET.assetId, versionId = "1.0.0",
                    x = 0, y = 0, z = -16, rotationY = 0, scale = 1 },
            }),
            Project("c", {}),
        },
    }
end

local function Bind(collection, targetIslandId, options)
    options = options or {}
    options.sourceIslandId = options.sourceIslandId or "a"
    options.sourceInstanceId = options.sourceInstanceId or 1
    options.targetIslandId = targetIslandId
    options.portalAssetId = PORTAL_ASSET_ID
    options.resolveAsset = options.resolveAsset or ResolveAsset
    options.resolveLayout = options.resolveLayout or ResolveLayout
    options.now = options.now or 10
    return PortalNetwork.BindPair(collection, options)
end

local collection = Collection()
local pair, bindError, created = Bind(collection, "b", { targetX = 0, targetZ = -16 })
assert(pair and not bindError and created, "binding must atomically create the destination endpoint")
assert(math.abs(pair.targetInstance.x) + math.abs(pair.targetInstance.z + 16) > 0.1,
    "portal placement must skip an explicitly requested position occupied by another model")
assert(pair.sourceInstance.portal.schema == PortalNetwork.SCHEMA
    and pair.targetInstance.portal.schema == PortalNetwork.SCHEMA,
    "both endpoints must use the canonical portal schema")
assert(pair.sourceInstance.portal.linkId == pair.targetInstance.portal.linkId,
    "both endpoints must share one stable link id")
assert(pair.sourceInstance.portal.targetIslandId == "b"
    and pair.sourceInstance.portal.targetInstanceId == pair.targetInstance.id,
    "source endpoint must point to the generated destination")
assert(pair.targetInstance.portal.targetIslandId == "a"
    and pair.targetInstance.portal.targetInstanceId == pair.sourceInstance.id
    and pair.targetInstance.portal.generatedPeer == true,
    "generated destination must point back to the source")
assert(#PortalNetwork.FindProject(collection, "b").instances == 2,
    "binding adds exactly one portal beside existing destination scenery")

local resolved = assert(PortalNetwork.Resolve(collection, "a", 1))
assert(resolved.targetProject.islandId == "b"
    and resolved.targetInstance.id == pair.targetInstance.id,
    "runtime resolution must return the reciprocal endpoint")

-- The runtime gate survives world replacement, unlike a cooldown kept on the
-- source IslandWorld. Exercise enough A <-> B passages to catch re-entry,
-- endpoint duplication and state growth regressions.
local travelCollection = Collection()
local travelPair = assert(Bind(travelCollection, "b", { now = 9 }))
local travelRevision = travelCollection.revision
local travelGate = PortalNetwork.CreateTransitGate({
    successCooldown = 1.2,
    failureCooldown = 0.24,
})
local currentIslandId, currentInstanceId = "a", 1
for trip = 1, 40 do
    local token = assert(travelGate:TryBegin(travelPair.linkId))
    local duplicateToken, duplicateReason = travelGate:TryBegin(travelPair.linkId)
    assert(not duplicateToken and duplicateReason == "portal_transition_in_flight",
        "a portal transition must reject re-entry while the world hand-off is active")
    local route = assert(PortalNetwork.Resolve(
        travelCollection, currentIslandId, currentInstanceId))
    currentIslandId = route.targetProject.islandId
    currentInstanceId = route.targetInstance.id
    assert(travelGate:Finish(token, true), "the matching trip token must finish once")
    local cooldownToken, cooldownReason = travelGate:TryBegin(travelPair.linkId)
    assert(not cooldownToken and cooldownReason == "portal_transition_cooldown",
        "arrival cooldown must survive the source world being replaced")
    for _ = 1, 5 do travelGate:Update(0.25) end
end
assert(currentIslandId == "a" and currentInstanceId == 1,
    "an even number of portal passages must return to the original endpoint")
assert(#PortalNetwork.FindProject(travelCollection, "a").instances == 1
    and #PortalNetwork.FindProject(travelCollection, "b").instances == 2,
    "repeated travel must not create endpoint or model duplicates")
assert(travelCollection.revision == travelRevision,
    "runtime travel resolution and gating must not mutate persisted projects")
local failedToken = assert(travelGate:TryBegin(travelPair.linkId))
assert(travelGate:Finish(failedToken, false), "failed travel must release the in-flight lock")
travelGate:Update(0.24)
assert(travelGate:TryBegin(travelPair.linkId),
    "failed travel must become retryable after the short failure cooldown")
travelGate:Reset()

-- The visual hand-off begins one rendered frame before world replacement and
-- remains active until the destination's incremental instance queue is empty.
local coordinator = PortalTransitionCoordinator.new({ delayFrames = 1 })
local started, loading = 0, true
assert(coordinator:Begin({ target = "b" }))
local duplicateLoading, duplicateLoadingReason = coordinator:Begin({ target = "c" })
assert(not duplicateLoading and duplicateLoadingReason == "portal_loading_in_flight",
    "the loading hand-off must reject a second transition")
local loadingResult = coordinator:Update(function(payload)
    started = started + 1
    assert(payload.target == "b", "the queued route payload must survive the render delay")
    return true
end, function() return loading end)
assert(started == 1 and loadingResult.phase == "loading" and coordinator:IsActive(),
    "the coordinator starts after the loading surface has received one render")
loading = false
local completedLoading = coordinator:Update(function() error("must only start once") end,
    function() return loading end)
assert(completedLoading.completed and completedLoading.succeeded and not coordinator:IsActive(),
    "the loading surface must close only after destination restoration completes")

assert(coordinator:Begin({ target = "missing" }))
local failedLoading = coordinator:Update(function() return false end, function() return false end)
assert(failedLoading.completed and not failedLoading.succeeded and not coordinator:IsActive(),
    "a failed route must release the loading input lock")

local revisionBeforeIdempotent = collection.revision
local countBeforeIdempotent = #PortalNetwork.FindProject(collection, "b").instances
local existing, existingError, createdAgain = Bind(collection, "b", { now = 11 })
assert(existing and not existingError and createdAgain == false,
    "binding an already paired endpoint to the same island is idempotent")
assert(collection.revision == revisionBeforeIdempotent
    and #PortalNetwork.FindProject(collection, "b").instances == countBeforeIdempotent,
    "idempotent binding must not touch revisions or duplicate the destination")

local oldLinkId = pair.linkId
local oldTargetInstanceId = pair.targetInstance.id
local rejectLayout = {
    islands = { { x = 0, z = 0, radius = 10 } },
    IsPlacementValid = function() return false, "blocked_for_test" end,
}
local failedPair, failedReason = Bind(collection, "c", {
    now = 12,
    layout = rejectLayout,
    resolveLayout = false,
})
assert(not failedPair and tostring(failedReason):find("target_portal_placement_failed", 1, true),
    "a destination without a valid portal position must reject the transaction")
local stillPaired = assert(PortalNetwork.Resolve(collection, "a", 1))
assert(stillPaired.linkId == oldLinkId and stillPaired.targetProject.islandId == "b"
    and stillPaired.targetInstance.id == oldTargetInstanceId,
    "failed rebinding must preserve the complete previous pair")

local rebound, reboundError, reboundCreated = Bind(collection, "c", { now = 13 })
assert(rebound and not reboundError and reboundCreated and rebound.targetProject.islandId == "c",
    "rebinding must create a new pair on the chosen island")
assert(rebound.linkId ~= oldLinkId, "rebinding uses a fresh link identity")
assert(#PortalNetwork.FindProject(collection, "b").instances == 1,
    "rebinding removes the generated endpoint from the old destination")
assert(PortalNetwork.Resolve(collection, "a", 1).targetProject.islandId == "c",
    "source must resolve to the new destination after rebinding")

local deleted, deletedInfo = PortalNetwork.DeleteEndpoint(collection, "a", 1, 14)
assert(deleted and deletedInfo.targetProject.islandId == "c",
    "deleting one endpoint must resolve its paired destination")
assert(not PortalNetwork.FindInstance(PortalNetwork.FindProject(collection, "a"), 1)
    and #PortalNetwork.FindProject(collection, "c").instances == 0,
    "deleting one endpoint removes both physical portal models")

local orphanCollection = Collection()
local orphanProject = PortalNetwork.FindProject(orphanCollection, "b")
orphanProject.instances[#orphanProject.instances + 1] = {
    id = 9, assetId = PORTAL_ASSET_ID, versionId = "1.0.0",
    x = 4, y = 0, z = -16, rotationY = 0, scale = 1,
    portal = {
        schema = PortalNetwork.SCHEMA,
        linkId = "dangling",
        targetIslandId = "missing-island",
        targetInstanceId = 99,
    },
}
assert(PortalNetwork.CleanOrphans(orphanCollection, 20) == 1,
    "orphan cleanup must report every invalid endpoint")
assert(orphanProject.instances[#orphanProject.instances].portal == nil
    and orphanProject.instances[#orphanProject.instances].assetId == PORTAL_ASSET_ID,
    "orphan cleanup keeps the visible portal model and clears only its dead binding")

local storeCollection = Collection()
local storePair = assert(Bind(storeCollection, "b", { now = 30 }))
local sourceBeforeCopy = PortalNetwork.FindProject(storeCollection, "a")
local duplicate = assert(ProjectStore.Duplicate(storeCollection, "a", 31))
assert(duplicate.islandId ~= "a" and duplicate.instances[1].assetId == PORTAL_ASSET_ID,
    "duplicating an island keeps its portal model as reusable scenery")
assert(duplicate.instances[1].portal == nil,
    "duplicating an island must strip source-world portal identities")
assert(sourceBeforeCopy.instances[1].portal.linkId == storePair.linkId,
    "stripping duplicate bindings must not mutate the source pair")

local copied = PortalNetwork.CopyProjectWithoutBindings(sourceBeforeCopy)
assert(copied.instances[1].portal == nil and sourceBeforeCopy.instances[1].portal ~= nil,
    "the standalone copy helper must be non-mutating")

local deletedProject = assert(ProjectStore.Delete(storeCollection, "b", 32))
assert(deletedProject and not PortalNetwork.FindProject(storeCollection, "b"),
    "project store deletion must remove the requested destination island")
assert(not PortalNetwork.FindInstance(sourceBeforeCopy, 1),
    "deleting an island must remove every paired endpoint on surviving islands")
assert(duplicate.instances[1] and duplicate.instances[1].portal == nil,
    "unbound portal scenery on unrelated duplicated islands must survive cleanup")

local legacy = PortalNetwork.NormalizeBinding({
    linkId = "legacy-link", peerIslandId = "b", peerInstanceId = 7,
})
assert(legacy and legacy.targetIslandId == "b" and legacy.targetInstanceId == 7,
    "legacy peer field names must normalize into the canonical target fields")

local invalidCollection = Collection()
local invalidRevision = invalidCollection.revision
local invalidPair, invalidError = Bind(invalidCollection, "a", { now = 40 })
assert(not invalidPair and invalidError == "target_must_be_another_island"
    and invalidCollection.revision == invalidRevision,
    "same-island binding must fail without mutating the collection")

print("island-portal-spec: ok (atomic pair, 40 round trips, rebind, resolve, cleanup, duplicate and delete)")
