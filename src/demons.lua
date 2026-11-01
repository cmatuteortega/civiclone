-- The demons: the world ends in the abyss. One of the cataclysm's kinds
-- (src/cataclysm.lua), on the same turns as the others, by D.DEMONS's:
--
--   OMEN       a blood moon. On its last turn the ground the demons' capital
--              will rise on is seen marked.
--   RIFTS      the citadel of the abyss rises there: the demons' one
--              capital. It sends hell spiders out, blights the land round
--              it (its borders) and strikes whoever stands beside it. Rifts
--              tear open in the land too, each seen coming the turn before,
--              each sending demons out and blighting the hexes beside it.
--   DEEP       the citadel grows: stronger, further reaching, and giant eyes
--              come out of it and the rifts, that strike from two hexes off.
--              Tentacles rise out of the coast's water beside the land, seen
--              coming the turn before, and lash whatever is on the shore:
--              they drag a civilian or anyone in a boat under at a blow, and
--              with no one to strike wreck the farms, mines and boats beside
--              them. The cities dread: they lose food every turn.
--   HELLGATE   the citadel at its greatest, brood mothers marching on the
--              towns, and the dread worse. On D.DEMONS.eye the Eye of the
--              Abyss comes out of the citadel, told some turns before, and
--              goes for the nearest capital.
--
-- It is the one cataclysm that fights back. The demons are the wild's
-- (owner 0, as the beasts are), but they keep to no lair: they go for the
-- civilizations' people and their towns. They never take a town: a demon's
-- blow leaves a city at 1 HP at least, and one that would have fallen loses
-- a citizen to them instead (none from a city with a shelter). A rift is
-- sealed as a den is cleared, by walking into it with no demon there; the
-- citadel stands HP like a city's, and has to be beaten down to nothing
-- before anyone can walk in and raze it. Then its blight heals, it sends
-- no one out, and the Eye never comes. Every demon slain, rift sealed and
-- the citadel razed brings glory, which counts in the score.
--
-- What holds it off is the sanctum (D.BUILDINGS.sanctum): no rift opens on
-- its city's land nor does the blight take it, the city shoots the demons
-- near it even without walls, and its people dread less. And an army.
--
-- The cells keep `blight`. game.cataclysm keeps `marks` ({ [cell id] =
-- "rift" | "tentacle" | "citadel" }, what comes up there as the next turn
-- begins) and `citadel` (the cell id of the citadel, once it is risen; its
-- lair, cells[id].lair, holds its `hp`, `maxHp` and `str`, and goes when it
-- is razed). The game emits "terrain" for every hex that changes, "rift"
-- for every rift that opens and "rise" for every tentacle, "citadel" as it
-- rises, "mark" when new marks are laid, and "demons" as each stage
-- begins. Nothing here draws.

local D = require "src.defs"
local Cat = require "src.cataclysm"
local Beasts = require "src.beasts"

local max, min, floor = math.max, math.min, math.floor

local Demons = {
    stages = { "omen", "rifts", "deep", "hellgate" },
    names = { omen = "THE OMEN", rifts = "THE RIFTS", deep = "THE DEEP", hellgate = "THE HELLGATE" },
    words = { omen = "OMEN", rifts = "RIFTS", deep = "THE DEEP", hellgate = "HELLGATE" },
    turns = D.DEMONS, event = "demons", ward = "sanctum", ended = "THE ABYSS HAS SWALLOWED THE WORLD",
    -- It marks where its citadel rises in the omen's last turn.
    early = true,
}

-- The citadel's razing comes to it through the beasts' clearing of lairs.
Beasts.onRazed = function(game, who) Demons.razed(game, who) end

local function isDemon(u) return u.owner == Beasts.WILD and u.def.demon end
Demons.isDemon = isDemon

local function land(game, cell) return game:passable(cell) end

-- Does the hex belong to a city with a sanctum?
local function hallowed(cell) return Cat.warded(cell, "sanctum") end
Demons.hallowed = hallowed

--- what is where -------------------------------------------------------------------------

-- What comes up on hex `cell` as the next turn begins: "rift", "tentacle"
-- or "citadel", or nil.
function Demons.marked(game, cell)
    local c = game.cataclysm
    if not c or c.kind ~= "demons" then return nil end
    return c.marks and c.marks[cell.id] or nil
