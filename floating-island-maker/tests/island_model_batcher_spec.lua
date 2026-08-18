package.path = "scripts/?.lua;" .. package.path

local function CopyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do result[index] = value end
    return result
end

local Attribute = {}
Attribute.__index = Attribute
function Attribute.new(array, itemSize)
    return setmetatable({ array = array or {}, itemSize = itemSize, count = #(array or {}) / itemSize }, Attribute)
end
function Attribute:getX(index) return self.array[index * self.itemSize + 1] end
function Attribute:getY(index) return self.array[index * self.itemSize + 2] end
function Attribute:getZ(index) return self.array[index * self.itemSize + 3] end

local Geometry = {}
Geometry.__index = Geometry
function Geometry.new(positions, normals, uvs)
    local self = setmetatable({ attributes = {}, disposeCount = 0 }, Geometry)
    if positions then self:setAttribute("position", Attribute.new(positions, 3)) end
    if normals then self:setAttribute("normal", Attribute.new(normals, 3)) end
    if uvs then self:setAttribute("uv", Attribute.new(uvs, 2)) end
    return self
end
function Geometry:setAttribute(name, attribute) self.attributes[name] = attribute; return self end
function Geometry:getAttribute(name) return self.attributes[name] end
function Geometry:getIndex() return nil end
function Geometry:clone()
    local result = Geometry.new()
    for name, attribute in pairs(self.attributes) do
        result:setAttribute(name, Attribute.new(CopyArray(attribute.array), attribute.itemSize))
    end
    return result
end
function Geometry:applyMatrix4(matrix)
    local position = self.attributes.position
    for index = 0, position.count - 1 do
        local base = index * 3
        position.array[base + 1] = position.array[base + 1] + (matrix.dx or 0)
        position.array[base + 2] = position.array[base + 2] + (matrix.dy or 0)
        position.array[base + 3] = position.array[base + 3] + (matrix.dz or 0)
    end
    return self
end
function Geometry:computeBoundingBox() return self end
function Geometry:computeBoundingSphere() return self end
function Geometry:dispose() self.disposeCount = self.disposeCount + 1 end

local THREE = {
    BufferGeometry = function() return Geometry.new() end,
    BufferAttribute = function(array, itemSize) return Attribute.new(array, itemSize) end,
}

local eventLog = {}
local GroupComponent = {}
GroupComponent.__index = GroupComponent
function GroupComponent.new(owner)
    return setmetatable({ owner = owner, nodes = {}, removeCalls = 0 }, GroupComponent)
end
function GroupComponent:AddInstanceNode(node)
    if self.failAddOnce then
        self.failAddOnce = false
        -- Model a native implementation that mutates its internal array and
        -- only then reports failure to Lua.
        self.nodes[#self.nodes + 1] = node
        error("injected native add failure")
    end
    self.nodes[#self.nodes + 1] = node
end
function GroupComponent:RemoveInstanceNode(node)
    eventLog[#eventLog + 1] = "remove-instance:" .. tostring(self.owner.name)
    self.removeCalls = self.removeCalls + 1
    if self.failRemoveOnce then
        self.failRemoveOnce = false
        error("injected native remove failure")
    end
    for index, candidate in ipairs(self.nodes) do
        if candidate == node then table.remove(self.nodes, index); return end
    end
end
function GroupComponent:RemoveAllInstanceNodes()
    self.removeAllCalls = (self.removeAllCalls or 0) + 1
    if self.failRemoveAllOnce then
        self.failRemoveAllOnce = false
        error("injected native clear failure")
    end
    self.nodes = {}
end
function GroupComponent:SetViewMask(value) self.viewMask = value end
function GroupComponent:SetCastShadows(value) self.castShadows = value end

local Node = {}
Node.__index = Node
function Node.new(name)
    return setmetatable({ name = name, children = {}, removed = false, position = { x = 0, y = 0, z = 0 } }, Node)
end
function Node:CreateChild(name)
    local child = Node.new(name)
    self.children[#self.children + 1] = child
    return child
end
function Node:CreateComponent(kind)
    assert(kind == "StaticModelGroup")
    self.component = GroupComponent.new(self)
    return self.component
end
function Node:Remove()
    eventLog[#eventLog + 1] = "remove-node:" .. tostring(self.name)
    self.removed = true
end
function Node:Dispose()
    eventLog[#eventLog + 1] = "dispose-node:" .. tostring(self.name)
    self.disposed = true
end

local rootNode = Node.new("BatchRoot")
local rootObject = { getNode = function() return rootNode end }
local geometryCalls, modelCalls = 0, 0
local triangle = Geometry.new(
    { 0, 0, 0, 1, 0, 0, 0, 1, 0 },
    { 0, 0, 1, 0, 0, 1, 0, 0, 1 },
    { 0, 0, 1, 0, 0, 1 }
)

local function Describe(block)
    return {
        materialId = block.materialId,
        color = block.color,
        emissionKind = block.emissionKind,
        transparent = block.transparent == true,
        castShadow = false,
    }
end

local IslandModelBatcher = require("IslandModelBatcher")
local batcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    geometryFor = function()
        geometryCalls = geometryCalls + 1
        return triangle
    end,
    blockMatrix = function(block) return { dx = block.x or 0, dy = block.y or 0, dz = block.z or 0 } end,
    describeBlock = Describe,
    materialFor = function(materialId, color) return "day:" .. materialId .. ":" .. color end,
    modelFor = function(geometry)
        modelCalls = modelCalls + 1
        return { geometry = geometry }
    end,
    nightMaterials = { lamp = "night:lamp" },
    viewMask = 7,
})

local asset = {
    assetId = "grass-detail",
    versionId = "1",
    blocks = {
        { shapeId = "box", materialId = "leaf", color = "#55AA33", x = 0 },
        { shapeId = "sphere", materialId = "leaf", color = "#55AA33", x = 10 },
        { shapeId = "cone", materialId = "leaf", color = "#225522", x = 20 },
        { shapeId = "sphere", materialId = "glow", color = "#FFCC55", emissionKind = "lamp", x = 30 },
    },
}

assert(batcher:IsEligible(asset), "a small opaque detail asset should be eligible")
local compiled = assert(batcher:Compile(asset))
assert(#compiled.parts == 3, "parts must split by material/colour/emission, not primitive shape")
assert(compiled.blockCount == 4 and compiled.hasNightEmission, "compiled metadata must preserve source count and emission")
assert(compiled.vertexCount == 12, "compiled metadata must expose real vertex cost for mobile budgeting")
assert(compiled.parts[1].vertexCount == 6, "different shapes sharing render state must bake into one geometry")
local bakedPositions = compiled.parts[1].geometry:getAttribute("position").array
assert(bakedPositions[1] == 0 and bakedPositions[10] == 10,
    "each source block local matrix must be applied before geometry is merged")
assert(geometryCalls == 4 and modelCalls == 3, "compile should build one native model per final part")
assert(batcher:Compile(asset) == compiled and geometryCalls == 4,
    "asset/version compilation must be cached")

local transparentAsset = {
    assetId = "transparent", versionId = "1",
    blocks = { { materialId = "glass", color = "#ffffff", transparent = true } },
}
assert(not batcher:IsEligible(transparentAsset), "transparent assets must retain their sorted render path")

local chunkBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    maxVertices = 6,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry) return { geometry = geometry } end,
})
local chunked = assert(chunkBatcher:Compile({
    assetId = "chunk-test", versionId = "1",
    blocks = {
        { materialId = "leaf", color = "#55aa33" },
        { materialId = "leaf", color = "#55aa33" },
        { materialId = "leaf", color = "#55aa33" },
    },
}))
assert(#chunked.parts == 2 and chunked.parts[1].vertexCount == 6 and chunked.parts[2].vertexCount == 3,
    "a material part must split on triangle boundaries before its vertex limit")
for _, part in ipairs(chunked.parts) do
    assert(part.vertexCount <= 6, "no compiled chunk may exceed its configured vertex limit")
end

local shardBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    maxInstancesPerGroup = 2,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry) return { geometry = geometry } end,
})

local function Instance(id, x, z)
    local native = Node.new("IslandInstance_" .. tostring(id))
    local object = {
        position = { x = x, y = 0, z = z },
        getNode = function() return native end,
    }
    return { id = id, x = x, z = z, root = object }, native
end


local shardA = Instance(201, 1, 1)
local shardB = Instance(202, 2, 1)
local shardC = Instance(203, 3, 1)
assert(shardBatcher:Register(shardA, asset))
assert(shardBatcher:Register(shardB, asset))
assert(shardBatcher:Register(shardC, asset))
assert(shardA._islandBatchMemberships[1].group == shardB._islandBatchMemberships[1].group,
    "a shard should accept instances up to its configured capacity")
assert(shardC._islandBatchMemberships[1].group.shard == 2
    and shardC._islandBatchMemberships[1].group ~= shardA._islandBatchMemberships[1].group,
    "an over-capacity cell/part must spill into a bounded second shard")
assert(shardC._islandBatchMemberships[1].group.name:find("_s2_") ~= nil,
    "group names must expose their shard for ray/debug diagnosis")

local first, firstNode = Instance(101, 2, 3)
local second, secondNode = Instance(102, 15.9, 4)
local unregistered = Instance(103, 1, 1)
local missingRefresh, missingReason = batcher:RefreshCell(unregistered)
assert(missingRefresh == nil and missingReason == "模型尚未注册到合批器",
    "RefreshCell must distinguish a broken registration from a valid same-cell no-op")
assert(batcher:Register(first, asset))
assert(batcher:Register(second, asset))
assert(first._islandBatched and first.batchedRenderPartCount == 3 and first.hasBatchedNightEmission,
    "Register must expose batching state on the logical instance")
assert(first.batchedVertexCount == compiled.vertexCount,
    "Register must expose compiled vertex cost without changing project data")
assert(#first._islandBatchMemberships == 3, "the same logical root must register once per compiled part")
for _, membership in ipairs(first._islandBatchMemberships) do
    assert(membership.node == firstNode and membership.group.component.nodes[1] == firstNode,
        "every part group must receive the original instance root node")
    assert(membership.group.component.viewMask == 7, "cell groups must preserve the scene view mask")
end

local firstGroup = first._islandBatchMemberships[1].group
assert(firstGroup == second._islandBatchMemberships[1].group,
    "placements inside the same 16 m cell must share a StaticModelGroup")
assert(batcher:ResolveRay(firstGroup.name, 0) == 101 and batcher:ResolveRay(firstGroup.name, 1) == 102,
    "ray subObject indices must resolve to logical model ids")
assert(batcher:ResolveRay({ drawable = firstGroup.component, subObject = 1 }) == 102,
    "ResolveRay must also accept a complete ray-query result")

assert(batcher:Unregister(first))
assert(first.batchedVertexCount == nil, "Unregister must clear transient batching metadata")
assert(firstGroup.component.removeCalls == 1 and #firstGroup.component.nodes == 1,
    "Unregister must first remove the instance node from every native group")
assert(batcher:ResolveRay(firstGroup.name, 0) == 102,
    "ray indices must stay aligned after an earlier instance is removed")
assert(not firstGroup.node.removed,
    "empty/reused groups must not be destroyed by normal LOD unregister operations")

second.x = 32.1
second.root.position.x = second.x
local formerGroupNode = firstGroup.node
assert(batcher:RefreshCell(second), "crossing a 16 m boundary must migrate all part memberships")
local migratedGroup = second._islandBatchMemberships[1].group
assert(migratedGroup ~= firstGroup and migratedGroup.cell.x == 2,
    "RefreshCell must move the logical root into the new spatial bucket")
assert(#firstGroup.instanceIds == 0 and formerGroupNode.removed,
    "cell migration must release abandoned empty groups instead of accumulating nodes")

local third = Instance(103, 35, 2)
assert(batcher:Register(third, asset))
assert(third._islandBatchMemberships[1].group == migratedGroup,
    "another placement in the migrated cell must reuse its existing group")

batcher:SetNightEnabled(true)
for _, membership in ipairs(second._islandBatchMemberships) do
    local expected = membership.part.emissionKind == "lamp" and "night:lamp" or membership.part.material
    assert(membership.group.component.material == expected,
        "night mode must only swap the emitted part material")
end
batcher:SetNightEnabled(false)
for _, membership in ipairs(second._islandBatchMemberships) do
    assert(membership.group.component.material == membership.part.material,
        "day mode must restore each compiled part's original material")
end

eventLog = {}
batcher:Clear()
assert(not second._islandBatched and not third._islandBatched,
    "Clear must release batching state from all live logical instances")
assert(next(batcher.groups) == nil and next(batcher.registrations) == nil,
    "Clear must remove every cached group and registration")
local firstRemoveInstance, firstRemoveNode
for index, event in ipairs(eventLog) do
    if not firstRemoveInstance and event:find("remove%-instance") then firstRemoveInstance = index end
    if not firstRemoveNode and event:find("remove%-node:IslandModelBatch") then firstRemoveNode = index end
end
assert(firstRemoveInstance and firstRemoveNode and firstRemoveInstance < firstRemoveNode,
    "native instance nodes must be detached before a group owner is destroyed")

-- LOD removals retain a short reuse window, then release their native owner.
-- A hard empty-group ceiling still prevents rapid camera travel from growing
-- the scene tree without bound before the delay expires.
local fakeNow = 0
local disposedModels = 0
local reclaimBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    now = function() return fakeNow end,
    sweepIntervalSeconds = 0,
    emptyGroupIdleSeconds = 5,
    maxEmptyGroups = 2,
    maxCompiledAssets = 2,
    compiledIdleSeconds = 50,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry)
        return { geometry = geometry, Dispose = function() disposedModels = disposedModels + 1 end }
    end,
    ownsModels = true,
})
local detailAsset = {
    assetId = "reclaim-detail", versionId = "1",
    blocks = { { materialId = "leaf", color = "#55aa33" } },
}
local reusable = Instance(301, 1, 1)
assert(reclaimBatcher:Register(reusable, detailAsset))
local reusableGroup = reusable._islandBatchMemberships[1].group
local reusableGroupNode = reusableGroup.node
assert(reclaimBatcher:Unregister(reusable))
assert(not reusableGroupNode.removed and reclaimBatcher:GetStats().emptyGroups == 1,
    "a normal LOD removal must retain its empty group during the reuse delay")
