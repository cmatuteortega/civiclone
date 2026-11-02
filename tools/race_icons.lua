-- An icon for each race (concepts/races.md), 32 by 32, made of the game's own
-- models: each one traced by the same tracer as the board, standing on a
-- little hex of its land, in the eight colours and nothing else.
--
--   luajit tools/race_icons.lua [dir]
--
-- writes dir/<race>.ppm for each race, and dir/races.ppm, all eight in a row.
--
-- The board's models are drawn at its scale, a city some fifty pixels across;
-- an icon is 32. So the models are traced afresh at the size the icon wants
-- (every part scaled before it is painted), not shrunk from a picture: each
-- keeps its one-pixel ink outline. What the tracer does not make, the board
-- draws a pixel at a time, and so does this: the flame (src/ui/fire.lua) and
-- the falling star (src/ui/sky.lua), at one moment of them.

package.path = "./?.lua;" .. package.path

local T = require "src.tracer"
local Sh = require "src.shapes"
local A = T.Affine
local IDX = T.IDX

local floor, sin, abs, max, min, sqrt = math.floor, math.sin, math.abs, math.max, math.min, math.sqrt
local SIZE = 32

-- Every part scaled by `scale` before it is painted, the models' too: they
-- paint through T.paint. src.models keeps what it has painted, so it is taken
-- up afresh for each icon at each scale.
local scale = 1
local paint = T.paint
T.paint = function(parts, edge)
    if scale ~= 1 then
        local m = A.scale(scale, scale, scale)
        for _, q in ipairs(parts) do q.at = A.mul(m, q.at or A.id()) end
    end
    return paint(parts, edge)
end
local function models()
    package.loaded["src.models"] = nil
    return require "src.models"
end

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

--- the ground under each ----------------------------------------------------------

local GROUND = {
    grass = { ramp = T.ramp("c", "k", "t", "n"), print = function(ux, uy, uz, lev, nx, ny)
        if ny < 0.6 then return floor(uy * 12) % 3 == 0 and IDX.n or IDX.t end
        if (floor(ux * 37) + floor(uz * 23)) % 13 == 0 then return IDX.t end
    end },
    hills = { ramp = T.ramp("c", "t", "k", "n"), print = function(ux, uy, uz, lev, nx, ny)
        if ny < 0.6 then return floor(uy * 9) % 3 == 0 and IDX.u or IDX.n end
        if (floor(ux * 29) + floor(uz * 17)) % 11 == 0 then return IDX.k end
    end },
    water = { ramp = T.ramp("n", "u", "u", "o"), print = function(ux, uy, uz, lev, nx, ny)
        if ny < 0.6 then return IDX.u end
        local r = sin(ux * 9 + uz * 4) + sin(uz * 12 - ux * 3.4)
        if abs(r - 1.0) < 0.12 then return IDX.t end
        if abs(r + 0.6) < 0.1 then return IDX.u end
        return IDX.n
    end },
    -- What the fire leaves: ash over burnt earth (src/world.lua).
    ash = { ramp = T.ramp("n", "u", "u", "o"), print = function(ux, uy, uz, lev, nx, ny)
        if ny < 0.6 then return floor(uy * 9) % 3 == 0 and IDX.o or IDX.u end
        local g = grain(floor(ux * 30), floor(uz * 30), 3)
        if g > 0.9 then return IDX.k end
        if g > 0.75 then return IDX.u end
    end },
}

-- A hex of ground `r` across its flats, `ht` deep, its top at y = 0.
local function hex(kind, r, ht)
    local g = GROUND[kind]
    local p = Sh.prism(6, 0, -ht, 0, r, ht, 0, 0)
    p.ramp, p.print = g.ramp, g.print
    return p
end

--- the canvas ----------------------------------------------------------------------

local W, key, dep = 192, {}, {}
local function clear()
    key, dep = {}, {}
    for n = 0, W * W - 1 do key[n], dep[n] = 0, -math.huge end
end
local function put(k, x, y, d)
    if k == 0 or x < 0 or y < 0 or x >= W or y >= W then return end
    local n = y * W + x
    if d == nil or d >= dep[n] - 0.6 then
        key[n] = k
        if d then dep[n] = d end
    end
