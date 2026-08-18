-- Emits the canonical built-in model geometry as a compact tab-separated
-- stream for generate_model_thumbnails.py. Keeping model construction in Lua
-- guarantees thumbnails follow the exact blocks used by the game.
package.path = "scripts/?.lua;" .. package.path

local BuiltinTemplates = require("BuiltinTemplates")
local ModelAssetStore = require("ModelAssetStore")

local function Field(value)
    local text = tostring(value or "")
    local sanitized = text:gsub("[\t\r\n]", " ")
    return sanitized
end

local store = ModelAssetStore.new(BuiltinTemplates.BuildAll())
for _, asset in ipairs(store:GetAssets("builtin")) do
    print(table.concat({
        "A", Field(asset.assetId), Field(asset.thumbnail), Field(asset.name),
        Field(asset.category), tostring(#(asset.blocks or {})),
    }, "\t"))
    for index, block in ipairs(asset.blocks or {}) do
        local position, size, rotation = block.position or {}, block.size or {}, block.rotation or {}
        print(table.concat({
            "B", Field(asset.assetId), tostring(index),
            tostring(position[1] or 0), tostring(position[2] or 0), tostring(position[3] or 0),
            tostring(size[1] or 1), tostring(size[2] or 1), tostring(size[3] or 1),
            tostring(rotation[1] or 0), tostring(rotation[2] or 0), tostring(rotation[3] or 0),
            Field(block.color or "#f2e7cf"), Field(block.materialId or "solid"),
            Field(block.shapeId or "box"), Field(block.collisionRole or ""),
        }, "\t"))
    end
end
