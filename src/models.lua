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
-- With eight sepia tones and up to six civilizations, a side is told by
-- value and pattern: the player's people wear light cloth, Umbra's dark,
-- Varro's light cloth banded with dark, Thistle's light checked with dark,
-- Reedholm's the middle shades with a pale hem, and Driftland's dark banded
-- with light. A city's roofs carry the same.

local T = require "src.tracer"
local Sh = require "src.shapes"
local H = require "src.hex"
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
-- What glows: a lamp, a demon's eyes.
local GLOW = ramp("w", "w", "w", "c")

-- A civilization's colours: its cloth and roofs, and what to print on them.
-- `bands`, the trim in bands across the cloth; `checks`, in squares; `hem`,
-- along its foot. `dark`: what is daubed on its roofs is pale.
local LOOK = {
    light = { cloth = ramp("w", "c", "s", "t"), trim = ramp("s", "t", "n", "u"), roof = ramp("w", "c", "s", "t") },
    dark = { cloth = ramp("k", "n", "u", "o"), trim = ramp("t", "k", "n", "u"), roof = ramp("t", "n", "u", "o"),
        dark = true },
    stripe = { cloth = ramp("w", "c", "s", "t"), trim = ramp("k", "n", "u", "o"), roof = ramp("w", "c", "s", "t"),
        bands = true },
    -- Thistle's: light cloth checked with dark.
    check = { cloth = ramp("w", "c", "s", "t"), trim = ramp("n", "u", "u", "o"), roof = ramp("c", "s", "t", "k"),
        checks = true },
    -- Reedholm's: cloth of the middle shades, a pale hem.
    hem = { cloth = ramp("s", "t", "k", "n"), trim = ramp("w", "w", "c", "s"), roof = ramp("s", "t", "k", "n"),
        hem = true },
    -- Driftland's: Varro's turned over, dark cloth banded with light.
    barred = { cloth = ramp("k", "n", "u", "o"), trim = ramp("w", "c", "s", "t"), roof = ramp("k", "n", "u", "o"),
        bands = true, dark = true },
}
M.LOOK = LOOK

-- The trim printed on whatever the cloth covers: in bands across it, in
-- squares, or along its foot. Nil for plain cloth.
local function banded(look)
    if look.bands then
        return function(ux, uy, uz)
            if floor((uy + 1) * 2.5) % 2 == 1 then return look.trim end
        end
    elseif look.checks then
        return function(ux, uy, uz)
            if (floor((ux + 1) * 2.5) + floor((uy + 1) * 2.5) + floor((uz + 1) * 2.5)) % 2 == 1 then return look.trim end
        end
    elseif look.hem then
        return function(ux, uy, uz)
            if uy < -0.2 then return look.trim end
        end
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