fakeNow = 3
assert(reclaimBatcher:Register(reusable, detailAsset))
assert(reusable._islandBatchMemberships[1].group == reusableGroup,
    "camera return inside the delay must reuse the original native group")
assert(reclaimBatcher:Unregister(reusable))
fakeNow = 9
reclaimBatcher:Sweep()
assert(reusableGroupNode.removed and reclaimBatcher:GetStats().emptyGroups == 0,
    "an idle empty group must be reclaimed after its delay")

local boundedGroupNodes = {}
for index, x in ipairs({ 1, 20, 40 }) do
    local item = Instance(310 + index, x, 1)
    assert(reclaimBatcher:Register(item, detailAsset))
    boundedGroupNodes[#boundedGroupNodes + 1] = item._islandBatchMemberships[1].group.node
    assert(reclaimBatcher:Unregister(item))
end
local boundedStats = reclaimBatcher:GetStats()
assert(boundedStats.emptyGroups == 2 and boundedStats.groups == 2,
    "each empty native group must be counted once while enforcing the configured hard ceiling")
local removedForPressure = 0
for _, node in ipairs(boundedGroupNodes) do
    if node.removed then removedForPressure = removedForPressure + 1 end
end
assert(removedForPressure == 1,
    "cache pressure must evict exactly the one oldest group above the hard ceiling")

-- If the native backend rejects a targeted unlink, rebuild the native member
-- array from Lua truth before releasing the target instance.
local recoveryBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry) return { geometry = geometry } end,
})
local recoveryAsset = {
    assetId = "unlink-recovery", versionId = "1",
    blocks = { { materialId = "leaf", color = "#55aa33" } },
}
local recoveryFirst, recoverySecond = Instance(360, 2, 2), Instance(361, 3, 2)
assert(recoveryBatcher:Register(recoveryFirst, recoveryAsset))
assert(recoveryBatcher:Register(recoverySecond, recoveryAsset))
local recoveryGroup = recoveryFirst._islandBatchMemberships[1].group
recoveryGroup.component.failRemoveOnce = true
assert(recoveryBatcher:Unregister(recoveryFirst))
assert((recoveryGroup.component.removeAllCalls or 0) == 1
    and #recoveryGroup.component.nodes == 1
    and recoveryGroup.component.nodes[1] == recoverySecond.root:getNode()
    and #recoveryGroup.instanceIds == 1 and recoveryGroup.instanceIds[1] == recoverySecond.id,
    "failed targeted unlink must clear and rebuild native membership without a stale pointer")
