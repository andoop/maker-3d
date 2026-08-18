---@diagnostic disable: undefined-global

local THREE = require("urhox-libs/3D")
local Catalog = require("BlockCatalog")
local MakerTransformControls = require("MakerTransformControls")

local Module = {}
local Methods = {}

local DEG
local Clamp
local CopyBlock
local RotateForward
local RotateInverse

-- Transform pointer events can arrive substantially faster than rendered
-- frames. Publishing a normal RefreshState here used to rebuild every derived
-- workbench list/signature for each sample, even though only the selected
-- block's transform changed. Reuse one tiny delta table and let BuilderUI
-- consume the latest live block once per UI frame (30 Hz on phones).
local function PublishTransformRefresh(self, block)
    if type(self.onChanged) ~= "function" or not block then return false end
    local state = self.transformRefreshState
    if not state then
        state = { _builderRefreshKind = "transform" }
        self.transformRefreshState = state
    end
    state.selected = block
    self.onChanged(state, nil)
    return true
end

local function TransformValuesChanged(a, b)
    for _, key in ipairs({ "x", "y", "z", "sx", "sy", "sz", "rx", "ry", "rz" }) do
        if math.abs((a[key] or 0) - (b[key] or 0)) > 0.000001 then return true end
    end
    return false
end

local function ContinuousScale(value)
    return math.max(0.05, value)
end

