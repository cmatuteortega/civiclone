-- The sound's glue to the screen (the sounds themselves are src/synth.lua,
-- rendered by src/audiothread.lua): what the game did, heard from where on
-- the screen it happened; the land under the camera; the music.
--
-- The effects. The rules put what happened on `game.events`; as the screen
-- takes each off (src/ui/anim.lua) it is heard here, panned to its hex and
-- quieter off the edge, and only if the player can see that hex. A blow
-- lands when the lunge does. The news of a turn (a unit trained, a city
-- grown, a border pushed out, a technology learned) comes one item after
-- another, not all at once.
--
-- The land. Every half second a few dozen points of the screen are looked
-- at: the more of it is sea, the louder the waves; forest, the leaves; hills
-- and mountains, the wind on the heights; open ground, birds. Wind under it all.
--
-- The music. Forty seconds in six layers, all started together so they stay
-- in step, each faded in as the empire earns it:
--   0 the pad                  always
--   1 strings                  a first city
--   2 the lyre                 a second city, or turn 12
--   3 a flute                  two technologies, or turn 30
--   4 a low drone              a third city, or turn 50
--   5 frame drums              enemy soldiers in sight near home (and a horn
--                              as they first appear)
-- Every few minutes the music draws back for a while and lets the land be
-- heard.
--
-- How loud each is comes from the settings (src/settings.lua): a master
-- volume over the music, the land and the effects, each its own. V goes the
-- master round loud, soft and off.

local D = require "src.defs"
local Synth = require "src.synth"
local S = require "src.ui.state"
local Settings = require "src.settings"
local Rain = require "src.ui.rain"

local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt

local Audio = { on = false }

-- How loud a kind of sound is ("music", "ambience" or "effects"), 0..1,
-- master and all.
local function level(kind)
    return Settings.get("master") / 100 * Settings.get(kind) / 100
end
-- How loud each layer of the music is when it is in.
local MIX = { [0] = 0.32, 0.26, 0.24, 0.2, 0.28, 0.32 }
-- The cycle the music breathes on: in for so long, then back for a while.
local PLAYS, RESTS = 160, 45

local pools, loops, layers = {}, {}, {}
local last, later, news = {}, {}, {}
local clock, musicAt, newsAt = 0, nil, 0
local jobs, done
local land, threat, hornAt = { wind = 0.2 }, false, -1e9
local was = {}

--- starting and stopping -----------------------------------------------------------

-- Gets ready to make every sound: nothing at all if there's no audio device.
-- The music first, so the title has it soonest, then the land, then the rest.
function Audio.init()
    if not (love.audio and love.sound and love.thread) then return false end
    local ok = pcall(function()
        love.audio.setDistanceModel("none")
        love.audio.newSource(love.sound.newSoundData(1, Synth.RATE, 16, 1), "static")
    end)
    if not ok then return false end
    jobs, done = love.thread.getChannel("synth.jobs"), love.thread.getChannel("synth.done")
    jobs:clear()
    done:clear()
    for k = 0, #Synth.LAYERS do layers[k] = { vol = 0 }; jobs:push(k) end
    local names = {}
    for name in pairs(Synth.LOOPS) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do loops[name] = { vol = 0 }; jobs:push(name) end
    names = {}
    for name in pairs(Synth.DEFS) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do pools[name] = { def = Synth.DEFS[name] }; jobs:push(name) end
    love.thread.newThread("src/audiothread.lua"):start()
    Audio.on = true
    return true
end

-- Quitting: the worker is told to stop.
function Audio.stop()
    if jobs then jobs:clear(); jobs:push("quit") end
end

-- What the worker has finished, made into sources.
local function collect()
    local job = done:pop()
    while job do
        local src = love.audio.newSource(job.data, "static")
        if type(job.name) == "number" then
            src:setLooping(true)
            src:setVolume(0)
            layers[job.name].src = src
        elseif loops[job.name] then
            src:setLooping(true)
            src:setVolume(0)
            loops[job.name].src = src
        else
            pools[job.name].srcs, pools[job.name].next = { src }, 1
        end
        job = done:pop()
    end
end

--- playing -------------------------------------------------------------------------

