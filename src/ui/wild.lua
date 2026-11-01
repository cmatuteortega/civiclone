-- Deer at the edges of the forests: on some open hexes beside a forest, one
-- or two graze, look up, wander a few steps. When anyone comes within a hex
-- of them they bound off into the trees and are gone, and come back out a
-- while after the hex is quiet again.
--
-- And sheep on half the farms, two to four of them grazing across from the
-- farmhouse, and on some a collie who runs a lap round them now and then and
-- sits to watch. Tame: they don't mind who comes by.
--
-- On the rivers: deer that live by one go down to the bank to drink, and
-- herons stand in the shallows, still, now and then striking down at a
-- fish. Anyone coming near puts a heron up: it flaps off downriver and is
-- gone, and is back in its place a while after.
--
-- Mountain goats graze the hills under the peaks, and bound off up the
-- mountain when anyone comes near. A fox sleeps curled in a forest by day and
-- trots its rounds there in the dark.
--
-- (The wild beasts that are in the rules -- wolves, bears, boar, horses and
-- the rest -- are units, src/beasts.lua, drawn by the board.)
--
-- Nothing of this is in the game's rules or its save: the deer are the
-- screen's alone, and found again from the map whenever it changes.

local H = require "src.hex"
local M = require "src.models"
local S = require "src.ui.state"
local Sea = require "src.ui.sea"
local World = require "src.world"
local D = require "src.defs"

local floor, sin, sqrt, atan2 = math.floor, math.sin, math.sqrt, math.atan2

local Wild = {}

local SHARE = 0.3    -- of the open hexes beside a forest, how many have deer
local WALK = 3       -- room units a second, grazing about
local RUN = 26       -- and bounding off
local QUIET = 12     -- seconds a hex must be left alone before they come back
local ROAM = 4.5     -- how far from its spot a deer wanders
local FOLDS = 0.5    -- of the farms, how many keep sheep
local LAP, SIT = 5, 9 -- seconds the dog runs round them, and sits
local HERONS = 0.1   -- of the rivers' edges, how many a heron stands in
local DRINK = 0.4    -- how often a deer by a river goes down to it
local FLY = 2.5      -- seconds a heron is seen flying off
local GOATS = 0.35   -- of the hills under a mountain, how many have goats
local FOXES = 0.12   -- of the forests, how many a fox lives in
local TROT = 0.8     -- radians a second round its hex, a fox at night

local function grain(a, b)
    local n = sin(a * 12.9898 + b * 78.233) * 43758.5453
    return n - floor(n)
end

local herds, flocks, herons, foxes, foundAt, foundIn = {}, {}, {}, {}, -1, nil

-- The facing (0..5) nearest the way from (dx, dz).
local function facing(dx, dz)
    return floor(math.deg(atan2(dz, dx)) / 60 + 0.5) % 6
end

