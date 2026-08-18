import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { TransformControls } from "three/addons/controls/TransformControls.js";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";

const $ = (id) => document.getElementById(id);
const viewport = $("viewport");
const statusEl = $("status");
const selectionBadge = $("selectionBadge");
const referenceOverlay = $("referenceOverlay");
const contextDock = document.querySelector(".context-dock");
const selectionHud = document.querySelector(".selection-hud");
const ui = {
  newSizeX: $("newSizeX"), newSizeY: $("newSizeY"), newSizeZ: $("newSizeZ"), newColor: $("newColor"),
  snapSize: $("snapSize"), objectCount: $("objectCount"), objectList: $("objectList"),
  noSelection: $("noSelection"), inspector: $("inspector"), selectedName: $("selectedName"),
  posX: $("posX"), posY: $("posY"), posZ: $("posZ"), sizeX: $("sizeX"), sizeY: $("sizeY"), sizeZ: $("sizeZ"),
  rotX: $("rotX"), rotY: $("rotY"), rotZ: $("rotZ"), selectedColor: $("selectedColor"),
  newShapes: $("newShapes"), selectedShapes: $("selectedShapes"),
  newMaterials: $("newMaterials"), selectedMaterials: $("selectedMaterials"),
  templateSummary: $("templateSummary"), templateCategories: $("templateCategories"), templateList: $("templateList"),
  duplicateQuick: $("duplicateQuick"), undo: $("undo"), redo: $("redo"),
};

const THEME_SATURATION = 1.24;
function saturateHex(hex, factor = THEME_SATURATION) {
  const channels = [1, 3, 5].map((start) => Number.parseInt(hex.slice(start, start + 2), 16));
  const gray = channels[0] * 0.299 + channels[1] * 0.587 + channels[2] * 0.114;
  return `#${channels.map((value) => Math.max(0, Math.min(255, Math.round(gray + (value - gray) * factor))).toString(16).padStart(2, "0")).join("")}`;
}
const THEME_MODEL = Object.fromEntries(Object.entries({
  plaster: "#f2e7cf", cloud: "#f7f1e3", grass: "#86b85a", leaf: "#5d9861", moss: "#6f8a50",
  earth: "#a86e4f", stone: "#899399", brick: "#ba674e", roofTile: "#c96f5d", pavement: "#9ca097",
  asphalt: "#5b6468", snow: "#eff2e8", glass: "#b2dada",
}).map(([key, value]) => [key, saturateHex(value)]));
const PALETTE = [
  "#f2e7cf", "#dcc49a", "#86b85a", "#5d9861", "#3f6e62", "#6f8a50",
  "#78b9d2", "#5eafc2", "#597993", "#3e536c", "#a86e4f", "#8b6248",
  "#5c463a", "#899399", "#b8b8aa", "#59646b", "#c96f5d", "#d98a86",
  "#88779b", "#d9b95f", "#c78a50", "#b38a52", "#8bd2cc", "#f7f1e3",
].map((color) => saturateHex(color));
const PRESETS = {
  story_cube: [1, 1, 1], half: [0.5, 0.5, 0.5], detail: [0.25, 0.25, 0.25], micro: [0.12, 0.12, 0.12],
  slab: [1, 0.22, 1], step: [1, 0.35, 0.65], trim: [1, 0.12, 0.12], beam: [2, 0.22, 0.22],
  wall: [2, 2, 0.25], low_wall: [2, 0.75, 0.35], column: [0.45, 2, 0.45], terrain: [2, 1, 2],
};
const SHAPES = [
  { id: "box", name: "圆角砖块", icon: "▣" },
  { id: "sphere", name: "软团球", icon: "●" },
  { id: "cylinder", name: "原木圆柱", icon: "◉" },
  { id: "cone", name: "尖顶圆锥", icon: "▲" },
  { id: "tri_prism", name: "屋顶斜块", icon: "◭" },
  { id: "pyramid", name: "塔顶方锥", icon: "◆" },
  { id: "tetra", name: "晶体尖块", icon: "◈" },
  { id: "torus", name: "遗迹圆环", icon: "○" },
];
const MATERIALS = [
  { id: "solid", name: "暖雾灰泥", preview: saturateHex("#f2e7cf") },
  { id: "painted_wood", name: "磨旧彩木", preview: saturateHex("#ab7d56") },
  { id: "wood", name: "蜂蜜原木", preview: saturateHex("#8b6248") },
  { id: "grass", name: "手绘风丘草", preview: saturateHex("#86b85a") },
  { id: "leaf", name: "团簇叶片", preview: saturateHex("#5d9861") },
  { id: "moss", name: "潮润苔石", preview: saturateHex("#6f8a50") },
  { id: "earth", name: "暖陶土层", preview: saturateHex("#a86e4f") },
  { id: "stone", name: "圆润雨岩", preview: saturateHex("#899399") },
  { id: "brick", name: "手绘砖块纹", preview: saturateHex("#ba674e") },
  { id: "ruin_stone", name: "风化乱石墙", preview: saturateHex("#9da4a2") },
  { id: "old_brick", name: "残旧红砖墙", preview: saturateHex("#be7d62") },
  { id: "carved_stone", name: "古代雕纹石", preview: saturateHex("#c2beab") },
  { id: "overgrown_stone", name: "荒草苔蚀石", preview: saturateHex("#849a6f") },
  { id: "roof_tile", name: "陶瓦鱼鳞纹", preview: saturateHex("#c96f5d") },
  { id: "pavement", name: "广场石板纹", preview: saturateHex("#9ca097") },
  { id: "asphalt", name: "雾灰道路面", preview: saturateHex("#5b6468") },
  { id: "snow", name: "柔雪粉刷", preview: saturateHex("#eff2e8") },
  { id: "marble", name: "日晒古石", preview: saturateHex("#b8b8aa") },
  { id: "sand", name: "燕麦细沙", preview: saturateHex("#d3b87e") },
  { id: "water", name: "雾蓝溪水", preview: saturateHex("#5eafc2"), transparent: true },
  { id: "glass", name: "雾蓝手作玻璃", preview: saturateHex("#b2dada"), transparent: true },
  { id: "crystal", name: "薄荷晶石", preview: saturateHex("#8bd2cc"), transparent: true },
  { id: "ceramic", name: "窑烧陶器", preview: saturateHex("#be6f53") },
  { id: "fabric", name: "亚麻软布", preview: saturateHex("#d19c94") },
  { id: "metal", name: "锤纹黄铜", preview: saturateHex("#7e7058") },
  { id: "glow", name: "灯芯柔光", preview: saturateHex("#e0c470") },
  { id: "fire", name: "壁炉余烬", preview: saturateHex("#db7441"), transparent: true },
];
const STORAGE_KEY = "island-3d-workbench-v3";

let mode = "select";
let transformMode = null;
let selected = null;
let nextId = 1;
let objects = [];
let history = [];
let future = [];
let transformStartSnapshot = null;
let inspectorStartSnapshot = null;
let focusAnimation = null;
let activePanel = "properties";
let mobileDockOpen = false;
let referenceVisible = false;
let newShapeId = "box";
let newMaterialId = "solid";
let templateLibrary = [];
let templateLibraryBlocks = 0;
let templateCategory = "全部";

const scene = new THREE.Scene();
scene.background = null;
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.NoToneMapping;
viewport.prepend(renderer.domElement);

const camera = new THREE.PerspectiveCamera(36, 1, 0.05, 300);
camera.position.set(13, 11, 15);
const orbit = new OrbitControls(camera, renderer.domElement);
orbit.enableDamping = true;
orbit.dampingFactor = 0.08;
orbit.target.set(0, 2.5, 0);

const transform = new TransformControls(camera, renderer.domElement);
transform.setMode("translate");
transform.setSize(0.8);
scene.add(transform.getHelper());
transform.addEventListener("dragging-changed", (event) => { orbit.enabled = !event.value; });
transform.addEventListener("mouseDown", () => { transformStartSnapshot = snapshot(); });
transform.addEventListener("objectChange", () => {
  if (!selected) return;
  syncRecordFromMesh(selected);
  updateInspector();
  updateSelectionHelper();
});
transform.addEventListener("mouseUp", () => {
  if (transformStartSnapshot) {
    history.push(transformStartSnapshot);
    if (history.length > 60) history.shift();
    transformStartSnapshot = null;
    future = [];
    snapSelectedTransform();
    commit("已调整积木");
  }
});

