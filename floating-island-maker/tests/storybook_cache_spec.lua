package.path = "scripts/?.lua;" .. package.path

local IslandLayout = require("IslandLayout")
local StorybookIslandData = require("StorybookIslandData")

StorybookIslandData.ClearCache()
local layouts = IslandLayout.List()
assert(#layouts >= 5, "cache pressure test needs at least five terrain presets")
for index = 1, 5 do
    local layout = IslandLayout.Resolve(layouts[index].id)
    local data = StorybookIslandData.Build(layout)
    assert(data and data.terrainId == layout.id, "terrain build must remain correct under cache pressure")
end
local stats = StorybookIslandData.CacheStats()
assert(stats.entries <= stats.limit and stats.limit == 4,
    "large procedural terrain descriptions must use a bounded LRU cache")

-- The most recent entry must still be reused exactly; worlds may safely retain
-- an older evicted table because eviction only removes the cache reference.
local latest = IslandLayout.Resolve(layouts[5].id)
assert(StorybookIslandData.Build(latest) == StorybookIslandData.Build(latest),
    "a retained terrain cache entry must preserve identity")

print("storybook-cache-spec: ok")
