---@diagnostic disable: undefined-global

-- Flat-shaded normalized polyhedra. The bundled polyhedron helpers use
-- vertex/radial normals (right for geodesic spheres), while editor pyramids
-- need one crisp normal per face.
local FacetedSolidGeometry = {}

local function Recipe(vertices, triangles)
    local function Build(self, node, nativeMaterial)
        local geometry = node:CreateComponent("CustomGeometry")
        geometry:BeginGeometry(0, TRIANGLE_LIST)
        for _, indices in ipairs(triangles) do
            local a = vertices[indices[1]]
            local b = vertices[indices[2]]
            local c = vertices[indices[3]]
            local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local acx, acy, acz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
            local nx = aby * acz - abz * acy
            local ny = abz * acx - abx * acz
            local nz = abx * acy - aby * acx
            local length = math.max(0.000001, math.sqrt(nx * nx + ny * ny + nz * nz))
            nx, ny, nz = nx / length, ny / length, nz / length
            for vertexIndex, vertex in ipairs({ a, b, c }) do
                geometry:DefineVertex(Vector3(vertex[1], vertex[2], vertex[3]))
                geometry:DefineNormal(Vector3(nx, ny, nz))
                if vertexIndex == 1 then geometry:DefineTexCoord(Vector2(0, 0))
                elseif vertexIndex == 2 then geometry:DefineTexCoord(Vector2(1, 0))
                else geometry:DefineTexCoord(Vector2(0.5, 1)) end
            end
        end
        geometry:Commit()
        if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
        return geometry
    end
    return { _kind = "geometry", build = Build }
end

function FacetedSolidGeometry.SquarePyramid()
    local vertices = {
        { -0.5, -0.5, -0.5 }, { 0.5, -0.5, -0.5 },
        { 0.5, -0.5, 0.5 }, { -0.5, -0.5, 0.5 },
        { 0, 0.5, 0 },
    }
    return Recipe(vertices, {
        { 1, 2, 3 }, { 1, 3, 4 },
        { 1, 5, 2 }, { 2, 5, 3 }, { 3, 5, 4 }, { 4, 5, 1 },
    })
end

function FacetedSolidGeometry.Tetrahedron()
    local vertices = {
        { 0.5, 0.5, 0.5 }, { -0.5, -0.5, 0.5 },
        { -0.5, 0.5, -0.5 }, { 0.5, -0.5, -0.5 },
    }
    return Recipe(vertices, {
        { 3, 2, 1 }, { 1, 4, 3 }, { 2, 4, 1 }, { 3, 4, 2 },
    })
end

return FacetedSolidGeometry