scene.add(new THREE.HemisphereLight(0xffffff, 0x8fa6ad, 2.1));
const sun = new THREE.DirectionalLight(0xfff8ea, 3.3);
sun.position.set(-8, 16, 11);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -18, right: 18, top: 18, bottom: -18, near: 0.1, far: 50 });
scene.add(sun);
const fill = new THREE.DirectionalLight(0x9bdcff, 0.55);
fill.position.set(10, 7, -12);
scene.add(fill);

const grid = new THREE.GridHelper(32, 64, 0x6e9cac, 0xb7d0d6);
grid.material.transparent = true;
grid.material.opacity = 0.58;
scene.add(grid);
const ground = new THREE.Mesh(
  new THREE.PlaneGeometry(80, 80),
  new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false, side: THREE.DoubleSide }),
);
ground.rotation.x = -Math.PI / 2;
ground.name = "__ground";
scene.add(ground);

const selectionHelper = new THREE.BoxHelper(new THREE.Mesh(), 0xffa92f);
selectionHelper.visible = false;
selectionHelper.material.depthTest = false;
selectionHelper.renderOrder = 20;
scene.add(selectionHelper);

const geometryCache = new Map();
const materialCache = new Map();

function triangularPrismGeometry() {
  const vertices = [
    [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0, 0.5, -0.5],
    [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [0, 0.5, 0.5],
  ];
  const triangles = [
    [0, 2, 1], [3, 4, 5], [0, 1, 4], [0, 4, 3],
    [1, 2, 5], [1, 5, 4], [2, 0, 3], [2, 3, 5],
  ];
  const positions = [], uvs = [];
  for (const triangle of triangles) {
    triangle.forEach((index, vertexIndex) => {
      positions.push(...vertices[index]);
      uvs.push(...([[0, 0], [1, 0], [0.5, 1]][vertexIndex]));
    });
  }
  const result = new THREE.BufferGeometry();
  result.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  result.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
  result.computeVertexNormals();
  return result;
}

function geometryFor(shapeId) {
  const id = SHAPES.some((shape) => shape.id === shapeId) ? shapeId : "box";
  if (geometryCache.has(id)) return geometryCache.get(id);
  let geometry;
  if (id === "sphere") geometry = new THREE.SphereGeometry(0.5, 24, 16);
  else if (id === "cylinder") geometry = new THREE.CylinderGeometry(0.5, 0.5, 1, 24, 1, false);
  else if (id === "cone") geometry = new THREE.ConeGeometry(0.5, 1, 24, 1, false);
  else if (id === "tri_prism") geometry = triangularPrismGeometry();
  else if (id === "pyramid") {
    geometry = new THREE.ConeGeometry(Math.SQRT1_2, 1, 4, 1, false);
    geometry.rotateY(Math.PI / 4);
  } else if (id === "tetra") geometry = new THREE.TetrahedronGeometry(0.64, 0);
  else if (id === "torus") geometry = new THREE.TorusGeometry(0.36, 0.14, 12, 32);
  else geometry = new RoundedBoxGeometry(1, 1, 1, 2, 0.018);
  geometry.computeBoundingBox();
  geometryCache.set(id, geometry);
  return geometry;
}

function materialSpec(materialId) {
  return MATERIALS.find((material) => material.id === materialId) || MATERIALS[0];
}

function hexChannels(hex) {
  const normalized = /^#[0-9a-f]{6}$/i.test(hex || "") ? hex : "#f5f1e8";
  return [1, 3, 5].map((start) => Number.parseInt(normalized.slice(start, start + 2), 16));
}

function mixHex(base, tint, amount) {
  const a = hexChannels(base), b = hexChannels(tint);
  return `#${a.map((value, index) => Math.round(value + (b[index] - value) * amount).toString(16).padStart(2, "0")).join("")}`;
}

function patternTexture(materialId) {
  const key = `texture:${materialId}`;
  if (materialCache.has(key)) return materialCache.get(key);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 64;
  const context = canvas.getContext("2d");
  const textureBases = {
    solid: "#f5efdf", painted_wood: "#e8ddcb", wood: "#8b6248",
    grass: "#86b85a", leaf: "#5d9861", moss: "#6f8a50",
    earth: "#bd845e", stone: "#b8b6b0", brick: "#ba674e",
    ruin_stone: "#9da4a2", old_brick: "#bd7d63", carved_stone: "#c2beab",
    overgrown_stone: "#849a70", roof_tile: "#c96f5d", pavement: "#a4a79f",
    asphalt: "#5b6468", snow: "#f1f3ed", marble: "#cac9bd",
    sand: "#dbc99f", water: "#5eafc2", glass: "#c7e5e2",
    crystal: "#a8ddd8", ceramic: "#c98768", fabric: "#d7b8aa",
    metal: "#a99776", glow: "#ead39a", fire: "#db7441",
  };
  context.fillStyle = textureBases[materialId] || "#f5efdf";
  context.fillRect(0, 0, 64, 64);
  const noise = (x, y, seed = 0) => {
    const value = Math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453;
    return value - Math.floor(value);
  };
  const speckles = (count, alpha = 0.12, light = false) => {
    for (let i = 0; i < count; i += 1) {
      const x = Math.floor(noise(i, 7, materialId.length) * 64);
      const y = Math.floor(noise(i, 19, materialId.length + 3) * 64);
      const shade = light ? 255 : Math.floor(75 + noise(i, 31, 9) * 90);
      context.fillStyle = `rgba(${shade},${shade},${shade},${alpha})`;
      context.fillRect(x, y, noise(i, 43, 2) > 0.8 ? 2 : 1, 1);
    }
  };
  const line = (x1, y1, x2, y2, color, width = 1) => {
    context.strokeStyle = color; context.lineWidth = width; context.beginPath(); context.moveTo(x1, y1); context.lineTo(x2, y2); context.stroke();
  };

  if (["wood", "painted_wood"].includes(materialId)) {
    for (let x = 5; x < 64; x += 9) line(x, 0, x + Math.sin(x) * 2, 64, "rgba(65,42,25,.28)", 1.4);
    for (let y = 8; y < 64; y += 18) line(0, y, 64, y + 2, "rgba(255,255,255,.13)");
  } else if (["grass", "leaf", "moss"].includes(materialId)) {
    speckles(180, 0.18);
    for (let i = 0; i < 24; i += 1) {
      const x = noise(i, 4, 5) * 64, y = noise(i, 8, 7) * 64;
      line(x, y + 4, x + (noise(i, 9, 8) - 0.5) * 4, y - 4, "rgba(35,70,34,.27)");
    }
  } else if (materialId === "earth" || materialId === "sand") {
    for (let y = 6; y < 64; y += materialId === "earth" ? 9 : 13) line(0, y, 64, y + Math.sin(y) * 2, "rgba(80,55,35,.18)");
    speckles(140, 0.16, materialId === "sand");
  } else if (["brick", "old_brick", "roof_tile"].includes(materialId)) {
    const rowHeight = materialId === "roof_tile" ? 10 : 8;
    for (let y = 0, row = 0; y < 64; y += rowHeight, row += 1) {
      line(0, y, 64, y, "rgba(75,55,45,.34)");
      for (let x = (row % 2) * 8; x < 64; x += 16) line(x, y, x, y + rowHeight, "rgba(75,55,45,.30)");
      if (materialId === "roof_tile") {
        for (let x = (row % 2) * 8; x < 64; x += 16) {
          context.strokeStyle = "rgba(75,55,45,.26)"; context.beginPath(); context.arc(x + 8, y + 2, 7, 0, Math.PI); context.stroke();
        }
      }
    }
    speckles(90, 0.12);
  } else if (["stone", "ruin_stone", "carved_stone", "overgrown_stone", "pavement"].includes(materialId)) {
    const cell = materialId === "carved_stone" ? 20 : materialId === "pavement" ? 16 : 14;
    for (let y = 0, row = 0; y < 64; y += cell, row += 1) {
      line(0, y, 64, y, "rgba(68,70,67,.30)", 1.5);
      for (let x = (row % 2) * (cell / 2); x < 64; x += cell) line(x, y, x, Math.min(64, y + cell), "rgba(68,70,67,.25)");
    }
    if (materialId === "carved_stone") {
      for (let y = 10; y < 64; y += 20) for (let x = 10; x < 64; x += 20) { context.strokeStyle = "rgba(70,65,55,.28)"; context.strokeRect(x - 4, y - 4, 8, 8); }
    }
    if (materialId === "overgrown_stone") {
      context.fillStyle = "rgba(64,98,49,.32)"; context.fillRect(0, 0, 64, 7); context.fillRect(11, 0, 5, 28); context.fillRect(42, 0, 4, 18);
    }
    speckles(120, 0.13);
  } else if (materialId === "asphalt") {
    speckles(360, 0.22, true);
  } else if (materialId === "snow" || materialId === "solid") {
    speckles(materialId === "snow" ? 160 : 90, 0.10, true);
  } else if (materialId === "marble") {
    for (let i = -20; i < 80; i += 17) {
      context.strokeStyle = "rgba(82,91,96,.22)"; context.lineWidth = 1.4; context.beginPath();
      for (let y = 0; y <= 64; y += 4) {
        const x = i + y * 0.55 + Math.sin(y * 0.22 + i) * 4;
        if (y === 0) context.moveTo(x, y); else context.lineTo(x, y);
      }
      context.stroke();
    }
  } else if (materialId === "water") {
    const gradient = context.createLinearGradient(0, 0, 64, 64); gradient.addColorStop(0, "#7fd2db"); gradient.addColorStop(1, "#397f9f"); context.fillStyle = gradient; context.fillRect(0, 0, 64, 64);
    for (let y = 5; y < 64; y += 9) {
      context.strokeStyle = "rgba(235,255,255,.44)"; context.beginPath();
      for (let x = 0; x <= 64; x += 4) {
        const waveY = y + Math.sin(x * 0.22 + y) * 2;
        if (x === 0) context.moveTo(x, waveY); else context.lineTo(x, waveY);
      }
      context.stroke();
    }
  } else if (["glass", "crystal"].includes(materialId)) {
    for (let i = -32; i < 96; i += 16) line(i, 64, i + 64, 0, "rgba(255,255,255,.32)", 2);
    speckles(50, 0.13, true);
  } else if (materialId === "ceramic") {
    speckles(110, 0.12);
    context.fillStyle = "rgba(255,255,255,.28)"; context.fillRect(8, 0, 5, 64);
  } else if (materialId === "fabric") {
    for (let i = 0; i < 64; i += 4) { line(i, 0, i, 64, "rgba(80,70,55,.17)"); line(0, i, 64, i, "rgba(255,255,255,.14)"); }
  } else if (materialId === "metal") {
    speckles(190, 0.18, true);
    for (let x = 8; x < 64; x += 16) for (let y = 8; y < 64; y += 16) { context.strokeStyle = "rgba(55,45,30,.25)"; context.strokeRect(x - 4, y - 4, 8, 8); }
  } else if (materialId === "glow") {
    const gradient = context.createRadialGradient(32, 32, 2, 32, 32, 44); gradient.addColorStop(0, "#ffffff"); gradient.addColorStop(.45, "#f7e8a0"); gradient.addColorStop(1, "#b7a05d"); context.fillStyle = gradient; context.fillRect(0, 0, 64, 64);
  } else if (materialId === "fire") {
    const gradient = context.createLinearGradient(0, 64, 0, 0); gradient.addColorStop(0, "#6b160d"); gradient.addColorStop(.45, "#f05219"); gradient.addColorStop(.8, "#ffcf51"); gradient.addColorStop(1, "#fff2bd"); context.fillStyle = gradient; context.fillRect(0, 0, 64, 64);
    for (let x = 2; x < 64; x += 8) { context.fillStyle = "rgba(255,255,220,.35)"; context.beginPath(); context.ellipse(x, 38 + Math.sin(x) * 8, 4, 19, .2, 0, Math.PI * 2); context.fill(); }
  } else {
    speckles(120, 0.12);
  }

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.magFilter = THREE.LinearFilter;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  materialCache.set(key, texture);
  return texture;
}

function materialFor(materialId, color) {
  const spec = materialSpec(materialId);
  const safeColor = /^#[0-9a-f]{6}$/i.test(color || "") ? color.toLowerCase() : "#f5f1e8";
  const key = `${spec.id}:${safeColor}`;
  if (!materialCache.has(key)) {
    const options = { color: safeColor, map: patternTexture(spec.id), roughness: 0.9, metalness: 0 };
    if (spec.id === "water") Object.assign(options, {
      color: mixHex(THEME_MODEL.cloud, safeColor, 0.34), roughness: 0.22,
      transparent: true, opacity: 0.76, depthWrite: false,
    });
    else if (spec.id === "fire") Object.assign(options, {
      color: mixHex("#ffffff", safeColor, 0.20), emissiveMap: patternTexture("fire"),
      emissive: "#d98244", emissiveIntensity: 1.05, roughness: 0.38,
      transparent: true, opacity: 1, side: THREE.DoubleSide, depthWrite: false,
    });
    else if (spec.id === "wood" || spec.id === "painted_wood") Object.assign(options, {
      color: mixHex(spec.id === "painted_wood" ? THEME_MODEL.plaster : THEME_MODEL.cloud,
        safeColor, spec.id === "painted_wood" ? 0.58 : 0.42),
      roughness: spec.id === "painted_wood" ? 0.78 : 0.88,
    });
    else if (spec.id === "marble") Object.assign(options, {
      color: mixHex(THEME_MODEL.cloud, safeColor, 0.36), roughness: 0.46, metalness: 0.01,
    });
    else if (spec.id === "glass" || spec.id === "crystal") {
      const crystalColor = mixHex(THEME_MODEL.glass, safeColor, 0.55);
      Object.assign(options, {
        color: crystalColor, emissive: spec.id === "crystal" ? crystalColor : "#000000",
        emissiveIntensity: spec.id === "crystal" ? 0.28 : 0,
        roughness: spec.id === "crystal" ? 0.16 : 0.24, metalness: 0.02,
        transparent: true, opacity: spec.id === "crystal" ? 0.78 : 0.5,
        side: THREE.DoubleSide, depthWrite: false,
      });
    } else if (["grass", "leaf", "moss"].includes(spec.id)) Object.assign(options, {
      color: mixHex(spec.id === "moss" ? "#d8d5b4" : THEME_MODEL.cloud,
        safeColor, spec.id === "grass" ? 0.34 : 0.46),
      roughness: spec.id === "moss" ? 0.98 : 0.94,
    });
    else if (spec.id === "sand" || spec.id === "earth") Object.assign(options, {
      color: mixHex(spec.id === "earth" ? "#d9b28d" : THEME_MODEL.cloud,
        safeColor, spec.id === "earth" ? 0.46 : 0.34),
      roughness: spec.id === "earth" ? 0.95 : 0.92,
    });
    else if (spec.id === "stone") Object.assign(options, {
      color: mixHex(THEME_MODEL.cloud, safeColor, 0.40), roughness: 0.92, metalness: 0.01,
    });
    else if (["ruin_stone", "old_brick", "carved_stone", "overgrown_stone"].includes(spec.id)) {
      const bases = { ruin_stone: "#9da4a2", old_brick: "#bd7d63", carved_stone: "#c2beab", overgrown_stone: "#849a70" };
      Object.assign(options, {
        color: mixHex(bases[spec.id], safeColor, spec.id === "overgrown_stone" ? 0.30 : 0.38),
        roughness: spec.id === "carved_stone" ? 0.91 : 0.97,
      });
    } else if (["brick", "roof_tile", "pavement", "asphalt", "snow"].includes(spec.id)) {
      const bases = { brick: THEME_MODEL.brick, roof_tile: THEME_MODEL.roofTile, pavement: THEME_MODEL.pavement, asphalt: THEME_MODEL.asphalt, snow: THEME_MODEL.snow };
      Object.assign(options, {
        color: mixHex(bases[spec.id], safeColor, spec.id === "snow" ? 0.26 : 0.42),
        roughness: spec.id === "asphalt" ? 0.97 : spec.id === "snow" ? 0.84 : 0.88,
      });
    } else if (spec.id === "metal") Object.assign(options, {
      color: mixHex("#c7b99d", safeColor, 0.48), roughness: 0.52, metalness: 0.52,
    });
    else if (spec.id === "ceramic") Object.assign(options, {
      color: mixHex(THEME_MODEL.plaster, safeColor, 0.62), roughness: 0.38, metalness: 0.01,
    });
    else if (spec.id === "fabric") Object.assign(options, {
      color: mixHex(THEME_MODEL.cloud, safeColor, 0.62), roughness: 1,
    });
    else if (spec.id === "glow") {
      const glowColor = mixHex("#ead39a", safeColor, 0.48);
      Object.assign(options, { color: glowColor, emissive: glowColor, emissiveIntensity: 0.72, roughness: 0.58 });
    }
    materialCache.set(key, new THREE.MeshStandardMaterial(options));
  }
  return materialCache.get(key);
}

function refreshCatalogButtons() {
  ui.newShapes.querySelectorAll("[data-shape]").forEach((button) => button.classList.toggle("active", button.dataset.shape === newShapeId));
  ui.newMaterials.querySelectorAll("[data-material]").forEach((button) => button.classList.toggle("active", button.dataset.material === newMaterialId));
  ui.selectedShapes.querySelectorAll("[data-shape]").forEach((button) => button.classList.toggle("active", Boolean(selected) && button.dataset.shape === selected.shapeId));
  ui.selectedMaterials.querySelectorAll("[data-material]").forEach((button) => button.classList.toggle("active", Boolean(selected) && button.dataset.material === selected.materialId));
}

function setSelectedShape(shapeId) {
  if (!selected || selected.shapeId === shapeId) return;
  pushHistory();
  selected.shapeId = shapeId;
  selected.mesh.geometry = geometryFor(shapeId);
  updateSelectionHelper();
  refreshCatalogButtons();
  commit(`已应用${SHAPES.find((shape) => shape.id === shapeId)?.name || "形状"}`);
}

function setSelectedMaterial(materialId) {
  if (!selected || selected.materialId === materialId) return;
  pushHistory();
  selected.materialId = materialId;
  selected.mesh.material = materialFor(materialId, selected.color);
  selected.mesh.castShadow = !materialSpec(materialId).transparent;
  refreshCatalogButtons();
  commit(`已应用${materialSpec(materialId).name}材质`);
}

function createCatalogButton(item, kind, target) {
  const button = document.createElement("button");
  button.className = "choice-button";
  button.dataset[kind] = item.id;
  const preview = kind === "shape"
    ? `<span class="shape-icon">${item.icon}</span>`
    : `<span class="preview" style="--preview:${item.preview};background-image:linear-gradient(135deg,rgba(255,255,255,.42),transparent 48%,rgba(22,52,62,.18))"></span>`;
  button.innerHTML = `${preview}<span>${item.name}</span>`;
  button.addEventListener("click", () => {
    if (target === "new") {
      if (kind === "shape") newShapeId = item.id;
      else newMaterialId = item.id;
      refreshCatalogButtons();
      setStatus(`新积木已切换为${item.name}`);
    } else if (kind === "shape") setSelectedShape(item.id);
    else setSelectedMaterial(item.id);
  });
  return button;
}

function buildCatalogControls() {
  SHAPES.forEach((shape) => {
    ui.newShapes.appendChild(createCatalogButton(shape, "shape", "new"));
    ui.selectedShapes.appendChild(createCatalogButton(shape, "shape", "selected"));
  });
  MATERIALS.forEach((material) => {
    ui.newMaterials.appendChild(createCatalogButton(material, "material", "new"));
    ui.selectedMaterials.appendChild(createCatalogButton(material, "material", "selected"));
  });
  refreshCatalogButtons();
}

const TEMPLATE_CATEGORY_ICONS = {
  "树木单件": "♣", "植被单件": "✿", "可进入建筑": "⌂", "飞行器": "✈",
  "围栏构件": "╫", "街景设施": "♟", "组合构件": "▦", "遗迹构件": "♜",
  "山体构件": "▲", "传送机关": "◎",
};

function templateColors(template) {
  const result = [];
  for (const block of template.blocks || []) {
    const color = /^#[0-9a-f]{6}$/i.test(block.color || "") ? block.color : null;
    if (color && !result.includes(color)) result.push(color);
    if (result.length >= 2) break;
  }
  return [result[0] || "#78b9d2", result[1] || "#f2e7cf"];
}

function renderTemplateLibrary() {
  const categoryCounts = new Map();
  for (const template of templateLibrary) categoryCounts.set(template.category, (categoryCounts.get(template.category) || 0) + 1);
  ui.templateSummary.textContent = `${templateLibrary.length} 模型 · ${templateLibraryBlocks} 组件`;
  ui.templateCategories.replaceChildren();
  const categories = ["全部", ...categoryCounts.keys()];
  for (const category of categories) {
    const button = document.createElement("button");
    const count = category === "全部" ? templateLibrary.length : categoryCounts.get(category);
    button.textContent = `${category} ${count}`;
    button.classList.toggle("active", category === templateCategory);
    button.addEventListener("click", () => {
      templateCategory = category;
      renderTemplateLibrary();
    });
    ui.templateCategories.appendChild(button);
  }

  const filtered = templateCategory === "全部"
    ? templateLibrary
    : templateLibrary.filter((template) => template.category === templateCategory);
  ui.templateList.replaceChildren();
  if (!filtered.length) {
    const empty = document.createElement("div");
    empty.className = "template-empty";
    empty.textContent = "这个分类暂时没有模型";
    ui.templateList.appendChild(empty);
    return;
  }
  for (const template of filtered) {
    const colors = templateColors(template);
    const card = document.createElement("article");
    card.className = "template-card";
    card.dataset.templateId = template.id;

    const preview = document.createElement("div");
    preview.className = "template-preview";
    preview.style.setProperty("--preview-a", colors[0]);
    preview.style.setProperty("--preview-b", colors[1]);
    preview.textContent = TEMPLATE_CATEGORY_ICONS[template.category] || "◆";
    const count = document.createElement("small");
    count.textContent = String(template.blocks?.length || 0);
    preview.appendChild(count);

    const copy = document.createElement("div");
    copy.className = "template-copy";
    const title = document.createElement("div");
    title.className = "template-title";
    title.textContent = template.name || "未命名模型";
    const meta = document.createElement("div");
    meta.className = "template-meta";
    meta.textContent = `${template.category || "模型"} · ${template.blocks?.length || 0} 组件`;
    const description = document.createElement("div");
    description.className = "template-description";
    description.textContent = template.description || "可直接插入并继续拆分编辑";
    copy.append(title, meta, description);

    const insert = document.createElement("button");
    insert.textContent = "插入";
    insert.title = `插入 ${template.name}`;
    insert.addEventListener("click", () => insertTemplate(template));
    card.append(preview, copy, insert);
    ui.templateList.appendChild(card);
  }
}

async function loadTemplateLibrary() {
  try {
    const response = await fetch("./model-library.json?v=30");
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const payload = await response.json();
    if (!Array.isArray(payload.models)) throw new Error("缺少 models 数组");
    templateLibrary = payload.models;
    templateLibraryBlocks = Number(payload.blockCount) || templateLibrary.reduce((sum, template) => sum + (template.blocks?.length || 0), 0);
    renderTemplateLibrary();
  } catch (error) {
    ui.templateSummary.textContent = "模型库读取失败";
    ui.templateList.replaceChildren();
    const empty = document.createElement("div");
    empty.className = "template-empty";
    empty.textContent = `请通过本地服务器打开工作台 · ${String(error.message || error)}`;
    ui.templateList.appendChild(empty);
  }
}

function setStatus(text) { statusEl.textContent = text; }
function cleanNumber(value) { return Math.round(Number(value) * 1000) / 1000; }
function snapStep() { return Number(ui.snapSize.value); }
function snapValue(value, step = snapStep()) { return step ? Math.round(value / step) * step : value; }
function newBlockSize() {
  return [ui.newSizeX, ui.newSizeY, ui.newSizeZ].map((input) => Math.max(0.05, Number(input.value) || 1));
}

function normalizeSpec(spec) {
  const position = spec.position || [spec.x, spec.y, spec.z];
  const size = spec.size || [spec.sx, spec.sy, spec.sz];
  const rotation = spec.rotation || [spec.rx, spec.ry, spec.rz];
  const id = Number(spec.id) || nextId++;
  const numberOr = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  return {
    id,
    name: spec.name || `积木 ${id}`,
    type: spec.type || "block",
    position: [numberOr(position[0], 0), numberOr(position[1], 0.5), numberOr(position[2], 0)],
    size: [size[0], size[1], size[2]].map((n) => Math.max(0.05, numberOr(n, 1))),
    rotation: [numberOr(rotation[0], 0), numberOr(rotation[1], 0), numberOr(rotation[2], 0)],
    color: spec.color || "#f5f1e8",
    materialId: materialSpec(spec.materialId || spec.material).id,
    shapeId: SHAPES.some((shape) => shape.id === (spec.shapeId || spec.shape)) ? (spec.shapeId || spec.shape) : "box",
  };
}

function createRecord(spec) {
  const record = normalizeSpec(spec);
  nextId = Math.max(nextId, record.id + 1);
  const mesh = new THREE.Mesh(geometryFor(record.shapeId), materialFor(record.materialId, record.color));
  mesh.position.fromArray(record.position);
  mesh.scale.fromArray(record.size);
  mesh.rotation.set(...record.rotation);
  mesh.castShadow = !materialSpec(record.materialId).transparent;
  mesh.receiveShadow = true;
  mesh.userData.recordId = record.id;
  record.mesh = mesh;
  objects.push(record);
  scene.add(mesh);
  return record;
}

function removeRecord(record) {
  if (!record) return;
  if (selected === record) selectRecord(null);
  scene.remove(record.mesh);
  objects = objects.filter((item) => item !== record);
}

function serializeRecord(record) {
  syncRecordFromMesh(record);
  return {
    id: record.id, name: record.name, type: record.type,
    position: record.position.map(cleanNumber), size: record.size.map(cleanNumber),
    rotation: record.rotation.map(cleanNumber), color: record.color,
    materialId: record.materialId, shapeId: record.shapeId,
  };
}

function snapshot() { return objects.map(serializeRecord); }
function restore(data, message = "已恢复场景") {
  transform.detach();
  selected = null;
  objects.forEach((record) => scene.remove(record.mesh));
  objects = [];
  nextId = 1;
  data.forEach(createRecord);
  selectRecord(null);
  refreshObjectList();
  setStatus(message);
  saveToLocal(false);
}

function pushHistory() {
  history.push(snapshot());
  if (history.length > 60) history.shift();
  future = [];
  updateHistoryButtons();
}

function undo() {
  if (!history.length) return;
  future.push(snapshot());
  restore(history.pop(), "已撤销");
  updateHistoryButtons();
}

function redo() {
  if (!future.length) return;
  history.push(snapshot());
  restore(future.pop(), "已重做");
  updateHistoryButtons();
}

function updateHistoryButtons() {
  ui.undo.disabled = history.length === 0;
  ui.redo.disabled = future.length === 0;
}

function syncRecordFromMesh(record) {
  record.position = record.mesh.position.toArray();
  record.size = record.mesh.scale.toArray().map((n) => Math.max(0.05, n));
  record.rotation = [record.mesh.rotation.x, record.mesh.rotation.y, record.mesh.rotation.z];
}

function updateSelectionHelper() {
  if (!selected) { selectionHelper.visible = false; return; }
  selectionHelper.setFromObject(selected.mesh);
  selectionHelper.visible = true;
}

function selectRecord(record) {
  selected = record;
  if (record) {
    if (mode === "select" && transformMode) transform.attach(record.mesh);
    else transform.detach();
    selectionBadge.textContent = `${record.name} · #${record.id} · ${transformMode ? ({ translate: "移动", rotate: "旋转", scale: "缩放" })[transformMode] : "已选择"}`;
    ui.duplicateQuick.classList.remove("hidden");
    ui.noSelection.classList.add("hidden");
    ui.inspector.classList.remove("hidden");
  } else {
    transform.detach();
    transformMode = null;
    focusAnimation = null;
    selectionBadge.textContent = "未选择积木 · 选择工具只显示轮廓";
    ui.duplicateQuick.classList.add("hidden");
    ui.noSelection.classList.remove("hidden");
    ui.inspector.classList.add("hidden");
  }
  inspectorStartSnapshot = null;
  refreshTransformButtons();
  refreshCatalogButtons();
  updateSelectionHelper();
  updateInspector();
  refreshObjectList();
}

function updateInspector() {
  if (!selected) return;
  syncRecordFromMesh(selected);
  ui.selectedName.value = selected.name;
  [ui.posX, ui.posY, ui.posZ].forEach((input, i) => { input.value = cleanNumber(selected.position[i]); });
  [ui.sizeX, ui.sizeY, ui.sizeZ].forEach((input, i) => { input.value = cleanNumber(selected.size[i]); });
  [ui.rotX, ui.rotY, ui.rotZ].forEach((input, i) => { input.value = cleanNumber(THREE.MathUtils.radToDeg(selected.rotation[i])); });
  ui.selectedColor.value = selected.color;
  refreshCatalogButtons();
}

function refreshObjectList() {
  ui.objectCount.textContent = `(${objects.length})`;
  ui.objectList.replaceChildren();
  const ordered = [...objects].reverse();
  for (const record of ordered) {
    const button = document.createElement("button");
    button.className = `object-item${record === selected ? " active" : ""}`;
    button.innerHTML = `<span>${record.name}</span><span>#${record.id}</span>`;
    button.addEventListener("click", () => selectRecord(record));
    ui.objectList.appendChild(button);
  }
}

function commit(message) {
  refreshObjectList();
  updateHistoryButtons();
  saveToLocal(false);
  setStatus(message);
}

function saveToLocal(notify = true) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify({ version: 3, name: "我的空岛模型", blocks: snapshot() }));
  if (notify) setStatus(`已保存到浏览器 · ${objects.length} 个积木`);
}

