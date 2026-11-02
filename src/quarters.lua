-- A city's quarters: the hexes it spills over into as it grows, past what
-- its middle hex can house. This is how they are laid together, the part
-- the rules and the pictures share: which of a hex's edges it shares with
-- another of the city's hexes (a street runs across, no wall stands on it),
-- which corners of the city's outline carry its towers (each tower stood
-- once, by one hex), the way each quarter's street comes in from the hex it
-- grew out of, and the gate where the street leaves on the far side.
--
-- Edge k of a hex faces neighbour k (src/hex.lua: 0 east, then clockwise);
-- its corner k is the one at 60k - 30 degrees, between edges k - 1 and k.

local H = require "src.hex"

local Q = {}

-- The stages a quarter fills in by, as the citizens it houses come: the
-- houses nearest the hex it grew out of first, out to its far edge.
Q.STAGES = 3
Q.HOUSES = { 4, 7, 11 }

local function key(c, r) return c .. ":" .. r end

-- `hexes`: the city's hexes in the order it took them, the middle first,
-- each { c = , r = , ... }. Answers, for each in the same order:
-- { joins = { [k] = true }, towers = { [k] = true }, toward = k or nil,
--   gate = k or nil }.
function Q.fabric(hexes)
    local at = {}
    for n, h in ipairs(hexes) do at[key(h.c, h.r)] = n end
    local function inside(c, r) return at[key(c, r)] end
    local out = {}
    for n, h in ipairs(hexes) do
        local f = { joins = {}, towers = {} }
        local nb = {}
        for k = 0, 5 do
            nb[k] = inside(H.step(h.c, h.r, k))
            if nb[k] then f.joins[k] = true end
        end
        -- The street comes in from the hex it grew out of: the earliest
        -- of the city's hexes beside it.
        if n > 1 then
            local best
            for k = 0, 5 do
                if nb[k] and nb[k] < n and (not best or nb[k] < nb[best]) then best = k end
            end
            f.toward = best
            -- And goes on out through the far side, where nothing of the
            -- city's stands.
            if best and not nb[(best + 3) % 6] then f.gate = (best + 3) % 6 end
        end
        -- Corner k is on the city's outline if one or two of the three hexes
        -- meeting there are the city's; the lowest of them stands the tower.
        for k = 0, 5 do
            local a, b = nb[(k + 5) % 6], nb[k]
            local count = 1 + (a and 1 or 0) + (b and 1 or 0)
            if count < 3 and n <= math.min(a or n, b or n) then f.towers[k] = true end
        end
        out[n] = f
    end
    return out
end

return Q