assert(recoverySecond._islandBatchedCompiled.refCount == 1,
    "unlink recovery must preserve the surviving compiled-model reference")

-- Registration can fail after a native group appended the attempted root but
-- before Lua recorded it. Both that current group and earlier parts must be
-- rebuilt from the surviving logical membership.
local rollbackBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry) return { geometry = geometry } end,
})
local rollbackAsset = {
    assetId = "register-rollback", versionId = "1",
    blocks = {
        { materialId = "leaf", color = "#55aa33" },
        { materialId = "leaf", color = "#77cc55" },
    },
}
local rollbackSeed, rollbackSeedNode = Instance(370, 2, 2)
assert(rollbackBatcher:Register(rollbackSeed, rollbackAsset))
local rollbackFirstGroup = rollbackSeed._islandBatchMemberships[1].group
local rollbackSecondGroup = rollbackSeed._islandBatchMemberships[2].group
rollbackFirstGroup.component.failRemoveOnce = true
rollbackSecondGroup.component.failAddOnce = true
local rollbackAttempt, rollbackAttemptNode = Instance(371, 3, 2)
local registered, rollbackError = rollbackBatcher:Register(rollbackAttempt, rollbackAsset)
assert(not registered and tostring(rollbackError):find("injected native add failure", 1, true),
    "a later-part native add failure must abort registration")
