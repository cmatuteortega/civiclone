-- The still sun: the world ends with the sun standing still in the sky. One
-- of the cataclysm's kinds (src/cataclysm.lua), on the same turns as the
-- others, by D.SUN's:
--
--   OMEN       the days grow long: every turn the sun crosses less of the
--              sky (src/ui/daylight.lua), until it is noon and it stops.
--   STILL      the sun stands still. A line is drawn across the world, a
--              new one every game, at any slant and through any part of the
--              land: on one side of it it is day for good, on the other
--              night, and a band of twilight lies along it. Nobody knows
--              before where it will fall, nor which side they will be on.
--              The day side dries a few hexes a turn, as the heat's land
--              does (grass to plains to desert), deepest in the day first;
--              the night side freezes as many (to tundra, then snow,
--              src/frost.lua). Farms off a river in the day, and every farm
--              in the night, yield less.
--   SEAR       the day burns: fires start in its forests and fields and
--              spread; and the night freezes the sea, the shallows from the
--              shore out, to ice that can be walked on and not sailed. The
--              cities thirst in the day and go cold in the night.
--   TWILIGHT   the band narrows. The day's deserts bake hard; the open sea
--              freezes too. Whoever ends a turn out on the baked earth or
--              the snow is hurt. The thirst and the cold worsen.
--
-- The twilight is the one place that is spared: what is there neither
-- dries nor freezes, and its cities neither thirst nor go cold. As the band
-- narrows, what was twilight falls to one side or the other.
--
-- What holds it off: a cistern on the day side (its land dries slower, its
-- farms keep their food, its people thirst less), a hearth on the night
-- side (its land freezes slower, its farms keep their food, its people go
-- less cold), and a shelter (D.SHELTER) on either.
--
-- game.cataclysm keeps `line` once the sun has stood still: { nx, nz } the
-- way to the day across the map (in room units), `d` how far along that
-- way the line lies, `w` a hex's width (src/defs.lua, D.sunSide). The cells
-- keep what the heat and the frost leave on them. The game emits "terrain"
-- for every hex that changes, "ignite" for every fire that starts,
-- "freeze" for every hex of sea that freezes, and "sun" as each stage
-- begins. Nothing here draws.

local D = require "src.defs"
local H = require "src.hex"
local Cat = require "src.cataclysm"
local Frost = require "src.frost"
local Rng = require "src.rng"

local max, min, floor, cos, sin, pi = math.max, math.min, math.floor, math.cos, math.sin, math.pi

local Sun = {
    stages = { "omen", "still", "sear", "twilight" },
    names = { omen = "THE OMEN", still = "THE SUN STANDS STILL", sear = "THE SEARING AND THE FROST",
        twilight = "THE LAST TWILIGHT" },
    words = { omen = "OMEN", still = "STILL SUN", sear = "SEAR & FROST", twilight = "TWILIGHT" },
    turns = D.SUN, event = "sun", ward = "hearth", ended = "THE SUN HAS STOOD STILL FOREVER",
}

--- the line ------------------------------------------------------------------------------

-- The line, once the sun has stood still in game `game`; nil before, or in
-- another cataclysm.
function Sun.line(game)
    local c = game.cataclysm
    return c and c.kind == "sun" and c.line or nil
end

-- How far into the day hex `cell` is, in hexes (below 0: into the night),
-- or nil before the sun has stood still.
function Sun.side(game, cell)
    return D.sunSide(game, cell.x, cell.z)
end

-- How far the twilight reaches either side of the line now, in hexes.
function Sun.band(game)
    local s = Cat.stage(game)
    return s and D.SUN.band[s] or D.SUN.band.still
end

-- Where hex `cell` lies: "day", "night" or "twilight", or nil before the sun
-- has stood still.
function Sun.zone(game, cell)
    local s = Sun.side(game, cell)
    if not s then return nil end
    local b = Sun.band(game)
    if s > b then return "day" end
    if s < -b then return "night" end
    return "twilight"
end

-- How deep into its side hex `cell` is, past the twilight, in hexes (0 in
-- the twilight or before the sun stands still).
function Sun.depth(game, cell)
    local s = Sun.side(game, cell)
    if not s then return 0 end
    return max(0, math.abs(s) - Sun.band(game))
end

