-- A city's quarters: the hexes it spills over into as it grows, past what
-- its middle hex can house. This is how they are laid together, the part
-- the rules and the pictures share: which of a hex's edges it shares with
-- another of the city's hexes (a street runs across, no wall stands on it),
-- which corners of the city's outline carry its towers (each tower stood
-- once, by one hex), the way each quarter's street comes in from the hex it
-- grew out of, and the gate where the street leaves on the far side.
--
-- Edge k of a hex faces neighbour k (src/hex.lua: 0 east, then clockwise);
-- its corner k is the one at 60k - 30 degrees, between edges k - 1 and k.

local H = require "src.hex"

local Q = {}

-- The stages a quarter fills in by, as the citizens it houses come: the
-- houses nearest the hex it grew out of first, out to its far edge.
Q.STAGES = 3
Q.HOUSES = { 4, 7, 11 }

local function key(c, r) return c .. ":" .. r end

-- `hexes`: the city's hexes in the order it took them, the middle first,
-- each { c = , r = , ... }. Answers, for each in the same order:
-- { joins = { [k] = true }, towers = { [k] = true }, toward = k or nil,
--   gate = k or nil }.
function Q.fabric(hexes)
    local at = {}
    for n, h in ipairs(hexes) do at[key(h.c, h.r)] = n end
    local function inside(c, r) return at[key(c, r)] end
    local out = {}
    for n, h in ipairs(hexes) do
        local f = { joins = {}, towers = {} }
        local nb = {}
        for k = 0, 5 do
            nb[k] = inside(H.step(h.c, h.r, k))
            if nb[k] then f.joins[k] = true end
        end
        -- The street comes in from the hex it grew out of: the earliest
        -- of the city's hexes beside it.
        if n > 1 then
            local best
            for k = 0, 5 do
                if nb[k] and nb[k] < n and (not best or nb[k] < nb[best]) then best = k end
            end
            f.toward = best
            -- And goes on out through the far side, where nothing of the
            -- city's stands.
            if best and not nb[(best + 3) % 6] then f.gate = (best + 3) % 6 end
        end
        -- Corner k is on the city's outline if one or two of the three hexes
        -- meeting there are the city's; the lowest of them stands the tower.
        for k = 0, 5 do
            local a, b = nb[(k + 5) % 6], nb[k]
            local count = 1 + (a and 1 or 0) + (b and 1 or 0)
            if count < 3 and n <= math.min(a or n, b or n) then f.towers[k] = true end
        end
        out[n] = f
    end
    return out
end

--- the rules --------------------------------------------------------------------------
--
-- A quarter is a cell whose `quarter` is the city it belongs to; the city
-- keeps their ids in the order it took them (`city.quarters`). A sacked one
-- has `sacked` turns left before it houses anyone again.

local D = require "src.defs"

local function list(city)
    city.quarters = city.quarters or {}
    return city.quarters
end