function loadFromLocal() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY) || localStorage.getItem("island-3d-workbench-v1");
    if (!raw) return false;
    const data = JSON.parse(raw);
    if (!Array.isArray(data.blocks)) return false;
    restore(data.blocks, `已恢复上次工程 · ${data.blocks.length} 个积木`);
    return true;
  } catch { return false; }
}

function collision(recordSpec, ignore = null) {
  const [x, y, z] = recordSpec.position;
  const [sx, sy, sz] = recordSpec.size;
  const epsilon = 0.015;
  return objects.some((record) => {
    if (record === ignore) return false;
    syncRecordFromMesh(record);
    const [ox, oy, oz] = record.position;
    const [osx, osy, osz] = record.size;
    return Math.abs(x - ox) < (sx + osx) / 2 - epsilon
      && Math.abs(y - oy) < (sy + osy) / 2 - epsilon
      && Math.abs(z - oz) < (sz + osz) / 2 - epsilon;
  });
}

function placeBlock(point, normal, targetRecord = null) {
  const size = newBlockSize();
  const center = point.clone();
  if (targetRecord) {
    const targetBox = new THREE.Box3().setFromObject(targetRecord.mesh);
    const targetCenter = targetBox.getCenter(new THREE.Vector3());
    const targetSize = targetBox.getSize(new THREE.Vector3());
    center.copy(targetCenter);
    if (Math.abs(normal.x) > 0.7) center.x += Math.sign(normal.x) * (targetSize.x + size[0]) / 2;
    else if (Math.abs(normal.y) > 0.7) center.y += Math.sign(normal.y) * (targetSize.y + size[1]) / 2;
    else center.z += Math.sign(normal.z) * (targetSize.z + size[2]) / 2;
  } else {
    const axisSize = Math.abs(normal.x) * size[0] + Math.abs(normal.y) * size[1] + Math.abs(normal.z) * size[2];
    center.addScaledVector(normal, axisSize / 2 + 0.006);
    center.set(snapValue(center.x), snapValue(center.y), snapValue(center.z));
    if (normal.y > 0.7 && center.y < size[1] / 2) center.y = size[1] / 2;
  }
  const spec = {
    name: `新${SHAPES.find((shape) => shape.id === newShapeId)?.name || "积木"}`,
    type: "block", position: center.toArray(), size, rotation: [0, 0, 0], color: ui.newColor.value,
    materialId: newMaterialId, shapeId: newShapeId,
  };
  const step = snapStep() || 0.1;
  for (let attempts = 0; attempts < 16 && collision(spec); attempts += 1) {
    spec.position[0] += normal.x * step;
    spec.position[1] += normal.y * step;
    spec.position[2] += normal.z * step;
  }
  pushHistory();
  createRecord(spec);
  selectRecord(null);
  commit("已放置积木");
}

