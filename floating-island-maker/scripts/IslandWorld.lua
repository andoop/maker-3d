---@diagnostic disable: undefined-global

local THREE = require("urhox-libs/3D")
local Catalog = require("BlockCatalog")
local BlockMaterials = require("BlockMaterials")
local HtmlRoundedBoxGeometry = require("HtmlRoundedBoxGeometry")
local TransparentBlockGeometry = require("TransparentBlockGeometry")
local TransparentFaceIndex = require("TransparentFaceIndex")
local TriangularPrismGeometry = require("TriangularPrismGeometry")
local FacetedSolidGeometry = require("FacetedSolidGeometry")
local FullCylinderGeometry = require("FullCylinderGeometry")
local MakerTransformControls = require("MakerTransformControls")
local IslandLayout = require("IslandLayout")
local IslandTransformGizmo = require("IslandTransformGizmo")
local StorybookIslandData = require("StorybookIslandData")
local StorybookEnvironmentGeometry = require("StorybookEnvironmentGeometry")
local ModelGeometry = require("ModelGeometry")
local DefaultIslandModels = require("DefaultIslandModels")
local Theme = require("CloudAtelierTheme")
local ViewportCoordinates = require("ViewportCoordinates")
local DayNightClock = require("DayNightClock")
local FirstPersonScale = require("FirstPersonScale")
local IslandPicking = require("IslandPicking")
local PortalTemplate = require("PortalTemplate")
local WorldPerformanceBudget = require("WorldPerformanceBudget")
local GeometryToModel = require("urhox-libs/3D/Core/GeometryToModel")
local IslandInstancedMesh = require("IslandInstancedMesh")
local IslandModelBatcher = require("IslandModelBatcher")
local IslandHistoryPlan = require("IslandHistoryPlan")
local IslandHistoryGuard = require("IslandHistoryGuard")
local MobileDetailProjection = require("MobileDetailProjection")
local MobileDetailCost = require("MobileDetailCost")
local MobileRenderDetailPolicy = require("MobileRenderDetailPolicy")
local MobileThermalPolicy = require("MobileThermalPolicy")
local CameraMotionStability = require("CameraMotionStability")
local IncrementalBuildQueue = require("IncrementalBuildQueue")

local IslandWorld = {}
IslandWorld.__index = IslandWorld

local function SetSceneGroupEnabled(object, enabled)
    if not object then return end
    local node = object.getNode and object:getNode() or nil
    if node and node.SetDeepEnabled then
        node:SetDeepEnabled(enabled == true)
    elseif object.traverse then
        object:traverse(function(child) child.visible = enabled == true end)
    else
        object.visible = enabled == true
    end
end

local DEG = math.pi / 180
local TAU = math.pi * 2
local ORBIT_TARGET_Y = -1.0
local MIN_ORBIT_RADIUS = 6
local FIRST_PERSON_HEIGHT = FirstPersonScale.HEIGHT
local FIRST_PERSON_EYE_HEIGHT = FirstPersonScale.EYE_HEIGHT
local FIRST_PERSON_RADIUS = FirstPersonScale.RADIUS
local FIRST_PERSON_STEP_HEIGHT = FirstPersonScale.STEP_HEIGHT
local FIRST_PERSON_JUMP_SPEED = 2.95
local FIRST_PERSON_GRAVITY = 9.8
local FIRST_PERSON_FLIGHT_SPEED = 4.8
local FIRST_PERSON_FLIGHT_FAST_SPEED = 8.2
local FIRST_PERSON_FLIGHT_MAX_Y = 64

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function SmoothStep(value)
    value = Clamp(tonumber(value) or 0, 0, 1)
    return value * value * (3 - 2 * value)
end

local function Clean(value)
    return math.floor((tonumber(value) or 0) * 1000 + 0.5) / 1000
end

local function Now()
    local ok, value = pcall(os.time)
    return ok and tonumber(value) or 0
end

local function NativePlatform()
    local getter = rawget(_G, "GetNativePlatform") or rawget(_G, "GetPlatform")
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter)
    return ok and value or nil
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Copy(key, seen)] = Copy(item, seen) end
    return result
end

local function Snap(value, step)
    step = tonumber(step) or 0
    if step <= 0 then return value end
    return math.floor(value / step + 0.5) * step
end

local function NormalizeAngle(value)
    while value > math.pi do value = value - TAU end
    while value < -math.pi do value = value + TAU end
    return value
end

local function InstanceCopy(instance)
    return {
        id = instance.id,
        assetId = instance.assetId,
        versionId = instance.versionId or "latest",
        x = Clean(instance.x),
        y = Clean(instance.y or 0),
        z = Clean(instance.z),
        rotationY = Clean(instance.rotationY or 0),
        scale = Clean(instance.scale or 1),
        portal = type(instance.portal) == "table" and Copy(instance.portal) or nil,
    }
end

local function SnapshotInstances(instances)
    local result = {}
    for index, instance in ipairs(instances or {}) do result[index] = InstanceCopy(instance) end
    return result
end

