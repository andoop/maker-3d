---@diagnostic disable: undefined-global

-- Maker-native interaction/rendering core for Three.js-style TransformControls.
-- Picker geometry and behavior are ported from Three.js r180:
-- https://github.com/mrdoob/three.js/blob/r180/examples/jsm/controls/TransformControls.js
-- Three.js is MIT licensed. This module contains an independent Lua port of
-- the small picker/overlay subset needed by Maker's UrhoX runtime.

local THREE = require("urhox-libs/3D")

local Module = {}
local PickerMethods = {}
local OverlayMethods = {}

local SCENE_LAYER = 0
local OVERLAY_LAYER = 1
local PICKER_LAYER = 2
local SCENE_MASK = 1
local OVERLAY_MASK = 2
local PICKER_MASK = 4

local function SetDeepEnabled(object, enabled)
    if not object then return end
    local node = object.getNode and object:getNode() or nil
    if node and node.SetDeepEnabled then
        node:SetDeepEnabled(enabled and true or false)
    elseif object.traverse then
        object:traverse(function(child) child.visible = enabled and true or false end)
    end
end

local function SetObjectLayer(object, layer, overlay)
    if not object then return end
    local function Apply(child)
        if child.layers and child.layers.set then child.layers:set(layer) end
        local component = rawget(child, "_component")
        if component then
            local mask = layer == SCENE_LAYER and SCENE_MASK
                or layer == OVERLAY_LAYER and OVERLAY_MASK
                or PICKER_MASK
            if component.SetViewMask then component:SetViewMask(mask) end
            if overlay and component.SetOccludee then component:SetOccludee(false) end
            if overlay and component.SetCastShadows then component:SetCastShadows(false) end
        end
    end
    if object.traverse then object:traverse(Apply) else Apply(object) end
end

local function SetPosition(object, value)
    if value then object.position:set(value[1], value[2], value[3]) end
end

local function SetRotation(object, value)
    if value then object.rotation:set(value[1], value[2], value[3]) end
end

