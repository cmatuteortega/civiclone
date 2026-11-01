-- The still sun's great storm (src/stillsun.lua), as it is seen: each
-- cyclone a wheel of cloud turning over the land, its arms wound in a
-- spiral round a dark eye, its shadow on the ground under it and dust and
-- leaves torn up round its foot; and where it will strike as the next turn
-- begins, the turn before, its eye's hex and the ring round it marked on
-- the ground in arcs turning the way the wind does.
--
-- A cyclone moves a hex or two a turn; the screen slides it there over a
-- second or so, from where it was drawn last. The rain and the lightning
-- are the deluge's (src/ui/rain.lua asks Storm.want).

local T = require "src.tracer"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local H = require "src.hex"
local D = require "src.defs"
local Cat = require "src.cataclysm"
local Sun = require "src.stillsun"

local floor, sin, cos, min, max, sqrt, pi = math.floor, math.sin, math.cos, math.min, math.max, math.sqrt, math.pi
local IDX = T.IDX

local Storm = {}

local SPIN = 1.7      -- turns of the wheel a second, in radians
local HIGH = 22       -- how high over the ground the cloud stands
local REACH = 2.1     -- how far its arms reach, in hexes across
local ARMS = 3

local shown = {}      -- where each cyclone is drawn now: { x, z }, by id
local last            -- the clock when it was last drawn

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

-- Canvas pixel of a room point.
local function screen(x, y, z)
    local i, j = S.world:toImage(x, y, z)
    return i - floor(S.camx), j - floor(S.camy)
end

-- How hard it rains under the storm: from as the cyclones form.
function Storm.want(game)
    if not game or not Sun.storming(game) then return 0 end
    return game.turn >= D.SUN.storm and 0.85 or 0.5
end

--- what is coming ---------------------------------------------------------------------

-- A hex the storm strikes as the next turn begins: arcs turning on its
-- ground, the way the wind turns; the eye's hex also ringed.
local function coming(cell, mark, list)
    local w = S.world
    list[#list + 1] = { z = cell.z - 1.5, draw = function()
        local ph = S.clock * SPIN * 0.5
        P.eachTop(cell, function(i, j, n)
            local x, z = w.wx[n] - cell.x, w.wz[n] - cell.z
            local d = sqrt(x * x + z * z) / H.APOTHEM
            if d > 1.02 then return end
            local a = math.atan2(z, x)
            -- Arcs wound in a spiral, broken.
            local v = (a + ph + d * 2.4) / (2 * pi) * (mark == "eye" and 4 or 3)
            local fv = v - floor(v)
            if fv < 0.1 and (i + j) % 2 == 0 then P.put(IDX.o, i, j)
            elseif fv < 0.16 and mark == "eye" then P.put(IDX.c, i, j) end
        end)
        if mark == "eye" then
            P.hexLine(cell, function(f) return floor(f * 18 - S.clock * 8) % 3 == 0 and IDX.w or IDX.o end, 0.5, 0.3)
        else
            P.hexLine(cell, function(f) return floor(f * 18 - S.clock * 8) % 3 == 0 and IDX.o or nil end, 0.5, 0.3)
        end
    end }
end

--- the cyclones -----------------------------------------------------------------------

