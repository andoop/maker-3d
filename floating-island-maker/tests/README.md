# game124 logic regression tests

These tests exercise the pure model-asset, market, island-layout and persistence contracts without requiring the Maker renderer.

Run from the project root:

```bash
npx -y -p fengari-node-cli fengari tests/model_system_spec.lua
npx -y -p fengari-node-cli fengari tests/storage_spec.lua
npx -y -p fengari-node-cli fengari tests/island_project_store_spec.lua
npx -y -p fengari-node-cli fengari tests/island_terrain_spec.lua
npx -y -p fengari-node-cli fengari tests/island_picking_spec.lua
npx -y -p fengari-node-cli fengari tests/island_transform_gizmo_spec.lua
npx -y -p fengari-node-cli fengari tests/island_ui_theme_spec.lua
npx -y -p fengari-node-cli fengari tests/template_quality_spec.lua
npx -y -p fengari-node-cli fengari tests/day_night_spec.lua
npx -y -p fengari-node-cli fengari tests/storybook_island_spec.lua
```

The Maker Lua LSP and parser checks remain separate because they validate every runtime script rather than only the pure logic modules.
