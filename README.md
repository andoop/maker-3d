# Maker 3D

这个仓库集中保存两套可以独立使用的 3D 创作项目。

| 目录 | 项目 | 说明 |
| --- | --- | --- |
| [`threejs-workbench/`](./threejs-workbench/) | Three.js 模型工作台 | 浏览器版积木模型编辑器，支持多形状、多材质、精确变换、模型库以及 JSON 导入导出。 |
| [`floating-island-maker/`](./floating-island-maker/) | 我的空岛 | TapTap Maker 完整项目，包含空岛建设、模型工作台、模型市场、探索与第一人称漫游。 |

## 快速开始

### Three.js 模型工作台

```bash
cd threejs-workbench
python3 -m http.server 8080
```

然后访问 <http://127.0.0.1:8080/>。不要直接双击 `index.html`，因为浏览器会限制模型库 JSON 的本地文件读取。

### 我的空岛

`floating-island-maker/` 保留了完整 Maker 工程结构。使用 TapTap Maker 打开该目录即可继续开发；项目的模块说明、操作方式和验证信息见其 [`README.md`](./floating-island-maker/README.md)。

## 两个项目之间的数据关系

- Three.js 工作台使用与“我的空岛”一致的模型 JSON v3 数据结构，可以互相导入、导出。
- 浏览器工作台的内置模型库来自 `floating-island-maker/scripts/BuiltinTemplates.lua`。
- 更新 Maker 内置模型后，可在 `threejs-workbench/` 中重新生成浏览器模型库：

```bash
lua generate-model-library.lua ../floating-island-maker model-library.json
```