function insertTemplate(template) {
  if (!template || !Array.isArray(template.blocks) || !template.blocks.length) {
    setStatus("模型为空，无法插入");
    return false;
  }
  let templateMinX = Infinity;
  for (const source of template.blocks) {
    const position = source.position || [source.x, source.y, source.z];
    const size = source.size || [source.sx, source.sy, source.sz];
    const x = Number(source.x ?? position[0]) || 0;
    const sx = Math.max(0.05, Number(source.sx ?? size[0]) || 1);
    templateMinX = Math.min(templateMinX, x - sx * 0.5);
  }

  let offsetX = 0;
  if (objects.length) {
    let existingMaxX = -Infinity;
    for (const record of objects) {
      const bounds = new THREE.Box3().setFromObject(record.mesh);
      existingMaxX = Math.max(existingMaxX, bounds.max.x);
    }
    offsetX = existingMaxX + 1 - templateMinX;
  }

  pushHistory();
  const inserted = [];
  for (const source of template.blocks) {
    const position = source.position || [source.x, source.y, source.z];
    const record = createRecord({
      ...source,
      id: undefined,
      position: [
        (Number(source.x ?? position[0]) || 0) + offsetX,
        Number(source.y ?? position[1]) || 0,
        Number(source.z ?? position[2]) || 0,
      ],
    });
    inserted.push(record);
  }
  selectRecord(null);
  commit(`已插入模型 · ${template.name || "未命名模型"} · ${inserted.length} 组件`);
  const insertedBounds = new THREE.Box3();
  inserted.forEach((record) => insertedBounds.expandByObject(record.mesh));
  focusBounds(insertedBounds, template.name || "模型");
  if (isMobileLayout()) setDockOpen(false);
  return true;
}

