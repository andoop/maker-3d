local Theme = require("CloudAtelierTheme")

local BlockCatalog = {}

BlockCatalog.COLORS = Theme.EditorColors()

BlockCatalog.PRESETS = {
    { id = "story_cube", name = "绘本砖", size = { 1, 1, 1 } },
    { id = "half", name = "半格砖", size = { 0.5, 0.5, 0.5 } },
    { id = "detail", name = "精细砖", size = { 0.25, 0.25, 0.25 } },
    { id = "micro", name = "微型零件", size = { 0.12, 0.12, 0.12 } },
    { id = "slab", name = "草地薄板", size = { 1, 0.22, 1 } },
    { id = "step", name = "冒险台阶", size = { 1, 0.35, 0.65 } },
    { id = "trim", name = "彩绘收边", size = { 1, 0.12, 0.12 } },
    { id = "beam", name = "木梁", size = { 2, 0.22, 0.22 } },
    { id = "wall", name = "门窗墙片", size = { 2, 2, 0.25 } },
    { id = "low_wall", name = "矮墙", size = { 2, 0.75, 0.35 } },
    { id = "column", name = "圆润立柱", size = { 0.45, 2, 0.45 } },
    { id = "terrain", name = "地形单元", size = { 2, 1, 2 } },
}

-- Shape and size are intentionally independent: a sphere can use the slab
-- preset, and changing an existing object's shape preserves its transform.
-- `bounds` is the local-space occupied fraction used by selection, alignment
-- and collision helpers. Most geometries fill the normalized 1m cube; a torus
-- is naturally thinner along its hole axis.
BlockCatalog.SHAPES = {
    { id = "box", name = "圆角砖块", bounds = { 1, 1, 1 } },
    { id = "sphere", name = "软团球", bounds = { 1, 1, 1 } },
    { id = "cylinder", name = "原木圆柱", bounds = { 1, 1, 1 } },
    { id = "cone", name = "尖顶圆锥", bounds = { 1, 1, 1 } },
    { id = "tri_prism", name = "屋顶斜块", bounds = { 1, 1, 1 } },
    { id = "pyramid", name = "塔顶方锥", bounds = { 1, 1, 1 } },
    { id = "tetra", name = "晶体尖块", bounds = { 1, 1, 1 } },
    { id = "torus", name = "遗迹圆环", bounds = { 1, 1, 0.24 } },
}

-- Materials are editor-level presets. `preview` is used by the compact
-- material picker; the renderer owns the actual PBR/texture implementation.
BlockCatalog.MATERIALS = {
    { id = "solid", name = "暖雾灰泥", preview = Theme.MATERIAL_PREVIEWS.solid },
    { id = "painted_wood", name = "磨旧彩木", preview = Theme.MATERIAL_PREVIEWS.painted_wood },
    { id = "wood", name = "蜂蜜原木", preview = Theme.MATERIAL_PREVIEWS.wood },
    { id = "grass", name = "手绘风丘草", preview = Theme.MATERIAL_PREVIEWS.grass },
    { id = "leaf", name = "团簇叶片", preview = Theme.MATERIAL_PREVIEWS.leaf },
    { id = "moss", name = "潮润苔石", preview = Theme.MATERIAL_PREVIEWS.moss },
    { id = "earth", name = "暖陶土层", preview = Theme.MATERIAL_PREVIEWS.earth },
    { id = "stone", name = "圆润雨岩", preview = Theme.MATERIAL_PREVIEWS.stone },
    { id = "brick", name = "手绘砖块纹", preview = Theme.MATERIAL_PREVIEWS.brick },
    { id = "ruin_stone", name = "风化乱石墙", preview = Theme.MATERIAL_PREVIEWS.ruin_stone },
    { id = "old_brick", name = "残旧红砖墙", preview = Theme.MATERIAL_PREVIEWS.old_brick },
    { id = "carved_stone", name = "古代雕纹石", preview = Theme.MATERIAL_PREVIEWS.carved_stone },
    { id = "overgrown_stone", name = "荒草苔蚀石", preview = Theme.MATERIAL_PREVIEWS.overgrown_stone },
    { id = "roof_tile", name = "陶瓦鱼鳞纹", preview = Theme.MATERIAL_PREVIEWS.roof_tile },
    { id = "pavement", name = "广场石板纹", preview = Theme.MATERIAL_PREVIEWS.pavement },
    { id = "asphalt", name = "雾灰道路面", preview = Theme.MATERIAL_PREVIEWS.asphalt },
    { id = "snow", name = "柔雪粉刷", preview = Theme.MATERIAL_PREVIEWS.snow },
    { id = "marble", name = "日晒古石", preview = Theme.MATERIAL_PREVIEWS.marble },
    { id = "sand", name = "燕麦细沙", preview = Theme.MATERIAL_PREVIEWS.sand },
    { id = "water", name = "雾蓝溪水", preview = Theme.MATERIAL_PREVIEWS.water, transparent = true },
    { id = "glass", name = "雾蓝手作玻璃", preview = Theme.MATERIAL_PREVIEWS.glass, transparent = true },
    { id = "crystal", name = "薄荷晶石", preview = Theme.MATERIAL_PREVIEWS.crystal, transparent = true },
    { id = "ceramic", name = "窑烧陶器", preview = Theme.MATERIAL_PREVIEWS.ceramic },
    { id = "fabric", name = "亚麻软布", preview = Theme.MATERIAL_PREVIEWS.fabric },
    { id = "metal", name = "锤纹黄铜", preview = Theme.MATERIAL_PREVIEWS.metal },
    { id = "glow", name = "灯芯柔光", preview = Theme.MATERIAL_PREVIEWS.glow },
    { id = "fire", name = "壁炉余烬", preview = Theme.MATERIAL_PREVIEWS.fire, transparent = true },
}

BlockCatalog.SNAP_STEPS = { 1, 0.5, 0.25, 0.1, 0.05, 0.01, 0 }
BlockCatalog.SNAP_LABELS = {
    [1] = "1 格",
    [0.5] = "1/2 格",
    [0.25] = "1/4 格",
    [0.1] = "0.1 格",
    [0.05] = "0.05 格",
    [0.01] = "0.01 格",
    [0] = "自由位置",
}

function BlockCatalog.FindColor(id)
    for _, color in ipairs(BlockCatalog.COLORS) do
        if color.id == id then return color end
    end
    return BlockCatalog.COLORS[1]
end

function BlockCatalog.FindPreset(id)
    for _, preset in ipairs(BlockCatalog.PRESETS) do
        if preset.id == id then return preset end
    end
    return BlockCatalog.PRESETS[1]
end

function BlockCatalog.FindShape(id)
    for _, shape in ipairs(BlockCatalog.SHAPES) do
        if shape.id == id then return shape end
    end
    return BlockCatalog.SHAPES[1]
end

function BlockCatalog.FindMaterial(id)
    for _, material in ipairs(BlockCatalog.MATERIALS) do
        if material.id == id then return material end
    end
    return BlockCatalog.MATERIALS[1]
end

return BlockCatalog
