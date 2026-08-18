---@diagnostic disable: undefined-global

local UI = require("urhox-libs/UI")
local IslandUITheme = require("IslandUITheme")
local ModelLibraryPresentation = require("ModelLibraryPresentation")
local IslandTerrainCatalog = require("IslandTerrainCatalog")
local ModelMiniature = require("ModelMiniature")
local UIRuntimeConfig = require("UIRuntimeConfig")
local ResponsiveLayout = require("ResponsiveLayout")
local TerrainDiscoveryGuide = require("TerrainDiscoveryGuide")

local IslandUI = {}
IslandUI._ExploreListVirtualization = require("ExploreListVirtualization")
local VERSION = "v2.47.0"
local STATUS_VISIBLE_SECONDS = 3.2
local MOBILE_HEADER_BUTTON_WIDTH = 35
local MOBILE_HEADER_TERRAIN_WIDTH = 42
local MOBILE_HEADER_HOME_BUILD_WIDTH = 60
local MOBILE_HEADER_GAP = 4
local LIBRARY_CATEGORY_STRIP_HEIGHT = 34
local ASSET_ROW_GAP = 8
local ASSET_POOL_BUFFER = 3
local PAUSE_TITLE_ASSET = "image/ui/cloud-atelier-title-comic.png"
local PAUSE_TITLE_ASPECT = 1881 / 836
local PAUSE_CREDIT_TEXT = "TapTap 制造"

-- Keep these color tables stable: widgets retain their references, so each
-- readable day/night theme can update the whole overlay at once.
local COLORS = IslandUITheme.Palette(12)
local appliedTimeMode_ = "day"

local function ApplyTimeTheme(hour, _phase)
    local mode = IslandUITheme.Mode(hour)
    if appliedTimeMode_ == mode then return end
    local palette = IslandUITheme.Palette(hour)
    for name, source in pairs(palette) do
        local target = COLORS[name]
        if not target then
            COLORS[name] = source
        else
            target[1], target[2], target[3], target[4] = source[1], source[2], source[3], source[4]
        end
    end
    appliedTimeMode_ = mode
end

local callbacks_ = nil
local state_ = nil
local paused_ = false
local status_ = "正在打开空岛……"
local statusVisibleUntil_ = 0
local profile_ = nil
local libraryOpen_ = false
local libraryCategory_ = "全部"
local islandManagerOpen_ = false
local rewardGateState_ = { phase = "idle" }
local terrainOpen_, terrainPurpose_ = false, "manage"
local terrainSelectedId_ = nil
local terrainRenameId_, terrainRenameValue_ = nil, ""
local terrainFeedback_ = ""
local autoBuildOpen_, autoBuildSelection_, autoBuildSelectionInitialized_ = false, {}, false
local portalBindingOpen_ = false
local resetConfirmOpen_ = false
local exploreOpen_, exploreLoading_, exploreSource_ = false, false, "sample"
local exploreEntries_ = {}
local exploreSort_ = "latest"
local social_ = {
    playerProfileOpen = false, playerProfile = {},
    guestbookOpen = false, guestbook = {}, guestbookDraft = "",
}
local Social = {}
local timePanelOpen_ = false
local mobileBottomHidden_ = false
local scrollPositions_ = {}
local pendingScrollRestores_ = {}
local structureListCache_ = setmetatable({}, { __mode = "k" })
local uiInitialized_, bootstrapActive_ = false, false
local renameIslandId_, renameIslandValue_, deleteConfirmId_ = nil, "", nil
local structureSignature_ = nil
local rebuilding_ = false
local statusLabel_, titleLabel_, countLabel_, selectionLabel_, selectionTransformLabel_ = nil, nil, nil, nil, nil
local undoButton_, redoButton_ = nil, nil
local terrainButton_ = nil
local autoBuildButton_, autoBuildAttentionPlayed_ = nil, false
local timeButton_, timeSlider_ = nil, nil
local placementPanel_, placementStatusLabel_, placementConfirmButton_ = nil, nil, nil
local terrainDiscovery_ = TerrainDiscoveryGuide.New(false)

local function RememberedScrollView(key, props)
    key = tostring(key or "default")
    props = props or {}
    local saved = scrollPositions_[key] or { x = 0, y = 0 }
    local inheritedOnScroll = props.onScroll
    props.onScroll = function(self, x, y)
        scrollPositions_[key] = {
            x = math.max(0, tonumber(x) or 0),
            y = math.max(0, tonumber(y) or 0),
        }
        if inheritedOnScroll then inheritedOnScroll(self, x, y) end
    end
    local scroll = UI.ScrollView(props)
    local restoreX = math.max(0, tonumber(saved.x) or 0)
    local restoreY = math.max(0, tonumber(saved.y) or 0)
    if scroll then
        pendingScrollRestores_[#pendingScrollRestores_ + 1] = {
            scroll = scroll, x = restoreX, y = restoreY,
        }
    end
    return scroll
end

local function RememberedVirtualList(key, props)
    key = tostring(key or "default")
    props = props or {}
    local saved = scrollPositions_[key] or { x = 0, y = 0 }
    local list = UI.VirtualList(props)
    local inheritedOnScroll = list.OnScroll
    list.OnScroll = function(self, x, y)
        scrollPositions_[key] = {
            x = math.max(0, tonumber(x) or 0),
            y = math.max(0, tonumber(y) or 0),
        }
        if inheritedOnScroll then return inheritedOnScroll(self, x, y) end
    end
    if list.scrollView_ then
        pendingScrollRestores_[#pendingScrollRestores_ + 1] = {
            scroll = list.scrollView_,
            x = math.max(0, tonumber(saved.x) or 0),
            y = math.max(0, tonumber(saved.y) or 0),
        }
    end
    return list
end

local function SetTextIfChanged(widget, text)
    if not widget then return end
    local value = tostring(text or "")
    if widget._lastText == value then return end
    widget._lastText = value
    widget:SetText(value)
end

local function SetStyleIfStateChanged(widget, key, value, style)
    if not widget or widget[key] == value then return end
    widget[key] = value
    widget:SetStyle(style)
end

local function ClockNow()
    local ok, value = pcall(os.clock)
    return ok and tonumber(value) or 0
end

local function ShowStatus(message)
    if not message or message == "" then return end
    status_ = tostring(message)
    statusVisibleUntil_ = ClockNow() + STATUS_VISIBLE_SECONDS
end

local function IsStatusVisible()
    return status_ ~= "" and ClockNow() <= (statusVisibleUntil_ or 0)
end

local function LogicalViewport()
    local scale = math.max(0.01, UI.GetScale())
    return graphics:GetWidth() / scale, graphics:GetHeight() / scale, scale
end

local function ViewportBottomForMode(mode, height, bottom)
    -- Mobile controls are overlays. Keeping the renderer behind them avoids a
    -- separate-looking strip at the bottom of the game view.
    if mode == "mobile" then return height end
    return height - bottom
end

local function ViewportTopForMode(mode, top)
    -- The phone header is made from floating controls just like the footer, so
    -- the 3D scene must continue underneath it as well.
    return mode == "mobile" and 0 or top
end

local function MobileHeaderTop(safeTop, nativeMenuBottom)
    return math.max((tonumber(safeTop) or 0) + 8,
        (tonumber(nativeMenuBottom) or 0) + 6)
end

local function MobileHeaderActionWidth()
    -- The first row only carries terrain creation controls; save/history live
    -- on a second row below the mini-program capsule.
    return MOBILE_HEADER_TERRAIN_WIDTH + MOBILE_HEADER_HOME_BUILD_WIDTH + MOBILE_HEADER_GAP * 2
end

local function MobileHeaderChildren(title, terrainButton, autoBuildButton)
    return { terrainButton, autoBuildButton, title }
end

local function MobileHeaderUtilityChildren(saveButton, undoButton, redoButton, pauseButton)
    return { saveButton, undoButton, redoButton, pauseButton }
end

local function LibraryCategoryStripHeight()
    return LIBRARY_CATEGORY_STRIP_HEIGHT
end

local function LibraryCategoryLayout(mode, width, tabCount)
    local available, gap = math.max(1, tonumber(width) or 1), 5
    if mode == "mobile" then
        return {
            horizontalScroll = true,
            gap = gap,
            tabWidth = math.max(54, math.min(74, (available - 12) / 4)),
            height = LIBRARY_CATEGORY_STRIP_HEIGHT,
        }
    end
    local columns = 3
    local rows = math.max(1, math.ceil(math.max(1, tonumber(tabCount) or 1) / columns))
    return {
        horizontalScroll = false,
        columns = columns,
        gap = gap,
        tabWidth = (available - gap * (columns - 1)) / columns,
        height = rows * 27 + math.max(0, rows - 1) * gap,
    }
end

local function FirstPersonEntryMetrics(mode)
    return mode == "mobile" and { width = 88, padding = 9 }
        or { width = 114, padding = 10 }
end

local function MobileIslandCardHeight()
    return 78
end

function IslandUI._MobileIslandActionHeight()
    return 28
end

function IslandUI._PlacementControlLabels(mobile)
    if mobile then
        return {
            switchModel = "换模型", rotateLeft = "左转", rotateRight = "右转",
            scaleDown = "缩小", scaleUp = "放大", confirm = "放置", close = "关闭",
        }
    end
    return {
        switchModel = "换模型", rotateLeft = "左转 Q", rotateRight = "右转 T",
        scaleDown = "−", scaleUp = "＋", close = "完成",
    }
end

function IslandUI._IslandPublishButtonState(item, state)
    item, state = item or {}, state or {}
    local syncId = state.islandMarketSyncIslandId
    local busy = state.islandMarketSyncBusy == true and syncId ~= nil
        and tostring(syncId) == tostring(item.id)
    return {
        label = busy and "处理中" or item.published and "下架" or "发布",
        disabled = busy,
        busy = busy,
    }
end

function IslandUI._MobileIslandActionWidths(innerWidth, gap, publishLabel)
    innerWidth, gap = math.max(1, tonumber(innerWidth) or 1), math.max(0, tonumber(gap) or 0)
    local available = math.max(5, innerWidth - gap * 4)
    local equalWidth = available / 5
    local publishWidth = publishLabel == "处理中" and math.max(equalWidth, 26) or equalWidth
    publishWidth = math.min(publishWidth, math.max(1, available - 4))
    return math.max(1, (available - publishWidth) / 4), publishWidth
end

local function ExploreActionDirection(mobile)
    return mobile and "row" or "column"
end

local function ExploreCardColumns(_mode)
    -- The three compact actions now live horizontally at the right of each
    -- phone card, so every entry needs the full list width to remain readable.
    return 1
end

local function TerrainPanelWidth(viewportWidth, mobile, mobileWidth)
    if mobile then return math.max(1, tonumber(mobileWidth) or viewportWidth) end
    local available = math.max(1, (tonumber(viewportWidth) or 1) - 64)
    local desired = math.max(760, (tonumber(viewportWidth) or 1) * 0.68)
    return math.min(available, math.min(920, desired))
end

local function PauseTitleLayout(profile)
    profile = profile or {}
    local safe = profile.safe or {}
    local width = math.max(1, tonumber(profile.width) or 1)
    local available = math.max(1, width - (tonumber(safe.left) or 0)
        - (tonumber(safe.right) or 0) - 32)
    local target = profile.mode == "mobile"
        and math.max(190, width * 0.30) or math.max(240, width * 0.26)
    local titleWidth = math.min(available, profile.mode == "mobile"
        and math.min(270, target) or math.min(360, target))
    return {
        left = (tonumber(safe.left) or 0) + 16,
        bottom = (tonumber(safe.bottom) or 0) + 16,
        width = titleWidth,
        height = titleWidth / PAUSE_TITLE_ASPECT,
    }
end

local function PauseCreditLayout(profile, title)
    profile = profile or {}
    title = title or PauseTitleLayout(profile)
    local mobile = profile.mode == "mobile"
    local width = mobile and 72 or 82
    local height = mobile and 16 or 18
    return {
        left = title.left + math.max(6, title.width * 0.075),
        bottom = title.bottom + math.max(1, title.height * 0.025),
        width = width,
        height = height,
        fontSize = mobile and 7 or 8,
    }
end

local function IslandManagerColumns(mode)
    return mode == "mobile" and 2 or 1
end

local function DesktopLibraryWidth(profile)
    return math.min(680, math.max(580, profile.width * 0.56))
end

local function TerrainManagementLabels(inUseCount)
    local inUse = (tonumber(inUseCount) or 0) > 0
    return "改名", inUse and "正在使用" or "重新生成",
        inUse and "禁止删除" or "删除地形"
end

local ResponsiveMode = ResponsiveLayout.Resolve

local function CurrentProfile()
    local width, height, scale = LogicalViewport()
    local dpr = math.max(0.01, graphics:GetDPR())
    local cssWidth, cssHeight = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local safe = { top = 0, right = 0, bottom = 0, left = 0 }
    local ok, value = pcall(UI.GetSafeAreaInsets)
    if ok and type(value) == "table" then
        safe.top, safe.right = tonumber(value.top) or 0, tonumber(value.right) or 0
        safe.bottom, safe.left = tonumber(value.bottom) or 0, tonumber(value.left) or 0
    end
    local nativePlatform = GetNativePlatform and GetNativePlatform()
        or GetPlatform and GetPlatform() or ""
    local mode = ResponsiveMode(cssWidth, cssHeight, nativePlatform)
    local nativeMenuRight, nativeMenuBottom = 0, 0
    local sdk = rawget(_G, "sdk")
    if sdk and sdk.GetNativeExitMenuRect then
        local okMenu, rect = pcall(function() return sdk:GetNativeExitMenuRect() end)
        if okMenu and rect then
            nativeMenuRight = math.max(0, width - (tonumber(rect.left) or 1) * width + 12)
            nativeMenuBottom = math.max(0, (tonumber(rect.bottom) or 0) * height + 8)
        end
    end
    if mode == "mobile" then
        nativeMenuRight = math.max(nativeMenuRight, safe.right + 140)
        nativeMenuBottom = math.max(nativeMenuBottom, safe.top + 44)
    end
    local mobileHeaderTop = MobileHeaderTop(safe.top, nativeMenuBottom)
    local visitMode = state_ and state_.visitMode
    local top = mode == "mobile" and (mobileHeaderTop + (visitMode and 96 or 78)) or 48
    local footer = mode == "mobile" and 0 or 22
    local bottom = mode == "mobile"
        and (visitMode and 0 or (mobileBottomHidden_ and (24 + safe.bottom) or (68 + safe.bottom)))
        or footer
    local left = 0
    if not (state_ and state_.visitMode) and libraryOpen_ and not islandManagerOpen_ then
        if mode == "desktop" then
            left = DesktopLibraryWidth({ width = width })
        elseif mode == "tablet" then
            left = 276
        end
    end
    local right = (mode == "desktop" and state_ and state_.selected) and 250 or 0
    if paused_ or state_ and state_.firstPerson then
        top, footer, bottom, left, right = 0, 0, 0, 0, 0
    end
    return {
        width = width, height = height, scale = scale, mode = mode, safe = safe,
        top = top, footer = footer, bottom = bottom, left = left, right = right,
        nativeMenuRight = nativeMenuRight,
        nativeMenuBottom = nativeMenuBottom,
        mobileHeaderTop = mobileHeaderTop,
        viewportLeft = left,
        viewportTop = ViewportTopForMode(mode, top),
        viewportRight = width - right,
        viewportBottom = ViewportBottomForMode(mode, height, bottom),
    }
end

local function MobileLeftInset(profile)
    return math.max(22, 12 + (profile.safe.left or 0))
end

local function MobileRightInset(profile)
    return math.max(22, 12 + (profile.safe.right or 0))
end

local function MobileBottomInset(profile)
    return math.max(14, 12 + (profile.safe.bottom or 0))
end

local function MobilePanelWidth(profile)
    return math.max(1, profile.width - MobileLeftInset(profile) - MobileRightInset(profile))
end

local function ShouldBuildMobileBottom(mode, selected, placementMode)
    return mode == "mobile" and placementMode ~= "place" and not selected
end

local function MobileModalTop(profile)
    return math.max((profile.safe.top or 0) + 12, (profile.nativeMenuBottom or 0) + 8)
end

local function RewardGateOpen()
    if type(rewardGateState_) ~= "table" then return false end
    if rewardGateState_.open ~= nil then return rewardGateState_.open == true end
    local phase = tostring(rewardGateState_.phase or "idle")
    return phase ~= "idle" and phase ~= "closed"
end

local function RewardGateBusy()
    local phase = type(rewardGateState_) == "table" and rewardGateState_.phase or "idle"
    return rewardGateState_ and rewardGateState_.busy == true
        or phase == "queued" or phase == "waiting" or phase == "playing"
end

