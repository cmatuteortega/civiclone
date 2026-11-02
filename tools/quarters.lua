-- Sheets of cities grown out over their quarters (src/quarters.lua): each
-- picture a stretch of map traced by the same World the game traces, the
-- city's middle hex and its quarters laid on it by depth, as the board lays
-- a city.
--
--   luajit tools/quarters.lua [dir]
--
-- writes dir/quarters-growth.ppm (each land, a row; a city growing out
-- over one, two and three quarters, along it), dir/quarters-kinds.ppm (the
-- quarter each land, the water and a river make, full) and
-- dir/quarters-rings.ppm (what goes round a city of several hexes: walls
-- with their gates, a river as its moat and a stone bridge between its
-- hexes, the levee, the buttress, the plague), at one pixel to the pixel.

package.path = "./?.lua;" .. package.path

local ffi = require "ffi"
local T = require "src.tracer"
local H = require "src.hex"
local D = require "src.defs"
local M = require "src.models"
local Q = require "src.quarters"
local Font = require "src.font"
local World = require "src.world"

local floor = math.floor
local IDX = T.IDX

--- the sheet --------------------------------------------------------------------------

local W, HT, key = 0, 0, {}
local function sheet(w, h)
    W, HT, key = w, h, {}
    for n = 0, W * HT - 1 do key[n] = IDX.c end
end
local function put(k, x, y)
    if k ~= 0 and x >= 0 and y >= 0 and x < W and y < HT then key[y * W + x] = k end
end
local ink = IDX.o
love = { graphics = { rectangle = function(_, x, y) put(ink, floor(x), floor(y)) end } }
local function text(s, x, y, centre)
    if centre then x = floor(x - Font.width(s) / 2) end
    ink = IDX.o
    -- At a fraction of a pixel the font is plotted a pixel at a time, which
    -- is all the stand-in for LÖVE above can draw.
    Font.print(s, x + 0.25, y + 0.25)
