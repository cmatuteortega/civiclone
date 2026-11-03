-- Diplomacy (src/diplomacy.lua) and loyalty (src/loyalty.lua): meeting,
-- peace and its closed borders, war, treaties and their breaking, letters
-- and their answers, and cities that change sides.

local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"
local Diplo = require "src.diplomacy"
local Loyalty = require "src.loyalty"
local Save = require "src.save"

local function newGame(seed) return Game.new({ seed = seed or 5, wild = false, cataclysm = false }) end

local function find(g, owner, kind)
    for _, u in ipairs(g.units) do if u.owner == owner and u.kind == kind then return u end end
end

-- Player 2's capital, founded where its settler stands.
local function rivalCity(g)
    return g:found(find(g, 2, "settler"))
end

-- A free land hex just outside the city's land, beside a hex of it.
local function outside(g, city)
    for _, cell in ipairs(g:within(g.cells[city.cell], 4)) do
        if not cell.owner and g:passable(cell) and not g.mil[cell.id] and not g.civ[cell.id] then
            for _, n in ipairs(g:neighbours(cell)) do
                if n.owner == city.owner and not n.city and g:passable(n) and not g.mil[n.id] then return cell, n end
            end
        end
    end
end

-- A land hex of the city's own, free, not the city.
local function inside(g, city)
    for _, cell in ipairs(g:within(g.cells[city.cell], 1)) do
        if cell.owner == city.owner and not cell.city and g:passable(cell) and not g.mil[cell.id] and not g.civ[cell.id] then
            return cell
        end
    end
end

