-- A sheet of the models of the sea, drawn the way the board draws them:
-- each picture laid down by depth over a little stretch of hexes traced
-- with the same tracer, in the eight colours and nothing else.
--
--   luajit tools/designs.lua [dir]
--
-- writes one picture a group (dir/galley.ppm, ...), at one pixel to the
-- pixel, as the board would show it at its smallest; scale them up by a
-- whole number to look at them.

package.path = "./?.lua;" .. package.path

local T = require "src.tracer"
local Sh = require "src.shapes"
local M = require "src.models"
local H = require "src.hex"
local Font = require "src.font"

local floor, sin = math.floor, math.sin
local IDX = T.IDX

--- a canvas of palette keys ------------------------------------------------------

local W, HT = 0, 0
local key, dep = {}, {}
local function canvas(w, h)
    W, HT = w, h
    key, dep = {}, {}
    for n = 0, W * HT - 1 do key[n], dep[n] = IDX.c, -math.huge end
end

local function put(k, x, y, d)
    if k == 0 or x < 0 or y < 0 or x >= W or y >= HT then return end
    local n = y * W + x
    if d == nil or d >= dep[n] - 0.6 then
        key[n] = k
        if d then dep[n] = d end
    end
end

-- Font.print plots through love.graphics: this one plots into the canvas.
local ink = IDX.o
love = { graphics = { rectangle = function(_, x, y) put(ink, floor(x), floor(y)) end } }
-- Captions wait until everything is laid down, then go on a strip of paper.
local captions = {}
local function label(text, x, y)
    captions[#captions + 1] = { text, x, y }
end
local function captionsDown()
    for _, c in ipairs(captions) do
        local w = Font.width(c[1])
        local x0 = floor(c[2] - w / 2)
        for j = c[3] - 1, c[3] + 5 do
            for i = x0 - 2, x0 + w + 1 do put(IDX.c, i, j) end
        end
        ink = IDX.o
        Font.print(c[1], x0, c[3])
    end
    captions = {}
end

-- Forget what is in front of what in a box, so the next scene there is laid
-- over the last rather than behind it.
local function reset(x, y, w, h)
    for j = y, y + h do
        for i = x, x + w do
            if i >= 0 and j >= 0 and i < W and j < HT then dep[j * W + i] = -math.huge end
        end
    end
end

--- a stretch of hexes ----------------------------------------------------------------

local GRASS = T.ramp("c", "k", "t", "n")
local function waterPrint(ux, uy, uz, lev, nx, ny)
    if ny < 0.6 then return IDX.u end
    local r = sin(ux * 0.45 + uz * 0.2) + sin(uz * 0.6 - ux * 0.17)
    if math.abs(r - 1.0) < 0.1 then return IDX.t end
    if math.abs(r + 0.6) < 0.08 then return IDX.u end
    return IDX.n
end
local function landPrint(ux, uy, uz, lev, nx, ny)
    if ny < 0.6 then
        if floor(uy * 12) % 3 == 0 then return IDX.n end
        return IDX.t
    end
    if (floor(ux * 37) + floor(uz * 23)) % 13 == 0 then return IDX.t end
end

-- Hexes as { dc, dr, "water" | "land", top }: traced into one picture with
-- its pivot at the middle of hex (0, 0). Water prints in room units.
local function ground(hexes)
    local parts = {}
    local cx, cz = H.center(0, 0)
    for k, h in ipairs(hexes) do
        local x, z = H.center(h[1], h[2])
        x, z = x - cx, z - cz
        local top = h[4] or (h[3] == "land" and 4 or -2)
        local p = Sh.prism(6, x, -10, z, H.APOTHEM - 0.3, top + 10, 0, 0)
        p.id = k
        if h[3] == "land" then
            p.ramp, p.print = GRASS, landPrint
        else
            p.ramp = T.ramp("n", "u", "u", "o")
            local hx, hz = x, z
            p.print = function(ux, uy, uz, lev, nx, ny)
                return waterPrint(hx + ux * H.APOTHEM, 0, hz + uz * H.APOTHEM, lev, nx, ny)
            end
        end
        parts[#parts + 1] = p
    end
    return T.paint(parts, 1.5)
end

-- Lays picture `pic` with its pivot at room point (x, y, z), the room's
-- origin being canvas pixel (ox, oy).
local function stamp(pic, ox, oy, x, y, z)
    local si, sj, d = T.project(x, y, z)
    local bi, bj = floor(ox + si) - pic.oi, floor(oy + sj) - pic.oj
    for pj = 0, pic.h - 1 do
        for pi = 0, pic.w - 1 do
            local n = pj * pic.w + pi
            local k = pic.key[n]
            if k ~= 0 then put(k, bi + pi, bj + pj, d + pic.dep[n]) end
        end
    end
end

local function write(name)
    captionsDown()
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

local ONE = { { 0, 0, "water" } }
local THREE = { { 0, 0, "water" }, { 1, 0, "water" }, { -1, 0, "water" } }

--- the scenes ------------------------------------------------------------------------

-- A row of single sea hexes, each with something on it, captioned.
local function title(text)
    ink = IDX.o
    Font.print(text, 4, 3)
end

local function row(name, head, items, picOf, ground_)
    local cw = 64
    canvas(cw * #items, 96)
    local sea = ground(ground_ or ONE)
    for k, it in ipairs(items) do
        local px, py = (k - 0.5) * cw, 56
        reset(floor(px - cw / 2), 0, cw, 96)
        stamp(sea, px, py, 0, 0, 0)
        stamp(picOf(it, k), px, py, 0, -2, 0)
        label(it.label, px, 88)
    end
    title(head)
    write(name)
end

row("galley", "GALLEY - MELEE SHIP, SAILING", {
    { label = "AURELIA", look = "light", face = 1 }, { label = "UMBRA", look = "dark", face = 0 },
    { label = "VARRO", look = "stripe", face = 2 }, { label = "STROKE", look = "light", face = 3, pose = 1 },
    { label = "RAM", look = "dark", face = 1, pose = 3 }, { label = "HEELED", look = "stripe", face = 0, roll = 1 },
}, function(it) return M.unit("galley", it.look, it.face, it.pose or 0, it.roll or 0) end)

row("quadrireme", "QUADRIREME - RANGED SHIP, SHIPBUILDING", {
    { label = "AURELIA", look = "light", face = 1 }, { label = "UMBRA", look = "dark", face = 0 },
    { label = "VARRO", look = "stripe", face = 2 }, { label = "LOOSING", look = "light", face = 0, pose = 3 },
    { label = "STROKE", look = "dark", face = 3, pose = 2 },
}, function(it) return M.unit("quadrireme", it.look, it.face, it.pose or 0, it.roll or 0) end)

row("embarked", "EMBARKED - LAND UNITS ROWED OVER THE WATER", {
    { label = "WARRIOR", kind = "warrior", look = "light", face = 1 },
    { label = "ARCHER", kind = "archer", look = "dark", face = 0 },
    { label = "SETTLER", kind = "settler", look = "stripe", face = 1 },
    { label = "BUILDER", kind = "builder", look = "light", face = 0 },
    { label = "HORSEMAN", kind = "horseman", look = "dark", face = 1 },
    { label = "SPEARMAN", kind = "spearman", look = "stripe", face = 3, pose = 1 },
}, function(it) return M.unit(it.kind, it.look, it.face, it.pose or 0, 0, true) end)

row("fishing", "FISHING BOATS - ON FISH, SAILING", {
    { label = "AURELIA", look = "light" }, { label = "UMBRA", look = "dark" }, { label = "VARRO", look = "stripe", roll = 1 },
}, function(it) return M.fishingBoats(it.look, it.roll or 0) end)

-- Cities on the water: the city on a hex of land with land behind it and
-- the sea in front, which is the way (shore 1, south-east) it builds out.
do
    local sets = {
        { "PIER", {}, "light", 2 },
        { "HARBOUR", { harbour = true }, "dark", 4 },
        { "LIGHTHOUSE", { lighthouse = true }, "stripe", 3 },
        { "BOTH, WITH WALLS", { harbour = true, lighthouse = true, walls = true, granary = true }, "light", 6 },
    }
    local cw = 112
    canvas(cw * #sets, 124)
    local hexes = { { 0, 0, "land" }, { -1, 0, "land" }, { 1, 0, "land" }, { 0, -1, "land" }, { -1, -1, "land" },
        { 0, 1, "water" }, { -1, 1, "water" }, { 1, 1, "water" } }
    local sea = ground(hexes)
    for k, s in ipairs(sets) do
        local px, py = (k - 0.5) * cw, 60
        reset(floor(px - cw / 2), 0, cw, 124)
        stamp(sea, px, py, 0, 0, 0)
        stamp(M.city(s[3], s[4], k == 4, s[2], 1, 6), px, py, 0, 4, 0)
        if k == 2 then
            -- A galley in, beside the quay.
            local x, z = H.center(0, 1)
            local cx, cz = H.center(0, 0)
            stamp(M.unit("galley", "dark", 0, 0, 0), px, py, x - cx, -2, z - cz)
        end
        label(s[1], px, 116)
    end
    title("CITIES ON THE WATER")
    write("cities")
end

-- A fish's leap, frame by frame, over one hex.
do
    canvas(130, 84)
    local sea = ground(THREE)
    stamp(sea, 65, 44, 0, 0, 0)
    for k = 0, 6 do
        local f = k / 6
        stamp(M.fish(f < 0.4 and -1 or (f > 0.6 and 1 or 0), 1), 65, 44, -16 + f * 32, -2 + sin(f * math.pi) * 9, 0)
    end
    label("A LEAP, FRAME BY FRAME", 65, 76)
    title("FISH")
    write("fish")
end
