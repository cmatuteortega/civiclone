-- What moves on the board: units walking the hexes they were moved through,
-- a lunge at whatever they attack, the flash of a hit and its number rising,
-- the dying fading out. The rules happen at once (src/game.lua); this plays
-- them back, and hands each event to the sound (src/ui/audio.lua) as it does.
--
-- Each unit has a drawn state: where it is drawn (x, y, z), the hexes still
-- to walk, the way it faces and its step. The game leaves the hexes a unit
-- went through on `unit.trail`; they are taken off here.

local H = require "src.hex"
local S = require "src.ui.state"
local Audio = require "src.ui.audio"
local M = require "src.models"
local World = require "src.world"

local max, min, floor = math.max, math.min, math.floor

local Anim = {}

local SPEED = 7 -- hexes a second

-- The wake: a mark dropped on the water every WAKE_EVERY room units a boat
-- goes, from its stern, each kept WAKE_LIFE seconds. Boats go fast (seven
-- hexes a second), so by the way gone rather than the time.
local WAKE_EVERY, WAKE_LIFE = 1.2, 1.4
Anim.WAKE_LIFE = WAKE_LIFE
-- How far behind its middle a boat's stern is, in room units.
local function sternOf(u) return u.def.sea and 9 * M.UNIT_SCALE or 5.5 * M.UNIT_SCALE end

-- The way (0..5) a city on the water builds out to it: the water nearest
-- the front of the screen, where its pier is seen. Nil inland.
local SHORE = { 1, 2, 0, 3, 5, 4 }
function Anim.shore(game, cell)
    for _, k in ipairs(SHORE) do
        local n = game:cell(H.step(cell.c, cell.r, k))
        if n and game:isWater(n) then return k end
    end
end

-- Where a unit on a hex stands: its middle, on top of the hill if it has
-- one. A ship in port lies off the city's pier, on the water.
local function home(cell, u)
    if u and u.def.sea and cell.city then
        local k = Anim.shore(S.game, cell) or 1
        local a = math.rad(60 * k)
        return cell.x + math.cos(a) * H.W * 0.82, -2, cell.z + math.sin(a) * H.W * 0.82
    end
    return cell.x, cell.top + ((cell.elev == "hills" and not cell.city) and 3.2 or 0), cell.z
end
Anim.home = home

-- The drawn state of unit u, made the first time it is asked for.
function Anim.of(u)
    local a = S.anim[u.id]
    if not a then
        local cell = S.game.cells[u.cell]
        local x, y, z = home(cell, u)
        a = { x = x, y = y, z = z, queue = {}, face = 1, pose = 0, walk = 0 }
        S.anim[u.id] = a
    end
    return a
end

-- Is anything still walking, lunging or falling?
function Anim.busy()
    for _, a in pairs(S.anim) do
        if #a.queue > 0 or (a.lunge and a.lunge > 0) then return true end
    end
    return false
end

local function face(from, to)
    local k = H.dirTo(from.c, from.r, to.c, to.r)
    if k then return k end
    local a = math.atan2(to.z - from.z, to.x - from.x)
    return floor(math.deg(a) / 60 + 0.5) % 6
end

-- Takes what the game has put on its list since last time.
function Anim.events(game)
    for _, e in ipairs(game.events) do
        Audio.hear(game, e)
        if e.kind == "attack" then
            local from, to = game.cells[e.from], game.cells[e.to]
            if e.unit then
                local a = Anim.of(e.unit)
                a.face = face(from, to)
                a.lunge, a.lungeTo = 0.35, { to.x, to.z }
            end
            if e.ranged then
                S.effects[#S.effects + 1] = { kind = "shot", t = 0, life = 0.3,
                    x0 = from.x, y0 = from.top + 5.5 * M.UNIT_SCALE, z0 = from.z,
                    x1 = to.x, y1 = to.top + 3.3 * M.UNIT_SCALE, z1 = to.z }
            end
        elseif e.kind == "hit" then
            local cell = game.cells[e.cell]
            S.effects[#S.effects + 1] = { kind = "number", t = 0, life = 1.2, text = "-" .. e.amount,
                x = cell.x, y = cell.top + 26, z = cell.z, delay = 0.15 }
            if e.unit then Anim.of(e.unit).flash = 0.3 end
            if cell.city then cell.city.flash = 0.3 end
        elseif e.kind == "death" then
            local a = S.anim[e.unit.id]
            local cell = game.cells[e.cell]
            S.effects[#S.effects + 1] = { kind = "death", t = 0, life = 0.8, unit = e.unit,
                x = a and a.x or cell.x, y = a and a.y or cell.top, z = a and a.z or cell.z, face = a and a.face or 1 }
            S.anim[e.unit.id] = nil
        elseif e.kind == "terrain" then
            S.world:refresh(e.cell)
        end
        if e.kind ~= "attack" and e.kind ~= "hit" then S.bordersDirty = true end
    end
    for k = #game.events, 1, -1 do game.events[k] = nil end
end

