-- The weather: short spells of rain and storm that come and go over the
-- whole map, a few turns at a time, by D.WEATHER's numbers.
--
--   FAIR    as it always was.
--   CLOUDS  the turn before a spell: the clouds gather, and the news says
--           what is coming, so ships can make for port.
--   RAIN    the fields drink: every farm yields more food, and the rain
--           puts out fires -- the heat's, the stones', the volcanoes',
--           whatever lit them -- and in the heat death no new ones start.
--   STORM   the farms still do, but the mine shafts flood (less production),
--           the fishing boats stay in harbour (less food), under the cloud
--           every unit sees less far, and the sea batters every ship and
--           boat out on it, unless it lies in port: on or beside a city of
--           its own, or near one with a harbour.
--
-- Outside a cataclysm the sky is the weather's. Once one begins, it is the
-- cataclysm's -- the deluge's rains, the still sun's storm, the long night's
-- snow -- but in the stages that burn (D.WEATHER.open) a rare spell of rain
-- still comes, and no storm.
--
-- What is kept is game.weather: `spell`, the weather of each turn of the
-- spell in order ("rain", "storm"), `at` the turn of it this is, `coming`
-- the spell the clouds have gathered for (it begins next turn), and `calm`
-- the turns of fair weather since the last. Nil is fair, as in a game kept
-- before there was weather. The dice are the game's seed and the turn, so
-- the weather does not move the game's own dice. Nothing here draws:
-- src/ui/rain.lua lets the rain fall and the lightning strike.

local D = require "src.defs"
local L = require "src.lang"
local Cat = require "src.cataclysm"

local floor, sin, max = math.floor, math.sin, math.max

local W = {}

W.names = { rain = "RAIN", storm = "STORM", clouds = "CLOUDS" }

-- A number 0..1 from the seed, the turn and `k`, the same each time.
local function dice(game, k)
    local n = sin((game.seed or 0) * 0.0137 + game.turn * 12.9898 + k * 78.233) * 43758.5453
    return n - floor(n)
end

local function range(game, r, k)
    return r[1] + floor(dice(game, k) * (r[2] - r[1] + 1))
end

-- Can there be weather now: always outside a cataclysm; in one, only in
-- the stages D.WEATHER.open names (and then rain alone).
function W.open(game)
    local s = Cat.stage(game)
    if s == nil then return true end
    local open = D.WEATHER.open[game.cataclysm.kind]
    return open ~= nil and open[s] == true
end

-- Is it a cataclysm's sky, where only rain comes, and less often?
local function shared(game) return Cat.stage(game) ~= nil end

-- The weather now: "rain", "storm", or nil (fair).
function W.now(game)
    local w = game.weather
    if not w or not w.spell or not W.open(game) then return nil end
    return w.spell[w.at]
end

-- Is it raining (in a storm too)?
function W.wet(game) return W.now(game) ~= nil end

-- The spell the clouds have gathered for, beginning next turn, or nil.
function W.coming(game)
    local w = game.weather
    return w and W.open(game) and w.coming or nil
end

-- Will there be a storm this turn or the next few: now, later in this
-- spell, or in the one coming.
function W.stormAhead(game)
    local w = game.weather
    if not w or not W.open(game) then return false end
    for _, list in ipairs({ w.spell or {}, w.coming or {} }) do
        for k = (list == w.spell and w.at or 1), #list do
            if list[k] == "storm" then return true end
        end
    end
    return false
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

-- The words for the top bar: "RAIN 3", "CLOUDS", or nil when fair.
function W.label(game)
    local now = W.now(game)
    if now then return L(W.names[now]) .. " " .. W.left(game) end
    if W.coming(game) then return L(W.names.clouds) end
end

local TELL = {
    rain = "THE RAINS HAVE COME: THE FARMS YIELD MORE",
    storm = "A STORM BREAKS: THE MINES FLOOD, THE BOATS STAY IN HARBOUR",
}

--- the storm at sea ------------------------------------------------------------------

-- Does unit u lie safe in port on hex `cell`: on a city of its own's hex or
-- beside it, or within reach of one of its own with a harbour?
function W.haven(game, u, cell)
    if cell.city then return true end
    local Wd = D.WEATHER
    for _, c in ipairs(game.cities) do
        if c.owner == u.owner then
            local d = game:dist(cell, game.cells[c.cell])
            if d <= Wd.haven or (c.buildings.harbour and d <= Wd.harbour) then return true end
        end
    end
    return false
end

