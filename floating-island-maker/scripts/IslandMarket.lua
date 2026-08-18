---@diagnostic disable: undefined-global

-- Cross-player island publishing and discovery. Published payloads are
-- declarative snapshots: projects contain transforms only, while every
-- non-builtin model is flattened, bounded and author-namespaced on import.

local IslandMarket = {}
local ModelAssetStore = require("ModelAssetStore")
local BuiltinTemplates = require("BuiltinTemplates")
local IslandLayout = require("IslandLayout")
local IslandTerrainCatalog = require("IslandTerrainCatalog")
local IslandPortalNetwork = require("IslandPortalNetwork")
local PortalTemplate = require("PortalTemplate")
local UserProfileService = require("UserProfileService")
local sampleStore_
local sampleEntries_
local sampleGenerationStats_

-- Offline showcase islands are generated from a dense authored candidate grid.
-- The live placement validator deliberately performs an exact scan, including
-- block-volume density checks, which becomes O(N^2 * blocks) for 1,350 sample
-- instances. Keep the validator authoritative, but only give it objects whose
-- cached horizontal bounds can possibly overlap the candidate.
local SAMPLE_PLACEMENT_CELL_SIZE = 4
local SAMPLE_TRANSPARENT_MATERIALS = { glass = true, water = true, fire = true }

local function SampleAssetVisualDensity(asset, cache, stats)
    local cached = cache[asset]
    if cached ~= nil then return cached end
    local bounds = asset and asset.bounds or {}
    local size = bounds.size or {}
    local boundsVolume = math.max(0.001,
        (tonumber(size[1]) or 1) * (tonumber(size[2]) or 1) * (tonumber(size[3]) or 1))
    local blocks = type(asset and asset.blocks) == "table" and asset.blocks or {}
    if #blocks == 0 then
        cache[asset] = 1
        stats.densityComputations = stats.densityComputations + 1
        return 1
    end
    local occupied = 0
    for _, block in ipairs(blocks) do
        local material = tostring(block.materialId or block.material or "solid")
        local role = tostring(block.collisionRole or "")
        if not SAMPLE_TRANSPARENT_MATERIALS[material] and role ~= "fluid" then
            local blockSize = block.size or {}
            occupied = occupied + math.max(0,
                (tonumber(blockSize[1]) or 1) * (tonumber(blockSize[2]) or 1)
                    * (tonumber(blockSize[3]) or 1))
        end
    end
    local density = math.min(1, occupied / boundsVolume)
    cache[asset] = density
    stats.densityComputations = stats.densityComputations + 1
    return density
end

local function SamplePlacementCellKey(x, z)
    return tostring(x) .. ":" .. tostring(z)
end

local function SamplePlacementCellRange(footprint)
    local size = SAMPLE_PLACEMENT_CELL_SIZE
    return math.floor((footprint.x - footprint.hx) / size),
        math.floor((footprint.x + footprint.hx) / size),
        math.floor((footprint.z - footprint.hz) / size),
        math.floor((footprint.z + footprint.hz) / size)
end