local function VectorLength(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

local function NormalizeVector(x, y, z)
    local length = VectorLength(x, y, z)
    if length < 0.000001 then return 0, 0, 0 end
    return x / length, y / length, z / length
end

local function DotVector(ax, ay, az, bx, by, bz)
    return ax * bx + ay * by + az * bz
end

local function CrossVector(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function ScreenCross(origin, a, b)
    return (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
end

local function PointSegmentDistanceSquared(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared < 0.0001 then
        local offsetX, offsetY = px - ax, py - ay
        return offsetX * offsetX + offsetY * offsetY
    end
    local amount = Clamp(((px - ax) * dx + (py - ay) * dy) / lengthSquared, 0, 1)
    local closestX, closestY = ax + dx * amount, ay + dy * amount
    local offsetX, offsetY = px - closestX, py - closestY
    return offsetX * offsetX + offsetY * offsetY
end

local function ConvexHull(points)
    if #points < 3 then return points end
    table.sort(points, function(a, b)
        if a.x == b.x then return a.y < b.y end
        return a.x < b.x
    end)
    local unique = {}
    for _, point in ipairs(points) do
        local previous = unique[#unique]
        if not previous or point.x ~= previous.x or point.y ~= previous.y then
            unique[#unique + 1] = point
        end
    end
    if #unique < 3 then return unique end

    local hull = {}
    for _, point in ipairs(unique) do
        while #hull >= 2 and ScreenCross(hull[#hull - 1], hull[#hull], point) <= 0 do
            hull[#hull] = nil
        end
        hull[#hull + 1] = point
    end
    local lowerSize = #hull
    for index = #unique - 1, 1, -1 do
        local point = unique[index]
        while #hull > lowerSize and ScreenCross(hull[#hull - 1], hull[#hull], point) <= 0 do
            hull[#hull] = nil
        end
        hull[#hull + 1] = point
    end
    hull[#hull] = nil
    return hull
end

local function PointInConvexPolygon(x, y, polygon, rasterPadding)
    if #polygon < 3 then return false end
    local point = { x = x, y = y }
    local direction
    for index = 1, #polygon do
        local start = polygon[index]
        local finish = polygon[index % #polygon + 1]
        local edge = ScreenCross(start, finish, point)
        local edgeLength = math.sqrt((finish.x - start.x) ^ 2 + (finish.y - start.y) ^ 2)
        local tolerance = (rasterPadding or 0) * edgeLength
        if math.abs(edge) > math.max(0.0001, tolerance) then
            local current = edge > 0
            if direction ~= nil and current ~= direction then return false end
            direction = current
        end
    end
    return true
end

local function AxisLocalPoint(axis, along, firstRadius, secondRadius)
    if axis == "x" then return { along, firstRadius, secondRadius } end
    if axis == "y" then return { firstRadius, along, secondRadius } end
    return { firstRadius, secondRadius, along }
end

local function SignedInPlaneAngle(startX, startY, startZ, endX, endY, endZ, eyeX, eyeY, eyeZ)
    startX, startY, startZ = NormalizeVector(startX, startY, startZ)
    endX, endY, endZ = NormalizeVector(endX, endY, endZ)
    local angle = math.acos(Clamp(DotVector(startX, startY, startZ, endX, endY, endZ), -1, 1))
    local crossX, crossY, crossZ = CrossVector(endX, endY, endZ, startX, startY, startZ)
    return angle * (DotVector(crossX, crossY, crossZ, eyeX, eyeY, eyeZ) < 0 and 1 or -1)
end

local function NormalizeAngle(angle)
    while angle > math.pi do angle = angle - math.pi * 2 end
    while angle < -math.pi do angle = angle + math.pi * 2 end
    return angle
end

local function HandleAxis(handle)
    if not handle then return nil end
    local first = handle:sub(1, 1)
    if first == "x" or first == "y" or first == "z" then return first end
    return nil
end

local function HandleAxes(handle)
    if handle == "xyz" then return { "x", "y", "z" } end
    if handle == "xy" then return { "x", "y" } end
    if handle == "yz" then return { "y", "z" } end
    if handle == "xz" then return { "x", "z" } end
    local axis = HandleAxis(handle)
    return axis and { axis } or {}
end

local function AxisVector(axis)
    if axis == "x" then return 1, 0, 0 end
    if axis == "y" then return 0, 1, 0 end
    return 0, 0, 1
end

local function AxisForBlock(axis, block, localSpace)
    local x, y, z = AxisVector(axis)
    if localSpace and block then return RotateForward(x, y, z, block.rx, block.ry, block.rz) end
    return x, y, z
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

local function ConfigureOverlayMaterial(material, techniqueStore)
    local native = material and material.getNative and material:getNative() or nil
    local technique = cache:GetResource("Technique", "Techniques/TransformOverlay.xml")
    if native and technique then
        native:SetTechnique(0, technique)
        rawset(material, "_workbenchOverlayTechnique", technique)
        if techniqueStore then techniqueStore[#techniqueStore + 1] = technique end
    end
    if native and native.SetRenderOrder then native:SetRenderOrder(255) end
    return material
end

local function ReinforceOverlayMaterial(material)
    local native = material and material.getNative and material:getNative() or nil
    local technique = material and rawget(material, "_workbenchOverlayTechnique")
        or cache:GetResource("Technique", "Techniques/TransformOverlay.xml")
    if native and technique then native:SetTechnique(0, technique) end
    if native and native.SetRenderOrder then native:SetRenderOrder(255) end
end

local function SetObjectTreeEnabled(object, enabled)
    if not object then return end
    local value = enabled and true or false
    local node = object.getNode and object:getNode() or nil
    -- UrhoX Node.enabled only affects components on that exact node. Gizmo
    -- handles are nested two or three levels deep, so `.visible = false`
    -- leaves descendant meshes rendered and creates controls that are visible
    -- but cannot be picked in the active transform mode.
    if node and node.SetDeepEnabled then
        local current = node.enabledSelf
        if current == nil then current = node.enabled end
        if current ~= value then node:SetDeepEnabled(value) end
    elseif object.traverse then
        object:traverse(function(child) child.visible = value end)
    else
        object.visible = value
    end
end

local function CollectExactPickerComponents(root)
    local components = {}
    if not root or not root.traverse then return components end
    root:traverse(function(child)
        local name = tostring(child.name or "")
        if name:match("^MakerTransformExactPicker:") then
            local component = rawget(child, "_component")
            if component then components[#components + 1] = component end
        end
    end)
    return components
end

local function QueueExactPickerComponents(octree, components)
    for _, component in ipairs(components or {}) do
        if component.MarkForUpdate then component:MarkForUpdate() end
        if octree and octree.QueueUpdate then octree:QueueUpdate(component) end
    end
end

function Methods:CreateSelectionHelper()
    self.overlayTechniques = self.overlayTechniques or {}
    local haloMaterial = ConfigureOverlayMaterial(THREE.LineBasicMaterial({
        color = 0x173f4e,
        transparent = true,
        opacity = 0.9,
    }), self.overlayTechniques)
    local material = ConfigureOverlayMaterial(THREE.LineBasicMaterial({
        color = 0xffbd3f,
        transparent = true,
        opacity = 1,
    }), self.overlayTechniques)
    self.selectionHalo = THREE.LineSegments(THREE.EdgesGeometry(THREE.BoxGeometry(1, 1, 1), 1), haloMaterial)
    self.selectionHalo.visible = false
    self.selectionHalo.renderOrder = 126
    MakerTransformControls.MarkOverlayObject(self.selectionHalo)
    self.scene:add(self.selectionHalo)
    self.selectionHelper = THREE.LineSegments(THREE.EdgesGeometry(THREE.BoxGeometry(1, 1, 1), 1), material)
    self.selectionHelper.visible = false
    self.selectionHelper.renderOrder = 127
    MakerTransformControls.MarkOverlayObject(self.selectionHelper)
    self.scene:add(self.selectionHelper)
end

function Methods:CreateDragHelpers()
    self.overlayTechniques = self.overlayTechniques or {}
    local function LineMaterial(color, opacity)
        return ConfigureOverlayMaterial(THREE.LineBasicMaterial({
            color = color,
            transparent = true,
            opacity = opacity,
        }), self.overlayTechniques)
    end
    local function EmptyLine(material)
        local zero = THREE.Vector3(0, 0, 0)
        local line = THREE.LineSegments(THREE.BufferGeometry():setFromPoints({ zero, zero }), material)
        line.visible = false
        line.renderOrder = 127
        MakerTransformControls.MarkOverlayObject(line)
        self.scene:add(line)
        return line
    end
    local markerMaterial = ConfigureOverlayMaterial(THREE.MeshBasicMaterial({
        color = 0xffffff,
        transparent = true,
        opacity = 0.5,
    }), self.overlayTechniques)
    local function EmptyMarker()
        local marker = THREE.Mesh(THREE.OctahedronGeometry(0.01, 2), markerMaterial)
        marker.visible = false
        marker.renderOrder = 127
        MakerTransformControls.MarkOverlayObject(marker)
        self.scene:add(marker)
        return marker
    end
    -- TransformControls shares one white helper material at 50% opacity for
    -- axis, start, end and delta helpers.
    self.dragAxisMaterial = LineMaterial(0xffffff, 0.5)
    self.dragAxisHelper = EmptyLine(self.dragAxisMaterial)
    self.dragDeltaHelper = EmptyLine(LineMaterial(0xffffff, 0.5))
    self.dragStartHelper = EmptyMarker()
    self.dragEndHelper = EmptyMarker()
    self.dragHelpers = {
        self.dragAxisHelper,
        self.dragDeltaHelper,
        self.dragStartHelper,
        self.dragEndHelper,
    }
    self.alignmentHelpers = {}
    for axis, color in pairs({ x = 0xff4266, y = 0x29d477, z = 0x3288ff }) do
        local helper = EmptyLine(LineMaterial(color, 0.95))
        self.alignmentHelpers[axis] = helper
        self.dragHelpers[#self.dragHelpers + 1] = helper
    end
end

function Methods:SetDragHelperPoints(helper, points)
    if not helper then return end
    if not points or #points < 2 then
        helper.visible = false
        return
    end
    helper.geometry = THREE.BufferGeometry():setFromPoints(points)
    helper.visible = true
end

function Methods:HideDragHelpers()
    for _, helper in ipairs(self.dragHelpers or {}) do helper.visible = false end
end

function Methods:RefreshAlignmentGuides(snaps, block)
    for axis, helper in pairs(self.alignmentHelpers or {}) do
        local snap = snaps and snaps[axis]
        if not snap or not block or not snap.target then
            helper.visible = false
        else
            local target = snap.target
            local movingHalf, targetHalf = WorldHalfExtents(block), WorldHalfExtents(target)
            local margin = math.max(0.12, self:GetGizmoScale(block) * 0.08)
            local minX = math.min(block.x - movingHalf.x, target.x - targetHalf.x) - margin
            local maxX = math.max(block.x + movingHalf.x, target.x + targetHalf.x) + margin
            local minY = math.min(block.y - movingHalf.y, target.y - targetHalf.y) - margin
            local maxY = math.max(block.y + movingHalf.y, target.y + targetHalf.y) + margin
            local minZ = math.min(block.z - movingHalf.z, target.z - targetHalf.z) - margin
            local maxZ = math.max(block.z + movingHalf.z, target.z + targetHalf.z) + margin
            local coordinate = snap.guideCoordinate
            local points
            if axis == "x" then
                points = {
                    THREE.Vector3(coordinate, minY, minZ), THREE.Vector3(coordinate, maxY, minZ),
                    THREE.Vector3(coordinate, maxY, minZ), THREE.Vector3(coordinate, maxY, maxZ),
                    THREE.Vector3(coordinate, maxY, maxZ), THREE.Vector3(coordinate, minY, maxZ),
                    THREE.Vector3(coordinate, minY, maxZ), THREE.Vector3(coordinate, minY, minZ),
                }
            elseif axis == "y" then
                points = {
                    THREE.Vector3(minX, coordinate, minZ), THREE.Vector3(maxX, coordinate, minZ),
                    THREE.Vector3(maxX, coordinate, minZ), THREE.Vector3(maxX, coordinate, maxZ),
                    THREE.Vector3(maxX, coordinate, maxZ), THREE.Vector3(minX, coordinate, maxZ),
                    THREE.Vector3(minX, coordinate, maxZ), THREE.Vector3(minX, coordinate, minZ),
                }
            else
                points = {
                    THREE.Vector3(minX, minY, coordinate), THREE.Vector3(maxX, minY, coordinate),
                    THREE.Vector3(maxX, minY, coordinate), THREE.Vector3(maxX, maxY, coordinate),
                    THREE.Vector3(maxX, maxY, coordinate), THREE.Vector3(minX, maxY, coordinate),
                    THREE.Vector3(minX, maxY, coordinate), THREE.Vector3(minX, minY, coordinate),
                }
            end
            self:SetDragHelperPoints(helper, points)
        end
    end
end

function Methods:RefreshHoverAxisHelper(handle)
    local block = self:GetSelected()
    if self.transformDrag or not block or not handle or not self.transformAttached then
        if not self.transformDrag then self:HideDragHelpers() end
        return
    end
    self.dragDeltaHelper.visible = false
    self.dragStartHelper.visible = false
    self.dragEndHelper.visible = false
    self:RefreshAlignmentGuides(nil, nil)
    if self.transformMode == "rotate" and (handle == "e" or handle == "free") then
        self.dragAxisHelper.visible = false
        return
    end

    local extent = 300
    local points = {}
    for _, axis in ipairs(HandleAxes(handle)) do
        local ax, ay, az = AxisForBlock(axis, block, self.transformMode == "scale")
        ax, ay, az = NormalizeVector(ax, ay, az)
        points[#points + 1] = THREE.Vector3(block.x - ax * extent, block.y - ay * extent, block.z - az * extent)
        points[#points + 1] = THREE.Vector3(block.x + ax * extent, block.y + ay * extent, block.z + az * extent)
    end
    self:SetDragHelperPoints(self.dragAxisHelper, points)
end

function Methods:RefreshDragHelpers()
    local drag = self.transformDrag
    local block = self:GetSelected()
    if not drag or not block then self:HideDragHelpers(); return end

    local start = drag.startBlock
    local startPoint = THREE.Vector3(start.x, start.y, start.z)
    local endPoint = THREE.Vector3(block.x, block.y, block.z)
    local helperScale = self:GetGizmoScale(start)
    local extent = 300
    local axisPoints = {}

    local function AddAxisLine(ax, ay, az)
        ax, ay, az = NormalizeVector(ax, ay, az)
        if VectorLength(ax, ay, az) < 0.0001 then return end
        axisPoints[#axisPoints + 1] = THREE.Vector3(start.x - ax * extent, start.y - ay * extent, start.z - az * extent)
        axisPoints[#axisPoints + 1] = THREE.Vector3(start.x + ax * extent, start.y + ay * extent, start.z + az * extent)
    end

    if drag.mode == "rotate" then
        if drag.handle == "e" then
            -- TransformControls intentionally hides its AXIS helper for E.
        elseif drag.handle == "free" and drag.currentRotationAxis then
            AddAxisLine(
                drag.currentRotationAxis[1],
                drag.currentRotationAxis[2],
                drag.currentRotationAxis[3]
            )
        else
            local axis = HandleAxis(drag.handle)
            if axis then
                local ax, ay, az = AxisForBlock(axis, start, false)
                AddAxisLine(ax, ay, az)
            end
        end
    else
        for _, axis in ipairs(HandleAxes(drag.handle)) do
            local ax, ay, az = AxisForBlock(axis, start, drag.mode == "scale")
            AddAxisLine(ax, ay, az)
        end
    end

    self:SetDragHelperPoints(self.dragAxisHelper, axisPoints)

    if drag.mode == "translate" then
        self:SetDragHelperPoints(self.dragDeltaHelper, { startPoint, endPoint })
        self.dragStartHelper.position:set(startPoint.x, startPoint.y, startPoint.z)
        self.dragStartHelper.scale:set(helperScale, helperScale, helperScale)
        self.dragStartHelper.visible = true
        self.dragEndHelper.position:set(endPoint.x, endPoint.y, endPoint.z)
        self.dragEndHelper.scale:set(helperScale, helperScale, helperScale)
        self.dragEndHelper.visible = true
        self:RefreshAlignmentGuides(drag.alignmentSnaps, block)
    else
        self.dragDeltaHelper.visible = false
        self.dragStartHelper.visible = false
        self.dragEndHelper.visible = false
        self:RefreshAlignmentGuides(nil, nil)
    end
end

function Methods:AddGizmoMesh(parent, geometry, material, x, y, z, sx, sy, sz, rx, ry, rz)
    local mesh = THREE.Mesh(geometry, material)
    mesh.position:set(x or 0, y or 0, z or 0)
    mesh.scale:set(sx or 1, sy or 1, sz or 1)
    mesh.rotation:set(rx or 0, ry or 0, rz or 0)
    mesh.castShadow = false
    mesh.renderOrder = 127
    MakerTransformControls.MarkOverlayObject(mesh)
    parent:add(mesh)
    return mesh
end

function Methods:CreateTransformGizmo()
    self.gizmo = THREE.Group()
    self.gizmo.visible = false
    self.scene:add(self.gizmo)
    self.gizmoGroups = {}
    self.gizmoMaterialBases = {}
    self.gizmoHandleMaterials = { translate = {}, scale = {}, rotate = {} }
    self.gizmoVisualHandles = { translate = {}, scale = {}, rotate = {} }
    self.gizmoAxisEndpointMeshes = { translate = {}, scale = {} }
    self.gizmoAxisShaftMeshes = { translate = {}, scale = {} }
    self.gizmoTechniques = {}

    local function Material(hex, opacity)
        local material = THREE.MeshBasicMaterial({
            color = hex,
            -- Always use the alpha overlay pass. Together with CMP_ALWAYS and
            -- render order 255 this matches HTML depthTest=false: selected
            -- blocks can never occlude any transform handle.
            transparent = true,
            opacity = opacity or 1,
        })
        -- TransformControls is an overlay: its handles never read or write the
        -- scene depth buffer. MeshBasicMaterial does not expose those flags in
        -- this wrapper, so clone its native technique per gizmo material and
        -- set the render passes programmatically.
        ConfigureOverlayMaterial(material, self.gizmoTechniques)
        self.gizmoMaterialBases[material] = { color = hex, opacity = opacity or 1 }
        return material
    end

    local colors = {
        x = Material(0xff0000),
        y = Material(0x00ff00),
        z = Material(0x0000ff),
    }
    self.gizmoAxisMaterials = colors
    local axes = { "x", "y", "z" }

    local function AddAxis(parent, mode, axis, endKind)
        local axisGroup = THREE.Group()
        parent:add(axisGroup)
        parent = axisGroup
        local material = colors[axis]
        local function AddShaft(...)
            local mesh = self:AddGizmoMesh(parent, ...)
            -- The rendered shaft is also its exact picker. This keeps mobile
            -- hit testing on the same native camera ray as the scene instead
            -- of reconstructing a second, screen-space touch corridor.
            MakerTransformControls.MarkOverlayPickerObject(mesh, axis, "object")
            self.gizmoAxisShaftMeshes[mode][axis] = mesh
            return mesh
        end
        local function AddEndpoint(...)
            local mesh = self:AddGizmoMesh(parent, ...)
            MakerTransformControls.MarkOverlayPickerObject(mesh, axis, "object")
            local endpoints = self.gizmoAxisEndpointMeshes[mode][axis] or {}
            endpoints[#endpoints + 1] = mesh
            self.gizmoAxisEndpointMeshes[mode][axis] = endpoints
            return mesh
        end
        if axis == "x" then
            AddShaft(THREE.CylinderGeometry(1, 1, 1, 3), material, 0.25, 0, 0, 0.0125, 0.5, 0.0125, 0, 0, -math.pi / 2)
            if endKind == "arrow" then
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0.55, 0, 0, 0.04, 0.1, 0.04, 0, 0, -math.pi / 2)
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, -0.55, 0, 0, 0.04, 0.1, 0.04, 0, 0, math.pi / 2)
            else
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0.54, 0, 0, 0.08, 0.08, 0.08)
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, -0.54, 0, 0, 0.08, 0.08, 0.08)
            end
        elseif axis == "y" then
            AddShaft(THREE.CylinderGeometry(1, 1, 1, 3), material, 0, 0.25, 0, 0.0125, 0.5, 0.0125)
            if endKind == "arrow" then
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, 0.55, 0, 0.04, 0.1, 0.04)
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, -0.55, 0, 0.04, 0.1, 0.04, 0, 0, math.pi)
            else
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, 0.54, 0, 0.08, 0.08, 0.08)
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, -0.54, 0, 0.08, 0.08, 0.08)
            end
        else
            AddShaft(THREE.CylinderGeometry(1, 1, 1, 3), material, 0, 0, 0.25, 0.0125, 0.5, 0.0125, math.pi / 2, 0, 0)
            if endKind == "arrow" then
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, 0, 0.55, 0.04, 0.1, 0.04, math.pi / 2, 0, 0)
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, 0, -0.55, 0.04, 0.1, 0.04, -math.pi / 2, 0, 0)
            else
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, 0, 0.54, 0.08, 0.08, 0.08)
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, 0, -0.54, 0.08, 0.08, 0.08)
            end
        end
        return axisGroup
    end

    local function AddPlaneHandles(parent, mode)
        local planeSpecs = {
            -- TransformControls colors a plane by its perpendicular axis:
            -- XY -> Z blue, YZ -> X red, XZ -> Y green.
            xy = { color = 0x0000ff, x = 0.15, y = 0.15, z = 0, rx = 0, ry = 0, rz = 0 },
            yz = { color = 0xff0000, x = 0, y = 0.15, z = 0.15, rx = 0, ry = math.pi / 2, rz = 0 },
            xz = { color = 0x00ff00, x = 0.15, y = 0, z = 0.15, rx = -math.pi / 2, ry = 0, rz = 0 },
        }
        for handle, spec in pairs(planeSpecs) do
            local material = Material(spec.color, 0.5)
            self.gizmoHandleMaterials[mode][handle] = material
            local mesh = self:AddGizmoMesh(parent, THREE.BoxGeometry(0.15, 0.15, 0.01), material,
                spec.x, spec.y, spec.z, 1, 1, 1, spec.rx, spec.ry, spec.rz)
            MakerTransformControls.MarkOverlayPickerObject(mesh, handle, "object")
            self.gizmoVisualHandles[mode][handle] = mesh
        end
        local center = Material(0xffffff, 0.25)
        self.gizmoHandleMaterials[mode].xyz = center
        local centerGeometry = mode == "translate"
            and THREE.OctahedronGeometry(0.1, 0)
            or THREE.BoxGeometry(0.1, 0.1, 0.1)
        local centerMesh = self:AddGizmoMesh(parent, centerGeometry, center)
        MakerTransformControls.MarkOverlayPickerObject(centerMesh, "xyz", "object")
        self.gizmoVisualHandles[mode].xyz = centerMesh
    end

    local translate = THREE.Group()
    for _, axis in ipairs(axes) do
        self.gizmoVisualHandles.translate[axis] = AddAxis(translate, "translate", axis, "arrow")
    end
    AddPlaneHandles(translate, "translate")
    self.gizmo:add(translate)
    self.gizmoGroups.translate = translate

    local scale = THREE.Group()
    for _, axis in ipairs(axes) do
        self.gizmoVisualHandles.scale[axis] = AddAxis(scale, "scale", axis, "box")
    end
    AddPlaneHandles(scale, "scale")
    self.gizmo:add(scale)
    self.gizmoGroups.scale = scale

    local rotate = THREE.Group()
    self.gizmoRotateAxisGroups = {}
    local function AddAxisHalfRing(axis, material)
        local dynamic = THREE.Group()
        rotate:add(dynamic)
        -- The rendered tube is deliberately substantial enough to target on
        -- a phone. The exact same mesh is the picker, so there is no invisible
        -- touch band around a thin-looking ring.
        local geometry = THREE.TorusGeometry(0.5, 0.025, 4, 64, math.pi)
        local ring
        if axis == "x" then
            -- CircleGeometry in Three applies rotateY(pi/2), then
            -- rotateX(pi/2), yielding a YZ semicircle with z >= 0.
            local rotateX = THREE.Group()
            rotateX.rotation:set(math.pi / 2, 0, 0)
            dynamic:add(rotateX)
            local rotateY = THREE.Group()
            rotateY.rotation:set(0, math.pi / 2, 0)
            rotateX:add(rotateY)
            ring = self:AddGizmoMesh(rotateY, geometry, material)
        elseif axis == "y" then
            ring = self:AddGizmoMesh(dynamic, geometry, material, 0, 0, 0, 1, 1, 1, math.pi / 2, 0, 0)
        else
            ring = self:AddGizmoMesh(dynamic, geometry, material, 0, 0, 0, 1, 1, 1, 0, 0, -math.pi / 2)
        end
        MakerTransformControls.MarkOverlayPickerObject(ring, axis, "object")
        self.gizmoRotateAxisGroups[axis] = dynamic
        self.gizmoVisualHandles.rotate[axis] = dynamic
    end
    AddAxisHalfRing("x", colors.x)
    AddAxisHalfRing("y", colors.y)
    AddAxisHalfRing("z", colors.z)
    local screenMaterial = Material(0xffff00, 0.25)
    self.gizmoHandleMaterials.rotate.e = screenMaterial
    local screenGroup = THREE.Group()
    self.gizmoScreenGroup = screenGroup
    local eRing = self:AddGizmoMesh(screenGroup, THREE.TorusGeometry(0.75, 0.025, 4, 64), screenMaterial)
    MakerTransformControls.MarkOverlayPickerObject(eRing, "e", "object")
    self.gizmoVisualHandles.rotate.e = eRing
    local freeMaterial = Material(0x787878)
    self.gizmoHandleMaterials.rotate.free = freeMaterial
    local freeRing = self:AddGizmoMesh(screenGroup, THREE.TorusGeometry(0.5, 0.025, 4, 64), freeMaterial)
    MakerTransformControls.MarkOverlayPickerObject(freeRing, "free", "object")
    self.gizmoVisualHandles.rotate.free = freeRing
    rotate:add(screenGroup)
    self.gizmo:add(rotate)
    self.gizmoGroups.rotate = rotate
    self.gizmoHandleScaleBases = {}
    for mode, handles in pairs(self.gizmoVisualHandles) do
        self.gizmoHandleScaleBases[mode] = {}
        for handle, object in pairs(handles) do
            self.gizmoHandleScaleBases[mode][handle] = {
                x = object.scale.x,
                y = object.scale.y,
                z = object.scale.z,
            }
        end
    end
    self.gizmoExactPickerComponents = CollectExactPickerComponents(self.gizmo)
    -- Do not create the former lower-left synchronized phone gizmo. Mobile
    -- users manipulate the enlarged controls on the selected block directly.
    self.mobileGizmoBundle = nil
    self.mobileGizmo = nil
    self:RefreshHelpers()
end

-- A second, screen-anchored Transform Gizmo for phones. It deliberately uses
-- the same geometry and material objects as the gizmo attached to the block,
-- so modes, colors, highlighting and visible hit silhouettes cannot drift.
function Methods:CreateMobileTransformGizmo()
    local bundle = {
        root = THREE.Group(),
        groups = {},
        visualHandles = { translate = {}, scale = {}, rotate = {} },
        axisEndpointMeshes = { translate = {}, scale = {} },
        axisShaftMeshes = { translate = {}, scale = {} },
        rotateAxisGroups = {},
        handleScaleBases = {},
    }
    bundle.root.visible = false
    self.scene:add(bundle.root)
    local axes = { "x", "y", "z" }

    local function AddAxis(parent, mode, axis, endKind)
        local axisGroup = THREE.Group()
        parent:add(axisGroup)
        local material = self.gizmoAxisMaterials[axis]
        local function AddShaft(...)
            local mesh = self:AddGizmoMesh(axisGroup, ...)
            MakerTransformControls.MarkOverlayPickerObject(mesh, axis, "fixed")
            bundle.axisShaftMeshes[mode][axis] = mesh
            return mesh
        end
        local function AddEndpoint(...)
            local mesh = self:AddGizmoMesh(axisGroup, ...)
            MakerTransformControls.MarkOverlayPickerObject(mesh, axis, "fixed")
            local endpoints = bundle.axisEndpointMeshes[mode][axis] or {}
            endpoints[#endpoints + 1] = mesh
            bundle.axisEndpointMeshes[mode][axis] = endpoints
            return mesh
        end
        if axis == "x" then
            AddShaft(THREE.CylinderGeometry(1, 1, 1, 3), material, 0.25, 0, 0, 0.0125, 0.5, 0.0125, 0, 0, -math.pi / 2)
            if endKind == "arrow" then
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0.55, 0, 0, 0.04, 0.1, 0.04, 0, 0, -math.pi / 2)
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, -0.55, 0, 0, 0.04, 0.1, 0.04, 0, 0, math.pi / 2)
            else
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0.54, 0, 0, 0.08, 0.08, 0.08)
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, -0.54, 0, 0, 0.08, 0.08, 0.08)
            end
        elseif axis == "y" then
            AddShaft(THREE.CylinderGeometry(1, 1, 1, 3), material, 0, 0.25, 0, 0.0125, 0.5, 0.0125)
            if endKind == "arrow" then
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, 0.55, 0, 0.04, 0.1, 0.04)
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, -0.55, 0, 0.04, 0.1, 0.04, 0, 0, math.pi)
            else
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, 0.54, 0, 0.08, 0.08, 0.08)
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, -0.54, 0, 0.08, 0.08, 0.08)
            end
        else
            AddShaft(THREE.CylinderGeometry(1, 1, 1, 3), material, 0, 0, 0.25, 0.0125, 0.5, 0.0125, math.pi / 2, 0, 0)
            if endKind == "arrow" then
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, 0, 0.55, 0.04, 0.1, 0.04, math.pi / 2, 0, 0)
                AddEndpoint(THREE.ConeGeometry(1, 1, 12), material, 0, 0, -0.55, 0.04, 0.1, 0.04, -math.pi / 2, 0, 0)
            else
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, 0, 0.54, 0.08, 0.08, 0.08)
                AddEndpoint(THREE.BoxGeometry(1, 1, 1), material, 0, 0, -0.54, 0.08, 0.08, 0.08)
            end
        end
        return axisGroup
    end

    local function AddPlaneHandles(parent, mode)
        local planeSpecs = {
            xy = { x = 0.15, y = 0.15, z = 0, rx = 0, ry = 0, rz = 0 },
            yz = { x = 0, y = 0.15, z = 0.15, rx = 0, ry = math.pi / 2, rz = 0 },
            xz = { x = 0.15, y = 0, z = 0.15, rx = -math.pi / 2, ry = 0, rz = 0 },
        }
        for handle, spec in pairs(planeSpecs) do
            local mesh = self:AddGizmoMesh(
                parent,
                THREE.BoxGeometry(0.15, 0.15, 0.01),
                self.gizmoHandleMaterials[mode][handle],
                spec.x, spec.y, spec.z, 1, 1, 1, spec.rx, spec.ry, spec.rz
            )
            MakerTransformControls.MarkOverlayPickerObject(mesh, handle, "fixed")
            bundle.visualHandles[mode][handle] = mesh
        end
        local centerGeometry = mode == "translate"
            and THREE.OctahedronGeometry(0.1, 0)
            or THREE.BoxGeometry(0.1, 0.1, 0.1)
        local centerMesh = self:AddGizmoMesh(
            parent, centerGeometry, self.gizmoHandleMaterials[mode].xyz
        )
        MakerTransformControls.MarkOverlayPickerObject(centerMesh, "xyz", "fixed")
        bundle.visualHandles[mode].xyz = centerMesh
    end

    local translate = THREE.Group()
    for _, axis in ipairs(axes) do
        bundle.visualHandles.translate[axis] = AddAxis(translate, "translate", axis, "arrow")
    end
    AddPlaneHandles(translate, "translate")
    bundle.root:add(translate)
    bundle.groups.translate = translate

    local scale = THREE.Group()
    for _, axis in ipairs(axes) do
        bundle.visualHandles.scale[axis] = AddAxis(scale, "scale", axis, "box")
    end
    AddPlaneHandles(scale, "scale")
    bundle.root:add(scale)
    bundle.groups.scale = scale

    local rotate = THREE.Group()
    local function AddAxisHalfRing(axis, material)
        local dynamic = THREE.Group()
        rotate:add(dynamic)
        local geometry = THREE.TorusGeometry(0.5, 0.025, 4, 64, math.pi)
        local ring
        if axis == "x" then
            local rotateX = THREE.Group()
            rotateX.rotation:set(math.pi / 2, 0, 0)
            dynamic:add(rotateX)
            local rotateY = THREE.Group()
            rotateY.rotation:set(0, math.pi / 2, 0)
            rotateX:add(rotateY)
            ring = self:AddGizmoMesh(rotateY, geometry, material)
        elseif axis == "y" then
            ring = self:AddGizmoMesh(dynamic, geometry, material, 0, 0, 0, 1, 1, 1, math.pi / 2, 0, 0)
        else
            ring = self:AddGizmoMesh(dynamic, geometry, material, 0, 0, 0, 1, 1, 1, 0, 0, -math.pi / 2)
        end
        MakerTransformControls.MarkOverlayPickerObject(ring, axis, "fixed")
        bundle.rotateAxisGroups[axis] = dynamic
        bundle.visualHandles.rotate[axis] = dynamic
    end
    AddAxisHalfRing("x", self.gizmoAxisMaterials.x)
    AddAxisHalfRing("y", self.gizmoAxisMaterials.y)
    AddAxisHalfRing("z", self.gizmoAxisMaterials.z)
    bundle.screenGroup = THREE.Group()
    bundle.visualHandles.rotate.e = self:AddGizmoMesh(
        bundle.screenGroup,
        THREE.TorusGeometry(0.75, 0.025, 4, 64),
        self.gizmoHandleMaterials.rotate.e
    )
    MakerTransformControls.MarkOverlayPickerObject(bundle.visualHandles.rotate.e, "e", "fixed")
    bundle.visualHandles.rotate.free = self:AddGizmoMesh(
        bundle.screenGroup,
        THREE.TorusGeometry(0.5, 0.025, 4, 64),
        self.gizmoHandleMaterials.rotate.free
    )
    MakerTransformControls.MarkOverlayPickerObject(bundle.visualHandles.rotate.free, "free", "fixed")
    rotate:add(bundle.screenGroup)
    bundle.root:add(rotate)
    bundle.groups.rotate = rotate

    for mode, handles in pairs(bundle.visualHandles) do
        bundle.handleScaleBases[mode] = {}
        for handle, object in pairs(handles) do
            bundle.handleScaleBases[mode][handle] = {
                x = object.scale.x,
                y = object.scale.y,
                z = object.scale.z,
            }
        end
    end
    self.mobileGizmoBundle = bundle
    self.mobileGizmo = bundle.root
    bundle.exactPickerComponents = CollectExactPickerComponents(bundle.root)
