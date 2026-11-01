-- The sky as it falls (src/skyfall.lua), as it is seen: the comet in the
-- sky, its tail longer every turn; the stones coming, each a spark high over
-- the hex it will fall on and the hex ringed on the ground; the fall itself,
-- a streak down out of the sky, a flash, the ground thrown up; the craters
-- glowing while they are hot; and the dust, darker stage by stage, until the
-- long night (src/ui/daylight.lua keeps the sun from rising). Shooting
-- stars cross the night from the omen on.
--
-- The rules strike at once, as the turn begins; the screen plays it back.
-- src/ui/anim.lua hands each "impact" here, and holds back the hexes it
-- changed, their numbers and the sound until the stone has come down
-- (SkyFx.impact says when). The stones fall one after another, a moment
-- apart, the heart of the comet last and slowest.
--
-- How much dust is in the sky is S.dust, 0 to 1, which the light lays on as
-- a dusk that never lifts. A flash is laid into S.flash, as the lightning's.

local T = require "src.tracer"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Sea = require "src.ui.sea"
local Smoke = require "src.ui.smoke"
local Audio = require "src.ui.audio"
local Cat = require "src.cataclysm"
local Sky = require "src.skyfall"
local D = require "src.defs"
local Daylight = require "src.ui.daylight"

local floor, sin, cos, min, max, abs, random = math.floor, math.sin, math.cos, math.min, math.max, math.abs, math.random
local IDX = T.IDX

local SkyFx = {}

