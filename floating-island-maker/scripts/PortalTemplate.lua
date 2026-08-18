local PortalTemplate = {}

PortalTemplate.ASSET_ID = "builtin:compose:cloud-gate-portal"
PortalTemplate.VERSION = 30

local function Block(name, x, y, z, sx, sy, sz, color, materialId, shapeId, rx, ry, rz, role)
    return {
        name = name, type = "block",
        position = { x, y, z }, size = { sx, sy, sz },
        rotation = { math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0) },
        color = color, materialId = materialId, shapeId = shapeId,
        collisionRole = role,
    }
end

function PortalTemplate.Build()
    local blocks = {
        Block("云门落脚石台", 0, 0.12, 0, 2.65, 0.24, 1.75,
            "#9aaeb8", "carved_stone", "cylinder", 0, 0, 0, "surface"),
        Block("云门左立柱", -1.08, 1.48, 0, 0.42, 2.72, 0.48,
            "#7893a2", "carved_stone", "cylinder", 0, 0, 0, "decorative"),
        Block("云门右立柱", 1.08, 1.48, 0, 0.42, 2.72, 0.48,
            "#7893a2", "carved_stone", "cylinder", 0, 0, 0, "decorative"),
        Block("云门拱顶", 0, 2.80, 0, 2.44, 0.40, 0.50,
            "#8ca5b2", "carved_stone", "box", 0, 0, 0, "decorative"),
        Block("云门能量镜面", 0, 1.46, 0.02, 1.78, 2.34, 0.07,
            "#7ee9e0", "glass", "box", 0, 0, 0, "decorative"),
        Block("云门光环", 0, 1.48, 0.02, 2.18, 2.70, 0.22,
            "#ffe48b", "glow", "torus", 0, 0, 0, "decorative"),
        Block("云门左导轨", -1.38, 1.28, 0.04, 0.11, 2.16, 0.16,
            "#e2b86b", "metal", "box", 0, 0, 0, "decorative"),
        Block("云门右导轨", 1.38, 1.28, 0.04, 0.11, 2.16, 0.16,
            "#e2b86b", "metal", "box", 0, 0, 0, "decorative"),
        Block("云门左符文", -1.08, 2.24, 0.30, 0.20, 0.20, 0.20,
            "#fff2a8", "glow", "sphere", 0, 0, 0, "decorative"),
        Block("云门右符文", 1.08, 2.24, 0.30, 0.20, 0.20, 0.20,
            "#fff2a8", "glow", "sphere", 0, 0, 0, "decorative"),
        Block("云门顶端星核", 0, 3.12, 0.08, 0.30, 0.30, 0.30,
            "#fff7c8", "glow", "sphere", 0, 0, 0, "decorative"),
    }
    return {
        version = PortalTemplate.VERSION,
        id = PortalTemplate.ASSET_ID,
        builtin = true,
        category = "传送机关",
        designProfile = "wonder-showcase",
        recommendedScale = 1,
        name = "成对云门",
        description = "成对绑定空岛 点击或步入传送",
        storeys = 0,
        tags = { "传送门", "成对机关", "空岛连接" },
        thumbnail = "image/model-thumbs/cloud-gate-portal.png",
        blocks = blocks,
    }
end

return PortalTemplate
