-- The pointer, drawn as everything else is: in the palette's ink and
-- cream, a pixel of it as big as a pixel of the HUD, so it sits on the same
-- grid as the lettering and the panels. An arrow, and a hand over what can
-- be pressed.
--
-- It is the system's own pointer given these pictures (love.mouse.newCursor),
-- not one drawn into the frame, so it moves as soon as the mouse does,
-- however slow the frame. The POINTER setting (src/settings.lua) has it
-- PIXEL, PIXEL LARGE (twice the size) or the SYSTEM's own. Where the system
-- has no pointer to give pictures to (a phone), nothing is done.

local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Settings = require "src.settings"

local Cursor = {}

-- Each picture: its rows (o ink, w cream, . clear) and the pixel that points.
Cursor.SHAPES = {
    arrow = {
        hot = { 0, 0 },
        "o..........",
        "oo.........",
        "owo........",
        "owwo.......",
        "owwwo......",
        "owwwwo.....",
        "owwwwwo....",
        "owwwwwwo...",
        "owwwwwwwo..",
        "owwwwwoooo.",
        "owwowwo....",
        "owo.owwo...",
        "oo..owwo...",
        "o....owwo..",
        ".....owwo..",
        "......oo...",
    },
    hand = {
        hot = { 4, 0 },
        "....oo.......",
        "...owwo......",
        "...owwo......",
        "...owwo......",
        "...owwoooo...",
        "...owwowwoooo",
        "oo.owwowwowwo",
        "owoowwwwwwwwo",
        "owwowwwwwwwwo",
        ".owwwwwwwwwwo",
        "..owwwwwwwwwo",
        "..owwwwwwwwo.",
        "...owwwwwwwo.",
        "...owwwwwwo..",
        "....owwwwwo..",
        "....oooooo...",
    },
}

local made = {}     -- the cursors made, by shape and size
local shown         -- what is set now: "arrow@3", or "system"

-- Shape `name` at `z` screen pixels a pixel, as LÖVE image data.
function Cursor.image(name, z)
    local shape = Cursor.SHAPES[name]
    local h, w = #shape, #shape[1]
    local data = love.image.newImageData(w * z, h * z)
    local ink, cream = Draw.rgb("o"), Draw.rgb("w")
    for j = 1, h do
        local row = shape[j]
        for i = 1, w do
            local ch = row:sub(i, i)
            local c = ch == "o" and ink or (ch == "w" and cream or nil)
            if c then
                for dy = 0, z - 1 do
                    for dx = 0, z - 1 do data:setPixel((i - 1) * z + dx, (j - 1) * z + dy, c[1], c[2], c[3], 1) end
                end
            end
        end
    end
    return data
end

local function get(name, z)
    local key = name .. "@" .. z
    if made[key] == nil then
        local shape = Cursor.SHAPES[name]
        local ok, c = pcall(love.mouse.newCursor, Cursor.image(name, z), shape.hot[1] * z, shape.hot[2] * z)
        made[key] = ok and c or false
    end
    return made[key] or nil, key
end

-- Is the pointer over something that can be pressed (as the HUD was last
-- drawn)?
local function overButton()
    local mx, my = S.mouse.x, S.mouse.y
    for _, b in ipairs(S.buttons or {}) do
        if b.fn and Draw.inside(b, mx, my) then return true end
    end
    return false
end

-- Each frame: the picture the pointer should have now.
function Cursor.update()
    if not (love.mouse and love.mouse.isCursorSupported and love.mouse.isCursorSupported()) then return end
    local mode = Settings.get("pointer")
    if mode == "system" or S.phone then
        if shown ~= "system" then
            love.mouse.setCursor()
            shown = "system"
        end
        return
    end
    local z = math.max(1, S.uz or 1) * (mode == "large" and 2 or 1)
    local c, key = get(overButton() and "hand" or "arrow", z)
    if key ~= shown then
        if c then love.mouse.setCursor(c) else love.mouse.setCursor() end
        shown = key
    end
end

return Cursor
