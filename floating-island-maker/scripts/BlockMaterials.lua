---@diagnostic disable: undefined-global

local THREE = require("urhox-libs/3D")
local Catalog = require("BlockCatalog")
local Theme = require("CloudAtelierTheme")

local BlockMaterials = {}
BlockMaterials.__index = BlockMaterials

local TEXTURE_SIZE = 16
local REALISTIC_TEXTURE_SIZE = 64
local TAU = math.pi * 2

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function NormalizeHex(value)
    value = tostring(value or Theme.MODEL.plaster):lower()
    if value:match("^#%x%x%x%x%x%x$") then return value end
    return Theme.MODEL.plaster
end

local function HexChannels(value)
    local hex = NormalizeHex(value)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

local function MixHex(base, tint, tintAmount)
    local br, bg, bb = HexChannels(base)
    local tr, tg, tb = HexChannels(tint)
    local amount = Clamp(tonumber(tintAmount) or 0, 0, 1)
    return string.format("#%02x%02x%02x",
        math.floor(br + (tr - br) * amount + 0.5),
        math.floor(bg + (tg - bg) * amount + 0.5),
        math.floor(bb + (tb - bb) * amount + 0.5))
end

local function HexToInt(value)
    return tonumber(NormalizeHex(value):sub(2), 16) or 0xffffff
end

local function HexColor(value, alpha)
    local r, g, b = HexChannels(value)
    return Color(r / 255, g / 255, b / 255, alpha or 1)
end

local function Noise(x, y, seed)
    local value = (x * 37 + y * 61 + seed * 101 + x * y * 17) % 257
    return value / 256
end

local function TextureFromImage(image, label)
    local native = Texture2D:new()
    native:SetSRGB(true)
    native:SetNumLevels(1)
    native:SetFilterMode(FILTER_BILINEAR)
    native:SetData(image, false)

    local texture = THREE.Texture("[block-material-" .. label .. "]")
    texture.wrapS = THREE.RepeatWrapping
    texture.wrapT = THREE.RepeatWrapping
    texture.generateMipmaps = false
    texture.magFilter = THREE.LinearFilter
    texture.minFilter = THREE.LinearFilter
    texture.colorSpace = "srgb"
    texture:_setNative(native)
    return texture
end

local function TextureFromCells(palette, cells, label)
    local image = Image()
    image:SetSize(TEXTURE_SIZE, TEXTURE_SIZE, 4)
    for y = 0, TEXTURE_SIZE - 1 do
        for x = 0, TEXTURE_SIZE - 1 do
            local paletteIndex = cells[y * TEXTURE_SIZE + x + 1] or 1
            image:SetPixel(x, y, HexColor(palette[paletteIndex] or palette[1]))
        end
    end
    local texture = TextureFromImage(image, label)
    texture.magFilter = THREE.LinearFilter
    texture.minFilter = THREE.LinearFilter
    texture.needsUpdate = true
    return texture
end

local function CreateWaterTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local u, v = x / size * TAU, y / size * TAU
            local broad = math.sin(u * 2 + v * 1.2 + 0.35)
            local crossing = math.sin(u * 3.5 - v * 2.4 + 1.15)
            local ridge = 1 - math.abs(broad * 0.68 + crossing * 0.32)
            local caustic = Clamp((ridge - 0.74) / 0.26, 0, 1)
            caustic = caustic * caustic
            local depth = 0.5 + 0.5 * math.sin(u * 0.75 - v * 1.25 + 0.8)
            local patch = (Noise(math.floor(x / 6), math.floor(y / 6), 31) - 0.5) * 0.018
            local r = 0.20 + depth * 0.035 + caustic * 0.18 + patch
            local g = 0.49 + depth * 0.075 + caustic * 0.23 + patch
            local b = 0.57 + depth * 0.090 + caustic * 0.20 + patch
            image:SetPixel(x, y, Color(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), 1))
        end
    end
    return TextureFromImage(image, "water")
end

