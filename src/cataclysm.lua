-- The cataclysm: what ends the world, and the game with it.
--
-- Each game has one, kept as game.cataclysm (nil with Game.new{ cataclysm =
-- false }). Only the heat death is built: the others (the sky falling, the
-- demons) are meant to go in KINDS beside it, with the same stages and the
-- same last turn.
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
-- its people thirst less.
--
-- The cells keep what has happened to them: `fire` (turns it still burns),
-- `burnt` (it has; `burntForest` if trees stood there), `scorched` (baked
-- desert). The game emits "terrain" for
-- every hex that changes, "ignite" for every fire that starts and "heat"
-- as each stage begins. Nothing here draws.

local D = require "src.defs"

local max = math.max

local Cat = {}

Cat.STAGES = { "omen", "drought", "fires", "scorch" }
Cat.NAMES = { omen = "THE OMEN", drought = "THE GREAT DROUGHT", fires = "THE WILDFIRES", scorch = "THE SCORCH" }
local RANK = { omen = 1, drought = 2, fires = 3, scorch = 4 }

function Cat.new(kind)
    return { kind = kind or "heat" }
end

-- The stage turn `turn` is in, or nil before the omen.
function Cat.stageAt(turn)
    local H, at = D.HEAT, nil
    for _, s in ipairs(Cat.STAGES) do if turn >= H[s] then at = s end end
    return at
end

-- The game's stage now, or nil.
function Cat.stage(game)
    if not game.cataclysm then return nil end
    return Cat.stageAt(game.turn)
end

-- Has the game reached stage `s` (or one after)?
function Cat.past(game, s)
    local now = Cat.stage(game)
    return now ~= nil and RANK[now] >= RANK[s]
end

-- How the top bar shows it: "DROUGHT 41", the turns to the end. Nil before
-- the omen.
function Cat.label(game)
    local s = Cat.stage(game)
    if not s then return nil end
    local left = max(0, D.LAST_TURN - game.turn + 1)
    local word = ({ omen = "OMEN", drought = "DROUGHT", fires = "WILDFIRES", scorch = "SCORCH" })[s]
    return word .. " " .. left
end

--- what holds the heat off --------------------------------------------------------

local function cool(cell)
    local c = cell.ownerCity
    return c and c.buildings and c.buildings.cistern and c.owner == cell.owner
end
Cat.cool = cool

-- Does a farm on this cell lose food to the drought?
function Cat.droughtFarm(game, cell)
    return cell.improvement == "farm" and Cat.past(game, "drought") and not game:onRiver(cell) and not cool(cell)
end

-- The food city `city` loses this turn to thirst.
function Cat.thirst(game, city)
    local s = Cat.stage(game)
    local t = s and D.HEAT.thirst[s] or 0
    if t > 0 and city.buildings.cistern then t = max(0, t - D.HEAT.cisternThirst) end
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
local function pick(game, weigh, n)
    local list, total = {}, 0
    for _, cell in ipairs(game.cells) do
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

-- Unit u hurt by the heat: `how` says what killed it, if it does.
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

local function unitsOn(game, cell)
    local out = {}
    if game.mil[cell.id] then out[#out + 1] = game.mil[cell.id] end
    if game.civ[cell.id] then out[#out + 1] = game.civ[cell.id] end
    return out
end

local function fires(game, stage)
    local H = D.HEAT
    local burning = {}
    for _, cell in ipairs(game.cells) do if cell.fire then burning[#burning + 1] = cell end end
    for _, cell in ipairs(burning) do
        for _, u in ipairs(unitsOn(game, cell)) do hurt(game, u, H.fireDamage, "WAS LOST TO THE FIRE") end
        for _, n in ipairs(game:neighbours(cell)) do
            if n.city then
                local c = n.city
                c.hp = max(1, c.hp - H.cityBurn)
                game:emit({ kind = "hit", cell = n.id, amount = H.cityBurn })
            elseif Cat.flammable(game, n) then
                local chance = n.feature == "forest" and H.spreadForest or H.spreadField
                if cool(n) then chance = chance * H.cisternFire end
                if game.rng:random() < chance then Cat.ignite(game, n) end
            end
        end
        cell.fire = cell.fire - 1
        if cell.fire <= 0 then burnOut(game, cell) end
    end
    -- New fires, where it is hot: forests most.
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

--- the turn -------------------------------------------------------------------------

local TELL = {
    omen = function() return ("THE SUN GROWS CRUEL. THE GREAT DROUGHT COMES IN %d TURNS"):format(D.HEAT.drought - D.HEAT.omen) end,
    drought = function() return "THE GREAT DROUGHT: THE LAND IS DRYING. BUILD CISTERNS" end,
    fires = function() return "THE WILDFIRES: THE FORESTS ARE BURNING" end,
    scorch = function() return ("THE SCORCH: THE EARTH BAKES. THE WORLD ENDS IN %d TURNS"):format(D.LAST_TURN - D.HEAT.scorch + 1) end,
}

-- The cataclysm's part of a turn, played once every civilization and the
-- wild have, as the new turn begins.
function Cat.turn(game)
    local c = game.cataclysm
    if not c then return end
    local stage = Cat.stage(game)
    if not stage then return end
    if c.stage ~= stage then
        c.stage = stage
        game:tell(nil, TELL[stage]())
        game:emit({ kind = "heat", stage = stage })
    end
    if stage == "omen" then return end
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
    local left = D.LAST_TURN - game.turn + 1
    if left == 5 or left == 1 then
        game:tell(nil, left == 1 and "THIS IS THE LAST TURN OF THE WORLD" or "FIVE TURNS ARE LEFT TO THE WORLD")
    end
end

return Cat
