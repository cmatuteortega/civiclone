local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local Beasts = require "src.beasts"
local D = require "src.defs"

-- The wild is left off: these are the builders' works (D.WORKS).
local function newGame(kind) return Game.new({ seed = 5, wild = false, cataclysm = kind or "heat" }) end

local function free(g, cell) return not g.mil[cell.id] and not g.civ[cell.id] and not cell.city and not cell.lair end

local function find(g, f)
    for _, cell in ipairs(g.cells) do
        if free(g, cell) and not g:isWater(cell) and cell.elev ~= "mountain" and f(cell) then return cell end
    end
end

local function settle(g)
    for _, u in ipairs(g.units) do
        if u.owner == 1 and u.kind == "settler" then return g:found(u) end
    end
end

-- Hex `cell` made the land of player 1's city.
local function own(cell, city)
    cell.owner, cell.ownerCity = 1, city
    return cell
end

local function has(list, k)
    for _, v in ipairs(list) do if v == k then return true end end
    return false
end

-- A hex with no river by it, nor the coast.
local function inland(g, c) return not g:onRiver(c) and not g:coastal(c) end

return {
    { "a builder fells a forest: its wood goes to the city, stumps are left, and it can be farmed", function()
        local g = newGame()
        local city = settle(g)
        local cell = own(find(g, function(c) return c.feature == "forest" and c.elev == "flat" and c.terrain == "grass" end), city)
        local b = g:addUnit("builder", 1, cell.id)
        assert(has(g:worksFor(b), "chop"))
        assert(not has(g:improvementsFor(b), "farm"), "no farm in a forest")
        local p0 = city.prod
        assert(g:work(b, "chop"))
        assert(cell.feature == nil and cell.felled)
        assert(city.prod == p0 + D.WORKS.chop.prod)
        assert(b.moves == 0 and b.charges == D.UNITS.builder.charges - 1)
        assert(g:describe(cell):find("FELLED"))
        b.moves = 2
        assert(has(g:improvementsFor(b), "farm"), "the felled land can be farmed")
        assert(not has(g:worksFor(b), "chop"))
    end },
    { "a forest outside our borders is not ours to fell", function()
        local g = newGame()
        settle(g)
        local cell = find(g, function(c) return c.feature == "forest" and not c.owner end)
        local b = g:addUnit("builder", 1, cell.id)
        assert(not has(g:worksFor(b), "chop"))
        assert(not g:work(b, "chop"))
        assert(cell.feature == "forest")
    end },
    { "a firebreak can't catch fire, a fire won't spread onto it, and a farm sown on it can burn again", function()
        local g = newGame()
        local city = settle(g)
        local cell = own(find(g, function(c) return c.terrain == "grass" and c.elev == "flat" and not c.feature end), city)
        cell.improvement = "farm"
        local b = g:addUnit("builder", 1, cell.id)
        assert(Cat.flammable(g, cell))
        assert(has(g:worksFor(b), "clear"))
        assert(g:work(b, "clear"))
        assert(cell.cleared and cell.improvement == nil and cell.terrain == "plains")
        assert(not Cat.flammable(g, cell))
        assert(g:describe(cell):find("FIREBREAK"))
        -- Fires all round it, turn after turn: it never catches.
        g.rng.random = function() return 0 end
        for _, n in ipairs(g:neighbours(cell)) do
            if not g:isWater(n) and not n.city and n.elev ~= "mountain" then n.fire = D.HEAT.burn end
        end
        Cat.fires(g, "fires")
        assert(not cell.fire, "the firebreak held")
        b.moves = 2
        assert(not has(g:worksFor(b), "clear"), "no firebreak twice")
        assert(g:improve(b, "farm"))
        assert(not cell.cleared and Cat.flammable(g, cell))
    end },
    { "a forest takes no firebreak: it must be felled", function()
        local g = newGame()
        local city = settle(g)
        local cell = own(find(g, function(c) return c.feature == "forest" end), city)
        local b = g:addUnit("builder", 1, cell.id)
        assert(not has(g:worksFor(b), "clear"))
    end },
    { "a builder beats out the fires on its hex and beside it; a fire by the water goes out at once", function()
        local g = newGame()
        local cell = find(g, function(c) return inland(g, c) and c.terrain == "grass" end)
        local b = g:addUnit("builder", 1, cell.id)
        assert(not has(g:worksFor(b), "douse"), "nothing burning")
        local dry
        for _, n in ipairs(g:neighbours(cell)) do
            if not g:isWater(n) and n.elev ~= "mountain" and inland(g, n) and not Cat.cool(n) then dry = n break end
        end
        cell.fire, dry.fire = 2, 3
        assert(has(g:worksFor(b), "douse"), "out of our borders too")
        assert(g:work(b, "douse"))
        assert(not cell.fire and cell.burnt, "2 turns of fire beaten out")
        assert(dry.fire == 3 - D.WORKS.douse.turns, "one of 3 burns less")
        -- By a river, out at once.
        local g2 = newGame()
        local wet = find(g2, function(c) return g2:onRiver(c) and c.terrain == "grass" end)
        local b2 = g2:addUnit("builder", 1, wet.id)
        wet.fire = D.HEAT.burn + 5
        assert(g2:work(b2, "douse"))
        assert(not wet.fire)
    end },
    { "mending baked earth needs water by it", function()
        local g = newGame()
        local city = settle(g)
        local dry = own(find(g, function(c) return inland(g, c) end), city)
        dry.terrain, dry.scorched = "desert", true
        local b = g:addUnit("builder", 1, dry.id)
        assert(not has(g:worksFor(b), "mend"), "no water, no mending")
        local wet = own(find(g, function(c) return g:onRiver(c) end), city)
        wet.terrain, wet.scorched = "desert", true
        local b2 = g:addUnit("builder", 1, wet.id)
        assert(g:work(b2, "mend"))
        assert(not wet.scorched and wet.terrain == "plains")
    end },
    { "mending: black rock, a cold crater, the ash and the marsh", function()
        local g = newGame("quake")
        local city = settle(g)
        local p = g.players[1]
        local cell = own(find(g, function(c) return c.elev == "flat" and not c.feature and c.terrain == "plains" end), city)
        local b = g:addUnit("builder", 1, cell.id)
        local function mend()
            b.moves, b.charges = 2, 3
            assert(g:work(b, "mend"))
        end
        cell.basalt, cell.resource = true, "obsidian"
        local f0 = g:yield(cell)
        mend()
        assert(not cell.basalt and cell.resource == nil)
        assert(g:yield(cell) >= f0, "a food more, but its obsidian gone")
        cell.crater, cell.glow = 1, 1
        b.moves = 2
        assert(not has(g:worksFor(b), "mend"), "not while it is hot")
        cell.glow = nil
        mend()
        assert(not cell.crater)
        cell.crater, cell.resource = 1, "iron"
        b.moves = 2
        assert(not has(g:worksFor(b), "mend"), "star iron is left for the mine")
        cell.crater, cell.resource = nil, nil
        cell.ashfall = 3
        mend()
        assert(not cell.ashfall and cell.soil)
        cell.terrain = "marsh"
        b.moves = 2
        assert(not has(g:worksFor(b), "mend"), "draining needs irrigation")
        p.techs.irrigation = true
        mend()
        assert(cell.terrain == "grass")
        b.moves = 2
        assert(not has(g:worksFor(b), "mend"), "nothing left to mend")
    end },
    { "the blight is burnt off only out of every rift's reach", function()
        local g = newGame("demons")
        local city = settle(g)
        local cell = own(find(g, function(c) return c.elev == "flat" and c.owner == nil end), city)
        g.turn = D.DEMONS.rifts
        cell.blight = true
        local b = g:addUnit("builder", 1, cell.id)
        assert(has(g:worksFor(b), "mend"))
        -- A rift beside it: not now.
        local by
        for _, n in ipairs(g:neighbours(cell)) do
            if free(g, n) and not g:isWater(n) and n.elev ~= "mountain" then by = n break end
        end
        Beasts.addLair(g, "rift", by.id)
        assert(not has(g:worksFor(b), "mend"))
        by.lair = nil
        for k = #g.lairs, 1, -1 do if g.lairs[k].cell == by.id then table.remove(g.lairs, k) end end
        assert(g:work(b, "mend"))
        assert(not cell.blight and cell.burnt)
    end },
    { "the works save and load", function()
        local Save = require "src.save"
        local g = newGame()
        local city = settle(g)
        local cell = own(find(g, function(c) return c.terrain == "grass" and not c.feature end), city)
        local b = g:addUnit("builder", 1, cell.id)
        assert(g:work(b, "clear"))
        local h = Save.decode(Save.encode(g))
        assert(h.cells[cell.id].cleared)
    end },
    { "the AI's builders beat out a fire on their land", function()
        local g = newGame()
        local city = settle(g)
        local cell = own(find(g, function(c) return inland(g, c) and c.terrain == "grass" and c.elev == "flat" end), city)
        cell.fire = 3
        local spot
        for _, n in ipairs(g:neighbours(cell)) do
            if free(g, n) and g:passable(n) and not g:isWater(n) and not n.fire then spot = n break end
        end
        local b = g:addUnit("builder", 1, spot.id)
        -- Played by the computer.
        AI.play(g, g.players[1])
        assert(b.dead or b.moves == 0)
        assert((cell.fire or 0) < 3, "the fire was fought")
    end },
}
