---@diagnostic disable: undefined-global

-- Exact Lua port of three@0.180.0 RoundedBoxGeometry's position/normal recipe.
-- The stock Maker helper only subdivides each face `segments` times, so with
-- segments=2 its rounded corner vertices pull the whole face inward and make
-- the centre look inflated. Three uses segments * 2 + 1 face divisions: that
-- leaves a large, perfectly planar centre and confines rounding to the edge.

local HtmlRoundedBoxGeometry = {}

local FACES = {
    { { 0.5, -0.5, 0.5 }, { 0.5, -0.5, -0.5 }, { 0.5, 0.5, 0.5 } },
    { { -0.5, -0.5, -0.5 }, { -0.5, -0.5, 0.5 }, { -0.5, 0.5, -0.5 } },
    { { -0.5, 0.5, 0.5 }, { 0.5, 0.5, 0.5 }, { -0.5, 0.5, -0.5 } },
    { { -0.5, -0.5, -0.5 }, { 0.5, -0.5, -0.5 }, { -0.5, -0.5, 0.5 } },
    { { -0.5, -0.5, 0.5 }, { 0.5, -0.5, 0.5 }, { -0.5, 0.5, 0.5 } },
    { { 0.5, -0.5, -0.5 }, { -0.5, -0.5, -0.5 }, { 0.5, 0.5, -0.5 } },
}

local function Sign(value)
    if value < 0 then return -1 end
    if value > 0 then return 1 end
    return 0
end

local function Build(self, node, nativeMaterial)
    local totalSegments = self.segments * 2 + 1
    local halfSegmentSize = 0.5 / totalSegments
    local radius = math.min(self.radius, self.width * 0.5, self.height * 0.5, self.depth * 0.5)
    local boxX = self.width * 0.5 - radius
    local boxY = self.height * 0.5 - radius
    local boxZ = self.depth * 0.5 - radius

    local geometry = node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)

    for _, face in ipairs(FACES) do
        local q1, q2, q4 = face[1], face[2], face[3]

        local function GridPoint(i, j)
            local u, v = i / totalSegments, j / totalSegments
            return q1[1] + u * (q2[1] - q1[1]) + v * (q4[1] - q1[1]),
                q1[2] + u * (q2[2] - q1[2]) + v * (q4[2] - q1[2]),
                q1[3] + u * (q2[3] - q1[3]) + v * (q4[3] - q1[3])
        end

        local function Emit(i, j)
            local ux, uy, uz = GridPoint(i, j)
            local nx = ux - Sign(ux) * halfSegmentSize
            local ny = uy - Sign(uy) * halfSegmentSize
            local nz = uz - Sign(uz) * halfSegmentSize
            local length = math.sqrt(nx * nx + ny * ny + nz * nz)
            if length > 0.000001 then
                nx, ny, nz = nx / length, ny / length, nz / length
            end

            geometry:DefineVertex(Vector3(
                boxX * Sign(ux) + nx * radius,
                boxY * Sign(uy) + ny * radius,
                boxZ * Sign(uz) + nz * radius
            ))
            geometry:DefineNormal(Vector3(nx, ny, nz))
            geometry:DefineTexCoord(Vector2(i / totalSegments, j / totalSegments))
        end

        for i = 0, totalSegments - 1 do
            for j = 0, totalSegments - 1 do
                Emit(i, j); Emit(i + 1, j); Emit(i + 1, j + 1)
                Emit(i, j); Emit(i + 1, j + 1); Emit(i, j + 1)
            end
        end
    end

    geometry:Commit()
    if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
    return geometry
end

function HtmlRoundedBoxGeometry.new(width, height, depth, segments, radius)
    return {
        _kind = "geometry",
        width = width or 1,
        height = height or 1,
        depth = depth or 1,
        segments = math.max(1, math.floor(segments or 2)),
        radius = radius or 0.1,
        build = Build,
    }
end

return HtmlRoundedBoxGeometry
