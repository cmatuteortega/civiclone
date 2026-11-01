local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local Sky = require "src.skyfall"
local D = require "src.defs"

-- The wild is left off: these are the sky's rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false, cataclysm = "sky" }) end

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

local function flat(g, c) return not g:isWater(c) and c.elev == "flat" and not c.river end

return {
    { "the sky's stages come on their turns", function()
        assert(Cat.stageAt(D.SKY.omen - 1, "sky") == nil)
        assert(Cat.stageAt(D.SKY.omen, "sky") == "omen")
        assert(Cat.stageAt(D.SKY.starfall, "sky") == "starfall")
        assert(Cat.stageAt(D.SKY.bombard + 1, "sky") == "bombard")
        assert(Cat.stageAt(D.LAST_TURN, "sky") == "dark")
        local g = newGame()
        assert(g.cataclysm.kind == "sky")
        g.turn = D.SKY.bombard
        assert(Cat.label(g) == "BOMBARDMENT " .. (D.LAST_TURN - D.SKY.bombard + 1))
        assert(Cat.past(g, "starfall") and not Cat.past(g, "floods"), "the deluge's stages are not the sky's")
        assert(Cat.ended(g) == "THE SKY HAS FALLEN")
        g.turn = D.SKY.omen
        Cat.turn(g)
        assert(g.log[#g.log].text:find("COMET"))
    end },
    { "every stone is seen coming: marked the turn before it falls", function()
        local g = newGame()
        g.turn = D.SKY.starfall - 2
        Cat.turn(g)
        assert(next(g.cataclysm.marks or {}) == nil, "nothing is coming yet")
        g.turn = D.SKY.starfall - 1
        Cat.turn(g)
        local marked = {}
        for id, size in pairs(g.cataclysm.marks) do
            marked[#marked + 1] = id
            assert(size == "small", "only small stones in the starfall")
            assert(Sky.marked(g, g.cells[id]) == "small")
        end
        assert(#marked == D.SKY.fall.starfall)
        local fell = {}
        g.events = {}
        g.turn = D.SKY.starfall
        Cat.turn(g)
        for _, e in ipairs(g.events) do if e.kind == "impact" then fell[#fell + 1] = e.cell end end
        table.sort(marked)
        table.sort(fell)
        assert(#fell == #marked)
        for k = 1, #fell do assert(fell[k] == marked[k], "they fall where they were seen coming") end
    end },
    { "a stone sinks its hex, flattens what is on it, and the crater yields less", function()
        local g = newGame()
        g.turn = D.SKY.starfall
        local cell = find(g, function(c) return flat(g, c) and c.terrain == "grass" and not c.resource end)
        cell.improvement = "farm"
        local top = cell.top
        local before = g:yield(cell)
        local u = g:addUnit("warrior", 1, cell.id)
        Sky.strike(g, cell, "small")
        assert(cell.top == top - D.SKY.sink.small, "the hex has sunk")
        assert(cell.crater == 1 and cell.glow and not cell.improvement)
        assert(u.hp == 100 - D.SKY.hit.small, "it hurt who stood there")
        assert(select(1, g:yield(cell)) == 0, "nothing while it is hot")
        assert(g:describe(cell):find("FRESH CRATER"))
        cell.glow = nil
        local now = g:yield(cell)
        assert(now == math.max(0, before - D.IMPROVEMENT.farm.food - D.SKY.craterFood) or cell.resource == "iron")
        local again = cell.top
        Sky.strike(g, cell, "big")
        assert(cell.top == math.max(D.SKY.floor, again - D.SKY.sink.big), "craters go deeper")
        for _ = 1, 10 do Sky.strike(g, cell, "big") end
        assert(cell.top >= D.SKY.floor, "never under the floor")
    end },
    { "hills are flattened and mountains broken; a river keeps its banks", function()
        local g = newGame()
        local hill = find(g, function(c) return c.elev == "hills" and not c.river end)
        local top = hill.top
        Sky.crater(g, hill, 1)
        assert(hill.elev == "flat" and hill.top == top - D.ELEV.hills.rise)
        local peak = find(g, function(c) return c.elev == "mountain" end)
        Sky.crater(g, peak, 1)
        assert(peak.elev == "hills" and g:passable(peak), "a broken mountain can be crossed")
        local banks = find(g, function(c) return not g:isWater(c) and c.elev == "flat" and g:onRiver(c) end)
        for _ = 1, 8 do Sky.crater(g, banks, 2) end
        for k = 0, 5 do
            local e = banks.river[k]
            if e then assert(banks.top > e.level, "the ground stays over the river's water") end
        end
    end },
    { "a big stone hurts what is beside it, and kills a city's people; a shelter halves it", function()
        local g = newGame()
        local city = settle(g)
        city.pop = 4
        local home = g.cells[city.cell]
        local top = home.top
        Sky.strike(g, home, "big")
        assert(city.hp == D.CITY.hp - D.SKY.city.big)
        assert(city.pop == 4 - D.SKY.pop)
        assert(home.top == top and not home.crater, "a city's own hex keeps its ground")
        city.hp, city.pop = D.CITY.hp, 4
        city.buildings.shelter = true
        Sky.strike(g, home, "big")
        assert(city.hp == D.CITY.hp - D.SKY.city.big * D.SHELTER.harm, "the shelter took half")
        assert(city.pop == 4, "and no one died")
        local near = find(g, function(c) return g:dist(c, home) == 2 and g:passable(c) end)
        local beside
        for _, n in ipairs(g:neighbours(near)) do if n ~= home and g:dist(n, home) >= 2 then beside = n end end
        local u = g:addUnit("warrior", 1, near.id)
        Sky.strike(g, beside, "big")
        assert(u.hp == 100 - D.SKY.near, "hurt by the blow beside it")
    end },
    { "the shelter is built against any cataclysm, and not without one", function()
        for _, kind in ipairs({ "heat", "flood", "sky" }) do
            local g = Game.new({ seed = 5, wild = false, cataclysm = kind })
            local city = settle(g)
            assert(not g:canBuild(city, "building", "shelter"), "it needs Mining")
            g.players[1].techs.mining = true
            assert(g:canBuild(city, "building", "shelter"), kind)
        end
        local g = Game.new({ seed = 5, wild = false, cataclysm = false })
        local city = settle(g)
        g.players[1].techs.mining = true
        assert(not g:canBuild(city, "building", "shelter"))
        assert(Cat.ward(newGame()) == "shelter")
    end },
    { "the shelter halves the heat's fire and the deluge's water on its city, and its stores feed it", function()
        local g = Game.new({ seed = 5, wild = false, cataclysm = "heat" })
        local city = settle(g)
        g.turn = D.HEAT.scorch
        local t = Cat.thirst(g, city)
        city.buildings.shelter = true
        assert(Cat.thirst(g, city) == t - D.SHELTER.stores)
        city.hp = 100
        Cat.harm(g, city, 20)
        assert(city.hp == 90)
        local f = Game.new({ seed = 5, wild = false, cataclysm = "flood" })
        local c2 = settle(f)
        f.turn = D.FLOOD.sea
        local fever = Cat.thirst(f, c2)
        c2.buildings.shelter = true
        assert(Cat.thirst(f, c2) == fever - D.SHELTER.stores)
    end },
    { "the cold takes food from the bombardment on, and the long night the farms'", function()
        local g = newGame()
        local city = settle(g)
        g.turn = D.SKY.starfall
        assert(Cat.thirst(g, city) == 0)
        g.turn = D.SKY.dark
        assert(Cat.thirst(g, city) == D.SKY.cold.dark)
        city.buildings.shelter = true
        assert(Cat.thirst(g, city) == D.SKY.cold.dark - D.SHELTER.skyStores)
        local cell = find(g, function(c) return flat(g, c) and c.terrain == "grass" and not c.resource end)
        cell.improvement = "farm"
        g.turn = D.SKY.dark - 1
        local before = g:yield(cell)
        g.turn = D.SKY.dark
        assert(g:yield(cell) == before - D.SKY.darkFarm)
    end },
    { "in the long night the sun never rises", function()
        local g = newGame()
        for t = D.SKY.dark, D.LAST_TURN do assert(D.night(t, g), "night at turn " .. t) end
        local h = Game.new({ seed = 5, wild = false, cataclysm = "heat" })
        local days = 0
        for t = D.SKY.dark, D.LAST_TURN do if not D.night(t, h) then days = days + 1 end end
        assert(days > 0, "the heat's world still has its days")
    end },
    { "the heart of the comet is told, and falls on seven hexes", function()
        local g = newGame()
        local city = settle(g)
        g.turn = D.SKY.heartWarn
        Cat.turn(g)
        local heart, left = Sky.heart(g)
        assert(heart and left == D.SKY.heart - D.SKY.heartWarn)
        local told = false
        for _, l in ipairs(g.log) do if l.text:find("HEART OF THE COMET WILL FALL") then told = true end end
        assert(told, "everyone is told")
        for _, n in ipairs(g:neighbours(heart)) do assert(Sky.marked(g, n) == "heart") end
        for id in pairs(g.cataclysm.marks) do assert(g:dist(g.cells[id], heart) > 1, "no stone falls under the heart") end
        local tops = {}
        for _, n in ipairs(g:within(heart, 1)) do tops[n.id] = n.top end
        g.turn = D.SKY.heart
        Cat.turn(g)
        assert(Sky.heart(g) == nil)
        for _, n in ipairs(g:within(heart, 1)) do
            if not g:isWater(n) and not n.city then
                assert(n.crater and n.top <= tops[n.id], "cratered")
            end
        end
        assert(city)
    end },
    { "the AI gets its units out from under a falling stone", function()
        local g = Game.new({ seed = 5, wild = false, cataclysm = "sky", allAI = true })
        local u
        for _, v in ipairs(g:unitsOf(2)) do if v.kind == "warrior" then u = v end end
        g.cataclysm.marks = { [u.cell] = "small" }
        u.moves = u.def.moves
        AI.play(g, g.players[2])
        assert(not Sky.marked(g, g.cells[u.cell]) or u.moves == 0, "it stepped away")
    end },
    { "an all-AI game runs through the sky's falling to its end", function()
        local g = Game.new({ seed = 7, allAI = true, cataclysm = "sky" })
        while g.turn <= D.LAST_TURN do
            AI.play(g, g.players[1])
            g:endTurn(AI)
        end
        local result, why = g:outcome()
        assert(result, "the game is over")
        if result == "lost" and g.players[1].alive then assert(why == "THE SKY HAS FALLEN" or why:find("FALLEN")) end
        assert(count(g, function(c) return c.crater end) > 60, "the land is cratered")
        assert(count(g, function(c) return (c.sunk or 0) > 0 end) > 40, "and sunk")
        local shelters = 0
        for _, c in ipairs(g.cities) do if c.buildings.shelter then shelters = shelters + 1 end end
        assert(shelters > 0, "the AI dug in")
    end },
    { "a hearth can be built under the falling sky, and holds off the long night's cold", function()
        local g = newGame()
        local city = settle(g)
        g.players[1].techs.pottery = true
        assert(g:canBuild(city, "building", "hearth"), "the hearth is a ward here too")
        g.turn = D.SKY.dark
        local cold = Cat.thirst(g, city)
        city.buildings.hearth = true
        assert(Cat.thirst(g, city) == math.max(0, cold - D.SKY.hearth))
        local farm
        for _, n in ipairs(g:within(g.cells[city.cell], 1)) do
            if n.ownerCity == city and not n.city and not g:isWater(n) and n.elev == "flat" then farm = n break end
        end
        if farm then
            farm.improvement = "farm"
            local warm = g:yield(farm)
            city.buildings.hearth = nil
            assert(g:yield(farm) == math.max(0, warm - D.SKY.darkFarm), "the hearth keeps the farm's food")
        end
    end },
}
