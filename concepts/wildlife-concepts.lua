-- Concept sheet for wildlife: new models built the way src/models.lua builds
-- its deer and sheep, traced with the game's tracer, on single hexes.
package.path = "./?.lua;" .. package.path
local T = require "src.tracer"
local Sh = require "src.shapes"
local M = require "src.models"
local H = require "src.hex"
local Font = require "src.font"
local A = T.Affine
local IDX, ramp = T.IDX, T.ramp
local floor, sin, cos, rad = math.floor, math.sin, math.cos, math.rad

local W, HT, key, dep = 0, 0, {}, {}
local function canvas(w, h) W, HT, key, dep = w, h, {}, {}
    for n = 0, W * HT - 1 do key[n], dep[n] = IDX.c, -math.huge end end
local function put(k, x, y, d)
    if k == 0 or x < 0 or y < 0 or x >= W or y >= HT then return end
    local n = y * W + x
    if d == nil or d >= dep[n] - 0.6 then key[n] = k; if d then dep[n] = d end end
end
local ink = IDX.o
love = { graphics = { rectangle = function(_, x, y) put(ink, floor(x), floor(y)) end } }
local function text(s, x, y, k) ink = k or IDX.o; Font.print(s, x, y) end
local function ctext(s, cx, y, k) text(s, floor(cx - Font.width(s) / 2), y, k) end

-- ground
local GRASS = ramp("c", "k", "t", "n")
local SAND = ramp("w", "c", "s", "t")
local function landPrint(ux, uy, uz, lev, nx, ny)
    if ny < 0.6 then if floor(uy * 12) % 3 == 0 then return IDX.n end return IDX.t end
    if (floor(ux * 37) + floor(uz * 23)) % 13 == 0 then return IDX.t end
end
local function waterPrint(ux, uy, uz, lev, nx, ny)
    if ny < 0.6 then return IDX.u end
    local r = sin(ux * 0.45 + uz * 0.2) + sin(uz * 0.6 - ux * 0.17)
    if math.abs(r - 1.0) < 0.1 then return IDX.t end
    if math.abs(r + 0.6) < 0.08 then return IDX.u end
    return IDX.n
end
local grounds = {}
local function ground(kind)
    if grounds[kind] then return grounds[kind] end
    local Z = ZOOM * 0.8
    local p = Sh.prism(6, 0, -3 * Z, 0, (H.APOTHEM - 0.3) * Z, ((kind == "water" and -2 or 4) + 3) * Z, 0, 0)
    p.id = 1
    if kind == "water" then
        p.ramp = ramp("n", "u", "u", "o")
        p.print = function(ux, uy, uz, l, nx, ny) return waterPrint(ux * H.APOTHEM * 0.5, 0, uz * H.APOTHEM * 0.5, l, nx, ny) end
    elseif kind == "desert" then
        p.ramp = SAND
        p.print = function(ux, uy, uz, l, nx, ny) if ny < 0.6 then return IDX.t end end
    else p.ramp, p.print = GRASS, landPrint end
    grounds[kind] = T.paint({ p }, 1.5)
    return grounds[kind]
end
local function stamp(pic, ox, oy, x, y, z)
    local si, sj, d = T.project(x, y, z)
    local bi, bj = floor(ox + si) - pic.oi, floor(oy + sj) - pic.oj
    for pj = 0, pic.h - 1 do for pi = 0, pic.w - 1 do
        local n = pj * pic.w + pi
        local k = pic.key[n]
        if k ~= 0 then put(k, bi + pi, bj + pj, d + pic.dep[n]) end
    end end
