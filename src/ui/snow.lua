-- Snow falling: on the night side of the still sun (src/stillsun.lua), more
-- stage by stage, and over everything in the long night of the sky's
-- falling (src/skyfall.lua), as the frost comes (src/frost.lua).
--
-- As the rain is (src/ui/rain.lua), flakes are laid on the overlay over
-- everything, in the canvas's pixels, a pixel each and a few nearer ones
-- bigger, drifting down slowly and swaying with the wind from the west.
-- Under the still sun a flake only shows where the board under it lies on
-- the night side, thinning out across the twilight, so the snow stops at
-- the line. Nothing of the flakes is kept: each is found from the clock and
-- its number.

local T = require "src.tracer"
local D = require "src.defs"
local S = require "src.ui.state"
local P = require "src.ui.pixels"
local Sea = require "src.ui.sea"
local Cat = require "src.cataclysm"

local floor, sin, min, max = math.floor, math.sin, math.min, math.max
local IDX = T.IDX

local Snow = {}

-- How hard it snows in each stage, on the night side of the still sun and
-- in the sky's long night.
Snow.SUN = { still = 0.25, sear = 0.55, twilight = 0.85 }
Snow.SKY = { dark = 0.6 }
local FALL = 26    -- pixels a second, at most

local level, clock = 0, 0

local function grain(a, b, c)
    local n = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return n - floor(n)
end

-- How hard it should be snowing now.
function Snow.want(game)
    local s = game and Cat.stage(game)
    if not s then return 0 end
    if Cat.is(game, "sun") and game.cataclysm.line then return Snow.SUN[s] or 0 end
    if Cat.is(game, "sky") then return Snow.SKY[s] or 0 end
    return 0
end

function Snow.update(dt)
    clock = clock + dt
    local want = S.mode == "play" and Snow.want(S.game) or 0
    if S.plan then level = want end
    level = level + (want - level) * min(1, dt * 0.5)
    if level < 0.01 and want == 0 then level = 0 end
end

-- How much of the snow shows over canvas pixel (x, y): 1 where it falls
-- (all of it but under the still sun, its night side), 0 where not.
local function falls(x, y)
    local g, w = S.game, S.world
    if not Cat.is(g, "sun") then return 1 end
    local i, j = x + floor(S.camx), y + floor(S.camy)
    local rx = w.seaBase[1] + i * w.seaI[1] + j * w.seaJ[1]
    local rz = w.seaBase[2] + i * w.seaI[2] + j * w.seaJ[2]
    local s = D.sunSide(g, rx, rz)
    if not s then return 0 end
    local b = require("src.stillsun").band(g)
    return max(0, min(1, (-s + b * 0.5) / (b + 0.5)))
end

-- Onto the overlay, over everything else on it.
function Snow.draw()
    if level <= 0 or not S.world or not S.world.seaBase then return end
    local cw, ch = S.cw, S.ch
    local span = ch + 16
    local n = floor(level * cw * ch / 140)
    local t = clock
    -- Flakes stop with the land when the land is set still; they hang.
    if Sea.still() then t = 0 end
    for k = 1, n do
        local near = grain(k, 9, 2) > 0.92
        local speed = FALL * (0.45 + grain(k, 2, 2) * 0.55) * (near and 1.4 or 1)
        local y = ((t * speed / span + grain(k, 1, 2)) % 1) * span - 8
        local sway = sin(t * (0.8 + grain(k, 5, 2)) + k) * 2.5
        local x = (grain(k, 3, 2) * (cw + 40) - 20 + y * 0.25 + sway) % (cw + 20) - 10
        local fx, fy = floor(x), floor(y)
        if fx >= 0 and fy >= 0 and fx < cw and fy < ch and grain(k, 4, 2) < falls(fx, fy) then
            P.putS(IDX.w, fx, fy)
            if near then
                P.putS(IDX.c, fx + 1, fy)
                P.putS(IDX.c, fx, fy + 1)
                P.putS(IDX.w, fx + 1, fy + 1)
            end
        end
    end
end

-- The snow's level, 0..1, for the ambience.
function Snow.level() return level end

return Snow
