local AdventureTemplateLibrary = require("AdventureTemplateLibrary")

local HouseTemplate = {}

-- BuilderWorld retains this legacy-shaped entrypoint for its reset action.
-- Reset now starts from the same real-scale, enterable cottage shown in the
-- composable built-in library.
function HouseTemplate.Build()
    local template = assert(AdventureTemplateLibrary.BuildOne("builtin:compose:sunny-meadow-cottage"))
    local result = {}
    for index, block in ipairs(template.blocks) do
        result[index] = {
            id = index,
            name = block.name,
            type = block.type or "block",
            x = block.position[1], y = block.position[2], z = block.position[3],
            sx = block.size[1], sy = block.size[2], sz = block.size[3],
            rx = block.rotation[1], ry = block.rotation[2], rz = block.rotation[3],
            color = block.color,
            materialId = block.materialId,
            shapeId = block.shapeId,
        }
    end
    return result
end

return HouseTemplate
