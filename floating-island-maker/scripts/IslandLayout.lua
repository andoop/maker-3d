local TerrainCatalog = require("IslandTerrainCatalog")

local IslandLayout = {}
local Layout = {}
Layout.__index = Layout

IslandLayout.TERRAIN_PRESET = TerrainCatalog.DEFAULT_ID
IslandLayout.LEGACY_WORLD_SCALE = 2

local MINIMUM_ZOOM_OUT_RADIUS = 320
local OVERVIEW_ZOOM_OUT_FACTOR = 1.80
local FAR_CLIP_SAFETY_RATIO = 0.55

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
end

local function RadiusX(island)
    return math.max(0.01, tonumber(island and (island.radiusX or island.radius)) or 0.01)
end

local function RadiusZ(island)
    return math.max(0.01, tonumber(island and (island.radiusZ or island.radius)) or 0.01)
end

local function GroundY(island)
    return tonumber(island and island.groundY) or 0.42
end

local function PointInIsland(layout, island, x, z, padding, includeEdgeInset)
    padding = math.max(0, tonumber(padding) or 0)
    local inset = includeEdgeInset == false and 0 or layout.edgeInset
    local rx, rz = RadiusX(island) - inset - padding, RadiusZ(island) - inset - padding
    if rx <= 0 or rz <= 0 then return false end
    local dx, dz = x - island.x, z - island.z
    return dx * dx / (rx * rx) + dz * dz / (rz * rz) <= 1
end

local function BoundaryRadius(island, axisX, axisZ, inset)
    inset = math.max(0, tonumber(inset) or 0)
    local rx, rz = RadiusX(island) - inset, RadiusZ(island) - inset
    if rx <= 0 or rz <= 0 then return 0 end
    local denominator = math.sqrt(axisX * axisX / (rx * rx) + axisZ * axisZ / (rz * rz))
    if denominator < 0.000001 then return 0 end
    return 1 / denominator
end

local function ProjectionRadius(footprint, axisX, axisZ)
    return footprint.halfWidth * math.abs(footprint.axisXx * axisX + footprint.axisXz * axisZ)
        + footprint.halfDepth * math.abs(footprint.axisZx * axisX + footprint.axisZz * axisZ)
end

local function Overlaps(first, second)
    local deltaX, deltaZ = second.x - first.x, second.z - first.z
    local gap = 0.04
    for _, axis in ipairs({
        { first.axisXx, first.axisXz }, { first.axisZx, first.axisZz },
        { second.axisXx, second.axisXz }, { second.axisZx, second.axisZz },
    }) do
        local separation = math.abs(deltaX * axis[1] + deltaZ * axis[2])
        local occupied = ProjectionRadius(first, axis[1], axis[2])
            + ProjectionRadius(second, axis[1], axis[2]) - gap
        if separation >= occupied then return false end
    end
    return true
end

local TRANSPARENT_MATERIALS = { glass = true, water = true, fire = true }

local function AssetHeight(asset, scale)
    local bounds = asset and asset.bounds or {}
    local size = bounds.size or {}
    return math.max(0.01, (tonumber(size[2]) or 1) * (tonumber(scale) or 1))
end

-- A hollow house can surround a chair without hiding it. Whole-model bounds
-- therefore only count as an occluder when the authored geometry substantially
-- fills those bounds. This keeps the placement rule permissive while still
-- preventing an object from being lost inside a rock, tree crown or duplicate.
local function AssetVisualDensity(asset)
    local bounds = asset and asset.bounds or {}
    local size = bounds.size or {}
    local boundsVolume = math.max(0.001,
        (tonumber(size[1]) or 1) * (tonumber(size[2]) or 1) * (tonumber(size[3]) or 1))
    local blocks = type(asset and asset.blocks) == "table" and asset.blocks or {}
    if #blocks == 0 then return 1 end
    local occupied = 0
    for _, block in ipairs(blocks) do
        local material = tostring(block.materialId or block.material or "solid")
        local role = tostring(block.collisionRole or "")
        if not TRANSPARENT_MATERIALS[material] and role ~= "fluid" then
            local blockSize = block.size or {}
            occupied = occupied + math.max(0,
                (tonumber(blockSize[1]) or 1) * (tonumber(blockSize[2]) or 1)
                    * (tonumber(blockSize[3]) or 1))
        end
    end
    return math.min(1, occupied / boundsVolume)
