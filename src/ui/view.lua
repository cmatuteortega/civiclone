-- The camera and the canvases it looks through: the board's, at a zoom that
-- goes in and out in whole steps, and the HUD's, at one that stays put.
-- Panning, zooming about a point, and easing towards a hex.

local ffi = require "ffi"
local S = require "src.ui.state"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local View = {}

function View.fit()
    local w, h = love.graphics.getDimensions()
    local base = max(1, floor(min(w, h) / S.SHORT + 0.5))
    S.uz = max(1, floor(min(w, h) / S.UI_SHORT + 0.5))
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
    local m = 40
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
    local w, h = love.graphics.getDimensions()
    local base = max(1, floor(min(w, h) / S.SHORT + 0.5))
    local new = max(-base + 1, min(3, S.zoomStep + step))
    if new == S.zoomStep then return false end
    local bi, bj = x / S.zoom + S.camx, y / S.zoom + S.camy
    S.zoomStep = new
    View.fit()
    S.camx, S.camy = bi - x / S.zoom, bj - y / S.zoom
    View.clamp()
    return true
end

function View.update(dt)
    local k = love.keyboard
    local speed = 260 / S.zoom * dt
    local dx, dy = 0, 0
    if k.isDown("left", "a") then dx = dx - speed end
    if k.isDown("right", "d") then dx = dx + speed end
    if k.isDown("up", "w") then dy = dy - speed end
    if k.isDown("down", "s") then dy = dy + speed end
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
