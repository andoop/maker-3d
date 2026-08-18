package.path = "scripts/?.lua;" .. package.path

local Theme = require("IslandUITheme")

local function Assert(condition, message)
    if not condition then error(message or "assertion failed", 2) end
end

local function Luminance(color)
    return color[1] * 0.2126 + color[2] * 0.7152 + color[3] * 0.0722
end

local noon = Theme.Palette(12)
local dusk = Theme.Palette(18)
local earlyDusk = Theme.Palette(17.01)
local midnight = Theme.Palette(0)

Assert(Luminance(noon.panel) > Luminance(midnight.panel) + 120,
    "night panels should be substantially darker than day panels")
Assert(Luminance(midnight.ink) > Luminance(midnight.panel) + 140,
    "night text must keep strong contrast against night panels")
Assert(Theme.Mode(12) == "day" and Theme.Mode(17) == "day",
    "fully bright hours must use the day overlay")
Assert(Theme.Mode(17.01) == "night" and Theme.Mode(6.99) == "night",
    "any partially dimmed hour must switch to the night overlay")
Assert(earlyDusk.panel[1] == midnight.panel[1]
        and earlyDusk.panel[2] == midnight.panel[2]
        and dusk.panel[3] == midnight.panel[3],
    "dawn and dusk must reuse the same night palette instead of a third tint")
Assert(noon.chrome[4] == midnight.chrome[4],
    "time adaptation must preserve authored overlay opacity")
Assert(midnight.scrim[4] > noon.scrim[4],
    "night scrims should suppress the scene more strongly behind open panels")

print("island-ui-theme-spec: ok")
