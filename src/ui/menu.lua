-- The menus: the pause menu (Escape while playing), the settings in five tabs
-- (display, interface, audio, gameplay, controls), the question asked before
-- a game is thrown away, and the one asked after the display changes -- kept
-- only if the player says so within fifteen seconds, as a screen that can't
-- be seen can't be put back by hand.
--
-- Settings take effect as they are changed and are saved as they are; this is
-- also where the ones that need doing something (the window, the sizes, the
-- touch buttons) are done.

local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Win = require "src.ui.windows"
local View = require "src.ui.view"
local Settings = require "src.settings"
local Font = require "src.font"

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local text, rect, button = Draw.text, Draw.rect, Draw.button

local Menu = {}

local TABS = { "display", "interface", "audio", "gameplay", "controls" }

-- A line about each setting, shown while the pointer is over it.
local TIPS = {
    mode = "WINDOWED, BORDERLESS (THE WHOLE DESKTOP) OR EXCLUSIVE FULLSCREEN",
    resolution = "THE WINDOW'S SIZE, OR THE SCREEN'S IN FULLSCREEN",
    vsync = "WAIT FOR THE SCREEN BETWEEN FRAMES: NO TEARING",
    fps = "AT MOST THIS MANY FRAMES A SECOND, TO SAVE POWER",
    seaMotion = "WAVES, FOAM AND BREAKERS ON THE SEA; OFF, IT LIES STILL",
    landMotion = "WIND, CLOUDS, SMOKE, BIRDS, DEER, SHEEP; OFF, ALL STILL",
    dayNight = "THE SUN GOES ROUND AS THE TURNS PASS; LAMPS LIGHT THE NIGHT",
    clock = "THE HOUR OF THE DAY IN THE CORNER, AND HOW IT LOOKS",
    showFps = "FRAMES A SECOND IN THE CORNER",
    uiScale = "HOW BIG THE MENUS, PANELS AND LETTERING ARE, IN WHOLE PIXELS",
    mapScale = "HOW BIG A PIXEL OF THE MAP IS BEFORE ANY ZOOM",
    touch = "BUTTONS DOWN THE RIGHT FOR WHAT KEYS DO",
    tooltips = "WHAT IS ON THE HEX UNDER THE POINTER, AT THE BOTTOM",
    newsTime = "HOW LONG THE NEWS STAYS AT THE TOP LEFT",
    lockWindows = "WINDOWS STAY WHERE THEY ARE AND CAN'T BE DRAGGED",
    snapWindows = "A DRAGGED WINDOW JUMPS TO A NEAR EDGE OF THE SCREEN",
    master = "EVERYTHING, TOGETHER. V GOES ROUND LOUD, SOFT AND OFF",
    music = "THE MUSIC, WHICH GROWS WITH THE EMPIRE",
    ambience = "THE LAND UNDER THE CAMERA: SEA, LEAVES, WIND AND BIRDS",
    effects = "UNITS, FIGHTS, BUTTONS AND THE NEWS",
    muteAway = "SILENCE WHILE ANOTHER WINDOW HAS THE KEYBOARD",
    animSpeed = "HOW FAST UNITS WALK AND FIGHT",
    panSpeed = "HOW FAST THE KEYS AND SCREEN EDGES MOVE THE CAMERA",
    edgePan = "THE POINTER AT THE EDGE OF THE WINDOW MOVES THE CAMERA",
    devTools = "A DEV WINDOW IN THE MENU: SKIP TURNS, JUMP TO THE CATACLYSM'S STAGES",
    autoCycle = "AFTER A UNIT'S ORDERS, ON TO THE NEXT THAT NEEDS SOME",
    follow = "THE CAMERA GOES TO EACH UNIT AS IT IS CHOSEN",
    grid = "THE LINES BETWEEN HEXES",
    resetWindows = "EVERY WINDOW BACK TO ITS OWN PLACE",
}

local tab = "display"
local capture         -- the command waiting for a key
local trial           -- the display as it was, while the new one is on trial
local tip