function Anim.update(game, dt)
    Anim.events(game)
    for _, u in ipairs(game.units) do
        local a = Anim.of(u)
        -- New hexes walked: onto the queue.
        if #u.trail > 1 then
            for k = 2, #u.trail do a.queue[#a.queue + 1] = u.trail[k] end
            u.trail = { u.cell }
        end
        if #a.queue > 0 then
            local to = game.cells[a.queue[1]]
            local tx, ty, tz = home(to, u)
            local fc = game:cell(H.at(a.x, a.z))
            if fc and fc ~= to then a.face = face(fc, to) end
            -- Fording a river: where the step crosses one with no bridge,
            -- the edge's middle and the way across it, to wade through.
            if fc and fc ~= to and a.fordTo ~= to.id then
                a.fordTo, a.ford = to.id, nil
                if not u.def.sea and not game:isWater(fc) and not game:isWater(to) and game:fords(fc, to) then
                    local e = game:riverBetween(fc, to)
                    local k = H.dirTo(fc.c, fc.r, to.c, to.r)
                    local ang = math.rad(60 * k)
                    a.ford = { e = e, nx = math.cos(ang), nz = math.sin(ang),
                        mx = fc.x + math.cos(ang) * H.APOTHEM, mz = fc.z + math.sin(ang) * H.APOTHEM }
                end
            end
            local dx, dz = tx - a.x, tz - a.z
            local d = math.sqrt(dx * dx + dz * dz)
            local step = SPEED * H.W * dt
            if d <= step then
                a.x, a.y, a.z = tx, ty, tz
                table.remove(a.queue, 1)
                Audio.step(u, to)
            else
                a.x, a.z = a.x + dx / d * step, a.z + dz / d * step
                -- Up or down the terraces halfway across.
                a.y = (d < H.W * 0.5) and ty or a.y
            end
            -- In the river: down in the water to the knees, and a splash
            -- going in.
            local f = a.ford
            a.wade = nil
            if f then
                local across = (a.x - f.mx) * f.nx + (a.z - f.mz) * f.nz
                local bank = World.bankOf(f.e)
                if math.abs(across) < bank + 0.5 then
                    a.wade = f.e.level - 0.6
                    if not f.splashed then
                        f.splashed = true
                        S.effects[#S.effects + 1] = { kind = "splash", t = 0, life = 0.9, x = a.x, y = f.e.level, z = a.z,
                            seed = u.id }
                        Audio.ford(u, to)
                    end
                end
            end
            -- Under way on the water: foam off the stern.
            local over = game:cell(H.at(a.x, a.z))
            if d > 0 and over and game:isWater(over) then
                local went = math.min(d, step)
                a.wake = (a.wake or 0) + went
                local ux, uz = dx / d, dz / d
                local back = sternOf(u)
                -- Laid back along the way just gone, the newest last; the
                -- older ones a little aged already.
                local n = 0
                while a.wake >= WAKE_EVERY do
                    a.wake = a.wake - WAKE_EVERY
                    local behind = a.wake + n * WAKE_EVERY
                    n = n + 1
                    S.wakes[#S.wakes + 1] = { x = a.x - ux * (back + behind), z = a.z - uz * (back + behind),
                        dx = ux, dz = uz, t = behind / (SPEED * H.W), seed = (u.id * 977 + #S.wakes) % 1000,
                        big = u.def.sea }
                end
            end
            a.walk = a.walk + dt * 8
            a.pose = floor(a.walk) % 2 + 1
        else
            a.pose, a.wade, a.ford, a.fordTo = 0, nil, nil, nil
            -- Settle where the unit is, in case it was put there without a walk.
            local cell = game.cells[u.cell]
            local x, y, z = home(cell, u)
            if math.abs(a.x - x) > 0.01 or math.abs(a.z - z) > 0.01 then
                a.queue[1] = u.cell
            else
                a.y = y
            end
        end
        if a.lunge then
            a.lunge = a.lunge - dt
            if a.lunge <= 0 then a.lunge = nil end
        end
        if a.flash then
            a.flash = a.flash - dt
            if a.flash <= 0 then a.flash = nil end
        end
    end
    for _, c in ipairs(game.cities) do
        if c.flash then
            c.flash = c.flash - dt
            if c.flash <= 0 then c.flash = nil end
        end
    end
    for k = #S.wakes, 1, -1 do
        local w = S.wakes[k]
        w.t = w.t + dt
        if w.t >= WAKE_LIFE then table.remove(S.wakes, k) end
    end
    for k = #S.effects, 1, -1 do
        local e = S.effects[k]
        e.t = e.t + dt
        if e.t >= e.life + (e.delay or 0) then table.remove(S.effects, k) end
    end
end

-- Where unit u is drawn now: x, y, z, the facing, the pose. Two on one hex
-- stand apart, the civilian behind.
function Anim.place(game, u)
    local a = Anim.of(u)
    local x, y, z = a.x, a.wade or a.y, a.z
    if #a.queue == 0 then
        local other = u.def.civilian and game.mil[u.cell] or game.civ[u.cell]
        if other and other ~= u then
            if u.def.civilian then x, z = x - 5, z - 4 else x, z = x + 4, z + 3 end
        end
        local cell = game.cells[u.cell]
        if cell.city and not u.def.civilian and not u.def.sea then x, z = x + 7, z + 6 end
    end
    local pose = a.pose
    if a.lunge then
        local f = math.sin(math.pi * min(1, (0.35 - a.lunge) / 0.35))
        local tx, tz = a.lungeTo[1], a.lungeTo[2]
        local dx, dz = tx - x, tz - z
        local d = max(1, math.sqrt(dx * dx + dz * dz))
        x, z = x + dx / d * 5 * f, z + dz / d * 5 * f
        pose = 3
    end
    return x, y, z, a.face, pose
end

return Anim
