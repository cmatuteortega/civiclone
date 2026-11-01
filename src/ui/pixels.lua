-- The overlay: everything that changes on the board, laid a pixel at a time
-- over the board's picture into one byte-for-byte image, each pixel kept only
-- where it is nearer than the board there. Underroot's src/ui/pixels.lua,
-- for a camera that pans rather than turns.
--
-- What is laid in a frame (P.begin to P.finish) is kept as a list of what
-- was asked, not laid at once: each pixel put or lifted, each picture
-- stamped. Most of it is what was asked the frame before (the towns, the
-- farms, the units standing still), so the canvas is cut into tiles, and
-- only a tile whose list differs from the last frame's is cleared and laid
-- again, in the same order, everything else left as it was. A tile comes
-- out byte for byte as it would laid whole; only the work is spared.

local ffi = require "ffi"
local T = require "src.tracer"
local S = require "src.ui.state"
local World = require "src.world"

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local P = {}
local RGB8 = World.RGB8
local R8, G8, B8 = {}, {}, {}
for k, c in pairs(RGB8) do R8[k], G8[k], B8[k] = c[1], c[2], c[3] end

-- The alpha a pixel is put with that is a window or a door, lit at night
-- (src/ui/sea.lua's cover), and one that is the rest of a building with
-- windows, which takes the night as the ground does. Neither is blended:
-- the cover draws every pixel of the overlay whole.
P.LAMP, P.WALL = 250, 252

--- the frame's list -------------------------------------------------------------

-- A tile is TILE pixels square.
local TILE, SHIFT = 16, 4
P.TILE = TILE

-- What a frame asked, in order: kind (PUT, LIFT, STAMP or THROUGH), where on
-- the canvas, and what (a key and an alpha; the steps; the stamp's number).
-- Each stamp's picture, remap, place and depth beside. Then, by tile, which
-- of them touch it, in order.
local PUT, LIFT, STAMP, THROUGH = 1, 2, 3, 4
local function newFrame()
    return { n = 0, kind = {}, x = {}, y = {}, v = {},
        ns = 0, pic = {}, remap = {}, bi = {}, bj = {}, d = {}, dark = {},
        tx0 = {}, ty0 = {}, tx1 = {}, ty1 = {},
        start = {}, at = {}, fill = {} }
end
local cur, prev = newFrame(), newFrame()
-- What the last frame was laid on: when any of it changes, all is laid again.
local laid = {}
-- The tiles to lay this frame.
local dirty = {}

-- Put key k at canvas pixel (x, y); `a` the alpha, if not the plain 255.
local function putS(k, x, y, a)
    if k == 0 or x < 0 or y < 0 or x >= S.cw or y >= S.ch then return end
    local f = cur
    local n = f.n + 1
    f.n = n
    f.kind[n], f.x[n], f.y[n], f.v[n] = PUT, x, y, k * 256 + (a or 255)
end
P.putS = putS

-- Mark canvas pixel (x, y), on the sea, to show `steps` lighter. The sea is
-- painted again every frame (src/ui/sea.lua), so a mark over it can't be a
-- colour: it is left in the alpha, which the overlay is never drawn with.
function P.liftS(steps, x, y)
    if x < 0 or y < 0 or x >= S.cw or y >= S.ch then return end
    local f = cur
    local n = f.n + 1
    f.n = n
    f.kind[n], f.x[n], f.y[n], f.v[n] = LIFT, x, y, steps
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
-- has windows, they are put as lamps and the rest of it as walls; `dark`
-- of them (0..1, by little blocks of the picture) left unlit, as in a town
-- the plague has emptied.
local function dim(pi, pj, dark)
    local n = math.sin(floor(pi / 3) * 12.9898 + floor(pj / 3) * 78.233) * 43758.5453
    return n - floor(n) < dark
end

-- Each picture's pixels that are there, listed once: where in it, its key,
-- its depth, and 1 a window, 2 a wall, 0 neither.
local listed = setmetatable({}, { __mode = "k" })
local function opaque(pic)
    local o = listed[pic]
    if o then return o end
    o = { n = 0, i = {}, j = {}, k = {}, d = {}, win = {} }
    local w, key, dep, win = pic.w, pic.key, pic.dep, pic.win
    for pj = 0, pic.h - 1 do
        for pi = 0, w - 1 do
            local q = pj * w + pi
            if key[q] ~= 0 then
                local n = o.n + 1
                o.n = n
                o.i[n], o.j[n], o.k[n], o.d[n] = pi, pj, key[q], dep[q]
                o.win[n] = win and (win[q] == 1 and 1 or 2) or 0
            end
        end
    end
    listed[pic] = o
    return o
end

-- Asks for a stamp: where it would land, kept for P.finish.
local function ask(kind, pic, x, y, z, remap, dark)
    local si, sj, d = S.world:toImage(x, y, z)
    local bi, bj = floor(si) - pic.oi, floor(sj) - pic.oj
    if not onScreen(bi, bj, pic.w + pic.h) then return end
    -- The tiles under it, on the canvas.
    local cx, cy = floor(S.camx), floor(S.camy)
    local x0, y0 = max(0, bi - cx), max(0, bj - cy)
    local x1, y1 = min(S.cw - 1, bi - cx + pic.w - 1), min(S.ch - 1, bj - cy + pic.h - 1)
    if x1 < x0 or y1 < y0 then return end
    local f = cur
    local s = f.ns + 1
    f.ns = s
    f.pic[s], f.remap[s], f.bi[s], f.bj[s], f.d[s], f.dark[s] = pic, remap or T.SAME, bi, bj, d, dark or false
    f.tx0[s], f.ty0[s], f.tx1[s], f.ty1[s] = floor(x0 / TILE), floor(y0 / TILE), floor(x1 / TILE), floor(y1 / TILE)
    local n = f.n + 1
    f.n = n
    f.kind[n], f.x[n], f.y[n], f.v[n] = kind, 0, 0, s
end

function P.stamp(pic, x, y, z, remap, dark) ask(STAMP, pic, x, y, z, remap, dark) end

-- A picture laid down as P.stamp does, and where the map stands in front of
-- it (a beast in the trees, behind a hill), seen through: every other pixel
-- of it, a step darker, as through leaves.
function P.stampThrough(pic, x, y, z, remap) ask(THROUGH, pic, x, y, z, remap) end

-- Lays stamp s of frame f on the overlay: only on the tiles marked in `on`,
-- or everywhere without it.
local function lay(f, s, through, on, tw)
    local pic, remap, bi, bj, d, dark = f.pic[s], f.remap[s], f.bi[s], f.bj[s], f.d[s], f.dark[s]
    local o = opaque(pic)
    local w = S.world
    local ww, wh, dep = w.w, w.h, w.dep
    local cw, ch, opx = S.cw, S.ch, S.opx
    local cx, cy = floor(S.camx), floor(S.camy)
    local oi, oj, ok, od, ow = o.i, o.j, o.k, o.d, o.win
    local LAMP, WALL, DARKER = P.LAMP, P.WALL, T.DARKER
    for q = 1, o.n do
        local i, j = bi + oi[q], bj + oj[q]
        local x, y = i - cx, j - cy
        if x >= 0 and y >= 0 and x < cw and y < ch
            and (not on or on[(y - y % TILE) / TILE * tw + (x - x % TILE) / TILE]) then
            local k, a
            if i < 0 or j < 0 or i >= ww or j >= wh or d + od[q] >= dep[j * ww + i] - 0.6 then
                k, a = remap[ok[q]], 255
                if not through then
                    local wn = ow[q]
                    if wn ~= 0 then
                        a = wn == 1 and LAMP or WALL
                        if a == LAMP and dark and dim(oi[q], oj[q], dark) then a = WALL end
                    end
                end
            elseif through and (i + j) % 2 == 0 then
                k, a = remap[DARKER[ok[q]]], 255
            end
            if k and k ~= 0 then
                local p = (y * cw + x) * 4
                opx[p], opx[p + 1], opx[p + 2], opx[p + 3] = R8[k], G8[k], B8[k], a
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

--- laying the frame -------------------------------------------------------------

-- A new frame's list, empty.
function P.begin()
    prev, cur = cur, prev
    cur.n, cur.ns = 0, 0
end

-- Which of frame f's asks touch each tile: f.at from f.start[t] on, in the
-- order they were asked. `tw` tiles across, `nt` in all.
local function sort(f, tw, nt)
    local start, at, kind, xs, ys, v = f.start, f.at, f.kind, f.x, f.y, f.v
    local tx0, ty0, tx1, ty1 = f.tx0, f.ty0, f.tx1, f.ty1
    for t = 0, nt do start[t] = 0 end
    for n = 1, f.n do
        local k = kind[n]
        if k <= LIFT then
            local t = floor(ys[n] / TILE) * tw + floor(xs[n] / TILE)
            start[t] = start[t] + 1
        else
            local s = v[n]
            for ty = ty0[s], ty1[s] do
                for tx = tx0[s], tx1[s] do
                    local t = ty * tw + tx
                    start[t] = start[t] + 1
                end
            end
        end
    end
    -- From counts to where each tile's run begins (1-based), and a cursor.
    local sum = 1
    for t = 0, nt do
        local c = start[t]
        start[t] = sum
        sum = sum + c
    end
    local fill = f.fill
    for t = 0, nt do fill[t] = start[t] end
    for n = 1, f.n do
        local k = kind[n]
        if k <= LIFT then
            local t = floor(ys[n] / TILE) * tw + floor(xs[n] / TILE)
            local q = fill[t]
            fill[t] = q + 1
            at[q] = n
        else
            local s = v[n]
            for ty = ty0[s], ty1[s] do
                for tx = tx0[s], tx1[s] do
                    local t = ty * tw + tx
                    local q = fill[t]
                    fill[t] = q + 1
                    at[q] = n
                end
            end
        end
    end
end

-- Is ask a of frame f the same as ask b of frame g?
local function same(f, a, g, b)
    local k = f.kind[a]
    if k ~= g.kind[b] then return false end
    if k <= LIFT then return f.x[a] == g.x[b] and f.y[a] == g.y[b] and f.v[a] == g.v[b] end
    local s, r = f.v[a], g.v[b]
    return f.pic[s] == g.pic[r] and f.bi[s] == g.bi[r] and f.bj[s] == g.bj[r] and f.d[s] == g.d[r]
        and f.remap[s] == g.remap[r] and f.dark[s] == g.dark[r]
end

-- A tile's asks, this frame and the last, the same in the same order?
local function unchanged(t)
    local a0, a1 = cur.start[t], cur.start[t + 1]
    local b0, b1 = prev.start[t], prev.start[t + 1]
    if a1 - a0 ~= b1 - b0 then return false end
    local ca, pa = cur.at, prev.at
    for q = 0, a1 - a0 - 1 do
        if not same(cur, ca[a0 + q], prev, pa[b0 + q]) then return false end
    end
    return true
end

-- Lays the frame's list onto the overlay: everything, if the board, the
-- camera or the canvas has changed since the last frame, else only the tiles
-- whose asks have (or everything, if `whole`). Answers the box of canvas
-- pixels laid again (x0, y0, x1, y1), or nothing if none was.
function P.finish(whole)
    local w, cw, ch, opx = S.world, S.cw, S.ch, S.opx
    local cx, cy = floor(S.camx), floor(S.camy)
    local tw, th = math.ceil(cw / TILE), math.ceil(ch / TILE)
    local nt = tw * th
    whole = whole or laid.world ~= w or laid.version ~= w.version or laid.overlay ~= S.overlay
        or laid.cx ~= cx or laid.cy ~= cy or laid.cw ~= cw or laid.ch ~= ch
    laid.world, laid.version, laid.overlay, laid.cx, laid.cy, laid.cw, laid.ch = w, w.version, S.overlay, cx, cy, cw, ch
    sort(cur, tw, nt)
    if whole then
        ffi.fill(opx, cw * ch * 4, 0)
        for t = 0, nt - 1 do dirty[t] = true end
    else
        local any = false
        for t = 0, nt - 1 do
            local d = not unchanged(t)
            dirty[t] = d
            any = any or d
        end
        if not any then return end
    end
    -- The tiles to lay cleared, and the box round them.
    local bx0, by0, bx1, by1 = tw, th, -1, -1
    for ty = 0, th - 1 do
        for tx = 0, tw - 1 do
            if dirty[ty * tw + tx] then
                bx0, by0, bx1, by1 = min(bx0, tx), min(by0, ty), max(bx1, tx), max(by1, ty)
                if not whole then
                    local x0, y0 = tx * TILE, ty * TILE
                    local x1, y1 = min(cw, x0 + TILE), min(ch, y0 + TILE)
                    for y = y0, y1 - 1 do ffi.fill(opx + (y * cw + x0) * 4, (x1 - x0) * 4, 0) end
                end
            end
        end
    end
    -- Everything asked that touches them, in order.
    local on = not whole and dirty or nil
    local f = cur
    local kind, xs, ys, v = f.kind, f.x, f.y, f.v
    local tx0, ty0, tx1, ty1 = f.tx0, f.ty0, f.tx1, f.ty1
    for n = 1, f.n do
        local k = kind[n]
        if k <= LIFT then
            local x, y = xs[n], ys[n]
            if whole or dirty[floor(y / TILE) * tw + floor(x / TILE)] then
                local p = (y * cw + x) * 4
                if k == PUT then
                    local key = floor(v[n] / 256)
                    opx[p], opx[p + 1], opx[p + 2], opx[p + 3] = R8[key], G8[key], B8[key], v[n] % 256
                elseif opx[p + 3] == 0 then
                    opx[p + 3] = v[n]
                end
            end
        else
            local s = v[n]
            local hit = whole
            if not hit then
                for ty = ty0[s], ty1[s] do
                    for tx = tx0[s], tx1[s] do
                        if dirty[ty * tw + tx] then hit = true break end
                    end
                    if hit then break end
                end
            end
            if hit then lay(f, s, k == THROUGH, on, tw) end
        end
    end
    return bx0 * TILE, by0 * TILE, min(cw, (bx1 + 1) * TILE) - 1, min(ch, (by1 + 1) * TILE) - 1
end

return P
