local ResponsiveLayout = require("ResponsiveLayout")

local MobileThermalPolicy = {}
MobileThermalPolicy.__index = MobileThermalPolicy

MobileThermalPolicy.ACTIVE_FPS = 40
MobileThermalPolicy.IDLE_FPS = 24
MobileThermalPolicy.PAUSED_FPS = 12
MobileThermalPolicy.INACTIVE_FPS = 8
MobileThermalPolicy.IDLE_DELAY = 2.5

local function ReadNumber(object, getter, field, fallback)
    if object and type(object[getter]) == "function" then
        local ok, value = pcall(object[getter], object)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if object and tonumber(object[field]) then return tonumber(object[field]) end
    return fallback
end

local function Call(object, method, value)
    if not object or type(object[method]) ~= "function" then return false end
    return pcall(object[method], object, value)
end

local function RuntimeEngine(explicit)
    if explicit then return explicit end
    local getter = rawget(_G, "GetEngine")
    if type(getter) == "function" then
        local ok, result = pcall(getter)
        if ok and result then return result end
    end
    return rawget(_G, "engine")
end

function MobileThermalPolicy.IsMobileViewport(width, height, dpr, platform)
    local scale = math.max(1, tonumber(dpr) or 1)
    return ResponsiveLayout.Resolve(
        math.max(1, tonumber(width) or 1) / scale,
        math.max(1, tonumber(height) or 1) / scale,
        platform
    ) == "mobile"
end

function MobileThermalPolicy.IsMobileDevice(platform)
    return ResponsiveLayout.IsMobilePlatform(platform)
end

function MobileThermalPolicy.FramePressureBand(frameTime, targetFps)
    local expected = 1 / math.max(1, tonumber(targetFps) or 60)
    local ratio = math.max(0, tonumber(frameTime) or expected) / expected
    if ratio >= 1.85 then return 3 end
    if ratio >= 1.55 then return 2 end
    if ratio >= 1.30 then return 1 end
    return 0
end

function MobileThermalPolicy.NewFramePressureState(initialBand)
    return {
        stableBand = math.max(0, math.min(3, math.floor(tonumber(initialBand) or 0))),
        candidateBand = nil,
        candidateElapsed = 0,
    }
end

function MobileThermalPolicy.ResetFramePressureState(state, band)
    state = state or MobileThermalPolicy.NewFramePressureState(band)
    state.stableBand = math.max(0, math.min(3, math.floor(tonumber(band) or 0)))
    state.candidateBand = nil
    state.candidateElapsed = 0
    return state
end

-- A dense view can hover on a frame-time boundary. Rebuilding the visible
-- model set every time that sample crosses the line makes the scene appear to
-- tremble even though the camera is still. Require sustained pressure before
-- lowering detail, and a longer stable recovery before restoring it.
function MobileThermalPolicy.StableFramePressureBand(state, frameTime, targetFps, timeStep)
    state = state or MobileThermalPolicy.NewFramePressureState(0)
    local rawBand = MobileThermalPolicy.FramePressureBand(frameTime, targetFps)
    local stableBand = math.max(0, math.min(3, tonumber(state.stableBand) or 0))
    if rawBand == stableBand then
        state.candidateBand = nil
        state.candidateElapsed = 0
        return stableBand, state
    end
    if state.candidateBand ~= rawBand then
        state.candidateBand = rawBand
        state.candidateElapsed = 0
    end
    state.candidateElapsed = (tonumber(state.candidateElapsed) or 0)
        + math.max(0, math.min(0.1, tonumber(timeStep) or 0))
    local required
    if rawBand < stableBand then required = 1.8
    elseif rawBand >= 2 then required = 0.35
    else required = 0.70 end
    if state.candidateElapsed >= required then
        state.stableBand = rawBand
        state.candidateBand = nil
        state.candidateElapsed = 0
        stableBand = rawBand
    end
    return stableBand, state
end

function MobileThermalPolicy.EnvironmentDetail(mobile)
    if mobile then
        return {
            shrubLat = 5, shrubLon = 8,
            foliageLat = 5, foliageLon = 8,
            distantFoliageLat = 4, distantFoliageLon = 8,
            nearCloudLat = 6, nearCloudLon = 10,
            lowCloudLat = 5, lowCloudLon = 10,
            midCloudLat = 5, midCloudLon = 10,
            highCloudLat = 4, highCloudLon = 8,
            farCloudLat = 4, farCloudLon = 8,
        }
    end
    return {
        shrubLat = 6, shrubLon = 10,
        foliageLat = 6, foliageLon = 10,
        distantFoliageLat = 6, distantFoliageLon = 10,
        nearCloudLat = 8, nearCloudLon = 14,
        lowCloudLat = 6, lowCloudLon = 12,
        midCloudLat = 6, midCloudLon = 12,
        highCloudLat = 5, highCloudLon = 10,
        farCloudLat = 5, farCloudLon = 10,
    }
end

