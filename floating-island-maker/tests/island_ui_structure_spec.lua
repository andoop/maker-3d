package.path = "scripts/?.lua;" .. package.path

package.preload["urhox-libs/UI"] = function() return {} end

local IslandUI = require("IslandUI")
local BuilderUI = require("BuilderUI")
local IslandTerrainCatalog = require("IslandTerrainCatalog")
local UIRuntimeConfig = require("UIRuntimeConfig")

assert(IslandUI._PlaceActionSucceeded(true), "successful placement may close the mobile library")
assert(not IslandUI._PlaceActionSucceeded(false), "failed placement must leave the mobile library open")
assert(not IslandUI._PlaceActionSucceeded(nil), "missing placement result must not look successful")
local mobilePlacementLabels = IslandUI._PlacementControlLabels(true)
local desktopPlacementLabels = IslandUI._PlacementControlLabels(false)
assert(mobilePlacementLabels.switchModel == "换模型"
        and desktopPlacementLabels.switchModel == "换模型",
    "mobile and desktop placement bars must expose the model-library shortcut")
assert(mobilePlacementLabels.confirm == "放置" and desktopPlacementLabels.close == "完成",
    "adding model switching must preserve each placement bar's established actions")
assert(IslandUI._ViewportBottomForMode("mobile", 800, 72) == 800,
    "mobile 3D viewport must extend behind the floating bottom controls")
assert(IslandUI._ViewportBottomForMode("desktop", 800, 22) == 778,
    "desktop viewport must continue reserving its footer")
assert(IslandUI._ViewportTopForMode("mobile", 64) == 0,
    "mobile 3D viewport must extend behind the floating header controls")
assert(IslandUI._ViewportTopForMode("desktop", 48) == 48,
    "desktop viewport must continue reserving its header")
assert(IslandUI._MobilePanelWidth({ width = 320, safe = { left = 0, right = 0 } }) == 276,
    "the compact single-row mobile header must respect both rounded screen edges")
assert(IslandUI._MobileHeaderTop(0, 44) == 50 and IslandUI._MobileHeaderTop(20, 64) == 70,
    "the single-row mobile header must sit immediately below the native mini-program capsule")
assert(IslandUI._MobileHeaderActionWidth() == 110
    and IslandUI._MobilePanelWidth({ width = 320, safe = { left = 0, right = 0 } })
        - IslandUI._MobileHeaderActionWidth() >= 160,
    "larger terrain controls must retain readable room for the island name")
assert(table.concat(IslandUI._MobileHeaderChildren(
        "岛名", "地形", "一键建岛", "保存", "撤销", "重做"), ",")
        == "地形,一键建岛,岛名",
    "terrain creation controls must stay on the mobile header's first row")
assert(table.concat(IslandUI._MobileHeaderUtilityChildren("保存", "撤销", "重做", "暂停"), ",")
        == "保存,撤销,重做,暂停",
    "save, history and pause controls must occupy their own row below the native capsule")
assert(IslandUI._AssetActionWidth("重新发布", true, 34) > IslandUI._AssetActionWidth("发布", true, 34),
    "model action buttons must expand with their label instead of clipping republish")
assert(IslandUI._AssetListColumns(619) == 1,
    "narrow model libraries must keep one readable card per row")
assert(IslandUI._AssetListColumns(620) == 2,
    "wide model libraries must use two columns instead of wasting horizontal space")
assert(IslandUI._DesktopLibraryWidth({ width = 1200 }) >= 650
    and IslandUI._DesktopLibraryWidth({ width = 1100 }) >= 580,
    "desktop model libraries must reserve enough width for two readable columns")
assert(IslandUI._ResponsiveMode(1200, 700, "Mac") == "desktop"
    and IslandUI._ResponsiveMode(800, 560, "Windows") == "tablet",
    "desktop systems must continue responding to their current window size")
assert(IslandUI._ResponsiveMode(1440, 900, "Android") == "mobile"
    and IslandUI._ResponsiveMode(1440, 900, "iOS") == "mobile"
    and IslandUI._ResponsiveMode(1440, 900, "HarmonyOS") == "mobile",
    "native phones must always use mobile UI regardless of viewport size")
assert(IslandUI._ResponsiveMode(1200, 700, "Web") == "desktop"
    and IslandUI._ResponsiveMode(800, 560, "Web") == "tablet",
    "web previews must keep their responsive viewport breakpoints")
assert(IslandUI._LibraryCategoryStripHeight() == 34,
    "mobile model categories must keep a compact horizontal strip")
