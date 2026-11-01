-- The sundering (src/quake.lua), as it is seen: the ground shaking, the
-- faults and the rift tearing open, the sea pouring in, the mountains
-- heaving up, the volcanoes smoking and erupting, the lava glowing and the
-- waves running in on the shore; and what is coming, the turn before: a
-- quake's hex ringed and trembling, a volcano's smoke thickening, the sea
-- drawn back off a shore with the wave building far out, and the rift's
-- line across the land before it tears.
--
-- The rules strike at once, as the turn begins; the screen plays it back,
-- one thing after another, as the sky's stones are (src/ui/sky.lua):
-- src/ui/anim.lua hands each event here, and holds back the hexes it
-- changed until it has played (QuakeFx.event says when). The whole board
-- shakes while a quake does: S.shake, in canvas pixels, laid on as the
-- board is drawn (main.lua).

local T = require "src.tracer"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local H = require "src.hex"
local Sea = require "src.ui.sea"
local Smoke = require "src.ui.smoke"
local Audio = require "src.ui.audio"
local Cat = require "src.cataclysm"
local Quake = require "src.quake"

local floor, sin, cos, min, max, sqrt = math.floor, math.sin, math.cos, math.min, math.max, math.sqrt
local IDX = T.IDX

local QuakeFx = {}

-- How long each thing plays, in seconds, and how far apart one turn's
-- things start.
local LONG = { tremor = 1.8, erupt = 3.2, wave = 1.6, sunder = 1.2, uplift = 1.2, greatquake = 4 }
-- When in its playing the land it changes is built again.
local WHEN = { tremor = 0.35, erupt = 1.0, wave = 1.15, sunder = 0.45, uplift = 0.6, greatquake = 0.6 }
local APART = { tremor = 1.1, erupt = 1.6, wave = 0, sunder = 0.35, uplift = 0.4, greatquake = 1.5 }
local MOST = 6         -- seconds of it queued, at most

local clock, queue = 0, 0
local plays = {}       -- what is playing now, or about to
local waveAt           -- when this turn's waves come in, all together
local shook = 0        -- how hard the ground shakes now

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

local function game() return S.game end

local function seen(g, id) return g.players[1].explored[id] end

-- Canvas pixel of a room point.
local function screen(x, y, z)
    local i, j, d = S.world:toImage(x, y, z)
    return i - floor(S.camx), j - floor(S.camy), d
end

--- the playing back -----------------------------------------------------------------------

