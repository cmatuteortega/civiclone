-- The fabric of a city of several hexes (src/quarters.lua).
local Q = require "src.quarters"
local H = require "src.hex"

local function count(set) local n = 0 for _ in pairs(set) do n = n + 1 end return n end

return {
    { "a city alone stands a tower on every corner, and no gate", function()
        local f = Q.fabric({ { c = 2, r = 2 } })
        assert(count(f[1].towers) == 6 and count(f[1].joins) == 0 and not f[1].gate)
    end },
    { "two hexes share an edge, and the outline's corners are towered once", function()
        local c, r = H.step(2, 2, 0)
        local f = Q.fabric({ { c = 2, r = 2 }, { c = c, r = r } })
        assert(f[1].joins[0] and f[2].joins[3])
        assert(f[2].toward == 3 and f[2].gate == 0)
        -- Ten corners round two hexes, each stood by one of them.
        assert(count(f[1].towers) + count(f[2].towers) == 10)
    end },
    { "where three meet, the corner inside them has no tower", function()
        local c1, r1 = H.step(2, 2, 0)
        local c2, r2 = H.step(2, 2, 1)
        local f = Q.fabric({ { c = 2, r = 2 }, { c = c1, r = r1 }, { c = c2, r = r2 } })
        assert(count(f[1].towers) + count(f[2].towers) + count(f[3].towers) == 12)
        assert(not f[1].towers[1])
    end },
}
