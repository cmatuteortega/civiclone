-- Deer at the edges of the forests: on some open hexes beside a forest, one
-- or two graze, look up, wander a few steps. When anyone comes within a hex
-- of them they bound off into the trees and are gone, and come back out a
-- while after the hex is quiet again.
--
-- Nothing of this is in the game's rules or its save: the deer are the
-- screen's alone, and found again from the map whenever it changes.

local H = require "src.hex"
local M = require "src.models"
local S = require "src.ui.state"
local Sea = require "src.ui.sea"

local floor, sin, sqrt, atan2 = math.floor, math.sin, math.sqrt, math.atan2

local Wild = {}

local SHARE = 0.3    -- of the open hexes beside a forest, how many have deer
local WALK = 3       -- room units a second, grazing about
local RUN = 26       -- and bounding off
local QUIET = 12     -- seconds a hex must be left alone before they come back
local ROAM = 4.5     -- how far from its spot a deer wanders

local function grain(a, b)
    local n = sin(a * 12.9898 + b * 78.233) * 43758.5453
    return n - floor(n)
end

local herds, foundAt, foundIn = {}, -1, nil

-- The facing (0..5) nearest the way from (dx, dz).
local function facing(dx, dz)
    return floor(math.deg(atan2(dz, dx)) / 60 + 0.5) % 6
end

-- Where deer live: open, flat grass or plains, nothing built, beside a forest.
local function find(g)
    local found = {}
    for _, cell in ipairs(g.cells) do
        if (cell.terrain == "grass" or cell.terrain == "plains") and cell.elev == "flat" and not cell.feature
            and not cell.city and not cell.improvement and grain(cell.id, 3) < SHARE then
            local woods
            for k = 0, 5 do
                local n = g:cell(H.step(cell.c, cell.r, (k + floor(grain(cell.id, 4) * 6)) % 6))
                if n and n.feature == "forest" and not n.city then woods = n break end
            end
            if woods then
                local old = herds[cell.id]
                if old and old.woods == woods then
                    found[cell.id] = old
                else
                    -- Their spot: a third of the way from the middle to the trees.
                    local sx = cell.x + (woods.x - cell.x) * 0.3
                    local sz = cell.z + (woods.z - cell.z) * 0.3
                    local herd = { cell = cell, woods = woods, sx = sx, sz = sz, deer = {}, gone = false, quiet = 0 }
                    for n = 1, 1 + floor(grain(cell.id, 5) * 2) do
                        herd.deer[n] = { x = sx + (n - 1.5) * 4, z = sz + (n - 1) * 2, face = floor(grain(cell.id, n) * 6),
                            pose = 1, wait = grain(n, cell.id) * 4, stag = grain(cell.id, n + 9) > 0.6 }
                    end
                    found[cell.id] = herd
                end
            end
        end
    end
    herds = found
end

-- Is anyone on the hex or next to it?
local function disturbed(g, cell)
    for _, n in ipairs(g:within(cell, 1)) do
        if g.mil[n.id] or g.civ[n.id] then return true end
    end
    return false
end

local function graze(herd, d, dt)
    if d.tx then
        local dx, dz = d.tx - d.x, d.tz - d.z
        local len = sqrt(dx * dx + dz * dz)
        local step = WALK * dt
        if len <= step then
            d.x, d.z, d.tx, d.tz = d.tx, d.tz, nil, nil
            d.pose, d.wait = 1, 3 + grain(d.x, d.z) * 4
        else
            d.x, d.z = d.x + dx / len * step, d.z + dz / len * step
            d.face = facing(dx, dz)
            d.walk = (d.walk or 0) + dt * 5
            d.pose = 2 + floor(d.walk) % 2
        end
        return
    end
    d.wait = d.wait - dt
    if d.wait > 0 then
        -- Looks up now and then while it grazes.
        d.pose = (d.wait % 4 < 0.9) and 0 or 1
        return
    end
    local a = grain(d.x * 3, d.z + S.clock) * math.pi * 2
    local r = ROAM * grain(d.z, d.x * 7)
    d.tx, d.tz = herd.sx + math.cos(a) * r, herd.sz + math.sin(a) * r
end

function Wild.update(dt)
    local g = S.game
    if not g or Sea.still() then return end
    -- Found again each turn and whenever a hex changes.
    local stamp = g.turn * 1000 + (S.world.version or 0)
    if g ~= foundIn then herds, foundIn = {}, g end
    if stamp ~= foundAt then find(g) foundAt = stamp end
    for _, herd in pairs(herds) do
        local near = disturbed(g, herd.cell)
        if near then herd.quiet = 0 else herd.quiet = herd.quiet + dt end
        if herd.gone then
            if herd.quiet > QUIET then
                -- Out of the trees again, to their spot.
                herd.gone = false
                for _, d in ipairs(herd.deer) do
                    d.x, d.z, d.tx, d.tz, d.running = herd.woods.x, herd.woods.z, nil, nil, nil
                    d.tx, d.tz = herd.sx + (grain(d.face, herd.cell.id) - 0.5) * ROAM, herd.sz
                end
            end
        else
            local left = 0
            for _, d in ipairs(herd.deer) do
                if near and not d.running then
                    d.running, d.tx, d.tz = true, nil, nil
                end
                if d.running then
                    local dx, dz = herd.woods.x - d.x, herd.woods.z - d.z
                    local len = sqrt(dx * dx + dz * dz)
                    if len > 3 then
                        d.x, d.z = d.x + dx / len * RUN * dt, d.z + dz / len * RUN * dt
                        d.face = facing(dx, dz)
                        d.walk = (d.walk or 0) + dt * 10
                        d.pose = 2 + floor(d.walk) % 2
                        left = left + 1
                    end
                else
                    graze(herd, d, dt)
                    left = left + 1
                end
            end
            if left == 0 then herd.gone = true end
        end
    end
end

-- Adds what is to be drawn to the board's list of things standing up: a
-- deer where the player can see.
function Wild.things(list, me, stamp)
    if Sea.still() then return end
    for _, herd in pairs(herds) do
        if not herd.gone and me.visible[herd.cell.id] then
            for _, d in ipairs(herd.deer) do
                local y = herd.cell.top
                list[#list + 1] = { z = d.z, draw = function()
                    stamp(M.deer(d.face, d.pose, d.stag), d.x, y, d.z)
                end }
            end
        end
    end
end

return Wild
