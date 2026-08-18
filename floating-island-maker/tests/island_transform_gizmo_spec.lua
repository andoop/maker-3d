package.path = "scripts/?.lua;" .. package.path

package.preload["urhox-libs/3D"] = function() return {} end
package.preload["MakerTransformControls"] = function() return {} end

local Gizmo = require("IslandTransformGizmo")

local normal, vertical = Gizmo.TouchHitPadding(1)
assert(normal == 14 and vertical == 20 and vertical > normal,
    "phone model gizmo must give the vertical translation axis extra tolerance")
local highDprNormal, highDprVertical = Gizmo.TouchHitPadding(3)
assert(highDprNormal == 28 and highDprVertical == 36,
    "framebuffer touch padding must remain bounded on high-DPR phones")

local function FakeGizmo(handle)
    local gizmo = setmetatable({ center = {}, mode = "translate" }, Gizmo)
    function gizmo:Hit(ray)
        local distance = math.sqrt(ray.x * ray.x + ray.y * ray.y)
        if distance > normal and distance <= vertical then return handle end
        return nil
    end
    return gizmo
end

local function RayAt(x, y) return { x = x - 100, y = y - 100 } end
local rect = { left = 0, top = 0, right = 200, bottom = 200 }
assert(FakeGizmo("y"):HitScreen(100, 100, true, RayAt, 1, rect) == "y",
    "the up/down axis must use the larger touch-only allowance")
assert(FakeGizmo("x"):HitScreen(100, 100, true, RayAt, 1, rect) == nil,
    "the larger vertical allowance must not invisibly expand the other axes")
assert(FakeGizmo("y"):HitScreen(100, 100, false, RayAt, 1, rect) == nil,
    "mouse picking must remain exact")

print("island-transform-gizmo-spec: ok")
