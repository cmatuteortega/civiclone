-- The sundering: the land itself breaks. One of the cataclysm's kinds
-- (src/cataclysm.lua), on the same turns as the others, by D.QUAKE's:
--
--   OMEN       the ground trembles. On the omen's last turn the great rift
--              is seen: a line across the land, from the sea to the sea,
--              where it will tear.
--   TREMORS    quakes, each seen coming the turn before (its hex marked).
--              A quake hurts what stands near it, shakes the cities near it
--              (a building may come down, people may die), wrecks mines and
--              farms and brings the forests down off the hills; and it
--              cracks the ground: faults open along the edges between the
--              hexes near it, and the faults already open run on. No one
--              walks across an open fault.
--   RIFT       the rift tears the land apart, hex by hex from where it
--              meets the sea: each hex cracks, then splits into a chasm no
--              one can cross, then the sea pours into it, and then it is
--              sea, the land either side of it parted for good. Where the
--              land is pressed together the ranges rise: shallows come up
--              as new land, the flat goes to hills and the hills to
--              mountains. The sea far out heaves now and then and a wave
--              runs in on a shore (seen coming the turn before: the sea
--              draws back).
--   FIRE       the volcanoes wake: an eruption is seen coming the turn
--              before, and pours lava over the land round it, that burns
--              what it covers and sets the forests by it alight, and
--              cools to black rock; ash falls round it on the farms, and
--              leaves the land the richer. More waves. On D.QUAKE.great,
--              told some turns before, the great quake: the whole rift
--              opens to the sea at once, every city shakes, and a great
--              wave runs in on every city by the sea.
--
-- What holds it off is the buttress (D.BUILDINGS.buttress): half the harm a
-- quake does the city, no building brought down and no one killed by one,
-- no fault opened on its land, and less fear. A levee keeps a wave out of
-- a city, and a shelter (D.SHELTER) halves every blow, as ever.
--
-- The cells keep what has happened to them: `fault` (the edges cracked
-- open: fault[k] for the edge towards neighbour k, set on both sides),
-- `riftLine` (where the rift will tear: its place along it), `rift` (how
-- far it has: 1 cracked, 2 a chasm, 3 the sea coming in), `riftAngle`
-- (which way the rift runs through it), `sundered` (it was land and the
-- rift has made it sea), `rangeLine` (where a range will rise), `raised`
-- (it was sea and has risen), `volcano`, `erupting` (turns its crater still
-- glows), `lava` (turns it still burns), `basalt` (lava cooled on it),
-- `ashfall` (turns the ash still lies), `soil` (the ash has made it rich).
-- game.cataclysm keeps `marks` ({ [cell id] = "quake" | "erupt" | "wave" },
-- what strikes as the next turn begins), `rift` (the rift's hexes in order),
-- `opened` (how many of them have begun to tear), `ranges` (each range's
-- hexes), `volcanoes` and `waveFrom` (the hex out at sea each wave comes
-- from, by the shore hex it strikes).
--
-- The game emits "terrain" for every hex that changes; "tremor" for every
-- quake (`cell`, `reach`, `turn`), "fault" for every fault opened (`cell`,
-- `k`), "sunder" for every step of the rift (`cell`, `step`, `turn`),
-- "uplift" for every hex that rises (`cell`, `turn`), "erupt" for every
-- eruption (`cell`, `lava`: the hexes its lava took, `turn`), "wave" for
-- every hex of the shore a wave strikes (`cell`, `from`, `turn`), "mark"
-- when new marks are laid, "greatquake" as the great quake strikes, and
-- "sundering" as each stage begins. Nothing here draws.

local D = require "src.defs"
local H = require "src.hex"
local Cat = require "src.cataclysm"

local max, min, floor, abs = math.max, math.min, math.floor, math.abs

local Q = {
    stages = { "omen", "tremors", "rift", "fire" },
    names = { omen = "THE OMEN", tremors = "THE TREMORS", rift = "THE SUNDERING", fire = "THE FIRE BELOW" },
    words = { omen = "OMEN", tremors = "TREMORS", rift = "SUNDERING", fire = "FIRE BELOW" },
    turns = D.QUAKE, event = "sundering", ward = "buttress", ended = "THE WORLD HAS BROKEN APART",
    -- It marks where its first quakes strike, and shows the rift, in the
    -- omen's last turn.
    early = true,
}

local function quaking(game)
    local c = game.cataclysm
    return c and c.kind == "quake" and c or nil
end

local function land(game, cell) return not game:isWater(cell) end

-- Does the hex belong to a city that has shored itself up?
local function braced(cell) return Cat.warded(cell, "buttress") end
Q.braced = braced

-- Where hex `cell` is, for the news: "NEAR ROME" by the nearest city
-- within five, else what the land is.
local function where(game, cell)
    local best, bd
    for _, c in ipairs(game.cities) do
        local d = game:dist(cell, game.cells[c.cell])
        if d <= 5 and (not bd or d < bd) then best, bd = c, d end
    end
    if best then return bd == 0 and ("AT " .. best.name) or ("NEAR " .. best.name) end
    return "FAR FROM ANY TOWN"
end
Q.where = where

local function buttressed(city) return city.buildings ~= nil and city.buildings.buttress ~= nil end

-- A blow of `amount` to city `city` from the shaking: halved by a buttress
-- (and again by a shelter, as Cat.harm does).
local function shake(game, city, amount)
    if buttressed(city) then amount = floor(amount * 0.5 + 0.5) end
    return Cat.harm(game, city, amount)
end

--- what it does to what the land yields --------------------------------------------------

-- Food on hex `cell`, `f` before the sundering has its say: lava and a
-- chasm yield nothing, ash buries the farms, black rock is poor, and the
-- ash leaves the soil rich.
function Q.food(game, cell, f)
    if cell.lava or (cell.rift or 0) >= 2 then return 0 end
    if cell.ashfall and cell.improvement == "farm" then f = f - D.QUAKE.ashFarm end
    if cell.basalt then f = f - 1 end
    if cell.soil then f = f + D.QUAKE.soil end
    return max(0, f)
end

-- The food city `city` loses this turn to fear; a buttress spares it some.
function Q.thirst(game, city)
    local s = Cat.stage(game)
    local t = s and D.QUAKE.fear[s] or 0
    if t > 0 and buttressed(city) then t = max(0, t - D.QUAKE.ward) end
    return t
end

--- faults -----------------------------------------------------------------------------------

-- Is there an open fault along the edge between two neighbouring hexes?
function Q.faultBetween(game, a, b)
    if not a.fault then return false end
    local k = H.dirTo(a.c, a.r, b.c, b.r)
    return k ~= nil and a.fault[k] == true
end

-- Can a fault open along edge k of hex `cell`: land both sides, no river
-- along it, no city on either side nor a buttress's land, not open already,
-- nor across the rift.
function Q.canFault(game, cell, k)
    local n = game:cell(H.step(cell.c, cell.r, k))
    if not n or not land(game, cell) or not land(game, n) then return false end
    if cell.city or n.city or braced(cell) or braced(n) then return false end
    if cell.fault and cell.fault[k] then return false end
    if cell.river and cell.river[k] then return false end
    if (cell.rift or 0) >= 2 or (n.rift or 0) >= 2 then return false end
    return true
end

-- Opens a fault along edge k of hex `cell`, on both sides.
function Q.openFault(game, cell, k)
    local n = game:cell(H.step(cell.c, cell.r, k))
    cell.fault = cell.fault or {}
    n.fault = n.fault or {}
    cell.fault[k] = true
    n.fault[(k + 3) % 6] = true
    game:emit({ kind = "fault", cell = cell.id, k = k, turn = game.turn })
    game:emit({ kind = "terrain", cell = cell.id })
    game:emit({ kind = "terrain", cell = n.id })
end

-- The edges a fault already open could run on to: those that meet it at a
-- corner. Answers { { cell, k }, ... }.
local function onward(game, cell, k)
    local out = {}
    local n = game:cell(H.step(cell.c, cell.r, k))
    -- Round each end of the edge: the hex's own edges either side, and the
    -- neighbour's.
    for _, d in ipairs({ -1, 1 }) do
        out[#out + 1] = { cell, (k + d) % 6 }
        if n then out[#out + 1] = { n, (k + 3 - d) % 6 } end
    end
    return out
end

-- Cracks `n` edges open round hex `cell`, within `reach`: running on from
-- the faults already open there first, then anywhere.
local function crack(game, cell, n, reach)
    local rng = game.rng
    local near = game:within(cell, reach)
    for _ = 1, n do
        local options = {}
        for _, h in ipairs(near) do
            if h.fault then
                for k = 0, 5 do
                    if h.fault[k] then
                        for _, o in ipairs(onward(game, h, k)) do
                            if Q.canFault(game, o[1], o[2]) then options[#options + 1] = o end
                        end
                    end
                end
            end
        end
        if #options == 0 or rng:random() < 0.3 then
            for _, h in ipairs(near) do
                for k = 0, 5 do
                    if Q.canFault(game, h, k) then options[#options + 1] = { h, k } end
                end
            end
        end
        if #options == 0 then return end
        local o = options[floor(rng:random() * #options) + 1]
        Q.openFault(game, o[1], o[2])
    end
end

-- The faults run on: `n` edges more, each from one already open.
local function spread(game, n)
    local options = {}
    for _, cell in ipairs(game.cells) do
        if cell.fault then
            for k = 0, 5 do
                if cell.fault[k] then
                    for _, o in ipairs(onward(game, cell, k)) do
                        if Q.canFault(game, o[1], o[2]) then options[#options + 1] = o end
                    end
                end
            end
        end
    end
    for _ = 1, n do
        if #options == 0 then return end
        local i = floor(game.rng:random() * #options) + 1
        local o = table.remove(options, i)
        if Q.canFault(game, o[1], o[2]) then Q.openFault(game, o[1], o[2]) end
    end
end

--- moving off what has broken -----------------------------------------------------------

-- Unit u, on hex `cell` it can no longer be on (a chasm, the sea, a new
-- mountain, new land under a ship): to the nearest hex it can be on, if
-- there is one within two; else lost to the earth or the sea.
local function strand(game, u, cell, how)
    if game:canEnter(u, cell) then return end
    local slot = game:slot(u)
    local best, bd
    for _, n in ipairs(game:within(cell, 2)) do
        if n ~= cell and not slot[n.id] and game:canEnter(u, n) and not game:foreignAt(n, u.owner)
            and not (n.city and n.city.owner ~= u.owner) then
            local d = game:dist(cell, n) + game.rng:random() * 0.5
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
    Cat.hurt(game, u, u.hp, how or "WAS SWALLOWED BY THE EARTH")
end
Q.strand = strand

local function strandAll(game, cell, how)
    for _, u in ipairs(Cat.unitsOn(game, cell)) do strand(game, u, cell, how) end
end

--- quakes -----------------------------------------------------------------------------------

-- What a quake does to city `city`, `blow` HP; at its heart (`heart`) it may
-- bring a building down and kill.
local function quakeCity(game, city, blow, heart)
    shake(game, city, blow)
    if buttressed(city) or not heart then return end
    local rng = game.rng
    if rng:random() < D.QUAKE.fall then
        local list = {}
        for id in pairs(city.buildings) do
            if id ~= "buttress" then list[#list + 1] = id end
        end
        table.sort(list)
        if #list > 0 then
            local id = list[floor(rng:random() * #list) + 1]
            city.buildings[id] = nil
            game:tell(city.owner, "THE QUAKE HAS BROUGHT DOWN THE " .. D.BUILDINGS[id].name .. " OF " .. city.name)
            game:emit({ kind = "terrain", cell = city.cell })
        end
    end
    if rng:random() < D.QUAKE.kill and city.pop > 1 and not Cat.sheltered(city) then
        city.pop = city.pop - 1
        game:assignWork(city)
        game:tell(city.owner, city.name .. " HAS BEEN SHAKEN: ITS PEOPLE DIE UNDER THE RUBBLE")
    else
        game:tell(city.owner, city.name .. " HAS BEEN SHAKEN BY A QUAKE")
    end
end

-- A quake strikes at hex `cell`.
function Q.quake(game, cell)
    local QK = D.QUAKE
    local stage = Cat.stage(game)
    local reach = QK.reach[stage] or 1
    local rng = game.rng
    game:emit({ kind = "tremor", cell = cell.id, reach = reach, turn = game.turn, water = game:isWater(cell) })
    for _, n in ipairs(game:within(cell, reach)) do
        local d = game:dist(cell, n)
        for _, u in ipairs(Cat.unitsOn(game, n)) do
            if not (u.def.sea and game:isWater(n)) then
                Cat.hurt(game, u, d == 0 and QK.hit or QK.near, "WAS LOST IN A QUAKE")
            end
        end
        if n.city then
            quakeCity(game, n.city, d == 0 and QK.city or QK.nearCity, d <= 1)
        elseif land(game, n) and not braced(n) then
            if (n.improvement == "mine" or n.improvement == "farm") and rng:random() < QK.wreck then
                if n.owner then
                    game:tell(n.owner, "A QUAKE HAS WRECKED A " .. D.IMPROVEMENT[n.improvement].name)
                end
                n.improvement = nil
                game:emit({ kind = "terrain", cell = n.id })
            end
            if n.elev == "hills" and n.feature == "forest" and rng:random() < QK.slide then
                n.feature = nil
                n.burntForest = nil
                n.slid = true
                game:emit({ kind = "terrain", cell = n.id })
            end
        end
    end
    if land(game, cell) then crack(game, cell, QK.faults[stage] or 0, reach) end
    -- A quake under the sea, from the rift on, may send a wave in.
    if game:isWater(cell) and Cat.past(game, "rift") and rng:random() < 0.5 then Q.heave(game, cell) end
end

--- the rift ---------------------------------------------------------------------------------

-- Is the hex at sea, for the rift: water, or a rift hex the sea is in.
local function wet(game, cell)
    return game:isWater(cell) or (cell.rift or 0) >= 3
end

-- The cheapest way over the land from hex `a` to hex `b` that keeps off
-- cities, lairs and mountains, a little noise in it so it wanders; nil if
-- there is none.
local function track(game, a, b, avoid)
    local rng = game.rng
    local cost, from, done = { [a.id] = 0 }, {}, {}
    local open = { a }
    while #open > 0 do
        local bi = 1
        for i = 2, #open do if cost[open[i].id] < cost[open[bi].id] then bi = i end end
        local cell = table.remove(open, bi)
        if cell == b then break end
        if not done[cell.id] then
            done[cell.id] = true
            for _, n in ipairs(game:neighbours(cell)) do
                local ok = n == b or (land(game, n) and n.elev ~= "mountain" and not n.city and not n.lair
                    and not (avoid and avoid[n.id]))
                if ok and not done[n.id] then
                    local step = 1 + rng:random() * 0.8
                    for _, m in ipairs(game:neighbours(n)) do if m.city then step = step + 3 end end
                    local c = cost[cell.id] + step
                    if not cost[n.id] or c < cost[n.id] then
                        cost[n.id], from[n.id] = c, cell
                        open[#open + 1] = n
                    end
                end
            end
        end
    end
    if not from[b.id] then return nil end
    local path, cell = {}, b
    while cell do
        table.insert(path, 1, cell)
        cell = from[cell.id]
    end
    return path
end

-- How much land the line `path` cuts off: the smaller of the two biggest
-- pieces of the land it touches, once its hexes are gone.
local function parts(game, path)
    local gone = {}
    for _, cell in ipairs(path) do gone[cell.id] = true end
    local seen, sizes = {}, {}
    for _, cell in ipairs(path) do
        for _, n in ipairs(game:neighbours(cell)) do
            if land(game, n) and not gone[n.id] and not seen[n.id] then
                local size, stack = 0, { n }
                seen[n.id] = true
                while #stack > 0 do
                    local h = table.remove(stack)
                    size = size + 1
                    for _, m in ipairs(game:neighbours(h)) do
                        if land(game, m) and not gone[m.id] and not seen[m.id] then
                            seen[m.id] = true
                            stack[#stack + 1] = m
                        end
                    end
                end
                sizes[#sizes + 1] = size
            end
        end
    end
    table.sort(sizes, function(x, y) return x > y end)
    return sizes[2] or 0
end

-- Shore hexes: land beside the sea, no city on them.
local function shores(game)
    local out = {}
    for _, cell in ipairs(game.cells) do
        if land(game, cell) and not cell.city and cell.elev ~= "mountain" and game:coastal(cell) then
            out[#out + 1] = cell
        end
    end
    return out
end

-- Which way a line through hex `cell` runs, from the hex before it to the
-- one after (either may be nil): an angle in the room, as hex edge k's
-- normal is 60k degrees.
local function heading(cell, before, after)
    local x0, z0 = before and before.x or cell.x, before and before.z or cell.z
    local x1, z1 = after and after.x or cell.x, after and after.z or cell.z
    if x0 == x1 and z0 == z1 then return 0 end
    return math.atan2(z1 - z0, x1 - x0)
end

-- Where the rift will tear: from a shore across the land to another shore,
-- cutting off as much land as it can. Answers its hexes in order.
function Q.planRift(game)
    local list = shores(game)
    if #list < 2 then return nil end
    local rng = game.rng
    local QK = D.QUAKE
    local best, bv
    for _ = 1, 40 do
        local a = list[floor(rng:random() * #list) + 1]
        local b = list[floor(rng:random() * #list) + 1]
        local d = game:dist(a, b)
        if a ~= b and d >= QK.riftLen[1] - 1 and d <= QK.riftLen[2] then
            local path = track(game, a, b)
            if path and #path >= QK.riftLen[1] and #path <= QK.riftLen[2] + 3 then
                local v = parts(game, path) + #path * 0.5 + rng:random()
                if not bv or v > bv then best, bv = path, v end
            end
        end
    end
    return best
end

-- Lays the rift's line on the map, and its heading through each hex.
local function layRift(game, path)
    local c = game.cataclysm
    c.rift, c.opened = {}, 0
    for i, cell in ipairs(path) do
        c.rift[i] = cell.id
        cell.riftLine = i
        -- At either end, it runs out to the sea beside it.
        local before, after = path[i - 1], path[i + 1]
        if not before or not after then
            for _, n in ipairs(game:neighbours(cell)) do
                if game:isWater(n) then
                    if not before then before = { x = 2 * cell.x - n.x, z = 2 * cell.z - n.z } end
                    if not after then after = n end
                    break
                end
            end
        end
        cell.riftAngle = heading(cell, before, after)
    end
end

-- One step further for hex `cell` of the rift: cracked, a chasm, the sea in,
-- then sea.
local function tear(game, cell)
    local step = (cell.rift or 0) + 1
    local what = game:describe(cell)
    cell.riftAt = game.turn
    if step <= 3 then
        cell.rift = step
        if step == 2 then
            -- Split wide open: nothing stands on it, nothing grows.
            if cell.elev == "hills" then
                cell.elev = "flat"
                cell.top = cell.top - D.ELEV.hills.rise
            end
            if cell.feature == "forest" then cell.feature = nil end
            cell.improvement, cell.fire, cell.flood, cell.lava = nil, nil, nil, nil
            if cell.resource and cell.resource ~= "stone" then cell.resource = nil end
            if cell.workedBy then cell.workedBy = nil end
            strandAll(game, cell, "FELL INTO THE RIFT")
            if cell.owner then game:tell(cell.owner, "THE EARTH HAS SPLIT OPEN UNDER THE " .. what) end
        elseif step == 3 and cell.owner then
            game:tell(cell.owner, "THE SEA IS POURING INTO THE RIFT")
        end
    else
        -- The sea has it, for good.
        cell.rift = nil
        cell.terrain = "coast"
        cell.top = D.TERRAIN.coast.top
        cell.elev = "flat"
        cell.sundered = true
        cell.feature, cell.improvement, cell.resource, cell.fault = nil, nil, nil, nil
        cell.silt, cell.burnt, cell.burntForest, cell.scorched, cell.basalt, cell.ashfall, cell.soil = nil, nil, nil, nil,
            nil, nil, nil
        cell.workedBy = nil
        for k = 0, 5 do
            local n = game:cell(H.step(cell.c, cell.r, k))
            if n and n.fault then n.fault[(k + 3) % 6] = nil end
            if n and game:isWater(n) then game:emit({ kind = "terrain", cell = n.id }) end
        end
        strandAll(game, cell, "WAS LOST TO THE SEA")
        if cell.owner then game:tell(cell.owner, "THE SEA HAS TAKEN THE RIFT: THE LAND IS PARTED") end
    end
    game:emit({ kind = "sunder", cell = cell.id, step = step, turn = game.turn })
    game:emit({ kind = "terrain", cell = cell.id })
    for _, n in ipairs(game:neighbours(cell)) do
        if n.city and step == 2 then shake(game, n.city, D.QUAKE.nearCity) end
        -- The land beside it is drawn again: its edge is a cliff now.
        if land(game, n) then game:emit({ kind = "terrain", cell = n.id }) end
    end
end
Q.tear = tear

-- The rift, a turn on: `open` more of its hexes begin to tear, and each torn
-- hex goes a step further once it has stood its turns (the sea coming in
-- only where it can reach: from the sea at either end, along the rift).
local function rive(game, open)
    local c = game.cataclysm
    if not c.rift then return end
    c.opened = min(#c.rift, (c.opened or 0) + open)
    local QK = D.QUAKE
    local n = #c.rift
    -- The ends first, the middle last: the sea comes in from both shores.
    local function order(i) return min(i, n + 1 - i) end
    for i, id in ipairs(c.rift) do
        local cell = game.cells[id]
        if order(i) <= math.ceil(c.opened / 2) and not cell.sundered and not cell.city then
            local due = game.turn - (cell.riftAt or -99) >= QK.riftTurns
            if not cell.rift then
                tear(game, cell)
            elseif due and cell.rift <= 2 then
                if cell.rift == 1 then
                    tear(game, cell)
                else
                    -- The sea comes in from the next hex towards either shore.
                    local a, b = game.cells[c.rift[i - 1] or 0], game.cells[c.rift[i + 1] or 0]
                    local reached = (i == 1 or i == n) and game:coastal(cell)
                    reached = reached or (a and (a.sundered or (a.rift or 0) >= 3)) or (b and (b.sundered or (b.rift or 0) >= 3))
                    if reached then tear(game, cell) end
                end
            elseif due and cell.rift == 3 then
                tear(game, cell)
            end
        end
    end
end

--- the ranges --------------------------------------------------------------------------------

-- Where the land is pressed together: lines of a few hexes, each over the
-- land or across shallows between two shores, off the rift and the cities.
function Q.planRanges(game)
    local QK = D.QUAKE
    local rng = game.rng
    local c = game.cataclysm
    c.ranges = {}
    local used = {}
    for _, id in ipairs(c.rift or {}) do used[id] = true end
    local function ok(cell)
        if used[cell.id] or cell.city or cell.lair then return false end
        if cell.terrain == "ocean" or D.TERRAIN[cell.terrain].sea then return false end
        return true
    end
    for r = 1, QK.ranges do
        local best, bv
        for _ = 1, 30 do
            local start = game.cells[floor(rng:random() * #game.cells) + 1]
            if ok(start) and land(game, start) then
                local k = floor(rng:random() * 6)
                local line, cell = { start }, start
                local len = QK.rangeLen[1] + floor(rng:random() * (QK.rangeLen[2] - QK.rangeLen[1] + 1))
                while #line < len do
                    local turn = rng:random() < 0.3 and (rng:random() < 0.5 and 1 or -1) or 0
                    local n = game:cell(H.step(cell.c, cell.r, (k + turn) % 6))
                    if not n or not ok(n) then break end
                    line[#line + 1] = n
                    cell = n
                end
                -- Better across the water between two shores (the lands
                -- pressed into one), and long.
                local wetn, landn = 0, 0
                for _, h in ipairs(line) do if game:isWater(h) then wetn = wetn + 1 else landn = landn + 1 end end
                local v = #line + (wetn > 0 and landn > 1 and (r == 1 and 6 or 2) or 0) - (wetn > 3 and 4 or 0)
                    + rng:random()
                if #line >= QK.rangeLen[1] and (not bv or v > bv) then best, bv = line, v end
            end
        end
        if best then
            local ids = {}
            for i, h in ipairs(best) do
                ids[i] = h.id
                used[h.id] = true
                h.rangeLine = r
                h.rangeAngle = heading(h, best[i - 1], best[i + 1])
            end
            c.ranges[#c.ranges + 1] = ids
        end
    end
end

-- Hex `cell` rises a step: shallows to new land, flat to hills, hills to
-- mountains.
function Q.raise(game, cell)
    local what = game:describe(cell)
    game:emit({ kind = "uplift", cell = cell.id, turn = game.turn })
    if game:isWater(cell) then
        cell.terrain = "plains"
        cell.top = D.TERRAIN.plains.top
        cell.elev = "flat"
        cell.raised = true
        cell.drowned, cell.drownedForest, cell.sundered = nil, nil, nil
        if cell.improvement == "boats" then cell.improvement = nil end
        if cell.resource == "fish" then cell.resource = nil end
        for _, n in ipairs(game:neighbours(cell)) do
            if game:isWater(n) then game:emit({ kind = "terrain", cell = n.id }) end
        end
        if cell.owner then game:tell(cell.owner, "NEW LAND HAS RISEN OUT OF THE SEA") end
    elseif cell.elev == "flat" then
        cell.elev = "hills"
        cell.top = cell.top + D.ELEV.hills.rise
        if cell.improvement == "farm" then cell.improvement = nil end
        if cell.owner then game:tell(cell.owner, "THE " .. what .. " HAS RISEN INTO HILLS") end
    else
        cell.elev = "mountain"
        cell.top = cell.top + D.ELEV.mountain.rise - D.ELEV.hills.rise
        cell.feature, cell.improvement = nil, nil
        if cell.resource == "wheat" then cell.resource = nil end
        if cell.workedBy then cell.workedBy = nil end
        if cell.owner then game:tell(cell.owner, "THE " .. what .. " HAS RISEN INTO MOUNTAINS") end
    end
    cell.fault, cell.flood = nil, nil
    for k = 0, 5 do
        local n = game:cell(H.step(cell.c, cell.r, k))
        if n and n.fault then n.fault[(k + 3) % 6] = nil; game:emit({ kind = "terrain", cell = n.id }) end
    end
    strandAll(game, cell, cell.elev == "mountain" and "WAS BURIED AS THE MOUNTAINS ROSE" or "WAS LOST AS THE LAND ROSE")
    game:emit({ kind = "terrain", cell = cell.id })
end

-- Can hex `cell` of a range rise now: not a city's own nor a mountain, the
-- shallows only beside land, and not under a lair.
local function risable(game, cell)
    if cell.city or cell.lair or cell.elev == "mountain" or (cell.rift or 0) > 0 or cell.volcano then return false end
    if game:isWater(cell) then
        if cell.terrain ~= "coast" then return false end
        for _, n in ipairs(game:neighbours(cell)) do if land(game, n) then return true end end
        return false
    end
    return not D.TERRAIN[cell.terrain].frozen or cell.terrain == "tundra"
end

local function uplift(game, n)
    local c = game.cataclysm
    local list = {}
    for _, ids in ipairs(c.ranges or {}) do
        for _, id in ipairs(ids) do
            local cell = game.cells[id]
            if risable(game, cell) then list[#list + 1] = cell end
        end
    end
    -- The sea first, so the shores meet; then the lowest.
    local picked = Cat.pick(game, function(cell)
        if game:isWater(cell) then return 4 end
        return cell.elev == "flat" and 2 or 1
    end, n, list)
    for _, cell in ipairs(picked) do Q.raise(game, cell) end
end

--- volcanoes ---------------------------------------------------------------------------------

-- Wakes the volcanoes: on the mountains, the ranges' first and those by the
-- rift; a hill is thrown up into one if there are too few.
function Q.wake(game, n)
    local c = game.cataclysm
    c.volcanoes = c.volcanoes or {}
    local picked = Cat.pick(game, function(cell)
        if cell.volcano or cell.city or cell.lair or not land(game, cell) then return 0 end
        if cell.elev ~= "mountain" and cell.elev ~= "hills" then return 0 end
        for _, v in ipairs(c.volcanoes) do if game:dist(game.cells[v], cell) < 4 then return 0 end end
        local w = cell.elev == "mountain" and 3 or 0.5
        if cell.rangeLine then w = w * 3 end
        for _, m in ipairs(game:within(cell, 2)) do if m.riftLine then w = w * 1.5 break end end
        return w
    end, n)
    for _, cell in ipairs(picked) do
        if cell.elev ~= "mountain" then
            cell.top = cell.top + D.ELEV.mountain.rise - (cell.elev == "hills" and D.ELEV.hills.rise or 0)
            cell.elev = "mountain"
            cell.feature, cell.improvement = nil, nil
            strandAll(game, cell, "WAS BURIED AS THE MOUNTAIN ROSE")
        end
        cell.volcano = true
        cell.fault = nil
        c.volcanoes[#c.volcanoes + 1] = cell.id
        game:emit({ kind = "terrain", cell = cell.id })
        game:tell(nil, "A VOLCANO HAS WOKEN " .. where(game, cell))
    end
end

-- Lava pours over hex `cell`: it burns for its turns, takes the forest,
-- the farm and the mine, and hurts whoever stands on it.
local function flood(game, cell)
    local what = game:describe(cell)
    cell.lava = D.QUAKE.lavaTurns
    cell.basalt, cell.ashfall, cell.soil, cell.flood, cell.fire = nil, nil, nil, nil, nil
    if cell.feature == "forest" then
        cell.feature = nil
        cell.burntForest = true
    end
    if cell.improvement then
        if cell.owner then game:tell(cell.owner, "LAVA HAS TAKEN A " .. D.IMPROVEMENT[cell.improvement].name) end
        cell.improvement = nil
    elseif cell.owner then
        game:tell(cell.owner, "LAVA IS POURING OVER THE " .. what)
    end
    if cell.resource == "wheat" then cell.resource = nil end
    for _, u in ipairs(Cat.unitsOn(game, cell)) do Cat.hurt(game, u, D.QUAKE.lavaHit, "WAS BURNT BY THE LAVA") end
    game:emit({ kind = "terrain", cell = cell.id })
end

-- Can lava run onto hex `cell`: land, no mountain, no city.
local function runny(game, cell)
    return land(game, cell) and cell.elev ~= "mountain" and not cell.city and (cell.rift or 0) < 2
end

-- Volcano `cell` erupts: the lava runs out over the land below it, as far
-- as D.QUAKE.flow, the ash falls round it, the forests by the lava catch
-- fire and the cities by it burn.
function Q.erupt(game, cell)
    local QK = D.QUAKE
    local rng = game.rng
    cell.erupting = 2
    -- Down from the crater: two or three tongues, each running on a hex or
    -- two, downhill where it can.
    local took, seen = {}, { [cell.id] = true }
    local mouths = {}
    for _, n in ipairs(game:neighbours(cell)) do if runny(game, n) then mouths[#mouths + 1] = n end end
    for _ = 1, min(#mouths, 2 + floor(rng:random() * 2)) do
        local i = floor(rng:random() * #mouths) + 1
        local at = table.remove(mouths, i)
        for _ = 1, QK.flow do
            if not at or seen[at.id] then break end
            seen[at.id] = true
            took[#took + 1] = at
            local next, nv
            for _, m in ipairs(game:neighbours(at)) do
                if runny(game, m) and not seen[m.id] and game:dist(m, cell) > game:dist(at, cell) then
                    local v = m.top + rng:random() * 3
                    if not nv or v < nv then next, nv = m, v end
                end
            end
            at = next
        end
    end
    local ids = {}
    for _, h in ipairs(took) do ids[#ids + 1] = h.id end
    game:emit({ kind = "erupt", cell = cell.id, lava = ids, turn = game.turn })
    game:tell(nil, "THE VOLCANO " .. where(game, cell) .. " HAS ERUPTED")
    for _, h in ipairs(took) do flood(game, h) end
    -- The forests by it catch, and the cities by it burn.
    for _, h in ipairs(took) do
        for _, n in ipairs(game:neighbours(h)) do
            if n.city then
                Cat.harm(game, n.city, QK.lavaCity)
            elseif n.feature == "forest" and Cat.flammable(game, n) and rng:random() < 0.2 then
                Cat.ignite(game, n)
            end
        end
    end
    for _, u in ipairs(Cat.unitsOn(game, cell)) do Cat.hurt(game, u, QK.lavaHit, "WAS BURNT BY THE LAVA") end
    -- Ash over the land round it.
    for _, n in ipairs(game:within(cell, QK.ashReach)) do
        if land(game, n) and n ~= cell and not n.lava and n.elev ~= "mountain" then
            n.ashfall = QK.ashTurns
            game:emit({ kind = "terrain", cell = n.id })
        end
        if n.city then shake(game, n.city, floor(QK.lavaCity * 0.4)) end
    end
    game:emit({ kind = "terrain", cell = cell.id })
end

-- The lava cools, the ash settles, the crater dims.
local function cool(game)
    for _, cell in ipairs(game.cells) do
        if cell.lava then
            for _, u in ipairs(Cat.unitsOn(game, cell)) do Cat.hurt(game, u, D.QUAKE.lavaHit, "WAS BURNT BY THE LAVA") end
            cell.lava = cell.lava - 1
            if cell.lava <= 0 then
                cell.lava = nil
                cell.basalt = true
                if not cell.resource and game.rng:random() < D.QUAKE.obsidian then cell.resource = "obsidian" end
                game:emit({ kind = "terrain", cell = cell.id })
            end
        end
        if cell.ashfall then
            cell.ashfall = cell.ashfall - 1
            if cell.ashfall <= 0 then
                cell.ashfall = nil
                if not cell.basalt then cell.soil = true end
                game:emit({ kind = "terrain", cell = cell.id })
            end
        end
        if cell.erupting then
            cell.erupting = cell.erupting - 1
            if cell.erupting <= 0 then
                cell.erupting = nil
                game:emit({ kind = "terrain", cell = cell.id })
            end
        end
    end
end

--- the waves ---------------------------------------------------------------------------------

-- The sea heaves at hex `from`, out at sea: the shore nearest it is marked,
-- and the wave strikes it as the next turn begins.
function Q.heave(game, from, size)
    local QK = D.QUAKE
    local c = game.cataclysm
    local rng = game.rng
    local n = size or (QK.waveLen[1] + floor(rng:random() * (QK.waveLen[2] - QK.waveLen[1] + 1)))
    local list = {}
    for _, cell in ipairs(game:within(from, 5)) do
        if land(game, cell) and cell.elev ~= "mountain" and game:coastal(cell) then list[#list + 1] = cell end
    end
    table.sort(list, function(a, b)
        local da, db = game:dist(a, from), game:dist(b, from)
        if da ~= db then return da < db end
        return a.id < b.id
    end)
    c.marks = c.marks or {}
    c.waveFrom = c.waveFrom or {}
    local hit = 0
    for _, cell in ipairs(list) do
        if hit >= n then break end
        if not c.marks[cell.id] then
            c.marks[cell.id] = "wave"
            c.waveFrom[cell.id] = from.id
            hit = hit + 1
            if cell.owner then game:tell(cell.owner, "THE SEA HAS DRAWN BACK FROM THE " .. game:describe(cell) .. ": A WAVE IS COMING") end
        end
    end
    if hit > 0 then game:emit({ kind = "mark" }) end
end

-- The sea hex the wave on shore hex `cell` comes from: its sea neighbour
-- nearest `from`.
local function seaward(game, cell, from)
    local best, bd
    for _, n in ipairs(game:neighbours(cell)) do
        if game:isWater(n) then
            local d = from and game:dist(n, from) or 0
            if not bd or d < bd then best, bd = n, d end
        end
    end
    return best
end
Q.seaward = seaward

-- A wave strikes shore hex `cell`.
function Q.strike(game, cell, from)
    local QK = D.QUAKE
    local sea = seaward(game, cell, from)
    game:emit({ kind = "wave", cell = cell.id, from = sea and sea.id or cell.id, turn = game.turn })
    for _, u in ipairs(Cat.unitsOn(game, cell)) do Cat.hurt(game, u, QK.waveHit, "WAS SWEPT AWAY BY THE WAVE") end
    -- Ships and boats by it are thrown about.
    for _, n in ipairs(game:neighbours(cell)) do
        if game:isWater(n) then
            for _, u in ipairs(Cat.unitsOn(game, n)) do
                Cat.hurt(game, u, floor(QK.waveHit / 2), "WAS OVERTURNED BY THE WAVE")
            end
        end
    end
    if cell.city then
        if not cell.city.buildings.levee then
            Cat.harm(game, cell.city, QK.waveCity)
            game:tell(cell.city.owner, "A WAVE HAS STRUCK " .. cell.city.name)
        end
    else
        -- The water lies on the low land a while, and takes what is on it
        -- as it goes back.
        if cell.elev == "flat" and (cell.rift or 0) == 0 then
            cell.flood = QK.waveTurns
            cell.waved = true
        end
        if cell.improvement == "boats" then cell.improvement = nil end
        game:emit({ kind = "terrain", cell = cell.id })
    end
end

-- The water the waves left goes back down: the farm and the mine washed
-- away, silt left.
local function ebb(game)
    for _, cell in ipairs(game.cells) do
        if cell.flood and cell.waved then
            cell.flood = cell.flood - 1
            if cell.flood <= 0 then
                cell.flood, cell.waved = nil, nil
                cell.silt = true
                if cell.improvement == "farm" or cell.improvement == "mine" then
                    if cell.owner then
                        game:tell(cell.owner, "THE WAVE HAS WASHED AWAY A " .. D.IMPROVEMENT[cell.improvement].name)
                    end
                    cell.improvement = nil
                end
                game:emit({ kind = "terrain", cell = cell.id })
            end
        end
    end
end

-- Somewhere out at sea for a wave to come from: the coast's water a hex or
-- two off the land, where people live likeliest.
local function offshore(game)
    local list = Cat.pick(game, function(cell)
        if not game:isWater(cell) or D.TERRAIN[cell.terrain].sea then return 0 end
        local near = false
        for _, n in ipairs(game:within(cell, 2)) do if land(game, n) then near = true break end end
        if not near then return 0 end
        local w = 1
        for _, c in ipairs(game.cities) do
            if game:dist(cell, game.cells[c.cell]) <= 3 then w = w + 2 end
        end
        return w
    end, 1)
    return list[1]
end

--- the marks --------------------------------------------------------------------------------

-- What is coming at hex `cell` as the next turn begins: "quake", "erupt"
-- or "wave"; or nil.
function Q.marked(game, cell)
    local c = quaking(game)
    return c and c.marks and c.marks[cell.id] or nil
end

-- Lays the quakes, eruptions and waves of the next turn.
local function mark(game)
    local c = game.cataclysm
    local QK = D.QUAKE
    local rng = game.rng
    c.marks, c.waveFrom = {}, {}
    local next = game.turn + 1
    if next > D.LAST_TURN then return end
    local stage = Cat.stageAt(next, "quake")
    local n = stage and QK.quakes[stage] or 0
    local picked = Cat.pick(game, function(cell)
        if cell.volcano then return 0 end
        local w = land(game, cell) and 1.5 or 0.25
        if cell.riftLine then w = w * 3 elseif cell.rangeLine then w = w * 2 end
        if cell.fault then w = w * 1.5 end
        return w
    end, n)
    for _, cell in ipairs(picked) do
        c.marks[cell.id] = "quake"
        if cell.owner then game:tell(cell.owner, "THE GROUND SHAKES UNDER THE " .. game:describe(cell) .. ": A QUAKE IS COMING") end
    end
    if stage == "fire" then
        for _, id in ipairs(c.volcanoes or {}) do
            local v = game.cells[id]
            if v.volcano and not c.marks[id] and rng:random() < QK.erupt then
                c.marks[id] = "erupt"
                game:tell(nil, "THE VOLCANO " .. where(game, v) .. " IS ABOUT TO ERUPT")
            end
        end
    end
    local wave = stage and QK.waves[stage] or 0
    if wave > 0 and rng:random() < wave then
        local from = offshore(game)
        if from then Q.heave(game, from) end
    end
    game:emit({ kind = "mark" })
end

--- the great quake ---------------------------------------------------------------------------

function Q.great(game)
    local QK = D.QUAKE
    local c = game.cataclysm
    game:emit({ kind = "greatquake", turn = game.turn })
    game:tell(nil, "THE GREAT QUAKE: THE LAND IS TORN APART")
    -- The whole rift to the sea at once.
    for _, id in ipairs(c.rift or {}) do
        local cell = game.cells[id]
        if not cell.sundered and not cell.city then
            while not cell.sundered do tear(game, cell) end
        end
    end
    c.opened = #(c.rift or {})
    -- Every city shakes, and the sea comes in on every city by it.
    for _, city in ipairs(game.cities) do
        shake(game, city, QK.greatCity)
        local cell = game.cells[city.cell]
        if game:coastal(cell) then
            local sea = seaward(game, cell)
            if sea then
                Q.strike(game, cell, sea)
                for _, n in ipairs(game:neighbours(cell)) do
                    if land(game, n) and n.elev ~= "mountain" and game:coastal(n) and game.rng:random() < 0.6 then
                        Q.strike(game, n, sea)
                    end
                end
            end
        end
    end
end

--- the turn ----------------------------------------------------------------------------------

Q.tell = {
    omen = function() return ("THE GROUND TREMBLES. THE TREMORS COME IN %d TURNS"):format(D.QUAKE.tremors - D.QUAKE.omen) end,
    tremors = function() return "THE TREMORS: QUAKES SHAKE THE LAND AND FAULTS OPEN IN IT. BUILD BUTTRESSES" end,
    rift = function() return "THE SUNDERING: THE RIFT TEARS THE LAND APART, AND THE MOUNTAINS RISE" end,
    fire = function() return ("THE FIRE BELOW: THE VOLCANOES WAKE. THE WORLD ENDS IN %d TURNS"):format(D.LAST_TURN - D.QUAKE.fire + 1) end,
}

function Q.play(game, stage)
    local QK = D.QUAKE
    local c = game.cataclysm
    if stage ~= "omen" then
        Cat.fires(game, stage)
        cool(game)
        ebb(game)
    end
    -- What was seen coming strikes: the eruptions, the quakes, the waves.
    local due = {}
    for id, what in pairs(c.marks or {}) do due[#due + 1] = { id, what } end
    table.sort(due, function(a, b)
        local order = { erupt = 1, quake = 2, wave = 3 }
        if order[a[2]] ~= order[b[2]] then return order[a[2]] < order[b[2]] end
        return a[1] < b[1]
    end)
    local from = c.waveFrom or {}
    c.marks, c.waveFrom = {}, {}
    for _, m in ipairs(due) do
        local cell = game.cells[m[1]]
        if m[2] == "erupt" and cell.volcano then Q.erupt(game, cell)
        elseif m[2] == "quake" then Q.quake(game, cell)
        elseif m[2] == "wave" and land(game, cell) then Q.strike(game, cell, from[m[1]] and game.cells[from[m[1]]]) end
    end
    -- The rift is seen the turn before the tremors; it tears from the rift
    -- stage on, and the ranges rise.
    if not c.rift and game.turn >= QK.tremors - 1 then
        local path = Q.planRift(game)
        if path then
            layRift(game, path)
            game:tell(nil, ("THE GROUND HAS CRACKED FROM SEA TO SEA, %s: THE GREAT RIFT WILL TEAR THERE")
                :format(where(game, path[floor(#path / 2) + 1])))
            for _, cell in ipairs(path) do game:emit({ kind = "terrain", cell = cell.id }) end
        end
    end
    if not c.ranges and game.turn >= QK.rift - 1 then Q.planRanges(game) end
    if stage == "tremors" then spread(game, QK.spread.tremors) end
    if stage == "rift" or stage == "fire" then
        spread(game, QK.spread[stage])
        rive(game, QK.riftStep[stage])
        uplift(game, QK.uplift[stage])
    end
    if stage == "fire" and not c.volcanoes then Q.wake(game, QK.volcanoes) end
    if game.turn == QK.warn then
        game:tell(nil, ("THE GREAT QUAKE COMES IN %d TURNS: THE WHOLE RIFT WILL OPEN, AND THE SEA COME IN ON EVERY SHORE")
            :format(QK.great - QK.warn))
    end
    if game.turn == QK.great then Q.great(game) end
    -- And the next turn's are seen coming.
    if game.turn + 1 >= QK.tremors then mark(game) end
end

-- Will unit u be hurt, or worse, if it ends the turn on hex `cell`: a quake,
-- an eruption or a wave coming, lava, the rift about to split under it.
function Q.danger(game, cell, u)
    local c = quaking(game)
    if not c then return false end
    if cell.lava and not u.def.sea then return true end
    local m = c.marks and c.marks[cell.id]
    if m == "quake" or m == "wave" then return not (u.def.sea and game:isWater(cell)) or m == "wave" end
    -- Beside an eruption coming, the lava may come.
    for _, n in ipairs(game:within(cell, 1)) do
        if c.marks and c.marks[n.id] == "erupt" then return true end
    end
    if cell.rift == 1 and not u.def.sea then return true end
    return false
end

return Q
