-- Shared art direction for the floating-island workbench.
-- Keeping the palette in one data-only module prevents the editor swatches,
-- procedural materials and authored templates from drifting into unrelated
-- visual styles again.

local Theme = {}

Theme.COLORS = {
    { id = "cream", name = "暖雾灰泥", css = "#f2e7cf" },
    { id = "parchment", name = "燕麦纸", css = "#dcc49a" },
    { id = "sun_grass", name = "风丘草", css = "#86b85a" },
    { id = "leaf", name = "鼠尾草绿", css = "#5d9861" },
    { id = "forest", name = "云杉绿", css = "#3f6e62" },
    { id = "moss", name = "苔石绿", css = "#6f8a50" },
    { id = "sky", name = "雾晴蓝", css = "#78b9d2" },
    { id = "lake", name = "溪谷蓝", css = "#5eafc2" },
    { id = "royal_blue", name = "风信蓝", css = "#597993" },
    { id = "deep_blue", name = "夜航靛", css = "#3e536c" },
    { id = "earth", name = "陶土棕", css = "#a86e4f" },
    { id = "wood", name = "蜂蜜木", css = "#8b6248" },
    { id = "wood_dark", name = "烟熏木", css = "#5c463a" },
    { id = "rock", name = "雨岩灰", css = "#899399" },
    { id = "rock_light", name = "日晒石", css = "#b8b8aa" },
    { id = "shadow", name = "岩影灰", css = "#59646b" },
    { id = "coral", name = "陶瓦红", css = "#c96f5d" },
    { id = "peach", name = "干花粉", css = "#d98a86" },
    { id = "purple", name = "暮雾紫", css = "#88779b" },
    { id = "yellow", name = "灯芯黄", css = "#d9b95f" },
    { id = "amber", name = "烤杏橙", css = "#c78a50" },
    { id = "gold", name = "旧黄铜", css = "#b38a52" },
    { id = "crystal", name = "薄荷晶", css = "#8bd2cc" },
    { id = "white", name = "云絮白", css = "#f7f1e3" },
}

Theme.MATERIAL_PREVIEWS = {
    solid = { 242, 231, 207, 255 },
    painted_wood = { 171, 125, 86, 255 },
    wood = { 139, 98, 72, 255 },
    grass = { 134, 184, 90, 255 },
    leaf = { 93, 152, 97, 255 },
    moss = { 111, 138, 80, 255 },
    earth = { 168, 110, 79, 255 },
    stone = { 137, 147, 153, 255 },
    brick = { 186, 103, 78, 255 },
    ruin_stone = { 157, 164, 162, 255 },
    old_brick = { 190, 125, 98, 255 },
    carved_stone = { 194, 190, 171, 255 },
    overgrown_stone = { 132, 154, 111, 255 },
    roof_tile = { 201, 111, 93, 255 },
    pavement = { 156, 160, 151, 255 },
    asphalt = { 91, 100, 104, 255 },
    snow = { 239, 242, 232, 255 },
    marble = { 184, 184, 170, 255 },
    sand = { 211, 184, 126, 255 },
    water = { 94, 175, 194, 255 },
    glass = { 178, 218, 218, 255 },
    crystal = { 139, 210, 204, 255 },
    ceramic = { 190, 111, 83, 255 },
    fabric = { 209, 156, 148, 255 },
    metal = { 126, 112, 88, 255 },
    glow = { 224, 196, 112, 255 },
    fire = { 219, 116, 65, 255 },
}

Theme.MODEL = {
    plaster = "#f2e7cf", plasterShade = "#dcc49a", cloud = "#f7f1e3",
    grass = "#86b85a", grassLight = "#a5c977", leaf = "#5d9861",
    forest = "#3f6e62", moss = "#6f8a50", earth = "#a86e4f",
    wood = "#8b6248", darkWood = "#5c463a", stone = "#899399",
    paleStone = "#b8b8aa", shadowStone = "#59646b", sky = "#78b9d2",
    water = "#5eafc2", blue = "#597993", navy = "#3e536c",
    terracotta = "#c96f5d", brick = "#ba674e", roofTile = "#c96f5d",
    pavement = "#9ca097", asphalt = "#5b6468", snow = "#eff2e8",
    rose = "#d98a86", yellow = "#d9b95f",
    amber = "#c78a50", brass = "#b38a52", glass = "#b2dada",
    crystal = "#8bd2cc", lavender = "#88779b",
}

