package.path = "scripts/?.lua;" .. package.path

local BuiltinTemplates = require("BuiltinTemplates")
local ModelAssetStore = require("ModelAssetStore")
local ModelMiniature = require("ModelMiniature")

local templates = BuiltinTemplates.BuildAll()
assert(#templates == 69, "thumbnail coverage must include the paired portal")

local paths = {}
for _, template in ipairs(templates) do
    local slug = tostring(template.id):gsub("^builtin:compose:", "")
    local expected = "image/model-thumbs/" .. slug .. ".png"
    assert(template.thumbnail == expected,
        "built-in thumbnail must use a stable resource path: " .. tostring(template.id))
    assert(not paths[template.thumbnail], "built-in thumbnail paths must be unique")
    paths[template.thumbnail] = true
end

local store = ModelAssetStore.new(templates)
local summaries = store:GetSummaries("builtin")
assert(#summaries == #templates, "model summaries must include every built-in model")
for _, summary in ipairs(summaries) do
    assert(type(summary.thumbnail) == "string" and paths[summary.thumbnail],
        "model list summary must expose its generated thumbnail")
    local asset = assert(store:Get(summary.assetId))
    assert(summary.thumbnail == asset.thumbnail,
        "summary thumbnail must match the canonical asset record")
end

local draft = store:CreateBlank("自定义灯塔")
assert(store:SaveDraft(draft.assetId, {
    name = "自定义灯塔",
    blocks = {
        { name = "塔身", position = { 0, 1.5, 0 }, size = { 0.5, 3, 0.5 },
            rotation = { 0, 0, 0 }, color = "#7aa6b4", materialId = "solid", shapeId = "box" },
        { name = "塔灯", position = { 0, 3.2, 0 }, size = { 1.1, 0.5, 1.1 },
            rotation = { 0, 0, 0 }, color = "#ffe07a", materialId = "glow", shapeId = "sphere" },
    },
}))
local mine = store:GetSummaries("mine")
assert(#mine == 1 and mine[1].thumbnail == nil and #mine[1].previewParts >= 2,
    "user models without PNG assets must expose a model-derived miniature")
local parts = ModelMiniature.Parts(assert(store:Get(draft.assetId)), 12)
assert(#parts >= 2 and parts[1].x >= 0 and parts[1].x <= 1
    and parts[1].y >= 0 and parts[1].y <= 1,
    "procedural miniatures must stay normalized inside their card")

print("model_thumbnail_spec: ok")
