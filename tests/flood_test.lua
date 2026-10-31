local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local Flood = require "src.flood"
local D = require "src.defs"

-- The wild is left off: these are the deluge's rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false, cataclysm = "flood" }) end

local function free(g, cell) return not g.mil[cell.id] and not g.civ[cell.id] and not cell.city end

local function find(g, f)
    for _, cell in ipairs(g.cells) do if free(g, cell) and f(cell) then return cell end end
end

local function count(g, f)
    local n = 0
    for _, cell in ipairs(g.cells) do if f(cell) then n = n + 1 end end
    return n
end

local function settle(g)
    for _, u in ipairs(g.units) do
        if u.owner == 1 and u.kind == "settler" then return g:found(u) end
    end
end

return {
    { "the deluge's stages come on their turns", function()
        assert(Cat.stageAt(D.FLOOD.omen - 1, "flood") == nil)
        assert(Cat.stageAt(D.FLOOD.omen, "flood") == "omen")
        assert(Cat.stageAt(D.FLOOD.rains, "flood") == "rains")
        assert(Cat.stageAt(D.FLOOD.floods + 1, "flood") == "floods")
        assert(Cat.stageAt(D.LAST_TURN, "flood") == "sea")
        local g = newGame()
        assert(g.cataclysm.kind == "flood")
        assert(Cat.label(g) == nil)
        g.turn = D.FLOOD.rains
        assert(Cat.label(g) == "RAINS " .. (D.LAST_TURN - D.FLOOD.rains + 1))
        assert(Cat.past(g, "rains") and not Cat.past(g, "drought"), "the heat's stages are not the deluge's")
        g.turn = D.FLOOD.omen
        Cat.turn(g)
        assert(g.log[#g.log].text:find("LONG RAINS"))
    end },
    { "the rains wet the land a step at a time, and the low grass by water goes to marsh", function()
        local g = newGame()
        local desert = count(g, function(c) return c.terrain == "desert" end)
        g.turn = D.FLOOD.rains
        for _ = 1, 25 do Cat.turn(g) end
        assert(count(g, function(c) return c.terrain == "desert" end) < desert)
        assert(count(g, function(c) return c.terrain == "marsh" end) > 0)
        for _, c in ipairs(g.cells) do
            if c.terrain == "marsh" then assert(c.elev == "flat", "no marsh on the hills") end
        end
    end },
    { "wetting greens the desert, and marsh sinks the farm", function()
        local g = newGame()
        local cell = find(g, function(c) return c.terrain == "desert" and c.elev == "flat" and not c.feature end)
        Flood.wetten(g, cell)
        assert(cell.terrain == "plains")
        Flood.wetten(g, cell)
        assert(cell.terrain == "grass")
        cell.improvement, cell.resource = "farm", "wheat"
        Flood.wetten(g, cell)
        assert(cell.terrain == "marsh" and not cell.improvement and not cell.resource)
        assert(g:moveCost(cell) == 2, "marsh is heavy going")
    end },
    { "the rains feed the farms, and the flood's silt feeds the land", function()
        local g = newGame()
        local cell = find(g, function(c) return c.terrain == "grass" and c.elev == "flat" and not c.feature and not c.resource end)
        cell.improvement = "farm"
        local before = g:yield(cell)
        g.turn = D.FLOOD.rains
        assert(g:yield(cell) == before + D.FLOOD.rainFarm)
        cell.improvement = nil
        local bare = g:yield(cell)
        cell.silt = true
        assert(g:yield(cell) == bare + D.FLOOD.siltFood)
    end },
    { "a flood lies a few turns, yields nothing, hurts who stands in it, and leaves silt", function()
        local g = newGame()
        local cell = find(g, function(c) return Flood.floodable(g, c) and g:onRiver(c) end)
        assert(cell, "a river hex")
        cell.improvement = "farm"
        local u = g:addUnit("warrior", 1, cell.id)
        g.turn = D.FLOOD.floods
        g.cataclysm.stage = "floods"
        Flood.inundate(g, cell)
        assert(cell.flood == D.FLOOD.last)
        assert(select(1, g:yield(cell)) == 0)
        assert(g:describe(cell):find("FLOODED"))
        for _ = 1, D.FLOOD.last do Cat.turn(g) end
        assert(u.hp < 100, "the water hurt it")
        if not cell.flood then
            assert(cell.silt and not cell.improvement, "the farm is gone, the silt left")
        end
    end },
    { "floods start on the rivers and run on from them", function()
        local g = newGame()
        g.turn = D.FLOOD.floods
        local seen = 0
        for _ = 1, 12 do
            Cat.turn(g)
            for _, c in ipairs(g.cells) do
                if c.flood then
                    seen = seen + 1
                    assert(c.elev == "flat" and not c.city, "only low land floods")
                end
            end
        end
        assert(seen > 0)
        assert(count(g, function(c) return c.silt end) > 0, "and goes down again")
    end },
    { "a levee keeps the water off its city", function()
        local g = newGame()
        local city = settle(g)
        local home = g.cells[city.cell]
        local near
        for _, n in ipairs(g:neighbours(home)) do
            if Flood.floodable(g, n) then near = n end
        end
        if not near then return end
        g.turn = D.FLOOD.floods
        g.cataclysm.stage = "floods"
        near.flood = 2
        local hp = city.hp
        Cat.turn(g)
        assert(city.hp < hp)
        city.hp = hp
        city.buildings.levee = true
        near.flood = 2
        Cat.turn(g)
        assert(city.hp == hp, "the levee held")
    end },
    { "fever takes food from the floods on, less with a levee", function()
        local g = newGame()
        local city = settle(g)
        g.turn = D.FLOOD.rains
        assert(Cat.thirst(g, city) == 0)
        g.turn = D.FLOOD.sea
        assert(Cat.thirst(g, city) == D.FLOOD.fever.sea)
        city.buildings.levee = true
        assert(Cat.thirst(g, city) == D.FLOOD.fever.sea - D.FLOOD.leveeFever)
    end },
    { "the levee is built only against the deluge, the cistern only against the heat", function()
        local g = newGame()
        local city = settle(g)
        g.players[1].techs.masonry = true
        assert(g:canBuild(city, "building", "levee"))
        assert(not g:canBuild(city, "building", "cistern"))
        local h = Game.new({ seed = 5, wild = false })
        local c2 = settle(h)
        h.players[1].techs.masonry = true
        assert(h:canBuild(c2, "building", "cistern") and not h:canBuild(c2, "building", "levee"))
    end },
    { "the sea takes the low shore, lowest first, but not the hills nor a levee's land", function()
        local g = newGame()
        local water = count(g, function(c) return g:isWater(c) end)
        g.turn = D.FLOOD.sea
        for _ = 1, 10 do Cat.turn(g) end
        local drowned = count(g, function(c) return c.drowned end)
        assert(count(g, function(c) return g:isWater(c) end) == water + drowned)
        assert(drowned > 10, "about three a turn")
        for _, c in ipairs(g.cells) do
            if c.drowned then
                assert(c.terrain == "coast" and c.elev == "flat" and not c.city)
                assert(c.top == D.TERRAIN.coast.top)
            end
        end
        local shore = find(g, function(c) return Flood.shore(g, c) end)
        local city = settle(g)
        shore.owner, shore.ownerCity = 1, city
        city.buildings.levee = true
        assert(not Flood.shore(g, shore), "the levee holds it")
    end },
    { "who stands where the sea comes rows, or goes to dry land, or is lost", function()
        local g = newGame()
        local cell = find(g, function(c) return Flood.shore(g, c) end)
        local u = g:addUnit("warrior", 1, cell.id)
        Flood.drown(g, cell)
        assert(not u.dead)
        assert(u.cell ~= cell.id and g:passable(g.cells[u.cell]), "walked to dry land")
        assert(g.mil[u.cell] == u and g.mil[cell.id] == nil)
        local other = find(g, function(c) return Flood.shore(g, c) end)
        g.players[1].techs.sailing = true
        local v = g:addUnit("warrior", 1, other.id)
        Flood.drown(g, other)
        assert(v.cell == other.id and g:embarked(v), "rows, with Sailing")
    end },
    { "an all-AI game runs through the deluge to its end", function()
        local g = Game.new({ seed = 7, allAI = true, cataclysm = "flood" })
        local desert = count(g, function(c) return c.terrain == "desert" end)
        while g.turn <= D.LAST_TURN do
            AI.play(g, g.players[1])
            g:endTurn(AI)
        end
        local result, why = g:outcome()
        assert(result, "the game is over")
        if result == "lost" and g.players[1].alive then assert(why == "THE WORLD HAS DROWNED" or why:find("FALLEN")) end
        assert(count(g, function(c) return c.terrain == "desert" end) < desert, "the deserts have greened")
        assert(count(g, function(c) return c.terrain == "marsh" end) > 0, "the lowlands are marsh")
        assert(count(g, function(c) return c.drowned end) > 30, "the sea has risen")
        local levees = 0
        for _, c in ipairs(g.cities) do if c.buildings.levee then levees = levees + 1 end end
        assert(levees > 0, "the AI built against it")
    end },
}
