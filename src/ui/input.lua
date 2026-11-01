-- The pointer and the keys. A press on the HUD is the HUD's; on the board a
-- left click chooses (or, with a unit chosen, sends it where it can go), a
-- drag pans, a right click sends the chosen unit, the wheel zooms.
--
-- A finger is the pointer: LÖVE turns the first one's taps and drags into
-- left clicks. Two fingers pinch to zoom and drag together to pan, and until
-- the last of them lifts the pretend pointer is ignored.
--
-- Windows come before the board: a press on one is its own (src/ui/windows.lua),
-- and while a menu is up (src/ui/menu.lua) the board and its keys wait. Keys
-- are looked up in the bindings (src/settings.lua), not by name.

local S = require "src.ui.state"
local View = require "src.ui.view"
local Hud = require "src.ui.hud"
local Draw = require "src.ui.draw"
local O = require "src.ui.orders"
local Audio = require "src.ui.audio"
local Win = require "src.ui.windows"
local Menu = require "src.ui.menu"
local Settings = require "src.settings"

local abs, log, sqrt = math.abs, math.log, math.sqrt

-- How far apart two fingers must spread (or close) for a step of zoom.
local PINCH_STEP = log(1.3)

local Input = {}

local function point(x, y)
    S.mouse.wx, S.mouse.wy = x, y
    S.mouse.x, S.mouse.y = math.floor(x / S.uz), math.floor(y / S.uz)
end

-- The hex under the pointer, unless the HUD is.
function Input.findHover()
    S.hover = nil
    if S.mode ~= "play" or not S.world or Win.modal() then return end
    if Win.at(S.mouse.x, S.mouse.y) then return end
    if Hud.covers(S.mouse.x, S.mouse.y) then return end
    local i, j = View.toBoard(S.mouse.wx, S.mouse.wy)
    S.hover = S.world:pick(i, j)
end

-- Behind a modal window nothing can be pressed.
local function firstLive(kind)
    return Win.modalFrom and Win.modalFrom[kind] or 1
end

local function buttonAt(x, y)
    for k = #S.buttons, firstLive("buttons"), -1 do
        local b = S.buttons[k]
        if Draw.inside(b, x, y) then return b end
    end
end

function Input.mousepressed(x, y, b)
    if S.pinched then return end
    point(x, y)
    local btn = buttonAt(S.mouse.x, S.mouse.y)
    if btn then
        S.pressed = btn
        local w = Win.at(S.mouse.x, S.mouse.y)
        if w and not Win.modal() then Win.raise(w.id) end
        return
    end
    -- A slider, the minimap: a press there, and a drag after it.
    for k = #S.panels, firstLive("panels"), -1 do
        local r = S.panels[k]
        if r.fn and Draw.inside(r, S.mouse.x, S.mouse.y) then
            -- Under a window, only the window's own.
            local w = Win.at(S.mouse.x, S.mouse.y)
            if not w or (k >= w.panelFrom and k <= w.panelTo) then
                r.fn(S.mouse.x, S.mouse.y)
                S.miniDrag = r
                return
            end
        end
    end
    if Win.press(S.mouse.x, S.mouse.y) then return end
    if S.mode ~= "play" then return end
    for k = #S.panels, 1, -1 do
        if Draw.inside(S.panels[k], S.mouse.x, S.mouse.y) then return end
    end
    if S.over and not S.over.hidden then return end
    if b == 1 or b == 3 then
        S.drag = { x = x, y = y, camx = S.camx, camy = S.camy, moved = false, button = b }
    elseif b == 2 then
        Input.findHover()
        local u = S.selected and S.selected.unit
        if not O.command(S.hover) and u and u.owner == 1 and S.hover and S.hover.id ~= u.cell then Audio.play("deny") end
    end
end

function Input.mousemoved(x, y)
    if S.pinched then return end
    point(x, y)
    if Win.dragging() then Win.move(S.mouse.x, S.mouse.y) return end
    if S.miniDrag and love.mouse.isDown(1) then S.miniDrag.fn(S.mouse.x, S.mouse.y) return end
    local d = S.drag
    if d then
        if not d.moved and (abs(x - d.x) > 4 or abs(y - d.y) > 4) then d.moved = true end
        if d.moved then
            S.camx, S.camy = d.camx - (x - d.x) / S.zoom, d.camy - (y - d.y) / S.zoom
            S.camGoal = nil
            View.clamp()
        end
    end
end

