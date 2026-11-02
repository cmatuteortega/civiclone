local Game = require "src.game"
local Weather = require "src.weather"
local D = require "src.defs"

local function newGame(kind) return Game.new({ seed = 7, wild = false, cataclysm = kind or false }) end

-- Turn the game's turn over, weather only, `n` times; what each was.
local function run(g, n)
    local seen = {}
    for _ = 1, n do
        g.turn = g.turn + 1
        Weather.turn(g)
        seen[#seen + 1] = Weather.now(g) or "fair"
    end
    return seen
end

local function find(g, f)
    for _, cell in ipairs(g.cells) do if f(cell) then return cell end end
end

return {
    { "spells of rain and storm come and go, and leave fair weather between", function()
        local g = newGame()
        local seen = run(g, 140)
        local rain, storm, fair = 0, 0, 0
        for _, w in ipairs(seen) do
            if w == "rain" then rain = rain + 1 elseif w == "storm" then storm = storm + 1 else fair = fair + 1 end
        end
        assert(rain > 0, "it never rained")
        assert(fair > rain + storm, "more bad weather than fair")
        for k = 1, D.WEATHER.from - 2 do assert(seen[k] == "fair", "weather before turn " .. D.WEATHER.from) end
        -- A storm never comes out of a fair sky: rain first.
        for k = 2, #seen do
            if seen[k] == "storm" then assert(seen[k - 1] ~= "fair", "a storm from a fair sky") end
        end
    end },

    { "the weather is the same for the same seed", function()
        local a, b = run(newGame(), 120), run(newGame(), 120)
        for k = 1, #a do assert(a[k] == b[k]) end
    end },

    { "rain feeds the farms; a storm floods the mines and keeps the boats in", function()
        local g = newGame()
        local farm = find(g, function(c) return not g:isWater(c) and c.elev == "flat" and not c.city end)
        farm.improvement = "farm"
        local mine = find(g, function(c) return c.elev == "hills" and not c.city end)
        mine.improvement = "mine"
        local f0 = g:yield(farm)
        local _, p0 = g:yield(mine)
        g.weather = { spell = { "rain" }, at = 1, calm = 0 }
        assert(g:yield(farm) == f0 + D.WEATHER.farmFood)
        assert(select(2, g:yield(mine)) == p0)
        assert(Weather.blind(g) == 0)
        g.weather = { spell = { "storm" }, at = 1, calm = 0 }
        assert(g:yield(farm) == f0 + D.WEATHER.farmFood)
        assert(select(2, g:yield(mine)) == p0 - D.WEATHER.mineProd)
        assert(Weather.blind(g) == D.WEATHER.blind)
        assert(Weather.label(g) == "STORM 1")
        g.weather = nil
        assert(g:yield(farm) == f0 and Weather.label(g) == nil)
    end },

    { "the cataclysm has the sky once it has begun", function()
        local g = newGame("flood")
        g.weather = { spell = { "rain", "rain" }, at = 1, calm = 0 }
        assert(Weather.now(g) == "rain")
        g.turn = D.FLOOD.omen
        assert(Weather.now(g) == nil)
        Weather.turn(g)
        assert(g.weather.spell == nil)
    end },

    { "the news tells of the spell and of the clearing", function()
        local g = newGame()
        g.weather = { spell = { "rain", "storm" }, at = 1, calm = 0 }
        local n = #g.log
        Weather.turn(g)
        assert(g.log[#g.log].text:find("STORM"), "no word of the storm")
        Weather.turn(g)
        assert(#g.log == n + 2 and g.log[#g.log].text == "THE SKY CLEARS")
    end },

    { "a game kept before the weather plays on", function()
        local g = newGame()
        g.weather = nil
        assert(Weather.now(g) == nil)
        g:endTurn()
        assert(g.weather ~= nil)
    end },
}
