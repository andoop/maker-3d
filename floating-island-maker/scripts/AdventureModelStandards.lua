-- Physical and structural standards shared by every composable built-in asset.
-- One authored unit is one island-world metre. The first-person character is
-- 1.2 m tall, so entrances, furniture, stairs and street pieces can be mixed
-- without compensating for hidden per-category scale multipliers.

local ModelGeometry = require("ModelGeometry")

local AdventureModelStandards = {}

local PROFILES = {
    ["树木单件"] = {
        id = "tree", scale = 1.0,
        minHeight = 1.8, maxHeight = 8.5, minFootprint = 0.8, maxFootprint = 7.5,
    },
    ["植被单件"] = {
        id = "vegetation", scale = 1.0,
        minHeight = 0.18, maxHeight = 2.4, minFootprint = 0.12, maxFootprint = 4.5,
    },
    ["可进入建筑"] = {
        id = "building", scale = 1.0,
        minHeight = 2.5, maxHeight = 9.0, minFootprint = 3.6, maxFootprint = 10.5,
    },
    ["飞行器"] = {
        id = "aircraft", scale = 1.0,
        minHeight = 0.75, maxHeight = 7.5, minFootprint = 2.3, maxFootprint = 11.0,
    },
    ["围栏构件"] = {
        id = "fence", scale = 1.0,
        minHeight = 0.4, maxHeight = 2.2, minFootprint = 0.75, maxFootprint = 5.0,
    },
    ["街景设施"] = {
        id = "street", scale = 1.0,
        minHeight = 0.32, maxHeight = 4.3, minFootprint = 0.25, maxFootprint = 5.5,
    },
    ["组合构件"] = {
        id = "kit", scale = 1.0,
        minHeight = 0.12, maxHeight = 4.0, minFootprint = 0.8, maxFootprint = 8.0,
    },
    ["遗迹构件"] = {
        id = "ruin", scale = 1.0,
        minHeight = 0.5, maxHeight = 8.0, minFootprint = 1.0, maxFootprint = 14.0,
    },
    ["山体构件"] = {
        id = "mountain", scale = 1.0,
        minHeight = 1.2, maxHeight = 12.0, minFootprint = 2.5, maxFootprint = 14.0,
    },
}

local FALLBACK = {
    id = "model", scale = 1.0,
    minHeight = 0.1, maxHeight = 16.0, minFootprint = 0.1, maxFootprint = 18.0,
}

local function Copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

function AdventureModelStandards.Profile(category)
    return Copy(PROFILES[category] or FALLBACK)
end

local function BoundsSize(template)
    if template.bounds and template.bounds.size then return template.bounds.size end
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, block in ipairs(template.blocks or {}) do
        local p, half = block.position, ModelGeometry.RotatedHalfExtents(block)
        minX, maxX = math.min(minX, p[1] - half[1]), math.max(maxX, p[1] + half[1])
        minY, maxY = math.min(minY, p[2] - half[2]), math.max(maxY, p[2] + half[2])
        minZ, maxZ = math.min(minZ, p[3] - half[3]), math.max(maxZ, p[3] + half[3])
    end
    if minX == math.huge then return { 0, 0, 0 } end
    return { maxX - minX, maxY - minY, maxZ - minZ }
end

local function ContainsAny(value, words)
    for _, word in ipairs(words) do
        if tostring(value or ""):find(word, 1, true) then return true end
    end
    return false
end