-- Plays effect `name`: `pan` from -1 (left) to 1 (right), `vol` 0..1, `pitch`
-- a factor. Not rendered yet: silence beats a stall.
function Audio.play(name, pan, vol, pitch)
    if not Audio.on or Audio.away or level("effects") <= 0 then return end
    local p = pools[name]
    if not p or not p.srcs then return end
    local def = p.def
    if last[name] and clock - last[name] < (def.gap or 0.03) then return end
    last[name] = clock
    -- A free source from the pool, or a new one up to `poly`, or the oldest.
    local src
    for _, s in ipairs(p.srcs) do
        if not s:isPlaying() then src = s break end
    end
    if not src then
        if #p.srcs < (def.poly or 2) then
            src = p.srcs[1]:clone()
            p.srcs[#p.srcs + 1] = src
        else
            src = p.srcs[p.next]
            p.next = p.next % #p.srcs + 1
            src:stop()
        end
    end
    local wob = def.wob or 0.03
    src:setPitch((pitch or 1) * (1 + (love.math.random() * 2 - 1) * wob))
    src:setVolume(max(0, min(1, (def.vol or 0.5) * (vol or 1) * level("effects"))))
    pan = max(-1, min(1, pan or 0)) * 0.7
    src:setPosition(pan, 0, -sqrt(1 - pan * pan))
    src:play()
end

-- Where on the screen hex `id` is, as a pan, and how loud for being there:
-- a third as loud off the edge.
local function where(id)
    local cell = S.game.cells[id]
    if not (cell and S.world and S.cw) then return 0, 1 end
    local i, j = S.world:toImage(cell.x, cell.top, cell.z)
    local sx, sy = (i - S.camx) / S.cw, (j - S.camy) / S.ch
    local off = sx < -0.05 or sx > 1.05 or sy < -0.05 or sy > 1.05
    return sx * 2 - 1, off and 0.35 or 1
end

-- Effect `name` from hex `id`, after `delay` seconds.
local function at(name, id, vol, delay, pitch)
    later[#later + 1] = { t = clock + (delay or 0), name = name, id = id, vol = vol or 1, pitch = pitch }
end

local function seen(id) return S.game.players[1].visible[id] end

-- Effect `name` from hex `id`, after `delay` seconds: for what plays its own
-- events back (src/ui/sky.lua's stones, heard as they land).
function Audio.at(name, id, vol, delay, pitch) at(name, id, vol, delay, pitch) end

-- Effect `name` from hex `id`, if the player can see it: for what the board
-- sees happen (a wolf howling, a horse snorting).
function Audio.call(name, id, vol)
    if not Audio.on or not seen(id) then return end
    at(name, id, vol or 1)
end

--- what happened -------------------------------------------------------------------

local ranged -- whether the attack the hits being heard belong to was a shot
local LUNGE, FLIGHT = 0.15, 0.3

-- The news of a turn, kept to a few: one turn's news is stale by the next's.
local function tell(name, id)
    if #news < 4 then news[#news + 1] = { name = name, id = id } end
end

-- One event off the game's list (src/ui/anim.lua hands each over).
function Audio.hear(game, e)
    if not Audio.on then return end
    local k = e.kind
    if k == "attack" then
        ranged = e.ranged
        if seen(e.from) or seen(e.to) then
            if ranged then at("loose", e.from) else at("clash", e.to, 1, LUNGE) end
            if e.unit and e.unit.owner == game.WILD then at("growl", e.from, 1) end
        end
    elseif k == "hit" then
        if seen(e.cell) then at(e.unit and "hit" or "stone", e.cell, 1, ranged and FLIGHT or LUNGE) end
    elseif k == "death" then
        if seen(e.cell) then at("death", e.cell, e.unit.owner == 1 and 1 or 0.6, 0.35) end
    elseif k == "capture" then
        if seen(e.cell) then at("capture", e.cell) end
    elseif k == "found" then
        if e.city.owner == 1 then at("found", e.cell)
        elseif seen(e.cell) then at("found", e.cell, 0.4) end
    elseif k == "conquer" then
        if e.city.owner == 1 then at("taken", e.cell)
        elseif e.from == 1 then at("fallen", e.cell)
        elseif seen(e.cell) then at("taken", e.cell, 0.4, 0, 0.9) end
    elseif k == "freeze" and e.cell then
        -- The sea freezing over.
        if seen(e.cell) then at("crack", e.cell, 0.7) end
    elseif k == "flood" and e.cell then
        -- A river over its banks.
        if seen(e.cell) then at("splash", e.cell, 0.7, 0, 0.6) end
    elseif k == "rift" or k == "citadel" or k == "abyss" or k == "razed" then
        -- The ground torn open (src/demons.lua), heard wherever it is.
        at("stone", e.cell, k == "rift" and 0.7 or 1, 0, 0.5)
        if k ~= "rift" then at("gong", nil, 0.8, 0.2, 0.6) end
    elseif k == "rise" or k == "sink" then
        if seen(e.cell) then at("splash", e.cell, 0.9, 0, 0.5) end
    elseif k == "devour" then
        if seen(e.cell) then at("fallen", e.cell, 0.6, 0, 0.7) end
    elseif k == "eliminated" or k == "heat" or k == "flood" or k == "sky" or k == "demons" or k == "sun" then
        -- A civilization gone, or the cataclysm come a stage nearer.
        at("gong")
    elseif k == "embark" or k == "land" then
        if seen(e.cell) then at("splash", e.cell, e.unit.owner == 1 and 1 or 0.6) end
    elseif k == "improve" then
        if seen(e.cell) then at("dig", e.cell) end
    -- The news of the turn, one after another.
    elseif k == "built" then
        local city = game.cells[e.cell].city
        if city and city.owner == 1 then tell("built", e.cell) end
    elseif k == "grow" then
        if e.city.owner == 1 then tell("grow", e.cell) end
    elseif k == "border" then
        if game.cells[e.cell].owner == 1 then tell("border", e.cell) end
    elseif k == "tech" then
        if e.player == 1 then tell("tech") end
    end
end

-- A unit come onto a new hex: a footstep, a hoof, or leaves brushed past.
function Audio.step(u, cell)
    if not Audio.on or not seen(cell.id) then return end
    local hooves = u.kind == "horseman" or u.kind == "horse" or u.kind == "aurochs"
    local name = hooves and "hoof" or (cell.feature == "forest" and "rustle" or "step")
    if S.game:isWater(cell) or u.def.sea then name = "oar" end
    at(name, cell.id, u.owner == 1 and 1 or 0.6)
end

-- A unit wading into a river: a splash.
function Audio.ford(u, cell)
    if not Audio.on or not seen(cell.id) then return end
    at("splash", cell.id, u.owner == 1 and 0.8 or 0.5)
end

--- each frame ------------------------------------------------------------------------

-- What the camera is over: how much of the screen is sea, forest, high
-- ground and open ground, of what has been explored.
local function survey()
    local p = S.game.players[1]
    local water, forest, high, open = 0, 0, 0, 0
    local cols, rows = 7, 5
    for a = 0, cols - 1 do
        for b = 0, rows - 1 do
            local cell = S.world:pick(S.camx + S.cw * (a + 0.5) / cols, S.camy + S.ch * (b + 0.5) / rows)
            if cell and p.explored[cell.id] then
                if D.TERRAIN[cell.terrain].water then water = water + 1
                elseif cell.elev ~= "flat" then high = high + 1
                elseif cell.feature == "forest" then forest = forest + 1
                else open = open + 1 end
            end
        end
    end
    local n = cols * rows
    water, forest, high, open = water / n, forest / n, high / n, open / n
    return {
        wind = 0.14 + 0.18 * (open + high),
        sea = 0.5 * water ^ 0.6,
        leaves = 0.4 * forest ^ 0.7,
        heights = 0.4 * high ^ 0.8,
        birds = 0.32 * min(1, (open + forest) * 1.6) * (1 - Rain.level() * 0.8),
        rain = 0.5 * Rain.level(),
    }
end

-- Enemy soldiers the player can see on their land or near one of their cities.
local function danger(game)
    local vis, cities = game.players[1].visible, game:citiesOf(1)
    for _, u in ipairs(game.units) do
        if u.owner ~= 1 and not u.def.civilian and vis[u.cell]
            and (u.owner ~= game.WILD or u.def.temper == "hostile") then
            local cell = game.cells[u.cell]
            if cell.owner == 1 then return true end
            for _, c in ipairs(cities) do
                if game:dist(cell, game.cells[c.cell]) <= 4 then return true end
            end
        end
    end
    return false
end

-- Which layers of the music the empire has earned.
local function earned(game)
    local cities, techs = #game:citiesOf(1), 0
    for _ in pairs(game.players[1].techs) do techs = techs + 1 end
    return {
        [0] = true,
        cities >= 1,
        cities >= 2 or game.turn >= 12,
        techs >= 2 or game.turn >= 30,
        cities >= 3 or game.turn >= 50,
        threat,
    }
end

-- Sounds for what the player did on the screen: chose a unit or city, opened
-- or closed a panel, came to the end.
local function watch()
    local sel = S.selected and (S.selected.unit or S.selected.city)
    if sel ~= was.sel and sel then
        if S.selected.city then Audio.play("city")
        else Audio.play("select", 0, 1, sel.def.civilian and 0.84 or 1) end
    end
    if S.panel ~= was.panel then Audio.play("page") end
    if S.over and not was.over then Audio.play(S.over.result == "won" and "won" or "lost") end
    was.sel, was.panel, was.over = sel, S.panel, S.over
end

local tick = 0
function Audio.update(dt)
    clock = clock + dt
    if not Audio.on then return end
    collect()
    if Audio.away then return end
    local playing = S.mode == "play" and S.game and S.world
    if playing then
        watch()
        -- What is due, on time.
        for k = #later, 1, -1 do
            local l = later[k]
            if clock >= l.t then
                table.remove(later, k)
                local pan, vol = 0, 1
                if l.id then pan, vol = where(l.id) end
                Audio.play(l.name, pan, vol * l.vol, l.pitch)
            end
        end
        if news[1] and clock >= newsAt then
            local n = table.remove(news, 1)
            Audio.play(n.name, n.id and (where(n.id)) or 0)
            newsAt = clock + 0.55
        end
        tick = tick - dt
        if tick <= 0 then
            tick = 0.5
            land = survey()
            local now = danger(S.game)
            if now and not threat and clock - hornAt > 90 then
                Audio.play("horn")
                hornAt = clock
            end
            threat = now
        end
        local loud = Rain.thunder()
        if loud then Audio.play("thunder", 0, loud, 0.85 + 0.3 * math.random()) end
    else
        later, news, threat = {}, {}, false
        land = { wind = 0.2, birds = 0.14, sea = 0.12 }
    end

    -- The land: each loop eases to where it should be; silent ones stop.
    for name, l in pairs(loops) do
        local want = (land[name] or 0) * level("ambience")
        l.vol = l.vol + (want - l.vol) * min(1, dt * 1.2)
        if l.src then
            if l.vol < 0.002 and want == 0 then
                if l.src:isPlaying() then l.src:stop() end
                l.vol = 0
            else
                if not l.src:isPlaying() then l.src:play() end
                l.src:setVolume(l.vol)
            end
        end
    end

    -- The music, once every layer is ready: all started together.
    for k = 0, #layers do if not layers[k].src then return end end
    if not musicAt then
        musicAt = clock
        for k = 0, #layers do layers[k].src:play() end
    end
    local on = playing and earned(S.game) or { [0] = true, true, true, true }
    local breath = (clock - musicAt) % (PLAYS + RESTS) < PLAYS and 1 or 0.3
    for k = 0, #layers do
        local l = layers[k]
        local want = on[k] and MIX[k] * level("music") * (k == 5 and 1 or breath) or 0
        -- In slowly, and the drums out slowly too once the danger has passed.
        l.vol = l.vol + (want - l.vol) * min(1, dt * (k == 5 and want > l.vol and 0.8 or 0.25))
        l.src:setVolume(l.vol)
    end
end

-- The game out of sight: everything stops where it is, and picks up after.
local held
function Audio.hide(away)
    if not Audio.on or away == Audio.away then return end
    Audio.away = away
    if away then held = love.audio.pause()
    elseif held then love.audio.play(held); held = nil end
end

-- Loud, soft, off: what V goes round, on the master volume. Answers its name.
function Audio.cycle()
    local m = Settings.get("master")
    m = m >= 100 and 50 or (m > 0 and 0 or 100)
    Settings.set("master", m)
    Settings.save()
    return m >= 100 and "LOUD" or (m > 0 and "SOFT" or "OFF")
end

-- Dev: every sound, loop and layer of the music written as a .wav into the
-- save directory (sounds/), to listen to. Answers where.
function Audio.dump()
    local function u32(v) return string.char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256) end
    local function u16(v) return string.char(v % 256, floor(v / 256) % 256) end
    local function wav(data)
        local n = data:getSampleCount()
        return "RIFF" .. u32(36 + n * 2) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(1) .. u32(Synth.RATE) .. u32(Synth.RATE * 2)
            .. u16(2) .. u16(16) .. "data" .. u32(n * 2) .. data:getString()
    end
    love.filesystem.createDirectory("sounds")
    for name in pairs(Synth.DEFS) do love.filesystem.write("sounds/" .. name .. ".wav", wav(Synth.make(name))) end
    for name in pairs(Synth.LOOPS) do love.filesystem.write("sounds/loop-" .. name .. ".wav", wav(Synth.make(name))) end
    for k = 0, #Synth.LAYERS do love.filesystem.write("sounds/music-" .. k .. ".wav", wav(Synth.make(k))) end
    return love.filesystem.getSaveDirectory() .. "/sounds"
end

return Audio
