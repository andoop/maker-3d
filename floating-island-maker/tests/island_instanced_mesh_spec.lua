package.path = "scripts/?.lua;" .. package.path

Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
Quaternion = function(w, x, y, z) return { w = w, x = x, y = y, z = z } end

local createdGroup
local fakeNode = {}
function fakeNode:CreateComponent(kind)
    assert(kind == "StaticModelGroup", "island batches must use the retained-mode instancing component")
    createdGroup = { instanceNodes = {} }
    function createdGroup:AddInstanceNode(node)
        self.instanceNodes[#self.instanceNodes + 1] = node
    end
    return createdGroup
end
function fakeNode:CreateChild(name)
    return { name = name }
end

package.preload["urhox-libs/3D/Core/Object3D"] = function()
    local base = {}
    function base.setup(self) rawset(self, "_node", fakeNode) end
    function base.makeMeta(methods, get, set)
        return {
            __index = function(self, key)
                local value = get and get(self, key)
                if value ~= nil then return value end
                if key == "getNode" then return function(target) return rawget(target, "_node") end end
                return methods[key]
            end,
            __newindex = function(self, key, value)
                if not (set and set(self, key, value)) then rawset(self, key, value) end
            end,
        }
    end
    return base
end

package.preload["urhox-libs/3D/Core/Vector3"] = function()
    return { new = function() return {} end }
end
package.preload["urhox-libs/3D/Core/Quaternion"] = function()
    return { new = function() return {} end }
end

local IslandInstancedMesh = require("IslandInstancedMesh")
local dayMaterial = { getNative = function() return "day-native" end }
local nightMaterial = { getNative = function() return "night-native" end }
local sharedModel = {}
local geometry = {}
local mesh = assert(IslandInstancedMesh.new(geometry, dayMaterial, 3, sharedModel))

assert(createdGroup.model == sharedModel and createdGroup.material == "day-native",
    "every island material batch must reuse the supplied native geometry model")
assert(#createdGroup.instanceNodes == 3 and mesh.count == 3,
    "the retained batch must create exactly one transform node per source block")

mesh:setMatrixAt(1, {
    decompose = function(_, position, rotation, scale)
        position.x, position.y, position.z = 1, 2, 3
        rotation.x, rotation.y, rotation.z, rotation.w = 0.1, 0.2, 0.3, 0.9
        scale.x, scale.y, scale.z = 4, 5, 6
    end,
})
local transformed = createdGroup.instanceNodes[2]
assert(transformed.position.x == 1 and transformed.position.y == 2 and transformed.position.z == 3,
    "instance matrices must preserve per-block positions")
assert(transformed.rotation.w == 0.9 and transformed.rotation.x == 0.1,
    "instance matrices must preserve three.js-to-native quaternion order")
assert(transformed.scale.x == 4 and transformed.scale.y == 5 and transformed.scale.z == 6,
    "instance matrices must preserve per-block scale")

mesh.material = nightMaterial
assert(createdGroup.material == "night-native",
    "night mode must hot-swap the material of a complete instanced batch")

assert(IslandInstancedMesh.new(geometry, dayMaterial, 2, nil) == nil,
    "missing native geometry must fail cleanly so IslandWorld can use its mesh fallback")

print("island-instanced-mesh tests passed")
