-- The cataclysm: what ends the world, and the game with it.
--
-- Each game has one, kept as game.cataclysm (nil with Game.new{ cataclysm =
-- false }): its `kind` one of Cat.KINDS. Three are built, the heat death
-- here, the deluge in src/flood.lua and the sky's falling in
-- src/skyfall.lua; the demons are meant to go in KINDS beside them. Every kind has four stages on its
-- turns, an omen first, and the same last turn, D.LAST_TURN: what is here
-- that is not the heat's (the stage, the top bar's label, the last turns'
-- warnings, the dev window's list) asks the kind.
--
-- The heat death, by D.HEAT's turns:
--
--   OMEN     everyone is told what is coming, and when.
--   DROUGHT  the land dries a few hexes a turn, outward from the deserts:
--            grassland to plains, plains to desert (its farm lost). Farms off
--            a river yield less.
--   FIRES    as well, fires start in the forests and fields by the dry land
--            and spread to what is beside them. A hex burns for a few turns,
--            yields nothing, and hurts what stands in it and the cities next
--            to it; it burns out to plains, its trees to stumps.
--   SCORCH   faster still, and the desert bakes hard: baked earth yields no
--            food, and burns whoever ends a turn on it.
--
-- A river, the coast, hills and a city's cistern hold the heat off: the
-- land dries slower there. A cistern's land is slower to catch fire, and
-- its people thirst less. A shelter (D.SHELTER), against any cataclysm,
-- halves the harm the fire beside a city does it, and its stores spare it
-- a little of the thirst.
--
-- The cells keep what has happened to them: `fire` (turns it still burns),
-- `burnt` (it has; `burntForest` if trees stood there), `scorched` (baked
-- desert). The game emits "terrain" for
-- every hex that changes, "ignite" for every fire that starts and "heat"
-- as each stage begins. Nothing here draws.

local D = require "src.defs"

local max = math.max

local Cat = {}
-- The deluge (src/flood.lua) takes this module's helpers as it loads.
package.loaded["src.cataclysm"] = Cat

