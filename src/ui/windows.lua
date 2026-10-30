-- Windows: the HUD's panels as a desktop's windows. Each has a title bar to
-- drag it by (snapping to the screen's edges), a close button, and a place in
-- the stack: a click anywhere on one brings it to the front, and one that
-- opens comes up on top. Where the player leaves a window is kept between
-- games (src/settings.lua), as a fraction of the room the screen leaves it,
-- so it stays put through a resize. A double click on the title bar sends it
-- back to its own place.
--
-- They are drawn as the HUD is, afresh each frame: whatever shows a window
-- adds it with Win.add, and Win.flush draws them all, back to front, after
-- everything else -- so their buttons, registered in that order, are pressed
-- front first. A modal window (the menu, the settings, a question) dithers
-- out all behind it, and nothing behind it can be pressed.

local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Font = require "src.font"
local Settings = require "src.settings"

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local Win = {}

-- The title bar's height; a window's own drawing starts below it.
Win.BAR = 10
-- How near an edge a dragged window jumps to it.
local SNAP = 5

local frame = {}         -- the windows added this frame
local shown = {}         -- what was shown last frame, by id
local z, zTop = {}, 0    -- the stack: higher is nearer
local drag               -- { id, dx, dy } while one is dragged
local lastClick = { t = -1 }
local dither, ditherW, ditherH

-- The top of the room windows may use: below the top bar while playing.
local function topEdge() return S.mode == "play" and 11 or 0 end

function Win.raise(id)
    zTop = zTop + 1
    z[id] = zTop
end

-- Where window `w` goes this frame: where it was dragged to, else where the
-- player left it, else its own place; always wholly on the screen.
local function place(w)
    local top = topEdge()
    local roomX, roomY = max(0, S.vw - w.w), max(0, S.vh - top - w.h)
    local x, y
    if drag and drag.id == w.id and drag.x then
        x, y = drag.x, drag.y
    else
        local f = Settings.window(w.id)
        if f and not w.fixed then x, y = f[1] * roomX, top + f[2] * roomY
        else x, y = w.x, w.y end
    end
    return floor(max(0, min(roomX, x))), floor(max(top, min(top + roomY, y)))
end

-- Adds a window to this frame:
--   id, title, w, h   what it is and its size, title bar and all
--   x, y              its own place, where it opens before it's moved
--   draw(x, y, w, h)  draws what's in it, given the room below the title bar
--   close             what the close button does (none: no button)
--   modal             dims everything behind it, which can't be pressed
--   fixed             can't be moved
function Win.add(w)
    frame[#frame + 1] = w
    if not shown[w.id] then Win.raise(w.id) end
end

local function chrome(w)
    local x, y = w.px, w.py
    Draw.rect("u", x, y, w.w, w.h)
    Draw.frame("o", x, y, w.w, w.h)
    Draw.frame("n", x + 1, y + 1, w.w - 2, w.h - 2)
    -- The title bar: lighter while it's the front window or being dragged.
    local front = w.front
    Draw.rect(front and "k" or "n", x + 1, y + 1, w.w - 2, Win.BAR - 1)
    Draw.rect("o", x + 1, y + Win.BAR, w.w - 2, 1)
    local title = w.title or ""
    local room = w.w - 8 - (w.close and 12 or 0)
    title = Font.cut(title, floor(room / 4))
    Draw.text(front and "w" or "c", title, x + 4, y + 3)
    -- A grip of dots, to say it can be dragged.
    if not w.fixed and not Settings.get("lockWindows") then
        local gx0 = x + 6 + Font.width(title)
        local gx1 = x + w.w - (w.close and 15 or 5)
        for gx = gx0, gx1 - 1, 2 do
            Draw.rect(front and "t" or "k", gx, y + 4, 1, 1)
            Draw.rect(front and "t" or "k", gx + 1, y + 6, 1, 1)
        end
    end
    if w.close then Draw.button("X", x + w.w - 11, y + 1, 9, 8, w.close) end
    S.panels[#S.panels + 1] = { x = x, y = y, w = w.w, h = w.h }
end

-- Every other pixel of the HUD in ink, made once a size.
local function backdrop()
    if not dither or ditherW ~= S.vw or ditherH ~= S.vh then
        local data = love.image.newImageData(S.vw, S.vh)
        local ink = Draw.rgb("o")
        data:mapPixel(function(i, j)
            if (i + j) % 2 == 0 then return ink[1], ink[2], ink[3], 1 end
            return 0, 0, 0, 0
        end)
        dither = love.graphics.newImage(data)
        dither:setFilter("nearest", "nearest")
        ditherW, ditherH = S.vw, S.vh
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(dither, 0, 0)
end

-- Draws this frame's windows, back to front, modal ones over a dimmed screen.
function Win.flush()
    local list = frame
    frame = {}
    table.sort(list, function(a, b)
        if (a.modal or false) ~= (b.modal or false) then return not a.modal end
        return (z[a.id] or 0) < (z[b.id] or 0)
    end)
    shown = {}
    Win.rects, Win.modalFrom = {}, nil
    local frontId = list[#list] and list[#list].id
    for _, w in ipairs(list) do
        shown[w.id] = true
        if w.modal then
            -- Each modal window dims what's behind it, other modal ones too,
            -- and what was registered before it can't be pressed.
            backdrop()
            Win.modalFrom = { buttons = #S.buttons + 1, panels = #S.panels + 1 }
        end
        w.px, w.py = place(w)
        w.front = w.id == frontId or (drag and drag.id == w.id)
        w.panelFrom = #S.panels + 1
        chrome(w)
        w.draw(w.px, w.py + Win.BAR + 1, w.w, w.h - Win.BAR - 1)
        w.panelTo = #S.panels
        Win.rects[#Win.rects + 1] = w
    end
    if drag and not shown[drag.id] then drag = nil end
end

-- The front window under HUD pixel (x, y), if any.
function Win.at(x, y)
    for k = #(Win.rects or {}), 1, -1 do
        local w = Win.rects[k]
        if x >= w.px and y >= w.py and x < w.px + w.w and y < w.py + w.h then return w end
    end
end

function Win.modal() return Win.modalFrom ~= nil end
function Win.dragging() return drag ~= nil end
function Win.isShown(id) return shown[id] == true end

-- A press at HUD pixel (x, y) after the buttons have had it: brings the window
-- there to the front, and starts dragging it by its title bar. Answers whether
-- the press stops here -- on a window, or anywhere while one is modal.
function Win.press(x, y)
    local w = Win.at(x, y)
    if not w then return Win.modal() end
    -- Behind a modal window, a window is only looked at.
    if Win.modal() and w ~= Win.rects[#Win.rects] then return true end
    Win.raise(w.id)
    if y < w.py + Win.BAR and not w.fixed and not Settings.get("lockWindows") then
        local now = love.timer.getTime()
        if lastClick.id == w.id and now - lastClick.t < 0.35 then
            -- A double click: back to its own place.
            Settings.setWindow(w.id, nil)
            Settings.save()
            lastClick = { t = -1 }
            return true
        end
        lastClick = { id = w.id, t = now }
        drag = { id = w.id, dx = x - w.px, dy = y - w.py, w = w.w, h = w.h }
    end
    return true
end

-- The pointer moved to HUD pixel (x, y) with a window held.
function Win.move(x, y)
    if not drag then return end
    local top = topEdge()
    local nx, ny = x - drag.dx, y - drag.dy
    if Settings.get("snapWindows") then
        if abs(nx) < SNAP then nx = 0 end
        if abs(nx + drag.w - S.vw) < SNAP then nx = S.vw - drag.w end
        if abs(ny - top) < SNAP then ny = top end
        if abs(ny + drag.h - S.vh) < SNAP then ny = S.vh - drag.h end
    end
    drag.x = max(0, min(S.vw - drag.w, nx))
    drag.y = max(top, min(S.vh - drag.h, ny))
end

-- Let go: the window is kept where it is.
function Win.release()
    local d = drag
    drag = nil
    if not (d and d.x) then return end
    local top = topEdge()
    local roomX, roomY = S.vw - d.w, S.vh - top - d.h
    Settings.setWindow(d.id, roomX > 0 and d.x / roomX or 0, roomY > 0 and (d.y - top) / roomY or 0)
    Settings.save()
end

return Win
