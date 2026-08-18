local MobileDetailCost = {}

function MobileDetailCost.EquivalentBlocks(blockCount, vertexCount)
    local blocks = math.max(1, math.floor((tonumber(blockCount) or 1) + 0.5))
    local vertices = math.max(0, tonumber(vertexCount) or 0)
    return math.max(blocks, math.ceil(vertices / 96))
end

function MobileDetailCost.ConservativeBlocks(blockCount)
    local blocks = math.max(1, math.floor((tonumber(blockCount) or 1) + 0.5))
    -- Round leaves/cones can cost several times more than one authored block.
    -- A failed precompile must overestimate, never admit excess geometry.
    return blocks * 6
end

return MobileDetailCost
