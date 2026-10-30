-- The tracer: underroot's method (src/tracer.lua there), turned to look at a
-- hex map the way a strategy game does -- from the south, tilted down.
--
-- Underroot's camera was isometric, turned 45 degrees to lay square tiles down
-- as diamonds. Hexes want the map read in rows, so here the camera faces
-- north and only tilts: 40 degrees down, which lays a hex down a little
-- squashed and shows the two faces of its side that look south. It stays
-- orthographic, and that is still what everything rests on: with no
-- perspective a picture of a thing is the same picture wherever it stands, so
-- the map is traced once and every warrior and city is traced once per pose
-- and kept.
--
-- Room space: x east (screen right), z south (towards you and down the
-- screen), y up. One unit of the room is two pixels across: the room was laid
-- out a unit to the pixel, and is traced at twice that for the detail.
--
-- Every pixel is traced once at its centre and its colour is *chosen* off a
-- ramp of palette keys, never blended. Then the two passes that make it read
-- as drawn rather than rendered: creases (a step down to the ramp's shadow
-- where neighbouring normals of one material disagree) and ink (round the
-- silhouette, and along any step in depth onto another part).
--
-- Two kinds of solid: the ellipsoid (a unit ball through an affine map), as in
-- underroot, and new here the hull -- a convex solid cut out by planes, which
-- is a hex prism, a pyramid of rock, a house with its gabled roof.

local ffi = require "ffi"
local Palette = require "src.palette"

local sqrt, cos, sin, max, min, floor, ceil = math.sqrt, math.cos, math.sin, math.max, math.min, math.floor, math.ceil

local T = {}

local ELEV = math.rad(40)
local CE, SE = cos(ELEV), sin(ELEV)
T.CE, T.SE = CE, SE
local UNIT = 0.5
T.UNIT = UNIT

-- The camera's three axes in the room: screen right, screen up, towards you.
local RX, RY, RZ = 1, 0, 0
local UX, UY, UZ = 0, CE, -SE
local NX, NY, NZ = 0, SE, CE
-- Every ray of every picture goes the same way: away from you.
local DX, DY, DZ = -NX, -NY, -NZ
T.DX, T.DY, T.DZ = DX, DY, DZ

-- The lamp: up, to the left of the screen and a little towards you, so every
-- flat top is lit, the south-west face of a hex is in the middle of its ramp
-- and the south-east face in shade -- the three tones a block is read by.
local LX, LY, LZ
do
    local a, b, e = 0.5, 0.75, 0.45
    LX, LY, LZ = -a * RX + e * NX, b + e * NY, -a * RZ + e * NZ
    local n = sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local HX, HY, HZ = LX + NX, LY + NY, LZ + NZ
do
    local n = sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end

-- The lamp and its half-way vector, for the light of the hour to be laid
-- against (src/ui/daylight.lua).
T.LAMP, T.HALF = { LX, LY, LZ }, { HX, HY, HZ }

local CREASE = 0.55

--- palette keys as small numbers ------------------------------------------------

-- 0 is "nothing here". Buffers hold these rather than strings so they can live in
-- ffi arrays the size of the world.
T.KEYS, T.IDX, T.RGB = {}, {}, {}
for i, row in ipairs(Palette.list) do
    T.KEYS[i], T.IDX[row[1]], T.RGB[i] = row[1], i, Palette.key[row[1]]
end
local IDX = T.IDX

-- Remaps a picture is laid down through: one step darker (fog, a shadow), two,
-- one step lighter (a highlight), and every lit key to white (the frame a
-- thing is hit).
T.DARKER, T.DARKER2, T.LIGHTER, T.FLASH, T.SAME = {}, {}, {}, {}, {}
for i, k in ipairs(T.KEYS) do
    T.SAME[i] = i
    T.DARKER[i] = IDX[Palette.darker[k]]
    T.LIGHTER[i] = IDX[Palette.lighter[k]]
