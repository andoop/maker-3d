-- Shared screen/viewport conversion for 3D picking.
--
-- Camera:GetScreenRay consumes coordinates normalized inside the active
-- viewport. Keeping that normalization beside the matching NDC-to-screen
-- projection prevents high-DPR phones and inset sub-viewports from using a
-- different coordinate path for rendering and touch picking.

local ViewportCoordinates = {}

local function Dimension(value)
    return math.max(1, tonumber(value) or 1)
end

function ViewportCoordinates.Normalize(rect, x, y)
    rect = rect or {}
    local left, top = tonumber(rect.left) or 0, tonumber(rect.top) or 0
    local width = Dimension((tonumber(rect.right) or left + 1) - left)
    local height = Dimension((tonumber(rect.bottom) or top + 1) - top)
    return ((tonumber(x) or left) - left) / width,
        ((tonumber(y) or top) - top) / height
end

function ViewportCoordinates.FromNdc(rect, x, y)
    rect = rect or {}
    local left, top = tonumber(rect.left) or 0, tonumber(rect.top) or 0
    local width = Dimension((tonumber(rect.right) or left + 1) - left)
    local height = Dimension((tonumber(rect.bottom) or top + 1) - top)
    return left + ((tonumber(x) or -1) + 1) * 0.5 * width,
        top + (1 - (tonumber(y) or 1)) * 0.5 * height
end

function ViewportCoordinates.GetScreenRay(camera, rect, x, y)
    local native = camera and camera.getCamera and camera:getCamera() or camera
    if not native or not native.GetScreenRay then return nil end
    local normalizedX, normalizedY = ViewportCoordinates.Normalize(rect, x, y)
    return native:GetScreenRay(normalizedX, normalizedY)
end

function ViewportCoordinates.IsTapMovement(startX, startY, endX, endY, threshold)
    local dx = (tonumber(endX) or 0) - (tonumber(startX) or 0)
    local dy = (tonumber(endY) or 0) - (tonumber(startY) or 0)
    local limit = math.max(0, tonumber(threshold) or 0)
    return dx * dx + dy * dy <= limit * limit
end

function ViewportCoordinates.NormalizePanDelta(dx, dy, _isGesture, _isMobile)
    -- Mouse, desktop trackpad and direct-touch midpoint deltas all represent
    -- screen-space direct manipulation. Preserve both axes here; callers own
    -- any navigation-specific convention before entering the shared path.
    return tonumber(dx) or 0, tonumber(dy) or 0
end

function ViewportCoordinates.RotationDelta(startAngle, currentAngle, reverse)
    local delta = (tonumber(currentAngle) or 0) - (tonumber(startAngle) or 0)
    local fullTurn = math.pi * 2
    while delta > math.pi do delta = delta - fullTurn end
    while delta < -math.pi do delta = delta + fullTurn end
    return reverse and -delta or delta
end

return ViewportCoordinates