end

function Methods:GetGizmoScale(block)
    if not block then return 1 end
    local dx = self.camera.position.x - block.x
    local dy = self.camera.position.y - block.y
    local dz = self.camera.position.z - block.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local perspectiveFactor = math.min(1.9 * math.tan((self.camera.fov or 36) * DEG * 0.5), 7)
    return math.max(0.001, distance * perspectiveFactor * self.transformSize / 4)
end

function Methods:IsGizmoHandleVisible(block, handle)
    if not block or (self.transformMode ~= "translate" and self.transformMode ~= "scale") then return true end
    if handle == "xyz" then return true end
    local _, _, _, _, _, _, eyeX, eyeY, eyeZ = self:GetCameraBasis(block)
    local localSpace = self.transformMode == "scale"
    local axis = HandleAxis(handle)
    local isAxisHandle = handle == "x" or handle == "y" or handle == "z"
        or handle == "x+" or handle == "x-"
        or handle == "y+" or handle == "y-"
        or handle == "z+" or handle == "z-"
    if axis and isAxisHandle then
        -- Keep all three axes visible even when one points almost directly at
        -- the camera. The overlay pass already ignores scene depth, and the
        -- visible end cap remains a valid exact target in this view.
        return true
    end
    local normalAxis = handle == "xy" and "z" or handle == "yz" and "x" or handle == "xz" and "y" or nil
    if normalAxis then
        local nx, ny, nz = AxisForBlock(normalAxis, block, localSpace)
        return math.abs(DotVector(nx, ny, nz, eyeX, eyeY, eyeZ)) >= 0.2
    end
    return true