end

local function InnerSamples(footprint, amount)
    amount = tonumber(amount) or 0.9
    local samples = { { x = footprint.x, z = footprint.z } }
    for _, signs in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
        samples[#samples + 1] = {
            x = footprint.x + signs[1] * footprint.halfWidth * footprint.axisXx * amount
                + signs[2] * footprint.halfDepth * footprint.axisZx * amount,
            z = footprint.z + signs[1] * footprint.halfWidth * footprint.axisXz * amount
                + signs[2] * footprint.halfDepth * footprint.axisZz * amount,
        }
    end
    return samples
end

local function MostlyContained(layout, candidate, candidateMinimumY, candidateMaximumY,
        other, otherMinimumY, otherMaximumY)
    if not Overlaps(candidate, other) then return false end
    for _, point in ipairs(InnerSamples(candidate, 0.9)) do
        if not layout:ContainsInFootprint(other, point.x, point.z, 0) then return false end
    end
    local candidateHeight = math.max(0.001, candidateMaximumY - candidateMinimumY)
    local vertical = math.max(0,
        math.min(candidateMaximumY, otherMaximumY) - math.max(candidateMinimumY, otherMinimumY))
    return vertical / candidateHeight >= 0.90
end

local function VectorPart(vector, name, index)
    if vector == nil then return nil end
    return tonumber(vector[name]) or tonumber(vector[index])
end

local function NewLayout(terrainId)
    local preset = TerrainCatalog.Get(terrainId)
    local self = setmetatable({
        id = preset.id,
        terrainId = preset.id,
        name = preset.name,
        description = preset.description,
        edgeInset = math.max(0, tonumber(preset.edgeInset) or 0.32),
        overview = preset.overview,
        camera = preset.camera,
        renderDistance = preset.renderDistance,
        islands = preset.islands,
        bridges = preset.bridges,
        _islandById = {},
        _bridgeMetrics = {},
    }, Layout)
    for _, island in ipairs(self.islands) do
        island.radiusX, island.radiusZ = RadiusX(island), RadiusZ(island)
        island.radius = tonumber(island.radius) or math.max(island.radiusX, island.radiusZ)
        island.groundY = GroundY(island)
        self._islandById[tostring(island.id)] = island
    end
    -- Uppercase aliases let existing data generators migrate one call site at
    -- a time while runtime code uses the clearer lowercase instance fields.
    self.ISLANDS, self.BRIDGES = self.islands, self.bridges
    self.RENDER_DISTANCE = self.renderDistance
    self.TERRAIN_PRESET = self.id
    self.EDGE_INSET = self.edgeInset
    self.RADIUS = self.islands[1] and self.islands[1].radius or 0
    return self
end