local function CreateFireTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local u = x / size * TAU
            local height = 0.67
                + math.sin(u * 2 + 0.4) * 0.14
                + math.sin(u * 5 - 0.9) * 0.075
                + math.sin(u * 9 + 1.6) * 0.035
            local upward = 1 - y / (size - 1)
            local edgeNoise = (Noise(x, y, 47) - 0.5) * 0.085
            local mask = Clamp((height - upward + edgeNoise) * 9, 0, 1)
            local coreShape = Clamp((height - upward - 0.10) * 5.5, 0, 1)
            local heat = Clamp((1 - upward) * 0.62 + coreShape * 0.52, 0, 1)
            local r, g, b
            if heat > 0.78 then
                local t = (heat - 0.78) / 0.22
                r, g, b = 1, 0.78 + t * 0.20, 0.20 + t * 0.58
            elseif heat > 0.42 then
                local t = (heat - 0.42) / 0.36
                r, g, b = 1, 0.22 + t * 0.56, 0.025 + t * 0.175
            else
                local t = heat / 0.42
                r, g, b = 0.34 + t * 0.66, 0.015 + t * 0.205, 0.006
            end
            local alpha = Clamp(mask * (0.72 + heat * 0.28), 0, 1)
            image:SetPixel(x, y, Color(r, g, b, alpha))
        end
    end
    return TextureFromImage(image, "fire")
end

-- Low-frequency washes, softened seams and sparse hand-painted marks form the
-- common surface language. The texture carries material character while the
-- model colour remains in control of the final palette.
local function CreateSurfaceTexture(id)
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local u, v = x / size * TAU, y / size * TAU
            local seed = id == "sand" and 83 or id == "stone" and 97
                or id == "earth" and 113 or id == "plaster" and 127 or 109
            local grain = Noise(x, y, seed) - 0.5
            local broad = Noise(math.floor(x / 9), math.floor(y / 9), seed + 7) - 0.5
            local r, g, b
            if id == "sand" then
                local dune = math.sin(u * 1.2 + v * 2.1 + math.sin(v) * 0.45) * 0.022
                local fleck = Noise(x * 3 + 1, y * 5 + 2, 89) > 0.955 and -0.055 or 0
                r = 0.86 + dune + broad * 0.045 + grain * 0.018 + fleck
                g = 0.79 + dune * 0.85 + broad * 0.038 + grain * 0.016 + fleck
                b = 0.63 + dune * 0.58 + broad * 0.028 + grain * 0.012 + fleck * 0.6
            elseif id == "stone" then
                local cellX, cellY = math.floor(x / 16), math.floor(y / 13)
                local offset = cellY % 2 * 7
                local localX = (x + offset) % 16
                local facet = (Noise(cellX * 11 + cellY, cellY * 13, 97) - 0.5) * 0.10
                local seamDistance = math.min(localX, 15 - localX, y % 13, 12 - y % 13)
                local seam = seamDistance <= 0 and -0.075 or seamDistance == 1 and -0.026 or 0
                local base = 0.73 + facet + seam + broad * 0.028 + grain * 0.012
                r, g, b = base * 1.01, base, base * 0.98
            elseif id == "earth" then
                local wave = math.floor((y + math.sin(x * 0.18) * 2) / 9) % 4
                local shift = ({ 0.035, -0.018, 0.016, -0.036 })[wave + 1]
                local seam = (y + math.floor(math.sin(x * 0.18) * 2)) % 9 == 0 and -0.045 or 0
                local fleck = Noise(math.floor(x / 4), math.floor(y / 4), 113) > 0.93 and 0.035 or 0
                r, g, b = 0.74 + shift + seam + fleck, 0.52 + shift * 0.65 + seam, 0.39 + shift * 0.45 + seam * 0.6
            elseif id == "plaster" then
                local trowel = math.sin(u * 0.75 + math.sin(v * 1.4) * 0.6) * 0.012
                local speck = Noise(x * 5, y * 3, 131) > 0.975 and -0.035 or 0
                r = 0.96 + broad * 0.035 + trowel + grain * 0.009 + speck
                g = 0.94 + broad * 0.032 + trowel + grain * 0.008 + speck
                b = 0.88 + broad * 0.026 + trowel * 0.8 + grain * 0.006 + speck
            else
                local hammer = Noise(math.floor(x / 5), math.floor(y / 5), 109) - 0.5
                local brush = math.sin(v * 8 + math.sin(u) * 0.8) * 0.018
                local sheen = math.max(0, math.cos(u - 0.35)) * 0.055
                local base = 0.66 + hammer * 0.09 + brush + sheen + grain * 0.012
                r, g, b = base * 1.04, base, base * 0.91
            end
            image:SetPixel(x, y, Color(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), 1))
        end
    end
    return TextureFromImage(image, id)
