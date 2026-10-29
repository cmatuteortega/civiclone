-- The whole palette: eight colours, darkest to lightest, and nothing is drawn
-- outside this list.
--
-- Underroot's rule, kept: a pixel's colour is *chosen* off a short ramp of
-- these, never blended, and there is no alpha anywhere. Eight steps of one
-- warm sepia, like a map drawn on old paper, so what tells grassland from
-- desert, or one civilization's warrior from another's, is value and pattern
-- rather than hue.
--
-- Each key also names the key one step darker (`darker`) and one step lighter
-- (`lighter`): fog of war is the world one step darker, a highlighted hex one
-- step lighter.

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

local Palette = {}

-- key, colour, one step darker, one step lighter.
Palette.list = {
    { "o", "292418", "o", "u" }, -- ink: outlines, the deep sea's shadow
    { "u", "524839", "o", "n" }, -- umber: the deep sea, forest shade
    { "n", "73654a", "u", "k" }, -- brown: coast, soil, forest
    { "k", "8b7d62", "n", "t" }, -- khaki: grassland
    { "t", "a48d6a", "k", "s" }, -- tan: plains
    { "s", "bda583", "t", "c" }, -- sand: rock, desert in shade
    { "c", "cdba94", "s", "w" }, -- cream: desert, paper
    { "w", "e6ceac", "c", "w" }, -- white: snow, glints, the player's colours
}

Palette.key, Palette.darker, Palette.lighter = {}, {}, {}
for _, row in ipairs(Palette.list) do
    Palette.key[row[1]] = hex(row[2])
    Palette.darker[row[1]] = row[3]
    Palette.lighter[row[1]] = row[4]
end

return Palette
