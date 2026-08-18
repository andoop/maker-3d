-- Cloud Atelier composable model kit.
--
-- Most assets are deliberately useful single pieces. Buildings are the
-- exception: a small set of authored, enterable examples demonstrates how
-- fine components, real openings, interiors and multi-storey circulation fit
-- the same 1.2 m first-person character scale.

local ChibiModelPass = require("ChibiModelPass")
local ModelStandards = require("AdventureModelStandards")
local Theme = require("CloudAtelierTheme")
local ModelLibraryPresentation = require("ModelLibraryPresentation")

local Library = {}
local C = Theme.MODEL
local TAU = math.pi * 2
local VERSION = 30
local NAMESPACE = "builtin:compose:"

local function Add(blocks, name, x, y, z, sx, sy, sz, color, material, shape, rx, ry, rz, kind, collisionRole)
    local block = {
        name = name, type = kind or "block",
        position = { x, y, z }, size = { sx, sy, sz },
        rotation = { math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0) },
        color = color or C.plaster, materialId = material or "solid", shapeId = shape or "box",
        collisionRole = collisionRole,
    }
    blocks[#blocks + 1] = block
    return block
end

local function Finalize(spec, blocks)
    ChibiModelPass.Apply(spec.id, spec.category, blocks)
    local profile = ModelStandards.Profile(spec.category, spec.id)
    return {
        version = VERSION, id = NAMESPACE .. spec.id, builtin = true,
        category = spec.category, designProfile = profile.id,
        recommendedScale = profile.scale, name = spec.name,
        description = ModelLibraryPresentation.CompactDescription(spec.description), storeys = spec.storeys,
        tags = { "云岬手绘", "组合单件", spec.category }, blocks = blocks,
        thumbnail = "image/model-thumbs/" .. spec.id .. ".png",
    }
end

local function CrownBall(blocks, name, x, y, z, sx, sy, sz, color)
    Add(blocks, name, x, y, z, sx, sy, sz, color, "leaf", "sphere", 0, 0, 0, nil, "decorative")
end

local TREE_SPECS = {
    { id = "tiny-fruit-tree", name = "矮生果树", style = "fruit", height = 2.25, radius = 1.25,
        description = "低矮圆冠与可读果实，适合庭院和道路转角。" },
    { id = "round-meadow-oak", name = "圆冠草甸橡树", style = "oak", height = 3.65, radius = 1.75,
        description = "中等高度的通用主景树，枝杈和冠团关系完整。" },
    { id = "tall-guardian-oak", name = "高冠守望橡树", style = "oak", height = 5.85, radius = 2.45,
        description = "适合作为广场、山坡和建筑群视觉锚点的高大乔木。" },
    { id = "young-cloud-pine", name = "幼年云杉", style = "pine", height = 3.15, radius = 1.45,
        description = "紧凑的三层针叶树冠，适合密集组合。" },
    { id = "tall-layered-pine", name = "高层叠云杉", style = "pine", height = 6.20, radius = 2.25,
        description = "六层递减树冠与裸露树梢，远近轮廓都清楚。" },
    { id = "storybook-birch", name = "绘本白桦", style = "birch", height = 4.45, radius = 1.55,
        description = "白色分节树干和轻盈小冠，适合成组形成林缘。" },
    { id = "soft-riverside-willow", name = "溪畔软垂柳", style = "willow", height = 4.70, radius = 2.55,
        description = "横向枝架与多束下垂叶帘，适合水边和庭院。" },
    { id = "pink-cloud-blossom", name = "粉云花树", style = "blossom", height = 3.95, radius = 2.05,
        description = "粉白花冠、深色枝干和少量飘落花簇。" },
}

local function BuildTree(spec)
    local b, h, r = {}, spec.height, spec.radius
    local trunkColor = spec.style == "birch" and C.plasterShade or C.darkWood
    if spec.style == "pine" then
        Add(b, spec.name .. "主干", 0, h * 0.48, 0, 0.34 + r * 0.08, h * 0.96,
            0.34 + r * 0.08, C.darkWood, "wood", "cylinder")
        local layers = h > 5 and 6 or 4
        for index = 0, layers - 1 do
            local amount = index / layers
            local width = r * 2 * (1 - amount * 0.58)
            local layerY = h * (0.34 + index * 0.105)
            for arm = 0, 2 do
                local angle = arm * 120 + index * 29
                local radians = math.rad(angle)
                local reach = width * (0.14 + arm % 2 * 0.025)
                Add(b, spec.name .. "针叶枝" .. index .. "-" .. arm,
                    math.sin(radians) * reach * 0.46, layerY - 0.10,
                    math.cos(radians) * reach * 0.46,
                    0.11 + r * 0.025, width * 0.40, 0.11 + r * 0.025,
                    C.darkWood, "wood", "cylinder", 0, angle, 72, nil, "decorative")
                Add(b, spec.name .. "针叶簇" .. index .. "-" .. arm,
                    math.sin(radians) * reach, layerY + (arm % 2) * 0.08,
                    math.cos(radians) * reach,
                    width * 0.62, h / layers * 1.02, width * 0.62,
                    index % 2 == 0 and C.forest or C.leaf, "leaf", "cone", 0, angle, 0, nil, "decorative")
            end
            Add(b, spec.name .. "针叶内簇" .. index, 0, layerY + 0.07, 0,
                width * 0.56, h / layers * 0.94, width * 0.56,
                index % 2 == 0 and C.leaf or C.forest, "leaf", "cone", 0, index * 17, 0, nil, "decorative")
        end
        Add(b, spec.name .. "裸露树梢", 0, h * 0.94, 0, 0.30, h * 0.22, 0.30,
            C.darkWood, "wood", "cone")
        return b
    end

    Add(b, spec.name .. "主干下段", 0, h * 0.30, 0, 0.42 + r * 0.12, h * 0.60,
        0.42 + r * 0.12, trunkColor, "wood", "cylinder")
    Add(b, spec.name .. "主干上段", 0.06, h * 0.69, -0.04,
        0.30 + r * 0.08, h * 0.48, 0.30 + r * 0.08,
        trunkColor, "wood", "cone", 0, 0, -3)
    local branches = spec.style == "willow" and 7 or h > 5 and 9 or 6
    for index = 0, branches - 1 do
        local angle = index * 360 / branches + (index % 2) * 13 + (h > 5 and index % 3 * 7 or 0)
        local radians = math.rad(angle)
        local length = r * (0.78 + index % 3 * 0.08)
        local y = h * (0.58 + index % 3 * 0.055)
        Add(b, spec.name .. "枝架" .. index,
            math.sin(radians) * length * 0.30, y,
            math.cos(radians) * length * 0.30,
            0.16 + r * 0.035, length, 0.16 + r * 0.035,
            trunkColor, "wood", "cylinder", 0, angle, 67, nil, "decorative")
        local crownX, crownZ = math.sin(radians) * length * 0.78, math.cos(radians) * length * 0.78
        local crownColor = spec.style == "blossom" and (index % 2 == 0 and C.rose or C.cloud)
            or index % 3 == 0 and C.grassLight or index % 2 == 0 and C.leaf or C.forest
        local clumps = spec.style == "willow" and 1 or 2
        for clump = 1, clumps do
            local amount = 0.62 + clump * 0.18
            local side = (clump % 2 == 0 and 1 or -1) * r * 0.12
            CrownBall(b, spec.name .. "枝叶团" .. index .. "-" .. clump,
                math.sin(radians) * length * amount + math.cos(radians) * side,
                y + 0.20 + clump * 0.16 + (index % 2) * 0.05,
                math.cos(radians) * length * amount - math.sin(radians) * side,
                r * (clump == 1 and 0.58 or 0.52), r * 0.48, r * (clump == 1 and 0.58 or 0.52), crownColor)
        end
        if spec.style == "willow" then
            for strand = -1, 1 do
                Add(b, spec.name .. "垂叶帘" .. index .. "-" .. strand,
                    crownX + strand * 0.24, y - 0.40 - math.abs(strand) * 0.12, crownZ,
                    0.20, 1.55 + (index % 2) * 0.25, 0.20,
                    strand == 0 and C.leaf or C.forest, "leaf", "cylinder", 0, 0, 0, nil, "decorative")
            end
        end
    end
    CrownBall(b, spec.name .. "树冠内团", 0, h * 0.78, 0,
        r * 0.72, r * 0.62, r * 0.72,
        spec.style == "blossom" and C.rose or C.leaf)

    if spec.style == "birch" then
        for band = 1, 5 do
            Add(b, spec.name .. "树皮横纹" .. band, 0, h * (0.14 + band * 0.105), 0,
                0.51 + r * 0.12, 0.055, 0.51 + r * 0.12,
                C.shadowStone, "painted_wood", "cylinder", 0, 0, 0, nil, "decorative")
        end
    elseif spec.style == "fruit" then
        for fruit = 0, 8 do
            local angle = fruit * TAU / 9
            Add(b, spec.name .. "果实" .. fruit,
                math.sin(angle) * r * 1.02, h * (0.59 + fruit % 3 * 0.09),
                math.cos(angle) * r * 1.02, 0.22, 0.22, 0.22,
                fruit % 2 == 0 and C.terracotta or C.yellow, "ceramic", "sphere", 0, 0, 0, nil, "decorative")
        end
    elseif spec.style == "blossom" then
        for flower = 0, 7 do
            local angle = flower * TAU / 8
            CrownBall(b, spec.name .. "花簇" .. flower,
                math.sin(angle) * r * 0.94, h * (0.67 + flower % 2 * 0.13),
                math.cos(angle) * r * 0.94, 0.28, 0.23, 0.28,
                flower % 3 == 0 and C.cloud or C.rose)
        end
    end
    return b
end

local VEGETATION_SPECS = {
    { id = "short-grass-tuft", name = "短草簇", style = "grass", scale = 0.55, description = "七叶短草单件。" },
    { id = "tall-wind-grass", name = "风摆高草", style = "grass", scale = 1.15, description = "高低错落的长叶草单件。" },
    { id = "meadow-grass-cluster", name = "草甸混生簇", style = "mixed", scale = 1.0, description = "短草、穗草和碎花组合。" },
    { id = "soft-fern", name = "卷叶蕨", style = "fern", scale = 1.0, description = "六向展开的林下蕨叶。" },
    { id = "broad-leaf-plant", name = "阔叶草木", style = "broad", scale = 1.1, description = "适合墙角和树下的阔叶单株。" },
    { id = "coral-wildflower", name = "珊瑚野花", style = "flower", scale = 0.85, color = C.rose, description = "暖粉花瓣与细小花芯。" },
    { id = "bluebell-wildflower", name = "风铃蓝花", style = "bell", scale = 1.0, color = C.sky, description = "蓝色钟形花簇。" },
    { id = "round-garden-bush", name = "圆团灌木", style = "bush", scale = 1.25, description = "三团式常绿灌木。" },
    { id = "flowering-shrub", name = "开花灌木", style = "flower_bush", scale = 1.35, description = "带细小花团的中型灌木。" },
    { id = "riverside-reeds", name = "溪畔芦苇", style = "reeds", scale = 1.25, description = "多高度茎秆和柔软穗头。" },
}

local function BuildVegetation(spec)
    local b, s = {}, spec.scale
    if spec.style == "grass" or spec.style == "mixed" then
        local count = spec.style == "mixed" and 12 or s > 0.8 and 11 or 7
        for index = 0, count - 1 do
            local angle = index * TAU / count
            local height = s * (0.62 + index % 4 * 0.13)
            Add(b, spec.name .. "叶片" .. index,
                math.sin(angle) * s * (0.18 + index % 2 * 0.08), height * 0.5,
                math.cos(angle) * s * (0.18 + index % 2 * 0.08),
                0.09 * s, height, 0.09 * s,
                index % 3 == 0 and C.grassLight or C.leaf, "leaf", "cone", 0, index * 31, 0, nil, "decorative")
        end
        if spec.style == "mixed" then
            for flower = 0, 4 do
                local angle = flower * TAU / 5
                Add(b, spec.name .. "碎花" .. flower, math.sin(angle) * 0.48, 0.58 + flower % 2 * 0.13,
                    math.cos(angle) * 0.48, 0.16, 0.14, 0.16,
                    flower % 2 == 0 and C.yellow or C.rose, "fabric", "sphere", 0, 0, 0, nil, "decorative")
            end
        end
    elseif spec.style == "fern" then
        for index = 0, 7 do
            local angle = index * 45
            local radians = math.rad(angle)
            Add(b, spec.name .. "叶梗" .. index,
                math.sin(radians) * 0.36, 0.65 + index % 2 * 0.05,
                math.cos(radians) * 0.36, 0.12, 0.95, 0.26,
                index % 2 == 0 and C.leaf or C.forest, "leaf", "cone", 52, angle, 0, nil, "decorative")
        end
        CrownBall(b, spec.name .. "卷芽", 0, 0.62, 0, 0.28, 0.42, 0.28, C.grassLight)
    elseif spec.style == "broad" then
        for index = 0, 5 do
            local angle = index * 60
            local radians = math.rad(angle)
            CrownBall(b, spec.name .. "阔叶" .. index,
                math.sin(radians) * 0.42, 0.56 + index % 2 * 0.12,
                math.cos(radians) * 0.42, 0.52, 0.82, 0.24,
                index % 2 == 0 and C.leaf or C.forest)
        end
        Add(b, spec.name .. "中心嫩叶", 0, 0.64, 0, 0.28, 1.05, 0.28,
            C.grassLight, "leaf", "cone", 0, 0, 0, nil, "decorative")
    elseif spec.style == "bell" then
        for stem = 0, 4 do
            local angle = stem * TAU / 5
            local height = 0.72 + stem % 3 * 0.16
            local x, z = math.sin(angle) * 0.26, math.cos(angle) * 0.26
            Add(b, spec.name .. "弯曲花茎" .. stem, x, height * 0.5 + 0.015, z,
                0.065, height, 0.065, C.forest, "leaf", "cylinder",
                0, stem * 17, stem % 2 == 0 and 4 or -4, nil, "decorative")
            Add(b, spec.name .. "下垂钟花" .. stem, x + math.sin(angle) * 0.10,
                height + 0.04, z + math.cos(angle) * 0.10,
                0.26, 0.34, 0.26, C.sky, "fabric", "cone", 0, 0, 180, nil, "decorative")
            Add(b, spec.name .. "钟花花芯" .. stem, x + math.sin(angle) * 0.10,
                height - 0.12, z + math.cos(angle) * 0.10,
                0.08, 0.11, 0.08, C.yellow, "ceramic", "sphere", 0, 0, 0, nil, "decorative")
        end
    elseif spec.style == "flower" then
        for stem = 0, 2 do
            local x = (stem - 1) * 0.24
            local height = s * (0.72 + stem * 0.15)
            Add(b, spec.name .. "花茎" .. stem, x, height * 0.5, (stem % 2) * 0.16,
                0.07, height, 0.07, C.forest, "leaf", "cylinder", 0, 0, 0, nil, "decorative")
            for petal = 0, 4 do
                local angle = petal * TAU / 5
                CrownBall(b, spec.name .. "花瓣" .. stem .. "-" .. petal,
                    x + math.sin(angle) * 0.15, height + math.cos(angle) * 0.03,
                    (stem % 2) * 0.16 + math.cos(angle) * 0.15,
                    0.18, 0.10, 0.18, spec.color)
            end
            Add(b, spec.name .. "花芯" .. stem, x, height + 0.04, (stem % 2) * 0.16,
                0.13, 0.11, 0.13, C.yellow, "glow", "sphere", 0, 0, 0, nil, "decorative")
        end
    elseif spec.style == "bush" or spec.style == "flower_bush" then
        for index = 0, 4 do
            local angle = index * TAU / 5
            CrownBall(b, spec.name .. "叶团" .. index,
                math.sin(angle) * s * 0.34, s * (0.43 + index % 2 * 0.16),
                math.cos(angle) * s * 0.34, s * 0.78, s * 0.66, s * 0.78,
                index % 2 == 0 and C.leaf or C.forest)
        end
        if spec.style == "flower_bush" then
            for flower = 0, 8 do
                local angle = flower * TAU / 9
                CrownBall(b, spec.name .. "花团" .. flower,
                    math.sin(angle) * s * 0.58, s * (0.58 + flower % 3 * 0.12),
                    math.cos(angle) * s * 0.58, 0.19, 0.16, 0.19,
                    flower % 2 == 0 and C.rose or C.cloud)
            end
        end
    elseif spec.style == "reeds" then
        for index = 0, 8 do
            local angle = index * 2.4
            local radius = 0.18 + index % 3 * 0.16
            local height = s * (0.72 + index % 4 * 0.17)
            local x, z = math.sin(angle) * radius, math.cos(angle) * radius
            Add(b, spec.name .. "苇杆" .. index, x, height * 0.5, z,
                0.055, height, 0.055, C.forest, "leaf", "cylinder", 0, 0, 0, nil, "decorative")
            Add(b, spec.name .. "苇穗" .. index, x, height + 0.13, z,
                0.10, 0.32, 0.10, C.earth, "fabric", "cylinder", 0, 0, 0, nil, "decorative")
        end
    end
    return b
end

local function Door(blocks, prefix, x, floorTop, z, facing, color)
    local width, height, thickness, openingWidth = 1.18, 1.68, 0.10, 1.12
    if facing == "z" then facing = "front" elseif facing == "x" then facing = "right" end
    local sideWall = facing == "right" or facing == "left"
    local along = sideWall and z or x
    -- The authored door is permanently shown fully open. It parks on the
    -- longer adjacent wall section and never occupies the actual doorway.
    local slideSign = along > 0.12 and -1 or 1
    local storedOffset = slideSign * (openingWidth * 0.5 + width * 0.5 + 0.06)
    local normalX = facing == "right" and 1 or facing == "left" and -1 or 0
    local normalZ = facing == "front" and 1 or 0
    local surfaceOffset = 0.08
    local leafX = sideWall and x + normalX * surfaceOffset or x + storedOffset
    local leafZ = sideWall and z + storedOffset or z + normalZ * surfaceOffset
    local leaf = Add(blocks, prefix .. "贴墙全开抽拉门板", leafX, floorTop + height * 0.5, leafZ,
        sideWall and thickness or width, height, sideWall and width or thickness,
        color or C.blue, "painted_wood", "box", 0, 0, 0, "door")
    leaf.collisionRole = "decorative"

    -- Only the two parts a readable sliding door needs are retained: one
    -- continuous upper rail and one recessed pull. There is deliberately no
    -- threshold, floor guide, roller ornament or added jamb in the passage.
    local trackLength = openingWidth + width + 0.20
    local trackOffset = slideSign * width * 0.5
    local trackX = sideWall and x + normalX * surfaceOffset or x + trackOffset
    local trackZ = sideWall and z + trackOffset or z + normalZ * surfaceOffset
    Add(blocks, prefix .. "黄铜抽拉门上轨", trackX, floorTop + height + 0.10, trackZ,
        sideWall and 0.12 or trackLength, 0.12, sideWall and trackLength or 0.12,
        C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
    local handleOffset = -slideSign * width * 0.31
    local handleNormal = thickness * 0.58 + 0.018
    local handleX = sideWall and leafX + normalX * handleNormal or leafX + handleOffset
    local handleZ = sideWall and leafZ + handleOffset or leafZ + normalZ * handleNormal
    Add(blocks, prefix .. "黄铜嵌入拉手", handleX, floorTop + 0.88, handleZ,
        sideWall and 0.035 or 0.13, 0.28, sideWall and 0.13 or 0.035,
        C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
end

local function Window(blocks, prefix, x, y, z, facing, width, height, frameColor)
    width, height = width or 1.05, height or 0.82
    local side = facing == "x"
    Add(blocks, prefix .. "雾蓝玻璃窗", x, y, z,
        side and 0.10 or width, height, side and width or 0.10,
        C.glass, "glass")
    Add(blocks, prefix .. "窗框上", x, y + height * 0.5, z,
        side and 0.14 or width + 0.16, 0.10, side and width + 0.16 or 0.14,
        frameColor or C.darkWood, "painted_wood")
    Add(blocks, prefix .. "窗框下", x, y - height * 0.5, z,
        side and 0.14 or width + 0.16, 0.10, side and width + 0.16 or 0.14,
        frameColor or C.darkWood, "painted_wood")
    Add(blocks, prefix .. "窗框中", x, y, z,
        side and 0.13 or 0.10, height, side and 0.10 or 0.13,
        frameColor or C.darkWood, "painted_wood")
end

local function AddRoomShell(blocks, prefix, width, depth, floorY, height, body, doorWall, doorOffset, doorColor)
    local floorTop = floorY + 0.10
    Add(blocks, prefix .. "室内地板", 0, floorY, 0, width, 0.20, depth,
        C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
    local wallBottom, wallY = floorTop, floorTop + height * 0.5
    doorWall = doorWall or "front"
    doorOffset = doorOffset or 0
    local openingWidth, openingHeight = 1.12, 1.75
    local function AddDoorWallPieces(axis, fixed, span, offset)
        local minimum, maximum = -span * 0.5, span * 0.5
        local openingMin, openingMax = offset - openingWidth * 0.5, offset + openingWidth * 0.5
        local leftWidth, rightWidth = openingMin - minimum, maximum - openingMax
        if axis == "z" then
            Add(blocks, prefix .. doorWall .. "墙·门洞左", (minimum + openingMin) * 0.5, wallY, fixed,
                leftWidth, height, 0.24, body, "solid")
            Add(blocks, prefix .. doorWall .. "墙·门洞右", (openingMax + maximum) * 0.5, wallY, fixed,
                rightWidth, height, 0.24, body, "solid")
            Add(blocks, prefix .. doorWall .. "墙·门洞上", offset, floorTop + openingHeight + (height - openingHeight) * 0.5, fixed,
                openingWidth, height - openingHeight, 0.24, body, "solid", "box", 0, 0, 0, nil, "decorative")
        else
            Add(blocks, prefix .. doorWall .. "墙·门洞左", fixed, wallY, (minimum + openingMin) * 0.5,
                0.24, height, leftWidth, body, "solid")
            Add(blocks, prefix .. doorWall .. "墙·门洞右", fixed, wallY, (openingMax + maximum) * 0.5,
                0.24, height, rightWidth, body, "solid")
            Add(blocks, prefix .. doorWall .. "墙·门洞上", fixed, floorTop + openingHeight + (height - openingHeight) * 0.5, offset,
                0.24, height - openingHeight, openingWidth, body, "solid", "box", 0, 0, 0, nil, "decorative")
        end
    end
    if doorWall == "front" then AddDoorWallPieces("z", depth * 0.5, width, doorOffset)
    elseif doorWall == "right" then AddDoorWallPieces("x", width * 0.5, depth, doorOffset)
    else AddDoorWallPieces("x", -width * 0.5, depth, doorOffset) end
    if doorWall ~= "front" then
        Add(blocks, prefix .. "front墙", 0, wallY, depth * 0.5, width, height, 0.24, body, "solid")
    end
    Add(blocks, prefix .. "back墙", 0, wallY, -depth * 0.5, width, height, 0.24, body, "solid")
    if doorWall ~= "left" then
        Add(blocks, prefix .. "left墙", -width * 0.5, wallY, 0, 0.24, height, depth, body, "solid")
    end
    if doorWall ~= "right" then
        Add(blocks, prefix .. "right墙", width * 0.5, wallY, 0, 0.24, height, depth, body, "solid")
    end
    if doorWall == "front" then
        Door(blocks, prefix, doorOffset, floorTop, depth * 0.5 + 0.03, "front", doorColor)
    elseif doorWall == "right" then
        Door(blocks, prefix, width * 0.5 + 0.03, floorTop, doorOffset, "right", doorColor)
    else
        Door(blocks, prefix, -width * 0.5 - 0.03, floorTop, doorOffset, "left", doorColor)
    end
    local windowY = floorTop + height * 0.58
    if doorWall ~= "left" then Window(blocks, prefix .. "左侧", -width * 0.5 - 0.03, windowY, 0.42, "x") end
    if doorWall ~= "right" then Window(blocks, prefix .. "右侧", width * 0.5 + 0.03, windowY, -0.42, "x") end
    if doorWall ~= "back" then Window(blocks, prefix .. "后侧", 0.52, windowY, -depth * 0.5 - 0.03, "z") end
    return floorTop, floorTop + height
end

local function AddRoof(blocks, prefix, width, depth, wallTop, color, height, shape)
    height = height or 1.18
    Add(blocks, prefix .. "完整屋顶", 0, wallTop + height * 0.5, 0,
        width + 0.48, height, depth + 0.58,
        color or C.terracotta, "roof_tile", shape or "tri_prism")
    Add(blocks, prefix .. "屋脊压条", 0, wallTop + height + 0.02, 0,
        0.14, depth + 0.72, 0.14, C.brass, "metal", "cylinder", 90, 0, 0, nil, "decorative")
end

local function AddInterior(blocks, prefix, floorTop, width, depth, style, doorWall)
    Add(blocks, prefix .. "室内地毯", 0, floorTop + 0.025, 0.25,
        math.min(2.1, width * 0.48), 0.05, math.min(1.35, depth * 0.36),
        style == "shop" and C.sky or C.rose, "fabric", "box", 0, 0, 0, nil, "decorative")
    Add(blocks, prefix .. "阅读桌面", width * 0.18, floorTop + 0.52, -depth * 0.12,
        1.20, 0.12, 0.66, C.wood, "painted_wood")
    for leg = -1, 1, 2 do
        Add(blocks, prefix .. "桌腿" .. leg, width * 0.18 + leg * 0.46, floorTop + 0.25, -depth * 0.12,
            0.11, 0.50, 0.11, C.darkWood, "wood", "cylinder")
    end
    Add(blocks, prefix .. "承重书架", -width * 0.5 + 0.28, floorTop + 0.72, -depth * 0.20,
        0.34, 1.38, 1.45, C.wood, "painted_wood")
    for shelf = 0, 3 do
        Add(blocks, prefix .. "书架横板" .. shelf, -width * 0.5 + 0.38,
            floorTop + 0.18 + shelf * 0.34, -depth * 0.20,
            0.32, 0.08, 1.28, C.darkWood, "wood")
    end
    if style == "bedroom" then
        local bedX = doorWall == "right" and -width * 0.22 or width * 0.22
        Add(blocks, prefix .. "床架", bedX, floorTop + 0.22, -depth * 0.34,
            1.15, 0.30, 1.72, C.wood, "wood")
        Add(blocks, prefix .. "床垫", bedX, floorTop + 0.40, -depth * 0.34,
            1.04, 0.18, 1.58, C.cloud, "fabric")
        Add(blocks, prefix .. "枕头", bedX, floorTop + 0.54, -depth * 0.75,
            0.72, 0.18, 0.36, C.rose, "fabric", "sphere", 0, 0, 0, nil, "decorative")
    elseif style == "shop" then
        Add(blocks, prefix .. "商店柜台", -0.35, floorTop + 0.48, -depth * 0.22,
            width * 0.48, 0.82, 0.48, C.wood, "painted_wood")
        for jar = 0, 4 do
            Add(blocks, prefix .. "陈列陶罐" .. jar, -width * 0.18 + jar * 0.28,
                floorTop + 1.00, -depth * 0.22, 0.18, 0.30 + jar % 2 * 0.09, 0.18,
                jar % 2 == 0 and C.terracotta or C.sky, "ceramic", "cylinder")
        end
    else
        -- Keep the complete chair against the left side of the room.  The old
        -- backrest used depth * 0.48 while its seat used depth * 0.23, which
        -- split the chair in half and left the backrest directly in the front
        -- doorway of the sunny cottage.
        local chairSide = doorWall == "left" and 1 or -1
        local chairX, chairZ = chairSide * math.min(1.0, width * 0.25), depth * 0.12
        Add(blocks, prefix .. "靠背椅座", chairX, floorTop + 0.30, chairZ,
            0.62, 0.16, 0.62, C.rose, "fabric")
        Add(blocks, prefix .. "靠背椅背", chairX, floorTop + 0.70, chairZ + 0.36,
            0.62, 0.72, 0.14, C.rose, "fabric")
    end
    Add(blocks, prefix .. "室内暖光", width * 0.30, floorTop + 1.45, depth * 0.25,
        0.28, 0.34, 0.28, C.yellow, "glow", "sphere", 0, 0, 0, nil, "decorative")
end

local function SideStair(blocks, prefix, width, depth, side, fromTop, toTop, reverse)
    local steps = math.max(7, math.ceil((toTop - fromTop) / 0.27))
    -- Keep upper doors a full frame-width away from building corners. The old
    -- 0.58 m inset left only a 2 cm wall sliver beside a 1.12 m opening.
    local landingInset = 0.92
    local startZ, endZ = reverse and (-depth * 0.5 + landingInset) or (depth * 0.5 + 0.38),
        reverse and (depth * 0.5 - landingInset) or (-depth * 0.5 + landingInset)
    local x = side * (width * 0.5 + 0.58)
    for index = 1, steps do
        local amount = index / steps
        local top = fromTop + (toTop - fromTop) * amount
        local z = startZ + (endZ - startZ) * amount
        Add(blocks, prefix .. "外部连续阶梯" .. index, x, top - 0.08, z,
            0.82, 0.16, 0.42, C.paleStone, "stone", "box", 0, 0, 0, "base", "surface")
        if index % 2 == 0 then
            Add(blocks, prefix .. "阶梯护栏柱" .. index, x + side * 0.48, top + 0.31, z,
                0.09, 0.72, 0.09, C.brass, "metal", "cylinder", 0, 0, 0, nil, "decorative")
        end
    end
    local travelDirection = endZ > startZ and 1 or -1
    Add(blocks, prefix .. "上层入口平台", side * (width * 0.5 + 0.44), toTop - 0.07,
        endZ + travelDirection * 0.24,
        1.18, 0.14, 0.72, C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
    return endZ
end

local function AddFoundation(blocks, prefix, width, depth)
    -- Keep the plinth fully inside the wall line. The former oversized slab
    -- projected 24 cm beyond every facade, leaving a square block in front of
    -- every otherwise-open doorway.
    Add(blocks, prefix .. "内收石砌基础", 0, 0.09, 0,
        math.max(0.8, width - 0.20), 0.18, math.max(0.8, depth - 0.20),
        C.paleStone, "stone", "box", 0, 0, 0, "base", "surface")
end

local HOUSE_SPECS = {
    { id = "sunny-meadow-cottage", name = "晴坡小屋", style = "cottage", storeys = 1,
        description = "可进入的一层住宅，带起居家具、书架、壁炉和门廊细节。" },
    { id = "blue-roof-family-house", name = "蓝顶家庭屋", style = "family", storeys = 2,
        description = "两层可参观住宅，外部连续楼梯连接卧室层和阳台。" },
    { id = "brick-corner-shop", name = "暖砖转角商店", style = "shop", storeys = 2,
        description = "下层商店、上层起居室，带柜台、货架、遮棚和侧梯。" },
    { id = "narrow-three-storey-home", name = "窄面三层民居", style = "narrow", storeys = 3,
        description = "小占地三层住宅，两段外梯分别通往每一层。" },
    { id = "glass-garden-studio", name = "玻璃花园工坊", style = "glass", storeys = 1,
        description = "真正中空可进入的玻璃工坊，带工作桌、盆栽与顶窗。" },
    { id = "stone-balcony-lodge", name = "石基露台旅舍", style = "lodge", storeys = 2,
        description = "宽体两层旅舍，石砌下层、木构上层和可到达露台。" },
}

local function BuildHouse(spec)
    local b = {}
    if spec.style == "glass" then
        local w, d, floorY, height = 5.4, 4.2, 0.18, 2.55
        AddFoundation(b, spec.name, w, d)
        Add(b, spec.name .. "室内地板", 0, floorY, 0, w, 0.20, d, C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
        local floorTop, wallTop = floorY + 0.10, floorY + 0.10 + height
        for _, x in ipairs({ -w * 0.5, -w * 0.25, 0, w * 0.25, w * 0.5 }) do
            Add(b, spec.name .. "温室立柱" .. x, x, floorTop + height * 0.5, 0,
                0.12, height, 0.12, C.brass, "metal", "cylinder")
        end
        for _, z in ipairs({ -d * 0.5, d * 0.5 }) do
            for panel = -1, 1 do
                -- The front centre bay is a real 1.24 m entrance, not a
                -- transparent collider hidden behind the half-open door.
                if z < 0 or panel ~= 0 then
                    local openingName = z > 0 and (panel < 0 and "前门洞左玻璃墙" or "前门洞右玻璃墙")
                        or "后侧玻璃墙"
                    Add(b, spec.name .. openingName .. panel, panel * 1.42,
                        floorTop + height * 0.52, z, 1.24, height * 0.86, 0.09, C.glass, "glass")
                end
            end
        end
        for _, x in ipairs({ -w * 0.5, w * 0.5 }) do
            Add(b, spec.name .. "侧面玻璃墙" .. x, x, floorTop + height * 0.52, 0,
                0.09, height * 0.86, d - 0.34, C.glass, "glass")
        end
        Door(b, spec.name, 0, floorTop, d * 0.5 + 0.04, "front", C.sky)
        Add(b, spec.name .. "屋盖玻璃", 0, wallTop + 0.58, 0, w + 0.36, 1.16, d + 0.42,
            C.glass, "glass", "tri_prism", 0, 0, 0, nil, "decorative")
        Add(b, spec.name .. "屋顶黄铜脊", 0, wallTop + 1.18, 0, 0.13, d + 0.50, 0.13,
            C.brass, "metal", "cylinder", 90, 0, 0, nil, "decorative")
        AddInterior(b, spec.name, floorTop, w, d, "workshop")
        for pot = -2, 2 do
            Add(b, spec.name .. "陶盆" .. pot, pot * 0.72, floorTop + 0.19, -d * 0.30,
                0.38, 0.38, 0.38, C.terracotta, "ceramic", "cylinder")
            CrownBall(b, spec.name .. "盆栽" .. pot, pot * 0.72, floorTop + 0.58, -d * 0.30,
                0.48, 0.56, 0.48, pot % 2 == 0 and C.leaf or C.grassLight)
        end
        return b
    end

    local width, depth, storyHeight, body, roofColor
    if spec.style == "cottage" then width, depth, storyHeight, body, roofColor = 4.8, 4.2, 2.18, C.plaster, C.terracotta
    elseif spec.style == "family" then width, depth, storyHeight, body, roofColor = 5.6, 4.7, 2.18, C.plaster, C.blue
    elseif spec.style == "shop" then width, depth, storyHeight, body, roofColor = 6.0, 4.5, 2.28, C.brick, C.terracotta
    elseif spec.style == "narrow" then width, depth, storyHeight, body, roofColor = 3.8, 4.25, 2.02, C.plasterShade, C.lavender
    else width, depth, storyHeight, body, roofColor = 6.2, 5.1, 2.25, C.paleStone, C.darkWood end
    AddFoundation(b, spec.name, width, depth)

    -- A 28 cm finished-floor height remains readable while the 1.2 m explorer
    -- can walk straight through the doorway without a podium-like threshold.
    local floorY = 0.18
    local groundTop, groundWallTop = AddRoomShell(b, spec.name .. "一层", width, depth, floorY,
        storyHeight, body, "front", spec.style == "shop" and -1.35 or 0,
        spec.style == "lodge" and C.terracotta or C.blue)
    AddInterior(b, spec.name .. "一层", groundTop, width, depth,
        spec.style == "shop" and "shop" or "living", "front")

    local lastWallTop = groundWallTop
    if spec.storeys >= 2 then
        local secondFloorY = floorY + storyHeight + 0.20
        local secondFloorTop = secondFloorY + 0.10
        local stairZ = SideStair(b, spec.name .. "一至二层", width, depth, 1, groundTop, secondFloorTop, false)
        local secondBody = spec.style == "lodge" and C.plaster or body
        local secondTop, secondWallTop = AddRoomShell(b, spec.name .. "二层", width, depth,
            secondFloorY, storyHeight, secondBody, "right", stairZ,
            spec.style == "shop" and C.terracotta or C.sky)
        AddInterior(b, spec.name .. "二层", secondTop, width, depth, "bedroom", "right")
        Add(b, spec.name .. "二层连续露台", 0, secondTop - 0.07, depth * 0.5 + 0.62,
            width * 0.72, 0.14, 1.05, C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
        for post = -2, 2 do
            Add(b, spec.name .. "露台栏杆柱" .. post, post * width * 0.15, secondTop + 0.42,
                depth * 0.5 + 1.05, 0.09, 0.82, 0.09, C.brass, "metal", "cylinder")
        end
        lastWallTop = secondWallTop

        if spec.storeys >= 3 then
            local thirdFloorY = secondFloorY + storyHeight + 0.20
            local thirdFloorTop = thirdFloorY + 0.10
            -- The next stair changes sides. A real U-shaped second-floor
            -- gallery connects the right-hand arrival platform to the left
            -- stair start; without it the upper stair looked plausible but
            -- was unreachable from the second-floor door.
            for gallerySide = -1, 1, 2 do
                Add(b, spec.name .. "二层连续环廊侧段" .. gallerySide,
                    gallerySide * (width * 0.5 + 0.47), secondTop - 0.07, 0,
                    0.72, 0.14, depth + 0.92, C.wood, "painted_wood", "box",
                    0, 0, 0, "base", "surface")
                for rail = -2, 2 do
                    Add(b, spec.name .. "二层环廊外栏" .. gallerySide .. "-" .. rail,
                        gallerySide * (width * 0.5 + 0.88), secondTop + 0.34, rail * depth * 0.21,
                        0.08, 0.72, 0.08, C.brass, "metal", "cylinder",
                        0, 0, 0, nil, "decorative")
                end
            end
            Add(b, spec.name .. "二层连续环廊后段", 0, secondTop - 0.07,
                -depth * 0.5 - 0.47, width + 1.66, 0.14, 0.72,
                C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
            local thirdStairZ = SideStair(b, spec.name .. "二至三层", width, depth, -1,
                secondTop, thirdFloorTop, true)
            local thirdTop, thirdWallTop = AddRoomShell(b, spec.name .. "三层", width, depth,
                thirdFloorY, storyHeight, C.plaster, "left", thirdStairZ, C.terracotta)
            AddInterior(b, spec.name .. "三层", thirdTop, width, depth, "living", "left")
            lastWallTop = thirdWallTop
        end
    end
    AddRoof(b, spec.name, width, depth, lastWallTop, roofColor,
        spec.style == "narrow" and 1.35 or 1.12,
        spec.style == "lodge" and "pyramid" or "tri_prism")

    if spec.style == "cottage" then
        for x = -1, 1, 2 do
            Add(b, spec.name .. "门廊柱" .. x, x * 0.86, groundTop + 0.85, depth * 0.5 + 1.12,
                0.16, 1.70, 0.16, C.darkWood, "wood", "cylinder")
        end
        Add(b, spec.name .. "石砌烟囱", width * 0.30, lastWallTop + 0.70, -0.60,
            0.58, 1.80, 0.58, C.shadowStone, "stone")
    elseif spec.style == "shop" then
        Add(b, spec.name .. "商店遮棚", -1.25, groundTop + 1.62, depth * 0.5 + 0.72,
            2.35, 0.14, 1.05, C.sky, "fabric", "box", -8, 0, 0, nil, "decorative")
        Add(b, spec.name .. "悬挂店牌", 1.82, groundTop + 1.62, depth * 0.5 + 0.42,
            0.80, 0.58, 0.10, C.yellow, "painted_wood")
    elseif spec.style == "lodge" then
        for beam = -2, 2 do
            Add(b, spec.name .. "外露木梁" .. beam, beam * width * 0.18, lastWallTop - 0.80, depth * 0.5 + 0.16,
                0.15, 1.45, 0.15, C.darkWood, "wood", "cylinder")
        end
        Add(b, spec.name .. "大厅壁炉", -width * 0.30, groundTop + 0.68, -depth * 0.5 + 0.30,
            1.15, 1.28, 0.48, C.shadowStone, "stone")
        Add(b, spec.name .. "壁炉余烬", -width * 0.30, groundTop + 0.36, -depth * 0.5 + 0.58,
            0.62, 0.28, 0.18, C.amber, "fire", "sphere", 0, 0, 0, nil, "decorative")
    end
    return b
end

local AIRCRAFT_SPECS = {
    { id = "wind-ribbon-glider", name = "风带滑翔翼", style = "glider", description = "轻木骨架、布翼和落地滑橇组成的单人滑翔器。" },
    { id = "cloud-courier-airship", name = "云岬邮递飞艇", style = "airship", description = "保留现有飞艇画风，细化气囊索、舵面、吊舱和灯具。" },
    { id = "storybook-balloon", name = "绘本热气球", style = "balloon", description = "分片气囊、编织吊篮、燃烧器与四根承重索。" },
    { id = "crystal-hover-skiff", name = "晶芯悬浮艇", style = "skiff", description = "短途悬浮小艇，带晶体动力、操纵台和防撞环。" },
}

local function BuildAircraft(spec)
    local b = {}
    if spec.style == "glider" then
        Add(b, spec.name .. "中央龙骨", 0, 0.62, 0, 0.16, 0.16, 4.2, C.darkWood, "wood")
        Add(b, spec.name .. "横向承重梁", 0, 0.82, 0.15, 6.4, 0.14, 0.14, C.brass, "metal")
        for side = -1, 1, 2 do
            Add(b, spec.name .. "布翼" .. side, side * 1.75, 0.92, 0.15,
                3.15, 0.11, 2.25, side < 0 and C.sky or C.rose, "fabric", "tri_prism", 0, side < 0 and 180 or 0, 0, nil, "decorative")
            Add(b, spec.name .. "翼端杆" .. side, side * 3.05, 0.80, 0.12,
                0.12, 0.12, 2.45, C.darkWood, "wood")
            Add(b, spec.name .. "落地滑橇" .. side, side * 0.48, 0.12, 0.42,
                0.10, 0.10, 2.05, C.brass, "metal")
        end
        Add(b, spec.name .. "驾驶吊带", 0, 0.48, 0.42, 0.62, 0.68, 0.82, C.rose, "fabric", "box", 0, 0, 0, nil, "decorative")
        Add(b, spec.name .. "垂直尾舵", 0, 1.18, -1.62, 0.12, 1.08, 1.15, C.yellow, "fabric", "tri_prism", 0, 0, 90, nil, "decorative")
    elseif spec.style == "airship" then
        Add(b, spec.name .. "承重吊舱地板", 0, 0.34, 0, 3.7, 0.34, 1.65, C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
        Add(b, spec.name .. "吊舱船体", 0, 0.58, 0, 4.35, 0.86, 1.95, C.blue, "painted_wood", "tri_prism", 0, 0, 180)
        Add(b, spec.name .. "前挡风玻璃", 1.48, 0.92, 0, 0.10, 0.72, 1.05, C.glass, "glass")
        for rib = -3, 3 do
            Add(b, spec.name .. "气囊肋骨" .. rib, rib * 0.65, 3.25, 0,
                3.05, 2.25, 0.54, C.brass, "metal", "torus", 0, 90, 0, nil, "decorative")
        end
        Add(b, spec.name .. "主气囊", 0, 3.25, 0, 5.35, 2.35, 3.05,
            C.cloud, "fabric", "sphere", 0, 0, 0, nil, "decorative")
        for cable = -2, 2 do
            Add(b, spec.name .. "气囊承重索" .. cable, cable * 0.72, 1.86, cable % 2 * 0.52,
                0.07, 2.15, 0.07, C.darkWood, "fabric", "cylinder", 0, 0, cable * 8, nil, "decorative")
        end
        for side = -1, 1, 2 do
            Add(b, spec.name .. "动力轴" .. side, -1.40, 0.74, side * 1.18,
                0.16, 0.72, 0.16, C.brass, "metal", "cylinder", 90)
            for blade = 0, 3 do
                Add(b, spec.name .. "动力桨叶" .. side .. "-" .. blade, -1.40, 0.74, side * 1.52,
                    0.16, 1.20, 0.10, C.sky, "painted_wood", "box", 0, 0, blade * 45, nil, "decorative")
            end
        end
        Add(b, spec.name .. "垂直尾舵", -2.35, 1.05, 0, 0.12, 1.75, 1.38, C.rose, "fabric", "tri_prism", 0, 0, 90, nil, "decorative")
        Add(b, spec.name .. "航行暖光", 1.78, 0.62, 0, 0.24, 0.28, 0.24, C.yellow, "glow", "sphere", 0, 0, 0, nil, "decorative")
    elseif spec.style == "balloon" then
        Add(b, spec.name .. "吊篮底", 0, 0.20, 0, 1.15, 0.30, 1.05, C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
        for side = -1, 1, 2 do
            Add(b, spec.name .. "吊篮围板X" .. side, side * 0.56, 0.58, 0, 0.10, 0.72, 1.05, C.earth, "wood")
            Add(b, spec.name .. "吊篮围板Z" .. side, 0, 0.58, side * 0.51, 1.15, 0.72, 0.10, C.earth, "wood")
        end
        for cable = 0, 3 do
            local x = cable % 2 == 0 and -0.48 or 0.48
            local z = cable < 2 and -0.43 or 0.43
            Add(b, spec.name .. "承重索" .. cable, x, 2.02, z, 0.06, 2.85, 0.06,
                C.darkWood, "fabric", "cylinder", 0, 0, 0, nil, "decorative")
        end
        for slice = 0, 7 do
            local angle = slice * TAU / 8
            CrownBall(b, spec.name .. "彩色气囊片" .. slice,
                math.sin(angle) * 0.58, 3.72, math.cos(angle) * 0.58,
                1.55, 2.62, 1.55, slice % 3 == 0 and C.rose or slice % 2 == 0 and C.yellow or C.sky)
            b[#b].materialId = "fabric"
        end
        Add(b, spec.name .. "燃烧器", 0, 1.12, 0, 0.34, 0.42, 0.34, C.brass, "metal", "cylinder")
        Add(b, spec.name .. "燃烧暖焰", 0, 1.42, 0, 0.23, 0.36, 0.23, C.amber, "fire", "cone", 0, 0, 0, nil, "decorative")
    else
        Add(b, spec.name .. "艇底龙骨", 0, 0.24, 0, 4.1, 0.48, 1.75, C.blue, "metal", "tri_prism", 0, 0, 180)
        Add(b, spec.name .. "站立甲板", 0, 0.46, 0, 3.35, 0.18, 1.38, C.wood, "painted_wood", "box", 0, 0, 0, "base", "surface")
        Add(b, spec.name .. "前部挡风", 1.25, 0.86, 0, 0.10, 0.68, 1.05, C.glass, "glass")
        Add(b, spec.name .. "操纵台", 0.62, 0.76, 0, 0.48, 0.64, 0.72, C.brass, "metal")
        for side = -1, 1, 2 do
            Add(b, spec.name .. "防撞环" .. side, 0, 0.40, side * 0.88,
                3.62, 0.78, 0.18, C.brass, "metal", "torus", 0, 0, 0, nil, "decorative")
            Add(b, spec.name .. "悬浮晶核" .. side, -0.62, 0.34, side * 0.64,
                0.48, 0.62, 0.48, C.crystal, "crystal", "tetra", 0, 45, 0, nil, "decorative")
            Add(b, spec.name .. "尾部稳定翼" .. side, -1.72, 0.62, side * 0.68,
                1.12, 0.12, 0.82, side < 0 and C.rose or C.sky, "fabric", "tri_prism", 0, side < 0 and 180 or 0, 0, nil, "decorative")
        end
        Add(b, spec.name .. "晶芯柔光", -0.62, 0.22, 0, 0.34, 0.34, 0.34, C.yellow, "glow", "sphere", 0, 0, 0, nil, "decorative")
    end
    return b
end

local FENCE_SPECS = {
    { id = "rustic-wood-fence", name = "原木横栏", style = "wood", description = "3 米通用直线木围栏。" },
    { id = "wood-fence-corner", name = "原木转角栏", style = "corner", description = "九十度转角连接件。" },
    { id = "swing-garden-gate", name = "花园推拉门", style = "gate", description = "门扇完全滑开，中央通道保持畅通。" },
    { id = "white-picket-fence", name = "白色尖桩栏", style = "picket", description = "细密尖桩与双横梁。" },
    { id = "storybook-stone-wall", name = "绘本矮石墙", style = "stone", description = "错缝砌筑的低矮石墙。" },
    { id = "brass-iron-railing", name = "黄铜铁艺栏", style = "iron", description = "细杆、顶球和上下承重梁。" },
    { id = "rope-post-barrier", name = "麻绳立柱栏", style = "rope", description = "适合码头和山径的柔绳护栏。" },
    { id = "living-hedge-segment", name = "常绿树篱段", style = "hedge", description = "多团叶片组成的可拼接绿篱。" },
}

local function BuildFence(spec)
    local b, length = {}, 3.2
    local function Post(x, z, color, material, height)
        Add(b, spec.name .. "立柱" .. x .. ":" .. z, x, (height or 1.15) * 0.5, z,
            0.22, height or 1.15, 0.22, color or C.darkWood, material or "wood", "cylinder")
    end
    if spec.style == "wood" or spec.style == "corner" then
        for _, x in ipairs({ -length * 0.5, 0, length * 0.5 }) do Post(x, 0) end
        for y = 0.42, 0.88, 0.46 do
            Add(b, spec.name .. "横梁" .. y, 0, y, 0, length + 0.18, 0.16, 0.16, C.wood, "wood")
        end
        if spec.style == "corner" then
            for _, z in ipairs({ 0.80, length * 0.5 }) do Post(-length * 0.5, z) end
            for y = 0.42, 0.88, 0.46 do
                Add(b, spec.name .. "转角横梁" .. y, -length * 0.5, y, length * 0.5 * 0.5,
                    0.16, 0.16, length * 0.5 + 0.18, C.wood, "wood")
            end
        end
    elseif spec.style == "gate" then
        Post(-1.15, 0, C.darkWood, "wood", 1.65); Post(1.15, 0, C.darkWood, "wood", 1.65)
        local openingWidth, width, height = 2.08, 1.90, 1.22
        local storedX = openingWidth * 0.5 + width * 0.5 + 0.06
        local gate = Add(b, spec.name .. "贴墙全开抽拉门板", storedX, height * 0.5, 0.08,
            width, height, 0.10, C.sky, "painted_wood", "box", 0, 0, 0, "door", "decorative")
        gate.collisionRole = "decorative"
        Add(b, spec.name .. "黄铜抽拉门上轨", width * 0.5, height + 0.10, 0.08,
            openingWidth + width + 0.20, 0.12, 0.12,
            C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
        Add(b, spec.name .. "黄铜嵌入拉手", storedX - width * 0.31, 0.70, 0.15,
            0.13, 0.28, 0.035, C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
    elseif spec.style == "picket" then
        for index = -7, 7 do
            Add(b, spec.name .. "尖桩" .. index, index * 0.23, 0.58 + math.abs(index % 2) * 0.04, 0,
                0.13, 1.16, 0.13, C.cloud, "painted_wood", "pyramid")
        end
        for y = 0.34, 0.78, 0.44 do
            Add(b, spec.name .. "白色横梁" .. y, 0, y, 0.04, 3.45, 0.13, 0.13, C.cloud, "painted_wood")
        end
    elseif spec.style == "stone" then
        for row = 0, 2 do
            local count = row == 2 and 4 or 5
            for index = 0, count - 1 do
                local width = row == 2 and 0.78 or 0.66
                Add(b, spec.name .. "错缝石块" .. row .. "-" .. index,
                    (index - (count - 1) * 0.5) * width + (row % 2) * 0.13,
                    0.22 + row * 0.40, 0, width - 0.04, 0.40, 0.58,
                    (index + row) % 2 == 0 and C.stone or C.paleStone, "stone")
            end
        end
    elseif spec.style == "iron" then
        for index = -6, 6 do
            Post(index * 0.27, 0, C.brass, "metal", 1.28)
            Add(b, spec.name .. "柱头球" .. index, index * 0.27, 1.33, 0,
                0.16, 0.16, 0.16, C.yellow, "metal", "sphere", 0, 0, 0, nil, "decorative")
        end
        for y = 0.20, 1.02, 0.82 do
            Add(b, spec.name .. "承重横梁" .. y, 0, y, 0, 3.45, 0.10, 0.12, C.brass, "metal")
        end
    elseif spec.style == "rope" then
        for _, x in ipairs({ -1.55, 0, 1.55 }) do Post(x, 0, C.darkWood, "wood", 1.25) end
        for segment = -1, 0 do
            for strand = 0, 3 do
                local amount = (strand + 0.5) / 4
                Add(b, spec.name .. "下垂绳" .. segment .. "-" .. strand,
                    segment * 1.55 + amount * 1.55, 0.86 - math.sin(amount * math.pi) * 0.26, 0,
                    0.42, 0.07, 0.07, C.wood, "fabric", "cylinder", 0, 0, 90, nil, "decorative")
            end
        end
    else
        for index = -3, 3 do
            CrownBall(b, spec.name .. "树篱叶团" .. index, index * 0.52, 0.66 + index % 2 * 0.08, 0,
                0.86, 1.18, 0.72, index % 2 == 0 and C.leaf or C.forest)
        end
        Add(b, spec.name .. "隐约枝干", 0, 0.42, 0, 3.20, 0.18, 0.18, C.darkWood, "wood")
    end
    return b
end

local STREET_SPECS = {
    { id = "warm-street-lamp", name = "暖光路灯", style = "lamp", description = "单臂黄铜路灯。" },
    { id = "twin-square-lamp", name = "双臂广场灯", style = "twin_lamp", description = "适合广场中心的双灯头路灯。" },
    { id = "garden-bollard-light", name = "花园矮灯", style = "bollard", description = "低位柔光照明单件。" },
    { id = "curved-wood-bench", name = "弧背木长椅", style = "bench", description = "带弧形靠背和金属扶手。" },
    { id = "stone-park-bench", name = "石基公园椅", style = "stone_bench", description = "厚重石脚与木坐面组合。" },
    { id = "small-cafe-set", name = "露天咖啡桌椅", style = "cafe", description = "圆桌与两把轻椅。" },
    { id = "striped-sun-umbrella", name = "条纹遮阳伞", style = "umbrella", description = "可与桌椅、摊位自由组合的遮阳伞。" },
    { id = "painted-wayfinding-sign", name = "彩绘指路牌", style = "sign", description = "三向路牌和石质底座。" },
    { id = "long-flower-planter", name = "长形花箱", style = "planter", description = "带多色小花的陶木花箱。" },
}

local function LampHead(b, prefix, x, y, z, scale)
    Add(b, prefix .. "灯架", x, y, z, 0.44 * scale, 0.14 * scale, 0.44 * scale, C.brass, "metal", "cylinder")
    Add(b, prefix .. "灯芯柔光", x, y - 0.18 * scale, z,
        0.30 * scale, 0.42 * scale, 0.30 * scale, C.yellow, "glow", "sphere", 0, 0, 0, nil, "decorative")
    Add(b, prefix .. "灯帽", x, y + 0.18 * scale, z,
        0.52 * scale, 0.24 * scale, 0.52 * scale, C.blue, "painted_wood", "cone")
end

local function BuildStreet(spec)
    local b = {}
    if spec.style == "lamp" or spec.style == "twin_lamp" then
        Add(b, spec.name .. "石质底座", 0, 0.15, 0, 0.72, 0.30, 0.72, C.paleStone, "stone", "cylinder")
        Add(b, spec.name .. "灯杆", 0, 1.65, 0, 0.18, 3.05, 0.18, C.brass, "metal", "cylinder")
        if spec.style == "lamp" then
            Add(b, spec.name .. "弯臂", 0.38, 3.00, 0, 0.80, 0.13, 0.13, C.brass, "metal", "cylinder", 0, 0, 90)
            LampHead(b, spec.name, 0.76, 2.82, 0, 1)
        else
            Add(b, spec.name .. "双向横臂", 0, 3.02, 0, 1.65, 0.14, 0.14, C.brass, "metal")
            LampHead(b, spec.name .. "左", -0.78, 2.82, 0, 0.9)
            LampHead(b, spec.name .. "右", 0.78, 2.82, 0, 0.9)
        end
    elseif spec.style == "bollard" then
        Add(b, spec.name .. "石座", 0, 0.13, 0, 0.58, 0.26, 0.58, C.stone, "stone", "cylinder")
        Add(b, spec.name .. "矮灯柱", 0, 0.62, 0, 0.22, 0.88, 0.22, C.brass, "metal", "cylinder")
        LampHead(b, spec.name, 0, 1.12, 0, 0.72)
    elseif spec.style == "bench" or spec.style == "stone_bench" then
        local supportMaterial = spec.style == "stone_bench" and "stone" or "metal"
        local supportColor = spec.style == "stone_bench" and C.stone or C.brass
        for x = -1, 1, 2 do
            Add(b, spec.name .. "承重椅脚" .. x, x * 0.78, 0.32, 0,
                0.20, 0.64, 0.54, supportColor, supportMaterial, spec.style == "stone_bench" and "box" or "cylinder")
        end
        for slat = -2, 2 do
            Add(b, spec.name .. "坐面木条" .. slat, slat * 0.28, 0.64, 0,
                0.24, 0.13, 1.05, C.wood, "painted_wood")
            Add(b, spec.name .. "弧背木条" .. slat, slat * 0.28, 1.02, -0.40,
                0.24, 0.62, 0.12, slat % 2 == 0 and C.sky or C.wood, "painted_wood", "box", -7)
        end
        for side = -1, 1, 2 do
            Add(b, spec.name .. "扶手" .. side, side * 0.83, 0.86, 0,
                0.12, 0.58, 0.72, C.brass, "metal", "torus", 0, 90, 0, nil, "decorative")
        end
    elseif spec.style == "cafe" then
        Add(b, spec.name .. "桌面", 0, 0.82, 0, 1.18, 0.14, 1.18, C.wood, "painted_wood", "cylinder")
        Add(b, spec.name .. "桌柱", 0, 0.40, 0, 0.18, 0.80, 0.18, C.brass, "metal", "cylinder")
        Add(b, spec.name .. "桌脚", 0, 0.10, 0, 0.82, 0.14, 0.82, C.brass, "metal", "box")
        for side = -1, 1, 2 do
            Add(b, spec.name .. "椅座" .. side, side * 1.02, 0.50, 0,
                0.64, 0.14, 0.64, side < 0 and C.rose or C.sky, "fabric")
            Add(b, spec.name .. "椅背" .. side, side * 1.32, 0.82, 0,
                0.14, 0.72, 0.64, side < 0 and C.rose or C.sky, "fabric")
            for leg = -1, 1, 2 do
                Add(b, spec.name .. "椅腿" .. side .. "-" .. leg, side * 1.02, 0.25, leg * 0.22,
                    0.09, 0.50, 0.09, C.brass, "metal", "cylinder")
            end
        end
    elseif spec.style == "umbrella" then
        Add(b, spec.name .. "配重石座", 0, 0.10, 0, 0.82, 0.20, 0.82, C.stone, "stone", "cylinder")
        Add(b, spec.name .. "中心伞杆", 0, 1.45, 0, 0.13, 2.70, 0.13, C.brass, "metal", "cylinder")
        for slice = 0, 7 do
            local angle = slice * 45
            local radians = math.rad(angle)
            Add(b, spec.name .. "条纹伞面" .. slice,
                math.sin(radians) * 0.70, 2.72, math.cos(radians) * 0.70,
                1.35, 0.16, 1.55, slice % 2 == 0 and C.rose or C.cloud,
                "fabric", "tri_prism", 0, angle, 0, nil, "decorative")
        end
        Add(b, spec.name .. "伞顶球", 0, 2.92, 0, 0.22, 0.22, 0.22, C.yellow, "metal", "sphere")
    elseif spec.style == "sign" then
        Add(b, spec.name .. "石座", 0, 0.12, 0, 0.68, 0.24, 0.68, C.paleStone, "stone", "cylinder")
        Add(b, spec.name .. "主立柱", 0, 1.18, 0, 0.18, 2.15, 0.18, C.darkWood, "wood", "cylinder")
        local colors = { C.sky, C.rose, C.yellow }
        for index = 0, 2 do
            Add(b, spec.name .. "方向牌" .. index, index % 2 == 0 and 0.48 or -0.48,
                1.82 - index * 0.42, 0, 1.12, 0.30, 0.12, colors[index + 1], "painted_wood", "box", 0, 0, index % 2 == 0 and -5 or 5)
            Add(b, spec.name .. "箭头" .. index, index % 2 == 0 and 1.06 or -1.06,
                1.82 - index * 0.42, 0, 0.38, 0.32, 0.12, colors[index + 1], "painted_wood", "pyramid", 0, 0, index % 2 == 0 and -90 or 90)
        end
    else
        Add(b, spec.name .. "长花箱", 0, 0.34, 0, 2.65, 0.68, 0.82, C.terracotta, "ceramic", "box")
        Add(b, spec.name .. "花箱泥土", 0, 0.69, 0, 2.42, 0.10, 0.64, C.earth, "earth")
        for flower = -4, 4 do
            Add(b, spec.name .. "花茎" .. flower, flower * 0.25, 0.98 + math.abs(flower % 2) * 0.08, 0,
                0.06, 0.58, 0.06, C.forest, "leaf", "cylinder", 0, 0, 0, nil, "decorative")
            CrownBall(b, spec.name .. "花球" .. flower, flower * 0.25, 1.30 + math.abs(flower % 2) * 0.08, 0,
                0.22, 0.18, 0.22, flower % 3 == 0 and C.yellow or flower % 2 == 0 and C.rose or C.sky)
        end
    end
    return b
end

local KIT_SPECS = {
    { id = "straight-cobble-path", name = "直线卵石路", style = "path", description = "可首尾拼接的 5 米步道路段。" },
    { id = "curved-cobble-path", name = "弧形卵石路", style = "curve", description = "四十五度转弯步道，可和直线路段连续组合。" },
    { id = "timber-footbridge", name = "原木步桥", style = "bridge", description = "带承重梁、独立桥板和双侧护栏的通用小桥。" },
    { id = "modular-stone-steps", name = "组合石阶", style = "steps", description = "八级连续石阶，可连接露台、山坡和建筑入口。" },
    { id = "shallow-lily-pond", name = "睡莲浅池", style = "pond", description = "低矮水面、自然石岸和睡莲组成的小型水景。" },
    { id = "loose-boulder-cluster", name = "苔石散落组", style = "rocks", description = "大小错落、朝向不同的七块苔石。" },
    { id = "square-timber-deck", name = "方形木平台", style = "deck", description = "带底梁的 3 米模块化木平台。" },
    { id = "vine-garden-arch", name = "藤蔓花园拱门", style = "arch", description = "净宽 1.7 米的可穿行木石拱门。" },
}

local function BuildKit(spec)
    local b = {}
    if spec.style == "path" then
        for index = -4, 4 do
            Add(b, spec.name .. "错缝路石" .. index, (index % 2) * 0.13, 0.08, index * 0.58,
                1.12 - math.abs(index % 3) * 0.08, 0.16, 0.52,
                index % 2 == 0 and C.paleStone or C.pavement, "pavement", "sphere",
                0, index * 11, 0, "base", "surface")
        end
    elseif spec.style == "curve" then
        for index = 0, 9 do
            local angle = math.rad(-22.5 + index * 5)
            Add(b, spec.name .. "扇形路石" .. index, math.sin(angle) * 2.35, 0.08,
                math.cos(angle) * 2.35 - 2.15,
                0.56, 0.16, 1.04, index % 2 == 0 and C.paleStone or C.pavement,
                "pavement", "sphere", 0, math.deg(angle), 0, "base", "surface")
        end
    elseif spec.style == "bridge" then
        for plank = -5, 5 do
            Add(b, spec.name .. "独立桥板" .. plank, 0, 0.38, plank * 0.40,
                1.92, 0.16, 0.34, plank % 2 == 0 and C.wood or C.darkWood,
                "painted_wood", "box", 0, plank % 3 - 1, 0, "base", "surface")
        end
        for side = -1, 1, 2 do
            Add(b, spec.name .. "纵向承重梁" .. side, side * 0.62, 0.23, 0,
                0.18, 0.22, 4.45, C.darkWood, "wood")
            for post = -2, 2 do
                Add(b, spec.name .. "护栏柱" .. side .. "-" .. post, side * 1.02, 0.78, post * 0.96,
                    0.11, 0.92, 0.11, C.darkWood, "wood", "cylinder", 0, 0, 0, nil, "decorative")
            end
            Add(b, spec.name .. "连续扶手" .. side, side * 1.02, 1.20, 0,
                0.12, 4.42, 0.12, C.brass, "metal", "cylinder", 90, 0, 0, nil, "decorative")
        end
    elseif spec.style == "steps" then
        for step = 0, 7 do
            local top = 0.18 + step * 0.24
            Add(b, spec.name .. "连续台阶" .. step, 0, top - 0.08, 1.62 - step * 0.46,
                1.75, 0.16, 0.52, step % 2 == 0 and C.paleStone or C.stone,
                "stone", "box", 0, 0, 0, "base", "surface")
        end
    elseif spec.style == "pond" then
        Add(b, spec.name .. "连续浅水面", 0, 0.08, 0, 3.75, 0.16, 2.75,
            C.water, "water", "sphere", 0, 0, 0, nil, "fluid")
        for stone = 0, 11 do
            local angle = stone * TAU / 12
            Add(b, spec.name .. "自然石岸" .. stone, math.sin(angle) * 1.92, 0.20,
                math.cos(angle) * 1.40, 0.68 + stone % 3 * 0.09, 0.40, 0.58,
                stone % 2 == 0 and C.stone or C.paleStone, "stone", "sphere")
        end
        for lily = 0, 4 do
            local angle = lily * TAU / 5 + 0.3
            Add(b, spec.name .. "睡莲叶" .. lily, math.sin(angle) * 1.15, 0.19,
                math.cos(angle) * 0.72, 0.52, 0.05, 0.42, C.leaf, "leaf", "sphere",
                0, lily * 31, 0, nil, "decorative")
            if lily % 2 == 0 then
                CrownBall(b, spec.name .. "睡莲花" .. lily, math.sin(angle) * 1.15, 0.27,
                    math.cos(angle) * 0.72, 0.20, 0.16, 0.20, lily == 0 and C.cloud or C.rose)
            end
        end
    elseif spec.style == "rocks" then
        local rocks = {
            { -1.05, 0.52, -0.28, 1.25, 1.04, 1.02 }, { 0.10, 0.78, 0.05, 1.55, 1.56, 1.32 },
            { 1.12, 0.42, 0.32, 0.92, 0.84, 0.82 }, { -0.62, 0.28, 0.82, 0.64, 0.56, 0.70 },
            { 0.58, 0.24, -0.88, 0.58, 0.48, 0.62 }, { 1.52, 0.20, -0.55, 0.46, 0.40, 0.52 },
            { -1.52, 0.18, 0.45, 0.42, 0.36, 0.46 },
        }
        for index, rock in ipairs(rocks) do
            Add(b, spec.name .. "散石" .. index, rock[1], rock[2], rock[3], rock[4], rock[5], rock[6],
                index % 2 == 0 and C.stone or C.paleStone, "stone", index % 3 == 0 and "tetra" or "sphere",
                0, index * 19, 0)
            if index <= 4 then
                Add(b, spec.name .. "石顶苔面" .. index, rock[1] - 0.05, rock[2] * 2 + 0.03, rock[3],
                    rock[4] * 0.62, 0.12, rock[6] * 0.55, C.moss, "moss", "sphere", 0, index * 13, 0,
                    nil, "decorative")
            end
        end
    elseif spec.style == "deck" then
        for plank = -5, 5 do
            Add(b, spec.name .. "拼接面板" .. plank, plank * 0.27, 0.28, 0,
                0.24, 0.18, 3.02, plank % 2 == 0 and C.wood or C.darkWood,
                "painted_wood", "box", 0, 0, 0, "base", "surface")
        end
        for beam = -1, 1, 2 do
            Add(b, spec.name .. "底部承重梁" .. beam, 0, 0.12, beam * 1.18,
                3.18, 0.18, 0.18, C.darkWood, "wood")
        end
    else
        for side = -1, 1, 2 do
            Add(b, spec.name .. "石质基座" .. side, side * 1.10, 0.18, 0,
                0.52, 0.36, 0.62, C.paleStone, "stone", "sphere")
            Add(b, spec.name .. "承重木柱" .. side, side * 1.10, 1.42, 0,
                0.22, 2.52, 0.22, C.darkWood, "wood", "cylinder")
        end
        for segment = -3, 3 do
            local angle = segment / 6 * math.pi
            Add(b, spec.name .. "拱顶木节" .. segment, math.sin(angle) * 1.10,
                2.54 + math.cos(angle) * 0.62, 0,
                0.34, 0.34, 0.38, segment % 2 == 0 and C.wood or C.darkWood,
                "painted_wood", "sphere")
        end
        for vine = -2, 2 do
            Add(b, spec.name .. "垂落藤蔓" .. vine, vine * 0.42, 2.32 + math.abs(vine) * 0.12, 0.18,
                0.10, 0.72 - math.abs(vine) * 0.10, 0.10, C.forest, "leaf", "cylinder",
                0, 0, vine * 6, nil, "decorative")
            CrownBall(b, spec.name .. "藤花" .. vine, vine * 0.42, 2.02 + math.abs(vine) * 0.12, 0.18,
                0.18, 0.18, 0.18, vine % 2 == 0 and C.rose or C.sky)
        end
    end
    return b
end

local RUIN_SPECS = {
    { id = "weathered-city-wall", name = "风化旧城墙", style = "wall",
        description = "一整块即呈现错缝乱石、裂痕和残缺垛口。" },
    { id = "broken-city-gate", name = "荒城断门", style = "gate",
        description = "全开推拉城门、残缺门楼和自然荒草。" },
    { id = "ruined-watchtower", name = "残缺守望塔", style = "tower",
        description = "圆形旧塔身、破损塔冠和窄窗石缝。" },
    { id = "old-castle-corner", name = "旧堡转角塔", style = "corner",
        description = "塔楼连接两向城墙，可连续拼接城防。" },
    { id = "collapsed-battlement", name = "坍塌红砖垛", style = "collapsed",
        description = "残墙、倒塌垛块与墙脚野草组成的废墟段。" },
    { id = "ancient-road-arch", name = "古道雕纹石拱", style = "arch",
        description = "大块雕纹石构成的可穿行古道拱门。" },
    { id = "overgrown-castle-keep", name = "荒草古堡主楼", style = "keep",
        description = "可进入空心主楼、全开推拉门和苔石残塔。" },
    { id = "moss-altar-terrace", name = "苔痕遗迹祭坛", style = "altar",
        description = "分层石台、古代石环和荒草组成的遗迹地标。" },
}

local function AddRuinGrass(blocks, name, x, z, scale, count)
    for index = 1, count do
        local angle = index * 2.17 + x * 0.23
        local radius = scale * (0.16 + index * 0.07)
        Add(blocks, name .. "荒草" .. index,
            x + math.sin(angle) * radius, scale * (0.52 + index % 2 * 0.08),
            z + math.cos(angle) * radius,
            scale * 0.13, scale * (0.64 + index % 3 * 0.13), scale * 0.13,
            index % 2 == 0 and C.grassLight or C.moss, "leaf", "cone",
            0, index * 29, index % 2 == 0 and 7 or -6, nil, "decorative")
    end
end

local function BuildRuin(spec)
    local b = {}
    if spec.style == "wall" then
        Add(b, spec.name .. "乱石城墙主体", 0, 1.50, 0, 6.4, 3.0, 0.86,
            C.stone, "ruin_stone")
        Add(b, spec.name .. "加厚残端", -3.05, 1.78, 0.02, 0.78, 3.56, 1.08,
            C.stone, "overgrown_stone")
        for index = -2, 2 do
            if index ~= 1 then
                Add(b, spec.name .. "残缺垛口" .. index, index * 1.17, 3.36 + (index % 2) * 0.08, 0,
                    0.72, 0.72, 0.92, index % 2 == 0 and C.paleStone or C.stone, "ruin_stone")
            end
        end
        Add(b, spec.name .. "墙顶苔层", -0.95, 3.08, 0.02, 2.8, 0.14, 0.72,
            C.moss, "overgrown_stone", "box", 0, 0, 0, nil, "decorative")
        AddRuinGrass(b, spec.name, 2.62, 0.34, 0.72, 2)
    elseif spec.style == "gate" then
        Add(b, spec.name .. "左城门侧墙", -2.25, 2.15, 0, 2.10, 4.30, 1.18,
            C.stone, "ruin_stone")
        Add(b, spec.name .. "右城门侧墙", 2.25, 1.88, 0, 2.10, 3.76, 1.18,
            C.stone, "overgrown_stone")
        Add(b, spec.name .. "城门顶梁", 0, 4.05, 0, 6.55, 1.12, 1.28,
            C.paleStone, "carved_stone")
        for index = -2, 2 do
            if index ~= -1 then
                Add(b, spec.name .. "门楼残垛" .. index, index * 1.18, 4.84 + (index % 2) * 0.05, 0,
                    0.76, 0.78, 1.18, C.stone, index == 2 and "overgrown_stone" or "ruin_stone")
            end
        end
        local openingWidth, width, height = 2.40, 2.46, 2.90
        local storedX = openingWidth * 0.5 + width * 0.5 + 0.06
        local gate = Add(b, spec.name .. "贴墙全开抽拉门板", storedX, height * 0.5, -0.64,
            width, height, 0.10, C.terracotta, "painted_wood", "box", 0, 0, 0, "door", "decorative")
        gate.collisionRole = "decorative"
        Add(b, spec.name .. "黄铜抽拉门上轨", width * 0.5, height + 0.10, -0.64,
            openingWidth + width + 0.20, 0.12, 0.12,
            C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
        Add(b, spec.name .. "黄铜嵌入拉手", storedX - width * 0.31, 1.38, -0.71,
            0.13, 0.32, 0.035, C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
        AddRuinGrass(b, spec.name, -3.05, 0.34, 0.78, 2)
        AddRuinGrass(b, spec.name, 3.05, -0.28, 0.66, 2)
    elseif spec.style == "tower" then
        Add(b, spec.name .. "风化圆塔主体", 0, 2.35, 0, 4.25, 4.70, 4.25,
            C.stone, "ruin_stone", "cylinder")
        Add(b, spec.name .. "苔蚀塔基", 0, 0.24, 0, 4.70, 0.48, 4.70,
            C.stone, "overgrown_stone", "cylinder")
        Add(b, spec.name .. "窄窗深槽", 0, 2.70, -2.13, 0.55, 1.42, 0.16,
            C.navy, "old_brick", "box", 0, 0, 0, nil, "decorative")
        for index = 0, 5 do
            if index ~= 2 then
                local angle = index * TAU / 6
                Add(b, spec.name .. "破损塔冠" .. index,
                    math.sin(angle) * 1.68, 5.02 + (index % 2) * 0.09,
                    math.cos(angle) * 1.68, 0.72, 0.82, 0.72,
                    index % 2 == 0 and C.paleStone or C.stone, "ruin_stone", "box", 0, index * 60, 0)
            end
        end
        Add(b, spec.name .. "塔顶荒苔", -0.58, 4.78, 0.25, 1.55, 0.14, 1.28,
            C.moss, "overgrown_stone", "sphere", 0, 18, 0, nil, "decorative")
        AddRuinGrass(b, spec.name, 1.78, 0.18, 0.78, 3)
    elseif spec.style == "corner" then
        Add(b, spec.name .. "转角圆塔", 0, 2.55, 0, 4.0, 5.10, 4.0,
            C.stone, "ruin_stone", "cylinder")
        Add(b, spec.name .. "东西向旧城墙", 3.35, 1.45, 0, 5.10, 2.90, 0.92,
            C.terracotta, "old_brick")
        Add(b, spec.name .. "南北向旧城墙", 0, 1.62, 3.35, 0.92, 3.24, 5.10,
            C.stone, "overgrown_stone")
        for index = 0, 5 do
            local angle = index * TAU / 6
            Add(b, spec.name .. "塔顶旧垛" .. index,
                math.sin(angle) * 1.55, 5.40, math.cos(angle) * 1.55,
                0.68, 0.72, 0.68, C.paleStone, index == 4 and "carved_stone" or "ruin_stone",
                "box", 0, index * 60, 0)
        end
        Add(b, spec.name .. "城墙苔边", 3.38, 2.95, 0, 4.72, 0.14, 0.72,
            C.moss, "overgrown_stone", "box", 0, 0, 0, nil, "decorative")
        AddRuinGrass(b, spec.name, -1.72, 1.52, 0.75, 3)
    elseif spec.style == "collapsed" then
        Add(b, spec.name .. "残旧红砖墙体", -0.65, 1.38, 0, 5.2, 2.76, 0.72,
            C.terracotta, "old_brick")
        Add(b, spec.name .. "断裂墙端", 2.16, 1.03, 0.05, 0.92, 1.84, 1.06,
            C.stone, "ruin_stone", "box", 0, 0, 8)
        for index = 1, 4 do
            Add(b, spec.name .. "坍塌垛块" .. index,
                1.65 + index * 0.62, 0.46 + (index % 2) * 0.13, 0.15 + (index % 3 - 1) * 0.45,
                0.72 + index % 2 * 0.18, 0.52, 0.66,
                index % 2 == 0 and C.brick or C.stone,
                index % 2 == 0 and "old_brick" or "ruin_stone", "box", index * 7, index * 19, index * 11)
        end
        Add(b, spec.name .. "墙脚苔痕", -1.35, 0.10, -0.40, 2.35, 0.20, 0.42,
            C.moss, "overgrown_stone", "sphere", 0, 0, 0, nil, "decorative")
        AddRuinGrass(b, spec.name, -2.42, -0.12, 0.78, 4)
    elseif spec.style == "arch" then
        Add(b, spec.name .. "左雕纹石柱", -1.62, 1.65, 0, 0.92, 3.30, 1.05,
            C.paleStone, "carved_stone")
        Add(b, spec.name .. "右风化石柱", 1.62, 1.65, 0, 0.92, 3.30, 1.05,
            C.stone, "ruin_stone")
        for index = -2, 2 do
            local angle = index / 4 * math.pi
            Add(b, spec.name .. "石拱楔块" .. index,
                math.sin(angle) * 1.62, 3.20 + math.cos(angle) * 0.84, 0,
                0.78, 0.82, 1.10, index % 2 == 0 and C.paleStone or C.stone,
                index == 0 and "carved_stone" or "ruin_stone", "box", 0, 0, -index * 13)
        end
        Add(b, spec.name .. "石拱中心雕环", 0, 4.18, -0.58, 0.82, 0.82, 0.28,
            C.paleStone, "carved_stone", "torus", 0, 0, 0, nil, "decorative")
        AddRuinGrass(b, spec.name, -2.05, 0.26, 0.66, 2)
        AddRuinGrass(b, spec.name, 2.06, -0.18, 0.62, 2)
    elseif spec.style == "keep" then
        local bodyWidth, bodyDepth, bodyHeight = 6.60, 5.20, 5.10
        local wall, openingWidth, openingHeight = 0.70, 1.45, 2.20
        local frontWidth = (bodyWidth - openingWidth) * 0.5
        Add(b, spec.name .. "旧砖古堡后墙", 0, bodyHeight * 0.5, bodyDepth * 0.5 - wall * 0.5,
            bodyWidth, bodyHeight, wall, C.terracotta, "old_brick")
        for side = -1, 1, 2 do
            Add(b, spec.name .. "旧砖古堡侧墙" .. side, side * (bodyWidth * 0.5 - wall * 0.5),
                bodyHeight * 0.5, 0, wall, bodyHeight, bodyDepth - wall * 2,
                side < 0 and C.terracotta or C.stone, side < 0 and "old_brick" or "overgrown_stone")
            Add(b, spec.name .. "旧砖古堡前墙" .. side,
                side * (openingWidth * 0.5 + frontWidth * 0.5), bodyHeight * 0.5,
                -bodyDepth * 0.5 + wall * 0.5, frontWidth, bodyHeight, wall,
                side < 0 and C.terracotta or C.stone, side < 0 and "old_brick" or "overgrown_stone")
        end
        Add(b, spec.name .. "旧砖古堡门洞上墙", 0, openingHeight + (bodyHeight - openingHeight) * 0.5,
            -bodyDepth * 0.5 + wall * 0.5, openingWidth, bodyHeight - openingHeight, wall,
            C.terracotta, "old_brick")
        Add(b, spec.name .. "左残塔", -3.55, 2.18, 0.35, 2.65, 4.36, 2.65,
            C.stone, "ruin_stone", "cylinder")
        Add(b, spec.name .. "右残塔", 3.55, 2.62, 0.35, 2.65, 5.24, 2.65,
            C.stone, "overgrown_stone", "cylinder")
        local doorWidth, doorHeight = 1.55, 2.08
        local storedX = openingWidth * 0.5 + doorWidth * 0.5 + 0.06
        local door = Add(b, spec.name .. "贴墙全开抽拉门板", storedX, doorHeight * 0.5, -2.66,
            doorWidth, doorHeight, 0.10, C.terracotta, "painted_wood", "box", 0, 0, 0, "door", "decorative")
        door.collisionRole = "decorative"
        Add(b, spec.name .. "黄铜抽拉门上轨", doorWidth * 0.5, doorHeight + 0.10, -2.66,
            openingWidth + doorWidth + 0.20, 0.12, 0.12,
            C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
        Add(b, spec.name .. "黄铜嵌入拉手", storedX - doorWidth * 0.31, 1.03, -2.73,
            0.13, 0.30, 0.035, C.brass, "metal", "box", 0, 0, 0, nil, "decorative")
        for index = -3, 3 do
            if index ~= 1 then
                Add(b, spec.name .. "主楼残垛" .. index, index * 0.86, 5.48 + (index % 2) * 0.08, -2.28,
                    0.58, 0.76, 0.70, index % 2 == 0 and C.stone or C.brick,
                    index % 2 == 0 and "ruin_stone" or "old_brick")
            end
        end
        Add(b, spec.name .. "侧向断墙", -5.45, 1.26, 0.65, 3.05, 2.52, 0.82,
            C.stone, "overgrown_stone", "box", 0, -8, 0)
        Add(b, spec.name .. "堡顶荒草带", -1.15, 5.18, 0.35, 2.55, 0.16, 1.35,
            C.moss, "overgrown_stone", "sphere", 0, 7, 0, nil, "decorative")
        AddRuinGrass(b, spec.name, -4.55, -0.82, 0.82, 4)
        AddRuinGrass(b, spec.name, 4.38, 1.12, 0.76, 3)
    else
        for level = 0, 2 do
            Add(b, spec.name .. "雕纹石台" .. level, 0, 0.16 + level * 0.28, 0,
                5.2 - level * 0.78, 0.32, 4.2 - level * 0.62,
                level == 1 and C.stone or C.paleStone,
                level == 2 and "carved_stone" or level == 1 and "overgrown_stone" or "ruin_stone",
                "box", 0, level * 7, 0, "base", "surface")
        end
        Add(b, spec.name .. "遗迹石环", 0, 2.25, 0, 3.15, 3.15, 0.58,
            C.paleStone, "carved_stone", "torus", 0, 0, 0, nil, "decorative")
        Add(b, spec.name .. "祭坛断碑", 0, 1.28, 0.15, 0.68, 2.30, 0.72,
            C.stone, "ruin_stone", "box", 0, 0, -5)
        AddRuinGrass(b, spec.name, -1.82, 0.92, 0.72, 3)
        AddRuinGrass(b, spec.name, 1.88, -0.85, 0.68, 3)
    end
    return b
end

local MOUNTAIN_SPECS = {
    { id = "soft-grass-mound", name = "草甸缓丘", style = "mound", description = "不对称草坡、土层与柔和阶地组成的低丘。" },
    { id = "layered-rocky-hill", name = "苔岩层岭", style = "layered", description = "双峰山脊、外露地层与连续山径组成的中型丘陵。" },
    { id = "needle-stone-peak", name = "风蚀针岩峰", style = "peak", description = "主峰、侧肩与破碎岩脚共同形成的陡峭石峰。" },
    { id = "snow-cap-mountain", name = "暮雪双脊山", style = "snow", description = "宽阔山脚、双峰脊线与不规则雪线组成的雪山。" },
    { id = "walkable-cliff-terrace", name = "青苔断崖台", style = "cliff", description = "自然断面、错落台地与连续石阶组成的可攀山崖。" },
    { id = "waterfall-rock-gate", name = "溪谷瀑布岩门", style = "waterfall", description = "两侧山肩、天然岩梁、瀑布和方块浅池组成的溪谷。" },
    { id = "world-tree-column-tower", name = "世界树岩塔", style = "column_tower",
        description = "纵向柱状节理、平顶岩冠与树根般基岩组成的巨型地标。" },
}

local function TerrainNoise(x, z, seed)
    local value = math.sin(x * 12.9898 + z * 78.233 + seed * 37.719) * 43758.5453
    return value - math.floor(value)
end

local function EllipseHeight(x, z, centerX, centerZ, radiusX, radiusZ)
    local dx, dz = (x - centerX) / radiusX, (z - centerZ) / radiusZ
    return math.max(0, 1 - math.sqrt(dx * dx + dz * dz))
end

local function AddVoxelColumn(blocks, prefix, gridX, gridZ, x, z, height, topMaterial, topColor, options)
    options = options or {}
    local step = options.step or 0.38
    local cell = options.cell or 0.88
    height = math.max(0.42, math.floor(height / step + 0.5) * step)
    local capHeight = options.capHeight or (topMaterial == "snow" and 0.20 or 0.15)
    local bodyHeight = math.max(0.27, height - capHeight)
    local bodyMaterial = options.bodyMaterial or (height < 1.20 and "earth" or "stone")
    local bodyColor = options.bodyColor
        or bodyMaterial == "earth" and C.earth
        or (TerrainNoise(gridX, gridZ, options.seed or 1) > 0.52 and C.shadowStone or C.stone)
    local label = tostring(gridX) .. ":" .. tostring(gridZ)
    local lowerMaterial = options.lowerMaterial
    if lowerMaterial and bodyHeight > 1.0 then
        local lowerHeight = math.min(bodyHeight * 0.34, options.lowerMax or 1.25)
        Add(blocks, prefix .. "承重方块基岩" .. label,
            x, lowerHeight * 0.5, z, cell, lowerHeight, cell,
            lowerMaterial == "earth" and C.earth or C.shadowStone, lowerMaterial, "box")
        Add(blocks, prefix .. "承重方块岩柱" .. label,
            x, lowerHeight + (bodyHeight - lowerHeight) * 0.5, z,
            cell, bodyHeight - lowerHeight, cell, bodyColor, bodyMaterial, "box")
    else
        Add(blocks, prefix .. "承重方块岩柱" .. label,
            x, bodyHeight * 0.5, z, cell, bodyHeight, cell,
            bodyColor, bodyMaterial, "box")
    end
    Add(blocks, prefix .. "方块地表" .. label,
        x, bodyHeight + capHeight * 0.5, z, cell + 0.025, capHeight, cell + 0.025,
        topColor, topMaterial, "box", 0, 0, 0, "base", "surface")
end

local function BuildMountain(spec)
    local b = {}
    if spec.style == "mound" then
        for x = -3, 3 do
            for z = -3, 3 do
                local main = EllipseHeight(x, z, -0.25, 0.20, 3.35, 2.75)
                local shoulder = EllipseHeight(x, z, 1.65, -0.65, 2.10, 1.75)
                local mass = math.max(main, shoulder * 0.78)
                if mass > 0.04 then
                    local height = 0.44 + main * 1.65 + shoulder * 0.48 + TerrainNoise(x, z, 2) * 0.16
                    AddVoxelColumn(b, spec.name, x, z, x * 0.82, z * 0.82, height,
                        "grass", TerrainNoise(x, z, 22) > 0.68 and C.grassLight or C.grass,
                        { seed = 2, cell = 0.80, step = 0.30, bodyMaterial = "earth", bodyColor = C.earth })
                end
            end
        end
    elseif spec.style == "layered" then
        for x = -4, 4 do
            for z = -3, 3 do
                local main = EllipseHeight(x, z, -0.65, 0.05, 4.45, 3.25)
                local second = EllipseHeight(x, z, 1.75, -0.65, 2.55, 2.35)
                local saddle = math.max(main, second * 0.92)
                if saddle > 0.035 then
                    local height = 0.52 + main * 3.45 + second * 1.35
                        + TerrainNoise(x, z, 5) * 0.34
                    local high = height > 2.45
                    AddVoxelColumn(b, spec.name, x, z, x * 0.84, z * 0.84, height,
                        high and "moss" or "grass", high and C.moss or C.grass,
                        { seed = 5, cell = 0.82, step = 0.38, bodyMaterial = "stone", lowerMaterial = "earth" })
                end
            end
        end
        for step = 0, 9 do
            Add(b, spec.name .. "侧向山径台阶" .. step, -3.45 + step * 0.66,
                0.18 + step * 0.36, 3.18,
                0.72, 0.18, 0.62, C.paleStone, "stone", "box", 0, 0, 0, "base", "surface")
        end
    elseif spec.style == "peak" then
        for x = -3, 3 do
            for z = -3, 3 do
                local foot = EllipseHeight(x, z, -0.10, 0.15, 3.30, 3.05)
                local spire = EllipseHeight(x, z, 0.55, -0.55, 1.70, 1.90)
                local shoulder = EllipseHeight(x, z, -1.45, 0.85, 1.75, 1.55)
                if foot > 0.025 then
                    local height = 0.50 + foot * 2.55 + spire * 4.05 + shoulder * 1.15
                        + TerrainNoise(x, z, 7) * 0.34
                    local topMaterial = height < 1.75 and "moss" or "stone"
                    AddVoxelColumn(b, spec.name, x, z, x * 0.84, z * 0.84, height,
                        topMaterial, topMaterial == "moss" and C.moss or C.paleStone,
                        { seed = 7, cell = 0.82, step = 0.40, bodyMaterial = "stone", lowerMaterial = "earth" })
                end
            end
        end
        for rock = 0, 6 do
            local angle = rock * TAU / 7
            Add(b, spec.name .. "风蚀散落岩块" .. rock,
                math.sin(angle) * (2.45 + rock % 2 * 0.35), 0.22,
                math.cos(angle) * (2.25 + rock % 3 * 0.22),
                0.55, 0.44, 0.62, rock % 2 == 0 and C.stone or C.shadowStone, "stone", "box",
                0, rock * 17, 0)
        end
    elseif spec.style == "snow" then
        -- This mountain is a real stepped voxel shell, not one stretched box
        -- per map cell. Every visible ledge and cliff band is made from equal
        -- cubes; hidden interior cubes are omitted to keep mobile cost sane.
        local cell, levelHeight = 0.72, 0.72
        local levels = {}
        for x = -6, 6 do
            levels[x] = {}
            for z = -6, 6 do
                local foot = EllipseHeight(x, z, -0.35, 0.18, 6.15, 5.55)
                local summit = EllipseHeight(x, z, 1.05, -0.85, 2.85, 2.95)
                local westRidge = EllipseHeight(x, z, -2.05, 0.65, 3.00, 2.60)
                local northShoulder = EllipseHeight(x, z, 0.20, 2.45, 3.20, 2.10)
                if foot > 0.018 then
                    local height = 0.78 + foot * 3.40 + summit * 5.20
                        + westRidge * 1.35 + northShoulder * 0.92
                        + TerrainNoise(x, z, 8) * 0.38
                    levels[x][z] = math.max(1, math.floor(height / levelHeight + 0.5))
                end
            end
        end
        local function HeightAt(x, z)
            return levels[x] and levels[x][z] or 0
        end
        for x = -6, 6 do
            for z = -6, 6 do
                local topLevel = HeightAt(x, z)
                if topLevel > 0 then
                    local lowestNeighbour = math.min(
                        HeightAt(x - 1, z), HeightAt(x + 1, z),
                        HeightAt(x, z - 1), HeightAt(x, z + 1))
                    local firstVisibleLevel = math.min(topLevel, math.max(1, lowestNeighbour + 1))
                    for level = firstVisibleLevel, topLevel do
                        local isTop = level == topLevel
                        local material, color
                        if isTop then
                            local snowLine = 7 + math.floor(TerrainNoise(x, z, 18) * 2)
                            if topLevel >= snowLine then material, color = "snow", C.snow
                            elseif topLevel >= 4 then
                                material = "stone"
                                color = TerrainNoise(x, z, 28) > 0.52 and C.paleStone or C.stone
                            else
                                material = "moss"
                                color = TerrainNoise(x, z, 38) > 0.62 and C.grass or C.moss
                            end
                        elseif level <= 2 then
                            material, color = "earth", C.earth
                        else
                            material = "stone"
                            color = TerrainNoise(x + level, z, 48) > 0.56 and C.shadowStone or C.stone
                        end
                        Add(b, spec.name .. (isTop and "雪山体素地表" or "雪山体素岩层")
                                .. x .. ":" .. z .. ":" .. level,
                            x * cell, (level - 0.5) * levelHeight, z * cell,
                            cell, levelHeight, cell, color, material, "box", 0, 0, 0,
                            isTop and "base" or nil, isTop and "surface" or nil)
                    end
                end
            end
        end
    elseif spec.style == "cliff" then
        for x = -4, 4 do
            for z = -3, 2 do
                local plateau = EllipseHeight(x, z, -0.55, -0.15, 4.55, 3.45)
                local crown = EllipseHeight(x, z, -1.15, -0.65, 3.15, 2.25)
                if plateau > 0.03 then
                    local frontWall = z <= 0 and (1.15 + (2 - math.min(2, math.abs(x))) * 0.32) or 0
                    local height = 0.54 + plateau * 2.10 + crown * 1.55 + frontWall
                        + TerrainNoise(x, z, 11) * 0.26
                    AddVoxelColumn(b, spec.name, x, z, x * 0.84, z * 0.84, height,
                        height > 3.45 and "grass" or "moss", height > 3.45 and C.grass or C.moss,
                        { seed = 11, cell = 0.82, step = 0.38, bodyMaterial = "stone", lowerMaterial = "earth" })
                end
            end
        end
        for step = 0, 14 do
            local level = step / 14
            Add(b, spec.name .. "连续山径台阶" .. step, -3.65 + step * 0.50,
                0.22 + level * 4.72, 2.95 - step * 0.025,
                0.58, 0.18, 0.52, C.paleStone, "stone", "box", 0, 0, 0, "base", "surface")
        end
    elseif spec.style == "waterfall" then
        for x = -4, 4 do
            if math.abs(x) >= 2 then
                for z = -2, 2 do
                    local inner = math.abs(x) == 2 and 1 or 0
                    local height = 3.35 + inner * 1.18 + (2 - math.abs(z)) * 0.26
                        + TerrainNoise(x, z, 12) * 0.36
                    AddVoxelColumn(b, spec.name, x, z, x * 0.72, z * 0.74, height,
                        "moss", TerrainNoise(x, z, 32) > 0.58 and C.grass or C.moss,
                        { seed = 12, cell = 0.70, step = 0.36, bodyMaterial = "stone", lowerMaterial = "earth" })
                end
            end
        end
        for bridgeX = -2, 2 do
            Add(b, spec.name .. "方块拱顶岩梁" .. bridgeX,
                bridgeX * 0.72, 5.13 + (2 - math.abs(bridgeX)) * 0.18, 0,
                0.74, 0.78, 2.90, bridgeX % 2 == 0 and C.paleStone or C.stone, "stone", "box")
        end
        Add(b, spec.name .. "瀑布水帘", 0, 2.62, 0.34, 2.05, 5.05, 0.16,
            C.water, "water", "box", 0, 0, 0, nil, "fluid")
        Add(b, spec.name .. "方块瀑布浅池", 0, 0.10, 1.55, 5.45, 0.20, 3.90,
            C.water, "water", "box", 0, 0, 0, nil, "fluid")
        for stone = 0, 9 do
            local angle = stone * TAU / 10
            Add(b, spec.name .. "池岸方石" .. stone, math.sin(angle) * 2.82, 0.26,
                1.55 + math.cos(angle) * 2.08, 0.74, 0.52, 0.68,
                stone % 2 == 0 and C.stone or C.paleStone, "stone", "box", 0, stone * 13, 0)
        end
    else
        -- An original storybook landmark informed by Devils Tower's vertical
        -- columnar jointing: a broad, almost level crown and irregular long
        -- stone prisms, with the outer columns flaring like giant tree roots.
        local rings = {
            { radius = 0.28, count = 5, top = 8.85, width = 0.72 },
            { radius = 1.00, count = 10, top = 8.66, width = 0.64 },
            { radius = 1.72, count = 14, top = 8.28, width = 0.58 },
            { radius = 2.36, count = 16, top = 6.18, width = 0.54 },
        }
        for ringIndex, ring in ipairs(rings) do
            for column = 0, ring.count - 1 do
                local angle = column * TAU / ring.count + ringIndex * 0.17
                local noise = TerrainNoise(column, ringIndex, 27)
                local radius = ring.radius + (noise - 0.5) * 0.18
                local x, z = math.sin(angle) * radius, math.cos(angle) * radius
                local bottom = ringIndex == 4 and 0.18 or 0.14
                local top = ring.top + (noise - 0.5) * (ringIndex == 4 and 1.15 or 0.42)
                local height = top - bottom
                local width = ring.width * (0.88 + noise * 0.22)
                Add(b, spec.name .. "纵向节理岩棱" .. ringIndex .. "-" .. column,
                    x, bottom + height * 0.5, z, width, height, width * 0.90,
                    column % 3 == 0 and C.shadowStone or column % 2 == 0 and C.paleStone or C.stone,
                    "stone", "box", 0, math.deg(angle) + column % 2 * 7, 0)
                if ringIndex <= 3 then
                    Add(b, spec.name .. "柱岩冠顶苔面" .. ringIndex .. "-" .. column,
                        x, top + 0.075, z, width * 1.04, 0.15, width * 0.94,
                        ringIndex == 1 and C.grass or C.moss, ringIndex == 1 and "grass" or "moss",
                        "box", 0, math.deg(angle) + column % 2 * 7, 0, "base", "surface")
                end
            end
        end
        for root = 0, 11 do
            local angle = root * TAU / 12
            Add(b, spec.name .. "承重巨树根状基岩" .. root,
                math.sin(angle) * 2.95, 0.55, math.cos(angle) * 2.95,
                0.64 + root % 3 * 0.08, 1.10, 2.18 + root % 2 * 0.34,
                root % 2 == 0 and C.stone or C.shadowStone, "stone", "box",
                0, math.deg(angle), 0)
            Add(b, spec.name .. "根端苔草" .. root,
                math.sin(angle) * 3.72, 1.05, math.cos(angle) * 3.72,
                0.72, 0.14, 0.82, root % 3 == 0 and C.grass or C.moss,
                root % 3 == 0 and "grass" or "moss", "box", 0, math.deg(angle), 0,
                "base", "surface")
        end
    end
    return b
end

local SPECS = {}
local function Register(items, category, builder)
    for _, source in ipairs(items) do
        local spec = {}
        for key, value in pairs(source) do spec[key] = value end
        spec.category, spec.builder = category, builder
        SPECS[#SPECS + 1] = spec
    end
end

Register(TREE_SPECS, "树木单件", BuildTree)
Register(VEGETATION_SPECS, "植被单件", BuildVegetation)
Register(HOUSE_SPECS, "可进入建筑", BuildHouse)
Register(AIRCRAFT_SPECS, "飞行器", BuildAircraft)
Register(FENCE_SPECS, "围栏构件", BuildFence)
Register(STREET_SPECS, "街景设施", BuildStreet)
Register(KIT_SPECS, "组合构件", BuildKit)
Register(RUIN_SPECS, "遗迹构件", BuildRuin)
Register(MOUNTAIN_SPECS, "山体构件", BuildMountain)

function Library.BuildAll()
    local result = {}
    for _, spec in ipairs(SPECS) do result[#result + 1] = Finalize(spec, spec.builder(spec)) end
    return result
end

function Library.BuildOne(id)
    id = tostring(id or ""):gsub("^builtin:compose:", "")
        :gsub("^builtin:wonder:", "")
    for _, spec in ipairs(SPECS) do
        if spec.id == id then return Finalize(spec, spec.builder(spec)) end
    end
    return nil
end

return Library
