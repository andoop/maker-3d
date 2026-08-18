---@diagnostic disable: undefined-global

-- A project-local StaticModelGroup wrapper used by IslandWorld. Unlike the
-- public three.js compatibility constructor, it accepts an already built
-- native Model so material batches can share one immutable geometry upload.

local NativeVector3 = Vector3
local NativeQuaternion = Quaternion

local Object3D = require("urhox-libs/3D/Core/Object3D")
local Vec3 = require("urhox-libs/3D/Core/Vector3")
local Quat = require("urhox-libs/3D/Core/Quaternion")

local IslandInstancedMesh = {}
local Methods = {}

local function NativeMaterial(material)
    return material and material.getNative and material:getNative() or nil
end

local function Get(self, key)
    if key == "isInstancedMesh" or key == "isMesh" then return true end
    if key == "type" then return "IslandInstancedMesh" end
    if key == "geometry" then return rawget(self, "_geometry") end
    if key == "material" then return rawget(self, "_material") end
    if key == "count" then return rawget(self, "_count") end
    return nil
end

local function Set(self, key, value)
    if key ~= "material" then return false end
    rawset(self, "_material", value)
    local group, native = rawget(self, "_group"), NativeMaterial(value)
    if group and native then group.material = native end
    return true
end

local Meta = Object3D.makeMeta(Methods, Get, Set)

function IslandInstancedMesh.new(geometry, material, count, sharedModel)
    if not sharedModel then return nil end
    local self = setmetatable({}, Meta)
    Object3D.setup(self)
    local node = self:getNode()
    local group = node:CreateComponent("StaticModelGroup")
    group.model = sharedModel
    local native = NativeMaterial(material)
    if native then group.material = native end

    local instances = {}
    for index = 1, math.max(1, tonumber(count) or 1) do
        local instanceNode = node:CreateChild("instance")
        group:AddInstanceNode(instanceNode)
        instances[index] = instanceNode
    end
    rawset(self, "_group", group)
    rawset(self, "_geometry", geometry)
    rawset(self, "_material", material)
    rawset(self, "_model", sharedModel)
    rawset(self, "_count", #instances)
    rawset(self, "_instances", instances)
    return self
end

function Methods:setMatrixAt(index, matrix)
    local instanceNode = rawget(self, "_instances")[(tonumber(index) or 0) + 1]
    if not instanceNode then return self end
    local position, rotation, scale = Vec3.new(), Quat.new(), Vec3.new()
    matrix:decompose(position, rotation, scale)
    instanceNode.position = NativeVector3(position.x, position.y, position.z)
    instanceNode.rotation = NativeQuaternion(rotation.w, rotation.x, rotation.y, rotation.z)
    instanceNode.scale = NativeVector3(scale.x, scale.y, scale.z)
    return self
end

function Methods:getGroup()
    return rawget(self, "_group")
end

return IslandInstancedMesh
