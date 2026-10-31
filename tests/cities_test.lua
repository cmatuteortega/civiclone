local M = require "src.models"

local function storeys(lay)
    local n = 0
    for _, h in ipairs(lay.houses) do n = n + h.storeys end
    return n
end

return {
    { "a city's tier follows its citizens", function()
        assert(M.cityTier(1) == 1 and M.cityTier(2) == 1)
        assert(M.cityTier(3) == 2 and M.cityTier(5) == 2)
        assert(M.cityTier(6) == 3 and M.cityTier(9) == 3)
        assert(M.cityTier(10) == 4 and M.cityTier(30) == 4)
    end },
    { "a growing city never loses a floor", function()
        for _, biome in ipairs({ "grass", "plains", "desert" }) do
            for _, hills in ipairs({ false, true }) do
                for seed = 0, 3 do
                    local site = { biome = biome, hills = hills, seed = seed }
                    local last = 0
                    for pop = 1, 20 do
                        local n = storeys(M.cityLayout(pop, {}, site))
                        assert(n >= last, ("%s %s seed %d: %d floors at %d, %d before"):format(
                            biome, tostring(hills), seed, n, pop, last))
                        last = n
                    end
                end
            end
        end
    end },
    { "no house stands in a river's channel, nor where a building is", function()
        local site = { biome = "grass", river = { [1] = 2.5, [2] = 2.5 }, seed = 1 }
        local lay = M.cityLayout(14, { granary = true, market = true }, site)
        for _, h in ipairs(lay.houses) do
            local p = M.CITY_PLOTS[h.plot]
            for _, e in ipairs(p.edges) do assert(not site.river[e], "house on river edge " .. e) end
            assert(h.plot ~= 4 and h.plot ~= 5, "house on a building's plot")
        end
    end },
    { "every kind of city can be painted", function()
        for _, biome in ipairs({ "grass", "plains", "desert" }) do
            for _, pop in ipairs({ 1, 4, 7, 12 }) do
                local site = { biome = biome, hills = pop == 7, river = pop == 4 and { [0] = 2 } or nil, seed = pop % 4 }
                local pic = M.city("stripe", pop, pop == 12, { walls = pop == 12, harbour = true }, pop == 1 and 1 or nil, 6,
                    site)
                assert(pic.w > 0 and pic.h > 0)
                assert(#M.cityChimneys(pop, {}, site) >= 1)
            end
        end
    end },
}
