local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"
local H = require "src.hex"

-- The wild (src/beasts.lua) is left off: these are the civilizations' rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false }) end

-- A land hex beside the coast, and that coast hex: somewhere to sail from.
local function shore(g)
    for _, cell in ipairs(g.cells) do
        if g:passable(cell) and not cell.city and not cell.owner then
            for _, n in ipairs(g:neighbours(cell)) do
                if n.terrain == "coast" and not g.mil[n.id] then return cell, n end
            end
        end
    end
end

-- Two land hexes with a river between and no one on them.
local function fordable(g)
    for _, cell in ipairs(g.cells) do
        for _, n in ipairs(g:neighbours(cell)) do
            if g:passable(cell) and g:passable(n) and g:riverBetween(cell, n) and not cell.city and not n.city
                and not g.mil[cell.id] and not g.mil[n.id] and not g.civ[cell.id] and not g.civ[n.id] then
                return cell, n
            end
        end
    end
end

local function find(g, owner, kind)
    for _, u in ipairs(g.units) do if u.owner == owner and u.kind == kind then return u end end
end

return {
    { "the same seed makes the same map", function()
        local a, b = newGame(11), newGame(11)
        for k, cell in ipairs(a.cells) do
            local o = b.cells[k]
            assert(cell.terrain == o.terrain and cell.elev == o.elev and cell.feature == o.feature and cell.top == o.top)
        end
    end },
    { "every civilization starts with a settler and a warrior on land", function()
        local g = newGame()
        for _, p in ipairs(g.players) do
            local s, w = find(g, p.id, "settler"), find(g, p.id, "warrior")
            assert(s and w)
            assert(g:passable(g.cells[s.cell]))
        end
    end },
    { "a settler founds a city that owns the hexes round it", function()
        local g = newGame()
        local s = find(g, 1, "settler")
        local cell = g.cells[s.cell]
        assert(g:canFound(s))
        local city = g:found(s)
        assert(city and city.capital and cell.city == city)
        assert(s.dead and not g.civ[cell.id])
        for _, n in ipairs(g:neighbours(cell)) do assert(n.owner == 1) end
        assert(#city.worked == 1)
        -- And no second city right next to it.
        local s2 = g:addUnit("settler", 1, g:neighbours(cell)[1].id)
        assert(not g:canFound(s2))
    end },
    { "a unit walks no further than its moves, and keeps on next turn", function()
        local g = newGame()
        local w = find(g, 1, "warrior")
        -- The furthest hex it could reach in two turns or more, by a way
        -- that fords no river (a ford takes all its moves).
        local function dry(path)
            local from = g.cells[w.cell]
            for _, id in ipairs(path) do
                if g:fords(from, g.cells[id]) then return false end
                from = g.cells[id]
            end
            return true
        end
        local goal
        for _, cell in ipairs(g:within(g.cells[w.cell], 5)) do
            local path = g:canStand(w, cell) and g:dist(cell, g.cells[w.cell]) >= 4 and g:path(w, cell.id)
            if path and dry(path) then goal = cell break end
        end
        assert(goal, "somewhere to go")
        g:moveTo(w, goal.id)
        assert(w.moves == 0)
        assert(w.dest == goal.id and w.cell ~= goal.id)
        local before = w.cell
        g:beginTurn(g.players[1])
        assert(w.cell ~= before, "carried on")
    end },
    { "rivers run from the hills to the sea, and only ever down", function()
        for _, seed in ipairs({ 5, 7, 11 }) do
            local g = newGame(seed)
            local edges, mouths = 0, 0
            for _, cell in ipairs(g.cells) do
                for k, e in pairs(cell.river or {}) do
                    -- On both hexes of the edge, between two land hexes.
                    local n = g:cell(H.step(cell.c, cell.r, k))
                    assert(n and n.river and n.river[(k + 3) % 6] == e, "the same river on both sides")
                    assert(not g:isWater(cell) and not g:isWater(n), "between land")
                    assert(e.level < math.min(cell.top, n.top), "below its banks")
                    edges = edges + 0.5
                    if e.mouth then mouths = mouths + 0.5 end
                end
            end
            assert(edges >= 15, "some rivers: " .. edges)
            assert(mouths >= 1, "that reach the sea")
            -- Each edge is at or below the one above it.
            for _, cell in ipairs(g.cells) do
                for _, e in pairs(cell.river or {}) do
                    for _, other in ipairs(g:within(cell, 1)) do
                        for _, f in pairs(other.river or {}) do
                            if f.from[1] == e.to[1] and f.from[2] == e.to[2] then
                                assert(f.level <= e.level + 1e-9, "no river runs uphill")
                            end
                        end
                    end
                end
            end
        end
    end },
    { "fording a river takes all a unit's moves, but not over a city's bridge", function()
        local g = newGame(7)
        local a, b = fordable(g)
        assert(a, "a river to ford")
        local w = g:addUnit("warrior", 1, a.id)
        assert(g:stepCost(w, a, b) == Game.ALL)
        assert(g:step(w, b.id) and w.moves == 0)
        assert(g:onRiver(a) and g:describe(a):find("RIVER"))
        local _, _, gold = g:yield(a)
        assert(gold >= D.RIVER.gold, "gold for the river")
        a.city = { owner = 1 }
        assert(g:stepCost(w, b, a) ~= Game.ALL, "a bridge")
        a.city = nil
    end },
    { "attacking across a river strikes weaker", function()
        local g = newGame(7)
        local a, b = fordable(g)
        local w = g:addUnit("warrior", 1, a.id)
        assert(g:attackStrength(w, false, b) == g:attackStrength(w, false) - D.RIVER.attack)
        assert(g:attackStrength(w, true, b) == g:attackStrength(w, true), "a shot is not")
    end },
    { "a melee attack hurts both sides and can kill", function()
        local g = newGame()
        local w = find(g, 1, "warrior")
        local here = g.cells[w.cell]
        local spot
        for _, n in ipairs(g:neighbours(here)) do
            if g:passable(n) and not g.mil[n.id] and not g.civ[n.id] then spot = n break end
        end
        local enemy = g:addUnit("warrior", 2, spot.id)
        assert(g:canAttack(w, spot))
        local dealt = g:forecast(w, spot)
        assert(dealt > 10)
        g:attack(w, spot)
        assert(w.moves == 0 and w.attacked)
        assert(enemy.hp < 100 or enemy.dead)
        assert(w.hp < 100)
        -- Kill it outright.
        g:beginTurn(g.players[1])
        if not enemy.dead then
            enemy.hp = 1
            g:attack(w, spot)
            assert(enemy.dead)
            assert(w.cell == spot.id, "the winner moves into the hex")
        end
    end },
    { "a city grows, builds what it is told and learns", function()
        local g = newGame()
        local city = g:found(find(g, 1, "settler"))
        g:setBuild(city, "unit", "warrior")
        g.players[1].researching = "pottery"
        local units = #g:unitsOf(1)
        for _ = 1, 25 do g:endTurn(AI) end
        assert(#g:unitsOf(1) > units or city.build == nil, "a warrior was trained")
        assert(g.players[1].techs.pottery, "pottery was learned")
        assert(city.pop >= 2, "the city grew")
    end },
    { "a city brought down by a melee unit changes hands", function()
        local g = newGame()
        local city = g:found(find(g, 2, "settler"))
        local home = g.cells[city.cell]
        local guard = g.mil[home.id]
        if guard then g:removeUnit(guard) end
        local spot
        for _, n in ipairs(g:neighbours(home)) do
            if g:passable(n) and not g.mil[n.id] then spot = n break end
        end
        local w = g:addUnit("swordsman", 1, spot.id)
        city.hp = 1
        g:attack(w, home)
        assert(city.owner == 1, "taken")
        assert(w.cell == home.id)
    end },
    { "builders improve hexes and wear out", function()
        local g = newGame()
        local city = g:found(find(g, 1, "settler"))
        local b
        for _, n in ipairs(g:neighbours(g.cells[city.cell])) do
            if n.elev == "flat" and not n.feature and n.terrain ~= "desert" and not D.TERRAIN[n.terrain].water then
                b = g:addUnit("builder", 1, n.id)
                break
            end
        end
        if not b then return end
        local f0 = g:yield(g.cells[b.cell])
        assert(g:improve(b, "farm"))
        -- A farm by a river yields a food more.
        assert(g:yield(g.cells[b.cell]) == f0 + 1 + (g:onRiver(g.cells[b.cell]) and D.RIVER.farmFood or 0))
        assert(b.charges == 2)
    end },
    { "land units take to the water only after sailing, and it takes all their moves", function()
        local g = newGame()
        local land, sea = shore(g)
        local w = g:addUnit("warrior", 1, land.id)
        assert(not g:canEnter(w, sea), "no boats before sailing")
        assert(not g:step(w, sea.id))
        g.players[1].techs.sailing = true
        assert(g:canEnter(w, sea))
        assert(g:stepCost(w, land, sea) == Game.ALL)
        w.moves = 1
        assert(g:step(w, sea.id), "embarks with any moves left")
        assert(w.cell == sea.id and w.moves == 0 and g:embarked(w))
        assert(g:defense(w) == D.EMBARK.str)
        g:beginTurn(g.players[1])
        assert(w.moves == D.EMBARK.moves, "a boat's moves on the water")
        -- Out on the water it cannot attack, even next to an enemy.
        local enemy = g:addUnit("warrior", 2, land.id)
        assert(not g:canAttack(w, land))
        g:removeUnit(enemy)
        -- And back onto the land, again for all its moves.
        assert(g:step(w, land.id))
        assert(w.moves == 0 and not g:embarked(w))
    end },
    { "the ocean wants cartography, for ships and boats alike", function()
        local g = newGame()
        g.players[1].techs.sailing = true
        local ocean
        for _, cell in ipairs(g.cells) do if cell.terrain == "ocean" then ocean = cell break end end
        assert(ocean, "the map has open ocean")
        local _, sea = shore(g)
        local ship = g:addUnit("galley", 1, sea.id)
        local w = g:addUnit("warrior", 1, shore(g).id)
        assert(not g:canEnter(ship, ocean) and not g:canEnter(w, ocean))
        assert(g:canEnter(ship, sea))
        assert(not g:canEnter(ship, shore(g)), "a ship does not sail onto the land")
        g.players[1].techs.cartography = true
        assert(g:canEnter(ship, ocean) and g:canEnter(w, ocean))
    end },
    { "only a city on the water builds ships and harbours, and they come out on the water", function()
        local g = newGame()
        local p = g.players[1]
        p.techs.pottery, p.techs.sailing, p.techs.shipbuilding = true, true, true
        local land = shore(g)
        local s = g:addUnit("settler", 1, land.id)
        for _, c in ipairs(g.cities) do g.cells[c.cell].city = nil end
        g.cities = {}
        local city = g:found(s)
        assert(city and g:coastal(g.cells[city.cell]))
        assert(g:canBuild(city, "unit", "galley") and g:canBuild(city, "building", "harbour"))
        assert(not g:canBuild(city, "building", "lighthouse"), "lighthouse wants cartography")
        g:setBuild(city, "unit", "galley")
        city.prod = 1000
        assert(g:complete(city))
        local ship = find(g, 1, "galley")
        assert(ship and g:isWater(g.cells[ship.cell]))
        -- A city inland cannot.
        for _, cell in ipairs(g.cells) do
            if g:passable(cell) and not g:coastal(cell) then
                local inland = { owner = 1, cell = cell.id, buildings = {} }
                assert(not g:canBuild(inland, "unit", "galley"))
                assert(not g:canBuild(inland, "building", "harbour"))
                break
            end
        end
    end },
    { "a galley sinks a boat but a soldier on the shore cannot touch a ship", function()
        local g = newGame()
        g.players[1].techs.sailing, g.players[2].techs.sailing = true, true
        local land, sea = shore(g)
        local ship = g:addUnit("galley", 1, sea.id)
        local soldier = g:addUnit("warrior", 2, land.id)
        assert(not g:canAttack(soldier, sea), "no melee from the land onto the water")
        assert(not g:canAttack(ship, land), "no ramming the beach")
        -- An enemy rowed out next to it is fair game.
        local water
        for _, n in ipairs(g:neighbours(sea)) do
            if n.terrain == "coast" and not g.mil[n.id] then water = n break end
        end
        assert(water)
        g:removeUnit(soldier)
        local boat = g:addUnit("warrior", 2, water.id)
        assert(g:embarked(boat) and g:canAttack(ship, water))
        local dealt = g:forecast(ship, water)
        assert(dealt >= 40, "a boat is easy prey: " .. dealt)
        boat.hp = 1
        g:attack(ship, water)
        assert(boat.dead and ship.cell == water.id)
    end },
    { "fishing boats, a harbour and a lighthouse feed a city from the sea", function()
        local g = newGame()
        local p = g.players[1]
        p.techs.pottery, p.techs.sailing, p.techs.shipbuilding, p.techs.cartography = true, true, true, true
        local land, sea = shore(g)
        sea.resource = "fish"
        local s = g:addUnit("settler", 1, land.id)
        for _, c in ipairs(g.cities) do g.cells[c.cell].city = nil end
        g.cities = {}
        local city = g:found(s)
        assert(sea.owner == 1)
        local f0, _, g0 = g:workYield(city, sea)
        local b = g:addUnit("builder", 1, sea.id)
        assert(g:embarked(b))
        local can = g:improvementsFor(b)
        assert(#can == 1 and can[1] == "boats")
        assert(g:improve(b, "boats"))
        city.buildings.harbour, city.buildings.lighthouse = true, true
        local f1, _, g1 = g:workYield(city, sea)
        assert(f1 == f0 + 2 and g1 == g0 + 1, "boats and harbour +2 food, lighthouse +1 gold")
        g:look(p)
        local far
        for _, cell in ipairs(g:within(g.cells[city.cell], 4)) do
            if g:dist(cell, g.cells[city.cell]) == 4 then far = cell break end
        end
        assert(p.visible[far.id], "the lighthouse sees 4 out")
    end },
    { "a hundred turns of computers playing every side run clean", function()
        local ships = 0
        for _, seed in ipairs({ 3, 8 }) do
            local g = Game.new({ seed = seed, allAI = true })
            for _ = 1, 100 do
                AI.play(g, g.players[1])
                g:endTurn(AI)
            end
            local cities = 0
            for _, p in ipairs(g.players) do cities = cities + #g:citiesOf(p.id) end
            assert(cities >= 6, "the world filled up a little: " .. cities)
            -- Every unit stands in the slot the game thinks it does.
            for _, u in ipairs(g.units) do
                assert(g:slot(u)[u.cell] == u, "unit " .. u.kind .. " is where it says")
                if u.def.sea then ships = ships + 1 end
            end
        end
        assert(ships > 0, "someone put to sea")
    end },
}
