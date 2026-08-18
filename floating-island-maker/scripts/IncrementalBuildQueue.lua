local IncrementalBuildQueue = {}
IncrementalBuildQueue.__index = IncrementalBuildQueue

function IncrementalBuildQueue.new()
    return setmetatable({
        jobs = {},
        index = 1,
        completed = 0,
        errors = {},
        cancelled = false,
    }, IncrementalBuildQueue)
end

function IncrementalBuildQueue:Add(job, label)
    if self.cancelled or type(job) ~= "function" then return false end
    self.jobs[#self.jobs + 1] = {
        run = job,
        label = tostring(label or ("job-" .. tostring(#self.jobs + 1))),
    }
    return true
end

function IncrementalBuildQueue:PendingCount()
    if self.cancelled then return 0 end
    return math.max(0, #self.jobs - self.index + 1)
end

function IncrementalBuildQueue:IsPending()
    return self:PendingCount() > 0
end

function IncrementalBuildQueue:Progress()
    return {
        completed = self.completed,
        total = #self.jobs,
        pending = self:PendingCount(),
        errors = #self.errors,
    }
end

function IncrementalBuildQueue:Advance(maxJobs)
    if self.cancelled then return 0, true end
    maxJobs = math.max(1, math.floor(tonumber(maxJobs) or 1))
    local advanced = 0
    while advanced < maxJobs and self.index <= #self.jobs do
        local job = self.jobs[self.index]
        self.jobs[self.index] = false
        self.index = self.index + 1
        advanced = advanced + 1
        local ok, errorMessage = pcall(job.run)
        if not ok then
            self.errors[#self.errors + 1] = {
                label = job.label,
                message = tostring(errorMessage),
            }
        end
        self.completed = self.completed + 1
    end
    return advanced, self.index > #self.jobs, self.errors[#self.errors]
end

function IncrementalBuildQueue:Cancel()
    self.cancelled = true
    self.jobs = {}
    self.index = 1
end

return IncrementalBuildQueue
