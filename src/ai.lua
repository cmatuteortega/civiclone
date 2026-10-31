-- The other civilizations: simple, greedy and a little aggressive.
--
-- Each turn a computer player picks research, gives every city something to
-- build, then moves every unit: settlers go to the best free site in reach
-- and found a city there, builders improve the hexes their cities work, and
-- soldiers hit anything they can beat, guard their cities, explore, and --
-- once there are enough of them -- march on the nearest enemy city they know.

local Mapgen = require "src.mapgen"
local D = require "src.defs"

local max = math.max

local AI = {}

local function military(u) return not u.def.civilian end

-- The best unit of a class this city can build now: the strongest melee, or
-- a ranged one.
local function bestSoldier(game, city, ranged)
    local best, bv
    for _, it in ipairs(game:buildable(city)) do
        local def = it.def
        if it.kind == "unit" and not def.civilian and not def.sea and (def.ranged ~= nil) == ranged and it.id ~= "scout" then
            local v = (def.ranged or def.str) + def.moves
            if not bv or v > bv then best, bv = it.id, v end
        end
    end
    return best
end

-- The best ship this city can build, if it can build one.
local function bestShip(game, city)
    local best, bv
    for _, it in ipairs(game:buildable(city)) do
        if it.kind == "unit" and it.def.sea then
            local v = (it.def.ranged or it.def.str) + game.rng:random() * 6
            if not bv or v > bv then best, bv = it.id, v end
        end
    end
    return best
end

-- How many ships a civilization wants: one for every two cities on the
-- water, one more once it knows of a rival's city on the water, at most 3.
local function shipsWanted(game, p)
    local coastal = 0
    for _, c in ipairs(game:citiesOf(p.id)) do
        if game:coastal(game.cells[c.cell]) then coastal = coastal + 1 end
    end
    if coastal == 0 then return 0 end
    local want = math.ceil(coastal / 2)
    for _, c in ipairs(game.cities) do
        if c.owner ~= p.id and p.explored[c.cell] and game:coastal(game.cells[c.cell]) then want = want + 1 break end
    end
    return math.min(3, want)
end

local function count(game, p, kind)
    local n = 0
    for _, u in ipairs(game:unitsOf(p.id)) do if u.kind == kind then n = n + 1 end end
    for _, c in ipairs(game:citiesOf(p.id)) do
        if c.build and c.build.id == kind then n = n + 1 end
    end
    return n
end

local function chooseBuild(game, p, city)
    local soldiers = 0
    for _, u in ipairs(game:unitsOf(p.id)) do if military(u) then soldiers = soldiers + 1 end end
    local cities = #game:citiesOf(p.id)
    local guard = game.mil[city.cell]
    -- A city with no one in it, or a civilization with too few, trains a soldier.
    if (not guard and soldiers < cities * 2) or soldiers < cities then
        return "unit", bestSoldier(game, city, game.rng:random() < 0.3) or "warrior"
    end
    if cities + count(game, p, "settler") < 5 and city.pop >= 2 and game.turn > 4
        and count(game, p, "settler") == 0 then
        return "unit", "settler"
    end
    if count(game, p, "builder") < max(1, cities - 1) and game.turn > 6 then return "unit", "builder" end
    -- A ship or two from the cities on the water.
    if game.turn > 15 then
        local ship = bestShip(game, city)
        if ship then
            local ships = 0
            for _, u in ipairs(game:unitsOf(p.id)) do if u.def.sea then ships = ships + 1 end end
            for _, c in ipairs(game:citiesOf(p.id)) do
                if c.build and c.build.kind == "unit" and game:canBuild(c, "unit", c.build.id)
                    and D.UNITS[c.build.id].sea then ships = ships + 1 end
            end
            if ships < shipsWanted(game, p) then return "unit", ship end
        end
    end
    for _, id in ipairs({ "monument", "granary", "walls", "library", "harbour", "market", "lighthouse" }) do
        if game:canBuild(city, "building", id) then
            if id ~= "walls" or game.turn > 30 then return "building", id end
        end
    end
    if soldiers < cities * 3 + math.floor(game.turn / 15) then
        return "unit", bestSoldier(game, city, game.rng:random() < 0.35) or "warrior"
    end
    return "unit", "builder"
end

--- settlers ----------------------------------------------------------------------