function AdventureModelStandards.Audit(template)
    local profile = AdventureModelStandards.Profile(template.category)
    local scale = tonumber(template.recommendedScale) or profile.scale
    local size = BoundsSize(template)
    local footprint = math.max(size[1], size[3]) * scale
    local height = size[2] * scale
    local result = {
        profile = profile.id,
        scale = scale,
        footprint = footprint,
        height = height,
        invalidScale = scale < 0.75 or scale > 1.25,
        invalidFootprint = footprint < profile.minFootprint or footprint > profile.maxFootprint,
        invalidHeight = height < profile.minHeight or height > profile.maxHeight,
        doors = 0,
        doorOpeningPieces = 0,
        invalidDoors = 0,
        materials = {},
        missingStructure = 0,
        structureNotes = {},
    }

    local names = ""
    for _, block in ipairs(template.blocks or {}) do
        result.materials[block.materialId or "solid"] = true
        local name = tostring(block.name or "")
        names = names .. "|" .. name
        if name:find("门洞", 1, true) then
            result.doorOpeningPieces = result.doorOpeningPieces + 1
        end
        if block.type == "door" and not name:find("门框", 1, true) then
            result.doors = result.doors + 1
            local doorHeight = block.size[2] * scale
            local doorWidth = math.max(block.size[1], block.size[3]) * scale
            -- 1.2 m avatar plus head/shoulder clearance.
            if profile.id == "building"
                and (doorHeight < 1.42 or doorHeight > 2.4 or doorWidth < 0.72 or doorWidth > 1.6) then
                result.invalidDoors = result.invalidDoors + 1
            end
        end
    end

    local function Require(condition, note)
        if condition then return end
        result.missingStructure = result.missingStructure + 1
        result.structureNotes[#result.structureNotes + 1] = note
    end

    if profile.id == "tree" then
        Require(result.materials.wood and result.materials.leaf, "trunk branches and foliage")
        Require(ContainsAny(names, { "树根", "主干", "裸露树梢" }), "readable rooted trunk")
    elseif profile.id == "vegetation" then
        Require(result.materials.leaf, "plant foliage")
        Require(ContainsAny(names, { "叶", "草", "花", "芦苇", "灌木" }), "botanical detail")
    elseif profile.id == "building" then
        Require(result.doors >= 1, "enterable door")
        Require(result.doorOpeningPieces >= result.doors * 2, "open wall geometry for every door")
        Require(names:find("屋顶", 1, true) or names:find("屋盖", 1, true), "complete roof")
        Require(names:find("室内地板", 1, true), "walkable interior floor")
        Require(ContainsAny(names, { "阅读桌", "床垫", "柜台", "靠背椅", "盆栽" }), "authored interior")
        Require(result.materials.stone and result.materials.painted_wood, "foundation and timber structure")
        Require(result.materials.glass, "windows")
    elseif profile.id == "aircraft" then
        Require(result.materials.metal and (result.materials.fabric or result.materials.glass
            or result.materials.crystal), "airframe and light surface")
        Require(ContainsAny(names, { "翼", "气囊", "动力", "吊篮", "滑橇", "舵" }), "flight-readable construction")
    elseif profile.id == "fence" then
        Require(ContainsAny(names, { "栏", "墙", "门", "树篱", "绳" }), "connectable barrier structure")
        Require(result.materials.wood or result.materials.painted_wood or result.materials.stone
            or result.materials.metal or result.materials.leaf, "barrier material")
    elseif profile.id == "street" then
        Require(ContainsAny(names, { "灯", "椅", "桌", "伞", "路牌", "花箱" }), "recognisable street function")
        local materialCount = 0
        for _ in pairs(result.materials) do materialCount = materialCount + 1 end
        Require(materialCount >= 2, "structural and accent materials")
    elseif profile.id == "kit" then
        Require(ContainsAny(names, { "路石", "桥板", "台阶", "浅水", "散石", "面板", "拱顶" }),
            "clear modular construction purpose")
        Require(result.materials.stone or result.materials.pavement or result.materials.painted_wood
            or result.materials.water, "kit structural material")
    elseif profile.id == "ruin" then
        Require(result.materials.ruin_stone or result.materials.old_brick
            or result.materials.carved_stone or result.materials.overgrown_stone,
            "large-scale weathered masonry texture")
        Require(result.materials.overgrown_stone or result.materials.moss or result.materials.leaf,
            "natural overgrowth integrated with the ruin")
        Require(ContainsAny(names, { "城墙", "城门", "塔", "垛", "石拱", "古堡", "祭坛" }),
            "recognisable ruin construction")
    elseif profile.id == "mountain" then
        Require(result.materials.stone or result.materials.earth, "load-bearing geological mass")
        Require(result.materials.grass or result.materials.moss or result.materials.snow
            or result.materials.water, "surface biome")
        Require(ContainsAny(names, { "承重", "岩层", "岩瓣", "断崖层", "岩柱", "山径" }), "organised geological structure")
    end

    return result
end

return AdventureModelStandards
