-- The board drawn each frame: the map's picture (rebuilt when what the player
-- has seen changes), then the overlay over it -- borders, furrows and the
-- marks of what is selected on the ground first, then improvements, cities
-- and units standing up, furthest first. The banners over cities and units
-- and the numbers of a fight are drawn apart, onto the HUD's canvas, so they
-- are the HUD's size rather than the map's.

local ffi = require "ffi"
local T = require "src.tracer"
local H = require "src.hex"
local M = require "src.models"
local D = require "src.defs"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Draw = require "src.ui.draw"
local Anim = require "src.ui.anim"
local Font = require "src.font"
local View = require "src.ui.view"
local Sea = require "src.ui.sea"
local World = require "src.world"
local Daylight = require "src.ui.daylight"
local Smoke = require "src.ui.smoke"
local Wild = require "src.ui.wild"
local Birds = require "src.ui.birds"

local floor, min = math.floor, math.min
local IDX = T.IDX

local Board = {}

-- How each civilization's banners and borders are drawn.
Board.TEAM = {
    light = { fill = "w", ink = "o", line = function() return IDX.w end },
    dark = { fill = "u", ink = "w", line = function() return IDX.o end },
    stripe = { fill = "t", ink = "o", band = "u",
        line = function(f) return floor(f * 6) % 2 == 0 and IDX.w or IDX.o end },
}

local function lookOf(owner) return S.game.players[owner].civ.look end

--- on the ground ---------------------------------------------------------------

-- Each owned hex's edges that face another owner's hex or none: drawn a
-- little inside, in the owner's line.
local function borders(me)
    local g = S.game
    for _, cell in ipairs(g.cells) do
        if cell.owner and me.explored[cell.id] then
            local team = Board.TEAM[lookOf(cell.owner)]
            local r = H.R - 1.6
            local y = cell.top + 0.3
            for e = 0, 5 do
                local n = g:cell(H.step(cell.c, cell.r, e))
                if not n or n.owner ~= cell.owner then
                    local a0, a1 = math.rad(60 * e - 30), math.rad(60 * e + 30)
                    P.line3(cell.x + r * math.cos(a0), y, cell.z + r * math.sin(a0),
                        cell.x + r * math.cos(a1), y, cell.z + r * math.sin(a1), team.line)
                end
            end
        end
    end
end

-- A farm's crop rows: bands across its top, a ridge a step lighter, then a
-- furrow a step darker, then the ground's own, running the way its layout
-- says. Light against dark shows on grassland as well as on plains.
local function furrows(cell, layout, seen)
    local w = S.world
    local a = math.rad(layout.rows)
    local ca, sa = math.cos(a), math.sin(a)
    local kind, river = w.buf.kind, World.LAND.river
    P.eachTop(cell, function(i, j, n)
        local x, z = w.wx[n], w.wz[n]
        if H.inset(x, z, cell.x, cell.z) > 2.5 and kind[n] ~= river then
            local band = floor((x * ca + z * sa) / 1.6) % 3
            local k = w.key[n]
            if band == 0 then k = T.LIGHTER[k] elseif band == 1 then k = T.DARKER[k] end
            if band ~= 2 or not seen then P.put(seen and k or T.DARKER[k], i, j) end
        end
    end)
end

-- The edges of a farm that face another farm: left open, so they read as
-- one field. And those along a river, which is its bound there.
local function farmOpen(cell)
    local open = {}
    for e = 0, 5 do
        local n = S.game:cell(H.step(cell.c, cell.r, e))
        if (n and n.improvement == "farm") or (cell.river and cell.river[e]) then open[e] = true end
    end
    return open
end

-- A hex's top a step lighter, every other pixel: where a unit can go. On
-- the sea, a mark for the moving water to lighten itself by.
local function lighten(cell, step)
    local sea, kind = Sea.shader and S.world.buf.sea, S.world.buf.kind
    P.eachTop(cell, function(i, j, n)
        if (i + j) % step == 0 and sea and (sea[n] ~= 0 or kind[n] == World.LAND.river) then
            P.lift(1, i, j)
        elseif (i + j) % step == 0 then
            local k = S.world.key[n]
            if S.game.players[1].visible[cell.id] then P.put(T.LIGHTER[k], i, j) else P.put(k, i, j) end
        end
    end)
end

--- the selection's marks ---------------------------------------------------------

local function selectedUnit()
    local u = S.selected and S.selected.unit
    if u and u.dead then S.selected = nil return nil end
    return u
