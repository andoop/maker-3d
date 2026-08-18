-- Broad-phase adjacency index for axis-aligned transparent blocks.
--
-- Water and glass hide their touching faces to avoid interior flicker.  The
-- old implementation compared every transparent block with every peer.  This
-- index records the six face planes once, so each block only examines peers
-- that can actually touch the queried face.

local ModelGeometry = require("ModelGeometry")

local TransparentFaceIndex = {}

local EPSILON = 0.002

local function PlaneKey(value)
    return tostring(math.floor((tonumber(value) or 0) / EPSILON + 0.5))
end

local function AddFace(axis, direction, plane, block)
    local directions = axis[direction]
    local key = PlaneKey(plane)
    local bucket = directions[key]
    if not bucket then
        bucket = {}
        directions[key] = bucket
    end
    bucket[#bucket + 1] = { block = block, plane = plane }
end

local function AxisAligned(block)
    local rx, ry, rz = ModelGeometry.Rotation(block)
    return math.abs(rx) <= 0.0001 and math.abs(ry) <= 0.0001 and math.abs(rz) <= 0.0001
end

---Build one face-plane index per normalized material ID.
---@param blocks table|nil
---@param materialFor function|nil
---@return table
function TransparentFaceIndex.Build(blocks, materialFor)
    local result = {}
    for _, block in ipairs(blocks or {}) do
        local resolvedMaterial = materialFor and materialFor(block) or nil
        -- A resolver can return nil to exclude opaque/non-box blocks. This
        -- keeps the index proportional to transparent geometry instead of to
        -- an entire detailed building.
        if AxisAligned(block) and (not materialFor or resolvedMaterial ~= nil) then
            local materialId = tostring(resolvedMaterial
                or block.materialId or block.material or "")
            local index = result[materialId]
            if not index then
                index = {
                    x = { negative = {}, positive = {} },
                    y = { negative = {}, positive = {} },
                    z = { negative = {}, positive = {} },
                }
                result[materialId] = index
            end
            local x, y, z = ModelGeometry.Position(block)
            local sx, sy, sz = ModelGeometry.Size(block)
            AddFace(index.x, "negative", x - sx * 0.5, block)
            AddFace(index.x, "positive", x + sx * 0.5, block)
            AddFace(index.y, "negative", y - sy * 0.5, block)
            AddFace(index.y, "positive", y + sy * 0.5, block)
            AddFace(index.z, "negative", z - sz * 0.5, block)
            AddFace(index.z, "positive", z + sz * 0.5, block)
        end
    end
    return result
end

local function Covered(sourceCenterA, sourceSizeA, sourceCenterB, sourceSizeB)
    return math.abs(sourceCenterB - sourceCenterA) + sourceSizeA * 0.5
        <= sourceSizeB * 0.5 + EPSILON
end

local function AxisValues(axis, x, y, z, sx, sy, sz)
    if axis == "x" then return x, sx end
    if axis == "y" then return y, sy end
    return z, sz
end

local function HasCoveringPeer(directionBuckets, facePlane, source, firstAxis, secondAxis)
    if not directionBuckets then return false end
    local x, y, z = ModelGeometry.Position(source)
    local sx, sy, sz = ModelGeometry.Size(source)
    local firstCenter, firstSize = AxisValues(firstAxis, x, y, z, sx, sy, sz)
    local secondCenter, secondSize = AxisValues(secondAxis, x, y, z, sx, sy, sz)
    local centerKey = tonumber(PlaneKey(facePlane)) or 0
    -- Adjacent quantization buckets are checked as well. Otherwise two faces
    -- only 0.001 apart could straddle a rounding boundary even though the
    -- established hidden-face tolerance is 0.002.
    for key = centerKey - 1, centerKey + 1 do
        for _, record in ipairs(directionBuckets[tostring(key)] or {}) do
            local other = record.block
            if other ~= source and math.abs((tonumber(record.plane) or 0) - facePlane) <= EPSILON then
                local ox, oy, oz = ModelGeometry.Position(other)
                local osx, osy, osz = ModelGeometry.Size(other)
                local otherFirstCenter, otherFirstSize = AxisValues(
                    firstAxis, ox, oy, oz, osx, osy, osz)
                local otherSecondCenter, otherSecondSize = AxisValues(
                    secondAxis, ox, oy, oz, osx, osy, osz)
                if Covered(firstCenter, firstSize, otherFirstCenter, otherFirstSize)
                    and Covered(secondCenter, secondSize, otherSecondCenter, otherSecondSize) then
                    return true
                end
            end
        end
    end
    return false
end

---Return the same six-direction mask consumed by TransparentBlockGeometry.
---@param indexes table|nil
---@param source table
---@param materialId string
---@return table|nil
function TransparentFaceIndex.HiddenFaces(indexes, source, materialId)
    if not AxisAligned(source) then return nil end
    local index = indexes and indexes[tostring(materialId or "")] or nil
    if not index then return {} end
    local x, y, z = ModelGeometry.Position(source)
    local sx, sy, sz = ModelGeometry.Size(source)
    local hidden = {}

    if HasCoveringPeer(index.x.negative, x + sx * 0.5, source, "y", "z") then
        hidden["x+"] = true
    end
    if HasCoveringPeer(index.x.positive, x - sx * 0.5, source, "y", "z") then
        hidden["x-"] = true
    end
    if HasCoveringPeer(index.y.negative, y + sy * 0.5, source, "x", "z") then
        hidden["y+"] = true
    end
    if HasCoveringPeer(index.y.positive, y - sy * 0.5, source, "x", "z") then
        hidden["y-"] = true
    end
    if HasCoveringPeer(index.z.negative, z + sz * 0.5, source, "x", "y") then
        hidden["z+"] = true
    end
    if HasCoveringPeer(index.z.positive, z - sz * 0.5, source, "x", "y") then
        hidden["z-"] = true
    end
    return hidden
end

return TransparentFaceIndex