local desktopCategories = IslandUI._LibraryCategoryLayout("desktop", 278, 10)
assert(not desktopCategories.horizontalScroll and desktopCategories.columns == 3
        and desktopCategories.height == 123,
    "desktop categories must restore the fully visible three-column wrapped grid")
local mobileCategories = IslandUI._LibraryCategoryLayout("mobile", 278, 10)
assert(mobileCategories.horizontalScroll and mobileCategories.height == 34,
    "phone categories must preserve the current horizontal scrolling behavior")
local manyAssets = {}
for index = 1, 12 do manyAssets[index] = { source = "builtin" } end
assert(IslandUI._AssetListContentHeight(manyAssets, 1, 8, false, 100) > 1000,
    "desktop all-model results must expose their complete vertical scroll extent")
assert(IslandUI._AssetListContentHeight({ { source = "market", license = "remix" } },
        1, 8, false, 1) >= 112,
    "desktop remixable market cards must reserve all three wrapped action rows")
assert(IslandUI._AssetListContentHeight({ { source = "market", license = "use_only" } },
        1, 8, true, 1) >= 70,
    "phone use-only market cards must reserve both wrapped action rows")
local virtualAssets = {}
for index = 1, 100 do
    virtualAssets[index] = { id = "asset-" .. tostring(index), source = "builtin" }
end
local assetRows = IslandUI._AssetVirtualRows(virtualAssets, 2)
assert(#assetRows == 50 and #assetRows[1].items == 2
        and assetRows[1].items[1] == virtualAssets[1]
        and assetRows[50].items[2] == virtualAssets[100],
    "the home model library must virtualize fixed two-card rows without reordering assets")
local emptyAssetRows = IslandUI._AssetVirtualRows({}, 2)
assert(#emptyAssetRows == 1 and emptyAssetRows[1].empty,
    "an empty home library must remain one readable pooled placeholder row")
local assetRowHeight = IslandUI._AssetVirtualRowHeight({
    { source = "builtin" }, { source = "market", license = "remix" },
}, false)
local assetPool = IslandUI._VirtualPoolUpperBound(400, assetRowHeight, 8, 3)
assert(assetRowHeight == 112 and assetPool == 10 and assetPool < #assetRows,
    "a 100-model home library must retain only visible rows and its six-row pool buffer")
assert(IslandUI._IslandManagerColumns("mobile") == 2
    and IslandUI._IslandManagerColumns("desktop") == 1,
    "the phone island manager must use a compact two-column grid")
local renameTerrain, regenerateTerrain, deleteTerrain = IslandUI._TerrainManagementLabels(0)
assert(renameTerrain == "改名" and regenerateTerrain == "重新生成" and deleteTerrain == "删除地形",
    "terrain management actions must use understandable labels instead of single characters")
local _, inUseTerrain, lockedTerrain = IslandUI._TerrainManagementLabels(2)
assert(inUseTerrain == "正在使用" and lockedTerrain == "禁止删除",
    "terrain cards must explain why an in-use random terrain cannot change")
assert(IslandUI._ShouldBuildMobileBottom("mobile", nil, "select"),
    "the normal phone bottom bar must be visible without a selection")
assert(not IslandUI._ShouldBuildMobileBottom("mobile", { id = 1 }, "select"),
    "the compact selection bar must replace the normal phone bottom bar")
assert(not IslandUI._ShouldBuildMobileBottom("mobile", nil, "place"),
    "the compact placement bar must replace the normal phone bottom bar")
assert(not IslandUI._ShouldBuildMobileBottom("mobile", { id = 1 }, "place"),
    "placement mode must hide the normal phone bottom bar even with stale selection state")
assert(not IslandUI._ShouldBuildMobileBottom("tablet", nil, "select"),
    "tablet layouts must not create the phone bottom bar")
assert(IslandUI._ResolveTerrainId(nil) == IslandTerrainCatalog.DEFAULT_ID
    and IslandUI._ResolveTerrainId("missing-terrain") == IslandTerrainCatalog.DEFAULT_ID,
    "terrain UI must safely fall back to the classic three-island preset")
assert(IslandUI._ResolveTerrainId("windstep-meadow") == "windstep-meadow",
    "terrain UI must preserve a valid authored preset")
assert(IslandUI._InitialTerrainSelection("create", "moonbay-gardens") == IslandTerrainCatalog.DEFAULT_ID,
    "new islands must begin from the current classic three-island terrain")
assert(IslandUI._InitialTerrainSelection("manage", "moonbay-gardens") == "moonbay-gardens",
    "the home terrain picker must start on the active island terrain")
