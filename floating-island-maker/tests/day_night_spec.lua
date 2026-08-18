package.path = "scripts/?.lua;" .. package.path

local Clock = require("DayNightClock")
local Viewport = require("ViewportCoordinates")

local dawn = Clock.VisualState(6)
local noon = Clock.VisualState(12)
local night = Clock.VisualState(23)
assert(dawn.dayFactor > 0 and dawn.dayFactor < 1, "dawn must blend night into day")
assert(noon.dayFactor == 1 and noon.starOpacity == 0, "noon must be fully bright")
assert(night.nightFactor == 1 and night.windowIntensity > 2, "night must enable building glow")
assert(noon.background ~= night.background and noon.skyTint ~= night.skyTint,
    "day and night need distinct saturated sky palettes")

local clock = Clock.new({ time = 23.5, auto = true, dayDuration = 480 })
clock:Update(20)
assert(math.abs(clock:GetTime() - 0.5) < 0.0001, "automatic time must wrap across midnight")
clock:SetAuto(false)
local paused = clock:GetTime()
clock:Update(100)
assert(clock:GetTime() == paused, "manual mode must pause automatic flow")
clock:SetTime(6.5)
assert(clock:GetTimeLabel() == "06:30" and clock:GetPhaseLabel() == "清晨",
    "clock labels must match the selected time")

local rect = { left = 200, top = 100, right = 1000, bottom = 700 }
local nx, ny = Viewport.Normalize(rect, 600, 400)
assert(math.abs(nx - 0.5) < 0.000001 and math.abs(ny - 0.5) < 0.000001,
    "touches must normalize inside the active inset viewport")
local x, y = Viewport.FromNdc(rect, 0, 0)
assert(x == 600 and y == 400, "projection and picking conversions must be exact inverses")
local edgeX, edgeY = Viewport.FromNdc(rect, -1, 1)
assert(edgeX == rect.left and edgeY == rect.top, "NDC edges must map to viewport edges")
assert(Viewport.IsTapMovement(100, 100, 106, 106, 9),
    "normal phone finger jitter must remain a placement tap")
assert(not Viewport.IsTapMovement(100, 100, 110, 100, 9),
    "deliberate movement beyond the shared threshold must become a drag")
local desktopPanX, desktopPanY = Viewport.NormalizePanDelta(7, 5, true, false)
assert(desktopPanX == 7 and desktopPanY == 5,
    "desktop trackpad placement panning must preserve horizontal and forward/backward motion")
local phonePanX, phonePanY = Viewport.NormalizePanDelta(7, 5, true, true)
assert(phonePanX == 7 and phonePanY == 5,
    "phone two-finger placement panning must keep direct-touch direction unchanged")
local mouseRotation = Viewport.RotationDelta(0, math.pi * 0.5, false)
local phoneRotation = Viewport.RotationDelta(0, math.pi * 0.5, true)
assert(math.abs(mouseRotation - math.pi * 0.5) < 0.000001,
    "mouse rotation must preserve the existing screen-angle direction")
assert(math.abs(phoneRotation + math.pi * 0.5) < 0.000001,
    "phone direct-touch rotation must follow the finger instead of turning backwards")
assert(math.abs(Viewport.RotationDelta(math.pi * 0.9, -math.pi * 0.9, true) + math.pi * 0.2) < 0.000001,
    "phone rotation must stay continuous while crossing the screen-angle seam")

print("day-night-spec: ok")
