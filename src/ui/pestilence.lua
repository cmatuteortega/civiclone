-- The plague (src/plague.lua), as it is seen beyond its own models
-- (src/models.lua: the rats, the crosses daubed on the houses, the graves on
-- the empty plots, the lazaret, the fallow farm's ruin):
--
--   - a miasma lying over a sick town and the land round it: the ground
--     paler in a slow drifting dither, thickest at the town, and wisps of it
--     curling up among the roofs;
--   - crows wheeling over the sick towns, and from the omen over every town,
--     most of all the first that will fall sick;
--   - a pyre burning outside a town that has lost people in the last turns,
--     a black column of smoke over it (src/ui/smoke.lua), and its light at
--     night;
--   - the flags of a shut town at its corners, a rope slung between them;
--   - flies about the people who carry it;
--   - from the great dying on, the sky overcast: more of the clouds'
--     shadows going over (src/ui/sea.lua's `overcast`).
--
-- Nothing is kept but the crows' flight: what is where comes from the clock
-- and the hex, so it costs nothing off the screen. Still eight colours: the
-- miasma is the ground's own keys a step lighter, never a tint.

local T = require "src.tracer"
local M = require "src.models"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Sea = require "src.ui.sea"
local Smoke = require "src.ui.smoke"
local Fire = require "src.ui.fire"
local Anim = require "src.ui.anim"
local Cat = require "src.cataclysm"

local floor, sin, cos, sqrt = math.floor, math.sin, math.cos, math.sqrt
local IDX = T.IDX

local Pest = {}

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

local function on(g) return g and Cat.is(g, "plague") end

-- How long a pyre burns after a death, in turns.
Pest.PYRE_TURNS = 2

-- What the town model of city `c` shows of the plague: its crosses while
-- it is sick, its graves (one for each of its dead).
function Pest.cityLook(c)
    if not c.sick and not c.dead then return nil end
    return { marked = c.sick ~= nil, graves = c.dead or 0 }
end

-- How many of a town's windows are dark at night: most of a sick one's.
function Pest.dark(c)
    if c.sick then return 0.7 end
    return 0
end

--- the miasma ---------------------------------------------------------------------------

-- How thick the miasma is at room point (x, z), `near` 0 at the sick town
-- and 1 a hex out, at time t.
local function thick(x, z, near, t)
    local f = sin(x * 0.13 + t * 0.35 + sin(z * 0.19 - t * 0.27) * 1.6) + sin(z * 0.21 + t * 0.22 + x * 0.06)
    return f * 0.5 + 0.75 - near * 0.9
end

-- The ground of hex `cell` under the miasma of the sick town on `town`.
local function haze(cell, town, list)
    list[#list + 1] = { z = cell.z - 1.8, draw = function()
        local w = S.world
        local t = Sea.still() and 0 or Sea.air()
        local key = w.key
        P.eachTop(cell, function(i, j, n)
            local x, z = w.wx[n], w.wz[n]
            local d = sqrt((x - town.x) ^ 2 + (z - town.z) ^ 2) / 24
            local v = thick(x, z, d, t)
            if v > 0.5 then
                -- A step paler, every other pixel; where it is thickest, two.
                if (i + j) % 2 == 0 then
                    local k = T.LIGHTER[key[n]]
                    if v > 0.95 then k = T.LIGHTER[k] end
                    P.put(k, i, j)
                elseif v > 1.1 and (i * 3 + j) % 4 == 1 then
                    P.put(IDX.c, i, j)
                end
            end
        end)
    end }
end

-- Wisps of it curling up among a sick town's roofs: a few pale shreds,
-- holed, rising slowly and drifting with the wind.
local function wisps(cell, list)
    list[#list + 1] = { z = cell.z + 6, draw = function()
        if Sea.still() then return end
        local t = Sea.air()
        for k = 1, 7 do
            local life = 7 + grain(cell.id, k, 1) * 4
            local age = (t / life + grain(k, cell.id, 2)) % 1
            local cycle = floor(t / life + grain(k, cell.id, 2))
            local a = grain(cell.id, k, cycle) * math.pi * 2
            local r0 = 3 + grain(k, cycle, cell.id) * 9
            local x = cell.x + cos(a) * r0 + age * 6
            local z = cell.z + sin(a) * r0 * 0.8
            local y = cell.top + 3 + age * 12
            local si, sj, d = S.world:toImage(x, y, z)
            local len = floor(4 + age * 7)
            local holes = age * age * 1.2
            for q = 0, len do
                local i = floor(si + q - len / 2)
                local j = floor(sj + sin(q * 0.6 + t * 1.5 + k) * 1.4)
                if grain(q, k, cycle) >= holes and P.visible(i, j, d + 8) then
                    P.put(age < 0.3 and IDX.c or IDX.s, i, j)
                    if q % 3 == 0 and grain(k, q, cycle + 1) > holes + 0.2 then P.put(IDX.s, i, j + 1) end
                end
            end
        end
    end }
end

--- the pyre --------------------------------------------------------------------------------

-- Where a town burns its dead: on a free hex of land beside it, the one
-- with the least on it, kept to the town's side of it.
function Pest.pyreSpot(g, c)
    local cell = g.cells[c.cell]
    local best, bv
    for _, n in ipairs(g:neighbours(cell)) do
        if g:passable(n) and not n.city then
            local v = (n.feature and 3 or 0) + (n.improvement and 2 or 0) + (g.mil[n.id] and 4 or 0) + grain(n.id, 1, 9) * 0.5
            if not bv or v < bv then best, bv = n, v end
        end
    end
    if not best then return nil end
    local x = best.x + (cell.x - best.x) * 0.3
    local z = best.z + (cell.z - best.z) * 0.3
    return best, x, z
end

local function burning(g, c) return c.pyre and g.turn - c.pyre <= Pest.PYRE_TURNS end

local function pyre(g, c, list)
    local spot, x, z = Pest.pyreSpot(g, c)
    if not spot then return end
    local y = spot.top + (spot.elev == "hills" and 1 or 0)
    list[#list + 1] = { z = z, draw = function()
        P.stamp(M.pyre(), x, y, z)
        if Sea.still() then return end
        local si, sj, d = S.world:toImage(x, y + 3.5, z)
        if not P.onScreen(floor(si), floor(sj), 60) then return end
        Fire.flame(si, sj, d, 9, 6, c.id)
        Fire.flame(si - 3, sj + 1, d, 6, 4, c.id + 7)
        Fire.flame(si + 3, sj + 1, d, 5, 4, c.id + 13)
    end }
    list[#list + 1] = { z = z + 4, draw = function()
        Smoke.fire(x, y + 8, z, c.id * 5, 0.85)
    end }
end

--- a shut town -------------------------------------------------------------------------------

local function flags(cell, list)
    local r = 13.2
    local poles = {}
    for k = 0, 5 do
        local a = math.rad(60 * k + 30)
        poles[k] = { cell.x + r * cos(a), cell.z + r * sin(a) }
    end
    -- The rope, slung low from pole to pole, sagging between.
    list[#list + 1] = { z = cell.z - 0.5, draw = function()
        local y = cell.top + 3.2
        for k = 0, 5 do
            local p0, p1 = poles[k], poles[(k + 1) % 6]
            local mx, mz = (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2
            P.line3(p0[1], y, p0[2], mx, y - 1.2, mz, IDX.u)
            P.line3(mx, y - 1.2, mz, p1[1], y, p1[2], IDX.u)
        end
    end }
    for k = 0, 5 do
        local p = poles[k]
        list[#list + 1] = { z = p[2] + 0.2, draw = function()
            local pose = Sea.still() and 0 or floor(Sea.air() * 3 + k * 0.7) % M.FLAG_POSES
            P.stamp(M.plagueFlag(pose), p[1], cell.top, p[2])
        end }
    end
end

--- flies -------------------------------------------------------------------------------------

-- Flies about unit u, who carries the sickness: specks of ink round its head.
local function flies(g, u, list)
    local x, y, z = Anim.place(g, u)
    list[#list + 1] = { z = z + 0.3, draw = function()
        if Sea.still() then return end
        local t = S.clock
        local si, sj, d = S.world:toImage(x, y + 10, z)
        for k = 1, 4 do
            local a = t * (3 + k * 0.7) + k * 1.7
            local i = floor(si + cos(a) * (3 + k % 2 * 2) + sin(t * 9 + k) * 0.6)
            local j = floor(sj + sin(a * 1.3) * 2.2)
            if P.visible(i, j, d + 6) then P.put(IDX.o, i, j) end
        end
    end }
end

--- onto the board ------------------------------------------------------------------------------

-- Everything of the plague's on the board, onto `list` (src/ui/board.lua
-- sorts what it draws, back to front).
function Pest.things(me, list)
    local g = S.game
    if not on(g) then return end
    for _, c in ipairs(g.cities) do
        local cell = g.cells[c.cell]
        if me.explored[cell.id] then
            if c.shut then flags(cell, list) end
            if burning(g, c) then pyre(g, c, list) end
            if c.sick and me.visible[cell.id] then
                for _, n in ipairs(g:within(cell, 1)) do
                    if me.visible[n.id] and not g:isWater(n) then haze(n, cell, list) end
                end
                wisps(cell, list)
            end
        end
    end
    for _, u in ipairs(g.units) do
        if u.sick and (u.owner == 1 or me.visible[u.cell]) then flies(g, u, list) end
    end
end

-- The farms the plague has left fallow: their ruins, on the board's list.
function Pest.ruins(me, list)
    local g = S.game
    for _, cell in ipairs(g.cells) do
        if cell.fallow and not cell.improvement and not cell.city and me.explored[cell.id] then
            local pic = M.farmRuin(M.farmLayout(cell.id))
            list[#list + 1] = { z = cell.z - 1, draw = function() P.stamp(pic, cell.x, cell.top, cell.z) end }
        end
    end
end

--- the crows ----------------------------------------------------------------------------------

-- Wing pixels either side of the body, for each beat: up, level, down.
local WINGS = {
    { -3, -2, -2, -1, -1, 0, 1, 0, 2, -1, 3, -2 },
    { -3, 0, -2, -1, -1, 0, 1, 0, 2, -1, 3, 0 },
    { -3, 1, -2, 1, -1, 0, 1, 0, 2, 1, 3, 1 },
    { -3, 0, -2, -1, -1, 0, 1, 0, 2, -1, 3, 0 },
}

local function crow(i, j, beat)
    i, j = floor(i), floor(j)
    local x, y = i - floor(S.camx), j - floor(S.camy)
    if x < 3 or y < 3 or x >= S.cw - 3 or y >= S.ch - 3 then return end
    local f = WINGS[beat % 4 + 1]
    P.putS(IDX.o, x, y)
    P.putS(IDX.o, x, y + 1)
    for n = 1, #f, 2 do P.putS(IDX.o, x + f[n], y + f[n + 1]) end
end

-- How many crows wheel over city `c` now.
function Pest.crows(g, c)
    if not on(g) then return 0 end
    local s = Cat.stage(g)
    if not s then return 0 end
    if c.sick then return 6 end
    if s == "omen" then
        local c0 = g.cataclysm.zero
        return c0 == c.id and 7 or 2
    end
    return 0
end

-- Onto the overlay, over everything: the crows. And the sky made overcast
-- for the shaders, which are sent it after.
function Pest.draw()
    local g = S.game
    S.overcast = Pest.pall(g)
    if not on(g) or not S.world or Sea.still() then return end
    local me = g.players[1]
    local t = Sea.air()
    for _, c in ipairs(g.cities) do
        local n = Pest.crows(g, c)
        if n > 0 and me.visible[c.cell] then
            local cell = g.cells[c.cell]
            local ci, cj = S.world:toImage(cell.x, cell.top + 30, cell.z)
            if P.onScreen(floor(ci), floor(cj), 40) then
                for k = 1, n do
                    local rate = 0.35 + grain(c.id, k, 3) * 0.25
                    local a = t * rate * (k % 2 == 0 and 1 or -1) + k * 2.1
                    local r = 10 + grain(k, c.id, 4) * 12
                    local glide = sin(t * 0.6 + k) > 0.2
                    local beat = glide and 1 or floor(t * 5 + k)
                    crow(ci + cos(a) * r, cj + sin(a) * r * 0.4 + sin(t + k) * 2, beat)
                end
            end
        end
    end
end

--- the light ------------------------------------------------------------------------------------

-- The pyres light the night round them. `out` and `sig` as Daylight.lamps
-- keeps them.
function Pest.lamps(w, me, out, sig)
    local g = S.game
    if not on(g) then return end
    for _, c in ipairs(g.cities) do
        if me.explored[c.cell] and burning(g, c) then
            local spot, x, z = Pest.pyreSpot(g, c)
            if spot then
                local i, j = w:toImage(x, spot.top, z)
                out[#out + 1] = { floor(i), floor(j) - 4, 22 }
                sig[#sig + 1] = "p" .. c.id
            end
        end
    end
end

-- How overcast the plague makes the sky (src/ui/sea.lua): more cloud from
-- the great dying on.
local PALL = { dying = 0.5, dance = 1 }
function Pest.pall(g)
    if not on(g) then return 0 end
    return PALL[Cat.stage(g) or ""] or 0
end

return Pest