function deleteRecord(record) {
  if (!record) return;
  pushHistory();
  removeRecord(record);
  refreshObjectList();
  commit("已拆除积木");
}

function duplicateSelected() {
  if (!selected) return;
  const spec = serializeRecord(selected);
  delete spec.id;
  const baseName = selected.name.replace(/(?:\s*(?:副本|副本\s*\d+))+$/u, "").trim() || "积木";
  const duplicateCount = objects.filter((record) => record !== selected && record.name.startsWith(`${baseName} 副本`)).length;
  spec.name = `${baseName} 副本${duplicateCount ? ` ${duplicateCount + 1}` : ""}`;
  const [x, y, z] = selected.position;
  const [sx, , sz] = selected.size;
  const [copyX, , copyZ] = spec.size;
  const candidates = [
    [x + (sx + copyX) / 2, y, z],
    [x - (sx + copyX) / 2, y, z],
    [x, y, z + (sz + copyZ) / 2],
    [x, y, z - (sz + copyZ) / 2],
  ];
  const position = candidates.find((candidate) => !collision({ ...spec, position: candidate }));
  if (!position) {
    setStatus("选中积木四周没有足够的复制空间");
    return;
  }
  pushHistory();
  spec.position = position;
  const copy = createRecord(spec);
  selectRecord(copy);
  commit("已复制到旁边");
}

