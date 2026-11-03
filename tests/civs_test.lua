-- How many civilizations a game has, and who they are: the rivals drawn
-- from the pool by the seed, each with its own look, the map grown to hold
-- them all, a kept game bringing back the same leaders, and each leader
-- playing by their leaning (D.CIVS, D.DIPLO.TEMPER).

local Game = require "src.game"
local AI = require "src.ai"
local D = require "src.defs"
local Save = require "src.save"
local Diplo = require "src.diplomacy"
local Mapgen = require "src.mapgen"

return {
    { "every civilization has a key, a look of its own, a known temper and enough city names", function()
        local looks = {}
        local Board = { light = 1, dark = 1, stripe = 1, check = 1, hem = 1, barred = 1 }
        for _, c in ipairs(D.CIVS) do
            assert(D.CIV[c.key] == c, c.name)
            assert(not looks[c.look], "two civilizations look the same: " .. c.look)
            looks[c.look] = true
            assert(Board[c.look], "no banner for " .. c.look)
            assert(D.DIPLO.TEMPER[c.temper], "no such temper as " .. tostring(c.temper))
            assert(#c.cities >= 7, c.name .. " has too few city names")
        end
        assert(D.CIVS[1].key == "aurelia" and D.CIVS[1].look == "light", "the player is Aurelia, in light cloth")
        assert(D.CIV_COUNTS.max == #D.CIVS)
    end },
    { "the rivals are drawn by the seed, never twice, the player always first", function()
        for n = D.CIV_COUNTS.min, D.CIV_COUNTS.max do
            for _, seed in ipairs({ 1, 2, 3, 77 }) do
                local a, b = Game.civsFor(n, seed), Game.civsFor(n, seed)
                assert(#a == n and a[1] == D.CIVS[1])
                local seen = {}
                for k, c in ipairs(a) do
                    assert(b[k] == c, "the same seed draws the same rivals")
                    assert(not seen[c.key], "drawn twice: " .. c.key)
                    seen[c.key] = true
                end
            end
        end
        -- Different seeds bring different rivals, some of the time.
        local firsts = {}
        for seed = 1, 40 do firsts[Game.civsFor(2, seed)[2].key] = true end
        local n = 0
        for _ in pairs(firsts) do n = n + 1 end
        assert(n >= 4, "a two-civilization game meets most of the rivals over forty seeds: " .. n)
        -- Rivals asked for by name come first.
        local named = Game.civsFor(3, 9, { "reedholm", "drift" })
        assert(named[2].key == "reedholm" and named[3].key == "drift")
    end },
    { "the map grows with the civilizations, and has room for every one of them", function()
        for n = D.CIV_COUNTS.min, D.CIV_COUNTS.max do
            local cols, rows = D.mapFor(n)
            for _, seed in ipairs({ 3, 5, 8, 21, 40 }) do
                local map = Mapgen.generate(cols, rows, seed, n)
                assert(#map.starts == n)
            end
        end
        local g = Game.new({ seed = 4, civs = 6, wild = false, cataclysm = false })
        assert(#g.players == 6 and g.cols == D.mapFor(6))
        for k, p in ipairs(g.players) do
            assert(p.id == k and p.civKey == p.civ.key)
            assert(#g:unitsOf(k) >= 2, "everyone starts with a settler and a band")
        end
        -- Out of bounds is held to the bounds.
        assert(#Game.new({ seed = 4, civs = 9, wild = false, cataclysm = false }).players == D.CIV_COUNTS.max)
        assert(#Game.new({ seed = 4, civs = 1, wild = false, cataclysm = false }).players == D.CIV_COUNTS.min)
    end },
    { "a kept game brings back the same leaders, and an old one without keys still reads", function()
        local g = Game.new({ seed = 12, civs = 5, cataclysm = false })
        for _ = 1, 3 do
            AI.play(g, g.players[1])
            g:endTurn(AI)
        end
        local back = assert(Save.decode(Save.encode(g)))
        for k, p in ipairs(g.players) do assert(back.players[k].civ == p.civ, p.name) end
        -- Kept before there was a pool: the first three, by place.
        local old = Game.new({ seed = 12, civs = 3, cataclysm = false, rivals = { "umbra", "varro" } })
        for _, p in ipairs(old.players) do p.civKey = nil end
        local back2 = assert(Save.decode(Save.encode(old)))
        assert(back2.players[2].civ == D.CIV.umbra and back2.players[3].civ == D.CIV.varro)
    end },
    { "six civilizations, the computer on every side, play a long game through", function()
        for _, seed in ipairs({ 6, 31 }) do
            local g = Game.new({ seed = seed, civs = 6, allAI = true })
            for _ = 1, 90 do
                AI.play(g, g.players[1])
                g:endTurn(AI)
            end
            local cities = 0
            for _, p in ipairs(g.players) do cities = cities + #g:citiesOf(p.id) end
            assert(cities >= 12, "the world filled up: " .. cities)
            for _, u in ipairs(g.units) do assert(g:slot(u)[u.cell] == u) end
        end
    end },
    { "Brannoch sends out more settlers than Tess, and Nocta's army is the mightier", function()
        local made = { thistle = {}, varro = {}, umbra = {} }
        local might = { thistle = 0, umbra = 0 }
        for _, seed in ipairs({ 2, 9, 14, 20 }) do
            local g = Game.new({ seed = seed, civs = 4, allAI = true, cataclysm = false,
                rivals = seed % 2 == 0 and { "thistle", "varro", "umbra" } or { "umbra", "thistle", "varro" } })
            local add = g.addUnit
            g.addUnit = function(self, kind, owner, ...)
                local m = made[self.players[owner].civ.key]
                if m then m[kind] = (m[kind] or 0) + 1 end
                return add(self, kind, owner, ...)
            end
            for _ = 1, 70 do
                AI.play(g, g.players[1])
                g:endTurn(AI)
            end
            for k, p in ipairs(g.players) do
                if might[p.civ.key] then might[p.civ.key] = might[p.civ.key] + Diplo.army(g, k) end
            end
        end
        local tb, vb = made.thistle.settler or 0, made.varro.settler or 0
        assert(tb > vb, ("settlers: Brannoch %d, Tess %d"):format(tb, vb))
        assert(might.umbra > might.thistle, ("might: Nocta %d, Brannoch %d"):format(might.umbra, might.thistle))
    end },
    { "Tess looks for the hills to settle on, Sedge for the water, more than one who leans no way", function()
        local g = Game.new({ seed = 2, civs = 5, allAI = true, cataclysm = false, wild = false,
            rivals = { "varro", "reedholm", "umbra", "thistle" } })
        local function wet(c) return g:coastal(c) or (c.river and next(c.river)) end
        local tess, sedge, nocta, noctaWet = 0, 0, 0, 0
        for id = 1, #g.cells, 5 do
            local cell = g.cells[id]
            if g:passable(cell) and not g:isWater(cell) and not g.civ[id] then
                local u = g:addUnit("settler", 2, id)
                local function site(owner)
                    u.owner = owner
                    return AI.siteFor(g, u)
                end
                local s = site(2)
                if s and s.elev == "hills" then tess = tess + 1 end
                s = site(3)
                if s and wet(s) then sedge = sedge + 1 end
                s = site(4)
                if s and s.elev == "hills" then nocta = nocta + 1 end
                if s and wet(s) then noctaWet = noctaWet + 1 end
                u.owner = 2
                g:removeUnit(u)
            end
        end
        assert(tess > nocta * 1.5, ("Tess on the hills %d, Nocta %d"):format(tess, nocta))
        assert(sedge > noctaWet, ("Sedge by water %d, Nocta %d"):format(sedge, noctaWet))
    end },
    { "a closed leader will not open borders to an acquaintance; a kindly one asks sooner", function()
        local g = Game.new({ seed = 3, civs = 3, wild = false, cataclysm = false, allAI = true,
            rivals = { "reedholm", "thistle" } })
        Diplo.meet(g, 2, 3)
        Diplo.meet(g, 1, 2)
        -- Reedholm thinks well of them, but not well enough.
        local ok, why = Diplo.consider(g, 2, 1, "borders")
        assert(not ok and why == "WE KEEP TO OURSELVES.", why)
        assert(Diplo.temper(g, 3).friends < 20 and Diplo.temper(g, 3).gift < 30)
        -- An opportunist hates one already at war with another.
        local o = Game.new({ seed = 3, civs = 4, wild = false, cataclysm = false, allAI = true,
            rivals = { "drift", "umbra", "varro" } })
        for a = 1, 4 do for b = a + 1, 4 do Diplo.meet(o, a, b) end end
        local before = Diplo.regard(o, 2, 4)
        o.turn = D.DIPLO.warFrom
        Diplo.declare(o, 3, 4, "grudge")
        assert(Diplo.regard(o, 2, 4) < before, "the Khan's eye is on the beset")
    end },
}
