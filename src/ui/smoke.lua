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
function Smoke.fire(x, y, z, seed, size)
    if Sea.still() then return end
    local si, sj, d = S.world:toImage(x, y, z)
    if not P.onScreen(floor(si), floor(sj), (BLAZE.rise + BLAZE.drift) * size) then return end
    local t = Sea.air()
    local phase = grain(seed, 3, 4)
    local puffs = {}
    for n = 0, BLAZE.puffs - 1 do
        local f = t / BLAZE.life + n / BLAZE.puffs + phase
        local age, cycle = f % 1, floor(f)
        local r = (1.5 + age ^ 0.8 * 7.5) * size * (0.85 + grain(seed, cycle, n) * 0.3)
        local ci = si + age ^ 1.5 * BLAZE.drift * size + sin(t * 1.1 + n * 2.3 + seed) * 1.6 * age
        local cj = sj - age * BLAZE.rise * size
        puffs[#puffs + 1] = { ci = ci, cj = cj, r = r, age = age, cycle = cycle, n = n }
    end
    -- Oldest first, so the young puffs at the root are on top.
    table.sort(puffs, function(a, b) return a.age > b.age end)
    local function disc(p, grow, f)
        local r = p.r + grow
        local reach = floor(r + 1)
        for dj = -reach, reach do
            for di = -reach, reach do
                if di * di + dj * dj <= r * r + 0.3 then
                    local i, j = floor(p.ci + di), floor(p.cj + dj)
                    if P.visible(i, j, d + 6) then f(i, j, di, dj) end
                end
            end
        end
    end
    for _, p in ipairs(puffs) do
        if p.age < 0.5 then disc(p, 1, function(i, j) P.put(IDX.o, i, j) end) end
    end
    for _, p in ipairs(puffs) do
        local holes = (p.age - 0.4) * 1.5
        disc(p, 0, function(i, j, di, dj)
            if grain(di, dj, p.cycle * 7 + p.n + seed) < holes then return end
            local k = IDX.k
            local r = p.r
            if dj > r * 0.4 then k = IDX.n end                     -- the underside
            local hx, hy = di + r * 0.35, dj + r * 0.4               -- lit from the upper left
            if hx * hx + hy * hy < r * r * 0.18 then k = IDX.t end
            if p.age < 0.12 then k = IDX.u end                     -- black at the root
            P.put(k, i, j)
        end)
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
