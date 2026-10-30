-- The sea, moving, and the wind over the land: a shader the board's picture
-- is drawn through, that paints every pixel of open water again each frame,
-- and every pixel of land the wind or a cloud's shadow is on. The tracer
-- laid the map down still; this sets it going, and it holds to the tracer's
-- rules: each pixel is still *chosen* off the eight keys, never blended, and
-- the fog and the grid still take it down a step at a time.
--
-- What it knows of a pixel comes from the world's mask (src/world.lua,
-- World:paint): what is there (which water, or which kind of land), how far
-- the land is or how high a tree's crown stands, how many steps darker to
-- lay it, and its key. Where in the room it is it works out itself: the
-- sea's top is all at one level, and with no perspective a level is a plain
-- linear map of the picture. The land is taken as if at that level too,
-- which is near enough for a gust or a cloud.
--
-- Rumbo's sea (src/sea.lua there) taught most of what is here, done on the
-- GPU rather than with sprites:
--   * patches of rough water and of smooth, so the sea is not a wallpaper;
--   * a swell that rolls towards you, so the sea breathes rather than boils;
--   * foam fades down the palette, through holes, not through alpha.
-- And new here, the shore: sand showing through the shallows, a breaker that
-- comes in from out at sea, white where it falls, and the wash it leaves on
-- the land's edge, all at different moments along a coast.
--
-- The wind blows from the west, in gusts that roll east over the map. Where
-- one passes, the crowns of the trees and the sheaves of wheat lean a pixel
-- or two with it, by how high they stand, and the grass and the dry grass
-- show their light sides in streaks. Over the desert the heat shimmers.
-- Under all of it, land, sea and what stands on them, the shadows of clouds
-- drift the same way, a step darker in a dither.
--
-- Marks laid over water (the hexes a city works) are not printed over it
-- still, which would stop the water under them: the overlay carries them as
-- a step to lighten by (src/ui/pixels.lua, P.lift) and this applies them.
--
-- And the light of the hour (src/ui/daylight.lua) is laid on here: the sun
-- or the moon relighting each pixel, the night over it, the lamps of the
-- towns giving some back, and the moon's path on the sea. Units and the rest
-- of the overlay take the night at most a step down, so they always read;
-- buildings take it as the ground does, and their windows light up.

local T = require "src.tracer"
local D = require "src.defs"
local Settings = require "src.settings"

local Sea = {}