local function NewSamplePlacementIndex(densityCache, stats)
    local index = { cells = {}, densityCache = densityCache, stats = stats }

    function index:Add(instance, asset)
        -- IslandLayout ignores sparse/hollow/transparent objects as burial
        -- occluders. Excluding the same objects from the index is therefore
        -- exact, not an approximation.
        if SampleAssetVisualDensity(asset, self.densityCache, self.stats) < 0.60 then return end
        local footprint = IslandLayout.Footprint(instance, asset)
        self.stats.footprintBuilds = self.stats.footprintBuilds + 1
        local record = { instance = instance, footprint = footprint, order = instance.id }
        local minX, maxX, minZ, maxZ = SamplePlacementCellRange(footprint)
        for cellX = minX, maxX do
            for cellZ = minZ, maxZ do
                local key = SamplePlacementCellKey(cellX, cellZ)
                local bucket = self.cells[key]
                if not bucket then bucket = {}; self.cells[key] = bucket end
                bucket[#bucket + 1] = record
            end
        end
        self.stats.indexedPlacements = self.stats.indexedPlacements + 1
    end

    function index:Candidates(asset, x, z, rotationY, scale)
        local footprint = IslandLayout.Footprint(nil, asset, x, z, rotationY, scale)
        self.stats.footprintBuilds = self.stats.footprintBuilds + 1
        local minX, maxX, minZ, maxZ = SamplePlacementCellRange(footprint)
        local seen, records = {}, {}
        for cellX = minX, maxX do
            for cellZ = minZ, maxZ do
                for _, record in ipairs(self.cells[SamplePlacementCellKey(cellX, cellZ)] or {}) do
                    local other = record.footprint
                    local aabbOverlaps = math.abs(other.x - footprint.x) <= other.hx + footprint.hx
                        and math.abs(other.z - footprint.z) <= other.hz + footprint.hz
                    if aabbOverlaps and not seen[record.instance] then
                        seen[record.instance] = true
                        records[#records + 1] = record
                    end
                end
            end
        end
        -- The exact validator normally observes placement order. It currently
        -- returns only a boolean to this generator, but preserving order keeps
        -- this optimization safe if its diagnostic result is used later.
        table.sort(records, function(first, second) return first.order < second.order end)
        local result = {}
        for _, record in ipairs(records) do result[#result + 1] = record.instance end
        self.stats.nearbyCandidates = self.stats.nearbyCandidates + #result
        return result
    end

    return index
end

local function SampleStore()
    if not sampleStore_ then sampleStore_ = ModelAssetStore.new(BuiltinTemplates.BuildAll()) end
    return sampleStore_
end

IslandMarket.PROFILE_KEY = "island3d_island_market_profile_v1"
IslandMarket.ACTIVITY_KEY = "island3d_island_market_activity_v1"
IslandMarket.PAGE_SIZE = 40
IslandMarket.MAX_PUBLIC_ISLANDS = 5
IslandMarket.MAX_INSTANCES = 600
IslandMarket.SAMPLE_PER_ISLAND = 90
IslandMarket.SAMPLE_INSTANCES = IslandMarket.SAMPLE_PER_ISLAND * #IslandLayout.ISLANDS
-- Island authoring itself is intentionally uncapped. Public snapshots still
-- keep a generous hard safety ceiling so malformed cloud payloads cannot
-- allocate without bound. Built-ins are referenced by id and cost no payload.
IslandMarket.MAX_ASSETS = 48
IslandMarket.MAX_ASSET_BLOCKS = 12000
IslandMarket.MAX_TOTAL_BLOCKS = 24000
IslandMarket.MAX_ASSET_SIZE = 120

local function AssetFitsPublicBounds(asset)
    local size = asset and asset.bounds and asset.bounds.size or {}
    return (tonumber(size[1]) or math.huge) <= IslandMarket.MAX_ASSET_SIZE
        and (tonumber(size[2]) or math.huge) <= IslandMarket.MAX_ASSET_SIZE
        and (tonumber(size[3]) or math.huge) <= IslandMarket.MAX_ASSET_SIZE
end

local function Dispatch(callbacks, name, ...)
    local callback = callbacks and callbacks[name]
    if callback then callback(...) end
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

local function GetCloud()
    local cloud = rawget(_G, "clientCloud")
    return cloud and cloud.GetRankList and cloud.BatchSet and cloud or nil
end

local function Decode(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" or value == "" then return nil end
    local ok, data = pcall(cjson.decode, value)
    return ok and type(data) == "table" and data or nil
end

local function ExtractProfile(item)
    if type(item) ~= "table" then return nil end
    for _, container in ipairs({ item.score, item.values, item.value, item }) do
        if type(container) == "table" then
            local profile = Decode(container[IslandMarket.PROFILE_KEY])
            if profile then return profile end
        end
    end
end

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback or 0 end
    return math.max(minimum, math.min(maximum, value))
end

local function LimitedText(value, fallback, maximum)
    local text = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    if text == "" then text = fallback or "" end
    maximum = math.max(1, tonumber(maximum) or 48)
    local index, count, length = 1, 0, #text
    while index <= length and count < maximum do
        local byte = text:byte(index)
        local width = byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4
        index, count = index + width, count + 1
    end
    return text:sub(1, index - 1)
end

local function SafeId(value, fallback)
    local text = LimitedText(value, fallback or "island", 80)
    text = text:gsub("[^%w_:%-%.]", "-"):gsub("%-+", "-")
    return text ~= "" and text or (fallback or "island")
end

local function PublicAssetId(ownerId, assetId)
    return "island-market:" .. SafeId(ownerId, "player") .. ":" .. SafeId(assetId, "model")
end

local function NormalizeInstance(source, index)
    if type(source) ~= "table" then return nil end
    local assetId = LimitedText(source.assetId, "", 160)
    if assetId == "" then return nil end
    local result = {
        id = index,
        assetId = assetId,
        versionId = LimitedText(source.versionId, "latest", 40),
        x = Clamp(source.x, -180, 180, 0),
        y = Clamp(source.y, -8, 30, 0),
        z = Clamp(source.z, -180, 180, 0),
        rotationY = Clamp(source.rotationY, -math.pi * 8, math.pi * 8, 0),
        scale = Clamp(source.scale, 0.1, 3, 1),
    }
    local portal = IslandPortalNetwork.NormalizeBinding(source.portal)
    if portal then result.portal = portal end
    return result
end

local function TerrainData(source)
    local terrain = type(source.terrain) == "table" and source.terrain or {}
    local terrainId = IslandTerrainCatalog.ResolveId(source.terrainId or terrain.preset)
    local spec = IslandTerrainCatalog.Get(terrainId) or {}
    local camera = type(spec.camera or spec.defaultCamera) == "table"
        and (spec.camera or spec.defaultCamera) or {}
    local target = type(camera.target) == "table" and camera.target or {}
    local overview = type(spec.overview) == "table" and spec.overview or {}
    return terrainId, spec, {
        theta = tonumber(camera.theta) or 0.733,
        phi = tonumber(camera.phi) or 0.96,
        radius = tonumber(camera.radius) or tonumber(overview.radius) or 118,
        target = {
            tonumber(target[1] or target.x) or tonumber(overview.x) or 0,
            tonumber(target[2] or target.y) or -1.0,
            tonumber(target[3] or target.z) or tonumber(overview.z) or 7,
        },
    }
end

local function NormalizeProject(source)
    source = type(source) == "table" and source or {}
    local instances, instanceIdCounts, rawToPublic = {}, {}, {}
    for _, instance in ipairs(source.instances or {}) do
        local rawId = tonumber(type(instance) == "table" and instance.id or nil)
        if rawId and rawId >= 1 then
            rawId = math.floor(rawId)
            instanceIdCounts[rawId] = (instanceIdCounts[rawId] or 0) + 1
        end
    end
    for _, instance in ipairs(source.instances or {}) do
        if #instances >= IslandMarket.MAX_INSTANCES then break end
        local clean = NormalizeInstance(instance, #instances + 1)
        if clean then
            instances[#instances + 1] = clean
            local rawId = tonumber(instance.id)
            if rawId and rawId >= 1 then
                rawId = math.floor(rawId)
                if instanceIdCounts[rawId] == 1 then rawToPublic[tostring(rawId)] = clean.id end
            end
        end
    end
    local environment = type(source.environment) == "table" and source.environment or {}
    local terrainId, terrainSpec, camera = TerrainData(source)
    return {
        schema = "island-project/v2", version = 2,
        revision = math.max(0, math.floor(tonumber(source.revision) or 0)),
        updatedAt = math.max(0, tonumber(source.updatedAt) or 0),
        islandId = SafeId(source.islandId, "island"),
        name = LimitedText(source.name, "玩家空岛", 28),
        terrainId = terrainId,
        terrain = { preset = terrainId, groundY = tonumber(terrainSpec.groundY) or 0.42 },
        environment = {
            timeOfDay = Clamp(environment.timeOfDay, 0, 24, 9.5),
            autoTime = environment.autoTime ~= false,
            dayDuration = Clamp(environment.dayDuration, 60, 3600, 480),
        },
        instances = instances,
        camera = camera,
    }, { rawToPublic = rawToPublic }
end

local function ProjectInstanceIndex(project)
    local result = {}
    for _, instance in ipairs(type(project) == "table" and project.instances or {}) do
        local id = tonumber(instance.id)
        if id and id >= 1 and not result[math.floor(id)] then result[math.floor(id)] = instance end
    end
    return result
end

local function RewriteAndValidatePortalGraph(records)
    local byRawIslandId, byPublicIslandId, projects = {}, {}, {}
    for _, record in ipairs(records or {}) do
        local project = record.project
        if project then
            projects[#projects + 1] = project
            byPublicIslandId[tostring(project.islandId)] = record
            local rawIslandId = tostring(record.rawIslandId or project.islandId)
            byRawIslandId[rawIslandId] = record
            byRawIslandId[SafeId(rawIslandId, project.islandId)] = record
        end
    end

    -- Public instance ids are compact and deterministic. Rewrite each endpoint
    -- only after every published island has its raw->public id map.
    for _, record in ipairs(records or {}) do
        for _, instance in ipairs(record.project and record.project.instances or {}) do
            local binding = IslandPortalNetwork.NormalizeBinding(instance.portal)
            if binding then
                local targetRecord = byRawIslandId[tostring(binding.targetIslandId)]
                    or byPublicIslandId[SafeId(binding.targetIslandId, "")]
                local targetId = targetRecord and targetRecord.rawToPublic
                    and targetRecord.rawToPublic[tostring(binding.targetInstanceId)] or nil
                if instance.assetId == PortalTemplate.ASSET_ID and targetRecord and targetId then
                    binding.targetIslandId = targetRecord.project.islandId
                    binding.targetInstanceId = targetId
                    instance.portal = binding
                else
                    instance.portal = nil
                end
            end
        end
    end

    local collection = { items = projects }
    local invalid = {}
    for _, project in ipairs(projects) do
        local index = ProjectInstanceIndex(project)
        for _, instance in ipairs(project.instances or {}) do
            if instance.portal then
                local route = IslandPortalNetwork.Resolve(collection, project.islandId, instance.id)
                local target = route and index[tonumber(instance.id)] and route.targetInstance or nil
                if not route or instance.assetId ~= PortalTemplate.ASSET_ID
                    or not target or target.assetId ~= PortalTemplate.ASSET_ID then
                    invalid[#invalid + 1] = instance
                end
            end
        end
    end
    for _, instance in ipairs(invalid) do instance.portal = nil end
    -- Removing one malformed endpoint can invalidate its former peer. A second
    -- pass strips that dangling peer too, so the imported graph is reciprocal.
    for _, project in ipairs(projects) do
        for _, instance in ipairs(project.instances or {}) do
            if instance.portal and not IslandPortalNetwork.Resolve(collection, project.islandId, instance.id) then
                instance.portal = nil
            end
        end
    end
end

function IslandMarket.ResolvePublishedPortal(entries, sourceEntry, sourceInstanceId)
    if type(sourceEntry) ~= "table" or type(sourceEntry.project) ~= "table" then
        return nil, "source_island_missing"
    end
    if sourceEntry.source ~= "cloud" then return nil, "source_not_published" end
    local ownerId = tostring(sourceEntry.ownerId or "")
    if ownerId == "" then return nil, "source_owner_missing" end
    local sourceIslandId = tostring(sourceEntry.project.islandId or sourceEntry.islandId or "")
    local sourceInstance = ProjectInstanceIndex(sourceEntry.project)[tonumber(sourceInstanceId)]
    if not sourceInstance then return nil, "source_endpoint_missing" end
    local binding = IslandPortalNetwork.NormalizeBinding(sourceInstance.portal)
    if not binding then return nil, "source_endpoint_unbound" end

    local projects, entryByIslandId = {}, {}
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        if type(entry) == "table" and entry.source == "cloud"
            and tostring(entry.ownerId or "") == ownerId and type(entry.project) == "table" then
            local islandId = tostring(entry.project.islandId or entry.islandId or "")
            if islandId ~= "" and not entryByIslandId[islandId] then
                entryByIslandId[islandId] = entry
                projects[#projects + 1] = entry.project
            end
        end
    end
    local registeredSource = entryByIslandId[sourceIslandId]
    if not registeredSource then return nil, "source_not_published" end
    local registeredInstance = ProjectInstanceIndex(registeredSource.project)[tonumber(sourceInstanceId)]
    local registeredBinding = registeredInstance
        and IslandPortalNetwork.NormalizeBinding(registeredInstance.portal) or nil
    -- The player may refresh Explore while still standing in an older scene
    -- snapshot. Only continue when that visible endpoint still describes the
    -- exact same live published pair; otherwise fail closed and ask them to
    -- revisit instead of mixing an old source with a newly rebound target.
    if not registeredBinding
        or registeredBinding.linkId ~= binding.linkId
        or registeredBinding.targetIslandId ~= binding.targetIslandId
        or tonumber(registeredBinding.targetInstanceId) ~= tonumber(binding.targetInstanceId) then
        return nil, "portal_pair_broken"
    end
    if not entryByIslandId[tostring(registeredBinding.targetIslandId)] then
        return nil, "target_not_published"
    end
    local route, errorMessage = IslandPortalNetwork.Resolve(
        { items = projects }, sourceIslandId, registeredInstance.id)
    if not route then return nil, errorMessage or "portal_pair_broken" end
    if route.sourceInstance.assetId ~= PortalTemplate.ASSET_ID
        or route.targetInstance.assetId ~= PortalTemplate.ASSET_ID then
        return nil, "portal_pair_broken"
    end
    local targetEntry = entryByIslandId[tostring(route.targetProject.islandId)]
    if not targetEntry then return nil, "target_not_published" end
    route.sourceEntry, route.targetEntry, route.ownerId = registeredSource, targetEntry, ownerId
    return route
end

function IslandMarket.BuildProfile(collection, assetStore)
    if type(collection) ~= "table" or type(collection.items) ~= "table" or not assetStore then
        return nil, "空岛发布数据无效"
    end
    local items, assets, assetBySource, portalRecords, publishedIslandIds = {}, {}, {}, {}, {}
    local totalBlocks, omittedEmptyInstances = 0, 0
    for _, sourceProject in ipairs(collection.items) do
        if sourceProject.published == true then
            if #items >= IslandMarket.MAX_PUBLIC_ISLANDS then
                return nil, "最多同时发布 "
                    .. tostring(IslandMarket.MAX_PUBLIC_ISLANDS) .. " 座空岛"
            end
            if #(sourceProject.instances or {}) > IslandMarket.MAX_INSTANCES then
                return nil, "单座空岛最多发布 600 个模型"
            end
            local project, projectMeta = NormalizeProject(sourceProject)
            if publishedIslandIds[project.islandId] then
                return nil, "已发布空岛存在重复标识，请复制为新空岛后再发布"
            end
            publishedIslandIds[project.islandId] = true
            local publishedInstances = {}
            for _, instance in ipairs(project.instances) do
                local originalId = tostring(instance.assetId or "")
                local originalVersion = tostring(instance.versionId or "latest")
                local resolvedId, resolvedScale = originalId, instance.scale
                if assetStore.ResolveLegacyInstance then
                    resolvedId, resolvedScale = assetStore:ResolveLegacyInstance(
                        originalId, instance.scale)
                end
                local sourceAsset = assetStore:Get(resolvedId, originalVersion)
                    or assetStore:Get(resolvedId)
                if not sourceAsset then
                    return nil, "《" .. tostring(project.name) .. "》中的模型“"
                        .. originalId .. "”已不存在，请删除或重新放置后再发布"
                end

                if sourceAsset.source == "builtin" then
                    -- Resolve legacy builtin:wonder:* ids before publishing.
                    -- A prefix check misclassified them as custom and remote
                    -- import then silently dropped the stale instance id.
                    instance.assetId = sourceAsset.assetId
                    instance.versionId = sourceAsset.versionId
                    instance.scale = resolvedScale
                    publishedInstances[#publishedInstances + 1] = instance
                else
                    local sourceKey = tostring(sourceAsset.assetId) .. "@"
                        .. tostring(sourceAsset.versionId or originalVersion)
                    local packaged = assetBySource[sourceKey]
                        or assetBySource[tostring(sourceAsset.assetId)]
                    if not packaged then
                        local flattened, errorMessage
                        if assetStore.AcquireRenderable then
                            flattened, errorMessage = assetStore:AcquireRenderable(sourceAsset)
                        else
                            flattened, errorMessage = assetStore:Flatten(sourceAsset)
                        end
                        if not flattened then
                            return nil, "《" .. tostring(project.name) .. "》中的《"
                                .. tostring(sourceAsset.name or originalId) .. "》无法展开："
                                .. tostring(errorMessage or "模型数据不完整")
                        end
                        local blockCount = #(flattened.blocks or {})
                        if blockCount == 0 then
                            -- Empty assets draw nothing. Old/imported saves may
                            -- still reference one, so omit it from the public
                            -- copy without mutating the owner's island.
                            omittedEmptyInstances = omittedEmptyInstances + 1
                        elseif blockCount > IslandMarket.MAX_ASSET_BLOCKS then
                            return nil, "《" .. tostring(project.name) .. "》中的《"
                                .. tostring(sourceAsset.name or originalId) .. "》有 "
                                .. tostring(blockCount) .. " 个积木，超过探索发布的单模型安全上限 "
                                .. tostring(IslandMarket.MAX_ASSET_BLOCKS) .. " 个"
                        elseif not AssetFitsPublicBounds(flattened) then
                            return nil, "《" .. tostring(project.name) .. "》中的《"
                                .. tostring(sourceAsset.name or originalId)
                                .. "》尺寸超过 " .. tostring(IslandMarket.MAX_ASSET_SIZE)
                                .. "，请缩小模型本体后再发布"
                        elseif #assets >= IslandMarket.MAX_ASSETS then
                            return nil, "已发布空岛合计超过 "
                                .. tostring(IslandMarket.MAX_ASSETS)
                                .. " 个不同的自制/市场模型，请减少模型种类后再发布"
                        elseif totalBlocks + blockCount > IslandMarket.MAX_TOTAL_BLOCKS then
                            return nil, "已发布空岛的自制/市场模型合计有 "
                                .. tostring(totalBlocks + blockCount)
                                .. " 个积木，超过探索发布安全上限 "
                                .. tostring(IslandMarket.MAX_TOTAL_BLOCKS) .. " 个"
                        else
                            packaged = ModelAssetStore.Normalize(flattened, {
                                source = "market", assetId = sourceAsset.assetId,
                                versionId = sourceAsset.versionId, ownerId = sourceAsset.ownerId,
                                author = sourceAsset.author, license = "use_only",
                            })
                            packaged.schema = ModelAssetStore.SCHEMA
                            packaged.components, packaged.dependencies, packaged.packagedDependencies = {}, {}, {}
                            assets[#assets + 1] = packaged
                            totalBlocks = totalBlocks + #packaged.blocks
                            assetBySource[sourceKey] = packaged
                            assetBySource[tostring(sourceAsset.assetId)] = packaged
                            assetBySource[originalId .. "@" .. originalVersion] = packaged
                            assetBySource[originalId] = packaged
                        end
                    end
                    if packaged then
                        instance.assetId = packaged.assetId
                        instance.versionId = packaged.versionId
                        publishedInstances[#publishedInstances + 1] = instance
                    end
                end
            end
            project.instances = publishedInstances
            portalRecords[#portalRecords + 1] = {
                rawIslandId = tostring(sourceProject.islandId or project.islandId),
                project = project,
                rawToPublic = projectMeta.rawToPublic,
            }
            items[#items + 1] = {
                publicationId = SafeId(project.islandId, "island-" .. tostring(#items + 1)),
                name = project.name,
                description = "摆放了 " .. tostring(#project.instances) .. " 个模型的可漫游空岛",
                updatedAt = project.updatedAt,
                project = project,
            }
        end
    end
    RewriteAndValidatePortalGraph(portalRecords)
    return {
        schema = "island-market-profile/v1",
        ownerId = UserProfileService.CurrentUserId() or "local",
        updatedAt = math.max(0, tonumber(collection.updatedAt) or 0),
        items = items,
        assets = assets,
        omittedEmptyInstances = omittedEmptyInstances,
    }
end

local function NormalizeRemoteProfile(profile, ownerId)
    if type(profile) ~= "table" or profile.schema ~= "island-market-profile/v1" then return {} end
    ownerId = tostring(ownerId or profile.ownerId or "unknown")
    local assets, assetMap, totalBlocks = {}, {}, 0
    for _, source in ipairs(profile.assets or {}) do
        if #assets >= IslandMarket.MAX_ASSETS then break end
        local blockCount = type(source) == "table" and type(source.blocks) == "table" and #source.blocks or 0
        if source.schema == ModelAssetStore.SCHEMA and blockCount > 0
            and blockCount <= IslandMarket.MAX_ASSET_BLOCKS
            and totalBlocks + blockCount <= IslandMarket.MAX_TOTAL_BLOCKS then
            local originalId, originalVersion = tostring(source.assetId or ""), tostring(source.versionId or "latest")
            local publicId = PublicAssetId(ownerId, originalId)
            local clean = ModelAssetStore.Normalize(source, {
                source = "market", assetId = publicId, versionId = originalVersion,
                ownerId = ownerId, author = "云岛旅人", license = "use_only",
            })
            clean.script, clean.code, clean.lua, clean.behaviors = nil, nil, nil, nil
            clean.components, clean.dependencies, clean.packagedDependencies = {}, {}, {}
            if AssetFitsPublicBounds(clean) then
                assets[#assets + 1] = clean
                totalBlocks = totalBlocks + blockCount
                assetMap[originalId .. "@" .. originalVersion] = clean
                assetMap[originalId] = clean
            end
        end
    end

    local entries, portalRecords, seenIslandIds = {}, {}, {}
    for _, item in ipairs(profile.items or {}) do
        if #entries >= IslandMarket.MAX_PUBLIC_ISLANDS then break end
        if type(item) == "table" and type(item.project) == "table" then
            local project, projectMeta = NormalizeProject(item.project)
            local rawIslandId = tostring(item.project.islandId or project.islandId)
            local publicIslandId = SafeId(item.publicationId, project.islandId)
            project.islandId = publicIslandId
            local safeInstances = {}
            for _, instance in ipairs(project.instances) do
                local asset = assetMap[instance.assetId .. "@" .. tostring(instance.versionId)]
                    or assetMap[instance.assetId]
                if asset then
                    instance.assetId, instance.versionId = asset.assetId, asset.versionId
                    safeInstances[#safeInstances + 1] = instance
                elseif tostring(instance.assetId):match("^builtin:compose:") then
                    safeInstances[#safeInstances + 1] = instance
                end
            end
            project.instances = safeInstances
            project.name = LimitedText(item.name or project.name, "玩家空岛", 28)
            if not seenIslandIds[publicIslandId] then
                seenIslandIds[publicIslandId] = true
                local entry = {
                    id = SafeId(ownerId, "player") .. ":" .. publicIslandId,
                    islandId = publicIslandId,
                    ownerId = ownerId,
                    owner = "云岛旅人",
                    name = project.name,
                    description = LimitedText(item.description, "欢迎来空岛漫游", 52),
                    count = #project.instances,
                    updatedAt = math.max(0, tonumber(item.updatedAt) or project.updatedAt or 0),
                    project = project,
                    assets = assets,
                    source = "cloud",
                }
                entries[#entries + 1] = entry
                portalRecords[#portalRecords + 1] = {
                    rawIslandId = rawIslandId,
                    project = project,
                    rawToPublic = projectMeta.rawToPublic,
                    entry = entry,
                }
            end
        end
    end
    RewriteAndValidatePortalGraph(portalRecords)
    return entries
end

local function WithNicknames(entries, ownerIds, callbacks, source)
    UserProfileService.Resolve(ownerIds, {
        ok = function(profiles)
            for _, entry in ipairs(entries) do
                local profile = profiles[UserProfileService.UserKey(entry.ownerId)]
                if profile then
                    entry.owner = LimitedText(profile.nickname, entry.owner, 24)
                    entry.avatar = UserProfileService.Copy(profile.avatar)
                end
            end
            Dispatch(callbacks, "ok", entries, source)
        end,
    })
end

function IslandMarket.IsOnline() return GetCloud() ~= nil end

function IslandMarket.Publish(profile, callbacks)
    if type(profile) ~= "table" or profile.schema ~= "island-market-profile/v1" then
        Dispatch(callbacks, "error", "空岛发布数据无效")
        return false
    end
    if type(profile.items) ~= "table"
        or #profile.items > IslandMarket.MAX_PUBLIC_ISLANDS then
        Dispatch(callbacks, "error", "每位玩家最多同时发布 "
            .. tostring(IslandMarket.MAX_PUBLIC_ISLANDS) .. " 座空岛")
        return false
    end
    local cloud = GetCloud()
    if not cloud then Dispatch(callbacks, "ok", "local"); return true end
    local timestamp = 1
    local okTime, value = pcall(os.time)
    if okTime then timestamp = math.max(1, math.floor(tonumber(value) or 1)) end
    local started, startError = pcall(function()
        cloud:BatchSet()
            :Set(IslandMarket.PROFILE_KEY, profile)
            :SetInt(IslandMarket.ACTIVITY_KEY, timestamp)
            :Save("发布探索空岛", {
                ok = function() Dispatch(callbacks, "ok", "cloud") end,
                error = function(code, reason)
                    Dispatch(callbacks, "error", "空岛发布失败：" .. tostring(reason or code or "未知错误"))
                end,
                timeout = function() Dispatch(callbacks, "error", "空岛发布超时，请重试") end,
            })
    end)
    if not started then Dispatch(callbacks, "error", "空岛发布启动失败：" .. tostring(startError)); return false end
    return true
end

function IslandMarket.Load(callbacks)
    local cloud = GetCloud()
    if not cloud then Dispatch(callbacks, "ok", {}, "offline"); return false end
    local started, startError = pcall(function()
        cloud:GetRankList(IslandMarket.ACTIVITY_KEY, 0, IslandMarket.PAGE_SIZE, {
            ok = function(rankList)
                local entries, ownerIds, seenOwners = {}, {}, {}
                for _, item in ipairs(rankList or {}) do
                    local rawOwnerId = UserProfileService.ExtractUserId(item)
                    local ownerId = UserProfileService.UserKey(rawOwnerId) or ""
                    local profile = ExtractProfile(item)
                    if ownerId ~= "" and profile then
                        local normalized = NormalizeRemoteProfile(profile, ownerId)
                        for _, entry in ipairs(normalized) do entries[#entries + 1] = entry end
                        if #normalized > 0 and not seenOwners[ownerId] then
                            seenOwners[ownerId] = true
                            ownerIds[#ownerIds + 1] = rawOwnerId
                        end
                    end
                end
                WithNicknames(entries, ownerIds, callbacks, "cloud")
            end,
            error = function(code, reason)
                Dispatch(callbacks, "error", "探索列表读取失败：" .. tostring(reason or code or "未知错误"))
            end,
            timeout = function() Dispatch(callbacks, "error", "探索列表读取超时") end,
        }, IslandMarket.PROFILE_KEY)
    end)
    if not started then Dispatch(callbacks, "error", "探索列表读取启动失败：" .. tostring(startError)); return false end
    return true
end

function IslandMarket.SampleEntries(assetStore)
    if sampleEntries_ then return Copy(sampleEntries_) end
    -- Samples are authored locally, so placement can use the same rotated
    -- footprint test as the live editor. This is both more accurate and more
    -- maintainable than guessing a different radius for every prop.
    local sampleStore = assetStore or SampleStore()
    local densityCache = setmetatable({}, { __mode = "k" })
    local generationStats = {
        placementChecks = 0,
        fullPoolCandidates = 0,
        nearbyCandidates = 0,
        densityComputations = 0,
        footprintBuilds = 0,
        indexedPlacements = 0,
    }
    local function Project(id, name, instances, timeOfDay, autoTime)
        return NormalizeProject({ islandId = id, name = name, instances = instances,
            environment = { timeOfDay = timeOfDay or 10.5, autoTime = autoTime ~= false, dayDuration = 480 } })
    end
    local function A(id, scale, y, rotationOffset)
        return { id = id, scale = scale or 1, y = y or 0, rotationOffset = rotationOffset or 0 }
    end
    local detailPalettes = {
        ["sample-town"] = { "straight-cobble-path", "curved-cobble-path", "straight-cobble-path",
            "rustic-wood-fence", "wood-fence-corner", "white-picket-fence", "swing-garden-gate",
            "garden-bollard-light", "warm-street-lamp", "curved-wood-bench",
            "painted-wayfinding-sign", "long-flower-planter", "small-cafe-set", "round-garden-bush" },
        ["sample-nature"] = { "short-grass-tuft", "tall-wind-grass", "soft-fern",
            "broad-leaf-plant", "riverside-reeds", "round-garden-bush", "stone-park-bench",
            "rope-post-barrier", "painted-wayfinding-sign", "garden-bollard-light" },
        ["sample-snow"] = { "short-grass-tuft", "tall-wind-grass", "soft-fern",
            "bluebell-wildflower", "garden-bollard-light", "stone-park-bench",
            "rope-post-barrier", "painted-wayfinding-sign", "warm-street-lamp", "loose-boulder-cluster" },
        ["sample-skyport"] = { "short-grass-tuft", "coral-wildflower", "bluebell-wildflower",
            "garden-bollard-light", "brass-iron-railing", "painted-wayfinding-sign",
            "stone-park-bench", "warm-street-lamp", "long-flower-planter", "striped-sun-umbrella" },
        ["sample-park"] = { "coral-wildflower", "bluebell-wildflower", "flowering-shrub",
            "round-garden-bush", "broad-leaf-plant", "short-grass-tuft", "curved-wood-bench",
            "white-picket-fence", "garden-bollard-light", "long-flower-planter" },
    }
    local zonePalettes = {
        ["sample-town"] = { "straight-cobble-path", "curved-cobble-path",
            "rustic-wood-fence", "wood-fence-corner", "white-picket-fence", "swing-garden-gate",
            "small-cafe-set", "warm-street-lamp", "twin-square-lamp", "curved-wood-bench",
            "soft-riverside-willow", "garden-bollard-light", "long-flower-planter", "twin-square-lamp",
            "straight-cobble-path", "curved-cobble-path", "rustic-wood-fence", "wood-fence-corner" },
        ["sample-nature"] = { "sunny-meadow-cottage", "stone-balcony-lodge",
            "glass-garden-studio", "blue-roof-family-house", "tall-layered-pine",
            "shallow-lily-pond", "storybook-birch", "soft-riverside-willow",
            "waterfall-rock-gate", "walkable-cliff-terrace", "snow-cap-mountain", "layered-rocky-hill",
            "young-cloud-pine", "round-meadow-oak", "tall-guardian-oak", "tiny-fruit-tree",
            "timber-footbridge", "riverside-reeds", "loose-boulder-cluster", "stone-park-bench" },
        ["sample-snow"] = { "stone-balcony-lodge", "sunny-meadow-cottage",
            "blue-roof-family-house", "tall-layered-pine", "young-cloud-pine",
            "storybook-birch", "loose-boulder-cluster", "rope-post-barrier",
            "modular-stone-steps", "painted-wayfinding-sign", "shallow-lily-pond",
            "stone-park-bench", "garden-bollard-light", "warm-street-lamp",
            "tall-wind-grass", "tall-layered-pine" },
        ["sample-skyport"] = { "glass-garden-studio", "blue-roof-family-house",
            "narrow-three-storey-home", "stone-balcony-lodge", "square-timber-deck",
            "twin-square-lamp", "brass-iron-railing", "small-cafe-set",
            "cloud-courier-airship", "painted-wayfinding-sign", "storybook-balloon",
            "stone-park-bench", "shallow-lily-pond", "garden-bollard-light",
            "striped-sun-umbrella", "long-flower-planter" },
        ["sample-park"] = { "sunny-meadow-cottage", "glass-garden-studio",
            "blue-roof-family-house", "stone-balcony-lodge", "pink-cloud-blossom",
            "shallow-lily-pond", "tiny-fruit-tree", "vine-garden-arch",
            "storybook-birch", "soft-riverside-willow", "small-cafe-set",
            "striped-sun-umbrella", "timber-footbridge", "curved-wood-bench",
            "riverside-reeds", "long-flower-planter" },
    }
    local structurePalettes = {
        ["sample-town"] = { "sunny-meadow-cottage", "blue-roof-family-house", "brick-corner-shop",
            "glass-garden-studio", "stone-balcony-lodge", "narrow-three-storey-home" },
        ["sample-nature"] = { "waterfall-rock-gate", "walkable-cliff-terrace",
            "snow-cap-mountain", "layered-rocky-hill", "tall-guardian-oak", "tall-layered-pine" },
        ["sample-snow"] = { "stone-balcony-lodge", "sunny-meadow-cottage", "blue-roof-family-house",
            "snow-cap-mountain", "layered-rocky-hill", "tall-layered-pine" },
        ["sample-skyport"] = { "glass-garden-studio", "blue-roof-family-house",
            "narrow-three-storey-home", "stone-balcony-lodge", "square-timber-deck", "sunny-meadow-cottage" },
        ["sample-park"] = { "sunny-meadow-cottage", "glass-garden-studio",
            "blue-roof-family-house", "stone-balcony-lodge", "pink-cloud-blossom", "shallow-lily-pond" },
    }
    -- Three deliberate neighbourhoods per sample: one central landmark and
    -- one landmark on each side island, then irregular perimeter slots that
    -- leave readable paths between models and keep bridge approaches open.
    local slots = {
        { x = 0, z = -16, r = 0 }, { x = -44, z = 24, r = 0 }, { x = 44, z = 24, r = 0 },
        { x = -18, z = -21, r = 78 }, { x = -13, z = -2, r = 135 },
        { x = -3, z = 4, r = 168 }, { x = 9, z = 2, r = 205 },
        { x = 18, z = -8, r = 250 }, { x = 20, z = -22, r = 285 },
        { x = 10, z = -33, r = 325 }, { x = -7, z = -36, r = 28 },
        { x = -58, z = 20, r = 74 }, { x = -53, z = 36, r = 132 },
        { x = -42, z = 39, r = 182 }, { x = -31, z = 32, r = 230 },
        { x = -30, z = 17, r = 282 }, { x = -44, z = 9, r = 0 },
        { x = 30, z = 20, r = 106 }, { x = 35, z = 36, r = 154 },
        { x = 46, z = 39, r = 198 }, { x = 57, z = 32, r = 246 },
        { x = 58, z = 17, r = 300 }, { x = 44, z = 9, r = 0 },
        -- A second authored ring turns each island into a real neighbourhood.
        -- These positions are for visible groves, waterside pieces and public
        -- facilities rather than tiny details used only to inflate the count.
        { x = 0, z = -5.5, r = 18 }, { x = 9.1, z = -10.8, r = 74 },
        { x = 9.1, z = -21.2, r = 126 }, { x = 0, z = -26.5, r = 188 },
        { x = -9.1, z = -21.2, r = 238 }, { x = -9.1, z = -10.8, r = 305 },
        { x = -44, z = 32.5, r = 14 }, { x = -35.9, z = 26.6, r = 76 },
        { x = -39, z = 17.1, r = 146 }, { x = -49, z = 17.1, r = 218 },
        { x = -52.1, z = 26.6, r = 292 },
        { x = 44, z = 32.5, r = 346 }, { x = 52.1, z = 26.6, r = 58 },
        { x = 49, z = 17.1, r = 132 }, { x = 39, z = 17.1, r = 208 },
        { x = 35.9, z = 26.6, r = 278 },
    }
    local function Compose(id, name, models, timeOfDay, autoTime)
        local instances, placed = {}, {}
        local placementIndex = NewSamplePlacementIndex(densityCache, generationStats)
        local function TryPlace(assetId, slot, scale, y, rotationOffset)
            local fullAssetId = "builtin:compose:" .. assetId
            local asset = sampleStore:Get(fullAssetId)
            if not asset or not slot then return false end
            local rotation = math.rad(slot.r + (rotationOffset or 0))
            scale = scale or 1
            generationStats.placementChecks = generationStats.placementChecks + 1
            generationStats.fullPoolCandidates = generationStats.fullPoolCandidates + #placed
            local nearby = placementIndex:Candidates(asset, slot.x, slot.z, rotation, scale)
            local valid = IslandLayout.IsPlacementValid(
                nearby, asset, slot.x, slot.z, rotation, scale)
            if not valid then return false end
            instances[#instances + 1] = {
                assetId = fullAssetId, x = slot.x, y = y or 0, z = slot.z,
                rotationY = rotation, scale = scale,
            }
            local placedInstance = {
                id = #placed + 1, x = slot.x, z = slot.z,
                rotationY = rotation, scale = scale, renderAsset = asset,
            }
            placed[#placed + 1] = placedInstance
            placementIndex:Add(placedInstance, asset)
            return true
        end
        if id ~= "sample-town" then
            for index, source in ipairs(models) do
                local slot = slots[index]
                if not slot then break end
                TryPlace(source.id, slot, source.scale, source.y, source.rotationOffset)
            end
        end

        local function AddTownGrid()
            local houses = { "sunny-meadow-cottage", "blue-roof-family-house", "brick-corner-shop",
                "glass-garden-studio", "stone-balcony-lodge", "narrow-three-storey-home" }
            local function StreetSlot(island, dx, dz, r)
                return { x = island.x + dx, z = island.z + dz, r = r }
            end
            local function PlaceStreet(island, compact)
                local span = compact and { -9, -3, 3, 9 } or { -17, -11, -5, 5, 11, 17 }
                for _, dx in ipairs(span) do TryPlace("straight-cobble-path", StreetSlot(island, dx, 0, 90)) end
                for _, dz in ipairs(compact and { -10, -4, 4, 10 } or { -16, -10, -4, 4, 10, 16 }) do
                    TryPlace("straight-cobble-path", StreetSlot(island, 0, dz, 0))
                end
                for _, dx in ipairs(compact and { -11, 11 } or { -19, 19 }) do
                    TryPlace("rustic-wood-fence", StreetSlot(island, dx, -8.5, 90))
                    TryPlace("rustic-wood-fence", StreetSlot(island, dx, 8.5, 90))
                end
                for _, dz in ipairs(compact and { -12, 12 } or { -18, 18 }) do
                    TryPlace("wood-fence-corner", StreetSlot(island, -8.5, dz, 0))
                    TryPlace("wood-fence-corner", StreetSlot(island, 8.5, dz, 0))
                end
            end
            local function PlaceLots(island, compact, islandIndex)
                local lots = compact
                    and { { -8, -9, 0 }, { 8, -9, 0 }, { -8, 9, 180 }, { 8, 9, 180 } }
                    or { { -15, -10, 0 }, { -5, -10, 0 }, { 5, -10, 0 }, { 15, -10, 0 },
                        { -15, 10, 180 }, { -5, 10, 180 }, { 5, 10, 180 }, { 15, 10, 180 } }
                for lotIndex, lot in ipairs(lots) do
                    local assetId = houses[((lotIndex + islandIndex * 2 - 2) % #houses) + 1]
                    TryPlace(assetId, StreetSlot(island, lot[1], lot[2], lot[3]), compact and 0.76 or 0.78, 0, 0)
                end
            end
            for islandIndex, island in ipairs(IslandLayout.ISLANDS) do
                local compact = island.radius < 24
                PlaceLots(island, compact, islandIndex)
                PlaceStreet(island, compact)
            end
        end
        if id == "sample-town" then AddTownGrid() end
        for zoneIndex, assetId in ipairs(zonePalettes[id] or {}) do
            TryPlace(assetId, slots[#models + zoneIndex], 1, 0, 0)
        end
        local palette = detailPalettes[id] or detailPalettes["sample-nature"]

        local function DistributedCandidates(island, step, pathHalfWidth, salt)
            local candidates = {}
            local limit = island.radius - 1.2
            local indexX = 0
            for dx = -limit, limit, step do
                indexX = indexX + 1
                local indexZ = 0
                for dz = -limit, limit, step do
                    indexZ = indexZ + 1
                    if dx * dx + dz * dz <= limit * limit
                        and math.abs(dx) > pathHalfWidth and math.abs(dz) > pathHalfWidth then
                        candidates[#candidates + 1] = {
                            x = island.x + dx, z = island.z + dz,
                            r = (indexX * 67 + indexZ * 131 + salt * 43) % 360,
                            order = (indexX * 193 + indexZ * 389 + salt * 97) % 1543,
                        }
                    end
                end
            end
            table.sort(candidates, function(first, second)
                if first.order == second.order then
                    if first.x == second.x then return first.z < second.z end
                    return first.x < second.x
                end
                return first.order < second.order
            end)
            return candidates
        end

        -- Reserve large, well-spaced lots on every island before adding small
        -- scenery. This guarantees that houses and theme landmarks are spread
        -- across the whole archipelago instead of being squeezed out by grass.
        if id ~= "sample-town" then
            for islandIndex, island in ipairs(IslandLayout.ISLANDS) do
                local candidates = DistributedCandidates(island, 4.4, 3.0, islandIndex * 11)
                for structureIndex, assetId in ipairs(structurePalettes[id] or {}) do
                    for candidateIndex = 1, #candidates do
                        local candidate = candidates[((candidateIndex + structureIndex * 7 - 2) % #candidates) + 1]
                        if TryPlace(assetId, candidate, 1, 0, 0) then break end
                    end
                end
            end
        end

        local islandCounts = {}
        for _, island in ipairs(IslandLayout.ISLANDS) do islandCounts[island.id] = 0 end
        for _, instance in ipairs(instances) do
            local island = IslandLayout.IslandAt(instance.x, instance.z)
            if island then islandCounts[island.id] = islandCounts[island.id] + 1 end
        end
        for islandIndex, island in ipairs(IslandLayout.ISLANDS) do
            local candidates = DistributedCandidates(island, 2.6, 1.8, islandIndex * 29)
            local detailIndex = islandIndex * 17 + 1
            for _, candidate in ipairs(candidates) do
                if islandCounts[island.id] >= IslandMarket.SAMPLE_PER_ISLAND then break end
                local assetId = palette[(detailIndex - 1) % #palette + 1]
                if TryPlace(assetId, candidate, 1, 0, 0) then
                    islandCounts[island.id] = islandCounts[island.id] + 1
                    detailIndex = detailIndex + 1
                end
            end
            if islandCounts[island.id] < IslandMarket.SAMPLE_PER_ISLAND then
                local finishing = { "short-grass-tuft", "coral-wildflower", "bluebell-wildflower",
                    "soft-fern", "broad-leaf-plant", "garden-bollard-light" }
                local fineCandidates = DistributedCandidates(island, 1.8, 1.8, islandIndex * 53)
                local fineIndex = islandIndex * 13 + 1
                for _, candidate in ipairs(fineCandidates) do
                    if islandCounts[island.id] >= IslandMarket.SAMPLE_PER_ISLAND then break end
                    local assetId = finishing[(fineIndex - 1) % #finishing + 1]
                    if TryPlace(assetId, candidate, 1, 0, 0) then
                        islandCounts[island.id] = islandCounts[island.id] + 1
                        fineIndex = fineIndex + 1
                    end
                end
            end
        end
        return Project(id, name, instances, timeOfDay, autoTime)
    end
    local samples = {
        { id = "sample:town", owner = "云岬镇造师", name = "云岬生活镇",
            description = "住宅、商店、工坊和完整街景分布在三座相连空岛",
            project = Compose("sample-town", "云岬生活镇", {
                A("straight-cobble-path"), A("straight-cobble-path"), A("curved-cobble-path"),
                A("rustic-wood-fence"), A("wood-fence-corner"), A("swing-garden-gate"),
                A("white-picket-fence"), A("small-cafe-set"), A("warm-street-lamp"),
                A("painted-wayfinding-sign"), A("long-flower-planter"), A("twin-square-lamp"),
                A("curved-wood-bench"), A("stone-park-bench"), A("garden-bollard-light"),
                A("tiny-fruit-tree"), A("round-meadow-oak"), A("soft-grass-mound"),
            }) },
        { id = "sample:snow", owner = "雪线测绘员", name = "雪岭远征线",
            description = "三类高山、云杉营地、攀登设施和空中补给点",
            project = Compose("sample-snow", "雪岭远征线", {
                A("snow-cap-mountain"), A("needle-stone-peak"), A("layered-rocky-hill"),
                A("tall-layered-pine"), A("young-cloud-pine"), A("modular-stone-steps"),
                A("rope-post-barrier"), A("painted-wayfinding-sign"), A("cloud-courier-airship", 1, 5),
                A("storybook-balloon", 1, 7), A("loose-boulder-cluster"), A("tall-wind-grass"),
                A("storybook-birch"), A("garden-bollard-light"), A("timber-footbridge"),
                A("shallow-lily-pond"), A("stone-park-bench"), A("wind-ribbon-glider", 1, 4),
                A("soft-grass-mound"), A("meadow-grass-cluster"), A("warm-street-lamp"),
                A("straight-cobble-path"), A("stone-balcony-lodge"),
            }, 8.4, false) },
        { id = "sample:skyport", owner = "晴空邮递社", name = "三岛天空港",
            description = "飞艇、滑翔翼、悬浮艇与灯光甲板组成的空港工坊",
            project = Compose("sample-skyport", "三岛天空港", {
                A("glass-garden-studio"), A("square-timber-deck"), A("square-timber-deck"),
                A("cloud-courier-airship", 1, 5), A("wind-ribbon-glider", 1, 3.5),
                A("crystal-hover-skiff", 1, 1.2), A("storybook-balloon", 1, 7),
                A("brass-iron-railing"), A("twin-square-lamp"), A("painted-wayfinding-sign"),
                A("small-cafe-set"), A("warm-street-lamp"), A("long-flower-planter"),
                A("garden-bollard-light"), A("stone-park-bench"), A("blue-roof-family-house"),
                A("straight-cobble-path"), A("striped-sun-umbrella"), A("curved-wood-bench"),
                A("tiny-fruit-tree"), A("white-picket-fence"), A("shallow-lily-pond"),
                A("soft-grass-mound"),
            }, 13.2, true) },
        { id = "sample:nature", owner = "云上地貌局", name = "山林湖草自然环线",
            description = "高山、森林、湖泊、草地、瀑布和步桥组成的自然大景",
            project = Compose("sample-nature", "山林湖草自然环线", {
                A("waterfall-rock-gate"), A("walkable-cliff-terrace"), A("snow-cap-mountain"),
                A("layered-rocky-hill"), A("needle-stone-peak"), A("tall-guardian-oak"),
                A("tall-layered-pine"), A("soft-riverside-willow"), A("storybook-birch"),
                A("round-meadow-oak"), A("shallow-lily-pond"), A("timber-footbridge"),
                A("riverside-reeds"), A("meadow-grass-cluster"), A("tall-wind-grass"),
                A("soft-fern"), A("broad-leaf-plant"), A("loose-boulder-cluster"),
                A("modular-stone-steps"), A("rope-post-barrier"), A("painted-wayfinding-sign"),
                A("stone-park-bench"), A("sunny-meadow-cottage"),
            }, 9.1, false) },
        { id = "sample:park", owner = "花园庆典会", name = "云岛中央公园",
            description = "花树、拱门、池塘、茶座、步道和围栏构成的开放公园",
            project = Compose("sample-park", "云岛中央公园", {
                A("sunny-meadow-cottage"), A("shallow-lily-pond"), A("pink-cloud-blossom"),
                A("vine-garden-arch"), A("flowering-shrub"), A("round-garden-bush"),
                A("striped-sun-umbrella"), A("small-cafe-set"), A("long-flower-planter"),
                A("white-picket-fence"), A("swing-garden-gate"), A("tiny-fruit-tree"),
                A("living-hedge-segment"), A("bluebell-wildflower"), A("coral-wildflower"),
                A("curved-wood-bench"), A("garden-bollard-light"), A("storybook-birch"),
                A("soft-riverside-willow"), A("riverside-reeds"), A("timber-footbridge"),
                A("curved-cobble-path"), A("soft-grass-mound"),
            }, 11.4, true) },
    }
    local sampleLikes = { 386, 274, 451, 523, 338 }
    for index, entry in ipairs(samples) do
        entry.ownerId, entry.count, entry.assets, entry.source = entry.id, #entry.project.instances, {}, "sample"
        entry.likes = sampleLikes[index] or 0
        entry.updatedAt = 1784200000 + (#samples - index) * 21600
    end
    sampleGenerationStats_ = generationStats
    sampleEntries_ = samples
    return Copy(sampleEntries_)
end

-- Engine-free performance evidence for regression tests. The counters compare
-- the candidate pool the old full scan would inspect with the exact nearby
-- subset passed to IslandLayout's unchanged validator.
function IslandMarket.SampleGenerationStats()
    return Copy(sampleGenerationStats_ or {})
end

IslandMarket.NormalizeRemoteProfile = NormalizeRemoteProfile
IslandMarket.Copy = Copy

return IslandMarket