function Layout:GetBridgeMetrics(bridgeOrId)
    local bridge = type(bridgeOrId) == "table" and bridgeOrId or nil
    if not bridge then
        local requested = tostring(bridgeOrId or "")
        for _, candidate in ipairs(self.bridges) do
            if tostring(candidate.id or "") == requested then bridge = candidate; break end
        end
    end
    if not bridge then return nil end
    local cacheKey = bridge.id or (tostring(bridge.from) .. ":" .. tostring(bridge.to))
    if self._bridgeMetrics[cacheKey] then return self._bridgeMetrics[cacheKey] end
    local first, second = self:GetIsland(bridge.from), self:GetIsland(bridge.to)
    if not first or not second then return nil end
    local dx, dz = second.x - first.x, second.z - first.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance < 0.000001 then return nil end
    local ux, uz = dx / distance, dz / distance
    -- Island silhouettes use independently inset X/Z radii, so bridge
    -- landings must use that same ellipse equation. Subtracting a scalar from
    -- the original directional radius leaves small but real gaps on elongated
    -- islands that can stop a first-person capsule at the seam.
    local landingOverlap = math.max(0, tonumber(bridge.landingOverlap) or 0.12)
    local firstRadius = BoundaryRadius(first, ux, uz, self.edgeInset)
    local secondRadius = BoundaryRadius(second, -ux, -uz, self.edgeInset)
    local startDistance = math.max(0, firstRadius - landingOverlap)
    local endDistance = math.min(distance, distance - secondRadius + landingOverlap)
    if endDistance < startDistance then
        local middle = (startDistance + endDistance) * 0.5
        startDistance, endDistance = middle, middle
    end
    local span = math.max(0.000001, endDistance - startDistance)
    local result = {
        bridge = bridge,
        first = first,
        second = second,
        ux = ux, uz = uz,
        distance = distance,
        startDistance = startDistance,
        endDistance = endDistance,
        length = span,
        startX = first.x + ux * startDistance,
        startZ = first.z + uz * startDistance,
        endX = first.x + ux * endDistance,
        endZ = first.z + uz * endDistance,
        startY = GroundY(first),
        endY = GroundY(second),
        landingOverlap = landingOverlap,
    }
    result.slope = (result.endY - result.startY) / span
    self._bridgeMetrics[cacheKey] = result
    return result
end

function Layout:_PointInBridge(bridge, x, z, padding)
    local metrics = self:GetBridgeMetrics(bridge)
    if not metrics then return nil end
    padding = math.max(0, tonumber(padding) or 0)
    local halfWidth = math.max(0, (tonumber(bridge.halfWidth) or 0) - padding)
    if halfWidth <= 0 then return nil end
    local dx, dz = x - metrics.first.x, z - metrics.first.z
    local along = dx * metrics.ux + dz * metrics.uz
    -- Recompute the landing against the caller's inset ellipse. This remains
    -- exact for non-circular islands, unlike extending by a scalar padding.
    local firstBoundary = BoundaryRadius(
        metrics.first, metrics.ux, metrics.uz, self.edgeInset + padding)
    local secondBoundary = BoundaryRadius(
        metrics.second, -metrics.ux, -metrics.uz, self.edgeInset + padding)
    local landingOverlap = metrics.landingOverlap or 0.12
    local bridgeStart = math.max(0, firstBoundary - landingOverlap)
    local bridgeEnd = math.min(metrics.distance,
        metrics.distance - secondBoundary + landingOverlap)
    if along < bridgeStart or along > bridgeEnd then return nil end
    local across = math.abs(-dx * metrics.uz + dz * metrics.ux)
    if across > halfWidth then return nil end
    local amount = (along - metrics.startDistance) / metrics.length
    return math.max(0, math.min(1, amount)), metrics
end

function Layout:ContainsPoint(x, z, padding)
    return self:SurfaceAt(x, z, padding) ~= nil
end

function Layout:SurfaceAt(x, z, padding)
    x, z = tonumber(x) or 0, tonumber(z) or 0
    padding = math.max(0, tonumber(padding) or 0)
    local island = self:IslandAt(x, z, padding)
    if island then return GroundY(island), "island", island end
    for _, bridge in ipairs(self.bridges) do
        local amount, metrics = self:_PointInBridge(bridge, x, z, padding)
        if amount then
            return metrics.startY + (metrics.endY - metrics.startY) * amount, "bridge", bridge
        end
    end
    return nil
end

