-- A deliberately small first-load composition. The third island stays open so
-- the player has an obvious building destination and mobile startup stays well
-- below the authored model-node budget.

local DefaultIslandModels = {
    BLOCK_BUDGET = 180,
    SHADOW_BUDGET = 90,
    MODELS = {
        { assetId = "builtin:compose:sunny-meadow-cottage", x = 0, z = -16, rotation = 0, scale = 1.0 },
    },
}

return DefaultIslandModels
