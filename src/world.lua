-- The map as a picture: every hex and what stands on it, traced once.
--
-- As in underroot, the camera has no perspective, so a picture of the map is
-- the same picture whatever happens on it. It is traced once at load, a
-- pixel at a time, into one image -- and into a depth buffer the same size,
-- which is what lets a warrior go behind a mountain or a city stand among
-- trees without anything being traced again. Each pixel also keeps which hex
-- it belongs to, which is how a click lands on a hex, how fog is laid over
-- the hexes no one has seen, and how a highlight finds a hex's top.
--
-- Each hex is a prism standing as high as its ground: water low and flat,
-- the land in two terraces, hills a step up with mounds on top, mountains a
-- step more with peaks of rock. Forests are trees, resources are sheaves and
-- boulders and crystals. When a hex changes (a city clears its forest) only
-- the hex is built again and only its corner of the picture traced again.

local ffi = require "ffi"
local T = require "src.tracer"
local Sh = require "src.shapes"
local H = require "src.hex"
local D = require "src.defs"

local max, min, abs, floor, ceil, sin = math.max, math.min, math.abs, math.floor, math.ceil, math.sin
local IDX = T.IDX
local ramp = T.ramp

local World = {}
World.__index = World

local BOTTOM = -8   -- how deep the map's block goes, seen along its south edge
local BACK = 2000
local BIN = 16
local FLAT = 3      -- the level fog is laid at

-- A cheap hash for grain: the same speck lands in the same place every time.
local function grain(x, z, k)
    local n = sin(floor(x) * 12.9898 + floor(z) * 78.233 + (k or 0) * 37.719) * 43758.5453
    return n - floor(n)
end

