-- Birds: now and then a flock crosses the map in a loose V, mostly with the
-- wind, and over the shore a gull or two wheels round. They fly over
-- everything, so they are put on top of the board without its depth, in
-- the board picture's pixels so they keep their place as the map pans.
--
-- Each is five pixels, its wings up, in a shallow V or down; dark, and
-- light only over the darkest ground, so it shows over a forest as over a
-- field.

local T = require "src.tracer"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Sea = require "src.ui.sea"

local floor, sin, cos, random = math.floor, math.sin, math.cos, math.random
local IDX = T.IDX

local Birds = {}

local flocks = {}
local wait = 6          -- seconds till the next flock

-- The wing pixels either side of the body, for each beat: up, a shallow V
-- (as it glides), down, the V again.
local WINGS = {
    { -2, -2, -1, -1, 1, -1, 2, -2 },
    { -2, -1, -1, 0, 1, 0, 2, -1 },
    { -2, 1, -1, 0, 1, 0, 2, 1 },
    { -2, -1, -1, 0, 1, 0, 2, -1 },
}

local function bird(i, j, beat)
    i, j = floor(i), floor(j)
    local w = S.world
    local x, y = i - floor(S.camx), j - floor(S.camy)
    if x < 2 or y < 2 or x >= S.cw - 2 or y >= S.ch - 2 then return end
    -- Dark, unless what is under it is darker still.
    local dark = false
    if i >= 0 and j >= 0 and i < w.w and j < w.h then dark = w.px[(j * w.w + i) * 4] < 100 end
    local k = dark and IDX.c or IDX.o
    local f = WINGS[beat % 4 + 1]
    P.putS(k, x, y)
    for n = 1, 8, 2 do P.putS(k, x + f[n], y + f[n + 1]) end
end

-- A new flock coming in over an edge of the screen, flying across it.
local function launch()
    local n = 3 + floor(random() * 5)
    local a = (random() - 0.5) * 0.9
    local west = random() < 0.8 -- mostly with the wind
    if not west then a = a + math.pi end
    local speed = 20 + random() * 10
    local cx, cy = floor(S.camx), floor(S.camy)
    local i = west and cx - 20 or cx + S.cw + 20
    local j = cy + S.ch * (0.15 + random() * 0.7)
    local f = { i = i, j = j, vi = cos(a) * speed, vj = sin(a) * speed, birds = {} }
    for k = 1, n do
        local rank, side = floor(k / 2), (k % 2 == 0) and 1 or -1
        -- Back along its way and out to a side, a little untidy.
        local back, out = rank * 5 + random() * 2, side * rank * 4 + random() * 2
        f.birds[k] = { di = -cos(a) * back - sin(a) * out, dj = -sin(a) * back + cos(a) * out,
            phase = random() * 4, rate = 6 + random() * 2 }
    end
    flocks[#flocks + 1] = f
end

function Birds.update(dt)
    if not S.world or Sea.still() then return end
    wait = wait - dt
    if wait <= 0 then
        launch()
        wait = 14 + random() * 22
    end
    for n = #flocks, 1, -1 do
        local f = flocks[n]
        f.i, f.j = f.i + f.vi * dt, f.j + f.vj * dt
        local x, y = f.i - S.camx, f.j - S.camy
        if x < -80 or y < -80 or x > S.cw + 80 or y > S.ch + 80 then table.remove(flocks, n) end
    end
end

-- Gulls, over the coast hexes on the screen: one in every few, each round a
-- point offshore, now beating, now gliding.
local function gulls(g, me)
    local t = Sea.air()
    for _, cell in ipairs(g.cells) do
        if cell.terrain == "coast" and me.visible[cell.id] and cell.id % 7 == 0 then
            local i, j = S.world:toImage(cell.x, cell.top + 16, cell.z)
            if P.onScreen(floor(i), floor(j), 20) then
                local a = t * 0.6 + cell.id
                local beat = (sin(t * 0.8 + cell.id) > 0.3) and floor(t * 5) or 1
                bird(i + cos(a) * 12, j + sin(a) * 5, beat)
            end
        end
    end
end

-- Onto the overlay, over everything else on it.
function Birds.draw()
    if Sea.still() then return end
    local g = S.game
    gulls(g, g.players[1])
    local t = Sea.air()
    for _, f in ipairs(flocks) do
        for _, b in ipairs(f.birds) do
            local beat = floor(t * b.rate + b.phase)
            -- Every so often they glide, wings level.
            if sin(t * 0.7 + b.phase) > 0.6 then beat = 1 end
            bird(f.i + b.di, f.j + b.dj + sin(t * 2 + b.phase) * 0.8, beat)
        end
    end
end

return Birds
