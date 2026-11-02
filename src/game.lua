-- The rules: the map, the civilizations, their units and cities, and a turn.
-- Nothing here draws or knows LÖVE, so the tests run it under plain LuaJIT.
--
-- The map is cells (src/mapgen.lua), indexed by id = r * cols + c + 1. A cell
-- holds at most one military unit and one civilian (`mil`, `civ`), and maybe
-- a city. Each player keeps what it has ever seen (`explored`) and what it
-- sees now (`visible`).
--
-- What the screen wants to show of what happened -- a unit walking, a hit, a
-- city founded -- is put on `events` for it to take off, and anything worth
-- telling the player goes on `log`.

local H = require "src.hex"
local D = require "src.defs"
local Rng = require "src.rng"
local Weather = require "src.weather"
local Mapgen = require "src.mapgen"
local Beasts = require "src.beasts"
local Cat = require "src.cataclysm"
local Frost = require "src.frost"
local Quake = require "src.quake"
local Q = require "src.quarters"
local L = require "src.lang"

local floor, ceil, max, min, exp = math.floor, math.ceil, math.max, math.min, math.exp

local Game = {}
Game.__index = Game

-- The owner of the wild's beasts (src/beasts.lua): no civilization. Its
-- player is players[0], out of the way of every ipairs over the players.
Game.WILD = Beasts.WILD

--- making one --------------------------------------------------------------------

