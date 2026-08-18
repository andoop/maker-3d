local IslandLayout = require("IslandLayout")

-- Pure-data island composition planner. It deliberately knows nothing about
-- scene nodes or UI so the same authored result can be previewed, persisted,
-- regenerated and tested before the world creates any render objects.
local IslandAutoBuilder = {}

local TAU = math.pi * 2
local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local MODULUS = 2147483647

local ROLE_ORDER = {
    mountain = 1, ruin = 2, building = 3, landmark = 4, aircraft = 5,
    water = 6, path = 7, tree = 8, fence = 9, street = 10,
    vegetation = 11, prop = 12,
}

local ROLE_NAMES = {
    mountain = "山体景观", ruin = "遗迹地标", building = "建筑群",
    landmark = "主题地标", aircraft = "飞行器", water = "水景",
    path = "道路", tree = "树林", fence = "围栏", street = "街景设施",
    vegetation = "植被", prop = "景观道具",
}

local ZONE_FOR_ROLE = {
    mountain = "vista", ruin = "vista", landmark = "vista",
    building = "settlement", aircraft = "plaza", water = "garden",
    path = "avenue", tree = "grove", fence = "boundary",
    street = "avenue", vegetation = "garden", prop = "plaza",
}

local ZONE_NAMES = {
    vista = "远景地标区", settlement = "建筑聚落区", plaza = "公共活动区",
    garden = "花园水景区", avenue = "入口道路区", grove = "林地区",
    boundary = "边界围合区",
}

local THEMES = {
    mixed = {
        id = "mixed", name = "奇幻聚落", description = "建筑、林地与山景层次完整的综合空岛",
        boost = { building = 1, path = 1, street = 1, tree = 1, vegetation = 1 },
    },
    village = {
        id = "village", name = "云上小镇", description = "道路串联房屋、灯具与围栏的生活聚落",
        boost = { building = 2, path = 2, street = 2, fence = 2 },
    },
    forest = {
        id = "forest", name = "雾森秘境", description = "高低树冠、林下植物与少量遗迹构成的森林秘境",
        boost = { tree = 3, vegetation = 3, water = 1, ruin = 1 },
    },
    mountain = {
        id = "mountain", name = "峭壁圣域", description = "险峰、石台与遗迹共同形成的高空圣域",
        boost = { mountain = 2, ruin = 2, tree = 1 },
    },
    garden = {
        id = "garden", name = "月湾花园", description = "水景、花木、座椅与步道相互穿插的空中花园",
        boost = { vegetation = 3, tree = 2, water = 2, street = 1, path = 1 },
    },
    skyport = {
        id = "skyport", name = "云港驿站", description = "飞行器、平台、路灯和建筑组成的空中港湾",
        boost = { aircraft = 2, path = 2, street = 2, building = 1 },
    },
    ruins = {
        id = "ruins", name = "失落古城", description = "残垣、古堡、石径和野生植被交织的遗迹群",
        boost = { ruin = 3, mountain = 1, vegetation = 2, path = 1 },
    },
}

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then return math.floor(value * 1000 + 0.5) / 1000 end
    return math.ceil(value * 1000 - 0.5) / 1000
end

local function NormalizeAngle(value)
    value = tonumber(value) or 0
    while value > math.pi do value = value - TAU end
    while value < -math.pi do value = value + TAU end
    return value
end

local function HashText(value, initial)
    local result = math.max(1, math.floor(tonumber(initial) or 216613)) % MODULUS
    local text = tostring(value or "")
    for index = 1, #text do result = (result * 131 + text:byte(index) + index * 17) % MODULUS end
    return math.max(1, result)
end

local function NewRandom(seed)
    local state = HashText(seed)
    return function()
        state = (state * 48271) % MODULUS
        return state / MODULUS
    end
end

local function Contains(text, value)
    return tostring(text or ""):lower():find(tostring(value):lower(), 1, true) ~= nil
end

local function AssetSource(source, resolveAsset)
    if type(source) == "table" and type(source.asset) == "table" then source = source.asset end
    if type(source) == "string" then
        source = resolveAsset and resolveAsset(source) or { assetId = source }
    end
    if type(source) ~= "table" then return nil end
    if not source.bounds and resolveAsset then
        local resolved = resolveAsset(source.assetId or source.id, source.versionId)
        if resolved then return resolved end
    end
    return source
end

local function AssetId(asset)
    return tostring(asset and (asset.assetId or asset.id) or "")
end

