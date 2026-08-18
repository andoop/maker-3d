local PortalTransitionCoordinator = {}

local function Complete(self, succeeded, reason)
    local payload = self.payload
    self.active = false
    self.started = false
    self.remainingFrames = 0
    self.payload = nil
    return {
        completed = true,
        succeeded = succeeded == true,
        reason = reason,
        payload = payload,
    }
end

function PortalTransitionCoordinator.new(options)
    options = type(options) == "table" and options or {}
    local coordinator = {
        active = false,
        started = false,
        remainingFrames = 0,
        delayFrames = math.max(1, math.floor(tonumber(options.delayFrames) or 1)),
        payload = nil,
    }

    function coordinator:Begin(payload)
        if self.active then return false, "portal_loading_in_flight" end
        self.active = true
        self.started = false
        self.remainingFrames = self.delayFrames
        self.payload = payload
        return true
    end

    function coordinator:IsActive()
        return self.active == true
    end

    -- Begin is called after the source world's Update. Waiting at least one
    -- subsequent Update gives the loading surface one complete render before
    -- potentially expensive world replacement or model restoration starts.
    function coordinator:Update(beginTransition, isWorldLoading)
        if not self.active then return nil end
        if not self.started then
            self.remainingFrames = math.max(0, self.remainingFrames - 1)
            if self.remainingFrames > 0 then
                return { active = true, phase = "waiting" }
            end
            self.started = true
            local called, succeeded = pcall(beginTransition, self.payload)
            if not called then return Complete(self, false, tostring(succeeded)) end
            if succeeded ~= true then return Complete(self, false, "transition_failed") end
        end

        local called, loading = pcall(isWorldLoading)
        if not called then return Complete(self, false, tostring(loading)) end
        if loading == true then return { active = true, phase = "loading" } end
        return Complete(self, true)
    end

    function coordinator:Reset()
        self.active = false
        self.started = false
        self.remainingFrames = 0
        self.payload = nil
    end

    return coordinator
end

return PortalTransitionCoordinator
