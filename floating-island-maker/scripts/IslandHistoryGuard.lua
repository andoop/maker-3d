local IslandHistoryGuard = {}

function IslandHistoryGuard.Capture(direction, history, future)
    history, future = history or {}, future or {}
    return {
        direction = direction,
        historyDepth = #history,
        futureDepth = #future,
        historyTop = history[#history],
        futureTop = future[#future],
    }
end

function IslandHistoryGuard.IsCurrent(checkpoint, history, future)
    if type(checkpoint) ~= "table" then return false end
    history, future = history or {}, future or {}
    if checkpoint.externalMutationDetected then return false end
    return #history == checkpoint.historyDepth
        and #future == checkpoint.futureDepth
        and history[#history] == checkpoint.historyTop
        and future[#future] == checkpoint.futureTop
end

-- Rendering may progressively contain the target or a partial rollback, but
-- persistence must keep seeing the operation-before snapshot until success.
function IslandHistoryGuard.PersistenceSources(transaction)
    if type(transaction) ~= "table" or transaction.completed == true then return nil end
    if type(transaction.currentSources) ~= "table" then return nil end
    return transaction.currentSources
end

return IslandHistoryGuard