-- The city's hexes, its middle first, as Q.fabric takes them.
function Q.hexes(game, city)
    local out = { game.cells[city.cell] }
    for _, id in ipairs(list(city)) do out[#out + 1] = game.cells[id] end
    return out
end

-- How many citizens it has room for.
function Q.housing(game, city)
    local n = D.QUARTER.home
    for _, id in ipairs(list(city)) do
        if not game.cells[id].sacked then n = n + D.QUARTER.each end
    end
    return n
end

-- How the city's growth goes for room: 1 at full pace, `slow` at its
-- housing, 0 when it is full past that.
function Q.pace(game, city)
    local room = Q.housing(game, city)
    if city.pop >= room + D.QUARTER.over then return 0 end
    if city.pop >= room then return D.QUARTER.slow end
    return 1
end

-- How full the nth quarter is (1..3, as M.quarter draws it), by the citizens
-- it houses past the middle and the quarters before it.
function Q.stage(city, n)
    local fill = city.pop - D.QUARTER.home - D.QUARTER.each * (n - 1)
    if fill <= 1 then return 1 end
    if fill <= 3 then return 2 end
    return 3
end

-- What the next quarter costs, or nil if it can have no more.
function Q.cost(city)
    return D.QUARTER.cost[#list(city) + 1]
end

-- Can the city build a quarter on `cell`: land of its own, flat or hills,
-- nothing built on it and no one else's unit in it, beside one of its
-- hexes and within reach of its middle.
function Q.can(game, city, cell)
    if not cell or not Q.cost(city) then return false end
    if cell.owner ~= city.owner or cell.city or cell.quarter or cell.lair then return false end
    if game:isWater(cell) or cell.elev == "mountain" or D.TERRAIN[cell.terrain].noCity then return false end
    if cell.fire or cell.lava or (cell.rift or 0) >= 2 or cell.blight or cell.crater then return false end
    local home = game.cells[city.cell]
    if game:dist(home, cell) > D.QUARTER.reach then return false end
    if game:foreignAt(cell, city.owner) then return false end
    for _, n in ipairs(game:neighbours(cell)) do
        if n == home or n.quarter == city then return true end
    end
    return false
end

-- Every hex it could build its next quarter on.
function Q.sites(game, city)
    local out = {}
    if not Q.cost(city) then return out end
    for _, cell in ipairs(game:within(game.cells[city.cell], D.QUARTER.reach)) do
        if Q.can(game, city, cell) then out[#out + 1] = cell end
    end
    return out
end

-- Whether it is time to give a city a quarter: near its housing, and with
-- somewhere to put one.
function Q.due(game, city)
    return Q.cost(city) ~= nil and city.pop >= Q.housing(game, city) - 1 and #Q.sites(game, city) > 0
end

-- The best of its sites, as a governor would choose: what the hex yields
-- worked is given up, so the poorer the better; high ground keeps it from
-- the water, the shore gives it docks, a river a mill.
function Q.best(game, city)
    local best, bv
    for _, cell in ipairs(Q.sites(game, city)) do
        local f, p, g = game:yield(cell)
        local v = -(f * 2 + p * 2 + g) - (cell.resource and 3 or 0) - (cell.improvement and 2 or 0)
        if cell.elev == "hills" then v = v + 2 end
        if game:coastal(cell) and not game:coastal(game.cells[city.cell]) then v = v + 2 end
        if game:onRiver(cell) then v = v + 1 end
        v = v + game.rng:random() * 0.1
        if not bv or v > bv then best, bv = cell, v end
    end
    return best
end

-- The changed hex and its neighbours laid again: a quarter's own ground,
-- and the bridges and walls it shares with them.
local function relay(game, cell)
    game:emit({ kind = "terrain", cell = cell.id })
    for _, n in ipairs(game:neighbours(cell)) do game:emit({ kind = "terrain", cell = n.id }) end
end

-- The city spills over into `cell`: it clears the hex as founding a city
-- does, works it no more, and houses more.
function Q.add(game, city, cell)
    if cell.workedBy then cell.workedBy = nil end
    cell.quarter = city
    cell.owner, cell.ownerCity = city.owner, city
    cell.feature, cell.improvement, cell.felled = nil, nil, nil
    local q = list(city)
    q[#q + 1] = cell.id
    game:assignWork(city)
    relay(game, cell)
    game:emit({ kind = "quarter", cell = cell.id, city = city })
    game:tell(city.owner, "{1} HAS SPILLED OVER INTO A NEW QUARTER", city.name)
end

-- A quarter lost (`why` told to its owner): its people with it, down to
-- what the city has room for now.
function Q.lose(game, city, cell, why)
    cell.quarter, cell.sacked = nil, nil
    local q = list(city)
    for k, id in ipairs(q) do
        if id == cell.id then table.remove(q, k) break end
    end
    if not city.dead then
        local room = Q.housing(game, city)
        if city.pop > room then
            city.pop = math.max(1, room)
            city.food = 0
        end
        game:assignWork(city)
        if why then game:tell(city.owner, why, city.name) end

    end
    relay(game, cell)
end

-- All of a city's quarters gone with it (sunk, razed).
function Q.dropAll(game, city)
    for _, id in ipairs(list(city)) do
        local cell = game.cells[id]
        cell.quarter, cell.sacked = nil, nil
        relay(game, cell)
    end
    city.quarters = {}
end

-- What has become of a quarter's hex that it can't stand: the news of it
-- ({1}, the city), or nil.
local function ruined(game, cell)
    if game:isWater(cell) then return "THE WATER HAS TAKEN {1}'S QUARTER" end
    if cell.fire then return "FIRE HAS TAKEN {1}'S QUARTER" end
    if cell.lava then return "THE FIRE OF THE EARTH HAS TAKEN {1}'S QUARTER" end
    if (cell.rift or 0) >= 2 then return "THE EARTH HAS SWALLOWED {1}'S QUARTER" end
    if cell.crater and cell.crater > 0 then return "A STONE FROM THE SKY HAS TAKEN {1}'S QUARTER" end
    if cell.blight then return "THE ABYSS HAS TAKEN {1}'S QUARTER" end
end

-- At the start of the city's owner's turn: quarters the cataclysm has
-- taken are lost; one an enemy stands in is sacked; one sacked mends once
-- left in peace long enough.
function Q.tend(game, city)
    local q = list(city)
    for k = #q, 1, -1 do
        local cell = game.cells[q[k]]
        local why = ruined(game, cell)
        if why then
            Q.lose(game, city, cell, why)
        else
            local m = game.mil[cell.id]
            if m and m.owner ~= city.owner and not m.def.civilian then
                if not cell.sacked then game:tell(city.owner, "THE ENEMY HAS SACKED {1}'S QUARTER", city.name) end
                cell.sacked = D.QUARTER.mend
            elseif cell.sacked then
                cell.sacked = cell.sacked - 1
                if cell.sacked <= 0 then
                    cell.sacked = nil
                    game:tell(city.owner, "{1}'S QUARTER IS REBUILT", city.name)

                end
            end
        end
    end
end

return Q
