---@diagnostic disable: undefined-global

-- Cross-model batching for small, immutable island details.
--
-- Compile() first bakes every block's local transform into CPU geometry. Blocks
-- with the same material, colour and night-emission state share one geometry
-- part even when they use different primitive shapes. Register() then puts all
-- placements of the same compiled part inside a 16 m cell into one
-- StaticModelGroup. The logical instance root remains the instance transform,
-- so moving, rotating, scaling, picking and deleting a whole model still work.
--
-- All engine-facing constructors are injectable. Tests can therefore exercise
-- compilation, cell migration and ray-index bookkeeping without UrhoX.

local IslandModelBatcher = {}
IslandModelBatcher.__index = IslandModelBatcher

local DEFAULT_CELL_SIZE = 16
local HARD_VERTEX_LIMIT = 48000
local DEFAULT_MAX_EMPTY_GROUPS = 96
local DEFAULT_EMPTY_GROUP_IDLE_SECONDS = 3.0
local DEFAULT_MAX_COMPILED_ASSETS = 64
local DEFAULT_MAX_COMPILED_VERTICES = 1500000
local DEFAULT_COMPILED_IDLE_SECONDS = 45.0
local DEFAULT_SWEEP_INTERVAL_SECONDS = 0.5
local KEY_SEPARATOR = "\31"

local function NormalizeColor(value)
    return tostring(value or "#f2e7cf"):lower():gsub("%s+", "")
end

local function NativeNode(value)
    if not value then return nil end
    if type(value) == "table" and value.getNode then return value:getNode() end
    return value
end

local function NativeMaterial(value)
    if not value then return nil end
    if type(value) == "table" and value.getNative then return value:getNative() end
    return value
end

local function AttributeFor(geometry, name)
    if not geometry then return nil end
    if geometry.getAttribute then
        local ok, value = pcall(geometry.getAttribute, geometry, name)
        if ok and value then return value end
    end
    local attributes = geometry.attributes
    if type(attributes) == "table" then return attributes[name] end
    return rawget(geometry, "_attributes") and rawget(geometry, "_attributes")[name] or nil
end

local function AttributeItemSize(attribute, fallback)
    if not attribute then return fallback end
    return math.max(1, math.floor(tonumber(attribute.itemSize or rawget(attribute, "itemSize")) or fallback))
end