-- The best free place to found a city that u can walk to, by what the land
-- round it yields, less the walk.
local function siteFor(game, u)
    local here = game.cells[u.cell]
    local best, bv
    for _, cell in ipairs(game:within(here, 9)) do
        if game:passable(cell) and not cell.city and (not cell.owner or cell.owner == u.owner) then
            local ok = true
            for _, c in ipairs(game.cities) do
                if game:dist(game.cells[c.cell], cell) < 4 then ok = false break end
            end
            if ok then
                local v = Mapgen.siteScore(game.cells, game.cols, game.rows, cell) - game:dist(here, cell) * 1.6
                if game:isWater(cell) then v = -1 end
                for _, n in ipairs(game:neighbours(cell)) do
                    if n.terrain == "coast" then v = v + 1 break end
                end
                if not bv or v > bv then best, bv = cell, v end
            end
        end
    end
    return best
end

local function settle(game, u)
    -- The first city where it stands, at once.
    if #game:citiesOf(u.owner) == 0 and game:canFound(u) then return game:found(u) end
    local site = u.site and game.cells[u.site]
    if site and (site.city or (site.owner and site.owner ~= u.owner)) then site = nil end
    if not site then
        site = siteFor(game, u)
        u.site = site and site.id
    end
    if not site then
        if game:canFound(u) then game:found(u) end
        return
    end
    if site.id == u.cell then
        if game:canFound(u) then game:found(u) else u.site = nil end
        return
    end
    if not game:moveTo(u, site.id) then u.site = nil end
    if u.cell == site.id and game:canFound(u) and u.moves > 0 then game:found(u) end
end

--- builders ------------------------------------------------------------------------