end

-- The citadel's lair while it stands, and its hex.
function Demons.citadel(game)
    local c = game.cataclysm
    if not c or c.kind ~= "demons" or not c.citadel then return nil end
    local cell = game.cells[c.citadel]
    if cell.lair and cell.lair.def.citadel then return cell.lair, cell end
end

-- The Eye of the Abyss's coming: the turns to it, while the citadel stands
-- and it is told.
function Demons.eyeComing(game)
    local lair = Demons.citadel(game)
    if not lair or game.turn < D.DEMONS.eyeWarn or game.turn >= D.DEMONS.eye then return nil end
    return D.DEMONS.eye - game.turn
end

local function tentacleNear(game, cell)
    for _, n in ipairs(game:within(cell, 1)) do
        local m = game.mil[n.id]
        if m and m.kind == "tentacle" then return true end
    end
    return false
end

--- what it does to what the land yields ----------------------------------------------------

-- Food on hex `cell`, `f` before the demons have their say: blighted land
-- yields none, and nor does the water a tentacle has darkened.
function Demons.food(game, cell, f)
    if cell.blight then return 0 end
    if game:isWater(cell) and Cat.past(game, "deep") and tentacleNear(game, cell) then return 0 end
    return f
end

-- The food city `city` loses this turn to dread; its sanctum spares some.
function Demons.thirst(game, city)
    local s = Cat.stage(game)
    local t = s and D.DEMONS.dread[s] or 0
    if t > 0 and city.buildings.sanctum then t = max(0, t - D.DEMONS.sanctumDread) end
    return t
end

-- A demon's blow has brought city `city` to nothing: it stands at 1 HP, and
-- the demons take one of its people (none from a shelter, never the last,
-- once a turn).
function Demons.devour(game, city)
    city.hp = 1
    if city.devoured == game.turn then return end
    city.devoured = game.turn
    if not Cat.sheltered(city) and city.pop > 1 then
        city.pop = city.pop - 1
        game:assignWork(city)
        game:tell(city.owner, "THE DEMONS FEED ON " .. city.name .. ": ITS PEOPLE ARE TAKEN")
        game:emit({ kind = "devour", cell = city.cell })
    else
        game:tell(city.owner, city.name .. " IS BESIEGED BY DEMONS")
    end
end

--- the blight ------------------------------------------------------------------------------

local function blightable(game, cell)
    return land(game, cell) and not cell.city and not cell.blight and not hallowed(cell)
end

-- Hex `cell` blighted: its trees die where they stand, its farm or mine and
-- its grain are lost.
function Demons.blight(game, cell)
    cell.blight = true
    cell.fire = nil
    if cell.feature == "forest" then
        cell.feature = nil
        cell.burntForest = true
    end
    if cell.improvement and cell.improvement ~= "boats" then
        if cell.owner then game:tell(cell.owner, "THE BLIGHT HAS TAKEN A " .. D.IMPROVEMENT[cell.improvement].name) end
        cell.improvement = nil
    end
    if cell.resource == "wheat" then cell.resource = nil end
    game:emit({ kind = "terrain", cell = cell.id })
end

