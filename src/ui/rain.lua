-- The weather of the deluge (src/flood.lua): rain, heavier stage by stage,
-- and in the floods and the rising sea a storm, with lightning and thunder.
--
-- The rain is streaks of a few pixels slanting with the wind from the west,
-- laid on the overlay over everything (as the birds are) in the canvas's
-- pixels, so it falls the same wherever the map is panned, and splashes a
-- pixel or two wide on what it falls on. On the water the board's shader
-- opens rings where the drops fall (src/ui/sea.lua, drops). How hard it is
-- falling is S.storm, 0 to 1, which the shaders also darken the sky with:
-- more of the map lies under cloud. A flash of lightning is S.flash, which
-- src/ui/daylight.lua lights the whole map with for a moment, and a bolt
-- drawn down out of the sky; its thunder follows a moment after, as far off
-- as the bolt was (src/ui/audio.lua takes it with Rain.thunder).
--
-- Nothing of the drops is kept: each is found from the clock and its number.

local T = require "src.tracer"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Sea = require "src.ui.sea"
local Cat = require "src.cataclysm"

local floor, sin, min, random = math.floor, math.sin, math.min, math.random
local IDX = T.IDX

local Rain = {}

-- How hard it rains in each stage of the deluge.
Rain.LEVEL = { omen = 0.2, rains = 0.5, floods = 0.8, sea = 1 }
-- Lightning: from this much rain on, every so often, seconds apart.
local STORM, GAP = 0.7, { 5, 13 }
local FALL = 190   -- how fast the rain falls, in pixels a second
local SLANT = 0.4  -- pixels east for each pixel down

local level, clock = 0, 0
local wait = 2.5
local bolt, thunderAt, thunderFar

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

-- How hard it should be raining now.
function Rain.want(game)
    if not game or not Cat.is(game, "flood") then return 0 end
    local s = Cat.stage(game)
    return s and Rain.LEVEL[s] or 0
end

-- A bolt from the sky to somewhere on the screen: its jagged way down, and
-- a branch off it.
local function strike()
    local x = S.cw * (0.15 + random() * 0.7)
    local ground = S.ch * (0.45 + random() * 0.4)
    local path, branch = {}, {}
    local y = -2
    while y < ground do
        path[#path + 1] = { floor(x + 0.5), floor(y + 0.5) }
        y = y + 1
        x = x + (random() - 0.5) * 2.2
        if random() < 0.08 then x = x + (random() < 0.5 and -2 or 2) end
    end
    local from = path[floor(#path * (0.3 + random() * 0.3))]
    if from then
        local bx, by, dir = from[1], from[2], random() < 0.5 and -1 or 1
        for _ = 1, floor(ground * 0.25) do
            bx, by = bx + dir * (0.4 + random() * 0.8), by + 1
            branch[#branch + 1] = { floor(bx + 0.5), floor(by + 0.5) }
        end
    end
    bolt = { path = path, branch = branch, t = 0 }
    thunderFar = random()
    thunderAt = clock + 0.3 + thunderFar * 1.6
end

function Rain.update(dt)
    clock = clock + dt
    local want = S.mode == "play" and Rain.want(S.game) or 0
    -- Pictures taken for checking start in the weather of the turn.
    if S.plan then level = want end
    level = level + (want - level) * min(1, dt * 0.6)
    if level < 0.01 and want == 0 then level = 0 end
    S.storm = level
    S.flash = 0
    if bolt then
        bolt.t = bolt.t + dt
        -- Bright, gone, bright again, fading.
        local t = bolt.t
        if t < 0.08 then S.flash = 1
        elseif t < 0.14 then S.flash = 0.2
        elseif t < 0.3 then S.flash = 0.8 * (1 - (t - 0.14) / 0.16)
        else bolt = nil end
    end
    if level >= STORM and want >= STORM and not Sea.still() then
        wait = wait - dt
        if wait <= 0 then
            strike()
            wait = GAP[1] + random() * (GAP[2] - GAP[1])
        end
    end
end

-- The thunder, once, when it is due: how loud (1 near, less far off).
function Rain.thunder()
    if thunderAt and clock >= thunderAt then
        thunderAt = nil
        return 1 - 0.6 * thunderFar
    end
end

-- The rain's sound, 0..1, for the ambience.
function Rain.level() return level end

-- The key a drop shows in over the canvas pixel: white over the dark and
-- the middling ground, dark over the lightest, so it always reads.
local function keyOver(x, y)
    local w = S.world
    local i, j = x + floor(S.camx), y + floor(S.camy)
    if i < 0 or j < 0 or i >= w.w or j >= w.h then return IDX.s end
    local v = w.px[(j * w.w + i) * 4]
    if v > 190 then return IDX.n end
    return v > 120 and IDX.w or IDX.c
end

-- Onto the overlay, over everything else on it.
function Rain.draw()
    if level <= 0 or Sea.still() or not S.world then return end
    local cw, ch = S.cw, S.ch
    local span = ch + 24
    local n = floor(level * cw * ch / 75)
    local t = clock
    for k = 1, n do
        local speed = FALL * (0.85 + grain(k, 2, 1) * 0.3)
        local y = ((t * speed / span + grain(k, 1, 1)) % 1) * span - 12
        local x = grain(k, 3, 1) * (cw + span * SLANT) - span * SLANT + y * SLANT
        local len = 4 + floor(grain(k, 4, 1) * 4)
        local key = keyOver(floor(x), floor(y))
        for i = 0, len - 1 do
            -- Broken towards its tail.
            if i < 3 or (i + k) % 3 ~= 0 then P.putS(key, floor(x - i * SLANT), floor(y - i)) end
        end
    end
    -- Splashes where it lands: a pixel thrown up either side, for a moment.
    local m = floor(level * cw * ch / 900)
    local slot = floor(t * 12)
    for k = 1, m do
        local x = floor(grain(k, slot, 5) * cw)
        local y = floor(grain(slot, k, 6) * ch)
        local key = keyOver(x, y)
        P.putS(key, x - 1, y)
        P.putS(key, x + 1, y)
        if grain(k, slot, 7) > 0.5 then P.putS(key, x, y - 1) end
    end
    if bolt and (bolt.t < 0.08 or (bolt.t > 0.14 and bolt.t < 0.26)) then
        -- The bolt: white, edged in the pale keys so it reads on the cloud.
        for _, list in ipairs({ bolt.path, bolt.branch }) do
            for _, q in ipairs(list) do
                P.putS(IDX.c, q[1] - 1, q[2])
                P.putS(IDX.c, q[1] + 1, q[2])
            end
        end
        for _, list in ipairs({ bolt.path, bolt.branch }) do
            for _, q in ipairs(list) do P.putS(IDX.w, q[1], q[2]) end
        end
    end
end

-- Test hook: the bolt falls now.
Rain.strike = function() wait = 0 end

return Rain
