-- The fabric of a city of several hexes (src/quarters.lua).
local Q = require "src.quarters"
local H = require "src.hex"
local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"
local Save = require "src.save"

local function newGame(seed) return Game.new({ seed = seed or 5, wild = false }) end

-- A city of the player's, founded where its settler starts, grown to `pop`.
local function cityOf(g, pop)
    for _, u in ipairs(g.units) do
        if u.owner == 1 and u.kind == "settler" then
            local c = g:found(u)
            c.pop = pop or 1
            return c
        end
    end
end

local function count(set) local n = 0 for _ in pairs(set) do n = n + 1 end return n end

return {
    { "a city alone stands a tower on every corner, and no gate", function()
        local f = Q.fabric({ { c = 2, r = 2 } })
        assert(count(f[1].towers) == 6 and count(f[1].joins) == 0 and not f[1].gate)
    end },
    { "two hexes share an edge, and the outline's corners are towered once", function()
        local c, r = H.step(2, 2, 0)
        local f = Q.fabric({ { c = 2, r = 2 }, { c = c, r = r } })
        assert(f[1].joins[0] and f[2].joins[3])
        assert(f[2].toward == 3 and f[2].gate == 0)
        -- Ten corners round two hexes, each stood by one of them.
        assert(count(f[1].towers) + count(f[2].towers) == 10)
    end },
    { "where three meet, the corner inside them has no tower", function()
        local c1, r1 = H.step(2, 2, 0)
        local c2, r2 = H.step(2, 2, 1)
        local f = Q.fabric({ { c = 2, r = 2 }, { c = c1, r = r1 }, { c = c2, r = r2 } })
        assert(count(f[1].towers) + count(f[2].towers) + count(f[3].towers) == 12)
        assert(not f[1].towers[1])
    end },
    { "a city's middle houses six, and past that it grows slower, then not at all", function()
        local g = newGame()
        local c = cityOf(g, 5)
        assert(Q.housing(g, c) == D.QUARTER.home and Q.pace(g, c) == 1)
        c.pop = D.QUARTER.home
        assert(Q.pace(g, c) == D.QUARTER.slow)
        c.pop = D.QUARTER.home + D.QUARTER.over
        assert(Q.pace(g, c) == 0)
        c.food = 0
        for _ = 1, 30 do g:finishTurn(g.players[1]) end
        assert(c.pop <= D.QUARTER.home + D.QUARTER.over, "it did not grow past its room")
    end },
    { "a quarter is built on a hex of its own beside it, and houses five more", function()
        local g = newGame()
        local c = cityOf(g, 4)
        assert(not Q.due(g, c) and #g:buildable(c) > 0)
        local sites = Q.sites(g, c)
        assert(#sites > 0, "somewhere to build")
        c.pop = D.QUARTER.home
        assert(Q.due(g, c))
        local listed
        for _, it in ipairs(g:buildable(c)) do if it.kind == "quarter" then listed = it end end
        assert(listed and listed.def.cost == D.QUARTER.cost[1], "the build list offers it")
        local site = Q.best(g, c)
        assert(g:setBuild(c, "quarter", site.id))
        assert(not g:setBuild(c, "quarter", c.cell), "not on the city's own hex")
        g:setBuild(c, "quarter", site.id)
        c.prod = D.QUARTER.cost[1]
        assert(g:complete(c))
        assert(site.quarter == c and c.quarters[1] == site.id)
        assert(Q.housing(g, c) == D.QUARTER.home + D.QUARTER.each)
        assert(not site.workedBy, "it is worked no more")
        for _, id in ipairs(c.worked) do assert(id ~= site.id) end
        assert(Q.cost(c) == D.QUARTER.cost[2])
        assert(g:describe(site):find("QUARTER OF " .. c.name))
    end },
    { "a quarter burned is lost, and the people it housed with it", function()
        local g = newGame()
        local c = cityOf(g, 6)
        local site = Q.best(g, c)
        Q.add(g, c, site)
        c.pop = 10
        site.fire = 3
        Q.tend(g, c)
        assert(not site.quarter and #c.quarters == 0)
        assert(c.pop == D.QUARTER.home, "down to what it has room for")
    end },
    { "an enemy in a quarter sacks it, and it mends once left", function()
        local g = newGame()
        local c = cityOf(g, 8)
        local site = Q.best(g, c)
        Q.add(g, c, site)
        local foe = g:addUnit("warrior", 2, site.id)
        Q.tend(g, c)
        assert(site.sacked and Q.housing(g, c) == D.QUARTER.home)
        g:removeUnit(foe)
        for _ = 1, D.QUARTER.mend do Q.tend(g, c) end
        assert(not site.sacked and Q.housing(g, c) == D.QUARTER.home + D.QUARTER.each)
    end },
    { "quarters are kept in a saved game", function()
        local g = newGame()
        local c = cityOf(g, 7)
        local site = Q.best(g, c)
        Q.add(g, c, site)
        local back = Save.decode(Save.encode(g))
        local bc
        for _, x in ipairs(back.cities) do if x.id == c.id then bc = x end end
        local bs = back.cells[site.id]
        assert(bs.quarter == bc and bc.quarters[1] == site.id)
    end },
    { "the others grow their cities out over quarters", function()
        local g = Game.new({ seed = 21, allAI = true, wild = false })
        for _ = 1, 140 do
            AI.play(g, g.players[1])
            g:endTurn(AI)
        end
        local n, most = 0, 0
        for _, c in ipairs(g.cities) do
            n = n + #(c.quarters or {})
            most = math.max(most, c.pop)
            for _, id in ipairs(c.quarters or {}) do assert(g.cells[id].quarter == c) end
            -- A sacked quarter houses no one, but turns no one out.
            local room = D.QUARTER.home + D.QUARTER.each * #(c.quarters or {})
            assert(c.pop <= room + D.QUARTER.over, c.name .. " is past its room: " .. c.pop .. "/" .. room)
        end
        assert(n > 0, "some quarters were built")
    end },
}