local function AssetText(asset)
    local values = {
        AssetId(asset), asset and asset.name, asset and asset.category,
        asset and asset.description, asset and asset.designProfile,
    }
    for _, tag in ipairs(type(asset and asset.tags) == "table" and asset.tags or {}) do
        values[#values + 1] = tag
    end
    return table.concat(values, " "):lower()
end

function IslandAutoBuilder.ClassifyAsset(asset)
    asset = type(asset) == "table" and asset or {}
    local category, text = tostring(asset.category or ""), AssetText(asset)
    if category == "可进入建筑" or Contains(category, "建筑") then return "building" end
    if category == "树木单件" or Contains(category, "树木") then return "tree" end
    if category == "植被单件" or Contains(category, "植被") then return "vegetation" end
    if category == "山体构件" or Contains(category, "山体") then return "mountain" end
    if category == "遗迹构件" or Contains(category, "遗迹") then return "ruin" end
    if category == "飞行器" or Contains(category, "飞行") then return "aircraft" end
    if category == "围栏构件" or Contains(category, "围栏") then return "fence" end
    if category == "街景设施" or Contains(category, "街景") then return "street" end
    if category == "组合构件" then
        if Contains(text, "path") or Contains(text, "road") or Contains(text, "bridge")
            or Contains(text, "step") or Contains(text, "deck") or Contains(text, "路")
            or Contains(text, "桥") or Contains(text, "阶") or Contains(text, "平台") then return "path" end
        if Contains(text, "pond") or Contains(text, "water") or Contains(text, "池")
            or Contains(text, "水") then return "water" end
        if Contains(text, "boulder") or Contains(text, "rock") or Contains(text, "石") then return "mountain" end
        if Contains(text, "arch") or Contains(text, "拱门") then return "landmark" end
        return "prop"
    end
    if Contains(text, "house") or Contains(text, "home") or Contains(text, "cottage")
        or Contains(text, "房") or Contains(text, "屋") then return "building" end
    if Contains(text, "tree") or Contains(text, "pine") or Contains(text, "oak")
        or Contains(text, "树") or Contains(text, "杉") then return "tree" end
    if Contains(text, "grass") or Contains(text, "flower") or Contains(text, "shrub")
        or Contains(text, "草") or Contains(text, "花") or Contains(text, "灌木") then return "vegetation" end
    if Contains(text, "mountain") or Contains(text, "peak") or Contains(text, "cliff")
        or Contains(text, "山") or Contains(text, "峰") or Contains(text, "崖") then return "mountain" end
    if Contains(text, "wall") or Contains(text, "fence") or Contains(text, "rail")
        or Contains(text, "墙") or Contains(text, "栏") then return "fence" end
    if Contains(text, "lamp") or Contains(text, "bench") or Contains(text, "sign")
        or Contains(text, "灯") or Contains(text, "椅") or Contains(text, "牌") then return "street" end
    return "prop"
end

local function AssetDimensions(asset)
    local bounds = type(asset.bounds) == "table" and asset.bounds or {}
    local size = type(bounds.size) == "table" and bounds.size or {}
    local width, height, depth = tonumber(size[1]), tonumber(size[2]), tonumber(size[3])
    local resolvedBounds = asset.bounds
    if not width or not depth then
        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
        for _, block in ipairs(type(asset.blocks) == "table" and asset.blocks or {}) do
            local position, blockSize = block.position or {}, block.size or {}
            local x, y, z = tonumber(position[1]) or 0, tonumber(position[2]) or 0, tonumber(position[3]) or 0
            local sx, sy, sz = tonumber(blockSize[1]) or 1, tonumber(blockSize[2]) or 1, tonumber(blockSize[3]) or 1
            minX, maxX = math.min(minX, x - sx * 0.5), math.max(maxX, x + sx * 0.5)
            minY, maxY = math.min(minY, y - sy * 0.5), math.max(maxY, y + sy * 0.5)
            minZ, maxZ = math.min(minZ, z - sz * 0.5), math.max(maxZ, z + sz * 0.5)
        end
        if minX < math.huge then
            width, height, depth = maxX - minX, maxY - minY, maxZ - minZ
            resolvedBounds = {
                min = { minX, minY, minZ }, max = { maxX, maxY, maxZ },
                size = { width, height, depth },
            }
        end
    end
    width, height, depth = math.max(0.2, width or 1), math.max(0.2, height or 1), math.max(0.2, depth or 1)
    resolvedBounds = resolvedBounds or {
        min = { -width * 0.5, 0, -depth * 0.5 },
        max = { width * 0.5, height, depth * 0.5 }, size = { width, height, depth },
    }
    return width, height, depth, resolvedBounds
end

-- Buildings in the library do not all put their doorway on local +Z. Prefer
-- the authored wall name, then fall back to the door leaf's nearest bounds
-- edge. The returned vector is in model-local X/Z space.
local function EntranceDirection(asset)
    local blocks = type(asset and asset.blocks) == "table" and asset.blocks or {}
    for _, block in ipairs(blocks) do
        local name = tostring(block.name or "")
        if Contains(name, "front墙·门洞") or Contains(name, "前墙·门洞") then return 0, 1 end
        if Contains(name, "back墙·门洞") or Contains(name, "后墙·门洞") then return 0, -1 end
        if Contains(name, "right墙·门洞") or Contains(name, "右墙·门洞") then return 1, 0 end
        if Contains(name, "left墙·门洞") or Contains(name, "左墙·门洞") then return -1, 0 end
    end
    local bounds = type(asset and asset.bounds) == "table" and asset.bounds or {}
    local minimum, maximum = bounds.min or {}, bounds.max or {}
    local minX, maxX = tonumber(minimum[1]), tonumber(maximum[1])
    local minZ, maxZ = tonumber(minimum[3]), tonumber(maximum[3])
    if minX and maxX and minZ and maxZ then
        for _, block in ipairs(blocks) do
            if tostring(block.type or "") == "door" or Contains(block.name, "门板") then
                local position = block.position or {}
                local x, z = tonumber(position[1]) or 0, tonumber(position[3]) or 0
                local edges = {
                    { math.abs(x - maxX), 1, 0 }, { math.abs(x - minX), -1, 0 },
                    { math.abs(z - maxZ), 0, 1 }, { math.abs(z - minZ), 0, -1 },
                }
                table.sort(edges, function(first, second) return first[1] < second[1] end)
                return edges[1][2], edges[1][3]
            end
        end
    end
    return 0, 1
end

local function NormalizeAssets(selectedAssets, resolveAsset)
    local result, seen, pending = {}, {}, {}
    if type(selectedAssets) == "table" then
        if #selectedAssets > 0 then
            for _, source in ipairs(selectedAssets) do pending[#pending + 1] = source end
        else
            for key, source in pairs(selectedAssets) do
                if source ~= false and source ~= nil then pending[#pending + 1] = source == true and key or source end
            end
        end
    end
    for _, source in ipairs(pending) do
        local asset = AssetSource(source, resolveAsset)
        local id = AssetId(asset)
        if asset and id ~= "" and not seen[id] then
            seen[id] = true
            local width, height, depth, resolvedBounds = AssetDimensions(asset)
            local entranceX, entranceZ = EntranceDirection(asset)
            result[#result + 1] = {
                asset = asset, assetId = id,
                versionId = tostring(asset.versionId or "latest"),
                role = IslandAutoBuilder.ClassifyAsset(asset),
                width = width, height = height, depth = depth,
                scale = Clamp(tonumber(asset.recommendedScale) or 1, 0.1, 3),
                entranceX = entranceX, entranceZ = entranceZ,
                footprintAsset = asset.bounds and asset or { bounds = resolvedBounds },
            }
        end
    end
    table.sort(result, function(first, second)
        local firstOrder, secondOrder = ROLE_ORDER[first.role] or 99, ROLE_ORDER[second.role] or 99
        if firstOrder ~= secondOrder then return firstOrder < secondOrder end
        return first.assetId < second.assetId
    end)
    return result
end

local function ResolveTheme(assets, requested)
    local requestedId = type(requested) == "table" and requested.id or requested
    requestedId = tostring(requestedId or "")
    if THEMES[requestedId] then return THEMES[requestedId] end
    local counts = {}
    for _, asset in ipairs(assets) do counts[asset.role] = (counts[asset.role] or 0) + 1 end
    local candidates = {
        { "forest", (counts.tree or 0) + (counts.vegetation or 0) * 0.7 },
        { "mountain", (counts.mountain or 0) * 1.2 + (counts.ruin or 0) },
        { "village", (counts.building or 0) * 1.4 + (counts.street or 0) * 0.5 + (counts.fence or 0) * 0.4 },
        { "skyport", (counts.aircraft or 0) * 2 + (counts.path or 0) * 0.25 },
        { "garden", (counts.water or 0) * 1.6 + (counts.vegetation or 0) * 0.6 + (counts.street or 0) * 0.2 },
        { "ruins", (counts.ruin or 0) * 1.8 + (counts.mountain or 0) * 0.35 },
    }
    table.sort(candidates, function(a, b) return a[2] == b[2] and a[1] < b[1] or a[2] > b[2] end)
    if candidates[1][2] >= math.max(3, #assets * 0.38) then return THEMES[candidates[1][1]] end
    return THEMES.mixed
end

local function LayoutCentre(layout)
    local total, x, z = 0, 0, 0
    for _, island in ipairs(layout.islands or {}) do
        local weight = math.max(1, (tonumber(island.radiusX or island.radius) or 1)
            * (tonumber(island.radiusZ or island.radius) or 1))
        x, z, total = x + island.x * weight, z + island.z * weight, total + weight
    end
    if total <= 0 then return 0, 0 end
    return x / total, z / total
end

local function IslandArea(island)
    return math.max(0.1, tonumber(island.radiusX or island.radius) or 1)
        * math.max(0.1, tonumber(island.radiusZ or island.radius) or 1)
end

local function SortedIslands(layout)
    local result = {}
    for _, island in ipairs(layout.islands or {}) do result[#result + 1] = island end
    table.sort(result, function(first, second)
        local firstArea, secondArea = IslandArea(first), IslandArea(second)
        if firstArea ~= secondArea then return firstArea > secondArea end
        return tostring(first.id) < tostring(second.id)
    end)
    return result
end

local function EntranceAngle(layout, island, centreX, centreZ)
    local targetX, targetZ, found = centreX, centreZ, false
    for _, bridge in ipairs(layout.bridges or {}) do
        local otherId
        if tostring(bridge.from) == tostring(island.id) then otherId = bridge.to
        elseif tostring(bridge.to) == tostring(island.id) then otherId = bridge.from end
        if otherId then
            local other = layout.GetIsland and layout:GetIsland(otherId) or nil
            if other then targetX, targetZ, found = other.x, other.z, true; break end
        end
    end
    if not found and math.abs(targetX - island.x) + math.abs(targetZ - island.z) < 0.001 then
        targetZ = island.z + 1
    end
    local radiusX = math.max(0.1, tonumber(island.radiusX or island.radius) or 1)
    local radiusZ = math.max(0.1, tonumber(island.radiusZ or island.radius) or 1)
    return math.atan((targetZ - island.z) / radiusZ, (targetX - island.x) / radiusX)
end

local function MakeBox(x, z, halfWidth, halfDepth, rotation)
    halfWidth, halfDepth = math.max(0.01, halfWidth), math.max(0.01, halfDepth)
    rotation = NormalizeAngle(rotation)
    local cosine, sine = math.cos(rotation), math.sin(rotation)
    local result = {
        x = x, z = z, halfWidth = halfWidth, halfDepth = halfDepth,
        axisXx = cosine, axisXz = -sine,
        axisZx = sine, axisZz = cosine,
    }
    result.hx = halfWidth * math.abs(result.axisXx) + halfDepth * math.abs(result.axisZx)
    result.hz = halfWidth * math.abs(result.axisXz) + halfDepth * math.abs(result.axisZz)
    result.corners = {}
    for _, signs in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
        result.corners[#result.corners + 1] = {
            x = x + signs[1] * halfWidth * result.axisXx + signs[2] * halfDepth * result.axisZx,
            z = z + signs[1] * halfWidth * result.axisXz + signs[2] * halfDepth * result.axisZz,
        }
    end
    return result
end

local function BuildZones(layout, islands)
    local centreX, centreZ = LayoutCentre(layout)
    local zones = {}
    for _, island in ipairs(islands) do
        local entryAngle = EntranceAngle(layout, island, centreX, centreZ)
        local radiusX = math.max(0.1, tonumber(island.radiusX or island.radius) or 1)
        local radiusZ = math.max(0.1, tonumber(island.radiusZ or island.radius) or 1)
        local minimumRadius = math.min(radiusX, radiusZ)
        local function Point(angle, radius)
            return {
                x = island.x + math.cos(angle) * radiusX * radius,
                z = island.z + math.sin(angle) * radiusZ * radius,
            }
        end
        local entrance, plaza = Point(entryAngle, 0.70), Point(entryAngle, 0.10)
        local roadX, roadZ = plaza.x - entrance.x, plaza.z - entrance.z
        local roadLength = math.max(0.1, math.sqrt(roadX * roadX + roadZ * roadZ))
        local inwardX, inwardZ = roadX / roadLength, roadZ / roadLength
        local rightX, rightZ = -inwardZ, inwardX
        local roadHalfWidth = Clamp(minimumRadius * 0.068, 1.45, 2.45)
        local portalHalfSize = Clamp(minimumRadius * 0.070, 1.55, 2.25)
        local portalOffset = math.min(minimumRadius * 0.33,
            roadHalfWidth + portalHalfSize + 0.75)
        local roadRotation = math.atan(inwardX, inwardZ)
        zones[tostring(island.id)] = {
            islandId = island.id, islandName = island.name, entryAngle = entryAngle,
            radiusX = radiusX, radiusZ = radiusZ, minimumRadius = minimumRadius,
            entrance = entrance, plaza = plaza,
            settlement = Point(entryAngle, 0.30),
            grove = Point(entryAngle + math.pi * 0.58, 0.50),
            garden = Point(entryAngle - math.pi * 0.58, 0.45),
            vista = Point(entryAngle + math.pi, 0.58),
            inwardX = inwardX, inwardZ = inwardZ,
            outwardX = -inwardX, outwardZ = -inwardZ,
            rightX = rightX, rightZ = rightZ,
            roadLength = roadLength, roadRotation = roadRotation,
            roadHalfWidth = roadHalfWidth,
            road = MakeBox((entrance.x + plaza.x) * 0.5, (entrance.z + plaza.z) * 0.5,
                roadHalfWidth, roadLength * 0.5, roadRotation),
            portal = {
                x = plaza.x + rightX * portalOffset,
                z = plaza.z + rightZ * portalOffset,
                halfSize = portalHalfSize,
            },
        }
    end
    return zones
end

local MODEL_PADDING = {
    mountain = 0.40, ruin = 0.38, building = 0.46, landmark = 0.40,
    aircraft = 0.48, water = 0.22, path = 0.05, tree = 0.28,
    fence = 0.12, street = 0.16, vegetation = 0.12, prop = 0.20,
}

local function ModelPadding(role)
    return MODEL_PADDING[role] or 0.20
end

local function LayoutCapacity(layout, islands)
    local inset = math.max(0, tonumber(layout.edgeInset or layout.EDGE_INSET) or 0)
    local area = 0
    for _, island in ipairs(islands) do
        local radiusX = math.max(0.1, (tonumber(island.radiusX or island.radius) or 1) - inset)
        local radiusZ = math.max(0.1, (tonumber(island.radiusZ or island.radius) or 1) - inset)
        area = area + math.pi * radiusX * radiusZ
    end
    local root = math.sqrt(math.max(1, area))
    return {
        area = area,
        modelAreaBudget = area * 0.20,
        maxUnique = math.floor(Clamp(root * 0.68, 10, 48)),
        maxInstances = math.floor(Clamp(root * 0.84, 16, 62)),
    }
end

local function AssetCost(data)
    local padding = ModelPadding(data.role)
    return math.max(0.25, (data.width * data.scale + padding * 2)
        * (data.depth * data.scale + padding * 2))
end

-- Selecting the complete library is useful as an intention, not as an order
-- to cover every square metre. Keep one representative of every available
-- role first, then add deterministic themed variety until either the visual
-- count or the actual footprint budget is reached.
local function SampleAssets(assets, theme, capacity, seed)
    if #assets == 0 then return {}, {} end
    local groups, roleIds = {}, {}
    for _, asset in ipairs(assets) do
        if not groups[asset.role] then
            groups[asset.role] = {}
            roleIds[#roleIds + 1] = asset.role
        end
        groups[asset.role][#groups[asset.role] + 1] = asset
    end
    local seedHash = HashText(seed)
    for _, role in ipairs(roleIds) do
        table.sort(groups[role], function(first, second)
            local firstHash = HashText(first.assetId, seedHash)
            local secondHash = HashText(second.assetId, seedHash)
            if firstHash ~= secondHash then return firstHash < secondHash end
            return first.assetId < second.assetId
        end)
    end
    table.sort(roleIds, function(first, second)
        local firstBoost = tonumber(theme.boost and theme.boost[first]) or 0
        local secondBoost = tonumber(theme.boost and theme.boost[second]) or 0
        if firstBoost ~= secondBoost then return firstBoost > secondBoost end
        return (ROLE_ORDER[first] or 99) < (ROLE_ORDER[second] or 99)
    end)

    local selected, selectedSet, spent, cursors = {}, {}, 0, {}
    local maxUnique = math.min(#assets, capacity.maxUnique)
    local round = 1
    while #selected < maxUnique do
        local progressed = false
        for _, role in ipairs(roleIds) do
            local cursor = (cursors[role] or 0) + 1
            local candidate = groups[role][cursor]
            if candidate and #selected < maxUnique then
                cursors[role] = cursor
                local cost = AssetCost(candidate)
                -- The first pass preserves role diversity even when one
                -- landmark is expensive; later passes obey the density cap.
                if round == 1 or spent + cost <= capacity.modelAreaBudget then
                    selected[#selected + 1] = candidate
                    selectedSet[candidate.assetId] = true
                    spent = spent + cost
                end
                progressed = true
            end
        end
        if not progressed then break end
        round = round + 1
        if round > #assets + 1 then break end
    end

    local sampledOut = {}
    for _, asset in ipairs(assets) do
        if not selectedSet[asset.assetId] then sampledOut[#sampledOut + 1] = asset end
    end
    return selected, sampledOut
end

local PLACEMENT_ORDER = {
    mountain = 1, ruin = 2, building = 3, landmark = 4, aircraft = 5,
    water = 6, path = 7, tree = 8, fence = 9, street = 10,
    vegetation = 11, prop = 12,
}

local function DesiredCopies(asset, theme, crowded)
    if crowded then return 1 end
    local copies = 1
    if asset.role == "path" then copies = 5
    elseif asset.role == "tree" then copies = 3
    elseif asset.role == "vegetation" then copies = 4
    elseif asset.role == "street" or asset.role == "fence" then copies = 2
    elseif asset.role == "water" or asset.role == "prop" then copies = 2 end
    local boost = math.min(2, tonumber(theme.boost and theme.boost[asset.role]) or 0)
    return Clamp(copies + boost, 1, 6)
end

local function MakeTasks(assets, theme, capacity)
    local tasks, roleCounts = {}, {}
    local crowded = #assets > 24
    for _, asset in ipairs(assets) do
        roleCounts[asset.role] = (roleCounts[asset.role] or 0) + 1
        tasks[#tasks + 1] = {
            data = asset, copyIndex = 1,
            roleIndex = roleCounts[asset.role],
            copies = DesiredCopies(asset, theme, crowded),
        }
    end
    for copyIndex = 2, 6 do
        for _, asset in ipairs(assets) do
            if #tasks >= capacity.maxInstances then break end
            local copies = DesiredCopies(asset, theme, crowded)
            if copies >= copyIndex then
                tasks[#tasks + 1] = {
                    data = asset, copyIndex = copyIndex,
                    roleIndex = roleCounts[asset.role] + copyIndex - 1,
                    copies = copies,
                }
            end
        end
        if #tasks >= capacity.maxInstances then break end
    end
    table.sort(tasks, function(first, second)
        if first.copyIndex ~= second.copyIndex then return first.copyIndex < second.copyIndex end
        local firstOrder = PLACEMENT_ORDER[first.data.role] or 99
        local secondOrder = PLACEMENT_ORDER[second.data.role] or 99
        if firstOrder ~= secondOrder then return firstOrder < secondOrder end
        local firstArea, secondArea = AssetCost(first.data), AssetCost(second.data)
        if firstArea ~= secondArea then return firstArea > secondArea end
        return first.data.assetId < second.data.assetId
    end)
    return tasks
end

local function ProjectionRadius(footprint, axisX, axisZ)
    return footprint.halfWidth * math.abs(footprint.axisXx * axisX + footprint.axisXz * axisZ)
        + footprint.halfDepth * math.abs(footprint.axisZx * axisX + footprint.axisZz * axisZ)
end

-- Separating-axis test for the actual rotated rectangles. The previous
-- planner compared only world-aligned bounding boxes and intentionally
-- accepted large intersection ratios, which made diagonal models pile up.
local function BoxesOverlap(first, second, gap)
    local deltaX, deltaZ = second.x - first.x, second.z - first.z
    gap = math.max(0, tonumber(gap) or 0)
    for _, axis in ipairs({
        { first.axisXx, first.axisXz }, { first.axisZx, first.axisZz },
        { second.axisXx, second.axisXz }, { second.axisZx, second.axisZz },
    }) do
        local separation = math.abs(deltaX * axis[1] + deltaZ * axis[2])
        local occupied = ProjectionRadius(first, axis[1], axis[2])
            + ProjectionRadius(second, axis[1], axis[2]) + gap
        if separation >= occupied - 0.000001 then return false end
    end
    return true
end

local OCCUPANCY_CELL_SIZE = 7

local function NewOccupancy()
    return { entries = {}, buckets = {} }
end

local function OccupancyRange(footprint, padding)
    local x, z = tonumber(footprint and footprint.x) or 0,
        tonumber(footprint and footprint.z) or 0
    padding = math.max(0, tonumber(padding) or 0)
    local hx = math.max(0.01, tonumber(footprint and footprint.hx) or 0.5) + padding
    local hz = math.max(0.01, tonumber(footprint and footprint.hz) or 0.5) + padding
    return math.floor((x - hx) / OCCUPANCY_CELL_SIZE),
        math.floor((x + hx) / OCCUPANCY_CELL_SIZE),
        math.floor((z - hz) / OCCUPANCY_CELL_SIZE),
        math.floor((z + hz) / OCCUPANCY_CELL_SIZE)
end

local function OccupancyKey(cellX, cellZ)
    return tostring(cellX) .. ":" .. tostring(cellZ)
end

local function AddOccupancy(occupied, entry)
    occupied.entries[#occupied.entries + 1] = entry
    local minX, maxX, minZ, maxZ = OccupancyRange(entry.footprint, entry.padding)
    for cellX = minX, maxX do
        for cellZ = minZ, maxZ do
            local key = OccupancyKey(cellX, cellZ)
            local bucket = occupied.buckets[key]
            if not bucket then bucket = {}; occupied.buckets[key] = bucket end
            bucket[#bucket + 1] = entry
        end
    end
end

local function NearbyOccupancy(occupied, footprint, padding)
    local result, seen = {}, {}
    local minX, maxX, minZ, maxZ = OccupancyRange(footprint, padding)
    for cellX = minX, maxX do
        for cellZ = minZ, maxZ do
            for _, entry in ipairs(occupied.buckets[OccupancyKey(cellX, cellZ)] or {}) do
                if not seen[entry] then
                    seen[entry] = true
                    result[#result + 1] = entry
                end
            end
        end
    end
    return result
end

local function ReservationAllows(reserveType, role, candidateKind)
    if reserveType == "avenue" or reserveType == "entrance" then
        return role == "path" or candidateKind == "clearance"
    end
    if reserveType == "door" then
        return role == "path" or candidateKind == "clearance"
    end
    return false -- The portal pad is always kept completely open.
end

local function CanOccupy(footprint, role, occupied, padding, candidateKind)
    padding, candidateKind = math.max(0, tonumber(padding) or 0), candidateKind or "model"
    for _, other in ipairs(NearbyOccupancy(occupied, footprint, padding)) do
        local overlaps = BoxesOverlap(footprint, other.footprint,
            padding + math.max(0, tonumber(other.padding) or 0))
        if overlaps then
            if other.kind == "reservation" then
                if not ReservationAllows(other.reserveType, role, candidateKind) then return false end
            elseif other.kind == "clearance" then
                if not (candidateKind == "clearance" or role == "path") then return false end
            elseif candidateKind == "clearance" and other.kind == "model" then
                if other.role ~= "path" then return false end
            else
                -- Every pair of actual models is strict: no role-based
                -- exception and no relaxed late packing.
                return false
            end
        end
    end
    return true
end

local function AddPlanningReservations(occupied, zones)
    local reservations = {}
    for key, zone in pairs(zones) do
        if type(zone) == "table" and zone.islandId then
            local entranceHalf = math.max(1.55, zone.roadHalfWidth)
            local items = {
                { type = "avenue", footprint = zone.road },
                { type = "entrance", footprint = MakeBox(zone.entrance.x, zone.entrance.z,
                    entranceHalf, entranceHalf, zone.roadRotation) },
                { type = "portal", footprint = MakeBox(zone.portal.x, zone.portal.z,
                    zone.portal.halfSize, zone.portal.halfSize, zone.roadRotation) },
            }
            for _, item in ipairs(items) do
                AddOccupancy(occupied, {
                    kind = "reservation", reserveType = item.type,
                    role = "reservation", footprint = item.footprint, padding = 0,
                    islandId = zone.islandId,
                })
                reservations[#reservations + 1] = {
                    type = item.type, islandId = zone.islandId,
                    x = Round(item.footprint.x), z = Round(item.footprint.z),
                    rotationY = Round(zone.roadRotation),
                    width = Round(item.footprint.halfWidth * 2),
                    depth = Round(item.footprint.halfDepth * 2),
                }
            end
        end
    end
    table.sort(reservations, function(first, second)
        if tostring(first.islandId) ~= tostring(second.islandId) then
            return tostring(first.islandId) < tostring(second.islandId)
        end
        return first.type < second.type
    end)
    return reservations
end

local function PreferredIslandStart(task, islandCount)
    if islandCount <= 1 then return 1 end
    local role = task.data.role
    local start, stride = 1, 3
    if role == "mountain" or role == "ruin" or role == "landmark" then
        start, stride = islandCount, 2
    elseif role == "tree" or role == "vegetation" or role == "water" or role == "aircraft" then
        start, stride = math.min(2, islandCount), 2
    end
    local offset = math.floor((math.max(1, task.roleIndex) - 1) / stride) + task.copyIndex - 1
    if start == islandCount and (role == "mountain" or role == "ruin" or role == "landmark") then
        return ((start - 1 - offset) % islandCount) + 1
    end
    return ((start - 1 + offset) % islandCount) + 1
end

local function Candidate(task, island, zone, attempt, random)
    local role = task.data.role
    local sequence = attempt - 1 + task.copyIndex * 13 + task.roleIndex * 7
        + (HashText(task.data.assetId) % 31)
    local x, z, rotation, targetX, targetZ

    if role == "building" then
        local row = sequence % 5
        local side = (math.floor(sequence / 5) % 2 == 0) and -1 or 1
        local band = math.floor(sequence / 10) % 3
        local amount = 0.18 + row * 0.155
        local roadX = zone.plaza.x + (zone.entrance.x - zone.plaza.x) * amount
        local roadZ = zone.plaza.z + (zone.entrance.z - zone.plaza.z) * amount
        local depth = task.data.depth * task.data.scale
        local width = task.data.width * task.data.scale
        local entranceExtent = (math.abs(task.data.entranceX) * width
            + math.abs(task.data.entranceZ) * depth) * 0.5
        local frontageExtent = (math.abs(task.data.entranceZ) * width
            + math.abs(task.data.entranceX) * depth) * 0.5
        local lateral = zone.roadHalfWidth + entranceExtent + 0.82
            + band * math.max(1.25, frontageExtent * 1.16)
        x, z = roadX + zone.rightX * side * lateral,
            roadZ + zone.rightZ * side * lateral
        targetX, targetZ = roadX, roadZ
        local desired = math.atan(targetX - x, targetZ - z)
        local localEntrance = math.atan(task.data.entranceX, task.data.entranceZ)
        rotation = desired - localEntrance
    elseif role == "path" then
        local slot = sequence % 11
        local amount = (slot + 0.5) / 11
        x = zone.entrance.x + (zone.plaza.x - zone.entrance.x) * amount
        z = zone.entrance.z + (zone.plaza.z - zone.entrance.z) * amount
        rotation = zone.roadRotation
        if task.data.width > task.data.depth then rotation = rotation + math.pi * 0.5 end
        targetX, targetZ = x + zone.inwardX, z + zone.inwardZ
    elseif role == "street" then
        local slot = sequence % 9
        local side = (math.floor(sequence / 9) % 2 == 0) and -1 or 1
        local amount = 0.12 + slot * 0.095
        local roadX = zone.entrance.x + (zone.plaza.x - zone.entrance.x) * amount
        local roadZ = zone.entrance.z + (zone.plaza.z - zone.entrance.z) * amount
        local lateral = zone.roadHalfWidth + task.data.width * task.data.scale * 0.5 + 0.48
        x, z = roadX + zone.rightX * side * lateral,
            roadZ + zone.rightZ * side * lateral
        targetX, targetZ = roadX, roadZ
        rotation = math.atan(targetX - x, targetZ - z)
    else
        local sector, minimumRadius, maximumRadius, spread = 0, 0.12, 0.66, 0.95
        if role == "mountain" then sector, minimumRadius, maximumRadius, spread = math.pi, 0.44, 0.67, 0.72
        elseif role == "ruin" or role == "landmark" then
            sector, minimumRadius, maximumRadius, spread = math.pi * 0.88, 0.31, 0.64, 0.94
        elseif role == "aircraft" then sector, minimumRadius, maximumRadius, spread = -math.pi * 0.34, 0.24, 0.58, 0.78
        elseif role == "water" then sector, minimumRadius, maximumRadius, spread = -math.pi * 0.58, 0.30, 0.59, 0.72
        elseif role == "tree" then sector, minimumRadius, maximumRadius, spread = math.pi * 0.58, 0.31, 0.68, 0.82
        elseif role == "vegetation" then sector, minimumRadius, maximumRadius, spread = -math.pi * 0.66, 0.23, 0.69, 1.02
        elseif role == "fence" then sector, minimumRadius, maximumRadius, spread = math.pi * 0.82, 0.38, 0.66, 0.92
        else sector, minimumRadius, maximumRadius, spread = -math.pi * 0.24, 0.17, 0.58, 1.08 end
        local angle = zone.entryAngle + sector
            + (((sequence * GOLDEN_ANGLE) % TAU) - math.pi) / math.pi * spread
        local distribution = (sequence * 0.61803398875 + random() * 0.19) % 1
        local radius = minimumRadius + (maximumRadius - minimumRadius) * math.sqrt(distribution)
        x = island.x + math.cos(angle) * zone.radiusX * radius
        z = island.z + math.sin(angle) * zone.radiusZ * radius
        if role == "ruin" or role == "landmark" then
            targetX, targetZ = zone.plaza.x, zone.plaza.z
            rotation = math.atan(targetX - x, targetZ - z)
        elseif role == "fence" then
            rotation = angle + math.pi * 0.5
            if task.data.width < task.data.depth then rotation = rotation + math.pi * 0.5 end
        else
            rotation = angle + math.pi * 0.5 + (random() - 0.5) * 0.22
        end
    end
    return Round(x), Round(z), Round(NormalizeAngle(rotation)),
        targetX and Round(targetX) or nil, targetZ and Round(targetZ) or nil
end

local function ExistingOccupancy(layout, existingInstances, resolveAsset)
    local occupied, maximumId = NewOccupancy(), 0
    for _, instance in ipairs(existingInstances or {}) do
        maximumId = math.max(maximumId, tonumber(instance.id) or 0)
        local asset = instance.renderAsset or instance.asset
        if not asset and resolveAsset then asset = resolveAsset(instance.assetId, instance.versionId) end
        asset = asset or { bounds = { min = { -0.5, 0, -0.5 }, max = { 0.5, 1, 0.5 }, size = { 1, 1, 1 } } }
        local role = IslandAutoBuilder.ClassifyAsset(asset)
        local _, _, _, resolvedBounds = AssetDimensions(asset)
        AddOccupancy(occupied, {
            kind = "model", role = role, existing = true,
            footprint = layout:Footprint(instance,
                asset.bounds and asset or { bounds = resolvedBounds }),
            padding = ModelPadding(role),
        })
    end
    return occupied, maximumId
end

local function DoorClearance(footprint, data, rotation)
    local depth = Clamp(footprint.halfDepth * 0.78, 1.70, 2.85)
    local halfWidth = Clamp(footprint.halfWidth * 0.44, 0.78, 1.55)
    local cosine, sine = math.cos(rotation), math.sin(rotation)
    local forwardX = data.entranceX * cosine + data.entranceZ * sine
    local forwardZ = -data.entranceX * sine + data.entranceZ * cosine
    local edge = ProjectionRadius(footprint, forwardX, forwardZ)
    return MakeBox(
        footprint.x + forwardX * (edge + depth * 0.5 + 0.08),
        footprint.z + forwardZ * (edge + depth * 0.5 + 0.08),
        halfWidth, depth * 0.5,
        math.atan(forwardX, forwardZ))
end

local function FootprintFitsIsland(layout, island, footprint, margin)
    local inset = math.max(0, tonumber(layout.edgeInset or layout.EDGE_INSET) or 0)
        + math.max(0, tonumber(margin) or 0)
    local radiusX = math.max(0.01, (tonumber(island.radiusX or island.radius) or 0.01) - inset)
    local radiusZ = math.max(0.01, (tonumber(island.radiusZ or island.radius) or 0.01) - inset)
    local points = { { x = footprint.x, z = footprint.z } }
    for _, corner in ipairs(footprint.corners or {}) do points[#points + 1] = corner end
    for _, point in ipairs(points) do
        local dx, dz = point.x - island.x, point.z - island.z
        if dx * dx / (radiusX * radiusX) + dz * dz / (radiusZ * radiusZ) > 1 then return false end
    end
    local supported = layout.IsFootprintSupported and layout:IsFootprintSupported(footprint, 0.12)
    return supported ~= false
end

local function TryPlaceTask(task, layout, islands, zones, occupied, random, nextId)
    local start = PreferredIslandStart(task, #islands)
    local scale = Clamp(task.data.scale, 0.18, 3)
    local padding = ModelPadding(task.data.role)
    local attempts = task.copyIndex == 1 and 46 or 34
    for islandOffset = 0, #islands - 1 do
        local island = islands[((start - 1 + islandOffset) % #islands) + 1]
        local zone = zones[tostring(island.id)]
        for attempt = 1, attempts do
            local x, z, rotation, targetX, targetZ = Candidate(task, island, zone, attempt, random)
            local footprint = layout:Footprint(nil, task.data.footprintAsset, x, z, rotation, scale)
            if FootprintFitsIsland(layout, island, footprint, padding * 0.45)
                and CanOccupy(footprint, task.data.role, occupied, padding, "model") then
                local clearance
                if task.data.role == "building" then
                    clearance = DoorClearance(footprint, task.data, rotation)
                    if not FootprintFitsIsland(layout, island, clearance, 0.08)
                        or not CanOccupy(clearance, "building", occupied, 0.08, "clearance") then
                        clearance = nil
                    end
                end
                if task.data.role ~= "building" or clearance then
                    local instance = {
                        id = nextId, assetId = task.data.assetId, versionId = task.data.versionId,
                        -- Y is stored relative to the local terrain surface.
                        x = x, y = 0, z = z,
                        rotationY = rotation, scale = Round(scale),
                        autoRole = task.data.role,
                        autoZone = ZONE_FOR_ROLE[task.data.role] or "plaza",
                        autoIslandId = island.id,
                        autoFacingX = targetX, autoFacingZ = targetZ,
                        autoEntranceX = task.data.entranceX,
                        autoEntranceZ = task.data.entranceZ,
                    }
                    AddOccupancy(occupied, {
                        kind = "model", role = task.data.role, instanceId = nextId,
                        footprint = footprint, padding = padding,
                    })
                    if clearance then
                        AddOccupancy(occupied, {
                            kind = "clearance", reserveType = "door", role = "clearance",
                            ownerId = nextId, footprint = clearance, padding = 0,
                        })
                    end
                    return instance, island
                end
            end
        end
    end
    return nil
end

local function SummaryText(theme, stats)
    local parts = {}
    for _, role in ipairs({ "building", "path", "street", "fence", "tree", "vegetation", "mountain", "ruin", "aircraft", "water", "prop" }) do
        local value = stats.byRole[role]
        if value and value.placed > 0 then parts[#parts + 1] = ROLE_NAMES[role] .. tostring(value.placed) end
    end
    local notes = {}
    if (stats.sampledOut or 0) > 0 then
        notes[#notes + 1] = "为保持疏密层次抽样 " .. tostring(stats.sampledOut) .. " 个模型"
    end
    if (stats.spaceSkipped or 0) > 0 then
        notes[#notes + 1] = tostring(stats.spaceSkipped) .. " 个副本因净空不足未放置"
    end
    local suffix = #notes > 0 and ("；" .. table.concat(notes, "；")) or ""
    return theme.name .. "：" .. table.concat(parts, "、") .. suffix
end

-- options = {
--   selectedAssets = { full model assets, summaries, or ids },
--   layout = IslandLayout.Resolve(...), terrainId = optional fallback,
--   existingInstances = {}, resolveAsset = function(id, versionId),
--   seed = string|number, theme = mixed|village|forest|mountain|garden|skyport|ruins,
-- }
-- Returns a deterministic plan. `instances` can be passed directly to the
-- island project's instance creation path; auto* fields are explanatory and
-- safely ignored by the persisted canonical instance schema.
function IslandAutoBuilder.Build(options)
    options = type(options) == "table" and options or {}
    local layout = options.layout
    if type(layout) ~= "table" or type(layout.islands) ~= "table" then
        layout = IslandLayout.Resolve(options.terrainId)
    end
    local assets = NormalizeAssets(options.selectedAssets or options.assets, options.resolveAsset)
    local theme = ResolveTheme(assets, options.theme)
    local islands = SortedIslands(layout)
    local zones = BuildZones(layout, islands)
    local seedParts = { tostring(options.seed or 124), tostring(layout.id or layout.terrainId), theme.id }
    for _, asset in ipairs(assets) do seedParts[#seedParts + 1] = asset.assetId end
    local fullSeed = table.concat(seedParts, "|")
    local capacity = LayoutCapacity(layout, islands)
    local plannedAssets, sampledOut = SampleAssets(assets, theme, capacity, fullSeed)
    local tasks = MakeTasks(plannedAssets, theme, capacity)
    local random = NewRandom(fullSeed)
    local occupied, maximumId = ExistingOccupancy(layout,
        options.existingInstances or options.instances or {}, options.resolveAsset)
    local reservations = AddPlanningReservations(occupied, zones)
    local instances, used = {}, {}
    local stats = {
        selected = #assets, considered = #plannedAssets, requested = #tasks,
        placed = 0, placedUnique = 0, duplicates = 0,
        sampledOut = #sampledOut, spaceSkipped = 0, skipped = #sampledOut,
        densityLimit = capacity.maxInstances,
        byRole = {}, byIsland = {}, skippedAssets = {},
    }
    for _, island in ipairs(islands) do
        stats.byIsland[tostring(island.id)] = { id = island.id, name = island.name, placed = 0 }
    end
    for _, asset in ipairs(assets) do
        if not stats.byRole[asset.role] then
            stats.byRole[asset.role] = { id = asset.role, name = ROLE_NAMES[asset.role], selected = 0, placed = 0 }
        end
        stats.byRole[asset.role].selected = stats.byRole[asset.role].selected + 1
    end
    for _, asset in ipairs(sampledOut) do
        stats.skippedAssets[#stats.skippedAssets + 1] = {
            assetId = asset.assetId, name = asset.asset.name,
            role = asset.role, copyIndex = 1, reason = "density",
        }
    end
    local nextId = maximumId + 1
    for _, task in ipairs(tasks) do
        local instance, island = TryPlaceTask(task, layout, islands, zones, occupied, random, nextId)
        if instance then
            instances[#instances + 1], nextId = instance, nextId + 1
            stats.placed = stats.placed + 1
            stats.byRole[task.data.role].placed = stats.byRole[task.data.role].placed + 1
            stats.byIsland[tostring(island.id)].placed = stats.byIsland[tostring(island.id)].placed + 1
            if used[task.data.assetId] then stats.duplicates = stats.duplicates + 1
            else used[task.data.assetId] = true; stats.placedUnique = stats.placedUnique + 1 end
        else
            stats.spaceSkipped = stats.spaceSkipped + 1
            stats.skipped = stats.skipped + 1
            stats.skippedAssets[#stats.skippedAssets + 1] = {
                assetId = task.data.assetId, name = task.data.asset.name,
                role = task.data.role, copyIndex = task.copyIndex, reason = "space",
            }
        end
    end
    for zoneId, zoneName in pairs(ZONE_NAMES) do
        local count = 0
        for _, instance in ipairs(instances) do if instance.autoZone == zoneId then count = count + 1 end end
        zones[zoneId] = { id = zoneId, name = zoneName, placed = count }
    end
    stats.summary = SummaryText(theme, stats)
    return {
        schema = "island-auto-build/v1", seed = tostring(options.seed or 124),
        terrainId = tostring(layout.id or layout.terrainId or ""),
        theme = { id = theme.id, name = theme.name, description = theme.description },
        instances = instances, stats = stats, zones = zones,
        reservations = reservations,
    }
end

IslandAutoBuilder.Generate = IslandAutoBuilder.Build
IslandAutoBuilder.ROLE_NAMES = ROLE_NAMES
IslandAutoBuilder.THEMES = THEMES

return IslandAutoBuilder