function Input.mousereleased(x, y, b)
    if S.pinched then return end
    point(x, y)
    S.miniDrag = nil
    if Win.dragging() then Win.release() end
    local btn = S.pressed
    S.pressed = nil
    if btn then
        if Draw.inside(btn, S.mouse.x, S.mouse.y) and btn.fn then
            Audio.play("click")
            btn.fn()
        end
        return
    end
    local d = S.drag
    S.drag = nil
    if d and not d.moved and d.button == 1 and S.mode == "play" then
        Input.findHover()
        O.click(S.hover)
    end
end

function Input.wheelmoved(_, dy)
    if S.mode ~= "play" or dy == 0 or Win.modal() or Win.at(S.mouse.x, S.mouse.y) then return end
    View.zoom(dy > 0 and 1 or -1, S.mouse.wx, S.mouse.wy)
end

--- fingers ---------------------------------------------------------------------------

local touches, pinch = {}, nil

-- The two fingers down, apart and between.
local function pair()
    local a, b
    for _, t in pairs(touches) do
        if not a then a = t elseif not b then b = t end
    end
    if not b then return end
    return sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2), (a.x + b.x) / 2, (a.y + b.y) / 2
end

function Input.touchpressed(id, x, y)
    S.touchSeen = true
    Menu.applyTouch()
    touches[id] = { x = x, y = y }
    if S.mode ~= "play" or pinch or Win.modal() or Win.dragging() then return end
    local d, mx, my = pair()
    if d then
        -- The first finger's press, drag or hold on a button ends here.
        S.drag, S.pressed, S.miniDrag = nil, nil, nil
        S.pinched = true
        pinch = { d = math.max(d, 1), mx = mx, my = my }
    end
end

function Input.touchmoved(id, x, y)
    local t = touches[id]
    if not t then return end
    t.x, t.y = x, y
    if not pinch then return end
    local d, mx, my = pair()
    if not d then return end
    View.pan((pinch.mx - mx) / S.zoom, (pinch.my - my) / S.zoom)
    pinch.mx, pinch.my = mx, my
    local steps = log(d / pinch.d) / PINCH_STEP
    if abs(steps) >= 1 then
        View.zoom(steps > 0 and 1 or -1, mx, my)
        pinch.d = d
    end
end

function Input.touchreleased(id)
    touches[id] = nil
    if next(touches) then
        -- One finger left of two: it neither pans nor zooms, and is not a click.
        pinch = nil
        return
    end
    pinch, S.pinched = nil, nil
end

--- keys ------------------------------------------------------------------------------

function Input.keypressed(key)
    if Menu.key(key) then return end
    local is = Settings.is
    if is("fullscreen", key) or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        local mode = Settings.get("mode") == "windowed" and "borderless" or "windowed"
        Settings.set("mode", mode)
        Menu.applyDisplay()
        Settings.save()
        return
    end
    if key == "escape" then
        if Menu.back() then return end
        if S.mode ~= "play" then love.event.quit() return end
        if S.panel then S.panel = nil
        elseif S.selected then O.select(nil)
        else Menu.openPause() end
        return
    end
    if is("sound", key) then O.cycleSound() return end
    -- In the new game window, Enter starts it.
    if S.choosing and not S.ask and not S.settings and (key == "return" or key == "kpenter") then
        S.choosing = false
        S.newGame()
        return
    end
    if Menu.open() then return end
    if S.mode ~= "play" then
        if key == "return" or key == "space" then Menu.titleStart() end
        return
    end
    local u = S.selected and S.selected.unit
    if is("endTurn", key) then O.endTurn() return end
    if is("main", key) or (key == "kpenter" and Settings.key("main") == "return") then
        if love.keyboard.isDown("lshift", "rshift") then O.endTurn() return end
        local _, fn = O.mainAction()
        if fn then fn() end
        return
    end
    if is("grid", key) then O.toggleGrid() return end
    if is("research", key) then S.panel = S.panel == "research" and nil or "research" return end
    if is("capital", key) then
        local cap = S.game:citiesOf(1)[1]
        if cap then O.select(cap, true) end
        return
    end
    if is("zoomIn", key) or key == "kp+" then View.zoom(1, S.mouse.wx, S.mouse.wy) return end
    if is("zoomOut", key) or key == "kp-" then View.zoom(-1, S.mouse.wx, S.mouse.wy) return end
    if is("nextUnit", key) then O.nextUnit(u) return end
    if u then
        for _, a in ipairs(O.actions(u)) do
            if is(a.cmd, key) then
                if not a.off then a.fn() end
                return
            end
        end
    end
end

return Input
