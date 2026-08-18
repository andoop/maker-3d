local IslandTerrainCatalog = {}
local RandomTerrainGenerator = require("RandomTerrainGenerator")

IslandTerrainCatalog.DEFAULT_ID = "storybook-triple-archipelago-large"

local ORDER = {
    IslandTerrainCatalog.DEFAULT_ID,
    "windstep-meadow",
    "cloudpine-spire",
    "moonbay-gardens",
    "starfall-ring",
    "twin-gate-highlands",
    "cascade-terraces",
    "sky-whale-ridge",
    "world-tree-spiral",
    "twin-vine-spiral",
}

-- Terrain records are intentionally engine-free. Rendering, placement,
-- traversal and camera code all resolve the same authored measurements through
-- IslandLayout instead of keeping their own copies of the island positions.
local PRESETS = {
    [IslandTerrainCatalog.DEFAULT_ID] = {
        id = IslandTerrainCatalog.DEFAULT_ID,
        name = "云桥三岛",
        description = "三座宽阔草岛由断桥相连",
        groundY = 0.42,
        edgeInset = 0.32,
        overview = { x = 0, y = -1.0, z = 7, radius = 118 },
        camera = {
            theta = 0.733, phi = 0.96, radius = 118,
            target = { 0, -1.0, 7, x = 0, y = -1.0, z = 7 },
        },
        renderDistance = { skyRadius = 680, cameraFar = 1400 },
        islands = {
            {
                id = "heart", name = "中央原野", x = 0, z = -16,
                radius = 29, radiusX = 29, radiusZ = 29, groundY = 0.42,
                focusRadius = 72, focusY = -1.0, style = "meadow", seed = 72,
            },
            {
                id = "west", name = "西风林岛", x = -44, z = 24,
                radius = 21, radiusX = 21, radiusZ = 21, groundY = 0.42,
                focusRadius = 62, focusY = -1.0, style = "cool-grove", seed = 133,
            },
            {
                id = "east", name = "晨光山岛", x = 44, z = 24,
                radius = 21, radiusX = 21, radiusZ = 21, groundY = 0.42,
                focusRadius = 62, focusY = -1.0, style = "warm-meadow", seed = 194,
            },
        },
        bridges = {
            { id = "heart-west", from = "heart", to = "west", halfWidth = 2.30, maxStepHeight = 0.24 },
            { id = "heart-east", from = "heart", to = "east", halfWidth = 2.30, maxStepHeight = 0.24 },
            { id = "west-east", from = "west", to = "east", halfWidth = 2.10, maxStepHeight = 0.24 },
        },
    },

    ["windstep-meadow"] = {
        id = "windstep-meadow",
        name = "风环裂谷",
        description = "巨型环崖、断桥与悬空卫岛",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "wind-ring",
        overview = { x = 4, y = 1.8, z = 5, radius = 180 },
        camera = {
            theta = 0.68, phi = 0.92, radius = 180,
            target = { 4, 1.8, 5, x = 4, y = 1.8, z = 5 },
        },
        renderDistance = { skyRadius = 760, cameraFar = 1580 },
        islands = {
            {
                id = "west-arc", name = "西风巨环", x = -45, z = 0,
                radius = 25, radiusX = 18, radiusZ = 27, groundY = 0.42,
                focusRadius = 76, focusY = -1.2, style = "wind-cliff", seed = 311,
                terrainProfile = "sheer", depthScale = 1.55, tipLeanX = -2.8,
            },
            {
                id = "north-arc", name = "北境环台", x = -12, z = -38,
                radius = 20, radiusX = 22, radiusZ = 13, groundY = 2.65,
                focusRadius = 68, focusY = 0.8, style = "wind-cliff", seed = 372,
                terrainProfile = "shelf", depthScale = 1.45, tipLeanZ = -2.4,
            },
            {
                id = "south-arc", name = "南境环台", x = -12, z = 40,
                radius = 22, radiusX = 24, radiusZ = 14, groundY = -1.55,
                focusRadius = 70, focusY = -3.0, style = "wind-cliff", seed = 433,
                terrainProfile = "shelf", depthScale = 1.70, tipLeanZ = 3.0,
            },
            {
                id = "sun-crown", name = "日冠高岛", x = 48, z = -42,
                radius = 15, radiusX = 15, radiusZ = 11, groundY = 9.20,
                focusRadius = 54, focusY = 7.4, style = "sunstone", seed = 494,
                terrainProfile = "spire", depthScale = 2.15, tipLeanX = 1.6,
            },
            {
                id = "east-gate", name = "东侧门岛", x = 65, z = 3,
                radius = 10, radiusX = 10, radiusZ = 8, groundY = 3.65,
                focusRadius = 46, focusY = 2.0, style = "wind-cliff", seed = 555,
                terrainProfile = "needle", depthScale = 2.10, tipLeanX = 2.1,
            },
            {
                id = "bloom-reach", name = "南岬浮岛", x = 47, z = 47,
                radius = 16, radiusX = 17, radiusZ = 13, groundY = -2.75,
                focusRadius = 56, focusY = -4.2, style = "warm-cliff", seed = 616,
                terrainProfile = "spire", depthScale = 1.90, tipLeanZ = 2.5,
            },
            {
                id = "heart-shard", name = "环心孤岩", x = 14, z = 8,
                radius = 6, radiusX = 6, radiusZ = 5, groundY = 5.40,
                focusRadius = 38, focusY = 4.0, style = "stone", seed = 677,
                terrainProfile = "needle", depthScale = 2.45,
            },
        },
        bridges = {
            { id = "west-north", from = "west-arc", to = "north-arc", halfWidth = 1.55, maxStepHeight = 0.52, stepSpacing = 2.55 },
            { id = "west-south", from = "west-arc", to = "south-arc", halfWidth = 1.65, maxStepHeight = 0.52, stepSpacing = 2.55 },
            { id = "north-crown", from = "north-arc", to = "sun-crown", halfWidth = 1.45, maxStepHeight = 0.56, stepSpacing = 2.45 },
            { id = "crown-gate", from = "sun-crown", to = "east-gate", halfWidth = 1.35, maxStepHeight = 0.56, stepSpacing = 2.35 },
            { id = "gate-reach", from = "east-gate", to = "bloom-reach", halfWidth = 1.35, maxStepHeight = 0.56, stepSpacing = 2.45 },
            { id = "reach-south", from = "bloom-reach", to = "south-arc", halfWidth = 1.50, maxStepHeight = 0.52, stepSpacing = 2.55 },
            { id = "south-heart", from = "south-arc", to = "heart-shard", halfWidth = 1.20, maxStepHeight = 0.58, stepSpacing = 2.35 },
        },
    },

    ["cloudpine-spire"] = {
        id = "cloudpine-spire",
        name = "天柱云径",
        description = "双拱山柱与盘旋登顶之路",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "sky-pillar",
        overview = { x = 1, y = 6.5, z = -8, radius = 176 },
        camera = {
            theta = 0.80, phi = 0.88, radius = 176,
            target = { 1, 6.5, -8, x = 1, y = 6.5, z = -8 },
        },
        renderDistance = { skyRadius = 750, cameraFar = 1560 },
        islands = {
            {
                id = "root-basin", name = "山门根台", x = -5, z = 45,
                radius = 23, radiusX = 26, radiusZ = 18, groundY = -2.20,
                focusRadius = 72, focusY = -3.8, style = "stone-root", seed = 521,
                terrainProfile = "sheer", depthScale = 1.85, tipLeanZ = 2.8,
            },
            {
                id = "west-shelf", name = "西壁石阶", x = -46, z = 15,
                radius = 12, radiusX = 13, radiusZ = 9, groundY = 2.40,
                focusRadius = 48, focusY = 0.7, style = "stone", seed = 582,
                terrainProfile = "spire", depthScale = 2.05, tipLeanX = -2.1,
            },
            {
                id = "arch-terrace", name = "巨拱腰台", x = -45, z = -24,
                radius = 11, radiusX = 12, radiusZ = 9, groundY = 7.10,
                focusRadius = 48, focusY = 5.4, style = "stone", seed = 643,
                terrainProfile = "spire", depthScale = 2.30, tipLeanX = -1.2,
            },
            {
                id = "summit-crown", name = "天柱冠台", x = -12, z = -63,
                radius = 11, radiusX = 12, radiusZ = 8, groundY = 18.20,
                focusRadius = 52, focusY = 15.8, style = "stone-crown", seed = 704,
                terrainProfile = "pillar", depthScale = 2.75, tipLeanZ = -1.5,
            },
            {
                id = "east-arch", name = "东拱高台", x = 30, z = -40,
                radius = 10, radiusX = 11, radiusZ = 8, groundY = 11.20,
                focusRadius = 48, focusY = 9.4, style = "stone", seed = 765,
                terrainProfile = "pillar", depthScale = 2.35, tipLeanX = 1.5,
            },
            {
                id = "east-ledge", name = "东壁回台", x = 50, z = 2,
                radius = 11, radiusX = 12, radiusZ = 9, groundY = 5.30,
                focusRadius = 48, focusY = 3.6, style = "stone", seed = 826,
                terrainProfile = "spire", depthScale = 2.10, tipLeanX = 2.3,
            },
            {
                id = "far-needle", name = "远望尖岛", x = 67, z = -67,
                radius = 6, radiusX = 6, radiusZ = 5, groundY = 14.40,
                focusRadius = 38, focusY = 12.8, style = "stone-crown", seed = 887,
                terrainProfile = "needle", depthScale = 2.75,
            },
        },
        bridges = {
            { id = "root-west", from = "root-basin", to = "west-shelf", halfWidth = 1.55, maxStepHeight = 0.54, stepSpacing = 2.35 },
            { id = "west-arch", from = "west-shelf", to = "arch-terrace", halfWidth = 1.42, maxStepHeight = 0.54, stepSpacing = 2.30 },
            { id = "arch-summit", from = "arch-terrace", to = "summit-crown", halfWidth = 1.32, maxStepHeight = 0.58, stepSpacing = 2.20 },
            { id = "summit-east", from = "summit-crown", to = "east-arch", halfWidth = 1.28, maxStepHeight = 0.58, stepSpacing = 2.20 },
            { id = "east-descent", from = "east-arch", to = "east-ledge", halfWidth = 1.42, maxStepHeight = 0.56, stepSpacing = 2.30 },
            { id = "ledge-root", from = "east-ledge", to = "root-basin", halfWidth = 1.55, maxStepHeight = 0.54, stepSpacing = 2.35 },
        },
    },

    ["moonbay-gardens"] = {
        id = "moonbay-gardens",
        name = "月蚀断崖",
        description = "双月牙峡谷与漂浮石门",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "moon-rift",
        overview = { x = 4, y = 4.0, z = -5, radius = 190 },
        camera = {
            theta = 0.64, phi = 0.92, radius = 190,
            target = { 4, 4.0, -5, x = 4, y = 4.0, z = -5 },
        },
        renderDistance = { skyRadius = 750, cameraFar = 1560 },
        islands = {
            {
                id = "south-basin", name = "月谷根岛", x = 0, z = 50,
                radius = 24, radiusX = 29, radiusZ = 18, groundY = -1.60,
                focusRadius = 76, focusY = -3.3, style = "moonstone", seed = 811,
                terrainProfile = "sheer", depthScale = 1.80, tipLeanZ = 3.1,
            },
            {
                id = "west-crescent", name = "西月长崖", x = -47, z = 10,
                radius = 18, radiusX = 15, radiusZ = 24, groundY = 3.20,
                focusRadius = 60, focusY = 1.4, style = "moonstone", seed = 872,
                terrainProfile = "pillar", depthScale = 2.20, tipLeanX = -2.6,
            },
            {
                id = "west-horn", name = "西月尖冠", x = -45, z = -70,
                radius = 10, radiusX = 9, radiusZ = 13, groundY = 12.60,
                focusRadius = 48, focusY = 10.6, style = "moonstone", seed = 933,
                terrainProfile = "needle", depthScale = 2.85, tipLeanZ = -1.8,
            },
            {
                id = "east-crescent", name = "东月长崖", x = 49, z = 10,
                radius = 18, radiusX = 15, radiusZ = 24, groundY = 5.20,
                focusRadius = 62, focusY = 3.2, style = "warm-cliff", seed = 994,
                terrainProfile = "pillar", depthScale = 2.25, tipLeanX = 2.7,
            },
            {
                id = "east-horn", name = "东月尖冠", x = 45, z = -72,
                radius = 9, radiusX = 9, radiusZ = 12, groundY = 15.80,
                focusRadius = 48, focusY = 13.7, style = "warm-cliff", seed = 1055,
                terrainProfile = "needle", depthScale = 2.95, tipLeanZ = -2.0,
            },
            {
                id = "eclipse-gate", name = "蚀心石门", x = 0, z = -38,
                radius = 7, radiusX = 7, radiusZ = 6, groundY = 8.10,
                focusRadius = 42, focusY = 6.5, style = "stone", seed = 1116,
                terrainProfile = "needle", depthScale = 2.55,
            },
            {
                id = "falling-moon", name = "坠月孤岛", x = 72, z = 55,
                radius = 8, radiusX = 8, radiusZ = 6, groundY = -4.60,
                focusRadius = 42, focusY = -6.0, style = "moonstone", seed = 1177,
                terrainProfile = "needle", depthScale = 2.50, tipLeanX = 1.7,
            },
        },
        bridges = {
            { id = "basin-west", from = "south-basin", to = "west-crescent", halfWidth = 1.55, maxStepHeight = 0.54, stepSpacing = 2.45 },
            { id = "west-horn", from = "west-crescent", to = "west-horn", halfWidth = 1.34, maxStepHeight = 0.58, stepSpacing = 2.25 },
            { id = "west-gate", from = "west-horn", to = "eclipse-gate", halfWidth = 1.20, maxStepHeight = 0.58, stepSpacing = 2.25 },
            { id = "gate-east", from = "eclipse-gate", to = "east-horn", halfWidth = 1.20, maxStepHeight = 0.58, stepSpacing = 2.25 },
            { id = "east-horn", from = "east-horn", to = "east-crescent", halfWidth = 1.34, maxStepHeight = 0.58, stepSpacing = 2.25 },
            { id = "east-basin", from = "east-crescent", to = "south-basin", halfWidth = 1.55, maxStepHeight = 0.54, stepSpacing = 2.45 },
        },
    },

    ["starfall-ring"] = {
        id = "starfall-ring",
        name = "星坠环庭",
        description = "陨星主庭与高低环绕的碎裂卫岛",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "starfall-ring",
        overview = { x = -2, y = 3.0, z = 5, radius = 188 },
        camera = {
            theta = 0.70, phi = 0.91, radius = 188,
            target = { -2, 3.0, 5, x = -2, y = 3.0, z = 5 },
        },
        renderDistance = { skyRadius = 780, cameraFar = 1620 },
        islands = {
            { id = "crater-court", name = "陨星主庭", x = 0, z = 8,
                radius = 28, radiusX = 32, radiusZ = 24, groundY = 0.42,
                focusRadius = 78, focusY = -1.2, style = "moonstone", seed = 1231,
                terrainProfile = "sheer", depthScale = 1.82, tipLeanZ = 1.8 },
            { id = "north-star", name = "北辰高台", x = 0, z = -49,
                radius = 15, radiusX = 18, radiusZ = 13, groundY = 11.8,
                focusRadius = 56, focusY = 9.7, style = "stone-crown", seed = 1292,
                terrainProfile = "pillar", depthScale = 2.55, tipLeanZ = -2.2 },
            { id = "east-shard", name = "东侧星片", x = 51, z = -13,
                radius = 14, radiusX = 17, radiusZ = 12, groundY = 5.4,
                focusRadius = 54, focusY = 3.4, style = "warm-cliff", seed = 1353,
                terrainProfile = "spire", depthScale = 2.15, tipLeanX = 2.1 },
            { id = "south-orbit", name = "南轨浮台", x = 25, z = 57,
                radius = 13, radiusX = 15, radiusZ = 11, groundY = -4.6,
                focusRadius = 52, focusY = -6.0, style = "wind-cliff", seed = 1414,
                terrainProfile = "spire", depthScale = 2.05, tipLeanZ = 2.4 },
            { id = "west-shard", name = "西侧星片", x = -53, z = -8,
                radius = 15, radiusX = 17, radiusZ = 13, groundY = 3.1,
                focusRadius = 54, focusY = 1.3, style = "moonstone", seed = 1475,
                terrainProfile = "spire", depthScale = 2.20, tipLeanX = -2.4 },
            { id = "far-mote", name = "远星孤岩", x = -67, z = 54,
                radius = 7, radiusX = 8, radiusZ = 6, groundY = 8.4,
                focusRadius = 40, focusY = 6.8, style = "stone-crown", seed = 1536,
                terrainProfile = "needle", depthScale = 2.75, tipLeanX = -1.5 },
        },
        bridges = {
            { id = "court-north", from = "crater-court", to = "north-star", halfWidth = 1.55, maxStepHeight = 0.95, stepSpacing = 2.55 },
            { id = "north-east", from = "north-star", to = "east-shard", halfWidth = 1.35, maxStepHeight = 0.95, stepSpacing = 2.45 },
            { id = "east-south", from = "east-shard", to = "south-orbit", halfWidth = 1.42, maxStepHeight = 0.95, stepSpacing = 2.55 },
            { id = "south-court", from = "south-orbit", to = "crater-court", halfWidth = 1.55, maxStepHeight = 0.95, stepSpacing = 2.60 },
            { id = "court-west", from = "crater-court", to = "west-shard", halfWidth = 1.55, maxStepHeight = 0.95, stepSpacing = 2.60 },
            { id = "west-far", from = "west-shard", to = "far-mote", halfWidth = 1.22, maxStepHeight = 0.95, stepSpacing = 2.40 },
        },
    },

    ["twin-gate-highlands"] = {
        id = "twin-gate-highlands",
        name = "双峰天门",
        description = "两座巨柱托起高空石门与环形登山路",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "twin-gate",
        overview = { x = 0, y = 6.5, z = -3, radius = 192 },
        camera = {
            theta = 0.78, phi = 0.87, radius = 192,
            target = { 0, 6.5, -3, x = 0, y = 6.5, z = -3 },
        },
        renderDistance = { skyRadius = 790, cameraFar = 1640 },
        islands = {
            { id = "gate-basin", name = "天门根台", x = 0, z = 53,
                radius = 25, radiusX = 30, radiusZ = 20, groundY = -2.4,
                focusRadius = 80, focusY = -4.0, style = "stone-root", seed = 1611,
                terrainProfile = "sheer", depthScale = 1.90, tipLeanZ = 3.0 },
            { id = "west-titan", name = "西天柱", x = -38, z = 5,
                radius = 17, radiusX = 18, radiusZ = 15, groundY = 6.2,
                focusRadius = 60, focusY = 4.0, style = "stone", seed = 1672,
                terrainProfile = "pillar", depthScale = 2.72, tipLeanX = -2.2 },
            { id = "east-titan", name = "东天柱", x = 38, z = 5,
                radius = 17, radiusX = 18, radiusZ = 15, groundY = 9.4,
                focusRadius = 60, focusY = 7.2, style = "warm-cliff", seed = 1733,
                terrainProfile = "pillar", depthScale = 2.82, tipLeanX = 2.2 },
            { id = "gate-crown", name = "云顶石门", x = 0, z = -46,
                radius = 15, radiusX = 17, radiusZ = 12, groundY = 18.4,
                focusRadius = 58, focusY = 16.0, style = "stone-crown", seed = 1794,
                terrainProfile = "pillar", depthScale = 3.05, tipLeanZ = -2.0 },
            { id = "west-stair", name = "西回廊", x = -63, z = -35,
                radius = 10, radiusX = 11, radiusZ = 9, groundY = 11.3,
                focusRadius = 46, focusY = 9.5, style = "stone", seed = 1855,
                terrainProfile = "needle", depthScale = 2.55, tipLeanX = -2.0 },
            { id = "east-stair", name = "东回廊", x = 63, z = -35,
                radius = 10, radiusX = 11, radiusZ = 9, groundY = 13.6,
                focusRadius = 46, focusY = 11.8, style = "stone", seed = 1916,
                terrainProfile = "needle", depthScale = 2.65, tipLeanX = 2.0 },
        },
        bridges = {
            { id = "basin-west", from = "gate-basin", to = "west-titan", halfWidth = 1.62, maxStepHeight = 0.95, stepSpacing = 2.55 },
            { id = "basin-east", from = "gate-basin", to = "east-titan", halfWidth = 1.62, maxStepHeight = 0.95, stepSpacing = 2.55 },
            { id = "west-stair", from = "west-titan", to = "west-stair", halfWidth = 1.35, maxStepHeight = 0.95, stepSpacing = 2.40 },
            { id = "west-crown", from = "west-stair", to = "gate-crown", halfWidth = 1.28, maxStepHeight = 0.95, stepSpacing = 2.35 },
            { id = "crown-east", from = "gate-crown", to = "east-stair", halfWidth = 1.28, maxStepHeight = 0.95, stepSpacing = 2.35 },
            { id = "east-titan", from = "east-stair", to = "east-titan", halfWidth = 1.35, maxStepHeight = 0.95, stepSpacing = 2.40 },
        },
    },

    ["cascade-terraces"] = {
        id = "cascade-terraces",
        name = "云瀑千阶",
        description = "宽阔平台沿天空瀑布般逐级攀升",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "cascade-terraces",
        overview = { x = -4, y = 4.0, z = -1, radius = 214 },
        camera = {
            theta = 0.66, phi = 0.91, radius = 214,
            target = { -4, 4.0, -1, x = -4, y = 4.0, z = -1 },
        },
        renderDistance = { skyRadius = 790, cameraFar = 1640 },
        islands = {
            { id = "lower-fan", name = "云瀑下庭", x = -75, z = 72,
                radius = 24, radiusX = 30, radiusZ = 18, groundY = -6.2,
                focusRadius = 78, focusY = -8.0, style = "cool-cliff", seed = 1991,
                terrainProfile = "sheer", depthScale = 1.75, tipLeanX = -2.0 },
            { id = "first-terrace", name = "初阶原台", x = -14, z = 38,
                radius = 20, radiusX = 24, radiusZ = 16, groundY = -1.2,
                focusRadius = 68, focusY = -3.0, style = "wind-cliff", seed = 2052,
                terrainProfile = "shelf", depthScale = 1.72 },
            { id = "middle-terrace", name = "中天阔台", x = 48, z = 3,
                radius = 20, radiusX = 24, radiusZ = 18, groundY = 4.2,
                focusRadius = 68, focusY = 2.4, style = "warm-cliff", seed = 2113,
                terrainProfile = "shelf", depthScale = 1.90, tipLeanX = 1.5 },
            { id = "upper-terrace", name = "上云回台", x = 3, z = -35,
                radius = 17, radiusX = 20, radiusZ = 15, groundY = 9.6,
                focusRadius = 62, focusY = 7.6, style = "stone", seed = 2174,
                terrainProfile = "pillar", depthScale = 2.25 },
            { id = "cascade-crown", name = "瀑顶冠岛", x = -39, z = -65,
                radius = 15, radiusX = 17, radiusZ = 12, groundY = 16.1,
                focusRadius = 56, focusY = 14.0, style = "stone-crown", seed = 2235,
                terrainProfile = "pillar", depthScale = 2.82, tipLeanZ = -2.0 },
            { id = "east-fall", name = "东坠孤台", x = 78, z = -52,
                radius = 8, radiusX = 9, radiusZ = 7, groundY = 7.0,
                focusRadius = 42, focusY = 5.3, style = "stone", seed = 2296,
                terrainProfile = "needle", depthScale = 2.55, tipLeanX = 1.8 },
            { id = "west-shelf", name = "西侧断层", x = -82, z = -4,
                radius = 10, radiusX = 12, radiusZ = 8, groundY = 1.8,
                focusRadius = 46, focusY = 0.2, style = "cool-cliff", seed = 2357,
                terrainProfile = "needle", depthScale = 2.40, tipLeanX = -2.2 },
        },
        bridges = {
            { id = "lower-first", from = "lower-fan", to = "first-terrace", halfWidth = 1.70, maxStepHeight = 0.90, stepSpacing = 2.65 },
            { id = "first-middle", from = "first-terrace", to = "middle-terrace", halfWidth = 1.62, maxStepHeight = 0.90, stepSpacing = 2.60 },
            { id = "middle-upper", from = "middle-terrace", to = "upper-terrace", halfWidth = 1.52, maxStepHeight = 0.90, stepSpacing = 2.50 },
            { id = "upper-crown", from = "upper-terrace", to = "cascade-crown", halfWidth = 1.40, maxStepHeight = 0.90, stepSpacing = 2.40 },
            { id = "middle-east", from = "middle-terrace", to = "east-fall", halfWidth = 1.25, maxStepHeight = 0.90, stepSpacing = 2.40 },
            { id = "first-west", from = "first-terrace", to = "west-shelf", halfWidth = 1.28, maxStepHeight = 0.90, stepSpacing = 2.45 },
        },
    },

    ["sky-whale-ridge"] = {
        id = "sky-whale-ridge",
        name = "鲸脊浮陆",
        description = "巨型长脊展开双翼般的悬空山陆",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "sky-whale",
        overview = { x = 0, y = 3.5, z = 1, radius = 218 },
        camera = {
            theta = 0.74, phi = 0.93, radius = 218,
            target = { 0, 3.5, 1, x = 0, y = 3.5, z = 1 },
        },
        renderDistance = { skyRadius = 800, cameraFar = 1660 },
        islands = {
            { id = "whale-head", name = "鲸首原野", x = -65, z = -8,
                radius = 23, radiusX = 28, radiusZ = 21, groundY = 3.0,
                focusRadius = 76, focusY = 1.1, style = "cool-cliff", seed = 2431,
                terrainProfile = "sheer", depthScale = 2.05, tipLeanX = -3.0 },
            { id = "whale-spine", name = "长脊中庭", x = 0, z = 1,
                radius = 22, radiusX = 32, radiusZ = 15, groundY = 5.1,
                focusRadius = 76, focusY = 3.2, style = "wind-cliff", seed = 2492,
                terrainProfile = "pillar", depthScale = 2.30 },
            { id = "whale-tail", name = "鲸尾岬台", x = 68, z = 25,
                radius = 18, radiusX = 24, radiusZ = 12, groundY = 1.4,
                focusRadius = 64, focusY = -0.4, style = "warm-cliff", seed = 2553,
                terrainProfile = "shelf", depthScale = 1.95, tipLeanX = 3.0 },
            { id = "north-fin", name = "北翼高岛", x = 1, z = -52,
                radius = 16, radiusX = 15, radiusZ = 20, groundY = 10.2,
                focusRadius = 60, focusY = 8.2, style = "stone-crown", seed = 2614,
                terrainProfile = "spire", depthScale = 2.45, tipLeanZ = -2.5 },
            { id = "south-fin", name = "南翼低岛", x = -1, z = 55,
                radius = 17, radiusX = 16, radiusZ = 21, groundY = -2.5,
                focusRadius = 62, focusY = -4.0, style = "cool-cliff", seed = 2675,
                terrainProfile = "spire", depthScale = 2.30, tipLeanZ = 2.6 },
            { id = "whale-eye", name = "远眸孤岩", x = -90, z = -55,
                radius = 7, radiusX = 8, radiusZ = 6, groundY = 12.4,
                focusRadius = 40, focusY = 10.8, style = "stone-crown", seed = 2736,
                terrainProfile = "needle", depthScale = 2.80, tipLeanX = -1.6 },
            { id = "tail-crown", name = "尾冠浮岛", x = 84, z = -42,
                radius = 9, radiusX = 10, radiusZ = 8, groundY = 8.1,
                focusRadius = 44, focusY = 6.4, style = "warm-cliff", seed = 2797,
                terrainProfile = "needle", depthScale = 2.55, tipLeanX = 1.8 },
        },
        bridges = {
            { id = "head-spine", from = "whale-head", to = "whale-spine", halfWidth = 1.75, maxStepHeight = 1.00, stepSpacing = 2.70 },
            { id = "spine-tail", from = "whale-spine", to = "whale-tail", halfWidth = 1.70, maxStepHeight = 1.00, stepSpacing = 2.70 },
            { id = "spine-north", from = "whale-spine", to = "north-fin", halfWidth = 1.48, maxStepHeight = 1.00, stepSpacing = 2.50 },
            { id = "spine-south", from = "whale-spine", to = "south-fin", halfWidth = 1.48, maxStepHeight = 1.00, stepSpacing = 2.50 },
            { id = "head-eye", from = "whale-head", to = "whale-eye", halfWidth = 1.20, maxStepHeight = 1.00, stepSpacing = 2.35 },
            { id = "tail-crown", from = "whale-tail", to = "tail-crown", halfWidth = 1.24, maxStepHeight = 1.00, stepSpacing = 2.40 },
        },
    },

    ["world-tree-spiral"] = {
        id = "world-tree-spiral",
        name = "苍穹世界树",
        description = "九层枝台绕巨木盘旋升向树冠",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "world-tree-spiral",
        connectionStyle = "shattered-stepping-stones",
        overview = { x = 0, y = 12.5, z = 1, radius = 224 },
        camera = {
            theta = 0.70, phi = 0.86, radius = 224,
            target = { 0, 12.5, 1, x = 0, y = 12.5, z = 1 },
        },
        renderDistance = { skyRadius = 820, cameraFar = 1700 },
        islands = {
            { id = "root-garden", name = "世界树根庭", x = 0, z = 68,
                radius = 27, radiusX = 31, radiusZ = 22, groundY = -6.0,
                focusRadius = 82, focusY = -7.8, style = "stone-root", seed = 2861,
                terrainProfile = "sheer", depthScale = 2.05, tipLeanZ = 3.2 },
            { id = "lower-bough", name = "初芽枝台", x = -55, z = 45,
                radius = 17, radiusX = 19, radiusZ = 14, groundY = -1.0,
                focusRadius = 62, focusY = -2.8, style = "cool-cliff", seed = 2922,
                terrainProfile = "shelf", depthScale = 2.10, tipLeanX = -2.2 },
            { id = "west-bough", name = "西风枝台", x = -72, z = 3,
                radius = 15, radiusX = 17, radiusZ = 12, groundY = 4.0,
                focusRadius = 58, focusY = 2.2, style = "wind-cliff", seed = 2983,
                terrainProfile = "spire", depthScale = 2.35, tipLeanX = -2.7 },
            { id = "northwest-bough", name = "暮云枝台", x = -50, z = -44,
                radius = 14, radiusX = 16, radiusZ = 11, groundY = 9.0,
                focusRadius = 56, focusY = 7.2, style = "stone", seed = 3044,
                terrainProfile = "pillar", depthScale = 2.55, tipLeanZ = -2.0 },
            { id = "north-bough", name = "云背枝台", x = 0, z = -68,
                radius = 14, radiusX = 16, radiusZ = 11, groundY = 14.0,
                focusRadius = 56, focusY = 12.2, style = "stone-crown", seed = 3105,
                terrainProfile = "pillar", depthScale = 2.72, tipLeanZ = -2.4 },
            { id = "northeast-bough", name = "晨辉枝台", x = 50, z = -45,
                radius = 13, radiusX = 15, radiusZ = 11, groundY = 19.0,
                focusRadius = 54, focusY = 17.2, style = "sunstone", seed = 3166,
                terrainProfile = "pillar", depthScale = 2.82, tipLeanX = 2.2 },
            { id = "east-bough", name = "日向枝台", x = 72, z = 1,
                radius = 13, radiusX = 15, radiusZ = 10, groundY = 24.0,
                focusRadius = 54, focusY = 22.2, style = "warm-cliff", seed = 3227,
                terrainProfile = "needle", depthScale = 2.90, tipLeanX = 2.7 },
            { id = "upper-bough", name = "高云枝台", x = 52, z = 47,
                radius = 14, radiusX = 16, radiusZ = 11, groundY = 29.0,
                focusRadius = 58, focusY = 27.2, style = "warm-cliff", seed = 3288,
                terrainProfile = "pillar", depthScale = 3.00, tipLeanZ = 2.2 },
            { id = "tree-crown", name = "树冠天庭", x = 8, z = 24,
                radius = 15, radiusX = 16, radiusZ = 12, groundY = 34.0,
                focusRadius = 62, focusY = 32.0, style = "stone-crown", seed = 3349,
                terrainProfile = "pillar", depthScale = 3.15, tipLeanX = 0.8 },
        },
        bridges = {
            { id = "root-lower", from = "root-garden", to = "lower-bough",
                halfWidth = 1.72, maxStepHeight = 0.90, stepSpacing = 2.65,
                broken = true, style = "shattered-stepping-stones" },
            { id = "lower-west", from = "lower-bough", to = "west-bough",
                halfWidth = 1.55, maxStepHeight = 0.90, stepSpacing = 2.55,
                broken = true, style = "shattered-stepping-stones" },
            { id = "west-northwest", from = "west-bough", to = "northwest-bough",
                halfWidth = 1.48, maxStepHeight = 0.90, stepSpacing = 2.50,
                broken = true, style = "shattered-stepping-stones" },
            { id = "northwest-north", from = "northwest-bough", to = "north-bough",
                halfWidth = 1.42, maxStepHeight = 0.90, stepSpacing = 2.45,
                broken = true, style = "shattered-stepping-stones" },
            { id = "north-northeast", from = "north-bough", to = "northeast-bough",
                halfWidth = 1.38, maxStepHeight = 0.90, stepSpacing = 2.45,
                broken = true, style = "shattered-stepping-stones" },
            { id = "northeast-east", from = "northeast-bough", to = "east-bough",
                halfWidth = 1.34, maxStepHeight = 0.90, stepSpacing = 2.40,
                broken = true, style = "shattered-stepping-stones" },
            { id = "east-upper", from = "east-bough", to = "upper-bough",
                halfWidth = 1.30, maxStepHeight = 0.90, stepSpacing = 2.40,
                broken = true, style = "shattered-stepping-stones" },
            { id = "upper-crown", from = "upper-bough", to = "tree-crown",
                halfWidth = 1.34, maxStepHeight = 0.90, stepSpacing = 2.40,
                broken = true, style = "shattered-stepping-stones" },
        },
    },

    ["twin-vine-spiral"] = {
        id = "twin-vine-spiral",
        name = "双藤星树",
        description = "两道藤形浮岛交错攀向星辉冠台",
        groundY = 0.42,
        edgeInset = 0.38,
        pureTerrain = true,
        formation = "twin-vine-spiral",
        connectionStyle = "shattered-stepping-stones",
        overview = { x = 0, y = 8.5, z = 1, radius = 216 },
        camera = {
            theta = 0.75, phi = 0.88, radius = 216,
            target = { 0, 8.5, 1, x = 0, y = 8.5, z = 1 },
        },
        renderDistance = { skyRadius = 820, cameraFar = 1700 },
        islands = {
            { id = "vine-root", name = "双藤根庭", x = 0, z = 71,
                radius = 26, radiusX = 30, radiusZ = 21, groundY = -4.0,
                focusRadius = 80, focusY = -5.8, style = "stone-root", seed = 3411,
                terrainProfile = "sheer", depthScale = 2.00, tipLeanZ = 3.0 },
            { id = "west-sprout", name = "西藤初台", x = -51, z = 49,
                radius = 16, radiusX = 18, radiusZ = 13, groundY = 0.0,
                focusRadius = 60, focusY = -1.8, style = "cool-cliff", seed = 3472,
                terrainProfile = "shelf", depthScale = 2.08, tipLeanX = -2.0 },
            { id = "east-sprout", name = "东藤初台", x = 51, z = 49,
                radius = 16, radiusX = 18, radiusZ = 13, groundY = 2.0,
                focusRadius = 60, focusY = 0.2, style = "warm-cliff", seed = 3533,
                terrainProfile = "shelf", depthScale = 2.12, tipLeanX = 2.0 },
            { id = "west-turn", name = "西藤回台", x = -70, z = 7,
                radius = 14, radiusX = 16, radiusZ = 11, groundY = 5.0,
                focusRadius = 56, focusY = 3.2, style = "wind-cliff", seed = 3594,
                terrainProfile = "spire", depthScale = 2.35, tipLeanX = -2.5 },
            { id = "east-turn", name = "东藤回台", x = 70, z = 7,
                radius = 14, radiusX = 16, radiusZ = 11, groundY = 7.0,
                focusRadius = 56, focusY = 5.2, style = "sunstone", seed = 3655,
                terrainProfile = "spire", depthScale = 2.42, tipLeanX = 2.5 },
            { id = "west-climb", name = "西藤云阶", x = -48, z = -38,
                radius = 13, radiusX = 15, radiusZ = 10, groundY = 10.0,
                focusRadius = 54, focusY = 8.2, style = "stone", seed = 3716,
                terrainProfile = "pillar", depthScale = 2.62, tipLeanZ = -2.0 },
            { id = "east-climb", name = "东藤云阶", x = 48, z = -38,
                radius = 13, radiusX = 15, radiusZ = 10, groundY = 12.0,
                focusRadius = 54, focusY = 10.2, style = "stone-crown", seed = 3777,
                terrainProfile = "pillar", depthScale = 2.68, tipLeanZ = -2.0 },
            { id = "west-bloom", name = "西藤花台", x = -10, z = -65,
                radius = 13, radiusX = 15, radiusZ = 10, groundY = 15.0,
                focusRadius = 54, focusY = 13.2, style = "cool-cliff", seed = 3838,
                terrainProfile = "pillar", depthScale = 2.82, tipLeanZ = -2.4 },
            { id = "east-bloom", name = "东藤花台", x = 25, z = -64,
                radius = 12, radiusX = 14, radiusZ = 9, groundY = 17.0,
                focusRadius = 52, focusY = 15.2, style = "warm-cliff", seed = 3899,
                terrainProfile = "pillar", depthScale = 2.88, tipLeanZ = -2.4 },
            { id = "star-crown", name = "星辉冠台", x = 5, z = -19,
                radius = 17, radiusX = 19, radiusZ = 13, groundY = 24.0,
                focusRadius = 64, focusY = 22.0, style = "stone-crown", seed = 3960,
                terrainProfile = "pillar", depthScale = 3.05, tipLeanX = 0.5 },
        },
        bridges = {
            { id = "root-west", from = "vine-root", to = "west-sprout",
                halfWidth = 1.68, maxStepHeight = 0.92, stepSpacing = 2.65,
                broken = true, style = "shattered-stepping-stones" },
            { id = "root-east", from = "vine-root", to = "east-sprout",
                halfWidth = 1.68, maxStepHeight = 0.92, stepSpacing = 2.65,
                broken = true, style = "shattered-stepping-stones" },
            { id = "west-sprout-turn", from = "west-sprout", to = "west-turn",
                halfWidth = 1.50, maxStepHeight = 0.92, stepSpacing = 2.50,
                broken = true, style = "shattered-stepping-stones" },
            { id = "east-sprout-turn", from = "east-sprout", to = "east-turn",
                halfWidth = 1.50, maxStepHeight = 0.92, stepSpacing = 2.50,
                broken = true, style = "shattered-stepping-stones" },
            { id = "west-turn-climb", from = "west-turn", to = "west-climb",
                halfWidth = 1.40, maxStepHeight = 0.92, stepSpacing = 2.45,
                broken = true, style = "shattered-stepping-stones" },
            { id = "east-turn-climb", from = "east-turn", to = "east-climb",
                halfWidth = 1.40, maxStepHeight = 0.92, stepSpacing = 2.45,
                broken = true, style = "shattered-stepping-stones" },
            { id = "west-climb-bloom", from = "west-climb", to = "west-bloom",
                halfWidth = 1.34, maxStepHeight = 0.92, stepSpacing = 2.40,
                broken = true, style = "shattered-stepping-stones" },
            { id = "east-climb-bloom", from = "east-climb", to = "east-bloom",
                halfWidth = 1.34, maxStepHeight = 0.92, stepSpacing = 2.40,
                broken = true, style = "shattered-stepping-stones" },
            { id = "west-bloom-crown", from = "west-bloom", to = "star-crown",
                halfWidth = 1.36, maxStepHeight = 1.00, stepSpacing = 2.45,
                broken = true, style = "shattered-stepping-stones" },
            { id = "east-bloom-crown", from = "east-bloom", to = "star-crown",
                halfWidth = 1.36, maxStepHeight = 1.00, stepSpacing = 2.45,
                broken = true, style = "shattered-stepping-stones" },
        },
    },
}

