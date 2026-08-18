package.path = "scripts/?.lua;" .. package.path

local BuiltinTemplates = require("BuiltinTemplates")
local Catalog = require("BlockCatalog")
local Theme = require("CloudAtelierTheme")
local ChibiModelPass = require("ChibiModelPass")
local ModelStandards = require("AdventureModelStandards")
local FirstPersonScale = require("FirstPersonScale")
local ModelGeometry = require("ModelGeometry")

local knownMaterials, knownShapes = {}, {}
for _, material in ipairs(Catalog.MATERIALS) do knownMaterials[material.id] = true end
for _, shape in ipairs(Catalog.SHAPES) do knownShapes[shape.id] = true end

local expectedCategories = {
    ["树木单件"] = 8,
    ["植被单件"] = 10,
    ["可进入建筑"] = 6,
    ["飞行器"] = 4,
    ["围栏构件"] = 8,
    ["街景设施"] = 9,
    ["组合构件"] = 8,
    ["遗迹构件"] = 8,
    ["山体构件"] = 7,
    ["传送机关"] = 1,
}

local function Round(value) return string.format("%.3f", tonumber(value) or 0) end
local function GeometrySignature(template)
    local parts = {}
    for _, block in ipairs(template.blocks) do
        parts[#parts + 1] = table.concat({
            block.shapeId, block.materialId,
            Round(block.position[1]), Round(block.position[2]), Round(block.position[3]),
            Round(block.size[1]), Round(block.size[2]), Round(block.size[3]),
            Round(block.rotation[1]), Round(block.rotation[2]), Round(block.rotation[3]),
        }, ":")
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function TopologySignature(template)
    local parts = {}
    for _, block in ipairs(template.blocks) do
        parts[#parts + 1] = table.concat({
            tostring(block.shapeId), tostring(block.materialId), tostring(block.collisionRole or "solid"),
        }, ":")
    end
    return table.concat(parts, "|")
end

local function FindTemplate(templates, suffix)
    for _, template in ipairs(templates) do
        if tostring(template.id):find(suffix, 1, true) then return template end
    end
end

assert(FirstPersonScale.HEIGHT == 1.20, "the shared chibi explorer must be exactly 1.2 m tall")
assert(FirstPersonScale.EYE_HEIGHT < FirstPersonScale.HEIGHT, "eye height must remain inside the character capsule")
assert(FirstPersonScale.SURFACE_PADDING >= FirstPersonScale.RADIUS,
    "raised surfaces must be detected before their expanded collider blocks the player")

