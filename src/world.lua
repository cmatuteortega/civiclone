-- The map as a picture: every hex and what stands on it, traced once.
--
-- As in underroot, the camera has no perspective, so a picture of the map is
-- the same picture whatever happens on it. It is traced once at load, a
-- pixel at a time, into one image -- and into a depth buffer the same size,
-- which is what lets a warrior go behind a mountain or a city stand among
-- trees without anything being traced again. Each pixel also keeps which hex
-- it belongs to, which is how a click lands on a hex, how fog is laid over
-- the hexes no one has seen, and how a highlight finds a hex's top.
--
-- Each hex is a prism standing as high as its ground: water low and flat,
-- the land in two terraces, hills a step up with mounds on top, mountains a
-- step more with peaks of rock. Forests are trees, resources are sheaves and
-- boulders and crystals. When a hex changes (a city clears its forest) only
-- the hex is built again and only its corner of the picture traced again.

local ffi = require "ffi"
local T = require "src.tracer"
local Sh = require "src.shapes"
local H = require "src.hex"
local D = require "src.defs"

local max, min, abs, floor, ceil, sin = math.max, math.min, math.abs, math.floor, math.ceil, math.sin
local IDX = T.IDX
local ramp = T.ramp

local World = {}
World.__index = World

local BOTTOM = -8   -- how deep the map's block goes, seen along its south edge
local BACK = 2000
local BIN = 16
local FLAT = 3      -- the level fog is laid at

-- A cheap hash for grain: the same speck lands in the same place every time.
local function grain(x, z, k)
    local n = sin(floor(x) * 12.9898 + floor(z) * 78.233 + (k or 0) * 37.719) * 43758.5453
    return n - floor(n)
end