local function AddPicker(self, mode, handle, geometry, position, rotation, parent)
    local mesh = THREE.Mesh(geometry, self.material)
    mesh.name = "MakerTransformPicker:" .. self.token .. ":" .. handle
    SetPosition(mesh, position)
    SetRotation(mesh, rotation)
    SetObjectLayer(mesh, PICKER_LAYER, false)
    local target = parent or self.modeGroups[mode]
    target:add(mesh)
    self.handles[mode][handle] = self.handles[mode][handle] or {}
    self.handles[mode][handle][#self.handles[mode][handle] + 1] = mesh
    self.components[#self.components + 1] = rawget(mesh, "_component")
    return mesh
end

local function AddAxisPickers(self, mode, axis)
    local geometry = THREE.CylinderGeometry(0.2, 0, 0.6, 4)
    if axis == "x" then
        AddPicker(self, mode, axis, geometry, { 0.3, 0, 0 }, { 0, 0, -math.pi / 2 })
        AddPicker(self, mode, axis, geometry, { -0.3, 0, 0 }, { 0, 0, math.pi / 2 })
    elseif axis == "y" then
        AddPicker(self, mode, axis, geometry, { 0, 0.3, 0 })
        AddPicker(self, mode, axis, geometry, { 0, -0.3, 0 }, { 0, 0, math.pi })
    else
        AddPicker(self, mode, axis, geometry, { 0, 0, 0.3 }, { math.pi / 2, 0, 0 })
        AddPicker(self, mode, axis, geometry, { 0, 0, -0.3 }, { -math.pi / 2, 0, 0 })
    end
end

local function AddPlanePickers(self, mode)
    AddPicker(self, mode, "xy", THREE.BoxGeometry(0.2, 0.2, 0.01), { 0.15, 0.15, 0 })
    AddPicker(self, mode, "yz", THREE.BoxGeometry(0.2, 0.2, 0.01), { 0, 0.15, 0.15 }, { 0, math.pi / 2, 0 })
    AddPicker(self, mode, "xz", THREE.BoxGeometry(0.2, 0.2, 0.01), { 0.15, 0, 0.15 }, { -math.pi / 2, 0, 0 })
end

local function CreatePickerGeometry(self)
    for _, mode in ipairs({ "translate", "scale", "rotate" }) do
        self.modeGroups[mode] = THREE.Group()
        self.root:add(self.modeGroups[mode])
        self.handles[mode] = {}
    end

    for _, mode in ipairs({ "translate", "scale" }) do
        for _, axis in ipairs({ "x", "y", "z" }) do AddAxisPickers(self, mode, axis) end
        AddPlanePickers(self, mode)
    end
    AddPicker(self, "translate", "xyz", THREE.OctahedronGeometry(0.2, 0))
    AddPicker(self, "scale", "xyz", THREE.BoxGeometry(0.2, 0.2, 0.2))

    AddPicker(self, "rotate", "free", THREE.SphereGeometry(0.25, 10, 8))
    AddPicker(self, "rotate", "x", THREE.TorusGeometry(0.5, 0.1, 4, 24), nil,
        { 0, -math.pi / 2, -math.pi / 2 })
    AddPicker(self, "rotate", "y", THREE.TorusGeometry(0.5, 0.1, 4, 24), nil,
        { math.pi / 2, 0, 0 })
    AddPicker(self, "rotate", "z", THREE.TorusGeometry(0.5, 0.1, 4, 24), nil,
        { 0, 0, -math.pi / 2 })

    self.screenGroup = THREE.Group()
    self.modeGroups.rotate:add(self.screenGroup)
    AddPicker(self, "rotate", "e", THREE.TorusGeometry(0.75, 0.1, 2, 24), nil, nil, self.screenGroup)
end

function Module.NewPicker(scene, camera, token)
    local self = setmetatable({}, { __index = PickerMethods })
    self.scene = assert(scene)
    self.camera = assert(camera)
    self.token = tostring(token or "default")
    self.octree = scene:getNode():GetComponent("Octree")
    self.root = THREE.Group()
    self.root.name = "MakerTransformPickerRoot"
    self.material = THREE.MeshBasicMaterial({
        color = 0xffffff,
        transparent = true,
        opacity = 0.01,
        side = THREE.DoubleSide,
    })
    self.modeGroups = {}
    self.handles = {}
    self.components = {}
    scene:add(self.root)
    CreatePickerGeometry(self)
    SetObjectLayer(self.root, PICKER_LAYER, false)
    SetDeepEnabled(self.root, false)
    return self
end

function PickerMethods:Update(block, mode, scale, handleVisible)
    local attached = block ~= nil
    SetDeepEnabled(self.root, attached)
    if not attached then return end

    self.root.position:set(block.x, block.y, block.z)
    self.root.scale:set(scale, scale, scale)
    if mode == "scale" then
        self.root.rotation:set(block.rx, block.ry, block.rz)
    else
        self.root.rotation:set(0, 0, 0)
    end
    for name, group in pairs(self.modeGroups) do SetDeepEnabled(group, name == mode) end
    for handle, objects in pairs(self.handles[mode] or {}) do
        local visible = not handleVisible or handleVisible(handle)
        for _, object in ipairs(objects) do SetDeepEnabled(object, visible) end
    end
    if mode == "rotate" and self.screenGroup then self.screenGroup:lookAt(self.camera.position) end

    for _, component in ipairs(self.components) do
        if component and component.MarkForUpdate then component:MarkForUpdate() end
        if component and self.octree and self.octree.QueueUpdate then self.octree:QueueUpdate(component) end
    end
end

function PickerMethods:HitTest(ray)
    if not ray or not self.octree then return nil end
    local results = self.octree:Raycast(
        ray,
        RAY_TRIANGLE,
        10000,
        DRAWABLE_GEOMETRY,
        PICKER_MASK
    ) or {}
    local fallback
    for _, result in ipairs(results) do
        if result and result.drawable and result.node then
            local name = tostring(result.node.name or "")
            -- The rendered endpoint mesh is the authoritative hit shape.
            -- Prefer it over the broad Three.js picker when both overlap.
            local exactToken, exact = name:match("^MakerTransformExactPicker:([^:]+):(.+)$")
            if exactToken == self.token and exact then return exact, true end
            local pickerToken, picker = name:match("^MakerTransformPicker:([^:]+):(.+)$")
            if pickerToken == self.token and picker then fallback = fallback or picker end
        end
    end
    return fallback, false
end

function PickerMethods:Dispose()
    if self.root then
        self.scene:remove(self.root)
        self.root:getNode():Remove()
        self.root = nil
    end
end

function Module.MarkSceneObject(object)
    SetObjectLayer(object, SCENE_LAYER, false)
end

function Module.MarkOverlayObject(object)
    SetObjectLayer(object, OVERLAY_LAYER, true)
end

function Module.MarkOverlayPickerObject(object, handle, token)
    if not object then return end
    SetObjectLayer(object, OVERLAY_LAYER, true)
    object.name = "MakerTransformExactPicker:" .. tostring(token or "default") .. ":" .. tostring(handle)
    local function Apply(child)
        local component = rawget(child, "_component")
        if component and component.SetViewMask then
            -- Render through the overlay camera mask and raycast through the
            -- picker mask using this same visible geometry.
            component:SetViewMask(OVERLAY_MASK | PICKER_MASK)
        end
    end
    if object.traverse then object:traverse(Apply) else Apply(object) end
end

function Module.NewOverlayRenderer(scene, camera, sourceViewport)
    local self = setmetatable({}, { __index = OverlayMethods })
    self.scene = assert(scene)
    self.camera = assert(camera)
    self.sourceViewport = assert(sourceViewport)

    -- Maker's web runtime does not reliably composite a second backbuffer
    -- viewport. Render visible helpers in the main viewport's alpha pass and
    -- keep only the invisible picker mask out of that camera. Overlay
    -- materials enforce CMP_ALWAYS, no depth writes and render order 255, so
    -- solid scene geometry cannot cover them.
    local nativeCamera = camera:getCamera()
    self.previousViewMask = nativeCamera:GetViewMask()
    nativeCamera:SetViewMask(SCENE_MASK | OVERLAY_MASK)
    return self
end

function OverlayMethods:Sync()
    -- Visible helpers share the main camera, so no camera transform copy is
    -- required. Kept as part of the reusable renderer interface.
end

function OverlayMethods:SetRect(rect)
    -- Visible helpers share the main viewport and inherit its rectangle.
end

function OverlayMethods:Dispose()
    local nativeCamera = self.camera and self.camera:getCamera() or nil
    if nativeCamera and self.previousViewMask then nativeCamera:SetViewMask(self.previousViewMask) end
end

Module.SCENE_MASK = SCENE_MASK
Module.OVERLAY_MASK = OVERLAY_MASK
Module.PICKER_MASK = PICKER_MASK

return Module
