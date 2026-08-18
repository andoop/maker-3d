-- Deterministic, engine-free description of the selectable storybook terrains.
-- Every island, bridge and distant silhouette is assembled from small bevelled
-- cells so the scene keeps the same crafted language at every scale.

local IslandLayout = require("IslandLayout")
local Theme = require("CloudAtelierTheme")

local StorybookIslandData = {}
local BUILD_CACHE = {}
local BUILD_CACHE_LIMIT = 4
local BUILD_CACHE_CLOCK = 0
local TAU = math.pi * 2
local GROUND_Y = 0.42

local PALETTE = Theme.ENVIRONMENT.island
local CLOUD = Theme.ENVIRONMENT.cloud
local DISTANCE = Theme.ENVIRONMENT.distance

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Fraction(value)
    return value - math.floor(value)
end

local function Hash(x, z, seed)
    return Fraction(math.sin(x * 12.9898 + z * 78.233 + seed * 37.719) * 43758.5453)
end

local function Pick(palette, x, z, seed)
    local value = Hash(x, z, seed)
    return palette[math.min(#palette, math.floor(value * #palette) + 1)]
end

local function EdgeRadius(base, angle, irregularity, seed)
    local broad = math.sin(angle * 5 + seed * 0.73) * 0.52
    local small = math.sin(angle * 11 - seed * 0.41) * 0.28
    local detail = math.sin(angle * 17 + seed * 0.19) * 0.20
    return base + (broad + small + detail) * irregularity
end

local function BuildLayer(options)
    local blocks = {}
    local cell = options.cell
    local radiusX = options.radiusX or options.radius
    local radiusZ = options.radiusZ or options.radius
    local baseRadius = math.min(radiusX, radiusZ)
    local extentX = math.ceil((radiusX + options.irregularity + cell) / cell)
    local extentZ = math.ceil((radiusZ + options.irregularity + cell) / cell)
    for ix = -extentX, extentX do
        for iz = -extentZ, extentZ do
            local localX, localZ = ix * cell, iz * cell
            local shapedX = localX * baseRadius / math.max(0.001, radiusX)
            local shapedZ = localZ * baseRadius / math.max(0.001, radiusZ)
            local angle = math.atan(shapedX, shapedZ)
            local distance = math.sqrt(shapedX * shapedX + shapedZ * shapedZ)
            local limit = EdgeRadius(baseRadius, angle, options.irregularity, options.seed)
            local insideInner = false
            local innerRadiusX = options.innerRadiusX or options.innerRadius
            local innerRadiusZ = options.innerRadiusZ or options.innerRadius
            if innerRadiusX and innerRadiusZ and innerRadiusX > 0 and innerRadiusZ > 0 then
                local innerBase = math.min(innerRadiusX, innerRadiusZ)
                local innerX = localX * innerBase / math.max(0.001, innerRadiusX)
                local innerZ = localZ * innerBase / math.max(0.001, innerRadiusZ)
                local innerDistance = math.sqrt(innerX * innerX + innerZ * innerZ)
                local innerLimit = EdgeRadius(innerBase, math.atan(innerX, innerZ),
                    options.innerIrregularity or options.irregularity * 0.28, options.seed + 101)
                insideInner = innerDistance < innerLimit
            end
            if distance <= limit and not insideInner then
                local shapeNoise = Hash(ix, iz, options.seed + 7)
                local heightNoise = Hash(ix, iz, options.seed + 13)
                local jitterX = options.jitter * (Hash(ix, iz, options.seed + 17) - 0.5)
                local jitterZ = options.jitter * (Hash(ix, iz, options.seed + 23) - 0.5)
                local height = options.height + (heightNoise - 0.5) * options.heightVariation
                if options.edgeHeight and distance >= limit - options.edgeBand then
                    height = options.edgeHeight + heightNoise * options.edgeHeightVariation
                end
                local bevel = options.bevel
                if options.innerBevel and distance < limit - options.edgeBand then bevel = options.innerBevel end
                local sizeVariation = options.sizeVariation or 0.055
                blocks[#blocks + 1] = {
                    x = (options.centerX or 0) + localX + jitterX,
                    y = options.topY - height * 0.5,
                    z = (options.centerZ or 0) + localZ + jitterZ,
                    sx = cell * (options.cellFill - sizeVariation + shapeNoise * sizeVariation),
                    sy = height,
                    sz = cell * (options.cellFill - sizeVariation
                        + Hash(ix, iz, options.seed + 29) * sizeVariation),
                    bevel = bevel,
                    color = Pick(options.palette, ix, iz, options.seed + 31),
                }
            end
        end
    end
    return blocks
end

local function AddBlock(target, x, y, z, sx, sy, sz, color, bevel, rotationY)
    target[#target + 1] = {
        x = x, y = y, z = z, sx = sx, sy = sy, sz = sz,
        color = color, bevel = bevel or 0.09, ry = tonumber(rotationY) or 0,
    }
end

local function AddLobe(target, x, y, z, rx, ry, rz, bottom, top)
    target[#target + 1] = {
        x = x, y = y, z = z, rx = rx, ry = ry, rz = rz,
        bottom = bottom, top = top,
    }
end

local function Append(target, source)
    for _, item in ipairs(source or {}) do target[#target + 1] = item end
end

local function BuildIsland(spec, index)
    local radiusX = spec.radiusX or spec.radius
    local radiusZ = spec.radiusZ or spec.radius
    local radius = math.sqrt(radiusX * radiusZ)
    local scale = radius / 14.5
    local seed = tonumber(spec.seed) or (11 + index * 61)
    local style = tostring(spec.palette or spec.style or "")
    local cool = style == "cool" or style:find("cool", 1, true)
        or style:find("pine", 1, true) or style:find("willow", 1, true)
        or style:find("dew", 1, true) or style:find("stone", 1, true)
    local warm = style == "warm" or style:find("warm", 1, true)
        or style:find("flower", 1, true) or style:find("blossom", 1, true)
        or style:find("lantern", 1, true)
    local grassPalette = cool and PALETTE.grassCool
        or warm and PALETTE.grassWarm
        or index == 2 and PALETTE.grassCool or index == 3 and PALETTE.grassWarm or PALETTE.grass
    local topY = tonumber(spec.groundY) or GROUND_Y
    local profileName = tostring(spec.terrainProfile or "")
    local profile = ({
        shelf = { upper = 0.84, lower = 0.64, tip = 0.35 },
        sheer = { upper = 0.90, lower = 0.72, tip = 0.45 },
        spire = { upper = 0.80, lower = 0.54, tip = 0.24 },
        needle = { upper = 0.70, lower = 0.42, tip = 0.14 },
        pillar = { upper = 0.91, lower = 0.73, tip = 0.46 },
    })[profileName]
    local depthScale = profile and math.max(1, tonumber(spec.depthScale) or 1.6) or 1
    local leanX, leanZ = tonumber(spec.tipLeanX) or 0, tonumber(spec.tipLeanZ) or 0
    local soilHeight = profile and 2.05 * scale * depthScale or 2.25 * scale
    local upperHeight = profile and 2.65 * scale * depthScale or 2.55 * scale
    local lowerHeight = profile and 2.85 * scale * depthScale or 2.75 * scale
    local tipHeight = profile and 3.10 * scale * depthScale or 2.45 * scale
    local upperTopY = profile and (topY - 0.46 - soilHeight * 0.68) or (topY - 2.14)
    local lowerTopY = profile and (upperTopY - upperHeight * 0.72) or (topY - 3.3 * scale - 0.67)
    local tipTopY = profile and (lowerTopY - lowerHeight * 0.72) or (topY - 5.2 * scale - 0.92)
    local upperRadius = profile and profile.upper or 0.78
    local lowerRadius = profile and profile.lower or 0.56
    local tipRadius = profile and profile.tip or 0.30
    return {
        id = spec.id, name = spec.name, x = spec.x, z = spec.z, radius = spec.radius or math.min(radiusX, radiusZ),
        radiusX = radiusX, radiusZ = radiusZ, groundY = topY,
        grass = BuildLayer({
            centerX = spec.x, centerZ = spec.z,
            radiusX = radiusX - 0.80, radiusZ = radiusZ - 0.80,
            irregularity = 0.48 * scale, cell = 2.42, seed = seed,
            topY = topY, height = 0.52, heightVariation = 0.04,
            edgeHeight = 0.76, edgeHeightVariation = 0.16, edgeBand = 1.35 * scale,
            jitter = 0.008, cellFill = 0.997, sizeVariation = 0.006,
            bevel = 0.075, innerBevel = 0.018, palette = grassPalette,
        }),
        soil = BuildLayer({
            centerX = spec.x, centerZ = spec.z,
            radiusX = radiusX - 1.40, radiusZ = radiusZ - 1.40,
            innerRadiusX = radiusX - 4.90 * scale, innerRadiusZ = radiusZ - 4.90 * scale,
            irregularity = 0.72 * scale, cell = 2.56, seed = seed + 12,
            topY = topY - 0.50, height = soilHeight, heightVariation = 0.72 * scale * depthScale,
            edgeHeight = profile and soilHeight * 1.08 or 2.45 * scale,
            edgeHeightVariation = 0.78 * scale * depthScale, edgeBand = 2.1 * scale,
            jitter = 0.10, cellFill = 0.965, sizeVariation = 0.055,
            bevel = 0.12, palette = PALETTE.soil,
        }),
        rockUpper = BuildLayer({
            centerX = spec.x + leanX * 0.16, centerZ = spec.z + leanZ * 0.16,
            radiusX = radiusX * upperRadius, radiusZ = radiusZ * upperRadius,
            innerRadiusX = radiusX * upperRadius - 4.0 * scale,
            innerRadiusZ = radiusZ * upperRadius - 4.0 * scale,
            irregularity = 0.92 * scale, cell = 2.72, seed = seed + 26,
            topY = upperTopY, height = upperHeight, heightVariation = 0.88 * scale * depthScale,
            edgeHeight = profile and upperHeight * 1.08 or 2.75 * scale,
            edgeHeightVariation = 0.72 * scale * depthScale, edgeBand = 2.4 * scale,
            jitter = 0.14, cellFill = 0.96, sizeVariation = 0.06,
            bevel = 0.14, palette = PALETTE.rock,
        }),
        rockLower = BuildLayer({
            centerX = spec.x + leanX * 0.54, centerZ = spec.z + leanZ * 0.54,
            radiusX = radiusX * lowerRadius, radiusZ = radiusZ * lowerRadius,
            innerRadiusX = radiusX * lowerRadius - 3.4 * scale,
            innerRadiusZ = radiusZ * lowerRadius - 3.4 * scale,
            irregularity = 1.05 * scale, cell = 2.74, seed = seed + 36,
            topY = lowerTopY, height = lowerHeight, heightVariation = 0.95 * scale * depthScale,
            edgeHeight = profile and lowerHeight * 1.08 or 2.95 * scale,
            edgeHeightVariation = 0.82 * scale * depthScale, edgeBand = 2.5 * scale,
            jitter = 0.15, cellFill = 0.955, sizeVariation = 0.06,
            bevel = 0.14, palette = PALETTE.rock,
        }),
        rockTip = BuildLayer({
            centerX = spec.x + leanX, centerZ = spec.z + leanZ,
            radiusX = radiusX * tipRadius, radiusZ = radiusZ * tipRadius,
            irregularity = 0.78 * scale, cell = 2.58, seed = seed + 48,
            topY = tipTopY, height = tipHeight, heightVariation = 0.92 * scale * depthScale,
            edgeHeight = profile and tipHeight * 1.10 or 2.65 * scale,
            edgeHeightVariation = 0.72 * scale * depthScale, edgeBand = 1.8 * scale,
            jitter = 0.13, cellFill = 0.95, sizeVariation = 0.06,
            bevel = 0.13, palette = PALETTE.rock,
        }),
    }
end

local function BuildTopDecor(data)
    for islandIndex, island in ipairs(data.islands) do
        local radiusX = (island.radiusX or island.radius) * 0.73
        local radiusZ = (island.radiusZ or island.radius) * 0.73
        local topY = island.groundY or GROUND_Y
        for clusterIndex = 1, 4 do
            local angle = TAU * clusterIndex / 4 + islandIndex * 0.43
            local x, z = island.x + math.sin(angle) * radiusX, island.z + math.cos(angle) * radiusZ
            for pieceIndex, piece in ipairs({
                { 0, 0, 1.45, 1.8, 1.35 }, { 0.82, 0.08, 1.05, 1.18, 0.98 },
                { -0.68, -0.16, 0.72, 0.70, 0.74 }, { 0.16, -0.64, 0.58, 0.52, 0.62 },
            }) do
                AddBlock(data.decorRocks, x + piece[1], topY + piece[4] * 0.5, z + piece[2],
                    piece[3], piece[4], piece[5], Pick(PALETTE.rockLight, islandIndex, pieceIndex, 81), 0.15)
            end
            for lobeIndex = 1, 4 do
                AddLobe(data.shrubs, x - 0.8 + lobeIndex * 0.32, topY + 0.34,
                    z + math.sin(lobeIndex * 1.7) * 0.24,
                    0.42 + (lobeIndex % 2) * 0.08, 0.38, 0.40,
                    PALETTE.shrubDark, islandIndex == 2 and PALETTE.grassCool[3] or PALETTE.shrubLight)
            end
        end
    end
end

local function BuildUndersideDetail(data, pureTerrain)
    for islandIndex, island in ipairs(data.islands) do
        local radiusX = island.radiusX or island.radius
        local radiusZ = island.radiusZ or island.radius
        local topY = island.groundY or GROUND_Y
        for index = 1, 18 do
            local angle = TAU * index / 18 + islandIndex * 0.19
            local amount = 0.74 + (index % 3) * 0.035
            local x = island.x + math.sin(angle) * radiusX * amount
            local z = island.z + math.cos(angle) * radiusZ * amount
            local y = topY - 2.42 - (index % 4) * 0.48
            AddBlock(data.rockLedges, x, y, z, 1.02, 0.58, 0.92,
                Pick(PALETTE.rock, index, islandIndex, 91), 0.11)
            if not pureTerrain and index % 2 == 0 then
                AddBlock(data.moss, x, y + 0.36, z, 0.88, 0.14, 0.78,
                    Pick(PALETTE.grass, index, islandIndex, 97), 0.045)
            end
        end
        for index = 1, 12 do
            local angle = TAU * index / 12 + 0.17 + islandIndex
            local radiusX = radiusX + 1.4 + (index % 3) * 0.55
            local radiusZ = radiusZ + 1.4 + (index % 3) * 0.55
            local size = 0.30 + (index % 3) * 0.12
            AddBlock(data.fragments,
                island.x + math.sin(angle) * radiusX, topY - 4.62 - (index % 5) * 0.66,
                island.z + math.cos(angle) * radiusZ,
                size, size * (1.1 + (index % 2) * 0.25), size,
                Pick(PALETTE.rock, index, islandIndex, 103), 0.07)
        end
    end
end

local function BuildBridges(data, layout)
    local byId = {}
    for _, island in ipairs(data.islands) do byId[island.id] = island end
    for bridgeIndex, bridge in ipairs(layout.BRIDGES or layout.bridges or {}) do
        local first, second = byId[bridge.from], byId[bridge.to]
        local metrics = layout.GetBridgeMetrics and layout:GetBridgeMetrics(bridge) or nil
        local dx, dz = second.x - first.x, second.z - first.z
        local distance = metrics and metrics.distance or math.sqrt(dx * dx + dz * dz)
        local ux, uz = metrics and metrics.ux or dx / distance, metrics and metrics.uz or dz / distance
        -- Render only the visible edge-to-edge span. The old centre-to-centre
        -- strip ran beneath both islands for dozens of metres, and its grass
        -- top was coplanar with the island top, producing severe z-fighting.
        local landingInset = 0.34
        local startDistance = metrics and metrics.startDistance
            or math.max(0, (first.radius or math.min(first.radiusX, first.radiusZ)) - landingInset)
        local endDistance = metrics and metrics.endDistance or math.min(distance,
            distance - (second.radius or math.min(second.radiusX, second.radiusZ)) + landingInset)
        local bridgeLength = math.max(0.01, endDistance - startDistance)
        local firstY, secondY = first.groundY or GROUND_Y, second.groundY or GROUND_Y
        local stepSpacing = math.max(2.10, tonumber(bridge.stepSpacing) or 2.58)
        local steps = math.max(1, math.ceil(bridgeLength / stepSpacing),
            math.ceil(math.abs(secondY - firstY) / math.max(0.18, bridge.maxStepHeight or 0.24)))
        local bridgeAngle = math.atan(ux, uz)
        local actualSpacing = bridgeLength / math.max(1, steps)
        local segmentLength = Clamp(actualSpacing * 0.82, 1.38, 2.72)
        local shattered = bridge.broken ~= false
        local curveDirection = bridgeIndex % 2 == 0 and -1 or 1
        local curve = shattered and math.min(0.34, (bridge.halfWidth or 1.31) * 0.16) or 0
        data.bridgeSpans[#data.bridgeSpans + 1] = {
            from = bridge.from, to = bridge.to,
            startDistance = startDistance, endDistance = endDistance,
            length = bridgeLength, steps = steps, startY = firstY, endY = secondY,
            broken = shattered, rotationY = bridgeAngle,
        }
        for index = 0, steps do
            local amount = index / steps
            local along = startDistance + bridgeLength * amount
            local lateral = math.sin(amount * math.pi) * curve * curveDirection
            local x = first.x + ux * along - uz * lateral
            local z = first.z + uz * along + ux * lateral
            local surfaceY = firstY + (secondY - firstY) * amount
            local broken = shattered and index > 1 and index < steps - 1
                and ((index + bridgeIndex * 2) % 6 == 0
                    or (steps > 12 and (index + bridgeIndex * 5) % 11 == 0))
            if not broken then
                local baseWidth = math.max(1.55, (bridge.halfWidth or 1.31) * 1.92)
                local width = baseWidth * (0.90 + Hash(index, bridgeIndex, 131) * 0.10)
                local slabLength = segmentLength * (0.88 + Hash(index, bridgeIndex, 137) * 0.12)
                -- Keep the landing a hair above the island plane so the short
                -- intentional edge overlap never shares an identical depth.
                -- The slab's long axis follows the bridge, avoiding the old
                -- diagonal checkerboard-road silhouette.
                AddBlock(data.bridgeGrass, x, surfaceY - 0.075, z,
                    width, 0.18, slabLength,
                    Pick(PALETTE.grass, index, bridgeIndex, 133), 0.045, bridgeAngle)
                AddBlock(data.bridgeSoil, x, surfaceY - 0.46, z,
                    width * 0.92, 0.72, slabLength * 0.94,
                    Pick(PALETTE.soil, index, bridgeIndex, 139), 0.10, bridgeAngle)
                AddBlock(data.bridgeRock, x, surfaceY - 1.17 - (index % 3) * 0.08, z,
                    width * (0.70 + Hash(index, bridgeIndex, 145) * 0.08),
                    1.05 + (index % 4) * 0.14,
                    slabLength * (0.72 + Hash(index, bridgeIndex, 147) * 0.09),
                    Pick(PALETTE.rock, index, bridgeIndex, 149), 0.12, bridgeAngle)
            else
                -- A fallen chunk below the gap makes the bridge look shattered
                -- while the logical walking ribbon remains continuous.
                AddBlock(data.bridgeFragments, x - uz * curveDirection * 0.54,
                    surfaceY - 2.42 - (index % 2) * 0.38, z + ux * curveDirection * 0.54,
                    0.72, 0.80, 1.02, Pick(PALETTE.rock, index, bridgeIndex, 157),
                    0.10, bridgeAngle + curveDirection * 0.22)
            end
        end
        -- A couple of off-axis remnants preserve the shattered floating-road
        -- silhouette without extending the walkable surface under the islands.
        local middle = startDistance + bridgeLength * 0.5
        for fragmentIndex = 1, 2 do
            local side = fragmentIndex == 1 and -1 or 1
            AddBlock(data.bridgeFragments,
                first.x + ux * (middle + side * 1.7) - uz * side * 0.72,
                (firstY + secondY) * 0.5 - 2.77 - fragmentIndex * 0.38,
                first.z + uz * (middle + side * 1.7) + ux * side * 0.72,
                0.58, 0.72, 0.62,
                Pick(PALETTE.rock, fragmentIndex, bridgeIndex, 163), 0.09,
                bridgeAngle + side * 0.34)
        end
    end
end

local function FindIsland(data, id)
    for _, island in ipairs(data.islands or {}) do
        if island.id == id then return island end
    end
    return nil
end

local function AddLandformBlock(data, kind, x, y, z, sx, sy, sz, color, bevel)
    AddBlock(data.terrainAccents, x, y, z, sx, sy, sz, color, bevel)
    local block = data.terrainAccents[#data.terrainAccents]
    block.landform = kind
    return block
end

-- Segmenting the geological masses avoids the single giant cuboid look while
-- keeping them engine-free and cheap enough to merge with the cliff geometry.
local function AddStratifiedPillar(data, kind, x, z, bottomY, topY, width, seed, leanX, leanZ)
    local totalHeight = math.max(0.5, topY - bottomY)
    local count = math.max(2, math.ceil(totalHeight / 3.4))
    leanX, leanZ = tonumber(leanX) or 0, tonumber(leanZ) or 0
    for index = 1, count do
        local amount = (index - 0.5) / count
        local height = totalHeight / count * 1.07
        local taper = 1 - amount * 0.20
        local offset = (index % 2 == 0 and 0.10 or -0.08) * width
        AddLandformBlock(data, kind,
            x + leanX * amount + offset,
            bottomY + totalHeight * amount,
            z + leanZ * amount - offset * 0.35,
            width * taper, height, width * (0.88 + (index % 3) * 0.035),
            Pick(PALETTE.rockLight, index, count, seed), math.min(0.30, width * 0.13))
    end
end

local function AddNaturalArch(data, kind, x, z, bottomY, topY, span, depth, axis, seed)
    local openingTop = bottomY + (topY - bottomY) * 0.68
    local columnWidth = math.max(1.5, span * 0.19)
    local halfSpan = span * 0.5 - columnWidth * 0.45
    if axis == "z" then
        AddStratifiedPillar(data, kind, x, z - halfSpan, bottomY, openingTop,
            columnWidth, seed, -0.18, 0.10)
        AddStratifiedPillar(data, kind, x, z + halfSpan, bottomY, openingTop,
            columnWidth, seed + 7, 0.16, -0.08)
        AddLandformBlock(data, kind, x, openingTop + (topY - openingTop) * 0.5, z,
            depth, topY - openingTop, span, Pick(PALETTE.rockLight, seed, 2, 391), 0.28)
    else
        AddStratifiedPillar(data, kind, x - halfSpan, z, bottomY, openingTop,
            columnWidth, seed, 0.12, -0.18)
        AddStratifiedPillar(data, kind, x + halfSpan, z, bottomY, openingTop,
            columnWidth, seed + 7, -0.10, 0.16)
        AddLandformBlock(data, kind, x, openingTop + (topY - openingTop) * 0.5, z,
            span, topY - openingTop, depth, Pick(PALETTE.rockLight, seed, 2, 397), 0.28)
    end
end

local function AddCliffRibs(data, kind, island, count, seed, innerAngle, spread)
    if not island then return end
    local radiusX, radiusZ = island.radiusX or island.radius, island.radiusZ or island.radius
    local topY = island.groundY - 1.0
    for index = 1, count do
        local amount = count == 1 and 0.5 or (index - 1) / (count - 1)
        local angle = innerAngle + (amount - 0.5) * spread
        local width = 1.45 + (index % 3) * 0.28
        local height = 4.8 + (index % 4) * 1.35
        local x = island.x + math.sin(angle) * radiusX * 0.79
        local z = island.z + math.cos(angle) * radiusZ * 0.79
        AddStratifiedPillar(data, kind, x, z, topY - height, topY,
            width, seed + index * 11, math.sin(angle) * 0.6, math.cos(angle) * 0.6)
    end
end

-- A stepped corkscrew of rounded stone masses gives the new vertical terrains
-- a readable giant-tree silhouette without introducing a literal prefab. The
-- gaps between segments keep the same light, toy-like language as the broken
-- walking slabs that spiral around it.
local function AddSpiralSpine(data, kind, x, z, bottomY, topY, radius, width,
        turns, count, seed, phase)
    local totalHeight = math.max(0.5, topY - bottomY)
    count = math.max(3, math.floor(tonumber(count) or 12))
    phase = tonumber(phase) or 0
    for index = 1, count do
        local amount = (index - 0.5) / count
        local angle = phase + amount * (tonumber(turns) or 1) * math.pi * 2
        local taper = 1 - amount * 0.26
        local segmentHeight = totalHeight / count * 1.16
        AddLandformBlock(data, kind,
            x + math.sin(angle) * radius * taper,
            bottomY + totalHeight * amount,
            z + math.cos(angle) * radius * taper,
            width * taper, segmentHeight, width * (0.88 + (index % 3) * 0.05) * taper,
            Pick(PALETTE.rockLight, index, count, seed), math.min(0.28, width * 0.12))
    end
end

-- These are terrain masses only: no trees, flowers, shrubs, water, furniture
-- or prefabs are emitted for the selectable fantasy terrains.
local function BuildTerrainFeatures(data, layout)
    if layout.id == "windstep-meadow" then
        AddCliffRibs(data, "wind-ring-rib", FindIsland(data, "west-arc"), 7, 311, math.pi * 0.5, 1.9)
        AddCliffRibs(data, "wind-ring-rib", FindIsland(data, "north-arc"), 5, 372, math.pi, 1.5)
        AddCliffRibs(data, "wind-ring-rib", FindIsland(data, "south-arc"), 5, 433, 0, 1.5)
        AddStratifiedPillar(data, "wind-monolith", 14, 5, -12.5, 3.8, 3.0, 479, 0.8, -0.4)
        AddStratifiedPillar(data, "wind-monolith", 25, 15, -15.0, -1.0, 2.4, 487, -0.4, 0.7)
    elseif layout.id == "cloudpine-spire" then
        -- A central, many-layered spine joins the authored terraces into one
        -- mountain silhouette. Two hollow rock arches mirror the reference.
        AddStratifiedPillar(data, "sky-spine", -8, -35, -19.0, 15.6, 6.6, 521, 1.1, -1.6)
        AddStratifiedPillar(data, "sky-spine", 4, -38, -15.0, 11.0, 5.2, 537, -0.9, -0.8)
        AddNaturalArch(data, "lower-arch", -10, -16, -5.0, 6.8, 14.5, 4.4, "x", 563)
        AddNaturalArch(data, "upper-arch", 6, -43, 2.0, 12.7, 12.0, 3.8, "z", 587)
        AddCliffRibs(data, "summit-rib", FindIsland(data, "summit-crown"), 5, 704, math.pi, 1.35)
    elseif layout.id == "moonbay-gardens" then
        AddCliffRibs(data, "west-moon-rib", FindIsland(data, "west-crescent"), 7, 872,
            math.pi * 0.5, 1.45)
        AddCliffRibs(data, "east-moon-rib", FindIsland(data, "east-crescent"), 7, 994,
            -math.pi * 0.5, 1.45)
        AddNaturalArch(data, "eclipse-arch", 0, -48, -7.0, 7.6, 15.0, 4.2, "x", 1116)
        AddStratifiedPillar(data, "moon-needle", -15, -52, -17.0, 5.0, 2.5, 1131, 0.4, -0.7)
        AddStratifiedPillar(data, "moon-needle", 15, -53, -18.5, 6.0, 2.7, 1147, -0.5, -0.6)
    elseif layout.id == "starfall-ring" then
        AddCliffRibs(data, "starfall-crater-rib", FindIsland(data, "crater-court"), 8, 1231, 0, 1.7)
        AddStratifiedPillar(data, "starfall-needle", -18, -37, -15.5, 5.0, 2.7, 1307, -0.5, -0.8)
        AddStratifiedPillar(data, "starfall-needle", 20, -34, -14.0, 6.5, 2.4, 1321, 0.6, -0.7)
    elseif layout.id == "twin-gate-highlands" then
        AddStratifiedPillar(data, "twin-gate-pillar", -18, -20, -21.0, 15.0, 5.3, 1611, -1.0, -0.6)
        AddStratifiedPillar(data, "twin-gate-pillar", 18, -20, -20.0, 17.4, 5.3, 1637, 1.0, -0.6)
        AddNaturalArch(data, "twin-gate-arch", 0, -28, 0.0, 15.8, 20.0, 5.2, "x", 1661)
    elseif layout.id == "cascade-terraces" then
        for index, island in ipairs(data.islands or {}) do
            if index <= 5 then
                AddCliffRibs(data, "cascade-rib", island, 4 + index % 3,
                    1991 + index * 61, index * 0.72, 1.25)
            end
        end
    elseif layout.id == "sky-whale-ridge" then
        AddCliffRibs(data, "whale-head-rib", FindIsland(data, "whale-head"), 7, 2431,
            math.pi * 0.5, 1.55)
        AddCliffRibs(data, "whale-spine-rib", FindIsland(data, "whale-spine"), 8, 2492,
            0, 1.75)
        AddStratifiedPillar(data, "whale-keel", 0, 4, -18.0, 1.8, 4.5, 2517, 0, 1.1)
    elseif layout.id == "world-tree-spiral" then
        -- A broad central core reads as the trunk while the offset segmented
        -- ridge and authored bridge chain wrap around it like a rising branch.
        AddStratifiedPillar(data, "world-tree-trunk", 0, 1, -31.0, 31.5,
            8.2, 2861, 0.7, -0.5)
        AddSpiralSpine(data, "world-tree-bark-spiral", 0, 1, -25.0, 32.5,
            5.8, 2.8, 1.55, 19, 2922, 0.35)
        AddCliffRibs(data, "world-tree-root-rib", FindIsland(data, "root-garden"),
            9, 2983, math.pi, 1.95)
        AddCliffRibs(data, "world-tree-crown-rib", FindIsland(data, "tree-crown"),
            7, 3044, 0, 1.65)
    elseif layout.id == "twin-vine-spiral" then
        -- Two opposite-phase spines make the two routes legible as paired vines
        -- before both paths meet at the high crown platform.
        AddSpiralSpine(data, "west-vine-spine", -2.4, 1, -25.0, 22.0,
            5.2, 3.0, 1.35, 17, 3411, 0.10)
        AddSpiralSpine(data, "east-vine-spine", 2.4, 1, -24.0, 24.0,
            5.2, 3.0, 1.35, 17, 3472, math.pi)
        AddCliffRibs(data, "twin-vine-root-rib", FindIsland(data, "vine-root"),
            8, 3533, math.pi, 1.85)
        AddCliffRibs(data, "twin-vine-crown-rib", FindIsland(data, "star-crown"),
            7, 3594, 0, 1.55)
    elseif layout.id ~= IslandLayout.TERRAIN_PRESET then
        -- Seeded user terrains still need a geological silhouette, but never
        -- receive authored props. A few deterministic cliff ribs echo each
        -- generated landmass without turning it into a decorated preset.
        for index, island in ipairs(data.islands or {}) do
            if index <= 5 then
                AddCliffRibs(data, "generated-cliff-rib", island,
                    3 + index % 3, 3011 + index * 67, index * 0.83, 1.18)
            end
        end
    end
end

local MID_CLOUD_PATTERN = {
    { 0, -0.65, 0, 4.8, 1.45, 2.5 }, { -3.7, -0.35, 0.15, 3.1, 1.65, 2.1 },
    { 3.8, -0.25, -0.1, 3.4, 1.75, 2.2 }, { -1.9, 0.45, 0.1, 2.7, 2.4, 1.9 },
    { 1.15, 0.70, -0.05, 3.0, 2.75, 2.0 }, { 3.0, 0.65, 0, 2.2, 2.1, 1.65 },
    { -0.2, 2.15, 0, 2.3, 2.7, 1.7 }, { -4.7, -0.1, 0.2, 2.0, 1.15, 1.55 },
    { 5.0, -0.05, -0.15, 2.1, 1.2, 1.6 },
}

local LOW_CLOUD_PATTERN = {
    { 0, 0, 0, 6.4, 1.25, 3.6 }, { -5.0, 0.18, 0.25, 4.2, 1.05, 3.0 },
    { 5.2, -0.10, -0.2, 4.6, 1.15, 3.2 }, { -2.2, 0.85, 0.05, 3.8, 1.55, 2.7 },
    { 2.5, 0.72, 0, 4.0, 1.48, 2.8 }, { 0.4, -0.55, 0.2, 4.8, 0.92, 3.1 },
}

local HORIZON_CLOUD_PATTERN = {
    { 0, -0.25, 0, 7.2, 1.9, 4.0 }, { -5.8, -0.15, 0.3, 4.6, 1.5, 3.3 },
    { 6.0, -0.10, -0.2, 5.0, 1.6, 3.5 }, { -2.7, 1.0, 0.1, 4.2, 2.4, 3.0 },
    { 2.4, 1.35, -0.1, 4.5, 2.8, 3.1 }, { 0.3, 2.9, 0, 3.5, 3.4, 2.5 },
    { 7.9, 0.65, 0.1, 3.2, 2.0, 2.4 },
}

local function AddCloudBank(target, bank, pattern, bottom, top)
    local x, y, z, scale = bank[1], bank[2], bank[3], bank[4]
    local angle = math.atan(x, z)
    local c, s = math.cos(angle), math.sin(angle)
    for partIndex, part in ipairs(pattern) do
        local dx, dz = part[1] * c + part[3] * s, -part[1] * s + part[3] * c
        AddLobe(target, x + dx * scale, y + part[2] * scale, z + dz * scale,
            part[4] * scale, part[5] * scale, part[6] * scale,
            partIndex % 3 == 0 and CLOUD.cool or bottom,
            partIndex % 4 == 0 and CLOUD.warm or top)
    end
end

local function BuildClouds(data, layout)
    -- Detached cloud banks follow the real island centres and radii but leave
    -- a clean band of sky between cloud and stone. They frame the islands
    -- without looking glued to the underside.
    for islandIndex, island in ipairs(data.islands) do
        for bank = 1, 10 do
            local angle = TAU * bank / 10 + islandIndex * 0.31
            local radius = island.radius * (1.44 + (bank % 3) * 0.05)
            local x, z = island.x + math.sin(angle) * radius, island.z + math.cos(angle) * radius
            local islandScale = Clamp(island.radius / 14.5, 1.15, 2.0)
            local scale = (0.72 + (bank % 3) * 0.10) * islandScale
            local heightOffset = (island.groundY or GROUND_Y) - GROUND_Y
            AddLobe(data.cloudsNear, x, -9.0 + heightOffset * 0.35 - islandScale * 0.55 + (bank % 3) * 0.55, z,
                3.2 * scale, 1.4 * scale, 2.5 * scale, CLOUD.shadow, CLOUD.light)
            AddLobe(data.cloudsNear, x + math.sin(angle + 1.2) * 1.8 * islandScale,
                -8.2 + heightOffset * 0.35 - islandScale * 0.42, z + math.cos(angle + 1.2) * 1.8 * islandScale,
                2.1 * scale, 1.15 * scale, 1.8 * scale, CLOUD.cool, CLOUD.warm)
            AddLobe(data.cloudsNear, x - math.sin(angle) * 1.4 * islandScale,
                -10.4 + heightOffset * 0.35 - islandScale * 0.58, z - math.cos(angle) * 1.4 * islandScale,
                2.4 * scale, 1.0 * scale, 2.0 * scale, CLOUD.shadow, CLOUD.soft)
        end
    end

    -- Each playable island contributes three low cloud banks beyond its edge;
    -- one extra bank closes the lower foreground into a continuous cloud sea.
    local lowBanks = {}
    for islandIndex, island in ipairs(data.islands) do
        for localIndex = 1, 3 do
            local angle = islandIndex * 0.71 + localIndex * TAU / 3
            local radius = island.radius * 1.72
            lowBanks[#lowBanks + 1] = {
                island.x + math.sin(angle) * radius,
                -7.2 + islandIndex * 0.55 - localIndex * 0.28,
                island.z + math.cos(angle) * radius,
                0.82 + island.radius / 58 + localIndex * 0.045,
            }
        end
    end
    local overview = layout:Overview()
    lowBanks[#lowBanks + 1] = { overview.x, -10.5, overview.z - overview.radius * 0.62, 1.32 }
    for _, bank in ipairs(lowBanks) do
        AddCloudBank(data.cloudsLow, bank, LOW_CLOUD_PATTERN, CLOUD.shadow, CLOUD.soft)
    end

    -- Mid towers form an asymmetric ring derived from the archipelago overview
    -- radius, so changing island size keeps background clearance intact.
    for index = 1, 8 do
        local angle = index * TAU / 8 + 0.24
        local radius = overview.radius * (0.68 + (index % 3) * 0.045)
        AddCloudBank(data.cloudsMid, {
            overview.x + math.sin(angle) * radius,
            7 + (index % 4) * 6.2,
            overview.z + math.cos(angle) * radius,
            0.82 + (index % 4) * 0.16,
        }, MID_CLOUD_PATTERN, CLOUD.cool, CLOUD.light)
    end

    -- High wisps use the same overview anchor but alternate radius and height,
    -- producing near/far parallax instead of a flat fixed-coordinate ring.
    for index = 1, 10 do
        local angle = index * TAU / 10 - 0.17
        local radius = overview.radius * (0.66 + (index % 4) * 0.12)
        local wisp = {
            overview.x + math.sin(angle) * radius,
            25 + (index % 5) * 7,
            overview.z + math.cos(angle) * radius,
            0.34 + (index % 4) * 0.075,
        }
        for part = 1, 4 do
            AddLobe(data.cloudsHigh, wisp[1] + (part - 2.5) * 2.2 * wisp[4],
                wisp[2] + math.sin(part * 1.2) * 0.5, wisp[3],
                (2.1 + (part % 2) * 0.6) * wisp[4],
                (1.0 + (part % 3) * 0.35) * wisp[4], 1.3 * wisp[4], CLOUD.cool, CLOUD.light)
        end
    end


    -- Horizon banks remain outside every playable and near-background island.
    for index = 1, 10 do
        local angle = index * TAU / 10 + 0.08
        local radius = overview.radius * (1.62 + (index % 3) * 0.12)
        AddCloudBank(data.cloudsFar, {
            overview.x + math.sin(angle) * radius,
            -2 + (index % 6) * 8,
            overview.z + math.cos(angle) * radius,
            1.08 + (index % 4) * 0.13,
        }, HORIZON_CLOUD_PATTERN, CLOUD.shadow, CLOUD.soft)
    end

    Append(data.clouds, data.cloudsNear)
    Append(data.clouds, data.cloudsLow)
    Append(data.clouds, data.cloudsMid)
    Append(data.clouds, data.cloudsHigh)
    Append(data.clouds, data.cloudsFar)
end

local DISTANT_ACCENT = {
    plaster = 0xe9ddc6, plasterShadow = 0xc9b594, roof = 0xbd6858, roofDark = 0x865049,
    wood = 0x80583f, darkWood = 0x563f36, stone = 0x8d9693, paleStone = 0xb7b8ab,
    water = 0x66bad1, snow = 0xe9f0e8, sand = 0xd0ae72, gold = 0xd5b45b,
    flower = 0xd98289, flowerBlue = 0x7aa6c2, crystal = 0x7fd2cf, crystalBlue = 0x78b9d2,
    leaf = 0x5e9562, pine = 0x3f6e62, leafLight = 0x8bb360, mushroom = 0xd36f62,
}

local function AddDistantTree(data, spec, dx, dz, height, style)
    local scale = spec.scale
    local x, z = spec.x + dx * scale, spec.z + dz * scale
    local trunkHeight = (height or 2.8) * scale
    AddBlock(data.distantStructures, x, spec.y + trunkHeight * 0.5, z,
        0.30 * scale, trunkHeight, 0.30 * scale, DISTANT_ACCENT.wood, 0.06 * scale)

    local lobeCount = spec.tier == "near" and 3 or spec.tier == "mid" and 2 or 1
    if style == "pine" then
        lobeCount = math.min(lobeCount, 2)
        for level = 1, lobeCount do
            local amount = (level - 1) / math.max(1, lobeCount - 1)
            AddLobe(data.distantFoliage, x, spec.y + trunkHeight * (0.58 + amount * 0.28), z,
                (1.05 - amount * 0.30) * scale, (0.86 - amount * 0.12) * scale,
                (1.02 - amount * 0.27) * scale, DISTANT_ACCENT.pine, DISTANT_ACCENT.leaf)
        end
    elseif style == "palm" then
        for lobe = 1, math.min(3, lobeCount + 1) do
            local angle = lobe * TAU / 3
            AddLobe(data.distantFoliage,
                x + math.sin(angle) * 0.38 * scale, spec.y + trunkHeight * 0.96,
                z + math.cos(angle) * 0.38 * scale,
                0.92 * scale, 0.34 * scale, 0.48 * scale,
                DISTANT_ACCENT.leaf, DISTANT_ACCENT.leafLight)
        end
    else
        for lobe = 1, lobeCount do
            local angle = lobe * 2.4 + dx * 0.17
            local offset = lobe == 1 and 0 or 0.42 * scale
            AddLobe(data.distantFoliage,
                x + math.sin(angle) * offset, spec.y + trunkHeight * (0.78 + (lobe % 2) * 0.10),
                z + math.cos(angle) * offset,
                (0.88 + (lobe % 2) * 0.16) * scale, 0.78 * scale, 0.84 * scale,
                DISTANT_ACCENT.leaf, DISTANT_ACCENT.leafLight)
        end
    end
end

local function AddDistantCottage(data, spec, dx, dz, size, roofColor)
    local s = spec.scale * (size or 1)
    local x, z = spec.x + dx * spec.scale, spec.z + dz * spec.scale
    AddBlock(data.distantStructures, x, spec.y + 1.05 * s, z,
        3.05 * s, 2.10 * s, 2.45 * s, DISTANT_ACCENT.plaster, 0.15 * s)
    -- A three-step roof reads as a soft pitched roof from every orbit angle.
    AddBlock(data.distantStructures, x, spec.y + 2.22 * s, z,
        3.55 * s, 0.42 * s, 2.95 * s, roofColor or DISTANT_ACCENT.roof, 0.12 * s)
    AddBlock(data.distantStructures, x, spec.y + 2.56 * s, z,
        2.75 * s, 0.38 * s, 2.70 * s, roofColor or DISTANT_ACCENT.roof, 0.11 * s)
    AddBlock(data.distantStructures, x, spec.y + 2.87 * s, z,
        1.85 * s, 0.34 * s, 2.42 * s, roofColor or DISTANT_ACCENT.roofDark, 0.10 * s)
    AddBlock(data.distantStructures, x, spec.y + 0.70 * s, z - 1.27 * s,
        0.58 * s, 1.35 * s, 0.16 * s, DISTANT_ACCENT.darkWood, 0.04 * s)
    AddBlock(data.distantStructures, x + 0.88 * s, spec.y + 1.26 * s, z - 1.28 * s,
        0.58 * s, 0.58 * s, 0.14 * s, DISTANT_ACCENT.flowerBlue, 0.04 * s)
    AddBlock(data.distantStructures, x + 1.05 * s, spec.y + 3.15 * s, z + 0.48 * s,
        0.42 * s, 1.20 * s, 0.48 * s, DISTANT_ACCENT.stone, 0.07 * s)
end

local function AddDistantGazebo(data, spec)
    local s = spec.scale
    for _, offset in ipairs({ { -1.25, -1.0 }, { 1.25, -1.0 }, { -1.25, 1.0 }, { 1.25, 1.0 } }) do
        AddBlock(data.distantStructures, spec.x + offset[1] * s, spec.y + 1.20 * s,
            spec.z + offset[2] * s, 0.25 * s, 2.40 * s, 0.25 * s,
            DISTANT_ACCENT.plasterShadow, 0.05 * s)
    end
    AddBlock(data.distantStructures, spec.x, spec.y + 2.55 * s, spec.z,
        3.45 * s, 0.42 * s, 3.05 * s, DISTANT_ACCENT.roof, 0.12 * s)
    AddBlock(data.distantStructures, spec.x, spec.y + 2.90 * s, spec.z,
        2.45 * s, 0.34 * s, 2.15 * s, DISTANT_ACCENT.roofDark, 0.10 * s)
end

local function AddDistantWildGrass(data, spec, count, radius)
    local s = spec.scale
    for index = 1, count do
        local angle = index * 2.31 + spec.x * 0.013
        local distance = radius * (0.28 + (index % 5) * 0.14)
        local height = (0.34 + (index % 3) * 0.13) * s
        AddBlock(data.distantStructures,
            spec.x + math.sin(angle) * distance * s, spec.y + height * 0.5,
            spec.z + math.cos(angle) * distance * 0.82 * s,
            0.12 * s, height, 0.12 * s,
            index % 3 == 0 and DISTANT_ACCENT.leafLight or DISTANT_ACCENT.pine, 0.025 * s)
    end
end

local function AddDistantLandmark(data, spec)
    local s, x, y, z = spec.scale, spec.x, spec.y, spec.z
    if spec.theme == "forgotten_castle" then
        AddBlock(data.distantStructures, x, y + 2.15 * s, z,
            6.3 * s, 4.3 * s, 4.8 * s, DISTANT_ACCENT.plasterShadow, 0.28 * s)
        AddBlock(data.distantStructures, x - 4.0 * s, y + 2.55 * s, z + 0.25 * s,
            2.45 * s, 5.10 * s, 2.45 * s, DISTANT_ACCENT.stone, 0.24 * s)
        AddBlock(data.distantStructures, x + 4.0 * s, y + 2.15 * s, z + 0.25 * s,
            2.45 * s, 4.30 * s, 2.45 * s, DISTANT_ACCENT.paleStone, 0.24 * s)
        AddBlock(data.distantStructures, x, y + 1.18 * s, z + 3.15 * s,
            10.0 * s, 2.36 * s, 0.78 * s, DISTANT_ACCENT.stone, 0.12 * s)
        AddBlock(data.distantStructures, x, y + 1.12 * s, z - 2.45 * s,
            1.05 * s, 2.24 * s, 0.18 * s, DISTANT_ACCENT.darkWood, 0.04 * s)
        for index = -3, 3 do
            if index ~= 1 then
                AddBlock(data.distantStructures, x + index * 0.85 * s, y + 4.68 * s, z - 1.95 * s,
                    0.55 * s, 0.72 * s, 0.62 * s,
                    index % 2 == 0 and DISTANT_ACCENT.paleStone or DISTANT_ACCENT.stone, 0.08 * s)
            end
        end
        AddBlock(data.distantStructures, x - 1.2 * s, y + 4.35 * s, z + 0.55 * s,
            2.6 * s, 0.16 * s, 1.3 * s, DISTANT_ACCENT.pine, 0.04 * s)
        AddDistantWildGrass(data, spec, 20, 5.2)
        AddDistantTree(data, spec, -5.0, -3.2, 3.0, "broad")
        AddDistantTree(data, spec, 5.2, 2.7, 2.7, "broad")
    elseif spec.theme == "meadow_village" then
        AddDistantCottage(data, spec, -2.4, -0.6, 0.92, DISTANT_ACCENT.roof)
        AddDistantCottage(data, spec, 2.3, 1.0, 0.74, DISTANT_ACCENT.roofDark)
        for _, tree in ipairs({ { -4.1, 2.6 }, { 4.2, -2.2 }, { -1.0, 3.6 }, { 3.8, 3.2 } }) do
            AddDistantTree(data, spec, tree[1], tree[2], 2.8, "broad")
        end
    elseif spec.theme == "pine_forest" then
        for index = 1, 10 do
            local angle = index * 2.17
            local radius = 1.0 + (index % 4) * 1.25
            AddDistantTree(data, spec, math.sin(angle) * radius, math.cos(angle) * radius,
                2.7 + (index % 3) * 0.55, "pine")
        end
        AddDistantCottage(data, spec, 0.7, -1.0, 0.64, DISTANT_ACCENT.roofDark)
    elseif spec.theme == "flower_garden" then
        AddDistantGazebo(data, spec)
        for _, tree in ipairs({ { -3.7, -2.8 }, { 3.8, -2.4 }, { -3.2, 2.8 }, { 3.3, 3.0 } }) do
            AddDistantTree(data, spec, tree[1], tree[2], 2.5, "broad")
        end
        for flower = 1, 12 do
            local angle = flower * TAU / 12
            AddBlock(data.distantStructures, x + math.sin(angle) * 3.1 * s, y + 0.16 * s,
                z + math.cos(angle) * 2.4 * s, 0.22 * s, 0.32 * s, 0.22 * s,
                flower % 2 == 0 and DISTANT_ACCENT.flower or DISTANT_ACCENT.gold, 0.04 * s)
        end
    elseif spec.theme == "ancient_ruins" or spec.theme == "sky_ruins" then
        local height = spec.theme == "ancient_ruins" and 4.4 or 3.4
        for _, pillar in ipairs({ { -2.2, -1.8, 1.0 }, { 2.2, -1.8, 0.72 },
                { -2.2, 1.8, 0.68 }, { 2.2, 1.8, 0.92 } }) do
            AddBlock(data.distantStructures, x + pillar[1] * s, y + height * pillar[3] * 0.5 * s,
                z + pillar[2] * s, 0.68 * s, height * pillar[3] * s, 0.68 * s,
                DISTANT_ACCENT.paleStone, 0.10 * s)
        end
        AddBlock(data.distantStructures, x, y + 3.72 * s, z - 1.8 * s,
            5.0 * s, 0.66 * s, 0.72 * s, DISTANT_ACCENT.stone, 0.11 * s)
        AddBlock(data.distantStructures, x - 0.65 * s, y + 0.34 * s, z,
            4.5 * s, 0.68 * s, 3.6 * s, DISTANT_ACCENT.stone, 0.10 * s)
        if spec.tier == "near" then
            AddDistantTree(data, spec, -3.7, 3.1, 2.7, "broad")
            AddDistantTree(data, spec, 3.4, 3.3, 2.9, "broad")
        end
        AddDistantWildGrass(data, spec, spec.tier == "near" and 16 or 7, 4.4)
    elseif spec.theme == "snow_peak" or spec.theme == "frost_peak" then
        AddBlock(data.distantStructures, x, y + 1.5 * s, z, 5.4 * s, 3.0 * s, 4.8 * s,
            DISTANT_ACCENT.stone, 0.34 * s)
        AddBlock(data.distantStructures, x - 0.5 * s, y + 3.45 * s, z + 0.15 * s,
            3.5 * s, 1.45 * s, 3.1 * s, DISTANT_ACCENT.paleStone, 0.28 * s)
        AddBlock(data.distantStructures, x - 0.6 * s, y + 4.30 * s, z + 0.08 * s,
            2.45 * s, 0.40 * s, 2.18 * s, DISTANT_ACCENT.snow, 0.10 * s)
        local treeCount = spec.tier == "mid" and 6 or 2
        for tree = 1, treeCount do
            local angle = tree * 2.1
            AddDistantTree(data, spec, math.sin(angle) * 4.0, math.cos(angle) * 3.4,
                2.2 + (tree % 2) * 0.4, "pine")
        end
    elseif spec.theme == "waterfall" then
        AddBlock(data.distantStructures, x + 2.2 * s, y + 1.25 * s, z,
            4.6 * s, 2.5 * s, 4.0 * s, DISTANT_ACCENT.stone, 0.28 * s)
        AddBlock(data.distantStructures, x + 4.25 * s, y - 0.25 * s, z - 0.2 * s,
            0.68 * s, 4.8 * s, 2.3 * s, DISTANT_ACCENT.water, 0.09 * s)
        AddBlock(data.distantStructures, x + 3.6 * s, y + 0.06 * s, z - 0.2 * s,
            2.5 * s, 0.22 * s, 3.0 * s, DISTANT_ACCENT.water, 0.06 * s)
        for _, tree in ipairs({ { -3.2, -2.7 }, { -2.5, 2.9 }, { 0.1, 3.6 }, { 0.0, -3.4 } }) do
            AddDistantTree(data, spec, tree[1], tree[2], 2.7, "broad")
        end
    elseif spec.theme == "orchard" then
        for row = -1, 1 do
            for column = -1, 1 do
                if not (row == 0 and column == 0) then
                    AddDistantTree(data, spec, column * 2.3, row * 2.1, 2.35, "broad")
                end
            end
        end
        AddDistantCottage(data, spec, 0, 0.1, 0.52, DISTANT_ACCENT.roof)
    elseif spec.theme == "crystal_grove" then
        for crystal = 1, 7 do
            local angle = crystal * 2.28
            local radius = 1.1 + crystal % 3 * 1.05
            local height = 1.7 + crystal % 4 * 0.75
            AddBlock(data.distantStructures, x + math.sin(angle) * radius * s, y + height * 0.5 * s,
                z + math.cos(angle) * radius * s, (0.45 + crystal % 2 * 0.16) * s,
                height * s, (0.45 + (crystal + 1) % 2 * 0.14) * s,
                crystal % 2 == 0 and DISTANT_ACCENT.crystal or DISTANT_ACCENT.crystalBlue, 0.12 * s)
        end
        for shrub = 1, 4 do
            local angle = shrub * TAU / 4 + 0.4
            AddLobe(data.distantFoliage, x + math.sin(angle) * 3.7 * s, y + 0.46 * s,
                z + math.cos(angle) * 3.1 * s, 0.74 * s, 0.50 * s, 0.68 * s,
                DISTANT_ACCENT.pine, DISTANT_ACCENT.crystal)
        end
    elseif spec.theme == "windmill" then
        AddDistantCottage(data, spec, -2.8, 1.7, 0.56, DISTANT_ACCENT.roof)
        AddBlock(data.distantStructures, x + 1.4 * s, y + 2.15 * s, z,
            2.15 * s, 4.30 * s, 2.15 * s, DISTANT_ACCENT.plasterShadow, 0.20 * s)
        AddBlock(data.distantStructures, x + 1.4 * s, y + 4.52 * s, z,
            2.65 * s, 0.52 * s, 2.55 * s, DISTANT_ACCENT.roofDark, 0.12 * s)
        AddBlock(data.distantStructures, x + 1.4 * s, y + 3.35 * s, z - 1.18 * s,
            5.3 * s, 0.26 * s, 0.22 * s, DISTANT_ACCENT.darkWood, 0.04 * s)
        AddBlock(data.distantStructures, x + 1.4 * s, y + 3.35 * s, z - 1.20 * s,
            0.26 * s, 5.3 * s, 0.22 * s, DISTANT_ACCENT.darkWood, 0.04 * s)
        for _, tree in ipairs({ { -4.1, -2.8 }, { -2.7, 3.5 }, { 4.5, 2.5 } }) do
            AddDistantTree(data, spec, tree[1], tree[2], 2.5, "broad")
        end
    elseif spec.theme == "sun_desert" then
        AddBlock(data.distantStructures, x, y + 1.2 * s, z, 4.8 * s, 2.4 * s, 3.7 * s,
            DISTANT_ACCENT.sand, 0.22 * s)
        AddBlock(data.distantStructures, x, y + 2.68 * s, z, 3.2 * s, 0.58 * s, 2.8 * s,
            DISTANT_ACCENT.gold, 0.12 * s)
        AddBlock(data.distantStructures, x - 1.55 * s, y + 3.9 * s, z + 0.9 * s,
            0.65 * s, 3.2 * s, 0.65 * s, DISTANT_ACCENT.paleStone, 0.10 * s)
        AddBlock(data.distantStructures, x + 1.55 * s, y + 3.9 * s, z + 0.9 * s,
            0.65 * s, 3.2 * s, 0.65 * s, DISTANT_ACCENT.paleStone, 0.10 * s)
        AddDistantTree(data, spec, -3.7, -2.3, 3.1, "palm")
        AddDistantTree(data, spec, 3.8, 2.5, 3.0, "palm")
    elseif spec.theme == "lighthouse" then
        AddBlock(data.distantStructures, x, y + 2.25 * s, z,
            1.75 * s, 4.5 * s, 1.75 * s, DISTANT_ACCENT.plaster, 0.20 * s)
        AddBlock(data.distantStructures, x, y + 4.55 * s, z,
            2.35 * s, 0.42 * s, 2.35 * s, DISTANT_ACCENT.roof, 0.10 * s)
        AddBlock(data.distantStructures, x, y + 4.92 * s, z,
            1.15 * s, 0.62 * s, 1.15 * s, DISTANT_ACCENT.gold, 0.12 * s)
        AddBlock(data.distantStructures, x, y + 5.35 * s, z,
            1.75 * s, 0.32 * s, 1.75 * s, DISTANT_ACCENT.roofDark, 0.09 * s)
        AddDistantTree(data, spec, -2.8, 1.5, 2.4, "pine")
        AddDistantTree(data, spec, 2.8, 1.2, 2.2, "pine")
    elseif spec.theme == "mushroom_grove" then
        for mushroom = 1, 5 do
            local angle = mushroom * 2.05
            local radius = 0.8 + mushroom % 3 * 1.25
            local height = 1.5 + mushroom % 2 * 0.7
            local mx, mz = x + math.sin(angle) * radius * s, z + math.cos(angle) * radius * s
            AddBlock(data.distantStructures, mx, y + height * 0.5 * s, mz,
                0.42 * s, height * s, 0.42 * s, DISTANT_ACCENT.plaster, 0.08 * s)
            AddLobe(data.distantFoliage, mx, y + height * s, mz,
                1.15 * s, 0.42 * s, 1.05 * s, DISTANT_ACCENT.roofDark, DISTANT_ACCENT.mushroom)
        end
    elseif spec.theme == "cliff_forest" then
        for tree = 1, 6 do
            local angle = tree * 2.24
            local radius = 1.0 + tree % 3 * 1.3
            AddDistantTree(data, spec, math.sin(angle) * radius, math.cos(angle) * radius,
                2.6 + tree % 2 * 0.5, "pine")
        end
    elseif spec.theme == "hamlet" then
        AddDistantCottage(data, spec, -1.5, 0, 0.65, DISTANT_ACCENT.roof)
        AddDistantCottage(data, spec, 1.6, 0.8, 0.54, DISTANT_ACCENT.roofDark)
        AddDistantTree(data, spec, 0, -2.5, 2.3, "broad")
    elseif spec.theme == "fallen_rampart" then
        AddBlock(data.distantStructures, x - 0.9 * s, y + 1.35 * s, z,
            5.8 * s, 2.70 * s, 0.82 * s, DISTANT_ACCENT.stone, 0.13 * s)
        AddBlock(data.distantStructures, x + 2.65 * s, y + 1.85 * s, z + 0.1 * s,
            1.25 * s, 3.70 * s, 1.30 * s, DISTANT_ACCENT.paleStone, 0.14 * s)
        AddBlock(data.distantStructures, x - 3.15 * s, y + 0.62 * s, z - 0.35 * s,
            1.35 * s, 1.24 * s, 1.15 * s, DISTANT_ACCENT.plasterShadow, 0.12 * s)
        for index = 1, 3 do
            AddBlock(data.distantStructures, x + (index - 2) * 1.45 * s, y + 2.96 * s, z,
                0.68 * s, 0.55 * s, 0.86 * s, DISTANT_ACCENT.stone, 0.08 * s)
        end
        AddDistantWildGrass(data, spec, 8, 3.8)
    else
        -- Horizon silhouettes keep one unmistakable landmark without spending
        -- geometry on details that are smaller than a screen pixel.
        AddBlock(data.distantStructures, x, y + 1.5 * s, z,
            2.2 * s, 3.0 * s, 2.2 * s, DISTANT_ACCENT.paleStone, 0.16 * s)
        AddBlock(data.distantStructures, x, y + 3.15 * s, z,
            3.0 * s, 0.42 * s, 2.8 * s, DISTANT_ACCENT.roof, 0.10 * s)
        AddDistantTree(data, spec, -2.2, 0.8, 2.3, "pine")
    end
end

local function BuildDistantIslands(data, terrainOnly)
    -- Four deliberately irregular depth bands contain large themed islands,
    -- medium story vignettes and tiny horizon landmarks. They frame rather
    -- than overlap the enlarged playable archipelago.
    local silhouettes = {
        { x = -96, z = -61, y = 8, scale = 1.85, tier = "near", theme = "forgotten_castle", pieces = 17, sizeClass = "large" },
        { x = 104, z = -68, y = 15, scale = 1.66, tier = "near", theme = "pine_forest", pieces = 16, sizeClass = "large" },
        { x = -108, z = 96, y = -5, scale = 1.42, tier = "near", theme = "flower_garden", pieces = 14, sizeClass = "medium" },
        { x = 111, z = 100, y = 22, scale = 1.55, tier = "near", theme = "ancient_ruins", pieces = 15, sizeClass = "large" },
        { x = -158, z = -72, y = 31, scale = 1.18, tier = "mid", theme = "snow_peak", pieces = 12, sizeClass = "medium" },
        { x = 163, z = -58, y = -8, scale = 1.14, tier = "mid", theme = "waterfall", pieces = 12, sizeClass = "medium" },
        { x = -153, z = 132, y = 18, scale = 0.98, tier = "mid", theme = "orchard", pieces = 11, sizeClass = "medium" },
        { x = 157, z = 135, y = 38, scale = 1.04, tier = "mid", theme = "crystal_grove", pieces = 11, sizeClass = "medium" },
        { x = -34, z = 184, y = 10, scale = 1.24, tier = "mid", theme = "windmill", pieces = 13, sizeClass = "large" },
        { x = 40, z = -190, y = 27, scale = 0.88, tier = "mid", theme = "sun_desert", pieces = 9, sizeClass = "small" },
        { x = -220, z = -96, y = 35, scale = 0.72, tier = "far", theme = "lighthouse", pieces = 9, sizeClass = "medium" },
        { x = 226, z = -74, y = 8, scale = 0.66, tier = "far", theme = "mushroom_grove", pieces = 8, sizeClass = "small" },
        { x = -213, z = 170, y = 20, scale = 0.74, tier = "far", theme = "cliff_forest", pieces = 10, sizeClass = "medium" },
        { x = 212, z = 174, y = 43, scale = 0.58, tier = "far", theme = "sky_ruins", pieces = 8, sizeClass = "small" },
        { x = 12, z = 244, y = 12, scale = 0.62, tier = "far", theme = "frost_peak", pieces = 9, sizeClass = "small" },
        { x = -28, z = -250, y = 39, scale = 0.54, tier = "far", theme = "fallen_rampart", pieces = 8, sizeClass = "small" },
        { x = -280, z = -90, y = 48, scale = 0.34, tier = "horizon", theme = "spire", pieces = 7, sizeClass = "small" },
        { x = 288, z = 60, y = 18, scale = 0.38, tier = "horizon", theme = "watchtower", pieces = 7, sizeClass = "small" },
        { x = -218, z = 218, y = 34, scale = 0.29, tier = "horizon", theme = "chapel", pieces = 7, sizeClass = "tiny" },
        { x = 180, z = 250, y = 54, scale = 0.25, tier = "horizon", theme = "spire", pieces = 6, sizeClass = "tiny" },
        { x = 10, z = -306, y = 24, scale = 0.31, tier = "horizon", theme = "watchtower", pieces = 7, sizeClass = "tiny" },
    }
    for islandIndex, spec in ipairs(silhouettes) do
        local colors = DISTANCE[spec.tier]
        local grassPalette = colors.grass
        if spec.theme == "sun_desert" then grassPalette = { 0xc8aa70, 0xd0b47b, 0xb99a66 }
        elseif spec.theme == "snow_peak" or spec.theme == "frost_peak" then
            grassPalette = { 0xcddbd6, 0xdce5df, 0xb8cbc5 }
        elseif spec.theme == "pine_forest" or spec.theme == "cliff_forest" then
            grassPalette = { colors.grass[1], 0x587a63, 0x66856b }
        elseif spec.theme == "flower_garden" or spec.theme == "orchard" then
            grassPalette = { 0x7fa65d, 0x8db366, 0x71975a }
        end

        local grassStart, soilStart, rockStart = #data.distantGrass, #data.distantSoil, #data.distantRock
        local structureStart, foliageStart = #data.distantStructures, #data.distantFoliage
        local firstRing = math.max(5, math.floor((spec.pieces - 1) * 0.48))
        for piece = 0, spec.pieces - 1 do
            local ring = piece == 0 and 0 or piece <= firstRing and 1 or 2
            local ringIndex = ring == 1 and piece or piece - firstRing
            local ringCount = ring == 1 and firstRing or math.max(1, spec.pieces - 1 - firstRing)
            local angle = islandIndex * 0.37 + ringIndex * TAU / ringCount + ring * 0.19
            local radial = ring == 0 and 0 or (ring == 1 and 2.45 or 4.35) * spec.scale
            radial = radial * (0.92 + Hash(piece, islandIndex, 197) * 0.17)
            local ox = math.sin(angle) * radial
            local oz = math.cos(angle) * radial * (0.76 + (islandIndex % 3) * 0.075)
            local width = (3.15 + Hash(piece, islandIndex, 201) * 0.74) * spec.scale
            local depth = (2.78 + Hash(islandIndex, piece, 207) * 0.68) * spec.scale
            AddBlock(data.distantGrass, spec.x + ox, spec.y - 0.14 * spec.scale, spec.z + oz,
                width, 0.28 * spec.scale, depth, Pick(grassPalette, islandIndex, piece, 211), 0.10 * spec.scale)
            AddBlock(data.distantSoil, spec.x + ox * 0.95, spec.y - 0.76 * spec.scale, spec.z + oz * 0.95,
                width * 0.91, 1.18 * spec.scale, depth * 0.91,
                Pick(colors.soil, islandIndex, piece, 223), 0.14 * spec.scale)
            AddBlock(data.distantRock, spec.x + ox * 0.78, spec.y - 2.02 * spec.scale, spec.z + oz * 0.78,
                width * 0.79, (2.30 + piece % 3 * 0.30) * spec.scale, depth * 0.77,
                Pick(colors.rock, islandIndex, piece, 229), 0.16 * spec.scale)
            if ring ~= 2 or piece % 2 == 0 then
                AddBlock(data.distantRock, spec.x + ox * 0.54, spec.y - 4.10 * spec.scale, spec.z + oz * 0.54,
                    width * 0.61, (2.65 + piece % 3 * 0.38) * spec.scale, depth * 0.59,
                    Pick(colors.rock, piece, islandIndex, 233), 0.14 * spec.scale)
            end
        end
        for tip = 1, 3 do
            local angle = islandIndex * 0.71 + tip * 2.0
            AddBlock(data.distantRock,
                spec.x + math.sin(angle) * 0.82 * spec.scale,
                spec.y - (6.15 + tip * 0.52) * spec.scale,
                spec.z + math.cos(angle) * 0.72 * spec.scale,
                (1.70 - tip * 0.15) * spec.scale, (2.80 - tip * 0.20) * spec.scale,
                (1.55 - tip * 0.13) * spec.scale,
                Pick(colors.rock, islandIndex, tip, 241), 0.13 * spec.scale)
        end

        if not terrainOnly then AddDistantLandmark(data, spec) end
        data.distantIslands[#data.distantIslands + 1] = {
            x = spec.x, y = spec.y, z = spec.z, scale = spec.scale, tier = spec.tier,
            theme = spec.theme, sizeClass = spec.sizeClass, pieceCount = spec.pieces,
            distance = math.sqrt(spec.x * spec.x + spec.z * spec.z),
            radius = 6.2 * spec.scale,
            grassCount = #data.distantGrass - grassStart,
            soilCount = #data.distantSoil - soilStart,
            rockCount = #data.distantRock - rockStart,
            detailCount = #data.distantStructures - structureStart,
            foliageCount = #data.distantFoliage - foliageStart,
        }
    end
end

function StorybookIslandData.Build(layout)
    layout = layout or IslandLayout.Resolve(IslandLayout.TERRAIN_PRESET)
    local cacheKey = tostring(layout.id or layout.terrainId or IslandLayout.TERRAIN_PRESET)
    BUILD_CACHE_CLOCK = BUILD_CACHE_CLOCK + 1
    local cached = BUILD_CACHE[cacheKey]
    if cached then
        cached.lastUsed = BUILD_CACHE_CLOCK
        return cached.data
    end
    local pureTerrain = layout.id ~= IslandLayout.TERRAIN_PRESET
    local data = {
        terrainId = layout.id,
        islands = {}, grass = {}, soil = {}, rockUpper = {}, rockLower = {}, rockTip = {},
        decorRocks = {}, rockLedges = {}, moss = {}, fragments = {}, shrubs = {},
        bridgeGrass = {}, bridgeSoil = {}, bridgeRock = {}, bridgeFragments = {}, bridgeSpans = {},
        terrainWater = {}, terrainAccents = {}, terrainFoliage = {},
        distantIslands = {}, distantGrass = {}, distantSoil = {}, distantRock = {},
        distantStructures = {}, distantFoliage = {},
        cloudsNear = {}, cloudsLow = {}, cloudsMid = {}, cloudsHigh = {}, cloudsFar = {}, clouds = {},
    }
    for index, spec in ipairs(layout.ISLANDS or layout.islands or {}) do
        local island = BuildIsland(spec, index)
        data.islands[#data.islands + 1] = island
        Append(data.grass, island.grass); Append(data.soil, island.soil)
        Append(data.rockUpper, island.rockUpper); Append(data.rockLower, island.rockLower)
        Append(data.rockTip, island.rockTip)
    end
    if not pureTerrain then BuildTopDecor(data) end
    BuildUndersideDetail(data, pureTerrain)
    BuildBridges(data, layout)
    BuildTerrainFeatures(data, layout)
    BuildDistantIslands(data, pureTerrain)
    BuildClouds(data, layout)
    BUILD_CACHE[cacheKey] = { data = data, lastUsed = BUILD_CACHE_CLOCK }
    local count = 0
    for _ in pairs(BUILD_CACHE) do count = count + 1 end
    while count > BUILD_CACHE_LIMIT do
        local oldestKey, oldestUse
        for key, entry in pairs(BUILD_CACHE) do
            if key ~= cacheKey and (oldestUse == nil or entry.lastUsed < oldestUse) then
                oldestKey, oldestUse = key, entry.lastUsed
            end
        end
        if not oldestKey then break end
        BUILD_CACHE[oldestKey] = nil
        count = count - 1
    end
    return data
end

function StorybookIslandData.CacheStats()
    local count = 0
    for _ in pairs(BUILD_CACHE) do count = count + 1 end
    return { entries = count, limit = BUILD_CACHE_LIMIT }
end

function StorybookIslandData.ClearCache()
    BUILD_CACHE = {}
    BUILD_CACHE_CLOCK = 0
end

return StorybookIslandData