function Layout:RaycastGround(ray, padding)
    if type(ray) ~= "table" and type(ray) ~= "userdata" then return nil end
    padding = math.max(0, tonumber(padding) or 0)
    local origin, direction = ray.origin, ray.direction
    local ox, oy, oz = VectorPart(origin, "x", 1), VectorPart(origin, "y", 2), VectorPart(origin, "z", 3)
    local dx, dy, dz = VectorPart(direction, "x", 1), VectorPart(direction, "y", 2), VectorPart(direction, "z", 3)
    if not ox or not oy or not oz or not dx or not dy or not dz then return nil end
    local nearest
    local function Consider(distance, x, y, z, kind, source)
        if distance < 0 or distance ~= distance or distance == math.huge then return end
        if not nearest or distance < nearest.distance then
            nearest = {
                x = x, y = y, z = z, distance = distance,
                kind = kind, id = source and source.id, source = source,
            }
        end
    end

    if math.abs(dy) >= 0.000001 then
        for _, island in ipairs(self.islands) do
            local y = GroundY(island)
            local distance = (y - oy) / dy
            if distance >= 0 then
                local x, z = ox + dx * distance, oz + dz * distance
                if PointInIsland(self, island, x, z, padding, true) then
                    Consider(distance, x, y, z, "island", island)
                end
            end
        end
    end

    for _, bridge in ipairs(self.bridges) do
        local metrics = self:GetBridgeMetrics(bridge)
        if metrics then
            local directionalSlope = metrics.slope * (dx * metrics.ux + dz * metrics.uz)
            local denominator = dy - directionalSlope
            if math.abs(denominator) >= 0.000001 then
                local originAlong = (ox - metrics.startX) * metrics.ux + (oz - metrics.startZ) * metrics.uz
                local surfaceAtOrigin = metrics.startY + metrics.slope * originAlong
                local distance = (surfaceAtOrigin - oy) / denominator
                if distance >= 0 then
                    local x, z = ox + dx * distance, oz + dz * distance
                    local amount = self:_PointInBridge(bridge, x, z, padding)
                    -- Match SurfaceAt's island-first rule inside the short
                    -- landing overlap so placement rays and model grounding
                    -- cannot disagree by the bridge slope at the seam.
                    if amount and not self:IslandAt(x, z, padding) then
                        local y = metrics.startY + (metrics.endY - metrics.startY) * amount
                        Consider(distance, x, y, z, "bridge", bridge)
                    end
                end
            end
        end
    end
    return nearest
end

function Layout:IslandAt(x, z, padding)
    x, z = tonumber(x) or 0, tonumber(z) or 0
    local best, bestDistance = nil, math.huge
    for _, island in ipairs(self.islands) do
        if PointInIsland(self, island, x, z, padding, padding ~= nil) then
            local dx, dz = x - island.x, z - island.z
            local distance = dx * dx / (RadiusX(island) ^ 2) + dz * dz / (RadiusZ(island) ^ 2)
            if distance < bestDistance then best, bestDistance = island, distance end
        end
    end
    return best
end

function Layout:GetIsland(id)
    return self._islandById[tostring(id or "")]
end

function Layout:Overview()
    return Copy(self.overview)
end

function Layout:MaximumOrbitRadius()
    local overviewRadius = math.max(1, tonumber(self.overview and self.overview.radius) or 1)
    local maximum = math.max(MINIMUM_ZOOM_OUT_RADIUS,
        overviewRadius * OVERVIEW_ZOOM_OUT_FACTOR)
    local cameraFar = tonumber(self.renderDistance and self.renderDistance.cameraFar)
    if cameraFar and cameraFar > 0 then
        maximum = math.min(maximum, cameraFar * FAR_CLIP_SAFETY_RATIO)
    end
    return math.max(6, maximum)
end

function Layout:DefaultGroundY()
    local primary = self.islands[1]
    return GroundY(primary)
end

function Layout:MinimumGroundY()
    local minimum = math.huge
    for _, island in ipairs(self.islands) do minimum = math.min(minimum, GroundY(island)) end
    return minimum == math.huge and 0.42 or minimum
end

function Layout:MaximumGroundY()
    local maximum = -math.huge
    for _, island in ipairs(self.islands) do maximum = math.max(maximum, GroundY(island)) end
    return maximum == -math.huge and 0.42 or maximum
end

function Layout:ContainsInFootprint(footprint, x, z, padding)
    if not footprint then return false end
    padding = math.max(0, tonumber(padding) or 0)
    local dx, dz = x - footprint.x, z - footprint.z
    local localX = math.abs(dx * footprint.axisXx + dz * footprint.axisXz)
    local localZ = math.abs(dx * footprint.axisZx + dz * footprint.axisZz)
    return localX <= footprint.halfWidth + padding and localZ <= footprint.halfDepth + padding
