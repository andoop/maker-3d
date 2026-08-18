---@diagnostic disable: undefined-global

local Catalog = require("BlockCatalog")
local ModelGeometry = require("ModelGeometry")
local ModelMiniature = require("ModelMiniature")

local ModelAssetStore = {}
ModelAssetStore.__index = ModelAssetStore

ModelAssetStore.SCHEMA = "model-asset/v1"
ModelAssetStore.STATE_SCHEMA = "model-library/v1"
ModelAssetStore.MAX_PUBLIC_ASSETS = 12
ModelAssetStore.MAX_PUBLIC_BLOCKS = 2400
ModelAssetStore.MAX_ASSET_BLOCKS = 1200
ModelAssetStore.LICENSES = {
    allow_fork = "可使用与二次创作",
    use_only = "仅允许整体使用",
    private = "仅自己可见",
}

-- Old showcase assets are no longer listed, but islands saved before the
-- composable-library migration should open with the closest new authored
-- model instead of silently losing their placement.
local LEGACY_REPLACEMENTS = {
    ["builtin:wonder:cloudspine-mountain"] = "builtin:compose:snow-cap-mountain",
    ["builtin:wonder:starlight-ancient-forest"] = "builtin:compose:round-meadow-oak",
    ["builtin:wonder:windbell-world-tree"] = "builtin:compose:tall-guardian-oak",
    ["builtin:wonder:sky-garden-tower"] = "builtin:compose:narrow-three-storey-home",
    ["builtin:wonder:crystal-greenhouse-library"] = "builtin:compose:glass-garden-studio",
    ["builtin:wonder:cliffside-wind-town"] = "builtin:compose:brick-corner-shop",
    ["builtin:wonder:cloud-sail-station"] = "builtin:compose:cloud-courier-airship",
}

local LEGACY_RECOMMENDED_SCALES = {
    ["builtin:wonder:cloudspine-mountain"] = 0.44,
    ["builtin:wonder:starlight-ancient-forest"] = 0.47,
    ["builtin:wonder:windbell-world-tree"] = 0.62,
    ["builtin:wonder:sky-garden-tower"] = 0.42,
    ["builtin:wonder:crystal-greenhouse-library"] = 0.52,
    ["builtin:wonder:cliffside-wind-town"] = 0.45,
    ["builtin:wonder:cloud-sail-station"] = 0.46,
}

local function ResolveLegacyId(assetId)
    local value = tostring(assetId or "")
    return LEGACY_REPLACEMENTS[value] or value
end

function ModelAssetStore:ResolveLegacyInstance(assetId, scale)
    local sourceId = tostring(assetId or "")
    local oldRecommendedScale = LEGACY_RECOMMENDED_SCALES[sourceId]
    if not oldRecommendedScale then return ResolveLegacyId(sourceId), tonumber(scale) or 1 end
    -- Preserve the user's relative resize while converting the old miniature
    -- default to the new real-scale asset.
    local relativeScale = (tonumber(scale) or oldRecommendedScale) / oldRecommendedScale
    return ResolveLegacyId(sourceId), relativeScale
end

local function Now()
    local ok, value = pcall(os.time)
    return ok and tonumber(value) or 0
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

local function Trim(value, fallback)
    local result = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    return result ~= "" and result or fallback
end

local function LimitedText(value, fallback, maximum)
    local result = Trim(value, fallback)
    maximum = math.max(1, tonumber(maximum) or 80)
    if #result > maximum then
        local start = maximum
        while start > 1 do
            local byte = result:byte(start)
            if not byte or byte < 0x80 or byte >= 0xC0 then break end
            start = start - 1
        end
        local lead = result:byte(start) or 0
        local width = lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or lead >= 0xC0 and 2 or 1
        local cut = start + width - 1 <= maximum and start + width - 1 or start - 1
        result = result:sub(1, math.max(0, cut))
    end
    return result
end

local function Slug(value)
    local result = tostring(value or "model"):lower():gsub("[^%w_%-]+", "-")
    result = result:gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
    return result ~= "" and result or "model"
end

local function CleanNumber(value, fallback)
    local number = tonumber(value)
    if number == nil then number = fallback or 0 end
    if number ~= number or number == math.huge or number == -math.huge then number = fallback or 0 end
    number = math.max(-10000, math.min(10000, number))
    return math.floor(number * 1000 + 0.5) / 1000
end

local function NormalizeHex(value)
    local text = tostring(value or "#f2e7cf"):lower()
    if text:match("^#%x%x%x%x%x%x$") then return text end
    if text:match("^%x%x%x%x%x%x$") then return "#" .. text end
    return "#f2e7cf"
end

