local IslandPortalNetwork = {}

IslandPortalNetwork.SCHEMA = "island-portal-link/v1"

local sequence = 0

-- Runtime travel is intentionally guarded outside IslandWorld. A portal trip can
-- replace the world that queued it, so a cooldown stored only on that world is
-- lost during the hand-off. Keeping this tiny gate independent of either scene
-- makes duplicate click/walk activations harmless while the destination is being
-- restored, and gives tests a deterministic way to exercise repeated round trips.
function IslandPortalNetwork.CreateTransitGate(options)
    options = type(options) == "table" and options or {}
    local gate = {
        inFlight = false,
        cooldown = 0,
        generation = 0,
        successCooldown = math.max(0, tonumber(options.successCooldown) or 1.2),
        failureCooldown = math.max(0, tonumber(options.failureCooldown) or 0.24),
        activeKey = nil,
    }

    function gate:Update(timeStep)
        local delta = math.max(0, math.min(0.25, tonumber(timeStep) or 0))
        self.cooldown = math.max(0, (tonumber(self.cooldown) or 0) - delta)
        return self.cooldown
    end

    function gate:TryBegin(key)
        if self.inFlight then return nil, "portal_transition_in_flight" end
        if (tonumber(self.cooldown) or 0) > 0 then return nil, "portal_transition_cooldown" end
        self.generation = self.generation + 1
        self.inFlight = true
        self.activeKey = tostring(key or "")
        return self.generation
    end

    function gate:Finish(token, succeeded)
        if not self.inFlight or tonumber(token) ~= self.generation then return false end
        self.inFlight = false
        self.activeKey = nil
        local duration = succeeded == true and self.successCooldown or self.failureCooldown
        self.cooldown = math.max(tonumber(self.cooldown) or 0, duration)
        return true
    end

    function gate:Reset()
        self.inFlight, self.cooldown, self.activeKey = false, 0, nil
    end

    function gate:IsBlocked()
        return self.inFlight == true or (tonumber(self.cooldown) or 0) > 0
    end

    return gate
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
end

local function CleanId(value)
    local result = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    return result
end

local function CleanInstanceId(value)
    local result = tonumber(value)
    if not result or result < 1 then return nil end
    return math.floor(result)
end

local function ProjectIndex(collection)
    local result = {}
    local items = type(collection) == "table" and type(collection.items) == "table"
        and collection.items or {}
    for _, project in ipairs(items) do
        local id = CleanId(project and project.islandId)
        if id ~= "" and not result[id] then result[id] = project end
    end
    return result
end

local function InstanceIndex(project)
    local result = {}
    local instances = type(project) == "table" and type(project.instances) == "table"
        and project.instances or {}
    for _, instance in ipairs(instances) do
        local id = CleanInstanceId(instance and instance.id)
        if id and not result[id] then result[id] = instance end
    end
    return result
end

local function FindProject(collection, islandId)
    return ProjectIndex(collection)[CleanId(islandId)]
end

local function FindInstance(project, instanceId)
    local id = CleanInstanceId(instanceId)
    if not id then return nil end
    return InstanceIndex(project)[id]
end

local function FindInstanceIndex(project, instanceId)
    local target = CleanInstanceId(instanceId)
    if not target then return nil end
    local instances = type(project) == "table" and type(project.instances) == "table"
        and project.instances or {}
    for index, instance in ipairs(instances) do
        if CleanInstanceId(instance.id) == target then return index, instance end
    end
    return nil
end

local function NextInstanceId(project)
    local maximum = 0
    local instances = type(project) == "table" and type(project.instances) == "table"
        and project.instances or {}
    for _, instance in ipairs(instances) do
        maximum = math.max(maximum, CleanInstanceId(instance and instance.id) or 0)
    end
    return maximum + 1
end

local function TouchProject(project, now)
    if type(project) ~= "table" then return end
    project.revision = math.max(0, tonumber(project.revision) or 0) + 1
    project.updatedAt = tonumber(now) or tonumber(project.updatedAt) or 0
