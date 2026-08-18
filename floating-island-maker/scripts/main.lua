---@diagnostic disable: undefined-global

local BuilderWorld = require("BuilderWorld")
local BuilderUI = require("BuilderUI")
local IslandWorld = require("IslandWorld")
local IslandUI = require("IslandUI")
local BuilderStorage = require("BuilderStorage")
local BuiltinTemplates = require("BuiltinTemplates")
local ModelAssetStore = require("ModelAssetStore")
local ModelMarket = require("ModelMarket")
local IslandMarket = require("IslandMarket")
local WorkspaceMigration = require("WorkspaceMigration")
local IslandProjectStore = require("IslandProjectStore")
local IslandTerrainCatalog = require("IslandTerrainCatalog")
local ViewportCoordinates = require("ViewportCoordinates")
local IslandAutoBuilder = require("IslandAutoBuilder")
local IslandPortalNetwork = require("IslandPortalNetwork")
local IslandLayout = require("IslandLayout")
local PortalTemplate = require("PortalTemplate")
local PortalTransitionCoordinator = require("PortalTransitionCoordinator")
local RewardGate = require("RewardGate")
local PresentationPauseController = require("PresentationPauseController")
local runtimeThermal_ = require("MobileThermalPolicy").new()

local world_ = nil
local currentUI_ = nil
local appMode_ = "island"
local assetStore_ = nil
local islandProject_ = nil
local islandCollection_ = nil
local exploreEntries_ = {}
local exploreSource_ = "sample"
local visitingEntry_ = nil
local islandSocial_ = {
    guestbookTarget = nil,
    visitSession = nil,
    profileRequest = 0,
    guestbookRequest = 0,
    guestbookPostRequest = 0,
    currentProfile = nil,
    profiles = require("UserProfileService"),
    guestbook = require("IslandGuestbook"),
}
local workbenchContext_ = nil
local storageReady_ = false
local cloudLoadFailed_ = false
local libraryTab_ = "builtin"

local pendingIslandSave_ = nil
local pendingLibrarySave_ = false
local pendingWorkbenchSave_ = false
local islandSaveInFlight_ = false
local islandSaveShowMessage_ = false
local islandMarketSyncState_ = {
    request = nil,
    queued = false,
    queuedIslandId = nil,
    queuedShowMessage = false,
    queuedProfile = nil,
    queuedRevision = nil,
    timeout = 15,
    autosaveDelay = 0.8,
}
local saveElapsed_ = 0
local TERRAIN_DISCOVERY_DISMISSAL_KEY = "terrain-picker-intro/v1"
local portalTransitGate_ = IslandPortalNetwork.CreateTransitGate({
    successCooldown = 1.2,
    failureCooldown = 0.24,
})
local portalTransition_ = PortalTransitionCoordinator.new({ delayFrames = 1 })
local portalLoadingState_ = nil
local portalLoadingStatus_ = nil
local rewardGate_ = nil
local presentationPause_ = PresentationPauseController.new()

function islandMarketSyncState_:QueueMarketSync(islandId, showMessage)
    if not islandCollection_ then return false end
    islandCollection_.marketSyncPending = true
    self.queued = true
    self.queuedIslandId = islandId or self.queuedIslandId
    self.queuedShowMessage = self.queuedShowMessage or showMessage == true
    self.queuedProfile, self.queuedRevision = nil, nil
    return true
end

local touches_ = {}
local touchCount_ = 0
local pinchDistance_ = nil
local pinchMidX_, pinchMidY_ = nil, nil
local transformTouchId_ = nil
local mobileTransformGesture_ = false
local mouseDown_ = false
local mouseButton_ = nil
local mouseStartX_, mouseStartY_ = 0, 0
local mouseLastX_, mouseLastY_ = 0, 0
local mouseDragged_ = false
local mouseTransform_ = false
local mouseNavigation_ = nil
local colorPickPointerGuard_ = false
local screenWidth_, screenHeight_ = graphics:GetWidth(), graphics:GetHeight()
local screenDpr_ = graphics:GetDPR()
local screenRebuildFrames_ = 0
local startupBootstrapFrames_ = 0
local startupContentFrames_ = 0
local firstPersonMoveTouchId_ = nil
local firstPersonLookTouchId_ = nil
local graphicsDeviceLost_ = false
local graphicsRecoveryFrames_ = 0
local graphicsRecoveryCount_ = 0

local function Distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function Timestamp()
    local ok, value = pcall(os.time)
    return ok and tonumber(value) or 0
end

local function ProjectTerrainId(project)
    local terrain = type(project and project.terrain) == "table" and project.terrain or {}
    return IslandTerrainCatalog.ResolveId(project and project.terrainId or terrain.preset)
end

local function EnsureIslandCollection(fallback)
    if not islandCollection_ then
        islandCollection_ = IslandProjectStore.Normalize(islandProject_, fallback, Timestamp())
        islandProject_ = IslandProjectStore.GetActive(islandCollection_)
    end
    return islandCollection_
end

local function SyncActiveIslandFromWorld()
    if visitingEntry_ then return islandProject_ end
    if appMode_ ~= "island" or not world_ then return islandProject_ end
    EnsureIslandCollection(world_:GetProjectData())
    local project = world_:GetProjectData()
    project.islandId = islandCollection_.activeId
    islandProject_ = IslandProjectStore.Put(islandCollection_, project, Timestamp()) or project
    return islandProject_
end

local function CallWorld(method, ...)
    if not world_ or type(world_[method]) ~= "function" then return nil end
    return world_[method](world_, ...)
end

local function IsPointOverUI(x, y)
    return currentUI_ and currentUI_.IsPointOverUI and currentUI_.IsPointOverUI(x, y) or false
end

local function UIHasFocus()
    return currentUI_ and currentUI_.HasFocus and currentUI_.HasFocus() or false
end

local function UIClearFocus()
    if currentUI_ and currentUI_.ClearFocus then currentUI_.ClearFocus() end
end

local function UIRebuild()
    if currentUI_ and currentUI_.Rebuild then currentUI_.Rebuild() end
end

local function Notify(message, variant)
    if currentUI_ == IslandUI and currentUI_.ShowToast then
        currentUI_.ShowToast(message, variant or "info")
    elseif currentUI_ and currentUI_.ShowToast and variant then
        currentUI_.ShowToast(message, variant)
    end
    if world_ then world_:Notify(message) end
end

function islandSocial_:RefreshCurrentUserProfile()
    local userId = self.profiles.CurrentUserId()
    if not userId then
        self.currentProfile = nil
        return false
    end
    self.currentProfile = self.profiles.GetCached(userId)
    return true
end

local function HandleIslandWorldChanged(state, status)
    if type(state) == "table" and state.visitMode ~= true then
        local currentProfile = islandSocial_.currentProfile
        local currentUserId = islandSocial_.profiles.CurrentUserId()
        if currentProfile then
            state.currentUserId = currentUserId
            state.ownerId = currentUserId
            state.ownerNickname = currentProfile.nickname
            state.nickname = currentProfile.nickname
            state.avatar = islandSocial_.profiles.Copy(currentProfile.avatar)
        end
    end
    if portalTransition_:IsActive() then
        portalLoadingState_ = state or portalLoadingState_
        if status and status ~= "" then portalLoadingStatus_ = status end
        return
    end
    IslandUI.Refresh(state, status)
end

local function RequireWorkspaceReady()
    if storageReady_ then return true end
    Notify("正在恢复云端工作区，请稍后操作")
    return false
end

local function ResolveTouchPoint(rawX, rawY, touchId)
    -- Engine touch events already use framebuffer pixels. Each world now
    -- normalizes these against its exact viewport rectangle before asking the
    -- native Camera for a ray; UI.GetScale/DPR remain UI-layout concerns only.
    -- Applying either factor here a second time makes gizmo hits drift on
    -- high-DPR phones and can even switch scale after a different handle hit.
    -- Prefer Input's live touch state when possible: event payloads may be one
    -- coalesced sample behind the position used by the mobile renderer.
    local count = input and tonumber(input.numTouches) or 0
    if touchId ~= nil and input and input.GetTouch then
        for index = 0, count - 1 do
            local state = input:GetTouch(index)
            if state and state.touchID == touchId and state.position then
                return state.position.x, state.position.y
            end
        end
    end
    return rawX, rawY
end

local function SyncTrackedTouchPoints()
    local count = input and tonumber(input.numTouches) or 0
    if not input or not input.GetTouch then return end
    for index = 0, count - 1 do
        local state = input:GetTouch(index)
        local tracked = state and touches_[state.touchID] or nil
        if tracked and state.position then
            tracked.x, tracked.y = state.position.x, state.position.y
        end
    end
end

local function NavigationModifierDown()
    return input:GetKeyDown(KEY_LCTRL) or input:GetKeyDown(KEY_RCTRL)
        or input:GetKeyDown(KEY_LGUI) or input:GetKeyDown(KEY_RGUI)
        or input:GetKeyDown(KEY_LSHIFT) or input:GetKeyDown(KEY_RSHIFT)
end

local function ResetGestureState(cancelWorld)
    if cancelWorld and world_ then
        CallWorld("CancelTransformDrag")
        CallWorld("CancelColorPick")
    end
    touches_, touchCount_ = {}, 0
    pinchDistance_, pinchMidX_, pinchMidY_ = nil, nil, nil
    transformTouchId_, mobileTransformGesture_ = nil, false
    mouseDown_, mouseButton_ = false, nil
    mouseDragged_, mouseTransform_, mouseNavigation_ = false, false, nil
    colorPickPointerGuard_ = false
    firstPersonMoveTouchId_, firstPersonLookTouchId_ = nil, nil
    CallWorld("SetFirstPersonMovement", 0, 0, false)
    CallWorld("SetFirstPersonFlightVertical", 0)
    CallWorld("SetFirstPersonJoystickVisual", 0, 0, false)
    UIClearFocus()
end

local function SetFirstPersonPointerCapture(enabled)
    if enabled and world_ and not world_.mobileEditor then
        input.mouseMode = MM_RELATIVE
        input.mouseVisible = false
    else
        input.mouseMode = MM_ABSOLUTE
        input.mouseVisible = true
    end
end

local function IsPresentationPaused()
    return appMode_ == "island" and presentationPause_:IsPaused()
end

local function SyncPresentationPauseUI(paused)
    if currentUI_ ~= IslandUI or not IslandUI.SetPaused then return end
    paused = paused == true
    if IslandUI.IsPaused and IslandUI.IsPaused() == paused then return end
    IslandUI.SetPaused(paused, true)
end

local function ResetPresentationPause()
    local wasPaused = presentationPause_:IsPaused()
    presentationPause_:Reset()
    if wasPaused then CallWorld("SetPresentationPaused", false) end
    SyncPresentationPauseUI(false)
end

local function SetPresentationPaused(paused, fromUI)
    paused = paused == true
    if appMode_ ~= "island" or not world_ or currentUI_ ~= IslandUI then
        ResetPresentationPause()
        return false
    end

    local transition = presentationPause_:SetPaused(paused, {
        restorePointerCapture = paused and CallWorld("IsFirstPerson") == true
            and world_.mobileEditor ~= true,
    })
    if transition.changed then
        -- Cancelling active gestures also zeros walk/run, flight and joystick
        -- input, so a held control can never continue moving under the clean
        -- screenshot surface.
        ResetGestureState(true)
        SetFirstPersonPointerCapture(false)
        CallWorld("SetPresentationPaused", paused)
    end
    -- IslandUI owns its local state when the request originates from a UI
    -- button. Runtime-originated resumes (Esc/P) still need an explicit sync.
    if not fromUI then SyncPresentationPauseUI(paused) end
    if not paused and transition.restorePointerCapture
        and CallWorld("IsFirstPerson") == true and world_.mobileEditor ~= true then
        SetFirstPersonPointerCapture(true)
    end
    return true
end

local function SaveModelLibrary(showMessage)
    if not assetStore_ then return false end
    pendingLibrarySave_ = false
    local payload = assetStore_:ExportState()
    if not storageReady_ then return false end
    return BuilderStorage.SaveModelLibrary(payload, {
        ok = function(source)
            cloudLoadFailed_ = source ~= "cloud"
            if showMessage then
                Notify(source == "cloud" and "模型库已保存到云端" or "模型库已保存到本地")
            end
        end,
        error = function(message)
            cloudLoadFailed_ = true
            if showMessage then Notify(message or "模型库保存失败") end
        end,
    })
end

