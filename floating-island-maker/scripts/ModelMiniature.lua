-- Engine-independent 2D miniatures for user/market models that do not have a
-- pre-rendered PNG. The UI draws these descriptors as a tiny model-derived
-- isometric silhouette, so every model card remains recognizable.

local ModelMiniature = {}

local MATERIAL_COLORS = {
    grass = { 113, 170, 84, 238 }, wood = { 151, 104, 69, 238 },
    carved_stone = { 137, 151, 156, 238 }, stone = { 132, 145, 151, 238 },
    glass = { 113, 205, 217, 190 }, water = { 69, 157, 218, 190 },
    metal = { 170, 175, 180, 238 }, glow = { 255, 222, 111, 244 },
    sand = { 222, 190, 119, 238 }, marble = { 224, 218, 204, 238 },
}

local function Color(value, materialId)
    if type(value) == "number" then
        return { math.floor(value / 0x10000) % 0x100,
            math.floor(value / 0x100) % 0x100, value % 0x100, 238 }
    end
    local text = tostring(value or "")
    local red, green, blue = text:match("^#(%x%x)(%x%x)(%x%x)$")
    if red then return { tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16), 238 } end
    local fallback = MATERIAL_COLORS[tostring(materialId or "")]
    if fallback then return { fallback[1], fallback[2], fallback[3], fallback[4] } end
    return { 105, 161, 181, 238 }
end

local function Number(source, index, fallback)
    return tonumber(type(source) == "table" and source[index]) or fallback
end

local function Candidate(block, index)
    local position, size = block.position or {}, block.size or {}
    local x, y, z = Number(position, 1, 0), Number(position, 2, 0), Number(position, 3, 0)
    local sx, sy, sz = math.max(0.02, Number(size, 1, 1)),
        math.max(0.02, Number(size, 2, 1)), math.max(0.02, Number(size, 3, 1))
    return {
        index = index, x = x, y = y, z = z, sx = sx, sy = sy, sz = sz,
        volume = sx * sy * sz,
        shapeId = tostring(block.shapeId or "box"),
        color = Color(block.color, block.materialId),
    }
end

local function RepresentativeBlocks(asset, limit)
    local candidates = {}
    for index, block in ipairs(type(asset and asset.blocks) == "table" and asset.blocks or {}) do
        candidates[#candidates + 1] = Candidate(block, index)
    end
    table.sort(candidates, function(first, second)
        if first.volume ~= second.volume then return first.volume > second.volume end
        return first.index < second.index
    end)
    local selected = {}
    for index = 1, math.min(math.max(1, limit or 12), #candidates) do
        selected[index] = candidates[index]
    end
    table.sort(selected, function(first, second)
        local firstDepth, secondDepth = first.x + first.z + first.y * 0.08,
            second.x + second.z + second.y * 0.08
        if firstDepth ~= secondDepth then return firstDepth < secondDepth end
        return first.index < second.index
    end)
    return selected
end

function ModelMiniature.Parts(asset, limit)
    local blocks = RepresentativeBlocks(asset, limit)
    if #blocks == 0 then return {} end
    local raw, minimumX, maximumX, minimumY, maximumY = {}, math.huge, -math.huge, math.huge, -math.huge
    for _, block in ipairs(blocks) do
        local centerX = block.x - block.z * 0.72
        local centerY = (block.x + block.z) * 0.30 - block.y
        local width = math.max(0.12, block.sx + block.sz * 0.72)
        local height = math.max(0.12, block.sy + (block.sx + block.sz) * 0.13)
        local part = {
            left = centerX - width * 0.5, top = centerY - height * 0.5,
            width = width, height = height, color = block.color,
            round = block.shapeId == "sphere" or block.shapeId == "cylinder"
                or block.shapeId == "torus",
        }
        raw[#raw + 1] = part
        minimumX, maximumX = math.min(minimumX, part.left), math.max(maximumX, part.left + width)
        minimumY, maximumY = math.min(minimumY, part.top), math.max(maximumY, part.top + height)
    end
    local rangeX, rangeY = math.max(0.001, maximumX - minimumX), math.max(0.001, maximumY - minimumY)
    local scale = 0.84 / math.max(rangeX, rangeY)
    local contentWidth, contentHeight = rangeX * scale, rangeY * scale
    local offsetX, offsetY = (1 - contentWidth) * 0.5, (1 - contentHeight) * 0.5
    local result = {}
    for _, part in ipairs(raw) do
        result[#result + 1] = {
            x = offsetX + (part.left - minimumX) * scale,
            y = offsetY + (part.top - minimumY) * scale,
            width = math.max(0.045, part.width * scale),
            height = math.max(0.045, part.height * scale),
            color = part.color, round = part.round,
        }
    end
    return result
end

return ModelMiniature
