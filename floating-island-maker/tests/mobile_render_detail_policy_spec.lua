package.path = "scripts/?.lua;" .. package.path

local MobileRenderDetailPolicy = require("MobileRenderDetailPolicy")

local function NewPolicy(overrides)
    overrides = overrides or {}
    overrides.maxVisibleBlocks = overrides.maxVisibleBlocks or 10
    overrides.minimumProjectedPixels = overrides.minimumProjectedPixels or 3
    overrides.retainedMinimumProjectedPixels = overrides.retainedMinimumProjectedPixels or 2
    overrides.retainedScoreBoost = overrides.retainedScoreBoost or 1.15
    overrides.proximityWeight = overrides.proximityWeight or 0.30
    return MobileRenderDetailPolicy.new(overrides)
end

local desktopCandidates = {
    { id = "tiny", projectedPixels = 0.1, distance = 500, blockCount = 200 },
    { id = "near", projectedPixels = 30, distance = 2, blockCount = 20 },
}
local desktopPolicy = NewPolicy()
local desktop, desktopStats = desktopPolicy:Evaluate(desktopCandidates, { mobile = false })
assert(desktop.tiny and desktop.near,
    "desktop must render every vegetation candidate regardless of the mobile detail budget")
assert(desktopStats.visibleCount == 2 and desktopStats.hiddenCount == 0,
    "desktop statistics must report the uncropped source list")

local mobilePolicy = NewPolicy()
local mobileCandidates = {
    { id = "large-near", projectedPixels = 20, distance = 3, blockCount = 6 },
    { id = "same-size-far", projectedPixels = 9, distance = 30, blockCount = 4 },
    { id = "same-size-near", projectedPixels = 9, distance = 4, blockCount = 4 },
    { id = "subpixel", projectedPixels = 1, distance = 1, blockCount = 1 },
}
local mobile, mobileStats = mobilePolicy:Evaluate(mobileCandidates, { mobile = true })
assert(mobile["large-near"] and mobile["same-size-near"],
    "mobile detail must spend its block budget on large and near vegetation first")
assert(not mobile["same-size-far"] and not mobile.subpixel,
    "far or visually insignificant vegetation must remain project data but skip this frame")
assert(mobileStats.visibleBlocks == 10 and mobileStats.visibleCount == 2
    and mobileStats.hiddenCount == 2,
    "the selected mobile render set must respect the visible-block budget")

local selectedPolicy = NewPolicy()
local selected, selectedStats = selectedPolicy:Evaluate({
    { id = 41, projectedPixels = 0, distance = 1000, blockCount = 17 },
    { id = 42, projectedPixels = 40, distance = 1, blockCount = 2 },
}, { isMobile = true, selectedId = 41 })
assert(selected[41], "the selected model must remain visible even when tiny, distant, or over budget")
assert(not selected[42] and selectedStats.overBudgetBlocks == 7,
    "selected detail may exceed the quality budget without silently adding more vegetation")

local hysteresisPolicy = NewPolicy()
local first = hysteresisPolicy:Evaluate({
    { id = "a", projectedPixels = 10.0, distance = 5, blockCount = 10 },
    { id = "b", projectedPixels = 9.8, distance = 5, blockCount = 10 },
}, { mobile = true })
assert(first.a and not first.b, "the initially larger candidate should win an equal-cost budget")
local smallCameraChange = hysteresisPolicy:Evaluate({
    { id = "a", projectedPixels = 9.7, distance = 5, blockCount = 10 },
    { id = "b", projectedPixels = 10.0, distance = 5, blockCount = 10 },
}, { mobile = true })
assert(smallCameraChange.a and not smallCameraChange.b,
    "retention hysteresis must prevent a tiny camera change from swapping vegetation")