end
-- Picture `pic` with the room point (x, y, z) at canvas pixel (ox, oy).
-- With `clip` ({ across, below }, in pixels) only what lies within `across`
-- either side of (ox, oy) and no further than `below` beneath it is laid:
-- one piece out of a picture of several.
local function stamp(pic, ox, oy, x, y, z, clip)
    local si, sj, d = T.project(x, y, z)
    local bi, bj = floor(ox + si) - pic.oi, floor(oy + sj) - pic.oj
    for pj = 0, pic.h - 1 do
        for pi = 0, pic.w - 1 do
            local n = pj * pic.w + pi
            local k = pic.key[n]
            local i, j = bi + pi, bj + pj
            if k ~= 0 and (not clip or (abs(i - ox) <= clip[1] and j - oy <= clip[2])) then
                put(k, i, j, d + pic.dep[n])
            end
        end
    end
end

--- what the board draws a pixel at a time ------------------------------------------

-- A flame, as src/ui/fire.lua draws one, at one moment: widest a little above
-- the root and up to a point, white at its heart, ragged at its edge, ringed
-- in ink. Its root at (si, sj).
local function flame(si, sj, tall, wide, seed)
    local shape = {}
    local rows = floor(tall + 0.5)
    for r = 0, rows do
        local f = r / max(tall, 1)
        local half = wide * 0.5 * (f < 0.2 and (0.75 + f * 1.25) or (1 - f) ^ 0.8 / 0.8 ^ 0.8) + 0.3
        local ci = si + sin(r * 0.7 + seed) * 0.8 * f
        local j = floor(sj - r)
        for i = floor(ci - half + 0.5), floor(ci + half - 0.5) do
            local u = abs(i + 0.5 - ci) / max(half, 0.5)
            if u < 0.8 or grain(i, j, seed) > f then
                local k = IDX.s
                if u < 0.45 and f < 0.6 then k = IDX.w
                elseif u < 0.8 and f < 0.85 then k = IDX.c end
                shape[#shape + 1] = { i, j, k }
            end
        end
    end
    local seen = {}
    for _, s in ipairs(shape) do seen[s[2] * 1000 + s[1]] = true end
    for _, s in ipairs(shape) do
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local i, j = s[1] + o[1], s[2] + o[2]
            if not seen[j * 1000 + i] then put(IDX.o, i, j) end
        end
    end
    for _, s in ipairs(shape) do put(s[3], s[1], s[2]) end
end

-- A falling star, as src/ui/sky.lua draws a stone coming down: white at the
-- head, the pale keys back along its tail, the head ringed in ink.
local function streak(x, y, dx, dy, len, w)
    local l = sqrt(dx * dx + dy * dy)
    dx, dy = dx / l, dy / l
    for s = len, 0, -1 do
        local f = s / len
        local px, py = x - dx * s, y - dy * s
        local half = (w - 1) * (1 - f) * 0.5
        local k = f < 0.25 and IDX.w or f < 0.6 and IDX.c or IDX.s
        if f < 0.85 or grain(s, 1, 5) > 0.5 then
            for o = -floor(half + 0.5), floor(half + 0.5) do
                put(k, floor(px - dy * o + 0.5), floor(py + dx * o + 0.5))
            end
        end
    end
    local r = max(1, floor(w / 2 + 0.5))
    for a = -r - 1, r + 1 do
        for b = -r - 1, r + 1 do
            local d = a * a + b * b
            if d <= (r + 1) * (r + 1) and d > r * r then put(IDX.o, floor(x) + a, floor(y) + b) end
        end
    end
    for a = -r, r do
        for b = -r, r do
            if a * a + b * b <= r * r then put(IDX.w, floor(x) + a, floor(y) + b) end
        end
    end
end

--- the races -----------------------------------------------------------------------

-- Each: what it stands on (ground, its radius and depth in room units, before
-- the icon's scale), what stands on it (`things(M)`: pictures and where, in
-- room units), the scale, anything drawn over (`after(ox, oy)`, the hex's
-- middle at canvas pixel ox, oy), and whether it is night.
local RACES = {
    { name = "hearthfolk", ground = "grass", r = 6, depth = 2, scale = 1.52,
        -- A homestead: the farmhouse under its thatch, the haystack beside
        -- it (M.farm, its walls left off).
        things = function(M)
            local open = { [0] = true, true, true, true, true, true }
            return { { M.farm(M.FARM_LAYOUTS[1], open), 3.6, 0, 6.1 } }
        end },
    { name = "moundfolk", ground = "hills", r = 5, depth = 2.5, scale = 1.52,
        -- The adit of a mine: a mound with a dark door propped in timber,
        -- out of M.mine, the ore heaped before it left off.
        things = function(M)
            return { { M.mine({ kind = "shaft", role = "workings", variant = 0 }), 6.79, 0, 3.92, clip = { 7, 5 } } }
        end },
    { name = "fenfolk", ground = "water", r = 3.4, depth = 1.2, scale = 2.32,
        -- A heron standing in the shallows, side on.
        things = function(M) return { { M.heron(3, 0), 0, 0, 0 } } end },
    { name = "nightborn", ground = "grass", r = 4.6, depth = 1.4, scale = 1.6, night = true,
        -- A wolf howling at night, under the moon.
        things = function(M) return { { M.beast("wolf", 0, M.BEAST_POSES.wolf.howl), 0, 0, 0 } } end,
        after = function()
            -- The moon, a crescent, in the corner.
            for j = 3, 10 do
                for i = 3, 10 do
                    local a = (i - 6.5) ^ 2 + (j - 6.5) ^ 2
                    local b = (i - 8.3) ^ 2 + (j - 5.5) ^ 2
                    if a <= 11 and b > 9 then put(a > 7 and IDX.s or IDX.c, i, j) end
                end
            end
        end },
    { name = "wildwardens", ground = "grass", r = 5.5, depth = 1.6, scale = 1.52,
        -- A bear, side on: what lives in the cave, kept.
        things = function(M) return { { M.beast("bear", 3, 0), 0, 0, 0 } } end },
    { name = "wayfarers", ground = "grass", r = 7, depth = 2, scale = 1.28,
        -- The settler's wagon, its ox in the traces: everything they own,
        -- on the road.
        things = function(M) return { { M.unit("settler", "light", 0, 0), 0, 0, 0 } } end },
    { name = "stargazers", ground = "hills", r = 4.5, depth = 2.5, scale = 1.28,
        -- Someone on a hill, and a star falling.
        things = function(M) return { { M.unit("scout", "light", 3, 0), 0, 0, 0 } } end,
        after = function() streak(24, 8, 1, 1, 10, 2) end },
    { name = "ashborn", ground = "ash", r = 6.5, depth = 1.6, scale = 1.44,
        -- Burnt ground, snags of what the fire left, and a fire burning.
        parts = function()
            local char = { ramp = T.ramp("n", "u", "o", "o") }
            local function seg(...) local p = Sh.seg(...); p.ramp = char.ramp; return p end
            return {
                seg(-4.5, -0.5, -2, -5.2, 7, -2.5, 0.75),
                seg(-4.9, 4.2, -2.2, -3.0, 5.6, -2.2, 0.4),
                seg(4.4, -0.5, -1.5, 5.4, 6, -1.0, 0.7),
                seg(1, 0.4, 3.5, 5, 0.6, 2.5, 0.65),
                seg(-3, -0.5, 3.5, -3, 1.3, 3.5, 0.9),
            }
        end,
        after = function(ox, oy)
            flame(ox - 1, oy + 3, 16, 9, 3)
            put(IDX.s, ox + 6, oy - 14); put(IDX.c, ox - 6, oy - 16); put(IDX.s, ox + 3, oy - 18)
        end },
}

--- an icon ---------------------------------------------------------------------------

local BG, NIGHT_BG = IDX.c, IDX.n

local function icon(race, s)
    s = s or race.scale
    scale = s
    local M = models()
    clear()
    local ox, oy = W / 2, W / 2
    local ground = { hex(race.ground, race.r, race.depth) }
    if race.parts then for _, p in ipairs(race.parts()) do ground[#ground + 1] = p end end
    stamp(T.paint(ground, 1.5), ox, oy, 0, 0, 0)
    for _, t in ipairs(race.things and race.things(M) or {}) do
        stamp(t[1], ox, oy, t[2] * s, t[3] * s, t[4] * s, t.clip and { t.clip[1] * s, t.clip[2] * s })
    end
    -- Its middle: the box round what is drawn.
    local i0, j0, i1, j1 = W, W, -1, -1
    for j = 0, W - 1 do
        for i = 0, W - 1 do
            if key[j * W + i] ~= 0 then i0, j0, i1, j1 = min(i0, i), min(j0, j), max(i1, i), max(j1, j) end
        end
    end
    -- Too big for the badge: a little smaller, and again.
    if i1 - i0 + 1 > SIZE - 5 or j1 - j0 + 1 > SIZE - 5 then return icon(race, s * 0.96) end
    local out = {}
    local dx, dy = floor((SIZE - (i1 - i0 + 1)) / 2) - i0, floor((SIZE - (j1 - j0 + 1)) / 2 + 0.5) - j0
    -- The badge: paper (or the night) in a frame of ink, its corners cut.
    local bg = race.night and NIGHT_BG or BG
    for j = 0, SIZE - 1 do
        for i = 0, SIZE - 1 do
            local cx, cy = min(i, SIZE - 1 - i), min(j, SIZE - 1 - j)
            local corner = cx + cy < 3
            local edge = cx == 0 or cy == 0 or (cx + cy == 3)
            out[j * SIZE + i] = corner and 0 or edge and IDX.o or bg
        end
    end
    -- The night: everything a step darker, as the board's night takes it,
    -- save the ink, which keeps the darkest key to itself.
    local function at(i, j)
        local k = key[(j - dy) * W + (i - dx)] or 0
        if race.night and k ~= 0 and k ~= IDX.o then k = max(IDX.u, T.DARKER[k]) end
        return k
    end
    -- Laid inside the frame.
    for j = 1, SIZE - 2 do
        for i = 1, SIZE - 2 do
            local si, sj, here = i - dx, j - dy, out[j * SIZE + i]
            if si >= 0 and sj >= 0 and si < W and sj < W and here ~= 0 and here ~= IDX.o then
                local k = at(i, j)
                if k ~= 0 then out[j * SIZE + i] = k end
            end
        end
    end
    -- What is drawn over, in the icon's own pixels.
    if race.after then
        clear()
        race.after(floor(W / 2 + dx), floor(W / 2 + dy))
        for j = 1, SIZE - 2 do
            for i = 1, SIZE - 2 do
                local k = key[j * W + i]
                if k ~= 0 and out[j * SIZE + i] ~= IDX.o then out[j * SIZE + i] = k end
            end
        end
    end
    return out
end

--- writing ---------------------------------------------------------------------------

local function ppm(name, w, h, px)
    local f = assert(io.open((arg[1] or ".") .. "/" .. name .. ".ppm", "wb"))
    f:write(("P6\n%d %d\n255\n"):format(w, h))
    local buf = {}
    for n = 0, w * h - 1 do
        local c = T.RGB[px[n] ~= 0 and px[n] or IDX.c]
        buf[#buf + 1] = string.char(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
    end
    f:write(table.concat(buf))
    f:close()
end

local all, gap = {}, 4
local sw = #RACES * (SIZE + gap) + gap
for n = 0, sw * (SIZE + 2 * gap) - 1 do all[n] = IDX.c end
for k, race in ipairs(RACES) do
    local px = icon(race)
    ppm(race.name, SIZE, SIZE, px)
    for j = 0, SIZE - 1 do
        for i = 0, SIZE - 1 do
            all[(j + gap) * sw + gap + (k - 1) * (SIZE + gap) + i] = px[j * SIZE + i]
        end
    end
end
ppm("races", sw, SIZE + 2 * gap, all)
