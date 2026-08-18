package.path = "scripts/?.lua;" .. package.path

local HistoryPlan = require("IslandHistoryPlan")

local function Model(id, x, assetId)
    return {
        id = id,
        assetId = assetId or "builtin:model",
        versionId = "2.0.0",
        x = x or 0,
        y = 0,
        z = id,
        rotationY = 0,
        scale = 1,
    }
end

local current, moved = {}, {}
for id = 1, 120 do
    current[id] = Model(id, id)
    moved[id] = Model(id, id)
end
moved[73].x = 99
local movement = HistoryPlan.Build(current, moved)
assert(movement.valid and movement.changeCount == 1
        and #movement.updates == 1 and movement.updates[1].id == 73
        and #movement.removals == 0 and #movement.additions == 0,
    "moving one model in a dense island must retain every native node except its transform")

local placed = { Model(1), Model(2), Model(3) }
local beforePlacement = { Model(1), Model(2) }
local undoPlacement = HistoryPlan.Build(placed, beforePlacement)
assert(undoPlacement.changeCount == 1 and #undoPlacement.removals == 1
        and undoPlacement.removals[1] == 3 and #undoPlacement.additions == 0,
    "undoing placement must remove only the newly placed model")

local undoDelete = HistoryPlan.Build(beforePlacement, placed)
assert(undoDelete.changeCount == 1 and #undoDelete.additions == 1
        and undoDelete.additions[1].id == 3 and #undoDelete.removals == 0,
    "undoing deletion must recreate only the deleted model")

local replaced = { Model(1), Model(2, 0, "builtin:replacement") }
local identity = HistoryPlan.Build(beforePlacement, replaced)
assert(identity.changeCount == 1 and #identity.removals == 1
        and #identity.additions == 1 and #identity.updates == 0
        and #identity.replacements == 1,
    "an asset identity change must replace rather than mutate the live renderable")

local portalA = Model(1)
portalA.portal = { targetIslandId = "a", nested = { 1, 2 } }
local portalB = Model(1)
portalB.portal = { targetIslandId = "b", nested = { 1, 2 } }
local portal = HistoryPlan.Build({ portalA }, { portalB })
assert(portal.changeCount == 1 and #portal.updates == 1,
    "portal binding changes must be restored without rebuilding the model")

local reordered = HistoryPlan.Build({ Model(1), Model(2) }, { Model(2), Model(1) })
assert(reordered.valid and reordered.changeCount == 0
        and reordered.target[1].id == 2 and reordered.target[2].id == 1,
    "the target order must remain available even when no render mutation is needed")

local invalid = HistoryPlan.Build({ Model(1), Model(1) }, { Model(1) })
assert(not invalid.valid, "ambiguous IDs must be rejected before any destructive restore")

print("island history plan tests passed")