end

function Layout:Footprint(instance, asset, x, z, rotationY, scale)
    asset = asset or (instance and instance.renderAsset)
    local bounds = asset and asset.bounds
        or { min = { -0.5, 0, -0.5 }, max = { 0.5, 1, 0.5 }, size = { 1, 1, 1 } }
    local modelScale = scale or instance and instance.scale or 1
    local width = math.max(0.2, (bounds.size[1] or 1) * modelScale)
    local depth = math.max(0.2, (bounds.size[3] or 1) * modelScale)
    local angle = rotationY or instance and instance.rotationY or 0
    local cosAngle, sinAngle = math.cos(angle), math.sin(angle)
    local centerX = (((bounds.min or {})[1] or -0.5) + ((bounds.max or {})[1] or 0.5)) * 0.5 * modelScale
    local centerZ = (((bounds.min or {})[3] or -0.5) + ((bounds.max or {})[3] or 0.5)) * 0.5 * modelScale
    local originX = x or instance and instance.x or 0
    local originZ = z or instance and instance.z or 0
    local halfWidth, halfDepth = width * 0.5, depth * 0.5
    local axisXx, axisXz = cosAngle, -sinAngle
    local axisZx, axisZz = sinAngle, cosAngle
    local result = {
        x = originX + centerX * cosAngle + centerZ * sinAngle,
        z = originZ - centerX * sinAngle + centerZ * cosAngle,
        halfWidth = halfWidth,
        halfDepth = halfDepth,
        axisXx = axisXx, axisXz = axisXz,
        axisZx = axisZx, axisZz = axisZz,
    }
    result.hx = halfWidth * math.abs(axisXx) + halfDepth * math.abs(axisZx)
    result.hz = halfWidth * math.abs(axisXz) + halfDepth * math.abs(axisZz)
    result.corners = {}
    for _, signs in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
        result.corners[#result.corners + 1] = {
            x = result.x + signs[1] * halfWidth * axisXx + signs[2] * halfDepth * axisZx,
            z = result.z + signs[1] * halfWidth * axisXz + signs[2] * halfDepth * axisZz,
        }
    end
    return result
end

function Layout:IsFootprintSupported(footprint, tolerance)
    if not footprint then return false, "missing_footprint" end
    tolerance = math.max(0, tonumber(tolerance) or 0.08)
    local centerY = self:SurfaceAt(footprint.x, footprint.z, 0)
    if centerY == nil then return false, "outside_island" end
    local minimumY, maximumY = centerY, centerY
    for _, corner in ipairs(footprint.corners or {}) do
        local groundY = self:SurfaceAt(corner.x, corner.z, 0)
        if groundY == nil then return false, "outside_island" end
        minimumY, maximumY = math.min(minimumY, groundY), math.max(maximumY, groundY)
    end
    if maximumY - minimumY > tolerance then return false, "uneven_ground" end
    return true, nil, (minimumY + maximumY) * 0.5
end

function Layout:SelectionFocusRadius(asset, scale, currentRadius, aspect)
    local bounds = asset and asset.bounds or {}
    local size = bounds.size or { 1, 1, 1 }
    local modelScale = math.max(0.1, tonumber(scale) or 1)
    local width = math.max(0.2, tonumber(size[1]) or 1) * modelScale
    local height = math.max(0.2, tonumber(size[2]) or 1) * modelScale
    local depth = math.max(0.2, tonumber(size[3]) or 1) * modelScale
    local verticalHalfFov = math.rad(20)
    local viewportAspect = math.max(0.35, tonumber(aspect) or 1)
    local horizontalHalfFov = math.atan(math.tan(verticalHalfFov) * viewportAspect)
    local limitingHalfFov = math.min(verticalHalfFov, horizontalHalfFov)
    local boundingRadius = math.sqrt(width * width + height * height + depth * depth) * 0.5
    local desired = math.max(8, math.min(180, boundingRadius / math.sin(limitingHalfFov) * 1.12))
    local current = tonumber(currentRadius) or desired
    if current <= desired * 1.2 then return current end
    return desired
