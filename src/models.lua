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

-- Six facings, one a hex direction; facing k points along 60k degrees.
M.FACINGS = 6

-- The picture of a unit of `kind`, of a civilization that looks `look`,
-- facing direction `face` (0..5), in pose 0..3.
function M.unit(kind, look, face, pose)
    face, pose = face or 1, pose or 0
    return kept(table.concat({ "u", kind, look, face, pose }, ":"), function()
        local parts = UNIT[kind](LOOK[look], pose)
        return place(parts, math.rad(60 * face))
    end, M.UNIT_SCALE)
end

--- cities -----------------------------------------------------------------------

-- Spots round a city's middle for houses, front ones last so they are the
-- ones you see first when it grows.
local SPOTS = {
    { -6, -4 }, { 6, -4 }, { -7, 2 }, { 7, 2 }, { 0, -7 }, { -4, 6 }, { 4, 6 }, { -9, -2 }, { 9, -2 },
}

local function house(parts, x, z, look, id, size, turn)
    size = size or 1
    local w, d, ht = 4 * size, 3.4 * size, 2.6 * size
    local h = turn and math.pi / 2 or 0
    parts[#parts + 1] = part(Sh.box(x, 0, z, w, d, ht, h), R.wall, id, function(ux, uy, uz, lev)
        -- A dark door or window in the middle of a wall.
        if math.abs(ux) < 0.25 and uy < 0.7 and uy > 0.15 and math.abs(uz) > 0.98 then return IDX.n end
    end)
    parts[#parts + 1] = part(Sh.roof(x, ht, z, w + 1, d + 1.2, 2.6 * size, h), look.roof, id + 1, banded(look))
end

-- The picture of a city: its houses (one more for each citizen, up to the
-- spots there are), its palace or hall, and whatever it has built.
function M.city(look, pop, capital, built)
    local b = built or {}
    local houses = math.min(#SPOTS, 1 + pop)
    local key = table.concat({ "c", look, houses, capital and 1 or 0, b.walls and 1 or 0, b.granary and 1 or 0,
        b.library and 1 or 0, b.market and 1 or 0, b.monument and 1 or 0 }, ":")
    return kept(key, function()
        local L = LOOK[look]
        local parts = {}
        for k = 1, houses do
            local s = SPOTS[k]
            house(parts, s[1], s[2], L, 10 + k * 2, 0.9 + (k % 3) * 0.08, k % 2 == 0)
        end
        if capital then
            -- The palace: a hall, its roof, and a tower with a pointed top.
            parts[#parts + 1] = part(Sh.box(0, 0, 0, 8, 6, 4.5), R.stone, 1, function(ux, uy, uz)
                if uy > 0.2 and uy < 0.75 and math.abs(uz) > 0.98 and floor((ux + 1) * 3) % 2 == 1 then return IDX.k end
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
                if math.abs(uz) > 0.98 and floor((ux + 1) * 4) % 2 == 0 and uy < 0.85 then return IDX.k end
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
                parts[#parts + 1] = part(Sh.box(mx, 0, mz, len, 1.6, 3.2, -math.atan2(z1 - z0, x1 - x0)), R.stone, 40,
                    function(ux, uy) if uy > 0.8 and floor((ux + 1) * 6) % 2 == 0 then return IDX.k end end)
                parts[#parts + 1] = part(Sh.prism(6, x0, 0, z0, 1.9, 4.8), R.stone, 41 + k)
                parts[#parts + 1] = part(Sh.pyramid(6, x0, 4.8, z0, 2.3, 2.2), L.roof, 41 + k)
            end
        end
        return parts
    end, M.CITY_SCALE)
end

--- improvements -----------------------------------------------------------------

-- A farm's barn; the furrows are laid on the ground a pixel at a time.
function M.farm()
    return kept("farm", function()
        local parts = {}
        parts[#parts + 1] = part(Sh.box(-5, 0, -4, 5, 4, 3.4), R.wood, 1, function(ux, uy, uz)
            if math.abs(ux) < 0.3 and uy < 0.75 and uz > 0.98 then return IDX.u end
        end)
        parts[#parts + 1] = part(Sh.roof(-5, 3.4, -4, 5.8, 4.8, 2.6), R.straw, 2)
        -- A haystack.
        parts[#parts + 1] = part(Sh.ell(4.5, 0.5, -4, 2.4, 3, 2.4), R.straw, 3)
        return parts
    end, 1.3)
end

-- A mine: a heap of spoil with a dark adit framed in timber, a headframe
-- over the shaft with its winding wheel, the miners' hut, and a cart of ore
-- on rails out of the adit. `hills`: each piece stands on the hill's mound
-- (src/world.lua) rather than sunk in it.
local MINE_SCALE = 1.4
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
        parts[#parts + 1] = part(Sh.ell(tx, top + 0.6, tz + 0.7, 2.3, 2.3, 0.35), R.straw, 10, function(ux, uy, uz)
            local d = ux * ux + uy * uy
            if d < 0.07 then return IDX.u end
            if d > 0.55 then return nil end
            if math.abs(ux) < 0.16 or math.abs(uy) < 0.16 then return IDX.t end
            return IDX.n
        end)
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

return M
