-- The deluge: the world ends in water. One of the cataclysm's kinds
-- (src/cataclysm.lua), on the same turns as the heat death, by D.FLOOD's:
--
--   OMEN       everyone is told what is coming, and when.
--   RAINS      the long rains. At first they are a blessing: the land grows
--              wetter a few hexes a turn, desert to plains, plains to
--              grassland, and every farm yields more. But flat grassland
--              beside water goes on to marsh, its farm sunk in the mire.
--   FLOODS     as well, the rivers burst their banks. A flood lies on a hex
--              for a few turns and runs on from it, down the river and over
--              the low land beside it: it yields nothing, hurts what stands
--              in it and the cities beside it, and as it goes down it takes
--              the farm or the mine with it but leaves silt, that yields
--              more for good. Cities sicken: fever takes their food.
--   SEA        the sea rises. Each turn it takes a few hexes of the flat land
--              along the shore, the lowest first, for good: they are coast,
--              and ships sail where the fields were. Hills stand out of it as
--              islands; the fever worsens, and the surge beats on the cities
--              by the shore.
--
-- It is the heat death the other way about: there the rivers and the coast
-- held out, and here they are where the water comes. What holds it off is
-- high ground, forest (its roots hold the banks), and a city's levee: its
-- land goes to marsh and floods less, the sea can't take it, the water
-- beside the city does it no harm, and its people sicken less. A shelter
-- (D.SHELTER) halves what the water does to a city with no levee.
--
-- The cells keep what has happened to them: `flood` (turns the water still
-- lies), `silt` (it has lain there), `drowned` (the sea has taken it;
-- `drownedForest` if trees stood there). The game emits "terrain" for every
-- hex that changes, "flood" for every flood that starts (with `cell`) and
-- as each stage begins (with `stage`). Nothing here draws.

local D = require "src.defs"
local Cat = require "src.cataclysm"

local max = math.max

local F = {
    stages = { "omen", "rains", "floods", "sea" },
    names = { omen = "THE OMEN", rains = "THE LONG RAINS", floods = "THE FLOODS", sea = "THE RISING SEA" },
    words = { omen = "OMEN", rains = "RAINS", floods = "FLOODS", sea = "SEA RISES" },
    turns = D.FLOOD, event = "flood", ward = "levee", ended = "THE WORLD HAS DROWNED",
}

local function levee(cell) return Cat.warded(cell, "levee") end
F.levee = levee

local function land(game, cell)
    return not game:isWater(cell) and cell.elev ~= "mountain"
end

-- Is there water beside the hex: a river along it, the sea or a marsh?
local function wet(game, cell)
    if game:onRiver(cell) then return true end
    for _, n in ipairs(game:neighbours(cell)) do
        if game:isWater(n) or n.terrain == "marsh" or n.flood then return true end
    end
    return false
end
F.wet = wet

--- what it does to what the land yields ------------------------------------------------

-- Food on hex `cell`, `f` before the deluge has its say: the rains feed the
-- farms, and silt the land the flood has left.
function F.food(game, cell, f)
    if cell.improvement == "farm" and Cat.past(game, "rains") then f = f + D.FLOOD.rainFarm end
    if cell.silt then f = f + D.FLOOD.siltFood end
    return f
end

-- The food city `city` loses this turn to fever.
function F.thirst(game, city)
    local s = Cat.stage(game)
    local t = s and D.FLOOD.fever[s] or 0
    if t > 0 and city.buildings.levee then t = max(0, t - D.FLOOD.leveeFever) end
    return t
end

--- the rains -----------------------------------------------------------------------------

-- How likely hex `cell` is to grow a step wetter this turn, against the
-- others; 0 if it can't. Grassland goes to marsh only flat and by water;
-- a forest's ground stays as it is; a flooded hex waits for the water.
local function wetWeight(game, cell)
    if not land(game, cell) or cell.city or cell.flood or cell.terrain == "marsh" then return 0 end
    if cell.terrain ~= "grass" then return cell.feature == "forest" and 0.3 or 1 end
    if cell.elev ~= "flat" or cell.feature or not wet(game, cell) then return 0 end
    local w = D.FLOOD.near
    if levee(cell) then w = w * D.FLOOD.levee end
    return w
