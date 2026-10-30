-- The clock: what hour of the day it is, in the corner under the top bar, as
-- the light on the map (src/ui/daylight.lua) has it. It eases on with the
-- light as a turn ends, so the sun climbs and sinks across it while the map
-- brightens and darkens.
--
-- Four looks, a setting:
--
--   arc    the sun's path as a dotted arch over a horizon; the sun walks it
--          by day and the moon by night, under a sky that darkens
--   dial   a round face that turns, day half light and night half dark,
--          under a fixed pointer, a tick for each turn of the day
--   strip  a day's sky as a ribbon in the top bar, sliding under a marker,
--          the sun at each noon and the moon at each midnight
--   scene  a little window: hills, a town and the sea, the sun rising from
--          behind the hills and setting again, stars and lit windows at night
--
-- Still only the eight keys: the sky's shades between them are dithered.

local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Font = require "src.font"
local Daylight = require "src.ui.daylight"
local Settings = require "src.settings"

local floor, max, min, sin, cos, pi, atan2 = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.atan2
local rect, text = Draw.rect, Draw.text

local Clock = {}

-- `--clock look`: the look for pictures, whatever the setting.
Clock.force = nil

local KEYS = { "o", "u", "n", "k", "t", "s", "c", "w" }

local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local function bayer(x, y) return (BAYER[(y % 4) * 4 + x % 4 + 1] + 0.5) / 16 end

-- The key for a level between the keys (0 ink .. 7 white), dithered at x, y.
local function key(level, x, y)
    level = min(7, max(0, level))
    local b = floor(level)
    if level - b > bayer(x, y) then b = b + 1 end
    return KEYS[min(8, b + 1)]
end

local function plot(k, x, y) rect(k, x, y, 1, 1) end

-- A little picture from rows of characters, each a key (or "." for none).
local function sprite(rows, x, y)
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local k = row:sub(c, c)
            if k ~= "." then plot(k, x + c - 1, y + r - 1) end
        end
    end
end

-- The sun is ringed a little darker than the day sky, so it reads on it.
local SUN = { ".nnn.", "nwwwn", "nwwwn", "nwwwn", ".nnn." }
local SUN_SMALL = { ".n.", "nwn", ".n." }
local MOON = { ".cc..", "cc...", "c....", "cc...", ".cc.." }
local MOON_SMALL = { "cc", "c.", "cc" }
local SUN_BIG = { "..nnn..", ".nwwwn.", "nwwwwwn", "nwwwwwn", "nwwwwwn", ".nwwwn.", "..nnn.." }

-- What each turn's hour is called.
function Clock.name(t)
    t = t % 1
    if t < 0.15 or t >= 0.88 then return "MIDNIGHT" end
    if t < 0.27 then return "DAWN" end
    if t < 0.38 then return "MORNING" end
    if t < 0.5 then return "LATE MORNING" end
    if t < 0.62 then return "NOON" end
    if t < 0.7 then return "AFTERNOON" end
    if t < 0.755 then return "SUNSET" end
    return "DUSK"
end