end

local function CreateBrickTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local row = math.floor(y / 8)
            local localY = y % 8
            local localX = (x + row % 2 * 8) % 16
            local seamDistance = math.min(localX, 15 - localX, localY, 7 - localY)
            local mortar = seamDistance <= 0 or (seamDistance == 1 and Noise(x, y, 221) > 0.45)
            local brickTone = (Noise(row * 13 + math.floor(x / 16), row * 29, 223) - 0.5) * 0.13
            local grain = (Noise(x * 3, y * 5, 227) - 0.5) * 0.045
            local chip = Noise(x * 7, y * 11, 229) > 0.985 and -0.16 or 0
            local r, g, b
            if mortar then
                local shadow = (Noise(x, y, 231) - 0.5) * 0.035
                r, g, b = 0.66 + shadow, 0.61 + shadow, 0.53 + shadow
            else
                local warm = ((x + y) % 19 == 0) and 0.045 or 0
                r = 0.67 + brickTone + grain + warm + chip
                g = 0.33 + brickTone * 0.48 + grain * 0.45 + chip * 0.55
                b = 0.24 + brickTone * 0.34 + grain * 0.32 + chip * 0.40
            end
            image:SetPixel(x, y, Color(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), 1))
        end
    end
    return TextureFromImage(image, "brick")
end

-- A single ruin block should read as a wall assembled from dozens of stones.
-- These four seamless procedural atlases keep that illusion cheap: large wall
-- models can use one structural component instead of one component per brick.
local function CreateRuinTexture(id)
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    local cellWidth = id == "old_brick" and 12 or id == "carved_stone" and 22 or 18
    local cellHeight = id == "old_brick" and 7 or id == "carved_stone" and 18 or 13
    local seed = id == "old_brick" and 307 or id == "carved_stone" and 331
        or id == "overgrown_stone" and 347 or 293

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local row = math.floor(y / cellHeight)
            local offset = id == "carved_stone" and 0 or row % 2 * math.floor(cellWidth * 0.48)
            local shiftedX = x + offset
            local column = math.floor(shiftedX / cellWidth)
            local localX, localY = shiftedX % cellWidth, y % cellHeight
            local edge = math.min(localX, cellWidth - 1 - localX, localY, cellHeight - 1 - localY)
            local uneven = Noise(row * 17 + column * 29, row * 31 - column * 7, seed) - 0.5
            local grain = (Noise(x * 5, y * 7, seed + 3) - 0.5) * 0.055
            local broad = (Noise(math.floor(x / 5), math.floor(y / 5), seed + 5) - 0.5) * 0.070
            local chippedCorner = edge <= 2
                and Noise(column * 23 + localX, row * 19 + localY, seed + 11) > 0.74
            local mortar = edge <= 1 or chippedCorner
            local crack = not mortar and Noise(math.floor(x / 2), math.floor(y / 2), seed + 13) > 0.982
            local r, g, b

            if mortar then
                local mortarNoise = (Noise(x, y, seed + 17) - 0.5) * 0.045
                if id == "old_brick" then
                    r, g, b = 0.68 + mortarNoise, 0.64 + mortarNoise, 0.56 + mortarNoise
                else
                    r, g, b = 0.50 + mortarNoise, 0.53 + mortarNoise, 0.50 + mortarNoise
                end
            elseif id == "old_brick" then
                local soot = Noise(math.floor(x / 4), math.floor(y / 4), seed + 19) > 0.92 and -0.06 or 0
                r = 0.80 + uneven * 0.16 + grain + broad + soot
                g = 0.51 + uneven * 0.09 + grain * 0.55 + broad * 0.45 + soot
                b = 0.39 + uneven * 0.06 + grain * 0.42 + soot * 0.75
            elseif id == "carved_stone" then
                local cx = (localX + 0.5) / cellWidth - 0.5
                local cy = (localY + 0.5) / cellHeight - 0.5
                local ring = math.sqrt(cx * cx + cy * cy)
                local carved = math.abs(ring - 0.28) < 0.045
                    or math.abs(cx - cy * 0.55) < 0.035 and math.abs(cx) < 0.31
                local incision = carved and -0.11 or 0
                local base = 0.84 + uneven * 0.10 + grain + broad + incision
                r, g, b = base * 1.02, base, base * 0.92
            else
                local base = (id == "overgrown_stone" and 0.74 or 0.78)
                    + uneven * 0.12 + grain + broad
                r, g, b = base * 1.01, base * 1.02, base * 0.96
            end

            if id == "overgrown_stone" and not mortar then
                local patch = Noise(math.floor(x / 4), math.floor(y / 4), seed + 23)
                local vine = math.abs((x + math.floor(math.sin(y * 0.18) * 4)) % 23 - 11) <= 1
                    and y % 17 > 2
                local moss = patch > 0.61 or vine
                if moss then
                    local strength = 0.18 + (patch - 0.61) * 0.30
                    r, g, b = r - strength * 0.62, g + strength * 0.34, b - strength * 0.58
                end
            end
            if crack then r, g, b = r - 0.09, g - 0.09, b - 0.08 end
            image:SetPixel(x, y, Color(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), 1))
        end
    end
    return TextureFromImage(image, id)
