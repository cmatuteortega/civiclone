-- The overlay: everything that changes on the board, laid a pixel at a time
-- over the board's picture into one byte-for-byte image, each pixel kept only
-- where it is nearer than the board there. Underroot's src/ui/pixels.lua,
-- for a camera that pans rather than turns.

local T = require "src.tracer"
local S = require "src.ui.state"
local World = require "src.world"

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local P = {}
local RGB8 = World.RGB8

-- The alpha a pixel is put with that is a window or a door, lit at night
-- (src/ui/sea.lua's cover), and one that is the rest of a building with
-- windows, which takes the night as the ground does. Neither is blended:
-- the cover draws every pixel of the overlay whole.
P.LAMP, P.WALL = 250, 252

-- Put key k at canvas pixel (x, y); `a` the alpha, if not the plain 255.
local function putS(k, x, y, a)
    if k == 0 or x < 0 or y < 0 or x >= S.cw or y >= S.ch then return end
    local p = (y * S.cw + x) * 4
    local c = RGB8[k]
    S.opx[p], S.opx[p + 1], S.opx[p + 2], S.opx[p + 3] = c[1], c[2], c[3], a or 255
end
P.putS = putS

-- Mark canvas pixel (x, y), on the sea, to show `steps` lighter. The sea is
-- painted again every frame (src/ui/sea.lua), so a mark over it can't be a
-- colour: it is left in the alpha, which the overlay is never drawn with.
function P.liftS(steps, x, y)
    if x < 0 or y < 0 or x >= S.cw or y >= S.ch then return end
    local p = (y * S.cw + x) * 4
    if S.opx[p + 3] == 0 then S.opx[p + 3] = steps end
end

-- Put key k at board-picture pixel (i, j).
local function put(k, i, j, a) putS(k, floor(i - floor(S.camx)), floor(j - floor(S.camy)), a) end
P.put = put

function P.lift(steps, i, j) P.liftS(steps, floor(i - floor(S.camx)), floor(j - floor(S.camy))) end

-- Is room depth d nearer than the board at picture pixel (i, j)?
local function visible(i, j, d)
    local w = S.world
    if i < 0 or j < 0 or i >= w.w or j >= w.h then return true end
    return d >= w.dep[j * w.w + i] - 0.6
end
P.visible = visible

-- Is picture pixel (i, j) on the canvas at all?
local function onScreen(i, j, pad)
    pad = pad or 0
    local x, y = i - floor(S.camx), j - floor(S.camy)
    return x >= -pad and y >= -pad and x < S.cw + pad and y < S.ch + pad
end
P.onScreen = onScreen

-- A picture laid down with its pivot at a room point, through a remap. If it
-- has windows, they are put as lamps and the rest of it as walls.
function P.stamp(pic, x, y, z, remap)
    remap = remap or T.SAME
    local si, sj, d = S.world:toImage(x, y, z)
    local bi, bj = floor(si) - pic.oi, floor(sj) - pic.oj
    if not onScreen(bi, bj, pic.w + pic.h) then return end
    local w, win, lamp, wall = pic.w, pic.win, P.LAMP, P.WALL
    for pj = 0, pic.h - 1 do
        for pi = 0, w - 1 do
            local n = pj * w + pi
            local k = pic.key[n]
            if k ~= 0 and visible(bi + pi, bj + pj, d + pic.dep[n]) then
                put(remap[k], bi + pi, bj + pj, win and (win[n] == 1 and lamp or wall) or nil)
            end
        end
    end
end

-- A picture laid down as P.stamp does, and where the map stands in front of
-- it (a beast in the trees, behind a hill), seen through: every other pixel
-- of it, a step darker, as through leaves.
function P.stampThrough(pic, x, y, z, remap)
    remap = remap or T.SAME
    local si, sj, d = S.world:toImage(x, y, z)
    local bi, bj = floor(si) - pic.oi, floor(sj) - pic.oj
    if not onScreen(bi, bj, pic.w + pic.h) then return end
    local w = pic.w
    for pj = 0, pic.h - 1 do
        for pi = 0, w - 1 do
            local n = pj * w + pi
            local k = pic.key[n]
            if k ~= 0 then
                local i, j = bi + pi, bj + pj
                if visible(i, j, d + pic.dep[n]) then
                    put(remap[k], i, j)
                elseif (i + j) % 2 == 0 then
                    put(remap[T.DARKER[k]], i, j)
                end
            end
        end
    end
end

-- A one-pixel line in the room, from (x0, y0, z0) to (x1, y1, z1), in key k
-- (or a function of how far along, answering a key or nothing), kept behind
-- whatever stands in front of it.
function P.line3(x0, y0, z0, x1, y1, z1, k)
    local i0, j0, d0 = S.world:toImage(x0, y0, z0)
    local i1, j1, d1 = S.world:toImage(x1, y1, z1)
    local n = max(1, math.ceil(max(abs(i1 - i0), abs(j1 - j0))))
    for s = 0, n do
        local f = s / n
        local i, j = floor(i0 + (i1 - i0) * f), floor(j0 + (j1 - j0) * f)
        local key = k
        if type(k) == "function" then key = k(f, i, j) end
        if key and visible(i, j, d0 + (d1 - d0) * f + 1) then put(key, i, j) end
    end
end

-- Every pixel of hex `cell`'s top: f(i, j, n) for each, n its index in the
-- board's buffers.
function P.eachTop(cell, f)
    local w = S.world
    local i0, i1, j0, j1 = w:topBox(cell)
    if not onScreen(i0, j0, (i1 - i0) + (j1 - j0)) then return end
    local cid, up = w.cell, w.up
    for j = max(0, j0), min(w.h - 1, j1) do
        for i = max(0, i0), min(w.w - 1, i1) do
            local n = j * w.w + i
            if cid[n] == cell.id and up[n] == 1 then f(i, j, n) end
        end
    end
end

-- A hex's outline on its top, `inset` units in from its edge.
function P.hexLine(cell, k, inset, lift)
    local H = require "src.hex"
    local r = (H.R - (inset or 0) * 1.1547)
    local y = cell.top + (lift or 0.2)
    for e = 0, 5 do
        local a0, a1 = math.rad(60 * e - 30), math.rad(60 * e + 30)
        P.line3(cell.x + r * math.cos(a0), y, cell.z + r * math.sin(a0),
            cell.x + r * math.cos(a1), y, cell.z + r * math.sin(a1), k)
    end
end

return P
