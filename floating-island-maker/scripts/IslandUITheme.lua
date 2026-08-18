-- Time-aware Q-style overlay palette for the island home screen.

local DayNightClock = require("DayNightClock")

local IslandUITheme = {}

local DAY = {
    ink = { 53, 67, 82, 255 }, muted = { 108, 119, 128, 255 },
    line = { 174, 205, 211, 255 }, panel = { 255, 248, 231, 246 },
    surface = { 255, 253, 245, 248 }, soft = { 231, 246, 238, 255 },
    blue = { 61, 155, 211, 255 }, blueDark = { 45, 105, 158, 255 },
    green = { 91, 169, 79, 255 }, gold = { 235, 180, 55, 255 },
    danger = { 219, 92, 75, 255 }, coralSoft = { 255, 231, 219, 255 },
    dangerHover = { 255, 216, 204, 255 }, dangerPressed = { 250, 199, 187, 255 },
    dangerLine = { 236, 151, 133, 255 },
    yellowSoft = { 255, 244, 192, 255 }, skySoft = { 224, 244, 255, 255 },
    white = { 255, 255, 255, 255 }, transparent = { 0, 0, 0, 0 },
    shadow = { 52, 78, 91, 48 }, chrome = { 255, 248, 231, 244 },
    panelGlass = { 255, 248, 231, 238 }, surfaceGlass = { 255, 248, 231, 232 },
    hudGlass = { 255, 248, 231, 220 }, statusGlass = { 255, 248, 231, 226 },
    subtleGlass = { 255, 248, 231, 208 }, timePanel = { 255, 248, 231, 242 },
    scrim = { 35, 69, 91, 58 }, scrimStrong = { 35, 69, 91, 76 },
    accentShadow = { 42, 111, 158, 45 }, topShadow = { 48, 76, 88, 30 },
    cardShadow = { 59, 79, 84, 24 },
    joystickFill = { 61, 155, 211, 62 }, joystickLine = { 255, 255, 255, 175 },
    skyText = { 255, 255, 255, 220 }, sliderTrack = { 49, 63, 91, 82 },
}

local NIGHT = {
    ink = { 236, 242, 255, 255 }, muted = { 166, 181, 210, 255 },
    line = { 89, 110, 151, 255 }, panel = { 25, 35, 62, 246 },
    surface = { 35, 48, 80, 248 }, soft = { 44, 61, 87, 255 },
    blue = { 101, 165, 235, 255 }, blueDark = { 143, 196, 247, 255 },
    green = { 119, 194, 132, 255 }, gold = { 247, 192, 82, 255 },
    danger = { 247, 127, 111, 255 }, coralSoft = { 76, 48, 62, 255 },
    dangerHover = { 95, 56, 69, 255 }, dangerPressed = { 112, 59, 69, 255 },
    dangerLine = { 166, 84, 94, 255 },
    yellowSoft = { 77, 67, 56, 255 }, skySoft = { 47, 67, 103, 255 },
    white = { 255, 255, 255, 255 }, transparent = { 0, 0, 0, 0 },
    shadow = { 1, 8, 25, 108 }, chrome = { 19, 30, 55, 244 },
    panelGlass = { 25, 36, 64, 238 }, surfaceGlass = { 35, 48, 80, 232 },
    hudGlass = { 18, 30, 56, 220 }, statusGlass = { 24, 37, 65, 226 },
    subtleGlass = { 31, 45, 73, 208 }, timePanel = { 25, 36, 64, 242 },
    scrim = { 3, 8, 25, 95 }, scrimStrong = { 3, 8, 25, 118 },
    accentShadow = { 70, 139, 222, 70 }, topShadow = { 0, 5, 20, 82 },
    cardShadow = { 0, 5, 18, 70 },
    joystickFill = { 75, 133, 205, 85 }, joystickLine = { 172, 207, 255, 190 },
    skyText = { 230, 240, 255, 235 }, sliderTrack = { 10, 18, 40, 150 },
}

function IslandUITheme.Mode(hour)
    -- The scene lighting still transitions continuously, but the overlay has
    -- only two deliberately authored themes. Any partially dimmed scene is
    -- already considered night so controls never sit in an in-between tint.
    return DayNightClock.VisualState(hour).dayFactor >= 1 and "day" or "night"
end

local UI_SATURATION = 1.20

local function SaturatedColor(color)
    local gray = color[1] * 0.299 + color[2] * 0.587 + color[3] * 0.114
    local function channel(value)
        return math.max(0, math.min(255, math.floor(gray + (value - gray) * UI_SATURATION + 0.5)))
    end
    return { channel(color[1]), channel(color[2]), channel(color[3]), color[4] }
end

function IslandUITheme.Palette(hour)
    local source = IslandUITheme.Mode(hour) == "day" and DAY or NIGHT
    local palette = {}
    for name, color in pairs(source) do
        palette[name] = SaturatedColor(color)
    end
    return palette
end

return IslandUITheme
