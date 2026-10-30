-- Sepia: a small Civilization in eight shades of sepia.
--
-- A hex map traced once into a picture with a depth buffer behind it
-- (src/world.lua), by underroot's 3D method (src/tracer.lua): hexes standing
-- as tall as their ground, mountains of faceted rock, forests, and fog drawn
-- as an old paper map. Units and cities are little models painted once per
-- pose (src/models.lua) and laid over the map a pixel at a time each frame,
-- each pixel kept only where it is nearer than the map there.
--
-- Everything renders into a low-res canvas scaled up by a whole number, in
-- the eight colours of src/palette.lua and nothing else. Every sound is
-- synthesised at load, off the main thread (src/synth.lua, src/ui/audio.lua).
--
-- This file starts the game, runs each frame and lays the two pictures on
-- the window. The rules are in src/game.lua and src/ai.lua, the numbers in
-- src/defs.lua, the screen's parts in src/ui/, the player's settings in
-- src/settings.lua.

local T = require "src.tracer"
local S = require "src.ui.state"
local View = require "src.ui.view"
local Input = require "src.ui.input"
local Hud = require "src.ui.hud"
local Board = require "src.ui.board"
local Anim = require "src.ui.anim"
local O = require "src.ui.orders"
local Draw = require "src.ui.draw"
local Game = require "src.game"
local World = require "src.world"
local Font = require "src.font"
local Audio = require "src.ui.audio"
local Win = require "src.ui.windows"
local Menu = require "src.ui.menu"
local Settings = require "src.settings"
local Sea = require "src.ui.sea"
local Daylight = require "src.ui.daylight"
local Wild = require "src.ui.wild"
local Birds = require "src.ui.birds"

local floor = math.floor

for _, name in ipairs({ "mousepressed", "mousereleased", "mousemoved", "wheelmoved", "keypressed",
        "touchpressed", "touchmoved", "touchreleased" }) do
    love[name] = Input[name]
end

function love.resize(w, h)
    Menu.resized(w, h)
    View.fit()
end
-- Out of sight, the sound stops; out of focus too, if the settings say.
local visible, focused = true, true
local function away() return not visible or (Settings.get("muteAway") and not focused) end
function love.visible(v) visible = v Audio.hide(away()) end
function love.focus(f) focused = f Audio.hide(away()) end
function love.quit() Audio.stop() end

-- A new game: a new map from a new seed, traced in slices while the loading
-- bar fills, then the first turn.
function S.newGame(seed)
    seed = seed or S.seedArg or (os.time() % 100000)
    S.seedArg = nil
    S.game = Game.new({ seed = seed })
    S.world = World.new(S.game)
    S.anim, S.effects, S.msgs = {}, {}, {}
    S.selected, S.panel, S.over, S.hover = nil, nil, nil, nil
    S.pause, S.ask = false, nil
    O.resetLog()
    S.progress = 0
    S.mode = "loading"
    S.painter = coroutine.create(function() S.world:paint(coroutine.yield) end)
end

local function startPlay()
    S.mode = "play"
    View.fit()
    O.collectLog()
    local first = S.game:unitsOf(1)[1]
    if first then View.lookAt(S.game.cells[first.cell], true) end
    O.nextUnit()
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    -- The title-bar / taskbar icon: the same city as the builds' (assets/icon/).
    love.window.setIcon(love.image.newImageData("assets/icon/icon.png"))
    love.graphics.setLineStyle("rough")
    Sea.load()
    Daylight.load()
    local os = love.system.getOS()
    S.phone = os == "Android" or os == "iOS"
    S.touch = S.phone
    for n, a in ipairs(args or {}) do
        if a == "--seed" and tonumber(args[n + 1]) then S.seedArg = tonumber(args[n + 1]) end
        if a == "--play" then S.play = true end
        -- `--touch` lays out the screen as for a phone.
        if a == "--touch" then S.touch, S.phone = true, true end
        -- For checking how it looks: `--shot file.png` takes a picture of the
        -- game a moment after it starts and quits; `--turns n` has the
        -- computer play the player's side for n turns first.
        if a == "--shot" then S.plan = { file = args[n + 1] or "shot.png", turns = 0, frames = 0 } end
        if a == "--turns" and S.plan then S.plan.turns = tonumber(args[n + 1]) or 0 end
        if a == "--select" and S.plan then S.plan.select = args[n + 1] end
        -- `--hour h`: every turn played at h o'clock (0..24), to see the light.
        if a == "--hour" and tonumber(args[n + 1]) then Daylight.force = tonumber(args[n + 1]) / 24 end
        -- `--clock look`: the clock drawn so (arc, dial, strip, scene, off).
        if a == "--clock" then require("src.ui.clock").force = args[n + 1] end
        -- `--open settings:audio` (or `pause`) shows a menu in the picture.
        if a == "--open" and S.plan then S.plan.open = args[n + 1] end
        -- `--sounds` writes every sound as a .wav into the save folder, and quits.
        if a == "--sounds" then
            print("wrote " .. Audio.dump())
            love.event.quit()
        end
    end
    -- Pictures are taken as the game starts, whatever the player has set.
    if not S.plan then Settings.load() end
    Menu.applyAll()
    -- Pictures are taken in silence.
    if not S.plan then Audio.init() end
