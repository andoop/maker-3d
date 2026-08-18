---@diagnostic disable: undefined-global, return-type-mismatch, assign-type-mismatch

local UI = require("urhox-libs/UI")
local Catalog = require("BlockCatalog")
local ModelLibraryPresentation = require("ModelLibraryPresentation")
local ModelMiniature = require("ModelMiniature")
local UIRuntimeConfig = require("UIRuntimeConfig")
local ResponsiveLayout = require("ResponsiveLayout")

local BuilderUI = {}
local WORKBENCH_VERSION = "v2.16.0"
local TEMPLATE_ROW_HEIGHT = 52
local TEMPLATE_ROW_GAP = 5
local TEMPLATE_EMPTY_HEIGHT = 44
local TEMPLATE_POOL_BUFFER = 3

local COLORS = {
    ink = { 53, 67, 82, 255 },
    muted = { 108, 119, 128, 255 },
    line = { 174, 205, 211, 255 },
    panel = { 255, 248, 231, 246 },
    blue = { 61, 155, 211, 255 },
    blueDark = { 45, 105, 158, 255 },
    accent = { 235, 180, 55, 255 },
    danger = { 219, 92, 75, 255 },
    page = { 235, 245, 239, 255 },
    viewport = { 232, 246, 251, 255 },
    white = { 255, 255, 255, 255 },
    white90 = { 255, 253, 245, 236 },
    hover = { 255, 244, 192, 255 },
    transparent = { 0, 0, 0, 0 },
    surface = { 255, 253, 245, 248 },
    surfaceSoft = { 231, 246, 238, 255 },
    rail = { 224, 244, 255, 250 },
    yellowSoft = { 255, 244, 192, 255 },
    coralSoft = { 255, 231, 219, 255 },
    skySoft = { 224, 244, 255, 255 },
    shadow = { 52, 78, 91, 48 },
}

local function SaturateUiColor(color, factor)
    local gray = color[1] * 0.299 + color[2] * 0.587 + color[3] * 0.114
    local function channel(value)
        return math.max(0, math.min(255, math.floor(gray + (value - gray) * factor + 0.5)))
    end
    color[1], color[2], color[3] = channel(color[1]), channel(color[2]), channel(color[3])
end

for _, color in pairs(COLORS) do SaturateUiColor(color, 1.20) end

local function ModelMiniatureChildren(item, size, tone)
    local children = {}
    for _, part in ipairs(ModelMiniature.Parts(item, 12)) do
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
        children[1] = UI.Label { text = "◇", fontSize = 15,
            fontWeight = "900", fontColor = tone }
    end
    return children
end

local callbacks_ = nil
local lastState_ = nil
local lastStatus_ = nil
local profile_ = nil
local refreshing_ = false
local referenceVisible_ = false
local referenceOpacity_ = 0.35
local referencePath_ = ""
local mobileMoreOpen_ = false
local mobilePanelTab_ = "properties"
local desktopPanelTab_ = "properties"
local desktopJsonFile_ = "cloud-model.json"
local workbenchName_ = "未命名模型"
local workbenchLicense_ = "private"
local scrollPositions_ = {}
local pendingScrollRestores_ = {}

