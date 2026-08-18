---@diagnostic disable: undefined-global

-- Merged procedural geometry for the storybook island. Hundreds of individually
-- bevelled cells become a handful of draw calls, preserving the small-block
-- craft and seams from the reference without sacrificing mobile performance.

local StorybookEnvironmentGeometry = {}
local Theme = require("CloudAtelierTheme")
local TAU = math.pi * 2
local SAFE_CUSTOM_GEOMETRY_VERTICES = 64000

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function DecodeColor(value)
    value = tonumber(value) or 0xffffff
    return math.floor(value / 0x10000) % 0x100 / 255,
        math.floor(value / 0x100) % 0x100 / 255,
        value % 0x100 / 255
end

local function Vertex(x, y, z)
    return { x, y, z }
end

local function Normalize(x, y, z)
    local length = math.max(0.000001, math.sqrt(x * x + y * y + z * z))
    return x / length, y / length, z / length
end

local function FaceColor(value, nx, ny, nz)
    local r, g, b = DecodeColor(value)
    local light = 0.70 + math.max(0, ny) * 0.27 + math.max(0, -nx) * 0.08
        + math.max(0, nz) * 0.05 - math.max(0, -ny) * 0.08
    return Color(Clamp(r * light, 0, 1), Clamp(g * light, 0, 1), Clamp(b * light, 0, 1), 1)
end

local function EmitTriangle(geometry, a, b, c, nx, ny, nz, color)
    local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local acx, acy, acz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local crossX = aby * acz - abz * acy
    local crossY = abz * acx - abx * acz
    local crossZ = abx * acy - aby * acx
    if crossX * nx + crossY * ny + crossZ * nz < 0 then b, c = c, b end
    local normal = Vector3(nx, ny, nz)
    for _, point in ipairs({ a, b, c }) do
        geometry:DefineVertex(Vector3(point[1], point[2], point[3]))
        geometry:DefineNormal(normal)
        geometry:DefineColor(color)
    end
end

local function EmitQuad(geometry, a, b, c, d, nx, ny, nz, color)
    EmitTriangle(geometry, a, b, c, nx, ny, nz, color)
    EmitTriangle(geometry, a, c, d, nx, ny, nz, color)
end