end

function Layout:IsPlacementValid(instances, asset, x, z, rotationY, scale, ignoreId, resolveAsset, y)
    if not asset then return false, "missing_asset" end
    local footprint = self:Footprint(nil, asset, x, z, rotationY, scale)
    local supported, supportReason, groundY = self:IsFootprintSupported(footprint)
    if not supported then return false, supportReason end
    local candidateMinimumY = groundY + (tonumber(y) or 0)
    local candidateMaximumY = candidateMinimumY + AssetHeight(asset, scale)
    for _, instance in ipairs(instances or {}) do
        if instance.id ~= ignoreId then
            local otherAsset = instance.renderAsset or (resolveAsset and resolveAsset(instance))
            if otherAsset and AssetVisualDensity(otherAsset) >= 0.60 then
                local other = self:Footprint(instance, otherAsset)
                local otherGroundY = self:SurfaceAt(instance.x or other.x, instance.z or other.z, 0)
                    or self:DefaultGroundY()
                local otherMinimumY = otherGroundY + (tonumber(instance.y) or 0)
                local otherMaximumY = otherMinimumY + AssetHeight(otherAsset, instance.scale)
                if MostlyContained(self, footprint, candidateMinimumY, candidateMaximumY,
                    other, otherMinimumY, otherMaximumY) then
                    return false, "buried", instance.id
                end
            end
        end
    end
    return true, nil, nil, groundY
end

function IslandLayout.ResolveId(terrainId)
    return TerrainCatalog.ResolveId(terrainId)
end

function IslandLayout.Resolve(terrainId)
    return NewLayout(terrainId)
end

function IslandLayout.List()
    return TerrainCatalog.List()
end

local DEFAULT = NewLayout(TerrainCatalog.DEFAULT_ID)

function IslandLayout.Default()
    return DEFAULT
end

-- Backward-compatible facade. Existing runtime code keeps using the default
-- three-island layout until it is explicitly handed a resolved layout object.
IslandLayout.ISLANDS = DEFAULT.islands
IslandLayout.BRIDGES = DEFAULT.bridges
IslandLayout.RENDER_DISTANCE = DEFAULT.renderDistance
IslandLayout.RADIUS = DEFAULT.RADIUS
IslandLayout.EDGE_INSET = DEFAULT.edgeInset

function IslandLayout.ContainsPoint(...) return DEFAULT:ContainsPoint(...) end
function IslandLayout.SurfaceAt(...) return DEFAULT:SurfaceAt(...) end
function IslandLayout.RaycastGround(...) return DEFAULT:RaycastGround(...) end
function IslandLayout.IslandAt(...) return DEFAULT:IslandAt(...) end
function IslandLayout.GetIsland(...) return DEFAULT:GetIsland(...) end
function IslandLayout.GetBridgeMetrics(...) return DEFAULT:GetBridgeMetrics(...) end
function IslandLayout.Overview(...) return DEFAULT:Overview(...) end
function IslandLayout.MaximumOrbitRadius(...) return DEFAULT:MaximumOrbitRadius(...) end
function IslandLayout.DefaultGroundY(...) return DEFAULT:DefaultGroundY(...) end
function IslandLayout.MinimumGroundY(...) return DEFAULT:MinimumGroundY(...) end
function IslandLayout.MaximumGroundY(...) return DEFAULT:MaximumGroundY(...) end
function IslandLayout.ContainsInFootprint(...) return DEFAULT:ContainsInFootprint(...) end
function IslandLayout.Footprint(...) return DEFAULT:Footprint(...) end
function IslandLayout.IsFootprintSupported(...) return DEFAULT:IsFootprintSupported(...) end
function IslandLayout.SelectionFocusRadius(...) return DEFAULT:SelectionFocusRadius(...) end
function IslandLayout.IsPlacementValid(...) return DEFAULT:IsPlacementValid(...) end

IslandLayout.Layout = Layout

return IslandLayout