end

function Methods:GetMobileGizmoAnchor(block)
    if not self.mobileEditor or not block or not self.viewportRect then return nil end
    local rect = self.viewportRect
    local width = math.max(1, rect.right - rect.left)
    local height = math.max(1, rect.bottom - rect.top)
    -- Keep the fixed control in the lower-left editing area, clear of the
    -- bottom tool bar. Its center is stable in framebuffer space on every
    -- camera orbit and on every phone aspect ratio.
    local inset = math.min(width * 0.38, height * 0.27)
    local screenX = rect.left + inset
    local screenY = rect.bottom - inset
    local ray = self:GetScreenRay(screenX, screenY)
    if not ray then return nil end
    local distance = 6
    self.mobileGizmoScreenX, self.mobileGizmoScreenY = screenX, screenY
    return {
        x = ray.origin.x + ray.direction.x * distance,
        y = ray.origin.y + ray.direction.y * distance,
        z = ray.origin.z + ray.direction.z * distance,
        rx = block.rx,
        ry = block.ry,
        rz = block.rz,
    }
end

function Methods:IsInMobileGizmoGestureArea(x, y)
    if not self.mobileGizmoBlock or not self.mobileGizmoScreenX or not self.mobileGizmoScreenY
        or not self.viewportRect then return false end
    local rect = self.viewportRect
    local width = math.max(1, rect.right - rect.left)
    local height = math.max(1, rect.bottom - rect.top)
    -- Matches the visible fixed controller footprint, including its outer
    -- screen-rotation ring. This is only a gesture-start area; individual
    -- one-finger handles still use their exact visible geometry.
    local radius = math.min(width * 0.38, height * 0.27) * 1.02
    local dx, dy = x - self.mobileGizmoScreenX, y - self.mobileGizmoScreenY
    return dx * dx + dy * dy <= radius * radius