end
for i = 1, #T.KEYS do T.DARKER2[i] = T.DARKER[T.DARKER[i]] end
for i, k in ipairs(T.KEYS) do T.FLASH[i] = (k == "o" or k == "u") and i or IDX.w end

--- projection ------------------------------------------------------------------

-- Room point to screen pixel (i right, j down) and depth (bigger is nearer).
function T.project(x, y, z)
    return (x * RX + y * RY + z * RZ) / UNIT,
        -(x * UX + y * UY + z * UZ) / UNIT,
        x * NX + y * NY + z * NZ
end

-- Where the ray through screen point (i, j) starts, on the plane `back` deep.
function T.origin(i, j, back)
    local a, b = i * UNIT, -j * UNIT
    return a * RX + b * UX + back * NX, a * RY + b * UY + back * NY, a * RZ + b * UZ + back * NZ
end

-- Where the ray through screen point (i, j) crosses the level y = h.
function T.onLevel(i, j, h)
    local ox, oy, oz = T.origin(i, j, 0)
    local t = (h - oy) / DY
    return ox + DX * t, oz + DZ * t
end

--- light and ramps -------------------------------------------------------------

-- A ramp is glint, lit, middle, shadow (as key indices).
local function ramp(g, l, m, s) return { IDX[g], IDX[l], IDX[m], IDX[s] } end
T.ramp = ramp

function T.diffuse(nx, ny, nz)
    return nx * LX + ny * LY + nz * LZ
end

-- Answers key index and the ramp level it came off (1 glint .. 4 shadow).
function T.shade(r, nx, ny, nz)
    local d = nx * LX + ny * LY + nz * LZ
    local h = nx * HX + ny * HY + nz * HZ
    if h > 0 and h ^ 40 > 0.6 then return r[1], 1 end
    if d > 0.78 then return r[2], 2 end
    if d > 0.2 then return r[3], 3 end
    if ny < 0 and d > 0.02 then return r[3], 3 end
    return r[4], 4
end

--- buffers ---------------------------------------------------------------------

-- One pixel's worth of everything the two passes need. `lev` 0 marks a printed
-- pixel (a joint, a window, a furrow) that a crease must not touch. `raw` is
-- the picture before the passes, kept so a corner of it can be traced again
-- and finished again (see T.finish's region).
function T.buffer(w, h)
    local n = w * h
    return {
        w = w, h = h,
        raw = ffi.new("uint8_t[?]", n),
        key = ffi.new("uint8_t[?]", n),
        lev = ffi.new("uint8_t[?]", n),
        shd = ffi.new("uint8_t[?]", n), -- the ramp's shadow key, for creases
        part = ffi.new("int16_t[?]", n),
        mat = ffi.new("int16_t[?]", n),
        dep = ffi.new("float[?]", n),
        dif = ffi.new("float[?]", n),
        nx = ffi.new("float[?]", n),
        ny = ffi.new("float[?]", n),
        nz = ffi.new("float[?]", n),
    }
end

-- Creases, then ink, both decided off the untouched picture (`raw`), written
-- into `key`. Only the pixels from (i0, j0) to (i1, j1) if a region is given.
function T.finish(b, edge, i0, j0, i1, j1)
    local w, h = b.w, b.h
    i0, j0 = max(0, i0 or 0), max(0, j0 or 0)
    i1, j1 = min(w - 1, i1 or w - 1), min(h - 1, j1 or h - 1)
    local raw, out, lev, shd, part, mat, dep, dif = b.raw, b.key, b.lev, b.shd, b.part, b.mat, b.dep, b.dif
    local nx, ny, nz = b.nx, b.ny, b.nz
    -- `inked`, if the buffer keeps one, says which pixels the ink was laid on.
    local inked = b.inked
    for j = j0, j1 do
        for i = i0, i1 do
            out[j * w + i] = raw[j * w + i]
            if inked then inked[j * w + i] = 0 end
        end
    end

    -- Each pair is looked at once, from its left or upper pixel; a region
    -- reaches one pixel back so the pairs across its edge are seen too.
    local function crease(p, q)
        if raw[q] == 0 or mat[p] ~= mat[q] then return end
        if nx[p] * nx[q] + ny[p] * ny[q] + nz[p] * nz[q] >= CREASE then return end
        local r = dif[p] < dif[q] and p or q
        if lev[r] == 2 or lev[r] == 3 then out[r] = shd[r] end
    end
    for j = max(0, j0 - 1), j1 do
        for i = max(0, i0 - 1), i1 do
            local p = j * w + i
            if raw[p] ~= 0 then
                if i < w - 1 then crease(p, p + 1) end
                if j < h - 1 then crease(p, p + w) end
            end
        end
    end

    local INK = IDX.o
    local function inked(p, q)
        if raw[q] == 0 then return true end
        return part[q] ~= part[p] and dep[p] - dep[q] > edge
    end
    for j = j0, j1 do
        for i = i0, i1 do
            local p = j * w + i
            if raw[p] ~= 0 then
                local rim = i == 0 or i == w - 1 or j == 0 or j == h - 1
                if (rim and not b.open) or (not rim and (inked(p, p - 1) or inked(p, p + 1)
                    or inked(p, p - w) or inked(p, p + w))) then
                    out[p] = INK
                    if b.inked then b.inked[p] = 1 end
                end
            end
        end
    end
end

--- affine maps -----------------------------------------------------------------

-- Twelve numbers, row-major: the 3x3 and then the shift, per row.
local A = {}
T.Affine = A

function A.id() return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 } end
function A.move(x, y, z) return { 1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z } end
function A.scale(x, y, z) return { x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0 } end
function A.rotY(a)
    local c, s = cos(a), sin(a)
    return { c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0 }
