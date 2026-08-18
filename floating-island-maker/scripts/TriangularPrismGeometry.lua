---@diagnostic disable: undefined-global

-- Normalized triangular prism for architectural wedges and roofs. The
-- triangle occupies X/Y and is extruded along Z, so all three editor size
-- fields map to its exact local bounding box.
local TriangularPrismGeometry = {}

local function Build(self, node, nativeMaterial)
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)

    local function Emit(vertex, normal, u, v)
        geometry:DefineVertex(Vector3(vertex[1], vertex[2], vertex[3]))
        geometry:DefineNormal(Vector3(normal[1], normal[2], normal[3]))
        geometry:DefineTexCoord(Vector2(u, v))
    end

    local function Triangle(a, b, c, normal)
        Emit(a, normal, 0, 0)
        Emit(b, normal, 1, 0)
        Emit(c, normal, 0.5, 1)
    end

    local function Quad(a, b, c, d, normal)
        Emit(a, normal, 0, 0)
        Emit(b, normal, 1, 0)
        Emit(c, normal, 1, 1)
        Emit(a, normal, 0, 0)
        Emit(c, normal, 1, 1)
        Emit(d, normal, 0, 1)
    end

    local a = { -0.5, -0.5, -0.5 }
    local b = { 0.5, -0.5, -0.5 }
    local c = { 0, 0.5, -0.5 }
    local d = { -0.5, -0.5, 0.5 }
    local e = { 0.5, -0.5, 0.5 }
    local f = { 0, 0.5, 0.5 }
    local slope = 1 / math.sqrt(1.25)
    local rise = 0.5 / math.sqrt(1.25)

    Triangle(d, e, f, { 0, 0, 1 })
    Triangle(a, c, b, { 0, 0, -1 })
    Quad(a, b, e, d, { 0, -1, 0 })
    Quad(a, d, f, c, { -slope, rise, 0 })
    Quad(b, c, f, e, { slope, rise, 0 })

    geometry:Commit()
    if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
    return geometry
end

function TriangularPrismGeometry.new()
    return {
        _kind = "geometry",
        parameters = { width = 1, height = 1, depth = 1 },
        build = Build,
    }
end

return TriangularPrismGeometry