local templates = BuiltinTemplates.BuildAll()
assert(#templates == 69, "the composable library must contain 68 authored assets plus the paired portal")

local totals = {
    blocks = 0, doors = 0, carved = 0, singlePieces = 0, buildings = 0, multiStorey = 0,
    ruins = 0, ruinBlocks = 0, largeTexturedMasonry = 0,
}
local categories, ids, names, signatures, topologies, materials, shapes = {}, {}, {}, {}, {}, {}, {}
local treeMinHeight, treeMaxHeight = math.huge, 0
for _, template in ipairs(templates) do
    assert((template.version or 0) >= 20, template.name .. " must use composable template version 20")
    assert(tostring(template.id):match("^builtin:compose:"), template.name .. " must use the compose namespace")
    assert(not ids[template.id], "duplicate template id: " .. template.id)
    assert(not names[template.name], "duplicate template name: " .. template.name)
    ids[template.id], names[template.name] = true, true
    categories[template.category] = (categories[template.category] or 0) + 1
    assert(#template.blocks >= 3 and #template.blocks <= 800, template.name .. " has an invalid component count")
    assert(template.recommendedScale == 1.0, template.name .. " must share the real 1:1 island scale")

    local audit = ChibiModelPass.Audit(template.blocks)
    local proportions = ModelStandards.Audit(template)
    assert(audit.invalid == 0, template.name .. " contains invalid sizes or transforms")
    assert(audit.duplicates == 0, template.name .. " contains exact duplicate geometry")
    assert(audit.belowGround == 0, template.name .. " contains parts below its placement plane")
    assert(audit.blockedDoors == 0, template.name .. " still has a solid wall behind a door")
    assert(not proportions.invalidScale, template.name .. " uses an unreasonable recommended scale")
    assert(not proportions.invalidFootprint, template.name .. " has an unreasonable footprint")
    assert(not proportions.invalidHeight, template.name .. " has an unreasonable height")
    assert(proportions.invalidDoors == 0, template.name .. " has an entrance too small for a 1.2 m avatar")
    assert(proportions.missingStructure == 0,
        template.name .. " lacks required construction: " .. table.concat(proportions.structureNotes, ", "))

    if template.category == "可进入建筑" then
        totals.buildings = totals.buildings + 1
        assert((template.storeys or 0) >= 1 and (template.storeys or 0) <= 3,
            template.name .. " must publish a believable storey count")
        if template.storeys >= 2 then totals.multiStorey = totals.multiStorey + 1 end
        assert(audit.doors >= template.storeys,
            template.name .. " must have a separate reachable entrance for every authored storey")
    else
        totals.singlePieces = totals.singlePieces + 1
    end
    if template.category == "遗迹构件" then
        totals.ruins, totals.ruinBlocks = totals.ruins + 1, totals.ruinBlocks + #template.blocks
        assert(#template.blocks <= 28, template.name .. " must use surface detail instead of hundreds of bricks")
    end
    if template.category == "树木单件" then
        treeMinHeight = math.min(treeMinHeight, proportions.height)
        treeMaxHeight = math.max(treeMaxHeight, proportions.height)
    end

    totals.blocks = totals.blocks + #template.blocks
    totals.doors = totals.doors + audit.doors
    totals.carved = totals.carved + audit.carvedOpenings
    for _, block in ipairs(template.blocks) do
        assert(knownMaterials[block.materialId], template.name .. " uses unknown material " .. tostring(block.materialId))
        assert(knownShapes[block.shapeId], template.name .. " uses unknown shape " .. tostring(block.shapeId))
        materials[block.materialId], shapes[block.shapeId] = true, true
        if template.category == "遗迹构件"
            and (block.materialId == "ruin_stone" or block.materialId == "old_brick"
                or block.materialId == "carved_stone" or block.materialId == "overgrown_stone")
            and math.max(block.size[1], block.size[3]) >= 5 then
            totals.largeTexturedMasonry = totals.largeTexturedMasonry + 1
        end
    end
    local signature = GeometrySignature(template)
    assert(not signatures[signature], template.name .. " duplicates another model's geometry")
    signatures[signature] = template.id
    local topology = TopologySignature(template)
    assert(not topologies[topology], template.name .. " is only a resized/recoloured clone of " .. tostring(topologies[topology]))
    topologies[topology] = template.id
end

for category, expectedCount in pairs(expectedCategories) do
    assert(categories[category] == expectedCount,
        string.format("%s must contain exactly %d authored choices", category, expectedCount))
end
local categoryCount = 0
for _ in pairs(categories) do categoryCount = categoryCount + 1 end
assert(categoryCount == 10, "unexpected model category leaked into the replacement library")
assert(totals.singlePieces == 63 and totals.buildings == 6,
    "the library must stay focused on reusable single pieces")
assert(totals.ruins == 8 and totals.ruinBlocks <= 110 and totals.largeTexturedMasonry >= 6,
    "ruin kit must achieve large masonry silhouettes with a low component count")
assert(totals.multiStorey >= 4, "the building set needs meaningful vertical variety")
assert(treeMinHeight < 2.6 and treeMaxHeight > 6.0,
    "tree choices must visibly range from courtyard scale to landmark scale")
assert(totals.blocks >= 2100 and totals.blocks <= 2470,
    "detail should come from deliberate small parts without exceeding the mobile budget")
assert(totals.doors >= 10 and totals.carved >= 24,
    "buildings must retain real carved entrances and windows")

local warmLamp = assert(FindTemplate(templates, "warm-street-lamp"))
local warmLampGlow = 0
for _, block in ipairs(warmLamp.blocks) do
    if block.materialId == "glow" then warmLampGlow = warmLampGlow + 1 end
    if tostring(block.name):find("石质底座", 1, true) or tostring(block.name):find("弯臂", 1, true)
        or tostring(block.name):find("灯帽", 1, true) then
        assert(block.materialId ~= "glow", "warm lamp structure must not inherit glow from its model prefix")
    end
end
assert(warmLampGlow == 1, "single-head street lamp should emit only from its light core")

local airship = assert(FindTemplate(templates, "cloud-courier-airship"))
local ribCount = 0
for _, block in ipairs(airship.blocks) do
    if tostring(block.name):find("气囊肋骨", 1, true) then
        ribCount = ribCount + 1
        local half = ModelGeometry.RotatedHalfExtents(block)
        assert(half[2] > 1.0 and half[3] > 1.4 and half[1] < 0.10,
            "airship rib must wrap the balloon in the YZ plane")
    end
end
assert(ribCount == 7, "courier airship needs seven readable balloon ribs")

local ropeFence = assert(FindTemplate(templates, "rope-post-barrier"))
for _, block in ipairs(ropeFence.blocks) do
    if tostring(block.name):find("下垂绳", 1, true) then
        assert(math.abs(block.position[1]) <= 1.55,
            "rope segments must remain between their three support posts")
    end
end
local layeredHill = assert(FindTemplate(templates, "layered-rocky-hill"))
for _, block in ipairs(layeredHill.blocks) do
    if tostring(block.name):find("侧向山径台阶", 1, true) then
        assert(block.position[3] >= 3.0, "layered hill steps must remain visible outside the rock mass")
    end
end

local voxelGeology = 0
local doorBearingModels, ruinDoorModels = 0, 0
for _, template in ipairs(templates) do
    if template.category == "山体构件" then
        for _, block in ipairs(template.blocks) do
            local name = tostring(block.name)
            if name:find("方块岩柱", 1, true) or name:find("方块地表", 1, true)
                or name:find("方块拱顶岩梁", 1, true) or name:find("雪山体素", 1, true) then
                voxelGeology = voxelGeology + 1
                assert(block.shapeId == "box", template.name .. " geological mass must use clean voxel blocks")
                assert(math.abs(block.rotation[1]) < 0.001 and math.abs(block.rotation[2]) < 0.001
                    and math.abs(block.rotation[3]) < 0.001,
                    template.name .. " voxel geology must not fake complexity through intersecting rotations")
            end
        end
    end
end
assert(voxelGeology >= 120, "mountain set needs a readable Minecraft-like stepped height field")

local snowMountain = assert(FindTemplate(templates, "snow-cap-mountain"))
local snowAudit = ModelStandards.Audit(snowMountain)
local snowSurfaces, exposedRockSurfaces, greenFootSurfaces, snowVoxels = 0, 0, 0, 0
for _, block in ipairs(snowMountain.blocks) do
    local name = tostring(block.name)
    if name:find("雪山体素", 1, true) then
        snowVoxels = snowVoxels + 1
        assert(block.shapeId == "box"
            and math.abs(block.size[1] - block.size[2]) < 0.05
            and math.abs(block.size[1] - block.size[3]) < 0.05,
            "snow mountain must be built from readable equal-sized voxel cubes")
        assert(math.abs(block.rotation[1]) < 0.001 and math.abs(block.rotation[2]) < 0.001
            and math.abs(block.rotation[3]) < 0.001,
            "snow mountain voxels must remain aligned to their stepped grid")
    end
    if name:find("雪山体素地表", 1, true) then
        if block.materialId == "snow" then snowSurfaces = snowSurfaces + 1 end
        if block.materialId == "stone" then exposedRockSurfaces = exposedRockSurfaces + 1 end
        if block.materialId == "moss" or block.materialId == "grass" then
            greenFootSurfaces = greenFootSurfaces + 1
        end
    end
end
assert(snowVoxels >= 140 and snowSurfaces >= 8 and exposedRockSurfaces >= 8
    and greenFootSurfaces >= 4 and snowAudit.footprint >= 7.5 and snowAudit.height >= 7.5,
    "snow mountain needs a broad true-voxel foot, exposed rock belt and broken snowline")

local columnTower = assert(FindTemplate(templates, "world-tree-column-tower"))
local jointColumns, rootButtresses = 0, 0
for _, block in ipairs(columnTower.blocks) do
    local name = tostring(block.name)
    if name:find("纵向节理岩棱", 1, true) then
        jointColumns = jointColumns + 1
        assert(block.shapeId == "box" and block.size[2] >= 4.6,
            "world-tree tower columns must remain long readable prisms")
    elseif name:find("承重巨树根状基岩", 1, true) then
        rootButtresses = rootButtresses + 1
    end
end
assert(jointColumns >= 40 and rootButtresses == 12,
    "world-tree tower needs a dense vertical crown and twelve root-like buttresses")

for _, template in ipairs(templates) do
    local doors, tracks, handles = {}, {}, {}
    for _, block in ipairs(template.blocks) do
        local name = tostring(block.name)
        if block.type == "door" then doors[#doors + 1] = block end
        if name:find("黄铜抽拉门上轨", 1, true) then tracks[#tracks + 1] = block end
        if name:find("黄铜嵌入拉手", 1, true) then handles[#handles + 1] = block end
        for _, forbidden in ipairs({
            "入口门槛", "抽拉门下导向器", "抽拉轨道滑轮",
            "抽拉门套边框", "抽拉门板竖框", "抽拉门板横档",
            "门廊地台", "门洞踏石",
        }) do
            assert(not name:find(forbidden, 1, true),
                template.name .. " doorway must stay clear of extra " .. forbidden)
        end
    end
    if #doors > 0 then
        doorBearingModels = doorBearingModels + 1
        if template.category == "遗迹构件" then ruinDoorModels = ruinDoorModels + 1 end
        assert(#tracks == #doors and #handles == #doors,
            template.name .. " must give every entrance one rail and one recessed pull")
        for _, door in ipairs(doors) do
            local matched, bestClearance = false, -math.huge
            local front = door.size[1] > door.size[3]
            assert(math.abs(door.rotation[1]) < 0.001 and math.abs(door.rotation[2]) < 0.001
                and math.abs(door.rotation[3]) < 0.001,
                template.name .. " sliding door must remain parallel to its wall")
            for _, track in ipairs(tracks) do
                local trackFront = track.size[1] > track.size[3]
                local doorTop = door.position[2] + door.size[2] * 0.5
                local normalDistance = front and math.abs(door.position[3] - track.position[3])
                    or math.abs(door.position[1] - track.position[1])
                if front == trackFront and math.abs(track.position[2] - doorTop - 0.10) < 0.03
                    and normalDistance < 0.04 then
                    local doorAlong = front and door.position[1] or door.position[3]
                    local trackAlong = front and track.position[1] or track.position[3]
                    local doorWidth = front and door.size[1] or door.size[3]
                    local trackLength = front and track.size[1] or track.size[3]
                    local openingWidth = trackLength - doorWidth - 0.20
                    local slideSign = doorAlong >= trackAlong and 1 or -1
                    local openingCenter = trackAlong - slideSign * doorWidth * 0.5
                    bestClearance = math.max(bestClearance,
                        math.abs(doorAlong - openingCenter) - doorWidth * 0.5 - openingWidth * 0.5)
                    assert(math.abs(doorAlong - trackAlong) + doorWidth * 0.5 <= trackLength * 0.5 + 0.001,
                        template.name .. " open door leaf must remain carried by its rail")
                    matched = true
                end
            end
            assert(matched and bestClearance >= 0.035,
                template.name .. " sliding door must park fully clear of its opening")
            assert(door.collisionRole == "decorative", template.name .. " open door must keep the passage walkable")
        end
    end
end
assert(doorBearingModels >= 9 and ruinDoorModels >= 2,
    "every building, garden gate and authored ruin doorway must use the shared open sliding-door system")

for _, material in ipairs({
    "solid", "painted_wood", "wood", "grass", "earth", "stone", "water", "crystal",
    "glass", "ceramic", "fabric", "metal", "glow", "leaf", "roof_tile", "fire", "moss", "snow", "pavement",
    "ruin_stone", "old_brick", "carved_stone", "overgrown_stone",
}) do
    assert(materials[material], "composable library is missing material: " .. material)
end
for _, shape in ipairs({ "box", "sphere", "cylinder", "cone", "tri_prism", "pyramid", "torus", "tetra" }) do
    assert(shapes[shape], "composable library is missing shape: " .. shape)
end
assert(#Catalog.COLORS == #Theme.COLORS, "editor and authored palette must share one theme source")
for index, source in ipairs(Theme.COLORS) do
    assert(Catalog.COLORS[index].id == source.id and Catalog.COLORS[index].css == source.css,
        "editor palette drifted from cloud atelier theme at " .. tostring(source.id))
end

print(string.format("template-quality-spec: ok (%d models, %d categories, %d blocks)",
    #templates, categoryCount, totals.blocks))