end

local function CreateRoofTileTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local row = math.floor(y / 10)
            local localY = y % 10
            local localX = (x + row % 2 * 8) % 16
            local curve = 4 + math.sin((localX / 15) * math.pi) * 3.4
            local seam = localY <= 1 or math.abs(localY - curve) <= 0.75 or localX <= 0 or localX >= 15
            local shadow = localY > curve and -0.045 or 0.035
            local variation = (Noise(row * 17 + math.floor(x / 16), row * 23, 241) - 0.5) * 0.10
            local speck = Noise(x * 5, y * 3, 243) > 0.972 and -0.08 or 0
            local r = 0.73 + variation + shadow + speck
            local g = 0.35 + variation * 0.42 + shadow * 0.35 + speck * 0.45
            local b = 0.27 + variation * 0.35 + shadow * 0.25 + speck * 0.32
            if seam then
                r, g, b = r - 0.09, g - 0.06, b - 0.045
            end
            image:SetPixel(x, y, Color(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), 1))
        end
    end
    return TextureFromImage(image, "roof_tile")
end

local function CreatePavementTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local row = math.floor(y / 16)
            local localY = y % 16
            local localX = (x + row % 2 * 8) % 16
            local seamDistance = math.min(localX, 15 - localX, localY, 15 - localY)
            local seam = seamDistance <= 1
            local slab = (Noise(row * 31 + math.floor(x / 16), row * 13, 251) - 0.5) * 0.12
            local grain = (Noise(x * 2, y * 3, 253) - 0.5) * 0.030
            local moss = Noise(x, y, 257) > 0.982 and 0.08 or 0
            local base = 0.64 + slab + grain - (seam and 0.09 or 0)
            local r = base + moss * 0.15
            local g = base * 1.01 + moss
            local b = base * 0.94 + moss * 0.20
            image:SetPixel(x, y, Color(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), 1))
        end
    end
    return TextureFromImage(image, "pavement")
end

local function CreateAsphaltTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local broad = (Noise(math.floor(x / 7), math.floor(y / 7), 263) - 0.5) * 0.075
            local grain = (Noise(x * 11, y * 13, 269) - 0.5) * 0.060
            local stone = Noise(x * 17, y * 19, 271) > 0.955 and 0.12 or 0
            local crack = math.abs(math.sin(x * 0.23 + math.sin(y * 0.11) * 2.8)) < 0.018 and -0.075 or 0
            local base = 0.34 + broad + grain + stone + crack
            image:SetPixel(x, y, Color(Clamp(base * 0.93, 0, 1), Clamp(base, 0, 1), Clamp(base * 1.03, 0, 1), 1))
        end
    end
    return TextureFromImage(image, "asphalt")
end

