---@diagnostic disable: undefined-global

local BuilderStorage = {}

local SAVE_DIR = "island-3d-workbench-v1"
local SAVE_PATH = SAVE_DIR .. "/project.json"
local TEMPLATES_PATH = SAVE_DIR .. "/templates.json"
local ISLAND_PATH = SAVE_DIR .. "/island-v2.json"
local LIBRARY_PATH = SAVE_DIR .. "/model-library-v2.json"
local PROJECT_CLOUD_KEY = "island3d_project_v1"
local TEMPLATES_CLOUD_KEY = "island3d_templates_v1"
local ISLAND_CLOUD_KEY = "island3d_island_v2"
local LIBRARY_CLOUD_KEY = "island3d_model_library_v2"
local WORKSPACE_WATCHDOG_SECONDS = 8
---@type table|nil
local pendingWorkspaceLoad = nil

-- Successful local writes are remembered only for the current Lua session.
-- Versioned stores mutate their root table in place and advance revision /
-- updatedAt for every supported content edit. A shallow identity snapshot also
-- catches replacing a top-level collection or changing a sync flag without a
-- revision bump. Unversioned legacy payloads deliberately bypass this fast
-- path so migration and compatibility saves are never suppressed.
local localSnapshotState = {}

local function CaptureSnapshotIdentity(payload)
    if type(payload) ~= "table"
        or rawget(payload, "revision") == nil
        or rawget(payload, "updatedAt") == nil then return nil end
    -- Weak references prevent the optimization cache from keeping an exported
    -- model library or a replaced island collection alive by itself.
    local fields = setmetatable({}, { __mode = "v" })
    local payloadRef = setmetatable({ payload }, { __mode = "v" })
    local count = 0
    for key, value in pairs(payload) do
        fields[key] = value
        count = count + 1
    end
    return { payloadRef = payloadRef, fields = fields, count = count }
end

local function IsSameLocalSnapshot(path, payload)
    local state = localSnapshotState[path]
    if not state or state.payloadRef[1] ~= payload then return false end
    if fileSystem.FileExists and not fileSystem:FileExists(path) then return false end
    local count = 0
    for key, value in pairs(payload) do
        if state.fields[key] ~= value then return false end
        count = count + 1
    end
    return count == state.count
end

local function EnsureDirectory()
    fileSystem:CreateDir(SAVE_DIR)
end

local function WriteJSON(path, payload)
    if IsSameLocalSnapshot(path, payload) then return true, nil, true end
    EnsureDirectory()
    local file = File(path, FILE_WRITE)
    if not file:IsOpen() then return false, "无法打开本地存档" end
    local ok, encoded = pcall(cjson.encode, payload)
    if not ok then
        file:Close()
        return false, "工程序列化失败"
    end
    file:WriteString(encoded)
    file:Close()
    localSnapshotState[path] = CaptureSnapshotIdentity(payload)
    return true, nil, false
end

