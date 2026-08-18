package.path = "scripts/?.lua;" .. package.path

package.preload["urhox-libs/UI"] = function() return {} end

local BuilderUI = require("BuilderUI")

assert(BuilderUI.GetVersion() == "v2.16.0",
    "the native-mobile workbench layout release must expose its visible version")
assert(BuilderUI._ResponsiveMode(1600, 1000, "Android") == "mobile"
    and BuilderUI._ResponsiveMode(1600, 1000, "iOS") == "mobile"
    and BuilderUI._ResponsiveMode(1600, 1000, "HarmonyOS") == "mobile",
    "large native mobile screens must never enter tablet or desktop workbench UI")
assert(BuilderUI._ResponsiveMode(1200, 700, "Mac") == "desktop"
    and BuilderUI._ResponsiveMode(800, 560, "Mac") == "tablet"
    and BuilderUI._ResponsiveMode(800, 560, "Web") == "tablet",
    "desktop and web preview windows must respond to their current viewport size")
assert(BuilderUI._TemplateListHeight(0) == 44,
    "an empty model category must keep a compact readable placeholder")
assert(BuilderUI._TemplateListHeight(1) == 52,
    "one workbench model card must use the authored row height")
local templates = {}
for index = 1, 69 do templates[index] = { id = "template-" .. tostring(index) } end
local virtualRows = BuilderUI._TemplateVirtualRows(templates)
assert(#virtualRows == 69 and virtualRows[1].item == templates[1]
        and virtualRows[69].item == templates[69],
    "workbench virtualization must preserve every model and its source order")
local emptyRows = BuilderUI._TemplateVirtualRows({})
assert(#emptyRows == 1 and emptyRows[1].empty,
    "an empty model category must remain one pooled placeholder row")

local buttonWidth, categoryHeight, columns = BuilderUI._TemplateCategoryLayout(272, 11)
assert(columns == 4 and buttonWidth == 65 and categoryHeight == 86,
    "desktop model categories must wrap into visible rows instead of a horizontal scroller")

local narrowWidth, narrowHeight, narrowColumns = BuilderUI._TemplateCategoryLayout(190, 11)
assert(narrowColumns == 3 and narrowWidth == 60 and narrowHeight == 116,
    "wrapped desktop categories must remain readable on the narrow tablet dock")

local desktopWrap, desktopVirtualRows = BuilderUI._TemplateLibraryPolicy("desktop")
assert(desktopWrap == true and desktopVirtualRows == true,
    "desktop must wrap every category while retaining pooled model rows")
local tabletWrap, tabletVirtualRows = BuilderUI._TemplateLibraryPolicy("tablet")
assert(tabletWrap == true and tabletVirtualRows == true,
    "tablet must use the same wrapped categories and pooled model rows")
local mobileWrap, mobileVirtualRows = BuilderUI._TemplateLibraryPolicy("mobile")
assert(mobileWrap == false and mobileVirtualRows == true,
    "phone must preserve its compact category strip while pooling model rows")

local modelViewport = BuilderUI._TemplateLibraryViewportHeight(400, categoryHeight)
local modelPool = BuilderUI._VirtualPoolUpperBound(modelViewport, 52, 5, 3)
assert(modelViewport == 267 and modelPool == 11 and modelPool < #virtualRows,
    "category tabs must share the list viewport instead of permanently shrinking it")
assert(BuilderUI._TemplateVirtualContentHeight(69, 57, categoryHeight) == 4019,
    "the unified scroll extent must include both wrapped categories and every model row")
local firstAtTop, lastAtTop = BuilderUI._TemplateVirtualVisibleRange(
    69, 57, 0, modelViewport, categoryHeight)
local firstAfterHeader, lastAfterHeader = BuilderUI._TemplateVirtualVisibleRange(
    69, 57, categoryHeight, modelViewport, categoryHeight)
local firstAfterRow, lastAfterRow = BuilderUI._TemplateVirtualVisibleRange(
    69, 57, categoryHeight + 57, modelViewport, categoryHeight)
assert(firstAtTop == 1 and lastAtTop == 4
        and firstAfterHeader == 1 and lastAfterHeader == 5
        and firstAfterRow == 2 and lastAfterRow == 6,
    "virtual model rows must follow the category header through one continuous vertical scroll")
assert(BuilderUI._CategoryGestureIsHorizontal(18, 4)
        and not BuilderUI._CategoryGestureIsHorizontal(4, 18)
        and not BuilderUI._CategoryGestureIsHorizontal(8, 8),
    "the nested phone category strip must yield vertical and ambiguous drags to the model list")

assert(BuilderUI._IsTransformRefresh({ _builderRefreshKind = "transform" }) == true
    and BuilderUI._IsTransformRefresh({}) == false,
    "only explicit transform deltas may enter the O(1) editor refresh path")
assert(math.abs(BuilderUI._TransformRefreshInterval("mobile") - 1 / 30) < 0.000001
    and BuilderUI._TransformRefreshInterval("desktop") == 0,
    "phone transform labels must be capped at 30 Hz while desktop consumes once per UI frame")

local liveBlock = { x = 1 }
local delta = { _builderRefreshKind = "transform", selected = liveBlock }
BuilderUI.Refresh(delta)
assert(BuilderUI._TakePendingTransformState(1 / 60, "mobile") == nil,
    "the first 60 Hz phone frame must retain the pending delta")
liveBlock.x = 2
assert(BuilderUI._TakePendingTransformState(1 / 60, "mobile") == delta
    and delta.selected.x == 2,
    "the second phone frame must consume the latest live transform without copying it")

print("builder-ui-structure-spec: ok")
