-- The sky falls: the world ends in stones and then in darkness. One of the
-- cataclysm's kinds (src/cataclysm.lua), on the same turns as the others, by
-- D.SKY's:
--
--   OMEN       a comet is seen, its tail longer every turn. The turn before
--              the starfall, the first stones are seen coming.
--   STARFALL   small stones fall, a few a turn. Each is seen coming: its hex
--              is marked the turn before it falls, so what stands there can
--              get out of the way. Where one falls it hurts what is there,
--              may set the forest beside it alight, and leaves a crater: the
--              hex sunk lower, its farm or mine gone, its trees flattened,
--              hills flattened and mountains broken. A crater yields less
--              food, none while it is still hot, and some hold star iron.
--   BOMBARD    more stones, and big ones: deeper craters, a blow to what is
--              beside them, people killed in a city struck. The dust starts
--              to hide the sun, and the cities go cold and hungry.
--   DARK       the long night: the sun is never seen again. Every farm
--              yields less and the cold worsens; stones still fall. On
--              D.SKY.heart the heart of the comet falls, told some turns
--              before: on a hex and the six round it, sinking them deep.
--
-- It is the one cataclysm that is seen coming hex by hex: the others creep
-- over the land, and this one strikes where it has said it will. What holds
-- it off is the shelter (D.SHELTER): a city that has dug one takes half the
-- blow, loses none of its people to a stone, and its stores hold off the
-- cold.
--
-- The cells keep what has happened to them: `crater` (how many stones have
-- fallen on it), `sunk` (how far it has gone down), `glow` (turns its
-- crater is still hot). game.cataclysm keeps `marks` ({ [cell id] = "small"
-- | "big" }, where stones fall as the next turn begins) and `heart` (the
-- cell id the heart falls on, once it is told). The game emits "terrain"
-- for every hex that changes, "impact" for every stone that falls (with
-- `cell`, `size` "small" | "big" | "heart", `water` and `turn`), "mark"
-- when new marks are laid, and "sky" as each stage begins. Nothing here
-- draws.

local D = require "src.defs"
local Cat = require "src.cataclysm"

local max, min, floor = math.max, math.min, math.floor

local Sky = {
    stages = { "omen", "starfall", "bombard", "dark" },
    names = { omen = "THE OMEN", starfall = "THE STARFALL", bombard = "THE BOMBARDMENT", dark = "THE LONG NIGHT" },
    words = { omen = "OMEN", starfall = "STARFALL", bombard = "BOMBARDMENT", dark = "LONG NIGHT" },
    turns = D.SKY, event = "sky", ward = "shelter", ended = "THE SKY HAS FALLEN",
    -- It marks where its first stones fall in the omen's last turn.
    early = true,
}

local function land(game, cell) return not game:isWater(cell) end

--- what it does to what the land yields -------------------------------------------------

-- Food on hex `cell`, `f` before the sky has its say: a crater yields less
-- (nothing while it is hot), and in the long night the farms fail.
function Sky.food(game, cell, f)
    if cell.glow then return 0 end
    if cell.crater then f = max(0, f - D.SKY.craterFood) end
    if cell.improvement == "farm" and Cat.past(game, "dark") then f = max(0, f - D.SKY.darkFarm) end
    return f
end

-- The food city `city` loses this turn to the cold; its shelter's stores
-- spare it some.
function Sky.thirst(game, city)
    local s = Cat.stage(game)
    local t = s and D.SKY.cold[s] or 0
    if t > 0 and Cat.sheltered(city) then t = max(0, t - D.SHELTER.skyStores) end
    return t
end

--- where the stones fall ------------------------------------------------------------------

-- What is coming down on hex `cell`: "small" or "big" (a stone, as the next
-- turn begins), "heart" (it is under the heart of the comet), or nil.
function Sky.marked(game, cell)
    local c = game.cataclysm
    if not c or c.kind ~= "sky" then return nil end
    if c.heart and game.turn < D.SKY.heart then
        local h = game.cells[c.heart]
        if game:dist(h, cell) <= 1 then return "heart" end
    end
    return c.marks and c.marks[cell.id] or nil
end

-- The heart's hex, while it is still to fall, and how many turns to it.
function Sky.heart(game)
    local c = game.cataclysm
    if not c or c.kind ~= "sky" or not c.heart or game.turn >= D.SKY.heart then return nil end
    return game.cells[c.heart], D.SKY.heart - game.turn
end