local function AttributeCount(attribute)
    if not attribute then return 0 end
    local count = tonumber(attribute.count)
    if count then return math.max(0, math.floor(count)) end
    local array = attribute.array or rawget(attribute, "array") or {}
    return math.floor(#array / AttributeItemSize(attribute, 3))
end

local function AttributeComponent(attribute, vertexIndex, component)
    if not attribute then return nil end
    local array = attribute.array or rawget(attribute, "array")
    if array then
        return array[vertexIndex * AttributeItemSize(attribute, 3) + component + 1]
    end
    if attribute.getComponent then return attribute:getComponent(vertexIndex, component) end
    if component == 0 and attribute.getX then return attribute:getX(vertexIndex) end
    if component == 1 and attribute.getY then return attribute:getY(vertexIndex) end
    if component == 2 and attribute.getZ then return attribute:getZ(vertexIndex) end
    if component == 3 and attribute.getW then return attribute:getW(vertexIndex) end
    return nil
end

local function AppendVertex(target, attribute, vertexIndex, itemSize, defaults)
    for component = 0, itemSize - 1 do
        local value = AttributeComponent(attribute, vertexIndex, component)
        if value == nil then value = defaults[component + 1] or 0 end
        target[#target + 1] = value
    end
end

local function ExtractTriangleData(geometry)
    local position = AttributeFor(geometry, "position")
    local count = AttributeCount(position)
    if count == 0 then return nil, "几何没有 position 顶点" end
    if count % 3 ~= 0 then
        return nil, "预烘焙只接受三角形列表，顶点数必须是 3 的倍数"
    end
    local normal, uv = AttributeFor(geometry, "normal"), AttributeFor(geometry, "uv")
    local data = { position = {}, normal = {}, uv = {}, vertexCount = count }
    for index = 0, count - 1 do
        AppendVertex(data.position, position, index, 3, { 0, 0, 0 })
        AppendVertex(data.normal, normal, index, 3, { 0, 1, 0 })
        AppendVertex(data.uv, uv, index, 2, { 0, 0 })
    end
    return data
end

-- Build-once geometries emit directly to CustomGeometry and have no CPU-side
-- attributes. This collector presents the tiny subset of CustomGeometry that
-- those recipes use, recovering a regular BufferGeometry without a native GPU
-- upload. It also supports the transformable geometry proxy used by the local
-- three.js compatibility layer.
local function CollectBuildOnceGeometry(geometry, three)
    local data = { position = {}, normal = {}, uv = {} }
    local collector = {}
    function collector:BeginGeometry() end
    function collector:SetNumGeometries() end
    function collector:DefineVertex(value)
        data.position[#data.position + 1] = tonumber(value and value.x) or 0
        data.position[#data.position + 1] = tonumber(value and value.y) or 0
        data.position[#data.position + 1] = tonumber(value and value.z) or 0
    end
    function collector:DefineNormal(value)
        data.normal[#data.normal + 1] = tonumber(value and value.x) or 0
        data.normal[#data.normal + 1] = tonumber(value and value.y) or 1
        data.normal[#data.normal + 1] = tonumber(value and value.z) or 0
    end
    function collector:DefineTexCoord(value)
        data.uv[#data.uv + 1] = tonumber(value and value.x) or 0
        data.uv[#data.uv + 1] = tonumber(value and value.y) or 0
    end
    function collector:Commit() end
    function collector:SetMaterial() end

    local collectorNode = {}
    function collectorNode:CreateComponent(kind)
        if kind ~= "CustomGeometry" then error("预烘焙仅支持 CustomGeometry") end
        return collector
    end
    geometry:build(collectorNode, nil)

    local vertexCount = math.floor(#data.position / 3)
    if vertexCount == 0 then return nil, "build-once 几何没有输出顶点" end
    while #data.normal < vertexCount * 3 do
        data.normal[#data.normal + 1] = (#data.normal % 3 == 1) and 1 or 0
    end
    while #data.uv < vertexCount * 2 do data.uv[#data.uv + 1] = 0 end

    local result = three.BufferGeometry()
    result:setAttribute("position", three.BufferAttribute(data.position, 3))
    result:setAttribute("normal", three.BufferAttribute(data.normal, 3))
    result:setAttribute("uv", three.BufferAttribute(data.uv, 2))
    return result
end

local function NewChunk()
    return { position = {}, normal = {}, uv = {}, vertexCount = 0 }
end

local function AppendRange(chunk, data, firstVertex, count)
    local function Append(source, target, itemSize)
        local first = firstVertex * itemSize + 1
        local last = (firstVertex + count) * itemSize
        for index = first, last do target[#target + 1] = source[index] end
    end
    Append(data.position, chunk.position, 3)
    Append(data.normal, chunk.normal, 3)
    Append(data.uv, chunk.uv, 2)
    chunk.vertexCount = chunk.vertexCount + count
end

local function AddPieceToBucket(bucket, data, maxVertices)
    local sourceOffset = 0
    while sourceOffset < data.vertexCount do
        local chunk = bucket.chunks[#bucket.chunks]
        if not chunk or chunk.vertexCount >= maxVertices then
            chunk = NewChunk()
            bucket.chunks[#bucket.chunks + 1] = chunk
        end
        local capacity = maxVertices - chunk.vertexCount
        capacity = capacity - capacity % 3
        if capacity < 3 then
            chunk = NewChunk()
            bucket.chunks[#bucket.chunks + 1] = chunk
            capacity = maxVertices
        end
        local count = math.min(capacity, data.vertexCount - sourceOffset)
        count = count - count % 3
        if count <= 0 then error("无法在顶点上限内切分三角形") end
        AppendRange(chunk, data, sourceOffset, count)
        sourceOffset = sourceOffset + count
    end
end

local function InstanceId(instance)
    if type(instance) ~= "table" then return instance end
    return instance.id or instance.instanceId
end

local function RegistrationKey(instance)
    local id = InstanceId(instance)
    return id ~= nil and tostring(id) or nil
end

local function InstancePosition(instance)
    local root = type(instance) == "table" and instance.root or nil
    local position = root and root.position or nil
    local node = NativeNode(root)
    local nativePosition = node and node.position or nil
    local x = tonumber(type(instance) == "table" and instance.x)
        or tonumber(position and position.x) or tonumber(nativePosition and nativePosition.x) or 0
    local z = tonumber(type(instance) == "table" and instance.z)
        or tonumber(position and position.z) or tonumber(nativePosition and nativePosition.z) or 0
    return x, z
end

local function CellCoordinate(value, cellSize)
    return math.floor((tonumber(value) or 0) / cellSize)
end

local function CellKey(x, z)
    return tostring(x) .. ":" .. tostring(z)
end

local function AssetCacheKey(asset)
    local id = asset and (asset.assetId or asset.id or asset.name) or "asset"
    local version = asset and (asset.versionId or asset.version or asset.updatedAt) or "latest"
    return tostring(id) .. "@" .. tostring(version)
end

local function DefaultDescription(block)
    return {
        materialId = tostring(block.materialId or block.material or "solid"),
        color = NormalizeColor(block.color),
        emissionKind = block.emissionKind,
        transparent = block.transparent == true,
        castShadow = block.castShadow == true,
    }
end

function IslandModelBatcher.new(options)
    options = options or {}
    local self = setmetatable({}, IslandModelBatcher)
    self.options = options
    self.three = options.three or options.THREE
    if not self.three then self.three = require("urhox-libs/3D") end
    self.root = options.root
    self.geometryFor = assert(options.geometryFor, "IslandModelBatcher 需要 geometryFor")
    self.materialFor = assert(options.materialFor, "IslandModelBatcher 需要 materialFor")
    self.modelFor = options.modelFor
    if not self.modelFor then
        local GeometryToModel = require("urhox-libs/3D/Core/GeometryToModel")
        self.modelFor = function(geometry) return GeometryToModel.toModel(geometry) end
        self.ownsModels = true
    else
        self.ownsModels = options.ownsModels == true
    end
    self.describeBlock = options.describeBlock
    self.partKey = options.partKey
    self.blockMatrix = options.blockMatrix
    self.isEligible = options.isEligible
    self.assetCacheKey = options.assetCacheKey or AssetCacheKey
    self.bakeGeometry = options.bakeGeometry
    self.createGroup = options.createGroup
    self.destroyGroup = options.destroyGroup
    self.disposeModel = options.disposeModel
    self.nightMaterials = options.nightMaterials or {}
    if options.nightWindowMaterial then self.nightMaterials.window = options.nightWindowMaterial end
    if options.nightLampMaterial then self.nightMaterials.lamp = options.nightLampMaterial end
    self.nightMaterialFor = options.nightMaterialFor
    self.viewMask = options.viewMask
    self.cellSize = math.max(1, tonumber(options.cellSize) or DEFAULT_CELL_SIZE)
    local requestedLimit = math.floor(tonumber(options.maxVertices) or HARD_VERTEX_LIMIT)
    requestedLimit = math.min(HARD_VERTEX_LIMIT, math.max(3, requestedLimit))
    self.maxVertices = requestedLimit - requestedLimit % 3
    self.maxBlocksPerAsset = math.max(1, math.floor(tonumber(options.maxBlocksPerAsset) or 48))
    self.maxInstancesPerGroup = math.max(1, math.floor(tonumber(options.maxInstancesPerGroup) or 96))
    self.maxEmptyGroups = math.max(0,
        math.floor(tonumber(options.maxEmptyGroups) or DEFAULT_MAX_EMPTY_GROUPS))
    self.emptyGroupIdleSeconds = math.max(0,
        tonumber(options.emptyGroupIdleSeconds) or DEFAULT_EMPTY_GROUP_IDLE_SECONDS)
    self.maxCompiledAssets = math.max(1,
        math.floor(tonumber(options.maxCompiledAssets) or DEFAULT_MAX_COMPILED_ASSETS))
    self.maxCompiledVertices = math.max(HARD_VERTEX_LIMIT,
        math.floor(tonumber(options.maxCompiledVertices) or DEFAULT_MAX_COMPILED_VERTICES))
    self.compiledIdleSeconds = math.max(0,
        tonumber(options.compiledIdleSeconds) or DEFAULT_COMPILED_IDLE_SECONDS)
    self.sweepIntervalSeconds = math.max(0,
        tonumber(options.sweepIntervalSeconds) or DEFAULT_SWEEP_INTERVAL_SECONDS)
    self.now = type(options.now) == "function" and options.now or os.clock
    self.compiled = {}
    self.compiledCount = 0
    self.compiledVertexCount = 0
    self.groups = {}
    self.groupsByNodeName = {}
    self.groupsByDrawable = {}
    self.cells = {}
    self.registrations = {}
    self.emptyGroupCount = 0
    self.nightEnabled = false
    self.nextGroupSerial = 1
    self.lastSweepAt = -math.huge
    self.disposed = false
    return self
end

function IslandModelBatcher:Now()
    local ok, value = pcall(self.now)
    if not ok then return 0 end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return 0 end
    return value
end

function IslandModelBatcher:TouchCompiled(compiled)
    if compiled then compiled.lastUsedAt = self:Now() end
end

function IslandModelBatcher:TouchGroup(group)
    if not group then return end
    group.lastUsedAt = self:Now()
    if group.emptySince ~= nil then
        group.emptySince = nil
        self.emptyGroupCount = math.max(0, self.emptyGroupCount - 1)
    end
end

function IslandModelBatcher:MarkGroupEmpty(group)
    if not group or group.emptySince ~= nil then return end
    local now = self:Now()
    group.emptySince = now
    group.lastUsedAt = now
    self.emptyGroupCount = self.emptyGroupCount + 1
end

local function DisposePartResources(self, part)
    if not part then return end
    if part.ownsModel and part.model then
        if self.disposeModel then pcall(self.disposeModel, part.model)
        elseif part.model.Dispose then pcall(part.model.Dispose, part.model) end
    end
    if part.geometry and part.geometry.dispose then pcall(part.geometry.dispose, part.geometry) end
    part.model, part.geometry = nil, nil
end

function IslandModelBatcher:DescribeBlock(block, asset)
    local description = self.describeBlock and self.describeBlock(block, asset) or nil
    if type(description) ~= "table" then description = DefaultDescription(block) end
    description.materialId = tostring(description.materialId or block.materialId or block.material or "solid")
    description.color = NormalizeColor(description.color or block.color)
    if description.emissionKind == nil then description.emissionKind = block.emissionKind end
    if description.transparent == nil then description.transparent = block.transparent == true end
    if description.castShadow == nil then description.castShadow = block.castShadow == true end
    return description
end

function IslandModelBatcher:IsEligible(asset)
    if self.disposed or type(asset) ~= "table" then return false end
    if self.isEligible then return self.isEligible(asset) == true end
    local blocks = asset.blocks or {}
    if #blocks == 0 or #blocks > self.maxBlocksPerAsset then return false end
    for _, block in ipairs(blocks) do
        local description = self:DescribeBlock(block, asset)
        if description.transparent or description.eligible == false then return false end
    end
    return true
end

function IslandModelBatcher:PartKey(block, description, asset)
    if self.partKey then
        local key = self.partKey(block, description, asset)
        if key ~= nil then return tostring(key) end
    end
    return table.concat({
        description.materialId,
        description.color,
        tostring(description.emissionKind or "none"),
        description.castShadow and "shadow" or "plain",
    }, KEY_SEPARATOR)
end

function IslandModelBatcher:BakeBlock(block, asset)
    local sourceGeometry = self.geometryFor(block, asset)
    if not sourceGeometry then return nil, "找不到积木几何" end
    local matrix = self.blockMatrix and self.blockMatrix(block, asset) or nil
    if self.bakeGeometry then
        local baked, errorMessage = self.bakeGeometry(block, sourceGeometry, matrix, asset)
        if not baked then return nil, errorMessage or "自定义几何预烘焙失败" end
        if baked.position and baked.vertexCount then return baked end
        sourceGeometry = baked
    end

    local geometry
    local ownsTemporaryGeometry = false
    if AttributeFor(sourceGeometry, "position") then
        if not sourceGeometry.clone then return nil, "CPU 几何缺少 clone" end
        geometry = sourceGeometry:clone()
        ownsTemporaryGeometry = true
        local index = geometry.getIndex and geometry:getIndex() or geometry.index
        if index and geometry.toNonIndexed then
            local indexedGeometry = geometry
            geometry = geometry:toNonIndexed()
            if geometry ~= indexedGeometry and indexedGeometry.dispose then
                pcall(indexedGeometry.dispose, indexedGeometry)
            end
        end
    elseif sourceGeometry.build then
        local collected, errorMessage = CollectBuildOnceGeometry(sourceGeometry, self.three)
        if not collected then return nil, errorMessage end
        geometry = collected
        ownsTemporaryGeometry = true
    else
        return nil, "几何既没有 CPU attributes，也没有 build 方法"
    end

    if matrix then
        if not geometry.applyMatrix4 then
            if ownsTemporaryGeometry and geometry.dispose then pcall(geometry.dispose, geometry) end
            return nil, "几何缺少 applyMatrix4"
        end
        geometry:applyMatrix4(matrix)
    end
    local data, errorMessage = ExtractTriangleData(geometry)
    if ownsTemporaryGeometry and geometry.dispose then pcall(geometry.dispose, geometry) end
    return data, errorMessage
end

function IslandModelBatcher:Compile(asset)
    if not self:IsEligible(asset) then return nil, "模型不符合小模型合批条件" end
    local cacheKey = tostring(self.assetCacheKey(asset))
    local cached = self.compiled[cacheKey]
    if cached then
        self:TouchCompiled(cached)
        self:MaybeSweep(false, cacheKey)
        return cached
    end

    local compiled = {
        asset = asset,
        cacheKey = cacheKey,
        parts = {},
        blockCount = #(asset.blocks or {}),
        vertexCount = 0,
        hasNightEmission = false,
        refCount = 0,
        lastUsedAt = self:Now(),
    }
    local pendingPart = nil
    local ok, result = pcall(function()
        local buckets, orderedBuckets = {}, {}
        for _, block in ipairs(asset.blocks or {}) do
            local description = self:DescribeBlock(block, asset)
            if description.transparent then error("透明积木不能进入 StaticModelGroup 预烘焙") end
            local key = self:PartKey(block, description, asset)
            local bucket = buckets[key]
            if not bucket then
                bucket = { key = key, description = description, chunks = {}, blockCount = 0 }
                buckets[key] = bucket
                orderedBuckets[#orderedBuckets + 1] = bucket
            end
            local data, errorMessage = self:BakeBlock(block, asset)
            if not data then error(errorMessage) end
            AddPieceToBucket(bucket, data, self.maxVertices)
            bucket.blockCount = bucket.blockCount + 1
        end

        for _, bucket in ipairs(orderedBuckets) do
            local description = bucket.description
            local material = self.materialFor(
                description.materialId, description.color, description.emissionKind, description, asset)
            if not material then error("找不到合批材质：" .. tostring(description.materialId)) end
            for chunkIndex, chunk in ipairs(bucket.chunks) do
                local geometry = self.three.BufferGeometry()
                pendingPart = {
                    geometry = geometry,
                    model = nil,
                    ownsModel = self.ownsModels,
                }
                geometry:setAttribute("position", self.three.BufferAttribute(chunk.position, 3))
                geometry:setAttribute("normal", self.three.BufferAttribute(chunk.normal, 3))
                geometry:setAttribute("uv", self.three.BufferAttribute(chunk.uv, 2))
                if geometry.computeBoundingBox then geometry:computeBoundingBox() end
                if geometry.computeBoundingSphere then geometry:computeBoundingSphere() end
                local model = self.modelFor(geometry, description, asset)
                pendingPart.model = model
                if not model then error("合并几何无法转换为原生 Model") end
                local part = {
                    key = bucket.key,
                    id = bucket.key .. KEY_SEPARATOR .. tostring(chunkIndex),
                    chunkIndex = chunkIndex,
                    geometry = geometry,
                    model = model,
                    material = material,
                    materialId = description.materialId,
                    color = description.color,
                    emissionKind = description.emissionKind,
                    castShadow = description.castShadow == true,
                    vertexCount = chunk.vertexCount,
                    blockCount = bucket.blockCount,
                    ownsModel = self.ownsModels,
                }
                compiled.parts[#compiled.parts + 1] = part
                pendingPart = nil
                compiled.vertexCount = compiled.vertexCount + part.vertexCount
                if part.emissionKind then compiled.hasNightEmission = true end
            end
        end
        return compiled
    end)

    if not ok then
        DisposePartResources(self, pendingPart)
        for _, part in ipairs(compiled.parts) do DisposePartResources(self, part) end
        compiled.parts = {}
        return nil, tostring(result)
    end
    self.compiled[cacheKey] = result
    self.compiledCount = self.compiledCount + 1
    self.compiledVertexCount = self.compiledVertexCount + (tonumber(result.vertexCount) or 0)
    -- The newly compiled asset is protected until Register has had a chance to
    -- attach its first live instance. Older inactive entries absorb any cache
    -- pressure first.
    self:MaybeSweep(false, cacheKey)
    return result
end

function IslandModelBatcher:DisposeCompiled(compiled)
    if not compiled or compiled.disposed == true
        or (tonumber(compiled.refCount) or 0) > 0 then return false end

    -- Empty groups still retain the native Model. Destroy those owners before
    -- releasing the model itself. A live group is a defensive veto even if a
    -- bookkeeping bug left refCount at zero.
    local groups = {}
    for _, group in pairs(self.groups) do
        if group.compiled == compiled then
            if #(group.instanceIds or {}) > 0 then return false end
            groups[#groups + 1] = group
        end
    end
    for _, group in ipairs(groups) do self:DestroyRenderGroup(group) end

    if self.compiled[compiled.cacheKey] == compiled then
        self.compiled[compiled.cacheKey] = nil
        self.compiledCount = math.max(0, self.compiledCount - 1)
        self.compiledVertexCount = math.max(0,
            self.compiledVertexCount - (tonumber(compiled.vertexCount) or 0))
    end
    for _, part in ipairs(compiled.parts or {}) do DisposePartResources(self, part) end
    -- Keep the immutable part metadata table intact for callers that retained
    -- the value returned by Compile; only its native/geometry resources expire.
    compiled.disposed = true
    return true
end

---Reclaim idle native groups and compiled models.
---Normal calls preserve a short reuse window. `force=true` removes every
---inactive entry and is intended for explicit memory-pressure handling.
---@param options table|boolean|nil
---@return table stats
function IslandModelBatcher:Sweep(options)
    if self.disposed then return self:GetStats() end
    if type(options) == "boolean" then options = { force = options } end
    options = options or {}
    local force = options.force == true
    local protectCacheKey = options.protectCacheKey
    local now = self:Now()
    self.lastSweepAt = now

    local empty = {}
    for _, group in pairs(self.groups) do
        if #(group.instanceIds or {}) == 0 then
            if group.emptySince == nil then self:MarkGroupEmpty(group) end
            empty[#empty + 1] = group
        end
    end
    table.sort(empty, function(first, second)
        local firstTime = tonumber(first.emptySince or first.lastUsedAt) or 0
        local secondTime = tonumber(second.emptySince or second.lastUsedAt) or 0
        if firstTime ~= secondTime then return firstTime < secondTime end
        return tostring(first.key) < tostring(second.key)
    end)
    local overEmptyLimit = math.max(0, #empty - self.maxEmptyGroups)
    for _, group in ipairs(empty) do
        local idle = now - (tonumber(group.emptySince) or now)
        if force or overEmptyLimit > 0 or idle >= self.emptyGroupIdleSeconds then
            self:DestroyRenderGroup(group)
            if overEmptyLimit > 0 then overEmptyLimit = overEmptyLimit - 1 end
        end
    end

    local inactive = {}
    for _, compiled in pairs(self.compiled) do
        if (tonumber(compiled.refCount) or 0) <= 0 and compiled.cacheKey ~= protectCacheKey then
            inactive[#inactive + 1] = compiled
        end
    end
    table.sort(inactive, function(first, second)
        local firstTime = tonumber(first.lastUsedAt) or 0
        local secondTime = tonumber(second.lastUsedAt) or 0
        if firstTime ~= secondTime then return firstTime < secondTime end
        return tostring(first.cacheKey) < tostring(second.cacheKey)
    end)
    for _, compiled in ipairs(inactive) do
        local overAssetLimit = self.compiledCount > self.maxCompiledAssets
        local overVertexLimit = self.compiledVertexCount > self.maxCompiledVertices
        local idle = now - (tonumber(compiled.lastUsedAt) or now)
        if force or overAssetLimit or overVertexLimit or idle >= self.compiledIdleSeconds then
            self:DisposeCompiled(compiled)
        end
    end
    return self:GetStats()
end

function IslandModelBatcher:MaybeSweep(force, protectCacheKey)
    if self.disposed then return false end
    local now = self:Now()
    local underPressure = self.emptyGroupCount > self.maxEmptyGroups
        or self.compiledCount > self.maxCompiledAssets
        or self.compiledVertexCount > self.maxCompiledVertices
    if force or underPressure or now - self.lastSweepAt >= self.sweepIntervalSeconds then
        self:Sweep({ force = force == true, protectCacheKey = protectCacheKey })
        return true
    end
    return false
end

function IslandModelBatcher:GetStats()
    local registrations = 0
    for _ in pairs(self.registrations or {}) do registrations = registrations + 1 end
    local groups = 0
    for _ in pairs(self.groups or {}) do groups = groups + 1 end
    return {
        registrations = registrations,
        groups = groups,
        emptyGroups = math.max(0, tonumber(self.emptyGroupCount) or 0),
        compiledAssets = math.max(0, tonumber(self.compiledCount) or 0),
        compiledVertices = math.max(0, tonumber(self.compiledVertexCount) or 0),
    }
end

function IslandModelBatcher:GetCell(x, z, create)
    local key = CellKey(x, z)
    local cell = self.cells[key]
    if cell or not create then return cell end
    cell = { key = key, x = x, z = z, groupCount = 0 }
    if not self.createGroup then
        local rootNode = NativeNode(self.root)
        if not rootNode or not rootNode.CreateChild then return nil end
        cell.node = rootNode:CreateChild("IslandModelBatchCell_" .. key)
    end
    self.cells[key] = cell
    return cell
end

function IslandModelBatcher:NightMaterial(part)
    if not part.emissionKind then return part.material end
    if self.nightMaterialFor then
        local material = self.nightMaterialFor(part.emissionKind, part)
        if material then return material end
    end
    return self.nightMaterials[part.emissionKind] or part.material
end

function IslandModelBatcher:ApplyGroupMaterial(group)
    local material = self.nightEnabled and self:NightMaterial(group.part) or group.part.material
    local native = NativeMaterial(material)
    if native ~= nil and group.component then group.component.material = native end
end

function IslandModelBatcher:CreateRenderGroup(compiled, part, cellX, cellZ)
    local cell = self:GetCell(cellX, cellZ, true)
    if not cell then return nil, "合批根节点不可用" end
    local baseKey = table.concat({ CellKey(cellX, cellZ), compiled.cacheKey, part.id }, KEY_SEPARATOR)
    local shard = 1
    local key = baseKey .. KEY_SEPARATOR .. tostring(shard)
    local existing = self.groups[key]
    while existing and #existing.instanceIds >= self.maxInstancesPerGroup do
        shard = shard + 1
        key = baseKey .. KEY_SEPARATOR .. tostring(shard)
        existing = self.groups[key]
    end
    if existing then
        self:TouchGroup(existing)
        return existing
    end

    local name = "IslandModelBatch_s" .. tostring(shard) .. "_" .. tostring(self.nextGroupSerial)
    self.nextGroupSerial = self.nextGroupSerial + 1
    local node, component
    if self.createGroup then
        local first, second = self.createGroup({
            key = key, name = name, shard = shard, cell = cell, compiled = compiled, part = part,
            model = part.model, material = part.material, viewMask = self.viewMask,
        })
        if type(first) == "table" and first.component then
            node, component = first.node, first.component
        elseif first and first.AddInstanceNode then
            component, node = first, second
        else
            node, component = first, second
        end
    else
        node = cell.node:CreateChild(name)
        component = node:CreateComponent("StaticModelGroup")
    end
    if not component or not component.AddInstanceNode then
        if node and node.Remove then node:Remove() end
        return nil, "无法创建 StaticModelGroup"
    end
    if node then node.name = name end
    component.model = part.model
    if self.viewMask ~= nil and component.SetViewMask then component:SetViewMask(self.viewMask) end
    if component.SetCastShadows then component:SetCastShadows(part.castShadow == true) end

    local group = {
        key = key,
        name = name,
        shard = shard,
        cell = cell,
        compiled = compiled,
        part = part,
        node = node,
        component = component,
        instanceIds = {},
        instanceNodes = {},
        lastUsedAt = self:Now(),
    }
    self.groups[key] = group
    self.groupsByNodeName[name] = group
    self.groupsByDrawable[component] = group
    cell.groupCount = cell.groupCount + 1
    self:ApplyGroupMaterial(group)
    return group
end

function IslandModelBatcher:DestroyRenderGroup(group)
    if not group or not self.groups[group.key] then return end
    -- Explicitly release every native instance pointer before either the group
    -- owner node or a shared compiled Model can be destroyed.
    local nativeMembersCleared = group.component == nil
    if group.component then
        nativeMembersCleared = group.component.RemoveAllInstanceNodes ~= nil
            and pcall(group.component.RemoveAllInstanceNodes, group.component)
    end
    if group.emptySince ~= nil then
        self.emptyGroupCount = math.max(0, self.emptyGroupCount - 1)
        group.emptySince = nil
    end
    self.groups[group.key] = nil
    self.groupsByNodeName[group.name] = nil
    self.groupsByDrawable[group.component] = nil
    local cell = group.cell
    if self.destroyGroup then self.destroyGroup(group)
    elseif group.node then
        local disposed = false
        if not nativeMembersCleared and group.node.Dispose then
            disposed = pcall(group.node.Dispose, group.node)
        end
        if not disposed and group.node.Remove then group.node:Remove() end
    end
    if cell then
        cell.groupCount = math.max(0, (cell.groupCount or 1) - 1)
        if cell.groupCount == 0 then
            self.cells[cell.key] = nil
            if cell.node and cell.node.Remove then cell.node:Remove() end
        end
    end
    group.component, group.node = nil, nil
end

function IslandModelBatcher:RebuildNativeMembers(group, skipIndex)
    if not group or not group.component or not group.component.RemoveAllInstanceNodes
        or not pcall(group.component.RemoveAllInstanceNodes, group.component) then
        return false
    end
    for index, node in ipairs(group.instanceNodes or {}) do
        if index ~= skipIndex then
            local added = pcall(group.component.AddInstanceNode, group.component, node)
            if not added then
                pcall(group.component.RemoveAllInstanceNodes, group.component)
                return false
            end
        end
    end
    return true
end

function IslandModelBatcher:RemoveGroupMember(group, targetNode, targetId)
    if not group or not group.component then return false end
    local removeIndex
    for index, node in ipairs(group.instanceNodes or {}) do
        if node == targetNode and group.instanceIds[index] == targetId then
            removeIndex = index
            break
        end
    end
    if not removeIndex then return true end

    local removed = pcall(group.component.RemoveInstanceNode, group.component, targetNode)
    if not removed then
        -- Some mobile native backends may reject an individual removal while
        -- rebuilding their internal StaticModelGroup array. Clear the native
        -- array first, then reconstruct it from the authoritative Lua members
        -- excluding the requested node. This prevents a dangling pointer from
        -- surviving into LRU model disposal.
        if not self:RebuildNativeMembers(group, removeIndex) then return false end
    end

    table.remove(group.instanceNodes, removeIndex)
    table.remove(group.instanceIds, removeIndex)
    return true
end

function IslandModelBatcher:Register(instance, asset)
    if self.disposed then return nil, "合批器已经释放" end
    local id, registrationKey = InstanceId(instance), RegistrationKey(instance)
    if id == nil or not registrationKey then return nil, "模型实例缺少 id" end
    local rootNode = NativeNode(type(instance) == "table" and instance.root or nil)
    if not rootNode then return nil, "模型实例缺少 root 节点" end
    if self.registrations[registrationKey] then self:Unregister(instance) end

    local compiled, errorMessage = self:Compile(asset)
    if not compiled then return nil, errorMessage end
    local x, z = InstancePosition(instance)
    local cellX, cellZ = CellCoordinate(x, self.cellSize), CellCoordinate(z, self.cellSize)
    local memberships = {}

    for _, part in ipairs(compiled.parts) do
        local group, groupError = self:CreateRenderGroup(compiled, part, cellX, cellZ)
        if not group then
            for index = #memberships, 1, -1 do
                local membership = memberships[index]
                local rollbackGroup = membership.group
                local safelyRemoved = self:RemoveGroupMember(
                    rollbackGroup, membership.node, id)
                if not safelyRemoved or #rollbackGroup.instanceIds == 0 then
                    self:DestroyRenderGroup(rollbackGroup)
                end
            end
            return nil, groupError
        end
        local ok, addError = pcall(group.component.AddInstanceNode, group.component, rootNode)
        if not ok then
            -- Native AddInstanceNode implementations are not guaranteed to be
            -- transactional: an exception can happen after the root pointer was
            -- appended. Rebuild from the authoritative, already-accounted Lua
            -- members so an untracked pointer cannot survive this failed add.
            local currentGroupRecovered = self:RebuildNativeMembers(group)
            if not currentGroupRecovered or #group.instanceIds == 0 then
                self:DestroyRenderGroup(group)
            end
            for index = #memberships, 1, -1 do
                local membership = memberships[index]
                local rollbackGroup = membership.group
                local safelyRemoved = self:RemoveGroupMember(
                    rollbackGroup, membership.node, id)
                if not safelyRemoved or #rollbackGroup.instanceIds == 0 then
                    self:DestroyRenderGroup(rollbackGroup)
                end
            end
            return nil, tostring(addError)
        end
        group.instanceIds[#group.instanceIds + 1] = id
        group.instanceNodes[#group.instanceNodes + 1] = rootNode
        self:TouchGroup(group)
        memberships[#memberships + 1] = { group = group, part = part, node = rootNode }
    end

    local registration = {
        key = registrationKey,
        instanceId = id,
        instance = instance,
        asset = asset,
        compiled = compiled,
        rootNode = rootNode,
        cellX = cellX,
        cellZ = cellZ,
        memberships = memberships,
    }
    self.registrations[registrationKey] = registration
    compiled.refCount = math.max(0, tonumber(compiled.refCount) or 0) + 1
    self:TouchCompiled(compiled)
    if type(instance) == "table" then
        instance._islandBatchMemberships = memberships
        instance._islandBatchedAsset = asset
        instance._islandBatchedCompiled = compiled
        instance._islandBatched = true
        instance.hasBatchedNightEmission = compiled.hasNightEmission == true
        instance.batchedRenderPartCount = #compiled.parts
        instance.batchedVertexCount = compiled.vertexCount
    end
    self:MaybeSweep(false, compiled.cacheKey)
    return true, compiled
end

function IslandModelBatcher:Unregister(instance, retainEmptyGroups)
    local key = RegistrationKey(instance)
    local registration = key and self.registrations[key] or nil
    if not registration and type(instance) == "table" then
        key = RegistrationKey({ id = instance.id or instance.instanceId })
        registration = key and self.registrations[key] or nil
    end
    if not registration then return false end

    -- RemoveInstanceNode must happen before either the logical instance root or
    -- group owner node is removed. Otherwise StaticModelGroup can retain a
    -- dangling native node pointer until the next ray query/render update.
    for _, membership in ipairs(registration.memberships) do
        local group = membership.group
        if group and group.component then
            local safeRemoval = self:RemoveGroupMember(
                group, membership.node, registration.instanceId)
            if not safeRemoval then
                -- Removing the group owner releases its native component even
                -- when both targeted removal and array reconstruction failed.
                -- This is safer than retaining an untracked native pointer.
                self:DestroyRenderGroup(group)
            end
            -- LOD keeps empty groups for rapid camera in/out reuse. Permanent
            -- removal and cell migration release them immediately, preventing
            -- a long editing session from accumulating abandoned native nodes.
            if group.component and #group.instanceIds == 0 and retainEmptyGroups == false then
                self:DestroyRenderGroup(group)
            elseif group.component and #group.instanceIds == 0 then
                self:MarkGroupEmpty(group)
            elseif group.component then
                self:TouchGroup(group)
            end
        end
    end
    self.registrations[registration.key] = nil
    if registration.compiled then
        registration.compiled.refCount = math.max(0,
            (tonumber(registration.compiled.refCount) or 1) - 1)
        self:TouchCompiled(registration.compiled)
    end
    local target = type(instance) == "table" and instance or registration.instance
    if type(target) == "table" then
        target._islandBatchMemberships = nil
        target._islandBatchedAsset = nil
        target._islandBatchedCompiled = nil
        target._islandBatched = nil
        target.hasBatchedNightEmission = nil
        target.batchedRenderPartCount = nil
        target.batchedVertexCount = nil
    end
    self:MaybeSweep(false)
    return true
end

function IslandModelBatcher:RefreshCell(instance)
    local key = RegistrationKey(instance)
    local registration = key and self.registrations[key] or nil
    if not registration then return nil, "模型尚未注册到合批器" end
    local rootNode = NativeNode(type(instance) == "table" and instance.root or nil)
    local x, z = InstancePosition(instance)
    local cellX, cellZ = CellCoordinate(x, self.cellSize), CellCoordinate(z, self.cellSize)
    if cellX == registration.cellX and cellZ == registration.cellZ and rootNode == registration.rootNode then
        return false, "仍在同一空间分桶"
    end
    local asset = registration.asset
    self:Unregister(instance, false)
    local ok, errorMessage = self:Register(instance, asset)
    if not ok then return nil, errorMessage end
    return true
end

function IslandModelBatcher:ResolveRay(nodeName, subObject)
    local group
    if type(nodeName) == "table" or type(nodeName) == "userdata" then
        local result = nodeName
        group = self.groupsByDrawable[result.drawable]
        subObject = subObject ~= nil and subObject or result.subObject
        local node = result.node
        nodeName = node and node.name or result.nodeName
    end
    group = group or self.groupsByNodeName[tostring(nodeName or "")]
    if not group then return nil end
    local index = tonumber(subObject)
    if index == nil then return #group.instanceIds == 1 and group.instanceIds[1] or nil end
    return group.instanceIds[math.floor(index) + 1]
end

function IslandModelBatcher:SetNightEnabled(enabled)
    enabled = enabled == true
    if self.nightEnabled == enabled then return false end
    self.nightEnabled = enabled
    for _, group in pairs(self.groups) do self:ApplyGroupMaterial(group) end
    return true
end

function IslandModelBatcher:Clear()
    local registrations = {}
    for _, registration in pairs(self.registrations) do registrations[#registrations + 1] = registration end
    for _, registration in ipairs(registrations) do self:Unregister(registration.instance) end

    -- Defensive cleanup for a component that rejected RemoveInstanceNode.
    local groups = {}
    for _, group in pairs(self.groups) do groups[#groups + 1] = group end
    for _, group in ipairs(groups) do
        if group.component and group.component.RemoveAllInstanceNodes then
            pcall(group.component.RemoveAllInstanceNodes, group.component)
        end
        self:DestroyRenderGroup(group)
    end
    for key, cell in pairs(self.cells) do
        if cell.node and cell.node.Remove then cell.node:Remove() end
        self.cells[key] = nil
    end
    self.registrations = {}
    self.groups = {}
    self.groupsByNodeName = {}
    self.groupsByDrawable = {}
    self.emptyGroupCount = 0
end

function IslandModelBatcher:Dispose()
    if self.disposed then return end
    self:Clear()
    local compiledEntries = {}
    for _, compiled in pairs(self.compiled) do compiledEntries[#compiledEntries + 1] = compiled end
    for _, compiled in ipairs(compiledEntries) do self:DisposeCompiled(compiled) end
    self.compiled = {}
    self.compiledCount, self.compiledVertexCount = 0, 0
    self.root = nil
    self.disposed = true
end

return IslandModelBatcher
