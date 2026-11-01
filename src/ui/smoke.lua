-- Smoke from the chimneys: a few puffs rising from a city's houses, the
-- farmhouse's thatch and the miners' hut, carried east by the same wind that
-- leans the trees (src/ui/sea.lua). A city has more fires the bigger it is.
--
-- Nothing is kept: where each puff is comes from the wind's clock alone, so
-- it costs nothing while off the screen and nothing to save. Each puff is a
-- little disk of pixels that grows as it rises and falls to holes, never to
-- alpha, light on top and a step darker underneath.

local T = require "src.tracer"
local M = require "src.models"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Sea = require "src.ui.sea"

local floor, sin = math.floor, math.sin
local IDX = T.IDX

local Smoke = {}

local PUFFS = 6      -- in the air at once, from one chimney
local LIFE = 6       -- seconds from the chimney to gone
local RISE = 28      -- pixels a puff climbs in its life
local DRIFT = 15     -- pixels the wind carries it east

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

-- One puff `age` (0..1) into its life, from the chimney at picture point
-- (si, sj) and depth d; `size` scales it.
local function puff(si, sj, d, age, cycle, n, seed, size)
    local t = Sea.air()
    local r = (0.8 + age * 2.6) * size
    local ci = si + age ^ 1.6 * DRIFT * size + sin(t * 1.3 + n * 2.1 + seed) * 1.2 * age
    local cj = sj - age * RISE * size
    local holes = age * age * 1.1 - 0.15
    local reach = floor(r + 0.5)
    for dj = -reach, reach do
        for di = -reach, reach do
            if di * di + dj * dj <= r * r + 0.3 then
                local i, j = floor(ci + di), floor(cj + dj)
                if grain(di, dj, cycle * 7 + n + seed) >= holes and P.visible(i, j, d + 4) then
                    -- Lit from the upper left, as everything is.
                    local k = age < 0.25 and IDX.w or IDX.c
                    if r > 1.4 and di + dj > r * 0.5 then k = IDX.s end
                    P.put(k, i, j)
                end
            end
        end
    end
end

-- One chimney at room point (x, y, z); `seed` sets it apart from the others.
-- `fits`, if given, makes it smoke now and then instead of all the time: a
-- few puffs, `fits.gap` seconds apart, every `fits.every` seconds, each
-- `fits.size` as big.
local function chimney(x, y, z, seed, fits)
    local si, sj, d = S.world:toImage(x, y, z)
    if not P.onScreen(floor(si), floor(sj), RISE + DRIFT) then return end
    local t = Sea.air()
    local phase = grain(seed, 1, 2)
    if fits then
        local at = t + phase * fits.every
        for n = 0, fits.puffs - 1 do
            local age = (at % fits.every - n * fits.gap) / LIFE
            if age >= 0 and age < 1 then puff(si, sj, d, age, floor(at / fits.every), n, seed, fits.size) end
        end
        return
    end
    for n = 0, PUFFS - 1 do
        local age = (t / LIFE + n / PUFFS + phase) % 1
        puff(si, sj, d, age, floor(t / LIFE + n / PUFFS + phase), n, seed, 1)
    end
end

-- A city's chimneys: one on a house for every two citizens, three at most,
-- wherever its layout put those houses.
function Smoke.city(cell, city)
    if Sea.still() then return end
    local s = M.CITY_SCALE
    for k, c in ipairs(M.cityChimneys(city.pop, city.buildings, M.citySite(cell))) do
        chimney(cell.x + c[1] * s, cell.top + c[2] * s, cell.z + c[3] * s, cell.id * 10 + k)
    end
end