for _, group in ipairs({ rollbackFirstGroup, rollbackSecondGroup }) do
    assert(#group.component.nodes == 1 and group.component.nodes[1] == rollbackSeedNode
        and #group.instanceIds == 1 and group.instanceIds[1] == rollbackSeed.id,
        "failed partial registration must remove its untracked native pointer and keep the seed")
    for _, node in ipairs(group.component.nodes) do
        assert(node ~= rollbackAttemptNode,
            "a native add that mutated before throwing must not retain the attempted root")
    end
end
assert((rollbackFirstGroup.component.removeAllCalls or 0) >= 1
    and (rollbackSecondGroup.component.removeAllCalls or 0) >= 1,
    "both earlier rollback and current failed-add groups must rebuild from Lua membership")
assert(rollbackBatcher:GetStats().registrations == 1
    and rollbackSeed._islandBatchedCompiled.refCount == 1
    and not rollbackAttempt._islandBatched,
    "failed registration must preserve only the existing logical registration")

-- If even RemoveAll fails while destroying an idle group, prefer the native
-- owner's immediate Dispose path instead of leaving its component alive until
-- a deferred scene-tree removal.
local disposalFallbackBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry) return { geometry = geometry } end,
})
local disposalInstance = Instance(380, 2, 2)
assert(disposalFallbackBatcher:Register(disposalInstance, recoveryAsset))
local disposalGroup = disposalInstance._islandBatchMemberships[1].group
local disposalNode = disposalGroup.node
assert(disposalFallbackBatcher:Unregister(disposalInstance))
disposalGroup.component.failRemoveAllOnce = true
disposalFallbackBatcher:Sweep({ force = true })
assert(disposalNode.disposed and not disposalNode.removed,
    "failed native RemoveAll must immediately dispose the group owner node")