local function CreateSnowTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local drift = math.sin(x * 0.12 + math.sin(y * 0.10) * 1.4) * 0.026
            local shade = (Noise(math.floor(x / 8), math.floor(y / 8), 281) - 0.5) * 0.038
            local sparkle = Noise(x * 23, y * 29, 283) > 0.992 and 0.10 or 0
            local r = 0.92 + drift + shade + sparkle
            local g = 0.94 + drift * 0.85 + shade + sparkle
            local b = 0.91 + drift * 0.55 + shade * 0.75 + sparkle
            image:SetPixel(x, y, Color(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), 1))
        end
    end
    return TextureFromImage(image, "snow")
end

local function CreatePlantTexture(id)
    local size = REALISTIC_TEXTURE_SIZE
    local palettes = {
        leaf = { "#3f6e62", "#4e815f", "#5d9861", "#72aa6a", "#8aba75" },
        moss = { "#596f45", "#657c49", "#6f8a50", "#81985c", "#94a96d" },
    }
    local colors = palettes[id]
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local patchSize = id == "leaf" and 9 or 7
            local px, py = math.floor(x / patchSize), math.floor(y / patchSize)
            local patch = Noise(px * 19, py * 23, id == "leaf" and 181 or 191)
            local index = patch < 0.13 and 1 or patch < 0.37 and 2 or patch > 0.9 and 5 or patch > 0.68 and 4 or 3
            local vein = id == "leaf" and ((x + y * 2) % 29 == 0)
                or id == "moss" and Noise(x, y, 197) > 0.982
            if vein then index = math.min(5, index + 1) end
            image:SetPixel(x, y, HexColor(colors[index]))
        end
    end
    local texture = TextureFromImage(image, id)
    texture.magFilter, texture.minFilter = THREE.LinearFilter, THREE.LinearFilter
    texture.needsUpdate = true
    return texture
end

local function CreatePaintedWoodTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local board = math.floor(x / 16)
            local seam = x % 16 == 0 or x % 16 == 15
            local brush = math.sin(y * 0.37 + board * 1.4 + math.sin(y * 0.08)) * 0.018
            local chip = Noise(x * 5, y * 7, 211) > 0.988 and -0.12 or 0
            local base = 0.91 + (board % 2 == 0 and 0.025 or -0.018) + brush - (seam and 0.055 or 0) + chip
            image:SetPixel(x, y, Color(base, base * 0.97, base * 0.90, 1))
        end
    end
    return TextureFromImage(image, "painted_wood")
end

local function CreateCrystalTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local facet = (math.floor(x / 12) + math.floor(y / 12) * 2) % 4
            local glint = (x + y) % 23 <= 1 or (x - y) % 31 == 0
            local value = ({ 0.72, 0.79, 0.88, 0.75 })[facet + 1] + (glint and 0.10 or 0)
            image:SetPixel(x, y, Color(value * 0.76, value * 0.96, value, 1))
        end
    end
    return TextureFromImage(image, "crystal")
end

-- Broad, softly filtered brush patches keep a large lawn alive without the
-- pixel-grid language that previously fought the cloud-atelier theme.
local function CreateGrassTexture()
    local size = REALISTIC_TEXTURE_SIZE
    local colors = {
        HexColor("#6e9d55"), HexColor("#79aa57"), HexColor("#86b85a"),
        HexColor("#93c166"), HexColor("#a3ca73"),
    }
    local image = Image()
    image:SetSize(size, size, 4)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local tileX, tileY = math.floor(x / 8), math.floor(y / 8)
            local tile = Noise(tileX * 17, tileY * 19, 151)
            local grain = Noise(x * 11 + (y % 5) * 7, y * 13 + (x % 7) * 3, 149)
            local index = 3
            if tile < 0.12 then index = 1
            elseif tile < 0.38 then index = 2
            elseif tile > 0.91 then index = 5
            elseif tile > 0.66 then index = 4 end
            if grain > 0.985 then index = math.min(5, index + 1)
            elseif grain < 0.015 then index = math.max(1, index - 1) end
            image:SetPixel(x, y, colors[index])
        end
    end
    local texture = TextureFromImage(image, "grass")
    texture.magFilter = THREE.LinearFilter
    texture.minFilter = THREE.LinearFilter
    texture.needsUpdate = true
    return texture
end

