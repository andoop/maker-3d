local IslandHistoryPlan = {}

local function Identity(source)
    return tostring(source and source.assetId or "") .. "\31"
        .. tostring(source and source.versionId or "latest")
end

local function SameValue(first, second, seen)
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return first == second end
    if first == second then return true end
    seen = seen or {}
    if seen[first] == second then return true end
    seen[first] = second
    for key, value in pairs(first) do
        if not SameValue(value, second[key], seen) then return false end
    end
    for key in pairs(second) do
        if first[key] == nil then return false end
    end
    return true
end

local function SameTransform(first, second)
    return (tonumber(first.x) or 0) == (tonumber(second.x) or 0)
        and (tonumber(first.y) or 0) == (tonumber(second.y) or 0)
        and (tonumber(first.z) or 0) == (tonumber(second.z) or 0)
        and (tonumber(first.rotationY) or 0) == (tonumber(second.rotationY) or 0)
        and (tonumber(first.scale) or 1) == (tonumber(second.scale) or 1)
        and SameValue(first.portal, second.portal)
end

local function IndexById(sources)
    local byId = {}
    for _, source in ipairs(sources or {}) do
        local id = tonumber(source and source.id)
        if not id or byId[id] then return nil end
        byId[id] = source
    end
    return byId
end

---Build a mutation plan without touching live scene objects.
---Identity changes require remove+add, while transform-only changes retain the
---existing native node and StaticModelGroup membership.
function IslandHistoryPlan.Build(current, target)
    current, target = current or {}, target or {}
    local currentById, targetById = IndexById(current), IndexById(target)
    if not currentById or not targetById then
        return { valid = false, reason = "duplicate-or-missing-id" }
    end

    local plan = {
        valid = true,
        removals = {},
        additions = {},
        updates = {},
        replacements = {},
        target = target,
        changedIds = {},
        changeCount = 0,
    }

    local function Changed(id)
        if plan.changedIds[id] then return end
        plan.changedIds[id] = true
        plan.changeCount = plan.changeCount + 1
    end

    for _, source in ipairs(current) do
        local id = tonumber(source.id)
        local replacement = targetById[id]
        if not replacement or Identity(source) ~= Identity(replacement) then
            plan.removals[#plan.removals + 1] = id
            Changed(id)
        elseif not SameTransform(source, replacement) then
            plan.updates[#plan.updates + 1] = { id = id, source = replacement }
            Changed(id)
        end
    end

    for _, source in ipairs(target) do
        local id = tonumber(source.id)
        local previous = currentById[id]
        if not previous or Identity(previous) ~= Identity(source) then
            plan.additions[#plan.additions + 1] = source
            if previous then plan.replacements[#plan.replacements + 1] = id end
            Changed(id)
        end
    end
    return plan
end

return IslandHistoryPlan