-- What each kind is: its stages in order, their names, the word the top
-- bar shows for each, its numbers (whose fields are the stages' turns),
-- and the event emitted as each stage begins. The heat's are also kept as
-- Cat.STAGES and Cat.NAMES.
Cat.STAGES = { "omen", "drought", "fires", "scorch" }
Cat.NAMES = { omen = "THE OMEN", drought = "THE GREAT DROUGHT", fires = "THE WILDFIRES", scorch = "THE SCORCH" }
local HEAT = {
    stages = Cat.STAGES, names = Cat.NAMES,
    words = { omen = "OMEN", drought = "DROUGHT", fires = "WILDFIRES", scorch = "SCORCH" },
    turns = D.HEAT, event = "heat", ward = "cistern", ended = "THE WORLD HAS BURNED",
}
Cat.KINDS = { heat = HEAT }

function Cat.new(kind)
    return { kind = kind or "heat" }
end

-- The kind of game's cataclysm (its table in KINDS), or nil.
function Cat.kindOf(game)
    return game.cataclysm and Cat.KINDS[game.cataclysm.kind] or nil
end

local function rank(K, s)
    for k, st in ipairs(K.stages) do if st == s then return k end end
end

-- The stage turn `turn` is in, for cataclysm kind `kind` (the heat by
-- default), or nil before the omen.
function Cat.stageAt(turn, kind)
    local K = Cat.KINDS[kind or "heat"]
    local at
    for _, s in ipairs(K.stages) do if turn >= K.turns[s] then at = s end end
    return at
end

-- The game's stage now, or nil.
function Cat.stage(game)
    if not game.cataclysm then return nil end
    return Cat.stageAt(game.turn, game.cataclysm.kind)
end

-- Has the game reached stage `s` (or one after)? False for a stage of
-- another kind's.
function Cat.past(game, s)
    local K, now = Cat.kindOf(game), Cat.stage(game)
    if not now or not rank(K, s) then return false end
    return rank(K, now) >= rank(K, s)
end

-- Is the game's cataclysm of this kind?
function Cat.is(game, kind)
    return game.cataclysm ~= nil and game.cataclysm.kind == kind
end

-- The name of stage `s` of the game's cataclysm: "THE GREAT DROUGHT".
function Cat.name(game, s)
    local K = Cat.kindOf(game)
    return K and K.names[s]
end

-- Its stages and their turns, in order: { { "omen", 90 }, ... }.
function Cat.stagesOf(game)
    local K, out = Cat.kindOf(game), {}
    if not K then return out end
    for _, s in ipairs(K.stages) do out[#out + 1] = { s, K.turns[s] } end
    return out
end

-- The building that holds it off ("cistern", "levee"), or nil.
function Cat.ward(game)
    local K = Cat.kindOf(game)
    return K and K.ward
end

-- How the end of the world is told, lost.
function Cat.ended(game)
    local K = Cat.kindOf(game)
    return K and K.ended
end

-- How the top bar shows it: "DROUGHT 41", the turns to the end. Nil before
-- the omen.
function Cat.label(game)
    local s = Cat.stage(game)
    if not s then return nil end
    local left = max(0, D.LAST_TURN - game.turn + 1)
    return Cat.kindOf(game).words[s] .. " " .. left
end

--- what holds the heat off --------------------------------------------------------

-- Does the hex belong to a city that has built `building`?
function Cat.warded(cell, building)
    local c = cell.ownerCity
    return c ~= nil and c.buildings ~= nil and c.buildings[building] ~= nil and c.owner == cell.owner
end

local function cool(cell) return Cat.warded(cell, "cistern") end
Cat.cool = cool

-- Does a farm on this cell lose food to the drought?
function Cat.droughtFarm(game, cell)
    return cell.improvement == "farm" and Cat.past(game, "drought") and not game:onRiver(cell) and not cool(cell)
end

-- Has city `city` dug a shelter (D.SHELTER)?
function Cat.sheltered(city)
    return city.buildings ~= nil and city.buildings.shelter ~= nil
end

-- A blow of `amount` HP from the cataclysm on city `city`: halved, if it
-- has a shelter, and never below 1 HP. Answers what it took.
function Cat.harm(game, city, amount)
    if Cat.sheltered(city) then amount = math.floor(amount * D.SHELTER.harm + 0.5) end
    city.hp = max(1, city.hp - amount)
    game:emit({ kind = "hit", cell = city.cell, amount = amount })
    return amount
end

-- The food city `city` loses this turn to thirst (or, in the deluge, to
-- fever; under the falling sky, to the cold). A shelter's stores spare it
-- some.
function Cat.thirst(game, city)
    local K = Cat.kindOf(game)
    local t = 0
    if K and K.thirst then
        t = K.thirst(game, city)
    elseif Cat.is(game, "heat") then
        local s = Cat.stage(game)
        t = s and D.HEAT.thirst[s] or 0
        if t > 0 and city.buildings.cistern then t = max(0, t - D.HEAT.cisternThirst) end
    end
    if t > 0 and Cat.sheltered(city) and not (K and K.ward == "shelter") then t = max(0, t - D.SHELTER.stores) end
    return t
end

--- drying -------------------------------------------------------------------------

local function land(game, cell)
    return not game:isWater(cell) and cell.elev ~= "mountain"
end

local function hot(game, cell)
    for _, n in ipairs(game:neighbours(cell)) do
        if n.terrain == "desert" or n.burnt then return true end
    end
    return false
end
Cat.hot = hot

-- How likely hex `cell` is to dry a step this turn, against the others; 0
-- if it can't. Forests don't dry: they burn. With `bake`, only the desert,
-- to bake hard; without, only the rest.
local function dryWeight(game, cell, bake)
    if not land(game, cell) or cell.feature == "forest" or cell.fire or cell.scorched then return 0 end
    if (cell.terrain == "desert") ~= (bake == true) then return 0 end
    local H = D.HEAT
    local w = 1
    if hot(game, cell) or cell.terrain == "desert" then w = w * H.near end
    if game:onRiver(cell) then w = w * H.river end
    if game:coastal(cell) then w = w * H.coast end
    if cell.elev == "hills" then w = w * H.hills end
    if cool(cell) then w = w * H.cistern end
    return w
end

-- One hex a step drier: grassland to plains, plains to desert, desert baked.
function Cat.dry(game, cell)
    if cell.terrain == "grass" then
        cell.terrain = "plains"
    elseif cell.terrain == "plains" then
        cell.terrain = "desert"
        if cell.improvement == "farm" then
            cell.improvement = nil
            if cell.owner then game:tell(cell.owner, "A FARM HAS TURNED TO DUST") end
        end
        if cell.resource == "wheat" then cell.resource = nil end
    else
        cell.scorched = true
    end
    game:emit({ kind = "terrain", cell = cell.id })
end

-- Picks `n` hexes by weight, without picking one twice.
local function pick(game, weigh, n, cells)
    local list, total = {}, 0
    for _, cell in ipairs(cells or game.cells) do
        local w = weigh(cell)
        if w > 0 then
            list[#list + 1] = { cell = cell, w = w }
            total = total + w
        end
    end
    local out = {}
    for _ = 1, n do
        if total <= 0 then break end
        local r = game.rng:random() * total
        for _, e in ipairs(list) do
            if e.w > 0 then
                r = r - e.w
                if r <= 0 then
                    out[#out + 1] = e.cell
                    total = total - e.w
                    e.w = 0
                    break
                end
            end
        end
    end
    return out
end
Cat.pick = pick

--- fire ---------------------------------------------------------------------------

-- Can fire take hold here: a forest, a farm, standing grain or meadow; not a
-- city, nor bare desert.
function Cat.flammable(game, cell)
    if not land(game, cell) or cell.city or cell.fire or cell.burnt then return false end
    if cell.feature == "forest" then return true end
    if cell.terrain == "desert" then return false end
    return cell.improvement == "farm" or cell.resource == "wheat" or cell.terrain == "grass"
end

function Cat.ignite(game, cell)
    local what = game:describe(cell)
    cell.fire = D.HEAT.burn
    game:emit({ kind = "ignite", cell = cell.id })
    game:emit({ kind = "terrain", cell = cell.id })
    if cell.owner then game:tell(cell.owner, "FIRE! THE " .. what .. " IS BURNING") end
end

-- A fire that has burnt out: the trees to stumps, the farm and the grain
-- gone, the grass to plains.
local function burnOut(game, cell)
    cell.fire = nil
    cell.burnt = true
    if cell.feature == "forest" then cell.burntForest = true end
    cell.feature = nil
    if cell.improvement == "farm" then cell.improvement = nil end
    if cell.resource == "wheat" then cell.resource = nil end
    if cell.terrain == "grass" then cell.terrain = "plains" end
    game:emit({ kind = "terrain", cell = cell.id })
end

-- Unit u hurt by the cataclysm: `how` says what killed it, if it does.
local function hurt(game, u, amount, how)
    u.hp = u.hp - amount
    game:emit({ kind = "hit", cell = u.cell, unit = u, amount = amount })
    if u.hp > 0 then return end
    game:removeUnit(u)
    game:emit({ kind = "death", cell = u.cell, unit = u })
    if u.owner ~= game.WILD then
        game:tell(u.owner, "OUR " .. u.def.name .. " " .. how)
        game:checkAlive(game.players[u.owner])
    end
end

Cat.hurt = hurt

local function unitsOn(game, cell)
    local out = {}
    if game.mil[cell.id] then out[#out + 1] = game.mil[cell.id] end
    if game.civ[cell.id] then out[#out + 1] = game.civ[cell.id] end
    return out
end
Cat.unitsOn = unitsOn

local function fires(game, stage)
    local H = D.HEAT
    local burning = {}
    for _, cell in ipairs(game.cells) do if cell.fire then burning[#burning + 1] = cell end end
    for _, cell in ipairs(burning) do
        for _, u in ipairs(unitsOn(game, cell)) do hurt(game, u, H.fireDamage, "WAS LOST TO THE FIRE") end
        for _, n in ipairs(game:neighbours(cell)) do
            if n.city then
                Cat.harm(game, n.city, H.cityBurn)
            elseif Cat.flammable(game, n) then
                local chance = n.feature == "forest" and H.spreadForest or H.spreadField
                if cool(n) then chance = chance * H.cisternFire end
                if game.rng:random() < chance then Cat.ignite(game, n) end
            end
        end
        cell.fire = cell.fire - 1
        if cell.fire <= 0 then burnOut(game, cell) end
    end
    -- New fires, where it is hot: forests most (none but the heat's own
    -- stages start them).
    local n = H.ignite[stage] or 0
    if n > 0 then
        local scorch = stage == "scorch"
        local starts = pick(game, function(cell)
            if not Cat.flammable(game, cell) or not (scorch or hot(game, cell)) then return 0 end
            return cell.feature == "forest" and 4 or 1
        end, n)
        for _, cell in ipairs(starts) do Cat.ignite(game, cell) end
    end
end

-- The fires burning now spread and burn down, as the heat's do: what
-- the sky's falling sets alight burns so too.
Cat.fires = fires

--- the turn -------------------------------------------------------------------------

local TELL = {
    omen = function() return ("THE SUN GROWS CRUEL. THE GREAT DROUGHT COMES IN %d TURNS"):format(D.HEAT.drought - D.HEAT.omen) end,
    drought = function() return "THE GREAT DROUGHT: THE LAND IS DRYING. BUILD CISTERNS" end,
    fires = function() return "THE WILDFIRES: THE FORESTS ARE BURNING" end,
    scorch = function() return ("THE SCORCH: THE EARTH BAKES. THE WORLD ENDS IN %d TURNS"):format(D.LAST_TURN - D.HEAT.scorch + 1) end,
}

-- The heat's part of a turn, in stage `stage`.
local function heatTurn(game, stage)
    if Cat.past(game, "fires") then fires(game, stage) end
    if stage == "scorch" then
        for _, cell in ipairs(game.cells) do
            if cell.scorched and not cell.city and not game:onRiver(cell) then
                for _, u in ipairs(unitsOn(game, cell)) do
                    if not u.def.sea then hurt(game, u, D.HEAT.scorchDamage, "DIED OF THE HEAT") end
                end
            end
        end
    end
    for _, cell in ipairs(pick(game, function(cell) return dryWeight(game, cell, false) end, D.HEAT.dry[stage])) do
        Cat.dry(game, cell)
    end
    if stage == "scorch" then
        for _, cell in ipairs(pick(game, function(cell) return dryWeight(game, cell, true) end, D.HEAT.bake)) do
            Cat.dry(game, cell)
        end
    end
end
HEAT.tell, HEAT.play = TELL, heatTurn

-- The cataclysm's part of a turn, played once every civilization and the
-- wild have, as the new turn begins. A kind that is `early` plays in its
-- omen too (the sky marks where its first stones will fall).
function Cat.turn(game)
    local c = game.cataclysm
    if not c then return end
    local K = Cat.KINDS[c.kind]
    local stage = Cat.stage(game)
    if not stage then return end
    if c.stage ~= stage then
        c.stage = stage
        game:tell(nil, K.tell[stage]())
        game:emit({ kind = K.event, stage = stage })
    end
    if stage ~= "omen" or K.early then K.play(game, stage) end
    local left = D.LAST_TURN - game.turn + 1
    if left == 5 or left == 1 then
        game:tell(nil, left == 1 and "THIS IS THE LAST TURN OF THE WORLD" or "FIVE TURNS ARE LEFT TO THE WORLD")
    end
end

Cat.KINDS.flood = require "src.flood"
Cat.KINDS.sky = require "src.skyfall"

return Cat