local function WoodCells()
    local cells = {}
    for y = 0, TEXTURE_SIZE - 1 do
        for x = 0, TEXTURE_SIZE - 1 do
            local grain = math.sin(x * 1.34 + math.sin(y * 0.48) * 1.1)
            local knotX, knotY = x - 10, y - 6
            local ring = math.sin(math.sqrt(knotX * knotX + knotY * knotY) * 1.8)
            local value = grain * 0.42 + ring * 0.28 + (Noise(x, y, 7) - 0.5) * 0.34
            local index = value > 0.48 and 1 or value > 0.08 and 2 or value > -0.34 and 3 or 4
            cells[y * TEXTURE_SIZE + x + 1] = index
        end
    end
    return cells
end

local function MarbleCells()
    local cells = {}
    for y = 0, TEXTURE_SIZE - 1 do
        for x = 0, TEXTURE_SIZE - 1 do
            local vein = math.abs(math.sin(x * 0.44 + y * 0.67 + math.sin(y * 0.31) * 1.9))
            local fine = math.abs(math.sin(x * 0.91 - y * 0.34 + 1.3))
            local index
            if vein < 0.10 or (fine < 0.055 and vein < 0.38) then index = 1
            elseif vein < 0.22 then index = 2
            elseif Noise(x, y, 19) > 0.82 then index = 3
            else index = 4 end
            cells[y * TEXTURE_SIZE + x + 1] = index
        end
    end
    return cells
end

local function GlassCells()
    local cells = {}
    for y = 0, TEXTURE_SIZE - 1 do
        for x = 0, TEXTURE_SIZE - 1 do
            local border = x == 0 or y == 0 or x == TEXTURE_SIZE - 1 or y == TEXTURE_SIZE - 1
            local glint = (x + y == 7) or (x + y == 8) or (x - y == 9)
            cells[y * TEXTURE_SIZE + x + 1] = border and 1 or glint and 2 or 3
        end
    end
    return cells
end

local function CeramicCells()
    local cells = {}
    for y = 0, TEXTURE_SIZE - 1 do
        for x = 0, TEXTURE_SIZE - 1 do
            local highlight = (x + y * 2) % 17 == 0 or (x == 3 and y >= 3 and y <= 7)
            local shade = Noise(x * 5, y * 7, 173)
            cells[y * TEXTURE_SIZE + x + 1] = highlight and 1 or shade < 0.18 and 3 or 2
        end
    end
    return cells
end

local function FabricCells()
    local cells = {}
    for y = 0, TEXTURE_SIZE - 1 do
        for x = 0, TEXTURE_SIZE - 1 do
            local weave = (x + y) % 4 == 0
            local thread = x % 4 == 0 or y % 4 == 0
            cells[y * TEXTURE_SIZE + x + 1] = weave and 1 or thread and 2 or 3
        end
    end
    return cells
end

local PALETTES = {
    wood = {
        "#5c463a", "#70513f", "#8b6248", "#a77a58",
    },
    marble = {
        "#788287", "#a2aaa9", "#cac9bd", "#ece3d1",
    },
    glass = {
        "#c7e5e2", "#eff6ed", "#a8d0d1",
    },
    ceramic = {
        "#f1dfc4", "#c98768", "#a8614e",
    },
    fabric = {
        "#efe0cf", "#d7b8aa", "#c79c94",
    },
}

function BlockMaterials.new()
    return setmetatable({
        -- Active meshes keep their material wrappers strongly referenced. A
        -- weak-value lookup therefore reuses every live colour (with no small
        -- LRU churn) while allowing deleted/edited historical colours to be
        -- reclaimed before the whole workbench is closed.
        materials = setmetatable({}, { __mode = "v" }),
        textures = {},
        mobileWater = false,
    }, BlockMaterials)
end

function BlockMaterials:SetMobileWater(enabled)
    enabled = enabled and true or false
    self.mobileWater = enabled
    -- Water now uses the same stable material on both render paths, so mode
    -- switches no longer require rebuilding every water-bearing model.
    return false
end

function BlockMaterials:RememberMaterial(key, material)
    self.materials[key] = material
    return material
end

