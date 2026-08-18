-- Shared, engine-free presentation rules for the island and workbench model
-- libraries. Keeping filtering here prevents the two selectors from drifting.
local ModelLibraryPresentation = {}

local function Trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function Utf8Prefix(value, limit)
    local index, count, length = 1, 0, #value
    while index <= length and count < limit do
        local byte = value:byte(index)
        local width = byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4
        index, count = index + width, count + 1
    end
    return value:sub(1, index - 1), index <= length
end

function ModelLibraryPresentation.CompactDescription(value, fallback, limit)
    local text = Trim(value)
    if text == "" then text = Trim(fallback or "可自由组合") end
    text = text:gsub("^云岬手绘共创精选%s*·%s*", "")
    local stop = #text + 1
    for _, punctuation in ipairs({ "，", "。", "；" }) do
        local position = text:find(punctuation, 1, true)
        if position and position < stop then stop = position end
    end
    if stop <= #text then text = text:sub(1, stop - 1) end
    local prefix, clipped = Utf8Prefix(text, tonumber(limit) or 18)
    return prefix .. (clipped and "…" or "")
end

local function SourceOf(item)
    return tostring(item.source or (item.builtin and "builtin" or "mine"))
end

local function MatchesSource(item, source)
    if not source or source == "all" then return true end
    if source == "favorites" then return item.favorite == true end
    return SourceOf(item) == source
end

function ModelLibraryPresentation.Categories(items, source)
    local result, seen = {}, {}
    for _, item in ipairs(items or {}) do
        if MatchesSource(item, source) then
            local category = Trim(item.category)
            if category == "" then category = "未分类" end
            if not seen[category] then
                seen[category] = true
                result[#result + 1] = category
            end
        end
    end
    return result
end

function ModelLibraryPresentation.Filter(items, source, category)
    local result = {}
    for _, item in ipairs(items or {}) do
        local itemCategory = Trim(item.category)
        if itemCategory == "" then itemCategory = "未分类" end
        if MatchesSource(item, source)
            and (not category or category == "全部" or category == itemCategory) then
            result[#result + 1] = item
        end
    end
    return result
end

return ModelLibraryPresentation