-- What the board's shader and the overlay's share: noise, dither, where a
-- pixel is in the room, the wind and the clouds.
local COMMON = [[
uniform Image palette;   // the eight keys, darkest first
uniform vec2 base;       // room (x, z) at the picture's corner, on the sea's level
uniform vec2 alongI;     // room (x, z) a pixel right
uniform vec2 alongJ;     // room (x, z) a pixel down
uniform float air;       // the wind's clock
uniform float weather;   // 1 for the wind and the clouds, 0 for the land still
uniform vec2 size;       // the board's picture, in pixels
uniform Image light;     // src/ui/daylight.lua's: r steps down (16ths, from 128), g a lamp's glow, b 1 to relight
uniform float lit;       // 1 while the days go round, 0 for the map as the tracer left it
uniform float exposure;  // steps the night takes off the lightest keys: 0 by day
uniform float night;     // 0 by day, 1 in the dark

const float O = 1.0, U = 2.0, N = 3.0, K = 4.0, TAN = 5.0, S = 6.0, C = 7.0, W = 8.0;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float hash(vec2 p, float k) { return hash(p + vec2(k * 17.17, k * 31.31)); }

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// An ordered dither, 0..1 over a four by four.
float bayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }

vec2 room(vec2 p) { return base + p.x * alongI + p.y * alongJ; }

vec3 key(float k) { return Texel(palette, vec2((k - 0.5) / 8.0, 0.5)).rgb; }

// A gust, 0..1: fronts that roll east, bent by a slow noise, strong in
// some places and nothing in others.
float gust(vec2 w, float t) {
    float bend = 3.0 * noise(w * 0.011 + vec2(0.0, t * 0.01));
    float front = sin(w.x * 0.034 + w.y * 0.008 - t * 0.75 + bend);
    float strength = smoothstep(0.25, 0.7, noise(w * 0.006 - vec2(t * 0.02, 0.0)));
    return smoothstep(0.35, 0.95, front) * strength;
}

// The shadows of clouds: 1 where one lies, 0 where not. Not a full step
// darker but half its pixels, and a quarter at the edge, so the land under
// them still reads.
float cloud(vec2 p, vec2 w, float t) {
    if (weather < 0.5) return 0.0;
    vec2 q = w * 0.0042 - vec2(t * 0.012, t * 0.003);
    float c = noise(q) * 0.7 + noise(q * 2.3 + 5.2) * 0.3;
    float edge = 0.66 + 0.04 * sin(t * 0.013);
    float d = bayer4(p);
    if (c > edge + 0.03) return d < 0.5 ? 1.0 : 0.0;
    if (c > edge) return d < 0.25 ? 1.0 : 0.0;
    return 0.0;
}

vec4 lightAt(vec2 p) { return Texel(light, (p + 0.5) / size); }

// The night laid on key k at p: lighter keys further down than dark ones,
// then `glow` of what it took given back by the lamps, in dithered rings.
// Never down to ink, in the dark: ink keeps the darkest key, so the
// outlines read.
float nightfall(float k, vec2 p, float glow) {
    float thr = bayer4(p);
    k = floor(k + exposure * clamp((k - 1.5) / 4.5, 0.2, 1.4) + thr);
    float lift = glow * (-exposure);
    k += floor(lift) + (thr < fract(lift) ? 1.0 : 0.0);
    return clamp(k, thr < night ? U : O, W);
}

// Key k at board pixel p, as the tracer laid it (before the fog), in the
// light of the hour: relit by the sun or the moon, then the night, and the
// lamps, laid over it.
float daylight(float k, vec2 p) {
    if (lit < 0.5) return k;
    vec4 l = lightAt(p);
    if (l.b < 0.5) return k;
    k -= (floor(l.r * 255.0 + 0.5) - 128.0) / 16.0;
    return nightfall(k, p, l.g * 1.4 + l.g * l.g * night * 0.9 / max(-exposure, 0.01));
}

// The paper map and the dark round it take the night, but no sun.
float dusk(float k, vec2 p) {
    if (lit < 0.5 || k < 1.5) return k;
    return nightfall(k, p, 0.0);
}
]]

