package.path = "scripts/?.lua;" .. package.path

local MobileThermalPolicy = require("MobileThermalPolicy")

local function FakeEngine(maxFps, inactiveFps)
    local result = {
        maxFps = maxFps,
        maxInactiveFps = inactiveFps,
        maxCalls = {},
        inactiveCalls = {},
    }
    function result:GetMaxFps() return self.maxFps end
    function result:GetMaxInactiveFps() return self.maxInactiveFps end
    function result:SetMaxFps(value)
        self.maxFps = value
        self.maxCalls[#self.maxCalls + 1] = value
    end
    function result:SetMaxInactiveFps(value)
        self.maxInactiveFps = value
        self.inactiveCalls[#self.inactiveCalls + 1] = value
    end
    return result
end

local engine = FakeEngine(60, 30)
local policy = MobileThermalPolicy.new({ engine = engine })
policy:SetMobile(true)
assert(engine.maxFps == 40 and engine.maxInactiveFps == 8,
    "mobile runtime should lower active and background frame rates")
local initialCallCount = #engine.maxCalls
assert(policy:Update(0.1, false, true) == 40 and #engine.maxCalls == initialCallCount,
    "unchanged thermal tiers must not reconfigure the engine every frame")
assert(policy:Update(2.6, false, false) == 24 and engine.maxFps == 24,
    "an untouched mobile scene should settle to the low-power tier")
policy:NoteInteraction()
assert(policy:Update(0.01, false, true) == 40 and engine.maxFps == 40,
    "touching the scene should immediately restore the responsive tier")
assert(policy:Update(0.01, true, false) == 12 and engine.maxFps == 12,
    "the screenshot pause surface should not keep rendering at gameplay speed")
policy:SetFocused(false)
assert(engine.maxFps == 8, "an unfocused mobile app should use the background tier")
policy:SetFocused(true)
assert(policy:Update(0.01, false, false) == 40,
    "returning to the app should provide a responsive grace period")
policy:SetMobile(false)
assert(engine.maxFps == 60 and engine.maxInactiveFps == 30,
    "leaving mobile mode should restore host engine limits")
policy:SetMobile(true)
assert(engine.maxFps == 40 and engine.maxInactiveFps == 8,
    "a Stop/Start-style mobile re-entry should reapply thermal limits")
policy:SetMobile(false)

local cappedEngine = FakeEngine(30, 20)
local capped = MobileThermalPolicy.new({ engine = cappedEngine })
capped:SetMobile(true)
assert(cappedEngine.maxFps == 30 and cappedEngine.maxInactiveFps == 8,
    "the policy must never raise a stricter host frame-rate cap")

assert(MobileThermalPolicy.FramePressureBand(1 / 30, 30) == 0
    and MobileThermalPolicy.FramePressureBand(1 / 40, 40) == 0,
    "intentional 24/40 FPS pacing must not be mistaken for GPU pressure")
assert(MobileThermalPolicy.FramePressureBand(1 / 20, 40) >= 2,
    "genuinely slow frames should still reduce decorative detail")

local pressureState = MobileThermalPolicy.NewFramePressureState(0)
for i = 1, 30 do
    local sample = i % 2 == 0 and (1 / 40) * 1.29 or (1 / 40) * 1.31
    local band
    band, pressureState = MobileThermalPolicy.StableFramePressureBand(
        pressureState, sample, 40, 1 / 60)
    assert(band == 0, "frame-time noise around a boundary must not toggle visible detail")
end
for _ = 1, 24 do
    MobileThermalPolicy.StableFramePressureBand(pressureState, (1 / 40) * 1.9, 40, 1 / 60)
end
assert(pressureState.stableBand == 3,
    "sustained severe pressure should still lower detail promptly")
for _ = 1, 60 do
    MobileThermalPolicy.StableFramePressureBand(pressureState, 1 / 40, 40, 1 / 60)
end
assert(pressureState.stableBand == 3,
    "a brief recovery must not immediately rebuild hidden detail")
for _ = 1, 50 do
    MobileThermalPolicy.StableFramePressureBand(pressureState, 1 / 40, 40, 1 / 60)
end
assert(pressureState.stableBand == 0,
    "a sustained recovery should eventually restore full detail")
MobileThermalPolicy.ResetFramePressureState(pressureState, 0)
assert(pressureState.stableBand == 0 and pressureState.candidateBand == nil,
    "an intentional FPS target change must reset pending pressure transitions")

assert(MobileThermalPolicy.IsMobileViewport(2400, 1080, 3, "Android"),
    "native phone identity should win over a large physical framebuffer")
assert(not MobileThermalPolicy.IsMobileViewport(1440, 900, 1, "macOS"),
    "desktop viewport detection should remain unchanged")
assert(MobileThermalPolicy.IsMobileViewport(700, 900, 1, "macOS")
    and not MobileThermalPolicy.IsMobileDevice("macOS")
    and MobileThermalPolicy.IsMobileDevice("Android"),
    "a narrow desktop may use mobile UI without receiving phone thermal limits")

local mobileDetail = MobileThermalPolicy.EnvironmentDetail(true)
local desktopDetail = MobileThermalPolicy.EnvironmentDetail(false)
assert(mobileDetail.nearCloudLat < desktopDetail.nearCloudLat
    and mobileDetail.nearCloudLon < desktopDetail.nearCloudLon,
    "mobile cloud silhouettes should use fewer vertices")
assert(MobileThermalPolicy.NightLightLimit(true) == 4
    and MobileThermalPolicy.NightLightLimit(false) == 8,
    "phones should keep fewer dynamic night lights than desktop")
assert(not MobileThermalPolicy.EnvironmentCastShadow(true, "GrassCells1", true)
    and not MobileThermalPolicy.EnvironmentCastShadow(true, "BridgeRock", true)
    and MobileThermalPolicy.EnvironmentCastShadow(true, "ShrubLobes", true)
    and MobileThermalPolicy.EnvironmentCastShadow(false, "GrassCells1", true),
    "phones should skip the redundant foundation shadow pass without changing desktop")
assert(MobileThermalPolicy.EnvironmentBuildsPerFrame(true) == 1
    and MobileThermalPolicy.EnvironmentBuildsPerFrame(false) > 1000,
    "mobile procedural terrain should be amortised while desktop stays immediate")

print("mobile_thermal_policy_spec: ok")
