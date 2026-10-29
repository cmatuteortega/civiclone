-- The solids everything is built of, for the tracer (src/tracer.lua): the
-- ellipsoid, and hulls cut out by planes -- a box, an n-sided prism or
-- frustum (a pyramid is a frustum with no top), a gabled roof, and a peak of
-- rock on any polygon.
--
-- Each answers a part: `kind`, `planes` in its own space, how far that space
-- reaches (`reach`, for the screen box) and `at`, the map into the room. A
-- hull's own space is y from 0 to 1, x and z out to 1, so `at` is a scale to
-- the size wanted, then any turn, then a move to where it stands.

local T = require "src.tracer"
local A = T.Affine

local sqrt, cos, sin, abs = math.sqrt, math.cos, math.sin, math.abs

local Sh = {}

-- An ellipsoid of radii rx, ry, rz centred on (cx, cy, cz), turned by whatever
-- rotations follow (innermost first).
function Sh.ell(cx, cy, cz, rx, ry, rz, ...)
    local m = A.scale(rx, ry, rz)
    for _, r in ipairs({ ... }) do m = A.mul(r, m) end
    return { kind = "ell", at = A.mul(A.move(cx, cy, cz), m) }
end

-- An ellipsoid laid between two points, `r` thick: a leg, a spear, a trunk.
-- Its unit ball's x runs along it, so a print can tell the root from the tip.
function Sh.seg(x0, y0, z0, x1, y1, z1, r, r2)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local l = sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / l, dy / l, dz / l
    local ux, uy, uz = 0, 1, 0
    if abs(dy) > 0.9 then ux, uy, uz = 1, 0, 0 end
    local px, py, pz = dy * uz - dz * uy, dz * ux - dx * uz, dx * uy - dy * ux
    local pl = sqrt(px * px + py * py + pz * pz)
    px, py, pz = px / pl, py / pl, pz / pl
    local qx, qy, qz = py * dz - pz * dy, pz * dx - px * dz, px * dy - py * dx
    local h, s = l / 2, r2 or r
    return { kind = "ell", at = {
        dx * h, qx * r, px * s, (x0 + x1) / 2,
        dy * h, qy * r, py * s, (y0 + y1) / 2,
        dz * h, qz * r, pz * s, (z0 + z1) / 2,
    } }
end

-- n sides round the y axis, each side's plane `top` of the way in at y = 1:
-- 1 a prism, 0 a pyramid. `turn` is the angle of the first side's normal.
local function frustumPlanes(n, top, turn)
    local planes = {}
    for k = 0, n - 1 do
        local a = (turn or 0) + k * 2 * math.pi / n
        planes[#planes + 1] = { cos(a), 1 - top, sin(a), 1 }
    end
    planes[#planes + 1] = { 0, 1, 0, 1 }
    planes[#planes + 1] = { 0, -1, 0, 0 }
    return planes
end

-- A hull of planes in its own space, put through `at` (scale to sx, sy, sz,
-- turn by `h` about the vertical, stand at x, y, z).
local function placed(planes, reach, x, y, z, sx, sy, sz, h)
    local m = A.scale(sx, sy, sz)
    if h and h ~= 0 then m = A.mul(A.rotY(h), m) end
    return { kind = "hull", planes = planes, reach = reach, at = A.mul(A.move(x, y, z), m) }
end

local function corner(n) return 1 / cos(math.pi / n) end

-- An n-sided frustum standing on (x, y, z): `r` out to its sides, `ht` tall,
-- its top `top` the size of its foot.
function Sh.frustum(n, top, x, y, z, r, ht, h, turn)
    local c = corner(n)
    return placed(frustumPlanes(n, top, turn), { -c, c, 0, 1, -c, c }, x, y, z, r, ht, r, h)
end
function Sh.prism(n, x, y, z, r, ht, h, turn) return Sh.frustum(n, 1, x, y, z, r, ht, h, turn) end
function Sh.pyramid(n, x, y, z, r, ht, h, turn) return Sh.frustum(n, 0, x, y, z, r, ht, h, turn) end

-- A box standing on (x, y, z), w across (x), d deep (z), ht tall.
local BOX = { { 1, 0, 0, 1 }, { -1, 0, 0, 1 }, { 0, 0, 1, 1 }, { 0, 0, -1, 1 }, { 0, 1, 0, 1 }, { 0, -1, 0, 0 } }
function Sh.box(x, y, z, w, d, ht, h)
    return placed(BOX, { -1, 1, 0, 1, -1, 1 }, x, y, z, w / 2, ht, d / 2, h)
end

-- A gabled roof standing on (x, y, z): its ridge runs along x, w long, over a
-- house d deep, ht from eaves to ridge.
local ROOF = { { 1, 0, 0, 1 }, { -1, 0, 0, 1 }, { 0, 1, 1, 1 }, { 0, 1, -1, 1 }, { 0, -1, 0, 0 } }
function Sh.roof(x, y, z, w, d, ht, h)
    return placed(ROOF, { -1, 1, 0, 1, -1, 1 }, x, y, z, w / 2, ht, d / 2, h)
end

--- hulls in the room, for the map ---------------------------------------------

-- The plane through three room points, turned so `ix, iy, iz` is inside.
local function through(a, b, c, ix, iy, iz)
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local d = nx * a[1] + ny * a[2] + nz * a[3]
    if nx * ix + ny * iy + nz * iz > d then nx, ny, nz, d = -nx, -ny, -nz, -d end
    return { nx, ny, nz, d }
end

-- A peak: a polygon on the level y (room points { x, z }, in order round it,
-- convex) drawn up to the apex. Planes in the room.
function Sh.peak(poly, y, apex)
    local planes = {}
    local cx, cz = 0, 0
    for _, p in ipairs(poly) do cx, cz = cx + p[1] / #poly, cz + p[2] / #poly end
    local ix, iy, iz = (cx * 3 + apex[1]) / 4, (y * 3 + apex[2]) / 4, (cz * 3 + apex[3]) / 4
    local x0, x1, z0, z1 = apex[1], apex[1], apex[3], apex[3]
    for k, p in ipairs(poly) do
        local q = poly[k % #poly + 1]
        planes[#planes + 1] = through({ p[1], y, p[2] }, { q[1], y, q[2] }, apex, ix, iy, iz)
        x0, x1, z0, z1 = math.min(x0, p[1]), math.max(x1, p[1]), math.min(z0, p[2]), math.max(z1, p[2])
    end
    planes[#planes + 1] = { 0, -1, 0, -y }
    return { kind = "hull", planes = planes, box = { x0, x1, y, apex[2], z0, z1 } }
end

return Sh