-- A horse, facing +x, and its rider on it; answers where the rider's right
-- hand is, for what it carries.
local function mount(parts, look, pose, hat)
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
    if hat == "helmet" then
        parts[#parts + 1] = part(Sh.ell(-0.3, 12.5, 0, 1.45, 0.9, 1.45), R.metal, 6)
    elseif hat == "hood" then
        parts[#parts + 1] = part(Sh.ell(-0.4, 12.3, 0, 1.5, 1.1, 1.5), look.trim, 6)
    elseif hat == "wide" then
        parts[#parts + 1] = part(Sh.ell(-0.2, 12.9, 0, 2.4, 0.4, 2.4), R.straw, 6)
    end
    for _, lz in ipairs({ -1.6, 1.6 }) do
        parts[#parts + 1] = part(Sh.seg(-0.4, 7.6, lz * 0.6, 0.6, 4.6, lz, 0.55), look.trim, 4)
    end
    return 0.4, 9.2, 1.9
end

-- A horseman: a warrior's lance of wood, couched on a blow.
function UNIT.horseman(look, pose)
    local parts = {}
    mount(parts, look, pose, "helmet")
    local tx, ty = 6, 13
    if pose == 3 then tx, ty = 8, 8 end
    parts[#parts + 1] = part(Sh.seg(-3, 7, 2, tx, ty, 2, 0.4), R.wood, 7)
    return parts
end

-- A rider with nothing but a staff, seeing far from the saddle.
function UNIT.rider(look, pose)
    local parts = {}
    local rx, ry, rz = mount(parts, look, pose, "wide")
    parts[#parts + 1] = part(Sh.seg(rx, ry - 2, rz + 0.4, rx + 0.8, ry + 5, rz + 0.4, 0.35), R.wood, 7)
    return parts
end

-- A lancer: the spear's iron head on a long ash shaft.
function UNIT.lancer(look, pose)
    local parts = {}
    mount(parts, look, pose, "helmet")
    local bx, by, tx, ty = -3, 7, 7, 14
    if pose == 3 then tx, ty = 9.5, 8 end
    parts[#parts + 1] = part(Sh.seg(bx, by, 2, tx, ty, 2, 0.35), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(tx - (tx - bx) * 0.1, ty - (ty - by) * 0.1, 2, tx, ty, 2, 0.6), R.metal, 9)
    shield(parts, -0.2, 8.6, -2.2, 2.0, R.metal)
    return parts
end

-- A knight: a sword raised, and cut down on a blow; a tall shield.
function UNIT.knight(look, pose)
    local parts = {}
    local rx, ry, rz = mount(parts, look, pose, "helmet")
    local tx, ty = rx + 1.5, ry + 5
    if pose == 3 then tx, ty = rx + 4.5, ry - 0.5 end
    parts[#parts + 1] = part(Sh.seg(rx, ry, rz, tx, ty, rz, 0.5), R.metal, 7)
    parts[#parts + 1] = part(Sh.box(0.2, 8.6, -2.1, 1, 0.9, 4.4), look.trim, 8)
    parts[#parts + 1] = part(Sh.box(0.4, 8.9, -2.1, 0.6, 1, 3.8), R.metal, 9)
    return parts
end

-- A horse archer: the bow held out to the side, drawn on a blow.
function UNIT.horsearcher(look, pose)
    local parts = {}
    mount(parts, look, pose, "hood")
    local bx, by, bz = 1.6, 10, -2.4
    if pose == 3 then bx, by, bz = 2.6, 10.4, -1.2 end
    parts[#parts + 1] = part(Sh.seg(bx, by - 3, bz, bx + 0.8, by - 1, bz, 0.35), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(bx + 0.8, by - 1, bz, bx + 0.8, by + 1, bz, 0.4), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(bx + 0.8, by + 1, bz, bx, by + 3, bz, 0.35), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(-2.2, 7.6, 1.4, -2.6, 11.4, 1.8, 0.6), R.dark, 9)
    return parts
end

-- A mounted slinger: the cord whirled over the head.
function UNIT.mountedslinger(look, pose)
    local parts = {}
    mount(parts, look, pose, "hood")
    local hx, hy, hz = 0.4, 14.2, 1.6
    parts[#parts + 1] = part(Sh.seg(-0.2, 10.4, 1.6, hx, hy, hz, 0.5), look.cloth, 4)
    local sx, sz = hx + (pose == 3 and 3 or -1.2), hz + (pose == 3 and 0 or 1.5)
    parts[#parts + 1] = part(Sh.seg(hx, hy, hz, sx, hy + 1.4, sz, 0.25), R.dark, 7)
    parts[#parts + 1] = part(Sh.ell(sx, hy + 1.4, sz, 0.8, 0.8, 0.8), R.stone, 9)
    return parts
end

-- The forms that ride (src/defs.lua D.FORMS): they go in a boat as a horse
-- does, smaller.
M.MOUNTED = { rider = true, horseman = true, lancer = true, knight = true, horsearcher = true, mountedslinger = true }

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
    local print = (L.checks or L.hem) and banded(L)
    -- Braced round on the yard, as on a reach, so it shows from either side.
    local brace = braceFor(face)
    local bx, bz = math.sin(brace), math.cos(brace)
    parts[#parts + 1] = part(Sh.ell(x + 0.5, y, 0, 1.2, ht / 2, w / 2, A.rotY(brace)), L.cloth, id, function(ux, uy, uz, lev)
        if L.bands then
            if floor((uy + 1) * 3) % 2 == 1 then return L.trim end
            return
        end
        if print then return print(ux, uy, uz) end
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
    elseif M.MOUNTED[kind] then
        cargo = UNIT[kind](look, 0)
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
-- The pictures already asked for, by what they were asked with, found
-- without making a key: shelf(t, a) is t[a], made if not there.
local function shelf(t, a)
    local s = t[a]
    if not s then s = {} t[a] = s end
    return s
end
local unitPics, beastPics, wheelPics = {}, {}, {}
local unitPic, beastPic, wheelPic

function M.unit(kind, look, face, pose, roll, boat)
    face, pose, roll = face or 1, pose or 0, roll or 0
    local row = shelf(shelf(shelf(shelf(shelf(unitPics, boat and true or false), kind), look), face), pose)
    local pic = row[roll]
    if not pic then
        pic = unitPic(kind, look, face, pose, roll, boat)
        row[roll] = pic
    end
    return pic
end

unitPic = function(kind, look, face, pose, roll, boat)
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

-- A city grows as it gains citizens, and is built the way the land it stands
-- on builds:
--
--   tier 1, a hamlet (1-2 citizens): a hall, a couple of houses, gardens and
--           open ground between them;
--   tier 2, a village (3-5): the gardens filling with houses round the hall;
--   tier 3, a town (6-9): every plot built on, the houses nearest the middle
--           a storey taller, and the land's own landmark beside the hall;
--   tier 4, a city (10 and up): houses three storeys high in the middle and
--           two at the edge, and the landmark grown into a monument.
--
-- And by the land (`site`): on grassland timber houses with gabled roofs and
-- trees in the gardens, half-timbered upper storeys, a bell tower and then a
-- stone keep; on plains round huts thatched to a cone, then long thatched
-- houses, haystacks and a windmill; on desert flat-roofed mud brick with
-- awnings in the city's colours on the roofs, palms, and a dome; on hills
-- stone houses on terraces stepping up to the back, and a temple on a podium
-- that becomes an acropolis. A city by a river turns a mill wheel in it, and
-- no house stands in the river's channel.
M.CITY_TIERS = { 1, 3, 6, 10 }
function M.cityTier(pop)
    local t = 1
    for k, p in ipairs(M.CITY_TIERS) do if pop >= p then t = k end end
    return t
end

-- The plots round the hall, in the order they are built on: an inner ring
-- out along the middles of the hex's edges (way k, as rivers and the shore
-- are told), the back ones first, then an outer ring into its corners, the
-- front ones last so they are the ones you see first when it grows.
local function ring(r, a) return { r * cos(math.rad(a)), r * sin(math.rad(a)) } end
local PLOTS = {}
for _, p in ipairs({
    { 5.7, 240, 1, "in", 4 }, { 5.7, 300, 1, "in", 5 }, { 5.7, 180, 1, "in", 3 }, { 5.7, 0, 1, "in", 0 },
    { 5.7, 120, 1, "in", 2 }, { 5.7, 60, 1, "in", 1 },
    { 7.5, 270, 0.82, "out", 4, 5 }, { 7.5, 210, 0.82, "out", 3, 4 }, { 7.5, 330, 0.82, "out", 5, 0 },
    { 7.5, 150, 0.82, "out", 2, 3 }, { 7.5, 30, 0.82, "out", 0, 1 }, { 7.5, 90, 0.82, "out", 1, 2 },
}) do
    local at = ring(p[1], p[2])
    PLOTS[#PLOTS + 1] = { x = at[1], z = at[2], size = p[3], ring = p[4], edges = { p[5], p[6] } }
end
M.CITY_PLOTS = PLOTS

-- What each building takes, of the plots: it stands in that plot instead of
-- a house.
local BUILT_PLOT = { granary = 4, library = 3, market = 5, monument = 12, cistern = 6, shelter = 10, sanctum = 11,
    hearth = 8, lazaret = 9 }
local BUILT_NAMES = {}
for name in pairs(BUILT_PLOT) do BUILT_NAMES[#BUILT_NAMES + 1] = name end
table.sort(BUILT_NAMES)

-- A little hash, so the same city is laid out the same way every time.
local function hash(a, b)
    local n = sin(a * 12.9898 + b * 78.233) * 43758.5453
    return n - floor(n)
end

local function edgesKey(set)
    if not set then return "*" end
    local n = 0
    for e = 0, 5 do if set[e] then n = n + 2 ^ e end end
    return n
end

local function siteKey(site)
    local rv = {}
    for k = 0, 5 do rv[#rv + 1] = site.river and site.river[k] and floor(site.river[k] * 2 + 0.5) / 2 or "-" end
    return table.concat({ site.biome or "grass", site.hills and "h" or "f", site.seed or 0, table.concat(rv, ","),
        site.snow and "s" or "-", edgesKey(site.joins), edgesKey(site.towers), site.gate or "-" }, ";")
end

-- The site of a city on map cell `cell`: its land, whether on hills, how far
-- down (room units) the water of each river along it runs, and one of four
-- layouts, by the hex.
function M.citySite(cell)
    local river
    if cell.river then
        for k = 0, 5 do
            local e = cell.river[k]
            if e then
                river = river or {}
                river[k] = cell.top - (e.level or cell.top - 2)
            end
        end
    end
    local biome = cell.terrain
    -- Snow on the roofs of a town on frozen ground (src/frost.lua).
    local snow = (biome == "snow" or biome == "tundra") or nil
    if biome ~= "plains" and biome ~= "desert" then biome = "grass" end
    return { biome = biome, hills = cell.elev == "hills", river = river, seed = cell.id % 4, snow = snow }
end

-- How a city at `pop` on `site`, with buildings `built`,
-- is laid out: its houses (x, z, size, storeys, how high its floor
-- stands, turned or not) and what the empty plots hold.
-- What a layout depends on, as one number: the population, which of the
-- buildings with plots of their own stand, whether on the plains, on hills,
-- which of the hex's edges a river runs along, and the layout's seed; nil if
-- any is not as a game makes them, which is laid out afresh.
local layouts, chimneys = {}, {}
local layOut, chimneysOf
local function layoutKey(pop, b, site)
    local seed = site.seed or 0
    if pop % 1 ~= 0 or pop < 0 or pop >= 2 ^ 14 or seed % 1 ~= 0 or seed < 0 or seed >= 1024 then return nil end
    local flags, bit = 0, 1
    for _, name in ipairs(BUILT_NAMES) do
        if b[name] then flags = flags + bit end
        bit = bit * 2
    end
    local river = 0
    if site.river then
        for e = 0, 5 do if site.river[e] then river = river + 2 ^ e end end
    end
    local plains = site.biome == "plains" and 1 or 0
    local hills = site.hills and 1 or 0
    local joins = 0
    if site.joins then
        for e = 0, 5 do if site.joins[e] then joins = joins + 2 ^ e end end
    end
    return seed + 1024 * (river + 64 * (hills + 2 * (plains + 2 * (joins + 64 * (flags + 512 * pop)))))
end

function M.cityLayout(pop, built, site)
    site = site or {}
    local b = built or {}
    -- The same town is laid out the same way every time: kept, and handed out
    -- to be read, never changed.
    local key = layoutKey(pop, b, site)
    local lay = key and layouts[key]
    if not lay then
        lay = layOut(pop, b, site)
        if key then layouts[key] = lay end
    end
    return lay
end

layOut = function(pop, b, site)
    local tier = M.cityTier(pop)
    local seed = site.seed or 0
    local houses, empty = {}, {}
    local want = math.min(#PLOTS, 1 + pop)
    local taken = {}
    for name, k in pairs(BUILT_PLOT) do if b[name] then taken[k] = name end end
    -- The town's landmark takes a plot of its own on the plains: a windmill.
    if site.biome == "plains" and not site.hills and tier >= 3 then taken[7] = taken[7] or "windmill" end
    -- On hills the temple stands at the back of the hex, where two plots were.
    if site.hills and tier >= 3 then taken[7], taken[1] = "temple", "temple" end
    for k, p in ipairs(PLOTS) do
        local wet = false
        if site.river then
            for _, e in ipairs(p.edges) do if site.river[e] then wet = true end end
        end
        local x = p.x + (hash(seed + k, 1) - 0.5) * 0.7
        local z = p.z + (hash(seed + k, 2) - 0.5) * 0.7
        -- On hills the ground is terraced, stepping up to the back.
        local y = site.hills and math.max(0, math.min(3.6, floor((1.5 - z) / 2.6) * 1.2)) or 0
        -- A street out to a quarter runs over the plot on that edge.
        if site.joins and p.ring == "in" and site.joins[p.edges[1]] then wet = true end
        if wet or taken[k] then
            if not wet then empty[#empty + 1] = { x = x, z = z, y = y, plot = k, what = taken[k] } end
        elseif #houses < want then
            local storeys = 1
            if tier == 3 then storeys = p.ring == "in" and 2 or 1
            elseif tier == 4 then storeys = p.ring == "in" and 3 or 2 end
            -- One in three a storey lower, so the roofs are not one line.
            if storeys > 1 and hash(seed + k, 3) < 0.33 then storeys = storeys - 1 end
            houses[#houses + 1] = { x = x, z = z, y = y, plot = k, ring = p.ring,
                size = p.size * (0.88 + hash(seed + k, 4) * 0.18), storeys = storeys,
                turn = (k + seed) % 2 == 0 }
        else
            empty[#empty + 1] = { x = x, z = z, y = y, plot = k }
        end
    end
    return { tier = tier, houses = houses, empty = empty }
end

-- Where its chimneys are (model units, from the city's middle on its
-- ground): one on a house for every two citizens, three at most.
local STOREY = 2.6
function M.cityChimneys(pop, built, site)
    -- Kept as the layout is, and by whether on the desert (lower chimneys)
    -- and with the hearth (one more).
    local key = layoutKey(pop, built or {}, site or {})
    if key then
        key = key * 4 + (site and site.biome == "desert" and 2 or 0) + (built and built.hearth and 1 or 0)
        local out = chimneys[key]
        if not out then
            out = chimneysOf(pop, built, site)
            chimneys[key] = out
        end
        return out
    end
    return chimneysOf(pop, built, site)
end

chimneysOf = function(pop, built, site)
    local lay = M.cityLayout(pop, built, site)
    local out = {}
    for k = 1, math.min(#lay.houses, 1 + floor(pop / 2), 3) do
        local h = lay.houses[k]
        local top = h.y + STOREY * h.size * h.storeys + (site and site.biome == "desert" and 0.6 or 2.4 * h.size)
        out[#out + 1] = { h.x + 0.8 * h.size, top, h.z }
    end
    -- The hearth's fire is never let go out.
    if built and built.hearth then
        local p = PLOTS[BUILT_PLOT.hearth]
        out[#out + 1] = { p.x + 1, 7.3, p.z - 1.4 }
    end
    return out
end

-- Still water, in a cistern: dark, the sky's light on it at the back.
local WATER = ramp("k", "n", "u", "o")

local R2 = {
    mud = ramp("s", "t", "k", "n"),
    slab = ramp("w", "c", "s", "t"),
    leaf = ramp("t", "n", "u", "o"),
    hedge = ramp("k", "n", "u", "o"),
    soil = ramp("t", "k", "n", "u"),
}

-- A window or a door in the middle of a wall, lit at night; `floors` of them
-- one over another.
local function windows(floors, door)
    return function(ux, uy, uz)
        if math.abs(uz) > 0.98 or math.abs(ux) > 0.98 then
            local across = math.abs(uz) > 0.98 and ux or uz
            local f = uy * floors
            local band = f - floor(f)
            if floor(f) == 0 and door then
                if math.abs(across) < 0.22 and band < 0.7 and band > 0.0 then return IDX.n, true end
            elseif math.abs(math.abs(across) - 0.45) < 0.15 and band > 0.35 and band < 0.7 then
                return IDX.n, true
            end
        end
    end
end

-- The plague's mark (src/plague.lua): a great cross daubed across the
-- ground storey of a house the sickness has been in, ink over its door and
-- its windows. `across` is how far along the wall (-1..1), `uy` how high.
local function daubed(across, uy)
    if uy < 0.1 or uy > 0.9 or abs(across) > 0.6 then return nil end
    local v = (uy - 0.5) / 0.4 * 0.6
    if abs(abs(across) - abs(v)) < 0.16 then return IDX.o end
end

-- A wall print with the plague's cross laid over it, on every face.
local function crossed(print)
    return function(ux, uy, uz, lev, ...)
        if abs(uz) > 0.98 or abs(ux) > 0.98 then
            local k = daubed(abs(uz) > 0.98 and ux or uz, uy)
            if k then return k end
        end
        if print then return print(ux, uy, uz, lev, ...) end
    end
end

-- The cross daubed on each slope of a gabled roof too, where it shows from
-- above: ink, or pale on a dark roof.
local function crossedRoof(print, pale)
    return function(ux, uy, uz, lev, ...)
        local a, b = ux / 0.6, (abs(uz) - 0.5) / 0.42
        if abs(a) < 1 and abs(b) < 1 and abs(abs(a) - abs(b)) < 0.2 then return pale and IDX.w or IDX.o end
        if print then return print(ux, uy, uz, lev, ...) end
    end
end

-- Thatch: the roof's own colour a step darker in courses, a dark eave.
local function thatched(L, courses)
    return function(ux, uy, uz, lev)
        if uy < 0.1 then return IDX.n end
        if lev > 1 and floor(uy * courses) % 2 == 1 then return L.roof[math.min(4, lev + 1)] end
    end
end

-- A house of `storeys` in the style of the land, its floor at y.
-- Snow lying on a roof: white on what looks up, the eave dark under it.
local function snowed(ux, uy, uz, lev)
    if uy < 0.08 then return IDX.n end
    return lev <= 2 and IDX.w or IDX.c
end

local function house(parts, x, y, z, L, id, size, storeys, turn, biome, snow, marked)
    local h = turn and math.pi / 2 or 0
    local w, d = 4 * size, 3.4 * size
    if turn then w, d = w * 0.92, d * 1.08 end
    local ht = STOREY * size
    if biome == "plains" and storeys == 1 then
        -- A round hut, thatched to a cone, a dark band where the thatch ends.
        parts[#parts + 1] = part(Sh.prism(8, x, y, z, 1.75 * size, ht * 0.95, 0, math.pi / 8), R.wall, id,
            function(ux, uy, uz)
                if marked and uz > 0.6 then
                    local k = daubed(ux, uy)
                    if k then return k end
                end
                if uz > 0.7 and math.abs(ux) < 0.3 and uy < 0.75 then return IDX.u, true end
            end)
        local thatch = thatched(L, 7)
        local cone = thatch
        if marked then
            -- The cross on the thatch, on the side to the front.
            cone = function(ux, uy, uz, lev, ...)
                if uz > 0.15 then
                    local a, b = ux / 0.55, (uy - 0.4) / 0.32
                    if abs(a) < 1 and abs(b) < 1 and abs(abs(a) - abs(b)) < 0.22 then return L.dark and IDX.w or IDX.o end
                end
                return thatch(ux, uy, uz, lev, ...)
            end
        end
        parts[#parts + 1] = part(Sh.pyramid(8, x, y + ht * 0.9, z, 2.45 * size, 3.4 * size, 0, math.pi / 8), L.roof,
            id + 1, cone)
        return
    end
    if biome == "desert" then
        -- Mud brick, the roof flat and pale; each storey up set back, leaving
        -- a terrace; an awning in the city's colours on the top one.
        local ww, dd, yy = w, d, y
        for s = 1, storeys do
            local print = windows(1, s == 1)
            if marked and s == 1 then print = crossed(print) end
            parts[#parts + 1] = part(Sh.box(x, yy, z, ww, dd, ht, h), R2.mud, id, print)
            parts[#parts + 1] = part(Sh.box(x, yy + ht, z, ww + 0.3, dd + 0.3, 0.45, h), R2.slab, id + 1)
            yy = yy + ht + 0.45
            if s < storeys then ww, dd = ww * 0.72, dd * 0.75 end
        end
        local ax = x + (turn and 0 or -ww * 0.18)
        local az = z + (turn and -dd * 0.18 or 0)
        parts[#parts + 1] = part(Sh.roof(ax, yy + 1.1, az, ww * 0.62, dd * 0.7, 0.55, h), L.roof, id + 2, banded(L))
        for _, s in ipairs({ -1, 1 }) do
            local px = ax + (turn and 0 or s * ww * 0.28)
            local pz = az + (turn and s * dd * 0.28 or 0)
            parts[#parts + 1] = part(Sh.seg(px, yy, pz + dd * 0.3, px, yy + 1.2, pz + dd * 0.3, 0.16), R.wood, id + 3)
        end
        return
    end
    -- Gabled houses: timber on grassland and plains, stone on hills. Upper
    -- storeys of timber are half-timbered and jut out a little.
    local wall = biome == "hills" and R.stone or R.wall
    local yy = y
    for s = 1, storeys do
        local jut = (s > 1 and biome ~= "hills") and 0.35 or 0
        local print = windows(1, s == 1)
        if s > 1 and biome ~= "hills" then
            local win = print
            print = function(ux, uy, uz, lev)
                local k, lit = win(ux, uy, uz, lev)
                if k then return k, lit end
                if uy > 0.9 or uy < 0.08 or math.abs(ux) > 0.92 then return IDX.n end
                if math.abs(math.abs(ux) - 0.75) < 0.06 then return IDX.n end
            end
        elseif biome == "grass" then
            -- Timber posts at the corners and a sill beam.
            local win = print
            print = function(ux, uy, uz, lev)
                local k, lit = win(ux, uy, uz, lev)
                if k then return k, lit end
                if math.abs(ux) > 0.9 or (math.abs(uz) > 0.9 and math.abs(ux) > 0.82) or uy < 0.08 then return IDX.n end
            end
        elseif biome == "hills" then
            local win = print
            print = function(ux, uy, uz, lev)
                local k, lit = win(ux, uy, uz, lev)
                if k then return k, lit end
                if lev ~= 1 and floor(uy * 4) % 2 == 0 and floor((ux + uz + 2) * 4) % 3 == 0 then return IDX.k end
            end
        end
        if marked and s == 1 then print = crossed(print) end
        parts[#parts + 1] = part(Sh.box(x, yy, z, w + jut, d + jut, ht, h), wall, id, print)
        yy = yy + ht
    end
    local roofHt = (biome == "plains" and 3.2 or 2.6) * size
    local roofPrint = snow and snowed or (biome == "plains" and thatched(L, 6) or banded(L))
    if marked then roofPrint = crossedRoof(roofPrint, L.dark) end
    parts[#parts + 1] = part(Sh.roof(x, yy, z, w + 1, d + 1.2, roofHt, h), L.roof, id + 1, roofPrint)
end

-- What stands on a plot no one has built on yet, by the land: a tree and a
-- fenced garden, a haystack and a plot of beds, a palm by a well, a terraced
-- garden of bushes.
local function garden(parts, e, L, id, biome, k)
    local x, y, z = e.x, e.y, e.z
    if biome == "desert" then
        -- A palm, leaning a little, its fronds drooping.
        local lean = (k % 2 == 0) and 0.9 or -0.7
        local tx, ty = x + lean * 0.7, y + 4.6
        parts[#parts + 1] = part(Sh.seg(x, y, z, tx, ty, z, 0.4, 0.3), R.wood, id, function(ux)
            if floor((ux + 1) * 6) % 2 == 0 then return IDX.n end
        end)
        for f = 0, 5 do
            local a = f * math.pi / 3 + k
            parts[#parts + 1] = part(Sh.seg(tx, ty + 0.3, z, tx + cos(a) * 2, ty - 0.8, z + sin(a) * 2, 0.45, 0.2),
                R2.leaf, id + 1)
        end
        if k % 3 == 0 then
            -- A well: a ring of stone.
            parts[#parts + 1] = part(Sh.prism(8, x - 2, y, z + 1.4, 1.1, 1, 0, math.pi / 8), R.stone, id + 2,
                function(ux, uy, uz, lev, nx, ny) if ny > 0.9 and ux * ux + uz * uz < 0.45 then return IDX.o end end)
        end
    elseif biome == "plains" then
        -- Beds of a kitchen garden in rows, and a haystack.
        for r = -1, 1 do
            parts[#parts + 1] = part(Sh.box(x - 0.8, y, z + r * 1.2, 3.2, 0.8, 0.35), R2.soil, id)
        end
        parts[#parts + 1] = part(Sh.ell(x + 1.8, y + 0.3, z - 0.4, 1.2, 1.8, 1.2), R.straw, id + 1,
            function(ux, uy) if floor((uy + 1) * 3) % 2 == 0 and uy > -0.3 then return IDX.t end end)
    elseif biome == "hills" then
        -- Bushes on a terrace of stone.
        parts[#parts + 1] = part(Sh.box(x, y - 1.2, z, 3.6, 3, 1.2), R.stone, id, function(ux, uy)
            if floor((ux + 1) * 5 + (uy > 0.5 and 0.5 or 0)) % 2 == 0 then return IDX.k end
        end)
        for f = 0, 2 do
            parts[#parts + 1] = part(Sh.ell(x - 1.1 + f * 1.1, y + 0.6, z + (f % 2) * 0.6 - 0.3, 0.9, 0.9, 0.9),
                R2.hedge, id + 1)
        end
    else
        -- A tree, and a little fenced garden.
        parts[#parts + 1] = part(Sh.seg(x + 1, y, z - 0.5, x + 1, y + 2.6, z - 0.5, 0.35), R.wood, id)
        parts[#parts + 1] = part(Sh.ell(x + 1, y + 4, z - 0.5, 1.9, 2.1, 1.9), R2.leaf, id + 1)
        parts[#parts + 1] = part(Sh.box(x - 1.2, y, z + 0.6, 2.6, 2.2, 0.3), R2.soil, id + 2, function(ux, uy, uz)
            if floor((ux + 1) * 4) % 2 == 0 then return IDX.u end
        end)
        parts[#parts + 1] = part(Sh.box(x - 1.2, y, z + 1.7, 2.8, 0.15, 0.8), R.wood, id + 3)
    end
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

-- A water mill on the river along edge k: a mill house on the bank and its
-- wheel in the channel, `drop` down to the water. In its own frame with +x
-- out across the edge.
local function mill(parts, drop, id, biome)
    local q = {}
    local bank = 8.36 - 2.5
    local wall = biome == "hills" and R.stone or (biome == "desert" and R2.mud or R.wall)
    q[#q + 1] = part(Sh.box(bank - 1.6, 0, -3.4, 3, 3.4, 3.2), wall, id, windows(1, false))
    q[#q + 1] = part(Sh.roof(bank - 1.6, 3.2, -3.4, 3.8, 4.2, 1.8, math.pi / 2), R.wood, id + 1)
    -- The wheel stands in the channel, its axle out from the bank.
    local wy = -drop + 1.4
    local wheel = Sh.prism(12, 0, -0.5, 0, 2.9, 0.9)
    wheel.at = A.mul(A.move(bank + 0.6, wy, -3.4), A.rotZ(math.pi / 2), wheel.at)
    q[#q + 1] = part(wheel, R.wood, id + 2, function(ux, uy, uz)
        local r = ux * ux + uz * uz
        -- Paddles round the rim, spokes to the hub, and light between.
        if r > 0.6 then
            if floor((math.atan2(uz, ux) / math.pi + 1) * 8) % 2 == 0 then return IDX.u end
            return IDX.c
        end
        if r < 0.04 then return IDX.o end
        if math.abs(ux) < 0.1 or math.abs(uz) < 0.1 or math.abs(ux - uz) < 0.13 or math.abs(ux + uz) < 0.13 then
            return IDX.n
        end
        return IDX.s
    end)
    q[#q + 1] = part(Sh.seg(bank - 0.4, wy, -3.4, bank + 1.6, wy, -3.4, 0.3), R.dark, id + 3)
    for _, p in ipairs(q) do parts[#parts + 1] = p end
    return q
end

-- The hall in the middle, in the style of the land, and (a capital) the
-- palace with its tower, which grows with the city.
local function hall(parts, L, tier, capital, biome, hills)
    local y = hills and 1.2 or 0
    -- A longhouse in a hamlet, a hall in a village, a storey taller in a town.
    local w, d = capital and 8 or (tier == 1 and 5 or 6), capital and 6 or (tier == 1 and 4 or 5)
    local ht = (capital and 4.5 or (tier == 1 and 3 or 4)) + (tier >= 3 and 1.2 or 0)
    if hills then
        -- The hall stands on its own terrace.
        parts[#parts + 1] = part(Sh.box(0, 0, 0, w + 1.6, d + 1.6, y), R.stone, 9, function(ux, uy)
            if floor((ux + 1) * 6 + (uy > 0.5 and 0.5 or 0)) % 2 == 0 then return IDX.k end
        end)
    end
    if biome == "desert" then
        parts[#parts + 1] = part(Sh.box(0, y, 0, w, d, ht, 0), R2.mud, 1, windows(2, true))
        parts[#parts + 1] = part(Sh.box(0, y + ht, 0, w + 0.4, d + 0.4, 0.5), R2.slab, 2)
        -- A dome on a drum, in the city's colours, bigger as it grows.
        local r = 2 + tier * 0.35
        parts[#parts + 1] = part(Sh.prism(12, 0, y + ht + 0.5, 0, r, 1.2, 0, 0), R2.slab, 3)
        parts[#parts + 1] = part(Sh.ell(0, y + ht + 1.7, 0, r, r * 1.05, r), L.roof, 4, banded(L))
        if capital or tier >= 3 then
            -- A slim tower beside it, taller with the city.
            local th = 7 + tier * 2 + (capital and 2 or 0)
            parts[#parts + 1] = part(Sh.prism(8, -w / 2 + 0.6, y, -d / 2 + 0.6, 1.1, th, 0, math.pi / 8), R2.mud, 5,
                function(ux, uy, uz) if uy > 0.8 and uy < 0.88 and uz > 0.5 then return IDX.n, true end end)
            parts[#parts + 1] = part(Sh.prism(8, -w / 2 + 0.6, y + th, -d / 2 + 0.6, 1.4, 0.4, 0, math.pi / 8), R2.slab, 6)
            parts[#parts + 1] = part(Sh.ell(-w / 2 + 0.6, y + th + 0.5, -d / 2 + 0.6, 0.9, 1.3, 0.9), L.roof, 7)
        end
        return
    end
    local wall = (hills or capital) and R.stone or R.wall
    parts[#parts + 1] = part(Sh.box(0, y, 0, w, d, ht), wall, 1, function(ux, uy, uz)
        if uy > 0.2 and uy < 0.75 and math.abs(uz) > 0.98 and floor((ux + 1) * 3) % 2 == 1 then return IDX.k, true end
    end)
    parts[#parts + 1] = part(Sh.roof(0, y + ht, 0, w + 1, d + 1.2, 3.2), L.roof, 2, banded(L))
    if capital then
        -- The palace's tower at its back corner, a storey taller each tier.
        local th = 7 + tier * 2
        parts[#parts + 1] = part(Sh.prism(6, -w / 2 + 1, y, -d / 2 + 0.6, 1.6, th, 0, 0.5), R.stone, 3,
            function(ux, uy, uz) if uy > 0.75 and uy < 0.85 and uz > 0.4 then return IDX.n, true end end)
        parts[#parts + 1] = part(Sh.pyramid(6, -w / 2 + 1, y + th, -d / 2 + 0.6, 2.2, 3.6 + tier * 0.4, 0, 0.5), L.roof, 4)
    elseif tier >= 3 and biome ~= "plains" and not (hills and tier == 3) then
        -- The town's tower: a bell tower of timber on grassland, a stone
        -- keep once it is a city; on hills the keep from the start.
        local th = tier == 3 and 10 or 13
        local stone = tier == 4 or hills
        parts[#parts + 1] = part(Sh.box(-w / 2 + 0.4, y, -d / 2 + 0.4, 2.8, 2.8, th), stone and R.stone or R.wall, 3,
            function(ux, uy, uz)
                if uy > 0.78 and uy < 0.9 and math.abs(ux) < 0.4 and math.abs(uz) > 0.98 then return IDX.o end
                if not stone and (math.abs(ux) > 0.9 or floor(uy * 4) ~= floor(uy * 4 + 0.08)) then return IDX.n end
            end)
        if stone then
            for c = 0, 3 do
                local cx, cz = (c % 2 == 0 and -1 or 1) * 1.15, (c < 2 and -1 or 1) * 1.15
                parts[#parts + 1] = part(Sh.box(-w / 2 + 0.4 + cx, y + th, -d / 2 + 0.4 + cz, 0.7, 0.7, 0.7), R.stone, 4)
            end
        else
            parts[#parts + 1] = part(Sh.pyramid(4, -w / 2 + 0.4, y + th, -d / 2 + 0.4, 2.4, 3.4, 0, math.pi / 4), L.roof, 4)
        end
    end
end

-- On hills, once a town, a temple on a podium at the back of the hex: rows
-- of columns under a pediment; once a city it stands on an acropolis.
local function temple(parts, L, tier)
    local px, pz = 0, -6.6
    local base = tier >= 4 and 3.6 or 2.4
    parts[#parts + 1] = part(Sh.box(px, 0, pz, 8.4, 4.4, base), R.stone, 80, function(ux, uy, uz, lev)
        if floor((ux + 1) * 7 + (floor(uy * 3) % 2) * 0.5) % 2 == 0 and lev ~= 1 then return IDX.k end
    end)
    parts[#parts + 1] = part(Sh.box(px, base, pz, 7.6, 3.6, 0.5), R.wall, 81)
    for c = 0, 5 do
        local cx = px - 3.2 + c * 1.28
        parts[#parts + 1] = part(Sh.prism(8, cx, base + 0.5, pz + 1.3, 0.38, 3.4, 0, math.pi / 8), R.wall, 82)
    end
    parts[#parts + 1] = part(Sh.box(px, base + 0.5, pz - 0.6, 7, 2, 3.4), R.stone, 83)
    parts[#parts + 1] = part(Sh.box(px, base + 3.9, pz, 8, 3.8, 0.5), R.wall, 84)
    parts[#parts + 1] = part(Sh.roof(px, base + 4.4, pz, 8.2, 4, 1.3), L.roof, 85, banded(L))
end

-- A windmill: a tapering tower, a cap, four sails to the front.
local function windmill(parts, x, y, z, L)
    parts[#parts + 1] = part(Sh.frustum(8, 0.7, x, y, z, 1.9, 7.5, 0, math.pi / 8), R.wall, 86, function(ux, uy, uz)
        if uz > 0.7 and math.abs(ux) < 0.3 and uy < 0.25 then return IDX.u, true end
    end)
    parts[#parts + 1] = part(Sh.pyramid(8, x, y + 7.5, z, 1.7, 2.2, 0, math.pi / 8), L.roof, 87)
    local hx, hy, hz = x, y + 7.2, z + 1.7
    for s = 0, 3 do
        local a = math.pi / 4 + s * math.pi / 2
        local ex, ey = hx + cos(a) * 5, hy + sin(a) * 5
        parts[#parts + 1] = part(Sh.seg(hx, hy, hz, ex, ey, hz, 0.18), R.wood, 88)
        local mx, my = hx + cos(a) * 3, hy + sin(a) * 3
        local sail = Sh.box(0, -0.5, 0, 3.6, 0.15, 1.1)
        sail.at = A.mul(A.move(mx - sin(a) * 0.55, my + cos(a) * 0.55, hz), A.rotZ(a), A.rotX(math.pi / 2), sail.at)
        parts[#parts + 1] = part(sail, R.straw, 89 + s, function(ux)
            if floor((ux + 1) * 4) % 2 == 0 then return IDX.t end
        end)
    end
end

--- what rings a city: walls, levee, streets --------------------------------------

-- A hex's corner k (at 60k - 30 degrees), `r` out; where one of the edges
-- meeting there is shared with another of the city's hexes, out at the
-- hex's very corner, so its walls and the next hex's meet.
local CORNER = 8.36 / math.cos(math.pi / 6) - 0.1
local function corner(k, r, joins)
    k = k % 6
    if joins and (joins[(k + 5) % 6] or joins[k]) then r = CORNER end
    local a = math.rad(60 * k - 30)
    return r * cos(a), r * sin(a)
end

-- A run of wall from (x0, z0) to (x1, z1), its top crenellated.
local function curtain(parts, x0, z0, x1, z1, id)
    local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
    if len < 0.2 then return end
    parts[#parts + 1] = part(Sh.box((x0 + x1) / 2, 0, (z0 + z1) / 2, len, 1.6, 3.2, -math.atan2(z1 - z0, x1 - x0)),
        R.stone, id, function(ux, uy) if uy > 0.8 and floor((ux + 1) * len / 1.4) % 2 == 0 then return IDX.k end end)
end

-- The walls round a city's hexes: along each edge of this one not `open`
-- (on the water, a river's moat, or shared with another of the city's
-- hexes), a tower on each of its corners the city's outline gives this hex
-- (`site.towers`; every corner when not told), and on `site.gate` a
-- gatehouse where its street goes out: two square towers and a passage
-- between under a crenellated lintel.
local function ramparts(parts, L, site, open)
    local joins, towers, gate = site.joins, site.towers, site.gate
    for k = 0, 5 do
        local x0, z0 = corner(k, 8.3, joins)
        local x1, z1 = corner(k + 1, 8.3, joins)
        if not open(k) then
            if k == gate then
                local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
                local ux, uz = (x1 - x0) / len, (z1 - z0) / len
                local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
                local turn = -math.atan2(uz, ux)
                local g = 2.6
                curtain(parts, x0, z0, mx - ux * (g / 2 + 1.2), mz - uz * (g / 2 + 1.2), 40)
                curtain(parts, mx + ux * (g / 2 + 1.2), mz + uz * (g / 2 + 1.2), x1, z1, 40)
                for side = -1, 1, 2 do
                    local tx, tz = mx + ux * side * (g / 2 + 1.1), mz + uz * side * (g / 2 + 1.1)
                    parts[#parts + 1] = part(Sh.box(tx, 0, tz, 2.3, 2.5, 5.4, turn), R.stone, 47, function(ux2, uy, uz2)
                        if uy > 0.6 and uy < 0.72 and abs(ux2) < 0.25 then return IDX.o end
                    end)
                    parts[#parts + 1] = part(Sh.pyramid(4, tx, 5.4, tz, 1.95, 2.4, 0, math.pi / 4 + turn), L.roof, 48)
                end
                -- The passage, dark, and the lintel over it.
                parts[#parts + 1] = part(Sh.box(mx, 0, mz, g, 1.2, 3, turn), WATER, 49)
                parts[#parts + 1] = part(Sh.box(mx, 3, mz, g + 0.4, 2.2, 1.5, turn), R.stone, 47, function(ux2, uy)
                    if uy > 0.7 and floor((ux2 + 1) * 3) % 2 == 0 then return IDX.k end
                end)
            else
                curtain(parts, x0, z0, x1, z1, 40)
            end
        end
        if not towers or towers[k] then
            parts[#parts + 1] = part(Sh.prism(6, x0, 0, z0, 1.9, 4.8), R.stone, 41 + k)
            parts[#parts + 1] = part(Sh.pyramid(6, x0, 4.8, z0, 2.3, 2.2), L.roof, 41 + k)
        end
    end
end

-- The levee: banks of earth round the city's hexes, low and broad, faced
-- with stone on top: the city's stand against the water. Gaps where the
-- pier goes out and the bridges cross; none along an edge shared with
-- another of its hexes, so it rings them all.
local function levee(parts, site, open, shore)
    local joins = site.joins
    for k = 0, 5 do
        if not (joins and joins[k]) then
            local x0, z0 = corner(k, 9.5, joins)
            local x1, z1 = corner(k + 1, 9.5, joins)
            local turn = -math.atan2(z1 - z0, x1 - x0)
            local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
            local runs = open(k) and { { 0.18, 0.36 }, { 0.82, 0.36 } } or { { 0.5, 1.04 } }
            for n, run in ipairs(runs) do
                local mx, mz = x0 + (x1 - x0) * run[1], z0 + (z1 - z0) * run[1]
                local l = len * run[2]
                -- The bank, its earth in courses, and a coping of stone.
                parts[#parts + 1] = part(Sh.box(mx, 0, mz, l, 2.4, 1.3, turn), R2.soil, 60 + k * 2 + n,
                    function(ux, uy) if uy < 0.5 and floor((ux + 1) * 9) % 3 == 0 then return IDX.n end end)
                parts[#parts + 1] = part(Sh.box(mx, 1.3, mz, l - 0.4, 1.4, 0.55, turn), R.stone, 60 + k * 2 + n,
                    function(ux) if floor((ux + 1) * 6) % 2 == 0 then return IDX.t end end)
            end
        end
    end
end

-- A street of cobbles out along way k, from r0 to r1 from the hex's middle.
local function street(parts, y, k, r0, r1)
    local a = math.rad(60 * k)
    local r = (r0 + r1) / 2
    local len = r1 - r0
    parts[#parts + 1] = part(Sh.box(r * cos(a), y, r * sin(a), len, 2.6, 0.22, -a), R.stone, 8,
        function(ux, uy, uz, lev)
            if lev ~= 1 and floor((ux + 1) * len * 0.9) % 2 == floor((uz + 1) * 1.6) % 2 then return IDX.t end
        end)
end

-- The picture of a city: its houses (one more for each citizen, till every
-- plot is built on, then taller), its hall or palace, its landmark, and
-- whatever it has built, all in the way of its `site` ({ biome = "grass" |
-- "plains" | "desert", hills, river = { [k] = how far down its water is },
-- seed }). A city on the water is told `shore`, the way (0..5) to the water
-- it faces, and `drop`, how far below its ground (in room units) the
-- water's top is.
-- `pest`, in the plague (src/plague.lua): { marked = the sickness is in
-- it, its houses daubed with crosses; graves = how many it has buried, in
-- rows on its empty plots }.
function M.city(look, pop, capital, built, shore, drop, site, pest)
    local b = built or {}
    local marked = pest and pest.marked or nil
    local graves = pest and math.min(pest.graves or 0, 9) or 0
    site = site or {}
    local biome = site.biome or "grass"
    local lay = M.cityLayout(pop, b, site)
    drop = drop and floor(drop * 2 + 0.5) / 2 or 0
    local key = table.concat({ "c", look, #lay.houses, lay.tier, capital and 1 or 0, b.walls and 1 or 0,
        b.granary and 1 or 0, b.library and 1 or 0, b.market and 1 or 0, b.monument and 1 or 0, shore or "-", drop,
        b.harbour and 1 or 0, b.lighthouse and 1 or 0, b.cistern and 1 or 0, b.levee and 1 or 0, b.shelter and 1 or 0, b.sanctum and 1 or 0, b.hearth and 1 or 0,
        b.lazaret and 1 or 0, b.buttress and 1 or 0, marked and 1 or 0, graves, siteKey(site) }, ":")
    return kept(key, function()
        local L = LOOK[look]
        local parts = {}
        if shore then
            local front = {}
            waterfront(front, L, -drop / M.CITY_SCALE, b)
            place(front, math.rad(60 * shore))
            for _, p in ipairs(front) do parts[#parts + 1] = p end
        end
        if site.river then
            -- One mill, on the first river edge clear of the shore.
            for k = 0, 5 do
                local down = site.river[k]
                if down and k ~= shore then
                    place(mill(parts, down / M.CITY_SCALE, 90, biome), math.rad(60 * k))
                    break
                end
            end
        end
        for k, h in ipairs(lay.houses) do
            if site.hills and h.y > 0 then
                -- The terrace it stands on.
                parts[#parts + 1] = part(Sh.box(h.x, 0, h.z, 4.6 * h.size, 4 * h.size, h.y), R.stone, 9, function(ux, uy)
                    if floor((ux + 1) * 5 + (uy > 0.5 and 0.5 or 0)) % 2 == 0 then return IDX.k end
                end)
            end
            -- Two houses in three bear the plague's cross, while it is there.
            local daub = marked and hash((site.seed or 0) + k, 7) < 0.67
            house(parts, h.x, h.y, h.z, L, 10 + k * 4, h.size, h.storeys, h.turn, site.hills and "hills" or biome, site.snow,
                daub)
            -- The buttress, against the sundering: every house shored up,
            -- a sloping prop of stone at each front corner and timbers
            -- braced in an X across its front wall.
            if b.buttress then
                local w, d = 4 * h.size, 3.4 * h.size
                if h.turn then w, d = d * 1.08, w * 0.92 end
                local tall = STOREY * h.size * h.storeys
                local fz = h.z + d / 2
                for side = -1, 1, 2 do
                    parts[#parts + 1] = part(Sh.frustum(4, 0.2, h.x + side * (w / 2 - 0.2), h.y, fz + 0.2, 0.95,
                        tall * 0.9, 0, math.pi / 4), R.stone, 105)
                end
                for side = -1, 1, 2 do
                    parts[#parts + 1] = part(Sh.seg(h.x - side * (w / 2 - 0.9), h.y + 0.3, fz + 0.15,
                        h.x + side * (w / 2 - 0.9), h.y + tall * 0.8, fz + 0.15, 0.22), R.wood, 106)
                end
            end
        end
        -- The plague's dead, buried on the plots their houses stood on: rows
        -- of three low mounds of fresh earth, a cross of sticks at the head of
        -- each.
        local dug = {}
        for _, e in ipairs(lay.empty) do
            if graves <= 0 then break end
            if not e.what then
                dug[e.plot] = true
                for r = 0, math.min(2, graves - 1) do
                    local gx, gz = e.x - 1.6 + r * 1.6, e.z + (r % 2) * 0.4
                    parts[#parts + 1] = part(Sh.ell(gx, e.y, gz, 0.6, 0.45, 1.3), R2.soil, 140 + r, function(ux, uy, uz)
                        if hash(floor(ux * 5), floor(uz * 5)) > 0.75 then return IDX.n end
                    end)
                    parts[#parts + 1] = part(Sh.seg(gx, e.y, gz - 1.5, gx, e.y + 1.7, gz - 1.5, 0.16), R.wood, 143)
                    parts[#parts + 1] = part(Sh.seg(gx - 0.55, e.y + 1.2, gz - 1.5, gx + 0.55, e.y + 1.2, gz - 1.5, 0.14),
                        R.wood, 143)
                end
                graves = graves - 3
            end
        end
        -- Gardens on a few of the plots not built on yet: fewer as it grows.
        local gardens = ({ 4, 3, 2, 1 })[lay.tier]
        for k, e in ipairs(lay.empty) do
            if e.what == "windmill" then
                windmill(parts, e.x, e.y, e.z, L)
            elseif not e.what and not dug[e.plot] and gardens > 0 and (e.plot + (site.seed or 0)) % 3 ~= 0 then
                gardens = gardens - 1
                garden(parts, e, L, 120 + k * 4, site.hills and "hills" or biome, e.plot + (site.seed or 0))
            end
        end
        hall(parts, L, lay.tier, capital, biome, site.hills)
        if site.hills and lay.tier >= 3 then
            -- The temple takes the back plot's place.
            temple(parts, L, lay.tier)
        end
        local function at(name)
            local p = PLOTS[BUILT_PLOT[name]]
            return p.x, p.z
        end
        if b.granary then
            local x, z = at("granary")
            parts[#parts + 1] = part(Sh.prism(8, x, 0, z, 2, 4.5, 0, 0.4), R.straw, 30)
            parts[#parts + 1] = part(Sh.pyramid(8, x, 4.5, z, 2.6, 2.6, 0, 0.4), L.roof, 31)
        end
        if b.library then
            local x, z = at("library")
            parts[#parts + 1] = part(Sh.box(x, 0, z, 4.6, 3.6, 4, math.pi / 2), R.stone, 32, function(ux, uy, uz)
                if math.abs(uz) > 0.98 and floor((ux + 1) * 4) % 2 == 0 and uy < 0.85 then return IDX.k, true end
            end)
            parts[#parts + 1] = part(Sh.roof(x, 4, z, 5.2, 4.4, 1.6, math.pi / 2), R.stone, 33)
        end
        if b.market then
            local x, z = at("market")
            for k, dz in ipairs({ -1.4, 1.4 }) do
                parts[#parts + 1] = part(Sh.pyramid(4, x - (k - 1.5) * 1.2, 0, z + dz, 1.8, 3, 0, math.pi / 4), L.roof,
                    34 + k, banded(L))
            end
        end
        if b.cistern then
            -- A round stone tower of a tank, standing over the walls, brimming
            -- with dark water: the city's store against the heat.
            local x, z = at("cistern")
            parts[#parts + 1] = part(Sh.prism(12, x, 0, z, 2.6, 4.6), R.stone, 50, function(ux, uy)
                if floor(uy * 5) % 2 == 1 and uy < 0.9 then return IDX.t end
            end)
            parts[#parts + 1] = part(Sh.prism(12, x, 0, z, 1.9, 4.8), WATER, 51, function(ux, uy, uz)
                if uy > 0.98 and ux < -0.15 and uz < -0.1 and ux + uz > -1.0 then return IDX.t end
            end)
        end
        if b.shelter then
            -- The cellars the people hide in: a low mound of turf over them,
            -- a ring of stones round its foot, and a way down into it at the
            -- front, two posts and a lintel of stone, black within.
            local x, z = at("shelter")
            parts[#parts + 1] = part(Sh.ell(x, 0, z, 3, 2.3, 2.6), R2.soil, 80, function(ux, uy, uz)
                if hash(floor(ux * 9), floor(uz * 9 + uy * 5)) > 0.8 then return IDX.k end
            end)
            for k = 0, 7 do
                local a = k / 8 * 2 * math.pi + 0.3
                parts[#parts + 1] = part(Sh.ell(x + cos(a) * 2.9, 0.2, z + sin(a) * 2.5, 0.6, 0.45, 0.5), R.stone, 81)
            end
            parts[#parts + 1] = part(Sh.box(x, 0, z + 2.2, 1.3, 0.8, 1.7), WATER, 82)
            for _, side in ipairs({ -1, 1 }) do
                parts[#parts + 1] = part(Sh.box(x + side * 0.9, 0, z + 2.5, 0.45, 0.45, 1.9), R.stone, 83)
            end
            parts[#parts + 1] = part(Sh.box(x, 1.9, z + 2.5, 2.4, 0.55, 0.5), R.stone, 84)
        end
        if b.sanctum then
            -- The sanctum, against the demons: a ring of tall carved stones,
            -- pale, round a lamp on a plinth kept burning.
            local x, z = at("sanctum")
            for k = 0, 5 do
                local a = k / 6 * 2 * math.pi
                parts[#parts + 1] = part(Sh.box(x + cos(a) * 2.6, 0, z + sin(a) * 2.3, 0.8, 0.7, 5.2 + (k % 2) * 1.2, -a), R.wall,
                    90, function(ux, uy) if floor(uy * 6) % 2 == 0 and abs(ux) < 0.3 then return IDX.t end end)
            end
            parts[#parts + 1] = part(Sh.prism(6, x, 0, z, 0.9, 2.4), R.stone, 91)
            parts[#parts + 1] = part(Sh.ell(x, 3.1, z, 0.7, 0.8, 0.7), GLOW, 92)
        end
        if b.hearth then
            -- The hearth, against the endless night: a squat kiln-house of
            -- stone, domed, its mouth glowing; a tall chimney at its back,
            -- and the wood for it stacked beside, log on log.
            local x, z = at("hearth")
            parts[#parts + 1] = part(Sh.prism(8, x, 0, z, 2.5, 2.2, 0, math.pi / 8), R.stone, 93, function(ux, uy)
                if floor(uy * 4) % 2 == 1 and floor((ux + 1) * 5) % 2 == 0 then return IDX.t end
            end)
            parts[#parts + 1] = part(Sh.ell(x, 2.1, z, 2.5, 1.9, 2.5), R.stone, 94, function(ux, uy, uz)
                if hash(floor(ux * 6), floor(uz * 6 + uy * 4)) > 0.82 then return IDX.t end
            end)
            parts[#parts + 1] = part(Sh.box(x, 0, z + 2.2, 1.5, 0.7, 1.6), GLOW, 95)
            parts[#parts + 1] = part(Sh.prism(4, x + 1, 2.5, z - 1.4, 0.75, 4.6, 0, math.pi / 4), R.stone, 96,
                function(ux, uy) if uy > 0.9 then return IDX.o end end)
            for k = 0, 2 do
                local lz = z + 0.8 + (k - 1) * 0.75
                parts[#parts + 1] = part(Sh.seg(x - 4.2, 0.35 + (k % 2) * 0.7, lz, x - 2.6, 0.35 + (k % 2) * 0.7, lz, 0.38),
                    R.wood, 97)
            end
        end
        if b.lazaret then
            -- The lazaret, against the plague: a long low house of the sick,
            -- whitewashed, a row of small windows down its side lit at night,
            -- its roof the city's colours, a plain cross on its gable end,
            -- and a herb garden in beds before it.
            local x, z = at("lazaret")
            parts[#parts + 1] = part(Sh.box(x, 0, z, 6.2, 3, 2.6, 0.5), R.wall, 98, function(ux, uy, uz)
                if abs(uz) > 0.98 and uy > 0.35 and uy < 0.7 and floor((ux + 1) * 5) % 2 == 1 then return IDX.n, true end
                if abs(ux) > 0.98 and abs(uz) < 0.2 and uy < 0.75 then return IDX.u, true end
            end)
            parts[#parts + 1] = part(Sh.roof(x, 2.6, z, 6.8, 3.6, 1.7, 0.5), L.roof, 99, banded(L))
            local gx, gz = x + cos(0.5) * 3.7, z - sin(0.5) * 3.7
            parts[#parts + 1] = part(Sh.seg(gx, 2.7, gz, gx, 5.1, gz, 0.2), R.wood, 100)
            parts[#parts + 1] = part(Sh.seg(gx, 4.3, gz - 0.7, gx, 4.3, gz + 0.7, 0.18), R.wood, 100)
            for r = -1, 1 do
                parts[#parts + 1] = part(Sh.box(x + 0.6 * r, 0, z + 2.8, 1.4, 0.7, 0.4, 0.5), R2.hedge, 101)
            end
        end
        local open = function(k) return k == shore or (site.river and site.river[k]) or (site.joins and site.joins[k]) end
        if b.levee then levee(parts, site, open, shore) end
        if b.monument then
            local x, z = at("monument")
            parts[#parts + 1] = part(Sh.box(x, 0, z, 2.4, 2.4, 1), R.stone, 37)
            parts[#parts + 1] = part(Sh.frustum(4, 0.45, x, 1, z, 0.9, 7, 0, math.pi / 4), R.stone, 38)
        end
        if b.walls then ramparts(parts, L, site, open) end
        if site.joins then
            -- A street out to each of its quarters, from the hall's door
            -- across the edge, where the plot on that edge was.
            for k = 0, 5 do
                if site.joins[k] then street(parts, site.hills and 1.2 or 0, k, 3.6, 9.2) end
            end
        end
        return parts
    end, M.CITY_SCALE)
end

--- quarters -----------------------------------------------------------------------

-- A quarter (src/quarters.lua): a hex a city has spilled over into. Its
-- street comes in from the hex it grew out of (`q.toward`) to a little
-- square in its middle and goes on out its far side (`q.gate`); houses fill
-- its plots from the near edge out as it fills (`q.stage`, 1..3), turned to
-- face in round the square, so its roofs run in rows round it, lower than
-- the city's heart. What stands in it is told by its land, as the city's
-- own picture is:
--   grass: timber and gabled, a well, then a guildhall with a belfry;
--   plains: round thatched huts, a barn, then a windmill;
--   desert: mud brick, a fountain under palms, a bazaar of awnings;
--   hills: stone houses on terraces, a round shrine of columns;
--   on the water (`q.docks`, the first of its quarters there): a docks
--   quarter, warehouses on its bank, the quay and its
--   crane out over the water (and the lighthouse, if the city has one);
--   by a river: a mill on the bank, its wheel turning.
-- It takes the city's walls, levee and buttress (`q.built`), its colours
-- (`look`), and the plague's marks (`q.marked`).

local function well(parts, x, y, z, L)
    parts[#parts + 1] = part(Sh.prism(8, x, y, z, 1.1, 1.1, 0, math.pi / 8), R.stone, 150, function(ux, uy, uz, lev, nx, ny)
        if ny > 0.9 and ux * ux + uz * uz < 0.45 then return IDX.o end
    end)
    for side = -1, 1, 2 do
        parts[#parts + 1] = part(Sh.seg(x + side * 0.9, y, z, x + side * 0.9, y + 2.6, z, 0.18), R.wood, 151)
    end
    parts[#parts + 1] = part(Sh.roof(x, y + 2.6, z, 2.6, 2, 0.9), L.roof, 152)
end

local function guildhall(parts, x, y, z, h, L)
    local q = {}
    q[#q + 1] = part(Sh.box(0, 0, 0, 6, 4.2, 2.8), R.stone, 153, windows(1, true))
    q[#q + 1] = part(Sh.box(0, 2.8, 0, 6.4, 4.6, 2.6), R.wall, 154, function(ux, uy, uz, lev)
        local k, lit = windows(1, false)(ux, uy, uz, lev)
        if k then return k, lit end
        if uy > 0.9 or uy < 0.08 or abs(ux) > 0.92 or abs(abs(ux) - 0.5) < 0.05 then return IDX.n end
    end)
    q[#q + 1] = part(Sh.roof(0, 5.4, 0, 7.2, 5.6, 3.6), L.roof, 155, banded(L))
    -- A belfry on the ridge, open, its bell dark in it.
    q[#q + 1] = part(Sh.box(1.2, 7.6, 0, 1.4, 1.4, 1.6), R.wood, 156, function(ux, uy, uz)
        if uy > 0.25 and uy < 0.85 and abs(ux) < 0.6 and abs(uz) < 0.6 then return IDX.o end
    end)
    q[#q + 1] = part(Sh.pyramid(4, 1.2, 9.2, 0, 1.3, 1.8, 0, math.pi / 4), L.roof, 157)
    place(q, h, x, y, z)
    for _, p in ipairs(q) do parts[#parts + 1] = p end
end

local function barn(parts, x, y, z, h, L)
    local q = {}
    q[#q + 1] = part(Sh.box(0, 0, 0, 6.4, 4, 3), R.wood, 158, function(ux, uy, uz)
        if abs(ux) > 0.98 and abs(uz) < 0.35 and uy < 0.8 then return IDX.o end
        if floor((uz + 1) * 6) % 2 == 0 and abs(ux) > 0.98 then return IDX.n end
        if floor((ux + 1) * 9) % 2 == 0 and abs(uz) > 0.98 then return IDX.n end
    end)
    q[#q + 1] = part(Sh.roof(0, 3, 0, 7.2, 5, 3.4), L.roof, 159, thatched(L, 6))
    place(q, h, x, y, z)
    for _, p in ipairs(q) do parts[#parts + 1] = p end
end

local function warehouse(parts, x, y, z, h, L)
    local q = {}
    q[#q + 1] = part(Sh.box(0, 0, 0, 6.6, 3.6, 3.4), R.stone, 160, function(ux, uy, uz)
        if abs(uz) > 0.98 and uy < 0.75 and abs((ux + 1) * 1.5 % 1 - 0.5) < 0.18 then return IDX.o end
        if uy > 0.92 then return IDX.k end
    end)
    q[#q + 1] = part(Sh.roof(0, 3.4, 0, 7, 4.2, 1.8), R.wood, 161, function(ux)
        if floor((ux + 1) * 7) % 2 == 0 then return IDX.n end
    end)
    -- A hoist beam out over its door, a bale hung on it.
    q[#q + 1] = part(Sh.seg(0, 3.2, 1.8, 0, 3.2, 3.2, 0.2), R.wood, 162)
    q[#q + 1] = part(Sh.box(0, 1.6, 3.1, 0.9, 0.9, 0.9), R.straw, 163)
    place(q, h, x, y, z)
    for _, p in ipairs(q) do parts[#parts + 1] = p end
end

local function bazaar(parts, y, L, stage)
    for n = 0, (stage >= 3 and 5 or 3) do
        local a = math.pi / 6 + n * math.pi / 3
        local x, z = cos(a) * 3.6, sin(a) * 3.6
        parts[#parts + 1] = part(Sh.box(x, y, z, 1.8, 1.4, 1, -a), R.wood, 164)
        for c = -1, 1, 2 do
            parts[#parts + 1] = part(Sh.seg(x + c * 0.8 * sin(a), y, z - c * 0.8 * cos(a),
                x + c * 0.8 * sin(a), y + 2.6, z - c * 0.8 * cos(a), 0.12), R.wood, 165)
        end
        parts[#parts + 1] = part(Sh.roof(x, y + 2.4, z, 2.6, 2.4, 0.8, -a + math.pi / 2), L.roof, 166, banded(L))
    end
end

local function fountain(parts, y, L)
    parts[#parts + 1] = part(Sh.prism(8, 0, y, 0, 2, 0.8, 0, math.pi / 8), R2.slab, 167)
    parts[#parts + 1] = part(Sh.prism(8, 0, y, 0, 1.6, 0.9, 0, math.pi / 8), WATER, 168, function(ux, uy, uz)
        if uy > 0.98 and ux < -0.2 and uz < -0.1 then return IDX.t end
    end)
    parts[#parts + 1] = part(Sh.prism(6, 0, y, 0, 0.35, 2.2), R2.slab, 169)
    parts[#parts + 1] = part(Sh.ell(0, y + 2.3, 0, 0.7, 0.35, 0.7), R2.slab, 169)
end

local function tholos(parts, y, L)
    parts[#parts + 1] = part(Sh.prism(12, 0, y, 0, 2.8, 0.7), R.stone, 170)
    for n = 0, 7 do
        local a = n * math.pi / 4
        parts[#parts + 1] = part(Sh.prism(6, cos(a) * 2.2, y + 0.7, sin(a) * 2.2, 0.28, 3.2), R.wall, 171)
    end
    parts[#parts + 1] = part(Sh.prism(12, 0, y + 3.9, 0, 2.7, 0.5), R.wall, 172)
    parts[#parts + 1] = part(Sh.pyramid(12, 0, y + 4.4, 0, 2.9, 2, 0, 0), L.roof, 173, banded(L))
end

-- How many of its plots a quarter has built on, at each stage.
local QUARTER_HOUSES = { 4, 7, 11 }

-- Where a quarter's houses go: in rows along its street, gable ends to it,
-- a row each side and one behind each of those, the square left open at the
-- crossing in the middle; within the hex, off the water and a river's bank.
-- Built from the end the street comes in at, out to the far one.
local SLOTS = {}
for _, v in ipairs({ -3.5, 3.5 }) do
    for _, u in ipairs({ 7.0, 3.5, -3.5, -7.0 }) do SLOTS[#SLOTS + 1] = { u, v, "in" } end
end
for _, v in ipairs({ -7.0, 7.0 }) do
    for _, u in ipairs({ 3.6, 0, -3.6 }) do SLOTS[#SLOTS + 1] = { u, v, "out" } end
end

local function quarterLayout(q)
    local seed = q.seed or 0
    local houses, empty = {}, {}
    local want = QUARTER_HOUSES[math.max(1, math.min(3, q.stage or 3))]
    local a = math.rad(60 * (q.toward or 0))
    local eu, ev = { cos(a), sin(a) }, { -sin(a), cos(a) }
    local here = {}
    for k, s in ipairs(SLOTS) do
        local u = s[1] + (hash(seed + k, 1) - 0.5) * 0.5
        local v = s[2] + (hash(seed + k, 2) - 0.5) * 0.4
        local x, z = eu[1] * u + ev[1] * v, eu[2] * u + ev[2] * v
        local ok = true
        for e = 0, 5 do
            local b = math.rad(60 * e)
            local d = x * cos(b) + z * sin(b)
            local wet = (q.river and q.river[e]) or q.shore == e
            if d > (wet and 4.6 or 6.2) then ok = false end
        end
        if ok then
            local y = q.hills and math.max(0, math.min(3.6, floor((1.5 - z) / 2.6) * 1.2)) or 0
            here[#here + 1] = { x = x, y = y, z = z, plot = k, ring = s[3], size = 0.86, d = -u + hash(seed + k, 5) * 0.8,
                -- Squared to the nearest right angle, as the middle's houses
                -- stand, so a street on the slant steps rather than leans.
                face = floor((a + math.pi / 2) / (math.pi / 2) + 0.5) * math.pi / 2 }
        end
    end
    table.sort(here, function(p, r) return p.d < r.d end)
    for n, h in ipairs(here) do
        if n <= want then
            local storeys = 1
            if q.stage >= 2 and h.ring == "in" then storeys = 2 end
            if q.stage >= 3 and hash(seed + h.plot, 3) < 0.35 then storeys = 2 end
            if storeys == 2 and hash(seed + h.plot, 6) < 0.25 then storeys = 1 end
            h.storeys = storeys
            h.size = 0.8 + hash(seed + h.plot, 4) * 0.14
            houses[#houses + 1] = h
        else
            empty[#empty + 1] = h
        end
    end
    return houses, empty
end

function M.quarter(look, q)
    local b = q.built or {}
    local stage = math.max(1, math.min(3, q.stage or 3))
    local biome = q.biome or "grass"
    local drop = q.drop and floor(q.drop * 2 + 0.5) / 2 or 0
    local key = table.concat({ "q", look, stage, biome, q.hills and 1 or 0, q.snow and 1 or 0, q.seed or 0,
        q.toward or "-", q.gate or "-", q.shore or "-", drop, edgesKey(q.joins), edgesKey(q.towers),
        siteKey({ biome = biome, river = q.river }), b.walls and 1 or 0, b.levee and 1 or 0, b.buttress and 1 or 0,
        b.lighthouse and 1 or 0, q.marked and 1 or 0, q.docks and 1 or 0 }, ":")
    return kept(key, function()
        local L = LOOK[look]
        local parts = {}
        local houses, empty = quarterLayout({ seed = q.seed, stage = stage, toward = q.toward, gate = q.gate,
            river = q.river, shore = q.shore, hills = q.hills })
        local style = q.hills and "hills" or biome
        local gy = q.hills and 1.2 or 0
        -- The street in from the hex it grew from, to the square, and out.
        if q.toward then
            street(parts, 0, q.toward, 2.4, 9.2)
            -- Out the far side once it has filled that far, to the gate.
            local out = (q.toward + 3) % 6
            if stage >= 2 and not (q.joins and q.joins[out]) and out ~= q.shore and not (q.river and q.river[out]) then
                street(parts, 0, out, 2.4, (b.walls and q.gate) and 9.2 or 7.4)
            end
        end
        parts[#parts + 1] = part(Sh.prism(8, 0, 0, 0, 3, gy + 0.22, 0, math.pi / 8), R.stone, 8, function(ux, uy, uz, lev)
            if lev ~= 1 and floor((ux + 2) * 4) % 2 == floor((uz + 2) * 4) % 2 then return IDX.t end
        end)
        -- What its land puts in the square.
        if biome == "desert" and not q.hills then
            fountain(parts, gy + 0.22, L)
            if stage >= 2 then bazaar(parts, gy + 0.22, L, stage) end
        elseif q.hills and stage >= 3 then
            tholos(parts, gy + 0.22, L)
        else
            well(parts, 0.6, gy + 0.22, -0.4, L)
        end
        -- The docks: the plots nearest the water hold warehouses, and the
        -- quay goes out over it.
        local docks = {}
        if q.shore then
            local front = {}
            waterfront(front, L, -drop / M.CITY_SCALE, q.docks and { harbour = true, lighthouse = b.lighthouse } or {})
            place(front, math.rad(60 * q.shore))
            for _, p in ipairs(front) do parts[#parts + 1] = p end
            local a = math.rad(60 * q.shore)
            table.sort(houses, function(u, v)
                return u.x * cos(a) + u.z * sin(a) > v.x * cos(a) + v.z * sin(a)
            end)
            if q.docks then
                for n = 1, math.min(stage, 2) do if houses[n] then docks[houses[n]] = true end end
            end
        end
        if q.river then
            -- The mill on a bank of its own, not one shared with the city.
            local at
            for k = 0, 5 do
                if q.river[k] and k ~= q.shore and not (q.joins and q.joins[k]) then at = at or k end
            end
            for k = 0, 5 do
                local down = q.river[k]
                if down and k == at then
                    place(mill(parts, down / M.CITY_SCALE, 90, biome), math.rad(60 * k))
                    break
                end
            end
        end
        -- The landmarks of its land, on the plots farthest out.
        local mark = {}
        local last, before = houses[#houses], houses[#houses - 1]
        if not q.hills and not q.shore then
            if biome == "grass" and stage >= 3 then mark[last] = "guild"
            elseif biome == "plains" and stage >= 2 then
                mark[last] = "barn"
                if stage >= 3 and before then mark[before] = "windmill" end
            end
        end
        for k, h in ipairs(houses) do
            if docks[h] then
                warehouse(parts, h.x, h.y, h.z, h.face, L)
            elseif mark[h] == "guild" then
                guildhall(parts, h.x * 0.92, h.y, h.z * 0.92, h.face, L)
            elseif mark[h] == "barn" then
                barn(parts, h.x, h.y, h.z, h.face, L)
            elseif mark[h] == "windmill" then
                windmill(parts, h.x, h.y, h.z, L)
            else
                if q.hills and h.y > 0 then
                    parts[#parts + 1] = part(Sh.box(h.x, 0, h.z, 4.6 * h.size, 4 * h.size, h.y), R.stone, 9,
                        function(ux, uy)
                            if floor((ux + 1) * 5 + (uy > 0.5 and 0.5 or 0)) % 2 == 0 then return IDX.k end
                        end)
                end
                local one = {}
                house(one, 0, 0, 0, L, 10 + k * 4, h.size, h.storeys, false, style, q.snow,
                    q.marked and hash((q.seed or 0) + k, 7) < 0.67)
                if b.buttress then
                    local w, d = 4 * h.size, 3.4 * h.size
                    local tall = STOREY * h.size * h.storeys
                    for side = -1, 1, 2 do
                        one[#one + 1] = part(Sh.frustum(4, 0.2, side * (w / 2 - 0.2), 0, d / 2 + 0.2, 0.95, tall * 0.9, 0,
                            math.pi / 4), R.stone, 105)
                    end
                end
                place(one, h.face, h.x, h.y, h.z)
                for _, p in ipairs(one) do parts[#parts + 1] = p end
            end
        end
        -- Gardens on the plots it has not reached yet.
        for k, e in ipairs(empty) do
            if k <= 3 then garden(parts, e, L, 120 + k * 4, style, e.plot + (q.seed or 0)) end
        end
        local function open(k) return k == q.shore or (q.river and q.river[k]) or (q.joins and q.joins[k]) end
        local site = { joins = q.joins, towers = q.towers, gate = q.gate }
        if b.levee then levee(parts, site, open, q.shore) end
        if b.walls then ramparts(parts, L, site, open) end
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

-- A mine. Not one picture stamped on every hex, but put together from the
-- hex's `site` (src/ui/board.lua works it out from the mines round it):
--
--   site.kind    "shaft" (hills, star iron), "quarry" (stone) or "gems"
--   site.role    "lone" (no mine beside it), "pithead" (the one of a run its
--                neighbours carry to: the headframe, the crane, the windlass,
--                the hut) or "workings" (an adit, a cut face: the digging)
--   site.links   the edges its tracks run out by, to the next mine on
--   site.layout  which of M.MINE_LAYOUTS, so no two beside each other match
--   site.variant 0 or 1, what else stands about
--   site.hills   each piece stands on the hill's mound rather than in it
--
-- Things stand out towards the hex's corners (six slots) and tracks run from
-- the middle to the edges' middles, between them, so they never run through
-- anything; a track that leaves by an edge meets its neighbour's there.
local MINE_SCALE = 1.4
M.MINE_SCALE = MINE_SCALE
local MINE_EDGE = H.APOTHEM / MINE_SCALE - 0.15
local SLOT_R = 5.6
-- Slot k stands towards the corner at 30 + 60k degrees: 0 front right, 1
-- front, 2 front left, 3 back left, 4 back, 5 back right.
local function slotAt(k)
    local a = math.rad(30 + 60 * k)
    return SLOT_R * cos(a), SLOT_R * sin(a)
end
-- `main` and `second` are at the back, where something tall hides nothing;
-- `side` and `other` at the front. `out` is the edge a lone mine's track
-- leaves by, away from its hut.
M.MINE_LAYOUTS = {
    { main = 3, second = 5, side = 0, other = 2, out = 2 },
    { main = 5, second = 3, side = 2, other = 0, out = 1 },
    { main = 4, second = 3, side = 0, other = 2, out = 2 },
}

-- The ground under (x, z) in model units: the hill's middle mound.
local function mineGround(hills)
    if not hills then return function() return 0 end end
    return function(x, z)
        local u, v = x * MINE_SCALE / 9.5, z * MINE_SCALE / 7.5
        local h = 1 - u * u - v * v
        return h > 0 and math.max(0, (-0.8 + 4 * math.sqrt(h)) / MINE_SCALE - 0.3) or 0
    end
end

-- Where everything of a site goes: the slots each piece takes, the starts of
-- the spurs into the middle and the tracks out, in model units.
local HUB_X, HUB_Z = 0, 0.6
local function minePlan(site)
    local L = M.MINE_LAYOUTS[site.layout] or M.MINE_LAYOUTS[1]
    local kind, role = site.kind or "shaft", site.role or "lone"
    local p = { L = L, kind = kind, role = role }
    -- What stands in each slot.
    local main, second, side, other
    if kind == "shaft" then
        if role == "pithead" then main, side, other = "frame", "hut", "timber"
        elseif role == "workings" then
            -- An adit and its ore; a smaller adit, more spoil and props; or
            -- a bell pit worked from a windlass, its spoil beside it.
            local v = site.variant or 0
            if v == 0 then main, side = "adit", "ore"
            elseif v == 1 then main, side = "smalladit", "timber"
            else main, second, side = "windlass", "heap", "ore" end
        else main, second, side, other = "adit", "frame", "hut", "ore" end
    elseif kind == "quarry" then
        if role == "pithead" then main, second, side, other = "crane", "face", "hut", "blocks"
        elseif role == "workings" then main, second, side = "bigface", (site.variant or 0) > 0 and "rubble" or nil, "blocks"
        else main, second, side, other = "bigface", "crane", "hut", "blocks" end
    else
        if role == "pithead" then main, second, side, other = "windlass", "heap", "tent", "trough"
        elseif role == "workings" then
            main, second, side = "smalladit", (site.variant or 0) > 0 and "heap" or nil, "trough"
        else main, second, side, other = "adit", "windlass", "tent", "trough" end
    end
    p.pieces = {}
    for _, q in ipairs({ { main, L.main }, { second, L.second }, { side, L.side }, { other, L.other } }) do
        if q[1] then
            local x, z = slotAt(q[2])
            p.pieces[#p.pieces + 1] = { what = q[1], slot = q[2], x = x, z = z }
        end
    end
    -- The tracks: a spur from the main piece's foot into the middle, then out
    -- by each linked edge (a lone mine's by its own way out).
    local m = p.pieces[1]
    local foot = { m.x, m.z + 1.4 }
    if m.what == "adit" then foot = { m.x, m.z + 3.6 } end
    if m.what == "smalladit" then foot = { m.x, m.z + 2.8 } end
    if m.what == "bigface" then foot = { m.x, m.z + 3.2 } end
    p.tracks = { { foot[1], foot[2], HUB_X, HUB_Z } }
    local outs = {}
    for e = 0, 5 do if site.links and site.links[e] then outs[#outs + 1] = e end end
    if #outs == 0 and role == "lone" then outs[1] = L.out end
    for _, e in ipairs(outs) do
        local a = math.rad(60 * e)
        p.tracks[#p.tracks + 1] = { HUB_X, HUB_Z, MINE_EDGE * cos(a), MINE_EDGE * sin(a) }
    end
    return p
end

-- The tracks of a site, in model units, for the ground under them to be
-- laid too (src/ui/board.lua).
function M.mineTracks(site) return minePlan(site).tracks end

-- Where a site's hut's chimney is (room units off the hex's middle top), or
-- nil if it has no hut.
function M.mineHut(site)
    for _, q in ipairs(minePlan(site).pieces) do
        if q.what == "hut" then
            local y = mineGround(site.hills)(q.x, q.z)
            return (q.x + 0.8) * MINE_SCALE, (y + 5.2) * MINE_SCALE, q.z * MINE_SCALE
        end
    end
end

-- The slot of a site's headframe, if it has one (its wheel turns).
local function frameSlot(site)
    for _, q in ipairs(minePlan(site).pieces) do
        if q.what == "frame" then return q.slot end
    end
end
M.mineFrame = frameSlot

--- the pieces, each standing at (x, z) on the ground gr(x, z) ---

local function rails(parts, ax, az, bx, bz, gr)
    local dx, dz = bx - ax, bz - az
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 0.5 then return end
    local nx, nz = -dz / len * 0.75, dx / len * 0.75
    local steps = math.max(2, math.ceil(len / 2.4))
    for _, side in ipairs({ -1, 1 }) do
        local px, pz = ax + nx * side, az + nz * side
        local py = gr(px, pz)
        for k = 1, steps do
            local qx, qz = ax + dx * k / steps + nx * side, az + dz * k / steps + nz * side
            local qy = gr(qx, qz)
            parts[#parts + 1] = part(Sh.seg(px, py + 0.32, pz, qx, qy + 0.32, qz, 0.2), R.dark, 3)
            px, pz, py = qx, qz, qy
        end
    end
    -- Sleepers under them, light against the dark rails.
    local turn = -math.atan2(dz, dx)
    for k = 0, math.floor(len / 1.7) do
        local t = (k + 0.5) * 1.7 / len
        if t < 1 then
            local x, z = ax + dx * t, az + dz * t
            parts[#parts + 1] = part(Sh.box(x, gr(x, z), z, 0.55, 2.3, 0.22, turn), R.wood, 6)
        end
    end
end

local function cart(parts, x, z, turn, gr, load)
    local y = gr(x, z)
    parts[#parts + 1] = part(Sh.box(x, y + 0.6, z, 3, 2.2, 1.5, turn), R.wood, 4)
    if load == "block" then
        parts[#parts + 1] = part(Sh.box(x, y + 2.1, z, 1.8, 1.6, 1.3, turn + 0.3), R.stone, 5, function(ux, uy)
            if uy > 0.95 then return IDX.c end
        end)
    else
        parts[#parts + 1] = part(Sh.ell(x, y + 2.1, z, 1.3, 0.8, 1.1), R.dark, 5, function(ux, uy, uz)
            if uy > 0.5 and floor(ux * 4 + uz * 4) % 3 == 0 then return IDX.t end
        end)
    end
end

-- Spoil is the dark of the rock dug out, so a run of heaps lies back
-- behind what stands among them.
local SPOIL = ramp("t", "k", "n", "u")
-- A heap of spoil, `s` its size; with an adit, the dark mouth in its face
-- framed in timber.
local function heap(parts, x, z, gr, s, adit)
    local fz = z + 3.2 * s
    local y = math.max(gr(x, z), gr(x, fz))
    parts[#parts + 1] = part(Sh.ell(x, y, z, 4.2 * s, 3.5 * s, 3.4 * s), SPOIL, 1, function(ux, uy, uz)
        if adit and uz > 0.55 and math.abs(ux) < 0.32 and uy < 0.6 then return IDX.o end
        if floor(ux * 6 + uy * 3) % 5 == 0 and floor(uz * 5 - uy * 4) % 3 == 0 then return IDX.c end
    end)
    if adit then
        local w, ht = 1.4 * s / 0.85, 2.6 * s / 0.85
        parts[#parts + 1] = part(Sh.seg(x - w, y, fz, x - w, y + ht, fz, 0.45), R.straw, 2)
        parts[#parts + 1] = part(Sh.seg(x + w, y, fz, x + w, y + ht, fz, 0.45), R.straw, 2)
        parts[#parts + 1] = part(Sh.seg(x - w - 0.6, y + ht + 0.1, fz, x + w + 0.6, y + ht + 0.1, fz, 0.5), R.straw, 2)
    end
end

-- The headframe: an A of two legs seen from the front, a strut behind, the
-- rope down the shaft from where the wheel turns (M.mineWheel).
local function headframe(parts, tx, tz, gr)
    local ty = gr(tx, tz)
    local top = ty + 8
    parts[#parts + 1] = part(Sh.seg(tx - 2.6, ty, tz + 0.6, tx - 0.4, top, tz + 0.2, 0.45), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(tx + 2.6, ty, tz + 0.6, tx + 0.4, top, tz + 0.2, 0.45), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(tx, ty, tz - 3.4, tx, top - 0.3, tz, 0.4), R.wood, 7)
    parts[#parts + 1] = part(Sh.seg(tx - 1.8, ty + 3.2, tz + 0.5, tx + 1.8, ty + 3.2, tz + 0.5, 0.35), R.wood, 8)
    parts[#parts + 1] = part(Sh.seg(tx + 2.1, top + 0.6, tz + 0.8, tx + 2.1, ty + 0.3, tz + 0.8, 0.14), R.dark, 11)
    -- The shaft's collar, dark, between the legs.
    parts[#parts + 1] = part(Sh.ell(tx, ty, tz + 0.4, 1.6, 0.3, 1.2), R.dark, 9)
end

-- The miners' hut: whitewashed, its gable and door to the front.
local function hut(parts, x, z, gr)
    local y = gr(x, z)
    parts[#parts + 1] = part(Sh.box(x, y, z, 4, 3, 2.4), R.wall, 12, function(ux, uy, uz)
        if math.abs(ux + 0.3) < 0.22 and uy < 0.75 and uz > 0.98 then return IDX.u end
        if math.abs(ux - 0.45) < 0.16 and uy > 0.35 and uy < 0.7 and uz > 0.98 then return IDX.u end
    end)
    parts[#parts + 1] = part(Sh.roof(x, y + 2.4, z, 3.8, 5, 2.6, math.pi / 2), R.wood, 13)
end

-- Pit props waiting: logs stacked three, two, one.
local function timber(parts, x, z, gr)
    local y = gr(x, z)
    for row, n in ipairs({ 3, 2, 1 }) do
        for k = 1, n do
            local zz = z + (k - (n + 1) / 2) * 0.95
            local yy = y + 0.45 + (row - 1) * 0.8
            parts[#parts + 1] = part(Sh.seg(x - 1.9, yy, zz, x + 1.9, yy, zz, 0.45), R.wood, 14, function(ux)
                if ux > 0.93 then return IDX.c end
            end)
        end
    end
end

-- A pile of ore and a lump or two off it.
local function ore(parts, x, z, gr)
    local y = gr(x, z)
    parts[#parts + 1] = part(Sh.ell(x, y, z, 2, 1.3, 1.7), R.dark, 15, function(ux, uy, uz)
        if floor(ux * 5 + uz * 4 + uy * 3) % 3 == 0 then return IDX.t end
    end)
    parts[#parts + 1] = part(Sh.ell(x + 2, gr(x + 2, z + 0.8), z + 0.8, 0.6, 0.5, 0.6), R.dark, 15)
    parts[#parts + 1] = part(Sh.ell(x - 1.6, gr(x - 1.6, z + 1.2), z + 1.2, 0.5, 0.4, 0.5), R.dark, 15)
end

-- A quarry's cut face: benches of rock stepping down to the front, the
-- drill marks dark down their faces and the cut tops pale.
local QUARRY = ramp("s", "t", "k", "n")
local function face(parts, x, z, gr, s)
    local y = gr(x, z)
    -- Pale where it is freshly cut on top, a dark seam or two along its face.
    local strata = function(ux, uy, uz)
        if uy > 0.95 then return IDX.c end
        if uz > 0.96 and (floor(uy * 7) == 2 or floor(uy * 7) == 5) then return IDX.n end
    end
    local turn = x < 0 and 0.35 or -0.35
    parts[#parts + 1] = part(Sh.box(x, y - 0.6, z - 1.6 * s, 6 * s, 2.6 * s, 3.6 * s, turn), QUARRY, 16, strata)
    parts[#parts + 1] = part(Sh.box(x + 0.5 * s, y - 0.6, z + 0.3 * s, 5 * s, 2 * s, 2.3 * s, turn), QUARRY, 17, strata)
    parts[#parts + 1] = part(Sh.box(x - 0.4 * s, y - 0.6, z + 1.9 * s, 3.6 * s, 1.6 * s, 1.2 * s, turn), QUARRY, 18, strata)
    -- Spalls fallen at its foot.
    for k, q in ipairs({ { 2.6, 2.6 }, { -2.2, 3 }, { 0.6, 3.4 } }) do
        local xx, zz = x + q[1] * s, z + q[2] * s
        parts[#parts + 1] = part(Sh.pyramid(5, xx, gr(xx, zz) - 0.2, zz, 0.7, 0.8, 0, k), R.stone, 20)
    end
end

-- Cut blocks, two and one on them.
local function blocks(parts, x, z, gr)
    local y = gr(x, z)
    local top = function(ux, uy) if uy > 0.95 then return IDX.c end end
    parts[#parts + 1] = part(Sh.box(x - 1, y, z, 1.8, 1.7, 1.5, 0.1), R.stone, 19, top)
    parts[#parts + 1] = part(Sh.box(x + 1, y, z + 0.2, 1.8, 1.7, 1.5, -0.1), R.stone, 19, top)
    parts[#parts + 1] = part(Sh.box(x, y + 1.5, z + 0.1, 1.8, 1.6, 1.4, 0.25), R.stone, 19, top)
end

-- Rubble off the cutting: a few broken stones.
local function rubble(parts, x, z, gr)
    for k, q in ipairs({ { 0, 0, 1.4 }, { 1.6, 0.6, 1 }, { -1.3, 0.9, 0.9 }, { 0.5, -1.2, 0.8 } }) do
        local xx, zz = x + q[1], z + q[2]
        parts[#parts + 1] = part(Sh.pyramid(5, xx, gr(xx, zz) - 0.2, zz, q[3], q[3] * 1.2, 0, k), R.stone, 20)
    end
end

-- A wooden crane over the cut, its boom out towards the middle and a block
-- hanging off it.
local function crane(parts, x, z, gr)
    local y = gr(x, z)
    local top = y + 9
    parts[#parts + 1] = part(Sh.seg(x, y, z, x, top, z, 0.42), R.wood, 21)
    parts[#parts + 1] = part(Sh.seg(x - 1.8, y, z + 0.4, x, y + 3.2, z, 0.3), R.wood, 21)
    parts[#parts + 1] = part(Sh.seg(x + 1.8, y, z + 0.4, x, y + 3.2, z, 0.3), R.wood, 21)
    local d = math.sqrt(x * x + z * z)
    local bx, bz = x - x / d * 5, z - z / d * 5 + 0.5
    parts[#parts + 1] = part(Sh.seg(x, y + 2, z, bx, y + 8, bz, 0.32), R.wood, 22)
    parts[#parts + 1] = part(Sh.seg(x, top, z, bx, y + 8.2, bz, 0.12), R.dark, 23)
    local by = gr(bx, bz) + 2.4
    parts[#parts + 1] = part(Sh.seg(bx, y + 8, bz, bx, by + 1.2, bz, 0.12), R.dark, 23)
    parts[#parts + 1] = part(Sh.box(bx, by, bz, 1.6, 1.4, 1.2, 0.4), R.stone, 24, function(ux, uy)
        if uy > 0.95 then return IDX.c end
    end)
end

-- A windlass over a narrow shaft: two posts, the barrel across them, its
-- crank, the rope and a bucket.
local function windlass(parts, x, z, gr)
    local y = gr(x, z)
    parts[#parts + 1] = part(Sh.ell(x, y, z + 0.3, 1.9, 0.3, 1.5), R.dark, 25)
    parts[#parts + 1] = part(Sh.seg(x - 1.8, y, z, x - 1.8, y + 3.4, z, 0.35), R.wood, 26)
    parts[#parts + 1] = part(Sh.seg(x + 1.8, y, z, x + 1.8, y + 3.4, z, 0.35), R.wood, 26)
    parts[#parts + 1] = part(Sh.seg(x - 2.2, y + 3, z, x + 2.2, y + 3, z, 0.45), R.wood, 27, function(ux)
        if math.abs(ux) < 0.4 then return IDX.u end
    end)
    parts[#parts + 1] = part(Sh.seg(x + 2.4, y + 3, z, x + 2.6, y + 2.1, z + 0.3, 0.15), R.dark, 28)
    parts[#parts + 1] = part(Sh.seg(x, y + 3, z, x, y + 1.4, z, 0.1), R.dark, 28)
    parts[#parts + 1] = part(Sh.prism(6, x, y + 0.6, z, 0.55, 0.8), R.wood, 29)
end

-- A miner's tent: canvas over a ridge, the flap open to the front.
local function tent(parts, x, z, gr)
    local y = gr(x, z)
    parts[#parts + 1] = part(Sh.roof(x, y, z, 3.2, 3.6, 3, math.pi / 2), R.straw, 30, function(ux, uy, uz)
        if math.abs(uz) < 0.22 and uy < 0.6 and ux > 0.9 then return IDX.o end
    end)
end

-- The sorting trough on its trestles, the stones that glint in it.
local function trough(parts, x, z, gr)
    local y = gr(x, z)
    parts[#parts + 1] = part(Sh.seg(x - 1.3, y, z, x - 1.3, y + 1.3, z, 0.25), R.wood, 31)
    parts[#parts + 1] = part(Sh.seg(x + 1.3, y, z, x + 1.3, y + 1.3, z, 0.25), R.wood, 31)
    parts[#parts + 1] = part(Sh.box(x, y + 1.2, z, 3.6, 1.6, 0.7), R.wood, 32, function(ux, uy)
        if uy > 0.95 and math.abs(ux) < 0.85 then return IDX.u end
    end)
    for k, q in ipairs({ { -0.7, 0.1 }, { 0.5, -0.1 }, { 1.1, 0.3 } }) do
        parts[#parts + 1] = part(Sh.pyramid(4, x + q[1], y + 1.8, z + q[2], 0.42, 0.9, 0, k * 0.5), GLOW, 33)
    end
end

local BUILD = {
    frame = headframe, hut = hut, timber = timber, ore = ore, tent = tent, trough = trough,
    windlass = windlass, crane = crane, blocks = blocks, rubble = rubble,
    heap = function(parts, x, z, gr) heap(parts, x, z, gr, 0.62, false) end,
    adit = function(parts, x, z, gr) heap(parts, x, z, gr, 1, true) end,
    smalladit = function(parts, x, z, gr) heap(parts, x, z, gr, 0.8, true) end,
    face = function(parts, x, z, gr) face(parts, x, z, gr, 0.7) end,
    bigface = function(parts, x, z, gr) face(parts, x, z, gr, 1) end,
}

function M.mine(site)
    if type(site) ~= "table" then site = { hills = site } end
    local key = { "mine", site.kind or "shaft", site.role or "lone", site.layout or 1, site.variant or 0,
        site.hills and "h" or "f" }
    for e = 0, 5 do key[#key + 1] = site.links and site.links[e] and e or "-" end
    return kept(table.concat(key, ":"), function()
        local parts = {}
        local gr = mineGround(site.hills)
        local p = minePlan(site)
        for _, q in ipairs(p.pieces) do BUILD[q.what](parts, q.x, q.z, gr) end
        for _, t in ipairs(p.tracks) do rails(parts, t[1], t[2], t[3], t[4], gr) end
        -- The cart on the first track out (or the spur), loaded with what
        -- the mine gives.
        local t = p.tracks[2] or p.tracks[1]
        local f = p.tracks[2] and 0.6 or 0.5
        local cx, cz = t[1] + (t[3] - t[1]) * f, t[2] + (t[4] - t[2]) * f
        if p.kind ~= "gems" or p.role ~= "workings" then
            cart(parts, cx, cz, -math.atan2(t[4] - t[2], t[3] - t[1]), gr, p.kind == "quarry" and "block" or "ore")
        end
        return parts
    end, MINE_SCALE)
end

-- The winding wheel at the top of a mine's headframe, painted apart so it can
-- turn: `step` 0..WHEEL_STEPS-1 of a quarter turn (its spokes are a cross,
-- so a quarter turn brings it round). Stamped where the mine is; nil for a
-- site with no headframe.
M.WHEEL_STEPS = 8
function M.mineWheel(site, step)
    if type(site) ~= "table" then site = { hills = site } end
    local slot = frameSlot(site)
    if not slot then return nil end
    local row = shelf(shelf(wheelPics, site.hills and true or false), slot)
    local pic = row[step]
    if not pic then
        pic = wheelPic(site.hills, slot, step)
        row[step] = pic
    end
    return pic
end

wheelPic = function(hills, slot, step)
    return kept(table.concat({ "wheel", hills and 1 or 0, slot, step }, ":"), function()
        local tx, tz = slotAt(slot)
        local ty = mineGround(hills)(tx, tz)
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

-- A mountain goat, pale and shaggy, a beard and horns swept back. `pose`
-- as a deer's: 0 head up, 1 grazing, 2 and 3 the two bounds of a run.
function M.goat(face, pose)
    return kept(table.concat({ "goat", face, pose }, ":"), function()
        local wool = R.skin
        local p = {}
        local run = pose >= 2
        local lift = run and 0.9 or 0
        p[#p + 1] = part(Sh.ell(0, 4.8 + lift, 0, 3.2, 2.0, 1.6), wool, 1)
        local hx, hy = 3.8, 7.4
        if pose == 1 then hx, hy = 4.2, 2.6 end
        p[#p + 1] = part(Sh.seg(2.0, 5.4 + lift, 0, hx - 0.4, hy - 0.4 + lift, 0, 0.9), wool, 2)
        p[#p + 1] = part(Sh.ell(hx + 0.4, hy + lift, 0, 1.3, 0.9, 0.85, A.rotZ(-0.4)), wool, 3)
        p[#p + 1] = part(Sh.seg(hx + 0.6, hy - 0.8 + lift, 0, hx + 0.4, hy - 2.0 + lift, 0, 0.35), R.stone, 4)
        local reach = pose == 2 and 1.2 or (pose == 3 and -0.9 or 0)
        for _, z in ipairs({ -0.5, 0.5 }) do
            p[#p + 1] = part(Sh.seg(hx, hy + 0.6 + lift, z, hx - 1.6, hy + 2.2 + lift, z * 1.4, 0.35, 0.2), R.dark, 5)
            p[#p + 1] = part(Sh.seg(2.0, 3.6 + lift, z * 1.4, 2.0 + reach, 0.3 + lift * 0.6, z * 1.4, 0.45), R.dark, 6)
            p[#p + 1] = part(Sh.seg(-2.0, 3.6 + lift, z * 1.4, -2.0 - reach, 0.3 + lift * 0.6, z * 1.4, 0.45), R.dark, 6)
        end
        p[#p + 1] = part(Sh.ell(-3.2, 5.8 + lift, 0, 0.6, 0.8, 0.5), wool, 7)
        return place(p, math.rad(60 * face))
    end, M.UNIT_SCALE * 0.42)
end

-- A fox, red-brown with a white tip to its brush: 0 standing, 1 and 2 the
-- steps of a trot, 3 curled up asleep with its tail round its nose.
function M.fox(face, pose)
    return kept(table.concat({ "fox", face, pose }, ":"), function()
        local coat = ramp("s", "t", "k", "n")
        local tip = function(ux) if ux > 0.6 then return IDX.w end end
        local p = {}
        if pose == 3 then
            p[#p + 1] = part(Sh.ell(0, 1.6, 0, 3.0, 1.6, 2.4), coat, 1)
            p[#p + 1] = part(Sh.ell(2.0, 2.0, 1.4, 1.3, 1.1, 1.1), coat, 2)
            p[#p + 1] = part(Sh.seg(-2.4, 1.0, -1.2, 2.4, 1.0, 2.8, 1.0, 0.6), coat, 3, tip)
            return place(p, math.rad(60 * face))
        end
        p[#p + 1] = part(Sh.ell(0, 3.6, 0, 2.8, 1.2, 1.1), coat, 1)
        p[#p + 1] = part(Sh.ell(3.0, 4.6, 0, 1.2, 1.0, 0.9), coat, 2)
        p[#p + 1] = part(Sh.seg(3.8, 4.4, 0, 5.4, 4.0, 0, 0.45, 0.2), coat, 3)
        for _, z in ipairs({ -0.5, 0.5 }) do p[#p + 1] = part(Sh.seg(2.6, 5.2, z, 2.4, 6.6, z, 0.35, 0.15), R.dark, 4) end
        local s = pose == 1 and 1.0 or (pose == 2 and -1.0 or 0)
        for _, l in ipairs({ { 1.8, 0.6, 1 }, { 1.8, -0.6, -1 }, { -1.8, 0.6, -1 }, { -1.8, -0.6, 1 } }) do
            p[#p + 1] = part(Sh.seg(l[1], 3.0, l[2], l[1] + s * l[3], 0.3, l[2], 0.32), R.dark, 5)
        end
        p[#p + 1] = part(Sh.seg(-2.4, 3.8, 0, -6.0, 3.4 + s * 0.3, 0, 1.0, 0.6), coat, 6, tip)
        return place(p, math.rad(60 * face))
    end, M.UNIT_SCALE * 0.4)
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

--- the wild's beasts ------------------------------------------------------------
--
-- The beasts that are units (src/beasts.lua), each facing `face` (0..5) in a
-- pose: 0 standing, 1 and 2 the two steps of a walk, 3 its strike, and from
-- 4 on what it does standing about (see M.BEAST_POSES). Built at the size of
-- the people and painted smaller, each by its own scale.

local GREY = ramp("c", "s", "k", "n")
local BONE = ramp("w", "w", "c", "s")
local BLACK = ramp("n", "u", "o", "o")
local FUR = ramp("t", "n", "u", "o")
local DUN = ramp("c", "t", "k", "n")
local SCALY = ramp("t", "k", "n", "u")
local DEEP = ramp("k", "n", "u", "o")

-- The four legs of a beast, front pair at fx and hind at hx, `w` apart,
-- hip at `hy`, swung by `s` (front and hind opposite, left and right
-- opposite) for the walk.
local function legs(parts, rmp, id, fx, hx, w, hy, s, r, foot)
    for _, l in ipairs({ { fx, w, 1 }, { fx, -w, -1 }, { hx, w, -1 }, { hx, -w, 1 } }) do
        parts[#parts + 1] = part(Sh.seg(l[1], hy, l[2], l[1] + s * l[3], 0.3, l[2], r), rmp, id, foot)
    end
end
local function stride(pose, n) return pose == 1 and n or (pose == 2 and -n or 0) end

local BEAST = {}

-- A peak of rock (Sh.peak) as a part: its planes in its own space like any
-- other, so it can be turned and scaled with the rest.
local function crag(poly, y, apex)
    local s = Sh.peak(poly, y, apex)
    s.reach, s.box, s.at = s.box, nil, A.id()
    return s
end

-- A grey wolf, a dark saddle and a brush of a tail. 4 howling at the sky,
-- 5 nose down to a scent, 6 lying down.
function BEAST.wolf(pose)
    local p = {}
    local lunge = pose == 3 and 1 or 0
    local lie = pose == 6
    local by = lie and 2.6 or (5.6 - lunge * 0.8)
    p[#p + 1] = part(Sh.ell(0, by, 0, 4.2, 1.9, 1.6, A.rotZ(lunge * -0.12)), GREY, 1, function(ux, uy)
        if uy > 0.55 then return IDX.n end end)
    p[#p + 1] = part(Sh.ell(2.6, by + 0.6, 0, 2.2, 2.3, 1.9), GREY, 2)
    local hx, hy, tilt = 5.2, by + 2.4, 0
    if pose == 4 then hx, hy, tilt = 4.4, by + 4.8, 0.9
    elseif pose == 3 then hx, hy = 6.4, by
    elseif pose == 5 then hx, hy, tilt = 5.8, 1.6, -0.6
    elseif lie then hx, hy = 5.6, by + 1.2 end
    p[#p + 1] = part(Sh.ell(hx, hy, 0, 1.7, 1.3, 1.2, A.rotZ(tilt)), GREY, 3)
    local mx, my = 1.6, -0.6
    if pose == 4 then mx, my = 1.0, 2.0 elseif pose == 5 then mx, my = 1.0, -1.6 end
    p[#p + 1] = part(Sh.seg(hx + 0.8, hy, 0, hx + 0.8 + mx, hy + my, 0, 0.6), GREY, 4)
    if pose == 3 then -- the jaw, dropped
        p[#p + 1] = part(Sh.seg(hx + 0.6, hy - 0.6, 0, hx + 2.2, hy - 1.6, 0, 0.4), GREY, 4)
    end
    for _, z in ipairs({ -0.7, 0.7 }) do
        p[#p + 1] = part(Sh.seg(hx - 0.6, hy + 0.8, z, hx - 0.9 - (pose == 4 and 0.8 or 0), hy + 2.4, z * 1.1, 0.4, 0.3),
            R.dark, 5)
    end
    if lie then
        for _, z in ipairs({ -1, 1 }) do
            p[#p + 1] = part(Sh.seg(3.0, 1.0, z, 6.2, 0.6, z * 0.8, 0.5), GREY, 6)
            p[#p + 1] = part(Sh.ell(-2.4, 1.6, z * 1.5, 2.0, 1.2, 0.7), GREY, 6)
        end
    else
        local s = pose == 3 and 1.6 or stride(pose, 1.5)
        legs(p, GREY, 6, 2.6, -2.8, 0.9, by - 1, s, 0.55)
    end
    local ty = pose == 3 and by + 1.6 or (lie and 1.2 or by - 1.4)
    local tz = lie and 2.4 or 0
    p[#p + 1] = part(Sh.seg(-3.8, by + 0.4, 0, -7.0, ty, tz, 1.0, 0.9), GREY, 7, function(ux)
        if ux > 0.6 then return IDX.n end end)
    return p
end

-- A brown bear, round and heavy. 3 and 4 reared up on its hind legs (3 the
-- paws coming down), 5 head down at a root.
function BEAST.bear(pose)
    local p = {}
    if pose == 3 or pose == 4 then
        local swipe = pose == 3 and 1 or 0
        p[#p + 1] = part(Sh.ell(-0.4, 8.4, 0, 3.0, 5.4, 3.0, A.rotZ(0.25 + swipe * 0.3)), FUR, 1)
        local hx, hy = 0.6 + swipe * 1.8, 14.0 - swipe * 1.2
        p[#p + 1] = part(Sh.ell(hx, hy, 0, 2.2, 2.0, 2.0), FUR, 2)
        p[#p + 1] = part(Sh.ell(hx + 2.0, hy - 0.4, 0, 1.0, 0.9, 0.9), R.wood, 3)
        for _, z in ipairs({ -1.4, 1.4 }) do
            p[#p + 1] = part(Sh.ell(hx - 0.6, hy + 1.8, z, 0.7, 0.7, 0.5), FUR, 4)
            local px, py = 3.6 + swipe * 2.4, 13.4 - swipe * 4.4
            p[#p + 1] = part(Sh.seg(0.8, 11.4, z * 1.9, px, py, z * 2.3, 1.0, 0.9), FUR, 5)
            p[#p + 1] = part(Sh.seg(-0.6, 4.0, z, 0.0, 0.4, z * 1.1, 1.2), FUR, 6)
            for c = -1, 1 do
                p[#p + 1] = part(Sh.seg(px + 0.2, py + c * 0.4, z * 2.3, px + 1.0, py + 0.6 + c * 0.5 - swipe * 1.2, z * 2.3, 0.15),
                    BONE, 7)
            end
        end
        return p
    end
    p[#p + 1] = part(Sh.ell(0, 6.6, 0, 6.0, 3.8, 3.2), FUR, 1)
    p[#p + 1] = part(Sh.ell(-1.4, 9.0, 0, 3.2, 2.0, 2.6), FUR, 2) -- the hump
    local hx, hy = 6.4, 7.2
    if pose == 5 then hx, hy = 7.0, 3.2 end
    p[#p + 1] = part(Sh.ell(hx, hy, 0, 2.3, 2.1, 2.1), FUR, 3)
    p[#p + 1] = part(Sh.ell(hx + 2.0, hy - 0.6, 0, 1.1, 0.9, 0.9), R.wood, 4)
    for _, z in ipairs({ -1.4, 1.4 }) do p[#p + 1] = part(Sh.ell(hx - 0.8, hy + 2.0, z, 0.7, 0.7, 0.5), FUR, 5) end
    local s = stride(pose, 1.3)
    for _, l in ipairs({ { 3.6, 1.6, 1 }, { 3.6, -1.6, -1 }, { -3.8, 1.6, -1 }, { -3.8, -1.6, 1 } }) do
        p[#p + 1] = part(Sh.seg(l[1], 5.0, l[2] * 1.6 / 1.6, l[1] + s * l[3], 0.5, l[2], 1.3), FUR, 6)
    end
    return p
end

-- A wild boar: a bristled hump, tusks, short legs. 3 a charge, head down;
-- 4 rooting in the ground.
function BEAST.boar(pose)
    local p = {}
    local charge = pose == 3 and 1 or 0
    p[#p + 1] = part(Sh.ell(0, 4.6, 0, 4.4, 2.8, 2.4), R.dark, 1, function(ux, uy, uz)
        if (floor(ux * 14) + floor(uz * 9)) % 5 == 0 and uy > 0 then return IDX.u end end)
    p[#p + 1] = part(Sh.seg(1.2, 7.0, 0, -2.6, 6.4, 0, 0.7), BLACK, 2)
    local hx, hy = 4.4 + charge, 5.0 - charge * 1.4
    if pose == 4 then hx, hy = 4.6, 2.4 end
    p[#p + 1] = part(Sh.ell(hx, hy, 0, 2.6, 2.0, 1.9, A.rotZ(-0.35)), R.dark, 3)
    p[#p + 1] = part(Sh.ell(hx + 2.2, hy - 1.0, 0, 0.9, 1.0, 1.0), R.wood, 4)
    for _, z in ipairs({ -0.9, 0.9 }) do
        p[#p + 1] = part(Sh.seg(hx + 1.6, hy - 1.2, z, hx + 2.2, hy + 0.4, z * 1.5, 0.3, 0.2), BONE, 5)
        p[#p + 1] = part(Sh.ell(hx - 0.8, hy + 2.0, z * 1.2, 0.5, 1.0, 0.6), R.dark, 6)
    end
    legs(p, BLACK, 7, 2.4, -2.6, 1.3, 3.0, charge == 1 and 1.4 or stride(pose, 1.1), 0.6)
    local wag = pose == 4 and 0.8 or 0
    p[#p + 1] = part(Sh.seg(-4.2, 5.4, 0, -5.2, 4.0, wag, 0.3), BLACK, 8)
    return p
end

-- An aurochs: a great black ox with a pale stripe down its back and pale
-- horns sweeping forward. 3 a charge, horns low; 4 grazing.
function BEAST.aurochs(pose)
    local p = {}
    local charge = pose == 3 and 1 or 0
    p[#p + 1] = part(Sh.ell(0, 6.4, 0, 5.4, 3.0, 2.6), BLACK, 1, function(ux, uy, uz)
        if uy > 0.7 and math.abs(uz) < 0.2 then return IDX.t end end)
    p[#p + 1] = part(Sh.ell(3.2, 7.6, 0, 2.6, 2.8, 2.4), BLACK, 2)
    local hx, hy = 6.6 + charge, 6.6 - charge * 1.8
    if pose == 4 then hx, hy = 6.8, 2.6 end
    p[#p + 1] = part(Sh.ell(hx, hy, 0, 2.0, 1.6, 1.4, A.rotZ(-0.5)), BLACK, 3)
    p[#p + 1] = part(Sh.ell(hx + 1.2, hy - 1.0, 0, 0.9, 0.8, 0.9), BLACK, 4, function() return IDX.t end)
    local fwd = charge * 1.2
    for _, z in ipairs({ -1, 1 }) do
        p[#p + 1] = part(Sh.seg(hx - 0.4, hy + 1.2, z * 1.0, hx - 0.4 + fwd, hy + 2.4 - fwd, z * 3.2, 0.45, 0.35), BONE, 5)
        p[#p + 1] = part(Sh.seg(hx - 0.4 + fwd, hy + 2.4 - fwd, z * 3.2, hx + 1.2 + fwd * 1.6, hy + 3.6 - fwd * 1.8, z * 2.8, 0.35, 0.2),
            BONE, 5)
    end
    legs(p, BLACK, 6, 3.6, -3.6, 1.4, 4.4, charge == 1 and 1.2 or stride(pose, 1.2), 0.75,
        function(ux) if ux > 0.6 then return IDX.c end end)
    local swish = (pose == 4 or pose == 0) and 0 or 0.8
    p[#p + 1] = part(Sh.seg(-5.2, 7.2, 0, -6.0, 3.0, swish, 0.3), BLACK, 7)
    return p
end

-- Wild horses: dun, a dark mane, tail and stockings. 3 and 5 rearing, 4
-- grazing.
function BEAST.horse(pose)
    local p = {}
    local up = pose == 3 or pose == 5
    local q = {}
    local stock = function(ux) if ux > 0.3 then return IDX.u end end
    q[#q + 1] = part(Sh.ell(0, 5.6, 0, 4.2, 2.1, 1.8), DUN, 1)
    local nx, ny = 4.8, 9.4
    if pose == 4 then nx, ny = 5.6, 2.2 end
    q[#q + 1] = part(Sh.seg(3.0, 6.4, 0, nx, ny, 0, 1.2), DUN, 1)
    q[#q + 1] = part(Sh.seg(2.6, 7.6, 0, nx - 0.4, ny + 1.0, 0, 0.5), BLACK, 2)
    q[#q + 1] = part(Sh.ell(nx + 1.0, ny - 0.3, 0, 1.9, 0.95, 0.95, A.rotZ(pose == 4 and -1.2 or 0)), DUN, 3,
        function(ux) if ux > 0.5 then return IDX.n end end)
    local tail = (pose == 1 or pose == 2) and 4.2 or 2.6
    q[#q + 1] = part(Sh.seg(-3.8, 6.4, 0, -5.6, tail, 0, 0.7), BLACK, 4)
    local s = stride(pose, 1.4)
    for _, lz in ipairs({ -1.0, 1.0 }) do
        if up then
            q[#q + 1] = part(Sh.seg(2.8, 4.6, lz, 4.4, 3.4 + lz * (pose == 3 and 1 or 0.5), lz, 0.55), DUN, 5, stock)
        else
            q[#q + 1] = part(Sh.seg(2.8, 4.6, lz, 2.8 + s * lz, 0.3, lz, 0.55), DUN, 5, stock)
        end
    end
    local rot = up and A.mul(A.move(-2.6, 0.4, 0), A.mul(A.rotZ(0.6), A.move(2.6, 0, 0))) or A.id()
    for _, x in ipairs(q) do
        x.at = A.mul(rot, x.at)
        p[#p + 1] = x
    end
    for _, lz in ipairs({ -1.0, 1.0 }) do
        p[#p + 1] = part(Sh.seg(-2.8, 4.6 + (up and 1 or 0), lz, up and -1.8 or (-2.8 - s * lz), 0.3, lz, 0.6), DUN, 6,
            stock)
    end
    return p
end

-- A crocodile: low and long, banded scutes, its pivot at the water's top.
-- 0 basking on the bank, 4 lying in the water with only its eyes and snout
-- out, 3 jaws wide.
function BEAST.croc(pose)
    local p = {}
    local sunk = pose == 4 and -1.6 or 0
    local scutes = function(ux, uy) if uy > 0.5 and floor(ux * 6) % 2 == 0 then return IDX.u end end
    local sway = stride(pose, 0.9)
    p[#p + 1] = part(Sh.ell(0, 0.8 + sunk, 0, 5.0, 1.3, 2.2), SCALY, 1, scutes)
    p[#p + 1] = part(Sh.seg(-4.0, 0.8 + sunk, 0, -10.0, 0.4 + sunk, 1.6 - sway * 2, 1.4, 0.4), SCALY, 2, scutes)
    local open = pose == 3 and 0.45 or 0
    p[#p + 1] = part(Sh.seg(4.2, 1.0 + sunk * 0.6, sway * 0.4, 9.6, 1.0 + open * 3 + sunk * 0.6, sway, 1.0, 0.5), SCALY, 3)
    p[#p + 1] = part(Sh.seg(4.2, 0.6 + sunk, sway * 0.4, 9.4, 0.4 - open * 1.2 + sunk, sway, 0.9, 0.45), SCALY, 4)
    if open > 0 then
        for k = 0, 4 do p[#p + 1] = part(Sh.ell(5.4 + k, 0.9 + open * (k + 1) * 0.5, 0, 0.18, 0.35, 0.6), BONE, 6) end
    end
    for _, z in ipairs({ -0.7, 0.7 }) do
        p[#p + 1] = part(Sh.ell(4.6, 2.0 + sunk * 0.5, z, 0.5, 0.5, 0.5), R.straw, 5)
    end
    if pose ~= 4 then
        for _, l in ipairs({ { 2.6, 1, 1 }, { 2.6, -1, -1 }, { -2.6, 1, -1 }, { -2.6, -1, 1 } }) do
            local s = stride(pose, 1.0) * l[3]
            p[#p + 1] = part(Sh.seg(l[1], 0.6, l[2] * 1.8, l[1] + 0.8 + s, -0.2, l[2] * 3.2, 0.5), SCALY, 7)
        end
    end
    return p
end

-- A sea serpent, its pivot at the sea's top: coils breaking the water and a
-- frilled head held high. 0, 1, 2 and 4 the coils rolling on as it swims,
-- 5 under with only a fin showing, 3 rearing with its jaws open.
function BEAST.serpent(pose)
    local p = {}
    local belly = function(ux, uy, uz, l, nx, ny)
        if ny < -0.2 then return IDX.s end
        if (floor(ux * 8) + floor(uz * 8)) % 3 == 0 then return IDX.u end
    end
    if pose == 5 then
        p[#p + 1] = part(crag({ { -2, -0.4 }, { 2, -0.4 }, { 0, 0.4 } }, -0.5, { -1.2, 3.4, 0 }), DEEP, 1)
        p[#p + 1] = part(Sh.ell(4, -0.2, 0, 2.2, 0.6, 1.2), DEEP, 2)
        return p
    end
    local phase = ({ [0] = 0, [1] = 0.5, [2] = 1.5, [4] = 1, [3] = 0 })[pose] or 0
    for k, c in ipairs({ { -9, 0 }, { -3.5, 1.5 } }) do
        local cx = c[1] + phase * 1.2
        local h = 3.4 + math.sin(phase * math.pi / 2 + k) * 0.8
        p[#p + 1] = part(Sh.seg(cx - 2.2, -1, c[2], cx, h, c[2], 1.3), DEEP, k, belly)
        p[#p + 1] = part(Sh.seg(cx, h, c[2], cx + 2.2, -1, c[2], 1.3), DEEP, k, belly)
        p[#p + 1] = part(crag({ { cx - 1.2, c[2] - 0.3 }, { cx + 1.2, c[2] - 0.3 }, { cx, c[2] + 0.3 } }, h + 0.8,
            { cx - 0.4, h + 2.6, c[2] }), R.dark, 10 + k)
    end
    local rise = pose == 3 and 13 or 10
    local bob = math.sin(phase * math.pi / 2) * 0.6
    p[#p + 1] = part(Sh.seg(2.2, -1, 2.4, 3.4, rise - 2 + bob, 2.0, 1.5, 1.1), DEEP, 5, belly)
    p[#p + 1] = part(Sh.seg(3.4, rise - 2 + bob, 2.0, 5.2, rise + bob, 1.6, 1.1), DEEP, 5, belly)
    p[#p + 1] = part(Sh.ell(6.6, rise + 0.2 + bob, 1.6, 2.2, 1.2, 1.2, A.rotZ(pose == 3 and 0.35 or -0.15)), DEEP, 6)
    if pose == 3 then
        p[#p + 1] = part(Sh.ell(7.0, rise - 1.4, 1.6, 1.8, 0.5, 1.0, A.rotZ(-0.4)), DEEP, 7)
        for k = 0, 2 do p[#p + 1] = part(Sh.seg(6.2 + k * 0.8, rise - 0.7, 1.6, 6.3 + k * 0.8, rise - 1.4, 1.6, 0.18), BONE, 9) end
    end
    for _, z in ipairs({ 0.6, 2.6 }) do
        p[#p + 1] = part(Sh.seg(5.6, rise + 1.0 + bob, z, 4.0, rise + 2.8 + bob, z + (z - 1.6) * 0.8, 0.5, 0.15), R.dark, 8)
    end
    return p
end

--- the demons ---------------------------------------------------------------------
--
-- The demons (src/demons.lua) are drawn so no one takes them for a beast:
-- ink-black, glossy, and lit by pale eyes, many of them. Hell spiders on
-- eight legs, giant eyes floating over the ground trailing tendrils,
-- tentacles out of the sea, a brood mother twice a spider's size with her
-- eggs on her back, and the Eye of the Abyss.

local INK = ramp("u", "o", "o", "o")
local GLOSS = ramp("k", "u", "o", "o")
local SCLERA = ramp("w", "c", "s", "t")

-- A spider facing +x: `big` the brood mother. Pose 0 standing, 1 and 2
-- the walk, 3 reared up with its front legs high and fangs out, 4 crouched
-- low, legs drawn in.
local function spider(pose, big)
    local p = {}
    local rear = pose == 3 and 1 or 0
    local low = pose == 4 and -1.2 or 0
    local by = 3.8 + low + rear * 0.8
    local tilt = A.rotZ(rear * 0.35)
    -- The abdomen, a pale hourglass on its back; the brood mother's carries
    -- her eggs.
    p[#p + 1] = part(Sh.ell(-3.4, by + 0.8, 0, 3.8, 3.0, 3.2, tilt), GLOSS, 1, function(ux, uy, uz)
        if uy > 0.55 and abs(uz) < 0.18 + abs(ux + 0.1) * 0.5 and abs(ux + 0.1) < 0.35 then return IDX.c end
    end)
    p[#p + 1] = part(Sh.ell(1.2, by + rear * 1.2, 0, 2.3, 1.7, 2.0), INK, 2)
    -- Eyes: eight, in two rows, pale.
    for k, e in ipairs({ { 3.2, 0.5, 0.55 }, { 3.2, 0.5, -0.55 }, { 3.0, 0.9, 1.15 }, { 3.0, 0.9, -1.15 },
        { 2.8, 1.25, 0.35 }, { 2.8, 1.25, -0.35 }, { 2.5, 1.35, 0.95 }, { 2.5, 1.35, -0.95 } }) do
        local r = k <= 2 and 0.45 or 0.3
        p[#p + 1] = part(Sh.ell(e[1], by + rear * 1.2 + e[2], e[3], r, r, r), GLOW, 3)
    end
    -- Fangs, out when it strikes.
    local fang = rear == 1 and 1.2 or 0.5
    for _, z in ipairs({ -0.5, 0.5 }) do
        p[#p + 1] = part(Sh.seg(3.3, by + rear * 1.2 - 0.5, z, 3.6 + fang * 0.4, by + rear * 1.2 - 0.9 - fang, z * 0.7, 0.32, 0.1),
            BONE, 4)
    end
    -- Eight legs, each bent high at the knee; in the walk the two sets of
    -- four step in turn.
    local reach = pose == 4 and 4.6 or 6.4
    for k, dx in ipairs({ 2.4, 0.9, -0.7, -2.4 }) do
        for _, side in ipairs({ -1, 1 }) do
            local set = ((k + (side > 0 and 1 or 0)) % 2 == 0) and 1 or -1
            local step = stride(pose, 0.9) * set
            local hx, hy, hz = 1.2 + dx * 0.35, by, side * 1.4
            local fx, fy, fz = 1.2 + dx * 1.9 + step, 0.2, side * reach
            local kx, ky, kz = 1.2 + dx * 1.2 + step * 0.5, by + 3.2 + (pose == 4 and -1.4 or 0), side * (reach * 0.62)
            if pose ~= 0 and pose ~= 4 and set > 0 and pose ~= 3 then ky, fy = ky + 0.8, 0.9 end
            if rear == 1 and k <= 2 then
                kx, ky, kz = 3.8 + (2 - k), by + 5.0, side * 2.6
                fx, fy, fz = 5.6 + (2 - k) * 0.8, by + 6.8 - k, side * 3.4
            end
            p[#p + 1] = part(Sh.seg(hx, hy, hz, kx, ky, kz, 0.42, 0.34), INK, 5 + k)
            p[#p + 1] = part(Sh.seg(kx, ky, kz, fx, fy, fz, 0.34, 0.14), INK, 5 + k, function(ux, uy)
                if uy < -0.6 then return IDX.n end
            end)
        end
    end
    if big then
        -- Her eggs, pale, clustered on her back, and spines along it.
        for k, e in ipairs({ { -3.8, 3.0, 0.9 }, { -2.6, 3.4, -0.7 }, { -4.6, 2.6, -1.0 }, { -3.0, 2.8, 1.8 },
            { -4.2, 3.2, 0.0 }, { -2.2, 3.0, 1.0 } }) do
            p[#p + 1] = part(Sh.ell(e[1], by + 0.8 + e[2], e[3], 0.8, 0.7, 0.8), SCLERA, 20 + k)
        end
        for k = 0, 3 do
            p[#p + 1] = part(Sh.seg(-0.6 - k * 1.6, by + 2.4 + (k == 0 and 0 or 0.8), 0, -1.0 - k * 1.6, by + 4.8 + (k == 0 and 0 or 0.8), 0,
                0.4, 0.05), INK, 30)
        end
    end
    return p
end

function BEAST.spider(pose) return spider(pose, false) end
function BEAST.brood(pose) return spider(pose, true) end

-- An eye looking out along +x and a little up, at whoever looks down on
-- it: white, veined, a dark iris ringed pale and a pupil; a brow of black
-- hide over the back of it, drawn down over the whole of it to blink.
local function eyeball(p, x, y, z, r, id, wide, shut)
    local look = A.rotZ(0.75)
    p[#p + 1] = part(Sh.ell(x, y, z, r, r, r, look), SCLERA, id, function(ux, uy, uz)
        if ux > 0.86 then return IDX.o end
        if ux > (wide and 0.8 or 0.74) then return wide and IDX.o or IDX.u end
        if ux > 0.6 then return IDX.n end
        if ux > 0.55 then return IDX.w end
        -- Veins, creeping out from the back.
        local a = math.atan2(uz, uy)
        if ux < 0.35 and abs(sin(a * 5 + ux * 9)) < 0.1 then return IDX.t end
    end)
    if shut then
        p[#p + 1] = part(Sh.ell(x, y, z, r * 1.06, r * 1.06, r * 1.06), INK, id + 1)
        return
    end
    p[#p + 1] = part(Sh.ell(x - r * 0.55, y + r * 0.45, z, r * 0.75, r * 0.7, r * 1.08), INK, id + 1)
end

-- A giant eye, floating over the ground, its tendrils hanging and curling
-- under it. 0, 1 and 2 bobbing as it drifts; 3 its gaze, wide, the
-- tendrils thrown out; 4 blinking.
function BEAST.eye(pose)
    local p = {}
    local bob = ({ [0] = 0, 0.5, -0.5, 0.2, 0 })[pose] or 0
    local y = 8.2 + bob
    eyeball(p, 0, y, 0, 3.2, 1, pose == 3, pose == 4)
    for k = 0, 5 do
        local a = k / 6 * 2 * math.pi
        local cz, cx = sin(a) * 1.8, cos(a) * 1.4 - 0.6
        local out = pose == 3 and 2.2 or 0.6
        local sway = sin(k * 1.7 + (pose == 1 and 0.8 or pose == 2 and -0.8 or 0)) * 0.9
        local mx, mz = cx * (1.4 + out * 0.4) + sway, cz * (1.4 + out * 0.5)
        p[#p + 1] = part(Sh.seg(cx, y - 2.4, cz, mx, y - 5.0, mz, 0.5, 0.32), INK, 10 + k)
        p[#p + 1] = part(Sh.seg(mx, y - 5.0, mz, mx * 1.3 - sway, y - 7.4 + out, mz * 1.4, 0.32, 0.1), INK, 10 + k)
    end
    return p
end

-- A tentacle up out of the sea, its pivot at the water's top: a thick
-- arm tapering to a curled tip, pale suckers along its inside, and two
-- lesser ones beside it. 0, 1 and 2 swaying, 3 lashing down along +x, 4
-- sunk low, coiling.
local function arm(p, x0, z0, height, lean, curl, side, id, thick)
    -- Walked up from the water a segment at a time, each turned a little
    -- more: upright at the root, rolled over at the tip.
    local n = 10
    local x, y, z = x0, -1.5, z0
    local seg = height / n
    for k = 1, n do
        local f = k / n
        local th = lean + curl * f * f * f * 3
        local nx, ny = x + sin(th) * seg, y + cos(th) * seg
        local nz = z0 + side * sin(f * math.pi) * 0.8
        local r0, r1 = thick * (1 - (k - 1) / n * 0.85), thick * (1 - k / n * 0.85)
        p[#p + 1] = part(Sh.seg(x, y, z, nx, ny, nz, r0, r1), GLOSS, id, function(ux, uy, uz, l, nxx)
            if nxx < -0.5 then return IDX.n end
        end)
        if k % 3 == 1 and k < n - 1 then
            p[#p + 1] = part(Sh.ell(x - cos(th) * r0 * 0.6, y + sin(th) * r0 * 0.6, z, r0 * 0.4, r0 * 0.4, r0 * 0.5), SCLERA, id + 1)
        end
        x, y, z = nx, ny, nz
    end
end

function BEAST.tentacle(pose)
    local p = {}
    local lean = ({ [0] = -0.15, -0.35, 0.1, 0.9, 0.2 })[pose] or 0
    local curl = ({ [0] = 0.9, 1.1, 0.7, 0.6, 2.0 })[pose] or 0.9
    local h = pose == 4 and 9 or 16
    arm(p, 0, 0, h, lean, curl, 1, 1, 2.2)
    arm(p, -3.6, 3.2, h * 0.5, lean - 0.3, curl + 0.6, -1, 10, 1.2)
    return p
end

-- The Eye of the Abyss: a great eye on a writhing crown of tentacles and
-- black spines, floating high. 0, 1 and 2 drifting, 3 its gaze, 4 the
-- arms coiling.
function BEAST.abyss(pose)
    local p = {}
    local bob = ({ [0] = 0, 0.6, -0.6, 0.3, 0 })[pose] or 0
    local y = 13 + bob
    eyeball(p, 0, y, 0, 5.2, 1, pose == 3, false)
    for k = 0, 7 do
        local a = k / 8 * 2 * math.pi + 0.2
        local ca, sa = cos(a), sin(a)
        local out = pose == 3 and 1.6 or (pose == 4 and 0.6 or 1)
        local w = sin(k * 2.1 + bob * 3) * 1.2
        local x1, z1 = ca * 4.8, sa * 4.8
        local x2, z2 = ca * 8.0 * out + w, sa * 8.0 * out
        local x3, z3 = ca * 9.6 * out, sa * 9.6 * out + w
        p[#p + 1] = part(Sh.seg(x1 * 0.6 - 1, y - 3, z1 * 0.6, x2, y - 6.5, z2, 1.0, 0.6), GLOSS, 10 + k)
        p[#p + 1] = part(Sh.seg(x2, y - 6.5, z2, x3, y - 11 + (pose == 4 and 4 or 0), z3, 0.6, 0.15), GLOSS, 10 + k)
        p[#p + 1] = part(Sh.seg(-ca * 0.5 - 1.5, y + 2.5, sa * 4, -ca * 1.2 - 2.4 - k % 2, y + 7 + (k % 3), sa * 5.6, 0.45, 0.05),
            INK, 30)
    end
    return p
end

-- The plague's rats (src/plague.lua): a swarm of five, dark and sleek,
-- long naked tails curling behind, pale eyes; 1 and 2 scurrying (each
-- rat's own way), 4 one up on its haunches sniffing the air.
local RAT = ramp("k", "n", "u", "o")
local TAIL = ramp("s", "t", "k", "n")
function BEAST.rats(pose)
    local p = {}
    local spots = { { 3.4, 0, 0 }, { -0.4, 3.0, 0.6 }, { -1.2, -3.2, -0.5 }, { -5, 0.8, 0.3 }, { 1.4, -0.6, 2.6 } }
    for k, s in ipairs(spots) do
        local x, z, a = s[1], s[2], s[3]
        -- Scurrying: each a little forward or back, by the pose.
        if pose == 1 then x = x + (k % 2 == 0 and 1.2 or -0.8) elseif pose == 2 then x = x + (k % 2 == 0 and -0.8 or 1.2) end
        local up = pose == 4 and k == 1
        local side = (k % 2 == 0) and 1 or -1
        local q = {}
        if up then
            q[#q + 1] = part(Sh.ell(0, 2.0, 0, 1.1, 2.0, 1.0, A.rotZ(-0.35)), RAT, 1)
            q[#q + 1] = part(Sh.ell(0.8, 4.1, 0, 1.0, 0.8, 0.75), RAT, 2)
            q[#q + 1] = part(Sh.seg(-0.8, 0.4, 0, -3.6, 0.3, 1.2, 0.26, 0.14), TAIL, 3)
        else
            q[#q + 1] = part(Sh.ell(0, 1.15, 0, 2.2, 1.15, 1.15), RAT, 1, function(ux, uy) if uy > 0.6 then return IDX.u end end)
            q[#q + 1] = part(Sh.ell(2.2, 1.0, 0, 1.05, 0.75, 0.75), RAT, 2)
            q[#q + 1] = part(Sh.seg(3.1, 0.85, 0, 3.6, 0.7, 0, 0.3, 0.15), TAIL, 6)
            q[#q + 1] = part(Sh.seg(-2.0, 0.7, 0, -4.4, 0.4, side * 1.5, 0.26, 0.16), TAIL, 3)
            q[#q + 1] = part(Sh.seg(-4.4, 0.4, side * 1.5, -5.8, 0.4, side * 0.3, 0.16, 0.1), TAIL, 3)
        end
        local hx, hy = up and 1.2 or 2.6, up and 4.4 or 1.35
        for _, e in ipairs({ -1, 1 }) do
            q[#q + 1] = part(Sh.ell(hx - 0.5, hy + 0.55, e * 0.45, 0.35, 0.4, 0.28), TAIL, 4)
        end
        q[#q + 1] = part(Sh.ell(hx + 0.25, hy + 0.15, 0.42, 0.18, 0.18, 0.18), GLOW, 5)
        place(q, a, x, 0, z)
        for _, part_ in ipairs(q) do p[#p + 1] = part_ end
    end
    return p
end

local BEAST_SCALE = { wolf = 0.74, bear = 0.74, boar = 0.68, aurochs = 0.7, horse = 0.82, croc = 0.66, serpent = 0.8,
    spider = 0.7, brood = 0.95, eye = 0.8, tentacle = 1.0, abyss = 0.95, rats = 0.8 }
-- What each beast's poses past 3 are, for the board to choose among.
M.BEAST_POSES = {
    wolf = { howl = 4, sniff = 5, lie = 6 }, bear = { rear = 4, root = 5 }, boar = { root = 4 },
    aurochs = { graze = 4 }, horse = { graze = 4, rear = 5 }, croc = { sunk = 4 }, serpent = { roll = 4, sunk = 5 },
    spider = { crouch = 4 }, brood = { crouch = 4 }, eye = { blink = 4 }, tentacle = { coil = 4 }, abyss = { coil = 4 },
    rats = { sniff = 4 },
}

--- the plague's ------------------------------------------------------------------

-- A flag of a town shut against the plague, on a tall pole: pale cloth with
-- a broad dark band down it, so it reads as the sickness's and no one's
-- banner. `pose` 0..3 its wave in the wind (it streams east, +x).
M.FLAG_POSES = 4
function M.plagueFlag(pose)
    pose = pose or 0
    return kept("pflag:" .. pose, function()
        local p = {}
        p[#p + 1] = part(Sh.seg(0, 0, 0, 0, 9, 0, 0.25), R.wood, 1)
        p[#p + 1] = part(Sh.ell(0, 9.2, 0, 0.35, 0.35, 0.35), R.wood, 1)
        -- The cloth, in three strips each a little further on the wave.
        for k = 0, 2 do
            local x0 = 0.3 + k * 1.3
            local lift = sin(pose * math.pi / 2 + k * 1.1) * 0.5
            p[#p + 1] = part(Sh.box(x0 + 0.65, 6.2 + lift, sin(pose * math.pi / 2 + k) * 0.35, 1.35, 0.2, 2.7), R.wall,
                2 + k, function(ux, uy, uz)
                    if k == 1 then return IDX.u end
                    if uy > 0.9 or uy < 0.1 then return IDX.n end
                end)
        end
        return p
    end, M.UNIT_SCALE)
end

-- A pyre of the plague's dead: logs laid crosswise in a stack, shrouded
-- shapes on it, pale; the board lights it (src/ui/pestilence.lua).
function M.pyre()
    return kept("pyre", function()
        local p = {}
        for layer = 0, 2 do
            for k = -1, 1 do
                local y = 0.45 + layer * 0.8
                if layer % 2 == 0 then
                    p[#p + 1] = part(Sh.seg(-2.4, y, k * 1.1, 2.4, y, k * 1.1, 0.42), R.wood, 1 + layer)
                else
                    p[#p + 1] = part(Sh.seg(k * 1.1, y, -2.2, k * 1.1, y, 2.2, 0.42), R.wood, 1 + layer)
                end
            end
        end
        for k = -1, 1, 2 do
            p[#p + 1] = part(Sh.ell(k * 0.7, 2.75, k * 0.3, 1.9, 0.55, 0.6, A.rotY(0.2 * k)), BONE, 5, function(ux)
                if abs(ux) > 0.8 then return IDX.s end
            end)
        end
        return p
    end, M.UNIT_SCALE)
end

-- A farm left fallow in the plague: its farmhouse abandoned, the thatch
-- fallen in and the rafters showing, the walls broken down at one side,
-- the haystack rotted black. Where the farm stood (`layout`).
function M.farmRuin(layout)
    layout = layout or M.FARM_LAYOUTS[1]
    return kept("ruin:" .. layout.home[1] .. ":" .. layout.home[2], function()
        local parts = {}
        local hx, hz = layout.home[1], layout.home[2]
        parts[#parts + 1] = part(Sh.prism(8, hx, 0, hz, 2.4, 2.4, 0, math.pi / 8), R.wall, 1, function(ux, uy, uz)
            if uz > 0.75 and abs(ux) < 0.3 and uy < 0.85 then return IDX.o end
            -- Broken down at the back, ragged.
            if ux < -0.2 and uy > 0.55 + hash(floor(uz * 6), 3) * 0.4 then return IDX.u end
            if uy > 0.92 then return IDX.n end
        end)
        parts[#parts + 1] = part(Sh.prism(8, hx, 0.1, hz, 2.0, 2.2, 0, math.pi / 8), ramp("n", "u", "o", "o"), 2)
        -- The rafters, bare, two of them fallen in.
        for k = 0, 3 do
            local a = k * math.pi / 2 + 0.4
            local fallen = k >= 2
            local x0, z0 = hx + cos(a) * 2.2, hz + sin(a) * 2.2
            local tx, ty, tz = hx, fallen and 1.6 or 5.4, hz
            if fallen then tx, tz = hx - cos(a) * 1.2, hz - sin(a) * 1.2 end
            parts[#parts + 1] = part(Sh.seg(x0, 2.4, z0, tx, ty, tz, 0.22), R.wood, 3)
        end
        parts[#parts + 1] = part(Sh.ell(hx + layout.hay * 5.4, 0.1, hz + 0.6, 1.9, 1.3, 1.7), R2.soil, 4,
            function(ux, uy) if hash(floor(ux * 4), floor(uy * 4)) > 0.6 then return IDX.u end end)
        return parts
    end, FARM_SCALE)
end

function M.beast(kind, face, pose)
    face, pose = face or 1, pose or 0
    local row = shelf(shelf(beastPics, kind), face)
    local pic = row[pose]
    if not pic then
        pic = beastPic(kind, face, pose)
        row[pose] = pic
    end
    return pic
end

beastPic = function(kind, face, pose)
    return kept(table.concat({ "beast", kind, face, pose }, ":"), function()
        return place(BEAST[kind](pose), math.rad(60 * face))
    end, M.UNIT_SCALE * BEAST_SCALE[kind])
end

-- Lairs: a wolf den (boulders round a dark hole, bones before it), a bear's
-- cave (a crag with a black mouth) and a wild bees' nest (a hollow stump and
-- a hive of straw-coloured comb on it).
local LAIR = {}
function LAIR.den()
    local p = {}
    p[#p + 1] = part(Sh.ell(0, 0.6, -0.6, 3.2, 3.0, 1.2), BLACK, 1)
    for k, b in ipairs({ { -4.6, 0, 3.4, 3.0 }, { 4.4, -0.4, 3.0, 2.6 }, { 0, -3.6, 4.2, 3.4 }, { -6.4, 3.4, 1.8, 1.4 },
        { 6.2, 3.0, 2.0, 1.6 }, { -2.6, -5.8, 2.4, 2.0 } }) do
        p[#p + 1] = part(Sh.ell(b[1], b[4] * 0.55, b[2], b[3], b[4], b[3] * 0.9), R.stone, 2 + k, function(ux, uy, uz)
            if (floor(ux * 5 + uz * 3) % 4 == 0) and uy > 0.3 then return IDX.t end end)
    end
    p[#p + 1] = part(Sh.seg(2.4, 0.3, 4.2, 4.8, 0.3, 5.4, 0.28), BONE, 20)
    p[#p + 1] = part(Sh.seg(-1.6, 0.3, 5.6, 0.8, 0.3, 4.6, 0.28), BONE, 21)
    p[#p + 1] = part(Sh.ell(-3.4, 0.6, 5.0, 0.8, 0.6, 0.7), BONE, 22)
    return p
end
function LAIR.cave()
    local p = {}
    p[#p + 1] = part(crag({ { -9, -6 }, { 7, -7 }, { 10, 1 }, { 2, 4 }, { -8, 3 } }, 0, { -1, 13, -3 }), R.stone, 1,
        function(ux, uy, uz, l, nx, ny) if ny > 0.75 then return IDX.c end end)
    p[#p + 1] = part(Sh.ell(1.6, 1.0, 2.6, 2.8, 3.6, 1.2), BLACK, 2) -- the mouth
    for k, b in ipairs({ { 6.4, 4.0, 1.8 }, { -5.6, 4.4, 1.4 }, { 8.6, 0, 1.6 } }) do
        p[#p + 1] = part(Sh.ell(b[1], b[3] * 0.5, b[2], b[3], b[3] * 0.8, b[3]), R.stone, 3 + k)
    end
    p[#p + 1] = part(Sh.seg(-1.0, 0.3, 6.0, 1.6, 0.3, 5.6, 0.3), BONE, 10)
    return p
end
function LAIR.hive()
    local p = {}
    p[#p + 1] = part(Sh.prism(7, 0, 0, 0, 3.4, 4.0, 0, 0), R.wood, 1, function(ux, uy, uz, l, nx, ny)
        if ny > 0.6 then
            if floor(math.sqrt(ux * ux + uz * uz) * 6) % 2 == 0 then return IDX.t end
            return IDX.s
        end
        if floor((math.atan2(uz, ux) + 4) * 4) % 3 == 0 then return IDX.n end
    end)
    p[#p + 1] = part(Sh.ell(0, 4.2, 0, 2.6, 4.2, 2.6), R.straw, 2, function(ux, uy)
        if floor((uy + 1) * 6) % 2 == 0 then return IDX.t end end)
    p[#p + 1] = part(Sh.ell(1.6, 4.8, 1.8, 0.7, 0.9, 0.5), BLACK, 3)
    return p
end
-- A rift: the ground torn open in a jagged black fissure, its lips of rock
-- thrown up and leaning out, a pale light down in it.
function LAIR.rift()
    local p = {}
    p[#p + 1] = part(Sh.ell(0, 0.2, 0, 7.5, 0.7, 2.6, A.rotY(0.35)), INK, 1, function(ux, uy, uz)
        if abs(uz + sin(ux * 9) * 0.15) < 0.12 then return IDX.w end
        if abs(uz + sin(ux * 9) * 0.15) < 0.3 then return IDX.c end
    end)
    for k = 0, 9 do
        local f = k / 9 - 0.5
        local side = k % 2 == 0 and 1 or -1
        local x, z = f * 13, side * (2.6 + abs(sin(k * 2.3)) * 0.8) - f * 4.6
        local h = 2.2 + abs(sin(k * 1.7)) * 2.4
        p[#p + 1] = part(crag({ { x - 1.4, z - 0.9 }, { x + 1.4, z - 0.9 }, { x + 1.0, z + 1.0 }, { x - 1.2, z + 0.9 } }, 0,
            { x, h, z + side * 1.4 }), R.stone, 2 + k, function(ux, uy, uz, l, nx, ny)
            if ny > 0.7 then return IDX.n end
        end)
    end
    for k = 0, 5 do
        local a = k * 1.1
        p[#p + 1] = part(Sh.ell(cos(a) * 8, 0.3, sin(a) * 5, 0.8, 0.5, 0.7), R.stone, 20)
    end
    return p
end

-- The citadel of the abyss, the demons' capital: a black spire of rock
-- grown out of the ground, ribbed, with lesser spikes round it like the
-- towers of a wall, a gate black as the pit at its foot, and an eye
-- glowing in a window high up.
function LAIR.citadel()
    local p = {}
    local ribs = function(ux, uy, uz, l, nx, ny)
        if floor(math.atan2(uz, ux) * 3) % 2 == 0 then return IDX.u end
        if floor(uy * 7) % 3 == 0 then return IDX.n end
    end
    p[#p + 1] = part(crag({ { -4, -4 }, { 4, -4.4 }, { 5, 1 }, { 1.4, 4.6 }, { -4.4, 3 } }, 0, { 0, 30, 0 }), GLOSS, 1, ribs)
    p[#p + 1] = part(crag({ { -6, -2 }, { -1, -6 }, { 4, -5 }, { 7, 0 }, { 3, 5 }, { -4, 5 } }, 0, { 0.4, 10, 0 }), INK, 2)
    for k = 0, 5 do
        local a = k / 6 * 2 * math.pi + 0.4
        local x, z = cos(a) * 8.4, sin(a) * 6.4
        local h = 9 + (k % 3) * 3
        p[#p + 1] = part(crag({ { x - 1.4, z - 1.2 }, { x + 1.4, z - 1.2 }, { x + 1.2, z + 1.2 }, { x - 1.4, z + 1.0 } }, 0,
            { x + cos(a) * 1.2, h, z + sin(a) * 1.2 }), GLOSS, 3 + k, ribs)
    end
    -- Walls of black between the spikes, low.
    for k = 0, 5 do
        local a0, a1 = k / 6 * 2 * math.pi + 0.4, (k + 1) / 6 * 2 * math.pi + 0.4
        if k ~= 1 then
            p[#p + 1] = part(Sh.seg(cos(a0) * 8.4, 1.8, sin(a0) * 6.4, cos(a1) * 8.4, 1.8, sin(a1) * 6.4, 1.6), INK, 10)
        end
    end
    -- The gate, at the front, and the eye in its window.
    p[#p + 1] = part(Sh.ell(1.2, 2.0, 4.6, 1.8, 3.2, 0.9), R.dark, 20, function() return IDX.o end)
    eyeball(p, 1.2, 19, 2.1, 1.3, 21, true, false)
    for _, z in ipairs({ -1, 1 }) do
        p[#p + 1] = part(Sh.ell(1.4 + z * 0.4, 3.0, 4.9, 0.25, 0.25, 0.25), GLOW, 25)
    end
    return p
end

local LAIR_SCALE = { citadel = 0.78, rift = 0.62 }
function M.lair(kind)
    return kept("lair:" .. kind, LAIR[kind], M.UNIT_SCALE * (LAIR_SCALE[kind] or 0.62))
end

-- A bee, or a few: a speck of ink, for the board to swarm about a hive.
function M.bee()
    return kept("bee", function() return { part(Sh.ell(0, 0, 0, 0.5, 0.4, 0.4), BLACK, 1) } end, 1)
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