end
F.wetWeight = wetWeight

-- One hex a step wetter: desert to plains, plains to grassland, grassland to
-- marsh (its farm sunk, its grain rotted).
function F.wetten(game, cell)
    if cell.terrain == "desert" then
        cell.terrain = "plains"
        cell.scorched = nil
    elseif cell.terrain == "plains" then
        cell.terrain = "grass"
    else
        cell.terrain = "marsh"
        if cell.improvement == "farm" then
            cell.improvement = nil
            if cell.owner then game:tell(cell.owner, "A FARM HAS SUNK INTO THE MIRE") end
        end
        if cell.resource == "wheat" then cell.resource = nil end
    end
    game:emit({ kind = "terrain", cell = cell.id })
end

--- the floods ----------------------------------------------------------------------------

-- Can the water lie here: low land, not a city's own hex, nor on hills.
function F.floodable(game, cell)
    return land(game, cell) and cell.elev == "flat" and not cell.city and not cell.flood
end

-- How likely a flood is to take hex `cell`, times the rest: less under
-- trees, on silt and on a levee's land.
local function hold(cell)
    local w = 1
    if cell.feature == "forest" then w = w * D.FLOOD.forest end
    if cell.silt then w = w * D.FLOOD.silted end
    if levee(cell) then w = w * D.FLOOD.leveeFlood end
    return w
end

function F.inundate(game, cell)
    local what = game:describe(cell)
    cell.flood = D.FLOOD.last
    game:emit({ kind = "flood", cell = cell.id })
    game:emit({ kind = "terrain", cell = cell.id })
    if cell.owner then game:tell(cell.owner, "FLOOD! THE " .. what .. " IS UNDER WATER") end
end

-- The water gone down: the farm and the mine washed away, silt left, and
-- the desert under it plains.
local function recede(game, cell)
    cell.flood = nil
    cell.silt = true
    if cell.improvement == "farm" or cell.improvement == "mine" then
        if cell.owner then game:tell(cell.owner, "THE FLOOD HAS WASHED AWAY A " .. D.IMPROVEMENT[cell.improvement].name) end
        cell.improvement = nil
    end
    if cell.terrain == "desert" then cell.terrain = "plains" end
    game:emit({ kind = "terrain", cell = cell.id })
end

-- How big the river along a hex is, at its biggest: 0 off one.
local function riverSize(game, cell)
    if not game:onRiver(cell) then return 0 end
    local size = 0
    for k = 0, 5 do
        local e = cell.river[k]
        if e then size = max(size, e.size or 1) end
    end
    return size
end

