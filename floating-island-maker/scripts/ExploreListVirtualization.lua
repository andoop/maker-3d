local ExploreListVirtualization = {}

ExploreListVirtualization.POOL_BUFFER = 2

local function EmptyMessage(loading, mode)
    if loading then return "正在寻找可参观的空岛……" end
    if mode == "favorites" then return "还没有收藏空岛，遇到喜欢的作品就收藏起来吧。" end
    return "还没有发现玩家空岛，先发布自己的空岛吧。"
end

function ExploreListVirtualization.Data(entries, loading, mode)
    local data = {}
    if not loading then
        for _, entry in ipairs(entries or {}) do data[#data + 1] = entry end
    end
    if #data == 0 then
        data[1] = { _empty = true, message = EmptyMessage(loading, mode) }
    end
    return data
end

function ExploreListVirtualization.Signature(entry)
    if entry and entry._empty then return "#empty:" .. tostring(entry.message) end
    return table.concat({
        tostring(entry and entry.id), tostring(entry and entry.name),
        tostring(entry and entry.ownerId), tostring(entry and entry.owner),
        tostring(entry and entry.count), tostring(entry and entry.description),
        tostring(entry and entry.source), tostring(entry and entry.likes),
        tostring(entry and entry.liked), tostring(entry and entry.favorite),
    }, ":")
end

return ExploreListVirtualization
