-- The camera and the canvases it looks through: the board's, at a zoom that
-- goes in and out in whole steps, and the HUD's, at one that stays put.
-- Panning, zooming about a point, and easing towards a hex.

local ffi = require "ffi"
local S = require "src.ui.state"
local Settings = require "src.settings"
local T = require "src.tracer"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local View = {}

-- The board's zoom before any steps in or out: as set, or the whole number
-- that makes the window's short edge nearest S.SHORT of its pixels.
function View.baseZoom()
    local w, h = love.graphics.getDimensions()
    local set = Settings.get("mapScale") or 0
    if set > 0 then return max(1, min(set, floor(min(w, h) / 200))) end
    return max(1, floor(min(w, h) / S.SHORT + 0.5))
end

-- The HUD's zoom: as set (as far as leaves the HUD room enough), else picked
-- off the short edge likewise.
function View.uiZoom()
    local w, h = love.graphics.getDimensions()
    local set = Settings.get("uiScale") or 0
    if set > 0 then
        local most = max(1, min(floor(w / 300), floor(h / 180)))
        return max(1, min(set, most))
    end
    return max(1, floor(min(w, h) / (S.phone and S.UI_SHORT_PHONE or S.UI_SHORT) + 0.5))
end

function View.fit()
    local w, h = love.graphics.getDimensions()
    local base = View.baseZoom()
    S.uz = View.uiZoom()
    S.vw, S.vh = ceil(w / S.uz), ceil(h / S.uz)
    S.ui = love.graphics.newCanvas(S.vw, S.vh)
    S.ui:setFilter("nearest", "nearest")
    S.zoom = max(1, base + S.zoomStep)
    S.cw, S.ch = ceil(w / S.zoom), ceil(h / S.zoom)
    S.canvas = love.graphics.newCanvas(S.cw, S.ch)
    S.canvas:setFilter("nearest", "nearest")
    -- The overlay: one byte-for-byte picture of everything laid over the
    -- board this frame. A pixel is either covered, fully, or not there.
    S.overlay = love.image.newImageData(S.cw, S.ch, "rgba8")
    S.opx = ffi.cast("uint8_t*", S.overlay:getFFIPointer())
    S.overlayImage = love.graphics.newImage(S.overlay)
    S.overlayImage:setFilter("nearest", "nearest")
    View.clamp()
end

-- Keeps the camera over the map, with a little room past its edges.
function View.clamp()
    if not S.world then return end
    local m = 40 / T.UNIT
    local w, h = S.world.w, S.world.h
    if w + 2 * m <= S.cw then S.camx = (w - S.cw) / 2
    else S.camx = max(-m, min(w - S.cw + m, S.camx)) end
    if h + 2 * m <= S.ch then S.camy = (h - S.ch) / 2
    else S.camy = max(-m, min(h - S.ch + m, S.camy)) end
end

-- The board picture's pixel under window pixel (x, y).
function View.toBoard(x, y)
    return floor(x / S.zoom + floor(S.camx)), floor(y / S.zoom + floor(S.camy))
end

-- The HUD pixel over board picture pixel (i, j).
function View.toHud(i, j)
    return floor((i - floor(S.camx)) * S.zoom / S.uz), floor((j - floor(S.camy)) * S.zoom / S.uz)
end

-- Sets where the camera should ease to: hex `cell` in the middle.
function View.lookAt(cell, now)
    local i, j = S.world:toImage(cell.x, cell.top, cell.z)
    S.camGoal = { i - S.cw / 2, j - S.ch / 2 }
    if now then
        S.camx, S.camy = S.camGoal[1], S.camGoal[2]
        S.camGoal = nil
        View.clamp()
    end
end

function View.pan(dx, dy)
    S.camx, S.camy = S.camx + dx, S.camy + dy
    S.camGoal = nil
    View.clamp()
end

-- Zooms a step in or out, keeping the board pixel under window pixel
-- (x, y) where it is. Says whether it changed.
function View.zoom(step, x, y)
    local base = View.baseZoom()
    local new = max(-base + 1, min(3, S.zoomStep + step))
    if new == S.zoomStep then return false end
    local bi, bj = x / S.zoom + S.camx, y / S.zoom + S.camy
    S.zoomStep = new
    View.fit()
    S.camx, S.camy = bi - x / S.zoom, bj - y / S.zoom
    View.clamp()
    return true
end

-- How near the window's edge, in its pixels, the pointer pans the camera.
local EDGE = 3

function View.update(dt)
    local k = love.keyboard
    local speed = 260 / S.zoom * dt * Settings.get("panSpeed")
    local dx, dy = 0, 0
    if not S.menuOpen then
        if k.isDown("left", Settings.key("panLeft")) then dx = dx - speed end
        if k.isDown("right", Settings.key("panRight")) then dx = dx + speed end
        if k.isDown("up", Settings.key("panUp")) then dy = dy - speed end
        if k.isDown("down", Settings.key("panDown")) then dy = dy + speed end
    end
    if Settings.get("edgePan") and not S.touch and not S.menuOpen and not S.drag
        and love.window.hasMouseFocus() then
        local mx, my = love.mouse.getPosition()
        local w, h = love.graphics.getDimensions()
        if mx < EDGE then dx = dx - speed elseif mx >= w - EDGE then dx = dx + speed end
        if my < EDGE then dy = dy - speed elseif my >= h - EDGE then dy = dy + speed end
    end
    if dx ~= 0 or dy ~= 0 then View.pan(dx, dy) end
    if S.camGoal then
        local f = min(1, dt * 8)
        S.camx = S.camx + (S.camGoal[1] - S.camx) * f
        S.camy = S.camy + (S.camGoal[2] - S.camy) * f
        if math.abs(S.camGoal[1] - S.camx) < 0.5 and math.abs(S.camGoal[2] - S.camy) < 0.5 then S.camGoal = nil end
        View.clamp()
    end
end

return View
