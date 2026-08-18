-- Engine-free coordinator for reusable rewarded-video gates.
--
-- The host injects showAd(done, request), calls Open() when presenting its
-- confirmation surface, Confirm() after explicit user consent, then Update()
-- once per frame. No SDK globals or product-specific free/unlock policy live
-- here, so the same gate can protect terrains and future rewards.

local RewardGate = {}

local DEFAULT_DELAY_FRAMES = 2
local DEFAULT_TIMEOUT_SECONDS = 150

local FAILURE_MESSAGES = {
    timeout = "广告等待超时，请重新尝试",
    immediate = "广告没有打开，请稍后再试",
    exception = "广告接口异常，请稍后再试",
    persist = "解锁保存失败，请重新尝试",
}

local function CleanText(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function SafeCall(callback, ...)
    if type(callback) ~= "function" then return true end
    return pcall(callback, ...)
end

local function FailureMessage(kind, result)
    if FAILURE_MESSAGES[kind] then return FAILURE_MESSAGES[kind] end
    local raw = type(result) == "table" and CleanText(result.msg) or ""
    if raw == "embed manual close" or raw == "用户跳过广告" then
        return "需要完整观看广告后才能解锁"
    end
    if raw == "unsupported platform" then return "当前环境暂不支持激励视频广告" end
    if raw ~= "" then return "广告播放失败：" .. raw end
    return "广告暂时无法播放，请稍后重试"
end

local function PublicRequest(request)
    return {
        key = CleanText(request and (request.key or request.gateId)),
        title = CleanText(request and request.title),
        description = CleanText(request and request.description),
        subject = CleanText(request and request.subject),
        confirmLabel = CleanText(request and request.confirmLabel),
        context = request and request.context or nil,
    }
end

local function ClearAttempt(self)
    self.attemptToken = nil
    self.remainingFrames = 0
    self.elapsed = 0
end

local function SetIdle(self)
    self.open = false
    self.phase = "closed"
    self.feedback = ""
    self.request = nil
    ClearAttempt(self)
end

local function NotifyChanged(self)
    if type(self.onChanged) ~= "function" then return true end
    local ok, callbackError = pcall(self.onChanged, self:GetSnapshot())
    if not ok then self.lastCallbackError = tostring(callbackError) end
    return ok
end

local function InvokeSettled(self, request, success, message, result)
    local ok, callbackError = SafeCall(request and request.onSettled,
        success == true, message, result)
    if not ok then self.lastCallbackError = tostring(callbackError) end
end

local function FailAttempt(self, token, kind, result, detail)
    if not self.open or self.attemptToken ~= token then return false end
    local request = self.request
    local message = FailureMessage(kind, result)
    ClearAttempt(self)
    self.phase = "ready"
    self.feedback = message
    self.lastOutcome = "failed"
    self.lastFailureKind = kind or "ad"
    self.lastError = detail and tostring(detail) or ""
    NotifyChanged(self)
    InvokeSettled(self, request, false, message, result)
    return false
end

local function GrantAttempt(self, token, result)
    if not self.open or self.attemptToken ~= token then return false end
    local request = self.request or {}

    -- Persist first. A failed write must never run the protected action or tell
    -- the caller that the reward was granted.
    if type(request.persistUnlock) == "function" then
        local ok, persisted, persistError = pcall(
            request.persistUnlock,
            CleanText(request.key or request.gateId),
            request.context,
            result)
        if not ok or persisted == false then
            return FailAttempt(self, token, "persist", result,
                ok and persistError or persisted)
        end
    end

    -- The grant is durable now. Release the single-request lock before action
    -- callbacks, allowing a successful flow to synchronously open its next gate.
    self.generation = self.generation + 1
    SetIdle(self)
    self.lastOutcome = "granted"
    self.lastFailureKind = nil
    self.lastError = ""
    NotifyChanged(self)

    local grantedOk, grantedError = SafeCall(request.onGranted,
        CleanText(request.key or request.gateId), request.context, result)
    if not grantedOk then self.lastCallbackError = tostring(grantedError) end
    InvokeSettled(self, request, true, nil, result)
    return true
end

local function HandleAdResult(self, token, result)
    if not self.open or self.attemptToken ~= token then return false end
    if type(result) == "table" and result.success == true then
        return GrantAttempt(self, token, result)
    end
    return FailAttempt(self, token, "ad", result)
end

function RewardGate.new(options)
    options = type(options) == "table" and options or {}
    local self = {
        showAd = options.showAd,
        onChanged = options.onChanged,
        delayFrames = math.max(0, math.floor(tonumber(options.delayFrames)
            or DEFAULT_DELAY_FRAMES)),
        timeoutSeconds = math.max(0.01, tonumber(options.timeoutSeconds)
            or DEFAULT_TIMEOUT_SECONDS),
        generation = 0,
        open = false,
        phase = "closed",
        feedback = "",
        request = nil,
        attemptToken = nil,
        remainingFrames = 0,
        elapsed = 0,
        lastOutcome = nil,
        lastFailureKind = nil,
        lastError = "",
        lastCallbackError = "",
    }

    function self:Open(request)
        if self.open then return false, "已有激励任务正在等待处理" end
        if type(request) ~= "table" then return false, "激励任务无效" end
        self.generation = self.generation + 1
        self.open = true
        self.phase = "ready"
        self.feedback = ""
        self.request = request
        ClearAttempt(self)
        self.lastOutcome = nil
        self.lastFailureKind = nil
        self.lastError = ""
        self.lastCallbackError = ""
        NotifyChanged(self)
        return true
    end

    function self:Confirm()
        if not self.open or self.phase ~= "ready" then
            return false, "当前激励任务不能开始"
        end
        if type(self.showAd) ~= "function" then
            self.generation = self.generation + 1
            local token = self.generation
            self.attemptToken = token
            FailAttempt(self, token, "exception", nil, "reward ad provider unavailable")
            return false, self.feedback
        end
        self.generation = self.generation + 1
        self.attemptToken = self.generation
        self.remainingFrames = self.delayFrames
        self.elapsed = 0
        self.feedback = ""
        self.phase = self.remainingFrames > 0 and "waiting" or "playing"
        if self.remainingFrames == 0 then self:_BeginAd(self.attemptToken)
        else NotifyChanged(self) end
        return true
    end

    function self:_BeginAd(token)
        if not self.open or self.attemptToken ~= token then return false end
        self.phase = "playing"
        NotifyChanged(self)
        if not self.open or self.attemptToken ~= token then return false end
        local request = self.request
        local ok, immediate = pcall(self.showAd, function(result)
            HandleAdResult(self, token, result or {})
        end, PublicRequest(request))
        if not ok then return FailAttempt(self, token, "exception", nil, immediate) end
        if immediate == false then return FailAttempt(self, token, "immediate") end
        return true
    end

    function self:Cancel()
        if not self.open then return false end
        self.generation = self.generation + 1
        SetIdle(self)
        self.lastOutcome = "cancelled"
        self.lastFailureKind = nil
        self.lastError = ""
        NotifyChanged(self)
        return true
    end

    function self:Update(deltaTime)
        if not self.open or not self.attemptToken then return false end
        local token = self.attemptToken
        if self.phase == "waiting" then
            self.remainingFrames = math.max(0, self.remainingFrames - 1)
            if self.remainingFrames == 0 then self:_BeginAd(token)
            else NotifyChanged(self) end
            return true
        end
        if self.phase == "playing" then
            self.elapsed = self.elapsed + math.max(0, tonumber(deltaTime) or 0)
            if self.elapsed >= self.timeoutSeconds then
                FailAttempt(self, token, "timeout")
            end
            return true
        end
        return false
    end

    function self:Reset()
        self.generation = self.generation + 1
        SetIdle(self)
        self.lastOutcome = nil
        self.lastFailureKind = nil
        self.lastError = ""
        self.lastCallbackError = ""
        NotifyChanged(self)
        return true
    end

    function self:GetSnapshot()
        local request = PublicRequest(self.request)
        return {
            open = self.open == true,
            phase = self.phase,
            busy = self.phase == "waiting" or self.phase == "playing",
            canConfirm = self.open == true and self.phase == "ready",
            key = request.key,
            title = request.title,
            description = request.description,
            subject = request.subject,
            confirmLabel = request.confirmLabel,
            context = request.context,
            feedback = self.feedback,
            token = self.attemptToken,
            remainingFrames = self.remainingFrames,
            elapsed = self.elapsed,
            timeoutSeconds = self.timeoutSeconds,
            lastOutcome = self.lastOutcome,
            lastFailureKind = self.lastFailureKind,
            lastError = self.lastError,
            lastCallbackError = self.lastCallbackError,
        }
    end

    return self
end

return RewardGate
