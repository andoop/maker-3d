package.path = "scripts/?.lua;" .. package.path

local ModelAssetStore = require("ModelAssetStore")
local BuiltinTemplates = require("BuiltinTemplates")
local IslandLayout = require("IslandLayout")
local WorkspaceMigration = require("WorkspaceMigration")
local DefaultIslandModels = require("DefaultIslandModels")
local ModelGeometry = require("ModelGeometry")
local Catalog = require("BlockCatalog")
local FirstPersonScale = require("FirstPersonScale")
local WorldPerformanceBudget = require("WorldPerformanceBudget")
local ModelLibraryPresentation = require("ModelLibraryPresentation")
local FullCylinderGeometry = require("FullCylinderGeometry")

local function Equal(actual, expected, label)
    assert(actual == expected, string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)))
end

local function Near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.0001,
        string.format("%s: expected %.4f, got %.4f", label or "number", expected, actual))
end

local function Block(name, x)
    return {
        name = name,
        position = { x or 0, 0.5, 0 },
        size = { 1, 1, 1 },
        rotation = { 0, 0, 0 },
        color = "#ffffff",
        materialId = "solid",
        shapeId = "box",
    }
end

local store = ModelAssetStore.new(BuiltinTemplates.BuildAll())
Equal(#store.builtins, 69, "composable built-ins include the paired cloud portal")
Equal(#store.marketAssets, 69, "offline market mirrors every current curated model")
local currentSnowMountain = assert(store:Get("builtin:compose:snow-cap-mountain"))
Equal(currentSnowMountain.versionId, "30.0.0", "builtin versions follow authored template revisions")
Equal(store:Get(currentSnowMountain.assetId, "1.0.0").versionId, "30.0.0",
    "saved builtin instances fall forward to the current authored revision")
assert(store.marketAssets[1].blocks == store.builtins[1].blocks,
    "immutable offline market cards must share builtin geometry instead of doubling memory")
Equal(store.marketAssets[1].versionId, store.builtins[1].versionId,
    "offline curated cards must expose the same authored revision as their builtin source")
local curatedUpgrade = ModelAssetStore.new(BuiltinTemplates.BuildAll())
local curatedId = curatedUpgrade.marketAssets[1].assetId
local staleKey = curatedId .. "@1.0.0"
curatedUpgrade:LoadState({
    cachedMarket = { {
        schema = ModelAssetStore.SCHEMA, assetId = curatedId, versionId = "1.0.0",
        name = "旧缓存模型", blocks = { Block("旧缓存块") }, source = "market",
    } },
    favorites = { [staleKey] = true }, downloaded = { [staleKey] = true },
})
Equal(#curatedUpgrade.marketAssets, 69, "stale curated cache must not duplicate current official cards")
local upgradedCurated = assert(curatedUpgrade:Get(curatedId))
Equal(upgradedCurated.versionId, "30.0.0", "curated cache resolves to the newest authored geometry")
assert(curatedUpgrade:IsFavorite(upgradedCurated), "curated favorites migrate to the newest authored revision")
local builtinCategories = ModelLibraryPresentation.Categories(store:GetSummaries("builtin"))
Equal(#builtinCategories, 10, "builtin category tab count includes portals")
Equal(#ModelLibraryPresentation.Filter(store:GetSummaries("builtin"), nil, "树木单件"), 8,
    "category tabs filter builtin models")
for _, asset in ipairs(store.builtins) do
    assert(not tostring(asset.description):find("，", 1, true)
        and not tostring(asset.description):find("。", 1, true)
        and not tostring(asset.description):find("；", 1, true),
        asset.name .. " description must stay compact")
end
assert(store:Get("builtin:compose:tiny-fruit-tree"), "small tree choice must exist")
assert(store:Get("builtin:compose:tall-layered-pine"), "landmark tree choice must exist")
Equal(store:Get("builtin:compose:blue-roof-family-house").storeys, 2,
    "enterable family house keeps its storey metadata")
assert(store:Get("builtin:compose:cloud-courier-airship"), "aircraft choice must exist")
assert(store:Get("builtin:compose:wood-fence-corner"), "connectable fence corner must exist")
assert(store:Get("builtin:compose:striped-sun-umbrella"), "street furnishing choice must exist")
assert(store:Get("builtin:compose:timber-footbridge"), "modular circulation kit must exist")
assert(store:Get("builtin:compose:walkable-cliff-terrace"), "structured mountain choice must exist")
assert(store:Get("builtin:compose:weathered-city-wall"), "low-component textured city wall must exist")
assert(store:Get("builtin:compose:overgrown-castle-keep"), "overgrown castle landmark must exist")
Equal(store:Get("builtin:wonder:cloudspine-mountain").assetId,
    "builtin:compose:snow-cap-mountain", "legacy mountain placement replacement")
Equal(store:Get("builtin:wonder:crystal-greenhouse-library").assetId,
    "builtin:compose:glass-garden-studio", "legacy building placement replacement")
Equal(store:Get("builtin:wonder:cloud-sail-station", "1.0.0").assetId,
    "builtin:compose:cloud-courier-airship", "legacy versioned placement replacement")
local migratedBuildingId, migratedBuildingScale = store:ResolveLegacyInstance(
    "builtin:wonder:sky-garden-tower", 0.42)
Equal(migratedBuildingId, "builtin:compose:narrow-three-storey-home", "legacy instance id migration")
Near(migratedBuildingScale, 1.0, "legacy default scale migration")
local _, migratedCustomScale = store:ResolveLegacyInstance("builtin:wonder:sky-garden-tower", 0.63)
Near(migratedCustomScale, 1.5, "legacy custom scale ratio migration")
assert(not store:Get("builtin:harbor:harbor-courier-residence"), "the rejected harbor library must be removed")
assert(not store:Get("builtin:cozy:rooftop-courier-workshop"), "the previous cozy library must be removed")
assert(not store:Get("builtin:adventure:meadow-cottage"), "the previous adventure library must be removed")
assert(not store:Get("builtin:storybook:meadow-cottage"), "the transitional storybook library must be removed")
assert(not store:Get("builtin:mykonos-house") and not store:Get("builtin:pool-villa"),
    "legacy builtin models must be removed from the model store")
-- Drafts stay mutable while every published version is immutable and addressable.
local draft = store:CreateBlank("版本模型")
assert(store:SaveDraft(draft.assetId, { name = "版本模型", blocks = { Block("A") } }))
local first = assert(store:Publish(draft.assetId))
Equal(first.versionId, "1.0.0", "first version")
Equal(#first.blocks, 1, "first version block count")
assert(store:HasPendingMarketSync(), "publish must enter the sync queue")

assert(store:SaveDraft(draft.assetId, { name = "版本模型", blocks = { Block("A"), Block("B", 1) } }))
local second = assert(store:Publish(draft.assetId))
Equal(second.versionId, "1.1.0", "second version")
Equal(#store:Get(draft.assetId, "1.0.0").blocks, 1, "old version remains immutable")
Equal(#store:Get(draft.assetId, "1.1.0").blocks, 2, "new version block count")
Equal(store:Get(draft.assetId).source, "mine", "unversioned lookup resolves the draft")
local ownMarketCards = 0
for _, asset in ipairs(store:GetAssets("market")) do
    if asset.assetId == draft.assetId then ownMarketCards = ownMarketCards + 1 end
end
Equal(ownMarketCards, 1, "market shows only the latest published version")
local deletePublished, deletePublishedError = store:Delete(draft.assetId)
assert(not deletePublished and tostring(deletePublishedError):find("先下架"), "active publication blocks draft deletion")
assert(store:Unpublish(draft.assetId), "published model can be withdrawn")
Equal(#store:GetPublishedProfile().items, 0, "withdrawn model leaves the public profile")
ownMarketCards = 0
for _, asset in ipairs(store:GetAssets("market")) do
    if asset.assetId == draft.assetId then ownMarketCards = ownMarketCards + 1 end
end
Equal(ownMarketCards, 0, "withdrawn model leaves the market list")
assert(store:Publish(draft.assetId), "withdrawn model can be republished as a new version")
Equal(store:Get(draft.assetId).publishedVersion, "1.2.0", "republish advances version")
store:MarkMarketSynced()
assert(not store:HasPendingMarketSync(), "successful cloud sync clears the queue")

-- Nested assets flatten once, retain packaged dependency metadata, and reject cycles.
local child = store:CreateBlank("子模型")
assert(store:SaveDraft(child.assetId, { name = "子模型", blocks = { Block("子块") } }))
local parent = store:CreateBlank("组合模型")
assert(store:SaveDraft(parent.assetId, {
    name = "组合模型",
    blocks = { Block("主体") },
    components = { { assetId = child.assetId, versionId = "latest", position = { 2, 0, 0 }, scale = 1 } },
}))
local flattened = assert(store:Flatten(parent.assetId))
Equal(#flattened.blocks, 2, "flattened nested block count")
Equal(#flattened.components, 0, "flattened package has no live nested component")
Equal(#flattened.packagedDependencies, 1, "dependency attribution is retained")

local sharedFlattened = assert(store:FlattenShared(parent.assetId))
assert(sharedFlattened == store:FlattenShared(parent.assetId),
    "shared flatten cache hits must reuse the exact canonical table")
assert(sharedFlattened == store:AcquireRenderable(parent.assetId),
    "renderable alias must reuse the shared flattened table")
local mutableFlattened = assert(store:Flatten(parent.assetId))
mutableFlattened.blocks[1].name = "只修改副本"
mutableFlattened.bounds.size[1] = 999
local freshMutableFlattened = assert(store:Flatten(parent.assetId))
assert(freshMutableFlattened ~= mutableFlattened,
    "editable flatten calls must return different top-level tables")
assert(freshMutableFlattened.blocks ~= mutableFlattened.blocks
        and freshMutableFlattened.bounds ~= mutableFlattened.bounds,
    "editable flatten calls must detach nested tables")
assert(sharedFlattened.blocks[1].name ~= "只修改副本"
        and sharedFlattened.bounds.size[1] ~= 999,
    "editing a Flatten result must not contaminate the shared cache")

local oldSharedVersion = sharedFlattened.versionId
assert(store:SaveDraft(parent.assetId, {
    name = "组合模型",
    blocks = { Block("更新主体"), Block("新增主体", -1) },
    components = { { assetId = child.assetId, versionId = "latest", position = { 2, 0, 0 }, scale = 1 } },
}))
local updatedShared = assert(store:FlattenShared(parent.assetId))
assert(updatedShared ~= sharedFlattened and updatedShared.versionId ~= oldSharedVersion,
    "saving a new asset version must replace the shared cache entry")
Equal(#updatedShared.blocks, 3, "updated shared flatten block count")
Equal(updatedShared.blocks[1].name, "更新主体", "updated shared flatten geometry")

local licenseShared = assert(store:FlattenShared(parent.assetId))
assert(store:SetLicense(parent.assetId, "allow_fork"))
local relicensedShared = assert(store:FlattenShared(parent.assetId))
assert(relicensedShared ~= licenseShared and relicensedShared.license == "allow_fork",
    "same-version metadata updates must invalidate the shared cache")

assert(store:SaveDraft(child.assetId, {
    name = "子模型",
    blocks = { Block("子块") },
    components = { { assetId = parent.assetId, versionId = "latest" } },
}))
local cyclic, cycleError = store:Flatten(parent.assetId)
assert(not cyclic and tostring(cycleError):find("循环"), "cyclic model dependency must be rejected")
local deletedDependency, dependencyError = store:Delete(child.assetId)
assert(not deletedDependency and tostring(dependencyError):find("引用"), "referenced model cannot be deleted")

-- A use-only market model can be placed as a whole but cannot be forked.
local useOnly = ModelAssetStore.Normalize({ name = "仅整体", blocks = { Block("块") }, license = "use_only" }, {
    source = "market", assetId = "market:test:use-only", versionId = "1.0.0", ownerId = "author",
})
store.marketAssets[#store.marketAssets + 1] = useOnly
store:Reindex()
local forked, forkError = store:Fork(useOnly)
assert(not forked and tostring(forkError):find("整体使用"), "use-only model must reject forking")
assert(store:ToggleFavorite(useOnly.assetId, useOnly.versionId), "favorite should turn on")
Equal(#store.cachedMarket, 1, "favoriting caches the exact market version")

local exported = store:ExportState()
assert(exported.marketSyncPending == false, "sync state must persist")
assert(exported.revision > 0 and exported.updatedAt >= 0, "library conflict metadata must persist")
local restored = ModelAssetStore.new(BuiltinTemplates.BuildAll())
restored:LoadState(exported)
Equal(restored.stateRevision, exported.revision, "library revision roundtrip")
assert(restored:Get(useOnly.assetId, useOnly.versionId), "cached market model restores offline")
assert(restored:IsFavorite(restored:Get(useOnly.assetId, useOnly.versionId)), "favorite restores offline")

-- Original workbench saves migrate exactly once into editable personal assets.
local migrationStore = ModelAssetStore.new(BuiltinTemplates.BuildAll())
local migrated, migratedCount = WorkspaceMigration.Apply(migrationStore, {
    legacyProject = { name = "旧工程", blocks = { Block("工程块") } },
    legacyTemplates = {
        { name = "旧模板", blocks = { Block("模板块") } },
        { name = "空模板", blocks = {} },
    },
})
assert(migrated and migratedCount == 2, "legacy project and non-empty templates migrate")
Equal(#migrationStore:GetAssets("mine"), 2, "legacy assets enter my models")
local librarySnapshot = migrationStore:ExportState()
local migratedAgain, secondCount = WorkspaceMigration.Apply(migrationStore, {
    library = librarySnapshot,
    legacyProject = { name = "不应重复", blocks = { Block("重复块") } },
})
assert(not migratedAgain and secondCount == 0, "existing v2 library prevents duplicate migration")
Equal(#migrationStore:GetAssets("mine"), 2, "migration is idempotent")

-- Publishing must never report success for an asset that cannot fit in the
-- player's public market profile.
local capacityStore = ModelAssetStore.new({})
for index = 1, ModelAssetStore.MAX_PUBLIC_ASSETS do
    local item = capacityStore:CreateBlank("公开模型" .. tostring(index))
    assert(capacityStore:SaveDraft(item.assetId, { name = item.name, blocks = { Block("块") } }))
    assert(capacityStore:Publish(item.assetId), "public capacity slot " .. tostring(index))
end
local overflow = capacityStore:CreateBlank("第十三个模型")
assert(capacityStore:SaveDraft(overflow.assetId, { name = overflow.name, blocks = { Block("块") } }))
local overflowPublish, overflowError = capacityStore:Publish(overflow.assetId)
assert(not overflowPublish and tostring(overflowError):find("12"), "thirteenth public asset must be rejected explicitly")

-- Non-centered model bounds must rotate around the model origin without lying
-- about their real occupied center.
local asymmetric = { bounds = { min = { 0, 0, -1 }, max = { 4, 2, 1 }, size = { 4, 2, 2 } } }
local footprint = IslandLayout.Footprint(nil, asymmetric, 0, 0, 0, 1)
Near(footprint.x, 2, "asymmetric footprint center x")
Near(footprint.z, 0, "asymmetric footprint center z")
local rotated = IslandLayout.Footprint(nil, asymmetric, 0, 0, math.pi * 0.5, 1)
Near(rotated.x, 0, "rotated footprint center x")
Near(rotated.z, -2, "rotated footprint center z")

local simple = { bounds = { min = { -1, 0, -1 }, max = { 1, 2, 1 }, size = { 2, 2, 2 } } }
assert(#IslandLayout.ISLANDS == 3 and #IslandLayout.BRIDGES == 3, "world uses a triangular three-island layout")
assert(IslandLayout.ContainsPoint(0, -16, 0.42), "central island is walkable")
assert(IslandLayout.ContainsPoint(-44, 24, 0.42) and IslandLayout.ContainsPoint(44, 24, 0.42),
    "both satellite islands are walkable")
assert(IslandLayout.ContainsPoint(-22, 4, 0.42), "shattered bridge keeps a continuous walking ribbon")
assert(not IslandLayout.ContainsPoint(29.2, -16, 0.42), "player radius stays inside the main island edge")
assert(IslandLayout.ContainsInFootprint(IslandLayout.Footprint(nil, simple, 2, 3, 0, 1), 2.8, 3, 0.1),
    "point-footprint collision includes player padding")
assert(IslandLayout.IsPlacementValid({}, simple, 0, 0, 0, 1))
assert(IslandLayout.IsPlacementValid({}, simple, 26.5, -16, 0, 1), "visible main island edge should remain usable")
local outside, outsideReason = IslandLayout.IsPlacementValid({}, simple, 28.0, -16, 0, 1)
assert(not outside and outsideReason == "outside_island", "island boundary must reject outside models")
local cornerOutside = IslandLayout.IsPlacementValid({}, simple, 28.0, 40.0, 0, 1)
assert(not cornerOutside, "gaps between the authored islands remain unavailable for models")
local placed = { { id = 1, x = 0, z = 0, rotationY = 0, scale = 1, renderAsset = simple } }
local overlap, overlapReason, overlapId = IslandLayout.IsPlacementValid(placed, simple, 0.5, 0, 0, 1)
assert(overlap, "partial model overlap must remain freely adjustable")
local buried, buriedReason, buriedId = IslandLayout.IsPlacementValid(placed, simple, 0, 0, 0, 1)
assert(not buried and buriedReason == "buried" and buriedId == 1,
    "a fully hidden duplicate must still be rejected")
assert(IslandLayout.IsPlacementValid(placed, simple, 0, 0, 0, 1, nil, nil, 2.2),
    "models stacked above one another must not collide in two dimensions")
local largeSolid = {
    bounds = { min = { -4, 0, -4 }, max = { 4, 8, 4 }, size = { 8, 8, 8 } },
    blocks = { { size = { 8, 8, 8 }, materialId = "stone" } },
}
local enclosing = { { id = 7, x = 0, y = 0, z = 0, rotationY = 0, scale = 1, renderAsset = largeSolid } }
local hidden, hiddenReason = IslandLayout.IsPlacementValid(enclosing, simple, 0, 0, 0, 1)
assert(not hidden and hiddenReason == "buried", "a small model lost inside one dense model must be rejected")
assert(IslandLayout.IsPlacementValid(enclosing, simple, 3.5, 0, 0, 1),
    "a model with a clearly visible part outside the occluder must be allowed")
local hollowBuilding = {
    bounds = { min = { -4, 0, -4 }, max = { 4, 8, 4 }, size = { 8, 8, 8 } },
    blocks = {
        { size = { 8, 0.2, 8 }, materialId = "wood" },
        { size = { 8, 8, 0.2 }, materialId = "solid" },
        { size = { 0.2, 8, 8 }, materialId = "solid" },
    },
}
assert(IslandLayout.IsPlacementValid({ { id = 8, x = 0, z = 0, scale = 1, renderAsset = hollowBuilding } },
    simple, 0, 0, 0, 1), "furniture and props must remain placeable inside hollow buildings")
Near(IslandLayout.SelectionFocusRadius(simple, 1, 80, 1), 8,
    "far model selection pulls the orbit camera closer")
Near(IslandLayout.SelectionFocusRadius(simple, 1, 7, 1), 7,
    "near model selection preserves the current camera distance")
assert(IslandLayout.SelectionFocusRadius({ bounds = { size = { 40, 20, 30 } } }, 1, 180, 1) > 80,
    "large model selection keeps enough framing distance instead of over-zooming")
assert(IslandLayout.SelectionFocusRadius(simple, 1, 80, 0.5) > 10,
    "portrait selection framing accounts for the narrower horizontal field of view")

-- Rotated thin models use oriented footprints, avoiding the false positives
-- produced by overlapping axis-aligned bounding boxes.
local thin = { bounds = { min = { -2, 0, -0.25 }, max = { 2, 1, 0.25 }, size = { 4, 1, 0.5 } } }
local diagonal = math.pi * 0.25
local separatedThin = {
    { id = 2, x = 0.6, z = 0.6, rotationY = diagonal, scale = 1, renderAsset = thin },
}
assert(IslandLayout.IsPlacementValid(separatedThin, thin, 0, 0, diagonal, 1),
    "separated rotated footprints should not collide through their AABBs")

-- The deliberately small starter composition must fit and remain below the
-- mobile node budget used by the runtime.
local starters = {}
local starterBlocks, starterShadows = 0, 0
for index, spec in ipairs(DefaultIslandModels.MODELS) do
    local asset = assert(restored:Flatten(assert(restored:Get(spec.assetId))))
    local rotation = spec.rotation * math.pi / 180
    local valid, reason = IslandLayout.IsPlacementValid(starters, asset, spec.x, spec.z, rotation, spec.scale)
    assert(valid, "starter model " .. tostring(index) .. " is invalid: " .. tostring(reason))
    starterBlocks = starterBlocks + #asset.blocks
    for _, block in ipairs(asset.blocks) do
        if ModelGeometry.ShouldCastShadow(block) then starterShadows = starterShadows + 1 end
    end
    starters[#starters + 1] = {
        id = index, x = spec.x, z = spec.z, rotationY = rotation, scale = spec.scale, renderAsset = asset,
    }
end
assert(starterBlocks <= DefaultIslandModels.BLOCK_BUDGET,
    "starter composition exceeds mobile model-node budget")
assert(starterShadows <= DefaultIslandModels.SHADOW_BUDGET,
    "starter composition exceeds mobile shadow-caster budget")

local denseHouse = assert(restored:Flatten(assert(restored:Get("builtin:compose:narrow-three-storey-home"))))
local denseInstances = {}
for index = 1, 5 do denseInstances[index] = { renderAsset = denseHouse } end
assert(WorldPerformanceBudget.CanAdd(denseInstances, denseHouse.blocks, true),
    "six detailed houses should remain within the mobile authoring budget")
denseInstances[6] = { renderAsset = denseHouse }
local seventhAllowed, seventhCost, mobileLimit = WorldPerformanceBudget.CanAdd(denseInstances, denseHouse.blocks, true)
assert(seventhAllowed and (seventhCost.blocks > mobileLimit.blocks or seventhCost.shadows > mobileLimit.shadows),
    "dense mobile scenes must keep authoring available beyond the render-quality watermark")
Equal(WorldPerformanceBudget.ShadowMapSize(true), 512,
    "mobile island rendering uses a device-friendly shadow map")
local shadowCursor = 0
for _ = 1, mobileLimit.shadows + 20 do
    local _, nextCursor = WorldPerformanceBudget.ReserveShadow(Block("结构阴影", 0), true, shadowCursor)
    shadowCursor = nextCursor
end
Equal(shadowCursor, mobileLimit.shadows,
    "adaptive mobile shadows stop growing while model content remains placeable")
local tinyShadow, unchangedCursor = WorldPerformanceBudget.ReserveShadow({
    name = "精细结构", size = { 0.45, 0.45, 0.45 }, materialId = "solid", shapeId = "box",
}, true, 0)
assert(not tinyShadow and unchangedCursor == 0,
    "small mobile details remain visible without consuming the shadow budget")

-- Runtime collision semantics use actual shape bounds and all local rotations;
-- decorative foliage/fabric/rings never become invisible first-person walls.
local rotatedRing = {
    name = "水平圆环", shapeId = "torus", materialId = "metal",
    size = { 8, 5, 0.2 }, rotation = { math.pi * 0.5, 0, 0 },
}
local ringHalf = ModelGeometry.RotatedHalfExtents(rotatedRing)
assert(ringHalf[2] < 0.1 and ModelGeometry.CollisionRole(rotatedRing) == "decorative",
    "horizontal torus must use rotated thin bounds and decorative collision")
assert(ModelGeometry.CollisionRole({ materialId = "leaf", shapeId = "sphere", size = { 4, 4, 4 } }) == "decorative",
    "tree crowns must not become first-person box walls")
assert(ModelGeometry.CollisionRole({ materialId = "glass", shapeId = "box", size = { 1, 2, 0.1 } }) == "solid",
    "structural glass remains a physical enclosure")

local function FindBlock(asset, keyword)
    for _, block in ipairs(asset.blocks) do
        if tostring(block.name):find(keyword, 1, true) then return block end
    end
end

local function SurfaceTop(block)
    local _, y = ModelGeometry.Position(block)
    return y + ModelGeometry.RotatedHalfExtents(block)[2]
end

local function RouteTops(asset, keyword)
    local tops = {}
    for _, block in ipairs(asset.blocks) do
        if tostring(block.name):find(keyword, 1, true) then
            assert(ModelGeometry.CollisionRole(block) == "surface",
                asset.name .. " route component is not a runtime walk surface: " .. tostring(block.name))
            tops[#tops + 1] = SurfaceTop(block)
        end
    end
    table.sort(tops)
    return tops
end


local function AssertRoute(assetId, scale, startKeyword, routeKeyword, finishKeyword)
    local asset = assert(store:Get(assetId))
    local startBlock, finishBlock = assert(FindBlock(asset, startKeyword)), assert(FindBlock(asset, finishKeyword))
    assert(ModelGeometry.CollisionRole(startBlock) == "surface",
        asset.name .. " route start is not a runtime walk surface: " .. tostring(startBlock.name))
    assert(ModelGeometry.CollisionRole(finishBlock) == "surface",
        asset.name .. " route finish is not a runtime walk surface: " .. tostring(finishBlock.name))
    local heights = { SurfaceTop(startBlock) }
    for _, top in ipairs(RouteTops(asset, routeKeyword)) do heights[#heights + 1] = top end
    heights[#heights + 1] = SurfaceTop(finishBlock)
    table.sort(heights)
    for index = 2, #heights do
        assert((heights[index] - heights[index - 1]) * scale <= FirstPersonScale.STEP_HEIGHT + 0.001,
            asset.name .. " route has an unreachable vertical gap")
    end
end

local function RuntimeCollider(block)
    local x, y, z = ModelGeometry.Position(block)
    local sx, sy, sz = ModelGeometry.Size(block)
    local rx, ry, rz = ModelGeometry.Rotation(block)
    local bounds = Catalog.FindShape(block.shapeId or block.shape).bounds
    local halfWidth, halfHeight, halfDepth, angle
    if math.abs(rx) <= 0.0001 and math.abs(rz) <= 0.0001 then
        halfWidth, halfHeight, halfDepth = sx * bounds[1] * 0.5, sy * bounds[2] * 0.5, sz * bounds[3] * 0.5
        angle = ry
    else
        local half = ModelGeometry.RotatedHalfExtents(block)
        halfWidth, halfHeight, halfDepth, angle = half[1], half[2], half[3], 0
    end
    return {
        block = block, x = x, z = z, halfWidth = halfWidth, halfDepth = halfDepth, angle = angle,
        minimumY = y - halfHeight, maximumY = y + halfHeight,
        role = ModelGeometry.CollisionRole(block),
    }
end

local function InsideCollider(collider, x, z, padding)
    local cosine, sine = math.cos(collider.angle), math.sin(collider.angle)
    local dx, dz = x - collider.x, z - collider.z
    local localX = math.abs(dx * cosine - dz * sine)
    local localZ = math.abs(dx * sine + dz * cosine)
    return localX <= collider.halfWidth + padding and localZ <= collider.halfDepth + padding
end

-- Walk a real 1.2 m player capsule from outside to inside through every
-- authored sliding doorway. This mirrors IslandWorld's surface/solid tests,
-- so a decorative open leaf cannot hide a foundation, wall or threshold that
-- still blocks the actual passage.
local function AssertDoorPassages(asset)
    local colliders, visualColliders, surfaces, doors = {}, {}, {}, {}
    for _, block in ipairs(asset.blocks) do
        local collider = RuntimeCollider(block)
        local name = tostring(block.name)
        if not name:find("贴墙全开抽拉门板", 1, true)
            and not name:find("黄铜抽拉门上轨", 1, true)
            and not name:find("黄铜嵌入拉手", 1, true) then
            visualColliders[#visualColliders + 1] = collider
        end
        if collider.role ~= "decorative" and collider.role ~= "fluid" then
            colliders[#colliders + 1] = collider
        end
        if collider.role == "surface" then surfaces[#surfaces + 1] = collider end
        if tostring(block.name):find("贴墙全开抽拉门板", 1, true) then doors[#doors + 1] = block end
    end
    for _, door in ipairs(doors) do
        local prefix = tostring(door.name):gsub("贴墙全开抽拉门板$", "")
        local track
        for _, block in ipairs(asset.blocks) do
            if tostring(block.name) == prefix .. "黄铜抽拉门上轨" then track = block break end
        end
        assert(track, asset.name .. " doorway has no matching sliding rail: " .. tostring(door.name))
        local dx, dy, dz = ModelGeometry.Position(door)
        local dsx, dsy, dsz = ModelGeometry.Size(door)
        local tx, _, tz = ModelGeometry.Position(track)
        local front = dsx > dsz
        local doorAlong, trackAlong = front and dx or dz, front and tx or tz
        local doorWidth = front and dsx or dsz
        local slideSign = doorAlong >= trackAlong and 1 or -1
        local openingAlong = trackAlong - slideSign * doorWidth * 0.5
        local normal = front and tz or tx
        local outward = normal >= 0 and 1 or -1
        local doorBottom = dy - dsy * 0.5
        local ground = doorBottom > FirstPersonScale.STEP_HEIGHT + 0.02 and doorBottom or 0
        for sample = 0, 12 do
            local distance = 0.72 - sample * 0.12
            local x = front and openingAlong or normal + outward * distance
            local z = front and normal + outward * distance or openingAlong
            local best = ground
            for _, surface in ipairs(surfaces) do
                if surface.maximumY <= ground + FirstPersonScale.STEP_HEIGHT + 0.001
                    and surface.maximumY > best
                    and InsideCollider(surface, x, z, FirstPersonScale.SURFACE_PADDING) then
                    best = surface.maximumY
                end
            end
            ground = best
            local blocker
            for _, collider in ipairs(colliders) do
                if collider.maximumY > ground + 0.02
                    and collider.minimumY < ground + FirstPersonScale.HEIGHT
                    and InsideCollider(collider, x, z, FirstPersonScale.RADIUS) then
                    blocker = collider.block
                    break
                end
            end
            assert(not blocker, asset.name .. " doorway is blocked by "
                .. tostring(blocker and blocker.name) .. ": " .. tostring(door.name))
            if sample >= 7 then
                local visualBlocker
                for _, collider in ipairs(visualColliders) do
                    if collider.maximumY > doorBottom + 0.16
                        and collider.minimumY < doorBottom + 1.40
                        and InsideCollider(collider, x, z, 0) then
                        visualBlocker = collider.block
                        break
                    end
                end
                assert(not visualBlocker, asset.name .. " doorway sightline is hidden by "
                    .. tostring(visualBlocker and visualBlocker.name) .. ": " .. tostring(door.name))
            end
        end
    end
    return #doors
end

local doorwayCount = 0
for _, asset in ipairs(store.builtins) do
    if asset.category == "可进入建筑" then
        local floor = FindBlock(asset, asset.name == "玻璃花园工坊" and "室内地板" or "一层室内地板")
        local foundation = FindBlock(asset, "内收石砌基础")
        assert(floor and foundation, asset.name .. " must expose a recessed foundation and finished floor")
        local floorX, _, floorZ = ModelGeometry.Size(floor)
        local foundationX, _, foundationZ = ModelGeometry.Size(foundation)
        assert(foundationX <= floorX - 0.12 and foundationZ <= floorZ - 0.12,
            asset.name .. " foundation must not project into the doorway approach")
        assert(SurfaceTop(floor) <= FirstPersonScale.STEP_HEIGHT - 0.10,
            asset.name .. " ground floor is too high to enter naturally")
        doorwayCount = doorwayCount + AssertDoorPassages(asset)
    end
end
assert(doorwayCount >= 10, "every authored building doorway must receive a first-person passage sweep")

-- Mirror the first-person runtime's conservative collision representation and
-- require each authored route piece to expose at least one player-sized stand
-- point. This catches stairs hidden inside rocks, roofs or oversized AABBs.
local function AssertRouteClearance(assetId, scale, routeKeyword)
    local asset = assert(store:Get(assetId))
    local colliders = {}
    for _, block in ipairs(asset.blocks) do
        local collider = RuntimeCollider(block)
        if collider.role ~= "decorative" and collider.role ~= "fluid" and block.type ~= "door" then
            colliders[#colliders + 1] = collider
        end
    end
    local playerHeight = FirstPersonScale.HEIGHT / scale
    local playerRadius = FirstPersonScale.RADIUS / scale
    local routeCount = 0
    for _, block in ipairs(asset.blocks) do
        if tostring(block.name):find(routeKeyword, 1, true) then
            routeCount = routeCount + 1
            local surface = RuntimeCollider(block)
            local clear = false
            for ix = -4, 4 do
                for iz = -4, 4 do
                    local localX = ix / 4 * math.max(0, surface.halfWidth - 0.04)
                    local localZ = iz / 4 * math.max(0, surface.halfDepth - 0.04)
                    local cosine, sine = math.cos(surface.angle), math.sin(surface.angle)
                    local x = surface.x + localX * cosine + localZ * sine
                    local z = surface.z - localX * sine + localZ * cosine
                    local blocked = false
                    for _, collider in ipairs(colliders) do
                        if collider.block ~= block
                            and collider.maximumY > surface.maximumY + 0.02
                            and collider.minimumY < surface.maximumY + playerHeight
                            and InsideCollider(collider, x, z, playerRadius) then
                            blocked = true
                            break
                        end
                    end
                    if not blocked then clear = true break end
                end
                if clear then break end
            end
            assert(clear, asset.name .. " route component has no first-person clearance: " .. tostring(block.name))
        end
    end
    assert(routeCount > 0, asset.name .. " route keyword matched no components: " .. routeKeyword)
end

local function AssertSurfaceChain(assetId, startKeyword, finishKeyword, allowedKeywords)
    local asset = assert(store:Get(assetId))
    local nodes, startIndex, finishIndex = {}, nil, nil
    for _, block in ipairs(asset.blocks) do
        local name = tostring(block.name or "")
        local allowed = false
        for _, keyword in ipairs(allowedKeywords) do
            if name:find(keyword, 1, true) then allowed = true break end
        end
        if allowed and ModelGeometry.CollisionRole(block) == "surface" then
            nodes[#nodes + 1] = RuntimeCollider(block)
            if name:find(startKeyword, 1, true) then startIndex = #nodes end
            if name:find(finishKeyword, 1, true) then finishIndex = #nodes end
        end
    end
    assert(startIndex and finishIndex, asset.name .. " surface chain endpoints are missing")
    local queue, visited = { startIndex }, { [startIndex] = true }
    local cursor = 1
    local horizontalReach = FirstPersonScale.RADIUS * 2 + 0.06
    while cursor <= #queue do
        local currentIndex = queue[cursor]
        cursor = cursor + 1
        if currentIndex == finishIndex then return end
        local current = nodes[currentIndex]
        for nextIndex, candidate in ipairs(nodes) do
            if not visited[nextIndex] then
                local gapX = math.max(0, math.abs(current.x - candidate.x)
                    - current.halfWidth - candidate.halfWidth)
                local gapZ = math.max(0, math.abs(current.z - candidate.z)
                    - current.halfDepth - candidate.halfDepth)
                local step = math.abs(current.maximumY - candidate.maximumY)
                if gapX <= horizontalReach and gapZ <= horizontalReach
                    and step <= FirstPersonScale.STEP_HEIGHT + 0.001 then
                    visited[nextIndex] = true
                    queue[#queue + 1] = nextIndex
                end
            end
        end
    end
    error(asset.name .. " has no connected surface chain from " .. startKeyword .. " to " .. finishKeyword)
end

AssertRoute("builtin:compose:blue-roof-family-house", 1,
    "一层室内地板", "一至二层外部连续阶梯", "二层室内地板")
AssertRoute("builtin:compose:narrow-three-storey-home", 1,
    "二层室内地板", "二至三层外部连续阶梯", "三层室内地板")
AssertRoute("builtin:compose:walkable-cliff-terrace", 1,
    "连续山径台阶0", "连续山径台阶", "连续山径台阶14")
AssertRouteClearance("builtin:compose:blue-roof-family-house", 1, "一至二层外部连续阶梯")
AssertRouteClearance("builtin:compose:narrow-three-storey-home", 1, "二至三层外部连续阶梯")
AssertRouteClearance("builtin:compose:narrow-three-storey-home", 1, "二层连续环廊")
AssertRouteClearance("builtin:compose:walkable-cliff-terrace", 1, "连续山径台阶")
AssertSurfaceChain("builtin:compose:narrow-three-storey-home", "二层室内地板", "三层室内地板", {
    "二层室内地板", "一至二层上层入口平台", "二层连续环廊",
    "二至三层外部连续阶梯", "二至三层上层入口平台", "三层室内地板",
})
local treeAsset = assert(store:Get("builtin:compose:tall-guardian-oak"))
assert(ModelGeometry.CollisionRole(assert(FindBlock(treeAsset, "枝架0"))) == "decorative",
    "visual tree branches must not become oversized invisible first-person walls")
local treeBranches, treeLeafClumps, treeRootSticks = 0, 0, 0
for _, block in ipairs(treeAsset.blocks) do
    local name = tostring(block.name)
    if name:find("枝架", 1, true) then treeBranches = treeBranches + 1 end
    if name:find("枝叶团", 1, true) then treeLeafClumps = treeLeafClumps + 1 end
    if name:find("树根", 1, true) then treeRootSticks = treeRootSticks + 1 end
end
assert(treeBranches >= 8 and treeLeafClumps >= treeBranches * 2,
    "tree crowns must expose branches with multiple separate leaf clumps")
assert(treeRootSticks == 0, "trees must not add radial wooden root sticks")

-- Runtime-independent coverage for the explicit closed cylinder recipe.
TRIANGLE_LIST = 0
Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
Vector2 = function(x, y) return { x = x, y = y } end
local cylinderGeometry = { vertices = {} }
function cylinderGeometry:BeginGeometry() end
function cylinderGeometry:DefineVertex(vertex) self.vertices[#self.vertices + 1] = vertex end
function cylinderGeometry:DefineNormal() end
function cylinderGeometry:DefineTexCoord() end
function cylinderGeometry:Commit() end
local cylinderNode = {}
function cylinderNode:CreateComponent() return cylinderGeometry end
local cylinderRecipe = FullCylinderGeometry.new(12)
cylinderRecipe.build(cylinderRecipe, cylinderNode, nil)
Equal(#cylinderGeometry.vertices, 144, "closed cylinder triangle vertex count")
local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
for _, vertex in ipairs(cylinderGeometry.vertices) do
    minX, maxX = math.min(minX, vertex.x), math.max(maxX, vertex.x)
    minY, maxY = math.min(minY, vertex.y), math.max(maxY, vertex.y)
    minZ, maxZ = math.min(minZ, vertex.z), math.max(maxZ, vertex.z)
end
Near(minX, -0.5, "cylinder min x"); Near(maxX, 0.5, "cylinder max x")
Near(minY, -0.5, "cylinder bottom cap"); Near(maxY, 0.5, "cylinder top cap")
Near(minZ, -0.5, "cylinder min z"); Near(maxZ, 0.5, "cylinder max z")

-- Cloud-market payloads are author-namespaced, bounded and declarative.
local marketAsset = {
    schema = "model-asset/v1",
    assetId = "builtin:spoof",
    versionId = "1.0.0",
    name = "远端模型",
    license = "allow_fork",
    blocks = { Block("远端块") },
    components = { { assetId = "builtin:compose:glass-garden-studio" } },
    script = "must not survive",
}
local oversized = { schema = "model-asset/v1", assetId = "too-big", blocks = {} }
for index = 1, 1201 do oversized.blocks[index] = Block("大模型") end
local oversizedGeometry = {
    schema = "model-asset/v1", assetId = "huge-geometry",
    blocks = { { name = "异常大块", position = { 0, 0, 0 }, size = { 1000, 1000, 1000 } } },
}

local publishSaved = false
clientCloud = {
    userId = 7,
    BatchSet = function()
        local builder = {}
        function builder:Set() return self end
        function builder:SetInt() return self end
        function builder:Save(_, events) publishSaved = true; events.ok() end
        return builder
    end,
    GetRankList = function(_, _, _, _, events)
        events.ok({ {
            userId = 42,
            score = { island3d_model_market_profile_v1 = { items = { marketAsset, oversized, oversizedGeometry } } },
        } })
    end,
}
GetUserNickname = function(options)
    options.onSuccess({ { userId = 42, nickname = "创作者" } })
end

local ModelMarket = require("ModelMarket")
local marketResult
assert(ModelMarket.Load({
    ok = function(items, source) marketResult = items; Equal(source, "cloud", "market source") end,
    error = function(message) error(message) end,
}))
Equal(#marketResult, 1, "oversized market assets are rejected")
Equal(marketResult[1].assetId, "market:42:builtin:spoof", "remote public asset namespace")
Equal(marketResult[1].author, "创作者", "remote author nickname")
assert(marketResult[1].script == nil and #marketResult[1].components == 0,
    "remote script and dependency fields must be stripped")
assert(ModelMarket.Publish({ schema = "model-market-profile/v1", items = { marketAsset } }, {
    ok = function(source) Equal(source, "cloud", "publish source") end,
    error = function(message) error(message) end,
}))
assert(publishSaved, "market publish must commit the cloud batch")

print("model-system-spec: ok")