function BlockMaterials:TextureFor(id)
    if self.textures[id] then return self.textures[id].texture end
    if id == "grass" or id == "leaf" or id == "moss" then
        local texture = id == "grass" and CreateGrassTexture() or CreatePlantTexture(id)
        self.textures[id] = { texture = texture }
        return texture
    end
    if id == "water" or id == "fire" then
        local texture = id == "water" and CreateWaterTexture() or CreateFireTexture()
        self.textures[id] = { texture = texture }
        return texture
    end
    if id == "sand" or id == "stone" or id == "metal" or id == "earth" or id == "solid" then
        local surfaceId = id == "solid" and "plaster" or id
        local texture = CreateSurfaceTexture(surfaceId)
        self.textures[id] = { texture = texture }
        return texture
    end
    if id == "ruin_stone" or id == "old_brick" or id == "carved_stone"
        or id == "overgrown_stone" then
        local texture = CreateRuinTexture(id)
        self.textures[id] = { texture = texture }
        return texture
    end
    if id == "brick" or id == "roof_tile" or id == "pavement" or id == "asphalt" or id == "snow" then
        local factories = {
            brick = CreateBrickTexture,
            roof_tile = CreateRoofTileTexture,
            pavement = CreatePavementTexture,
            asphalt = CreateAsphaltTexture,
            snow = CreateSnowTexture,
        }
        local texture = factories[id]()
        self.textures[id] = { texture = texture }
        return texture
    end
    local cells
    local paletteId = id
    if id == "painted_wood" then
        local texture = CreatePaintedWoodTexture()
        self.textures[id] = { texture = texture }
        return texture
    elseif id == "crystal" then
        local texture = CreateCrystalTexture()
        self.textures[id] = { texture = texture }
        return texture
    elseif id == "wood" then cells = WoodCells(); paletteId = "wood"
    elseif id == "marble" then cells = MarbleCells()
    elseif id == "glass" then cells = GlassCells(); paletteId = "glass"
    elseif id == "ceramic" then cells = CeramicCells()
    elseif id == "fabric" then cells = FabricCells()
    else return nil end
    -- These textures never change. An Image-backed Texture2D avoids the
    -- Canvas shim's EndAllViewsRender display-list replay on every frame.
    local texture = TextureFromCells(PALETTES[paletteId], cells, id)
    self.textures[id] = { texture = texture }
    return texture
end