assert(IslandUI._AutoBuildButtonLabel(false) == "一键建岛"
    and not IslandUI._AutoBuildButtonLabel(true):find("✦", 1, true),
    "one-click island labels must avoid unsupported decorative glyphs")
assert(IslandUI._ResetButtonDisabled(0) and not IslandUI._ResetButtonDisabled(1),
    "reset is available only when the current island has content")
assert(IslandUI.GetVersion() == "v2.47.0", "the far-overview stability update must expose the new visible version")
assert(BuilderUI.GetVersion() == "v2.16.0", "the workbench must expose its unified scrolling version")
assert(IslandUI._TerrainCardColumns(329) == 1 and IslandUI._TerrainCardColumns(330) == 2,
    "terrain cards must stay readable on narrow phones and use two columns when space permits")
assert(IslandUI._MobileModalTop({ safe = { top = 8 }, nativeMenuBottom = 54 }) == 62,
    "mobile modals must start below the native mini-program capsule")
local discoveryState = { visitMode = false, firstPerson = false, mode = "select" }
assert(IslandUI._TerrainDiscoveryDelay == 3
    and not IslandUI._ShouldOpenTerrainDiscovery("waiting", 2.99, true, false, discoveryState)
    and IslandUI._ShouldOpenTerrainDiscovery("waiting", 3, true, false, discoveryState),
    "terrain discovery must wait three seconds before opening")
assert(not IslandUI._ShouldOpenTerrainDiscovery("waiting", 3, nil, false, discoveryState)
    and not IslandUI._ShouldOpenTerrainDiscovery("waiting", 3, true, true, discoveryState)
    and not IslandUI._ShouldOpenTerrainDiscovery("waiting", 3, true, false,
        { visitMode = true, firstPerson = false, mode = "select" })
    and not IslandUI._ShouldOpenTerrainDiscovery("waiting", 3, true, false,
        { visitMode = false, firstPerson = true, mode = "select" })
    and not IslandUI._ShouldOpenTerrainDiscovery("waiting", 3, true, false,
        { visitMode = false, firstPerson = false, mode = "place" }),
    "terrain discovery must wait for storage and avoid blocking gameplay surfaces")
local flyX, flyY = IslandUI._TerrainDiscoveryFlightDelta(
    { x = 100, y = 120, w = 300, h = 200 }, { x = 22, y = 18, w = 44, h = 34 })
assert(flyX == -206 and flyY == -185,
    "terrain discovery flight must target the live terrain-button center")
local discoveryGeometry = IslandUI._TerrainDiscoveryPanelGeometry({
    width = 390, height = 844, mode = "mobile", safe = { left = 8, right = 8, top = 10, bottom = 12 },
    nativeMenuBottom = 58, top = 0, footer = 0,
})
assert(discoveryGeometry.left >= 22 and discoveryGeometry.left + discoveryGeometry.width <= 368
    and discoveryGeometry.top >= 66 and discoveryGeometry.top + discoveryGeometry.height <= 818,
    "terrain discovery card must respect mobile rounded corners and native controls")
assert(IslandUI._HandleTerrainDiscoveryBackdropPointer() == false,
    "terrain discovery backdrop taps must be absorbed without closing the guide")
assert(math.abs(IslandUI._TerrainPanelWidth(1200, false, 0) - 816) < 0.001
        and IslandUI._TerrainPanelWidth(1600, false, 0) == 920,
    "desktop terrain panels must expand with the viewport while retaining a readable cap")
assert(IslandUI._TerrainPanelWidth(390, true, 346) == 346,
    "desktop terrain sizing must never leak into the phone layout")
local firstPersonEntry = IslandUI._FirstPersonEntryMetrics("desktop")
assert(firstPersonEntry.width == 114 and firstPersonEntry.padding == 10,
    "the desktop P/Esc entry must reserve visible horizontal padding")
assert(IslandUI._MobileIslandCardHeight() == 78
        and IslandUI._MobileIslandActionHeight() == 28,
    "phone island cards must give their single action row a comfortable touch height")
local regularActionWidth, busyPublishWidth = IslandUI._MobileIslandActionWidths(113, 2, "处理中")
assert(busyPublishWidth >= 26 and regularActionWidth * 4 + busyPublishWidth + 8 == 113,
    "the busy publishing label must fit while all five phone actions remain on one row")
local publishing = IslandUI._IslandPublishButtonState(
    { id = "island-a", published = false },
    { islandMarketSyncBusy = true, islandMarketSyncIslandId = "island-a" })
assert(publishing.label == "处理中" and publishing.disabled and publishing.busy,
    "the island currently syncing with the market must expose disabled progress feedback")