-- A failure after earlier parts were compiled must release both the completed
-- model and the current in-progress geometry immediately.
local failedGeometry, failedModelDisposals, failedModelCalls = {}, 0, 0
local failureBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry)
        failedModelCalls = failedModelCalls + 1
        failedGeometry[#failedGeometry + 1] = geometry
        if failedModelCalls == 2 then error("injected model conversion failure") end
        return { geometry = geometry, Dispose = function()
            failedModelDisposals = failedModelDisposals + 1
        end }
    end,
    ownsModels = true,
})
local failedCompile, failedCompileError = failureBatcher:Compile({
    assetId = "partial-compile", versionId = "1",
    blocks = {
        { materialId = "leaf", color = "#55aa33" },
        { materialId = "leaf", color = "#77cc55" },
    },
})
assert(failedCompile == nil and tostring(failedCompileError):find("injected model conversion failure", 1, true),
    "injected native model conversion failure must be reported")
assert(failedModelDisposals == 1 and #failedGeometry == 2
    and failedGeometry[1].disposeCount == 1 and failedGeometry[2].disposeCount == 1
    and failureBatcher:GetStats().compiledAssets == 0,
    "partial compilation failure must dispose every completed and in-progress native resource")

-- Compiled geometry is LRU-bounded, but a live registration is never evicted.
local cacheBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    now = function() return fakeNow end,
    sweepIntervalSeconds = 0,
    maxCompiledAssets = 1,
    compiledIdleSeconds = 100,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry)
        return { geometry = geometry, Dispose = function() disposedModels = disposedModels + 1 end }
    end,
    ownsModels = true,
})
local cacheAssetA = {
    assetId = "cache-a", versionId = "1",
    blocks = { { materialId = "leaf", color = "#55aa33" } },
}
local cacheAssetB = {
    assetId = "cache-b", versionId = "1",
    blocks = { { materialId = "leaf", color = "#66bb44" } },
}
local activeCacheInstance = Instance(401, 2, 2)
local secondActiveCacheInstance = Instance(402, 3, 2)
assert(cacheBatcher:Register(activeCacheInstance, cacheAssetA))
assert(cacheBatcher:Register(secondActiveCacheInstance, cacheAssetA))
local activeCompiled = activeCacheInstance._islandBatchedCompiled
assert(activeCompiled.refCount == 2,
    "compiled refcounts must include every live registration sharing the cached model")