end

function Methods:RefreshGizmoBundle(bundle, block, visible, scale)
    if not bundle then return end
    SetObjectTreeEnabled(bundle.root, visible)
    if visible and block then
        bundle.root.position:set(block.x, block.y, block.z)
        if self.transformMode == "scale" then
            bundle.root.rotation:set(block.rx, block.ry, block.rz)
        else
            bundle.root.rotation:set(0, 0, 0)
        end
        bundle.root.scale:set(scale, scale, scale)
        if bundle.screenGroup then bundle.screenGroup:lookAt(self.camera.position) end
        if self.transformMode == "rotate" and bundle.rotateAxisGroups then
            local _, _, _, _, _, _, eyeX, eyeY, eyeZ = self:GetCameraBasis(block)
            bundle.rotateAxisGroups.x.rotation:set(math.atan(-eyeY, eyeZ), 0, 0)
            bundle.rotateAxisGroups.y.rotation:set(0, math.atan(eyeX, eyeZ), 0)
            bundle.rotateAxisGroups.z.rotation:set(0, 0, math.atan(eyeY, eyeX))
        end
    end
    for name, group in pairs(bundle.groups or {}) do
        SetObjectTreeEnabled(group, visible and name == self.transformMode)
    end
    if visible then
        for handle, object in pairs((bundle.visualHandles or {})[self.transformMode] or {}) do
            SetObjectTreeEnabled(object, self:IsGizmoHandleVisible(block, handle))
        end
    end
end

function Methods:RefreshHelpers()
    local block = self:GetSelected()
    local visible = block ~= nil and self.transformAttached
    -- The fixed lower-left phone gizmo has been removed. Keeping this state
    -- false also disables its old gesture area and prevents invisible capture.
    local mobileVisible = false
    local gizmoScale = 1
    local mobileBlock = nil
    local mobileScale = 1
    self.selectionHelper.visible = block ~= nil
    self.selectionHalo.visible = block ~= nil
    SetObjectTreeEnabled(self.gizmo, visible)
    if block then
        self.selectionHelper.position:set(block.x, block.y, block.z)
        self.selectionHelper.rotation:set(0, 0, 0)
        local xx, xy, xz = RotateForward(1, 0, 0, block.rx, block.ry, block.rz)
        local yx, yy, yz = RotateForward(0, 1, 0, block.rx, block.ry, block.rz)
        local zx, zy, zz = RotateForward(0, 0, 1, block.rx, block.ry, block.rz)
        local bounds = Catalog.FindShape(block.shapeId).bounds
        local sx = block.sx * bounds[1]
        local sy = block.sy * bounds[2]
        local sz = block.sz * bounds[3]
        self.selectionHelper.scale:set(
            math.abs(xx * sx) + math.abs(yx * sy) + math.abs(zx * sz),
            math.abs(xy * sx) + math.abs(yy * sy) + math.abs(zy * sz),
            math.abs(xz * sx) + math.abs(yz * sy) + math.abs(zz * sz)
        )
        local selectionScaleX, selectionScaleY, selectionScaleZ = self.selectionHelper.scale.x, self.selectionHelper.scale.y, self.selectionHelper.scale.z
        local haloPadding = math.max(0.012, self:GetGizmoScale(block) * 0.009)
        self.selectionHalo.position:set(block.x, block.y, block.z)
        self.selectionHalo.rotation:set(0, 0, 0)
        self.selectionHalo.scale:set(
            selectionScaleX + haloPadding,
            selectionScaleY + haloPadding,
            selectionScaleZ + haloPadding
        )
        self.gizmo.position:set(block.x, block.y, block.z)
        -- Three TransformControls forces scale handles into object-local space,
        -- while translate/rotate retain the workbench's default world space.
        if self.transformMode == "scale" then
            self.gizmo.rotation:set(block.rx, block.ry, block.rz)
        else
            self.gizmo.rotation:set(0, 0, 0)
        end
        gizmoScale = self:GetGizmoScale(block)
        self.gizmo.scale:set(gizmoScale, gizmoScale, gizmoScale)
        if self.gizmoScreenGroup then self.gizmoScreenGroup:lookAt(self.camera.position) end
        if self.transformMode == "rotate" and self.gizmoRotateAxisGroups then
            local _, _, _, _, _, _, eyeX, eyeY, eyeZ = self:GetCameraBasis(block)
            self.gizmoRotateAxisGroups.x.rotation:set(math.atan(-eyeY, eyeZ), 0, 0)
            self.gizmoRotateAxisGroups.y.rotation:set(0, math.atan(eyeX, eyeZ), 0)
            self.gizmoRotateAxisGroups.z.rotation:set(0, 0, math.atan(eyeY, eyeX))
        end
    end
    for name, group in pairs(self.gizmoGroups or {}) do
        SetObjectTreeEnabled(group, visible and name == self.transformMode)
    end
    if visible then
        for handle, object in pairs((self.gizmoVisualHandles or {})[self.transformMode] or {}) do
            SetObjectTreeEnabled(object, self:IsGizmoHandleVisible(block, handle))
        end
    end
    self.mobileGizmoBlock = nil
    self.mobileGizmoScreenX, self.mobileGizmoScreenY = nil, nil
    self.mobileGizmoScale = mobileScale
    self:RefreshGizmoBundle(self.mobileGizmoBundle, mobileBlock, mobileVisible, mobileScale)
    -- Exact visible pickers live on transformed overlay roots. Queue them
    -- explicitly after every block/camera/fixed-anchor update so the octree
    -- raycast cannot use their previous-frame position on mobile.
    QueueExactPickerComponents(self.octree, self.gizmoExactPickerComponents)
    -- Reassert depthTest=false semantics after every state/material refresh.
    -- This keeps the selection outline and transform gizmo above solid blocks.
    ReinforceOverlayMaterial(self.selectionHelper and self.selectionHelper.material)
    ReinforceOverlayMaterial(self.selectionHalo and self.selectionHalo.material)
    for material in pairs(self.gizmoMaterialBases or {}) do ReinforceOverlayMaterial(material) end
    for _, helper in ipairs(self.dragHelpers or {}) do
        ReinforceOverlayMaterial(helper and helper.material)
    end
    if self.transformOverlay then self.transformOverlay:Sync() end
    if self.transformPicker then
        self.transformPicker:Update(visible and block or nil, self.transformMode, gizmoScale, function(handle)
            return self:IsGizmoHandleVisible(block, handle)
        end)
    end
    if self.mobileTransformPicker then
        self.mobileTransformPicker:Update(mobileVisible and mobileBlock or nil, self.transformMode, mobileScale, function(handle)
            return self:IsGizmoHandleVisible(mobileBlock, handle)
        end)
    end
    if not visible then self:SetGizmoHighlight(nil) end
end

function Methods:ProjectPoint(x, y, z)
    if not self.viewport or not self.camera or not self.viewportRect then return nil end
    -- Viewport:WorldToScreenPoint returns IntVector2. That pixel truncation is
    -- harmless for long shafts but can collapse a small oblique cone into a
    -- degenerate polygon. Project through the Three-compatible camera matrices
    -- and map NDC to the active viewport while retaining sub-pixel precision.
    local point = THREE.Vector3(x, y, z):project(self.camera)
    local rect = self.viewportRect
    return
        rect.left + (point.x + 1) * 0.5 * (rect.right - rect.left),
        rect.top + (1 - point.y) * 0.5 * (rect.bottom - rect.top)
end

function Methods:ProjectGizmoLocalPoint(block, gizmoScale, point)
    local localX, localY, localZ = point[1], point[2], point[3]
    if self.transformMode == "scale" then
        localX, localY, localZ = RotateForward(localX, localY, localZ, block.rx, block.ry, block.rz)
    end
    local worldX = block.x + localX * gizmoScale
    local worldY = block.y + localY * gizmoScale
    local worldZ = block.z + localZ * gizmoScale
    local screenX, screenY = self:ProjectPoint(worldX, worldY, worldZ)
    return screenX, screenY, worldX, worldY, worldZ
end

