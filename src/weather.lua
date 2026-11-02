-- The weather: short spells of rain and storm that come and go over the
-- whole map, a few turns at a time, by D.WEATHER's numbers.
--
--   FAIR   as it always was.
--   RAIN   the fields drink: every farm yields more food.
--   STORM  the farms still do, but the mine shafts flood (less production),
--          the fishing boats stay in harbour (less food), and under the
--          cloud and the rain every unit sees less far.
--
-- A spell is told as it begins and as the sky clears. It is the sky's own
-- until a cataclysm's omen; from then on the cataclysm has the sky (the
-- deluge's rains, the still sun's storm, the long night's snow), and the
-- weather stays fair.
--
-- What is kept is game.weather: `spell`, the weather of each turn of the
-- spell in order ("rain", "storm"), `at` the turn of it this is, and
-- `calm` the turns of fair weather since the last. Nil is fair, as in a
-- game kept before there was weather. The dice are the game's seed and the
-- turn, so the weather does not move the game's own dice. Nothing here
-- draws: src/ui/rain.lua lets the rain fall and the lightning strike.

local D = require "src.defs"
local L = require "src.lang"
local Cat = require "src.cataclysm"

local floor, sin = math.floor, math.sin

local W = {}

W.names = { rain = "RAIN", storm = "STORM" }

-- A number 0..1 from the seed, the turn and `k`, the same each time.
local function dice(game, k)
    local n = sin((game.seed or 0) * 0.0137 + game.turn * 12.9898 + k * 78.233) * 43758.5453
    return n - floor(n)
end

local function range(game, r, k)
    return r[1] + floor(dice(game, k) * (r[2] - r[1] + 1))
end

-- Can there be weather now: not once a cataclysm has begun.
function W.open(game)
    return Cat.stage(game) == nil
end

-- The weather now: "rain", "storm", or nil (fair).
function W.now(game)
    local w = game.weather
    if not w or not w.spell or not W.open(game) then return nil end
    return w.spell[w.at]
end

-- The turns left of the weather now, this one with them.
function W.left(game)
    local w = game.weather
    if not W.now(game) then return 0 end
    local n = 0
    for k = w.at, #w.spell do
        if w.spell[k] ~= w.spell[w.at] then break end
        n = n + 1
    end
    return n
end

-- The words for the top bar: "RAIN 3", or nil when fair.
function W.label(game)
    local now = W.now(game)
    return now and (L(W.names[now]) .. " " .. W.left(game)) or nil
end

local TELL = {
    rain = "THE RAINS HAVE COME: THE FARMS YIELD MORE",
    storm = "A STORM BREAKS: THE MINES FLOOD, THE BOATS STAY IN HARBOUR",
}

-- A new turn's weather, as the turn begins.
function W.turn(game)
    local W_ = D.WEATHER
    local w = game.weather or { calm = 0 }
    game.weather = w
    local before = W.now(game)
    if not W.open(game) then
        w.spell, w.at = nil, nil
        return
    end
    if w.spell then
        w.at = w.at + 1
        if w.at > #w.spell then w.spell, w.at, w.calm = nil, nil, 0 end
    elseif game.turn >= W_.from then
        w.calm = (w.calm or 0) + 1
        if w.calm > W_.calm and dice(game, 1) < W_.chance then
            local spell = {}
            if dice(game, 2) < W_.stormChance then
                for _ = 1, W_.lead do spell[#spell + 1] = "rain" end
                for _ = 1, range(game, W_.storm, 3) do spell[#spell + 1] = "storm" end
                for _ = 1, W_.tail do spell[#spell + 1] = "rain" end
            else
                for _ = 1, range(game, W_.rain, 4) do spell[#spell + 1] = "rain" end
            end
            w.spell, w.at = spell, 1
        end
    end
    local now = W.now(game)
    if now ~= before then
        if now then game:tell(nil, TELL[now])
        elseif before then game:tell(nil, "THE SKY CLEARS") end
        game:emit({ kind = "weather", weather = now })
    end
end

-- What the weather does to hex `cell`'s food and production.
function W.yield(game, cell, f, p)
    local now = W.now(game)
    if not now then return f, p end
    local W_ = D.WEATHER
    if cell.improvement == "farm" then f = f + W_.farmFood end
    if now == "storm" then
        if cell.improvement == "mine" then p = math.max(0, p - W_.mineProd) end
        if cell.improvement == "boats" then f = math.max(0, f - W_.boatsFood) end
    end
    return f, p
end

-- How many hexes less far every unit sees.
function W.blind(game)
    return W.now(game) == "storm" and D.WEATHER.blind or 0
end

return W