return {
    { "civilizations meet on seeing a unit or the land of the other, and start at peace", function()
        local g = newGame()
        local city = rivalCity(g)
        assert(not Diplo.met(g, 1, 2))
        local out = outside(g, city)
        local w = g:addUnit("warrior", 1, out.id)
        g:look(g.players[1])
        assert(Diplo.met(g, 1, 2), "met on seeing them")
        assert(Diplo.stance(g, 1, 2) == "AT PEACE")
        assert(not Diplo.atWar(g, 1, 2) and Diplo.atWar(g, 1, g.WILD), "the wild is always at war")
        -- The rival's envoy waits on the player's answer.
        local mail = Diplo.waiting(g, 1)
        assert(#mail == 1 and mail[1].kind == "greeting" and mail[1].from == 2)
        Diplo.answer(g, mail[1], "welcome")
        assert(#Diplo.waiting(g, 1) == 0)
        local _, parts = Diplo.regard(g, 2, 1)
        local welcomed = false
        for _, p in ipairs(parts) do if p[1] == "WELCOMED OUR ENVOY" then welcomed = true end end
        assert(welcomed, "and remembers it")
        assert(w)
    end },
    { "at peace a soldier can neither attack the other nor walk their land; at war it can", function()
        local g = newGame()
        local city = rivalCity(g)
        local out, land = outside(g, city)
        local w = g:addUnit("warrior", 1, out.id)
        g:look(g.players[1])
        assert(not g:canEnter(w, land), "their land is closed")
        assert(not g:reach(w)[land.id], "and out of reach")
        local e = g:addUnit("warrior", 2, land.id)
        assert(not g:canAttack(w, land), "no fighting at peace")
        assert(g:atPeaceWith(1, land) == 2)
        Diplo.declare(g, 1, 2, "player")
        assert(Diplo.atWar(g, 1, 2) and g:canEnter(w, land) and g:canAttack(w, land))
        assert(e)
    end },
    { "open borders let units in; meeting puts out those already in", function()
        local g = newGame()
        local city = rivalCity(g)
        local spot = inside(g, city)
        -- Walked in before anyone met: put out to the nearest hex it may stand on.
        local w = g:addUnit("warrior", 1, spot.id)
        g:look(g.players[1])
        assert(Diplo.met(g, 1, 2))
        assert(g.cells[w.cell].owner ~= 2, "put out of their land")
        assert(Diplo.propose(g, 1, 2, "borders") ~= nil)
        Diplo.openBorders(g, 1, 2)
        assert(g:canEnter(w, spot), "open now")
    end },
    { "a war breaking a treaty is a betrayal, and everyone remembers", function()
        local g = newGame()
        for a = 1, 3 do for b = a + 1, 3 do Diplo.meet(g, a, b) end end
        Diplo.openBorders(g, 1, 2)
        Diplo.declare(g, 1, 2, "player")
        local function has(a, b, words)
            local _, parts = Diplo.regard(g, a, b)
            for _, p in ipairs(parts) do if p[1] == words then return true end end
        end
        assert(has(2, 1, "BETRAYED US") and has(2, 1, "DECLARED WAR ON US"))
        assert(has(3, 1, "BREAKS TREATIES"), "a third side remembers too")
        assert(not Diplo.open(g, 1, 2), "the treaty is gone")
    end },
    { "a peace holds for its truce", function()
        local g = newGame()
        Diplo.meet(g, 1, 2)
        Diplo.declare(g, 2, 1, "weak")
        g.turn = g.turn + 10
        Diplo.makePeace(g, 1, 2)
        assert(not Diplo.atWar(g, 1, 2))
        local ok = Diplo.propose(g, 1, 2, "war")
        assert(not ok and not Diplo.atWar(g, 1, 2), "no war in the truce")
        g.turn = g.turn + D.DIPLO.truce
        assert(Diplo.propose(g, 1, 2, "war") and Diplo.atWar(g, 1, 2))
    end },
    { "allies see what the other sees", function()
        local g = newGame()
        local city = rivalCity(g)
        Diplo.meet(g, 1, 2)
        local far = city.cell
        g:look(g.players[1])
        Diplo.ally(g, 1, 2)
        assert(Diplo.allied(g, 1, 2) and Diplo.open(g, 1, 2))
        assert(g.players[1].visible[far], "their city is in sight")
    end },
    { "a letter left too long takes its default answer", function()
        local g = newGame()
        Diplo.meet(g, 1, 2)
        Diplo.declare(g, 2, 1, "weak")
        local l = Diplo.send(g, 2, 1, "peace")
        assert(Diplo.stillAsks(g, l))
        for _ = 1, D.DIPLO.answer + 1 do g:endTurn() end
        assert(l.answer == "no" and l.late, tostring(l.answer))
        assert(Diplo.atWar(g, 1, 2), "no peace for silence")
    end },
    { "tribute paid is gold handed over, refused is remembered", function()
        local g = newGame()
        Diplo.meet(g, 1, 2)
        g.players[1].gold, g.players[2].gold = 100, 0
        local l = Diplo.send(g, 2, 1, "tribute", { gold = 40 })
        Diplo.answer(g, l, "pay")
        assert(g.players[1].gold == 60 and g.players[2].gold == 40)
        local l2 = Diplo.send(g, 2, 1, "tribute", { gold = 500 })
        Diplo.answer(g, l2, "pay")
        assert(l2.answer == "no", "what cannot be paid is refused")
    end },
    { "the computer answers its own letters at once, by its regard", function()
        local g = newGame()
        Diplo.meet(g, 2, 3)
        Diplo.remember(g, 3, 2, "gift", 25)
        Diplo.remember(g, 3, 2, "aided", 25)
        g.turn = 30
        local l = Diplo.send(g, 2, 3, "borders")
        assert(l.answer == "yes" and Diplo.open(g, 2, 3))
    end },
    { "a city with no loyalty left goes over: to the computer at once, to the player if they agree", function()
        local g = newGame()
        local city = rivalCity(g)
        Diplo.meet(g, 1, 2)
        -- A big city of the player's next door pulls on it.
        local near
        for _, cell in ipairs(g:within(g.cells[city.cell], 5)) do
            if g:dist(cell, g.cells[city.cell]) == 4 and g:passable(cell) and not cell.owner then near = cell break end
        end
        local s = g:addUnit("settler", 1, near.id)
        local mine = g:found(s)
        mine.pop = 20
        -- Not their capital, which holds firm.
        city.capital = false
        local delta = Loyalty.parts(g, city)
        assert(delta < 0, "pulled down: " .. delta)
        city.loyalty = 1
        Loyalty.turn(g, city)
        assert(city.owner == 2 and city.pleading, "the player is asked first")
        local l = Diplo.letter(g, city.pleading)
        assert(l.kind == "defect")
        Diplo.answer(g, l, "yes")
        assert(city.owner == 1 and Loyalty.of(city) == D.LOYALTY.after, "now the player's")
        assert(g.cells[city.cell].owner == 1)
    end },
    { "a player's city with no loyalty left goes over to the computer, and a letter says so", function()
        local g = newGame()
        local city = rivalCity(g)
        city.pop = 12
        local near
        for _, cell in ipairs(g:within(g.cells[city.cell], 5)) do
            if g:dist(cell, g.cells[city.cell]) == 4 and g:passable(cell) and not cell.owner then near = cell break end
        end
        local mine = g:found(g:addUnit("settler", 1, near.id))
        Diplo.meet(g, 1, 2)
        for _, l in ipairs(Diplo.waiting(g, 1)) do Diplo.answer(g, l, "welcome") end
        mine.capital = false
        mine.loyalty = 1
        Loyalty.turn(g, mine)
        assert(mine.owner == 2, "gone over at once")
        local mail = Diplo.waiting(g, 1)
        assert(#mail == 1 and mail[1].kind == "revolt")
    end },
    { "unrest and uprising cost all but food", function()
        local g = newGame()
        local city = rivalCity(g)
        city.pop = 4
        g:assignWork(city)
        local f, p, gold = g:cityYield(city)
        city.loyalty = D.LOYALTY.uprising - 1
        local f2, p2, gold2 = g:cityYield(city)
        assert(f2 == f, "food is kept")
        assert(p2 == math.floor(p * 0.5) and gold2 == math.floor(gold * 0.5))
        assert(Loyalty.state(city) == "UPRISING")
    end },
    { "diplomacy and loyalty are kept with the game", function()
        local g = newGame()
        local city = rivalCity(g)
        Diplo.meet(g, 1, 2)
        Diplo.openBorders(g, 1, 2)
        Diplo.remember(g, 2, 1, "gift", 10)
        city.loyalty = 42
        local back = assert(Save.decode(Save.encode(g)))
        assert(Diplo.met(back, 1, 2) and Diplo.open(back, 1, 2))
        assert(Diplo.regard(back, 2, 1) == Diplo.regard(g, 2, 1))
        assert(#Diplo.waiting(back, 1) == #Diplo.waiting(g, 1))
        assert(back:cityById(city.id).loyalty == 42)
    end },
    { "a game kept before diplomacy is taken up with everyone met and at war", function()
        local g = newGame()
        g.turn = 40
        g.diplo = nil
        Diplo.ensure(g)
        assert(Diplo.atWar(g, 1, 2) and Diplo.atWar(g, 2, 3))
    end },
    { "the computer's leaders make war and peace over a whole game", function()
        local g = Game.new({ seed = 8, allAI = true, cataclysm = "heat" })
        local wars, peaces, met = 0, 0, 0
        for _ = 1, 140 do
            AI.play(g, g.players[1])
            g:endTurn(AI)
            for _, e in ipairs(g.events) do
                if e.kind == "war" then wars = wars + 1 end
                if e.kind == "peace" then peaces = peaces + 1 end
                if e.kind == "met" then met = met + 1 end
            end
            g.events = {}
        end
        assert(met >= 2, "met " .. met)
        assert(wars >= 1, "no war in 140 turns")
        assert(peaces >= 1, "no peace in 140 turns")
    end },
}