end
local function write(name)
    local out = assert(io.open((arg[1] or ".") .. "/" .. name .. ".ppm", "wb"))
    out:write(("P6\n%d %d\n255\n"):format(W, HT))
    local buf = {}
    for n = 0, W * HT - 1 do
        local c = T.RGB[key[n]]
        buf[#buf + 1] = string.char(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
    end
    out:write(table.concat(buf))
    out:close()
end

--- a stretch of map ---------------------------------------------------------------------

local COLS, ROWS = 6, 5
local MID = { 2, 2 }

-- `land(c, r)` answers terrain, elevation and feature for each hex; `river`
-- is a list of corners ({ c, r, k }: hex (c, r)'s corner k) a river runs
-- along, from the first to the last, down to the water level of each edge.
local function corner(cell, k)
    local a = math.rad(60 * k - 30)
    return { cell.x + H.R * math.cos(a), cell.z + H.R * math.sin(a) }
end
local function stretch(land, river)
    local cells = {}
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            local x, z = H.center(c, r)
            local terrain, elev, feature = land(c, r)
            local t = D.TERRAIN[terrain]
            local top = t.top + (t.water and 0 or D.ELEV[elev or "flat"].rise)
            cells[#cells + 1] = { id = r * COLS + c + 1, c = c, r = r, x = x, z = z, terrain = terrain,
                elev = elev or "flat", feature = feature, top = top }
        end
    end
    local game = { cells = cells, cols = COLS, rows = ROWS }
    local function at(c, r)
        if c < 0 or r < 0 or c >= COLS or r >= ROWS then return nil end
        return cells[r * COLS + c + 1]
    end
    if river then
        local function near(p, q) return math.abs(p[1] - q[1]) < 0.5 and math.abs(p[2] - q[2]) < 0.5 end
        local pts = {}
        for _, s in ipairs(river) do pts[#pts + 1] = corner(at(s[1], s[2]), s[3]) end
        for n = 1, #pts - 1 do
            local p, q = pts[n], pts[n + 1]
            local list = {}
            for _, cell in ipairs(cells) do
                for k = 0, 5 do
                    local a, b = corner(cell, k), corner(cell, k + 1)
                    if (near(a, p) and near(b, q)) or (near(a, q) and near(b, p)) then list[#list + 1] = { cell, k } end
                end
            end
            local level = math.huge
            for _, ce in ipairs(list) do level = math.min(level, ce[1].top) end
            local e = { size = 1, level = level - 2.5, from = p, to = q, fall = false, mouth = false, foot = false,
                name = "OSIER", at = n }
            for _, ce in ipairs(list) do
                ce[1].river = ce[1].river or {}
                ce[1].river[ce[2]] = e
            end
        end
    end
    return game, at
end

-- The city's hexes, as steps from the middle hex: { k, ... } walks from the
-- middle each way in turn, so { {}, { 0 }, { 1 } } is the middle, its east
-- neighbour and its south-east one.
local function hexesOf(path)
    local out = {}
    for _, steps in ipairs(path) do
        local c, r = MID[1], MID[2]
        for _, k in ipairs(steps) do c, r = H.step(c, r, k) end
        out[#out + 1] = { c = c, r = r }
    end
    return out
end

local SHORE = { 1, 2, 0, 3, 5, 4 }
local function shoreOf(at, cell)
    for _, k in ipairs(SHORE) do
        local n = at(H.step(cell.c, cell.r, k))
        if n and D.TERRAIN[n.terrain].water then return k end
    end
end

-- Traces the stretch and lays the city on it: `city` is { look, pop,
-- capital, built, hexes = { path as hexesOf takes }, stages = { per quarter },
-- marked }. Answers the picture, its size and where the middle hex's middle
-- falls on it.
local function scene(game, at, city)
    local hexes = hexesOf(city.hexes or { {} })
    local fabric = Q.fabric(hexes)
    for n, h in ipairs(hexes) do
        local cell = at(h.c, h.r)
        if n == 1 then cell.city = true else cell.quarter = true end
        h.cell = cell
    end
    local world = World.new(game)
    local w, h = world.w, world.h
    local b = T.buffer(w, h)
    b.open = true
    for _, f in ipairs({ { "cell", "int16_t" }, { "flat", "int16_t" }, { "edge", "uint8_t" }, { "flatEdge", "uint8_t" },
        { "wx", "float" }, { "wy", "float" }, { "wz", "float" }, { "up", "uint8_t" }, { "sea", "uint8_t" },
        { "shore", "uint8_t" }, { "kind", "uint8_t" }, { "sway", "uint8_t" }, { "inked", "uint8_t" } }) do
        b[f[1]] = ffi.new(f[2] .. "[?]", w * h)
    end
    world.buf = b
    world:bin()
    world:trace(0, 0, w - 1, h - 1)
    T.finish(b, 1.2)
    local img, dep = {}, {}
    for n = 0, w * h - 1 do img[n], dep[n] = b.key[n], b.dep[n] end

    local built = city.built or {}
    -- Once it has a docks quarter, the harbour and the lighthouse are
    -- there, and the middle keeps only its pier.
    local middle = built
    for n = 2, #hexes do
        if shoreOf(at, hexes[n].cell) then
            middle = {}
            for k, v in pairs(built) do middle[k] = v end
            middle.harbour, middle.lighthouse = nil, nil
            break
        end
    end
    local docked = false
    for n, hx in ipairs(hexes) do
        local cell, f = hx.cell, fabric[n]
        local shore = shoreOf(at, cell)
        local site = M.citySite(cell)
        local pic
        if n == 1 then
            site.joins = next(f.joins) and f.joins or nil
            site.towers = site.joins and f.towers or nil
            pic = M.city(city.look or "light", city.pop, city.capital, middle, shore, shore and cell.top + 2, site,
                city.marked and { marked = true } or nil)
        else
            pic = M.quarter(city.look or "light", { biome = site.biome, hills = site.hills, snow = site.snow,
                seed = site.seed, river = site.river, stage = (city.stages or {})[n - 1] or 3, toward = f.toward,
                gate = f.gate, joins = f.joins, towers = f.towers, shore = shore, drop = shore and cell.top + 2,
                built = built, marked = city.marked, docks = shore and not docked })
            docked = docked or shore ~= nil
        end
        local si, sj, d = world:toImage(cell.x, cell.top, cell.z)
        local bi, bj = floor(si) - pic.oi, floor(sj) - pic.oj
        for pj = 0, pic.h - 1 do
            for pi = 0, pic.w - 1 do
                local m = pj * pic.w + pi
                local k = pic.key[m]
                local i, j = bi + pi, bj + pj
                if k ~= 0 and i >= 0 and j >= 0 and i < w and j < h then
                    local z = d + pic.dep[m]
                    if z >= dep[j * w + i] - 0.6 then
                        img[j * w + i] = k
                        dep[j * w + i] = math.max(dep[j * w + i], z)
                    end
                end
            end
        end
    end
    local mid = at(MID[1], MID[2])
    local ci, cj = world:toImage(mid.x, 4, mid.z)
    return img, w, h, ci, cj
end

-- Copies a box `bw` x `bh` round (ci, cj) of a picture onto the sheet at
-- (x, y), the middle hex a little left of and below its middle.
local function lay(img, w, h, ci, cj, x, y, bw, bh, ox, oy)
    ox, oy = ox or 0.44, oy or 0.6
    for j = 0, bh - 1 do
        for i = 0, bw - 1 do
            local si, sj = floor(ci - bw * (ox or 0.4)) + i, floor(cj - bh * (oy or 0.62)) + j
            if si >= 0 and sj >= 0 and si < w and sj < h and img[sj * w + si] ~= 0 then
                put(img[sj * w + si], x + i, y + j)
            end
        end
    end
end

--- the lands --------------------------------------------------------------------------

local function plain(base, around)
    return function(c, r)
        local a = around and around(c, r)
        if a then return a[1], a[2], a[3] end
        return base
    end
end
local function hills(c, r)
    if (c + r * 3) % 7 == 0 and not (r == 2 and c >= 1 and c <= 3) then return "grass", "mountain" end
    return (c + r) % 3 == 0 and "plains" or "grass", "hills"
end
local LANDS = {
    { "GRASSLAND", plain("grass", function(c, r)
        if (c + r * 2) % 5 == 0 and (r < 1 or r > 3 or c > 4) then return { "grass", "flat", "forest" } end
    end) },
    { "PLAINS", plain("plains", function(c, r) if (c * 3 + r) % 7 == 0 and r ~= 2 then return { "grass" } end end) },
    { "DESERT", plain("desert", function(c, r) if (c + r) % 6 == 0 and r ~= 2 and r ~= 3 then return { "desert", "hills" } end end) },
    { "HILLS", hills },
}

-- A city growing: the middle alone, then out east, south-east and west.
local GROWTH = {
    { "POP 6", { pop = 6, hexes = { {} } } },
    { "POP 8: A QUARTER", { pop = 8, hexes = { {}, { 0 } }, stages = { 1 } } },
    { "POP 11: FILLED", { pop = 11, hexes = { {}, { 0 } }, stages = { 3 } } },
    { "POP 14: TWO", { pop = 14, hexes = { {}, { 0 }, { 1 } }, stages = { 3, 2 } } },
    { "POP 20: THREE, WALLED", { pop = 20, hexes = { {}, { 0 }, { 1 }, { 3 } }, stages = { 3, 3, 3 },
        built = { walls = true, granary = true, library = true, market = true, monument = true } } },
}

local BW, BH = 176, 118

-- A river down past the city's middle, round its east and south: along
-- its north-east, east, south-east and south-west edges.
local RIVER = { { 2, 1, 4 }, { 2, 2, 5 }, { 2, 2, 0 }, { 2, 2, 1 }, { 2, 2, 2 }, { 2, 2, 3 }, { 1, 2, 2 }, { 1, 2, 3 } }
local out = arg[1] or "."

do
    local left = 50
    sheet(left + BW * #GROWTH, 14 + BH * #LANDS)
    for col, g in ipairs(GROWTH) do text(g[1], left + (col - 0.5) * BW, 4, true) end
    for row, land in ipairs(LANDS) do
        for col, g in ipairs(GROWTH) do
            local game, at = stretch(land[2])
            local city = {}
            for k, v in pairs(g[2]) do city[k] = v end
            city.look = ({ "light", "dark", "stripe", "light" })[row]
            local img, w, h, ci, cj = scene(game, at, city)
            lay(img, w, h, ci, cj, left + (col - 1) * BW, 14 + (row - 1) * BH, BW, BH)
        end
        text(land[1], 3, 14 + (row - 0.5) * BH)
        io.write(".") io.flush()
    end
    write("quarters-growth")
end

-- The quarter each place makes, full, beside its city's middle.
do
    local coast = function(base)
        return plain(base, function(c, r) if r >= 3 or (r == 2 and c >= 4) then return { "coast" } end end)
    end
    local KINDS = {
        { "GRASS: GUILDHALL", plain("grass"), nil, { pop = 11, hexes = { {}, { 0 } } } },
        { "PLAINS: BARN, MILL", plain("plains"), nil, { pop = 11, look = "stripe", hexes = { {}, { 0 } } } },
        { "DESERT: BAZAAR", plain("desert"), nil, { pop = 11, look = "dark", hexes = { {}, { 0 } } } },
        { "HILLS: SHRINE", hills, nil, { pop = 11, hexes = { {}, { 0 } } } },
        { "COAST: DOCKS", coast("plains"), nil,
            { pop = 12, look = "dark", hexes = { {}, { 0 } }, built = { harbour = true, lighthouse = true } } },
        { "RIVER: MILL, BRIDGE", plain("grass"), RIVER,
            { pop = 11, look = "stripe", hexes = { {}, { 0 } } } },
    }
    local per = 3
    sheet(BW * per, (BH + 10) * math.ceil(#KINDS / per))
    for k, s in ipairs(KINDS) do
        local col, row = (k - 1) % per, floor((k - 1) / per)
        local game, at = stretch(s[2], s[3])
        local img, w, h, ci, cj = scene(game, at, s[4])
        lay(img, w, h, ci, cj, col * BW, row * (BH + 10), BW, BH)
        text(s[1], (col + 0.5) * BW, row * (BH + 10) + BH + 2, true)
        io.write(".") io.flush()
    end
    write("quarters-kinds")
end

-- What goes round a city of several hexes.
do
    local everything = { walls = true, granary = true, library = true, market = true, monument = true }
    local RINGS = {
        { "WALLS AND GATES", plain("grass"), nil,
            { pop = 17, hexes = { {}, { 0 }, { 2 } }, stages = { 3, 3 }, built = everything } },
        { "RIVER: MOAT, BRIDGE", plain("grass"), RIVER,
            { pop = 15, look = "dark", hexes = { {}, { 0 }, { 1 } }, stages = { 3, 2 }, built = everything } },
        { "COAST, WALLED", plain("plains", function(c, r) if r >= 3 or (r == 2 and c >= 4) then return { "coast" } end end),
            nil, { pop = 15, look = "stripe", hexes = { {}, { 0 }, { 3 } }, stages = { 3, 3 },
            built = { walls = true, harbour = true, lighthouse = true, market = true } } },
        { "LEVEE", plain("grass"), RIVER,
            { pop = 13, hexes = { {}, { 0 }, { 2 } }, stages = { 3, 2 }, built = { levee = true } } },
        { "SNOW, BUTTRESS", plain("tundra", function(c, r) if (c + r) % 4 == 0 then return { "snow" } end end), nil,
            { pop = 14, look = "dark", hexes = { {}, { 0 }, { 1 } }, stages = { 3, 2 },
                built = { buttress = true, walls = true, hearth = true } } },
        { "PLAGUE", plain("plains"), nil,
            { pop = 13, look = "stripe", hexes = { {}, { 3 }, { 0 } }, stages = { 3, 2 }, marked = true,
                built = { lazaret = true } } },
    }
    local per = 3
    sheet(BW * per, (BH + 10) * math.ceil(#RINGS / per))
    for k, s in ipairs(RINGS) do
        local col, row = (k - 1) % per, floor((k - 1) / per)
        local game, at = stretch(s[2], s[3])
        local img, w, h, ci, cj = scene(game, at, s[4])
        lay(img, w, h, ci, cj, col * BW, row * (BH + 10), BW, BH)
        text(s[1], (col + 0.5) * BW, row * (BH + 10) + BH + 2, true)
        io.write(".") io.flush()
    end
    write("quarters-rings")
end
print()