local function EmitBlock(geometry, block)
    local x0, x1 = block.x - block.sx * 0.5, block.x + block.sx * 0.5
    local y0, y1 = block.y - block.sy * 0.5, block.y + block.sy * 0.5
    local z0, z1 = block.z - block.sz * 0.5, block.z + block.sz * 0.5
    local bevel = math.min(block.bevel or 0.08, block.sx * 0.24, block.sy * 0.24, block.sz * 0.24)
    local rotationY = tonumber(block.ry or block.rotationY) or 0
    local cosine, sine = math.cos(rotationY), math.sin(rotationY)

    -- Environment cells used to be axis-aligned only. Bridge slabs then read
    -- as a row of diagonal checkerboard squares whenever two islands were not
    -- on the same axis. Rotate authored cells inside the merged geometry so a
    -- broken bridge can follow its route without creating extra scene nodes.
    local function Vertex(x, y, z)
        local dx, dz = x - block.x, z - block.z
        return {
            block.x + dx * cosine + dz * sine,
            y,
            block.z - dx * sine + dz * cosine,
        }
    end

    local function ColorFor(nx, ny, nz)
        nx, ny, nz = Normalize(nx, ny, nz)
        nx, nz = nx * cosine + nz * sine, -nx * sine + nz * cosine
        return nx, ny, nz, FaceColor(block.color, nx, ny, nz)
    end

    for _, face in ipairs({
        { 1, 0, 0, Vertex(x1, y0 + bevel, z0 + bevel), Vertex(x1, y1 - bevel, z0 + bevel),
            Vertex(x1, y1 - bevel, z1 - bevel), Vertex(x1, y0 + bevel, z1 - bevel) },
        { -1, 0, 0, Vertex(x0, y0 + bevel, z1 - bevel), Vertex(x0, y1 - bevel, z1 - bevel),
            Vertex(x0, y1 - bevel, z0 + bevel), Vertex(x0, y0 + bevel, z0 + bevel) },
        { 0, 1, 0, Vertex(x0 + bevel, y1, z0 + bevel), Vertex(x0 + bevel, y1, z1 - bevel),
            Vertex(x1 - bevel, y1, z1 - bevel), Vertex(x1 - bevel, y1, z0 + bevel) },
        { 0, -1, 0, Vertex(x0 + bevel, y0, z1 - bevel), Vertex(x0 + bevel, y0, z0 + bevel),
            Vertex(x1 - bevel, y0, z0 + bevel), Vertex(x1 - bevel, y0, z1 - bevel) },
        { 0, 0, 1, Vertex(x0 + bevel, y0 + bevel, z1), Vertex(x1 - bevel, y0 + bevel, z1),
            Vertex(x1 - bevel, y1 - bevel, z1), Vertex(x0 + bevel, y1 - bevel, z1) },
        { 0, 0, -1, Vertex(x1 - bevel, y0 + bevel, z0), Vertex(x0 + bevel, y0 + bevel, z0),
            Vertex(x0 + bevel, y1 - bevel, z0), Vertex(x1 - bevel, y1 - bevel, z0) },
    }) do
        local nx, ny, nz, color = ColorFor(face[1], face[2], face[3])
        EmitQuad(geometry, face[4], face[5], face[6], face[7], nx, ny, nz, color)
    end

    for _, sy in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            local yf, zf = sy < 0 and y0 or y1, sz < 0 and z0 or z1
            local nx, ny, nz, color = ColorFor(0, sy, sz)
            EmitQuad(geometry,
                Vertex(x0 + bevel, yf, zf - sz * bevel), Vertex(x1 - bevel, yf, zf - sz * bevel),
                Vertex(x1 - bevel, yf - sy * bevel, zf), Vertex(x0 + bevel, yf - sy * bevel, zf),
                nx, ny, nz, color)
        end
    end
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            local xf, zf = sx < 0 and x0 or x1, sz < 0 and z0 or z1
            local nx, ny, nz, color = ColorFor(sx, 0, sz)
            EmitQuad(geometry,
                Vertex(xf, y0 + bevel, zf - sz * bevel), Vertex(xf, y1 - bevel, zf - sz * bevel),
                Vertex(xf - sx * bevel, y1 - bevel, zf), Vertex(xf - sx * bevel, y0 + bevel, zf),
                nx, ny, nz, color)
        end
    end
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            local xf, yf = sx < 0 and x0 or x1, sy < 0 and y0 or y1
            local nx, ny, nz, color = ColorFor(sx, sy, 0)
            EmitQuad(geometry,
                Vertex(xf, yf - sy * bevel, z0 + bevel), Vertex(xf, yf - sy * bevel, z1 - bevel),
                Vertex(xf - sx * bevel, yf, z1 - bevel), Vertex(xf - sx * bevel, yf, z0 + bevel),
                nx, ny, nz, color)
        end
    end

    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                local xf, yf, zf = sx < 0 and x0 or x1, sy < 0 and y0 or y1, sz < 0 and z0 or z1
                local nx, ny, nz, color = ColorFor(sx, sy, sz)
                EmitTriangle(geometry,
                    Vertex(xf, yf - sy * bevel, zf - sz * bevel),
                    Vertex(xf - sx * bevel, yf, zf - sz * bevel),
                    Vertex(xf - sx * bevel, yf - sy * bevel, zf),
                    nx, ny, nz, color)
            end
        end
    end
end

local function BuildBlocks(self, node, nativeMaterial)
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    for _, block in ipairs(self.blocks) do EmitBlock(geometry, block) end
    geometry:Commit()
    if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
    return geometry
end

local function MixColor(bottom, top, amount)
    local br, bg, bb = DecodeColor(bottom)
    local tr, tg, tb = DecodeColor(top)
    amount = Clamp(amount, 0, 1)
    return Color(br + (tr - br) * amount, bg + (tg - bg) * amount, bb + (tb - bb) * amount, 1)
