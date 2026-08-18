---@diagnostic disable: undefined-global

local THREE = require("urhox-libs/3D")
local MakerTransformControls = require("MakerTransformControls")

local IslandTransformGizmo = {}
IslandTransformGizmo.__index = IslandTransformGizmo

local DEG = math.pi / 180

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function SetDeepEnabled(object, enabled)
    if not object then return end
    local node = object.getNode and object:getNode() or nil
    if node and node.SetDeepEnabled then node:SetDeepEnabled(enabled == true)
    elseif object.traverse then object:traverse(function(child) child.visible = enabled == true end)
    else object.visible = enabled == true end
end

local function PrepareOverlayMaterial(material)
    local native = material and material.getNative and material:getNative() or nil
    local technique = cache:GetResource("Technique", "Techniques/TransformOverlay.xml")
    if native and technique then
        native:SetTechnique(0, technique)
        rawset(material, "_islandOverlayTechnique", technique)
    end
    if native and native.SetRenderOrder then native:SetRenderOrder(255) end
    return material
end

local function ReinforceOverlayMaterial(material)
    local native = material and material.getNative and material:getNative() or nil
    local technique = material and rawget(material, "_islandOverlayTechnique")
        or cache:GetResource("Technique", "Techniques/TransformOverlay.xml")
    if native and technique then native:SetTechnique(0, technique) end
    if native and native.SetRenderOrder then native:SetRenderOrder(255) end
end