end
Board.selectedUnit = selectedUnit

-- Where the selected unit could go this turn, and what it could hit.
local function marks()
    S.hoverTurns = nil
    local g = S.game
    local u = selectedUnit()
    if u and u.owner == 1 and not Anim.busy() then
        if u.moves > 0 then
            local reach = g:reach(u)
            for id, r in pairs(reach) do
                if id ~= u.cell and not r.through then lighten(g.cells[id], 2) end
            end
            local cell = g.cells[u.cell]
            local range = u.def.ranged and u.def.range or 1
            for _, n in ipairs(g:within(cell, range)) do
                if g:canAttack(u, n) and g.players[1].visible[n.id] then
                    P.hexLine(n, function(f) return floor(S.clock * 4) % 2 == 0 and IDX.o or IDX.w end, 1)
                end
            end
        end
        P.hexLine(g.cells[u.cell], IDX.w, 0.5)
        -- The way to the hex under the pointer.
        local hover = S.hover
        if hover and hover.id ~= u.cell and g.players[1].explored[hover.id] then
            local attack = g:foreignAt(hover, 1) ~= nil
            local path = S.pathFor(u, hover, attack)
            if path then
                local last = u.cell
                for _, id in ipairs(path) do
                    local a, b = g.cells[last], g.cells[id]
                    P.line3(a.x, a.top + 1, a.z, b.x, b.top + 1, b.z,
                        function(f, i, j) if (i + j) % 2 == 0 then return IDX.w end end)
                    last = id
                end
                P.hexLine(hover, attack and IDX.o or IDX.w, 1)
            end
        end
    elseif S.selected and S.selected.city then
        local c = S.selected.city
        local g2 = S.game
        for _, id in ipairs(c.worked) do lighten(g2.cells[id], 3) end
        P.hexLine(g2.cells[c.cell], IDX.w, 0.5)
    end
    if S.hover and not u then P.hexLine(S.hover, IDX.c, 0.5) end
end

--- standing up -----------------------------------------------------------------

-- Which step of its turn a mine's wheel is at: it winds a load up for a few
-- seconds, rests, lets the cage down, rests, each mine at its own moment.
local WIND, REST = 3.5, 2.5
local function wheelStep(cell)
    local t = (Sea.air() + cell.id * 1.7) % (2 * (WIND + REST))
    local turns = 2 * M.WHEEL_STEPS -- steps in one winding
    local f
    if t < WIND then f = t / WIND
    elseif t < WIND + REST then f = 1
    elseif t < 2 * WIND + REST then f = 1 - (t - WIND - REST) / WIND
    else f = 0 end
    f = f * f * (3 - 2 * f)
    return floor(f * turns) % M.WHEEL_STEPS
end

-- How far up a unit standing idle is drawn: a breath, a pixel up for a
-- moment every few seconds, no two units together. Not a fortified one.
local function breath(u, a)
    if Sea.still() or u.fortified or #a.queue > 0 or a.lunge then return 0 end
    local period = 3 + (u.id % 5) * 0.23
    local t = (Sea.air() + u.id * 0.77) % period
    return t < 0.45 and 0.7 or 0
end

