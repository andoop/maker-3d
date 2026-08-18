local PresentationPauseController = {}

local function Snapshot(controller, changed, restorePointerCapture)
    return {
        changed = changed == true,
        paused = controller.paused == true,
        restorePointerCapture = restorePointerCapture == true,
    }
end

function PresentationPauseController.new()
    local controller = {
        paused = false,
        restorePointerCapture = false,
    }

    function controller:IsPaused()
        return self.paused == true
    end

    -- Pointer capture belongs to the runtime rather than the presentation UI.
    -- Remember it while paused so desktop first-person mode can resume without
    -- forcing the player to click the scene again.
    function controller:SetPaused(paused, options)
        paused = paused == true
        options = type(options) == "table" and options or {}
        if paused == self.paused then return Snapshot(self, false, false) end

        if paused then
            self.paused = true
            self.restorePointerCapture = options.restorePointerCapture == true
            return Snapshot(self, true, false)
        end

        local restorePointerCapture = self.restorePointerCapture == true
        self.paused = false
        self.restorePointerCapture = false
        return Snapshot(self, true, restorePointerCapture)
    end

    function controller:Reset()
        local changed = self.paused == true or self.restorePointerCapture == true
        self.paused = false
        self.restorePointerCapture = false
        return Snapshot(self, changed, false)
    end

    return controller
end

return PresentationPauseController