local otherIsland = IslandUI._IslandPublishButtonState(
    { id = "island-b", published = false },
    { islandMarketSyncBusy = true, islandMarketSyncIslandId = "island-a" })
assert(otherIsland.label == "发布" and not otherIsland.disabled,
    "a market sync must not disable another island's publish action")
local publishedIsland = IslandUI._IslandPublishButtonState({ id = "island-a", published = true }, {})
assert(publishedIsland.label == "下架" and not publishedIsland.disabled,
    "idle published islands must retain their normal unpublish action")
assert(IslandUI._ExploreActionDirection(true) == "row"
        and IslandUI._ExploreActionDirection(false) == "column",
    "phone exploration actions must be horizontal without changing desktop cards")
assert(IslandUI._ExploreCardColumns("mobile") == 1,
    "horizontal phone actions require one full-width exploration card per row")
local longExplore = {}
for index = 1, 120 do
    longExplore[index] = { id = "island-" .. index, name = "空岛 " .. index }
end
local virtualExplore = IslandUI._ExploreVirtualData(longExplore, false, "latest")
assert(#virtualExplore == 120
        and IslandUI._VirtualPoolUpperBound(600, 98, 9, IslandUI._ExplorePoolBuffer) < 16,
    "long exploration feeds must retain their data while mounting only a small visible pool")
local loadingExplore = IslandUI._ExploreVirtualData(longExplore, true, "latest")
assert(#loadingExplore == 1 and loadingExplore[1]._empty
        and tostring(loadingExplore[1].message):find("正在寻找"),
    "a refreshing exploration feed should mount one lightweight loading row")
assert(IslandUI._ExploreVirtualSignature({ id = "a", likes = 1 })
        ~= IslandUI._ExploreVirtualSignature({ id = "a", likes = 2 }),
    "recycled exploration cards must refresh when their visible social state changes")
local pauseTitle = IslandUI._PauseTitleLayout({ width = 800, mode = "mobile",
    safe = { left = 8, right = 8, bottom = 10 } })
assert(IslandUI._PauseTitleAsset == "image/ui/cloud-atelier-title-comic.png"
        and math.abs(pauseTitle.width / pauseTitle.height - 1881 / 836) < 0.0001
        and pauseTitle.left == 24 and pauseTitle.bottom == 26,
    "pause mode must use the compact comic title at its native aspect ratio")
assert(IslandUI._PauseContinueLayout == nil,
    "tap-to-resume pause mode must not expose a Continue button layout")
local pauseCredit = IslandUI._PauseCreditLayout({ width = 800, mode = "mobile",
    safe = { left = 8, right = 8, bottom = 10 } }, pauseTitle)
assert(IslandUI._PauseCreditText == "TapTap 制造"
        and pauseCredit.height <= 18 and pauseCredit.fontSize <= 8
        and pauseCredit.left >= pauseTitle.left
        and pauseCredit.left + pauseCredit.width <= pauseTitle.left + pauseTitle.width
        and pauseCredit.bottom >= pauseTitle.bottom
        and pauseCredit.bottom + pauseCredit.height <= pauseTitle.bottom + pauseTitle.height,
    "the TapTap maker credit must remain a small secondary mark inside the pause logo footprint")
local desktopPauseTitle = IslandUI._PauseTitleLayout({ width = 1200, mode = "desktop", safe = {} })
local desktopPauseCredit = IslandUI._PauseCreditLayout(
    { width = 1200, mode = "desktop", safe = {} }, desktopPauseTitle)
assert(desktopPauseCredit.height == 18 and desktopPauseCredit.fontSize == 8
        and desktopPauseCredit.left + desktopPauseCredit.width
            <= desktopPauseTitle.left + desktopPauseTitle.width,
    "desktop screenshot mode must keep the maker credit secondary and inside the authored logo")
local pauseProfile = { width = 800, nativeMenuRight = 150, nativeMenuBottom = 60 }
assert(IslandUI._CanResumePauseAt(pauseProfile, 100, 100),
    "ordinary pause-surface taps must resume gameplay")
assert(not IslandUI._CanResumePauseAt(pauseProfile, 700, 40),
    "the native mini-program capsule must remain usable while paused")
assert(UIRuntimeConfig.FONTS[1].weights.normal == "Fonts/MiSans-Regular.ttf"
    and UIRuntimeConfig.FONTS[1].weights.bold == "Fonts/MiSans-Bold.ttf",
    "first-frame UI must use engine-bundled fonts instead of a download-while-playing font")
