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
local Mapgen = require "src.mapgen"
local Beasts = require "src.beasts"
local Cat = require "src.cataclysm"

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
        self:addUnit("warrior", k, start.id)
        local near = self:freeNear(start.id, false)
        if near then self:addUnit("scout", k, near) end
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

-- Can a land unit stand here at all?
function Game:passable(cell)
    return not self:isWater(cell) and cell.elev ~= "mountain"
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
    if from.city or to.city then return false end
    return self:riverBetween(from, to) ~= nil
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
    if not water then return cell.elev ~= "mountain" end
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
    if u.def.sea then return 1 end
    local fw, tw = self:isWater(from), self:isWater(to)
    if fw ~= tw then return Game.ALL end
    if tw then return 1 end
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
    if cell.elev == "mountain" or cell.fire or cell.flood then return 0, 0, 0 end
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
    if cell.city then f, p = max(f, 2), max(p, 1) end
    return f, p, g
end

-- The name of what is on a cell, for the screen: "GRASSLAND HILLS FOREST".
function Game:describe(cell)
    local parts = {}
    if cell.elev == "mountain" then
        parts[1] = "MOUNTAINS"
    else
        parts[1] = D.TERRAIN[cell.terrain].name
        if cell.elev == "hills" then parts[#parts + 1] = "HILLS" end
    end
    if cell.feature then parts[#parts + 1] = D.FEATURE[cell.feature].name end
    if cell.resource then parts[#parts + 1] = D.RESOURCE[cell.resource].name end
    if cell.improvement then parts[#parts + 1] = D.IMPROVEMENT[cell.improvement].name end
    if self:onRiver(cell) then parts[#parts + 1] = "RIVER" end
    if cell.flood then parts[#parts + 1] = "- FLOODED"
    elseif cell.silt then parts[#parts + 1] = "- SILT"
    elseif cell.drowned then parts[#parts + 1] = "- DROWNED LAND" end
    if cell.glow then parts[#parts + 1] = "- FRESH CRATER"
    elseif cell.crater then parts[#parts + 1] = "- CRATER" end
    if cell.blight then parts[#parts + 1] = "- BLIGHTED" end
    if cell.fire then parts[#parts + 1] = "- BURNING"
    elseif cell.scorched then parts[#parts + 1] = "- SCORCHED"
    elseif cell.burnt then parts[#parts + 1] = "- BURNT" end
    if cell.lair then parts[#parts + 1] = "- " .. cell.lair.def.name end
    return table.concat(parts, " ")
end

--- events and the log --------------------------------------------------------------

function Game:emit(e) self.events[#self.events + 1] = e end

-- Something to tell player `who` (or everyone, if nil).
function Game:tell(who, text)
    self.log[#self.log + 1] = { turn = self.turn, who = who, text = text }
end

--- units ---------------------------------------------------------------------------

function Game:addUnit(kind, owner, cellId)
    local def = assert(D.UNITS[kind] or D.BEASTS[kind], kind)
    local u = { id = self.nextId, kind = kind, def = def, owner = owner, cell = cellId,
        hp = 100, moves = def.moves, charges = def.charges, trail = { cellId } }
    self.nextId = self.nextId + 1
    self.units[#self.units + 1] = u
    if def.civilian then self.civ[cellId] = u else self.mil[cellId] = u end
    return u
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
    local open = { start }
    local function h(id) local c = self.cells[id] return H.distance(c.c, c.r, g.c, g.r) end
    while #open > 0 do
        local bi, bv = 1, math.huge
        for k, id in ipairs(open) do
            local v = cost[id] + h(id)
            if v < bv then bi, bv = k, v end
        end
        local id = table.remove(open, bi)
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
                    if not cost[n.id] then open[#open + 1] = n.id end
                    cost[n.id], from[n.id] = c, id
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
        -- it carry us on.
        local cell = self.cells[id]
        if not self:canStand(u, cell) then
            local cost = self:stepCost(u, self.cells[u.cell], cell)
            local nextId = path[k + 1]
            local nextCost = nextId and self:stepCost(u, cell, self.cells[nextId])
            if not cost or not nextCost or cost == Game.ALL or nextCost == Game.ALL
                or u.moves - cost < nextCost then break end
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
    self:tell(u.owner, "A " .. u.def.name .. " WAS CAPTURED")
    if u.kind == "settler" or u.kind == "builder" then
        local taken = self:addUnit("builder", by.owner, cell)
        taken.moves = 0
        self:tell(by.owner, "CAPTURED A " .. u.def.name)
    end
    self:emit({ kind = "capture", cell = cell })
end

--- combat --------------------------------------------------------------------------

-- How strong a unit stands defending its cell.
function Game:defense(u)
    local cell = self.cells[u.cell]
    local base = self:embarked(u) and D.EMBARK.str or u.def.str
    local s = base - floor((100 - u.hp) / 10)
    s = s + D.ELEV[cell.elev].defense + (cell.feature and D.FEATURE[cell.feature].defense or 0)
    if u.fortified then s = s + D.COMBAT.fortify end
    return s
end

-- How hard u strikes: its strength, less its wounds; and, given the cell it
-- strikes, less again for a melee attack across a river.
function Game:attackStrength(u, ranged, cell)
    local base = ranged and u.def.ranged or u.def.str
    local s = base - floor((100 - u.hp) / 10) + Beasts.nightBonus(self, u)
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
    elseif target.hp <= 0 and not ranged and u.owner ~= Game.WILD and target.def.lives ~= "shore" and self:canEnter(u, cell) then
        -- Into the hex it won.
        self:relocate(u, cell.id)
    end
    return true
end

-- `by`: the owner of what killed it, and `killer` the unit, if one did.
function Game:kill(u, by, killer)
    self:removeUnit(u)
    self:emit({ kind = "death", cell = u.cell, unit = u })
    if u.owner == Game.WILD then
        Beasts.slain(self, u, by)
        return
    end
    if by == Game.WILD then
        self:tell(u.owner, "OUR " .. u.def.name .. " WAS KILLED BY " .. (killer and ("A " .. killer.def.name) or "THE WILD"))
    else
        self:tell(u.owner, "OUR " .. u.def.name .. " WAS KILLED")
        if by then self:tell(by, "ENEMY " .. u.def.name .. " DESTROYED") end
    end
    self:checkAlive(self.players[u.owner])
end

--- cities --------------------------------------------------------------------------

-- Can unit u found a city where it stands?
function Game:canFound(u)
    if u.kind ~= "settler" or u.moves <= 0 then return false end
    local cell = self.cells[u.cell]
    if not self:passable(cell) or cell.city or (cell.lair and (cell.lair.def.beast or cell.lair.def.demon)) then return false end
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
    self:tell(u.owner, name .. " WAS FOUNDED")
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
-- food first.
function Game:assignWork(city)
    for _, id in ipairs(city.worked) do
        if self.cells[id].workedBy == city then self.cells[id].workedBy = nil end
    end
    city.worked = {}
    local home = self.cells[city.cell]
    local choices = {}
    for _, cell in ipairs(self:within(home, D.CITY.workRadius)) do
        if cell.owner == city.owner and not cell.city and not cell.workedBy and cell.elev ~= "mountain" then
            local f, p, g = self:workYield(city, cell)
            choices[#choices + 1] = { cell = cell, v = f * 2.2 + p * 2 + g + self.rng:random() * 0.01 }
        end
    end
    table.sort(choices, function(a, b) return a.v > b.v end)
    for k = 1, min(city.pop, #choices) do
        local cell = choices[k].cell
        cell.workedBy = city
        city.worked[#city.worked + 1] = cell.id
    end
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
    f = f - Cat.thirst(self, city)
    return f, p, g, sci, cul
end

-- Can this player build `kind` ("unit" or "building", id) in this city?
function Game:canBuild(city, kind, id)
    local p = self.players[city.owner]
    local def = kind == "unit" and D.UNITS[id] or D.BUILDINGS[id]
    if not def then return false end
    if def.tech and not p.techs[def.tech] then return false end
    if kind == "building" and city.buildings[id] then return false end
    -- What holds a cataclysm off, only against that one ("any": against
    -- whichever it is, but not when there is none).
    if def.ward == "any" then
        if not self.cataclysm then return false end
    elseif def.ward and not Cat.is(self, def.ward) then
        return false
    end
    -- Ships, harbours and lighthouses only by the water.
    if (def.sea or def.coastal) and not self:coastal(self.cells[city.cell]) then return false end
    return true
end

-- Everything the city could build now, units then buildings, in order.
function Game:buildable(city)
    local out = {}
    for _, kind in ipairs({ "unit", "building" }) do
        local list = {}
        for id, def in pairs(kind == "unit" and D.UNITS or D.BUILDINGS) do
            if self:canBuild(city, kind, id) then list[#list + 1] = { kind = kind, id = id, def = def } end
        end
        table.sort(list, function(a, b) return a.def.order < b.def.order end)
        for _, it in ipairs(list) do out[#out + 1] = it end
    end
    return out
end

function Game:setBuild(city, kind, id)
    if not self:canBuild(city, kind, id) then return false end
    city.build = { kind = kind, id = id }
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
    local def = city.build.kind == "unit" and D.UNITS[city.build.id] or D.BUILDINGS[city.build.id]
    return ceil(max(0, def.cost - city.prod) * 2.5) + 5
end

function Game:buy(city)
    local cost = self:buyCost(city)
    local p = self.players[city.owner]
    if not cost or p.gold < cost or city.bought then return false end
    local def = city.build.kind == "unit" and D.UNITS[city.build.id] or D.BUILDINGS[city.build.id]
    if city.build.kind == "unit" and not self:placeFor(city, def) then return false end
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

-- Finishes what the city is building, if it can: answers whether it did.
function Game:complete(city)
    local b = city.build
    if b.kind == "unit" then
        local def = D.UNITS[b.id]
        if def.pop and city.pop <= def.pop then return false end
        local at = self:placeFor(city, def)
        if not at then return false end
        local u = self:addUnit(b.id, city.owner, at)
        u.moves = 0
        if def.pop then
            city.pop = city.pop - def.pop
            city.food = 0
            self:assignWork(city)
        end
        self:tell(city.owner, city.name .. " TRAINED A " .. def.name)
        self:emit({ kind = "built", cell = city.cell, unit = u })
    else
        city.buildings[b.id] = true
        if b.id == "walls" then city.hp = self:maxHp(city) end
        self:tell(city.owner, city.name .. " BUILT A " .. D.BUILDINGS[b.id].name)
        self:emit({ kind = "built", cell = city.cell })
    end
    local def = b.kind == "unit" and D.UNITS[b.id] or D.BUILDINGS[b.id]
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
    self:tell(old, city.name .. " HAS FALLEN TO " .. self.players[u.owner].name)
    self:tell(u.owner, "WE HAVE TAKEN " .. city.name)
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
    self:tell(nil, p.name .. " HAS BEEN DESTROYED")
    self:emit({ kind = "eliminated", player = p.id })
end

--- science -------------------------------------------------------------------------

function Game:canResearch(p, id)
    local t = D.TECH[id]
    if not t or p.techs[id] then return false end
    for _, need in ipairs(t.needs) do if not p.techs[need] then return false end end
    return true
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
            see(cell, u.def.sight + (cell.elev == "hills" and 1 or 0))
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
    for _, c in ipairs(self:citiesOf(p.id)) do c.bought = false end
end

-- The end of a player's turn: its cities grow and build, its science and
-- gold come in, its walls shoot.
function Game:finishTurn(p)
    local sci, gold = 0, 0
    for _, city in ipairs(self:citiesOf(p.id)) do
        self:assignWork(city)
        local f, pr, g, s, cu = self:cityYield(city)
        sci, gold = sci + s, gold + g
        -- Food: two a citizen; the rest stored towards the next.
        city.food = city.food + f - city.pop * 2
        if city.food >= self:growthNeed(city) then
            city.food = city.food - self:growthNeed(city)
            city.pop = city.pop + 1
            self:assignWork(city)
            self:tell(p.id, city.name .. " HAS GROWN TO " .. city.pop)
            self:emit({ kind = "grow", cell = city.cell, city = city })
        elseif city.food < 0 then
            if city.pop > 1 then
                city.pop = city.pop - 1
                self:assignWork(city)
                self:tell(p.id, city.name .. " IS STARVING")
            end
            city.food = 0
        end
        if city.build then
            city.prod = city.prod + pr
            local def = city.build.kind == "unit" and D.UNITS[city.build.id] or D.BUILDINGS[city.build.id]
            if city.prod >= def.cost then self:complete(city) end
        end
        city.culture = city.culture + cu
        if city.culture >= self:borderNeed(city) then
            city.culture = city.culture - self:borderNeed(city)
            self:growBorder(city)
        end
        city.hp = min(self:maxHp(city), city.hp + D.CITY.heal)
        self:cityStrike(city)
    end
    -- Upkeep: a unit beyond the free ones costs one gold.
    local units = #self:unitsOf(p.id)
    local cities = #self:citiesOf(p.id)
    gold = gold - max(0, units - (2 + cities))
    p.gold = max(0, p.gold + gold)
    p.lastGold, p.lastScience = gold, sci
    if p.researching then
        p.science = p.science + sci
        local t = D.TECH[p.researching]
        if p.science >= t.cost then
            p.science = p.science - t.cost
            p.techs[t.id] = true
            p.researching = nil
            self:tell(p.id, "WE HAVE LEARNED " .. t.name)
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

function Game:score(p)
    local s = 0
    for _, c in ipairs(self:citiesOf(p.id)) do s = s + 5 + c.pop * 2 end
    for _ in pairs(p.techs) do s = s + 4 end
    for _ in pairs(p.explored) do s = s + 0.05 end
    -- Demons slain, rifts sealed, the citadel razed (src/demons.lua).
    s = s + (p.glory or 0)
    return floor(s)
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
function Game:endTurn(ai)
    local me = self.players[1]
    self:finishTurn(me)
    for k = 2, #self.players do
        local p = self.players[k]
        if p.alive then
            self.current = k
            self:beginTurn(p)
            if ai then ai.play(self, p) end
            self:finishTurn(p)
        end
    end
    self:wildTurn()
    self.current = 1
    self.turn = self.turn + 1
    Cat.turn(self)
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
    u.moves, u.acted = 0, true
    u.charges = u.charges - 1
    self:emit({ kind = "improve", cell = cell.id })
    if u.charges <= 0 then self:removeUnit(u) end
    return true
end

return Game