local function improve(game, u)
    local options = game:improvementsFor(u)
    local here = game.cells[u.cell]
    if #options > 0 and here.workedBy then
        return game:improve(u, options[#options])
    end
    -- The nearest worked hex with nothing on it that something could go on.
    local best, bd
    for _, cell in ipairs(game.cells) do
        if cell.workedBy and cell.owner == u.owner and not cell.improvement and not game.mil[cell.id]
            and not game.civ[cell.id] then
            local techs = game.players[u.owner].techs
            local can = (cell.elev == "flat" and not cell.feature and cell.terrain ~= "desert" and not game:isWater(cell))
                or (cell.elev == "hills" and techs.mining)
                or (cell.resource == "fish" and techs.sailing)
            if can then
                local d = game:dist(here, cell)
                if not bd or d < bd then best, bd = cell, d end
            end
        end
    end
    if best then
        game:moveTo(u, best.id)
        if u.cell == best.id and u.moves > 0 then
            local o = game:improvementsFor(u)
            if #o > 0 then game:improve(u, o[#o]) end
        end
    else
        u.fortified = true
    end
end

--- soldiers ------------------------------------------------------------------------

-- Hit the best target in reach, if the odds are good.
local function strike(game, u)
    local here = game.cells[u.cell]
    local best, bv
    local reach = u.def.ranged and u.def.range or 1
    for _, cell in ipairs(game:within(here, reach)) do
        if game:canAttack(u, cell) then
            local dealt, taken = game:forecast(u, cell)
            local target = game.mil[cell.id]
            local hp = cell.city and cell.city.hp or (target and target.hp or 0)
            local v = dealt - taken * 0.8 + (dealt >= hp and 40 or 0)
            if taken >= u.hp then v = -100 end
            -- A city at nothing is the best target there is.
            if cell.city and cell.city.hp <= 0 and not u.def.ranged then v = 200 end
            if v > 0 and (not bv or v > bv) then best, bv = cell, v end
        end
    end
    if best then return game:attack(u, best) end
end

-- The nearest thing of an enemy's this player has seen: a city first.
local function targetFor(game, p, u)
    local here = game.cells[u.cell]
    local best, bd
    for _, c in ipairs(game.cities) do
        if c.owner ~= p.id and p.explored[c.cell] then
            local d = game:dist(here, game.cells[c.cell])
            if not bd or d < bd then best, bd = game.cells[c.cell], d end
        end
    end
    if best then return best end
    for _, v in ipairs(game.units) do
        if v.owner ~= p.id and p.visible[v.cell] then
            local d = game:dist(here, game.cells[v.cell])
            if not bd or d < bd then best, bd = game.cells[v.cell], d end
        end
    end
    return best
end

-- The nearest hex this player has not seen, that a unit could stand next to.
local function frontier(game, p, u)
    local here = game.cells[u.cell]
    local best, bd
    for _, cell in ipairs(game.cells) do
        if not p.explored[cell.id] and game:canEnter(u, cell) then
            local d = game:dist(here, cell) + game.rng:random() * 2
            if not bd or d < bd then best, bd = cell, d end
        end
    end
    return best
end

local function march(game, u, goal)
    if not goal or goal.id == u.cell then return false end
    local enemy = game:foreignAt(goal, u.owner)
    local path = game:path(u, goal.id, enemy ~= nil)
    if not path then return false end
    if #path > 0 then game:walk(u, path) end
    return true
end

-- A ship: strike, go home when hurt, sail on the enemy's cities on the water
-- when the army marches, and otherwise chart the coast.
local function ship(game, p, u, attacking)
    if strike(game, u) then return end
    if u.hp < 50 then
        for _, c in ipairs(game:citiesOf(p.id)) do
            if game:canEnter(u, game.cells[c.cell]) and not game.mil[c.cell] then
                march(game, u, game.cells[c.cell])
                break
            end
        end
        return
    end
    if attacking then
        local here = game.cells[u.cell]
        local best, bd
        for _, c in ipairs(game.cities) do
            local cell = game.cells[c.cell]
            if c.owner ~= p.id and p.explored[c.cell] and game:coastal(cell) then
                local d = game:dist(here, cell)
                if not bd or d < bd then best, bd = cell, d end
            end
        end
        if best and march(game, u, best) then
            strike(game, u)
            return
        end
    end
    if not march(game, u, frontier(game, p, u)) then u.fortified = true end
end

local function soldier(game, p, u, attacking)
    if u.def.sea then return ship(game, p, u, attacking) end
    if strike(game, u) then return end
    -- Wounded: back home to heal.
    if u.hp < 45 then
        local home = game:citiesOf(p.id)[1]
        if home and u.cell ~= home.cell and not game.mil[home.cell] then
            march(game, u, game.cells[home.cell])
        end
        u.fortified = u.moves > 0
        return
    end
    if u.kind == "scout" then
        if not march(game, u, frontier(game, p, u)) then u.fortified = true end
        return
    end
    -- An empty city of ours, nearest first.
    for _, c in ipairs(game:citiesOf(p.id)) do
        if not game.mil[c.cell] and game:dist(game.cells[u.cell], game.cells[c.cell]) <= 6 then
            march(game, u, game.cells[c.cell])
            if u.cell == c.cell then u.fortified = true end
            return
        end
    end
    -- A guard stays home unless the army is marching.
    local here = game.cells[u.cell]
    if here.city and here.city.owner == p.id and not attacking then
        u.fortified = true
        return
    end
    if attacking then
        local goal = targetFor(game, p, u)
        if goal then
            march(game, u, goal)
            strike(game, u)
            return
        end
    end
    if not march(game, u, frontier(game, p, u)) then u.fortified = true end
end

function AI.play(game, p)
    if not p.researching then
        local list = game:researchable(p)
        if #list > 0 then p.researching = list[game.rng:random(#list)].id end
    end
    for _, city in ipairs(game:citiesOf(p.id)) do
        if not city.build then
            local kind, id = chooseBuild(game, p, city)
            if not game:setBuild(city, kind, id) then game:setBuild(city, "unit", "warrior") end
        end
        -- Buy a soldier when an enemy is at the gates.
        if city.hp < game:maxHp(city) and city.build and city.build.kind == "unit" then game:buy(city) end
    end
    local soldiers = 0
    for _, u in ipairs(game:unitsOf(p.id)) do if military(u) and u.kind ~= "scout" then soldiers = soldiers + 1 end end
    local attacking = game.turn >= 25 and soldiers >= 2 + #game:citiesOf(p.id)
    -- A copy: units die and found cities as the list is walked.
    local units = {}
    for k, u in ipairs(game:unitsOf(p.id)) do units[k] = u end
    for _, u in ipairs(units) do
        if not u.dead and u.moves > 0 then
            u.fortified = false
            if u.kind == "settler" then settle(game, u)
            elseif u.kind == "builder" then improve(game, u)
            else soldier(game, p, u, attacking) end
        end
    end
end

return AI