-- How much dust hides the sun in each stage.
SkyFx.DUST = { omen = 0, starfall = 0, bombard = 0.15, dark = 0.55 }
-- How long each stone takes to come down, in seconds, how long it shakes
-- the ground after, and how far apart one turn's stones fall.
local FALL = { small = 0.75, big = 1.0, heart = 2.6 }
local BURST = { small = 0.9, big = 1.6, heart = 3.5 }
local APART = 0.3
local MOST = 4         -- seconds of stones queued, at most
-- Where a stone comes from: this far up and to the west of where it falls,
-- in pixels of the picture (the comet's side).
local FROM = { -70, -150 }

local dust, clock = 0, 0
local falls = {}       -- the stones coming down now
local later = {}       -- hexes to build again once their stone is down: { id, at }
local queue = 0        -- when the next stone of this turn can start
local shooting         -- the shooting star crossing now
local nextShot = 3

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

local function game() return S.game end

-- How much dust there should be now.
function SkyFx.want(g)
    -- The sundering's ash (src/ui/quake.lua) hides the sun as the dust does.
    if g and Cat.is(g, "quake") then return require("src.ui.quake").dust(g) end
    if not g or not Cat.is(g, "sky") then return 0 end
    local s = Cat.stage(g)
    return s and SkyFx.DUST[s] or 0
end

--- the fall, played back -----------------------------------------------------------------

-- A stone fallen (the "impact" event): when it lands, from now, in seconds,
-- and how far round it the land it changed reaches.
function SkyFx.impact(g, e)
    local start = max(0, queue - clock)
    -- Stones of turns gone by (skipped through), or more than can be shown
    -- in a few seconds, are not played back: their land is built at once.
    if e.turn ~= g.turn or start > MOST then return 0, 0 end
    local size = e.size
    local fall = FALL[size]
    local cell = g.cells[e.cell]
    local seen = g.players[1].explored[e.cell]
    falls[#falls + 1] = { cell = cell, size = size, water = e.water, t = -start, fall = fall, seen = seen,
        seed = e.cell * 7 + #falls }
    queue = clock + start + (size == "heart" and 1.2 or APART)
    if seen then
        local loud = size == "heart" and 1 or size == "big" and 0.8 or 0.55
        Audio.at("whoosh", e.cell, loud, start, size == "heart" and 0.6 or size == "big" and 0.8 or 1)
        Audio.at(e.water and "splash" or (size == "heart" and "heartfall" or "impact"), e.cell, loud, start + fall,
            size == "small" and 1.15 or 1)
    end
    return start + fall, size == "heart" and 2 or 1
end

-- Hex `id` built again after `delay` seconds, not now.
function SkyFx.later(id, delay)
    later[#later + 1] = { id = id, at = clock + delay }
end

function SkyFx.update(dt)
    clock = clock + dt
    local g = game()
    local want = S.mode == "play" and SkyFx.want(g) or 0
    if S.plan then dust = want end
    dust = dust + (want - dust) * min(1, dt * 0.5)
    S.dust = dust
    if queue < clock then queue = clock end
    local flash = 0
    for k = #falls, 1, -1 do
        local f = falls[k]
        f.t = f.t + dt
        if f.t >= f.fall and not f.landed then
            f.landed = true
            if f.seen then
                S.effects[#S.effects + 1] = { kind = "dust", t = 0, life = f.size == "heart" and 2 or 1.1,
                    x = f.cell.x, y = f.cell.top, z = f.cell.z, seed = f.cell.id }
            end
        end
        if f.landed and f.seen then
            local since = f.t - f.fall
            local peak = f.size == "heart" and 1 or f.size == "big" and 0.6 or 0.35
            flash = max(flash, peak * max(0, 1 - since / (f.size == "heart" and 0.9 or 0.25)))
        end
        if f.t >= f.fall + BURST[f.size] then table.remove(falls, k) end
    end
    if flash > 0 then S.flash = max(S.flash or 0, flash) end
    -- The land the stones changed, built again as they land.
    local due = {}
    for k = #later, 1, -1 do
        if later[k].at <= clock then
            due[#due + 1] = later[k].id
            table.remove(later, k)
        end
    end
    if #due > 0 and S.world then S.world:refreshAll(due) end
    -- A shooting star now and then, at night, once the comet is seen.
    if shooting then
        shooting.t = shooting.t + dt
        if shooting.t > shooting.life then shooting = nil end
    end
    nextShot = nextShot - dt
    if nextShot <= 0 and g and Cat.is(g, "sky") and Cat.stage(g) and Daylight.at(Daylight.now()).night > 0.5 and not Sea.still() then
        local cw, ch = S.cw or 320, S.ch or 200
        shooting = { x = cw * (0.1 + random() * 0.8), y = ch * (0.05 + random() * 0.3), t = 0,
            life = 0.45 + random() * 0.3, dx = (random() < 0.5 and -1 or 1) * (0.8 + random() * 0.6), len = 6 + random() * 8 }
        nextShot = 1.5 + random() * 4
    end
end

-- Anything still to land, for pictures and the tests.
function SkyFx.busy() return #falls > 0 or #later > 0 end

--- drawing -------------------------------------------------------------------------------------

-- A streak in canvas pixels: a head at (x, y) with a tail back along
-- (dx, dy), `len` long, `w` wide; white at the head, the pale keys behind.
local function streak(x, y, dx, dy, len, w, seed)
    local l = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / l, dy / l
    local tick = floor(clock * 20)
    for s = len, 0, -1 do
        local f = s / len
        local px, py = x - dx * s, y - dy * s
        local half = (w - 1) * (1 - f) * 0.5
        local k = f < 0.25 and IDX.w or f < 0.6 and IDX.c or IDX.s
        if f < 0.85 or grain(s, tick, seed) > 0.5 then
            for o = -floor(half + 0.5), floor(half + 0.5) do
                P.putS(k, floor(px - dy * o + 0.5), floor(py + dx * o + 0.5))
            end
        end
    end
    -- The head, ringed so it reads on the light ground too.
    local r = max(1, floor(w / 2 + 0.5))
    for a = -r - 1, r + 1 do
        for b = -r - 1, r + 1 do
            local d = a * a + b * b
            if d <= (r + 1) * (r + 1) and d > r * r then P.putS(IDX.o, floor(x) + a, floor(y) + b) end
        end
    end
    for a = -r, r do
        for b = -r, r do
            if a * a + b * b <= r * r then P.putS(IDX.w, floor(x) + a, floor(y) + b) end
        end
    end
end

-- The comet, high in the sky over the map: from the omen to the heart's
-- fall, its tail growing.
local function comet(g)
    if not Cat.is(g, "sky") or not Cat.stage(g) or g.turn >= D.SKY.heart then return end
    local f = (g.turn - D.SKY.omen) / (D.SKY.heart - D.SKY.omen)
    local cw, ch = S.cw, S.ch
    local x, y = cw * (0.8 - 0.25 * f), ch * (0.1 + 0.08 * f)
    local len = 14 + f * 60
    local tick = floor(clock * 6)
    -- The tail streams away from the sun, up and to the east: two of them,
    -- the dust's broad and pale, the gas's straight and fainter.
    for s = len, 1, -1 do
        local u = s / len
        local px, py = x + s * 0.92, y - s * 0.38 - u * u * 6
        local half = 0.5 + u * (2 + f * 3)
        for o = -floor(half), floor(half) do
            local edge = abs(o) / max(1, half)
            if grain(s, o, tick) > u * 0.8 + edge * 0.3 then
                P.putS(u < 0.3 and edge < 0.5 and IDX.w or u < 0.7 and IDX.c or IDX.s, floor(px), floor(py + o))
            end
        end
        if s % 2 == 0 and grain(s, 3, tick) > u then P.putS(IDX.s, floor(x + s * 0.99), floor(y - s * 0.12)) end
    end
    local r = f > 0.5 and 2 or 1
    for a = -r, r do
        for b = -r, r do if a * a + b * b <= r * r then P.putS(IDX.w, floor(x) + a, floor(y) + b) end end
    end
end

-- What is seen of a stone coming, over hex `cell`: the hex hatched on the
-- ground, the hatching running across it, and ringed; and high over it a
-- spark, flickering, its short tail pointing back the way it comes, with a
-- thread of light down to where it will fall.
local function coming(cell, size, list)
    local big = size ~= "small"
    local tick = floor(clock * 10)
    list[#list + 1] = { z = cell.z - 1.5, draw = function()
        local gap = big and 4 or 5
        P.eachTop(cell, function(i, j)
            local d = (i + j * 2 + tick) % gap
            if d == 0 then P.put(IDX.w, i, j) elseif d == 1 and big then P.put(IDX.c, i, j) end
        end)
        P.hexLine(cell, function(f) return floor(f * 12 + clock * 6) % 2 == 0 and IDX.w or IDX.o end, 0.6, 0.4)
        P.hexLine(cell, function(f) return floor(f * 12 - clock * 6) % 2 == 0 and IDX.o or IDX.c end, 1.6, 0.4)
    end }
    if size == "heart" then return end
    list[#list + 1] = { z = cell.z + 50, draw = function()
        local i, j = S.world:toImage(cell.x, cell.top, cell.z)
        local x, y = floor(i - floor(S.camx)), floor(j - floor(S.camy))
        if x < -80 or y < -200 or x > S.cw + 80 or y > S.ch + 40 then return end
        local hx, hy = x + FROM[1] * 0.3, y + FROM[2] * 0.3
        -- A thread of light down to where it will fall.
        for s = 6, floor(y - hy) - 2, 2 do
            local t = s / (y - hy)
            if grain(s, cell.id, floor(clock * 6)) > 0.45 then
                P.putS(IDX.c, floor(hx + (x - hx) * t), floor(hy + (y - hy) * t))
            end
        end
        streak(hx, hy, -FROM[1], -FROM[2], big and 12 or 8, big and 3 or 2, cell.id)
        if grain(cell.id, floor(clock * 8), 31) > 0.4 then
            for _, o in ipairs({ { -3, 0 }, { 3, 0 }, { 0, -3 }, { 0, 3 } }) do
                P.putS(IDX.w, floor(hx) + o[1], floor(hy) + o[2])
            end
        end
    end }
end

-- The heart's mark: its seven hexes ringed, and over them, high up, the
-- heart itself, bigger each turn it comes nearer.
local function heartComing(g, list)
    local cell, left = Sky.heart(g)
    if not cell or not g.players[1].explored[cell.id] then return end
    list[#list + 1] = { z = cell.z + 60, draw = function()
        local i, j = S.world:toImage(cell.x, cell.top, cell.z)
        local x, y = floor(i - floor(S.camx)), floor(j - floor(S.camy))
        local near = 1 - left / (D.SKY.heart - D.SKY.heartWarn + 1)
        local hx, hy = x + FROM[1] * (0.5 - 0.25 * near), y + FROM[2] * (0.5 - 0.25 * near)
        streak(hx, hy, -FROM[1], -FROM[2], 10 + near * 22, 3 + floor(near * 3), cell.id)
    end }
end

-- A stone coming down now, and where it has landed: the flash on the
-- ground, the ring of it going out, the rubble thrown up.
local function falling(f, list)
    local cell = f.cell
    if not f.seen or f.t < 0 then return end
    list[#list + 1] = { z = cell.z + 40, draw = function()
        local i, j = S.world:toImage(cell.x, cell.top, cell.z)
        local x, y = i - floor(S.camx), j - floor(S.camy)
        local scale = f.size == "heart" and 2.4 or f.size == "big" and 1.3 or 1
        if not f.landed then
            local u = f.t / f.fall
            local e = u * u
            local fx, fy = FROM[1] * scale * (1 - e), FROM[2] * scale * (1 - e)
            local w = f.size == "heart" and 7 or f.size == "big" and 4 or 3
            streak(x + fx, y + fy, -FROM[1], -FROM[2], (f.size == "heart" and 80 or 34 * scale) * (0.5 + u), w, f.seed)
            return
        end
        local since = (f.t - f.fall) / BURST[f.size]
        local big, heart = f.size ~= "small", f.size == "heart"
        local cx, cy = floor(x), floor(y)
        -- The cloud thrown up: puffs of dust boiling up and out from where
        -- it struck, inked round as the smoke is, thinning as it settles.
        local puffs = heart and 16 or big and 8 or 4
        local rise = heart and 70 or big and 30 or 14
        local thin = max(0, since - 0.35) * 1.6
        local discs = {}
        for k = 1, puffs do
            local a = grain(k, f.seed, 44) * 2 * math.pi
            local out = (0.3 + grain(f.seed, k, 45) * 0.7) * (heart and 46 or big and 18 or 9)
            local up = (0.2 + grain(k, 7, f.seed) * 0.8) * rise
            local g = 1 - (1 - min(1, since * 2.2)) ^ 2
            discs[k] = { cx + cos(a) * out * g, cy + sin(a) * out * g * T.SE - up * g,
                (heart and 9 or big and 5 or 3) * (0.5 + g * 0.8) * (0.8 + grain(k, k, 46) * 0.4), k }
        end
        table.sort(discs, function(a, b) return a[2] < b[2] end)
        for _, q in ipairs(discs) do
            local r = q[3]
            for b = -floor(r) - 1, floor(r) + 1 do
                for a = -floor(r) - 1, floor(r) + 1 do
                    local dd = a * a + b * b
                    if dd <= (r + 1) * (r + 1) and grain(a, b, q[4] + f.seed) >= thin then
                        local k = IDX.o
                        if dd <= r * r then
                            k = (b < -r * 0.3 and a < 0) and IDX.s or b > r * 0.4 and IDX.n or IDX.t
                            if f.water then k = (b < 0) and IDX.w or IDX.c end
                        end
                        P.putS(k, floor(q[1]) + a, floor(q[2]) + b)
                    end
                end
            end
        end
        -- The blast going out over the ground: two rings of light squashed
        -- as the hexes are, the outer fading first.
        if since < 0.7 then
            local reach = heart and 110 or big and 44 or 20
            for ring = 0, 1 do
                local r = reach * (0.12 + since * (1.1 - ring * 0.35))
                local steps = floor(r * 5)
                for s2 = 0, steps do
                    local a = s2 / steps * 2 * math.pi
                    if grain(s2, f.seed + ring, 41) > since * 1.3 then
                        local px, py = floor(x + cos(a) * r), floor(y + sin(a) * r * T.SE)
                        local k = ring == 0 and (since < 0.3 and IDX.w or IDX.c) or IDX.s
                        P.putS(k, px, py)
                        if big then P.putS(k, px, py + 1) end
                    end
                end
            end
        end
        -- The fireball, white, ringed in the pale keys, shrinking.
        if since < 0.3 then
            local core = (heart and 26 or big and 11 or 5) * (1 - since * 2.5)
            for b = -floor(core) - 2, floor(core) + 2 do
                for a = -floor(core * 1.4) - 2, floor(core * 1.4) + 2 do
                    local dd = (a / 1.4) ^ 2 + b * b
                    if dd <= core * core then P.putS(IDX.w, cx + a, cy + b - floor(core * 0.4))
                    elseif dd <= (core + 2) ^ 2 then P.putS(IDX.c, cx + a, cy + b - floor(core * 0.4)) end
                end
            end
        end
        -- Rubble, thrown up and out, falling back: lumps of a few pixels
        -- from a great stone.
        local n = heart and 44 or big and 24 or 10
        local lump = heart and 2 or big and 1 or 0
        for k = 1, n do
            local a = grain(k, f.seed, 42) * 2 * math.pi
            local speed = (10 + grain(f.seed, k, 43) * 26) * scale
            local up = (18 + grain(k, k, f.seed) * 30) * scale
            local u = min(1, since * 1.3)
            local px = floor(x + cos(a) * speed * u)
            local py = floor(y + sin(a) * speed * u * T.SE - up * u * (1 - u) * 4)
            if u < 1 then
                for b = 0, lump do
                    for a2 = 0, lump do
                        local k2 = f.water and (k % 2 == 0 and IDX.w or IDX.c)
                            or ((a2 == 0 and b == 0) and IDX.s or IDX.u)
                        P.putS(k2, px + a2, py + b)
                    end
                end
            end
        end
    end }
end

-- A crater still hot: the pit's dark catching red, here and there, and a
-- thread of smoke going up.
local function glowing(cell, list)
    local w = S.world
    local tick = floor(S.clock * 5)
    list[#list + 1] = { z = cell.z - 1.2, draw = function()
        local r2 = (2 + (cell.sunk or 0) * 0.6) ^ 2
        P.eachTop(cell, function(i, j, n)
            local x, z = w.wx[n] - cell.x, w.wz[n] - cell.z
            if x * x + z * z < r2 and grain(i, j, tick) > 0.72 then
                P.put(grain(j, i, tick) > 0.5 and IDX.w or IDX.c, i, j)
            end
        end)
        Smoke.fire(cell.x + 0.5, cell.top + 3, cell.z, cell.id * 5 + 2, 0.55)
    end }
end

-- Everything of the sky's on the board, onto `list` (src/ui/board.lua sorts
-- what it draws, back to front).
function SkyFx.things(me, list)
    local g = game()
    if not g or not Cat.is(g, "sky") then return end
    for _, cell in ipairs(g.cells) do
        if me.explored[cell.id] then
            if cell.glow and not cell.city then glowing(cell, list) end
            local m = Sky.marked(g, cell)
            if m then coming(cell, m, list) end
        end
    end
    heartComing(g, list)
    for _, f in ipairs(falls) do falling(f, list) end
end

-- Onto the overlay over everything: the comet and the shooting stars.
function SkyFx.draw()
    local g = game()
    if not g or not S.world or not Cat.is(g, "sky") then return end
    comet(g)
    if shooting then
        local s = shooting
        local u = s.t / s.life
        streak(s.x + s.dx * u * 40, s.y + u * 18, s.dx * 40, 18, s.len * (1 - abs(u - 0.5)), 1, 77)
    end
end

-- How dark the dust has made it, 0..1.
function SkyFx.dust() return dust end

-- Everything still falling down at once: the land it changed built now,
-- nothing left to play back (pictures taken for checking start so).
function SkyFx.flush()
    local ids = {}
    for _, l in ipairs(later) do ids[#ids + 1] = l.id end
    if #ids > 0 and S.world then S.world:refreshAll(ids) end
    falls, later, queue = {}, {}, clock
end

return SkyFx
