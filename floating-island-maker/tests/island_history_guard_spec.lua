package.path = "scripts/?.lua;" .. package.path

local Guard = require("IslandHistoryGuard")

local oldState, targetState = { { id = 1 } }, { { id = 1 }, { id = 2 } }
local history, future = { oldState }, {}
local checkpoint = Guard.Capture("undo", history, future)
assert(Guard.IsCurrent(checkpoint, history, future),
    "an untouched history stack must retain its transaction token")

history[#history + 1] = targetState
assert(not Guard.IsCurrent(checkpoint, history, future),
    "a changed history depth must invalidate an in-flight completion")
table.remove(history)
history[#history] = { { id = 99 } }
assert(not Guard.IsCurrent(checkpoint, history, future),
    "replacing the stack top at the same depth must invalidate completion")

history[#history] = oldState
checkpoint.externalMutationDetected = true
assert(not Guard.IsCurrent(checkpoint, history, future),
    "an external checkpoint attempt must force rollback")

local transaction = { currentSources = oldState }
assert(Guard.PersistenceSources(transaction) == oldState,
    "autosave must observe the operation-before snapshot while target loading is pending")
transaction.recoveryFailed = true
assert(Guard.PersistenceSources(transaction) == oldState,
    "a failed rollback must keep persistence isolated from the partial scene")
transaction.completed = true
assert(Guard.PersistenceSources(transaction) == nil,
    "a completed transaction must release persistence back to the live scene")

print("island-history-guard-spec: ok")