--- applying -------------------------------------------------------------------------

local function dims(res)
    local w, h = (res or ""):match("^(%d+)x(%d+)$")
    return tonumber(w), tonumber(h)
end

-- The window sizes to offer: the common ones that fit the desktop, and the
-- one it is now if that's none of them.
local SIZES = { "1024x576", "1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160" }
local function resolutions()
    local out = {}
    if Settings.get("mode") == "fullscreen" then
        local modes = love.window.getFullscreenModes()
        table.sort(modes, function(a, b) return a.width * a.height < b.width * b.height end)
        for _, m in ipairs(modes) do
            local r = m.width .. "x" .. m.height
            if out[#out] ~= r then out[#out + 1] = r end
        end
    else
        local dw, dh = love.window.getDesktopDimensions()
        for _, r in ipairs(SIZES) do
            local w, h = dims(r)
            if w <= dw and h <= dh then out[#out + 1] = r end
        end
    end
    local cur = Settings.get("resolution")
    local has = false
    for _, r in ipairs(out) do if r == cur then has = true end end
    if not has and dims(cur) then
        out[#out + 1] = cur
        table.sort(out, function(a, b)
            local aw, ah = dims(a)
            local bw, bh = dims(b)
            return aw * ah < bw * bh
        end)
    end
    if #out == 0 then out[1] = cur end
    return out
end

-- The sizes a setting of whole-number zooms may be: 0 for automatic, then
-- each zoom that leaves at least `minW` x `minH` of its pixels.
local function zooms(minW, minH)
    local w, h = love.graphics.getDimensions()
    local out = { 0 }
    for k = 1, 12 do
        if ceil(w / k) >= minW and ceil(h / k) >= minH then out[#out + 1] = k end
    end
    return out
end
Menu.UI_MIN_W, Menu.UI_MIN_H = 300, 180
local function uiScales() return zooms(Menu.UI_MIN_W, Menu.UI_MIN_H) end
local function mapScales() return zooms(320, 200) end

-- The window as the display settings say.
function Menu.applyDisplay()
    if S.phone then return end
    local mode = Settings.get("mode")
    local w, h = dims(Settings.get("resolution"))
    local flags = {
        fullscreen = mode ~= "windowed",
        fullscreentype = mode == "fullscreen" and "exclusive" or "desktop",
        vsync = Settings.get("vsync"),
        resizable = true, minwidth = 640, minheight = 400,
        highdpi = true, usedpiscale = false,
    }
    if mode == "borderless" or not w then w, h = 0, 0 end
    if mode == "windowed" then
        local dw, dh = love.window.getDesktopDimensions()
        w, h = min(w, dw), min(h, dh)
    end
    local cw, ch, cf = love.window.getMode()
    local same = cw == w and ch == h and cf.fullscreen == flags.fullscreen
        and (not flags.fullscreen or cf.fullscreentype == flags.fullscreentype)
    if same then
        love.window.setVSync(flags.vsync)
    else
        S.settingMode = true
        love.window.setMode(w, h, flags)
        S.settingMode = false
        love.window.setIcon(love.image.newImageData("assets/icon/icon.png"))
    end
    View.fit()
end

-- Whether to show the touch buttons, as the setting and the screen say.
function Menu.applyTouch()
    local t = Settings.get("touch")
    S.touch = t == "on" or (t == "auto" and (S.phone or S.touchSeen or false))
end

-- What has to be done about a setting that has just changed.
local function changed(id)
    if id == "uiScale" or id == "mapScale" then View.fit()
    elseif id == "touch" then Menu.applyTouch()
    elseif id == "grid" then S.grid = Settings.get("grid")
    end
    Settings.save()
end

-- Everything as saved, at the start.
function Menu.applyAll()
    S.grid = Settings.get("grid")
    Menu.applyTouch()
    if not S.phone then
        local _, _, f = love.window.getMode()
        local mode = Settings.get("mode")
        local now = f.fullscreen and (f.fullscreentype == "exclusive" and "fullscreen" or "borderless") or "windowed"
        local w, h = love.window.getMode()
        if mode ~= now or (mode ~= "borderless" and Settings.get("resolution") ~= w .. "x" .. h)
            or f.vsync ~= Settings.get("vsync") then
            Menu.applyDisplay()
        end
    end
    View.fit()
end

-- The window was resized by hand: in a window, that's its resolution now.
function Menu.resized(w, h)
    if S.settingMode or S.phone then return end
    local _, _, f = love.window.getMode()
    if not f.fullscreen and Settings.get("mode") == "windowed" then
        Settings.set("resolution", w .. "x" .. h)
        Settings.save()
    end
end

local function startTrial(old)
    trial = old
    trial.left = 15
    Menu.applyDisplay()
end

local function endTrial(keep)
    if not trial then return end
    if not keep then
        Settings.set("mode", trial.mode)
        Settings.set("resolution", trial.resolution)
        Settings.set("vsync", trial.vsync)
        Menu.applyDisplay()
    end
    Settings.save()
    trial = nil
end

function Menu.update(dt)
    if trial then
        trial.left = trial.left - dt
        if trial.left <= 0 then endTrial(false) end
    end
end

-- Steps a display setting, applying it on trial.
local function stepDisplay(id, dir, list)
    local old = trial or { mode = Settings.get("mode"), resolution = Settings.get("resolution"), vsync = Settings.get("vsync") }
    Settings.step(id, dir, list)
    if id == "mode" and Settings.get("mode") == "fullscreen" then
        -- Exclusive fullscreen needs a mode the screen has.
        local list2 = resolutions()
        local ok = false
        for _, r in ipairs(list2) do if r == Settings.get("resolution") then ok = true end end
        if not ok then Settings.set("resolution", list2[#list2]) end
    end
    if id == "vsync" then
        Menu.applyDisplay()
        Settings.save()
        return
    end
    trial = nil
    startTrial(old)
end

-- Steps a size a zoom bigger or smaller from what it is now, automatic or
-- not; past either end, back to automatic.
local function stepScale(id, dir, list)
    local v = Settings.get(id)
    local cur = v ~= 0 and v or (id == "uiScale" and S.uz or View.baseZoom())
    local nxt = cur + dir
    if nxt < 1 or nxt > list[#list] then nxt = 0 end
    if v == 0 and nxt == 0 then nxt = dir > 0 and list[#list] or 1 end
    Settings.set(id, nxt)
    changed(id)
end

--- opening and closing ---------------------------------------------------------------

function Menu.openSettings(at)
    if type(at) == "string" then tab = at end
    S.settings = true
    capture = nil
end

function Menu.closeSettings()
    S.settings = false
    capture = nil
end

function Menu.openPause() S.pause = true end

-- The new game window: which cataclysm ends the world, then START.
function Menu.openNewGame() S.choosing = true end

-- The developer tools' window (the DEVELOPER TOOLS setting).
function Menu.openDev() S.dev = true end

-- Asks `question` with a yes and a no; `yes` is done on yes.
function Menu.ask(question, yesLabel, yes)
    S.ask = { text = question, label = yesLabel, fn = yes }
end

-- Is any menu up (so the board and its keys wait)?
function Menu.open() return S.settings or S.pause or S.ask or S.choosing or S.dev or trial ~= nil end

-- Escape: shuts the front menu. Answers whether there was one.
function Menu.back()
    if capture then capture = nil return true end
    if trial then endTrial(false) return true end
    if S.ask then S.ask = nil return true end
    if S.settings then Menu.closeSettings() return true end
    if S.dev then S.dev = false return true end
    if S.choosing then S.choosing = false return true end
    if S.pause then S.pause = false return true end
    return false
end

-- A key, if the menus want it: one being bound. Answers whether they took it.
function Menu.key(key)
    if not capture then return false end
    if key == "escape" then capture = nil return true end
    if Settings.RESERVED[key] then return true end
    Settings.bind(capture, key)
    Settings.save()
    capture = nil
    return true
end

--- the settings window --------------------------------------------------------------

local ROW = 12

-- A choice: "<" the value ">"; a click on the value goes forward too.
local function chooser(id, x, y, w, list, onStep, opts)
    opts = opts or {}
    local vw = w - 22
    local step = function(dir) return function()
        if onStep then onStep(id, dir, list) else Settings.step(id, dir, list) changed(id) end
    end end
    local off = opts.off
    button("<", x, y, 10, 10, step(-1), { off = off })
    local label = opts.label or Settings.show(id)
    button(label, x + 11, y, vw, 10, step(1), { off = off })
    button(">", x + 12 + vw, y, 10, 10, step(1), { off = off })
end

-- A slider: a bar to click or drag on, and the number.
local function slider(id, x, y, w)
    local s = Settings.BY[id]
    local v = Settings.get(id)
    local bw = w - 24
    button("-", x, y, 10, 10, function() Settings.step(id, -1) changed(id) end)
    local bx = x + 12
    rect("o", bx, y + 1, bw, 8)
    local n = floor((bw - 2) * (v - s.min) / (s.max - s.min) + 0.5)
    rect("n", bx + 1, y + 2, bw - 2, 6)
    if n > 0 then rect("c", bx + 1, y + 2, n, 6) rect("w", bx + 1, y + 2, n, 1) end
    -- Ticks at every step.
    for k = 1, (s.max - s.min) / s.step - 1 do
        local tx = bx + 1 + floor((bw - 2) * k * s.step / (s.max - s.min))
        rect(tx <= bx + n and "s" or "u", tx, y + 7, 1, 1)
    end
    local num = tostring(v)
    -- In ink over the filled part, so it reads.
    text(n > bw / 2 and "o" or "w", num, bx + floor((bw - Font.width(num)) / 2), y + 3)
    S.panels[#S.panels + 1] = { x = bx, y = y, w = bw, h = 10, fn = function(mx)
        local f = max(0, min(1, (mx - bx - 1) / (bw - 2)))
        local was = Settings.get(id)
        Settings.set(id, s.min + f * (s.max - s.min))
        if Settings.get(id) ~= was then changed(id) end
    end }
    button("+", x + w - 10, y, 10, 10, function() Settings.step(id, 1) changed(id) end)
end

local function hovering(x, y, w, h)
    local m = S.mouse
    return m.x >= x and m.y >= y and m.x < x + w and m.y < y + h
end

local function settingRows(x, y, w)
    local cw = 128
    local cx = x + w - cw - 4
    for _, s in ipairs(Settings.LIST) do
        if s.tab == tab then
            if hovering(x, y - 1, w, ROW) then
                tip = TIPS[s.id]
                rect("n", x + 2, y - 1, w - 4, ROW)
            end
            text("c", s.name, x + 6, y + 3)
            if s.min then
                slider(s.id, cx, y, cw)
            elseif s.id == "resolution" then
                local mode = Settings.get("mode")
                chooser(s.id, cx, y, cw, resolutions(), stepDisplay,
                    { off = S.phone or mode == "borderless", label = mode == "borderless" and "DESKTOP" or nil })
            elseif s.id == "mode" or s.id == "vsync" then
                chooser(s.id, cx, y, cw, nil, stepDisplay, { off = S.phone })
            elseif s.id == "uiScale" or s.id == "mapScale" then
                local v = Settings.get(s.id)
                local label = v == 0 and ("AUTO (" .. (s.id == "uiScale" and S.uz or View.baseZoom()) .. "X)") or (v .. "X")
                chooser(s.id, cx, y, cw, s.id == "uiScale" and uiScales() or mapScales(), stepScale, { label = label })
            else
                chooser(s.id, cx, y, cw)
            end
            y = y + ROW
        end
    end
    if tab == "interface" then
        if hovering(x, y - 1, w, ROW) then tip = TIPS.resetWindows end
        text("c", "WINDOW POSITIONS", x + 6, y + 3)
        button("RESET ALL", cx, y, cw, 10, function()
            Settings.resetWindows()
            Settings.save()
        end)
    end
    if S.phone and tab == "display" then
        text("k", "THE DISPLAY IS THE DEVICE'S OWN HERE", x + 6, y + 3)
    end
end

local function controlRows(x, y, w, h)
    local perCol = ceil(#Settings.COMMANDS / 2)
    local rowH = min(ROW, floor(h / perCol))
    local colW = floor((w - 6) / 2)
    for k, c in ipairs(Settings.COMMANDS) do
        local col = floor((k - 1) / perCol)
        local cx, cy = x + 3 + col * colW, y + ((k - 1) % perCol) * rowH
        local kw = 50
        text("c", c.name, cx + 3, cy + 3)
        local waiting = capture == c.id
        local label = waiting and (floor(S.clock * 3) % 2 == 0 and "PRESS A KEY" or "") or Settings.keyName(Settings.key(c.id))
        button(label, cx + colW - kw - 4, cy, kw, rowH - 1, function() capture = c.id end, { on = waiting })
    end
    tip = capture and "PRESS THE NEW KEY, OR ESCAPE TO KEEP THE OLD. A KEY IN USE SWAPS"
        or "CLICK A KEY TO CHANGE IT. ARROWS ALWAYS PAN; ESCAPE IS THE MENU"
end

local function settingsWindow()
    local top = S.mode == "play" and 11 or 0
    local w = min(300, S.vw - 4)
    local h = min(206, S.vh - top - 4)
    Win.add({
        id = "settings", title = "SETTINGS", w = w, h = h, modal = true,
        x = floor((S.vw - w) / 2), y = top + floor((S.vh - top - h) / 2),
        close = Menu.closeSettings,
        draw = function(x, y, ww, hh)
            tip = nil
            -- The tabs.
            local tw = floor((ww - 6) / #TABS)
            for k, t in ipairs(TABS) do
                local on = t == tab
                button(t:upper(), x + 3 + (k - 1) * tw, y + 2, tw - 1, 11, function()
                    tab = t
                    capture = nil
                end, { on = on })
            end
            rect("o", x + 2, y + 14, ww - 4, 1)
            local bodyY, footY = y + 18, y + hh - 26
            if tab == "controls" then controlRows(x, bodyY, ww, footY - bodyY - 1)
            else settingRows(x, bodyY, ww) end
            -- What the setting under the pointer does.
            rect("o", x + 2, footY, ww - 4, 1)
            if tip then text("s", Font.cut(tip, floor((ww - 10) / 4)), x + 5, footY + 3) end
            button("RESET " .. tab:upper(), x + 4, y + hh - 15, 96, 12, function()
                local old = { mode = Settings.get("mode"), resolution = Settings.get("resolution"), vsync = Settings.get("vsync") }
                Settings.reset(tab)
                if tab == "display" then startTrial(trial or old) end
                Menu.applyTouch()
                S.grid = Settings.get("grid")
                View.fit()
                Settings.save()
            end)
            button("DONE", x + ww - 64, y + hh - 15, 60, 12, Menu.closeSettings, { strong = true })
        end,
    })
end

--- the pause menu, and questions ---------------------------------------------------------

local function pauseWindow()
    local dev = Settings.get("devTools")
    local w, h = 120, 11 + (dev and 6 or 5) * 15 + 6
    Win.add({
        id = "pause", title = "MENU", w = w, h = h, modal = true,
        x = floor((S.vw - w) / 2), y = floor((S.vh - h) / 2),
        close = function() S.pause = false end,
        draw = function(x, y, ww)
            local bx, bw = x + 8, ww - 16
            local yy = y + 4
            local function item(label, fn, opts)
                button(label, bx, yy, bw, 13, fn, opts)
                yy = yy + 15
            end
            item("RESUME", function() S.pause = false end, { strong = true })
            item("SETTINGS", Menu.openSettings)
            if dev then item("DEV TOOLS", function() S.pause = false Menu.openDev() end) end
            item("NEW GAME", function()
                Menu.ask("START AGAIN? THIS GAME WILL BE LOST.", "NEW GAME", function()
                    S.pause = false
                    Menu.openNewGame()
                end)
            end)
            item("MAIN MENU", function()
                Menu.ask("LEAVE FOR THE MAIN MENU? THIS GAME WILL BE LOST.", "LEAVE", function()
                    S.pause = false
                    S.mode = "title"
                end)
            end)
            item("QUIT GAME", function()
                Menu.ask("QUIT? THIS GAME WILL BE LOST.", "QUIT", function() love.event.quit() end)
            end)
        end,
    })
end

--- a new game: how the world ends ------------------------------------------------------

-- The cataclysms, in the order the window lists them. Those not built yet
-- show, greyed, so the player knows they are coming.
Menu.CATACLYSMS = {
    { id = "heat", name = "HEAT DEATH", about = { "THE SUN GROWS CRUEL: DROUGHT, WILDFIRES,", "THEN THE SCORCH. THE WORLD ENDS AT TURN 160" } },
    { id = "flood", name = "THE DELUGE", about = { "THE RAINS WILL NOT STOP: MARSHES, FLOODS,", "THEN THE RISING SEA. THE WORLD ENDS AT TURN 160" } },
    { id = "sky", name = "SKY DEATH", soon = true, about = { "METEORS AND STRANGE THINGS IN THE SKY.", "NOT YET MADE" } },
    { id = "demons", name = "DEMONS", soon = true, about = { "DEMONIC CREATURES COME UP OUT OF THE EARTH.", "NOT YET MADE" } },
    { id = "none", name = "NONE", about = { "NO CATACLYSM: THE GAME ENDS AT TURN 150", "AND THE HIGHEST SCORE WINS" } },
}

local function newGameWindow()
    local w, h = 220, 11 + 14 + #Menu.CATACLYSMS * 14 + 26 + 22
    Win.add({
        id = "newgame", title = "NEW GAME", w = w, h = h, modal = true,
        x = floor((S.vw - w) / 2), y = floor((S.vh - h) / 2),
        close = function() S.choosing = false end,
        draw = function(x, y, ww, hh)
            text("w", "HOW DOES THE WORLD END?", x + 6, y + 4)
            local pick = Settings.get("cataclysm")
            local under
            local yy = y + 15
            for _, c in ipairs(Menu.CATACLYSMS) do
                local label = c.soon and (c.name .. " - COMING") or c.name
                button(label, x + 6, yy, ww - 12, 12, function()
                    if c.soon then return end
                    Settings.set("cataclysm", c.id)
                    Settings.save()
                end, { on = c.id == pick, off = c.soon })
                if hovering(x + 6, yy, ww - 12, 12) then under = c end
                yy = yy + 14
            end
            -- What the one under the pointer (or the one chosen) does.
            local about = under and under.about
            if not about then
                for _, c in ipairs(Menu.CATACLYSMS) do if c.id == pick then about = c.about end end
            end
            for k, l in ipairs(about or {}) do text("s", l, x + 6, yy + 2 + (k - 1) * 8) end
            local bw = 60
            button("START", x + floor(ww / 2) - bw - 2, y + hh - 16, bw, 12, function()
                S.choosing = false
                S.newGame()
            end, { strong = true })
            button("CANCEL", x + floor(ww / 2) + 2, y + hh - 16, bw, 12, function() S.choosing = false end)
        end,
    })
end

--- developer tools: skipping turns ---------------------------------------------------------

local function devWindow()
    local O = require "src.ui.orders"
    local Cat = require "src.cataclysm"
    local g = S.game
    local jumps = { { "+1", 1 }, { "+5", 5 }, { "+10", 10 }, { "+25", 25 } }
    local stages = {}
    for _, st in ipairs(Cat.stagesOf(g)) do stages[#stages + 1] = { Cat.name(g, st[1]):gsub("^THE ", ""), st[2] } end
    stages[#stages + 1] = { "LAST TURN", g:lastTurn() }
    local w, h = 200, 11 + 26 + 14 + 8 + #stages * 14 + 24
    Win.add({
        id = "dev", title = "DEV TOOLS", w = w, h = h, modal = true,
        x = floor((S.vw - w) / 2), y = floor((S.vh - h) / 2),
        close = function() S.dev = false end,
        draw = function(x, y, ww, hh)
            local stage = Cat.stage(g)
            text("w", "TURN " .. g.turn .. (stage and ("  " .. Cat.name(g, stage)) or ""), x + 6, y + 4)
            text("s", "THE COMPUTER PLAYS YOUR SIDE UP TO THE TURN", x + 6, y + 13)
            local bw = floor((ww - 12 - 6) / #jumps)
            for k, j in ipairs(jumps) do
                button(j[1], x + 6 + (k - 1) * (bw + 2), y + 23, bw, 12, function() O.skipTo(g.turn + j[2]) end,
                    { off = S.over ~= nil })
            end
            local yy = y + 41
            text("c", "JUMP TO:", x + 6, yy)
            yy = yy + 9
            for _, st in ipairs(stages) do
                local past = g.turn >= st[2]
                button(st[1] .. "  (TURN " .. st[2] .. ")", x + 6, yy, ww - 12, 12, function() O.skipTo(st[2]) end,
                    { off = past or S.over ~= nil })
                yy = yy + 14
            end
            button("CLOSE", x + ww - 56, y + hh - 16, 50, 12, function() S.dev = false end, { strong = true })
        end,
    })
end

local function question(id, title, lines, yes, yesLabel, no, noLabel)
    local w = 40
    for _, l in ipairs(lines) do w = max(w, Font.width(l) + 16) end
    w = min(w, S.vw - 4)
    local h = 11 + #lines * 8 + 24
    Win.add({
        id = id, title = title, w = w, h = h, modal = true,
        x = floor((S.vw - w) / 2), y = floor((S.vh - h) / 2),
        close = no,
        draw = function(x, y, ww, hh)
            for k, l in ipairs(lines) do text("w", l, x + floor((ww - Font.width(l)) / 2), y + 4 + (k - 1) * 8) end
            local bw = 56
            button(yesLabel, x + floor(ww / 2) - bw - 2, y + hh - 16, bw, 12, yes, { strong = true })
            button(noLabel, x + floor(ww / 2) + 2, y + hh - 16, bw, 12, no)
        end,
    })
end

--- all of it ---------------------------------------------------------------------------

function Menu.draw()
    if S.pause and S.mode == "play" then pauseWindow() end
    if S.dev and S.mode == "play" then devWindow() end
    if S.choosing then newGameWindow() end
    if S.settings then settingsWindow() end
    if S.ask then
        local a = S.ask
        question("ask", "ARE YOU SURE?", { a.text }, function()
            S.ask = nil
            a.fn()
        end, a.label, function() S.ask = nil end, "CANCEL")
    end
    if trial then
        question("trial", "DISPLAY", { "KEEP THESE DISPLAY SETTINGS?", "GOING BACK IN " .. ceil(trial.left) .. " SECONDS" },
            function() endTrial(true) end, "KEEP", function() endTrial(false) end, "GO BACK")
    end
end

-- The frame rate, in the corner, over everything.
function Menu.drawFps()
    if not Settings.get("showFps") then return end
    local s = love.timer.getFPS() .. " FPS"
    local w = Font.width(s) + 4
    local y = S.mode == "play" and 12 or 1
    rect("o", S.vw - w - 1, y, w, 7)
    text("w", s, S.vw - w + 1, y + 1)
end

-- Holds the frame back to the limit, if there is one.
local nextFrame
function Menu.throttle()
    local fps = Settings.get("fps")
    if not fps or fps <= 0 then nextFrame = nil return end
    local now = love.timer.getTime()
    if nextFrame and now < nextFrame then
        love.timer.sleep(nextFrame - now)
        now = nextFrame
    end
    -- On time, the next is a frame after this one was due; late, a frame from now.
    if nextFrame and now - nextFrame < 1 / fps then nextFrame = nextFrame + 1 / fps
    else nextFrame = now + 1 / fps end
end

return Menu