-- Where deer live: open, flat grass or plains, nothing built, beside a forest.
local function find(g)
    local found = {}
    for _, cell in ipairs(g.cells) do
        if (cell.terrain == "grass" or cell.terrain == "plains") and cell.elev == "flat" and not cell.feature
            and not cell.city and not cell.improvement and not cell.lair and grain(cell.id, 3) < SHARE then
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
                    -- By a river: a place on its bank to drink, facing it.
                    for d = 0, 5 do
                        local k = (d + floor(grain(cell.id, 12) * 6)) % 6
                        local e = cell.river and cell.river[k]
                        if e and not g:isWater(cell) then
                            local a = math.rad(60 * k)
                            local inset = H.APOTHEM - World.bankOf(e) - 2.2
                            herd.drink = { x = cell.x + math.cos(a) * inset, z = cell.z + math.sin(a) * inset, face = k }
                            break
                        end
                    end
                    for n = 1, 1 + floor(grain(cell.id, 5) * 2) do
                        herd.deer[n] = { x = sx + (n - 1.5) * 4, z = sz + (n - 1) * 2, face = floor(grain(cell.id, n) * 6),
                            pose = 1, wait = grain(n, cell.id) * 4, stag = grain(cell.id, n + 9) > 0.6 }
                    end
                    found[cell.id] = herd
                end
            end
        end
    end
    -- Goats: on hills under a mountain, the mountain where they run to.
    for _, cell in ipairs(g.cells) do
        if cell.elev == "hills" and not g:isWater(cell) and not cell.city and not cell.improvement and not cell.lair
            and grain(cell.id, 21) < GOATS then
            local peak
            for k = 0, 5 do
                local n = g:cell(H.step(cell.c, cell.r, k))
                if n and n.elev == "mountain" then peak = n break end
            end
            local key = -cell.id
            if peak then
                local old = herds[key]
                if old and old.woods == peak then
                    found[key] = old
                else
                    local sx = cell.x + (peak.x - cell.x) * 0.15
                    local sz = cell.z + (peak.z - cell.z) * 0.15
                    local herd = { cell = cell, woods = peak, sx = sx, sz = sz, deer = {}, gone = false, quiet = 0,
                        goat = true, y = cell.top + 3.2 }
                    for n = 1, 1 + floor(grain(cell.id, 22) * 3) do
                        herd.deer[n] = { x = sx + (n - 2) * 3.5, z = sz + (n % 2) * 2.5, face = floor(grain(cell.id, n + 22) * 6),
                            pose = 1, wait = grain(n, cell.id + 22) * 4 }
                    end
                    found[key] = herd
                end
            end
        end
    end
    herds = found

    -- Foxes: one to some forests, its earth a little off the middle.
    local earths = {}
    for _, cell in ipairs(g.cells) do
        if cell.feature == "forest" and not cell.city and not cell.lair and grain(cell.id, 31) < FOXES then
            earths[cell.id] = foxes[cell.id] or { cell = cell, a = grain(cell.id, 32) * 6.28, walk = 0, quiet = 99,
                sx = cell.x + (grain(cell.id, 33) - 0.5) * 6, sz = cell.z + 5 + grain(cell.id, 34) * 3,
                face = floor(grain(cell.id, 35) * 6) }
        end
    end
    foxes = earths

    -- The sheep: on farms, across from the farmhouse.
    local folds = {}
    for _, cell in ipairs(g.cells) do
        if cell.improvement == "farm" and cell.elev == "flat" and grain(cell.id, 6) < FOLDS then
            local old = flocks[cell.id]
            if old then
                folds[cell.id] = old
            else
                local home = M.farmLayout(cell.id).home
                local sx, sz = cell.x - home[1] * M.FARM_SCALE * 0.45, cell.z - home[2] * M.FARM_SCALE * 0.45
                local flock = { cell = cell, sx = sx, sz = sz, deer = {} }
                for n = 1, 2 + floor(grain(cell.id, 7) * 3) do
                    flock.deer[n] = { x = sx + (grain(n, cell.id * 3) - 0.5) * 10, z = sz + (grain(cell.id * 3, n) - 0.5) * 7,
                        face = floor(grain(cell.id, n + 4) * 6), pose = 1, wait = grain(n, cell.id + 1) * 5 }
                end
                if grain(cell.id, 8) < 0.6 then flock.dog = { t = grain(cell.id, 9) * (LAP + SIT), a = 0, walk = 0 } end
                folds[cell.id] = flock
            end
        end
    end
    flocks = folds

    -- The herons: in some of the rivers' edges, away from towns, standing in
    -- the water a little off the middle of the edge.
    local stands = {}
    for _, cell in ipairs(g.cells) do
        for k = 0, 5 do
            local e = cell.river and cell.river[k]
            local n = e and g:cell(H.step(cell.c, cell.r, k))
            if n and n.id > cell.id and not cell.city and not n.city and grain(cell.id * 6 + k, 13) < HERONS then
                local key = cell.id * 6 + k
                local old = herons[key]
                if old and old.edge == e then
                    stands[key] = old
                else
                    local fx, fz = e.to[1] - e.from[1], e.to[2] - e.from[2]
                    local l = sqrt(fx * fx + fz * fz)
                    fx, fz = fx / l, fz / l
                    local u = (grain(key, 14) - 0.5) * 6
                    local side = (grain(key, 15) - 0.5) * 2
                    local x = (e.from[1] + e.to[1]) / 2 + fx * u - fz * side
                    local z = (e.from[2] + e.to[2]) / 2 + fz * u + fx * side
                    stands[key] = { edge = e, cells = { cell, n }, x = x, z = z, hx = x, hz = z, y = e.level,
                        fx = fx, fz = fz, face = floor(grain(key, 16) * 6), t = grain(key, 17) * 8, pose = 0, quiet = 0 }
                end
            end
        end
    end
    herons = stands
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
            if d.drinking and herd.drink then d.face, d.wait = herd.drink.face, 6 + grain(d.z, d.x) * 4 end
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
    if d.drinking then
        -- At the water: head down to it a long while.
        d.drinking = nil
    elseif herd.drink and grain(d.x + S.clock, d.z) < DRINK then
        local w = herd.drink
        d.tx, d.tz = w.x + (grain(d.z, S.clock) - 0.5) * 4, w.z + (grain(S.clock, d.x) - 0.5) * 2
        d.drinking = true
        return
    end
    local a = grain(d.x * 3, d.z + S.clock) * math.pi * 2
    local r = ROAM * grain(d.z, d.x * 7)
    d.tx, d.tz = herd.sx + math.cos(a) * r, herd.sz + math.sin(a) * r