-- A blob of cloud at canvas pixel (x, y), `r` across: lit from the
-- north-west, its underside dark. `edge` draws only its ink rim (all the
-- rims go down first, so where blobs overlap the ink is covered and only
-- the arm's outline shows).
local function puff(x, y, r, seed, thin, edge)
    for b = -floor(r) - 1, floor(r) + 1 do
        for a = -floor(r) - 1, floor(r) + 1 do
            local dd = a * a + b * b
            if dd <= (r + 1) * (r + 1) and grain(a, b, seed) >= thin then
                if dd > r * r then
                    if edge then P.putS(IDX.o, floor(x) + a, floor(y) + b) end
                elseif not edge then
                    local k = (b < -r * 0.25 and a < r * 0.4) and IDX.w or (b > r * 0.45) and IDX.s or IDX.c
                    P.putS(k, floor(x) + a, floor(y) + b)
                end
            end
        end
    end
end

-- A cyclone over room point (x, z) on ground `top`.
local function wheel(id, x, top, z, list)
    list[#list + 1] = { z = z + 60, draw = function()
        local gx, gy = screen(x, top, z)
        if gx < -120 or gy < -160 or gx > S.cw + 120 or gy > S.ch + 120 then return end
        local cx, cy = screen(x, top + HIGH, z)
        local ex = screen(x + H.W * REACH, top + HIGH, z)
        local R = max(8, ex - cx)
        local se = T.SE
        local rot = S.clock * SPIN + id * 1.3
        -- Its shadow on the ground, dithered, turning with it.
        for k = 1, 260 do
            local f = grain(k, id, 11)
            local a = grain(id, k, 12) * 2 * pi - rot * 0.8
            local r = R * (0.2 + f * 0.85)
            local px, py = gx + cos(a + f * 2.6) * r, gy + sin(a + f * 2.6) * r * se
            P.putS(IDX.u, floor(px), floor(py))
        end
        -- Dust and leaves torn up round its foot, whirling.
        for k = 1, 40 do
            local a = grain(k, id, 13) * 2 * pi + rot * (1.6 + grain(id, k, 14))
            local r = R * (0.25 + grain(k, k, id) * 0.6)
            local up = grain(k, id, 15) * (cy - gy) * 0.8
            P.putS(k % 3 == 0 and IDX.n or IDX.t, floor(gx + cos(a) * r), floor(gy + sin(a) * r * se + up))
        end
        -- The arms, wound in to the eye, thickest near it; their tails
        -- thin to wisps.
        local blobs = {}
        for arm = 0, ARMS - 1 do
            local n = 28
            for s = 0, n do
                local f = s / n
                local a = rot + arm * 2 * pi / ARMS + f * 4.2
                local r = R * (0.1 + 0.95 * f)
                blobs[#blobs + 1] = { cx + cos(a) * r, cy + sin(a) * r * se, max(1.2, R * (0.1 * (1 - f) + 0.025)),
                    arm * 31 + s, f }
            end
        end
        -- The back of the wheel first.
        table.sort(blobs, function(a, b) return a[2] < b[2] end)
        for _, q in ipairs(blobs) do puff(q[1], q[2], q[3], q[4] + id, 0.1 + q[5] * 0.7, true) end
        for _, q in ipairs(blobs) do puff(q[1], q[2], q[3], q[4] + id, 0.1 + q[5] * 0.7) end
        -- The eye: dark, ringed pale.
        local er = max(2, R * 0.06)
        for b = -floor(er) - 1, floor(er) + 1 do
            for a = -floor(er) - 1, floor(er) + 1 do
                local dd = a * a + (b / se) * (b / se)
                if dd <= er * er then P.putS(IDX.o, floor(cx) + a, floor(cy) + b)
                elseif dd <= (er + 1.4) * (er + 1.4) then P.putS(IDX.w, floor(cx) + a, floor(cy) + b) end
            end
        end
    end }
end

-- Onto the board's list: what is coming, and the cyclones.
function Storm.things(me, list)
    local g = S.game
    if not g or not S.world or not Sun.storming(g) then return end
    local c = g.cataclysm
    for id, mark in pairs(c.stormMarks or {}) do
        if me.explored[id] then coming(g.cells[id], mark, list) end
    end
    local now = S.clock or 0
    local dt = last and min(0.25, max(0, now - last)) or 1
    last = now
    local live = {}
    for _, cy in ipairs(Sun.cyclones(g)) do
        local cell = g.cells[cy.cell]
        live[cy.id] = true
        local at = shown[cy.id]
        if not at or S.plan then
            at = { cell.x, cell.z }
            shown[cy.id] = at
        else
            local k = min(1, dt * 1.6)
            at[1], at[2] = at[1] + (cell.x - at[1]) * k, at[2] + (cell.z - at[2]) * k
        end
        local under = g:cell(H.at(at[1], at[2])) or cell
        if me.explored[under.id] or me.explored[cell.id] then
            wheel(cy.id, at[1], max(under.top, D.TERRAIN.coast.top), at[2], list)
        end
    end
    for id in pairs(shown) do if not live[id] then shown[id] = nil end end
end

return Storm
