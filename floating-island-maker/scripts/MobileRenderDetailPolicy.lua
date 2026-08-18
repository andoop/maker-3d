local MobileRenderDetailPolicy = {}
MobileRenderDetailPolicy.__index = MobileRenderDetailPolicy

MobileRenderDetailPolicy.DEFAULTS = {
    -- This is a render-detail budget, never an authoring or save-data limit.
    maxVisibleBlocks = 720,
    minimumProjectedPixels = 3.0,
    retainedMinimumProjectedPixels = 1.8,
    retainedScoreBoost = 1.12,
    proximityWeight = 0.30,
    -- Ground-cover candidates may reserve a bounded part of the unchanged
    -- budget for one representative per screen tile. This avoids spending the
    -- entire budget on a tiny ring around the camera.
    coverageBudgetFraction = 0.25,
    -- Native StaticModelGroup membership changes are intentionally amortised.
    -- Selection remains immediate even when it exceeds this per-evaluation cap.
    maxVisibilityChangesPerEvaluation = 32,
}

local function FiniteNumber(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function PositiveNumber(value, fallback)
    return math.max(0, FiniteNumber(value, fallback))
end

local function CandidateId(candidate, index)
    if candidate.id ~= nil then return candidate.id end
    if candidate.instanceId ~= nil then return candidate.instanceId end
    return index
end

local function CandidatePixels(candidate)
    return PositiveNumber(
        candidate.projectedPixels or candidate.screenPixels or candidate.projectedSize,
        0
    )
end

local function CandidateDistance(candidate)
    return PositiveNumber(candidate.distance or candidate.cameraDistance, 1000000000)
end

local function CandidateBlockCount(candidate)
    local raw = candidate.visibleBlockCount or candidate.visibleBlocks
        or candidate.blockCount or candidate.cost or 1
    return math.max(1, math.floor(PositiveNumber(raw, 1) + 0.5))
end

local function IsMobile(context)
    if context.mobile ~= nil then return context.mobile == true end
    return context.isMobile == true
end

local function IsSelected(candidate, id, context)
    return candidate.selected == true
        or (context.selectedId ~= nil and id == context.selectedId)
end

local function CopyDefaults(options)
    local defaults = MobileRenderDetailPolicy.DEFAULTS
    options = options or {}
    local minimumPixels = PositiveNumber(
        options.minimumProjectedPixels,
        defaults.minimumProjectedPixels
    )
    local retainedMinimum = PositiveNumber(
        options.retainedMinimumProjectedPixels,
        defaults.retainedMinimumProjectedPixels
    )
    return {
        maxVisibleBlocks = math.floor(PositiveNumber(
            options.maxVisibleBlocks,
            defaults.maxVisibleBlocks
        )),
        minimumProjectedPixels = minimumPixels,
        retainedMinimumProjectedPixels = math.min(minimumPixels, retainedMinimum),
        retainedScoreBoost = math.max(1, PositiveNumber(
            options.retainedScoreBoost,
            defaults.retainedScoreBoost
        )),
        proximityWeight = PositiveNumber(options.proximityWeight, defaults.proximityWeight),
        coverageBudgetFraction = math.min(0.5, PositiveNumber(
            options.coverageBudgetFraction,
            defaults.coverageBudgetFraction
        )),
        maxVisibilityChangesPerEvaluation = math.max(1, math.floor(PositiveNumber(
            options.maxVisibilityChangesPerEvaluation,
            defaults.maxVisibilityChangesPerEvaluation
        ))),
    }
end

---Create a stateful mobile vegetation visibility policy.
---The policy only remembers visibility decisions for hysteresis; it never owns
---or mutates model instances.
---@param options table|nil
---@return table
function MobileRenderDetailPolicy.new(options)
    return setmetatable({
        options = CopyDefaults(options),
        previousVisible = {},
        dirty = true,
        lastEntries = nil,
        lastMobile = nil,
        lastBudget = nil,
        lastRevision = nil,
        lastSelectedId = nil,
        desiredVisible = nil,
        desiredOrder = nil,
        pendingChanges = 0,
        lastVisible = nil,
        lastStats = nil,
    }, MobileRenderDetailPolicy)
end

---Forget the preceding frame's visibility without touching project data.
function MobileRenderDetailPolicy:Reset()
    self.previousVisible = {}
    self.dirty = true
    self.lastEntries = nil
    self.lastMobile = nil
    self.lastBudget = nil
    self.lastRevision = nil
    self.lastSelectedId = nil
    self.desiredVisible = nil
    self.desiredOrder = nil
    self.pendingChanges = 0
    self.lastVisible = nil
    self.lastStats = nil
end

---Force the next Evaluate call to rebuild its ranking even when candidates are
---numerically unchanged. Callers can use this for scene/device-quality events.
function MobileRenderDetailPolicy:MarkDirty()
    self.dirty = true
end

MobileRenderDetailPolicy.Invalidate = MobileRenderDetailPolicy.MarkDirty

local function Score(entry, options, wasVisible)
    local proximity = 1 + options.proximityWeight / (1 + entry.distance)
    local retention = wasVisible and options.retainedScoreBoost or 1
    return entry.pixels * proximity * retention * entry.priority
end

local function NewStats(mobile, count, budget)
    return {
        mobile = mobile,
        candidateCount = count,
        visibleCount = 0,
        hiddenCount = 0,
        visibleBlocks = 0,
        budget = budget,
        overBudgetBlocks = 0,
        changeCount = 0,
        pendingChanges = 0,
        reused = false,
    }
end

local function EntriesEqual(first, second)
    if type(first) ~= "table" or type(second) ~= "table" or #first ~= #second then return false end
    for index, entry in ipairs(first) do
        local other = second[index]
        if not other or entry.id ~= other.id or entry.pixels ~= other.pixels
            or entry.distance ~= other.distance or entry.blocks ~= other.blocks
            or entry.selected ~= other.selected or entry.inView ~= other.inView
            or entry.minimumPixels ~= other.minimumPixels
            or entry.retainedMinimumPixels ~= other.retainedMinimumPixels
            or entry.priority ~= other.priority
            or entry.coverageKey ~= other.coverageKey then return false end
    end
    return true
end

local function CopyStats(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function RankDesired(entries, options, previousVisible, budget)
    local desired, order, ranked = {}, {}, {}
    local usedBlocks = 0

    -- Selected vegetation is a correctness rule, not a quality preference. It
    -- stays visible even when its own detail exceeds the mobile budget.
    for _, entry in ipairs(entries) do
        if entry.selected then
            desired[entry.id] = true
            order[#order + 1] = entry.id
            usedBlocks = usedBlocks + entry.blocks
        else
            local wasVisible = previousVisible[entry.id] == true
            local threshold = wasVisible and entry.retainedMinimumPixels or entry.minimumPixels
            if entry.inView and entry.pixels >= threshold then
                entry.score = Score(entry, options, wasVisible)
                ranked[#ranked + 1] = entry
            end
        end
    end

    table.sort(ranked, function(first, second)
        if first.score ~= second.score then return first.score > second.score end
        if first.pixels ~= second.pixels then return first.pixels > second.pixels end
        if first.distance ~= second.distance then return first.distance < second.distance end
        return first.index < second.index
    end)

    -- First distribute a small, fixed share across visible screen tiles. The
    -- same full-detail block cost is charged, so this changes composition but
    -- never raises the phone heat/render budget.
    local coverageLimit = math.floor(budget * options.coverageBudgetFraction + 0.5)
    local coverageByKey, coverage = {}, {}
    for _, entry in ipairs(ranked) do
        if entry.coverageKey ~= nil then
            local previous = coverageByKey[entry.coverageKey]
            if not previous or entry.score > previous.score then
                coverageByKey[entry.coverageKey] = entry
            end
        end
    end
    for _, entry in pairs(coverageByKey) do coverage[#coverage + 1] = entry end
    table.sort(coverage, function(first, second)
        if first.score ~= second.score then return first.score > second.score end
        return first.index < second.index
    end)
    local coverageBlocks = 0
    for _, entry in ipairs(coverage) do
        if coverageBlocks + entry.blocks <= coverageLimit
            and usedBlocks + entry.blocks <= budget then
            desired[entry.id] = true
            order[#order + 1] = entry.id
            coverageBlocks = coverageBlocks + entry.blocks
            usedBlocks = usedBlocks + entry.blocks
        end
    end

    for _, entry in ipairs(ranked) do
        if not desired[entry.id] and usedBlocks + entry.blocks <= budget then
            desired[entry.id] = true
            order[#order + 1] = entry.id
            usedBlocks = usedBlocks + entry.blocks
        end
    end
    return desired, order
end

local function ApplyTransition(entries, previousVisible, desired, desiredOrder, maximumChanges)
    local visibleById, nextVisible, byId = {}, {}, {}
    local changes = 0
    for _, entry in ipairs(entries) do
        local visible = previousVisible[entry.id] == true
        visibleById[entry.id] = visible
        if visible then nextVisible[entry.id] = true end
        byId[entry.id] = entry
    end

    -- Selection is immediate even when the normal native-operation budget has
    -- already been consumed. This preserves editing correctness.
    for _, entry in ipairs(entries) do
        if entry.selected and not visibleById[entry.id] then
            visibleById[entry.id], nextVisible[entry.id] = true, true
            changes = changes + 1
        end
    end

    -- Hide first so a staged transition cannot make an already dense frame
    -- even denser while waiting for the following evaluation.
    for _, entry in ipairs(entries) do
        if changes >= maximumChanges then break end
        if visibleById[entry.id] and not desired[entry.id] and not entry.selected then
            visibleById[entry.id], nextVisible[entry.id] = false, nil
            changes = changes + 1
        end
    end
    for _, id in ipairs(desiredOrder or {}) do
        if changes >= maximumChanges then break end
        if byId[id] and not visibleById[id] then
            visibleById[id], nextVisible[id] = true, true
            changes = changes + 1
        end
    end

    local pending = 0
    for _, entry in ipairs(entries) do
        if (visibleById[entry.id] == true) ~= (desired[entry.id] == true) then pending = pending + 1 end
    end
    return visibleById, nextVisible, changes, pending
end

---Choose which vegetation models should be rendered this frame.
---Candidates are read-only tables with `id`, `projectedPixels`, `distance`,
---and `blockCount` (aliases are accepted above). The returned map contains an
---explicit boolean for every candidate ID. On desktop every value is true.
---`context.revision` enables an O(1) clean fast path; without it, unchanged
---candidate values are detected automatically before ranking.
---@param candidates table|nil
---@param context table|nil `{ mobile/isMobile, selectedId, maxVisibleBlocks, revision, dirty, maxVisibilityChanges }`
---@return table visibleById
---@return table stats
function MobileRenderDetailPolicy:Evaluate(candidates, context)
    candidates = candidates or {}
    context = context or {}

    local mobile = IsMobile(context)
    local configuredBudget = self.options.maxVisibleBlocks
    local budget = math.floor(PositiveNumber(context.maxVisibleBlocks, configuredBudget))
    local revision = context.revision ~= nil and context.revision or context.detailRevision
    if context.dirty == true then self.dirty = true end

    -- A caller-owned revision avoids even rebuilding the compact comparison
    -- entries. It is opt-in so existing callers remain correct without changes.
    if not self.dirty and self.pendingChanges == 0 and revision ~= nil
        and revision == self.lastRevision and mobile == self.lastMobile
        and budget == self.lastBudget and context.selectedId == self.lastSelectedId
        and self.lastVisible and self.lastStats then
        local stats = CopyStats(self.lastStats)
        stats.reused = true
        return self.lastVisible, stats
    end

    local entries, totalBlocks = {}, 0
    for index, candidate in ipairs(candidates) do
        local id = CandidateId(candidate, index)
        local entry = {
            id = id,
            index = index,
            pixels = CandidatePixels(candidate),
            distance = CandidateDistance(candidate),
            blocks = CandidateBlockCount(candidate),
            selected = IsSelected(candidate, id, context),
            inView = candidate.inView ~= false,
            minimumPixels = PositiveNumber(candidate.minimumProjectedPixels,
                self.options.minimumProjectedPixels),
            retainedMinimumPixels = PositiveNumber(candidate.retainedMinimumProjectedPixels,
                self.options.retainedMinimumProjectedPixels),
            priority = math.max(0.01, PositiveNumber(candidate.priority, 1)),
            coverageKey = candidate.coverageKey,
        }
        entry.retainedMinimumPixels = math.min(entry.minimumPixels, entry.retainedMinimumPixels)
        entries[#entries + 1] = entry
        totalBlocks = totalBlocks + entry.blocks
    end

    local sameInput = not self.dirty and mobile == self.lastMobile and budget == self.lastBudget
        and EntriesEqual(entries, self.lastEntries)
    if sameInput and self.pendingChanges == 0 and self.lastVisible and self.lastStats then
        self.lastRevision = revision
        local stats = CopyStats(self.lastStats)
        stats.reused = true
        return self.lastVisible, stats
    end

    local stats = NewStats(mobile, #entries, budget)
    local visibleById = {}
    if not mobile then
        for _, entry in ipairs(entries) do visibleById[entry.id] = true end
        stats.visibleCount = #entries
        stats.visibleBlocks = totalBlocks
        self.previousVisible = visibleById
        self.desiredVisible, self.desiredOrder, self.pendingChanges = nil, nil, 0
    else
        local desired, desiredOrder
        if sameInput and self.pendingChanges > 0 and self.desiredVisible then
            desired, desiredOrder = self.desiredVisible, self.desiredOrder
        else
            desired, desiredOrder = RankDesired(entries, self.options, self.previousVisible, budget)
        end
        local maximumChanges = math.max(1, math.floor(PositiveNumber(
            context.maxVisibilityChanges,
            self.options.maxVisibilityChangesPerEvaluation
        )))
        local nextVisible, changeCount, pendingChanges
        visibleById, nextVisible, changeCount, pendingChanges = ApplyTransition(
            entries, self.previousVisible, desired, desiredOrder, maximumChanges)
        self.previousVisible = nextVisible
        self.desiredVisible, self.desiredOrder = desired, desiredOrder
        self.pendingChanges = pendingChanges
        stats.changeCount, stats.pendingChanges = changeCount, pendingChanges

        for _, entry in ipairs(entries) do
            if visibleById[entry.id] then
                stats.visibleCount = stats.visibleCount + 1
                stats.visibleBlocks = stats.visibleBlocks + entry.blocks
            else
                stats.hiddenCount = stats.hiddenCount + 1
            end
        end
        stats.overBudgetBlocks = math.max(0, stats.visibleBlocks - budget)
    end

    self.dirty = false
    self.lastEntries = entries
    self.lastMobile, self.lastBudget, self.lastRevision = mobile, budget, revision
    self.lastSelectedId = context.selectedId
    self.lastVisible, self.lastStats = visibleById, stats
    return visibleById, stats
end

return MobileRenderDetailPolicy
