local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local Plague = require "src.plague"
local D = require "src.defs"

local P = D.PLAGUE

-- The wild's beasts are left off: these are the plague's rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false, cataclysm = "plague" }) end

local function settle(g, who)
    for _, u in ipairs(g.units) do
        if u.owner == (who or 1) and u.kind == "settler" then return g:found(u) end
    end
end

-- A city of player `who` founded on a free land hex `d` or more from `from`.
local function townNear(g, from, d, who, f)
    for _, cell in ipairs(g:within(from, d + 2)) do
        if g:dist(cell, from) >= d and g:passable(cell) and not cell.city and not cell.lair
            and not g.mil[cell.id] and not g.civ[cell.id] and (not cell.owner or cell.owner == (who or 1))
            and (not f or f(cell)) then
            local s = g:addUnit("settler", who or 1, cell.id)
            local c = g:found(s)
            if c then return c end
            g:removeUnit(s)
        end
    end
end

-- The plague at turn `t`, its stage begun.
local function at(g, t)
    g.turn = t
    g.cataclysm.stage = Cat.stage(g)
end

-- A free land hex beside `cell`.
local function beside(g, cell)
    for _, n in ipairs(g:neighbours(cell)) do
        if g:passable(n) and not n.city and not g.mil[n.id] and not g.civ[n.id] then return n end
    end
end

