-- A city's focus (D.FOCUS) and the score at the end (D.SCORE): what a
-- civilization has, and what of it lasted.

local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"

local function newGame(seed, cat) return Game.new({ seed = seed or 5, wild = false, cataclysm = cat or false }) end

-- A city of `pop` citizens for player 1, on its settler's hex, with every
-- hex within reach its own.
local function town(g, pop)
    local p = g.players[1]
    local settler
    for _, u in ipairs(g:unitsOf(1)) do if u.kind == "settler" then settler = u end end
    local city = g:found(settler)
    for _, cell in ipairs(g:within(g.cells[city.cell], D.CITY.workRadius)) do
        if not cell.owner then cell.owner, cell.ownerCity = 1, city end
    end
    city.pop = pop or 4
    g:assignWork(city)
    return city, p
end

local function worked(g, city)
    local f, p = 0, 0
    for _, id in ipairs(city.worked) do
        local a, b = g:workYield(city, g.cells[id])
        f, p = f + a, p + b
    end
    return f, p
end

local function part(g, p, label)
    for _, it in ipairs(g:scoreParts(p)) do if it[1] == label then return it[2] end end
end

return {
    { "a city starts balanced, and food or production focus moves its citizens", function()
        local g = newGame(5)
        local city = town(g, 5)
        assert(city.focus == nil, "balanced unless told")
        local f0, p0 = worked(g, city)
        assert(g:setFocus(city, "food"))
        assert(city.focus == "food")
        local f1 = worked(g, city)
        assert(f1 >= f0, ("food focus works no less food: %d < %d"):format(f1, f0))
        assert(g:setFocus(city, "prod"))
        local _, p2 = worked(g, city)
        assert(p2 >= p0, ("production focus works no less production: %d < %d"):format(p2, p0))
        assert(g:setFocus(city, "balanced"))
        assert(city.focus == nil, "balanced is kept as no focus")
        assert(not g:setFocus(city, "gold"), "no such focus")
    end },
    { "the focus is kept as the city grows", function()
        local g = newGame(5)
        local city = town(g, 3)
        g:setFocus(city, "prod")
        city.food = g:growthNeed(city) + 100
        g:finishTurn(g.players[1])
        assert(city.pop == 4 and city.focus == "prod")
    end },
    { "a starving AI city takes up food focus, and lets it go once fed and the world is quiet", function()
        local g = Game.new({ seed = 5, wild = false, cataclysm = false, allAI = true })
        local city = town(g, 3)
        -- Starve it: every citizen works the desert.
        city.pop = 30
        AI.play(g, g.players[1])
        assert(city.focus == "food", "starving: " .. tostring(city.focus))
        city.pop = 1
        AI.play(g, g.players[1])
        assert(city.focus == nil, "fed again: " .. tostring(city.focus))
    end },
    { "the score adds up its parts", function()
        local g = newGame(5)
        local _, p = town(g, 4)
        local sum = 0
        for _, it in ipairs(g:scoreParts(p)) do sum = sum + it[2] end
        assert(g:score(p) == sum)
        assert(part(g, p, "CITIES") == D.SCORE.city)
        assert(part(g, p, "CITIZENS") == 4 * D.SCORE.citizen)
        assert(part(g, p, "GOOD LAND") > 0, "a new city's land gives food")
    end },
    { "people kept: the share of a civilization's people at their most it still has", function()
        local g = newGame(5)
        local city, p = town(g, 8)
        g:finishTurn(p)
        assert(p.peak == g:people(p), "the most it has had is what it has")
        assert(part(g, p, "PEOPLE KEPT") == D.SCORE.kept, "none lost yet")
        city.pop = math.floor(p.peak / 2)
        local kept = part(g, p, "PEOPLE KEPT")
        assert(kept == math.floor(D.SCORE.kept * (city.pop / p.peak) ^ 2) and kept < D.SCORE.kept, "half lost: " .. kept)
    end },
    { "good land: land gone to desert gives no food and counts for nothing", function()
        local g = newGame(5)
        local _, p = town(g, 4)
        local before = 0
        for _, cell in ipairs(g.cells) do
            if cell.owner == 1 and not g:isWater(cell) and g:yield(cell) >= 1 then before = before + 1 end
        end
        for _, cell in ipairs(g.cells) do
            if cell.owner == 1 and not g:isWater(cell) and not cell.city then
                cell.terrain, cell.feature, cell.resource, cell.improvement, cell.river = "desert", nil, nil, nil, nil
                cell.rivers = nil
            end
        end
        assert(part(g, p, "GOOD LAND") < math.floor(before * D.SCORE.land), "the desert took the land")
    end },
    { "wards held: a city standing with a ward against this cataclysm", function()
        local g = newGame(5, "heat")
        local city, p = town(g, 4)
        assert(part(g, p, "WARDS HELD") == 0)
        city.buildings.levee = true       -- not against the heat
        assert(part(g, p, "WARDS HELD") == 0, "a levee holds nothing off in the heat")
        city.buildings.cistern = true
        assert(part(g, p, "WARDS HELD") == D.SCORE.ward)
        city.buildings.shelter = true     -- one city counts once
        assert(part(g, p, "WARDS HELD") == D.SCORE.ward)
        local plain = newGame(5)
        local c2, p2 = town(plain, 4)
        c2.buildings.shelter = true
        assert(part(plain, p2, "WARDS HELD") == 0, "no cataclysm, no ward")
    end },
}
