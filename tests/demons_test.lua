local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local Demons = require "src.demons"
local D = require "src.defs"

-- The wild's beasts are left off: these are the demons' rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false, cataclysm = "demons" }) end

local function free(g, cell) return not g.mil[cell.id] and not g.civ[cell.id] and not cell.city and not cell.lair end

local function find(g, f)
    for _, cell in ipairs(g.cells) do if free(g, cell) and f(cell) then return cell end end
end

local function count(g, f)
    local n = 0
    for _, cell in ipairs(g.cells) do if f(cell) then n = n + 1 end end
    return n
end

local function settle(g, who)
    for _, u in ipairs(g.units) do
        if u.owner == (who or 1) and u.kind == "settler" then return g:found(u) end
    end
end

local function cityOf(g, who) return g:citiesOf(who or 1)[1] end

local function flat(g, c) return g:passable(c) and c.elev == "flat" and not c.river end

-- A free land hex beside `cell`.
local function beside(g, cell, f)
    for _, n in ipairs(g:neighbours(cell)) do
        if free(g, n) and g:passable(n) and (not f or f(n)) then return n end
    end
end

-- The citadel risen by the turns as they come, from the omen's last turn.
local function raise(g)
    g.turn = D.DEMONS.rifts - 1
    Cat.turn(g)
    g.turn = D.DEMONS.rifts
    Cat.turn(g)
    return Demons.citadel(g)
end