function snapSelectedTransform() {
  if (!selected) return;
  const step = snapStep();
  if (step && transformMode === "translate") {
    selected.mesh.position.set(
      snapValue(selected.mesh.position.x, step), snapValue(selected.mesh.position.y, step), snapValue(selected.mesh.position.z, step),
    );
  }
  selected.mesh.scale.set(
    Math.max(0.05, selected.mesh.scale.x), Math.max(0.05, selected.mesh.scale.y), Math.max(0.05, selected.mesh.scale.z),
  );
  syncRecordFromMesh(selected);
  updateInspector();
  updateSelectionHelper();
}

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
function pointerHit(event) {
  const rect = renderer.domElement.getBoundingClientRect();
  pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  return raycaster.intersectObjects([...objects.map((record) => record.mesh), ground], false)[0] || null;
}

renderer.domElement.addEventListener("pointerdown", (event) => {
  if (event.button !== 0 || transform.dragging) return;
  const hit = pointerHit(event);
  if (!hit) { if (mode === "select") selectRecord(null); return; }
  const record = objects.find((item) => item.mesh === hit.object) || null;
  if (mode === "delete") { if (record) deleteRecord(record); return; }
  if (mode === "select") { selectRecord(record); return; }
  if (mode === "add") {
    let normal = new THREE.Vector3(0, 1, 0);
    if (record && hit.face) normal.copy(hit.face.normal).transformDirection(record.mesh.matrixWorld).round();
    placeBlock(hit.point, normal, record);
  }
});

function applyInspector({ push = true, message = "已实时更新积木" } = {}) {
  if (!selected) return;
  if (push) pushHistory();
  selected.name = ui.selectedName.value.trim() || selected.name;
  selected.mesh.position.set(
    Number(ui.posX.value) || 0,
    Number(ui.posY.value) || 0,
    Number(ui.posZ.value) || 0,
  );
  selected.mesh.scale.set(
    Math.max(0.05, Number(ui.sizeX.value) || 0.05),
    Math.max(0.05, Number(ui.sizeY.value) || 0.05),
    Math.max(0.05, Number(ui.sizeZ.value) || 0.05),
  );
  selected.mesh.rotation.set(
    THREE.MathUtils.degToRad(Number(ui.rotX.value) || 0),
    THREE.MathUtils.degToRad(Number(ui.rotY.value) || 0),
    THREE.MathUtils.degToRad(Number(ui.rotZ.value) || 0),
  );
  selected.color = ui.selectedColor.value;
  selected.mesh.material = materialFor(selected.materialId, selected.color);
  snapSelectedTransform();
  commit(message);
}

function refreshTransformButtons() {
  document.querySelectorAll("[data-transform]").forEach((button) => {
    button.classList.toggle("active", Boolean(selected) && button.dataset.transform === transformMode);
  });
}

function setMode(nextMode) {
  mode = nextMode;
  transformMode = null;
  transform.detach();
  document.querySelectorAll("[data-mode]").forEach((button) => button.classList.toggle("active", button.dataset.mode === mode));
  renderer.domElement.style.cursor = mode === "add" ? "crosshair" : mode === "delete" ? "not-allowed" : "default";
  refreshTransformButtons();
  if (selected) selectionBadge.textContent = `${selected.name} · #${selected.id} · 已选择`;
  setStatus(mode === "add" ? "放置模式：点击地面或积木表面" : mode === "delete" ? "拆除模式：点击积木删除" : "选择模式：只选择和显示轮廓，不显示坐标轴");
}

function setTransformMode(nextMode) {
  if (!selected) {
    setStatus("请先使用选择工具点中一个积木");
    return false;
  }
  mode = "select";
  transformMode = nextMode;
  transform.setMode(nextMode);
  const step = snapStep();
  transform.setTranslationSnap(step || null);
  transform.setRotationSnap(THREE.MathUtils.degToRad(15));
  transform.setScaleSnap(step || null);
  transform.attach(selected.mesh);
  document.querySelectorAll("[data-mode]").forEach((button) => button.classList.toggle("active", button.dataset.mode === "select"));
  renderer.domElement.style.cursor = "default";
  refreshTransformButtons();
  const label = ({ translate: "移动", rotate: "旋转", scale: "缩放" })[nextMode];
  selectionBadge.textContent = `${selected.name} · #${selected.id} · ${label}`;
  setStatus(`${label}工具：拖动对应坐标轴；按 V 返回纯选择`);
  return true;
}