local decisiveCameraChange = hysteresisPolicy:Evaluate({
    { id = "a", projectedPixels = 5.0, distance = 5, blockCount = 10 },
    { id = "b", projectedPixels = 12.0, distance = 5, blockCount = 10 },
}, { mobile = true })
assert(not decisiveCameraChange.a and decisiveCameraChange.b,
    "a meaningful projected-size change must still replace retained vegetation")

local thresholdPolicy = NewPolicy()
local entered = thresholdPolicy:Evaluate({
    { id = "kept", projectedPixels = 3.1, distance = 8, blockCount = 1 },
}, { mobile = true })
assert(entered.kept, "vegetation above the entry threshold should become visible")
local retained = thresholdPolicy:Evaluate({
    { id = "kept", projectedPixels = 2.2, distance = 8, blockCount = 1 },
    { id = "new", projectedPixels = 2.2, distance = 7, blockCount = 1 },
}, { mobile = true })
assert(retained.kept and not retained.new,
    "visible vegetation gets a lower exit threshold while a new peer stays hidden")

local viewPolicy = NewPolicy({ maxVisibleBlocks = 4 })
local inView = viewPolicy:Evaluate({
    { id = "behind", projectedPixels = 40, distance = 1, blockCount = 4, inView = false },
    { id = "ahead", projectedPixels = 4, distance = 20, blockCount = 4, inView = true },
}, { mobile = true })
assert(not inView.behind and inView.ahead,
    "off-screen or camera-behind grass must not consume the visible-view budget")

local coveragePolicy = NewPolicy({
    maxVisibleBlocks = 16,
    coverageBudgetFraction = 0.5,
})
local coverage = coveragePolicy:Evaluate({
    { id = "near", projectedPixels = 12, distance = 2, blockCount = 8 },
    { id = "far-left", projectedPixels = 1, distance = 40, blockCount = 4,
        minimumProjectedPixels = 0.8, retainedMinimumProjectedPixels = 0.5,
        priority = 1.1, coverageKey = "0:1" },
    { id = "far-right", projectedPixels = 1, distance = 42, blockCount = 4,
        minimumProjectedPixels = 0.8, retainedMinimumProjectedPixels = 0.5,
        priority = 1.1, coverageKey = "4:1" },
}, { mobile = true })
assert(coverage.near and coverage["far-left"] and coverage["far-right"],
    "ground cover must retain visible mid-distance representatives across screen tiles")

local stagedPolicy = NewPolicy({
    maxVisibleBlocks = 20,
    minimumProjectedPixels = 0,
    retainedMinimumProjectedPixels = 0,
    maxVisibilityChangesPerEvaluation = 2,
})
local stagedCandidates = {}
for index = 1, 5 do
    stagedCandidates[index] = {
        id = "staged-" .. tostring(index),
        projectedPixels = 20 - index,
        distance = index,
        blockCount = 1,
    }
end
local stagedFirst, stagedFirstStats = stagedPolicy:Evaluate(stagedCandidates, { mobile = true })
assert(stagedFirstStats.visibleCount == 2 and stagedFirstStats.changeCount == 2
    and stagedFirstStats.pendingChanges == 3,
    "a dense first evaluation must cap native visibility changes and publish its pending work")
local stagedSecond, stagedSecondStats = stagedPolicy:Evaluate(stagedCandidates, { mobile = true })
assert(stagedSecondStats.visibleCount == 4 and stagedSecondStats.pendingChanges == 1,
    "unchanged input must continue the cached transition without rebuilding its target")
local stagedThird, stagedThirdStats = stagedPolicy:Evaluate(stagedCandidates, { mobile = true })
assert(stagedThirdStats.visibleCount == 5 and stagedThirdStats.pendingChanges == 0,
    "staged visibility must converge over bounded evaluations")
local stagedReused, stagedReusedStats = stagedPolicy:Evaluate(stagedCandidates, { mobile = true })
assert(stagedReused == stagedThird and stagedReusedStats.reused,
    "a clean unchanged evaluation must reuse its completed event-driven decision")