end
function A.rotZ(a)
    local c, s = cos(a), sin(a)
    return { c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0 }
end
function A.rotX(a)
    local c, s = cos(a), sin(a)
    return { 1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0 }
end

function A.mul(a, b, ...)
    local r = {}
    for row = 0, 2 do
        local a1, a2, a3, a4 = a[row * 4 + 1], a[row * 4 + 2], a[row * 4 + 3], a[row * 4 + 4]
        for col = 1, 4 do
            r[row * 4 + col] = a1 * b[col] + a2 * b[4 + col] + a3 * b[8 + col]
        end
        r[row * 4 + 4] = r[row * 4 + 4] + a4
    end
    if ... then return A.mul(r, ...) end
    return r
end

function A.inv(m)
    local a, b, c, d, e, f, g, h, i = m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]
    local A1, B1, C1 = e * i - f * h, -(d * i - f * g), d * h - e * g
    local det = a * A1 + b * B1 + c * C1
    local r = {
        A1 / det, -(b * i - c * h) / det, (b * f - c * e) / det, 0,
        B1 / det, (a * i - c * g) / det, -(a * f - c * d) / det, 0,
        C1 / det, -(a * h - b * g) / det, (a * e - b * d) / det, 0,
    }
    for row = 0, 2 do
        r[row * 4 + 4] = -(r[row * 4 + 1] * m[4] + r[row * 4 + 2] * m[8] + r[row * 4 + 3] * m[12])
    end
    return r
end

--- hitting a solid ---------------------------------------------------------------