assert(cacheBatcher:Compile(cacheAssetB))
assert(cacheBatcher:GetStats().compiledAssets == 2,
    "a live compiled model must survive temporary pressure from a newly compiled asset")
assert(cacheBatcher:Unregister(activeCacheInstance, false))
cacheBatcher:Sweep(true)
assert(activeCompiled.refCount == 1 and cacheBatcher.compiled[activeCompiled.cacheKey] == activeCompiled,
    "an explicit cache sweep must not release a compiled model with a live registration")
assert(cacheBatcher:Unregister(secondActiveCacheInstance, false))
cacheBatcher:Sweep(true)
assert(cacheBatcher:GetStats().compiledAssets == 0,
    "once its final registration leaves, a forced sweep may release the compiled model")
assert(disposedModels >= 1, "evicted owned native models must be explicitly disposed")

-- Cache hits update recency: with room for two inactive assets, adding a third
-- must evict the untouched middle entry rather than the recently reused first.
local lruBatcher = IslandModelBatcher.new({
    root = rootObject,
    three = THREE,
    now = function() return fakeNow end,
    sweepIntervalSeconds = 0,
    maxCompiledAssets = 2,
    compiledIdleSeconds = 100,
    geometryFor = function() return triangle end,
    describeBlock = Describe,
    materialFor = function() return "day" end,
    modelFor = function(geometry)
        return { geometry = geometry, Dispose = function() disposedModels = disposedModels + 1 end }
    end,
    ownsModels = true,
})
local function LruAsset(id, color)
    return {
        assetId = id, versionId = "1",
        blocks = { { materialId = "leaf", color = color } },
    }
end
local lruA = LruAsset("lru-a", "#335511")
local lruB = LruAsset("lru-b", "#446622")
local lruC = LruAsset("lru-c", "#557733")
fakeNow = 20
local compiledLruA = assert(lruBatcher:Compile(lruA))
fakeNow = 21
local compiledLruB = assert(lruBatcher:Compile(lruB))
fakeNow = 22
assert(lruBatcher:Compile(lruA) == compiledLruA)
fakeNow = 23
local compiledLruC = assert(lruBatcher:Compile(lruC))
assert(lruBatcher.compiled[compiledLruA.cacheKey] == compiledLruA
    and lruBatcher.compiled[compiledLruC.cacheKey] == compiledLruC
    and lruBatcher.compiled[compiledLruB.cacheKey] == nil and compiledLruB.disposed,
    "LRU pressure must preserve the recently touched asset and evict the oldest inactive one")

batcher:Dispose()
chunkBatcher:Dispose()
shardBatcher:Dispose()
reclaimBatcher:Dispose()
cacheBatcher:Dispose()
lruBatcher:Dispose()
recoveryBatcher:Dispose()
rollbackBatcher:Dispose()
disposalFallbackBatcher:Dispose()
failureBatcher:Dispose()
for _, part in ipairs(compiled.parts) do
    assert(part.geometry == nil and part.model == nil, "Dispose must release compiled geometry/model references")
end

print("island-model-batcher tests passed")