-- An event of the sundering's, off the game's list: when the land it
-- changed should be built again, from now, in seconds (0: at once), and how
-- far round it that land reaches.
function QuakeFx.event(g, e)
    local kind = e.kind
    if not LONG[kind] then return 0, 0 end
    -- Turns gone by (skipped through), or more than can be shown in a few
    -- seconds, are not played back: their land is built at once.
    if e.turn ~= g.turn then return 0, 0 end
    local start = max(0, queue - clock)
    if kind == "wave" then
        -- The waves of a turn come in together, a little apart by where.
        if not waveAt or waveAt < clock then waveAt = clock + start end
        start = waveAt - clock + grain(e.cell, 1, 5) * 0.3
    end
    if start > MOST then return 0, 0 end
    local cell = g.cells[e.cell]
    local look = kind == "greatquake" or (cell and seen(g, e.cell))
    plays[#plays + 1] = { kind = kind, cell = cell, e = e, t = -start, seen = look, seed = (e.cell or 1) * 7 + #plays }
    if kind ~= "wave" then queue = clock + start + APART[kind] end
    if look then
        local id = e.cell
        if kind == "tremor" then
            Audio.at("rumble", id, e.water and 0.6 or 0.9, start, 1 - (e.reach or 1) * 0.08)
        elseif kind == "erupt" then
            Audio.at("eruption", id, 1, start)
        elseif kind == "wave" then
            if grain(e.cell, 2, 6) < 0.5 then Audio.at("wave", id, 0.9, start, 0.9 + grain(e.cell, 3, 6) * 0.2) end
        elseif kind == "sunder" then
            Audio.at(e.step >= 3 and "splash" or "rumble", id, 0.7, start + WHEN.sunder, e.step >= 3 and 0.5 or 1.3)
        elseif kind == "uplift" then
            Audio.at("rumble", id, 0.6, start, 1.4)
        elseif kind == "greatquake" then
            Audio.at("rumble", nil, 1, start, 0.7)
            Audio.at("rumble", nil, 0.9, start + 1.2, 0.6)
        end
    end
    local reach = kind == "tremor" and (e.reach or 1) + 1 or kind == "erupt" and 2 or kind == "greatquake" and 0 or 1
    return start + WHEN[kind], reach
end

function QuakeFx.busy() return #plays > 0 end

-- Everything still to play, played now (pictures taken for checking start
-- so).
function QuakeFx.flush()
    plays, queue, waveAt = {}, clock, nil
    S.shake = nil
end

function QuakeFx.update(dt)
    clock = clock + dt
    if queue < clock then queue = clock end
    local g = game()
    local amp = 0
    for k = #plays, 1, -1 do
        local p = plays[k]
        p.t = p.t + dt
        local u = p.t / LONG[p.kind]
        -- The ground shakes: hardest at the start, dying away.
        if p.t >= 0 and p.seen then
            local f = max(0, 1 - u)
            if p.kind == "tremor" then amp = amp + f * f * (1.2 + (p.e.reach or 1) * 0.9)
            elseif p.kind == "greatquake" then amp = amp + 4 * f
            elseif p.kind == "erupt" and p.t < 1.2 then amp = amp + 1.5 * (1 - p.t / 1.2)
            elseif p.kind == "uplift" then amp = amp + 0.8 * f
            elseif p.kind == "sunder" and p.t > WHEN.sunder then amp = amp + 0.6 * f end
        end
        -- Dust thrown up off the hexes a quake shakes, as it reaches them.
        if p.kind == "tremor" and p.seen and p.t >= 0 and not p.dusted and g then
            p.dusted = true
            for _, n in ipairs(g:within(p.cell, p.e.reach or 1)) do
                if not g:isWater(n) and seen(g, n.id) then
                    S.effects[#S.effects + 1] = { kind = "dust", t = 0, life = 1.2,
                        delay = g:dist(n, p.cell) * 0.18, x = n.x, y = n.top, z = n.z, seed = n.id }
                end
            end
        end
        if p.kind == "erupt" and p.seen and p.t >= 0 and not p.flashed then
            p.flashed = true
            S.flash = max(S.flash or 0, 0.5)
        end
        if p.t >= LONG[p.kind] then table.remove(plays, k) end
    end
    if Sea.still() then amp = 0 end
    shook = shook + (amp - shook) * min(1, dt * 20)
    if shook > 0.15 then
        local a = min(5, shook)
        S.shake = { floor(sin(clock * 61) * a + 0.5), floor(sin(clock * 47 + 1.3) * a * 0.5 + 0.5) }
    else
        S.shake = nil
    end
end

--- drawing ----------------------------------------------------------------------------------

-- Puffs of dust or steam boiling up from canvas pixel (x, y): `n` of them,
-- out to `out` and up to `rise`, `size` across, at `g` of their going (0 to
-- 1), thinning by `thin`; light ones (`pale`) for steam and spray.
local function cloud(x, y, n, out, rise, size, g, thin, seed, pale)
    local discs = {}
    for k = 1, n do
        local a = grain(k, seed, 44) * 2 * math.pi
        local o = (0.3 + grain(seed, k, 45) * 0.7) * out
        local up = (0.2 + grain(k, 7, seed) * 0.8) * rise
        discs[k] = { x + cos(a) * o * g, y + sin(a) * o * g * T.SE - up * g, size * (0.5 + g * 0.8) * (0.8 + grain(k, k, 46) * 0.4), k }
    end
    table.sort(discs, function(a, b) return a[2] < b[2] end)
    for _, q in ipairs(discs) do
        local r = q[3]
        for b = -floor(r) - 1, floor(r) + 1 do
            for a = -floor(r) - 1, floor(r) + 1 do
                local dd = a * a + b * b
                if dd <= (r + 1) * (r + 1) and grain(a, b, q[4] + seed) >= thin then
                    local k = IDX.o
                    if dd <= r * r then
                        if pale then k = b < 0 and IDX.w or IDX.c
                        else k = (b < -r * 0.3 and a < 0) and IDX.s or b > r * 0.4 and IDX.n or IDX.t end
                    end
                    P.putS(k, floor(q[1]) + a, floor(q[2]) + b)
                end
            end
        end
    end
end

-- A ring going out over the ground from canvas pixel (x, y), `r` across,
-- squashed as the hexes are, every other bit of it drawn.
local function ring(x, y, r, k, seed, gaps)
    local steps = max(8, floor(r * 5))
    for s = 0, steps do
        local a = s / steps * 2 * math.pi
        if grain(s, seed, 41) > gaps then P.putS(k, floor(x + cos(a) * r), floor(y + sin(a) * r * T.SE)) end
    end
end

-- A quake: rings of the shock going out over the ground, dark and pale,
-- and a jolt of rubble thrown up at its heart.
local function tremor(p, list)
    local cell = p.cell
    local reach = (p.e.reach or 1)
    list[#list + 1] = { z = cell.z + 30, draw = function()
        local x, y = screen(cell.x, cell.top, cell.z)
        local u = p.t / LONG.tremor
        local far = (reach + 0.6) * H.W
        for n = 0, 2 do
            local f = u * 1.6 - n * 0.22
            if f > 0 and f < 1 then
                local r = f * far * 0.5 * T.UNIT
                ring(x, y, r, n == 1 and IDX.c or IDX.u, p.seed + n, 0.25 + f * 0.6)
                ring(x, y + 1, r, IDX.o, p.seed + n + 9, 0.6 + f * 0.4)
            end
        end
        if p.t < 0.7 then
            for k = 1, 14 do
                local a = grain(k, p.seed, 42) * 2 * math.pi
                local sp = (6 + grain(p.seed, k, 43) * 14)
                local f = min(1, p.t * 1.6)
                local px = floor(x + cos(a) * sp * f)
                local py = floor(y + sin(a) * sp * f * T.SE - (10 + grain(k, k, p.seed) * 10) * f * (1 - f) * 4)
                P.putS(k % 3 == 0 and IDX.s or IDX.u, px, py)
            end
        end
    end }
end

-- The top of a volcano's cone (where its crater is), in the room.
local function crater(cell) return cell.x, cell.top + 20, cell.z end

-- An eruption: a flash, a column of ash boiling up out of the crater and
-- out over the land, a fountain of fire, and bombs of lava thrown out to
-- where the lava will run.
local function erupting(p, list)
    local cell = p.cell
    local cx, cy, cz = crater(cell)
    list[#list + 1] = { z = cell.z + 45, draw = function()
        local x, y = screen(cx, cy, cz)
        local t = p.t
        -- The column, rising and spreading, darker and thicker than any
        -- smoke, thinning at the end.
        local g = 1 - (1 - min(1, t / 2.2)) ^ 2
        local thin = max(0, t - 2.2) * 1.2
        cloud(x, y - 6, 14, 26, 70, 7, g, thin, p.seed, false)
        -- The fountain: drops of fire thrown up and falling back.
        if t < 2.6 then
            for k = 1, 40 do
                local life = 0.7 + grain(k, p.seed, 51) * 0.6
                local tt = (t + grain(p.seed, k, 52) * life) % life
                local a = (grain(k, 3, p.seed) - 0.5) * 1.6
                local sp = 10 + grain(k, 4, p.seed) * 22
                local px = floor(x + sin(a) * sp * tt * 1.4)
                local py = floor(y - 2 - (36 + grain(k, 5, p.seed) * 20) * tt + 60 * tt * tt)
                P.putS(tt < life * 0.5 and IDX.w or IDX.c, px, py)
                if k % 4 == 0 then P.putS(IDX.s, px, py + 1) end
            end
        end
        -- The flash, white round the crater.
        if t < 0.35 then
            local core = 9 * (1 - t / 0.35)
            for b = -floor(core) - 1, floor(core) + 1 do
                for a = -floor(core * 1.5) - 1, floor(core * 1.5) + 1 do
                    local dd = (a / 1.5) ^ 2 + b * b
                    if dd <= core * core then P.putS(IDX.w, x + a, y + b - 3)
                    elseif dd <= (core + 1.5) ^ 2 then P.putS(IDX.c, x + a, y + b - 3) end
                end
            end
        end
        -- Bombs, out along an arc to each hex the lava takes, a dark trail
        -- behind each.
        for k, id in ipairs(p.e.lava or {}) do
            local to = S.game.cells[id]
            local f = (t - 0.15 - k * 0.12) / 0.9
            if f > 0 and f < 1 then
                local tx, ty = screen(to.x, to.top, to.z)
                for s = 0, 6 do
                    local ff = max(0, f - s * 0.04)
                    local bx = x + (tx - x) * ff
                    local by = y + (ty - y) * ff - sin(math.pi * ff) * 40
                    P.putS(s == 0 and IDX.w or (s < 3 and IDX.c or IDX.n), floor(bx), floor(by))
                    if s == 0 then
                        P.putS(IDX.c, floor(bx) + 1, floor(by))
                        P.putS(IDX.o, floor(bx), floor(by) + 1)
                    end
                end
            end
        end
    end }
end

-- A wave: a wall of water coming in from the sea hex it rose by onto the
-- shore, its face dark and its crest breaking white, spray thrown off the
-- top; then thrown up white over the land where it strikes.
local function waving(p, list)
    local cell = p.cell
    -- Every crest of one wave runs in from where it rose, out at sea, so
    -- they come in as one front.
    local o = S.game.cells[p.e.origin or p.e.from] or cell
    local dx, dz = cell.x - o.x, cell.z - o.z
    local l = sqrt(dx * dx + dz * dz)
    if l < 0.01 then
        o = S.game.cells[p.e.from] or cell
        dx, dz = cell.x - o.x, cell.z - o.z
        l = sqrt(dx * dx + dz * dz)
    end
    if l < 0.01 then dx, dz = 0, 1 else dx, dz = dx / l, dz / l end
    l = H.W * 1.7
    local from = { x = cell.x - dx * l, z = cell.z - dz * l }
    local ax, az = -dz, dx
    list[#list + 1] = { z = cell.z + 4, draw = function()
        local u = p.t / LONG.wave
        local arrive = WHEN.wave / LONG.wave
        -- From a hex and a half out to the hex's middle.
        local along = (min(u, arrive) / arrive) * (l + H.W * 0.5) - H.W * 1.2
        local base = -2
        local height = 3 + min(u / arrive, 1) * 9
        if u < arrive then
            local half = H.W * 0.95
            -- The swell behind the crest first, dark and lower, then the
            -- face, pale, and the crest breaking white on top.
            for layer = 2, 0, -1 do
                local back = layer * 3.2
                local mx = from.x + dx * (along + H.W * 0.5 - back)
                local mz = from.z + dz * (along + H.W * 0.5 - back)
                local hh0 = height * (1 - layer * 0.3)
                for s = -24, 24 do
                    local f = s / 24
                    local bend = (1 - f * f) * 3
                    local wx, wz = mx + ax * f * half + dx * bend, mz + az * f * half + dz * bend
                    local hh = hh0 * (1 - f * f * 0.6)
                    local x0, y0 = screen(wx, base, wz)
                    local _, y1 = screen(wx, base + hh, wz)
                    local n = max(1, floor(y0 - y1))
                    for k = 0, n do
                        local key
                        if layer > 0 then
                            key = k == 0 and IDX.o or (k < n * 0.4 and IDX.t or IDX.n)
                        else
                            key = (k == 0 and IDX.o) or (k <= 2 and IDX.w) or (k <= n * 0.45 and IDX.c)
                                or (k < n and IDX.s) or IDX.o
                        end
                        P.putS(key, floor(x0), floor(y1 + k))
                        P.putS(key, floor(x0) + 1, floor(y1 + k))
                    end
                    -- Spray off the crest.
                    if layer == 0 and grain(s, floor(clock * 14), p.seed) > 0.55 then
                        for q = 0, 1 do
                            P.putS(IDX.w, floor(x0 + (grain(s, 2 + q, p.seed) - 0.5) * 6),
                                floor(y1 - 1 - grain(s, 3 + q, p.seed) * 6))
                        end
                    end
                end
            end
        else
            -- Thrown up white over the shore, and falling back.
            local x, y = screen(cell.x - dx * 4, cell.top, cell.z - dz * 4)
            local f = (u - arrive) / (1 - arrive)
            cloud(x, y, 9, 20, 18, 4, 1 - (1 - f) ^ 2, f * 1.1, p.seed, true)
        end
    end }
end

-- A step of the rift: the ground split with dust thrown up along it; the
-- sea pouring in white; the halves going down into it.
local function sundering(p, list)
    local cell = p.cell
    local step = p.e.step
    list[#list + 1] = { z = cell.z + 6, draw = function()
        local x, y = screen(cell.x, cell.top, cell.z)
        local f = min(1, max(0, (p.t - WHEN.sunder * 0.5) / (LONG.sunder - WHEN.sunder * 0.5)))
        if step <= 2 then
            -- Dust along the line of it.
            local a = cell.riftAngle or 0
            for s = -1, 1 do
                local sx, sy = screen(cell.x + cos(a) * s * 7, cell.top, cell.z + sin(a) * s * 7)
                cloud(sx, sy, 3, 6, 10 + step * 4, 3, f, f * 1.2, p.seed + s, false)
            end
        else
            cloud(x, y + 2, 7, 12, 14, 4, f, f * 1.1, p.seed, true)
        end
    end }
end

-- New land heaving up: dust off its sides, and rocks rolling.
local function heaving(p, list)
    local cell = p.cell
    list[#list + 1] = { z = cell.z + 5, draw = function()
        local x, y = screen(cell.x, cell.top, cell.z)
        local f = min(1, p.t / LONG.uplift)
        cloud(x, y + 4, 6, 16, 8, 3, f, f * 1.2, p.seed, cell.raised and true or false)
    end }
end

--- what is coming -------------------------------------------------------------------------

-- A quake coming at hex `cell`: its top trembling in rings drawn on it, dark
-- and pale, going out from its middle and coming again.
local function quakeComing(cell, list)
    local w = S.world
    list[#list + 1] = { z = cell.z - 1.5, draw = function()
        local ph = (S.clock * 0.9) % 1
        P.eachTop(cell, function(i, j, n)
            local x, z = w.wx[n] - cell.x, w.wz[n] - cell.z
            local d = sqrt(x * x + z * z) / H.APOTHEM
            local band = (d - ph) * 3
            local fb = band - floor(band)
            if d < 1.05 and fb < 0.12 then P.put((floor(band) % 2 == 0) and IDX.o or IDX.c, i, j)
            elseif d < 1.05 and fb < 0.2 and (i + j) % 2 == 0 then P.put(IDX.u, i, j) end
        end)
        P.hexLine(cell, function(f) return floor(f * 18 + S.clock * 8) % 3 == 0 and IDX.o or nil end, 0.5, 0.3)
    end }
end

-- The sea drawn back off shore hex `cell` before a wave: the shallows by it
-- left bare, pale sand in ripples, and further out a dark line where the
-- water is heaping up.
local function waveComing(g, cell, list)
    local w = S.world
    for _, n in ipairs(g:neighbours(cell)) do
        if g:isWater(n) and g.players[1].explored[n.id] then
            list[#list + 1] = { z = n.z - 1.4, draw = function()
                P.eachTop(n, function(i, j, idx)
                    local x, z = w.wx[idx], w.wz[idx]
                    local d = sqrt((x - cell.x) ^ 2 + (z - cell.z) ^ 2)
                    if d < H.W * 1.05 then
                        local r = sin(x * 0.9 + z * 0.4) + (grain(i, j, 61) - 0.5) * 0.4
                        P.put(r > 0.6 and IDX.s or (r < -0.7 and IDX.t or IDX.c), i, j)
                    elseif d < H.W * 1.15 then
                        P.put(IDX.w, i, j)
                    elseif d > H.W * 1.4 and d < H.W * 1.4 + 1.6 then
                        P.put(floor(S.clock * 3 + d) % 2 == 0 and IDX.o or IDX.u, i, j)
                    end
                end)
            end }
        end
    end
end

-- The rift, seen before it tears: a line of ink across the land through
-- its hexes, broken, with ticks across it.
local function riftLine(g, me, list)
    local c = g.cataclysm
    if not c.rift then return end
    for i = 1, #c.rift - 1 do
        local a, b = g.cells[c.rift[i]], g.cells[c.rift[i + 1]]
        if (me.explored[a.id] or me.explored[b.id]) and not (a.rift or a.sundered) and not (b.rift or b.sundered) then
            list[#list + 1] = { z = min(a.z, b.z) - 1, draw = function()
                P.line3(a.x, a.top + 0.3, a.z, b.x, b.top + 0.3, b.z, function(f, i2, j2)
                    if floor(f * 9) % 3 == 2 then return nil end
                    return IDX.o
                end)
            end }
        end
    end
end

-- A range, before and while it rises: little ridges drawn up across its
-- hexes the way it runs.
local function rangeLine(g, me, list)
    for _, ids in ipairs(g.cataclysm.ranges or {}) do
        for _, id in ipairs(ids) do
            local cell = g.cells[id]
            if me.explored[id] and cell.elev ~= "mountain" and not g:isWater(cell) then
                local a = cell.rangeAngle or 0
                list[#list + 1] = { z = cell.z - 1, draw = function()
                    for s = -1, 1 do
                        local x, z = cell.x + cos(a) * s * 6, cell.z + sin(a) * s * 6
                        local px, pz = -sin(a) * 2.2, cos(a) * 2.2
                        local y = cell.top + (cell.elev == "hills" and 1.4 or 0.2)
                        P.line3(x - px + cos(a) * 1.6, y, z - pz + sin(a) * 1.6, x, y + 0.5, z, IDX.u)
                        P.line3(x, y + 0.5, z, x + px + cos(a) * 1.6, y, z + pz + sin(a) * 1.6, IDX.u)
                    end
                end }
            end
        end
    end
end

-- Lava burning on hex `cell`: the seams between its plates flickering
-- white and pale, and smoke going up off it here and there.
local function burning(cell, list)
    local tick = floor(S.clock * 6)
    list[#list + 1] = { z = cell.z - 1.2, draw = function()
        P.eachTop(cell, function(i, j)
            local g = grain(i, j, tick)
            if g > 0.93 then P.put(IDX.w, i, j) elseif g < 0.04 then P.put(IDX.c, i, j) end
        end)
        Smoke.fire(cell.x + 3, cell.top + 1, cell.z - 2, cell.id * 5 + 3, 0.5)
    end }
end

-- A volcano, awake: its smoke going up, thick and dark when it is about to
-- erupt, or erupting; the fire in its crater flickering.
local function volcano(cell, coming, list)
    local cx, cy, cz = crater(cell)
    list[#list + 1] = { z = cell.z + 1, draw = function()
        if cell.erupting or coming then
            local w = S.world
            local i, j = w:toImage(cx, cy, cz)
            local tick = floor(S.clock * 8)
            for b = -2, 1 do
                for a = -5, 5 do
                    if grain(a, b, tick) > 0.45 then P.put(grain(b, a, tick) > 0.5 and IDX.w or IDX.c, floor(i) + a, floor(j) + b) end
                end
            end
        end
        Smoke.fire(cx, cy, cz, cell.id * 5 + 1, (cell.erupting or coming) and 2.2 or 1.1)
    end }
end

-- Everything of the sundering's on the board, onto `list` (src/ui/board.lua
-- sorts what it draws, back to front).
function QuakeFx.things(me, list)
    local g = game()
    if not g or not Cat.is(g, "quake") then return end
    local c = g.cataclysm
    riftLine(g, me, list)
    rangeLine(g, me, list)
    for _, cell in ipairs(g.cells) do
        if me.explored[cell.id] then
            if cell.lava then burning(cell, list) end
            local m = c.marks and c.marks[cell.id]
            if cell.volcano then volcano(cell, m == "erupt", list) end
            if m == "quake" then quakeComing(cell, list)
            elseif m == "wave" then waveComing(g, cell, list) end
        end
    end
    for _, p in ipairs(plays) do
        if p.seen and p.t >= 0 and p.cell then
            if p.kind == "tremor" then tremor(p, list)
            elseif p.kind == "erupt" then erupting(p, list)
            elseif p.kind == "wave" then waving(p, list)
            elseif p.kind == "sunder" then sundering(p, list)
            elseif p.kind == "uplift" then heaving(p, list) end
        end
    end
end

-- The night lit by the lava, the volcanoes about to erupt and erupting
-- (src/ui/daylight.lua asks).
function QuakeFx.lamps(w, me, out, sig)
    local g = game()
    if not g or not Cat.is(g, "quake") then return end
    local c = g.cataclysm
    for _, cell in ipairs(g.cells) do
        if me.explored[cell.id] then
            local r
            if cell.lava then r = 26
            elseif cell.volcano and (cell.erupting or (c.marks and c.marks[cell.id] == "erupt")) then r = 40
            elseif cell.volcano then r = 14 end
            if r then
                local y = cell.volcano and cell.top + 15 or cell.top
                local i, j = w:toImage(cell.x, y, cell.z)
                out[#out + 1] = { floor(i), floor(j) - 2, r }
                sig[#sig + 1] = "q" .. cell.id .. ":" .. r
            end
        end
    end
end

-- How much the ash hides the sun: some once the volcanoes wake, more while
-- one erupts.
function QuakeFx.dust(g)
    if not g or not Cat.is(g, "quake") or not Cat.past(g, "fire") then return 0 end
    for _, cell in ipairs(g.cells) do
        if cell.erupting then return 0.1 end
    end
    return 0
end

QuakeFx.marked = Quake.marked

return QuakeFx