-- How far room point (x, z) is from hex `cell`'s edge: below nothing inside it,
-- the true distance outside, corners rounded (Inigo Quilez's hexagon).
local function hexDistance(cell, x, z)
    local px, py = abs(z - cell.z), abs(x - cell.x)
    local d = 2 * min(-0.866025404 * px + 0.5 * py, 0)
    px, py = px + 0.866025404 * d, py - 0.5 * d
    local k = 0.577350269 * H.APOTHEM
    px, py = px - max(-k, min(k, px)), py - H.APOTHEM
    local l = math.sqrt(px * px + py * py)
    return py < 0 and -l or l
end

--- what things are made of ---------------------------------------------------------

-- `print` answers a key index for a pixel that is printed rather than lit (a
-- furrow, a ripple, a speck of grit), a ramp to light it with instead, or
-- nothing to take the material's own.
local SIDE = ramp("s", "t", "n", "u")
local SIDE_DARK = ramp("t", "n", "u", "o")

-- The cut side of a hex: earth in bands.
local function strata(x, y, z, lev)
    local band = floor((-y + 0.6 * sin((x + z) * 0.2)) / 2.5)
    if band % 3 == 2 then return SIDE_DARK end
    return SIDE
end

local MAT = {}

-- The kinds of land the moving picture knows (after 1 ocean and 2 coast).
local LAND = { crown = 3, sheaf = 4, grass = 5, plains = 6, other = 7, desert = 8, river = 9, flood = 10, pool = 11,
    snow = 12, ice = 13, slush = 14 }
World.LAND = LAND

-- The pale rim of sand and dried mud along a river's bank, broken here and
-- there, so the dark water reads against the land beside it.
local function rim(s, x, z)
    local pull = s.pull
    if not pull then return end
    local cell = s.cellRef
    for k = 0, 5 do
        if pull[k] then
            local a = math.rad(60 * k)
            local inside = H.APOTHEM - pull[k] - ((x - cell.x) * math.cos(a) + (z - cell.z) * math.sin(a))
            if inside < 1.3 then
                local g = grain(x * 2, z * 2, 59)
                if inside < 0.7 then return g > 0.2 and IDX.c or IDX.s end
                if g > 0.55 then return IDX.s end
            end
        end
    end
end

-- Where fire has passed (src/cataclysm.lua): the ground blackened in
-- blotches, flecked with pale ash. Nil where it shows through.
local function ash(x, z)
    local v = sin(x * 0.42 + sin(z * 0.31) * 2.1) + sin(z * 0.5 - x * 0.23 + 1.7)
    local g = grain(x, z, 81)
    if v > 0.9 then return g > 0.94 and IDX.s or IDX.u end
    if v > 0.1 then
        if g > 0.96 then return IDX.c end
        return g > 0.35 and IDX.n or IDX.k
    end
    if g > 0.85 then return IDX.n end
end

-- Where the demons' blight lies (src/demons.lua): the ground gone black
-- in patches, veined with cracks of ink and a pale glint here and there in
-- them, as if lit from under. Nil where the ground shows through.
local function veins(x, z)
    local v = sin(x * 0.55 + sin(z * 0.4) * 2.4) * sin(z * 0.47 - x * 0.21 + 1.3)
    local g = grain(x, z, 91)
    if abs(v) < 0.06 then return g > 0.88 and IDX.c or IDX.o end
    if abs(v) < 0.14 then return IDX.u end
    if v > 0.5 then return g > 0.55 and IDX.n or IDX.u end
    if v < -0.6 and g > 0.5 then return IDX.n end
    if g > 0.94 then return IDX.u end
end

-- Where a flood has lain (src/flood.lua): pale silt in bands, as the water
-- left it going down, with dark tide lines between. Nil where it shows
-- through.
local function silt(x, z)
    local v = sin(x * 0.21 + z * 0.13 + sin(z * 0.17 - x * 0.05) * 2.6)
    local g = grain(x, z, 87)
    if v > 0.55 then
        if abs(v - 0.62) < 0.05 then return IDX.t end
        return g > 0.12 and IDX.s or IDX.t
    end
    if v > 0.25 and g > 0.6 then return IDX.c end
end

-- A farm left fallow in the plague (src/plague.lua): the old furrows still
-- showing under it in faint bands, overgrown in dark clumps of dock and
-- nettle, thistles standing pale out of them. Nil where the ground shows
-- through.
local function weeds(s, x, z)
    local g = grain(x, z, 131)
    local clump = sin(x * 0.7 + sin(z * 0.55) * 1.9) * sin(z * 0.62 - x * 0.31 + 0.7)
    if clump > 0.45 then
        if g > 0.9 then return IDX.c end
        return g > 0.3 and IDX.u or IDX.n
    end
    if clump > 0.3 and g > 0.4 then return IDX.n end
    if g > 0.965 then return IDX.w end
    -- The furrows, nearly gone.
    local a = math.rad(s.rows or 30)
    if floor((x * math.cos(a) + z * math.sin(a)) / 1.6) % 3 == 0 and g > 0.55 then return IDX.k end
end

-- Where a stone has fallen (src/skyfall.lua): the pit at the middle
-- blackened, and rays of pale rubble thrown out from it, a few long and
-- most short, specks of it between. Nil where the ground shows through.
local function blast(s, x, z)
    local cell = s.cellRef
    local dx, dz = x - cell.x, z - cell.z
    local d = math.sqrt(dx * dx + dz * dz)
    local g = grain(x, z, 71)
    local pit = s.crater
    if d < pit then return g > 0.25 and IDX.u or IDX.n end
    if d < pit + 1.4 then return g > 0.45 and IDX.n or IDX.k end
    local turn = (math.atan2(dz, dx) + math.pi) / (2 * math.pi) * 11
    local k = floor(turn)
    local long = pit + 2 + grain(k, cell.id, 73) * 9
    if grain(k, cell.id, 72) > 0.3 and d < long and abs(turn - k - 0.5) < 0.2 * (1 - d / (long + 2)) then
        return g > 0.2 and IDX.c or IDX.s
    end
    if g > 0.94 then return IDX.n end
    if g < 0.03 then return IDX.c end
end

--- the sundering (src/quake.lua) ------------------------------------------------------

-- How near room point (x, z) is to the edge between two cells of a jittered
-- grid `size` across (0 on the edge): the plates of a crust.
local function plates(x, z, size, seed)
    local gx, gz = floor(x / size), floor(z / size)
    local d1, d2 = 1e9, 1e9
    for a = -1, 1 do
        for b = -1, 1 do
            local cx, cz = gx + a, gz + b
            local px = (cx + 0.15 + grain(cx, cz, seed) * 0.7) * size
            local pz = (cz + 0.15 + grain(cz, cx, seed + 1) * 0.7) * size
            local d = (x - px) ^ 2 + (z - pz) ^ 2
            if d < d1 then d1, d2 = d, d1 elseif d < d2 then d2 = d end
        end
    end
    return math.sqrt(d2) - math.sqrt(d1)
end

-- Lava, still burning: a black crust broken into plates, the fire showing
-- white and pale in the seams between them. Its glow is set flickering on
-- the board (src/ui/quake.lua).
local function lava(x, z)
    local c = plates(x, z, 3.4, 171)
    if c < 0.28 then return IDX.w end
    if c < 0.55 then return grain(x * 2, z * 2, 172) > 0.4 and IDX.c or IDX.s end
    local g = grain(x, z, 173)
    if g > 0.93 then return IDX.n end
    return IDX.u
end

-- Lava cooled: black rock in ropes and folds, the way it ran, a dull glint
-- on their backs and a pale speck of ash here and there.
local function basalt(x, z)
    local v = sin(x * 0.55 + sin(z * 0.42) * 2.3 + z * 0.12)
    local g = grain(x, z, 174)
    if abs(v - 0.8) < 0.12 then return IDX.n end
    if abs(v + 0.3) < 0.07 then return IDX.o end
    if g > 0.97 then return IDX.s end
    if g > 0.85 then return IDX.n end
    return IDX.u
end

-- Ground the ash has made rich: dark and crumbly, flecked.
local function loam(x, z)
    local g = grain(x, z, 175)
    if g > 0.9 then return IDX.u end
    if g > 0.8 then return IDX.n end
end

-- The sea's floor come up into the air: pale wet sand in ripples, dark
-- weed drying in patches, shells white in it.
local function seabed(x, z)
    local g = grain(x, z, 176)
    if g > 0.985 then return IDX.w end
    local weed = sin(x * 0.31 + sin(z * 0.27) * 2) * sin(z * 0.36 - x * 0.12)
    if weed > 0.55 then return g > 0.4 and IDX.n or IDX.k end
    local r = sin(x * 0.9 + z * 0.35 + sin(z * 0.2) * 1.5)
    if r > 0.82 then return IDX.s end
    if r < -0.9 then return IDX.c end
end

-- The arms of the rift through hex `cell`: from its middle out to the
-- middle of each edge it runs out by (src/quake.lua's riftEdges), as unit
-- headings { x, z }.
local function riftArms(cell)
    local ks = cell.riftEdges
    if not ks or #ks == 0 then
        -- Laid before the rift kept its edges: straight through, the way it
        -- headed.
        local k = floor((cell.riftAngle or 0) / (math.pi / 3) + 0.5) % 6
        ks = { (k + 3) % 6, k }
    elseif #ks == 1 then
        ks = { ks[1], (ks[1] + 3) % 6 }
    end
    local out = {}
    for i, k in ipairs(ks) do
        local a = math.rad(60 * k)
        out[i] = { math.cos(a), math.sin(a), k = k }
    end
    return out
end
World.riftArms = riftArms

-- A hex the rift has cracked: a black crack zigzagging out from its middle
-- along each arm of the rift to the middle of the edge, where it meets the
-- next hex's (or the sea); its lips broken pale, hairline cracks off it.
local function riftCrack(s, x, z)
    local cell = s.cellRef
    local dx, dz = x - cell.x, z - cell.z
    -- The arm nearest.
    local u, v, arm, best
    for i, d in ipairs(s.riftArms) do
        local uu = dx * d[1] + dz * d[2]
        local vv = -dx * d[2] + dz * d[1]
        local far = abs(vv) + max(0, -uu)
        if not best or far < best then u, v, arm, best = uu, vv, i, far end
    end
    if u < -1.5 then return end
    -- The zigzag dies away at the middle and at the edge, so the arms meet,
    -- and meet the next hex's.
    local taper = max(0, min(1, u / 3, (H.APOTHEM - u) / 3))
    local t = (u / 2.6) % 2
    local zig = v - ((abs(t - 1) - 0.5) * 2.2 + sin(u * 0.4) * 0.8) * taper
    local w = abs(zig)
    if w < 0.6 then return IDX.o end
    if w < 1.0 then return IDX.u end
    if w < 1.5 and grain(x * 2, z * 2, 177) > 0.4 then return IDX.c end
    -- Hairlines off it, every so often.
    local k = floor(u / 3.2)
    if k >= 0 and u < H.APOTHEM - 2 and grain(k, cell.id + arm * 7, 178) > 0.5 then
        local off = u - (k + 0.5) * 3.2
        local side = grain(k, cell.id + arm * 7, 179) > 0.5 and 1 or -1
        if v * side > 0 and v * side < 4.5 and abs(off - v * side * 0.5) < 0.3 then return IDX.u end
    end
end

-- The lip of an open fault along edge k of a hex: the ground broken dark
-- right at the edge, cracks running back from it.
local function faultLip(s, x, z)
    local cell, pull = s.cellRef, s.faultPull
    for k = 0, 5 do
        if pull[k] then
            local a = math.rad(60 * k)
            local inside = H.APOTHEM - pull[k] - ((x - cell.x) * math.cos(a) + (z - cell.z) * math.sin(a))
            if inside < 2.6 then
                local along = -(x - cell.x) * math.sin(a) + (z - cell.z) * math.cos(a)
                local g = grain(x * 2, z * 2, 180)
                if inside < 0.6 then return g > 0.25 and IDX.u or IDX.o end
                if inside < 1.2 then return g > 0.55 and IDX.n or nil end
                local jag = floor(along / 2.2)
                if grain(jag, cell.id + k, 181) > 0.55 and abs(along - (jag + 0.5) * 2.2 - (inside - 1.2) * 0.6) < 0.28 then
                    return IDX.u
                end
            end
        end
    end
end

-- The prints of the land laid over a ground's own: lava and black rock, a
-- crater's blast, the rift's crack, ash, then silt, then the rim of a
-- river's bank.
local function overland(s, x, z, ny)
    if ny <= 0.9 then return end
    if s.lava then return lava(x, z) end
    if s.faultPull then
        local a = faultLip(s, x, z)
        if a then return a end
    end
    if s.riftArms then
        local a = riftCrack(s, x, z)
        if a then return a end
    end
    if s.basalt then return basalt(x, z) end
    if s.raised then
        local a = seabed(x, z)
        if a then return a end
    end
    if s.crater then
        local a = blast(s, x, z)
        if a then return a end
    end
    if s.blight then
        local a = veins(x, z)
        if a then return a end
    end
    if s.fallow then
        local a = weeds(s, x, z)
        if a then return a end
    end
    if s.ash then
        local a = ash(x, z)
        if a then return a end
    end
    if s.silt then
        local a = silt(x, z)
        if a then return a end
    end
    if s.soil then
        local a = loam(x, z)
        if a then return a end
    end
    if s.pull then return rim(s, x, z) end
end

MAT.grass = { id = 1, ramp = ramp("s", "k", "n", "u"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    local o = overland(s, x, z, ny)
    if o then return o end
    local g = grain(x, z, 1)
    if g > 0.93 then return IDX.n end           -- tufts
    if g < 0.04 then return IDX.t end           -- flowers
    if ny > 0.9 and grain(floor(x / 3), floor(z / 2), 2) > 0.86 then return IDX.n end
end }
MAT.plains = { id = 2, ramp = ramp("c", "t", "k", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    local o = overland(s, x, z, ny)
    if o then return o end
    local g = grain(x, z, 3)
    if g > 0.94 then return IDX.k end
    if g < 0.03 then return IDX.s end
    -- Dry grass in long strokes, leaning.
    if ny > 0.9 and (floor(x + z * 0.5) % 7 == 0) and grain(floor(x / 4), z, 4) > 0.45 then return IDX.k end
end }
MAT.desert = { id = 3, ramp = ramp("w", "c", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    local o = overland(s, x, z, ny)
    if o then return o end
    -- Dunes: ripples running across.
    local d = sin(x * 0.35 + sin(z * 0.25) * 2.2 + z * 0.1)
    if ny > 0.9 and abs(d - 0.75) < 0.12 then return IDX.s end
    if grain(x, z, 5) > 0.96 then return IDX.t end
end }

-- Marsh, the long rains' (src/flood.lua): sodden ground darker than the
-- grass, tussocks of sedge pale on it and black mud between.
MAT.marsh = { id = 14, ramp = ramp("t", "k", "n", "u"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    local o = overland(s, x, z, ny)
    if o then return o end
    local g = grain(x, z, 61)
    if g > 0.9 then return IDX.s end
    if g < 0.07 then return IDX.u end
    if ny > 0.9 and floor(x * 0.9 - z * 0.4) % 5 == 0 and grain(floor(x / 2), floor(z), 62) > 0.55 then return IDX.c end
end }
-- Floodwater, lying on the land: brown and thick, eddies in it. The board's
-- shader sets it moving (src/ui/sea.lua); this is how it lies still.
MAT.flood = { id = 19, ramp = ramp("t", "k", "n", "u"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return grain(x * 2, y * 2, 63) > 0.6 and IDX.c or IDX.t end
    local e = sin(x * 0.12 + sin(z * 0.3) * 1.8) + 0.5 * sin(z * 0.9 - x * 0.05)
    if abs(e - 0.9) < 0.1 then return IDX.t end
    if abs(e + 0.6) < 0.08 then return IDX.u end
    if grain(x, z, 64) > 0.99 then return IDX.c end
    return IDX.n
end }
-- A marsh's standing pools: still, dark, a glint at the back.
MAT.pool = { id = 20, ramp = ramp("n", "u", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny > 0.8 and nz < -0.1 and nx < 0 and grain(x * 2, z * 2, 65) > 0.6 then return IDX.k end
    return ny > 0.6 and IDX.u or IDX.o
end }
-- Trees the sea has drowned: dead wood, bleached.
MAT.deadwood = { id = 8, ramp = ramp("c", "s", "t", "n") }
-- A fallen stone (src/skyfall.lua), cooled: a dark lump, pitted, the odd
-- glint of metal in it. Still hot, it glows: pale through a black crust.
MAT.starstone = { id = 41, ramp = ramp("t", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    local g = grain(x * 2, y * 2 + z, 74)
    if g > 0.93 then return IDX.s end
    if g < 0.12 then return IDX.o end
end }
MAT.hotstone = { id = 42, ramp = ramp("w", "w", "c", "s"), print = function(s, x, y, z, nx, ny, nz, lev)
    local v = sin(x * 1.7 + sin(z * 1.3) * 2) + sin(y * 2.1 - z * 0.9)
    if v > 0.6 then return IDX.u end
    if v > 0.2 then return IDX.k end
end }
-- The depths of a chasm or a fault: dark, the odd glint of wet rock.
local ABYSS_SIDE = ramp("u", "o", "o", "o")
MAT.abyss = { id = 51, ramp = ramp("n", "u", "o", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return strata(x, y, z, lev) == SIDE and SIDE_DARK or ABYSS_SIDE end
    if grain(x * 2, z * 2, 182) > 0.9 then return IDX.n end
    return IDX.o
end }
-- Molten rock: the lava running down a volcano and filling its crater.
MAT.lava = { id = 52, ramp = ramp("w", "w", "c", "s"), print = function(s, x, y, z, nx, ny, nz, lev)
    local v = sin(x * 1.3 + sin(z * 1.1 + y) * 2) + sin(y * 1.7 - z * 0.8)
    if v > 1.1 then return IDX.u end
    if v > 0.7 then return IDX.n end
end }
-- A volcano's cone: ash and cinders in bands round it, darker than rock,
-- streaked down the slope where the old flows ran.
MAT.cinder = { id = 53, ramp = ramp("c", "s", "t", "k"), print = function(s, x, y, z, nx, ny, nz, lev)
    local band = floor((y + sin(x * 0.3 + z * 0.2) * 0.8) / 1.6)
    local streak = grain(floor(math.atan2(z - s.cellRef.z, x - s.cellRef.x) * 9), 0, 183)
    if streak > 0.8 then return lev <= 2 and IDX.n or IDX.u end
    if band % 4 == 0 then return lev <= 2 and IDX.t or IDX.n end
    if grain(x * 2, y * 2 + z, 184) > 0.93 then return IDX.s end
end }

-- Star iron: black and heavy, its broken faces bright.
MAT.iron = { id = 43, ramp = ramp("c", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(x * 3, y * 3 + z, 75) > 0.9 then return IDX.w end
end }

-- Cracks between the plates of baked mud: where room point (x, z) is
-- nearly as near the second-nearest of a jittered grid of points as the
-- nearest. Answers how near (0 on the crack).
local CRACK = 3.2
local function crack(x, z)
    local gx, gz = floor(x / CRACK), floor(z / CRACK)
    local d1, d2 = 1e9, 1e9
    for a = -1, 1 do
        for b = -1, 1 do
            local cx, cz = gx + a, gz + b
            local px = (cx + 0.15 + grain(cx, cz, 91) * 0.7) * CRACK
            local pz = (cz + 0.15 + grain(cz, cx, 92) * 0.7) * CRACK
            local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
            if d < d1 then d1, d2 = d, d1 elseif d < d2 then d2 = d end
        end
    end
    return d2 - d1
end

-- Baked earth, the scorch's (src/cataclysm.lua): a darker clay than the
-- sand, split into plates by dark cracks, their lips caught light.
MAT.scorched = { id = 16, ramp = ramp("c", "s", "t", "k"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    if ny > 0.9 and s.pull then
        local r = rim(s, x, z)
        if r then return r end
    end
    if s.crater and ny > 0.9 then
        local a = blast(s, x, z)
        if a then return a end
    end
    if s.ash and ny > 0.9 then
        local a = ash(x, z)
        if a and a ~= IDX.k then return a end
    end
    if s.silt and ny > 0.9 then
        local a = silt(x, z)
        if a then return a end
    end
    if ny > 0.9 then
        local c = crack(x, z)
        if c < 0.38 then return IDX.n end
        if c < 0.7 then return IDX.w end
        if grain(x, z, 93) > 0.95 then return IDX.k end
    end
end }
-- The sea's floor the great ebb has left bare (src/cataclysm.lua): a crust
-- of salt, white, cracked into great plates with their lips curled, the
-- dried mud dark in the seams; the old ripples of the sand showing
-- through, and the odd shell, weed or bone. Its cut side is the mud the
-- sea laid down, in thin bands.
MAT.saltflat = { id = 54, ramp = ramp("w", "c", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then
        local band = floor((y + 0.3 * sin(x * 0.3 + z * 0.2)) * 1.4)
        return band % 4 == 0 and IDX.t or (band % 2 == 0 and IDX.s or IDX.c)
    end
    if ny > 0.9 then
        local c = crack(x * 0.55, z * 0.55)
        if c < 0.1 then return IDX.n end
        if c < 0.2 then return IDX.t end
        if c < 0.3 then return IDX.w end
        local r = sin(x * 0.8 + z * 0.33 + sin(z * 0.21) * 1.6)
        if r > 0.9 and grain(floor(x * 0.5), floor(z * 2), 190) > 0.35 then return IDX.c end
        local g = grain(x, z, 191)
        if g > 0.993 then return IDX.k end
        if g > 0.985 then return IDX.s end
    end
end }
-- A river's bed run dry: mud cracked into small plates, darker than the
-- banks, pale stones lying where the water ran; its banks are the earth's.
MAT.riverbed = { id = 55, ramp = ramp("s", "t", "k", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return strata(x, y, z, lev) end
    local c = crack(x * 1.7, z * 1.7)
    if c < 0.14 then return IDX.u end
    if c < 0.3 then return IDX.n end
    local g = grain(x, z, 192)
    if g > 0.94 then return IDX.c end
    if g > 0.9 then return IDX.s end
end }

-- What fire leaves of a tree, and a tree still burning: charcoal, its
-- grain picked out in glowing (lit) seams.
MAT.char = { id = 17, ramp = ramp("n", "u", "o", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(floor(x * 2), floor(y * 1.5), 94) > 0.9 then return IDX.k end
end }
MAT.charTree = { id = 18, ramp = ramp("k", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(x * 2, y * 2 + z, 7) > 0.8 then return IDX.o end
end }

--- the frost (src/frost.lua) ----------------------------------------------------------

-- Frozen ground, the tundra: a pale ground cut into the great polygons the
-- frost heaves it into, the troughs between them filled white with snow,
-- dark tussocks and pale lichen scattered over it, rime glinting.
local POLY = 7.5
local function polygon(x, z)
    local gx, gz = floor(x / POLY), floor(z / POLY)
    local d1, d2 = 1e9, 1e9
    for a = -1, 1 do
        for b = -1, 1 do
            local cx, cz = gx + a, gz + b
            local px = (cx + 0.1 + grain(cx, cz, 141) * 0.8) * POLY
            local pz = (cz + 0.1 + grain(cz, cx, 142) * 0.8) * POLY
            local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
            if d < d1 then d1, d2 = d, d1 elseif d < d2 then d2 = d end
        end
    end
    return d2 - d1
end
MAT.tundra = { id = 44, ramp = ramp("c", "s", "t", "k"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    local o = overland(s, x, z, ny)
    if o then return o end
    if ny > 0.9 then
        local p = polygon(x, z)
        if p < 0.5 then return grain(x * 2, z * 2, 143) > 0.15 and IDX.w or IDX.c end
        if p < 0.9 then return IDX.c end
    end
    local g = grain(x, z, 144)
    if g > 0.965 then return IDX.n end              -- tussocks
    if g > 0.93 then return IDX.k end
    if g < 0.03 then return IDX.w end               -- rime
    if g < 0.06 then return IDX.c end               -- lichen
end }
-- Snow, deep and drifted: white, the drifts' crests and the wind's ripples
-- (sastrugi) a step down in long strokes, a sparkle here and there. Its cut
-- side is snow on the earth.
MAT.snow = { id = 45, ramp = ramp("w", "w", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then
        if y > (s.cellRef and s.cellRef.top or 0) - 1.4 then return IDX.w end
        return strata(x, y, z, lev)
    end
    local o = overland(s, x, z, ny)
    if o then return o end
    if ny > 0.9 then
        local d = sin(x * 0.13 + sin(z * 0.21) * 1.8 - z * 0.05)
        if d > 0.86 and grain(floor(x * 0.5), floor(z * 2), 146) > 0.25 then return IDX.c end
        local r = sin(x * 0.7 + z * 0.3 + sin(z * 0.4 + x * 0.05) * 1.4)
        if r > 0.95 and grain(floor(x * 0.4), floor(z * 2.2), 147) > 0.55 then return IDX.c end
    end
    local g = grain(x, z, 148)
    if g > 0.996 then return IDX.s end
end }
-- The sea frozen: great floes of white, the seams between them a thin grey
-- line with a bright lip, snow dusted over in streaks, grey new ice where a
-- lead froze last; its edge an ice cliff in blue-white layers.
MAT.ice = { id = 46, ramp = ramp("w", "c", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then
        local band = floor((y + 0.5 * sin(x * 0.4 + z * 0.3)) * 1.6)
        return band % 3 == 0 and IDX.s or (band % 3 == 1 and IDX.c or IDX.w)
    end
    local lead = sin(x * 0.07 + sin(z * 0.06) * 2.2 + z * 0.035)
    if abs(lead) < 0.02 then return IDX.n end
    if abs(lead) < 0.06 then return grain(x * 2, z * 2, 149) > 0.6 and IDX.s or IDX.t end
    local c = crack(x * 0.3, z * 0.3)
    if c < 0.07 then return IDX.t end
    if c < 0.16 then return IDX.w end
    local dust = sin(x * 0.2 - z * 0.1 + sin(x * 0.05) * 3)
    if dust > 0.75 then return grain(x, z, 150) > 0.15 and IDX.w or IDX.c end
    local g = grain(x, z, 151)
    if g > 0.99 then return IDX.w end
    if g < 0.012 then return IDX.s end
    return IDX.c
end }
-- Blocks of ice thrown up where the floes pressed together, and the snow on
-- them: white on top, their broken faces a step or two down, streaked.
MAT.iceblock = { id = 47, ramp = ramp("w", "c", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny > 0.9 then return grain(x * 2, z * 2, 152) > 0.1 and IDX.w or IDX.c end
    if grain(floor(y * 2), floor(x + z), 153) > 0.9 then return IDX.w end
    -- The broken faces: blue-grey ice, darker turned from the light.
    return lev <= 2 and IDX.c or (lev == 3 and IDX.s or IDX.t)
end }
-- A river frozen over: grey ice, snow blown along it in streaks the way it
-- ran, a crack down the middle and its banks rimed.
MAT.riverIce = { id = 48, ramp = ramp("s", "t", "k", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return strata(x, y, z, lev) end
    local f = s.flow
    local along, across = x * f[1] + z * f[2], z * f[1] - x * f[2]
    if grain(floor(along / 4), floor(across * 1.2), 154) > 0.72 then return IDX.c end
    local c = crack(along * 0.7, across * 1.6)
    if c < 0.12 then return IDX.n end
    if grain(x, z, 155) > 0.97 then return IDX.w end
    return IDX.t
end }
-- Trees under snow: the snow lying on whatever looks up, in clumps; on
-- tundra only a rime on the tops of the needles. The trunks dark.
MAT.snowTree = { id = 49, ramp = ramp("t", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny > 0.25 and grain(floor(x * 1.5), floor(z * 1.5 + y), 156) > 0.15 then return ny > 0.6 and IDX.w or IDX.c end
    if ny > -0.2 and grain(x * 2, y * 2 + z, 157) > 0.8 then return IDX.c end
    if grain(x * 2, y * 2 + z, 7) > 0.88 and lev <= 3 then return IDX.u end
end }
MAT.rimeTree = { id = 50, ramp = ramp("t", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny > 0.55 and grain(floor(x * 2), floor(z * 2 + y), 158) > 0.55 then return IDX.c end
    if grain(x * 2, y * 2 + z, 159) > 0.93 then return IDX.s end
    if grain(x * 2, y * 2 + z, 7) > 0.88 and lev <= 3 then return IDX.u end
end }

-- Water: the sea's top, by what kind of water the hex is. Ripples, glints,
-- and foam where it meets the land.
local function water(s, x, z, deep)
    local g = grain(x, z, 13)
    local ripple = sin(x * 0.45 + z * 0.2) + sin(z * 0.6 - x * 0.17)
    if g > 0.998 then return IDX.c end
    local cell = s.cellRef
    if cell and not deep then
        -- Foam along any edge with land beyond it.
        for k = 0, 5 do
            local a = math.rad(60 * k)
            local inside = H.APOTHEM - ((x - cell.x) * math.cos(a) + (z - cell.z) * math.sin(a))
            if inside < 2.2 then
                local c, r = H.step(cell.c, cell.r, k)
                local n = s.world:cellAt(c, r)
                if n and not D.TERRAIN[n.terrain].water then
                    if inside < 1.1 or grain(x * 2, z, 17) > 0.5 then return IDX.c end
                end
            end
        end
    end
    if cell and cell.ruin then
        -- A town the great flood sank (src/flood.lua): its walls and
        -- streets seen dark through the water, in blocks, broken.
        local a = math.rad(15 + (cell.id % 3) * 30)
        local u = (x - cell.x) * math.cos(a) + (z - cell.z) * math.sin(a)
        local v = (z - cell.z) * math.cos(a) - (x - cell.x) * math.sin(a)
        if H.inset(x, z, cell.x, cell.z) > 2.5 and grain(floor(u / 4.4), floor(v / 4.4), cell.id + 193) > 0.25 then
            local fu, fv = (u / 4.4) % 1, (v / 4.4) % 1
            if (fu < 0.14 or fv < 0.14) and grain(x * 2, z * 2, 194) > 0.3 then return IDX.u end
        end
    end
    if deep then
        if abs(ripple - 1.1) < 0.08 then return IDX.n end
        if abs(ripple + 0.7) < 0.06 then return IDX.o end
        return IDX.u
    end
    if abs(ripple - 1.0) < 0.1 then return IDX.t end
    if abs(ripple + 0.6) < 0.08 then return IDX.u end
    return IDX.n
end
MAT.ocean = { id = 4, ramp = ramp("n", "u", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return SIDE_DARK end
    return water(s, x, z, true)
end }
MAT.coast = { id = 5, ramp = ramp("k", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return SIDE_DARK end
    return water(s, x, z, false)
end }
MAT.rock = { id = 6, ramp = ramp("c", "t", "k", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    -- Snow on the high faces that look up.
    if s.snow and y > s.snow and ny > 0.3 then return lev <= 3 and IDX.w or IDX.c end
    local g = grain(x * 1.5, z + y * 2, 6)
    if g > 0.94 then return IDX.n end
end }
MAT.tree = { id = 7, ramp = ramp("t", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(x * 2, y * 2 + z, 7) > 0.88 and lev <= 3 then return IDX.u end
end }
MAT.trunk = { id = 8, ramp = ramp("t", "n", "u", "o") }
MAT.wheat = { id = 9, ramp = ramp("w", "c", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(x * 3, y * 3, 8) > 0.8 then return IDX.t end
end }
-- A plot of standing grain: its ears speckled on top, its rows down the
-- sides.
MAT.plot = { id = 9, ramp = MAT.wheat.ramp, print = function(s, x, y, z, nx, ny, nz, lev)
    if ny > 0.5 then
        if grain(x * 3, z * 3, 8) > 0.86 then return IDX.s end
    elseif floor(x * 1.2 + z * 0.7) % 2 == 0 then
        return IDX.s
    end
end }
MAT.stone = { id = 10, ramp = ramp("w", "c", "k", "n") }
MAT.gem = { id = 11, ramp = ramp("w", "w", "s", "k") }
-- A river's water: ripples drawn along the way it runs, a glint now and
-- then, white where the river above falls into it; its cut banks are the
-- earth's strata, and where it falls over one the fall is white water.
MAT.river = { id = 12, ramp = ramp("k", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then
        if s.falls then
            local col = floor(x * 1.3 + z * 0.8)
            return grain(col, floor(y * 0.7), 31) > 0.4 and IDX.w or IDX.c
        end
        return strata(x, y, z, lev)
    end
    local f = s.flow
    if s.foot and (x - s.foot[1]) ^ 2 + (z - s.foot[2]) ^ 2 < s.churn then
        return grain(x * 2, z * 2, 32) > 0.45 and IDX.c or IDX.s
    end
    local along, across = x * f[1] + z * f[2], z * f[1] - x * f[2]
    -- Streaks drawn out along the stream.
    if grain(floor(along / 3.5), floor(across * 1.4), 34) > 0.8 then return IDX.n end
    if grain(x, z, 33) > 0.995 then return IDX.k end
    return IDX.u
end }
-- Reeds along the banks, and their dark heads; the planks of a bridge.
MAT.reed = { id = 13, ramp = ramp("c", "s", "t", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    -- Stems, and their dark heads standing out of the top.
    if y > s.heads and grain(floor(x * 1.6), floor(y * 0.8), 58) > 0.55 then return IDX.u end
    if floor(x * 1.6 + z * 0.3) % 2 == 0 then return lev >= 3 and IDX.n or IDX.t end
end }
MAT.plank = { id = 15, ramp = ramp("c", "s", "t", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    local a = s.across
    if a and ny > 0.9 and floor((x * a[1] + z * a[2]) * 1.1) % 3 == 0 then return IDX.t end
end }

-- Hills are their ground's own stuff, but a material of their own, so no
-- crease rings them where they meet the flat.
local MOUND = {}
for _, k in ipairs({ "grass", "plains", "desert", "scorched", "marsh", "tundra", "snow" }) do
    MOUND[k] = { id = MAT[k].id + 20, ramp = MAT[k].ramp, print = MAT[k].print }
end

--- building the solids --------------------------------------------------------------

-- A hex prism in the room, standing from the map's bottom up to `top`.
-- `pull`, if given, pulls edge k in by pull[k]: where a river runs.
local function hexPrism(cx, cz, top, pull)
    local planes = {}
    for k = 0, 5 do
        local a = math.rad(60 * k)
        local nx, nz = math.cos(a), math.sin(a)
        planes[#planes + 1] = { nx, 0, nz, nx * cx + nz * cz + H.APOTHEM - (pull and pull[k] or 0) }
    end
    planes[#planes + 1] = { 0, 1, 0, top }
    planes[#planes + 1] = { 0, -1, 0, -BOTTOM }
    return { kind = "hull", planes = planes, prism = true,
        box = { cx - H.APOTHEM, cx + H.APOTHEM, BOTTOM, top, cz - H.R, cz + H.R } }
end

--- rivers ----------------------------------------------------------------------------

-- How far a river cuts into each hex beside it: wider below where two join.
local BANK = { 3.6, 4.6 }
local function bankOf(e) return e.size >= 2 and BANK[2] or BANK[1] end
World.bankOf = bankOf

-- The water of river `e` along edge k of a hex: the hex's prism, only the
-- strip of it within the bank of the edge, down at the water's level.
local function riverStrip(cell, k, e, level)
    local s = hexPrism(cell.x, cell.z, level or e.level)
    local a = math.rad(60 * k)
    local nx, nz = math.cos(a), math.sin(a)
    local bank = bankOf(e)
    table.insert(s.planes, { -nx, 0, -nz, -(nx * cell.x + nz * cell.z + H.APOTHEM - bank) })
    s.prism = nil
    local fx, fz = e.to[1] - e.from[1], e.to[2] - e.from[2]
    local l = math.sqrt(fx * fx + fz * fz)
    s.flow = { fx / l, fz / l }
    s.falls = e.fall or e.mouth
    if e.foot then s.foot, s.churn = e.from, (bank * 1.7) ^ 2 end
    s.riverPart = true
    return s
end

-- How far an open fault (src/quake.lua) cuts into each hex beside it, and
-- how deep the dark goes.
local FAULT = 2.2
local DEEP = -6

-- The bottom of a fault along edge k of a hex: the strip of its prism
-- within the fault's width of the edge, far down, or up at the sea's level
-- where the sea has got into it (`wet`).
local function faultStrip(cell, k, wet)
    local s = hexPrism(cell.x, cell.z, wet and D.TERRAIN.coast.top or DEEP)
    local a = math.rad(60 * k)
    local nx, nz = math.cos(a), math.sin(a)
    table.insert(s.planes, { -nx, 0, -nz, -(nx * cell.x + nz * cell.z + H.APOTHEM - FAULT - 0.3) })
    s.prism = nil
    return s
end

-- Where along a river edge k of a hex: the room point `inset` in from the
-- edge's middle, `u` along it.
local function alongEdge(cell, k, inset, u)
    local a = math.rad(60 * k)
    local nx, nz = math.cos(a), math.sin(a)
    local d = H.APOTHEM - inset
    return cell.x + nx * d - nz * u, cell.z + nz * d + nx * u
end

-- Is room point (x, z) on hex `cell` within `margin` of the water of a
-- river along its edges?
local function nearRiver(cell, x, z, margin)
    if not cell.river and not cell.dry then return false end
    for k = 0, 5 do
        local e = (cell.river and cell.river[k]) or (cell.dry and cell.dry[k])
        if e then
            local a = math.rad(60 * k)
            local inside = H.APOTHEM - ((x - cell.x) * math.cos(a) + (z - cell.z) * math.sin(a))
            if inside < bankOf(e) + margin then return true end
        end
    end
    return false
end

-- Points scattered over a hex, kept `inset` in from its edge: the same ones
-- for the same hex every time.
local function scatter(cell, n, inset, k)
    local out = {}
    local tries = 0
    while #out < n and tries < n * 12 do
        tries = tries + 1
        local x = cell.x + (grain(cell.id, tries, k) * 2 - 1) * H.R
        local z = cell.z + (grain(tries, cell.id, k + 1) * 2 - 1) * H.R
        if H.inset(x, z, cell.x, cell.z) > inset and not nearRiver(cell, x, z, 2) then
            local ok = true
            for _, p in ipairs(out) do
                if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < 20 then ok = false end
            end
            if ok then out[#out + 1] = { x, z } end
        end
    end
    -- Back to front, so nothing depends on the order they were found in.
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

-- The solids of one hex.
function World:hexSolids(cell)
    local out = {}
    local ashen = (cell.burnt or cell.fire or cell.ashfall) and true or nil
    local silted = cell.silt and not cell.flood or nil
    -- A field abandoned in the plague, its furrows the way its farm's ran.
    local fallow = (cell.fallow and not cell.improvement and not cell.city) or nil
    -- A crater's pit: wider the deeper it went.
    local pit = cell.crater and not cell.city and min(5.5, 1.6 + (cell.sunk or 0) * 0.6) or nil
    local function add(s, mat)
        s.mat, s.cell, s.cellRef, s.world = mat, cell.id, cell, self
        s.ash, s.silt, s.crater, s.blight = ashen, silted, pit, cell.blight
        s.fallow = fallow
        -- The sundering's (src/quake.lua).
        s.lava, s.basalt, s.soil, s.raised = cell.lava and true, cell.basalt, cell.soil and not cell.ashfall, cell.raised
        if cell.rift == 1 then s.riftArms = riftArms(cell) end
        -- The way its rows ran, as src/models.lua's M.FARM_LAYOUTS has them.
        if fallow then s.rows = ({ 30, 90, 150 })[cell.id % 3 + 1] end
        out[#out + 1] = s
        return s
    end
    local t = D.TERRAIN[cell.terrain]
    local top = cell.top
    local soil = cell.scorched and "scorched" or cell.terrain
    local base = cell.elev == "mountain" and MAT.rock or MAT[soil]
    local river = not t.water and not t.sea and cell.river
    -- The beds of the rivers the heat has dried (src/cataclysm.lua).
    local dry = not t.water and not t.sea and cell.dry
    local pull
    if river or dry then
        pull = {}
        for k = 0, 5 do
            local e = (river and river[k]) or (dry and dry[k])
            pull[k] = e and bankOf(e) or nil
        end
    end
    -- The sundering's open faults (src/quake.lua) cut the hex back from its
    -- edge as a river does, and leave the dark below.
    local faults
    if cell.fault and not t.water then
        for k = 0, 5 do
            if cell.fault[k] then
                faults = faults or {}
                faults[k] = FAULT
            end
        end
    end
    local cut = pull
    if faults then
        cut = {}
        for k = 0, 5 do cut[k] = max(pull and pull[k] or 0, faults[k] or 0) end
    end
    -- The sea's ice stands a little proud of the water: its edge a low cliff.
    if t.sea then top = top + 1 end
    if faults then
        for k = 0, 5 do
            if faults[k] then
                local wet = cell.faultWet and cell.faultWet[k]
                add(faultStrip(cell, k, wet), wet and MAT.coast or MAT.abyss)
            end
        end
    end
    -- A chasm the rift has torn: a canal from the hex's middle out to the
    -- middle of each edge the rift runs out by -- on to the next hex of
    -- the rift, or at its ends into the sea -- the land standing either
    -- side of it, the dark below, or the sea pouring in; a few boulders
    -- fallen in.
    if (cell.rift or 0) >= 2 and not t.water then
        local arms = riftArms(cell)
        local gap = cell.rift == 2 and 3.8 or 5
        local cx, cz = cell.x, cell.z
        -- The land beside an arm d on its left (`side` 1) or right (-1),
        -- `off` out from it: the half of the room there, as a hull's plane.
        local function beside(d, side, off)
            local lx, lz = -d[2], d[1]
            return { -side * lx, 0, -side * lz, -side * (lx * cx + lz * cz) - off }
        end
        local th = {}
        for i, d in ipairs(arms) do th[i] = math.atan2(d[2], d[1]) end
        -- Round the middle from each arm to the next: the land between them.
        local n = #arms
        local order = {}
        for i = 1, n do order[i] = i end
        table.sort(order, function(i, j) return th[i] < th[j] end)
        for o = 1, n do
            local a, b = arms[order[o]], arms[order[o % n + 1]]
            local span = th[order[o % n + 1]] - th[order[o]]
            if span <= 1e-6 then span = span + 2 * math.pi end
            local pieces
            if span <= math.pi + 1e-6 then
                -- Narrow enough to be one piece; none if the canal fills it.
                if gap / math.sin(span / 2) < H.R - 0.5 then pieces = { { beside(a, 1, gap), beside(b, -1, gap) } } end
            else
                -- Wider: two, either side of the line halfway between.
                local m = th[order[o]] + span / 2
                local mid = { math.cos(m), math.sin(m) }
                pieces = { { beside(a, 1, gap), beside(mid, -1, 0) }, { beside(mid, 1, 0), beside(b, -1, gap) } }
            end
            for _, cuts in ipairs(pieces or {}) do
                local piece = hexPrism(cx, cz, top, cut)
                for _, pl in ipairs(cuts) do table.insert(piece.planes, pl) end
                local h = add(piece, base)
                h.pull, h.faultPull = pull, faults
            end
        end
        local sea = cell.rift == 3
        add(hexPrism(cx, cz, sea and D.TERRAIN.coast.top or DEEP), sea and MAT.coast or MAT.abyss)
        -- Boulders: one at the middle, one out along each arm.
        for k = 0, n do
            local d = arms[k] or arms[1]
            local u = k == 0 and 0 or 5 + (grain(cell.id, k, 185) - 0.5) * 2
            local w = (grain(k, cell.id, 186) - 0.5) * gap
            local bx, bz = cx + d[1] * u - d[2] * w, cz + d[2] * u + d[1] * w
            if H.inset(bx, bz, cx, cz) > 2 then
                local r = 1.2 + grain(cell.id, k, 187) * 0.8
                local y = sea and D.TERRAIN.coast.top - 0.4 or (k == 0 and 0 or DEEP + 2 + k)
                add(Sh.ell(bx, y, bz, r * 1.2, r, r), MAT.stone)
            end
        end
        return out
    end
    local ground = add(hexPrism(cell.x, cell.z, top, cut), base)
    ground.pull, ground.faultPull = pull, faults
    if t.water then
        if cell.drownedForest then
            -- What the sea left of a forest: dead trunks standing out of the
            -- water, bleached, some broken off, one leaning.
            for n, p in ipairs(scatter(cell, 5, 3.5, 40)) do
                local x, z = p[1], p[2]
                local tall = 0.85 + grain(x, z, 41) * 0.35
                local h = (n % 3 == 0) and 2.2 or 5.5
                local lx = n % 4 == 1 and 1.6 or (grain(x, z, 95) - 0.5) * 0.6
                add(Sh.seg(x, top - 1, z, x + lx, top + h * tall, z, n % 3 == 0 and 0.75 or 0.55), MAT.deadwood)
                if h > 3 and n % 2 == 0 then
                    add(Sh.seg(x + lx * 0.6, top + 3.4 * tall, z, x + lx * 0.6 + 1.5, top + 4.6 * tall, z - 0.3, 0.3),
                        MAT.deadwood)
                end
            end
        end
        return out
    end
    if t.sea then
        -- The sea frozen (src/frost.lua): a ridge of blocks thrown up where
        -- two floes pressed together, slabs tilted on end along it, a few
        -- broken pieces lying loose, and whatever drowned trees stood in
        -- the water caught in it.
        local a = grain(cell.id, 1, 160) * math.pi
        local ca, sa = math.cos(a), math.sin(a)
        local off = (grain(cell.id, 2, 160) - 0.5) * 6
        for k = -3, 3 do
            local u = k * 2.4 + (grain(cell.id, k, 161) - 0.5) * 0.8
            local x, z = cell.x + ca * u - sa * off, cell.z + sa * u + ca * off
            if H.inset(x, z, cell.x, cell.z) > 3 then
                local h = 2.4 + grain(cell.id, k, 162) * 3.4 * (1 - abs(k) / 5)
                local w = 2.2 + grain(k, cell.id, 163) * 1.2
                add(Sh.frustum(4, 0.3, x, top - 0.4, z, w, h, nil, -a + (grain(cell.id, k, 164) - 0.5) * 1.2),
                    MAT.iceblock).join = "ridge"
            end
        end
        -- And a hummock: snow drifted over broken ice.
        local p = scatter(cell, 1, 5, 165)[1]
        if p then
            local r = 2.6 + grain(p[1], p[2], 166) * 1.4
            add(Sh.ell(p[1], top - 0.3, p[2], r, 1.6 + grain(p[2], p[1], 167), r * 0.8), MAT.iceblock)
        end
        if cell.drownedForest then
            for n, p in ipairs(scatter(cell, 4, 3.5, 40)) do
                local x, z = p[1], p[2]
                local h = (n % 3 == 0) and 2.2 or 5.5
                add(Sh.seg(x, top - 1, z, x + (grain(x, z, 95) - 0.5) * 0.6, top + h, z, 0.55), MAT.deadwood)
            end
        end
        return out
    end
    if dry then
        -- Dry: the bed a little below where the water ran.
        for k = 0, 5 do
            local e = dry[k]
            if e then
                local bed = add(riverStrip(cell, k, e, e.level - 0.6), MAT.riverbed)
                bed.riverPart, bed.falls, bed.foot, bed.join = nil, nil, nil, "bed"
            end
        end
    end
    if river then
        -- Frozen over on frozen ground (src/frost.lua).
        local riverMat = t.frozen and MAT.riverIce or MAT.river
        for k = 0, 5 do
            if river[k] then add(riverStrip(cell, k, river[k]), riverMat) end
        end
    end

    if cell.elev == "hills" and not cell.city then
        -- One broad mound in the middle, a unit stands on it, and a smaller
        -- one off to a side. A city levels them.
        local mound = river and 0.74 or 1
        add(Sh.ell(cell.x, top - 0.8, cell.z, 9.5 * mound, 4, 7.5 * mound), MOUND[soil])
        local a = grain(cell.id, 7, 21) * math.pi * 2
        if river then
            -- Off towards an edge no river runs along.
            local k0 = floor(grain(cell.id, 8, 21) * 6)
            for d = 0, 5 do
                local k = (k0 + d) % 6
                if not river[k] and not river[(k + 1) % 6] and not river[(k + 5) % 6] then a = math.rad(60 * k) break end
            end
        end
        add(Sh.ell(cell.x + math.cos(a) * 7, top - 0.5, cell.z + math.sin(a) * 5, 4.5, 2.6, 3.5), MOUND[soil])
    elseif cell.elev == "mountain" then
        -- A ring of five to seven points round (cx, cz), each pushed in or out.
        local function ring(cx, cz, r, seed)
            local poly = {}
            local sides = 5 + floor(grain(cell.id, 9, seed) * 3)
            for k = 0, sides - 1 do
                local a = math.rad(360 * k / sides + grain(cell.id, 0, seed) * 60 + (grain(cell.id, k, seed) - 0.5) * 18)
                local rr = r * (0.82 + grain(k, cell.id, seed) * 0.18)
                poly[#poly + 1] = { cx + rr * math.cos(a), cz + rr * math.sin(a) }
            end
            return poly
        end
        if cell.volcano then
            -- A volcano: a cone of cinders cut off flat at the top, a crater
            -- in it dark, or full of fire while it erupts and the lava
            -- running down its sides.
            local h = 20
            local r = H.R * (river and 0.8 or 0.94)
            local turn = grain(cell.id, 6, 30)
            add(Sh.frustum(12, 0.26, cell.x, top - 0.5, cell.z, r, h + 0.5, nil, turn), MAT.cinder)
            -- The crater's lip, and the pit in it.
            local hot = cell.erupting
            add(Sh.ell(cell.x, top + h - 0.2, cell.z, r * 0.21, 0.9, r * 0.19), hot and MAT.lava or MAT.abyss)
            -- Lava down its sides while it erupts: three tongues, the
            -- front one towards the camera.
            if hot then
                for k = 0, 2 do
                    local a = math.rad(grain(cell.id, k, 188) * 50 + k * 120 + 65)
                    local ca, sa = math.cos(a), math.sin(a)
                    for m = 0, 3 do
                        local f0, f1 = m / 4, (m + 1) / 4
                        local wob = (grain(cell.id, k * 4 + m, 189) - 0.5) * 2
                        local function at(f) return 0.26 + f * 0.7 end
                        add(Sh.seg(cell.x + ca * r * at(f0) - sa * wob * f0, top + h * (1 - f0) + 0.3, cell.z + sa * r * at(f0) + ca * wob * f0,
                            cell.x + ca * r * at(f1) - sa * wob * f1, top + h * (1 - f1) + 0.3, cell.z + sa * r * at(f1) + ca * wob * f1,
                            0.8 + f0 * 0.5, 0.8 + f1 * 0.5), MAT.lava).join = "lava"
                    end
                end
            end
            return out
        end
        -- Kept back from a river below it.
        local wide = river and 0.78 or 0.92
        local ox = (grain(cell.id, 1, 30) - 0.5) * 5
        local h = 13 + grain(cell.id, 2, 30) * 10
        local main = add(Sh.peak(ring(cell.x + ox * 0.5, cell.z, H.R * wide, 31), top,
            { cell.x + ox, top + h, cell.z - 1 - grain(cell.id, 4, 30) * 2 }), MAT.rock)
        -- The snow comes down the mountain when the land round it freezes.
        local cold = 0
        for k = 0, 5 do
            local n = self:cellAt(H.step(cell.c, cell.r, k))
            if n and D.TERRAIN[n.terrain].frozen then cold = cold + 1 end
        end
        local line = cold >= 2 and (cold >= 4 and 0.05 or 0.3) or 0.6
        main.snow = top + h * line
        local roll = grain(cell.id, 3, 30)
        if roll > 0.3 then
            local side = roll > 0.65 and 1 or -1
            local sx, sz = cell.x - side * 6, cell.z + 3
            local h2 = h * (0.4 + grain(cell.id, 5, 30) * 0.25)
            local second = add(Sh.peak(ring(sx, sz, H.R * (wide - 0.37), 32), top, { sx - side * 1.5, top + h2, sz }), MAT.rock)
            second.snow = top + h2 * (line + 0.1)
        end
    end

    if cell.terrain == "marsh" and not cell.city then
        -- Pools standing in the marsh, and clumps of reeds among them.
        for n, p in ipairs(scatter(cell, 7, 3, 66)) do
            local x, z = p[1], p[2]
            if n % 3 ~= 0 then
                local r = 2 + grain(x, z, 67) * 1.6
                add(Sh.ell(x, top - 0.3, z, r * 1.3, 0.5, r), MAT.pool).join = "pools"
            else
                for m = 0, 2 do
                    local h = 1.8 + grain(x + m, z, 55) * 1.4
                    local tuft = add(Sh.ell(x + (m - 1) * 1.4, top + h * 0.35, z + (m % 2) * 0.8, 1.1, h, 0.8), MAT.reed)
                    tuft.heads, tuft.join = top + h * 1.05, "reeds"
                end
            end
        end
    end
    if cell.flood then
        -- The water lying over it all, up to the trees' knees, the sheaves'
        -- ears and a farm's walls, into the river.
        local slab = hexPrism(cell.x, cell.z, top + 0.8, { [0] = 0.05, 0.05, 0.05, 0.05, 0.05, 0.05 })
        slab.planes[#slab.planes] = { 0, -1, 0, -(top - 0.3) }
        slab.box[3] = top - 0.3
        add(slab, MAT.flood)
    end

    if cell.feature == "forest" and not cell.city then
        -- Burning, the crowns go to charcoal.
        local crown, trunk = cell.fire and MAT.charTree or MAT.tree, cell.fire and MAT.char or MAT.trunk
        -- Snow on the boughs, or a rime on them (src/frost.lua).
        if cell.terrain == "snow" then crown = MAT.snowTree elseif cell.terrain == "tundra" then crown = MAT.rimeTree end
        local pts = scatter(cell, cell.elev == "hills" and 4 or 5, 3.5, 40)
        for n, p in ipairs(pts) do
            local x, z = p[1], p[2]
            local g = top + (cell.elev == "hills" and 1 or 0)
            local tall = 0.85 + grain(x, z, 41) * 0.35
            add(Sh.seg(x, g - 0.5, z, x, g + 3 * tall, z, 0.9), trunk)
            if cell.elev == "hills" or (cell.terrain == "plains" and n % 2 == 0) then
                -- A pine: two tiers of needles.
                add(Sh.pyramid(6, x, g + 2 * tall, z, 4 * tall, 6 * tall, 0, 0.3), crown)
                add(Sh.pyramid(6, x, g + 5 * tall, z, 3 * tall, 5 * tall, 0, 0.8), crown)
            else
                add(Sh.ell(x, g + 5.5 * tall, z, 3.8 * tall, 3.6 * tall, 3.8 * tall), crown)
            end
        end
    elseif cell.slid and not cell.city then
        -- A forest the quake brought down off the hill: trunks lying every
        -- way, their roots torn up, and rocks come down with them.
        local pts = scatter(cell, 5, 3.5, 40)
        for n, p in ipairs(pts) do
            local x, z = p[1], p[2]
            local g = top + (cell.elev == "hills" and 1 or 0)
            if n % 2 == 1 then
                local a = grain(x, z, 189) * math.pi
                local dx, dz = math.cos(a) * 3, math.sin(a) * 3
                add(Sh.seg(x - dx, g + 0.5, z - dz, x + dx, g + 0.7, z + dz, 0.6), MAT.trunk)
                add(Sh.ell(x - dx, g + 0.8, z - dz, 1, 1.1, 1), MAT.trunk)
            else
                add(Sh.ell(x, g + 0.6, z, 1.6, 1.2, 1.4), MAT.stone)
            end
        end
    elseif cell.burntForest and not cell.city then
        -- What the fire left of a forest: stumps where the trees stood, a
        -- bare snag or two still standing, a trunk fallen.
        local pts = scatter(cell, cell.elev == "hills" and 4 or 5, 3.5, 40)
        for n, p in ipairs(pts) do
            local x, z = p[1], p[2]
            local g = top + (cell.elev == "hills" and 1 or 0)
            local tall = 0.85 + grain(x, z, 41) * 0.35
            if n % 3 == 1 then
                -- A snag, leaning, with a broken limb.
                local lx, lz = (grain(x, z, 95) - 0.5) * 1.6, (grain(z, x, 96) - 0.5) * 1.2
                add(Sh.seg(x, g - 0.5, z, x + lx, g + 5.5 * tall, z + lz, 0.6), MAT.char)
                add(Sh.seg(x + lx * 0.5, g + 3 * tall, z + lz * 0.5, x + lx * 0.5 + 1.6, g + 4.2 * tall, z + lz * 0.5, 0.35),
                    MAT.char)
            elseif n % 3 == 2 then
                -- Fallen, along the ground.
                local a = grain(x, z, 97) * math.pi
                local dx, dz = math.cos(a) * 2.6 * tall, math.sin(a) * 2.6 * tall
                add(Sh.seg(x - dx, g + 0.5, z - dz, x + dx, g + 0.6, z + dz, 0.55), MAT.char)
            else
                add(Sh.seg(x, g - 0.5, z, x, g + 1.1 * tall, z, 0.85), MAT.char)
            end
        end
    end

    if river and cell.city then
        -- A city bridges the rivers by it: a deck of planks across, railed,
        -- on a trestle in the water.
        for k = 0, 5 do
            local e = river[k]
            if e then
                local n = self:cellAt(H.step(cell.c, cell.r, k))
                local deck = max(top, n and n.top or top) + 0.4
                local bank = bankOf(e)
                local a = math.rad(60 * k)
                local cx, cz = alongEdge(cell, k, 0, 0)
                local span = bank * 2 + 3.4
                local across = { math.cos(a), math.sin(a) }
                local b = add(Sh.box(cx, deck - 0.6, cz, span, 3.6, 0.6, -a), MAT.plank)
                b.across, b.join = across, "bridge" .. k
                local tx, tz = -across[2], across[1]
                for side = -1, 1, 2 do
                    local rx, rz = cx + tx * side * 1.6, cz + tz * side * 1.6
                    local rail = add(Sh.box(rx, deck + 0.6, rz, span - 1.2, 0.35, 0.35, -a), MAT.plank)
                    rail.across, rail.join = across, "bridge" .. k
                    -- Posts up to the rail at either end, and piles down
                    -- into the water mid-stream.
                    for along = -1, 1, 2 do
                        local px, pz = rx + across[1] * along * (span / 2 - 0.8), rz + across[2] * along * (span / 2 - 0.8)
                        add(Sh.seg(px, deck - 0.2, pz, px, deck + 1.2, pz, 0.35), MAT.plank).join = "bridge" .. k
                    end
                    add(Sh.seg(rx, e.level - 0.5, rz, rx, deck - 0.4, rz, 0.45), MAT.trunk).join = "bridge" .. k
                end
            end
        end
    end
    if river and not cell.city and cell.elev ~= "mountain" and cell.feature ~= "forest" then
        -- Reeds in clumps along some of the banks, their heads dark.
        for k = 0, 5 do
            local e = river[k]
            if e then
                local bank = bankOf(e)
                for q = 1, 2 do
                    if grain(cell.id, k * 7 + q, 50) > 0.45 then
                        local u = (grain(cell.id, k * 7 + q, 51) - 0.5) * 9
                        local bx, bz = alongEdge(cell, k, bank + 1.4, u)
                        for m = 0, 1 + floor(grain(bx, bz, 52) * 2) do
                            local x0 = bx + (m - 1) * 2.2 * -math.sin(math.rad(60 * k)) + (grain(bx, m, 53) - 0.5)
                            local z0 = bz + (m - 1) * 2.2 * math.cos(math.rad(60 * k)) + (grain(bz, m, 54) - 0.5)
                            local h = 1.8 + grain(bx + m, bz, 55) * 1.2
                            local tuft = add(Sh.ell(x0, top + h * 0.35, z0, 1.3, h, 0.9), MAT.reed)
                            tuft.heads, tuft.join = top + h * 1.05, "reeds"
                        end
                    end
                end
            end
        end
    end

    if cell.city then return out end
    if pit then
        -- The rim the stone threw up round where it fell: a ring of low
        -- mounds of the ground's own earth, kept off a river's bank; and
        -- the stone itself in the middle, or the star iron it was.
        local deep = (cell.sunk or 0) >= 2
        local n = deep and 11 or 8
        local r = H.APOTHEM - (deep and 2.4 or 3)
        local mound = cell.elev == "mountain" and MAT.rock or MOUND[soil]
        for k = 0, n - 1 do
            local a = (k + grain(cell.id, k, 76) * 0.4) / n * 2 * math.pi
            local x, z = cell.x + math.cos(a) * r, cell.z + math.sin(a) * r * 0.95
            if not nearRiver(cell, x, z, 1.6) then
                local w = (deep and 2.6 or 2) * (0.8 + grain(cell.id, k, 77) * 0.4)
                add(Sh.ell(x, top - 0.2, z, w, (deep and 1.7 or 1.1) * (0.8 + grain(k, cell.id, 78) * 0.4), w * 0.8), mound)
            end
        end
        local ground = top + (cell.elev == "hills" and 1 or 0)
        if cell.resource == "iron" then
            for k, p in ipairs({ { 0, 0, 1.5, 2.6 }, { 1.7, 0.9, 1, 1.6 }, { -1.4, 1.1, 0.9, 1.3 } }) do
                add(Sh.pyramid(5, cell.x + p[1], ground - 0.4, cell.z + p[2], p[3], p[4], 0, grain(cell.id, k, 79) * 3),
                    cell.glow and MAT.hotstone or MAT.iron)
            end
        else
            add(Sh.ell(cell.x, ground + 0.2, cell.z, 1.5, 1.1, 1.3), cell.glow and MAT.hotstone or MAT.starstone)
        end
    end
    if cell.resource == "wheat" then
        -- Two low plots of grain in rows, and between and round them a stand
        -- of it, clump by clump, inked only round its outside. All along
        -- one of three ways, by the hex (none end on, where a plot would
        -- look a crate).
        local a = math.rad(({ 0, 30, -30 })[cell.id % 3 + 1])
        local ca, sa = math.cos(a), math.sin(a)
        local function at(u, v) return cell.x + u * ca - v * sa, cell.z + u * sa + v * ca end
        local plots = { { -2.2, -2.6, 5.4 }, { 2.4, 2.4, 4.4 } }
        for _, q in ipairs(plots) do
            local x, z = at(q[1], q[2])
            add(Sh.box(x, top, z, q[3], 3.6, 1.6, -a), MAT.plot)
        end
        for row = -4, 4 do
            for k = -4, 4 do
                local u, v = k * 2.1 + (row % 2) * 1.05, row * 1.9
                local clear = true
                for _, q in ipairs(plots) do
                    if math.abs(u - q[1]) < q[3] / 2 + 1.1 and math.abs(v - q[2]) < 2.9 then clear = false end
                end
                local x, z = at(u, v)
                if clear and H.inset(x, z, cell.x, cell.z) > 4 and not nearRiver(cell, x, z, 1.4) then
                    add(Sh.ell(x, top + 0.3, z, 1.3, 1.4, 1.3), MAT.wheat).join = "wheat"
                end
            end
        end
    elseif cell.resource == "stone" then
        for n, p in ipairs(scatter(cell, 3, 4, 60)) do
            local r = n == 1 and 2.6 or 1.8
            add(Sh.ell(p[1], top + (cell.elev == "hills" and 1.5 or 0.8), p[2], r, r * 0.8, r), MAT.stone)
        end
    elseif cell.resource == "gems" then
        for _, p in ipairs(scatter(cell, 2, 5, 70)) do
            add(Sh.pyramid(4, p[1], top + 2.2, p[2], 1.6, 3, 0, 0.4), MAT.gem)
            local low = Sh.pyramid(4, p[1], top + 2.2, p[2], 1.6, 2, 0, 0.4)
            low.at = T.Affine.mul(T.Affine.move(p[1], 2 * (top + 2.2), p[2]), T.Affine.scale(1, -1, 1),
                T.Affine.move(-p[1], 0, -p[2]), low.at)
            add(low, MAT.gem)
        end
    end
    return out
end

--- the picture --------------------------------------------------------------------

function World.new(game)
    local self = setmetatable({}, World)
    self.game = game
    self.cells = game.cells
    self.cols, self.rows = game.cols, game.rows
    self.X, self.Z = H.size(self.cols, self.rows)
    local i0, i1, j0, j1 = T.screenBox(0, self.X, BOTTOM, 40, 0, self.Z)
    self.i0, self.j0 = floor(i0) - 6, floor(j0) - 6
    self.w, self.h = ceil(i1) - self.i0 + 6, ceil(j1) - self.j0 + 6
    self.solids, self.byCell = {}, {}
    self.nextPart = 1
    for _, cell in ipairs(self.cells) do self:addCell(cell) end
    return self
end

function World:cellAt(c, r)
    if c < 0 or r < 0 or c >= self.cols or r >= self.rows then return nil end
    return self.cells[r * self.cols + c + 1]
end

function World:addCell(cell)
    local list = self:hexSolids(cell)
    -- Solids that `join` are one part, so not inked where they meet.
    local joined = {}
    for _, s in ipairs(list) do
        -- All the rivers' water is one part, so no ink where hexes meet in it.
        if s.riverPart then
            if not self.riverPart then
                self.riverPart = self.nextPart
                self.nextPart = self.nextPart % 32000 + 1
            end
            s.join = nil
        end
        s.part = s.riverPart and self.riverPart or (s.join and joined[s.join])
        if not s.part then
            s.part = self.nextPart
            self.nextPart = self.nextPart % 32000 + 1
            if s.join then joined[s.join] = s.part end
        end
        T.prepare(s)
        self.solids[#self.solids + 1] = s
        if self.bins then self:binOne(s) end
    end
    self.byCell[cell.id] = list
    -- Land gone under the sea, or come out of it: how far every shore is
    -- from the land is found again.
    local water = D.TERRAIN[cell.terrain].water or false
    self.waterOf = self.waterOf or {}
    if self.waterOf[cell.id] ~= nil and self.waterOf[cell.id] ~= water then self.landNear, self.iceNear = nil, nil end
    self.waterOf[cell.id] = water
end

-- The screen box of a solid, in pixels of the picture.
function World:boxOf(s)
    local i0, i1, j0, j1 = T.screenBox(T.bounds(s))
    return floor(i0) - self.i0 - 1, ceil(i1) - self.i0 + 1, floor(j0) - self.j0 - 1, ceil(j1) - self.j0 + 1
end

-- Where each solid can land on the screen, binned in 16-pixel squares, so a
-- pixel only asks the handful that could be in it.
function World:binOne(s)
    local i0, i1, j0, j1 = self:boxOf(s)
    for by = max(0, floor(j0 / BIN)), min(self.bh - 1, floor(j1 / BIN)) do
        for bx = max(0, floor(i0 / BIN)), min(self.bw - 1, floor(i1 / BIN)) do
            local list = self.bins[by * self.bw + bx + 1]
            list[#list + 1] = s
        end
    end
end

-- The bins solid `s` was put in, into set `into`.
function World:binsOf(s, into)
    local i0, i1, j0, j1 = self:boxOf(s)
    for by = max(0, floor(j0 / BIN)), min(self.bh - 1, floor(j1 / BIN)) do
        for bx = max(0, floor(i0 / BIN)), min(self.bw - 1, floor(i1 / BIN)) do
            into[by * self.bw + bx + 1] = true
        end
    end
end

function World:bin()
    self.bw, self.bh = ceil(self.w / BIN), ceil(self.h / BIN)
    self.bins = {}
    for n = 1, self.bw * self.bh do self.bins[n] = {} end
    for _, s in ipairs(self.solids) do self:binOne(s) end
end

-- Traces the pixels from (i0, j0) to (i1, j1) of the picture. `yield` is told
-- each few rows done. `again`: the picture is being traced again where the
-- land changed, so the hex under each pixel on the fog's level, which
-- never changes, is not found again.
function World:trace(i0, j0, i1, j1, yield, again)
    local b = self.buf
    local w = self.w
    local HIT = T.HIT
    for pj = j0, j1 do
        for pi = i0, i1 do
            local si, sj = self.i0 + pi + 0.5, self.j0 + pj + 0.5
            local ox, oy, oz = T.origin(si, sj, BACK)
            local bt, best, nx, ny, nz, ux, uy, uz = math.huge, nil, 0, 1, 0, 0, 0, 0
            for _, s in ipairs(self.bins[floor(pj / BIN) * self.bw + floor(pi / BIN) + 1]) do
                if not s.dead then
                    local t, ax, ay, az, lx, ly, lz = HIT[s.kind](s, ox, oy, oz)
                    if t and t < bt then
                        bt, best, nx, ny, nz, ux, uy, uz = t, s, ax, ay, az, lx, ly, lz
                    end
                end
            end
            local n = pj * w + pi
            -- Where the ray meets the fog's level: the hex shown there when the
            -- one traced is not known yet.
            if not again then
                local fx, fz = T.onLevel(si, sj, FLAT)
                local fc, fr = H.at(fx, fz)
                local flat = self:cellAt(fc, fr)
                b.flat[n] = flat and flat.id or 0
                b.flatEdge[n] = flat and H.inset(fx, fz, flat.x, flat.z) < 0.8 and 1 or 0
            end
            if best then
                local x, y, z = ox + T.DX * bt, oy + T.DY * bt, oz + T.DZ * bt
                local m = best.mat
                local r = m.ramp
                local key, lev = T.shade(r, nx, ny, nz)
                if m.print then
                    best.ux, best.uy, best.uz = ux, uy, uz
                    local k = m.print(best, x, y, z, nx, ny, nz, lev)
                    if type(k) == "table" then
                        r = k
                        key, lev = T.shade(r, nx, ny, nz)
                    elseif k then
                        key, lev = k, 0
                    end
                end
                b.raw[n], b.lev[n], b.shd[n] = key, lev, r[4]
                b.part[n], b.mat[n] = best.part, m.id
                b.dep[n] = BACK - bt
                b.dif[n] = T.diffuse(nx, ny, nz)
                b.nx[n], b.ny[n], b.nz[n] = nx, ny, nz
                b.cell[n] = best.cell
                b.wx[n], b.wy[n], b.wz[n] = x, y, z
                b.up[n] = ny > 0.7 and 1 or 0
                local top = best.prism and ny > 0.99
                b.edge[n] = top and H.inset(x, z, best.cellRef.x, best.cellRef.z) < 0.8 and 1 or 0
                -- What the wind does to it, for src/ui/sea.lua: a tree's crown
                -- and a sheaf sway, by how high above the ground they are, in
                -- sixteenths; grass and dry grass ripple; the heat shimmers
                -- over sand.
                local kind, sway = LAND.other, 0
                if m == MAT.river then
                    -- The river: which way it runs, in 64ths of a turn, and
                    -- whether this is falling water (1) or the churn at a
                    -- fall's foot (2). Its banks are only earth.
                    local f = best.flow
                    local turn = floor(math.atan2(f[2], f[1]) / (2 * math.pi) * 64 + 0.5) % 64
                    local sub = 0
                    if ny < 0.6 then sub = best.falls and 1 or -1
                    elseif best.foot and (x - best.foot[1]) ^ 2 + (z - best.foot[2]) ^ 2 < best.churn then sub = 2 end
                    if sub >= 0 then kind, sway = LAND.river, turn * 4 + sub end
                elseif m == MAT.pool and ny > 0.8 then
                    kind = LAND.pool
                elseif m == MAT.flood and ny > 0.8 then
                    -- A flood: how far the dry land is, in quarter units.
                    kind = LAND.flood
                    sway = max(1, min(255, floor(self:dryDistance(best.cellRef, x, z) * 4 + 0.5)))
                elseif m == MAT.tree or m == MAT.snowTree or m == MAT.rimeTree or m.id == MAT.wheat.id or m == MAT.reed then
                    local cell = best.cellRef
                    local ground = cell.top + ((m ~= MAT.wheat and m ~= MAT.reed and cell.elev == "hills") and 1 or 0)
                    local crown = m == MAT.tree or m == MAT.snowTree or m == MAT.rimeTree
                    kind = crown and LAND.crown or LAND.sheaf
                    sway = max(0, min(255, floor((y - ground) * 16)))
                elseif ny > 0.9 and (m.id == MAT.grass.id or m.id == MAT.grass.id + 20 or m == MAT.marsh) then
                    kind = LAND.grass
                elseif ny > 0.9 and (m.id == MAT.plains.id or m.id == MAT.plains.id + 20
                    or m.id == MAT.tundra.id or m.id == MAT.tundra.id + 20) then
                    kind = LAND.plains
                elseif ny > 0.9 and (m.id == MAT.snow.id or m.id == MAT.snow.id + 20) then
                    kind = LAND.snow
                elseif ny > 0.9 and (m == MAT.ice or m == MAT.iceblock) then
                    kind = LAND.ice
                elseif ny > 0.9 and (m.id == MAT.desert.id or m.id == MAT.desert.id + 20
                    or m.id == MAT.scorched.id or m.id == MAT.scorched.id + 20 or m == MAT.saltflat) then
                    kind = LAND.desert
                end
                b.kind[n], b.sway[n] = kind, sway
                -- The sea's top, for src/sea.lua to set moving: which water,
                -- and how far the land is, in quarter units up to 63.
                if top and (m == MAT.ocean or m == MAT.coast) then
                    b.sea[n] = m == MAT.ocean and 1 or 2
                    b.shore[n] = min(255, floor(self:shoreDistance(best.cellRef, x, z) * 4 + 0.5))
                    -- By the ice (src/frost.lua): slush and floes, no surf.
                    local ice = self:iceDistance(best.cellRef, x, z)
                    if ice < 10 then b.sea[n], b.shore[n] = LAND.slush, floor(ice * 4 + 0.5) end
                else
                    b.sea[n] = 0
                end
            else
                b.raw[n], b.cell[n], b.edge[n], b.up[n], b.sea[n], b.kind[n] = 0, 0, 0, 0, 0, 0
                b.dep[n] = -1e9
                b.wy[n] = -1e9
            end
        end
        if yield and pj % 4 == 0 then yield((pj - j0) / max(1, j1 - j0)) end
    end
end

-- Traces the whole map. `yield`, if given, is told the progress (0..1)
-- every few rows -- coroutine.yield, so the load screen can say how far
-- along it is.
function World:paint(yield)
    local w, h = self.w, self.h
    local b = T.buffer(w, h)
    b.open = true
    b.cell = ffi.new("int16_t[?]", w * h)
    b.flat = ffi.new("int16_t[?]", w * h)
    b.edge = ffi.new("uint8_t[?]", w * h)
    b.flatEdge = ffi.new("uint8_t[?]", w * h)
    b.wx = ffi.new("float[?]", w * h)
    b.wy = ffi.new("float[?]", w * h)
    b.wz = ffi.new("float[?]", w * h)
    b.up = ffi.new("uint8_t[?]", w * h)
    b.sea = ffi.new("uint8_t[?]", w * h)
    b.shore = ffi.new("uint8_t[?]", w * h)
    b.kind = ffi.new("uint8_t[?]", w * h)
    b.sway = ffi.new("uint8_t[?]", w * h)
    b.inked = ffi.new("uint8_t[?]", w * h)
    self.buf = b
    self:bin()
    self:trace(0, 0, w - 1, h - 1, yield)
    T.finish(b, 1.2)
    self.key, self.dep, self.cell, self.up = b.key, b.dep, b.cell, b.up
    self.wx, self.wy, self.wz = b.wx, b.wy, b.wz
    self.data = love.image.newImageData(w, h, "rgba8")
    self.px = ffi.cast("uint8_t*", self.data:getFFIPointer())
    self.image = love.graphics.newImage(self.data)
    self.image:setFilter("nearest", "nearest")
    -- Beside it, a picture of what moves for src/ui/sea.lua: red what it is
    -- (1 ocean, 2 coast, or a kind of land from LAND; 0 unseen, or ink on
    -- the water), green how far the land is from water or how high a crown
    -- stands, blue how many steps darker the fog and the grid lay it, alpha
    -- the key laid there.
    self.maskData = love.image.newImageData(w, h, "rgba8")
    self.mpx = ffi.cast("uint8_t*", self.maskData:getFFIPointer())
    self.maskImage = love.graphics.newImage(self.maskData)
    self.maskImage:setFilter("nearest", "nearest")
    -- And two more for the light of the hour (src/ui/daylight.lua): each
    -- pixel's normal, and how near it is.
    self.shapeData = love.image.newImageData(w, h, "rgba8")
    self.spx = ffi.cast("uint8_t*", self.shapeData:getFFIPointer())
    self.nearData = love.image.newImageData(w, h, "rgba8")
    self.npx = ffi.cast("uint8_t*", self.nearData:getFFIPointer())
    self:shape(0, 0, w - 1, h - 1)
    self.shapeImage = love.graphics.newImage(self.shapeData)
    self.shapeImage:setFilter("nearest", "nearest")
    self.nearImage = love.graphics.newImage(self.nearData)
    self.nearImage:setFilter("nearest", "nearest")
end

-- How near is laid in the near picture: in 32nds of a unit, from 64 behind
-- the room's origin, in two bytes.
World.NEAR_FROM, World.NEAR_STEPS = -64, 32

-- The shape picture and the near picture from (i0, j0) to (i1, j1). Shape:
-- the normal in red, green and blue (each -1..1 laid as 0..1), and alpha 1
-- where the light may change the pixel (not where the ink was laid, nor
-- where nothing is). Near: red and green how near, high byte first, as
-- NEAR_FROM and NEAR_STEPS say; alpha 0 where nothing is.
function World:shape(i0, j0, i1, j1)
    local b, w = self.buf, self.w
    local spx, npx = self.spx, self.npx
    local key, raw, inked, dep, nx, ny, nz = b.key, b.raw, b.inked, b.dep, b.nx, b.ny, b.nz
    local from, steps = World.NEAR_FROM, World.NEAR_STEPS
    for j = j0, j1 do
        for i = i0, i1 do
            local n = j * w + i
            local p = n * 4
            if key[n] == 0 then
                spx[p], spx[p + 1], spx[p + 2], spx[p + 3] = 128, 128, 128, 0
                npx[p], npx[p + 1], npx[p + 2], npx[p + 3] = 0, 0, 0, 0
            else
                spx[p] = floor((nx[n] * 0.5 + 0.5) * 255 + 0.5)
                spx[p + 1] = floor((ny[n] * 0.5 + 0.5) * 255 + 0.5)
                spx[p + 2] = floor((nz[n] * 0.5 + 0.5) * 255 + 0.5)
                spx[p + 3] = (raw[n] == 0 or inked[n] == 1) and 0 or 255
                local c = max(1, min(65535, floor((dep[n] - from) * steps + 0.5)))
                npx[p], npx[p + 1], npx[p + 2], npx[p + 3] = floor(c / 256), c % 256, 0, 255
            end
        end
    end
end

-- How far room point (x, z) on water hex `cell` is from the nearest land, as
-- far as two hexes out; further than that is open sea (64).
function World:shoreDistance(cell, x, z)
    -- Water in a land hex (the sea come into a rift or a fault): the shore
    -- close by on every side.
    if not D.TERRAIN[cell.terrain].water then return 2 end
    self.landNear = self.landNear or {}
    local near = self.landNear[cell.id]
    if not near then
        near = {}
        for dr = -2, 2 do
            for dc = -3, 3 do
                local n = self:cellAt(cell.c + dc, cell.r + dr)
                if n and not D.TERRAIN[n.terrain].water and H.distance(cell.c, cell.r, n.c, n.r) <= 2 then
                    near[#near + 1] = n
                end
            end
        end
        self.landNear[cell.id] = near
    end
    local d = 64
    for k = 1, #near do d = min(d, hexDistance(near[k], x, z)) end
    return max(0, d)
end

-- How far room point (x, z) on water hex `cell` is from the sea's ice
-- beside it (src/frost.lua); 64 with none beside it.
function World:iceDistance(cell, x, z)
    self.iceNear = self.iceNear or {}
    local near = self.iceNear[cell.id]
    if not near then
        near = {}
        for k = 0, 5 do
            local n = self:cellAt(H.step(cell.c, cell.r, k))
            if n and D.TERRAIN[n.terrain].sea then near[#near + 1] = n end
        end
        self.iceNear[cell.id] = near
    end
    local d = 64
    for k = 1, #near do d = min(d, hexDistance(near[k], x, z)) end
    return max(0, d)
end

-- How far room point (x, z) on flooded hex `cell` is from the dry land
-- beyond its edges (not another flood's, nor the water), up to 63.
function World:dryDistance(cell, x, z)
    local d = 63
    for k = 0, 5 do
        local n = self:cellAt(H.step(cell.c, cell.r, k))
        if n and not n.flood and not D.TERRAIN[n.terrain].water then
            local a = math.rad(60 * k)
            d = min(d, H.APOTHEM - ((x - cell.x) * math.cos(a) + (z - cell.z) * math.sin(a)))
        end
    end
    return max(0, d)
end

-- One hex has changed (a city cleared its forest): build its solids again
-- and trace its corner of the picture again.
function World:refresh(cellId)
    self:refreshAll({ cellId })
end

-- Hexes in list `ids` to be built again, a few each frame (World:work)
-- rather than all at once: a turn of the cataclysm changes dozens, and
-- tracing them all in one frame stopped the game for a moment.
function World:queue(ids)
    self.pending = self.pending or {}
    self.pendingSet = self.pendingSet or {}
    for _, id in ipairs(ids) do
        if not self.pendingSet[id] then
            self.pendingSet[id] = true
            self.pending[#self.pending + 1] = id
        end
    end
end

-- Builds again as many of the hexes queued as fit in about `budget` seconds
-- (by how long a hex has taken so far), at least one; all of them without
-- a budget. `now` tells the time in seconds.
function World:work(budget, now)
    local pending = self.pending
    if not pending or #pending == 0 then return end
    local n = #pending
    if budget then n = max(1, min(n, floor(budget / (self.perHex or 0.01)))) end
    local ids = {}
    for k = 1, n do
        ids[k] = pending[k]
        self.pendingSet[pending[k]] = nil
    end
    local rest = {}
    for k = n + 1, #pending do rest[#rest + 1] = pending[k] end
    self.pending = rest
    local t0 = now and now()
    self:refreshAll(ids)
    if t0 then
        local each = (now() - t0) / n
        self.perHex = self.perHex and self.perHex * 0.7 + each * 0.3 or each
    end
end

-- Any hexes still waiting to be built again?
function World:busy() return self.pending ~= nil and #self.pending > 0 end

-- Builds every hex in the list again and traces each one's corner of the
-- picture, then hands the images over once: what a turn of the cataclysm
-- changes, all together.
function World:refreshAll(ids)
    if #ids == 0 then return end
    local boxes, stale = {}, {}
    for _, cellId in ipairs(ids) do
        local i0, i1, j0, j1 = math.huge, -math.huge, math.huge, -math.huge
        local function grow(s)
            local a, b, c, d = self:boxOf(s)
            i0, i1, j0, j1 = min(i0, a), max(i1, b), min(j0, c), max(j1, d)
        end
        for _, s in ipairs(self.byCell[cellId] or {}) do
            s.dead = true
            grow(s)
            self:binsOf(s, stale)
        end
        self:addCell(self.cells[cellId])
        for _, s in ipairs(self.byCell[cellId]) do grow(s) end
        boxes[#boxes + 1] = { max(0, i0 - 1), max(0, j0 - 1), min(self.w - 1, i1 + 1), min(self.h - 1, j1 + 1) }
    end
    -- Dead solids leave the list, and the bins they were in, so a hex
    -- changed turn after turn (a crater struck again, the frost) does not
    -- leave every pixel over it asking more and more of them.
    local keep = {}
    for _, s in ipairs(self.solids) do if not s.dead then keep[#keep + 1] = s end end
    self.solids = keep
    for n in pairs(stale) do
        local list, live = self.bins[n], {}
        for _, s in ipairs(list) do if not s.dead then live[#live + 1] = s end end
        self.bins[n] = live
    end
    for _, b in ipairs(boxes) do self:trace(b[1], b[2], b[3], b[4], nil, true) end
    for _, b in ipairs(boxes) do T.finish(self.buf, 1.2, b[1] - 1, b[2] - 1, b[3] + 1, b[4] + 1) end
    local u = { math.huge, math.huge, -1, -1 }
    for _, b in ipairs(boxes) do
        local i0, j0, i1, j1 = max(0, b[1] - 1), max(0, b[2] - 1), min(self.w - 1, b[3] + 1), min(self.h - 1, b[4] + 1)
        self:shape(i0, j0, i1, j1)
        u[1], u[2], u[3], u[4] = min(u[1], i0), min(u[2], j0), max(u[3], i1), max(u[4], j1)
    end
    self:upload(self.shapeImage, self.shapeData, self.spx, u)
    self:upload(self.nearImage, self.nearData, self.npx, u)
    -- Only these corners of the picture need laying again: as far as the
    -- creases and the ink were laid again, a pixel past where they looked.
    self.redo = self.redo or {}
    for _, b in ipairs(boxes) do
        self.redo[#self.redo + 1] = { max(0, b[1] - 2), max(0, b[2] - 2), min(self.w - 1, b[3] + 2), min(self.h - 1, b[4] + 2) }
    end
    self.dirty = true
    -- Counted, for what is found from the map (src/ui/wild.lua) and the
    -- light laid on it (src/ui/daylight.lua).
    self.version = (self.version or 0) + 1
end

-- The picture as the player knows the map: what they see as it is, what they
-- have seen a step darker, and what they never have as a drawn map on paper.
-- `grid`: a faint line round every hex.
--
-- A pixel depends only on how the player knows the hex traced there, so
-- after the first time only the pixels of hexes whose knowing has changed
-- (a unit's step reveals a few) are laid again, and the corners of the
-- picture traced again since (World:refreshAll). The whole of it again only
-- when the grid is turned on or off.
function World:build(explored, visible, grid)
    local w, h = self.w, self.h
    local ncell = #self.cells
    local shown = self.shown
    local full = not shown or self.shownGrid ~= grid
    if not shown then
        shown = ffi.new("uint8_t[?]", ncell + 1)
        self.shown, self.changed = shown, ffi.new("uint8_t[?]", ncell + 1)
        -- Each hex's box in the picture, found as it is laid.
        self.cbox = ffi.new("int16_t[?]", (ncell + 1) * 4)
        for id = 0, ncell do
            local q = id * 4
            self.cbox[q], self.cbox[q + 1], self.cbox[q + 2], self.cbox[q + 3] = 32767, -1, 32767, -1
        end
        self:grow(0, 0, w - 1, h - 1)
    end
    self.shownGrid = grid
    -- Which hexes the player knows otherwise than when last laid.
    local changed, list = self.changed, {}
    for id = 1, ncell do
        local now = visible[id] and 3 or explored[id] and 2 or 1
        if shown[id] ~= now then
            shown[id], changed[id] = now, 1
            list[#list + 1] = id
        else
            changed[id] = 0
        end
    end
    local redo = self.redo
    self.redo = nil
    -- The box round all that is laid, to hand over only that.
    local u = { math.huge, math.huge, -1, -1 }
    local function took(i0, j0, i1, j1)
        u[1], u[2], u[3], u[4] = min(u[1], i0), min(u[2], j0), max(u[3], i1), max(u[4], j1)
    end
    if full then
        for _, b in ipairs(redo or {}) do self:grow(b[1], b[2], b[3], b[4]) end
        self:lay(explored, visible, grid, 0, 0, w - 1, h - 1)
        took(0, 0, w - 1, h - 1)
    else
        -- The corners traced again first, so the boxes of the hexes in them
        -- are as they are now.
        for _, b in ipairs(redo or {}) do
            self:grow(b[1], b[2], b[3], b[4])
            self:lay(explored, visible, grid, b[1], b[2], b[3], b[4])
            took(b[1], b[2], b[3], b[4])
        end
        local box = self.cbox
        for _, id in ipairs(list) do
            local q = id * 4
            if box[q + 1] >= 0 then
                self:lay(explored, visible, grid, box[q], box[q + 2], box[q + 1], box[q + 3], changed)
                took(box[q], box[q + 2], box[q + 1], box[q + 3])
            end
        end
        if #list == 0 and not redo then
            self.dirty = false
            return
        end
    end
    if u[3] >= 0 then
        self:upload(self.image, self.data, self.px, u)
        self:upload(self.maskImage, self.maskData, self.mpx, u)
    end
    self.dirty = false
end

-- Hands box `u` ({ i0, j0, i1, j1 }) of picture `data` (its pixels at
-- `ptr`) over to `image`: only that box, unless it is most of the picture.
function World:upload(image, data, ptr, u)
    local w = self.w
    local i0, j0, i1, j1 = u[1], u[2], u[3], u[4]
    local rw, rh = i1 - i0 + 1, j1 - j0 + 1
    if rw * rh * 2 > w * self.h then
        image:replacePixels(data)
        return
    end
    local sub = love.image.newImageData(rw, rh, "rgba8")
    local sp = ffi.cast("uint8_t*", sub:getFFIPointer())
    for j = 0, rh - 1 do ffi.copy(sp + j * rw * 4, ptr + ((j0 + j) * w + i0) * 4, rw * 4) end
    image:replacePixels(sub, 1, 1, i0, j0)
    sub:release()
end

-- The box of each hex with pixels from (i0, j0) to (i1, j1) grown to take
-- them in.
function World:grow(i0, j0, i1, j1)
    local w, cell, box = self.w, self.cell, self.cbox
    for j = j0, j1 do
        for i = i0, i1 do
            local c = cell[j * w + i]
            if c ~= 0 then
                local q = c * 4
                if i < box[q] then box[q] = i end
                if i > box[q + 1] then box[q + 1] = i end
                if j < box[q + 2] then box[q + 2] = j end
                if j > box[q + 3] then box[q + 3] = j end
            end
        end
    end
end

-- Lays the pixels from (i0, j0) to (i1, j1) of the picture as the player
-- knows the map; with `only`, just those of the hexes it marks.
function World:lay(explored, visible, grid, i0, j0, i1, j1, only)
    local w = self.w
    local px, key, cell, edge, flat, flatEdge = self.px, self.key, self.cell, self.buf.edge, self.buf.flat, self.buf.flatEdge
    local mpx, sea, shore, raw = self.mpx, self.buf.sea, self.buf.shore, self.buf.raw
    local kind, sway = self.buf.kind, self.buf.sway
    local RGB8 = World.RGB8
    local DARK = T.DARKER
    local bg = IDX.o
    local PAPER, LINE, SPECK = IDX.c, IDX.t, IDX.s
    for j = j0, j1 do
        for i = i0, i1 do
            local n = j * w + i
            local c = cell[n]
            if not only or (c ~= 0 and only[c] == 1) then
                local k = key[n]
                local what, dark = 0, 0
                if k == 0 then
                    k = bg
                elseif not explored[c] then
                    local f = flat[n]
                    if f == 0 then k = bg
                    elseif flatEdge[n] == 1 then k = LINE
                    else
                        k = PAPER
                        if grain(i, j, 90) > 0.97 then k = SPECK end
                    end
                else
                    if grid and edge[n] == 1 and (i + j) % 2 == 0 then k, dark = DARK[k], dark + 1 end
                    if not visible[c] then k, dark = DARK[k], dark + 1 end
                    -- Water, but not where the ink has drawn the map's edge over it.
                    if sea[n] ~= 0 then what = key[n] == raw[n] and sea[n] or 0 else what = kind[n] end
                    -- The river moves only where neither ink nor a crease is on it.
                    if (what == LAND.river or what == LAND.flood or what == LAND.pool) and key[n] ~= raw[n] then
                        what = LAND.other
                    end
                end
                local rgb = RGB8[k]
                local p = n * 4
                px[p], px[p + 1], px[p + 2], px[p + 3] = rgb[1], rgb[2], rgb[3], 255
                mpx[p], mpx[p + 1], mpx[p + 2], mpx[p + 3] = what, sea[n] ~= 0 and shore[n] or sway[n], dark, k
            end
        end
    end
end

World.RGB8 = {}
for k, c in ipairs(T.RGB) do World.RGB8[k] = { floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5) } end

--- standing on it ------------------------------------------------------------------

-- Picture pixel of a room point, and its depth.
function World:toImage(x, y, z)
    local i, j, d = T.project(x, y, z)
    return i - self.i0, j - self.j0, d
end

-- The cell under picture pixel (i, j): the hex traced there, or nil.
function World:pick(i, j)
    i, j = floor(i), floor(j)
    if i < 0 or j < 0 or i >= self.w or j >= self.h then return end
    local c = self.cell[j * self.w + i]
    if c == 0 then
        local f = self.buf.flat[j * self.w + i]
        return f ~= 0 and self.cells[f] or nil
    end
    return self.cells[c]
end

-- The picture box of a hex's top: i0, i1, j0, j1.
function World:topBox(cell)
    local i0, i1, j0, j1 = T.screenBox(cell.x - H.APOTHEM, cell.x + H.APOTHEM, cell.top, cell.top, cell.z - H.R, cell.z + H.R)
    return floor(i0 - self.i0) - 1, ceil(i1 - self.i0) + 1, floor(j0 - self.j0) - 1, ceil(j1 - self.j0) + 1
end

return World
