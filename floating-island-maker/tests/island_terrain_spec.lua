package.path = "scripts/?.lua;" .. package.path

local TerrainCatalog = require("IslandTerrainCatalog")
local IslandLayout = require("IslandLayout")
local StorybookIslandData = require("StorybookIslandData")
local StorybookEnvironmentGeometry = require("StorybookEnvironmentGeometry")

_G.Color = function(...) return { ... } end
_G.Vector3 = function(...) return { ... } end
_G.TRIANGLE_LIST = 0

local function Near(actual, expected, message, epsilon)
    epsilon = epsilon or 0.0001
    assert(math.abs((tonumber(actual) or 0) - (tonumber(expected) or 0)) <= epsilon,
        (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function BuildVertexCount(source)
    local count = 0
    local geometry = {
        BeginGeometry = function() end,
        DefineVertex = function() count = count + 1 end,
        DefineNormal = function() end,
        DefineColor = function() end,
        Commit = function() end,
        SetMaterial = function() end,
    }
    source.build(source, { CreateComponent = function() return geometry end })
    return count
end

local expectedIds = {
    "storybook-triple-archipelago-large",
    "windstep-meadow",
    "cloudpine-spire",
    "moonbay-gardens",
    "starfall-ring",
    "twin-gate-highlands",
    "cascade-terraces",
    "sky-whale-ridge",
    "world-tree-spiral",
    "twin-vine-spiral",
}

local summaries = TerrainCatalog.List()
assert(#summaries == #expectedIds, "terrain catalog must expose exactly ten curated choices")
for index, expectedId in ipairs(expectedIds) do
    assert(summaries[index].id == expectedId, "terrain list order must remain deliberate")
    assert(summaries[index].name ~= "" and summaries[index].description ~= "",
        "every terrain needs concise Chinese presentation copy")
    assert(summaries[index].islandCount >= 1, "terrain summary must expose its island count")
end
assert(summaries[1].default and not summaries[2].default, "only the classic three-island terrain is default")
assert(IslandLayout.ResolveId(nil) == expectedIds[1]
    and IslandLayout.ResolveId("unknown-terrain") == expectedIds[1]
    and IslandLayout.ResolveId("storybook-triple-archipelago") == expectedIds[1],
    "missing, unknown and legacy terrain ids must resolve safely")
assert(IslandLayout.ResolveId({ id = "windstep-meadow" }) == "windstep-meadow"
    and IslandLayout.ResolveId({ terrainId = "cloudpine-spire" }) == "cloudpine-spire"
    and IslandLayout.ResolveId({ preset = "moonbay-gardens" }) == "moonbay-gardens",
    "terrain ids carried by UI, project and legacy terrain records must all resolve")

local mutableCopy = TerrainCatalog.Get("windstep-meadow")
mutableCopy.islands[1].x = 999
assert(TerrainCatalog.Get("windstep-meadow").islands[1].x ~= 999,
    "catalog callers must not mutate authored terrain records")

local default = IslandLayout.Resolve(expectedIds[1])
assert(default.id == IslandLayout.TERRAIN_PRESET and #default.islands == 3 and #default.bridges == 3,
    "default terrain must preserve the existing triangular archipelago")
Near(default:GetIsland("heart").x, 0, "default central island x")
Near(default:GetIsland("heart").z, -16, "default central island z")
Near(default:GetIsland("heart").groundY, 0.42, "default central island height")
local defaultOverview = default:Overview()
Near(defaultOverview.x, 0, "default overview x")
Near(defaultOverview.y, -1.0, "default overview y")
Near(defaultOverview.z, 7, "default overview z")
Near(defaultOverview.radius, 118, "default overview radius")

-- The compatibility facade remains byte-for-byte meaningful to existing
-- callers while new worlds resolve independent layout instances.
assert(#IslandLayout.ISLANDS == 3 and #IslandLayout.BRIDGES == 3,
    "legacy facade must continue to expose the original three islands")
assert(IslandLayout.ContainsPoint(0, -16, 0.42)
    and IslandLayout.ContainsPoint(-22, 4, 0.42),
    "legacy facade must preserve island and bridge traversal")
assert(not IslandLayout.ContainsPoint(29.2, -16, 0.42),
    "legacy facade must preserve the original edge inset")
local defaultBridge = assert(default:GetBridgeMetrics(default.bridges[1]))
local paddedLandingDistance = defaultBridge.startDistance - 0.40
assert(default:ContainsPoint(
    defaultBridge.first.x + defaultBridge.ux * paddedLandingDistance,
    defaultBridge.first.z + defaultBridge.uz * paddedLandingDistance,
    0.42), "character padding must not open a collision gap at bridge landings")

local expectedCounts = {
    ["windstep-meadow"] = 7,
    ["cloudpine-spire"] = 7,
    ["moonbay-gardens"] = 7,
    ["starfall-ring"] = 6,
    ["twin-gate-highlands"] = 6,
    ["cascade-terraces"] = 7,
    ["sky-whale-ridge"] = 7,
    ["world-tree-spiral"] = 9,
    ["twin-vine-spiral"] = 10,
}
local simple = {
    bounds = {
        min = { -0.5, 0, -0.5 }, max = { 0.5, 1, 0.5 }, size = { 1, 1, 1 },
    },
}

for _, terrainId in ipairs(expectedIds) do
    local layout = IslandLayout.Resolve(terrainId)
    local storybook = StorybookIslandData.Build(layout)
    assert(layout.id == terrainId and layout.TERRAIN_PRESET == terrainId,
        "resolved layout must retain its canonical terrain id")
    assert(storybook.terrainId == terrainId and #storybook.islands == #layout.islands,
        "storybook generation must use the selected terrain instead of the default layout")
    assert(layout.camera and layout.camera.target and layout.renderDistance.cameraFar > layout.renderDistance.skyRadius,
        "every terrain needs an authored camera and safe far plane")
    local maximumOrbitRadius = layout:MaximumOrbitRadius()
    assert(maximumOrbitRadius >= layout:Overview().radius,
        "every terrain must zoom at least as far out as its authored overview")
    assert(maximumOrbitRadius > 180 and maximumOrbitRadius < layout.renderDistance.cameraFar,
        "orbit zoom-out must exceed the legacy fixed cap without reaching the far plane")
    if terrainId == "twin-vine-spiral" then
        assert(maximumOrbitRadius > 380,
            "the ten-island terrain must support a substantially wider overview")
    end
    if expectedCounts[terrainId] then
        assert(#layout.islands == expectedCounts[terrainId],
            "new terrain must preserve its deliberately authored main and satellite landmasses")
    end

    local uniqueIds = {}
    for _, island in ipairs(layout.islands) do
        assert(not uniqueIds[island.id], "island ids must be unique inside a terrain")
        uniqueIds[island.id] = true
        assert(island.radiusX > 0 and island.radiusZ > 0 and island.focusRadius > 0,
            "islands need usable elliptical bounds and focus framing")
        local surfaceY, kind, source = layout:SurfaceAt(island.x, island.z, 0)
        Near(surfaceY, island.groundY, terrainId .. " centre surface")
        assert(kind == "island" and source.id == island.id,
            "island centres must resolve to their authored surface")
        assert(layout:ContainsPoint(
            island.x + island.radiusX * 0.6,
            island.z + island.radiusZ * 0.6,
            0), "elliptical island interior must be walkable")
        local valid, reason = layout:IsPlacementValid({}, simple, island.x, island.z, 0, 1)
        assert(valid, terrainId .. " island centre must accept a small model: " .. tostring(reason))

        local hit = layout:RaycastGround({
            origin = { x = island.x, y = island.groundY + 30, z = island.z },
            direction = { x = 0, y = -1, z = 0 },
        })
        assert(hit and hit.kind == "island" and hit.id == island.id,
            "vertical terrain ray must hit the intended island")
        Near(hit.y, island.groundY, terrainId .. " ray height")
    end

    for firstIndex = 1, #layout.islands - 1 do
        local first = layout.islands[firstIndex]
        for secondIndex = firstIndex + 1, #layout.islands do
            local second = layout.islands[secondIndex]
            local dx, dz = second.x - first.x, second.z - first.z
            local radiusX = first.radiusX + second.radiusX
            local radiusZ = first.radiusZ + second.radiusZ
            assert(dx * dx / (radiusX * radiusX) + dz * dz / (radiusZ * radiusZ) > 1.05,
                terrainId .. " authored island masses must have a visible air gap")
        end
    end

    for _, bridge in ipairs(layout.bridges) do
        assert(bridge.broken ~= false,
            terrainId .. " connectors must use the shared shattered bridge language")
        local metrics = assert(layout:GetBridgeMetrics(bridge), "bridge endpoints must resolve")
        local middleX = (metrics.startX + metrics.endX) * 0.5
        local middleZ = (metrics.startZ + metrics.endZ) * 0.5
        local surfaceY, kind, source = layout:SurfaceAt(middleX, middleZ, 0)
        Near(surfaceY, (metrics.startY + metrics.endY) * 0.5,
            terrainId .. " bridge midpoint height", 0.001)
        assert(kind == "bridge" and source == bridge and layout:ContainsPoint(middleX, middleZ, 0),
            "bridge midpoint must be a walkable interpolated surface")
        for _, padding in ipairs({ 0, 0.22, 0.42 }) do
            for sample = 0, 800 do
                local along = metrics.distance * sample / 800
                local x = metrics.first.x + metrics.ux * along
                local z = metrics.first.z + metrics.uz * along
                assert(layout:ContainsPoint(x, z, padding),
                    string.format("%s bridge %s has a %.3fm seam at %.3f padding",
                        terrainId, tostring(bridge.id), along, padding))
            end
        end
        for sample = 0, 100 do
            local along = metrics.distance * sample / 100
            local x = metrics.first.x + metrics.ux * along
            local z = metrics.first.z + metrics.uz * along
            local expectedY = assert(layout:SurfaceAt(x, z, 0))
            local hit = assert(layout:RaycastGround({
                origin = { x = x, y = layout:MaximumGroundY() + 30, z = z },
                direction = { x = 0, y = -1, z = 0 },
            }))
            Near(hit.y, expectedY, terrainId .. " ray and logical ground seam", 0.001)
        end
    end
    assert(#storybook.bridgeSpans == #layout.bridges,
        "every logical bridge must have one rendered span")
    for bridgeIndex, bridge in ipairs(layout.bridges) do
        local metrics = assert(layout:GetBridgeMetrics(bridge))
        local span = assert(storybook.bridgeSpans[bridgeIndex])
        Near(span.startY, metrics.startY, terrainId .. " rendered bridge start height")
        Near(span.endY, metrics.endY, terrainId .. " rendered bridge end height")
        assert(span.broken == true and type(span.rotationY) == "number",
            "rendered connectors must retain broken styling and path-aligned rotation")
        assert(span.steps >= math.ceil(math.abs(metrics.endY - metrics.startY)
                / math.max(0.18, bridge.maxStepHeight or 0.24)),
            "rendered bridge steps must respect the authored vertical step limit")
        if terrainId ~= TerrainCatalog.DEFAULT_ID then
            assert(metrics.length / span.steps >= 1.60,
                terrainId .. " stairs must stay spacious instead of stacking crowded tiles")
        end
    end
    if terrainId ~= TerrainCatalog.DEFAULT_ID then
        local preset = TerrainCatalog.Get(terrainId)
        assert(preset.pureTerrain == true and preset.formation ~= nil,
            "new presets must identify themselves as authored pure terrain")
        assert(#storybook.decorRocks == 0 and #storybook.shrubs == 0 and #storybook.moss == 0,
            "new terrain surfaces must not receive decorative rocks, shrubs or moss props")
        assert(#storybook.terrainWater == 0 and #storybook.terrainFoliage == 0,
            "new terrains must not inject ponds, waterfalls, trees or flowers")
        assert(#storybook.distantStructures == 0 and #storybook.distantFoliage == 0,
            "pure terrain presets must keep distant islands geological too")
        assert(#storybook.terrainAccents > 0,
            "new terrains still need authored geological arches, ribs or pillars")
        for _, block in ipairs(storybook.terrainAccents) do
            assert(type(block.landform) == "string" and block.landform ~= "",
                "every terrain accent must be explicitly geological, never an unlabelled prop")
        end
    end
    local cloudChunks = StorybookEnvironmentGeometry.CloudChunks(storybook.cloudsNear, 8, 14)
    assert(#cloudChunks >= 1, "every terrain must render at least one near-cloud chunk")
    for chunkIndex, chunk in ipairs(cloudChunks) do
        assert(BuildVertexCount(StorybookEnvironmentGeometry.Clouds(chunk, 8, 14)) < 65535,
            terrainId .. " near-cloud chunk " .. tostring(chunkIndex)
                .. " must remain inside the mobile 16-bit CustomGeometry limit")
    end
end

local windstep = IslandLayout.Resolve("windstep-meadow")
local windstepData = StorybookIslandData.Build(windstep)
assert(windstep:GetIsland("west-arc").radiusZ > windstep:GetIsland("west-arc").radiusX,
    "wind ring must use a long cliff arc instead of a generic round platform")
assert(windstep:MaximumGroundY() - windstep:MinimumGroundY() > 11,
    "wind ring needs a dramatic high-to-low satellite silhouette")
assert(not windstep:ContainsPoint(3, 0, 0),
    "wind ring needs a broad empty centre matching the reference negative space")
assert(#windstep.bridges == #windstep.islands,
    "wind ring needs one connected outer cycle plus its central shard route")
local windKinds = {}
for _, block in ipairs(windstepData.terrainAccents) do windKinds[block.landform] = true end
assert(windKinds["wind-ring-rib"] and windKinds["wind-monolith"],
    "wind ring needs cliff ribs and suspended geological monoliths")

local cloudpine = IslandLayout.Resolve("cloudpine-spire")
local cloudpineData = StorybookIslandData.Build(cloudpine)
assert(cloudpine:MaximumGroundY() - cloudpine:MinimumGroundY() > 20,
    "sky pillar must be the strongly vertical terrain")
local cloudKinds = {}
for _, block in ipairs(cloudpineData.terrainAccents) do cloudKinds[block.landform] = true end
assert(cloudKinds["sky-spine"] and cloudKinds["lower-arch"] and cloudKinds["upper-arch"],
    "sky pillar needs a stratified central mountain and two hollow geological arches")
for _, bridge in ipairs(cloudpine.bridges) do
    assert(bridge.broken ~= false,
        "the mountain ascent must use the same broken floating-slab language")
end
local steepBridge = cloudpine.bridges[1]
local steepMetrics = assert(cloudpine:GetBridgeMetrics(steepBridge))
local function BridgePoint(amount)
    local along = steepMetrics.startDistance + steepMetrics.length * amount
    return {
        x = steepMetrics.first.x + steepMetrics.ux * along,
        z = steepMetrics.first.z + steepMetrics.uz * along,
    }
end
local middle = BridgePoint(0.5)
local uneven = {
    x = middle.x, z = middle.z,
    corners = { BridgePoint(0.35), BridgePoint(0.35), BridgePoint(0.65), BridgePoint(0.65) },
}
local supported, supportReason = cloudpine:IsFootprintSupported(uneven)
assert(not supported and supportReason == "uneven_ground",
    "models must not straddle a visibly sloped bridge surface")

local moonbay = IslandLayout.Resolve("moonbay-gardens")
local moonbayData = StorybookIslandData.Build(moonbay)
assert(#moonbay.islands == 7 and #moonbay.bridges == 6,
    "moon rift must read as two long crescents, twin horns, a gate and satellites")
assert(moonbay:MaximumGroundY() - moonbay:MinimumGroundY() > 20,
    "moon rift needs genuinely high horns and a deeply fallen satellite")
assert(not moonbay:ContainsPoint(0, -52, 0),
    "moon rift must keep a visible canyon below its natural stone gate")
local moonKinds = {}
for _, block in ipairs(moonbayData.terrainAccents) do moonKinds[block.landform] = true end
assert(moonKinds["eclipse-arch"] and moonKinds["moon-needle"],
    "moon rift needs a suspended natural arch and flanking cliff needles")

local worldTree = IslandLayout.Resolve("world-tree-spiral")
local worldTreeData = StorybookIslandData.Build(worldTree)
assert(#worldTree.islands == 9 and #worldTree.bridges == 8,
    "world tree must expose one continuous nine-level spiral ascent")
assert(worldTree:MaximumGroundY() - worldTree:MinimumGroundY() >= 40,
    "world tree needs a dramatic root-to-crown height range")
for index, bridge in ipairs(worldTree.bridges) do
    local first, second = worldTree:GetIsland(bridge.from), worldTree:GetIsland(bridge.to)
    assert(first and second and second.groundY > first.groundY,
        "world tree bridge " .. tostring(index) .. " must always climb toward the crown")
    assert(bridge.broken == true and bridge.style == "shattered-stepping-stones",
        "world tree must use the shared spacious shattered path language")
end
local worldTreeKinds = {}
for _, block in ipairs(worldTreeData.terrainAccents) do worldTreeKinds[block.landform] = true end
assert(worldTreeKinds["world-tree-trunk"] and worldTreeKinds["world-tree-bark-spiral"]
    and worldTreeKinds["world-tree-root-rib"] and worldTreeKinds["world-tree-crown-rib"],
    "world tree needs a central trunk, a visible spiral and distinct root and crown masses")

local twinVine = IslandLayout.Resolve("twin-vine-spiral")
local twinVineData = StorybookIslandData.Build(twinVine)
assert(#twinVine.islands == 10 and #twinVine.bridges == 10,
    "twin vine terrain must expose two complete climbing routes to one crown")
assert(twinVine:MaximumGroundY() - twinVine:MinimumGroundY() >= 28,
    "twin vine terrain needs a clearly layered vertical silhouette")
local crownEntrances = 0
for _, bridge in ipairs(twinVine.bridges) do
    local first, second = twinVine:GetIsland(bridge.from), twinVine:GetIsland(bridge.to)
    assert(first and second and second.groundY > first.groundY,
        "each twin vine path segment must climb instead of doubling back vertically")
    if bridge.to == "star-crown" then crownEntrances = crownEntrances + 1 end
    assert(bridge.broken == true and bridge.style == "shattered-stepping-stones",
        "both vine routes must retain the shared broken stepping-stone style")
end
assert(crownEntrances == 2, "both vine routes must independently reach the crown")
local twinVineKinds = {}
for _, block in ipairs(twinVineData.terrainAccents) do twinVineKinds[block.landform] = true end
assert(twinVineKinds["west-vine-spine"] and twinVineKinds["east-vine-spine"]
    and twinVineKinds["twin-vine-root-rib"] and twinVineKinds["twin-vine-crown-rib"],
    "twin vine terrain needs two readable spiral cores plus rooted and crowned endpoints")

assert(IslandLayout.Resolve("windstep-meadow") ~= IslandLayout.Resolve("windstep-meadow"),
    "resolved layouts must not share mutable runtime state")

print("island-terrain-spec: ok (classic plus 9 spacious pure-landform fantasy terrains)")
