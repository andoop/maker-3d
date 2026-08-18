package.path = "scripts/?.lua;" .. package.path

local IncrementalBuildQueue = require("IncrementalBuildQueue")
local queue = IncrementalBuildQueue.new()
local order = {}

queue:Add(function() order[#order + 1] = "terrain-a" end, "terrain-a")
queue:Add(function() error("bad cloud") end, "cloud-b")
queue:Add(function() order[#order + 1] = "terrain-c" end, "terrain-c")

local advanced, complete = queue:Advance(1)
assert(advanced == 1 and not complete and queue:PendingCount() == 2,
    "one mobile frame must execute only its bounded terrain job")
advanced, complete = queue:Advance(1)
assert(advanced == 1 and not complete and #queue.errors == 1
        and queue.errors[1].label == "cloud-b",
    "a failed geometry chunk must be recorded without blocking later chunks")
advanced, complete = queue:Advance(1)
assert(advanced == 1 and complete and table.concat(order, ",") == "terrain-a,terrain-c",
    "the queue must preserve order and finish after the final chunk")
local progress = queue:Progress()
assert(progress.completed == 3 and progress.total == 3 and progress.pending == 0,
    "performance diagnostics need exact incremental build progress")

queue = IncrementalBuildQueue.new()
queue:Add(function() error("cancelled job ran") end)
queue:Cancel()
assert(not queue:IsPending() and queue:Advance(1) == 0,
    "disposing a world must release all queued geometry closures")

print("incremental_build_queue_spec: ok")
