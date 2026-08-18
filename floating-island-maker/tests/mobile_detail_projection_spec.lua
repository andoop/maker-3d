package.path = "scripts/?.lua;" .. package.path

local Matrix4 = require("urhox-libs/3D/Core/Matrix4")
local Vector3 = require("urhox-libs/3D/Core/Vector3")
local Projection = require("MobileDetailProjection")

local near, far = 0.1, 600
local top = near * math.tan(math.rad(72) * 0.5)
local projection = Matrix4.new():makePerspective(-top * 1.8, top * 1.8, top, -top, near, far)

local function IsVisible(x, y, z)
    local projected = Vector3.new(x, y, z):applyMatrix4(projection)
    return Projection.InView(projected.x, projected.y, -z, far, 1.16)
end

assert(IsVisible(0, 0, -2) and IsVisible(0, 0, -100),
    "real WebGL projection must retain points in front of the first-person camera")
assert(not IsVisible(0, 0, 2) and not IsVisible(0, 0, 10) and not IsVisible(0, 0, 100),
    "signed forward depth must reject every camera-behind point even when NDC z folds near +1")
assert(not IsVisible(0, 0, -700), "the camera far plane must reject distant authored details")
assert(not IsVisible(100, 0, -10), "horizontal frustum overflow must not consume detail budget")
assert(Projection.CoverageKey(-0.9, 0) ~= Projection.CoverageKey(0.9, 0),
    "visible ground cover must distribute across distinct screen tiles")

print("mobile detail projection tests passed")