Theme.ENVIRONMENT = {
    island = {
        grass = { 0x789f58, 0x82ac5c, 0x8ab563, 0x93bd6b, 0x708f52 },
        grassCool = { 0x668f67, 0x719c6d, 0x7ba775, 0x5f8262, 0x87b17c },
        grassWarm = { 0x8aa55d, 0x97b267, 0xa2bc72, 0x7e9857, 0x91aa62 },
        soil = { 0x956249, 0xa86e4f, 0xb77c59, 0x895945, 0x9e684c },
        rock = { 0x66737a, 0x778289, 0x899399, 0x9da4a2, 0x59666e },
        rockLight = { 0x969b98, 0xaaaba2, 0x858e91, 0xb8b8aa },
        shrubDark = 0x3f6e62,
        shrubLight = 0x86b85a,
    },
    cloud = {
        shadow = 0xb8ced5,
        cool = 0xc8dadd,
        soft = 0xd9e4e1,
        warm = 0xeee5d3,
        light = 0xf7f1e3,
    },
    -- Atmospheric perspective palettes for the explorable-looking islands in
    -- the background. Every farther tier leans a little more toward sky blue
    -- instead of merely shrinking the same saturated miniature.
    distance = {
        near = {
            grass = { 0x718f5c, 0x7d9d63, 0x86a66b },
            soil = { 0x8d654f, 0x9a7057, 0x82604f },
            rock = { 0x718087, 0x829097, 0x66767f },
        },
        mid = {
            grass = { 0x748f70, 0x819b78, 0x6c8870 },
            soil = { 0x806c61, 0x8b7568, 0x75665f },
            rock = { 0x778990, 0x87979c, 0x6d8089 },
        },
        far = {
            grass = { 0x829a8c, 0x8ca497, 0x789187 },
            soil = { 0x7c7974, 0x89847d, 0x727370 },
            rock = { 0x81969f, 0x8fa2aa, 0x758b96 },
        },
        horizon = {
            grass = { 0x91aaa6, 0x9bb3ae, 0x88a19f },
            soil = { 0x849093, 0x8f9a9d, 0x79878c },
            rock = { 0x8da5ae, 0x99afb6, 0x829ba6 },
        },
    },
    sky = {
        -- Layered hand-painted animation sky. The lower dome turns toward a
        -- turquoise ocean colour, visible only when the camera looks down.
        background = 0x54b7e6,
        sea = 0x2f9fb8,
        bottom = 0x8dd7e9,
        horizon = 0xa5e2f2,
        middle = 0x16b5ef,
        top = 0x0875d1,
    },
    light = {
        hemisphereSky = 0xfff5df,
        hemisphereGround = 0x75959a,
        sun = 0xffdfb1,
        fill = 0x9cd8ee,
    },
}

local function SaturateRgb(r, g, b, factor)
    local gray = r * 0.299 + g * 0.587 + b * 0.114
    local function channel(value)
        return math.max(0, math.min(255, math.floor(gray + (value - gray) * factor + 0.5)))
    end
    return channel(r), channel(g), channel(b)
end

local function SaturateCss(css, factor)
    local r, g, b = tonumber(css:sub(2, 3), 16), tonumber(css:sub(4, 5), 16), tonumber(css:sub(6, 7), 16)
    r, g, b = SaturateRgb(r, g, b, factor)
    return string.format("#%02x%02x%02x", r, g, b)
end

local function SaturatePacked(value, factor)
    local r = math.floor(value / 0x10000) % 0x100
    local g = math.floor(value / 0x100) % 0x100
    local b = value % 0x100
    r, g, b = SaturateRgb(r, g, b, factor)
    return r * 0x10000 + g * 0x100 + b
end

local function SaturatePackedTree(value, factor)
    if type(value) == "number" then return SaturatePacked(value, factor) end
    if type(value) ~= "table" then return value end
    for key, child in pairs(value) do value[key] = SaturatePackedTree(child, factor) end
    return value
end

local SATURATION = 1.24
for _, color in ipairs(Theme.COLORS) do color.css = SaturateCss(color.css, SATURATION) end
for key, css in pairs(Theme.MODEL) do Theme.MODEL[key] = SaturateCss(css, SATURATION) end
for _, rgba in pairs(Theme.MATERIAL_PREVIEWS) do
    rgba[1], rgba[2], rgba[3] = SaturateRgb(rgba[1], rgba[2], rgba[3], SATURATION)
end
SaturatePackedTree(Theme.ENVIRONMENT, SATURATION)

local function HexToRgba(css)
    return {
        tonumber(css:sub(2, 3), 16), tonumber(css:sub(4, 5), 16),
        tonumber(css:sub(6, 7), 16), 255,
    }
end

function Theme.EditorColors()
    local result = {}
    for index, source in ipairs(Theme.COLORS) do
        local rgba = HexToRgba(source.css)
        result[index] = {
            id = source.id, name = source.name, css = source.css,
            rgba = rgba,
            hex = rgba[1] * 0x10000 + rgba[2] * 0x100 + rgba[3],
        }
    end
    return result
end

return Theme
