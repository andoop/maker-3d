-- Global Q-style finish and structural quality pass for every built-in model.
-- It is deliberately data-only so templates can be audited in Fengari tests
-- without booting the 3D engine.

local ModelGeometry = require("ModelGeometry")

local ChibiModelPass = {}

local TAU = math.pi * 2
local MIN_PART_SIZE = 0.04

local COLOR_MAP = {
    ["#f5f1e8"] = "#f2e7cf", ["#f7f3ea"] = "#f2e7cf", ["#eee5d7"] = "#dcc49a",
    ["#dfd4c3"] = "#dcc49a", ["#ddd5c5"] = "#b8b8aa", ["#dfd0b8"] = "#dcc49a",
    ["#c3b6a5"] = "#b8b8aa", ["#aaa092"] = "#899399", ["#706b66"] = "#59646b",
    ["#0875b5"] = "#78b9d2", ["#064e79"] = "#3e536c", ["#5eafd2"] = "#78b9d2",
    ["#b7e6ef"] = "#b2dada", ["#3ea6e0"] = "#5eafc2", ["#176f9e"] = "#597993",
    ["#bd6c32"] = "#a86e4f", ["#dc5b91"] = "#d98a86", ["#e84a96"] = "#d98a86",
    ["#6f9a37"] = "#86b85a", ["#6f923c"] = "#6f8a50", ["#3e6935"] = "#3f6e62",
    ["#4b6f2d"] = "#3f6e62", ["#839253"] = "#6f8a50", ["#f4a72c"] = "#d9b95f",
    ["#f3b43f"] = "#d9b95f", ["#7b5230"] = "#8b6248", ["#8b603c"] = "#8b6248",
    ["#54351f"] = "#5c463a", ["#b98a58"] = "#c78a50", ["#30383c"] = "#59646b",
    ["#20282d"] = "#3e536c", ["#bd4f43"] = "#c96f5d", ["#9477a8"] = "#88779b",
    ["#df735f"] = "#c96f5d", ["#c99b43"] = "#b38a52",
}

local DOOR_EXCLUDES = {
    "门框", "门楣", "门柱", "门廊", "门槛", "门牌", "门洞",
    "门厅", "月门", "拱门", "门花", "门环", "门顶", "门套",
}

local STRUCTURAL_WORDS = {
    "墙", "立面", "房体", "主体", "客房盒", "站房", "小屋",
    "观察室", "工作室", "书屋", "更衣室", "亭身", "塔身", "钟楼",
}

local FABRIC_WORDS = {
    "沙发", "靠背", "软垫", "坐垫", "床垫", "枕头", "床品",
    "织物", "地毯", "吊床", "座垫", "布帘", "窗帘",
}

local GLOW_WORDS = { "暖光", "光源", "星灯", "灯泡", "灯珠", "发光", "核心光" }
local GLOW_EXCLUDES = { "灯杆", "灯座", "灯架", "灯线", "路灯柱", "定位灯杆" }

local function Contains(value, needle)
    return tostring(value or ""):find(needle, 1, true) ~= nil
end

local function ContainsAny(value, words)
    for _, word in ipairs(words) do if Contains(value, word) then return true end end
    return false
end

local function Round(value)
    return math.floor((tonumber(value) or 0) * 1000 + 0.5) / 1000
end

local function CopyBlock(source)
    local p, s, r = source.position or {}, source.size or {}, source.rotation or {}
    return {
        name = source.name,
        type = source.type or "block",
        position = { p[1] or 0, p[2] or 0, p[3] or 0 },
        size = { s[1] or 1, s[2] or 1, s[3] or 1 },
        rotation = { r[1] or 0, r[2] or 0, r[3] or 0 },
        color = source.color or "#f2e7cf",
        materialId = source.materialId or "solid",
        shapeId = source.shapeId or "box",
        collisionRole = source.collisionRole,
    }
end

local function AngleDistance(a, b)
    local delta = ((tonumber(a) or 0) - (tonumber(b) or 0)) % TAU
    if delta > math.pi then delta = TAU - delta end
    return math.abs(delta)
end

local function IsFlatRotation(block)
    local r = block.rotation or {}
    return AngleDistance(r[1], 0) < 0.01 and AngleDistance(r[3], 0) < 0.01