-- A solid is `kind` "ell" or "hull" and an `at` map from its own space into the
-- room (a hull may leave it out and give its planes in the room). `prepare`
-- works out, once, the ray's way in the solid's own space; `hit` answers the
-- nearest t along the ray from room point (ox, oy, oz), the room normal there,
-- and the hit point in the solid's own space (for prints), or nothing.
function T.prepare(s)
    if s.at then
        local v = A.inv(s.at)
        s.inv = v
        s.bx = v[1] * DX + v[2] * DY + v[3] * DZ
        s.by = v[5] * DX + v[6] * DY + v[7] * DZ
        s.bz = v[9] * DX + v[10] * DY + v[11] * DZ
    else
        s.bx, s.by, s.bz = DX, DY, DZ
    end
    s.qa = s.bx * s.bx + s.by * s.by + s.bz * s.bz
    if s.kind == "hull" then
        -- Each plane's n . way, which is the same for every ray.
        local nd = {}
        for k, p in ipairs(s.planes) do nd[k] = p[1] * s.bx + p[2] * s.by + p[3] * s.bz end
        s.nd = nd
    end
end

local function toLocal(s, ox, oy, oz)
    local v = s.inv
    if not v then return ox, oy, oz end
    return v[1] * ox + v[2] * oy + v[3] * oz + v[4],
        v[5] * ox + v[6] * oy + v[7] * oz + v[8],
        v[9] * ox + v[10] * oy + v[11] * oz + v[12]
end

-- A normal from the solid's own space back into the room: through the
-- transpose of the same inverse.
local function toRoomNormal(s, nx, ny, nz)
    local v = s.inv
    if v then
        nx, ny, nz = v[1] * nx + v[5] * ny + v[9] * nz, v[2] * nx + v[6] * ny + v[10] * nz,
            v[3] * nx + v[7] * ny + v[11] * nz
    end
    local l = sqrt(nx * nx + ny * ny + nz * nz)
    return nx / l, ny / l, nz / l
end

local function hitEll(s, ox, oy, oz)
    local ax, ay, az = toLocal(s, ox, oy, oz)
    local bx, by, bz = s.bx, s.by, s.bz
    local qb = ax * bx + ay * by + az * bz
    local qc = ax * ax + ay * ay + az * az - 1
    local d = qb * qb - s.qa * qc
    if d < 0 then return end
    local t = (-qb - sqrt(d)) / s.qa
    local ux, uy, uz = ax + t * bx, ay + t * by, az + t * bz
    local nx, ny, nz = toRoomNormal(s, ux, uy, uz)
    return t, nx, ny, nz, ux, uy, uz
end

-- A hull: each plane is { nx, ny, nz, d }, inside where n . p <= d. The ray is
-- in while it is inside every plane; it enters through the plane it crosses
-- last on the way in.
local function hitHull(s, ox, oy, oz)
    local ax, ay, az = toLocal(s, ox, oy, oz)
    local tin, tout, best = -math.huge, math.huge, nil
    local planes, nd = s.planes, s.nd
    for k = 1, #planes do
        local p = planes[k]
        local num = p[4] - (p[1] * ax + p[2] * ay + p[3] * az)
        local den = nd[k]
        if den < -1e-9 then
            local t = num / den
            if t > tin then tin, best = t, p end
        elseif den > 1e-9 then
            local t = num / den
            if t < tout then tout = t end
        elseif num < 0 then
            return
        end
        if tin > tout then return end
    end
    if not best then return end
    local nx, ny, nz = toRoomNormal(s, best[1], best[2], best[3])
    return tin, nx, ny, nz, ax + tin * s.bx, ay + tin * s.by, az + tin * s.bz
end

T.HIT = { ell = hitEll, hull = hitHull }

-- The room box a solid can reach: x0, x1, y0, y1, z0, z1. An ellipsoid's is
-- the unit ball's box through its map; a hull says how far its own space
-- reaches (`reach`, a box) or gives its room box itself.
function T.bounds(s)
    if s.box then return unpack(s.box) end
    local m = s.at
    local r = s.reach or { -1, 1, -1, 1, -1, 1 }
    local lo, hi = { m[4], m[8], m[12] }, { m[4], m[8], m[12] }
    for row = 0, 2 do
        for col = 1, 3 do
            local a = m[row * 4 + col]
            local p, q = a * r[col * 2 - 1], a * r[col * 2]
            lo[row + 1] = lo[row + 1] + min(p, q)
            hi[row + 1] = hi[row + 1] + max(p, q)
        end
    end
    return lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]