function Game.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.cols, self.rows = opts.cols or D.COLS, opts.rows or D.ROWS
    local map = Mapgen.generate(self.cols, self.rows, opts.seed or os.time(), opts.civs or #D.CIVS)
    self.seed = map.seed
    self.cells = map.cells
    self.rng = Rng.new(map.seed + 17)
    self.mil, self.civ = {}, {}
    self.units, self.cities = {}, {}
    self.events, self.log = {}, {}
    self.lairs = {}
    self.turn = 1
    self.nextId = 1
    self.players = {}
    for k = 1, opts.civs or #D.CIVS do
        local civ = D.CIVS[k]
        local p = {
            id = k, civ = civ, name = civ.name, human = k == 1 and not opts.allAI,
            gold = 10, science = 0, researching = nil, techs = {},
            explored = {}, visible = {}, cityNames = 0, alive = true, everCity = false,
        }
        self.players[k] = p
        local start = map.starts[k]
        self:addUnit("settler", k, start.id)
        self:addUnit("band", k, start.id, { weapon = "club" })
        local near = self:freeNear(start.id, false)
        if near then self:addUnit("band", k, near) end
    end
    self.players[Game.WILD] = Beasts.player()
    if opts.wild ~= false then Beasts.populate(self) end
    -- What ends the world (src/cataclysm.lua).
    if opts.cataclysm ~= false then self.cataclysm = Cat.new(opts.cataclysm) end
    for _, p in ipairs(self.players) do self:look(p) end
    self.current = 1
    self:beginTurn(self.players[1])
    return self
end

--- cells ---------------------------------------------------------------------------

function Game:cell(c, r)
    if c < 0 or r < 0 or c >= self.cols or r >= self.rows then return nil end
    return self.cells[r * self.cols + c + 1]
end

function Game:neighbours(cell)
    local out = {}
    for k = 0, 5 do
        local n = self:cell(H.step(cell.c, cell.r, k))
        if n then out[#out + 1] = n end
    end
    return out
end

function Game:within(cell, n)
    local out = {}
    for _, p in ipairs(H.range(cell.c, cell.r, n)) do
        local m = self:cell(p[1], p[2])
        if m then out[#out + 1] = m end
    end
    return out
end

function Game:dist(a, b) return H.distance(a.c, a.r, b.c, b.r) end

function Game:isWater(cell) return D.TERRAIN[cell.terrain].water end

-- Can a land unit stand here at all? Not on the water, a mountain, nor a
-- chasm the sundering has torn (src/quake.lua).
function Game:passable(cell)
    return not self:isWater(cell) and cell.elev ~= "mountain" and (cell.rift or 0) < 2
end

-- What it costs to walk into a cell: 1, and one more each for hills and forest.
function Game:moveCost(cell)
    if not self:passable(cell) then return nil end
    return 1 + (cell.elev == "hills" and 1 or 0) + (cell.feature == "forest" and 1 or 0)
        + (D.TERRAIN[cell.terrain].move or 0)
end

-- The river along the edge between two neighbouring cells, or nil.
function Game:riverBetween(a, b)
    if not a.river or not b.river then return nil end
    local k = H.dirTo(a.c, a.r, b.c, b.r)
    return k and a.river[k] or nil
end

-- Does a river run along any edge of the cell?
function Game:onRiver(cell)
    return cell.river ~= nil and next(cell.river) ~= nil and not self:isWater(cell)
end

-- The name of a river by the cell ("THE OSIER"), or nil: the one that runs
-- along most of its edges, the first found breaking ties.
function Game:riverName(cell)
    if not self:onRiver(cell) then return nil end
    local count, best = {}, nil
    for k = 0, 5 do
        local e = cell.river[k]
        if e then
            count[e.name] = (count[e.name] or 0) + 1
            if not best or count[e.name] > count[best] then best = e.name end
        end
    end
    return best
end

-- Must a step from one land cell to the next ford a river? Not where either
-- is a city: a city bridges the rivers by it.
function Game:fords(from, to)
    if from.city or to.city or from.quarter or to.quarter then return false end
    if self:riverBetween(from, to) == nil then return false end
    -- Frozen over (src/frost.lua): walked across on the ice.
    return not Frost.riverIced(from, to)
end

-- Is the cell beside water (so a city on it can build ships)?
function Game:coastal(cell)
    for _, n in ipairs(self:neighbours(cell)) do
        if self:isWater(n) then return true end
    end
    return false
end

-- Is unit u a land unit out on the water, in a boat?
function Game:embarked(u)
    return not u.def.sea and self:isWater(self.cells[u.cell])
end

-- Can unit u ever be on this cell, by what it is and what its people know?
-- Ships keep to the water and their own cities on it; land units walk the
-- land and, after Sailing, row out onto the coast. The ocean wants
-- Cartography of either.
function Game:canEnter(u, cell)
    if u.owner == Game.WILD then return Beasts.canEnter(self, u, cell) end
    local water = self:isWater(cell)
    local techs = self.players[u.owner].techs
    if u.def.sea then
        if not water then
            return cell.city ~= nil and cell.city.owner == u.owner and self:coastal(cell)
        end
        return cell.terrain == "coast" or techs.cartography == true
    end
    if not water then return self:passable(cell) end
    if not techs.sailing then return false end
    return cell.terrain == "coast" or techs.cartography == true
end

-- A step that takes every move the unit has left: onto the water or off it,
-- or across a river where there is no bridge.
Game.ALL = math.huge

-- What it costs unit u to step from one cell into the next (nil: it cannot).
-- Embarking or landing costs Game.ALL: it can be done with any moves left,
-- and leaves none.
function Game:stepCost(u, from, to)
    if not self:canEnter(u, to) then return nil end
    -- A town shut against the plague (src/plague.lua): no one comes in or
    -- goes out.
    if (to.city and to.city.shut) or (from.city and from.city.shut) then return nil end
    if u.def.sea then return 1 end
    local fw, tw = self:isWater(from), self:isWater(to)
    if fw ~= tw then return Game.ALL end
    if tw then return 1 end
    -- An open fault (src/quake.lua): no one walks across.
    if from.fault and Quake.faultBetween(self, from, to) then return nil end
    if self:fords(from, to) then return Game.ALL end
    return self:moveCost(to)
end

-- Can a unit with `left` moves (of `full` a turn) take a step costing c?
local function affords(left, full, c)
    if left <= 0 then return false end
    if c == Game.ALL then return true end
    return left >= c or left == full
end
Game.affords = affords

-- The moves u has in a turn where it stands: a boat's, out on the water.
function Game:maxMoves(u)
    if self:embarked(u) then return D.EMBARK.moves end
    return u.def.moves
end

-- What a cell yields: food, production, gold. A city's own hex yields at
-- least 2 food and 1 production.
function Game:yield(cell)
    local t, e = D.TERRAIN[cell.terrain], D.ELEV[cell.elev]
    local f, p, g = t.food + e.food, t.prod + e.prod, t.gold
    if cell.elev == "mountain" or cell.fire or cell.flood or cell.lava or (cell.rift or 0) >= 2 then return 0, 0, 0 end
    if cell.feature then
        local ft = D.FEATURE[cell.feature]
        f, p = f + ft.food, p + ft.prod
    end
    if cell.resource then
        local r = D.RESOURCE[cell.resource]
        f, p, g = f + r.food, p + r.prod, g + r.gold
    end
    if cell.improvement then
        local i = D.IMPROVEMENT[cell.improvement]
        f, p = f + i.food, p + i.prod
    end
    if self:onRiver(cell) then
        g = g + D.RIVER.gold
        if cell.improvement == "farm" then f = f + D.RIVER.farmFood end
    end
    if Cat.droughtFarm(self, cell) then f = f - D.HEAT.droughtFarm end
    if cell.scorched then f = 0 end
    local K = Cat.kindOf(self)
    if K and K.food then f = K.food(self, cell, f) end
    -- Rain and storm (src/weather.lua).
    f, p = Weather.yield(self, cell, f, p)
    if cell.city then f, p = max(f, 2), max(p, 1) end
    return f, p, g
end

-- The name of what is on a cell, for the screen: "GRASSLAND HILLS FOREST".
function Game:describe(cell)
    local parts = {}
    if cell.elev == "mountain" then
        parts[1] = L"MOUNTAINS"
    else
        parts[1] = L(D.TERRAIN[cell.terrain].name)
        if cell.elev == "hills" then parts[#parts + 1] = L"HILLS" end
    end
    if cell.feature then parts[#parts + 1] = L(D.FEATURE[cell.feature].name) end
    if cell.resource then parts[#parts + 1] = L(D.RESOURCE[cell.resource].name) end
    if cell.improvement then parts[#parts + 1] = L(D.IMPROVEMENT[cell.improvement].name) end
    if self:onRiver(cell) then parts[#parts + 1] = "RIVER"
    elseif cell.dry and not self:isWater(cell) then parts[#parts + 1] = "DRY RIVERBED" end
    if cell.flood then parts[#parts + 1] = "- FLOODED"
    elseif cell.silt then parts[#parts + 1] = "- SILT"
    elseif cell.drowned then parts[#parts + 1] = "- DROWNED LAND" end
    if cell.glow then parts[#parts + 1] = "- FRESH CRATER"
    elseif cell.crater then parts[#parts + 1] = "- CRATER" end
    if cell.blight then parts[#parts + 1] = "- BLIGHTED" end
    if cell.fallow then parts[#parts + 1] = "- FALLOW" end
    -- The sundering's (src/quake.lua).
    if cell.volcano then parts[#parts + 1] = cell.erupting and "- ERUPTING VOLCANO" or "- VOLCANO" end
    if cell.rift == 1 then parts[#parts + 1] = "- CRACKED"
    elseif cell.rift == 2 then parts[#parts + 1] = "- CHASM"
    elseif cell.rift == 3 then parts[#parts + 1] = "- CHASM, THE SEA POURING IN"
    elseif cell.riftLine and not cell.sundered then parts[#parts + 1] = "- ON THE RIFT" end
    if cell.sundered then parts[#parts + 1] = "- THE RIFT" end
    if cell.raised then parts[#parts + 1] = "- RISEN SEABED" end
    if cell.lava then parts[#parts + 1] = "- LAVA"
    elseif cell.basalt then parts[#parts + 1] = "- BLACK ROCK" end
    if cell.ashfall then parts[#parts + 1] = "- ASH"
    elseif cell.soil then parts[#parts + 1] = "- VOLCANIC SOIL" end
    if cell.fault and next(cell.fault) then parts[#parts + 1] = "- FAULT" end
    if cell.fire then parts[#parts + 1] = "- BURNING"
    elseif cell.scorched then parts[#parts + 1] = "- SCORCHED"
    elseif cell.burnt then parts[#parts + 1] = "- BURNT"
    elseif cell.cleared then parts[#parts + 1] = "- FIREBREAK" end
    if cell.felled and not cell.feature then parts[#parts + 1] = "- FELLED" end
    if cell.lair then parts[#parts + 1] = "- " .. L(cell.lair.def.name) end
    if cell.quarter then
        parts[#parts + 1] = cell.sacked and L("- A QUARTER OF {1}, SACKED", cell.quarter.name) or L("- A QUARTER OF {1}", cell.quarter.name)
    end
    -- A town the great flood sank (src/flood.lua).
    if cell.ruin then parts[#parts + 1] = L("- THE SUNKEN RUINS OF {1}", cell.ruin.name) end
    -- Each part in the language now: a line written whole is looked up here.
    for k, s in ipairs(parts) do parts[k] = L(s) end
    return table.concat(parts, " ")
end

--- events and the log --------------------------------------------------------------

function Game:emit(e) self.events[#self.events + 1] = e end

-- Something to tell player `who` (or everyone, if nil), in the player's
-- language: `text` is the English, with what goes into it after it, as
-- src/lang.lua puts them together ("{1} WAS FOUNDED", name).
function Game:tell(who, text, ...)
    self.log[#self.log + 1] = { turn = self.turn, who = who, text = L(text, ...) }
end

--- units ---------------------------------------------------------------------------

-- A unit of `kind`: what a city trains ("band", "ship", "settler",
-- "builder") carrying `gear` (a band with none is a scout, a ship has a ram),
-- or a form by its name ("archer"), or a beast.
function Game:addUnit(kind, owner, cellId, gear)
    local form = D.FORMS[kind]
    if form then kind, gear = form.unit, form.gear end
    local def
    if D.UNITS[kind] then
        if D.UNITS[kind].armed and not (gear and gear.weapon) then gear = { weapon = "ram" } end
        def = D.unitDef(kind, gear)
    else
        def = assert(D.BEASTS[kind], kind)
    end
    local u = { id = self.nextId, kind = def.kind or kind, def = def, owner = owner, cell = cellId,
        hp = 100, moves = def.moves, charges = def.charges, trail = { cellId } }
    if def.gear then u.unit, u.gear = def.unit, D.copyGear(def.gear) end
    self.nextId = self.nextId + 1
    self.units[#self.units + 1] = u
    if def.civilian then self.civ[cellId] = u else self.mil[cellId] = u end
    return u
end

-- u carries `gear` now: its form, name and numbers are what it carries,
-- and its moves no more than its new kind has.
function Game:equip(u, gear)
    local def = D.unitDef(u.unit, gear)
    u.def, u.kind, u.gear = def, def.kind, D.copyGear(def.gear)
    u.moves = min(u.moves, def.moves)
end

function Game:removeUnit(u)
    for k, v in ipairs(self.units) do
        if v == u then table.remove(self.units, k) break end
    end
    if self.mil[u.cell] == u then self.mil[u.cell] = nil end
    if self.civ[u.cell] == u then self.civ[u.cell] = nil end
    u.dead = true
end

function Game:unitsOf(owner)
    local out = {}
    for _, u in ipairs(self.units) do if u.owner == owner then out[#out + 1] = u end end
    return out
end

-- The slot a unit of this kind takes on a cell.
function Game:slot(u) return u.def.civilian and self.civ or self.mil end

-- A free cell near `cellId` where a unit of that class can stand, nearest
-- first: on the land, or with `sea`, on water that `owner` may sail.
function Game:freeNear(cellId, civilian, sea, owner)
    local here = self.cells[cellId]
    local techs = owner and self.players[owner].techs or {}
    for _, cell in ipairs(self:within(here, 2)) do
        local ok
        if sea then ok = self:isWater(cell) and (cell.terrain == "coast" or techs.cartography)
        else ok = self:passable(cell) end
        if cell.id ~= cellId and ok and not (civilian and self.civ or self.mil)[cell.id]
            and not self:foreignAt(cell, nil) then
            return cell.id
        end
    end
end

-- Is there anything of another player's on the cell (a unit or a city)?
-- `owner` nil: anyone at all.
function Game:foreignAt(cell, owner)
    local m, c = self.mil[cell.id], self.civ[cell.id]
    if m and m.owner ~= owner then return m end
    if c and c.owner ~= owner then return c end
    if cell.city and cell.city.owner ~= owner then return cell.city end
    -- The demons' citadel (src/demons.lua), while it still stands.
    local l = cell.lair
    if l and l.hp and l.hp > 0 and owner ~= Game.WILD then return l end
end

-- The demons' citadel on the cell, standing against `owner`'s units, or nil.
function Game:besieged(cell, owner)
    local l = cell.lair
    if l and l.hp and l.hp > 0 and owner ~= Game.WILD then return l end
end

-- Can unit u stop on this cell?
function Game:canStand(u, cell)
    if not self:canEnter(u, cell) then return false end
    if self:slot(u)[cell.id] and self:slot(u)[cell.id] ~= u then return false end
    if self:foreignAt(cell, u.owner) then return false end
    return true
end

-- Can unit u walk through this cell on its way somewhere? Its own side's
-- units do not stop it; anyone else's do.
function Game:canPass(u, cell)
    if not self:canEnter(u, cell) then return false end
    if self:foreignAt(cell, u.owner) then return false end
    return true
end

-- Every cell unit u can reach this turn, and the moves it would have left
-- there: { [cellId] = { left, from } }. A unit with all its moves can always
-- take one step, whatever it costs; after that a step needs the moves for it.
function Game:reach(u)
    local best = { [u.cell] = { left = u.moves } }
    local open = { self.cells[u.cell] }
    while #open > 0 do
        -- The cell with the most moves left first.
        local bi = 1
        for k = 2, #open do
            if best[open[k].id].left > best[open[bi].id].left then bi = k end
        end
        local cell = table.remove(open, bi)
        local left = best[cell.id].left
        if left > 0 then
            for _, n in ipairs(self:neighbours(cell)) do
                local cost = self:stepCost(u, cell, n)
                if cost and self:canPass(u, n) and affords(left, self:maxMoves(u), cost) then
                    local l = cost == Game.ALL and 0 or max(0, left - cost)
                    if not best[n.id] or best[n.id].left < l then
                        best[n.id] = { left = l, from = cell.id }
                        open[#open + 1] = n
                    end
                end
            end
        end
    end
    -- Only where it could stop.
    for id in pairs(best) do
        if id ~= u.cell and not self:canStand(u, self.cells[id]) then best[id].through = true end
    end
    return best
end

-- The cheapest way for u from its cell to `goal` (a list of cell ids, not
-- counting where it stands), or nil. `toAttack`: the goal may hold an enemy,
-- and the path ends next to it.
function Game:path(u, goal, toAttack)
    local start = u.cell
    if start == goal then return {} end
    local g = self.cells[goal]
    local cost, from = { [start] = 0 }, {}
    -- The hexes still to look from, in a heap by cost so far and the
    -- distance left, then by when each was first reached: the cheapest
    -- first, and of equals the one reached first. A hex whose cost falls
    -- is put in again; what is taken out stale is passed over.
    local hf, hs, hid, size, seq = {}, {}, {}, 0, 0
    local order, done = {}, {}
    local hc = {}
    local function h(id)
        local v = hc[id]
        if not v then
            local c = self.cells[id]
            v = H.distance(c.c, c.r, g.c, g.r)
            hc[id] = v
        end
        return v
    end
    local function before(a, b) return hf[a] < hf[b] or (hf[a] == hf[b] and hs[a] < hs[b]) end
    local function swap(a, b)
        hf[a], hf[b] = hf[b], hf[a]
        hs[a], hs[b] = hs[b], hs[a]
        hid[a], hid[b] = hid[b], hid[a]
    end
    local function push(id)
        size = size + 1
        hf[size], hs[size], hid[size] = cost[id] + h(id), order[id], id
        local k = size
        while k > 1 do
            local up = floor(k / 2)
            if not before(k, up) then break end
            swap(k, up)
            k = up
        end
    end
    local function pop()
        local f, id = hf[1], hid[1]
        hf[1], hs[1], hid[1] = hf[size], hs[size], hid[size]
        hf[size], hs[size], hid[size] = nil, nil, nil
        size = size - 1
        local k = 1
        while true do
            local l, r, m = 2 * k, 2 * k + 1, k
            if l <= size and before(l, m) then m = l end
            if r <= size and before(r, m) then m = r end
            if m == k then break end
            swap(k, m)
            k = m
        end
        return id, f
    end
    order[start] = 0
    push(start)
    while size > 0 do
        local id, f = pop()
        if not done[id] and f == cost[id] + h(id) then
            done[id] = true
            if id == goal then break end
            local cell = self.cells[id]
            for _, n in ipairs(self:neighbours(cell)) do
                local step = self:stepCost(u, cell, n)
                -- Onto the water or off it costs the rest of a turn.
                if step == Game.ALL then step = u.def.moves end
                -- What is attacked need not be somewhere the unit could go: a
                -- ship strikes a city on the shore.
                if not step and toAttack and n.id == goal
                    and (n.city or (u.def.sea and self:isWater(n)) or (not u.def.sea and self:passable(n))) then
                    step = 1
                end
                local ok = step and self:canPass(u, n)
                if n.id == goal then
                    ok = step and (toAttack or self:canStand(u, n))
                end
                if ok then
                    -- Through a hex one of ours holds only if there is no other
                    -- way: a unit cannot stop there if its moves run out.
                    local c = cost[id] + step + ((n.id ~= goal and not self:canStand(u, n)) and 1.5 or 0)
                    if not cost[n.id] or c < cost[n.id] then
                        local new = not cost[n.id]
                        cost[n.id], from[n.id] = c, id
                        -- Looked from already: its cost is kept, but it is
                        -- not looked from again.
                        if new then
                            seq = seq + 1
                            order[n.id] = seq
                            push(n.id)
                        elseif not done[n.id] then
                            push(n.id)
                        end
                    end
                end
            end
        end
    end
    if not cost[goal] then return nil end
    local out, id = {}, goal
    while id ~= start do
        table.insert(out, 1, id)
        id = from[id]
    end
    if toAttack then out[#out] = nil end
    return out
end

-- Moves u one step to a neighbouring cell, if it can. Answers whether it did.
function Game:step(u, toId)
    local to = self.cells[toId]
    local from = self.cells[u.cell]
    local cost = self:stepCost(u, from, to)
    if not cost or not affords(u.moves, self:maxMoves(u), cost) then return false end
    if not self:canPass(u, to) then return false end
    local slot = self:slot(u)
    if slot[u.cell] == u then slot[u.cell] = nil end
    u.cell = toId
    u.moves = cost == Game.ALL and 0 or max(0, u.moves - cost)
    if cost == Game.ALL then
        self:emit({ kind = self:isWater(to) and "embark" or "land", cell = toId, unit = u })
    end
    u.fortified, u.acted = false, true
    u.trail[#u.trail + 1] = toId
    -- Stepping through a cell another of ours holds: pass on, but come back
    -- into the slot if it ends here and the slot is free.
    if not slot[toId] then slot[toId] = u end
    -- A military unit walking onto an enemy civilian takes it.
    local c = self.civ[toId]
    if not u.def.civilian and c and c.owner ~= u.owner then self:capture(u, c) end
    self:look(self.players[u.owner])
    Beasts.arrive(self, u, to)
    return true
end

-- Puts u on a neighbouring cell whatever it costs, with nothing left to move:
-- a melee unit taking the hex or the city it has just won.
function Game:relocate(u, toId)
    local slot = self:slot(u)
    if slot[u.cell] == u then slot[u.cell] = nil end
    u.cell = toId
    slot[toId] = u
    u.moves, u.fortified, u.acted = 0, false, true
    u.trail[#u.trail + 1] = toId
    local c = self.civ[toId]
    if not u.def.civilian and c and c.owner ~= u.owner then self:capture(u, c) end
    self:look(self.players[u.owner])
    Beasts.arrive(self, u, self.cells[toId])
end

-- Walks u along a path as far as its moves go this turn, never stopping on a
-- cell it cannot stand on. What is left is kept as u.dest for next turn.
function Game:walk(u, path)
    local k = 1
    while k <= #path do
        local id = path[k]
        -- Do not walk into a cell we could not stop in unless the moves after
        -- it carry us on, through every such cell in a row, to one we can.
        local cell = self.cells[id]
        if not self:canStand(u, cell) then
            local left, full, prev, j, clear = u.moves, self:maxMoves(u), self.cells[u.cell], k, false
            while path[j] do
                local c = self.cells[path[j]]
                local cost = self:stepCost(u, prev, c)
                if not cost or cost == Game.ALL or not affords(left, full, cost) then break end
                left = max(0, left - cost)
                if self:canStand(u, c) then clear = true break end
                prev, j = c, j + 1
            end
            if not clear then break end
        end
        if not self:step(u, id) then break end
        k = k + 1
    end
    if self:slot(u)[u.cell] ~= u then
        -- Stopped where another of ours stands (it should not happen): stay.
        self:slot(u)[u.cell] = self:slot(u)[u.cell] or u
    end
    local rest = {}
    for n = k, #path do rest[#rest + 1] = path[n] end
    u.dest = #rest > 0 and path[#path] or nil
    return k > 1
end

-- An order to go to `goal`: moves now, and on in later turns.
function Game:moveTo(u, goal)
    local p = self:path(u, goal)
    if not p then return false end
    u.sleep = false
    return self:walk(u, p)
end

function Game:capture(by, u)
    if by.owner == Game.WILD then return self:kill(u, Game.WILD, by) end
    local cell = u.cell
    self:removeUnit(u)
    self:tell(u.owner, "A {1} WAS CAPTURED", u.def.name)
    if u.kind == "settler" or u.kind == "builder" then
        local taken = self:addUnit("builder", by.owner, cell)
        taken.moves = 0
        self:tell(by.owner, "CAPTURED A {1}", u.def.name)
    end
    self:emit({ kind = "capture", cell = cell })
end

--- combat --------------------------------------------------------------------------

-- What its rank adds to a unit's strength (D.RANKS).
function Game:rankBonus(u)
    local r = D.rank(u.xp)
    return r and r.str or 0
end

-- u came through a fight: a point, or two for a kill (D.RANKS). Says so
-- when it rises a rank.
function Game:harden(u, n)
    if u.dead or u.owner == Game.WILD or u.def.civilian then return end
    local was = D.rank(u.xp)
    u.xp = (u.xp or 0) + n
    local now = D.rank(u.xp)
    if now and now ~= was then self:tell(u.owner, "OUR {1} IS NOW " .. now.name, u.def.name) end
end

-- What a band that won a fight takes from the one it beat: a better weapon
-- of the same sort (a blade for a blade, a bow for a sling), a horse if it
-- has none, a hide if it has none. Taken from the fallen, gear needs no
-- research.
function Game:plunder(u, from)
    if u.dead or u.unit ~= "band" or from.unit ~= "band" or u.owner == Game.WILD then return end
    local gear, took = { weapon = u.gear.weapon, mount = u.gear.mount, armour = u.gear.armour }, {}
    local mine, theirs = gear.weapon and D.GEAR[gear.weapon], from.gear.weapon and D.GEAR[from.gear.weapon]
    if theirs and (not mine or ((mine.ranged ~= nil) == (theirs.ranged ~= nil) and theirs.cost > mine.cost)) then
        gear.weapon = from.gear.weapon
        took[#took + 1] = L(theirs.name)
    end
    if from.gear.mount and not gear.mount then
        gear.mount = from.gear.mount
        took[#took + 1] = L(D.GEAR[from.gear.mount].name)
    end
    if from.gear.armour and not gear.armour then
        gear.armour = from.gear.armour
        took[#took + 1] = L(D.GEAR[from.gear.armour].name)
    end
    if #took == 0 then return end
    local was = u.def.name
    self:equip(u, gear)
    local all = table.concat(took, L" AND ")
    if u.def.name ~= was then
        self:tell(u.owner, "OUR {1} TOOK THE ENEMY'S {2}: NOW A {3}", was, all, u.def.name)
    else
        self:tell(u.owner, "OUR {1} TOOK THE ENEMY'S {2}", was, all)
    end
    self:emit({ kind = "loot", cell = u.cell, text = table.concat(took, " ") })
end

-- How strong a unit stands defending its cell.
function Game:defense(u)
    local cell = self.cells[u.cell]
    local base = self:embarked(u) and D.EMBARK.str or u.def.str
    local s = base - floor((100 - u.hp) / 10) + self:rankBonus(u)
    s = s + D.ELEV[cell.elev].defense + (cell.feature and D.FEATURE[cell.feature].defense or 0)
    if u.fortified then s = s + D.COMBAT.fortify end
    return s
end

-- How hard u strikes: its strength, less its wounds; and, given the cell it
-- strikes, less again for a melee attack across a river.
function Game:attackStrength(u, ranged, cell)
    local base = ranged and u.def.ranged or u.def.str
    local s = base - floor((100 - u.hp) / 10) + Beasts.nightBonus(self, u) + self:rankBonus(u)
    if cell and not ranged and self:riverBetween(self.cells[u.cell], cell) then s = s - D.RIVER.attack end
    return s
end

function Game:cityStrength(city)
    local s = D.CITY.str + city.pop * 2
    local g = self.mil[city.cell]
    if g and g.owner == city.owner then s = max(s, g.def.str + 2) end
    if city.buildings.walls then s = s + D.BUILDINGS.walls.defense end
    return s
end

local function damage(rng, a, d)
    local luck = 0.8 + rng:random() * 0.4
    return max(1, floor(D.COMBAT.base * exp((a - d) / D.COMBAT.scale) * luck + 0.5))
end

-- What u could hit from where it stands: the cell has an enemy and is in reach.
function Game:canAttack(u, cell)
    if u.def.civilian or u.moves <= 0 or u.attacked or self:embarked(u) then return false end
    local target = self:foreignAt(cell, u.owner)
    if not target then return false end
    local d = self:dist(self.cells[u.cell], cell)
    -- A shot needs a soldier or a city to aim at; a civilian is only taken.
    if u.def.ranged then
        local m = self.mil[cell.id]
        return d <= u.def.range and ((m and m.owner ~= u.owner) or (cell.city and cell.city.owner ~= u.owner)
            or self:besieged(cell, u.owner)) and true or false
    end
    if d ~= 1 then return false end
    -- The wild leaves the towns alone, and itself; not the demons the towns.
    if u.owner == Game.WILD and ((cell.city and not u.def.demon) or target.owner == Game.WILD) then return false end
    if self:besieged(cell, u.owner) and not self.mil[cell.id] then return true end
    -- A tentacle in the water is struck from the shore.
    local m = self.mil[cell.id]
    if m and m.def.lives == "shore" and m.owner ~= u.owner and not u.def.sea then return true end
    -- A crocodile takes only what comes to the water: across its river.
    if u.def.across and not self:riverBetween(self.cells[u.cell], cell) then return false end
    -- Melee: a city from anywhere next to it; otherwise a ship fights on the
    -- water and a soldier on the land.
    if cell.city then return true end
    -- A tentacle lashes the shore.
    if u.def.sea then return self:isWater(cell) or (u.def.demon == true and self:passable(cell)) end
    return self:passable(cell)
end

-- What an attack would do: damage dealt, damage taken (a guess, no luck).
function Game:forecast(u, cell)
    local city = cell.city and cell.city.owner ~= u.owner and cell.city
    local a = self:attackStrength(u, u.def.ranged, cell)
    local d
    local lair = not city and not self.mil[cell.id] and self:besieged(cell, u.owner)
    if city then d = self:cityStrength(city)
    elseif lair then d = lair.str
    else
        local t = self.mil[cell.id]
        if not t or t.owner == u.owner then return 100, 0 end
        d = self:defense(t)
    end
    local dealt = floor(D.COMBAT.base * exp((a - d) / D.COMBAT.scale) + 0.5)
    local taken = u.def.ranged and 0 or floor(D.COMBAT.base * exp((d - a) / D.COMBAT.scale) + 0.5)
    return dealt, taken
end

-- u attacks whatever is on `cell`. A melee attacker that kills moves in; one
-- that brings a city to nothing takes it.
function Game:attack(u, cell)
    if not self:canAttack(u, cell) then return false end
    local from = self.cells[u.cell]
    local ranged = u.def.ranged ~= nil
    local a = self:attackStrength(u, ranged, cell)
    local city = cell.city and cell.city.owner ~= u.owner and cell.city
    local target = self.mil[cell.id]
    if target and target.owner == u.owner then target = nil end
    u.moves, u.attacked, u.fortified, u.acted = 0, true, false, true
    self:emit({ kind = "attack", unit = u, from = from.id, to = cell.id, ranged = ranged })

    if city then
        local d = self:cityStrength(city)
        local dealt = damage(self.rng, a, d)
        city.hp = city.hp - dealt
        self:emit({ kind = "hit", cell = cell.id, amount = dealt })
        if not ranged then
            local taken = damage(self.rng, d, a)
            u.hp = u.hp - taken
            self:emit({ kind = "hit", cell = from.id, amount = taken, unit = u })
        end
        -- The demons never take a town: they feed on it (src/demons.lua).
        if u.owner == Game.WILD and city.hp < 1 then Cat.KINDS.demons.devour(self, city) end
        if u.hp <= 0 then
            self:kill(u, city.owner)
        elseif city.hp <= 0 then
            city.hp = 0
            if not ranged then self:conquer(u, city) end
        end
        return true
    end

    local lair = not target and self:besieged(cell, u.owner)
    if lair then
        -- The demons' citadel: beaten down like a city's walls; at nothing,
        -- a melee attacker walks in and razes it (src/beasts.lua).
        local d = lair.str
        local dealt = damage(self.rng, a, d)
        lair.hp = max(0, lair.hp - dealt)
        self:emit({ kind = "hit", cell = cell.id, amount = dealt })
        if not ranged then
            local taken = damage(self.rng, d, a)
            u.hp = u.hp - taken
            self:emit({ kind = "hit", cell = from.id, amount = taken, unit = u })
        end
        if u.hp <= 0 then
            self:kill(u, Game.WILD)
        elseif lair.hp <= 0 and not ranged then
            self:relocate(u, cell.id)
        elseif lair.hp <= 0 then
            self:tell(u.owner, "THE CITADEL OF THE ABYSS IS BROKEN: WALK IN AND RAZE IT")
        end
        return true
    end

    if not target then
        -- Only a civilian there: a melee attacker just walks in and takes it.
        local c = self.civ[cell.id]
        if not ranged and c and u.def.drags then
            -- A tentacle drags them under.
            self:emit({ kind = "hit", cell = cell.id, amount = c.hp, unit = c })
            self:kill(c, Game.WILD, u)
        elseif not ranged and c and u.owner == Game.WILD then
            -- A beast does not take the people it falls on: it mauls them.
            local dealt = damage(self.rng, a, self:defense(c))
            c.hp = c.hp - dealt
            self:emit({ kind = "hit", cell = cell.id, amount = dealt, unit = c })
            if c.hp <= 0 then self:kill(c, Game.WILD, u) end
        elseif not ranged and c and self:canEnter(u, cell) then self:relocate(u, cell.id) end
        return true
    end
    local d = self:defense(target)
    local dealt = damage(self.rng, a, d)
    -- Out in a boat, a tentacle takes them under at a blow.
    if u.def.drags and not ranged and self:embarked(target) then dealt = target.hp end
    target.hp = target.hp - dealt
    target.fortified = false
    -- A beast that minds its own business minds whoever struck it now.
    if target.owner == Game.WILD and target.def.temper == "neutral" then
        target.angry, target.angryTurns = u.id, 3
    end
    self:emit({ kind = "hit", cell = cell.id, amount = dealt, unit = target })
    if not ranged then
        local taken = damage(self.rng, d, a)
        u.hp = u.hp - taken
        self:emit({ kind = "hit", cell = from.id, amount = taken, unit = u })
    end
    if target.hp <= 0 then self:kill(target, u.owner, u) end
    if u.hp <= 0 then
        self:kill(u, target.owner, target)
        self:harden(target, 2)
    else
        self:harden(u, target.hp <= 0 and 2 or 1)
        if target.hp > 0 then self:harden(target, 1) end
        if target.hp <= 0 and not ranged then self:plunder(u, target) end
        if target.hp <= 0 and not ranged and u.owner ~= Game.WILD and target.def.lives ~= "shore" and self:canEnter(u, cell) then
            -- Into the hex it won.
            self:relocate(u, cell.id)
        end
    end
    return true
end

-- `by`: the owner of what killed it, and `killer` the unit, if one did.
function Game:kill(u, by, killer)
    self:removeUnit(u)
    self:emit({ kind = "death", cell = u.cell, unit = u })
    if u.owner == Game.WILD then
        Beasts.slain(self, u, by, killer)
        return
    end
    if by == Game.WILD then
        if killer then self:tell(u.owner, "OUR {1} WAS KILLED BY A {2}", u.def.name, killer.def.name)
        else self:tell(u.owner, "OUR {1} WAS KILLED BY THE WILD", u.def.name) end
    else
        self:tell(u.owner, "OUR {1} WAS KILLED", u.def.name)
        if by then self:tell(by, "ENEMY {1} DESTROYED", u.def.name) end
    end
    self:checkAlive(self.players[u.owner])
end

--- cities --------------------------------------------------------------------------

-- Can unit u found a city where it stands?
function Game:canFound(u)
    if u.kind ~= "settler" or u.moves <= 0 then return false end
    local cell = self.cells[u.cell]
    if not self:passable(cell) or D.TERRAIN[cell.terrain].noCity or cell.city or (cell.lair and (cell.lair.def.beast or cell.lair.def.demon)) then return false end
    if cell.owner and cell.owner ~= u.owner then return false end
    for _, c in ipairs(self.cities) do
        if self:dist(self.cells[c.cell], cell) < 4 then return false end
    end
    return true
end

function Game:found(u)
    if not self:canFound(u) then return false end
    local p = self.players[u.owner]
    local cell = self.cells[u.cell]
    p.cityNames = p.cityNames + 1
    local name = p.civ.cities[p.cityNames] or (p.name .. " " .. p.cityNames)
    local city = {
        id = self.nextId, name = name, owner = u.owner, cell = cell.id, pop = 1, food = 0, prod = 0,
        culture = 0, claimed = 0, hp = D.CITY.hp, buildings = {}, worked = {},
        capital = not p.everCity, founder = u.owner, founded = self.turn,
    }
    self.nextId = self.nextId + 1
    self:removeUnit(u)
    cell.city = city
    -- A city clears the forest it is built in, and levels its hills.
    cell.feature = nil
    self:emit({ kind = "terrain", cell = cell.id })
    cell.improvement = nil
    self.cities[#self.cities + 1] = city
    p.everCity = true
    for _, n in ipairs(self:within(cell, D.CITY.claimRadius)) do
        if not n.owner then n.owner, n.ownerCity = u.owner, city end
    end
    cell.owner, cell.ownerCity = u.owner, city
    self:assignWork(city)
    self:look(p)
    self:emit({ kind = "found", cell = cell.id, city = city })
    self:tell(u.owner, "{1} WAS FOUNDED", name)
    local K = Cat.kindOf(self)
    if K and K.founded then K.founded(self, u, city) end
    return city
end

function Game:citiesOf(owner)
    local out = {}
    for _, c in ipairs(self.cities) do if c.owner == owner then out[#out + 1] = c end end
    return out
end

function Game:maxHp(city) return D.CITY.hp + (city.buildings.walls and D.BUILDINGS.walls.hp or 0) end

-- Food a city needs stored to grow: Civilization VI's 15 + 8n + n^1.5.
function Game:growthNeed(city)
    local n = city.pop - 1
    return floor(15 + 8 * n + n ^ 1.5)
end

-- Picks the hexes a city's citizens work: the best of its own within reach,
-- weighed by the city's focus (D.FOCUS), food a little first unless told.
function Game:assignWork(city)
    for _, id in ipairs(city.worked) do
        if self.cells[id].workedBy == city then self.cells[id].workedBy = nil end
    end
    city.worked = {}
    local home = self.cells[city.cell]
    local w = D.FOCUS[city.focus or "balanced"] or D.FOCUS.balanced
    local choices = {}
    for _, cell in ipairs(self:within(home, D.CITY.workRadius)) do
        if cell.owner == city.owner and not cell.city and not cell.quarter and not cell.workedBy and cell.elev ~= "mountain" then
            local f, p, g = self:workYield(city, cell)
            choices[#choices + 1] = { cell = cell, v = f * w.food + p * w.prod + g * w.gold + self.rng:random() * 0.01 }
        end
    end
    table.sort(choices, function(a, b) return a.v > b.v end)
    for k = 1, min(city.pop, #choices) do
        local cell = choices[k].cell
        cell.workedBy = city
        city.worked[#city.worked + 1] = cell.id
    end
end

-- Sets what a city weighs first in working its land: "balanced", "food" or
-- "prod". Its citizens move at once.
function Game:setFocus(city, focus)
    if not D.FOCUS[focus] then return false end
    city.focus = focus ~= "balanced" and focus or nil
    self:assignWork(city)
    return true
end

-- What a cell yields worked by this city: its own yield, and on the water
-- what the city's harbour and lighthouse add.
function Game:workYield(city, cell)
    local f, p, g = self:yield(cell)
    if self:isWater(cell) and not cell.city then
        for b in pairs(city.buildings) do
            local def = D.BUILDINGS[b]
            f, g = f + (def.seaFood or 0), g + (def.seaGold or 0)
        end
    end
    return f, p, g
end

-- What a city makes in a turn: food, production, gold, science, culture.
function Game:cityYield(city)
    local f, p, g = self:yield(self.cells[city.cell])
    for _, id in ipairs(city.worked) do
        local a, b, c = self:workYield(city, self.cells[id])
        f, p, g = f + a, p + b, g + c
    end
    local sci, cul = city.pop * 0.5, 1 + floor(city.pop / 3)
    if city.capital and city.owner == city.founder then
        local pal = D.CITY.palace
        f, p, g, sci, cul = f + pal.food, p + pal.prod, g + pal.gold, sci + pal.science, cul + pal.culture
    end
    for b in pairs(city.buildings) do
        local def = D.BUILDINGS[b]
        f, p, g = f + (def.food or 0), p + (def.prod or 0), g + (def.gold or 0)
        sci, cul = sci + (def.science or 0), cul + (def.culture or 0)
    end
    -- Rationing: the cataclysm's hunger eats what is spare, never into
    -- what feeds the city.
    local hunger = Cat.thirst(self, city)
    if hunger > 0 and self:knows(city, "rationing") then hunger = min(hunger, max(0, f - 2 * city.pop)) end
    f = f - hunger
    local K = Cat.kindOf(self)
    if K and K.gold then g = K.gold(self, city, g) end
    return f, p, g, sci, cul
end

-- Can this player build `kind` ("unit" or "building", id) in this city,
-- a band or a ship carrying `gear` (any it could carry, if not given)?
-- Does this building hold off the cataclysm there is? A ward is only for
-- that one ("any": whichever it is, but not when there is none; a table:
-- against more than one, { heat = true, sun = true }).
function Game:wardsOff(def)
    if not def.ward or not self.cataclysm then return false end
    if def.ward == "any" then return true end
    if type(def.ward) == "table" then return def.ward[self.cataclysm.kind] == true end
    return Cat.is(self, def.ward) and true or false
end

function Game:canBuild(city, kind, id, gear)
    if kind == "quarter" then return Q.can(self, city, id and self.cells[id]) end
    local p = self.players[city.owner]
    if kind == "unit" and D.FORMS[id] then id, gear = D.FORMS[id].unit, D.FORMS[id].gear end
    local def = kind == "unit" and D.UNITS[id] or D.BUILDINGS[id]
    if not def then return false end
    if def.tech and not p.techs[def.tech] then return false end
    if gear and not self:canEquip(p, id, gear) then return false end
    if kind == "building" and city.buildings[id] then return false end
    if def.ward and not self:wardsOff(def) then return false end
    -- Ships, harbours and lighthouses only by the water.
    if (def.sea or def.coastal) and not self:coastal(self.cells[city.cell]) then return false end
    return true
end

--- gear --------------------------------------------------------------------------

-- What this player gives out now in place of a piece of gear, if it has
-- left it behind: the newest of its line that research has opened (the
-- club gives way to the spear, and the spear to the sword).
function Game:replacement(p, id)
    local by, best = D.GEAR_REPLACED_BY[id], nil
    while by do
        local t = D.GEAR[by].tech
        if t and not p.techs[t] then break end
        best, by = by, D.GEAR_REPLACED_BY[by]
    end
    return best
end

-- Can this player give out this piece now: known, and not left behind?
function Game:canMake(p, id)
    local g = D.GEAR[id]
    if not g or g.loot then return false end
    if g.tech and not p.techs[g.tech] then return false end
    return self:replacement(p, id) == nil
end

-- The pieces this player can give a `unit` ("band" or "ship") for a slot,
-- in order.
function Game:gearFor(p, unit, slot)
    local out = {}
    for id, g in pairs(D.GEAR) do
        if g.unit == unit and g.slot == slot and self:canMake(p, id) then out[#out + 1] = id end
    end
    table.sort(out, function(a, b) return D.GEAR[a].order < D.GEAR[b].order end)
    return out
end

-- Can this player make a `unit` carrying `gear`? (Armour is only ever taken.)
function Game:canEquip(p, unit, gear)
    local base = D.UNITS[unit]
    if not base then return false end
    if not base.geared then return next(gear) == nil end
    if base.armed and not gear.weapon then return false end
    if gear.armour then return false end
    for _, slot in ipairs({ "weapon", "mount" }) do
        local id = gear[slot]
        if id then
            local g = D.GEAR[id]
            if not g or g.unit ~= unit or g.slot ~= slot or not self:canMake(p, id) then return false end
        end
    end
    return true
end

-- What a `unit` is given unless the player says otherwise: the strongest
-- weapon it can have (or the strongest shot, if `ranged`), on foot. A
-- band is given a blade unless asked for a shot; a ship whichever is
-- stronger.
function Game:bestGear(p, unit, ranged)
    if not D.UNITS[unit].geared then return {} end
    if ranged == nil and unit == "band" then ranged = false end
    local best, bv
    for _, id in ipairs(self:gearFor(p, unit, "weapon")) do
        local g = D.GEAR[id]
        if ranged == nil or (g.ranged ~= nil) == ranged then
            local v = g.ranged or g.str
            if not bv or v > bv then best, bv = id, v end
        end
    end
    return { weapon = best }
end

-- What a city's order is: its name and what it costs. A refit costs what
-- the new gear costs over the old (at least 5).
-- A quarter, as the build list shows it: what the next one costs.
function Game:quarterDef(city)
    return { name = "QUARTER", short = "QUART.", cost = Q.cost(city) or D.QUARTER.cost[1], icon = "city",
        says = { "THE CITY SPILLS OVER INTO A HEX BESIDE IT,", L("HOUSING {1} MORE CITIZENS.", D.QUARTER.each),
            "THE HEX IS WORKED NO MORE." } }
end

function Game:buildDef(b)
    if b.kind == "quarter" then
        local def = self:quarterDef({})
        def.cost = b.cost or def.cost
        return def
    end
    if b.kind ~= "unit" then return D.BUILDINGS[b.id] end
    local def = D.unitDef(b.id, b.gear)
    if not b.refit then return def end
    local u = self:unitById(b.refit)
    local was = u and u.gear and D.gearCost(u.gear) or 0
    return { name = L("REFIT {1}", def.name), cost = max(5, D.gearCost(b.gear) - was), refit = true, unit = def }
end

function Game:unitById(id)
    for _, u in ipairs(self.units) do if u.id == id then return u end end
end

-- Can u be given new gear by the city it stands in?
function Game:canRefit(u)
    if not u.gear or u.dead then return false end
    local city = self.cells[u.cell].city
    return city ~= nil and city.owner == u.owner and (u.unit ~= "ship" or self:coastal(self.cells[city.cell]))
end

-- An order to the city u stands in to give it `gear`; what is made goes
-- into it as into anything, and it can be bought.
function Game:refit(u, gear)
    if not self:canRefit(u) or not self:canEquip(self.players[u.owner], u.unit, gear) then return false end
    local city = self.cells[u.cell].city
    -- Armour taken from the fallen is kept whatever else it is given.
    gear = { weapon = gear.weapon, mount = gear.mount, armour = u.gear.armour }
    city.build = { kind = "unit", id = u.unit, gear = gear, refit = u.id }
    return true
end

-- Everything the city could build now, units then buildings, in order.
function Game:buildable(city)
    local out = {}
    for _, kind in ipairs({ "unit", "building" }) do
        local list = {}
        for id, def in pairs(kind == "unit" and D.UNITS or D.BUILDINGS) do
            if self:canBuild(city, kind, id) then
                local it = { kind = kind, id = id, def = def }
                if def.geared then
                    it.gear = self:bestGear(self.players[city.owner], id)
                    it.def = D.unitDef(id, it.gear)
                    it.order = def.order
                end
                list[#list + 1] = it
            end
        end
        table.sort(list, function(a, b) return (a.order or a.def.order) < (b.order or b.def.order) end)
        for _, it in ipairs(list) do out[#out + 1] = it end
    end
    -- A quarter, once the city is near its housing and has somewhere for
    -- one: the hex is chosen after (src/ui/orders.lua).
    if Q.due(self, city) then
        out[#out + 1] = { kind = "quarter", def = self:quarterDef(city) }
    end
    return out
end

-- What the city builds next: a band or a ship carrying `gear`, or the
-- best it can if not said.
function Game:setBuild(city, kind, id, gear)
    if kind == "unit" and D.FORMS[id] then id, gear = D.FORMS[id].unit, D.FORMS[id].gear end
    if kind == "unit" and D.UNITS[id] and D.UNITS[id].geared and not gear then
        gear = self:bestGear(self.players[city.owner], id)
    end
    if not self:canBuild(city, kind, id, kind == "unit" and (gear or {}) or nil) then return false end
    city.build = { kind = kind, id = id, gear = gear, cost = kind == "quarter" and Q.cost(city) or nil }
    return true
end

-- Turns until done at the city's present rate, from `progress` made (what
-- it has made so far, by default).
function Game:turnsFor(city, cost, progress)
    local _, p = self:cityYield(city)
    return max(1, ceil((cost - (progress or city.prod)) / max(1, p)))
end

function Game:buyCost(city)
    if not city.build then return nil end
    local def = self:buildDef(city.build)
    return ceil(max(0, def.cost - city.prod) * 2.5) + 5
end

function Game:buy(city)
    local cost = self:buyCost(city)
    local p = self.players[city.owner]
    if not cost or p.gold < cost or city.bought then return false end
    local def = self:buildDef(city.build)
    if city.build.refit and not self:refitReady(city) then return false end
    if city.build.kind == "unit" and not def.refit and not self:placeFor(city, def) then return false end
    if def.pop and city.pop <= def.pop then return false end
    p.gold = p.gold - cost
    city.prod = def.cost
    city.bought = true
    self:complete(city)
    return true
end

-- Where a new unit of this kind can come out: the city's hex, or next to it.
-- A ship comes out on the water beside it, or in the city if there is no room.
function Game:placeFor(city, def)
    local slot = def.civilian and self.civ or self.mil
    if def.sea then
        for _, n in ipairs(self:neighbours(self.cells[city.cell])) do
            if self:isWater(n) and n.terrain == "coast" and not slot[n.id] and not self:foreignAt(n, nil) then
                return n.id
            end
        end
        if not slot[city.cell] then return city.cell end
        return self:freeNear(city.cell, false, true, city.owner)
    end
    if not slot[city.cell] then return city.cell end
    return self:freeNear(city.cell, def.civilian)
end

-- Is the unit a city is refitting there to be given its gear?
function Game:refitReady(city)
    local u = self:unitById(city.build.refit)
    return u ~= nil and u.cell == city.cell and u.owner == city.owner
end

-- Finishes what the city is building, if it can: answers whether it did.
function Game:complete(city)
    local b = city.build
    if b.refit then
        local u = self:unitById(b.refit)
        if not u or u.owner ~= city.owner or u.cell ~= city.cell then
            -- Gone, or gone off: what was made is kept for the next thing.
            if u and u.owner == city.owner then self:tell(city.owner, "OUR {1} LEFT {2} BEFORE IT WAS REFITTED", u.def.name, city.name) end
            city.build = nil
            return false
        end
        local cost = self:buildDef(b).cost
        local was = u.def.name
        self:equip(u, b.gear)
        self:tell(city.owner, "{1} REFITTED A {2}: NOW A {3}", city.name, was, u.def.name)
        self:emit({ kind = "built", cell = city.cell, unit = u })
        city.prod = max(0, city.prod - cost)
        city.build = nil
        return true
    end
    if b.kind == "quarter" then
        local cell = self.cells[b.id]
        if not Q.can(self, city, cell) then
            -- Taken or lost meanwhile: what was made is kept for the next thing.
            self:tell(city.owner, "{1} CAN NO LONGER BUILD ITS QUARTER THERE", city.name)
            city.build = nil
            return false
        end
        local cost = self:buildDef(b).cost
        Q.add(self, city, cell)
        city.prod = max(0, city.prod - cost)
        city.build = nil
        return true
    end
    if b.kind == "unit" then
        local def = D.unitDef(b.id, b.gear)
        if def.pop and city.pop <= def.pop then return false end
        local at = self:placeFor(city, def)
        if not at then return false end
        local u = self:addUnit(b.id, city.owner, at, b.gear)
        u.moves = 0
        if def.pop then
            city.pop = city.pop - def.pop
            city.food = 0
            self:assignWork(city)
        end
        self:tell(city.owner, "{1} TRAINED A {2}", city.name, def.name)
        self:emit({ kind = "built", cell = city.cell, unit = u })
    else
        city.buildings[b.id] = true
        if b.id == "walls" then city.hp = self:maxHp(city) end
        self:tell(city.owner, "{1} BUILT A {2}", city.name, D.BUILDINGS[b.id].name)
        self:emit({ kind = "built", cell = city.cell })
    end
    local def = self:buildDef(b)
    city.prod = max(0, city.prod - def.cost)
    city.build = nil
    return true
end

-- Culture spills over into new hexes: the best unowned hex next to the city's
-- land, within its reach.
function Game:growBorder(city)
    local home = self.cells[city.cell]
    local best, bv
    for _, cell in ipairs(self:within(home, D.CITY.workRadius)) do
        if not cell.owner then
            local touches = false
            for _, n in ipairs(self:neighbours(cell)) do
                if n.owner == city.owner and n.ownerCity == city then touches = true end
            end
            if touches then
                local f, p, g = self:yield(cell)
                local v = f * 2 + p * 2 + g + (cell.resource and 2 or 0) - self:dist(home, cell) * 1.5
                if not bv or v > bv then best, bv = cell, v end
            end
        end
    end
    if best then
        best.owner, best.ownerCity = city.owner, city
        city.claimed = city.claimed + 1
        self:emit({ kind = "border", cell = best.id })
        return true
    end
end

function Game:borderNeed(city)
    return floor(D.CITY.borderCost + 6 * city.claimed ^ 1.3)
end

-- A city with walls shoots the weakest enemy in reach; one with a sanctum
-- (src/demons.lua), the weakest demon, walls or none.
function Game:cityStrike(city)
    local walls, sanctum = city.buildings.walls, city.buildings.sanctum
    if (not walls and not sanctum) or city.hp <= 0 then return end
    local home = self.cells[city.cell]
    local best
    for _, cell in ipairs(self:within(home, D.CITY.rangedRange)) do
        local u = self.mil[cell.id] or self.civ[cell.id]
        if u and u.owner ~= city.owner and (walls or u.def.demon) and (not best or u.hp < best.hp) then best = u end
    end
    if not best then return end
    local dealt = damage(self.rng, self:cityStrength(city), self:defense(best))
    best.hp = best.hp - dealt
    self:emit({ kind = "attack", from = city.cell, to = best.cell, ranged = true, city = city })
    self:emit({ kind = "hit", cell = best.cell, amount = dealt, unit = best })
    if best.hp <= 0 then self:kill(best, city.owner) end
end

-- A melee unit walks into a city with nothing left: it changes hands.
function Game:conquer(u, city)
    local old = city.owner
    local cell = self.cells[city.cell]
    -- Whatever of theirs was inside is lost with it.
    for _, slot in ipairs({ self.mil, self.civ }) do
        local v = slot[cell.id]
        if v and v.owner ~= u.owner then self:removeUnit(v) end
    end
    city.owner = u.owner
    city.pop = max(1, city.pop - 1)
    city.hp = 50
    city.build, city.prod = nil, 0
    city.buildings.walls = nil
    for _, n in ipairs(self.cells) do
        if n.ownerCity == city then n.owner = u.owner end
    end
    self:relocate(u, cell.id)
    self:assignWork(city)
    self:emit({ kind = "conquer", cell = cell.id, city = city, from = old })
    self:tell(old, "{1} HAS FALLEN TO {2}", city.name, self.players[u.owner].name)
    self:tell(u.owner, "WE HAVE TAKEN {1}", city.name)
    self:checkAlive(self.players[old])
end

-- A player with no cities left and no settler to found one is out.
function Game:checkAlive(p)
    if not p.alive or p.wild then return end
    if #self:citiesOf(p.id) > 0 then return end
    for _, u in ipairs(self.units) do
        if u.owner == p.id and u.kind == "settler" then return end
    end
    if not p.everCity and self.turn < 5 then return end
    p.alive = false
    for _, u in ipairs(self:unitsOf(p.id)) do self:removeUnit(u) end
    self:tell(nil, "{1} HAS BEEN DESTROYED", p.name)
    self:emit({ kind = "eliminated", player = p.id })
end

--- science -------------------------------------------------------------------------

function Game:canResearch(p, id)
    local t = D.TECH[id]
    if not t or p.techs[id] then return false end
    for _, need in ipairs(t.needs) do if not p.techs[need] then return false end end
    return true
end

-- The way to technology `id`: every one it needs that `p` doesn't know yet,
-- each after what it needs, and `id` last. Empty if it is known.
function Game:researchPath(p, id)
    local out, seen = {}, {}
    local function walk(t)
        if p.techs[t] or seen[t] then return end
        seen[t] = true
        for _, need in ipairs(D.TECH[t].needs) do walk(need) end
        out[#out + 1] = t
    end
    walk(id)
    return out
end

-- Sets `p` researching toward `id`: straight at it if it can be, else at
-- the first on the way, with the rest queued to follow, each as the one
-- before is learned. What science it has stays with it.
function Game:researchToward(p, id)
    local path = self:researchPath(p, id)
    if #path == 0 then return false end
    p.researching = table.remove(path, 1)
    p.queue = #path > 0 and path or nil
    return true
end

-- Where research is making for: the last queued, else what is under way.
function Game:researchGoal(p)
    local q = p.queue
    if q and #q > 0 then return q[#q] end
    return p.researching
end

-- What technology `id` costs `p` now: its cost, and more for every city
-- past the first (D.RESEARCH).
function Game:techCost(p, id)
    local cities = p and #self:citiesOf(p.id) or 1
    return floor(D.TECH[id].cost * (1 + D.RESEARCH.perCity * max(0, cities - 1)) + 0.5)
end

-- Does the owner of player id or city `who` know technology `id`?
function Game:knows(who, id)
    local p = type(who) == "table" and (who.techs and who or self.players[who.owner]) or self.players[who]
    return p ~= nil and p.techs ~= nil and p.techs[id] == true
end

function Game:researchable(p)
    local out = {}
    for _, t in ipairs(D.TECHS) do
        if self:canResearch(p, t.id) then out[#out + 1] = t end
    end
    return out
end

--- sight ---------------------------------------------------------------------------

-- What a player sees now: round its units and cities, and all its land.
function Game:look(p)
    if p.wild then return end
    local vis = {}
    local function see(cell, n)
        for _, m in ipairs(self:within(cell, n)) do vis[m.id] = true end
    end
    for _, u in ipairs(self.units) do
        if u.owner == p.id then
            local cell = self.cells[u.cell]
            -- A storm (src/weather.lua) shortens it.
            see(cell, max(1, u.def.sight + (cell.elev == "hills" and 1 or 0) - Weather.blind(self)))
        end
    end
    for _, c in ipairs(self.cities) do
        if c.owner == p.id then
            -- A lighthouse's beam carries further.
            see(self.cells[c.cell], c.buildings.lighthouse and D.BUILDINGS.lighthouse.sight or 2)
        end
    end
    for _, cell in ipairs(self.cells) do
        if cell.owner == p.id then vis[cell.id] = true end
    end
    local changed = false
    for id in pairs(vis) do
        if not p.explored[id] then p.explored[id] = true changed = true end
        if not p.visible[id] then changed = true end
    end
    for id in pairs(p.visible) do if not vis[id] then changed = true end end
    p.visible = vis
    if changed then p.sightChanged = true end
end

--- turns ---------------------------------------------------------------------------

-- The start of a player's turn: moves back, the wounded heal, orders to go
-- somewhere carried on.
function Game:beginTurn(p)
    for _, u in ipairs(self:unitsOf(p.id)) do
        if not u.acted and u.hp < 100 then
            local cell = self.cells[u.cell]
            local heal = D.COMBAT.healField
            if cell.owner == p.id then heal = D.COMBAT.healHome end
            if cell.city and cell.city.owner == p.id then heal = D.COMBAT.healCity end
            if p.techs.medicine then heal = heal * 2 end
            u.hp = min(100, u.hp + heal)
        end
        u.moves, u.acted, u.attacked, u.skipped = self:maxMoves(u), false, false, false
        u.trail = { u.cell }
    end
    for _, u in ipairs(self:unitsOf(p.id)) do
        if u.dest and not u.dead then
            if u.dest == u.cell then u.dest = nil
            elseif not self:moveTo(u, u.dest) then u.dest = nil end
        end
    end
    for _, c in ipairs(self:citiesOf(p.id)) do
        c.bought = false
        Q.tend(self, c)
    end
end

-- The end of a player's turn: its cities grow and build, its science and
-- gold come in, its walls shoot.
function Game:finishTurn(p)
    local sci, gold = 0, 0
    for _, city in ipairs(self:citiesOf(p.id)) do
        self:assignWork(city)
        local f, pr, g, s, cu = self:cityYield(city)
        sci, gold = sci + s, gold + g
        -- Food: two a citizen; the rest stored towards the next, slower
        -- when the city is out of room (src/quarters.lua), and none once it
        -- is well past it.
        local spare = f - city.pop * 2
        if spare > 0 then
            local pace = Q.pace(self, city)
            if pace == 0 then spare = min(spare, max(0, self:growthNeed(city) - 1 - city.food))
            else spare = spare * pace end
        end
        city.food = city.food + spare
        -- A town the cataclysm keeps from growing (the plague's sick and
        -- shut, src/plague.lua) stores up to the brink.
        local K = Cat.kindOf(self)
        if K and K.stunted and K.stunted(self, city) then city.food = min(city.food, self:growthNeed(city) - 1) end
        if city.food >= self:growthNeed(city) then
            city.food = city.food - self:growthNeed(city)
            city.pop = city.pop + 1
            self:assignWork(city)
            self:tell(p.id, "{1} HAS GROWN TO {2}", city.name, city.pop)
            self:emit({ kind = "grow", cell = city.cell, city = city })
        elseif city.food < 0 then
            if city.pop > 1 then
                city.pop = city.pop - 1
                self:assignWork(city)
                self:tell(p.id, "{1} IS STARVING", city.name)
            end
            city.food = 0
        end
        if city.build then
            city.prod = city.prod + pr
            local def = self:buildDef(city.build)
            if city.prod >= def.cost then self:complete(city) end
        end
        city.culture = city.culture + cu
        if city.culture >= self:borderNeed(city) then
            city.culture = city.culture - self:borderNeed(city)
            self:growBorder(city)
        end
        city.hp = min(self:maxHp(city), city.hp + D.CITY.heal * (p.techs.medicine and 2 or 1))
        self:cityStrike(city)
    end
    -- Upkeep: a unit beyond the free ones costs one gold.
    local units = #self:unitsOf(p.id)
    local cities = #self:citiesOf(p.id)
    gold = gold - max(0, units - (2 + cities))
    p.gold = max(0, p.gold + gold)
    p.lastGold, p.lastScience = gold, sci
    -- Its people at their most, for what the score counts kept.
    p.peak = max(p.peak or 0, self:people(p))
    if p.researching then
        p.science = p.science + sci
        local t, cost = D.TECH[p.researching], self:techCost(p, p.researching)
        if p.science >= cost then
            p.science = p.science - cost
            p.techs[t.id] = true
            p.researching = nil
            -- The next on the way to what it is making for.
            while p.queue and #p.queue > 0 and not p.researching do
                local next = table.remove(p.queue, 1)
                if self:canResearch(p, next) then p.researching = next end
            end
            if p.queue and #p.queue == 0 then p.queue = nil end
            -- A weapon left behind, on a unit under way, becomes what took
            -- its place, keeping what was made.
            for _, city in ipairs(self:citiesOf(p.id)) do
                local b = city.build
                local by = b and b.gear and b.gear.weapon and self:replacement(p, b.gear.weapon)
                if by then b.gear = { weapon = by, mount = b.gear.mount, armour = b.gear.armour } end
            end
            self:tell(p.id, "WE HAVE LEARNED {1}", t.name)
            self:emit({ kind = "tech", player = p.id, tech = t.id })
        end
    else
        -- Science made with nothing chosen is kept for the next one.
        p.science = p.science + sci
    end
    self:look(p)
end

-- The per-turn figures for the top bar: gold, science, culture.
function Game:income(p)
    local sci, gold, cul = 0, 0, 0
    for _, city in ipairs(self:citiesOf(p.id)) do
        local _, _, g, s, c = self:cityYield(city)
        sci, gold, cul = sci + s, gold + g, cul + c
    end
    local units = #self:unitsOf(p.id)
    gold = gold - max(0, units - (2 + #self:citiesOf(p.id)))
    return gold, sci, cul
end

-- Every citizen of a civilization's cities.
function Game:people(p)
    local n = 0
    for _, c in ipairs(self:citiesOf(p.id)) do n = n + c.pop end
    return n
end

-- The score, part by part: { { label, points }, ... }. It counts what a
-- civilization has at the end and what of it lasted: the share of its
-- people at their most it still has, its land that still gives food, and its
-- cities that stand with a ward against the cataclysm (D.SCORE).
function Game:scoreParts(p)
    local S = D.SCORE
    local cities, wards = self:citiesOf(p.id), 0
    for _, c in ipairs(cities) do
        for b in pairs(c.buildings) do
            if self:wardsOff(D.BUILDINGS[b]) then wards = wards + 1 break end
        end
    end
    local techs, explored, land = 0, 0, 0
    for _ in pairs(p.techs) do techs = techs + 1 end
    for _ in pairs(p.explored) do explored = explored + 1 end
    for _, cell in ipairs(self.cells) do
        if cell.owner == p.id and not self:isWater(cell) and self:yield(cell) >= 1 then land = land + 1 end
    end
    local people = self:people(p)
    local peak = max(p.peak or 0, people)
    return {
        { "CITIES", #cities * S.city },
        { "CITIZENS", people * S.citizen },
        { "PEOPLE KEPT", peak > 0 and floor(S.kept * (people / peak) ^ 2) or 0 },
        { "GOOD LAND", floor(land * S.land) },
        { "WARDS HELD", wards * S.ward },
        { "TECHNOLOGY", techs * S.tech },
        { "EXPLORED", floor(explored * S.explored) },
        -- Demons slain, rifts sealed, the citadel razed (src/demons.lua).
        { "GLORY", floor(p.glory or 0) },
    }
end

function Game:score(p)
    local s = 0
    for _, part in ipairs(self:scoreParts(p)) do s = s + part[2] end
    return s
end

-- The last turn played: the cataclysm's, or without one an earlier end.
function Game:lastTurn() return self.cataclysm and D.LAST_TURN or D.PLAIN_LAST_TURN end

-- How the game stands for the human: nil while it goes on, or "won" / "lost"
-- and why.
function Game:outcome()
    local me = self.players[1]
    if not me.alive then return "lost", "YOUR CIVILIZATION HAS FALLEN" end
    local rivals = 0
    for k = 2, #self.players do if self.players[k].alive then rivals = rivals + 1 end end
    if rivals == 0 then return "won", "DOMINATION VICTORY" end
    -- Holding every capital also wins.
    local capitals, held = 0, 0
    for _, c in ipairs(self.cities) do
        if c.capital then
            capitals = capitals + 1
            if c.owner == 1 then held = held + 1 end
        end
    end
    if capitals >= #self.players and held == capitals then return "won", "DOMINATION VICTORY" end
    if self.turn > self:lastTurn() then
        local mine, best = self:score(me), 0
        for k = 2, #self.players do best = max(best, self:score(self.players[k])) end
        if mine >= best then return "won", "SCORE VICTORY" end
        return "lost", Cat.ended(self) or "TIME HAS RUN OUT"
    end
end

-- The human ends their turn: they finish, every other civilization plays,
-- and the next turn begins. `ai` is the module that plays them.
--
-- A "phase" event goes on the list as each part of it begins (`who`: the
-- player, Game.WILD, or "cataclysm"), so the screen can play the turn
-- back a part at a time (src/ui/playback.lua). The rules do not wait.
function Game:endTurn(ai)
    local me = self.players[1]
    self:finishTurn(me)
    for k = 2, #self.players do
        local p = self.players[k]
        if p.alive then
            self.current = k
            self:emit({ kind = "phase", who = k })
            self:beginTurn(p)
            if ai then ai.play(self, p) end
            self:finishTurn(p)
        end
    end
    self:emit({ kind = "phase", who = Game.WILD })
    self:wildTurn()
    self.current = 1
    self.turn = self.turn + 1
    self:emit({ kind = "phase", who = "cataclysm" })
    Cat.turn(self)
    Weather.turn(self)
    for _, p in ipairs(self.players) do self:checkAlive(p) end
    self:beginTurn(me)
    self:look(me)
end

-- The wild plays after the civilizations: its beasts heal and act, its
-- lairs send out more.
function Game:wildTurn()
    local w = self.players[Game.WILD]
    self.current = Game.WILD
    for _, u in ipairs(self:unitsOf(Game.WILD)) do
        if not u.acted and u.hp < 100 then u.hp = min(100, u.hp + D.WILD.heal) end
        u.moves, u.acted, u.attacked = self:maxMoves(u), false, false
        u.trail = { u.cell }
    end
    Beasts.play(self)
    for _, p in ipairs(self.players) do self:look(p) end
    return w
end

-- The first of the player's units still wanting orders, after `after`.
function Game:idleUnit(owner, after)
    local list = self:unitsOf(owner)
    local start = 0
    for k, u in ipairs(list) do if u == after then start = k end end
    for n = 1, #list do
        local u = list[(start + n - 1) % #list + 1]
        if u.moves > 0 and not u.fortified and not u.sleep and not u.dest and not u.skipped then return u end
    end
end

-- A city of this player that has nothing to build.
function Game:idleCity(owner)
    for _, c in ipairs(self:citiesOf(owner)) do
        if not c.build then return c end
    end
end

-- Things a builder can make on its cell.
function Game:improvementsFor(u)
    if u.kind ~= "builder" or u.moves <= 0 then return {} end
    local cell = self.cells[u.cell]
    if cell.owner ~= u.owner or cell.city or cell.elev == "mountain" then return {} end
    local p = self.players[u.owner]
    local out = {}
    -- Out on the water, rowed there: only fishing boats, over the fish.
    if self:isWater(cell) then
        if cell.resource == "fish" and cell.improvement ~= "boats" and p.techs.sailing then out[1] = "boats" end
        return out
    end
    if cell.improvement ~= "farm" and cell.elev == "flat" and not cell.feature and cell.terrain ~= "desert"
        and not D.TERRAIN[cell.terrain].noFarm and not cell.fire and not cell.flood and not cell.blight then
        out[#out + 1] = "farm"
    end
    if cell.improvement ~= "mine" and (cell.elev == "hills" or cell.resource == "stone" or cell.resource == "gems"
        or cell.resource == "iron") and p.techs.mining and not cell.glow and not cell.blight then
        out[#out + 1] = "mine"
    end
    return out
end

function Game:improve(u, what)
    local ok = false
    for _, k in ipairs(self:improvementsFor(u)) do if k == what then ok = true end end
    if not ok then return false end
    local cell = self.cells[u.cell]
    cell.improvement = what
    -- A fallow field (src/plague.lua) is worked again; a firebreak's ground
    -- sown, and so it can burn again.
    if what == "farm" and (cell.fallow or cell.cleared) then
        cell.fallow, cell.cleared = nil, nil
        self:emit({ kind = "terrain", cell = cell.id })
    end
    u.moves, u.acted = 0, true
    u.charges = u.charges - 1
    self:emit({ kind = "improve", cell = cell.id })
    if u.charges <= 0 then self:removeUnit(u) end
    return true
end

--- what else builders do to the land (D.WORKS) -----------------------------------------

-- What hex `cell` would be mended of first, if a builder of player p's
-- stood on it: "blight", "scorched", "basalt", "crater", "ash" or "marsh";
-- nil if nothing. The rest wait for another builder's turn.
function Game:mendable(cell, p)
    if cell.city or self:isWater(cell) or cell.elev == "mountain" or cell.fire or cell.flood or cell.lava then
        return nil
    end
    if cell.blight then
        return Cat.KINDS.demons.free(self, cell) and "blight" or nil
    end
    if cell.scorched and (self:onRiver(cell) or Cat.cool(cell)) then return "scorched" end
    if cell.basalt then return "basalt" end
    -- A crater with star iron in it is left for the mine.
    if cell.crater and not cell.glow and cell.resource ~= "iron" then return "crater" end
    if cell.ashfall then return "ash" end
    if cell.terrain == "marsh" and p.techs[D.WORKS.mend.marshTech] then return "marsh" end
    return nil
end

-- The burning hexes a builder on `cell` could beat out: its own, and the
-- land beside it.
function Game:douseable(cell)
    local out = {}
    if cell.fire and not self:isWater(cell) then out[1] = cell end
    for _, n in ipairs(self:neighbours(cell)) do
        if n.fire and not self:isWater(n) then out[#out + 1] = n end
    end
    return out
end

-- The works (D.WORKS) builder u can do where it stands. Chopping, cutting a
-- firebreak and mending are for its own land; a fire is fought anywhere.
function Game:worksFor(u)
    if u.kind ~= "builder" or u.moves <= 0 then return {} end
    local cell = self.cells[u.cell]
    local out = {}
    if self:isWater(cell) or cell.city then return out end
    local own = cell.owner == u.owner and cell.elev ~= "mountain"
    if own and cell.feature == "forest" and not cell.fire and not cell.blight then out[#out + 1] = "chop" end
    if own and cell.feature ~= "forest" and Cat.flammable(self, cell) then out[#out + 1] = "clear" end
    if #self:douseable(cell) > 0 then out[#out + 1] = "douse" end
    if own and self:mendable(cell, self.players[u.owner]) then out[#out + 1] = "mend" end
    return out
end

-- Builder u does work `what` (D.WORKS) where it stands; false if it can't.
function Game:work(u, what)
    local ok = false
    for _, k in ipairs(self:worksFor(u)) do if k == what then ok = true end end
    if not ok then return false end
    local cell = self.cells[u.cell]
    if what == "chop" then
        cell.feature, cell.felled = nil, true
        local city = cell.ownerCity
        if city and city.owner == u.owner then
            city.prod = city.prod + D.WORKS.chop.prod
            self:tell(u.owner, "THE FOREST'S WOOD HAS GONE TO {1}: {2} PRODUCTION", city.name, D.WORKS.chop.prod)

        end
        self:emit({ kind = "terrain", cell = cell.id })
    elseif what == "clear" then
        cell.cleared = true
        if cell.improvement == "farm" then cell.improvement = nil end
        if cell.resource == "wheat" then cell.resource = nil end
        if cell.terrain == "grass" then cell.terrain = "plains" end
        self:emit({ kind = "terrain", cell = cell.id })
    elseif what == "douse" then
        for _, c in ipairs(self:douseable(cell)) do
            c.fire = c.fire - D.WORKS.douse.turns
            if c.fire <= 0 or self:onRiver(c) or self:coastal(c) or Cat.cool(c) then Cat.burnOut(self, c) end
        end
        self:emit({ kind = "douse", cell = cell.id })
    elseif what == "mend" then
        local m = self:mendable(cell, self.players[u.owner])
        if m == "blight" then
            -- Burnt off: clean ground, black with the fire.
            cell.blight, cell.burnt = nil, true
        elseif m == "scorched" then
            cell.scorched, cell.terrain = nil, "plains"
        elseif m == "basalt" then
            cell.basalt = nil
            if cell.resource == "obsidian" then cell.resource = nil end
        elseif m == "crater" then
            -- Its pit filled; the ground stays as low as the stones left it.
            cell.crater = nil
        elseif m == "ash" then
            cell.ashfall, cell.soil = nil, true
        elseif m == "marsh" then
            cell.terrain = "grass"
        end
        self:emit({ kind = "terrain", cell = cell.id })
    end
    u.moves, u.acted = 0, true
    u.charges = u.charges - 1
    self:emit({ kind = "improve", cell = cell.id })
    if u.charges <= 0 then self:removeUnit(u) end
    return true
end

return Game
