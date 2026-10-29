local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"

local function newGame(seed) return Game.new({ seed = seed or 5 }) end

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
        -- The furthest hex it could reach in two turns or more.
        local goal
        for _, cell in ipairs(g:within(g.cells[w.cell], 5)) do
            if g:canStand(w, cell) and g:dist(cell, g.cells[w.cell]) >= 4 and g:path(w, cell.id) then goal = cell break end
        end
        assert(goal, "somewhere to go")
        g:moveTo(w, goal.id)
        assert(w.moves == 0)
        assert(w.dest == goal.id and w.cell ~= goal.id)
        local before = w.cell
        g:beginTurn(g.players[1])
        assert(w.cell ~= before, "carried on")
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
        assert(g:yield(g.cells[b.cell]) == f0 + 1)
        assert(b.charges == 2)
    end },
    { "a hundred turns of computers playing every side run clean", function()
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
            end
        end
    end },
}