local function RewardGateStateKey(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    return table.concat({ tostring(snapshot.open == true), tostring(snapshot.phase or "closed"),
        tostring(snapshot.key or ""), tostring(snapshot.title or ""),
        tostring(snapshot.description or ""), tostring(snapshot.subject or snapshot.detail or ""),
        tostring(snapshot.confirmLabel or ""), tostring(snapshot.feedback or snapshot.message or "") }, "\30")
end

local function BlockingSurfaceOpen()
    return libraryOpen_ or islandManagerOpen_ or exploreOpen_ or terrainOpen_
        or autoBuildOpen_ or portalBindingOpen_ or resetConfirmOpen_
        or social_.playerProfileOpen or social_.guestbookOpen
        or terrainDiscovery_.phase == "open" or terrainDiscovery_.phase == "flying"
        or RewardGateOpen()
end

local function Button(text, onClick, props)
    props = props or {}
    local mobile = profile_ and profile_.mode == "mobile"
    return UI.Button {
        text = text,
        position = props.position,
        left = props.left,
        right = props.right,
        top = props.top,
        bottom = props.bottom,
        width = props.width,
        minWidth = props.minWidth,
        height = props.height or (mobile and 36 or 30),
        flexGrow = props.flexGrow,
        flexShrink = props.flexShrink == nil and 0 or props.flexShrink,
        paddingHorizontal = props.paddingHorizontal or 7,
        backgroundColor = props.backgroundColor or (props.danger and COLORS.coralSoft or COLORS.surface),
        hoverBackgroundColor = props.hoverBackgroundColor or (props.danger and COLORS.dangerHover or COLORS.yellowSoft),
        pressedBackgroundColor = props.pressedBackgroundColor or (props.danger and COLORS.dangerPressed or COLORS.skySoft),
        borderColor = props.borderColor or (props.danger and COLORS.dangerLine or COLORS.line),
        borderWidth = props.borderWidth or 1,
        borderRadius = props.borderRadius or 10,
        textColor = props.textColor or (props.danger and COLORS.danger or COLORS.ink),
        fontSize = props.fontSize or 10,
        fontWeight = "bold",
        boxShadow = props.boxShadow or false,
        disabled = props.disabled,
        onClick = onClick,
    }
end

local function ActiveButton(text, active, onClick, props)
    props = props or {}
    if active then
        props.backgroundColor, props.hoverBackgroundColor = COLORS.blue, COLORS.blueDark
        props.borderColor, props.textColor = COLORS.blueDark, COLORS.white
        props.borderWidth = 2
        props.boxShadow = { { x = 0, y = 3, blur = 8, color = COLORS.accentShadow } }
    end
    return Button(text, onClick, props)
end

function Social.CopySnapshot(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do result[key] = value end
    end
    return result
end

function Social.NonEmptyText(value, fallback)
    local text = value == nil and "" or tostring(value)
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then return tostring(fallback or "") end
    return text
end

function Social.AvatarProps(snapshot, name, size, fallbackColor)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local avatar = type(snapshot.avatar) == "table" and snapshot.avatar or {}
    local directSource = type(snapshot.avatar) == "string" and snapshot.avatar or nil
    return {
        src = avatar.src or avatar.url or directSource or snapshot.avatarUrl,
        name = name,
        initials = avatar.initials or snapshot.initials,
        backgroundColor = avatar.backgroundColor or snapshot.avatarColor or fallbackColor,
        textColor = avatar.textColor,
        status = avatar.status or snapshot.statusIndicator,
        size = size,
        shape = avatar.shape or "circle",
        showBorder = avatar.showBorder ~= false,
        onClick = snapshot.onClick,
    }
end

function Social.ClosePrimarySurfaces()
    libraryOpen_, islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, false, false
    terrainOpen_, autoBuildOpen_, portalBindingOpen_, resetConfirmOpen_ = false, false, false, false
end

function Social.RequestPlayerProfile(ownerId, nickname)
    local normalizedId = ownerId ~= nil and tostring(ownerId) or ""
    local normalizedName = Social.NonEmptyText(nickname, "云岛旅人")
    Social.ClosePrimarySurfaces()
    social_.playerProfileOpen = true
    social_.playerProfile = {
        ownerId = normalizedId,
        userId = normalizedId,
        nickname = normalizedName,
        loading = callbacks_ and type(callbacks_.openPlayerProfile) == "function" or false,
    }
    if callbacks_ and callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
    IslandUI.Rebuild()
    if callbacks_ and callbacks_.openPlayerProfile then
        local accepted = callbacks_.openPlayerProfile(
            normalizedId ~= "" and normalizedId or nil, normalizedName)
        if accepted == false and social_.playerProfile.loading == true then
            social_.playerProfile.loading = false
            social_.playerProfile.feedback = "暂时无法读取这位玩家的资料。"
            IslandUI.Rebuild()
        end
    end
end

function Social.CurrentGuestbookIdentity()
    local snapshot = state_ or {}
    local ownerId = snapshot.visitMode
        and (snapshot.visitOwnerId or snapshot.ownerId or snapshot.userId)
        or (snapshot.ownerId or snapshot.userId or snapshot.currentUserId)
    local islandId = snapshot.visitMode
        and (snapshot.visitIslandId or snapshot.activeIslandId or snapshot.islandId)
        or (snapshot.activeIslandId or snapshot.islandId)
    local owner = snapshot.visitMode
        and (snapshot.visitOwner or snapshot.ownerNickname or snapshot.nickname)
        or (snapshot.ownerNickname or snapshot.nickname or "我")
    return ownerId ~= nil and tostring(ownerId) or "",
        islandId ~= nil and tostring(islandId) or "",
        Social.NonEmptyText(owner, snapshot.visitMode and "云岛旅人" or "我")
end

function Social.RequestGuestbook()
    local ownerId, islandId, owner = Social.CurrentGuestbookIdentity()
    local sameBoard = tostring(social_.guestbook.ownerId or social_.guestbook.userId or "") == ownerId
        and tostring(social_.guestbook.islandId or "") == islandId
    local nextState = sameBoard and Social.CopySnapshot(social_.guestbook) or {}
    nextState.ownerId, nextState.userId = ownerId, ownerId
    nextState.islandId, nextState.owner = islandId, owner
    nextState.nickname = nextState.nickname or owner
    nextState.messages = type(nextState.messages) == "table" and nextState.messages or {}
    nextState.canPost = state_ and state_.visitMode == true or false
    nextState.loading = callbacks_ and type(callbacks_.openGuestbook) == "function" or false
    nextState.posting = false
    if not sameBoard then social_.guestbookDraft = "" end
    social_.guestbook = nextState
    Social.ClosePrimarySurfaces()
    social_.playerProfileOpen, social_.guestbookOpen = false, true
    if callbacks_ and callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
    IslandUI.Rebuild()
    if callbacks_ and callbacks_.openGuestbook then
        local accepted = callbacks_.openGuestbook(ownerId ~= "" and ownerId or nil,
            islandId ~= "" and islandId or nil, state_ and state_.visitMode == true)
        if accepted == false and social_.guestbook.loading == true then
            social_.guestbook.loading = false
            social_.guestbook.feedback = Social.NonEmptyText(social_.guestbook.feedback,
                "留言板暂时无法打开。")
            IslandUI.Rebuild()
        end
    end
end

function Social.NicknameButton(nickname, ownerId, props)
    props = props or {}
    return Button(Social.NonEmptyText(nickname, "云岛旅人"), function()
        Social.RequestPlayerProfile(ownerId, nickname)
    end, {
        width = props.width,
        minWidth = props.minWidth or 0,
        height = props.height or 20,
        flexGrow = props.flexGrow,
        flexShrink = props.flexShrink == nil and 1 or props.flexShrink,
        paddingHorizontal = props.paddingHorizontal or 2,
        fontSize = props.fontSize or 8,
        backgroundColor = COLORS.transparent,
        hoverBackgroundColor = COLORS.skySoft,
        pressedBackgroundColor = COLORS.yellowSoft,
        borderColor = COLORS.transparent,
        borderWidth = 0,
        borderRadius = props.borderRadius or 7,
        textColor = props.textColor or COLORS.blueDark,
    })
end

function Social.PlayerIdentity(nickname, ownerId, avatarSnapshot, props)
    props = props or {}
    local name = Social.NonEmptyText(nickname, "云岛旅人")
    local snapshot = type(avatarSnapshot) == "table"
        and Social.CopySnapshot(avatarSnapshot) or {}
    snapshot.onClick = function()
        Social.RequestPlayerProfile(ownerId, name)
    end
    local avatarSize = props.avatarSize or 24
    return UI.Panel {
        width = props.width,
        height = props.height or math.max(avatarSize, 24),
        minWidth = props.minWidth or 0,
        flexGrow = props.flexGrow,
        flexShrink = props.flexShrink == nil and 1 or props.flexShrink,
        flexDirection = "row", alignItems = "center", gap = props.gap or 6,
        paddingHorizontal = props.paddingHorizontal or 0,
        backgroundColor = props.backgroundColor or COLORS.transparent,
        borderColor = props.borderColor or COLORS.transparent,
        borderWidth = props.borderWidth or 0,
        borderRadius = props.borderRadius or math.floor(avatarSize * 0.5 + 5),
        pointerEvents = "box-none",
        children = {
            UI.Avatar(Social.AvatarProps(snapshot, name, avatarSize, props.avatarColor or COLORS.blue)),
            Social.NicknameButton(name, ownerId, {
                height = props.nameHeight or math.max(20, avatarSize - 2),
                fontSize = props.fontSize or 9,
                paddingHorizontal = 0,
                textColor = props.textColor or COLORS.blueDark,
                flexGrow = props.nameFlexGrow,
            }),
        },
    }
end

function Social.SubmitGuestbookMessage()
    local message = Social.NonEmptyText(social_.guestbookDraft, "")
    if message == "" then
        social_.guestbook.feedback = "先写下一句话吧。"
        IslandUI.Rebuild()
        return
    end
    if not callbacks_ or type(callbacks_.postGuestbookMessage) ~= "function" then
        social_.guestbook.feedback = "留言功能暂不可用。"
        IslandUI.Rebuild()
        return
    end
    social_.guestbook.posting = true
    social_.guestbook.feedback = ""
    IslandUI.Rebuild()
    local ok, accepted, feedback = pcall(callbacks_.postGuestbookMessage, message)
    if not ok then
        social_.guestbook.posting = false
        social_.guestbook.feedback = "留言发送失败，请稍后重试。"
        IslandUI.Rebuild()
    elseif accepted == false then
        social_.guestbook.posting = false
        social_.guestbook.feedback = Social.NonEmptyText(feedback, "留言发送失败，请稍后重试。")
        IslandUI.Rebuild()
    elseif accepted == true then
        social_.guestbookDraft = ""
        social_.guestbook.feedback = Social.NonEmptyText(feedback, "留言已送达。")
        IslandUI.Rebuild()
    end
end

local function ResolveTerrainId(value)
    local candidate = type(value) == "table"
        and (value.id or value.terrainId or value.preset) or value
    if IslandTerrainCatalog.ResolveId then
        return IslandTerrainCatalog.ResolveId(candidate)
    end
    return tostring(candidate or IslandTerrainCatalog.DEFAULT_ID)
end

local function CurrentTerrainId()
    return ResolveTerrainId(state_ and (state_.terrainId or state_.terrainPreset)
        or IslandTerrainCatalog.DEFAULT_ID)
end

local function TerrainPresets()
    local source = state_ and state_.terrainPresets
    if type(source) ~= "table" or #source == 0 then source = IslandTerrainCatalog.List() end
    local result = {}
    for _, summary in ipairs(source or {}) do
        local full = IslandTerrainCatalog.Get and IslandTerrainCatalog.Get(summary) or nil
        local item = full or summary
        if full and type(summary) == "table" then
            item.rewardRequired = summary.rewardRequired == true
            item.unlocked = summary.unlocked == true
            item.locked = summary.locked == true
        end
        result[#result + 1] = item
    end
    return result
end

local function TerrainName(id)
    for _, summary in ipairs(state_ and state_.terrainPresets or {}) do
        if ResolveTerrainId(summary) == ResolveTerrainId(id) then
            return tostring(summary.name or "空岛地形")
        end
    end
    local preset = IslandTerrainCatalog.Get and IslandTerrainCatalog.Get(ResolveTerrainId(id)) or nil
    return preset and tostring(preset.name or "空岛地形") or "空岛地形"
end

local function TerrainLocked(id)
    local resolved = ResolveTerrainId(id)
    for _, summary in ipairs(state_ and state_.terrainPresets or {}) do
        if ResolveTerrainId(summary) == resolved then return summary.locked == true end
    end
    return resolved ~= IslandTerrainCatalog.DEFAULT_ID
end

local function AssetSelectionKey(asset)
    return tostring(asset and (asset.assetId or asset.id) or "")
        .. "@" .. tostring(asset and asset.versionId or "latest")
end

local function AutoBuildAssets()
    local assets = state_ and state_.autoBuildAssets or nil
    if type(assets) ~= "table" or #assets == 0 then assets = state_ and state_.assets or {} end
    return assets
end

local function SetAllAutoBuildAssets(selected)
    autoBuildSelection_ = {}
    autoBuildSelectionInitialized_ = true
    if selected then
        for _, asset in ipairs(AutoBuildAssets()) do autoBuildSelection_[AssetSelectionKey(asset)] = true end
    end
end

local function AutoBuildSelectionCount()
    local count = 0
    for _, asset in ipairs(AutoBuildAssets()) do
        if autoBuildSelection_[AssetSelectionKey(asset)] then count = count + 1 end
    end
    return count
end

local function AutoBuildButtonLabel(compactMobile)
    return "一键建岛"
end

local function ResetButtonDisabled(count)
    return (tonumber(count) or 0) <= 0
end

local function OpenAutoBuild()
    if not autoBuildSelectionInitialized_ then SetAllAutoBuildAssets(true) end
    libraryOpen_, islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, false, false
    terrainOpen_, autoBuildOpen_ = false, true
    IslandUI.Rebuild()
end

function IslandUI._OpenPlacementModelLibrary()
    -- Keep the live placement state and its ghost intact. Only swap the UI
    -- surface, retaining the current model tab, category and remembered scroll.
    islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, false
    terrainOpen_, autoBuildOpen_, portalBindingOpen_, resetConfirmOpen_ = false, false, false, false
    libraryOpen_ = true
    IslandUI.Rebuild()
end

local function CloseAutoBuild()
    autoBuildOpen_ = false
    IslandUI.Rebuild()
end

local function OpenResetConfirmation()
    libraryOpen_, islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, false, false
    terrainOpen_, autoBuildOpen_, portalBindingOpen_ = false, false, false
    resetConfirmOpen_ = true
    IslandUI.Rebuild()
end

local function CloseResetConfirmation()
    resetConfirmOpen_ = false
    IslandUI.Rebuild()
end

local function OpenPortalBinding()
    if not state_ or not state_.selected or not state_.selected.isPortal then return end
    libraryOpen_, islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, false, false
    terrainOpen_, autoBuildOpen_ = false, false
    portalBindingOpen_ = true
    IslandUI.Rebuild()
end

local function ClosePortalBinding()
    portalBindingOpen_ = false
    IslandUI.Rebuild()
end

local function InitialTerrainSelection(purpose, currentId)
    if purpose == "create" then return ResolveTerrainId(IslandTerrainCatalog.DEFAULT_ID) end
    return ResolveTerrainId(currentId)
end

local function OpenTerrainPicker(purpose)
    if terrainDiscovery_.phase == "waiting" then
        terrainDiscovery_.handledThisRun = true
        terrainDiscovery_.phase = "done"
        terrainDiscovery_.elapsed = 0
    end
    terrainPurpose_ = purpose == "create" and "create" or "manage"
    terrainSelectedId_ = InitialTerrainSelection(terrainPurpose_, CurrentTerrainId())
    terrainRenameId_, terrainRenameValue_, terrainFeedback_ = nil, "", ""
    libraryOpen_, islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, false, false
    autoBuildOpen_, terrainOpen_ = false, true
    IslandUI.Rebuild()
end

local function CloseTerrainPicker()
    terrainOpen_ = false
    terrainPurpose_, terrainSelectedId_ = "manage", nil
    terrainRenameId_, terrainRenameValue_, terrainFeedback_ = nil, "", ""
    IslandUI.Rebuild()
end

function IslandUI.CloseTerrainDiscovery()
    if terrainDiscovery_.phase ~= "open" then return false end
    if callbacks_ and callbacks_.dismissTerrainDiscovery then
        callbacks_.dismissTerrainDiscovery(terrainDiscovery_.doNotRemind == true)
    end
    terrainDiscovery_.phase = "flying"
    terrainDiscovery_.flightFinished = false
    IslandUI.Rebuild()
    return true
end

local function CloseRewardGate()
    if RewardGateBusy() then return end
    if callbacks_ and callbacks_.cancelRewardGate then
        callbacks_.cancelRewardGate()
    else
        rewardGateState_ = { phase = "idle" }
        IslandUI.Rebuild()
    end
end

local function TabLabel(tab)
    return ({ builtin = "内置", mine = "我的", market = "市场", favorites = "收藏" })[tab] or "模型"
end

local function SourceTone(source)
    if source == "market" then return COLORS.gold end
    if source == "mine" then return COLORS.green end
    return COLORS.blue
end

local function AssetGlyph(asset)
    local category = tostring(asset.category or "")
    if category:find("建筑群") then return "▦" end
    if category:find("建筑") then return "⌂" end
    if category:find("飞行器") then return "✦" end
    if category:find("围栏") then return "▥" end
    if category:find("街景") then return "▣" end
    if category:find("构件") then return "▰" end
    if category:find("道具") or category:find("机关") then return "⚙" end
    if category:find("物品") or category:find("家具") then return "▣" end
    if category:find("森林") or category:find("树木") then return "♣" end
    if category:find("自然") or category:find("植被") then return "✿" end
    if category:find("水域") or category:find("湖泊") then return "≈" end
    if category:find("山体") or category:find("地貌") then return "▲" end
    if category:find("地形") then return "▰" end
    if category:find("遗迹") or category:find("秘境") then return "✦" end
    return asset.source == "market" and "◆" or asset.source == "mine" and "●" or "⌂"
end

local function ModelMiniatureChildren(asset, size, fallbackFontSize)
    local parts = type(asset.previewParts) == "table" and asset.previewParts
        or ModelMiniature.Parts(asset, 12)
    ---@type Widget[]
    local children = {}
    for _, part in ipairs(parts or {}) do
        local width, height = math.max(1.5, part.width * size), math.max(1.5, part.height * size)
        children[#children + 1] = UI.Panel {
            position = "absolute", left = part.x * size, top = part.y * size,
            width = width, height = height, backgroundColor = part.color,
            borderColor = { 61, 95, 108, 72 }, borderWidth = 1,
            borderRadius = part.round and math.min(width, height) * 0.5 or 1.5,
            pointerEvents = "none",
        }
    end
    if #children == 0 then
        children[1] = UI.Label { text = AssetGlyph(asset), fontSize = fallbackFontSize,
            fontWeight = "900", fontColor = SourceTone(asset.source) }
    end
    return children
end

local function PlaceActionSucceeded(result)
    return result == true
end

local function RunAndClose(callback)
    local result = callback and callback() or false
    if PlaceActionSucceeded(result) and profile_ and profile_.mode == "mobile" then
        libraryOpen_ = false
        IslandUI.Rebuild()
    end
    return result
end

local function AssetActionWidth(text, mobile, minimum)
    local ok, utf8Length = pcall(function() return utf8.len(tostring(text or "")) end)
    local length = ok and tonumber(utf8Length) or nil
    length = length or #tostring(text or "")
    local fontSize, horizontalPadding = 9, mobile and 12 or 14
    return math.max(minimum or 1, math.ceil(length * fontSize + horizontalPadding))
end

local function AssetListColumns(width)
    return width >= 620 and 2 or 1
end

local function BuildAssetCard(asset, width)
    local mobile = profile_ and profile_.mode == "mobile"
    local cardPadding = mobile and 8 or 11
    local cardGap = mobile and 7 or 9
    local compactMine = asset.source == "mine"
    local wideMine = compactMine and width >= 430
    local iconSize = compactMine and (mobile and 27 or 32) or mobile and 31 or 40
    local actionHeight = compactMine and (mobile and 25 or 26) or mobile and 26 or 28
    local primaryActionMinimum = compactMine and 32 or mobile and 42 or 46
    local secondaryActionMinimum = compactMine and 32 or mobile and 38 or 42
    local actionPadding = compactMine and 4 or mobile and 6 or 7
    local actions = {
        Button("放置", function()
            RunAndClose(function()
                return callbacks_.placeAsset(asset.assetId or asset.id, asset.versionId)
            end)
        end, { width = AssetActionWidth("放置", mobile, primaryActionMinimum), height = actionHeight,
            paddingHorizontal = actionPadding, backgroundColor = COLORS.soft, borderColor = COLORS.blue }),
    }
    if asset.source == "market" then
        local favoriteLabel = asset.favorite and "已藏" or "收藏"
        actions[#actions + 1] = Button(favoriteLabel, function()
            callbacks_.toggleFavorite(asset.assetId or asset.id, asset.versionId)
        end, { width = AssetActionWidth(favoriteLabel, mobile, secondaryActionMinimum), height = actionHeight,
            paddingHorizontal = mobile and 6 or 7, fontSize = 9 })
        if asset.license ~= "use_only" then
            actions[#actions + 1] = Button("再创作", function() callbacks_.editAsset(asset.assetId or asset.id) end,
                { width = AssetActionWidth("再创作", mobile, secondaryActionMinimum), height = actionHeight,
                    paddingHorizontal = mobile and 6 or 7, fontSize = 9, backgroundColor = COLORS.soft })
        end
    elseif asset.source == "mine" then
        actions[#actions + 1] = Button("编辑", function() callbacks_.editAsset(asset.assetId or asset.id) end,
            { width = AssetActionWidth("编辑", mobile, secondaryActionMinimum), height = actionHeight,
                paddingHorizontal = actionPadding, fontSize = 9 })
        actions[#actions + 1] = Button("删除", function() callbacks_.deleteAsset(asset.assetId or asset.id) end,
            { width = AssetActionWidth("删除", mobile, secondaryActionMinimum), height = actionHeight,
                paddingHorizontal = actionPadding, fontSize = 9, danger = true })
        local publishLabel = asset.withdrawn and "重新发布" or asset.publishedVersion and "更新" or "发布"
        actions[#actions + 1] = Button(publishLabel, function()
            callbacks_.publishAsset(asset.assetId or asset.id)
        end, { width = AssetActionWidth(publishLabel, mobile, secondaryActionMinimum), height = actionHeight,
            paddingHorizontal = actionPadding, fontSize = 9, backgroundColor = COLORS.soft })
        if asset.publishedVersion and not asset.withdrawn then
            actions[#actions + 1] = Button("下架", function()
                callbacks_.unpublishAsset(asset.assetId or asset.id)
            end, { width = AssetActionWidth("下架", mobile, secondaryActionMinimum), height = actionHeight,
                paddingHorizontal = actionPadding, fontSize = 9, danger = true })
        end
    end
    local actionWidth = mobile and (#actions > 2 and 78 or 42)
        or asset.source == "mine" and 112 or (#actions > 2 and 86 or 46)
    local assetMeta
    if compactMine then
        local status = asset.withdrawn and "已下架" or asset.publishedVersion and "已发布" or "草稿"
        assetMeta = tostring(asset.category or "模型") .. " · " .. tostring(asset.count or 0)
            .. " 组件 · " .. status
    else
        assetMeta = tostring(asset.category or "模型") .. " · " .. tostring(asset.author or "我的空岛")
            .. " · " .. tostring(asset.count or 0) .. " 组件"
    end
    ---@type Widget[]
    local infoChildren = {
        UI.Label { text = tostring(asset.name or "未命名模型"), fontSize = mobile and 10 or 11,
            fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
    }
    if not compactMine and asset.source == "market" and asset.ownerId then
        infoChildren[#infoChildren + 1] = UI.Panel {
            width = "100%", height = 20, flexDirection = "row", alignItems = "center", gap = 1,
            backgroundColor = COLORS.transparent, borderWidth = 0, pointerEvents = "box-none",
            children = {
                UI.Label { text = tostring(asset.category or "模型") .. " · ", flexShrink = 0,
                    fontSize = 8, fontWeight = "bold", fontColor = COLORS.muted, maxLines = 1 },
                Social.PlayerIdentity(asset.author, asset.ownerId, asset, {
                    height = 20, avatarSize = 18, fontSize = 8, gap = 4,
                    textColor = COLORS.blueDark,
                }),
                UI.Label { text = " · " .. tostring(asset.count or 0) .. " 组件", flexShrink = 0,
                    fontSize = 8, fontWeight = "bold", fontColor = COLORS.muted, maxLines = 1 },
            },
        }
    else
        infoChildren[#infoChildren + 1] = UI.Label {
            text = assetMeta,
            fontSize = 8, fontWeight = "bold", fontColor = COLORS.muted, maxLines = 1,
        }
    end
    if not mobile and not compactMine then
        infoChildren[#infoChildren + 1] = UI.Label {
            text = ModelLibraryPresentation.CompactDescription(asset.description),
            fontSize = 8, fontColor = COLORS.muted, maxLines = 1,
        }
    end
    local iconChildren = (not asset.thumbnail or asset.thumbnail == "")
        and ModelMiniatureChildren(asset, iconSize, mobile and 16 or 21) or {}
    local iconPanel = UI.Panel {
        width = iconSize, height = iconSize, flexShrink = 0, alignItems = "center", justifyContent = "center",
        backgroundImage = asset.thumbnail,
        backgroundFit = "contain",
        backgroundColor = { SourceTone(asset.source)[1], SourceTone(asset.source)[2], SourceTone(asset.source)[3], 32 },
        borderColor = { SourceTone(asset.source)[1], SourceTone(asset.source)[2], SourceTone(asset.source)[3], 92 },
        borderWidth = 2,
        borderRadius = 9,
        children = iconChildren,
    }
    local infoPanel = UI.Panel {
        flexGrow = 1, flexShrink = 1, flexDirection = "column", gap = 2,
        justifyContent = "center", children = infoChildren,
    }
    if wideMine then
        return UI.Panel {
            width = width, minHeight = 60, padding = 8, gap = 9,
            flexDirection = "row", alignItems = "center",
            backgroundColor = COLORS.surface,
            borderColor = asset.featured and COLORS.gold or COLORS.line,
            borderWidth = asset.featured and 2 or 1, borderRadius = 14,
            children = {
                iconPanel,
                infoPanel,
                UI.Panel {
                    flexShrink = 0, flexDirection = "row", gap = 4,
                    alignItems = "center", justifyContent = "flex-end", children = actions,
                },
            },
        }
    end
    if compactMine then
        return UI.Panel {
            width = width, minHeight = mobile and 66 or 70, padding = mobile and 5 or 6, gap = 4,
            flexDirection = "column", justifyContent = "center",
            backgroundColor = COLORS.surface,
            borderColor = asset.featured and COLORS.gold or COLORS.line,
            borderWidth = asset.featured and 2 or 1, borderRadius = 14,
            children = {
                UI.Panel {
                    width = "100%", height = mobile and 27 or 29, flexDirection = "row", alignItems = "center",
                    gap = 6,
                    children = { iconPanel, infoPanel },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 3,
                    alignItems = "center", justifyContent = "flex-end", children = actions,
                },
            },
        }
    end
    return UI.Panel {
        width = width,
        minHeight = mobile and (#actions > 2 and 68 or 58) or (#actions > 2 and 92 or 80),
        padding = cardPadding,
        gap = cardGap,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = COLORS.surface,
        borderColor = asset.featured and COLORS.gold or COLORS.line,
        borderWidth = asset.featured and 2 or 1,
        borderRadius = 15,
        children = {
            iconPanel,
            infoPanel,
            UI.Panel { flexDirection = "row", flexWrap = "wrap", width = actionWidth, gap = mobile and 2 or 3, justifyContent = "flex-end", children = actions },
        },
    }
end

local function BuildLibraryTabs()
    local children = {}
    for _, item in ipairs({ { "builtin", "内置" }, { "mine", "我的" }, { "market", "市场" }, { "favorites", "收藏" } }) do
        local tab, label = item[1], item[2]
        children[#children + 1] = ActiveButton(label, state_ and state_.libraryTab == tab, function()
            libraryCategory_ = "全部"
            callbacks_.setLibraryTab(tab)
        end, { flexGrow = 1, flexShrink = 1, height = 30, paddingHorizontal = 2, fontSize = 9 })
    end
    return UI.Panel { width = "100%", paddingHorizontal = 2, flexDirection = "row", gap = 6, children = children }
end

local function BuildCategoryTabs(width)
    local categories = ModelLibraryPresentation.Categories(state_ and state_.assets or {})
    if #categories <= 1 then
        libraryCategory_ = "全部"
        return nil, 0
    end
    local available = math.max(1, width)
    local children = {}
    local valid = libraryCategory_ == "全部"
    for _, category in ipairs(categories) do
        if category == libraryCategory_ then valid = true end
    end
    if not valid then libraryCategory_ = "全部" end
    local tabs = { "全部" }
    for _, category in ipairs(categories) do tabs[#tabs + 1] = category end
    local mobile = profile_ and profile_.mode == "mobile"
    local layout = LibraryCategoryLayout(mobile and "mobile" or "desktop", available, #tabs)
    local gap = layout.gap
    if mobile then
        local tabWidth = layout.tabWidth
        for _, category in ipairs(tabs) do
            children[#children + 1] = ActiveButton(category, libraryCategory_ == category, function()
                libraryCategory_ = category
                IslandUI.Rebuild()
            end, { width = tabWidth, height = 28, paddingHorizontal = 3, fontSize = 8 })
        end
        return RememberedScrollView("library-categories:" .. tostring(state_ and state_.libraryTab or "builtin"), {
            width = available, height = layout.height,
            scrollX = true, scrollY = false, showScrollbar = false,
            padding = 0,
            children = {
                UI.Panel {
                    width = #tabs * tabWidth + math.max(0, #tabs - 1) * gap,
                    height = 30, flexDirection = "row", gap = gap, children = children,
                },
            },
        }), layout.height
    end

    -- Desktop returns to the original compact category grid. Every category is
    -- visible at once, leaving wheel/trackpad scrolling exclusively to assets.
    local columns = layout.columns
    local buttonWidth = layout.tabWidth
    for _, category in ipairs(tabs) do
        children[#children + 1] = ActiveButton(category, libraryCategory_ == category, function()
            libraryCategory_ = category
            IslandUI.Rebuild()
        end, { width = buttonWidth, height = 27, paddingHorizontal = 2, fontSize = 8 })
    end
    return UI.Panel {
        width = available, height = layout.height,
        flexDirection = "row", flexWrap = "wrap", gap = gap, children = children,
    }, layout.height
end

local function AssetCardEstimatedHeight(asset, mobile)
    if asset and asset.source == "mine" then return mobile and 66 or 70 end
    if asset and asset.source == "market" then
        -- The narrow action rail wraps each market action onto its own row.
        -- Include those real rows plus card padding so the explicit scroll
        -- document can never clip the final market/favorite cards.
        local hasThreeActions = asset.license ~= "use_only"
        if mobile then return hasThreeActions and 98 or 70 end
        return hasThreeActions and 112 or 82
    end
    return mobile and 58 or 80
end

local function AssetListContentHeight(assets, columns, gap, mobile, minimum)
    assets = assets or {}
    columns = math.max(1, math.floor(tonumber(columns) or 1))
    gap = math.max(0, tonumber(gap) or 0)
    local total, rowHeight, inRow, rows = 0, 0, 0, 0
    for _, asset in ipairs(assets) do
        rowHeight = math.max(rowHeight, AssetCardEstimatedHeight(asset, mobile))
        inRow = inRow + 1
        if inRow == columns then
            total, rows, rowHeight, inRow = total + rowHeight, rows + 1, 0, 0
        end
    end
    if inRow > 0 then total, rows = total + rowHeight, rows + 1 end
    if rows > 1 then total = total + gap * (rows - 1) end
    return math.max(tonumber(minimum) or 1, total)
end

local function VirtualPoolUpperBound(viewportHeight, itemHeight, itemGap, poolBuffer)
    local rowHeight = math.max(1, (tonumber(itemHeight) or 1) + (tonumber(itemGap) or 0))
    return math.ceil(math.max(0, tonumber(viewportHeight) or 0) / rowHeight)
        + math.max(0, math.floor(tonumber(poolBuffer) or 0)) * 2
end

local function AssetVirtualRows(assets, columns)
    columns = math.max(1, math.floor(tonumber(columns) or 1))
    local rows, row = {}, nil
    for _, asset in ipairs(assets or {}) do
        if not row or #row.items >= columns then
            row = { items = {} }
            rows[#rows + 1] = row
        end
        row.items[#row.items + 1] = asset
    end
    if #rows == 0 then rows[1] = { items = {}, empty = true } end
    return rows
end

local function AssetVirtualRowHeight(assets, mobile)
    local height = mobile and 58 or 80
    for _, asset in ipairs(assets or {}) do
        height = math.max(height, AssetCardEstimatedHeight(asset, mobile))
    end
    return height
end

local function AssetVirtualRowSignature(data)
    if not data or data.empty then return "#empty" end
    local parts = {}
    for _, asset in ipairs(data.items or {}) do
        parts[#parts + 1] = table.concat({
            tostring(asset.assetId or asset.id), tostring(asset.versionId),
            tostring(asset.name), tostring(asset.favorite), tostring(asset.license),
            tostring(asset.withdrawn), tostring(asset.publishedVersion), tostring(asset.featured),
        }, ":")
    end
    return table.concat(parts, "|")
end

local function BuildAssetList(width, height)
    local innerWidth = width - 16
    local columns = AssetListColumns(innerWidth)
    local cardWidth = columns == 1 and innerWidth or (innerWidth - ASSET_ROW_GAP) * 0.5
    local assets = ModelLibraryPresentation.Filter(state_ and state_.assets or {}, nil, libraryCategory_)
    local mobile = profile_ and profile_.mode == "mobile"
    local rowHeight = AssetVirtualRowHeight(assets, mobile)
    local viewportHeight = math.max(1, height - 16)
    local rows = AssetVirtualRows(assets, columns)
    local function CreateRow()
        return UI.Panel {
            width = innerWidth, height = rowHeight,
            flexDirection = "row", alignItems = "stretch", gap = ASSET_ROW_GAP,
        }
    end
    local function BindRow(widget, data)
        local signature = AssetVirtualRowSignature(data)
        if widget._assetVirtualSignature == signature then return end
        widget._assetVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        if data.empty then
            widget:AddChild(UI.Panel {
                width = innerWidth, height = rowHeight, padding = 16,
                alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.soft, borderColor = COLORS.line,
                borderWidth = 1, borderRadius = 14,
                children = { UI.Label {
                    text = state_ and state_.libraryTab == "mine"
                        and "还没有自己的模型，点击“新建模型”开始创作。"
                        or "这个分类暂时没有模型。",
                    fontSize = 10, fontColor = COLORS.muted,
                } },
            })
            return
        end
        for _, asset in ipairs(data.items or {}) do
            local card = BuildAssetCard(asset, cardWidth)
            card:SetStyle({ height = rowHeight, flexShrink = 0 })
            widget:AddChild(card)
        end
    end
    local list = RememberedVirtualList("library-assets:" .. tostring(state_ and state_.libraryTab or "builtin")
        .. ":" .. tostring(libraryCategory_), {
        width = innerWidth,
        height = viewportHeight,
        viewportHeight = viewportHeight,
        data = rows,
        itemHeight = rowHeight,
        itemGap = ASSET_ROW_GAP,
        poolBuffer = ASSET_POOL_BUFFER,
        showScrollbar = true,
        bounces = mobile,
        createItem = CreateRow,
        bindItem = BindRow,
    })
    return UI.Panel {
        width = width, height = height, padding = 8,
        overflow = "hidden", children = { list },
    }
end

local function BuildLibraryPanel(profile, mobile)
    local mobileLeft = mobile and MobileLeftInset(profile) or 0
    local outerGap = mobile and 0 or 12
    local width = mobile and MobilePanelWidth(profile) or (profile.left - outerGap * 2)
    local height = mobile and (profile.height - profile.top - profile.bottom - 10)
        or (profile.height - profile.top - profile.footer - 16)
    local panelPadding = mobile and 10 or 12
    local contentWidth = width - panelPadding * 2
    local categoryTabs, categoryHeight = BuildCategoryTabs(contentWidth)
    local fixedContentHeight = (mobile and 98 or 104) + categoryHeight
    local assetListHeight = math.max(1, height - fixedContentHeight)
    local headerChildren = {
        UI.Label { text = "模型库", flexGrow = 1, fontSize = mobile and 12 or 13, fontWeight = "900", fontColor = COLORS.ink },
        Button("新建模型", callbacks_.newModel, { height = mobile and 28 or 29, paddingHorizontal = 6, backgroundColor = COLORS.soft, borderColor = COLORS.blue }),
    }
    if state_ and state_.libraryTab == "market" then
        headerChildren[#headerChildren + 1] = Button("刷新", callbacks_.refreshMarket, { width = 40, height = mobile and 28 or 29, paddingHorizontal = 1 })
    end
    if mobile then
        headerChildren[#headerChildren + 1] = Button("关闭", function()
            libraryOpen_ = false
            IslandUI.Rebuild()
        end, { width = 44, height = 28, paddingHorizontal = 3 })
    end
    ---@type any[]
    local panelChildren = {
        UI.Panel {
            height = mobile and 32 or 36, flexDirection = "row", alignItems = "center", gap = 8,
            paddingHorizontal = 4,
            children = headerChildren,
        },
        BuildLibraryTabs(),
    }
    if categoryTabs then panelChildren[#panelChildren + 1] = categoryTabs end
    panelChildren[#panelChildren + 1] = BuildAssetList(contentWidth, assetListHeight)
    return UI.Panel {
        position = "absolute",
        left = mobile and mobileLeft or outerGap,
        top = profile.top + (mobile and 5 or 8),
        width = width,
        height = height,
        padding = panelPadding,
        flexDirection = "column",
        gap = mobile and 7 or 9,
        backgroundColor = mobile and COLORS.statusGlass or COLORS.panel,
        backdropBlur = mobile and 12 or 16,
        borderColor = COLORS.line,
        borderWidth = 2,
        borderRadius = 18,
        overflow = "hidden",
        boxShadow = { { x = 0, y = 8, blur = 24, color = COLORS.shadow } },
        children = panelChildren,
    }
end

local function BuildLibraryDismiss(profile)
    if profile.mode ~= "mobile" or not libraryOpen_ then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0,
        top = profile.top, bottom = profile.bottom,
        backgroundColor = COLORS.transparent,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        libraryOpen_ = false
        IslandUI.Rebuild()
    end
    return dismiss
end

local function UpdatedLabel(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 then return "刚刚创建" end
    local ok, value = pcall(os.date, "%m-%d %H:%M", timestamp)
    return ok and ("更新 " .. tostring(value)) or "已保存"
end

local function BuildIslandCard(item, width)
    local mobile = profile_ and profile_.mode == "mobile"
    local cardPadding = mobile and 4 or 12
    local actionHeight = mobile and IslandUI._MobileIslandActionHeight() or 29
    local actionGap = mobile and 2 or 6
    local mobileInnerWidth = math.max(1, width - cardPadding * 2)
    local publishAction = IslandUI._IslandPublishButtonState(item, state_)
    local mobileActionWidth, mobilePublishWidth = IslandUI._MobileIslandActionWidths(
        mobileInnerWidth, actionGap, publishAction.label)
    local actionWidth = mobile and mobileActionWidth or 42
    local publishActionWidth = mobile and mobilePublishWidth or actionWidth
    local renameActionWidth = mobile
        and math.max(38, (mobileInnerWidth - actionGap) * 0.5) or 62
    local renaming = renameIslandId_ == item.id
    local titleControl
    if renaming then
        titleControl = UI.TextField {
            value = renameIslandValue_, flexGrow = 1, minWidth = 0, height = mobile and 27 or 31,
            fontSize = mobile and 9 or 11, backgroundColor = COLORS.white, borderColor = COLORS.blue,
            borderWidth = 2, borderRadius = 10, paddingHorizontal = mobile and 6 or 9,
            onChange = function(_, text) renameIslandValue_ = text end,
            onSubmit = function(_, text)
                renameIslandValue_ = text
                renameIslandId_ = nil
                callbacks_.renameIsland(item.id, renameIslandValue_)
            end,
        }
    else
        titleControl = UI.Panel {
            flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 2,
            children = {
                UI.Label { text = tostring(item.name or "未命名空岛"), fontSize = mobile and 10 or 12,
                    fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                UI.Label {
                    text = mobile and (tostring(item.count or 0) .. " 模型 · "
                            .. (item.published and "已发布" or "未发布"))
                        or (tostring(item.count or 0) .. " 个模型 · "
                            .. (item.published and "已发布 · " or "未发布 · ") .. UpdatedLabel(item.updatedAt)),
                    fontSize = 8, fontColor = COLORS.muted, maxLines = 1,
                },
            },
        }
    end
    local actions = {}
    if renaming then
        actions[#actions + 1] = Button(mobile and "保存" or "保存名称", function()
            renameIslandId_ = nil
            callbacks_.renameIsland(item.id, renameIslandValue_)
        end, { width = renameActionWidth, height = actionHeight, paddingHorizontal = 2,
            fontSize = mobile and 8 or 10, backgroundColor = COLORS.soft, borderColor = COLORS.blue })
        actions[#actions + 1] = Button("取消", function() renameIslandId_ = nil; IslandUI.Rebuild() end,
            { width = renameActionWidth, height = actionHeight, paddingHorizontal = 2, fontSize = mobile and 8 or 10 })
    else
        actions[#actions + 1] = ActiveButton(item.active and "当前" or "打开", item.active, function()
            if not item.active then callbacks_.openIsland(item.id) end
        end, { width = mobile and actionWidth or 44, height = actionHeight, paddingHorizontal = 1,
            fontSize = mobile and 8 or 10, disabled = item.active })
        actions[#actions + 1] = Button("改名", function()
            renameIslandId_, renameIslandValue_, deleteConfirmId_ = item.id, tostring(item.name or ""), nil
            IslandUI.Rebuild()
        end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1, fontSize = mobile and 8 or 10 })
        actions[#actions + 1] = Button("复制", function() callbacks_.duplicateIsland(item.id) end,
            { width = actionWidth, height = actionHeight, paddingHorizontal = 1, fontSize = mobile and 8 or 10 })
        actions[#actions + 1] = Button(publishAction.label, function()
            if publishAction.disabled then return end
            callbacks_.setIslandPublished(item.id, not item.published)
        end, { width = publishActionWidth, height = actionHeight, paddingHorizontal = 1,
            fontSize = mobile and (publishAction.busy and 7 or 8) or 10,
            disabled = publishAction.disabled,
            backgroundColor = publishAction.busy and COLORS.skySoft
                or item.published and COLORS.yellowSoft or COLORS.soft,
            borderColor = publishAction.busy and COLORS.blue
                or item.published and COLORS.gold or COLORS.blue })
        actions[#actions + 1] = Button(deleteConfirmId_ == item.id and "确认" or "删除", function()
            if deleteConfirmId_ == item.id then deleteConfirmId_ = nil; callbacks_.deleteIsland(item.id)
            else deleteConfirmId_ = item.id; IslandUI.Rebuild() end
        end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1,
            fontSize = mobile and 8 or 10, danger = true })
    end
    return UI.Panel {
        width = width,
        height = mobile and MobileIslandCardHeight() or nil,
        minHeight = not mobile and (renaming and 90 or 98) or nil,
        padding = cardPadding, gap = mobile and 5 or 10,
        flexDirection = "column", alignItems = "center", justifyContent = "center",
        backgroundColor = item.active and COLORS.soft or COLORS.surface,
        borderColor = item.active and COLORS.blue or COLORS.line,
        borderWidth = item.active and 2 or 1, borderRadius = 15,
        boxShadow = mobile and false
            or { { x = 0, y = 4, blur = 11, color = COLORS.cardShadow } },
        children = {
            UI.Panel { width = "100%", height = mobile and 29 or nil,
                flexDirection = "row", alignItems = "center", gap = mobile and 5 or 8, children = {
                UI.Panel {
                    width = mobile and 22 or 34, height = mobile and 22 or 34,
                    alignItems = "center", justifyContent = "center",
                    backgroundColor = item.active and COLORS.skySoft or COLORS.yellowSoft,
                    borderColor = item.active and COLORS.blue or COLORS.gold, borderWidth = 2,
                    borderRadius = mobile and 11 or 17,
                    children = { UI.Label { text = "岛", fontSize = mobile and 9 or 13,
                        fontWeight = "900", fontColor = item.active and COLORS.blue or COLORS.gold } },
                },
                titleControl,
            } },
            UI.Panel { width = "100%",
                height = mobile and actionHeight or nil,
                flexDirection = "row", flexWrap = mobile and "nowrap" or "wrap", gap = actionGap,
                alignItems = "center", justifyContent = "center", children = actions },
        },
    }
end

local function BuildExploreDismiss(profile)
    if not exploreOpen_ then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        exploreOpen_ = false
        IslandUI.Rebuild()
    end
    return dismiss
end

local function SortExploreEntries(entries, mode)
    local result = {}
    for _, entry in ipairs(entries or {}) do
        if mode ~= "favorites" or entry.favorite == true then result[#result + 1] = entry end
    end
    table.sort(result, function(a, b)
        if mode == "hot" then
            local aLikes, bLikes = tonumber(a.likes) or 0, tonumber(b.likes) or 0
            if aLikes ~= bLikes then return aLikes > bLikes end
        end
        local aUpdated, bUpdated = tonumber(a.updatedAt) or 0, tonumber(b.updatedAt) or 0
        if aUpdated ~= bUpdated then return aUpdated > bUpdated end
        return tostring(a.id or a.name or "") < tostring(b.id or b.name or "")
    end)
    return result
end

local function BuildExploreCard(entry, width, mobile)
    local sourceLabel = entry.source == "cloud" and "玩家发布" or "离线示范"
    local actionWidth = mobile and math.max(30, math.min(36, (width * 0.42 - 4) / 3)) or 52
    local actionHeight = mobile and 22 or 25
    local avatarSize = mobile and 34 or 42
    local infoChildren = {
        UI.Label { text = tostring(entry.name or "玩家空岛"), fontSize = mobile and 9 or 12,
            fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
        UI.Panel { width = "100%", height = mobile and 20 or 22,
            flexDirection = "row", alignItems = "center", gap = 4,
            backgroundColor = COLORS.transparent, borderWidth = 0,
            children = {
                Social.NicknameButton(entry.owner, entry.ownerId, {
                    height = mobile and 20 or 22, fontSize = mobile and 8 or 9,
                    paddingHorizontal = 0, textColor = COLORS.blueDark,
                }),
                UI.Label { text = "· " .. tostring(entry.count or 0) .. " 模型",
                    flexShrink = 0, fontSize = mobile and 7 or 8,
                    fontColor = COLORS.muted, maxLines = 1 },
            } },
        UI.Label { text = tostring(entry.description or "欢迎来空岛漫游"),
            fontSize = mobile and 8 or 9, fontColor = COLORS.muted, maxLines = 2 },
        UI.Label { text = sourceLabel .. " · " .. tostring(entry.likes or 0) .. " 赞",
            fontSize = mobile and 7 or 8, fontWeight = "bold",
            fontColor = COLORS.blueDark, maxLines = 1 },
    }
    local actions = {
        ActiveButton(entry.liked and "已赞" or "点赞", entry.liked == true, function()
            callbacks_.toggleExploreLike(entry.id)
        end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1, fontSize = mobile and 7 or 8 }),
        ActiveButton(entry.favorite and "已藏" or "收藏", entry.favorite == true, function()
            callbacks_.toggleExploreFavorite(entry.id)
        end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1, fontSize = mobile and 7 or 8 }),
        Button("参观", function()
            exploreOpen_ = false
            callbacks_.visitIsland(entry)
        end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1,
            fontSize = mobile and 7 or 8, backgroundColor = COLORS.blue, hoverBackgroundColor = COLORS.blueDark,
            borderColor = COLORS.blue, textColor = COLORS.white }),
    }
    local identitySnapshot = Social.CopySnapshot(entry)
    identitySnapshot.onClick = function()
        Social.RequestPlayerProfile(entry.ownerId, entry.owner)
    end
    return UI.Panel {
        width = width, height = mobile and 88 or 98,
        padding = mobile and 6 or 9, gap = mobile and 6 or 8,
        flexDirection = "row", alignItems = "center", backgroundColor = COLORS.surface,
        borderColor = entry.source == "cloud" and COLORS.blue or COLORS.gold,
        borderWidth = 1, borderRadius = 15,
        -- Shadows on every moving card force an extra blurred layer on phones.
        -- Desktop keeps the decoration; mobile relies on the existing border.
        boxShadow = mobile and false
            or { { x = 0, y = 4, blur = 11, color = COLORS.cardShadow } },
        children = {
            UI.Panel {
                width = avatarSize, height = avatarSize, flexShrink = 0,
                alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.skySoft, borderColor = COLORS.blue,
                borderWidth = 2, borderRadius = avatarSize * 0.5,
                children = { UI.Avatar(Social.AvatarProps(identitySnapshot,
                    Social.NonEmptyText(entry.owner, "云岛旅人"), avatarSize - 4, COLORS.blue)) },
            },
            UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column",
                gap = mobile and 2 or 3, justifyContent = "center", children = infoChildren },
            UI.Panel { width = mobile and (actionWidth * 3 + 4) or actionWidth, flexShrink = 0,
                flexDirection = ExploreActionDirection(mobile), alignItems = "center",
                gap = mobile and 2 or 4, justifyContent = "center", children = actions },
        },
    }
end

local function BuildExplorePanel(profile)
    if not exploreOpen_ then return nil end
    local mobile = profile.mode == "mobile"
    local left = mobile and MobileLeftInset(profile) or 20
    local width = mobile and MobilePanelWidth(profile) or math.min(460, profile.width - 40)
    local height = profile.height - profile.top - profile.bottom - (mobile and 20 or 32)
    local favoriteCount = 0
    for _, entry in ipairs(exploreEntries_ or {}) do if entry.favorite then favoriteCount = favoriteCount + 1 end end
    local visibleEntries = SortExploreEntries(exploreEntries_, exploreSort_)
    local contentWidth = width - 40
    local cardGap = mobile and 8 or 9
    local cardWidth = contentWidth
    local cardHeight = mobile and 88 or 98
    local virtualData = IslandUI._ExploreListVirtualization.Data(
        visibleEntries, exploreLoading_, exploreSort_)
    local sourceText = exploreSource_ == "cloud" and ("玩家空岛 · " .. tostring(#exploreEntries_) .. " 座")
        or "离线探索示范"
    local headerChildren
    if mobile then
        headerChildren = {
            UI.Label { text = "探索空岛", width = 48, flexShrink = 0,
                fontSize = 12, fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
            ActiveButton("最新", exploreSort_ == "latest", function()
                exploreSort_ = "latest"; IslandUI.Rebuild()
            end, { width = 32, height = 30, paddingHorizontal = 1, fontSize = 8 }),
            ActiveButton("最热", exploreSort_ == "hot", function()
                exploreSort_ = "hot"; IslandUI.Rebuild()
            end, { width = 32, height = 30, paddingHorizontal = 1, fontSize = 8 }),
            ActiveButton("收藏", exploreSort_ == "favorites", function()
                exploreSort_ = "favorites"; IslandUI.Rebuild()
            end, { width = 36, height = 30, paddingHorizontal = 1, fontSize = 8 }),
            Button("刷新", callbacks_.refreshExplore,
                { width = 34, height = 30, paddingHorizontal = 1, fontSize = 8 }),
            Button("关闭", function()
                exploreOpen_ = false
                IslandUI.Rebuild()
            end, { width = 34, height = 30, paddingHorizontal = 1, fontSize = 8 }),
        }
    else
        headerChildren = {
            UI.Panel { width = 32, height = 32, borderRadius = 16, backgroundColor = COLORS.skySoft,
                borderColor = COLORS.blue, borderWidth = 2, alignItems = "center", justifyContent = "center",
                children = { UI.Label { text = "探", fontSize = 12, fontWeight = "900", fontColor = COLORS.blueDark } } },
            UI.Panel { flexGrow = 1, flexDirection = "column", gap = 0, children = {
                UI.Label { text = "探索空岛", fontSize = 14, fontWeight = "900", fontColor = COLORS.ink },
                UI.Label { text = sourceText, fontSize = 8, fontColor = COLORS.muted },
            } },
            Button("刷新", callbacks_.refreshExplore, { width = 42, height = 31, paddingHorizontal = 2 }),
            Button("关闭", function()
                exploreOpen_ = false
                IslandUI.Rebuild()
            end, { width = 42, height = 31, paddingHorizontal = 2 }),
        }
    end
    local panelChildren = {
        UI.Panel { width = "100%", height = mobile and 32 or 38,
            flexDirection = "row", alignItems = "center", gap = mobile and 4 or 8,
            children = headerChildren },
    }
    if not mobile then
        panelChildren[#panelChildren + 1] = UI.Panel {
            width = "100%", height = 31, flexDirection = "row", gap = 7, children = {
                ActiveButton("最新", exploreSort_ == "latest", function()
                    exploreSort_ = "latest"; IslandUI.Rebuild()
                end, { flexGrow = 1, flexShrink = 1, height = 31, paddingHorizontal = 2, fontSize = 9 }),
                ActiveButton("最热", exploreSort_ == "hot", function()
                    exploreSort_ = "hot"; IslandUI.Rebuild()
                end, { flexGrow = 1, flexShrink = 1, height = 31, paddingHorizontal = 2, fontSize = 9 }),
                ActiveButton("收藏 " .. tostring(favoriteCount), exploreSort_ == "favorites", function()
                    exploreSort_ = "favorites"; IslandUI.Rebuild()
                end, { flexGrow = 1, flexShrink = 1, height = 31, paddingHorizontal = 2, fontSize = 9 }),
            },
        }
    end
    local listHeight = math.max(1, height - (mobile and 58 or 105))
    local function CreateExploreRow()
        return UI.Panel {
            width = cardWidth, height = cardHeight, overflow = "hidden",
        }
    end
    local function BindExploreRow(widget, entry)
        local signature = IslandUI._ExploreListVirtualization.Signature(entry)
        if widget._exploreVirtualSignature == signature then return end
        widget._exploreVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        if entry._empty then
            widget:AddChild(UI.Panel {
                width = cardWidth, height = cardHeight, padding = 18,
                alignItems = "center", justifyContent = "center",
                borderRadius = 14, backgroundColor = COLORS.soft,
                borderColor = COLORS.line, borderWidth = 1,
                children = { UI.Label {
                    text = tostring(entry.message or "暂时没有可参观的空岛"),
                    fontSize = 10, fontColor = COLORS.muted,
                } },
            })
        else
            widget:AddChild(BuildExploreCard(entry, cardWidth, mobile))
        end
    end
    local exploreList = RememberedVirtualList("explore:" .. tostring(exploreSort_), {
        width = contentWidth, height = listHeight, viewportHeight = listHeight,
        data = virtualData, itemHeight = cardHeight, itemGap = cardGap,
        poolBuffer = IslandUI._ExploreListVirtualization.POOL_BUFFER,
        showScrollbar = true, bounces = mobile,
        createItem = CreateExploreRow, bindItem = BindExploreRow,
    })
    panelChildren[#panelChildren + 1] = UI.Panel {
        width = width - 28, height = listHeight, paddingHorizontal = 6,
        overflow = "hidden", children = { exploreList },
    }
    return UI.Panel {
        position = "absolute", left = left, top = profile.top + (mobile and 10 or 16),
        width = width, height = height, padding = 14, gap = mobile and 8 or 12, flexDirection = "column",
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel, backdropBlur = 16,
        borderColor = COLORS.line, borderWidth = 2, borderRadius = 20, overflow = "hidden",
        boxShadow = { { x = 0, y = 10, blur = 30, color = COLORS.shadow } },
        children = panelChildren,
    }
end

local function TerrainCardColumns(width)
    return width >= 330 and 2 or 1
end

local function BuildTerrainPreview(preset, width, height)
    local previewHeight = tonumber(height) or 58
    local islands = preset and preset.islands or {}
    local children, byId = {}, {}
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, island in ipairs(islands) do
        local rx = tonumber(island.radiusX or island.radius) or 1
        local rz = tonumber(island.radiusZ or island.radius) or 1
        minX, maxX = math.min(minX, (island.x or 0) - rx), math.max(maxX, (island.x or 0) + rx)
        minZ, maxZ = math.min(minZ, (island.z or 0) - rz), math.max(maxZ, (island.z or 0) + rz)
        byId[tostring(island.id)] = island
    end
    if #islands == 0 then minX, maxX, minZ, maxZ = -1, 1, -1, 1 end
    local innerWidth, innerHeight = math.max(30, width - 16), previewHeight - 12
    local scale = math.min(innerWidth / math.max(1, maxX - minX), innerHeight / math.max(1, maxZ - minZ))
    local offsetX = 8 + (innerWidth - (maxX - minX) * scale) * 0.5
    local offsetY = 6 + (innerHeight - (maxZ - minZ) * scale) * 0.5
    local function Center(island)
        return offsetX + ((island.x or 0) - minX) * scale,
            offsetY + ((island.z or 0) - minZ) * scale
    end
    for _, bridge in ipairs(preset and preset.bridges or {}) do
        local first, second = byId[tostring(bridge.from)], byId[tostring(bridge.to)]
        if first and second then
            local x1, y1 = Center(first)
            local x2, y2 = Center(second)
            local dx, dy = x2 - x1, y2 - y1
            children[#children + 1] = UI.Panel {
                position = "absolute", left = (x1 + x2) * 0.5 - math.sqrt(dx * dx + dy * dy) * 0.5,
                top = (y1 + y2) * 0.5 - 1.5,
                width = math.sqrt(dx * dx + dy * dy), height = 3,
                rotate = math.deg(math.atan(dy, dx)),
                backgroundColor = COLORS.gold, borderRadius = 2, pointerEvents = "none",
            }
        end
    end
    local islandTones = { COLORS.green, COLORS.blue, COLORS.gold, COLORS.blueDark, COLORS.green }
    for index, island in ipairs(islands) do
        local x, y = Center(island)
        local islandWidth = math.max(9, (tonumber(island.radiusX or island.radius) or 1) * 2 * scale)
        local islandHeight = math.max(7, (tonumber(island.radiusZ or island.radius) or 1) * 2 * scale)
        local elevated = math.abs(tonumber(island.groundY) or 0.42) > 1.25
        children[#children + 1] = UI.Panel {
            position = "absolute", left = x - islandWidth * 0.5, top = y - islandHeight * 0.5,
            width = islandWidth, height = islandHeight,
            backgroundColor = islandTones[(index - 1) % #islandTones + 1],
            borderColor = elevated and COLORS.white or COLORS.soft,
            borderWidth = elevated and 2 or 1,
            borderRadius = math.min(islandWidth, islandHeight) * 0.5,
            boxShadow = { { x = 0, y = elevated and 4 or 2, blur = 5, color = COLORS.cardShadow } },
            pointerEvents = "none",
        }
    end
    return UI.Panel {
        width = width, height = previewHeight, position = "relative", overflow = "hidden",
        backgroundColor = COLORS.skySoft, borderColor = COLORS.line, borderWidth = 1, borderRadius = 12,
        pointerEvents = "none", children = children,
    }
end

local function CommitTerrainRename(terrainId, value)
    local name = tostring(value or "")
    -- Clear editing state before the synchronous callback refreshes world/UI
    -- state, otherwise that refresh can rebuild the old TextField once more.
    terrainRenameId_, terrainRenameValue_ = nil, ""
    local renamed = callbacks_.renameRandomTerrain
        and callbacks_.renameRandomTerrain(terrainId, name) == true
    if not renamed then
        terrainRenameId_, terrainRenameValue_ = terrainId, name
    end
    if terrainOpen_ then IslandUI.Rebuild() end
    return renamed == true
end

local function BuildTerrainCard(summary, width)
    local preset = IslandTerrainCatalog.Get(summary) or summary
    local id = ResolveTerrainId(preset)
    local selected = id == ResolveTerrainId(terrainSelectedId_)
    local current = id == CurrentTerrainId()
    local mobile = profile_ and profile_.mode == "mobile"
    local islandCount = tonumber(summary.islandCount) or #(preset.islands or {})
    local generated = preset.generated == true or summary.generated == true
    local locked = summary.locked == true
    local renaming = generated and terrainRenameId_ == id
    local inUseCount = tonumber(summary.inUseCount) or 0
    local previewWidth, previewHeight = mobile and 56 or 62, mobile and 52 or 56
    local compactManagement = generated and not renaming
    local actionHeight = compactManagement and 26 or mobile and 34 or 32
    local detail = generated
        and ("随机 · " .. tostring(islandCount) .. " 岛 · 种子 "
            .. tostring(preset.seed or summary.seed or "-")
            .. (inUseCount > 0 and (" · 使用 " .. tostring(inUseCount)) or ""))
        or tostring(preset.description or (tostring(islandCount) .. " 座空岛"))

    local info
    local actions = {}
    if renaming then
        info = UI.TextField {
            value = terrainRenameValue_, flexGrow = 1, minWidth = 0, height = actionHeight,
            fontSize = 9, backgroundColor = COLORS.white, borderColor = COLORS.blue,
            borderWidth = 2, borderRadius = 8, paddingHorizontal = 6,
            onChange = function(_, text) terrainRenameValue_ = text end,
            onSubmit = function(_, text)
                terrainRenameValue_ = text
                CommitTerrainRename(id, terrainRenameValue_)
            end,
        }
        actions = {
            Button("保存", function() CommitTerrainRename(id, terrainRenameValue_) end,
                { width = mobile and 38 or 42, height = actionHeight, paddingHorizontal = 1, fontSize = 8,
                    backgroundColor = COLORS.blue, borderColor = COLORS.blue, textColor = COLORS.white }),
            Button("取消", function()
                terrainRenameId_, terrainRenameValue_ = nil, ""
                IslandUI.Rebuild()
            end, { width = mobile and 38 or 42, height = actionHeight, paddingHorizontal = 1, fontSize = 8 }),
        }
    else
        info = UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 2,
            justifyContent = "center", children = {
                UI.Label { text = tostring(preset.name or "空岛地形"), fontSize = mobile and 10 or 11,
                    fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                not (mobile and generated) and UI.Label {
                    text = (locked and "看视频解锁 · " or "") .. detail,
                    fontSize = 8, fontColor = locked and COLORS.gold or COLORS.muted, maxLines = 1,
                } or nil,
                mobile and generated and locked and UI.Label {
                    text = "看视频解锁", fontSize = 8, fontWeight = "900",
                    fontColor = COLORS.gold, maxLines = 1,
                } or nil,
            } }
        if generated then
            local actionWidth = 58
            local renameLabel, regenerateLabel, deleteLabel = TerrainManagementLabels(inUseCount)
            actions = {
                Button(renameLabel, function()
                    terrainFeedback_ = ""
                    terrainRenameId_, terrainRenameValue_ = id, tostring(preset.name or "随机地形")
                    IslandUI.Rebuild()
                end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1, fontSize = 8 }),
                Button(regenerateLabel, function()
                    if inUseCount == 0 then
                        local nextId = callbacks_.regenerateRandomTerrain
                            and callbacks_.regenerateRandomTerrain(id) or nil
                        if nextId and terrainOpen_ then
                            terrainSelectedId_, terrainRenameId_, terrainRenameValue_, terrainFeedback_ =
                                nextId, nil, "", ""
                            IslandUI.Rebuild()
                        end
                    end
                end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1, fontSize = 8,
                    backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
                    disabled = inUseCount > 0 }),
                Button(deleteLabel, function()
                    if inUseCount == 0 and callbacks_.deleteRandomTerrain
                        and callbacks_.deleteRandomTerrain(id) == true and terrainOpen_ then
                        if ResolveTerrainId(terrainSelectedId_) == id then
                            terrainSelectedId_ = IslandTerrainCatalog.DEFAULT_ID
                        end
                        terrainRenameId_, terrainRenameValue_, terrainFeedback_ = nil, "", ""
                        IslandUI.Rebuild()
                    end
                end, { width = actionWidth, height = actionHeight, paddingHorizontal = 1,
                    fontSize = 8, danger = inUseCount == 0, disabled = inUseCount > 0 }),
            }
        else
            local badge = locked and "视频解锁"
                or current and "当前" or selected and "已选" or tostring(islandCount) .. "岛"
            actions = {
                UI.Panel { width = locked and 52 or 42, height = 28, flexShrink = 0,
                    alignItems = "center", justifyContent = "center",
                    backgroundColor = locked and COLORS.yellowSoft or selected and COLORS.skySoft or COLORS.yellowSoft,
                    borderColor = locked and COLORS.gold or selected and COLORS.blue or COLORS.gold,
                    borderWidth = 1, borderRadius = 9,
                    pointerEvents = "none", children = {
                        UI.Label { text = badge, fontSize = 8, fontWeight = "900",
                            fontColor = locked and COLORS.gold or selected and COLORS.blueDark or COLORS.muted },
                    } },
            }
        end
    end

    return UI.Panel {
        width = width, height = compactManagement and 100 or mobile and 68 or 72, padding = 6, gap = 7,
        flexDirection = "row", alignItems = "center",
        backgroundColor = selected and COLORS.soft or COLORS.surface,
        borderColor = selected and COLORS.blue or current and COLORS.gold or COLORS.line,
        borderWidth = selected and 2 or 1, borderRadius = 13,
        boxShadow = mobile and false
            or { { x = 0, y = 3, blur = 8, color = COLORS.cardShadow } },
        pointerEvents = "auto",
        onClick = function()
            terrainSelectedId_ = id
            terrainFeedback_ = ""
            if locked and callbacks_.openTerrainReward then
                callbacks_.openTerrainReward(id, terrainPurpose_)
            elseif not selected then
                IslandUI.Rebuild()
            end
        end,
        children = {
            BuildTerrainPreview(preset, previewWidth, previewHeight),
            info,
            UI.Panel { flexShrink = 0, flexDirection = compactManagement and "column" or "row", alignItems = "center",
                gap = 2, children = actions },
        },
    }
end

local function BuildAutoBuildAssetCard(asset, width)
    local selected = autoBuildSelection_[AssetSelectionKey(asset)] == true
    local previewSize = profile_ and profile_.mode == "mobile" and 38 or 44
    local previewChildren = (not asset.thumbnail or asset.thumbnail == "")
        and ModelMiniatureChildren(asset, previewSize, 18) or {}
    return UI.Panel {
        width = width, height = profile_ and profile_.mode == "mobile" and 58 or 64,
        padding = 7, gap = 8, flexDirection = "row", alignItems = "center",
        backgroundColor = selected and COLORS.soft or COLORS.surface,
        borderColor = selected and COLORS.blue or COLORS.line,
        borderWidth = selected and 2 or 1, borderRadius = 13,
        children = {
            UI.Panel {
                width = previewSize, height = previewSize, flexShrink = 0,
                alignItems = "center", justifyContent = "center",
                backgroundImage = asset.thumbnail, backgroundFit = "contain",
                backgroundColor = COLORS.skySoft, borderColor = COLORS.line,
                borderWidth = 1, borderRadius = 9, children = previewChildren,
            },
            UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 2,
                justifyContent = "center", children = {
                    UI.Label { text = tostring(asset.name or "模型"), fontSize = 10,
                        fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                    UI.Label { text = tostring(asset.category or "模型") .. " · "
                            .. tostring(asset.count or 0) .. " 组件",
                        fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                } },
            ActiveButton(selected and "已选" or "选择", selected, function()
                    autoBuildSelection_[AssetSelectionKey(asset)] = not selected or nil
                    autoBuildSelectionInitialized_ = true
                    IslandUI.Rebuild()
                end, { width = profile_ and profile_.mode == "mobile" and 38 or 36,
                    height = profile_ and profile_.mode == "mobile" and 30 or 27,
                    paddingHorizontal = 1, fontSize = 8 }),
        },
    }
end

local function BuildAutoBuildDismiss(profile)
    if not autoBuildOpen_ then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        CloseAutoBuild()
    end
    return dismiss
end

local function BuildAutoBuildPanel(profile)
    if not autoBuildOpen_ then return nil end
    local mobile = profile.mode == "mobile"
    local width = mobile and MobilePanelWidth(profile) or math.min(700, profile.width - 48)
    local modalTop = mobile and MobileModalTop(profile) or (profile.top + 14)
    local modalBottom = mobile and MobileBottomInset(profile) or (profile.footer + 14)
    local availableHeight = math.max(1, profile.height - modalTop - modalBottom)
    local height = math.min(availableHeight, mobile and math.max(360, availableHeight * 0.82) or 560)
    local left = mobile and MobileLeftInset(profile) or (profile.width - width) * 0.5
    local top = modalTop + math.max(0, (availableHeight - height) * 0.5)
    local contentWidth, gap = width - 28, 8
    local innerWidth = contentWidth - 12
    local columns = contentWidth >= 430 and 2 or 1
    local cardWidth = (innerWidth - gap * (columns - 1)) / columns
    local assets = AutoBuildAssets()
    local rows = AssetVirtualRows(assets, columns)
    local rowHeight = mobile and 58 or 64
    local selectedCount, totalCount = AutoBuildSelectionCount(), #assets
    local listHeight = math.max(1, height - (mobile and 124 or 120))
    local function CreateAutoBuildRow()
        return UI.Panel {
            width = innerWidth, height = rowHeight,
            flexDirection = "row", alignItems = "stretch", gap = gap,
        }
    end
    local function BindAutoBuildRow(widget, row)
        local signatureParts = {}
        for _, asset in ipairs(row.items or {}) do
            signatureParts[#signatureParts + 1] = tostring(asset.assetId or asset.id)
                .. ":" .. tostring(asset.versionId) .. ":"
                .. tostring(autoBuildSelection_[AssetSelectionKey(asset)] == true)
        end
        local signature = row.empty and "#empty" or table.concat(signatureParts, "|")
        if widget._autoBuildVirtualSignature == signature then return end
        widget._autoBuildVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        if row.empty then
            widget:AddChild(UI.Panel {
                width = innerWidth, height = rowHeight, padding = 14,
                alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.soft, borderColor = COLORS.line,
                borderWidth = 1, borderRadius = 14,
                children = { UI.Label { text = "模型库为空，请先创建或恢复模型。",
                    fontSize = 10, fontColor = COLORS.muted } },
            })
            return
        end
        for _, asset in ipairs(row.items or {}) do
            local card = BuildAutoBuildAssetCard(asset, cardWidth)
            card:SetStyle({ height = rowHeight, flexShrink = 0 })
            widget:AddChild(card)
        end
    end
    local autoBuildList = RememberedVirtualList("auto-build", {
        width = innerWidth, height = listHeight, viewportHeight = listHeight,
        data = rows, itemHeight = rowHeight, itemGap = gap,
        poolBuffer = 2, showScrollbar = true, bounces = mobile,
        createItem = CreateAutoBuildRow, bindItem = BindAutoBuildRow,
    })
    return UI.Panel {
        position = "absolute", left = left, top = top, width = width, height = height,
        padding = 14, gap = 9, flexDirection = "column", overflow = "hidden",
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel, backdropBlur = 16,
        borderColor = COLORS.gold, borderWidth = 2, borderRadius = 20,
        boxShadow = { { x = 0, y = 10, blur = 30, color = COLORS.shadow } },
        children = {
            UI.Panel { width = "100%", height = 38, flexDirection = "row", alignItems = "center", gap = 5,
                children = {
                    UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 0,
                        children = {
                            UI.Label { text = "一键建岛", fontSize = mobile and 12 or 15,
                                fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                            UI.Label { text = "已选 " .. tostring(selectedCount) .. "/" .. tostring(totalCount),
                                fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                        } },
                    Button("全选", function() SetAllAutoBuildAssets(true); IslandUI.Rebuild() end,
                        { width = mobile and 40 or 48, height = 31, paddingHorizontal = 1,
                            fontSize = 8, backgroundColor = COLORS.soft, borderColor = COLORS.blue }),
                    Button("清空", function() SetAllAutoBuildAssets(false); IslandUI.Rebuild() end,
                        { width = mobile and 40 or 48, height = 31, paddingHorizontal = 1, fontSize = 8 }),
                    Button("关闭", CloseAutoBuild, { width = 44, height = 31, paddingHorizontal = 3 }),
                } },
            UI.Panel { width = contentWidth, height = listHeight, padding = 6,
                overflow = "hidden", children = { autoBuildList } },
            UI.Panel { width = "100%", height = mobile and 40 or 36, flexDirection = "row", gap = 8,
                children = {
                    Button("取消", CloseAutoBuild, { width = mobile and 62 or 72,
                        height = mobile and 40 or 36 }),
                    Button(selectedCount > 0 and ("生成优美空岛 · " .. tostring(selectedCount) .. " 种模型")
                            or "请先勾选模型", function()
                        local selected = {}
                        for _, asset in ipairs(AutoBuildAssets()) do
                            if autoBuildSelection_[AssetSelectionKey(asset)] then
                                selected[#selected + 1] = {
                                    assetId = asset.assetId or asset.id, versionId = asset.versionId,
                                }
                            end
                        end
                        if #selected > 0 and callbacks_.autoBuildIsland
                            and callbacks_.autoBuildIsland(selected) == true then CloseAutoBuild() end
                    end, {
                        flexGrow = 1, flexShrink = 1, height = mobile and 40 or 36,
                        disabled = selectedCount == 0,
                        backgroundColor = selectedCount > 0 and COLORS.blue or COLORS.soft,
                        hoverBackgroundColor = COLORS.blueDark,
                        borderColor = selectedCount > 0 and COLORS.blue or COLORS.line,
                        textColor = selectedCount > 0 and COLORS.white or COLORS.muted,
                    }),
                } },
        },
    }
end

local function BuildResetConfirmationDismiss(profile)
    if not resetConfirmOpen_ then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        CloseResetConfirmation()
    end
    return dismiss
end

local function BuildResetConfirmationPanel(profile)
    if not resetConfirmOpen_ then return nil end
    local mobile = profile.mode == "mobile"
    local width = mobile and math.min(MobilePanelWidth(profile), 390)
        or math.min(420, profile.width - 48)
    local buttonHeight = mobile and 40 or 36
    return UI.Panel {
        position = "absolute", left = (profile.width - width) * 0.5,
        top = profile.top + math.max(12,
            (profile.height - profile.top - profile.bottom - 220) * 0.34),
        width = width, padding = mobile and 16 or 18, gap = 12,
        flexDirection = "column", alignItems = "stretch",
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel, backdropBlur = 16,
        borderColor = COLORS.dangerLine, borderWidth = 2, borderRadius = 20,
        boxShadow = { { x = 0, y = 10, blur = 30, color = COLORS.shadow } },
        children = {
            UI.Label { text = "重新建设当前空岛？", fontSize = mobile and 16 or 18,
                fontWeight = "900", fontColor = COLORS.ink, textAlign = "center" },
            UI.Label {
                text = "确认后会清理当前空岛上的全部模型；成对云门的另一端也会同步移除。地形与空岛名称会保留。",
                fontSize = mobile and 10 or 11, fontColor = COLORS.muted,
                whiteSpace = "normal", textAlign = "center",
            },
            UI.Label { text = "该操作不可通过撤销恢复", fontSize = 9,
                fontWeight = "bold", fontColor = COLORS.danger, textAlign = "center" },
            UI.Panel { width = "100%", flexDirection = "row", gap = 8, children = {
                Button("取消", CloseResetConfirmation,
                    { flexGrow = 1, flexShrink = 1, height = buttonHeight }),
                Button("确认清空", function()
                    resetConfirmOpen_ = false
                    if callbacks_.clearIsland then callbacks_.clearIsland() end
                    IslandUI.Rebuild()
                end, { flexGrow = 1, flexShrink = 1, height = buttonHeight, danger = true }),
            } },
        },
    }
end

local function BuildPortalBindingDismiss(profile)
    if not portalBindingOpen_ then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        ClosePortalBinding()
    end
    return dismiss
end

local function BuildPortalBindingPanel(profile)
    if not portalBindingOpen_ or not state_ or not state_.selected or not state_.selected.isPortal then return nil end
    local mobile = profile.mode == "mobile"
    local width = mobile and MobilePanelWidth(profile) or math.min(460, profile.width - 48)
    local choices = {}
    for _, island in ipairs(state_.islands or {}) do
        if not island.active then choices[#choices + 1] = island end
    end
    if #choices == 0 then
        choices[1] = { _empty = true }
    end
    local margin = mobile and 8 or 16
    local availableHeight = math.max(1, profile.height - profile.top - profile.bottom - margin * 2)
    local height = math.min(mobile and 440 or 500, 124 + #choices * 67, availableHeight)
    local listWidth = width - 32
    local listHeight = math.max(36, height - 86)
    local rowHeight = 58
    local function CreatePortalChoiceRow()
        return UI.Panel { width = listWidth, height = rowHeight, overflow = "hidden" }
    end
    local function BindPortalChoiceRow(widget, island)
        local isCurrentTarget = not island._empty
            and tostring(island.id) == tostring(state_.selected.portalTargetIslandId or "")
        local signature = island._empty and "#empty" or table.concat({
            tostring(island.id), tostring(island.name), tostring(island.terrainName),
            tostring(island.count), tostring(isCurrentTarget),
        }, ":")
        if widget._portalVirtualSignature == signature then return end
        widget._portalVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        if island._empty then
            widget:AddChild(UI.Panel { width = listWidth, height = rowHeight, padding = 10,
                alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.soft, borderColor = COLORS.line,
                borderWidth = 1, borderRadius = 14,
                children = { UI.Label {
                    text = "还没有另一座空岛。请先新建一座，再回来绑定。",
                    fontSize = 9, fontColor = COLORS.muted, maxLines = 2,
                } },
            })
            return
        end
        widget:AddChild(UI.Panel {
            width = listWidth, height = rowHeight, padding = 9, gap = 9,
            flexDirection = "row", alignItems = "center",
            backgroundColor = isCurrentTarget and COLORS.soft or COLORS.surface,
            borderColor = isCurrentTarget and COLORS.gold or COLORS.line,
            borderWidth = isCurrentTarget and 2 or 1, borderRadius = 14,
            children = {
                UI.Panel { width = 34, height = 34, borderRadius = 17,
                    backgroundColor = COLORS.skySoft, borderColor = COLORS.blue, borderWidth = 1,
                    alignItems = "center", justifyContent = "center",
                    children = { UI.Label { text = "岛", fontSize = 12,
                        fontWeight = "900", fontColor = COLORS.blueDark } } },
                UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 1,
                    children = {
                        UI.Label { text = tostring(island.name or "空岛"), fontSize = 11,
                            fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                        UI.Label { text = tostring(island.terrainName or "空岛地形") .. " · "
                                .. tostring(island.count or 0) .. " 个模型",
                            fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                    } },
                Button(isCurrentTarget and "重新连接" or "连接", function()
                    if callbacks_.bindPortal
                        and callbacks_.bindPortal(state_.selected.id, island.id) == true then
                        ClosePortalBinding()
                    end
                end, { width = isCurrentTarget and 68 or 50, height = 32,
                    backgroundColor = isCurrentTarget and COLORS.yellowSoft or COLORS.blue,
                    borderColor = isCurrentTarget and COLORS.gold or COLORS.blue,
                    textColor = isCurrentTarget and COLORS.blueDark or COLORS.white }),
            },
        })
    end
    local portalList = RememberedVirtualList("portal-bind", {
        width = listWidth, height = listHeight, viewportHeight = listHeight,
        data = choices, itemHeight = rowHeight, itemGap = 8,
        poolBuffer = 2, showScrollbar = true, bounces = mobile,
        createItem = CreatePortalChoiceRow, bindItem = BindPortalChoiceRow,
    })
    return UI.Panel {
        position = "absolute", left = mobile and MobileLeftInset(profile) or (profile.width - width) * 0.5,
        top = profile.top + margin + math.max(0,
            (availableHeight - height) * 0.35),
        width = width, height = height, padding = 14, gap = 10,
        flexDirection = "column", overflow = "hidden",
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel, backdropBlur = 16,
        borderColor = COLORS.gold, borderWidth = 2, borderRadius = 20,
        boxShadow = { { x = 0, y = 10, blur = 30, color = COLORS.shadow } },
        children = {
            UI.Panel { width = "100%", height = 42, flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Panel { width = 34, height = 34, borderRadius = 12,
                        backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold, borderWidth = 2,
                        alignItems = "center", justifyContent = "center",
                        children = { UI.Label { text = "门", fontSize = 13, fontWeight = "900", fontColor = COLORS.blueDark } } },
                    UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 0,
                        children = {
                            UI.Label { text = "连接另一座空岛", fontSize = 14, fontWeight = "900", fontColor = COLORS.ink },
                            UI.Label { text = "另一端会自动放到目标空岛的安全位置",
                                fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                        } },
                    Button("关闭", ClosePortalBinding, { width = 44, height = 31, paddingHorizontal = 3 }),
                } },
            UI.Panel { width = width - 28, height = listHeight, padding = 2,
                overflow = "hidden", children = { portalList } },
        },
    }
end

function IslandUI._BuildTerrainDiscoveryDismiss(profile)
    if terrainDiscovery_.phase ~= "open" then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = IslandUI._HandleTerrainDiscoveryBackdropPointer
    return dismiss
end

function IslandUI._HandleTerrainDiscoveryBackdropPointer()
    if callbacks_ and callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
    -- The discovery card is intentional onboarding, so outside taps only
    -- absorb scene input. Closing stays explicit via “关闭” or “知道了”.
    return false
end

function IslandUI._BuildTerrainDiscoveryPanel(profile)
    local flying = terrainDiscovery_.phase == "flying"
    if terrainDiscovery_.phase ~= "open" and not flying then return nil end
    local mobile = profile.mode == "mobile"
    local geometry = TerrainDiscoveryGuide.PanelGeometry(profile)
    local compact = geometry.height < 200
    local headerHeight = compact and 30 or 34
    local footerHeight = compact and 32 or 36
    local closeButton = Button("关闭", IslandUI.CloseTerrainDiscovery, {
        width = mobile and 48 or 50, height = headerHeight,
        paddingHorizontal = 5, fontSize = 9,
        backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.line,
    })
    local checkbox = UI.Checkbox {
        checked = terrainDiscovery_.doNotRemind, label = "不再提醒",
        width = mobile and 102 or 112, height = footerHeight,
        size = mobile and 18 or 17, gap = 6,
        fontSize = mobile and 10 or 9,
        onChange = function(_, checked)
            if not flying then terrainDiscovery_.doNotRemind = checked == true end
        end,
    }
    local card = UI.Panel {
        width = geometry.width, height = geometry.height,
        padding = mobile and 13 or 15, gap = compact and 6 or 8,
        flexDirection = "column", overflow = "hidden",
        pointerEvents = flying and "none" or "auto",
        transformOrigin = "center",
        backgroundColor = COLORS.panelGlass, backdropBlur = 18,
        borderColor = COLORS.gold, borderWidth = 2, borderRadius = mobile and 19 or 22,
        boxShadow = { { x = 0, y = 12, blur = 34, color = COLORS.shadow } },
        children = {
            UI.Panel { width = "100%", height = headerHeight, flexShrink = 0,
                flexDirection = "row", alignItems = "center", gap = 8, children = {
                    UI.Label { text = "新内容", width = mobile and 48 or 52, height = 24,
                        paddingHorizontal = 6, textAlign = "center",
                        fontSize = 8, fontWeight = "900", fontColor = COLORS.blueDark,
                        backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
                        borderWidth = 1, borderRadius = 12 },
                    UI.Label { text = "发现多种空岛地形", flexGrow = 1, flexShrink = 1,
                        fontSize = mobile and 14 or 15, fontWeight = "900",
                        fontColor = COLORS.ink, maxLines = 1 },
                    closeButton,
                } },
            UI.Panel { width = "100%", flexGrow = 1, minHeight = 0,
                paddingHorizontal = mobile and 10 or 12,
                paddingVertical = compact and 6 or 9,
                gap = compact and 3 or 5, flexDirection = "column",
                justifyContent = "center",
                backgroundColor = COLORS.skySoft, borderColor = COLORS.blue,
                borderWidth = 1, borderRadius = 13, children = {
                    UI.Label { text = "经典三岛之外，还有螺旋群岛、云阶、随机地形等选择。",
                        fontSize = mobile and 10 or 11, fontWeight = "bold",
                        fontColor = COLORS.ink, whiteSpace = "normal", maxLines = 2 },
                    UI.Label { text = "点击左上角“地形”，选择后可在新建空岛时使用。",
                        fontSize = mobile and 9 or 10, fontColor = COLORS.blueDark,
                        whiteSpace = "normal", maxLines = 2 },
                } },
            UI.Panel { width = "100%", height = footerHeight, flexShrink = 0,
                flexDirection = "row", alignItems = "center", gap = 8, children = {
                    checkbox,
                    UI.Panel { flexGrow = 1, height = 1, pointerEvents = "none" },
                    Button("知道了", IslandUI.CloseTerrainDiscovery, {
                        width = mobile and 72 or 78, height = footerHeight,
                        paddingHorizontal = 7, fontSize = 10,
                        backgroundColor = COLORS.blue, hoverBackgroundColor = COLORS.blueDark,
                        borderColor = COLORS.blue, textColor = COLORS.white,
                    }),
                } },
        },
    }
    local carrier = UI.Panel {
        position = "absolute", left = geometry.left, top = geometry.top,
        width = geometry.width, height = geometry.height,
        pointerEvents = flying and "none" or "box-none",
        transformOrigin = "center", children = { card },
    }
    terrainDiscovery_.carrier, terrainDiscovery_.card = carrier, card
    return carrier
end

local function BuildTerrainDismiss(profile)
    if not terrainOpen_ then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        CloseTerrainPicker()
    end
    return dismiss
end

local function BuildTerrainPanel(profile)
    if not terrainOpen_ then return nil end
    local mobile = profile.mode == "mobile"
    local width = TerrainPanelWidth(profile.width, mobile, MobilePanelWidth(profile))
    local modalTop = mobile and MobileModalTop(profile) or (profile.top + 16)
    local modalBottom = mobile and MobileBottomInset(profile) or (profile.footer + 16)
    local availableHeight = math.max(1, profile.height - modalTop - modalBottom)
    local height = math.min(availableHeight,
        mobile and math.max(360, availableHeight * 0.94) or 500)
    local left = mobile and MobileLeftInset(profile) or (profile.width - width) * 0.5
    local top = modalTop + math.max(0, (availableHeight - height) * 0.5)
    local padding = mobile and 12 or 14
    local contentWidth = width - padding * 2
    local innerWidth = contentWidth - 8
    local columns = mobile and 1 or TerrainCardColumns(innerWidth)
    local gap = 9
    local cardWidth = (innerWidth - gap * (columns - 1)) / columns
    local presets = TerrainPresets()
    local terrainRows = AssetVirtualRows(presets, columns)
    local selectedId = ResolveTerrainId(terrainSelectedId_)
    local applyingCurrent = terrainPurpose_ == "manage" and selectedId == CurrentTerrainId()
    local selectedLocked = TerrainLocked(selectedId)
    local actionText = selectedLocked and "观看视频解锁"
        or terrainPurpose_ == "create" and "下一步" or applyingCurrent and "当前地形" or "应用地形"
    local terrainHint = terrainFeedback_ ~= "" and terrainFeedback_
        or terrainPurpose_ == "create" and "新建空岛后，将应用选择的地形"
        or "新建空岛时，会应用选择的地形"
    local function CreateRandomTerrain()
        local terrainId = callbacks_.createRandomTerrain and callbacks_.createRandomTerrain() or nil
        if terrainId and terrainOpen_ then
            terrainSelectedId_, terrainRenameId_, terrainRenameValue_, terrainFeedback_ = terrainId, nil, "", ""
            IslandUI.Rebuild()
        end
    end
    local rowHeight = 100
    local listHeight = math.max(1, height - (mobile and 122 or 126))
    local function CreateTerrainRow()
        return UI.Panel { width = innerWidth, height = rowHeight,
            flexDirection = "row", alignItems = "stretch", gap = gap }
    end
    local function BindTerrainRow(widget, row)
        local signatureParts = {}
        for _, preset in ipairs(row.items or {}) do
            local id = ResolveTerrainId(preset)
            signatureParts[#signatureParts + 1] = table.concat({
                tostring(id), tostring(preset.name), tostring(preset.locked),
                tostring(preset.inUseCount), tostring(id == selectedId),
                tostring(terrainRenameId_ == id),
            }, ":")
        end
        local signature = row.empty and "#empty" or table.concat(signatureParts, "|")
        if widget._terrainVirtualSignature == signature then return end
        widget._terrainVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        if row.empty then
            widget:AddChild(UI.Panel { width = innerWidth, height = rowHeight,
                alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.soft, borderColor = COLORS.line,
                borderWidth = 1, borderRadius = 13,
                children = { UI.Label { text = "暂时没有可用地形",
                    fontSize = 10, fontColor = COLORS.muted } },
            })
            return
        end
        for _, preset in ipairs(row.items or {}) do
            local card = BuildTerrainCard(preset, cardWidth)
            card:SetStyle({ height = rowHeight, flexShrink = 0 })
            widget:AddChild(card)
        end
    end
    local terrainList = RememberedVirtualList("terrain:" .. tostring(terrainPurpose_), {
        width = innerWidth, height = listHeight, viewportHeight = listHeight,
        data = terrainRows, itemHeight = rowHeight, itemGap = gap,
        poolBuffer = 2, showScrollbar = true, bounces = mobile,
        createItem = CreateTerrainRow, bindItem = BindTerrainRow,
    })
    return UI.Panel {
        position = "absolute", left = left, top = top, width = width, height = height,
        padding = padding, gap = mobile and 8 or 10, flexDirection = "column", overflow = "hidden",
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel, backdropBlur = 16,
        borderColor = COLORS.gold, borderWidth = 2, borderRadius = 20,
        boxShadow = { { x = 0, y = 10, blur = 30, color = COLORS.shadow } },
        children = {
            UI.Panel { width = "100%", height = 44, flexShrink = 0,
                flexDirection = "row", alignItems = "center", gap = 8, children = {
                UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 0, children = {
                    UI.Label { text = terrainPurpose_ == "create" and "新建空岛 · 选择地形" or "选择空岛地形",
                        fontSize = mobile and 12 or 14, fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                    UI.Label { text = terrainHint, fontSize = 8,
                        fontWeight = terrainFeedback_ ~= "" and "bold" or "normal",
                        fontColor = terrainFeedback_ ~= "" and COLORS.danger or COLORS.muted,
                        whiteSpace = "normal", maxLines = 2 },
                } },
                Button("生成随机", CreateRandomTerrain, { width = mobile and 68 or 78, height = 32,
                    paddingHorizontal = 2, fontSize = 8, backgroundColor = COLORS.blue,
                    hoverBackgroundColor = COLORS.blueDark, borderColor = COLORS.blue, textColor = COLORS.white }),
                Button("关闭", CloseTerrainPicker, { width = 44, height = 31, paddingHorizontal = 3 }),
            } },
            UI.Panel { width = contentWidth, height = listHeight, padding = 4,
                overflow = "hidden", children = { terrainList } },
            UI.Panel { width = "100%", height = mobile and 38 or 34, flexShrink = 0,
                flexDirection = "row", gap = 8, children = {
                Button("取消", CloseTerrainPicker, { width = mobile and 62 or 70, height = mobile and 38 or 34 }),
                Button(actionText, function()
                    if selectedLocked then
                        if callbacks_.openTerrainReward then
                            callbacks_.openTerrainReward(selectedId, terrainPurpose_)
                        end
                    elseif terrainPurpose_ == "create" then
                        terrainOpen_, terrainPurpose_, terrainSelectedId_ = false, "manage", nil
                        terrainFeedback_ = ""
                        if callbacks_.openNewIslandReward then
                            callbacks_.openNewIslandReward(selectedId)
                        end
                    elseif not applyingCurrent then
                        local applied, failureMessage
                        if callbacks_.applyTerrain then
                            applied, failureMessage = callbacks_.applyTerrain(selectedId)
                        end
                        -- Applying may recreate the whole IslandUI synchronously. Only
                        -- close this surface when the original picker still exists.
                        if applied == true and terrainOpen_ then
                            CloseTerrainPicker()
                        elseif applied ~= true and terrainOpen_ then
                            terrainFeedback_ = tostring(failureMessage
                                or "当前空岛无法应用该地形，请新建空岛后选择")
                            IslandUI.Rebuild()
                        end
                    end
                end, {
                    flexGrow = 1, flexShrink = 1, height = mobile and 38 or 34,
                    disabled = applyingCurrent,
                    backgroundColor = applyingCurrent and COLORS.soft or COLORS.blue,
                    hoverBackgroundColor = COLORS.blueDark,
                    borderColor = applyingCurrent and COLORS.line or COLORS.blue,
                    textColor = applyingCurrent and COLORS.muted or COLORS.white,
                }),
            } },
        },
    }
end

local function BuildRewardGateDismiss(profile)
    if not RewardGateOpen() then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim, pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        if not RewardGateBusy() then CloseRewardGate() end
    end
    return dismiss
end

local function BuildRewardGatePanel(profile)
    if not RewardGateOpen() then return nil end
    local mobile = profile.mode == "mobile"
    local gate = rewardGateState_
    local phase = tostring(gate.phase or "prompt")
    local busy = RewardGateBusy()
    local feedback = tostring(gate.feedback or gate.message or "")
    local failed = feedback ~= ""
    local width = mobile and math.min(304,
        profile.width - (profile.safe.left or 0) - (profile.safe.right or 0) - 48)
        or math.min(400, profile.width - 40)
    local buttonHeight = mobile and 38 or 34
    local modalTop = mobile and MobileModalTop(profile) or profile.top
    local availableHeight = profile.height - modalTop - (mobile and MobileBottomInset(profile) or profile.bottom)
    local statusText = (phase == "queued" or phase == "waiting") and "正在准备视频，请稍候…"
        or phase == "playing" and "视频播放中，请完整观看…"
        or failed and feedback
        or tostring(gate.statusText or "完整观看视频后即可获得奖励")
    local statusColor = failed and COLORS.danger or COLORS.blueDark
    local detail = tostring(gate.detail or gate.subject or "")
    return UI.Panel {
        position = "absolute", left = (profile.width - width) * 0.5,
        top = modalTop + math.max(12, availableHeight * 0.22),
        width = width, padding = mobile and 14 or 18, gap = mobile and 8 or 12,
        flexDirection = "column", alignItems = "stretch",
        backgroundColor = COLORS.panel, backdropBlur = 16,
        borderColor = COLORS.gold, borderWidth = 2, borderRadius = 20,
        boxShadow = { { x = 0, y = 10, blur = 30, color = COLORS.shadow } },
        children = {
            UI.Panel { width = "100%", height = 32, flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Label { text = tostring(gate.title or "观看视频解锁"), flexGrow = 1,
                        fontSize = mobile and 14 or 18,
                        fontWeight = "900", fontColor = COLORS.ink, textAlign = "left" },
                    Button("关闭", CloseRewardGate, { width = 44, height = 30,
                        paddingHorizontal = 2, fontSize = 8, disabled = busy }),
                } },
            UI.Label {
                text = tostring(gate.description or "观看一段激励视频，完整播放后即可继续。"),
                fontSize = mobile and 10 or 11, fontColor = COLORS.muted, whiteSpace = "normal", textAlign = "center",
            },
            detail ~= "" and UI.Label { text = detail,
                fontSize = 10, fontWeight = "bold", fontColor = COLORS.blueDark, textAlign = "center" },
            UI.Panel { width = "100%", minHeight = 30, paddingHorizontal = 8, paddingVertical = 6,
                alignItems = "center", justifyContent = "center",
                backgroundColor = busy and COLORS.skySoft or failed and COLORS.coralSoft or COLORS.soft,
                borderColor = busy and COLORS.blue or failed and COLORS.dangerLine or COLORS.line,
                borderWidth = 1, borderRadius = 10, children = {
                    UI.Label { text = statusText, fontSize = 9, fontWeight = "bold",
                        fontColor = statusColor, textAlign = "center", whiteSpace = "normal", maxLines = 2 },
                } },
            UI.Panel { width = "100%", flexDirection = "row", gap = 8, children = {
                Button("暂不观看", CloseRewardGate, {
                    flexGrow = 1, flexShrink = 1, height = buttonHeight,
                    disabled = busy,
                }),
                Button(busy and "正在打开视频…" or failed and "重新尝试"
                        or tostring(gate.confirmLabel or "观看视频解锁"), function()
                    if busy then return end
                    if callbacks_.confirmRewardGate then callbacks_.confirmRewardGate() end
                end, {
                    flexGrow = 1, flexShrink = 1, height = buttonHeight,
                    disabled = busy,
                    backgroundColor = COLORS.blue, hoverBackgroundColor = COLORS.blueDark,
                    borderColor = COLORS.blue, textColor = COLORS.white,
                }),
            } },
        },
    }
end

local function BuildIslandManagerDismiss(profile)
    if not islandManagerOpen_ then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = profile.top, bottom = profile.bottom,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim, pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        islandManagerOpen_, renameIslandId_, deleteConfirmId_ = false, nil, nil
        IslandUI.Rebuild()
    end
    return dismiss
end

local function BuildIslandManager(profile)
    if not islandManagerOpen_ then return nil end
    local mobile = profile.mode == "mobile"
    local left = mobile and MobileLeftInset(profile) or 20
    local width = mobile and MobilePanelWidth(profile) or math.min(440, profile.width - 40)
    local height = profile.height - profile.top - profile.bottom - (mobile and 20 or 32)
    local panelPadding = mobile and 10 or 14
    local scrollPadding = mobile and 4 or 6
    local listWidth = width - panelPadding * 2
    local gridWidth = listWidth - scrollPadding * 2
    local columns = IslandManagerColumns(profile.mode)
    local cardGap = mobile and 6 or 9
    local cardWidth = (gridWidth - cardGap * (columns - 1)) / columns
    local islands = state_ and state_.islands or {}
    local islandRows = AssetVirtualRows(islands, columns)
    local rowHeight = mobile and MobileIslandCardHeight() or 98
    local listHeight = math.max(1, height - (mobile and 56 or 66))
    local function CreateIslandRow()
        return UI.Panel { width = gridWidth, height = rowHeight,
            flexDirection = "row", alignItems = "stretch", gap = cardGap }
    end
    local function BindIslandRow(widget, row)
        local signatureParts = {}
        for _, item in ipairs(row.items or {}) do
            signatureParts[#signatureParts + 1] = table.concat({
                tostring(item.id), tostring(item.name), tostring(item.active),
                tostring(item.published), tostring(item.count), tostring(item.updatedAt),
                tostring(renameIslandId_ == item.id), tostring(deleteConfirmId_ == item.id),
                tostring(state_ and state_.islandMarketSyncBusy),
                tostring(state_ and state_.islandMarketSyncIslandId),
            }, ":")
        end
        local signature = row.empty and "#empty" or table.concat(signatureParts, "|")
        if widget._islandVirtualSignature == signature then return end
        widget._islandVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        if row.empty then
            widget:AddChild(UI.Panel { width = gridWidth, height = rowHeight,
                alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.soft, borderColor = COLORS.line,
                borderWidth = 1, borderRadius = 15,
                children = { UI.Label { text = "还没有空岛，点击上方新建。",
                    fontSize = 10, fontColor = COLORS.muted } },
            })
            return
        end
        for _, item in ipairs(row.items or {}) do
            local card = BuildIslandCard(item, cardWidth)
            card:SetStyle({ height = rowHeight, minHeight = rowHeight, flexShrink = 0 })
            widget:AddChild(card)
        end
    end
    local islandList = RememberedVirtualList("island-manager", {
        width = gridWidth, height = listHeight, viewportHeight = listHeight,
        data = islandRows, itemHeight = rowHeight, itemGap = cardGap,
        poolBuffer = 2, showScrollbar = true, bounces = mobile,
        createItem = CreateIslandRow, bindItem = BindIslandRow,
    })
    return UI.Panel {
        position = "absolute", left = left, top = profile.top + (mobile and 10 or 16),
        width = width, height = height, padding = panelPadding, gap = mobile and 8 or 12, flexDirection = "column",
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel, backdropBlur = 16,
        borderColor = COLORS.line, borderWidth = 2, borderRadius = 20,
        overflow = "hidden",
        boxShadow = { { x = 0, y = 10, blur = 30, color = COLORS.shadow } },
        children = {
            UI.Panel { width = "100%", height = 38, flexDirection = "row", alignItems = "center", gap = 8, children = {
                UI.Panel { width = 32, height = 32, borderRadius = 16, backgroundColor = COLORS.yellowSoft,
                    borderColor = COLORS.gold, borderWidth = 2, alignItems = "center", justifyContent = "center",
                    children = { UI.Label { text = "岛", fontSize = 12, fontWeight = "900", fontColor = COLORS.blueDark } } },
                UI.Panel { flexGrow = 1, flexDirection = "column", gap = 0, children = {
                    UI.Label { text = "我的空岛", fontSize = 14, fontWeight = "900", fontColor = COLORS.ink },
                    UI.Label { text = tostring(#islands) .. " 座独立空岛", fontSize = 8, fontColor = COLORS.muted },
                } },
                Button("＋ 新建", function()
                    OpenTerrainPicker("create")
                end, { width = 58, height = 31, paddingHorizontal = 3, backgroundColor = COLORS.blue, hoverBackgroundColor = COLORS.blueDark, borderColor = COLORS.blue, textColor = COLORS.white }),
                mobile and Button("关闭", function()
                    islandManagerOpen_, renameIslandId_, deleteConfirmId_ = false, nil, nil
                    IslandUI.Rebuild()
                end, { width = 44, height = 31, paddingHorizontal = 3 }) or nil,
            } },
            UI.Panel { width = listWidth, height = listHeight, padding = scrollPadding,
                overflow = "hidden", children = { islandList } },
        },
    }
end

local function BuildTopBar(profile)
    if state_ and state_.visitMode then
        local mobile = profile.mode == "mobile"
        titleLabel_ = UI.Label { text = state_.visitName or state_.name or "玩家空岛",
            flexGrow = 1, flexShrink = 1, fontSize = mobile and 10 or 12, fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 }
        if mobile then
            local actionGap = 4
            local actionWidth = math.max(34, math.min(54,
                (MobilePanelWidth(profile) - actionGap * 4) / 5))
            local actionGroupWidth = actionWidth * 5 + actionGap * 4
            return UI.Panel {
                position = "absolute", left = MobileLeftInset(profile), top = profile.mobileHeaderTop,
                width = MobilePanelWidth(profile), height = 78,
                backgroundColor = COLORS.transparent, borderWidth = 0,
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        position = "absolute", left = 0, top = 0,
                        width = actionGroupWidth, height = 38,
                        flexDirection = "row", alignItems = "center", gap = actionGap,
                        backgroundColor = COLORS.transparent, borderWidth = 0,
                        pointerEvents = "box-none",
                        children = {
                            Button("返回", callbacks_.leaveVisit, {
                                width = actionWidth, height = 38, flexShrink = 0,
                                paddingHorizontal = 10, fontSize = 10,
                            }),
                            Button("探索更多", callbacks_.exploreMore, {
                                width = actionWidth, height = 38, flexShrink = 0,
                                paddingHorizontal = 3, fontSize = 8,
                                backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
                            }),
                            Button("留言板", Social.RequestGuestbook, {
                                width = actionWidth, height = 38, flexShrink = 0,
                                paddingHorizontal = 3, fontSize = 8,
                                backgroundColor = COLORS.soft, borderColor = COLORS.blue,
                            }),
                            Button("暂停", function() IslandUI.SetPaused(true) end, {
                                width = actionWidth, height = 38, flexShrink = 0,
                                paddingHorizontal = 8, fontSize = 9,
                                backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.gold,
                            }),
                            Button("漫游", callbacks_.enterFirstPerson, {
                                width = actionWidth, height = 38, flexShrink = 0,
                                paddingHorizontal = 10, fontSize = 10,
                                backgroundColor = COLORS.soft, borderColor = COLORS.blue,
                            }),
                        },
                    },
                    UI.Panel {
                        position = "absolute", left = 0, top = 44,
                        width = math.max(120, profile.width - MobileLeftInset(profile) - profile.nativeMenuRight),
                        height = 30, flexDirection = "column", justifyContent = "center",
                        backgroundColor = COLORS.transparent, borderWidth = 0,
                        pointerEvents = "box-none", children = {
                            titleLabel_,
                            UI.Panel { height = 17, flexDirection = "row", alignItems = "center", gap = 1,
                                backgroundColor = COLORS.transparent, borderWidth = 0,
                                pointerEvents = "box-none", children = {
                                    UI.Label { text = "正在参观 ·", flexShrink = 0,
                                        fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                                    Social.PlayerIdentity(state_.visitOwner,
                                        state_.visitOwnerId or state_.ownerId,
                                        { avatar = state_.visitAvatar }, {
                                            height = 22, avatarSize = 20, fontSize = 8, gap = 4,
                                        }),
                                } },
                        },
                    },
                },
            }
        end
        return UI.Panel {
            position = "absolute", left = 0, top = 0, right = 0, height = profile.top,
            flexDirection = "row", alignItems = "center", gap = 7,
            paddingLeft = 14 + profile.safe.left,
            paddingRight = 14 + profile.safe.right,
            paddingTop = 7, paddingBottom = 6,
            backgroundColor = COLORS.chrome, backdropBlur = 16,
            borderBottomColor = COLORS.line, borderBottomWidth = 2,
            boxShadow = { { x = 0, y = 5, blur = 16, color = COLORS.topShadow } },
            pointerEvents = "auto",
            children = {
                Button("← 返回", callbacks_.leaveVisit, { width = 62, height = 32, paddingHorizontal = 2 }),
                Button("探索更多", callbacks_.exploreMore, {
                    width = 72, height = 32, paddingHorizontal = 2,
                    backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
                }),
                Button("留言板", Social.RequestGuestbook, {
                    width = 56, height = 32, paddingHorizontal = 3,
                    backgroundColor = COLORS.soft, borderColor = COLORS.blue,
                }),
                UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 0,
                    paddingHorizontal = 0, borderRadius = 0,
                    backgroundColor = COLORS.transparent,
                    borderColor = COLORS.transparent, borderWidth = 0, children = {
                    titleLabel_,
                    UI.Panel { height = 18, flexDirection = "row", alignItems = "center", gap = 1,
                        backgroundColor = COLORS.transparent, borderWidth = 0,
                        pointerEvents = "box-none", children = {
                            UI.Label { text = "正在参观 ·", flexShrink = 0,
                                fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                            Social.PlayerIdentity(state_.visitOwner,
                                state_.visitOwnerId or state_.ownerId,
                                { avatar = state_.visitAvatar }, {
                                    height = 22, avatarSize = 20, fontSize = 8, gap = 4,
                                }),
                        } },
                } },
                Button("漫游", callbacks_.enterFirstPerson, { width = 48, height = 32, paddingHorizontal = 2,
                    backgroundColor = COLORS.soft, borderColor = COLORS.blue }),
                Button("暂停", function() IslandUI.SetPaused(true) end, {
                    width = 50, height = 32, paddingHorizontal = 8,
                    backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.gold,
                }),
            },
        }
    end
    local compactMobile = profile.mode == "mobile"
    undoButton_ = Button("撤销", callbacks_.undo, {
        width = compactMobile and MOBILE_HEADER_BUTTON_WIDTH or 42, flexGrow = nil,
        flexShrink = 0, height = compactMobile and 32 or 32,
        paddingHorizontal = compactMobile and 6 or 2,
        fontSize = compactMobile and 9 or 10,
    })
    redoButton_ = Button("重做", OpenResetConfirmation, {
        width = compactMobile and MOBILE_HEADER_BUTTON_WIDTH or 42, flexGrow = nil,
        flexShrink = 0, height = compactMobile and 32 or 32,
        paddingHorizontal = compactMobile and 6 or 2,
        fontSize = compactMobile and 9 or 10,
    })
    titleLabel_ = UI.Label { text = state_ and state_.name or "我的空岛",
        flexShrink = compactMobile and 1 or 0,
        fontSize = compactMobile and 10 or 13, fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 }
    countLabel_ = UI.Label { text = compactMobile and VERSION
            or (tostring(state_ and state_.count or 0) .. " 个模型"),
        flexShrink = compactMobile and 1 or 0, fontSize = 8, fontWeight = "bold", fontColor = COLORS.muted, maxLines = 1 }
    local title
    if compactMobile then
        title = UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, height = 34,
            flexDirection = "column", justifyContent = "center", gap = 0,
            backgroundColor = COLORS.transparent, borderWidth = 0, pointerEvents = "none",
            children = { titleLabel_, countLabel_ } }
    else
        title = UI.Panel {
            width = profile.mode == "mobile" and 108 or 188,
            flexShrink = 1, flexDirection = "row", alignItems = "center", gap = 7,
            children = {
                UI.Panel { width = 32, height = 32, flexShrink = 0, borderRadius = 16,
                    backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold, borderWidth = 2,
                    alignItems = "center", justifyContent = "center",
                    children = { UI.Label { text = "岛", fontSize = 12, fontWeight = "900", fontColor = COLORS.blueDark } } },
                UI.Panel { flexGrow = 1, flexShrink = 1, flexDirection = "column", gap = 0,
                    children = { titleLabel_, countLabel_ } },
            },
        }
    end
    terrainButton_ = ActiveButton("地形", terrainOpen_, function() OpenTerrainPicker("manage") end, {
        width = compactMobile and MOBILE_HEADER_TERRAIN_WIDTH or 50,
        flexGrow = nil, flexShrink = 0,
        height = compactMobile and 34 or 32, paddingHorizontal = compactMobile and 8 or 4,
        fontSize = compactMobile and 10 or 10,
        backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
        boxShadow = { { x = 0, y = 3, blur = 9, color = COLORS.accentShadow } },
    })
    autoBuildButton_ = ActiveButton(AutoBuildButtonLabel(compactMobile),
        autoBuildOpen_, OpenAutoBuild, {
            width = compactMobile and MOBILE_HEADER_HOME_BUILD_WIDTH or 72,
            flexGrow = nil, flexShrink = 0,
            height = compactMobile and 34 or 32,
            paddingHorizontal = compactMobile and 8 or 5,
            fontSize = compactMobile and 10 or 9,
            backgroundColor = COLORS.yellowSoft, hoverBackgroundColor = COLORS.gold,
            borderColor = COLORS.gold, textColor = COLORS.blueDark,
            boxShadow = { { x = 0, y = 4, blur = 12, color = COLORS.accentShadow } },
        })
    local firstPersonEntry = FirstPersonEntryMetrics(profile.mode)
    ---@type any[]
    local children = { title, terrainButton_ }
    if profile.mode ~= "mobile" then
        children[#children + 1] = autoBuildButton_
        children[#children + 1] = Button("模型库", function() exploreOpen_, islandManagerOpen_ = false, false; libraryOpen_ = not libraryOpen_; IslandUI.Rebuild() end, { width = 50 })
        children[#children + 1] = Button("新建模型", callbacks_.newModel, { width = 60, backgroundColor = COLORS.soft })
        children[#children + 1] = Button("我的空岛", function() exploreOpen_, libraryOpen_ = false, false; islandManagerOpen_ = not islandManagerOpen_; IslandUI.Rebuild() end, { width = 62 })
        children[#children + 1] = Button("探索", function()
            libraryOpen_, islandManagerOpen_, exploreOpen_ = false, false, not exploreOpen_
            IslandUI.Rebuild()
            if exploreOpen_ then callbacks_.refreshExplore() end
        end, { width = 44, backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold })
        children[#children + 1] = Button("留言板", Social.RequestGuestbook, {
            width = 50, minWidth = 38, flexShrink = 1,
            paddingHorizontal = 3, backgroundColor = COLORS.soft, borderColor = COLORS.blue,
        })
        children[#children + 1] = Button("第一人称 P/Esc", function()
            libraryOpen_, islandManagerOpen_, exploreOpen_ = false, false, false
            callbacks_.enterFirstPerson()
        end, { width = firstPersonEntry.width, flexShrink = 0,
            paddingHorizontal = firstPersonEntry.padding, fontSize = 9,
            backgroundColor = COLORS.soft, borderColor = COLORS.blue })
        children[#children + 1] = Button("暂停", function() IslandUI.SetPaused(true) end, {
            width = 50, flexShrink = 0, paddingHorizontal = 8,
            backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.gold,
        })
    end
    local saveButton = Button("保存", callbacks_.save, {
        width = compactMobile and MOBILE_HEADER_BUTTON_WIDTH or 42, flexGrow = nil,
        flexShrink = 0, height = compactMobile and 32 or 32,
        paddingHorizontal = compactMobile and 6 or 7,
        fontSize = compactMobile and 9 or 10,
        backgroundColor = COLORS.soft, borderColor = COLORS.blue,
    })
    local pauseButton = compactMobile and Button("暂停", function() IslandUI.SetPaused(true) end, {
        width = MOBILE_HEADER_BUTTON_WIDTH, height = 32, flexShrink = 0,
        paddingHorizontal = 6, fontSize = 9,
        backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.gold,
    }) or nil
    children[#children + 1] = saveButton
    children[#children + 1] = undoButton_
    children[#children + 1] = redoButton_
    if profile.mode ~= "mobile" then
        children[#children + 1] = UI.Spacer()
        children[#children + 1] = Button("等轴", function() callbacks_.setView("iso") end, { width = 42 })
        children[#children + 1] = Button("顶部", function() callbacks_.setView("top") end, { width = 42 })
    end
    if compactMobile then
        return UI.Panel {
            position = "absolute", left = 0, right = 0, top = 0,
            height = profile.mobileHeaderTop + 72,
            backgroundColor = COLORS.transparent, borderWidth = 0,
            pointerEvents = "box-none",
            children = {
                UI.Panel {
                    position = "absolute", left = MobileLeftInset(profile), top = profile.mobileHeaderTop,
                    width = MobilePanelWidth(profile), height = 36,
                    flexDirection = "row", alignItems = "center", gap = MOBILE_HEADER_GAP,
                    backgroundColor = COLORS.transparent, borderWidth = 0,
                    pointerEvents = "box-none",
                    children = MobileHeaderChildren(title, terrainButton_, autoBuildButton_),
                },
                UI.Panel {
                    position = "absolute", right = MobileRightInset(profile),
                    top = profile.mobileHeaderTop + 38,
                    width = MOBILE_HEADER_BUTTON_WIDTH * 4 + MOBILE_HEADER_GAP * 3, height = 34,
                    flexDirection = "row", alignItems = "center", gap = MOBILE_HEADER_GAP,
                    backgroundColor = COLORS.transparent, borderWidth = 0,
                    pointerEvents = "box-none",
                    children = MobileHeaderUtilityChildren(saveButton, undoButton_, redoButton_, pauseButton),
                },
            },
        }
    end
    return UI.Panel {
        position = "absolute", left = 0, top = 0, right = 0, height = profile.top,
        flexDirection = "row", alignItems = "center", gap = 8,
        paddingLeft = 14 + profile.safe.left,
        paddingRight = 14 + profile.safe.right,
        paddingTop = 7,
        paddingBottom = 6,
        backgroundColor = COLORS.chrome, backdropBlur = 16,
        borderBottomColor = COLORS.line, borderBottomWidth = 2,
        boxShadow = { { x = 0, y = 5, blur = 16, color = COLORS.topShadow } },
        pointerEvents = "auto",
        children = children,
    }
end

local function ActionGrid(children)
    return UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 7, children = children }
end

local function BuildPortalInspectorActions(selected)
    if not selected or not selected.isPortal then return UI.Panel { width = "100%", height = 0 } end
    local actions = {}
    if selected.portalBound then
        actions[#actions + 1] = Button("进入《" .. tostring(selected.portalTargetName or "另一座空岛") .. "》",
            callbacks_.enterPortal, { flexGrow = 1, flexShrink = 1,
                backgroundColor = COLORS.blue, borderColor = COLORS.blue, textColor = COLORS.white })
    end
    actions[#actions + 1] = Button(selected.portalBound and "重新绑定" or "绑定另一座空岛",
        OpenPortalBinding, { flexGrow = 1, flexShrink = 1,
            backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold })
    return UI.Panel { width = "100%", flexDirection = "column", gap = 7,
        children = {
            UI.Label { text = selected.portalBound
                    and ("成对云门 · 已连接 " .. tostring(selected.portalTargetName or "另一座空岛"))
                or "成对云门 · 等待连接另一座空岛",
                fontSize = 9, fontWeight = "900", fontColor = COLORS.blueDark, maxLines = 2 },
            ActionGrid(actions),
        } }
end

local function BuildInspector(profile)
    if not state_ or not state_.selected or profile.mode ~= "desktop" then return nil end
    local selected = state_.selected
    selectionLabel_ = UI.Label {
        text = selected.name,
        fontSize = 14, fontWeight = "900", fontColor = COLORS.ink, maxLines = 2,
    }
    selectionTransformLabel_ = UI.Label {
        text = string.format("X %.2f · Y %.2f · Z %.2f\n旋转 %.0f° · 等比 %.2f",
            selected.x, selected.y or 0, selected.z, selected.rotationY, selected.scale),
        fontSize = 10, fontColor = COLORS.muted,
    }
    return UI.Panel {
        position = "absolute", right = 12, top = profile.top + 12,
        width = profile.right - 24, bottom = profile.footer + 12,
        padding = 14, flexDirection = "column", gap = 11,
        backgroundColor = COLORS.panel, backdropBlur = 14,
        borderColor = COLORS.line, borderWidth = 2, borderRadius = 18,
        overflow = "hidden",
        boxShadow = { { x = 0, y = 8, blur = 24, color = COLORS.shadow } },
        children = {
            UI.Panel { width = "100%", height = 27, flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Panel { width = 24, height = 24, borderRadius = 12, backgroundColor = COLORS.yellowSoft,
                        alignItems = "center", justifyContent = "center",
                        children = { UI.Label { text = "✦", fontSize = 11, fontWeight = "900", fontColor = COLORS.gold } } },
                    UI.Label { text = "完整模型", fontSize = 10, fontWeight = "900", fontColor = COLORS.blueDark },
                } },
            selectionLabel_,
            selectionTransformLabel_,
            UI.Label { text = "整模型工具", fontSize = 10, fontWeight = "900", fontColor = COLORS.ink },
            ActionGrid({
                ActiveButton("移动 W", state_.transformMode == "translate", function() callbacks_.setTransformMode("translate") end, { flexGrow = 1, flexShrink = 1 }),
                ActiveButton("旋转 E", state_.transformMode == "rotate", function() callbacks_.setTransformMode("rotate") end, { flexGrow = 1, flexShrink = 1 }),
                ActiveButton("缩放 R", state_.transformMode == "scale", function() callbacks_.setTransformMode("scale") end, { flexGrow = 1, flexShrink = 1 }),
            }),
            UI.Panel { height = 1, width = "100%", backgroundColor = COLORS.line },
            UI.Label { text = "地面微调", fontSize = 10, fontWeight = "900", fontColor = COLORS.ink },
            ActionGrid({
                Button("← X", function() callbacks_.transformSelected("x", -0.25) end, { flexGrow = 1, flexShrink = 1 }),
                Button("X →", function() callbacks_.transformSelected("x", 0.25) end, { flexGrow = 1, flexShrink = 1 }),
                Button("← Z", function() callbacks_.transformSelected("z", -0.25) end, { flexGrow = 1, flexShrink = 1 }),
                Button("Z →", function() callbacks_.transformSelected("z", 0.25) end, { flexGrow = 1, flexShrink = 1 }),
            }),
            UI.Label { text = "旋转与尺寸", fontSize = 10, fontWeight = "900", fontColor = COLORS.ink },
            ActionGrid({
                Button("左转 Q", function() callbacks_.transformSelected("rotate", -15) end, { flexGrow = 1, flexShrink = 1 }),
                Button("右转 T", function() callbacks_.transformSelected("rotate", 15) end, { flexGrow = 1, flexShrink = 1 }),
                Button("缩小", function() callbacks_.transformSelected("scale", -0.1) end, { flexGrow = 1, flexShrink = 1 }),
                Button("放大", function() callbacks_.transformSelected("scale", 0.1) end, { flexGrow = 1, flexShrink = 1 }),
            }),
            UI.Label { text = "离地高度", fontSize = 10, fontWeight = "900", fontColor = COLORS.ink },
            ActionGrid({
                Button("降低", function() callbacks_.transformSelected("y", -0.1) end, { flexGrow = 1, flexShrink = 1 }),
                Button("升高", function() callbacks_.transformSelected("y", 0.1) end, { flexGrow = 1, flexShrink = 1 }),
            }),
            UI.Spacer(),
            BuildPortalInspectorActions(selected),
            Button(selected.isPortal and "传送机关作为整体使用"
                or selected.canCustomize and "在工作台中定制此实例" or "作者仅允许整体使用", callbacks_.editSelected, {
                width = "100%", height = 36, disabled = selected.isPortal or not selected.canCustomize,
                backgroundColor = not selected.isPortal and selected.canCustomize and COLORS.blue or COLORS.soft,
                hoverBackgroundColor = not selected.isPortal and selected.canCustomize and COLORS.blueDark or COLORS.soft,
                textColor = not selected.isPortal and selected.canCustomize and COLORS.white or COLORS.muted,
                borderColor = not selected.isPortal and selected.canCustomize and COLORS.blue or COLORS.line,
            }),
            ActionGrid({
                Button("复制", callbacks_.duplicate, { flexGrow = 1, flexShrink = 1 }),
                Button("删除", callbacks_.deleteSelected, { flexGrow = 1, flexShrink = 1, danger = true }),
            }),
        },
    }
end

local function BuildContextBar(profile)
    if not state_ then return nil end
    local mobile = profile.mode == "mobile"
    if mobile and libraryOpen_ then return nil end
    local bottom = mobile and profile.bottom or profile.footer + 8
    if state_.mode == "place" then
        local valid = state_.placementValid == true
        local labels = IslandUI._PlacementControlLabels(mobile)
        placementStatusLabel_ = UI.Label {
            text = mobile and (valid and "可放" or "不可")
                or (valid and "点击草地放置" or "当前位置不可放置"),
            flexGrow = 1, flexShrink = 1, fontSize = 10, fontWeight = "900",
            fontColor = valid and COLORS.green or COLORS.danger,
            maxLines = 1,
        }
        if mobile then
            placementConfirmButton_ = Button(labels.confirm, callbacks_.confirmPlacement, {
                width = 34, flexGrow = 1, flexShrink = 1, height = 36,
                paddingHorizontal = 1, fontSize = 8, disabled = not valid,
                backgroundColor = COLORS.blue, borderColor = COLORS.blue, textColor = COLORS.white,
            })
            placementPanel_ = UI.Panel {
                position = "absolute",
                left = MobileLeftInset(profile), right = MobileRightInset(profile),
                bottom = MobileBottomInset(profile), height = 48,
                padding = 5, flexDirection = "row", alignItems = "center", gap = 3,
                backgroundColor = COLORS.surfaceGlass, backdropBlur = 12,
                borderColor = valid and COLORS.green or COLORS.danger,
                borderWidth = 2, borderRadius = 16,
                boxShadow = { { x = 0, y = 8, blur = 24, color = COLORS.shadow } },
                children = {
                    UI.Panel {
                        width = 32, flexGrow = 1, flexShrink = 1, height = 36,
                        alignItems = "center", justifyContent = "center", pointerEvents = "none",
                        children = { placementStatusLabel_ },
                    },
                    Button(labels.switchModel, IslandUI._OpenPlacementModelLibrary, {
                        width = 38, flexGrow = 1, flexShrink = 1, height = 36,
                        paddingHorizontal = 1, fontSize = 8,
                        backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
                    }),
                    Button(labels.rotateLeft, function() callbacks_.rotatePlacement(-15) end, {
                        width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8,
                    }),
                    Button(labels.rotateRight, function() callbacks_.rotatePlacement(15) end, {
                        width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8,
                    }),
                    Button(labels.scaleDown, function() callbacks_.scalePlacement(-0.1) end, {
                        width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8,
                    }),
                    Button(labels.scaleUp, function() callbacks_.scalePlacement(0.1) end, {
                        width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8,
                    }),
                    placementConfirmButton_,
                    Button(labels.close, callbacks_.cancelPlacement, {
                        width = 34, flexGrow = 1, flexShrink = 1, height = 36,
                        paddingHorizontal = 1, fontSize = 8, backgroundColor = COLORS.soft,
                    }),
                },
            }
            return placementPanel_
        end
        placementPanel_ = UI.Panel {
            position = "absolute", left = profile.left + 16, right = profile.right + 16, bottom = bottom,
            height = 50, padding = 8, flexDirection = "row", alignItems = "center", gap = 7,
            backgroundColor = COLORS.panel, backdropBlur = 14, borderColor = valid and COLORS.green or COLORS.danger,
            borderWidth = 2, borderRadius = 16,
            boxShadow = { { x = 0, y = 7, blur = 20, color = COLORS.shadow } },
            children = {
                placementStatusLabel_,
                Button(labels.switchModel, IslandUI._OpenPlacementModelLibrary, {
                    width = 64, backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
                }),
                Button(labels.rotateLeft, function() callbacks_.rotatePlacement(-15) end, { width = 56 }),
                Button(labels.rotateRight, function() callbacks_.rotatePlacement(15) end, { width = 56 }),
                Button(labels.scaleDown, function() callbacks_.scalePlacement(-0.1) end, { width = 36 }),
                Button(labels.scaleUp, function() callbacks_.scalePlacement(0.1) end, { width = 36 }),
                Button(labels.close, callbacks_.cancelPlacement, { width = 48, backgroundColor = COLORS.soft }),
            },
        }
        return placementPanel_
    end
    if state_.selected and (mobile or profile.mode == "tablet") then
        if mobile then
            return UI.Panel {
                position = "absolute",
                left = MobileLeftInset(profile), right = MobileRightInset(profile),
                bottom = MobileBottomInset(profile), height = 48,
                padding = 5, flexDirection = "row", alignItems = "center", gap = 3,
                backgroundColor = COLORS.surfaceGlass, backdropBlur = 12,
                borderColor = COLORS.gold, borderWidth = 2, borderRadius = 16,
                boxShadow = { { x = 0, y = 8, blur = 24, color = COLORS.shadow } },
                children = {
                    ActiveButton("移动", state_.transformMode == "translate", function()
                        callbacks_.setTransformMode("translate")
                    end, { width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8 }),
                    ActiveButton("旋转", state_.transformMode == "rotate", function()
                        callbacks_.setTransformMode("rotate")
                    end, { width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8 }),
                    ActiveButton("缩放", state_.transformMode == "scale", function()
                        callbacks_.setTransformMode("scale")
                    end, { width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8 }),
                    Button(state_.selected.isPortal and state_.selected.portalBound and "进入" or "复制",
                        state_.selected.isPortal and state_.selected.portalBound and callbacks_.enterPortal
                            or callbacks_.duplicate, {
                        width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8,
                    }),
                    Button(state_.selected.isPortal and (state_.selected.portalBound and "改绑" or "绑定")
                            or state_.selected.canCustomize and "定制" or "只读",
                        state_.selected.isPortal and OpenPortalBinding or callbacks_.editSelected, {
                        width = 34, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8,
                        disabled = not state_.selected.isPortal and not state_.selected.canCustomize,
                        backgroundColor = state_.selected.isPortal and COLORS.yellowSoft
                            or state_.selected.canCustomize and COLORS.blue or COLORS.soft,
                        textColor = state_.selected.isPortal and COLORS.blueDark
                            or state_.selected.canCustomize and COLORS.white or COLORS.muted,
                        borderColor = state_.selected.isPortal and COLORS.gold
                            or state_.selected.canCustomize and COLORS.blue or COLORS.line,
                    }),
                    Button("删除", callbacks_.deleteSelected, {
                        width = 32, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8, danger = true,
                    }),
                    Button("关闭", callbacks_.clearSelection, {
                        width = 34, flexGrow = 1, flexShrink = 1, height = 36, paddingHorizontal = 1, fontSize = 8,
                        backgroundColor = COLORS.soft,
                    }),
                },
            }
        end
        return UI.Panel {
            position = "absolute", left = 12, right = 12, bottom = bottom,
            height = 52, padding = 8, flexDirection = "row", alignItems = "center", gap = 6,
            backgroundColor = COLORS.panel, backdropBlur = 14, borderColor = COLORS.gold, borderWidth = 2, borderRadius = 16,
            boxShadow = { { x = 0, y = 7, blur = 20, color = COLORS.shadow } },
            children = {
                UI.Label { text = state_.selected.name, flexGrow = 1, flexShrink = 1, fontSize = 10, fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                ActiveButton("移", state_.transformMode == "translate", function() callbacks_.setTransformMode("translate") end, { width = 34, paddingHorizontal = 1 }),
                ActiveButton("转", state_.transformMode == "rotate", function() callbacks_.setTransformMode("rotate") end, { width = 34, paddingHorizontal = 1 }),
                ActiveButton("缩", state_.transformMode == "scale", function() callbacks_.setTransformMode("scale") end, { width = 34, paddingHorizontal = 1 }),
                Button(state_.selected.isPortal and state_.selected.portalBound and "进入" or "复制",
                    state_.selected.isPortal and state_.selected.portalBound and callbacks_.enterPortal
                        or callbacks_.duplicate, { width = 42, paddingHorizontal = 1 }),
                Button(state_.selected.isPortal and (state_.selected.portalBound and "改绑" or "绑定")
                        or state_.selected.canCustomize and "定制" or "只读",
                    state_.selected.isPortal and OpenPortalBinding or callbacks_.editSelected, {
                    width = 42, paddingHorizontal = 1,
                    disabled = not state_.selected.isPortal and not state_.selected.canCustomize,
                    backgroundColor = state_.selected.isPortal and COLORS.yellowSoft
                        or state_.selected.canCustomize and COLORS.blue or COLORS.soft,
                    textColor = state_.selected.isPortal and COLORS.blueDark
                        or state_.selected.canCustomize and COLORS.white or COLORS.muted,
                    borderColor = state_.selected.isPortal and COLORS.gold
                        or state_.selected.canCustomize and COLORS.blue or COLORS.line,
                }),
                Button("删", callbacks_.deleteSelected, { width = 34, paddingHorizontal = 1, danger = true }),
            },
        }
    end
    return nil
end

local function BuildMobileBottom(profile)
    if profile.mode == "mobile" and BlockingSurfaceOpen() then return nil end
    if not ShouldBuildMobileBottom(profile.mode, state_ and state_.selected, state_ and state_.mode) then return nil end
    if mobileBottomHidden_ then
        return UI.Panel {
            position = "absolute", left = MobileLeftInset(profile), bottom = MobileBottomInset(profile),
            width = 54, height = 38,
            backgroundColor = COLORS.transparent, borderWidth = 0,
            children = {
                Button("菜单", function()
                    mobileBottomHidden_ = false
                    IslandUI.Rebuild()
                end, {
                    width = 54, height = 38, paddingHorizontal = 3,
                    backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.blue,
                    boxShadow = { { x = 0, y = 5, blur = 14, color = COLORS.shadow } },
                }),
            },
        }
    end
    return UI.Panel {
        position = "absolute", left = MobileLeftInset(profile), right = MobileRightInset(profile),
        bottom = MobileBottomInset(profile), height = 42,
        padding = 0, flexDirection = "row", alignItems = "center", gap = 5,
        backgroundColor = COLORS.transparent,
        borderColor = COLORS.transparent, borderWidth = 0, borderRadius = 0,
        overflow = "visible",
        children = {
            Button("收", function()
                mobileBottomHidden_ = true
                libraryOpen_, islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, false, false
                IslandUI.Rebuild()
            end, {
                width = 30, height = 42, paddingHorizontal = 1, fontSize = 9,
                backgroundColor = COLORS.surfaceGlass,
            }),
            ActiveButton("模型", libraryOpen_, function() exploreOpen_, islandManagerOpen_ = false, false; libraryOpen_ = not libraryOpen_; IslandUI.Rebuild() end,
                { flexGrow = 1, flexShrink = 1, height = 42 }),
            ActiveButton("空岛", islandManagerOpen_, function() exploreOpen_, libraryOpen_ = false, false; islandManagerOpen_ = not islandManagerOpen_; IslandUI.Rebuild() end,
                { flexGrow = 1, flexShrink = 1, height = 42 }),
            ActiveButton("探索", exploreOpen_, function()
                libraryOpen_, islandManagerOpen_, exploreOpen_ = false, false, not exploreOpen_
                IslandUI.Rebuild()
                if exploreOpen_ then callbacks_.refreshExplore() end
            end, { flexGrow = 1, flexShrink = 1, height = 42, paddingHorizontal = 1 }),
            Button("漫游", function()
                libraryOpen_, islandManagerOpen_, exploreOpen_ = false, false, false
                callbacks_.enterFirstPerson()
            end, { flexGrow = 1, flexShrink = 1, height = 42, paddingHorizontal = 2, backgroundColor = COLORS.soft, borderColor = COLORS.blue }),
            ActiveButton("留言", social_.guestbookOpen, Social.RequestGuestbook, {
                flexGrow = 1, flexShrink = 1, height = 42, paddingHorizontal = 2,
                backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.blue,
            }),
            Button("保存", callbacks_.save, { flexGrow = 1, flexShrink = 1, height = 42 }),
        },
    }
end

local function BuildFirstPersonHud(profile)
    local mobile = profile.mode == "mobile"
    local function FlightVerticalButton(text, direction, right, bottom, size, color)
        local button = UI.Button {
            position = "absolute", right = right, bottom = bottom,
            width = size, height = size, borderRadius = size * 0.5,
            backgroundColor = COLORS.surfaceGlass, borderColor = color, borderWidth = 3,
            hoverBackgroundColor = COLORS.yellowSoft,
            pressedBackgroundColor = COLORS.skySoft,
            boxShadow = { { x = 0, y = 5, blur = 14, color = COLORS.shadow } },
            text = text, fontSize = 11, fontWeight = "900", textColor = COLORS.blueDark,
        }
        local function Stop()
            if callbacks_.setFirstPersonFlightVertical then callbacks_.setFirstPersonFlightVertical(0) end
        end
        ---@type fun(self: any, event: any): any
        local inheritedPointerDown = button.OnPointerDown
        ---@type fun(self: any, event: any): any
        local inheritedPointerUp = button.OnPointerUp
        ---@type fun(self: any, event: any): any
        local inheritedPointerCancel = button.OnPointerCancel
        button.OnPointerDown = function(self, event)
            local consumed = inheritedPointerDown and inheritedPointerDown(self, event)
            if not event or not event:IsPrimaryAction() then return consumed end
            if callbacks_.nudgeFirstPersonFlight then callbacks_.nudgeFirstPersonFlight(direction) end
            if callbacks_.setFirstPersonFlightVertical then
                callbacks_.setFirstPersonFlightVertical(direction)
            end
            return consumed
        end
        button.OnPointerUp = function(self, event)
            local consumed = inheritedPointerUp and inheritedPointerUp(self, event)
            Stop()
            return consumed
        end
        button.OnPointerCancel = function(self, event)
            local consumed = inheritedPointerCancel and inheritedPointerCancel(self, event)
            Stop()
            return consumed
        end
        return button
    end
    ---@type any[]
    local topActions = {
        Button("← 退出 Esc", callbacks_.exitFirstPerson, {
            width = mobile and 88 or 114, height = mobile and 38 or 34,
            paddingHorizontal = mobile and 9 or 12,
            backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.blue,
        }),
        ActiveButton(state_ and state_.firstPersonRun and "跑步" or "走路",
            state_ and state_.firstPersonRun, callbacks_.toggleFirstPersonRun,
            { width = mobile and 50 or 62, height = mobile and 38 or 34, paddingHorizontal = 3 }),
        ActiveButton(state_ and state_.firstPersonFlying and "飞行中" or "飞行",
            state_ and state_.firstPersonFlying, callbacks_.toggleFirstPersonFlying,
            { width = mobile and 54 or 62, height = mobile and 38 or 34, paddingHorizontal = 3 }),
        Button("暂停", function() IslandUI.SetPaused(true) end, {
            width = mobile and 50 or 54, height = mobile and 38 or 34,
            paddingHorizontal = mobile and 7 or 9,
            backgroundColor = COLORS.surfaceGlass, borderColor = COLORS.gold,
        }),
    }
    if state_ and state_.visitMode then
        table.insert(topActions, 2, Button("探索更多", callbacks_.exploreMore, {
            width = mobile and 64 or 76, height = mobile and 38 or 34, paddingHorizontal = 3,
            backgroundColor = COLORS.yellowSoft, borderColor = COLORS.gold,
        }))
    end
    table.insert(topActions, state_ and state_.visitMode and 3 or 2,
        Button("留言板", Social.RequestGuestbook, {
            width = mobile and 54 or 62, height = mobile and 38 or 34,
            paddingHorizontal = 3, backgroundColor = COLORS.soft, borderColor = COLORS.blue,
        }))
    if not mobile then
        topActions[#topActions + 1] = UI.Panel {
            paddingHorizontal = 10, height = 34, justifyContent = "center",
            backgroundColor = COLORS.statusGlass, borderColor = COLORS.gold, borderWidth = 2,
            borderRadius = 12, pointerEvents = "none",
            boxShadow = { { x = 0, y = 4, blur = 12, color = COLORS.shadow } },
            children = { UI.Label { text = "✦ " .. (state_ and state_.name or "我的空岛"), fontSize = 10, fontWeight = "900", fontColor = COLORS.ink } },
        }
    end
    ---@type any[]
    local children = {
        UI.Panel {
            position = "absolute", left = math.max(16, profile.safe.left + 12), top = math.max(14, profile.safe.top + 10),
            flexDirection = "row", gap = 7, alignItems = "center",
            children = topActions,
        },
        UI.Label {
            position = "absolute", left = profile.width * 0.5 - 15, top = profile.height * 0.5 - 18,
            width = 30, height = 36, text = "+", textAlign = "center", fontSize = 25,
            fontWeight = "300", fontColor = COLORS.skyText, pointerEvents = "none",
        },
    }
    if mobile then
        if state_ and state_.firstPersonJoystickActive then
            local radius = 58
            local centerX = math.max(profile.safe.left + radius + 8,
                math.min(profile.width * 0.58 - radius, state_.firstPersonJoystickX or radius))
            local centerY = math.max(profile.safe.top + radius + 8,
                math.min(profile.height - profile.safe.bottom - radius - 8, state_.firstPersonJoystickY or radius))
            children[#children + 1] = UI.Panel {
                position = "absolute", left = centerX - radius, top = centerY - radius,
                width = radius * 2, height = radius * 2, borderRadius = radius,
                borderColor = COLORS.joystickLine, borderWidth = 3,
                backgroundColor = COLORS.joystickFill, alignItems = "center", justifyContent = "center",
                pointerEvents = "none",
                children = {
                    UI.Panel { width = 48, height = 48, borderRadius = 24,
                        backgroundColor = COLORS.subtleGlass, borderColor = COLORS.blue, borderWidth = 3,
                        alignItems = "center", justifyContent = "center" },
                },
            }
        end
        if state_ and state_.firstPersonFlying then
            children[#children + 1] = FlightVerticalButton("上升", 1,
                math.max(28, profile.safe.right + 22), math.max(46, profile.safe.bottom + 38), 64, COLORS.blue)
            children[#children + 1] = FlightVerticalButton("下降", -1,
                math.max(100, profile.safe.right + 94), math.max(51, profile.safe.bottom + 43), 54, COLORS.gold)
        else
            children[#children + 1] = UI.Button {
                position = "absolute", right = math.max(28, profile.safe.right + 22), bottom = math.max(46, profile.safe.bottom + 38),
                width = 64, height = 64, text = "跳跃", borderRadius = 32,
                backgroundColor = COLORS.surfaceGlass, hoverBackgroundColor = COLORS.yellowSoft,
                pressedBackgroundColor = COLORS.skySoft, borderColor = COLORS.blue, borderWidth = 3,
                textColor = COLORS.blueDark, fontSize = 11, fontWeight = "900",
                onClick = function() if callbacks_.jumpFirstPerson then callbacks_.jumpFirstPerson() end end,
            }
        end
    else
        children[#children + 1] = UI.Label {
            position = "absolute", left = profile.width * 0.5 - 190, bottom = 18, width = 380,
            text = state_ and state_.firstPersonFlying
                and "WASD 飞行 · Shift 加速 · Space 上升 · Ctrl 下降 · F 关闭飞行 · Esc 退出"
                or "WASD 行走 · Shift 跑步 · Space 跳跃 · F 开启飞行 · Esc 退出",
            paddingHorizontal = 12, paddingVertical = 6, backgroundColor = COLORS.hudGlass,
            borderColor = COLORS.line, borderWidth = 2, borderRadius = 12,
            textAlign = "center", fontSize = 10, fontWeight = "bold", fontColor = COLORS.ink, pointerEvents = "none",
        }
    end
    return UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none", children = children }
end

local function BuildFooter(profile)
    if profile.mode == "mobile" then return nil end
    statusLabel_ = UI.Label { text = status_, flexGrow = 1, flexShrink = 1, fontSize = 9, fontWeight = "bold", fontColor = COLORS.ink, maxLines = 1 }
    return UI.Panel {
        position = "absolute", left = 0, right = 0, bottom = 0, height = profile.footer,
        paddingHorizontal = 14, flexDirection = "row", alignItems = "center", gap = 12,
        backgroundColor = COLORS.panel, borderTopColor = COLORS.line, borderTopWidth = 1,
        children = {
            statusLabel_,
            UI.Label { text = "点击岛面聚焦 · 滚轮缩放 · P 第一人称 / Esc 退出 · W/E/R 切换移动/旋转/缩放 · Q/T 左右旋转 · Del 删除 · Ctrl+S 保存 · Ctrl+Z/Y 撤销重做", fontSize = 8, fontColor = COLORS.muted },
            UI.Label { text = "空岛 " .. VERSION, fontSize = 9, fontWeight = "900", fontColor = COLORS.blue },
        },
    }
end

local function BuildTimeControl(profile)
    if not state_ then return nil end
    if BlockingSurfaceOpen() then return nil end
    local mobile = profile.mode == "mobile"
    local phaseMark = ({ dawn = "晨", day = "日", dusk = "暮", night = "夜" })[state_.timePhase] or "日"
    timeButton_ = ActiveButton(phaseMark .. " " .. tostring(state_.timeLabel or "09:30"), timePanelOpen_, function()
        timePanelOpen_ = not timePanelOpen_
        IslandUI.Rebuild()
    end, {
        width = mobile and 78 or 86, height = mobile and 38 or 32,
        paddingHorizontal = 4, backgroundColor = COLORS.surface, borderColor = COLORS.gold,
    })
    local chipBottom = nil
    local chipTop = mobile and math.max(profile.top + 12, (profile.safe.top or 0) + 58) or (profile.top + 10)
    local chipRight = mobile and MobileRightInset(profile) or (profile.right + 14)
    local children = {
        UI.Panel {
            position = "absolute", right = chipRight, top = chipTop, bottom = chipBottom,
            width = mobile and 78 or 86, height = mobile and 38 or 32,
            children = { timeButton_ },
        },
    }
    if timePanelOpen_ then
        local panelWidth = mobile and math.min(224, profile.width - 36) or 236
        timeSlider_ = UI.Slider {
            value = state_.timeOfDay or 9.5, min = 0, max = 24, step = 0.25,
            width = panelWidth - 28, height = 30, thumbSize = 18, trackHeight = 6,
            trackBgColor = COLORS.sliderTrack,
            trackFillGradient = { direction = "to-right", from = { 80, 104, 170, 255 }, to = { 255, 188, 83, 255 } },
            thumbColor = COLORS.gold,
            onChange = function(_, value) callbacks_.setTimeOfDay(value, false) end,
            onChangeEnd = function() callbacks_.commitTimeOfDay() end,
        }
        local presets = {
            { "清晨", 6.5 }, { "正午", 12 }, { "黄昏", 18 }, { "深夜", 23 },
        }
        local presetButtons = {}
        for _, preset in ipairs(presets) do
            presetButtons[#presetButtons + 1] = Button(preset[1], function()
                callbacks_.setTimeOfDay(preset[2], true)
            end, { flexGrow = 1, flexShrink = 1, height = 29, paddingHorizontal = 2, fontSize = 9 })
        end
        local panelBottom = nil
        local panelTop = mobile and (chipTop + 46) or (chipTop + 40)
        children[#children + 1] = UI.Panel {
            position = "absolute", right = chipRight, top = panelTop, bottom = panelBottom,
            width = panelWidth, height = 170, padding = 14,
            flexDirection = "column", gap = 8,
            backgroundColor = COLORS.timePanel, backdropBlur = 16,
            borderColor = COLORS.gold, borderWidth = 2, borderRadius = 17,
            boxShadow = { { x = 0, y = 8, blur = 22, color = COLORS.shadow } },
            children = {
                UI.Panel { width = "100%", height = 24, flexDirection = "row", alignItems = "center", children = {
                    UI.Label { text = "世界时间", flexGrow = 1, fontSize = 11, fontWeight = "900", fontColor = COLORS.ink },
                    UI.Label { text = state_.timePhaseLabel or "白天", fontSize = 9, fontWeight = "bold", fontColor = COLORS.blueDark },
                } },
                timeSlider_,
                UI.Panel { width = "100%", flexDirection = "row", gap = 5, children = presetButtons },
                ActiveButton(state_.timeAuto and "自动流逝：开" or "自动流逝：关", state_.timeAuto, function()
                    callbacks_.setTimeAuto(not state_.timeAuto)
                end, { width = "100%", height = 30, fontSize = 9 }),
            },
        }
    end
    return UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none", children = children }
end

local function CanResumePauseAt(profile, x, y)
    profile = profile or {}
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return true end
    local viewportWidth = math.max(1, tonumber(profile.width) or 1)
    local nativeMenuRight = math.max(0, tonumber(profile.nativeMenuRight) or 0)
    local nativeMenuBottom = math.max(0, tonumber(profile.nativeMenuBottom) or 0)
    if nativeMenuRight <= 0 or nativeMenuBottom <= 0 then return true end
    return not (x >= viewportWidth - nativeMenuRight and y <= nativeMenuBottom)
end

local function ResumePauseFromPointer(profile, event)
    if not paused_ then return false end
    if event and event.IsPrimaryAction and not event:IsPrimaryAction() then return false end
    if event and not CanResumePauseAt(profile, event.x, event.y) then return false end
    if callbacks_ and callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
    return IslandUI.SetPaused(false)
end

local function BuildPauseLayer(profile)
    local title = PauseTitleLayout(profile)
    local credit = PauseCreditLayout(profile, title)
    local layer = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        width = "100%", height = "100%",
        pointerEvents = "auto", backgroundColor = COLORS.transparent,
        onClick = function(_, event)
            -- Resume only after a complete tap/click. This keeps the release
            -- from falling through into island selection after the UI rebuild.
            ResumePauseFromPointer(profile, event)
        end,
        children = {
            UI.Panel {
                position = "absolute", left = title.left, bottom = title.bottom,
                width = title.width, height = title.height,
                backgroundImage = PAUSE_TITLE_ASSET, backgroundFit = "contain",
                backgroundColor = COLORS.transparent, borderWidth = 0,
                pointerEvents = "none",
            },
            UI.Panel {
                position = "absolute", left = credit.left, bottom = credit.bottom,
                width = credit.width, height = credit.height,
                paddingHorizontal = 6, alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.subtleGlass,
                borderColor = COLORS.line, borderWidth = 1, borderRadius = credit.height * 0.5,
                pointerEvents = "none",
                children = {
                    UI.Label { text = PAUSE_CREDIT_TEXT, fontSize = credit.fontSize,
                        fontWeight = "bold", fontColor = COLORS.muted,
                        textAlign = "center", pointerEvents = "none" },
                },
            },
        },
    }
    layer.focusable = false
    return layer
end

function Social.ModalGeometry(profile, maxWidth, maxHeight)
    profile = profile or { width = 1, height = 1, safe = {}, mode = "desktop" }
    local safe = profile.safe or {}
    local mobile = profile.mode == "mobile"
    local leftInset = mobile and MobileLeftInset(profile)
        or math.max(20, (tonumber(safe.left) or 0) + 20)
    local rightInset = mobile and MobileRightInset(profile)
        or math.max(20, (tonumber(safe.right) or 0) + 20)
    local topInset = mobile and MobileModalTop(profile)
        or math.max(20, (tonumber(safe.top) or 0) + 20)
    local bottomInset = mobile and MobileBottomInset(profile)
        or math.max(20, (tonumber(safe.bottom) or 0) + 20)
    local availableWidth = math.max(1, (tonumber(profile.width) or 1) - leftInset - rightInset)
    local availableHeight = math.max(1, (tonumber(profile.height) or 1) - topInset - bottomInset)
    local width = math.min(availableWidth, tonumber(maxWidth) or availableWidth)
    local height = math.min(availableHeight, tonumber(maxHeight) or availableHeight)
    return {
        left = mobile and leftInset or ((profile.width - width) * 0.5),
        top = mobile and topInset or (topInset + (availableHeight - height) * 0.5),
        width = width,
        height = height,
        mobile = mobile,
    }
end

function Social.BuildDismiss(profile, open, closeAction)
    if not open then return nil end
    local dismiss = UI.Panel {
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = profile.mode == "mobile" and COLORS.scrimStrong or COLORS.scrim,
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        if callbacks_ and callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        closeAction()
    end
    return dismiss
end

function Social.PlayerProfileIdentity(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local ownerId = snapshot.ownerId or snapshot.userId or snapshot.id
    local nickname = snapshot.nickname or snapshot.name or snapshot.owner
    return ownerId ~= nil and tostring(ownerId) or "",
        Social.NonEmptyText(nickname, "云岛旅人")
end

function Social.PlayerProfileIslands(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local islands = snapshot.publishedIslands or snapshot.islands or {}
    return type(islands) == "table" and islands or {}
end

function Social.PlayerProfileModels(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local models = snapshot.publishedModels or snapshot.models or snapshot.assets or {}
    return type(models) == "table" and models or {}
end

function Social.ProfileStat(label, value, width, mobile)
    return UI.Panel {
        width = width, height = mobile and 42 or 46, paddingHorizontal = 4,
        flexDirection = "column", alignItems = "center", justifyContent = "center", gap = 0,
        backgroundColor = COLORS.soft, borderColor = COLORS.line, borderWidth = 1, borderRadius = 12,
        children = {
            UI.Label { text = tostring(value or 0), fontSize = mobile and 11 or 13,
                fontWeight = "900", fontColor = COLORS.blueDark, textAlign = "center", maxLines = 1 },
            UI.Label { text = tostring(label or ""), fontSize = 7,
                fontWeight = "bold", fontColor = COLORS.muted, textAlign = "center", maxLines = 1 },
        },
    }
end

function Social.BuildProfileIslandCard(island, width, mobile, profileIsMe, profileSnapshot)
    island = type(island) == "table" and island or {}
    local payload = type(island.entry) == "table" and island.entry
        or type(island.islandEntry) == "table" and island.islandEntry or island
    local published = island.published ~= false and payload.published ~= false
    local isOwn = profileIsMe == true or island.isOwn == true or payload.isOwn == true
    local islandName = Social.NonEmptyText(island.name or payload.name, "未命名空岛")
    local details = tostring(island.count or payload.count or 0) .. " 模型"
    local likes = tonumber(island.likes or payload.likes) or 0
    if likes > 0 then details = details .. " · " .. tostring(likes) .. " 赞" end
    local identitySnapshot = Social.CopySnapshot(island)
    if profileSnapshot then
        identitySnapshot.avatar = profileSnapshot.avatar
    end
    identitySnapshot.onClick = function()
        Social.RequestPlayerProfile(
            island.ownerId or payload.ownerId,
            island.owner or payload.owner or "云岛旅人")
    end
    return UI.Panel {
        width = width, minHeight = mobile and 62 or 68, padding = mobile and 8 or 10,
        flexDirection = "row", alignItems = "center", gap = 8,
        backgroundColor = COLORS.surface, borderColor = published and COLORS.blue or COLORS.line,
        borderWidth = 1, borderRadius = 13,
        children = {
            UI.Panel { width = mobile and 32 or 38, height = mobile and 32 or 38,
                flexShrink = 0, alignItems = "center", justifyContent = "center",
                borderRadius = mobile and 16 or 19, backgroundColor = COLORS.yellowSoft,
                borderColor = COLORS.gold, borderWidth = 2,
                children = { UI.Avatar(Social.AvatarProps(identitySnapshot,
                    Social.NonEmptyText(island.owner or payload.owner, "云岛旅人"),
                    mobile and 28 or 34, COLORS.gold)) },
            },
            UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 2,
                children = {
                    UI.Label { text = islandName, fontSize = mobile and 10 or 11,
                        fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                    UI.Label { text = details, fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                    UI.Label { text = Social.NonEmptyText(island.description or payload.description,
                            published and "已发布，可前往参观" or "暂未发布"),
                        fontSize = 8, fontColor = published and COLORS.blueDark or COLORS.muted,
                        maxLines = 1 },
                } },
            Button(isOwn and "我的空岛" or "参观", function()
                if isOwn then return end
                social_.playerProfileOpen, social_.guestbookOpen = false, false
                if callbacks_ and callbacks_.visitIsland then callbacks_.visitIsland(payload) end
            end, {
                width = isOwn and (mobile and 54 or 64) or (mobile and 44 or 52),
                height = mobile and 30 or 32,
                paddingHorizontal = 3, fontSize = mobile and 8 or 9,
                disabled = isOwn or not published or not (callbacks_ and callbacks_.visitIsland),
                backgroundColor = isOwn and COLORS.soft or COLORS.blue,
                hoverBackgroundColor = isOwn and COLORS.soft or COLORS.blueDark,
                borderColor = isOwn and COLORS.line or COLORS.blue,
                textColor = isOwn and COLORS.muted or COLORS.white,
            }),
        },
    }
end

function Social.BuildProfileModelCard(model, width, mobile)
    model = type(model) == "table" and model or {}
    local detail = Social.NonEmptyText(model.category or model.licenseLabel or model.license,
        model.published == false and "未发布" or "已发布模型")
    local identitySnapshot = Social.CopySnapshot(model)
    identitySnapshot.onClick = function()
        Social.RequestPlayerProfile(model.ownerId, model.author)
    end
    return UI.Panel {
        width = width, minHeight = mobile and 48 or 52, padding = mobile and 8 or 10,
        flexDirection = "row", alignItems = "center", gap = 8,
        backgroundColor = COLORS.surface, borderColor = COLORS.line, borderWidth = 1, borderRadius = 12,
        children = {
            UI.Panel { width = mobile and 28 or 32, height = mobile and 28 or 32,
                flexShrink = 0, alignItems = "center", justifyContent = "center",
                borderRadius = 9, backgroundColor = COLORS.skySoft,
                children = { UI.Avatar(Social.AvatarProps(identitySnapshot,
                    model.author, mobile and 24 or 28, COLORS.blue)) },
            },
            UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 1,
                children = {
                    UI.Label { text = Social.NonEmptyText(model.name, "未命名模型"),
                        fontSize = mobile and 9 or 10, fontWeight = "900", fontColor = COLORS.ink,
                        maxLines = 1 },
                    Social.PlayerIdentity(model.author, model.ownerId, identitySnapshot, {
                        height = 18, avatarSize = 16, fontSize = 7, gap = 3,
                        textColor = COLORS.blueDark,
                    }),
                    UI.Label { text = detail, fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                } },
            UI.Label { text = tostring(model.likes or model.uses or model.downloads or 0),
                width = 28, flexShrink = 0, textAlign = "center", fontSize = 8,
                fontWeight = "bold", fontColor = COLORS.blueDark, maxLines = 1 },
        },
    }
end

function Social.BuildPlayerProfileDismiss(profile)
    return Social.BuildDismiss(profile, social_.playerProfileOpen, function()
        social_.playerProfileOpen = false
        IslandUI.Rebuild()
    end)
end

function Social.BuildPlayerProfilePanel(profile)
    if not social_.playerProfileOpen then return nil end
    local snapshot = type(social_.playerProfile) == "table" and social_.playerProfile or {}
    local geometry = Social.ModalGeometry(profile, 560, 640)
    local mobile = geometry.mobile
    local padding = mobile and 11 or 16
    local contentWidth = math.max(1, geometry.width - padding * 2)
    local ownerId, nickname = Social.PlayerProfileIdentity(snapshot)
    local islands, models = Social.PlayerProfileIslands(snapshot), Social.PlayerProfileModels(snapshot)
    local publishedIslands, publishedModels = {}, {}
    for _, island in ipairs(islands) do
        if type(island) == "table" and island.published ~= false then
            publishedIslands[#publishedIslands + 1] = island
        end
    end
    for _, model in ipairs(models) do
        if type(model) == "table" and model.published ~= false then
            publishedModels[#publishedModels + 1] = model
        end
    end
    local visibleIslandCount = tonumber(snapshot.publishedIslandCount or snapshot.publishedCount)
        or #publishedIslands
    local visibleModelCount = tonumber(snapshot.publishedModelCount or snapshot.totalModels)
        or #publishedModels
    local statGap = mobile and 5 or 7
    local statWidth = math.max(1, (contentWidth - statGap * 2) / 3)
    local profileRows = {}
    local feedback = Social.NonEmptyText(snapshot.error or snapshot.feedback or snapshot.message, "")
    if feedback ~= "" then
        profileRows[#profileRows + 1] = { kind = "feedback", text = feedback,
            error = snapshot.error ~= nil }
    end
    local bio = Social.NonEmptyText(snapshot.bio or snapshot.description or snapshot.signature, "")
    if bio ~= "" then
        profileRows[#profileRows + 1] = { kind = "bio", text = bio }
    end
    local statusText = Social.NonEmptyText(snapshot.status or snapshot.lastSeenLabel or snapshot.updatedLabel, "")
    if statusText == "" and (tonumber(snapshot.latestUpdatedAt) or 0) > 0 then
        statusText = "最近发布 · " .. UpdatedLabel(snapshot.latestUpdatedAt)
    end
    if statusText ~= "" then
        profileRows[#profileRows + 1] = { kind = "status", text = statusText }
    end
    profileRows[#profileRows + 1] = { kind = "section",
        text = "发布的空岛 · " .. tostring(visibleIslandCount) }
    if #publishedIslands == 0 then
        profileRows[#profileRows + 1] = { kind = "empty",
            text = snapshot.loading and "正在读取发布的空岛……" or "这个玩家还没有发布空岛。" }
    else
        for _, island in ipairs(publishedIslands) do
            profileRows[#profileRows + 1] = { kind = "island", value = island }
        end
    end
    profileRows[#profileRows + 1] = { kind = "section",
        text = "发布的模型 · " .. tostring(visibleModelCount) }
    if #publishedModels == 0 then
        profileRows[#profileRows + 1] = { kind = "empty",
            text = snapshot.loading and "正在读取发布的模型……" or "暂无公开模型。" }
    else
        for _, model in ipairs(publishedModels) do
            profileRows[#profileRows + 1] = { kind = "model", value = model }
        end
    end
    local rowHeight = mobile and 78 or 84
    local rowGap = mobile and 7 or 8
    local listHeight = math.max(1, geometry.height - (mobile and 144 or 170))
    local function CreateProfileRow()
        return UI.Panel { width = contentWidth, height = rowHeight, overflow = "hidden" }
    end
    local function BindProfileRow(widget, row)
        local value = row.value or {}
        local signature = table.concat({ tostring(row.kind), tostring(row.text),
            tostring(value.id or value.islandId or value.assetId), tostring(value.name),
            tostring(value.likes), tostring(value.published), tostring(value.count),
        }, ":")
        if widget._profileVirtualSignature == signature then return end
        widget._profileVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        local child
        if row.kind == "island" then
            child = Social.BuildProfileIslandCard(value, contentWidth, mobile,
                snapshot.isMe == true, snapshot)
        elseif row.kind == "model" then
            child = Social.BuildProfileModelCard(value, contentWidth, mobile)
        elseif row.kind == "section" then
            child = UI.Panel { width = contentWidth, height = rowHeight,
                paddingHorizontal = 4, justifyContent = "center",
                children = { UI.Label { text = tostring(row.text),
                    fontSize = mobile and 10 or 11, fontWeight = "900",
                    fontColor = COLORS.ink } },
            }
        else
            local profileMessageLabel = UI.Label {
                text = tostring(row.text or ""), width = "100%", maxLines = 4,
            }
            profileMessageLabel:SetStyle({
                fontSize = row.kind == "bio" and (mobile and 9 or 10) or 9,
                fontWeight = row.kind == "feedback" and "bold" or "normal",
                fontColor = row.kind == "feedback"
                        and (row.error and COLORS.danger or COLORS.blueDark)
                    or row.kind == "status" and COLORS.muted or COLORS.ink,
                textAlign = row.kind == "bio" and "left" or "center",
            })
            child = UI.Panel { width = contentWidth, height = rowHeight, padding = 12,
                alignItems = "center", justifyContent = "center",
                backgroundColor = row.kind == "bio" and COLORS.soft or COLORS.surface,
                borderColor = row.kind == "feedback" and (row.error and COLORS.dangerLine or COLORS.blue)
                    or COLORS.line,
                borderWidth = row.kind == "status" and 0 or 1, borderRadius = 12,
                children = { profileMessageLabel },
            }
        end
        child:SetStyle({ height = rowHeight, minHeight = rowHeight, flexShrink = 0 })
        widget:AddChild(child)
    end
    local profileList = RememberedVirtualList("player-profile:" .. ownerId, {
        width = contentWidth, height = listHeight, viewportHeight = listHeight,
        data = profileRows, itemHeight = rowHeight, itemGap = rowGap,
        poolBuffer = 2, showScrollbar = true, bounces = mobile,
        createItem = CreateProfileRow, bindItem = BindProfileRow,
    })
    local profileIdentity = Social.CopySnapshot(snapshot)
    profileIdentity.onClick = function()
        Social.RequestPlayerProfile(ownerId, nickname)
    end
    return UI.Panel {
        position = "absolute", left = geometry.left, top = geometry.top,
        width = geometry.width, height = geometry.height, padding = padding,
        flexDirection = "column", gap = mobile and 8 or 10,
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel,
        backdropBlur = 18, borderColor = COLORS.blue, borderWidth = 2, borderRadius = 20,
        overflow = "hidden", boxShadow = { { x = 0, y = 12, blur = 34, color = COLORS.shadow } },
        children = {
            UI.Panel { width = contentWidth, height = mobile and 64 or 72,
                flexDirection = "row", alignItems = "center", gap = mobile and 9 or 12,
                children = {
                    UI.Avatar(Social.AvatarProps(profileIdentity, nickname,
                        mobile and 48 or 56, COLORS.blue)),
                    UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 1,
                        children = {
                            Social.NicknameButton(nickname, ownerId, {
                                height = mobile and 24 or 28, fontSize = mobile and 13 or 15,
                                paddingHorizontal = 0, textColor = COLORS.ink,
                            }),
                            UI.Label { text = ownerId ~= "" and ("玩家 ID · " .. ownerId)
                                    or "玩家资料",
                                fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                            snapshot.loading and UI.Label { text = "资料更新中……",
                                fontSize = 8, fontWeight = "bold", fontColor = COLORS.blueDark,
                                maxLines = 1 } or nil,
                        } },
                    Button("关闭", function()
                        social_.playerProfileOpen = false
                        IslandUI.Rebuild()
                    end, { width = mobile and 42 or 48, height = mobile and 30 or 32,
                        paddingHorizontal = 3, fontSize = 9 }),
                } },
            UI.Panel { width = contentWidth, height = mobile and 42 or 46,
                flexDirection = "row", gap = statGap, children = {
                    Social.ProfileStat("发布空岛", visibleIslandCount, statWidth, mobile),
                    Social.ProfileStat("发布模型", visibleModelCount, statWidth, mobile),
                    Social.ProfileStat("获赞", snapshot.likes or snapshot.totalLikes or 0, statWidth, mobile),
                } },
            profileList,
        },
    }
end

function Social.GuestbookMessages(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local messages = snapshot.messages or snapshot.entries or snapshot.items or {}
    return type(messages) == "table" and messages or {}
end

function Social.GuestbookMessageIdentity(message)
    message = type(message) == "table" and message or {}
    local authorId = message.authorId or message.userId or message.ownerId or message.playerId
    local nickname = message.nickname or message.authorNickname or message.author or message.owner
    return authorId ~= nil and tostring(authorId) or "",
        Social.NonEmptyText(nickname, "云岛旅人")
end

function Social.GuestbookMessageTime(message)
    message = type(message) == "table" and message or {}
    local label = message.timeLabel or message.createdLabel or message.updatedLabel
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    local timestamp = tonumber(message.createdAt or message.timestamp or message.updatedAt)
    if timestamp and timestamp > 0 then
        local ok, formatted = pcall(os.date, "%m-%d %H:%M", timestamp)
        if ok and formatted then return tostring(formatted) end
    end
    return "刚刚"
end

function Social.BuildGuestbookMessageCard(message, width, mobile)
    message = type(message) == "table" and message or {}
    local authorId, nickname = Social.GuestbookMessageIdentity(message)
    local body = Social.NonEmptyText(message.text or message.message or message.content, "留下了一朵云。")
    local identitySnapshot = Social.CopySnapshot(message)
    identitySnapshot.onClick = function()
        Social.RequestPlayerProfile(authorId, nickname)
    end
    return UI.Panel {
        width = width, minHeight = mobile and 72 or 78, padding = mobile and 9 or 11,
        flexDirection = "row", alignItems = "flex-start", gap = mobile and 8 or 10,
        backgroundColor = (message.mine or message.isMe) and COLORS.skySoft or COLORS.surface,
        borderColor = (message.mine or message.isMe) and COLORS.blue or COLORS.line,
        borderWidth = 1, borderRadius = 14,
        children = {
            UI.Avatar(Social.AvatarProps(identitySnapshot, nickname,
                mobile and 32 or 38, COLORS.blue)),
            UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 4,
                children = {
                    UI.Panel { width = "100%", height = mobile and 20 or 22,
                        flexDirection = "row", alignItems = "center", gap = 4,
                        backgroundColor = COLORS.transparent, borderWidth = 0,
                        pointerEvents = "box-none", children = {
                            Social.NicknameButton(nickname, authorId, {
                                height = mobile and 20 or 22, fontSize = mobile and 9 or 10,
                                paddingHorizontal = 0, textColor = COLORS.blueDark,
                            }),
                            UI.Spacer(),
                            UI.Label { text = Social.GuestbookMessageTime(message), flexShrink = 0,
                                fontSize = 7, fontColor = COLORS.muted, maxLines = 1 },
                        } },
                    UI.Label { text = body, width = "100%", fontSize = mobile and 9 or 10,
                        fontColor = COLORS.ink, maxLines = 5 },
                } },
        },
    }
end

function Social.BuildGuestbookDismiss(profile)
    return Social.BuildDismiss(profile, social_.guestbookOpen, function()
        social_.guestbookOpen, social_.guestbookDraft = false, ""
        IslandUI.Rebuild()
    end)
end

function Social.RefreshGuestbook()
    if not callbacks_ or type(callbacks_.refreshGuestbook) ~= "function" then return end
    social_.guestbook.loading = true
    social_.guestbook.feedback = ""
    IslandUI.Rebuild()
    callbacks_.refreshGuestbook(social_.guestbook.ownerId or social_.guestbook.userId,
        social_.guestbook.islandId)
end

function Social.BuildGuestbookPanel(profile)
    if not social_.guestbookOpen then return nil end
    local snapshot = type(social_.guestbook) == "table" and social_.guestbook or {}
    local geometry = Social.ModalGeometry(profile, 570, 650)
    local mobile = geometry.mobile
    local padding = mobile and 11 or 16
    local contentWidth = math.max(1, geometry.width - padding * 2)
    local ownerId = snapshot.ownerId or snapshot.userId
    ownerId = ownerId ~= nil and tostring(ownerId) or ""
    local islandId = snapshot.islandId ~= nil and tostring(snapshot.islandId) or ""
    local owner = Social.NonEmptyText(snapshot.nickname or snapshot.owner or snapshot.name,
        state_ and state_.visitMode and "云岛旅人" or "我")
    local ownerIdentity = Social.CopySnapshot(snapshot)
    ownerIdentity.onClick = function()
        Social.RequestPlayerProfile(ownerId, owner)
    end
    local messages = Social.GuestbookMessages(snapshot)
    local feedback = Social.NonEmptyText(snapshot.error or snapshot.feedback or snapshot.message, "")
    local messageRows = {}
    if feedback ~= "" then
        messageRows[#messageRows + 1] = { kind = "feedback", text = feedback,
            error = snapshot.error ~= nil }
    end
    if snapshot.loading and #messages > 0 then
        messageRows[#messageRows + 1] = { kind = "notice", text = "正在刷新留言……" }
    end
    if #messages == 0 then
        messageRows[#messageRows + 1] = { kind = "empty",
            text = snapshot.loading and "正在把留言送上云端……"
                or "留言板还是空的，来做第一个留下脚印的人吧。" }
    else
        for _, message in ipairs(messages) do
            messageRows[#messageRows + 1] = { kind = "message", value = message }
        end
    end
    local canPost = snapshot.canPost
    if canPost == nil then canPost = state_ and state_.visitMode == true end
    local posting = snapshot.posting == true
    local footer
    if canPost then
        footer = UI.Panel { width = contentWidth, height = mobile and 66 or 70,
            paddingTop = 7, flexDirection = "column", gap = 4,
            borderTopColor = COLORS.line, borderTopWidth = 1,
            children = {
                UI.Panel { width = contentWidth, height = mobile and 38 or 40,
                    flexDirection = "row", alignItems = "center", gap = 7,
                    children = {
                        UI.TextField {
                            value = social_.guestbookDraft, flexGrow = 1, minWidth = 0,
                            height = mobile and 36 or 38, maxLength = 80,
                            placeholder = "写下对这座空岛的留言……",
                            disabled = posting, fontSize = mobile and 9 or 10,
                            backgroundColor = COLORS.white, borderColor = COLORS.blue,
                            borderWidth = 2, borderRadius = 11,
                            paddingHorizontal = mobile and 8 or 10,
                            onChange = function(_, value) social_.guestbookDraft = tostring(value or "") end,
                            onSubmit = function(_, value)
                                social_.guestbookDraft = tostring(value or "")
                                Social.SubmitGuestbookMessage()
                            end,
                        },
                        Button(posting and "发送中" or "发送", Social.SubmitGuestbookMessage, {
                            width = mobile and 50 or 58, height = mobile and 36 or 38,
                            paddingHorizontal = 3, fontSize = mobile and 9 or 10,
                            disabled = posting,
                            backgroundColor = COLORS.blue, hoverBackgroundColor = COLORS.blueDark,
                            borderColor = COLORS.blue, textColor = COLORS.white,
                        }),
                    } },
                UI.Label { text = "最多 80 字 · 留言会显示你的昵称",
                    width = contentWidth, fontSize = 7, fontColor = COLORS.muted,
                    textAlign = "right", maxLines = 1 },
            } }
    else
        local unavailableText = snapshot.isOwn and "这是你的空岛留言板，访客的新留言会出现在这里。"
            or snapshot.source ~= "cloud" and "离线示范空岛暂不支持留言。"
            or "当前无法留言，请稍后再试。"
        footer = UI.Panel { width = contentWidth, height = 34,
            paddingTop = 8, borderTopColor = COLORS.line, borderTopWidth = 1,
            alignItems = "center", justifyContent = "center", children = {
                UI.Label { text = unavailableText,
                    width = contentWidth, fontSize = mobile and 8 or 9,
                    fontColor = COLORS.muted, textAlign = "center", maxLines = 2 },
            } }
    end
    local islandLabel = Social.NonEmptyText(snapshot.islandName or snapshot.title,
        islandId ~= "" and ("空岛 " .. islandId) or "当前空岛")
    local sourceLabel = snapshot.source == "cloud" and "云端"
        or snapshot.source == "mine" and "我的空岛" or "离线"
    local rowHeight = mobile and 104 or 118
    local rowGap = mobile and 7 or 8
    local footerHeight = canPost and (mobile and 66 or 70) or 34
    local listHeight = math.max(1, geometry.height - padding * 2
        - (mobile and 54 or 60) - footerHeight - (mobile and 16 or 20))
    local function CreateGuestbookRow()
        return UI.Panel { width = contentWidth, height = rowHeight, overflow = "hidden" }
    end
    local function BindGuestbookRow(widget, row)
        local message = row.value or {}
        local signature = table.concat({ tostring(row.kind), tostring(row.text),
            tostring(message.id or message.messageId), tostring(message.authorId or message.userId),
            tostring(message.text or message.message or message.content),
            tostring(message.createdAt or message.timestamp),
        }, ":")
        if widget._guestbookVirtualSignature == signature then return end
        widget._guestbookVirtualSignature = signature
        while #widget.children > 0 do widget.children[#widget.children]:Destroy() end
        local child
        if row.kind == "message" then
            child = Social.BuildGuestbookMessageCard(message, contentWidth, mobile)
        else
            local guestbookMessageLabel = UI.Label {
                text = tostring(row.text or ""), width = "100%", maxLines = 3,
            }
            guestbookMessageLabel:SetStyle({
                textAlign = "center", fontSize = mobile and 9 or 10,
                fontWeight = row.kind == "empty" and "normal" or "bold",
                fontColor = row.kind == "feedback"
                        and (row.error and COLORS.danger or COLORS.blueDark)
                    or row.kind == "notice" and COLORS.blueDark or COLORS.muted,
            })
            child = UI.Panel { width = contentWidth, height = rowHeight, padding = 16,
                alignItems = "center", justifyContent = "center",
                backgroundColor = row.kind == "feedback" and COLORS.surface or COLORS.soft,
                borderColor = row.kind == "feedback" and (row.error and COLORS.dangerLine or COLORS.blue)
                    or COLORS.line,
                borderWidth = 1, borderRadius = 14,
                children = { guestbookMessageLabel },
            }
        end
        child:SetStyle({ height = rowHeight, minHeight = rowHeight, flexShrink = 0 })
        widget:AddChild(child)
    end
    local guestbookList = RememberedVirtualList(
        "guestbook:" .. ownerId .. ":" .. islandId, {
            width = contentWidth, height = listHeight, viewportHeight = listHeight,
            data = messageRows, itemHeight = rowHeight, itemGap = rowGap,
            poolBuffer = 2, showScrollbar = true, bounces = mobile,
            createItem = CreateGuestbookRow, bindItem = BindGuestbookRow,
        })
    return UI.Panel {
        position = "absolute", left = geometry.left, top = geometry.top,
        width = geometry.width, height = geometry.height, padding = padding,
        flexDirection = "column", gap = mobile and 8 or 10,
        backgroundColor = mobile and COLORS.panelGlass or COLORS.panel,
        backdropBlur = 18, borderColor = COLORS.gold, borderWidth = 2, borderRadius = 20,
        overflow = "hidden", boxShadow = { { x = 0, y = 12, blur = 34, color = COLORS.shadow } },
        children = {
            UI.Panel { width = contentWidth, height = mobile and 54 or 60,
                flexDirection = "row", alignItems = "center", gap = mobile and 8 or 10,
                children = {
                    UI.Avatar(Social.AvatarProps(ownerIdentity, owner,
                        mobile and 40 or 46, COLORS.gold)),
                    UI.Panel { flexGrow = 1, minWidth = 0, flexDirection = "column", gap = 0,
                        children = {
                            UI.Panel { height = mobile and 22 or 24,
                                flexDirection = "row", alignItems = "center", gap = 1,
                                backgroundColor = COLORS.transparent, borderWidth = 0,
                                pointerEvents = "box-none", children = {
                                    Social.NicknameButton(owner, ownerId, {
                                        height = mobile and 22 or 24,
                                        fontSize = mobile and 11 or 13,
                                        paddingHorizontal = 0, textColor = COLORS.ink,
                                    }),
                                    UI.Label { text = "的留言板", flexShrink = 0,
                                        fontSize = mobile and 11 or 13,
                                        fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 },
                                } },
                            UI.Label { text = islandLabel .. " · " .. sourceLabel .. " · "
                                    .. tostring(#messages) .. " 条留言",
                                fontSize = 8, fontColor = COLORS.muted, maxLines = 1 },
                        } },
                    Button("刷新", Social.RefreshGuestbook, {
                        width = mobile and 40 or 44, height = mobile and 30 or 32,
                        paddingHorizontal = 2, fontSize = 8,
                        disabled = snapshot.loading == true
                            or not (callbacks_ and callbacks_.refreshGuestbook),
                    }),
                    Button("关闭", function()
                        social_.guestbookOpen, social_.guestbookDraft = false, ""
                        IslandUI.Rebuild()
                    end, { width = mobile and 40 or 44, height = mobile and 30 or 32,
                        paddingHorizontal = 2, fontSize = 8 }),
                } },
            guestbookList,
            footer,
        },
    }
end

function Social.AppendLayers(children, profile)
    local guestbookDismiss = Social.BuildGuestbookDismiss(profile)
    if guestbookDismiss then children[#children + 1] = guestbookDismiss end
    local guestbook = Social.BuildGuestbookPanel(profile)
    if guestbook then children[#children + 1] = guestbook end
    local profileDismiss = Social.BuildPlayerProfileDismiss(profile)
    if profileDismiss then children[#children + 1] = profileDismiss end
    local playerProfile = Social.BuildPlayerProfilePanel(profile)
    if playerProfile then children[#children + 1] = playerProfile end
end

local function BuildRoot(profile)
    if paused_ then
        local pausedChildren = { BuildPauseLayer(profile) }
        Social.AppendLayers(pausedChildren, profile)
        return UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none",
            backgroundColor = COLORS.transparent, children = pausedChildren }
    end
    if state_ and state_.firstPerson then
        local children = { BuildFirstPersonHud(profile) }
        local exploreDismiss = BuildExploreDismiss(profile)
        if exploreDismiss then children[#children + 1] = exploreDismiss end
        local explore = BuildExplorePanel(profile)
        if explore then children[#children + 1] = explore end
        local timeControl = BuildTimeControl(profile)
        if timeControl then children[#children + 1] = timeControl end
        Social.AppendLayers(children, profile)
        return UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none",
            backgroundColor = COLORS.transparent, children = children }
    end
    if state_ and state_.visitMode then
        local visitChildren = { BuildTopBar(profile) }
        local exploreDismiss = BuildExploreDismiss(profile)
        if exploreDismiss then visitChildren[#visitChildren + 1] = exploreDismiss end
        local explore = BuildExplorePanel(profile)
        if explore then visitChildren[#visitChildren + 1] = explore end
        local timeControl = BuildTimeControl(profile)
        if timeControl then visitChildren[#visitChildren + 1] = timeControl end
        local footer = BuildFooter(profile)
        if footer then visitChildren[#visitChildren + 1] = footer end
        Social.AppendLayers(visitChildren, profile)
        return UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none",
            backgroundColor = COLORS.transparent, children = visitChildren }
    end
    local children = { BuildTopBar(profile) }
    local autoBuildDismiss = BuildAutoBuildDismiss(profile)
    if autoBuildDismiss then children[#children + 1] = autoBuildDismiss end
    local resetDismiss = BuildResetConfirmationDismiss(profile)
    if resetDismiss then children[#children + 1] = resetDismiss end
    local portalBindingDismiss = BuildPortalBindingDismiss(profile)
    if portalBindingDismiss then children[#children + 1] = portalBindingDismiss end
    local exploreDismiss = BuildExploreDismiss(profile)
    if exploreDismiss then children[#children + 1] = exploreDismiss end
    local islandDismiss = BuildIslandManagerDismiss(profile)
    if islandDismiss then children[#children + 1] = islandDismiss end
    local dismiss = BuildLibraryDismiss(profile)
    if dismiss then children[#children + 1] = dismiss end
    if libraryOpen_ then children[#children + 1] = BuildLibraryPanel(profile, profile.mode == "mobile") end
    local islandManager = BuildIslandManager(profile)
    if islandManager then children[#children + 1] = islandManager end
    local terrainDismiss = BuildTerrainDismiss(profile)
    if terrainDismiss then children[#children + 1] = terrainDismiss end
    local terrainPanel = BuildTerrainPanel(profile)
    if terrainPanel then children[#children + 1] = terrainPanel end
    local autoBuildPanel = BuildAutoBuildPanel(profile)
    if autoBuildPanel then children[#children + 1] = autoBuildPanel end
    local resetPanel = BuildResetConfirmationPanel(profile)
    if resetPanel then children[#children + 1] = resetPanel end
    local portalBindingPanel = BuildPortalBindingPanel(profile)
    if portalBindingPanel then children[#children + 1] = portalBindingPanel end
    local explore = BuildExplorePanel(profile)
    if explore then children[#children + 1] = explore end
    local inspector = BuildInspector(profile)
    if inspector then children[#children + 1] = inspector end
    local context = BuildContextBar(profile)
    if context then children[#children + 1] = context end
    local mobileBottom = BuildMobileBottom(profile)
    if mobileBottom then children[#children + 1] = mobileBottom end
    local timeControl = BuildTimeControl(profile)
    if timeControl then children[#children + 1] = timeControl end
    local footer = BuildFooter(profile)
    if footer then children[#children + 1] = footer end
    local terrainDiscoveryDismiss = IslandUI._BuildTerrainDiscoveryDismiss(profile)
    if terrainDiscoveryDismiss then children[#children + 1] = terrainDiscoveryDismiss end
    local terrainDiscoveryPanel = IslandUI._BuildTerrainDiscoveryPanel(profile)
    if terrainDiscoveryPanel then children[#children + 1] = terrainDiscoveryPanel end
    Social.AppendLayers(children, profile)
    -- Reward confirmation is the final interactive layer so the generic video
    -- gate always owns input above terrain, inspector and footer surfaces.
    local rewardGateDismiss = BuildRewardGateDismiss(profile)
    if rewardGateDismiss then children[#children + 1] = rewardGateDismiss end
    local rewardGatePanel = BuildRewardGatePanel(profile)
    if rewardGatePanel then children[#children + 1] = rewardGatePanel end
    return UI.Panel {
        width = "100%", height = "100%", pointerEvents = "box-none",
        backgroundColor = COLORS.transparent,
        children = children,
    }
end

function Social.ProfileStateKey(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local islands = Social.PlayerProfileIslands(snapshot)
    local models = Social.PlayerProfileModels(snapshot)
    return table.concat({
        tostring(snapshot.ownerId or snapshot.userId or snapshot.id or ""),
        tostring(snapshot.loading == true), tostring(snapshot.isMe == true),
        tostring(snapshot.feedback or snapshot.message or snapshot.error or ""),
        tostring(snapshot.publishedIslandCount or #islands),
        tostring(snapshot.publishedModelCount or snapshot.totalModels or #models),
        tostring(snapshot.totalLikes or snapshot.likes or 0),
    }, "\30")
end

function Social.GuestbookStateKey(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local messages = Social.GuestbookMessages(snapshot)
    local last = type(messages[#messages]) == "table" and messages[#messages] or {}
    return table.concat({
        tostring(snapshot.ownerId or snapshot.userId or ""), tostring(snapshot.islandId or ""),
        tostring(snapshot.loading == true), tostring(snapshot.posting == true),
        tostring(snapshot.canPost), tostring(snapshot.isOwn == true), tostring(snapshot.source or ""),
        tostring(snapshot.feedback or snapshot.message or snapshot.error or ""),
        tostring(#messages), tostring(last.id or last.messageId or ""),
        tostring(last.text or last.message or last.content or ""),
    }, "\30")
end

local function TerrainStructureKey(open, purpose, selectedId, pendingId)
    return table.concat({ tostring(open == true), tostring(purpose or "manage"),
        tostring(selectedId or ""), tostring(pendingId or "") }, ":")
end

local function CachedListStructureKey(list, kind)
    if type(list) ~= "table" then return tostring(kind) .. ":empty" end
    local cache = structureListCache_[list]
    if cache and cache[kind] then return cache[kind] end
    cache = cache or {}
    local parts = { tostring(kind) }
    for _, item in ipairs(list) do
        if kind == "asset" then
            parts[#parts + 1] = table.concat({ tostring(item.id), tostring(item.versionId),
                tostring(item.favorite), tostring(item.publishedVersion), tostring(item.withdrawn),
                tostring(item.license), tostring(item.thumbnail) }, ":")
        elseif kind == "auto" then
            parts[#parts + 1] = table.concat({ tostring(item.id), tostring(item.versionId),
                tostring(item.thumbnail) }, ":")
        elseif kind == "terrain" then
            parts[#parts + 1] = table.concat({ tostring(item.id), tostring(item.name),
                tostring(item.generated), tostring(item.seed), tostring(item.inUseCount),
                tostring(item.rewardRequired), tostring(item.unlocked), tostring(item.locked) }, ":")
        else
            -- Live model counts are deliberately excluded so placement does
            -- not destroy/recreate every overlay and list.
            parts[#parts + 1] = table.concat({ tostring(item.id), tostring(item.name),
                tostring(item.active), tostring(item.published) }, ":")
        end
    end
    local key = table.concat(parts, "\30")
    cache[kind] = key
    structureListCache_[list] = cache
    return key
end

local function StructureSignature(state)
    if not state then
        return table.concat({ "empty", tostring(paused_), tostring(social_.playerProfileOpen),
            tostring(social_.guestbookOpen), Social.ProfileStateKey(social_.playerProfile),
            Social.GuestbookStateKey(social_.guestbook) }, "|")
    end
    local parts = {
        tostring(profile_ and profile_.mode or ""), tostring(paused_), tostring(libraryOpen_), tostring(state.mode),
        tostring(islandManagerOpen_), tostring(RewardGateOpen()), tostring(autoBuildOpen_),
        tostring(social_.playerProfileOpen), Social.ProfileStateKey(social_.playerProfile),
        tostring(social_.guestbookOpen), Social.GuestbookStateKey(social_.guestbook),
        tostring(state.islandMarketSyncBusy), tostring(state.islandMarketSyncIslandId),
        tostring(rewardGateState_ and rewardGateState_.phase),
        tostring(rewardGateState_ and (rewardGateState_.feedback or rewardGateState_.message)),
        tostring(AutoBuildSelectionCount()), tostring(portalBindingOpen_), tostring(resetConfirmOpen_),
        tostring(exploreOpen_), tostring(renameIslandId_), tostring(terrainRenameId_),
        tostring(deleteConfirmId_), tostring(state.firstPerson),
        TerrainStructureKey(terrainOpen_, terrainPurpose_, terrainSelectedId_,
            rewardGateState_ and rewardGateState_.key),
        tostring(state.terrainId or state.terrainPreset or IslandTerrainCatalog.DEFAULT_ID),
        tostring(state.visitMode),
        tostring(exploreSort_),
        tostring(state.firstPersonRun),
        tostring(state.firstPersonFlying),
        tostring(IslandUITheme.Mode(state.timeOfDay)),
        tostring(timePanelOpen_), tostring(state.timeAuto),
        tostring(mobileBottomHidden_),
        tostring(state.firstPersonJoystickActive),
        tostring(math.floor((state.firstPersonJoystickX or 0) + 0.5)),
        tostring(math.floor((state.firstPersonJoystickY or 0) + 0.5)),
        tostring(state.transformMode),
        tostring(state.libraryTab), tostring(libraryCategory_), tostring(state.selected and state.selected.id or "none"),
        tostring(state.selected and state.selected.canCustomize),
        tostring(state.selected and state.selected.isPortal),
        tostring(state.selected and state.selected.portalBound),
        tostring(state.selected and state.selected.portalTargetIslandId),
        CachedListStructureKey(state.assets, "asset"),
        CachedListStructureKey(state.autoBuildAssets, "auto"),
        CachedListStructureKey(state.terrainPresets, "terrain"),
        CachedListStructureKey(state.islands, "island"),
    }
    return table.concat(parts, "|")
end

-- Kept engine-free for regression coverage: content-only state must never
-- recreate the native UI root during an interaction.
IslandUI._StructureSignature = StructureSignature
IslandUI._PlaceActionSucceeded = PlaceActionSucceeded
IslandUI._ViewportBottomForMode = ViewportBottomForMode
IslandUI._ViewportTopForMode = ViewportTopForMode
IslandUI._MobileHeaderTop = MobileHeaderTop
IslandUI._MobileHeaderActionWidth = MobileHeaderActionWidth
IslandUI._MobileHeaderChildren = MobileHeaderChildren
IslandUI._MobileHeaderUtilityChildren = MobileHeaderUtilityChildren
IslandUI._LibraryCategoryStripHeight = LibraryCategoryStripHeight
IslandUI._LibraryCategoryLayout = LibraryCategoryLayout
IslandUI._FirstPersonEntryMetrics = FirstPersonEntryMetrics
IslandUI._MobileIslandCardHeight = MobileIslandCardHeight
IslandUI._ExploreActionDirection = ExploreActionDirection
IslandUI._ExploreCardColumns = ExploreCardColumns
IslandUI._TerrainPanelWidth = TerrainPanelWidth
IslandUI._AssetListContentHeight = AssetListContentHeight
IslandUI._AssetVirtualRows = AssetVirtualRows
IslandUI._AssetVirtualRowHeight = AssetVirtualRowHeight
IslandUI._VirtualPoolUpperBound = VirtualPoolUpperBound
IslandUI._PauseTitleLayout = PauseTitleLayout
IslandUI._PauseTitleAsset = PAUSE_TITLE_ASSET
IslandUI._PauseCreditLayout = PauseCreditLayout
IslandUI._PauseCreditText = PAUSE_CREDIT_TEXT
IslandUI._CanResumePauseAt = CanResumePauseAt
IslandUI._ResumePauseFromPointer = ResumePauseFromPointer
IslandUI._IslandManagerColumns = IslandManagerColumns
IslandUI._TerrainManagementLabels = TerrainManagementLabels
IslandUI._SortExploreEntries = SortExploreEntries
IslandUI._ExploreVirtualData = IslandUI._ExploreListVirtualization.Data
IslandUI._ExploreVirtualSignature = IslandUI._ExploreListVirtualization.Signature
IslandUI._ExplorePoolBuffer = IslandUI._ExploreListVirtualization.POOL_BUFFER
IslandUI._MobilePanelWidth = MobilePanelWidth
IslandUI._AssetActionWidth = AssetActionWidth
IslandUI._AssetListColumns = AssetListColumns
IslandUI._DesktopLibraryWidth = DesktopLibraryWidth
IslandUI._ResponsiveMode = ResponsiveMode
IslandUI._ShouldBuildMobileBottom = ShouldBuildMobileBottom
IslandUI._TerrainCardColumns = TerrainCardColumns
IslandUI._ResolveTerrainId = ResolveTerrainId
IslandUI._TerrainStructureKey = TerrainStructureKey
IslandUI._InitialTerrainSelection = InitialTerrainSelection
IslandUI._AssetSelectionKey = AssetSelectionKey
IslandUI._AutoBuildButtonLabel = AutoBuildButtonLabel
IslandUI._ResetButtonDisabled = ResetButtonDisabled
IslandUI._MobileModalTop = MobileModalTop
IslandUI._SocialModalGeometry = Social.ModalGeometry
IslandUI._RewardGateStateKey = RewardGateStateKey
IslandUI._TerrainDiscoveryDelay = TerrainDiscoveryGuide.DELAY
IslandUI._ShouldOpenTerrainDiscovery = TerrainDiscoveryGuide.ShouldOpen
IslandUI._TerrainDiscoveryFlightDelta = TerrainDiscoveryGuide.FlightDelta
IslandUI._TerrainDiscoveryPanelGeometry = TerrainDiscoveryGuide.PanelGeometry

function IslandUI._EnsureUIInitialized()
    if uiInitialized_ then return end
    UI.Init(UIRuntimeConfig.Options(UI.Scale.DEFAULT))
    uiInitialized_ = true
end

function IslandUI.ShowBootstrap()
    IslandUI._EnsureUIInitialized()
    bootstrapActive_ = true
    UI.SetScale(UI.Scale.DEFAULT)
    local width = LogicalViewport()
    local cardWidth = math.max(220, math.min(310, width - 48))
    UI.SetRoot(UI.SafeAreaView {
        width = "100%", height = "100%", edges = "none", nativeMenuInset = false,
        pointerEvents = "box-none",
        children = {
            UI.Panel { width = "100%", height = "100%", alignItems = "center", justifyContent = "center",
                backgroundColor = COLORS.transparent, pointerEvents = "none", children = {
                    UI.Panel { width = cardWidth, padding = 18, gap = 7, flexDirection = "column",
                        alignItems = "center", backgroundColor = COLORS.panelGlass,
                        backdropBlur = 12, borderColor = COLORS.gold, borderWidth = 2,
                        borderRadius = 20, boxShadow = { { x = 0, y = 8, blur = 24, color = COLORS.shadow } },
                        children = {
                            UI.Label { text = "云岛造物工坊", fontSize = 17, fontWeight = "900",
                                fontColor = COLORS.ink, textAlign = "center" },
                            UI.Label { text = "正在准备模型、地形与空岛……", fontSize = 10,
                                fontWeight = "bold", fontColor = COLORS.blueDark, textAlign = "center" },
                            UI.Label { text = VERSION, fontSize = 8, fontColor = COLORS.muted,
                                textAlign = "center" },
                        },
                    },
                } },
        },
    }, true)
end

function IslandUI.Init(callbacks)
    callbacks_ = callbacks
    state_, status_, structureSignature_ = nil, "正在打开空岛……", nil
    paused_ = false
    statusVisibleUntil_ = ClockNow() + STATUS_VISIBLE_SECONDS
    libraryOpen_ = false
    exploreOpen_ = false
    exploreSort_ = "latest"
    social_.playerProfileOpen, social_.playerProfile = false, {}
    social_.guestbookOpen, social_.guestbook, social_.guestbookDraft = false, {}, ""
    timePanelOpen_ = false
    mobileBottomHidden_ = false
    rewardGateState_ = { phase = "idle" }
    terrainOpen_, terrainPurpose_, autoBuildOpen_, portalBindingOpen_, resetConfirmOpen_ =
        false, "manage", false, false, false
    terrainSelectedId_ = nil
    terrainRenameId_, terrainRenameValue_, terrainFeedback_ = nil, "", ""
    autoBuildSelection_, autoBuildSelectionInitialized_ = {}, false
    scrollPositions_ = {}
    structureListCache_ = setmetatable({}, { __mode = "k" })
    autoBuildAttentionPlayed_ = false
    terrainDiscovery_ = TerrainDiscoveryGuide.New(terrainDiscovery_.handledThisRun)
    islandManagerOpen_, renameIslandId_, renameIslandValue_, deleteConfirmId_ = false, nil, "", nil
    IslandUI._EnsureUIInitialized()
    bootstrapActive_ = false
    IslandUI.Rebuild()
end

function IslandUI.Rebuild(exitBootstrap)
    -- The bootstrap surface owns the root throughout a portal hand-off. Only
    -- FinishPortalLoading may explicitly replace it once the destination is ready.
    if bootstrapActive_ and exitBootstrap ~= true then return end
    if exitBootstrap == true then bootstrapActive_ = false end
    if rebuilding_ then return end
    rebuilding_ = true
    UI.ClearFocus()
    UI.SetScale(UI.Scale.DEFAULT)
    profile_ = CurrentProfile()
    pendingScrollRestores_ = {}
    statusLabel_, titleLabel_, countLabel_, selectionLabel_, selectionTransformLabel_ = nil, nil, nil, nil, nil
    undoButton_, redoButton_, terrainButton_, autoBuildButton_, timeButton_, timeSlider_ = nil, nil, nil, nil, nil, nil
    placementPanel_, placementStatusLabel_, placementConfirmButton_ = nil, nil, nil
    terrainDiscovery_.carrier, terrainDiscovery_.card = nil, nil
    UI.SetRoot(UI.SafeAreaView {
        width = "100%", height = "100%", edges = "none", nativeMenuInset = false,
        pointerEvents = "box-none", children = { BuildRoot(profile_) },
    }, true)
    -- SetRoot happens between interaction frames. Resolve Yoga now, then clamp
    -- and restore every list before the next render; waiting for ScrollView's
    -- first Update would still see zero-sized pre-layout content and jump to 0.
    UI.Layout()
    for _, restore in ipairs(pendingScrollRestores_) do
        local scroll = restore.scroll
        if scroll and scroll.UpdateContentSize and scroll.SetScroll then
            scroll:UpdateContentSize()
            local bounces = scroll.props.bounces
            scroll.props.bounces = false
            scroll:SetScroll(restore.x, restore.y)
            scroll.props.bounces = bounces
        end
    end
    pendingScrollRestores_ = {}
    if terrainDiscovery_.phase == "flying" and terrainDiscovery_.carrier
        and terrainDiscovery_.card and terrainButton_ then
        local animated = pcall(function()
            local source = terrainDiscovery_.card:GetAbsoluteLayoutForHitTest()
            local target = terrainButton_:GetAbsoluteLayoutForHitTest()
            local dx, dy = TerrainDiscoveryGuide.FlightDelta(source, target)
            terrainDiscovery_.carrier:Animate({
                keyframes = {
                    [0] = { translateX = 0, translateY = 0, opacity = 1 },
                    [0.72] = { translateX = dx * 0.72, translateY = dy * 0.72, opacity = 0.94 },
                    [1] = { translateX = dx, translateY = dy, opacity = 0 },
                },
                duration = 0.58, easing = "easeInOutCubic", fillMode = "forwards",
                onComplete = function()
                    if terrainDiscovery_.phase == "flying" then
                        terrainDiscovery_.flightFinished = true
                    end
                end,
            })
            terrainDiscovery_.card:Animate({
                keyframes = {
                    [0] = { scale = 1 },
                    [0.55] = { scale = 0.72 },
                    [1] = { scale = 0.08 },
                },
                duration = 0.58, easing = "easeInOutCubic", fillMode = "forwards",
            })
        end)
        if not animated then terrainDiscovery_.flightFinished = true end
    end
    if state_ and terrainButton_ and terrainDiscovery_.attentionPending and terrainButton_.Animate then
        pcall(function()
            terrainButton_:Animate({
                keyframes = {
                    [0] = { scale = 1.0, translateY = 0, borderWidth = 1 },
                    [0.45] = { scale = 1.09, translateY = -2, borderWidth = 2 },
                    [1] = { scale = 1.0, translateY = 0, borderWidth = 1 },
                },
                duration = 0.46, easing = "easeInOut", loop = 3,
            })
        end)
        terrainDiscovery_.attentionPending = false
    end
    if state_ and profile_.mode == "mobile" and autoBuildButton_
        and not autoBuildAttentionPlayed_ and autoBuildButton_.Animate then
        local animated = pcall(function()
            autoBuildButton_:Animate({
                keyframes = {
                    [0] = { scale = 1.0, opacity = 0.98 },
                    [0.5] = { scale = 1.04, opacity = 1.0 },
                    [1] = { scale = 1.0, opacity = 0.98 },
                },
                duration = 0.9, easing = "easeInOut", loop = 2,
            })
        end)
        autoBuildAttentionPlayed_ = animated
    end
    callbacks_.setViewportRect(
        profile_.viewportLeft * profile_.scale,
        profile_.viewportTop * profile_.scale,
        profile_.viewportRight * profile_.scale,
        profile_.viewportBottom * profile_.scale,
        profile_.scale,
        profile_.mode
    )
    structureSignature_ = StructureSignature(state_)
    rebuilding_ = false
    if state_ then IslandUI.Refresh(state_, nil) end
end

function IslandUI.Refresh(state, message)
    state_ = state or state_
    if message and message ~= "" then ShowStatus(message) end
    if not state_ then return end
    ApplyTimeTheme(state_.timeOfDay, state_.timePhase)
    local signature = StructureSignature(state_)
    if not rebuilding_ and structureSignature_ and signature ~= structureSignature_ then
        IslandUI.Rebuild()
        return
    end
    structureSignature_ = signature
    if titleLabel_ then SetTextIfChanged(titleLabel_, state_.name or "我的空岛") end
    if countLabel_ then
        SetTextIfChanged(countLabel_, profile_ and profile_.mode == "mobile"
            and VERSION or (tostring(state_.count or 0) .. " 个模型 · " .. VERSION))
    end
    if statusLabel_ then SetTextIfChanged(statusLabel_, IsStatusVisible() and status_ or "") end
    if undoButton_ then undoButton_:SetDisabled(not state_.canUndo) end
    if redoButton_ then redoButton_:SetDisabled(ResetButtonDisabled(state_.count)) end
    if timeButton_ then
        local phaseMark = ({ dawn = "晨", day = "日", dusk = "暮", night = "夜" })[state_.timePhase] or "日"
        SetTextIfChanged(timeButton_, phaseMark .. " " .. tostring(state_.timeLabel or "09:30"))
    end
    if timeSlider_ then timeSlider_.props.value = state_.timeOfDay or 9.5 end
    if placementStatusLabel_ then
        local valid = state_.placementValid == true
        SetTextIfChanged(placementStatusLabel_, profile_ and profile_.mode == "mobile"
                and (valid and "可放" or "不可")
            or (valid and "点击草地放置" or "当前位置不可放置"))
        SetStyleIfStateChanged(placementStatusLabel_, "_validState", valid, { fontColor = valid and COLORS.green or COLORS.danger })
        if placementPanel_ then
            SetStyleIfStateChanged(placementPanel_, "_validState", valid, { borderColor = valid and COLORS.green or COLORS.danger })
        end
        if placementConfirmButton_ then placementConfirmButton_:SetDisabled(not valid) end
    end
    if selectionLabel_ and state_.selected then SetTextIfChanged(selectionLabel_, state_.selected.name or "模型") end
    if selectionTransformLabel_ and state_.selected then
        SetTextIfChanged(selectionTransformLabel_, string.format("X %.2f · Y %.2f · Z %.2f\n旋转 %.0f° · 等比 %.2f",
            state_.selected.x, state_.selected.y or 0, state_.selected.z,
            state_.selected.rotationY, state_.selected.scale))
    end
end

function IslandUI.Update(timeStep)
    if bootstrapActive_ then return end
    if terrainDiscovery_.phase == "flying" then
        if terrainDiscovery_.flightFinished and not rebuilding_ then
            terrainDiscovery_.flightFinished = false
            terrainDiscovery_.phase = "done"
            terrainDiscovery_.attentionPending = true
            IslandUI.Rebuild()
        end
        return
    end
    if terrainDiscovery_.phase ~= "waiting" or terrainDiscovery_.handledThisRun
        or not callbacks_ or type(callbacks_.terrainDiscoveryEligibility) ~= "function" then return end

    local ok, eligible = pcall(callbacks_.terrainDiscoveryEligibility)
    if not ok or eligible == nil then return end
    if eligible ~= true then
        terrainDiscovery_.handledThisRun = true
        terrainDiscovery_.phase = "done"
        return
    end
    terrainDiscovery_.elapsed = terrainDiscovery_.elapsed + math.max(0, tonumber(timeStep) or 0)
    if not TerrainDiscoveryGuide.ShouldOpen(terrainDiscovery_.phase, terrainDiscovery_.elapsed, eligible,
        BlockingSurfaceOpen(), state_) then return end

    terrainDiscovery_.handledThisRun = true
    terrainDiscovery_.phase = "open"
    terrainDiscovery_.doNotRemind = false
    IslandUI.Rebuild()
end

function IslandUI.SetRewardGateState(snapshot)
    local nextState = type(snapshot) == "table" and snapshot or { phase = "closed", open = false }
    if RewardGateStateKey(rewardGateState_) == RewardGateStateKey(nextState) then
        rewardGateState_ = nextState
        return
    end
    rewardGateState_ = nextState
    if uiInitialized_ and callbacks_ and not rebuilding_ then IslandUI.Rebuild() end
end

function IslandUI.SetPaused(value, fromRuntime)
    local nextPaused = value == true
    if paused_ == nextPaused then return false end
    paused_ = nextPaused
    if not fromRuntime and callbacks_ and callbacks_.setPaused then callbacks_.setPaused(nextPaused) end
    if uiInitialized_ and callbacks_ and not rebuilding_ then IslandUI.Rebuild() end
    return true
end

function IslandUI.IsPaused()
    return paused_ == true
end

function IslandUI.SetExploreState(entries, loading, source)
    exploreEntries_ = type(entries) == "table" and entries or exploreEntries_
    exploreLoading_ = loading == true
    exploreSource_ = tostring(source or exploreSource_ or "sample")
    if exploreOpen_ and callbacks_ and not rebuilding_ then IslandUI.Rebuild() end
end

function IslandUI.SetPlayerProfile(snapshot, loading, feedback)
    local nextState = {}
    if type(snapshot) == "table" then
        nextState = Social.CopySnapshot(snapshot)
    elseif snapshot ~= nil then
        nextState.ownerId, nextState.userId = tostring(snapshot), tostring(snapshot)
    else
        nextState = Social.CopySnapshot(social_.playerProfile)
    end
    if loading ~= nil then nextState.loading = loading == true end
    if feedback ~= nil then nextState.feedback = tostring(feedback) end
    social_.playerProfile = nextState
    if nextState.open == true then social_.playerProfileOpen = true end
    if nextState.open == false then social_.playerProfileOpen = false end
    if social_.playerProfileOpen and uiInitialized_ and callbacks_ and not rebuilding_ then
        IslandUI.Rebuild()
    end
end

function IslandUI.OpenPlayerProfile(snapshot, nickname)
    if type(snapshot) == "table" then
        IslandUI.SetPlayerProfile(snapshot)
    else
        local ownerId = snapshot ~= nil and tostring(snapshot) or ""
        social_.playerProfile = {
            ownerId = ownerId, userId = ownerId,
            nickname = Social.NonEmptyText(nickname, "云岛旅人"),
        }
    end
    Social.ClosePrimarySurfaces()
    social_.guestbookOpen, social_.playerProfileOpen = false, true
    if uiInitialized_ and callbacks_ and not rebuilding_ then IslandUI.Rebuild() end
end

function IslandUI.ClosePlayerProfile()
    if not social_.playerProfileOpen then return false end
    social_.playerProfileOpen = false
    if uiInitialized_ and callbacks_ and not rebuilding_ then IslandUI.Rebuild() end
    return true
end

function IslandUI.IsPlayerProfileOpen()
    return social_.playerProfileOpen == true
end

IslandUI.SetPlayerProfileState = IslandUI.SetPlayerProfile

function IslandUI.SetGuestbookState(snapshot)
    local nextState = {}
    if type(snapshot) == "table" then
        nextState = Social.CopySnapshot(snapshot)
    else
        nextState = Social.CopySnapshot(social_.guestbook)
    end
    nextState.messages = type(nextState.messages) == "table" and nextState.messages or {}
    social_.guestbook = nextState
    if nextState.sent == true or nextState.posted == true or nextState.clearDraft == true then
        social_.guestbookDraft = ""
    end
    if nextState.open == true then social_.guestbookOpen = true end
    if nextState.open == false then social_.guestbookOpen = false end
    if social_.guestbookOpen and uiInitialized_ and callbacks_ and not rebuilding_ then
        IslandUI.Rebuild()
    end
end

function IslandUI.OpenGuestbook(snapshot)
    if type(snapshot) == "table" then
        IslandUI.SetGuestbookState(snapshot)
    elseif type(social_.guestbook) ~= "table" or next(social_.guestbook) == nil then
        local ownerId, islandId, owner = Social.CurrentGuestbookIdentity()
        social_.guestbook = {
            ownerId = ownerId, userId = ownerId, islandId = islandId,
            owner = owner, nickname = owner, messages = {},
            canPost = state_ and state_.visitMode == true or false,
            isOwn = not (state_ and state_.visitMode == true),
        }
    end
    Social.ClosePrimarySurfaces()
    social_.playerProfileOpen, social_.guestbookOpen = false, true
    if uiInitialized_ and callbacks_ and not rebuilding_ then IslandUI.Rebuild() end
end

function IslandUI.CloseGuestbook()
    if not social_.guestbookOpen then return false end
    social_.guestbookOpen, social_.guestbookDraft = false, ""
    if uiInitialized_ and callbacks_ and not rebuilding_ then IslandUI.Rebuild() end
    return true
end

function IslandUI.IsGuestbookOpen()
    return social_.guestbookOpen == true
end

function IslandUI.OpenExplore()
    libraryOpen_, islandManagerOpen_, exploreOpen_, timePanelOpen_ = false, false, true, false
    IslandUI.Rebuild()
end

function IslandUI.IsPointOverUI(x, y)
    local scale = math.max(0.01, UI.GetScale())
    return UI.FindWidgetAt(x / scale, y / scale) ~= nil
end

function IslandUI.HasFocus() return UI.GetFocus() ~= nil end
function IslandUI.ClearFocus() UI.ClearFocus() end
function IslandUI.ShowToast(message, variant)
    UI.Toast.Show({
        message = tostring(message or ""),
        variant = variant or "info",
        duration = 4.5,
    })
end
function IslandUI.GetProfile() return profile_ end
function IslandUI.GetVersion() return VERSION end
function IslandUI.Shutdown()
    rewardGateState_ = { phase = "idle" }
    paused_ = false
    social_.playerProfileOpen, social_.playerProfile = false, {}
    social_.guestbookOpen, social_.guestbook, social_.guestbookDraft = false, {}, ""
    if uiInitialized_ then UI.Shutdown() end
    uiInitialized_, bootstrapActive_ = false, false
end

return IslandUI