-- Incremental loading is normally a render optimization only. A history
-- transaction is the exception: until its target succeeds, persistence must
-- continue to observe the operation-before snapshot.
local function SnapshotWorldInstances(world)
    local stableSources = IslandHistoryGuard.PersistenceSources(
        world and world.activeHistoryTransaction)
    if stableSources then return Copy(stableSources) end
    local pending = world and world.pendingProjectLoad or nil
    local generated = pending and pending.generatedTransaction or nil
    if generated and type(generated.currentSources) == "table" then
        return Copy(generated.currentSources)
    end
    local result, seen = SnapshotInstances(world and world.instances), {}
    for _, instance in ipairs(result) do
        local id = tonumber(instance.id)
        if id then seen[id] = true end
    end
    if pending then
        for index = pending.index, pending.total do
            local source = pending.sources[index]
            local id = source and tonumber(source.id) or nil
            if source and (not id or not seen[id]) then
                result[#result + 1] = InstanceCopy(source)
                if id then seen[id] = true end
            end
        end
    end
    return result
end

local function ReserveInstanceIds(world, sources)
    local nextId = math.max(1, tonumber(world and world.nextId) or 1)
    for _, source in ipairs(sources or {}) do
        nextId = math.max(nextId, (tonumber(source and source.id) or 0) + 1)
    end
    world.nextId = nextId
    return nextId
end

local function ModelPosition(source)
    return ModelGeometry.Position(source)
end

local function ModelSize(source)
    return ModelGeometry.Size(source)
end

local function ModelRotation(source)
    return ModelGeometry.Rotation(source)
end

local function RenderBatchKey(shapeId, materialId, color, castShadow, emissionKind)
    color = tostring(color or "#f2e7cf"):lower():gsub("%s+", "")
    return table.concat({
        tostring(shapeId), tostring(materialId), color,
        castShadow and "shadow" or "plain", tostring(emissionKind or "none"),
    }, "\31")
end

local function BlockTransformMatrix(source)
    local x, y, z = ModelPosition(source)
    local sx, sy, sz = ModelSize(source)
    local rx, ry, rz = ModelRotation(source)
    return THREE.Matrix4():compose(
        THREE.Vector3(x, y, z),
        THREE.Quaternion():setFromEuler(THREE.Euler(rx, ry, rz)),
        THREE.Vector3(sx, sy, sz)
    )
end

-- Only small, fully decorative opaque assets enter the cross-instance baker.
-- Buildings, portals and transparent materials retain the established render
-- path. Eligibility follows the blocks rather than the library category, so a
-- grass model stays protected after a player copies/customises it and Maker
-- moves it into the "我的模型" category.
local bakedDetailEligibility = setmetatable({}, { __mode = "k" })
local groundCoverEligibility = setmetatable({}, { __mode = "k" })
local bakedDetailCost = setmetatable({}, { __mode = "k" })

local function IsBakedDetailAsset(asset)
    if type(asset) ~= "table" then return false end
    local blocks = asset and asset.blocks or {}
    local cached = bakedDetailEligibility[asset]
    if cached and cached.blocks == blocks and cached.count == #blocks then
        return cached.eligible
    end
    local eligible = #blocks > 0 and #blocks <= 48
        and tostring(asset.assetId or "") ~= PortalTemplate.ASSET_ID
    if eligible then
        for _, block in ipairs(blocks) do
            if Catalog.FindMaterial(block.materialId or block.material).transparent
                or ModelGeometry.CollisionRole(block) ~= "decorative"
                or ModelGeometry.ShouldCastShadow(block) then
                eligible = false
                break
            end
        end
    end
    bakedDetailEligibility[asset] = {
        blocks = blocks,
        count = #blocks,
        eligible = eligible,
    }
    return eligible
end

local function IsGroundCoverAsset(asset)
    if type(asset) ~= "table" then return false end
    local cached = groundCoverEligibility[asset]
    if cached ~= nil then return cached end
    local id = tostring(asset.assetId or asset.id or ""):lower()
    local name = tostring(asset.name or ""):lower()
    local category = tostring(asset.category or "")
    local bounds = asset.bounds or {}
    local size = bounds.size or { 1, 1, 1 }
    local compact = (tonumber(size[2]) or 1) <= 2.4
        and math.max(tonumber(size[1]) or 1, tonumber(size[3]) or 1) <= 3.2
    local named = id:find("grass", 1, true) or id:find("flower", 1, true)
        or id:find("fern", 1, true) or id:find("reeds", 1, true)
        or name:find("草", 1, true) or name:find("花", 1, true)
        or name:find("蕨", 1, true) or name:find("芦苇", 1, true)
    local eligible = compact and (named ~= nil or category == "植被单件")
    groundCoverEligibility[asset] = eligible
    return eligible
end

local function NameContains(name, value)
    return tostring(name or ""):find(value, 1, true) ~= nil
end

local function NightEmissionKind(source)
    local materialId = tostring(source.materialId or source.material or "")
    local name = tostring(source.name or "")
    if materialId == "glow" or materialId == "fire" then return "lamp" end
    for _, keyword in ipairs({ "灯芯", "暖光", "星灯", "灯泡", "灯珠", "航标灯", "蘑菇灯", "光源" }) do
        if NameContains(name, keyword) then return "lamp" end
    end
    if materialId == "glass" then
        for _, keyword in ipairs({ "窗", "玻璃门", "玻璃墙", "温室", "穹顶" }) do
            if NameContains(name, keyword) then return "window" end
        end
    end
    return nil
end

local function IsPassableDoorBlock(source)
    if tostring(source.type or "") == "door" then return true end
    local name = tostring(source.name or "")
    if name:lower():find("door", 1, true) then return true end
    for _, excluded in ipairs({ "门楣", "门廊", "门框", "门柱", "门厅", "门牌", "门上", "门后", "拱门", "月门", "洞门" }) do
        if NameContains(name, excluded) then return false end
    end
    if name:find("门$") or NameContains(name, "门窗") or NameContains(name, "门帘") then return true end
    for _, doorway in ipairs({ "主入口", "蓝色入口", "深蓝入口", "木质入口", "入口凹槽", "入口玻璃门" }) do
        if NameContains(name, doorway) then return true end
    end
    return false
end

local function IsWalkSurfaceBlock(source, sx, sy, sz)
    return ModelGeometry.IsWalkSurface(source)
end

local function MakeBoxLines(bounds, padding)
    padding = padding or 0
    local min, max = bounds.min, bounds.max
    local x0, y0, z0 = min[1] - padding, min[2] - padding, min[3] - padding
    local x1, y1, z1 = max[1] + padding, max[2] + padding, max[3] + padding
    local p = {
        THREE.Vector3(x0, y0, z0), THREE.Vector3(x1, y0, z0),
        THREE.Vector3(x1, y0, z0), THREE.Vector3(x1, y0, z1),
        THREE.Vector3(x1, y0, z1), THREE.Vector3(x0, y0, z1),
        THREE.Vector3(x0, y0, z1), THREE.Vector3(x0, y0, z0),
        THREE.Vector3(x0, y1, z0), THREE.Vector3(x1, y1, z0),
        THREE.Vector3(x1, y1, z0), THREE.Vector3(x1, y1, z1),
        THREE.Vector3(x1, y1, z1), THREE.Vector3(x0, y1, z1),
        THREE.Vector3(x0, y1, z1), THREE.Vector3(x0, y1, z0),
        THREE.Vector3(x0, y0, z0), THREE.Vector3(x0, y1, z0),
        THREE.Vector3(x1, y0, z0), THREE.Vector3(x1, y1, z0),
        THREE.Vector3(x1, y0, z1), THREE.Vector3(x1, y1, z1),
        THREE.Vector3(x0, y0, z1), THREE.Vector3(x0, y1, z1),
    }
    return THREE.BufferGeometry():setFromPoints(p)
end

function IslandWorld.new(assetStore, terrainId)
    local self = setmetatable({}, IslandWorld)
    self.assetStore = assetStore
    self.layout = IslandLayout.Resolve(terrainId)
    self.terrainId = self.layout.id
    self.instances, self.byId = {}, {}
    self.rendered = {}
    self.modelRenderBlockCount = 0
    self.modelShadowBlockCount = 0
    self.modelRenderBatchCount = 0
    self.instancedGeometryModels = {}
    self.nextId = 1
    self.selectedId = nil
    self.mode = "select"
    self.readOnly = false
    self.visitOwner, self.visitOwnerId, self.visitAvatar, self.visitIslandId, self.visitName = nil, nil, nil, nil, nil
    self.transformMode = "translate"
    self.placementAssetId = nil
    self.placementVersionId = nil
    self.placementRotation = 0
    self.placementScale = 1
    self.placementValid = false
    self.placementX, self.placementZ = 0, 0
    self.snap = 0.25
    self.history, self.future = {}, {}
    self.pendingProjectLoad = nil
    self.activeHistoryTransaction = nil
    self.pendingPortalActivation = nil
    self.portalTransitionActive = false
    self.portalCooldown = 0
    self.portalContactId = nil
    self.disposed = false
    self.projectRevision = 0
    self.projectUpdatedAt = Now()
    self.onChanged, self.onCommit = nil, nil
    self.libraryTab = "builtin"
    self.librarySummaries = {}
    self.autoBuildSummaries = {}
    self.terrainSummaries = nil
    self.randomTerrainSummaries = {}
    self.terrainDisplayName = self.layout.name
    self.islandSummaries = {}
    self.activeIslandId = nil
    self.islandMarketSyncBusy = false
    self.islandMarketSyncIslandId = nil
    self.viewportRect = { left = 0, top = 0, right = graphics:GetWidth(), bottom = graphics:GetHeight() }
    self.uiScale = math.max(1, graphics:GetDPR())
    self.mobileEditor = MobileThermalPolicy.IsMobileViewport(
        graphics:GetWidth(), graphics:GetHeight(), self.uiScale, NativePlatform())
    self.mobileDevice = MobileThermalPolicy.IsMobileDevice(NativePlatform())
    self.drag = nil
    self.interactiveStateDirty = false
    self.interactiveStateElapsed = 0
    self.renderDetailElapsed = 0
    self.renderDetailRevision = 0
    self.renderDetailDirty = true
    self.renderDetailCandidates = nil
    self.renderDetailInstances = nil
    self.renderDetailFrameTime = 1 / 60
    self.thermalTargetFps = 60
    self.renderDetailPressureBand = 0
    self.renderDetailPressureState = MobileThermalPolicy.NewFramePressureState(0)
    self.renderDetailBudget = 720
    self.renderDetailStats = nil
    self.renderDetailCameraSample = nil
    self.renderDetailCameraCooldown = 0
    self.renderDetailProjectionScratch = THREE.Vector3()
    self.batchedRecoveryQueue = {}
    self.renderDetailWasMobile = false
    self.performanceElapsed = 0
    self.environmentBuildQueue = IncrementalBuildQueue.new()
    self.environmentBuildFinished = false
    self.environmentBuildLastErrorCount = 0
    self.renderDetailPolicy = MobileRenderDetailPolicy.new({
        maxVisibleBlocks = 720,
        minimumProjectedPixels = 2.6,
        retainedMinimumProjectedPixels = 1.7,
        maxVisibilityChangesPerEvaluation = 10,
    })
    local overview = self.layout:Overview()
    local terrainCamera = self.layout.camera or {}
    self.maxOrbitRadius = self.layout:MaximumOrbitRadius()
    local cameraTarget = terrainCamera.target or { overview.x, overview.y, overview.z }
    self.target = THREE.Vector3(cameraTarget[1] or overview.x,
        cameraTarget[2] or overview.y or ORBIT_TARGET_Y, cameraTarget[3] or overview.z)
    self.theta = tonumber(terrainCamera.theta) or 42 * DEG
    self.phi = tonumber(terrainCamera.phi) or 55 * DEG
    self.radius = Clamp(tonumber(terrainCamera.radius) or overview.radius,
        MIN_ORBIT_RADIUS, self.maxOrbitRadius)
    self.focusedIslandId = nil
    self.deltaTheta, self.deltaPhi, self.radiusScale = 0, 0, 1
    self.cameraFocusAnimation = nil
    self.firstPerson = false
    self.firstPersonX, self.firstPersonZ = 0, 10
    self.firstPersonYaw, self.firstPersonPitch = math.pi, 0
    self.firstPersonForward, self.firstPersonRight = 0, 0
    self.firstPersonFast = false
    self.firstPersonRun = false
    self.firstPersonJoystickActive = false
    self.firstPersonJoystickX, self.firstPersonJoystickY = 0, 0
    local defaultGroundY = self.layout:DefaultGroundY()
    self.firstPersonGroundY, self.firstPersonVisualGroundY = defaultGroundY, defaultGroundY
    self.firstPersonFeetY = defaultGroundY
    self.firstPersonVerticalVelocity = 0
    self.firstPersonOnGround = true
    self.firstPersonFlying = false
    self.firstPersonFlightVertical = 0
    self.dayNight = DayNightClock.new({ time = 9.5, auto = true, dayDuration = 480 })
    self.dayNightVisual = DayNightClock.VisualState(self.dayNight:GetTime())
    self.dayNightUiElapsed = 0
    self.dayNightVisualElapsed = 0
    self.nightLightRefreshElapsed = 0
    self.activeNightLights = {}
    self.nightEmissionEnabled = false
    self.nightLightsDirty = true
    self.materialSystem = BlockMaterials.new()
    self.transparentGeometry = {}
    self.geometry = {
        box = HtmlRoundedBoxGeometry.new(1, 1, 1, 2, 0.075),
        sphere = THREE.SphereGeometry(0.5, 20, 14),
        cylinder = FullCylinderGeometry.new(20),
        cone = THREE.ConeGeometry(0.5, 1, 20, 1, false),
        tri_prism = TriangularPrismGeometry.new(),
        pyramid = FacetedSolidGeometry.SquarePyramid(),
        tetra = FacetedSolidGeometry.Tetrahedron(),
        torus = THREE.TorusGeometry(0.38, 0.12, 10, 26),
    }
    -- Fine foliage is viewed through a much smaller physical viewport on
    -- phones.  These Q-style silhouettes preserve the authored dimensions
    -- while cutting the expensive round-shape triangle count by 40-75%.
    self.mobileDetailGeometry = {
        sphere = THREE.SphereGeometry(0.5, 10, 7),
        cylinder = FullCylinderGeometry.new(12),
        cone = THREE.ConeGeometry(0.5, 1, 12, 1, false),
        torus = THREE.TorusGeometry(0.38, 0.12, 6, 16),
    }

    self.scene = THREE.Scene()
    self.scene.background = Theme.ENVIRONMENT.sky.background
    self.octree = self.scene:getNode():GetComponent("Octree")
    self.environmentRoot = THREE.Group()
    self.skyRoot = THREE.Group()
    self.instanceRoot = THREE.Group()
    self.modelBatchRoot = THREE.Group()
    self.ghostRoot = THREE.Group()
    self.helperRoot = THREE.Group()
    self.scene:add(self.environmentRoot)
    self.scene:add(self.skyRoot)
    self.scene:add(self.instanceRoot)
    self.scene:add(self.modelBatchRoot)
    self.scene:add(self.ghostRoot)
    self.scene:add(self.helperRoot)

    self.hemisphere = THREE.HemisphereLight(
        Theme.ENVIRONMENT.light.hemisphereSky, Theme.ENVIRONMENT.light.hemisphereGround, 0.82)
    self.scene:add(self.hemisphere)
    self.sun = THREE.DirectionalLight(Theme.ENVIRONMENT.light.sun, 1.42)
    self.sun.position:set(-16, 25, 12)
    self.sunTargetX, self.sunTargetY, self.sunTargetZ = -16, 25, 12
    self.sunLookTarget = THREE.Vector3(0, 0, 3.5)
    self.dynamicShadowsEnabled = nil
    self.sun.castShadow = true
    local initialShadowMapSize = WorldPerformanceBudget.ShadowMapSize(self.mobileDevice)
    self.sun.shadow.mapSize:set(initialShadowMapSize, initialShadowMapSize)
    local shadowExtent = math.min(120, math.max(45, (tonumber(overview.radius) or 72) * 0.68))
    self.sun.shadow.camera.left, self.sun.shadow.camera.right = -shadowExtent, shadowExtent
    self.sun.shadow.camera.top, self.sun.shadow.camera.bottom = shadowExtent, -shadowExtent
    self.sun.shadow.camera.near, self.sun.shadow.camera.far = 0.1, 120
    self.scene:add(self.sun)
    self.fill = THREE.DirectionalLight(Theme.ENVIRONMENT.light.fill, 0.32)
    self.fill.position:set(15, 9, -18)
    self.scene:add(self.fill)

    self.nightWindowMaterial = THREE.MeshStandardMaterial({
        color = 0xffd693, transparent = true, opacity = 0.82,
        roughness = 0.28, metalness = 0,
        emissive = 0xff9d45, emissiveIntensity = 0,
    })
    self.nightLampMaterial = THREE.MeshStandardMaterial({
        color = 0xffdc83, roughness = 0.34, metalness = 0,
        emissive = 0xff8e32, emissiveIntensity = 0,
    })

    self.modelBatcher = IslandModelBatcher.new({
        root = self.modelBatchRoot,
        geometryFor = function(block)
            local shapeId = Catalog.FindShape(block.shapeId or block.shape).id
            local mobileGeometry = self.mobileDevice and self.mobileDetailGeometry[shapeId] or nil
            return mobileGeometry or self.geometry[shapeId] or self.geometry.box
        end,
        materialFor = function(materialId, color)
            return self:Material(materialId, color)
        end,
        describeBlock = function(block)
            local material = Catalog.FindMaterial(block.materialId or block.material)
            return {
                materialId = material.id,
                color = block.color,
                emissionKind = NightEmissionKind(block),
                transparent = material.transparent == true,
                castShadow = false,
            }
        end,
        blockMatrix = BlockTransformMatrix,
        isEligible = IsBakedDetailAsset,
        assetCacheKey = function(asset)
            return table.concat({
                tostring(asset.assetId or asset.id),
                tostring(asset.versionId or asset.version or "latest"),
                self.mobileDevice and "mobile" or "desktop",
            }, "|")
        end,
        nightWindowMaterial = self.nightWindowMaterial,
        nightLampMaterial = self.nightLampMaterial,
        viewMask = MakerTransformControls.SCENE_MASK,
        cellSize = 16,
        maxInstancesPerGroup = WorldPerformanceBudget.InstanceGroupLimit(self.mobileDevice),
        maxVertices = 48000,
        -- Use game elapsed time instead of os.clock (CPU time). Resource reuse
        -- windows then behave consistently across desktop and low-power phones.
        now = function() return tonumber(self.performanceElapsed) or 0 end,
    })

    self:CreateStorybookIsland()
    -- The environment reaches well beyond the playable islands. A generous
    -- far plane prevents its distant layers being clipped at the extended
    -- overview zoom-out limit on narrow phone screens.
    self.camera = THREE.PerspectiveCamera(40, 1, 0.1, self.layout.RENDER_DISTANCE.cameraFar)
    self.scene:add(self.camera)
    self:ApplyCamera()
    self.renderer = THREE.WebGLRenderer({ scene = self.scene, camera = self.camera })
    self.renderer.shadowMap.enabled = true
    self.renderer.shadowMap.type = THREE.PCFSoftShadowMap
    self.renderer.toneMapping = THREE.NoToneMapping
    self.viewport = rawget(self.renderer, "_vp")
    self:ApplyRenderQuality()
    self.transformGizmo = IslandTransformGizmo.new(self.scene, self.camera, self.viewport)
    self:ApplyDayNight(true)
    return self
end

function IslandWorld:Material(materialId, color)
    return self.materialSystem:MaterialFor(materialId or "solid", color or "#f2e7cf")
end

function IslandWorld:InstancedModelFor(geometry)
    local cached = self.instancedGeometryModels[geometry]
    if cached then return cached end
    local ok, model = pcall(GeometryToModel.toModel, geometry)
    if not ok or not model then return nil end
    self.instancedGeometryModels[geometry] = model
    return model
end

function IslandWorld:ApplyRenderQuality()
    local mobile = self.mobileDevice == true
    local shadowMapSize = WorldPerformanceBudget.ShadowMapSize(mobile)
    if self.sun and self.sun.shadow and self.sun.shadow.mapSize then
        self.sun.shadow.mapSize:set(shadowMapSize, shadowMapSize)
    end
    if renderer and renderer.SetShadowMapSize then renderer:SetShadowMapSize(shadowMapSize) end

    -- Distant/decorative environment layers remain fully visible but do not
    -- consume a second full shadow pass on phones. Main island foundations,
    -- bridges and foliage retain their grounding shadows.
    for _, mesh in ipairs(self.environmentRoot and self.environmentRoot.children or {}) do
        local base = rawget(mesh, "_qualityBaseCastShadow")
        if base == nil then
            base = mesh.castShadow == true
            rawset(mesh, "_qualityBaseCastShadow", base)
        end
        local name = tostring(mesh.name or (mesh.getNode and mesh:getNode().name) or "")
        local decorative = name:find("DistantIsland", 1, true)
            or name:find("RockDetails", 1, true)
            or name:find("TerrainAccents", 1, true)
            or name:find("TerrainWater", 1, true)
            or name:find("MossCells", 1, true)
            or name:find("ShrubLobes", 1, true)
            or name:find("TerrainFoliage", 1, true)
        mesh.castShadow = base and not (mobile and decorative) or false
    end
    self:RefreshDynamicShadowPolicy(true)
end

function IslandWorld:RefreshDynamicShadowPolicy(force)
    if not self.sun then return end
    local overview = self.layout:Overview()
    local current = force and nil or self.dynamicShadowsEnabled
    local enabled = WorldPerformanceBudget.DynamicShadowsEnabled(
        self.mobileDevice == true, self.firstPerson == true,
        self.radius, overview.radius, current)
    if not force and enabled == self.dynamicShadowsEnabled then return end
    self.dynamicShadowsEnabled = enabled
    self.sun.castShadow = enabled
end

function IslandWorld:CreateEnvironmentMesh(name, geometry, material, x, y, z, sx, sy, sz, rotationY, rotationX, rotationZ)
    local mesh = THREE.Mesh(geometry, material)
    mesh.position:set(x, y, z)
    mesh.scale:set(sx, sy, sz)
    mesh.rotation:set(rotationX or 0, rotationY or 0, rotationZ or 0)
    mesh.castShadow = MobileThermalPolicy.EnvironmentCastShadow(
        self.mobileDevice, name, true)
    mesh.receiveShadow = true
    -- Procedural environment batches span hundreds of metres. Native custom
    -- geometry bounds can be conservative, so automatic frustum culling made
    -- the far islands disappear at some orbit angles.
    mesh.frustumCulled = false
    mesh:getNode().name = "IslandEnvironment_" .. name
    MakerTransformControls.MarkSceneObject(mesh)
    self.environmentRoot:add(mesh)
    return mesh
end

function IslandWorld:CreateSkyMesh(name, geometry, material, x, y, z, sx, sy, sz, rotationX, rotationY, rotationZ)
    local mesh = THREE.Mesh(geometry, material)
    mesh.position:set(x or 0, y or 0, z or 0)
    mesh.scale:set(sx or 1, sy or 1, sz or 1)
    mesh.rotation:set(rotationX or 0, rotationY or 0, rotationZ or 0)
    mesh.castShadow, mesh.receiveShadow = false, false
    mesh:getNode().name = "IslandSky_" .. tostring(name)
    MakerTransformControls.MarkSceneObject(mesh)
    self.skyRoot:add(mesh)
    return mesh
end

function IslandWorld:CreateCelestialSky()
    local starMaterial = THREE.MeshBasicMaterial({
        color = 0xfff8df, transparent = true, opacity = 0,
    })
    local sunMaterial = THREE.MeshBasicMaterial({
        color = 0xffe28a, transparent = true, opacity = 1,
    })
    local sunHaloMaterial = THREE.MeshBasicMaterial({
        color = 0xffca72, transparent = true, opacity = 0.34,
    })
    local moonMaterial = THREE.MeshBasicMaterial({
        color = 0xdceaff, transparent = true, opacity = 0,
    })
    local moonHaloMaterial = THREE.MeshBasicMaterial({
        color = 0x94bfff, transparent = true, opacity = 0,
    })
    local planetMaterial = THREE.MeshBasicMaterial({
        color = 0xb49be8, transparent = true, opacity = 0,
    })
    local planetRingMaterial = THREE.MeshBasicMaterial({
        color = 0xf0c5df, transparent = true, opacity = 0, side = THREE.DoubleSide,
    })
    local smallPlanetMaterial = THREE.MeshBasicMaterial({
        color = 0x75d3cf, transparent = true, opacity = 0,
    })
    self.celestialMaterials = {
        starMaterial, sunMaterial, sunHaloMaterial, moonMaterial,
        moonHaloMaterial, planetMaterial, planetRingMaterial, smallPlanetMaterial,
    }

    local stars = {}
    for index = 1, 84 do
        local y = -0.08 + ((index * 37) % 97) / 97 * 1.02
        local angle = index * 2.3999632297
        local ring = math.sqrt(math.max(0, 1 - y * y))
        local radius = 272 + (index % 5) * 4
        local size = 0.48 + (index % 4) * 0.18
        stars[#stars + 1] = {
            x = math.cos(angle) * ring * radius,
            y = y * radius,
            z = math.sin(angle) * ring * radius,
            sx = size, sy = size, sz = size, bevel = size * 0.18, color = 0xffffff,
        }
    end
    self.starField = self:CreateSkyMesh("Stars",
        StorybookEnvironmentGeometry.Blocks(stars), starMaterial)

    self.sunDisc = self:CreateSkyMesh("Sun", THREE.SphereGeometry(1, 24, 16), sunMaterial,
        0, 0, 0, 10, 10, 10)
    self.sunHalo = self:CreateSkyMesh("SunHalo", THREE.SphereGeometry(1, 20, 14), sunHaloMaterial,
        0, 0, 0, 14, 14, 14)
    self.moonDisc = self:CreateSkyMesh("Moon", THREE.SphereGeometry(1, 22, 14), moonMaterial,
        0, 0, 0, 8, 8, 8)
    self.moonHalo = self:CreateSkyMesh("MoonHalo", THREE.SphereGeometry(1, 18, 12), moonHaloMaterial,
        0, 0, 0, 11, 11, 11)

    self.planetGroup = THREE.Group()
    self.planetGroup.position:set(-185, 92, 145)
    local planet = THREE.Mesh(THREE.SphereGeometry(1, 20, 14), planetMaterial)
    planet.scale:set(8.2, 8.2, 8.2)
    planet.castShadow, planet.receiveShadow = false, false
    MakerTransformControls.MarkSceneObject(planet)
    self.planetGroup:add(planet)
    local ring = THREE.Mesh(THREE.TorusGeometry(1.45, 0.13, 8, 38), planetRingMaterial)
    ring.rotation:set(1.02, 0.18, -0.32)
    ring.scale:set(8.2, 8.2, 8.2)
    ring.castShadow, ring.receiveShadow = false, false
    MakerTransformControls.MarkSceneObject(ring)
    self.planetGroup:add(ring)
    self.skyRoot:add(self.planetGroup)

    self.smallPlanet = self:CreateSkyMesh("SmallPlanet", THREE.SphereGeometry(1, 18, 12), smallPlanetMaterial,
        210, 55, 112, 4.5, 4.5, 4.5)
end

function IslandWorld:CreateStorybookIsland()
    local data = StorybookIslandData.Build(self.layout)
    self.storybookIslandData = data
    local detail = MobileThermalPolicy.EnvironmentDetail(self.mobileDevice)

    -- Vertex colours carry the per-cell tonal variation and bevel shading.
    -- Each layer is hundreds of small authored cells merged into one draw call;
    -- there is deliberately no giant box/cylinder hidden behind the silhouette.
    local grassMaterial = THREE.MeshStandardMaterial({
        color = 0xffffff, vertexColors = true, roughness = 0.84, metalness = 0,
    })
    local soilMaterial = THREE.MeshStandardMaterial({
        color = 0xffffff, vertexColors = true, roughness = 0.90, metalness = 0,
    })
    local rockMaterial = THREE.MeshStandardMaterial({
        color = 0xffffff, vertexColors = true, roughness = 0.87, metalness = 0,
    })
    local cloudMaterial = THREE.MeshStandardMaterial({
        color = 0xffffff, vertexColors = true, roughness = 0.96, metalness = 0,
    })
    local skyMaterial = THREE.MeshStandardMaterial({
        color = 0xffffff, vertexColors = true, roughness = 1, metalness = 0,
        side = THREE.DoubleSide,
    })
    local waterMaterial = THREE.MeshStandardMaterial({
        color = 0xffffff, vertexColors = true, roughness = 0.32, metalness = 0.03,
    })
    self.islandGrassTextures = {}
    self.islandGrassMaterials = { grassMaterial }
    self.islandSceneryMaterials = { soilMaterial, rockMaterial, cloudMaterial, skyMaterial, waterMaterial }
    self.islandFoundationGeometries = {}

    local function Merge(...)
        local result = {}
        for _, list in ipairs({ ... }) do
            for _, item in ipairs(list or {}) do result[#result + 1] = item end
        end
        return result
    end

    local function BlockLayer(name, blocks, material)
        if not blocks or #blocks == 0 then return nil end
        local result, chunkSize = {}, 420
        for first = 1, #blocks, chunkSize do
            local chunk = {}
            for index = first, math.min(#blocks, first + chunkSize - 1) do
                chunk[#chunk + 1] = blocks[index]
            end
            local chunkIndex = math.floor((first - 1) / chunkSize) + 1
            local chunkName = name .. (#blocks > chunkSize and ("_" .. tostring(chunkIndex)) or "")
            local capturedChunk = chunk
            local function BuildChunk()
                result[#result + 1] = self:CreateEnvironmentMesh(
                    chunkName, StorybookEnvironmentGeometry.Blocks(capturedChunk), material,
                    0, 0, 0, 1, 1, 1, 0)
            end
            if self.mobileDevice then
                self.environmentBuildQueue:Add(BuildChunk, chunkName)
            else
                BuildChunk()
            end
        end
        return result
    end

    local function CloudLayer(name, lobes, latitudeSegments, longitudeSegments, material,
        castShadow, receiveShadow)
        local result = {}
        local chunks = StorybookEnvironmentGeometry.CloudChunks(
            lobes, latitudeSegments, longitudeSegments)
        for index, chunk in ipairs(chunks) do
            local chunkName = name .. (#chunks > 1 and ("_" .. tostring(index)) or "")
            local capturedChunk = chunk
            local function BuildChunk()
                local mesh = self:CreateEnvironmentMesh(
                    chunkName,
                    StorybookEnvironmentGeometry.Clouds(
                        capturedChunk, latitudeSegments, longitudeSegments),
                    material, 0, 0, 0, 1, 1, 1, 0)
                mesh.castShadow = MobileThermalPolicy.EnvironmentCastShadow(
                    self.mobileDevice, chunkName, castShadow == true)
                mesh.receiveShadow = receiveShadow == true
                result[#result + 1] = mesh
            end
            if self.mobileDevice then
                self.environmentBuildQueue:Add(BuildChunk, chunkName)
            else
                BuildChunk()
            end
        end
        return result
    end

    local sky = self:CreateEnvironmentMesh("SkyGradient",
        StorybookEnvironmentGeometry.SkyDome(
            Theme.ENVIRONMENT.sky.top, Theme.ENVIRONMENT.sky.middle,
            Theme.ENVIRONMENT.sky.horizon, Theme.ENVIRONMENT.sky.bottom,
            Theme.ENVIRONMENT.sky.sea, self.layout.RENDER_DISTANCE.skyRadius),
        skyMaterial, 0, 0, 0, 1, 1, 1, 0)
    sky.castShadow, sky.receiveShadow = false, false
    self.environmentRoot:remove(sky)
    self.skyRoot:add(sky)
    self.skyDome = sky
    self.skyMaterial = skyMaterial
    self.cloudMaterial = cloudMaterial
    self:CreateCelestialSky()

    -- Each island stays in its own merged batch. This keeps every mobile
    -- CustomGeometry safely below the 16-bit vertex limit while the complete
    -- archipelago still costs only a handful of draw calls.
    for index, island in ipairs(data.islands or {}) do
        BlockLayer("GrassCells" .. index, island.grass, grassMaterial)
        BlockLayer("SoilCells" .. index, island.soil, soilMaterial)
        BlockLayer("RockCells" .. index, Merge(island.rockUpper, island.rockLower, island.rockTip), rockMaterial)
    end
    BlockLayer("BridgeGrass", data.bridgeGrass, grassMaterial)
    BlockLayer("BridgeSoil", data.bridgeSoil, soilMaterial)
    BlockLayer("BridgeRock", Merge(data.bridgeRock, data.bridgeFragments), rockMaterial)
    BlockLayer("RockDetails", Merge(data.decorRocks, data.rockLedges, data.fragments), rockMaterial)
    BlockLayer("MossCells", data.moss, grassMaterial)
    BlockLayer("TerrainWater", data.terrainWater, waterMaterial)
    BlockLayer("TerrainAccents", data.terrainAccents, rockMaterial)
    BlockLayer("DistantIslandGrass", data.distantGrass, grassMaterial)
    BlockLayer("DistantIslandSoil", data.distantSoil, soilMaterial)
    BlockLayer("DistantIslandRock", data.distantRock, rockMaterial)
    BlockLayer("DistantIslandLandmarks", data.distantStructures, rockMaterial)

    CloudLayer("ShrubLobes", data.shrubs,
        detail.shrubLat, detail.shrubLon, grassMaterial, true, true)

    if data.terrainFoliage and #data.terrainFoliage > 0 then
        CloudLayer("TerrainFoliage", data.terrainFoliage,
            detail.foliageLat, detail.foliageLon,
            grassMaterial, true, true)
    end

    CloudLayer("DistantIslandFoliage", data.distantFoliage,
        detail.distantFoliageLat, detail.distantFoliageLon,
        grassMaterial, false, false)

    CloudLayer("IslandOrbitClouds", data.cloudsNear,
        detail.nearCloudLat, detail.nearCloudLon, cloudMaterial)
    CloudLayer("LowCloudRibbons", data.cloudsLow,
        detail.lowCloudLat, detail.lowCloudLon, cloudMaterial)
    CloudLayer("MidCloudTowers", data.cloudsMid,
        detail.midCloudLat, detail.midCloudLon, cloudMaterial)
    CloudLayer("HighCloudWisps", data.cloudsHigh,
        detail.highCloudLat, detail.highCloudLon, cloudMaterial)
    CloudLayer("HorizonCloudBanks", data.cloudsFar,
        detail.farCloudLat, detail.farCloudLon, cloudMaterial)
    self.environmentBuildFinished = not self.environmentBuildQueue:IsPending()
end

function IslandWorld:IsEnvironmentLoading()
    return self.environmentBuildQueue ~= nil
        and self.environmentBuildQueue:IsPending()
end

function IslandWorld:AdvanceEnvironmentBuilds()
    local queue = self.environmentBuildQueue
    if not queue or not queue:IsPending() then
        self.environmentBuildFinished = true
        return false
    end
    local _, complete = queue:Advance(
        MobileThermalPolicy.EnvironmentBuildsPerFrame(self.mobileDevice))
    local progress = queue:Progress()
    if progress.errors > self.environmentBuildLastErrorCount then
        self.environmentBuildLastErrorCount = progress.errors
        local failure = queue.errors[progress.errors]
        print("[IslandWorld] environment build failed: "
            .. tostring(failure and failure.label) .. " · "
            .. tostring(failure and failure.message))
    end
    if complete then
        self.environmentBuildFinished = true
        self:ApplyRenderQuality()
        self:RefreshState()
    end
    return true
end

function IslandWorld:BuildAssetGroup(asset, nodeName, overrideMaterial, markOverlay)
    local group = THREE.Group()
    local nightEmissionMeshes = {}
    local batchesByKey, orderedBatches = {}, {}
    local renderBatchCount = 0
    local shadowStart = math.max(0, tonumber(self.modelShadowBlockCount) or 0)
    local shadowCursor = shadowStart

    local transparentFaceIndex = TransparentFaceIndex.Build(asset.blocks, function(source)
        if Catalog.FindShape(source.shapeId or source.shape).id ~= "box" then return nil end
        local material = Catalog.FindMaterial(source.materialId or source.material)
        return material.transparent and material.id or nil
    end)

    local function AddNightEmitter(mesh, material, emissionKind)
        if not emissionKind then return end
        nightEmissionMeshes[#nightEmissionMeshes + 1] = {
            mesh = mesh,
            originalMaterial = material,
            kind = emissionKind,
        }
    end

    local function AddLooseMesh(record)
        local mesh = THREE.Mesh(record.geometry, record.material)
        local x, y, z = ModelPosition(record.source)
        local sx, sy, sz = ModelSize(record.source)
        local rx, ry, rz = ModelRotation(record.source)
        mesh.position:set(x, y, z)
        mesh.scale:set(sx, sy, sz)
        mesh.rotation:set(rx, ry, rz)
        mesh.castShadow = record.castShadow
        mesh.receiveShadow = record.receiveShadow
        mesh:getNode().name = nodeName
        if markOverlay then MakerTransformControls.MarkOverlayObject(mesh)
        else MakerTransformControls.MarkSceneObject(mesh) end
        group:add(mesh)
        renderBatchCount = renderBatchCount + 1
        AddNightEmitter(mesh, record.material, record.emissionKind)
    end

    local function AddInstancedBatch(batch)
        if #batch.records < 2 then AddLooseMesh(batch.records[1]); return end
        local sharedModel = self:InstancedModelFor(batch.geometry)
        if not sharedModel then
            for _, record in ipairs(batch.records) do AddLooseMesh(record) end
            return
        end
        local mesh
        local ok = pcall(function()
            mesh = IslandInstancedMesh.new(batch.geometry, batch.material, #batch.records, sharedModel)
            for index, record in ipairs(batch.records) do
                mesh:setMatrixAt(index - 1, BlockTransformMatrix(record.source))
            end
        end)
        local drawable = ok and mesh and mesh:getGroup() or nil
        if not drawable then
            if mesh and mesh.getNode then mesh:getNode():Remove() end
            for _, record in ipairs(batch.records) do AddLooseMesh(record) end
            return
        end

        -- StaticModelGroup ray hits report their owner node, not the individual
        -- instance child. Name both so exact model picking survives either
        -- engine result form and remains compatible with RayInstance.
        mesh:getNode().name = nodeName
        for _, instanceNode in ipairs(rawget(mesh, "_instances") or {}) do
            instanceNode.name = nodeName
        end
        if drawable.SetViewMask then drawable:SetViewMask(MakerTransformControls.SCENE_MASK) end
        if drawable.SetCastShadows then drawable:SetCastShadows(batch.castShadow == true) end
        group:add(mesh)
        renderBatchCount = renderBatchCount + 1
        AddNightEmitter(mesh, batch.material, batch.emissionKind)
    end

    for _, source in ipairs(asset.blocks or {}) do
        local shapeId = Catalog.FindShape(source.shapeId or source.shape).id
        local mobileGeometry = self.mobileDevice and self.mobileDetailGeometry[shapeId] or nil
        local geometry = mobileGeometry or self.geometry[shapeId] or self.geometry.box
        local materialDefinition = Catalog.FindMaterial(source.materialId or source.material)
        local materialId = materialDefinition.id
        if shapeId == "box" and materialDefinition.transparent then
            local hidden = TransparentFaceIndex.HiddenFaces(
                transparentFaceIndex, source, materialId)
            if hidden then
                local key = materialId
                    .. (hidden["x+"] and "1" or "0") .. (hidden["x-"] and "1" or "0")
                    .. (hidden["y+"] and "1" or "0") .. (hidden["y-"] and "1" or "0")
                    .. (hidden["z+"] and "1" or "0") .. (hidden["z-"] and "1" or "0")
                geometry = self.transparentGeometry[key]
                if not geometry then
                    geometry = TransparentBlockGeometry.new(hidden, materialId == "water" and 0.7 or 1)
                    self.transparentGeometry[key] = geometry
                end
            end
        end
        local material = overrideMaterial or self:Material(materialId, source.color)
        local collisionRole = ModelGeometry.CollisionRole(source)
        local transparent = materialDefinition.transparent == true
        local castShadow = false
        if overrideMaterial == nil then
            castShadow, shadowCursor = WorldPerformanceBudget.ReserveShadow(
                source, self.mobileDevice == true, shadowCursor)
        end
        local emissionKind = overrideMaterial == nil and NightEmissionKind(source) or nil
        local record = {
            source = source,
            geometry = geometry,
            material = material,
            castShadow = castShadow,
            receiveShadow = not transparent and collisionRole ~= "decorative",
            emissionKind = emissionKind,
        }

        -- Transparent blocks stay as individual meshes for correct sorting and
        -- hidden-face treatment. Ghost/overlay geometry also stays individual.
        -- Opaque immutable blocks are safe to instance by visual render state.
        if overrideMaterial == nil and not markOverlay and not transparent then
            local key = RenderBatchKey(shapeId, materialId, source.color, castShadow, emissionKind)
            local batch = batchesByKey[key]
            if not batch or #batch.records >= WorldPerformanceBudget.InstanceGroupLimit(self.mobileDevice) then
                batch = {
                    geometry = geometry,
                    material = material,
                    castShadow = castShadow,
                    emissionKind = emissionKind,
                    records = {},
                }
                batchesByKey[key] = batch
                orderedBatches[#orderedBatches + 1] = batch
            end
            batch.records[#batch.records + 1] = record
        else
            AddLooseMesh(record)
        end
    end
    for _, batch in ipairs(orderedBatches) do AddInstancedBatch(batch) end
    rawset(group, "_nightEmissionMeshes", nightEmissionMeshes)
    rawset(group, "_renderBlockCount", #(asset.blocks or {}))
    rawset(group, "_shadowBlockCount", shadowCursor - shadowStart)
    rawset(group, "_renderBatchCount", renderBatchCount)
    return group
end

function IslandWorld:CreateInstanceNightLight(instance)
    local emitters = instance.nightEmissionMeshes or {}
    if (#emitters == 0 and not instance.hasBatchedNightEmission)
        or not instance.root or not instance.renderAsset then return end
    local bounds = instance.renderAsset.bounds or {}
    local minimum, maximum = bounds.min or {}, bounds.max or {}
    local minimumY, maximumY = tonumber(minimum[2]) or 0, tonumber(maximum[2]) or 2
    local light = THREE.PointLight(0xffb45c, 0, 8, 2)
    light.position:set(
        ((tonumber(minimum[1]) or -0.5) + (tonumber(maximum[1]) or 0.5)) * 0.5,
        minimumY + (maximumY - minimumY) * 0.40,
        ((tonumber(minimum[3]) or -0.5) + (tonumber(maximum[3]) or 0.5)) * 0.5
    )
    light.castShadow = false
    light.visible = false
    instance.root:add(light)
    instance.nightLight = light
    self.nightLightsDirty = true
end

function IslandWorld:SetNightEmissionEnabled(enabled)
    enabled = enabled == true
    if self.nightEmissionEnabled == enabled then return end
    self.nightEmissionEnabled = enabled
    if self.modelBatcher then self.modelBatcher:SetNightEnabled(enabled) end
    for _, instance in ipairs(self.instances or {}) do
        for _, entry in ipairs(instance.nightEmissionMeshes or {}) do
            entry.mesh.material = enabled
                and (entry.kind == "lamp" and self.nightLampMaterial or self.nightWindowMaterial)
                or entry.originalMaterial
        end
    end
end

function IslandWorld:RefreshNightLights(force)
    local visual = self.dayNightVisual or {}
    local intensity = tonumber(visual.windowIntensity) or 0
    if force or math.abs((self.lastNightMaterialIntensity or -1) - intensity) > 0.001 then
        self.lastNightMaterialIntensity = intensity
        if self.nightWindowMaterial then self.nightWindowMaterial.emissiveIntensity = intensity end
        if self.nightLampMaterial then self.nightLampMaterial.emissiveIntensity = intensity * 1.18 end
    end
    self:SetNightEmissionEnabled(intensity > 0.08)

    if intensity <= 0.08 then
        for _, light in ipairs(self.activeNightLights or {}) do
            light.intensity, light.visible = 0, false
        end
        self.activeNightLights = {}
        self.nightLightsDirty = false
        return
    end

    local refreshInterval = MobileThermalPolicy.NightLightRefreshInterval(self.mobileDevice)
    if not force and not self.nightLightsDirty and self.nightLightRefreshElapsed < refreshInterval then
        local lightIntensity = math.min(1.45, intensity * 0.68)
        if math.abs((self.lastNightLightIntensity or -1) - lightIntensity) > 0.001 then
            self.lastNightLightIntensity = lightIntensity
            for _, light in ipairs(self.activeNightLights or {}) do light.intensity = lightIntensity end
        end
        return
    end
    self.nightLightRefreshElapsed = 0
    self.nightLightsDirty = false
    local candidates = {}
    for _, instance in ipairs(self.instances or {}) do
        if instance.nightLight then
            local dx, dz = self.camera.position.x - instance.x, self.camera.position.z - instance.z
            candidates[#candidates + 1] = { light = instance.nightLight, distance = dx * dx + dz * dz }
            instance.nightLight.intensity, instance.nightLight.visible = 0, false
        end
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    self.activeNightLights = {}
    self.lastNightLightIntensity = math.min(1.45, intensity * 0.68)
    local lightLimit = MobileThermalPolicy.NightLightLimit(self.mobileDevice)
    for index = 1, math.min(lightLimit, #candidates) do
        local light = candidates[index].light
        light.intensity = self.lastNightLightIntensity
        light.visible = true
        self.activeNightLights[#self.activeNightLights + 1] = light
    end
end

function IslandWorld:GroundOffset(asset, scale, x, z)
    local bounds = asset and asset.bounds or { min = { 0, 0, 0 } }
    local groundY = self.layout:SurfaceAt(x or 0, z or 0, 0)
        or self.layout:DefaultGroundY()
    return groundY - (tonumber(bounds.min[2]) or 0) * (scale or 1)
end

function IslandWorld:ApplyInstanceTransform(instance)
    local root = instance.root
    if not root then return end
    root.position:set(instance.x,
        self:GroundOffset(instance.renderAsset, instance.scale, instance.x, instance.z) + (instance.y or 0),
        instance.z)
    root.rotation:set(0, instance.rotationY or 0, 0)
    root.scale:set(instance.scale, instance.scale, instance.scale)
    self:RefreshInstanceCollision(instance)
    self.nightLightsDirty = true
    if instance.usesModelBatcher then self:MarkRenderDetailDirty() end
end

function IslandWorld:RenderBatchedInstanceStandalone(instance)
    if not instance or not instance.root or not instance.renderAsset then return false end
    if self.modelBatcher then self.modelBatcher:Unregister(instance, false) end
    local ok, root = pcall(self.BuildAssetGroup, self, instance.renderAsset,
        "IslandInstance_" .. tostring(instance.id), nil, false)
    if not ok or not root then return false end

    local oldRoot = instance.root
    local oldBatchCount = tonumber(instance.renderBatchCount) or 0
    local oldShadowCount = tonumber(instance.shadowBlockCount) or 0
    self.instanceRoot:remove(oldRoot)
    oldRoot:getNode():Remove()
    self.instanceRoot:add(root)
    instance.root = root
    instance.usesModelBatcher = false
    instance.renderDetailVisible = true
    instance.renderBlockCount = rawget(root, "_renderBlockCount")
        or #(instance.renderAsset.blocks or {})
    instance.shadowBlockCount = rawget(root, "_shadowBlockCount") or 0
    instance.renderBatchCount = rawget(root, "_renderBatchCount") or instance.renderBlockCount
    instance.nightEmissionMeshes = rawget(root, "_nightEmissionMeshes") or {}
    instance.nightLight = nil
    self.modelRenderBatchCount = math.max(0, self.modelRenderBatchCount - oldBatchCount)
        + instance.renderBatchCount
    self.modelShadowBlockCount = math.max(0, self.modelShadowBlockCount - oldShadowCount)
        + instance.shadowBlockCount
    self.rendered[instance.id] = root
    self:ApplyInstanceTransform(instance)
    self:CreateInstanceNightLight(instance)
    self.nightLightsDirty = true
    self:MarkRenderDetailDirty()
    return true
end

function IslandWorld:RefreshBatchedInstanceCell(instance, rollbackSource)
    if not instance or not instance.usesModelBatcher
        or instance.renderDetailVisible == false then return true end
    local refreshed, reason = self.modelBatcher:RefreshCell(instance)
    if refreshed ~= nil then return true end

    if rollbackSource then
        instance.x = tonumber(rollbackSource.x) or 0
        instance.y = tonumber(rollbackSource.y) or 0
        instance.z = tonumber(rollbackSource.z) or 0
        instance.rotationY = tonumber(rollbackSource.rotationY) or 0
        instance.scale = Clamp(tonumber(rollbackSource.scale) or 1, 0.1, 3)
        instance.portal = type(rollbackSource.portal) == "table" and Copy(rollbackSource.portal) or nil
        self:ApplyInstanceTransform(instance)
    end

    local recovered = self.modelBatcher:Register(instance, instance.renderAsset)
    if not recovered then recovered = self:RenderBatchedInstanceStandalone(instance) end
    if not recovered then
        -- Both native batching and the standalone fallback failed. Publish the
        -- real hidden state and zero its visible-part accounting so the next
        -- detail-policy tick retries registration instead of treating an
        -- invisible model as successfully rendered forever.
        self.modelRenderBatchCount = math.max(0,
            self.modelRenderBatchCount - (tonumber(instance.renderBatchCount) or 0))
        instance.renderBatchCount = 0
        instance.renderDetailVisible = false
        SetSceneGroupEnabled(instance.root, false)
        if instance.nightLight then
            instance.nightLight.intensity = 0
            instance.nightLight.visible = false
        end
        if not self.mobileDevice then
            self.batchedRecoveryQueue[instance.id] = {
                elapsed = 0,
                attempts = 0,
            }
        end
        self.nightLightsDirty = true
        self:MarkRenderDetailDirty()
    end
    -- When a rollback source is supplied the requested edit did not complete,
    -- even if the old visual was recovered successfully.  The caller must not
    -- consume history or persist the failed transform.
    return rollbackSource == nil and recovered == true, reason
end

function IslandWorld:ProcessBatchedInstanceRecoveries(timeStep)
    local queue = self.batchedRecoveryQueue
    if type(queue) ~= "table" or not self.modelBatcher then return false end
    local processed = false
    for id, recovery in pairs(queue) do
        local instance = self.byId[tonumber(id)]
        if not instance or not instance.usesModelBatcher
            or instance.renderDetailVisible ~= false then
            queue[id] = nil
        else
            recovery.elapsed = (tonumber(recovery.elapsed) or 0)
                + math.max(0, tonumber(timeStep) or 0)
            local delay = math.min(4, 0.45 * (1 + (tonumber(recovery.attempts) or 0)))
            if not processed and recovery.elapsed >= delay then
                processed = true
                recovery.elapsed = 0
                recovery.attempts = (tonumber(recovery.attempts) or 0) + 1
                SetSceneGroupEnabled(instance.root, true)
                local registered = self.modelBatcher:Register(instance, instance.renderAsset)
                if registered then
                    instance.renderDetailVisible = true
                    instance.renderBatchCount = tonumber(instance.batchedRenderPartCount) or 1
                    self.modelRenderBatchCount = self.modelRenderBatchCount
                        + instance.renderBatchCount
                    if not instance.nightLight then self:CreateInstanceNightLight(instance) end
                    self.nightLightsDirty = true
                    queue[id] = nil
                elseif self:RenderBatchedInstanceStandalone(instance) then
                    queue[id] = nil
                else
                    SetSceneGroupEnabled(instance.root, false)
                end
            end
        end
    end
    return processed
end

function IslandWorld:RefreshInstanceCollision(instance)
    instance.firstPersonColliders = {}
    instance.firstPersonSurfaces = {}
    instance.firstPersonFootprint = nil
    local asset = instance.renderAsset
    if not asset then return end
    instance.firstPersonFootprint = self.layout:Footprint(instance, asset)
    -- Eligible baked details are guaranteed to contain decorative blocks only.
    -- They never participate in first-person collision, so avoid rebuilding a
    -- throwaway collider table for every grass leaf after each transform.
    if IsBakedDetailAsset(asset) then return end
    local scale = instance.scale or 1
    local rootY = self:GroundOffset(asset, scale, instance.x, instance.z) + (instance.y or 0)
    local instanceAngle = instance.rotationY or 0
    local instanceCosine, instanceSine = math.cos(instanceAngle), math.sin(instanceAngle)
    for _, block in ipairs(asset.blocks or {}) do
        local bx, by, bz = ModelPosition(block)
        local sx, sy, sz = ModelSize(block)
        local rx, blockYRotation, rz = ModelRotation(block)
        local shape = Catalog.FindShape(block.shapeId or block.shape)
        local role = ModelGeometry.CollisionRole(block)
        local halfWidth, halfHeight, halfDepth, colliderAngle
        if math.abs(rx) <= 0.0001 and math.abs(rz) <= 0.0001 then
            halfWidth = sx * shape.bounds[1] * scale * 0.5
            halfHeight = sy * shape.bounds[2] * scale * 0.5
            halfDepth = sz * shape.bounds[3] * scale * 0.5
            colliderAngle = instanceAngle + blockYRotation
        else
            local half = ModelGeometry.RotatedHalfExtents(block)
            halfWidth, halfHeight, halfDepth = half[1] * scale, half[2] * scale, half[3] * scale
            colliderAngle = instanceAngle
        end
        local centerY = rootY + by * scale
        local collider = {
            x = instance.x + (bx * instanceCosine + bz * instanceSine) * scale,
            z = instance.z + (-bx * instanceSine + bz * instanceCosine) * scale,
            halfWidth = halfWidth,
            halfDepth = halfDepth,
            angle = colliderAngle,
            minimumY = centerY - halfHeight,
            maximumY = centerY + halfHeight,
            passableDoor = IsPassableDoorBlock(block),
            passableFluid = role == "fluid",
            role = role,
        }
        if role ~= "decorative" then instance.firstPersonColliders[#instance.firstPersonColliders + 1] = collider end
        if role == "surface" or IsWalkSurfaceBlock(block, sx, sy, sz) then
            instance.firstPersonSurfaces[#instance.firstPersonSurfaces + 1] = collider
        end
    end
end

function IslandWorld:TransformCenter(instance)
    if not instance or not instance.renderAsset then return nil end
    local bounds = instance.renderAsset.bounds or {}
    local minimum, maximum = bounds.min or {}, bounds.max or {}
    local scale = instance.scale or 1
    local localX = ((tonumber(minimum[1]) or -0.5) + (tonumber(maximum[1]) or 0.5)) * 0.5 * scale
    local localY = ((tonumber(minimum[2]) or 0) + (tonumber(maximum[2]) or 1)) * 0.5 * scale
    local localZ = ((tonumber(minimum[3]) or -0.5) + (tonumber(maximum[3]) or 0.5)) * 0.5 * scale
    local angle = instance.rotationY or 0
    local cosine, sine = math.cos(angle), math.sin(angle)
    return {
        x = instance.x + localX * cosine + localZ * sine,
        y = self:GroundOffset(instance.renderAsset, scale, instance.x, instance.z) + (instance.y or 0) + localY,
        z = instance.z - localX * sine + localZ * cosine,
    }
end

function IslandWorld:ProjectedDetailPixels(instance)
    if not instance or not instance.renderAsset or not self.camera then return 0, math.huge end
    local center = self:TransformCenter(instance)
    if not center then return 0, math.huge end
    local dx = (tonumber(self.camera.position.x) or 0) - center.x
    local dy = (tonumber(self.camera.position.y) or 0) - center.y
    local dz = (tonumber(self.camera.position.z) or 0) - center.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local bounds = instance.renderAsset.bounds or {}
    local size = bounds.size or { 1, 1, 1 }
    local scale = tonumber(instance.scale) or 1
    local diameter = math.sqrt(
        (tonumber(size[1]) or 1) ^ 2
        + (tonumber(size[2]) or 1) ^ 2
        + (tonumber(size[3]) or 1) ^ 2) * scale
    local viewportHeight = math.max(1,
        (tonumber(self.viewportRect.bottom) or graphics:GetHeight())
        - (tonumber(self.viewportRect.top) or 0))
    if self.mobileDevice then
        viewportHeight = viewportHeight / math.max(1, tonumber(self.uiScale) or 1)
    end
    local halfFov = math.max(1, tonumber(self.camera.fov) or 40) * DEG * 0.5
    local focalPixels = viewportHeight / math.max(0.01, 2 * math.tan(halfFov))
    local forwardX, forwardY, forwardZ
    if self.firstPerson then
        local cosinePitch = math.cos(self.firstPersonPitch)
        forwardX = math.sin(self.firstPersonYaw) * cosinePitch
        forwardY = math.sin(self.firstPersonPitch)
        forwardZ = math.cos(self.firstPersonYaw) * cosinePitch
    else
        forwardX = self.target.x - self.camera.position.x
        forwardY = self.target.y - self.camera.position.y
        forwardZ = self.target.z - self.camera.position.z
        local length = math.sqrt(forwardX * forwardX + forwardY * forwardY + forwardZ * forwardZ)
        if length > 0.0001 then
            forwardX, forwardY, forwardZ = forwardX / length, forwardY / length, forwardZ / length
        end
    end
    local forwardDepth = -dx * forwardX - dy * forwardY - dz * forwardZ
    local projected = self.renderDetailProjectionScratch
    projected:set(center.x, center.y, center.z):project(self.camera)
    local inView = MobileDetailProjection.InView(
        projected.x, projected.y, forwardDepth, self.camera.far, 1.16)
    local coverageKey = inView and MobileDetailProjection.CoverageKey(projected.x, projected.y) or nil
    return diameter * focalPixels / math.max(0.1, distance), distance, inView, coverageKey
end

function IslandWorld:ResolveRenderDetailCost(instance)
    if instance.renderDetailCostAsset == instance.renderAsset
        and tonumber(instance.renderDetailCost) then return instance.renderDetailCost end
    local cached = bakedDetailCost[instance.renderAsset]
    if cached then
        instance.renderDetailCost, instance.renderDetailCostAsset = cached, instance.renderAsset
        return cached
    end
    local compiled = self.modelBatcher and self.modelBatcher:Compile(instance.renderAsset) or nil
    local blocks = #(instance.renderAsset.blocks or {})
    instance.renderDetailCost = compiled
        and MobileDetailCost.EquivalentBlocks(blocks, compiled.vertexCount)
        or MobileDetailCost.ConservativeBlocks(blocks)
    instance.renderDetailCostAsset = instance.renderAsset
    bakedDetailCost[instance.renderAsset] = instance.renderDetailCost
    return instance.renderDetailCost
end

-- Dense projects keep every authored model in save data.  On phones only,
-- decorative vegetation that occupies just a few physical pixels competes
-- for a bounded *visible-detail* budget.  Hidden entries are unregistered
-- from StaticModelGroup first, so ray-query subObject indices remain exact;
-- approaching them registers the same root again with no data reconstruction.
function IslandWorld:MarkRenderDetailDirty()
    self.renderDetailDirty = true
    self.renderDetailRevision = (tonumber(self.renderDetailRevision) or 0) + 1
    self.renderDetailCandidates, self.renderDetailInstances = nil, nil
    if self.renderDetailPolicy and self.renderDetailPolicy.MarkDirty then
        self.renderDetailPolicy:MarkDirty()
    end
end

function IslandWorld:MarkRenderDetailCameraChanged(force)
    local changed
    if self.firstPerson then
        local eyeY = (self.firstPersonFeetY or self.firstPersonGroundY
            or self.layout:DefaultGroundY()) + FIRST_PERSON_EYE_HEIGHT
        changed, self.renderDetailCameraSample = CameraMotionStability.UpdateFirstPersonSample(
            self.renderDetailCameraSample,
            self.firstPersonX, eyeY, self.firstPersonZ,
            self.firstPersonYaw, self.firstPersonPitch, force)
    else
        changed, self.renderDetailCameraSample = CameraMotionStability.UpdateOrbitSample(
            self.renderDetailCameraSample,
            self.target.x, self.target.y, self.target.z,
            self.theta, self.phi, self.radius, force)
    end
    if not changed then return false end
    -- Rebuilding dense visibility batches while the camera is moving can
    -- produce a visible tremble on slower phones. Keep the last stable set
    -- during manipulation, then refresh shortly after the camera settles.
    self.renderDetailCameraCooldown = 0.20
    self:MarkRenderDetailDirty()
    return true
end

function IslandWorld:AdaptiveRenderDetailBudget()
    local rect = self.viewportRect or {}
    local width = math.max(1, (tonumber(rect.right) or graphics:GetWidth())
        - (tonumber(rect.left) or 0))
    local height = math.max(1, (tonumber(rect.bottom) or graphics:GetHeight())
        - (tonumber(rect.top) or 0))
    local logicalScale = self.mobileDevice and math.max(1, tonumber(self.uiScale) or 1) or 1
    width, height = width / logicalScale, height / logicalScale
    -- Work in logical pixels so a high-DPR phone does not request extra detail
    -- that its small screen cannot resolve. Mobile keeps the authored scene but
    -- uses a lower visible-decoration ceiling than desktop.
    local areaFactor = Clamp(math.sqrt((width * height) / (1280 * 720)), 0.58, 1.0)
    local pressure = ({ 1.0, 0.86, 0.72, 0.55 })[
        Clamp((tonumber(self.renderDetailPressureBand) or 0) + 1, 1, 4)]
    local maximum = self.mobileDevice and 480 or 720
    local minimum = self.mobileDevice and 200 or 240
    local target = Clamp(math.floor(maximum * areaFactor * pressure + 0.5), minimum, maximum)
    local current = tonumber(self.renderDetailBudget) or target
    -- Decrease promptly under sustained frame pressure; recover slowly to
    -- avoid detail popping when one cheap frame follows a heavy one.
    local rate = target < current and 0.30 or 0.06
    current = current + (target - current) * rate
    self.renderDetailBudget = Clamp(math.floor(current + 0.5), minimum, maximum)
    return self.renderDetailBudget
end

function IslandWorld:RefreshMobileRenderDetail(force)
    if not self.renderDetailPolicy or not self.modelBatcher then return end
    if not self.mobileDevice then
        if self.renderDetailWasMobile then self.renderDetailPolicy:Reset() end
        self.renderDetailWasMobile = false
        return
    end
    self.renderDetailWasMobile = true
    if not force and (tonumber(self.renderDetailCameraCooldown) or 0) > 0 then return end
    local hasPending = (tonumber(self.renderDetailPolicy.pendingChanges) or 0) > 0
    if not force and not self.renderDetailDirty and not hasPending then return end
    local interval = hasPending and 0.055 or 0.12
    if not force and self.renderDetailElapsed < interval then return end
    self.renderDetailElapsed = 0
    local candidates, details = self.renderDetailCandidates, self.renderDetailInstances
    if self.renderDetailDirty or not candidates or not details then
        candidates, details = {}, {}
        for _, instance in ipairs(self.instances or {}) do
            if instance.usesModelBatcher and instance.renderAsset then
                local pixels, distance, inView, coverageKey = self:ProjectedDetailPixels(instance)
                local groundCover = IsGroundCoverAsset(instance.renderAsset)
                candidates[#candidates + 1] = {
                    id = instance.id,
                    projectedPixels = pixels,
                    distance = distance,
                    inView = inView,
                    blockCount = self:ResolveRenderDetailCost(instance),
                    selected = self.selectedId == instance.id,
                    -- Small grass enters at a much farther distance, while the
                    -- unchanged global budget and per-screen-tile coverage keep
                    -- dense islands thermally bounded.
                    minimumProjectedPixels = groundCover and 0.82 or nil,
                    retainedMinimumProjectedPixels = groundCover and 0.52 or nil,
                    priority = groundCover and 1.12 or 1,
                    coverageKey = groundCover and coverageKey or nil,
                }
                details[instance.id] = instance
            end
        end
        self.renderDetailCandidates, self.renderDetailInstances = candidates, details
    end
    if #candidates == 0 then
        self.renderDetailDirty = false
        self.renderDetailStats = {
            mobile = true,
            candidateCount = 0,
            visibleCount = 0,
            hiddenCount = 0,
            visibleBlocks = 0,
            budget = self:AdaptiveRenderDetailBudget(),
            overBudgetBlocks = 0,
            changeCount = 0,
            pendingChanges = 0,
            reused = false,
        }
        return
    end
    local budget = self:AdaptiveRenderDetailBudget()
    local visibleById, stats = self.renderDetailPolicy:Evaluate(candidates, {
        mobile = true,
        selectedId = self.selectedId,
        maxVisibleBlocks = budget,
        revision = self.renderDetailRevision,
        dirty = self.renderDetailDirty or force,
        maxVisibilityChanges = force and 12 or 8,
    })
    local registrationRetry = false
    for id, instance in pairs(details) do
        local shouldShow = visibleById[id] == true
        local isShown = instance.renderDetailVisible ~= false
        if shouldShow and not isShown then
            SetSceneGroupEnabled(instance.root, true)
            local registered, compiled = self.modelBatcher:Register(instance, instance.renderAsset)
            if registered then
                instance.renderDetailVisible = true
                instance.renderDetailCost = MobileDetailCost.EquivalentBlocks(
                    #(instance.renderAsset.blocks or {}), compiled and compiled.vertexCount)
                instance.renderDetailCostAsset = instance.renderAsset
                bakedDetailCost[instance.renderAsset] = instance.renderDetailCost
                local batches = tonumber(instance.batchedRenderPartCount) or 1
                instance.renderBatchCount = batches
                self.modelRenderBatchCount = self.modelRenderBatchCount + batches
                if not instance.nightLight then self:CreateInstanceNightLight(instance) end
            else
                SetSceneGroupEnabled(instance.root, false)
                registrationRetry = true
            end
        elseif not shouldShow and isShown then
            self.modelRenderBatchCount = math.max(0,
                self.modelRenderBatchCount - (tonumber(instance.renderBatchCount) or 0))
            self.modelBatcher:Unregister(instance)
            SetSceneGroupEnabled(instance.root, false)
            instance.renderDetailVisible = false
            instance.renderBatchCount = 0
        end
    end
    self.renderDetailDirty = false
    self.renderDetailStats = stats
    if registrationRetry then self:MarkRenderDetailDirty() end
end

function IslandWorld:RefreshTransformGizmo()
    if not self.transformGizmo then return end
    local center = self.presentationPaused and nil or self:TransformCenter(self:GetSelected())
    self.transformGizmo:Refresh(center, self.transformMode, self.mobileEditor)
end

function IslandWorld:RenderInstance(instance, preparedRenderable)
    local asset = self.assetStore:Get(instance.assetId, instance.versionId)
    local renderable = preparedRenderable or (asset and self.assetStore:AcquireRenderable(asset) or nil)
    if not renderable then return false end
    instance.renderAsset = renderable
    local root
    if self.modelBatcher and IsBakedDetailAsset(renderable) then
        root = THREE.Group()
        root:getNode().name = "IslandInstance_" .. tostring(instance.id)
        self.instanceRoot:add(root)
        instance.root = root
        self:ApplyInstanceTransform(instance)
        local registered, compiled
        if self.mobileDevice then
            -- Do not register every tiny decoration only to remove most of it
            -- on the following LOD tick. The policy may precompile one shared
            -- asset to obtain its true cost, but native group membership is
            -- still created only when the instance becomes visible.
            registered = true
            instance.usesModelBatcher = true
            instance.renderDetailVisible = false
            SetSceneGroupEnabled(root, false)
        else
            registered, compiled = self.modelBatcher:Register(instance, renderable)
        end
        if registered then
            instance.usesModelBatcher = true
            if not self.mobileDevice then instance.renderDetailVisible = true end
            instance.renderBlockCount = #(renderable.blocks or {})
            instance.shadowBlockCount = 0
            instance.renderBatchCount = self.mobileDevice and 0
                or tonumber(instance.batchedRenderPartCount) or 1
            -- A round block is considerably more expensive than a simple leaf.
            -- Preserve source-block accounting, but charge extra for assets
            -- whose baked triangle count is higher (96 vertices per equivalent).
            instance.renderDetailCost = compiled
                and MobileDetailCost.EquivalentBlocks(instance.renderBlockCount, compiled.vertexCount)
                or instance.renderBlockCount
            if compiled then
                instance.renderDetailCostAsset = renderable
                bakedDetailCost[renderable] = instance.renderDetailCost
            end
            instance.nightEmissionMeshes = {}
        else
            self.instanceRoot:remove(root)
            root:getNode():Remove()
            instance.root, root = nil, nil
        end
    end
    if not root then
        root = self:BuildAssetGroup(renderable, "IslandInstance_" .. tostring(instance.id), nil, false)
        self.instanceRoot:add(root)
        instance.root = root
        instance.renderBlockCount = rawget(root, "_renderBlockCount") or #(renderable.blocks or {})
        instance.shadowBlockCount = rawget(root, "_shadowBlockCount") or 0
        instance.renderBatchCount = rawget(root, "_renderBatchCount") or instance.renderBlockCount
        instance.nightEmissionMeshes = rawget(root, "_nightEmissionMeshes") or {}
        if self.nightEmissionEnabled then
            for _, entry in ipairs(instance.nightEmissionMeshes) do
                entry.mesh.material = entry.kind == "lamp" and self.nightLampMaterial or self.nightWindowMaterial
            end
        end
        self:ApplyInstanceTransform(instance)
    end
    self.modelRenderBlockCount = self.modelRenderBlockCount + instance.renderBlockCount
    self.modelShadowBlockCount = self.modelShadowBlockCount + instance.shadowBlockCount
    self.modelRenderBatchCount = self.modelRenderBatchCount + instance.renderBatchCount
    self:CreateInstanceNightLight(instance)
    self.rendered[instance.id] = root
    return true
end

function IslandWorld:ClearInstances()
    self.pendingProjectLoad = nil
    self.pendingPortalActivation = nil
    self.portalTransitionActive = false
    self.portalContactId = nil
    if self.modelBatcher then self.modelBatcher:Clear() end
    for _, instance in ipairs(self.instances) do
        if instance.root then
            self.instanceRoot:remove(instance.root)
            instance.root:getNode():Remove()
            instance.root = nil
        end
    end
    self.instances, self.byId, self.rendered = {}, {}, {}
    self.modelRenderBlockCount, self.modelShadowBlockCount, self.modelRenderBatchCount = 0, 0, 0
    self.renderDetailStats, self.renderDetailElapsed = nil, 0
    self.renderDetailCandidates, self.renderDetailInstances = nil, nil
    self.batchedRecoveryQueue = {}
    self.renderDetailDirty = true
    self.renderDetailRevision = (tonumber(self.renderDetailRevision) or 0) + 1
    self.renderDetailWasMobile = self.mobileDevice == true
    if self.renderDetailPolicy then self.renderDetailPolicy:Reset() end
    self.activeNightLights = {}
    self.nightLightsDirty = true
    self.selectedId, self.pendingSelectionId = nil, nil
    self:ClearSelectionHelper()
end

function IslandWorld:CreateInstance(source, preparedRenderable)
    local assetId, migratedScale
    if self.assetStore.ResolveLegacyInstance then
        assetId, migratedScale = self.assetStore:ResolveLegacyInstance(source.assetId, source.scale)
    else
        assetId, migratedScale = tostring(source.assetId or ""), tonumber(source.scale) or 1
    end
    local asset = self.assetStore:Get(assetId, source.versionId)
    local renderable = preparedRenderable or (asset and self.assetStore:AcquireRenderable(asset) or nil)
    if not renderable then return nil, "missing" end
    local instance = {
        id = tonumber(source.id) or self.nextId,
        assetId = assetId,
        -- Built-ins are authored as a moving official revision. Persist the
        -- resolved version so an island stops carrying stale 1.0.0 cache keys.
        versionId = asset and asset.source == "builtin" and asset.versionId
            or tostring(source.versionId or "latest"),
        x = tonumber(source.x or (source.position and source.position[1])) or 0,
        y = tonumber(source.y or (source.position and source.position[2])) or 0,
        z = tonumber(source.z or (source.position and source.position[3])) or 0,
        rotationY = tonumber(source.rotationY or source.ry) or 0,
        scale = Clamp(migratedScale, 0.1, 3),
        portal = type(source.portal) == "table" and Copy(source.portal) or nil,
    }
    if instance.assetId == "" or not self:RenderInstance(instance, renderable) then return nil, "missing" end
    self.nextId = math.max(self.nextId, instance.id + 1)
    self.instances[#self.instances + 1] = instance
    self.byId[instance.id] = instance
    if instance.usesModelBatcher then self:MarkRenderDetailDirty() end
    return instance
end

function IslandWorld:RemoveInstance(instance)
    if not instance then return end
    self.batchedRecoveryQueue[instance.id] = nil
    if instance.usesModelBatcher and self.modelBatcher then self.modelBatcher:Unregister(instance, false) end
    if instance.root then
        self.instanceRoot:remove(instance.root)
        instance.root:getNode():Remove()
    end
    self.byId[instance.id], self.rendered[instance.id] = nil, nil
    self.modelRenderBlockCount = math.max(0,
        self.modelRenderBlockCount - (tonumber(instance.renderBlockCount) or 0))
    self.modelShadowBlockCount = math.max(0,
        self.modelShadowBlockCount - (tonumber(instance.shadowBlockCount) or 0))
    self.modelRenderBatchCount = math.max(0,
        self.modelRenderBatchCount - (tonumber(instance.renderBatchCount) or 0))
    self.nightLightsDirty = true
    for index, item in ipairs(self.instances) do
        if item == instance then table.remove(self.instances, index); break end
    end
    if self.selectedId == instance.id then self.selectedId = nil end
    if instance.usesModelBatcher then self:MarkRenderDetailDirty() end
    self:RefreshSelectionHelper()
end

function IslandWorld:ClearSelectionHelper()
    if self.selectionHelper then
        self.helperRoot:remove(self.selectionHelper)
        self.selectionHelper:getNode():Remove()
        self.selectionHelper = nil
    end
    if self.selectionHelperMaterial and self.selectionHelperMaterial.dispose then self.selectionHelperMaterial:dispose() end
    if self.selectionHelperGeometry and self.selectionHelperGeometry.dispose then self.selectionHelperGeometry:dispose() end
    self.selectionHelperMaterial, self.selectionHelperGeometry = nil, nil
    self.selectionHelperId, self.selectionHelperAsset = nil, nil
    if self.transformGizmo then self.transformGizmo:Refresh(nil, self.transformMode, self.mobileEditor) end
end

function IslandWorld:RefreshSelectionHelper()
    local instance = self.selectedId and self.byId[self.selectedId] or nil
    if not instance or not instance.renderAsset then self:ClearSelectionHelper(); return end
    if not self.selectionHelper or self.selectionHelperId ~= instance.id or self.selectionHelperAsset ~= instance.renderAsset then
        self:ClearSelectionHelper()
        local material = IslandTransformGizmo.PrepareOverlayMaterial(
            THREE.LineBasicMaterial({ color = 0xffa829, transparent = true, opacity = 1 }))
        local geometry = MakeBoxLines(instance.renderAsset.bounds, 0.08)
        local lines = THREE.LineSegments(geometry, material)
        lines.renderOrder = 9999
        MakerTransformControls.MarkOverlayObject(lines)
        self.helperRoot:add(lines)
        self.selectionHelper = lines
        self.selectionHelperMaterial, self.selectionHelperGeometry = material, geometry
        self.selectionHelperId, self.selectionHelperAsset = instance.id, instance.renderAsset
    end
    self.selectionHelper.position:set(instance.x,
        self:GroundOffset(instance.renderAsset, instance.scale, instance.x, instance.z) + (instance.y or 0),
        instance.z)
    self.selectionHelper.rotation:set(0, instance.rotationY, 0)
    self.selectionHelper.scale:set(instance.scale, instance.scale, instance.scale)
    self:RefreshTransformGizmo()
end

function IslandWorld:SetPresentationPaused(paused)
    paused = paused == true
    if self.presentationPaused == paused then return false end
    self.presentationPaused = paused
    -- Screenshot pause is a presentation surface, so editor-only 3D affordances
    -- must disappear with the native UI without destroying selection or the
    -- current placement preview. Re-enable those exact roots on resume.
    SetSceneGroupEnabled(self.helperRoot, not paused)
    SetSceneGroupEnabled(self.ghostRoot, not paused)
    if self.transformGizmo then
        if paused then self.transformGizmo:Refresh(nil, self.transformMode, self.mobileEditor)
        else self:RefreshTransformGizmo() end
    end
    return true
end

function IslandWorld:SetOnChanged(callback) self.onChanged = callback end
function IslandWorld:SetOnCommit(callback) self.onCommit = callback end
function IslandWorld:SetOnPortalDelete(callback) self.onPortalDelete = callback end

function IslandWorld:SetInstancePortal(instanceId, portal)
    if self.activeHistoryTransaction then
        self.activeHistoryTransaction.externalMutationDetected = true
        self:Notify("撤销或重做仍在完成中，请稍候再绑定云门")
        return false
    end
    local instance = self.byId[tonumber(instanceId)]
    if not instance or instance.assetId ~= PortalTemplate.ASSET_ID then return false end
    instance.portal = type(portal) == "table" and Copy(portal) or nil
    self:RefreshState()
    return true
end

function IslandWorld:QueuePortalActivation(instance, reason)
    if not instance or instance.assetId ~= PortalTemplate.ASSET_ID
        or type(instance.portal) ~= "table" then return false end
    if self.disposed or self.portalTransitionActive or self.pendingProjectLoad
        or self.activeHistoryTransaction then return false end
    if (tonumber(self.portalCooldown) or 0) > 0 then return false end
    self.pendingPortalActivation = {
        instanceId = instance.id,
        portal = Copy(instance.portal),
        reason = tostring(reason or "click"),
        firstPerson = self.firstPerson == true,
    }
    self.portalCooldown = 1.2
    return true
end

function IslandWorld:ActivateSelectedPortal()
    local selected = self:GetSelected()
    if not selected or selected.assetId ~= PortalTemplate.ASSET_ID then return false end
    if type(selected.portal) ~= "table" then
        self:Notify("这座云门尚未绑定另一座空岛")
        return false
    end
    return self:QueuePortalActivation(selected, "button")
end

function IslandWorld:ConsumePortalActivation()
    local pending = self.pendingPortalActivation
    self.pendingPortalActivation = nil
    if pending then self.portalTransitionActive = true end
    return pending
end

function IslandWorld:FinishPortalTransition(succeeded)
    self.pendingPortalActivation = nil
    self.portalTransitionActive = false
    local cooldown = succeeded == true and 1.2 or 0.24
    self.portalCooldown = math.max(tonumber(self.portalCooldown) or 0, cooldown)
    return true
end

function IslandWorld:RemovePortalLocally(instanceId, message, recordHistory)
    if self:RejectMutationWhileLoading() then return false end
    local instance = self.byId[tonumber(instanceId)]
    if not instance or instance.assetId ~= PortalTemplate.ASSET_ID then return false end
    if recordHistory ~= false then self:PushHistory() end
    self:RemoveInstance(instance)
    self:Commit(message or "已移除成对云门")
    return true
end

-- Pair binding changes multiple island projects atomically, while the normal
-- world history contains only this active island. Treat such operations as a
-- persistence checkpoint so Undo can never restore just one half of a link.
function IslandWorld:CheckpointExternalMutation()
    if self.activeHistoryTransaction then
        self.activeHistoryTransaction.externalMutationDetected = true
        self:Notify("撤销或重做仍在完成中，请稍候再修改空岛")
        return false
    end
    self.history, self.future = {}, {}
    self:RefreshState()
    return true
end

function IslandWorld:SetTransformMode(mode)
    if mode ~= "translate" and mode ~= "rotate" and mode ~= "scale" then return false end
    if self.transformMode == mode then return true end
    self.transformMode = mode
    if self.transformGizmo then self.transformGizmo:SetHighlight(nil) end
    self:RefreshTransformGizmo()
    self:RefreshState()
    return true
end

function IslandWorld:GetSelected()
    return self.selectedId and self.byId[self.selectedId] or nil
end

function IslandWorld:Notify(message)
    if self.onChanged then self.onChanged(self:GetState(), message) end
end

function IslandWorld:RefreshState()
    if self.onChanged then self.onChanged(self:GetState(), nil) end
end

function IslandWorld:Commit(message)
    self.projectRevision = self.projectRevision + 1
    self.projectUpdatedAt = Now()
    self.interactiveStateDirty = false
    self.interactiveStateElapsed = 0
    self:RefreshSelectionHelper()
    self:Notify(message)
    if self.onCommit then self.onCommit(self:GetProjectData()) end
end

function IslandWorld:PushHistory()
    if self.activeHistoryTransaction then
        self.activeHistoryTransaction.externalMutationDetected = true
        return false
    end
    return self:RecordHistorySnapshot(SnapshotWorldInstances(self))
end

function IslandWorld:RecordHistorySnapshot(snapshot)
    if self.activeHistoryTransaction then
        self.activeHistoryTransaction.externalMutationDetected = true
        return false
    end
    self.history[#self.history + 1] = Copy(snapshot or {})
    if #self.history > 60 then table.remove(self.history, 1) end
    self.future = {}
    return true
end

function IslandWorld:PrepareInstanceSources(snapshot)
    local sources, prepared = Copy(snapshot or {}), {}
    for index, source in ipairs(sources) do
        local assetId = tostring(source.assetId or "")
        if self.assetStore.ResolveLegacyInstance then
            assetId = self.assetStore:ResolveLegacyInstance(assetId, source.scale)
        end
        local asset = self.assetStore:Get(assetId, source.versionId)
        local renderable = asset and self.assetStore:AcquireRenderable(asset) or nil
        if not renderable then return nil, nil, "missing" end
        prepared[index] = renderable
    end
    return sources, prepared
end

function IslandWorld:InstanceSourcesAvailable(sources)
    for _, source in ipairs(sources or {}) do
        local assetId = tostring(source.assetId or "")
        if self.assetStore.ResolveLegacyInstance then
            assetId = self.assetStore:ResolveLegacyInstance(assetId, source.scale)
        end
        if not self.assetStore:Get(assetId, source.versionId) then return false end
    end
    return true
end

function IslandWorld:RestoreInstances(snapshot, message, persist, prepared, deferNotify)
    self.mode, self.drag = "select", nil
    self.placementAssetId, self.placementVersionId = nil, nil
    self:ClearGhost()
    self:ClearInstances()
    self.nextId = 1
    local sources = Copy(snapshot or {})
    if #sources > 24 then
        ReserveInstanceIds(self, sources)
        self.pendingProjectLoad = {
            sources = sources, index = 1, total = #sources,
            message = message, historyRestore = true, prepared = prepared,
        }
    else
        for index, source in ipairs(sources) do
            if not self:CreateInstance(source, prepared and prepared[index]) then return false end
        end
    end
    local status = self.pendingProjectLoad
        and (tostring(message or "正在恢复空岛") .. " · 正在分批布置") or message
    if not deferNotify then
        if persist then self:Commit(status) else self:Notify(status) end
    end
    return true, status
end

local MAX_INCREMENTAL_HISTORY_CHANGES = 1

-- Normal editing history changes one model at a time. Keep every unaffected
-- native node, render batch and collision object alive instead of clearing the
-- whole island and rebuilding it over several frames. Large generated edits
-- deliberately retain the established incremental full-restore path.
function IslandWorld:RestoreHistoryIncrementally(snapshot)
    local target = Copy(snapshot or {})
    local plan = IslandHistoryPlan.Build(SnapshotWorldInstances(self), target)
    if not plan.valid then return nil, "invalid" end
    if plan.changeCount > MAX_INCREMENTAL_HISTORY_CHANGES
        or #plan.replacements > 0 then
        return false, "full"
    end

    -- Resolve everything that might need creating before mutating the scene.
    -- A missing/deleted custom model must not consume either history stack.
    local prepared = {}
    for index, source in ipairs(plan.additions) do
        local assetId = tostring(source.assetId or "")
        if self.assetStore.ResolveLegacyInstance then
            assetId = self.assetStore:ResolveLegacyInstance(assetId, source.scale)
        end
        local asset = self.assetStore:Get(assetId, source.versionId)
        local renderable = asset and self.assetStore:AcquireRenderable(asset) or nil
        if not renderable then return nil, "missing" end
        prepared[index] = renderable
    end

    local selectedId = self.selectedId

    for _, change in ipairs(plan.updates) do
        local instance, source = self.byId[change.id], change.source
        if not instance then return nil, "live-missing" end
        local previous = InstanceCopy(instance)
        instance.x = tonumber(source.x) or 0
        instance.y = tonumber(source.y) or 0
        instance.z = tonumber(source.z) or 0
        instance.rotationY = tonumber(source.rotationY) or 0
        instance.scale = Clamp(tonumber(source.scale) or 1, 0.1, 3)
        instance.portal = type(source.portal) == "table" and Copy(source.portal) or nil
        self:ApplyInstanceTransform(instance)
        if not self:RefreshBatchedInstanceCell(instance, previous) then
            return nil, "batch"
        end
    end
    for index, source in ipairs(plan.additions) do
        local instance = self:CreateInstance(source, prepared[index])
        if not instance then return nil, "create" end
    end
    for _, id in ipairs(plan.removals) do
        local instance = self.byId[id]
        if not instance then return nil, "live-missing" end
        self:RemoveInstance(instance)
    end

    self.mode, self.drag = "select", nil
    self.placementAssetId, self.placementVersionId = nil, nil
    self:ClearGhost()

    local ordered = {}
    for _, source in ipairs(plan.target) do
        local instance = self.byId[tonumber(source.id)]
        if instance then ordered[#ordered + 1] = instance end
    end
    self.instances = ordered
    self.nextId = 1
    ReserveInstanceIds(self, target)
    self.selectedId = selectedId and self.byId[selectedId] and selectedId or nil
    self.pendingSelectionId = nil
    self:MarkRenderDetailDirty()
    return true
end

function IslandWorld:ApplyHistorySelection(transaction, targetPhase)
    local selectedId = targetPhase and transaction.targetSelectedId
        or transaction.currentSelectedId
    self.selectedId = selectedId and self.byId[selectedId] and selectedId or nil
    self.pendingSelectionId = nil
    self:RefreshSelectionHelper()
end

-- A full history restore is a transaction, not a best-effort render queue.
-- History stacks and persistence are updated only after every target model has
-- been created.  A native creation failure switches to an equally preflighted
-- rollback phase and leaves both history stacks untouched.
function IslandWorld:StartHistoryRestorePhase(transaction, phase)
    if transaction.completed or self.activeHistoryTransaction ~= transaction then
        return nil, "cancelled"
    end
    local targetPhase = phase == "target"
    local sources = targetPhase and transaction.targetSources or transaction.currentSources
    local prepared = targetPhase and transaction.targetPrepared or transaction.currentPrepared
    self.mode, self.drag = "select", nil
    self.placementAssetId, self.placementVersionId = nil, nil
    self:ClearGhost()
    self:ClearInstances()
    self.nextId = 1
    ReserveInstanceIds(self, sources)

    if #sources > 24 then
        local operation = transaction.direction == "undo" and "撤销" or "重做"
        local progress = targetPhase and ("正在" .. operation .. "空岛操作")
            or (operation .. "失败，正在还原原空岛")
        self.pendingProjectLoad = {
            sources = sources,
            prepared = prepared,
            index = 1,
            total = #sources,
            message = transaction.message,
            historyTransaction = transaction,
            historyPhase = phase,
        }
        self:Notify(progress .. " · 0/" .. tostring(#sources))
        return true, "pending"
    end

    for index, source in ipairs(sources) do
        if not self:CreateInstance(source, prepared[index]) then
            return nil, "create"
        end
    end
    return true, "complete"
end

function IslandWorld:CompleteHistoryTransaction(transaction)
    if transaction.completed or self.activeHistoryTransaction ~= transaction then return false end
    if not self:InstanceSourcesAvailable(transaction.targetSources)
        or transaction.externalMutationDetected
        or not IslandHistoryGuard.IsCurrent(transaction.stackCheckpoint,
        self.history, self.future) then
        self.pendingProjectLoad = nil
        return self:BeginHistoryRollback(transaction, "history-changed")
    end
    transaction.completed = true
    self.activeHistoryTransaction = nil
    self:ApplyHistorySelection(transaction, true)
    self:ApplyDayNight(true)
    if transaction.direction == "undo" then
        self.future[#self.future + 1] = Copy(transaction.currentSources)
        if #self.future > 60 then table.remove(self.future, 1) end
        table.remove(self.history)
    else
        self.history[#self.history + 1] = Copy(transaction.currentSources)
        if #self.history > 60 then table.remove(self.history, 1) end
        table.remove(self.future)
    end
    self:Commit(transaction.message)
    return true
end

function IslandWorld:CompleteHistoryRollback(transaction)
    if transaction.completed or self.activeHistoryTransaction ~= transaction then return false end
    transaction.completed = true
    transaction.recoveryFailed = false
    self.activeHistoryTransaction = nil
    self:ApplyHistorySelection(transaction, false)
    self:ApplyDayNight(true)
    self.interactiveStateDirty = false
    local operation = transaction.direction == "undo" and "撤销" or "重做"
    self:Notify(operation .. "失败，已恢复操作前的空岛")
    return false
end

function IslandWorld:FailHistoryRollback(transaction)
    if transaction.completed or self.activeHistoryTransaction ~= transaction then return false end
    self.pendingProjectLoad = nil
    transaction.recoveryFailed = true
    transaction.recoveryRetryElapsed = 0
    transaction.recoveryRetryCount = (tonumber(transaction.recoveryRetryCount) or 0) + 1
    self:ApplyDayNight(true)
    self.interactiveStateDirty = false
    local operation = transaction.direction == "undo" and "撤销" or "重做"
    self:Notify(operation .. "失败，正在重新恢复操作前的空岛 · 暂时不能编辑")
    return false
end

function IslandWorld:BeginHistoryRollback(transaction, reason)
    if transaction.completed or self.activeHistoryTransaction ~= transaction then
        return false, "cancelled"
    end
    transaction.failureReason = reason
    transaction.recoveryFailed = false
    local restored, status = self:StartHistoryRestorePhase(transaction, "rollback")
    if not restored then return self:FailHistoryRollback(transaction), "rollback-failed" end
    if status == "complete" then
        return self:CompleteHistoryRollback(transaction), "rolled-back"
    end
    return false, "rollback-pending"
end

function IslandWorld:BeginHistoryTransaction(direction, snapshot, current, message)
    local plan = IslandHistoryPlan.Build(current or {}, snapshot or {})
    if not plan.valid then return nil, "invalid" end
    local targetSources, targetPrepared = self:PrepareInstanceSources(snapshot)
    if not targetSources then return nil, "missing" end
    local currentSources, currentPrepared = self:PrepareInstanceSources(current)
    if not currentSources then return nil, "rollback-missing" end
    local selectedId = self.selectedId
    local transaction = {
        direction = direction,
        message = message,
        targetSources = targetSources,
        targetPrepared = targetPrepared,
        currentSources = currentSources,
        currentPrepared = currentPrepared,
        currentSelectedId = selectedId,
        targetSelectedId = selectedId,
        stackCheckpoint = IslandHistoryGuard.Capture(direction, self.history, self.future),
    }
    self.activeHistoryTransaction = transaction
    local restored, status = self:StartHistoryRestorePhase(transaction, "target")
    if not restored then
        return self:BeginHistoryRollback(transaction, "create")
    end
    if status == "complete" then self:CompleteHistoryTransaction(transaction) end
    return true, status
end

function IslandWorld:IsProjectLoading()
    return self.pendingProjectLoad ~= nil or self.activeHistoryTransaction ~= nil
        or self:IsEnvironmentLoading()
end

function IslandWorld:CancelHistoryTransaction(reason)
    local transaction = self.activeHistoryTransaction
    if not transaction then return false end
    transaction.cancelled = tostring(reason or "cancelled")
    transaction.completed = true
    self.activeHistoryTransaction = nil
    if self.pendingProjectLoad and self.pendingProjectLoad.historyTransaction == transaction then
        self.pendingProjectLoad = nil
    end
    return true
end

function IslandWorld:RejectMutationWhileLoading()
    if not self.pendingProjectLoad and not self.activeHistoryTransaction
        and not self:IsEnvironmentLoading() then return false end
    local transaction = self.activeHistoryTransaction
    if transaction and transaction.recoveryFailed then
        self:Notify("正在恢复操作前的空岛，请稍候再编辑")
    else
        self:Notify(self:IsEnvironmentLoading()
            and "空岛地形仍在分批生成中，请稍候再编辑"
            or "空岛仍在分批布置中，请稍候再编辑")
    end
    return true
end

function IslandWorld:SetLibrary(tab, summaries)
    self.libraryTab = tab or self.libraryTab
    self.librarySummaries = summaries or {}
    self:RefreshState()
end

function IslandWorld:SetAutoBuildLibrary(summaries)
    self.autoBuildSummaries = summaries or {}
end

function IslandWorld:SetTerrainLibrary(summaries, randomSummaries)
    self.terrainSummaries = type(summaries) == "table" and summaries or nil
    self.randomTerrainSummaries = type(randomSummaries) == "table" and randomSummaries or {}
    self.terrainDisplayName = self.layout.name
    for _, summary in ipairs(self.terrainSummaries or {}) do
        if tostring(summary.id or summary.terrainId or "") == tostring(self.terrainId or "") then
            self.terrainDisplayName = tostring(summary.name or self.layout.name)
            break
        end
    end
    self:RefreshState()
end

function IslandWorld:SetIslandDirectory(summaries, activeId)
    self.islandSummaries = summaries or {}
    self.activeIslandId = activeId and tostring(activeId) or self.activeIslandId
    self:RefreshState()
end

function IslandWorld:SetIslandMarketSyncState(busy, islandId)
    busy = busy == true
    islandId = busy and islandId and tostring(islandId) or nil
    if self.islandMarketSyncBusy == busy
        and self.islandMarketSyncIslandId == islandId then return end
    self.islandMarketSyncBusy = busy
    self.islandMarketSyncIslandId = islandId
    self:RefreshState()
end

function IslandWorld:SetProjectIdentity(islandId, name)
    self.activeIslandId = islandId and tostring(islandId) or self.activeIslandId
    if name then self.projectName = tostring(name) end
    self:RefreshState()
end

function IslandWorld:ApplyDayNight(force)
    local visual = DayNightClock.VisualState(self.dayNight:GetTime())
    self.dayNightVisual = visual
    self.scene.background = visual.background
    if self.skyMaterial and self.skyMaterial.color then self.skyMaterial.color:setHex(visual.skyTint) end
    if self.cloudMaterial and self.cloudMaterial.color then self.cloudMaterial.color:setHex(visual.cloudTint) end
    if self.hemisphere then
        self.hemisphere.color:setHex(visual.hemisphereSky)
        self.hemisphere.groundColor:setHex(visual.hemisphereGround)
        self.hemisphere.intensity = visual.hemisphereIntensity
    end
    if self.sun then
        self.sun.color:setHex(visual.keyColor)
        self.sun.intensity = visual.keyIntensity
    end
    if self.fill then
        self.fill.color:setHex(visual.fillColor)
        self.fill.intensity = visual.fillIntensity
    end

    local angle = visual.celestialAngle
    local sunX, sunY, sunZ = math.cos(angle) * 205, math.sin(angle) * 150, -160
    local moonX, moonY, moonZ = -sunX, -sunY, 150
    if self.sunDisc then self.sunDisc.position:set(sunX, sunY, sunZ) end
    if self.sunHalo then self.sunHalo.position:set(sunX, sunY, sunZ) end
    if self.moonDisc then self.moonDisc.position:set(moonX, moonY, moonZ) end
    if self.moonHalo then self.moonHalo.position:set(moonX, moonY, moonZ) end
    if self.sun then
        local activeX, activeY, activeZ
        if visual.dayFactor >= 0.5 then
            activeX, activeY, activeZ = sunX * 0.20, math.max(12, sunY * 0.20), sunZ * 0.20
        else
            activeX, activeY, activeZ = moonX * 0.20, math.max(12, moonY * 0.20), moonZ * 0.20
        end
        self.sunTargetX, self.sunTargetY, self.sunTargetZ = activeX, activeY, activeZ
        if force == true then
            self.sun.position:set(activeX, activeY, activeZ)
            self.sun:lookAt(self.sunLookTarget)
        end
    end

    local starOpacity = visual.starOpacity
    if self.celestialMaterials then
        self.celestialMaterials[1].opacity = starOpacity
        self.celestialMaterials[2].opacity = Clamp(visual.dayFactor * 1.4, 0, 1)
        self.celestialMaterials[3].opacity = Clamp(visual.dayFactor * 0.38, 0, 0.38)
        self.celestialMaterials[4].opacity = starOpacity
        self.celestialMaterials[5].opacity = starOpacity * 0.28
        self.celestialMaterials[6].opacity = starOpacity * 0.92
        self.celestialMaterials[7].opacity = starOpacity * 0.82
        self.celestialMaterials[8].opacity = starOpacity * 0.88
    end
    if self.starField then self.starField.visible = starOpacity > 0.015 end
    if self.planetGroup then self.planetGroup.visible = starOpacity > 0.035 end
    if self.smallPlanet then self.smallPlanet.visible = starOpacity > 0.035 end
    if self.moonDisc then self.moonDisc.visible = starOpacity > 0.015 end
    if self.moonHalo then self.moonHalo.visible = starOpacity > 0.015 end
    if self.sunDisc then self.sunDisc.visible = visual.dayFactor > 0.015 end
    if self.sunHalo then self.sunHalo.visible = visual.dayFactor > 0.015 end
    self:RefreshNightLights(force == true)
end

function IslandWorld:AdvanceSunDirection(timeStep)
    if not self.sun or self.sunTargetX == nil then return false end
    local delta = Clamp(tonumber(timeStep) or 0, 0, 0.1)
    if delta <= 0 then return false end
    local response = 1 - math.exp(-delta * 9)
    local position = self.sun.position
    local nextX = position.x + (self.sunTargetX - position.x) * response
    local nextY = position.y + (self.sunTargetY - position.y) * response
    local nextZ = position.z + (self.sunTargetZ - position.z) * response
    local dx, dy, dz = nextX - position.x, nextY - position.y, nextZ - position.z
    if dx * dx + dy * dy + dz * dz < 0.00000001 then return false end
    position:set(nextX, nextY, nextZ)
    self.sun:lookAt(self.sunLookTarget)
    return true
end

function IslandWorld:SetTimeOfDay(hour, persist)
    self.dayNight:SetTime(hour)
    self:ApplyDayNight(true)
    if persist then
        self:Commit("世界时间已设为 " .. self.dayNight:GetTimeLabel())
    else
        self:RefreshState()
    end
    return true
end

function IslandWorld:CommitTimeSettings()
    self:Commit("世界时间已设为 " .. self.dayNight:GetTimeLabel())
    return true
end

function IslandWorld:SetTimeAuto(enabled)
    self.dayNight:SetAuto(enabled)
    self:Commit(self.dayNight:IsAuto() and "已开启昼夜自动流逝" or "已暂停昼夜自动流逝")
    return true
end

function IslandWorld:GetScreenRay(x, y)
    return ViewportCoordinates.GetScreenRay(self.camera, self.viewportRect, x, y)
end

function IslandWorld:RaycastMaximumDistance()
    local cameraFar = tonumber(self.layout.RENDER_DISTANCE and self.layout.RENDER_DISTANCE.cameraFar)
        or 1400
    return math.max(500, math.min(cameraFar * 0.90,
        (tonumber(self.maxOrbitRadius) or 320) * 1.50))
end

function IslandWorld:RayGround(x, y)
    local ray = self:GetScreenRay(x, y)
    if not ray then return nil end
    local hit = self.layout:RaycastGround(ray)
    if not hit then return nil end
    return ray.origin + ray.direction * hit.distance, hit
end

function IslandWorld:RayInstance(x, y)
    local ray = self:GetScreenRay(x, y)
    if not ray then return nil end
    local maximumDistance = self:RaycastMaximumDistance()
    local results = self.octree and self.octree:Raycast(
        ray, RAY_TRIANGLE, maximumDistance, DRAWABLE_GEOMETRY, MakerTransformControls.SCENE_MASK
    ) or {}
    local triangle
    for _, result in ipairs(results) do
        local nodeName = result.node and tostring(result.node.name or "") or ""
        local id = tonumber(nodeName:match("^IslandInstance_(%d+)$"))
        if not id and self.modelBatcher then id = tonumber(self.modelBatcher:ResolveRay(result)) end
        if id and self.byId[id] then
            local distance = tonumber(result.distance) or math.huge
            if not triangle or distance < triangle.distance then
                triangle = { instance = self.byId[id], result = result, distance = distance }
            end
        end
    end

    -- Sparse models have a deliberately readable whole-model bounds box while
    -- their real triangles may be only a few pixels wide. Use that oriented
    -- box as a bounded fallback instead of expanding every triangle collider.
    local fallback
    local viewportHeight = math.max(1,
        (tonumber(self.viewportRect.bottom) or graphics:GetHeight())
        - (tonumber(self.viewportRect.top) or 0))
    for _, instance in ipairs(self.instances or {}) do
        local asset = instance.renderAsset
        if instance.renderDetailVisible ~= false
            and asset and IslandPicking.UseBoundsFallback(asset) then
            local rootY = self:GroundOffset(asset, instance.scale, instance.x, instance.z)
                + (instance.y or 0)
            local center = IslandPicking.InstanceCenter(instance, asset, rootY)
            local cameraDistance = IslandPicking.Distance(self.camera and self.camera.position, center)
            local dpr = graphics and graphics.GetDPR and graphics:GetDPR() or 1
            local pointerScale = math.max(1, tonumber(self.uiScale) or 1, tonumber(dpr) or 1)
            local padding = IslandPicking.WorldPadding(cameraDistance, viewportHeight,
                self.mobileEditor, self.camera and self.camera.fov or 40, pointerScale)
            local distance = IslandPicking.RayInstanceBounds(
                ray, instance, asset, rootY, padding, maximumDistance)
            if distance and (not fallback or distance < fallback.distance) then
                fallback = {
                    instance = instance,
                    result = { distance = distance, proxy = true },
                    distance = distance,
                }
            end
        end
    end
    local chosen = IslandPicking.Choose(triangle, fallback)
    if chosen then return chosen.instance, chosen.result end
    return nil
end

function IslandWorld:RayIslandBody(x, y)
    local ray = self:GetScreenRay(x, y)
    if not ray then return nil end
    local results = self.octree and self.octree:Raycast(
        ray, RAY_TRIANGLE, self:RaycastMaximumDistance(),
        DRAWABLE_GEOMETRY, MakerTransformControls.SCENE_MASK
    ) or {}
    local nearest
    for _, result in ipairs(results) do
        local nodeName = result.node and tostring(result.node.name or "") or ""
        local islandIndex = IslandPicking.EnvironmentIslandIndex(nodeName)
        local island = islandIndex and self.layout.islands[islandIndex] or nil
        local distance = tonumber(result.distance)
        if island and distance and (not nearest or distance < nearest.distance) then
            nearest = { island = island, result = result, distance = distance }
        end
    end
    if nearest then return nearest.island, nearest.result end
    return nil
end

function IslandWorld:Footprint(instance, asset, x, z, rotationY, scale)
    return self.layout:Footprint(instance, asset, x, z, rotationY, scale)
end

function IslandWorld:IsPlacementValid(asset, x, z, rotationY, scale, ignoreId, y)
    return self.layout:IsPlacementValid(
        self.instances, asset, x, z, rotationY, scale, ignoreId, nil, y)
end

function IslandWorld:ClearGhost()
    if self.ghost then
        self.ghostRoot:remove(self.ghost)
        self.ghost:getNode():Remove()
        self.ghost = nil
    end
    if self.ghostMaterial and self.ghostMaterial.dispose then self.ghostMaterial:dispose() end
    self.ghostMaterial = nil
end

function IslandWorld:RebuildGhost()
    self:ClearGhost()
    if self.mode ~= "place" or not self.placementAssetId then return end
    local asset = self.assetStore:Get(self.placementAssetId, self.placementVersionId)
    local renderable = asset and self.assetStore:AcquireRenderable(asset) or nil
    if not renderable then return end
    local color = self.placementValid and 0x4bd8a0 or 0xf35b58
    local material = IslandTransformGizmo.PrepareOverlayMaterial(
        THREE.MeshBasicMaterial({ color = color, transparent = true, opacity = 0.52 }))
    self.ghostMaterial = material
    self.ghostAsset = renderable
    self.ghost = self:BuildAssetGroup(renderable, "IslandGhost", material, true)
    self.ghostRoot:add(self.ghost)
    self:ApplyGhostTransform()
end

function IslandWorld:ApplyGhostTransform()
    if not self.ghost or not self.ghostAsset then return end
    self.ghost.position:set(self.placementX,
        self:GroundOffset(self.ghostAsset, self.placementScale, self.placementX, self.placementZ),
        self.placementZ)
    self.ghost.rotation:set(0, self.placementRotation, 0)
    self.ghost.scale:set(self.placementScale, self.placementScale, self.placementScale)
end

function IslandWorld:UpdatePlacement(x, y)
    if self.mode ~= "place" then return false end
    local point = self:RayGround(x, y)
    if not point then return false end
    local renderable = self.ghostAsset
    if not renderable then
        local asset = self.assetStore:Get(self.placementAssetId, self.placementVersionId)
        renderable = asset and self.assetStore:AcquireRenderable(asset) or nil
    end
    if not renderable then return false end
    local nextX, nextZ = Snap(point.x, self.snap), Snap(point.z, self.snap)
    local valid = self:IsPlacementValid(
        renderable, nextX, nextZ, self.placementRotation, self.placementScale)
    local validChanged = valid ~= self.placementValid
    self.placementX, self.placementZ, self.placementValid = nextX, nextZ, valid
    if validChanged or not self.ghost then self:RebuildGhost() else self:ApplyGhostTransform() end
    return true
end

function IslandWorld:StartPlacement(assetId, versionId)
    if self.readOnly then self:Notify("参观模式不能修改这座空岛"); return false end
    if self:RejectMutationWhileLoading() then return false end
    local asset = self.assetStore:Get(assetId, versionId)
    local renderable, errorMessage = nil, nil
    if asset then renderable, errorMessage = self.assetStore:AcquireRenderable(asset) end
    if not renderable then self:Notify(errorMessage or "模型不存在"); return false end
    self.mode = "place"
    self.selectedId = nil
    self:MarkRenderDetailDirty()
    self.placementAssetId = asset.assetId
    self.placementVersionId = asset.versionId
    local maxSide = math.max(renderable.bounds.size[1], renderable.bounds.size[3], 1)
    self.placementScale = Clamp(tonumber(renderable.recommendedScale or asset.recommendedScale)
        or (6 / maxSide), 0.2, 1)
    self.placementRotation = 0
    self.placementX, self.placementZ = self.target.x, self.target.z
    local overview = self.layout:Overview()
    if math.abs(self.target.y - (overview.y or ORBIT_TARGET_Y)) > 0.001 then
        self:BeginOrbitFocus(self.target.x, overview.y or ORBIT_TARGET_Y, self.target.z, self.radius)
    end
    self.placementValid = self:IsPlacementValid(
        renderable, self.placementX, self.placementZ, 0, self.placementScale)
    self.assetStore:MarkUsed(asset)
    self:RefreshSelectionHelper()
    self:RebuildGhost()
    self:Notify("移动预览到岛上，点击即可放置《" .. asset.name .. "》")
    return true
end

function IslandWorld:CancelPlacement()
    self.mode = "select"
    self.placementAssetId, self.placementVersionId = nil, nil
    self:ClearGhost()
    self:Notify("已返回选择模式")
end

function IslandWorld:PlaceCurrent()
    if self:RejectMutationWhileLoading() then return false end
    if not self.placementValid or not self.ghostAsset then
        self:Notify("当前位置超出空岛，或模型几乎完全被另一个模型包住")
        return false
    end
    local historySnapshot = SnapshotWorldInstances(self)
    -- Remove the preview first so placement never transiently holds two full
    -- copies of a detailed model.
    self:ClearGhost()
    local instance = self:CreateInstance({
        id = self.nextId,
        assetId = self.placementAssetId,
        versionId = self.placementVersionId,
        x = self.placementX,
        z = self.placementZ,
        rotationY = self.placementRotation,
        scale = self.placementScale,
    })
    if not instance then
        self:Notify("模型放置失败")
        self:RebuildGhost()
        return false
    end
    if not self:RecordHistorySnapshot(historySnapshot) then
        self:RemoveInstance(instance)
        self:Notify("模型放置失败")
        self:RebuildGhost()
        return false
    end
    self.selectedId = nil
    local asset = self.assetStore:Get(instance.assetId, instance.versionId)
    if instance.assetId == PortalTemplate.ASSET_ID then
        self.mode = "select"
        self.placementAssetId, self.placementVersionId = nil, nil
        self.selectedId = instance.id
        self:RefreshSelectionHelper()
        self:Commit("已放置成对云门 · 请选择另一座空岛完成绑定")
        return true
    end
    self.placementValid = self:IsPlacementValid(self.ghostAsset, self.placementX, self.placementZ,
        self.placementRotation, self.placementScale)
    self:RebuildGhost()
    self:Commit("已放置《" .. tostring(asset and asset.name or "模型") .. "》· 点击模型后可整体编辑")
    return true
end

function IslandWorld:Tap(x, y)
    if self.firstPerson then return end
    if self.readOnly then
        -- A published visit is read-only, but its validated cloud gates remain
        -- interactive. Directly hitting a bound gate takes priority over the
        -- usual island-focus gesture and never selects or edits the instance.
        local instance = self:RayInstance(x, y)
        if instance and instance.assetId == PortalTemplate.ASSET_ID
            and type(instance.portal) == "table" then
            if self:QueuePortalActivation(instance, "click") then
                self:Notify("正在穿过云门……")
                return
            end
        end
        local island = self:RayIslandBody(x, y)
        if island then self:FocusIsland(island); return end
        local point = self:RayGround(x, y)
        if point and self:FocusIslandAt(point.x, point.z) then return end
        self:FocusArchipelago()
        return
    end
    if self.mode == "place" then
        self:UpdatePlacement(x, y)
        self:PlaceCurrent()
        return
    end
    local instance, instanceHit = self:RayInstance(x, y)
    local island, islandHit = self:RayIslandBody(x, y)
    if island and IslandPicking.IsIslandInFront(
            islandHit and islandHit.distance, instanceHit and instanceHit.distance) then
        self.selectedId = nil
        self:MarkRenderDetailDirty()
        self:RefreshSelectionHelper()
        self:FocusIsland(island)
        return
    end
    if not instance then
        self.selectedId = nil
        self:MarkRenderDetailDirty()
        self:RefreshSelectionHelper()
        local point = self:RayGround(x, y)
        if point and self:FocusIslandAt(point.x, point.z) then return end
        self:FocusArchipelago()
        return
    end
    if instance.assetId == PortalTemplate.ASSET_ID and type(instance.portal) == "table"
        and self.selectedId == instance.id then
        if self:QueuePortalActivation(instance, "click") then
            self:Notify("正在穿过云门……")
            return
        end
    end
    self:Select(instance)
end

function IslandWorld:Select(instance)
    if self.readOnly then return false end
    self.selectedId = instance and instance.id or nil
    self:MarkRenderDetailDirty()
    self:RefreshMobileRenderDetail(true)
    self:RefreshSelectionHelper()
    if instance then self:FocusSelected() end
    self:RefreshState()
    return true
end

function IslandWorld:SelectById(id)
    local numericId = tonumber(id)
    local instance = numericId and self.byId[numericId] or nil
    if numericId and not instance and self.pendingProjectLoad then
        self.pendingSelectionId = numericId
        return false
    end
    self.pendingSelectionId = nil
    self:Select(instance)
    return instance ~= nil
end

function IslandWorld:FocusSelected()
    local instance = self:GetSelected()
    if not instance or not instance.renderAsset then return false end
    local asset = instance.renderAsset
    local scale = tonumber(instance.scale) or 1
    local center = self:TransformCenter(instance)
    if not center then return false end
    local viewportWidth = math.max(1, self.viewportRect.right - self.viewportRect.left)
    local viewportHeight = math.max(1, self.viewportRect.bottom - self.viewportRect.top)
    local focusRadius = self.layout:SelectionFocusRadius(asset, scale, self.radius,
        viewportWidth / viewportHeight)
    self.focusedIslandId = nil
    self:BeginOrbitFocus(center.x, center.y, center.z, focusRadius)
    return true
end

function IslandWorld:BeginTransformDrag(x, y, isTouch)
    if self.firstPerson or self.readOnly then return false end
    if self:RejectMutationWhileLoading() then return false end
    if self.mode == "place" then
        self:UpdatePlacement(x, y)
        if isTouch then
            self.drag = { placement = true, startX = x, startY = y, moved = false }
            return true
        end
        return false
    end
    local selected = self:GetSelected()
    if not selected then return false end
    local handle = self.transformGizmo and self.transformGizmo:HitScreen(
        x, y, isTouch,
        function(sampleX, sampleY) return self:GetScreenRay(sampleX, sampleY) end,
        self.uiScale, self.viewportRect) or nil
    if handle then
        local drag = {
            gizmo = true,
            mode = self.transformMode,
            handle = handle,
            snapshot = SnapshotWorldInstances(self),
            startInstance = InstanceCopy(selected),
            id = selected.id,
            startPointerX = x,
            startPointerY = y,
            reverseRotation = isTouch == true and self.mobileEditor,
            valid = true,
        }
        if drag.mode == "translate" and handle ~= "y" then
            drag.startGround = self:RayGround(x, y)
            if not drag.startGround then return false end
        elseif drag.mode == "rotate" then
            drag.centerX, drag.centerY = self.transformGizmo:ProjectCenter(self.viewportRect)
            if not drag.centerX then return false end
            drag.startAngle = math.atan(y - drag.centerY, x - drag.centerX)
        end
        self.drag = drag
        self.transformGizmo:SetHighlight(handle)
        return true
    end
    if self.transformMode ~= "translate" then return false end
    local hit = self:RayInstance(x, y)
    if hit ~= selected then return false end
    local point = self:RayGround(x, y)
    if not point then return false end
    self.drag = {
        snapshot = SnapshotWorldInstances(self),
        startInstance = InstanceCopy(selected),
        id = selected.id,
        offsetX = selected.x - point.x,
        offsetZ = selected.z - point.z,
        valid = true,
    }
    return true
end

function IslandWorld:DragTransform(x, y)
    if not self.drag then return false end
    if self.drag.placement then
        -- Touch events normally drift a few framebuffer pixels between begin
        -- and end. Use the same scaled threshold as main.lua so one layer
        -- cannot call it a tap while this layer rejects it as a drag.
        local threshold = self:PointerDragThreshold(true)
        if not ViewportCoordinates.IsTapMovement(
            self.drag.startX, self.drag.startY, x, y, threshold) then self.drag.moved = true end
        return self:UpdatePlacement(x, y)
    end
    local drag = self.drag
    local instance = self.byId[drag.id]
    if not instance then return false end
    if drag.gizmo then
        local start = drag.startInstance
        local nextX, nextY, nextZ = start.x, start.y, start.z
        local nextRotation, nextScale = start.rotationY, start.scale
        if drag.mode == "translate" then
            if drag.handle == "y" then
                local viewportHeight = math.max(1, self.viewportRect.bottom - self.viewportRect.top)
                nextY = Clamp(start.y - (y - drag.startPointerY) * self.radius / viewportHeight * 1.4, -2, 15)
            else
                local point = self:RayGround(x, y)
                if not point then return false end
                local deltaX = point.x - drag.startGround.x
                local deltaZ = point.z - drag.startGround.z
                if drag.handle == "x" or drag.handle == "xz" or drag.handle == "xyz" then
                    nextX = start.x + deltaX
                end
                if drag.handle == "z" or drag.handle == "xz" or drag.handle == "xyz" then
                    nextZ = start.z + deltaZ
                end
            end
        elseif drag.mode == "rotate" then
            local angle = math.atan(y - drag.centerY, x - drag.centerX)
            nextRotation = start.rotationY + ViewportCoordinates.RotationDelta(
                drag.startAngle, angle, drag.reverseRotation)
        else
            local pointerDelta = (x - drag.startPointerX) - (y - drag.startPointerY)
            nextScale = Clamp(start.scale * math.exp(pointerDelta * 0.008), 0.1, 3)
        end
        local valid = self:IsPlacementValid(
            instance.renderAsset, nextX, nextZ, nextRotation, nextScale, instance.id, nextY)
        drag.valid = valid
        if valid then
            instance.x, instance.y, instance.z = nextX, nextY, nextZ
            instance.rotationY, instance.scale = nextRotation, nextScale
        end
    else
        local point = self:RayGround(x, y)
        if not point then return false end
        local nextX = point.x + drag.offsetX
        local nextZ = point.z + drag.offsetZ
        local valid = self:IsPlacementValid(instance.renderAsset, nextX, nextZ,
            instance.rotationY, instance.scale, instance.id, instance.y)
        drag.valid = valid
        if valid then instance.x, instance.z = nextX, nextZ end
    end
    self:ApplyInstanceTransform(instance)
    self:RefreshSelectionHelper()
    self.interactiveStateDirty = true
    return true
end

function IslandWorld:EndTransformDrag()
    if not self.drag then return false end
    if self.drag.placement then
        local shouldPlace = not self.drag.moved
        self.drag = nil
        if shouldPlace then return self:PlaceCurrent() end
        return true
    end
    local drag = self.drag
    local instance = self.byId[drag.id]
    local start = drag.startInstance
    local changed = instance and start and (
        math.abs(instance.x - start.x) > 0.0001
        or math.abs((instance.y or 0) - (start.y or 0)) > 0.0001
        or math.abs(instance.z - start.z) > 0.0001
        or math.abs((instance.rotationY or 0) - (start.rotationY or 0)) > 0.0001
        or math.abs((instance.scale or 1) - (start.scale or 1)) > 0.0001)
    self.drag = nil
    if self.transformGizmo then self.transformGizmo:SetHighlight(nil) end
    if changed then
        if not self:RefreshBatchedInstanceCell(instance, start) then
            self.interactiveStateDirty = false
            self:RefreshSelectionHelper()
            self:Notify("移动失败，模型已恢复原位置")
            return false
        end
        self.history[#self.history + 1] = drag.snapshot
        if #self.history > 60 then table.remove(self.history, 1) end
        self.future = {}
        local message = drag.mode == "rotate" and "已旋转完整模型"
            or drag.mode == "scale" and "已等比缩放完整模型" or "已移动完整模型"
        self:Commit(message)
    else
        self.interactiveStateDirty = false
        self:RefreshState()
    end
    return changed
end

function IslandWorld:CancelTransformDrag()
    if not self.drag then return false end
    if self.drag.placement then self.drag = nil; return true end
    local drag = self.drag
    self.drag = nil
    local instance = self.byId[drag.id]
    local start = drag.startInstance
    if instance and start then
        instance.x, instance.y, instance.z = start.x, start.y, start.z
        instance.rotationY, instance.scale = start.rotationY, start.scale
        self:ApplyInstanceTransform(instance)
    end
    if self.transformGizmo then self.transformGizmo:SetHighlight(nil) end
    self.interactiveStateDirty = false
    self:RefreshSelectionHelper()
    self:RefreshState()
    return true
end

function IslandWorld:IsFixedTransformDrag() return false end
function IslandWorld:BeginMobileTransformGesture() return false end
function IslandWorld:DragMobileTransformGesture() return false end
function IslandWorld:IsNearGizmo(x, y, isTouch)
    return self.transformGizmo and self.transformGizmo:HitScreen(
        x, y, isTouch,
        function(sampleX, sampleY) return self:GetScreenRay(sampleX, sampleY) end,
        self.uiScale, self.viewportRect) ~= nil or false
end
function IslandWorld:IsInMobileGizmoGestureArea() return false end
function IslandWorld:HoverTransform(x, y)
    if self.readOnly then return false end
    if self.mode == "place" then return self:UpdatePlacement(x, y) end
    local handle = self.transformGizmo and self.transformGizmo:Hit(self:GetScreenRay(x, y)) or nil
    if self.transformGizmo then self.transformGizmo:SetHighlight(handle) end
    return handle ~= nil
end
function IslandWorld:ClearTransformHover()
    if self.transformGizmo and not self.drag then self.transformGizmo:SetHighlight(nil) end
end
function IslandWorld:SetMobileGizmoSuppressed() end
function IslandWorld:IsColorPicking() return false end
function IslandWorld:CancelColorPick() return false end

function IslandWorld:PointerDragThreshold(isTouch)
    return (isTouch and 9 or 4) * math.max(1, self.uiScale or 1)
end

function IslandWorld:RotatePlacement(deltaDegrees)
    if self.mode ~= "place" then return end
    if self:RejectMutationWhileLoading() then return false end
    self.placementRotation = self.placementRotation + (tonumber(deltaDegrees) or 0) * DEG
    local valid = self:IsPlacementValid(self.ghostAsset, self.placementX, self.placementZ,
        self.placementRotation, self.placementScale)
    if valid ~= self.placementValid then self.placementValid = valid; self:RebuildGhost()
    else self.placementValid = valid; self:ApplyGhostTransform() end
    self:RefreshState()
end

function IslandWorld:ScalePlacement(delta)
    if self.mode ~= "place" then return end
    if self:RejectMutationWhileLoading() then return false end
    self.placementScale = Clamp(self.placementScale + (tonumber(delta) or 0), 0.1, 3)
    local valid = self:IsPlacementValid(self.ghostAsset, self.placementX, self.placementZ,
        self.placementRotation, self.placementScale)
    if valid ~= self.placementValid then self.placementValid = valid; self:RebuildGhost()
    else self.placementValid = valid; self:ApplyGhostTransform() end
    self:RefreshState()
end

function IslandWorld:TransformSelected(kind, amount)
    if self.readOnly then self:Notify("参观模式不能修改这座空岛"); return false end
    if self:RejectMutationWhileLoading() then return false end
    local instance = self:GetSelected()
    if not instance then self:Notify("请先点击选择岛上的模型"); return false end
    local snapshot = SnapshotWorldInstances(self)
    local previous = InstanceCopy(instance)
    local oldRotation, oldScale, oldX, oldY, oldZ =
        instance.rotationY, instance.scale, instance.x, instance.y, instance.z
    if kind == "rotate" then instance.rotationY = instance.rotationY + (tonumber(amount) or 0) * DEG
    elseif kind == "scale" then instance.scale = Clamp(instance.scale + (tonumber(amount) or 0), 0.1, 3)
    elseif kind == "x" then instance.x = Snap(instance.x + (tonumber(amount) or 0), self.snap)
    elseif kind == "z" then instance.z = Snap(instance.z + (tonumber(amount) or 0), self.snap)
    elseif kind == "y" then instance.y = Clamp((instance.y or 0) + (tonumber(amount) or 0), -2, 15) end
    if not self:IsPlacementValid(instance.renderAsset, instance.x, instance.z,
        instance.rotationY, instance.scale, instance.id, instance.y) then
        instance.rotationY, instance.scale, instance.x, instance.y, instance.z =
            oldRotation, oldScale, oldX, oldY, oldZ
        self:Notify("调整后会超出空岛，或模型几乎完全被另一个模型包住")
        return false
    end
    self:ApplyInstanceTransform(instance)
    if not self:RefreshBatchedInstanceCell(instance, previous) then
        self:RefreshSelectionHelper()
        self:Notify("调整失败，模型已恢复原位置")
        return false
    end
    self.history[#self.history + 1] = snapshot
    if #self.history > 60 then table.remove(self.history, 1) end
    self.future = {}
    self:Commit(kind == "rotate" and "已旋转完整模型" or kind == "scale" and "已等比缩放完整模型" or "已微调模型位置")
    return true
end

function IslandWorld:DuplicateSelected()
    if self.readOnly then return false end
    if self:RejectMutationWhileLoading() then return false end
    local selected = self:GetSelected()
    if not selected then return false end
    local source = InstanceCopy(selected)
    source.id = self.nextId
    if source.assetId == PortalTemplate.ASSET_ID then source.portal = nil end
    local placed = false
    for radius = 1, 8 do
        local x = selected.x + radius * 0.5
        local z = selected.z + radius * 0.5
        if self:IsPlacementValid(selected.renderAsset, x, z,
            selected.rotationY, selected.scale, nil, selected.y) then
            source.x, source.z, placed = x, z, true
            break
        end
    end
    if not placed then
        self:Notify("附近没有足够空间复制模型")
        return false
    end
    local historySnapshot = SnapshotWorldInstances(self)
    local copy = self:CreateInstance(source)
    if not copy then
        self:Notify("复制模型失败")
        return false
    end
    if not self:RecordHistorySnapshot(historySnapshot) then
        self:RemoveInstance(copy)
        self:Notify("复制模型失败")
        return false
    end
    self.selectedId = copy and copy.id or nil
    self:Commit("已复制完整模型")
    return copy ~= nil
end

function IslandWorld:DeleteSelected()
    if self.readOnly then return false end
    if self:RejectMutationWhileLoading() then return false end
    local selected = self:GetSelected()
    if not selected then return false end
    self:PushHistory()
    self:RemoveInstance(selected)
    self:Commit("已从空岛移除模型")
    return true
end

function IslandWorld:Undo()
    if self.readOnly then return false end
    if self:RejectMutationWhileLoading() then return false end
    if #self.history == 0 then return false end
    local current = SnapshotWorldInstances(self)
    local target = self.history[#self.history]
    local incremental, reason = self:RestoreHistoryIncrementally(target)
    if incremental == nil then
        local message = reason == "missing" and "撤销失败：历史模型已不存在"
            or reason == "invalid" and "撤销失败：历史记录已损坏"
            or "撤销失败，请稍后重试"
        self:Notify(message)
        return false
    end
    local status = "已撤销空岛操作"
    if not incremental then
        local started, result = self:BeginHistoryTransaction("undo", target, current, status)
        if started then return true end
        if result == "missing" or result == "rollback-missing" then
            self:Notify("撤销失败：历史模型已不存在")
        elseif result == "invalid" then
            self:Notify("撤销失败：历史记录已损坏")
        end
        return false
    end
    self.future[#self.future + 1] = current
    if #self.future > 60 then table.remove(self.future, 1) end
    table.remove(self.history)
    self:Commit(status)
    return true
end

function IslandWorld:Redo()
    if self.readOnly then return false end
    if self:RejectMutationWhileLoading() then return false end
    if #self.future == 0 then return false end
    local current = SnapshotWorldInstances(self)
    local target = self.future[#self.future]
    local incremental, reason = self:RestoreHistoryIncrementally(target)
    if incremental == nil then
        local message = reason == "missing" and "重做失败：历史模型已不存在"
            or reason == "invalid" and "重做失败：历史记录已损坏"
            or "重做失败，请稍后重试"
        self:Notify(message)
        return false
    end
    local status = "已重做空岛操作"
    if not incremental then
        local started, result = self:BeginHistoryTransaction("redo", target, current, status)
        if started then return true end
        if result == "missing" or result == "rollback-missing" then
            self:Notify("重做失败：历史模型已不存在")
        elseif result == "invalid" then
            self:Notify("重做失败：历史记录已损坏")
        end
        return false
    end
    self.history[#self.history + 1] = current
    if #self.history > 60 then table.remove(self.history, 1) end
    table.remove(self.future)
    self:Commit(status)
    return true
end

function IslandWorld:NewIsland()
    if self.readOnly then return false end
    if self:RejectMutationWhileLoading() then return false end
    self:PushHistory()
    self:RestoreInstances({}, "已新建空白空岛", true)
end

function IslandWorld:ApplyGeneratedPlan(plan)
    if self.readOnly then self:Notify("参观模式不能一键建岛"); return false end
    if self:RejectMutationWhileLoading() then return false end
    local planned = type(plan) == "table" and plan.instances or nil
    if type(planned) ~= "table" or #planned == 0 then
        self:Notify("没有找到可放置的模型")
        return false
    end
    local sources, prepared, nextId = {}, {}, self.nextId
    for _, source in ipairs(planned) do
        local asset = self.assetStore:Get(source.assetId, source.versionId)
        local renderable = asset and self.assetStore:AcquireRenderable(asset) or nil
        if renderable then
            local x, z = tonumber(source.x) or 0, tonumber(source.z) or 0
            local rotationY, scale = tonumber(source.rotationY) or 0, tonumber(source.scale) or 1
            local footprint = self.layout:Footprint(nil, renderable, x, z, rotationY, scale)
            if self.layout:IsFootprintSupported(footprint, 0.12) then
                sources[#sources + 1] = {
                    id = nextId, assetId = asset.assetId, versionId = asset.versionId,
                    x = x, y = tonumber(source.y) or 0, z = z,
                    rotationY = rotationY, scale = scale,
                }
                prepared[#sources] = renderable
                nextId = nextId + 1
            end
        end
    end
    if #sources == 0 then self:Notify("所选模型在当前地形上没有合适位置"); return false end
    local transaction = {
        currentSources = SnapshotWorldInstances(self),
        currentNextId = self.nextId,
        currentSelectedId = self.selectedId,
        createdIds = {},
    }
    self.mode, self.selectedId = "select", nil
    self:ClearGhost()
    self:RefreshSelectionHelper()
    local summary = type(plan.stats) == "table" and tostring(plan.stats.summary or "") or ""
    local completeMessage = "一键建岛完成 · 新增 " .. tostring(#sources) .. " 个模型"
    if summary ~= "" then completeMessage = summary .. " · 共 " .. tostring(#sources) .. " 个模型" end
    if #sources <= 16 then
        for index, source in ipairs(sources) do
            local instance = self:CreateInstance(source, prepared[index])
            if not instance then
                self:RollbackGeneratedPlan(transaction, "一键建岛失败，已恢复操作前的空岛")
                return false
            end
            transaction.createdIds[#transaction.createdIds + 1] = instance.id
        end
        if not self:RecordHistorySnapshot(transaction.currentSources) then
            self:RollbackGeneratedPlan(transaction, "一键建岛失败，已恢复操作前的空岛")
            return false
        end
        self:Commit(completeMessage)
    else
        ReserveInstanceIds(self, sources)
        self.pendingProjectLoad = {
            sources = sources, index = 1, total = #sources,
            prepared = prepared,
            message = completeMessage,
            generatedTransaction = transaction,
        }
        -- Keep persistence on currentSources until every native instance has
        -- been created. A mid-queue failure can then remove only the additions
        -- without ever saving or exposing a half-built island.
        self:Notify("一键建岛正在布置 · 0/" .. tostring(#sources))
    end
    return true, #sources
end

function IslandWorld:RollbackGeneratedPlan(transaction, message)
    if type(transaction) ~= "table" then return false end
    for index = #(transaction.createdIds or {}), 1, -1 do
        local instance = self.byId[tonumber(transaction.createdIds[index])]
        if instance then self:RemoveInstance(instance) end
    end
    self.nextId = math.max(1, tonumber(transaction.currentNextId) or self.nextId)
    local selectedId = tonumber(transaction.currentSelectedId)
    self.selectedId = selectedId and self.byId[selectedId] and selectedId or nil
    self.pendingSelectionId = nil
    self.mode = "select"
    self:ApplyDayNight(true)
    self:RefreshSelectionHelper()
    self:Notify(message or "一键建岛失败，已恢复操作前的空岛")
    return false
end

function IslandWorld:GetTerrainId()
    return self.terrainId
end

function IslandWorld:CanUseTerrain(terrainId)
    local candidate = IslandLayout.Resolve(terrainId)
    if candidate.id == self.terrainId then return true, 0 end
    local invalid = 0
    for _, instance in ipairs(SnapshotWorldInstances(self)) do
        local asset = self.assetStore:Get(instance.assetId, instance.versionId)
        local renderable = asset and self.assetStore:AcquireRenderable(asset) or nil
        local footprint = candidate:Footprint(instance, renderable)
        local supported = candidate:IsFootprintSupported(footprint)
        if not supported then invalid = invalid + 1 end
    end
    return invalid == 0, invalid
end

function IslandWorld:GetProjectData()
    local instances = SnapshotWorldInstances(self)
    return {
        schema = "island-project/v2",
        version = 2,
        revision = self.projectRevision,
        updatedAt = self.projectUpdatedAt,
        name = self.projectName or "我的空岛",
        islandId = self.activeIslandId,
        terrainId = self.terrainId,
        terrain = { preset = self.terrainId, groundY = self.layout:DefaultGroundY() },
        environment = {
            timeOfDay = Clean(self.dayNight:GetTime()),
            autoTime = self.dayNight:IsAuto(),
            dayDuration = self.dayNight.dayDuration,
        },
        instances = instances,
        camera = {
            theta = Clean(self.theta), phi = Clean(self.phi), radius = Clean(self.radius),
            target = { Clean(self.target.x), Clean(self.target.y), Clean(self.target.z) },
        },
    }
end

function IslandWorld:SetReadOnly(entry)
    self.readOnly = entry ~= nil and entry ~= false
    self.visitOwner = self.readOnly and tostring(entry.owner or "云岛旅人") or nil
    self.visitOwnerId = self.readOnly and tostring(entry.ownerId or "") or nil
    self.visitAvatar = self.readOnly and entry.avatar or nil
    self.visitIslandId = self.readOnly and tostring(entry.islandId
        or (type(entry.project) == "table" and entry.project.islandId) or self.activeIslandId or "") or nil
    self.visitName = self.readOnly and tostring(entry.name or self.projectName or "玩家空岛") or nil
    self.selectedId = nil
    self:MarkRenderDetailDirty()
    self.mode = "select"
    self:ClearGhost()
    self:RefreshSelectionHelper()
    self:RefreshState()
end

function IslandWorld:LoadProjectData(data, message, options)
    if type(data) ~= "table" or type(data.instances) ~= "table" then return false end
    options = options or {}
    local terrain = type(data.terrain) == "table" and data.terrain or {}
    local requestedTerrainId = IslandLayout.ResolveId(data.terrainId or terrain.preset)
    if requestedTerrainId ~= self.terrainId then return false, "terrain_mismatch" end
    -- Project navigation is an explicit transaction cancellation point. The
    -- caller persists the stable pre-operation snapshot before loading the new
    -- project, and no delayed history completion may touch the new stacks.
    self:CancelHistoryTransaction("project-load")
    self.projectName = tostring(data.name or "我的空岛")
    self.activeIslandId = data.islandId and tostring(data.islandId) or self.activeIslandId
    self.projectRevision = math.max(0, tonumber(data.revision) or 0)
    self.projectUpdatedAt = tonumber(data.updatedAt) or 0
    local environment = type(data.environment) == "table" and data.environment or {}
    self.dayNight:SetTime(tonumber(environment.timeOfDay) or 9.5)
    self.dayNight:SetAuto(environment.autoTime ~= false)
    self.dayNight.dayDuration = math.max(60, tonumber(environment.dayDuration) or 480)
    self:ClearInstances()
    self.nextId = 1
    local sources = Copy(data.instances)
    if options.incremental == true and #sources > 24 then
        local priorityId = tonumber(options.priorityInstanceId)
        local prioritySource
        if priorityId then
            for index, source in ipairs(sources) do
                if tonumber(source.id) == priorityId then
                    if self:CreateInstance(source) then
                        prioritySource = source
                        table.remove(sources, index)
                    end
                    break
                end
            end
        end
        if prioritySource then
            local priorityX, priorityZ = tonumber(prioritySource.x) or 0, tonumber(prioritySource.z) or 0
            local safeRadius = math.max(2.5, tonumber(options.priorityRadius) or 4.5)
            local deferred = {}
            for _, source in ipairs(sources) do
                local asset = self.assetStore:Get(source.assetId, source.versionId)
                local bounds = asset and asset.bounds or {}
                local size, scale = bounds.size or {}, math.max(0.1, tonumber(source.scale) or 1)
                local extent = math.sqrt((tonumber(size[1]) or 1) ^ 2
                    + (tonumber(size[3]) or 1) ^ 2) * scale * 0.5
                local dx, dz = (tonumber(source.x) or 0) - priorityX,
                    (tonumber(source.z) or 0) - priorityZ
                if math.sqrt(dx * dx + dz * dz) <= safeRadius + extent then
                    if not self:CreateInstance(source) then deferred[#deferred + 1] = source end
                else
                    deferred[#deferred + 1] = source
                end
            end
            sources = deferred
        end
        if #sources > 0 then
            ReserveInstanceIds(self, sources)
            self.pendingProjectLoad = {
                sources = sources,
                index = 1,
                total = #sources,
                message = message or ("已恢复空岛 · " .. tostring(#data.instances) .. " 个模型"),
            }
        end
    else
        for _, source in ipairs(sources) do self:CreateInstance(source) end
    end
    local camera = data.camera
    if type(camera) == "table" then
        self.theta = tonumber(camera.theta) or self.theta
        self.phi = Clamp(tonumber(camera.phi) or self.phi, 12 * DEG, 84 * DEG)
        local overview = self.layout:Overview()
        self.radius = Clamp(tonumber(camera.radius) or self.radius,
            MIN_ORBIT_RADIUS, self.maxOrbitRadius)
        local target = camera.target or {}
        self.target:set(
            tonumber(target[1]) or overview.x,
            tonumber(target[2]) or overview.y or ORBIT_TARGET_Y,
            tonumber(target[3]) or overview.z
        )
        self:ApplyCamera()
    end
    self:ApplyDayNight(true)
    self.history, self.future = {}, {}
    if self.pendingProjectLoad then
        self:Notify("正在布置《" .. tostring(self.projectName) .. "》· 0/"
            .. tostring(self.pendingProjectLoad.total))
    else
        self:Notify(message or ("已恢复空岛 · " .. tostring(#self.instances) .. " 个模型"))
    end
    return true
end

function IslandWorld:AdvancePendingProjectLoad()
    local pending = self.pendingProjectLoad
    if not pending then return false end
    local created, blockBudget = 0, 0
    local maxCreated = self.mobileDevice and (self.readOnly and 5 or 7) or 12
    local maxBlockBudget = self.mobileDevice and (self.readOnly and 90 or 120) or 180
    while pending.index <= pending.total and created < maxCreated do
        local source = pending.sources[pending.index]
        local renderable = pending.prepared and pending.prepared[pending.index] or nil
        if not renderable then
            local asset = self.assetStore:Get(source.assetId, source.versionId)
            renderable = asset and self.assetStore:AcquireRenderable(asset) or nil
        end
        local cost = renderable and #renderable.blocks or 1
        if created > 0 and blockBudget + cost > maxBlockBudget then break end
        local instance = self:CreateInstance(source, renderable)
        if not instance and pending.historyTransaction then
            local transaction, phase = pending.historyTransaction, pending.historyPhase
            self.pendingProjectLoad = nil
            if phase == "target" then
                self:BeginHistoryRollback(transaction, "create")
            else
                self:FailHistoryRollback(transaction)
            end
            return true
        end
        if not instance and pending.generatedTransaction then
            local transaction = pending.generatedTransaction
            self.pendingProjectLoad = nil
            self:RollbackGeneratedPlan(transaction,
                "一键建岛失败，已恢复操作前的空岛")
            return true
        end
        if instance and pending.generatedTransaction then
            local createdIds = pending.generatedTransaction.createdIds
            createdIds[#createdIds + 1] = instance.id
        end
        if instance and self.pendingSelectionId == instance.id then
            self.pendingSelectionId = nil
            self:Select(instance)
        end
        pending.index = pending.index + 1
        created = created + 1
        blockBudget = blockBudget + cost
    end
    if pending.index > pending.total then
        local message = pending.message
        self.pendingProjectLoad = nil
        if pending.historyTransaction then
            if pending.historyPhase == "target" then
                self:CompleteHistoryTransaction(pending.historyTransaction)
            else
                self:CompleteHistoryRollback(pending.historyTransaction)
            end
        elseif pending.generatedTransaction then
            local transaction = pending.generatedTransaction
            if not self:InstanceSourcesAvailable(pending.sources)
                or not self:RecordHistorySnapshot(transaction.currentSources) then
                self:RollbackGeneratedPlan(transaction,
                    "一键建岛失败，已恢复操作前的空岛")
            else
                self:ApplyDayNight(true)
                self:Commit(message)
            end
        else
            self:ApplyDayNight(true)
            self:Notify(message)
        end
    end
    return true
end

function IslandWorld:LoadDefault()
    self:RestoreInstances({}, "欢迎来到空岛 · 从模型库继续建设", false)
end

function IslandWorld:IsInViewport(x, y)
    local rect = self.viewportRect
    return x >= rect.left and x < rect.right and y >= rect.top and y < rect.bottom
end

function IslandWorld:SetThermalFrameTarget(fps)
    local target = math.max(1, tonumber(fps) or 60)
    if math.abs(target - (tonumber(self.thermalTargetFps) or 60)) < 0.1 then return end
    self.thermalTargetFps = target
    -- A deliberate 30 -> 45 FPS tier change is not a slow frame. Reset the
    -- smoothed sample to the new pacing interval so resuming interaction does
    -- not briefly hide and rebuild decorative model batches.
    self.renderDetailFrameTime = 1 / target
    self.renderDetailPressureState = MobileThermalPolicy.ResetFramePressureState(
        self.renderDetailPressureState, 0)
    if self.renderDetailPressureBand ~= 0 then
        self.renderDetailPressureBand = 0
        self:MarkRenderDetailDirty()
    end
end

function IslandWorld:SetViewportRect(left, top, right, bottom, uiScale, editorMode)
    local width, height = graphics:GetWidth(), graphics:GetHeight()
    left, top = Clamp(math.floor(left + 0.5), 0, width - 1), Clamp(math.floor(top + 0.5), 0, height - 1)
    right, bottom = Clamp(math.floor(right + 0.5), left + 1, width), Clamp(math.floor(bottom + 0.5), top + 1, height)
    self.viewportRect = { left = left, top = top, right = right, bottom = bottom }
    self.uiScale = tonumber(uiScale) or self.uiScale
    self:MarkRenderDetailDirty()
    self.mobileEditor = editorMode == "mobile"
    local nativeCamera = self.camera and self.camera.getCamera and self.camera:getCamera() or nil
    if nativeCamera then
        if nativeCamera.SetAutoAspectRatio then nativeCamera:SetAutoAspectRatio(false) end
        nativeCamera.aspectRatio = math.max(1, right - left) / math.max(1, bottom - top)
    end
    local materialModeChanged = self.materialSystem:SetMobileWater(self.mobileDevice)
    self:ApplyRenderQuality()
    if self.viewport then self.viewport:SetRect(IntRect(left, top, right, bottom)) end
    if materialModeChanged and #self.instances > 0 then
        local snapshot, selectedId = SnapshotInstances(self.instances), self.selectedId
        local pending, pendingSelectionId = self.pendingProjectLoad, self.pendingSelectionId
        self:ClearInstances()
        self.nextId = 1
        for _, source in ipairs(snapshot) do self:CreateInstance(source) end
        self.pendingProjectLoad, self.pendingSelectionId = pending, pendingSelectionId
        if pending then ReserveInstanceIds(self, pending.sources) end
        self.selectedId = selectedId and self.byId[selectedId] and selectedId or nil
        self:RefreshSelectionHelper()
        if self.mode == "place" then self:RebuildGhost() end
    end
    self:RefreshTransformGizmo()
end

function IslandWorld:ApplyCamera()
    if self.firstPerson then return self:ApplyFirstPersonCamera() end
    local sinPhi = math.sin(self.phi)
    self.camera.position:set(
        self.target.x + self.radius * sinPhi * math.sin(self.theta),
        self.target.y + self.radius * math.cos(self.phi),
        self.target.z + self.radius * sinPhi * math.cos(self.theta)
    )
    self.camera:lookAt(self.target)
    -- The sky is an infinitely-distant backdrop. Keeping its sphere centred
    -- on the active camera removes the blue circular cut-out that appeared
    -- through the far side of the dome at maximum phone zoom-out.
    if self.skyRoot then
        self.skyRoot.position:set(self.camera.position.x, self.camera.position.y, self.camera.position.z)
    end
    self:RefreshDynamicShadowPolicy(false)
    if self.transformGizmo then self:RefreshTransformGizmo() end
    self:MarkRenderDetailCameraChanged(false)
end

function IslandWorld:ApplyFirstPersonCamera()
    local cosinePitch = math.cos(self.firstPersonPitch)
    local forwardX = math.sin(self.firstPersonYaw) * cosinePitch
    local forwardY = math.sin(self.firstPersonPitch)
    local forwardZ = math.cos(self.firstPersonYaw) * cosinePitch
    local eyeY = (self.firstPersonFeetY or self.firstPersonGroundY or self.layout:DefaultGroundY())
        + FIRST_PERSON_EYE_HEIGHT
    self.camera.position:set(self.firstPersonX, eyeY, self.firstPersonZ)
    self.camera:lookAt(THREE.Vector3(
        self.firstPersonX + forwardX,
        eyeY + forwardY,
        self.firstPersonZ + forwardZ
    ))
    if self.skyRoot then
        self.skyRoot.position:set(self.camera.position.x, self.camera.position.y, self.camera.position.z)
    end
    self:RefreshDynamicShadowPolicy(false)
    self:MarkRenderDetailCameraChanged(false)
end

function IslandWorld:IsFirstPerson()
    return self.firstPerson == true
end

function IslandWorld:IsFirstPersonFlying()
    return self.firstPerson == true and self.firstPersonFlying == true
end

function IslandWorld:IsPointInsideCollider(collider, x, z, padding)
    local cosine, sine = math.cos(collider.angle), math.sin(collider.angle)
    local dx, dz = x - collider.x, z - collider.z
    local localX = math.abs(dx * cosine - dz * sine)
    local localZ = math.abs(dx * sine + dz * cosine)
    padding = tonumber(padding) or 0
    return localX <= collider.halfWidth + padding and localZ <= collider.halfDepth + padding
end

function IslandWorld:FindFirstPersonSurface(x, z, currentGroundY)
    local terrainY = self.layout:SurfaceAt(x, z, 0)
    local best = terrainY or self.layout:MinimumGroundY()
    local maximumStepY = (tonumber(currentGroundY) or best) + FIRST_PERSON_STEP_HEIGHT
    for _, instance in ipairs(self.instances) do
        if self.layout:ContainsInFootprint(
            instance.firstPersonFootprint, x, z, FirstPersonScale.SURFACE_PADDING) then
            for _, surface in ipairs(instance.firstPersonSurfaces or {}) do
                if surface.maximumY <= maximumStepY + 0.001 and surface.maximumY > best
                    and self:IsPointInsideCollider(surface, x, z, FirstPersonScale.SURFACE_PADDING) then
                    best = surface.maximumY
                end
            end
        end
    end
    return best
end

function IslandWorld:IsFirstPersonBlocked(x, z, groundY)
    local playerRadius = FIRST_PERSON_RADIUS
    local fallbackGroundY = self.layout:SurfaceAt(x, z, 0) or self.layout:DefaultGroundY()
    local playerMinY = (tonumber(groundY) or fallbackGroundY) + 0.02
    local playerMaxY = (tonumber(groundY) or fallbackGroundY) + FIRST_PERSON_HEIGHT
    for _, instance in ipairs(self.instances) do
        if self.layout:ContainsInFootprint(instance.firstPersonFootprint, x, z, playerRadius) then
            for _, collider in ipairs(instance.firstPersonColliders or {}) do
                if not collider.passableDoor and not collider.passableFluid
                    and collider.maximumY > playerMinY and collider.minimumY < playerMaxY
                    and self:IsPointInsideCollider(collider, x, z, playerRadius) then return true end
            end
        end
    end
    return false
end

function IslandWorld:CanFirstPersonStand(x, z, currentGroundY)
    if not self.layout:ContainsPoint(x, z, FIRST_PERSON_RADIUS + 0.08) then
        return false, currentGroundY or self.layout:DefaultGroundY()
    end
    local surfaceY = self:FindFirstPersonSurface(x, z, currentGroundY)
    return not self:IsFirstPersonBlocked(x, z, surfaceY), surfaceY
end

function IslandWorld:IsFirstPersonGroundClear(x, z, clearance)
    clearance = math.max(FIRST_PERSON_RADIUS, tonumber(clearance) or FIRST_PERSON_RADIUS)
    if not self.layout:ContainsPoint(x, z, clearance + 0.08) then return false end
    for _, instance in ipairs(self.instances) do
        if self.layout:ContainsInFootprint(instance.firstPersonFootprint, x, z, clearance) then return false end
    end
    return true
end

function IslandWorld:FirstPersonEscapeCount(x, z, groundY)
    local count = 0
    local distance = math.max(0.30, FIRST_PERSON_RADIUS * 3.5)
    for index = 0, 7 do
        local angle = TAU * index / 8
        local valid = self:CanFirstPersonStand(
            x + math.sin(angle) * distance,
            z + math.cos(angle) * distance,
            groundY
        )
        if valid then count = count + 1 end
    end
    return count
end

function IslandWorld:TryFirstPersonMove(x, z)
    if not self.layout:ContainsPoint(x, z, FIRST_PERSON_RADIUS + 0.08) then return false end
    local surfaceY = self:FindFirstPersonSurface(x, z, self.firstPersonGroundY)
    local feetY = self.firstPersonOnGround and surfaceY or self.firstPersonFeetY
    if self:IsFirstPersonBlocked(x, z, feetY) then return false end
    self.firstPersonX, self.firstPersonZ = x, z
    self.firstPersonGroundY = surfaceY
    if self.firstPersonOnGround then
        local drop = self.firstPersonFeetY - surfaceY
        if drop <= FIRST_PERSON_STEP_HEIGHT then
            self.firstPersonFeetY = surfaceY
        else
            self.firstPersonOnGround = false
        end
    end
    return true
end

function IslandWorld:TryFirstPersonFlyMove(x, z, feetY)
    -- Flight may cross the gaps between the three islands, but remains inside
    -- the authored archipelago and cloud field instead of drifting forever.
    local overview = self.layout:Overview()
    local limit = math.max(110, (tonumber(overview.radius) or 42) * 2.5)
    if math.abs(x - (overview.x or 0)) > limit or math.abs(z - (overview.z or 0)) > limit then return false end
    feetY = Clamp(tonumber(feetY) or self.firstPersonFeetY,
        self.layout:MinimumGroundY(), FIRST_PERSON_FLIGHT_MAX_Y)
    if self:IsFirstPersonBlocked(x, z, feetY) then return false end
    self.firstPersonX, self.firstPersonZ, self.firstPersonFeetY = x, z, feetY
    self.firstPersonGroundY = self:FindFirstPersonSurface(x, z, feetY)
    return true
end

function IslandWorld:FindFirstPersonSpawn()
    -- Prefer a genuinely open patch of island instead of merely a point that
    -- does not overlap a collider. This prevents dense saved islands from
    -- spawning the player in a narrow gap with no direction to walk out.
    for _, island in ipairs(self.layout.ISLANDS) do
        for ring = 0, 18 do
            local radiusX = math.max(0, (island.radiusX or island.radius) - 1.2 - ring * 0.6)
            local radiusZ = math.max(0, (island.radiusZ or island.radius) - 1.2 - ring * 0.6)
            local radius = math.max(radiusX, radiusZ)
            local steps = radius < 0.01 and 1 or math.max(24, math.ceil(TAU * radius / 0.55))
            for index = 0, steps - 1 do
                local angle = TAU * (index + (ring % 2) * 0.5) / steps
                local x = island.x + math.sin(angle) * radiusX
                local z = island.z + math.cos(angle) * radiusZ
                if self:IsFirstPersonGroundClear(x, z, 0.48) then
                    return x, z, self.layout:SurfaceAt(x, z, 0) or island.groundY
                end
            end
        end
    end

    local fallbackX, fallbackZ, fallbackY = nil, nil, nil
    for _, island in ipairs(self.layout.ISLANDS) do
        for ring = 0, 18 do
            local radiusX = math.max(0, (island.radiusX or island.radius) - 1.2 - ring * 0.6)
            local radiusZ = math.max(0, (island.radiusZ or island.radius) - 1.2 - ring * 0.6)
            local radius = math.max(radiusX, radiusZ)
            local steps = radius < 0.01 and 1 or math.max(24, math.ceil(TAU * radius / 0.55))
            for index = 0, steps - 1 do
                local angle = TAU * (index + (ring % 2) * 0.5) / steps
                local x = island.x + math.sin(angle) * radiusX
                local z = island.z + math.cos(angle) * radiusZ
                local valid, surfaceY = self:CanFirstPersonStand(x, z, island.groundY)
                if valid then
                    fallbackX, fallbackZ, fallbackY = fallbackX or x, fallbackZ or z, fallbackY or surfaceY
                    if self:FirstPersonEscapeCount(x, z, surfaceY) >= 3 then return x, z, surfaceY end
                end
            end
        end
    end
    return fallbackX or 0, fallbackZ or 0, fallbackY or self.layout:DefaultGroundY()
end

function IslandWorld:EnterFirstPerson()
    if self.firstPerson then return true end
    if self.mode == "place" then self:CancelPlacement() end
    self.cameraFocusAnimation = nil
    self.selectedId = nil
    self:MarkRenderDetailDirty()
    self:ClearSelectionHelper()
    self.firstPersonX, self.firstPersonZ, self.firstPersonGroundY = self:FindFirstPersonSpawn()
    self.firstPersonFeetY = self.firstPersonGroundY
    self.firstPersonVisualGroundY = self.firstPersonGroundY
    self.firstPersonVerticalVelocity = 0
    self.firstPersonOnGround = true
    self.firstPersonFlying = false
    self.firstPersonFlightVertical = 0
    self.firstPersonYaw = math.atan(-self.firstPersonX, -self.firstPersonZ)
    self.firstPersonPitch = 0
    self.firstPersonForward, self.firstPersonRight = 0, 0
    self.firstPersonFast = false
    self.firstPersonRun = false
    self.firstPerson = true
    self.mode = "preview"
    self.camera.fov = 72
    self:ApplyFirstPersonCamera()
    self:Notify("第一人称漫游 · 可行走、跳跃或开启飞行探索整片空岛")
    return true
end

function IslandWorld:ExitFirstPerson()
    if not self.firstPerson then return false end
    self.firstPerson = false
    self.firstPersonForward, self.firstPersonRight = 0, 0
    self.firstPersonFast = false
    self.firstPersonRun = false
    self.firstPersonVerticalVelocity = 0
    self.firstPersonOnGround = true
    self.firstPersonFlying = false
    self.firstPersonFlightVertical = 0
    self.portalContactId = nil
    self.mode = "select"
    self.camera.fov = 40
    self:ApplyCamera()
    self:Notify("已退出第一人称预览")
    return true
end

function IslandWorld:CheckFirstPersonPortal()
    if not self.firstPerson or self.disposed or self.portalTransitionActive
        or self.pendingProjectLoad then return false end
    local nearest, nearestDistance
    for _, instance in ipairs(self.instances or {}) do
        if instance.assetId == PortalTemplate.ASSET_ID and type(instance.portal) == "table" then
            local dx, dz = self.firstPersonX - instance.x, self.firstPersonZ - instance.z
            local scale = math.max(0.1, tonumber(instance.scale) or 1)
            local angle = tonumber(instance.rotationY) or 0
            local cosine, sine = math.cos(angle), math.sin(angle)
            local localX = dx * cosine - dz * sine
            local localZ = dx * sine + dz * cosine
            local rootY = self:GroundOffset(instance.renderAsset, scale, instance.x, instance.z)
                + (tonumber(instance.y) or 0)
            local feetY = tonumber(self.firstPersonFeetY) or rootY
            local insideOpening = math.abs(localX) <= math.max(0.52, 0.90 * scale)
                and math.abs(localZ) <= math.max(0.24, 0.34 * scale)
                and feetY >= rootY - 0.22
                and feetY <= rootY + math.max(1.45, 2.35 * scale)
            local distance = math.sqrt(localX * localX + localZ * localZ)
            if insideOpening and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = instance, distance
            end
        end
    end
    local contactId = nearest and nearest.id or nil
    if nearest and self.portalContactId ~= contactId and (self.portalCooldown or 0) <= 0 then
        self.portalContactId = contactId
        return self:QueuePortalActivation(nearest, "walk")
    end
    self.portalContactId = contactId
    return false
end

function IslandWorld:ArriveAtPortal(instanceId, firstPerson)
    local instance = self.byId[tonumber(instanceId)]
    if not instance or instance.assetId ~= PortalTemplate.ASSET_ID then return false end
    self.pendingPortalActivation = nil
    self.portalTransitionActive = false
    self.portalCooldown = 1.2
    self.portalContactId = instance.id
    local angle = tonumber(instance.rotationY) or 0
    local offset = math.max(1.08, (tonumber(instance.scale) or 1) * 1.12)
    local arrivalX = instance.x + math.sin(angle) * offset
    local arrivalZ = instance.z + math.cos(angle) * offset
    if firstPerson then
        if not self.firstPerson then self:EnterFirstPerson() end
        local valid, surfaceY = self:CanFirstPersonStand(arrivalX, arrivalZ, self.layout:DefaultGroundY())
        if not valid then
            arrivalX, arrivalZ = instance.x - math.sin(angle) * offset, instance.z - math.cos(angle) * offset
            valid, surfaceY = self:CanFirstPersonStand(arrivalX, arrivalZ, self.layout:DefaultGroundY())
        end
        if not valid then
            for ring = 1, 3 do
                local radius = offset + ring * 0.85
                for step = 0, 15 do
                    local searchAngle = angle + step * TAU / 16
                    local candidateX = instance.x + math.sin(searchAngle) * radius
                    local candidateZ = instance.z + math.cos(searchAngle) * radius
                    local candidateValid, candidateY = self:CanFirstPersonStand(
                        candidateX, candidateZ, self.layout:DefaultGroundY())
                    if candidateValid then
                        arrivalX, arrivalZ, surfaceY, valid = candidateX, candidateZ, candidateY, true
                        break
                    end
                end
                if valid then break end
            end
        end
        if not valid then
            self:ExitFirstPerson()
            self:Select(instance)
            self:Notify("已抵达目标空岛 · 云门周围较拥挤，已切换为俯视模式")
            return true
        end
        self.firstPersonX, self.firstPersonZ = arrivalX, arrivalZ
        self.firstPersonGroundY = surfaceY or self.layout:SurfaceAt(arrivalX, arrivalZ, 0)
            or self.layout:DefaultGroundY()
        self.firstPersonFeetY = self.firstPersonGroundY
        self.firstPersonVisualGroundY = self.firstPersonGroundY
        self.firstPersonYaw, self.firstPersonPitch = NormalizeAngle(angle + math.pi), 0
        self.firstPersonVerticalVelocity, self.firstPersonOnGround = 0, true
        self:ApplyFirstPersonCamera()
        self:Notify("已穿过云门 · 继续漫游这座空岛")
    else
        self:Select(instance)
        self:Notify("已抵达云门另一端 · 再次点击可返回")
    end
    return true
end

function IslandWorld:SetFirstPersonMovement(forward, right, fast)
    if not self.firstPerson then return false end
    self.firstPersonForward = Clamp(tonumber(forward) or 0, -1, 1)
    self.firstPersonRight = Clamp(tonumber(right) or 0, -1, 1)
    self.firstPersonFast = fast == true
    return true
end

function IslandWorld:SetFirstPersonJoystickVisual(x, y, active)
    local nextActive = active == true and self.firstPerson == true
    local nextX = nextActive and (tonumber(x) or 0) or 0
    local nextY = nextActive and (tonumber(y) or 0) or 0
    local changed = self.firstPersonJoystickActive ~= nextActive
        or math.abs(self.firstPersonJoystickX - nextX) > 0.5
        or math.abs(self.firstPersonJoystickY - nextY) > 0.5
    self.firstPersonJoystickActive = nextActive
    self.firstPersonJoystickX, self.firstPersonJoystickY = nextX, nextY
    if changed then self:RefreshState() end
    return true
end

function IslandWorld:IsFirstPersonRunEnabled()
    return self.firstPersonRun == true
end

function IslandWorld:ToggleFirstPersonRun()
    if not self.firstPerson then return false end
    self.firstPersonRun = not self.firstPersonRun
    self.firstPersonFast = self.firstPersonRun
    self:RefreshState()
    return self.firstPersonRun
end

function IslandWorld:ToggleFirstPersonFlying()
    if not self.firstPerson then return false end
    if self.firstPersonFlying and not self.layout:ContainsPoint(
        self.firstPersonX, self.firstPersonZ, FIRST_PERSON_RADIUS + 0.08
    ) then
        self:Notify("请先飞到岛面或桥面上方，再关闭飞行")
        return true
    end
    self.firstPersonFlying = not self.firstPersonFlying
    self.firstPersonFlightVertical = 0
    self.firstPersonVerticalVelocity = 0
    if self.firstPersonFlying then
        self.firstPersonOnGround = false
        self:Notify("飞行已开启 · 可跨越岛屿，上升或下降探索")
    else
        local surfaceY = self:FindFirstPersonSurface(
            self.firstPersonX, self.firstPersonZ, self.firstPersonFeetY
        )
        self.firstPersonGroundY = surfaceY
        if self.firstPersonFeetY <= surfaceY + 0.03 then
            self.firstPersonFeetY = surfaceY
            self.firstPersonOnGround = true
        else
            self.firstPersonOnGround = false
        end
        self:Notify("飞行已关闭 · 已恢复重力")
    end
    self:RefreshState()
    return self.firstPersonFlying
end

function IslandWorld:SetFirstPersonFlightVertical(value)
    if not self.firstPerson or not self.firstPersonFlying then
        self.firstPersonFlightVertical = 0
        return false
    end
    self.firstPersonFlightVertical = Clamp(tonumber(value) or 0, -1, 1)
    return true
end

function IslandWorld:NudgeFirstPersonFlight(direction)
    if not self.firstPerson or not self.firstPersonFlying then return false end
    local nextFeetY = Clamp(
        self.firstPersonFeetY + Clamp(tonumber(direction) or 0, -1, 1) * 0.9,
        self.layout:MinimumGroundY(), FIRST_PERSON_FLIGHT_MAX_Y
    )
    if not self:TryFirstPersonFlyMove(self.firstPersonX, self.firstPersonZ, nextFeetY) then return false end
    self:ApplyFirstPersonCamera()
    return true
end

function IslandWorld:JumpFirstPerson()
    if self.firstPersonFlying then return self:NudgeFirstPersonFlight(1) end
    if not self.firstPerson or not self.firstPersonOnGround then return false end
    self.firstPersonVerticalVelocity = FIRST_PERSON_JUMP_SPEED
    self.firstPersonOnGround = false
    return true
end

function IslandWorld:LookFirstPerson(dx, dy, isTouch)
    if not self.firstPerson then return false end
    local sensitivity = isTouch and 0.0042 or 0.0032
    -- Dragging in either input system turns the view in the same direction as
    -- the pointer. In particular, dragging a phone finger upward looks up.
    self.firstPersonYaw = NormalizeAngle(self.firstPersonYaw - (tonumber(dx) or 0) * sensitivity)
    self.firstPersonPitch = Clamp(self.firstPersonPitch - (tonumber(dy) or 0) * sensitivity,
        -82 * DEG, 82 * DEG)
    self:ApplyFirstPersonCamera()
    return true
end

function IslandWorld:OrbitByPixels(dx, dy, isTouch)
    if self.firstPerson then return end
    if isTouch then
        local threshold = math.max(1.2, math.min(2.4, (tonumber(self.uiScale) or 1) * 0.8))
        dx, dy = CameraMotionStability.FilterPointerDelta(dx, dy, threshold)
        if dx == 0 and dy == 0 then return false end
    end
    self.cameraFocusAnimation = nil
    self.focusedIslandId = nil
    local height = math.max(1, self.viewportRect.bottom - self.viewportRect.top)
    if isTouch and self.mobileEditor then
        -- Direct manipulation must remain tied to the finger. Queueing touch
        -- deltas as inertia made low-FPS dense views release them unevenly.
        self.deltaTheta, self.deltaPhi = 0, 0
        self.theta = NormalizeAngle(self.theta - TAU * dx / height)
        self.phi = Clamp(self.phi - TAU * dy / height, 12 * DEG, 84 * DEG)
        self:ApplyCamera()
        return true
    end
    self.deltaTheta = self.deltaTheta - TAU * dx / height
    self.deltaPhi = self.deltaPhi - TAU * dy / height
    return true
end

function IslandWorld:StopCameraMotion()
    self.cameraFocusAnimation = nil
    self.deltaTheta, self.deltaPhi, self.radiusScale = 0, 0, 1
end

function IslandWorld:PanByPixels(dx, dy, isGesture)
    -- Orbit mode always permits a free camera target. Tapping an island or a
    -- model performs only a one-shot focus; the next two-finger/right-button
    -- pan can immediately move away from that point.
    if self.firstPerson then return false end
    dx, dy = ViewportCoordinates.NormalizePanDelta(dx, dy, isGesture, self.mobileEditor)
    if isGesture and self.mobileEditor then
        dx, dy = CameraMotionStability.FilterPointerDelta(dx, dy, 0.75)
        if dx == 0 and dy == 0 then return false end
    end
    self.cameraFocusAnimation = nil
    local viewX = self.target.x - self.camera.position.x
    local viewY = self.target.y - self.camera.position.y
    local viewZ = self.target.z - self.camera.position.z
    local viewLength = math.sqrt(viewX * viewX + viewY * viewY + viewZ * viewZ)
    if viewLength < 0.001 then return false end
    viewX, viewY, viewZ = viewX / viewLength, viewY / viewLength, viewZ / viewLength
    local rightX, rightZ = -viewZ, viewX
    local rightLength = math.sqrt(rightX * rightX + rightZ * rightZ)
    if rightLength > 0.001 then rightX, rightZ = rightX / rightLength, rightZ / rightLength end
    local upX, upZ = -rightZ * viewY, rightX * viewY
    local height = math.max(1, self.viewportRect.bottom - self.viewportRect.top)
    local scale = 2 * self.radius * math.tan((self.camera.fov or 40) * DEG * 0.5) / height
    -- A Mac trackpad reports much smaller midpoint deltas than direct phone
    -- contacts. Give desktop two-finger placement panning a stronger response
    -- while leaving the already-correct phone tuning unchanged.
    scale = scale * (isGesture and (self.mobileEditor and 1.35 or 1.8) or 1.05)
    local overview = self.layout:Overview()
    local limit = overview.radius * 0.78
    local targetY = self.target.y
    self.target:set(
        Clamp(self.target.x + (-dx * rightX + dy * upX) * scale, overview.x - limit, overview.x + limit),
        targetY,
        Clamp(self.target.z + (-dx * rightZ + dy * upZ) * scale, overview.z - limit, overview.z + limit)
    )
    self.focusedIslandId = nil
    self:ApplyCamera()
    return true
end

function IslandWorld:Zoom(factor)
    if self.firstPerson then return end
    self.cameraFocusAnimation = nil
    self.focusedIslandId = nil
    self.radiusScale = self.radiusScale * Clamp(tonumber(factor) or 1, 0.5, 2)
end

function IslandWorld:ZoomByGesture(factor)
    factor = CameraMotionStability.FilterPinchFactor(factor, 0.006)
    if factor == 1 then return false end
    if self.mobileEditor then
        self.cameraFocusAnimation = nil
        self.focusedIslandId = nil
        self.radiusScale = 1
        self.radius = Clamp(self.radius * factor, MIN_ORBIT_RADIUS, self.maxOrbitRadius)
        self:ApplyCamera()
        return true
    end
    self:Zoom(factor)
    return true
end

function IslandWorld:SetView(name)
    if self.firstPerson then return end
    self.cameraFocusAnimation = nil
    if name == "top" then self.theta, self.phi = 0, 12 * DEG
    elseif name == "front" then self.theta, self.phi = 0, 58 * DEG
    else self.theta, self.phi = 42 * DEG, 55 * DEG end
    self:ApplyCamera()
    self:RefreshState()
end

function IslandWorld:FocusIslandAt(x, z)
    local island = self.layout:IslandAt(x, z)
    if not island then return false end
    return self:FocusIsland(island)
end

function IslandWorld:FocusIsland(island)
    if not island then return false end
    self.focusedIslandId = island.id
    self:BeginOrbitFocus(island.x, island.focusY or ((island.groundY or 0.42) - 1),
        island.z, island.focusRadius or 34)
    self:Notify("已聚焦 · " .. tostring(island.name))
    self:RefreshState()
    return true
end

function IslandWorld:FocusArchipelago()
    local overview = self.layout:Overview()
    self.focusedIslandId = nil
    self:BeginOrbitFocus(overview.x, overview.y or ORBIT_TARGET_Y, overview.z, overview.radius)
    self:Notify("已返回《" .. tostring(self.layout.name or "空岛") .. "》全景")
    self:RefreshState()
    return true
end

function IslandWorld:BeginOrbitFocus(x, y, z, radius)
    self.deltaTheta, self.deltaPhi, self.radiusScale = 0, 0, 1
    self.cameraFocusAnimation = {
        elapsed = 0,
        duration = self.mobileEditor and 0.48 or 0.58,
        fromX = self.target.x,
        fromY = self.target.y,
        fromZ = self.target.z,
        fromRadius = self.radius,
        toX = tonumber(x) or self.target.x,
        toY = tonumber(y) or (self.layout:Overview().y or ORBIT_TARGET_Y),
        toZ = tonumber(z) or self.target.z,
        toRadius = Clamp(tonumber(radius) or self.radius,
            MIN_ORBIT_RADIUS, self.maxOrbitRadius),
    }
end

function IslandWorld:Update(timeStep)
    local clockDelta = Clamp(tonumber(timeStep) or 0, 0, 0.1)
    self.performanceElapsed = (tonumber(self.performanceElapsed) or 0) + clockDelta
    self.renderDetailCameraCooldown = math.max(0,
        (tonumber(self.renderDetailCameraCooldown) or 0) - clockDelta)
    local frameSample = Clamp(tonumber(timeStep) or (1 / 60), 1 / 240, 0.1)
    self.renderDetailFrameTime = (tonumber(self.renderDetailFrameTime) or frameSample) * 0.94
        + frameSample * 0.06
    local pressureBand
    pressureBand, self.renderDetailPressureState = MobileThermalPolicy.StableFramePressureBand(
        self.renderDetailPressureState, self.renderDetailFrameTime,
        self.thermalTargetFps, clockDelta)
    if pressureBand ~= self.renderDetailPressureBand then
        self.renderDetailPressureBand = pressureBand
        self:MarkRenderDetailDirty()
    end
    self:AdvanceEnvironmentBuilds()
    self.portalCooldown = math.max(0, (tonumber(self.portalCooldown) or 0) - clockDelta)
    local historyTransaction = self.activeHistoryTransaction
    if historyTransaction and historyTransaction.recoveryFailed
        and not self.pendingProjectLoad then
        historyTransaction.recoveryRetryElapsed =
            (tonumber(historyTransaction.recoveryRetryElapsed) or 0) + clockDelta
        local retryDelay = math.min(5,
            0.75 * math.max(1, tonumber(historyTransaction.recoveryRetryCount) or 1))
        if historyTransaction.recoveryRetryElapsed >= retryDelay then
            historyTransaction.recoveryRetryElapsed = 0
            self:BeginHistoryRollback(historyTransaction, "automatic-retry")
        end
    end
    self:AdvancePendingProjectLoad()
    self:ProcessBatchedInstanceRecoveries(clockDelta)
    self.renderDetailElapsed = (tonumber(self.renderDetailElapsed) or 0) + clockDelta
    self:RefreshMobileRenderDetail(false)
    if self.modelBatcher and self.modelBatcher.MaybeSweep then self.modelBatcher:MaybeSweep(false) end
    self.nightLightRefreshElapsed = self.nightLightRefreshElapsed + clockDelta
    local timeChanged = self.dayNight:Update(clockDelta)
    self.dayNightVisualElapsed = self.dayNightVisualElapsed + clockDelta
    local visualInterval = MobileThermalPolicy.DayNightVisualInterval(self.mobileDevice)
    if timeChanged and self.dayNightVisualElapsed >= visualInterval then
        self.dayNightVisualElapsed = 0
        self:ApplyDayNight(false)
    else
        self:RefreshNightLights(false)
    end
    self:AdvanceSunDirection(clockDelta)
    self.dayNightUiElapsed = self.dayNightUiElapsed + clockDelta
    if self.dayNightUiElapsed >= MobileThermalPolicy.DayNightUiInterval(self.mobileDevice) then
        self.dayNightUiElapsed = 0
        self:RefreshState()
    end
    if self.firstPerson then
        local deltaTime = Clamp(tonumber(timeStep) or 0, 0, 0.05)
        local forward, right = self.firstPersonForward, self.firstPersonRight
        local length = math.sqrt(forward * forward + right * right)
        if length > 1 then forward, right = forward / length, right / length end
        local cameraChanged = false
        if length > 0.001 then
            local speed
            if self.firstPersonFlying then
                speed = (self.firstPersonFast or self.firstPersonRun)
                    and FIRST_PERSON_FLIGHT_FAST_SPEED or FIRST_PERSON_FLIGHT_SPEED
            else
                speed = (self.firstPersonFast or self.firstPersonRun) and 7.2 or 4.2
            end
            local distance = speed * deltaTime
            local sine, cosine = math.sin(self.firstPersonYaw), math.cos(self.firstPersonYaw)
            local moveX = (forward * sine - right * cosine) * distance
            local moveZ = (forward * cosine + right * sine) * distance
            local nextX = self.firstPersonX + moveX
            if self.firstPersonFlying then
                if self:TryFirstPersonFlyMove(nextX, self.firstPersonZ, self.firstPersonFeetY) then cameraChanged = true end
            else
                if self:TryFirstPersonMove(nextX, self.firstPersonZ) then cameraChanged = true end
            end
            local nextZ = self.firstPersonZ + moveZ
            if self.firstPersonFlying then
                if self:TryFirstPersonFlyMove(self.firstPersonX, nextZ, self.firstPersonFeetY) then cameraChanged = true end
            else
                if self:TryFirstPersonMove(self.firstPersonX, nextZ) then cameraChanged = true end
            end
        end
        if self.firstPersonFlying then
            local vertical = self.firstPersonFlightVertical or 0
            if math.abs(vertical) > 0.001 then
                local flightSpeed = (self.firstPersonFast or self.firstPersonRun)
                    and FIRST_PERSON_FLIGHT_FAST_SPEED or FIRST_PERSON_FLIGHT_SPEED
                local nextFeetY = self.firstPersonFeetY + vertical * flightSpeed * deltaTime
                if self:TryFirstPersonFlyMove(self.firstPersonX, self.firstPersonZ, nextFeetY) then
                    cameraChanged = true
                end
            end
            self.firstPersonVerticalVelocity = 0
            self.firstPersonOnGround = false
        elseif self.firstPersonOnGround then
            self.firstPersonFeetY = self.firstPersonGroundY
        else
            self.firstPersonVerticalVelocity = self.firstPersonVerticalVelocity - FIRST_PERSON_GRAVITY * deltaTime
            local nextFeetY = self.firstPersonFeetY + self.firstPersonVerticalVelocity * deltaTime
            local surfaceY = self:FindFirstPersonSurface(self.firstPersonX, self.firstPersonZ, self.firstPersonGroundY)
            self.firstPersonGroundY = surfaceY
            if self.firstPersonVerticalVelocity <= 0 and nextFeetY <= surfaceY then
                self.firstPersonFeetY = surfaceY
                self.firstPersonVerticalVelocity = 0
                self.firstPersonOnGround = true
            elseif not self:IsFirstPersonBlocked(self.firstPersonX, self.firstPersonZ, nextFeetY) then
                self.firstPersonFeetY = nextFeetY
            elseif self.firstPersonVerticalVelocity > 0 then
                self.firstPersonVerticalVelocity = 0
            else
                self.firstPersonFeetY = surfaceY
                self.firstPersonVerticalVelocity = 0
                self.firstPersonOnGround = true
            end
            cameraChanged = true
        end
        self.firstPersonVisualGroundY = self.firstPersonFeetY
        if cameraChanged then self:ApplyFirstPersonCamera() end
        self:CheckFirstPersonPortal()
        return
    end
    local changed = false
    local focus = self.cameraFocusAnimation
    if focus then
        focus.elapsed = math.min(focus.duration, focus.elapsed + clockDelta)
        local progress = SmoothStep(focus.elapsed / math.max(0.001, focus.duration))
        self.target:set(
            focus.fromX + (focus.toX - focus.fromX) * progress,
            focus.fromY + (focus.toY - focus.fromY) * progress,
            focus.fromZ + (focus.toZ - focus.fromZ) * progress
        )
        self.radius = focus.fromRadius + (focus.toRadius - focus.fromRadius) * progress
        if focus.elapsed >= focus.duration then self.cameraFocusAnimation = nil end
        changed = true
    end
    if clockDelta > 0
        and (math.abs(self.deltaTheta) > 0.00001 or math.abs(self.deltaPhi) > 0.00001) then
        local applied, retained = CameraMotionStability.DampedStep(0.9, 0.9, clockDelta)
        self.theta = NormalizeAngle(self.theta + self.deltaTheta * applied)
        self.phi = Clamp(self.phi + self.deltaPhi * applied, 12 * DEG, 84 * DEG)
        self.deltaTheta, self.deltaPhi = self.deltaTheta * retained, self.deltaPhi * retained
        if math.abs(self.deltaTheta) <= 0.00001 then self.deltaTheta = 0 end
        if math.abs(self.deltaPhi) <= 0.00001 then self.deltaPhi = 0 end
        changed = true
    end
    if clockDelta > 0 and math.abs(self.radiusScale - 1) > 0.0001 then
        local applied, retained = CameraMotionStability.DampedStep(0.84, 0.75, clockDelta)
        self.radius = Clamp(self.radius * (1 + (self.radiusScale - 1) * applied),
            MIN_ORBIT_RADIUS, self.maxOrbitRadius)
        self.radiusScale = 1 + (self.radiusScale - 1) * retained
        if math.abs(self.radiusScale - 1) <= 0.0001 then self.radiusScale = 1 end
        changed = true
    end
    if changed then self:ApplyCamera() end
    if self.interactiveStateDirty then
        self.interactiveStateElapsed = self.interactiveStateElapsed + (tonumber(timeStep) or 0)
        if self.interactiveStateElapsed >= 0.1 then
            self.interactiveStateElapsed = 0
            self:RefreshState()
        end
    end
end

-- Collected only on demand (for diagnostics and future performance HUDs), so
-- observability itself never adds work to the render loop.
function IslandWorld:GetPerformanceStats()
    local luaMemoryKB = 0
    pcall(function() luaMemoryKB = tonumber(collectgarbage("count")) or 0 end)
    local batcher = self.modelBatcher and self.modelBatcher.GetStats
        and self.modelBatcher:GetStats() or {}
    local detail = {}
    for key, value in pairs(self.renderDetailStats or {}) do detail[key] = value end
    local environment = self.environmentBuildQueue and self.environmentBuildQueue:Progress()
        or { completed = 0, total = 0, pending = 0, errors = 0 }
    return {
        authoredInstances = #(self.instances or {}),
        authoredBlocks = tonumber(self.modelRenderBlockCount) or 0,
        visibleRenderParts = tonumber(self.modelRenderBatchCount) or 0,
        shadowBlocks = tonumber(self.modelShadowBlockCount) or 0,
        frameTimeMs = (tonumber(self.renderDetailFrameTime) or 0) * 1000,
        pressureBand = tonumber(self.renderDetailPressureBand) or 0,
        detailBudget = tonumber(self.renderDetailBudget) or 0,
        luaMemoryKB = luaMemoryKB,
        batching = batcher,
        mobileDetail = detail,
        environmentBuild = environment,
    }
end

function IslandWorld:GetState()
    local selected = self:GetSelected()
    local selectedAsset = selected and self.assetStore:Get(selected.assetId, selected.versionId) or nil
    return {
        appMode = "island",
        visitMode = self.readOnly == true,
        visitOwner = self.visitOwner,
        visitOwnerId = self.visitOwnerId,
        visitAvatar = self.visitAvatar,
        visitIslandId = self.visitIslandId,
        visitName = self.visitName,
        name = self.projectName or "我的空岛",
        terrainId = self.terrainId,
        terrainName = self.terrainDisplayName or self.layout.name,
        terrainPresets = self.terrainSummaries or IslandLayout.List(),
        randomTerrains = self.randomTerrainSummaries,
        count = self.activeHistoryTransaction
            and #(self.activeHistoryTransaction.currentSources or {})
            or (#self.instances + (self.pendingProjectLoad
                and math.max(0, self.pendingProjectLoad.total - self.pendingProjectLoad.index + 1) or 0)),
        mode = self.mode,
        firstPerson = self.firstPerson,
        firstPersonRun = self.firstPersonRun,
        firstPersonOnGround = self.firstPersonOnGround,
        firstPersonFlying = self.firstPersonFlying,
        timeOfDay = self.dayNight:GetTime(),
        timeLabel = self.dayNight:GetTimeLabel(),
        timePhase = self.dayNight:GetPhase(),
        timePhaseLabel = self.dayNight:GetPhaseLabel(),
        timeAuto = self.dayNight:IsAuto(),
        focusedIslandId = self.focusedIslandId,
        firstPersonJoystickActive = self.firstPersonJoystickActive,
        firstPersonJoystickX = self.firstPersonJoystickX / math.max(0.01, self.uiScale or 1),
        firstPersonJoystickY = self.firstPersonJoystickY / math.max(0.01, self.uiScale or 1),
        islands = self.islandSummaries,
        activeIslandId = self.activeIslandId,
        islandMarketSyncBusy = self.islandMarketSyncBusy == true,
        islandMarketSyncIslandId = self.islandMarketSyncIslandId,
        transformMode = self.transformMode,
        placementAssetId = self.placementAssetId,
        placementValid = self.placementValid,
        placementRotation = self.placementRotation / DEG,
        placementScale = self.placementScale,
        selected = selected and {
            id = selected.id,
            assetId = selected.assetId,
            versionId = selected.versionId,
            name = selectedAsset and selectedAsset.name or "模型",
            source = selectedAsset and selectedAsset.source or "unknown",
            canCustomize = not (selectedAsset and selectedAsset.source == "market"
                and selectedAsset.license == "use_only" and selectedAsset.isOwnPublication ~= true),
            x = selected.x, y = selected.y or 0, z = selected.z,
            rotationY = (selected.rotationY or 0) / DEG,
            scale = selected.scale,
            isPortal = selected.assetId == PortalTemplate.ASSET_ID,
            portalBound = selected.assetId == PortalTemplate.ASSET_ID
                and type(selected.portal) == "table" and selected.portal.targetIslandId ~= nil,
            portalTargetIslandId = type(selected.portal) == "table"
                and tostring(selected.portal.targetIslandId or "") or nil,
            portalTargetName = type(selected.portal) == "table" and (function()
                local targetId = tostring(selected.portal.targetIslandId or "")
                for _, summary in ipairs(self.islandSummaries or {}) do
                    if tostring(summary.id or summary.islandId) == targetId then
                        return tostring(summary.name or "另一座空岛")
                    end
                end
                return "另一座空岛"
            end)() or nil,
        } or nil,
        libraryTab = self.libraryTab,
        assets = self.librarySummaries,
        autoBuildAssets = self.autoBuildSummaries,
        canUndo = self.pendingProjectLoad == nil and self.activeHistoryTransaction == nil
            and not self:IsEnvironmentLoading() and #self.history > 0,
        canRedo = self.pendingProjectLoad == nil and self.activeHistoryTransaction == nil
            and not self:IsEnvironmentLoading() and #self.future > 0,
    }
end

function IslandWorld:Dispose()
    if self.disposed then return end
    self.disposed = true
    -- Stop every producer before dismantling native nodes. In particular an
    -- incremental restore must not retain its source tail after a portal swaps
    -- worlds, and UI/storage callbacks must not observe half-disposed state.
    self:CancelHistoryTransaction("dispose")
    self.pendingProjectLoad = nil
    self.pendingPortalActivation = nil
    self.portalTransitionActive = false
    self.portalContactId = nil
    self.onChanged, self.onCommit, self.onPortalDelete = nil, nil, nil
    self.drag, self.cameraFocusAnimation = nil, nil
    if self.environmentBuildQueue then self.environmentBuildQueue:Cancel() end
    self.environmentBuildQueue = nil
    self:ClearGhost()
    self:ClearSelectionHelper()
    self:ClearInstances()
    if self.modelBatcher then self.modelBatcher:Dispose(); self.modelBatcher = nil end
    if self.transformGizmo then self.transformGizmo:Dispose(); self.transformGizmo = nil end
    if self.renderer and self.renderer.dispose then self.renderer:dispose() end
    self.renderer, self.viewport = nil, nil
    if self.hemisphere and self.hemisphere.dispose then self.hemisphere:dispose() end
    if self.sun and self.sun.dispose then self.sun:dispose() end
    if self.fill and self.fill.dispose then self.fill:dispose() end
    if self.nightWindowMaterial and self.nightWindowMaterial.dispose then self.nightWindowMaterial:dispose() end
    if self.nightLampMaterial and self.nightLampMaterial.dispose then self.nightLampMaterial:dispose() end
    for _, material in ipairs(self.celestialMaterials or {}) do
        if material and material.dispose then material:dispose() end
    end
    for _, material in ipairs(self.islandSceneryMaterials or {}) do
        if material and material.dispose then material:dispose() end
    end
    for _, material in ipairs(self.islandGrassMaterials or {}) do
        if material and material.dispose then material:dispose() end
    end
    for _, texture in ipairs(self.islandGrassTextures or {}) do
        if texture and texture.dispose then texture:dispose() end
    end
    for _, geometry in ipairs(self.islandFoundationGeometries or {}) do
        if geometry and geometry.dispose then geometry:dispose() end
    end
    for _, geometry in pairs(self.transparentGeometry or {}) do
        if geometry and geometry.dispose then geometry:dispose() end
    end
    self.transparentGeometry = {}
    for _, model in pairs(self.instancedGeometryModels or {}) do
        if model and model.Dispose then pcall(model.Dispose, model) end
    end
    self.instancedGeometryModels = {}
    for _, geometry in pairs(self.mobileDetailGeometry or {}) do
        if geometry and geometry.dispose then geometry:dispose() end
    end
    self.mobileDetailGeometry = {}
    for _, geometry in pairs(self.geometry or {}) do
        if geometry and geometry.dispose then geometry:dispose() end
    end
    self.geometry = {}
    if self.materialSystem then self.materialSystem:Dispose() end
    self.materialSystem = nil

    -- THREE.BufferGeometry keeps a reference to its native CustomGeometry.
    -- Removing the native Scene tree releases all those components immediately
    -- instead of waiting for Lua GC after every portal round trip.
    local sceneNode = self.scene and self.scene.getNode and self.scene:getNode() or nil
    if sceneNode then
        if sceneNode.RemoveAllChildren then sceneNode:RemoveAllChildren() end
        if sceneNode.RemoveAllComponents then sceneNode:RemoveAllComponents() end
        if sceneNode.Remove then sceneNode:Remove() end
    end
    self.scene = nil
    self.environmentRoot, self.skyRoot, self.instanceRoot, self.modelBatchRoot = nil, nil, nil, nil
    self.ghostRoot, self.helperRoot = nil, nil
    self.camera, self.hemisphere, self.sun, self.fill = nil, nil, nil, nil
    self.storybookIslandData = nil
    self.activeNightLights = {}
    self.instances, self.byId, self.rendered = {}, {}, {}
end

return IslandWorld
