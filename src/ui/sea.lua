-- The sea, moving: a shader the board's picture is drawn through, that
-- paints every pixel of open water again each frame. The tracer laid the
-- sea down still; this sets it going, and it holds to the tracer's rules:
-- each pixel is still *chosen* off the eight keys, never blended, and the
-- fog and the grid still take it down a step at a time.
--
-- What it knows of a pixel comes from the world's sea picture (src/world.lua,
-- World:paint): which water it is, how far the land is, and how many steps
-- darker to lay it. Where in the room it is it works out itself: the sea's
-- top is all at one level, and with no perspective a level is a plain linear
-- map of the picture.
--
-- Rumbo's sea (src/sea.lua there) taught most of what is here, done on the
-- GPU rather than with sprites:
--   * the field is mostly short ripples a shade off the water, and only a few
--     strokes stand up as waves, with a shadow under them, or break white;
--   * patches of rough water and of smooth, so the sea is not a wallpaper;
--   * the strokes come in trains on a swell that rolls towards you, so the
--     sea breathes rather than boils;
--   * a stroke is born, grows, drifts a few pixels and shrinks away, each on
--     its own clock, so nothing ticks in step;
--   * foam fades down the palette, through holes, not through alpha.
-- And new here, the shore: sand showing through the shallows, a breaker that
-- comes in from out at sea, white where it falls, and the wash it leaves on
-- the land's edge, all at different moments along a coast.
--
-- Marks laid over water (the hexes a city works) are not printed over it
-- still, which would stop the water under them: the overlay carries them as
-- a step to lighten by (src/ui/pixels.lua, P.lift) and this applies them.

local T = require "src.tracer"
local D = require "src.defs"
local Settings = require "src.settings"

local Sea = {}

local SOURCE = [[
uniform Image seaMask;   // r which water (1 ocean, 2 coast), g land's distance x4, b steps darker
uniform Image palette;   // the eight keys, darkest first
uniform Image overlay;   // the board's overlay: alpha 1..3 marks steps lighter
uniform vec2 overlaySize;
uniform vec2 size;       // the picture, in pixels
uniform vec2 base;       // room (x, z) at the picture's corner, on the sea's level
uniform vec2 alongI;     // room (x, z) a pixel right
uniform vec2 alongJ;     // room (x, z) a pixel down
uniform float time;

const float O = 1.0, U = 2.0, N = 3.0, K = 4.0, TAN = 5.0, S = 6.0, C = 7.0, W = 8.0;
const float CW = 20.0, CH = 6.0;   // the cells strokes are dealt into, in pixels

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

// The stroke over pixel p, if any: how big it is (1 a ripple, 2 a wave, 3 a
// crest about to break; a half less at its ends) or -1 for the shadow under a
// wave. Each cell of the grid holds one stroke at a time; a stroke drifts
// down three pixels in its life, so a pixel asks its own row and the one
// above. `still`: how calm the water may be at the calmest.
float stroke(vec2 p, float t, float still) {
    float row = floor(p.y / CH);
    float best = 0.0;
    for (int n = 0; n < 2; n++) {
        float r = row - float(n);
        float shift = floor(hash(vec2(r, 3.7)) * CW);
        float col = floor((p.x + shift) / CW);
        vec2 c = vec2(col, r);
        float life = 2.6 + 2.4 * hash(c);
        float ph = t / life + hash(c, 1.0);
        float gen = floor(ph);
        float u = fract(ph);
        vec2 g = c + vec2(gen * 7.13, gen * 3.71);
        float left = col * CW - shift;
        vec2 w = room(vec2(left + CW * 0.5, r * CH + CH * 0.5));
        float sw = swell(w, t);
        float ro = max(still, rough(w, t));
        // More of them, and bigger, on the swell's crests and in rough water.
        float crest = smoothstep(-0.4, 0.9, sw);
        if (hash(g, 2.0) > (0.12 + 0.8 * ro) * (0.25 + 0.75 * crest)) continue;
        float grade = pow(ro, 1.4) * (0.35 + 0.65 * crest) * (0.45 + 0.55 * hash(g, 3.0));
        float big = grade > 0.36 ? 3.0 : (grade > 0.16 ? 2.0 : 1.0);
        float most = big == 1.0 ? 4.0 + 5.0 * hash(g, 5.0) : 2.0 + 5.0 * big + 5.0 * hash(g, 5.0);
        float len = floor(most * sin(3.14159 * u) + 0.5);
        float xc = left + most * 0.5 + hash(g, 4.0) * (CW - most);
        float y = r * CH + floor(hash(g, 6.0) * (CH - 2.0)) + floor(u * 3.0);
        float dx = abs(p.x + 0.5 - xc);
        if (p.y == y && dx < len * 0.5) {
            float k = (dx < len * 0.5 - 1.5 || big == 1.0) ? big : big - 0.5;
            best = max(best, k);
        } else if (p.y == y + 1.0 && big > 1.0 && dx < len * 0.5 - 1.0 && best == 0.0) {
            best = -1.0;
        }
    }
    return best;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 m = Texel(seaMask, tc);
    float kind = floor(m.r * 255.0 + 0.5);
    if (kind < 0.5) return Texel(tex, tc) * color;
    float shore = m.g * 255.0 / 4.0;
    float dark = floor(m.b * 255.0 + 0.5);

    vec2 p = floor(tc * size);
    vec2 w = room(p + 0.5);
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

    // The shallows are never quite still.
    float s = stroke(p, t, deep ? 0.0 : 0.4);
    if (s > 0.0) {
        k = water + ceil(s);
        if (fract(s) > 0.0) k -= 1.0;
        // A crest about to break, now and then, shows white.
        if (s == 3.0 && ro > 0.6 && hash(floor(p / 3.0), floor(t * 1.5)) > 0.7) k = deep ? C : W;
    } else if (s < 0.0) {
        k = water - 1.0;
    }

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

    k = clamp(k - dark, 1.0, 8.0);
    return vec4(Texel(palette, vec2((k - 0.5) / 8.0, 0.5)).rgb, 1.0) * color;
}
]]