function setView(name) {
  const distance = 22;
  focusAnimation = null;
  if (name === "front") camera.position.set(0, 5, distance);
  else if (name === "right") camera.position.set(distance, 5, 0);
  else if (name === "top") camera.position.set(0.01, distance, 0.01);
  else camera.position.set(13, 11, 15);
  orbit.target.set(0, 2.7, 0);
  camera.lookAt(orbit.target);
  orbit.update();
}

function setPanel(panelId) {
  activePanel = panelId;
  document.querySelectorAll("[data-panel]").forEach((panel) => panel.classList.toggle("hidden", panel.dataset.panel !== panelId));
  document.querySelectorAll("[data-panel-tab]").forEach((button) => button.classList.toggle("active", button.dataset.panelTab === panelId));
}

function isMobileLayout() {
  return window.matchMedia("(max-width: 760px)").matches;
}

function setDockOpen(open) {
  mobileDockOpen = Boolean(open);
  const shouldClose = isMobileLayout() && !mobileDockOpen;
  contextDock.classList.toggle("mobile-closed", shouldClose);
  selectionHud.classList.toggle("panel-open", isMobileLayout() && mobileDockOpen);
  $("mobilePanelToggle").classList.toggle("active", isMobileLayout() && mobileDockOpen);
}

function focusBounds(bounds, label) {
  if (!bounds || bounds.isEmpty()) return;
  const target = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const radius = Math.max(size.x, size.y, size.z, 0.8);
  const direction = camera.position.clone().sub(orbit.target).normalize();
  const distance = Math.max(3.2, radius * 4.2);
  focusAnimation = {
    start: performance.now(), duration: 460,
    fromTarget: orbit.target.clone(), toTarget: target,
    fromPosition: camera.position.clone(), toPosition: target.clone().addScaledVector(direction, distance),
  };
  setStatus(`正在聚焦 · ${label}`);
}

function focusSelected() {
  if (!selected) {
    setStatus("请先选择一个积木，再进行聚焦");
    return;
  }
  focusBounds(new THREE.Box3().setFromObject(selected.mesh), selected.name);
}

function updateFocusAnimation(now) {
  if (!focusAnimation) return;
  const raw = Math.min(1, (now - focusAnimation.start) / focusAnimation.duration);
  const eased = raw * raw * (3 - 2 * raw);
  orbit.target.lerpVectors(focusAnimation.fromTarget, focusAnimation.toTarget, eased);
  camera.position.lerpVectors(focusAnimation.fromPosition, focusAnimation.toPosition, eased);
  if (raw >= 1) focusAnimation = null;
}

function createHouseTemplate() {
  const result = [];
  const add = (name, position, size, color, type = "block") => result.push({ name, position, size, color, type, rotation: [0, 0, 0] });
  const white = "#f5f1e8", warm = "#ded1be", blue = "#0875b5", blueDark = "#064e79", terra = "#bd6c32";
  for (let x = -6; x <= 5; x += 1) for (let z = -4; z <= 4; z += 1) {
    add("地砖", [x, 0.25, z], [1, 0.5, 1], (x + z * 3) % 7 === 0 ? warm : white, "base");
    if (x === -6 || x === 5 || z === -4 || z === 4) add("底座侧砖", [x, -0.35, z], [1, 0.7, 1], "#b9ae9f", "base");
  }
  for (let y = 1; y <= 6; y += 1) {
    for (let x = -3; x <= 3; x += 1) {
      if (!((x === 0 || x === 1) && y <= 5)) add("前墙砖", [x, y, 3], [1, 1, 1], white, "wall");
      add("后墙砖", [x, y, -3], [1, 1, 1], white, "wall");
    }
    for (let z = -2; z <= 2; z += 1) {
      add("左墙砖", [-3, y, z], [1, 1, 1], white, "wall");
      if (!(z >= -1 && z <= 0 && y >= 3 && y <= 4)) add("右墙砖", [3, y, z], [1, 1, 1], white, "wall");
    }
  }
  add("蓝色门", [0.5, 3, 3.56], [1.85, 4.9, 0.18], blueDark, "door");
  add("窗洞", [3.54, 3.5, -0.5], [0.18, 1.9, 1.9], "#073b5e", "window");
  add("前窗扇", [3.7, 4, 1.25], [0.25, 3, 0.95], blue, "window");
  add("后窗扇", [3.7, 4, -1.72], [0.25, 3, 0.95], "#138ac9", "window");
  for (let x = -3; x <= 3; x += 1) { add("屋顶围砖", [x, 7, 3], [1, 1, 1], white, "roof"); add("屋顶围砖", [x, 7, -3], [1, 1, 1], white, "roof"); }
  for (let z = -2; z <= 2; z += 1) { add("屋顶围砖", [-3, 7, z], [1, 1, 1], white, "roof"); add("屋顶围砖", [3, 7, z], [1, 1, 1], white, "roof"); }
  for (let x = -2; x <= 2; x += 1) for (let z = -2; z <= 2; z += 1) add("屋顶地砖", [x, 6.56, z], [1, 0.14, 1], white, "roof");
  const addPot = (x, z, flower) => {
    add("陶土花盆", [x, 0.8, z], [1, 0.8, 1], terra, "pot");
    add("花盆沿", [x, 1.18, z], [1.35, 0.28, 1.35], "#d17b38", "pot");
    add("泥土", [x, 1.32, z], [0.88, 0.12, 0.88], "#58402d", "soil");
    for (const [dx, dy, dz, c] of [[-.35,1.55,0,"#6f9a37"],[.2,1.62,.22,"#4b6f2d"],[0,1.9,-.18,"#7fa83f"],[-.18,2.14,0,flower],[.2,2.25,.04,flower]]) add("花叶", [x+dx,dy,z+dz], [.38,.38,.38], c, "plant");
  };
  addPot(2.25, 4.2, "#e84a96");
  addPot(4.7, -0.7, "#f4a72c");
  add("大花盆", [-2.7, 0.8, 4.2], [1, 0.8, 1], terra, "pot");
  add("大花盆沿", [-2.7, 1.18, 4.2], [1.35, 0.28, 1.35], "#d17b38", "pot");
  for (let i = 0; i < 9; i += 1) add("花树枝干", [-2.7 + (i % 2) * 0.06, 1.45 + i * 0.45, 4.16], [0.34, 0.54, 0.34], i % 2 ? "#7b5230" : "#684328", "tree");
  const flowerCenters = [
    [-3.75, 3.0], [-3.45, 3.55], [-3.15, 4.1], [-2.75, 3.45], [-2.35, 3.9], [-1.95, 4.3],
    [-3.4, 4.65], [-2.95, 5.05], [-2.45, 4.75], [-1.95, 5.25], [-3.0, 5.65], [-2.45, 6.05],
  ];
  flowerCenters.forEach(([x, y], index) => {
    const color = index % 3 === 0 ? "#cf317c" : index % 3 === 1 ? "#e84a96" : "#f05ca6";
    for (const [dx, dy, dz] of [[0,0,0],[.28,.03,.08],[-.26,.04,-.06],[.02,.28,.04]]) {
      add("粉色花瓣", [x + dx, y + dy, 4.2 + dz], [.32, .32, .32], color, "flower");
    }
    if (index % 2 === 0) add("花树叶片", [x, y - .3, 4.1], [.32, .32, .32], "#547f2d", "leaf");
  });
  return result;
}

