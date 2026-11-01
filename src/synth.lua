-- Every sound in the game, made from nothing: no sample files. The synth is
-- underroot's (src/sfx.lua there) by way of herding's: a sound is a few voices
-- mixed, each an oscillator (sine, triangle, a soft sine with a little of its
-- octaves, square, saw, white noise, or "grit", noise held at a pitch) with
-- its pitch swept, a low or high pass swept the same way, frequency
-- modulation, vibrato and tremolo, and an envelope that opens over `a`
-- seconds and dies away as a power curve. A sound may add an echo.
--
-- Three kinds of thing are made here:
--   DEFS    the effects: a click, a step, a clash of bronze, a city founded
--   LOOPS   the land: wind, the sea, birds, leaves, the wind on the heights,
--           each a few seconds crossfaded end into start so it has no seam
--   LAYERS  the music: forty seconds in D dorian (Dm9, Bbmaj7, F, Cadd9, ten
--           seconds each) in six layers of the very same length, so that,
--           started together, they stay in step however long they loop
--
-- Rendering needs nothing of LÖVE but love.sound for the last step (`make`),
-- so src/audiothread.lua renders them off the main thread, and the tests
-- render every one of them under plain LuaJIT (`render`).

local ffi = require "ffi"
local Rng = require "src.rng"

local floor, min, max, abs, sin, cos, exp = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.exp
local TAU = 2 * math.pi
local RATE = 22050

local Synth = { RATE = RATE }

local function midi(n) return 440 * 2 ^ ((n - 69) / 12) end
Synth.midi = midi

-- Notes by name, D dorian's and a few more, octaves 2 to 7: N.D4, N.Fs4...
local N = {}
do
    local names = { "C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B" }
    for oct = 1, 7 do
        for k, nm in ipairs(names) do N[nm .. oct] = midi(12 * (oct + 1) + k - 1) end
    end
end

--- the synth ---------------------------------------------------------------------------------

-- One voice, added into `out` (a buffer of doubles long enough for it).
local function voice(v, out, rng)
    local start = floor((v.at or 0) * RATE)
    local len = max(1, floor(v.dur * RATE))
    local f0, f1 = v.f0 or 440, v.f1 or v.f0 or 440
    local bend = v.bend or 1
    local wave = v.wave or "sine"
    local duty = v.duty or 0.5
    local a = v.a or 0.004
    local curve = v.curve or 2
    local vol = v.vol or 1
    local lp0, lp1 = v.lp and v.lp[1], v.lp and (v.lp[2] or v.lp[1])
    local hp0, hp1 = v.hp and v.hp[1], v.hp and (v.hp[2] or v.hp[1])
    local vib, fm, trem = v.vib, v.fm, v.trem
    local phase, mphase = 0, 0
    local held, last = rng:random() * 2 - 1, 0
    local l1, l2, h1 = 0, 0, 0
    -- A filter that doesn't sweep is worked out once, not every sample.
    local lpk = lp0 and lp0 == lp1 and 1 - exp(-TAU * lp0 / RATE)
    local hpk = hp0 and hp0 == hp1 and 1 - exp(-TAU * hp0 / RATE)
    for i = 0, len - 1 do
        local x = i / len
        local t = i / RATE
        local f = f0
        if f1 ~= f0 then f = f0 * (f1 / f0) ^ (x ^ bend) end
        if vib then f = f * (1 + vib[2] * sin(TAU * vib[1] * t)) end
        local pm = 0
        if fm then
            mphase = mphase + f * fm[1] / RATE
            pm = fm[2] * (fm[3] and (1 - x) or 1) * sin(TAU * mphase)
        end
        phase = phase + f / RATE
        local p = (phase + pm / TAU) % 1
        local s
        if wave == "sine" then
            s = sin(TAU * p)
        elseif wave == "tri" then
            s = 1 - 4 * abs(p - 0.5)
        elseif wave == "soft" then
            s = sin(TAU * p) * 0.8 + sin(TAU * p * 2) * 0.15 + sin(TAU * p * 3) * 0.05
        elseif wave == "square" then
            s = (p < duty and 1 - duty or -duty) * 1.4 -- zero on average, whatever the duty
        elseif wave == "saw" then
            s = (2 * p - 1) * 0.8
        elseif wave == "noise" then
            s = rng:random() * 2 - 1
        else -- "grit": noise held for a cycle of f, so it has a pitch
            if floor(phase) ~= last then last, held = floor(phase), rng:random() * 2 - 1 end
            s = held
        end
        if lp0 then
            local k = lpk or 1 - exp(-TAU * lp0 * (lp1 / lp0) ^ x / RATE)
            l1 = l1 + k * (s - l1)
            l2 = l2 + k * (l1 - l2)
            s = l2
        end
        if hp0 then
            local k = hpk or 1 - exp(-TAU * hp0 * (hp1 / hp0) ^ x / RATE)
            h1 = h1 + k * (s - h1)
            s = s - h1
        end
        local env
        if t < a then env = t / a
        else
            env = 1 - (t - a) / max(1e-4, v.dur - a)
            if curve ~= 1 then env = env ^ curve end
        end
        if trem then env = env * (1 - trem[2] * (0.5 + 0.5 * sin(TAU * trem[1] * t))) end
        local o = start + i
        out[o] = out[o] + s * env * vol
    end
end

