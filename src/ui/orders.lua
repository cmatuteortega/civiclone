-- What the player's clicks and keys mean: choosing a unit or a city, sending
-- a unit somewhere or at someone, the orders on a unit's panel, and the big
-- button that says what the turn still wants (a unit's orders, something to
-- build, something to research) before it can end.

local S = require "src.ui.state"
local View = require "src.ui.view"
local Anim = require "src.ui.anim"
local AI = require "src.ai"
local Audio = require "src.ui.audio"
local Settings = require "src.settings"

local max = math.max

local O = {}

local function me() return S.game.players[1] end

-- Messages for the player, as the game tells them.
local seen = 0
function O.collectLog()
    local log = S.game.log
    for k = seen + 1, #log do
        local l = log[k]
        if l.who == nil or l.who == 1 then
            table.insert(S.msgs, 1, { text = l.text, t = 0 })
            if #S.msgs > 6 then S.msgs[#S.msgs] = nil end
        end
    end
    seen = #log
end
function O.resetLog() seen = 0 end

--- paths ---------------------------------------------------------------------------

-- The path for u to `cell`, kept while nothing about it changes.
local cached = {}
function S.pathFor(u, cell, attack)
    local key = u.id .. ":" .. u.cell .. ":" .. cell.id .. ":" .. u.moves .. ":" .. S.game.turn .. ":" .. #S.game.units
    if cached.key ~= key then
        local path = S.game:path(u, cell.id, attack)
        cached = { key = key, path = path, turns = path and O.turnsAlong(u, path) }
    end
    S.hoverTurns = cached.turns
    return cached.path
end

-- How many turns walking a path takes, this one being the first.
function O.turnsAlong(u, path)
    local g = S.game
    local m, full, turns = u.moves, u.def.moves, 1
    for _, id in ipairs(path) do
        local c = g:moveCost(g.cells[id]) or 1
        if m <= 0 or not (m >= c or m == full) then
            turns, m = turns + 1, full
        end
        m = max(0, m - c)
    end
    return turns
end

--- choosing ------------------------------------------------------------------------

function O.select(thing, look)
    if not thing then
        S.selected = nil
        return
    end
    if thing.def then
        S.selected = { unit = thing }
        thing.skipped = false
        if look then View.lookAt(S.game.cells[thing.cell]) end
    else
        S.selected = { city = thing }
        if look then View.lookAt(S.game.cells[thing.cell]) end
    end
    S.panel = nil
end

-- On to the next of the player's units wanting orders, if any.
function O.nextUnit(after)
    local u = S.game:idleUnit(1, after)
    if u then O.select(u, Settings.get("follow")) return true end
    O.select(nil)
    return false
end

-- After an order: if the unit has nothing left to do, the next one.
local function after(u)
    if not Settings.get("autoCycle") then
        if u.dead then S.selected = nil end
        return
    end
    if u.dead or u.moves <= 0 or u.dest then
        if not O.nextUnit(u) then S.selected = nil end
    end
end

-- Sends the selected unit at a cell: an attack if there is an enemy there it
-- can reach, otherwise a walk.
function O.command(cell)
    local g = S.game
    local u = S.selected and S.selected.unit
    if not u or u.dead or u.owner ~= 1 or g.current ~= 1 or not cell then return false end
    if Anim.busy() then return false end
    local enemy = g:foreignAt(cell, 1)
    if enemy and g:canAttack(u, cell) then
        g:attack(u, cell)
        after(u)
        return true
    end
    if enemy then
        if u.def.civilian then return false end
        local path = g:path(u, cell.id, true)
        if not path then return false end
        u.sleep, u.fortified = false, false
        g:walk(u, path)
        u.dest = nil
        if g:canAttack(u, cell) then g:attack(u, cell) end
        after(u)
        return true
    end
    if cell.id == u.cell then return false end
    if g:moveTo(u, cell.id) then
        after(u)
        return true
    end
    -- Could not take a step this turn, but has a way: go next turn.
    local path = g:path(u, cell.id)
    if path then
        u.dest = cell.id
        after(u)
        return true
    end
    return false
end

