---@diagnostic disable: undefined-global

local THREE = require("urhox-libs/3D")
local Catalog = require("BlockCatalog")
local BlockMaterials = require("BlockMaterials")
local HouseTemplate = require("HouseTemplate")
local HtmlRoundedBoxGeometry = require("HtmlRoundedBoxGeometry")
local TransparentBlockGeometry = require("TransparentBlockGeometry")
local TriangularPrismGeometry = require("TriangularPrismGeometry")
local FacetedSolidGeometry = require("FacetedSolidGeometry")
local FullCylinderGeometry = require("FullCylinderGeometry")
local BuilderTransformControls = require("BuilderTransformControls")
local MakerTransformControls = require("MakerTransformControls")
local ViewportCoordinates = require("ViewportCoordinates")
local Theme = require("CloudAtelierTheme")
local WorldPerformanceBudget = require("WorldPerformanceBudget")
local MobileThermalPolicy = require("MobileThermalPolicy")

local BuilderWorld = {}
BuilderWorld.__index = BuilderWorld

local DEG = math.pi / 180
local TAU = math.pi * 2
local TRANSPARENT_FACE_KEYS = { "x+", "x-", "y+", "y-", "z+", "z-" }

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function NativePlatform()
    local getter = rawget(_G, "GetNativePlatform") or rawget(_G, "GetPlatform")
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter)
    return ok and value or nil
end

local function SmoothStep(value)
    value = Clamp(tonumber(value) or 0, 0, 1)
    return value * value * (3 - 2 * value)
end

local function CleanNumber(value)
    return math.floor((tonumber(value) or 0) * 1000 + 0.5) / 1000
end

local function HtmlNumber(value)
    local text = tostring(value or "")
    if text:match("^%s*$") then return 0 end
    return tonumber(text)
end

local function SnapValue(value, step)
    if not step or step <= 0 then return value end
    return math.floor(value / step + 0.5) * step
end

local function NormalizeHex(value, fallback)
    value = tostring(value or fallback or "#f2e7cf"):lower()
    if value:match("^#%x%x%x%x%x%x$") then return value end
    if value:match("^%x%x%x%x%x%x$") then return "#" .. value end
    return fallback or "#f2e7cf"
end

local function ImagePixel(image, x, y)
    if not image or image.width <= 0 or image.height <= 0 then return nil end
    local pixelX = Clamp(math.floor(tonumber(x) or 0), 0, image.width - 1)
    local pixelY = Clamp(math.floor(tonumber(y) or 0), 0, image.height - 1)
    return image:GetPixel(pixelX, pixelY)
end

local function ColorHex(color)
    if not color then return nil end
    local function Channel(value)
        return Clamp(math.floor((tonumber(value) or 0) * 255 + 0.5), 0, 255)
    end
    return string.format("#%02x%02x%02x", Channel(color.r), Channel(color.g), Channel(color.b))
end

local function CopyBlock(block)
    return {
        id = block.id,
        name = block.name,
        type = block.type,
        x = block.x, y = block.y, z = block.z,
        sx = block.sx, sy = block.sy, sz = block.sz,
        rx = block.rx or 0, ry = block.ry or 0, rz = block.rz or 0,
        color = block.color,
        materialId = block.materialId or "solid",
        shapeId = Catalog.FindShape(block.shapeId).id,
    }
end

local function CopyBlocks(blocks)
    local result = {}
    for index, block in ipairs(blocks or {}) do result[index] = CopyBlock(block) end
    return result
end

local function DuplicateBaseName(value)
    local name = tostring(value or ""):match("^%s*(.-)%s*$")
    if name == "" then return "积木" end
    while true do
        -- Copies made by older releases could themselves be copied, producing
        -- names such as “窗框 副本 副本”. Always return to the authored base
        -- before assigning a short sequence number.
        local shorter = (name or ""):gsub("%s+副本%s*%d*%s*$", "")
        shorter = shorter:match("^%s*(.-)%s*$")
        if shorter == name then break end
        name = shorter
        if name == "" then return "积木" end
    end
    return name
end

