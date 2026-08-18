local AdventureTemplateLibrary = require("AdventureTemplateLibrary")
local PortalTemplate = require("PortalTemplate")

local BuiltinTemplates = {}

function BuiltinTemplates.BuildAll()
    local result = AdventureTemplateLibrary.BuildAll()
    result[#result + 1] = PortalTemplate.Build()
    return result
end

return BuiltinTemplates