function Clock.day()
    return floor((S.game.turn - 1) / #Daylight.HOURS) + 1
end

-- The sky at hour t, h up from the horizon (0) to the top (1), as a level.
local function sky(t, h)
    local L = Daylight.at(t)
    local day = 1 - L.night
    local top = 1.1 + 3.4 * day - 0.6 * L.golden
    local low = top + 0.5 * day + 1.6 * L.golden
    return top + (low - top) * (1 - h)
end

-- How dark it is, 0 by day .. 1 in the night.
local function dark(t) return Daylight.at(t).night end

-- A fixed scatter of stars over a box, shown as the night comes.
local function stars(x, y, w, h, night, keep)
    if night < 0.4 then return end
    local n = floor(w * h / 40)
    for s = 1, n do
        local px = (s * 37 + s * s * 11) % w
        local py = (s * 23 + s * s * 7) % h
        local tw = sin(S.clock * 1.3 + s * 2.1) > -0.7
        if (s % 5) / 5 < (night - 0.4) / 0.6 and tw and (not keep or keep(px, py)) then
            plot(s % 3 == 0 and "w" or "c", x + px, y + py)
        end
    end
end

-- A label in a dark band.
local function label(s, x, y, w)
    text("c", s, x + floor((w - Font.width(s)) / 2), y)
end

local function panel(x, y, w, h)
    rect("o", x, y, w, h)
    S.panels[#S.panels + 1] = { x = x, y = y, w = w, h = h }
end

--- arc ----------------------------------------------------------------------------

local function arc(right, top, t)
    local w, h = 58, 36
    local x, y = right - w, top
    panel(x, y, w, h)
    local ix, iy, iw, ih = x + 1, y + 1, w - 2, 24
    local night = dark(t)
    for py = 0, ih - 1 do
        for px = 0, iw - 1 do
            plot(key(sky(t, 1 - py / (ih - 1)) - 0.4, px, py), ix + px, iy + py)
        end
    end
    stars(ix, iy, iw, ih - 4, night)
    -- The horizon, and the path the sun takes over it, dotted.
    local cx, hy, R = ix + floor(iw / 2), iy + ih - 3, 21
    rect(night > 0.5 and "n" or "t", ix, hy + 1, iw, ih - (hy + 1 - iy))
    rect("o", ix, hy, iw, 1)
    for k = 0, 40 do
        local a = k / 40 * pi
        if k % 3 == 0 then
            plot(night > 0.5 and "k" or "n", floor(cx - R * cos(a) + 0.5), floor(hy - R * 0.85 * sin(a) + 0.5))
        end
    end
    -- The sun by day, the moon by night: each on the arch from left to right.
    local function on(p, rows)
        if p < 0 or p > 1 then return end
        local a, o = p * pi, floor(#rows / 2)
        local sx, sy = floor(cx - R * cos(a) + 0.5) - o, floor(hy - R * 0.85 * sin(a) + 0.5) - o
        for r, row in ipairs(rows) do
            for c = 1, #row do
                local k = row:sub(c, c)
                if k ~= "." and sy + r - 1 < hy then plot(k, sx + c - 1, sy + r - 1) end
            end
        end
    end
    on((t % 1 - 0.25) / 0.5, SUN_BIG)
    on(((t % 1 - 0.75) % 1) / 0.5, MOON)
    label(Clock.name(t), x, y + 27, w)
end

--- dial ---------------------------------------------------------------------------

local function dial(right, top, t)
    local R = 13
    local d = R * 2 + 1
    local name, day = Clock.name(t), "DAY " .. Clock.day()
    local tw = max(Font.width(name), Font.width(day))
    local w, h = d + tw + 10, d + 6
    local x, y = right - w, top
    panel(x, y, w, h)
    local cx, cy = right - R - 4, y + 4 + R
    -- The face: each pixel the hour it stands for, the hour now at the top,
    -- the day going round clockwise.
    for py = -R, R do
        for px = -R, R do
            local r2 = px * px + py * py
            if r2 <= R * R then
                local k
                if r2 > (R - 1) * (R - 1) then
                    k = "n"
                else
                    local a = atan2(px, -py) / (2 * pi)
                    local hr = t - a * 0.5
                    k = key(sky(hr, 0.6) - 0.3, px, py)
                end
                plot(k, cx + px, cy + py)
            end
        end
    end
    -- A tick for each turn of the day, ink on the rim.
    for _, hr in ipairs(Daylight.HOURS) do
        local a = (t - hr) / 0.5 * pi
        plot("o", floor(cx + (R - 1) * sin(a) + 0.5), floor(cy - (R - 1) * cos(a) + 0.5))
    end
    -- Noon's sun and midnight's moon, going round with it.
    local a = (t - 0.5) / 0.5 * pi
    sprite(SUN, floor(cx + (R - 6) * sin(a) + 0.5) - 2, floor(cy - (R - 6) * cos(a) + 0.5) - 2)
    local b = a + pi
    sprite(MOON, floor(cx + (R - 6) * sin(b) + 0.5) - 2, floor(cy - (R - 6) * cos(b) + 0.5) - 2)
    -- The pointer, fixed at the top.
    rect("w", cx, cy - R - 2, 1, 4)
    rect("w", cx - 1, cy - R - 2, 3, 1)
    rect("o", cx, cy, 1, 1)
    text("w", name, x + 4, cy - 6)
    text("s", day, x + 4, cy + 2)
end

--- strip --------------------------------------------------------------------------

-- In the top bar, ending at `right`; answers where it begins.
local function strip(right, top, t)
    local w, h = 81, 7
    local x, y = right - w, top
    rect("o", x - 1, y - 1, w + 2, h + 2)
    local half = floor(w / 2)
    for px = 0, w - 1 do
        local hr = t + (px - half) / w
        for py = 0, h - 1 do
            plot(key(sky(hr, 1 - py / (h - 1)) - 0.3, px, py), x + px, y + py)
        end
    end
    -- The turns, as ticks along the bottom.
    for _, th in ipairs(Daylight.HOURS) do
        for k = -1, 1 do
            local px = floor(half + (floor(t) + k + th % 1 - t) * w + 0.5)
            if px >= 0 and px < w then plot("o", x + px, y + h - 1) end
        end
    end
    -- The sun at each noon in view and the moon at each midnight.
    for k = -1, 1 do
        local sx = floor(x + half + (floor(t) + k + 0.5 - t) * w + 0.5)
        if sx - 1 >= x and sx + 1 < x + w then sprite(SUN_SMALL, sx - 1, y + 2) end
        local mx = floor(x + half + (floor(t) + k - t) * w + 0.5)
        if mx >= x and mx + 1 < x + w then sprite(MOON_SMALL, mx, y + 2) end
    end
    -- The marker, at now.
    rect("w", x + half, y - 1, 1, 2)
    rect("w", x + half, y + h - 1, 1, 2)
    local name = Clock.name(t)
    text("c", name, x - Font.width(name) - 5, y + 1)
    return x - Font.width(name) - 5
end
Clock.strip = strip

--- scene --------------------------------------------------------------------------

local function scene(right, top, t)
    local w, h = 64, 44
    local x, y = right - w, top
    panel(x, y, w, h)
    local ix, iy, iw, ih = x + 2, y + 2, w - 4, 31
    local night = dark(t)
    local sea = iy + ih - 7
    local function hill(px)
        local u = px / iw
        return floor(sea - 2 - 6 * max(0, 1 - ((u - 0.2) / 0.2) ^ 2) - 4 * max(0, 1 - ((u - 0.85) / 0.2) ^ 2)
            - 1.5 * max(0, sin(u * pi * 5)))
    end
    -- The sky, then the sun or moon on a wide arch whose foot is behind the
    -- hills, so it comes up out of them and goes down into them.
    for py = iy, sea - 1 do
        for px = 0, iw - 1 do
            plot(key(sky(t, 1 - (py - iy) / (sea - iy)), px, py), ix + px, py)
        end
    end
    stars(ix, iy, iw, sea - iy - 6, night)
    local cx, base, R = ix + floor(iw / 2), sea - 3, 26
    local function body(p, rows)
        if p < 0 or p > 1 then return nil end
        local a, o = p * pi, floor(#rows / 2)
        local sx, sy = floor(cx - (R - 1) * cos(a) + 0.5), floor(base - (base - iy - 3) * sin(a) + 0.5)
        sprite(rows, sx - o, sy - o)
        -- Only what stands over the sea lays glints on it.
        return sy < hill(sx - ix) - 1 and sx or nil
    end
    local sunX = body((t % 1 - 0.25) / 0.5, SUN_BIG)
    local moonX = body(((t % 1 - 0.75) % 1) / 0.5, MOON)
    -- The hills, darker as the night comes, with a town on the higher one.
    local hk = 2.6 - 1.6 * night
    for px = 0, iw - 1 do
        local top = hill(px)
        for py = top, sea - 1 do plot(key(hk - (py - top) * 0.05, px, py), ix + px, py) end
        plot("o", ix + px, top)
    end
    local tx = ix + 11
    local ty = hill(11) - 1
    local town = {
        "....o.....",
        "...ooo..o.",
        ".o.ooo.ooo",
        "oooooooooo",
    }
    sprite(town, tx - 4, ty - 3)
    if night > 0.45 then
        plot("w", tx - 1, ty - 1)
        plot("c", tx + 3, ty - 1)
        if night > 0.7 then plot("w", tx, ty - 2) end
    end
    -- The sea, with a path of glints under the sun or moon.
    for py = sea, iy + ih - 1 do
        for px = 0, iw - 1 do
            local k = key(1.6 + 1.6 * (1 - night) - (py - sea) * 0.12, px, py)
            local gx = sunX or moonX
            if gx and math.abs(ix + px - gx) <= 1 + (py - sea) * 0.4 and (px * px * 5 + py * 31 + floor(S.clock * 3)) % 4 == 0 then
                k = sunX and "w" or "c"
            end
            plot(k, ix + px, py)
        end
    end
    Draw.frame("n", ix - 1, iy - 1, iw + 2, ih + 2)
    local s = Clock.name(t) .. "  DAY " .. Clock.day()
    label(s, x, y + h - 8, w)
end

--- which ----------------------------------------------------------------------------

function Clock.look()
    return Clock.force or Settings.get("clock") or "arc"
end

-- Under the top bar, at the right (left of the touch buttons on a touch
-- screen). The strip is drawn in the top bar itself, by Clock.inBar.
function Clock.draw(right)
    if not S.game then return end
    local look, t = Clock.look(), Daylight.now()
    if look == "arc" then arc(right, 13, t)
    elseif look == "dial" then dial(right, 13, t)
    elseif look == "scene" then scene(right, 13, t)
    end
end

-- The strip, in the top bar ending at `right`: answers where the bar's text
-- to its left must end, or `right` if it isn't shown.
function Clock.inBar(right)
    if Clock.look() ~= "strip" or not S.game then return right end
    return strip(right, 2, Daylight.now()) - 4
end

return Clock