local function NormalizeBlock(source)
    source = type(source) == "table" and source or {}
    local position, size, rotation = source.position or {}, source.size or {}, source.rotation or {}
    local shapeId = Catalog.FindShape(source.shapeId or source.shape).id
    local collisionRole = tostring(source.collisionRole or "")
    if collisionRole ~= "solid" and collisionRole ~= "surface"
        and collisionRole ~= "decorative" and collisionRole ~= "fluid" then collisionRole = nil end
    return {
        name = LimitedText(source.name, "组件", 72),
        type = "block",
        position = {
            CleanNumber(source.x or position[1], 0),
            CleanNumber(source.y or position[2], 0.5),
            CleanNumber(source.z or position[3], 0),
        },
        size = {
            math.max(0.05, CleanNumber(source.sx or size[1], 1)),
            math.max(0.05, CleanNumber(source.sy or size[2], 1)),
            math.max(0.05, CleanNumber(source.sz or size[3], 1)),
        },
        rotation = {
            CleanNumber(source.rx or rotation[1], 0),
            CleanNumber(source.ry or rotation[2], 0),
            CleanNumber(source.rz or rotation[3], 0),
        },
        color = NormalizeHex(source.color),
        materialId = Catalog.FindMaterial(source.materialId or source.material).id,
        shapeId = shapeId,
        collisionRole = collisionRole,
    }
end