local SOURCE = COMMON .. [[
uniform Image mask;      // r what (1 ocean, 2 coast, 3.. land), g land's distance x4 or height x16, b steps darker, a key
uniform Image overlay;   // the board's overlay: alpha 1..3 marks steps lighter
uniform vec2 overlaySize;
uniform float time;      // the sea's clock
uniform float moonX;     // the canvas's column under the moon

const float CROWN = 3.0, SHEAF = 4.0, GRASS = 5.0, PLAINS = 6.0, DESERT = 8.0;

float what(vec4 m) { return floor(m.r * 255.0 + 0.5); }
float keyOf(vec4 m) { return floor(m.a * 255.0 + 0.5); }
bool sways(float kind) { return kind == CROWN || kind == SHEAF; }
vec4 at(vec2 p) { return Texel(mask, (p + 0.5) / size); }

// How many pixels east a swaying pixel at p leans: more the higher above
// its ground, and a little to and fro even in the lull.
float lean(vec2 p, vec4 m, float t) {
    float h = m.g * 255.0 / 16.0;
    float reach = what(m) == CROWN ? clamp((h - 2.5) / 5.0, 0.0, 1.3) : clamp(h / 4.0, 0.0, 0.9);
    vec2 w = room(p);
    float sway = 1.7 * gust(w, t) + 0.5 * sin(t * 1.9 + 6.283 * noise(w * 0.035)) - 0.1;
    return clamp(floor(reach * sway + 0.5), -1.0, 2.0);
}

// The long swell, rolling towards you and a little east, its crests bent by
// a slow noise so no two are ruled straight.
float swell(vec2 w, float t) {
    float warp = 2.4 * noise(w * 0.02 + vec2(t * 0.012, 0.0));
    return sin(dot(w, vec2(0.287, 0.958)) * 0.224 - t * 0.85 + warp);
}

// Rough water and smooth, in patches that wander.
float rough(vec2 w, float t) {
    return noise(w * 0.013 + vec2(-t * 0.006, t * 0.004));
}

vec3 sea(vec4 m, vec2 p, vec2 w, vec2 sc) {
    float kind = what(m);
    float shore = m.g * 255.0 / 4.0;
    float dark = floor(m.b * 255.0 + 0.5);
    float t = time;
    bool deep = kind < 1.5;
    float water = deep ? U : N;
    float k = water;

    float sw = swell(w, t);
    float ro = rough(w, t);
    // The swell's troughs, a step darker in a thin dither, where the sea is up.
    if (sw < -0.8 && ro > 0.3 && bayer4(p) < (sw < -0.93 ? 0.375 : 0.1875)) k = water - 1.0;
    // Far out the sea is deeper: its troughs wider.
    if (deep && shore > 40.0 && sw < -0.35 && ro > 0.45 && bayer4(p) < 0.25) k = O;

    // A glint: a pixel of the sun, for a moment, on a high swell.
    if (sw > 0.6 && hash(p, floor(t * 2.0 + hash(p) * 7.0)) > 0.997) k = deep ? S : C;

    if (!deep) {
        // The shore breathes, a little in and out.
        float d = shore + 0.35 * sin(t * 0.6 + w.x * 0.07 + w.y * 0.05);
        // Sand showing through the shallows, thinner going out.
        if (d < 5.0 && bayer4(p) < (5.0 - d) / 9.0) k = max(k, K);

        // Breakers: each comes in from seven units out and falls on the shore,
        // at its own moment along the coast.
        float ph = t / 3.6 + 1.8 * noise(w * 0.045) + w.x * 0.012;
        float age = fract(ph);
        float front = (1.0 - age) * 7.5;
        float lace = noise(w * vec2(0.85, 1.25) + vec2(t * 0.35, t * 0.12));
        float lace2 = noise(w * 1.7 - vec2(t * 0.2, 0.0));
        float off = d - front;
        if (abs(off) < 0.55 && lace > 0.15 + 0.45 * front / 7.5) {
            // Swelling far out, breaking nearer, white where it falls.
            k = front > 3.2 ? max(k, TAN) : (front > 1.2 ? C : W);
        } else if (off > 0.0 && front < 3.2 && off < 0.6 + 2.0 * age && lace2 > 0.5 + 0.2 * off) {
            // What it leaves behind it, going to holes.
            k = off < 1.2 ? C : S;
        }
        // The wash: thrown up the shore as the wave falls, then drawn back.
        float wash = 0.7 + 1.6 * pow(1.0 - age, 3.0);
        if (d < wash && lace2 > 0.2 + 0.5 * d / wash) k = d < 0.6 || age < 0.2 ? W : C;
    }

    // The overlay's marks: steps lighter.
    vec4 o = Texel(overlay, sc / overlaySize);
    if (o.a > 0.0 && o.a < 0.5) k += floor(o.a * 255.0 + 0.5);

    k = daylight(k, p);
    // The moon on the sea: a broken path of glints under it that shimmer.
    if (lit > 0.5 && night > 0.3 && dark < 0.5) {
        float off = (sc.x - moonX) / 30.0;
        float path = exp(-off * off);
        if (hash(vec2(floor(p.x / 2.0), p.y), floor(t * 5.0)) > 1.0 - 0.22 * path * night) k = path > 0.6 ? W : S;
    }

    k = clamp(k - dark - cloud(p, w, air), 1.0, 8.0);
    return key(k);
}

// Key k at p, darkened `dark` steps by the fog and the grid, in the light of
// the hour: the light is laid on the key under the fog, and the fog again
// after.
float lightLand(float k, float dark, vec2 p) {
    if (lit < 0.5) return k;
    return clamp(daylight(k + dark, p) - dark, 1.0, 8.0);
}

vec3 land(vec4 m, vec2 p, vec2 w) {
    float kind = what(m);
    float t = air;
    float k = keyOf(m);
    float dark = floor(m.b * 255.0 + 0.5);
    if (weather < 0.5) return key(lightLand(k, dark, p));
    float from = kind;
    // Whatever leans onto this pixel, from the west or from the east.
    bool covered = false;
    for (int n = 0; n < 3; n++) {
        float d = n == 0 ? 1.0 : (n == 1 ? 2.0 : -1.0);
        vec4 o = at(p - vec2(d, 0.0));
        if (sways(what(o)) && lean(p - vec2(d, 0.0), o, t) == d) {
            k = keyOf(o);
            from = what(o);
            covered = true;
            break;
        }
    }
    // Leaned off: what is behind it, taken from the side it left.
    if (!covered && sways(kind)) {
        float d = lean(p, m, t);
        if (d != 0.0) {
            for (int n = 1; n <= 3; n++) {
                vec4 o = at(p - vec2(sign(d) * float(n), 0.0));
                if (!sways(what(o)) && what(o) > 0.5) { k = keyOf(o); from = what(o); break; }
            }
        }
    }
    // Heat over the sand, stronger in patches that wander: its rows wave a
    // pixel to and fro, and bands of glare a step lighter rise through it.
    if (!covered && kind == DESERT) {
        float heat = 0.4 + 0.6 * smoothstep(0.4, 0.7, noise(w * 0.018 + vec2(t * 0.04, -t * 0.02)));
        float wave = sin(p.y * 0.9 - t * 4.0 + 6.0 * noise(w * 0.05));
        float d = floor(wave * heat * 1.4 + 0.5);
        vec4 o = at(p - vec2(d, 0.0));
        if (d != 0.0 && what(o) == DESERT) k = keyOf(o);
        float band = fract((p.y + t * 5.0 + 4.0 * noise(w * 0.04)) / 9.0);
        if (band < 0.2 * heat && bayer4(p) < 0.25 * heat) k += 1.0;
    }
    float g = gust(w, t);
    if (from == CROWN && g > 0.45 && k > U && hash(p, floor(t * 5.0 + hash(p) * 3.0)) > 0.9) {
        // Leaves turned over by the gust, a glint of their light side.
        k += 1.0;
    } else if ((from == GRASS || from == PLAINS) && g > 0.3) {
        // The grass laid over in streaks that run with the wind.
        float streak = noise(w * vec2(0.05, 0.4) - vec2(t * 0.9, 0.0));
        if (streak * g > 0.42 && bayer4(p + vec2(floor(t * 3.0), 0.0)) < 0.25) k += 1.0;
    }
    k = clamp(lightLand(k, dark, p) - cloud(p, w, t), 1.0, 8.0);
    return key(k);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 m = Texel(mask, tc);
    float kind = what(m);
    vec2 p = floor(tc * size);
    if (kind < 0.5) {
        if (lit < 0.5) return Texel(tex, tc) * color;
        return vec4(key(dusk(keyOf(m), p)), 1.0) * color;
    }
    vec2 w = room(p + 0.5);
    vec3 c = kind < 2.5 ? sea(m, p, w, sc) : land(m, p, w);
    return vec4(c, 1.0) * color;
}
]]

