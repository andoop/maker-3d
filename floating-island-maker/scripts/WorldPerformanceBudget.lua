local ModelGeometry = require("ModelGeometry")

local WorldPerformanceBudget = {}

-- These figures are render-quality watermarks, not authoring limits. Players
-- may keep building beyond them; the renderer preserves every block and only
-- stops adding more shadow casters once the device-friendly budget is full.
WorldPerformanceBudget.MOBILE = {
    blocks = 1200,
    shadows = 192,
    shadowMapSize = 512,
    minimumDetailShadowSpan = 0.55,
    minimumDetailShadowVolume = 0.12,
}
WorldPerformanceBudget.DESKTOP = {
    blocks = 2400,
    shadows = 700,
    shadowMapSize = 2048,
    minimumDetailShadowSpan = 0,
    minimumDetailShadowVolume = 0,
}

local function AddBlocks(cost, blocks)
    for _, block in ipairs(blocks or {}) do
        cost.blocks = cost.blocks + 1
        if ModelGeometry.ShouldCastShadow(block) then cost.shadows = cost.shadows + 1 end
    end
end

function WorldPerformanceBudget.Measure(instances, candidateBlocks)
    local cost = { blocks = 0, shadows = 0 }
    for _, instance in ipairs(instances or {}) do
        AddBlocks(cost, instance.renderAsset and instance.renderAsset.blocks or instance.blocks)
    end
    AddBlocks(cost, candidateBlocks)
    return cost
end

function WorldPerformanceBudget.CanAdd(instances, candidateBlocks, mobile)
    local cost = WorldPerformanceBudget.Measure(instances, candidateBlocks)
    local limit = mobile and WorldPerformanceBudget.MOBILE or WorldPerformanceBudget.DESKTOP
    -- Kept for compatibility with older callers. Placement is never rejected:
    -- dense scenes are handled by instancing and adaptive shadow quality.
    return true, cost, limit
end

function WorldPerformanceBudget.ShadowMapSize(mobile)
    local limit = mobile and WorldPerformanceBudget.MOBILE or WorldPerformanceBudget.DESKTOP
    return limit.shadowMapSize
end

-- StaticModelGroup uploads one transform record per member. Smaller mobile
-- shards avoid oversized transient instance buffers on drivers that otherwise
-- show tiled/duplicated frames under dense vegetation, while desktop retains
-- the more aggressive draw-call reduction.
function WorldPerformanceBudget.InstanceGroupLimit(mobile)
    return mobile and 48 or 256
end

-- A 512px phone shadow map spread over an entire archipelago cannot resolve
-- roof trims, grass and railings. At overview distance those sub-pixel
-- shadows alias as the sun or camera moves and can make the whole island look
-- as though it is trembling. Keep dynamic shadows for close inspection and
-- first-person play, with hysteresis around the overview transition.
function WorldPerformanceBudget.DynamicShadowsEnabled(
        mobile, firstPerson, radius, overviewRadius, currentlyEnabled)
    if not mobile or firstPerson then return true end
    local overview = math.max(1, tonumber(overviewRadius) or 118)
    local threshold = math.max(82, math.min(120, overview * 0.68))
    local distance = math.max(0, tonumber(radius) or threshold)
    if currentlyEnabled == true then return distance < threshold * 1.08 end
    if currentlyEnabled == false then return distance < threshold * 0.92 end
    return distance < threshold
end

-- Reserve one model block in the adaptive shadow budget. The returned cursor
-- makes the function deterministic and engine-free, which also lets project
-- restore choose the same casters on every run.
function WorldPerformanceBudget.ReserveShadow(block, mobile, used)
    used = math.max(0, tonumber(used) or 0)
    if not ModelGeometry.ShouldCastShadow(block) then return false, used end
    local limit = mobile and WorldPerformanceBudget.MOBILE or WorldPerformanceBudget.DESKTOP
    if used >= limit.shadows then return false, used end

    if mobile then
        local rawX, rawY, rawZ = ModelGeometry.Size(block)
        local sx, sy, sz = math.abs(rawX), math.abs(rawY), math.abs(rawZ)
        local span = math.max(sx, sy, sz)
        local volume = sx * sy * sz
        if span < limit.minimumDetailShadowSpan
            and volume < limit.minimumDetailShadowVolume then
            return false, used
        end
    end
    return true, used + 1
end

return WorldPerformanceBudget