-- Lays the marks of the stones that fall as the next turn begins, in the
-- stage that turn is in.
local function mark(game)
    local c = game.cataclysm
    c.marks = {}
    local next = game.turn + 1
    if next > D.LAST_TURN then return end
    local stage = Cat.stageAt(next, "sky")
    local n = stage and D.SKY.fall[stage] or 0
    if n <= 0 then return end
    local heart = c.heart and game.turn < D.SKY.heart and game.cells[c.heart]
    local picked = Cat.pick(game, function(cell)
        if heart and game:dist(heart, cell) <= 1 then return 0 end
        return land(game, cell) and D.SKY.land or 1
    end, n)
    local big = D.SKY.big[stage] or 0
    for _, cell in ipairs(picked) do
        c.marks[cell.id] = game.rng:random() < big and "big" or "small"
        if cell.owner then
            local what = c.marks[cell.id] == "big" and "A GREAT STONE" or "A STONE"
            game:tell(cell.owner, what .. " IS FALLING ON THE " .. game:describe(cell))
        end
    end
    game:emit({ kind = "mark" })
end

--- craters ----------------------------------------------------------------------------------

-- The lowest hex `cell` may sink to: the floor, and above the water of any
-- river along it.
local function lowest(cell)
    local low = D.SKY.floor
    if cell.river then
        for k = 0, 5 do
            local e = cell.river[k]
            if e and e.level then low = max(low, e.level + 0.6) end
        end
    end
    return low
end

-- A stone's crater on land hex `cell`, sinking it `depth`: a mountain broken
-- to hills, hills flattened, flat land sunk; the forest, the farm or the
-- mine, the grain gone; star iron in it, sometimes. A city's own hex keeps
-- its ground (the stone breaks on its roofs).
function Sky.crater(game, cell, depth)
    if cell.city then return end
    local before = cell.top
    if cell.elev == "mountain" then
        cell.elev = "hills"
        cell.top = cell.top - (D.ELEV.mountain.rise - D.ELEV.hills.rise)
    elseif cell.elev == "hills" then
        cell.elev = "flat"
        cell.top = cell.top - D.ELEV.hills.rise
    else
        cell.top = cell.top - depth
    end
    cell.top = max(min(lowest(cell), before), cell.top)
    cell.sunk = (cell.sunk or 0) + (before - cell.top)
    cell.crater = (cell.crater or 0) + 1
    cell.glow = D.SKY.glow
    if cell.improvement then
        if cell.owner then game:tell(cell.owner, "A " .. D.IMPROVEMENT[cell.improvement].name .. " HAS BEEN STRUCK FROM THE SKY") end
        cell.improvement = nil
    end
    if cell.feature == "forest" then
        cell.feature = nil
        cell.burntForest = true
    end
    cell.fire, cell.flood = nil, nil
    if cell.resource == "wheat" then cell.resource = nil end
    if not cell.resource and game.rng:random() < D.SKY.iron then cell.resource = "iron" end
    game:emit({ kind = "terrain", cell = cell.id })
end

-- Sets the forests round hex `cell` alight, each by `chance`.
local function kindle(game, cell, chance, reach)
    for _, n in ipairs(game:within(cell, reach or 1)) do
        if n ~= cell and n.feature == "forest" and Cat.flammable(game, n) and game.rng:random() < chance then
            Cat.ignite(game, n)
        end
    end
end

-- What a stone does to the units on hex `cell`: `amount` each, ships and
-- boats too.
local function strikeUnits(game, cell, amount)
    for _, u in ipairs(Cat.unitsOn(game, cell)) do Cat.hurt(game, u, amount, "WAS STRUCK FROM THE SKY") end
end

-- A city struck: the blow (halved by a shelter), and `pop` of its people
-- killed (none in a shelter), never the last.
local function strikeCity(game, city, amount, pop)
    Cat.harm(game, city, amount)
    if pop > 0 and not Cat.sheltered(city) and city.pop > 1 then
        city.pop = max(1, city.pop - pop)
        game:assignWork(city)
        game:tell(city.owner, city.name .. " HAS BEEN STRUCK FROM THE SKY: ITS PEOPLE DIE")
    else
        game:tell(city.owner, city.name .. " HAS BEEN STRUCK FROM THE SKY")
    end
end