local function NormalizeTags(source)
    local result = {}
    for _, value in ipairs(type(source) == "table" and source or {}) do
        if #result >= 12 then break end
        result[#result + 1] = LimitedText(value, "标签", 32)
    end
    return result
end

local function NormalizeAttributions(source)
    local result = {}
    for _, item in ipairs(type(source) == "table" and source or {}) do
        if #result >= 24 then break end
        if type(item) == "table" then
            result[#result + 1] = {
                assetId = LimitedText(item.assetId, "unknown", 160),
                versionId = LimitedText(item.versionId, "latest", 32),
                name = LimitedText(item.name, "来源模型", 72),
                author = LimitedText(item.author, "云岛旅人", 48),
                license = ModelAssetStore.LICENSES[item.license] and item.license or "allow_fork",
            }
        end
    end
    return result
end

local function NormalizeDependencies(source)
    local result, seen = {}, {}
    for _, item in ipairs(type(source) == "table" and source or {}) do
        if #result >= 24 then break end
        if type(item) == "table" then
            local assetId = LimitedText(item.assetId, "", 160)
            local versionId = LimitedText(item.versionId, "latest", 32)
            local key = assetId .. "@" .. versionId
            if assetId ~= "" and not seen[key] then
                seen[key] = true
                result[#result + 1] = { assetId = assetId, versionId = versionId }
            end
        end
    end
    return result
end

local function RotateHalfExtents(block)
    return ModelGeometry.RotatedHalfExtents(block)
end

local function BoundsForBlocks(blocks)
    if type(blocks) ~= "table" or #blocks == 0 then
        return { min = { -0.5, 0, -0.5 }, max = { 0.5, 1, 0.5 }, size = { 1, 1, 1 }, pivot = { 0, 0, 0 } }
    end
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, block in ipairs(blocks) do
        local half = RotateHalfExtents(block)
        local p = block.position
        minX, maxX = math.min(minX, p[1] - half[1]), math.max(maxX, p[1] + half[1])
        minY, maxY = math.min(minY, p[2] - half[2]), math.max(maxY, p[2] + half[2])
        minZ, maxZ = math.min(minZ, p[3] - half[3]), math.max(maxZ, p[3] + half[3])
    end
    return {
        min = { CleanNumber(minX), CleanNumber(minY), CleanNumber(minZ) },
        max = { CleanNumber(maxX), CleanNumber(maxY), CleanNumber(maxZ) },
        size = { CleanNumber(maxX - minX), CleanNumber(maxY - minY), CleanNumber(maxZ - minZ) },
        pivot = { CleanNumber((minX + maxX) * 0.5), CleanNumber(minY), CleanNumber((minZ + maxZ) * 0.5) },
    }
end

local function NormalizeComponent(source)
    source = type(source) == "table" and source or {}
    local position = source.position or {}
    return {
        id = Trim(source.id, "component"),
        assetId = Trim(source.assetId, ""),
        versionId = Trim(source.versionId, "latest"),
        position = {
            CleanNumber(position[1] or source.x, 0),
            CleanNumber(position[2] or source.y, 0),
            CleanNumber(position[3] or source.z, 0),
        },
        rotationY = CleanNumber(source.rotationY or source.ry, 0),
        scale = math.max(0.05, CleanNumber(source.scale, 1)),
        linked = source.linked ~= false,
    }
end

local function SourceName(source)
    if source == "builtin" then return "内置" end
    if source == "market" then return "市场" end
    return "我的"
end

local function AssetKey(assetId, versionId)
    return tostring(assetId or "") .. "@" .. tostring(versionId or "latest")
end

local function IsCuratedOfflineMarketAsset(asset)
    return type(asset) == "table" and tostring(asset.assetId or ""):match("^market:curated:") ~= nil
end

local function UserId()
    local cloud = rawget(_G, "clientCloud")
    return tostring(cloud and cloud.userId or "local")
end

function ModelAssetStore.Normalize(source, options)
    source = type(source) == "table" and source or {}
    options = options or {}
    local blocks = {}
    for _, block in ipairs(source.blocks or {}) do blocks[#blocks + 1] = NormalizeBlock(block) end
    local components = {}
    for _, component in ipairs(source.components or {}) do
        local normalized = NormalizeComponent(component)
        if normalized.assetId ~= "" then components[#components + 1] = normalized end
    end
    local assetId = LimitedText(options.assetId or source.assetId or source.id, "", 160)
    if assetId == "" then assetId = "user:" .. UserId() .. ":" .. Slug(source.name) .. "-" .. tostring(Now()) end
    local origin = options.source or source.source
    if not origin then origin = source.builtin and "builtin" or "mine" end
    local license = Trim(options.license or source.license, origin == "mine" and "private" or "allow_fork")
    if not ModelAssetStore.LICENSES[license] then license = origin == "mine" and "private" or "allow_fork" end
    if origin ~= "mine" and license == "private" then license = "allow_fork" end
    local revision = math.max(1, math.floor(tonumber(options.revision or source.revision) or 1))
    local versionId = Trim(options.versionId or source.versionId, "draft-" .. tostring(revision))
    local asset = {
        schema = ModelAssetStore.SCHEMA,
        assetId = assetId,
        id = assetId,
        versionId = LimitedText(versionId, "draft-" .. tostring(revision), 32),
        revision = revision,
        source = origin,
        builtin = origin == "builtin",
        ownerId = LimitedText(options.ownerId or source.ownerId, origin == "builtin" and "official" or UserId(), 80),
        author = LimitedText(options.author or source.author, origin == "builtin" and "我的空岛" or "我", 48),
        name = LimitedText(options.name or source.name, "未命名模型", 72),
        description = LimitedText(options.description or source.description, "可在空岛和模型工作台中复用的模型", 240),
        category = LimitedText(options.category or source.category, origin == "mine" and "我的模型" or "精选模型", 48),
        designProfile = LimitedText(source.designProfile, origin == "builtin" and "wonder-showcase" or "custom", 32),
        recommendedScale = math.max(0.1, math.min(3, CleanNumber(source.recommendedScale, 1))),
        storeys = math.max(0, math.min(10, math.floor(tonumber(source.storeys) or 0))),
        tags = NormalizeTags(source.tags),
        license = license,
        parentAssetId = LimitedText(source.parentAssetId or source.parentAsset, "", 160),
        attributions = NormalizeAttributions(source.attributions),
        blocks = blocks,
        components = components,
        dependencies = {},
        packagedDependencies = NormalizeDependencies(source.packagedDependencies),
        createdAt = tonumber(source.createdAt) or Now(),
        updatedAt = tonumber(options.updatedAt or source.updatedAt) or Now(),
        publishedAt = tonumber(source.publishedAt) or nil,
        publishedVersion = source.publishedVersion and LimitedText(source.publishedVersion, "", 32) or nil,
        downloadCount = math.max(0, tonumber(source.downloadCount) or 0),
        featured = source.featured == true,
        thumbnail = type(source.thumbnail) == "string" and LimitedText(source.thumbnail, "", 256) or nil,
    }
    local seenDependencies = {}
    for _, component in ipairs(components) do
        local key = AssetKey(component.assetId, component.versionId)
        if not seenDependencies[key] then
            seenDependencies[key] = true
            asset.dependencies[#asset.dependencies + 1] = { assetId = component.assetId, versionId = component.versionId }
        end
    end
    asset.bounds = BoundsForBlocks(blocks)
    asset.stats = {
        blocks = #blocks,
        components = #components,
        transparent = 0,
        performance = #blocks <= 120 and "流畅" or #blocks <= 360 and "适中" or "精细",
    }
    for _, block in ipairs(blocks) do
        if Catalog.FindMaterial(block.materialId).transparent then asset.stats.transparent = asset.stats.transparent + 1 end
    end
    return asset
end

local function TransformBlock(block, component)
    local result = Copy(block)
    local p, s, r = result.position, result.size, result.rotation
    local scale = component.scale or 1
    local yaw = component.rotationY or 0
    local cosYaw, sinYaw = math.cos(yaw), math.sin(yaw)
    local x, z = p[1] * scale, p[3] * scale
    p[1] = component.position[1] + x * cosYaw + z * sinYaw
    p[2] = component.position[2] + p[2] * scale
    p[3] = component.position[3] - x * sinYaw + z * cosYaw
    s[1], s[2], s[3] = s[1] * scale, s[2] * scale, s[3] * scale
    r[2] = (r[2] or 0) + yaw
    return result
end

function ModelAssetStore.new(builtinTemplates)
    local self = setmetatable({}, ModelAssetStore)
    self.builtins, self.userAssets, self.marketAssets = {}, {}, {}
    self.byId, self.byKey = {}, {}
    self.favorites, self.downloaded = {}, {}
    self.cachedMarket = {}
    self.flattenCache = {}
    self.published = {}
    self.marketSyncPending = false
    self.withdrawn = {}
    self.sequence = 1
    self.stateRevision = 0
    self.updatedAt = Now()
    for _, template in ipairs(builtinTemplates or {}) do
        local templateVersion = math.max(1, math.floor(tonumber(template.version) or 1))
        local asset = ModelAssetStore.Normalize(template, {
            source = "builtin",
            assetId = tostring(template.id or "builtin:model"),
            versionId = tostring(templateVersion) .. ".0.0",
            ownerId = "official",
            author = "绘本冒险工坊",
            license = "allow_fork",
        })
        self.builtins[#self.builtins + 1] = asset
    end
    self:BuildOfflineMarket()
    self:Reindex()
    return self
end

function ModelAssetStore:Touch()
    self.stateRevision = (tonumber(self.stateRevision) or 0) + 1
    self.updatedAt = Now()
end

function ModelAssetStore:BuildOfflineMarket()
    self.marketAssets = {}
    local names = { "绿野工坊", "云朵木作社", "湖光设计所", "山谷造物家" }
    for index, source in ipairs(self.builtins) do
        local asset = ModelAssetStore.Normalize(source, {
            source = "market",
            assetId = "market:curated:" .. Slug(source.assetId:gsub("^builtin:", "")),
            versionId = source.versionId,
            ownerId = "curated-" .. tostring((index - 1) % #names + 1),
            author = names[(index - 1) % #names + 1],
            license = "allow_fork",
        })
        asset.featured = index <= 4
        asset.description = source.description
        -- Built-ins are immutable. Offline market cards can safely share the
        -- same geometry tables and only copy them when Flatten/Fork is used,
        -- avoiding a second resident copy of the full curated model library.
        asset.blocks, asset.bounds, asset.stats = source.blocks, source.bounds, source.stats
        self.marketAssets[#self.marketAssets + 1] = asset
    end
end

function ModelAssetStore:Reindex()
    self.byId, self.byKey = {}, {}
    -- Drafts must win the unversioned lookup for the current owner. Published
    -- snapshots remain addressable through their immutable version key.
    for _, collection in ipairs({ self.builtins, self.marketAssets, self.published, self.userAssets }) do
        for _, asset in ipairs(collection) do
            self.byId[asset.assetId] = asset
            self.byKey[AssetKey(asset.assetId, asset.versionId)] = asset
        end
    end
end

function ModelAssetStore:LoadState(state)
    state = type(state) == "table" and state or {}
    self.userAssets = {}
    for _, source in ipairs(state.items or state.userAssets or {}) do
        local asset = ModelAssetStore.Normalize(source, { source = "mine" })
        self.userAssets[#self.userAssets + 1] = asset
    end
    self.favorites = Copy(state.favorites or {})
    self.downloaded = Copy(state.downloaded or {})
    self.cachedMarket = {}
    local marketSeen, currentCurated = {}, {}
    for _, asset in ipairs(self.marketAssets) do
        marketSeen[AssetKey(asset.assetId, asset.versionId)] = true
        if IsCuratedOfflineMarketAsset(asset) then currentCurated[asset.assetId] = asset end
    end
    for _, source in ipairs(state.cachedMarket or {}) do
        local asset = ModelAssetStore.Normalize(source, { source = "market" })
        local key = AssetKey(asset.assetId, asset.versionId)
        local current = currentCurated[asset.assetId]
        if current then
            -- Curated cards are moving official content. Never let a cached
            -- 1.0.0 copy shadow newly authored doors or model geometry.
            local currentKey = AssetKey(current.assetId, current.versionId)
            if self.favorites[key] then self.favorites[currentKey] = true end
            if self.downloaded[key] then self.downloaded[currentKey] = true end
            self.favorites[key], self.downloaded[key] = nil, nil
        elseif not marketSeen[key] then
            marketSeen[key] = true
            self.cachedMarket[#self.cachedMarket + 1] = asset
            self.marketAssets[#self.marketAssets + 1] = asset
        end
    end
    self.published = {}
    for _, source in ipairs(state.published or {}) do
        local asset = ModelAssetStore.Normalize(source, { source = "market" })
        asset.isOwnPublication = true
        self.published[#self.published + 1] = asset
    end
    self.marketSyncPending = state.marketSyncPending == true
    self.withdrawn = Copy(state.withdrawn or {})
    self.sequence = math.max(1, tonumber(state.sequence) or (#self.userAssets + 1))
    self.stateRevision = math.max(0, tonumber(state.revision) or 0)
    self.updatedAt = tonumber(state.updatedAt) or 0
    self:InvalidateFlattenCache()
    self:Reindex()
end

function ModelAssetStore:ExportState()
    return {
        schema = ModelAssetStore.STATE_SCHEMA,
        version = 1,
        revision = self.stateRevision,
        updatedAt = self.updatedAt,
        sequence = self.sequence,
        items = Copy(self.userAssets),
        favorites = Copy(self.favorites),
        downloaded = Copy(self.downloaded),
        cachedMarket = Copy(self.cachedMarket),
        published = Copy(self.published),
        marketSyncPending = self.marketSyncPending == true,
        withdrawn = Copy(self.withdrawn),
    }
end

function ModelAssetStore:Get(assetId, versionId)
    assetId = ResolveLegacyId(assetId)
    if versionId and versionId ~= "latest" then
        local exact = self.byKey[AssetKey(assetId, versionId)]
        if exact then return exact end
        local current = self.byId[assetId]
        -- Draft revisions and official built-ins intentionally follow their
        -- latest authored form. Published/market versions never fall forward
        -- silently: their immutable snapshot must be present.
        if current and (current.source == "mine" or current.source == "builtin") then return current end
        return nil
    end
    return self.byId[assetId]
end

local function FlattenCacheKey(asset)
    return AssetKey(asset.assetId, asset.versionId)
end

function ModelAssetStore:InvalidateFlattenCache()
    self.flattenCache = {}
end

-- Returns the canonical flattened model cached for this exact asset version.
-- Callers may retain and compare this table, but must treat it and every nested
-- table as read-only. Editing/export paths should keep using Flatten(), which
-- deliberately returns a detached, mutable copy.
function ModelAssetStore:FlattenShared(assetOrId, visited)
    local asset = type(assetOrId) == "table" and assetOrId or self:Get(assetOrId)
    if not asset then return nil, "模型不存在" end
    visited = visited or {}
    local cacheKey = FlattenCacheKey(asset)
    local cached = self.flattenCache[cacheKey]
    if not visited[cacheKey] and cached then
        -- The key is assetId@versionId. Retaining the source identity as well
        -- prevents an externally refreshed asset with the same version label
        -- from observing geometry cached for the replaced table.
        if cached.source == asset then return cached.value end
        self.flattenCache[cacheKey] = nil
    end
    if visited[cacheKey] then return nil, "模型依赖形成循环" end
    visited[cacheKey] = true
    local blocks = Copy(asset.blocks or {})
    for _, component in ipairs(asset.components or {}) do
        local child = self:Get(component.assetId, component.versionId)
        if not child then visited[cacheKey] = nil; return nil, "缺少依赖模型：" .. tostring(component.assetId) end
        local flattened, errorMessage = self:FlattenShared(child, visited)
        if not flattened then visited[cacheKey] = nil; return nil, errorMessage end
        for _, block in ipairs(flattened.blocks) do blocks[#blocks + 1] = TransformBlock(block, component) end
    end
    visited[cacheKey] = nil
    local result = Copy(asset)
    result.blocks = blocks
    result.packagedDependencies = Copy(asset.dependencies or asset.packagedDependencies or {})
    result.components = {}
    result.bounds = BoundsForBlocks(blocks)
    result.stats = Copy(asset.stats)
    result.stats.blocks = #blocks
    self.flattenCache[cacheKey] = { source = asset, value = result }
    return result
end

-- Backward-compatible editable snapshot API. Mutating this result never
-- changes the shared render cache or a later Flatten() result.
function ModelAssetStore:Flatten(assetOrId, visited)
    local shared, errorMessage = self:FlattenShared(assetOrId, visited)
    if not shared then return nil, errorMessage end
    return Copy(shared)
end

-- Rendering/footprint code can use either name while migration is incremental.
ModelAssetStore.AcquireRenderable = ModelAssetStore.FlattenShared

function ModelAssetStore:CreateBlank(name)
    local id = "user:" .. UserId() .. ":model-" .. tostring(Now()) .. "-" .. tostring(self.sequence)
    self.sequence = self.sequence + 1
    local asset = ModelAssetStore.Normalize({ name = Trim(name, "新模型"), blocks = {} }, {
        source = "mine", assetId = id, ownerId = UserId(), author = "我", license = "private",
    })
    self.userAssets[#self.userAssets + 1] = asset
    self:Touch()
    self:Reindex()
    return asset
end

function ModelAssetStore:Fork(assetOrId, name)
    local source = type(assetOrId) == "table" and assetOrId or self:Get(assetOrId)
    if not source then return nil, "模型不存在" end
    if source.license == "use_only" then return nil, "作者仅允许整体使用，不能二次编辑" end
    local flattened, errorMessage = self:Flatten(source)
    if not flattened then return nil, errorMessage end
    local asset = self:CreateBlank(Trim(name, source.name .. " · 我的版本"))
    asset.blocks = Copy(flattened.blocks)
    asset.parentAssetId = source.assetId
    asset.description = "基于《" .. source.name .. "》创建"
    asset.category = "我的模型"
    asset.attributions = Copy(source.attributions or {})
    if source.source == "market" then
        asset.attributions[#asset.attributions + 1] = {
            assetId = source.assetId,
            versionId = source.versionId,
            name = source.name,
            author = source.author,
            license = source.license,
        }
    end
    asset.bounds = BoundsForBlocks(asset.blocks)
    asset.stats.blocks = #asset.blocks
    self:Reindex()
    return asset
end

function ModelAssetStore:SaveDraft(assetId, data)
    local asset = self:Get(assetId)
    if not asset or asset.source ~= "mine" then return nil, "只能保存自己的模型" end
    local normalized = ModelAssetStore.Normalize(data, {
        source = "mine",
        assetId = asset.assetId,
        revision = asset.revision + 1,
        versionId = "draft-" .. tostring(asset.revision + 1),
        ownerId = asset.ownerId,
        author = asset.author,
        name = data.name or asset.name,
        description = data.description or asset.description,
        category = data.category or asset.category,
        license = asset.license,
    })
    normalized.createdAt = asset.createdAt
    normalized.parentAssetId = asset.parentAssetId
    normalized.publishedVersion = asset.publishedVersion
    for index, item in ipairs(self.userAssets) do
        if item.assetId == asset.assetId then self.userAssets[index] = normalized; break end
    end
    self:Touch()
    self:InvalidateFlattenCache()
    self:Reindex()
    return normalized
end

function ModelAssetStore:Delete(assetId)
    for _, owner in ipairs(self.userAssets) do
        if owner.assetId ~= assetId then
            for _, component in ipairs(owner.components or {}) do
                if component.assetId == assetId then
                    return false, "这个模型正被《" .. tostring(owner.name) .. "》引用，不能删除"
                end
            end
        end
    end
    if not self.withdrawn[assetId] then
        for _, published in ipairs(self.published) do
            if published.assetId == assetId then return false, "已发布模型需要先下架再删除草稿" end
        end
    end
    for index, asset in ipairs(self.userAssets) do
        if asset.assetId == assetId then
            table.remove(self.userAssets, index)
            self:Touch()
            self:InvalidateFlattenCache()
            self:Reindex()
            return true
        end
    end
    return false, "模型不存在或不可删除"
end

function ModelAssetStore:SetLicense(assetId, license)
    local asset = self:Get(assetId)
    if not asset or asset.source ~= "mine" then return nil, "只能修改自己的模型许可" end
    if not ModelAssetStore.LICENSES[license] then return nil, "不支持的模型许可" end
    if asset.license == license then return asset end
    asset.license = license
    asset.updatedAt = Now()
    self:Touch()
    self:InvalidateFlattenCache()
    self:Reindex()
    return asset
end

function ModelAssetStore:ValidateForPublish(assetId)
    local asset = self:Get(assetId)
    if not asset or asset.source ~= "mine" then return false, "只能发布自己的模型" end
    local flattened, errorMessage = self:Flatten(asset)
    if not flattened then return false, errorMessage end
    if #flattened.blocks == 0 then return false, "空模型不能发布" end
    if #flattened.blocks > ModelAssetStore.MAX_ASSET_BLOCKS then
        return false, "模型超过 1200 个组件，请先优化"
    end
    if flattened.bounds.size[1] > 120 or flattened.bounds.size[2] > 120 or flattened.bounds.size[3] > 120 then
        return false, "模型尺寸过大，无法发布"
    end
    local publicCount, publicBlocks = 0, 0
    for _, draft in ipairs(self.userAssets) do
        if draft.assetId ~= assetId and draft.publishedVersion and not self.withdrawn[draft.assetId] then
            local snapshot = self:Get(draft.assetId, draft.publishedVersion)
            if snapshot then
                publicCount = publicCount + 1
                publicBlocks = publicBlocks + #(snapshot.blocks or {})
            end
        end
    end
    if publicCount >= ModelAssetStore.MAX_PUBLIC_ASSETS then
        return false, "模型市场最多同时公开 12 个作品，请先下架一个作品"
    end
    if publicBlocks + #flattened.blocks > ModelAssetStore.MAX_PUBLIC_BLOCKS then
        return false, "公开作品合计超过 2400 个组件，请先下架或精简其他作品"
    end
    return true, flattened
end

function ModelAssetStore:Publish(assetId)
    local ok, flattenedOrMessage = self:ValidateForPublish(assetId)
    if not ok then return nil, flattenedOrMessage end
    local source, flattened = self:Get(assetId), flattenedOrMessage
    local major, minor = 1, 0
    if source.publishedVersion then
        local majorText, minorText = tostring(source.publishedVersion):match("^(%d+)%.(%d+)")
        major, minor = tonumber(majorText) or 1, (tonumber(minorText) or 0) + 1
    end
    local versionId = tostring(major) .. "." .. tostring(minor) .. ".0"
    local publishLicense = source.license == "private" and "allow_fork" or source.license
    -- Publishing makes the draft public as well. A model that was still marked
    -- private gets the least surprising public default: attribution + forking.
    source.license = publishLicense
    local published = ModelAssetStore.Normalize(flattened, {
        source = "market",
        assetId = source.assetId,
        versionId = versionId,
        revision = source.revision,
        ownerId = source.ownerId,
        author = source.author,
        license = publishLicense,
    })
    published.publishedAt = Now()
    published.isOwnPublication = true
    source.publishedVersion = versionId
    local replaced = false
    for index, item in ipairs(self.published) do
        if item.assetId == published.assetId and item.versionId == published.versionId then
            self.published[index] = published
            replaced = true
            break
        end
    end
    if not replaced then self.published[#self.published + 1] = published end
    self.withdrawn[assetId] = nil
    self.marketSyncPending = true
    self:Touch()
    -- Publishing may change the draft's effective license without changing its
    -- draft version, so the assetId@versionId cache must be invalidated here.
    self:InvalidateFlattenCache()
    self:Reindex()
    return published
end

function ModelAssetStore:Unpublish(assetId)
    local hasPublished = false
    for _, asset in ipairs(self.published) do
        if asset.assetId == assetId then hasPublished = true; break end
    end
    if not hasPublished then return false, "这个模型还没有发布" end
    if self.withdrawn[assetId] then return false, "这个模型已经下架" end
    self.withdrawn[assetId] = true
    self.marketSyncPending = true
    self:Touch()
    return true
end

function ModelAssetStore:HasPendingMarketSync()
    return self.marketSyncPending == true and #self.published > 0
end

function ModelAssetStore:MarkMarketSynced()
    if not self.marketSyncPending then return end
    self.marketSyncPending = false
    self:Touch()
end

function ModelAssetStore:MergeRemoteMarket(items)
    local curated = {}
    for _, item in ipairs(self.marketAssets) do
        if tostring(item.assetId):match("^market:curated:") then curated[#curated + 1] = item end
    end
    self.marketAssets = curated
    local seen = {}
    for _, item in ipairs(curated) do seen[AssetKey(item.assetId, item.versionId)] = true end
    for _, item in ipairs(self.cachedMarket or {}) do
        local key = AssetKey(item.assetId, item.versionId)
        if not seen[key] then
            seen[key] = true
            self.marketAssets[#self.marketAssets + 1] = item
        end
    end
    for _, source in ipairs(items or {}) do
        local asset = ModelAssetStore.Normalize(source, { source = "market" })
        local key = AssetKey(asset.assetId, asset.versionId)
        if asset.ownerId ~= UserId() and not seen[key] and #asset.blocks > 0 then
            seen[key] = true
            self.marketAssets[#self.marketAssets + 1] = asset
        end
    end
    table.sort(self.marketAssets, function(a, b)
        if a.featured ~= b.featured then return a.featured == true end
        return (tonumber(a.publishedAt) or 0) > (tonumber(b.publishedAt) or 0)
    end)
    self:InvalidateFlattenCache()
    self:Reindex()
end

-- Island visits need the exact flattened model versions carried by a public
-- island snapshot. Cache them like downloaded market assets so revisiting also
-- works offline, without replacing the independently refreshed model market.
function ModelAssetStore:CacheExternalAssets(items)
    local changed = false
    for _, source in ipairs(items or {}) do
        local asset = ModelAssetStore.Normalize(source, { source = "market" })
        local key = AssetKey(asset.assetId, asset.versionId)
        if #asset.blocks > 0 and not self.byKey[key] then
            self.cachedMarket[#self.cachedMarket + 1] = Copy(asset)
            self.marketAssets[#self.marketAssets + 1] = asset
            self.downloaded[key] = true
            changed = true
        end
    end
    if changed then
        self:Touch()
        self:InvalidateFlattenCache()
        self:Reindex()
    end
    return changed
end

function ModelAssetStore:ToggleFavorite(assetId, versionId)
    local asset = self:Get(assetId, versionId)
    if not asset then return false end
    local key = AssetKey(asset.assetId, asset.versionId)
    if self.favorites[key] then self.favorites[key] = nil; self:Touch(); return false end
    self.favorites[key] = true
    self:MarkUsed(asset)
    self:Touch()
    return true
end

function ModelAssetStore:IsFavorite(asset)
    return asset and self.favorites[AssetKey(asset.assetId, asset.versionId)] == true or false
end

function ModelAssetStore:MarkUsed(asset)
    if not asset then return end
    local key = AssetKey(asset.assetId, asset.versionId)
    local changed = self.downloaded[key] ~= true
    self.downloaded[key] = true
    if asset.source == "market" and not asset.isOwnPublication then
        for _, cached in ipairs(self.cachedMarket) do
            if AssetKey(cached.assetId, cached.versionId) == key then
                if changed then self:Touch() end
                return
            end
        end
        self.cachedMarket[#self.cachedMarket + 1] = Copy(asset)
        changed = true
    end
    if changed then self:Touch() end
end

function ModelAssetStore:GetPublishedProfile()
    local ordered = Copy(self.published)
    table.sort(ordered, function(a, b) return (tonumber(a.publishedAt) or 0) > (tonumber(b.publishedAt) or 0) end)
    local items, seen, totalBlocks = {}, {}, 0
    for _, asset in ipairs(ordered) do
        local count = asset.stats and tonumber(asset.stats.blocks) or #(asset.blocks or {})
        if not self.withdrawn[asset.assetId] and not seen[asset.assetId]
            and #items < ModelAssetStore.MAX_PUBLIC_ASSETS
            and totalBlocks + count <= ModelAssetStore.MAX_PUBLIC_BLOCKS then
            seen[asset.assetId] = true
            items[#items + 1] = Copy(asset)
            totalBlocks = totalBlocks + count
        end
    end
    return { schema = "model-market-profile/v1", ownerId = UserId(), updatedAt = Now(), items = items }
end

local function VersionTuple(value)
    local major, minor, patch = tostring(value or "0.0.0"):match("^(%d+)%.(%d+)%.?(%d*)")
    return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
end

local function IsNewerAsset(candidate, current)
    if not current then return true end
    local candidatePublished = tonumber(candidate.publishedAt) or 0
    local currentPublished = tonumber(current.publishedAt) or 0
    if candidatePublished ~= currentPublished then return candidatePublished > currentPublished end
    local ca, cb, cc = VersionTuple(candidate.versionId)
    local oa, ob, oc = VersionTuple(current.versionId)
    if ca ~= oa then return ca > oa end
    if cb ~= ob then return cb > ob end
    if cc ~= oc then return cc > oc end
    return (tonumber(candidate.updatedAt) or 0) > (tonumber(current.updatedAt) or 0)
end

local function LatestAssets(items)
    local latest, order = {}, {}
    for _, asset in ipairs(items or {}) do
        if not latest[asset.assetId] then order[#order + 1] = asset.assetId end
        if IsNewerAsset(asset, latest[asset.assetId]) then latest[asset.assetId] = asset end
    end
    local result = {}
    for _, assetId in ipairs(order) do result[#result + 1] = latest[assetId] end
    return result
end

function ModelAssetStore:GetAssets(tab)
    local result = {}
    local function Append(items)
        for _, asset in ipairs(items or {}) do
            if tab ~= "favorites" or self:IsFavorite(asset) then result[#result + 1] = asset end
        end
    end
    if tab == "builtin" then Append(self.builtins)
    elseif tab == "mine" then Append(self.userAssets)
    elseif tab == "market" then
        local activeOwn = {}
        for _, asset in ipairs(LatestAssets(self.published)) do
            if not self.withdrawn[asset.assetId] then activeOwn[#activeOwn + 1] = asset end
        end
        Append(activeOwn)
        for _, asset in ipairs(LatestAssets(self.marketAssets)) do
            if not IsCuratedOfflineMarketAsset(asset) then
                Append({ asset })
            end
        end
    elseif tab == "favorites" then
        Append(self.published)
        for _, asset in ipairs(self.marketAssets) do
            if not IsCuratedOfflineMarketAsset(asset) then Append({ asset }) end
        end
    else
        Append(self.builtins)
        Append(self.userAssets)
        Append(LatestAssets(self.published))
        for _, asset in ipairs(LatestAssets(self.marketAssets)) do
            if not IsCuratedOfflineMarketAsset(asset) then Append({ asset }) end
        end
    end
    return result
end

function ModelAssetStore:GetSummaries(tab)
    local summaries = {}
    for _, asset in ipairs(self:GetAssets(tab)) do
        if (not asset.thumbnail or asset.thumbnail == "")
            and (not asset.previewParts or #asset.previewParts == 0) then
            local flattened = self:Flatten(asset)
            asset.previewParts = ModelMiniature.Parts(flattened or asset, 12)
        end
        summaries[#summaries + 1] = {
            id = asset.assetId,
            assetId = asset.assetId,
            versionId = asset.versionId,
            name = asset.name,
            description = asset.description,
            category = asset.category,
            designProfile = asset.designProfile,
            recommendedScale = asset.recommendedScale,
            storeys = asset.storeys,
            thumbnail = asset.thumbnail,
            previewParts = Copy(asset.previewParts),
            source = asset.source,
            sourceName = SourceName(asset.source),
            builtin = asset.source == "builtin",
            author = asset.author,
            ownerId = asset.ownerId,
            count = asset.stats and asset.stats.blocks or #asset.blocks,
            performance = asset.stats and asset.stats.performance or "流畅",
            favorite = self:IsFavorite(asset),
            featured = asset.featured,
            license = asset.license,
            publishedVersion = asset.publishedVersion,
            isOwnPublication = asset.isOwnPublication,
            withdrawn = self.withdrawn[asset.assetId] == true,
        }
    end
    return summaries
end

ModelAssetStore.Copy = Copy
ModelAssetStore.AssetKey = AssetKey
ModelAssetStore.BoundsForBlocks = BoundsForBlocks

return ModelAssetStore
