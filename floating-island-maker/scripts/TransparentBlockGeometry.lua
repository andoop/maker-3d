---@diagnostic disable: undefined-global

-- A lightweight cube recipe for transparent blocks. Adjacent blocks of the
-- same transparent material can omit fully covered internal faces, avoiding
-- the dark doubled surface that otherwise makes water/glass look segmented.

local TransparentBlockGeometry = {}

local FACES = {
    ["x+"] = {
        normal = { 1, 0, 0 },
        vertices = {
            { 0.5, -0.5, -0.5, 0, 1 }, { 0.5, 0.5, -0.5, 0, 0 }, { 0.5, 0.5, 0.5, 1, 0 },
            { 0.5, -0.5, -0.5, 0, 1 }, { 0.5, 0.5, 0.5, 1, 0 }, { 0.5, -0.5, 0.5, 1, 1 },
        },
    },
    ["x-"] = {
        normal = { -1, 0, 0 },
        vertices = {
            { -0.5, -0.5, 0.5, 0, 1 }, { -0.5, 0.5, 0.5, 0, 0 }, { -0.5, 0.5, -0.5, 1, 0 },
            { -0.5, -0.5, 0.5, 0, 1 }, { -0.5, 0.5, -0.5, 1, 0 }, { -0.5, -0.5, -0.5, 1, 1 },
        },
    },
    ["y+"] = {
        normal = { 0, 1, 0 },
        vertices = {
            { -0.5, 0.5, -0.5, 0, 1 }, { -0.5, 0.5, 0.5, 0, 0 }, { 0.5, 0.5, 0.5, 1, 0 },
            { -0.5, 0.5, -0.5, 0, 1 }, { 0.5, 0.5, 0.5, 1, 0 }, { 0.5, 0.5, -0.5, 1, 1 },
        },
    },
    ["y-"] = {
        normal = { 0, -1, 0 },
        vertices = {
            { -0.5, -0.5, 0.5, 0, 1 }, { -0.5, -0.5, -0.5, 0, 0 }, { 0.5, -0.5, -0.5, 1, 0 },
            { -0.5, -0.5, 0.5, 0, 1 }, { 0.5, -0.5, -0.5, 1, 0 }, { 0.5, -0.5, 0.5, 1, 1 },
        },
    },
    ["z+"] = {
        normal = { 0, 0, 1 },
        vertices = {
            { -0.5, -0.5, 0.5, 0, 1 }, { 0.5, -0.5, 0.5, 1, 1 }, { 0.5, 0.5, 0.5, 1, 0 },
            { -0.5, -0.5, 0.5, 0, 1 }, { 0.5, 0.5, 0.5, 1, 0 }, { -0.5, 0.5, 0.5, 0, 0 },
        },
    },
    ["z-"] = {
        normal = { 0, 0, -1 },
        vertices = {
            { 0.5, -0.5, -0.5, 0, 1 }, { -0.5, -0.5, -0.5, 1, 1 }, { -0.5, 0.5, -0.5, 1, 0 },
            { 0.5, -0.5, -0.5, 0, 1 }, { -0.5, 0.5, -0.5, 1, 0 }, { 0.5, 0.5, -0.5, 0, 0 },
        },
    },
}

local FACE_ORDER = { "x+", "x-", "y+", "y-", "z+", "z-" }

local function Build(self, node, nativeMaterial)
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local vertexColor = Color(1, 1, 1, self.alpha)
    local emitted = 0
    for _, key in ipairs(FACE_ORDER) do
        if not self.hiddenFaces[key] then
            local face = FACES[key]
            local normal = Vector3(face.normal[1], face.normal[2], face.normal[3])
            for _, vertex in ipairs(face.vertices) do
                geometry:DefineVertex(Vector3(vertex[1], vertex[2], vertex[3]))
                geometry:DefineNormal(normal)
                geometry:DefineTexCoord(Vector2(vertex[4], vertex[5]))
                geometry:DefineColor(vertexColor)
                emitted = emitted + 1
            end
        end
    end
    -- A fully enclosed cell has no visible surface. Keep a zero-area triangle
    -- so CustomGeometry can still commit a valid (but invisible) drawable.
    if emitted == 0 then
        for _ = 1, 3 do
            geometry:DefineVertex(Vector3(0, 0, 0))
            geometry:DefineNormal(Vector3(0, 1, 0))
            geometry:DefineTexCoord(Vector2(0, 0))
            geometry:DefineColor(Color(1, 1, 1, 0))
        end
    end
    geometry:Commit()
    if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
    return geometry
end

function TransparentBlockGeometry.new(hiddenFaces, alpha)
    return {
        hiddenFaces = hiddenFaces or {},
        alpha = alpha or 1,
        build = Build,
    }
end

return TransparentBlockGeometry