end

-- The sheep graze about; the dog runs its lap round them, then sits facing
-- them.
local function tend(flock, dt)
    for _, d in ipairs(flock.deer) do graze(flock, d, dt) end
    local dog = flock.dog
    if not dog then return end
    dog.t = (dog.t + dt) % (LAP + SIT)
    if dog.t < LAP then
        dog.a = dog.a + dt * 1.4
        dog.walk = dog.walk + dt * 10
        dog.gait = floor(dog.walk) % 4
        dog.face = facing(-math.sin(dog.a) * 8, math.cos(dog.a) * 6)
    else
        dog.gait = 0
        dog.face = facing(-math.cos(dog.a), -math.sin(dog.a))
    end
    dog.x, dog.z = flock.sx + math.cos(dog.a) * 8, flock.sz + math.sin(dog.a) * 6
end

function Wild.update(dt)
    local g = S.game
    if not g or Sea.still() then return end
    -- Found again each turn and whenever a hex changes.
    local stamp = g.turn * 1000 + (S.world.version or 0)
    if g ~= foundIn then herds, flocks, herons, foxes, foundIn = {}, {}, {}, {}, g end
    if stamp ~= foundAt then find(g) foundAt = stamp end
    for _, flock in pairs(flocks) do tend(flock, dt) end
    for _, h in pairs(herons) do
        local near = disturbed(g, h.cells[1]) or disturbed(g, h.cells[2])
        if near then h.quiet = 0 else h.quiet = h.quiet + dt end
        if h.flying then
            -- Off downriver, climbing, wings beating.
            h.flying = h.flying + dt
            h.x, h.z = h.x + h.fx * 22 * dt, h.z + h.fz * 22 * dt
            h.y = h.y + 9 * dt
            h.pose = 2 + floor(h.flying * 6) % 2
            if h.flying > FLY then h.flying, h.gone = nil, true end
        elseif h.gone then
            if h.quiet > QUIET * 1.5 then
                h.gone, h.x, h.z, h.y, h.pose = false, h.hx, h.hz, h.edge.level, 0
            end
        elseif near then
            h.flying, h.face = 0, facing(h.fx, h.fz)
        else
            -- Still a long while, then a strike.
            h.t = h.t + dt
            local period = 7 + grain(h.hx, h.hz) * 6
            h.pose = (h.t % period) > period - 0.5 and 1 or 0
        end
    end
    -- The foxes: asleep by day, trotting round by night; gone while anyone is
    -- near, back a while after.
    for _, f in pairs(foxes) do
        local night = D.night(g.turn, g, f.cell)
        if disturbed(g, f.cell) then f.quiet = 0 else f.quiet = f.quiet + dt end
        f.gone = f.quiet < QUIET
        if night then
            f.a = f.a + dt * TROT
            f.walk = f.walk + dt * 7
            f.pose = 1 + floor(f.walk) % 2
            f.x, f.z = f.cell.x + math.cos(f.a) * 6, f.cell.z + math.sin(f.a) * 4.5
            f.face = facing(-math.sin(f.a) * 6, math.cos(f.a) * 4.5)
        else
            f.x, f.z, f.pose = f.sx, f.sz, 3
        end
    end
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
                local y = herd.y or herd.cell.top
                list[#list + 1] = { z = d.z, draw = function()
                    if herd.goat then stamp(M.goat(d.face, d.pose), d.x, y, d.z)
                    else stamp(M.deer(d.face, d.pose, d.stag), d.x, y, d.z) end
                end }
            end
        end
    end
    for _, f in pairs(foxes) do
        if not f.gone and f.x and me.visible[f.cell.id] then
            local y = f.cell.top
            list[#list + 1] = { z = f.z, draw = function() stamp(M.fox(f.face, f.pose), f.x, y, f.z) end }
        end
    end
    for _, h in pairs(herons) do
        if not h.gone and (me.visible[h.cells[1].id] or me.visible[h.cells[2].id]) then
            list[#list + 1] = { z = h.z, draw = function() stamp(M.heron(h.face, h.pose), h.x, h.y, h.z) end }
        end
    end
    for _, flock in pairs(flocks) do
        if me.visible[flock.cell.id] then
            local y = flock.cell.top
            for _, d in ipairs(flock.deer) do
                list[#list + 1] = { z = d.z, draw = function() stamp(M.sheep(d.face, d.pose), d.x, y, d.z) end }
            end
            local dog = flock.dog
            if dog and dog.x then
                list[#list + 1] = { z = dog.z, draw = function() stamp(M.dog(dog.face, dog.gait), dog.x, y, dog.z) end }
            end
        end
    end
end

return Wild