-- Is unit u out in the storm's way on hex `cell`: a ship, or a boat, on
-- the water and not in port. The wild's are their own.
function W.exposed(game, u, cell)
    if u.owner == game.WILD or not game:isWater(cell) then return false end
    return not W.haven(game, u, cell)
end

-- What the storm does at sea as its turn begins: every ship and boat out in
-- it battered, and sunk if it has no more to give.
local function batter(game)
    local Wd = D.WEATHER
    local out = {}
    for _, u in ipairs(game.units) do
        if W.exposed(game, u, game.cells[u.cell]) then out[#out + 1] = u end
    end
    for _, u in ipairs(out) do
        if not u.dead then
            Cat.hurt(game, u, u.def.sea and Wd.shipHit or Wd.boatHit, "WAS SUNK IN THE STORM")
        end
    end
end

--- the rain on the fires -------------------------------------------------------------

-- Each fire burning goes out with chance D.WEATHER.douse, the land under it
-- saved as it is.
local function douse(game)
    local n = 0
    for _, cell in ipairs(game.cells) do
        if cell.fire and dice(game, 100 + cell.id * 0.37) < D.WEATHER.douse then
            cell.fire = nil
            game:emit({ kind = "terrain", cell = cell.id })
            n = n + 1
        end
    end
    if n > 0 then game:tell(nil, "THE RAIN HAS PUT OUT {1} FIRES", n) end
end

-- Should the heat's own fires start this turn (src/cataclysm.lua)? Not in
-- the rain.
function W.kindling(game) return not W.wet(game) end

--- the turn ---------------------------------------------------------------------------

-- A spell, from the dice: rain alone, or a storm wrapped in rain (not in a
-- cataclysm's sky).
local function cast(game)
    local Wd = D.WEATHER
    local spell = {}
    if not shared(game) and dice(game, 2) < Wd.stormChance then
        for _ = 1, Wd.lead do spell[#spell + 1] = "rain" end
        for _ = 1, range(game, Wd.storm, 3) do spell[#spell + 1] = "storm" end
        for _ = 1, Wd.tail do spell[#spell + 1] = "rain" end
    else
        for _ = 1, range(game, Wd.rain, 4) do spell[#spell + 1] = "rain" end
    end
    return spell
end

-- A new turn's weather, as the turn begins.
function W.turn(game)
    local Wd = D.WEATHER
    local w = game.weather or { calm = 0 }
    game.weather = w
    local before = w.spell and w.spell[w.at]
    if not W.open(game) then
        w.spell, w.at, w.coming = nil, nil, nil
        return
    end
    if w.spell then
        w.at = w.at + 1
        if w.at > #w.spell then w.spell, w.at, w.calm = nil, nil, 0 end
    elseif w.coming then
        w.spell, w.at, w.coming = w.coming, 1, nil
    elseif game.turn >= Wd.from then
        w.calm = (w.calm or 0) + 1
        local chance = Wd.chance * (shared(game) and Wd.cataclysmChance or 1)
        if w.calm > Wd.calm and dice(game, 1) < chance then
            w.coming = cast(game)
            local storm = false
            for _, s in ipairs(w.coming) do if s == "storm" then storm = true end end
            game:tell(nil, storm and "CLOUDS GATHER: A STORM IS COMING. BRING THE SHIPS INTO PORT"
                or "CLOUDS GATHER: RAIN IS COMING")
            game:emit({ kind = "weather", weather = "clouds" })
        end
    end
    local now = W.now(game)
    if now ~= before then
        if now then game:tell(nil, TELL[now])
        elseif before then game:tell(nil, "THE SKY CLEARS") end
        game:emit({ kind = "weather", weather = now })
    end
    if now == "storm" then batter(game) end
    if now then douse(game) end
end

--- what it does -----------------------------------------------------------------------

-- What the weather does to hex `cell`'s food and production.
function W.yield(game, cell, f, p)
    local now = W.now(game)
    if not now then return f, p end
    local Wd = D.WEATHER
    if cell.improvement == "farm" then f = f + Wd.farmFood end
    if now == "storm" then
        if cell.improvement == "mine" then p = max(0, p - Wd.mineProd) end
        if cell.improvement == "boats" then f = max(0, f - Wd.boatsFood) end
    end
    return f, p
end

-- How many hexes less far every unit sees.
function W.blind(game)
    return W.now(game) == "storm" and D.WEATHER.blind or 0
end

-- How overcast the sky is for the shaders (src/ui/sea.lua): the clouds
-- gathering the turn before a spell.
function W.overcast(game)
    return W.coming(game) and D.WEATHER.overcast or 0
end

return W
