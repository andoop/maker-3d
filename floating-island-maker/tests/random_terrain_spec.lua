package.path = "scripts/?.lua;" .. package.path

local Generator = require("RandomTerrainGenerator")
local Catalog = require("IslandTerrainCatalog")
local IslandLayout = require("IslandLayout")
local StorybookIslandData = require("StorybookIslandData")
local Store = require("IslandProjectStore")

local function Canonical(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(first, second) return tostring(first) < tostring(second) end)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        parts[#parts + 1] = Canonical(key) .. "=" .. Canonical(value[key])
    end
    parts[#parts + 1] = "}"
    return table.concat(parts, "|")
end

local first = Generator.Generate("repeatable-seed")
local second = Generator.Generate("repeatable-seed")
assert(Canonical(first) == Canonical(second), "the same seed must reproduce identical terrain data")
assert(first.id == Generator.IdForSeed("repeatable-seed")
    and Generator.SeedFromId(first.id) == first.seed,
    "generated IDs must round-trip the normalized seed")
assert(Canonical(first) ~= Canonical(Generator.Generate("different-seed")),
    "different seeds must generate a different terrain")

math.randomseed(12477)
local before = math.random()
Generator.Generate(7788)
local after = math.random()
math.randomseed(12477)
assert(before == math.random() and after == math.random(),
    "terrain generation must not perturb Lua's shared random stream")

local formations = {}
for _, seed in ipairs({ 1, 2, 5, 314159 }) do
    local terrain = Generator.Generate(seed)
    formations[terrain.formation] = true
    assert(terrain.generated and terrain.pureTerrain
        and terrain.algorithm == "seeded-floating-archipelago",
        "random terrain records must remain pure landform data")
    assert(terrain.instances == nil and terrain.decorations == nil,
        "the generator must never inject model or decoration instances")
    assert(#terrain.islands >= 5 and #terrain.islands <= 7
        and #terrain.bridges <= 9,
        "generation work must stay inside the mobile-safe island and bridge budget")
    assert(terrain.connectionStyle == "shattered-stepping-stones",
        "random layouts must declare the broken bridge visual language")

    local byId, buildableCount = {}, 0
    local minimumY, maximumY = math.huge, -math.huge
    for _, island in ipairs(terrain.islands) do
        assert(not byId[island.id], "random island IDs must be unique")
        byId[island.id] = island
        minimumY, maximumY = math.min(minimumY, island.groundY), math.max(maximumY, island.groundY)
        if island.buildable then
            buildableCount = buildableCount + 1
            assert(island.radiusX >= 27 and island.radiusZ >= 23,
                "the primary island must preserve a broad flat construction lawn")
        end
    end
    assert(buildableCount == 1 and maximumY - minimumY >= 10,
        "every random terrain needs one clear building lawn and a dramatic height range")

    for firstIndex = 1, #terrain.islands - 1 do
        local a = terrain.islands[firstIndex]
        for secondIndex = firstIndex + 1, #terrain.islands do
            local b = terrain.islands[secondIndex]
            local dx, dz = b.x - a.x, b.z - a.z
            local rx = a.radiusX + b.radiusX + 1.5
            local rz = a.radiusZ + b.radiusZ + 1.5
            assert(dx * dx / (rx * rx) + dz * dz / (rz * rz) > 1,
                "generated landmasses must not overlap")
        end
    end

    local graph = {}
    for _, island in ipairs(terrain.islands) do graph[island.id] = {} end
    for _, bridge in ipairs(terrain.bridges) do
        assert(byId[bridge.from] and byId[bridge.to] and bridge.from ~= bridge.to,
            "every bridge must connect two real islands")
        assert(bridge.broken == true and bridge.style == "shattered-stepping-stones"
            and bridge.stepSpacing >= 2.2,
            "every generated connector must be an explicit spacious broken bridge")
        graph[bridge.from][#graph[bridge.from] + 1] = bridge.to
        graph[bridge.to][#graph[bridge.to] + 1] = bridge.from
    end
    local visited, queue = {}, { terrain.islands[1].id }
    visited[queue[1]] = true
    local cursor = 1
    while queue[cursor] do
        local id = queue[cursor]
        cursor = cursor + 1
        for _, nextId in ipairs(graph[id]) do
            if not visited[nextId] then visited[nextId], queue[#queue + 1] = true, nextId end
        end
    end
    for _, island in ipairs(terrain.islands) do
        assert(visited[island.id], "the broken stepping-stone graph must still connect every island")
    end

    local layout = IslandLayout.Resolve(terrain.id)
    assert(layout.id == terrain.id and #layout.islands == #terrain.islands,
        "encoded random terrain IDs must resolve without an in-memory registry")
    for _, bridge in ipairs(layout.bridges) do
        local metrics = assert(layout:GetBridgeMetrics(bridge))
        local steps = math.max(1, math.ceil(metrics.length / bridge.stepSpacing),
            math.ceil(math.abs(metrics.endY - metrics.startY) / bridge.maxStepHeight))
        assert(metrics.length / steps >= 1.35,
            "random broken bridge steps must not collapse into a crowded staircase")
    end
end
assert(formations["random-broken-halo"] and formations["random-sky-ridge"]
    and formations["random-twin-crescent"],
    "the seeded algorithm must expose all three topology families")

StorybookIslandData.ClearCache()
local rendered = StorybookIslandData.Build(IslandLayout.Resolve(first.id))
assert(#rendered.decorRocks == 0 and #rendered.shrubs == 0 and #rendered.moss == 0
    and #rendered.terrainWater == 0 and #rendered.terrainFoliage == 0
    and #rendered.distantStructures == 0 and #rendered.distantFoliage == 0,
    "random terrain rendering must remain free of authored decor models")

local collection = Store.Normalize(nil, nil, 10)
local record = assert(Store.CreateRandomTerrain(collection, "云上故乡", 4242, 11))
assert(record.id == Generator.IdForSeed(4242) and #collection.randomTerrains == 1,
    "creating a random terrain persists its compact seed metadata")
assert(#Catalog.List(collection.randomTerrains) == #Catalog.List() + 1,
    "the catalog can append managed random terrains without changing authored callers")
assert(Store.CreateRandomTerrain(collection, "重复", 4242, 12).id == record.id
    and #collection.randomTerrains == 1,
    "the same explicit seed must reuse its deterministic terrain instead of duplicating it")

local active = assert(Store.GetActive(collection))
assert(Store.SetTerrain(collection, active.islandId, record.id, 13))
assert(Store.ListRandomTerrains(collection)[1].inUseCount == 1,
    "random terrain management must report which saved islands use a seed")
local managedCard = Catalog.List(Store.ListRandomTerrains(collection))[#Catalog.List() + 1]
assert(managedCard.inUseCount == 1 and Catalog.Get(managedCard).inUseCount == 1,
    "catalog summaries must preserve usage state through the UI preview expansion")
local normalized = Store.Normalize(collection, nil, 14)
assert(Store.GetRandomTerrain(normalized, record.id).name == "云上故乡"
    and Store.GetActive(normalized).terrainId == record.id,
    "random terrain metadata and island references must survive normalization")
assert(Store.RenameRandomTerrain(normalized, record.id, "星环家园", 15).name == "星环家园",
    "managed random terrains can be renamed")

local unsafeRegeneration, unsafeReason = Store.RegenerateRandomTerrain(normalized, record.id, 5151, 16)
assert(not unsafeRegeneration and tostring(unsafeReason):find("使用"),
    "a topology cannot regenerate underneath islands that still contain placed models")
assert(Store.SetTerrain(normalized, Store.GetActive(normalized).islandId, Catalog.DEFAULT_ID, 16.1))
local regenerated = assert(Store.RegenerateRandomTerrain(normalized, record.id, 5151, 16.2))
assert(regenerated.id ~= record.id and regenerated.seed == 5151
    and Store.GetActive(normalized).terrainId == Catalog.DEFAULT_ID,
    "an unused managed terrain can safely replace its seed without touching island projects")
assert(Store.SetTerrain(normalized, Store.GetActive(normalized).islandId, regenerated.id, 16.3))
local deleted, deleteReason = Store.DeleteRandomTerrain(normalized, regenerated.id, 17)
assert(not deleted and tostring(deleteReason):find("使用"),
    "a used random terrain cannot silently leave a broken save reference")
assert(Store.DeleteRandomTerrain(normalized, regenerated.id, 18, { force = true })
    and Store.GetActive(normalized).terrainId == Catalog.DEFAULT_ID
    and #Store.ListRandomTerrains(normalized) == 0,
    "forced deletion safely returns dependent islands to the default terrain")

local orphanId = Generator.IdForSeed(9191)
local recovered = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "seeded",
    items = { { islandId = "seeded", name = "旧随机空岛", terrainId = orphanId, instances = {} } },
}, nil, 19)
assert(Store.GetActive(recovered).terrainId == orphanId
    and Store.GetRandomTerrain(recovered, orphanId),
    "encoded IDs from early saves must self-heal their missing management metadata")

local canonical = Store.Normalize({
    schema = Store.SCHEMA,
    activeId = "canonical",
    randomTerrains = {
        { id = "random-terrain-v1-0001", name = "前导零" },
        { id = "random-terrain-v1-1", name = "规范 ID" },
    },
    items = { {
        islandId = "canonical", name = "规范化测试",
        terrainId = "random-terrain-v1-0001", instances = {},
    } },
}, nil, 19.2)
assert(#canonical.randomTerrains == 1
    and canonical.randomTerrains[1].id == Generator.IdForSeed(1)
    and Store.GetActive(canonical).terrainId == Generator.IdForSeed(1),
    "non-canonical encoded IDs must migrate and deduplicate by their seed")

local longName = string.rep("云", 40)
local longDescription = string.rep("地", 100)
local textSafe = Store.Normalize({
    schema = Store.SCHEMA,
    randomTerrains = { { seed = 7272, name = longName, description = longDescription } },
    items = { { islandId = "text", name = longName, instances = {} } },
}, nil, 19.4)
assert(utf8.len(textSafe.items[1].name) == 28
    and utf8.len(textSafe.randomTerrains[1].name) == 28
    and utf8.len(textSafe.randomTerrains[1].description) == 80,
    "persisted Chinese labels must be truncated by codepoint without creating UI mojibake")

local cappedRecords = {}
for index = 1, 24 do cappedRecords[index] = { seed = 10000 + index } end
local full = Store.Normalize({
    schema = Store.SCHEMA,
    randomTerrains = cappedRecords,
    items = { { islandId = "full", name = "满目录", instances = {} } },
}, nil, 19.6)
assert(Store.CreateRandomTerrain(full, nil, 10001, 19.7).id == Generator.IdForSeed(10001)
    and #full.randomTerrains == 24,
    "a full manager must still resolve an already-saved explicit seed")
local referencedOverflowId = Generator.IdForSeed(999999)
cappedRecords[25] = { seed = 999999 }
local referencedOverflow = Store.Normalize({
    schema = Store.SCHEMA,
    randomTerrains = cappedRecords,
    items = { {
        islandId = "overflow", name = "引用恢复",
        terrainId = referencedOverflowId, instances = {},
    } },
}, nil, 19.8)
assert(Store.GetRandomTerrain(referencedOverflow, referencedOverflowId)
    and Store.GetActive(referencedOverflow).terrainId == referencedOverflowId,
    "a referenced encoded terrain must remain manageable even beyond the creation cap")

local legacy = Store.Normalize({
    schema = "island-project/v2", name = "旧存档", instances = {},
}, nil, 20)
assert(Store.GetActive(legacy).terrainId == Catalog.DEFAULT_ID
    and #Store.ListRandomTerrains(legacy) == 0,
    "old saves without random terrain data remain fully compatible")

print("random-terrain-spec: ok (deterministic landforms plus managed seed persistence)")
