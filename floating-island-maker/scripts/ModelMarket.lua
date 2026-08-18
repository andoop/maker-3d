---@diagnostic disable: undefined-global

local ModelMarket = {}
local ModelAssetStore = require("ModelAssetStore")
local UserProfileService = require("UserProfileService")

ModelMarket.PROFILE_KEY = "island3d_model_market_profile_v1"
ModelMarket.ACTIVITY_KEY = "island3d_model_market_activity_v1"
ModelMarket.PAGE_SIZE = 50
ModelMarket.MAX_PROFILE_ASSETS = 12
ModelMarket.MAX_PROFILE_BLOCKS = 2400
ModelMarket.MAX_RESULT_ASSETS = 120
ModelMarket.MAX_RESULT_BLOCKS = 12000

local function Dispatch(callbacks, name, ...)
    local callback = callbacks and callbacks[name]
    if callback then callback(...) end
end

local function GetCloud()
    local cloud = rawget(_G, "clientCloud")
    return cloud and cloud.GetRankList and cloud.BatchSet and cloud or nil
end

local function Decode(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" or value == "" then return nil end
    local ok, data = pcall(cjson.decode, value)
    return ok and type(data) == "table" and data or nil
end

local function ExtractProfile(item)
    if type(item) ~= "table" then return nil end
    local containers = { item.score, item.values, item.value, item }
    for _, container in ipairs(containers) do
        if type(container) == "table" then
            local profile = Decode(container[ModelMarket.PROFILE_KEY])
            if profile then return profile end
        end
    end
    return nil
end

local function PublicAssetId(ownerId, assetId)
    ownerId, assetId = tostring(ownerId or "unknown"), tostring(assetId or "model")
    ownerId = ownerId:gsub("[^%w_%-%.]", "-")
    local expectedPrefix = "user:" .. ownerId .. ":"
    if assetId:sub(1, #expectedPrefix) == expectedPrefix then return assetId end
    -- The owner is part of the public identity. This prevents an untrusted
    -- profile from shadowing built-ins or another creator's model ID.
    return "market:" .. ownerId .. ":" .. assetId:gsub("[^%w_:%-%.]", "-")
end

local function WithNicknames(items, ownerIds, callbacks, source)
    UserProfileService.Resolve(ownerIds, {
        ok = function(profiles)
            for _, asset in ipairs(items) do
                local profile = profiles[UserProfileService.UserKey(asset.ownerId)]
                if profile then
                    asset.author = profile.nickname
                    asset.avatar = UserProfileService.Copy(profile.avatar)
                end
            end
            Dispatch(callbacks, "ok", items, source)
        end,
    })
end

function ModelMarket.IsOnline()
    return GetCloud() ~= nil
end

function ModelMarket.Publish(profile, callbacks)
    if type(profile) ~= "table" then
        Dispatch(callbacks, "error", "发布数据无效")
        return false
    end
    local cloud = GetCloud()
    if not cloud then
        Dispatch(callbacks, "ok", "local")
        return true
    end
    local timestamp = 0
    local okTime, value = pcall(os.time)
    if okTime then timestamp = math.max(1, math.floor(tonumber(value) or 1)) end
    local started, startError = pcall(function()
        cloud:BatchSet()
            :Set(ModelMarket.PROFILE_KEY, profile)
            :SetInt(ModelMarket.ACTIVITY_KEY, timestamp)
            :Save("发布模型市场作品", {
                ok = function() Dispatch(callbacks, "ok", "cloud") end,
                error = function(code, reason)
                    Dispatch(callbacks, "error", "模型市场发布失败：" .. tostring(reason or code or "未知错误"))
                end,
                timeout = function() Dispatch(callbacks, "error", "模型市场发布超时，请重试") end,
            })
    end)
    if not started then
        Dispatch(callbacks, "error", "模型市场发布启动失败：" .. tostring(startError))
        return false
    end
    return true
end

function ModelMarket.Load(callbacks)
    local cloud = GetCloud()
    if not cloud then
        Dispatch(callbacks, "ok", {}, "offline")
        return false
    end
    local started, startError = pcall(function()
        cloud:GetRankList(ModelMarket.ACTIVITY_KEY, 0, ModelMarket.PAGE_SIZE, {
            ok = function(rankList)
                local assets, ownerIds, ownerSeen = {}, {}, {}
                local resultBlocks = 0
                for _, item in ipairs(rankList or {}) do
                    local rawOwnerId = UserProfileService.ExtractUserId(item)
                    local ownerId = UserProfileService.UserKey(rawOwnerId) or ""
                    local profile = ExtractProfile(item)
                    if profile and type(profile.items) == "table" then
                        if ownerId ~= "" and not ownerSeen[ownerId] then
                            ownerSeen[ownerId] = true
                            ownerIds[#ownerIds + 1] = rawOwnerId
                        end
                        local profileAssets, profileBlocks = 0, 0
                        for _, source in ipairs(profile.items) do
                            local blockCount = type(source) == "table" and type(source.blocks) == "table" and #source.blocks or 0
                            local withinProfile = profileAssets < ModelMarket.MAX_PROFILE_ASSETS
                                and profileBlocks + blockCount <= ModelMarket.MAX_PROFILE_BLOCKS
                            local withinResult = #assets < ModelMarket.MAX_RESULT_ASSETS
                                and resultBlocks + blockCount <= ModelMarket.MAX_RESULT_BLOCKS
                            if withinProfile and withinResult and blockCount > 0 and blockCount <= 1200
                                and source.schema == "model-asset/v1" then
                                local clean = ModelAssetStore.Copy(source)
                                clean.ownerId = ownerId ~= "" and ownerId or tostring(clean.ownerId or "unknown")
                                clean.assetId = PublicAssetId(clean.ownerId, clean.assetId or clean.id)
                                clean.id = clean.assetId
                                clean.source = "market"
                                -- Marketplace payloads are declarative. Ignore every unknown
                                -- executable field even if a malformed client tried to add one.
                                clean.script, clean.code, clean.lua, clean.behaviors = nil, nil, nil, nil
                                clean.components, clean.dependencies, clean.packagedDependencies = {}, {}, {}
                                clean.tags, clean.thumbnail = {}, nil
                                clean = ModelAssetStore.Normalize(clean, {
                                    source = "market", assetId = clean.assetId,
                                    ownerId = clean.ownerId, license = clean.license,
                                })
                                local size = clean.bounds and clean.bounds.size or {}
                                local dimensionsValid = (tonumber(size[1]) or 999) <= 120
                                    and (tonumber(size[2]) or 999) <= 120
                                    and (tonumber(size[3]) or 999) <= 120
                                if dimensionsValid then
                                    assets[#assets + 1] = clean
                                    profileAssets = profileAssets + 1
                                    profileBlocks = profileBlocks + blockCount
                                    resultBlocks = resultBlocks + blockCount
                                end
                            end
                        end
                    end
                end
                WithNicknames(assets, ownerIds, callbacks, "cloud")
            end,
            error = function(code, reason)
                Dispatch(callbacks, "error", "模型市场读取失败：" .. tostring(reason or code or "未知错误"))
            end,
            timeout = function() Dispatch(callbacks, "error", "模型市场读取超时") end,
        }, ModelMarket.PROFILE_KEY)
    end)
    if not started then
        Dispatch(callbacks, "error", "模型市场读取启动失败：" .. tostring(startError))
        return false
    end
    return true
end

return ModelMarket
