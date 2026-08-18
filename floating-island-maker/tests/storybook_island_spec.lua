package.path = "scripts/?.lua;" .. package.path

local StorybookIslandData = require("StorybookIslandData")
local StorybookEnvironmentGeometry = require("StorybookEnvironmentGeometry")
local Theme = require("CloudAtelierTheme")
local IslandLayout = require("IslandLayout")

local data = StorybookIslandData.Build()
assert(#data.islands == 3, "the storybook world must contain three authored islands")
local foundation = { data.grass, data.soil, data.rockUpper, data.rockLower, data.rockTip }
local foundationCount = 0
local palette = {}
for _, layer in ipairs(foundation) do
    assert(#layer > 0, "every storybook stratum must contain detailed cells")
    for _, block in ipairs(layer) do
        foundationCount = foundationCount + 1
        assert(block.sx > 0 and block.sy > 0 and block.sz > 0, "island cells must have valid dimensions")
        assert(block.sx <= 2.90 and block.sz <= 2.90,
            "doubled island foundation must keep proportionally small cells")
        assert((block.bevel or 0) > 0, "every island cell must have a bevel")
        palette[block.color] = true
    end
end

assert(foundationCount == 1720, "hollow doubled-island foundation cell count changed unexpectedly")
assert(#data.grass == 864 and #data.soil == 365, "doubled islands need a complete top and hollow soil shells")
assert(#data.rockUpper > #data.rockLower and #data.rockLower > #data.rockTip,
    "rock layers must taper toward the floating island tip")
assert(data.ocean == nil, "the reference scene must not create ocean geometry")
assert(IslandLayout.RENDER_DISTANCE.skyRadius >= 600
    and IslandLayout.RENDER_DISTANCE.cameraFar >= IslandLayout.RENDER_DISTANCE.skyRadius * 2,
    "distant islands need a sky dome and camera depth safely beyond every orbit angle")
assert(#data.bridgeGrass >= 24 and #data.bridgeGrass <= 42 and #data.bridgeFragments >= 6,
    "three bridges need sparse edge-to-edge routes, visible gaps and fallen fragments")
assert(#data.bridgeSpans == #IslandLayout.BRIDGES, "every authored route needs one visible bridge span")
local islandById = {}
for _, island in ipairs(data.islands) do islandById[island.id] = island end
for _, span in ipairs(data.bridgeSpans) do
    local first, second = islandById[span.from], islandById[span.to]
    assert(math.abs(span.startDistance - first.radius) < 0.5,
        "bridge rendering must begin at the first island edge, not its centre")
    local remainingAtEnd = math.sqrt((second.x - first.x) ^ 2 + (second.z - first.z) ^ 2) - span.endDistance
    assert(math.abs(remainingAtEnd - second.radius) < 0.5,
        "bridge rendering must stop at the second island edge, not continue beneath it")
    assert(span.broken == true and type(span.rotationY) == "number",
        "every authored route must use the path-aligned shattered bridge style")
end
local rotatedBridgeBlocks = 0
for _, block in ipairs(data.bridgeGrass) do
    if type(block.ry) == "number" and math.abs(block.ry) > 0.05 then
        rotatedBridgeBlocks = rotatedBridgeBlocks + 1
    end
end
assert(rotatedBridgeBlocks >= math.floor(#data.bridgeGrass * 0.6),
    "bridge slabs must follow their routes instead of forming diagonal checkerboard roads")
assert(#data.cloudsNear == 90 and #data.cloudsLow == 60 and #data.cloudsMid == 72
    and #data.cloudsHigh == 40 and #data.cloudsFar == 70,
    "five cloud depth bands must remain deliberately populated")
assert(#data.clouds == 332, "all five detached cloud depth bands must enter the environment")
assert(#data.distantIslands == 21 and #data.distantGrass == 216
    and #data.distantSoil == 216 and #data.distantRock == 458,
    "the horizon needs multi-scale detailed floating island foundations")
assert(#data.distantStructures == 219 and #data.distantFoliage == 116,
    "themed distant islands need readable landmarks and layered vegetation")
local distantTierCounts = { near = 0, mid = 0, far = 0, horizon = 0 }
local minimumDistance, maximumDistance = math.huge, 0
local minimumHeight, maximumHeight = math.huge, -math.huge
local themes, sizeClasses = {}, {}
for _, island in ipairs(data.distantIslands) do
    distantTierCounts[island.tier] = distantTierCounts[island.tier] + 1
    themes[island.theme], sizeClasses[island.sizeClass] = true, true
    minimumDistance, maximumDistance = math.min(minimumDistance, island.distance), math.max(maximumDistance, island.distance)
    minimumHeight, maximumHeight = math.min(minimumHeight, island.y), math.max(maximumHeight, island.y)
    assert(island.detailCount > 0, "every background island needs a themed landmark")
    assert(island.pieceCount >= 6 and island.grassCount == island.pieceCount,
        "background island size must come from a deliberately authored foundation")
    if island.tier == "near" then assert(island.distance > 110 and island.distance < 155 and island.scale >= 1.4)
    elseif island.tier == "mid" then assert(island.distance > 165 and island.distance < 210)
    elseif island.tier == "far" then assert(island.distance > 230 and island.distance < 280)
    else assert(island.tier == "horizon" and island.distance > 285 and island.distance < 315
        and island.scale <= 0.4) end

end
assert(distantTierCounts.near == 4 and distantTierCounts.mid == 6
    and distantTierCounts.far == 6 and distantTierCounts.horizon == 5,
    "distant islands must form four readable perspective bands")
local themeCount = 0
for _ in pairs(themes) do themeCount = themeCount + 1 end
assert(themeCount >= 14, "background islands need distinct themes rather than repeated silhouettes")
assert(sizeClasses.large and sizeClasses.medium and sizeClasses.small and sizeClasses.tiny,
    "background islands need a genuine large-to-tiny scale hierarchy")
assert(minimumDistance < 115 and maximumDistance > 305,
    "background islands need a deep near-to-horizon distance range")
assert(minimumHeight <= -8 and maximumHeight >= 54,
    "background islands need high and low silhouettes instead of a flat ring")
for islandIndex, island in ipairs(data.islands) do
    for cloudIndex = (islandIndex - 1) * 30 + 1, islandIndex * 30 do
        local cloud = data.cloudsNear[cloudIndex]
        local dx, dz = cloud.x - island.x, cloud.z - island.z
        local edgeDistance = math.sqrt(dx * dx + dz * dz) - math.max(cloud.rx, cloud.rz)
        assert(edgeDistance > island.radius + 3.5,
            "island-following clouds must leave a visible sky gap around the stone edge")
    end
end
assert(#data.fragments >= 20 and #data.moss >= 15, "all three undersides need fragments and moss ledges")

local paletteCount = 0
for _ in pairs(palette) do paletteCount = paletteCount + 1 end
assert(paletteCount >= 12, "small island cells need meaningful tonal variation")
local themedIslandColors = {}
for key, colors in pairs(Theme.ENVIRONMENT.island) do
    if type(colors) == "table" then
        for _, color in ipairs(colors) do themedIslandColors[color] = true end
    elseif key ~= "shrubDark" and key ~= "shrubLight" then
        themedIslandColors[colors] = true
    end
end
for color in pairs(palette) do
    assert(themedIslandColors[color], "island foundation color drifted outside cloud atelier theme")
end

for _, block in ipairs(data.grass) do
    assert(math.abs(block.y + block.sy * 0.5 - 0.42) < 0.0001,
        "all grass cells must preserve one walkable ground plane")
end

for _, island in ipairs(data.islands) do
    local grassAtCentre, tipAtCentre = false, false
    for _, block in ipairs(island.grass) do
        local dx, dz = block.x - island.x, block.z - island.z
        if dx * dx + dz * dz < 1 then grassAtCentre = true end
    end
    for _, block in ipairs(island.rockTip) do
        local dx, dz = block.x - island.x, block.z - island.z
        if dx * dx + dz * dz < 1 then tipAtCentre = true end
    end
    assert(grassAtCentre and tipAtCentre, "hollow islands must stay visually sealed above and below")
    for _, layer in ipairs({ island.soil, island.rockUpper, island.rockLower }) do
        for _, block in ipairs(layer) do
            local dx, dz = block.x - island.x, block.z - island.z
            assert(dx * dx + dz * dz > 25,
                "soil and rock bodies must remain hollow instead of filling invisible interiors")
        end
    end
end

assert(StorybookEnvironmentGeometry.Blocks(data.grass).build,
    "small cells must be mergeable into one mobile-friendly geometry")
assert(StorybookEnvironmentGeometry.Clouds(data.clouds).build,
    "cloud lobes must be mergeable into one mobile-friendly geometry")
assert(StorybookEnvironmentGeometry.SkyDome().build,
    "the lower sea-colour hint must come from a sky gradient, not ocean geometry")

-- Exercise the real CustomGeometry recipes with lightweight engine stubs.
-- Keeping each merged batch below 65,535 non-indexed vertices avoids the
-- common mobile 16-bit geometry limit while retaining all visible small cells.
TRIANGLE_LIST = 0
Vector3 = function(x, y, z) return { x, y, z } end
Color = function(r, g, b, a) return { r, g, b, a } end
local function BuildVertexCount(recipe)
    local geometry = { vertices = 0 }
    function geometry:BeginGeometry() end
    function geometry:DefineVertex() self.vertices = self.vertices + 1 end
    function geometry:DefineNormal() end
    function geometry:DefineColor() end
    function geometry:Commit() end
    local node = {}
    function node:CreateComponent() return geometry end
    recipe.build(recipe, node, nil)
    return geometry.vertices
end

local grassVertices = 0
for _, island in ipairs(data.islands) do
    local vertices = BuildVertexCount(StorybookEnvironmentGeometry.Blocks(island.grass))
    assert(vertices < 65535, "each island grass batch must fit mobile 16-bit geometry")
    grassVertices = grassVertices + vertices
end
local nearCloudVertices = BuildVertexCount(StorybookEnvironmentGeometry.Clouds(data.cloudsNear, 8, 14))
local lowCloudVertices = BuildVertexCount(StorybookEnvironmentGeometry.Clouds(data.cloudsLow, 6, 12))
local midCloudVertices = BuildVertexCount(StorybookEnvironmentGeometry.Clouds(data.cloudsMid, 6, 12))
local highCloudVertices = BuildVertexCount(StorybookEnvironmentGeometry.Clouds(data.cloudsHigh, 5, 10))
local farCloudVertices = BuildVertexCount(StorybookEnvironmentGeometry.Clouds(data.cloudsFar, 5, 10))
local skyVertices = BuildVertexCount(StorybookEnvironmentGeometry.SkyDome())
assert(grassVertices == #data.grass * 132, "all island grass cells must enter a merged batch")
assert(nearCloudVertices == #data.cloudsNear * 8 * 14 * 6 and nearCloudVertices < 65535,
    "root clouds must remain one safe merged mobile batch")
assert(lowCloudVertices == #data.cloudsLow * 6 * 12 * 6 and lowCloudVertices < 65535,
    "low cloud ribbons must remain one safe merged mobile batch")
assert(midCloudVertices == #data.cloudsMid * 6 * 12 * 6 and midCloudVertices < 65535,
    "mid cloud towers must remain one safe merged mobile batch")
assert(highCloudVertices == #data.cloudsHigh * 5 * 10 * 6 and highCloudVertices < 65535,
    "high cloud wisps must remain one safe merged mobile batch")
assert(farCloudVertices == #data.cloudsFar * 5 * 10 * 6 and farCloudVertices < 65535,
    "horizon cloud banks must remain one safe merged mobile batch")
assert(BuildVertexCount(StorybookEnvironmentGeometry.Blocks(data.distantRock)) < 65535,
    "distant island rock detail must remain one safe merged mobile batch")
assert(BuildVertexCount(StorybookEnvironmentGeometry.Blocks(data.distantStructures)) < 65535,
    "distant island landmarks must remain one safe merged mobile batch")
assert(BuildVertexCount(StorybookEnvironmentGeometry.Clouds(data.distantFoliage, 6, 10)) < 65535,
    "distant island vegetation must remain one safe merged mobile batch")
assert(skyVertices == 16 * 32 * 6, "sky gradient dome topology changed unexpectedly")

print(string.format(
    "storybook-island-spec: ok (%d foundation cells, %d distant islands, %d cloud lobes, %d+%d+%d+%d+%d cloud vertices)",
    foundationCount, #data.distantIslands, #data.clouds,
    nearCloudVertices, lowCloudVertices, midCloudVertices, highCloudVertices, farCloudVertices
))
