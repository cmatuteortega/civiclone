-- Everything painted on its own rather than into the map: units, cities and
-- improvements.
--
-- Underroot's lesson, straight across: a pose is *numbers*, not a held
-- picture. Each model here is a function from a few numbers (a facing, a
-- step of the walk, a civilization's colours) to a list of solids, and its
-- picture is asked for those numbers and kept under that key. Twenty warriors
-- cost what one costs.
--
-- And what was learned there holds: don't model a face. A shield's boss, a
-- wagon's canvas ribs and a civilization's stripes are printed on the part at
-- the hit point, not built.
--
-- With eight sepia tones and three civilizations, a side is told by value
-- and pattern: the player's people wear light cloth, Umbra's dark, and
-- Varro's light cloth banded with dark. A city's roofs carry the same.

local T = require "src.tracer"
local Sh = require "src.shapes"
local A = T.Affine

local sin, cos, floor, abs = math.sin, math.cos, math.floor, math.abs
local ramp = T.ramp
local IDX = T.IDX

local M = {}

-- Models are built at a size that is easy to think in (a person eleven units
-- tall) and painted `scale` times that.
local cache = {}
local function kept(key, build, scale)
    local p = cache[key]
    if not p then
        local parts = build()
        if scale and scale ~= 1 then
            local m = A.scale(scale, scale, scale)
            for _, q in ipairs(parts) do q.at = A.mul(m, q.at) end
        end
        p = T.paint(parts, 1.5)
        cache[key] = p
    end
    return p
end
M.UNIT_SCALE, M.CITY_SCALE = 1.2, 1.45
M.count = function()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end

--- materials --------------------------------------------------------------------

local R = {
    skin = ramp("w", "c", "s", "t"),
    wood = ramp("s", "t", "n", "u"),
    dark = ramp("k", "n", "u", "o"),
    metal = ramp("w", "c", "k", "n"),
    wall = ramp("w", "c", "s", "t"),
    stone = ramp("c", "s", "t", "k"),
    horse = ramp("t", "n", "u", "o"),
    straw = ramp("w", "c", "t", "k"),
    hull = ramp("c", "s", "t", "n"),
    rope = ramp("c", "s", "t", "k"),
}

-- A civilization's colours: its cloth and roofs, and what to print on them.
local LOOK = {
    light = { cloth = ramp("w", "c", "s", "t"), trim = ramp("s", "t", "n", "u"), roof = ramp("w", "c", "s", "t") },
    dark = { cloth = ramp("k", "n", "u", "o"), trim = ramp("t", "k", "n", "u"), roof = ramp("t", "n", "u", "o") },
    stripe = { cloth = ramp("w", "c", "s", "t"), trim = ramp("k", "n", "u", "o"), roof = ramp("w", "c", "s", "t"),
        bands = true },
}
M.LOOK = LOOK

-- Bands of the darker trim across whatever the cloth covers.
local function banded(look)
    if not look.bands then return nil end
    return function(ux, uy, uz)
        if floor((uy + 1) * 2.5) % 2 == 1 then return look.trim end
    end
end

local function part(s, rmp, id, print)
    s.ramp, s.id, s.print = rmp, id, print
    return s
end

-- Turns a list of parts by heading h (model front, +x, points along (cos h,
-- sin h) on the ground: 0 east, pi/2 south) and moves them by (dx, dy, dz).
local function place(parts, h, dx, dy, dz)
    local m = A.mul(A.move(dx or 0, dy or 0, dz or 0), A.rotY(-h))
    for _, p in ipairs(parts) do p.at = A.mul(m, p.at or A.id()) end
    return parts
end

--- people -----------------------------------------------------------------------

-- A person standing at the origin facing +x, their right hand towards +z.
-- `pose`: 0 still, 1 and 2 the two steps of a walk, 3 a blow. `hands`
-- answers where the right and left hands go (x, y, z each).
local function person(parts, look, pose, opts)
    opts = opts or {}
    local cloth, trim = look.cloth, look.trim
    local print = banded(look)
    local stride = (pose == 1 and 1.4) or (pose == 2 and -1.4) or 0
    local hip, lean = 4.6, pose == 3 and 0.8 or 0
    parts[#parts + 1] = part(Sh.seg(0, hip, 0.9, stride, 0.4, 1.1, 0.75), trim, 1)
    parts[#parts + 1] = part(Sh.seg(0, hip, -0.9, -stride, 0.4, -1.1, 0.75), trim, 1)
    parts[#parts + 1] = part(Sh.ell(lean * 0.5, 6.6, 0, 1.5, 2.4, 1.9), cloth, 2, print)
    parts[#parts + 1] = part(Sh.ell(lean + 0.2, 9.9, 0, 1.45, 1.5, 1.45), R.skin, 3)
    local rx, ry, rz = 1.2, 5.6, 2.3
    if pose == 3 then rx, ry, rz = 2.2, 9.5, 2 end
    local lx, ly, lz = 1.0, 6, -2.3
    if opts.hands then rx, ry, rz, lx, ly, lz = opts.hands(pose) end
    parts[#parts + 1] = part(Sh.seg(lean * 0.4, 8.2, 1.9, rx, ry, rz, 0.6), cloth, 4)
    parts[#parts + 1] = part(Sh.seg(lean * 0.4, 8.2, -1.9, lx, ly, lz, 0.6), cloth, 4)
    if opts.hat == "helmet" then
        parts[#parts + 1] = part(Sh.ell(lean + 0.1, 10.6, 0, 1.6, 1.1, 1.6), R.metal, 5)
    elseif opts.hat == "wide" then
        parts[#parts + 1] = part(Sh.ell(lean + 0.2, 10.9, 0, 2.6, 0.45, 2.6), R.straw, 5)
        parts[#parts + 1] = part(Sh.ell(lean + 0.2, 11.3, 0, 1.2, 0.8, 1.2), R.straw, 5)
    elseif opts.hat == "hood" then
        parts[#parts + 1] = part(Sh.ell(lean - 0.2, 10.4, 0, 1.6, 1.3, 1.6), trim, 5)
    end
    return rx, ry, rz, lx, ly, lz
end

-- A round shield on the left arm, turned half to the front, its boss and
-- rim printed.
local function shield(parts, x, y, z, r, rmp)
    parts[#parts + 1] = part(Sh.ell(x + 0.6, y, z + 0.5, 0.45, r, r * 0.9, A.rotY(math.pi / 4)), rmp, 8,
        function(ux, uy, uz, lev)
            local d = uy * uy + uz * uz
            if d < 0.12 then return IDX.c end
            if d > 0.75 and lev ~= 4 then return IDX.n end
        end)
end

local UNIT = {}

function UNIT.warrior(look, pose)
    local parts = {}
    local rx, ry, rz = person(parts, look, pose)
    -- A club, raised on a blow.
    local tx, ty = rx + 1.2, ry + 4
    if pose == 3 then tx, ty = rx + 3, ry + 1 end
    parts[#parts + 1] = part(Sh.seg(rx, ry - 0.5, rz, tx, ty, rz + 0.3, 0.9, 0.7), R.wood, 7)
    shield(parts, 1.0, 6.4, -2.7, 2.1, R.wood)
    return parts
end

function UNIT.spearman(look, pose)
    local parts = {}
    local rx, ry, rz = person(parts, look, pose, { hat = "helmet" })
    local bx, by, tx, ty = rx - 0.6, 0.8, rx + 0.6, 15
    if pose == 3 then bx, by, tx, ty = rx - 4, ry + 1, rx + 6, ry + 2 end
    parts[#parts + 1] = part(Sh.seg(bx, by, rz + 0.2, tx, ty, rz + 0.2, 0.45), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(tx - (tx - bx) * 0.08, ty - (ty - by) * 0.08, rz + 0.2, tx, ty, rz + 0.2, 0.7), R.metal, 9)
    shield(parts, 1.0, 6.4, -2.8, 2.6, R.metal)
    return parts
end

function UNIT.swordsman(look, pose)
    local parts = {}
    local rx, ry, rz = person(parts, look, pose, { hat = "helmet" })
    local tx, ty = rx + 2.5, ry + 3.5
    if pose == 3 then tx, ty = rx + 4, ry - 1 end
    parts[#parts + 1] = part(Sh.seg(rx, ry, rz, tx, ty, rz, 0.5), R.metal, 7)
    -- A tall square shield.
    parts[#parts + 1] = part(Sh.box(1.3, 3.6, -2.8, 1, 0.9, 5.2), look.trim, 8)
    parts[#parts + 1] = part(Sh.box(1.5, 3.9, -2.8, 0.6, 1, 4.6), R.metal, 9)
    return parts
end

function UNIT.slinger(look, pose)
    local parts = {}
    local rx, ry, rz = person(parts, look, pose, {
        hat = "hood",
        hands = function(p)
            if p == 3 then return 0.5, 11.5, 2.2, 1.5, 7, -2 end
            return 0.6, 10.5, 2.4, 1.0, 6, -2.3
        end,
    })
    -- The sling's cord and its stone, whirling over the head.
    local sx, sz = rx + (pose == 3 and 3 or -1.2), rz + (pose == 3 and 0 or 1.5)
    parts[#parts + 1] = part(Sh.seg(rx, ry, rz, sx, ry + 1.6, sz, 0.25), R.dark, 7)
    parts[#parts + 1] = part(Sh.ell(sx, ry + 1.6, sz, 0.8, 0.8, 0.8), R.stone, 9)
    return parts
end

function UNIT.archer(look, pose)
    local parts = {}
    person(parts, look, pose, { hat = "hood",
        hands = function(p)
            if p == 3 then return 0.2, 8.4, 0.9, 3.4, 8.4, -0.6 end
            return 1.2, 5.6, 2.3, 2.6, 7.4, -1.6
        end })
    -- The bow: three pieces bowed round the left hand.
    local bx, by, bz = 3.4, 8.4, -0.8
    if pose ~= 3 then bx, by, bz = 2.8, 7.4, -1.8 end
    parts[#parts + 1] = part(Sh.seg(bx, by - 3.6, bz, bx + 0.9, by - 1.2, bz, 0.4), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(bx + 0.9, by - 1.2, bz, bx + 0.9, by + 1.2, bz, 0.45), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(bx + 0.9, by + 1.2, bz, bx, by + 3.6, bz, 0.4), R.wood, 7)
    -- A quiver on the back.
    parts[#parts + 1] = part(Sh.seg(-1.8, 5.5, 0.6, -2.2, 10.2, 1.2, 0.7), R.dark, 9)
    return parts
end

function UNIT.scout(look, pose)
    local parts = {}
    local rx, _, rz = person(parts, look, pose, { hat = "wide" })
    parts[#parts + 1] = part(Sh.seg(rx + 0.3, 0.4, rz + 0.2, rx + 0.8, 11.5, rz + 0.2, 0.4), R.wood, 7)
    return parts
end

function UNIT.builder(look, pose)
    local parts = {}
    local rx, ry, rz = person(parts, look, pose, { hat = "wide",
        hands = function(p)
            if p == 3 then return 2.5, 9.5, 1.6, 1.5, 8, -1 end
            return 0.6, 9.5, 1.8, 1.0, 6, -2.3
        end })
    -- A pick over the shoulder: the haft, and the head across its end.
    local hx, hy, hz = rx - 3.5, ry + 1.2, rz - 0.4
    if pose == 3 then hx, hy, hz = rx + 3.5, ry - 3, rz end
    parts[#parts + 1] = part(Sh.seg(rx + (rx - hx) * 0.15, ry, rz, hx, hy, hz, 0.4), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(hx, hy - 1.8, hz, hx, hy + 1.8, hz, 0.45), R.metal, 9)
    return parts
end

-- A covered wagon, its canvas in the civilization's cloth, ribs printed.
function UNIT.settler(look, pose)
    local parts = {}
    local roll = pose == 1 and 0.3 or 0
    parts[#parts + 1] = part(Sh.box(0, 2.3, 0, 9, 4.4, 2.2), R.wood, 1)
    parts[#parts + 1] = part(Sh.ell(-0.3, 4.5, 0, 4.8, 3.6, 2.5), look.cloth, 2, function(ux, uy, uz, lev)
        if floor((ux + 1) * 4 + roll) % 2 == 0 and lev ~= 1 and abs(ux) < 0.9 then return look.trim end
    end)
    for _, wx in ipairs({ -2.9, 2.9 }) do
        for _, wz in ipairs({ -2.4, 2.4 }) do
            parts[#parts + 1] = part(Sh.ell(wx, 1.8, wz, 1.8, 1.8, 0.45), R.dark, 3, function(ux, uy)
                if ux * ux + uy * uy < 0.15 then return IDX.t end
            end)
        end
    end
    -- An ox in front.
    parts[#parts + 1] = part(Sh.ell(7.2, 3.6, 0, 2.6, 1.7, 1.5), R.horse, 4)
    parts[#parts + 1] = part(Sh.ell(9.6, 4.2, 0, 1.2, 1.0, 1.0), R.horse, 4)
    local s = pose == 1 and 0.8 or (pose == 2 and -0.8 or 0)
    for _, lz in ipairs({ -0.8, 0.8 }) do
        parts[#parts + 1] = part(Sh.seg(8.4, 2.6, lz, 8.4 + s, 0.3, lz, 0.5), R.horse, 4)
        parts[#parts + 1] = part(Sh.seg(6.0, 2.6, lz, 6.0 - s, 0.3, lz, 0.5), R.horse, 4)
    end
    return parts
end

function UNIT.horseman(look, pose)
    local parts = {}
    local s = pose == 1 and 1.2 or (pose == 2 and -1.2 or 0)
    parts[#parts + 1] = part(Sh.ell(0, 5.4, 0, 4.3, 2.1, 1.8), R.horse, 1)
    parts[#parts + 1] = part(Sh.seg(3.0, 6.2, 0, 4.8, 9.2, 0, 1.2), R.horse, 1)
    parts[#parts + 1] = part(Sh.ell(5.7, 9.0, 0, 1.9, 0.95, 0.95), R.horse, 1)
    parts[#parts + 1] = part(Sh.seg(-3.8, 6.2, 0, -5.4, 2.8, 0, 0.6), R.dark, 2)
    for _, lz in ipairs({ -1.0, 1.0 }) do
        parts[#parts + 1] = part(Sh.seg(2.8, 4.4, lz, 2.8 + s, 0.3, lz, 0.6), R.horse, 3)
        parts[#parts + 1] = part(Sh.seg(-2.8, 4.4, lz, -2.8 - s, 0.3, lz, 0.6), R.horse, 3)
    end
    -- The rider.
    local print = banded(look)
    parts[#parts + 1] = part(Sh.ell(-0.4, 8.8, 0, 1.4, 2.1, 1.7), look.cloth, 4, print)
    parts[#parts + 1] = part(Sh.ell(-0.2, 11.8, 0, 1.3, 1.35, 1.3), R.skin, 5)
    parts[#parts + 1] = part(Sh.ell(-0.3, 12.5, 0, 1.45, 0.9, 1.45), R.metal, 6)
    for _, lz in ipairs({ -1.6, 1.6 }) do
        parts[#parts + 1] = part(Sh.seg(-0.4, 7.6, lz * 0.6, 0.6, 4.6, lz, 0.55), look.trim, 4)
    end
    local tx, ty = 6, 13
    if pose == 3 then tx, ty = 8, 8 end
    parts[#parts + 1] = part(Sh.seg(-3, 7, 2, tx, ty, 2, 0.4), R.wood, 7)
    return parts
end

--- on the water -----------------------------------------------------------------
--
-- Everything that floats stands with its waterline at the pivot (y = 0):
-- the sea's top. Below that the hull goes on down, and the board keeps a
-- pixel only where it is nearer than the map there, so the water hides it
-- and the boat sits in the sea rather than on it.

-- A boat's hull, along x: `len` long, `beam` across, from `y0` (below the
-- water) up to `y1`. A box with its sides drawn in under it, cut to a point
-- at the bow (+x) and a blunter one at the stern, both raked out as they
-- rise. `print` paints its planks.
local function hull(len, beam, y0, y1, rmp, id, print)
    local planes = {
        { 0, 1, 0, 1 }, { 0, -1, 0, 0 },
        -- The sides lean out from a narrower keel.
        { 0, -0.45, 1, 0.55 }, { 0, -0.45, -1, 0.55 },
        -- The bow and the stern, raked.
        { 1, -0.35, 0.95, 0.8 }, { 1, -0.35, -0.95, 0.8 },
        { -1, -0.25, 0.85, 0.82 }, { -1, -0.25, -0.85, 0.82 },
    }
    local at = A.mul(A.move(0, y0, 0), A.scale(len / 2, y1 - y0, beam / 2))
    return part({ kind = "hull", planes = planes, reach = { -1.3, 1.3, 0, 1, -1, 1 }, at = at }, rmp, id, print)
end

-- Planks along a hull: a darker seam every so often, and the top strake in
-- the civilization's trim so a ship can be told by its side as well as its
-- sail.
local function planked(look, eye)
    return function(ux, uy, uz, lev)
        -- Looking down into it: the bilge in shade inside the rail.
        if uy > 0.99 and math.abs(uz) < 0.8 and math.abs(ux) < 0.86 then return IDX.u end
        if uy > 0.84 then return look.trim end
        if eye and ux > 0.62 and ux < 0.74 and uy > 0.55 and uy < 0.72 then return IDX.w end
        if floor(uy * 7) % 2 == 0 and lev ~= 1 then return IDX.u end
    end
end

-- A row of `n` oars along both sides from x0 to x1, out of the hull at
-- height y and half-beam b, their blades in the water: forward at a stroke's
-- start (pose 1), back at its end (2), level between.
local function oars(parts, n, x0, x1, y, b, pose, reach)
    local sweep = (pose == 1 and 1.6) or (pose == 2 and -1.6) or 0
    local lift = pose == 1 and 0.8 or 0
    reach = reach or 4
    for k = 0, n - 1 do
        local x = x0 + (x1 - x0) * k / math.max(1, n - 1)
        for _, side in ipairs({ -1, 1 }) do
            parts[#parts + 1] = part(Sh.seg(x, y, side * b, x + sweep, -0.6 + lift, side * (b + reach), 0.22), R.wood, 20)
        end
    end
end

-- A row of round shields hung along the near and far gunwales, in the
-- civilization's cloth and trim by turns.
local function shields(parts, look, n, x0, x1, y, b)
    for k = 0, n - 1 do
        local x = x0 + (x1 - x0) * k / math.max(1, n - 1)
        local rmp = k % 2 == 0 and look.cloth or look.trim
        for _, side in ipairs({ -1, 1 }) do
            parts[#parts + 1] = part(Sh.ell(x, y, side * (b + 0.1), 0.7, 0.7, 0.25), rmp, 21)
        end
    end
end

-- A square sail on a yard, bellied by the wind (an ellipsoid pressed flat),
-- in the civilization's cloth, Varro's banded; the light and dark carry a
-- sun or a crescent painted on it.
-- How far round a sail is braced on a ship facing `face`: as near as it
-- goes (a little under 60 degrees) to square to the camera, so the sail
-- shows whichever way the ship heads.
local function braceFor(face)
    local b = math.rad(60 * (face or 1) - 90)
    b = (b + math.pi / 2) % math.pi - math.pi / 2
    return math.max(-1, math.min(1, b))
end

local function sail(parts, look, x, y, w, ht, id, face)
    local L = look
    -- Braced round on the yard, as on a reach, so it shows from either side.
    local brace = braceFor(face)
    local bx, bz = math.sin(brace), math.cos(brace)
    parts[#parts + 1] = part(Sh.ell(x + 0.5, y, 0, 1.2, ht / 2, w / 2, A.rotY(brace)), L.cloth, id, function(ux, uy, uz, lev)
        if L.bands then
            if floor((uy + 1) * 3) % 2 == 1 then return L.trim end
            return
        end
        local d = uy * uy + uz * uz
        if L == LOOK.light and d < 0.16 and d > 0.05 then return L.trim end
        if L == LOOK.dark and d < 0.2 and (uy - 0.18) ^ 2 + (uz - 0.12) ^ 2 > 0.1 then return IDX.c end
    end)
    local half = w / 2 + 0.6
    parts[#parts + 1] = part(Sh.seg(x + 0.6 + bx * half, y + ht / 2, -bz * half, x + 0.6 - bx * half, y + ht / 2, bz * half, 0.3),
        R.wood, id + 1)
end

-- A galley: a long low hull with a bronze ram at the bow, a curled stern
-- post, a single square sail, shields along its sides and five oars a side.
function UNIT.galley(look, pose, face)
    local parts = {}
    parts[#parts + 1] = hull(17, 4.6, -1.6, 1.9, R.hull, 1, planked(look, true))
    -- A deck a little under the gunwale, so the hull reads as hollow.
    parts[#parts + 1] = part(Sh.box(-0.4, 1.6, 0, 13, 3.4, 0.3), R.wood, 2)
    -- The ram, low at the bow, and the stern post curling up and over.
    parts[#parts + 1] = part(Sh.seg(7.6, 0.1, 0, 10.4, 0.1, 0, 0.6, 0.5), R.metal, 3)
    parts[#parts + 1] = part(Sh.seg(-7.8, 1.6, 0, -9.4, 4.4, 0, 0.55), R.hull, 4)
    parts[#parts + 1] = part(Sh.seg(-9.4, 4.4, 0, -8.4, 5.6, 0, 0.45), R.hull, 4)
    shields(parts, look, 5, -4.5, 4.5, 2.4, 2.05)
    oars(parts, 5, -4.6, 4.2, 1.5, 2.2, pose)
    -- The mast and its sail; on a blow (pose 3) the sail is half furled
    -- for the ramming run.
    parts[#parts + 1] = part(Sh.seg(0, 1.6, 0, 0, 13.5, 0, 0.35), R.wood, 5)
    if pose == 3 then sail(parts, look, 0, 10.4, 8.4, 2.6, 6, face)
    else sail(parts, look, 0, 8.4, 8.4, 6, 6, face) end
    -- A steersman at the stern oar.
    parts[#parts + 1] = part(Sh.ell(-6.6, 3.2, 0, 0.9, 1.4, 0.9), look.cloth, 8, banded(look))
    parts[#parts + 1] = part(Sh.ell(-6.5, 5.0, 0, 0.8, 0.8, 0.8), R.skin, 9)
    parts[#parts + 1] = part(Sh.seg(-6.6, 3.5, 1.2, -9.2, -0.6, 2.6, 0.3), R.wood, 10)
    return parts
end

-- A quadrireme: a bigger, higher hull with two banks of oars, a foresail
-- raked over the bow, and a fighting tower forward with a bolt thrower on
-- it, its arms drawn back, and loosed on a blow.
function UNIT.quadrireme(look, pose, face)
    local parts = {}
    parts[#parts + 1] = hull(19, 5.6, -1.8, 2.8, R.hull, 1, planked(look, true))
    parts[#parts + 1] = part(Sh.box(-0.6, 2.5, 0, 15, 4.4, 0.3), R.wood, 2)
    parts[#parts + 1] = part(Sh.seg(8.6, 0.2, 0, 11.4, 0.2, 0, 0.7, 0.55), R.metal, 3)
    parts[#parts + 1] = part(Sh.seg(-8.8, 2.4, 0, -10.6, 5.6, 0, 0.6), R.hull, 4)
    parts[#parts + 1] = part(Sh.seg(-10.6, 5.6, 0, -9.6, 7.0, 0, 0.5), R.hull, 4)
    -- Two banks of oars, the lower ones shorter.
    oars(parts, 6, -5.6, 5.0, 2.2, 2.7, pose, 4.2)
    oars(parts, 6, -5.2, 5.4, 0.9, 2.5, pose == 1 and 2 or (pose == 2 and 1 or pose), 3)
    -- The tower forward: a box of planks with a crenellated top, and the
    -- bolt thrower on it.
    parts[#parts + 1] = part(Sh.box(5.2, 2.6, 0, 3.6, 3.8, 3), R.wood, 11, function(ux, uy, uz)
        if uy > 0.8 and floor((ux + uz + 2) * 3) % 2 == 0 then return look.trim end
    end)
    local fire = pose == 3
    local by = 6.4
    parts[#parts + 1] = part(Sh.seg(4.2, by, 0, 7.6, by + 0.3, 0, 0.45), R.wood, 12)
    local armX = fire and 6.6 or 5.6
    parts[#parts + 1] = part(Sh.seg(6.6, by + 0.2, 0, armX, by + 0.4, -2.0, 0.25), R.wood, 13)
    parts[#parts + 1] = part(Sh.seg(6.6, by + 0.2, 0, armX, by + 0.4, 2.0, 0.25), R.wood, 13)
    parts[#parts + 1] = part(Sh.seg(armX, by + 0.4, -2.0, fire and 6.4 or 4.6, by + 0.35, 0, 0.12), R.rope, 14)
    parts[#parts + 1] = part(Sh.seg(armX, by + 0.4, 2.0, fire and 6.4 or 4.6, by + 0.35, 0, 0.12), R.rope, 14)
    -- The main mast and sail, and the small foresail on a raked spar.
    parts[#parts + 1] = part(Sh.seg(-1.2, 2.5, 0, -1.2, 15.5, 0, 0.4), R.wood, 5)
    sail(parts, look, -1.2, 10, 9.6, 6.6, 6, face)
    parts[#parts + 1] = part(Sh.seg(7.6, 2.8, 0, 10.6, 8.2, 0, 0.3), R.wood, 15)
    parts[#parts + 1] = part(Sh.ell(9.4, 7.2, 0, 0.6, 1.5, 2.2), look.cloth, 16, banded(look))
    -- Shields along the rail aft of the tower, and a steersman.
    shields(parts, look, 5, -6.5, 2.2, 3.3, 2.55)
    parts[#parts + 1] = part(Sh.ell(-7.6, 4.1, 0, 0.9, 1.4, 0.9), look.cloth, 8, banded(look))
    parts[#parts + 1] = part(Sh.ell(-7.5, 5.9, 0, 0.8, 0.8, 0.8), R.skin, 9)
    return parts
end

-- A land unit out on the water: a small open boat with a short mast and a
-- sail in its colours, and the unit itself, a size smaller, standing in it.
-- A wagon goes as its canvas-covered load and a drover; a horse stands in
-- the boat as it is, only smaller.
local function embarked(kind, look, pose, face)
    local parts = {}
    parts[#parts + 1] = hull(11, 4.4, -0.6, 3.0, R.hull, 1, planked(look))
    -- The mast at the stern with a small sail, so the boat reads as theirs.
    parts[#parts + 1] = part(Sh.seg(-3.9, 2, 0, -3.9, 12, 0, 0.3), R.wood, 3)
    parts[#parts + 1] = part(Sh.ell(-3.6, 8.6, 0, 0.7, 2.8, 2.6, A.rotY(braceFor(face))), look.cloth, 4, banded(look))
    -- A pair of oars, pulled as it goes.
    oars(parts, 1, 2.6, 2.6, 1.9, 2.1, pose, 3)
    local cargo
    local s = 0.78
    if kind == "settler" then
        -- The wagon's canvas load, ribs and all, and the drover.
        parts[#parts + 1] = part(Sh.ell(1.6, 2.7, 0, 2.6, 2.0, 1.6), look.cloth, 30, function(ux)
            if floor((ux + 1) * 3) % 2 == 0 then return look.trim end
        end)
        cargo = {}
        person(cargo, look, 0, { hat = "wide" })
    elseif kind == "horseman" then
        cargo = UNIT.horseman(look, 0)
        s = 0.6
    else
        cargo = UNIT[kind](look, pose == 3 and 3 or 0)
    end
    local m = A.mul(A.move(kind == "settler" and -1.0 or 0.3, 2.2, 0), A.scale(s, s, s))
    for _, q in ipairs(cargo) do
        q.at = A.mul(m, q.at or A.id())
        q.id = (q.id or 0) + 40
        parts[#parts + 1] = q
    end
    return parts
end
M.embarkedParts = embarked

-- Six facings, one a hex direction; facing k points along 60k degrees.
M.FACINGS = 6

-- The picture of a unit of `kind`, of a civilization that looks `look`,
-- facing direction `face` (0..5), in pose 0..3. On the water: `roll` (-1, 0,
-- 1) heels it a little over to one side or the other on the swell, and
-- `boat` puts a land unit in a boat (embarked).
M.ROLL = 0.07
function M.unit(kind, look, face, pose, roll, boat)
    face, pose, roll = face or 1, pose or 0, roll or 0
    return kept(table.concat({ boat and "e" or "u", kind, look, face, pose, roll }, ":"), function()
        local parts = boat and embarked(kind, LOOK[look], pose, face) or UNIT[kind](LOOK[look], pose, face)
        if roll ~= 0 then
            local r = A.rotX(roll * M.ROLL)
            for _, q in ipairs(parts) do q.at = A.mul(r, q.at or A.id()) end
        end
        return place(parts, math.rad(60 * face))
    end, M.UNIT_SCALE)
end

-- Does this kind of unit float (and so roll, and stand on the water's top)?
function M.ship(kind) return UNIT[kind] ~= nil and (kind == "galley" or kind == "quadrireme") end

--- cities -----------------------------------------------------------------------

-- Spots round a city's middle for houses, front ones last so they are the
-- ones you see first when it grows.
local SPOTS = {
    { -6, -4 }, { 6, -4 }, { -7, 2 }, { 7, 2 }, { 0, -7 }, { -4, 6 }, { 4, 6 }, { -9, -2 }, { 9, -2 },
}
M.CITY_SPOTS = SPOTS

local function house(parts, x, z, look, id, size, turn)
    size = size or 1
    local w, d, ht = 4 * size, 3.4 * size, 2.6 * size
    local h = turn and math.pi / 2 or 0
    parts[#parts + 1] = part(Sh.box(x, 0, z, w, d, ht, h), R.wall, id, function(ux, uy, uz, lev)
        -- A dark door or window in the middle of a wall, lit at night.
        if math.abs(ux) < 0.25 and uy < 0.7 and uy > 0.15 and math.abs(uz) > 0.98 then return IDX.n, true end
    end)
    parts[#parts + 1] = part(Sh.roof(x, ht, z, w + 1, d + 1.2, 2.6 * size, h), look.roof, id + 1, banded(look))
end

-- What a city on the water builds out over it, in its own frame with +x
-- out to sea and the water's top `yw` below the city's ground: steps down
-- the bank and a timber pier with a boat tied up, then with a harbour a
-- stone quay, a crane and goods on it, and with a lighthouse a mole running
-- out to a striped tower with its lamp, lit at night.
local function waterfront(parts, L, yw, b)
    local q = {}
    local function add(p) q[#q + 1] = p return p end
    local function float(p, x, y, z)
        p.at = A.mul(A.move(x, y, z), p.at)
        return add(p)
    end
    local x0 = 8.3 -- the bank: the hex's edge, in the city's units
    if b.harbour then
        -- The quay along the bank, its stones in courses.
        add(part(Sh.box(x0 + 1.4, yw - 1.4, 0, 3, 13, 2.9), R.stone, 60, function(ux, uy, uz, lev)
            if lev ~= 1 and (floor(uy * 5) % 2 == 0 and floor((uz + 1) * 7) % 2 == 0) then return IDX.k end
        end))
        x0 = x0 + 2.9
        local top = yw + 1.5
        -- The crane: a post, its jib, a rope and a bale on the hook.
        add(part(Sh.seg(9.6, top, -4.4, 9.6, top + 7, -4.4, 0.35), R.wood, 61))
        add(part(Sh.seg(9.6, top + 6.4, -4.4, 13.4, top + 8.2, -4.4, 0.28), R.wood, 61))
        add(part(Sh.seg(13.4, top + 8.2, -4.4, 13.4, top + 3.6, -4.4, 0.1), R.rope, 62))
        add(part(Sh.box(13.4, top + 2.2, -4.4, 1.5, 1.5, 1.4), R.straw, 63))
        -- Crates and jars waiting on the quay.
        add(part(Sh.box(9.4, top, 3.2, 1.6, 1.6, 1.5), R.wood, 64))
        add(part(Sh.box(9.6, top + 1.5, 3.4, 1.2, 1.2, 1.1), R.wood, 65))
        for k, z in ipairs({ 5.2, 6.2 }) do
            add(part(Sh.ell(9.4 + k * 0.4, top + 0.9, z, 0.55, 0.95, 0.55), R.straw, 66))
        end
    else
        -- Steps cut down the bank to the water.
        local drop = -yw
        for k = 0, 2 do
            add(part(Sh.box(x0 - 1.3 + k * 0.8, yw - 1, 1.6, 0.8, 2.2, drop * (1 - (k + 1) / 4) + 1), R.stone, 60))
        end
    end
    -- The pier: planks on posts, out from the bank.
    local deck, len = yw + 0.9, 5
    add(part(Sh.box(x0 + len / 2, deck, 0, len, 2.4, 0.4), R.wood, 67, function(ux)
        if floor((ux + 1) * 6) % 2 == 0 then return IDX.n end
    end))
    for k = 0, 2 do
        for _, z in ipairs({ -1.1, 1.1 }) do
            add(part(Sh.seg(x0 + 0.8 + k * 2, yw - 1, z, x0 + 0.8 + k * 2, deck + 0.7, z, 0.3), R.dark, 68))
        end
    end
    -- A boat tied up alongside, its mast bare.
    float(hull(5.6, 2.2, -0.7, 0.7, R.hull, 69, planked(L)), x0 + 2.6, yw, 2.6)
    add(part(Sh.seg(x0 + 2.2, yw + 0.6, 2.6, x0 + 2.2, yw + 5.4, 2.6, 0.2), R.wood, 70))
    add(part(Sh.seg(x0 + 4.4, deck + 0.6, 1.1, x0 + 4.4, yw + 0.6, 2.4, 0.1), R.rope, 71))
    if b.lighthouse then
        -- The mole: a spit of piled stone out to a rock.
        local mx, mz = x0 + 5.5, -5
        add(part(Sh.box((x0 + mx) / 2, yw - 1.2, mz, mx - x0 + 1, 2.2, 2.2), R.stone, 72, function(ux, uy)
            if uy > 0.8 and floor((ux + 1) * 5) % 2 == 0 then return IDX.k end
        end))
        add(part(Sh.ell(mx, yw + 0.2, mz, 2.2, 1.6, 2.2), R.stone, 73))
        -- The tower, banded light and dark, a gallery round its top, the
        -- lantern with its lights, and a cap.
        local ty = yw + 1.2
        add(part(Sh.frustum(8, 0.7, mx, ty, mz, 1.8, 9, 0, math.pi / 8), R.wall, 74, function(ux, uy)
            if floor(uy * 4) % 2 == 1 then return R.dark end
        end))
        add(part(Sh.prism(8, mx, ty + 9, mz, 1.75, 0.45, 0, math.pi / 8), R.stone, 75))
        add(part(Sh.prism(8, mx, ty + 9.45, mz, 1.0, 1.7, 0, math.pi / 8), R.metal, 76, function(ux, uy, uz)
            if uy > 0.12 and uy < 0.88 and math.abs(math.atan2(uz, ux) % (math.pi / 4) - math.pi / 8) > 0.12 then
                return IDX.c, true
            end
        end))
        add(part(Sh.pyramid(8, mx, ty + 11.15, mz, 1.35, 1.7, 0, math.pi / 8), L.roof, 77))
    end
    for _, p in ipairs(q) do parts[#parts + 1] = p end
end

-- The picture of a city: its houses (one more for each citizen, up to the
-- spots there are), its palace or hall, and whatever it has built. A city on
-- the water is told `shore`, the way (0..5) to the water it faces, and
-- `drop`, how far below its ground (in room units) the water's top is.
function M.city(look, pop, capital, built, shore, drop)
    local b = built or {}
    local houses = math.min(#SPOTS, 1 + pop)
    drop = drop and floor(drop * 2 + 0.5) / 2 or 0
    local key = table.concat({ "c", look, houses, capital and 1 or 0, b.walls and 1 or 0, b.granary and 1 or 0,
        b.library and 1 or 0, b.market and 1 or 0, b.monument and 1 or 0, shore or "-", drop,
        b.harbour and 1 or 0, b.lighthouse and 1 or 0 }, ":")
    return kept(key, function()
        local L = LOOK[look]
        local parts = {}
        if shore then
            local front = {}
            waterfront(front, L, -drop / M.CITY_SCALE, b)
            place(front, math.rad(60 * shore))
            for _, p in ipairs(front) do parts[#parts + 1] = p end
        end
        for k = 1, houses do
            local s = SPOTS[k]
            house(parts, s[1], s[2], L, 10 + k * 2, 0.9 + (k % 3) * 0.08, k % 2 == 0)
        end
        if capital then
            -- The palace: a hall, its roof, and a tower with a pointed top.
            parts[#parts + 1] = part(Sh.box(0, 0, 0, 8, 6, 4.5), R.stone, 1, function(ux, uy, uz)
                if uy > 0.2 and uy < 0.75 and math.abs(uz) > 0.98 and floor((ux + 1) * 3) % 2 == 1 then return IDX.k, true end
            end)
            parts[#parts + 1] = part(Sh.roof(0, 4.5, 0, 9, 7.2, 3.2), L.roof, 2, banded(L))
            parts[#parts + 1] = part(Sh.prism(6, 3.5, 0, 1.5, 2, 10, 0, 0.5), R.stone, 3)
            parts[#parts + 1] = part(Sh.pyramid(6, 3.5, 10, 1.5, 2.6, 4, 0, 0.5), L.roof, 4)
        else
            parts[#parts + 1] = part(Sh.box(0, 0, 0, 6, 5, 4), R.stone, 1)
            parts[#parts + 1] = part(Sh.roof(0, 4, 0, 7, 6.2, 3), L.roof, 2, banded(L))
        end
        if b.granary then
            parts[#parts + 1] = part(Sh.prism(8, -4, 0, 4, 2, 4.5, 0, 0.4), R.straw, 30)
            parts[#parts + 1] = part(Sh.pyramid(8, -4, 4.5, 4, 2.6, 2.6, 0, 0.4), L.roof, 31)
        end
        if b.library then
            parts[#parts + 1] = part(Sh.box(-3, 0, -12, 7, 4, 4), R.stone, 32, function(ux, uy, uz)
                if math.abs(uz) > 0.98 and floor((ux + 1) * 4) % 2 == 0 and uy < 0.85 then return IDX.k, true end
            end)
            parts[#parts + 1] = part(Sh.roof(-3, 4, -12, 7.6, 4.8, 1.6), R.stone, 33)
        end
        if b.market then
            for k, x in ipairs({ 9, 13 }) do
                parts[#parts + 1] = part(Sh.pyramid(4, x, 0, 6 + k, 2.2, 3.2, 0, math.pi / 4), L.roof, 34 + k, banded(L))
            end
        end
        if b.monument then
            parts[#parts + 1] = part(Sh.box(-2, 0, 10, 2.4, 2.4, 1), R.stone, 37)
            parts[#parts + 1] = part(Sh.frustum(4, 0.45, -2, 1, 10, 0.9, 7, 0, math.pi / 4), R.stone, 38)
        end
        if b.walls then
            -- Walls round the hex just inside its edge, towers at the corners.
            local r = 8.3
            for k = 0, 5 do
                local a0, a1 = math.rad(60 * k - 30), math.rad(60 * k + 30)
                local x0, z0, x1, z1 = r * cos(a0), r * sin(a0), r * cos(a1), r * sin(a1)
                local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
                local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
                -- Not along the water's edge: the pier goes out there.
                if k ~= shore then
                    parts[#parts + 1] = part(Sh.box(mx, 0, mz, len, 1.6, 3.2, -math.atan2(z1 - z0, x1 - x0)), R.stone, 40,
                        function(ux, uy) if uy > 0.8 and floor((ux + 1) * 6) % 2 == 0 then return IDX.k end end)
                end
                parts[#parts + 1] = part(Sh.prism(6, x0, 0, z0, 1.9, 4.8), R.stone, 41 + k)
                parts[#parts + 1] = part(Sh.pyramid(6, x0, 4.8, z0, 2.3, 2.2), L.roof, 41 + k)
            end
        end
        return parts
    end, M.CITY_SCALE)
end

--- improvements -----------------------------------------------------------------

-- A farm: a round thatched farmhouse and a haystack in one corner, and a low
-- dry-stone wall along a few of the hex's edges; the crop rows are laid on
-- the ground a pixel at a time (src/ui/board.lua). Three layouts, so a run of
-- farms is not one picture over and over: each says where the farmstead
-- stands, which edges are walled, and which way the rows run (degrees).
M.FARM_LAYOUTS = {
    { home = { -5.5, -5 }, hay = 1, walls = { 0, 1, 2 }, rows = 30 },
    { home = { 5.5, -5 }, hay = -1, walls = { 2, 3, 1 }, rows = 90 },
    { home = { -7, 1 }, hay = 1, walls = { 5, 0, 1 }, rows = 150 },
}
function M.farmLayout(cellId) return M.FARM_LAYOUTS[cellId % #M.FARM_LAYOUTS + 1] end

local FARM_SCALE = 1.3
M.FARM_SCALE = FARM_SCALE
-- `open`: a set of edges not to wall, those shared with another farm, so
-- neighbouring farms read as one field.
function M.farm(layout, open)
    layout = layout or M.FARM_LAYOUTS[1]
    open = open or {}
    local key = { "farm", layout.home[1], layout.home[2] }
    for _, e in ipairs(layout.walls) do key[#key + 1] = open[e] and "-" or e end
    return kept(table.concat(key, ":"), function()
        local parts = {}
        local hx, hz = layout.home[1], layout.home[2]
        -- The farmhouse: round walls, a door to the front, a cone of thatch.
        parts[#parts + 1] = part(Sh.prism(8, hx, 0, hz, 2.4, 3, 0, math.pi / 8), R.wall, 1, function(ux, uy, uz)
            if uz > 0.75 and math.abs(ux) < 0.3 and uy < 0.7 then return IDX.u, true end
        end)
        parts[#parts + 1] = part(Sh.pyramid(8, hx, 2.8, hz, 2.9, 4.2, 0, math.pi / 8), R.straw, 2, function(ux, uy, uz)
            if uy < 0.12 then return IDX.t end
        end)
        -- A haystack beside it, a little to the front.
        parts[#parts + 1] = part(Sh.ell(hx + layout.hay * 5.4, 0.3, hz + 0.6, 1.6, 2.3, 1.6), R.straw, 3,
            function(ux, uy) if floor((uy + 1) * 3) % 2 == 0 and uy > -0.3 then return IDX.t end end)
        -- Walls just inside the hex's edges, in room units brought to the
        -- model's own (it is painted FARM_SCALE times as big).
        local r = (14 - 1.5) / FARM_SCALE
        for _, e in ipairs(layout.walls) do
            if not open[e] then
                local a0, a1 = math.rad(60 * e - 30), math.rad(60 * e + 30)
                local x0, z0, x1, z1 = r * cos(a0), r * sin(a0), r * cos(a1), r * sin(a1)
                local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
                parts[#parts + 1] = part(Sh.box((x0 + x1) / 2, 0, (z0 + z1) / 2, len + 0.6, 0.9, 1,
                    -math.atan2(z1 - z0, x1 - x0)), R.stone, 10 + e, function(ux, uy)
                        if floor((ux + 1) * 7 + (uy > 0.5 and 0.5 or 0)) % 2 == 0 and uy < 0.95 then return IDX.t end
                    end)
            end
        end
        return parts
    end, FARM_SCALE)
end

-- A mine: a heap of spoil with a dark adit framed in timber, a headframe
-- over the shaft with its winding wheel, the miners' hut, and a cart of ore
-- on rails out of the adit. `hills`: each piece stands on the hill's mound
-- (src/world.lua) rather than sunk in it.
local MINE_SCALE = 1.4
M.MINE_SCALE = MINE_SCALE
function M.mine(hills)
    return kept(hills and "mine:hills" or "mine", function()
        local parts = {}
        -- The ground under (x, z): the hill's middle mound, in model units.
        local function ground(x, z)
            if not hills then return 0 end
            local u, v = x * MINE_SCALE / 9.5, z * MINE_SCALE / 7.5
            local h = 1 - u * u - v * v
            return h > 0 and math.max(0, (-0.8 + 4 * math.sqrt(h)) / MINE_SCALE - 0.3) or 0
        end

        -- The spoil heap, back left, the adit in its face framed in timber.
        local hx, hz = -4, -3.6
        local fz = hz + 3.3
        local hy = math.max(ground(hx, hz), ground(hx, fz))
        parts[#parts + 1] = part(Sh.ell(hx, hy, hz, 4.4, 3.6, 3.6), R.stone, 1, function(ux, uy, uz, lev)
            if uz > 0.55 and math.abs(ux) < 0.32 and uy < 0.6 then return IDX.o end
        end)
        parts[#parts + 1] = part(Sh.seg(hx - 1.4, hy, fz, hx - 1.4, hy + 2.6, fz, 0.45), R.straw, 2)
        parts[#parts + 1] = part(Sh.seg(hx + 1.4, hy, fz, hx + 1.4, hy + 2.6, fz, 0.45), R.straw, 2)
        parts[#parts + 1] = part(Sh.seg(hx - 2, hy + 2.7, fz, hx + 2, hy + 2.7, fz, 0.5), R.straw, 2)

        -- Rails from the adit out to the front, and a cart of ore on them.
        local ax, az, bx, bz = hx, fz + 0.3, hx + 4, 8
        local dx, dz = bx - ax, bz - az
        local len = math.sqrt(dx * dx + dz * dz)
        local nx, nz = -dz / len * 0.75, dx / len * 0.75
        for _, side in ipairs({ -1, 1 }) do
            local px, pz, py = ax + nx * side, az + nz * side, ground(ax, az)
            for k = 1, 3 do
                local qx, qz = ax + dx * k / 3 + nx * side, az + dz * k / 3 + nz * side
                local qy = ground(qx, qz)
                parts[#parts + 1] = part(Sh.seg(px, py + 0.12, pz, qx, qy + 0.12, qz, 0.22), R.dark, 3)
                px, pz, py = qx, qz, qy
            end
        end
        local cx, cz = ax + dx * 0.55, az + dz * 0.55
        local cy = ground(cx, cz)
        local turn = math.atan2(dz, dx)
        parts[#parts + 1] = part(Sh.box(cx, cy + 0.6, cz, 3, 2.2, 1.5, turn), R.wood, 4)
        parts[#parts + 1] = part(Sh.ell(cx, cy + 2.1, cz, 1.3, 0.8, 1.1), R.dark, 5, function(ux, uy, uz)
            if uy > 0.5 and floor(ux * 4 + uz * 4) % 3 == 0 then return IDX.t end
        end)

        -- The headframe, right: an A of two legs seen from the front, a strut
        -- behind, and the winding wheel at the top, its rope down the shaft.
        local tx, tz = 4.6, -2
        local ty = ground(tx, tz)
        local top = ty + 8
        parts[#parts + 1] = part(Sh.seg(tx - 2.6, ty, tz + 0.6, tx - 0.4, top, tz + 0.2, 0.45), R.wood, 7)
        parts[#parts + 1] = part(Sh.seg(tx + 2.6, ty, tz + 0.6, tx + 0.4, top, tz + 0.2, 0.45), R.wood, 7)
        parts[#parts + 1] = part(Sh.seg(tx, ty, tz - 3.4, tx, top - 0.3, tz, 0.4), R.wood, 7)
        parts[#parts + 1] = part(Sh.seg(tx - 1.8, ty + 3.2, tz + 0.5, tx + 1.8, ty + 3.2, tz + 0.5, 0.35), R.wood, 8)
        parts[#parts + 1] = part(Sh.seg(tx + 2.1, top + 0.6, tz + 0.8, tx + 2.1, ty + 0.3, tz + 0.8, 0.14), R.dark, 11)

        -- The miners' hut, front right: whitewashed, its gable and door to the front.
        local ux0, uz0 = 4.4, 5
        local uy0 = ground(ux0, uz0)
        parts[#parts + 1] = part(Sh.box(ux0, uy0, uz0, 4, 3, 2.4), R.wall, 12, function(ux, uy, uz)
            if math.abs(ux + 0.3) < 0.22 and uy < 0.75 and uz > 0.98 then return IDX.u end
            if math.abs(ux - 0.45) < 0.16 and uy > 0.35 and uy < 0.7 and uz > 0.98 then return IDX.u end
        end)
        parts[#parts + 1] = part(Sh.roof(ux0, uy0 + 2.4, uz0, 3.8, 5, 2.6, math.pi / 2), R.wood, 13)
        return parts
    end, MINE_SCALE)
end

-- The winding wheel at the top of a mine's headframe, painted apart so it can
-- turn: `step` 0..WHEEL_STEPS-1 of a quarter turn (its spokes are a cross,
-- so a quarter turn brings it round). Stamped where the mine is.
M.WHEEL_STEPS = 8
function M.mineWheel(hills, step)
    return kept(table.concat({ "wheel", hills and 1 or 0, step }, ":"), function()
        local tx, tz = 4.6, -2
        local ty = 0
        if hills then
            local u, v = tx * MINE_SCALE / 9.5, tz * MINE_SCALE / 7.5
            local h = 1 - u * u - v * v
            ty = h > 0 and math.max(0, (-0.8 + 4 * math.sqrt(h)) / MINE_SCALE - 0.3) or 0
        end
        local a = step / M.WHEEL_STEPS * math.pi / 2
        local ca, sa = cos(a), sin(a)
        return { part(Sh.ell(tx, ty + 8.6, tz + 0.7, 2.3, 2.3, 0.35), R.straw, 10, function(ux, uy, uz)
            local d = ux * ux + uy * uy
            if d < 0.07 then return IDX.u end
            if d > 0.55 then return nil end
            local rx, ry = ux * ca - uy * sa, ux * sa + uy * ca
            if math.abs(rx) < 0.16 or math.abs(ry) < 0.16 then return IDX.t end
            return IDX.n
        end) }
    end, MINE_SCALE)
end

--- wildlife ------------------------------------------------------------------------

-- Herding's sheep, brought down to the map: a cloud of wool, puffs of one
-- part so they run into each other uninked, a dark face and ears, four
-- stubby legs. `pose` 0 head up, 1 grazing, 2 and 3 the two steps of a walk.
local WOOL, FACE = ramp("w", "w", "c", "s"), ramp("t", "n", "u", "o")
function M.sheep(face, pose)
    return kept(table.concat({ "sheep", face, pose }, ":"), function()
        local parts = {}
        for _, p in ipairs({ { -0.4, 5.0, 0, 6.0, 4.2, 4.8 }, { -3.0, 7.0, 1.8, 3.4, 3.0, 3.0 },
            { -2.8, 7.0, -2.0, 3.3, 3.0, 3.0 }, { 1.0, 7.6, 1.6, 3.3, 3.0, 3.0 },
            { 1.0, 7.5, -1.8, 3.3, 3.0, 3.0 }, { -5.4, 5.6, 0, 2.6, 2.6, 2.8 } }) do
            parts[#parts + 1] = part(Sh.ell(p[1], p[2], p[3], p[4], p[5], p[6]), WOOL, 1)
        end
        local hx, hy = 6.4, 6.6
        if pose == 1 then hx, hy = 7.2, 2.8 end
        parts[#parts + 1] = part(Sh.ell(hx, hy, 0, 3.0, 2.7, 2.5), FACE, 2)
        parts[#parts + 1] = part(Sh.ell(hx + 2.0, hy - 0.8, 0, 1.5, 1.6, 1.6), FACE, 2)
        parts[#parts + 1] = part(Sh.ell(hx - 0.6, hy + 1.0, 2.8, 0.8, 1.0, 1.4), FACE, 3)
        parts[#parts + 1] = part(Sh.ell(hx - 0.6, hy + 1.0, -2.8, 0.8, 1.0, 1.4), FACE, 3)
        parts[#parts + 1] = part(Sh.ell(hx - 1.6, hy + 2.2, 0, 2.0, 1.4, 1.8), WOOL, 1) -- the topknot
        local st = pose == 2 and 0.9 or (pose == 3 and -0.9 or 0)
        for _, l in ipairs({ { 3.4, 2.4, st }, { 3.4, -2.4, -st }, { -3.4, 2.4, -st }, { -3.4, -2.4, st } }) do
            parts[#parts + 1] = part(Sh.ell(l[1] + l[3], 1.2, l[2], 1.0, 1.7, 1.0), FACE, 4)
        end
        return place(parts, math.rad(60 * face))
    end, M.UNIT_SCALE * 0.3)
end

-- And herding's collie, who keeps them: a dark coat, cream chest, muzzle and
-- tail tip. `gait` 0..3 is where the legs are in the stride.
local COAT, CREAM = ramp("k", "n", "u", "o"), ramp("w", "w", "c", "s")
function M.dog(face, gait)
    return kept(table.concat({ "dog", face, gait }, ":"), function()
        local hy = 9.4
        local parts = {
            part(Sh.ell(0, 6.4, 0, 6.2, 3.6, 3.4), COAT, 1),
            part(Sh.ell(4.2, 6.4, 0, 2.8, 3.2, 3.0), CREAM, 2), -- the chest and ruff
            part(Sh.ell(7.2, hy, 0, 3.1, 2.9, 2.8), COAT, 3),
            part(Sh.ell(9.8, hy - 1.0, 0, 2.0, 1.4, 1.5), CREAM, 4), -- muzzle
            part(Sh.ell(6.4, hy + 2.6, 1.6, 0.8, 1.6, 0.9), COAT, 5),
            part(Sh.ell(6.4, hy + 2.6, -1.6, 0.8, 1.6, 0.9), COAT, 5),
            part(Sh.ell(-7.0, 7.2, 0, 3.0, 1.7, 1.6), COAT, 6), -- a brush of a tail
            part(Sh.ell(-9.6, 7.8, 0, 1.6, 1.4, 1.3), CREAM, 7),
        }
        local swing = sin(gait / 4 * math.pi * 2) * 1.8
        for _, l in ipairs({ { 3.8, 2.0, 1 }, { 3.8, -2.0, -1 }, { -3.8, 2.0, -1 }, { -3.8, -2.0, 1 } }) do
            parts[#parts + 1] = part(Sh.ell(l[1] + swing * l[3], 1.6, l[2], 1.1, 2.0, 1.1), l[1] > 0 and CREAM or COAT, 8)
        end
        return place(parts, math.rad(60 * face))
    end, M.UNIT_SCALE * 0.26)
end

-- A deer, facing `face` (0..5, as a unit), in pose 0 head up, 1 grazing, or
-- 2 and 3 the two bounds of a run. Antlers on some (`stag`).
function M.deer(face, pose, stag)
    return kept(table.concat({ "deer", face, pose, stag and 1 or 0 }, ":"), function()
        local hide = R.wood
        local parts = {}
        local run = pose >= 2
        local reach = pose == 2 and 1.6 or (pose == 3 and -1.2 or 0)
        local lift = run and 0.8 or 0
        parts[#parts + 1] = part(Sh.ell(0, 5.2 + lift, 0, 3.6, 2.1, 1.9), hide, 1)
        for _, lz in ipairs({ -0.9, 0.9 }) do
            parts[#parts + 1] = part(Sh.seg(2.2, 4.4 + lift, lz, 2.2 + reach, 0.3 + lift * 0.5, lz, 0.55), hide, 2)
            parts[#parts + 1] = part(Sh.seg(-2.2, 4.4 + lift, lz, -2.2 - reach, 0.3 + lift * 0.5, lz, 0.55), hide, 2)
        end
        -- A white scut, raised when it runs.
        parts[#parts + 1] = part(Sh.ell(-3.6, 6.2 + lift * 1.5, 0, 0.8, 0.8, 0.7), R.skin, 3)
        local hx, hy = 4.4, 8.6
        if pose == 1 then hx, hy = 4.6, 1.6 end
        parts[#parts + 1] = part(Sh.seg(2.6, 5.6 + lift, 0, hx - 0.4, hy - 0.4 + lift, 0, 1.0, 0.7), hide, 4)
        parts[#parts + 1] = part(Sh.ell(hx + 0.5, hy + lift, 0, 1.5, 1.0, 0.95), hide, 5)
        if stag and pose ~= 1 then
            for _, lz in ipairs({ -0.6, 0.6 }) do
                parts[#parts + 1] = part(Sh.seg(hx, hy + 0.6 + lift, lz, hx - 0.8, hy + 3 + lift, lz * 2.4, 0.3), R.straw, 6)
            end
        end
        return place(parts, math.rad(60 * face))
    end, M.UNIT_SCALE * 0.55)
end

-- A heron, grey and long-legged, facing `face` (0..5): pose 0 standing
-- watch in the shallows of a river, 1 striking down at a fish, 2 and 3 the
-- wings up and down as it flies off, legs trailed behind and neck drawn in.
function M.heron(face, pose)
    return kept(table.concat({ "heron", face, pose }, ":"), function()
        local grey, dark, bill = R.stone, R.dark, R.straw
        local parts = {}
        local fly = pose >= 2
        local by = fly and 6 or 7.6
        parts[#parts + 1] = part(Sh.ell(0, by, 0, 3.2, 1.6, 1.5, A.rotZ(fly and 0 or 0.3)), grey, 1)
        if fly then
            for _, lz in ipairs({ -0.4, 0.4 }) do
                parts[#parts + 1] = part(Sh.seg(-2.4, by - 0.3, lz, -6.2, by - 0.7, lz, 0.3), dark, 2)
            end
            for _, side in ipairs({ -1, 1 }) do
                local tilt = pose == 2 and -side * 0.75 or side * 0.45
                parts[#parts + 1] = part(Sh.ell(-0.2, by + (pose == 2 and 1.6 or -0.6), side * 3.6, 2.4, 0.3, 3.6, A.rotX(tilt)), grey, 3,
                    function(ux) if ux < -0.45 then return IDX.n end end)
            end
            parts[#parts + 1] = part(Sh.seg(2.4, by + 0.3, 0, 4.2, by + 1.2, 0, 0.55), grey, 4)
            parts[#parts + 1] = part(Sh.ell(5.0, by + 1.3, 0, 1.0, 0.75, 0.7), grey, 5)
            parts[#parts + 1] = part(Sh.seg(5.6, by + 1.2, 0, 8.0, by + 1.0, 0, 0.25), bill, 6)
        else
            for _, lz in ipairs({ -0.6, 0.6 }) do
                parts[#parts + 1] = part(Sh.seg(0.2, by - 1, lz, 0.5, -0.5, lz * 1.2, 0.3), dark, 2)
            end
            -- The wings folded along its back, a darker grey.
            parts[#parts + 1] = part(Sh.ell(-0.6, by + 0.5, 0, 2.8, 1.1, 1.6, A.rotZ(0.3)), grey, 3,
                function(ux, uy) if uy > 0.2 then return IDX.k end end)
            local hx, hy, tx, ty
            if pose == 1 then
                hx, hy, tx, ty = 5.4, by - 3.6, 6.4, by - 6.4
            else
                hx, hy, tx, ty = 3.0, by + 5.4, 5.8, by + 5.0
            end
            parts[#parts + 1] = part(Sh.seg(2.0, by + 0.8, 0, hx - 0.3, hy - 0.4, 0, 0.55), grey, 4)
            parts[#parts + 1] = part(Sh.ell(hx, hy, 0, 1.0, 0.8, 0.7), grey, 5)
            parts[#parts + 1] = part(Sh.seg(hx + 0.6, hy - 0.1, 0, tx, ty, 0, 0.25), bill, 6)
            -- Its black crest, trailing.
            parts[#parts + 1] = part(Sh.seg(hx - 0.5, hy + 0.3, 0, hx - 2.2, hy + 0.1, 0, 0.2), dark, 7)
        end
        return place(parts, math.rad(60 * face))
    end, M.UNIT_SCALE * 0.5)
end

--- the sea's harvest -------------------------------------------------------------

-- Fishing boats over the fish: two small open boats, each with a fisher in
-- the civilization's cloth, hauling a net strung between them on a line of
-- floats; a stake of a fish trap off to one side. `roll` heels them on the
-- swell (-1, 0, 1), the two by turns. `phase` (0..3) is the step of the
-- haul: the first fisher reaching out over the side (0), lifting (1),
-- pulling it in (2), lifting (3), the second half a haul behind; the floats
-- bob along the line with it.
local HAUL = {
    [0] = { lean = -0.5, hands = { 1.4, 4.4, 3.4, 1.8, 4.6, 2.4 } },
    [1] = { lean = -0.3, hands = { 1.1, 5.6, 2.9, 1.5, 5.6, 1.9 } },
    [2] = { lean = -0.05, hands = { 0.6, 6.8, 1.7, 1.0, 6.6, 0.9 } },
}
HAUL[3] = HAUL[1]
function M.fishingBoats(look, roll, phase)
    roll, phase = roll or 0, phase or 0
    return kept(table.concat({ "boats", look, roll, phase }, ":"), function()
        local L = LOOK[look]
        local parts = {}
        local function boat(x, z, h, r, id, step)
            local q = {}
            q[#q + 1] = hull(6.4, 2.6, -0.8, 0.9, R.hull, id, planked(L))
            q[#q + 1] = part(Sh.box(0, 0.6, 0, 4.6, 1.8, 0.2), R.wood, id + 1)
            -- The fisher, at this step of the haul.
            local haul = HAUL[step]
            local f = {}
            person(f, L, 0, { hat = "wide",
                hands = function() return unpack(haul.hands) end })
            local m = A.mul(A.move(0.4, 0.2, 0), A.rotX(haul.lean), A.scale(0.62, 0.62, 0.62))
            for _, p in ipairs(f) do
                p.at = A.mul(m, p.at or A.id())
                p.id = p.id + id + 2
                q[#q + 1] = p
            end
            local t = A.mul(A.move(x, 0, z), A.rotY(-h), A.rotX(r * M.ROLL))
            for _, p in ipairs(q) do
                p.at = A.mul(t, p.at)
                parts[#parts + 1] = p
            end
        end
        boat(-5.5, -1.5, math.rad(80), roll, 10, phase)
        boat(5, 2.5, math.rad(-100), -roll, 30, (phase + 2) % 4)
        -- The net's floats, in a bow between the two, a swell running along
        -- them with the haul; the near ends drawn up a little when hauled.
        for k = 0, 8 do
            local f = k / 8
            local x = -4.4 + f * 8.6
            local z = -0.2 + f * 2.6 + math.sin(f * math.pi) * 3.2
            local y = 0.15 + 0.3 * math.sin(phase * math.pi / 2 + k * 1.1)
            if k == 0 and phase == 2 then y = y + 0.5 end
            if k == 8 and phase == 0 then y = y + 0.5 end
            parts[#parts + 1] = part(Sh.ell(x, y, z, 0.45, 0.35, 0.45), R.straw, 50)
        end
        -- A fish trap: stakes in a ring, a little off.
        for k = 0, 4 do
            local a = k * 2 * math.pi / 5
            parts[#parts + 1] = part(Sh.seg(-1 + math.cos(a) * 1.6, -1, -7 + math.sin(a) * 1.3,
                -1 + math.cos(a) * 1.5, 1.6 + (k % 2) * 0.5, -7 + math.sin(a) * 1.2, 0.22), R.dark, 51)
        end
        return parts
    end, M.UNIT_SCALE)
end

-- A fish leaping, side on, its body bent by `bend` (-1 rising, 0, 1
-- falling) and facing `face` (+1 east or -1 west).
function M.fish(bend, face)
    return kept(table.concat({ "fish", bend, face }, ":"), function()
        local parts = {}
        local a = bend * 0.5
        parts[#parts + 1] = part(Sh.ell(0, 0, 0, 1.5, 0.75, 0.8, A.rotZ(a)), R.metal, 1, function(ux, uy)
            if uy > 0.35 then return IDX.k end
        end)
        local tx, ty = -1.5 * math.cos(a), -1.5 * math.sin(a)
        parts[#parts + 1] = part(Sh.ell(tx - 0.3, ty, 0, 0.45, 0.6, 0.15, A.rotZ(a)), R.metal, 2)
        if face < 0 then
            for _, p in ipairs(parts) do p.at = A.mul(A.scale(-1, 1, 1), p.at) end
        end
        return parts
    end,1.6)
end

return M
