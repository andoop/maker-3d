local MobileDetailProjection = {}

function MobileDetailProjection.InView(ndcX, ndcY, forwardDepth, cameraFar, border)
    ndcX, ndcY = tonumber(ndcX), tonumber(ndcY)
    forwardDepth = tonumber(forwardDepth)
    cameraFar = math.max(0.1, tonumber(cameraFar) or 1000)
    border = math.max(1, tonumber(border) or 1.16)
    if not ndcX or not ndcY or not forwardDepth
        or ndcX ~= ndcX or ndcY ~= ndcY or forwardDepth ~= forwardDepth then return false end
    -- Perspective division cannot identify a point behind the eye by NDC z
    -- alone: those values fold back towards +1. Signed camera-forward depth is
    -- therefore the authoritative front/far-plane test.
    return forwardDepth > 0.02 and forwardDepth <= cameraFar
        and ndcX >= -border and ndcX <= border
        and ndcY >= -border and ndcY <= border
end

function MobileDetailProjection.CoverageKey(ndcX, ndcY)
    local function Clamp(value, minimum, maximum)
        return math.max(minimum, math.min(maximum, value))
    end
    local column = Clamp(math.floor(((tonumber(ndcX) or 0) + 1) * 2.5), 0, 4)
    local row = Clamp(math.floor((1 - (tonumber(ndcY) or 0)) * 1.5), 0, 2)
    return tostring(column) .. ":" .. tostring(row)
end

return MobileDetailProjection
