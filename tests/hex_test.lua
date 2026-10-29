local H = require "src.hex"

return {
    { "each neighbour is one step away, and back", function()
        for _, at in ipairs({ { 4, 4 }, { 5, 5 }, { 0, 1 } }) do
            for k = 0, 5 do
                local c, r = H.step(at[1], at[2], k)
                assert(H.distance(at[1], at[2], c, r) == 1)
                assert(H.dirTo(at[1], at[2], c, r) == k)
                local bc, br = H.step(c, r, (k + 3) % 6)
                assert(bc == at[1] and br == at[2], "opposite direction leads back")
            end
        end
    end },
    { "a room point maps to the hex it is over", function()
        for r = 0, 6 do
            for c = 0, 6 do
                local x, z = H.center(c, r)
                local pc, pr = H.at(x, z)
                assert(pc == c and pr == r)
                -- Just inside the east edge is still this hex.
                local ec, er = H.at(x + H.APOTHEM - 0.3, z)
                assert(ec == c and er == r)
            end
        end
    end },
    { "a range of n holds 1 + 3n(n+1) hexes, nearest first", function()
        local list = H.range(5, 5, 2)
        assert(#list == 19)
        assert(list[1][1] == 5 and list[1][2] == 5)
        for k = 2, 7 do assert(H.distance(5, 5, list[k][1], list[k][2]) == 1) end
    end },
    { "the inset is zero on an edge and the apothem in the middle", function()
        local x, z = H.center(3, 3)
        assert(math.abs(H.inset(x, z, x, z) - H.APOTHEM) < 1e-9)
        assert(math.abs(H.inset(x + H.APOTHEM, z, x, z)) < 1e-9)
    end },
}
