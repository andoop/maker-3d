package.path = "scripts/?.lua;" .. package.path

package.preload["urhox-libs/3D"] = function() return {} end
package.preload["BlockCatalog"] = function() return {} end
package.preload["MakerTransformControls"] = function() return {} end

local BuilderTransformControls = require("BuilderTransformControls")

local received = {}
local world = {
    onChanged = function(state, message)
        assert(message == nil, "interactive transform deltas must not emit status messages")
        received[#received + 1] = state
    end,
}
local block = {
    id = 7, x = 1, y = 2, z = 3,
    sx = 1, sy = 1, sz = 1,
    rx = 0, ry = 0, rz = 0,
}

assert(BuilderTransformControls._PublishTransformRefresh(world, block) == true,
    "a live transform must publish a lightweight UI delta")
assert(received[1]._builderRefreshKind == "transform" and received[1].selected == block,
    "the delta must identify the transform fast path and retain the live selected block")

block.x = 4.25
assert(BuilderTransformControls._PublishTransformRefresh(world, block) == true)
assert(received[2] == received[1],
    "successive pointer samples must reuse one delta table instead of allocating per event")
assert(received[2].selected.x == 4.25,
    "the reused delta must expose the newest transform values")

assert(BuilderTransformControls._PublishTransformRefresh({}, block) == false,
    "worlds without a change observer must safely skip the UI delta")

print("builder-transform-refresh-spec: ok")
