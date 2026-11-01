-- The wild, for the rules: wolves, bears, crocodiles and sea serpents that go
-- for whoever comes near; boar and aurochs that only fight what fights them;
-- wild horses that run, and can be tamed; and the dens, caves and hives on
-- the map that more of them come out of.
--
-- They are units like any other, owned by no civilization: owner 0, the
-- wild's own player (`Game.WILD`), which is kept at players[0] so that
-- everything that goes through the civilizations with ipairs passes it by.
-- They walk and fight by the same rules (src/game.lua), and play their turn
-- after the last civilization's (Beasts.play). Their numbers are in
-- src/defs.lua (D.BEASTS, D.LAIRS, D.WILD). Nothing here draws.

local D = require "src.defs"

local floor, min = math.floor, math.min

local Beasts = {}

Beasts.WILD = 0

-- The wild's player: no cities, no techs, sees nothing (it knows).
function Beasts.player()
    return { id = Beasts.WILD, wild = true, name = "THE WILD", civ = { name = "THE WILD", look = "wild", cities = {} },
        human = false, gold = 0, science = 0, techs = {}, explored = {}, visible = {}, cityNames = 0,
        alive = true, everCity = false }
end

function Beasts.isBeast(u) return u.owner == Beasts.WILD end

--- where they go -------------------------------------------------------------------

-- Can beast u be on this cell: its own ground, never a city.
function Beasts.canEnter(game, u, cell)
    if cell.city then return false end
    local lives = u.def.lives
    if lives == "ocean" then return cell.terrain == "ocean" end
    -- A tentacle (src/demons.lua): in the coast's water by the land.
    if lives == "shore" then
        if cell.terrain ~= "coast" then return false end
        for _, n in ipairs(game:neighbours(cell)) do if not game:isWater(n) then return true end end
        return false
    end
    if game:isWater(cell) or cell.elev == "mountain" then return false end
    if lives == "river" then return game:onRiver(cell) end
    return true
end

-- How far the nearest city is from a cell (a big number with none).
local function cityDistance(game, cell)
    local best = math.huge
    for _, c in ipairs(game.cities) do
        best = min(best, game:dist(cell, game.cells[c.cell]))
    end
    return best
end

