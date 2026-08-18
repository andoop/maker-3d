local WorkspaceMigration = {}

-- Converts the original single-workbench save into the v2 asset library.  The
-- migration is deliberately idempotent: once a v2 library exists, legacy
-- projects are ignored instead of being imported again on every startup.
function WorkspaceMigration.Apply(assetStore, payload)
    payload = type(payload) == "table" and payload or {}
    if type(payload.library) == "table" then
        assetStore:LoadState(payload.library)
        return false, 0
    end

    assetStore:LoadState({ items = {}, favorites = {}, published = {} })
    local imported = 0
    local function Import(source, fallbackName)
        if type(source) ~= "table" or type(source.blocks) ~= "table" or #source.blocks == 0 then return end
        local asset = assetStore:CreateBlank(source.name or fallbackName)
        local ok = assetStore:SaveDraft(asset.assetId, source)
        if ok then imported = imported + 1 end
    end

    for _, legacy in ipairs(payload.legacyTemplates or {}) do Import(legacy, "旧模型") end
    Import(payload.legacyProject, "旧工作台模型")
    return imported > 0, imported
end

return WorkspaceMigration
