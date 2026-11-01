-- The 3x5 face, lifted from underroot's src/font.lua, which had it from
-- Survive School by way of the frog prototype (caps, digits and a little
-- punctuation). LÖVE's vector font would break the pixel grid inside a canvas
-- this small, so lettering is plotted a pixel at a time like everything else.
-- Text is UTF-8: accented capitals carry their mark on a sixth row, one pixel
-- above the letter. Each letter is drawn out of one picture of them all
-- (src/ui/sheet.lua): the same pixels as a box for each.

local Sheet = require "src.ui.sheet"

local Font = {}

local GW, GH, ADVANCE = 3, 5, 4

local GLYPHS = {
    A = { ".#.", "#.#", "###", "#.#", "#.#" },
    B = { "##.", "#.#", "##.", "#.#", "##." },
    C = { ".##", "#..", "#..", "#..", ".##" },
    D = { "##.", "#.#", "#.#", "#.#", "##." },
    E = { "###", "#..", "##.", "#..", "###" },
    F = { "###", "#..", "##.", "#..", "#.." },
    G = { ".##", "#..", "#.#", "#.#", ".##" },
    H = { "#.#", "#.#", "###", "#.#", "#.#" },
    I = { "###", ".#.", ".#.", ".#.", "###" },
    J = { "..#", "..#", "..#", "#.#", ".#." },
    K = { "#.#", "##.", "#..", "##.", "#.#" },
    L = { "#..", "#..", "#..", "#..", "###" },
    M = { "#.#", "###", "###", "#.#", "#.#" },
    N = { "#.#", "##.", "###", ".##", "#.#" },
    O = { ".#.", "#.#", "#.#", "#.#", ".#." },
    P = { "##.", "#.#", "##.", "#..", "#.." },
    Q = { ".#.", "#.#", "#.#", "##.", ".##" },
    R = { "##.", "#.#", "##.", "#.#", "#.#" },
    S = { ".##", "#..", ".#.", "..#", "##." },
    T = { "###", ".#.", ".#.", ".#.", ".#." },
    U = { "#.#", "#.#", "#.#", "#.#", "###" },
    V = { "#.#", "#.#", "#.#", "#.#", ".#." },
    W = { "#.#", "#.#", "###", "###", "#.#" },
    X = { "#.#", "#.#", ".#.", "#.#", "#.#" },
    Y = { "#.#", "#.#", ".#.", ".#.", ".#." },
    Z = { "###", "..#", ".#.", "#..", "###" },
    ["0"] = { "###", "#.#", "#.#", "#.#", "###" },
    ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
    ["2"] = { "##.", "..#", ".#.", "#..", "###" },
    ["3"] = { "##.", "..#", ".#.", "..#", "##." },
    ["4"] = { "#.#", "#.#", "###", "..#", "..#" },
    ["5"] = { "###", "#..", "##.", "..#", "##." },
    ["6"] = { ".##", "#..", "###", "#.#", "###" },
    ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
    ["8"] = { "###", "#.#", "###", "#.#", "###" },
    ["9"] = { "###", "#.#", "###", "..#", "##." },
    [":"] = { "...", ".#.", "...", ".#.", "..." },
    ["."] = { "...", "...", "...", "...", ".#." },
    ["-"] = { "...", "...", "###", "...", "..." },
    ["/"] = { "..#", "..#", ".#.", "#..", "#.." },
    ["!"] = { ".#.", ".#.", ".#.", "...", ".#." },
    ["?"] = { "##.", "..#", ".#.", "...", ".#." },
    ["+"] = { "...", ".#.", "###", ".#.", "..." },
    [" "] = { "...", "...", "...", "...", "..." },
    ["'"] = { ".#.", ".#.", "...", "...", "..." },
    [","] = { "...", "...", "...", ".#.", "#.." },
    [";"] = { "...", ".#.", "...", ".#.", "#.." },
    ["("] = { ".#.", "#..", "#..", "#..", ".#." },
    [")"] = { ".#.", "..#", "..#", "..#", ".#." },
    ["%"] = { "#.#", "..#", ".#.", "#..", "#.#" },
    ["="] = { "...", "###", "...", "###", "..." },
    ["<"] = { "..#", ".#.", "#..", ".#.", "..#" },
    [">"] = { "#..", ".#.", "..#", ".#.", "#.." },
    ["¡"] = { ".#.", "...", ".#.", ".#.", ".#." },
    ["¿"] = { ".#.", "...", ".#.", "#..", ".##" },
}

