-- The cataclysm: what ends the world, and the game with it.
--
-- Each game has one, kept as game.cataclysm (nil with Game.new{ cataclysm =
-- false }): its `kind` one of Cat.KINDS. Seven are built: the heat death
-- here, the deluge in src/flood.lua, the sky's falling in src/skyfall.lua,
-- the demons in src/demons.lua, the still sun in src/stillsun.lua, the
-- plague in src/plague.lua and the sundering in src/quake.lua (what
-- the cold does, the last two share: src/frost.lua). Every kind has four stages on its
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
--            food, and burns whoever ends a turn on it. On D.HEAT.ebb,
--            told some turns before, the great ebb: the sea draws back
--            from every shore at once, its shallows left as salt flats
--            to walk on, and it goes on drawing back, a few hexes a turn.
--
-- From the drought on the rivers fail, a few stretches a turn, from the
-- springs down: a dry river is a bed of cracked mud, and holds nothing off.
--
-- A river, the coast, hills and a city's cistern hold the heat off: the
-- land dries slower there. A cistern's land is slower to catch fire, and
-- its people thirst less. A shelter (D.SHELTER), against any cataclysm,
-- halves the harm the fire beside a city does it, and its stores spare it
-- a little of the thirst.
--
-- The cells keep what has happened to them: `fire` (turns it still burns),
-- `burnt` (it has; `burntForest` if trees stood there), `scorched` (baked
-- desert), `dry` (the river beds by it: dry[k], as river[k] was),
-- `ebbed` (the sea has left it). The game emits "ebb" as the sea draws
-- back, and "terrain" for
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

-- The building that holds it off ("cistern", "levee"), or nil. For city
-- `city`, if given, the one it wants where it stands (under the still sun,
-- a cistern in the day and a hearth in the night).
function Cat.ward(game, city)
    local K = Cat.kindOf(game)
    if K and city and K.wardFor then return K.wardFor(game, city) end
    return K and K.ward
end

-- What city `city` builds against it after its ward and its shelter, or
-- nil: a hearth against the sky's long night, a levee against the
-- sundering's waves by the sea.
function Cat.also(game, city)
    local K = Cat.kindOf(game)
    return K and K.also and K.also(game, city) or nil
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
-- fever; under the falling sky, to the cold; before the demons, to dread;
-- in the plague, to the sickness or to fear; in the sundering, to fear). A
-- shelter's stores spare it
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
-- if it can't. Forests don't dry: they burn. The frozen north the map was
-- made with (src/mapgen.lua) holds its cold. With `bake`, only the desert,
-- to bake hard; without, only the rest.
local function dryWeight(game, cell, bake)
    if not land(game, cell) or cell.feature == "forest" or cell.fire or cell.scorched then return 0 end
    if D.TERRAIN[cell.terrain].frozen or cell.terrain == "saltflat" then return 0 end
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

-- Will unit u be hurt, or worse, if it ends the turn on hex `cell`: a
-- fire, a flood (if it cannot swim), the heat's baked earth in the scorch,
-- a stone marked to fall, the still sun's day or night, the ice round a
-- ship, a rift or the citadel about to come up under it. A city's hex is
-- never one. The beasts (src/beasts.lua) keep off these.
function Cat.perilous(game, cell, u)
    local c = game.cataclysm
    if not c or cell.city then return false end
    local sea = u.def.sea
    if cell.fire and not game:isWater(cell) then return true end
    if cell.flood and not sea then return true end
    local kind = c.kind
    if kind == "flood" and not sea then
        local F = Cat.KINDS.flood
        local level, left = F.coming(game)
        return level ~= nil and left <= 1 and F.doomed(game, cell)
    end
    if kind == "heat" then
        return not sea and (cell.scorched == true or cell.terrain == "saltflat") and Cat.stage(game) == "scorch"
            and not game:onRiver(cell)
    elseif kind == "sky" then
        if Cat.KINDS.sky.marked(game, cell) then return true end
        return sea and cell.terrain == "ice"
    elseif kind == "sun" then
        return Cat.KINDS.sun.danger(game, cell, u) == true
    elseif kind == "demons" then
        local m = c.marks and c.marks[cell.id]
        return m == "rift" or m == "citadel"
    elseif kind == "quake" then
        return Cat.KINDS.quake.danger(game, cell, u) == true
    end
    return false
end

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

--- the rivers fail ----------------------------------------------------------------

