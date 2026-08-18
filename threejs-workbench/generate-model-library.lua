local gameRoot = assert(arg[1], "usage: lua generate-model-library.lua <game124-root> <output-json>")
local outputPath = assert(arg[2], "missing output-json")

package.path = gameRoot .. "/scripts/?.lua;" .. package.path

local templates = require("BuiltinTemplates").BuildAll()

local function IsArray(value)
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count, maximum = count + 1, math.max(maximum, key)
    end
    return count == maximum
end

local function Escape(value)
    return value:gsub("[\\\"%z\1-\31]", function(character)
        local replacements = {
            ["\\"] = "\\\\", ["\""] = "\\\"", ["\b"] = "\\b",
            ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
        }
        return replacements[character] or string.format("\\u%04x", character:byte())
    end)
end

local function Encode(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge, "non-finite number")
        return string.format("%.15g", value)
    end
    if kind == "string" then return "\"" .. Escape(value) .. "\"" end
    assert(kind == "table", "unsupported JSON type: " .. kind)
    if IsArray(value) then
        local result = {}
        for index = 1, #value do result[index] = Encode(value[index]) end
        return "[" .. table.concat(result, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
        if type(value[key]) ~= "function" then keys[#keys + 1] = tostring(key) end
    end
    table.sort(keys)
    local result = {}
    for _, key in ipairs(keys) do
        result[#result + 1] = "\"" .. Escape(key) .. "\":" .. Encode(value[key])
    end
    return "{" .. table.concat(result, ",") .. "}"
end

local blockCount = 0
for _, template in ipairs(templates) do blockCount = blockCount + #(template.blocks or {}) end

local payload = {
    version = 30,
    source = "game124/scripts/BuiltinTemplates.lua",
    modelCount = #templates,
    blockCount = blockCount,
    models = templates,
}

local output = assert(io.open(outputPath, "wb"))
output:write(Encode(payload))
output:write("\n")
output:close()

print(string.format("generated %d models / %d blocks -> %s", #templates, blockCount, outputPath))