end

-- The dev plan above, a frame at a time.
local function followPlan()
    local plan = S.plan
    plan.frames = plan.frames + 1
    if plan.frames == 2 then
        local AI = require "src.ai"
        for _ = 1, plan.turns do
            AI.play(S.game, S.game.players[1])
            O.endTurn()
        end
        Anim.events(S.game)
        S.anim, S.effects = {}, {}
        for _, u in ipairs(S.game.units) do u.trail = { u.cell } end
        local cap = S.game:citiesOf(1)[1]
        if plan.select == "city" and cap then O.select(cap, true)
        else
            local u = S.game:unitsOf(1)[1]
            if u then O.select(u, true) end
        end
        if S.selected then View.lookAt(S.game.cells[(S.selected.unit or S.selected.city).cell], true) end
        -- `--select coast`: the camera over the explored shore nearest the
        -- player's first unit or city, to look at the sea.
        if plan.select == "coast" and S.selected then
            local from = S.game.cells[(S.selected.unit or S.selected.city).cell]
            local best, bd = nil, math.huge
            for _, cell in ipairs(S.game.cells) do
                local d = S.game:dist(cell, from)
                if cell.terrain == "coast" and S.game.players[1].explored[cell.id] and d < bd then best, bd = cell, d end
            end
            if best then View.lookAt(best, true) end
        end
        -- The pointer over the furthest hex the chosen unit can reach.
        local u = S.selected and S.selected.unit
        if u then
            local best, bd = nil, -1
            for id, r in pairs(S.game:reach(u)) do
                local d = S.game:dist(S.game.cells[id], S.game.cells[u.cell])
                if not r.through and d > bd then best, bd = S.game.cells[id], d end
            end
            if best then
                local i, j = S.world:toImage(best.x, best.top, best.z)
                S.mouse.wx, S.mouse.wy = (i - floor(S.camx)) * S.zoom, (j - floor(S.camy)) * S.zoom
                S.mouse.x, S.mouse.y = floor(S.mouse.wx / S.uz), floor(S.mouse.wy / S.uz)
            end
        end
    end
    if plan.frames == 3 and plan.open then
        local what, tab = plan.open:match("^(%a+):?(%a*)$")
        if what == "pause" then Menu.openPause() end
        if what == "settings" then Menu.openSettings(tab ~= "" and tab or nil) end
    end
    if plan.frames == 30 then S.shot = plan.file end
    if plan.frames == 32 then love.event.quit() end
end

function love.update(dt)
    Menu.throttle()
    if S.play then S.play = nil S.newGame() end
    dt = math.min(dt, 1 / 20)
    S.clock = S.clock + dt
    S.dt = dt
    Sea.update(dt)
    Audio.hide(away())
    Audio.update(dt)
    Menu.update(dt)
    S.menuOpen = Menu.open() or Win.modal()
    if S.mode == "loading" then
        local t0 = love.timer.getTime()
        while coroutine.status(S.painter) ~= "dead" and love.timer.getTime() - t0 < 1 / 30 do
            local ok, p = coroutine.resume(S.painter)
            if not ok then error(p) end
            S.progress = p or 1
        end
        if coroutine.status(S.painter) == "dead" then
            S.painter = nil
            startPlay()
        end
        return
    end
    if S.mode ~= "play" then return end
    if S.plan then followPlan() end
    View.update(dt)
    Anim.update(S.game, dt * Settings.get("animSpeed"))
    Daylight.update(dt)
    Wild.update(dt)
    Birds.update(dt)
    Input.findHover()
    if not S.over then
        local result, why = S.game:outcome()
        if result then S.over = { result = result, why = why } end
    end
    O.collectLog()
end

--- the title and the loading bar ------------------------------------------------