-- Foundation cells already contain baked face/edge shading and still receive
-- shadows from placed models. Rendering the same hundreds of thousands of
-- foundation vertices again into the phone shadow map adds heat while changing
-- the image only subtly. Authored shrubs and terrain foliage keep casting.
function MobileThermalPolicy.EnvironmentCastShadow(mobile, name, requested)
    if requested ~= true then return false end
    if not mobile then return true end
    name = tostring(name or "")
    for _, prefix in ipairs({
        "GrassCells", "SoilCells", "RockCells", "Bridge", "RockDetails",
        "MossCells", "TerrainWater", "TerrainAccents", "DistantIsland",
    }) do
        if name:find(prefix, 1, true) then return false end
    end
    return true
end

function MobileThermalPolicy.EnvironmentBuildsPerFrame(mobile)
    return mobile and 1 or 1000000
end

function MobileThermalPolicy.DayNightVisualInterval(mobile) return mobile and 0.25 or 0.08 end
function MobileThermalPolicy.DayNightUiInterval(mobile) return mobile and 0.75 or 0.45 end
function MobileThermalPolicy.NightLightRefreshInterval(mobile) return mobile and 1.0 or 0.55 end
function MobileThermalPolicy.NightLightLimit(mobile) return mobile and 4 or 8 end

function MobileThermalPolicy.new(options)
    options = options or {}
    local self = setmetatable({}, MobileThermalPolicy)
    self.engine = RuntimeEngine(options.engine)
    self.activeFps = math.max(1, tonumber(options.activeFps) or MobileThermalPolicy.ACTIVE_FPS)
    self.idleFps = math.max(1, tonumber(options.idleFps) or MobileThermalPolicy.IDLE_FPS)
    self.pausedFps = math.max(1, tonumber(options.pausedFps) or MobileThermalPolicy.PAUSED_FPS)
    self.inactiveFps = math.max(1, tonumber(options.inactiveFps) or MobileThermalPolicy.INACTIVE_FPS)
    self.idleDelay = math.max(0, tonumber(options.idleDelay) or MobileThermalPolicy.IDLE_DELAY)
    self.originalMaxFps = ReadNumber(self.engine, "GetMaxFps", "maxFps", 0)
    self.originalInactiveFps = ReadNumber(self.engine, "GetMaxInactiveFps", "maxInactiveFps", 0)
    self.mobile, self.focused = false, true
    self.idleElapsed = 0
    self.appliedMaxFps, self.appliedInactiveFps = nil, nil
    return self
end

function MobileThermalPolicy:_Limited(target)
    target = math.max(1, math.floor((tonumber(target) or self.activeFps) + 0.5))
    if self.originalMaxFps > 0 then target = math.min(target, self.originalMaxFps) end
    return target
end

function MobileThermalPolicy:_ApplyMax(target)
    target = self:_Limited(target)
    if self.appliedMaxFps ~= target and Call(self.engine, "SetMaxFps", target) then
        self.appliedMaxFps = target
    end
    return target
end

function MobileThermalPolicy:_ApplyInactive(target)
    target = math.max(1, math.floor((tonumber(target) or self.inactiveFps) + 0.5))
    if self.originalInactiveFps > 0 then target = math.min(target, self.originalInactiveFps) end
    if self.appliedInactiveFps ~= target and Call(self.engine, "SetMaxInactiveFps", target) then
        self.appliedInactiveFps = target
    end
end

function MobileThermalPolicy:SetMobile(mobile)
    mobile = mobile == true
    if self.mobile == mobile then return end
    self.mobile = mobile
    self.idleElapsed = 0
    if mobile then
        self:_ApplyInactive(self.inactiveFps)
        self:_ApplyMax(self.activeFps)
    else
        self:Restore()
    end
end

function MobileThermalPolicy:SetFocused(focused)
    self.focused = focused ~= false
    self.idleElapsed = 0
    if self.mobile and not self.focused then self:_ApplyMax(self.inactiveFps) end
end

function MobileThermalPolicy:NoteInteraction()
    self.idleElapsed = 0
end

function MobileThermalPolicy:Update(timeStep, paused, interacting)
    if not self.mobile then
        return self.originalMaxFps > 0 and self.originalMaxFps or 60
    end
    if interacting then self.idleElapsed = 0
    else self.idleElapsed = self.idleElapsed + math.max(0, tonumber(timeStep) or 0) end

    local target
    if not self.focused then target = self.inactiveFps
    elseif paused then target = self.pausedFps
    elseif interacting or self.idleElapsed < self.idleDelay then target = self.activeFps
    else target = self.idleFps end
    return self:_ApplyMax(target)
end

function MobileThermalPolicy:Restore()
    if self.appliedMaxFps ~= nil then
        Call(self.engine, "SetMaxFps", self.originalMaxFps)
        self.appliedMaxFps = nil
    end
    if self.appliedInactiveFps ~= nil then
        Call(self.engine, "SetMaxInactiveFps", self.originalInactiveFps)
        self.appliedInactiveFps = nil
    end
end

return MobileThermalPolicy
