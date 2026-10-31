-- Day and night. Each turn is played at an hour of the day, and when a turn
-- ends the light goes on to the next in a couple of seconds: the sun crosses
-- from the east in the morning to the west at evening, its shadows long at
-- either end, then the dusk, a night with a moon in it and lamps lit in the
-- towns, and a dawn.
--
-- It keeps the tracer's rules. No pixel is blended or tinted: the light only
-- says how many steps up or down the eight keys a pixel goes, and a step is
-- never more than whole pixels, dithered as the clouds are. So:
--
--   * The sun relights the map off each pixel's normal (src/world.lua keeps
--     them, World:shape): the ramp level it lays against the level the
--     tracer's own lamp laid, and the pixel moves by the difference.
--   * Its shadows are found by walking from each pixel towards it over how
--     near everything is: anything nearer the camera on the way stands in
--     front of the sun.
--   * Low, it gilds what faces it a step lighter.
--   * The night is a few steps darker, more for light keys than for dark
--     ones so the dark still has steps in it, and never down to ink: ink
--     keeps the darkest key to itself, so every outline still reads. A moon
--     from the other side keeps the shapes, at half strength.
--   * Lamps give back what the night took round each town, in dithered
--     rings, its windows and doors are lit one by one (src/models.lua marks
--     them, src/ui/pixels.lua lays them as P.LAMP), and the moon leaves a
--     broken path of glints on the sea under it.
--
-- All that is worked out on the GPU into a picture the map's size, the light,
-- drawn again only when the hour or the map or the towns change: red how
-- many steps the sun or moon lays a pixel down, green a lamp's glow, blue 1
-- where the pixel may be relit. The board's shader and the overlay's
-- (src/ui/sea.lua) lay the night and the lamps on from it each frame.

local T = require "src.tracer"
local S = require "src.ui.state"
local Settings = require "src.settings"

local sin, cos, sqrt, max, min, floor, pi = math.sin, math.cos, math.sqrt, math.max, math.min, math.floor, math.pi

local Daylight = {}

-- The hour each turn of a day is played at, as a part of the day (0
-- midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset): mostly daylight, a turn at
-- sunset, at dusk, at midnight and at dawn. Past 1 is the next day, so the
-- clock only ever goes forward.
Daylight.HOURS = require("src.defs").HOURS

-- How long the light takes to go on to the next turn's hour, in seconds.
local CHANGE = 2.4