-- The overlay drawn over the board: only the pixels it covers, not the marks
-- it leaves for the sea to lighten; and what stands there under the clouds
-- too, a step darker. At night it goes down at most a step, and the lamps
-- light it; but a building (alpha P.WALL) takes the night as the ground does
-- and half the lamps' glow, and its windows (alpha P.LAMP) light up one by
-- one as it gets dark.
local COVER = COMMON .. [[
uniform vec2 cam;        // the board picture's pixel at the canvas's corner

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 px = Texel(tex, tc);
    if (px.a < 0.9) discard;
    bool window = px.a < 0.984, wall = px.a < 0.995;
    vec2 p = floor(sc) + cam;
    float shade = cloud(p, room(p + 0.5), air);
    if (shade < 0.5 && lit < 0.5) return vec4(px.rgb, 1.0) * color;
    // Which key it is, to go down or up from.
    float k = 1.0, best = 9.0;
    for (int n = 1; n <= 8; n++) {
        vec3 d = key(float(n)) - px.rgb;
        float e = dot(d, d);
        if (e < best) { best = e; k = float(n); }
    }
    k = max(1.0, k - shade);
    if (lit > 0.5 && k > 1.5) {
        float glow = lightAt(p).g;
        if (wall) {
            // A building: the night as on the ground, half the lamps' glow,
            // so its lit windows show.
            k = nightfall(k, p, glow * 0.7);
            if (window && night * 1.2 - 0.1 > hash(p, 4.0)) k = W;
        } else {
            // Anyone else: at most a step down, so they always read.
            float e = max(exposure * 0.5, -1.0);
            k = clamp(floor(k + e - e * glow * 1.5 + bayer4(p)), 1.0, 8.0);
        }
    }
    return vec4(key(k), 1.0) * color;
}
]]

