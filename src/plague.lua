-- The plague: the world ends in sickness. One of the cataclysm's kinds
-- (src/cataclysm.lua), on the same turns as the others, by D.PLAGUE's:
--
--   OMEN     crows gather over the towns. On its last turn the first town to
--            fall sick is seen: everyone is told which.
--   FEVER    it falls sick, and the sickness goes from town to town: to the
--            towns near a sick one (more by a river or the sea they share),
--            and with the people who walk out of one, or beside one, into or
--            beside another. A sick town loses food and its people, one now
--            and then, and doesn't grow; a death may leave one of its farms
--            fallow. In time it mends, and then can't catch it again for a
--            while.
--   DYING    faster, and a second town falls sick far from the first. The
--            sick towns send rats out that run for the towns still well and
--            bring it in, and spoil the farms they stand on. The well towns
--            go hungry for fear.
--   DANCE    worse still. On D.PLAGUE.great the great pestilence comes, told
--            some turns before: every sick town loses a third of its people,
--            and every well town near one that isn't shut falls sick.
--
-- It is the one cataclysm that goes from town to town, and what holds it
-- off is keeping people out: a town can be shut (quarantined): no one walks
-- in or out of it, it doesn't grow and it makes no gold, but the sickness
-- reaches it, and goes out of it, only a little. The lazaret
-- (D.BUILDINGS.lazaret) halves its deaths, mends it sooner and spares its
-- people some hunger; a shelter's stores spare a little more.
--
-- The cities keep `sick` (the turns they have been sick, nil when well),
-- `immune` (the turn till which they can't catch it again), `shut`,
-- `dead` (how many the plague has taken) and `pyre` (the turn of the last
-- death). A unit that carries it keeps `sick`, the turns left. The cells
-- keep `fallow`, a farm abandoned. game.cataclysm keeps `zero` (the first
-- sick town's id, from the omen's last turn) and `seeded` (the stages that
-- have had their outbreak). The game emits "terrain" for every hex that
-- changes, "sicken" for every town that falls sick, "mend" for one that
-- mends, "pestilence" for a death, "rats" for a swarm out, "great" for the
-- great pestilence, and "plague" as each stage begins. Nothing here draws.

local D = require "src.defs"
local Cat = require "src.cataclysm"
local Beasts = require "src.beasts"

local max, min, floor = math.max, math.min, math.floor

local Plague = {
    stages = { "omen", "fever", "dying", "dance" },
    names = { omen = "THE OMEN", fever = "THE FEVER", dying = "THE GREAT DYING", dance = "THE DANCE OF DEATH" },
    words = { omen = "OMEN", fever = "FEVER", dying = "GREAT DYING", dance = "DANCE OF DEATH" },
    turns = D.PLAGUE, event = "plague", ward = "lazaret", ended = "THE PLAGUE HAS EMPTIED THE WORLD",
    -- It shows its first sick town in the omen's last turn.
    early = true,
}

local P = D.PLAGUE

local function isRat(u) return u.owner == Beasts.WILD and u.def.vermin end
Plague.isRat = isRat

local function on(game) return Cat.is(game, "plague") end

--- the towns ------------------------------------------------------------------------------

-- Is city `city` sick now?
function Plague.sick(city) return city.sick ~= nil end

-- Can't it catch it, having mended?
function Plague.immune(game, city) return (city.immune or 0) > game.turn end

-- Is it shut?
function Plague.shut(city) return city.shut == true end

local function lazaret(city) return city.buildings ~= nil and city.buildings.lazaret ~= nil end

-- Can the sickness take city `city` now?
local function open(game, city) return not city.sick and not Plague.immune(game, city) end

-- Shuts city `city` or opens it again (`shut` true or false; by default,
-- the other way from how it is). Answers how it is now.
function Plague.setShut(game, city, shut)
    if shut == nil then shut = not city.shut end
    if (city.shut == true) == shut then return shut end
    city.shut = shut or nil
    game:tell(city.owner, city.name .. (shut and " IS SHUT: NO ONE COMES IN OR GOES OUT" or " IS OPEN AGAIN"))
    game:emit({ kind = "shut", cell = city.cell, shut = shut })
    return shut
end

-- City `city` falls sick; `how` says how it came, if it is told.
function Plague.infect(game, city, how)
    if not open(game, city) then return false end
    city.sick = 1
    game:tell(city.owner, "THE PLAGUE HAS COME TO " .. city.name .. (how and (", " .. how) or ""))
    -- The player hears of the towns they know falling sick.
    if city.owner ~= 1 and game.players[1] and game.players[1].explored[city.cell] then
        game:tell(1, "THE PLAGUE HAS COME TO " .. city.name)
    end
    game:emit({ kind = "sicken", cell = city.cell, city = city })
    return true
end

local function mend(game, city)
    city.sick = nil
    city.immune = game.turn + P.immunity
    game:tell(city.owner, city.name .. " HAS MENDED: THE PLAGUE HAS PASSED IT BY")
    game:emit({ kind = "mend", cell = city.cell, city = city })
end

-- How many towns are sick now.
function Plague.count(game)
    local n = 0
    for _, c in ipairs(game.cities) do if c.sick then n = n + 1 end end
    return n
end

-- The first sick town, seen coming in the omen's last turn (until it falls
-- sick), or nil.
function Plague.zero(game)
    local c = game.cataclysm
    if not c or c.kind ~= "plague" or not c.zero then return nil end
    for _, city in ipairs(game.cities) do if city.id == c.zero then return city end end