local LEGACY_IDS = {
    ["storybook-triple-archipelago"] = IslandTerrainCatalog.DEFAULT_ID,
}

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
end

local RANDOM_PRESET_CACHE, RANDOM_PRESET_ORDER = {}, {}
local MAX_RANDOM_PRESET_CACHE = 64

local function CachedRandomPreset(terrainId)
    local cached = RANDOM_PRESET_CACHE[terrainId]
    if cached then return cached end
    cached = RandomTerrainGenerator.FromId(terrainId)
    if not cached then return nil end
    RANDOM_PRESET_CACHE[terrainId] = cached
    RANDOM_PRESET_ORDER[#RANDOM_PRESET_ORDER + 1] = terrainId
    if #RANDOM_PRESET_ORDER > MAX_RANDOM_PRESET_CACHE then
        local expiredId = table.remove(RANDOM_PRESET_ORDER, 1)
        RANDOM_PRESET_CACHE[expiredId] = nil
    end
    return cached
end

function IslandTerrainCatalog.ResolveId(terrainId)
    if type(terrainId) == "table" then
        terrainId = terrainId.terrainId or terrainId.id or terrainId.preset
    end
    local candidate = tostring(terrainId or "")
    candidate = LEGACY_IDS[candidate] or candidate
    if PRESETS[candidate] then return candidate end
    local randomSeed = RandomTerrainGenerator.SeedFromId(candidate)
    if randomSeed then return RandomTerrainGenerator.IdForSeed(randomSeed) end
    return IslandTerrainCatalog.DEFAULT_ID
end

function IslandTerrainCatalog.Get(terrainId)
    local metadata = type(terrainId) == "table" and terrainId or nil
    local resolved = IslandTerrainCatalog.ResolveId(terrainId)
    if PRESETS[resolved] then return Copy(PRESETS[resolved]) end
    local generated = Copy(CachedRandomPreset(resolved))
    if generated and metadata then
        if metadata.name ~= nil then generated.name = tostring(metadata.name) end
        if metadata.description ~= nil then generated.description = tostring(metadata.description) end
        generated.inUseCount = tonumber(metadata.inUseCount) or 0
        generated.active = metadata.active == true
        generated.createdAt = tonumber(metadata.createdAt) or 0
        generated.updatedAt = tonumber(metadata.updatedAt) or 0
    end
    return generated
end

function IslandTerrainCatalog.IsBuiltin(terrainId)
    if type(terrainId) == "table" then
        terrainId = terrainId.terrainId or terrainId.id or terrainId.preset
    end
    local candidate = tostring(terrainId or "")
    candidate = LEGACY_IDS[candidate] or candidate
    return PRESETS[candidate] ~= nil
end

function IslandTerrainCatalog.IsRandom(terrainId)
    return RandomTerrainGenerator.SeedFromId(terrainId) ~= nil
end

function IslandTerrainCatalog.RandomSeed(terrainId)
    return RandomTerrainGenerator.SeedFromId(terrainId)
end

function IslandTerrainCatalog.RandomIdForSeed(seed)
    return RandomTerrainGenerator.IdForSeed(seed)
end

function IslandTerrainCatalog.GenerateRandom(seed, options)
    return RandomTerrainGenerator.Generate(seed, options)
end

-- Pass a persisted random-terrain metadata list to append the user's own
-- deterministic terrains. Existing callers intentionally receive only the
-- authored catalog, preserving the old menu and tests byte-for-byte.
function IslandTerrainCatalog.List(customTerrains)
    local result = {}
    for _, terrainId in ipairs(ORDER) do
        local preset = PRESETS[terrainId]
        if preset then
            result[#result + 1] = {
                id = preset.id,
                name = preset.name,
                description = preset.description,
                islandCount = #preset.islands,
                default = preset.id == IslandTerrainCatalog.DEFAULT_ID,
            }
        end
    end
    local records = type(customTerrains) == "table" and customTerrains or {}
    if type(records.customTerrains) == "table" then records = records.customTerrains end
    local used = {}
    for _, record in ipairs(records) do
        local terrainId = IslandTerrainCatalog.ResolveId(record)
        if RandomTerrainGenerator.IsId(terrainId) and not used[terrainId] then
            local preset
            if record.name == nil or record.description == nil or record.islandCount == nil
                or record.formation == nil or record.seed == nil then
                preset = IslandTerrainCatalog.Get(record)
            end
            used[terrainId] = true
            result[#result + 1] = {
                id = terrainId,
                name = tostring(record.name or (preset and preset.name) or "随机地形"),
                description = tostring(record.description
                    or (preset and preset.description) or "确定性生成的纯地貌空岛"),
                islandCount = tonumber(record.islandCount)
                    or (preset and #preset.islands) or 0,
                generated = true,
                seed = tonumber(record.seed) or (preset and preset.seed),
                formation = record.formation or (preset and preset.formation),
                inUseCount = tonumber(record.inUseCount) or 0,
                active = record.active == true,
                default = false,
            }
        end
    end
    return result
end

return IslandTerrainCatalog
