-- Drawing on a canvas a pixel at a time in the palette: colours by key,
-- filled boxes, framed panels, the 3x5 lettering, buttons the pointer can
-- press, and the little pictures that stand for each kind of unit.

local T = require "src.tracer"
local Font = require "src.font"
local S = require "src.ui.state"

local floor = math.floor

local Draw = {}

function Draw.color(k) love.graphics.setColor(T.RGB[T.IDX[k]]) end
function Draw.rgb(k) return T.RGB[T.IDX[k]] end

function Draw.rect(k, x, y, w, h)
    Draw.color(k)
    love.graphics.rectangle("fill", floor(x), floor(y), w, h)
end

-- A one-pixel frame.
function Draw.frame(k, x, y, w, h)
    Draw.rect(k, x, y, w, 1)
    Draw.rect(k, x, y + h - 1, w, 1)
    Draw.rect(k, x, y, 1, h)
    Draw.rect(k, x + w - 1, y, 1, h)
end

function Draw.text(k, s, x, y)
    Draw.color(k)
    Font.print(s, floor(x), floor(y))
end

-- Text with a dark pixel under and right of every lit one, to read on
-- anything.
function Draw.shadowed(k, s, x, y, shadow)
    Draw.text(shadow or "o", s, x + 1, y + 1)
    Draw.text(k, s, x, y)
end

Draw.width = Font.width

-- A panel: dark, framed in ink with a lighter inner line. Clicks on it stop
-- at it.
function Draw.panel(x, y, w, h)
    Draw.rect("u", x, y, w, h)
    Draw.frame("o", x, y, w, h)
    Draw.frame("n", x + 1, y + 1, w - 2, h - 2)
    S.panels[#S.panels + 1] = { x = x, y = y, w = w, h = h }
end

local function inside(r, x, y) return x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end
Draw.inside = inside

-- A button: a raised box with a label; registered so a click on it calls
-- `fn`. `on`: drawn pressed in (the thing it chooses is chosen). `off`:
-- greyed out and does nothing. Answers whether the pointer is over it.
function Draw.button(label, x, y, w, h, fn, opts)
    opts = opts or {}
    local r = { x = x, y = y, w = w, h = h, fn = (not opts.off) and fn or nil, label = label }
    S.buttons[#S.buttons + 1] = r
    local hot = inside(r, S.mouse.x, S.mouse.y) and not opts.off
    local face = opts.on and "s" or (hot and "t" or "k")
    if opts.off then face = "n" end
    if opts.strong and not opts.off then face = hot and "w" or "c" end
    Draw.rect("o", x, y, w, h)
    Draw.rect(face, x + 1, y + 1, w - 2, h - 2)
    if not opts.on then
        Draw.rect(opts.off and "k" or "w", x + 1, y + 1, w - 2, 1)
        Draw.rect(opts.off and "u" or "n", x + 1, y + h - 2, w - 2, 1)
    end
    local ink = opts.off and "k" or "o"
    if opts.icon then
        Draw.icon(opts.icon, x + 3, y + floor((h - 5) / 2), ink)
        Draw.text(ink, label, x + 10, y + floor((h - 5) / 2))
    elseif opts.left then
        Draw.text(ink, label, x + 3, y + floor((h - 5) / 2))
    else
        Draw.text(ink, label, x + floor((w - Font.width(label)) / 2), y + floor((h - 5) / 2))
    end
    return hot
end

-- Five by five pictures for each kind of unit, for banners and buttons.
local ICONS = {
    warrior = { "...#.", "..##.", ".##..", "##...", "#...." },
    spearman = { "....#", "...#.", "..#..", ".#...", "#...." },
    swordsman = { "....#", "...#.", "#.#..", ".#...", "#.#.." },
    slinger = { ".###.", "#...#", "#...#", ".#.#.", "..#.." },
    archer = { ".##..", "#..#.", "#...#", "#..#.", ".##.." },
    scout = { ".....", ".###.", "#.#.#", ".###.", "....." },
    builder = { "####.", "..#..", "..#..", "..#..", "..#.." },
    settler = { ".###.", "#####", "#####", ".#.#.", "....." },
    horseman = { "...##", "#####", ".###.", ".#.#.", ".#.#." },
    galley = { "..#..", ".##..", "###..", "..#..", "#####" },
    quadrireme = { "..#..", ".###.", "#####", "..#..", "#####" },
    boat = { "..#..", "..##.", "..###", "..#..", ".###." },
    city = { "..#..", ".###.", "#####", "#.#.#", "#####" },
    star = { "..#..", "#####", ".###.", ".#.#.", "#...#" },
    food = { ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".###." },
    prod = { "#...#", ".#.#.", "..#..", ".#.#.", "#...#" },
    gold = { ".###.", "##.##", "#.#.#", "##.##", ".###." },
    science = { "..#..", ".#.#.", "#####", ".#.#.", "..#.." },
    culture = { "#.#.#", ".###.", "##.##", ".###.", "#.#.#" },
    shield = { "#####", "#...#", "#...#", ".#.#.", "..#.." },
    -- The wild's beasts.
    wolf = { "#...#", "##.##", "#####", ".###.", "..#.." },
    bear = { "##.##", "#####", "#.#.#", "#####", ".###." },
    boar = { "#...#", ".###.", "##.##", "#####", ".#.#." },
    aurochs = { "#...#", "#...#", ".###.", ".###.", "..#.." },
    horse = { "..##.", ".###.", "##.#.", "#..#.", "...#." },
    croc = { ".....", "#.#..", "#####", ".####", "....." },
    serpent = { "...#.", "..#.#", "..#..", "#.#.#", ".#.#." },
}
Draw.ICONS = ICONS

function Draw.icon(name, x, y, k)
    local g = ICONS[name]
    if not g then return end
    Draw.color(k or "o")
    for r = 1, 5 do
        for c = 1, 5 do
            if g[r]:sub(c, c) == "#" then love.graphics.rectangle("fill", floor(x) + c - 1, floor(y) + r - 1, 1, 1) end
        end
    end
end

-- A bar `w` long, filled to fraction f.
function Draw.bar(x, y, w, f, k, back)
    Draw.rect(back or "o", x, y, w, 1)
    local n = math.max(0, math.min(w, floor(w * f + 0.5)))
    if n > 0 then Draw.rect(k, x, y, n, 1) end
end

return Draw
