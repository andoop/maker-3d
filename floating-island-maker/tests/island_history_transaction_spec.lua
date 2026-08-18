local file = assert(io.open("scripts/IslandWorld.lua", "r"))
local source = file:read("*a")
file:close()

assert(source:find("IslandHistoryGuard.PersistenceSources", 1, true)
        and source:find("world and world.activeHistoryTransaction", 1, true)
        and source:find("generated.currentSources", 1, true),
    "autosave snapshots must stay on the operation-before state until transaction success")

local place = assert(source:match(
    "function IslandWorld:PlaceCurrent.-\nend\n\nfunction IslandWorld:Tap"))
assert(place:find("local historySnapshot = SnapshotWorldInstances(self)", 1, true)
        and place:find("self:RecordHistorySnapshot(historySnapshot)", 1, true)
        and not place:find("self:PushHistory()", 1, true)
        and not place:find("table.remove(self.history)", 1, true),
    "failed placement must leave both undo and redo stacks byte-for-byte unchanged")

local duplicate = assert(source:match(
    "function IslandWorld:DuplicateSelected.-\nend\n\nfunction IslandWorld:DeleteSelected"))
assert(duplicate:find("local historySnapshot = SnapshotWorldInstances(self)", 1, true)
        and duplicate:find("self:RecordHistorySnapshot(historySnapshot)", 1, true)
        and not duplicate:find("self:PushHistory()", 1, true)
        and not duplicate:find("table.remove(self.history)", 1, true),
    "failed duplication must not clear redo or evict the oldest undo entry")

local startPhase = assert(source:match(
    "function IslandWorld:StartHistoryRestorePhase.-\nend\n\nfunction IslandWorld:CompleteHistoryTransaction"))
assert(startPhase:find("historyTransaction = transaction", 1, true)
        and startPhase:find("historyPhase = phase", 1, true),
    "large history restores must carry an explicit transaction and phase through the frame queue")
assert(startPhase:find("if not self:CreateInstance(source, prepared[index]) then", 1, true),
    "synchronous full restores must observe every native instance creation failure")

local complete = assert(source:match(
    "function IslandWorld:CompleteHistoryTransaction.-\nend\n\nfunction IslandWorld:CompleteHistoryRollback"))
assert(complete:find("table.remove(self.history)", 1, true)
        and complete:find("table.remove(self.future)", 1, true)
        and complete:find("self:Commit(transaction.message)", 1, true),
    "history stacks and persistence must move together only in the completion handler")
assert(complete:find("self.activeHistoryTransaction ~= transaction", 1, true)
        and complete:find("IslandHistoryGuard.IsCurrent", 1, true)
        and complete:find("self:InstanceSourcesAvailable(transaction.targetSources)", 1, true),
    "completion must be idempotent and reject a replaced history stack token")

local advance = assert(source:match(
    "function IslandWorld:AdvancePendingProjectLoad.-\nend\n\nfunction IslandWorld:LoadDefault"))
assert(advance:find("if not instance and pending.historyTransaction then", 1, true)
        and advance:find("self:BeginHistoryRollback(transaction, \"create\")", 1, true),
    "an asynchronous target creation failure must immediately enter rollback")
assert(advance:find("self:CompleteHistoryTransaction(pending.historyTransaction)", 1, true)
        and advance:find("self:CompleteHistoryRollback(pending.historyTransaction)", 1, true),
    "queued target and rollback phases must have separate terminal outcomes")

local rollbackFailure = assert(source:match(
    "function IslandWorld:FailHistoryRollback.-\nend\n\nfunction IslandWorld:BeginHistoryRollback"))
assert(rollbackFailure:find("transaction.recoveryFailed = true", 1, true)
        and not rollbackFailure:find("transaction.completed = true", 1, true),
    "a failed rollback must retain the transaction lock and original snapshot")
-- The broad source assertion is intentional: Update is too large to duplicate
-- in this structural harness, while the guard itself is tested dynamically.
assert(source:find("self:BeginHistoryRollback(historyTransaction, \"automatic-retry\")", 1, true),
    "recovery failure must automatically retry instead of reopening a partial scene")

local incremental = assert(source:match(
    "function IslandWorld:RestoreHistoryIncrementally.-\nend\n\nfunction IslandWorld:ApplyHistorySelection"))
assert(incremental:find("if not plan.valid then return nil, \"invalid\" end", 1, true),
    "duplicate or missing IDs must be rejected before the scene can be cleared")
assert(incremental:find("self:RefreshBatchedInstanceCell(instance, previous)", 1, true),
    "incremental history updates must recover a failed batched-cell migration")
local batchRecovery = assert(source:match(
    "function IslandWorld:RefreshBatchedInstanceCell.-\nend\n\nfunction IslandWorld:RefreshInstanceCollision"))
assert(batchRecovery:find("instance.renderDetailVisible = false", 1, true)
        and batchRecovery:find("instance.renderBatchCount = 0", 1, true)
        and batchRecovery:find("self.batchedRecoveryQueue[instance.id]", 1, true)
        and batchRecovery:find("self:MarkRenderDetailDirty()", 1, true),
    "a failed standalone fallback must publish correct counts and schedule a visible retry")
assert(source:find("function IslandWorld:ProcessBatchedInstanceRecoveries", 1, true)
        and source:find("self:ProcessBatchedInstanceRecoveries(clockDelta)", 1, true),
    "desktop recovery must retry independently of the mobile detail policy")

local generated = assert(source:match(
    "function IslandWorld:ApplyGeneratedPlan.-\nend\n\nfunction IslandWorld:RollbackGeneratedPlan"))
assert(generated:find("generatedTransaction = transaction", 1, true)
        and generated:find("self:RollbackGeneratedPlan(transaction", 1, true)
        and generated:find("self:RecordHistorySnapshot(transaction.currentSources)", 1, true)
        and not generated:find("self:PushHistory()", 1, true),
    "one-click building must publish history only after every addition succeeds")
assert(advance:find("if not instance and pending.generatedTransaction then", 1, true)
        and advance:find("self:RollbackGeneratedPlan(transaction", 1, true)
        and advance:find("self:RecordHistorySnapshot(transaction.currentSources)", 1, true),
    "queued one-click building must rollback partial additions and commit once at completion")

local mainFile = assert(io.open("scripts/main.lua", "r"))
local mainSource = mainFile:read("*a")
mainFile:close()
assert(mainSource:find("空岛仍在布置中，请稍候再绑定云门", 1, true)
        and mainSource:find("空岛仍在布置中，完成后会自动保存", 1, true)
        and mainSource:find("空岛仍在布置中，请稍候再删除模型", 1, true),
    "portal binding, model deletion and manual save must respect the global history lock")

print("island-history-transaction-spec: ok")
