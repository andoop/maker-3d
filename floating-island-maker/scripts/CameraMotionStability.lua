local CameraMotionStability = {}

local PI = math.pi
local TAU = PI * 2

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function AngularDistance(a, b)
    local difference = ((tonumber(a) or 0) - (tonumber(b) or 0) + PI) % TAU - PI
    return math.abs(difference)
end

local function DistanceSquared(ax, ay, az, bx, by, bz)
    local dx = (tonumber(ax) or 0) - (tonumber(bx) or 0)
    local dy = (tonumber(ay) or 0) - (tonumber(by) or 0)
    local dz = (tonumber(az) or 0) - (tonumber(bz) or 0)
    return dx * dx + dy * dy + dz * dz
end

-- Ignore only the sub-pixel chatter produced by a stationary touch contact.
-- Real drags pass through unchanged, so the camera never acquires a different
-- direction or speed merely because input filtering is enabled.
function CameraMotionStability.FilterPointerDelta(dx, dy, threshold)
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
    threshold = math.max(0, tonumber(threshold) or 0)
    if dx * dx + dy * dy < threshold * threshold then return 0, 0 end
    return dx, dy
end

-- Pinch distances fluctuate slightly even when both fingers are held still.
-- Comparing in logarithmic space makes the dead zone symmetric for zooming in
-- and zooming out.
function CameraMotionStability.FilterPinchFactor(factor, minimumLogDelta)
    factor = tonumber(factor) or 1
    if factor <= 0 then return 1 end
    if math.abs(math.log(factor)) < math.max(0, tonumber(minimumLogDelta) or 0) then
        return 1
    end
    return factor
end

-- Converts the old 60-Hz inertia constants into a time-based step. At 60 FPS
-- it is exactly the old behaviour; at 20/30/120 FPS it covers the same amount
-- of movement over the same wall-clock time instead of speeding up or stalling.
function CameraMotionStability.DampedStep(retentionPerFrame, totalApplication, timeStep)
    local retention = Clamp(tonumber(retentionPerFrame) or 0, 0, 1)
    local elapsedFrames = Clamp(tonumber(timeStep) or 0, 0, 0.1) * 60
    local retained = retention ^ elapsedFrames
    local applied = math.max(0, tonumber(totalApplication) or 0) * (1 - retained)
    return applied, retained
end

function CameraMotionStability.UpdateOrbitSample(sample, targetX, targetY, targetZ,
        theta, phi, radius, force)
    sample = sample or {}
    local changed = force == true or sample.mode ~= "orbit"
    if not changed then
        local positionThreshold = 0.35
        local angleThreshold = math.rad(0.45)
        local radiusThreshold = math.max(0.25, math.abs(tonumber(radius) or 0) * 0.006)
        changed = DistanceSquared(targetX, targetY, targetZ,
                sample.x, sample.y, sample.z) >= positionThreshold * positionThreshold
            or AngularDistance(theta, sample.theta) >= angleThreshold
            or AngularDistance(phi, sample.phi) >= angleThreshold
            or math.abs((tonumber(radius) or 0) - (tonumber(sample.radius) or 0)) >= radiusThreshold
    end
    if changed then
        sample.mode = "orbit"
        sample.x, sample.y, sample.z = targetX, targetY, targetZ
        sample.theta, sample.phi, sample.radius = theta, phi, radius
    end
    return changed, sample
end

function CameraMotionStability.UpdateFirstPersonSample(sample, x, y, z, yaw, pitch, force)
    sample = sample or {}
    local changed = force == true or sample.mode ~= "first-person"
    if not changed then
        local positionThreshold = 0.30
        local angleThreshold = math.rad(0.45)
        changed = DistanceSquared(x, y, z,
                sample.x, sample.y, sample.z) >= positionThreshold * positionThreshold
            or AngularDistance(yaw, sample.yaw) >= angleThreshold
            or AngularDistance(pitch, sample.pitch) >= angleThreshold
    end
    if changed then
        sample.mode = "first-person"
        sample.x, sample.y, sample.z = x, y, z
        sample.yaw, sample.pitch = yaw, pitch
    end
    return changed, sample
end

return CameraMotionStability
