-- Loyalty: how much a city's people hold to the civilization that has them,
-- from 0 to 100 (D.LOYALTY).
--
-- A city's people are pulled by the cities near it: by their own
-- civilization's, its own people counted with them, and by a foreigner's.
-- An ally's pull nothing either way. The capital steadies it, nearby or in
-- the city itself, and so do soldiers in the town; hunger, an enemy at the
-- gates, being newly conquered and the dread of the end wear it away, and a
-- ward against the end gives people hope.
--
-- Under D.LOYALTY.unrest the city is in unrest, and makes a quarter less of
-- everything but its food; under D.LOYALTY.uprising, in uprising, half.
-- At nothing it goes over to the civilization pulling hardest on it, if
-- one is: a city wishing to be the player's asks first (a letter, through
-- src/diplomacy.lua), and is the computer's at once.
--
-- No LÖVE here: the tests play it.

local D = require "src.defs"
local Cat = require "src.cataclysm"
local Diplo = require "src.diplomacy"

local floor, max, min = math.floor, math.max, math.min

local Loyalty = {}

function Loyalty.of(city) return city.loyalty or 100 end

-- Each civilization's pull on the city, by owner: its cities' people
-- within D.LOYALTY.radius, the nearer the more.
local function pulls(game, city)
    local R = D.LOYALTY.radius
    local here = game.cells[city.cell]
    local by = {}
    for _, c in ipairs(game.cities) do
        local d = game:dist(here, game.cells[c.cell])
        if d <= R then
            by[c.owner] = (by[c.owner] or 0) + c.pop * (1 - d / (R + 1))
        end
    end
    return by
end

-- The foreign civilization pulling hardest on the city, and how hard; an
-- ally's not at all.
function Loyalty.strongest(game, city)
    local best, bv
    for owner, v in pairs(pulls(game, city)) do
        if owner ~= city.owner and owner ~= game.WILD and not Diplo.allied(game, owner, city.owner)
            and v > 0 and (not bv or v > bv) then
            best, bv = owner, v
        end
    end
    return best, bv
end

-- What moves the city's loyalty this turn: the change, and its parts
-- { { words, n } }.
function Loyalty.parts(game, city)
    local Y = D.LOYALTY
    local parts = {}
    local function add(words, n)
        if n ~= 0 then parts[#parts + 1] = { words, n } end
    end
    local own, foreign = 0, 0
    for owner, v in pairs(pulls(game, city)) do
        if owner == city.owner then own = own + v
        elseif not Diplo.allied(game, owner, city.owner) then foreign = foreign + v end
    end
    local pull = floor((own - foreign) * Y.pull * 10 + 0.5) / 10
    pull = max(Y.least, min(Y.most, pull))
    if pull > 0 then add("OUR PEOPLE NEARBY", pull)
    elseif pull < 0 then add("FOREIGN CITIES NEARBY", pull) end
    local home = game.cells[city.cell]
    if city.capital and city.owner == city.founder then
        add("THE CAPITAL", Y.capital)
    else
        for _, c in ipairs(game:citiesOf(city.owner)) do
            if c.capital and c.founder == city.owner and game:dist(home, game.cells[c.cell]) <= Y.capitalReach then
                add("NEAR THE CAPITAL", Y.nearCapital)
                break
            end
        end
    end
    local m = game.mil[city.cell]
    if m and m.owner == city.owner then add("A GARRISON", Y.garrison) end
    if city.taken and game.turn - city.taken < Y.occupiedTurns then add("NEWLY CONQUERED", Y.occupied) end
    local f = game:cityYield(city)
    if f < city.pop * 2 then add("HUNGER", Y.starving) end
    for _, n in ipairs(game:within(home, 2)) do
        local u = game.mil[n.id]
        if u and u.owner ~= city.owner and u.owner ~= game.WILD and Diplo.atWar(game, u.owner, city.owner) then
            add("THE ENEMY AT THE GATES", Y.gates)
            break
        end
    end
    if city.sick then add("THE PLAGUE", Y.sick) end
    if Cat.stage(game) then
        local warded = false
        for b in pairs(city.buildings) do
            if game:wardsOff(D.BUILDINGS[b]) then warded = true break end
        end
        if warded then add("THE WARD GIVES HOPE", Y.ward) else add("DREAD OF THE END", Y.dread) end
    end
    local total = 0
    for _, p in ipairs(parts) do total = total + p[2] end
    return total, parts
end

-- "UNREST", "UPRISING", or nil while the city is content.
function Loyalty.state(city)
    local v = Loyalty.of(city)
    if v < D.LOYALTY.uprising then return "UPRISING" end
    if v < D.LOYALTY.unrest then return "UNREST" end
end

-- What the city makes of all but food, for its loyalty.
function Loyalty.factor(city)
    local s = Loyalty.state(city)
    if s == "UPRISING" then return 0.5 end
    if s == "UNREST" then return 0.75 end
    return 1
end

-- The end of the owner's turn for the city: its loyalty moves, and at
-- nothing it may go over.
function Loyalty.turn(game, city)
    local was = Loyalty.of(city)
    local delta = Loyalty.parts(game, city)
    local now = max(0, min(100, was + delta))
    city.loyalty = now
    local Y = D.LOYALTY
    if was >= Y.unrest and now < Y.unrest then
        game:tell(city.owner, "{1} IS IN UNREST", city.name)
    elseif was >= Y.uprising and now < Y.uprising then
        game:tell(city.owner, "{1} IS IN UPRISING", city.name)
    end
    if now > 0 or city.pleading then return end
    local to = Loyalty.strongest(game, city)
    if not to then return end
    if game.players[to].human then
        local l = Diplo.send(game, city.owner, to, "defect", { city = city.name, id = city.id })
        if l then city.pleading = l.id end
    else
        game:cede(city, to)
    end
end

return Loyalty