local function CollectPickerComponents(root)
    local result = {}
    if root and root.traverse then
        root:traverse(function(child)
            if tostring(child.name or ""):match("^MakerTransformExactPicker:island:") then
                local component = rawget(child, "_component")
                if component then result[#result + 1] = component end
            end
        end)
    end
    return result
end

local function QueueComponents(octree, components)
    for _, component in ipairs(components or {}) do
        if component.MarkForUpdate then component:MarkForUpdate() end
        if octree and octree.QueueUpdate then octree:QueueUpdate(component) end
    end
end

local function AllowedHandle(mode, handle)
    if mode == "translate" then
        return handle == "x" or handle == "y" or handle == "z" or handle == "xz" or handle == "xyz"
    end
    if mode == "rotate" then return handle == "y" end
    return handle == "xyz"
end

function IslandTransformGizmo.new(scene, camera, viewport)
    local self = setmetatable({}, IslandTransformGizmo)
    self.scene, self.camera, self.viewport = scene, camera, viewport
    self.octree = scene:getNode():GetComponent("Octree")
    self.root = THREE.Group()
    self.root.visible = false
    self.groups = {}
    self.materials, self.materialBases = {}, {}
    self.handleMaterials = { translate = {}, rotate = {}, scale = {} }
    scene:add(self.root)

    local function Material(color, opacity)
        local material = PrepareOverlayMaterial(THREE.MeshBasicMaterial({
            color = color, transparent = true, opacity = opacity or 1,
        }))
        self.materials[#self.materials + 1] = material
        self.materialBases[material] = { color = color, opacity = opacity or 1 }
        return material
    end

    local axisMaterials = {
        x = Material(0xff3b30),
        y = Material(0x35c96f),
        z = Material(0x2388ff),
    }

    local function TrackHandle(mode, handle, material)
        local list = self.handleMaterials[mode][handle] or {}
        list[#list + 1] = material
        self.handleMaterials[mode][handle] = list
    end

    local function AddMesh(parent, geometry, material, x, y, z, sx, sy, sz, rx, ry, rz, handle)
        local mesh = THREE.Mesh(geometry, material)
        mesh.position:set(x or 0, y or 0, z or 0)
        mesh.scale:set(sx or 1, sy or 1, sz or 1)
        mesh.rotation:set(rx or 0, ry or 0, rz or 0)
        mesh.castShadow = false
        mesh.renderOrder = 255
        if handle then MakerTransformControls.MarkOverlayPickerObject(mesh, handle, "island")
        else MakerTransformControls.MarkOverlayObject(mesh) end
        parent:add(mesh)
        return mesh
    end

    local function AddAxis(parent, mode, axis, endpointKind, handle)
        local material = axisMaterials[axis]
        local rotation = axis == "x" and { 0, 0, -math.pi / 2 }
            or axis == "z" and { math.pi / 2, 0, 0 } or { 0, 0, 0 }
        AddMesh(parent, THREE.CylinderGeometry(1, 1, 1, 5), material,
            0, 0, 0, 0.014, 1.25, 0.014, rotation[1], rotation[2], rotation[3], handle)
        local positions = axis == "x" and { { 0.72, 0, 0, -math.pi / 2 }, { -0.72, 0, 0, math.pi / 2 } }
            or axis == "y" and { { 0, 0.72, 0, 0 }, { 0, -0.72, 0, math.pi } }
            or { { 0, 0, 0.72, math.pi / 2 }, { 0, 0, -0.72, -math.pi / 2 } }
        for _, position in ipairs(positions) do
            if endpointKind == "arrow" then
                AddMesh(parent, THREE.ConeGeometry(1, 1, 12), material,
                    position[1], position[2], position[3], 0.065, 0.16, 0.065,
                    axis == "x" and 0 or position[4], 0, axis == "x" and position[4] or 0, handle)
            else
                AddMesh(parent, THREE.BoxGeometry(0.13, 0.13, 0.13), material,
                    position[1], position[2], position[3], 1, 1, 1, 0, 0, 0, handle)
            end
        end
        TrackHandle(mode, handle, material)
    end

    local translate = THREE.Group()
    AddAxis(translate, "translate", "x", "arrow", "x")
    AddAxis(translate, "translate", "y", "arrow", "y")
    AddAxis(translate, "translate", "z", "arrow", "z")
    local planeMaterial = Material(0x35c96f, 0.42)
    AddMesh(translate, THREE.BoxGeometry(0.23, 0.012, 0.23), planeMaterial,
        0.18, 0, 0.18, 1, 1, 1, 0, 0, 0, "xz")
    TrackHandle("translate", "xz", planeMaterial)
    local centerMaterial = Material(0xffffff, 0.8)
    AddMesh(translate, THREE.OctahedronGeometry(0.115, 0), centerMaterial, 0, 0, 0, 1, 1, 1, 0, 0, 0, "xyz")
    TrackHandle("translate", "xyz", centerMaterial)
    self.root:add(translate)
    self.groups.translate = translate

    local rotate = THREE.Group()
    local rotateMaterial = axisMaterials.y
    AddMesh(rotate, THREE.TorusGeometry(0.72, 0.035, 6, 64), rotateMaterial,
        0, 0, 0, 1, 1, 1, math.pi / 2, 0, 0, "y")
    TrackHandle("rotate", "y", rotateMaterial)
    self.root:add(rotate)
    self.groups.rotate = rotate

    local scale = THREE.Group()
    AddAxis(scale, "scale", "x", "box", "xyz")
    AddAxis(scale, "scale", "y", "box", "xyz")
    AddAxis(scale, "scale", "z", "box", "xyz")
    local scaleCenter = Material(0xffffff, 0.9)
    AddMesh(scale, THREE.BoxGeometry(0.15, 0.15, 0.15), scaleCenter,
        0, 0, 0, 1, 1, 1, 0, 0, 0, "xyz")
    TrackHandle("scale", "xyz", scaleCenter)
    self.root:add(scale)
    self.groups.scale = scale

    self.exactPickerComponents = CollectPickerComponents(self.root)
    self.picker = MakerTransformControls.NewPicker(scene, camera, "island")
    self.overlay = MakerTransformControls.NewOverlayRenderer(scene, camera, viewport)
    return self
end

function IslandTransformGizmo:Refresh(center, mode, mobile)
    self.mode = mode or self.mode or "translate"
    self.center = center
    local visible = center ~= nil
    SetDeepEnabled(self.root, visible)
    if not visible then
        self.picker:Update(nil, self.mode, 1)
        self:SetHighlight(nil)
        return
    end
    local dx, dy, dz = self.camera.position.x - center.x,
        self.camera.position.y - center.y, self.camera.position.z - center.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local size = mobile and 1.55 or 0.86
    local perspective = math.min(1.9 * math.tan((self.camera.fov or 40) * DEG * 0.5), 7)
    self.scale = math.max(0.001, distance * perspective * size / 4)
    self.root.position:set(center.x, center.y, center.z)
    self.root.rotation:set(0, 0, 0)
    self.root.scale:set(self.scale, self.scale, self.scale)
    for name, group in pairs(self.groups) do SetDeepEnabled(group, name == self.mode) end
    local proxy = { x = center.x, y = center.y, z = center.z, rx = 0, ry = 0, rz = 0 }
    self.picker:Update(proxy, self.mode, self.scale, function(handle) return AllowedHandle(self.mode, handle) end)
    QueueComponents(self.octree, self.exactPickerComponents)
    for _, material in ipairs(self.materials) do ReinforceOverlayMaterial(material) end
    if self.overlay then self.overlay:Sync() end
end

function IslandTransformGizmo:Hit(ray)
    if not self.center or not ray then return nil end
    local handle, exact = self.picker:HitTest(ray)
    return exact and AllowedHandle(self.mode, handle) and handle or nil
end

function IslandTransformGizmo.TouchHitPadding(uiScale)
    local scale = math.max(1, tonumber(uiScale) or 1)
    local normal = Clamp(10 * scale, 14, 28)
    local vertical = Clamp(14 * scale, 20, 36)
    return normal, math.max(normal, vertical)
end

function IslandTransformGizmo:HitScreen(x, y, isTouch, getRay, uiScale, viewportRect)
    if not self.center or type(getRay) ~= "function" then return nil end
    local direct = self:Hit(getRay(x, y))
    if direct or not isTouch then return direct end

    local normalPadding, verticalPadding = IslandTransformGizmo.TouchHitPadding(uiScale)
    local sampleCount = 36
    local goldenAngle = math.pi * (3 - math.sqrt(5))
    local rect = viewportRect or {}
    local left, top = tonumber(rect.left) or -math.huge, tonumber(rect.top) or -math.huge
    local right, bottom = tonumber(rect.right) or math.huge, tonumber(rect.bottom) or math.huge
    for sample = 1, sampleCount do
        local radius = verticalPadding * math.sqrt(sample / sampleCount)
        local angle = sample * goldenAngle
        local sampleX = x + math.cos(angle) * radius
        local sampleY = y + math.sin(angle) * radius
        if sampleX >= left and sampleX < right and sampleY >= top and sampleY < bottom then
            local handle = self:Hit(getRay(sampleX, sampleY))
            if handle and (radius <= normalPadding
                    or (self.mode == "translate" and handle == "y")) then
                return handle
            end
        end
    end
    return nil
end

function IslandTransformGizmo:SetHighlight(handle)
    if self.highlighted == handle then return end
    self.highlighted = handle
    for material, base in pairs(self.materialBases) do
        if material.color and material.color.setHex then material.color:setHex(base.color) end
        material.opacity = base.opacity
    end
    for _, material in ipairs(self.handleMaterials[self.mode or "translate"][handle] or {}) do
        if material.color and material.color.setHex then material.color:setHex(0xffd83d) end
        material.opacity = 1
    end
end

function IslandTransformGizmo:ProjectCenter(viewportRect)
    if not self.center or not viewportRect then return nil end
    local point = THREE.Vector3(self.center.x, self.center.y, self.center.z):project(self.camera)
    return viewportRect.left + (point.x + 1) * 0.5 * (viewportRect.right - viewportRect.left),
        viewportRect.top + (1 - point.y) * 0.5 * (viewportRect.bottom - viewportRect.top)
end

function IslandTransformGizmo:Dispose()
    if self.picker then self.picker:Dispose(); self.picker = nil end
    if self.overlay then self.overlay:Dispose(); self.overlay = nil end
    if self.root then
        self.scene:remove(self.root)
        self.root:getNode():Remove()
        self.root = nil
    end
    for _, material in ipairs(self.materials or {}) do if material.dispose then material:dispose() end end
    self.materials, self.materialBases = {}, {}
end

IslandTransformGizmo.PrepareOverlayMaterial = PrepareOverlayMaterial

return IslandTransformGizmo