end

-- The great pestilence's coming: the turns to it, once it is told.
function Plague.greatComing(game)
    if not on(game) or game.turn < P.warn or game.turn >= P.great then return nil end
    return P.great - game.turn
end

--- what it does to what a town makes ---------------------------------------------------------

-- Food on hex `cell`, `f` before the plague has its say: none where rats are.
function Plague.food(game, cell, f)
    local m = game.mil[cell.id]
    if m and isRat(m) then return 0 end
    return f
end

-- The food city `city` loses this turn: the sick to the sickness, the well
-- to fear. A lazaret spares some.
function Plague.thirst(game, city)
    local s = Cat.stage(game)
    if not s then return 0 end
    local t = (city.sick and P.sick[s] or P.fear[s]) or 0
    if t > 0 and lazaret(city) then t = max(0, t - P.ward) end
    return t
end

-- Does city `city` not grow now: sick, or shut.
function Plague.stunted(game, city) return city.sick ~= nil or city.shut == true end

-- The gold city `city` makes, `g` before: none, shut.
function Plague.gold(game, city, g)
    if city.shut then return 0 end
    return g
end

-- A city founded by unit `u`: sick, if they carried it.
function Plague.founded(game, u, city)
    if u.sick and Cat.stage(game) and Cat.stage(game) ~= "omen" then Plague.infect(game, city, "BROUGHT BY ITS SETTLERS") end
end