end

local function CloudPoint(lobe, ux, uy, uz)
    local nx, ny, nz = Normalize(ux / lobe.rx, uy / lobe.ry, uz / lobe.rz)
    return {
        position = Vertex(lobe.x + ux, lobe.y + uy, lobe.z + uz),
        normal = { nx, ny, nz },
        color = MixColor(lobe.bottom, lobe.top, (uy / lobe.ry + 1) * 0.5),
    }
end

local function EmitSmoothTriangle(geometry, a, b, c)
    local abx, aby, abz = b.position[1] - a.position[1], b.position[2] - a.position[2], b.position[3] - a.position[3]
    local acx, acy, acz = c.position[1] - a.position[1], c.position[2] - a.position[2], c.position[3] - a.position[3]
    local crossX = aby * acz - abz * acy
    local crossY = abz * acx - abx * acz
    local crossZ = abx * acy - aby * acx
    local avgX = a.normal[1] + b.normal[1] + c.normal[1]
    local avgY = a.normal[2] + b.normal[2] + c.normal[2]
    local avgZ = a.normal[3] + b.normal[3] + c.normal[3]
    if crossX * avgX + crossY * avgY + crossZ * avgZ < 0 then b, c = c, b end
    for _, vertex in ipairs({ a, b, c }) do
        geometry:DefineVertex(Vector3(vertex.position[1], vertex.position[2], vertex.position[3]))
        geometry:DefineNormal(Vector3(vertex.normal[1], vertex.normal[2], vertex.normal[3]))
        geometry:DefineColor(vertex.color)
    end
end

local function EmitLobe(geometry, lobe, latitudeSegments, longitudeSegments)
    for latitude = 0, latitudeSegments - 1 do
        local phi0, phi1 = math.pi * latitude / latitudeSegments, math.pi * (latitude + 1) / latitudeSegments
        local y0, y1 = math.cos(phi0), math.cos(phi1)
        local ring0, ring1 = math.sin(phi0), math.sin(phi1)
        for longitude = 0, longitudeSegments - 1 do
            local theta0 = TAU * longitude / longitudeSegments
            local theta1 = TAU * (longitude + 1) / longitudeSegments
            local a = CloudPoint(lobe, math.cos(theta0) * ring0 * lobe.rx, y0 * lobe.ry, math.sin(theta0) * ring0 * lobe.rz)
            local b = CloudPoint(lobe, math.cos(theta0) * ring1 * lobe.rx, y1 * lobe.ry, math.sin(theta0) * ring1 * lobe.rz)
            local c = CloudPoint(lobe, math.cos(theta1) * ring1 * lobe.rx, y1 * lobe.ry, math.sin(theta1) * ring1 * lobe.rz)
            local d = CloudPoint(lobe, math.cos(theta1) * ring0 * lobe.rx, y0 * lobe.ry, math.sin(theta1) * ring0 * lobe.rz)
            EmitSmoothTriangle(geometry, a, b, c)
            EmitSmoothTriangle(geometry, a, c, d)
        end
    end
end

local function BuildClouds(self, node, nativeMaterial)
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    for _, lobe in ipairs(self.lobes) do
        EmitLobe(geometry, lobe, self.latitudeSegments, self.longitudeSegments)
    end
    geometry:Commit()
    if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
    return geometry
end

local function SkyPoint(radius, ux, uy, uz, sea, bottom, horizon, middle, top)
    local color
    if uy < -0.34 then
        -- Only the lowest viewing angles reveal the turquoise ocean layer.
        color = MixColor(sea, bottom, (uy + 1) / 0.66)
    elseif uy < 0 then
        color = MixColor(bottom, horizon, (uy + 0.34) / 0.34)
    elseif uy < 0.38 then
        color = MixColor(horizon, middle, uy / 0.38)
    else
        color = MixColor(middle, top, (uy - 0.38) / 0.62)
    end
    return {
        position = Vertex(ux * radius, uy * radius, uz * radius),
        normal = { -ux, -uy, -uz },
        color = color,
    }