end

local function TouchCollection(collection, now)
    if type(collection) ~= "table" then return end
    collection.revision = math.max(0, tonumber(collection.revision) or 0) + 1
    collection.updatedAt = tonumber(now) or tonumber(collection.updatedAt) or 0
end

local function TouchProjects(projects, now)
    local seen = {}
    for _, project in ipairs(projects or {}) do
        if project and not seen[project] then
            seen[project] = true
            TouchProject(project, now)
        end
    end
end

local function ExistingLinkIds(collection)
    local result = {}
    local items = type(collection) == "table" and type(collection.items) == "table"
        and collection.items or {}
    for _, project in ipairs(items) do
        local instances = type(project.instances) == "table" and project.instances or {}
        for _, instance in ipairs(instances) do
            local portal = type(instance.portal) == "table" and instance.portal or nil
            local id = CleanId(portal and portal.linkId)
            if id ~= "" then result[id] = true end
        end
    end
    return result
end

local function NewLinkId(collection, now)
    local used = ExistingLinkIds(collection)
    local prefix = "portal-" .. tostring(math.max(0, math.floor(tonumber(now) or 0)))
    repeat
        sequence = sequence + 1
        local candidate = prefix .. "-" .. tostring(sequence)
        if not used[candidate] then return candidate end
    until false
end

local function Binding(linkId, targetIslandId, targetInstanceId, generatedPeer)
    return {
        schema = IslandPortalNetwork.SCHEMA,
        linkId = CleanId(linkId),
        targetIslandId = CleanId(targetIslandId),
        targetInstanceId = CleanInstanceId(targetInstanceId),
        generatedPeer = generatedPeer == true,
    }
end

local function ResolveLayout(options, targetProject)
    local layout = options.layout
    if type(layout) == "function" then layout = layout(targetProject, targetProject.terrainId) end
    if not layout and type(options.resolveLayout) == "function" then
        layout = options.resolveLayout(targetProject.terrainId, targetProject)
    end
    return layout
end

local function ResolveAsset(options, assetId, versionId, instance, project)
    if type(options.resolveAsset) ~= "function" then return nil end
    return options.resolveAsset(assetId, versionId, instance, project)
end

local function ProjectionRadius(footprint, axisX, axisZ)
    return footprint.halfWidth * math.abs(footprint.axisXx * axisX + footprint.axisXz * axisZ)
        + footprint.halfDepth * math.abs(footprint.axisZx * axisX + footprint.axisZz * axisZ)
end

local function StrictFootprintOverlap(first, second, padding)
    local deltaX, deltaZ = second.x - first.x, second.z - first.z
    padding = math.max(0, tonumber(padding) or 0)
    for _, axis in ipairs({
        { first.axisXx, first.axisXz }, { first.axisZx, first.axisZz },
        { second.axisXx, second.axisXz }, { second.axisZx, second.axisZz },
    }) do
        local separation = math.abs(deltaX * axis[1] + deltaZ * axis[2])
        local occupied = ProjectionRadius(first, axis[1], axis[2])
            + ProjectionRadius(second, axis[1], axis[2]) + padding
        if separation >= occupied then return false end
    end
    return true
end

local function HasStrictClearance(layout, targetProject, portalAsset, candidate, options, ignoreId)
    local portalFootprint = layout:Footprint(nil, portalAsset,
        candidate.x, candidate.z, candidate.rotationY, candidate.scale)
    for _, other in ipairs(options._strictPortalFootprints or {}) do
        if StrictFootprintOverlap(portalFootprint, other, 0.62) then return false end
    end
    return true
end

