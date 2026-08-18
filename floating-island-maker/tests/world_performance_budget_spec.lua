package.path = "scripts/?.lua;" .. package.path

local WorldPerformanceBudget = require("WorldPerformanceBudget")

assert(WorldPerformanceBudget.InstanceGroupLimit(true) == 48,
    "mobile instance shards must stay below the conservative driver ceiling")
assert(WorldPerformanceBudget.InstanceGroupLimit(false) == 256,
    "desktop should retain the more aggressive draw-call reduction")
assert(WorldPerformanceBudget.ShadowMapSize(true) == 512
    and WorldPerformanceBudget.ShadowMapSize(false) == 2048,
    "instance safety must not alter the established shadow-map budget")

assert(not WorldPerformanceBudget.DynamicShadowsEnabled(true, false, 118, 118, nil),
    "a phone archipelago overview should avoid unresolved shimmering shadows")
assert(WorldPerformanceBudget.DynamicShadowsEnabled(true, false, 72, 118, nil)
    and WorldPerformanceBudget.DynamicShadowsEnabled(true, true, 180, 180, false),
    "close island focus and first-person play should retain dynamic shadows")
assert(WorldPerformanceBudget.DynamicShadowsEnabled(false, false, 300, 118, false),
    "desktop rendering should retain its full shadow quality")
assert(WorldPerformanceBudget.DynamicShadowsEnabled(true, false, 85, 118, true)
    and not WorldPerformanceBudget.DynamicShadowsEnabled(true, false, 78, 118, false),
    "shadow distance hysteresis should prevent rapid toggles near its boundary")

print("world_performance_budget_spec: ok")