end

local function BuildSky(self, node, nativeMaterial)
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    for latitude = 0, self.latitudeSegments - 1 do
        local phi0 = math.pi * latitude / self.latitudeSegments
        local phi1 = math.pi * (latitude + 1) / self.latitudeSegments
        local y0, y1 = math.cos(phi0), math.cos(phi1)
        local ring0, ring1 = math.sin(phi0), math.sin(phi1)
        for longitude = 0, self.longitudeSegments - 1 do
            local theta0 = TAU * longitude / self.longitudeSegments
            local theta1 = TAU * (longitude + 1) / self.longitudeSegments
            local a = SkyPoint(self.radius, math.cos(theta0) * ring0, y0, math.sin(theta0) * ring0,
                self.sea, self.bottom, self.horizon, self.middle, self.top)
            local b = SkyPoint(self.radius, math.cos(theta0) * ring1, y1, math.sin(theta0) * ring1,
                self.sea, self.bottom, self.horizon, self.middle, self.top)
            local c = SkyPoint(self.radius, math.cos(theta1) * ring1, y1, math.sin(theta1) * ring1,
                self.sea, self.bottom, self.horizon, self.middle, self.top)
            local d = SkyPoint(self.radius, math.cos(theta1) * ring0, y0, math.sin(theta1) * ring0,
                self.sea, self.bottom, self.horizon, self.middle, self.top)
            EmitSmoothTriangle(geometry, a, b, c)
            EmitSmoothTriangle(geometry, a, c, d)
        end
    end
    geometry:Commit()
    if nativeMaterial then geometry:SetMaterial(nativeMaterial) end
    return geometry
end

function StorybookEnvironmentGeometry.Blocks(blocks)
    return { _kind = "geometry", blocks = blocks or {}, build = BuildBlocks }
end

function StorybookEnvironmentGeometry.Clouds(lobes, latitudeSegments, longitudeSegments)
    return {
        _kind = "geometry", lobes = lobes or {}, build = BuildClouds,
        latitudeSegments = latitudeSegments or 8,
        longitudeSegments = longitudeSegments or 14,
    }
end

-- Urho's mobile CustomGeometry path uses 16-bit vertex indices. Keep every
-- procedural cloud mesh below that ceiling while preserving one shared
-- material and the same deterministic lobe order across chunks.
function StorybookEnvironmentGeometry.CloudChunks(lobes, latitudeSegments, longitudeSegments)
    lobes = lobes or {}
    latitudeSegments = math.max(1, math.floor(tonumber(latitudeSegments) or 8))
    longitudeSegments = math.max(1, math.floor(tonumber(longitudeSegments) or 14))
    local verticesPerLobe = latitudeSegments * longitudeSegments * 6
    local chunkSize = math.max(1, math.floor(SAFE_CUSTOM_GEOMETRY_VERTICES / verticesPerLobe))
    local chunks = {}
    for first = 1, #lobes, chunkSize do
        local chunk = {}
        for index = first, math.min(#lobes, first + chunkSize - 1) do
            chunk[#chunk + 1] = lobes[index]
        end
        chunks[#chunks + 1] = chunk
    end
    return chunks, chunkSize
end

function StorybookEnvironmentGeometry.SkyDome(top, middle, horizon, bottom, sea, radius)
    return {
        _kind = "geometry", build = BuildSky,
        top = top or Theme.ENVIRONMENT.sky.top,
        middle = middle or Theme.ENVIRONMENT.sky.middle,
        horizon = horizon or Theme.ENVIRONMENT.sky.horizon,
        bottom = bottom or Theme.ENVIRONMENT.sky.bottom,
        sea = sea or Theme.ENVIRONMENT.sky.sea,
        radius = radius or 180,
        latitudeSegments = 16,
        longitudeSegments = 32,
    }
end

return StorybookEnvironmentGeometry