-- How a boat heels on the swell now: -1, 0 or 1, each its own time, still
-- while it moves or when the water is set still.
local function roll(seed, a)
    if Sea.still() or (a and (#a.queue > 0 or a.lunge)) then return 0 end
    local v = math.sin(Sea.time() * 1.25 + seed * 1.71)
    return v > 0.55 and 1 or (v < -0.55 and -1 or 0)
end

-- Now and then a fish over a fish hex leaps, and rings spread where it fell.
local LEAP, RINGS = 0.8, 1.6
local function fish(cell, list)
    if Sea.still() then return end
    local period = 5 + (cell.id % 7) * 0.7
    local t = (Sea.time() + cell.id * 1.37) % period
    local ox = ((cell.id * 7) % 9 - 4) * 1.2
    local oz = ((cell.id * 5) % 7 - 3) * 1.1
    local dir = cell.id % 2 == 0 and 1 or -1
    if t < LEAP then
        local f = t / LEAP
        local x, y, z = cell.x + ox + (f - 0.5) * 12 * dir, cell.top + math.sin(f * math.pi) * 7, cell.z + oz
        local bend = f < 0.4 and -1 or (f > 0.6 and 1 or 0)
        list[#list + 1] = { z = z, draw = function() P.stamp(M.fish(bend, dir), x, y, z) end }
    elseif t < LEAP + RINGS then
        -- Two rings growing out from the splash, lifting the water a step.
        local age = (t - LEAP) / RINGS
        local cx, cz = cell.x + ox + 6 * dir, cell.z + oz
        for _, r in ipairs({ 1 + age * 5, age * 3 }) do
            if r > 0.5 then
                local n = floor(r * 5) + 6
                for k = 0, n - 1 do
                    local a = k * 2 * math.pi / n
                    local i, j = S.world:toImage(cx + math.cos(a) * r, cell.top, cz + math.sin(a) * r * 0.8)
                    P.lift(1, floor(i), floor(j))
                end
            end
        end
    end
end

-- Rings on the water at (x, y, z), growing with `age` (0..1), lifting it a
-- step: a fish come down, a heron's strike, a soldier wading in.
local function rings(x, y, z, age, size)
    for _, r in ipairs({ (1 + age * 4) * size, age * 2.4 * size }) do
        if r > 0.5 then
            local n = floor(r * 5) + 6
            for k = 0, n - 1 do
                local a = k * 2 * math.pi / n
                local i, j = S.world:toImage(x + math.cos(a) * r, y, z + math.sin(a) * r * 0.8)
                P.lift(1, floor(i), floor(j))
            end
        end
    end
end

-- The rivers' edges, each once, for the fish in them: found again when the
-- game is a new one.
local riverEdges, edgesOf
local function edgesIn(g)
    if edgesOf == g then return riverEdges end
    riverEdges, edgesOf = {}, g
    for _, cell in ipairs(g.cells) do
        for k = 0, 5 do
            local e = cell.river and cell.river[k]
            local n = e and g:cell(H.step(cell.c, cell.r, k))
            if n and n.id > cell.id then
                local fx, fz = e.to[1] - e.from[1], e.to[2] - e.from[2]
                local l = math.sqrt(fx * fx + fz * fz)
                riverEdges[#riverEdges + 1] = { e = e, a = cell, b = n, id = cell.id * 6 + k,
                    x = (e.from[1] + e.to[1]) / 2, z = (e.from[2] + e.to[2]) / 2, fx = fx / l, fz = fz / l }
            end
        end
    end
    return riverEdges
end

-- In a few of the rivers' edges, now and then a fish leaps upstream and
-- falls back with a ring.
local function riverFish(me, list)
    if Sea.still() then return end
    for _, r in ipairs(edgesIn(S.game)) do
        if r.id % 4 == 1 and (me.visible[r.a.id] or me.visible[r.b.id]) and not r.a.city and not r.b.city then
            local period = 7 + (r.id % 9) * 0.8
            local t = (Sea.time() + r.id * 1.91) % period
            local y0 = r.e.level
            if t < LEAP * 0.8 then
                local f = t / (LEAP * 0.8)
                -- Against the stream.
                local x = r.x - r.fx * (f - 0.5) * 6
                local z = r.z - r.fz * (f - 0.5) * 6
                local y = y0 + math.sin(f * math.pi) * 4.5
                local bend = f < 0.4 and -1 or (f > 0.6 and 1 or 0)
                local dir = r.fx > 0 and -1 or 1
                list[#list + 1] = { z = z, draw = function() P.stamp(M.fish(bend, dir), x, y, z) end }
            elseif t < LEAP * 0.8 + RINGS then
                rings(r.x - r.fx * 3, y0, r.z - r.fz * 3, (t - LEAP * 0.8) / RINGS, 0.7)
            end
        end
    end
end

-- A splash where someone wades into a river: drops thrown up and falling
-- back, white, and rings going out.
local function splash(e, list)
    local f = e.t / e.life
    rings(e.x, e.y, e.z, f, 0.9)
    if f < 0.6 then
        list[#list + 1] = { z = e.z + 0.2, draw = function()
            for k = 0, 7 do
                local a = k * 0.785 + e.seed
                local sp = 2.2 + (k % 3) * 0.8
                local tt = e.t * 1.6
                local x = e.x + math.cos(a) * sp * tt * 2
                local z = e.z + math.sin(a) * sp * tt * 1.4
                local y = e.y + 0.5 + (4 + (k % 2) * 2) * tt - 14 * tt * tt
                if y > e.y then
                    local i, j, d = S.world:toImage(x, y, z)
                    if P.visible(floor(i), floor(j), d) then P.put(k % 3 == 0 and T.IDX.c or T.IDX.w, i, j) end
                end
            end
        end }
    end
end

-- The wakes: from each mark the foam spreads out to either side as it ages,
-- a V behind the boat, churned white close astern and thinning to a step of
-- lightness, then to nothing, broken up the older it gets. Only on water
-- the player sees; nothing when the water is set still.
local function hash(a, b)
    local v = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
    return v - floor(v)
end
local function wakes(me)
    if Sea.still() or #S.wakes == 0 then return end
    local g = S.game
    for _, w in ipairs(S.wakes) do
        local cell = g:cell(H.at(w.x, w.z))
        if cell and g:isWater(cell) and me.visible[cell.id] then
            local f = w.t / Anim.WAKE_LIFE
            local px, pz = -w.dz, w.dx
            local spread = (w.big and 1.6 or 1) + f * (w.big and 7 or 4.5)
            local steps = f < 0.45 and 2 or 1
            for _, side in ipairs({ -1, 1 }) do
                for k = 0, 2 do
                    if hash(w.seed + k, side) > f * f * 0.95 then
                        local x = w.x + px * spread * side - w.dx * k * 0.5
                        local z = w.z + pz * spread * side - w.dz * k * 0.5
                        local i, j = S.world:toImage(x, -2, z)
                        P.lift(steps, floor(i), floor(j))
                    end
                end
            end
            -- Churned water right astern, while it is new.
            if f < 0.4 then
                for k = 0, 3 do
                    local r = hash(w.seed, k + 7) * 2 - 1
                    local x, z = w.x + px * r * spread * 0.6, w.z + pz * r * spread * 0.6
                    local i, j = S.world:toImage(x, -2, z)
                    P.lift(2, floor(i), floor(j))
                end
            end
        end
    end
end

-- Fishing boats at work: the two fishers haul the net in turns, its floats
-- bob, and every so often a fish comes up out of it, flapping, and is swung
-- into the first boat, the water ringing where it left.
local HAUL = 0.45 -- seconds to a step of the haul
local CATCH, SWING = 9, 0.9
local function fishing(cell, me, list)
    local look = lookOf(cell.owner or 1)
    local seen = me.visible[cell.id] and not Sea.still()
    local phase = seen and floor(Sea.time() / HAUL + cell.id) % 4 or 0
    local pic = M.fishingBoats(look, seen and roll(cell.id) or 0, phase)
    list[#list + 1] = { z = cell.z - 1, draw = function() P.stamp(pic, cell.x, cell.top, cell.z) end }
    if not seen then return end
    local period = CATCH + (cell.id % 5) * 1.3
    local t = (Sea.time() + cell.id * 2.1) % period
    local s = M.UNIT_SCALE
    -- From the middle of the net to the first boat.
    local x0, z0 = cell.x + 0.2 * s, cell.z + 2.4 * s
    local x1, z1 = cell.x - 5.2 * s, cell.z - 1.2 * s
    if t < SWING then
        local f = t / SWING
        local x = x0 + (x1 - x0) * f
        local z = z0 + (z1 - z0) * f
        local y = cell.top + math.sin(f * math.pi) * 6 + f * 1.5
        local bend = floor(t * 12) % 2 == 0 and -1 or 1
        local face = x1 < x0 and -1 or 1
        list[#list + 1] = { z = z + 0.5, draw = function() P.stamp(M.fish(bend, face), x, y, z) end }
    end
    if t < SWING + 1.2 then
        -- The ring where it came up.
        local r = 0.8 + t * 3
        local n = floor(r * 5) + 6
        for k = 0, n - 1 do
            local a = k * 2 * math.pi / n
            local i, j = S.world:toImage(x0 + math.cos(a) * r, cell.top, z0 + math.sin(a) * r * 0.8)
            P.lift(1, floor(i), floor(j))
        end
    end
end

local function things(me)
    local g = S.game
    wakes(me)
    local list = {}
    for _, cell in ipairs(g.cells) do
        if cell.improvement == "boats" and me.explored[cell.id] then
            fishing(cell, me, list)
        elseif cell.improvement and me.explored[cell.id] then
            local pic
            if cell.improvement == "farm" then
                local layout = M.farmLayout(cell.id)
                furrows(cell, layout, me.visible[cell.id])
                pic = M.farm(layout, farmOpen(cell))
            else
                pic = M.mine(cell.elev == "hills")
            end
            list[#list + 1] = { z = cell.z - 1, draw = function()
                P.stamp(pic, cell.x, cell.top, cell.z)
                if cell.improvement == "mine" then
                    local step = me.visible[cell.id] and wheelStep(cell) or 0
                    P.stamp(M.mineWheel(cell.elev == "hills", step), cell.x, cell.top, cell.z)
                end
                if me.visible[cell.id] then Smoke.improvement(cell) end
            end }
        end
    end
    for _, cell in ipairs(g.cells) do
        if cell.resource == "fish" and cell.improvement ~= "boats" and me.visible[cell.id] then fish(cell, list) end
    end
    riverFish(me, list)
    for _, e in ipairs(S.effects) do
        if e.kind == "splash" then splash(e, list) end
    end
    for _, c in ipairs(g.cities) do
        local cell = g.cells[c.cell]
        if me.explored[cell.id] then
            list[#list + 1] = { z = cell.z, draw = function()
                local shore = Anim.shore(g, cell)
                local pic = M.city(lookOf(c.owner), c.pop, c.capital, c.buildings, shore, shore and cell.top + 2)
                P.stamp(pic, cell.x, cell.top, cell.z, c.flash and T.FLASH or nil)
                if me.visible[cell.id] then Smoke.city(cell, c) end
            end }
        end
    end
    for _, u in ipairs(g.units) do
        if u.owner == 1 or me.visible[u.cell] then
            local x, y, z, face, pose = Anim.place(g, u)
            local a = Anim.of(u)
            -- On the water (a ship, or a land unit in a boat, by where it is
            -- drawn now): it heels on the swell rather than breathes.
            local under = g:cell(H.at(x, z))
            local afloat = u.def.sea or (under and g:isWater(under))
            local boat = afloat and not u.def.sea
            local heel = afloat and roll(u.id, a) or 0
            if not afloat then y = y + breath(u, a) end
            list[#list + 1] = { z = z + 0.1, draw = function()
                local remap = a.flash and floor(a.flash * 20) % 2 == 0 and T.FLASH or nil
                if u.fortified and not remap then remap = nil end
                P.stamp(M.unit(u.kind, lookOf(u.owner), face, pose, heel, boat), x, y, z, remap)
            end }
        end
    end
    for _, e in ipairs(S.effects) do
        if e.kind == "death" and floor(e.t * 12) % 2 == 0 then
            list[#list + 1] = { z = e.z, draw = function()
                local boat = not e.unit.def.sea and g:isWater(g.cells[e.unit.cell])
                P.stamp(M.unit(e.unit.kind, lookOf(e.unit.owner), e.face, 0, 0, boat), e.x, e.y, e.z, T.FLASH)
            end }
        end
    end
    Wild.things(list, me, P.stamp)
    table.sort(list, function(a, b) return a.z < b.z end)
    for _, t in ipairs(list) do t.draw() end
    Birds.draw()
end

--- flat on top -----------------------------------------------------------------

-- HUD pixel of a room point.
local function screen(x, y, z)
    return View.toHud(S.world:toImage(x, y, z))
end

local function unitBanner(u)
    local g = S.game
    local x, y, z = Anim.place(g, u)
    local sx, sy = screen(x, y + 12 * M.UNIT_SCALE, z)
    -- Two on a hex: their banners side by side. In a city, under its banner.
    if #Anim.of(u).queue == 0 then
        if g.cells[u.cell].city then sx, sy = screen(x, y + 12, z) end
        local other = u.def.civilian and g.mil[u.cell] or g.civ[u.cell]
        if other and other ~= u and (other.owner == 1 or g.players[1].visible[u.cell]) then
            sx = sx + (u.def.civilian and -3 or 3)
        end
    end
    local team = Board.TEAM[lookOf(u.owner)]
    local bx, by = sx - 4, sy - 9
    local sel = selectedUnit() == u
    Draw.rect(sel and "w" or "o", bx - 1, by - 1, 9, 9)
    Draw.rect(team.fill, bx, by, 7, 7)
    if team.band then Draw.rect(team.band, bx, by, 7, 1) Draw.rect(team.band, bx, by + 6, 7, 1) end
    Draw.icon(u.kind, bx + 1, by + 1, team.ink)
    -- Moves left, for the player's own: a pip beside it.
    if u.owner == 1 and u.moves > 0 and not u.fortified then Draw.rect("w", bx + 8, by + 6, 1, 1) end
    if u.fortified then Draw.rect("c", bx + 8, by, 1, 3) end
    if u.hp < 100 then Draw.bar(bx - 1, by + 8, 9, u.hp / 100, u.hp > 50 and "w" or "s") end
end

local function cityBanner(c)
    local g = S.game
    local cell = g.cells[c.cell]
    local sx, sy = screen(cell.x, cell.top + 36, cell.z - 4)
    local team = Board.TEAM[lookOf(c.owner)]
    local name = c.name
    local tw = Font.width(name)
    local w = tw + 14 + (c.capital and 6 or 0)
    local x, y = sx - floor(w / 2), sy - 12
    Draw.rect("o", x - 1, y - 1, w + 2, 11)
    Draw.rect(team.fill, x, y, w, 9)
    if team.band then Draw.rect(team.band, x, y, w, 1) Draw.rect(team.band, x, y + 8, w, 1) end
    -- The population in a box of its own.
    Draw.rect("o", x, y, 9, 9)
    local pop = tostring(c.pop)
    Draw.text("w", pop, x + 5 - floor(Font.width(pop) / 2), y + 2)
    local tx = x + 11
    if c.capital then Draw.icon("star", tx, y + 2, team.ink) tx = tx + 6 end
    Draw.text(team.ink, name, tx, y + 2)
    -- Growth and production underneath, for the player's own.
    if c.owner == 1 then
        Draw.bar(x, y + 10, w, c.food / g:growthNeed(c), "c", "u")
        local def = c.build and (c.build.kind == "unit" and D.UNITS[c.build.id] or D.BUILDINGS[c.build.id])
        Draw.bar(x, y + 11, w, def and c.prod / def.cost or 0, "s", "n")
        if not c.build and floor(S.clock * 2) % 2 == 0 then Draw.rect("w", x + w + 2, y + 2, 1, 5) end
    end
    if c.hp < g:maxHp(c) then Draw.bar(x, y - 3, w, c.hp / g:maxHp(c), "w", "o") end
end

-- Onto the HUD's canvas, before the HUD itself so its panels stay on top.
function Board.banners()
    local g = S.game
    local me = g.players[1]
    for _, u in ipairs(g.units) do
        if u.owner == 1 or me.visible[u.cell] then unitBanner(u) end
    end
    for _, c in ipairs(g.cities) do
        if me.explored[c.cell] then cityBanner(c) end
    end
    -- Turns to the hex under the pointer.
    local u = selectedUnit()
    if u and S.hover and S.hoverTurns then
        local sx, sy = screen(S.hover.x, S.hover.top + 2, S.hover.z)
        local s = tostring(S.hoverTurns)
        Draw.rect("o", sx - 3, sy - 4, Font.width(s) + 4, 7)
        Draw.text("w", s, sx - 1, sy - 3)
    end
    for _, e in ipairs(S.effects) do
        local t = e.t - (e.delay or 0)
        if e.kind == "number" and t > 0 then
            local sx, sy = screen(e.x, e.y, e.z)
            sy = sy - floor(t * 10)
            Draw.shadowed("w", e.text, sx - floor(Font.width(e.text) / 2), sy)
        elseif e.kind == "shot" then
            local f = min(1, e.t / e.life)
            local x0, y0 = screen(e.x0, e.y0, e.z0)
            local x1, y1 = screen(e.x1, e.y1, e.z1)
            local x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f - math.sin(math.pi * f) * 8
            Draw.rect("o", x - 1, y - 1, 3, 3)
            Draw.rect("w", x, y, 1, 1)
        end
    end
end

function Board.draw()
    local g, w = S.game, S.world
    local me = g.players[1]
    if w.dirty or me.sightChanged or S.gridShown ~= S.grid then
        w:build(me.explored, me.visible, S.grid)
        me.sightChanged, S.gridShown = false, S.grid
    end
    ffi.fill(S.opx, S.cw * S.ch * 4, 0)
    borders(me)
    marks()
    things(me)
    S.overlayImage:replacePixels(S.overlay)
    Daylight.draw(w)

    love.graphics.setCanvas(S.canvas)
    love.graphics.clear(T.RGB[IDX.o])
    love.graphics.setColor(1, 1, 1)
    local moving = Sea.begin(w, S.overlayImage, floor(S.camx), floor(S.camy))
    if moving then Daylight.apply(Sea.shader, Sea.cover, S.cw) end
    love.graphics.draw(w.image, -floor(S.camx), -floor(S.camy))
    if moving then love.graphics.setShader(Sea.cover) end
    love.graphics.draw(S.overlayImage, 0, 0)
    love.graphics.setShader()
end

return Board
