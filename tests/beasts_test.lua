-- The wild (src/beasts.lua): beasts on the map, how they fight, what they
-- leave, their lairs, and taming the horses.

local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"
local Beasts = require "src.beasts"

-- A game with no wild in it, to put beasts into by hand.
local function bare(seed) return Game.new({ seed = seed or 5, wild = false }) end

-- Two neighbouring open land hexes, no river between, nothing on them, away
-- from everyone.
local function pair(g)
    for _, cell in ipairs(g.cells) do
        if g:passable(cell) and not cell.city and not g.mil[cell.id] and not g.civ[cell.id] then
            for _, n in ipairs(g:neighbours(cell)) do
                if g:passable(n) and not n.city and not g.mil[n.id] and not g.civ[n.id] and not g:riverBetween(cell, n)
                    and not cell.lair and not n.lair then
                    return cell, n
                end
            end
        end
    end
end

local function count(g, kind)
    local n = 0
    for _, u in ipairs(g.units) do if u.owner == Game.WILD and (not kind or u.kind == kind) then n = n + 1 end end
    return n
end

return {
    { "the map starts wild, away from where anyone starts", function()
        local g = Game.new({ seed = 5 })
        assert(count(g) > 10, "beasts about: " .. count(g))
        assert(#g.lairs > 2, "lairs: " .. #g.lairs)
        for _, u in ipairs(g.units) do
            if u.owner == Game.WILD then
                assert(Beasts.canEnter(g, u, g.cells[u.cell]), u.kind .. " on its own ground")
                for _, v in ipairs(g.units) do
                    if v.owner ~= Game.WILD then
                        assert(g:dist(g.cells[u.cell], g.cells[v.cell]) >= D.WILD.clear - 1, "a " .. u.kind .. " too near a start")
                    end
                end
            end
        end
        -- The wild is no civilization: not counted, never out.
        assert(#g.players == #D.CIVS and g.players[Game.WILD].wild)
    end },
    { "beasts keep to their ground: serpents the ocean, crocodiles their rivers", function()
        local g = Game.new({ seed = 8 })
        for _, u in ipairs(g.units) do
            local cell = g.cells[u.cell]
            if u.kind == "serpent" then assert(cell.terrain == "ocean") end
            if u.kind == "croc" then assert(g:onRiver(cell)) end
        end
    end },
    { "a wolf goes for a builder next to it, and wounds it rather than taking it", function()
        local g = bare()
        local a, b = pair(g)
        local wolf = Beasts.spawn(g, "wolf", a.id)
        local builder = g:addUnit("builder", 1, b.id)
        Beasts.play(g)
        assert(builder.hp < 100, "mauled")
        assert(not builder.dead and builder.owner == 1, "not captured")
        assert(wolf.cell == a.id, "the wolf stays where it was")
    end },
    { "killing a beast gives its loot: gold to the killer, food to their city", function()
        local g = bare()
        local a, b = pair(g)
        local s = g:addUnit("settler", 1, b.id)
        g.mil[b.id] = nil
        local city = g:found(s)
        local boar = Beasts.spawn(g, "boar", a.id)
        local w = g:addUnit("swordsman", 1, b.id)
        local gold, food = g.players[1].gold, city.food
        boar.hp = 1
        assert(g:canAttack(w, a))
        g:attack(w, a)
        assert(boar.dead)
        assert(g.players[1].gold == gold + D.BEASTS.boar.loot.gold)
        assert(city.food == food + D.BEASTS.boar.loot.food)
        local said = false
        for _, l in ipairs(g.log) do if l.text:find("WILD BOAR SLAIN") then said = true end end
        assert(said)
    end },
    { "a boar left alone stays calm; struck, it goes for whoever struck it", function()
        local g = bare()
        local a, b = pair(g)
        local boar = Beasts.spawn(g, "boar", a.id)
        local w = g:addUnit("warrior", 1, b.id)
        for _ = 1, 4 do
            g:wildTurn()
            assert(w.hp == 100, "a boar does not start it")
            -- Back next to the warrior, wherever it wandered.
            if boar.cell ~= a.id and not g.mil[a.id] then g:relocate(boar, a.id) end
        end
        g:attack(w, a)
        assert(boar.angry == w.id)
        local hp = w.hp
        boar.hp = 100
        g:wildTurn()
        assert(w.hp < hp, "it charged back")
    end },
    { "wolves are stronger in the dark", function()
        local g = bare()
        local a = pair(g)
        local wolf = Beasts.spawn(g, "wolf", a.id)
        local day, night
        for t = 1, 8 do
            g.turn = t
            if D.night(t) then night = g:attackStrength(wolf) else day = g:attackStrength(wolf) end
        end
        assert(night == day + D.BEASTS.wolf.night)
    end },
    { "a beast never strikes a city, nor another beast", function()
        local g = bare()
        local a, b = pair(g)
        local wolf = Beasts.spawn(g, "wolf", a.id)
        local bear = Beasts.spawn(g, "bear", b.id)
        assert(not g:canAttack(wolf, b) and not g:canAttack(bear, a))
        g:removeUnit(bear)
        local s = g:addUnit("settler", 1, b.id)
        g:found(s)
        assert(not g:canAttack(wolf, b))
    end },
    { "a crocodile strikes only across its river", function()
        local g = bare()
        local croc, prey, side
        for _, cell in ipairs(g.cells) do
            if g:passable(cell) and g:onRiver(cell) and not g.mil[cell.id] and not cell.city then
                for _, n in ipairs(g:neighbours(cell)) do
                    if g:passable(n) and not g.mil[n.id] and not n.city then
                        if g:riverBetween(cell, n) then prey = prey or n else side = side or n end
                    end
                end
                if prey and side then croc = cell break end
                prey, side = nil, nil
            end
        end
        assert(croc, "a river with land both ways")
        local c = Beasts.spawn(g, "croc", croc.id)
        g:addUnit("warrior", 1, prey.id)
        g:addUnit("warrior", 1, side.id)
        assert(g:canAttack(c, prey), "across the river")
        assert(not g:canAttack(c, side), "not along the bank")
    end },
    { "a soldier walking into an unguarded den clears it for gold", function()
        local g = bare()
        local a, b = pair(g)
        local lair = Beasts.addLair(g, "den", a.id)
        local w = g:addUnit("warrior", 1, b.id)
        local gold = g.players[1].gold
        assert(g:step(w, a.id))
        assert(not a.lair and #g.lairs == 0)
        assert(g.players[1].gold == gold + lair.def.prize.gold)
    end },
    { "wild bees sting whoever takes their honey, never to death", function()
        local g = bare()
        local a, b = pair(g)
        Beasts.addLair(g, "hive", a.id)
        local w = g:addUnit("warrior", 1, b.id)
        w.hp = 10
        assert(g:step(w, a.id))
        assert(w.hp == 1 and not w.dead and not a.lair)
    end },
    { "a den sends out a new wolf in time while no one is near", function()
        local g = bare()
        local a = pair(g)
        Beasts.addLair(g, "den", a.id)
        for _ = 1, D.LAIRS.den.every * D.LAIRS.den.keep + 1 do Beasts.play(g) end
        assert(count(g, "wolf") == D.LAIRS.den.keep)
    end },
    { "wild horses run from people, and a rider's people tame them", function()
        local g = bare()
        local a, b = pair(g)
        local h = Beasts.spawn(g, "horse", a.id)
        local w = g:addUnit("warrior", 1, b.id)
        g:wildTurn()
        assert(g:dist(g.cells[h.cell], g.cells[w.cell]) > 1, "they ran")
        -- Without Horseback Riding, coming next to them does nothing.
        local near
        for _, n in ipairs(g:neighbours(g.cells[h.cell])) do
            if g:canStand(w, n) and g:dist(n, g.cells[w.cell]) == 1 then near = n end
        end
        if near then
            local w2 = g:addUnit("warrior", 1, near.id)
            assert(not h.dead)
            g:removeUnit(w2)
        end
        g.players[1].techs.horses = true
        for _, n in ipairs(g:neighbours(g.cells[h.cell])) do
            if g:passable(n) and not g.mil[n.id] then
                local w3 = g:addUnit("warrior", 1, n.id)
                w3.moves = 2
                g:relocate(w3, n.id)
                break
            end
        end
        assert(h.dead, "tamed")
        local rider
        for _, u in ipairs(g:unitsOf(1)) do if u.kind == "horseman" then rider = u end end
        assert(rider and rider.cell == h.cell)
    end },
    { "a hundred turns with the wild run clean, and the wild is hunted", function()
        local g = Game.new({ seed = 21, allAI = true })
        for _ = 1, 100 do
            AI.play(g, g.players[1])
            g:endTurn(AI)
        end
        local slain = 0
        for _, l in ipairs(g.log) do if l.text:find("SLAIN") then slain = slain + 1 end end
        assert(slain > 0, "someone hunted")
        for _, u in ipairs(g.units) do
            assert(g:slot(u)[u.cell] == u, u.kind .. " is where it says")
            if u.owner == Game.WILD then assert(Beasts.canEnter(g, u, g.cells[u.cell])) end
        end
    end },
}