-- A wildfire's smoke (src/ui/fire.lua): a thick column from room point
-- (x, y, z), billowing as it climbs and carried off by the wind. Its puffs
-- are drawn as one cloud: an ink line round all of them first, then each
-- filled, dark beneath and paler on top, so it reads over the char and over
-- the sand alike. High up it thins to holes and loses its line.
local BLAZE = { puffs = 7, life = 7, rise = 50, drift = 30 }
-- The puffs of the column being drawn, kept in tables used again.
local pCi, pCj, pR, pAge, pCycle, pN, order = {}, {}, {}, {}, {}, {}, {}
-- Which pixels this column has laid, over a box round all its puffs: the
-- pixel at q in the box is this column's while filled[q] (or inked[q]) is
-- its number.
local filled, inked, column = {}, {}, 0
function Smoke.fire(x, y, z, seed, size)
    if Sea.still() then return end
    local w = S.world
    local si, sj, d = w:toImage(x, y, z)
    if not P.onScreen(floor(si), floor(sj), (BLAZE.rise + BLAZE.drift) * size) then return end
    column = column + 1
    local t = Sea.air()
    local phase = grain(seed, 3, 4)
    local count = BLAZE.puffs
    local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
    for n = 0, count - 1 do
        local f = t / BLAZE.life + n / BLAZE.puffs + phase
        local age, cycle = f % 1, floor(f)
        local q = n + 1
        local r = (1.5 + age ^ 0.8 * 7.5) * size * (0.85 + grain(seed, cycle, n) * 0.3)
        local ci = si + age ^ 1.5 * BLAZE.drift * size + sin(t * 1.1 + n * 2.3 + seed) * 1.6 * age
        local cj = sj - age * BLAZE.rise * size
        pR[q], pCi[q], pCj[q] = r, ci, cj
        pAge[q], pCycle[q], pN[q] = age, cycle, n
        order[q] = q
        local reach = floor(r + 2) + 1
        i0, i1 = math.min(i0, floor(ci) - reach), math.max(i1, floor(ci) + reach)
        j0, j1 = math.min(j0, floor(cj) - reach), math.max(j1, floor(cj) + reach)
    end
    local bw = i1 - i0 + 1
    -- Oldest first, so the young puffs at the root are on top. (No two are
    -- the same age: they are a seventh of a life apart.)
    for a = 2, count do
        local v, b = order[a], a - 1
        while b >= 1 and pAge[order[b]] < pAge[v] do order[b + 1] = order[b] b = b - 1 end
        order[b + 1] = v
    end
    -- Whether a pixel is nearer than the board there is P.visible's test,
    -- and the holes are grain's, both written out here: this is the most
    -- of what a fire costs.
    local deep = d + 6
    local ww, wh, dep = w.w, w.h, w.dep
    local put, mark = P.put, column
    -- Each puff filled, dark beneath and paler on top; high up it thins to
    -- holes. Where puffs overlap the one on top is what shows, so they are
    -- taken youngest first and each pixel laid by the first that fills it.
    for a = count, 1, -1 do
        local p = order[a]
        local ci, cj, r, age = pCi[p], pCj[p], pR[p], pAge[p]
        local holes = (age - 0.4) * 1.5
        local salt = (pCycle[p] * 7 + pN[p] + seed) * 37.719
        local rr = r * r + 0.3
        local reach = floor(r + 1)
        for dj = -reach, reach do
            local j = floor(cj + dj)
            local row = (j - j0) * bw - i0 + 1
            for di = -reach, reach do
                if di * di + dj * dj <= rr then
                    local i = floor(ci + di)
                    local q = row + i
                    if filled[q] ~= mark
                        and (i < 0 or j < 0 or i >= ww or j >= wh or deep >= dep[j * ww + i] - 0.6) then
                        local g = sin(di * 12.9898 + dj * 78.233 + salt) * 43758.5453
                        if g - floor(g) >= holes then
                            filled[q] = mark
                            local k = IDX.k
                            if dj > r * 0.4 then k = IDX.n end                     -- the underside
                            local hx, hy = di + r * 0.35, dj + r * 0.4               -- lit from the upper left
                            if hx * hx + hy * hy < r * r * 0.18 then k = IDX.t end
                            if age < 0.12 then k = IDX.u end                     -- black at the root
                            put(k, i, j)
                        end
                    end
                end
            end
        end
    end
    -- An ink line round the young puffs, a pixel out, where no puff is
    -- filled over it: it reads over the char and over the sand alike.
    local ink = IDX.o
    for a = 1, count do
        local p = order[a]
        if pAge[p] < 0.5 then
            local ci, cj, r = pCi[p], pCj[p], pR[p] + 1
            local rr = r * r + 0.3
            local reach = floor(r + 1)
            for dj = -reach, reach do
                local j = floor(cj + dj)
                local row = (j - j0) * bw - i0 + 1
                for di = -reach, reach do
                    if di * di + dj * dj <= rr then
                        local i = floor(ci + di)
                        local q = row + i
                        if filled[q] ~= mark and inked[q] ~= mark then
                            inked[q] = mark
                            if i < 0 or j < 0 or i >= ww or j >= wh or deep >= dep[j * ww + i] - 0.6 then
                                put(ink, i, j)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- A farmhouse's fire is low: two small puffs, then nothing for a while.
local FARM = { puffs = 2, gap = 1.1, every = 15, size = 0.6 }

-- A farm's, from the peak of the farmhouse's thatch; a mine's, from the hut.
function Smoke.improvement(cell)
    if Sea.still() then return end
    if cell.improvement == "farm" then
        local home, s = M.farmLayout(cell.id).home, M.FARM_SCALE
        chimney(cell.x + home[1] * s, cell.top + 7 * s, cell.z + home[2] * s, cell.id * 10, FARM)
    elseif cell.improvement == "mine" then
        local s = M.MINE_SCALE
        chimney(cell.x + 5.2 * s, cell.top + 5.2 * s, cell.z + 5 * s, cell.id * 10)
    end
end

return Smoke
