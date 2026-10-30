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

-- A farm's furrows: every other band of its top a step darker.
local function furrows(cell)
    local w = S.world
    P.eachTop(cell, function(i, j, n)
        if floor((w.wx[n] - w.wz[n] * 0.4) / 2.4) % 2 == 0 and H.inset(w.wx[n], w.wz[n], cell.x, cell.z) > 2.5 then
            local k = w.key[n]
            P.put(T.DARKER[k], i, j)
        end
    end)
end

-- A hex's top a step lighter, every other pixel: where a unit can go.
local function lighten(cell, step)
    P.eachTop(cell, function(i, j, n)
        if (i + j) % step == 0 then
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

local function things(me)
    local g = S.game
    local list = {}
    for _, cell in ipairs(g.cells) do
        if cell.improvement and me.explored[cell.id] then
            if cell.improvement == "farm" then furrows(cell) end
            list[#list + 1] = { z = cell.z - 1, draw = function()
                P.stamp(cell.improvement == "farm" and M.farm() or M.mine(), cell.x, cell.top, cell.z)
            end }
        end
    end
    for _, c in ipairs(g.cities) do
        local cell = g.cells[c.cell]
        if me.explored[cell.id] then
            list[#list + 1] = { z = cell.z, draw = function()
                local pic = M.city(lookOf(c.owner), c.pop, c.capital, c.buildings)
                P.stamp(pic, cell.x, cell.top, cell.z, c.flash and T.FLASH or nil)
            end }
        end
    end
    for _, u in ipairs(g.units) do
        if u.owner == 1 or me.visible[u.cell] then
            local x, y, z, face, pose = Anim.place(g, u)
            local a = Anim.of(u)
            list[#list + 1] = { z = z + 0.1, draw = function()
                local remap = a.flash and floor(a.flash * 20) % 2 == 0 and T.FLASH or nil
                if u.fortified and not remap then remap = nil end
                P.stamp(M.unit(u.kind, lookOf(u.owner), face, pose), x, y, z, remap)
            end }
        end
    end
    for _, e in ipairs(S.effects) do
        if e.kind == "death" and floor(e.t * 12) % 2 == 0 then
            list[#list + 1] = { z = e.z, draw = function()
                P.stamp(M.unit(e.unit.kind, lookOf(e.unit.owner), e.face, 0), e.x, e.y, e.z, T.FLASH)
            end }
        end
    end
    table.sort(list, function(a, b) return a.z < b.z end)
    for _, t in ipairs(list) do t.draw() end
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

    love.graphics.setCanvas(S.canvas)
    love.graphics.clear(T.RGB[IDX.o])
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(w.image, -floor(S.camx), -floor(S.camy))
    love.graphics.draw(S.overlayImage, 0, 0)
end

return Board
