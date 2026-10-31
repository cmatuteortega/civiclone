-- A sheet of cities as they grow, on the land they stand on: each picture a
-- little stretch of map traced by the same World the game traces (its
-- grass, sand, hills, rivers and sea), with a city laid on its middle hex by
-- depth, as the board lays it.
--
--   luajit tools/cities.lua [dir]
--
-- writes dir/cities-growth.ppm (each land, a row; each size, a column) and
-- dir/cities-sites.ppm (the same city in different places), at one pixel to
-- the pixel; scale them up by a whole number to look at them.

package.path = "./?.lua;" .. package.path

local ffi = require "ffi"
local T = require "src.tracer"
local H = require "src.hex"
local D = require "src.defs"
local M = require "src.models"
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
    Font.print(s, x, y)
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

local COLS, ROWS = 5, 4
local MID = { 2, 1 } -- the city's hex

-- A map of COLS x ROWS: `land(c, r)` answers terrain, elevation and feature
-- for each hex; `rivers` lists the edges ({ c, r, k }) a river runs along.
local function stretch(land, rivers)
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
    local function at(c, r) return cells[r * COLS + c + 1] end
    -- A river from the stretch's west edge to its east, along the edges
    -- between hexes, through the corner `through` ({ c, r, angle }).
    if rivers then
        local cell = at(rivers[1], rivers[2])
        local a = math.rad(rivers[3])
        local start = { cell.x + H.R * math.cos(a), cell.z + H.R * math.sin(a) }
        -- Every corner of every hex, and the edges between them.
        local edges = {}
        local function cornerKey(x, z) return floor(x * 4 + 0.5) .. ":" .. floor(z * 4 + 0.5) end
        local nextTo = {}
        for _, c in ipairs(cells) do
            for k = 0, 5 do
                local a0, a1 = math.rad(60 * k - 30), math.rad(60 * k + 30)
                local p = { c.x + H.R * math.cos(a0), c.z + H.R * math.sin(a0) }
                local q = { c.x + H.R * math.cos(a1), c.z + H.R * math.sin(a1) }
                local kp, kq = cornerKey(p[1], p[2]), cornerKey(q[1], q[2])
                nextTo[kp] = nextTo[kp] or { at = p }
                nextTo[kq] = nextTo[kq] or { at = q }
                nextTo[kp][kq], nextTo[kq][kp] = true, true
                local ek = kp < kq and kp .. "|" .. kq or kq .. "|" .. kp
                edges[ek] = edges[ek] or {}
                table.insert(edges[ek], { c, k })
            end
        end
        local function walk(dir)
            local path = { start }
            local here = cornerKey(start[1], start[2])
            for _ = 1, 12 do
                local best, bx
                for k in pairs(nextTo[here]) do
                    if k ~= "at" then
                        local p = nextTo[k].at
                        local score = (p[1] - nextTo[here].at[1]) * dir - math.abs(p[2] - start[2]) * 0.4
                        if not bx or score > bx then best, bx = k, score end
                    end
                end
                if not best or bx <= 0 then break end
                path[#path + 1] = nextTo[best].at
                here = best
            end
            return path
        end
        local west, east = walk(-1), walk(1)
        local path = {}
        for k = #west, 1, -1 do path[#path + 1] = west[k] end
        for k = 2, #east do path[#path + 1] = east[k] end
        for k = 1, #path - 1 do
            local p, q = path[k], path[k + 1]
            local kp, kq = cornerKey(p[1], p[2]), cornerKey(q[1], q[2])
            local list = edges[kp < kq and kp .. "|" .. kq or kq .. "|" .. kp]
            local level = math.huge
            for _, ce in ipairs(list) do level = math.min(level, ce[1].top) end
            local e = { size = 1, level = level - 2.5, from = p, to = q, fall = false, mouth = false, foot = false,
                name = "OSIER", at = k }
            for _, ce in ipairs(list) do
                ce[1].river = ce[1].river or {}
                ce[1].river[ce[2]] = e
            end
        end
    end
    return game, at
end

-- Traces the stretch, lays the city on its middle hex, and copies the
-- picture onto the sheet with its middle hex's middle at (px, py).
local SHORE = { 1, 2, 0, 3, 5, 4 }
local function scene(game, at, city, px, py)
    local cell = at(MID[1], MID[2])
    cell.city = true
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

    local shore
    for _, k in ipairs(SHORE) do
        local n = at(H.step(cell.c, cell.r, k))
        if n and D.TERRAIN[n.terrain].water then shore = k break end
    end
    local pic = M.city(city.look or "light", city.pop, city.capital, city.built, shore, shore and cell.top + 2,
        M.citySite(cell))
    local si, sj, d = world:toImage(cell.x, cell.top, cell.z)
    local bi, bj = floor(si) - pic.oi, floor(sj) - pic.oj
    for pj = 0, pic.h - 1 do
        for pi = 0, pic.w - 1 do
            local n = pj * pic.w + pi
            local k = pic.key[n]
            local i, j = bi + pi, bj + pj
            if k ~= 0 and i >= 0 and j >= 0 and i < w and j < h and d + pic.dep[n] >= dep[j * w + i] - 0.6 then
                img[j * w + i] = k
            end
        end
    end
    -- The middle hex's middle, on the stretch's picture.
    local ci, cj = world:toImage(cell.x, 4, cell.z)
    return img, w, h, ci, cj
end

-- Copies a box `bw` x `bh` round (ci, cj) of a picture onto the sheet at (x, y).
local function lay(img, w, h, ci, cj, x, y, bw, bh)
    for j = 0, bh - 1 do
        for i = 0, bw - 1 do
            local si, sj = floor(ci - bw / 2) + i, floor(cj - bh * 0.7) + j
            if si >= 0 and sj >= 0 and si < w and sj < h and img[sj * w + si] ~= 0 then
                put(img[sj * w + si], x + i, y + j)
            end
        end
    end
end

--- the lands --------------------------------------------------------------------------

local function plain(base, around)
    return function(c, r)
        if c == MID[1] and r == MID[2] then return base end
        local a = around and around(c, r)
        if a then return a[1], a[2], a[3] end
        return base
    end
end
local LANDS = {
    { "GRASSLAND", plain("grass", function(c, r)
        if (c + r * 2) % 5 == 0 then return { "grass", "flat", "forest" } end
    end) },
    { "PLAINS", plain("plains", function(c, r)
        if (c * 3 + r) % 7 == 0 then return { "grass" } end
    end) },
    { "DESERT", plain("desert", function(c, r)
        if (c + r) % 6 == 0 then return { "desert", "hills" } end
    end) },
    { "HILLS", function(c, r)
        if c == MID[1] and r == MID[2] then return "grass", "hills" end
        if (c + r) % 3 == 0 then return "grass", "mountain" end
        if (c + r) % 2 == 0 then return "plains", "hills" end
        return "grass", "hills", (c % 2 == 0) and "forest" or nil
    end },
}

local SIZES = {
    { 1, "HAMLET - 1" }, { 4, "VILLAGE - 4" }, { 7, "TOWN - 7" }, { 12, "CITY - 12" },
}

local BW, BH = 70, 74
do
    local left = 46
    sheet(left + BW * #SIZES, 14 + BH * #LANDS)
    for col, s in ipairs(SIZES) do text(s[2], left + (col - 0.5) * BW, 4, true) end
    for row, land in ipairs(LANDS) do
        for col, s in ipairs(SIZES) do
            local game, at = stretch(land[2])
            local img, w, h, ci, cj = scene(game, at, { pop = s[1], look = arg[2] or "dark" },
                0, 0)
            lay(img, w, h, ci, cj, left + (col - 1) * BW, 14 + (row - 1) * BH, BW, BH)
        end
        text(land[1], 3, 14 + (row - 0.5) * BH)
    end
    write("cities-growth")
end

-- The same sizes of city in different places: by a river, on the coast, a
-- capital, and one with everything built, in each civilization's colours.
do
    local everything = { granary = true, library = true, market = true, monument = true, walls = true }
    local SITES = {
        { "RIVER, GRASS", plain("grass"), { MID[1], MID[2], 150 }, { pop = 5 } },
        { "RIVER, DESERT", plain("desert"), { MID[1], MID[2], 30 }, { pop = 9, look = "dark" } },
        { "COAST, PLAINS", plain("plains", function(c, r) if r >= 2 then return { "coast" } end end), nil,
            { pop = 6, look = "stripe", built = { harbour = true } } },
        { "CAPITAL, HILLS", function(c, r)
            if c == MID[1] and r == MID[2] then return "plains", "hills" end
            return "plains", (c + r) % 2 == 0 and "hills" or "flat"
        end, nil, { pop = 11, capital = true, look = "dark" } },
        { "CAPITAL, DESERT", plain("desert"), nil, { pop = 12, capital = true, look = "stripe", built = everything } },
        { "WALLED, GRASS", plain("grass"), nil, { pop = 10, built = everything } },
        { "COAST, DESERT", plain("desert", function(c, r) if r >= 2 then return { "coast" } end end), nil,
            { pop = 10, built = { harbour = true, lighthouse = true } } },
        { "RIVER, HILLS", plain("grass", function() return { "grass", "hills" } end), { MID[1], MID[2], 150 },
            { pop = 3, look = "stripe" } },
    }
    local per = 4
    sheet(BW * per, (BH + 10) * math.ceil(#SITES / per))
    for k, s in ipairs(SITES) do
        local col, row = (k - 1) % per, floor((k - 1) / per)
        local land = s[2]
        if s[1]:find("HILLS") and not s[1]:find("CAPITAL") then
            land = function(c, r)
                if c == MID[1] and r == MID[2] then return "grass", "hills" end
                return "grass", (c + r) % 2 == 0 and "hills" or "flat"
            end
        end
        local game, at = stretch(land, s[3])
        local img, w, h, ci, cj = scene(game, at, s[4])
        lay(img, w, h, ci, cj, col * BW, row * (BH + 10), BW, BH)
        text(s[1], (col + 0.5) * BW, row * (BH + 10) + BH + 2, true)
    end
    write("cities-sites")
end
