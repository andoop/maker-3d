package.path = "scripts/?.lua;" .. package.path

local TransparentFaceIndex = require("TransparentFaceIndex")

local function Block(id, x, y, z, sx, sy, sz, material, rotation)
    return {
        id = id,
        position = { x, y, z },
        size = { sx, sy, sz },
        rotation = rotation or { 0, 0, 0 },
        materialId = material or "water",
    }
end

local source = Block("source", 0, 0, 0, 2, 2, 2)
local right = Block("right", 2, 0, 0, 2, 2, 2)
local topLarge = Block("top", 0, 2.5, 0, 4, 3, 4)
local wrongMaterial = Block("glass", 0, 0, 2, 2, 2, 2, "glass")
local partial = Block("partial", -2, 0.8, 0, 2, 1, 2)
local rotated = Block("rotated", 0, 0, -2, 2, 2, 2, "water", { 0, 0.2, 0 })
local ignoredOpaque = Block("opaque", 0, 0, -2, 2, 2, 2, "solid")
local blocks = { source, right, topLarge, wrongMaterial, partial, rotated, ignoredOpaque }
local index = TransparentFaceIndex.Build(blocks, function(block)
    return block.materialId ~= "solid" and block.materialId or nil
end)
local hidden = assert(TransparentFaceIndex.HiddenFaces(index, source, "water"))

assert(hidden["x+"], "a fully covering peer on the positive X plane must hide that face")
assert(hidden["y+"], "a larger peer sharing the positive Y plane must hide that face")
assert(not hidden["x-"], "a partial peer must not hide an uncovered face")
assert(not hidden["z+"], "a different transparent material must not hide the face")
assert(not hidden["z-"], "rotated blocks must stay out of the axis-aligned adjacency index")
assert(index.solid == nil, "resolver-filtered opaque blocks must not allocate face buckets")
assert(TransparentFaceIndex.HiddenFaces(index, rotated, "water") == nil,
    "rotated source geometry must preserve the established all-faces path")

local toleranceSource = Block("tolerance-source", 20, 0, 0, 2, 2, 2)
local tolerancePeer = Block("tolerance-peer", 22.0012, 0, 0, 2, 2, 2)
local toleranceIndex = TransparentFaceIndex.Build({ toleranceSource, tolerancePeer },
    function(block) return block.materialId end)
assert(TransparentFaceIndex.HiddenFaces(toleranceIndex, toleranceSource, "water")["x+"],
    "near-touching faces must keep the established 0.002 tolerance across hash buckets")

print("transparent-face-index-spec: ok")