local function SaveIsland(showMessage, skipWorldSync)
    if not skipWorldSync and appMode_ == "island" and world_ then SyncActiveIslandFromWorld() end
    EnsureIslandCollection(islandProject_)
    if not islandProject_ then return false end
    if not storageReady_ then
        if showMessage then Notify("正在恢复云端工作区，请稍后再保存") end
        return false
    end
    if islandSaveInFlight_ then
        -- Coalesce edits/active-island changes while the previous cloud write
        -- is outstanding. Portal round trips must never stack cloud requests.
        pendingIslandSave_, saveElapsed_ = islandCollection_, 0
        islandSaveShowMessage_ = islandSaveShowMessage_ or showMessage == true
        return true
    end
    showMessage = showMessage == true or islandSaveShowMessage_
    islandSaveShowMessage_ = false
    pendingIslandSave_ = nil
    islandSaveInFlight_ = true
    local payload = islandCollection_
    return BuilderStorage.SaveIsland(payload, {
        ok = function(source)
            islandSaveInFlight_ = false
            cloudLoadFailed_ = source ~= "cloud"
            if showMessage then
                Notify(source == "cloud" and ("空岛列表已保存到云端 · " .. tostring(#(islandProject_.instances or {})) .. " 个模型")
                    or "云端不可用，空岛已保存到本地")
            end
            if pendingIslandSave_ then saveElapsed_ = islandMarketSyncState_.autosaveDelay end
        end,
        error = function(message)
            islandSaveInFlight_ = false
            cloudLoadFailed_ = true
            if showMessage then Notify(message or "空岛保存失败") end
            if pendingIslandSave_ then saveElapsed_ = islandMarketSyncState_.autosaveDelay end
        end,
    })
end

local function PersistWorkbenchDraft(showMessage, deferStorage)
    if appMode_ ~= "workbench" or not world_ or not workbenchContext_ then return false end
    pendingWorkbenchSave_ = false
    local data = world_:GetTemplateData(workbenchContext_.name)
    if data then
        data.name = workbenchContext_.name
        data.description = workbenchContext_.description
        data.attributions = workbenchContext_.attributions
        local asset, errorMessage = assetStore_:SaveDraft(workbenchContext_.assetId, data)
        if not asset then
            if showMessage then Notify(errorMessage or "模型保存失败") end
            return false
        end
        workbenchContext_.name = asset.name
        workbenchContext_.description = asset.description
        workbenchContext_.license = asset.license
        if BuilderUI.SetContext then BuilderUI.SetContext({ name = asset.name, license = asset.license }) end
    end
    pendingLibrarySave_ = true
    saveElapsed_ = 0
    -- Returning to the island is latency-sensitive. The in-memory draft is
    -- already authoritative; let the existing 0.8 s autosave flush the large
    -- library after the island is visible instead of serializing it in the
    -- same click frame.
    if storageReady_ and not deferStorage then SaveModelLibrary(showMessage) end
    if showMessage then Notify(data and ("模型已保存 · " .. workbenchContext_.name) or "空白模型草稿已保存") end
    return true
end

local function ScheduleIslandSave(payload)
    EnsureIslandCollection(payload)
    payload.islandId = payload.islandId or islandCollection_.activeId
    islandProject_ = IslandProjectStore.Put(islandCollection_, payload, Timestamp()) or payload
    pendingIslandSave_ = islandCollection_
    saveElapsed_ = 0
    if appMode_ == "island" and world_ then
        world_:SetIslandDirectory(IslandProjectStore.Summaries(islandCollection_), islandCollection_.activeId)
    end
end

local function ApplyWorkbenchDraftToIslandInstance()
    if not workbenchContext_ or not workbenchContext_.returnInstanceId then return false end
    EnsureIslandCollection(islandProject_)
    if not islandProject_ then return false end
    local targetId = tonumber(workbenchContext_.returnInstanceId)
    local savedInstance = nil
    for _, instance in ipairs(islandProject_.instances or {}) do
        if tonumber(instance.id) == targetId then
            savedInstance = instance
            break
        end
    end
    if not savedInstance then return false end
    savedInstance.assetId = workbenchContext_.assetId
    savedInstance.versionId = "latest"
    islandProject_.revision = (tonumber(islandProject_.revision) or 0) + 1
    islandProject_.updatedAt = Timestamp()
    ScheduleIslandSave(islandProject_)
    return true
end

local function ScheduleLibrarySave()
    pendingLibrarySave_ = true
    saveElapsed_ = 0
end

local function ScheduleWorkbenchSave()
    pendingWorkbenchSave_ = true
    saveElapsed_ = 0
end

local function FlushPendingSaves()
    if pendingWorkbenchSave_ then PersistWorkbenchDraft(false) end
    if pendingIslandSave_ then SaveIsland(false) end
    if pendingLibrarySave_ then SaveModelLibrary(false) end
    saveElapsed_ = 0
end

local function CloseCurrentSurface()
    ResetPresentationPause()
    ResetGestureState(true)
    SetFirstPersonPointerCapture(false)
    if world_ and world_.Dispose then world_:Dispose() end
    if currentUI_ and currentUI_.Shutdown then currentUI_.Shutdown() end
    world_, currentUI_ = nil, nil
end

local function TerrainRewardKey(terrainId)
    return "terrain:" .. tostring(IslandTerrainCatalog.ResolveId(terrainId))
end

local function DecorateTerrainRewards(collection, summaries)
    local result = type(summaries) == "table" and summaries or {}
    for _, summary in ipairs(result) do
        local terrainId = IslandTerrainCatalog.ResolveId(summary)
        local rewardRequired = terrainId ~= IslandTerrainCatalog.DEFAULT_ID
        local unlocked = not rewardRequired
            or IslandProjectStore.IsRewardUnlocked(collection, TerrainRewardKey(terrainId))
        summary.rewardRequired = rewardRequired
        summary.unlocked = unlocked
        summary.locked = rewardRequired and not unlocked
    end
    return result
end

local function RefreshIslandLibrary(tab)
    libraryTab_ = tab or libraryTab_
    if appMode_ == "island" and world_ then
        local autoBuildSummaries, seen = {}, {}
        for _, summary in ipairs(assetStore_:GetSummaries("all")) do
            local key = tostring(summary.assetId or summary.id)
            if tostring(summary.assetId or summary.id) ~= PortalTemplate.ASSET_ID and not seen[key] then
                seen[key] = true
                autoBuildSummaries[#autoBuildSummaries + 1] = summary
            end
        end
        world_:SetAutoBuildLibrary(autoBuildSummaries)
        world_:SetLibrary(libraryTab_, assetStore_:GetSummaries(libraryTab_))
        local collection = EnsureIslandCollection(world_:GetProjectData())
        local randomTerrains = IslandProjectStore.ListRandomTerrains(collection)
        world_:SetTerrainLibrary(DecorateTerrainRewards(collection,
            IslandTerrainCatalog.List(randomTerrains)), randomTerrains)
        world_:SetIslandDirectory(IslandProjectStore.Summaries(islandCollection_), islandCollection_.activeId)
    end
end

local function AutoBuildIsland(selection)
    if not RequireWorkspaceReady() or visitingEntry_ or appMode_ ~= "island" then return false end
    local selectedAssets, seen = {}, {}
    for _, source in ipairs(type(selection) == "table" and selection or {}) do
        local assetId = type(source) == "table" and (source.assetId or source.id) or source
        local versionId = type(source) == "table" and source.versionId or nil
        local asset = assetStore_:Get(assetId, versionId)
        if asset and not seen[asset.assetId] then
            seen[asset.assetId] = true
            selectedAssets[#selectedAssets + 1] = asset
        end
    end
    if #selectedAssets == 0 then Notify("请至少勾选一个模型"); return false end
    local plan = IslandAutoBuilder.Build({
        selectedAssets = selectedAssets,
        layout = world_.layout,
        existingInstances = world_.instances,
        resolveAsset = function(assetId, versionId)
            local asset = assetStore_:Get(assetId, versionId)
            return asset and assetStore_:AcquireRenderable(asset) or nil
        end,
        seed = table.concat({ tostring(islandProject_ and islandProject_.islandId or "island"),
            tostring(islandProject_ and islandProject_.revision or 0), tostring(#selectedAssets) }, ":"),
    })
    local applied = world_:ApplyGeneratedPlan(plan)
    if applied then
        for _, asset in ipairs(selectedAssets) do assetStore_:MarkUsed(asset) end
        ScheduleLibrarySave()
    end
    return applied == true
end

local function WorkbenchAssets()
    local result, seen = {}, {}
    for _, asset in ipairs(assetStore_:GetAssets("all")) do
        local canInsert = asset.source ~= "market" or asset.license ~= "use_only" or asset.isOwnPublication == true
        if canInsert and not seen[asset.assetId] then
            seen[asset.assetId] = true
            local flattened = assetStore_:Flatten(asset)
            if flattened and #flattened.blocks > 0 then
                flattened.favorite = assetStore_:IsFavorite(asset)
                flattened.thumbnail = asset.thumbnail
                flattened.sourceName = asset.source == "market" and "模型市场" or asset.source == "mine" and "我的模型" or "内置模型"
                result[#result + 1] = flattened
            end
        end
    end
    return result
end

local function RefreshWorkbenchLibrary()
    if appMode_ == "workbench" and world_ then world_:SetTemplateLibrary(WorkbenchAssets()) end
end

local function RefreshActiveLibrary()
    if appMode_ == "island" then RefreshIslandLibrary(libraryTab_) else RefreshWorkbenchLibrary() end
end

local function ToggleFavorite(assetId, versionId)
    if not RequireWorkspaceReady() then return end
    local favorite = assetStore_:ToggleFavorite(assetId, versionId)
    ScheduleLibrarySave()
    RefreshActiveLibrary()
    Notify(favorite and "已收藏模型，可在空岛与工作台中随时使用" or "已取消收藏")
end

local function RefreshMarket(showMessage)
    if showMessage then Notify("正在刷新模型市场……") end
    ModelMarket.Load({
        ok = function(items, source)
            if not assetStore_ then return end
            assetStore_:MergeRemoteMarket(items)
            RefreshActiveLibrary()
            if showMessage then
                Notify(source == "cloud" and ("模型市场已更新 · " .. tostring(#items) .. " 个玩家作品")
                    or "当前离线，已显示内置的市场精选")
            end
        end,
        error = function(message)
            RefreshActiveLibrary()
            if showMessage then Notify(message .. " · 已保留离线精选") end
        end,
    })
end

local function SyncMarketProfile(showMessage, published)
    if not assetStore_ or not assetStore_:HasPendingMarketSync() then return false end
    local profile = assetStore_:GetPublishedProfile()
    ModelMarket.Publish(profile, {
        ok = function(source)
            if not assetStore_ then return end
            if source == "cloud" then
                assetStore_:MarkMarketSynced()
                SaveModelLibrary(false)
                if showMessage then
                    if published then Notify("已发布到模型市场 · 版本 " .. tostring(published.versionId))
                    else Notify("模型市场公开列表已同步") end
                end
            elseif showMessage then
                Notify("发布版本已保存在待同步队列 · 联网后自动同步市场")
            end
        end,
        error = function(message)
            if showMessage then Notify(message .. " · 发布版本已进入待同步队列") end
        end,
    })
    return true
end

local function UnpublishAsset(assetId)
    if not RequireWorkspaceReady() then return false end
    local ok, errorMessage = assetStore_:Unpublish(assetId)
    if not ok then Notify(errorMessage or "模型无法下架"); return false end
    ScheduleLibrarySave()
    RefreshActiveLibrary()
    Notify("正在从模型市场下架作品……")
    SyncMarketProfile(true)
    return true
end

local function PublishAsset(assetId)
    if not RequireWorkspaceReady() then return false end
    local published, errorMessage = assetStore_:Publish(assetId)
    if not published then Notify(errorMessage or "模型无法发布"); return false end
    if workbenchContext_ and workbenchContext_.assetId == assetId then
        local draft = assetStore_:Get(assetId)
        workbenchContext_.license = draft and draft.license or published.license
        if BuilderUI.SetContext then
            BuilderUI.SetContext({ name = workbenchContext_.name, license = workbenchContext_.license })
        end
    end
    ScheduleLibrarySave()
    RefreshActiveLibrary()
    Notify("正在发布《" .. published.name .. "》" .. published.versionId .. "……")
    SyncMarketProfile(true, published)
    return true
end

local OpenIsland
local OpenWorkbench

local function PortalErrorMessage(reason)
    local value = tostring(reason or "")
    if value == "target_must_be_another_island" then return "请选择另一座空岛" end
    if value == "source_endpoint_unbound" then return "这座云门尚未绑定" end
    if value == "portal_pair_broken" then return "云门配对已失效，请重新绑定" end
    if value == "source_not_published" then return "当前参观空岛已经下架" end
    if value == "target_not_published" then return "目标空岛未发布或已经下架" end
    if value == "target_island_missing" then return "目标空岛已不存在" end
    if value:find("target_portal_placement_failed", 1, true) then
        return "目标空岛暂时找不到可放置另一端的位置"
    end
    return "云门操作失败：" .. (value ~= "" and value or "未知原因")
end

local function BindPortalToIsland(instanceId, targetIslandId)
    if not RequireWorkspaceReady() or visitingEntry_ or appMode_ ~= "island" then return false end
    if world_ and world_:IsProjectLoading() then
        world_:Notify("空岛仍在布置中，请稍候再绑定云门")
        return false
    end
    local selected = world_ and world_.byId and world_.byId[tonumber(instanceId)] or nil
    if not selected or selected.assetId ~= PortalTemplate.ASSET_ID then
        Notify("请先选择一座成对云门")
        return false
    end
    SyncActiveIslandFromWorld()
    local collection = EnsureIslandCollection(islandProject_)
    local activeId = tostring(collection.activeId or islandProject_.islandId or "")
    local pair, errorMessage = IslandPortalNetwork.BindPair(collection, {
        sourceIslandId = activeId,
        sourceInstanceId = selected.id,
        targetIslandId = targetIslandId,
        portalAssetId = PortalTemplate.ASSET_ID,
        portalVersionId = selected.versionId,
        resolveAsset = function(assetId, versionId)
            local asset = assetStore_:Get(assetId, versionId)
            return asset and assetStore_:AcquireRenderable(asset) or nil
        end,
        resolveLayout = function(terrainId) return IslandLayout.Resolve(terrainId) end,
        now = Timestamp(),
    })
    if not pair then Notify(PortalErrorMessage(errorMessage)); return false end
    islandProject_ = IslandProjectStore.GetActive(collection)
    world_:SetInstancePortal(selected.id, pair.sourceBinding)
    world_:CheckpointExternalMutation()
    world_:SetIslandDirectory(IslandProjectStore.Summaries(collection), collection.activeId)
    if pair.sourceProject.published == true or pair.targetProject.published == true then
        islandMarketSyncState_:QueueMarketSync(pair.sourceProject.islandId)
    end
    pendingIslandSave_, saveElapsed_ = collection, 0
    SaveIsland(false, true)
    Notify("云门已成对连接《" .. tostring(pair.targetProject.name or "另一座空岛") .. "》")
    return true
end

local function DeleteSelectedIslandInstance()
    if appMode_ ~= "island" or not world_ then return false end
    if world_:IsProjectLoading() then
        world_:Notify("空岛仍在分批布置中，请稍候再编辑")
        return false
    end
    local selected = world_:GetSelected()
    if not selected then return false end
    if selected.assetId ~= PortalTemplate.ASSET_ID then return world_:DeleteSelected() end
    if not RequireWorkspaceReady() or visitingEntry_ then return false end
    SyncActiveIslandFromWorld()
    local collection = EnsureIslandCollection(islandProject_)
    local deleted, result = IslandPortalNetwork.DeleteEndpoint(
        collection, collection.activeId, selected.id, Timestamp())
    if not deleted then Notify(PortalErrorMessage(result)); return false end
    world_:RemovePortalLocally(selected.id, "已移除成对云门 · 另一端也已同步清理", false)
    world_:CheckpointExternalMutation()
    islandProject_ = IslandProjectStore.GetActive(collection)
    if type(result) == "table" and ((result.sourceProject and result.sourceProject.published == true)
        or (result.targetProject and result.targetProject.published == true)) then
        islandMarketSyncState_:QueueMarketSync(collection.activeId)
    end
    pendingIslandSave_, saveElapsed_ = collection, 0
    SaveIsland(false, true)
    return true
end

local function ActivatePortalRoute(activation)
    if not activation then return false end
    local portal = type(activation.portal) == "table" and activation.portal or {}
    local transitToken = portalTransitGate_:TryBegin(portal.linkId)
    if not transitToken then
        CallWorld("FinishPortalTransition", false)
        return false
    end
    local function Finish(success, message)
        if message then Notify(message) end
        CallWorld("FinishPortalTransition", success == true)
        portalTransitGate_:Finish(transitToken, success == true)
        return success == true
    end
    if appMode_ ~= "island" then return Finish(false) end
    if visitingEntry_ then
        local route, errorMessage = IslandMarket.ResolvePublishedPortal(
            exploreEntries_, visitingEntry_, activation.instanceId)
        if not route then return Finish(false, PortalErrorMessage(errorMessage)) end
        local targetEntry = route.targetEntry
        if assetStore_:CacheExternalAssets(targetEntry.assets or {}) then ScheduleLibrarySave() end
        visitingEntry_ = targetEntry
        islandSocial_.visitSession = islandSocial_.visitSession or {}
        islandSocial_.visitSession.ownerId = tostring(targetEntry.ownerId or "")
        islandSocial_.visitSession.currentEntry = targetEntry
        local opened = OpenIsland("穿过云门 · 已抵达《"
            .. tostring(targetEntry.name or "另一座空岛") .. "》", false, {
            visit = targetEntry,
            incremental = true,
            priorityInstanceId = route.targetInstance.id,
            priorityRadius = 4.5,
            portalTransition = true,
        })
        if opened == false then return Finish(false, "目标空岛暂时无法打开") end
        local arrived = world_ and world_:ArriveAtPortal(
            route.targetInstance.id, activation.firstPerson == true)
        if activation.firstPerson == true and arrived and world_:IsFirstPerson()
            and not portalTransition_:IsActive() then
            SetFirstPersonPointerCapture(true)
        end
        return Finish(arrived == true, arrived and nil or "目标云门暂时无法抵达")
    end
    if not RequireWorkspaceReady() then return Finish(false) end
    SyncActiveIslandFromWorld()
    local collection = EnsureIslandCollection(islandProject_)
    local sourceIslandId = tostring(collection.activeId or islandProject_.islandId or "")
    local route, errorMessage = IslandPortalNetwork.Resolve(
        collection, sourceIslandId, activation.instanceId)
    if not route then return Finish(false, PortalErrorMessage(errorMessage)) end
    local targetProject, setError = IslandProjectStore.SetActive(
        collection, route.targetProject.islandId, Timestamp())
    if not targetProject then return Finish(false, setError or "目标空岛无法打开") end
    islandProject_ = targetProject
    -- Active-island persistence is debounced with the regular autosave queue.
    -- Writing storage synchronously on every passage was another source of
    -- overlapping work when players walked back and forth quickly.
    pendingIslandSave_, saveElapsed_ = collection, 0
    local opened = OpenIsland("穿过云门 · 已抵达《" .. tostring(targetProject.name or "另一座空岛") .. "》", false, {
        incremental = true,
        priorityInstanceId = route.targetInstance.id,
        priorityRadius = 4.5,
        portalTransition = true,
    })
    if opened == false then return Finish(false, "目标空岛暂时无法打开") end
    local arrived = world_ and world_:ArriveAtPortal(route.targetInstance.id, activation.firstPerson == true)
    if activation.firstPerson == true and arrived and world_:IsFirstPerson() then
        if not portalTransition_:IsActive() then SetFirstPersonPointerCapture(true) end
    end
    return Finish(arrived == true, arrived and nil or "目标云门暂时无法抵达")
end

local function BeginPortalTransition(activation)
    local began = portalTransition_:Begin(activation)
    if not began then return false end
    portalLoadingState_, portalLoadingStatus_ = nil, nil
    ResetGestureState(true)
    SetFirstPersonPointerCapture(false)
    -- Use the exact same lightweight surface as application startup. It owns
    -- the UI root during the hand-off, while main.lua blocks scene input.
    IslandUI.ShowBootstrap()
    return true
end

local function FinishPortalLoading(result)
    local state = portalLoadingState_ or CallWorld("GetState")
    local status = portalLoadingStatus_
    if result and not result.succeeded and (not status or status == "") then
        status = "传送失败，请稍后重试"
    end
    portalLoadingState_, portalLoadingStatus_ = nil, nil
    if currentUI_ == IslandUI then
        -- Refresh first so Rebuild uses the destination state even when the
        -- source and target happen to share the same structural signature.
        IslandUI.Refresh(state, status)
        IslandUI.Rebuild(true)
    end
    if result and result.succeeded and CallWorld("IsFirstPerson") then
        SetFirstPersonPointerCapture(true)
    else
        SetFirstPersonPointerCapture(false)
    end
end

local function DecorateExploreEntries(entries)
    local favorites = islandCollection_ and islandCollection_.exploreFavorites or {}
    local likes = islandCollection_ and islandCollection_.exploreLikes or {}
    for _, entry in ipairs(entries or {}) do
        local id = tostring(entry.id or "")
        if entry.baseLikes == nil then entry.baseLikes = math.max(0, tonumber(entry.likes) or 0) end
        entry.favorite = favorites[id] == true
        entry.liked = likes[id] == true
        entry.likes = (tonumber(entry.baseLikes) or 0) + (entry.liked and 1 or 0)
    end
    return entries
end

local function SetExploreEntries(entries, loading, source)
    if type(entries) == "table" then exploreEntries_ = DecorateExploreEntries(entries) end
    exploreSource_ = tostring(source or exploreSource_ or "sample")
    IslandUI.SetExploreState(exploreEntries_, loading == true, exploreSource_)
end

local function ToggleExploreFlag(entryId, field)
    if not RequireWorkspaceReady() then return nil end
    local collection = EnsureIslandCollection(islandProject_)
    local id = tostring(entryId or "")
    if id == "" then return nil end
    collection[field] = type(collection[field]) == "table" and collection[field] or {}
    local enabled = collection[field][id] ~= true
    collection[field][id] = enabled and true or nil
    collection.revision = (tonumber(collection.revision) or 0) + 1
    collection.updatedAt = Timestamp()
    pendingIslandSave_, saveElapsed_ = collection, 0
    SetExploreEntries(exploreEntries_, false, exploreSource_)
    return enabled
end

local function ToggleExploreFavorite(entryId)
    local enabled = ToggleExploreFlag(entryId, "exploreFavorites")
    if enabled ~= nil then Notify(enabled and "已收藏这座空岛" or "已取消收藏") end
    return enabled
end

local function ToggleExploreLike(entryId)
    local enabled = ToggleExploreFlag(entryId, "exploreLikes")
    if enabled ~= nil then Notify(enabled and "已点赞这座空岛" or "已取消点赞") end
    return enabled
end

local function RefreshIslandMarket(showMessage)
    SetExploreEntries(exploreEntries_, true, "cloud")
    if showMessage then Notify("正在寻找可参观的玩家空岛……") end
    IslandMarket.Load({
        ok = function(entries, source)
            if not assetStore_ then return end
            if #entries == 0 then entries, source = IslandMarket.SampleEntries(assetStore_), "sample" end
            SetExploreEntries(entries, false, source)
            if showMessage then
                Notify(source == "cloud" and ("探索列表已更新 · " .. tostring(#entries) .. " 座玩家空岛")
                    or "当前离线，已展示可参观的示范空岛")
            end
        end,
        error = function(message)
            if not assetStore_ then return end
            SetExploreEntries(IslandMarket.SampleEntries(assetStore_), false, "sample")
            if showMessage then Notify(tostring(message) .. " · 已展示示范空岛") end
        end,
    })
end

function islandMarketSyncState_:SetUI(busy, islandId)
    if world_ and world_.SetIslandMarketSyncState then
        world_:SetIslandMarketSyncState(busy == true, islandId)
    end
end

local function SyncIslandMarketProfile(showMessage, preparedProfile, islandId)
    if not islandCollection_ or not assetStore_ then
        if showMessage then Notify("空岛发布服务还没有准备好，请稍后重试", "error") end
        return false
    end
    if not islandCollection_.marketSyncPending then
        islandMarketSyncState_.queued = false
        islandMarketSyncState_.queuedIslandId = nil
        islandMarketSyncState_.queuedShowMessage = false
        islandMarketSyncState_.queuedProfile = nil
        islandMarketSyncState_.queuedRevision = nil
        if showMessage then Notify("发布状态已经是最新", "success") end
        return true
    end
    if islandMarketSyncState_.request then
        islandMarketSyncState_.queued = true
        islandMarketSyncState_.queuedIslandId = islandId
            or islandMarketSyncState_.queuedIslandId
        islandMarketSyncState_.queuedShowMessage = islandMarketSyncState_.queuedShowMessage
            or showMessage == true
        if preparedProfile then
            islandMarketSyncState_.queuedProfile = preparedProfile
            islandMarketSyncState_.queuedRevision = math.max(0,
                tonumber(islandCollection_.revision) or 0)
        end
        if islandId then
            islandMarketSyncState_.request.islandId = tostring(islandId)
            islandMarketSyncState_:SetUI(true, islandMarketSyncState_.request.islandId)
        end
        if showMessage then Notify("上一项发布正在同步，最新操作已排队", "info") end
        return true
    end

    local profile, errorMessage = preparedProfile, nil
    if not profile then profile, errorMessage = IslandMarket.BuildProfile(islandCollection_, assetStore_) end
    if not profile then
        if showMessage then Notify(errorMessage or "空岛不符合发布要求", "error") end
        return false
    end

    local request = {
        revision = math.max(0, tonumber(islandCollection_.revision) or 0),
        elapsed = 0,
        islandId = islandId and tostring(islandId) or nil,
        showMessage = showMessage == true,
        omittedEmptyInstances = tonumber(profile.omittedEmptyInstances) or 0,
    }
    islandMarketSyncState_.request = request
    islandMarketSyncState_:SetUI(true, request.islandId)

    local function FinishRequest()
        if islandMarketSyncState_.request ~= request then return false end
        islandMarketSyncState_.request = nil
        islandMarketSyncState_:SetUI(false, nil)
        return true
    end

    local started = IslandMarket.Publish(profile, {
        ok = function(source)
            if not FinishRequest() or not islandCollection_ then return end
            local stillCurrent = math.max(0, tonumber(islandCollection_.revision) or 0)
                == request.revision
            if source == "cloud" and stillCurrent then
                islandCollection_.marketSyncPending = false
                islandMarketSyncState_.queued = false
                islandMarketSyncState_.queuedIslandId = nil
                islandMarketSyncState_.queuedShowMessage = false
                islandMarketSyncState_.queuedProfile = nil
                islandMarketSyncState_.queuedRevision = nil
                SaveIsland(false, true)
                if request.showMessage then
                    local omitted = request.omittedEmptyInstances > 0
                        and (" · 已忽略 " .. tostring(request.omittedEmptyInstances) .. " 个空模型") or ""
                    Notify("探索市场已同步 · 玩家可以参观已发布空岛" .. omitted, "success")
                end
                RefreshIslandMarket(false)
            elseif source == "cloud" then
                -- A newer publish/unpublish or island edit happened while this
                -- request was in flight. Never let the stale callback clear it.
                islandCollection_.marketSyncPending = true
                islandMarketSyncState_.queued = true
                islandMarketSyncState_.queuedIslandId = request.islandId
                islandMarketSyncState_.queuedShowMessage = islandMarketSyncState_.queuedShowMessage
                    or request.showMessage == true
                if request.showMessage then Notify("上一版已同步，正在继续发布最新状态", "info") end
            elseif request.showMessage then
                Notify("发布状态已保存在本地 · 联网后会自动同步", "warning")
            end
        end,
        error = function(message)
            if not FinishRequest() then return end
            if islandCollection_ then islandCollection_.marketSyncPending = true end
            if request.showMessage then
                Notify(tostring(message) .. " · 已保留待同步状态，可再次点击发布", "error")
            end
        end,
    })
    if started == false and islandMarketSyncState_.request == request then
        FinishRequest()
        if showMessage then Notify("发布请求没有启动，请稍后重试", "error") end
        return false
    end
    return true
end

local function SetIslandPublished(islandId, published)
    if not RequireWorkspaceReady() then return false end
    if visitingEntry_ then
        Notify("正在参观其他玩家空岛，请先回到自己的空岛再发布", "warning")
        return false
    end
    if world_ and world_.IsProjectLoading and world_:IsProjectLoading() then
        Notify("空岛模型仍在加载，请稍候再发布", "warning")
        return false
    end
    SyncActiveIslandFromWorld()
    local collection = EnsureIslandCollection(islandProject_)
    local project = IslandProjectStore.Get(collection, islandId)
    if not project then Notify("空岛不存在", "error"); return false end
    local previous, oldPending = project.published == true, collection.marketSyncPending == true
    local oldProjectRevision, oldProjectUpdatedAt = project.revision, project.updatedAt
    local oldCollectionRevision, oldCollectionUpdatedAt = collection.revision, collection.updatedAt
    local changed, errorMessage = IslandProjectStore.SetPublished(collection, islandId, published, Timestamp())
    if not changed then Notify(errorMessage or "发布状态修改失败", "error"); return false end
    Notify(published and ("正在校验《" .. tostring(project.name) .. "》的发布内容……")
        or ("正在准备下架《" .. tostring(project.name) .. "》……"), "info")

    local profile, profileError = IslandMarket.BuildProfile(collection, assetStore_)
    if not profile then
        project.published, project.revision, project.updatedAt = previous, oldProjectRevision, oldProjectUpdatedAt
        collection.marketSyncPending = oldPending
        collection.revision, collection.updatedAt = oldCollectionRevision, oldCollectionUpdatedAt
        Notify(profileError or "空岛不符合发布要求", "error")
        world_:SetIslandDirectory(IslandProjectStore.Summaries(collection), collection.activeId)
        return false
    end
    SaveIsland(false, true)
    world_:SetIslandDirectory(IslandProjectStore.Summaries(collection), collection.activeId)
    Notify(published and ("正在发布《" .. tostring(project.name) .. "》到探索市场……")
        or ("正在从探索市场下架《" .. tostring(project.name) .. "》……"), "info")
    return SyncIslandMarketProfile(true, profile, islandId)
end

function islandMarketSyncState_:Update(timeStep)
    if self.request then
        self.request.elapsed = (tonumber(self.request.elapsed) or 0)
            + math.max(0, tonumber(timeStep) or 0)
        if self.request.elapsed >= self.timeout and not self.request.slowNotified then
            self.request.slowNotified = true
            if self.request.showMessage then
                Notify("网络响应较慢，仍在等待；最新操作会在当前请求结束后自动同步", "warning")
            end
        end
    end
    if not self.request and self.queued
        and islandCollection_ and islandCollection_.marketSyncPending then
        local islandId = self.queuedIslandId
        local showMessage = self.queuedShowMessage
        local revision = math.max(0, tonumber(islandCollection_.revision) or 0)
        local profile = self.queuedRevision == revision and self.queuedProfile or nil
        self.queued, self.queuedIslandId, self.queuedShowMessage = false, nil, false
        self.queuedProfile, self.queuedRevision = nil, nil
        -- A cloud write is never overlapped with its predecessor. If the local
        -- project changed again, discard the queued snapshot and rebuild it.
        SyncIslandMarketProfile(showMessage, profile, islandId)
    end
end

local function VisitIsland(entry)
    if not RequireWorkspaceReady() then return false end
    local target = nil
    for _, candidate in ipairs(exploreEntries_) do
        if tostring(candidate.id) == tostring(type(entry) == "table" and entry.id or entry) then target = candidate; break end
    end
    if not target or type(target.project) ~= "table" then Notify("这座空岛暂时无法参观"); return false end
    local switchingFromOwnIsland = visitingEntry_ == nil
    if switchingFromOwnIsland then
        SyncActiveIslandFromWorld()
        SaveIsland(false, true)
        islandSocial_.visitSession = {
            homeIslandId = tostring(islandCollection_ and islandCollection_.activeId
                or islandProject_ and islandProject_.islandId or ""),
        }
    end
    if assetStore_:CacheExternalAssets(target.assets or {}) then ScheduleLibrarySave() end
    visitingEntry_ = target
    islandSocial_.visitSession = islandSocial_.visitSession or {}
    islandSocial_.visitSession.ownerId = tostring(target.ownerId or "")
    islandSocial_.visitSession.currentEntry = target
    local message = "已进入《" .. tostring(target.name) .. "》· 可环绕观察或进入第一人称漫游"
    if appMode_ == "island" and world_ and world_:GetTerrainId() == ProjectTerrainId(target.project) then
        ResetGestureState(false)
        world_:ExitFirstPerson()
        SetFirstPersonPointerCapture(false)
        world_:SetOnCommit(nil)
        world_:SetReadOnly(target)
        world_:LoadProjectData(IslandMarket.Copy(target.project), message, { incremental = true })
    else
        OpenIsland(message, false, { visit = target })
    end
    return true
end

local function LeaveVisit()
    if not visitingEntry_ then return false end
    local visitedName = visitingEntry_.name
    local homeIslandId = islandSocial_.visitSession and islandSocial_.visitSession.homeIslandId or nil
    visitingEntry_, islandSocial_.visitSession = nil, nil
    local collection = EnsureIslandCollection(islandProject_)
    islandProject_ = homeIslandId and IslandProjectStore.Get(collection, homeIslandId)
        or IslandProjectStore.GetActive(collection)
    local message = "已结束参观《" .. tostring(visitedName) .. "》· 返回我的空岛"
    if appMode_ == "island" and world_ and islandProject_
        and world_:GetTerrainId() == ProjectTerrainId(islandProject_) then
        ResetGestureState(false)
        world_:ExitFirstPerson()
        SetFirstPersonPointerCapture(false)
        world_:SetReadOnly(false)
        world_:SetOnCommit(function(payload) ScheduleIslandSave(payload) end)
        world_:LoadProjectData(islandProject_, message, { incremental = true })
        world_:SetProjectIdentity(islandProject_.islandId, islandProject_.name)
        RefreshIslandLibrary(libraryTab_)
    else
        OpenIsland(message)
    end
    return true
end

local function ExploreMore()
    if not visitingEntry_ then return false end
    ResetGestureState(false)
    SetFirstPersonPointerCapture(false)
    world_:ExitFirstPerson()
    IslandUI.OpenExplore()
    world_:Notify("请选择下一座空岛 · 当前场景会保留到新岛开始载入")
    return true
end

function islandSocial_:CurrentUserProfile()
    local userId = self.profiles.CurrentUserId()
    local profile = userId and self.profiles.GetCached(userId) or nil
    return userId, profile or {
        nickname = self.profiles.FallbackNickname(userId),
        avatar = self.profiles.BuildAvatar(
            self.profiles.FallbackNickname(userId), "lg"),
    }
end

function islandSocial_:ProfileIslands(ownerId, nickname, avatar)
    local result, positionByIslandId = {}, {}
    for _, entry in ipairs(exploreEntries_ or {}) do
        local islandId = tostring(entry.islandId
            or (type(entry.project) == "table" and entry.project.islandId) or "")
        if tostring(entry.ownerId or "") == tostring(ownerId or "")
            and islandId ~= "" and not positionByIslandId[islandId] then
            local copy = IslandMarket.Copy(entry)
            copy.owner = nickname or copy.owner
            copy.avatar = copy.avatar or IslandMarket.Copy(avatar)
            result[#result + 1] = copy
            positionByIslandId[islandId] = #result
        end
    end
    local currentUserId = self.profiles.CurrentUserId()
    if currentUserId and tostring(ownerId) == currentUserId and islandCollection_ then
        for _, project in ipairs(islandCollection_.items or {}) do
            if project.published == true then
                local islandId = tostring(project.islandId)
                local localEntry = {
                        id = "mine:" .. islandId,
                        islandId = tostring(project.islandId),
                        ownerId = currentUserId,
                        owner = nickname or "云岛旅人",
                        avatar = IslandMarket.Copy(avatar),
                        name = tostring(project.name or "我的空岛"),
                        description = "我的已发布空岛",
                        count = #(project.instances or {}),
                        updatedAt = tonumber(project.updatedAt) or 0,
                        source = "local",
                        isOwn = true,
                    }
                local position = positionByIslandId[islandId]
                if position then result[position] = localEntry
                else
                    result[#result + 1] = localEntry
                    positionByIslandId[islandId] = #result
                end
            end
        end
    end
    table.sort(result, function(first, second)
        local a, b = tonumber(first.updatedAt) or 0, tonumber(second.updatedAt) or 0
        if a ~= b then return a > b end
        return tostring(first.name or "") < tostring(second.name or "")
    end)
    return result
end

function islandSocial_:PublishedModels(ownerId, isMe)
    if not assetStore_ then return {} end
    local result, seen = {}, {}
    local function Append(asset)
        if type(asset) ~= "table" then return end
        local id = tostring(asset.assetId or asset.id or "")
        if id == "" or seen[id] then return end
        seen[id] = true
        result[#result + 1] = {
            id = id,
            assetId = id,
            name = tostring(asset.name or "未命名模型"),
            category = tostring(asset.category or "模型"),
            count = math.max(0, tonumber(asset.stats and asset.stats.blocks or asset.count
                or #(asset.blocks or {})) or 0),
            likes = math.max(0, tonumber(asset.likes or asset.uses or asset.downloads) or 0),
            publishedAt = math.max(0, tonumber(asset.publishedAt or asset.updatedAt) or 0),
            published = true,
        }
    end
    if isMe and assetStore_.GetPublishedProfile then
        local profile = assetStore_:GetPublishedProfile()
        for _, asset in ipairs(profile and profile.items or {}) do Append(asset) end
    else
        for _, asset in ipairs(assetStore_:GetAssets("market") or {}) do
            if tostring(asset.ownerId or "") == tostring(ownerId or "") then Append(asset) end
        end
    end
    table.sort(result, function(first, second)
        if first.publishedAt ~= second.publishedAt then return first.publishedAt > second.publishedAt end
        return first.name < second.name
    end)
    return result
end

function islandSocial_:OpenPlayerProfile(ownerId, nickname)
    ownerId = self.profiles.UserKey(ownerId) or ""
    if ownerId == "" then
        Notify("暂时无法识别这位玩家", "warning")
        return false
    end
    self.profileRequest = self.profileRequest + 1
    local requestId = self.profileRequest
    local cached = self.profiles.GetCached(ownerId)
    local displayName = tostring(nickname or cached.nickname or "云岛旅人")
    local function Present(resolvedProfile, loading)
        if islandSocial_.profileRequest ~= requestId then return end
        local islands = self:ProfileIslands(ownerId,
            resolvedProfile.nickname or displayName, resolvedProfile.avatar)
        local totalModels, totalLikes, latestUpdatedAt = 0, 0, 0
        for _, entry in ipairs(islands) do
            totalModels = totalModels + math.max(0, tonumber(entry.count) or 0)
            totalLikes = totalLikes + math.max(0, tonumber(entry.likes) or 0)
            latestUpdatedAt = math.max(latestUpdatedAt, tonumber(entry.updatedAt) or 0)
        end
        local currentUserId = islandSocial_.profiles.CurrentUserId()
        local isMe = currentUserId ~= nil and ownerId == currentUserId
        local publishedModels = self:PublishedModels(ownerId, isMe)
        local snapshot = {
            ownerId = ownerId,
            userId = ownerId,
            nickname = resolvedProfile.nickname or displayName,
            avatar = resolvedProfile.avatar or islandSocial_.profiles.BuildAvatar(displayName, "lg"),
            isMe = isMe,
            publishedIslands = islands,
            islands = islands,
            publishedCount = #islands,
            totalModels = totalModels,
            totalLikes = totalLikes,
            latestUpdatedAt = latestUpdatedAt,
            publishedModels = publishedModels,
            models = publishedModels,
            publishedModelCount = #publishedModels,
            loading = loading == true,
        }
        if currentUI_ == IslandUI and IslandUI.SetPlayerProfile then
            IslandUI.SetPlayerProfile(snapshot)
        end
    end
    Present({ nickname = displayName, avatar = cached.avatar }, true)
    self.profiles.Resolve({ ownerId }, {
        ok = function(profiles)
            Present(profiles[ownerId] or cached, false)
        end,
    })
    return true
end

function islandSocial_:ResolveGuestbookTarget(ownerId, islandId)
    local currentUserId = self.profiles.CurrentUserId()
    if visitingEntry_ then
        return {
            ownerId = tostring(visitingEntry_.ownerId or ownerId or ""),
            islandId = tostring(visitingEntry_.islandId
                or (visitingEntry_.project and visitingEntry_.project.islandId) or islandId or ""),
            owner = tostring(visitingEntry_.owner or "云岛旅人"),
            nickname = tostring(visitingEntry_.owner or "云岛旅人"),
            avatar = IslandMarket.Copy(visitingEntry_.avatar),
            name = tostring(visitingEntry_.name or "玩家空岛"),
            source = tostring(visitingEntry_.source or "cloud"),
            canPost = visitingEntry_.source == "cloud" and currentUserId ~= nil
                and tostring(visitingEntry_.ownerId or "") ~= currentUserId,
            isOwn = currentUserId ~= nil and tostring(visitingEntry_.ownerId or "") == currentUserId,
        }
    end
    local _, currentProfile = self:CurrentUserProfile()
    local ownerName = currentProfile.nickname or "云岛旅人"
    local ownerAvatar = currentProfile.avatar
    local project = islandProject_ or (islandCollection_ and IslandProjectStore.GetActive(islandCollection_))
    return {
        ownerId = tostring(currentUserId or ownerId or ""),
        islandId = tostring(project and project.islandId or islandId or ""),
        owner = ownerName,
        nickname = ownerName,
        avatar = IslandMarket.Copy(ownerAvatar),
        name = tostring(project and project.name or "我的空岛"),
        source = "mine",
        canPost = false,
        isOwn = true,
    }
end

function islandSocial_:SetGuestbookSnapshot(target, fields)
    local snapshot = {
        ownerId = target.ownerId,
        userId = target.ownerId,
        islandId = target.islandId,
        owner = target.owner,
        nickname = target.nickname or target.owner,
        avatar = IslandMarket.Copy(target.avatar),
        islandName = target.name,
        source = target.source,
        canPost = target.canPost == true,
        isOwn = target.isOwn == true,
        messages = target.messages or {},
        posting = target.posting == true,
    }
    for key, value in pairs(fields or {}) do snapshot[key] = value end
    if currentUI_ == IslandUI and IslandUI.SetGuestbookState then
        IslandUI.SetGuestbookState(snapshot)
    end
end

function islandSocial_:LoadGuestbook(target, initial)
    self.guestbookRequest = self.guestbookRequest + 1
    local requestId = self.guestbookRequest
    local targetKey = self.guestbook.TargetKey(target) or ""
    self.guestbookTarget = target
    local previousMessages = initial or target.messages or {}
    self:SetGuestbookSnapshot(target, { loading = true, messages = previousMessages, feedback = "" })
    return self.guestbook.Load(target, {
        ok = function(messages)
            if islandSocial_.guestbookRequest ~= requestId
                or islandSocial_.guestbook.TargetKey(islandSocial_.guestbookTarget) ~= targetKey then return end
            target.messages = messages
            islandSocial_:SetGuestbookSnapshot(target, {
                loading = false, messages = messages, feedback = "" })
        end,
        error = function(message)
            if islandSocial_.guestbookRequest ~= requestId
                or islandSocial_.guestbook.TargetKey(islandSocial_.guestbookTarget) ~= targetKey then return end
            islandSocial_:SetGuestbookSnapshot(target, { loading = false, messages = previousMessages,
                feedback = tostring(message or "留言板暂时无法读取") })
        end,
    })
end

function islandSocial_:OpenGuestbook(ownerId, islandId)
    local target = self:ResolveGuestbookTarget(ownerId, islandId)
    if target.ownerId == "" or target.islandId == "" then
        self:SetGuestbookSnapshot(target, {
            loading = false, feedback = "留言板暂时无法识别这座空岛" })
        return false
    end
    if self.guestbook.TargetKey(self.guestbookTarget) == self.guestbook.TargetKey(target) then
        target.messages = self.guestbookTarget.messages
    end
    return self:LoadGuestbook(target)
end

function islandSocial_:PostGuestbookMessage(text)
    local target = self.guestbookTarget
    local currentTarget = self:ResolveGuestbookTarget()
    local targetKey = self.guestbook.TargetKey(target)
    if not targetKey or targetKey ~= self.guestbook.TargetKey(currentTarget) then
        return false, "当前空岛已经切换，请重新打开留言板"
    end
    if not target.canPost then return false, "只能在参观已发布空岛时留言" end
    self.guestbookPostRequest = self.guestbookPostRequest + 1
    local requestId = self.guestbookPostRequest
    target.posting = true
    self:SetGuestbookSnapshot(target, {
        loading = false, posting = true, feedback = "正在发送留言……" })
    local started = self.guestbook.Post(target, text, {
        ok = function()
            if islandSocial_.guestbookPostRequest ~= requestId
                or islandSocial_.guestbook.TargetKey(islandSocial_.guestbookTarget) ~= targetKey then return end
            target.posting = false
            Notify("留言已送达", "success")
            islandSocial_:LoadGuestbook(target)
        end,
        error = function(message)
            if islandSocial_.guestbookPostRequest ~= requestId
                or islandSocial_.guestbook.TargetKey(islandSocial_.guestbookTarget) ~= targetKey then return end
            target.posting = false
            islandSocial_:SetGuestbookSnapshot(target, { loading = false, posting = false,
                feedback = tostring(message or "留言发送失败，请稍后重试") })
        end,
    })
    if started == false then return false, "留言发送没有启动，请稍后重试" end
    return true, "正在发送留言……"
end

local function FindIslandInstance(project, id)
    for _, instance in ipairs(project and project.instances or {}) do
        if tonumber(instance.id) == tonumber(id) then return instance end
    end
    return nil
end

local function EnsureEditableAsset(asset)
    if not asset then return nil, "模型不存在" end
    if asset.source == "mine" then return asset end
    return assetStore_:Fork(asset)
end

local function EditAsset(assetId)
    if not RequireWorkspaceReady() then return end
    local source = assetStore_:Get(assetId)
    local asset, errorMessage = EnsureEditableAsset(source)
    if not asset then Notify(errorMessage or "这个模型不能编辑"); return end
    if asset ~= source then ScheduleLibrarySave() end
    OpenWorkbench(asset.assetId, { source = source and source.source or "mine" })
end

local function EditSelectedIslandModel()
    if not RequireWorkspaceReady() then return end
    if appMode_ ~= "island" or not world_ then return end
    local selected = world_:GetSelected()
    if not selected then Notify("请先点击选择岛上的模型"); return end
    local source = assetStore_:Get(selected.assetId, selected.versionId)
    local asset, errorMessage = nil, "模型不存在"
    if source then asset, errorMessage = assetStore_:Fork(source, source.name .. " · 空岛定制") end
    if not asset then Notify(errorMessage or "这个模型不能编辑"); return end
    ScheduleLibrarySave()
    OpenWorkbench(asset.assetId, { returnInstanceId = selected.id, source = source and source.source or "mine" })
end

local function NewModel()
    if not RequireWorkspaceReady() then return end
    local asset = assetStore_:CreateBlank("新模型")
    ScheduleLibrarySave()
    OpenWorkbench(asset.assetId, { isNew = true })
end

local function SaveCurrentAsNewModel(name)
    if not RequireWorkspaceReady() then return end
    if appMode_ ~= "workbench" or not world_ then return end
    local data = world_:GetTemplateData(name)
    if not data then Notify("当前模型为空，无法创建副本"); return end
    local asset = assetStore_:CreateBlank(name)
    data.description = workbenchContext_ and workbenchContext_.description or data.description
    data.attributions = ModelAssetStore.Copy(workbenchContext_ and workbenchContext_.attributions or {})
    assetStore_:SaveDraft(asset.assetId, data)
    ScheduleLibrarySave()
    RefreshWorkbenchLibrary()
    Notify("已保存到“我的模型” · " .. asset.name)
end

local function RenameCurrentModel(name)
    if not workbenchContext_ then return end
    local clean = tostring(name or ""):match("^%s*(.-)%s*$") or ""
    if clean == "" then Notify("模型名称不能为空"); return end
    workbenchContext_.name = clean
    if BuilderUI.SetContext then BuilderUI.SetContext({ name = clean, license = workbenchContext_.license }) end
    PersistWorkbenchDraft(false)
    Notify("模型已改名为《" .. clean .. "》")
end

local function CycleCurrentLicense()
    if not workbenchContext_ then return end
    local current = workbenchContext_.license or "private"
    local nextLicense = current == "private" and "allow_fork" or current == "allow_fork" and "use_only" or "private"
    local asset, errorMessage = assetStore_:SetLicense(workbenchContext_.assetId, nextLicense)
    if not asset then Notify(errorMessage or "无法修改模型许可"); return end
    workbenchContext_.license = asset.license
    if BuilderUI.SetContext then BuilderUI.SetContext({ name = workbenchContext_.name, license = asset.license }) end
    ScheduleLibrarySave()
    Notify("模型许可已改为：" .. tostring(ModelAssetStore.LICENSES[asset.license] or asset.license))
end

local function InsertAsset(assetId)
    local source = assetStore_:Get(assetId)
    if source and source.license == "use_only" then
        Notify("作者只允许整体放入空岛，不能拆入模型工作台")
        return
    end
    local asset, errorMessage = nil, nil
    if source then asset, errorMessage = assetStore_:Flatten(source) end
    if not asset then Notify(errorMessage or "未找到模型"); return end
    assetStore_:MarkUsed(source)
    world_:InsertTemplate(asset)
    if source and source.source == "market" and workbenchContext_ then
        workbenchContext_.attributions = workbenchContext_.attributions or {}
        local exists = false
        for _, item in ipairs(workbenchContext_.attributions) do
            if item.assetId == source.assetId and item.versionId == source.versionId then exists = true; break end
        end
        if not exists then
            workbenchContext_.attributions[#workbenchContext_.attributions + 1] = {
                assetId = source.assetId,
                versionId = source.versionId,
                name = source.name,
                author = source.author,
                license = source.license,
            }
        end
    end
    ScheduleLibrarySave()
end

local function DeleteAsset(assetId)
    if appMode_ == "island" and world_ and world_:IsProjectLoading() then
        world_:Notify("空岛仍在布置中，请稍候再删除模型")
        return false
    end
    if workbenchContext_ and workbenchContext_.assetId == assetId then
        Notify("正在编辑的模型不能删除")
        return
    end
    for _, instance in ipairs(islandProject_ and islandProject_.instances or {}) do
        if instance.assetId == assetId then Notify("这个模型正在空岛中使用，不能删除"); return end
    end
    local deleted, errorMessage = assetStore_:Delete(assetId)
    if deleted then
        ScheduleLibrarySave()
        RefreshActiveLibrary()
        Notify("已删除我的模型")
    else
        Notify(errorMessage or "内置或市场模型不会从源库中删除")
    end
end

local WORKBENCH_JSON_DIRECTORY = "model-json"

local function WorkbenchJsonPath(fileName)
    local name = tostring(fileName or ""):match("^%s*(.-)%s*$") or ""
    name = name:gsub("\\", "/"):match("([^/]+)$") or ""
    name = name:gsub("[^%w%._%-]", "_")
    if name == "" then name = "cloud-model.json" end
    if not name:lower():match("%.json$") then name = name .. ".json" end
    return WORKBENCH_JSON_DIRECTORY .. "/" .. name, name
end

local function ExportWorkbenchFile(fileName)
    local raw = world_ and world_:ExportJSON()
    if not raw then Notify("模型 JSON 导出失败", "error"); return false end
    local path, name = WorkbenchJsonPath(fileName)
    fileSystem:CreateDir(WORKBENCH_JSON_DIRECTORY)
    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then
        Notify("无法创建模型 JSON 文件", "error")
        return false
    end
    file:WriteString(raw)
    file:Close()
    Notify("已导出 " .. name .. " · 保存在项目用户目录", "success")
    print("[WorkbenchJSON] exported: " .. path)
    return true
end

local function ImportWorkbenchFile(fileName)
    local path, name = WorkbenchJsonPath(fileName)
    if not fileSystem:FileExists(path) then
        Notify("未找到 " .. name .. " · 请先放入项目用户目录或导出同名文件", "error")
        return false
    end
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then
        Notify("无法读取模型 JSON 文件", "error")
        return false
    end
    local raw = file:ReadString()
    file:Close()
    local imported = world_:ImportJSON(raw)
    if imported then
        Notify("已从 " .. name .. " 导入模型", "success")
        print("[WorkbenchJSON] imported: " .. path)
    end
    return imported == true
end

local function ExportWorkbench()
    local raw = world_:ExportJSON()
    if not raw then Notify("模型 JSON 导出失败"); return end
    local nativeUI = GetUI()
    nativeUI:SetUseSystemClipboard(true)
    nativeUI:SetClipboardText(raw)
    Notify("模型 JSON 已复制到系统剪贴板 · 可粘贴保存为 .json 文件", "success")
    return true
end

local function ImportWorkbench()
    local nativeUI = GetUI()
    nativeUI:SetUseSystemClipboard(true)
    local raw = nativeUI:GetClipboardText()
    if tostring(raw or ""):match("^%s*$") then
        Notify("系统剪贴板为空 · 请先复制模型 JSON 内容", "error")
        return false
    end
    return world_:ImportJSON(raw) == true
end

local function ChooseReference()
    local nativeUI = GetUI()
    nativeUI:SetUseSystemClipboard(true)
    local path = tostring(nativeUI:GetClipboardText() or ""):match("^%s*(.-)%s*$") or ""
    if path:sub(1, 1) == '"' and path:sub(-1) == '"' then path = path:sub(2, -2) end
    if path ~= "" and (fileSystem:FileExists(path) or cache:Exists(path)) then
        BuilderUI.SetReferencePath(path)
        Notify("已载入参考图片：" .. path)
    else
        Notify("请先复制项目内有效图片路径")
    end
end

local function CreateWorkbenchCallbacks()
    return {
        setViewportRect = function(...) world_:SetViewportRect(...) end,
        setMobileGizmoSuppressed = function(value) world_:SetMobileGizmoSuppressed(value) end,
        consumeScenePointer = function() colorPickPointerGuard_ = true end,
        setMode = function(value) world_:SetMode(value) end,
        focusSelected = function() world_:FocusSelected() end,
        setTransformMode = function(value) world_:SetTransformMode(value) end,
        setPreset = function(value) world_:SetPreset(value) end,
        setShape = function(value) world_:SetShape(value) end,
        setNewSize = function(axis, value) world_:SetNewSize(axis, value) end,
        setNewColor = function(value) world_:SetNewColor(value) end,
        setNewMaterial = function(value) world_:SetNewMaterial(value) end,
        setSelectedMaterial = function(value) world_:SetSelectedMaterial(value) end,
        setSelectedShape = function(value) world_:SetSelectedShape(value) end,
        beginColorPick = function(target) world_:BeginColorPick(target) end,
        previewColorPick = function(...) return world_:GetColorPickPreview(...) end,
        pickSceneColor = function(...)
            colorPickPointerGuard_ = true
            return world_:PickSceneColor(...)
        end,
        cancelColorPick = function()
            colorPickPointerGuard_ = true
            return world_:CancelColorPick()
        end,
        setPaletteColor = function(value) world_:SetPaletteColor(value) end,
        setSnap = function(value) world_:SetSnap(value) end,
        updateInspector = function(key, value) world_:UpdateInspector(key, value) end,
        finishInspectorEdit = function() world_:FinishInspectorEdit() end,
        resetRotation = function() world_:ResetSelectedRotation() end,
        duplicate = function() world_:DuplicateSelected() end,
        deleteSelected = function() world_:DeleteSelected() end,
        selectById = function(id) world_:SelectById(id) end,
        undo = function() world_:Undo() end,
        redo = function() world_:Redo() end,
        save = function()
            if PersistWorkbenchDraft(false, true) then
                OpenIsland("模型已保存并应用到空岛", true)
            end
        end,
        newProject = NewModel,
        loadExample = function() world_:LoadExample(true) end,
        exportProject = ExportWorkbench,
        importProject = ImportWorkbench,
        exportJsonFile = ExportWorkbenchFile,
        importJsonFile = ImportWorkbenchFile,
        saveTemplate = SaveCurrentAsNewModel,
        renameCurrentModel = RenameCurrentModel,
        cycleCurrentLicense = CycleCurrentLicense,
        insertTemplate = InsertAsset,
        deleteTemplate = DeleteAsset,
        chooseReference = ChooseReference,
        setView = function(name) world_:SetView(name) end,
        backToIsland = function()
            if PersistWorkbenchDraft(false, true) then
                OpenIsland("已保存模型并返回空岛", true)
            end
        end,
        publishCurrent = function()
            PersistWorkbenchDraft(false)
            PublishAsset(workbenchContext_.assetId)
        end,
    }
end

local function OpenManagedIsland(islandId, message)
    if not RequireWorkspaceReady() then return false end
    SyncActiveIslandFromWorld()
    local project, errorMessage = IslandProjectStore.SetActive(EnsureIslandCollection(), islandId, Timestamp())
    if not project then Notify(errorMessage or "无法打开空岛"); return false end
    islandProject_ = project
    SaveIsland(false, true)
    OpenIsland(message or ("已打开《" .. project.name .. "》"))
    return true
end

local function CreateManagedIsland(terrainId)
    if not RequireWorkspaceReady() then return false end
    SyncActiveIslandFromWorld()
    local resolvedTerrainId = IslandTerrainCatalog.ResolveId(terrainId)
    islandProject_ = IslandProjectStore.Create(
        EnsureIslandCollection(), nil, Timestamp(), resolvedTerrainId)
    islandProject_.instances = {}
    SaveIsland(false, true)
    local terrainMetadata = IslandProjectStore.GetRandomTerrain(islandCollection_, resolvedTerrainId)
    local terrainSpec = IslandTerrainCatalog.Get(terrainMetadata or resolvedTerrainId)
    OpenIsland("已创建《" .. tostring(terrainSpec.name or "空岛地形") .. "》· 可从模型库开始建设")
    return true
end

local function ApplyTerrainToCurrent(terrainId)
    if not RequireWorkspaceReady() then return false, "工作区仍在恢复，请稍后再试" end
    if visitingEntry_ then return false, "参观别人的空岛时不能修改地形" end
    local resolvedTerrainId = IslandTerrainCatalog.ResolveId(terrainId)
    if world_:GetTerrainId() == resolvedTerrainId then
        Notify("当前已经是这套地形")
        return true
    end
    local supported, invalidCount = world_:CanUseTerrain(resolvedTerrainId)
    if not supported then
        local message = "有 " .. tostring(invalidCount or 0)
            .. " 个模型不适合这套地形，请新建空岛后选择"
        Notify(message)
        return false, message
    end
    SyncActiveIslandFromWorld()
    local project, errorMessage = IslandProjectStore.SetTerrain(
        EnsureIslandCollection(), islandCollection_.activeId, resolvedTerrainId, Timestamp())
    if not project then
        local message = tostring(errorMessage or "地形切换失败，请稍后再试")
        Notify(message)
        return false, message
    end
    islandProject_ = project
    SaveIsland(false, true)
    local terrainMetadata = IslandProjectStore.GetRandomTerrain(islandCollection_, resolvedTerrainId)
    local terrainSpec = IslandTerrainCatalog.Get(terrainMetadata or resolvedTerrainId)
    OpenIsland("已切换为《" .. tostring(terrainSpec.name or "空岛地形") .. "》")
    return true
end

local function CreateRandomTerrain()
    if not RequireWorkspaceReady() or visitingEntry_ then return nil end
    SyncActiveIslandFromWorld()
    local collection = EnsureIslandCollection(islandProject_)
    local record, errorMessage = IslandProjectStore.CreateRandomTerrain(
        collection, nil, nil, Timestamp())
    if not record then Notify(errorMessage or "随机地形生成失败"); return nil end
    SaveIsland(false, true)
    RefreshIslandLibrary(libraryTab_)
    Notify("已生成《" .. tostring(record.name or "随机地形") .. "》")
    return record.id
end

local function RenameRandomTerrain(terrainId, name)
    if not RequireWorkspaceReady() then return false end
    local record, errorMessage = IslandProjectStore.RenameRandomTerrain(
        EnsureIslandCollection(islandProject_), terrainId, name, Timestamp())
    if not record then Notify(errorMessage or "随机地形改名失败"); return false end
    SaveIsland(false, true)
    RefreshIslandLibrary(libraryTab_)
    Notify("随机地形已改名为《" .. tostring(record.name) .. "》")
    return true
end

local function RegenerateRandomTerrain(terrainId)
    if not RequireWorkspaceReady() or visitingEntry_ then return nil end
    SyncActiveIslandFromWorld()
    local collection = EnsureIslandCollection(islandProject_)
    local activeBefore = IslandProjectStore.GetActive(collection)
    local wasActive = activeBefore and ProjectTerrainId(activeBefore) == tostring(terrainId)
    local record, errorMessage = IslandProjectStore.RegenerateRandomTerrain(
        collection, terrainId, nil, Timestamp())
    if not record then Notify(errorMessage or "随机地形重新生成失败"); return nil end
    islandProject_ = IslandProjectStore.GetActive(collection)
    SaveIsland(false, true)
    if wasActive then
        OpenIsland("已重新生成《" .. tostring(record.name or "随机地形") .. "》")
    else
        RefreshIslandLibrary(libraryTab_)
        Notify("《" .. tostring(record.name or "随机地形") .. "》已换成新地貌")
    end
    return record.id
end

local function DeleteRandomTerrain(terrainId)
    if not RequireWorkspaceReady() or visitingEntry_ then return false end
    local deleted, errorMessage = IslandProjectStore.DeleteRandomTerrain(
        EnsureIslandCollection(islandProject_), terrainId, Timestamp())
    if not deleted then Notify(errorMessage or "随机地形删除失败"); return false end
    SaveIsland(false, true)
    RefreshIslandLibrary(libraryTab_)
    Notify("随机地形已删除")
    return true
end

local function SetRewardGateSnapshot(snapshot)
    if currentUI_ == IslandUI and IslandUI.SetRewardGateState then
        IslandUI.SetRewardGateState(snapshot)
    end
end

local function EnsureRewardGate()
    if rewardGate_ then return rewardGate_ end
    rewardGate_ = RewardGate.new({
        delayFrames = 2,
        timeoutSeconds = 150,
        onChanged = SetRewardGateSnapshot,
        showAd = function(done)
            local adSdk = rawget(_G, "sdk")
            if not adSdk or type(adSdk.ShowRewardVideoAd) ~= "function" then
                done({ success = false, msg = "unsupported platform" })
                return true
            end
            return adSdk:ShowRewardVideoAd(function(result) done(result or {}) end)
        end,
    })
    return rewardGate_
end

local function TerrainDisplayName(terrainId)
    local resolved = IslandTerrainCatalog.ResolveId(terrainId)
    local randomTerrains = IslandProjectStore.ListRandomTerrains(
        EnsureIslandCollection(islandProject_))
    for _, summary in ipairs(IslandTerrainCatalog.List(randomTerrains)) do
        if IslandTerrainCatalog.ResolveId(summary) == resolved then
            return tostring(summary.name or "空岛地形")
        end
    end
    return "空岛地形"
end

local function OpenTerrainReward(terrainId, purpose)
    if not RequireWorkspaceReady() or visitingEntry_ then return false end
    local collection = EnsureIslandCollection(islandProject_)
    local resolved = IslandTerrainCatalog.ResolveId(terrainId)
    local key = TerrainRewardKey(resolved)
    if resolved == IslandTerrainCatalog.DEFAULT_ID
        or IslandProjectStore.IsRewardUnlocked(collection, key) then
        RefreshIslandLibrary(libraryTab_)
        return false, "该地形已经解锁"
    end
    return EnsureRewardGate():Open({
        key = key,
        title = "解锁空岛地形",
        description = purpose == "create"
            and "完整观看视频后，将永久解锁这套地形并直接创建新空岛。"
            or "完整观看视频后，这套地形会永久加入你的地形库。",
        subject = (purpose == "create" and "解锁并新建 · " or "待解锁 · ")
            .. TerrainDisplayName(resolved),
        confirmLabel = purpose == "create" and "观看视频并新建" or "观看视频解锁",
        context = { terrainId = resolved, purpose = purpose },
        persistUnlock = function(rewardKey)
            local unlocked, changed = IslandProjectStore.UnlockReward(collection, rewardKey, Timestamp())
            if not unlocked then return false, "解锁记录无效" end
            if changed and not SaveIsland(false, true) then
                collection.rewardUnlocks[rewardKey] = nil
                return false, "解锁记录保存失败"
            end
            return true
        end,
        onGranted = function()
            RefreshIslandLibrary(libraryTab_)
            if purpose == "create" then
                -- The terrain unlock is itself the rewarded action selected in
                -- the new-island flow. Creating immediately avoids asking the
                -- player to watch a second video for the same operation.
                CreateManagedIsland(resolved)
            else
                Notify("已解锁《" .. TerrainDisplayName(resolved) .. "》")
            end
        end,
    })
end

local function OpenNewIslandReward(terrainId)
    if not RequireWorkspaceReady() or visitingEntry_ then return false end
    local resolved = IslandTerrainCatalog.ResolveId(terrainId)
    local collection = EnsureIslandCollection(islandProject_)
    if resolved ~= IslandTerrainCatalog.DEFAULT_ID
        and not IslandProjectStore.IsRewardUnlocked(collection, TerrainRewardKey(resolved)) then
        return OpenTerrainReward(resolved, "create")
    end
    return EnsureRewardGate():Open({
        title = "新增空岛",
        description = "观看一段激励视频，即可获得一次新增空岛机会。",
        subject = "已选地形 · " .. TerrainDisplayName(resolved),
        confirmLabel = "观看视频并新增",
        context = { terrainId = resolved },
        onGranted = function() CreateManagedIsland(resolved) end,
    })
end

local function ConfirmRewardGate()
    return EnsureRewardGate():Confirm()
end

local function CancelRewardGate()
    if not rewardGate_ then return false end
    return rewardGate_:Cancel()
end

local function DuplicateManagedIsland(islandId)
    if not RequireWorkspaceReady() then return false end
    SyncActiveIslandFromWorld()
    local project, errorMessage = IslandProjectStore.Duplicate(EnsureIslandCollection(), islandId, Timestamp())
    if not project then Notify(errorMessage or "复制空岛失败"); return false end
    islandProject_ = project
    SaveIsland(false, true)
    OpenIsland("已复制并打开《" .. project.name .. "》")
    return true
end

local function RenameManagedIsland(islandId, name)
    if not RequireWorkspaceReady() then return false end
    SyncActiveIslandFromWorld()
    local project, errorMessage = IslandProjectStore.Rename(EnsureIslandCollection(), islandId, name, Timestamp())
    if not project then Notify(errorMessage or "空岛改名失败"); return false end
    if islandCollection_.activeId == project.islandId then
        islandProject_ = project
        world_:SetProjectIdentity(project.islandId, project.name)
    end
    world_:SetIslandDirectory(IslandProjectStore.Summaries(islandCollection_), islandCollection_.activeId)
    if project.published == true then islandMarketSyncState_:QueueMarketSync(project.islandId) end
    SaveIsland(false, true)
    Notify("空岛已改名为《" .. project.name .. "》")
    return true
end

local function DeleteManagedIsland(islandId)
    if not RequireWorkspaceReady() then return false end
    SyncActiveIslandFromWorld()
    local deletingActive = islandCollection_.activeId == tostring(islandId)
    local deletedProject = IslandProjectStore.Get(islandCollection_, islandId)
    local publicGraphMayChange = deletedProject and deletedProject.published == true or false
    if not publicGraphMayChange and deletedProject then
        for _, instance in ipairs(deletedProject.instances or {}) do
            local binding = IslandPortalNetwork.NormalizeBinding(instance.portal)
            local peer = binding and IslandProjectStore.Get(islandCollection_, binding.targetIslandId) or nil
            if peer and peer.published == true then publicGraphMayChange = true; break end
        end
    end
    local project, errorMessage = IslandProjectStore.Delete(EnsureIslandCollection(), islandId, Timestamp())
    if not project then Notify(errorMessage or "删除空岛失败"); return false end
    islandProject_ = project
    if publicGraphMayChange then islandMarketSyncState_:QueueMarketSync(project.islandId) end
    SaveIsland(false, true)
    if deletingActive then OpenIsland("已删除空岛，并打开《" .. project.name .. "》")
    else
        -- Deleting another island can also remove this island's paired portal.
        -- Reload the active project so a stale live endpoint cannot be written
        -- back into the collection on the next save.
        world_:LoadProjectData(project, "已删除空岛", { incremental = true })
        world_:SetProjectIdentity(project.islandId, project.name)
        world_:SetIslandDirectory(IslandProjectStore.Summaries(islandCollection_), islandCollection_.activeId)
    end
    return true
end

local function ClearCurrentIsland()
    if not RequireWorkspaceReady() or visitingEntry_ or appMode_ ~= "island" or not world_ then
        return false
    end
    if world_:IsProjectLoading() then
        world_:Notify("空岛仍在布置中，请稍候再重做")
        return false
    end
    SyncActiveIslandFromWorld()
    local collection = EnsureIslandCollection(islandProject_)
    local project = IslandProjectStore.GetActive(collection)
    if not project then Notify("当前空岛不存在"); return false end

    -- A reset is collection-wide when paired portals are involved: remove
    -- every reciprocal endpoint before clearing the remaining local models.
    local portalIds = {}
    for _, instance in ipairs(project.instances or {}) do
        if instance.assetId == PortalTemplate.ASSET_ID or type(instance.portal) == "table" then
            portalIds[#portalIds + 1] = instance.id
        end
    end
    local now = Timestamp()
    local publishedPeerChanged = false
    for _, instanceId in ipairs(portalIds) do
        local deleted, result = IslandPortalNetwork.DeleteEndpoint(collection, project.islandId,
            instanceId, now, { touchCollection = false })
        if deleted and type(result) == "table" and result.targetProject
            and result.targetProject.published == true then
            publishedPeerChanged = true
        end
    end
    project.instances = {}
    project.revision = math.max(0, tonumber(project.revision) or 0) + 1
    project.updatedAt = now
    collection.revision = math.max(0, tonumber(collection.revision) or 0) + 1
    collection.updatedAt = now
    if project.published == true or publishedPeerChanged then
        islandMarketSyncState_:QueueMarketSync(project.islandId)
    end

    islandProject_ = project
    world_:LoadProjectData(project, "当前空岛已清空 · 可以重新建设")
    world_:CheckpointExternalMutation()
    world_:SetIslandDirectory(IslandProjectStore.Summaries(collection), collection.activeId)
    pendingIslandSave_, saveElapsed_ = collection, 0
    SaveIsland(false, true)
    return true
end

local function CreateIslandCallbacks()
    return {
        setPaused = function(paused) return SetPresentationPaused(paused, true) end,
        setViewportRect = function(...) world_:SetViewportRect(...) end,
        consumeScenePointer = function() colorPickPointerGuard_ = true end,
        setLibraryTab = function(tab) RefreshIslandLibrary(tab) end,
        placeAsset = function(assetId, versionId)
            if not RequireWorkspaceReady() then return false end
            local started = world_:StartPlacement(assetId, versionId)
            if started then
                ScheduleLibrarySave()
            end
            return started == true
        end,
        toggleFavorite = ToggleFavorite,
        refreshMarket = function() if RequireWorkspaceReady() then RefreshMarket(true) end end,
        publishAsset = PublishAsset,
        unpublishAsset = UnpublishAsset,
        deleteAsset = DeleteAsset,
        editAsset = EditAsset,
        newModel = NewModel,
        editSelected = EditSelectedIslandModel,
        setTransformMode = function(mode) if RequireWorkspaceReady() then world_:SetTransformMode(mode) end end,
        transformSelected = function(kind, amount)
            if RequireWorkspaceReady() then
                world_:TransformSelected(kind, amount)
            end
        end,
        rotatePlacement = function(amount)
            if RequireWorkspaceReady() then
                world_:RotatePlacement(amount)
            end
        end,
        scalePlacement = function(amount)
            if RequireWorkspaceReady() then
                world_:ScalePlacement(amount)
            end
        end,
        confirmPlacement = function()
            if RequireWorkspaceReady() then
                return world_:PlaceCurrent()
            end
        end,
        cancelPlacement = function() world_:CancelPlacement() end,
        duplicate = function() if RequireWorkspaceReady() then world_:DuplicateSelected() end end,
        deleteSelected = function() if RequireWorkspaceReady() then return DeleteSelectedIslandInstance() end end,
        bindPortal = BindPortalToIsland,
        enterPortal = function() return world_:ActivateSelectedPortal() end,
        clearSelection = function() world_:Select(nil) end,
        undo = function() if RequireWorkspaceReady() then world_:Undo() end end,
        redo = function() if RequireWorkspaceReady() then world_:Redo() end end,
        clearIsland = ClearCurrentIsland,
        save = function()
            if not RequireWorkspaceReady() then return end
            if world_:IsProjectLoading() then
                world_:Notify("空岛仍在布置中，完成后会自动保存")
                return
            end
            SyncActiveIslandFromWorld()
            SaveIsland(true)
        end,
        newIsland = CreateManagedIsland,
        applyTerrain = ApplyTerrainToCurrent,
        createRandomTerrain = CreateRandomTerrain,
        renameRandomTerrain = RenameRandomTerrain,
        regenerateRandomTerrain = RegenerateRandomTerrain,
        deleteRandomTerrain = DeleteRandomTerrain,
        autoBuildIsland = AutoBuildIsland,
        terrainDiscoveryEligibility = function()
            if not storageReady_ then return nil end
            return not IslandProjectStore.IsUIDismissed(
                EnsureIslandCollection(islandProject_), TERRAIN_DISCOVERY_DISMISSAL_KEY)
        end,
        dismissTerrainDiscovery = function(doNotRemind)
            if doNotRemind ~= true or not storageReady_ then return true end
            local dismissed, changed = IslandProjectStore.DismissUI(
                EnsureIslandCollection(islandProject_),
                TERRAIN_DISCOVERY_DISMISSAL_KEY, Timestamp())
            if dismissed and changed then SaveIsland(false, true) end
            return dismissed == true
        end,
        openTerrainReward = OpenTerrainReward,
        openNewIslandReward = OpenNewIslandReward,
        confirmRewardGate = ConfirmRewardGate,
        cancelRewardGate = CancelRewardGate,
        openIsland = OpenManagedIsland,
        duplicateIsland = DuplicateManagedIsland,
        renameIsland = RenameManagedIsland,
        deleteIsland = DeleteManagedIsland,
        setIslandPublished = SetIslandPublished,
        refreshExplore = function() RefreshIslandMarket(true) end,
        toggleExploreFavorite = ToggleExploreFavorite,
        toggleExploreLike = ToggleExploreLike,
        visitIsland = VisitIsland,
        leaveVisit = LeaveVisit,
        exploreMore = ExploreMore,
        openPlayerProfile = function(ownerId, nickname)
            return islandSocial_:OpenPlayerProfile(ownerId, nickname)
        end,
        openGuestbook = function(ownerId, islandId)
            return islandSocial_:OpenGuestbook(ownerId, islandId)
        end,
        refreshGuestbook = function(ownerId, islandId)
            return islandSocial_:OpenGuestbook(ownerId, islandId)
        end,
        postGuestbookMessage = function(text)
            return islandSocial_:PostGuestbookMessage(text)
        end,
        enterFirstPerson = function()
            if world_:IsProjectLoading() then
                world_:Notify("空岛仍在布置中，请稍候进入漫游")
                return false
            end
            ResetGestureState(true)
            if world_:EnterFirstPerson() then
                SetFirstPersonPointerCapture(true)
                return true
            end
            return false
        end,
        exitFirstPerson = function()
            ResetGestureState(false)
            world_:ExitFirstPerson()
            SetFirstPersonPointerCapture(false)
        end,
        toggleFirstPersonRun = function() world_:ToggleFirstPersonRun() end,
        toggleFirstPersonFlying = function() world_:ToggleFirstPersonFlying() end,
        setFirstPersonFlightVertical = function(value) world_:SetFirstPersonFlightVertical(value) end,
        setTimeOfDay = function(value, persist) world_:SetTimeOfDay(value, persist) end,
        commitTimeOfDay = function() world_:CommitTimeSettings() end,
        setTimeAuto = function(value) world_:SetTimeAuto(value) end,
        jumpFirstPerson = function() world_:JumpFirstPerson() end,
        nudgeFirstPersonFlight = function(direction) world_:NudgeFirstPersonFlight(direction) end,
        setView = function(name) world_:SetView(name) end,
    }
end

OpenIsland = function(message, workbenchAlreadyPersisted, options)
    options = options or {}
    ResetPresentationPause()
    local returningFromWorkbench = appMode_ == "workbench"
    local visitEntry = options.visit
    visitingEntry_ = visitEntry or nil
    local returnInstanceId = workbenchContext_ and workbenchContext_.returnInstanceId or nil
    if appMode_ == "workbench" and world_ and not workbenchAlreadyPersisted then PersistWorkbenchDraft(false) end
    if appMode_ == "workbench" then ApplyWorkbenchDraftToIslandInstance() end
    local sourceProject = visitEntry and visitEntry.project or islandProject_

    -- Portal travel between islands using the same terrain can reuse the whole
    -- native scene, renderer, environment and UI. Only model instances change.
    -- This turns the common A <-> B round trip from a full world reconstruction
    -- into the existing incremental project restore path.
    local reusePortalWorld = options.portalTransition == true
        and not returningFromWorkbench
        and appMode_ == "island" and world_ and currentUI_ == IslandUI
        and sourceProject and world_:GetTerrainId() == ProjectTerrainId(sourceProject)
    if reusePortalWorld then
        ResetGestureState(false)
        workbenchContext_ = nil
        world_:SetProjectIdentity(sourceProject.islandId, sourceProject.name)
        local loaded = world_:LoadProjectData(visitEntry and IslandMarket.Copy(sourceProject)
            or sourceProject, message, {
            incremental = true,
            priorityInstanceId = options.priorityInstanceId,
            priorityRadius = options.priorityRadius,
        })
        if not loaded then return false end
        if visitEntry then
            world_:SetOnCommit(nil)
            world_:SetReadOnly(visitEntry)
            if message then world_:Notify(message) end
            return true
        end
        world_:SetReadOnly(false)
        islandProject_ = world_:GetProjectData()
        if islandCollection_ then
            islandProject_.islandId = islandCollection_.activeId
            islandProject_ = IslandProjectStore.Put(
                islandCollection_, islandProject_, Timestamp()) or islandProject_
            world_:SetIslandDirectory(
                IslandProjectStore.Summaries(islandCollection_), islandCollection_.activeId)
        end
        if message then world_:Notify(message) end
        return true
    end

    CloseCurrentSurface()
    appMode_ = "island"
    workbenchContext_ = nil
    world_ = IslandWorld.new(assetStore_, ProjectTerrainId(sourceProject))
    runtimeThermal_:SetMobile(world_.mobileDevice == true)
    currentUI_ = IslandUI
    IslandUI.Init(CreateIslandCallbacks())
    world_:SetOnChanged(HandleIslandWorldChanged)
    if islandMarketSyncState_.request then
        world_:SetIslandMarketSyncState(true, islandMarketSyncState_.request.islandId)
    end
    if options.portalTransition == true and portalTransition_:IsActive() then
        -- A different terrain reconstructs IslandUI during OpenIsland. Restore
        -- the loading root immediately so no interactive frame leaks through.
        IslandUI.ShowBootstrap()
    end
    if not visitEntry then world_:SetOnCommit(function(payload) ScheduleIslandSave(payload) end) end
    if visitEntry then
        if not world_:LoadProjectData(IslandMarket.Copy(visitEntry.project), message, {
            incremental = options.incremental ~= false,
            priorityInstanceId = options.priorityInstanceId,
            priorityRadius = options.priorityRadius,
        }) then world_:LoadDefault() end
        world_:SetReadOnly(visitEntry)
        if message then world_:Notify(message) end
        return true
    end
    if islandProject_ then world_:SetProjectIdentity(islandProject_.islandId, islandProject_.name) end
    if islandProject_ and not world_:LoadProjectData(islandProject_, message, {
        incremental = options.incremental ~= false,
        priorityInstanceId = options.priorityInstanceId,
        priorityRadius = options.priorityRadius,
    }) then
        islandProject_ = nil
        world_:LoadDefault()
    elseif not islandProject_ then
        world_:LoadDefault()
    end
    islandProject_ = world_:GetProjectData()
    if islandCollection_ then
        islandProject_.islandId = islandCollection_.activeId
        islandProject_ = IslandProjectStore.Put(islandCollection_, islandProject_, Timestamp()) or islandProject_
    end
    RefreshIslandLibrary(libraryTab_)
    if returnInstanceId then world_:SelectById(returnInstanceId) end
    if message then world_:Notify(message) end
    return true
end

OpenWorkbench = function(assetId, options)
    options = options or {}
    ResetPresentationPause()
    if appMode_ == "island" and world_ then SyncActiveIslandFromWorld() end
    if appMode_ == "workbench" and world_ then PersistWorkbenchDraft(false) end
    local asset = assetStore_:Get(assetId)
    local renderable, errorMessage = nil, nil
    if asset then renderable, errorMessage = assetStore_:Flatten(asset) end
    if not asset or not renderable then Notify(errorMessage or "模型不存在"); return end
    CloseCurrentSurface()
    appMode_ = "workbench"
    workbenchContext_ = {
        assetId = asset.assetId,
        name = asset.name,
        description = asset.description,
        license = asset.license,
        attributions = ModelAssetStore.Copy(asset.attributions or {}),
        returnInstanceId = options.returnInstanceId,
        source = options.source or asset.source,
        isNew = options.isNew == true,
    }
    world_ = BuilderWorld.new()
    runtimeThermal_:SetMobile(world_.mobileDevice == true)
    currentUI_ = BuilderUI
    BuilderUI.Init(CreateWorkbenchCallbacks())
    if BuilderUI.SetContext then BuilderUI.SetContext({ name = asset.name, license = asset.license }) end
    world_:SetOnChanged(function(state, status) BuilderUI.Refresh(state, status) end)
    world_:SetOnCommit(function() ScheduleWorkbenchSave() end)
    RefreshWorkbenchLibrary()
    if #renderable.blocks > 0 then
        world_:LoadProjectData({ blocks = renderable.blocks }, "模型工作台 · " .. asset.name)
    else
        world_:NewProject()
        world_:Notify("空白模型已创建 · 从基础形状、内置模型或模型市场开始")
    end
    world_:SetView("iso", true)
end

local function GraphicsDeviceIsLost()
    if not graphics or not graphics.IsDeviceLost then return false end
    local ok, lost = pcall(function() return graphics:IsDeviceLost() end)
    return ok and lost == true
end

local function GraphicsMetric(method)
    if not graphics or type(graphics[method]) ~= "function" then return -1 end
    local ok, value = pcall(function() return graphics[method](graphics) end)
    return ok and tonumber(value) or -1
end

local function LogGraphicsRecovery(stage, detail)
    if not log or not log.Write then return end
    log:Write(LOG_WARNING, string.format(
        "Island graphics %s: %dx%d dpr=%.2f batches=%d primitives=%d%s",
        tostring(stage), graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR(),
        GraphicsMetric("GetNumBatches"), GraphicsMetric("GetNumPrimitives"),
        detail and (" " .. tostring(detail)) or ""))
end

local function HandleDeviceLost()
    if graphicsDeviceLost_ then return end
    graphicsDeviceLost_ = true
    graphicsRecoveryFrames_ = 0
    ResetGestureState(false)
    local detail = world_ and string.format("models=%d blocks=%d renderParts=%d shadowBlocks=%d",
        #(world_.instances or {}), tonumber(world_.modelRenderBlockCount) or 0,
        tonumber(world_.modelRenderBatchCount) or 0,
        tonumber(world_.modelShadowBlockCount) or 0) or nil
    LogGraphicsRecovery("device-lost", detail)
end

local function HandleDeviceReset()
    if not graphicsDeviceLost_ and graphicsRecoveryFrames_ > 0 then return end
    graphicsDeviceLost_ = false
    -- Let the swap chain settle before recreating native scene, renderer and
    -- NanoVG resources. Rebuilding immediately inside DeviceReset can retain
    -- the invalid surface stride that produced the tiled blue frame.
    graphicsRecoveryFrames_ = 3
    LogGraphicsRecovery("device-reset")
end

local function RecoverGraphicsSurface()
    graphicsRecoveryCount_ = graphicsRecoveryCount_ + 1
    local ok, errorMessage = pcall(function()
        if appMode_ == "workbench" then
            local context = workbenchContext_ and ModelAssetStore.Copy(workbenchContext_) or nil
            if not context then return end
            PersistWorkbenchDraft(false, true)
            OpenWorkbench(context.assetId, context)
            world_:Notify("图形资源已恢复 · 模型内容未丢失")
        else
            local visit = visitingEntry_
            if not visit then SyncActiveIslandFromWorld() end
            OpenIsland("图形资源已恢复 · 空岛内容未丢失", true, {
                visit = visit,
                incremental = true,
            })
        end
        screenWidth_, screenHeight_, screenDpr_ =
            graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
        screenRebuildFrames_ = 2
    end)
    if not ok then
        LogGraphicsRecovery("rebuild-failed", errorMessage)
        graphicsRecoveryFrames_ = 30
        return false
    end
    LogGraphicsRecovery("rebuilt", "count=" .. tostring(graphicsRecoveryCount_))
    return true
end

local function LoadStartupContent()
    -- Rich offline showcase islands are intentionally generated on the first
    -- Explore refresh (or as a cloud fallback), not during app startup. Even
    -- after spatial-index optimisation they are unnecessary work before the
    -- player's own island and text UI become interactive.
    BuilderStorage.LoadWorkspace(function(payload)
        if not assetStore_ then return end
        local migrated = WorkspaceMigration.Apply(assetStore_, payload)
        storageReady_ = true
        cloudLoadFailed_ = payload and payload.error ~= nil or false
        local fallback = appMode_ == "island" and world_:GetProjectData() or islandProject_
        islandCollection_ = IslandProjectStore.Normalize(payload and payload.island, fallback, Timestamp())
        islandProject_ = IslandProjectStore.GetActive(islandCollection_)
        SetExploreEntries(exploreEntries_, false, exploreSource_)
        if appMode_ == "island" then
            if islandProject_ then
                local restoreMessage = payload.islandSource == "cloud"
                    and "已从云端恢复空岛" or "已从本地恢复空岛"
                if world_:GetTerrainId() ~= ProjectTerrainId(islandProject_) then
                    OpenIsland(restoreMessage, true)
                else
                    world_:LoadProjectData(islandProject_, restoreMessage, { incremental = true })
                end
            end
            RefreshIslandLibrary(libraryTab_)
        else
            RefreshWorkbenchLibrary()
        end
        if migrated then
            SaveModelLibrary(false)
            Notify("旧工作台工程已迁移到“我的模型”")
        elseif payload and payload.error then
            Notify(payload.error .. " · 已使用本地工作区")
        end
        if not payload or not payload.island or payload.island.schema ~= IslandProjectStore.SCHEMA then
            if appMode_ == "island" then SyncActiveIslandFromWorld() end
            SaveIsland(false)
        end
        local currentUserId = islandSocial_.profiles.CurrentUserId()
        if currentUserId then
            islandSocial_.profiles.Resolve({ currentUserId }, {
                ok = function(profiles)
                    islandSocial_.currentProfile = profiles[currentUserId]
                        or islandSocial_.profiles.GetCached(currentUserId)
                    if appMode_ == "island" and world_ then world_:RefreshState() end
                end,
            })
        end
        RefreshMarket(false)
        if assetStore_:HasPendingMarketSync() then SyncMarketProfile(false) end
        if islandCollection_.marketSyncPending then SyncIslandMarketProfile(false) end
    end)
end

local function SetupApplication()
    assetStore_ = ModelAssetStore.new(BuiltinTemplates.BuildAll())
    islandSocial_:RefreshCurrentUserProfile()
    OpenIsland()
    IslandUI.SetExploreState({}, true, "sample")
    world_:Notify("正在恢复空岛、我的模型与市场收藏……")
    -- Let the actual island UI render before local/cloud workspace restoration
    -- starts creating the player's saved models.
    startupContentFrames_ = 2
end

local function HandleMouseDown(eventType, eventData)
    runtimeThermal_:NoteInteraction()
    if IsPresentationPaused() then return end
    if colorPickPointerGuard_ then colorPickPointerGuard_ = false; return end
    if portalTransition_:IsActive() or touchCount_ > 0 or mouseDown_ or not world_ then return end
    local button = eventData:GetInt("Button")
    if button ~= MOUSEB_LEFT and button ~= MOUSEB_RIGHT and button ~= MOUSEB_MIDDLE then return end
    local x, y = eventData:GetInt("X"), eventData:GetInt("Y")
    if IsPointOverUI(x, y) or not world_:IsInViewport(x, y) then return end
    if CallWorld("IsFirstPerson") then
        mouseDown_, mouseButton_ = true, button
        mouseStartX_, mouseStartY_, mouseLastX_, mouseLastY_ = x, y, x, y
        mouseDragged_, mouseTransform_, mouseNavigation_ = false, false, "firstperson"
        return
    end
    if button == MOUSEB_LEFT and CallWorld("IsColorPicking") then CallWorld("PickSceneColor", x, y); return end
    CallWorld("StopCameraMotion")
    mouseDown_, mouseButton_ = true, button
    mouseStartX_, mouseStartY_, mouseLastX_, mouseLastY_ = x, y, x, y
    mouseDragged_, mouseTransform_ = false, false
    local modified = NavigationModifierDown()
    if button == MOUSEB_MIDDLE then mouseNavigation_ = "zoom"
    elseif button == MOUSEB_LEFT then mouseNavigation_ = modified and "pan" or "orbit"
    else mouseNavigation_ = modified and "orbit" or "pan" end
    if button == MOUSEB_LEFT and storageReady_ then mouseTransform_ = CallWorld("BeginTransformDrag", x, y, false) == true end
end

local function HandleMouseMove(eventType, eventData)
    runtimeThermal_:NoteInteraction()
    if IsPresentationPaused() then return end
    if portalTransition_:IsActive() or touchCount_ > 0 or not world_ then return end
    local x, y = eventData:GetInt("X"), eventData:GetInt("Y")
    if not mouseDown_ then
        if CallWorld("IsFirstPerson") then return end
        if CallWorld("IsColorPicking") then CallWorld("ClearTransformHover"); return end
        if world_:IsInViewport(x, y) and not IsPointOverUI(x, y) then CallWorld("HoverTransform", x, y)
        else CallWorld("ClearTransformHover") end
        return
    end
    local dx, dy = x - mouseLastX_, y - mouseLastY_
    if mouseNavigation_ == "firstperson" then
        CallWorld("LookFirstPerson", dx, dy, false)
        mouseDragged_ = mouseDragged_ or math.abs(dx) + math.abs(dy) > 0
        mouseLastX_, mouseLastY_ = x, y
        return
    end
    if Distance(mouseStartX_, mouseStartY_, x, y) > (CallWorld("PointerDragThreshold", false) or 4) then mouseDragged_ = true end
    if mouseTransform_ then CallWorld("DragTransform", x, y)
    elseif mouseDragged_ then
        if mouseNavigation_ == "orbit" then CallWorld("OrbitByPixels", dx, dy)
        elseif mouseNavigation_ == "zoom" then
            local scale = math.max(0.01, tonumber(world_.uiScale) or 1)
            CallWorld("Zoom", 0.95 ^ (-(dy / scale) * 0.01))
        else
            -- Desktop mouse/trackpad panning uses the same direct screen-space
            -- direction as the already-correct phone two-finger midpoint.
            CallWorld("PanByPixels", dx, dy)
        end
    end
    mouseLastX_, mouseLastY_ = x, y
end

local function HandleMouseUp(eventType, eventData)
    runtimeThermal_:NoteInteraction()
    if IsPresentationPaused() then return end
    if portalTransition_:IsActive() or touchCount_ > 0 or not world_ then return end
    local button = eventData:GetInt("Button")
    if not mouseDown_ or button ~= mouseButton_ then return end
    if mouseNavigation_ == "firstperson" then
        mouseDown_, mouseButton_, mouseDragged_, mouseTransform_, mouseNavigation_ = false, nil, false, false, nil
        return
    elseif mouseTransform_ then CallWorld("EndTransformDrag")
    elseif button == MOUSEB_LEFT and not mouseDragged_ then
        local x, y = eventData:GetInt("X"), eventData:GetInt("Y")
        if world_:IsInViewport(x, y) and not IsPointOverUI(x, y) then world_:Tap(x, y) end
    end
    mouseDown_, mouseButton_, mouseDragged_, mouseTransform_, mouseNavigation_ = false, nil, false, false, nil
end

local function HandleMouseWheel(eventType, eventData)
    runtimeThermal_:NoteInteraction()
    if IsPresentationPaused() then return end
    if portalTransition_:IsActive() or not world_ or CallWorld("IsColorPicking") then return end
    if CallWorld("IsFirstPerson") then return end
    local position = input.mousePosition
    if IsPointOverUI(position.x, position.y) or not world_:IsInViewport(position.x, position.y) then return end
    local wheel = eventData:GetInt("Wheel")
    local step = appMode_ == "workbench" and 0.92 or 0.95
    if wheel > 0 then world_:Zoom(step) elseif wheel < 0 then world_:Zoom(1 / step) end
end

local function TouchPoints()
    local points = {}
    for _, touch in pairs(touches_) do points[#points + 1] = touch end
    table.sort(points, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return points
end

local function HandleTouchBegin(eventType, eventData)
    runtimeThermal_:NoteInteraction()
    if IsPresentationPaused() then return end
    if colorPickPointerGuard_ then colorPickPointerGuard_ = false; return end
    if portalTransition_:IsActive() or mouseDown_ or not world_ then return end
    local id = eventData:GetInt("TouchID")
    local fixedGestureCandidate = false
    if transformTouchId_ ~= nil and id ~= transformTouchId_ then fixedGestureCandidate = CallWorld("IsFixedTransformDrag") == true
    elseif transformTouchId_ == nil and touchCount_ == 1 then
        for _, existing in pairs(touches_) do if existing.fixedGizmoArea then fixedGestureCandidate = true; break end end
    end
    if transformTouchId_ ~= nil and id ~= transformTouchId_ and not fixedGestureCandidate then
        CallWorld("CancelTransformDrag")
        transformTouchId_ = nil
    end
    local rawX, rawY = eventData:GetInt("X"), eventData:GetInt("Y")
    local x, y = ResolveTouchPoint(rawX, rawY, id)
    if IsPointOverUI(x, y) or not world_:IsInViewport(x, y) then return end
    if CallWorld("IsFirstPerson") then
        if touchCount_ >= 2 and not touches_[id] then return end
        if not touches_[id] then touchCount_ = touchCount_ + 1 end
        local midpoint = (world_.viewportRect.left + world_.viewportRect.right) * 0.5
        local role = x < midpoint and "move" or "look"
        if role == "move" and firstPersonMoveTouchId_ ~= nil then role = "look" end
        if role == "look" and firstPersonLookTouchId_ ~= nil then role = "move" end
        if role == "move" then firstPersonMoveTouchId_ = id else firstPersonLookTouchId_ = id end
        touches_[id] = {
            id = id, role = role, x = x, y = y, lastX = x, lastY = y,
            startX = x, startY = y, dragged = false,
        }
        if role == "move" then CallWorld("SetFirstPersonJoystickVisual", x, y, true) end
        return
    end
    if CallWorld("IsColorPicking") then CallWorld("PickSceneColor", x, y); return end
    if touchCount_ >= 2 and not touches_[id] then return end
    if not touches_[id] then touchCount_ = touchCount_ + 1 end
    touches_[id] = {
        id = id, x = x, y = y, lastX = x, lastY = y, startX = x, startY = y,
        dragged = false,
    }
    touches_[id].fixedGizmoArea = CallWorld("IsInMobileGizmoGestureArea", x, y) == true
    if touchCount_ == 1 then
        CallWorld("StopCameraMotion")
        if storageReady_ and CallWorld("BeginTransformDrag", x, y, true) then
            transformTouchId_ = id
            touches_[id].fixedGizmo = CallWorld("IsFixedTransformDrag") == true
        else
            touches_[id].gestureWaiting = touches_[id].fixedGizmoArea
            touches_[id].sceneTapPending = not touches_[id].fixedGizmoArea
        end
    end
    if touchCount_ == 2 then
        -- TouchMove events arrive per finger. Snapshot both live positions so
        -- midpoint and pinch calculations never mix this frame with the other
        -- finger's previous frame.
        SyncTrackedTouchPoints()
        local points = TouchPoints()
        local began = fixedGestureCandidate and #points >= 2
            and CallWorld("BeginMobileTransformGesture", points[1].x, points[1].y, points[2].x, points[2].y)
        if began then
            mobileTransformGesture_, transformTouchId_ = true, nil
            pinchDistance_, pinchMidX_, pinchMidY_ = nil, nil, nil
        else
            pinchDistance_ = Distance(points[1].x, points[1].y, points[2].x, points[2].y)
            pinchMidX_, pinchMidY_ = (points[1].x + points[2].x) * 0.5, (points[1].y + points[2].y) * 0.5
        end
        points[1].dragged, points[2].dragged = true, true
        points[1].sceneTapPending, points[2].sceneTapPending = false, false
    end
end

local function HandleTouchMove(eventType, eventData)
    runtimeThermal_:NoteInteraction()
    if IsPresentationPaused() then return end
    if portalTransition_:IsActive() then return end
    local id = eventData:GetInt("TouchID")
    local touch = touches_[id]
    if not touch or not world_ then return end
    local x, y = ResolveTouchPoint(eventData:GetInt("X"), eventData:GetInt("Y"), id)
    local dx, dy = x - touch.lastX, y - touch.lastY
    touch.x, touch.y = x, y
    if CallWorld("IsFirstPerson") then
        if touch.role == "move" then
            local radius = 72 * math.max(1, tonumber(world_.uiScale) or 1)
            local right = math.max(-1, math.min(1, (x - touch.startX) / radius))
            local forward = math.max(-1, math.min(1, -(y - touch.startY) / radius))
            local length = math.sqrt(right * right + forward * forward)
            if length > 1 then right, forward = right / length, forward / length end
            CallWorld("SetFirstPersonMovement", forward, right, CallWorld("IsFirstPersonRunEnabled") == true)
        else
            CallWorld("LookFirstPerson", dx, dy, true)
        end
        touch.lastX, touch.lastY = x, y
        return
    end
    if not ViewportCoordinates.IsTapMovement(touch.startX, touch.startY, x, y,
        CallWorld("PointerDragThreshold", true) or 9) then touch.dragged = true end
    SyncTrackedTouchPoints()
    if mobileTransformGesture_ and touchCount_ >= 2 then
        local points = TouchPoints()
        if #points >= 2 then CallWorld("DragMobileTransformGesture", points[1].x, points[1].y, points[2].x, points[2].y) end
    elseif transformTouchId_ == id then CallWorld("DragTransform", x, y)
    elseif touchCount_ >= 2 then
        local points = TouchPoints()
        if #points >= 2 then
            local distance = Distance(points[1].x, points[1].y, points[2].x, points[2].y)
            local midX, midY = (points[1].x + points[2].x) * 0.5, (points[1].y + points[2].y) * 0.5
            if pinchDistance_ and distance > 4 then
                local factor = pinchDistance_ / distance
                CallWorld("ZoomByGesture", factor)
            end
            if pinchMidX_ then
                -- Direct manipulation: moving both fingers right/down moves
                -- the visible model right/down. BuilderWorld converts this
                -- screen delta into its camera-right/camera-up basis.
                local panDx, panDy = midX - pinchMidX_, midY - pinchMidY_
                CallWorld("PanByPixels", panDx, panDy, true)
            end
            pinchDistance_, pinchMidX_, pinchMidY_ = distance, midX, midY
        end
    elseif not touch.gestureWaiting and not touch.gestureConsumed and touch.dragged then
        CallWorld("OrbitByPixels", dx, dy, true)
    end
    touch.lastX, touch.lastY = x, y
end

local function HandleTouchEnd(eventType, eventData)
    runtimeThermal_:NoteInteraction()
    if IsPresentationPaused() then return end
    if colorPickPointerGuard_ then colorPickPointerGuard_ = false; return end
    if portalTransition_:IsActive() then return end
    local id = eventData:GetInt("TouchID")
    local touch = touches_[id]
    if not touch or not world_ then return end
    local endX, endY = ResolveTouchPoint(eventData:GetInt("X"), eventData:GetInt("Y"), id)
    touch.x, touch.y = endX, endY
    if not ViewportCoordinates.IsTapMovement(touch.startX, touch.startY, endX, endY,
        CallWorld("PointerDragThreshold", true) or 9) then
        touch.dragged = true
    end
    if CallWorld("IsFirstPerson") then
        if touch.role == "move" then
            firstPersonMoveTouchId_ = nil
            CallWorld("SetFirstPersonMovement", 0, 0, false)
            CallWorld("SetFirstPersonJoystickVisual", 0, 0, false)
        else
            firstPersonLookTouchId_ = nil
        end
        touches_[id] = nil
        touchCount_ = math.max(0, touchCount_ - 1)
        return
    elseif mobileTransformGesture_ then
        local points = TouchPoints()
        if #points >= 2 then
            CallWorld("DragMobileTransformGesture", points[1].x, points[1].y, points[2].x, points[2].y)
        end
        CallWorld("EndTransformDrag")
        mobileTransformGesture_ = false
        for otherId, other in pairs(touches_) do
            if otherId ~= id then other.gestureConsumed, other.sceneTapPending, other.dragged = true, false, true end
        end
    elseif transformTouchId_ == id then
        CallWorld("DragTransform", touch.x, touch.y)
        CallWorld("EndTransformDrag")
        transformTouchId_ = nil
    elseif touch.sceneTapPending and not touch.dragged and touchCount_ == 1
        and world_:IsInViewport(touch.x, touch.y) and not IsPointOverUI(touch.x, touch.y) then
        world_:Tap(touch.x, touch.y)
    end
    touches_[id] = nil
    touchCount_ = math.max(0, touchCount_ - 1)
    if touchCount_ < 2 then pinchDistance_, pinchMidX_, pinchMidY_ = nil, nil, nil end
end

local function CommandDown()
    return input:GetKeyDown(KEY_LCTRL) or input:GetKeyDown(KEY_RCTRL)
        or input:GetKeyDown(KEY_LGUI) or input:GetKeyDown(KEY_RGUI)
end

local function ShiftDown()
    return input:GetKeyDown(KEY_LSHIFT) or input:GetKeyDown(KEY_RSHIFT)
end

local function HandleShortcuts()
    if IsPresentationPaused() or portalTransition_:IsActive() or not world_ or UIHasFocus() then return end
    if CallWorld("IsFirstPerson") then
        if input:GetKeyPress(KEY_F) then CallWorld("ToggleFirstPersonFlying") end
        if input:GetKeyPress(KEY_SPACE) and CallWorld("IsFirstPersonFlying") ~= true then
            CallWorld("JumpFirstPerson")
        end
        if input:GetKeyPress(KEY_ESCAPE) then
            ResetGestureState(false)
            CallWorld("ExitFirstPerson")
            SetFirstPersonPointerCapture(false)
        end
        return
    end
    if not storageReady_ then return end
    if CallWorld("IsColorPicking") then
        if input:GetKeyPress(KEY_ESCAPE) then CallWorld("CancelColorPick") end
        return
    end
    local command = CommandDown()
    if command and input:GetKeyPress(KEY_Z) then
        if ShiftDown() then CallWorld("Redo") else CallWorld("Undo") end
    elseif command and input:GetKeyPress(KEY_Y) then CallWorld("Redo")
    elseif command and input:GetKeyPress(KEY_D) then CallWorld("DuplicateSelected")
    elseif command and input:GetKeyPress(KEY_S) then
        if appMode_ == "island" and visitingEntry_ then Notify("参观模式不会修改或保存别人的空岛")
        elseif appMode_ == "island" and world_:IsProjectLoading() then
            world_:Notify("空岛仍在布置中，完成后会自动保存")
        elseif appMode_ == "island" then islandProject_ = world_:GetProjectData(); SaveIsland(true)
        else PersistWorkbenchDraft(true) end
    elseif not command and appMode_ == "island" and visitingEntry_ and input:GetKeyPress(KEY_ESCAPE) then
        LeaveVisit()
    elseif not command and (input:GetKeyPress(KEY_DELETE) or input:GetKeyPress(KEY_BACKSPACE)) then
        if appMode_ == "island" then DeleteSelectedIslandInstance() else CallWorld("DeleteSelected") end
    elseif not command and appMode_ == "island" and input:GetKeyPress(KEY_P) then
        if world_:EnterFirstPerson() then SetFirstPersonPointerCapture(true) end
    elseif not command and appMode_ == "island" and input:GetKeyPress(KEY_Q) then
        if world_.mode == "place" then CallWorld("RotatePlacement", -15)
        else CallWorld("TransformSelected", "rotate", -15) end
    elseif not command and appMode_ == "island" and input:GetKeyPress(KEY_T) then
        if world_.mode == "place" then CallWorld("RotatePlacement", 15)
        else CallWorld("TransformSelected", "rotate", 15) end
    elseif not command and appMode_ == "workbench" and input:GetKeyPress(KEY_F) then CallWorld("FocusSelected")
    elseif not command and appMode_ == "workbench" and input:GetKeyPress(KEY_V) then CallWorld("SetMode", "select")
    elseif not command and appMode_ == "workbench" and input:GetKeyPress(KEY_B) then CallWorld("SetMode", "add")
    elseif not command and appMode_ == "workbench" and input:GetKeyPress(KEY_X) then CallWorld("SetMode", "delete")
    elseif not command and input:GetKeyPress(KEY_W) then CallWorld("SetTransformMode", "translate")
    elseif not command and input:GetKeyPress(KEY_E) then CallWorld("SetTransformMode", "rotate")
    elseif not command and input:GetKeyPress(KEY_R) then CallWorld("SetTransformMode", "scale")
    elseif input:GetKeyPress(KEY_ESCAPE) then
        if not CallWorld("CancelColorPick") and not CallWorld("CancelTransformDrag") then
            if appMode_ == "island" and world_.mode == "place" then world_:CancelPlacement() else CallWorld("Select", nil) end
        end
    end
end

local function HandleUpdate(eventType, eventData)
    if startupBootstrapFrames_ > 0 then
        startupBootstrapFrames_ = startupBootstrapFrames_ - 1
        if startupBootstrapFrames_ == 0 then SetupApplication() end
        return
    end
    if startupContentFrames_ > 0 then
        startupContentFrames_ = startupContentFrames_ - 1
        if startupContentFrames_ == 0 and assetStore_ then LoadStartupContent() end
        return
    end
    local deviceLost = GraphicsDeviceIsLost()
    if deviceLost then
        HandleDeviceLost()
        return
    elseif graphicsDeviceLost_ then
        -- Some backends restore without dispatching DeviceReset to Lua.
        HandleDeviceReset()
    end
    if graphicsRecoveryFrames_ > 0 then
        graphicsRecoveryFrames_ = graphicsRecoveryFrames_ - 1
        if graphicsRecoveryFrames_ == 0 then RecoverGraphicsSurface() end
        return
    end
    if not world_ then return end
    local width, height, dpr = graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
    if width ~= screenWidth_ or height ~= screenHeight_ or math.abs(dpr - screenDpr_) > 0.001 then
        screenWidth_, screenHeight_, screenDpr_ = width, height, dpr
        screenRebuildFrames_ = 2
    elseif screenRebuildFrames_ > 0 then
        screenRebuildFrames_ = screenRebuildFrames_ - 1
        if screenRebuildFrames_ == 0 then
            ResetGestureState(true)
            if portalTransition_:IsActive() then IslandUI.ShowBootstrap() else UIRebuild() end
        end
    end
    local timeStep = eventData:GetFloat("TimeStep")
    BuilderStorage.Update(timeStep)
    islandSocial_.profiles.Update(timeStep)
    local thermalTarget = runtimeThermal_:Update(timeStep, IsPresentationPaused(),
        touchCount_ > 0 or mouseDown_
            or (input and (tonumber(input.numTouches) or 0) > 0)
            or portalTransition_:IsActive())
    CallWorld("SetThermalFrameTarget", thermalTarget)
    islandMarketSyncState_:Update(timeStep)
    if IsPresentationPaused() then
        -- Keep the resize/rebuild path above alive, but freeze every game-time
        -- source below: reward and portal clocks, world/day-night/camera update,
        -- autosave debounce, portal consumption and ordinary shortcuts.
        if input:GetKeyPress(KEY_ESCAPE) or input:GetKeyPress(KEY_P) then
            SetPresentationPaused(false)
        end
        return
    end
    if not portalTransition_:IsActive() and currentUI_ and currentUI_.Update then
        currentUI_.Update(timeStep)
    end
    if rewardGate_ then rewardGate_:Update(timeStep) end
    portalTransitGate_:Update(timeStep)
    if portalTransition_:IsActive() then
        local transitionResult = portalTransition_:Update(
            ActivatePortalRoute,
            function() return CallWorld("IsProjectLoading") == true end)
        if transitionResult and transitionResult.completed then FinishPortalLoading(transitionResult) end
    end
    if not portalTransition_:IsActive()
        and CallWorld("IsFirstPerson") and firstPersonMoveTouchId_ == nil then
        local forward = (input:GetKeyDown(KEY_W) and 1 or 0) - (input:GetKeyDown(KEY_S) and 1 or 0)
        local right = (input:GetKeyDown(KEY_D) and 1 or 0) - (input:GetKeyDown(KEY_A) and 1 or 0)
        CallWorld("SetFirstPersonMovement", forward, right, ShiftDown())
        local flying = CallWorld("IsFirstPersonFlying") == true
        if flying and not world_.mobileEditor then
            local rise = input:GetKeyDown(KEY_SPACE) and 1 or 0
            local descend = (input:GetKeyDown(KEY_LCTRL) or input:GetKeyDown(KEY_RCTRL)) and 1 or 0
            CallWorld("SetFirstPersonFlightVertical", rise - descend)
        elseif not flying then
            CallWorld("SetFirstPersonFlightVertical", 0)
        end
        if not world_.mobileEditor then
            local mouseMove = input.mouseMove
            if mouseMove and (math.abs(mouseMove.x) + math.abs(mouseMove.y) > 0) then
                CallWorld("LookFirstPerson", mouseMove.x, mouseMove.y, false)
            end
        end
    end
    if pendingIslandSave_ or pendingLibrarySave_ or pendingWorkbenchSave_ then
        saveElapsed_ = saveElapsed_ + timeStep
        if saveElapsed_ >= islandMarketSyncState_.autosaveDelay then FlushPendingSaves() end
    end
    world_:Update(timeStep)
    if not portalTransition_:IsActive() then
        local portalActivation = CallWorld("ConsumePortalActivation")
        if portalActivation then BeginPortalTransition(portalActivation) end
    end
    HandleShortcuts()
end

local function HandleEndRendering()
    if appMode_ == "workbench" and CallWorld("IsColorPicking") then CallWorld("CapturePendingColorPickFrame") end
end

local function HandleScreenMode()
    ResetGestureState(true)
    screenRebuildFrames_ = 2
end

local function HandleInputFocus(eventType, eventData)
    local focused = eventData:GetBool("Focus")
    runtimeThermal_:SetFocused(focused)
    if not focused then ResetGestureState(true) end
end

local function SubscribeEvents()
    SubscribeToEvent("Update", HandleUpdate)
    SubscribeToEvent("EndRendering", HandleEndRendering)
    SubscribeToEvent("TouchBegin", HandleTouchBegin)
    SubscribeToEvent("TouchMove", HandleTouchMove)
    SubscribeToEvent("TouchEnd", HandleTouchEnd)
    SubscribeToEvent("MouseButtonDown", HandleMouseDown)
    SubscribeToEvent("MouseMove", HandleMouseMove)
    SubscribeToEvent("MouseButtonUp", HandleMouseUp)
    SubscribeToEvent("MouseWheel", HandleMouseWheel)
    SubscribeToEvent("ScreenMode", HandleScreenMode)
    SubscribeToEvent("InputFocus", HandleInputFocus)
    SubscribeToEvent("DeviceLost", HandleDeviceLost)
    SubscribeToEvent("DeviceReset", HandleDeviceReset)
end

function Start()
    runtimeThermal_:SetFocused(true)
    runtimeThermal_:NoteInteraction()
    presentationPause_:Reset()
    portalTransitGate_:Reset()
    portalTransition_:Reset()
    graphics.windowTitle = "云岛造物工坊"
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true
    -- Give the lightweight, engine-bundled-font loading surface one complete
    -- render before template/sample generation and 3D world creation begin.
    IslandUI.ShowBootstrap()
    startupBootstrapFrames_ = 2
    SubscribeEvents()
    print("[MyIslandStudio] island, model workbench and model market v2 started")
end

function Stop()
    startupBootstrapFrames_, startupContentFrames_ = 0, 0
    BuilderStorage.ResetPendingLoads()
    ResetPresentationPause()
    portalTransition_:Reset()
    portalLoadingState_, portalLoadingStatus_ = nil, nil
    if rewardGate_ then rewardGate_:Reset() end
    rewardGate_ = nil
    if appMode_ == "island" and world_ then SyncActiveIslandFromWorld()
    elseif appMode_ == "workbench" and world_ then PersistWorkbenchDraft(false) end
    if storageReady_ then
        if islandCollection_ then BuilderStorage.SaveIsland(islandCollection_) end
        if assetStore_ then BuilderStorage.SaveModelLibrary(assetStore_:ExportState()) end
    end
    pendingIslandSave_, pendingLibrarySave_, pendingWorkbenchSave_ = nil, false, false
    islandSaveInFlight_, islandSaveShowMessage_ = false, false
    if currentUI_ then CloseCurrentSurface() else IslandUI.Shutdown() end
    assetStore_ = nil
    runtimeThermal_:SetMobile(false)
end