-- The civilizations' units within n of a cell, nearest first.
local function people(game, cell, n)
    local out = {}
    for _, m in ipairs(game:within(cell, n)) do
        for _, slot in ipairs({ game.mil, game.civ }) do
            local v = slot[m.id]
            if v and v.owner ~= Beasts.WILD then out[#out + 1] = v end
        end
    end
    table.sort(out, function(a, b)
        return game:dist(cell, game.cells[a.cell]) < game:dist(cell, game.cells[b.cell])
    end)
    return out
end
Beasts.people = people

--- making the map wild ---------------------------------------------------------------

local function shuffled(game, list)
    for k = #list, 2, -1 do
        local j = game.rng:random(k)
        list[k], list[j] = list[j], list[k]
    end
    return list
end

-- Is the cell clear of every civilization's first units and every city by
-- D.WILD.clear, and of every lair and beast by `gap`?
local function roomy(game, cell, starts, gap)
    for _, s in ipairs(starts) do
        if game:dist(cell, s) < D.WILD.clear then return false end
    end
    if cityDistance(game, cell) < D.WILD.clear then return false end
    for _, l in ipairs(game.lairs) do
        if game:dist(cell, game.cells[l.cell]) < gap then return false end
    end
    for _, u in ipairs(game.units) do
        if u.owner == Beasts.WILD and game:dist(cell, game.cells[u.cell]) < gap then return false end
    end
    return true
end

-- A beast of `kind` on the cell, or the nearest free one to it its kind may
-- stand on. Its home is where it was put.
function Beasts.spawn(game, kind, cellId, home)
    local def = D.BEASTS[kind]
    local probe = { def = def, owner = Beasts.WILD }
    local at
    for _, cell in ipairs(game:within(game.cells[cellId], 1)) do
        if not game.mil[cell.id] and not game.civ[cell.id] and Beasts.canEnter(game, probe, cell)
            and (cell.id == cellId or not at) then
            if cell.id == cellId then at = cell.id break end
            at = at or cell.id
        end
    end
    if not at then return nil end
    local u = game:addUnit(kind, Beasts.WILD, at)
    u.home = home or at
    return u
end

function Beasts.addLair(game, kind, cellId)
    local lair = { kind = kind, cell = cellId, timer = 0, def = D.LAIRS[kind] }
    game.cells[cellId].lair = lair
    game.lairs[#game.lairs + 1] = lair
    return lair
end

-- Lairs and herds over the map at the start, away from where anyone starts.
function Beasts.populate(game)
    local starts = {}
    for _, u in ipairs(game.units) do starts[#starts + 1] = game.cells[u.cell] end
    local land, ocean = 0, 0
    for _, cell in ipairs(game.cells) do
        if game:passable(cell) then land = land + 1 end
        if cell.terrain == "ocean" then ocean = ocean + 1 end
    end
    local W = D.WILD
    local function count(per, of) return floor(of / 100 * per + 0.5) end
    local function place(n, gap, ok, put)
        if n <= 0 then return 0 end
        local list = {}
        for _, cell in ipairs(game.cells) do
            if ok(cell) then list[#list + 1] = cell end
        end
        local made = 0
        for _, cell in ipairs(shuffled(game, list)) do
            if made >= n then break end
            if not game.mil[cell.id] and not game.civ[cell.id] and not cell.lair and roomy(game, cell, starts, gap) then
                if put(cell) then made = made + 1 end
            end
        end
        return made
    end
    local function nextToMountain(cell)
        for _, n in ipairs(game:neighbours(cell)) do if n.elev == "mountain" then return true end end
    end
    local function besideForest(cell)
        for _, n in ipairs(game:neighbours(cell)) do if n.feature == "forest" then return true end end
    end
    local land_ = function(cell) return game:passable(cell) end
    -- The lairs, each with its beasts about it.
    place(count(W.caves, land), 4, function(c) return land_(c) and c.elev == "hills" and nextToMountain(c) end,
        function(cell)
            Beasts.addLair(game, "cave", cell.id)
            Beasts.spawn(game, "bear", cell.id, cell.id)
            return true
        end)
    place(count(W.dens, land), 4, function(c) return land_(c) and (c.feature == "forest" or c.elev == "hills") end,
        function(cell)
            Beasts.addLair(game, "den", cell.id)
            for _ = 1, D.LAIRS.den.keep do Beasts.spawn(game, "wolf", cell.id, cell.id) end
            return true
        end)
    place(count(W.hives, land), 3, function(c) return land_(c) and c.feature == "forest" end,
        function(cell) Beasts.addLair(game, "hive", cell.id) return true end)
    -- The herds.
    game.wildWant = {}
    local herds = {
        boar = { 2, function(c) return land_(c) and (c.feature == "forest" or besideForest(c)) end, 1 },
        aurochs = { 3, function(c) return land_(c) and c.terrain == "grass" and c.elev == "flat" and not c.feature end, 2 },
        horse = { 3, function(c) return land_(c) and c.terrain == "plains" and c.elev == "flat" and not c.feature end, 2 },
        croc = { 3, function(c) return land_(c) and game:onRiver(c) end, 1 },
        serpent = { 5, function(c) return c.terrain == "ocean" end, 1 },
    }
    for _, kind in ipairs({ "serpent", "croc", "aurochs", "horse", "boar" }) do
        local h = herds[kind]
        local n = count(W[kind], kind == "serpent" and ocean or land)
        game.wildWant[kind] = { n = n, ok = h[2], size = h[3] }
        place(n, h[1], h[2], function(cell)
            local first = Beasts.spawn(game, kind, cell.id)
            for _ = 2, h[3] do if first then Beasts.spawn(game, kind, cell.id, first.home) end end
            return first ~= nil
        end)
    end
end

--- what they bring ---------------------------------------------------------------------

-- The city of player `who` nearest a cell, or nil.
local function nearestCity(game, who, cell)
    local best, bd
    for _, c in ipairs(game:citiesOf(who)) do
        local d = game:dist(cell, game.cells[c.cell])
        if not bd or d < bd then best, bd = c, d end
    end
    return best
end

-- Gives `prize` (gold, food, culture) to player `who`, the food and culture
-- to their city nearest `cell`. Answers what was given, as words.
local function give(game, who, prize, cell)
    local p = game.players[who]
    local bits = {}
    -- Glory (the demons' slain, src/demons.lua) counts in the score.
    if prize.glory and prize.glory > 0 then
        p.glory = (p.glory or 0) + prize.glory
        bits[#bits + 1] = "+" .. prize.glory .. " GLORY"
    end
    if prize.gold and prize.gold > 0 then
        p.gold = p.gold + prize.gold
        bits[#bits + 1] = "+" .. prize.gold .. " GOLD"
    end
    local city = nearestCity(game, who, cell)
    if city then
        if prize.food and prize.food > 0 then
            city.food = city.food + prize.food
            bits[#bits + 1] = "+" .. prize.food .. " FOOD TO " .. city.name
        end
        if prize.culture and prize.culture > 0 then
            city.culture = city.culture + prize.culture
            bits[#bits + 1] = "+" .. prize.culture .. " CULTURE"
        end
    end
    return table.concat(bits, ", "), bits[1]
end

-- Beast u was killed by player `by` (nil: by no one).
function Beasts.slain(game, u, by)
    if not by or by == Beasts.WILD then return end
    local cell = game.cells[u.cell]
    local words, first = give(game, by, u.def.loot or {}, cell)
    game:tell(by, u.def.name .. " SLAIN" .. (words ~= "" and (": " .. words) or ""))
    if first then game:emit({ kind = "loot", cell = cell.id, text = first }) end
end

-- What happens when one of a civilization's units comes onto a cell: a lair
-- with nothing left to guard it is cleared; a hive stings and gives its
-- honey; wild horses beside a rider's people are tamed.
function Beasts.arrive(game, u, cell)
    if u.owner == Beasts.WILD or u.dead then return end
    local lair = cell.lair
    if lair and not u.def.civilian then
        local def = lair.def
        if def.sting then
            local taken = min(def.sting, u.hp - 1)
            if taken > 0 then
                u.hp = u.hp - taken
                game:emit({ kind = "hit", cell = cell.id, amount = taken, unit = u })
            end
        end
        Beasts.removeLair(game, lair)
        local words, first = give(game, u.owner, def.prize, cell)
        local what = def.sting and "WILD BEES ROBBED OF THEIR HONEY" or (def.name .. " CLEARED")
        if def.demon then
            what = def.citadel and "THE CITADEL OF THE ABYSS RAZED" or "RIFT SEALED"
            if cell.blight then
                cell.blight = nil
                game:emit({ kind = "terrain", cell = cell.id })
            end
            if def.citadel and Beasts.onRazed then Beasts.onRazed(game, u.owner) end
        end
        game:tell(u.owner, what .. (words ~= "" and (": " .. words) or ""))
        game:emit({ kind = "cleared", cell = cell.id, lair = lair.kind, text = first })
    end
    if not u.def.civilian and game.players[u.owner].techs.horses then
        for _, n in ipairs(game:within(cell, 1)) do
            local h = game.mil[n.id]
            if h and h.owner == Beasts.WILD and h.def.tame and game.players[u.owner].techs[h.def.tame] then
                Beasts.tame(game, h, u.owner)
            end
        end
    end
end

function Beasts.tame(game, h, who)
    local at = h.cell
    game:removeUnit(h)
    local r = game:addUnit("horseman", who, at)
    r.moves = 0
    game:tell(who, "WILD HORSES TAMED: A HORSEMAN JOINS US")
    game:emit({ kind = "tame", cell = at, unit = h, rider = r })
    game:look(game.players[who])
    return r
end

function Beasts.removeLair(game, lair)
    game.cells[lair.cell].lair = nil
    for k, l in ipairs(game.lairs) do
        if l == lair then table.remove(game.lairs, k) break end
    end
    -- Its beasts live on, at home where they are.
    for _, v in ipairs(game.units) do
        if v.owner == Beasts.WILD and v.home == lair.cell then v.home = v.cell end
    end
end

--- their turn --------------------------------------------------------------------------

-- How far beast u will go from home: further when hunting.
local function leashOk(game, u, cell, extra)
    return game:dist(cell, game.cells[u.home or u.cell]) <= u.def.leash + (extra or 0)
end

-- A step to a neighbouring cell it can stand on, chosen by `score` (the
-- highest; nil not at all).
local function stepBy(game, u, score)
    local best, bv
    for _, n in ipairs(game:neighbours(game.cells[u.cell])) do
        if game:canStand(u, n) then
            local v = score(n)
            if v and (not bv or v > bv) then best, bv = n, v end
        end
    end
    if best and game:step(u, best.id) then return true end
    return false
end

-- Strike whoever is next to it that it can, the weakest first.
local function strikeNear(game, u, only)
    local best, bv
    for _, n in ipairs(game:neighbours(game.cells[u.cell])) do
        if game:canAttack(u, n) then
            local t = game.mil[n.id] or game.civ[n.id]
            if t and (not only or t.id == only) then
                local v = (t.def.civilian and 1000 or 0) - (t.hp or 100) - game:defense(t)
                if not bv or v > bv then best, bv = n, v end
            end
        end
    end
    if best then return game:attack(u, best) end
    return false
end

-- Go for unit t: as near as it can along the way, then strike.
local function hunt(game, u, t)
    if strikeNear(game, u, t.id) then return true end
    local goal = game.cells[t.cell]
    local path = game:path(u, t.cell, true)
    if not path then return false end
    local steps = {}
    for _, id in ipairs(path) do
        if not leashOk(game, u, game.cells[id], 2) then break end
        steps[#steps + 1] = id
    end
    if #steps > 0 then game:walk(u, steps) end
    u.dest = nil
    if u.moves > 0 and game:dist(game.cells[u.cell], goal) == 1 then return strikeNear(game, u, t.id) end
    return true
end

-- Ambles a step about home now and then, keeping off the towns.
local function wander(game, u)
    if game.rng:random() > 0.45 then return end
    local here = game.cells[u.cell]
    local home = game.cells[u.home or u.cell]
    stepBy(game, u, function(n)
        if not leashOk(game, u, n) or cityDistance(game, n) < 2 then return nil end
        local v = game.rng:random()
        -- Drawn back home when far from it.
        if game:dist(n, home) < game:dist(here, home) then v = v + 0.3 end
        return v
    end)
end

-- Away from everyone within sense, as far as its moves go.
local function flee(game, u, from)
    for _ = 1, u.def.moves do
        if u.moves <= 0 then return end
        local ok = stepBy(game, u, function(n)
            if not leashOk(game, u, n, 2) then return nil end
            local d = math.huge
            for _, v in ipairs(from) do d = min(d, game:dist(n, game.cells[v.cell])) end
            return d + game.rng:random() * 0.1
        end)
        if not ok then return end
    end
end

local function act(game, u)
    local def = u.def
    local here = game.cells[u.cell]
    local night = D.night(game.turn, game, here)
    local sense = def.sense + ((night and def.night) and 1 or 0)
    if def.temper == "shy" then
        local near = people(game, here, sense)
        if #near > 0 then return flee(game, u, near) end
        return wander(game, u)
    end
    -- Hurt: back home to lick its wounds, striking only what is in the way.
    if u.hp < 35 and u.cell ~= u.home then
        if strikeNear(game, u) then return end
        local home = game.cells[u.home]
        return stepBy(game, u, function(n) return -game:dist(n, home) end)
    end
    if def.temper == "neutral" then
        if u.angry then
            u.angryTurns = (u.angryTurns or 3) - 1
            local foe
            for _, v in ipairs(game.units) do if v.id == u.angry then foe = v end end
            if foe and not foe.dead and game:dist(here, game.cells[foe.cell]) <= 3 and u.angryTurns >= 0 then
                return hunt(game, u, foe)
            end
            u.angry, u.angryTurns = nil, nil
        end
        return wander(game, u)
    end
    -- Hostile: whoever is nearest and in reach of home.
    if strikeNear(game, u) then return end
    for _, t in ipairs(people(game, here, sense)) do
        if leashOk(game, u, game.cells[t.cell], 2) and not game.cells[t.cell].city then
            return hunt(game, u, t)
        end
    end
    return wander(game, u)
end

-- The wild's turn: every beast acts, the lairs send out more, and herds
-- wander in where the land has too few.
function Beasts.play(game)
    local list = {}
    for _, u in ipairs(game.units) do
        if u.owner == Beasts.WILD then list[#list + 1] = u end
    end
    -- The demons (src/demons.lua) act in the cataclysm's turn, not here.
    for _, u in ipairs(list) do
        if not u.dead and u.moves > 0 and not u.def.demon then act(game, u) end
        u.dest = nil
    end
    for _, lair in ipairs(game.lairs) do
        local def = lair.def
        if def.beast then
            lair.timer = lair.timer + 1
            local n = 0
            for _, v in ipairs(game.units) do
                if v.owner == Beasts.WILD and v.home == lair.cell then n = n + 1 end
            end
            local cell = game.cells[lair.cell]
            if n < def.keep and lair.timer >= def.every and #people(game, cell, 3) == 0 then
                lair.timer = 0
                Beasts.spawn(game, def.beast, lair.cell, lair.cell)
            end
        end
    end
    if game.wildWant and game.turn % D.WILD.herds == 0 then
        local have = {}
        for _, v in ipairs(game.units) do
            if v.owner == Beasts.WILD then have[v.kind] = (have[v.kind] or 0) + 1 end
        end
        for _, kind in ipairs({ "serpent", "croc", "aurochs", "horse", "boar" }) do
            local want = game.wildWant[kind]
            if want and (have[kind] or 0) < want.n * want.size then
                -- Somewhere no one sees, away from the towns.
                local list2 = {}
                for _, cell in ipairs(game.cells) do
                    if want.ok(cell) and not game.mil[cell.id] and cityDistance(game, cell) >= D.WILD.clear then
                        local seen = false
                        for _, p in ipairs(game.players) do seen = seen or p.visible[cell.id] end
                        if not seen then list2[#list2 + 1] = cell end
                    end
                end
                if #list2 > 0 then Beasts.spawn(game, kind, list2[game.rng:random(#list2)].id) end
            end
        end
    end
end

-- The strength a beast adds in the dark (wolves hunt at night).
function Beasts.nightBonus(game, u)
    if u.owner == Beasts.WILD and u.def.night and D.night(game.turn, game, game.cells[u.cell]) then return u.def.night end
    return 0
end

return Beasts