-- How far room point (x, z) is from hex `cell`'s edge: below nothing inside it,
-- the true distance outside, corners rounded (Inigo Quilez's hexagon).
local function hexDistance(cell, x, z)
    local px, py = abs(z - cell.z), abs(x - cell.x)
    local d = 2 * min(-0.866025404 * px + 0.5 * py, 0)
    px, py = px + 0.866025404 * d, py - 0.5 * d
    local k = 0.577350269 * H.APOTHEM
    px, py = px - max(-k, min(k, px)), py - H.APOTHEM
    local l = math.sqrt(px * px + py * py)
    return py < 0 and -l or l
end

--- what things are made of ---------------------------------------------------------

-- `print` answers a key index for a pixel that is printed rather than lit (a
-- furrow, a ripple, a speck of grit), a ramp to light it with instead, or
-- nothing to take the material's own.
local SIDE = ramp("s", "t", "n", "u")
local SIDE_DARK = ramp("t", "n", "u", "o")

-- The cut side of a hex: earth in bands.
local function strata(x, y, z, lev)
    local band = floor((-y + 0.6 * sin((x + z) * 0.2)) / 2.5)
    if band % 3 == 2 then return SIDE_DARK end
    return SIDE
end

local MAT = {}

-- The kinds of land the moving picture knows (after 1 ocean and 2 coast).
local LAND = { crown = 3, sheaf = 4, grass = 5, plains = 6, other = 7 }
World.LAND = LAND

MAT.grass = { id = 1, ramp = ramp("s", "k", "n", "u"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    local g = grain(x, z, 1)
    if g > 0.93 then return IDX.n end           -- tufts
    if g < 0.04 then return IDX.t end           -- flowers
    if ny > 0.9 and grain(floor(x / 3), floor(z / 2), 2) > 0.86 then return IDX.n end
end }
MAT.plains = { id = 2, ramp = ramp("c", "t", "k", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    local g = grain(x, z, 3)
    if g > 0.94 then return IDX.k end
    if g < 0.03 then return IDX.s end
    -- Dry grass in long strokes, leaning.
    if ny > 0.9 and (floor(x + z * 0.5) % 7 == 0) and grain(floor(x / 4), z, 4) > 0.45 then return IDX.k end
end }
MAT.desert = { id = 3, ramp = ramp("w", "c", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    -- Dunes: ripples running across.
    local d = sin(x * 0.35 + sin(z * 0.25) * 2.2 + z * 0.1)
    if ny > 0.9 and abs(d - 0.75) < 0.12 then return IDX.s end
    if grain(x, z, 5) > 0.96 then return IDX.t end
end }

-- Water: the sea's top, by what kind of water the hex is. Ripples, glints,
-- and foam where it meets the land.
local function water(s, x, z, deep)
    local g = grain(x, z, 13)
    local ripple = sin(x * 0.45 + z * 0.2) + sin(z * 0.6 - x * 0.17)
    if g > 0.998 then return IDX.c end
    local cell = s.cellRef
    if cell and not deep then
        -- Foam along any edge with land beyond it.
        for k = 0, 5 do
            local a = math.rad(60 * k)
            local inside = H.APOTHEM - ((x - cell.x) * math.cos(a) + (z - cell.z) * math.sin(a))
            if inside < 2.2 then
                local c, r = H.step(cell.c, cell.r, k)
                local n = s.world:cellAt(c, r)
                if n and not D.TERRAIN[n.terrain].water then
                    if inside < 1.1 or grain(x * 2, z, 17) > 0.5 then return IDX.c end
                end
            end
        end
    end
    if deep then
        if abs(ripple - 1.1) < 0.08 then return IDX.n end
        if abs(ripple + 0.7) < 0.06 then return IDX.o end
        return IDX.u
    end
    if abs(ripple - 1.0) < 0.1 then return IDX.t end
    if abs(ripple + 0.6) < 0.08 then return IDX.u end
    return IDX.n
end
MAT.ocean = { id = 4, ramp = ramp("n", "u", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return SIDE_DARK end
    return water(s, x, z, true)
end }
MAT.coast = { id = 5, ramp = ramp("k", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 then return SIDE_DARK end
    return water(s, x, z, false)
end }
MAT.rock = { id = 6, ramp = ramp("c", "t", "k", "n"), print = function(s, x, y, z, nx, ny, nz, lev)
    if ny < 0.6 and s.prism then return strata(x, y, z, lev) end
    -- Snow on the high faces that look up.
    if s.snow and y > s.snow and ny > 0.3 then return lev <= 3 and IDX.w or IDX.c end
    local g = grain(x * 1.5, z + y * 2, 6)
    if g > 0.94 then return IDX.n end
end }
MAT.tree = { id = 7, ramp = ramp("t", "n", "u", "o"), print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(x * 2, y * 2 + z, 7) > 0.88 and lev <= 3 then return IDX.u end
end }
MAT.trunk = { id = 8, ramp = ramp("t", "n", "u", "o") }
MAT.wheat = { id = 9, ramp = ramp("w", "c", "s", "t"), print = function(s, x, y, z, nx, ny, nz, lev)
    if grain(x * 3, y * 3, 8) > 0.8 then return IDX.t end
end }
MAT.stone = { id = 10, ramp = ramp("w", "c", "k", "n") }
MAT.gem = { id = 11, ramp = ramp("w", "w", "s", "k") }
-- Hills are their ground's own stuff, but a material of their own, so no
-- crease rings them where they meet the flat.
local MOUND = {}
for _, k in ipairs({ "grass", "plains", "desert" }) do
    MOUND[k] = { id = MAT[k].id + 20, ramp = MAT[k].ramp, print = MAT[k].print }
end

--- building the solids --------------------------------------------------------------

-- A hex prism in the room, standing from the map's bottom up to `top`.
local function hexPrism(cx, cz, top)
    local planes = {}
    for k = 0, 5 do
        local a = math.rad(60 * k)
        local nx, nz = math.cos(a), math.sin(a)
        planes[#planes + 1] = { nx, 0, nz, nx * cx + nz * cz + H.APOTHEM }
    end
    planes[#planes + 1] = { 0, 1, 0, top }
    planes[#planes + 1] = { 0, -1, 0, -BOTTOM }
    return { kind = "hull", planes = planes, prism = true,
        box = { cx - H.APOTHEM, cx + H.APOTHEM, BOTTOM, top, cz - H.R, cz + H.R } }
end

-- Points scattered over a hex, kept `inset` in from its edge: the same ones
-- for the same hex every time.
local function scatter(cell, n, inset, k)
    local out = {}
    local tries = 0
    while #out < n and tries < n * 12 do
        tries = tries + 1
        local x = cell.x + (grain(cell.id, tries, k) * 2 - 1) * H.R
        local z = cell.z + (grain(tries, cell.id, k + 1) * 2 - 1) * H.R
        if H.inset(x, z, cell.x, cell.z) > inset then
            local ok = true
            for _, p in ipairs(out) do
                if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < 20 then ok = false end
            end
            if ok then out[#out + 1] = { x, z } end
        end
    end
    -- Back to front, so nothing depends on the order they were found in.
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

-- The solids of one hex.
function World:hexSolids(cell)
    local out = {}
    local function add(s, mat)
        s.mat, s.cell, s.cellRef, s.world = mat, cell.id, cell, self
        out[#out + 1] = s
        return s
    end
    local t = D.TERRAIN[cell.terrain]
    local top = cell.top
    local base = cell.elev == "mountain" and MAT.rock or MAT[cell.terrain]
    add(hexPrism(cell.x, cell.z, top), base)
    if t.water then return out end

    if cell.elev == "hills" and not cell.city then
        -- One broad mound in the middle, a unit stands on it, and a smaller
        -- one off to a side. A city levels them.
        add(Sh.ell(cell.x, top - 0.8, cell.z, 9.5, 4, 7.5), MOUND[cell.terrain])
        local a = grain(cell.id, 7, 21) * math.pi * 2
        add(Sh.ell(cell.x + math.cos(a) * 7, top - 0.5, cell.z + math.sin(a) * 5, 4.5, 2.6, 3.5), MOUND[cell.terrain])
    elseif cell.elev == "mountain" then
        -- A ring of five to seven points round (cx, cz), each pushed in or out.
        local function ring(cx, cz, r, seed)
            local poly = {}
            local sides = 5 + floor(grain(cell.id, 9, seed) * 3)
            for k = 0, sides - 1 do
                local a = math.rad(360 * k / sides + grain(cell.id, 0, seed) * 60 + (grain(cell.id, k, seed) - 0.5) * 18)
                local rr = r * (0.82 + grain(k, cell.id, seed) * 0.18)
                poly[#poly + 1] = { cx + rr * math.cos(a), cz + rr * math.sin(a) }
            end
            return poly
        end
        local ox = (grain(cell.id, 1, 30) - 0.5) * 5
        local h = 13 + grain(cell.id, 2, 30) * 10
        local main = add(Sh.peak(ring(cell.x + ox * 0.5, cell.z, H.R * 0.92, 31), top,
            { cell.x + ox, top + h, cell.z - 1 - grain(cell.id, 4, 30) * 2 }), MAT.rock)
        main.snow = top + h * 0.6
        local roll = grain(cell.id, 3, 30)
        if roll > 0.3 then
            local side = roll > 0.65 and 1 or -1
            local sx, sz = cell.x - side * 6, cell.z + 3
            local h2 = h * (0.4 + grain(cell.id, 5, 30) * 0.25)
            local second = add(Sh.peak(ring(sx, sz, H.R * 0.55, 32), top, { sx - side * 1.5, top + h2, sz }), MAT.rock)
            second.snow = top + h2 * 0.7
        end
    end

    if cell.feature == "forest" and not cell.city then
        local pts = scatter(cell, cell.elev == "hills" and 4 or 5, 3.5, 40)
        for n, p in ipairs(pts) do
            local x, z = p[1], p[2]
            local g = top + (cell.elev == "hills" and 1 or 0)
            local tall = 0.85 + grain(x, z, 41) * 0.35
            add(Sh.seg(x, g - 0.5, z, x, g + 3 * tall, z, 0.9), MAT.trunk)
            if cell.elev == "hills" or (cell.terrain == "plains" and n % 2 == 0) then
                -- A pine: two tiers of needles.
                add(Sh.pyramid(6, x, g + 2 * tall, z, 4 * tall, 6 * tall, 0, 0.3), MAT.tree)
                add(Sh.pyramid(6, x, g + 5 * tall, z, 3 * tall, 5 * tall, 0, 0.8), MAT.tree)
            else
                add(Sh.ell(x, g + 5.5 * tall, z, 3.8 * tall, 3.6 * tall, 3.8 * tall), MAT.tree)
            end
        end
    end

    if cell.city then return out end
    if cell.resource == "wheat" then
        for _, p in ipairs(scatter(cell, 4, 4, 50)) do
            add(Sh.ell(p[1], top + 2, p[2], 1.1, 2.4, 1.1), MAT.wheat)
        end
    elseif cell.resource == "stone" then
        for n, p in ipairs(scatter(cell, 3, 4, 60)) do
            local r = n == 1 and 2.6 or 1.8
            add(Sh.ell(p[1], top + (cell.elev == "hills" and 1.5 or 0.8), p[2], r, r * 0.8, r), MAT.stone)
        end
    elseif cell.resource == "gems" then
        for _, p in ipairs(scatter(cell, 2, 5, 70)) do
            add(Sh.pyramid(4, p[1], top + 2.2, p[2], 1.6, 3, 0, 0.4), MAT.gem)
            local low = Sh.pyramid(4, p[1], top + 2.2, p[2], 1.6, 2, 0, 0.4)
            low.at = T.Affine.mul(T.Affine.move(p[1], 2 * (top + 2.2), p[2]), T.Affine.scale(1, -1, 1),
                T.Affine.move(-p[1], 0, -p[2]), low.at)
            add(low, MAT.gem)
        end
    end
    return out
end

--- the picture --------------------------------------------------------------------

function World.new(game)
    local self = setmetatable({}, World)
    self.game = game
    self.cells = game.cells
    self.cols, self.rows = game.cols, game.rows
    self.X, self.Z = H.size(self.cols, self.rows)
    local i0, i1, j0, j1 = T.screenBox(0, self.X, BOTTOM, 40, 0, self.Z)
    self.i0, self.j0 = floor(i0) - 6, floor(j0) - 6
    self.w, self.h = ceil(i1) - self.i0 + 6, ceil(j1) - self.j0 + 6
    self.solids, self.byCell = {}, {}
    self.nextPart = 1
    for _, cell in ipairs(self.cells) do self:addCell(cell) end
    return self
end

function World:cellAt(c, r)
    if c < 0 or r < 0 or c >= self.cols or r >= self.rows then return nil end
    return self.cells[r * self.cols + c + 1]
end

function World:addCell(cell)
    local list = self:hexSolids(cell)
    for _, s in ipairs(list) do
        s.part = self.nextPart
        self.nextPart = self.nextPart % 32000 + 1
        T.prepare(s)
        self.solids[#self.solids + 1] = s
        if self.bins then self:binOne(s) end
    end
    self.byCell[cell.id] = list
end

-- The screen box of a solid, in pixels of the picture.
function World:boxOf(s)
    local i0, i1, j0, j1 = T.screenBox(T.bounds(s))
    return floor(i0) - self.i0 - 1, ceil(i1) - self.i0 + 1, floor(j0) - self.j0 - 1, ceil(j1) - self.j0 + 1
end

-- Where each solid can land on the screen, binned in 16-pixel squares, so a
-- pixel only asks the handful that could be in it.
function World:binOne(s)
    local i0, i1, j0, j1 = self:boxOf(s)
    for by = max(0, floor(j0 / BIN)), min(self.bh - 1, floor(j1 / BIN)) do
        for bx = max(0, floor(i0 / BIN)), min(self.bw - 1, floor(i1 / BIN)) do
            local list = self.bins[by * self.bw + bx + 1]
            list[#list + 1] = s
        end
    end
end

function World:bin()
    self.bw, self.bh = ceil(self.w / BIN), ceil(self.h / BIN)
    self.bins = {}
    for n = 1, self.bw * self.bh do self.bins[n] = {} end
    for _, s in ipairs(self.solids) do self:binOne(s) end
end

-- Traces the pixels from (i0, j0) to (i1, j1) of the picture. `yield` is told
-- each few rows done.
function World:trace(i0, j0, i1, j1, yield)
    local b = self.buf
    local w = self.w
    local HIT = T.HIT
    for pj = j0, j1 do
        for pi = i0, i1 do
            local si, sj = self.i0 + pi + 0.5, self.j0 + pj + 0.5
            local ox, oy, oz = T.origin(si, sj, BACK)
            local bt, best, nx, ny, nz, ux, uy, uz = math.huge, nil, 0, 1, 0, 0, 0, 0
            for _, s in ipairs(self.bins[floor(pj / BIN) * self.bw + floor(pi / BIN) + 1]) do
                if not s.dead then
                    local t, ax, ay, az, lx, ly, lz = HIT[s.kind](s, ox, oy, oz)
                    if t and t < bt then
                        bt, best, nx, ny, nz, ux, uy, uz = t, s, ax, ay, az, lx, ly, lz
                    end
                end
            end
            local n = pj * w + pi
            -- Where the ray meets the fog's level: the hex shown there when the
            -- one traced is not known yet.
            local fx, fz = T.onLevel(si, sj, FLAT)
            local fc, fr = H.at(fx, fz)
            local flat = self:cellAt(fc, fr)
            b.flat[n] = flat and flat.id or 0
            b.flatEdge[n] = flat and H.inset(fx, fz, flat.x, flat.z) < 0.8 and 1 or 0
            if best then
                local x, y, z = ox + T.DX * bt, oy + T.DY * bt, oz + T.DZ * bt
                local m = best.mat
                local r = m.ramp
                local key, lev = T.shade(r, nx, ny, nz)
                if m.print then
                    best.ux, best.uy, best.uz = ux, uy, uz
                    local k = m.print(best, x, y, z, nx, ny, nz, lev)
                    if type(k) == "table" then
                        r = k
                        key, lev = T.shade(r, nx, ny, nz)
                    elseif k then
                        key, lev = k, 0
                    end
                end
                b.raw[n], b.lev[n], b.shd[n] = key, lev, r[4]
                b.part[n], b.mat[n] = best.part, m.id
                b.dep[n] = BACK - bt
                b.dif[n] = T.diffuse(nx, ny, nz)
                b.nx[n], b.ny[n], b.nz[n] = nx, ny, nz
                b.cell[n] = best.cell
                b.wx[n], b.wy[n], b.wz[n] = x, y, z
                b.up[n] = ny > 0.7 and 1 or 0
                local top = best.prism and ny > 0.99
                b.edge[n] = top and H.inset(x, z, best.cellRef.x, best.cellRef.z) < 0.8 and 1 or 0
                -- What the wind does to it, for src/ui/sea.lua: a tree's crown
                -- and a sheaf sway, by how high above the ground they are, in
                -- sixteenths; grass and dry grass ripple.
                local kind, sway = LAND.other, 0
                if m == MAT.tree or m == MAT.wheat then
                    local cell = best.cellRef
                    local ground = cell.top + ((m == MAT.tree and cell.elev == "hills") and 1 or 0)
                    kind = m == MAT.tree and LAND.crown or LAND.sheaf
                    sway = max(0, min(255, floor((y - ground) * 16)))
                elseif ny > 0.9 and (m.id == MAT.grass.id or m.id == MAT.grass.id + 20) then
                    kind = LAND.grass
                elseif ny > 0.9 and (m.id == MAT.plains.id or m.id == MAT.plains.id + 20) then
                    kind = LAND.plains
                end
                b.kind[n], b.sway[n] = kind, sway
                -- The sea's top, for src/sea.lua to set moving: which water,
                -- and how far the land is, in quarter units up to 63.
                if top and (m == MAT.ocean or m == MAT.coast) then
                    b.sea[n] = m == MAT.ocean and 1 or 2
                    b.shore[n] = min(255, floor(self:shoreDistance(best.cellRef, x, z) * 4 + 0.5))
                else
                    b.sea[n] = 0
                end
            else
                b.raw[n], b.cell[n], b.edge[n], b.up[n], b.sea[n], b.kind[n] = 0, 0, 0, 0, 0, 0
                b.dep[n] = -1e9
                b.wy[n] = -1e9
            end
        end
        if yield and pj % 4 == 0 then yield((pj - j0) / max(1, j1 - j0)) end
    end
end

-- Traces the whole map. `yield`, if given, is told the progress (0..1)
-- every few rows -- coroutine.yield, so the load screen can say how far
-- along it is.
function World:paint(yield)
    local w, h = self.w, self.h
    local b = T.buffer(w, h)
    b.open = true
    b.cell = ffi.new("int16_t[?]", w * h)
    b.flat = ffi.new("int16_t[?]", w * h)
    b.edge = ffi.new("uint8_t[?]", w * h)
    b.flatEdge = ffi.new("uint8_t[?]", w * h)
    b.wx = ffi.new("float[?]", w * h)
    b.wy = ffi.new("float[?]", w * h)
    b.wz = ffi.new("float[?]", w * h)
    b.up = ffi.new("uint8_t[?]", w * h)
    b.sea = ffi.new("uint8_t[?]", w * h)
    b.shore = ffi.new("uint8_t[?]", w * h)
    b.kind = ffi.new("uint8_t[?]", w * h)
    b.sway = ffi.new("uint8_t[?]", w * h)
    self.buf = b
    self:bin()
    self:trace(0, 0, w - 1, h - 1, yield)
    T.finish(b, 1.2)
    self.key, self.dep, self.cell, self.up = b.key, b.dep, b.cell, b.up
    self.wx, self.wy, self.wz = b.wx, b.wy, b.wz
    self.data = love.image.newImageData(w, h, "rgba8")
    self.px = ffi.cast("uint8_t*", self.data:getFFIPointer())
    self.image = love.graphics.newImage(self.data)
    self.image:setFilter("nearest", "nearest")
    -- Beside it, a picture of what moves for src/ui/sea.lua: red what it is
    -- (1 ocean, 2 coast, or a kind of land from LAND; 0 unseen, or ink on
    -- the water), green how far the land is from water or how high a crown
    -- stands, blue how many steps darker the fog and the grid lay it, alpha
    -- the key laid there.
    self.maskData = love.image.newImageData(w, h, "rgba8")
    self.mpx = ffi.cast("uint8_t*", self.maskData:getFFIPointer())
    self.maskImage = love.graphics.newImage(self.maskData)
    self.maskImage:setFilter("nearest", "nearest")
end

-- How far room point (x, z) on water hex `cell` is from the nearest land, as
-- far as two hexes out; further than that is open sea (64).
function World:shoreDistance(cell, x, z)
    self.landNear = self.landNear or {}
    local near = self.landNear[cell.id]
    if not near then
        near = {}
        for dr = -2, 2 do
            for dc = -3, 3 do
                local n = self:cellAt(cell.c + dc, cell.r + dr)
                if n and not D.TERRAIN[n.terrain].water and H.distance(cell.c, cell.r, n.c, n.r) <= 2 then
                    near[#near + 1] = n
                end
            end
        end
        self.landNear[cell.id] = near
    end
    local d = 64
    for k = 1, #near do d = min(d, hexDistance(near[k], x, z)) end
    return max(0, d)
end

-- One hex has changed (a city cleared its forest): build its solids again
-- and trace its corner of the picture again.
function World:refresh(cellId)
    local i0, i1, j0, j1 = math.huge, -math.huge, math.huge, -math.huge
    local function grow(s)
        local a, b, c, d = self:boxOf(s)
        i0, i1, j0, j1 = min(i0, a), max(i1, b), min(j0, c), max(j1, d)
    end
    for _, s in ipairs(self.byCell[cellId] or {}) do
        s.dead = true
        grow(s)
    end
    -- Dead solids stay in the bins (skipped) but leave the list.
    local keep = {}
    for _, s in ipairs(self.solids) do if not s.dead then keep[#keep + 1] = s end end
    self.solids = keep
    self:addCell(self.cells[cellId])
    for _, s in ipairs(self.byCell[cellId]) do grow(s) end
    i0, j0 = max(0, i0 - 1), max(0, j0 - 1)
    i1, j1 = min(self.w - 1, i1 + 1), min(self.h - 1, j1 + 1)
    self:trace(i0, j0, i1, j1)
    T.finish(self.buf, 1.2, i0 - 1, j0 - 1, i1 + 1, j1 + 1)
    self.dirty = true
end

-- The picture as the player knows the map: what they see as it is, what they
-- have seen a step darker, and what they never have as a drawn map on paper.
-- `grid`: a faint line round every hex.
function World:build(explored, visible, grid)
    local w, h = self.w, self.h
    local px, key, cell, edge, flat, flatEdge = self.px, self.key, self.cell, self.buf.edge, self.buf.flat, self.buf.flatEdge
    local mpx, sea, shore, raw = self.mpx, self.buf.sea, self.buf.shore, self.buf.raw
    local kind, sway = self.buf.kind, self.buf.sway
    local RGB8 = World.RGB8
    local DARK = T.DARKER
    local bg = IDX.o
    local PAPER, LINE, SPECK = IDX.c, IDX.t, IDX.s
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local n = j * w + i
            local k = key[n]
            local c = cell[n]
            local what, dark = 0, 0
            if k == 0 then
                k = bg
            elseif not explored[c] then
                local f = flat[n]
                if f == 0 then k = bg
                elseif flatEdge[n] == 1 then k = LINE
                else
                    k = PAPER
                    if grain(i, j, 90) > 0.97 then k = SPECK end
                end
            else
                if grid and edge[n] == 1 and (i + j) % 2 == 0 then k, dark = DARK[k], dark + 1 end
                if not visible[c] then k, dark = DARK[k], dark + 1 end
                -- Water, but not where the ink has drawn the map's edge over it.
                if sea[n] ~= 0 then what = key[n] == raw[n] and sea[n] or 0 else what = kind[n] end
            end
            local rgb = RGB8[k]
            local p = n * 4
            px[p], px[p + 1], px[p + 2], px[p + 3] = rgb[1], rgb[2], rgb[3], 255
            mpx[p], mpx[p + 1], mpx[p + 2], mpx[p + 3] = what, sea[n] ~= 0 and shore[n] or sway[n], dark, k
        end
    end
    self.image:replacePixels(self.data)
    self.maskImage:replacePixels(self.maskData)
    self.dirty = false
end

World.RGB8 = {}
for k, c in ipairs(T.RGB) do World.RGB8[k] = { floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5) } end

--- standing on it ------------------------------------------------------------------

-- Picture pixel of a room point, and its depth.
function World:toImage(x, y, z)
    local i, j, d = T.project(x, y, z)
    return i - self.i0, j - self.j0, d
end

-- The cell under picture pixel (i, j): the hex traced there, or nil.
function World:pick(i, j)
    i, j = floor(i), floor(j)
    if i < 0 or j < 0 or i >= self.w or j >= self.h then return end
    local c = self.cell[j * self.w + i]
    if c == 0 then
        local f = self.buf.flat[j * self.w + i]
        return f ~= 0 and self.cells[f] or nil
    end
    return self.cells[c]
end

-- The picture box of a hex's top: i0, i1, j0, j1.
function World:topBox(cell)
    local i0, i1, j0, j1 = T.screenBox(cell.x - H.APOTHEM, cell.x + H.APOTHEM, cell.top, cell.top, cell.z - H.R, cell.z + H.R)
    return floor(i0 - self.i0) - 1, ceil(i1 - self.i0) + 1, floor(j0 - self.j0) - 1, ceil(j1 - self.j0) + 1
end

return World