-- How many samples a voice reaches to.
local function reach(v) return floor((v.at or 0) * RATE) + max(1, floor(v.dur * RATE)) end

-- A sound mixed into a buffer of doubles: its voices and its `gen` (a
-- function of time, for what voices can't say), an echo of four repeats if it
-- has one, then
--   `wrap` (seconds): everything past that length folded back onto the start,
--          so a layer of the music is exactly that long and loops seamlessly
--   `loop` (seconds): that much of the end crossfaded into the start, for
--          the land's loops, which are noise and would double where folded;
--          the loop is that much shorter than the sound
-- and scaled so its loudest is `gain`. Answers the buffer and its length in
-- samples.
function Synth.render(def)
    local rng = Rng.new(def.seed or 1)
    local n = def.len and floor(def.len * RATE) or 0
    for _, v in ipairs(def) do n = max(n, reach(v)) end
    local d = def.echo and floor(def.echo[1] * RATE) or 0
    local total = n + d * 4
    if def.wrap then total = max(total, floor(def.wrap * RATE)) end
    local out = ffi.new("double[?]", total + 1)
    for _, v in ipairs(def) do voice(v, out, rng) end
    if def.gen then
        local gen = def.gen()
        for i = 0, floor(def.len * RATE) - 1 do out[i] = out[i] + gen(i / RATE, rng) end
    end
    if def.echo then
        local fb = def.echo[2]
        for i = d, n + d * 4 - 1 do out[i] = out[i] + out[i - d] * fb end
        n = n + d * 4
    end
    if def.wrap then
        local w = floor(def.wrap * RATE)
        for i = w, n - 1 do out[i % w] = out[i % w] + out[i] end
        n = w
    end
    if def.loop then
        local x = floor(def.loop * RATE)
        n = n - x
        for i = 0, x - 1 do
            local f = i / x
            out[i] = out[i] * f + out[n + i] * (1 - f)
        end
    end
    local peak = 1e-6
    for i = 0, n - 1 do peak = max(peak, abs(out[i])) end
    local g = (def.gain or 0.8) / peak
    for i = 0, n - 1 do out[i] = max(-1, min(1, out[i] * g)) end
    return out, n
end

--- the kinds of note ---------------------------------------------------------------------------
--
-- Each answers a list of voices; `sound` flattens them into one def.

-- A plucked string, the lyre's: a triangle with its octave, its brightness
-- dying away faster than it does.
local function pluck(at, f, dur, vol)
    vol = vol or 1
    return {
        { at = at, dur = dur or 1, wave = "tri", f0 = f, lp = { 3200, 600 }, a = 0.002, curve = 3, vol = vol },
        { at = at, dur = (dur or 1) * 0.5, wave = "sine", f0 = f * 2, a = 0.002, curve = 3, vol = vol * 0.25 },
    }
end

-- A struck bell: a sine and the inharmonic partials of a struck bar, each
-- dying faster than the one below.
local function bell(at, f, dur, vol)
    vol = vol or 1
    return {
        { at = at, dur = dur or 1, f0 = f, a = 0.002, curve = 2.5, vol = vol },
        { at = at, dur = (dur or 1) * 0.6, f0 = f * 2.76, a = 0.002, curve = 3, vol = vol * 0.3 },
        { at = at, dur = (dur or 1) * 0.3, f0 = f * 5.4, a = 0.001, curve = 3, vol = vol * 0.12 },
    }
end

-- A knock on wood: a short sine and its fourth harmonic, gone at once.
local function wood(at, f, vol)
    vol = vol or 1
    return {
        { at = at, dur = 0.12, f0 = f, a = 0.001, curve = 4, vol = vol },
        { at = at, dur = 0.04, f0 = f * 4, a = 0.001, curve = 3, vol = vol * 0.3 },
        { at = at, dur = 0.008, wave = "noise", hp = { 2000 }, vol = vol * 0.25 },
    }
end

-- A frame drum: a low thump falling in pitch, and the slap of the skin.
local function drum(at, vol, f)
    vol, f = vol or 1, f or 95
    return {
        { at = at, dur = 0.4, f0 = f, f1 = f * 0.6, bend = 0.5, a = 0.002, curve = 2.5, vol = vol },
        { at = at, dur = 0.07, wave = "noise", lp = { 900, 300 }, vol = vol * 0.4 },
    }
end

-- A def from its playing options and any number of voices or lists of them.
local function sound(opts, ...)
    for _, part in ipairs({ ... }) do
        if part.dur then opts[#opts + 1] = part
        else for _, v in ipairs(part) do opts[#opts + 1] = v end end
    end
    return opts
end

--- the effects -------------------------------------------------------------------------------
--
-- Each: its voices, then how it is played: `vol`, `gap` (shortest time between
-- two), `poly` (most at once), `wob` (how far its pitch wanders, either way).

local DEFS = {
    --- the screen
    click = sound({ vol = 0.22, gap = 0.03 },
        { dur = 0.035, wave = "tri", f0 = 1200, f1 = 800, curve = 2 },
        { dur = 0.01, wave = "noise", hp = { 3000 }, vol = 0.3 }),
    select = sound({ vol = 0.22, gap = 0.05, wob = 0.01 }, wood(0, N.D5), wood(0.06, N.A5, 0.8)),
    city = sound({ vol = 0.25, gap = 0.1, echo = { 0.16, 0.25 } }, bell(0, N.D5, 1, 0.6), bell(0.08, N.A5, 0.9, 0.4)),
    page = sound({ vol = 0.16, gap = 0.08, wob = 0.08 },
        { dur = 0.09, wave = "noise", hp = { 1500 }, lp = { 6000, 2500 }, a = 0.01, curve = 1.5 },
        { at = 0.05, dur = 0.07, wave = "noise", hp = { 1200 }, lp = { 4000, 1500 }, a = 0.01, curve = 1.5, vol = 0.6 }),
    deny = sound({ vol = 0.25, gap = 0.15 }, wood(0, 180), wood(0.09, 160)),

    --- units at rest and on the move
    step = sound({ vol = 0.1, gap = 0.06, poly = 3, wob = 0.15 },
        { dur = 0.06, wave = "noise", lp = { 600, 200 }, curve = 2 },
        { dur = 0.05, f0 = 95, f1 = 60, curve = 2, vol = 0.6 }),
    hoof = sound({ vol = 0.12, gap = 0.06, poly = 3, wob = 0.1 },
        { dur = 0.04, wave = "tri", f0 = 330, f1 = 220, curve = 3 },
        { at = 0.07, dur = 0.04, wave = "tri", f0 = 300, f1 = 200, curve = 3, vol = 0.8 },
        { dur = 0.03, wave = "noise", lp = { 1500 }, vol = 0.5 }, { at = 0.07, dur = 0.03, wave = "noise", lp = { 1500 }, vol = 0.4 }),
    rustle = sound({ vol = 0.1, gap = 0.08, poly = 3, wob = 0.12 },
        { dur = 0.2, wave = "noise", hp = { 900 }, lp = { 5000, 1500 }, a = 0.03, trem = { 28, 0.6 }, curve = 1.5 }),
    -- An oar's stroke: the blade's wash, and the loom knocking in its pin.
    oar = sound({ vol = 0.12, gap = 0.08, poly = 3, wob = 0.12 },
        { dur = 0.28, wave = "noise", hp = { 300 }, lp = { 2200, 500 }, a = 0.05, curve = 1.6 },
        wood(0.02, 210, 0.5)),
    -- Into a boat or out of it: a thud on the planks and a splash.
    splash = sound({ vol = 0.2, gap = 0.12, poly = 2, wob = 0.1 },
        wood(0, 150, 0.8),
        { at = 0.03, dur = 0.4, wave = "noise", hp = { 400 }, lp = { 5000, 700 }, a = 0.01, curve = 2 },
        { at = 0.05, dur = 0.12, f0 = 260, f1 = 120, curve = 2, vol = 0.3 }),
    fortify = sound({ vol = 0.3, gap = 0.15 },
        { dur = 0.16, f0 = 170, f1 = 90, curve = 2.5 },
        { dur = 0.08, wave = "noise", lp = { 1000 }, vol = 0.5 },
        bell(0.02, 1240, 0.25, 0.15)),
    sleep = sound({ vol = 0.2, gap = 0.15, echo = { 0.15, 0.25 } }, pluck(0, N.A4, 0.6), pluck(0.14, N.D4, 0.9)),

    --- the land worked, the empire grown
    found = sound({ vol = 0.45, gap = 0.5, echo = { 0.18, 0.35 } },
        drum(0, 0.7),
        pluck(0, N.D4, 1.2, 0.7), pluck(0.09, N.F4, 1.2, 0.7), pluck(0.18, N.A4, 1.2, 0.7), pluck(0.27, N.D5, 1.4, 0.7),
        pluck(0.36, N.E5, 1.6, 0.6), bell(0.36, N.A5, 1.6, 0.35),
        { dur = 1.8, f0 = N.D3, a = 0.2, curve = 1.5, vol = 0.35 }),
    built = sound({ vol = 0.3, gap = 0.3, echo = { 0.12, 0.2 } },
        wood(0, 720, 0.8), wood(0.11, 960, 0.8), bell(0.22, N.E5, 0.8, 0.5)),
    dig = sound({ vol = 0.28, gap = 0.3, wob = 0.08 },
        { dur = 0.12, wave = "noise", hp = { 300 }, lp = { 2400, 700 }, curve = 1.5 },
        { at = 0.17, dur = 0.12, wave = "noise", hp = { 300 }, lp = { 2100, 600 }, curve = 1.5 },
        { at = 0.34, dur = 0.2, f0 = 130, f1 = 60, curve = 2, vol = 0.8 },
        { at = 0.34, dur = 0.1, wave = "noise", lp = { 700 }, vol = 0.5 }),
    border = sound({ vol = 0.12, gap = 0.4, echo = { 0.2, 0.3 } },
        bell(0, N.A6, 0.6, 0.4), bell(0.09, N.E6, 0.6, 0.3),
        { dur = 0.6, wave = "noise", hp = { 5000 }, a = 0.15, curve = 1.5, vol = 0.05 }),
    grow = sound({ vol = 0.25, gap = 0.3, echo = { 0.14, 0.25 } },
        pluck(0, N.D5, 0.7), pluck(0.1, N.A5, 0.8), bell(0.2, N.D6, 0.7, 0.3)),
    tech = sound({ vol = 0.4, gap = 0.6, echo = { 0.14, 0.35 } },
        pluck(0, N.D4, 1.5, 0.6), pluck(0.07, N.A4, 1.5, 0.6), pluck(0.14, N.D5, 1.5, 0.6),
        pluck(0.21, N.F5, 1.5, 0.6), pluck(0.28, N.A5, 1.6, 0.6), bell(0.35, N.E6, 1.8, 0.4),
        { at = 0.2, dur = 1, wave = "noise", hp = { 5000 }, a = 0.3, curve = 1.5, vol = 0.04 }),

    --- war
    clash = sound({ vol = 0.3, gap = 0.08, poly = 3, wob = 0.1 },
        { dur = 0.05, wave = "noise", hp = { 2000 }, curve = 1.5 },
        { dur = 0.35, f0 = 1900, curve = 3, vol = 0.35 }, { dur = 0.25, f0 = 2830, curve = 3, vol = 0.25 },
        { dur = 0.15, f0 = 4100, curve = 3, vol = 0.15 },
        { dur = 0.14, f0 = 150, f1 = 70, curve = 2, vol = 0.7 }),
    loose = sound({ vol = 0.28, gap = 0.08, poly = 3, wob = 0.08 },
        { dur = 0.14, wave = "tri", f0 = 420, f1 = 180, vib = { 40, 0.05 }, curve = 2 },
        { at = 0.03, dur = 0.3, wave = "noise", hp = { 600 }, lp = { 1200, 3500 }, a = 0.12, curve = 1.5, vol = 0.4 }),
    hit = sound({ vol = 0.3, gap = 0.06, poly = 3, wob = 0.12 },
        { dur = 0.1, wave = "noise", lp = { 1500, 300 }, curve = 1.5 },
        { dur = 0.18, f0 = 160, f1 = 55, curve = 2, vol = 0.9 }),
    stone = sound({ vol = 0.32, gap = 0.08, poly = 2, wob = 0.1 },
        { dur = 0.22, wave = "grit", f0 = 500, f1 = 120, lp = { 2000, 400 }, curve = 1.5 },
        { dur = 0.15, wave = "noise", lp = { 1200, 250 }, vol = 0.6 },
        { dur = 0.2, f0 = 110, f1 = 50, curve = 2, vol = 0.6 }),
    death = sound({ vol = 0.3, gap = 0.2, echo = { 0.2, 0.25 } },
        { dur = 0.5, f0 = 300, f1 = 70, bend = 0.6, curve = 1.5, vol = 0.7 },
        { dur = 0.3, wave = "noise", lp = { 1200, 150 }, curve = 1.5, vol = 0.5 },
        pluck(0.12, N.F4, 0.6, 0.5), pluck(0.32, N.D4, 1, 0.5)),
    --- the wild
    -- A wolf's howl: a soft voice sliding up, held, falling away; a second
    -- answering under it.
    howl = sound({ vol = 0.2, gap = 3, echo = { 0.3, 0.35 }, wob = 0.06 },
        { dur = 2.2, wave = "soft", f0 = 330, f1 = 520, bend = 0.25, a = 0.5, vib = { 5, 0.012 }, curve = 1.2 },
        { at = 1.6, dur = 1.0, wave = "soft", f0 = 500, f1 = 300, bend = 2, a = 0.05, vib = { 5, 0.012 }, curve = 1.5,
            vol = 0.6 },
        { at = 0.5, dur = 1.8, wave = "soft", f0 = 260, f1 = 410, bend = 0.3, a = 0.6, vib = { 4.5, 0.01 }, curve = 1.3,
            vol = 0.35 }),
    -- A beast going for someone: a low rasping snarl.
    growl = sound({ vol = 0.28, gap = 0.2, poly = 2, wob = 0.12 },
        { dur = 0.55, wave = "grit", f0 = 85, f1 = 70, lp = { 900, 500 }, a = 0.05, trem = { 26, 0.6 }, curve = 1.4 },
        { dur = 0.4, wave = "noise", lp = { 700, 300 }, a = 0.04, trem = { 30, 0.5 }, curve = 1.5, vol = 0.5 }),
    -- A horse's snort, or an ox's: a breath blown out hard.
    snort = sound({ vol = 0.18, gap = 1, wob = 0.15 },
        { dur = 0.32, wave = "noise", hp = { 300 }, lp = { 2500, 700 }, a = 0.02, trem = { 18, 0.4 }, curve = 1.6 },
        { dur = 0.2, wave = "grit", f0 = 120, f1 = 90, lp = { 600 }, curve = 2, vol = 0.4 }),
    -- Bees about their nest.
    buzz = sound({ vol = 0.08, gap = 2, wob = 0.1 },
        { dur = 1.4, wave = "saw", f0 = 220, f1 = 235, lp = { 1400 }, a = 0.2, vib = { 9, 0.02 }, trem = { 7, 0.4 },
            curve = 1.2 },
        { dur = 1.2, wave = "saw", f0 = 330, f1 = 318, lp = { 1600 }, a = 0.3, vib = { 11, 0.02 }, curve = 1.2,
            vol = 0.5 }),
    capture = sound({ vol = 0.25, gap = 0.3, echo = { 0.15, 0.25 } }, pluck(0, N.A3, 0.6), pluck(0.16, N.F3, 1)),
    horn = sound({ vol = 0.3, gap = 4, echo = { 0.3, 0.4 } },
        { dur = 1.5, wave = "saw", f0 = N.D3, lp = { 300, 900 }, a = 0.3, vib = { 4, 0.006 }, curve = 1.5 },
        { dur = 1.5, wave = "saw", f0 = N.A3, lp = { 300, 900 }, a = 0.35, vib = { 4.5, 0.006 }, curve = 1.5, vol = 0.6 },
        { at = 0.9, dur = 1.6, wave = "saw", f0 = N.D3, f1 = N.C3, bend = 0.3, lp = { 700, 300 }, a = 0.2, curve = 1.5, vol = 0.7 }),
    taken = sound({ vol = 0.45, gap = 1, echo = { 0.22, 0.35 } },
        drum(0, 0.8), drum(0.28, 0.6),
        { at = 0.1, dur = 1.4, wave = "saw", f0 = N.D3, lp = { 400, 1400 }, a = 0.08, curve = 1.5, vol = 0.5 },
        { at = 0.1, dur = 1.4, wave = "saw", f0 = N.A3, lp = { 400, 1400 }, a = 0.08, curve = 1.5, vol = 0.35 },
        bell(0.45, N.D5, 1.4, 0.5), bell(0.45, N.Fs5, 1.4, 0.3)),
    fallen = sound({ vol = 0.45, gap = 1, echo = { 0.25, 0.35 } },
        drum(0, 0.8, 80),
        { at = 0.05, dur = 0.9, wave = "saw", f0 = N.A3, lp = { 600 }, a = 0.1, curve = 1.2, vol = 0.4 },
        { at = 0.7, dur = 0.9, wave = "saw", f0 = N.F3, lp = { 500 }, a = 0.1, curve = 1.2, vol = 0.4 },
        { at = 1.35, dur = 1.6, wave = "saw", f0 = N.D3, lp = { 500, 200 }, a = 0.1, curve = 1.5, vol = 0.45 }),
    -- Thunder, in the storms of the deluge: a crack, then a long low roll.
    thunder = sound({ vol = 0.45, gap = 3 },
        { dur = 0.25, wave = "noise", hp = { 300 }, lp = { 4000, 900 }, a = 0.002, curve = 2 },
        { at = 0.05, dur = 3.2, wave = "noise", lp = { 260, 60 }, a = 0.08, curve = 1.2, trem = { 3.5, 0.6 } },
        { at = 0.1, dur = 2.6, f0 = 55, f1 = 38, a = 0.1, curve = 1.5, vol = 0.35 }),
    -- A stone out of the sky: the roar of it coming, then the blow, the
    -- ground thrown up and falling back; the heart of the comet's longer
    -- and lower, the earth groaning after.
    whoosh = sound({ vol = 0.3, gap = 0.1, poly = 4, wob = 0.08 },
        { dur = 0.8, wave = "noise", hp = { 200, 900 }, lp = { 700, 5000 }, a = 0.6, curve = 0.6 },
        { dur = 0.8, f0 = 300, f1 = 900, a = 0.6, curve = 0.8, vol = 0.12, vib = { 23, 0.02 } }),
    impact = sound({ vol = 0.5, gap = 0.08, poly = 4, wob = 0.1 },
        { dur = 0.06, wave = "noise", hp = { 500 }, lp = { 6000, 1500 }, a = 0.001, curve = 2 },
        { dur = 0.7, f0 = 70, f1 = 32, bend = 0.6, a = 0.003, curve = 1.8, vol = 0.9 },
        { at = 0.02, dur = 1.2, wave = "noise", lp = { 900, 120 }, a = 0.01, curve = 1.6, vol = 0.55 },
        { at = 0.3, dur = 0.6, wave = "noise", hp = { 800 }, lp = { 3000, 1200 }, a = 0.05, curve = 1.5, vol = 0.12,
            trem = { 18, 0.8 } }),
    heartfall = sound({ vol = 0.6, gap = 2 },
        { dur = 0.12, wave = "noise", hp = { 300 }, lp = { 5000, 800 }, a = 0.001, curve = 2 },
        { dur = 2.4, f0 = 52, f1 = 24, bend = 0.5, a = 0.004, curve = 1.4 },
        { at = 0.04, dur = 4, wave = "noise", lp = { 600, 50 }, a = 0.02, curve = 1.2, vol = 0.7, trem = { 2.5, 0.5 } },
        { at = 0.6, dur = 3, f0 = 38, f1 = 30, a = 0.4, curve = 1.3, vol = 0.4, vib = { 1.5, 0.05 } }),
    -- The sea freezing (src/frost.lua): a sharp crack, a ringing ping
    -- running off across the ice, and its grinding settling after.
    crack = sound({ vol = 0.35, gap = 0.2, poly = 3, wob = 0.12 },
        { dur = 0.05, wave = "noise", hp = { 2500 }, lp = { 9000, 3000 }, a = 0.001, curve = 2 },
        { dur = 0.7, f0 = 1900, f1 = 700, a = 0.002, curve = 2.4, vol = 0.22, vib = { 31, 0.01 } },
        { at = 0.04, dur = 0.5, wave = "noise", hp = { 600 }, lp = { 3000, 900 }, a = 0.01, curve = 1.8, vol = 0.3,
            trem = { 14, 0.7 } }),
    gong = sound({ vol = 0.4, gap = 2 },
        { dur = 3.5, f0 = 98, fm = { 1.41, 2.2, true }, a = 0.005, curve = 1.6 },
        { dur = 2.5, f0 = 98 * 2.76, a = 0.005, curve = 2, vol = 0.3, vib = { 3, 0.004 } },
        { dur = 1.2, wave = "noise", lp = { 900, 150 }, a = 0.01, curve = 1.5, vol = 0.3 }),

    -- The sundering's (src/quake.lua): a quake, the earth groaning low and
    -- shuddering, stones knocking in it; an eruption, a deep blast and the
    -- roar after it; a wave, the sea rushing in and breaking on the shore.
    rumble = sound({ vol = 0.55, gap = 0.6, poly = 2, wob = 0.1 },
        { dur = 2.2, wave = "noise", lp = { 220, 60 }, a = 0.15, curve = 1.3, trem = { 9, 0.7 } },
        { dur = 2.0, f0 = 46, f1 = 34, a = 0.2, curve = 1.4, vol = 0.6, vib = { 7, 0.06 } },
        { at = 0.3, dur = 1.2, wave = "grit", f0 = 140, f1 = 90, lp = { 700, 300 }, a = 0.1, curve = 1.6, vol = 0.25,
            trem = { 17, 0.9 } }),
    eruption = sound({ vol = 0.6, gap = 1.5 },
        { dur = 0.1, wave = "noise", hp = { 200 }, lp = { 4000, 700 }, a = 0.001, curve = 2 },
        { dur = 1.6, f0 = 58, f1 = 28, bend = 0.5, a = 0.004, curve = 1.5 },
        { at = 0.05, dur = 3.2, wave = "noise", lp = { 1400, 200 }, a = 0.3, curve = 1.1, vol = 0.7, trem = { 5, 0.3 } },
        { at = 0.4, dur = 2.4, wave = "grit", f0 = 90, f1 = 60, lp = { 900, 300 }, a = 0.4, curve = 1.3, vol = 0.3,
            trem = { 21, 0.8 } }),
    wave = sound({ vol = 0.5, gap = 0.4, poly = 2, wob = 0.08 },
        { dur = 1.3, wave = "noise", hp = { 100, 300 }, lp = { 400, 2600 }, bend = 0.4, a = 1.0, curve = 0.7 },
        { at = 1.1, dur = 1.6, wave = "noise", hp = { 200 }, lp = { 5000, 500 }, a = 0.01, curve = 1.6, vol = 0.9 },
        { at = 1.1, dur = 0.8, f0 = 70, f1 = 40, a = 0.005, curve = 1.8, vol = 0.5 }),

    -- The plague's (src/plague.lua): a knell for its dead, one great bell
    -- tolled low with its hum held under it; and rats, a scuttle of claws
    -- and a few thin squeaks.
    knell = sound({ vol = 0.42, gap = 1.5, echo = { 0.3, 0.3 } },
        bell(0, 146.8, 3.2, 0.8), bell(0, 146.8 * 1.19, 2.4, 0.25),
        { dur = 3.6, f0 = 73.4, a = 0.01, curve = 1.4, vol = 0.35, vib = { 2.2, 0.003 } }),
    squeak = sound({ vol = 0.16, gap = 0.4, poly = 2, wob = 0.15 },
        { dur = 0.3, wave = "noise", hp = { 2200 }, lp = { 7000, 3000 }, a = 0.01, curve = 1.2, vol = 0.5, trem = { 23, 0.9 } },
        { at = 0.05, dur = 0.06, wave = "tri", f0 = 3400, f1 = 2900, a = 0.003, curve = 1.6, vol = 0.5 },
        { at = 0.17, dur = 0.05, wave = "tri", f0 = 3900, f1 = 3300, a = 0.003, curve = 1.6, vol = 0.4 }),

    --- the turn, and the end
    turn = sound({ vol = 0.28, gap = 0.4, echo = { 0.2, 0.25 } },
        drum(0, 0.9, 85),
        { dur = 0.6, wave = "noise", lp = { 300, 1200 }, a = 0.15, curve = 1.5, vol = 0.2 },
        bell(0.22, N.A4, 1.2, 0.4), bell(0.34, N.D5, 1.4, 0.35)),
    won = sound({ vol = 0.55, gap = 2, echo = { 0.16, 0.35 } },
        drum(0, 0.6), pluck(0, N.D4, 1, 0.7), pluck(0.15, N.Fs4, 1, 0.7), pluck(0.3, N.A4, 1, 0.7),
        pluck(0.45, N.D5, 2.4, 0.7), bell(0.45, N.Fs5, 2.4, 0.4), bell(0.45, N.A5, 2.4, 0.3),
        { at = 0.45, dur = 2.4, f0 = N.D3, a = 0.1, curve = 1.5, vol = 0.5 }),
    lost = sound({ vol = 0.5, gap = 2, echo = { 0.25, 0.35 } },
        pluck(0, N.A4, 1.2, 0.7), pluck(0.4, N.F4, 1.2, 0.7), pluck(0.8, N.E4, 1.2, 0.7), pluck(1.2, N.D4, 2.6, 0.7),
        { at = 1.2, dur = 2.6, f0 = N.D2, a = 0.3, curve = 1.2, vol = 0.6 }),
}

--- the land ---------------------------------------------------------------------------------
--
-- Each a few seconds, its slow swells a whole number of turns over its length
-- so the seam does not show. A `gen` makes, once per render, the function of
-- time that adds what voices can't say.

-- A one-pole low pass for a gen: k from its cut-off.
local function onePole(hz) return 1 - exp(-TAU * hz / RATE) end

local LOOPS = {
    -- Wind over open ground: a low rush and a thin high one, swelling out of step.
    wind = sound({ len = 8, loop = 0.8, gain = 0.6, seed = 3 },
        { dur = 8.8, wave = "noise", lp = { 420 }, hp = { 70 }, a = 0.01, curve = 0, trem = { 1 / 4, 0.55 } },
        { dur = 8.8, wave = "noise", lp = { 1500 }, hp = { 700 }, a = 0.01, curve = 0, trem = { 1 / 8, 0.85 }, vol = 0.18 }),
    -- The sea on the shore: two trains of swell out of step, each wave a
    -- rush that breaks into foam.
    sea = { len = 13, loop = 1, gain = 0.6, seed = 5,
        gen = function()
            local lo, hi, lk, hk = 0, 0, onePole(380), onePole(2500)
            return function(t, rng)
                local n = rng:random() * 2 - 1
                lo = lo + lk * (n - lo)
                hi = hi + hk * (n - hi)
                local w1 = (0.5 - 0.5 * cos(TAU * t / 6)) ^ 2
                local w2 = (0.5 - 0.5 * cos(TAU * (t + 1.7) / 4)) ^ 2 * 0.7
                local swell = max(w1, w2)
                return lo * 4 * (0.3 + 0.7 * swell) + (n - hi) * 0.25 * swell ^ 3
            end
        end },
    -- Birds: a few calls, each a short run of chirps sweeping up or down, and
    -- far off a dove.
    birds = { len = 10, loop = 0.5, gain = 0.5, seed = 7,
        { dur = 10.5, wave = "noise", lp = { 2000 }, hp = { 1200 }, a = 0.01, curve = 0, vol = 0.01 },
        gen = function()
            local notes = {}
            local r = Rng.new(21)
            local t = 0.3
            while t < 9.4 do
                local f, n, dn = 2600 + r:random() * 2200, 2 + r:random(4), 0.06 + r:random() * 0.05
                local up = r:random() < 0.5
                for k = 0, n - 1 do
                    local f0 = f * (1 + 0.04 * k)
                    notes[#notes + 1] = { t = t + k * dn * 1.6, d = dn, f0 = f0, f1 = up and f0 * 1.35 or f0 * 0.7, v = 0.5 + 0.5 * r:random() }
                end
                t = t + n * dn * 1.6 + 0.6 + r:random() * 1.6
            end
            for _, at in ipairs({ 2.2, 2.75, 7.1, 7.65 }) do
                notes[#notes + 1] = { t = at, d = 0.38, f0 = 520, f1 = 470, v = 0.5, dove = true }
            end
            return function(time)
                local s = 0
                for _, c in ipairs(notes) do
                    local u = time - c.t
                    if u >= 0 and u < c.d then
                        local x = u / c.d
                        local ph = c.f0 * u + (c.f1 - c.f0) * u * u / (2 * c.d)
                        local env = c.dove and sin(math.pi * x) ^ 2 or min(1, x * 12) * (1 - x) ^ 2
                        s = s + sin(TAU * ph) * env * c.v * (c.dove and 0.8 or 0.35)
                    end
                end
                return s
            end
        end },
    -- Leaves: the hiss of a wood in the wind, coming and going.
    leaves = sound({ len = 6, loop = 0.6, gain = 0.5, seed = 9 },
        { dur = 6.6, wave = "noise", hp = { 1400 }, lp = { 5500 }, a = 0.01, curve = 0, trem = { 1 / 3, 0.75 } },
        { dur = 6.6, wave = "noise", hp = { 800 }, lp = { 2500 }, a = 0.01, curve = 0, trem = { 1 / 2, 0.8 }, vol = 0.6 }),
    -- Rain: a steady hiss on everything, and drops pattering near, a few
    -- louder on the leaves and the roofs.
    rain = { len = 6, loop = 0.5, gain = 0.55, seed = 13,
        gen = function()
            local lo, hi, lk, hk = 0, 0, onePole(2200), onePole(500)
            local drops = {}
            local r = Rng.new(31)
            for k = 1, 260 do drops[k] = { t = r:random() * 5.98, v = 0.2 + r:random() * 0.8, f = 1800 + r:random() * 2600 } end
            table.sort(drops, function(a, b) return a.t < b.t end)
            return function(t, rng)
                local n = rng:random() * 2 - 1
                lo = lo + lk * (n - lo)
                hi = hi + hk * (lo - hi)
                local s = (lo - hi) * 1.6 * (0.85 + 0.15 * sin(TAU * t / 3))
                for _, d in ipairs(drops) do
                    local u = t - d.t
                    if u >= 0 and u < 0.012 then s = s + sin(TAU * d.f * u) * (1 - u / 0.012) ^ 2 * d.v * 0.3 end
                end
                return s
            end
        end },
    -- The heights: a hollow wind with a whistle in it, rising and falling.
    heights = sound({ len = 9, loop = 0.9, gain = 0.5, seed = 11 },
        { dur = 9.9, wave = "noise", lp = { 900 }, hp = { 250 }, a = 0.01, curve = 0, trem = { 1 / 4.5, 0.7 } },
        { dur = 9.9, f0 = 620, vib = { 2 / 9, 0.12 }, a = 0.01, curve = 0, trem = { 1 / 9, 0.95 }, vol = 0.05 }),
}

--- the music ---------------------------------------------------------------------------------
--
-- Each chord: root, fifth, third, a colour (the ninth or seventh), and a note
-- on top. Ten seconds a chord, four chords, forty seconds a turn of it.

local CHORDS = {
    { 50, 57, 65, 64, 69 }, -- Dm9: D A F E A
    { 46, 53, 62, 69, 74 }, -- Bbmaj7: Bb F D A D
    { 41, 48, 57, 67, 72 }, -- Fadd9: F C A G C
    { 48, 55, 64, 62, 67 }, -- Cadd9: C G E D G
}
local BAR, LEN = 10, 40
local BEAT = BAR / 8

local function padNotes(tones, wave, vol, octave, extra)
    local list = { wrap = LEN }
    for c, ch in ipairs(CHORDS) do
        for _, k in ipairs(tones) do
            for _, dt in ipairs({ 0.997, 1.003 }) do
                local v = { at = (c - 1) * BAR, dur = BAR + 3, wave = wave, f0 = midi(ch[k] + 12 * (octave or 0)) * dt,
                    a = 2.5, curve = 1.4, vol = vol }
                for key, val in pairs(extra or {}) do v[key] = val end
                list[#list + 1] = v
            end
        end
    end
    return list
end

local LAYERS = {}
-- 0: the pad, root and fifth, breathing slowly.
LAYERS[0] = padNotes({ 1, 2 }, "soft", 0.14, 0, { trem = { 1 / 10, 0.3 } })
-- 1: strings, the third and the colour, darker.
LAYERS[1] = padNotes({ 3, 4 }, "tri", 0.06, 0, { trem = { 1 / 5, 0.3 }, lp = { 1400 } })
do -- 2: the lyre, up and down each chord, one note a beat
    local lyre = sound({ wrap = LEN, echo = { BEAT / 2, 0.3 } })
    local pattern = { 1, 2, 3, 5, 4, 3, 2, 3 }
    for c, ch in ipairs(CHORDS) do
        for s = 0, 7 do
            local n = ch[pattern[s + 1]] + 12
            sound(lyre, pluck((c - 1) * BAR + s * BEAT, midi(n), 2.2, s == 0 and 0.13 or 0.1))
        end
    end
    LAYERS[2] = lyre
end
do -- 3: a flute, slow over the top, falling home to D each time round
    local flute = { wrap = LEN, echo = { 0.45, 0.3 } }
    local melody = {
        { 81, 2 }, { 79, 1 }, { 77, 1 }, { 76, 2 }, { 74, 2 },
        { 74, 1 }, { 77, 1 }, { 81, 2 }, { 79, 2 }, { 77, 2 },
        { 76, 2 }, { 77, 1 }, { 79, 1 }, { 81, 3 }, { 0, 1 },
        { 79, 2 }, { 76, 2 }, { 74, 3 }, { 0, 1 },
    }
    local at = 0
    for _, m in ipairs(melody) do
        if m[1] > 0 then
            flute[#flute + 1] = { at = at, dur = m[2] * BEAT + 0.6, wave = "soft", f0 = midi(m[1]), vib = { 5, 0.006 },
                lp = { 2400 }, a = 0.25, curve = 1.3, vol = 0.07 }
            flute[#flute + 1] = { at = at, dur = 0.12, wave = "noise", hp = { 2500 }, lp = { 6000 }, a = 0.05, curve = 1, vol = 0.006 }
        end
        at = at + m[2] * BEAT
    end
    LAYERS[3] = flute
end
-- 4: a drone an octave under the root, swelling.
LAYERS[4] = padNotes({ 1 }, "sine", 0.16, -1, { trem = { 1 / 5, 0.4 } })
do -- 5: frame drums, for when there are enemies about: boom, tak, boom, tak
    local drums = sound({ wrap = LEN })
    for b = 0, LEN / (2 * BEAT) - 1 do
        local t = b * 2 * BEAT
        sound(drums, drum(t, 0.3, 90), drum(t + BEAT, 0.18, 110),
            { at = t + BEAT * 0.75, dur = 0.05, wave = "noise", hp = { 1500 }, lp = { 5000 }, vol = 0.06 },
            { at = t + BEAT * 1.5, dur = 0.05, wave = "noise", hp = { 1500 }, lp = { 5000 }, vol = 0.08 })
    end
    LAYERS[5] = drums
end

Synth.DEFS, Synth.LOOPS, Synth.LAYERS, Synth.LENGTH = DEFS, LOOPS, LAYERS, LEN

-- A def by its name: an effect's ("clash"), a loop's ("sea"), or a layer of
-- the music's (its number).
function Synth.def(name)
    if type(name) == "number" then return LAYERS[name] end
    return DEFS[name] or LOOPS[name]
end

-- A def rendered into SoundData, ready to play.
function Synth.make(name)
    local out, n = Synth.render(Synth.def(name))
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    local p = ffi.cast("int16_t *", data:getFFIPointer())
    for i = 0, n - 1 do p[i] = floor(out[i] * 32767 + 0.5) end
    return data
end

return Synth