local function floods(game, stage)
    local FL = D.FLOOD
    local lying = {}
    for _, cell in ipairs(game.cells) do if cell.flood then lying[#lying + 1] = cell end end
    for _, cell in ipairs(lying) do
        for _, u in ipairs(Cat.unitsOn(game, cell)) do
            if not u.def.sea then Cat.hurt(game, u, FL.floodDamage, "WAS SWEPT AWAY BY THE FLOOD") end
        end
        for _, n in ipairs(game:neighbours(cell)) do
            if n.city then
                if not n.city.buildings.levee then Cat.harm(game, n.city, FL.cityFlood) end
            elseif F.floodable(game, n) and n.top <= cell.top then
                -- Down the river, or out over the low land beside it.
                local chance = (game:riverBetween(cell, n) or (game:onRiver(cell) and game:onRiver(n)))
                    and FL.spreadRiver or FL.spreadLand
                if game.rng:random() < chance * hold(n) then F.inundate(game, n) end
            end
        end
        cell.flood = cell.flood - 1
        if cell.flood <= 0 then recede(game, cell) end
    end
    -- New floods, where the rivers run: the big rivers most.
    local n = FL.burst[stage] or 0
    if n > 0 then
        local starts = Cat.pick(game, function(cell)
            if not F.floodable(game, cell) then return 0 end
            local size = riverSize(game, cell)
            if size == 0 then return 0 end
            return size * size * hold(cell)
        end, n)
        for _, cell in ipairs(starts) do F.inundate(game, cell) end
    end
end

--- the sea -------------------------------------------------------------------------------

-- Can the sea take this hex: flat land by the sea, not a city's own hex,
-- nor a levee's.
function F.shore(game, cell)
    if not land(game, cell) or cell.elev ~= "flat" or cell.city or cell.lair or levee(cell) then return false end
    for _, n in ipairs(game:neighbours(cell)) do
        if game:isWater(n) then return true end
    end
    return false
end

-- Unit u, on a hex the sea has taken: rowing, if it can be on the water;
-- else to the nearest dry land, if there is any; else lost.
local function strand(game, u, cell)
    if game:canEnter(u, cell) then return end
    local to = game:freeNear(cell.id, u.def.civilian)
    if to then
        game:slot(u)[cell.id] = nil
        game:slot(u)[to] = u
        u.cell = to
        u.trail = { to }
        game:emit({ kind = "terrain", cell = to })
        return
    end
    Cat.hurt(game, u, u.hp, "WAS LOST TO THE SEA")
end

-- The sea takes a hex, for good: it is coast now, whatever was on it gone,
-- its trees left standing dead in the water.
function F.drown(game, cell)
    local what = game:describe(cell)
    cell.terrain = "coast"
    cell.top = D.TERRAIN.coast.top
    cell.drowned = true
    if cell.feature == "forest" then cell.drownedForest = true end
    cell.feature, cell.improvement, cell.flood, cell.silt = nil, nil, nil, nil
    cell.fire, cell.burnt, cell.burntForest, cell.scorched = nil, nil, nil, nil
    if cell.resource ~= "fish" then cell.resource = nil end
    if cell.workedBy then cell.workedBy = nil end
    for _, u in ipairs(Cat.unitsOn(game, cell)) do strand(game, u, cell) end
    if cell.owner then game:tell(cell.owner, "THE SEA HAS TAKEN THE " .. what) end
    game:emit({ kind = "terrain", cell = cell.id })
    -- The water beside it meets new land: its shore is drawn again.
    for _, n in ipairs(game:neighbours(cell)) do
        if game:isWater(n) then game:emit({ kind = "terrain", cell = n.id }) end
    end
end

local function rise(game)
    local FL = D.FLOOD
    local list = {}
    for _, cell in ipairs(game.cells) do
        if F.shore(game, cell) then list[#list + 1] = cell end
    end
    -- Lowest first: the n-th lowest `low`^n as likely as the lowest.
    table.sort(list, function(a, b)
        if a.e ~= b.e then return (a.e or 0) < (b.e or 0) end
        return a.id < b.id
    end)
    local weight = {}
    for k, cell in ipairs(list) do weight[cell.id] = FL.low ^ (k - 1) * (cell.terrain == "marsh" and 2 or 1) end
    for _, cell in ipairs(Cat.pick(game, function(cell) return weight[cell.id] or 0 end, FL.rise, list)) do
        F.drown(game, cell)
    end
    -- The surge, on every city by the shore that has no levee.
    for _, c in ipairs(game.cities) do
        local cell = game.cells[c.cell]
        if not c.buildings.levee and cell.elev == "flat" and game:coastal(cell) then Cat.harm(game, c, FL.surge) end
    end
end

--- the turn --------------------------------------------------------------------------------

F.tell = {
    omen = function() return ("THE RAINS WILL NOT STOP. THE LONG RAINS COME IN %d TURNS"):format(D.FLOOD.rains - D.FLOOD.omen) end,
    rains = function() return "THE LONG RAINS: THE LAND GROWS RICH, AND THE LOWLANDS SODDEN. BUILD LEVEES" end,
    floods = function() return "THE FLOODS: THE RIVERS HAVE BURST THEIR BANKS" end,
    sea = function() return ("THE RISING SEA: THE COASTS DROWN. THE WORLD ENDS IN %d TURNS"):format(D.LAST_TURN - D.FLOOD.sea + 1) end,
}

function F.play(game, stage)
    if Cat.past(game, "floods") then floods(game, stage) end
    if stage == "sea" then rise(game) end
    for _, cell in ipairs(Cat.pick(game, function(cell) return wetWeight(game, cell) end, D.FLOOD.wet[stage] or 0)) do
        F.wetten(game, cell)
    end
end

return F
