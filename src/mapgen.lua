-- Making a map from a seed: one or two continents out of a few octaves of
-- noise, mountains along the highest of it, deserts where the second noise is
-- dry, forests where a third is wet, a few resources, and a start for each
-- civilization on the biggest stretch of land, as far from the others as it
-- can be.
--
-- Thresholds are taken as shares of the map (quantiles) rather than noise
-- values, so every seed has about the same amount of land, hills and desert.

local H = require "src.hex"
local Rng = require "src.rng"
local D = require "src.defs"

local abs, max, min, floor = math.abs, math.max, math.min, math.floor

local Mapgen = {}

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
    return cells, rng
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
    return s
end
Mapgen.siteScore = siteScore

-- The map: { cols, rows, cells, starts } where starts are cells, one per
-- civilization. Tries the seeds after the one given until a map has room for
-- them all.
function Mapgen.generate(cols, rows, seed, civs)
    for attempt = 0, 40 do
        local cells, rng = build(cols, rows, seed + attempt * 7919)
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
                return { cols = cols, rows = rows, cells = cells, starts = starts, seed = seed + attempt * 7919 }
            end
        end
    end
    error("no map with room for every civilization")
end

return Mapgen