-- A stone falls on hex `cell`: "small" or "big".
function Sky.strike(game, cell, size)
    local S = D.SKY
    local water = game:isWater(cell)
    game:emit({ kind = "impact", cell = cell.id, size = size, water = water, turn = game.turn })
    strikeUnits(game, cell, S.hit[size])
    if cell.city then strikeCity(game, cell.city, S.city[size], size == "big" and S.pop or 0) end
    if not water then Sky.crater(game, cell, S.sink[size]) end
    if size == "big" then
        for _, n in ipairs(game:neighbours(cell)) do
            strikeUnits(game, n, S.near)
            if n.city then Cat.harm(game, n.city, S.nearCity) end
        end
    end
    if not water then kindle(game, cell, S.burn * (size == "big" and 1 or 0.5)) end
end

-- The heart of the comet falls on hex `cell` and the six round it.
function Sky.heartfall(game, cell)
    local S = D.SKY
    game:emit({ kind = "impact", cell = cell.id, size = "heart", water = game:isWater(cell), turn = game.turn })
    game:tell(nil, "THE HEART OF THE COMET HAS FALLEN")
    for _, n in ipairs(game:within(cell, 2)) do
        local d = game:dist(cell, n)
        strikeUnits(game, n, d == 0 and S.heartHit or d == 1 and S.ringHit or S.shock)
        if n.city then
            local c = n.city
            if d == 0 then
                local lost = Cat.sheltered(c) and floor(c.pop * S.heartPop * 0.5) or floor(c.pop * S.heartPop + 0.5)
                c.pop = max(1, c.pop - lost)
                game:assignWork(c)
                Cat.harm(game, c, c.hp)
                game:tell(c.owner, c.name .. " LIES UNDER THE HEART OF THE COMET")
            elseif d == 1 then
                strikeCity(game, c, S.ringCity, S.pop)
            else
                Cat.harm(game, c, S.nearCity)
            end
        end
        if d <= 1 and not game:isWater(n) then Sky.crater(game, n, d == 0 and S.heartSink or S.ringSink) end
    end
    kindle(game, cell, S.burn, 3)
end

-- Picks the hex the heart falls on: land, where people live most.
local function aim(game)
    local list = Cat.pick(game, function(cell)
        if not land(game, cell) then return 0 end
        local w = 1
        for _, c in ipairs(game.cities) do
            local d = game:dist(cell, game.cells[c.cell])
            if d >= 1 and d <= 3 then w = w + 2 end
        end
        return w
    end, 1)
    return list[1]
end

--- the turn ----------------------------------------------------------------------------------

Sky.tell = {
    omen = function() return ("A COMET HAS BEEN SEEN IN THE SKY. THE STARFALL COMES IN %d TURNS"):format(D.SKY.starfall - D.SKY.omen) end,
    starfall = function() return "THE STARFALL: STONES FALL FROM THE SKY WHERE THEY ARE SEEN COMING. DIG SHELTERS" end,
    bombard = function() return "THE BOMBARDMENT: GREAT STONES FALL, AND THE DUST HIDES THE SUN" end,
    dark = function() return ("THE LONG NIGHT: THE SUN IS GONE. THE WORLD ENDS IN %d TURNS"):format(D.LAST_TURN - D.SKY.dark + 1) end,
}

function Sky.play(game, stage)
    local c = game.cataclysm
    -- The fires the stones lit burn on.
    if stage ~= "omen" then Cat.fires(game, stage) end
    for _, cell in ipairs(game.cells) do
        if cell.glow then
            cell.glow = cell.glow - 1
            if cell.glow <= 0 then
                cell.glow = nil
                game:emit({ kind = "terrain", cell = cell.id })
            end
        end
    end
    -- What was seen coming falls.
    local due = {}
    for id, size in pairs(c.marks or {}) do due[#due + 1] = { id, size } end
    table.sort(due, function(a, b) return a[1] < b[1] end)
    c.marks = {}
    for _, m in ipairs(due) do Sky.strike(game, game.cells[m[1]], m[2]) end
    if game.turn == D.SKY.heartWarn and not c.heart then
        local cell = aim(game)
        if cell then
            c.heart = cell.id
            game:tell(nil, ("THE HEART OF THE COMET WILL FALL ON THE %s IN %d TURNS"):format(game:describe(cell),
                D.SKY.heart - game.turn))
            game:emit({ kind = "mark", heart = cell.id })
        end
    end
    if game.turn == D.SKY.heart and c.heart then Sky.heartfall(game, game.cells[c.heart]) end
    -- And the next turn's are seen coming.
    if game.turn + 1 >= D.SKY.starfall then mark(game) end
end

return Sky
