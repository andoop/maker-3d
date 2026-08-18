local RandomTerrainGenerator = {}

RandomTerrainGenerator.ALGORITHM_VERSION = 1
RandomTerrainGenerator.ID_PREFIX = "random-terrain-v1-"

local MODULUS = 2147483647
local MAX_SEED = MODULUS - 1
local MULTIPLIER = 16807
local QUOTIENT = 127773
local REMAINDER = 2836
local TAU = math.pi * 2

local FORMATIONS = {
    { id = "broken-halo", name = "断环浮境" },
    { id = "sky-ridge", name = "云脊阶岛" },
    { id = "twin-crescent", name = "双月裂谷" },
}

local STYLES = {
    "meadow", "cool-grove", "warm-meadow", "wind-cliff",
    "sunstone", "moonstone", "stone-crown",
}

local PROFILES = { "shelf", "sheer", "spire", "pillar", "needle" }

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Round(value, digits)
    local scale = 10 ^ (digits or 2)
    if value >= 0 then return math.floor(value * scale + 0.5) / scale end
    return math.ceil(value * scale - 0.5) / scale
end

local function HashString(value)
    local hash = 173
    local text = tostring(value or "")
    for index = 1, #text do
        hash = (hash * 131 + text:byte(index) + index * 17) % MAX_SEED
    end
    return hash + 1
end

---Normalize a numeric or textual seed without changing Lua's global RNG.
---@param value any
---@return integer
function RandomTerrainGenerator.NormalizeSeed(value)
    local numeric = tonumber(value)
    if numeric and numeric == numeric and numeric ~= math.huge and numeric ~= -math.huge then
        local integral = math.floor(math.abs(numeric))
        if integral < 1 then return 1 end
        return ((integral - 1) % MAX_SEED) + 1
    end
    return HashString(value)
end

---@param seed any
---@return string
function RandomTerrainGenerator.IdForSeed(seed)
    return RandomTerrainGenerator.ID_PREFIX .. tostring(RandomTerrainGenerator.NormalizeSeed(seed))
end