function exportProject() {
  const payload = JSON.stringify({ version: 3, name: "我的空岛模型", blocks: snapshot() }, null, 2);
  const blob = new Blob([payload], { type: "application/json" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `island-model-${new Date().toISOString().slice(0, 10)}.json`;
  link.click();
  URL.revokeObjectURL(link.href);
  setStatus("工程 JSON 已导出");
}

async function importProject(file) {
  try {
    const data = JSON.parse(await file.text());
    if (!Array.isArray(data.blocks)) throw new Error("缺少 blocks 数组");
    if (data.version != null && ![1, 3].includes(Number(data.version))) throw new Error(`不支持 version=${data.version} 的模型 JSON`);
    if (data.blocks.length > 4000) throw new Error("模型积木数量超过 4000 个");
    pushHistory();
    restore(data.blocks, `已导入 ${data.blocks.length} 个积木`);
  } catch (error) { setStatus(`导入失败：${error.message}`); }
}

document.querySelectorAll("[data-mode]").forEach((button) => button.addEventListener("click", () => setMode(button.dataset.mode)));
document.querySelectorAll("[data-transform]").forEach((button) => button.addEventListener("click", () => setTransformMode(button.dataset.transform)));
document.querySelectorAll("[data-view]").forEach((button) => button.addEventListener("click", () => setView(button.dataset.view)));
document.querySelectorAll("[data-panel-tab]").forEach((button) => button.addEventListener("click", () => setPanel(button.dataset.panelTab)));
$("mobilePanelToggle").addEventListener("click", () => setDockOpen(!mobileDockOpen));
$("closeDock").addEventListener("click", () => setDockOpen(false));
document.querySelectorAll("[data-preset]").forEach((button) => button.addEventListener("click", () => {
  const [x, y, z] = PRESETS[button.dataset.preset];
  ui.newSizeX.value = x; ui.newSizeY.value = y; ui.newSizeZ.value = z;
  document.querySelectorAll("[data-preset]").forEach((item) => item.classList.toggle("active", item === button));
}));

const swatches = $("swatches");
PALETTE.forEach((color, index) => {
  const button = document.createElement("button");
  button.className = `swatch${index === 0 ? " active" : ""}`;
  button.style.background = color;
  button.title = color;
  button.addEventListener("click", () => {
    ui.newColor.value = color;
    swatches.querySelectorAll("button").forEach((item) => item.classList.toggle("active", item === button));
  });
  swatches.appendChild(button);
});

ui.snapSize.addEventListener("change", () => {
  if (transformMode && selected) setTransformMode(transformMode);
  else setStatus(`放置吸附已切换为 ${ui.snapSize.selectedOptions[0].textContent}`);
});
ui.undo.addEventListener("click", undo);
ui.redo.addEventListener("click", redo);
$("duplicateSelected").addEventListener("click", duplicateSelected);
ui.duplicateQuick.addEventListener("click", duplicateSelected);
$("deleteSelected").addEventListener("click", () => deleteRecord(selected));
$("focusSelected").addEventListener("click", focusSelected);
$("resetRotation").addEventListener("click", () => {
  if (!selected) return;
  ui.rotX.value = 0; ui.rotY.value = 0; ui.rotZ.value = 0;
  applyInspector({ message: "已将旋转回正" });
});

const inspectorInputs = [
  ui.selectedName, ui.posX, ui.posY, ui.posZ,
  ui.rotX, ui.rotY, ui.rotZ, ui.sizeX, ui.sizeY, ui.sizeZ, ui.selectedColor,
];
inspectorInputs.forEach((input) => {
  input.addEventListener("input", () => {
    if (!selected) return;
    if (!inspectorStartSnapshot) inspectorStartSnapshot = snapshot();
    applyInspector({ push: false, message: "已实时更新积木" });
  });
  input.addEventListener("change", () => {
    if (!inspectorStartSnapshot) return;
    history.push(inspectorStartSnapshot);
    if (history.length > 60) history.shift();
    inspectorStartSnapshot = null;
    future = [];
    commit("已保存属性修改");
  });
});

$("saveLocal").addEventListener("click", () => saveToLocal(true));
$("exportProject").addEventListener("click", exportProject);
$("importProject").addEventListener("click", () => $("projectFile").click());
$("projectFile").addEventListener("change", (event) => { if (event.target.files[0]) importProject(event.target.files[0]); event.target.value = ""; });
$("newProject").addEventListener("click", () => { pushHistory(); restore([], "已新建空白工程"); });
$("toggleReference").addEventListener("click", (event) => {
  referenceVisible = !referenceVisible;
  referenceOverlay.style.opacity = referenceVisible ? $("referenceOpacity").value : 0;
  event.currentTarget.classList.toggle("active", referenceVisible);
  event.currentTarget.textContent = referenceVisible ? "隐藏原图" : "显示原图";
});
$("referenceOpacity").addEventListener("input", (event) => { if (referenceVisible) referenceOverlay.style.opacity = event.target.value; });
$("chooseReference").addEventListener("click", () => $("referenceFile").click());
$("referenceFile").addEventListener("change", (event) => {
  const file = event.target.files[0];
  if (!file) return;
  referenceOverlay.src = URL.createObjectURL(file);
  referenceVisible = true;
  referenceOverlay.style.opacity = $("referenceOpacity").value;
  $("toggleReference").classList.add("active");
  $("toggleReference").textContent = "隐藏原图";
  setStatus(`已载入参考图片：${file.name}`);
});

window.addEventListener("keydown", (event) => {
  const typing = /INPUT|SELECT|TEXTAREA/.test(document.activeElement?.tagName || "");
  if (typing) return;
  const command = event.ctrlKey || event.metaKey;
  if (command && event.key.toLowerCase() === "z") { event.preventDefault(); event.shiftKey ? redo() : undo(); }
  else if (command && event.key.toLowerCase() === "y") { event.preventDefault(); redo(); }
  else if (command && event.key.toLowerCase() === "d") { event.preventDefault(); duplicateSelected(); }
  else if (command && event.key.toLowerCase() === "s") { event.preventDefault(); saveToLocal(true); }
  else if (event.key === "Delete" || event.key === "Backspace") deleteRecord(selected);
  else if (event.key.toLowerCase() === "w") setTransformMode("translate");
  else if (event.key.toLowerCase() === "e") setTransformMode("rotate");
  else if (event.key.toLowerCase() === "r") setTransformMode("scale");
  else if (event.key.toLowerCase() === "v") setMode("select");
  else if (event.key.toLowerCase() === "b") setMode("add");
  else if (event.key.toLowerCase() === "x") setMode("delete");
  else if (event.key.toLowerCase() === "f") focusSelected();
  else if (event.key === "Escape") {
    if (transformMode) setMode("select");
    else selectRecord(null);
  }
});

function resize() {
  const width = Math.max(1, viewport.clientWidth);
  const height = Math.max(1, viewport.clientHeight);
  renderer.setSize(width, height, false);
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
}
window.addEventListener("resize", () => {
  resize();
  setDockOpen(mobileDockOpen);
});

window.workbench = {
  getProject: () => ({ version: 3, name: "我的空岛模型", blocks: snapshot() }),
  loadProject: (project) => restore(project.blocks || []),
  addBlock: (spec) => { pushHistory(); const record = createRecord(spec); selectRecord(record); commit("已添加积木"); },
  getStats: () => ({ blocks: objects.length, templates: templateLibrary.length, templateBlocks: templateLibraryBlocks, selectedId: selected?.id || null, mode, transformMode, transformVisible: Boolean(selected && transformMode) }),
  getTemplates: () => templateLibrary,
  insertTemplate: (id) => insertTemplate(templateLibrary.find((template) => template.id === id)),
  selectById: (id) => selectRecord(objects.find((record) => record.id === Number(id)) || null),
  setMode,
  setTransformMode,
};

buildCatalogControls();
loadTemplateLibrary();
resize();
setMode("select");
setPanel(activePanel);
setDockOpen(false);
const forceFresh = new URLSearchParams(location.search).has("fresh");
if (forceFresh || !loadFromLocal()) restore(createHouseTemplate(), "工作台已就绪 · 已载入可编辑小屋模板");
updateHistoryButtons();
setView("iso");

function animate(now) {
  updateFocusAnimation(now);
  orbit.update();
  updateSelectionHelper();
  renderer.render(scene, camera);
  requestAnimationFrame(animate);
}
animate();