assert(IslandUI._TerrainStructureKey(false, "manage", nil, nil)
    ~= IslandUI._TerrainStructureKey(true, "manage", IslandTerrainCatalog.DEFAULT_ID, nil),
    "opening the terrain picker must change the native UI structure")
assert(IslandUI._TerrainStructureKey(true, "manage", IslandTerrainCatalog.DEFAULT_ID, nil)
    ~= IslandUI._TerrainStructureKey(true, "create", "windstep-meadow", nil),
    "terrain purpose and selected preset must participate in the structure signature")
assert(IslandUI._TerrainStructureKey(false, "manage", nil, nil)
    ~= IslandUI._TerrainStructureKey(false, "manage", nil, "cloudpine-spire"),
    "the fixed terrain carried into the ad step must participate in the structure signature")
assert(IslandUI._RewardGateStateKey({ open = true, phase = "waiting", key = "terrain:a", remainingFrames = 2 })
    == IslandUI._RewardGateStateKey({ open = true, phase = "waiting", key = "terrain:a", remainingFrames = 1 }),
    "reward loading frame countdown must not recreate the full native UI")
assert(IslandUI._RewardGateStateKey({ open = true, phase = "waiting", key = "terrain:a" })
    ~= IslandUI._RewardGateStateKey({ open = true, phase = "playing", key = "terrain:a" }),
    "reward prompt phase changes must update the visible loading state")

local explore = {
    { id = "old-hot", updatedAt = 10, likes = 90, favorite = true },
    { id = "new", updatedAt = 30, likes = 2 },
    { id = "middle", updatedAt = 20, likes = 8, favorite = true },
}
assert(IslandUI._SortExploreEntries(explore, "latest")[1].id == "new",
    "latest exploration sort prioritizes publication time")
assert(IslandUI._SortExploreEntries(explore, "hot")[1].id == "old-hot",
    "hot exploration sort prioritizes likes")
local favorites = IslandUI._SortExploreEntries(explore, "favorites")
assert(#favorites == 2 and favorites[1].id == "middle",
    "favorite exploration view filters entries and keeps latest-first ordering")

local function State(count, islandCount, valid, islandName, terrainId)
    return {
        count = count,
        mode = "place",
        firstPerson = false,
        firstPersonRun = false,
        firstPersonFlying = false,
        timePhase = "day",
        timeAuto = true,
        firstPersonJoystickActive = false,
        transformMode = "translate",
        terrainId = terrainId or IslandTerrainCatalog.DEFAULT_ID,
        libraryTab = "builtin",
        placementValid = valid,
        assets = {},
        islands = {
            { id = "main", name = islandName or "我的空岛", count = islandCount, active = true },
        },
    }
end

local initial = IslandUI._StructureSignature(State(2, 2, true))
assert(initial == IslandUI._StructureSignature(State(3, 3, true)),
    "placing a model must not rebuild the whole UI because a live count changed")
assert(initial == IslandUI._StructureSignature(State(2, 2, false)),
    "placement validity is incremental styling and must not rebuild the whole UI")
assert(initial ~= IslandUI._StructureSignature(State(2, 2, true, "新名字")),
    "renaming an island still changes the island manager structure")
assert(initial ~= IslandUI._StructureSignature(State(2, 2, true, nil, "windstep-meadow")),
    "changing the active terrain must rebuild the picker and its current-selection badge")
local marketSyncState = State(2, 2, true)
marketSyncState.islandMarketSyncBusy = true
marketSyncState.islandMarketSyncIslandId = "main"
assert(initial ~= IslandUI._StructureSignature(marketSyncState),
    "island publishing progress must rebuild cards so the busy state is immediately visible")
assert(not IslandUI.IsPaused(), "island UI must begin outside screenshot pause mode")
assert(IslandUI.SetPaused(true, true) and IslandUI.IsPaused(),
    "pause mode must be publicly controllable even before native UI initialization")
assert(initial ~= IslandUI._StructureSignature(State(2, 2, true)),
    "pause state must participate in the native UI structure signature")
local secondaryClick = { x = 100, y = 100, IsPrimaryAction = function() return false end }
assert(not IslandUI._ResumePauseFromPointer(pauseProfile, secondaryClick) and IslandUI.IsPaused(),
    "secondary mouse actions must not leave screenshot pause mode")
local primaryClick = { x = 100, y = 100, IsPrimaryAction = function() return true end }
assert(IslandUI._ResumePauseFromPointer(pauseProfile, primaryClick) and not IslandUI.IsPaused(),
    "one completed tap or primary click on the pause surface must restore normal gameplay")

print("island-ui-structure-spec: ok")
