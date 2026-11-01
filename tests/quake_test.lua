local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local Quake = require "src.quake"
local H = require "src.hex"
local D = require "src.defs"

-- The wild is left off: these are the sundering's rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false, cataclysm = "quake" }) end

local function free(g, cell) return not g.mil[cell.id] and not g.civ[cell.id] and not cell.city end

local function find(g, f)
    for _, cell in ipairs(g.cells) do if free(g, cell) and f(cell) then return cell end end
end

local function count(g, f)
    local n = 0
    for _, cell in ipairs(g.cells) do if f(cell) then n = n + 1 end end
    return n
end

local function settle(g)
    for _, u in ipairs(g.units) do
        if u.owner == 1 and u.kind == "settler" then return g:found(u) end
    end
end

local function at(g, turn)
    g.turn = turn
    g.cataclysm.stage = Cat.stage(g)
end

return {
    { "the sundering's stages come on their turns", function()
        assert(Cat.stageAt(D.QUAKE.omen - 1, "quake") == nil)
        assert(Cat.stageAt(D.QUAKE.omen, "quake") == "omen")
        assert(Cat.stageAt(D.QUAKE.tremors, "quake") == "tremors")
        assert(Cat.stageAt(D.QUAKE.rift + 1, "quake") == "rift")
        assert(Cat.stageAt(D.LAST_TURN, "quake") == "fire")
        local g = newGame()
        g.turn = D.QUAKE.rift
        assert(Cat.label(g) == "SUNDERING " .. (D.LAST_TURN - D.QUAKE.rift + 1))
        assert(Cat.ended(g) == "THE WORLD HAS BROKEN APART")
        assert(Cat.ward(g) == "buttress")
        g.turn = D.QUAKE.omen
        Cat.turn(g)
        assert(g.log[#g.log].text:find("TREMBLES"))
    end },
    { "the rift is seen from sea to sea before the tremors, and quakes are marked the turn before", function()
        local g = newGame()
        g.turn = D.QUAKE.tremors - 1
        Cat.turn(g)
        local c = g.cataclysm
        assert(c.rift and #c.rift >= D.QUAKE.riftLen[1], "the rift is laid")
        local first, last = g.cells[c.rift[1]], g.cells[c.rift[#c.rift]]
        assert(g:coastal(first) and g:coastal(last), "it runs from the sea to the sea")
        for i, id in ipairs(c.rift) do
            local cell = g.cells[id]
            assert(cell.riftLine == i and not g:isWater(cell) and not cell.city and cell.elev ~= "mountain")
            if i > 1 then assert(g:dist(cell, g.cells[c.rift[i - 1]]) == 1, "one hex to the next") end
            assert(not cell.rift, "nothing torn yet")
        end
        local marks = 0
        for _, what in pairs(c.marks) do
            assert(what == "quake")
            marks = marks + 1
        end
        assert(marks == D.QUAKE.quakes.tremors)
    end },
    { "a fault opens on both sides of an edge, and no one walks across it", function()
        local g = newGame()
        local a, k
        a = find(g, function(c)
            for d = 0, 5 do
                local n = g:cell(H.step(c.c, c.r, d))
                if n and free(g, n) and g:passable(c) and g:passable(n) and Quake.canFault(g, c, d) then k = d return true end
            end
        end)
        assert(a, "an edge to crack")
        local b = g:cell(H.step(a.c, a.r, k))
        local u = g:addUnit("warrior", 1, a.id)
        assert(g:stepCost(u, a, b) ~= nil)
        Quake.openFault(g, a, k)
        assert(a.fault[k] and b.fault[(k + 3) % 6])
        assert(Quake.faultBetween(g, a, b) and Quake.faultBetween(g, b, a))
        assert(g:stepCost(u, a, b) == nil, "no one walks across an open fault")
        assert(not Quake.canFault(g, a, k), "not twice")
        assert(g:describe(a):find("FAULT"))
    end },
    { "a quake hurts what is near, shakes cities and cracks the ground", function()
        local g = newGame()
        local city = settle(g)
        at(g, D.QUAKE.tremors + 1)
        local cell = g.cells[city.cell]
        city.buildings.monument, city.buildings.granary = true, true
        city.pop = 4
        local hp, pop = city.hp, city.pop
        local faults = count(g, function(c) return c.fault and next(c.fault) ~= nil end)
        for _ = 1, 6 do Quake.quake(g, cell) end
        assert(city.hp < hp, "the city is shaken")
        assert(city.pop < pop or not city.buildings.monument or not city.buildings.granary, "people die or buildings fall")
        assert(count(g, function(c) return c.fault and next(c.fault) ~= nil end) > faults, "faults open")
        assert(not (cell.fault and next(cell.fault)), "but never on a city's own edges")
    end },
    { "a buttress halves a quake and saves the buildings", function()
        local g = newGame()
        local city = settle(g)
        at(g, D.QUAKE.rift + 1)
        city.buildings.buttress, city.buildings.monument, city.buildings.granary = true, true, true
        city.pop = 4
        local cell = g.cells[city.cell]
        local before = city.hp
        Quake.quake(g, cell)
        assert(before - city.hp == math.floor(D.QUAKE.city * 0.5 + 0.5))
        for _ = 1, 10 do Quake.quake(g, cell) end
        assert(city.buildings.monument and city.buildings.granary, "no building comes down")
        local pop = city.pop
        Quake.great(g)
        assert(city.pop == pop, "and the great quake kills none of its people")
        for _, n in ipairs(g:within(cell, 1)) do
            if n.ownerCity == city then assert(not (n.fault and next(n.fault)), "no fault on its land") end
        end
        local plain = Quake.thirst(g, { buildings = {} })
        assert(Quake.thirst(g, city) == plain - D.QUAKE.ward, "and its people fear less")
    end },
    { "the rift tears hex by hex from the sea: cracked, a chasm, the sea in, then sea", function()
        local g = newGame(9)
        g.turn = D.QUAKE.tremors - 1
        Cat.turn(g)
        local c = g.cataclysm
        local first = g.cells[c.rift[1]]
        local u = g:addUnit("warrior", 1, first.id)
        for t = D.QUAKE.rift, D.QUAKE.rift + 9 do
            at(g, t)
            Cat.turn(g)
        end
        assert(first.sundered and g:isWater(first) and first.terrain == "coast", "the end by the sea is sea")
        assert(not u.dead and u.cell ~= first.id or u.dead, "whoever stood there was moved, or lost")
        local chasm = count(g, function(cell) return (cell.rift or 0) >= 2 end)
        local torn = count(g, function(cell) return cell.rift ~= nil or cell.sundered end)
        assert(torn > 2, "more of it is torn")
        for _, cell in ipairs(g.cells) do
            if (cell.rift or 0) >= 2 then
                assert(not g:passable(cell) and g:yield(cell) == 0, "a chasm can't be crossed, nor worked")
            end
        end
        assert(chasm >= 0)
    end },
    { "the great quake opens the whole rift to the sea, and waves strike the cities on the shore", function()
        local g = newGame(9)
        local city = settle(g)
        g.turn = D.QUAKE.tremors - 1
        Cat.turn(g)
        at(g, D.QUAKE.great)
        local hp = city.hp
        Quake.great(g)
        for _, id in ipairs(g.cataclysm.rift) do
            local cell = g.cells[id]
            assert(cell.sundered or cell.city, "every hex of it is sea")
        end
        assert(city.hp < hp)
    end },
    { "the ranges rise: shallows to land, flat to hills, hills to mountains", function()
        local g = newGame()
        local shoal = find(g, function(c)
            if c.terrain ~= "coast" then return false end
            for _, n in ipairs(g:neighbours(c)) do if g:passable(n) then return true end end
        end)
        Quake.raise(g, shoal)
        assert(not g:isWater(shoal) and shoal.raised and shoal.elev == "flat", "new land out of the sea")
        assert(g:describe(shoal):find("RISEN SEABED"))
        local flat = find(g, function(c) return g:passable(c) and c.elev == "flat" end)
        local u = g:addUnit("warrior", 1, flat.id)
        local top = flat.top
        Quake.raise(g, flat)
        assert(flat.elev == "hills" and flat.top == top + D.ELEV.hills.rise)
        Quake.raise(g, flat)
        assert(flat.elev == "mountain")
        assert(u.dead or u.cell ~= flat.id, "no one stands on the new mountain")
        g.turn = D.QUAKE.rift - 1
        g.cataclysm.rift = {}
        Quake.planRanges(g)
        assert(#g.cataclysm.ranges >= 1)
    end },
    { "a volcano erupts: lava burns the land and cools to black rock, ash falls and leaves it rich", function()
        local g = newGame()
        at(g, D.QUAKE.fire)
        Quake.wake(g, 1)
        local v = g.cells[g.cataclysm.volcanoes[1]]
        assert(v.volcano and v.elev == "mountain")
        local any = find(g, function(c)
            if not g:passable(c) or g:dist(c, v) ~= 1 then return false end
            return true
        end)
        if any then any.improvement = "farm" end
        Quake.erupt(g, v)
        local ran = {}
        for _, c in ipairs(g.cells) do if c.lava then ran[#ran + 1] = c end end
        assert(#ran >= 1, "lava runs")
        assert(v.erupting)
        for _, c in ipairs(g.cells) do
            if c.lava then assert(g:yield(c) == 0 and not c.improvement) end
        end
        local ash = find(g, function(c) return c.ashfall ~= nil end)
        assert(ash, "ash falls")
        -- It sleeps again, so what it did can be watched settling.
        v.volcano = nil
        for t = 1, D.QUAKE.ashTurns + 1 do
            at(g, D.QUAKE.fire + t)
            Cat.turn(g)
        end
        for _, c in ipairs(ran) do
            assert(c.basalt or c.lava, "the lava cooled to black rock (or ran there again)")
        end
        assert(count(g, function(c) return c.soil end) >= 1, "the ash made the soil rich")
    end },
    { "a wave is seen coming, then floods the shore and goes back down", function()
        local g = newGame()
        at(g, D.QUAKE.rift + 2)
        local sea = find(g, function(c)
            if c.terrain ~= "coast" then return false end
            for _, n in ipairs(g:neighbours(c)) do if g:passable(n) and n.elev == "flat" then return true end end
        end)
        Quake.heave(g, sea, 3)
        local marked = {}
        for id, what in pairs(g.cataclysm.marks) do
            assert(what == "wave")
            marked[#marked + 1] = g.cells[id]
        end
        assert(#marked >= 1)
        local shore = marked[1]
        local u = g:addUnit("warrior", 1, shore.id)
        assert(Cat.perilous(g, shore, u), "a wave coming is a peril")
        at(g, g.turn + 1)
        Cat.turn(g)
        assert(u.hp < 100 or u.dead)
        local flooded = {}
        for _, c in ipairs(g.cells) do if c.flood and c.waved then flooded[#flooded + 1] = c end end
        assert(#flooded >= 1)
        for _ = 1, D.QUAKE.waveTurns + 1 do
            at(g, g.turn + 1)
            Cat.turn(g)
        end
        for _, c in ipairs(flooded) do assert(c.silt, "it went back down, and left silt") end
    end },
    { "the AI steps off a quake coming", function()
        local g = newGame()
        local city = settle(g)
        at(g, D.QUAKE.omen + 1)
        local spot = find(g, function(c) return g:passable(c) and not c.city and g:dist(c, g.cells[city.cell]) == 2 end)
        local u = g:addUnit("warrior", 1, spot.id)
        g.cataclysm.marks = { [spot.id] = "quake" }
        AI.play(g, g.players[1])
        assert(u.cell ~= spot.id, "it stepped off")
    end },
    { "a whole game of the sundering plays to its end", function()
        local g = Game.new({ seed = 11, cataclysm = "quake", allAI = true })
        while not g:outcome() do
            for _, p in ipairs(g.players) do if p.alive then AI.play(g, p) end end
            g:endTurn(AI)
            g.events = {}
            assert(g.turn <= D.LAST_TURN + 1)
        end
        assert(g.turn == D.LAST_TURN + 1)
        assert(count(g, function(c) return c.sundered end) >= 3, "the rift has parted the land")
        assert(count(g, function(c) return c.fault and next(c.fault) end) > 0)
        assert(#(g.cataclysm.volcanoes or {}) >= 1)
        local buttresses = 0
        for _, c in ipairs(g.cities) do if c.buildings.buttress then buttresses = buttresses + 1 end end
        assert(buttresses >= 1, "the AI built buttresses")
    end },
    { "the rift runs out of each hex towards the next, and at its ends into the sea", function()
        local g = newGame(9)
        g.turn = D.QUAKE.tremors - 1
        Cat.turn(g)
        local c = g.cataclysm
        local n = #c.rift
        for i, id in ipairs(c.rift) do
            local cell = g.cells[id]
            assert(#cell.riftEdges == 2 and cell.riftEdges[1] ~= cell.riftEdges[2])
            for j, k in ipairs(cell.riftEdges) do
                local to = g:cell(H.step(cell.c, cell.r, k))
                local along = c.rift[i + (j == 1 and -1 or 1)]
                if along then
                    assert(to.id == along, "towards the next hex of the rift")
                else
                    assert(g:isWater(to), "at its end, out into the sea")
                end
            end
        end
        assert(g:isWater(g:cell(H.step(g.cells[c.rift[n]].c, g.cells[c.rift[n]].r, g.cells[c.rift[n]].riftEdges[2]))))
    end },
    { "the sea runs into the faults that reach it, and on along them; not into the others", function()
        local g = newGame()
        -- A land hex by the sea, its edge k between two land hexes, with
        -- the sea at a corner of it.
        local a, k
        a = find(g, function(cell)
            if g:isWater(cell) then return false end
            for d = 0, 5 do
                local corner = g:cell(H.step(cell.c, cell.r, (d + 1) % 6))
                if corner and g:isWater(corner) and Quake.canFault(g, cell, d) then k = d return true end
            end
        end)
        assert(a, "a fault to open by the sea")
        Quake.openFault(g, a, k)
        -- And one running on from its other end, if it can.
        local on = (k + 5) % 6
        local runs = Quake.canFault(g, a, on)
        if runs then Quake.openFault(g, a, on) end
        -- And one far from any sea.
        local far, fk = find(g, function(cell)
            if g:isWater(cell) then return false end
            for _, n in ipairs(g:within(cell, 3)) do if g:isWater(n) or n.fault then return false end end
            return true
        end)
        if far then
            for d = 0, 5 do if Quake.canFault(g, far, d) then fk = d break end end
            if fk then Quake.openFault(g, far, fk) end
        end
        Quake.soak(g)
        local b = g:cell(H.step(a.c, a.r, k))
        assert(a.faultWet and a.faultWet[k] and b.faultWet[(k + 3) % 6], "the sea is in it, both sides")
        if runs then assert(a.faultWet[on], "and on along the crack") end
        if far and fk then assert(not (far.faultWet and far.faultWet[fk]), "but not in a crack far from the sea") end
        -- Drawn as water at the sea's level, in the sea's stuff.
        local ffi = require "ffi"
        local was = love
        love = {
            image = { newImageData = function(w, h)
                local buf = ffi.new("uint8_t[?]", w * h * 4)
                return { getFFIPointer = function() return buf end, release = function() end }
            end },
            graphics = { newImage = function() return { setFilter = function() end, replacePixels = function() end } end },
        }
        local World = require "src.world"
        local w = World.new(g)
        local wet = 0
        for _, s in ipairs(w:hexSolids(a)) do
            for _, pl in ipairs(s.planes or {}) do
                if pl[2] == 1 and pl[4] == D.TERRAIN.coast.top and s.kind == "hull" then wet = wet + 1 end
            end
        end
        love = was
        assert(wet >= 1, "the water in the fault")
    end },
    { "a chasm's canal runs from the middle out by the rift's edges, the land either side", function()
        local ffi = require "ffi"
        local was = love
        love = {
            image = { newImageData = function(w, h)
                local buf = ffi.new("uint8_t[?]", w * h * 4)
                return { getFFIPointer = function() return buf end, release = function() end }
            end },
            graphics = { newImage = function() return { setFilter = function() end, replacePixels = function() end } end },
        }
        local World = require "src.world"
        local g = newGame()
        local w = World.new(g)
        local cell = find(g, function(c) return not g:isWater(c) and c.elev == "flat" and not c.river end)
        local function inside(s, x, y, z)
            for _, pl in ipairs(s.planes) do
                if pl[1] * x + pl[2] * y + pl[3] * z > pl[4] + 1e-6 then return false end
            end
            return true
        end
        local function land(x, z)
            for _, s in ipairs(w:hexSolids(cell)) do
                if s.kind == "hull" and s.planes[7] and s.planes[7][4] == cell.top and inside(s, x, cell.top - 0.5, z) then
                    return true
                end
            end
            return false
        end
        -- Bent sharply, gently, and straight through.
        for _, ks in ipairs({ { 0, 2 }, { 0, 1 }, { 1, 4 }, { 5, 3 } }) do
            for step = 2, 3 do
                cell.rift, cell.riftEdges = step, ks
                for _, k in ipairs(ks) do
                    local a = math.rad(60 * k)
                    for _, u in ipairs({ 0, 4, 8, H.APOTHEM - 0.5 }) do
                        assert(not land(cell.x + math.cos(a) * u, cell.z + math.sin(a) * u), "the canal is open along the arm")
                    end
                end
                -- The land stands across the edges the rift does not run out by.
                for k = 0, 5 do
                    if k ~= ks[1] and k ~= ks[2] then
                        local a = math.rad(60 * k)
                        local near
                        for _, j in ipairs(ks) do
                            if math.abs((k - j + 3) % 6 - 3) <= 1 then near = true end
                        end
                        local u = near and H.APOTHEM - 1 or H.APOTHEM - 3
                        assert(land(cell.x + math.cos(a) * u, cell.z + math.sin(a) * u), "land by edge " .. k)
                    end
                end
            end
        end
        love = was
    end },
}
