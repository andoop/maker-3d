local TerrainDiscoveryGuide = {}

TerrainDiscoveryGuide.DELAY = 3.0

function TerrainDiscoveryGuide.New(handledThisRun)
    return {
        handledThisRun = handledThisRun == true,
        phase = handledThisRun == true and "done" or "waiting",
        elapsed = 0,
        doNotRemind = false,
        carrier = nil,
        card = nil,
        flightFinished = false,
        attentionPending = false,
    }
end

function TerrainDiscoveryGuide.ShouldOpen(phase, elapsed, eligible, blocked, state)
    return phase == "waiting"
        and (tonumber(elapsed) or 0) >= TerrainDiscoveryGuide.DELAY
        and eligible == true
        and blocked ~= true
        and type(state) == "table"
        and state.visitMode ~= true
        and state.firstPerson ~= true
        and state.mode ~= "place"
end

function TerrainDiscoveryGuide.FlightDelta(source, target)
    if type(source) ~= "table" or type(target) ~= "table" then return 0, 0 end
    local sourceX = (tonumber(source.x) or 0) + (tonumber(source.w) or 0) * 0.5
    local sourceY = (tonumber(source.y) or 0) + (tonumber(source.h) or 0) * 0.5
    local targetX = (tonumber(target.x) or 0) + (tonumber(target.w) or 0) * 0.5
    local targetY = (tonumber(target.y) or 0) + (tonumber(target.h) or 0) * 0.5
    return targetX - sourceX, targetY - sourceY
end

function TerrainDiscoveryGuide.PanelGeometry(profile)
    profile = type(profile) == "table" and profile or {}
    local safe = type(profile.safe) == "table" and profile.safe or {}
    local mobile = profile.mode == "mobile"
    local widthAvailable = math.max(1, tonumber(profile.width) or 1)
    local heightAvailable = math.max(1, tonumber(profile.height) or 1)
    local mobileLeft = math.max(22, 12 + (tonumber(safe.left) or 0))
    local mobileRight = math.max(22, 12 + (tonumber(safe.right) or 0))
    local sideInset = mobile and math.max(mobileLeft, mobileRight) or 24
    local width = mobile and math.min(372, math.max(1, widthAvailable - sideInset * 2))
        or math.min(440, math.max(1, widthAvailable - 64))
    local topInset = mobile
        and math.max((tonumber(safe.top) or 0) + 12,
            (tonumber(profile.nativeMenuBottom) or 0) + 8)
        or (tonumber(profile.top) or 0) + 18
    local bottomInset = mobile and math.max(14, 12 + (tonumber(safe.bottom) or 0))
        or (tonumber(profile.footer) or 0) + 18
    local availableHeight = math.max(1, heightAvailable - topInset - bottomInset)
    local height = math.min(mobile and 216 or 224, availableHeight)
    return {
        left = (widthAvailable - width) * 0.5,
        top = topInset + math.max(0, (availableHeight - height) * 0.5),
        width = width,
        height = height,
    }
end

return TerrainDiscoveryGuide