local function TemplateListHeight(count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count == 0 then return TEMPLATE_EMPTY_HEIGHT end
    return count * TEMPLATE_ROW_HEIGHT + math.max(0, count - 1) * TEMPLATE_ROW_GAP
end

local function TemplateCategoryLayout(width, count)
    width = math.max(1, math.floor(tonumber(width) or 1))
    count = math.max(1, math.floor(tonumber(count) or 1))
    local gap, minimumButtonWidth, rowHeight = 4, 60, 26
    local columns = math.max(1, math.min(count,
        math.floor((width + gap) / (minimumButtonWidth + gap))))
    local buttonWidth = math.max(1, math.floor((width - math.max(0, columns - 1) * gap) / columns))
    local rows = math.ceil(count / columns)
    return buttonWidth, rows * rowHeight + math.max(0, rows - 1) * gap, columns
end

local function TemplateLibraryPolicy(mode)
    local desktop = mode == "desktop" or mode == "tablet"
    -- PC/tablet expands every category into wrapped rows. The category control
    -- is the header of the same vertical virtual list on every device.
    return desktop, true
end

local function VirtualPoolUpperBound(viewportHeight, itemHeight, itemGap, poolBuffer)
    local rowHeight = math.max(1, (tonumber(itemHeight) or 1) + (tonumber(itemGap) or 0))
    return math.ceil(math.max(0, tonumber(viewportHeight) or 0) / rowHeight)
        + math.max(0, math.floor(tonumber(poolBuffer) or 0)) * 2
end

local function TemplateVirtualRows(items)
    local rows = {}
    for _, item in ipairs(items or {}) do rows[#rows + 1] = { item = item } end
    if #rows == 0 then rows[1] = { empty = true } end
    return rows
end

local function TemplateLibraryViewportHeight(totalHeight)
    -- Authored fixed heights: current model card 75, count 12, sources 28;
    -- three 6px gaps separate those controls from the unified category/list
    -- scroller. Categories consume scroll content, not fixed viewport height.
    local fixedHeight = 75 + 12 + 28 + 18
    return math.max(TEMPLATE_ROW_HEIGHT, math.floor((tonumber(totalHeight) or 0) - fixedHeight))
end

local function TemplateVirtualContentHeight(count, rowHeight, headerHeight)
    count = math.max(0, math.floor(tonumber(count) or 0))
    rowHeight = math.max(1, tonumber(rowHeight) or 1)
    headerHeight = math.max(0, tonumber(headerHeight) or 0)
    return headerHeight + count * rowHeight
end

local function TemplateVirtualVisibleRange(count, rowHeight, scrollOffset, viewportHeight, headerHeight)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count == 0 then return 0, 0 end
    rowHeight = math.max(1, tonumber(rowHeight) or 1)
    scrollOffset = math.max(0, tonumber(scrollOffset) or 0)
    viewportHeight = math.max(0, tonumber(viewportHeight) or 0)
    headerHeight = math.max(0, tonumber(headerHeight) or 0)
    local visibleEnd = scrollOffset + viewportHeight - headerHeight
    if visibleEnd <= 0 then return 0, 0 end
    local first = math.floor(math.max(0, scrollOffset - headerHeight) / rowHeight) + 1
    local last = math.ceil(visibleEnd / rowHeight)
    return math.max(1, math.min(count, first)), math.max(1, math.min(count, last))
end

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
    if scroll and (restoreX > 0 or restoreY > 0) then
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
    local restoreX = math.max(0, tonumber(saved.x) or 0)
    local restoreY = math.max(0, tonumber(saved.y) or 0)
    if list.scrollView_ and (restoreX > 0 or restoreY > 0) then
        pendingScrollRestores_[#pendingScrollRestores_ + 1] = {
            scroll = list.scrollView_, x = restoreX, y = restoreY,
        }
    end
    return list
end

local function AttachTemplateVirtualHeader(list, header, headerHeight)
    if not list or not header or not list.contentContainer_ or not list.scrollView_ then return list end
    local inheritedUpdateVisibleItems = list.UpdateVisibleItems
    local inheritedSetData = list.SetData
    list._templateHeader = header

    list.CalculateVisibleRange = function(self)
        local layout = self:GetLayout()
        local viewportHeight = 400
        if layout.h > 0 then
            viewportHeight = layout.h
        elseif type(self.props.height) == "number" then
            viewportHeight = self.props.height
        elseif type(self.props.viewportHeight) == "number" then
            viewportHeight = self.props.viewportHeight
        end
        return TemplateVirtualVisibleRange(#self.props.data, self.rowHeight_,
            self.scrollOffset_, viewportHeight, self._templateHeaderHeight)
    end

    list.UpdateVisibleItems = function(self)
        inheritedUpdateVisibleItems(self)
        local inset = math.max(0, tonumber(self._templateHeaderHeight) or 0)
        for index, widget in pairs(self.pool_.inUse) do
            widget:SetStyle({ top = inset + (index - 1) * self.rowHeight_ })
        end
    end

    list.SetData = function(self, data)
        inheritedSetData(self, data)
        self.contentContainer_:SetStyle({
            height = TemplateVirtualContentHeight(#self.props.data, self.rowHeight_,
                self._templateHeaderHeight),
        })
        self.scrollView_:UpdateContentSize()
    end

    list.ScrollToIndex = function(self, index)
        local y = math.max(0, tonumber(self._templateHeaderHeight) or 0)
            + math.max(0, (tonumber(index) or 1) - 1) * self.rowHeight_
        self.scrollView_:SetScroll(0, y)
    end

    list.SetTemplateHeaderHeight = function(self, value)
        self._templateHeaderHeight = math.max(0, tonumber(value) or 0)
        self._templateHeader:SetStyle({
            position = "absolute", left = 0, top = 0,
            height = self._templateHeaderHeight,
        })
        self.contentContainer_:SetStyle({
            height = TemplateVirtualContentHeight(#self.props.data, self.rowHeight_,
                self._templateHeaderHeight),
        })
        self.visibleRange_ = { first = -1, last = -1 }
        self:UpdateVisibleItems()
        self.scrollView_:UpdateContentSize()
    end

    local virtualList = list
    list.scrollView_.UpdateContentSize = function(scroll)
        local layout = scroll:GetLayout()
        scroll.contentWidth_ = layout.w > 0 and layout.w or 0
        scroll.contentHeight_ = TemplateVirtualContentHeight(
            #virtualList.props.data, virtualList.rowHeight_, virtualList._templateHeaderHeight)
    end
    list.contentContainer_:AddChild(header)
    list:SetTemplateHeaderHeight(headerHeight)
    return list
end

local function CategoryGestureIsHorizontal(dx, dy)
    return math.abs(tonumber(dx) or 0) > math.abs(tonumber(dy) or 0) * 1.08
end

local function EnableCategoryAxisRouting(scroll, verticalScroll)
    if not scroll then return scroll end
    local inheritedOnWheel = scroll.OnWheel
    scroll.OnWheel = function(self, dx, dy)
        local horizontal = tonumber(dx) or 0
        local vertical = tonumber(dy) or 0
        if not CategoryGestureIsHorizontal(horizontal, vertical) and verticalScroll then
            -- Vertical wheel/trackpad input belongs to the unified model list;
            -- horizontal input still reveals the compact phone category strip.
            verticalScroll:OnWheel(0, vertical)
            return
        end
        if inheritedOnWheel then return inheritedOnWheel(self, horizontal, vertical) end
    end
    local inheritedOnPanStart = scroll.OnPanStart
    scroll.OnPanStart = function(self, event)
        if not CategoryGestureIsHorizontal(event.totalDeltaX, event.totalDeltaY) then
            -- Returning false lets the gesture dispatcher bubble to the outer
            -- vertical VirtualList, even when the finger began on a category.
            return false
        end
        return inheritedOnPanStart and inheritedOnPanStart(self, event) or false
    end
    return scroll
end

local modeButtons_ = {}
local presetButtons_ = {}
local newShapeButtons_ = {}
local selectedShapeButtons_ = {}
local colorButtons_ = {}
local newMaterialButtons_ = {}
local selectedMaterialButtons_ = {}
local transformButtons_ = {}
local undoButton_ = nil
local redoButton_ = nil
local statusLabel_ = nil
local selectionBadge_ = nil
local duplicateQuickButton_ = nil
local objectCountLabel_ = nil
local noSelectionLabel_ = nil
local inspectorPanel_ = nil
local objectVirtualList_ = nil
local templateVirtualList_ = nil
local templateCountLabel_ = nil
local templateSourceTabs_ = nil
local templateCategoryTabs_ = nil
local templateCategoriesWrapped_ = false
local templateNameField_ = nil
local templateListScroll_ = nil
local templateLibraryScroll_ = nil
local referenceOverlay_ = nil
local referenceToggleButton_ = nil
local referenceOpacitySlider_ = nil
local snapDropdown_ = nil
local newColorPicker_ = nil
local selectedColorPicker_ = nil
local colorPickOverlay_ = nil
local resetColorPickOverlay_ = nil
local newSizeFields_ = {}
local selectedFields_ = {}
local objectListSignature_ = nil
local objectListContentSignature_ = nil
local objectListSelectedId_ = nil
local templateListSignature_ = nil
local templateListIdentitySignature_ = nil
local templateSource_ = "builtin"
local templateCategory_ = "全部"
local templateLibraryWidth_ = 0
local templateLibraryHeight_ = 0
local workbenchTitleLabel_ = nil
local workbenchNameField_ = nil
local licenseButton_ = nil
local pendingTransformState_ = nil
local transformRefreshElapsed_ = 0
local rootRebuildInProgress_ = false

local function IsTransformRefresh(state)
    return type(state) == "table" and state._builderRefreshKind == "transform"
end

local function TransformRefreshInterval(mode)
    return mode == "mobile" and (1 / 30) or 0
end

local function TakePendingTransformState(timeStep, mode)
    if not pendingTransformState_ then return nil end
    local interval = TransformRefreshInterval(mode)
    transformRefreshElapsed_ = transformRefreshElapsed_ + math.max(0, tonumber(timeStep) or 0)
    if interval > 0 and transformRefreshElapsed_ + 0.000001 < interval then return nil end
    local state = pendingTransformState_
    pendingTransformState_ = nil
    transformRefreshElapsed_ = interval > 0
        and math.max(0, transformRefreshElapsed_ - interval) or 0
    return state
end

local function CompactLicenseLabel(license)
    if license == "allow_fork" then return "许可：可再创作" end
    if license == "use_only" then return "许可：仅整体" end
    return "许可：私有"
end

local function CanonicalPickerHex(hex)
    local value = tostring(hex or ""):lower()
    local r, g, b = value:match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return value end
    local red, green, blue = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    for _, color in ipairs(Catalog.COLORS) do
        local cr = math.floor(color.hex / 0x10000) % 0x100
        local cg = math.floor(color.hex / 0x100) % 0x100
        local cb = color.hex % 0x100
        if math.abs(red - cr) <= 1 and math.abs(green - cg) <= 1 and math.abs(blue - cb) <= 1 then
            return color.css
        end
    end
    return value
end

local function NormalizeTypedHex(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$"):lower()
    if text:sub(1, 1) == "#" then text = text:sub(2) end
    if text:match("^%x%x%x$") then
        text = text:sub(1, 1):rep(2) .. text:sub(2, 2):rep(2) .. text:sub(3, 3):rep(2)
    end
    if not text:match("^%x%x%x%x%x%x$") then return nil end
    return "#" .. text
end

local function HexRGBA(hex)
    local value = CanonicalPickerHex(hex)
    local r, g, b = value:match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return COLORS.line end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), 255 }
end

local function EstimateColorPopupHeight(picker)
    local pickerSize = picker.pickerSize_ or 180
    local sliderHeight = picker.sliderHeight_ or 16
    local sliderGap = picker.sliderGap_ or 12
    local presetSize = picker.presetSize_ or 24
    local presetGap = picker.presetGap_ or 4
    local popupWidth = pickerSize + 32
    local height = 16 + pickerSize + sliderGap + sliderHeight + sliderGap
    if picker.showAlpha_ then height = height + sliderHeight + sliderGap end
    if picker.showPresets_ then
        local perRow = math.max(1, math.floor((popupWidth - 16) / (presetSize + presetGap)))
        local rows = math.ceil(#(picker.presets_ or {}) / perRow)
        height = height + rows * (presetSize + presetGap) + 8
    end
    if picker.showInput_ then
        height = height + (picker.fontSize_ or 12) * 1.25 + (picker.padding_ or 8)
    end
    return height + 12
end

local function ConfigureColorPickerOverlay(picker, colorPickTarget)
    if not picker then return end
    -- ColorPicker's popup uses one widget for both the color well and editable
    -- HEX row. Do not let the generic pointer dispatcher automatically focus
    -- it after the pipette handler has deliberately closed it. The HEX row
    -- still requests focus explicitly through UI.SetFocus below.
    picker.focusable = false
    local height = profile_ and profile_.height or 1000
    -- The stock popup can only open downward. Compact its HSV square, hue
    -- slider and editable HEX row on short screens.
    if height < 300 then
        picker.pickerSize_, picker.sliderHeight_, picker.sliderGap_ = 88, 10, 5
        picker.presetSize_, picker.presetGap_ = 16, 2
        picker.fontSize_, picker.padding_ = 9, 4
    elseif height < 360 then
        picker.pickerSize_, picker.sliderHeight_, picker.sliderGap_ = 108, 12, 6
        picker.presetSize_, picker.presetGap_ = 18, 3
        picker.fontSize_, picker.padding_ = 10, 6
    elseif height < 440 then
        -- 138 keeps both of ColorPicker's preset-column calculations at six,
        -- so all 12 swatches stay inside popupBounds_ and remain hittable.
        picker.pickerSize_, picker.sliderHeight_, picker.sliderGap_ = 138, 12, 7
        picker.presetSize_, picker.presetGap_ = 20, 3
        picker.fontSize_, picker.padding_ = 11, 6
    end

    local inheritedOpen = picker.Open
    picker.Open = function(self)
        -- Dropdown's legacy Close blindly pops the current top overlay. Close
        -- it before ColorPicker pushes itself; the guarded SetOpen below makes
        -- the later blur callback a harmless no-op.
        if snapDropdown_ and snapDropdown_.state and snapDropdown_.state.isOpen then
            snapDropdown_:Close()
        end
        local other = self == newColorPicker_ and selectedColorPicker_ or newColorPicker_
        if other and other ~= self and other.isOpen_ then other:Close() end
        return inheritedOpen(self)
    end

    local function CommitHexDraft(self)
        if not self.hexEditing_ then return end
        local normalized = NormalizeTypedHex(self.hexDraft_)
        self.hexEditing_ = false
        self.hexReplaceAll_ = false
        if normalized then
            self:SetHex(normalized)
            self:NotifyChange()
        else
            self.hexDraft_ = self:GetHex()
        end
    end

    local inheritedClose = picker.Close
    picker.Close = function(self)
        if UI.GetFocus() == self then UI.SetFocus(nil) end
        CommitHexDraft(self)
        return inheritedClose(self)
    end

    -- HTML uses a native <input type="color">: the closed control is one
    -- full-width color well, not a separate HEX field and eyedropper button.
    picker.Render = function(self, nvg)
        local x, y = self:GetAbsolutePosition()
        local w, h = self:GetComputedSize()
        local hitTest = self:GetAbsoluteLayoutForHitTest()
        self.inputBounds_ = { x = hitTest.x, y = hitTest.y, w = hitTest.w, h = hitTest.h }
        local border = self.isOpen_ and COLORS.blue or COLORS.line

        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, 9)
        nvgFillColor(nvg, nvgRGBA(255, 253, 245, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(border[1], border[2], border[3], border[4] or 255))
        nvgStrokeWidth(nvg, self.isOpen_ and 2 or 1)
        nvgStroke(nvg)

        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 3, y + 3, math.max(1, w - 6), math.max(1, h - 6), 7)
        nvgFillColor(nvg, self:GetNvgColor())
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(35, 64, 73, 55))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        if self.isOpen_ then
            local queueFn = self.queueOverlay_ or UI.QueueOverlay
            queueFn(function(overlayNvg) self:RenderPopup(overlayNvg) end)
        end
    end

    -- Recreate the native picker's bottom row: editable HEX on the left and
    -- its eyedropper action inside the popup on the right.
    picker.RenderHexInput = function(self, nvg, x, y, width)
        local rowHeight = self.hexInputHeight_ or math.max(25, self.fontSize_ * 1.5 + self.padding_)
        local eyeWidth, gap = rowHeight, 6
        local fieldWidth = math.max(48, width - eyeWidth - gap)
        self.hexInputBounds_ = { x = x, y = y, w = fieldWidth, h = rowHeight }
        self.eyedropperBounds_ = { x = x + fieldWidth + gap, y = y, w = eyeWidth, h = rowHeight }

        local fieldBorder = self.hexEditing_ and COLORS.blue or COLORS.line
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, fieldWidth, rowHeight, 8)
        nvgFillColor(nvg, nvgRGBA(255, 253, 245, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(fieldBorder[1], fieldBorder[2], fieldBorder[3], fieldBorder[4] or 255))
        nvgStrokeWidth(nvg, self.hexEditing_ and 2 or 1)
        nvgStroke(nvg)

        nvgFontSize(nvg, self.fontSize_)
        nvgFillColor(nvg, nvgRGBA(COLORS.ink[1], COLORS.ink[2], COLORS.ink[3], 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, x + 7, y + rowHeight * 0.5, self.hexEditing_ and self.hexDraft_ or self:GetHex())

        local bx, by = self.eyedropperBounds_.x, self.eyedropperBounds_.y
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bx, by, eyeWidth, rowHeight, 8)
        nvgFillColor(nvg, nvgRGBA(COLORS.surfaceSoft[1], COLORS.surfaceSoft[2], COLORS.surfaceSoft[3], 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(COLORS.line[1], COLORS.line[2], COLORS.line[3], 255))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        -- Compact pipette glyph, matching the semantic position of the HTML
        -- browser picker's eyedropper without depending on an icon font.
        local cx, cy = bx + eyeWidth * 0.5, by + rowHeight * 0.5
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - 6, cy + 6)
        nvgLineTo(nvg, cx + 6, cy - 6)
        nvgMoveTo(nvg, cx + 2, cy - 7)
        nvgLineTo(nvg, cx + 7, cy - 2)
        nvgMoveTo(nvg, cx - 7, cy + 3)
        nvgLineTo(nvg, cx - 3, cy + 7)
        nvgStrokeColor(nvg, nvgRGBA(COLORS.blueDark[1], COLORS.blueDark[2], COLORS.blueDark[3], 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end

    picker.OnFocus = function(self)
        self.hexEditing_ = true
        self.hexDraft_ = self:GetHex()
        self.hexReplaceAll_ = true
        if input then input:SetScreenKeyboardVisible(true) end
    end

    picker.OnBlur = function(self)
        CommitHexDraft(self)
        if input then input:SetScreenKeyboardVisible(false) end
    end

    picker.OnTextInput = function(self, text)
        if not self.hexEditing_ then return end
        local incoming = tostring(text or ""):gsub("[^0-9a-fA-F]", ""):upper()
        if incoming == "" then return end
        if self.hexReplaceAll_ then
            self.hexDraft_ = "#" .. incoming
            self.hexReplaceAll_ = false
        else
            local digits = tostring(self.hexDraft_ or ""):gsub("[^0-9a-fA-F]", "")
            self.hexDraft_ = "#" .. (digits .. incoming):sub(1, 6)
        end
        local normalized = NormalizeTypedHex(self.hexDraft_)
        if normalized then
            self:SetHex(normalized)
            self:NotifyChange()
        end
    end

    picker.OnKeyDown = function(self, key)
        if not self.hexEditing_ then return end
        if key == KEY_BACKSPACE or key == KEY_DELETE then
            local digits = tostring(self.hexDraft_ or ""):gsub("[^0-9a-fA-F]", "")
            self.hexDraft_ = "#" .. digits:sub(1, math.max(0, #digits - 1))
            self.hexReplaceAll_ = false
        elseif key == KEY_RETURN or key == KEY_KP_ENTER then
            CommitHexDraft(self)
            UI.ClearFocus()
        elseif key == KEY_ESCAPE then
            self.hexEditing_ = false
            self.hexDraft_ = self:GetHex()
            UI.ClearFocus()
        end
    end

    local inheritedRenderPopup = picker.RenderPopup
    picker.RenderPopup = function(self, nvg)
        local inheritedLayout = self.GetAbsoluteLayoutForHitTest
        self.GetAbsoluteLayoutForHitTest = function(widget)
            local layout = inheritedLayout(widget)
            local current = profile_
            if not current then return layout end
            local safe = current.safe or { top = 0, right = 0, bottom = 0, left = 0 }
            local popupWidth = (self.pickerSize_ or 180) + 32
            local popupHeight = self.popupBounds_ and self.popupBounds_.h or EstimateColorPopupHeight(self)
            local left = math.max(safe.left + 4, math.min(layout.x, current.width - safe.right - popupWidth - 4))
            local minimumTop = safe.top + 4
            local screenBottom = current.height - safe.bottom - 4
            local maximumTop = math.max(minimumTop, screenBottom - popupHeight)
            local below = layout.y + layout.h + 4
            local above = layout.y - popupHeight - 4
            local popupTop
            if below + popupHeight <= screenBottom then
                popupTop = below
            elseif above >= minimumTop then
                popupTop = above
            else
                -- Only very short screens can fit the popup and field
                -- separately but not wholly on either side. Keep the popup on
                -- screen; the pointer wrapper below gives it hit-test priority
                -- over the small overlap with the trigger field.
                popupTop = math.max(minimumTop, math.min(below, maximumTop))
            end
            return { x = left, y = popupTop - layout.h - 4, w = layout.w, h = layout.h }
        end
        inheritedRenderPopup(self, nvg)
        self.GetAbsoluteLayoutForHitTest = inheritedLayout
    end

    local inheritedPointerDown = picker.OnPointerDown
    picker.OnPointerDown = function(self, event)
        if event and self.isOpen_ and self:PointInBounds(event.x, event.y, self.eyedropperBounds_) then
            self.hexEditing_ = false
            if UI.GetFocus() == self then UI.ClearFocus() end
            self:Close()
            callbacks_.beginColorPick(colorPickTarget)
            return true
        end
        if event and self.isOpen_ and self:PointInBounds(event.x, event.y, self.hexInputBounds_) then
            self.hexDraft_ = self:GetHex()
            self.hexReplaceAll_ = true
            UI.SetFocus(self)
            return true
        end
        local popup = self.popupBounds_
        local inputBounds = self.inputBounds_
        local inPopup = event and self.isOpen_ and popup
            and event.x >= popup.x and event.x <= popup.x + popup.w
            and event.y >= popup.y and event.y <= popup.y + popup.h
        local overlapsInput = inPopup and inputBounds
            and event.x >= inputBounds.x and event.x <= inputBounds.x + inputBounds.w
            and event.y >= inputBounds.y and event.y <= inputBounds.y + inputBounds.h
        if overlapsInput then
            self.inputBounds_ = { x = -100000, y = -100000, w = 0, h = 0 }
            local consumed = inheritedPointerDown(self, event)
            self.inputBounds_ = inputBounds
            return consumed
        end
        return inheritedPointerDown(self, event)
    end
end

local function GuardDropdownOverlay(dropdown)
    if not dropdown then return end
    local inheritedSetOpen = dropdown.SetOpen
    dropdown.SetOpen = function(self, open)
        if not open and not (self.state and self.state.isOpen) then return end
        return inheritedSetOpen(self, open)
    end
end

local function LogicalViewport()
    local scale = math.max(0.01, UI.GetScale())
    return graphics:GetWidth() / scale, graphics:GetHeight() / scale, scale
end

local function CurrentProfile()
    local width, height, scale = LogicalViewport()
    local dpr = math.max(0.01, graphics:GetDPR())
    local cssWidth, cssHeight = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local safe = { top = 0, right = 0, bottom = 0, left = 0 }
    local okSafe, safeValue = pcall(UI.GetSafeAreaInsets)
    if okSafe and type(safeValue) == "table" then
        safe.top = tonumber(safeValue.top) or 0
        safe.right = tonumber(safeValue.right) or 0
        safe.bottom = tonumber(safeValue.bottom) or 0
        safe.left = tonumber(safeValue.left) or 0
    end
    local nativeMenuRight = 0
    local gameSdk = rawget(_G, "sdk")
    if gameSdk and gameSdk.GetNativeExitMenuRect then
        local okMenu, rect = pcall(function() return gameSdk:GetNativeExitMenuRect() end)
        if okMenu and rect then
            nativeMenuRight = math.max(0, width - (tonumber(rect.left) or 1) * width + 10)
        end
    end
    local nativePlatform = GetNativePlatform and GetNativePlatform()
        or GetPlatform and GetPlatform() or ""
    local mode = ResponsiveLayout.Resolve(cssWidth, cssHeight, nativePlatform)
    -- WeChat/TapTap mini-game shells reserve a native capsule in the upper
    -- right even when the SDK cannot report its rectangle yet. Keep editor
    -- actions out of that non-client area on every phone.
    if mode == "mobile" then
        -- Reserve the complete mini-program capsule plus an extra separation
        -- gap. Save/undo/redo must remain comfortably left of the native capsule,
        -- including hosts that do not expose GetNativeExitMenuRect yet.
        nativeMenuRight = math.max(nativeMenuRight, safe.right + 136)
    end
    local top = mode == "mobile" and math.max(56, safe.top + 56) or 50
    local footer = mode == "mobile" and (58 + safe.bottom) or 23
    -- Reserve enough room for real inner padding and complete shortcut labels.
    -- The previous 60px rail left only ~36px for each button after borders.
    local toolWidth = mode == "desktop" and 96 or mode == "tablet" and 90 or 0
    local rightWidth = mode == "desktop" and 320 or mode == "tablet" and 292 or 0
    local viewportLeft = mode == "mobile" and 0 or (safe.left + toolWidth)
    local viewportRight = mode == "mobile" and width or (width - rightWidth)
    return {
        mode = mode,
        width = width,
        height = height,
        scale = scale,
        top = top,
        footer = footer,
        safe = safe,
        nativeMenuRight = nativeMenuRight,
        toolWidth = toolWidth,
        rightWidth = rightWidth,
        viewportLeft = viewportLeft,
        viewportTop = mode == "mobile" and 0 or top,
        viewportRight = viewportRight,
        viewportBottom = mode == "mobile" and height or (height - footer),
    }
end

local function Button(text, onClick, props)
    props = props or {}
    local touch = profile_ and profile_.mode == "mobile"
    return UI.Button {
        text = text,
        width = props.width,
        minWidth = props.minWidth,
        height = props.height or (touch and 36 or 31),
        flexGrow = props.flexGrow,
        flexShrink = props.flexShrink == nil and 0 or props.flexShrink,
        paddingHorizontal = props.paddingHorizontal or 10,
        backgroundColor = props.backgroundColor or (props.danger and COLORS.coralSoft or COLORS.surface),
        hoverBackgroundColor = props.hoverBackgroundColor or (props.danger and { 255, 216, 204, 255 } or COLORS.hover),
        pressedBackgroundColor = props.pressedBackgroundColor or (props.danger and { 250, 199, 187, 255 } or COLORS.skySoft),
        borderColor = props.borderColor or (props.danger and { 236, 151, 133, 255 } or COLORS.line),
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

local function SetActive(button, active)
    if not button then return end
    button:SetStyle({
        backgroundColor = active and COLORS.blue or COLORS.surface,
        hoverBackgroundColor = active and COLORS.blueDark or COLORS.hover,
        pressedBackgroundColor = active and COLORS.blueDark or COLORS.skySoft,
        textColor = active and COLORS.white or COLORS.ink,
        borderColor = active and COLORS.blueDark or COLORS.line,
        borderWidth = active and 2 or 1,
        boxShadow = active and { { x = 0, y = 3, blur = 8, color = { 42, 111, 158, 45 } } } or false,
    })
end

local function SetStyleIfChanged(widget, style)
    if not widget then return end
    widget:SetStyle(style)
end

local function SetTextIfChanged(widget, text)
    if not widget then return end
    local value = tostring(text or "")
    if widget._lastText == value then return end
    widget._lastText = value
    widget:SetText(value)
end

local function SetValueIfChanged(widget, value)
    if not widget then return end
    if widget._lastValue == value then return end
    widget._lastValue = value
    widget:SetValue(value)
end

local function SetVisibleIfChanged(widget, visible)
    if not widget then return end
    if widget._lastVisible == visible then return end
    widget._lastVisible = visible
    widget:SetVisible(visible)
end

local function SetActiveIfChanged(button, active)
    if not button or button._activeState == active then return end
    button._activeState = active
    SetActive(button, active)
end

local function SectionTitle(text)
    return UI.Panel {
        height = 28, flexDirection = "row", alignItems = "center", gap = 8,
        pointerEvents = "none",
        children = {
            UI.Panel { width = 7, height = 7, borderRadius = 4, backgroundColor = COLORS.accent },
            UI.Label { text = text, fontSize = 11, fontWeight = "900", fontColor = COLORS.blueDark },
            UI.Panel { flexGrow = 1, height = 1, backgroundColor = { 174, 205, 211, 130 } },
        },
    }
end

local function Hint(text)
    return UI.Label {
        text = text,
        fontSize = 10,
        lineHeight = 15,
        fontColor = COLORS.muted,
        whiteSpace = "normal",
        wordBreak = "break-word",
        pointerEvents = "none",
    }
end

local function Section(title, children)
    local items = { SectionTitle(title) }
    for _, child in ipairs(children or {}) do items[#items + 1] = child end
    return UI.Panel {
        flexDirection = "column",
        flexShrink = 0,
        gap = 9,
        padding = 12,
        marginBottom = 10,
        backgroundColor = COLORS.surface,
        borderColor = COLORS.line,
        borderWidth = 1,
        borderRadius = 14,
        boxShadow = { { x = 0, y = 3, blur = 9, color = { 54, 78, 88, 18 } } },
        children = items,
    }
end

local function FieldLabel(text, control, props)
    props = props or {}
    return UI.Panel {
        flexDirection = "column",
        gap = 6,
        flexGrow = props.flexGrow,
        flexShrink = props.flexShrink == nil and 0 or props.flexShrink,
        flexBasis = props.flexBasis,
        width = props.width,
        minWidth = 0,
        children = {
            UI.Label { text = text, fontSize = 10, fontColor = COLORS.muted, pointerEvents = "none" },
            control,
        },
    }
end

local function TextField(value, onChange, props)
    props = props or {}
    local touch = profile_ and profile_.mode == "mobile"
    return UI.TextField {
        value = tostring(value or ""),
        width = props.width,
        height = props.height or (touch and 34 or 32),
        minWidth = 0,
        flexGrow = props.flexGrow,
        flexBasis = props.flexBasis,
        fontSize = props.fontSize or (touch and 11 or 10),
        backgroundColor = COLORS.white,
        borderColor = COLORS.line,
        borderWidth = 1,
        borderRadius = 10,
        paddingHorizontal = 9,
        onChange = function(_, text)
            if not refreshing_ and onChange then onChange(text) end
        end,
        onSubmit = function(_, text)
            if not refreshing_ and onChange then onChange(text) end
            if props.onCommit then props.onCommit() end
        end,
        onBlur = function()
            if props.onCommit then props.onCommit() end
        end,
    }
end

local function GridRow(children, gap)
    return UI.Panel {
        flexDirection = "row",
        gap = gap or 8,
        alignItems = "center",
        children = children,
    }
end

local function FixedGrid(items, columns, width, columnGap, rowGap, rowHeight)
    local rows = {}
    local index = 1
    while index <= #items do
        local row = {}
        for _ = 1, columns do
            if index > #items then break end
            row[#row + 1] = items[index]
            index = index + 1
        end
        rows[#rows + 1] = UI.Panel {
            width = width,
            height = rowHeight,
            flexShrink = 0,
            flexDirection = "row",
            alignItems = "center",
            gap = columnGap,
            children = row,
        }
    end
    return UI.Panel {
        width = width,
        height = #rows * rowHeight + math.max(0, #rows - 1) * rowGap,
        flexShrink = 0,
        flexDirection = "column",
        gap = rowGap,
        children = rows,
    }
end

local function BuildPresetButtons(innerWidth)
    local gap = 8
    local width = (innerWidth - gap) * 0.5
    local buttons = {}
    for index, preset in ipairs(Catalog.PRESETS) do
        local button = Button(preset.name, function() callbacks_.setPreset(preset.id) end, { width = width })
        presetButtons_[preset.id] = button
        buttons[#buttons + 1] = button
    end
    local rowHeight = profile_ and profile_.mode == "mobile" and 34 or 31
    return FixedGrid(buttons, 2, innerWidth, gap, gap, rowHeight)
end

local function BuildShapeControls(innerWidth, target)
    local gap, columns = 8, 2
    local width = (innerWidth - gap) / columns
    local buttons = {}
    local destination = target == "selected" and selectedShapeButtons_ or newShapeButtons_
    for _, shape in ipairs(Catalog.SHAPES) do
        local button = Button(shape.name, function()
            if target == "selected" then callbacks_.setSelectedShape(shape.id)
            else callbacks_.setShape(shape.id) end
        end, {
            width = width,
            height = profile_ and profile_.mode == "mobile" and 35 or 32,
            paddingHorizontal = 6,
            fontSize = 10,
            backgroundColor = COLORS.surface,
        })
        destination[shape.id] = button
        buttons[#buttons + 1] = button
    end
    local rowHeight = profile_ and profile_.mode == "mobile" and 35 or 32
    return FixedGrid(buttons, columns, innerWidth, gap, gap, rowHeight)
end

local function BuildNewSizeFields()
    newSizeFields_.x = TextField("1", function(value) callbacks_.setNewSize("x", value) end)
    newSizeFields_.y = TextField("1", function(value) callbacks_.setNewSize("y", value) end)
    newSizeFields_.z = TextField("1", function(value) callbacks_.setNewSize("z", value) end)
    return GridRow({
        FieldLabel("宽 X", newSizeFields_.x, { flexGrow = 1, flexBasis = 0 }),
        FieldLabel("高 Y", newSizeFields_.y, { flexGrow = 1, flexBasis = 0 }),
        FieldLabel("深 Z", newSizeFields_.z, { flexGrow = 1, flexBasis = 0 }),
    }, 8)
end

local function BuildColorControls(innerWidth)
    local columns, gap = 5, 8
    local swatchWidth = (innerWidth - gap * (columns - 1)) / columns
    local swatches = {}
    for _, color in ipairs(Catalog.COLORS) do
        local button = Button("", function() callbacks_.setPaletteColor(color.id) end, {
            width = swatchWidth,
            height = 28,
            paddingHorizontal = 0,
            backgroundColor = color.rgba,
            hoverBackgroundColor = color.rgba,
            pressedBackgroundColor = color.rgba,
            borderColor = { 35, 64, 73, 34 },
            borderWidth = 2,
            borderRadius = 9,
        })
        colorButtons_[color.id] = button
        swatches[#swatches + 1] = button
    end
    newColorPicker_ = UI.ColorPicker {
        color = "#f2e7cf",
        width = innerWidth,
        height = 34,
        size = "sm",
        showAlpha = false,
        showInput = true,
        showPresets = false,
        onChange = function(_, color)
            if not refreshing_ then callbacks_.setNewColor(CanonicalPickerHex(color.hex)) end
        end,
    }
    ConfigureColorPickerOverlay(newColorPicker_, "new")
    return UI.Panel {
        width = innerWidth,
        flexShrink = 0,
        flexDirection = "column",
        gap = 9,
        children = {
            FixedGrid(swatches, columns, innerWidth, gap, gap, 28),
            FieldLabel("自定义颜色", newColorPicker_),
        },
    }
end

local function BuildMaterialControls(innerWidth, target)
    local columns, gap = 2, 8
    local width = (innerWidth - gap) / columns
    local buttons = {}
    local destination = target == "selected" and selectedMaterialButtons_ or newMaterialButtons_
    for _, material in ipairs(Catalog.MATERIALS) do
        local luminance = material.preview[1] * 0.299 + material.preview[2] * 0.587 + material.preview[3] * 0.114
        local button = Button(material.name, function()
            if target == "selected" then callbacks_.setSelectedMaterial(material.id)
            else callbacks_.setNewMaterial(material.id) end
        end, {
            width = width,
            height = profile_ and profile_.mode == "mobile" and 35 or 32,
            paddingHorizontal = 6,
            backgroundColor = material.preview,
            hoverBackgroundColor = material.preview,
            pressedBackgroundColor = material.preview,
            textColor = luminance < 150 and COLORS.white or COLORS.ink,
            borderColor = { 53, 67, 82, 52 },
            borderWidth = 2,
            borderRadius = 9,
        })
        button._materialPreview = material.preview
        button._materialTextColor = luminance < 150 and COLORS.white or COLORS.ink
        destination[material.id] = button
        buttons[#buttons + 1] = button
    end
    local rowHeight = profile_ and profile_.mode == "mobile" and 35 or 32
    return FixedGrid(buttons, columns, innerWidth, gap, gap, rowHeight)
end

local function BuildSnapDropdown(innerWidth)
    local options = {}
    for _, value in ipairs(Catalog.SNAP_STEPS) do
        options[#options + 1] = { value = value, label = Catalog.SNAP_LABELS[value] }
    end
    snapDropdown_ = UI.Dropdown {
        options = options,
        value = 0.25,
        width = innerWidth,
        height = 28,
        maxVisibleItems = 5,
        onChange = function(_, value)
            if not refreshing_ then callbacks_.setSnap(value) end
        end,
    }
    GuardDropdownOverlay(snapDropdown_)
    return snapDropdown_
end

local function BuildSelectedColorControls(innerWidth)
    selectedColorPicker_ = UI.ColorPicker {
        color = "#f2e7cf", width = innerWidth, height = 34, size = "sm", showAlpha = false,
        showInput = true,
        showPresets = false,
        onChange = function(_, color)
            if not refreshing_ then callbacks_.updateInspector("color", color.hex) end
        end,
        onClose = function() callbacks_.finishInspectorEdit() end,
    }
    ConfigureColorPickerOverlay(selectedColorPicker_, "selected")
    return FieldLabel("颜色", selectedColorPicker_)
end

local function BuildInspectorFields(innerWidth)
    local function Live(key)
        return function(value) callbacks_.updateInspector(key, value) end
    end
    local function LiveField(initial, key)
        return TextField(initial, Live(key), { onCommit = callbacks_.finishInspectorEdit })
    end
    selectedFields_.name = TextField("", Live("name"), { width = innerWidth, onCommit = callbacks_.finishInspectorEdit })
    selectedFields_.x = LiveField("0", "x")
    selectedFields_.y = LiveField("0", "y")
    selectedFields_.z = LiveField("0", "z")
    selectedFields_.sx = LiveField("1", "sx")
    selectedFields_.sy = LiveField("1", "sy")
    selectedFields_.sz = LiveField("1", "sz")
    selectedFields_.rotX = LiveField("0", "rotX")
    selectedFields_.rotY = LiveField("0", "rotY")
    selectedFields_.rotZ = LiveField("0", "rotZ")
    inspectorPanel_ = UI.Panel {
        flexDirection = "column", gap = 9,
        children = {
            FieldLabel("名称", selectedFields_.name),
            UI.Panel {
                width = innerWidth, padding = 6, flexDirection = "row", gap = 6,
                backgroundColor = COLORS.surfaceSoft, borderColor = COLORS.line,
                borderWidth = 1, borderRadius = 11,
                children = {
                    Button("复制到旁边", callbacks_.duplicate, {
                        flexGrow = 1, flexShrink = 1, height = 32, paddingHorizontal = 10,
                        backgroundColor = COLORS.surface, borderColor = COLORS.blue,
                    }),
                    Button("删除", callbacks_.deleteSelected, {
                        width = 48, height = 32, paddingHorizontal = 7, danger = true,
                    }),
                },
            },
            FieldLabel("形状", BuildShapeControls(innerWidth, "selected")),
            FieldLabel("材质", BuildMaterialControls(innerWidth, "selected")),
            BuildSelectedColorControls(innerWidth),
            SectionTitle("位置"),
            GridRow({ FieldLabel("X", selectedFields_.x, { flexGrow = 1, flexBasis = 0 }), FieldLabel("Y", selectedFields_.y, { flexGrow = 1, flexBasis = 0 }), FieldLabel("Z", selectedFields_.z, { flexGrow = 1, flexBasis = 0 }) }, 8),
            SectionTitle("旋转角度"),
            GridRow({ FieldLabel("X°", selectedFields_.rotX, { flexGrow = 1, flexBasis = 0 }), FieldLabel("Y°", selectedFields_.rotY, { flexGrow = 1, flexBasis = 0 }), FieldLabel("Z°", selectedFields_.rotZ, { flexGrow = 1, flexBasis = 0 }) }, 8),
            Button("旋转回正 0°", callbacks_.resetRotation, { width = innerWidth, backgroundColor = COLORS.surfaceSoft }),
            SectionTitle("尺寸"),
            GridRow({ FieldLabel("宽", selectedFields_.sx, { flexGrow = 1, flexBasis = 0 }), FieldLabel("高", selectedFields_.sy, { flexGrow = 1, flexBasis = 0 }), FieldLabel("深", selectedFields_.sz, { flexGrow = 1, flexBasis = 0 }) }, 8),
        },
    }
    return inspectorPanel_
end

local function BuildObjectList(innerWidth, listHeight)
    objectCountLabel_ = UI.Label { text = "图层 (0)", fontSize = 11, fontWeight = "bold", fontColor = COLORS.ink }
    local rowHeight = profile_ and profile_.mode == "mobile" and 36 or 32
    local function CreateRow()
        local color = UI.Panel { width = 6, height = rowHeight - 8, borderRadius = 3, backgroundColor = COLORS.line, pointerEvents = "none" }
        local name = UI.Label { text = "图层", flexGrow = 1, flexShrink = 1, maxLines = 1, fontSize = 11, fontColor = COLORS.ink, pointerEvents = "none" }
        local id = UI.Label { text = "#0", flexShrink = 0, fontSize = 9, fontColor = COLORS.muted, pointerEvents = "none" }
        local row = UI.Panel {
            width = "100%", height = rowHeight,
            flexDirection = "row", alignItems = "center", gap = 8,
            paddingHorizontal = 10,
            backgroundColor = COLORS.white,
            borderColor = COLORS.line, borderWidth = 1, borderRadius = 9,
            children = { color, name, id },
        }
        row._color, row._name, row._id = color, name, id
        return row
    end
    objectVirtualList_ = UI.VirtualList {
        width = innerWidth,
        height = listHeight or 180,
        viewportHeight = listHeight or 180,
        data = {},
        itemHeight = rowHeight,
        itemGap = 6,
        poolBuffer = 3,
        showScrollbar = true,
        createItem = CreateRow,
        bindItem = function(widget, data)
            widget._name:SetText(data.name)
            widget._id:SetText(tostring(data.shapeName) .. " · " .. tostring(data.materialName) .. " · #" .. tostring(data.id))
            widget._color:SetStyle({ backgroundColor = data.rgba or COLORS.line })
            widget:SetStyle({
                backgroundColor = data.selected and COLORS.blue or COLORS.surface,
                borderColor = data.selected and COLORS.blueDark or COLORS.line,
                borderWidth = data.selected and 2 or 1,
            })
            widget._name:SetStyle({ fontColor = data.selected and COLORS.white or COLORS.ink })
            widget._id:SetStyle({ fontColor = data.selected and { 225, 242, 248, 255 } or COLORS.muted })
        end,
        onItemClick = function(data) callbacks_.selectById(data.id) end,
    }
    return UI.Panel {
        flexDirection = "column", gap = 8,
        children = {
            objectCountLabel_,
            objectVirtualList_,
        },
    }
end

local function CreateTemplateVirtualRow()
    local partSlots, previewChildren = {}, {}
    for index = 1, 12 do
        local slot = UI.Panel {
            position = "absolute", left = 0, top = 0, width = 1, height = 1,
            backgroundColor = COLORS.line, borderColor = COLORS.line,
            borderWidth = 1, borderRadius = 1, pointerEvents = "none", visible = false,
        }
        partSlots[index] = slot
        previewChildren[#previewChildren + 1] = slot
    end
    local fallback = UI.Label {
        text = "◇", fontSize = 15, fontWeight = "900",
        fontColor = COLORS.blue, pointerEvents = "none", visible = false,
    }
    previewChildren[#previewChildren + 1] = fallback

    local toneBar = UI.Panel {
        width = 4, height = 30, flexShrink = 0,
        backgroundColor = COLORS.blue, borderRadius = 2, pointerEvents = "none",
    }
    local preview = UI.Panel {
        width = 38, height = 38, flexShrink = 0,
        alignItems = "center", justifyContent = "center",
        backgroundFit = "contain", backgroundColor = COLORS.surfaceSoft,
        borderColor = COLORS.line, borderWidth = 1, borderRadius = 8,
        pointerEvents = "none", children = previewChildren,
    }
    local title = UI.Label {
        text = "模型", maxLines = 1, fontSize = 10,
        fontWeight = "900", fontColor = COLORS.ink, pointerEvents = "none",
    }
    local meta = UI.Label {
        text = "模型 · 0 组件", maxLines = 1, fontSize = 8,
        fontColor = COLORS.muted, pointerEvents = "none",
    }
    local actionState = {}
    local insertButton = Button("插入", function()
        if actionState.templateId then callbacks_.insertTemplate(actionState.templateId) end
    end, {
        width = 42, height = 28, paddingHorizontal = 6, fontSize = 9,
        backgroundColor = COLORS.surfaceSoft, borderColor = COLORS.blue,
    })
    local deleteButton = Button("删除", function()
        if actionState.templateId then callbacks_.deleteTemplate(actionState.templateId) end
    end, { width = 40, height = 28, paddingHorizontal = 5, fontSize = 9, danger = true })
    local content = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingHorizontal = 7, paddingVertical = 5,
        children = {
            toneBar,
            preview,
            UI.Panel {
                flexGrow = 1, flexShrink = 1, minWidth = 0,
                flexDirection = "column", justifyContent = "center", gap = 2,
                children = { title, meta },
            },
            UI.Panel {
                flexShrink = 0, flexDirection = "row", alignItems = "center",
                gap = 4, children = { insertButton, deleteButton },
            },
        },
    }
    local empty = UI.Panel {
        width = "100%", height = "100%", paddingHorizontal = 12,
        alignItems = "center", justifyContent = "center", visible = false,
        children = { UI.Label {
            text = "这个分类暂时没有可插入模型。",
            fontSize = 9, fontColor = COLORS.muted, pointerEvents = "none",
        } },
    }
    local row = UI.Panel {
        width = "100%", height = TEMPLATE_ROW_HEIGHT,
        backgroundColor = COLORS.surface, borderColor = COLORS.line,
        borderWidth = 1, borderRadius = 10, overflow = "hidden",
        children = { content, empty },
    }
    row._content, row._empty = content, empty
    row._toneBar, row._preview = toneBar, preview
    row._partSlots, row._fallback = partSlots, fallback
    row._title, row._meta = title, meta
    row._deleteButton = deleteButton
    row._templateActionState = actionState
    return row
end

local function BindTemplateVirtualRow(row, data)
    local item = data and data.item or nil
    if not item then
        row._templateActionState.templateId = nil
        SetVisibleIfChanged(row._content, false)
        SetVisibleIfChanged(row._empty, true)
        local label = row._empty.children and row._empty.children[1]
        if label then
            SetTextIfChanged(label, templateSource_ == "mine" and "还没有自己的模型。"
                or "这个分类暂时没有可插入模型。")
        end
        row:SetStyle({ backgroundColor = COLORS.surfaceSoft, borderColor = COLORS.line })
        return
    end

    row._templateActionState.templateId = item.id
    SetVisibleIfChanged(row._content, true)
    SetVisibleIfChanged(row._empty, false)
    local source = item.source or (item.builtin and "builtin" or "mine")
    local tone = source == "market" and COLORS.accent
        or source == "mine" and COLORS.blue or { 91, 166, 112, 255 }
    local meta = tostring(item.category or "模型") .. " · " .. tostring(item.count or 0) .. " 组件"
    if source == "market" and item.author then meta = tostring(item.author) .. " · " .. meta end
    if item.favorite then meta = "已收藏 · " .. meta end
    SetTextIfChanged(row._title, tostring(item.name or "未命名模型"))
    SetTextIfChanged(row._meta, meta)
    row._title:SetStyle({ fontColor = item.builtin and COLORS.blueDark or COLORS.ink })
    row._toneBar:SetStyle({ backgroundColor = tone })
    row:SetStyle({
        backgroundColor = item.builtin and COLORS.surfaceSoft or COLORS.surface,
        borderColor = COLORS.line,
    })
    SetVisibleIfChanged(row._deleteButton, source == "mine")

    local thumbnail = item.thumbnail or ""
    row._preview:SetStyle({
        backgroundImage = thumbnail,
        backgroundFit = "contain",
        backgroundColor = { tone[1], tone[2], tone[3], 24 },
        borderColor = { tone[1], tone[2], tone[3], 84 },
    })
    local parts = thumbnail == "" and ModelMiniature.Parts(item, 12) or {}
    for index, slot in ipairs(row._partSlots) do
        local part = parts[index]
        SetVisibleIfChanged(slot, part ~= nil)
        if part then
            local width, height = math.max(1.5, part.width * 38), math.max(1.5, part.height * 38)
            slot:SetStyle({
                left = part.x * 38, top = part.y * 38,
                width = width, height = height,
                backgroundColor = part.color,
                borderColor = { 61, 95, 108, 72 }, borderWidth = 1,
                borderRadius = part.round and math.min(width, height) * 0.5 or 1.5,
            })
        end
    end
    row._fallback:SetStyle({ fontColor = tone })
    SetVisibleIfChanged(row._fallback, thumbnail == "" and #parts == 0)
end

local function BuildTemplateLibrary(innerWidth, wrapCategories, libraryHeight)
    templateCategoriesWrapped_ = wrapCategories == true
    templateNameField_ = TextField(workbenchName_, nil, { flexGrow = 1, height = 30, fontSize = 10 })
    templateCountLabel_ = UI.Label {
        text = "内置 0 · 我的 0 · 市场 0", width = innerWidth, height = 12, flexShrink = 0,
        fontSize = 8, fontWeight = "bold", fontColor = COLORS.muted, maxLines = 1,
    }
    templateLibraryWidth_ = innerWidth
    templateLibraryHeight_ = math.max(TEMPLATE_ROW_HEIGHT, tonumber(libraryHeight) or 0)
    templateSourceTabs_ = UI.Panel { width = innerWidth, height = 28, flexDirection = "row", gap = 4 }
    local categories = ModelLibraryPresentation.Categories(lastState_ and lastState_.templates or {}, templateSource_)
    local categoryHeight = 26
    if templateCategoriesWrapped_ then
        local _
        _, categoryHeight = TemplateCategoryLayout(innerWidth, #categories + 1)
    end
    templateCategoryTabs_ = UI.Panel {
        width = innerWidth, height = categoryHeight, flexShrink = 0,
        flexDirection = "row", flexWrap = templateCategoriesWrapped_ and "wrap" or "nowrap", gap = 4,
    }
    local categoryControlHeight = templateCategoriesWrapped_ and categoryHeight or 30
    local listHeight = TemplateLibraryViewportHeight(templateLibraryHeight_)
    templateVirtualList_ = RememberedVirtualList(table.concat({
            "workbench-template-rows", tostring(profile_ and profile_.mode or "desktop"),
            tostring(templateSource_), tostring(templateCategory_),
        }, ":"), {
        width = innerWidth,
        height = listHeight,
        viewportHeight = listHeight,
        data = {},
        itemHeight = TEMPLATE_ROW_HEIGHT,
        itemGap = TEMPLATE_ROW_GAP,
        poolBuffer = TEMPLATE_POOL_BUFFER,
        showScrollbar = true,
        bounces = profile_ and profile_.mode == "mobile",
        createItem = CreateTemplateVirtualRow,
        bindItem = BindTemplateVirtualRow,
    })
    licenseButton_ = Button(CompactLicenseLabel(workbenchLicense_), callbacks_.cycleCurrentLicense,
        { flexGrow = 1.15, flexShrink = 1, height = 28, paddingHorizontal = 5,
            fontSize = 8, backgroundColor = COLORS.surfaceSoft })
    local currentModelPanel = UI.Panel {
        width = innerWidth, height = 75, flexShrink = 0,
        padding = 6, flexDirection = "column", gap = 5,
        backgroundColor = COLORS.surfaceSoft, borderColor = COLORS.line,
        borderWidth = 1, borderRadius = 11,
        children = {
            GridRow({
                UI.Label { text = "当前", width = 28, flexShrink = 0, fontSize = 8,
                    fontWeight = "900", fontColor = COLORS.blueDark, pointerEvents = "none" },
                templateNameField_,
                Button("改名", function() callbacks_.renameCurrentModel(templateNameField_:GetValue()) end,
                    { width = 40, height = 30, paddingHorizontal = 5, fontSize = 9 }),
            }, 5),
            GridRow({
                licenseButton_,
                Button("发布", callbacks_.publishCurrent, {
                    flexGrow = 0.85, flexShrink = 1, height = 28, paddingHorizontal = 6,
                    fontSize = 9, backgroundColor = COLORS.surface, borderColor = COLORS.blue,
                }),
                Button("存副本", function() callbacks_.saveTemplate(templateNameField_:GetValue()) end, {
                    flexGrow = 1, flexShrink = 1, height = 28, paddingHorizontal = 6, fontSize = 9,
                }),
            }, 5),
        },
    }
    local categoryControl = templateCategoryTabs_
    if not templateCategoriesWrapped_ then
        categoryControl = EnableCategoryAxisRouting(RememberedScrollView(
            table.concat({ "workbench-template-categories",
                tostring(profile_ and profile_.mode or "desktop"), tostring(templateSource_) }, ":"), {
            width = innerWidth, height = 30, scrollX = true, scrollY = false,
            showScrollbar = false, padding = 0, children = { templateCategoryTabs_ },
        }), templateVirtualList_.scrollView_)
    end
    AttachTemplateVirtualHeader(templateVirtualList_, categoryControl, categoryControlHeight)
    templateListScroll_ = templateVirtualList_.scrollView_
    templateLibraryScroll_ = templateListScroll_
    return UI.Panel {
        width = innerWidth, height = templateLibraryHeight_, overflow = "hidden",
        flexShrink = 0, flexDirection = "column", gap = 6,
        children = {
            currentModelPanel,
            templateCountLabel_,
            templateSourceTabs_,
            templateVirtualList_,
        },
    }
end

local function BuildViewButtons(compact)
    return GridRow({
        Button(compact and "等轴" or "等轴角度", function() callbacks_.setView("iso") end, { flexGrow = 1, flexShrink = 1 }),
        Button("正面", function() callbacks_.setView("front") end, { flexGrow = 1, flexShrink = 1 }),
        Button("右侧", function() callbacks_.setView("right") end, { flexGrow = 1, flexShrink = 1 }),
        Button("顶部", function() callbacks_.setView("top") end, { flexGrow = 1, flexShrink = 1 }),
    }, 6)
end

local function BuildDesktopToolRail(profile)
    local outerPadding = profile.mode == "tablet" and 10 or 12
    local panelPadding = 10
    local width = profile.toolWidth - outerPadding * 2
    local function RailButton(text, callback)
        return Button(text, callback, {
            width = width - panelPadding * 2,
            height = 37,
            paddingHorizontal = 6,
            fontSize = 10,
            backgroundColor = COLORS.surface,
        })
    end
    modeButtons_.select = RailButton("选择 V", function() callbacks_.setMode("select") end)
    modeButtons_.add = RailButton("放置 B", function() callbacks_.setMode("add") end)
    modeButtons_.delete = RailButton("拆除 X", function() callbacks_.setMode("delete") end)
    local focusButton = RailButton("聚焦 F", callbacks_.focusSelected)
    transformButtons_.translate = RailButton("移动 W", function() callbacks_.setTransformMode("translate") end)
    transformButtons_.rotate = RailButton("旋转 E", function() callbacks_.setTransformMode("rotate") end)
    transformButtons_.scale = RailButton("缩放 R", function() callbacks_.setTransformMode("scale") end)
    return UI.Panel {
        position = "absolute", left = profile.safe.left + outerPadding,
        top = profile.top + 14, bottom = profile.footer + 14,
        width = width,
        alignItems = "center",
        gap = 8,
        paddingLeft = panelPadding,
        paddingRight = panelPadding,
        paddingTop = 12,
        paddingBottom = 12,
        backgroundColor = { 255, 248, 231, 242 },
        borderColor = COLORS.line,
        borderWidth = 2,
        borderRadius = 15,
        boxShadow = { { x = 0, y = 7, blur = 20, color = COLORS.shadow } },
        children = {
            UI.Label { text = "选择与放置", fontSize = 8, fontWeight = "900", fontColor = COLORS.muted },
            modeButtons_.select, modeButtons_.add, modeButtons_.delete, focusButton,
            UI.Divider { orientation = "horizontal", color = COLORS.line, spacing = 2 },
            UI.Label { text = "选中后变换", fontSize = 8, fontWeight = "900", fontColor = COLORS.muted },
            transformButtons_.translate, transformButtons_.rotate, transformButtons_.scale,
        },
    }
end

local function BuildEditorTabs(active, onSelect, height, includeJson)
    local buttons = {}
    local specs = { { "properties", "属性" }, { "build", "新组件" }, { "layers", "图层" }, { "templates", "模型库" } }
    if includeJson then specs[#specs + 1] = { "json", "导入导出" } end
    for _, spec in ipairs(specs) do
        local id, label = spec[1], spec[2]
        local button = Button(label, function() onSelect(id) end, { flexGrow = 1, flexShrink = 1, height = height or 24, paddingHorizontal = 1, fontSize = 9 })
        SetActive(button, active == id)
        buttons[#buttons + 1] = button
    end
    return GridRow(buttons, 7)
end

local function BuildDesktopContextDock(profile)
    local dockWidth = profile.rightWidth - 24
    local innerWidth = dockWidth - 24
    local availableHeight = profile.height - profile.top - profile.footer - 28
    local headerHeight, tabHeight = 84, 46
    local contentHeight = availableHeight - headerHeight - tabHeight
    local content
    if desktopPanelTab_ == "layers" then
        content = UI.Panel { width = "100%", height = contentHeight, padding = 12, children = { BuildObjectList(innerWidth, contentHeight - 40) } }
    elseif desktopPanelTab_ == "json" then
        local fileField = TextField(desktopJsonFile_, function(value)
            desktopJsonFile_ = tostring(value or "")
        end, { width = "100%" })
        content = UI.Panel {
            width = "100%", height = contentHeight, padding = 12,
            flexDirection = "column",
            children = {
                Section("模型 JSON 文件备份", {
                    Hint("浏览器版推荐使用上方“导入模型 JSON / 导出模型 JSON”通过系统剪贴板交换；这里用于项目用户沙箱内的命名备份。"),
                    FieldLabel("文件名", fileField),
                    GridRow({
                        Button("导入 JSON", function()
                            callbacks_.importJsonFile(desktopJsonFile_)
                        end, { flexGrow = 1, height = 34, backgroundColor = COLORS.skySoft, borderColor = COLORS.blue }),
                        Button("导出 JSON", function()
                            callbacks_.exportJsonFile(desktopJsonFile_)
                        end, { flexGrow = 1, height = 34, backgroundColor = COLORS.yellowSoft, borderColor = COLORS.accent }),
                    }, 7),
                    Hint("导入会替换当前工作台内容，并可通过“撤销”恢复。仅接受声明式模型工程 JSON。"),
                }),
                Section("系统剪贴板", {
                    GridRow({
                        Button("导入模型 JSON", callbacks_.importProject,
                            { flexGrow = 1, height = 32, paddingHorizontal = 2 }),
                        Button("导出模型 JSON", callbacks_.exportProject,
                            { flexGrow = 1, height = 32, paddingHorizontal = 2 }),
                    }, 7),
                }),
            },
        }
    elseif desktopPanelTab_ == "templates" then
        -- Keep controls stable and virtualize only the model rows. This avoids
        -- constructing the full built-in catalogue while preserving the PC
        -- wrapped categories and their existing visual hierarchy.
        local wrapCategories = TemplateLibraryPolicy(profile.mode)
        content = UI.Panel {
            width = "100%", height = contentHeight, padding = 12,
            children = { BuildTemplateLibrary(innerWidth, wrapCategories,
                math.max(TEMPLATE_ROW_HEIGHT, contentHeight - 24)) },
        }
    elseif desktopPanelTab_ == "build" then
        content = RememberedScrollView("workbench-desktop:build", {
            width = "100%", height = contentHeight, scrollX = false, scrollY = true,
            showScrollbar = true, scrollbarInteractive = true, padding = 12,
            children = { UI.Panel { width = "100%", flexDirection = "column", children = {
                Section("基础形状", { BuildShapeControls(innerWidth - 24, "new") }),
                Section("积木预设", { BuildPresetButtons(innerWidth - 24) }),
                Section("尺寸与放置", { BuildNewSizeFields(), FieldLabel("仅放置吸附", BuildSnapDropdown(innerWidth - 24)) }),
                Section("新积木材质", { BuildMaterialControls(innerWidth - 24, "new"), Hint("颜色会作为材质色调，修改后立即生效。") }),
                Section("新积木颜色", { BuildColorControls(innerWidth - 24) }),
                Section("观察角度", { BuildViewButtons(true) }),
            }}},
        })
    else
        noSelectionLabel_ = Hint("未选择积木；点击模型中的积木后编辑。")
        content = RememberedScrollView("workbench-desktop:properties", {
            width = "100%", height = contentHeight, scrollX = false, scrollY = true,
            showScrollbar = true, scrollbarInteractive = true, padding = 12,
            children = { Section("实时属性", { noSelectionLabel_, BuildInspectorFields(innerWidth - 24) }) },
        })
    end
    return UI.Panel {
        position = "absolute", right = 12, top = profile.top + 14, bottom = profile.footer + 14,
        width = dockWidth,
        flexDirection = "column",
        backgroundColor = COLORS.panel,
        borderColor = COLORS.line,
        borderWidth = 2,
        borderRadius = 17,
        overflow = "hidden",
        boxShadow = { { x = -5, y = 7, blur = 25, color = COLORS.shadow } },
        children = {
            UI.Panel {
                height = headerHeight,
                flexDirection = "column",
                justifyContent = "center",
                gap = 7,
                paddingHorizontal = 12,
                paddingVertical = 8,
                backgroundColor = COLORS.rail,
                borderBottomColor = COLORS.line,
                borderBottomWidth = 1,
                children = {
                    UI.Panel {
                        width = "100%", height = 24, flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            UI.Panel { width = 23, height = 23, borderRadius = 12, backgroundColor = COLORS.yellowSoft,
                                alignItems = "center", justifyContent = "center",
                                children = { UI.Label { text = "✦", fontSize = 10, fontWeight = "900", fontColor = COLORS.accent } } },
                            UI.Label { text = "模型工作台", fontSize = 11, fontWeight = "900", fontColor = COLORS.ink },
                            UI.Spacer(),
                            UI.Label { text = WORKBENCH_VERSION, fontSize = 9, fontWeight = "bold", fontColor = COLORS.blue },
                        },
                    },
                    GridRow({
                        Button("导入模型 JSON", callbacks_.importProject,
                            { flexGrow = 1, height = 30, paddingHorizontal = 2,
                                backgroundColor = COLORS.skySoft, borderColor = COLORS.blue }),
                        Button("导出模型 JSON", callbacks_.exportProject,
                            { flexGrow = 1, height = 30, paddingHorizontal = 2,
                                backgroundColor = COLORS.yellowSoft, borderColor = COLORS.accent }),
                    }, 7),
                },
            },
            UI.Panel { width = "100%", height = tabHeight, padding = 8, backgroundColor = COLORS.surfaceSoft, borderBottomColor = COLORS.line, borderBottomWidth = 1,
                children = { BuildEditorTabs(desktopPanelTab_, function(id) desktopPanelTab_ = id; BuilderUI.Rebuild() end, 30, profile.mode == "desktop") } },
            content,
        },
    }
end

local function SetMobileMoreOpen(open, tab)
    open = open and true or false
    if tab then mobilePanelTab_ = tab end
    if mobileMoreOpen_ == open then return end
    mobileMoreOpen_ = open
    callbacks_.setMobileGizmoSuppressed(open)
    if open and not tab then mobilePanelTab_ = lastState_ and lastState_.selected and "properties" or "build" end
    BuilderUI.Rebuild()
end

local function ToggleMobileMore() SetMobileMoreOpen(not mobileMoreOpen_) end

local function RunMobileBarAction(action)
    if action then action() end
    if mobileMoreOpen_ then SetMobileMoreOpen(false) end
end

local function BuildMobileBottomBar(profile)
    local buttonHeight = 36
    local function MobileAction(text, callback, props)
        props = props or {}
        return Button(text, function() RunMobileBarAction(callback) end, {
            flexGrow = props.flexGrow or 1,
            flexShrink = 1,
            height = buttonHeight,
            paddingHorizontal = props.paddingHorizontal or 2,
            fontSize = props.fontSize or 9,
            backgroundColor = props.backgroundColor or COLORS.surface,
            borderColor = props.borderColor or COLORS.line,
        })
    end
    local function Group(children, flexGrow, width)
        return UI.Panel {
            width = width,
            flexGrow = flexGrow,
            flexShrink = 1,
            height = 42,
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            paddingHorizontal = 0,
            paddingVertical = 0,
            backgroundColor = COLORS.transparent,
            borderWidth = 0,
            borderRadius = 0,
            boxShadow = false,
            children = children,
        }
    end

    modeButtons_.select = MobileAction("选择", function() callbacks_.setMode("select") end)
    modeButtons_.add = MobileAction("放置", function() callbacks_.setMode("add") end)
    modeButtons_.delete = MobileAction("拆除", function() callbacks_.setMode("delete") end, {
        backgroundColor = COLORS.coralSoft,
        borderColor = { 236, 151, 133, 180 },
    })
    local focusButton = MobileAction("聚焦", callbacks_.focusSelected, { flexGrow = 0.86 })
    transformButtons_.translate = MobileAction("移动", function() callbacks_.setTransformMode("translate") end)
    transformButtons_.rotate = MobileAction("旋转", function() callbacks_.setTransformMode("rotate") end)
    transformButtons_.scale = MobileAction("缩放", function() callbacks_.setTransformMode("scale") end)
    local panelButton = Button("面板", ToggleMobileMore, {
        width = 58,
        height = 48,
        paddingHorizontal = 4,
        fontSize = 10,
        backgroundColor = mobileMoreOpen_ and COLORS.blue or COLORS.surfaceSoft,
        hoverBackgroundColor = mobileMoreOpen_ and COLORS.blueDark or COLORS.hover,
        pressedBackgroundColor = mobileMoreOpen_ and COLORS.blueDark or COLORS.skySoft,
        borderColor = mobileMoreOpen_ and COLORS.blueDark or { 174, 205, 211, 190 },
        borderWidth = mobileMoreOpen_ and 2 or 1,
        textColor = mobileMoreOpen_ and COLORS.white or COLORS.ink,
        borderRadius = 16,
        boxShadow = { { x = 0, y = -3, blur = 14, color = { 52, 78, 91, 34 } } },
    })

    local modeGroup = Group({ modeButtons_.select, modeButtons_.add, modeButtons_.delete, focusButton }, 1.35)
    local transformGroup = Group({ transformButtons_.translate, transformButtons_.rotate, transformButtons_.scale }, 1.0)
    local left = 10 + profile.safe.left
    local right = 10 + profile.safe.right
    local bottom = 8 + profile.safe.bottom
    return UI.Panel {
        position = "absolute",
        left = left,
        right = right,
        bottom = bottom,
        height = 54,
        flexDirection = "row",
        alignItems = "center",
        gap = 7,
        backgroundColor = COLORS.transparent,
        pointerEvents = "box-none",
        children = { modeGroup, transformGroup, panelButton },
    }
end

local function BuildMobileSheet(profile)
    if not mobileMoreOpen_ then return nil end
    local horizontal = 14
    local maximumWidth = math.max(0, profile.width - profile.safe.left - profile.safe.right - horizontal * 2)
    local panelWidth = math.min(420, math.min(maximumWidth, math.max(260, maximumWidth * 0.68)))
    local innerWidth = panelWidth - 24
    local available = profile.height - profile.top - profile.footer - 18
    local panelHeight = math.min(500, math.max(0, available))
    local headerHeight, tabHeight = 46, 46
    local contentHeight = math.max(0, panelHeight - headerHeight - tabHeight)
    local content
    if mobilePanelTab_ == "layers" then
        content = UI.Panel { width = "100%", height = contentHeight, padding = 12, children = { BuildObjectList(innerWidth, math.max(1, contentHeight - 40)) } }
    elseif mobilePanelTab_ == "templates" then
        content = UI.Panel {
            width = "100%", height = contentHeight, padding = 12,
            children = { BuildTemplateLibrary(innerWidth, false,
                math.max(TEMPLATE_ROW_HEIGHT, contentHeight - 24)) },
        }
    elseif mobilePanelTab_ == "build" then
        content = RememberedScrollView("workbench-mobile:build", {
            width = "100%", height = contentHeight, scrollX = false, scrollY = true,
            showScrollbar = true, padding = 12,
            children = { UI.Panel { width = "100%", flexDirection = "column", children = {
                Section("新积木", {
                    FieldLabel("形状", BuildShapeControls(innerWidth - 24, "new")),
                    BuildPresetButtons(innerWidth - 24),
                    BuildNewSizeFields(),
                    FieldLabel("仅放置吸附", BuildSnapDropdown(innerWidth - 24)),
                    FieldLabel("材质", BuildMaterialControls(innerWidth - 24, "new")),
                    BuildColorControls(innerWidth - 24),
                }),
                Section("观察角度", { BuildViewButtons(true) }),
            }}},
        })
    else
        noSelectionLabel_ = Hint("未选择积木；点击模型中的积木后再编辑属性。")
        content = RememberedScrollView("workbench-mobile:properties", {
            width = "100%", height = contentHeight, scrollX = false, scrollY = true,
            showScrollbar = true, padding = 12,
            children = { Section("实时属性", { noSelectionLabel_, BuildInspectorFields(innerWidth - 24) }) },
        })
    end
    return UI.Panel {
        position = "absolute",
        left = profile.safe.left + horizontal,
        bottom = profile.footer + 12,
        width = panelWidth,
        height = panelHeight,
        flexDirection = "column",
        backgroundColor = COLORS.panel,
        borderColor = COLORS.line,
        borderWidth = 2,
        borderRadius = 18,
        overflow = "hidden",
        pointerEvents = "auto",
        boxShadow = { { x = 0, y = 9, blur = 30, color = COLORS.shadow } },
        children = {
            UI.Panel {
                height = headerHeight,
                flexShrink = 0,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                paddingHorizontal = 14,
                backgroundColor = COLORS.rail,
                borderBottomColor = COLORS.line,
                borderBottomWidth = 1,
                children = {
                    UI.Panel { width = 23, height = 23, borderRadius = 12, backgroundColor = COLORS.yellowSoft,
                        alignItems = "center", justifyContent = "center",
                        children = { UI.Label { text = "✦", fontSize = 10, fontWeight = "900", fontColor = COLORS.accent } } },
                    UI.Label { text = "编辑面板", fontSize = 11, fontWeight = "900", fontColor = COLORS.ink },
                    UI.Spacer(),
                    UI.Label { text = WORKBENCH_VERSION, fontSize = 9, fontWeight = "bold", fontColor = COLORS.blue },
                    Button("关闭", function()
                        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
                        SetMobileMoreOpen(false)
                    end, {
                        width = 46, height = 30, paddingHorizontal = 6, fontSize = 9,
                        backgroundColor = COLORS.surface, borderColor = COLORS.blue,
                    }),
                },
            },
            UI.Panel { width = "100%", height = tabHeight, padding = 8, backgroundColor = COLORS.surfaceSoft,
                children = { BuildEditorTabs(mobilePanelTab_, function(id) mobilePanelTab_ = id; BuilderUI.Rebuild() end, 30) } },
            content,
        },
    }
end

local function BuildMobileSheetDismiss(profile)
    local dismiss = UI.Panel {
        position = "absolute",
        left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        backgroundColor = { 35, 69, 91, 42 },
        pointerEvents = "auto",
    }
    dismiss.focusable = false
    dismiss.OnPointerDown = function()
        -- Rebuilding removes this shield before the raw 3D event fires. Keep a
        -- one-event guard so the dismiss tap cannot also select/move a block.
        if callbacks_.consumeScenePointer then callbacks_.consumeScenePointer() end
        SetMobileMoreOpen(false)
    end
    return dismiss
end

local function BuildViewOverlay(profile)
    local width = profile.viewportRight - profile.viewportLeft
    local height = profile.viewportBottom - profile.viewportTop
    local referenceWidth = math.min(width * 0.70, 615)
    local referenceHeight = height * 0.86
    referenceOverlay_ = UI.Panel {
        width = referenceWidth,
        height = referenceHeight,
        backgroundImage = referencePath_,
        backgroundFit = "contain",
        opacity = referenceVisible_ and referenceOpacity_ or 0,
        pointerEvents = "none",
    }

    local duplicateWidth = profile.mode == "mobile" and 72 or 96
    selectionBadge_ = UI.Label {
        text = "未选择积木 · 单指/左键旋转 · 双指/右键平移",
        minHeight = 27,
        maxWidth = math.max(100, width - duplicateWidth - 54),
        paddingHorizontal = 12,
        paddingVertical = 7,
        backgroundColor = COLORS.white90,
        borderColor = COLORS.line,
        borderWidth = 2,
        borderRadius = 12,
        fontSize = 10,
        fontWeight = "bold",
        fontColor = COLORS.ink,
        boxShadow = { { x = 0, y = 4, blur = 12, color = COLORS.shadow } },
        pointerEvents = "none",
    }
    duplicateQuickButton_ = Button(profile.mode == "mobile" and "复制" or "复制到旁边", callbacks_.duplicate, {
        width = duplicateWidth,
        height = 32,
        paddingHorizontal = profile.mode == "mobile" and 8 or 10,
        backgroundColor = COLORS.surfaceSoft,
        borderColor = COLORS.blue,
        boxShadow = { { x = 0, y = 4, blur = 12, color = COLORS.shadow } },
    })
    duplicateQuickButton_:SetVisible(false)

    local selectionHud = UI.Panel {
        position = "absolute",
        left = 16 + (profile.safe and profile.safe.left or 0),
        top = profile.mode == "mobile" and profile.top + 12 or 16,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        pointerEvents = "box-none",
        children = { selectionBadge_, duplicateQuickButton_ },
    }

    return UI.Panel {
        position = "absolute",
        left = profile.viewportLeft,
        top = profile.viewportTop,
        width = width,
        height = height,
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "box-none",
        children = { referenceOverlay_, selectionHud },
    }
end

local function BuildColorPickOverlay(profile)
    local overlay = UI.Panel {
        position = "absolute",
        left = 0,
        top = 0,
        width = profile.width,
        height = profile.height,
        visible = false,
        backgroundColor = COLORS.transparent,
        pointerEvents = "auto",
    }
    overlay.focusable = false

    local preview = nil
    local pointerX, pointerY = nil, nil
    local pointerType = "mouse"
    local touchPending = false

    resetColorPickOverlay_ = function()
        preview = nil
        pointerX, pointerY = nil, nil
        pointerType = "mouse"
        touchPending = false
    end

    local function InScreen(x, y)
        return x >= 0 and x < profile.width and y >= 0 and y < profile.height
    end

    local function UpdatePreview(event)
        if not event or not InScreen(event.x, event.y) then
            preview = nil
            pointerX, pointerY = nil, nil
            return false
        end
        pointerX, pointerY = event.x, event.y
        pointerType = event.pointerType or "mouse"
        preview = callbacks_.previewColorPick(
            event.x * profile.scale,
            event.y * profile.scale,
            8
        )
        return preview ~= nil
    end

    overlay.props.onPointerMove = function(event, widget)
        UpdatePreview(event)
    end

    overlay.props.onPointerDown = function(event, widget)
        if not event then return end
        UpdatePreview(event)
        if event.pointerType == "touch" then
            touchPending = true
        elseif event.button == nil or event.button == MOUSEB_LEFT then
            callbacks_.pickSceneColor(
                event.x * profile.scale,
                event.y * profile.scale,
                preview and preview.hex or nil
            )
        elseif event.button == MOUSEB_RIGHT then
            callbacks_.cancelColorPick()
        end
    end

    overlay.props.onPointerUp = function(event, widget)
        if touchPending and event then
            touchPending = false
            if InScreen(event.x, event.y) then
                UpdatePreview(event)
                callbacks_.pickSceneColor(
                    event.x * profile.scale,
                    event.y * profile.scale,
                    preview and preview.hex or nil
                )
            else
                callbacks_.cancelColorPick()
            end
        end
    end

    overlay.props.onPointerCancel = function(event, widget)
        touchPending = false
    end

    overlay.props.onClick = function(widget, event)
    end

    overlay.Render = function(self, nvg)
        if not preview or not pointerX or not pointerY then return end
        local gridSize = tonumber(preview.size) or 11
        local pixels = preview.pixels or {}
        if #pixels < gridSize * gridSize then return end

        local radius = profile.mode == "mobile" and 53 or 47
        local diameter = radius * 2
        local lensX = pointerX
        local lensY = pointerY
        if pointerType == "touch" then lensY = lensY - radius - 24 end
        lensX = math.max(radius + 6, math.min(profile.width - radius - 6, lensX))
        lensY = math.max(radius + 6, math.min(profile.height - radius - 6, lensY))

        -- Native HTML eyedropper-style circular loupe with a crisp outer ring.
        nvgBeginPath(nvg)
        nvgCircle(nvg, lensX + 2, lensY + 3, radius + 5)
        nvgFillColor(nvg, nvgRGBA(10, 28, 36, 85))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, lensX, lensY, radius + 3)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgFill(nvg)

        local innerRadius = radius - 2
        local innerDiameter = innerRadius * 2
        local cell = innerDiameter / gridSize
        local startX, startY = lensX - innerRadius, lensY - innerRadius
        local centerIndex = math.floor(gridSize * 0.5)
        local centerColor = pixels[centerIndex * gridSize + centerIndex + 1]
        -- Fill the entire optical area with the exact centre pixel first. The
        -- sampled grid then paints the neighbouring pixels over it, so no white
        -- or transparent holes can appear inside the loupe near its round edge.
        nvgBeginPath(nvg)
        nvgCircle(nvg, lensX, lensY, innerRadius)
        nvgFillColor(nvg, nvgRGBA(centerColor[1], centerColor[2], centerColor[3], centerColor[4] or 255))
        nvgFill(nvg)

        local index = 1
        for row = 0, gridSize - 1 do
            for column = 0, gridSize - 1 do
                local cellX, cellY = startX + column * cell, startY + row * cell
                local centerX, centerY = cellX + cell * 0.5, cellY + cell * 0.5
                local dx, dy = centerX - lensX, centerY - lensY
                -- Only paint cells whose farthest corner remains inside the
                -- optical circle. The anti-aliased circular base fills the
                -- small edge band, so square pixels can never nick the rim.
                local farX = math.abs(dx) + cell * 0.52
                local farY = math.abs(dy) + cell * 0.52
                if farX * farX + farY * farY <= innerRadius * innerRadius then
                    local color = pixels[index]
                    nvgBeginPath(nvg)
                    nvgRect(nvg, cellX - 0.35, cellY - 0.35, cell + 0.7, cell + 0.7)
                    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
                    nvgFill(nvg)
                end
                index = index + 1
            end
        end

        -- The outlined centre pixel is the value committed on click/release.
        local targetX = startX + centerIndex * cell
        local targetY = startY + centerIndex * cell
        nvgBeginPath(nvg)
        nvgRect(nvg, targetX - 1.5, targetY - 1.5, cell + 3, cell + 3)
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgStrokeWidth(nvg, 3)
        nvgStroke(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, targetX - 0.5, targetY - 0.5, cell + 1, cell + 1)
        nvgStrokeColor(nvg, nvgRGBA(18, 38, 46, 255))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        nvgBeginPath(nvg)
        nvgCircle(nvg, lensX, lensY, radius + 3)
        nvgStrokeColor(nvg, nvgRGBA(28, 55, 66, 230))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end

    colorPickOverlay_ = overlay
    return overlay
end

local function BuildTopBarDesktop(profile)
    undoButton_ = Button("撤销", callbacks_.undo, { width = 46 })
    redoButton_ = Button("重做", callbacks_.redo, { width = 46 })
    workbenchTitleLabel_ = UI.Label { text = "模型工作台 · " .. WORKBENCH_VERSION, fontSize = 11, fontWeight = "900", fontColor = COLORS.ink, maxLines = 1 }
    workbenchNameField_ = TextField(workbenchName_, nil, { width = profile.mode == "tablet" and 118 or 172, onCommit = function()
        callbacks_.renameCurrentModel(workbenchNameField_:GetValue())
    end })
    local children = {
        Button("← 空岛", callbacks_.backToIsland, { width = 58, backgroundColor = COLORS.surfaceSoft, borderColor = COLORS.blue }),
        UI.Panel {
            width = profile.mode == "tablet" and 205 or 270, flexShrink = 0,
            flexDirection = "row", alignItems = "center", gap = 7,
            children = {
                UI.Panel { width = 30, height = 30, flexShrink = 0, borderRadius = 15,
                    backgroundColor = COLORS.yellowSoft, borderColor = COLORS.accent, borderWidth = 2,
                    alignItems = "center", justifyContent = "center",
                    children = { UI.Label { text = "模", fontSize = 11, fontWeight = "900", fontColor = COLORS.blueDark } } },
                UI.Panel { flexGrow = 1, flexShrink = 1, gap = 4, children = {
                    workbenchTitleLabel_,
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        workbenchNameField_,
                        Button("改名", function() callbacks_.renameCurrentModel(workbenchNameField_:GetValue()) end,
                            { width = 42, height = 32, paddingHorizontal = 2, fontSize = 9, backgroundColor = COLORS.surfaceSoft }),
                    } },
                } },
            },
        },
        Button("新建", callbacks_.newProject, { width = 40 }),
        Button("保存", callbacks_.save, { width = 40, backgroundColor = COLORS.surfaceSoft, borderColor = { 93, 159, 178, 170 } }),
        undoButton_, redoButton_,
        UI.Spacer(),
        Button("等轴", function() callbacks_.setView("iso") end, { width = 40 }),
        Button("正面", function() callbacks_.setView("front") end, { width = 40 }),
        Button("右侧", function() callbacks_.setView("right") end, { width = 40 }),
        Button("顶部", function() callbacks_.setView("top") end, { width = 40 }),
    }
    if profile.mode == "desktop" then
        table.insert(children, 4, Button("范例", callbacks_.loadExample, { width = 40 }))
    end
    return UI.Panel {
        position = "absolute", left = 0, top = 0, right = 0, height = profile.top,
        flexDirection = "row", alignItems = "center", gap = 10,
        paddingHorizontal = 20, paddingVertical = 8,
        backgroundColor = { 255, 248, 231, 244 },
        backdropBlur = 16,
        borderBottomColor = COLORS.line, borderBottomWidth = 2,
        boxShadow = { { x = 0, y = 5, blur = 16, color = { 48, 76, 88, 30 } } },
        children = children,
    }
end

local function BuildTopBarMobile(profile)
    local compact = profile.width < 360
    undoButton_ = Button(compact and "撤" or "撤销", function() RunMobileBarAction(callbacks_.undo) end,
        { width = compact and 32 or 42, height = 36, paddingHorizontal = 1, fontSize = 9 })
    redoButton_ = Button(compact and "重" or "重做", function() RunMobileBarAction(callbacks_.redo) end,
        { width = compact and 32 or 42, height = 36, paddingHorizontal = 1, fontSize = 9 })
    workbenchTitleLabel_ = UI.Label { text = "模型 · " .. workbenchName_, flexGrow = 1, flexShrink = 1,
        fontSize = 10, fontWeight = "900", fontColor = COLORS.ink, maxLines = 1, pointerEvents = "none" }
    local children = {
        Button(compact and "回岛" or "回空岛", function() RunMobileBarAction(callbacks_.backToIsland) end,
            { width = compact and 40 or 52, height = 36, paddingHorizontal = 3, fontSize = 9, backgroundColor = COLORS.surfaceSoft }),
    }
    if not compact then children[#children + 1] = workbenchTitleLabel_ end
    children[#children + 1] = Button("改名", function()
        SetMobileMoreOpen(true, "templates")
    end, { width = compact and 38 or 42, height = 36, paddingHorizontal = 2, fontSize = 9, backgroundColor = COLORS.surfaceSoft })
    children[#children + 1] = Button(compact and "存" or "保存", function() RunMobileBarAction(callbacks_.save) end, { width = compact and 36 or 42, height = 36, paddingHorizontal = 2, fontSize = 9, backgroundColor = COLORS.surfaceSoft })
    children[#children + 1] = undoButton_
    children[#children + 1] = redoButton_
    return UI.Panel {
        position = "absolute", left = 0, top = 0, right = 0, height = profile.top,
        flexDirection = "row", alignItems = "center", gap = compact and 5 or 8,
        paddingLeft = 26 + profile.safe.left,
        paddingRight = 12 + math.max(profile.safe.right, profile.nativeMenuRight),
        paddingTop = 7 + profile.safe.top,
        paddingBottom = 6,
        backgroundColor = COLORS.transparent,
        borderBottomWidth = 0,
        boxShadow = false,
        pointerEvents = "box-none",
        children = children,
    }
end

local function BuildFooter(profile)
    statusLabel_ = UI.Label {
        text = lastStatus_ or "正在初始化工作台……",
        fontSize = 9,
        fontWeight = "bold",
        fontColor = COLORS.ink,
        flexShrink = 1,
        maxLines = 1,
    }
    local children = { statusLabel_ }
    if profile.mode ~= "mobile" then
        children[#children + 1] = UI.Label {
            text = "右键/Shift+拖动平移 · F 聚焦 · V/B/X 选择/添加/删除模式 · W/E/R 移动/旋转/缩放 · Del 删除 · Ctrl+D 复制 · Ctrl+S 保存 · Ctrl+Z/Y 撤销重做 · Esc 取消",
            fontSize = 9,
            fontColor = COLORS.muted,
            flexShrink = 1,
            maxLines = 1,
            pointerEvents = "none",
        }
    end
    children[#children + 1] = UI.Label {
        text = "模型工作台 " .. WORKBENCH_VERSION,
        fontSize = 9,
        fontWeight = "900",
        fontColor = COLORS.blue,
        flexShrink = 0,
        maxLines = 1,
        pointerEvents = "none",
    }
    return UI.Panel {
        position = "absolute", left = 0, right = 0, bottom = 0, height = profile.footer,
        flexDirection = "row", alignItems = "center", gap = 14,
        paddingLeft = 18 + (profile.safe and profile.safe.left or 0),
        paddingRight = 18 + (profile.safe and profile.safe.right or 0),
        paddingBottom = profile.safe and profile.safe.bottom or 0,
        backgroundColor = { 255, 248, 231, 246 },
        borderTopColor = COLORS.line, borderTopWidth = 1,
        children = children,
    }
end

local function BuildRoot(profile)
    ---@type table
    local children = { BuildViewOverlay(profile) }
    if profile.mode == "desktop" or profile.mode == "tablet" then
        children[#children + 1] = BuildDesktopToolRail(profile)
        children[#children + 1] = BuildDesktopContextDock(profile)
        children[#children + 1] = BuildTopBarDesktop(profile)
        children[#children + 1] = BuildFooter(profile)
    else
        local sheet = BuildMobileSheet(profile)
        if sheet then
            children[#children + 1] = BuildMobileSheetDismiss(profile)
            children[#children + 1] = sheet
        end
        children[#children + 1] = BuildTopBarMobile(profile)
        children[#children + 1] = BuildMobileBottomBar(profile)
    end
    -- Last child on purpose: while eyedropper is active this transparent
    -- shield owns every pointer, freezing all editor panels and scene tools.
    children[#children + 1] = BuildColorPickOverlay(profile)
    return UI.Panel {
        width = "100%", height = "100%",
        -- UI is rendered after the 3D viewport. Keep the full-screen root
        -- transparent so the center scene remains visible; panels paint only
        -- their own editor chrome.
        backgroundColor = COLORS.transparent,
        pointerEvents = "box-none",
        children = children,
    }
end

function BuilderUI.Init(callbacks)
    callbacks_ = callbacks
    lastState_, lastStatus_ = nil, nil
    mobileMoreOpen_, mobilePanelTab_, desktopPanelTab_ = false, "properties", "properties"
    scrollPositions_, pendingScrollRestores_ = {}, {}
    pendingTransformState_, transformRefreshElapsed_, rootRebuildInProgress_ = nil, 0, false
    UI.Init(UIRuntimeConfig.Options(UI.Scale.DEFAULT))
    BuilderUI.Rebuild()
end

function BuilderUI.SetContext(context)
    if type(context) == "table" then
        workbenchName_ = tostring(context.name or "未命名模型")
        workbenchLicense_ = tostring(context.license or "private")
    else
        workbenchName_ = tostring(context or "未命名模型")
    end
    if workbenchTitleLabel_ and profile_ and profile_.mode == "mobile" then
        SetTextIfChanged(workbenchTitleLabel_, "模型 · " .. workbenchName_)
    end
    if workbenchNameField_ and workbenchNameField_:GetValue() ~= workbenchName_ then
        SetValueIfChanged(workbenchNameField_, workbenchName_)
    end
    if templateNameField_ and templateNameField_:GetValue() ~= workbenchName_ then
        SetValueIfChanged(templateNameField_, workbenchName_)
    end
    if licenseButton_ then SetTextIfChanged(licenseButton_, CompactLicenseLabel(workbenchLicense_)) end
end

function BuilderUI.Rebuild()
    -- A rebuilt tree must not leave a destroyed TextField as the active focus.
    if newColorPicker_ then newColorPicker_:Close() end
    if selectedColorPicker_ then selectedColorPicker_:Close() end
    if snapDropdown_ and snapDropdown_.Close then snapDropdown_:Close() end
    UI.ClearFocus()
    -- A DPR-only change does not make UI.Update recalculate its scale because
    -- the physical width/height stayed unchanged. Refresh it before deriving
    -- the responsive profile and framebuffer viewport rectangle.
    UI.SetScale(UI.Scale.DEFAULT)
    profile_ = CurrentProfile()
    pendingScrollRestores_ = {}
    modeButtons_, presetButtons_, colorButtons_, transformButtons_ = {}, {}, {}, {}
    newShapeButtons_, selectedShapeButtons_ = {}, {}
    newMaterialButtons_, selectedMaterialButtons_ = {}, {}
    newSizeFields_, selectedFields_ = {}, {}
    undoButton_, redoButton_, statusLabel_, selectionBadge_, duplicateQuickButton_ = nil, nil, nil, nil, nil
    objectCountLabel_, noSelectionLabel_, inspectorPanel_, objectVirtualList_ = nil, nil, nil, nil
    templateVirtualList_, templateCountLabel_, templateSourceTabs_, templateCategoryTabs_, templateNameField_ = nil, nil, nil, nil, nil
    templateCategoriesWrapped_ = false
    templateListScroll_, templateLibraryScroll_ = nil, nil
    templateLibraryHeight_ = 0
    workbenchTitleLabel_, workbenchNameField_ = nil, nil
    licenseButton_ = nil
    referenceOverlay_, referenceToggleButton_, referenceOpacitySlider_, snapDropdown_ = nil, nil, nil, nil
    newColorPicker_, selectedColorPicker_ = nil, nil
    colorPickOverlay_ = nil
    resetColorPickOverlay_ = nil
    objectListSignature_ = nil
    objectListContentSignature_ = nil
    objectListSelectedId_ = nil
    templateListSignature_ = nil
    templateListIdentitySignature_ = nil

    rootRebuildInProgress_ = true
    UI.SetRoot(UI.SafeAreaView {
        width = "100%", height = "100%", edges = "none", nativeMenuInset = false,
        -- The safe-area shell spans the whole screen. It must only route events
        -- to its interactive children; otherwise it swallows every mouse/touch
        -- event before the 3D viewport can start an orbit or transform drag.
        pointerEvents = "box-none",
        children = { BuildRoot(profile_) },
    }, true)

    -- Populate dynamic model/category rows before measuring ScrollViews.
    -- Restoring against the header-only tree would clamp a valid saved offset
    -- to zero, then the cards would be appended after the position was lost.
    if lastState_ then BuilderUI.Refresh(lastState_, nil) end
    BuilderUI.RefreshReference()
    UI.Layout()
    local updatedScrolls = {}
    local function UpdateScrollContent(scroll)
        if not scroll or updatedScrolls[scroll] or not scroll.UpdateContentSize then return end
        scroll:UpdateContentSize()
        updatedScrolls[scroll] = true
    end
    UpdateScrollContent(templateListScroll_)
    UpdateScrollContent(templateLibraryScroll_)
    for _, restore in ipairs(pendingScrollRestores_) do
        local scroll = restore.scroll
        if scroll and scroll.UpdateContentSize and scroll.SetScroll then
            UpdateScrollContent(scroll)
            local bounces = scroll.props.bounces
            scroll.props.bounces = false
            scroll:SetScroll(restore.x, restore.y)
            scroll.props.bounces = bounces
        end
    end
    pendingScrollRestores_ = {}
    rootRebuildInProgress_ = false

    callbacks_.setViewportRect(
        profile_.viewportLeft * profile_.scale,
        profile_.viewportTop * profile_.scale,
        profile_.viewportRight * profile_.scale,
        profile_.viewportBottom * profile_.scale,
        profile_.scale,
        profile_.mode
    )
end

function BuilderUI.RefreshReference()
    if referenceOverlay_ then
        SetStyleIfChanged(referenceOverlay_, {
            backgroundImage = referencePath_,
            backgroundFit = "contain",
            opacity = referenceVisible_ and referenceOpacity_ or 0,
        })
    end
    if referenceToggleButton_ then
        SetTextIfChanged(referenceToggleButton_, referencePath_ == "" and "选择参考图"
            or referenceVisible_ and "隐藏参考" or "显示参考")
        SetActiveIfChanged(referenceToggleButton_, referenceVisible_)
    end
    if referenceOpacitySlider_ and math.abs(referenceOpacitySlider_:GetValue() - referenceOpacity_) > 0.001 then
        SetValueIfChanged(referenceOpacitySlider_, referenceOpacity_)
    end
end

function BuilderUI.SetReferencePath(path)
    if path and path ~= "" then
        referencePath_ = path
        referenceVisible_ = true
        BuilderUI.RefreshReference()
    end
end

local function UpdateObjectList(state)
    if not objectVirtualList_ then return end
    local selectedId = state.selected and state.selected.id or nil
    local identityParts, contentParts = {}, { tostring(selectedId or 0) }
    local data = {}
    for index, item in ipairs(state.objects or {}) do
        identityParts[#identityParts + 1] = tostring(item.id)
        local material = Catalog.FindMaterial(item.materialId)
        local shape = Catalog.FindShape(item.shapeId)
        contentParts[#contentParts + 1] = tostring(item.name) .. ":" .. tostring(item.color) .. ":" .. material.id .. ":" .. shape.id
        data[index] = {
            id = item.id,
            name = item.name,
            rgba = HexRGBA(item.color),
            materialName = material.name,
            shapeName = shape.name,
            selected = selectedId == item.id,
        }
    end
    local identitySignature = table.concat(identityParts, "|")
    local contentSignature = table.concat(contentParts, "|")
    if identitySignature ~= objectListSignature_ then
        objectListSignature_ = identitySignature
        objectListContentSignature_ = contentSignature
        objectVirtualList_:SetData(data)
    elseif contentSignature ~= objectListContentSignature_ or selectedId ~= objectListSelectedId_ then
        objectListContentSignature_ = contentSignature
        objectVirtualList_.props.data = data
        objectVirtualList_:Refresh()
    end
    if selectedId and selectedId ~= objectListSelectedId_ then
        for index, item in ipairs(data) do
            if item.id == selectedId then objectVirtualList_:ScrollToIndex(index); break end
        end
    end
    objectListSelectedId_ = selectedId
end

local function UpdateTemplateList(state)
    if not templateVirtualList_ then return end
    local parts = {}
    for _, item in ipairs(state.templates or {}) do
        parts[#parts + 1] = table.concat({
            tostring(item.id), tostring(item.name), tostring(item.count),
            tostring(item.source), tostring(item.category), tostring(item.description), tostring(item.author),
            tostring(item.favorite), tostring(item.versionId),
        }, ":")
    end
    local signature = table.concat(parts, "|") .. "#" .. tostring(templateSource_) .. "#" .. tostring(templateCategory_)
    if signature ~= templateListSignature_ then
        templateListSignature_ = signature

        if templateSourceTabs_ then
            templateSourceTabs_:ClearChildren()
            for _, sourceSpec in ipairs({
                { "builtin", "内置" }, { "mine", "我的" }, { "market", "市场" }, { "favorites", "收藏" },
            }) do
                local sourceId, sourceLabel = sourceSpec[1], sourceSpec[2]
                local button = Button(sourceLabel, function()
                    templateSource_, templateCategory_ = sourceId, "全部"
                    BuilderUI.Rebuild()
                end, { flexGrow = 1, flexShrink = 1, height = 28, paddingHorizontal = 5, fontSize = 9 })
                SetActive(button, templateSource_ == sourceId)
                templateSourceTabs_:AddChild(button)
            end
        end

        local categories = ModelLibraryPresentation.Categories(state.templates or {}, templateSource_)
        local validCategory = templateCategory_ == "全部"
        for _, category in ipairs(categories) do
            if category == templateCategory_ then validCategory = true end
        end
        if not validCategory then templateCategory_ = "全部" end
        if templateCategoryTabs_ then
            templateCategoryTabs_:ClearChildren()
            local tabs, gap = { "全部" }, 4
            for _, category in ipairs(categories) do tabs[#tabs + 1] = category end
            local wrappedCategories = templateCategoriesWrapped_
            local buttonWidth, categoryHeight = nil, 26
            if wrappedCategories then
                buttonWidth, categoryHeight = TemplateCategoryLayout(templateLibraryWidth_, #tabs)
                templateCategoryTabs_:SetStyle({
                    width = templateLibraryWidth_, height = categoryHeight,
                    flexWrap = "wrap", flexShrink = 0,
                })
            else
                buttonWidth = math.max(56, math.min(72, math.max(1, templateLibraryWidth_) * 0.3))
                templateCategoryTabs_:SetStyle({
                    width = #tabs * buttonWidth + math.max(0, #tabs - 1) * gap,
                    height = 26, flexWrap = "nowrap",
                })
            end
            for _, categoryName in ipairs(tabs) do
                local category = categoryName
                local button = Button(category, function()
                    templateCategory_ = category
                    BuilderUI.Rebuild()
                end, { width = buttonWidth, height = 26, paddingHorizontal = 5, fontSize = 8 })
                SetActive(button, templateCategory_ == category)
                templateCategoryTabs_:AddChild(button)
            end

            local categoryControlHeight = wrappedCategories and categoryHeight or 30
            local listHeight = TemplateLibraryViewportHeight(templateLibraryHeight_)
            templateVirtualList_.props.viewportHeight = listHeight
            templateVirtualList_:SetStyle({ height = listHeight })
            if templateVirtualList_.SetTemplateHeaderHeight then
                templateVirtualList_:SetTemplateHeaderHeight(categoryControlHeight)
            end
        end

        local filtered = ModelLibraryPresentation.Filter(state.templates or {}, templateSource_, templateCategory_)
        local rows = TemplateVirtualRows(filtered)
        local identity = {}
        for _, row in ipairs(rows) do
            local item = row.item
            identity[#identity + 1] = item and tostring(item.id) or "#empty"
        end
        local identitySignature = table.concat(identity, "|")
        if identitySignature ~= templateListIdentitySignature_ then
            templateListIdentitySignature_ = identitySignature
            local scroll = templateVirtualList_.scrollView_
            local scrollX, scrollY = 0, 0
            if scroll and scroll.GetScroll then scrollX, scrollY = scroll:GetScroll() end
            templateVirtualList_:SetData(rows)
            if scroll and scroll.UpdateContentSize and scroll.SetScroll then
                scroll:UpdateContentSize()
                local bounces = scroll.props.bounces
                scroll.props.bounces = false
                scroll:SetScroll(scrollX, scrollY)
                scroll.props.bounces = bounces
            end
        else
            templateVirtualList_.props.data = rows
            templateVirtualList_:Refresh()
        end

        if templateListScroll_ and not rootRebuildInProgress_ then
            local scrollX, scrollY = templateListScroll_:GetScroll()
            UI.Layout()
            templateListScroll_:UpdateContentSize()
            local bounces = templateListScroll_.props.bounces
            templateListScroll_.props.bounces = false
            templateListScroll_:SetScroll(scrollX, scrollY)
            templateListScroll_.props.bounces = bounces
        end
    end
end

local function FormatNumber(value)
    local rounded = math.floor((tonumber(value) or 0) * 1000 + 0.5) / 1000
    return tostring(rounded)
end

local function RefreshField(field, value, focused)
    if focused == nil then focused = UI.GetFocus() end
    if field and focused ~= field and field._lastValue ~= value then
        field._lastValue = value
        field:SetValue(value)
    end
end

local function RefreshSelectedTransformFields(selected, focused)
    if not selected then return end
    if focused == nil then focused = UI.GetFocus() end
    RefreshField(selectedFields_.x, FormatNumber(selected.x), focused)
    RefreshField(selectedFields_.y, FormatNumber(selected.y), focused)
    RefreshField(selectedFields_.z, FormatNumber(selected.z), focused)
    RefreshField(selectedFields_.sx, FormatNumber(math.max(0.05, tonumber(selected.sx) or 0.05)), focused)
    RefreshField(selectedFields_.sy, FormatNumber(math.max(0.05, tonumber(selected.sy) or 0.05)), focused)
    RefreshField(selectedFields_.sz, FormatNumber(math.max(0.05, tonumber(selected.sz) or 0.05)), focused)
    RefreshField(selectedFields_.rotX, FormatNumber((selected.rx or 0) * 180 / math.pi), focused)
    RefreshField(selectedFields_.rotY, FormatNumber((selected.ry or 0) * 180 / math.pi), focused)
    RefreshField(selectedFields_.rotZ, FormatNumber((selected.rz or 0) * 180 / math.pi), focused)
end

function BuilderUI.Refresh(state, message)
    if IsTransformRefresh(state) then
        -- Coalesce all pointer samples until BuilderUI.Update. The delta table
        -- and selected block are intentionally stable references, so this hot
        -- path is O(1) and does not allocate per event.
        pendingTransformState_ = state
        return
    end
    pendingTransformState_, transformRefreshElapsed_ = nil, 0
    lastState_ = state
    refreshing_ = true
    local selected = state.selected
    if message then
        lastStatus_ = message
        if statusLabel_ then statusLabel_:SetText(message) end
    end
    if undoButton_ then undoButton_:SetDisabled(not state.canUndo) end
    if redoButton_ then redoButton_:SetDisabled(not state.canRedo) end

    for id, button in pairs(modeButtons_) do SetActiveIfChanged(button, state.mode == id) end
    for id, button in pairs(presetButtons_) do SetActiveIfChanged(button, state.presetId == id) end
    for id, button in pairs(newShapeButtons_) do SetActiveIfChanged(button, state.shapeId == id) end
    for id, button in pairs(selectedShapeButtons_) do SetActiveIfChanged(button, selected and selected.shapeId == id) end
    for id, button in pairs(transformButtons_) do SetActiveIfChanged(button, state.transformMode == id) end
    if colorPickOverlay_ then
        local active = state.colorPickTarget ~= nil
        SetVisibleIfChanged(colorPickOverlay_, active)
        if not active and resetColorPickOverlay_ then
            resetColorPickOverlay_()
        end
    end
    local function RefreshColorButton(button, active)
        if not button then return end
        if button._lastColorActive == active then return end
        button._lastColorActive = active
        button:SetStyle({
            borderColor = { 35, 64, 73, 34 },
            borderWidth = 2,
            boxShadow = active and {
                { x = 0, y = 0, blur = 0, spread = 3, color = COLORS.blue },
                { x = 0, y = 0, blur = 0, spread = 1, color = { 251, 254, 253, 255 } },
            } or false,
        })
    end
    for _, color in ipairs(Catalog.COLORS) do
        RefreshColorButton(colorButtons_[color.id], state.paletteActiveId == color.id)
    end

    local function RefreshMaterialButton(button, active)
        if not button then return end
        if button._lastMaterialActive == active then return end
        button._lastMaterialActive = active
        button:SetStyle({
            backgroundColor = active and COLORS.blue or button._materialPreview,
            hoverBackgroundColor = active and COLORS.blueDark or button._materialPreview,
            pressedBackgroundColor = active and COLORS.blueDark or button._materialPreview,
            textColor = active and COLORS.white or button._materialTextColor,
            borderColor = active and COLORS.blueDark or { 35, 64, 73, 45 },
            borderWidth = active and 2 or 1,
        })
    end
    for _, material in ipairs(Catalog.MATERIALS) do
        RefreshMaterialButton(newMaterialButtons_[material.id], state.newMaterialId == material.id)
        RefreshMaterialButton(selectedMaterialButtons_[material.id], selected and selected.materialId == material.id)
    end

    local focused = UI.GetFocus()
    if state.newSize then
        RefreshField(newSizeFields_.x, FormatNumber(state.newSize[1]), focused)
        RefreshField(newSizeFields_.y, FormatNumber(state.newSize[2]), focused)
        RefreshField(newSizeFields_.z, FormatNumber(state.newSize[3]), focused)
    end
    if newColorPicker_ then newColorPicker_:SetHex(state.newColor or "#f2e7cf") end
    if snapDropdown_ then snapDropdown_:SetValue(state.snap) end

    if selectionBadge_ then
        local selectionText = selected and (selected.name .. " · #" .. tostring(selected.id) .. " · 视野中心可自由平移")
            or "未选择积木 · 单指/左键旋转 · 双指/右键平移"
        SetTextIfChanged(selectionBadge_, selectionText)
    end
    if duplicateQuickButton_ then SetVisibleIfChanged(duplicateQuickButton_, selected ~= nil) end
    if noSelectionLabel_ then SetVisibleIfChanged(noSelectionLabel_, selected == nil) end
    if inspectorPanel_ then SetVisibleIfChanged(inspectorPanel_, selected ~= nil) end
    if selected then
        RefreshField(selectedFields_.name, selected.name, focused)
        RefreshSelectedTransformFields(selected, focused)
        if selectedColorPicker_ then selectedColorPicker_:SetHex(selected.color) end
    end

    if objectCountLabel_ then SetTextIfChanged(objectCountLabel_, "图层 (" .. tostring(state.count or 0) .. ")") end
    if templateCountLabel_ then
        local builtinCount, mineCount, marketCount = 0, 0, 0
        for _, item in ipairs(state.templates or {}) do
            local source = item.source or (item.builtin and "builtin" or "mine")
            if source == "builtin" then builtinCount = builtinCount + 1
            elseif source == "market" then marketCount = marketCount + 1
            else mineCount = mineCount + 1 end
        end
        SetTextIfChanged(templateCountLabel_, "内置 " .. tostring(builtinCount) .. " · 我的 " .. tostring(mineCount) .. " · 市场 " .. tostring(marketCount))
    end
    UpdateObjectList(state)
    UpdateTemplateList(state)
    refreshing_ = false
end

function BuilderUI.Update(timeStep)
    local state = TakePendingTransformState(timeStep, profile_ and profile_.mode or "desktop")
    if not state then return end
    refreshing_ = true
    RefreshSelectedTransformFields(state.selected)
    refreshing_ = false
end

function BuilderUI.IsPointerOverUI() return UI.IsPointerOverUI() end
function BuilderUI.GetVersion() return WORKBENCH_VERSION end
function BuilderUI.IsPointOverUI(x, y)
    local scale = math.max(0.01, UI.GetScale())
    return UI.FindWidgetAt(x / scale, y / scale) ~= nil
end
function BuilderUI.HasFocus() return UI.GetFocus() ~= nil end
function BuilderUI.ClearFocus() UI.ClearFocus() end
function BuilderUI.GetProfile() return profile_ end
BuilderUI._TemplateListHeight = TemplateListHeight
BuilderUI._TemplateCategoryLayout = TemplateCategoryLayout
BuilderUI._TemplateLibraryPolicy = TemplateLibraryPolicy
BuilderUI._TemplateVirtualRows = TemplateVirtualRows
BuilderUI._TemplateLibraryViewportHeight = TemplateLibraryViewportHeight
BuilderUI._TemplateVirtualContentHeight = TemplateVirtualContentHeight
BuilderUI._TemplateVirtualVisibleRange = TemplateVirtualVisibleRange
BuilderUI._CategoryGestureIsHorizontal = CategoryGestureIsHorizontal
BuilderUI._VirtualPoolUpperBound = VirtualPoolUpperBound
BuilderUI._ResponsiveMode = ResponsiveLayout.Resolve
BuilderUI._IsTransformRefresh = IsTransformRefresh
BuilderUI._TransformRefreshInterval = TransformRefreshInterval
BuilderUI._TakePendingTransformState = TakePendingTransformState

function BuilderUI.Shutdown()
    pendingTransformState_, transformRefreshElapsed_, rootRebuildInProgress_ = nil, 0, false
    UI.Shutdown()
end

return BuilderUI
