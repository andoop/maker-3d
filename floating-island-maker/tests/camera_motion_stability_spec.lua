package.path = "scripts/?.lua;" .. package.path

local CameraMotionStability = require("CameraMotionStability")

local dx, dy = CameraMotionStability.FilterPointerDelta(0.6, 0.7, 1.2)
assert(dx == 0 and dy == 0, "stationary touch chatter should not rotate the camera")
dx, dy = CameraMotionStability.FilterPointerDelta(2, -3, 1.2)
assert(dx == 2 and dy == -3, "intentional pointer motion must pass through unchanged")

assert(CameraMotionStability.FilterPinchFactor(1.003, 0.006) == 1,
    "sub-percent pinch noise should not slowly zoom the scene")
assert(CameraMotionStability.FilterPinchFactor(1.02, 0.006) == 1.02,
    "an intentional pinch must pass through unchanged")

local step60, retain60 = CameraMotionStability.DampedStep(0.9, 0.9, 1 / 60)
local step30, retain30 = CameraMotionStability.DampedStep(0.9, 0.9, 1 / 30)
assert(math.abs(step60 - 0.09) < 0.000001 and math.abs(retain60 - 0.9) < 0.000001,
    "60-Hz orbit inertia must retain its established feel")
assert(math.abs(step30 - (0.09 + 0.09 * 0.9)) < 0.000001
        and math.abs(retain30 - 0.81) < 0.000001,
    "a slow frame must advance inertia by the same elapsed-time amount")

local changed, sample = CameraMotionStability.UpdateOrbitSample(
    nil, 0, 0, 0, 0, 0, 20, false)
assert(changed, "the first camera sample must invalidate visibility detail")
changed, sample = CameraMotionStability.UpdateOrbitSample(
    sample, 0.1, 0, 0, math.rad(0.2), 0, 20.05, false)
assert(not changed, "imperceptible camera drift must not rebuild dense visibility sets")
changed, sample = CameraMotionStability.UpdateOrbitSample(
    sample, 0.5, 0, 0, math.rad(0.7), 0, 20.5, false)
assert(changed, "meaningful camera motion must still refresh visible detail")
changed = CameraMotionStability.UpdateOrbitSample(
    { mode = "orbit", x = 0, y = 0, z = 0, theta = math.pi * 2 - 0.002, phi = 0, radius = 20 },
    0, 0, 0, 0.002, 0, 20, false)
assert(not changed, "angle wrapping must not look like a full camera revolution")

changed, sample = CameraMotionStability.UpdateFirstPersonSample(
    nil, 0, 1.2, 0, 0, 0, false)
assert(changed, "the first first-person camera sample must be captured")
changed = CameraMotionStability.UpdateFirstPersonSample(
    sample, 0.05, 1.2, 0.05, math.rad(0.1), 0, false)
assert(not changed, "tiny first-person noise must not rebuild visibility sets")

print("camera_motion_stability_spec: ok")