-- The hour turn `turn` is played at, counting whole days.
function Daylight.hourOf(turn)
    local n = turn - 1
    local hours = Daylight.HOURS
    return floor(n / #hours) + hours[n % #hours + 1]
end

local function unit(x, y, z)
    local n = sqrt(x * x + y * y + z * z)
    return x / n, y / n, z / n
end

local function smooth(a, b, x)
    x = min(max((x - a) / (b - a), 0), 1)
    return x * x * (3 - 2 * x)
end

-- The way to the sun at hour t, and how high it stands (-1 under your feet at
-- midnight, 1 overhead). It rises in the east, passes high in the south
-- (behind the camera, as the tracer's lamp is) and sets in the west.
function Daylight.sun(t)
    local ph = (t % 1 - 0.25) / 0.5 * pi
    local el = sin(ph)
    local up = max(el, 0)
    local x, y, z = unit(cos(ph), up * 1.15 + 0.06, 0.12 + 0.38 * up)
    return x, y, z, el
end

-- The moon: from the upper right, against the afternoon sun.
local MOON = { unit(0.55, 0.9, 0.25) }

-- The way half between a light and the camera, for glints.
local function half(x, y, z) return { unit(x, y + T.SE, z + T.CE) } end

-- What the light is at hour t:
--   exposure  steps the night takes off the lightest keys (0 by day, -2.3)
--   night     0 by day, 1 in the dark: how much of the moon, the lamps
--   golden    1 with the sun low: how much it gilds what faces it
function Daylight.at(t)
    local x, y, z, el = Daylight.sun(t)
    return {
        sun = { x, y, z }, el = el,
        exposure = -2.3 * (1 - smooth(-0.35, 0.18, el)),
        night = 1 - smooth(-0.3, 0.05, el),
        golden = smooth(-0.12, 0.05, el) * (1 - smooth(0.12, 0.45, el)),
    }
end

-- The light picture's shader, run over the world's shape picture.
local LIGHT = [[
uniform Image near;      // how near: r, g in 32nds from -64, high byte first; a 0 where nothing
uniform vec2 size;       // the picture, in pixels
uniform vec3 lamp0;      // the tracer's lamp, and half way from it to the camera
uniform vec3 half0;
uniform vec3 sun;
uniform vec3 sunHalf;
uniform vec3 moon;
uniform vec3 moonHalf;
uniform float sunUp;     // the sun's height, -1..1
uniform float night;
uniform float golden;
uniform vec2 march;      // a step towards the sun, in pixels of the picture
uniform float rise;      // and how much nearer the camera that comes
uniform float reach;     // how many steps to look

float bayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }

// The ramp level (1 glint .. 4 shadow) a normal is laid at by a light, as
// T.shade lays it.
float level(vec3 n, vec3 l, vec3 h) {
    float d = dot(n, l);
    float g = dot(n, h);
    if (g > 0.0 && pow(g, 40.0) > 0.6) return 1.0;
    if (d > 0.78) return 2.0;
    if (d > 0.2) return 3.0;
    if (n.y < 0.0 && d > 0.02) return 3.0;
    return 4.0;
}

float nearAt(vec2 q) {
    vec4 d = Texel(near, (q + 0.5) / size);
    if (d.a < 0.5) return -1e6;
    return (floor(d.r * 255.0 + 0.5) * 256.0 + floor(d.g * 255.0 + 0.5)) / 32.0 - 64.0;
}

// Is anything between picture pixel p and the sun?
bool shaded(vec2 p) {
    float d0 = nearAt(p);
    for (int s = 1; s < 200; s++) {
        float f = float(s);
        if (f > reach) break;
        vec2 q = floor(p + march * f + 0.5);
        if (q.x < 0.0 || q.y < 0.0 || q.x >= size.x || q.y >= size.y) break;
        float gap = nearAt(q) - (d0 + rise * f);
        if (gap > 1.0 && gap < 30.0) return true;
    }
    return false;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 shape = Texel(tex, tc);
    // Ink, and nothing: left as they are.
    if (shape.a < 0.5) return vec4(128.0 / 255.0, 0.0, 0.0, 1.0);
    vec2 p = floor(tc * size);
    vec3 n = shape.rgb * 2.0 - 1.0;
    float thr = bayer4(p);
    float was = level(n, lamp0, half0);
    float down = 0.0;
    if (sunUp > -0.05) {
        float lv = level(n, sun, sunHalf);
        // A step at most either way: the sky still lights what the sun
        // has turned from.
        down = clamp(lv - was, -1.0, 1.0);
        // In a shadow: a step further down, if the sun was on it.
        if (sunUp > 0.02 && lv < 4.0 && shaded(p)) down = min(down + 1.0, 2.0);
        // The low sun gilds what faces it.
        if (lv <= 2.0 && thr < golden * 0.9) down -= 1.0;
    }
    // The moon, on as many pixels as it is dark.
    if (thr < night) down = clamp(level(n, moon, moonHalf) - was, -1.0, 2.0) * 0.6;
    return vec4((floor(down * 16.0 + 0.5) + 128.0) / 255.0, 0.0, 1.0, 1.0);
}
]]

-- A lamp's glow, drawn into the light's green over a box round it.
local POOL = [[
uniform vec3 lamp;       // its picture pixel and how far it reaches across

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 d = (floor(sc) + 0.5 - lamp.xy) / vec2(lamp.z, lamp.z * 0.62);
    return vec4(0.0, clamp(1.0 - length(d), 0.0, 1.0), 0.0, 1.0);
}
]]
Daylight.LIGHT, Daylight.POOL = LIGHT, POOL

local function on() return Settings.get("dayNight") ~= false end
Daylight.on = on