return {
    { "the demons' stages come on their turns", function()
        assert(Cat.stageAt(D.DEMONS.omen - 1, "demons") == nil)
        assert(Cat.stageAt(D.DEMONS.omen, "demons") == "omen")
        assert(Cat.stageAt(D.DEMONS.rifts, "demons") == "rifts")
        assert(Cat.stageAt(D.DEMONS.deep + 1, "demons") == "deep")
        assert(Cat.stageAt(D.LAST_TURN, "demons") == "hellgate")
        local g = newGame()
        assert(g.cataclysm.kind == "demons")
        g.turn = D.DEMONS.hellgate
        assert(Cat.label(g) == "HELLGATE " .. (D.LAST_TURN - D.DEMONS.hellgate + 1))
        assert(Cat.ward(g) == "sanctum")
        assert(Cat.ended(g) == "THE ABYSS HAS SWALLOWED THE WORLD")
        g.turn = D.DEMONS.omen
        Cat.turn(g)
        assert(g.log[#g.log].text:find("BLOOD"))
    end },
    { "the citadel's ground is marked the turn before it rises, away from every city", function()
        local g = newGame()
        settle(g, 1)
        settle(g, 2)
        g.turn = D.DEMONS.rifts - 2
        Cat.turn(g)
        assert(next(g.cataclysm.marks or {}) == nil, "nothing yet")
        g.turn = D.DEMONS.rifts - 1
        Cat.turn(g)
        local at
        for id, what in pairs(g.cataclysm.marks) do if what == "citadel" then at = id end end
        assert(at and Demons.marked(g, g.cells[at]) == "citadel")
        for _, c in ipairs(g.cities) do
            assert(g:dist(g.cells[at], g.cells[c.cell]) >= D.DEMONS.citadelFrom, "far from the towns")
        end
        g.turn = D.DEMONS.rifts
        Cat.turn(g)
        local lair, cell = Demons.citadel(g)
        assert(lair and cell.id == at, "it rose where it was seen coming")
        assert(lair.hp == D.DEMONS.citadelHp.rifts and lair.str == D.DEMONS.citadelStr.rifts)
        assert(cell.blight, "its ground is blighted")
        for _, p in ipairs(g.players) do assert(p.explored[at], "everyone knows where it is") end
    end },
    { "the citadel grows stage by stage, sends demons out and blights its borders", function()
        local g = newGame()
        local lair, cell = raise(g)
        local before = count(g, function(c) return c.blight end)
        for t = D.DEMONS.rifts + 1, D.DEMONS.deep do
            g.turn = t
            Cat.turn(g)
        end
        assert(lair.maxHp == D.DEMONS.citadelHp.deep and lair.str == D.DEMONS.citadelStr.deep, "it has grown")
        assert(count(g, function(c) return c.blight end) > before + 10, "the blight has spread")
        local reach = D.DEMONS.citadelReach.deep
        local demons = 0
        for _, u in ipairs(g.units) do
            if u.def.demon and u.home == cell.id then demons = demons + 1 end
        end
        assert(demons > 0, "it has sent its demons out")
        for _, c in ipairs(g.cells) do
            if c.blight then
                local near = g:dist(c, cell) <= reach
                for _, l in ipairs(g.lairs) do
                    if l.kind == "rift" and g:dist(c, g.cells[l.cell]) <= D.DEMONS.riftReach.deep then near = true end
                end
                assert(near, "blight lies only within some reach")
            end
        end
    end },
    { "no one walks into the citadel while it stands; beaten down, it is razed and the Eye never opens", function()
        local g = newGame()
        settle(g, 1)
        local lair, cell = raise(g)
        for _, v in ipairs(g:unitsOf(g.WILD)) do g:removeUnit(v) end
        local spot = beside(g, cell)
        local u = g:addUnit("swordsman", 1, spot.id)
        assert(not g:canStand(u, cell), "it stands")
        assert(g:canAttack(u, cell), "but it can be struck")
        local hp = lair.hp
        assert(g:attack(u, cell))
        assert(lair.hp < hp, "it took the blow")
        u.hp, u.moves, u.attacked = 100, u.def.moves, false
        lair.hp = 1
        local glory = g.players[1].glory or 0
        assert(g:attack(u, cell))
        assert(u.cell == cell.id, "the attacker walked in")
        assert(not Demons.citadel(g), "and razed it")
        assert((g.players[1].glory or 0) >= glory + D.LAIRS.citadel.prize.glory, "for glory")
        local told = false
        for _, l in ipairs(g.log) do if l.text:find("NEVER OPEN") then told = true end end
        assert(told)
        g.turn = D.DEMONS.eye
        Cat.turn(g)
        for _, v in ipairs(g.units) do assert(v.kind ~= "abyss", "no Eye of the Abyss") end
    end },
    { "the Eye of the Abyss is told, and opens in the citadel if it stands", function()
        local g = newGame()
        raise(g)
        g.turn = D.DEMONS.eyeWarn
        Cat.turn(g)
        assert(Demons.eyeComing(g) == D.DEMONS.eye - D.DEMONS.eyeWarn)
        g.turn = D.DEMONS.eye
        Cat.turn(g)
        local eye
        for _, v in ipairs(g.units) do if v.kind == "abyss" then eye = v end end
        assert(eye and eye.def.boss)
    end },
    { "a rift is seen coming, opens, blights round it, and is sealed by walking in", function()
        local g = newGame()
        settle(g, 1)
        local spot = find(g, function(c) return flat(g, c) and g:dist(c, g.cells[cityOf(g).cell]) == 5 end)
        g.turn = D.DEMONS.rifts
        g.cataclysm.marks = { [spot.id] = "rift" }
        Cat.turn(g)
        assert(spot.lair and spot.lair.kind == "rift", "it opened")
        assert(spot.blight)
        -- Clear its demons off, and walk in.
        for _, v in ipairs(g:unitsOf(g.WILD)) do g:removeUnit(v) end
        local by = beside(g, spot)
        local u = g:addUnit("warrior", 1, by.id)
        assert(g:step(u, spot.id))
        assert(not spot.lair, "sealed")
        assert(not spot.blight, "its own ground heals")
        assert((g.players[1].glory or 0) >= D.LAIRS.rift.prize.glory)
    end },
    { "the blight takes the farm and the trees and yields nothing; a sanctum's land it never takes", function()
        local g = newGame()
        settle(g, 1)
        local city = cityOf(g)
        local farm = find(g, function(c) return flat(g, c) and c.terrain == "grass" end)
        farm.improvement = "farm"
        local wood = find(g, function(c) return g:passable(c) and c.feature == "forest" end)
        Demons.blight(g, farm)
        Demons.blight(g, wood)
        assert(not farm.improvement and farm.blight)
        assert(not wood.feature and wood.burntForest, "the trees are dead")
        g.turn = D.DEMONS.rifts
        assert(g:yield(farm) == 0, "blighted land yields no food")
        assert(g:describe(farm):find("BLIGHTED"))
        city.buildings.sanctum = true
        local own
        for _, c in ipairs(g.cells) do if c.ownerCity == city and not c.city and g:passable(c) then own = c end end
        assert(Demons.hallowed(own), "the sanctum keeps its land")
        g.turn = D.DEMONS.rifts
        g.cataclysm.marks = { [own.id] = "rift" }
        for _ = 1, 10 do Demons.play(g, "rifts") end
        assert(not own.blight, "the blight never takes it")
    end },
    { "a demon never takes a city: it is left at 1 HP and loses a citizen; a shelter keeps its people", function()
        local g = newGame()
        settle(g, 1)
        local city = cityOf(g)
        city.pop = 4
        g.turn = D.DEMONS.rifts
        local cell = g.cells[city.cell]
        local spot = beside(g, cell)
        local b = g:addUnit("brood", g.WILD, spot.id)
        city.hp = 2
        g.current = g.WILD
        assert(g:canAttack(b, cell), "a demon goes for the town")
        assert(g:attack(b, cell))
        assert(city.owner == 1 and city.hp == 1, "it still stands")
        assert(city.pop == 3, "a citizen taken")
        -- Once a turn; and a shelter keeps them.
        b.moves, b.attacked = 2, false
        g:attack(b, cell)
        assert(city.pop == 3)
        g.turn = g.turn + 1
        city.buildings.shelter = true
        b.moves, b.attacked = 2, false
        g:attack(b, cell)
        assert(city.pop == 3 and city.hp == 1)
        -- A beast still leaves the towns alone.
        local w = g:addUnit("wolf", g.WILD, beside(g, cell).id)
        assert(not g:canAttack(w, cell))
    end },
    { "a tentacle drags a civilian under, lashes the shore, and is struck from it", function()
        local g = newGame()
        local water = find(g, function(c)
            if c.terrain ~= "coast" then return false end
            local n = 0
            for _, nb in ipairs(g:neighbours(c)) do if free(g, nb) and g:passable(nb) then n = n + 1 end end
            return n >= 2
        end)
        local t = g:addUnit("tentacle", g.WILD, water.id)
        local a = beside(g, water)
        local b = beside(g, water, function(n) return n ~= a end)
        local builder = g:addUnit("builder", 1, a.id)
        local warrior = g:addUnit("warrior", 1, b.id)
        g.current = g.WILD
        assert(g:canAttack(t, a), "it reaches the shore")
        assert(g:attack(t, a))
        assert(builder.dead, "the builder was dragged under")
        g.current = 1
        assert(g:canAttack(warrior, water), "a soldier on the shore strikes it")
        t.hp = 1
        g:attack(warrior, water)
        assert(t.dead and warrior.cell == b.id, "killed, and the soldier stays on the land")
    end },
    { "tentacles are seen coming by the shore in the deep, and sink after their time", function()
        local g = newGame()
        g.turn = D.DEMONS.deep - 1
        Cat.turn(g)
        local marked = 0
        for _, what in pairs(g.cataclysm.marks) do if what == "tentacle" then marked = marked + 1 end end
        assert(marked == D.DEMONS.tentacles.deep)
        g.turn = D.DEMONS.deep
        Cat.turn(g)
        local up = 0
        for _, u in ipairs(g.units) do if u.kind == "tentacle" then up = up + 1 end end
        assert(up == marked)
        local old = {}
        for _, u in ipairs(g.units) do
            if u.kind == "tentacle" then u.life = 1; old[#old + 1] = u end
        end
        g.turn = D.DEMONS.deep + 1
        Cat.turn(g)
        for _, u in ipairs(old) do assert(u.dead, "it has sunk") end
    end },
    { "dread takes food from the cities, less with a sanctum, less again with a shelter", function()
        local g = newGame()
        settle(g, 1)
        local city = cityOf(g)
        g.turn = D.DEMONS.hellgate
        local full = D.DEMONS.dread.hellgate
        assert(Cat.thirst(g, city) == full)
        city.buildings.sanctum = true
        assert(Cat.thirst(g, city) == full - D.DEMONS.sanctumDread)
        city.buildings.shelter = true
        assert(Cat.thirst(g, city) == full - D.DEMONS.sanctumDread - D.SHELTER.stores)
    end },
    { "the sanctum is built only against the demons, and shoots them without walls", function()
        local g = newGame()
        settle(g, 1)
        local city = cityOf(g)
        g.players[1].techs.writing = true
        assert(g:canBuild(city, "building", "sanctum"))
        local h = Game.new({ seed = 5, wild = false, cataclysm = "heat" })
        settle(h, 1)
        h.players[1].techs.writing = true
        assert(not h:canBuild(cityOf(h), "building", "sanctum"))
        city.buildings.sanctum = true
        local spot = beside(g, g.cells[city.cell])
        local s = g:addUnit("spider", g.WILD, spot.id)
        g:cityStrike(city)
        assert(s.hp < 100 or s.dead, "the sanctum shot the demon")
    end },
    { "the AI builds sanctums and fights the demons, and an all-AI game runs to its end", function()
        local g = Game.new({ seed = 7, allAI = true, cataclysm = "demons" })
        while g.turn <= D.LAST_TURN do
            AI.play(g, g.players[1])
            g:endTurn(AI)
        end
        local result = g:outcome()
        assert(result, "the game is over")
        local sanctums, glory = 0, 0
        for _, c in ipairs(g.cities) do if c.buildings.sanctum then sanctums = sanctums + 1 end end
        for _, p in ipairs(g.players) do glory = glory + (p.glory or 0) end
        assert(sanctums > 0, "the AI raised sanctums")
        assert(glory > 5, "and slew demons")
        assert(count(g, function(c) return c.blight end) > 10, "the land is blighted")
    end },
}
