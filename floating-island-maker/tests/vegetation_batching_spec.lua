package.path = "scripts/?.lua;" .. package.path

-- Build-once geometry recipes use the Maker vector constructors.  Tiny table
-- stand-ins are sufficient here because the batch collector only reads x/y/z.
TRIANGLE_LIST = 0
Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
Vector2 = function(x, y) return { x = x, y = y } end

local THREE = require("urhox-libs/3D")
local Catalog = require("BlockCatalog")
local ModelGeometry = require("ModelGeometry")
local Library = require("AdventureTemplateLibrary")
local HtmlRoundedBoxGeometry = require("HtmlRoundedBoxGeometry")
local FullCylinderGeometry = require("FullCylinderGeometry")
local TriangularPrismGeometry = require("TriangularPrismGeometry")
local FacetedSolidGeometry = require("FacetedSolidGeometry")
local IslandModelBatcher = require("IslandModelBatcher")
local MobileDetailCost = require("MobileDetailCost")
local MobileRenderDetailPolicy = require("MobileRenderDetailPolicy")

local geometry = {
    box = HtmlRoundedBoxGeometry.new(1, 1, 1, 2, 0.075),
    sphere = THREE.SphereGeometry(0.5, 10, 7),
    cylinder = FullCylinderGeometry.new(12),
    cone = THREE.ConeGeometry(0.5, 1, 12, 1, false),
    tri_prism = TriangularPrismGeometry.new(),
    pyramid = FacetedSolidGeometry.SquarePyramid(),
    tetra = FacetedSolidGeometry.Tetrahedron(),
    torus = THREE.TorusGeometry(0.38, 0.12, 6, 16),
}

local function Transform(block)
    local x, y, z = ModelGeometry.Position(block)
    local sx, sy, sz = ModelGeometry.Size(block)
    local rx, ry, rz = ModelGeometry.Rotation(block)
    return THREE.Matrix4():compose(
        THREE.Vector3(x, y, z),
        THREE.Quaternion():setFromEuler(THREE.Euler(rx, ry, rz)),
        THREE.Vector3(sx, sy, sz)
    )
end

local batcher = IslandModelBatcher.new({
    three = THREE,
    geometryFor = function(block)
        local shapeId = Catalog.FindShape(block.shapeId or block.shape).id
        return geometry[shapeId] or geometry.box
    end,
    blockMatrix = Transform,
    describeBlock = function(block)
        local material = Catalog.FindMaterial(block.materialId or block.material)
        return {
            materialId = material.id,
            color = block.color,
            transparent = material.transparent == true,
            castShadow = false,
        }
    end,
    materialFor = function(materialId, color)
        return { materialId = materialId, color = color }
    end,
    modelFor = function(mergedGeometry)
        return { vertexCount = mergedGeometry:getAttribute("position").count }
    end,
    isEligible = function(asset)
        if #(asset.blocks or {}) > 48 then return false end
        for _, block in ipairs(asset.blocks or {}) do
            if Catalog.FindMaterial(block.materialId or block.material).transparent
                or ModelGeometry.CollisionRole(block) ~= "decorative"
                or ModelGeometry.ShouldCastShadow(block) then return false end
        end
        return #(asset.blocks or {}) > 0
    end,
    assetCacheKey = function(asset) return tostring(asset.id) .. "@mobile" end,
    maxVertices = 48000,
})

local vegetationCount, sourceBlocks, compiledParts, compiledVertices = 0, 0, 0, 0
local detailCandidates, maximumCostRatio = {}, 0
for _, asset in ipairs(Library.BuildAll()) do
    if asset.category == "植被单件" then
        vegetationCount = vegetationCount + 1
        assert(batcher:IsEligible(asset), asset.name .. " must remain safe for decorative batching")
        local compiled, errorMessage = batcher:Compile(asset)
        assert(compiled, asset.name .. " failed to compile: " .. tostring(errorMessage))
        assert(compiled.vertexCount > 0, asset.name .. " must publish its real render cost")
        sourceBlocks = sourceBlocks + #asset.blocks
        local detailCost = MobileDetailCost.EquivalentBlocks(#asset.blocks, compiled.vertexCount)
        maximumCostRatio = math.max(maximumCostRatio, detailCost / #asset.blocks)
        detailCandidates[#detailCandidates + 1] = {
            id = asset.id,
            projectedPixels = 1,
            distance = 20 + vegetationCount,
            blockCount = detailCost,
            minimumProjectedPixels = 0.8,
            retainedMinimumProjectedPixels = 0.5,
            coverageKey = tostring(vegetationCount) .. ":0",
        }
        compiledParts = compiledParts + #compiled.parts
        for _, part in ipairs(compiled.parts) do
            assert(part.vertexCount <= 48000, asset.name .. " exceeded the mobile vertex ceiling")
            compiledVertices = compiledVertices + part.vertexCount
        end
    end
end

assert(vegetationCount == 10, "all ten built-in vegetation assets must be covered")
assert(compiledParts < sourceBlocks * 0.5,
    "asset baking should cut vegetation render units by more than half")
assert(compiledVertices > 0, "real vegetation geometry must produce renderable triangles")
assert(maximumCostRatio > 2,
    "the fixture must prove why source-block counts cannot safely budget round foliage")
local detailPolicy = MobileRenderDetailPolicy.new({
    maxVisibleBlocks = 120,
    minimumProjectedPixels = 2.6,
    retainedMinimumProjectedPixels = 1.7,
    coverageBudgetFraction = 0.25,
    maxVisibilityChangesPerEvaluation = 32,
})
local _, detailStats = detailPolicy:Evaluate(detailCandidates, { mobile = true })
assert(detailStats.visibleBlocks <= 120,
    "first-frame vegetation admission must use compiled vertex cost without exceeding budget")

local copiedGrass
for _, asset in ipairs(Library.BuildAll()) do
    if tostring(asset.id):find("short%-grass%-tuft") then copiedGrass = asset; break end
end
assert(copiedGrass, "the short-grass fixture must exist")
copiedGrass.category = "我的模型"
copiedGrass.id = "user:copied-short-grass"
assert(batcher:IsEligible(copiedGrass),
    "copied/customised grass must stay protected after its category changes")

batcher:Dispose()
print(string.format(
    "vegetation-batching-spec: ok (%d assets, %d blocks -> %d parts, %d vertices)",
    vegetationCount, sourceBlocks, compiledParts, compiledVertices))