local time, air = 0, 0

local function still() return Settings.get("landMotion") == false end

-- Compiles the shaders. If the graphics can't, the board is drawn as the
-- tracer left it, still.
function Sea.load()
    local ok, shader = pcall(love.graphics.newShader, SOURCE)
    if not ok then
        print("sea: no moving water: " .. tostring(shader))
        return
    end
    local ok2, cover = pcall(love.graphics.newShader, COVER)
    if not ok2 then
        print("sea: no moving water: " .. tostring(cover))
        return
    end
    Sea.shader, Sea.cover = shader, cover
    local data = love.image.newImageData(8, 1, "rgba8")
    for k, c in ipairs(T.RGB) do data:setPixel(k - 1, 0, c[1], c[2], c[3], 1) end
    Sea.palette = love.graphics.newImage(data)
    Sea.palette:setFilter("nearest", "nearest")
    shader:send("palette", Sea.palette)
    cover:send("palette", Sea.palette)
end

function Sea.update(dt)
    -- Kept short, so the GPU's floats hold their fraction; the jump back is
    -- once an hour.
    if Settings.get("seaMotion") ~= false then time = (time + dt) % 3600 end
    if not still() then air = (air + dt) % 3600 end
end

-- Sets the shader going for world `w` drawn at the canvas's (x, y), with the
-- overlay `overlay` (an image the canvas's size) over it, the board picture's
-- pixel (camx, camy) at the canvas's corner. Answers whether it did: if not,
-- draw as usual. The overlay is then drawn through Sea.cover.
function Sea.begin(w, overlay, camx, camy)
    local sh = Sea.shader
    if not sh then return false end
    if not w.seaBase then
        local level = D.TERRAIN.ocean.top
        local x0, z0 = T.onLevel(w.i0, w.j0, level)
        local x1, z1 = T.onLevel(w.i0 + 1, w.j0, level)
        local x2, z2 = T.onLevel(w.i0, w.j0 + 1, level)
        w.seaBase = { x0, z0 }
        w.seaI = { x1 - x0, z1 - z0 }
        w.seaJ = { x2 - x0, z2 - z0 }
    end
    local weather = still() and 0 or 1
    for _, s in ipairs({ sh, Sea.cover }) do
        s:send("base", w.seaBase)
        s:send("alongI", w.seaI)
        s:send("alongJ", w.seaJ)
        s:send("air", air)
        s:send("weather", weather)
    end
    sh:send("mask", w.maskImage)
    for _, s in ipairs({ sh, Sea.cover }) do
        if s:hasUniform("size") then s:send("size", { w.w, w.h }) end
    end
    sh:send("overlay", overlay)
    sh:send("overlaySize", { overlay:getWidth(), overlay:getHeight() })
    sh:send("time", time)
    Sea.cover:send("cam", { camx, camy })
    love.graphics.setShader(sh)
    return true
end

-- The shaders' source, for checking them outside the game.
Sea.SOURCE, Sea.COVER = SOURCE, COVER

Sea.time = function() return time end
-- The wind's clock, stopped when the land is set still.
Sea.air = function() return air end
Sea.still = still

return Sea
