package.path = "scripts/?.lua;" .. package.path

local Picking = require("IslandPicking")

local function Near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.001,
        (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local asset = { bounds = { min = { -2, 0, -0.2 }, max = { 2, 4, 0.2 }, size = { 4, 4, 0.4 } } }
local instance = { x = 3, z = 5, rotationY = math.pi * 0.5, scale = 1 }
local hit = Picking.RayInstanceBounds({
    origin = { x = 3, y = 2, z = 10 },
    direction = { x = 0, y = 0, z = -1 },
}, instance, asset, 0, 0, 100)
assert(hit and hit >= 2.7 and hit <= 3.1, "rotated asymmetric instance bounds must be hittable")

local sparseMiss = Picking.RayInstanceBounds({
    origin = { x = 0.55, y = 1.5, z = 4 },
    direction = { x = 0, y = 0, z = -1 },
}, { x = 0, z = 0, rotationY = 0, scale = 1 },
    { bounds = { min = { -0.5, 0, -0.08 }, max = { 0.5, 3, 0.08 } } }, 0, 0, 100)
assert(sparseMiss == nil, "ray outside an exact thin bounds should miss without touch padding")
local sparseHit = Picking.RayInstanceBounds({
    origin = { x = 0.55, y = 1.5, z = 4 },
    direction = { x = 0, y = 0, z = -1 },
}, { x = 0, z = 0, rotationY = 0, scale = 1 },
    { bounds = { min = { -0.5, 0, -0.08 }, max = { 0.5, 3, 0.08 } } }, 0, 0.10, 100)
assert(sparseHit, "bounded touch padding should recover a thin lamp or grass hit")

local desktopPadding = Picking.WorldPadding(20, 800, false, 40)
local mobilePadding = Picking.WorldPadding(20, 800, true, 40)
assert(mobilePadding > desktopPadding, "mobile fallback must match a larger finger target")
assert(Picking.WorldPadding(20, 2400, true, 40, 3)
        > Picking.WorldPadding(20, 2400, true, 40, 1) * 2.9,
    "high-DPR phones must preserve a logical finger-sized target")
assert(Picking.WorldPadding(5000, 200, true, 40) <= 0.70,
    "distant model fallback must never become an unbounded screen target")

local exact = { instance = { id = 1 }, distance = 6 }
local behind = { instance = { id = 2 }, distance = 7 }
assert(Picking.Choose(exact, behind) == exact, "a rear proxy cannot steal a real front triangle")
local front = { instance = { id = 3 }, distance = 4 }
assert(Picking.Choose(exact, front) == front, "a thin foreground proxy should beat rear geometry")

assert(Picking.EnvironmentIslandIndex("IslandEnvironment_GrassCells1") == 1,
    "an island grass surface must resolve to its authored island")
assert(Picking.EnvironmentIslandIndex("IslandEnvironment_SoilCells10_2") == 10,
    "a chunked island cliff wall must resolve to its authored island")
assert(Picking.EnvironmentIslandIndex("IslandEnvironment_RockCells7_12") == 7,
    "a chunked island underside must resolve to its authored island")
assert(Picking.EnvironmentIslandIndex("IslandEnvironment_BridgeRock") == nil,
    "bridges must not impersonate an island foundation")
assert(Picking.EnvironmentIslandIndex("IslandEnvironment_DistantIslandRock") == nil,
    "distant decorative islands must not steal main-island taps")
assert(Picking.EnvironmentIslandIndex("IslandEnvironment_RockCells2_preview") == nil,
    "only real numbered terrain chunks may resolve to an island")
assert(Picking.IsIslandInFront(4, 8), "a foreground island body must occlude a rear model")
assert(not Picking.IsIslandInFront(8, 4), "a foreground model must remain selectable")
assert(Picking.IsIslandInFront(4, nil), "an island body must be selectable without a model hit")

assert(Picking.UseBoundsFallback({
    bounds = { min = { -0.2, 0, -0.2 }, max = { 0.2, 4, 0.2 } },
    blocks = { { size = { 0.12, 4, 0.12 } } },
}), "a slender streetlamp needs a bounds fallback")
assert(Picking.UseBoundsFallback({
    bounds = { min = { -1.2, 0, -1.2 }, max = { 1.2, 0.7, 1.2 } },
    blocks = { { size = { 0.1, 0.6, 0.1 } }, { size = { 0.1, 0.4, 0.1 } } },
}), "a sparse grass cluster needs a bounds fallback")
assert(not Picking.UseBoundsFallback({
    bounds = { min = { -4, 0, -3 }, max = { 4, 5, 3 } },
    blocks = {
        { size = { 8, 0.2, 6 } }, { size = { 8, 0.2, 6 } },
        { size = { 8, 5, 0.2 } }, { size = { 8, 5, 0.2 } },
    },
}), "a large hollow house must use exact triangles instead of its empty OBB")

local center = Picking.InstanceCenter(instance, asset, 0)
Near(center.x, 3, "rotated center x")
Near(center.z, 5, "rotated center z")

print("island picking spec passed")