local function NextDuplicateName(blocks, sourceName)
    local base = DuplicateBaseName(sourceName)
    local prefix = base .. " 副本"
    local used = {}
    for _, block in ipairs(blocks or {}) do
        local name = tostring(block and block.name or ""):match("^%s*(.-)%s*$")
        if name == prefix then
            used[1] = true
        elseif name:sub(1, #prefix) == prefix then
            local suffix = name:sub(#prefix + 1)
            local sequence = tonumber(suffix:match("^%s+(%d+)%s*$"))
            if sequence and sequence >= 2 then used[sequence] = true end
        end
    end
    if not used[1] then return prefix end
    local sequence = 2
    while used[sequence] do sequence = sequence + 1 end
    return prefix .. " " .. tostring(sequence)
end


local function EulerQuaternion(rx, ry, rz)
    local c1, c2, c3 = math.cos((rx or 0) * 0.5), math.cos((ry or 0) * 0.5), math.cos((rz or 0) * 0.5)
    local s1, s2, s3 = math.sin((rx or 0) * 0.5), math.sin((ry or 0) * 0.5), math.sin((rz or 0) * 0.5)
    return
        s1 * c2 * c3 + c1 * s2 * s3,
        c1 * s2 * c3 - s1 * c2 * s3,
        c1 * c2 * s3 + s1 * s2 * c3,
        c1 * c2 * c3 - s1 * s2 * s3
end

local function RotateQuaternion(x, y, z, qx, qy, qz, qw)
    local ix = qw * x + qy * z - qz * y
    local iy = qw * y + qz * x - qx * z
    local iz = qw * z + qx * y - qy * x
    local iw = -qx * x - qy * y - qz * z
    return
        ix * qw - iw * qx - iy * qz + iz * qy,
        iy * qw - iw * qy - iz * qx + ix * qz,
        iz * qw - iw * qz - ix * qy + iy * qx
end

local function RotateForward(x, y, z, rx, ry, rz)
    local qx, qy, qz, qw = EulerQuaternion(rx, ry, rz)
    return RotateQuaternion(x, y, z, qx, qy, qz, qw)
end

local function RotateInverse(x, y, z, rx, ry, rz)
    local qx, qy, qz, qw = EulerQuaternion(rx, ry, rz)
    return RotateQuaternion(x, y, z, -qx, -qy, -qz, qw)
end

local function WorldHalfExtents(block)
    local bounds = Catalog.FindShape(block.shapeId).bounds
    local sx = block.sx * bounds[1]
    local sy = block.sy * bounds[2]
    local sz = block.sz * bounds[3]
    local xx, xy, xz = RotateForward(1, 0, 0, block.rx, block.ry, block.rz)
    local yx, yy, yz = RotateForward(0, 1, 0, block.rx, block.ry, block.rz)
    local zx, zy, zz = RotateForward(0, 0, 1, block.rx, block.ry, block.rz)
    return {
        x = (math.abs(xx * sx) + math.abs(yx * sy) + math.abs(zx * sz)) * 0.5,
        y = (math.abs(xy * sx) + math.abs(yy * sy) + math.abs(zy * sz)) * 0.5,
        z = (math.abs(xz * sx) + math.abs(yz * sy) + math.abs(zz * sz)) * 0.5,
    }
end

local function Intersects(a, b, epsilon)
    epsilon = epsilon or 0.015
    local ah, bh = WorldHalfExtents(a), WorldHalfExtents(b)
    return math.abs(a.x - b.x) < ah.x + bh.x - epsilon
        and math.abs(a.y - b.y) < ah.y + bh.y - epsilon
        and math.abs(a.z - b.z) < ah.z + bh.z - epsilon
end

local function AngleDistance(a, b)
    local delta = ((tonumber(a) or 0) - (tonumber(b) or 0)) % TAU
    if delta > math.pi then delta = TAU - delta end
    return math.abs(delta)
end

local function SameOrientation(a, b)
    return AngleDistance(a.rx, b.rx) < 0.0001
        and AngleDistance(a.ry, b.ry) < 0.0001
        and AngleDistance(a.rz, b.rz) < 0.0001
end


local function PrettyJSON(value)
    local ok, compact = pcall(cjson.encode, value)
    if not ok then return nil end
    local output, indent, inString, escaped = {}, 0, false, false
    local function NewLine()
        output[#output + 1] = "\n" .. string.rep("  ", indent)
    end
    for index = 1, #compact do
        local char = compact:sub(index, index)
        if inString then
            output[#output + 1] = char
            if escaped then escaped = false
            elseif char == "\\" then escaped = true
            elseif char == "\"" then inString = false end
        elseif char == "\"" then
            inString = true
            output[#output + 1] = char
        elseif char == "{" or char == "[" then
            output[#output + 1] = char
            indent = indent + 1
            NewLine()
        elseif char == "}" or char == "]" then
            indent = math.max(0, indent - 1)
            NewLine()
            output[#output + 1] = char
        elseif char == "," then
            output[#output + 1] = char
            NewLine()
        elseif char == ":" then
            output[#output + 1] = ": "
        else
            output[#output + 1] = char
        end
    end
    return table.concat(output)
end


function BuilderWorld.new()
    local self = setmetatable({}, BuilderWorld)
    self.blocks = {}
    self.byId = {}
    self.nextId = 1
    self.selectedId = nil
    self.transformAttached = false
    self.mode = "select"
    self.transformMode = "translate"
    self.presetId = "story_cube"
    self.shapeId = "box"
    self.paletteActiveId = "cream"
    self.newSize = { 1, 1, 1 }
    self.newColor = "#f2e7cf"
    self.newMaterialId = "solid"
    self.colorPickTarget = nil
    self.colorPickImage = nil
    self.colorPickCaptureFrames = 0
    self.snap = 0.25
    self.transformSize = 0.8
    self.mobileEditor = MobileThermalPolicy.IsMobileViewport(
        graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR(), NativePlatform())
    self.mobileDevice = MobileThermalPolicy.IsMobileDevice(NativePlatform())
    self.mobileGizmoSuppressed = false
    self.shadowQualityDirty = self.mobileDevice
    self.liveInspectorKey = nil
    self.templateSummaries = {}
    self.objectListCache = nil
    self.history = {}
    self.future = {}
    self.materialSystem = BlockMaterials.new()
    self.onChanged = nil
    self.onCommit = nil
    self.viewportRect = { left = 0, top = 0, right = graphics:GetWidth(), bottom = graphics:GetHeight() }
    self.uiScale = math.max(1, graphics:GetDPR())
    self.target = THREE.Vector3(0, 2.5, 0)
    self.theta, self.phi, self.radius = 0, 0, 1
    self.deltaTheta, self.deltaPhi, self.radiusScale = 0, 0, 1
    self.panOffsetX, self.panOffsetY, self.panOffsetZ = 0, 0, 0
    self.cameraFocusAnimation = nil
    self.transformDrag = nil
    -- Use the same segments*2+1 recipe as three@0.180.0. Maker's bundled
    -- approximation rounds each entire face and makes the centre look puffed.
    self.blockGeometry = HtmlRoundedBoxGeometry.new(1, 1, 1, 2, 0.075)
    self.shapeGeometries = {
        box = self.blockGeometry,
        sphere = THREE.SphereGeometry(0.5, 24, 16),
        cylinder = FullCylinderGeometry.new(24),
        cone = THREE.ConeGeometry(0.5, 1, 24, 1, false),
        tri_prism = TriangularPrismGeometry.new(),
        pyramid = FacetedSolidGeometry.SquarePyramid(),
        tetra = FacetedSolidGeometry.Tetrahedron(),
        torus = THREE.TorusGeometry(0.38, 0.12, 12, 32),
    }
    self.mobileShapeGeometries = {
        sphere = THREE.SphereGeometry(0.5, 10, 7),
        cylinder = FullCylinderGeometry.new(12),
        cone = THREE.ConeGeometry(0.5, 1, 12, 1, false),
        torus = THREE.TorusGeometry(0.38, 0.12, 6, 16),
    }

    self.scene = THREE.Scene()
    self.scene.background = Theme.ENVIRONMENT.sky.horizon
    self.octree = self.scene:getNode():GetComponent("Octree")
    self.root = THREE.Group()
    self.scene:add(self.root)

    -- UrhoX emulates HemisphereLight as one flat ambient contribution rather
    -- than Three.js' normal-based sky/ground gradient. Using the HTML numeric
    -- intensities directly clips the whole model before the sun is evaluated,
    -- so use an engine-calibrated equivalent that preserves the same palette.
    self.hemisphere = THREE.HemisphereLight(
        Theme.ENVIRONMENT.light.hemisphereSky, Theme.ENVIRONMENT.light.hemisphereGround, 0.66)
    self.scene:add(self.hemisphere)
    self.sun = THREE.DirectionalLight(Theme.ENVIRONMENT.light.sun, 1.42)
    self.sun.position:set(-8, 16, 11)
    self.sun.castShadow = true
    local initialShadowMapSize = WorldPerformanceBudget.ShadowMapSize(self.mobileDevice)
    self.sun.shadow.mapSize:set(initialShadowMapSize, initialShadowMapSize)
    self.sun.shadow.camera.left, self.sun.shadow.camera.right = -18, 18
    self.sun.shadow.camera.top, self.sun.shadow.camera.bottom = 18, -18
    self.sun.shadow.camera.near, self.sun.shadow.camera.far = 0.1, 50
    self.scene:add(self.sun)
    self.fill = THREE.DirectionalLight(Theme.ENVIRONMENT.light.fill, 0.30)
    self.fill.position:set(10, 7, -12)
    self.scene:add(self.fill)

    self:CreateGrid()

    self.camera = THREE.PerspectiveCamera(36, 1, 0.05, 300)
    self.camera.position:set(13, 11, 15)
    self.camera:lookAt(self.target)
    self.scene:add(self.camera)
    self:SetSphericalFromCamera()

    self.renderer = THREE.WebGLRenderer({ scene = self.scene, camera = self.camera })
    self.renderer.shadowMap.enabled = true
    self.renderer.shadowMap.type = THREE.PCFSoftShadowMap
    -- The Maker wrapper maps every non-zero Three tone mapper to Urho's LUT,
    -- which is not ACES and was the source of the visible halo/color shift.
    self.renderer.toneMapping = THREE.NoToneMapping
    local zone = rawget(self.scene, "_zone")
    if zone then
        if zone.SetTonemapLUTEnabled then zone:SetTonemapLUTEnabled(false) end
        if zone.SetBloomPlusEnabled then zone:SetBloomPlusEnabled(false) end
        if zone.SetAutoExposureEnabled then zone:SetAutoExposureEnabled(false) end
        if zone.SetVignetteEnabled then zone:SetVignetteEnabled(false) end
        local tonemap = zone.GetTonemapLUTEnabled and zone:GetTonemapLUTEnabled() or false
        local bloom = zone.GetBloomPlusEnabled and zone:GetBloomPlusEnabled() or false
        local exposure = zone.GetAutoExposureEnabled and zone:GetAutoExposureEnabled() or false
        local vignette = zone.GetVignetteEnabled and zone:GetVignetteEnabled() or false
        print(string.format(
            "[Island3DWorkbench] postfx tonemap=%s bloom=%s autoExposure=%s vignette=%s",
            tostring(tonemap), tostring(bloom), tostring(exposure), tostring(vignette)
        ))
    end
    self.viewport = rawget(self.renderer, "_vp")

    self.transformOverlay = MakerTransformControls.NewOverlayRenderer(self.scene, self.camera, self.viewport)
    self.transformPicker = MakerTransformControls.NewPicker(self.scene, self.camera, "object")
    -- Phones use only the gizmo attached to the selected block. The former
    -- fixed lower-left copy was removed so it cannot render or capture touch.
    self.mobileTransformPicker = nil

    self:CreateCheckerBackdrop()
    self:CreateSelectionHelper()
    self:CreateDragHelpers()
    self:CreateTransformGizmo()
    self:ApplyRenderQuality()
    return self
end

function BuilderWorld:CreateGrid()
    local minorPoints, majorPoints = {}, {}
    for index = 0, 64 do
        local coordinate = -16 + index * 0.5
        local target = math.abs(coordinate) < 0.0001 and majorPoints or minorPoints
        target[#target + 1] = THREE.Vector3(coordinate, 0.003, -16)
        target[#target + 1] = THREE.Vector3(coordinate, 0.003, 16)
        target[#target + 1] = THREE.Vector3(-16, 0.003, coordinate)
        target[#target + 1] = THREE.Vector3(16, 0.003, coordinate)
    end
    local minor = THREE.LineSegments(
        THREE.BufferGeometry():setFromPoints(minorPoints),
        THREE.LineBasicMaterial({ color = 0xb7d0d6, opacity = 0.58, transparent = true })
    )
    local major = THREE.LineSegments(
        THREE.BufferGeometry():setFromPoints(majorPoints),
        THREE.LineBasicMaterial({ color = 0x6e9cac, opacity = 0.58, transparent = true })
    )
    MakerTransformControls.MarkSceneObject(minor)
    MakerTransformControls.MarkSceneObject(major)
    self.scene:add(minor)
    self.scene:add(major)
end

function BuilderWorld:CreateCheckerBackdrop()
    -- The checker never changes, so upload a 2x2 image once. CanvasTexture
    -- would replay a NanoVG display list into a render target every frame.
    local image = Image()
    image:SetSize(2, 2, 4)
    local light = Color(234 / 255, 245 / 255, 247 / 255, 1)
    local dark = Color(217 / 255, 234 / 255, 237 / 255, 1)
    image:SetPixel(0, 0, dark)
    image:SetPixel(1, 0, light)
    image:SetPixel(0, 1, light)
    image:SetPixel(1, 1, dark)
    local native = Texture2D:new()
    native:SetSRGB(true)
    native:SetNumLevels(1)
    native:SetFilterMode(FILTER_NEAREST)
    native:SetData(image, false)
    self.checkerTexture = THREE.Texture("[workbench-checker]")
    self.checkerTexture:_setNative(native)
    self.checkerTexture.wrapS = THREE.RepeatWrapping
    self.checkerTexture.wrapT = THREE.RepeatWrapping
    self.checkerTexture.generateMipmaps = false
    self.checkerTexture.magFilter = THREE.NearestFilter
    self.checkerTexture.minFilter = THREE.NearestFilter
    self.checkerTexture.colorSpace = "srgb"
    self.checkerTexture.needsUpdate = true
    self.checkerMaterial = THREE.MeshBasicMaterial({
        color = 0xffffff,
        map = self.checkerTexture,
        side = THREE.DoubleSide,
    })
    self.checkerBackdrop = THREE.Mesh(THREE.PlaneGeometry(1, 1), self.checkerMaterial)
    MakerTransformControls.MarkSceneObject(self.checkerBackdrop)
    self.checkerBackdrop.position:set(0, 0, -220)
    self.checkerBackdrop.renderOrder = -100
    self.camera:add(self.checkerBackdrop)
    self:UpdateBackdrop()
end


function BuilderWorld:SetOnChanged(callback) self.onChanged = callback end
function BuilderWorld:SetOnCommit(callback) self.onCommit = callback end

function BuilderWorld:Notify(message)
    if self.onChanged then self.onChanged(self:GetState(), message) end
end

function BuilderWorld:RefreshState()
    if self.onChanged then self.onChanged(self:GetState(), nil) end
end

function BuilderWorld:Commit(message)
    self:RefreshTransparentTopology()
    self:MarkShadowQualityDirty()
    self:RefreshHelpers()
    self:Notify(message)
    if self.onCommit then self.onCommit(self:GetProjectData()) end
end

function BuilderWorld:MaterialFor(materialId, color, forceNew)
    return self.materialSystem:MaterialFor(materialId, color, forceNew)
end

function BuilderWorld:MarkShadowQualityDirty()
    if self.mobileDevice then self.shadowQualityDirty = true end
end

function BuilderWorld:ApplyRenderQuality()
    local mobile = self.mobileDevice == true
    local shadowMapSize = WorldPerformanceBudget.ShadowMapSize(mobile)
    if self.sun and self.sun.shadow and self.sun.shadow.mapSize then
        self.sun.shadow.mapSize:set(shadowMapSize, shadowMapSize)
    end
    if renderer and renderer.SetShadowMapSize then renderer:SetShadowMapSize(shadowMapSize) end
    if not mobile then
        self.shadowQualityDirty = false
        return
    end

    local shadowCursor = 0
    local selected = self.selectedId and self.byId[self.selectedId] or nil
    local function Assign(block)
        if not block or not block.mesh then return end
        local castShadow
        castShadow, shadowCursor = WorldPerformanceBudget.ReserveShadow(
            block, true, shadowCursor)
        block.mesh.castShadow = castShadow
    end
    Assign(selected)
    for _, block in ipairs(self.blocks or {}) do
        if block ~= selected then Assign(block) end
    end
    self.shadowQualityDirty = false
end

function BuilderWorld:GeometryForShape(shapeId)
    local id = Catalog.FindShape(shapeId).id
    local mobileGeometry = self.mobileDevice and self.mobileShapeGeometries[id] or nil
    return mobileGeometry or self.shapeGeometries[id] or self.blockGeometry
end

function BuilderWorld:BaseGeometrySignature(shapeId)
    return "shape:" .. Catalog.FindShape(shapeId).id
end

function BuilderWorld:NormalizeBlock(source)
    local position = source.position
    local size = source.size
    local rotation = source.rotation
    local id = tonumber(source.id)
    if not id or id == 0 then
        id = self.nextId
        self.nextId = self.nextId + 1
    end
    return {
        id = id,
        name = source.name or "积木 " .. tostring(self.nextId),
        type = source.type or "block",
        x = tonumber(source.x or (position and position[1])) or 0,
        y = tonumber(source.y or (position and position[2])) or 0.5,
        z = tonumber(source.z or (position and position[3])) or 0,
        sx = math.max(0.05, tonumber(source.sx or (size and size[1])) or 1),
        sy = math.max(0.05, tonumber(source.sy or (size and size[2])) or 1),
        sz = math.max(0.05, tonumber(source.sz or (size and size[3])) or 1),
        rx = tonumber(source.rx or (rotation and rotation[1])) or 0,
        ry = tonumber(source.ry or (rotation and rotation[2])) or 0,
        rz = tonumber(source.rz or (rotation and rotation[3])) or 0,
        color = NormalizeHex(source.color),
        materialId = Catalog.FindMaterial(source.materialId or source.material).id,
        -- Projects saved before v1.9 do not contain shapeId and remain boxes.
        shapeId = Catalog.FindShape(source.shapeId or source.shape).id,
    }
end

function BuilderWorld:CreateBlockMesh(block, geometry)
    local mesh = THREE.Mesh(geometry or self:GeometryForShape(block.shapeId), self:MaterialFor(block.materialId, block.color))
    mesh.position:set(block.x, block.y, block.z)
    mesh.scale:set(block.sx, block.sy, block.sz)
    mesh.rotation:set(block.rx, block.ry, block.rz)
    mesh.castShadow = not self.mobileDevice
        and not Catalog.FindMaterial(block.materialId).transparent
    mesh.receiveShadow = true
    mesh.userData.recordId = block.id
    mesh.name = "Block_" .. tostring(block.id)
    MakerTransformControls.MarkSceneObject(mesh)
    self.root:add(mesh)
    block.mesh = mesh
    self:MarkShadowQualityDirty()
    return mesh
end

function BuilderWorld:CreateRecord(source)
    local block = self:NormalizeBlock(source)
    self.nextId = math.max(self.nextId, block.id + 1)
    -- Geometry objects are build-once recipes. Every Mesh invocation emits an
    -- independent CustomGeometry component on that object's node.
    self:CreateBlockMesh(block, self:GeometryForShape(block.shapeId))
    block.geometrySignature = self:BaseGeometrySignature(block.shapeId)
    self.blocks[#self.blocks + 1] = block
    self.byId[block.id] = block
    self.objectListCache = nil
    return block
end

function BuilderWorld:ReplaceBlockGeometry(block, geometry, signature)
    if block.mesh then
        self.root:remove(block.mesh)
        block.mesh:getNode():Remove()
    end
    self:CreateBlockMesh(block, geometry)
    block.geometrySignature = signature
end

function BuilderWorld:GetTransparentFaceMask(block, transparentBlocks)
    local hidden, signature = {}, {}
    local epsilon = 0.002
    local qx, qy, qz, qw = EulerQuaternion(block.rx, block.ry, block.rz)
    -- Test each neighbour once. The previous face-first version repeated the
    -- inverse Euler transform six times per pair, which became noticeable for
    -- large pools or glass walls.
    for _, other in ipairs(transparentBlocks) do
        if block ~= other and block.materialId == other.materialId and SameOrientation(block, other) then
            local dx, dy, dz = RotateQuaternion(
                other.x - block.x, other.y - block.y, other.z - block.z,
                -qx, -qy, -qz, qw
            )
            local coversX = math.abs(dx) + block.sx * 0.5 <= other.sx * 0.5 + epsilon
            local coversY = math.abs(dy) + block.sy * 0.5 <= other.sy * 0.5 + epsilon
            local coversZ = math.abs(dz) + block.sz * 0.5 <= other.sz * 0.5 + epsilon
            if coversY and coversZ then
                local target = (block.sx + other.sx) * 0.5
                if math.abs(dx - target) <= epsilon then hidden["x+"] = true end
                if math.abs(dx + target) <= epsilon then hidden["x-"] = true end
            end
            if coversX and coversZ then
                local target = (block.sy + other.sy) * 0.5
                if math.abs(dy - target) <= epsilon then hidden["y+"] = true end
                if math.abs(dy + target) <= epsilon then hidden["y-"] = true end
            end
            if coversX and coversY then
                local target = (block.sz + other.sz) * 0.5
                if math.abs(dz - target) <= epsilon then hidden["z+"] = true end
                if math.abs(dz + target) <= epsilon then hidden["z-"] = true end
            end
        end
    end
    for _, face in ipairs(TRANSPARENT_FACE_KEYS) do
        signature[#signature + 1] = hidden[face] and "1" or "0"
    end
    return hidden, block.materialId .. ":" .. table.concat(signature)
end

function BuilderWorld:RefreshTransparentTopology(force)
    local transparentGroups = {}
    for _, block in ipairs(self.blocks) do
        local baseSignature = self:BaseGeometrySignature(block.shapeId)
        if Catalog.FindMaterial(block.materialId).transparent and block.shapeId == "box" then
            local group = transparentGroups[block.materialId]
            if not group then group = {}; transparentGroups[block.materialId] = group end
            group[#group + 1] = block
        elseif block.geometrySignature ~= baseSignature then
            -- Face suppression is box-specific. Curved and faceted transparent
            -- shapes retain their complete geometry so they never lose faces.
            self:ReplaceBlockGeometry(block, self:GeometryForShape(block.shapeId), baseSignature)
        end
    end
    for _, transparentBlocks in pairs(transparentGroups) do
        for _, block in ipairs(transparentBlocks) do
            local hidden, faceSignature = self:GetTransparentFaceMask(block, transparentBlocks)
            local signature = "transparent-box:" .. faceSignature
            if force or block.geometrySignature ~= signature then
                local alpha = block.materialId == "water" and 0.7 or 1
                self:ReplaceBlockGeometry(block, TransparentBlockGeometry.new(hidden, alpha), signature)
            end
        end
    end
end

function BuilderWorld:DestroyRecords()
    if self.root then
        self.scene:remove(self.root)
        self.root:getNode():Remove()
    end
    self.root = THREE.Group()
    self.scene:add(self.root)
    self.blocks, self.byId = {}, {}
    self.objectListCache = nil
    self.transformAttached = false
    self.precisionJoystickActive = false
    self.precisionJoystickSnapshot = nil
    self:MarkShadowQualityDirty()
end

function BuilderWorld:RemoveRecord(block)
    if not block then return end
    self.root:remove(block.mesh)
    block.mesh:getNode():Remove()
    self.byId[block.id] = nil
    for index, candidate in ipairs(self.blocks) do
        if candidate == block then table.remove(self.blocks, index); break end
    end
    self.objectListCache = nil
    if self.selectedId == block.id then
        self.selectedId = nil
        self.transformAttached = false
    end
    self:MarkShadowQualityDirty()
end

function BuilderWorld:ApplyBlockToMesh(block)
    if not block or not block.mesh then return end
    block.mesh.position:set(block.x, block.y, block.z)
    block.mesh.scale:set(block.sx, block.sy, block.sz)
    block.mesh.rotation:set(block.rx, block.ry, block.rz)
    block.mesh.material = self:MaterialFor(block.materialId, block.color)
    if not self.mobileDevice then
        block.mesh.castShadow = not Catalog.FindMaterial(block.materialId).transparent
    end
    self:RefreshHelpers()
end

function BuilderWorld:Snapshot()
    local blocks = CopyBlocks(self.blocks)
    for _, block in ipairs(blocks) do
        for _, key in ipairs({ "x", "y", "z", "sx", "sy", "sz", "rx", "ry", "rz" }) do
            block[key] = CleanNumber(block[key])
        end
    end
    return blocks
end

function BuilderWorld:PushHistory(snapshot)
    self.liveInspectorKey = nil
    self.history[#self.history + 1] = snapshot or self:Snapshot()
    if #self.history > 60 then table.remove(self.history, 1) end
    self.future = {}
end

function BuilderWorld:Restore(blocks, message, persist)
    self:DestroyRecords()
    self.liveInspectorKey = nil
    self.colorPickTarget = nil
    self.colorPickImage = nil
    self.colorPickCaptureFrames = 0
    self.nextId, self.selectedId, self.transformAttached = 1, nil, false
    for _, source in ipairs(blocks or {}) do self:CreateRecord(source) end
    self:RefreshTransparentTopology(true)
    self:RefreshHelpers()
    if persist then self:Commit(message or "已恢复模型") else self:Notify(message or "已恢复模型") end
end

function BuilderWorld:GetSelected()
    return self.selectedId and self.byId[self.selectedId] or nil
end

function BuilderWorld:FocusSelected()
    local block = self:GetSelected()
    if not block then
        self:Notify("请先选择一个积木")
        return false
    end
    self:StopCameraMotion()
    self.cameraFocusAnimation = {
        elapsed = 0,
        duration = self.mobileEditor and 0.38 or 0.46,
        fromX = self.target.x,
        fromY = self.target.y,
        fromZ = self.target.z,
        toX = block.x,
        toY = block.y,
        toZ = block.z,
    }
    self:Notify("正在聚焦 · " .. tostring(block.name or "选中积木"))
    return true
end

function BuilderWorld:Select(block)
    self.liveInspectorKey = nil
    self.selectedId = block and block.id or nil
    self.transformAttached = block ~= nil
    self:SetGizmoHighlight(nil)
    self:HideDragHelpers()
    self:MarkShadowQualityDirty()
    self:RefreshHelpers()
    self:RefreshState()
end

function BuilderWorld:SelectById(id)
    self:Select(self.byId[tonumber(id)])
end

function BuilderWorld:HasCollision(candidate, ignoreId)
    for _, block in ipairs(self.blocks) do
        if block.id ~= ignoreId and Intersects(candidate, block, 0.015) then return true end
    end
    return false
end

function BuilderWorld:IsInViewport(x, y)
    local rect = self.viewportRect
    return x >= rect.left and x < rect.right and y >= rect.top and y < rect.bottom
end

function BuilderWorld:SetViewportRect(left, top, right, bottom, uiScale, editorMode)
    local width, height = graphics:GetWidth(), graphics:GetHeight()
    left = Clamp(math.floor(left + 0.5), 0, width - 1)
    top = Clamp(math.floor(top + 0.5), 0, height - 1)
    right = Clamp(math.floor(right + 0.5), left + 1, width)
    bottom = Clamp(math.floor(bottom + 0.5), top + 1, height)
    self.viewportRect = { left = left, top = top, right = right, bottom = bottom }
    self.uiScale = uiScale or self.uiScale
    self.mobileEditor = editorMode == "mobile"
    self.transformSize = self.mobileEditor and 2.0 or 0.8
    -- Keep the native render projection, THREE.Vector3:project and
    -- Viewport:GetScreenRay on the exact same sub-viewport aspect ratio.
    -- Relying on the engine's deferred auto-aspect update leaves one frame of
    -- stale projection after phone rotation/UI rebuild and makes a visible
    -- gizmo disagree with its touch ray.
    local nativeCamera = self.camera and self.camera.getCamera and self.camera:getCamera() or nil
    if nativeCamera then
        if nativeCamera.SetAutoAspectRatio then nativeCamera:SetAutoAspectRatio(false) end
        nativeCamera.aspectRatio = math.max(1, right - left) / math.max(1, bottom - top)
    end
    if self.materialSystem:SetMobileWater(editorMode == "mobile") then
        for _, block in ipairs(self.blocks) do
            if block.materialId == "water" and block.mesh then
                block.mesh.material = self:MaterialFor(block.materialId, block.color, true)
            end
        end
    end
    if self.viewport then self.viewport:SetRect(IntRect(left, top, right, bottom)) end
    if self.transformOverlay then self.transformOverlay:SetRect(IntRect(left, top, right, bottom)) end
    self:UpdateBackdrop()
    self:RefreshHelpers()
end

function BuilderWorld:SetMobileGizmoSuppressed(suppressed)
    local value = suppressed and true or false
    if self.mobileGizmoSuppressed == value then return end
    self.mobileGizmoSuppressed = value
    self:RefreshHelpers()
end

function BuilderWorld:UpdateBackdrop()
    if not self.checkerBackdrop then return end
    local rect = self.viewportRect
    local width, height = math.max(1, rect.right - rect.left), math.max(1, rect.bottom - rect.top)
    local distance = 220
    local planeHeight = 2 * distance * math.tan((self.camera and self.camera.fov or 36) * DEG * 0.5)
    local planeWidth = planeHeight * width / height
    self.checkerBackdrop.scale:set(planeWidth * 1.04, planeHeight * 1.04, 1)
    self.checkerTexture.repeat_ = { x = width / (22 * self.uiScale), y = height / (22 * self.uiScale) }
    local native = self.checkerMaterial:getNative()
    if native and native.SetUVTransform then
        native:SetUVTransform(Vector2(0, 0), 0, Vector2(self.checkerTexture.repeat_.x, self.checkerTexture.repeat_.y))
    end
end

function BuilderWorld:GetScreenRay(x, y)
    -- Render projection and touch picking must use one exact inverse pair.
    -- Normalizing inside the active inset viewport avoids DPR/safe-area drift
    -- from Viewport:GetScreenRay's platform-specific pixel conversion.
    return ViewportCoordinates.GetScreenRay(self.camera, self.viewportRect, x, y)
end

function BuilderWorld:Raycast(x, y)
    if not self:IsInViewport(x, y) then return nil, nil, nil end
    local ray = self:GetScreenRay(x, y)
    if not ray then return nil, nil, nil end
    local bestBlock, bestNormal, bestDistance = nil, nil, 10000
    local results = self.octree and self.octree:Raycast(
        ray,
        RAY_TRIANGLE,
        bestDistance,
        DRAWABLE_GEOMETRY,
        MakerTransformControls.SCENE_MASK
    ) or {}
    for _, result in ipairs(results) do
        local nodeName = result.node and tostring(result.node.name or "") or ""
        local blockId = tonumber(nodeName:match("^Block_(%d+)$"))
        local block = blockId and self.byId[blockId] or nil
        if block and result.distance >= 0 and result.distance < bestDistance then
            bestBlock, bestNormal, bestDistance = block, result.normal, result.distance
        end
    end
    local groundDistance = nil
    if math.abs(ray.direction.y) > 0.00001 then
        local distance = -ray.origin.y / ray.direction.y
        if distance >= 0 then
            local groundPoint = ray.origin + ray.direction * distance
            if math.abs(groundPoint.x) <= 40 and math.abs(groundPoint.z) <= 40 then groundDistance = distance end
        end
    end
    if bestBlock and (not groundDistance or bestDistance <= groundDistance) then
        return bestBlock, bestNormal, ray.origin + ray.direction * bestDistance
    end
    if groundDistance then return nil, Vector3.UP, ray.origin + ray.direction * groundDistance end
    return nil, nil, nil
end

function BuilderWorld:PlaceBlock(point, normal, targetBlock)
    local sx, sy, sz = self.newSize[1], self.newSize[2], self.newSize[3]
    local nx, ny, nz = 0, 0, 0
    local ax, ay, az = math.abs(normal.x), math.abs(normal.y), math.abs(normal.z)
    if ax >= ay and ax >= az then nx = normal.x >= 0 and 1 or -1
    elseif ay >= az then ny = normal.y >= 0 and 1 or -1
    else nz = normal.z >= 0 and 1 or -1 end
    local shape = Catalog.FindShape(self.shapeId)
    local candidate = {
        name = "新" .. shape.name, type = "block",
        x = point.x,
        y = point.y,
        z = point.z,
        sx = sx, sy = sy, sz = sz,
        rx = 0, ry = 0, rz = 0,
        color = self.newColor,
        materialId = self.newMaterialId,
        shapeId = shape.id,
    }

    if targetBlock then
        -- CAD-style face placement: use the clicked block as the reference,
        -- align both in-plane centre axes, then put the new block exactly
        -- against the chosen outer face. Different sizes stay centred; equal
        -- sizes become flush without a visual gap.
        local targetHalf = WorldHalfExtents(targetBlock)
        local candidateHalf = WorldHalfExtents(candidate)
        candidate.x, candidate.y, candidate.z = targetBlock.x, targetBlock.y, targetBlock.z
        if nx ~= 0 then candidate.x = targetBlock.x + nx * (targetHalf.x + candidateHalf.x)
        elseif ny ~= 0 then candidate.y = targetBlock.y + ny * (targetHalf.y + candidateHalf.y)
        else candidate.z = targetBlock.z + nz * (targetHalf.z + candidateHalf.z) end
    else
        local candidateHalf = WorldHalfExtents(candidate)
        candidate.x = SnapValue(point.x + nx * candidateHalf.x, self.snap)
        candidate.y = SnapValue(point.y + ny * candidateHalf.y, self.snap)
        candidate.z = SnapValue(point.z + nz * candidateHalf.z, self.snap)
        if ny > 0 and candidate.y < candidateHalf.y then candidate.y = candidateHalf.y end
    end
    local step = self.snap > 0 and self.snap or 0.1
    local attempts = 0
    while attempts < 16 and self:HasCollision(candidate, nil) do
        candidate.x = candidate.x + nx * step
        candidate.y = candidate.y + ny * step
        candidate.z = candidate.z + nz * step
        attempts = attempts + 1
    end
    self:PushHistory()
    self:CreateRecord(candidate)
    self:Select(nil)
    self:Commit("已放置积木")
end

function BuilderWorld:Tap(x, y)
    local block, normal, point = self:Raycast(x, y)
    if self.mode == "delete" then
        if not block then return end
        self:PushHistory()
        self:RemoveRecord(block)
        self:Commit("已拆除积木")
    elseif self.mode == "add" then
        if not point then return end
        self:PlaceBlock(point, normal, block)
    else
        self:Select(block)
    end
end

function BuilderWorld:IsColorPicking()
    return self.colorPickTarget ~= nil
end

function BuilderWorld:BeginColorPick(target)
    if target ~= "new" and target ~= "selected" then return false end
    if target == "selected" and not self:GetSelected() then
        self:Notify("请先选择要修改颜色的积木")
        return false
    end
    if self.colorPickTarget == target then
        return self:CancelColorPick("已取消吸管取色")
    end
    self:CancelTransformDrag()
    self:ClearTransformHover()
    -- Native eyedropper freezes the page under the lens. Stop every pending
    -- OrbitControls inertia component before the snapshot is captured.
    self.deltaTheta, self.deltaPhi, self.radiusScale = 0, 0, 1
    self.panOffsetX, self.panOffsetY, self.panOffsetZ = 0, 0, 0
    self.colorPickTarget = target
    self.colorPickImage = nil
    -- Capture only from EndRendering. Reading the framebuffer from Update can
    -- see an unfinished/cleared back buffer instead of the frame under cursor.
    self.colorPickCaptureFrames = 1
    input.mouseVisible = false
    self:Notify(target == "selected"
        and "吸管已开启：点击工作台任意位置，将屏幕颜色应用到当前积木"
        or "吸管已开启：点击工作台任意位置，将屏幕颜色用于新积木")
    return true
end

function BuilderWorld:CancelColorPick(message)
    if not self.colorPickTarget then return false end
    self.colorPickTarget = nil
    self.colorPickImage = nil
    self.colorPickCaptureFrames = 0
    input.mouseVisible = true
    self:Notify(message or "已取消吸管取色")
    return true
end

function BuilderWorld:CaptureColorPickImage()
    if not self.colorPickTarget then return false end
    local image = Image()
    local captured = graphics:TakeScreenShot(image)
    -- Some runtime bindings populate the destination image even when the
    -- native return value is absent. Image dimensions are the final authority.
    if (captured == false) or image.width <= 0 or image.height <= 0 then return false end
    self.colorPickImage = image
    self.colorPickCaptureFrames = 0
    return true
end

function BuilderWorld:CapturePendingColorPickFrame()
    if not self.colorPickTarget or self.colorPickImage then return false end
    if self.colorPickCaptureFrames > 0 then
        self.colorPickCaptureFrames = self.colorPickCaptureFrames - 1
    end
    if self.colorPickCaptureFrames > 0 then return false end
    return self:CaptureColorPickImage()
end

function BuilderWorld:GetColorPickPreview(x, y, radius)
    if not self.colorPickTarget then return nil end
    -- Do not snapshot from a pointer event fired in the same frame that closed
    -- the color popup. EndRendering captures the first fully completed frame.
    if self.colorPickCaptureFrames > 0 then return nil end
    if not self.colorPickImage and not self:CaptureColorPickImage() then return nil end
    radius = math.max(2, math.min(8, math.floor(tonumber(radius) or 5)))
    local size = radius * 2 + 1
    local pixels = {}
    for row = -radius, radius do
        for column = -radius, radius do
            local color = ImagePixel(self.colorPickImage, x + column, y + row)
            pixels[#pixels + 1] = {
                math.floor(Clamp((color and color.r or 0) * 255 + 0.5, 0, 255)),
                math.floor(Clamp((color and color.g or 0) * 255 + 0.5, 0, 255)),
                math.floor(Clamp((color and color.b or 0) * 255 + 0.5, 0, 255)),
                255,
            }
        end
    end
    return {
        size = size,
        pixels = pixels,
        hex = ColorHex(ImagePixel(self.colorPickImage, x, y)),
    }
end

function BuilderWorld:PickSceneColor(x, y, previewHex)
    local target = self.colorPickTarget
    if not target then return false end
    -- Keep the picker active if the user presses before the rendered-frame handoff;
    -- committing a stale framebuffer could sample the popup instead of scene.
    if self.colorPickCaptureFrames > 0 then return false end
    if not self.colorPickImage and not self:CaptureColorPickImage() then
        self:Notify("屏幕颜色读取失败，请重新取色")
        return false
    end
    -- Commit the exact centre color displayed by the loupe. Falling back to
    -- the frozen image keeps direct/non-UI callers working as before.
    local pickedColor = tostring(previewHex or ""):match("^#%x%x%x%x%x%x$")
        and NormalizeHex(previewHex)
        or ColorHex(ImagePixel(self.colorPickImage, x, y))
    if not pickedColor then
        self:Notify("屏幕颜色读取失败，请重新取色")
        return false
    end
    self.colorPickTarget = nil
    self.colorPickImage = nil
    self.colorPickCaptureFrames = 0
    input.mouseVisible = true
    if target == "selected" then
        local destination = self:GetSelected()
        if not destination then
            self:Notify("当前积木已取消选择，吸管取色未应用")
            return false
        end
        self:UpdateInspector("color", pickedColor)
        self:FinishInspectorEdit()
        self:Notify("已吸取 " .. pickedColor .. " · 应用到 " .. tostring(destination.name))
    else
        self:SetNewColor(pickedColor)
        self:Notify("已吸取 " .. pickedColor .. " · 用于新积木")
    end
    return true
end

function BuilderWorld:SetMode(mode)
    self.colorPickTarget = nil
    self.colorPickImage = nil
    self.colorPickCaptureFrames = 0
    input.mouseVisible = true
    self.mode = mode
    self.transformAttached = mode == "select" and self:GetSelected() ~= nil
    self:SetGizmoHighlight(nil)
    self:HideDragHelpers()
    self:RefreshHelpers()
    self:Notify(mode == "add" and "放置模式：点击表面继续搭建" or mode == "delete" and "拆除模式：点击积木删除" or "选择模式：点击积木进行编辑")
end

function BuilderWorld:SetTransformMode(mode)
    self.transformMode = mode
    self:SetGizmoHighlight(nil)
    self:HideDragHelpers()
    self:RefreshHelpers()
    self:RefreshState()
end

function BuilderWorld:SetPreset(id)
    local preset = Catalog.FindPreset(id)
    self.presetId = preset.id
    self.newSize = { preset.size[1], preset.size[2], preset.size[3] }
    self:RefreshState()
end

function BuilderWorld:SetShape(id)
    self.shapeId = Catalog.FindShape(id).id
    self:RefreshState()
end

function BuilderWorld:SetNewSize(axis, value)
    local index = axis == "x" and 1 or axis == "y" and 2 or 3
    local parsed = tonumber(value)
    if parsed == nil or parsed == 0 then parsed = 1 end
    self.newSize[index] = math.max(0.05, parsed)
    self:RefreshState()
end

function BuilderWorld:SetNewColor(value)
    self.colorPickTarget = nil
    self.colorPickImage = nil
    self.colorPickCaptureFrames = 0
    input.mouseVisible = true
    self.newColor = NormalizeHex(value, self.newColor)
    self.paletteActiveId = nil
    for _, color in ipairs(Catalog.COLORS) do
        if color.css == self.newColor then self.paletteActiveId = color.id; break end
    end
    self:RefreshState()
end

function BuilderWorld:SetPaletteColor(id)
    self.colorPickTarget = nil
    self.colorPickImage = nil
    self.colorPickCaptureFrames = 0
    input.mouseVisible = true
    local color = Catalog.FindColor(id)
    self.newColor = color.css
    self.paletteActiveId = color.id
    self:RefreshState()
end

function BuilderWorld:SetNewMaterial(id)
    self.newMaterialId = Catalog.FindMaterial(id).id
    self:RefreshState()
end

function BuilderWorld:SetSelectedMaterial(id)
    local block = self:GetSelected()
    if not block then return end
    local materialId = Catalog.FindMaterial(id).id
    if block.materialId == materialId then return end
    self:PushHistory()
    block.materialId = materialId
    block.mesh.material = self:MaterialFor(block.materialId, block.color, true)
    if not self.mobileDevice then
        block.mesh.castShadow = not Catalog.FindMaterial(block.materialId).transparent
    end
    self:MarkShadowQualityDirty()
    self.objectListCache = nil
    self:RefreshHelpers()
    self:Commit("已应用" .. Catalog.FindMaterial(materialId).name .. "材质")
end

function BuilderWorld:SetSelectedShape(id)
    local block = self:GetSelected()
    if not block then return end
    local shape = Catalog.FindShape(id)
    if block.shapeId == shape.id then return end
    self:PushHistory()
    block.shapeId = shape.id
    self:ReplaceBlockGeometry(
        block,
        self:GeometryForShape(shape.id),
        self:BaseGeometrySignature(shape.id)
    )
    self.objectListCache = nil
    self:Commit("已将积木形状改为" .. shape.name)
end

function BuilderWorld:SetSnap(step)
    self.snap = tonumber(step) or 0
    self:RefreshState()
end

function BuilderWorld:FinishInspectorEdit()
    self.liveInspectorKey = nil
end

function BuilderWorld:ResetSelectedRotation()
    local block = self:GetSelected()
    if not block then return end
    if math.abs(block.rx or 0) < 0.000001
        and math.abs(block.ry or 0) < 0.000001
        and math.abs(block.rz or 0) < 0.000001 then
        self:Notify("当前积木已经回正")
        return
    end
    self:PushHistory()
    block.rx, block.ry, block.rz = 0, 0, 0
    self:ApplyBlockToMesh(block)
    self:Commit("已将积木旋转回正到 0°")
end

function BuilderWorld:UpdateInspector(key, value)
    local block = self:GetSelected()
    if not block then return end
    if key == "color" then
        self.colorPickTarget = nil
        self.colorPickImage = nil
        self.colorPickCaptureFrames = 0
        input.mouseVisible = true
    end
    local nextValue
    if key == "name" then
        nextValue = tostring(value or ""):match("^%s*(.-)%s*$")
        if nextValue == "" then return end
    elseif key == "color" then
        nextValue = NormalizeHex(value, block.color)
    elseif key == "x" or key == "y" or key == "z" then
        if tostring(value or ""):match("^%s*$") then return end
        nextValue = HtmlNumber(value)
        if nextValue == nil then return end
    elseif key == "sx" or key == "sy" or key == "sz" then
        if tostring(value or ""):match("^%s*$") then return end
        nextValue = HtmlNumber(value)
        if nextValue == nil then return end
        nextValue = math.max(0.05, nextValue)
    elseif key == "rotX" or key == "rotY" or key == "rotZ" then
        if tostring(value or ""):match("^%s*$") then return end
        nextValue = HtmlNumber(value)
        if nextValue == nil then return end
        nextValue = nextValue * DEG
    else
        return
    end

    local storageKey = key == "rotX" and "rx" or key == "rotY" and "ry" or key == "rotZ" and "rz" or key
    local previous = block[storageKey]
    if type(previous) == "number" and type(nextValue) == "number" then
        if math.abs(previous - nextValue) < 0.000001 then return end
    elseif previous == nextValue then
        return
    end
    if self.liveInspectorKey ~= key then
        self:PushHistory()
        self.liveInspectorKey = key
    end
    block[storageKey] = nextValue
    if key == "name" or key == "color" then self.objectListCache = nil end
    if key == "color" then
        -- Force both the material wrapper and the native drawable to refresh.
        -- Reassigning a cached material alone is not sufficient on every
        -- runtime backend when the same material was already bound.
        -- Force a fresh native material binding. Reusing a cached wrapper can
        -- leave the old shader parameters attached on some runtime backends.
        local material = self:MaterialFor(block.materialId, block.color, true)
        block.mesh.material = material
        self:RefreshHelpers()
    else
        self:ApplyBlockToMesh(block)
    end
    self:Commit("已实时更新积木")
end

function BuilderWorld:DuplicateSelected()
    local block = self:GetSelected()
    if not block then return false end
    local copy = CopyBlock(block)
    copy.id = nil
    copy.name = NextDuplicateName(self.blocks, block.name)
    local sourceHalf = WorldHalfExtents(block)
    local copyHalf = WorldHalfExtents(copy)
    local candidates = {
        { x = block.x + sourceHalf.x + copyHalf.x, z = block.z },
        { x = block.x - sourceHalf.x - copyHalf.x, z = block.z },
        { x = block.x, z = block.z + sourceHalf.z + copyHalf.z },
        { x = block.x, z = block.z - sourceHalf.z - copyHalf.z },
    }
    local positionFound = false
    for _, candidate in ipairs(candidates) do
        copy.x, copy.y, copy.z = candidate.x, block.y, candidate.z
        if not self:HasCollision(copy, nil) then
            positionFound = true
            break
        end
    end
    if not positionFound then
        self:Notify("选中组件四周没有足够的复制空间")
        return false
    end

    self:PushHistory()
    local created = self:CreateRecord(copy)
    self.selectedId = created.id
    self.transformAttached = true
    self:Commit("已复制到旁边")
    return true
end

function BuilderWorld:DeleteSelected()
    local block = self:GetSelected()
    if not block then return end
    self:PushHistory()
    self:RemoveRecord(block)
    self:Commit("已拆除积木")
end

function BuilderWorld:Undo()
    if #self.history == 0 then return end
    self.future[#self.future + 1] = self:Snapshot()
    local previous = table.remove(self.history)
    self:Restore(previous, "已撤销", true)
end

function BuilderWorld:Redo()
    if #self.future == 0 then return end
    self.history[#self.history + 1] = self:Snapshot()
    local nextState = table.remove(self.future)
    self:Restore(nextState, "已重做", true)
end

function BuilderWorld:NewProject()
    self:PushHistory()
    self:Restore({}, "已新建空白模型", true)
end

function BuilderWorld:LoadExample(recordHistory)
    if recordHistory ~= false then self:PushHistory() end
    self:Restore(HouseTemplate.Build(), "已载入可编辑小屋模板", true)
    self:SetView("iso", true)
end

function BuilderWorld:GetProjectData()
    local blocks = {}
    for index, block in ipairs(self.blocks) do
        blocks[index] = {
            id = block.id,
            name = block.name,
            type = block.type,
            position = { CleanNumber(block.x), CleanNumber(block.y), CleanNumber(block.z) },
            size = { CleanNumber(block.sx), CleanNumber(block.sy), CleanNumber(block.sz) },
            rotation = { CleanNumber(block.rx), CleanNumber(block.ry), CleanNumber(block.rz) },
            color = block.color,
            materialId = block.materialId,
            shapeId = block.shapeId,
        }
    end
    return { version = 3, name = "我的空岛模型", blocks = blocks }
end

function BuilderWorld:SetTemplateLibrary(items)
    self.templateSummaries = {}
    for _, item in ipairs(items or {}) do
        self.templateSummaries[#self.templateSummaries + 1] = {
            id = item.id,
            name = item.name or "未命名模型",
            count = type(item.blocks) == "table" and #item.blocks or 0,
            builtin = item.builtin == true,
            category = item.category,
            description = item.description,
            sourceAsset = item.sourceAsset,
            source = item.source or (item.builtin and "builtin" or "mine"),
            sourceName = item.sourceName,
            author = item.author,
            favorite = item.favorite == true,
            license = item.license,
            versionId = item.versionId,
        }
    end
    self:RefreshState()
end

function BuilderWorld:GetTemplateData(name)
    if #self.blocks == 0 then return nil end
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, block in ipairs(self.blocks) do
        local half = WorldHalfExtents(block)
        minX, maxX = math.min(minX, block.x - half.x), math.max(maxX, block.x + half.x)
        minY, maxY = math.min(minY, block.y - half.y), math.max(maxY, block.y + half.y)
        minZ, maxZ = math.min(minZ, block.z - half.z), math.max(maxZ, block.z + half.z)
    end
    local centerX, centerZ = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
    local blocks = {}
    for index, block in ipairs(self.blocks) do
        blocks[index] = {
            name = block.name,
            type = block.type,
            position = { CleanNumber(block.x - centerX), CleanNumber(block.y - minY), CleanNumber(block.z - centerZ) },
            size = { CleanNumber(block.sx), CleanNumber(block.sy), CleanNumber(block.sz) },
            rotation = { CleanNumber(block.rx), CleanNumber(block.ry), CleanNumber(block.rz) },
            color = block.color,
            materialId = block.materialId,
            shapeId = block.shapeId,
        }
    end
    return { version = 3, name = name or "我的模型", blocks = blocks }
end

function BuilderWorld:InsertTemplate(data)
    if type(data) ~= "table" or type(data.blocks) ~= "table" or #data.blocks == 0 then
        self:Notify("模型为空，无法插入")
        return false
    end
    local templateMinX = math.huge
    for _, source in ipairs(data.blocks) do
        local position, size = source.position or {}, source.size or {}
        local bounds = Catalog.FindShape(source.shapeId or source.shape).bounds
        templateMinX = math.min(templateMinX,
            (tonumber(source.x or position[1]) or 0)
                - (tonumber(source.sx or size[1]) or 1) * bounds[1] * 0.5
        )
    end
    local offsetX = 0
    if #self.blocks > 0 then
        local existingMaxX = -math.huge
        for _, block in ipairs(self.blocks) do
            existingMaxX = math.max(existingMaxX, block.x + WorldHalfExtents(block).x)
        end
        offsetX = existingMaxX + 1 - templateMinX
    end
    self:PushHistory()
    for _, source in ipairs(data.blocks) do
        local position, size, rotation = source.position or {}, source.size or {}, source.rotation or {}
        self:CreateRecord({
            name = source.name,
            type = source.type,
            position = {
                (tonumber(source.x or position[1]) or 0) + offsetX,
                tonumber(source.y or position[2]) or 0.5,
                tonumber(source.z or position[3]) or 0,
            },
            size = {
                tonumber(source.sx or size[1]) or 1,
                tonumber(source.sy or size[2]) or 1,
                tonumber(source.sz or size[3]) or 1,
            },
            rotation = {
                tonumber(source.rx or rotation[1]) or 0,
                tonumber(source.ry or rotation[2]) or 0,
                tonumber(source.rz or rotation[3]) or 0,
            },
            color = source.color,
            materialId = source.materialId or source.material,
            shapeId = source.shapeId or source.shape,
        })
    end
    self:Select(nil)
    self:Commit("已插入模型 · " .. tostring(data.name or "我的模型"))
    return true
end

function BuilderWorld:ExportJSON()
    return PrettyJSON(self:GetProjectData())
end

function BuilderWorld:ImportJSON(raw)
    local ok, data = pcall(cjson.decode, tostring(raw or ""))
    if not ok or type(data) ~= "table" or type(data.blocks) ~= "table" then
        self:Notify("导入失败：没有有效的模型工程 JSON")
        return false
    end
    if data.version ~= nil and tonumber(data.version) ~= 3 then
        self:Notify("导入失败：不支持这个模型 JSON 版本")
        return false
    end
    if #data.blocks > 4000 then
        self:Notify("导入失败：模型积木数量超过 4000 个")
        return false
    end
    self:PushHistory()
    self:Restore(data.blocks, "已导入 " .. tostring(#data.blocks) .. " 个积木", true)
    return true
end

function BuilderWorld:LoadProjectData(data, message)
    if type(data) ~= "table" or type(data.blocks) ~= "table" then return false end
    self:Restore(data.blocks, message or ("已恢复上次工程 · " .. tostring(#data.blocks) .. " 个积木"), false)
    return true
end

function BuilderWorld:SetSphericalFromCamera()
    local dx = self.camera.position.x - self.target.x
    local dy = self.camera.position.y - self.target.y
    local dz = self.camera.position.z - self.target.z
    self.radius = math.max(0.001, math.sqrt(dx * dx + dy * dy + dz * dz))
    self.theta = math.atan(dx, dz)
    self.phi = math.acos(Clamp(dy / self.radius, -1, 1))
end

function BuilderWorld:ApplyCameraSpherical()
    local sinPhi = math.sin(self.phi)
    self.camera.position:set(
        self.target.x + self.radius * sinPhi * math.sin(self.theta),
        self.target.y + self.radius * math.cos(self.phi),
        self.target.z + self.radius * sinPhi * math.cos(self.theta)
    )
    self.camera:lookAt(self.target)
    self:RefreshHelpers()
end

function BuilderWorld:OrbitByPixels(dx, dy)
    self.cameraFocusAnimation = nil
    local height = math.max(1, self.viewportRect.bottom - self.viewportRect.top)
    self.deltaTheta = self.deltaTheta - TAU * dx / height
    self.deltaPhi = self.deltaPhi - TAU * dy / height
end

function BuilderWorld:StopCameraMotion()
    self.deltaTheta, self.deltaPhi, self.radiusScale = 0, 0, 1
    self.panOffsetX, self.panOffsetY, self.panOffsetZ = 0, 0, 0
    self.cameraFocusAnimation = nil
end

function BuilderWorld:PanByPixels(dx, dy, isGesture)
    self.cameraFocusAnimation = nil
    local viewX = self.target.x - self.camera.position.x
    local viewY = self.target.y - self.camera.position.y
    local viewZ = self.target.z - self.camera.position.z
    local viewLength = math.sqrt(viewX * viewX + viewY * viewY + viewZ * viewZ)
    if viewLength < 0.001 then return end
    viewX, viewY, viewZ = viewX / viewLength, viewY / viewLength, viewZ / viewLength
    -- Three OrbitControls pans in camera-right/camera-up space. The previous
    -- basis was camera-left/down, which made two-finger panning feel reversed.
    local rightX, rightZ = -viewZ, viewX
    local rightLength = math.sqrt(rightX * rightX + rightZ * rightZ)
    if rightLength > 0.001 then rightX, rightZ = rightX / rightLength, rightZ / rightLength end
    local upX = -rightZ * viewY
    local upY = rightZ * viewX - rightX * viewZ
    local upZ = rightX * viewY
    local height = math.max(1, self.viewportRect.bottom - self.viewportRect.top)
    local scale = 2 * self.radius * math.tan((self.camera.fov or 36) * DEG * 0.5) / height
    -- Close-up perspective makes the mathematically correct world delta very
    -- small. A bounded inverse-zoom gain keeps mouse and two-finger panning
    -- responsive after zooming in without making distant views oversensitive.
    local closeUpGain = Clamp(math.sqrt(8 / math.max(self.radius, 0.25)), 1, 2.5)
    -- A two-finger midpoint is visually controlled by two contacts and needs
    -- a slightly quicker response than a mouse drag. Keep the gain bounded so
    -- the point under the fingers remains stable rather than jumping.
    local inputGain = isGesture and (self.mobileEditor and 1.45 or 1.25) or 1.15
    scale = scale * closeUpGain * inputGain
    -- Apply panning immediately. The former inertial accumulator moved only
    -- eight percent per frame, which made the workbench feel as if its view
    -- centre were locked even though a delayed target change existed.
    self.target:set(
        self.target.x + (-dx * rightX + dy * upX) * scale,
        self.target.y + dy * upY * scale,
        self.target.z + (-dx * rightZ + dy * upZ) * scale
    )
    self.panOffsetX, self.panOffsetY, self.panOffsetZ = 0, 0, 0
    self:ApplyCameraSpherical()
end

function BuilderWorld:Zoom(factor)
    factor = tonumber(factor)
    if not factor or factor <= 0 then return end
    self.cameraFocusAnimation = nil
    self.radius = math.max(0.001, self.radius * factor)
    self:ApplyCameraSpherical()
end

function BuilderWorld:ZoomByGesture(factor)
    factor = tonumber(factor)
    if not factor or factor <= 0 then return end
    local response = self.mobileEditor and 1.45 or 1.2
    self:Zoom(factor ^ response)
end

function BuilderWorld:SetView(name, silent)
    self.cameraFocusAnimation = nil
    -- Direction presets must not recenter the editor. Preserve the freely
    -- panned target and only move the camera to the requested orientation.
    local tx, ty, tz = self.target.x, self.target.y, self.target.z
    if name == "front" then self.camera.position:set(tx, ty + 2.3, tz + 22)
    elseif name == "right" then self.camera.position:set(tx + 22, ty + 2.3, tz)
    elseif name == "top" then self.camera.position:set(tx + 0.01, ty + 19.3, tz + 0.01)
    else self.camera.position:set(tx + 13, ty + 8.3, tz + 15) end
    self.camera:lookAt(self.target)
    self:SetSphericalFromCamera()
    self.deltaTheta, self.deltaPhi, self.radiusScale = 0, 0, 1
    self.panOffsetX, self.panOffsetY, self.panOffsetZ = 0, 0, 0
    self:RefreshHelpers()
    if not silent then self:RefreshState() end
end


function BuilderWorld:Update(timeStep)
    if self.shadowQualityDirty then self:ApplyRenderQuality() end
    if self.colorPickTarget then
        -- EndRendering owns the frozen screenshot; Update only freezes every
        -- camera and scene mutation while the exclusive picker is active.
        return
    end
    local cameraChanged = false
    local focus = self.cameraFocusAnimation
    if focus then
        focus.elapsed = math.min(focus.duration, focus.elapsed + Clamp(tonumber(timeStep) or 0, 0, 0.1))
        local progress = SmoothStep(focus.elapsed / math.max(0.001, focus.duration))
        self.target:set(
            focus.fromX + (focus.toX - focus.fromX) * progress,
            focus.fromY + (focus.toY - focus.fromY) * progress,
            focus.fromZ + (focus.toZ - focus.fromZ) * progress
        )
        if focus.elapsed >= focus.duration then self.cameraFocusAnimation = nil end
        cameraChanged = true
    end
    if math.abs(self.deltaTheta) > 0.00001 or math.abs(self.deltaPhi) > 0.00001 then
        -- Preserve the total orbit distance while applying more of it in the
        -- current frame. This removes the sluggish phone feel and shortens the
        -- period in which inertia could move the camera under a new tap.
        local response = self.mobileEditor and 0.2 or 0.12
        local damping = 1 - response
        self.theta = self.theta + self.deltaTheta * response
        self.phi = Clamp(self.phi + self.deltaPhi * response, 0.000001, math.pi - 0.000001)
        self.deltaTheta = self.deltaTheta * damping
        self.deltaPhi = self.deltaPhi * damping
        cameraChanged = true
    end
    if math.abs(self.panOffsetX) > 0.000001 or math.abs(self.panOffsetY) > 0.000001 or math.abs(self.panOffsetZ) > 0.000001 then
        self.target:set(
            self.target.x + self.panOffsetX * 0.08,
            self.target.y + self.panOffsetY * 0.08,
            self.target.z + self.panOffsetZ * 0.08
        )
        self.panOffsetX, self.panOffsetY, self.panOffsetZ = self.panOffsetX * 0.92, self.panOffsetY * 0.92, self.panOffsetZ * 0.92
        cameraChanged = true
    end
    -- ApplyCameraSpherical already refreshes all camera-dependent helpers.
    -- When the scene is idle there is nothing to recompute; transform and
    -- selection mutations refresh helpers at their mutation sites.
    if cameraChanged then self:ApplyCameraSpherical() end
end

function BuilderWorld:GetState()
    local selected = self:GetSelected()
    local selectedState = selected and CopyBlock(selected) or nil
    if selectedState then
        -- HTML syncRecordFromMesh clamps Inspector size display during a
        -- transient negative scale drag; mouseUp applies the same clamp to the
        -- actual mesh in EndTransformDrag.
        selectedState.sx = math.max(0.05, selectedState.sx)
        selectedState.sy = math.max(0.05, selectedState.sy)
        selectedState.sz = math.max(0.05, selectedState.sz)
    end
    if not self.objectListCache then
        self.objectListCache = {}
        for index = #self.blocks, 1, -1 do
            self.objectListCache[#self.objectListCache + 1] = {
                id = self.blocks[index].id,
                name = self.blocks[index].name,
                color = self.blocks[index].color,
                materialId = self.blocks[index].materialId,
                shapeId = self.blocks[index].shapeId,
            }
        end
    end
    return {
        count = #self.blocks,
        selected = selectedState,
        objects = self.objectListCache,
        templates = self.templateSummaries,
        mode = self.mode,
        transformMode = self.transformMode,
        presetId = self.presetId,
        shapeId = self.shapeId,
        paletteActiveId = self.paletteActiveId,
        newSize = { self.newSize[1], self.newSize[2], self.newSize[3] },
        newColor = self.newColor,
        newMaterialId = self.newMaterialId,
        colorPickTarget = self.colorPickTarget,
        snap = self.snap,
        canUndo = #self.history > 0,
        canRedo = #self.future > 0,
    }
end

function BuilderWorld:Dispose()
    if self.hemisphere and self.hemisphere.dispose then self.hemisphere:dispose() end
    if self.sun and self.sun.dispose then self.sun:dispose() end
    if self.fill and self.fill.dispose then self.fill:dispose() end
    if self.checkerTexture and self.checkerTexture.dispose then self.checkerTexture:dispose() end
    if self.checkerMaterial and self.checkerMaterial.dispose then self.checkerMaterial:dispose() end
    for _, geometry in pairs(self.mobileShapeGeometries or {}) do
        if geometry and geometry.dispose then geometry:dispose() end
    end
    self.mobileShapeGeometries = {}
    if self.materialSystem then self.materialSystem:Dispose() end
    if self.transformPicker then self.transformPicker:Dispose() end
    if self.mobileTransformPicker then self.mobileTransformPicker:Dispose() end
    if self.transformOverlay then self.transformOverlay:Dispose() end
    if self.renderer and self.renderer.dispose then self.renderer:dispose() end
end

BuilderTransformControls.Install(BuilderWorld, {
    DEG = DEG,
    Clamp = Clamp,
    SnapValue = SnapValue,
    CopyBlock = CopyBlock,
    RotateForward = RotateForward,
    RotateInverse = RotateInverse,
})

BuilderWorld._DuplicateBaseName = DuplicateBaseName
BuilderWorld._NextDuplicateName = NextDuplicateName

return BuilderWorld