-- The overlay drawn over the board: only the pixels it covers, not the marks
-- it leaves for the sea to lighten.
local COVER = [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 p = Texel(tex, tc);
    if (p.a < 0.99) discard;
    return p * color;
}
]]

local time = 0

-- Compiles the shaders. If the graphics can't, the board is drawn as the
-- tracer left it, the sea still.
function Sea.load()
    local ok, shader = pcall(love.graphics.newShader, SOURCE)
    if not ok then
        print("sea: no moving water: " .. tostring(shader))
        return
    end
    local ok2, cover = pcall(love.graphics.newShader, COVER)
    if not ok2 then return end
    Sea.shader, Sea.cover = shader, cover
    local data = love.image.newImageData(8, 1, "rgba8")
    for k, c in ipairs(T.RGB) do data:setPixel(k - 1, 0, c[1], c[2], c[3], 1) end
    Sea.palette = love.graphics.newImage(data)
    Sea.palette:setFilter("nearest", "nearest")
    shader:send("palette", Sea.palette)
end

function Sea.update(dt)
    -- Kept short, so the GPU's floats hold their fraction; the jump back is
    -- once an hour.
    if Settings.get("seaMotion") ~= false then time = (time + dt) % 3600 end
end

-- Sets the shader going for world `w` drawn at the canvas's (x, y), with the
-- overlay `overlay` (an image the canvas's size) over it. Answers whether
-- it did: if not, draw as usual.
function Sea.begin(w, overlay)
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
    sh:send("seaMask", w.seaImage)
    sh:send("size", { w.w, w.h })
    sh:send("base", w.seaBase)
    sh:send("alongI", w.seaI)
    sh:send("alongJ", w.seaJ)
    sh:send("overlay", overlay)
    sh:send("overlaySize", { overlay:getWidth(), overlay:getHeight() })
    sh:send("time", time)
    love.graphics.setShader(sh)
    return true
end

Sea.time = function() return time end

return Sea