local function ReadJSON(path)
    if not fileSystem:FileExists(path) then return nil end
    local file = File(path, FILE_READ)
    if not file:IsOpen() then return nil end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function DecodeCloudValue(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" or value == "" then return nil end
    local ok, data = pcall(cjson.decode, value)
    return ok and type(data) == "table" and data or nil
end

local function Newest(cloudValue, localValue)
    if not cloudValue then return localValue, localValue and "local" or nil end
    if not localValue then return cloudValue, "cloud" end
    local cloudRevision = tonumber(cloudValue.revision) or 0
    local localRevision = tonumber(localValue.revision) or 0
    local cloudUpdatedAt = tonumber(cloudValue.updatedAt) or 0
    local localUpdatedAt = tonumber(localValue.updatedAt) or 0
    if cloudUpdatedAt > 0 and localUpdatedAt > 0 and cloudUpdatedAt ~= localUpdatedAt then
        return cloudUpdatedAt > localUpdatedAt and cloudValue or localValue,
            cloudUpdatedAt > localUpdatedAt and "cloud" or "local"
    end
    if cloudRevision ~= localRevision then
        return cloudRevision > localRevision and cloudValue or localValue,
            cloudRevision > localRevision and "cloud" or "local"
    end
    return cloudValue, "cloud"
end

local function GetCloud()
    local cloud = rawget(_G, "clientCloud")
    return cloud and cloud.Set and cloud.Get and cloud or nil
end

local function Dispatch(callbacks, name, ...)
    local callback = callbacks and callbacks[name]
    if callback then callback(...) end
end

local function SaveCloud(key, payload, localPath, callbacks)
    local localOk, localError = WriteJSON(localPath, payload)
    local cloud = GetCloud()
    if not cloud then
        if localOk then Dispatch(callbacks, "ok", "local")
        else Dispatch(callbacks, "error", localError or "保存失败") end
        return localOk, localError
    end

    local started, startError = pcall(function()
        cloud:Set(key, payload, {
            ok = function() Dispatch(callbacks, "ok", "cloud") end,
            error = function(code, reason)
                if localOk then Dispatch(callbacks, "ok", "local", "云端保存失败：" .. tostring(reason or code or "未知错误"))
                else Dispatch(callbacks, "error", "云端保存失败：" .. tostring(reason or code or "未知错误")) end
            end,
            timeout = function()
                if localOk then Dispatch(callbacks, "ok", "local", "云端保存超时")
                else Dispatch(callbacks, "error", "云端保存超时，请重试") end
            end,
        })
    end)
    if not started then
        local message = "云端保存启动失败：" .. tostring(startError)
        if localOk then Dispatch(callbacks, "ok", "local", message); return true end
        Dispatch(callbacks, "error", message)
        return false, message
    end
    return true
end

function BuilderStorage.Save(payload, callbacks)
    return SaveCloud(PROJECT_CLOUD_KEY, payload, SAVE_PATH, callbacks)
end

function BuilderStorage.SaveTemplates(items, callbacks)
    local payload = { version = 1, items = items or {} }
    return SaveCloud(TEMPLATES_CLOUD_KEY, payload, TEMPLATES_PATH, callbacks)
end

function BuilderStorage.SaveIsland(payload, callbacks)
    return SaveCloud(ISLAND_CLOUD_KEY, payload, ISLAND_PATH, callbacks)
end

function BuilderStorage.SaveModelLibrary(payload, callbacks)
    return SaveCloud(LIBRARY_CLOUD_KEY, payload, LIBRARY_PATH, callbacks)
end

function BuilderStorage.LoadWorkspace(callback)
    if pendingWorkspaceLoad then
        pendingWorkspaceLoad.cancelled = true
        pendingWorkspaceLoad = nil
    end
    local localIsland = ReadJSON(ISLAND_PATH)
    local localLibrary = ReadJSON(LIBRARY_PATH)
    local legacyProject = ReadJSON(SAVE_PATH)
    local legacyTemplatesData = ReadJSON(TEMPLATES_PATH)
    local legacyTemplates = legacyTemplatesData and legacyTemplatesData.items or {}
    local cloud = GetCloud()
    if not cloud or not cloud.BatchGet then
        callback({
            island = localIsland,
            library = localLibrary,
            legacyProject = legacyProject,
            legacyTemplates = legacyTemplates,
            source = "local",
            islandSource = localIsland and "local" or nil,
            librarySource = localLibrary and "local" or nil,
        })
        return
    end

    local finished = false
    local request = { cancelled = false }
    local function Finish(payload)
        if finished or request.cancelled then return end
        finished = true
        if pendingWorkspaceLoad and pendingWorkspaceLoad.finish == Finish then
            pendingWorkspaceLoad = nil
        end
        callback(payload)
    end
    local function LocalFallback(errorMessage)
        return {
            island = localIsland,
            library = localLibrary,
            legacyProject = legacyProject,
            legacyTemplates = legacyTemplates,
            source = "local",
            islandSource = localIsland and "local" or nil,
            librarySource = localLibrary and "local" or nil,
            error = errorMessage,
        }
    end
    local started, startError = pcall(function()
        cloud:BatchGet()
            :Key(ISLAND_CLOUD_KEY)
            :Key(LIBRARY_CLOUD_KEY)
            :Key(PROJECT_CLOUD_KEY)
            :Key(TEMPLATES_CLOUD_KEY)
            :Fetch({
                ok = function(values)
                    values = values or {}
                    local cloudIsland = DecodeCloudValue(values[ISLAND_CLOUD_KEY])
                    local cloudLibrary = DecodeCloudValue(values[LIBRARY_CLOUD_KEY])
                    local cloudLegacyProject = DecodeCloudValue(values[PROJECT_CLOUD_KEY])
                    local cloudLegacyTemplatesData = DecodeCloudValue(values[TEMPLATES_CLOUD_KEY])
                    local island, islandSource = Newest(cloudIsland, localIsland)
                    local library, librarySource = Newest(cloudLibrary, localLibrary)
                    Finish({
                        island = island,
                        library = library,
                        legacyProject = cloudLegacyProject or legacyProject,
                        legacyTemplates = cloudLegacyTemplatesData and cloudLegacyTemplatesData.items or legacyTemplates,
                        source = (islandSource == "cloud" or librarySource == "cloud") and "cloud" or "local",
                        islandSource = islandSource,
                        librarySource = librarySource,
                    })
                end,
                error = function(code, reason)
                    Finish(LocalFallback(
                        "云端工作区读取失败：" .. tostring(reason or code or "未知错误")))
                end,
                timeout = function()
                    Finish(LocalFallback("云端工作区读取超时"))
                end,
            })
    end)
    if not started then
        Finish(LocalFallback("云端工作区读取启动失败：" .. tostring(startError)))
    elseif not finished then
        -- Some mobile network stacks have been observed to invoke neither the
        -- SDK success/error callback nor its timeout callback. Keep rendering
        -- and fall back to the already-read local snapshot after a short,
        -- engine-frame-driven deadline instead of trapping startup forever.
        request.elapsed = 0
        request.finish = Finish
        request.fallback = LocalFallback("云端工作区响应过慢，已先使用本地工作区")
        pendingWorkspaceLoad = request
    end
end

function BuilderStorage.Update(timeStep)
    local pending = pendingWorkspaceLoad
    if not pending then return false end
    pending.elapsed = pending.elapsed + math.max(0, tonumber(timeStep) or 0)
    if pending.elapsed < WORKSPACE_WATCHDOG_SECONDS then return false end
    pending.finish(pending.fallback)
    return true
end

function BuilderStorage.ResetPendingLoads()
    if pendingWorkspaceLoad then pendingWorkspaceLoad.cancelled = true end
    pendingWorkspaceLoad = nil
end

BuilderStorage.WORKSPACE_WATCHDOG_SECONDS = WORKSPACE_WATCHDOG_SECONDS

function BuilderStorage.LoadAll(callback)
    local localProject = ReadJSON(SAVE_PATH)
    local localTemplatesData = ReadJSON(TEMPLATES_PATH)
    local localTemplates = localTemplatesData and localTemplatesData.items or {}
    local cloud = GetCloud()
    if not cloud or not cloud.BatchGet then
        callback(localProject, localTemplates, "local", nil)
        return
    end

    local finished = false
    local function Finish(project, templates, source, errorMessage)
        if finished then return end
        finished = true
        callback(project, templates or {}, source, errorMessage)
    end

    local started, startError = pcall(function()
        cloud:BatchGet()
            :Key(PROJECT_CLOUD_KEY)
            :Key(TEMPLATES_CLOUD_KEY)
            :Fetch({
                ok = function(values)
                    values = values or {}
                    local cloudProject = DecodeCloudValue(values[PROJECT_CLOUD_KEY])
                    local project = cloudProject or localProject
                    local templatesData = DecodeCloudValue(values[TEMPLATES_CLOUD_KEY])
                    local templates = templatesData and templatesData.items or localTemplates
                    Finish(project, templates, cloudProject and "cloud" or localProject and "local" or "cloud", nil)
                end,
                error = function(code, reason)
                    Finish(localProject, localTemplates, "local", "云存档读取失败：" .. tostring(reason or code or "未知错误"))
                end,
                timeout = function()
                    Finish(localProject, localTemplates, "local", "云存档读取超时")
                end,
            })
    end)
    if not started then
        Finish(localProject, localTemplates, "local", "云存档读取启动失败：" .. tostring(startError))
    end
end

return BuilderStorage