end
local function write(path)
    local out = assert(io.open(path, "wb"))
    out:write(("P6\n%d %d\n255\n"):format(W, HT))
    local buf = {}
    for n = 0, W * HT - 1 do
        local c = T.RGB[key[n]]
        buf[#buf + 1] = string.char(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
    end
    out:write(table.concat(buf)); out:close()
end

-- modelling
ZOOM = 2.6
local function part(s, r, id, pr) s.ramp, s.id, s.print = r, id, pr; return s end
local function paint(parts, face, scale)
    local m = A.mul(A.scale(scale, scale, scale), A.rotY(-rad(60 * face)))
    for _, q in ipairs(parts) do q.at = A.mul(m, q.at or A.id()) end
    return T.paint(parts, 1.5)
end
local R = {
    skin = ramp("w", "c", "s", "t"), wood = ramp("s", "t", "n", "u"), dark = ramp("k", "n", "u", "o"),
    grey = ramp("c", "s", "k", "n"), stone = ramp("c", "s", "t", "k"), bone = ramp("w", "w", "c", "s"),
    horse = ramp("c", "t", "k", "n"), black = ramp("n", "u", "o", "o"), green = ramp("t", "k", "n", "u"),
}

local Mob = {}

-- WOLF: grey, long legs, pointed ears, a brush. pose 0 stand, 1 howl, 2 lunge.
function Mob.wolf(pose)
    local p, coat = {}, R.grey
    local lunge = pose == 2 and 1 or 0
    local bodyY = 5.6 - lunge * 0.8
    p[#p+1] = part(Sh.ell(0, bodyY, 0, 4.2, 1.9, 1.6, A.rotZ(lunge * -0.12)), coat, 1, function(ux, uy)
        if uy > 0.55 then return IDX.n end end) -- dark saddle
    p[#p+1] = part(Sh.ell(2.6, bodyY + 0.6, 0, 2.2, 2.3, 1.9), coat, 2) -- ruff
    local hx, hy = 5.2, 8.0
    if pose == 1 then hx, hy = 4.4, 10.4 elseif pose == 2 then hx, hy = 6.4, 5.6 end
    p[#p+1] = part(Sh.ell(hx, hy, 0, 1.7, 1.3, 1.2, A.rotZ(pose == 1 and 0.9 or 0)), coat, 3)
    local sx, sy = pose == 1 and 0.6 or 1.0, pose == 1 and 1.3 or -0.2
    p[#p+1] = part(Sh.seg(hx + 0.8, hy, 0, hx + 1.4 + sx * 1.6, hy + sy * 1.4 - 0.4, 0, 0.6), coat, 4) -- muzzle
    for _, z in ipairs({ -0.7, 0.7 }) do
        p[#p+1] = part(Sh.seg(hx - 0.6, hy + 0.8, z, hx - 0.9 - (pose == 1 and 0.6 or 0), hy + 2.4, z * 1.1, 0.4, 0.3), R.dark, 5)
    end
    local st = pose == 2 and 1.6 or 0
    for _, l in ipairs({ { 2.6, 0.9, 1 }, { 2.6, -0.9, 1 }, { -2.8, 0.9, -1 }, { -2.8, -0.9, -1 } }) do
        p[#p+1] = part(Sh.seg(l[1], bodyY - 1, l[2], l[1] + st * l[3], 0.3, l[2], 0.55), coat, 6)
    end
    local ty = pose == 2 and 7.2 or 4.2
    p[#p+1] = part(Sh.seg(-3.8, bodyY + 0.4, 0, -7.0, ty, 0, 1.0, 0.9), coat, 7, function(ux)
        if ux > 0.6 then return IDX.n end end)
    return p
end

-- BOAR: bristled hump, short legs, white tusks.
function Mob.boar(pose)
    local p, hide = {}, R.dark
    local charge = pose == 2 and 1 or 0
    p[#p+1] = part(Sh.ell(0, 4.6, 0, 4.4, 2.8, 2.4), hide, 1, function(ux, uy, uz)
        if (floor(ux * 14) + floor(uz * 9)) % 5 == 0 and uy > 0 then return IDX.u end end)
    p[#p+1] = part(Sh.seg(1.2, 7.0, 0, -2.6, 6.4, 0, 0.7), R.black, 2) -- bristle ridge
    local hy = pose == 1 and 2.4 or 5.0 - charge
    p[#p+1] = part(Sh.ell(4.4, hy, 0, 2.6, 2.0, 1.9, A.rotZ(-0.35)), hide, 3)
    p[#p+1] = part(Sh.ell(6.6, hy - 1.0, 0, 0.9, 1.0, 1.0), R.wood, 4) -- snout
    for _, z in ipairs({ -0.9, 0.9 }) do
        p[#p+1] = part(Sh.seg(6.0, hy - 1.2, z, 6.6, hy + 0.4, z * 1.5, 0.3, 0.2), R.bone, 5)
        p[#p+1] = part(Sh.ell(3.6, hy + 2.0, z * 1.2, 0.5, 1.0, 0.6), hide, 6)
    end
    local st = charge * 1.4
    for _, l in ipairs({ { 2.4, 1.3, 1 }, { 2.4, -1.3, -1 }, { -2.6, 1.3, -1 }, { -2.6, -1.3, 1 } }) do
        p[#p+1] = part(Sh.seg(l[1], 3.0, l[2], l[1] + st * l[3], 0.3, l[2], 0.6), R.black, 7)
    end
    p[#p+1] = part(Sh.seg(-4.2, 5.4, 0, -5.2, 4.0, 0, 0.3), R.black, 8)
    return p
end

-- BEAR: huge, round, dark. pose 0 on all fours, 3 reared up.
function Mob.bear(pose)
    local p, fur = {}, ramp("t", "n", "u", "o")
    if pose == 3 then
        p[#p+1] = part(Sh.ell(-0.4, 8.4, 0, 3.0, 5.4, 3.0, A.rotZ(0.25)), fur, 1)
        p[#p+1] = part(Sh.ell(0.6, 14.0, 0, 2.2, 2.0, 2.0), fur, 2)
        p[#p+1] = part(Sh.ell(2.6, 13.6, 0, 1.0, 0.9, 0.9), R.wood, 3)
        for _, z in ipairs({ -1.4, 1.4 }) do
            p[#p+1] = part(Sh.ell(0.0, 15.8, z, 0.7, 0.7, 0.5), fur, 4)
            p[#p+1] = part(Sh.seg(0.8, 11.4, z * 1.9, 3.6, 13.4, z * 2.3, 1.0, 0.9), fur, 5)
            p[#p+1] = part(Sh.seg(-0.6, 4.0, z, 0.0, 0.4, z * 1.1, 1.2), fur, 6)
            for c = -1, 1 do p[#p+1] = part(Sh.seg(3.8, 13.8 + c * 0.4, z * 2.3, 4.6, 14.6 + c * 0.5, z * 2.3, 0.15), R.bone, 7) end
        end
    else
        p[#p+1] = part(Sh.ell(0, 6.6, 0, 6.0, 3.8, 3.2), fur, 1)
        p[#p+1] = part(Sh.ell(-1.4, 9.0, 0, 3.2, 2.0, 2.6), fur, 2) -- the hump
        p[#p+1] = part(Sh.ell(6.4, 7.2, 0, 2.3, 2.1, 2.1), fur, 3)
        p[#p+1] = part(Sh.ell(8.4, 6.6, 0, 1.1, 0.9, 0.9), R.wood, 4)
        for _, z in ipairs({ -1.4, 1.4 }) do
            p[#p+1] = part(Sh.ell(5.6, 9.2, z, 0.7, 0.7, 0.5), fur, 5)
            p[#p+1] = part(Sh.seg(3.6, 5.0, z * 1.6, 3.8, 0.5, z * 1.6, 1.3), fur, 6)
            p[#p+1] = part(Sh.seg(-3.8, 5.0, z * 1.6, -4.0, 0.5, z * 1.6, 1.4), fur, 6)
        end
    end
    return p
end

-- AUROCHS: big dark ox, pale stripe down the back, long forward horns.
function Mob.aurochs(pose)
    local p = {}
    p[#p+1] = part(Sh.ell(0, 6.4, 0, 5.4, 3.0, 2.6), R.black, 1, function(ux, uy, uz)
        if uy > 0.7 and math.abs(uz) < 0.2 then return IDX.t end end)
    p[#p+1] = part(Sh.ell(3.2, 7.6, 0, 2.6, 2.8, 2.4), R.black, 2)
    local hy = pose == 1 and 2.6 or 6.6
    p[#p+1] = part(Sh.ell(6.6, hy, 0, 2.0, 1.6, 1.4, A.rotZ(-0.5)), R.black, 3)
    p[#p+1] = part(Sh.ell(7.8, hy - 1.0, 0, 0.9, 0.8, 0.9), R.dark, 4, function() return IDX.t end) -- pale muzzle
    for _, z in ipairs({ -1, 1 }) do
        p[#p+1] = part(Sh.seg(6.2, hy + 1.2, z * 1.0, 6.2, hy + 2.4, z * 3.2, 0.45, 0.35), R.bone, 5)
        p[#p+1] = part(Sh.seg(6.2, hy + 2.4, z * 3.2, 7.8, hy + 3.6, z * 2.8, 0.35, 0.2), R.bone, 5)
        p[#p+1] = part(Sh.seg(3.6, 4.4, z * 1.4, 3.6, 0.4, z * 1.4, 0.75), R.black, 6, function(ux) if ux > 0.6 then return IDX.c end end)
        p[#p+1] = part(Sh.seg(-3.6, 4.4, z * 1.4, -3.6, 0.4, z * 1.4, 0.75), R.black, 6, function(ux) if ux > 0.6 then return IDX.c end end)
    end
    p[#p+1] = part(Sh.seg(-5.2, 7.2, 0, -6.0, 3.0, 0, 0.3), R.black, 7)
    return p
end

-- WILD HORSE: dun with a dark mane and legs, standing or rearing.
function Mob.horse(pose)
    local p = {}
    local up = pose == 3
    local rot = up and A.rotZ(0.6) or A.id()
    local q = {}
    q[#q+1] = part(Sh.ell(0, 5.6, 0, 4.2, 2.1, 1.8), R.horse, 1)
    q[#q+1] = part(Sh.seg(3.0, 6.4, 0, 4.8, 9.4, 0, 1.2), R.horse, 1)
    q[#q+1] = part(Sh.seg(2.6, 7.6, 0, 4.4, 10.4, 0, 0.5), R.black, 2) -- mane
    q[#q+1] = part(Sh.ell(5.8, 9.1, 0, 1.9, 0.95, 0.95), R.horse, 3, function(ux) if ux > 0.5 then return IDX.n end end)
    q[#q+1] = part(Sh.seg(-3.8, 6.4, 0, -5.4, 2.6, 0, 0.7), R.black, 4)
    for _, lz in ipairs({ -1.0, 1.0 }) do
        if up then
            q[#q+1] = part(Sh.seg(2.8, 4.6, lz, 4.6, 3.8 + lz, lz, 0.55), R.horse, 5, function(ux) if ux > 0.3 then return IDX.u end end)
        else
            q[#q+1] = part(Sh.seg(2.8, 4.6, lz, 2.8, 0.3, lz, 0.55), R.horse, 5, function(ux) if ux > 0.3 then return IDX.u end end)
        end
    end
    for _, q1 in ipairs(q) do q1.at = A.mul(A.mul(A.move(-2.6, 0.4, 0), rot), A.mul(A.move(2.6, 0, 0), q1.at)) p[#p+1] = q1 end
    for _, lz in ipairs({ -1.0, 1.0 }) do
        p[#p+1] = part(Sh.seg(-2.8, 4.6 + (up and 1 or 0), lz, up and -1.8 or -2.8, 0.3, lz, 0.6), R.horse, 6, function(ux) if ux > 0.3 then return IDX.u end end)
    end
    return p
end

-- CROCODILE: low, long, scutes along its back; jaws open when it strikes.
function Mob.croc(pose)
    local p, hide = {}, R.green
    local scutes = function(ux, uy, uz) if uy > 0.5 and floor(ux * 6) % 2 == 0 then return IDX.u end end
    p[#p+1] = part(Sh.ell(0, 0.8, 0, 5.0, 1.3, 2.2), hide, 1, scutes)
    p[#p+1] = part(Sh.seg(-4.0, 0.8, 0, -10.0, 0.4, 1.6, 1.4, 0.4), hide, 2, scutes)
    local open = pose == 2 and 0.45 or 0
    p[#p+1] = part(Sh.seg(4.2, 1.0, 0, 9.6, 1.0 + open * 3, 0, 1.0, 0.5), hide, 3)
    p[#p+1] = part(Sh.seg(4.2, 0.6, 0, 9.4, 0.4 - open * 1.2, 0, 0.9, 0.45), hide, 4)
    if open > 0 then
        for k = 0, 4 do p[#p+1] = part(Sh.ell(5.4 + k, 0.9 + open * (k + 1) * 0.5, 0, 0.18, 0.35, 0.6), R.bone, 6) end
    end
    for _, z in ipairs({ -0.7, 0.7 }) do p[#p+1] = part(Sh.ell(4.6, 2.0, z, 0.5, 0.5, 0.5), R.straw or R.bone, 5) end
    for _, l in ipairs({ { 2.6, 1 }, { 2.6, -1 }, { -2.6, 1 }, { -2.6, -1 } }) do
        p[#p+1] = part(Sh.seg(l[1], 0.6, l[2] * 1.8, l[1] + 0.8, -0.2, l[2] * 3.2, 0.5), hide, 7)
    end
    return p
end

-- SEA SERPENT: coils breaking the water, a finned head rearing.
function Mob.serpent(pose)
    local p, sc = {}, ramp("k", "n", "u", "o")
    local belly = function(ux, uy, uz, l, nx, ny) if ny < -0.2 then return IDX.s end
        if (floor(ux * 8) + floor(uz * 8)) % 3 == 0 then return IDX.u end end
    for k, c in ipairs({ { -9, 0 }, { -3.5, 1.5 } }) do
        p[#p+1] = part(Sh.seg(c[1] - 2.2, -1, c[2], c[1], 3.4, c[2], 1.3), sc, k, belly)
        p[#p+1] = part(Sh.seg(c[1], 3.4, c[2], c[1] + 2.2, -1, c[2], 1.3), sc, k, belly)
        p[#p+1] = part(Sh.peak({ { c[1] - 1.2, c[2] - 0.3 }, { c[1] + 1.2, c[2] - 0.3 }, { c[1], c[2] + 0.3 } }, 4.2, { c[1] - 0.4, 6.0, c[2] }), R.dark, 10 + k)
    end
    local rise = pose == 2 and 13 or 10
    p[#p+1] = part(Sh.seg(2.2, -1, 2.4, 3.4, rise - 2, 2.0, 1.5, 1.1), sc, 5, belly)
    p[#p+1] = part(Sh.seg(3.4, rise - 2, 2.0, 5.2, rise, 1.6, 1.1), sc, 5, belly)
    p[#p+1] = part(Sh.ell(6.6, rise + 0.2, 1.6, 2.2, 1.2, 1.2, A.rotZ(pose == 2 and 0.35 or -0.15)), sc, 6)
    if pose == 2 then
        p[#p+1] = part(Sh.ell(7.0, rise - 1.4, 1.6, 1.8, 0.5, 1.0, A.rotZ(-0.4)), sc, 7)
        for k = 0, 2 do p[#p+1] = part(Sh.seg(6.2 + k * 0.8, rise - 0.7, 1.6, 6.3 + k * 0.8, rise - 1.4, 1.6, 0.18), R.bone, 9) end
    end
    for _, z in ipairs({ 0.6, 2.6 }) do
        p[#p+1] = part(Sh.seg(5.6, rise + 1.0, z, 4.0, rise + 2.8, z + (z - 1.6) * 0.8, 0.5, 0.15), R.dark, 8) -- frills
    end
    -- foam rings where it breaks the sea
    for _, c in ipairs({ { -9, 0 }, { -3.5, 1.5 }, { 2.6, 2.4 } }) do
        for a = 0, 5 do
            local t = a * math.pi / 3
            p[#p+1] = part(Sh.ell(c[1] + cos(t) * 2.2, 0.1, c[2] + sin(t) * 1.6, 0.7, 0.25, 0.5), R.bone, 20)
        end
    end
    return p
end

-- MOUNTAIN GOAT: pale, shaggy beard, swept-back horns.
function Mob.goat(pose)
    local p, wool = {}, R.skin
    p[#p+1] = part(Sh.ell(0, 4.8, 0, 3.2, 2.0, 1.6), wool, 1)
    local hx, hy = 3.8, pose == 1 and 2.6 or 7.4
    p[#p+1] = part(Sh.seg(2.0, 5.4, 0, hx - 0.4, hy - 0.4, 0, 0.9), wool, 2)
    p[#p+1] = part(Sh.ell(hx + 0.4, hy, 0, 1.3, 0.9, 0.85, A.rotZ(-0.4)), wool, 3)
    p[#p+1] = part(Sh.seg(hx + 0.6, hy - 0.8, 0, hx + 0.4, hy - 2.0, 0, 0.35), R.stone, 4) -- beard
    for _, z in ipairs({ -0.5, 0.5 }) do
        p[#p+1] = part(Sh.seg(hx, hy + 0.6, z, hx - 1.6, hy + 2.2, z * 1.4, 0.35, 0.2), R.dark, 5)
        p[#p+1] = part(Sh.seg(2.0, 3.6, z * 1.4, 2.0 + (pose == 2 and 0.8 or 0), 0.3, z * 1.4, 0.45), R.dark, 6)
        p[#p+1] = part(Sh.seg(-2.0, 3.6, z * 1.4, -2.0 - (pose == 2 and 0.8 or 0), 0.3, z * 1.4, 0.45), R.dark, 6)
    end
    p[#p+1] = part(Sh.ell(-3.2, 5.8, 0, 0.6, 0.8, 0.5), wool, 7)
    return p
end

-- FOX: decoration. Rusty-pale, white tail tip; curled asleep or trotting.
function Mob.fox(pose)
    local p, coat = {}, ramp("s", "t", "k", "n")
    if pose == 1 then
        p[#p+1] = part(Sh.ell(0, 1.6, 0, 3.0, 1.6, 2.4), coat, 1)
        p[#p+1] = part(Sh.ell(2.0, 2.0, 1.4, 1.3, 1.1, 1.1), coat, 2)
        p[#p+1] = part(Sh.seg(-2.4, 1.0, -1.2, 2.4, 1.0, 2.8, 1.0, 0.6), coat, 3, function(ux) if ux > 0.6 then return IDX.w end end)
        return p
    end
    p[#p+1] = part(Sh.ell(0, 3.6, 0, 2.8, 1.2, 1.1), coat, 1)
    p[#p+1] = part(Sh.ell(3.0, 4.6, 0, 1.2, 1.0, 0.9), coat, 2)
    p[#p+1] = part(Sh.seg(3.8, 4.4, 0, 5.4, 4.0, 0, 0.45, 0.2), coat, 3)
    for _, z in ipairs({ -0.5, 0.5 }) do p[#p+1] = part(Sh.seg(2.6, 5.2, z, 2.4, 6.6, z, 0.35, 0.15), R.dark, 4) end
    for _, l in ipairs({ { 1.8, 0.6 }, { 1.8, -0.6 }, { -1.8, 0.6 }, { -1.8, -0.6 } }) do
        p[#p+1] = part(Sh.seg(l[1], 3.0, l[2], l[1], 0.3, l[2], 0.32), R.dark, 5)
    end
    p[#p+1] = part(Sh.seg(-2.4, 3.8, 0, -6.0, 3.4, 0, 1.0, 0.6), coat, 6, function(ux) if ux > 0.6 then return IDX.w end end)
    return p
end

-- LAIRS: wolf den (boulders, a dark mouth, bones), bear cave in a hill.
function Mob.den()
    local p = {}
    p[#p+1] = part(Sh.ell(0, 0.6, -0.6, 3.2, 3.0, 1.2), R.black, 1) -- the mouth, going down
    for k, b in ipairs({ { -4.6, 0, 3.4, 3.0 }, { 4.4, -0.4, 3.0, 2.6 }, { 0, -3.6, 4.2, 3.4 }, { -6.4, 3.4, 1.8, 1.4 },
        { 6.2, 3.0, 2.0, 1.6 }, { -2.6, -5.8, 2.4, 2.0 } }) do
        p[#p+1] = part(Sh.ell(b[1], b[4] * 0.55, b[2], b[3], b[4], b[3] * 0.9), R.stone, 2 + k, function(ux, uy, uz)
            if (floor(ux * 5 + uz * 3) % 4 == 0) and uy > 0.3 then return IDX.t end end)
    end
    p[#p+1] = part(Sh.seg(2.4, 0.3, 4.2, 4.8, 0.3, 5.4, 0.28), R.bone, 20)
    p[#p+1] = part(Sh.seg(-1.6, 0.3, 5.6, 0.8, 0.3, 4.6, 0.28), R.bone, 21)
    p[#p+1] = part(Sh.ell(-3.4, 0.6, 5.0, 0.8, 0.6, 0.7), R.bone, 22)
    return p
end

function Mob.hive()
    local p = {}
    p[#p+1] = part(Sh.prism(7, 0, 0, 0, 3.4, 4.0, 0, 0), R.wood, 1, function(ux, uy, uz, l, nx, ny)
        if ny > 0.6 then if floor(math.sqrt(ux * ux + uz * uz) * 6) % 2 == 0 then return IDX.t end return IDX.s end
        if floor((math.atan2(uz, ux) + 4) * 4) % 3 == 0 then return IDX.n end end)
    p[#p+1] = part(Sh.ell(0, 4.2, 0, 2.6, 4.2, 2.6), ramp("w", "c", "t", "k"), 2, function(ux, uy)
        if floor((uy + 1) * 6) % 2 == 0 then return IDX.t end end)
    p[#p+1] = part(Sh.ell(1.6, 4.8, 1.8, 0.7, 0.9, 0.5), R.black, 3) -- the door
    for k = 1, 9 do
        local a = k * 2.4
        p[#p+1] = part(Sh.ell(cos(a) * (3 + k % 3), 6 + (k * 1.7) % 5, sin(a) * (3 + k % 2), 0.35, 0.3, 0.3), R.black, 10 + k)
    end
    return p
end
R.straw = ramp("w", "c", "t", "k")

--- the sheet -------------------------------------------------------------------
local CW, CH = 128, 160
local rows = {
    { "HOSTILE - ATTACK UNITS THAT COME NEAR", {
        { "WOLF", "wolf", 0, 0, "grass", 0.5, "PACKS. 2X AT NIGHT", "PELT +15 GOLD" },
        { "WOLF HOWLING", "wolf", 1, 1, "grass", 0.5, "CALLS THE PACK", "" },
        { "WOLF LUNGING", "wolf", 2, 0, "grass", 0.5, "STR 15", "" },
        { "BEAR", "bear", 0, 0, "grass", 0.5, "STR 30. SLOW", "FUR +25 GOLD" },
        { "BEAR REARING", "bear", 3, 0, "grass", 0.5, "GUARDS ITS CAVE", "" },
    } },
    { "AMBUSHERS - HIDE IN WATER UNTIL STRUCK", {
        { "CROCODILE", "croc", 0, 0, "water", 0.5, "ON RIVER EDGES", "HIDE +20 GOLD" },
        { "CROC STRIKE", "croc", 2, 0, "water", 0.5, "HITS RIVER CROSSERS", "" },
        { "SEA SERPENT", "serpent", 0, 1, "water", 0.5, "DEEP OCEAN", "AMBERGRIS +60" },
        { "SERPENT ATTACK", "serpent", 2, 0, "water", 0.5, "STR 40. SINKS BOATS", "" },
    } },
    { "NEUTRAL - FIGHT BACK IF HUNTED", {
        { "WILD BOAR", "boar", 0, 0, "grass", 0.5, "FOREST EDGES", "MEAT +10 FOOD" },
        { "BOAR CHARGE", "boar", 2, 1, "grass", 0.5, "STR 18 WHEN HIT", "" },
        { "AUROCHS", "aurochs", 0, 0, "grass", 0.48, "HERDS ON GRASS", "+25 FOOD, HORNS" },
        { "AUROCHS GRAZING", "aurochs", 1, 3, "grass", 0.48, "STR 28 IF HUNTED", "" },
    } },
    { "PEACEFUL - TAME, HUNT, OR JUST SCENERY", {
        { "WILD HORSES", "horse", 0, 0, "grass", 0.5, "PLAINS", "TAME: FREE HORSE" },
        { "MUSTANG REARING", "horse", 3, 0, "grass", 0.5, "HORSEBACK RIDING", "" },
        { "MOUNTAIN GOAT", "goat", 0, 0, "grass", 0.45, "HILLS BY PEAKS", "DECOR" },
        { "FOX", "fox", 0, 5, "grass", 0.45, "TROTS AT DUSK", "DECOR" },
        { "FOX ASLEEP", "fox", 1, 1, "grass", 0.45, "CURLED BY DAY", "DECOR" },
    } },
    { "LAIRS - CLEAR THEM FOR A PRIZE", {
        { "WOLF DEN", "den", 0, 1, "grass", 0.55, "SPAWNS A PACK", "CLEAR: 40 GOLD" },
        { "WILD BEES", "hive", 0, 0, "grass", 0.55, "BEES STING", "HONEY +1 AMENITY" },
    } },
}
local maxc = 0
for _, r in ipairs(rows) do maxc = math.max(maxc, #r[2]) end
canvas(CW * maxc, CH * #rows + 10)
for ri, row in ipairs(rows) do
    local y0 = (ri - 1) * CH + 6
    text(row[1], 4, y0, IDX.o)
    for ci, it in ipairs(row[2]) do
        local px, py = (ci - 0.5) * CW, y0 + 78
        stamp(ground(it[5]), px, py, 0, 0, 0)
        local pic = paint(Mob[it[2]](it[3]), it[4], it[6] * M.UNIT_SCALE * ZOOM * 1.55)
        stamp(pic, px, py, 0, (it[5] == "water" and -2 or 4) * ZOOM * 0.8, 0)
        ctext(it[1], px, y0 + 132, IDX.o)
        ctext(it[7], px, y0 + 140, IDX.n)
        if it[8] ~= "" then ctext(it[8], px, y0 + 148, IDX.u) end
    end
end
write(arg[1] or "/tmp/mobs/sheet.ppm")
