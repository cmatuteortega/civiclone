-- The wildfires of the heat death (src/cataclysm.lua), as they burn: flames
-- licking up from a burning hex's trees or its field, sparks going up, the
-- ashes on the ground glowing, and a black column of smoke over it all
-- (src/ui/smoke.lua). At night the fire is a lamp (src/ui/daylight.lua).
--
-- Like the smoke, nothing is kept: every flame comes from the clock and the
-- hex, so it costs nothing off the screen. Each flame is a tongue of pixels
-- inked round, white at its root, then the pale keys out to its edge and its
-- tip, its height and its lean flickering a dozen times a second.

local T = require "src.tracer"
local H = require "src.hex"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Smoke = require "src.ui.smoke"

local floor, sin, abs, max = math.floor, math.sin, math.abs, math.max
local IDX = T.IDX

local Fire = {}

local FLICKER = 12   -- times a second a flame changes

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

-- Where on the hex the flames stand: a few, kept in from its edge, the same
-- for the same hex. A forest burns higher and in more places than a field.
local function spots(cell)
    local out = {}
    local n = cell.feature == "forest" and 5 or 4
    local tries = 0
    while #out < n and tries < 40 do
        tries = tries + 1
        local x = cell.x + (grain(cell.id, tries, 1) * 2 - 1) * H.R
        local z = cell.z + (grain(tries, cell.id, 2) * 2 - 1) * H.R
        if H.inset(x, z, cell.x, cell.z) > 3 then
            local ok = true
            for _, p in ipairs(out) do if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < 18 then ok = false end end
            if ok then out[#out + 1] = { x, z } end
        end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end
Fire.spots = spots

-- One flame from picture point (si, sj) at depth d: `tall` and `wide` its
-- size in pixels, `seed` sets it apart. Its shape is found first, then laid
-- with an ink line round it, so it reads against anything.
--
-- The shape is kept in tables used again by every flame, rather than made
-- anew for each: a pixel (i, j) is in this flame's shape while seen[q] is
-- this flame's number, q = j * 4096 + i, its key in keyAt[q], and listed
-- once in shapeI, shapeJ.
local seen, keyAt, inked = {}, {}, {}
local shapeI, shapeJ, shapeN = {}, {}, 0
local flameNo = 0
local function set(i, j, k)
    local q = j * 4096 + i
    if seen[q] ~= flameNo then
        seen[q] = flameNo
        shapeN = shapeN + 1
        shapeI[shapeN], shapeJ[shapeN] = i, j
    end
    keyAt[q] = k
end
local AROUND_I, AROUND_J = { 1, -1, 0, 0 }, { 0, 0, 1, -1 }

local function flame(si, sj, d, tall, wide, seed)
    -- The tables started again now and then, so they do not grow without end.
    flameNo = flameNo + 1
    if flameNo > 20000 then seen, keyAt, inked, flameNo = {}, {}, {}, 1 end
    shapeN = 0
    local tick = floor(S.clock * FLICKER)
    local h = tall * (0.7 + 0.45 * grain(seed, tick, 3))
    local lean = (grain(seed, floor(tick / 3), 4) - 0.5) * 3
    local rows = floor(h + 0.5)
    for r = 0, rows do
        local f = r / max(h, 1)
        -- Widest a little above the root, to a point.
        local half = wide * 0.5 * (f < 0.2 and (0.75 + f * 1.25) or (1 - f) ^ 0.8 / 0.8 ^ 0.8) + 0.3
        local ci = si + lean * f * f + sin(S.clock * 9 + r * 0.7 + seed) * 0.8 * f
        local j = floor(sj - r)
        for i = floor(ci - half + 0.5), floor(ci + half - 0.5) do
            local u = abs(i + 0.5 - ci) / max(half, 0.5)
            -- Ragged at the edge: a few pixels missing, more up high.
            if u < 0.8 or grain(i, j, tick + seed) > f then
                local k = IDX.s
                if u < 0.45 and f < 0.6 then k = IDX.w
                elseif u < 0.8 and f < 0.85 then k = IDX.c end
                set(i, j, k)
            end
        end
    end
    -- A tongue broken off above, now and then.
    if grain(seed, tick, 5) > 0.5 then
        local i, j = floor(si + lean * 1.3), floor(sj - rows - 2 - grain(seed, tick, 6) * 3)
        set(i, j, IDX.c)
        set(i, j - 1, IDX.s)
    end
    -- The ink round it, each pixel of it once: it is all the one key, and
    -- never where the shape is, so in what order makes no difference.
    local ink = IDX.o
    for n = 1, shapeN do
        local pi, pj = shapeI[n], shapeJ[n]
        for o = 1, 4 do
            local i, j = pi + AROUND_I[o], pj + AROUND_J[o]
            local q = j * 4096 + i
            if seen[q] ~= flameNo and inked[q] ~= flameNo then
                inked[q] = flameNo
                if P.visible(i, j, d + 5) then P.put(ink, i, j) end
            end
        end
    end
    for n = 1, shapeN do
        local i, j = shapeI[n], shapeJ[n]
        if P.visible(i, j, d + 5) then P.put(keyAt[j * 4096 + i], i, j) end
    end
end

Fire.flame = flame

-- Sparks: single pixels going up from the fire, winking.
local function sparks(cell, si, sj, d)
    local t = S.clock
    for n = 1, 6 do
        local life = 1.4 + grain(cell.id, n, 7)
        local age = (t / life + grain(n, cell.id, 8)) % 1
        local i = floor(si + (grain(cell.id, n, 9) - 0.5) * 18 + age * 6 + sin(t * 3 + n) * 1.5)
        local j = floor(sj - 4 - age * 30)
        if grain(n, floor(t * 10), cell.id) > 0.25 and P.visible(i, j, d + 4) then
            P.put(age < 0.5 and IDX.w or IDX.c, i, j)
        end
    end
end

-- The ground of a burning hex: its ashes catching, here and there, and
-- going out again.
local function embers(cell)
    local w = S.world
    local tick = floor(S.clock * 4)
    P.eachTop(cell, function(i, j, n)
        local k = w.key[n]
        if (k == IDX.n or k == IDX.u or k == IDX.o) and grain(i, j, tick) > 0.9 then
            P.put(grain(j, i, tick) > 0.5 and IDX.c or IDX.s, i, j)
        end
    end)
end

-- Everything of hex `cell`'s fire, onto `list` (as src/ui/board.lua sorts
-- what it draws, back to front).
function Fire.things(cell, list)
    local forest = cell.feature == "forest"
    local g = cell.top + (cell.elev == "hills" and 1 or 0)
    local pts = spots(cell)
    list[#list + 1] = { z = cell.z - 2, draw = function() embers(cell) end }
    for k, p in ipairs(pts) do
        local x, z = p[1], p[2]
        list[#list + 1] = { z = z + 0.3, draw = function()
            -- In a forest, out of the crowns; in a field, off the ground.
            local si, sj, d = S.world:toImage(x, g + (forest and 6 or 0.5), z)
            if not P.onScreen(floor(si), floor(sj), 40) then return end
            local seed = cell.id * 7 + k
            if forest then
                flame(si, sj, d, 15 + grain(seed, 1, 10) * 7, 8, seed)
                flame(si - 3, sj + 3, d, 8, 5, seed + 50)
            else
                flame(si, sj, d, 7 + grain(seed, 1, 10) * 4, 5, seed)
            end
        end }
    end
    list[#list + 1] = { z = cell.z + 4, draw = function()
        local si, sj, d = S.world:toImage(cell.x, g, cell.z)
        sparks(cell, si, sj, d)
        -- Two columns of smoke, the forest's the bigger.
        local size = forest and 1.2 or 0.8
        Smoke.fire(cell.x - 2, g + (forest and 14 or 7), cell.z - 1, cell.id * 3, size)
        if forest then Smoke.fire(cell.x + 3, g + 12, cell.z + 1, cell.id * 3 + 1, size * 0.75) end
    end }
end

return Fire
