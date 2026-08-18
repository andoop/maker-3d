package.path = "scripts/?.lua;" .. package.path

local BuiltinTemplates = require("BuiltinTemplates")
local ModelAssetStore = require("ModelAssetStore")
local IslandProjectStore = require("IslandProjectStore")
local IslandMarket = require("IslandMarket")
local IslandLayout = require("IslandLayout")
local TerrainCatalog = require("IslandTerrainCatalog")

local function Block(name, x)
    return {
        name = name, position = { x or 0, 0.5, 0 }, size = { 1, 1, 1 }, rotation = { 0, 0, 0 },
        color = "#f2e7cf", materialId = "solid", shapeId = "box",
    }
end

local store = ModelAssetStore.new(BuiltinTemplates.BuildAll())
local custom = store:CreateBlank("自制观景台")
assert(store:SaveDraft(custom.assetId, { name = custom.name, blocks = { Block("平台") } }))
custom = assert(store:Get(custom.assetId))

local collection = IslandProjectStore.Normalize(nil, nil, 10)
local project = IslandProjectStore.GetActive(collection)
local terrainList = TerrainCatalog.List()
assert(#terrainList >= 2, "market terrain tests require the authored terrain choices")
local alternateTerrainId = terrainList[2].id
project.name = "测试发布岛"
project.instances = {
    { id = 1, assetId = "builtin:compose:sunny-meadow-cottage", versionId = "1.0.0", x = 0, z = -16, scale = 1 },
    { id = 2, assetId = custom.assetId, versionId = custom.versionId, x = 8, z = -16, scale = 1 },
}
assert(IslandProjectStore.SetTerrain(collection, project.islandId, alternateTerrainId, 10.5))
assert(IslandProjectStore.SetPublished(collection, project.islandId, true, 11))
local profile = assert(IslandMarket.BuildProfile(collection, store))
assert(profile.schema == "island-market-profile/v1" and #profile.items == 1,
    "published island enters a bounded public profile")
assert(#profile.assets == 1 and profile.assets[1].components[1] == nil,
    "non-builtin island models are flattened and packaged exactly once")
assert(profile.items[1].project.terrainId == alternateTerrainId
    and profile.items[1].project.terrain.preset == alternateTerrainId,
    "published island snapshots preserve the selected terrain")

-- Publishing a busy current island must not be misreported as having too few
-- models because another published/inactive island contains a detailed custom
-- asset. The public snapshot now allows normal large workbench models, omits
-- genuinely empty legacy assets, and canonicalises old built-in ids.
local detailed = store:CreateBlank("千层花窗")
local detailedBlocks = {}
for index = 1, 1201 do
    local block = Block("细节" .. tostring(index), ((index - 1) % 40) * 0.05)
    block.position[3] = math.floor((index - 1) / 40) * 0.05
    block.size = { 0.04, 0.04, 0.04 }
    detailedBlocks[index] = block
end
detailed = assert(store:SaveDraft(detailed.assetId, {
    name = detailed.name, blocks = detailedBlocks,
}))
local emptyLegacy = store:CreateBlank("空白旧模型")
local multiCollection = IslandProjectStore.Normalize(nil, nil, 20)
local busyCurrent = IslandProjectStore.GetActive(multiCollection)
busyCurrent.name = "百景当前岛"
busyCurrent.instances = {}
for index = 1, 100 do
    busyCurrent.instances[index] = {
        id = index, assetId = "builtin:compose:short-grass-tuft",
        versionId = "1.0.0", x = index, z = 0, scale = 1,
    }
end
busyCurrent.instances[#busyCurrent.instances + 1] = {
    id = 101, assetId = "builtin:wonder:cloudspine-mountain",
    versionId = "1.0.0", x = 0, z = 1, scale = 1,
}
busyCurrent.instances[#busyCurrent.instances + 1] = {
    id = 102, assetId = emptyLegacy.assetId,
    versionId = emptyLegacy.versionId, x = 0, z = 2, scale = 1,
}
local detailedIsland = assert(IslandProjectStore.Create(multiCollection, "非活动细节岛", 21))
detailedIsland.instances = {
    { id = 1, assetId = detailed.assetId, versionId = detailed.versionId, x = 0, z = 0, scale = 1 },
}
assert(IslandProjectStore.SetPublished(multiCollection, busyCurrent.islandId, true, 22))
assert(IslandProjectStore.SetPublished(multiCollection, detailedIsland.islandId, true, 23))
assert(IslandProjectStore.SetActive(multiCollection, busyCurrent.islandId, 24))
local multiProfile, multiProfileError = IslandMarket.BuildProfile(multiCollection, store)
assert(multiProfile, "a 1201-block model on another published island must no longer reject the current island: "
    .. tostring(multiProfileError))
assert(#multiProfile.assets == 1 and #multiProfile.assets[1].blocks == 1201,
    "the detailed custom asset must be packaged once instead of hitting the former 1200-block limit")
assert(multiProfile.omittedEmptyInstances == 1,
    "an invisible empty legacy model should be omitted from the public copy without blocking publication")
local busyPublished
for _, item in ipairs(multiProfile.items) do
    if item.name == busyCurrent.name then busyPublished = item.project; break end
end
assert(busyPublished and #busyPublished.instances == 101,
    "the public busy island must preserve 100 visible models plus its canonical legacy builtin")
assert(busyPublished.instances[101].assetId == "builtin:compose:snow-cap-mountain"
    and #multiProfile.assets == 1,
    "legacy builtins must publish under their canonical id without consuming custom-asset capacity")
assert(math.abs((busyPublished.instances[101].scale or 0) - (1 / 0.44)) < 0.001,
    "legacy builtins must preserve their visible size when their canonical id is published")

-- The producer must reject the same dimensions that the remote consumer
-- rejects. Otherwise publishing appears successful while visitors silently
-- lose the oversized model and every instance that references it.
local oversized = store:CreateBlank("超宽测试模型")
oversized = assert(store:SaveDraft(oversized.assetId, {
    name = oversized.name,
    blocks = { {
        name = "超宽主体", position = { 0, 0.5, 0 }, size = { 121, 1, 1 },
        rotation = { 0, 0, 0 }, color = "#f2e7cf", materialId = "solid", shapeId = "box",
    } },
}))
local oversizedCollection = IslandProjectStore.Normalize(nil, nil, 30)
local oversizedIsland = IslandProjectStore.GetActive(oversizedCollection)
oversizedIsland.name = "尺寸校验岛"
oversizedIsland.instances = {
    { id = 1, assetId = oversized.assetId, versionId = oversized.versionId, x = 0, z = 0, scale = 1 },
}
assert(IslandProjectStore.SetPublished(oversizedCollection, oversizedIsland.islandId, true, 31))
local oversizedProfile, oversizedError = IslandMarket.BuildProfile(oversizedCollection, store)
assert(not oversizedProfile and tostring(oversizedError):find("尺寸超过 120", 1, true),
    "oversized custom assets must fail before upload instead of disappearing for visitors")

local variedCollection = IslandProjectStore.Normalize(nil, nil, 40)
local variedIsland = IslandProjectStore.GetActive(variedCollection)
variedIsland.name, variedIsland.instances = "模型种类校验岛", {}
for index = 1, IslandMarket.MAX_ASSETS + 1 do
    local varied = store:CreateBlank("独立小模型" .. tostring(index))
    varied = assert(store:SaveDraft(varied.assetId, {
        name = varied.name, blocks = { Block("主体" .. tostring(index)) },
    }))
    variedIsland.instances[index] = {
        id = index, assetId = varied.assetId, versionId = varied.versionId,
        x = index, z = 0, scale = 1,
    }
end
assert(IslandProjectStore.SetPublished(variedCollection, variedIsland.islandId, true, 41))
local variedProfile, variedError = IslandMarket.BuildProfile(variedCollection, store)
assert(not variedProfile and tostring(variedError):find("超过 48 个不同", 1, true)
    and not tostring(variedError):find("积木，超过", 1, true),
    "too many unique custom assets must report model kinds rather than a false block-count error")

local publicCollection = IslandProjectStore.Normalize(nil, nil, 50)
for index = 1, IslandMarket.MAX_PUBLIC_ISLANDS do
    local publicIsland = index == 1 and IslandProjectStore.GetActive(publicCollection)
        or assert(IslandProjectStore.Create(publicCollection, "发布岛 " .. tostring(index), 50 + index))
    publicIsland.name = "发布岛 " .. tostring(index)
    publicIsland.instances = { {
        id = 1, assetId = "builtin:compose:sunny-meadow-cottage",
        versionId = "1.0.0", x = index, z = 0, scale = 1,
    } }
    assert(IslandProjectStore.SetPublished(
        publicCollection, publicIsland.islandId, true, 60 + index))
end
local fiveIslandProfile = assert(IslandMarket.BuildProfile(publicCollection, store))
assert(#fiveIslandProfile.items == 5,
    "one player should be able to publish five islands")
local sixthIsland = assert(IslandProjectStore.Create(publicCollection, "第六座发布岛", 70))
sixthIsland.instances = { {
    id = 1, assetId = "builtin:compose:sunny-meadow-cottage",
    versionId = "1.0.0", x = 6, z = 0, scale = 1,
} }
assert(IslandProjectStore.SetPublished(publicCollection, sixthIsland.islandId, true, 71))
local sixIslandProfile, sixIslandError = IslandMarket.BuildProfile(publicCollection, store)
assert(not sixIslandProfile and tostring(sixIslandError):find("最多同时发布 5 座空岛", 1, true),
    "a sixth published island should report the shared five-island limit")
assert(IslandProjectStore.SetPublished(publicCollection, sixthIsland.islandId, false, 72))
assert(#assert(IslandMarket.BuildProfile(publicCollection, store)).items == 5,
    "unpublishing one island should immediately free a publication slot")

local oversizedRemoteProfile = IslandMarket.Copy(fiveIslandProfile)
oversizedRemoteProfile.items[6] = IslandMarket.Copy(oversizedRemoteProfile.items[1])
oversizedRemoteProfile.items[6].publicationId = "remote-sixth"
assert(#IslandMarket.NormalizeRemoteProfile(oversizedRemoteProfile, "limit-test") == 5,
    "remote profiles from malformed or newer clients must normalize to five islands")

local remoteProfile = IslandMarket.Copy(profile)
remoteProfile.ownerId = "spoofed"
remoteProfile.assets[1].assetId = "builtin:compose:spoof"
remoteProfile.assets[1].script = "must not survive"
remoteProfile.items[1].project.instances[2].assetId = "builtin:compose:spoof"
local entries = IslandMarket.NormalizeRemoteProfile(remoteProfile, "42")
assert(#entries == 1 and #entries[1].project.instances == 2, "remote island retains safe builtin and packaged models")
assert(entries[1].project.instances[2].assetId:find("^island%-market:42:"),
    "remote custom asset identity is namespaced by its real cloud owner")
assert(entries[1].assets[1].script == nil and #entries[1].assets[1].components == 0,
    "remote island packages cannot inject scripts or live dependencies")
assert(entries[1].project.terrainId == alternateTerrainId
    and entries[1].project.terrain.preset == alternateTerrainId,
    "remote exploration preserves a valid published terrain")
assert(store:CacheExternalAssets(entries[1].assets), "visiting downloads exact packaged model versions")
assert(store:Get(entries[1].project.instances[2].assetId, entries[1].project.instances[2].versionId),
    "downloaded visit assets remain resolvable by the island world")

local unknownTerrainProfile = IslandMarket.Copy(profile)
unknownTerrainProfile.items[1].project.terrainId = "not-a-real-terrain"
unknownTerrainProfile.items[1].project.terrain = { preset = "not-a-real-terrain" }
local unknownTerrainEntries = IslandMarket.NormalizeRemoteProfile(unknownTerrainProfile, "43")
assert(unknownTerrainEntries[1].project.terrainId == TerrainCatalog.DEFAULT_ID
    and unknownTerrainEntries[1].project.terrain.preset == TerrainCatalog.DEFAULT_ID,
    "unknown remote terrain identifiers fall back to the current three-island terrain")

local publishSaved = false
local publishBatchSetCalls = 0
clientCloud = {
    userId = 7,
    BatchSet = function()
        publishBatchSetCalls = publishBatchSetCalls + 1
        local builder = {}
        function builder:Set() return self end
        function builder:SetInt() return self end
        function builder:Save(_, callbacks) publishSaved = true; callbacks.ok() end
        return builder
    end,
    GetRankList = function(_, _, _, _, callbacks)
        callbacks.ok({ { userId = 42, score = { [IslandMarket.PROFILE_KEY] = remoteProfile } } })
    end,
}
GetUserNickname = function(options)
    options.onSuccess({ { userId = 42, nickname = "云端岛主" } })
end

local loaded
assert(IslandMarket.Load({ ok = function(items, source) loaded = items; assert(source == "cloud") end }))
assert(#loaded == 1 and loaded[1].owner == "云端岛主", "exploration aggregates public islands and resolves owners")
assert(loaded[1].project.terrainId == alternateTerrainId,
    "cloud discovery keeps the published terrain identity")
assert(IslandMarket.Publish(profile, { ok = function(source) assert(source == "cloud") end }))
assert(publishSaved, "island publication commits its cloud profile and activity score")
local rejectedMessage
local callsBeforeRejectedPublish = publishBatchSetCalls
assert(not IslandMarket.Publish(oversizedRemoteProfile, {
    error = function(message) rejectedMessage = message end,
}))
assert(tostring(rejectedMessage):find("最多同时发布 5 座空岛", 1, true)
    and publishBatchSetCalls == callsBeforeRejectedPublish,
    "direct publication must reject a sixth item before starting a cloud write")
local sampleStart = os.clock()
local samples = IslandMarket.SampleEntries(store)
local sampleElapsed = os.clock() - sampleStart
local cachedSamples = IslandMarket.SampleEntries()
cachedSamples[1].name = "不能污染缓存"
assert(IslandMarket.SampleEntries()[1].name ~= "不能污染缓存",
    "reopening exploration must reuse generation work without sharing mutable sample state")
assert(sampleElapsed < 4.0,
    string.format("offline sample generation regressed to %.3fs", sampleElapsed))
local generationStats = IslandMarket.SampleGenerationStats()
assert((generationStats.placementChecks or 0) > 0
    and (generationStats.nearbyCandidates or math.huge)
        < (generationStats.fullPoolCandidates or 0) / 20,
    "sample placement must query a bounded spatial neighbourhood instead of scanning the full pool")
assert((generationStats.densityComputations or math.huge) <= #store.builtins,
    "sample visual density must be computed at most once per model asset")
assert(#samples == 5, "offline exploration must expose the five authored theme islands")
assert((samples[1].likes or 0) > 0 and (samples[1].updatedAt or 0) > 0,
    "offline exploration samples provide useful hot and latest sorting metadata")
local requiredSamples = {
    ["sample:snow"] = true,
    ["sample:skyport"] = true,
    ["sample:nature"] = true,
    ["sample:town"] = true,
    ["sample:park"] = true,
}
local sampleIds = {}
local expectedSampleFingerprints = {
    ["sample:town"] = 1990766904,
    ["sample:snow"] = 1764031557,
    ["sample:skyport"] = 496142611,
    ["sample:nature"] = 564000191,
    ["sample:park"] = 1510583308,
}
local function SampleFingerprint(sample)
    local serialized = {}
    for _, instance in ipairs(sample.project.instances or {}) do
        serialized[#serialized + 1] = table.concat({
            tostring(instance.assetId),
            string.format("%.4f", instance.x or 0),
            string.format("%.4f", instance.y or 0),
            string.format("%.4f", instance.z or 0),
            string.format("%.6f", instance.rotationY or 0),
            string.format("%.4f", instance.scale or 1),
        }, "|")
    end
    local hash, text = 17, table.concat(serialized, ";")
    for index = 1, #text do hash = (hash * 131 + text:byte(index)) % 2147483647 end
    return hash
end
for _, sample in ipairs(samples) do
    assert(not sampleIds[sample.id], "sample island ids must remain unique")
    sampleIds[sample.id] = true
    requiredSamples[sample.id] = nil
    assert(SampleFingerprint(sample) == expectedSampleFingerprints[sample.id],
        sample.name .. " layout changed while optimizing sample generation")
    assert(sample.project.terrainId == TerrainCatalog.DEFAULT_ID
        and sample.project.terrain.preset == TerrainCatalog.DEFAULT_ID,
        "legacy exploration samples default to the current three-island terrain")
    assert(sample.count == IslandMarket.SAMPLE_INSTANCES and sample.count == #sample.project.instances,
        sample.name .. " must contain the complete authored exploration composition")
    local placed, uniqueAssets, categories = {}, {}, {}
    local hasPond, buildingCount, propCount = false, 0, 0
    local hasSnow, aircraftCount, mountainCount, forestCount, parkCount = false, 0, 0, 0, 0
    local townRoads, townFences, townRows = 0, 0, {}
    local islandCounts, coverage = {}, {}
    for _, island in ipairs(IslandLayout.ISLANDS) do
        islandCounts[island.id] = 0
        coverage[island.id] = { quadrants = { 0, 0, 0, 0 }, outer = 0 }
    end
    for index, instance in ipairs(sample.project.instances) do
        local asset = assert(store:Get(instance.assetId, instance.versionId),
            sample.name .. " references missing model " .. tostring(instance.assetId))
        uniqueAssets[instance.assetId] = true
        categories[asset.category] = true
        if asset.category == "可进入建筑" then buildingCount = buildingCount + 1 end
        if asset.category == "街景设施" or asset.category == "围栏构件" then propCount = propCount + 1 end
        if instance.assetId == "builtin:compose:snow-cap-mountain" then hasSnow = true end
        if instance.assetId == "builtin:compose:cloud-courier-airship"
            or instance.assetId == "builtin:compose:wind-ribbon-glider"
            or instance.assetId == "builtin:compose:crystal-hover-skiff"
            or instance.assetId == "builtin:compose:storybook-balloon" then
            aircraftCount = aircraftCount + 1
        end
        if instance.assetId == "builtin:compose:snow-cap-mountain"
            or instance.assetId == "builtin:compose:layered-rocky-hill"
            or instance.assetId == "builtin:compose:needle-stone-peak"
            or instance.assetId == "builtin:compose:walkable-cliff-terrace"
            or instance.assetId == "builtin:compose:waterfall-rock-gate" then
            mountainCount = mountainCount + 1
        end
        if instance.assetId == "builtin:compose:tall-layered-pine"
            or instance.assetId == "builtin:compose:tall-guardian-oak"
            or instance.assetId == "builtin:compose:storybook-birch"
            or instance.assetId == "builtin:compose:soft-riverside-willow"
            or instance.assetId == "builtin:compose:round-meadow-oak" then
            forestCount = forestCount + 1
        end
        if instance.assetId == "builtin:compose:vine-garden-arch"
            or instance.assetId == "builtin:compose:curved-wood-bench"
            or instance.assetId == "builtin:compose:long-flower-planter"
            or instance.assetId == "builtin:compose:white-picket-fence" then
            parkCount = parkCount + 1
        end
        if sample.id == "sample:town" then
            if instance.assetId == "builtin:compose:straight-cobble-path"
                or instance.assetId == "builtin:compose:curved-cobble-path" then townRoads = townRoads + 1 end
            if instance.assetId == "builtin:compose:rustic-wood-fence"
                or instance.assetId == "builtin:compose:wood-fence-corner"
                or instance.assetId == "builtin:compose:white-picket-fence"
                or instance.assetId == "builtin:compose:swing-garden-gate" then townFences = townFences + 1 end
            if asset.category == "可进入建筑" then
                local row = math.floor((tonumber(instance.z) or 0) + 0.5)
                townRows[row] = (townRows[row] or 0) + 1
            end
        end
        local containingIsland = IslandLayout.IslandAt(instance.x, instance.z)
        assert(containingIsland, sample.name .. " contains an instance outside the three authored islands")
        islandCounts[containingIsland.id] = islandCounts[containingIsland.id] + 1
        local dx, dz = instance.x - containingIsland.x, instance.z - containingIsland.z
        local quadrant = (dx >= 0 and 1 or 0) + (dz >= 0 and 2 or 0) + 1
        coverage[containingIsland.id].quadrants[quadrant]
            = coverage[containingIsland.id].quadrants[quadrant] + 1
        if dx * dx + dz * dz >= (containingIsland.radius * 0.62) ^ 2 then
            coverage[containingIsland.id].outer = coverage[containingIsland.id].outer + 1
        end
        if instance.assetId == "builtin:compose:shallow-lily-pond" then hasPond = true end
        local valid, reason = IslandLayout.IsPlacementValid(
            placed, asset, instance.x, instance.z, instance.rotationY, instance.scale)
        assert(valid, sample.name .. " has an invalid mock placement at #" .. tostring(index)
            .. " " .. tostring(instance.assetId) .. ": " .. tostring(reason))
        placed[#placed + 1] = {
            id = index, x = instance.x, z = instance.z,
            rotationY = instance.rotationY, scale = instance.scale, renderAsset = asset,
        }
    end
    local uniqueCount = 0
    for _ in pairs(uniqueAssets) do uniqueCount = uniqueCount + 1 end
    assert(uniqueCount >= 20, sample.name .. " must demonstrate many different reusable model combinations")
    for _, island in ipairs(IslandLayout.ISLANDS) do
        assert(islandCounts[island.id] == IslandMarket.SAMPLE_PER_ISLAND,
            sample.name .. " must fill " .. island.name .. " instead of concentrating on one island")
        assert(coverage[island.id].outer >= 40,
            sample.name .. " must extend scenery to the outer edge of " .. island.name)
        for quadrant, count in ipairs(coverage[island.id].quadrants) do
            assert(count >= 10, sample.name .. " leaves quadrant " .. tostring(quadrant)
                .. " of " .. island.name .. " visually empty")
        end
    end
    if sample.id == "sample:town" then
        local orderedRows = 0
        for _, count in pairs(townRows) do if count >= 3 then orderedRows = orderedRows + 1 end end
        assert(buildingCount >= 16 and townRoads >= 16 and townFences >= 12 and orderedRows >= 4,
            sample.name .. " must read as an orderly town with houses, streets and wooden fencing")
    elseif sample.id == "sample:snow" then
        assert(hasSnow and mountainCount >= 7 and forestCount >= 7,
            sample.name .. " must read as a snowy mountain expedition")
    elseif sample.id == "sample:skyport" then
        assert(aircraftCount >= 4 and categories["飞行器"],
            sample.name .. " must read as a flying theme with multiple aircraft")
    elseif sample.id == "sample:nature" then
        assert(mountainCount >= 10 and forestCount >= 12 and hasPond and categories["植被单件"],
            sample.name .. " must combine high mountains, forest, lake and grassland")
    elseif sample.id == "sample:park" then
        assert(parkCount >= 16 and hasPond and categories["街景设施"],
            sample.name .. " must read as an open park with paths, flowers and amenities")
    end
end
print(string.format(
    "island sample generation %.3fs · nearby %d / legacy pool %d",
    sampleElapsed, generationStats.nearbyCandidates or 0,
    generationStats.fullPoolCandidates or 0))
for id in pairs(requiredSamples) do error("missing required exploration sample " .. tostring(id)) end

print("island-market-spec: ok")
