-- Engine-independent picking helpers for whole island model instances.
--
-- Scene triangle hits remain the most precise signal. These helpers provide a
-- bounded oriented-box fallback for sparse models (grass, railings, lamp
-- posts) whose authored bounds are easy to see but whose real triangles only
-- occupy a tiny part of that box.

local IslandPicking = {}

local ENVIRONMENT_ISLAND_LAYERS = {
    "GrassCells",
    "SoilCells",
    "RockCells",
}

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Part(value, key, index)
    if value == nil then return nil end
    return tonumber(value[key]) or tonumber(value[index])
end

local function Coordinates(value)
    return Part(value, "x", 1), Part(value, "y", 2), Part(value, "z", 3)
end

local function Bounds(asset)
    local bounds = type(asset and asset.bounds) == "table" and asset.bounds or {}
    local minimum = type(bounds.min) == "table" and bounds.min or { -0.5, 0, -0.5 }
    local maximum = type(bounds.max) == "table" and bounds.max or { 0.5, 1, 0.5 }
    return {
        tonumber(minimum[1]) or -0.5,
        tonumber(minimum[2]) or 0,
        tonumber(minimum[3]) or -0.5,
    }, {
        tonumber(maximum[1]) or 0.5,
        tonumber(maximum[2]) or 1,
        tonumber(maximum[3]) or 0.5,
    }
end

local function Slab(origin, direction, minimum, maximum, near, far)
    if math.abs(direction) < 0.0000001 then
        if origin < minimum or origin > maximum then return nil end
        return near, far
    end
    local first, second = (minimum - origin) / direction, (maximum - origin) / direction
    if first > second then first, second = second, first end
    near, far = math.max(near, first), math.min(far, second)
    if far < near then return nil end
    return near, far
end

-- Returns world-ray entry distance for a translated, uniformly scaled and
-- Y-rotated asset bounds box. `rootY` is the actual rendered root position.
function IslandPicking.RayInstanceBounds(ray, instance, asset, rootY, worldPadding, maximumDistance)
    if not ray or not instance or not asset then return nil end
    local ox, oy, oz = Coordinates(ray.origin)
    local dx, dy, dz = Coordinates(ray.direction)
    if not ox or not oy or not oz or not dx or not dy or not dz then return nil end

    local scale = math.max(0.0001, math.abs(tonumber(instance.scale) or 1))
    local angle = tonumber(instance.rotationY) or 0
    local cosine, sine = math.cos(angle), math.sin(angle)
    local translatedX = ox - (tonumber(instance.x) or 0)
    local translatedY = oy - (tonumber(rootY) or 0)
    local translatedZ = oz - (tonumber(instance.z) or 0)

    -- Inverse of IslandWorld's local-to-world Y rotation:
    -- worldX = localX*c + localZ*s; worldZ = -localX*s + localZ*c.
    local localOrigin = {
        (translatedX * cosine - translatedZ * sine) / scale,
        translatedY / scale,
        (translatedX * sine + translatedZ * cosine) / scale,
    }
    local localDirection = {
        (dx * cosine - dz * sine) / scale,
        dy / scale,
        (dx * sine + dz * cosine) / scale,
    }
    local minimum, maximum = Bounds(asset)
    local padding = math.max(0, tonumber(worldPadding) or 0) / scale
    local near, far = 0, math.max(0.001, tonumber(maximumDistance) or 500)
    for axis = 1, 3 do
        near, far = Slab(localOrigin[axis], localDirection[axis],
            minimum[axis] - padding, maximum[axis] + padding, near, far)
        if not near then return nil end
    end
    return near, far
end

-- Convert a stable screen-space touch target into world units at a model's
-- depth. The cap prevents distant large bounds from becoming screen-wide.
function IslandPicking.WorldPadding(distance, viewportHeight, mobile, verticalFovDegrees, pixelScale)
    distance = math.max(0.01, tonumber(distance) or 1)
    viewportHeight = math.max(1, tonumber(viewportHeight) or 1)
    local pixels = (mobile and 18 or 7) * math.max(1, tonumber(pixelScale) or 1)
    local halfFov = math.rad((tonumber(verticalFovDegrees) or 40) * 0.5)
    local unitsPerPixel = 2 * distance * math.tan(halfFov) / viewportHeight
    return Clamp(unitsPerPixel * pixels, mobile and 0.10 or 0.04, 0.70)
