package.path = "scripts/?.lua;" .. package.path

local RewardGate = require("RewardGate")

local adCalls, completion
local order, settled = {}, {}
local stateChanges = {}
local gate = RewardGate.new({
    showAd = function(done, request)
        adCalls = adCalls + 1
        assert(request.key == "terrain:spiral", "the ad provider receives public request metadata")
        completion = done
        return true
    end,
    onChanged = function(snapshot)
        stateChanges[#stateChanges + 1] = snapshot.phase
    end,
})

adCalls = 0
assert(gate:Open({
    key = "terrain:spiral",
    title = "解锁螺旋空岛",
    context = { terrainId = "spiral" },
    persistUnlock = function(key, context)
        assert(key == "terrain:spiral" and context.terrainId == "spiral")
        order[#order + 1] = "persist"
        return true
    end,
    onGranted = function() order[#order + 1] = "granted" end,
    onSettled = function(success, message)
        order[#order + 1] = "settled"
        settled[#settled + 1] = { success = success, message = message }
    end,
}))
local duplicateOpen, duplicateReason = gate:Open({ key = "terrain:other" })
assert(not duplicateOpen and duplicateReason:find("已有", 1, true),
    "only one reward confirmation can be active")
assert(gate:Confirm() and adCalls == 0 and gate:GetSnapshot().phase == "waiting",
    "explicit confirmation queues rather than immediately opening the SDK surface")
gate:Update(0.25)
assert(adCalls == 0 and gate:GetSnapshot().remainingFrames == 1,
    "the first update preserves one complete loading frame")
gate:Update(0.25)
assert(adCalls == 1 and gate:GetSnapshot().phase == "playing",
    "the ad provider starts after the required two-frame delay")
completion({ success = true })
assert(table.concat(order, ",") == "persist,granted,settled"
    and settled[1].success == true and settled[1].message == nil,
    "a successful ad persists the grant before protected and settlement callbacks")
assert(not gate:GetSnapshot().open and gate:GetSnapshot().lastOutcome == "granted",
    "successful grants release the active-request lock")
assert(stateChanges[1] == "ready" and stateChanges[2] == "waiting"
    and stateChanges[#stateChanges - 1] == "playing" and stateChanges[#stateChanges] == "closed",
    "state observers receive confirmation, playback and terminal snapshots without polling")
completion({ success = true })
assert(#order == 3, "duplicate SDK callbacks are ignored after successful settlement")

local lateCompletion, grantedAfterReset = nil, 0
local resetGate = RewardGate.new({ showAd = function(done) lateCompletion = done end })
assert(resetGate:Open({ onGranted = function() grantedAfterReset = grantedAfterReset + 1 end }))
assert(resetGate:Confirm())
resetGate:Update(0)
resetGate:Update(0)
resetGate:Reset()
lateCompletion({ success = true })
assert(grantedAfterReset == 0 and not resetGate:GetSnapshot().open,
    "reset invalidates callbacks that arrive after their request is gone")

local cancelledCompletion, cancelledGrant = nil, 0
local cancelGate = RewardGate.new({ showAd = function(done) cancelledCompletion = done end })
assert(cancelGate:Open({ onGranted = function() cancelledGrant = cancelledGrant + 1 end }))
assert(cancelGate:Confirm())
cancelGate:Update(0)
cancelGate:Update(0)
assert(cancelGate:Cancel() and cancelGate:GetSnapshot().lastOutcome == "cancelled")
cancelledCompletion({ success = true })
assert(cancelledGrant == 0, "cancel invalidates an in-flight provider callback")

local immediateSettled = {}
local immediateGate = RewardGate.new({ showAd = function() return false end })
assert(immediateGate:Open({ onSettled = function(...)
    immediateSettled = { ... }
end }))
assert(immediateGate:Confirm())
immediateGate:Update(0)
immediateGate:Update(0)
assert(immediateSettled[1] == false
    and tostring(immediateSettled[2]):find("没有打开", 1, true)
    and immediateGate:GetSnapshot().phase == "ready"
    and immediateGate:GetSnapshot().canConfirm,
    "an immediate false return is reported and leaves the same confirmation retryable")

local exceptionSettled = {}
local exceptionGate = RewardGate.new({ showAd = function() error("provider exploded") end })
assert(exceptionGate:Open({ onSettled = function(...)
    exceptionSettled = { ... }
end }))
assert(exceptionGate:Confirm())
exceptionGate:Update(0)
exceptionGate:Update(0)
assert(exceptionSettled[1] == false
    and tostring(exceptionSettled[2]):find("接口异常", 1, true)
    and exceptionGate:GetSnapshot().lastFailureKind == "exception",
    "provider exceptions settle safely without wedging the gate")

local timeoutCompletion, timeoutCount = nil, 0
local timeoutGate = RewardGate.new({
    timeoutSeconds = 150,
    showAd = function(done) timeoutCompletion = done end,
})
assert(timeoutGate:Open({ onSettled = function(success, message)
    assert(success == false and message:find("超时", 1, true))
    timeoutCount = timeoutCount + 1
end }))
assert(timeoutGate:Confirm())
timeoutGate:Update(0)
timeoutGate:Update(0)
timeoutGate:Update(149.9)
assert(timeoutCount == 0 and timeoutGate:GetSnapshot().phase == "playing",
    "the provider stays active until the full 150-second timeout")
timeoutGate:Update(0.1)
assert(timeoutCount == 1 and timeoutGate:GetSnapshot().phase == "ready",
    "the 150-second timeout settles once and permits a deliberate retry")
timeoutCompletion({ success = true })
assert(timeoutCount == 1, "a callback arriving after timeout cannot grant or settle again")

local persisted, protected, persistSettled = 0, 0, {}
local persistCompletion
local persistGate = RewardGate.new({ showAd = function(done) persistCompletion = done end })
assert(persistGate:Open({
    persistUnlock = function()
        persisted = persisted + 1
        return false, "disk full"
    end,
    onGranted = function() protected = protected + 1 end,
    onSettled = function(...) persistSettled = { ... } end,
}))
assert(persistGate:Confirm())
persistGate:Update(0)
persistGate:Update(0)
persistCompletion({ success = true })
assert(persisted == 1 and protected == 0 and persistSettled[1] == false
    and persistGate:GetSnapshot().lastFailureKind == "persist",
    "a failed durable unlock blocks the protected action and reports failure")

local noProviderSettled = {}
local noProviderGate = RewardGate.new()
assert(noProviderGate:Open({ onSettled = function(...) noProviderSettled = { ... } end }))
local providerStarted, providerMessage = noProviderGate:Confirm()
assert(not providerStarted and providerMessage:find("接口异常", 1, true)
    and noProviderSettled[1] == false,
    "a missing injected provider is handled as a retryable exception")

print("reward-gate-spec: ok")
