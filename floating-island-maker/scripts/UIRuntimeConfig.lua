local UIRuntimeConfig = {}

-- The TapTap rounded font lives in the official-resource bundle and can be
-- downloaded while playing. On a cold mobile cache that leaves panels visible
-- before any glyphs are ready. MiSans is part of the engine/startup bundle, so
-- it is already available when the first game UI frame is rendered.
UIRuntimeConfig.FONTS = {
    {
        family = "sans",
        weights = {
            normal = "Fonts/MiSans-Regular.ttf",
            bold = "Fonts/MiSans-Bold.ttf",
        },
    },
}

function UIRuntimeConfig.Options(scale)
    return {
        theme = "default-taptap",
        fonts = UIRuntimeConfig.FONTS,
        scale = scale,
    }
end

return UIRuntimeConfig