end

-- The screen box of a room box: i0, i1, j0, j1.
function T.screenBox(x0, x1, y0, y1, z0, z1)
    local i0, i1, j0, j1 = math.huge, -math.huge, math.huge, -math.huge
    for _, x in ipairs({ x0, x1 }) do
        for _, y in ipairs({ y0, y1 }) do
            for _, z in ipairs({ z0, z1 }) do
                local i, j = T.project(x, y, z)
                i0, i1, j0, j1 = min(i0, i), max(i1, i), min(j0, j), max(j1, j)
            end
        end
    end
    return i0, i1, j0, j1
end

--- pictures of models ----------------------------------------------------------

-- A model is a list of parts, each a solid as above whose map is relative to
-- the model's pivot (the ground under it). A part answers its `ramp`, an
-- optional `print` (a function of the point in its own space, the ramp level
-- and the room normal, answering a key index to paint, a ramp to use instead,
-- or nothing; and after a key, true if it is a window or a door that is lit
-- at night) and its `id` (what the ink pass tells parts apart by).
local BACK = 200

function T.paint(parts, edge)
    local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(parts) do
        T.prepare(p)
        local a, b, c, d = T.screenBox(T.bounds(p))
        p.i0, p.i1, p.j0, p.j1 = a, b, c, d
        i0, i1, j0, j1 = min(i0, a), max(i1, b), min(j0, c), max(j1, d)
    end
    i0, j0 = floor(i0) - 1, floor(j0) - 1
    i1, j1 = ceil(i1) + 1, ceil(j1) + 1
    local w, h = i1 - i0 + 1, j1 - j0 + 1
    local b = T.buffer(w, h)
    local best = ffi.new("float[?]", w * h)
    for n = 0, w * h - 1 do best[n] = 1e9 end
    local win, lamps = ffi.new("uint8_t[?]", w * h), false

    for _, p in ipairs(parts) do
        local hit = T.HIT[p.kind or "ell"]
        for pj = max(0, floor(p.j0) - j0), min(h - 1, ceil(p.j1) - j0) do
            for pi = max(0, floor(p.i0) - i0), min(w - 1, ceil(p.i1) - i0) do
                local ox, oy, oz = T.origin(i0 + pi + 0.5, j0 + pj + 0.5, BACK)
                local t, nx, ny, nz, ux, uy, uz = hit(p, ox, oy, oz)
                local n = pj * w + pi
                if t and t < best[n] then
                    best[n] = t
                    local r = p.ramp
                    local k, lev = T.shade(r, nx, ny, nz)
                    local printed, lamp
                    if p.print then printed, lamp = p.print(ux, uy, uz, lev, nx, ny, nz) end
                    win[n] = lamp and 1 or 0
                    if type(printed) == "table" then
                        r = printed
                        k, lev = T.shade(r, nx, ny, nz)
                    elseif printed then
                        k, lev = printed, 0
                    end
                    b.raw[n], b.lev[n], b.shd[n] = k, lev, r[4]
                    b.part[n], b.mat[n] = p.id or 0, p.matId or p.id or 0
                    b.dep[n] = BACK - t
                    b.dif[n] = T.diffuse(nx, ny, nz)
                    b.nx[n], b.ny[n], b.nz[n] = nx, ny, nz
                end
            end
        end
    end
    T.finish(b, edge or 2)
    -- A window the ink went round is ink.
    for n = 0, w * h - 1 do
        if b.key[n] == IDX.o then win[n] = 0 end
        if win[n] == 1 then lamps = true end
    end
    -- `oi, oj`: the pixel of the picture the pivot falls on. `win`, if any of
    -- it is a window: 1 at each pixel that is.
    return { w = w, h = h, oi = -i0, oj = -j0, key = b.key, dep = b.dep, win = lamps and win or nil }
end

return T