function BlockMaterials:MaterialFor(materialId, color, forceNew)
    local definition = Catalog.FindMaterial(materialId)
    local id = definition.id
    color = NormalizeHex(color)
    local key = id .. "|" .. color
    if not forceNew and self.materials[key] then return self.materials[key] end

    local material
    local options
    if id == "water" then
        -- One stable hand-painted PBR treatment is shared by phone and desktop.
        -- It keeps water in the same visual language and avoids mobile
        -- refraction flicker or unsupported technique-level render states.
        options = {
            color = HexToInt(MixHex(Theme.MODEL.cloud, color, 0.34)),
            map = self:TextureFor(id),
            roughness = 0.22,
            metalness = 0,
            transparent = true,
            opacity = 0.76,
        }
    elseif id == "fire" then
        local texture = self:TextureFor(id)
        options = {
            color = HexToInt(MixHex("#ffffff", color, 0.20)),
            map = texture,
            emissiveMap = texture,
            emissive = 0xd98244,
            emissiveIntensity = 1.05,
            roughness = 0.38,
            metalness = 0,
            transparent = true,
            opacity = 1,
            side = THREE.DoubleSide,
        }
    elseif id == "wood" or id == "painted_wood" then
        options = {
            color = HexToInt(MixHex(id == "painted_wood" and Theme.MODEL.plaster or Theme.MODEL.cloud,
                color, id == "painted_wood" and 0.58 or 0.42)),
            map = self:TextureFor(id),
            roughness = id == "painted_wood" and 0.78 or 0.88,
            metalness = 0,
        }
    elseif id == "marble" then
        options = {
            color = HexToInt(MixHex(Theme.MODEL.cloud, color, 0.36)),
            map = self:TextureFor(id),
            roughness = 0.46,
            metalness = 0.01,
        }
    elseif id == "glass" or id == "crystal" then
        local crystalColor = HexToInt(MixHex(Theme.MODEL.glass, color, 0.55))
        options = {
            color = crystalColor,
            map = self:TextureFor(id),
            emissive = id == "crystal" and crystalColor or nil,
            emissiveIntensity = id == "crystal" and 0.28 or nil,
            roughness = id == "crystal" and 0.16 or 0.24,
            metalness = 0.02,
            transparent = true,
            opacity = id == "crystal" and 0.78 or 0.50,
            side = THREE.DoubleSide,
        }
    elseif id == "grass" or id == "leaf" or id == "moss" then
        options = {
            color = HexToInt(MixHex(id == "moss" and "#d8d5b4" or Theme.MODEL.cloud, color,
                id == "grass" and 0.34 or 0.46)),
            map = self:TextureFor(id),
            roughness = id == "moss" and 0.98 or 0.94,
            metalness = 0,
        }
    elseif id == "sand" or id == "earth" then
        options = {
            color = HexToInt(MixHex(id == "earth" and "#d9b28d" or Theme.MODEL.cloud, color,
                id == "earth" and 0.46 or 0.34)),
            map = self:TextureFor(id),
            roughness = id == "earth" and 0.95 or 0.92,
            metalness = 0,
        }
    elseif id == "stone" then
        options = {
            color = HexToInt(MixHex(Theme.MODEL.cloud, color, 0.40)),
            map = self:TextureFor(id),
            roughness = 0.92,
            metalness = 0.01,
        }
    elseif id == "ruin_stone" or id == "old_brick" or id == "carved_stone"
        or id == "overgrown_stone" then
        local bases = {
            ruin_stone = "#9da4a2", old_brick = "#bd7d63",
            carved_stone = "#c2beab", overgrown_stone = "#849a70",
        }
        options = {
            color = HexToInt(MixHex(bases[id], color, id == "overgrown_stone" and 0.30 or 0.38)),
            map = self:TextureFor(id),
            roughness = id == "carved_stone" and 0.91 or 0.97,
            metalness = 0,
        }
    elseif id == "brick" or id == "roof_tile" or id == "pavement" or id == "asphalt" or id == "snow" then
        local bases = {
            brick = Theme.MODEL.brick,
            roof_tile = Theme.MODEL.roofTile,
            pavement = Theme.MODEL.pavement,
            asphalt = Theme.MODEL.asphalt,
            snow = Theme.MODEL.snow,
        }
        local roughness = id == "asphalt" and 0.97 or id == "snow" and 0.84 or 0.88
        options = {
            color = HexToInt(MixHex(bases[id], color, id == "snow" and 0.26 or 0.42)),
            map = self:TextureFor(id),
            roughness = roughness,
            metalness = 0,
        }
    elseif id == "metal" then
        options = {
            color = HexToInt(MixHex("#c7b99d", color, 0.48)),
            map = self:TextureFor(id),
            roughness = 0.52,
            metalness = 0.52,
        }
    elseif id == "ceramic" then
        options = {
            color = HexToInt(MixHex(Theme.MODEL.plaster, color, 0.62)),
            map = self:TextureFor(id),
            roughness = 0.38,
            metalness = 0.01,
        }
    elseif id == "fabric" then
        options = {
            color = HexToInt(MixHex(Theme.MODEL.cloud, color, 0.62)),
            map = self:TextureFor(id),
            roughness = 1,
            metalness = 0,
        }
    elseif id == "glow" then
        local glowColor = HexToInt(MixHex("#ead39a", color, 0.48))
        options = {
            color = glowColor,
            emissive = glowColor,
            emissiveIntensity = 0.72,
            roughness = 0.58,
            metalness = 0,
        }
    else
        options = {
            color = HexToInt(color),
            map = self:TextureFor("solid"),
            roughness = 0.90,
            metalness = 0,
        }
    end
    if not material then material = THREE.MeshStandardMaterial(options) end
    return self:RememberMaterial(key, material)
end

function BlockMaterials:Dispose()
    for _, entry in pairs(self.textures) do
        if entry.texture and entry.texture.dispose then entry.texture:dispose() end
    end
    for _, material in pairs(self.materials) do
        if material and material.dispose then material:dispose() end
    end
    self.textures = {}
    self.materials = setmetatable({}, { __mode = "v" })
end

return BlockMaterials
