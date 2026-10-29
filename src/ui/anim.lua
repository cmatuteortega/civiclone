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

local max, min, floor = math.max, math.min, math.floor

local Anim = {}

local SPEED = 7 -- hexes a second

-- Where a unit on a hex stands: its middle, on top of the hill if it has one.
local function home(cell)
    return cell.x, cell.top + ((cell.elev == "hills" and not cell.city) and 3.2 or 0), cell.z
end
Anim.home = home

-- The drawn state of unit u, made the first time it is asked for.
function Anim.of(u)
    local a = S.anim[u.id]
    if not a then
        local cell = S.game.cells[u.cell]
        local x, y, z = home(cell)
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
                    x0 = from.x, y0 = from.top + 10, z0 = from.z, x1 = to.x, y1 = to.top + 6, z1 = to.z }
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
            local tx, ty, tz = home(to)
            local fc = game:cell(H.at(a.x, a.z))
            if fc and fc ~= to then a.face = face(fc, to) end
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
            a.walk = a.walk + dt * 8
            a.pose = floor(a.walk) % 2 + 1
        else
            a.pose = 0
            -- Settle where the unit is, in case it was put there without a walk.
            local cell = game.cells[u.cell]
            local x, y, z = home(cell)
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
    local x, y, z = a.x, a.y, a.z
    if #a.queue == 0 then
        local other = u.def.civilian and game.mil[u.cell] or game.civ[u.cell]
        if other and other ~= u then
            if u.def.civilian then x, z = x - 5, z - 4 else x, z = x + 4, z + 3 end
        end
        local cell = game.cells[u.cell]
        if cell.city and not u.def.civilian then x, z = x + 7, z + 6 end
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