-- A left click on the board.
function O.click(cell)
    local g = S.game
    if not cell then O.select(nil) return end
    local u = S.selected and S.selected.unit
    local mil, civ = g.mil[cell.id], g.civ[cell.id]
    local mine = {}
    if mil and mil.owner == 1 then mine[#mine + 1] = mil end
    if civ and civ.owner == 1 then mine[#mine + 1] = civ end
    if cell.city and cell.city.owner == 1 then mine[#mine + 1] = cell.city end
    -- A unit already chosen goes where the click is, if it is somewhere it
    -- can go or someone it can hit.
    if u and u.owner == 1 and #mine == 0 and u.moves > 0 then
        local reach = g:reach(u)
        local r = reach[cell.id]
        if g:canAttack(u, cell) or (r and not r.through) then
            O.command(cell)
            return
        end
    end
    if #mine == 0 then
        O.select(nil)
        return
    end
    -- Clicking the same hex again goes round what is on it.
    local current = S.selected and (S.selected.unit or S.selected.city)
    local at = 0
    for k, thing in ipairs(mine) do if thing == current then at = k end end
    O.select(mine[at % #mine + 1])
end

--- a unit's orders -----------------------------------------------------------------

-- The orders the selected unit can be given now: { label, cmd, fn, off },
-- `cmd` naming the key bound to it (src/settings.lua).
function O.actions(u)
    local g = S.game
    local out = {}
    if not u or u.owner ~= 1 then return out end
    if u.kind == "settler" then
        out[#out + 1] = { label = "FOUND CITY", cmd = "found", off = not g:canFound(u), fn = function()
            local city = g:found(u)
            if city then O.select(city) end
        end }
    end
    if u.kind == "builder" then
        local can = {}
        for _, k in ipairs(g:improvementsFor(u)) do can[k] = true end
        out[#out + 1] = { label = "FARM", cmd = "farm", off = not can.farm, fn = function() g:improve(u, "farm") after(u) end }
        out[#out + 1] = { label = "MINE", cmd = "mine", off = not can.mine, fn = function() g:improve(u, "mine") after(u) end }
    end
    if not u.def.civilian then
        out[#out + 1] = { label = u.fortified and "WAKE" or "FORTIFY", cmd = "fortify", fn = function()
            u.fortified = not u.fortified
            u.dest = nil
            if u.fortified then Audio.play("fortify") end
            if u.fortified and Settings.get("autoCycle") then O.nextUnit(u) end
        end }
    else
        out[#out + 1] = { label = u.sleep and "WAKE" or "SLEEP", cmd = "sleep", fn = function()
            u.sleep = not u.sleep
            u.dest = nil
            if u.sleep then Audio.play("sleep") end
            if u.sleep and Settings.get("autoCycle") then O.nextUnit(u) end
        end }
    end
    out[#out + 1] = { label = "SKIP", cmd = "skip", fn = function()
        u.skipped = true
        u.dest = nil
        O.nextUnit(u)
    end }
    return out
end

-- The hex grid on or off, and kept so.
function O.toggleGrid()
    S.grid = not S.grid
    Settings.set("grid", S.grid)
    Settings.save()
end

-- Sound loud, soft or off, said in the news.
function O.cycleSound()
    local level = Audio.cycle()
    if S.mode == "play" then table.insert(S.msgs, 1, { text = "SOUND: " .. level, t = 0 }) end
end

--- the turn -----------------------------------------------------------------------

-- What the big button says and does now.
function O.mainAction()
    local g = S.game
    if S.over then return nil end
    if Anim.busy() then return "PLEASE WAIT", nil end
    local city = g:idleCity(1)
    if city then
        return "CHOOSE PRODUCTION", function() O.select(city, true) end
    end
    if not me().researching and #g:researchable(me()) > 0 then
        return "CHOOSE RESEARCH", function() S.panel = "research" end
    end
    local u = g:idleUnit(1)
    if u then return "UNIT NEEDS ORDERS", function() O.select(u, true) end end
    return "END TURN", O.endTurn
end

-- Can the turn end now (whatever units are left without orders)?
function O.canEnd()
    local g = S.game
    if S.over or Anim.busy() then return false end
    if g:idleCity(1) then return false end
    if not me().researching and #g:researchable(me()) > 0 then return false end
    return true
end

function O.endTurn()
    if not O.canEnd() then return end
    local g = S.game
    S.selected, S.panel = nil, nil
    Audio.play("turn")
    g:endTurn(AI)
    O.collectLog()
    local result, why = g:outcome()
    if result then
        S.over = { result = result, why = why }
        return
    end
    O.nextUnit()
end

return O