-- The paper map the fog is drawn as, for behind the title: hex outlines,
-- squashed as the board's are, on cream.
local function hexField()
    Draw.rect("c", 0, 0, S.vw, S.vh)
    Draw.color("t")
    local R, sq = 9, T.SE
    local w, rowStep = R * math.sqrt(3), R * 1.5
    local function line(x0, y0, x1, y1)
        local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        for k = 0, n do
            local f = k / math.max(1, n)
            love.graphics.rectangle("fill", floor(x0 + (x1 - x0) * f), floor(y0 + (y1 - y0) * f), 1, 1)
        end
    end
    for r = -1, floor(S.vh / (rowStep * sq)) + 1 do
        for c = -1, floor(S.vw / w) + 1 do
            local cx, cy = c * w + (r % 2) * w / 2, r * rowStep * sq
            -- Three edges a hex, so each is drawn once: north-west, north-east, east.
            for _, e in ipairs({ 4, 5, 0 }) do
                local a0, a1 = math.rad(60 * e - 30), math.rad(60 * e + 30)
                line(cx + R * math.cos(a0), cy + R * math.sin(a0) * sq, cx + R * math.cos(a1), cy + R * math.sin(a1) * sq)
            end
        end
    end
end

local function bigText(k, s, cx, y, scale)
    love.graphics.push()
    love.graphics.translate(floor(cx - Font.width(s) * scale / 2), y)
    love.graphics.scale(scale, scale)
    Draw.text(k, s, 0, 0)
    love.graphics.pop()
end

local function title()
    hexField()
    local cx = floor(S.vw / 2)
    local y = floor(S.vh / 2) - 56
    Draw.rect("o", cx - 130, y - 10, 260, 124)
    Draw.frame("k", cx - 128, y - 8, 256, 120)
    bigText("o", "SEPIA", cx + 1, y + 1, 4)
    bigText("w", "SEPIA", cx, y, 4)
    local sub = "BUILD AN EMPIRE ON A MAP OF SEPIA HEXES"
    Draw.text("c", sub, cx - floor(Font.width(sub) / 2), y + 26)
    Draw.button("NEW GAME", cx - 40, y + 38, 80, 14, function() S.newGame() end, { strong = true })
    Draw.button("SETTINGS", cx - 40, y + 54, 39, 12, Menu.openSettings)
    Draw.button("QUIT", cx + 1, y + 54, 39, 12, function() love.event.quit() end)
    local help = S.touch and {
        "TAP: SELECT, OR SEND THE CHOSEN UNIT THERE",
        "DRAG: PAN   PINCH: ZOOM",
        "THE BUTTONS DOWN THE RIGHT: ZOOM, NEXT UNIT,",
        "CAPITAL, HEX GRID AND SOUND",
    } or (function()
        -- As the keys are bound now.
        local function k(cmd) return Settings.keyName(Settings.key(cmd)) end
        return {
            "LEFT CLICK: SELECT   RIGHT CLICK: MOVE OR ATTACK",
            "DRAG, ARROWS OR " .. k("panUp") .. k("panLeft") .. k("panDown") .. k("panRight") .. ": PAN   WHEEL: ZOOM   "
                .. k("grid") .. ": GRID   " .. k("research") .. ": RESEARCH",
            k("main") .. ": NEXT   " .. k("endTurn") .. ": END TURN   " .. k("skip") .. ": SKIP",
            k("found") .. ": FOUND CITY   " .. k("fortify") .. ": FORTIFY   " .. k("farm") .. ": FARM   "
                .. k("mine") .. ": MINE   " .. k("capital") .. ": CAPITAL",
            k("sound") .. ": SOUND   ESC: MENU   DRAG A WINDOW BY ITS TITLE",
        }
    end)()
    for k, l in ipairs(help) do Draw.text("t", l, cx - floor(Font.width(l) / 2), y + 76 + (k - 1) * 7) end
end

local function loading()
    hexField()
    local cx, cy = floor(S.vw / 2), floor(S.vh / 2)
    local s = "SURVEYING THE LAND"
    Draw.rect("o", cx - 70, cy - 14, 140, 26)
    Draw.text("w", s, cx - floor(Font.width(s) / 2), cy - 9)
    Draw.bar(cx - 60, cy + 2, 120, S.progress or 0, "w", "n")
    Draw.bar(cx - 60, cy + 3, 120, S.progress or 0, "c", "n")
end

function love.draw()
    love.graphics.setCanvas(S.ui)
    love.graphics.clear(0, 0, 0, 0)
    S.buttons, S.panels = {}, {}
    if S.mode == "title" then
        title()
    elseif S.mode == "loading" then
        loading()
    else
        Board.banners()
        Hud.draw(S.dt or 0)
    end
    -- The windows over all the rest, and the menus over them.
    Menu.draw()
    Win.flush()
    Menu.drawFps()
    if S.mode == "play" then Board.draw() end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.clear(T.RGB[T.IDX.o])
    if S.mode == "play" then love.graphics.draw(S.canvas, 0, 0, 0, S.zoom, S.zoom) end
    love.graphics.draw(S.ui, 0, 0, 0, S.uz, S.uz)
    if S.shot then
        local file = S.shot
        love.graphics.captureScreenshot(function(img)
            img:encode("png", file)
            print("saved " .. love.filesystem.getSaveDirectory() .. "/" .. file)
        end)
        S.shot = nil
    end
end
