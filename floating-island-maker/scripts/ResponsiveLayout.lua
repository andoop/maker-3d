local ResponsiveLayout = {}

local MOBILE_PLATFORMS = {
    android = true,
    ios = true,
    ipados = true,
    harmonyos = true,
}

local function PlatformKey(platform)
    local normalized = tostring(platform or ""):lower():gsub("%s+", "")
    return normalized
end

function ResponsiveLayout.IsMobilePlatform(platform)
    return MOBILE_PLATFORMS[PlatformKey(platform)] == true
end

function ResponsiveLayout.Resolve(cssWidth, cssHeight, nativePlatform)
    local width = math.max(1, tonumber(cssWidth) or 1)
    local height = math.max(1, tonumber(cssHeight) or 1)
    local platform = PlatformKey(nativePlatform)

    -- Native mobile platform wins over viewport size. A large phone or foldable must not
    -- silently switch to the tablet/desktop chrome just because its CSS
    -- viewport crosses a breakpoint.
    if MOBILE_PLATFORMS[platform] then return "mobile" end

    if width > 1050 and height >= 620 then return "desktop" end
    if width >= 760 and height >= 500 then return "tablet" end
    return "mobile"
end

return ResponsiveLayout
