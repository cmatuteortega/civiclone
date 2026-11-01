-- The demons (src/demons.lua), as they are seen beyond their own models
-- (src/models.lua): what is coming up marked on the ground the turn before
-- -- the hex split by a crack pulsing pale for a rift or the citadel, the
-- water turning in rings for a tentacle -- a pale light flickering in every
-- open rift, and from the omen on a blood moon, black with a pale rim,
-- hanging in the night sky.
--
-- The light shader lights the rifts and the citadel at night as it does a
-- town (src/ui/daylight.lua asks Abyss.lamps).

local T = require "src.tracer"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Cat = require "src.cataclysm"

local floor, sin, cos, abs = math.floor, math.sin, math.cos, math.abs
local IDX = T.IDX

local Abyss = {}

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

-- A crack across hex `cell`'s top, zigzagging, pulsing pale; `big` for the
-- citadel's ground, branched.
local function splitting(cell, big, list)
    list[#list + 1] = { z = cell.z - 1.5, draw = function()
        local w = S.world
        local beat = (sin(S.clock * 5) + 1) * 0.5
        local seed = cell.id * 0.37
        P.eachTop(cell, function(i, j, n)
            local x, z = w.wx[n] - cell.x, w.wz[n] - cell.z
            local line = z - sin(x * 0.9 + seed) * 1.6 - x * 0.25
            local d = abs(line)
            if big then d = math.min(d, abs(x + sin(z * 1.1 + seed) * 1.2) + (z > 0 and 0 or 99)) end
            if d < 0.55 then
                P.put(beat > 0.5 and IDX.w or IDX.c, i, j)
            elseif d < 1.2 then
                P.put(IDX.o, i, j)
            elseif d < 2.2 and grain(i, j, floor(S.clock * 6)) > 0.8 then
                P.put(IDX.u, i, j)
            end
        end)
        P.hexLine(cell, function(f) return floor(f * 12 + S.clock * 4) % 2 == 0 and IDX.o or IDX.c end, 0.8, 0.4)
    end }
end

-- The water over hex `cell` turning in rings, something under it.
local function stirring(cell, list)
    list[#list + 1] = { z = cell.z - 1.5, draw = function()
        local w = S.world
        local t = S.clock * 3
        P.eachTop(cell, function(i, j, n)
            local x, z = w.wx[n] - cell.x, w.wz[n] - cell.z
            local r = math.sqrt(x * x + z * z * 1.4)
            local a = math.atan2(z, x)
            local v = sin(r * 1.3 - t + a * 2)
            if v > 0.8 then P.put(r < 3 and IDX.o or IDX.c, i, j) elseif v < -0.85 then P.put(IDX.u, i, j) end
        end)
    end }
end

-- A pale light flickering in an open rift.
local function flicker(cell, list)
    list[#list + 1] = { z = cell.z - 0.5, draw = function()
        local tick = floor(S.clock * 8)
        for k = 1, 6 do
            if grain(k, cell.id, tick) > 0.5 then
                local f = (k - 3.5) / 3.5
                local x, z = cell.x + f * 5, cell.z - 1 - f * 1.8 + sin(f * 9) * 0.4
                local i, j = S.world:toImage(x, cell.top + 0.6 + grain(k, tick, 3) * 1.5, z)
                P.put(grain(tick, k, 5) > 0.5 and IDX.w or IDX.c, floor(i), floor(j))
            end
        end
    end }
end

-- Everything of the demons' on the board, onto `list` (src/ui/board.lua
-- sorts what it draws, back to front).
function Abyss.things(me, list)
    local g = S.game
    if not g or not Cat.is(g, "demons") then return end
    for id, what in pairs(g.cataclysm.marks or {}) do
        local cell = g.cells[id]
        if me.explored[id] then
            if what == "tentacle" then stirring(cell, list) else splitting(cell, what == "citadel", list) end
        end
    end
    for _, l in ipairs(g.lairs) do
        if l.kind == "rift" and me.visible[l.cell] then flicker(g.cells[l.cell], list) end
    end
end

-- Onto the overlay over everything: the blood moon, at night, from the
-- omen on.
function Abyss.draw()
    local g = S.game
    if not g or not S.world or not Cat.is(g, "demons") or not Cat.stage(g) then return end
    local Daylight = require "src.ui.daylight"
    local night = Daylight.at(Daylight.now()).night
    if night < 0.4 then return end
    local x, y = floor(S.cw * 0.18), floor(S.ch * 0.14)
    local r = 7
    local tick = floor(S.clock * 2)
    for b = -r - 2, r + 2 do
        for a = -r - 2, r + 2 do
            local d = math.sqrt(a * a + b * b)
            if d <= r - 1 then
                local k = IDX.u
                if grain(a, b, 7) > 0.8 then k = IDX.n end
                if d > r - 2.5 and a < 0 then k = IDX.k end
                P.putS(k, x + a, y + b)
            elseif d <= r + 0.5 then
                P.putS(IDX.c, x + a, y + b)
            elseif d <= r + 2 and grain(a, b, tick) > 0.7 then
                P.putS(IDX.s, x + a, y + b)
            end
        end
    end
end

-- The lamps of the demons for the night: the citadel's eye and gate, every
-- rift, and what is coming up. `out` and `sig` as Daylight.lamps keeps them.
function Abyss.lamps(w, me, out, sig)
    local g = S.game
    if not g or not Cat.is(g, "demons") then return end
    for _, l in ipairs(g.lairs) do
        if l.def.demon and me.explored[l.cell] then
            local cell = g.cells[l.cell]
            local i, j = w:toImage(cell.x, cell.top, cell.z)
            local r = l.def.citadel and 36 or 20
            out[#out + 1] = { floor(i), floor(j) - (l.def.citadel and 14 or 2), r }
            sig[#sig + 1] = "d" .. cell.id .. ":" .. r
        end
    end
    for id, what in pairs(g.cataclysm.marks or {}) do
        if me.explored[id] and what ~= "tentacle" then
            local cell = g.cells[id]
            local i, j = w:toImage(cell.x, cell.top, cell.z)
            out[#out + 1] = { floor(i), floor(j) - 2, 16 }
            sig[#sig + 1] = "m" .. id
        end
    end
end

return Abyss
