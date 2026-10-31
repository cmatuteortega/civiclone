-- Making a map from a seed: one or two continents out of a few octaves of
-- noise, mountains along the highest of it, deserts where the second noise is
-- dry, forests where a third is wet, a few resources, rivers from the hills
-- down to the sea, and a start for each civilization on the biggest stretch
-- of land, as far from the others as it can be.
--
-- Thresholds are taken as shares of the map (quantiles) rather than noise
-- values, so every seed has about the same amount of land, hills and desert.

local H = require "src.hex"
local Rng = require "src.rng"
local D = require "src.defs"

local abs, max, min, floor = math.abs, math.max, math.min, math.floor

local Mapgen = {}

local makeRivers -- below, under rivers

local LAND, MOUNTAIN, HILLS, DESERT, PLAINS, FOREST = 0.5, 0.07, 0.2, 0.2, 0.38, 0.26

-- The value below which share f of the list lies.
local function quantile(values, f)
    local s = {}
    for k, v in ipairs(values) do s[k] = v end
    table.sort(s)
    return s[max(1, min(#s, floor(#s * f + 0.5)))]
end

local function build(cols, rows, seed)
    local rng = Rng.new(seed)
    local elevN, moistN, woodN = Rng.noise(seed), Rng.noise(seed + 101), Rng.noise(seed + 977)
    local cells = {}
    local function at(c, r)
        if c < 0 or r < 0 or c >= cols or r >= rows then return nil end
        return cells[r * cols + c + 1]
    end

    -- Height: noise, pulled down towards the edges so the map is an island
    -- or two in an ocean.
    local heights = {}
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local x, z = H.center(c, r)
            local u, v = x / H.W / cols, z / H.ROW / rows
            local e = elevN(u * 3.1, v * 2.3, 5)
            local edge = max(abs(u * 2 - 1), abs(v * 2 - 1))
            e = e - max(0, edge - 0.45) * 1.6
            local cell = { id = r * cols + c + 1, c = c, r = r, x = x, z = z, e = e,
                m = moistN(u * 4 + 7, v * 3 + 3, 4), wood = woodN(u * 6 + 13, v * 5, 3) }
            cells[cell.id] = cell
            heights[#heights + 1] = e
        end
    end
    local seaLevel = quantile(heights, 1 - LAND)

    local land = {}
    for _, cell in ipairs(cells) do
        if cell.e >= seaLevel then land[#land + 1] = cell end
    end
    local landE, landM = {}, {}
    for k, cell in ipairs(land) do landE[k], landM[k] = cell.e, cell.m end
    local mountainAt = quantile(landE, 1 - MOUNTAIN)
    local hillsAt = quantile(landE, 1 - MOUNTAIN - HILLS)
    local uplandAt = quantile(landE, 0.5)
    local desertAt = quantile(landM, DESERT)
    local plainsAt = quantile(landM, DESERT + PLAINS)

    for _, cell in ipairs(cells) do
        if cell.e < seaLevel then
            cell.terrain, cell.elev = "ocean", "flat"
        else
            cell.terrain = cell.m < desertAt and "desert" or (cell.m < plainsAt and "plains" or "grass")
            -- Hills scattered a little as well as on the high ground, so not
            -- every hill sits at the foot of a mountain.
            if cell.e >= mountainAt then cell.elev = "mountain"
            elseif cell.e >= hillsAt or rng:random() < 0.06 then cell.elev = "hills"
            else cell.elev = "flat" end
        end
    end
    -- Coast: water beside land.
    for _, cell in ipairs(cells) do
        if cell.terrain == "ocean" then
            for k = 0, 5 do
                local n = at(H.step(cell.c, cell.r, k))
                if n and not D.TERRAIN[n.terrain].water then cell.terrain = "coast" break end
            end
        end
    end
    -- Forest where it is wet enough, never on desert or mountains.
    local woods = {}
    for _, cell in ipairs(land) do
        if cell.elev ~= "mountain" and cell.terrain ~= "desert" then woods[#woods + 1] = cell.wood + cell.m * 0.3 end
    end
    local forestAt = #woods > 0 and quantile(woods, 1 - FOREST) or 2
    for _, cell in ipairs(land) do
        if cell.elev ~= "mountain" and cell.terrain ~= "desert" and cell.wood + cell.m * 0.3 >= forestAt then
            cell.feature = "forest"
        end
    end
    -- Resources.
    for _, cell in ipairs(land) do
        local roll = rng:random()
        if cell.elev == "flat" and not cell.feature and cell.terrain ~= "desert" and roll < 0.08 then
            cell.resource = "wheat"
        elseif cell.elev == "hills" and not cell.feature and roll < 0.14 then
            cell.resource = "stone"
        elseif cell.terrain == "desert" and cell.elev ~= "mountain" and roll < 0.06 then
            cell.resource = "gems"
        end
    end
    -- Fish in the shallows, from a roll of their own so the land is as it was.
    local fishRng = Rng.new(seed + 4243)
    for _, cell in ipairs(cells) do
        if cell.terrain == "coast" and fishRng:random() < 0.12 then cell.resource = "fish" end
    end
    -- How high each hex stands: low and high ground a step apart, so the land
    -- reads in terraces.
    for _, cell in ipairs(cells) do
        local t = D.TERRAIN[cell.terrain]
        local top = t.top
        if not t.water then
            if cell.e >= uplandAt then top = top + 2 end
            top = top + D.ELEV[cell.elev].rise
        end
        cell.top = top
    end
    -- Rivers, from a roll of their own as well.
    local rivers = makeRivers(cells, cols, rows, land, seed)
    return cells, rng, rivers
end

--- rivers ----------------------------------------------------------------------------
--
-- Rivers run along the edges between hexes, as in Civilization VI, from
-- corner to corner. A corner's height is the mean of the three hexes that
-- meet there. Every corner is given a way down to the sea by a priority
-- flood from the shore inland (so a river finds its way out of a hollow
-- rather than ending in it), and a river is that way down from a corner high
-- in the hills. One that reaches another joins it, and the river below runs
-- wider.
--
-- What is kept is on the cells: `cell.river[k]` for each edge k a river runs
-- along, the same table on both hexes of the edge:
--   from, to   the room (x, z) of its corners, upstream first
--   size       how many rivers run in it (2 or more below where they join)
--   level      the water's height: never higher than the bank lower down
--              the river, so it only ever steps down
--   fall       it drops to the next edge down at `to` (a cascade)
--   mouth      `to` is on the sea: it falls into it
--   foot       the river above drops into it at `from`
--   name, at   the river's name, and how many edges from its source

local RIVER_EVERY = 65     -- land hexes to a river, about
local RIVER_SHORTEST = 4   -- edges a river must run to the sea, at least
local RIVER_TRIBUTARY = 3  -- and one that joins another
local RIVER_APART = 3.2    -- hexes between where two rivers rise
local RIVER_SINK = 1.2     -- how far below the lower bank the water lies

-- The corners of the map, each with the hexes that meet there and the edges
-- that run out of it.
local function cornersOf(cells, at)
    local list, byKey, of = {}, {}, {}
    for _, cell in ipairs(cells) do
        local mine = {}
        for k, p in ipairs(H.corners(cell.x, cell.z)) do
            local key = floor(p[1] * 4 + 0.5) * 65536 + floor(p[2] * 4 + 0.5)
            local v = byKey[key]
            if not v then
                v = { id = #list + 1, x = p[1], z = p[2], cells = {}, out = {} }
                byKey[key] = v
                list[#list + 1] = v
            end
            v.cells[#v.cells + 1] = cell
            mine[k - 1] = v
        end
        of[cell.id] = mine
    end
    for _, cell in ipairs(cells) do
        for k = 0, 5 do
            local n = at(H.step(cell.c, cell.r, k))
            if n and n.id > cell.id then
                local a, b = of[cell.id][k], of[cell.id][(k + 1) % 6]
                local edge = { a = a, b = b, cells = { cell, n }, ks = { k, (k + 3) % 6 } }
                a.out[#a.out + 1] = { to = b, edge = edge }
                b.out[#b.out + 1] = { to = a, edge = edge }
            end
        end
    end
    return list
end

-- A small heap of corners, lowest `fill` first (ties by id, so the same map
-- every time).
local function lower(a, b) return a.fill < b.fill or (a.fill == b.fill and a.id < b.id) end
local function push(h, v)
    h[#h + 1] = v
    local k = #h
    while k > 1 do
        local p = floor(k / 2)
        if lower(h[k], h[p]) then h[k], h[p] = h[p], h[k] k = p else break end
    end
end
local function pop(h)
    local top = h[1]
    h[1] = h[#h]
    h[#h] = nil
    local k = 1
    while true do
        local l, r, m = k * 2, k * 2 + 1, k
        if h[l] and lower(h[l], h[m]) then m = l end
        if h[r] and lower(h[r], h[m]) then m = r end
        if m == k then break end
        h[k], h[m] = h[m], h[k]
        k = m
    end
    return top
end

function makeRivers(cells, cols, rows, land, seed)
    local rng = Rng.new(seed + 6151)
    local function at(c, r)
        if c < 0 or r < 0 or c >= cols or r >= rows then return nil end
        return cells[r * cols + c + 1]
    end
    local corners = cornersOf(cells, at)
    local function wet(cell) return D.TERRAIN[cell.terrain].water end
    -- A river may run between two land hexes, not both mountains.
    local function runs(edge)
        local a, b = edge.cells[1], edge.cells[2]
        return not wet(a) and not wet(b) and not (a.elev == "mountain" and b.elev == "mountain")
    end
    local heap = {}
    for _, v in ipairs(corners) do
        local e, sea = 0, false
        for _, cell in ipairs(v.cells) do
            e = e + cell.e
            if wet(cell) then sea = true end
        end
        v.h = e / #v.cells
        v.sea = sea
        if sea then
            v.fill, v.done = v.h, true
            push(heap, v)
        end
    end
    -- The flood: from the shore inland, each corner's way down the one it
    -- was reached from.
    while #heap > 0 do
        local v = pop(heap)
        for _, o in ipairs(v.out) do
            local n = o.to
            if not n.done and not n.sea and #n.cells == 3 and runs(o.edge) then
                n.done, n.down, n.downEdge = true, v, o.edge
                n.fill = max(n.h, v.fill)
                n.steps = (v.steps or 0) + 1
                push(heap, n)
            end
        end
    end

    -- Where rivers rise: corners high up beside hills or mountains, a long
    -- way from the sea, the highest first among a few picked at random.
    local springs = {}
    for _, v in ipairs(corners) do
        if v.down and (v.steps or 0) >= RIVER_SHORTEST then
            local high = false
            for _, cell in ipairs(v.cells) do
                if cell.elev ~= "flat" then high = true end
            end
            if high then springs[#springs + 1] = v end
        end
    end
    table.sort(springs, function(a, b) return a.h + a.steps * 0.004 > b.h + b.steps * 0.004 end)
    local want = max(3, floor(#land / RIVER_EVERY + 0.5))
    local rivers, risen, inRiver = {}, {}, {}
    local names = {}
    for k, n in ipairs(D.RIVERS) do names[k] = n end
    for k = #names, 2, -1 do
        local j = rng:random(k)
        names[k], names[j] = names[j], names[k]
    end
    local tries = 0
    while #rivers < want and #springs > 0 and tries < 400 do
        tries = tries + 1
        local v = table.remove(springs, rng:random(min(#springs, 4)))
        local apart = not inRiver[v.id]
        for _, s in ipairs(risen) do
            local d = math.sqrt((s.x - v.x) ^ 2 + (s.z - v.z) ^ 2) / H.W
            if d < RIVER_APART then apart = false break end
        end
        if apart then
            -- Down to the sea, or to a river already there.
            local path, w, joins = {}, v, nil
            while w.down do
                path[#path + 1] = { from = w, to = w.down, edge = w.downEdge }
                w = w.down
                if inRiver[w.id] then joins = w break end
            end
            if #path >= (joins and RIVER_TRIBUTARY or RIVER_SHORTEST) then
                local name = names[(#rivers % #names) + 1]
                rivers[#rivers + 1] = { name = name, path = path, joins = joins }
                risen[#risen + 1] = v
                for n, p in ipairs(path) do
                    inRiver[p.from.id] = true
                    inRiver[p.to.id] = true
                    p.edge.size = (p.edge.size or 0) + 1
                    p.edge.from, p.edge.to = p.from, p.to
                    if not p.edge.name then p.edge.name, p.edge.at = name, n end
                end
                -- Below where it joins, the river it joined runs fuller.
                local below = joins
                while below and below.down do
                    below.downEdge.size = below.downEdge.size + 1
                    below = below.down
                end
            end
        end
    end

    -- The water's level along each: never higher than upstream. Corners in
    -- order from the springs down, each edge out of a corner taking the
    -- lowest that comes into it.
    local into, incoming, edges = {}, {}, {}
    for _, r in ipairs(rivers) do
        for _, p in ipairs(r.path) do
            if not edges[p.edge] then
                edges[p.edge] = true
                edges[#edges + 1] = p.edge
                incoming[p.to.id] = (incoming[p.to.id] or 0) + 1
            end
        end
    end
    local queue = {}
    for _, e in ipairs(edges) do
        if not incoming[e.from.id] then
            incoming[e.from.id] = 0
            queue[#queue + 1] = e.from
        end
    end
    local seenQ = {}
    local head = 1
    while queue[head] do
        local v = queue[head]
        head = head + 1
        if not seenQ[v.id] then
            seenQ[v.id] = true
            local e = v.downEdge
            if e and edges[e] then
                local bank = min(e.cells[1].top, e.cells[2].top) - RIVER_SINK
                e.level = min(bank, into[v.id] or math.huge)
                local to = e.to
                into[to.id] = min(into[to.id] or math.huge, e.level)
                incoming[to.id] = incoming[to.id] - 1
                if incoming[to.id] == 0 then queue[#queue + 1] = to end
            end
        end
    end
    for _, e in ipairs(edges) do
        local down = e.to.downEdge
        e.mouth = e.to.sea
        e.fall = (not e.mouth and down and edges[down] and down.level < e.level - 0.01) or false
        e.foot = (into[e.from.id] or e.level) > e.level + 0.01
        local info = {
            from = { e.from.x, e.from.z }, to = { e.to.x, e.to.z },
            size = e.size, level = e.level, fall = e.fall, mouth = e.mouth or false, foot = e.foot,
            name = e.name, at = e.at,
        }
        for n = 1, 2 do
            local cell = e.cells[n]
            cell.river = cell.river or {}
            cell.river[e.ks[n]] = info
        end
    end
    local out = {}
    for k, r in ipairs(rivers) do out[k] = { name = r.name, length = #r.path, joins = r.joins and true or false } end
    return out
end

-- Land a unit can walk, joined up: the biggest piece.
local function biggestLand(cells, cols, rows)
    local seen, best = {}, {}
    local function passable(cell)
        return cell and not D.TERRAIN[cell.terrain].water and cell.elev ~= "mountain"
    end
    for _, start in ipairs(cells) do
        if passable(start) and not seen[start.id] then
            local piece, queue, head = {}, { start }, 1
            seen[start.id] = true
            while queue[head] do
                local cell = queue[head]
                head = head + 1
                piece[#piece + 1] = cell
                for k = 0, 5 do
                    local c, r = H.step(cell.c, cell.r, k)
                    local n = c >= 0 and r >= 0 and c < cols and r < rows and cells[r * cols + c + 1]
                    if passable(n) and not seen[n.id] then
                        seen[n.id] = true
                        queue[#queue + 1] = n
                    end
                end
            end
            if #piece > #best then best = piece end
        end
    end
    return best
end

-- How good a place is to found a first city: what the hexes round it yield.
local function siteScore(cells, cols, rows, cell)
    local s = 0
    for _, p in ipairs(H.range(cell.c, cell.r, 2)) do
        local c, r = p[1], p[2]
        local n = c >= 0 and r >= 0 and c < cols and r < rows and cells[r * cols + c + 1]
        if n then
            local t, e = D.TERRAIN[n.terrain], D.ELEV[n.elev]
            local f = t.food + e.food
            local pr = t.prod + e.prod + (n.feature and 1 or 0)
            if n.elev == "mountain" then f, pr = 0, 0 end
            s = s + f * 1.5 + pr + t.gold * 0.5 + (n.resource and 1 or 0)
        end
    end
    -- A river by the city: gold, and farms that yield more.
    if cell.river and next(cell.river) then s = s + 2 end
    return s
end
Mapgen.siteScore = siteScore

-- The map: { cols, rows, cells, starts } where starts are cells, one per
-- civilization. Tries the seeds after the one given until a map has room for
-- them all.
function Mapgen.generate(cols, rows, seed, civs)
    for attempt = 0, 40 do
        local cells, rng, rivers = build(cols, rows, seed + attempt * 7919)
        local piece = biggestLand(cells, cols, rows)
        local landCount = 0
        for _, cell in ipairs(cells) do
            if not D.TERRAIN[cell.terrain].water then landCount = landCount + 1 end
        end
        if #piece >= landCount * 0.5 then
            local candidates = {}
            for _, cell in ipairs(piece) do
                if cell.terrain ~= "desert" and cell.c > 1 and cell.r > 1 and cell.c < cols - 2 and cell.r < rows - 2 then
                    cell.score = siteScore(cells, cols, rows, cell)
                    candidates[#candidates + 1] = cell
                end
            end
            table.sort(candidates, function(a, b) return a.score > b.score end)
            -- The first among the best few, then each next the one furthest
            -- from those already taken, good land breaking ties.
            local starts = {}
            if #candidates > 0 then
                starts[1] = candidates[rng:random(min(6, #candidates))]
            end
            while #starts < civs and #candidates > 0 do
                local best, bestV
                for _, cell in ipairs(candidates) do
                    local d = math.huge
                    for _, s in ipairs(starts) do d = min(d, H.distance(cell.c, cell.r, s.c, s.r)) end
                    local v = min(d, 12) * 10 + cell.score
                    if not bestV or v > bestV then best, bestV = cell, v end
                end
                starts[#starts + 1] = best
            end
            local apart = math.huge
            for a = 1, #starts do
                for b = a + 1, #starts do
                    apart = min(apart, H.distance(starts[a].c, starts[a].r, starts[b].c, starts[b].r))
                end
            end
            if #starts == civs and apart >= 8 then
                return { cols = cols, rows = rows, cells = cells, starts = starts, rivers = rivers, seed = seed + attempt * 7919 }
            end
        end
    end
    error("no map with room for every civilization")
end

return Mapgen
