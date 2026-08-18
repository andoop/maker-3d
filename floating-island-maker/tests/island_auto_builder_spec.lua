package.path = "scripts/?.lua;" .. package.path

local IslandAutoBuilder = require("IslandAutoBuilder")
local IslandLayout = require("IslandLayout")

local function Asset(id, category, width, depth, name)
    return {
        assetId = "test:" .. id, versionId = "1.0.0", name = name or id,
        category = category, recommendedScale = 1,
        bounds = {
            min = { -width * 0.5, 0, -depth * 0.5 },
            max = { width * 0.5, 2, depth * 0.5 },
            size = { width, 2, depth },
        },
    }
end

local assets = {
    Asset("mountain", "山体构件", 7.0, 6.0, "层叠险峰"),
    Asset("ruin", "遗迹构件", 5.5, 3.2, "古城断门"),
    Asset("house-a", "可进入建筑", 5.0, 4.6, "坡顶民居"),
    Asset("house-b", "可进入建筑", 4.6, 4.2, "云上商店"),
    Asset("path", "组合构件", 1.1, 5.0, "直线卵石路"),
    Asset("lamp", "街景设施", 0.7, 0.7, "暖光路灯"),
    Asset("fence", "围栏构件", 3.2, 0.25, "原木围栏"),
    Asset("tree", "树木单件", 3.4, 3.2, "高冠橡树"),
    Asset("grass", "植被单件", 0.5, 0.5, "短草簇"),
    Asset("pond", "组合构件", 4.2, 3.0, "睡莲浅池"),
    Asset("airship", "飞行器", 5.2, 2.8, "云港飞艇"),
}

local layout = IslandLayout.Resolve("storybook-triple-archipelago-large")