local function StrictPortalFootprints(layout, targetProject, options, ignoreId)
    local result = {}
    for _, instance in ipairs(targetProject.instances or {}) do
        if CleanInstanceId(instance.id) ~= CleanInstanceId(ignoreId) then
            local asset = ResolveAsset(options,
                instance.assetId, instance.versionId, instance, targetProject)
            if asset then result[#result + 1] = layout:Footprint(instance, asset) end
        end
    end
    return result
end

local function CandidateValid(layout, targetProject, portalAsset, candidate, options, ignoreId)
    if not layout or type(layout.Footprint) ~= "function"
        or type(layout.IsFootprintSupported) ~= "function" then return false, "missing_layout" end
    local footprint = layout:Footprint(nil, portalAsset,
        candidate.x, candidate.z, candidate.rotationY, candidate.scale)
    local valid, reason = layout:IsFootprintSupported(footprint, 0.12)
    if valid ~= true then return false, reason end
    if not HasStrictClearance(layout, targetProject, portalAsset, candidate, options, ignoreId) then
        return false, "portal_clearance"
    end
    return true, nil
end

local function AddCandidate(result, seen, x, z, rotationY, scale, y)
    x, z = tonumber(x), tonumber(z)
    if not x or not z then return end
    local key = string.format("%.3f:%.3f", x, z)
    if seen[key] then return end
    seen[key] = true
    result[#result + 1] = {
        x = x,
        y = tonumber(y) or 0,
        z = z,
        rotationY = tonumber(rotationY) or 0,
        scale = math.max(0.1, math.min(3, tonumber(scale) or 1)),
    }
end

local function PlacementCandidates(layout, options, sourceInstance)
    local result, seen = {}, {}
    local scale = tonumber(options.targetScale) or tonumber(sourceInstance.scale) or 1
    local targetPosition = type(options.targetPosition) == "table" and options.targetPosition or {}
    AddCandidate(result, seen,
        options.targetX or targetPosition.x or targetPosition[1],
        options.targetZ or targetPosition.z or targetPosition[3],
        options.targetRotationY or targetPosition.rotationY,
        scale,
        options.targetY or targetPosition.y or targetPosition[2])

    local islands = type(layout) == "table" and (layout.islands or layout.ISLANDS) or {}
    local seed = (CleanInstanceId(sourceInstance.id) or 1) * 0.731
    local rings = { 0.62, 0.46, 0.28, 0.08, 0 }
    for islandIndex, island in ipairs(islands or {}) do
        local centerX, centerZ = tonumber(island.x) or 0, tonumber(island.z) or 0
        local radiusX = math.max(0, tonumber(island.radiusX or island.radius) or 0)
        local radiusZ = math.max(0, tonumber(island.radiusZ or island.radius) or 0)
        for _, ring in ipairs(rings) do
            local steps = ring == 0 and 1 or 16
            for step = 0, steps - 1 do
                local angle = seed + islandIndex * 0.47 + step * math.pi * 2 / steps
                local x = centerX + math.sin(angle) * radiusX * ring
                local z = centerZ + math.cos(angle) * radiusZ * ring
                local facing = math.atan(centerX - x, centerZ - z)
                AddCandidate(result, seen, x, z, facing, scale, options.targetY)
            end
        end
    end

    if #result == 0 and layout and type(layout.Overview) == "function" then
        local overview = layout:Overview() or {}
        AddCandidate(result, seen, overview.x, overview.z, 0, scale, options.targetY)
    end
    return result
end

local function FindPlacement(layout, targetProject, portalAsset, options, sourceInstance, ignoreId)
    local lastReason = "no_supported_position"
    for _, candidate in ipairs(PlacementCandidates(layout, options, sourceInstance)) do
        local valid, reason = CandidateValid(
            layout, targetProject, portalAsset, candidate, options, ignoreId)
        if valid then return candidate end
        lastReason = reason or lastReason
    end
    return nil, lastReason
end

local function RemoveInstance(project, instanceId)
    local index, instance = FindInstanceIndex(project, instanceId)
    if not index then return nil end
    table.remove(project.instances, index)
    return instance
end

local function ReciprocalPeer(collection, sourceProject, sourceInstance, binding)
    if not binding then return nil end
    local targetProject = FindProject(collection, binding.targetIslandId)
    local targetInstance = targetProject and FindInstance(targetProject, binding.targetInstanceId) or nil
    local peer = targetInstance and IslandPortalNetwork.NormalizeBinding(targetInstance.portal) or nil
    if not targetProject or not targetInstance or not peer then return nil end
    if peer.linkId ~= binding.linkId
        or peer.targetIslandId ~= CleanId(sourceProject.islandId)
        or peer.targetInstanceId ~= CleanInstanceId(sourceInstance.id) then return nil end
    return targetProject, targetInstance, peer
end

function IslandPortalNetwork.NormalizeBinding(source)
    if type(source) ~= "table" then return nil end
    local linkId = CleanId(source.linkId)
    local targetIslandId = CleanId(source.targetIslandId or source.peerIslandId)
    local targetInstanceId = CleanInstanceId(source.targetInstanceId or source.peerInstanceId)
    if linkId == "" or targetIslandId == "" or not targetInstanceId then return nil end
    return Binding(linkId, targetIslandId, targetInstanceId, source.generatedPeer)
end

function IslandPortalNetwork.Resolve(collection, islandId, instanceId)
    local sourceProject = FindProject(collection, islandId)
    if not sourceProject then return nil, "source_island_missing" end
    local sourceInstance = FindInstance(sourceProject, instanceId)
    if not sourceInstance then return nil, "source_endpoint_missing" end
    local binding = IslandPortalNetwork.NormalizeBinding(sourceInstance.portal)
    if not binding then return nil, "source_endpoint_unbound" end
    local targetProject, targetInstance, targetBinding = ReciprocalPeer(
        collection, sourceProject, sourceInstance, binding)
    if not targetProject then return nil, "portal_pair_broken" end
    return {
        linkId = binding.linkId,
        sourceProject = sourceProject,
        sourceInstance = sourceInstance,
        sourceBinding = binding,
        targetProject = targetProject,
        targetInstance = targetInstance,
        targetBinding = targetBinding,
    }
end

function IslandPortalNetwork.BindPair(collection, options)
    options = type(options) == "table" and options or {}
    if type(collection) ~= "table" or type(collection.items) ~= "table" then
        return nil, "collection_invalid"
    end
    local sourceIslandId = CleanId(options.sourceIslandId)
    local targetIslandId = CleanId(options.targetIslandId)
    if sourceIslandId == "" or targetIslandId == "" then return nil, "island_id_missing" end
    if sourceIslandId == targetIslandId then return nil, "target_must_be_another_island" end

    local sourceProject = FindProject(collection, sourceIslandId)
    local targetProject = FindProject(collection, targetIslandId)
    if not sourceProject then return nil, "source_island_missing" end
    if not targetProject then return nil, "target_island_missing" end
    local sourceInstance = FindInstance(sourceProject, options.sourceInstanceId)
    if not sourceInstance then return nil, "source_endpoint_missing" end

    local portalAssetId = CleanId(options.portalAssetId or sourceInstance.assetId)
    if portalAssetId == "" then return nil, "portal_asset_missing" end
    if CleanId(sourceInstance.assetId) ~= portalAssetId then return nil, "source_is_not_portal_asset" end
    local portalAsset = options.portalAsset
        or ResolveAsset(options, portalAssetId,
            options.portalVersionId or sourceInstance.versionId or "latest",
            sourceInstance, targetProject)
    if type(portalAsset) ~= "table" or type(portalAsset.bounds) ~= "table" then
        return nil, "portal_asset_unavailable"
    end

    local current = IslandPortalNetwork.Resolve(collection, sourceIslandId, sourceInstance.id)
    if current and current.targetProject == targetProject then
        return current, nil, false
    end

    -- Preflight the entire new pair before touching either existing endpoint.
    -- If rebinding cannot find a supported destination, the previous pair stays intact.
    local previousBinding = IslandPortalNetwork.NormalizeBinding(sourceInstance.portal)
    local previousTargetProject, previousTargetInstance = ReciprocalPeer(
        collection, sourceProject, sourceInstance, previousBinding)
    local ignoreTargetId = previousTargetProject == targetProject and previousTargetInstance
        and previousTargetInstance.id or nil
    local layout = ResolveLayout(options, targetProject)
    if not layout then return nil, "target_layout_missing" end
    local placementOptions = {}
    for key, value in pairs(options) do placementOptions[key] = value end
    placementOptions._strictPortalFootprints = StrictPortalFootprints(
        layout, targetProject, options, ignoreTargetId)
    local placement, placementReason = FindPlacement(
        layout, targetProject, portalAsset, placementOptions, sourceInstance, ignoreTargetId)
    if not placement then return nil, "target_portal_placement_failed:" .. tostring(placementReason) end

    local targetInstance = {
        id = NextInstanceId(targetProject),
        assetId = portalAssetId,
        versionId = tostring(options.portalVersionId or sourceInstance.versionId or "latest"),
        x = placement.x,
        y = placement.y,
        z = placement.z,
        rotationY = placement.rotationY,
        scale = placement.scale,
    }
    local linkId = NewLinkId(collection, options.now)
    local sourceBinding = Binding(linkId, targetIslandId, targetInstance.id, false)
    local targetBinding = Binding(linkId, sourceIslandId, sourceInstance.id, true)
    targetInstance.portal = targetBinding

    local touched = { sourceProject, targetProject }
    if previousTargetProject and previousTargetInstance then
        RemoveInstance(previousTargetProject, previousTargetInstance.id)
        touched[#touched + 1] = previousTargetProject
    end
    sourceInstance.portal = sourceBinding
    targetProject.instances = targetProject.instances or {}
    targetProject.instances[#targetProject.instances + 1] = targetInstance
    TouchProjects(touched, options.now)
    if options.touchCollection ~= false then TouchCollection(collection, options.now) end

    return {
        linkId = linkId,
        sourceProject = sourceProject,
        sourceInstance = sourceInstance,
        sourceBinding = sourceBinding,
        targetProject = targetProject,
        targetInstance = targetInstance,
        targetBinding = targetBinding,
    }, nil, true
end

IslandPortalNetwork.Bind = IslandPortalNetwork.BindPair

function IslandPortalNetwork.Unbind(collection, islandId, instanceId, now, options)
    options = type(options) == "table" and options or {}
    local sourceProject = FindProject(collection, islandId)
    local sourceInstance = sourceProject and FindInstance(sourceProject, instanceId) or nil
    if not sourceProject then return false, "source_island_missing" end
    if not sourceInstance then return false, "source_endpoint_missing" end
    local binding = IslandPortalNetwork.NormalizeBinding(sourceInstance.portal)
    local targetProject, targetInstance = ReciprocalPeer(
        collection, sourceProject, sourceInstance, binding)
    sourceInstance.portal = nil
    local touched = { sourceProject }
    if targetProject and targetInstance then
        if options.keepPeer == true then targetInstance.portal = nil
        else RemoveInstance(targetProject, targetInstance.id) end
        touched[#touched + 1] = targetProject
    end
    TouchProjects(touched, now)
    if options.touchCollection ~= false then TouchCollection(collection, now) end
    return true, {
        sourceProject = sourceProject,
        sourceInstance = sourceInstance,
        targetProject = targetProject,
        targetInstance = targetInstance,
    }
end

function IslandPortalNetwork.DeleteEndpoint(collection, islandId, instanceId, now, options)
    options = type(options) == "table" and options or {}
    local sourceProject = FindProject(collection, islandId)
    local sourceInstance = sourceProject and FindInstance(sourceProject, instanceId) or nil
    if not sourceProject then return false, "source_island_missing" end
    if not sourceInstance then return false, "source_endpoint_missing" end
    local binding = IslandPortalNetwork.NormalizeBinding(sourceInstance.portal)
    local targetProject, targetInstance = ReciprocalPeer(
        collection, sourceProject, sourceInstance, binding)
    RemoveInstance(sourceProject, sourceInstance.id)
    local touched = { sourceProject }
    if targetProject and targetInstance then
        RemoveInstance(targetProject, targetInstance.id)
        touched[#touched + 1] = targetProject
    end
    TouchProjects(touched, now)
    if options.touchCollection ~= false then TouchCollection(collection, now) end
    return true, {
        sourceProject = sourceProject,
        sourceInstance = sourceInstance,
        targetProject = targetProject,
        targetInstance = targetInstance,
    }
end

function IslandPortalNetwork.CleanOrphans(collection, now, options)
    options = type(options) == "table" and options or {}
    local invalid, touched = {}, {}
    local items = type(collection) == "table" and type(collection.items) == "table"
        and collection.items or {}
    for _, project in ipairs(items) do
        local instances = type(project.instances) == "table" and project.instances or {}
        for _, instance in ipairs(instances) do
            if instance.portal ~= nil then
                local resolved = IslandPortalNetwork.Resolve(collection, project.islandId, instance.id)
                if not resolved then invalid[#invalid + 1] = { project = project, instance = instance } end
            end
        end
    end
    for _, entry in ipairs(invalid) do
        entry.instance.portal = nil
        touched[#touched + 1] = entry.project
    end
    if #invalid > 0 then
        TouchProjects(touched, now)
        if options.touchCollection ~= false then TouchCollection(collection, now) end
    end
    return #invalid
end

function IslandPortalNetwork.RemoveIslandReferences(collection, islandId, now, options)
    options = type(options) == "table" and options or {}
    local removedIslandId = CleanId(islandId)
    local removedProject = FindProject(collection, removedIslandId)
    if not removedProject then return 0, "source_island_missing" end

    local touched, removeFromPeers = {}, {}
    for _, instance in ipairs(removedProject.instances or {}) do
        local binding = IslandPortalNetwork.NormalizeBinding(instance.portal)
        local targetProject, targetInstance = ReciprocalPeer(
            collection, removedProject, instance, binding)
        if targetProject and targetProject ~= removedProject and targetInstance then
            removeFromPeers[#removeFromPeers + 1] = {
                project = targetProject,
                instanceId = targetInstance.id,
            }
        end
    end
    -- Also remove stale one-way endpoints that reference the island being deleted.
    for _, project in ipairs(collection.items or {}) do
        if project ~= removedProject then
            for _, instance in ipairs(project.instances or {}) do
                local binding = IslandPortalNetwork.NormalizeBinding(instance.portal)
                if binding and binding.targetIslandId == removedIslandId then
                    removeFromPeers[#removeFromPeers + 1] = {
                        project = project,
                        instanceId = instance.id,
                    }
                end
            end
        end
    end

    local removed, seen = 0, {}
    for _, entry in ipairs(removeFromPeers) do
        local key = tostring(entry.project) .. ":" .. tostring(entry.instanceId)
        if not seen[key] and RemoveInstance(entry.project, entry.instanceId) then
            seen[key] = true
            removed = removed + 1
            touched[#touched + 1] = entry.project
        end
    end
    if removed > 0 then TouchProjects(touched, now) end
    if removed > 0 and options.touchCollection ~= false then TouchCollection(collection, now) end
    return removed
end

function IslandPortalNetwork.StripProjectBindings(project)
    local stripped = 0
    local instances = type(project) == "table" and type(project.instances) == "table"
        and project.instances or {}
    for _, instance in ipairs(instances) do
        if instance.portal ~= nil then
            instance.portal = nil
            stripped = stripped + 1
        end
    end
    return stripped
end

function IslandPortalNetwork.CopyProjectWithoutBindings(project)
    local result = Copy(project)
    IslandPortalNetwork.StripProjectBindings(result)
    return result
end

IslandPortalNetwork.FindProject = FindProject
IslandPortalNetwork.FindInstance = FindInstance
IslandPortalNetwork.Copy = Copy

return IslandPortalNetwork