-- Sends a uniform if the shader has it (one the compiler dropped can't be).
local function send(sh, name, ...)
    if sh:hasUniform(name) then sh:send(name, ...) end
end

function Daylight.load()
    local ok, light = pcall(love.graphics.newShader, LIGHT)
    if not ok then
        print("daylight: no day and night: " .. tostring(light))
        return
    end
    local ok2, pool = pcall(love.graphics.newShader, POOL)
    if not ok2 then
        print("daylight: no day and night: " .. tostring(pool))
        return
    end
    Daylight.light, Daylight.pool = light, pool
    -- The glows of two towns that meet: the brighter of them, if the
    -- graphics can say so; added if not.
    Daylight.blend = love.graphics.getSupported().lighten and "lighten" or "add"
end

--- the clock ------------------------------------------------------------------

local now, from, goal, since, game = 0, 0, 0, 0, nil
-- `--hour h`: every turn at h o'clock, for pictures.
Daylight.force = nil

function Daylight.update(dt)
    local g = S.game
    if not g then return end
    local target = Daylight.force or Daylight.hourOf(g.turn)
    if g ~= game or S.plan then
        game, now, from, goal, since = g, target, target, target, CHANGE
    elseif target ~= goal then
        from, goal, since = now, target, 0
    end
    since = since + dt * (Settings.get("animSpeed") or 1)
    local f = min(1, since / CHANGE)
    now = from + (goal - from) * f * f * (3 - 2 * f)
end

-- The hour it is now, part of a day (0 midnight).
function Daylight.now() return now % 1 end

--- the light picture --------------------------------------------------------------

-- The lamps: a town the player knows of, at its picture pixel, reaching
-- further the bigger it is.
function Daylight.lamps(w)
    local g = S.game
    local me = g.players[1]
    local list, sig = {}, {}
    for _, c in ipairs(g.cities) do
        local cell = g.cells[c.cell]
        if me.explored[cell.id] then
            local i, j = w:toImage(cell.x, cell.top, cell.z)
            local r = 22 + 3 * min(c.pop, 8) + (c.capital and 8 or 0)
            list[#list + 1] = { floor(i), floor(j) - 4, r }
            sig[#sig + 1] = c.cell .. ":" .. r
        end
    end
    -- A wildfire lights the night round it as a town does.
    for _, cell in ipairs(g.cells) do
        if cell.fire and me.explored[cell.id] then
            local i, j = w:toImage(cell.x, cell.top, cell.z)
            local r = cell.feature == "forest" and 34 or 26
            list[#list + 1] = { floor(i), floor(j) - 4, r }
            sig[#sig + 1] = "f" .. cell.id
        end
    end
    return list, table.concat(sig, ",")
end

-- Everything the light shader is sent for hour t.
function Daylight.uniforms(t)
    local a = Daylight.at(t)
    local L = a.sun
    -- A step towards the sun: a pixel along whichever way it moves most.
    local di = L[1] / T.UNIT
    local dj = -(L[2] * T.CE - L[3] * T.SE) / T.UNIT
    local dd = L[2] * T.SE + L[3] * T.CE
    local step = 1 / max(math.abs(di), math.abs(dj), 1e-6)
    return {
        lamp0 = T.LAMP, half0 = T.HALF,
        sun = L, sunHalf = half(L[1], L[2], L[3]),
        moon = MOON, moonHalf = half(MOON[1], MOON[2], MOON[3]),
        sunUp = a.el, night = a.night, golden = a.golden,
        march = { di * step, dj * step }, rise = dd * step,
        reach = 60 + 120 * (1 - min(max(a.el, 0), 1)),
    }
end

local canvas, drawn

-- Draws the light picture for world `w`, if anything it shows has changed.
function Daylight.draw(w)
    if not Daylight.light or not on() or not w.shapeImage then return end
    if not canvas or canvas:getWidth() ~= w.w or canvas:getHeight() ~= w.h then
        canvas = love.graphics.newCanvas(w.w, w.h)
        canvas:setFilter("nearest", "nearest")
        drawn = nil
    end
    local lamps, sig = Daylight.lamps(w)
    local t = floor(now * 4000 + 0.5) / 4000
    local what = table.concat({ t, tostring(w), w.version or 0, sig }, "|")
    if what == drawn then return end
    drawn = what

    local sh = Daylight.light
    for name, v in pairs(Daylight.uniforms(t)) do send(sh, name, v) end
    send(sh, "near", w.nearImage)
    send(sh, "size", { w.w, w.h })
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.setBlendMode("replace")
    love.graphics.setColor(1, 1, 1)
    love.graphics.setShader(sh)
    love.graphics.draw(w.shapeImage, 0, 0)
    if #lamps > 0 then
        love.graphics.setShader(Daylight.pool)
        love.graphics.setColorMask(false, true, false, false)
        love.graphics.setBlendMode(Daylight.blend, "premultiplied")
        for _, l in ipairs(lamps) do
            Daylight.pool:send("lamp", l)
            love.graphics.rectangle("fill", l[1] - l[3], l[2] - l[3], l[3] * 2, l[3] * 2)
        end
        love.graphics.setColorMask(true, true, true, true)
    end
    love.graphics.pop()
end

-- Sends the board's shader and the overlay's what they lay the light on
-- with. The board picture is `cw` pixels across the canvas.
function Daylight.apply(board, cover, cw)
    local lit = Daylight.light and on() and canvas ~= nil
    local a = Daylight.at(now)
    -- The storm of the deluge lights the lamps a little, and its lightning
    -- lights everything for a moment (src/ui/rain.lua).
    local storm, flash = S.storm or 0, S.flash or 0
    local exposure = a.exposure + 2.2 * flash
    local night = max(a.night, storm * 0.28) * (1 - flash)
    for _, sh in ipairs({ board, cover }) do
        send(sh, "lit", lit and 1 or 0)
        if lit then
            send(sh, "light", canvas)
            send(sh, "exposure", exposure)
            send(sh, "night", night)
        end
    end
    if lit then send(board, "moonX", floor(cw * 0.62)) end
end

return Daylight