return {
    { "the plague's stages come on their turns", function()
        assert(Cat.stageAt(P.omen - 1, "plague") == nil)
        assert(Cat.stageAt(P.omen, "plague") == "omen")
        assert(Cat.stageAt(P.fever, "plague") == "fever")
        assert(Cat.stageAt(P.dying + 1, "plague") == "dying")
        assert(Cat.stageAt(D.LAST_TURN, "plague") == "dance")
        local g = newGame()
        assert(g.cataclysm.kind == "plague")
        g.turn = P.fever
        assert(Cat.label(g) == "FEVER " .. (D.LAST_TURN - P.fever + 1))
        assert(Cat.ward(g) == "lazaret")
        assert(Cat.ended(g) == "THE PLAGUE HAS EMPTIED THE WORLD")
        g.turn = P.omen
        Cat.turn(g)
        assert(g.log[#g.log].text:find("CROWS"))
    end },
    { "the first sick town is seen in the omen's last turn and falls sick as the fever comes", function()
        local g = newGame()
        settle(g, 1)
        settle(g, 2)
        g.turn = P.fever - 1
        Cat.turn(g)
        local zero = Plague.zero(g)
        assert(zero, "it is seen")
        assert(not zero.sick, "not yet")
        g.turn = P.fever
        Cat.turn(g)
        assert(zero.sick, "it has fallen sick")
        assert(Plague.count(g) >= 1)
    end },
    { "a sick town loses food and its people, doesn't grow, and in time mends", function()
        local g = newGame()
        local city = settle(g, 1)
        at(g, P.dying)
        city.pop, city.food = 8, 0
        local well = Plague.thirst(g, city)
        assert(well == P.fear.dying, "the well go hungry for fear")
        Plague.infect(g, city)
        assert(Plague.thirst(g, city) == P.sick.dying, "the sick more")
        city.buildings.lazaret = true
        assert(Plague.thirst(g, city) == P.sick.dying - P.ward, "a lazaret spares some")
        city.buildings.lazaret = nil
        city.food = g:growthNeed(city) + 50
        g:finishTurn(g.players[1])
        assert(city.pop == 8, "a sick town doesn't grow")
        local died, mended = false, false
        for _ = 1, 80 do
            Cat.turn(g)
            if city.pop < 8 then died = true end
            if not city.sick then mended = true break end
        end
        assert(died, "its people died")
        assert(mended, "it mended")
        assert(Plague.immune(g, city), "and is spared a while")
        assert(not Plague.infect(g, city), "it can't catch it again yet")
        assert(city.pop >= 1 and city.dead and city.dead > 0)
    end },
    { "it goes to the towns near a sick one, and hardly to a shut one", function()
        local g = newGame()
        local a = settle(g, 1)
        local b = townNear(g, g.cells[a.cell], 4, 1)
        assert(b, "a second town")
        at(g, P.dance)
        Plague.infect(g, a)
        local open = Plague.chance(g, a, b, "dance")
        assert(open > 0, "it can spread")
        Plague.setShut(g, b, true)
        local shut = Plague.chance(g, a, b, "dance")
        assert(shut < open * 0.2, "far less to a shut town")
        Plague.setShut(g, b, false)
        local caught = false
        for _ = 1, 60 do
            Cat.turn(g)
            if b.sick then caught = true break end
            if not a.sick then a.immune = nil; Plague.infect(g, a) end
        end
        assert(caught, "the near town caught it")
    end },
    { "no one walks into or out of a shut town", function()
        local g = newGame()
        local a = settle(g, 1)
        local cell = g.cells[a.cell]
        local n = beside(g, cell)
        local u = g:addUnit("warrior", 1, n.id)
        Plague.setShut(g, a, true)
        assert(g:stepCost(u, n, cell) == nil, "can't go in")
        assert(not g:path(u, cell.id), "no way in")
        local inside = g:addUnit("builder", 1, cell.id)
        assert(g:stepCost(inside, cell, n) == nil, "can't go out")
        local _, _, gold = g:cityYield(a)
        assert(gold == 0, "a shut town makes no gold")
        Plague.setShut(g, a, false)
        assert(g:stepCost(u, n, cell), "open again")
    end },
    { "people catch it in a sick town, carry it, and bring it to a well one", function()
        local g = newGame()
        local a = settle(g, 1)
        local b = townNear(g, g.cells[a.cell], 4, 1)
        at(g, P.fever)
        g.cataclysm.seeded = { fever = true }
        Plague.infect(g, a)
        local u = g:addUnit("warrior", 1, a.cell)
        for _ = 1, 30 do
            if u.sick then break end
            Plague.play(g, "fever")
        end
        assert(u.sick, "the garrison caught it")
        local hp = u.hp
        -- Off to the other town.
        g.mil[u.cell] = nil
        u.cell = b.cell
        g.mil[b.cell] = u
        a.sick, a.immune = nil, g.turn + 99
        local brought = false
        for _ = 1, 30 do
            if not u.sick or u.dead then break end
            Plague.play(g, "fever")
            if b.sick then brought = true break end
        end
        assert(brought, "it brought it in")
        assert(u.dead or u.hp < hp, "and sickened of it")
    end },
    { "a settler that carries it founds a sick town", function()
        local g = newGame()
        at(g, P.fever)
        local s
        for _, u in ipairs(g.units) do if u.owner == 1 and u.kind == "settler" then s = u end end
        s.sick = 3
        local city = g:found(s)
        assert(city and city.sick, "sick from the first")
    end },
    { "a sick town sends rats out; rats spoil a farm and bring it to a well town", function()
        local g = newGame()
        local a = settle(g, 1)
        at(g, P.dance)
        g.cataclysm.seeded = { fever = true, dying = true, dance = true }
        Plague.infect(g, a)
        local rats
        for _ = 1, 40 do
            Plague.play(g, "dance")
            for _, u in ipairs(g.units) do if Plague.isRat(u) then rats = u end end
            if rats then break end
        end
        assert(rats, "rats came out")
        local cell = g.cells[rats.cell]
        assert(Plague.food(g, cell, 3) == 0, "no food where they are")
        local b = townNear(g, g.cells[a.cell], 4, 1)
        assert(b)
        a.sick, a.immune = nil, g.turn + 99
        local bn = beside(g, g.cells[b.cell])
        g.mil[rats.cell] = nil
        rats.cell = bn.id
        g.mil[bn.id] = rats
        rats.life = 99
        local brought = false
        for _ = 1, 30 do
            Plague.play(g, "dance")
            if b.sick then brought = true break end
        end
        assert(brought, "the rats brought it in")
    end },
    { "a death may leave a farm fallow, and a builder farms it again", function()
        local g = newGame()
        local a = settle(g, 1)
        at(g, P.dying)
        local farmland
        for _, n in ipairs(g:neighbours(g.cells[a.cell])) do
            if n.owner == 1 and n.elev == "flat" and not n.feature and g:passable(n) and n.terrain ~= "desert" then
                n.improvement = "farm"
                farmland = n
                break
            end
        end
        assert(farmland, "a farm")
        a.pop = 9
        Plague.infect(g, a)
        local old = D.PLAGUE.fallow
        D.PLAGUE.fallow = 1
        for _ = 1, 40 do
            Plague.play(g, "dying")
            if farmland.fallow then break end
            a.sick = a.sick or 2
        end
        D.PLAGUE.fallow = old
        assert(farmland.fallow and not farmland.improvement, "it lies fallow")
        assert(g:describe(farmland):find("FALLOW"))
        local b = g:addUnit("builder", 1, farmland.id)
        assert(g:improve(b, "farm"))
        assert(not farmland.fallow, "farmed again")
    end },
    { "the great pestilence takes a third of a sick town and sickens the open towns near it", function()
        local g = newGame()
        local a = settle(g, 1)
        local b = townNear(g, g.cells[a.cell], 4, 1)
        local c = townNear(g, g.cells[a.cell], 4, 1)
        at(g, P.great)
        g.cataclysm.seeded = { fever = true, dying = true, dance = true }
        a.pop = 9
        Plague.infect(g, a)
        Plague.setShut(g, c, true)
        Plague.play(g, "dance")
        assert(a.pop <= 7, "a third of its people")
        assert(b.sick, "the open town fell sick")
    end },
    { "the lazaret is only for the plague", function()
        local g = newGame()
        local city = settle(g, 1)
        g.players[1].techs.writing = true
        assert(g:canBuild(city, "building", "lazaret"))
        local h = Game.new({ seed = 5, wild = false, cataclysm = "heat" })
        local hc = settle(h, 1)
        h.players[1].techs.writing = true
        assert(not h:canBuild(hc, "building", "lazaret"))
    end },
    { "the AI builds lazarets and shuts its towns, and an all-AI game runs to its end", function()
        local g = Game.new({ seed = 7, allAI = true, cataclysm = "plague" })
        local shut, sick = false, 0
        while g.turn <= D.LAST_TURN do
            AI.play(g, g.players[1])
            g:endTurn(AI)
            for _, c in ipairs(g.cities) do if c.shut then shut = true end end
            sick = math.max(sick, Plague.count(g))
        end
        assert(g:outcome(), "the game is over")
        local lazarets, dead = 0, 0
        for _, c in ipairs(g.cities) do
            if c.buildings.lazaret then lazarets = lazarets + 1 end
            dead = dead + (c.dead or 0)
        end
        assert(lazarets > 0, "the AI built lazarets")
        assert(shut, "and shut its gates")
        assert(sick >= 2 and dead > 5, "the plague went about and killed")
    end },
}