-- What the hover says of hex `cell`: how its town is.
function Plague.describe(game, cell)
    local c = cell.city
    if not c then return nil end
    local bits = {}
    if c.sick then bits[#bits + 1] = "SICK WITH THE PLAGUE"
    elseif Plague.immune(game, c) then bits[#bits + 1] = "MENDED, SPARED FOR " .. (c.immune - game.turn) .. " TURNS" end
    if c.shut then bits[#bits + 1] = "SHUT" end
    if #bits == 0 then return nil end
    return "- " .. table.concat(bits, ", ")
end

--- the sickness in a town ---------------------------------------------------------------------

-- One of city `city`'s farms left to the weeds: no one to work it.
local function fallow(game, city)
    local list = {}
    for _, cell in ipairs(game.cells) do
        if cell.ownerCity == city and cell.improvement == "farm" then list[#list + 1] = cell end
    end
    if #list == 0 then return end
    local cell = list[game.rng:random(#list)]
    cell.improvement = nil
    cell.fallow = true
    if cell.resource == "wheat" and game.rng:random() < 0.5 then cell.resource = nil end
    game:tell(city.owner, "A FARM OF " .. city.name .. " LIES FALLOW: THERE IS NO ONE TO WORK IT")
    game:emit({ kind = "terrain", cell = cell.id })
end

-- City `city` loses `n` of its people to the plague (never the last).
local function die(game, city, n, quiet)
    n = min(n, city.pop - 1)
    if n <= 0 then return 0 end
    city.pop = city.pop - n
    city.dead = (city.dead or 0) + n
    city.pyre = game.turn
    game:assignWork(city)
    if not quiet then
        game:tell(city.owner, n == 1 and (city.name .. " HAS LOST ONE OF ITS PEOPLE TO THE PLAGUE")
            or (city.name .. " HAS LOST " .. n .. " OF ITS PEOPLE TO THE PLAGUE"))
    end
    game:emit({ kind = "pestilence", cell = city.cell, city = city, n = n })
    if game.rng:random() < P.fallow then fallow(game, city) end
    return n
end

local function sickTurn(game, city, s)
    city.sick = city.sick + 1
    local death = P.death[s] or 0
    if lazaret(city) then death = death * P.lazaretDeath end
    if game.rng:random() < death then die(game, city, 1) end
    if city.sick > P.mendAfter then
        local m = (P.mend[s] or 0) + (lazaret(city) and P.lazaretMend or 0)
        if game.rng:random() < m then mend(game, city) end
    end
end

--- from town to town -----------------------------------------------------------------------

local function both(game, a, b, f) return f(game, game.cells[a.cell]) and f(game, game.cells[b.cell]) end

local function riverside(game, cell) return game:onRiver(cell) end
local function seaside(game, cell) return game:coastal(cell) end

-- The chance a turn sick city `a` gives it to well city `b`, in stage `s`.
function Plague.chance(game, a, b, s)
    local d = game:dist(game.cells[a.cell], game.cells[b.cell])
    if d > P.reach then return 0 end
    local p = P.spread[s] or 0
    if d > 3 then p = p * 0.5 ^ (d - 3) end
    if both(game, a, b, riverside) or both(game, a, b, seaside) then p = p * P.water end
    if a.shut then p = p * P.shut end
    if b.shut then p = p * P.shut end
    return p
end

local function spread(game, s)
    local sick, catch = {}, {}
    for _, c in ipairs(game.cities) do if c.sick then sick[#sick + 1] = c end end
    for _, b in ipairs(game.cities) do
        if open(game, b) then
            for _, a in ipairs(sick) do
                if game.rng:random() < Plague.chance(game, a, b, s) then
                    catch[#catch + 1] = { b, a }
                    break
                end
            end
        end
    end
    for _, e in ipairs(catch) do
        local from = e[2]
        Plague.infect(game, e[1], from.owner == e[1].owner and ("FROM " .. from.name) or ("FROM " .. from.name .. " OF " .. game.players[from.owner].name))
    end
end

-- The cities beside hex `cell`, and on it.
local function citiesBy(game, cell)
    local out = {}
    if cell.city then out[1] = cell.city end
    for _, n in ipairs(game:neighbours(cell)) do if n.city then out[#out + 1] = n.city end end
    return out
end

local function ratsBy(game, cell)
    for _, n in ipairs(game:neighbours(cell)) do
        local m = game.mil[n.id]
        if m and isRat(m) then return true end
    end
    return false
end

-- The civilizations' people: those that carry it sicken (and may die of
-- it) and bring it where they go; those that don't may catch it.
local function people(game, s)
    local list = {}
    for _, u in ipairs(game.units) do
        if u.owner ~= Beasts.WILD then list[#list + 1] = u end
    end
    for _, u in ipairs(list) do
        if not u.dead then
            local cell = game.cells[u.cell]
            if u.sick then
                for _, c in ipairs(citiesBy(game, cell)) do
                    if open(game, c) then
                        local p = P.bring[s] or 0
                        if c.shut and c.cell ~= u.cell then p = p * P.shut end
                        if game.rng:random() < p then
                            Plague.infect(game, c, "BROUGHT BY A " .. u.def.name .. (u.owner ~= c.owner and (" OF " .. game.players[u.owner].name) or ""))
                        end
                    end
                end
                u.sick = u.sick - 1
                if u.sick <= 0 then
                    u.sick, u.immune = nil, game.turn + P.immunity
                end
                Cat.hurt(game, u, P.sickHp, "DIED OF THE PLAGUE")
            elseif (u.immune or 0) <= game.turn then
                local p = 0
                if cell.city and cell.city.sick then p = P.catchIn
                else
                    for _, c in ipairs(citiesBy(game, cell)) do if c.sick then p = P.catchBy break end end
                end
                if ratsBy(game, cell) then p = max(p, P.catchRats) end
                if p > 0 and game.rng:random() < p then
                    u.sick = P.carry
                    game:tell(u.owner, "OUR " .. u.def.name .. " CARRIES THE PLAGUE")
                    game:emit({ kind = "carrier", cell = u.cell, unit = u })
                end
            end
        end
    end
end

--- the rats --------------------------------------------------------------------------------

-- The well towns within `n` of hex `cell`, nearest first.
local function wellNear(game, cell, n)
    local out = {}
    for _, c in ipairs(game.cities) do
        local d = game:dist(cell, game.cells[c.cell])
        if d <= n and open(game, c) then out[#out + 1] = { d = d, city = c } end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function ratsAct(game, s)
    local list = {}
    for _, u in ipairs(game.units) do
        if isRat(u) then
            u.moves = game:maxMoves(u)
            list[#list + 1] = u
        end
    end
    for _, u in ipairs(list) do
        u.life = (u.life or P.ratLife) - 1
        if u.life <= 0 then
            game:removeUnit(u)
            game:emit({ kind = "scatter", cell = u.cell, unit = u })
        else
            local here = game.cells[u.cell]
            local beside = false
            for _, c in ipairs(citiesBy(game, here)) do
                if open(game, c) then
                    beside = true
                    local p = P.ratBite
                    if c.shut then p = p * P.shut * 2 end
                    if game.rng:random() < p then Plague.infect(game, c, "BROUGHT BY RATS") end
                end
            end
            if not beside then
                local went = false
                for _, t in ipairs(wellNear(game, here, u.def.sense)) do
                    local path = game:path(u, t.city.cell, true)
                    if path and #path > 0 then
                        game:walk(u, path)
                        went = true
                        break
                    end
                end
                if not went then
                    -- Nowhere to run for: a step about.
                    local best, bv
                    for _, n in ipairs(game:neighbours(here)) do
                        if game:canStand(u, n) and game:stepCost(u, here, n) then
                            local v = game.rng:random()
                            if not bv or v > bv then best, bv = n, v end
                        end
                    end
                    if best then game:step(u, best.id) end
                end
            end
            u.dest = nil
        end
    end
end

local function ratsOut(game, s)
    local chance = P.rats[s] or 0
    if chance <= 0 then return end
    local out = 0
    for _, u in ipairs(game.units) do if isRat(u) then out = out + 1 end end
    for _, c in ipairs(game.cities) do
        if c.sick and out < (P.ratMax[s] or 0) and game.rng:random() < chance then
            local cell = game.cells[c.cell]
            local spots = {}
            for _, n in ipairs(game:neighbours(cell)) do
                if game:passable(n) and not n.city and not game.mil[n.id] and not game.civ[n.id] then spots[#spots + 1] = n end
            end
            if #spots > 0 then
                local at = spots[game.rng:random(#spots)]
                local u = game:addUnit("rats", Beasts.WILD, at.id)
                u.home, u.life = c.cell, P.ratLife
                out = out + 1
                game:tell(c.owner, "RATS ARE RUNNING OUT OF " .. c.name)
                game:emit({ kind = "rats", cell = at.id, unit = u })
            end
        end
    end
end

--- outbreaks ---------------------------------------------------------------------------------

-- Where an outbreak starts: a big town, on the water most of all, far from
-- the sick ones; less in a shut one.
local function siteOutbreak(game)
    local best, total, list = nil, 0, {}
    for _, c in ipairs(game.cities) do
        if open(game, c) then
            local cell = game.cells[c.cell]
            local w = 1 + c.pop
            if game:coastal(cell) then w = w + 3 end
            if game:onRiver(cell) then w = w + 2 end
            local near = math.huge
            for _, o in ipairs(game.cities) do
                if o.sick then near = min(near, game:dist(cell, game.cells[o.cell])) end
            end
            if near ~= math.huge then w = w * min(1, (near / 8) ^ 2) end
            if c.shut then w = w * P.shut end
            list[#list + 1] = { c, w }
            total = total + w
        end
    end
    local r = game.rng:random() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then best = e[1] break end
    end
    return best or (list[#list] and list[#list][1])
end

local function outbreak(game, s)
    local c = game.cataclysm
    c.seeded = c.seeded or {}
    if c.seeded[s] then return end
    c.seeded[s] = true
    for k = 1, P.seeds[s] or 0 do
        local city = (k == 1 and s == "fever") and Plague.zero(game) or nil
        if not city or not open(game, city) then city = siteOutbreak(game) end
        if city then Plague.infect(game, city, s == "fever" and "THE FIRST OF ALL" or "FROM OVER THE SEA") end
    end
    c.zero = nil
end

local function great(game)
    local sick, catch = {}, {}
    for _, c in ipairs(game.cities) do if c.sick then sick[#sick + 1] = c end end
    for _, b in ipairs(game.cities) do
        if open(game, b) and not b.shut then
            for _, a in ipairs(sick) do
                if game:dist(game.cells[a.cell], game.cells[b.cell]) <= P.reach then catch[#catch + 1] = b break end
            end
        end
    end
    game:tell(nil, "THE GREAT PESTILENCE HAS COME")
    for _, c in ipairs(sick) do
        local n = floor(c.pop * (lazaret(c) and P.lazaretLoss or P.greatLoss) + 0.5)
        die(game, c, max(1, n))
    end
    for _, c in ipairs(catch) do Plague.infect(game, c, "IN THE GREAT PESTILENCE") end
    game:emit({ kind = "great" })
end

--- the turn ----------------------------------------------------------------------------------

Plague.tell = {
    omen = function() return ("THE CROWS ARE GATHERING. THE FEVER COMES IN %d TURNS"):format(P.fever - P.omen) end,
    fever = function() return "THE FEVER: THE PLAGUE GOES FROM TOWN TO TOWN. BUILD LAZARETS, SHUT YOUR GATES" end,
    dying = function() return "THE GREAT DYING: RATS RUN FROM THE SICK TOWNS, AND THE WELL GO HUNGRY FOR FEAR" end,
    dance = function() return ("THE DANCE OF DEATH. THE WORLD ENDS IN %d TURNS"):format(D.LAST_TURN - P.dance + 1) end,
}

function Plague.play(game, stage)
    local c = game.cataclysm
    if stage == "omen" then
        -- On its last turn, the first sick town is seen.
        if game.turn == P.fever - 1 and not c.zero then
            local city = siteOutbreak(game)
            if city then
                c.zero = city.id
                game:tell(nil, "A FEVER IS SEEN IN " .. city.name .. " OF " .. game.players[city.owner].name)
                game:emit({ kind = "zero", cell = city.cell, city = city })
            end
        end
        return
    end
    outbreak(game, stage)
    if game.rng:random() < (P.flare[stage] or 0) then
        local city = siteOutbreak(game)
        if city then Plague.infect(game, city, "FROM OVER THE SEA") end
    end
    ratsAct(game, stage)
    people(game, stage)
    spread(game, stage)
    for _, city in ipairs(game.cities) do
        if city.sick then sickTurn(game, city, stage) end
    end
    ratsOut(game, stage)
    if game.turn == P.warn then
        game:tell(nil, ("THE GREAT PESTILENCE WILL COME IN %d TURNS. SHUT THE TOWNS NEAR THE SICK"):format(P.great - P.warn))
    end
    if game.turn == P.great then great(game) end
end

return Plague