-- Draws the line: any way across the map, through the land somewhere
-- between D.SUN.from and D.SUN.to of its breadth that way. Which side is
-- day is part of the way it points.
function Sun.place(game)
    -- Dice of its own, mixed from the game's: the game's own first throws
    -- run too near alike from one seed to the next.
    local h = math.sin(game.rng:random() * 98765.4321 + (game.seed or 0) * 12.9898 + game.turn * 78.233) * 43758.5453
    local r = Rng.new(floor((h - floor(h)) * 2147483646))
    for _ = 1, 3 do r:random() end
    local a = r:random() * 2 * pi
    local nx, nz = cos(a), sin(a)
    local along = {}
    for _, cell in ipairs(game.cells) do
        if not game:isWater(cell) then along[#along + 1] = cell.x * nx + cell.z * nz end
    end
    table.sort(along)
    local f = D.SUN.from + r:random() * (D.SUN.to - D.SUN.from)
    local d = #along > 0 and along[max(1, min(#along, floor(f * #along + 0.5)))] or 0
    game.cataclysm.line = { nx = nx, nz = nz, d = d, w = H.W }
    return game.cataclysm.line
end

--- what it does to what the land yields ----------------------------------------------------

local function cistern(cell) return Cat.warded(cell, "cistern") end

-- Food on hex `cell`, `f` before the sun has its say: ice yields nothing,
-- and a farm loses food off a river in the day (unless a cistern waters
-- it), or anywhere in the night (unless a hearth warms it).
function Sun.food(game, cell, f)
    if cell.terrain == "ice" then return 0 end
    if cell.improvement == "farm" then
        local z = Sun.zone(game, cell)
        if (z == "day" and not game:onRiver(cell) and not cistern(cell)) or (z == "night" and not Frost.warm(cell)) then
            f = max(0, f - D.SUN.farm)
        end
    end
    return f
end

-- The food city `city` loses this turn: to thirst in the day, to the cold in
-- the night, a cistern or a hearth sparing it some. Nothing in the
-- twilight.
function Sun.thirst(game, city)
    local s = Cat.stage(game)
    local z = Sun.zone(game, game.cells[city.cell])
    if not s or not z or z == "twilight" then return 0 end
    local t, ward
    if z == "day" then t, ward = D.SUN.thirst[s] or 0, city.buildings.cistern
    else t, ward = D.SUN.cold[s] or 0, city.buildings.hearth end
    if t > 0 and ward then t = max(0, t - D.SUN.ward) end
    return t
end

-- The ward a city wants against it: a cistern in the day, a hearth in the
-- night, none in the twilight (nor before anyone knows which).
function Sun.wardFor(game, city)
    local z = Sun.zone(game, game.cells[city.cell])
    if z == "day" then return "cistern" end
    if z == "night" then return "hearth" end
end

-- Is hex `cell` a place unit u is hurt for ending a turn on?
function Sun.danger(game, cell, u)
    if u.def.sea then return cell.terrain == "ice" end
    if cell.city or not Cat.past(game, "twilight") then return false end
    local z = Sun.zone(game, cell)
    if z == "day" then return cell.scorched == true and not game:onRiver(cell) end
    if z == "night" then return cell.terrain == "snow" end
    return false
end

-- What the screen says of where the hex lies.
function Sun.describe(game, cell)
    local z = Sun.zone(game, cell)
    return z and ({ day = "- ENDLESS DAY", night = "- ENDLESS NIGHT", twilight = "- TWILIGHT" })[z]
end

--- the day -------------------------------------------------------------------------------

-- How likely hex `cell` is to dry a step this turn, against the others: the
-- deeper in the day the likelier, and less by a river, the coast, on hills
-- and a cistern's land. With `bake`, only the desert, to bake hard.
local function dryWeight(game, cell, bake)
    if game:isWater(cell) or cell.elev == "mountain" or cell.feature == "forest" or cell.fire or cell.scorched then
        return 0
    end
    if (cell.terrain == "desert") ~= (bake == true) then return 0 end
    if Frost.frozen(cell) and not bake then
        -- What froze before the line was drawn thaws first, to bare plains.
        if Sun.zone(game, cell) ~= "day" then return 0 end
    end
    local depth = Sun.zone(game, cell) == "day" and Sun.depth(game, cell) or 0
    if depth <= 0 then return 0 end
    local w = min(depth, D.SUN.deep) / D.SUN.deep
    local HT = D.HEAT
    if Cat.hot(game, cell) then w = w * 3 end
    if game:onRiver(cell) then w = w * HT.river end
    if game:coastal(cell) then w = w * HT.coast end
    if cell.elev == "hills" then w = w * HT.hills end
    if cistern(cell) then w = w * HT.cistern end
    return w
end

local function dry(game, cell)
    if Frost.frozen(cell) then
        cell.terrain = "plains"
        game:emit({ kind = "terrain", cell = cell.id })
    else
        Cat.dry(game, cell)
    end
end

-- New fires in the day, deepest in it likeliest, forests most.
local function ignite(game, n)
    local starts = Cat.pick(game, function(cell)
        if not Cat.flammable(game, cell) or Sun.zone(game, cell) ~= "day" then return 0 end
        local w = min(Sun.depth(game, cell), D.SUN.deep) / D.SUN.deep
        if cistern(cell) then w = w * D.HEAT.cisternFire end
        return (cell.feature == "forest" and 4 or 1) * w
    end, n)
    for _, cell in ipairs(starts) do Cat.ignite(game, cell) end
end

--- the night -----------------------------------------------------------------------------

local function frostWeight(game, cell)
    if not Frost.chillable(game, cell) or Sun.zone(game, cell) ~= "night" then return 0 end
    local w = min(Sun.depth(game, cell), D.SUN.deep) / D.SUN.deep
    if w <= 0 then return 0 end
    return Frost.hold(game, cell, w, D.SUN)
end

local function freezeWeight(game, cell, open)
    if Sun.zone(game, cell) ~= "night" or not Frost.freezable(game, cell, open) then return 0 end
    return 0.2 + min(Sun.depth(game, cell), D.SUN.deep) / D.SUN.deep
end

--- the turn ------------------------------------------------------------------------------

Sun.tell = {
    omen = function() return ("THE DAYS GROW LONG: THE SUN IS SLOWING. IT WILL STAND STILL IN %d TURNS"):format(
        D.SUN.still - D.SUN.omen) end,
    still = function() return "THE SUN STANDS STILL: ONE SIDE OF THE WORLD IN ENDLESS DAY, ONE IN ENDLESS NIGHT" end,
    sear = function() return "THE SEARING AND THE FROST: THE DAY BURNS, AND THE NIGHT FREEZES THE SEA" end,
    twilight = function() return ("THE LAST TWILIGHT: THE BAND NARROWS. THE WORLD ENDS IN %d TURNS"):format(
        D.LAST_TURN - D.SUN.twilight + 1) end,
}

-- Tells every civilization where its cities lie, as the sun stops.
local function tellSides(game)
    for _, p in ipairs(game.players) do
        if p.alive then
            local n = { day = 0, night = 0, twilight = 0 }
            for _, c in ipairs(game:citiesOf(p.id)) do
                local z = Sun.zone(game, game.cells[c.cell])
                n[z] = n[z] + 1
            end
            if n.day + n.night + n.twilight > 0 then
                local parts = {}
                if n.day > 0 then parts[#parts + 1] = n.day .. " IN THE DAY (BUILD CISTERNS)" end
                if n.night > 0 then parts[#parts + 1] = n.night .. " IN THE NIGHT (BUILD HEARTHS)" end
                if n.twilight > 0 then parts[#parts + 1] = n.twilight .. " IN THE TWILIGHT" end
                game:tell(p.id, "OF OUR CITIES " .. table.concat(parts, ", "))
            end
        end
    end
end

function Sun.play(game, stage)
    local c = game.cataclysm
    if not c.line then
        Sun.place(game)
        game:emit({ kind = "sunline" })
        tellSides(game)
    end
    local S = D.SUN
    -- The fires burn on and spread, as the heat's do, and new ones start.
    Cat.fires(game, stage)
    if (S.ignite[stage] or 0) > 0 then ignite(game, S.ignite[stage]) end
    -- The ice closes on what sails; in the twilight the far sides kill.
    Frost.crush(game, S.crush)
    if stage == "twilight" then
        Frost.bite(game, S.frostbite, function(cell) return Sun.zone(game, cell) == "night" end)
        for _, cell in ipairs(game.cells) do
            if cell.scorched and not cell.city and not game:onRiver(cell) and Sun.zone(game, cell) == "day" then
                for _, u in ipairs(Cat.unitsOn(game, cell)) do
                    if not u.def.sea then Cat.hurt(game, u, S.scorchDamage, "DIED OF THE HEAT") end
                end
            end
        end
    end
    -- The day dries the land, and in the twilight bakes its deserts.
    for _, cell in ipairs(Cat.pick(game, function(cell) return dryWeight(game, cell, false) end, S.dry[stage] or 0)) do
        dry(game, cell)
    end
    if stage == "twilight" then
        for _, cell in ipairs(Cat.pick(game, function(cell) return dryWeight(game, cell, true) end, S.bake)) do
            Cat.dry(game, cell)
        end
    end
    -- The night freezes it, and the sea.
    for _, cell in ipairs(Cat.pick(game, function(cell) return frostWeight(game, cell) end, S.frost[stage] or 0)) do
        Frost.chill(game, cell)
    end
    local open = stage == "twilight"
    for _, cell in ipairs(Cat.pick(game, function(cell) return freezeWeight(game, cell, open) end, S.freeze[stage] or 0)) do
        Frost.freeze(game, cell)
    end
end

return Sun