function Methods:ProjectedMeshShapeContains(x, y, mesh, localPoints, extraPadding)
    local projected = {}
    for _, point in ipairs(localPoints) do
        local world = mesh:localToWorld(THREE.Vector3(point[1], point[2], point[3]))
        local screenX, screenY = self:ProjectPoint(world.x, world.y, world.z)
        if screenX == nil or screenY == nil then return false end
        projected[#projected + 1] = { x = screenX, y = screenY }
    end
    -- Rasterized edges cover sub-pixel samples around the mathematical hull.
    -- Mouse input keeps the original 0.75 framebuffer-pixel edge allowance;
    -- mobile touch may request an explicit finger-sized padding.
    return PointInConvexPolygon(x, y, ConvexHull(projected), 0.75 + (extraPadding or 0))
end

function Methods:HitVisibleAxisEndpoint(x, y, bundle, hitBlock, extraPadding)
    local mode = self.transformMode
    if mode ~= "translate" and mode ~= "scale" then return nil end
    local block = hitBlock or self:GetSelected()
    if not block then return nil end
    local endpointMeshes = bundle and bundle.axisEndpointMeshes or self.gizmoAxisEndpointMeshes
    local best
    local localPoints = {}
    if mode == "translate" then
        -- These are the real unit ConeGeometry vertices. The endpoint mesh's
        -- own scale, rotation and complete parent transform are applied by
        -- localToWorld, so hit testing cannot drift from what is rendered.
        localPoints[#localPoints + 1] = { 0, 0.5, 0 }
        for segment = 0, 11 do
            local angle = segment * math.pi * 2 / 12
            localPoints[#localPoints + 1] = { math.sin(angle), -0.5, math.cos(angle) }
        end
    else
        for _, localX in ipairs({ -0.5, 0.5 }) do
            for _, localY in ipairs({ -0.5, 0.5 }) do
                for _, localZ in ipairs({ -0.5, 0.5 }) do
                    localPoints[#localPoints + 1] = { localX, localY, localZ }
                end
            end
        end
    end

    for _, axis in ipairs({ "x", "y", "z" }) do
        if self:IsGizmoHandleVisible(block, axis) then
            for _, mesh in ipairs((endpointMeshes[mode] or {})[axis] or {}) do
                if self:ProjectedMeshShapeContains(x, y, mesh, localPoints, extraPadding) then
                    local center = mesh:localToWorld(THREE.Vector3(0, 0, 0))
                    local screenX, screenY = self:ProjectPoint(center.x, center.y, center.z)
                    local offsetX, offsetY = x - screenX, y - screenY
                    local screenDistance = offsetX * offsetX + offsetY * offsetY
                    local cameraDistance =
                        (self.camera.position.x - center.x) * (self.camera.position.x - center.x)
                        + (self.camera.position.y - center.y) * (self.camera.position.y - center.y)
                        + (self.camera.position.z - center.z) * (self.camera.position.z - center.z)
                    -- At oblique views two projected end caps can overlap.
                    -- Resolve by pointer proximity, then by the front-most cap,
                    -- instead of the old fixed X/Y/Z iteration order.
                    if not best
                        or screenDistance < best.screenDistance - 0.25
                        or (math.abs(screenDistance - best.screenDistance) <= 0.25
                            and cameraDistance < best.cameraDistance) then
                        best = {
                            axis = axis,
                            screenDistance = screenDistance,
                            cameraDistance = cameraDistance,
                        }
                    end
                end
            end
        end
    end
    return best and best.axis or nil
end

function Methods:HitVisibleAxisShaft(x, y, bundle, hitBlock, extraPadding)
    local mode = self.transformMode
    if mode ~= "translate" and mode ~= "scale" then return nil end
    local block = hitBlock or self:GetSelected()
    if not block then return nil end
    local shaftMeshes = bundle and bundle.axisShaftMeshes or self.gizmoAxisShaftMeshes
    local localPoints = {}
    for _, localY in ipairs({ -0.5, 0.5 }) do
        for segment = 0, 2 do
            local angle = segment * math.pi * 2 / 3
            localPoints[#localPoints + 1] = { math.sin(angle), localY, math.cos(angle) }
        end
    end
    local best

    -- Test the actual rendered triangular shaft mesh. The old Three.js picker
    -- is intentionally much wider and is no longer allowed to create an axis
    -- hit outside this visible rasterized silhouette.
    for _, axis in ipairs({ "x", "y", "z" }) do
        if self:IsGizmoHandleVisible(block, axis) then
            local mesh = (shaftMeshes[mode] or {})[axis]
            if mesh and self:ProjectedMeshShapeContains(x, y, mesh, localPoints, extraPadding) then
                local start = mesh:localToWorld(THREE.Vector3(0, -0.5, 0))
                local finish = mesh:localToWorld(THREE.Vector3(0, 0.5, 0))
                local startX, startY = self:ProjectPoint(start.x, start.y, start.z)
                local finishX, finishY = self:ProjectPoint(finish.x, finish.y, finish.z)
                local distance = PointSegmentDistanceSquared(x, y, startX, startY, finishX, finishY)
                if not best
                    or distance < best.distance - 0.25
                    or (math.abs(distance - best.distance) <= 0.25 and axis < best.axis) then
                    best = { axis = axis, distance = distance }
                end
            end
        end
    end
    return best and best.axis or nil
end

function Methods:GetCameraBasis(block)
    local ex, ey, ez = NormalizeVector(
        self.camera.position.x - block.x,
        self.camera.position.y - block.y,
        self.camera.position.z - block.z
    )
    local fx, fy, fz = -ex, -ey, -ez
    local ux, uy, uz = 0, 1, 0
    if math.abs(fy) > 0.98 then ux, uy, uz = 0, 0, 1 end
    local rx, ry, rz = CrossVector(fx, fy, fz, ux, uy, uz)
    rx, ry, rz = NormalizeVector(rx, ry, rz)
    ux, uy, uz = CrossVector(rx, ry, rz, fx, fy, fz)
    ux, uy, uz = NormalizeVector(ux, uy, uz)
    return rx, ry, rz, ux, uy, uz, ex, ey, ez
end

function Methods:RayPlanePoint(screenX, screenY, ox, oy, oz, nx, ny, nz)
    local ray = self:GetScreenRay(screenX, screenY)
    if not ray then return nil end
    local denominator = DotVector(ray.direction.x, ray.direction.y, ray.direction.z, nx, ny, nz)
    if math.abs(denominator) < 0.00001 then return nil end
    local distance = DotVector(
        ox - ray.origin.x, oy - ray.origin.y, oz - ray.origin.z,
        nx, ny, nz
    ) / denominator
    return {
        x = ray.origin.x + ray.direction.x * distance,
        y = ray.origin.y + ray.direction.y * distance,
        z = ray.origin.z + ray.direction.z * distance,
    }
end

function Methods:SetGizmoHighlight(handle)
    if self.gizmoHighlighted == handle then return end
    self.gizmoHighlighted = handle
    for material, base in pairs(self.gizmoMaterialBases or {}) do
        if material.color and material.color.setHex then material.color:setHex(base.color) end
        material.opacity = base.opacity
    end
    for mode, handles in pairs(self.gizmoVisualHandles or {}) do
        for visualHandle, object in pairs(handles) do
            local base = self.gizmoHandleScaleBases
                and self.gizmoHandleScaleBases[mode]
                and self.gizmoHandleScaleBases[mode][visualHandle]
            if base then object.scale:set(base.x, base.y, base.z) end
        end
    end
    if not handle then return end
    -- Three.js highlights a captured handle by recoloring it yellow; its
    -- rendered geometry does not grow. Invisible picker sizing is independent.
    local direct = self.gizmoHandleMaterials
        and self.gizmoHandleMaterials[self.transformMode]
        and self.gizmoHandleMaterials[self.transformMode][handle]
    if direct and direct.color and direct.color.setHex then
        direct.color:setHex(0xffff00)
        direct.opacity = 1
    end
    local highlightedAxes = HandleAxes(handle)
    if handle == "free" then highlightedAxes = { "x", "y", "z" } end
    for _, axis in ipairs(highlightedAxes) do
        local material = self.gizmoAxisMaterials and self.gizmoAxisMaterials[axis]
        if material and material.color and material.color.setHex then
            material.color:setHex(0xffff00)
            material.opacity = 1
        end
    end
    if handle == "free" then
        local screen = self.gizmoHandleMaterials
            and self.gizmoHandleMaterials.rotate
            and self.gizmoHandleMaterials.rotate.e
        if screen and screen.color and screen.color.setHex then
            screen.color:setHex(0xffff00)
            screen.opacity = 1
        end
    end
end

function Methods:PointerDragThreshold(isTouch)
    return (isTouch and 14 or 8) * math.max(self.uiScale, 0.01)
end

function Methods:GetTouchHitPadding()
    -- Coordinates are framebuffer pixels. Convert a comfortable 12 logical
    -- pixels through the current UI scale, with bounds for unusual DPRs.
    return Clamp(12 * math.max(self.uiScale or 1, 1), 18, 32)
end

function Methods:HitExpandedTouchTarget(x, y, picker)
    if not picker or not self.viewportRect then return nil end
    local padding = self:GetTouchHitPadding()
    local rect = self.viewportRect
    -- A golden-angle spiral covers the complete finger-sized disk with a
    -- bounded number of native rays. Every successful sample must still hit
    -- the real rendered mesh; no oversized 3D picker volume is accepted.
    local sampleCount = 32
    local goldenAngle = math.pi * (3 - math.sqrt(5))
    for sample = 1, sampleCount do
        local radius = padding * math.sqrt(sample / sampleCount)
        local angle = sample * goldenAngle
        local sampleX = x + math.cos(angle) * radius
        local sampleY = y + math.sin(angle) * radius
        if sampleX >= rect.left and sampleX < rect.right
            and sampleY >= rect.top and sampleY < rect.bottom then
            local handle, exact = picker:HitTest(self:GetScreenRay(sampleX, sampleY))
            if exact then return handle end
        end
    end
    return nil
end

function Methods:HitGizmoTarget(x, y, isTouch, bundle, picker, block)
    if not block or not picker then return nil end
    -- Prefer a native triangle hit on the exact mesh that was rendered. Shaft,
    -- endpoint, plane, center and rotation handles all share this path. Mouse
    -- stops here; touch may add a bounded screen-space finger allowance below.
    local handle, exact = picker:HitTest(self:GetScreenRay(x, y))
    if exact then return handle end
    if isTouch then
        local expanded = self:HitExpandedTouchTarget(x, y, picker)
        if expanded then return expanded end
    end
    -- Keep the projected visible silhouette only as a same-size fallback for
    -- a drawable whose octree update is still queued in this input frame. On
    -- mobile, apply the same bounded finger padding to this linear fallback.
    local fallbackPadding = isTouch and self:GetTouchHitPadding() or 0
    local endpoint = self:HitVisibleAxisEndpoint(x, y, bundle, block, fallbackPadding)
    if endpoint then return endpoint end
    local shaft = self:HitVisibleAxisShaft(x, y, bundle, block, fallbackPadding)
    if shaft then return shaft end
    -- Reject Three.js's intentionally oversized invisible fallback pickers.
    return nil
end

function Methods:HitGizmo(x, y, isTouch)
    local block = self:GetSelected()
    if not block or not self.transformAttached or not self.transformPicker then return nil end
    local fixed
    if self.mobileGizmoBlock and self.mobileTransformPicker then
        fixed = self:HitGizmoTarget(
            x, y, isTouch, self.mobileGizmoBundle, self.mobileTransformPicker, self.mobileGizmoBlock
        )
    end
    local attached = self:HitGizmoTarget(x, y, isTouch, nil, self.transformPicker, block)
    if fixed and attached then
        -- When the fixed phone controller overlaps the object controller,
        -- capture the controller whose visible centre is closest to the touch
        -- instead of always letting the fixed copy steal the event.
        local fixedX, fixedY = self.mobileGizmoScreenX, self.mobileGizmoScreenY
        local objectX, objectY = self:ProjectPoint(block.x, block.y, block.z)
        if fixedX and fixedY and objectX and objectY then
            local fdx, fdy = x - fixedX, y - fixedY
            local odx, ody = x - objectX, y - objectY
            if odx * odx + ody * ody < fdx * fdx + fdy * fdy then
                return attached, "object"
            end
        end
        return fixed, "fixed"
    end
    if fixed then return fixed, "fixed" end
    if attached then return attached, "object" end
    return nil
end

function Methods:IsNearGizmo(x, y, isTouch)
    return self:HitGizmo(x, y, isTouch) ~= nil
end

function Methods:HoverTransform(x, y)
    if self.transformDrag then return true end
    local handle = self:HitGizmo(x, y)
    self:SetGizmoHighlight(handle)
    self:RefreshHoverAxisHelper(handle)
    return self.gizmoHighlighted ~= nil
end

function Methods:ClearTransformHover()
    if not self.transformDrag then
        self:SetGizmoHighlight(nil)
        self:HideDragHelpers()
    end
end

function Methods:DragPlaneFor(handle, block, mode)
    local axis = HandleAxis(handle)
    if mode == "rotate" and axis then return AxisVector(axis) end
    local _, _, _, _, _, _, ex, ey, ez = self:GetCameraBasis(block)
    if handle == "xyz" or handle == "e" then return ex, ey, ez end
    if handle == "xy" then return AxisForBlock("z", block, mode == "scale") end
    if handle == "yz" then return AxisForBlock("x", block, mode == "scale") end
    if handle == "xz" then return AxisForBlock("y", block, mode == "scale") end
    if axis then
        local ax, ay, az = AxisForBlock(axis, block, mode == "scale")
        local amount = DotVector(ex, ey, ez, ax, ay, az)
        local nx, ny, nz = ex - ax * amount, ey - ay * amount, ez - az * amount
        nx, ny, nz = NormalizeVector(nx, ny, nz)
        if VectorLength(nx, ny, nz) < 0.0001 then
            local rx, ry, rz, ux, uy, uz = self:GetCameraBasis(block)
            nx, ny, nz = CrossVector(ax, ay, az, rx, ry, rz)
            if VectorLength(nx, ny, nz) < 0.0001 then nx, ny, nz = CrossVector(ax, ay, az, ux, uy, uz) end
            nx, ny, nz = NormalizeVector(nx, ny, nz)
        end
        return nx, ny, nz
    end
    return ex, ey, ez
end

function Methods:BeginTransformDrag(x, y, isTouch)
    local handle, source = self:HitGizmo(x, y, isTouch)
    local block = self:GetSelected()
    if not handle or not block then return false end
    local fixedPointerMap = nil
    if source == "fixed" and self.mobileGizmoScreenX and self.mobileGizmoScreenY then
        local objectX, objectY = self:ProjectPoint(block.x, block.y, block.z)
        if objectX and objectY then
            fixedPointerMap = {
                fixedX = self.mobileGizmoScreenX,
                fixedY = self.mobileGizmoScreenY,
                objectX = objectX,
                objectY = objectY,
                scale = self.transformSize / 1.35,
            }
            x = objectX + (x - fixedPointerMap.fixedX) * fixedPointerMap.scale
            y = objectY + (y - fixedPointerMap.fixedY) * fixedPointerMap.scale
        end
    end
    local start = CopyBlock(block)
    local drag = {
        handle = handle,
        source = source,
        mode = self.transformMode,
        startX = x,
        startY = y,
        startBlock = start,
        snapshot = self:Snapshot(),
        changed = false,
        fixedPointerMap = fixedPointerMap,
    }
    if self.transformMode == "rotate" then
        drag.startQuaternion = THREE.Quaternion():setFromEuler(THREE.Euler(start.rx, start.ry, start.rz))
        local _, _, _, _, _, _, eyeX, eyeY, eyeZ = self:GetCameraBasis(start)
        drag.eye = { eyeX, eyeY, eyeZ }
        drag.planeNormal = { eyeX, eyeY, eyeZ }
        drag.startHit = self:RayPlanePoint(x, y, start.x, start.y, start.z, eyeX, eyeY, eyeZ)
        if not drag.startHit then return false end
        drag.rotationDistance = math.max(0.001, VectorLength(
            self.camera.position.x - start.x,
            self.camera.position.y - start.y,
            self.camera.position.z - start.z
        ))
        if handle == "e" then
            drag.rotationAxis = THREE.Vector3(eyeX, eyeY, eyeZ)
        elseif handle ~= "free" then
            local ax, ay, az = AxisVector(handle)
            drag.rotationAxis = THREE.Vector3(ax, ay, az)
        end
    else
        local nx, ny, nz = self:DragPlaneFor(handle, start, self.transformMode)
        drag.planeNormal = { nx, ny, nz }
        drag.startHit = self:RayPlanePoint(x, y, start.x, start.y, start.z, nx, ny, nz)
        if not drag.startHit then return false end
        if self.transformMode == "scale" then
            local localX, localY, localZ = RotateInverse(
                drag.startHit.x - start.x,
                drag.startHit.y - start.y,
                drag.startHit.z - start.z,
                start.rx, start.ry, start.rz
            )
            drag.startLocalHit = { x = localX, y = localY, z = localZ }
            drag.uniformFallback = handle == "xyz" and VectorLength(localX, localY, localZ) < 0.0001
            if handle ~= "xyz" then
                local minimumStart = self:GetGizmoScale(start) * 0.015
                for _, axis in ipairs(HandleAxes(handle)) do
                    if math.abs(drag.startLocalHit[axis] or 0) < minimumStart then return false end
                end
            end
        end
    end
    self.transformDrag = drag
    self:SetGizmoHighlight(handle)
    self:RefreshDragHelpers()
    self:RefreshState()
    return true
end

function Methods:IsFixedTransformDrag()
    return self.transformDrag ~= nil and self.transformDrag.source == "fixed"
end

-- The fixed phone gizmo also acts as a direct multi-touch controller. A
-- gesture is only entered after the first finger captured that fixed gizmo;
-- ordinary two-finger gestures elsewhere continue to control the camera.
function Methods:BeginMobileTransformGesture(firstX, firstY, secondX, secondY)
    if not self.mobileEditor then return false end
    if self.transformDrag then
        if not self:IsFixedTransformDrag() then return false end
        self:CancelTransformDrag()
    end
    local block = self:GetSelected()
    if not block then return false end

    local start = CopyBlock(block)
    local midpointX = (firstX + secondX) * 0.5
    local midpointY = (firstY + secondY) * 0.5
    local deltaX, deltaY = secondX - firstX, secondY - firstY
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    local handle = self.transformMode == "rotate" and "e" or "xyz"
    local drag = {
        handle = handle,
        source = "fixed",
        gesture = true,
        mode = self.transformMode,
        startBlock = start,
        snapshot = self:Snapshot(),
        changed = false,
        startMidX = midpointX,
        startMidY = midpointY,
        startDistance = math.max(4, distance),
        startAngle = math.atan(deltaY, deltaX),
    }

    if drag.mode == "translate" then
        local _, _, _, _, _, _, eyeX, eyeY, eyeZ = self:GetCameraBasis(start)
        drag.planeNormal = { eyeX, eyeY, eyeZ }
        drag.startHit = self:RayPlanePoint(midpointX, midpointY, start.x, start.y, start.z, eyeX, eyeY, eyeZ)
        if not drag.startHit then return false end
    elseif drag.mode == "rotate" then
        local _, _, _, _, _, _, eyeX, eyeY, eyeZ = self:GetCameraBasis(start)
        drag.eye = { eyeX, eyeY, eyeZ }
        drag.startQuaternion = THREE.Quaternion():setFromEuler(THREE.Euler(start.rx, start.ry, start.rz))
    end

    self.transformDrag = drag
    self:SetGizmoHighlight(handle)
    self:RefreshDragHelpers()
    self:RefreshState()
    return true
end

function Methods:DragMobileTransformGesture(firstX, firstY, secondX, secondY)
    local drag = self.transformDrag
    local block = self:GetSelected()
    if not drag or not drag.gesture or not block then return false end

    local midpointX = (firstX + secondX) * 0.5
    local midpointY = (firstY + secondY) * 0.5
    local deltaX, deltaY = secondX - firstX, secondY - firstY
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    local start = drag.startBlock

    if drag.mode == "translate" then
        local normal = drag.planeNormal
        local current = self:RayPlanePoint(
            midpointX, midpointY,
            start.x, start.y, start.z,
            normal[1], normal[2], normal[3]
        )
        if not current or not drag.startHit then return false end
        local nextX = start.x + current.x - drag.startHit.x
        local nextY = start.y + current.y - drag.startHit.y
        local nextZ = start.z + current.z - drag.startHit.z
        block.x, block.y, block.z = self:SnapTranslation(block, nextX, nextY, nextZ, "xyz", drag)
    elseif drag.mode == "rotate" then
        local currentAngle = math.atan(deltaY, deltaX)
        -- Screen Y points downward, so negate the screen-space twist before
        -- applying it around the camera-facing world axis.
        local angle = -NormalizeAngle(currentAngle - drag.startAngle)
        self:ApplyWorldRotation(
            block,
            drag,
            THREE.Vector3(drag.eye[1], drag.eye[2], drag.eye[3]),
            angle
        )
    else
        local factor = math.max(0.02, distance) / drag.startDistance
        block.sx = ContinuousScale(start.sx * factor)
        block.sy = ContinuousScale(start.sy * factor)
        block.sz = ContinuousScale(start.sz * factor)
    end

    drag.changed = drag.changed or TransformValuesChanged(start, block)
    self:ApplyBlockToMesh(block)
    self:RefreshDragHelpers()
    PublishTransformRefresh(self, block)
    return true
end

function Methods:ApplyWorldRotation(block, drag, axis, angle)
    local delta = THREE.Quaternion():setFromAxisAngle(axis, angle)
    local result = THREE.Quaternion():multiplyQuaternions(delta, drag.startQuaternion)
    local euler = THREE.Euler():setFromQuaternion(result)
    block.rx, block.ry, block.rz = euler.x, euler.y, euler.z
end

function Methods:SnapTranslation(block, x, y, z, handle, drag)
    local nextValue = { x = x, y = y, z = z }
    local allowed = {}
    for _, axis in ipairs(HandleAxes(handle)) do allowed[axis] = true end
    local movingHalf = WorldHalfExtents(block)
    local threshold = math.max(0.02, math.min(0.12, self:GetGizmoScale(block) * 0.035))
    local previous = drag.alignmentSnaps or {}
    local snaps = {}

    for _, axis in ipairs({ "x", "y", "z" }) do
        if allowed[axis] then
            local raw = nextValue[axis]
            local best
            local retained = previous[axis]
            if retained and retained.target and self.byId[retained.target.id] then
                local distance = math.abs(raw - retained.value)
                if distance <= threshold * 1.65 then
                    best = {
                        value = retained.value,
                        guideCoordinate = retained.guideCoordinate,
                        kind = retained.kind,
                        target = retained.target,
                        distance = distance,
                        priority = retained.priority,
                    }
                end
            end

            if not best then
                for _, target in ipairs(self.blocks or {}) do
                    if target.id ~= block.id then
                        local targetHalf = WorldHalfExtents(target)
                        local targetCenter = target[axis]
                        local targetMin = targetCenter - targetHalf[axis]
                        local targetMax = targetCenter + targetHalf[axis]
                        local candidates = {
                            { value = targetCenter, guide = targetCenter, kind = "center", priority = 1 },
                            { value = targetMin + movingHalf[axis], guide = targetMin, kind = "face", priority = 2 },
                            { value = targetMax - movingHalf[axis], guide = targetMax, kind = "face", priority = 2 },
                            { value = targetMax + movingHalf[axis], guide = targetMax, kind = "adjacent", priority = 3 },
                            { value = targetMin - movingHalf[axis], guide = targetMin, kind = "adjacent", priority = 3 },
                        }
                        for _, candidate in ipairs(candidates) do
                            local distance = math.abs(raw - candidate.value)
                            local score = distance + candidate.priority * 0.000001
                            if distance <= threshold and (not best or score < best.score) then
                                best = {
                                    value = candidate.value,
                                    guideCoordinate = candidate.guide,
                                    kind = candidate.kind,
                                    target = target,
                                    distance = distance,
                                    score = score,
                                    priority = candidate.priority,
                                }
                            end
                        end
                    end
                end
            end

            if best then
                nextValue[axis] = best.value
                snaps[axis] = best
            end
        end
    end

    drag.alignmentSnaps = snaps
    return nextValue.x, nextValue.y, nextValue.z
end

function Methods:DragTransform(x, y)
    local drag = self.transformDrag
    local block = self:GetSelected()
    if not drag or not block then return false end
    if drag.fixedPointerMap then
        local map = drag.fixedPointerMap
        x = map.objectX + (x - map.fixedX) * map.scale
        y = map.objectY + (y - map.fixedY) * map.scale
    end
    local start = drag.startBlock
    local handle = drag.handle
    if drag.mode == "rotate" then
        local eye = drag.eye
        local normal = drag.planeNormal
        local current = self:RayPlanePoint(x, y, start.x, start.y, start.z, normal[1], normal[2], normal[3])
        if not current or not drag.startHit then return false end
        local startX, startY, startZ = drag.startHit.x - start.x, drag.startHit.y - start.y, drag.startHit.z - start.z
        local endX, endY, endZ = current.x - start.x, current.y - start.y, current.z - start.z
        local offsetX, offsetY, offsetZ = endX - startX, endY - startY, endZ - startZ
        local speed = 20 / drag.rotationDistance
        local axisX, axisY, axisZ
        local angle
        if handle == "free" then
            axisX, axisY, axisZ = CrossVector(offsetX, offsetY, offsetZ, eye[1], eye[2], eye[3])
            axisX, axisY, axisZ = NormalizeVector(axisX, axisY, axisZ)
            if VectorLength(axisX, axisY, axisZ) < 0.0001 then return false end
            drag.currentRotationAxis = { axisX, axisY, axisZ }
            local tangentX, tangentY, tangentZ = CrossVector(axisX, axisY, axisZ, eye[1], eye[2], eye[3])
            angle = DotVector(offsetX, offsetY, offsetZ, tangentX, tangentY, tangentZ) * speed
        elseif handle == "e" then
            axisX, axisY, axisZ = eye[1], eye[2], eye[3]
            angle = SignedInPlaneAngle(startX, startY, startZ, endX, endY, endZ, eye[1], eye[2], eye[3])
        else
            axisX, axisY, axisZ = drag.rotationAxis.x, drag.rotationAxis.y, drag.rotationAxis.z
            local tangentX, tangentY, tangentZ = CrossVector(axisX, axisY, axisZ, eye[1], eye[2], eye[3])
            tangentX, tangentY, tangentZ = NormalizeVector(tangentX, tangentY, tangentZ)
            if VectorLength(tangentX, tangentY, tangentZ) < 0.0001 then
                axisX, axisY, axisZ = eye[1], eye[2], eye[3]
                angle = SignedInPlaneAngle(startX, startY, startZ, endX, endY, endZ, eye[1], eye[2], eye[3])
            else
                angle = DotVector(offsetX, offsetY, offsetZ, tangentX, tangentY, tangentZ) * speed
            end
        end
        self:ApplyWorldRotation(
            block,
            drag,
            THREE.Vector3(axisX, axisY, axisZ),
            angle
        )
    else
        if drag.mode == "scale" and handle == "xyz" then
            local factor
            if drag.uniformFallback then
                factor = math.exp(((x - drag.startX) - (y - drag.startY)) * 0.009 / math.max(self.uiScale, 0.01))
            else
                local normal = drag.planeNormal
                local current = self:RayPlanePoint(x, y, start.x, start.y, start.z, normal[1], normal[2], normal[3])
                if not current or not drag.startHit then return false end
                local startX, startY, startZ = drag.startHit.x - start.x, drag.startHit.y - start.y, drag.startHit.z - start.z
                local endX, endY, endZ = current.x - start.x, current.y - start.y, current.z - start.z
                local startLength = VectorLength(startX, startY, startZ)
                if startLength < 0.0001 then return false end
                factor = VectorLength(endX, endY, endZ) / startLength
                if DotVector(startX, startY, startZ, endX, endY, endZ) < 0 then factor = -factor end
            end
            block.sx = ContinuousScale(start.sx * factor)
            block.sy = ContinuousScale(start.sy * factor)
            block.sz = ContinuousScale(start.sz * factor)
        else
            local normal = drag.planeNormal
            local current = self:RayPlanePoint(x, y, start.x, start.y, start.z, normal[1], normal[2], normal[3])
            if not current or not drag.startHit then return false end
            local dx, dy, dz = current.x - drag.startHit.x, current.y - drag.startHit.y, current.z - drag.startHit.z
            if drag.mode == "translate" then
                local nextX, nextY, nextZ = start.x, start.y, start.z
                if handle == "xyz" then
                    nextX, nextY, nextZ = start.x + dx, start.y + dy, start.z + dz
                else
                    for _, axis in ipairs(HandleAxes(handle)) do
                        local ax, ay, az = AxisVector(axis)
                        local amount = DotVector(dx, dy, dz, ax, ay, az)
                        nextX, nextY, nextZ = nextX + ax * amount, nextY + ay * amount, nextZ + az * amount
                    end
                end
                nextX, nextY, nextZ = self:SnapTranslation(block, nextX, nextY, nextZ, handle, drag)
                block.x, block.y, block.z = nextX, nextY, nextZ
            else
                local handleAxes = HandleAxes(handle)
                local localX, localY, localZ = RotateInverse(
                    current.x - start.x,
                    current.y - start.y,
                    current.z - start.z,
                    start.rx, start.ry, start.rz
                )
                local currentLocal = { x = localX, y = localY, z = localZ }
                for _, axis in ipairs(handleAxes) do
                    local key = axis == "x" and "sx" or axis == "y" and "sy" or "sz"
                    local denominator = drag.startLocalHit and drag.startLocalHit[axis] or 0
                    if math.abs(denominator) < 0.0001 then return false end
                    local value = start[key] * (currentLocal[axis] / denominator)
                    block[key] = ContinuousScale(value)
                end
            end
        end
    end
    drag.changed = drag.changed or TransformValuesChanged(start, block)
    self:ApplyBlockToMesh(block)
    self:RefreshDragHelpers()
    PublishTransformRefresh(self, block)
    return true
end

function Methods:EndTransformDrag()
    local drag = self.transformDrag
    if not drag then return false end
    self.transformDrag = nil
    self:HideDragHelpers()
    self:SetGizmoHighlight(nil)
    local block = self:GetSelected()
    if block then
        block.sx = math.max(0.05, block.sx)
        block.sy = math.max(0.05, block.sy)
        block.sz = math.max(0.05, block.sz)
        drag.changed = drag.changed or TransformValuesChanged(drag.startBlock, block)
        self:ApplyBlockToMesh(block)
    end
    -- TransformControls emits mouseUp for every captured drag, even when the
    -- object did not move. The HTML workbench records that snapshot verbatim.
    self:PushHistory(drag.snapshot)
    self:Commit("已调整积木")
    return true
end

function Methods:CancelTransformDrag()
    local drag = self.transformDrag
    local block = self:GetSelected()
    if not drag or not block then return false end
    local start = drag.startBlock
    for key, value in pairs(start) do if key ~= "id" then block[key] = value end end
    self.transformDrag = nil
    self:HideDragHelpers()
    self:SetGizmoHighlight(nil)
    self:ApplyBlockToMesh(block)
    self:RefreshTransparentTopology()
    self:RefreshState()
    return true
end

function Module.Install(target, dependencies)
    DEG = assert(dependencies.DEG)
    Clamp = assert(dependencies.Clamp)
    CopyBlock = assert(dependencies.CopyBlock)
    RotateForward = assert(dependencies.RotateForward)
    RotateInverse = assert(dependencies.RotateInverse)
    for name, method in pairs(Methods) do target[name] = method end
end

Module._PublishTransformRefresh = PublishTransformRefresh

return Module
