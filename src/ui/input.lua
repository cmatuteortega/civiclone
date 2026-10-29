-- The pointer and the keys. A press on the HUD is the HUD's; on the board a
-- left click chooses (or, with a unit chosen, sends it where it can go), a
-- drag pans, a right click sends the chosen unit, the wheel zooms.

local S = require "src.ui.state"
local View = require "src.ui.view"
local Hud = require "src.ui.hud"
local Draw = require "src.ui.draw"
local O = require "src.ui.orders"

local abs = math.abs

local Input = {}

local function point(x, y)
    S.mouse.wx, S.mouse.wy = x, y
    S.mouse.x, S.mouse.y = math.floor(x / S.uz), math.floor(y / S.uz)
end

-- The hex under the pointer, unless the HUD is.
function Input.findHover()
    S.hover = nil
    if S.mode ~= "play" or not S.world then return end
    if Hud.covers(S.mouse.x, S.mouse.y) then return end
    local i, j = View.toBoard(S.mouse.wx, S.mouse.wy)
    S.hover = S.world:pick(i, j)
end

local function buttonAt(x, y)
    for k = #S.buttons, 1, -1 do
        local b = S.buttons[k]
        if Draw.inside(b, x, y) then return b end
    end
end

function Input.mousepressed(x, y, b)
    point(x, y)
    local btn = buttonAt(S.mouse.x, S.mouse.y)
    if btn then
        S.pressed = btn
        return
    end
    if S.mode ~= "play" then return end
    for k = #S.panels, 1, -1 do
        local r = S.panels[k]
        if Draw.inside(r, S.mouse.x, S.mouse.y) then
            if r.fn then r.fn(S.mouse.x, S.mouse.y) S.miniDrag = r end
            return
        end
    end
    if S.over and not S.over.hidden then return end
    if b == 1 or b == 3 then
        S.drag = { x = x, y = y, camx = S.camx, camy = S.camy, moved = false, button = b }
    elseif b == 2 then
        Input.findHover()
        O.command(S.hover)
    end
end

function Input.mousemoved(x, y)
    point(x, y)
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
    point(x, y)
    S.miniDrag = nil
    local btn = S.pressed
    S.pressed = nil
    if btn then
        if Draw.inside(btn, S.mouse.x, S.mouse.y) and btn.fn then btn.fn() end
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
    if S.mode ~= "play" or dy == 0 then return end
    View.zoom(dy > 0 and 1 or -1, S.mouse.wx, S.mouse.wy)
end

function Input.keypressed(key)
    if key == "f11" or (key == "return" and (love.keyboard.isDown("lalt", "ralt"))) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        return
    end
    if S.mode ~= "play" then
        if key == "return" or key == "space" then S.newGame() end
        if key == "escape" then love.event.quit() end
        return
    end
    local u = S.selected and S.selected.unit
    if key == "escape" then
        if S.panel then S.panel = nil elseif S.selected then O.select(nil) end
        return
    end
    if key == "return" or key == "kpenter" then
        if love.keyboard.isDown("lshift", "rshift") then O.endTurn() return end
        local _, fn = O.mainAction()
        if fn then fn() end
        return
    end
    if key == "g" then S.grid = not S.grid return end
    if key == "t" then S.panel = S.panel == "research" and nil or "research" return end
    if key == "h" then
        local cap = S.game:citiesOf(1)[1]
        if cap then O.select(cap, true) end
        return
    end
    if key == "=" or key == "kp+" then View.zoom(1, S.mouse.wx, S.mouse.wy) return end
    if key == "-" or key == "kp-" then View.zoom(-1, S.mouse.wx, S.mouse.wy) return end
    if key == "tab" then O.nextUnit(u) return end
    if u then
        for _, a in ipairs(O.actions(u)) do
            if (a.key == "SPACE" and key == "space") or (a.key:lower() == key) then
                if not a.off then a.fn() end
                return
            end
        end
    end
end

return Input
