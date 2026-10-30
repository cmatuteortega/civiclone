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

local floor, sin, min = math.floor, math.sin, math.min
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

-- One chimney at room point (x, y, z); `seed` sets it apart from the others.
local function chimney(x, y, z, seed)
    local si, sj, d = S.world:toImage(x, y, z)
    if not P.onScreen(floor(si), floor(sj), RISE + DRIFT) then return end
    local t = Sea.air()
    local phase = grain(seed, 1, 2)
    for n = 0, PUFFS - 1 do
        local age = (t / LIFE + n / PUFFS + phase) % 1
        local cycle = floor(t / LIFE + n / PUFFS + phase)
        local r = 0.8 + age * 2.6
        local ci = si + age ^ 1.6 * DRIFT + sin(t * 1.3 + n * 2.1 + seed) * 1.2 * age
        local cj = sj - age * RISE
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
end

-- A city's chimneys: one on a house for every two citizens, three at most.
function Smoke.city(cell, city)
    if Sea.still() then return end
    local s = M.CITY_SCALE
    local houses = min(#M.CITY_SPOTS, 1 + city.pop)
    for k = 1, min(houses, 1 + floor(city.pop / 2), 3) do
        local spot = M.CITY_SPOTS[k]
        local size = 0.9 + (k % 3) * 0.08
        chimney(cell.x + (spot[1] + 0.8) * s, cell.top + 5.2 * size * s, cell.z + spot[2] * s, cell.id * 10 + k)
    end
end

-- A farm's, from the peak of the farmhouse's thatch; a mine's, from the hut.
function Smoke.improvement(cell)
    if Sea.still() then return end
    if cell.improvement == "farm" then
        local home, s = M.farmLayout(cell.id).home, M.FARM_SCALE
        chimney(cell.x + home[1] * s, cell.top + 7 * s, cell.z + home[2] * s, cell.id * 10)
    elseif cell.improvement == "mine" then
        local s = M.MINE_SCALE
        chimney(cell.x + 5.2 * s, cell.top + 5.2 * s, cell.z + 5 * s, cell.id * 10)
    end
end

return Smoke
