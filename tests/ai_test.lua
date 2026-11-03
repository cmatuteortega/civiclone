-- The computer players against the cataclysm: once it is foretold they
-- research the way to its wards, put other buildings by for them, and buy
-- them with what gold they have over their reserve; and each rival leans
-- its own way in research (D.CIVS).

local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"

-- A game of `kind` with player `id`'s first city founded, the clock at the
-- omen.
local function foretold(kind, id)
    local g = Game.new({ seed = 5, wild = false, cataclysm = kind, allAI = true })
    local settler
    for _, u in ipairs(g:unitsOf(id)) do if u.kind == "settler" then settler = u end end
    local city = g:found(settler)
    g.turn = D.HEAT.omen
    return g, g.players[id], city
end

return {
    { "once the cataclysm is foretold, research makes for its ward", function()
        local g, p = foretold("heat", 2)
        assert(AI.research(g, p) == "mining", "irrigation's first step, for the cistern")
        p.techs.mining = true
        assert(AI.research(g, p) == "masonry", "then masonry")
        p.techs.masonry = true
        assert(AI.research(g, p) == "irrigation", "then the cistern's own")
        p.techs.irrigation = true
        local next = AI.research(g, p)
        assert(next and next ~= "irrigation", "and then free to choose again")
    end },
    { "a rival puts a building by for its ward and buys it with gold over its reserve", function()
        local g, p, city = foretold("heat", 3)
        p.techs.mining, p.techs.masonry, p.techs.irrigation = true, true, true
        city.build = { kind = "building", id = "monument" }
        p.gold = 1000
        AI.play(g, p)
        assert(city.buildings.cistern, "the cistern bought")
        assert(p.gold < 1000 and p.gold >= p.civ.reserve, "with the gold over the reserve")
    end },
    { "a rival short of gold makes its ward, but doesn't buy it", function()
        local g, p, city = foretold("heat", 2)
        p.techs.mining, p.techs.masonry, p.techs.irrigation = true, true, true
        city.build = { kind = "building", id = "monument" }
        p.gold = p.civ.reserve + 20
        AI.play(g, p)
        assert(city.build and city.build.id == "cistern", "the monument put by for the cistern")
        assert(not city.buildings.cistern and p.gold == p.civ.reserve + 20, "and none of the reserve spent")
    end },
    { "before the omen nothing is bought or put by", function()
        local g, p, city = foretold("heat", 3)
        g.turn = D.HEAT.omen - 1
        p.techs.mining, p.techs.masonry, p.techs.irrigation = true, true, true
        city.build = { kind = "building", id = "monument" }
        p.gold = 1000
        AI.play(g, p)
        assert(not city.buildings.cistern and (not city.build or city.build.id ~= "cistern"))
    end },
    { "Nocta leans to war in research, Tess to building", function()
        local g = Game.new({ seed = 5, wild = false, cataclysm = false, allAI = true, rivals = { "umbra", "varro" } })
        local war, build = 0, 0
        for _ = 1, 300 do
            if AI.research(g, g.players[2]) == "archery" then war = war + 1 end
            if AI.research(g, g.players[3]) ~= "archery" then build = build + 1 end
        end
        -- Archery is one in three for a civilization that leans no way.
        assert(war > 150, "Nocta picks archery most often: " .. war)
        assert(build > 250, "Tess seldom does: " .. build)
    end },
}