stagedPolicy:MarkDirty()
local _, dirtyStats = stagedPolicy:Evaluate(stagedCandidates, { mobile = true })
assert(not dirtyStats.reused, "MarkDirty must force a fresh ranking after a scene-quality event")

local revisionPolicy = NewPolicy({ maxVisibleBlocks = 4 })
local revisionCandidates = {
    { id = "revision", projectedPixels = 10, distance = 2, blockCount = 2 },
}
revisionPolicy:Evaluate(revisionCandidates, { mobile = true, revision = 7 })
local revisionVisible, revisionStats = revisionPolicy:Evaluate(
    revisionCandidates, { mobile = true, revision = 7 })
assert(revisionVisible.revision and revisionStats.reused,
    "an unchanged caller revision must take the clean fast path")
local selectedRevision, selectedRevisionStats = revisionPolicy:Evaluate({
    { id = "revision", projectedPixels = 10, distance = 2, blockCount = 2 },
    { id = "selected-now", projectedPixels = 0, distance = 200, blockCount = 20 },
}, { mobile = true, revision = 8, selectedId = "selected-now", maxVisibilityChanges = 1 })
assert(selectedRevision["selected-now"] and not selectedRevisionStats.reused,
    "selection changes must bypass the cache and become visible immediately")

-- A realistic dense-island candidate set must converge without any evaluation
-- issuing an unbounded burst of native group membership changes.
local stressPolicy = NewPolicy({
    maxVisibleBlocks = 120,
    minimumProjectedPixels = 0,
    retainedMinimumProjectedPixels = 0,
    maxVisibilityChangesPerEvaluation = 17,
})
local stressCandidates = {}
for index = 1, 1200 do
    stressCandidates[index] = {
        id = "stress-" .. tostring(index),
        projectedPixels = 1201 - index,
        distance = index,
        blockCount = 1,
    }
end
local stressVisible, stressStats = stressPolicy:Evaluate(
    stressCandidates, { mobile = true, revision = 100 })
local stressRounds = 1
assert(stressStats.changeCount <= 17 and stressStats.pendingChanges > 0,
    "a 1200-candidate first pass must obey its per-evaluation transition budget")
while stressStats.pendingChanges > 0 and stressRounds < 100 do
    stressVisible, stressStats = stressPolicy:Evaluate(
        stressCandidates, { mobile = true, revision = 100 })
    stressRounds = stressRounds + 1
    assert(stressStats.changeCount <= 17,
        "every dense-island transition round must stay inside the native-change budget")
end
assert(stressRounds < 100 and stressStats.pendingChanges == 0
    and stressStats.visibleCount == 120 and stressStats.visibleBlocks == 120,
    "the staged dense-island decision must converge to the configured block budget")
local stressCached, stressCachedStats = stressPolicy:Evaluate(
    stressCandidates, { mobile = true, revision = 100 })
assert(stressCached == stressVisible and stressCachedStats.reused,
    "a converged 1200-candidate revision must reuse its decision without reranking")
local selectedStress, selectedStressStats = stressPolicy:Evaluate(stressCandidates, {
    mobile = true,
    revision = 101,
    selectedId = "stress-1200",
    maxVisibilityChanges = 1,
})
assert(selectedStress["stress-1200"] and selectedStressStats.changeCount == 1,
    "selection in a dense set must become visible immediately without an unbounded transition")

local immutableCandidate = {
    id = "source",
    projectedPixels = 8,
    distance = 2,
    blockCount = 3,
    blocks = { "leaf", "stem", "flower" },
}
local originalBlocks = immutableCandidate.blocks
local sourceList = { immutableCandidate }
NewPolicy():Evaluate(sourceList, { mobile = true })
assert(#sourceList == 1 and sourceList[1] == immutableCandidate
    and immutableCandidate.blocks == originalBlocks and #immutableCandidate.blocks == 3,
    "render detail evaluation must not remove, replace, or rewrite project instance data")

print("mobile render detail policy tests passed")