-- An accented capital: the letter, under a row for its mark.
local MARK = { ACUTE = "..#", DIAERESIS = "#.#", TILDE = "###" }
for ch, m in pairs({ ["Á"] = { "A", "ACUTE" }, ["É"] = { "E", "ACUTE" }, ["Í"] = { "I", "ACUTE" },
    ["Ó"] = { "O", "ACUTE" }, ["Ú"] = { "U", "ACUTE" }, ["Ü"] = { "U", "DIAERESIS" }, ["Ñ"] = { "N", "TILDE" } }) do
    local g = { MARK[m[2]] }
    for _, row in ipairs(GLYPHS[m[1]]) do g[#g + 1] = row end
    GLYPHS[ch] = g
end
-- Their small letters, written as the capitals (every line is upper case).
local UPPER = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ü"] = "Ü", ["ñ"] = "Ñ" }

-- A character at a time, the bytes of one UTF-8 character together.
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

function Font.has(ch) return GLYPHS[UPPER[ch] or ch:upper()] ~= nil end
Font.CHAR = CHAR

-- How many characters, not bytes.
function Font.length(text)
    local n = 0
    for _ in text:gmatch(CHAR) do n = n + 1 end
    return n
end

-- The first `n` characters.
function Font.cut(text, n)
    local out, k = {}, 0
    for ch in text:gmatch(CHAR) do
        k = k + 1
        if k > n then break end
        out[k] = ch
    end
    return table.concat(out)
end

-- The text broken into lines of at most `n` characters, at the spaces; a
-- word longer than a line is cut. With `most`, no more lines than that.
function Font.wrap(text, n, most)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = Font.cut(word, n)
        elseif Font.length(line) + 1 + Font.length(word) <= n then
            line = line .. " " .. word
        else
            lines[#lines + 1] = line
            line = Font.cut(word, n)
        end
        if most and #lines >= most then break end
    end
    if line ~= "" and not (most and #lines >= most) then lines[#lines + 1] = line end
    return lines
end

function Font.width(text)
    return Font.length(text) * ADVANCE - 1
end

-- Plotted with the colour already set by the caller.
-- A pixel at a time, as it was: where (x, y) is not a whole pixel, which
-- the picture's quads can't be trusted to land on the same pixels as.
local function plot(text, x, y)
    local n = 0
    for ch in text:gmatch(CHAR) do
        local g = GLYPHS[UPPER[ch] or ch:upper()]
        if g then
            local top = #g - GH -- a mark's row above the letter
            for r = 1, #g do
                local row = g[r]
                for c = 1, GW do
                    if row:sub(c, c) == "#" then
                        love.graphics.rectangle("fill", x + n * ADVANCE + c - 1, y + r - 1 - top, 1, 1)
                    end
                end
            end
        end
        n = n + 1
    end
end

for _, g in pairs(GLYPHS) do Sheet.add(g, g, GW, #g, #g - GH) end

function Font.print(text, x, y)
    if x % 1 ~= 0 or y % 1 ~= 0 then return plot(text, x, y) end
    local n = 0
    for ch in text:gmatch(CHAR) do
        local g = GLYPHS[UPPER[ch] or ch:upper()]
        if g then Sheet.draw(g, x + n * ADVANCE, y) end
        n = n + 1
    end
end

return Font