local function Encode(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local result = { "{" }
    for _, key in ipairs(keys) do result[#result + 1] = tostring(key) .. "=" .. Encode(value[key]) .. ";" end
    result[#result + 1] = "}"
    return table.concat(result)
end

local function ProjectionRadius(footprint, axisX, axisZ)
    return footprint.halfWidth * math.abs(footprint.axisXx * axisX + footprint.axisXz * axisZ)
        + footprint.halfDepth * math.abs(footprint.axisZx * axisX + footprint.axisZz * axisZ)
end

local function Overlaps(first, second)
    local deltaX, deltaZ = second.x - first.x, second.z - first.z
    for _, axis in ipairs({
        { first.axisXx, first.axisXz }, { first.axisZx, first.axisZz },
        { second.axisXx, second.axisXz }, { second.axisZx, second.axisZz },
    }) do
        local separation = math.abs(deltaX * axis[1] + deltaZ * axis[2])
        local occupied = ProjectionRadius(first, axis[1], axis[2])
            + ProjectionRadius(second, axis[1], axis[2])
        if separation >= occupied - 0.000001 then return false end
    end
    return true
end

local function AssetMap(values)
    local result = {}
    for _, asset in ipairs(values) do result[asset.assetId] = asset end
    return result
end

local function ReservationFootprint(targetLayout, reservation)
    return targetLayout:Footprint(nil, {
        bounds = {
            min = { -reservation.width * 0.5, 0, -reservation.depth * 0.5 },
            max = { reservation.width * 0.5, 1, reservation.depth * 0.5 },
            size = { reservation.width, 1, reservation.depth },
        },
    }, reservation.x, reservation.z, reservation.rotationY, 1)
end

local function AssertPlanGeometry(plan, targetLayout, knownAssets, existing)
    local byId, footprints = AssetMap(knownAssets), {}
    for index, instance in ipairs(plan.instances) do
        local asset = assert(byId[instance.assetId], "plan introduced an unknown model")
        local footprint = targetLayout:Footprint(nil, asset,
            instance.x, instance.z, instance.rotationY, instance.scale)
        local supported, reason = targetLayout:IsFootprintSupported(footprint, 0.12)
        assert(supported, "model footprint crossed the terrain boundary: " .. tostring(reason))
        local island = assert(targetLayout:GetIsland(instance.autoIslandId),
            "every generated model identifies its hosting island")
        for _, corner in ipairs(footprint.corners) do
            local rx = island.radiusX - targetLayout.edgeInset
            local rz = island.radiusZ - targetLayout.edgeInset
            local dx, dz = corner.x - island.x, corner.z - island.z
            assert(dx * dx / (rx * rx) + dz * dz / (rz * rz) <= 1.000001,
                "model corner crossed its assigned island")
        end
        for previousIndex, previous in ipairs(footprints) do
            assert(not Overlaps(footprint, previous), string.format(
                "generated footprints overlap: %d (%s) and %d (%s)",
                previousIndex, plan.instances[previousIndex].assetId, index, instance.assetId))
        end
        footprints[#footprints + 1] = footprint
    end

    for _, source in ipairs(existing or {}) do
        local asset = source.renderAsset or byId[source.assetId]
        local footprint = targetLayout:Footprint(source, asset)
        for index, generated in ipairs(footprints) do
            assert(not Overlaps(footprint, generated),
                "generated model overlapped existing model at index " .. tostring(index))
        end
    end

    local portalCount = 0
    for _, reservation in ipairs(plan.reservations or {}) do
        if reservation.type == "portal" then
            portalCount = portalCount + 1
            local footprint = ReservationFootprint(targetLayout, reservation)
            for index, generated in ipairs(footprints) do
                assert(not Overlaps(footprint, generated),
                    "portal landing space was occupied by generated model " .. tostring(index))
            end
        end
    end
    assert(portalCount == #targetLayout.islands,
        "each island needs a clear future portal landing pad")
end

local first = IslandAutoBuilder.Build({
    selectedAssets = assets, layout = layout, seed = "same-seed", theme = "mixed",
})
local second = IslandAutoBuilder.Build({
    selectedAssets = assets, layout = layout, seed = "same-seed", theme = "mixed",
})
assert(Encode(first) == Encode(second), "same selections, terrain, theme and seed must be deterministic")
assert(first.schema == "island-auto-build/v1" and first.theme.id == "mixed",
    "plan exposes a stable schema and chosen theme")
assert(first.stats.placedUnique == #assets,
    "the planner should use every selected model when the island has room")
assert(first.stats.placed > #assets and first.stats.duplicates > 0,
    "small composable pieces should be repeated to create a genuinely rich island")
assert(type(first.stats.summary) == "string" and #first.stats.summary > 12,
    "the generated composition needs an explainable summary")
assert(first.stats.sampledOut == 0 and first.stats.spaceSkipped == 0,
    "a small curated selection should fit without density sampling or forced loss")
assert(#first.reservations == #layout.islands * 3,
    "the planner reserves an avenue, landing and portal pad on every island")
AssertPlanGeometry(first, layout, assets)

local allowed, found = {}, {}
for _, asset in ipairs(assets) do allowed[asset.assetId] = true end
local islandsUsed = {}
for _, instance in ipairs(first.instances) do
    assert(allowed[instance.assetId], "auto build cannot introduce an unselected model")
    found[instance.assetId] = true
    islandsUsed[tostring(instance.autoIslandId)] = true
    local asset
    for _, candidate in ipairs(assets) do if candidate.assetId == instance.assetId then asset = candidate; break end end
    local footprint = layout:Footprint(nil, asset, instance.x, instance.z, instance.rotationY, instance.scale)
    local supported, reason = layout:IsFootprintSupported(footprint, 0.12)
    assert(supported, "every generated model footprint must stay on one level island surface: " .. tostring(reason))
end
for _, asset in ipairs(assets) do assert(found[asset.assetId], "selected asset was not used: " .. asset.assetId) end
local usedCount = 0
for _ in pairs(islandsUsed) do usedCount = usedCount + 1 end
assert(usedCount == #layout.islands, "a rich mixed selection should deliberately compose across every available island")

-- The role map is the basis of themed clustering: settlement pieces face the
-- common entrance, forest pieces live in the grove sector and large scenery
-- occupies the distant vista island instead of being randomly interleaved.
local zoneCounts = {}
for _, instance in ipairs(first.instances) do
    zoneCounts[instance.autoZone] = (zoneCounts[instance.autoZone] or 0) + 1
    if instance.assetId == "test:house-a" or instance.assetId == "test:house-b" then
        assert(instance.autoRole == "building" and instance.autoZone == "settlement",
            "buildings must form an entrance-facing settlement cluster")
        local dx, dz = instance.autoFacingX - instance.x, instance.autoFacingZ - instance.z
        local length = math.sqrt(dx * dx + dz * dz)
        local dot = math.sin(instance.rotationY) * dx / length
            + math.cos(instance.rotationY) * dz / length
        assert(dot > 0.995, "building doors must face the reserved avenue")
    elseif instance.assetId == "test:tree" then
        assert(instance.autoRole == "tree" and instance.autoZone == "grove",
            "trees must form a recognizable grove")
    elseif instance.assetId == "test:mountain" then
        assert(instance.autoRole == "mountain" and instance.autoZone == "vista",
            "mountains must anchor the scenic vista zone")
    end
end
assert((zoneCounts.settlement or 0) >= 2 and (zoneCounts.avenue or 0) >= 4
    and (zoneCounts.grove or 0) >= 2 and (zoneCounts.garden or 0) >= 2,
    "the result needs multiple legible themed districts rather than uniform random scatter")

-- No pair may share exactly the same centre; this is the strictest symptom of
-- complete burial and also catches deterministic candidate reuse.
local positions = {}
for _, instance in ipairs(first.instances) do
    local key = string.format("%.3f:%.3f", instance.x, instance.z)
    assert(not positions[key], "generated models must not be completely stacked at one centre")
    positions[key] = true
end

local subset = { assets[3], assets[8], assets[9] }
local subsetPlan = IslandAutoBuilder.Build({
    selectedAssets = subset, terrainId = "windstep-meadow", seed = 77, theme = "forest",
})
local subsetAllowed = { [subset[1].assetId] = true, [subset[2].assetId] = true, [subset[3].assetId] = true }
assert(subsetPlan.stats.selected == 3 and subsetPlan.stats.placedUnique == 3,
    "deselecting models must reduce the requested set without losing selected types")
for _, instance in ipairs(subsetPlan.instances) do
    assert(subsetAllowed[instance.assetId], "subset generation used a deselected model")
    assert(instance.y == 0,
        "generated Y is a terrain-relative offset and must stay zero on elevated terrain")
end
local usedElevatedIsland = false
local windstepLayout = IslandLayout.Resolve("windstep-meadow")
for _, instance in ipairs(subsetPlan.instances) do
    local surfaceY = assert(windstepLayout:SurfaceAt(instance.x, instance.z, 0))
    if math.abs(surfaceY - windstepLayout:DefaultGroundY()) > 0.5 then usedElevatedIsland = true end
end
assert(usedElevatedIsland,
    "elevated terrain coverage must exercise the relative-Y invariant")

local sideDoorHouse = Asset("side-door-house", "可进入建筑", 6.0, 3.4, "侧门工坊")
sideDoorHouse.blocks = {
    { name = "一层right墙·门洞左", position = { 3, 1, -0.8 }, size = { 0.2, 2, 1 } },
}
local sideDoorPlan = IslandAutoBuilder.Build({
    selectedAssets = { sideDoorHouse }, layout = layout,
    seed = "side-door", theme = "village",
})
local sideDoorInstance = assert(sideDoorPlan.instances[1], "side-door building should fit")
assert(sideDoorInstance.autoEntranceX == 1 and sideDoorInstance.autoEntranceZ == 0,
    "the planner must detect an authored side entrance")
local sideDx = sideDoorInstance.autoFacingX - sideDoorInstance.x
local sideDz = sideDoorInstance.autoFacingZ - sideDoorInstance.z
local sideLength = math.sqrt(sideDx * sideDx + sideDz * sideDz)
local sideCosine, sideSine = math.cos(sideDoorInstance.rotationY), math.sin(sideDoorInstance.rotationY)
local sideForwardX = sideDoorInstance.autoEntranceX * sideCosine
    + sideDoorInstance.autoEntranceZ * sideSine
local sideForwardZ = -sideDoorInstance.autoEntranceX * sideSine
    + sideDoorInstance.autoEntranceZ * sideCosine
assert((sideForwardX * sideDx + sideForwardZ * sideDz) / sideLength > 0.995,
    "the actual side doorway, not assumed local +Z, must face the avenue")
AssertPlanGeometry(sideDoorPlan, layout, { sideDoorHouse })

local withExisting = IslandAutoBuilder.Build({
    selectedAssets = { assets[3] }, layout = layout, seed = 9,
    existingInstances = {
        { id = 80, assetId = assets[3].assetId, x = 0, y = 0.42, z = -16, scale = 1,
            rotationY = 0, renderAsset = assets[3] },
    },
})
assert(withExisting.instances[1] and withExisting.instances[1].id == 81,
    "generated ids continue after existing island instances")
assert(math.abs(withExisting.instances[1].x) > 0.01 or math.abs(withExisting.instances[1].z + 16) > 0.01,
    "new composition must not fully bury itself in an existing model")
AssertPlanGeometry(withExisting, layout, { assets[3] }, {
    { id = 80, assetId = assets[3].assetId, x = 0, y = 0.42, z = -16, scale = 1,
        rotationY = 0, renderAsset = assets[3] },
})

local differentSeed = IslandAutoBuilder.Build({
    selectedAssets = assets, layout = layout, seed = "different-seed", theme = "mixed",
})
assert(Encode(first.instances) ~= Encode(differentSeed.instances),
    "changing the seed should produce another valid authored arrangement")

-- A complete library is an input pool, not an instruction to carpet the
-- terrain. The sampler must keep role variety while respecting a visual count
-- and real-footprint density budget.
local categoryCycle = {
    { "可进入建筑", "房屋" }, { "树木单件", "树木" },
    { "植被单件", "花草" }, { "山体构件", "山体" },
    { "遗迹构件", "遗迹" }, { "街景设施", "路灯" },
    { "围栏构件", "围栏" }, { "组合构件", "石径 road" },
}
local crowdedAssets = {}
for index = 1, 144 do
    local source = categoryCycle[((index - 1) % #categoryCycle) + 1]
    local width = 0.55 + (index % 7) * 0.31
    local depth = 0.50 + (index % 5) * 0.37
    crowdedAssets[#crowdedAssets + 1] = Asset("crowded-" .. tostring(index),
        source[1], width, depth, source[2] .. tostring(index))
end
local started = os.clock()
local crowded = IslandAutoBuilder.Build({
    selectedAssets = crowdedAssets, layout = layout,
    seed = "large-library", theme = "mixed",
})
local elapsed = os.clock() - started
assert(crowded.stats.selected == #crowdedAssets and crowded.stats.sampledOut > 0,
    "large selections must be deterministically sampled")
assert(crowded.stats.considered <= 48 and crowded.stats.placed <= crowded.stats.densityLimit,
    "density control must bound both unique variety and total model count")
assert(crowded.stats.placedUnique >= 8,
    "sampling should retain broad role variety instead of one repeated category")
assert(crowded.stats.duplicates == 0,
    "a dense full-library selection should prefer variety over duplicate clutter")
AssertPlanGeometry(crowded, layout, crowdedAssets)
assert(elapsed < 1.5,
    string.format("large-library planning must stay interactive (%.3fs)", elapsed))

local crowdedAgain = IslandAutoBuilder.Build({
    selectedAssets = crowdedAssets, layout = layout,
    seed = "large-library", theme = "mixed",
})
assert(Encode(crowded) == Encode(crowdedAgain),
    "density sampling and strict packing must remain deterministic")

print("island_auto_builder_spec: ok")
