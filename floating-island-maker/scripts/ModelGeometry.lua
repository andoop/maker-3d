-- Engine-free geometry and first-person collision semantics shared by asset
-- normalization, audits, runtime collision and tests.

local Catalog = require("BlockCatalog")

local ModelGeometry = {}

local DECORATIVE_MATERIALS = {
    leaf = true, fabric = true, crystal = true, glow = true, fire = true,
}

local function Contains(name, keyword)
    return tostring(name or ""):find(keyword, 1, true) ~= nil
end

function ModelGeometry.Position(source)
    local p = source.position or {}
    return tonumber(source.x or p[1]) or 0,
        tonumber(source.y or p[2]) or 0.5,
        tonumber(source.z or p[3]) or 0
end

function ModelGeometry.Size(source)
    local s = source.size or {}
    return math.max(0.05, tonumber(source.sx or s[1]) or 1),
        math.max(0.05, tonumber(source.sy or s[2]) or 1),
        math.max(0.05, tonumber(source.sz or s[3]) or 1)
end

function ModelGeometry.Rotation(source)
    local r = source.rotation or {}
    return tonumber(source.rx or r[1]) or 0,
        tonumber(source.ry or r[2]) or 0,
        tonumber(source.rz or r[3]) or 0
end

function ModelGeometry.RotatedHalfExtents(source)
    local sx, sy, sz = ModelGeometry.Size(source)
    local shape = Catalog.FindShape(source.shapeId or source.shape)
    sx, sy, sz = sx * shape.bounds[1], sy * shape.bounds[2], sz * shape.bounds[3]
    local rx, ry, rz = ModelGeometry.Rotation(source)
    local cx, sxn = math.cos(rx), math.sin(rx)
    local cy, syn = math.cos(ry), math.sin(ry)
    local cz, szn = math.cos(rz), math.sin(rz)
    local m11 = cy * cz
    local m12 = cz * syn * sxn - szn * cx
    local m13 = cz * syn * cx + szn * sxn
    local m21 = cy * szn
    local m22 = szn * syn * sxn + cz * cx
    local m23 = szn * syn * cx - cz * sxn
    local m31 = -syn
    local m32 = cy * sxn
    local m33 = cy * cx
    return {
        (math.abs(m11) * sx + math.abs(m12) * sy + math.abs(m13) * sz) * 0.5,
        (math.abs(m21) * sx + math.abs(m22) * sy + math.abs(m23) * sz) * 0.5,
        (math.abs(m31) * sx + math.abs(m32) * sy + math.abs(m33) * sz) * 0.5,
    }
end

function ModelGeometry.IsWalkSurface(source)
    local materialId = tostring(source.materialId or source.material or "")
    if materialId == "water" or materialId == "fire" then return false end
    local name = tostring(source.name or "")
    for _, keyword in ipairs({
        "地板", "地砖", "地面", "地台", "台地", "平台", "基台", "地基",
        "岩台", "庭院", "露台", "踏步", "台阶", "阶梯", "连续梯", "步道", "路面", "木板",
    }) do
        if Contains(name, keyword) then return true end
    end
    if tostring(source.type or "") == "base" then return true end
    local sx, sy, sz = ModelGeometry.Size(source)
    return sy <= math.min(sx, sz) * 0.4 and sx >= 0.5 and sz >= 0.5
end

function ModelGeometry.CollisionRole(source)
    local explicit = tostring(source.collisionRole or "")
    if explicit == "solid" or explicit == "surface" or explicit == "decorative" or explicit == "fluid" then
        return explicit
    end
    local materialId = tostring(source.materialId or source.material or "solid")
    local name = tostring(source.name or "")
    if materialId == "water" then return "fluid" end
    if DECORATIVE_MATERIALS[materialId] then return "decorative" end
    if materialId == "glass" and (Contains(name, "穹顶") or Contains(name, "屋盖")) then
        return "decorative"
    end
    if Catalog.FindShape(source.shapeId or source.shape).id == "torus" then return "decorative" end
    if ModelGeometry.IsWalkSurface(source) then return "surface" end
    return "solid"
end

function ModelGeometry.ShouldCastShadow(source)
    if ModelGeometry.CollisionRole(source) == "decorative" then return false end
    if Catalog.FindMaterial(source.materialId or source.material).transparent then return false end
    local sx, sy, sz = ModelGeometry.Size(source)
    return sx * sy * sz >= 0.08 or math.max(sx, sy, sz) >= 2.0
end

return ModelGeometry