-- Where the blight comes from: { cell, reach, spread } for the citadel and
-- every rift.
local function sources(game, stage)
    local out = {}
    local _, cc = Demons.citadel(game)
    if cc then out[#out + 1] = { cell = cc, reach = D.DEMONS.citadelReach[stage] or 1, spread = D.DEMONS.citadelSpread } end
    for _, l in ipairs(game.lairs) do
        if l.kind == "rift" then
            out[#out + 1] = { cell = game.cells[l.cell], reach = D.DEMONS.riftReach[stage] or 1, spread = D.DEMONS.spread }
        end
    end
    return out
end

local function spreadBlight(game, stage)
    local src = sources(game, stage)
    for _, s in ipairs(src) do
        local near = game:within(s.cell, s.reach)
        for _, cell in ipairs(Cat.pick(game, function(c) return blightable(game, c) and 1 or 0 end, s.spread, near)) do
            Demons.blight(game, cell)
        end
    end
    -- Out of every reach, it heals.
    for _, cell in ipairs(game.cells) do
        if cell.blight then
            local free = true
            if not hallowed(cell) then
                for _, s in ipairs(src) do
                    if game:dist(cell, s.cell) <= s.reach then free = false break end
                end
            end
            if free and game.rng:random() < D.DEMONS.heal then
                cell.blight = nil
                game:emit({ kind = "terrain", cell = cell.id })
            end
        end
    end
    -- And whoever stands on it withers.
    for _, cell in ipairs(game.cells) do
        if cell.blight then
            for _, u in ipairs(Cat.unitsOn(game, cell)) do
                if u.owner ~= Beasts.WILD then Cat.hurt(game, u, D.DEMONS.blightDamage, "WITHERED IN THE BLIGHT") end
            end
        end
    end
end

--- coming up --------------------------------------------------------------------------------

-- Whatever stands on hex `cell` where something comes up out of the ground
-- is thrown off it: to a free hex beside, or it is lost.
local function clear(game, cell, how)
    for _, u in ipairs(Cat.unitsOn(game, cell)) do
        if u.owner ~= Beasts.WILD or not u.def.demon then
            local to = u.owner ~= Beasts.WILD and game:freeNear(cell.id, u.def.civilian, u.def.sea, u.owner)
            if to then
                local slot = game:slot(u)
                slot[cell.id] = nil
                u.cell = to
                slot[to] = u
                u.trail = { to }
                game:emit({ kind = "hit", cell = to, unit = u, amount = 0 })
            elseif u.owner == Beasts.WILD then
                game:removeUnit(u)
            else
                Cat.hurt(game, u, u.hp, how)
            end
        end
    end
end

-- How near the nearest city is to hex `cell` (a big number with none).
local function cityDistance(game, cell)
    local best = math.huge
    for _, c in ipairs(game.cities) do best = min(best, game:dist(cell, game.cells[c.cell])) end
    return best
end

-- Where the citadel rises: open land at least D.DEMONS.citadelFrom from
-- every city, likeliest just beyond that, and out of anyone's borders.
local function siteCitadel(game)
    local from = D.DEMONS.citadelFrom
    local list = Cat.pick(game, function(cell)
        if not land(game, cell) or cell.lair or cell.city then return 0 end
        local d = cityDistance(game, cell)
        if d < from then return 0 end
        local w = d == math.huge and 1 or 1 / (1 + (d - from))
        if cell.owner then w = w * 0.2 end
        return w
    end, 1)
    if list[1] then return list[1] end
    list = Cat.pick(game, function(cell) return (land(game, cell) and not cell.city and not cell.lair) and 1 or 0 end, 1)
    return list[1]
end

local function riseCitadel(game, cell)
    local c = game.cataclysm
    clear(game, cell, "WAS CRUSHED AS THE CITADEL ROSE")
    if cell.lair then Beasts.removeLair(game, cell.lair) end
    local lair = Beasts.addLair(game, "citadel", cell.id)
    lair.hp = D.DEMONS.citadelHp.rifts
    lair.maxHp = lair.hp
    lair.str = D.DEMONS.citadelStr.rifts
    lair.timer = D.DEMONS.citadelEvery.rifts
    c.citadel = cell.id
    cell.feature, cell.improvement = nil, nil
    Demons.blight(game, cell)
    game:tell(nil, "THE CITADEL OF THE ABYSS HAS RISEN ON THE " .. game:describe(cell))
    -- Everyone knows where it is.
    for _, p in ipairs(game.players) do
        for _, n in ipairs(game:within(cell, 1)) do p.explored[n.id] = true end
        p.sightChanged = true
    end
    game:emit({ kind = "citadel", cell = cell.id })
end

local function openRift(game, cell)
    clear(game, cell, "FELL INTO A RIFT")
    local lair = Beasts.addLair(game, "rift", cell.id)
    lair.timer = 0
    Demons.blight(game, cell)
    if cell.owner then game:tell(cell.owner, "A RIFT HAS TORN OPEN ON OUR LAND") end
    game:emit({ kind = "rift", cell = cell.id })
    -- Something comes up out of it at once.
    Beasts.spawn(game, "spider", cell.id, cell.id)
end

local function riseTentacle(game, cell)
    if game.mil[cell.id] then
        local u = game.mil[cell.id]
        if u.owner == Beasts.WILD then return end
        Cat.hurt(game, u, 40, "WAS DRAGGED UNDER BY A TENTACLE")
        if game.mil[cell.id] then return end
    end
    local t = game:addUnit("tentacle", Beasts.WILD, cell.id)
    t.home, t.life = cell.id, D.DEMONS.tentacleLife
    game:emit({ kind = "rise", cell = cell.id })
end

-- Lays the marks of what comes up as the next turn begins.
local function mark(game)
    local c = game.cataclysm
    c.marks = {}
    local nextTurn = game.turn + 1
    if nextTurn > D.LAST_TURN then return end
    local stage = Cat.stageAt(nextTurn, "demons")
    local T = D.DEMONS
    if nextTurn == T.rifts and not c.citadel then
        local cell = siteCitadel(game)
        if cell then
            c.marks[cell.id] = "citadel"
            game:tell(nil, "THE GROUND IS SPLITTING ON THE " .. game:describe(cell) .. ": SOMETHING IS COMING UP")
        end
    end
    if stage == "omen" or not stage then
        game:emit({ kind = "mark" })
        return
    end
    -- A rift, now and then.
    local open = 0
    for _, l in ipairs(game.lairs) do if l.kind == "rift" then open = open + 1 end end
    if open < (T.riftMax[stage] or 0) and game.rng:random() < (T.rift[stage] or 0) then
        local from = T.riftFrom[stage]
        local cell = Cat.pick(game, function(cell)
            if not land(game, cell) or cell.city or cell.lair or c.marks[cell.id] or hallowed(cell) then return 0 end
            local d = cityDistance(game, cell)
            if d < from then return 0 end
            return d == math.huge and 1 or 1 / (1 + d - from)
        end, 1)[1]
        if cell then
            c.marks[cell.id] = "rift"
            if cell.owner then game:tell(cell.owner, "THE GROUND IS SPLITTING ON THE " .. game:describe(cell)) end
        end
    end
    -- Tentacles, by the shore.
    local n = T.tentacles[stage] or 0
    if n > 0 then
        local up = 0
        for _, u in ipairs(game.units) do if u.kind == "tentacle" then up = up + 1 end end
        n = min(n, (T.tentacleMax[stage] or 0) - up)
        if n > 0 then
            local picked = Cat.pick(game, function(cell)
                if cell.terrain ~= "coast" or game.mil[cell.id] or c.marks[cell.id] then return 0 end
                local w, shore = 1, false
                for _, nb in ipairs(game:neighbours(cell)) do
                    if land(game, nb) or nb.city then
                        shore = true
                        if nb.city then w = w + 4 end
                        if nb.improvement then w = w + 2 end
                        local v = game.mil[nb.id] or game.civ[nb.id]
                        if v and v.owner ~= Beasts.WILD then w = w + 2 end
                    end
                end
                if not shore then return 0 end
                if cell.improvement == "boats" then w = w + 2 end
                return w
            end, n)
            for _, cell in ipairs(picked) do
                c.marks[cell.id] = "tentacle"
                if cell.owner then game:tell(cell.owner, "SOMETHING STIRS IN THE WATER BY THE " .. game:describe(cell)) end
            end
        end
    end
    game:emit({ kind = "mark" })
end

--- the demons' own turn ------------------------------------------------------------------

-- The civilizations' units within n of a cell, and their cities, nearest
-- first: { what, cell }.
local function prey(game, cell, n, citiesOnly)
    local out = {}
    if not citiesOnly then
        for _, v in ipairs(game.units) do
            if v.owner ~= Beasts.WILD then
                local d = game:dist(cell, game.cells[v.cell])
                if d <= n and not game.cells[v.cell].city then out[#out + 1] = { d = d, cell = game.cells[v.cell] } end
            end
        end
    end
    for _, c in ipairs(game.cities) do
        local d = game:dist(cell, game.cells[c.cell])
        -- The towns draw them most: a city is gone for before the people
        -- nearer.
        if d <= n then out[#out + 1] = { d = d + (citiesOnly and (c.capital and 0 or 0.5) or -2.5), cell = game.cells[c.cell] } end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

-- Strike the best thing in reach: a civilian (or someone in a boat, for
-- what drags them under) first, then the weakest.
local function strike(game, u)
    local here = game.cells[u.cell]
    local reach = u.def.ranged and u.def.range or 1
    local best, bv
    for _, cell in ipairs(game:within(here, reach)) do
        if cell ~= here and game:canAttack(u, cell) then
            local v
            if cell.city then
                v = 40 - cell.city.hp / 10
            else
                local t = game.mil[cell.id] or game.civ[cell.id]
                v = 100 - t.hp - game:defense(t)
                if t.def.civilian or (u.def.drags and game:embarked(t)) then v = v + 1000 end
            end
            if not bv or v > bv then best, bv = cell, v end
        end
    end
    if best then return game:attack(u, best) end
    return false
end

-- Out of the way of nothing: a step about home, keeping within its leash.
local function wander(game, u)
    local here = game.cells[u.cell]
    local home = game.cells[u.home or u.cell]
    local best, bv
    for _, n in ipairs(game:neighbours(here)) do
        if game:canStand(u, n) and game:stepCost(u, here, n) and game:dist(n, home) <= u.def.leash then
            local v = game.rng:random()
            if not bv or v > bv then best, bv = n, v end
        end
    end
    if best then game:step(u, best.id) end
end

-- A tentacle with nothing to strike tears at what is beside it.
local function wreck(game, u)
    if game.rng:random() >= D.DEMONS.wreck then return end
    local list = {}
    for _, n in ipairs(game:within(game.cells[u.cell], 1)) do
        if n.improvement and not n.city then list[#list + 1] = n end
    end
    if #list == 0 then return end
    local cell = list[game.rng:random(#list)]
    if cell.owner then game:tell(cell.owner, "A TENTACLE HAS TORN APART A " .. D.IMPROVEMENT[cell.improvement].name) end
    cell.improvement = nil
    game:emit({ kind = "terrain", cell = cell.id })
    game:emit({ kind = "attack", unit = u, from = u.cell, to = cell.id })
end

local function act(game, u)
    if u.kind == "tentacle" then
        if not strike(game, u) then wreck(game, u) end
        return
    end
    if strike(game, u) then return end
    local here = game.cells[u.cell]
    local list = u.def.boss and prey(game, here, 99, true) or prey(game, here, u.def.sense)
    for _, p in ipairs(list) do
        local path = game:path(u, p.cell.id, true)
        if path and #path > 0 then
            -- One that strikes from afar goes only as near as it must.
            if u.def.ranged then
                local cut = {}
                for _, id in ipairs(path) do
                    cut[#cut + 1] = id
                    if game:dist(game.cells[id], p.cell) <= u.def.range then break end
                end
                path = cut
            end
            game:walk(u, path)
            u.dest = nil
            if u.moves > 0 then strike(game, u) end
            return
        elseif path then
            return
        end
    end
    wander(game, u)
end

-- Every demon acts: what is beside it is struck, and the rest hunted.
local function demonsAct(game)
    local list = {}
    for _, u in ipairs(game.units) do
        if isDemon(u) then
            u.moves, u.attacked = game:maxMoves(u), false
            list[#list + 1] = u
        end
    end
    for _, u in ipairs(list) do
        if not u.dead then act(game, u) end
        u.dest = nil
    end
end

-- The kind a lair sends out in stage `stage`.
local function brood(game, stage, citadel)
    local r = game.rng:random()
    if stage == "rifts" then return "spider" end
    if stage == "deep" then return r < 0.45 and "eye" or "spider" end
    if citadel and r < 0.4 then return "brood" end
    return r < 0.7 and "spider" or "eye"
end

-- The citadel and the rifts send their demons out, and the citadel strikes
-- whoever is beside it.
local function lairsTurn(game, stage)
    local T = D.DEMONS
    for _, l in ipairs(game.lairs) do
        if l.def.demon then
            local cell = game.cells[l.cell]
            local citadel = l.def.citadel
            if citadel then
                -- It grows stage by stage, and heals.
                local top = T.citadelHp[stage] or l.maxHp
                if top > l.maxHp then l.hp, l.maxHp = l.hp + (top - l.maxHp), top end
                l.str = T.citadelStr[stage] or l.str
                l.hp = min(l.maxHp, l.hp + T.citadelHeal)
                for _, n in ipairs(game:neighbours(cell)) do
                    for _, u in ipairs(Cat.unitsOn(game, n)) do
                        if u.owner ~= Beasts.WILD then Cat.hurt(game, u, T.citadelHit, "WAS STRUCK DOWN BY THE CITADEL") end
                    end
                end
            end
            l.timer = (l.timer or 0) + 1
            local every = citadel and T.citadelEvery[stage] or T.riftEvery[stage]
            local keep = citadel and T.citadelKeep[stage] or T.riftKeep[stage]
            local n = 0
            for _, v in ipairs(game.units) do if isDemon(v) and v.home == l.cell then n = n + 1 end end
            if n < keep and l.timer >= every then
                l.timer = 0
                Beasts.spawn(game, brood(game, stage, citadel), l.cell, l.cell)
            end
        end
    end
end

--- the turn ----------------------------------------------------------------------------------

Demons.tell = {
    omen = function() return ("THE MOON HAS TURNED TO BLOOD. THE RIFTS OPEN IN %d TURNS"):format(D.DEMONS.rifts - D.DEMONS.omen) end,
    rifts = function() return "THE RIFTS: DEMONS COME UP OUT OF THE EARTH. RAISE SANCTUMS, SEAL THE RIFTS" end,
    deep = function() return "THE DEEP: TENTACLES RISE FROM THE SEA, AND THE TOWNS LIVE IN DREAD" end,
    hellgate = function() return ("THE HELLGATE: THE ABYSS IS OPEN. THE WORLD ENDS IN %d TURNS"):format(D.LAST_TURN - D.DEMONS.hellgate + 1) end,
}

function Demons.play(game, stage)
    local c = game.cataclysm
    local T = D.DEMONS
    if stage ~= "omen" then
        -- The tentacles that have had their time sink.
        for _, u in ipairs(game:unitsOf(Beasts.WILD)) do
            if u.kind == "tentacle" then
                u.life = (u.life or T.tentacleLife) - 1
                if u.life <= 0 then
                    game:removeUnit(u)
                    game:emit({ kind = "sink", cell = u.cell, unit = u })
                end
            end
        end
        demonsAct(game)
    end
    -- What was seen coming comes up.
    local due = {}
    for id, what in pairs(c.marks or {}) do due[#due + 1] = { id, what } end
    table.sort(due, function(a, b) return a[1] < b[1] end)
    c.marks = {}
    for _, m in ipairs(due) do
        local cell = game.cells[m[1]]
        if m[2] == "citadel" then riseCitadel(game, cell)
        elseif m[2] == "rift" and not cell.lair and not cell.city then openRift(game, cell)
        elseif m[2] == "tentacle" then riseTentacle(game, cell) end
    end
    if stage ~= "omen" then
        lairsTurn(game, stage)
        spreadBlight(game, stage)
        local lair, cc = Demons.citadel(game)
        if lair and game.turn == T.eyeWarn then
            game:tell(nil, ("THE EYE OF THE ABYSS WILL OPEN IN THE CITADEL IN %d TURNS. RAZE IT"):format(T.eye - game.turn))
        end
        if lair and game.turn == T.eye then
            local eye = Beasts.spawn(game, "abyss", cc.id, cc.id)
            if eye then
                game:tell(nil, "THE EYE OF THE ABYSS HAS OPENED. IT COMES FOR THE CAPITALS")
                game:emit({ kind = "abyss", cell = eye.cell })
            end
        end
    end
    -- And the next turn's are seen coming.
    if game.turn + 1 >= T.rifts then mark(game) end
end

-- The citadel has been razed, by player `who`.
function Demons.razed(game, who)
    game:tell(nil, "THE CITADEL OF THE ABYSS HAS BEEN RAZED BY " .. game.players[who].name)
    if game.turn < D.DEMONS.eye then game:tell(nil, "THE EYE OF THE ABYSS WILL NEVER OPEN") end
    game:emit({ kind = "razed", cell = game.cataclysm.citadel })
end

return Demons