---@param terrainId any
---@return boolean
function RandomTerrainGenerator.IsId(terrainId)
    if type(terrainId) == "table" then
        terrainId = terrainId.terrainId or terrainId.id or terrainId.preset
    end
    local value = tostring(terrainId or "")
    if value:sub(1, #RandomTerrainGenerator.ID_PREFIX) ~= RandomTerrainGenerator.ID_PREFIX then
        return false
    end
    local seed = value:sub(#RandomTerrainGenerator.ID_PREFIX + 1)
    if not seed:match("^%d+$") then return false end
    local numeric = tonumber(seed)
    return numeric ~= nil and numeric >= 1 and numeric <= MAX_SEED
        and seed == tostring(math.floor(numeric))
end

---@param terrainId any
---@return integer|nil
function RandomTerrainGenerator.SeedFromId(terrainId)
    local value = type(terrainId) == "table"
        and (terrainId.terrainId or terrainId.id or terrainId.preset) or terrainId
    value = tostring(value or "")
    if value:sub(1, #RandomTerrainGenerator.ID_PREFIX) ~= RandomTerrainGenerator.ID_PREFIX then
        return nil
    end
    local encoded = value:sub(#RandomTerrainGenerator.ID_PREFIX + 1)
    if not encoded:match("^%d+$") then return nil end
    local seed = tonumber(encoded)
    if not seed or seed < 1 or seed > MAX_SEED then return nil end
    return math.floor(seed)
end

local Random = {}
Random.__index = Random

function Random.new(seed)
    local self = setmetatable({ state = RandomTerrainGenerator.NormalizeSeed(seed) }, Random)
    -- Park-Miller's first value is correlated for nearby numeric seeds. A
    -- short deterministic warm-up lets sequential user seeds explore all
    -- formations without changing reproducibility or touching global state.
    self:Next(); self:Next(); self:Next()
    return self
end

function Random:Next()
    local high = math.floor(self.state / QUOTIENT)
    local low = self.state - high * QUOTIENT
    local nextValue = MULTIPLIER * low - REMAINDER * high
    if nextValue <= 0 then nextValue = nextValue + MODULUS end
    self.state = nextValue
    return nextValue / MODULUS
end

function Random:Int(minimum, maximum)
    return minimum + math.floor(self:Next() * (maximum - minimum + 1))
end

function Random:Range(minimum, maximum)
    return minimum + (maximum - minimum) * self:Next()
end

function Random:Pick(values)
    return values[self:Int(1, #values)]
end

local function Island(rng, index, values)
    local radiusX = Round(values.radiusX, 2)
    local radiusZ = Round(values.radiusZ, 2)
    return {
        id = values.id or ("land-" .. tostring(index)),
        name = values.name or ("浮岛 " .. tostring(index)),
        x = Round(values.x, 2),
        z = Round(values.z, 2),
        radius = Round(math.max(radiusX, radiusZ), 2),
        radiusX = radiusX,
        radiusZ = radiusZ,
        groundY = Round(values.groundY, 2),
        focusRadius = Round(math.max(44, math.max(radiusX, radiusZ) * 2.55), 2),
        focusY = Round(values.groundY - 1.65, 2),
        style = values.style or rng:Pick(STYLES),
        seed = rng:Int(31, 2000000000),
        terrainProfile = values.terrainProfile or rng:Pick(PROFILES),
        depthScale = Round(values.depthScale or rng:Range(1.55, 2.45), 2),
        tipLeanX = Round(values.tipLeanX or rng:Range(-2.4, 2.4), 2),
        tipLeanZ = Round(values.tipLeanZ or rng:Range(-2.4, 2.4), 2),
        buildable = values.buildable == true,
    }
end

local function BrokenBridge(rng, id, from, to, width)
    return {
        id = id,
        from = from,
        to = to,
        halfWidth = Round(width or rng:Range(1.38, 1.92), 2),
        maxStepHeight = Round(rng:Range(0.56, 0.68), 2),
        stepSpacing = Round(rng:Range(2.25, 2.95), 2),
        landingOverlap = 0.16,
        broken = true,
        style = "shattered-stepping-stones",
    }
end

local function BuildBrokenHalo(rng)
    local islands, bridges = {}, {}
    local mainY = Round(rng:Range(-0.8, 1.4), 2)
    islands[1] = Island(rng, 1, {
        id = "build-haven", name = "环心原野", x = 0, z = 0,
        radiusX = rng:Range(29, 34), radiusZ = rng:Range(25, 31),
        groundY = mainY, terrainProfile = "sheer", depthScale = rng:Range(1.55, 1.85),
        buildable = true,
    })

    local satelliteCount = 4 + rng:Int(0, 2)
    local phase = rng:Range(0, TAU)
    local heightPhase = rng:Range(0, TAU)
    for satelliteIndex = 1, satelliteCount do
        local amount = (satelliteIndex - 1) / satelliteCount
        local angle = phase + amount * TAU + rng:Range(-0.10, 0.10)
        local distance = rng:Range(70, 84)
        local radiusX, radiusZ = rng:Range(12.5, 18.5), rng:Range(11.5, 17.0)
        local height = mainY + math.sin(angle + heightPhase) * 6.4 + rng:Range(-1.0, 1.0)
        islands[#islands + 1] = Island(rng, #islands + 1, {
            id = "halo-" .. tostring(satelliteIndex),
            name = "断环台 " .. tostring(satelliteIndex),
            x = math.sin(angle) * distance,
            z = math.cos(angle) * distance,
            radiusX = radiusX,
            radiusZ = radiusZ,
            groundY = height,
        })
    end

    -- The outer chain reads as one fractured halo; two short spokes keep the
    -- large central building lawn connected without a dense starburst.
    for index = 2, #islands do
        local nextIndex = index == #islands and 2 or index + 1
        bridges[#bridges + 1] = BrokenBridge(rng,
            "halo-chain-" .. tostring(index - 1), islands[index].id, islands[nextIndex].id)
    end
    local closest, opposite = 2, 2 + math.floor(satelliteCount * 0.5)
    bridges[#bridges + 1] = BrokenBridge(rng, "halo-heart-a", islands[1].id, islands[closest].id, 1.92)
    bridges[#bridges + 1] = BrokenBridge(rng, "halo-heart-b", islands[1].id, islands[opposite].id, 1.82)
    return islands, bridges
end

local function BuildSkyRidge(rng)
    local islands, bridges = {}, {}
    local count = 6 + rng:Int(0, 1)
    local spacing = rng:Range(70, 76)
    local rise = rng:Range(2.25, 2.65)
    local bendPhase = rng:Range(0, TAU)
    local middle = math.ceil(count * 0.5)
    for index = 1, count do
        local offset = index - middle
        local main = index == middle
        local radiusX = main and rng:Range(27, 32) or rng:Range(12.5, 18.5)
        local radiusZ = main and rng:Range(24, 29) or rng:Range(11.5, 17.5)
        local height = (index - 1) * rise - (count - 1) * rise * 0.5
            + math.sin(index * 1.07 + bendPhase) * 1.8
        islands[#islands + 1] = Island(rng, index, {
            id = main and "build-haven" or ("ridge-" .. tostring(index)),
            name = main and "云脊原野" or ("云脊台 " .. tostring(index)),
            x = offset * spacing + rng:Range(-2.4, 2.4),
            z = math.sin(index * 0.92 + bendPhase) * 24 + rng:Range(-3.0, 3.0),
            radiusX = radiusX,
            radiusZ = radiusZ,
            groundY = height,
            terrainProfile = main and "sheer" or nil,
            buildable = main,
        })
        if index > 1 then
            bridges[#bridges + 1] = BrokenBridge(rng, "ridge-step-" .. tostring(index - 1),
                islands[index - 1].id, islands[index].id, main and 1.92 or nil)
        end
    end
    return islands, bridges
end

local function BuildTwinCrescent(rng)
    local islands, bridges = {}, {}
    local mainY = rng:Range(-1.2, 1.2)
    islands[1] = Island(rng, 1, {
        id = "build-haven", name = "月谷原野", x = 0, z = 38,
        radiusX = rng:Range(29, 34), radiusZ = rng:Range(23, 28),
        groundY = mainY, terrainProfile = "sheer", buildable = true,
    })

    local perSide = 2 + rng:Int(0, 1)
    local previousBySide = {}
    for sideIndex, side in ipairs({ -1, 1 }) do
        local previous = islands[1]
        for level = 1, perSide do
            local curve = level / perSide
            local x = side * (42 + curve * 38 + math.sin(curve * math.pi) * 10)
            local z = 23 - curve * 168 + math.cos(curve * math.pi) * 7
            local height = mainY + side * 1.6 + (level - 1) * (3.6 + rng:Range(-0.4, 0.6))
                + (sideIndex == 1 and -2.1 or 2.1)
            local island = Island(rng, #islands + 1, {
                id = (side < 0 and "west-moon-" or "east-moon-") .. tostring(level),
                name = (side < 0 and "西月台 " or "东月台 ") .. tostring(level),
                x = x + rng:Range(-2.2, 2.2), z = z + rng:Range(-2.8, 2.8),
                radiusX = rng:Range(13.5, 18.5), radiusZ = rng:Range(13.0, 19.0),
                groundY = height,
                terrainProfile = level == perSide and "needle" or nil,
            })
            islands[#islands + 1] = island
            bridges[#bridges + 1] = BrokenBridge(rng,
                (side < 0 and "west-moon-step-" or "east-moon-step-") .. tostring(level),
                previous.id, island.id, level == 1 and 1.88 or nil)
            previous = island
        end
        previousBySide[sideIndex] = previous
    end
    if perSide == 2 then
        -- A small high satellite keeps the five-island variant from reading as
        -- a symmetrical logo while preserving one clear central building area.
        local satellite = Island(rng, #islands + 1, {
            id = "moon-shard", name = "坠月孤台",
            x = rng:Range(-12, 12), z = rng:Range(-172, -158),
            radiusX = rng:Range(10.5, 13.0), radiusZ = rng:Range(9.5, 12.0),
            groundY = mainY + rng:Range(8.8, 11.8), terrainProfile = "needle",
        })
        islands[#islands + 1] = satellite
        bridges[#bridges + 1] = BrokenBridge(rng, "moon-crown-step",
            previousBySide[rng:Int(1, 2)].id, satellite.id, 1.42)
    end
    return islands, bridges
end

local BUILDERS = { BuildBrokenHalo, BuildSkyRidge, BuildTwinCrescent }

local function EnsureHeightRange(islands)
    local minimumIndex, maximumIndex = 1, 1
    for index = 2, #islands do
        if islands[index].groundY < islands[minimumIndex].groundY then minimumIndex = index end
        if islands[index].groundY > islands[maximumIndex].groundY then maximumIndex = index end
    end
    if islands[maximumIndex].groundY - islands[minimumIndex].groundY < 10 then
        local centre = (islands[maximumIndex].groundY + islands[minimumIndex].groundY) * 0.5
        islands[minimumIndex].groundY = Round(centre - 5.2, 2)
        islands[maximumIndex].groundY = Round(centre + 5.2, 2)
        islands[minimumIndex].focusY = Round(islands[minimumIndex].groundY - 1.65, 2)
        islands[maximumIndex].focusY = Round(islands[maximumIndex].groundY - 1.65, 2)
    end
end

local function CameraFor(islands)
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    for _, island in ipairs(islands) do
        minX = math.min(minX, island.x - island.radiusX)
        maxX = math.max(maxX, island.x + island.radiusX)
        minZ = math.min(minZ, island.z - island.radiusZ)
        maxZ = math.max(maxZ, island.z + island.radiusZ)
        minY, maxY = math.min(minY, island.groundY), math.max(maxY, island.groundY)
    end
    local x, z = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
    local y = (minY + maxY) * 0.5 - 1.3
    local span = math.max(maxX - minX, maxZ - minZ)
    local radius = Clamp(span * 1.08 + (maxY - minY) * 1.4, 128, 440)
    return {
        overview = { x = Round(x, 2), y = Round(y, 2), z = Round(z, 2), radius = Round(radius, 2) },
        camera = {
            theta = 0.70, phi = 0.94, radius = Round(radius, 2),
            target = { Round(x, 2), Round(y, 2), Round(z, 2),
                x = Round(x, 2), y = Round(y, 2), z = Round(z, 2) },
        },
        renderDistance = {
            skyRadius = Round(math.max(760, radius * 4.25), 2),
            cameraFar = Round(math.max(1580, radius * 7.5), 2),
        },
    }
end

---Generate a bounded, pure-landform floating archipelago.
---The terrain ID includes the algorithm version and seed, so old saves remain
---stable if a later generator version is introduced.
---@param seed any
---@param options table|nil presentation-only options (name, id)
---@return table
function RandomTerrainGenerator.Generate(seed, options)
    options = type(options) == "table" and options or {}
    seed = RandomTerrainGenerator.NormalizeSeed(seed)
    local rng = Random.new(seed)
    local formationIndex = rng:Int(1, #FORMATIONS)
    local formation = FORMATIONS[formationIndex]
    local islands, bridges = BUILDERS[formationIndex](rng)
    EnsureHeightRange(islands)
    local view = CameraFor(islands)
    local terrainId = RandomTerrainGenerator.IsId(options.id)
        and tostring(options.id) or RandomTerrainGenerator.IdForSeed(seed)
    return {
        id = terrainId,
        name = tostring(options.name or (formation.name .. " · " .. string.format("%04d", seed % 10000))),
        description = tostring(options.description or "确定性生成的高低浮岛与破碎踏石"),
        generated = true,
        pureTerrain = true,
        algorithm = "seeded-floating-archipelago",
        algorithmVersion = RandomTerrainGenerator.ALGORITHM_VERSION,
        seed = seed,
        formation = "random-" .. formation.id,
        connectionStyle = "shattered-stepping-stones",
        groundY = islands[1].groundY,
        edgeInset = 0.38,
        overview = view.overview,
        camera = view.camera,
        renderDistance = view.renderDistance,
        islands = islands,
        bridges = bridges,
    }
end

---@param terrainId any
---@param options table|nil
---@return table|nil
function RandomTerrainGenerator.FromId(terrainId, options)
    local seed = RandomTerrainGenerator.SeedFromId(terrainId)
    if not seed then return nil end
    options = type(options) == "table" and options or {}
    options.id = type(terrainId) == "table"
        and (terrainId.terrainId or terrainId.id or terrainId.preset) or terrainId
    return RandomTerrainGenerator.Generate(seed, options)
end

return RandomTerrainGenerator
