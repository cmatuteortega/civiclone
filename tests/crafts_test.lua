-- The late crafts (D.TECHS, the fourth and fifth columns), what research
-- costs a wide civilization (D.RESEARCH), and the rivals turning on one
-- that runs away with the game (D.AI_LEADER).

local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local D = require "src.defs"

local function newGame(cat) return Game.new({ seed = 5, wild = false, cataclysm = cat or false }) end

-- Player `id`'s first city, of `pop` citizens.
local function town(g, id, pop)
    local settler
    for _, u in ipairs(g:unitsOf(id)) do if u.kind == "settler" then settler = u end end
    local city = g:found(settler)
    city.pop = pop or 4
    g:assignWork(city)
    return city, g.players[id]
end

return {
    { "the late crafts sit in the fourth and fifth columns, each unlocking something", function()
        for _, id in ipairs({ "astronomy", "medicine", "engineering", "preserving" }) do
            assert(D.TECH[id].tier == 4, id .. " in the fourth column")
        end
        for _, id in ipairs({ "fortification", "rationing" }) do
            assert(D.TECH[id].tier == 5, id .. " in the fifth column")
        end
        for _, id in ipairs(AI.SURVIVAL) do assert(D.TECH[id], id) end
        assert(D.unlocks("preserving")[1].name == "STOREHOUSE")
        assert(D.unlocks("rationing")[1].icon == "food", "its own icon, not a boat")
    end },
    { "a technology costs more for every city past the first", function()
        local g = newGame()
        local _, p = town(g, 1)
        assert(g:techCost(p, "pottery") == D.TECH.pottery.cost, "one city: the cost as it stands")
        for k = 1, 4 do g.cities[#g.cities + 1] = { owner = 1, buildings = {}, pop = 1, cell = 0, id = -k } end
        local want = math.floor(D.TECH.engineering.cost * (1 + 4 * D.RESEARCH.perCity) + 0.5)
        assert(g:techCost(p, "engineering") == want, "five cities: " .. g:techCost(p, "engineering"))
    end },
    { "research is learned at what it costs now", function()
        local g = newGame()
        local first, p = town(g, 1)
        -- A second city, far enough off.
        for _, cell in ipairs(g.cells) do
            if g:dist(cell, g.cells[first.cell]) >= 5 and not g.mil[cell.id] and not g.civ[cell.id] then
                local u = g:addUnit("settler", 1, cell.id)
                if g:canFound(u) then g:found(u) break end
                g:removeUnit(u)
            end
        end
        assert(#g:citiesOf(1) == 2)
        -- What the turn makes is added before the cost is weighed.
        local _, sci = g:income(p)
        p.researching, p.science = "pottery", D.TECH.pottery.cost - sci
        g:finishTurn(p)
        assert(not p.techs.pottery, "two cities pay more than the bare cost")
        local _, sci2 = g:income(p)
        p.science = g:techCost(p, "pottery") - sci2
        g:finishTurn(p)
        assert(p.techs.pottery)
    end },
    { "medicine heals twice as fast", function()
        local g = newGame()
        local _, p = town(g, 1)
        local u
        for _, v in ipairs(g:unitsOf(1)) do if v.kind ~= "settler" then u = v end end
        u.hp = 50
        g:beginTurn(p)
        local once = u.hp - 50
        u.hp = 50
        p.techs.medicine = true
        g:beginTurn(p)
        assert(u.hp - 50 == math.min(50, once * 2), "healed " .. (u.hp - 50) .. " not " .. once * 2)
    end },
    { "engineering deepens the shelter, fortification makes walls a ward too", function()
        local g = newGame("sky")
        local city, p = town(g, 1)
        city.buildings.shelter = true
        city.hp = 200
        assert(Cat.harm(g, city, 40) == 20, "a shelter halves")
        p.techs.engineering = true
        city.hp = 200
        assert(Cat.harm(g, city, 40) == 10, "a deep shelter quarters")
        city.buildings.walls, p.techs.fortification = true, true
        city.hp = 200
        assert(Cat.harm(g, city, 40) == 5, "walls halve it again")
    end },
    { "a storehouse spares the cataclysm's hunger, rationing keeps it from starving a city", function()
        local g = newGame("sky")
        local city, p = town(g, 1, 3)
        g.turn = D.SKY.dark
        local hunger = Cat.thirst(g, city)
        assert(hunger > 0, "the long night is cold")
        city.buildings.storehouse = true
        assert(Cat.thirst(g, city) == math.max(0, hunger - D.BUILDINGS.storehouse.stores))
        city.buildings.storehouse = nil
        city.pop = 12
        g:assignWork(city)
        local f = g:cityYield(city)
        p.techs.rationing = true
        local fr = g:cityYield(city)
        local fed, need = f + hunger, city.pop * 2
        assert(fr == fed - math.min(hunger, math.max(0, fed - need)), "the hunger eats only what is spare")
        assert(fr - need >= math.min(0, fed - need), "and never starves it")
    end },
    { "the rivals turn on one running away with the game", function()
        local g = newGame()
        local _, a = town(g, 1, 3)
        local _, b = town(g, 2, 3)
        town(g, 3, 3)
        assert(AI.leader(g, b) == nil, "no one ahead")
        for k = 1, 12 do g.cities[#g.cities + 1] = { owner = 1, buildings = {}, pop = 6, cell = 0, id = -k } end
        g.turn = g.turn + 1
        assert(AI.leader(g, b) == a.id, "player 1 far ahead")
        assert(AI.leader(g, a) == nil, "the leader has no leader")
    end },
}