end

-- Whole-bounds fallback is reserved for genuinely small or slender authored
-- models. Large hollow houses must be selected by real geometry so their
-- empty doors and rooms do not steal clicks from objects visible inside.
function IslandPicking.UseBoundsFallback(asset)
    local minimum, maximum = Bounds(asset)
    local width = math.max(0.01, maximum[1] - minimum[1])
    local height = math.max(0.01, maximum[2] - minimum[2])
    local depth = math.max(0.01, maximum[3] - minimum[3])
    local footprintArea = width * depth
    local thinSide = math.min(width, depth)
    if footprintArea > 12 and thinSide > 1.2 then return false end
    if thinSide <= 0.72 or math.max(width, height, depth) <= 1.45 then return true end
    local occupied = 0
    local blocks = type(asset and asset.blocks) == "table" and asset.blocks or {}
    for _, block in ipairs(blocks) do
        local size = type(block.size) == "table" and block.size or {}
        occupied = occupied + math.max(0, (tonumber(size[1]) or 1)
            * (tonumber(size[2]) or 1) * (tonumber(size[3]) or 1))
    end
    local density = #blocks == 0 and 0 or occupied / math.max(0.001, width * height * depth)
    return density <= 0.34
end

function IslandPicking.InstanceCenter(instance, asset, rootY)
    local minimum, maximum = Bounds(asset)
    local scale = tonumber(instance and instance.scale) or 1
    local localX = (minimum[1] + maximum[1]) * 0.5 * scale
    local localY = (minimum[2] + maximum[2]) * 0.5 * scale
    local localZ = (minimum[3] + maximum[3]) * 0.5 * scale
    local angle = tonumber(instance and instance.rotationY) or 0
    local cosine, sine = math.cos(angle), math.sin(angle)
    return {
        x = (tonumber(instance and instance.x) or 0) + localX * cosine + localZ * sine,
        y = (tonumber(rootY) or 0) + localY,
        z = (tonumber(instance and instance.z) or 0) - localX * sine + localZ * cosine,
    }
end

function IslandPicking.Distance(first, second)
    local ax, ay, az = Coordinates(first)
    local bx, by, bz = Coordinates(second)
    if not ax or not ay or not az or not bx or not by or not bz then return math.huge end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Choose between a real triangle hit and fallback box candidates. A proxy may
-- win only when it starts clearly in front of the real geometry; this lets a
-- thin foreground lamp be selected without allowing a distant giant bounds
-- box to steal a click from an actually touched model.
function IslandPicking.Choose(triangle, fallback)
    if not triangle then return fallback end
    if not fallback then return triangle end
    local triangleDistance = tonumber(triangle.distance) or math.huge
    local fallbackDistance = tonumber(fallback.distance) or math.huge
    if fallbackDistance + 0.03 < triangleDistance then return fallback end
    return triangle
end

-- Main-island foundations are rendered as separate merged grass, soil and
-- rock meshes. Recover the authored island index from those native node names
-- so a tap on the cliff wall or underside behaves like a tap on the top.
function IslandPicking.EnvironmentIslandIndex(nodeName)
    nodeName = tostring(nodeName or "")
    for _, layer in ipairs(ENVIRONMENT_ISLAND_LAYERS) do
        local prefix = "^IslandEnvironment_" .. layer
        local index = nodeName:match(prefix .. "(%d+)$")
            or nodeName:match(prefix .. "(%d+)_%d+$")
        if index then return tonumber(index) end
    end
    return nil
end

-- An island foundation must occlude a model that is geometrically behind it.
-- The small tolerance keeps coincident grass-top triangles deterministic.
function IslandPicking.IsIslandInFront(islandDistance, instanceDistance)
    islandDistance = tonumber(islandDistance)
    if not islandDistance then return false end
    instanceDistance = tonumber(instanceDistance)
    if not instanceDistance then return true end
    return islandDistance <= instanceDistance + 0.01
end

return IslandPicking
