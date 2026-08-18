package.path = "scripts/?.lua;" .. package.path

local PresentationPauseController = require("PresentationPauseController")

local controller = PresentationPauseController.new()
assert(not controller:IsPaused(), "presentation pause must start inactive")

local paused = controller:SetPaused(true, { restorePointerCapture = true })
assert(paused.changed and paused.paused and not paused.restorePointerCapture,
    "entering presentation pause must report a single state transition")
assert(controller:IsPaused(), "entering presentation pause must freeze the runtime")

local duplicatePause = controller:SetPaused(true, { restorePointerCapture = false })
assert(not duplicatePause.changed and duplicatePause.paused,
    "repeated pause requests must be idempotent and preserve resume state")

local resumed = controller:SetPaused(false)
assert(resumed.changed and not resumed.paused and resumed.restorePointerCapture,
    "resuming must return the desktop first-person capture recorded at pause time")
assert(not controller:IsPaused(), "resuming must release the runtime freeze")

local duplicateResume = controller:SetPaused(false)
assert(not duplicateResume.changed and not duplicateResume.restorePointerCapture,
    "repeated resume requests must not restore stale pointer capture")

controller:SetPaused(true, { restorePointerCapture = true })
local reset = controller:Reset()
assert(reset.changed and not controller:IsPaused() and not reset.restorePointerCapture,
    "surface changes must clear pause state without leaking pointer capture")

local afterReset = controller:SetPaused(false)
assert(not afterReset.changed and not afterReset.restorePointerCapture,
    "a reset pause controller must remain inert on a later resume request")

print("presentation-pause tests passed")