end

local function NormalAxis(block)
    local s = block.size
    return s[1] <= s[3] and "x" or "z"
end

local function IsDoorLeaf(block)
    if block.shapeId ~= "box" then return false end
    local name, s = tostring(block.name or ""), block.size
    if block.type ~= "door" and not (Contains(name, "门") or Contains(name, "入口")) then return false end
    for _, excluded in ipairs(DOOR_EXCLUDES) do if Contains(name, excluded) then return false end end
    local axis = NormalAxis(block)
    local width, thickness = axis == "x" and s[3] or s[1], axis == "x" and s[1] or s[3]
    return s[2] >= 1.0 and width >= 0.62 and thickness <= 0.5
end

local function IsAuthoredSlidingDoor(block)
    local name = tostring(block and block.name or "")
    return Contains(name, "贴墙全开抽拉门")
end

local function IsWindowPane(block)
    local name, s = tostring(block.name or ""), block.size
    if block.shapeId ~= "box" or name:sub(1, #"精修·") == "精修·" then return false end
    if IsDoorLeaf(block) or not (block.materialId == "glass" or Contains(name, "窗")) then return false end
    local axis = NormalAxis(block)
    local width, thickness = axis == "x" and s[3] or s[1], axis == "x" and s[1] or s[3]
    return s[2] >= 0.5 and width >= 0.5 and thickness <= 0.36
end

local function IsStructural(block, openingKind)
    local name, s = tostring(block.name or ""), block.size
    if block.shapeId ~= "box" or not IsFlatRotation(block) then return false end
    local authoredDoorWall = Contains(name, "门洞左") or Contains(name, "门洞右") or Contains(name, "门洞上")
    if ContainsAny(name, { "窗", "框", "地板", "楼板", "屋顶", "台面", "栏杆" })
        or (Contains(name, "门") and not authoredDoorWall) then return false end
    if not ContainsAny(name, STRUCTURAL_WORDS) then return false end
    local axis = NormalAxis(block)
    local thickness = axis == "x" and s[1] or s[3]
    local width = axis == "x" and s[3] or s[1]
    local limit = openingKind == "window" and 0.85 or 1.2
    return thickness <= limit and width >= 1.2 and s[2] >= 1.2
end

local function LocalOffset(block, worldX, worldZ)
    local ry = (block.rotation and block.rotation[2]) or 0
    local c, s = math.cos(ry), math.sin(ry)
    local dx, dz = worldX - block.position[1], worldZ - block.position[3]
    return dx * c - dz * s, dx * s + dz * c
end

local function WorldOffset(block, localX, localZ)
    local ry = (block.rotation and block.rotation[2]) or 0
    local c, s = math.cos(ry), math.sin(ry)
    return localX * c + localZ * s, -localX * s + localZ * c
end

local function FindBlockingStructure(blocks, opening, openingKind)
    local axis = NormalAxis(opening)
    local bestIndex, bestScore
    for index, candidate in ipairs(blocks) do
        -- Swinging door leaves may be rotated away from their opening while
        -- windows remain coplanar and keep the stricter angle match.
        local angleMatches = openingKind == "door"
            or AngleDistance((candidate.rotation or {})[2], (opening.rotation or {})[2]) < 0.035
        if candidate ~= opening and IsStructural(candidate, openingKind)
            and NormalAxis(candidate) == axis and angleMatches then
            local localX, localZ = LocalOffset(candidate, opening.position[1], opening.position[3])
            local across = axis == "z" and localX or localZ
            local normal = axis == "z" and localZ or localX
            local wallWidth = axis == "z" and candidate.size[1] or candidate.size[3]
            local wallDepth = axis == "z" and candidate.size[3] or candidate.size[1]
            local openWidth = axis == "z" and opening.size[1] or opening.size[3]
            local openDepth = axis == "z" and opening.size[3] or opening.size[1]
            local wallBottom = candidate.position[2] - candidate.size[2] * 0.5
            local wallTop = candidate.position[2] + candidate.size[2] * 0.5
            local openBottom = opening.position[2] - opening.size[2] * 0.5
            local openTop = opening.position[2] + opening.size[2] * 0.5
            local contained = math.abs(across) + openWidth * 0.5 <= wallWidth * 0.5 + 0.08
                and openBottom >= wallBottom - 0.12 and openTop <= wallTop + 0.12
                and math.abs(normal) <= wallDepth * 0.5 + openDepth * 0.5 + 0.24
            if contained then
                local score = math.abs(normal) + wallDepth * 0.05
                if not bestScore or score < bestScore then bestIndex, bestScore = index, score end
            end
        end
    end
    return bestIndex
end

local function CarveOpening(blocks, opening, openingKind)
    local wallIndex = FindBlockingStructure(blocks, opening, openingKind)
    if not wallIndex then return false end
    local wall = table.remove(blocks, wallIndex)
    local axis = NormalAxis(wall)
    local localX, localZ = LocalOffset(wall, opening.position[1], opening.position[3])
    local across = axis == "z" and localX or localZ
    local wallWidth = axis == "z" and wall.size[1] or wall.size[3]
    local openWidth = axis == "z" and opening.size[1] or opening.size[3]
    local horizontalGap = openingKind == "door" and 0.08 or 0.06
    local verticalGap = openingKind == "door" and 0.035 or 0.06
    local wallMin, wallMax = -wallWidth * 0.5, wallWidth * 0.5
    local openMin = math.max(wallMin, across - openWidth * 0.5 - horizontalGap)
    local openMax = math.min(wallMax, across + openWidth * 0.5 + horizontalGap)
    local wallBottom = wall.position[2] - wall.size[2] * 0.5
    local wallTop = wall.position[2] + wall.size[2] * 0.5
    local openBottom = math.max(wallBottom, opening.position[2] - opening.size[2] * 0.5 - verticalGap)
    local openTop = math.min(wallTop, opening.position[2] + opening.size[2] * 0.5 + verticalGap)
    local label = openingKind == "door" and "门洞" or "窗洞"

    local function AddPiece(suffix, minimumAcross, maximumAcross, minimumY, maximumY)
        local width, height = maximumAcross - minimumAcross, maximumY - minimumY
        if width < 0.08 or height < 0.08 then return end
        local piece = CopyBlock(wall)
        piece.name = "Q版·" .. tostring(wall.name or "墙体") .. "·" .. label .. suffix
        local centerAcross = (minimumAcross + maximumAcross) * 0.5
        local offsetX, offsetZ = axis == "z" and centerAcross or 0, axis == "x" and centerAcross or 0
        local worldX, worldZ = WorldOffset(wall, offsetX, offsetZ)
        piece.position[1] = wall.position[1] + worldX
        piece.position[2] = (minimumY + maximumY) * 0.5
        piece.position[3] = wall.position[3] + worldZ
        if axis == "z" then piece.size[1] = width else piece.size[3] = width end
        piece.size[2] = height
        blocks[#blocks + 1] = piece
    end

    AddPiece("左", wallMin, openMin, wallBottom, wallTop)
    AddPiece("右", openMax, wallMax, wallBottom, wallTop)
    AddPiece("下", openMin, openMax, wallBottom, openBottom)
    AddPiece("上", openMin, openMax, openTop, wallTop)
    return true
end

local function GeometryKey(block)
    local p, s, r = block.position, block.size, block.rotation
    return table.concat({
        Round(p[1]), Round(p[2]), Round(p[3]),
        Round(s[1]), Round(s[2]), Round(s[3]),
        Round(r[1]), Round(r[2]), Round(r[3]),
        tostring(block.color), tostring(block.materialId), tostring(block.shapeId), tostring(block.collisionRole),
    }, "|")
end

local function RotatedHalfExtents(block)
    return ModelGeometry.RotatedHalfExtents(block)
end

local function RemoveExactDuplicates(blocks)
    local seen, compact = {}, {}
    for _, block in ipairs(blocks) do
        local key = GeometryKey(block)
        if not seen[key] then seen[key] = true; compact[#compact + 1] = block end
    end
    for index = #blocks, 1, -1 do blocks[index] = nil end
    for index, block in ipairs(compact) do blocks[index] = block end
end

local function StyleBlock(block)
    block.position = block.position or { 0, 0, 0 }
    block.size = block.size or { 1, 1, 1 }
    block.rotation = block.rotation or { 0, 0, 0 }
    block.shapeId = block.shapeId or "box"
    block.materialId = block.materialId or "solid"
    block.color = COLOR_MAP[tostring(block.color or ""):lower()] or block.color or "#f2e7cf"
    for index = 1, 3 do
        block.position[index] = Round(block.position[index])
        block.size[index] = math.max(MIN_PART_SIZE, Round(block.size[index]))
        block.rotation[index] = tonumber(block.rotation[index]) or 0
    end

    local name = tostring(block.name or "")
    if block.materialId ~= "water" and block.materialId ~= "fire" and block.materialId ~= "glass"
        and block.materialId ~= "brick" and block.materialId ~= "roof_tile"
        and block.materialId ~= "ruin_stone" and block.materialId ~= "old_brick"
        and block.materialId ~= "carved_stone" and block.materialId ~= "overgrown_stone"
        and block.materialId ~= "pavement" and block.materialId ~= "asphalt"
        and block.materialId ~= "snow" then
        if Contains(name, "陶") or Contains(name, "花盆") or Contains(name, "花器") then
            block.materialId = "ceramic"
        elseif ContainsAny(name, FABRIC_WORDS) then
            block.materialId = "fabric"
        elseif block.materialId == "solid" and ContainsAny(name, GLOW_WORDS)
            and not ContainsAny(name, GLOW_EXCLUDES) then
            block.materialId = "glow"
        end
    end

    local s = block.size
    if block.shapeId == "box" then
        if ContainsAny(name, { "把手", "旋钮", "灯泡", "灯珠", "果实", "花球", "花芯" }) then
            block.shapeId = "sphere"
        elseif s[1] <= 0.52 and s[3] <= 0.52 and s[2] >= 0.52
            and ContainsAny(name, { "立柱", "柱", "杆", "桌腿", "凳脚", "床脚", "枝干" }) then
            block.shapeId = "cylinder"
        end
    end
end

function ChibiModelPass.Apply(id, category, blocks)
    for _, block in ipairs(blocks) do StyleBlock(block) end
    RemoveExactDuplicates(blocks)

    local doors, windows = {}, {}
    for _, block in ipairs(blocks) do
        if IsDoorLeaf(block) then doors[#doors + 1] = block
        elseif IsWindowPane(block) then windows[#windows + 1] = block end
    end
    for _, door in ipairs(doors) do
        -- Built-in sliding doors already author their opening from explicit
        -- jamb/lintel wall pieces. Their parked leaf intentionally sits over
        -- the adjacent solid wall, which must not be carved as a second door.
        if not IsAuthoredSlidingDoor(door) then CarveOpening(blocks, door, "door") end
    end
    for _, window in ipairs(windows) do CarveOpening(blocks, window, "window") end
    RemoveExactDuplicates(blocks)
    return ChibiModelPass.Audit(blocks)
end

function ChibiModelPass.Audit(blocks)
    local report = {
        count = #blocks, invalid = 0, duplicates = 0, belowGround = 0,
        doors = 0, blockedDoors = 0, carvedOpenings = 0,
    }
    local seen = {}
    for _, block in ipairs(blocks) do
        local p, s = block.position or {}, block.size or {}
        if not p[1] or not p[2] or not p[3] or not s[1] or not s[2] or not s[3]
            or s[1] <= 0 or s[2] <= 0 or s[3] <= 0 then report.invalid = report.invalid + 1 end
        if p[2] and s[2] then
            local half = RotatedHalfExtents(block)
            if p[2] - half[2] < -0.002 then report.belowGround = report.belowGround + 1 end
        end
        local key = p[1] and s[1] and GeometryKey(block) or tostring(block)
        if seen[key] then report.duplicates = report.duplicates + 1 else seen[key] = true end
        if IsDoorLeaf(block) then
            report.doors = report.doors + 1
            if not IsAuthoredSlidingDoor(block) and FindBlockingStructure(blocks, block, "door") then
                report.blockedDoors = report.blockedDoors + 1
            end
        end
        if Contains(block.name, "门洞") or Contains(block.name, "窗洞") then
            report.carvedOpenings = report.carvedOpenings + 1
        end
    end
    return report
end

return ChibiModelPass