-- Every stretch of river still running, each once, with the two hexes
-- either side of it: { e, { cell, k }, { cell, k } }.
local function stretches(game)
    local out, at = {}, {}
    for _, cell in ipairs(game.cells) do
        if cell.river then
            for k = 0, 5 do
                local e = cell.river[k]
                if e then
                    local s = at[e]
                    if not s then
                        s = { e = e }
                        at[e] = s
                        out[#out + 1] = s
                    end
                    s[#s + 1] = { cell = cell, k = k }
                end
            end
        end
    end
    return out
end

local function corner(p) return math.floor(p[1] * 4 + 0.5) * 65536 + math.floor(p[2] * 4 + 0.5) end

-- A stretch of river runs dry: its water gone from both banks, kept as
-- `dry` (cell.dry[k], the same table the river was) for its bed to be
-- drawn.
function Cat.dryRiver(game, s)
    for _, side in ipairs(s) do
        local cell, k = side.cell, side.k
        cell.river[k] = nil
        if next(cell.river) == nil then cell.river = nil end
        cell.dry = cell.dry or {}
        cell.dry[k] = s.e
        game:emit({ kind = "terrain", cell = cell.id })
    end
end

-- `n` stretches of river run dry, the springs first: only one no water
-- still runs into, the smallest likeliest, a cistern's slower.
local function failRivers(game, n)
    if n <= 0 then return end
    local list = stretches(game)
    local into = {}
    for _, s in ipairs(list) do into[corner(s.e.to)] = true end
    local heads = {}
    for _, s in ipairs(list) do
        if not into[corner(s.e.from)] then heads[#heads + 1] = s end
    end
    local weight = {}
    for _, s in ipairs(heads) do
        local w = 1 / ((s.e.size or 1) ^ 2)
        for _, side in ipairs(s) do
            if cool(side.cell) then w = w * D.HEAT.riverCistern end
        end
        weight[s] = w
    end
    local told = {}
    for _ = 1, n do
        local total = 0
        for _, s in ipairs(heads) do total = total + weight[s] end
        if total <= 0 then break end
        local r = game.rng:random() * total
        for _, s in ipairs(heads) do
            r = r - weight[s]
            if weight[s] > 0 and r <= 0 then
                weight[s] = 0
                Cat.dryRiver(game, s)
                for _, side in ipairs(s) do
                    local o = side.cell.owner
                    if o and not told[o] then
                        told[o] = true
                        game:tell(o, (s.e.name or "A RIVER") .. " IS RUNNING DRY")
                    end
                end
                break
            end
        end
    end
end
Cat.failRivers = failRivers

--- the great ebb ----------------------------------------------------------------

-- Unit u, on hex `cell` it can no longer be on (a ship on the salt, or in
-- a town the sea has left): to the nearest hex within 3 it can be on, if
-- there is one; else lost.
local function beach(game, u, cell)
    if game:canEnter(u, cell) then return end
    local slot = game:slot(u)
    local best, bd
    for _, n in ipairs(game:within(cell, 3)) do
        if n ~= cell and not slot[n.id] and game:canEnter(u, n) and not game:foreignAt(n, u.owner) then
            local d = game:dist(cell, n) + n.id * 1e-6
            if not bd or d < bd then best, bd = n, d end
        end
    end
    if best then
        slot[cell.id] = nil
        slot[best.id] = u
        u.cell = best.id
        u.trail = { best.id }
        game:emit({ kind = "terrain", cell = best.id })
        return
    end
    hurt(game, u, u.hp, "WAS LEFT HIGH AND DRY")
end

-- Can the sea draw back from hex `cell`: the shallows (not the deep, not a
-- lair's).
local function ebbable(game, cell)
    return cell.terrain == "coast" and not cell.lair
end

-- The sea draws back from hex `cell`: its floor bare, a salt flat, the
-- fish and the boats gone; the deep water beside it is shallows now.
function Cat.bare(game, cell)
    cell.terrain = "saltflat"
    cell.top = D.TERRAIN.saltflat.top
    cell.elev = "flat"
    cell.ebbed = true
    if cell.resource == "fish" then cell.resource = nil end
    if cell.improvement == "boats" then cell.improvement = nil end
    if cell.workedBy then cell.workedBy = nil end
    game:emit({ kind = "terrain", cell = cell.id })
    for _, n in ipairs(game:neighbours(cell)) do
        if n.terrain == "ocean" then n.terrain = "coast" end
        if game:isWater(n) then game:emit({ kind = "terrain", cell = n.id }) end
    end
end

-- The sea draws back: from every shallow with `n` nil, or else from `n`
-- of the shallows beside the dry land. Whoever can't stay where the sea
-- has left is moved, or lost.
function Cat.ebb(game, n)
    local list = {}
    for _, cell in ipairs(game.cells) do
        if ebbable(game, cell) then
            if not n then
                list[#list + 1] = cell
            else
                for _, m in ipairs(game:neighbours(cell)) do
                    if not game:isWater(m) then list[#list + 1] = cell break end
                end
            end
        end
    end
    if n then list = pick(game, function(cell) return 1 end, n, list) end
    for _, cell in ipairs(list) do Cat.bare(game, cell) end
    if #list == 0 then return list end
    -- The ships on the salt, and in the towns the sea has left.
    local units = {}
    for _, u in ipairs(game.units) do units[#units + 1] = u end
    for _, u in ipairs(units) do
        if not u.dead then beach(game, u, game.cells[u.cell]) end
    end
    for _, c in ipairs(game.cities) do game:assignWork(c) end
    game:emit({ kind = "ebb", cells = #list })
    return list
end

-- Will the sea have drawn back yet: the turns to the great ebb, once it is
-- told; nil before, or once it has.
function Cat.ebbIn(game)
    if not Cat.is(game, "heat") or game.turn < D.HEAT.warn or game.turn >= D.HEAT.ebb then return nil end
    return D.HEAT.ebb - game.turn
end

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
    failRivers(game, D.HEAT.riverDry[stage] or 0)
    if game.turn == D.HEAT.warn then
        game:tell(nil, ("THE SEA IS DRAWING BACK FROM THE SHORES: IN %d TURNS THE SHALLOWS WILL BE DRY"):format(
            D.HEAT.ebb - game.turn))
        game:emit({ kind = "mark" })
    end
    if game.turn == D.HEAT.ebb then
        Cat.ebb(game)
        game:tell(nil, "THE GREAT EBB: THE SEA HAS DRAWN BACK. ITS FLOOR LIES BARE, AND CAN BE WALKED")
    elseif game.turn > D.HEAT.ebb then
        Cat.ebb(game, D.HEAT.recede)
    end
    if stage == "scorch" then
        for _, cell in ipairs(game.cells) do
            if (cell.scorched or cell.terrain == "saltflat") and not cell.city and not game:onRiver(cell) then
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
Cat.KINDS.demons = require "src.demons"
Cat.KINDS.sun = require "src.stillsun"
Cat.KINDS.plague = require "src.plague"
Cat.KINDS.quake = require "src.quake"

return Cat
