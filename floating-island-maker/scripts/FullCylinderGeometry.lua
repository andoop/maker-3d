---@diagnostic disable: undefined-global

-- Closed, normalized Y-axis cylinder. The runtime CylinderGeometry helper has
-- shown incomplete sectors on some Maker clients, so model blocks use this
-- deterministic CustomGeometry recipe with explicit side and cap triangles.
local FullCylinderGeometry = {}
local TAU = math.pi * 2

local function Build(self, node, nativeMaterial)
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local segments = math.max(3, math.floor(tonumber(self.parameters.radialSegments) or 24))

    local function Emit(x, y, z, nx, ny, nz, u, v)
        geometry:DefineVertex(Vector3(x, y, z))
        geometry:DefineNormal(Vector3(nx, ny, nz))
        geometry:DefineTexCoord(Vector2(u, v))
    end

    for index = 0, segments - 1 do
        local nextIndex = index + 1
        local angleA, angleB = TAU * index / segments, TAU * nextIndex / segments
        local ax, az = math.sin(angleA) * 0.5, math.cos(angleA) * 0.5
        local bx, bz = math.sin(angleB) * 0.5, math.cos(angleB) * 0.5
        local nax, naz, nbx, nbz = math.sin(angleA), math.cos(angleA), math.sin(angleB), math.cos(angleB)
        local uA, uB = index / segments, nextIndex / segments

        -- Two side triangles with smooth radial normals.
        Emit(ax, -0.5, az, nax, 0, naz, uA, 0)
        Emit(bx, -0.5, bz, nbx, 0, nbz, uB, 0)
        Emit(bx, 0.5, bz, nbx, 0, nbz, uB, 1)
        Emit(ax, -0.5, az, nax, 0, naz, uA, 0)
        Emit(bx, 0.5, bz, nbx, 0, nbz, uB, 1)
        Emit(ax, 0.5, az, nax, 0, naz, uA, 1)

        -- Explicit top and bottom caps prevent the partial/open appearance.
        Emit(0, 0.5, 0, 0, 1, 0, 0.5, 0.5)
        Emit(ax, 0.5, az, 0, 1, 0, ax + 0.5, az + 0.5)
        Emit(bx, 0.5, bz, 0, 1, 0, bx + 0.5, bz + 0.5)
        Emit(0, -0.5, 0, 0, -1, 0, 0.5, 0.5)
        Emit(bx, -0.5, bz, 0, -1, 0, bx + 0.5, bz + 0.5)
        Emit(ax, -0.5, az, 0, -1, 0, ax + 0.5, az + 0.5)
    end

    geometry:Commit()
    if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
    return geometry
end

function FullCylinderGeometry.new(radialSegments)
    return {
        _kind = "geometry",
        parameters = { radiusTop = 0.5, radiusBottom = 0.5, height = 1, radialSegments = radialSegments or 24 },
        build = Build,
    }
end

return FullCylinderGeometry
