-- Engine-free clock and lighting palette for the floating-island world.

local DayNightClock = {}
DayNightClock.__index = DayNightClock

local TAU = math.pi * 2

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function SmoothStep(value)
    value = Clamp(value, 0, 1)
    return value * value * (3 - 2 * value)
end

local function Channel(value, shift)
    return math.floor(value / shift) % 0x100
end

local function MixHex(a, b, amount)
    amount = Clamp(amount, 0, 1)
    local function Mix(shift)
        return math.floor(Channel(a, shift) + (Channel(b, shift) - Channel(a, shift)) * amount + 0.5)
    end
    return Mix(0x10000) * 0x10000 + Mix(0x100) * 0x100 + Mix(1)
end

local function Peak(hour, center, radius)
    local distance = math.abs(hour - center)
    distance = math.min(distance, 24 - distance)
    return SmoothStep(1 - distance / radius)
end

function DayNightClock.VisualState(hour)
    hour = (tonumber(hour) or 0) % 24
    local dayFactor
    if hour >= 7 and hour < 17 then
        dayFactor = 1
    elseif hour >= 5 and hour < 7 then
        dayFactor = SmoothStep((hour - 5) / 2)
    elseif hour >= 17 and hour < 19 then
        dayFactor = 1 - SmoothStep((hour - 17) / 2)
    else
        dayFactor = 0
    end
    local twilight = math.max(Peak(hour, 6, 2.2), Peak(hour, 18, 2.2))
    local nightFactor = 1 - dayFactor

    local background = MixHex(0x07182f, 0x54b7e6, dayFactor)
    background = MixHex(background, hour < 12 and 0xf0a879 or 0xe58a72, twilight * 0.28)
    -- White multiplies the authored sky-dome vertex colours unchanged during
    -- full daylight. Twilight alone adds warmth; no daytime grey veil.
    local skyTint = MixHex(0x17365d, 0xffffff, dayFactor)
    skyTint = MixHex(skyTint, 0xffc09a, twilight * 0.16)
    local cloudTint = MixHex(0x647895, 0xffffff, dayFactor)
    cloudTint = MixHex(cloudTint, 0xffd1ad, twilight * 0.22)

    local phase = "night"
    if hour >= 5 and hour < 7 then phase = "dawn"
    elseif hour >= 7 and hour < 17 then phase = "day"
    elseif hour >= 17 and hour < 19 then phase = "dusk" end

    return {
        phase = phase,
        dayFactor = dayFactor,
        nightFactor = nightFactor,
        twilightFactor = twilight,
        background = background,
        skyTint = skyTint,
        cloudTint = cloudTint,
        hemisphereSky = MixHex(0x647ba9, 0xfff5df, dayFactor),
        hemisphereGround = MixHex(0x17243e, 0x75959a, dayFactor),
        hemisphereIntensity = 0.30 + dayFactor * 0.78,
        keyColor = MixHex(0xaac6ff, 0xffdfaa, dayFactor),
        keyIntensity = 0.34 + dayFactor * 1.28,
        fillColor = MixHex(0x4c6697, 0x9cd8ee, dayFactor),
        fillIntensity = 0.12 + dayFactor * 0.36,
        starOpacity = SmoothStep(nightFactor),
        windowIntensity = SmoothStep(nightFactor) * 2.1,
        celestialAngle = (hour - 6) / 24 * TAU,
    }
end

function DayNightClock.new(options)
    options = options or {}
    local self = setmetatable({}, DayNightClock)
    self.time = (tonumber(options.time) or 9.5) % 24
    self.auto = options.auto ~= false
    self.dayDuration = math.max(60, tonumber(options.dayDuration) or 480)
    return self
end

function DayNightClock:GetTime() return self.time end
function DayNightClock:IsAuto() return self.auto end
function DayNightClock:SetAuto(value) self.auto = value == true; return self.auto end

function DayNightClock:SetTime(hour)
    self.time = (tonumber(hour) or self.time) % 24
    if self.time < 0 then self.time = self.time + 24 end
    return self.time
end

function DayNightClock:AddHours(hours)
    return self:SetTime(self.time + (tonumber(hours) or 0))
end

function DayNightClock:Update(deltaTime)
    if not self.auto then return false end
    local previous = self.time
    self:SetTime(self.time + math.max(0, tonumber(deltaTime) or 0) * 24 / self.dayDuration)
    return self.time ~= previous
end

function DayNightClock:GetTimeLabel()
    local hour = math.floor(self.time)
    local minute = math.floor((self.time - hour) * 60 + 0.5)
    if minute >= 60 then hour, minute = (hour + 1) % 24, 0 end
    return string.format("%02d:%02d", hour, minute)
end

function DayNightClock:GetPhase()
    return DayNightClock.VisualState(self.time).phase
end

function DayNightClock:GetPhaseLabel()
    return ({ dawn = "清晨", day = "白天", dusk = "黄昏", night = "夜晚" })[self:GetPhase()]
end

return DayNightClock
