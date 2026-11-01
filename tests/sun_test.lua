local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local Sun = require "src.stillsun"
local Frost = require "src.frost"
local D = require "src.defs"

-- The wild is left off: these are the still sun's rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false, cataclysm = "sun" }) end

local function free(g, cell) return not g.mil[cell.id] and not g.civ[cell.id] and not cell.city end

local function find(g, f)
    for _, cell in ipairs(g.cells) do if free(g, cell) and f(cell) then return cell end end
end

local function count(g, f)
    local n = 0
    for _, cell in ipairs(g.cells) do if f(cell) then n = n + 1 end end
    return n
end

-- A game at the turn the sun stands still, the line drawn.
local function stilled(seed)
    local g = newGame(seed)
    g.turn = D.SUN.still
    Cat.turn(g)
    return g
end

local function settle(g)
    for _, u in ipairs(g.units) do
        if u.owner == 1 and u.kind == "settler" then return g:found(u) end
    end
end

return {
    { "the still sun's stages come on their turns", function()
        assert(Cat.stageAt(D.SUN.omen - 1, "sun") == nil)
        assert(Cat.stageAt(D.SUN.omen, "sun") == "omen")
        assert(Cat.stageAt(D.SUN.still, "sun") == "still")
        assert(Cat.stageAt(D.SUN.sear + 1, "sun") == "sear")
        assert(Cat.stageAt(D.LAST_TURN, "sun") == "twilight")
        local g = newGame()
        g.turn = D.SUN.sear
        assert(Cat.label(g) == "SEAR & FROST " .. (D.LAST_TURN - D.SUN.sear + 1))
        assert(Cat.ended(g) == "THE SUN HAS STOOD STILL FOREVER")
        g.turn = D.SUN.omen
        Cat.turn(g)
        assert(g.log[#g.log].text:find("DAYS GROW LONG"))
        assert(not Sun.line(g), "nobody knows where the line will fall in the omen")
    end },
    { "the line is drawn as the sun stops, through the land, a new one every game", function()
        local seen = {}
        for seed = 1, 6 do
            local g = stilled(seed)
            local line = Sun.line(g)
            assert(line, "drawn as the sun stands still")
            local day, night, land = 0, 0, 0
            for _, cell in ipairs(g.cells) do
                if not g:isWater(cell) then
                    land = land + 1
                    local s = Sun.side(g, cell)
                    if s > 0 then day = day + 1 else night = night + 1 end
                end
            end
            -- Through the land: a good part of it on either side.
            assert(day >= land * 0.2 and night >= land * 0.2, ("seed %d: %d day, %d night"):format(seed, day, night))
            seen[#seen + 1] = math.floor(math.atan2(line.nz, line.nx) * 100)
        end
        local differ = false
        for k = 2, #seen do if seen[k] ~= seen[1] then differ = true end end
        assert(differ, "the line runs a different way in different games")
    end },
    { "every hex lies in the day, the night or the twilight, and the twilight narrows", function()
        local g = stilled()
        local n = { day = 0, night = 0, twilight = 0 }
        for _, cell in ipairs(g.cells) do
            local z = Sun.zone(g, cell)
            n[z] = n[z] + 1
            assert((z == "night") == (Sun.side(g, cell) < -D.SUN.band.still))
        end
        assert(n.day > 0 and n.night > 0 and n.twilight > 0)
        g.turn = D.SUN.twilight
        local m = { day = 0, night = 0, twilight = 0 }
        for _, cell in ipairs(g.cells) do
            local z = Sun.zone(g, cell)
            m[z] = m[z] + 1
        end
        assert(m.twilight < n.twilight, "the band has narrowed")
    end },
    { "it is always night on the night side, never on the day side", function()
        local g = stilled()
        local day = find(g, function(c) return Sun.zone(g, c) == "day" end)
        local night = find(g, function(c) return Sun.zone(g, c) == "night" end)
        for t = D.SUN.still, D.SUN.still + 8 do
            assert(D.night(t, g, night) == true)
            assert(D.night(t, g, day) == false)
        end
    end },
    { "the day dries the land and the night freezes it, never the twilight", function()
        local g = stilled()
        local before = {}
        for _, cell in ipairs(g.cells) do before[cell.id] = cell.terrain end
        for t = D.SUN.still + 1, D.SUN.still + 15 do
            g.turn = t
            Cat.turn(g)
        end
        local dried, froze = 0, 0
        for _, cell in ipairs(g.cells) do
            if cell.terrain ~= before[cell.id] and not (cell.terrain == "plains" and cell.burnt) then
                local z = Sun.zone(g, cell)
                assert(z ~= "twilight", "the twilight is spared")
                if Frost.frozen(cell) then
                    assert(z == "night", "it freezes only in the night")
                    froze = froze + 1
                else
                    assert(z == "day", "it dries only in the day")
                    dried = dried + 1
                end
            end
        end
        assert(dried > 10 and froze > 10, dried .. " dried, " .. froze .. " froze")
    end },
    { "land freezes to tundra and then snow: the grain killed, the farm buried", function()
        local g = stilled()
        local cell = find(g, function(c) return c.terrain == "grass" and c.elev == "flat" and not g:onRiver(c) end)
        cell.improvement, cell.resource = "farm", "wheat"
        Frost.chill(g, cell)
        assert(cell.terrain == "tundra" and cell.improvement == "farm" and cell.resource == nil)
        Frost.chill(g, cell)
        assert(cell.terrain == "snow" and cell.improvement == nil, "buried under the snow")
        assert(g:yield(cell) == 0, "snow yields no food")
        assert(not Frost.chillable(g, cell), "snow is as cold as it gets")
        local u = g:addUnit("warrior", 1, cell.id)
        assert(g:moveCost(cell) == 2, "deep snow is heavy going")
        g:removeUnit(u)
    end },
    { "the sea freezes from the frozen shore, and the ice is walked on and not sailed", function()
        local g = stilled()
        local sea = find(g, function(c) return c.terrain == "coast" end)
        assert(not Frost.freezable(g, sea, false) or Frost.besideFrozen(g, sea))
        -- Freeze the land beside it.
        for _, n in ipairs(g:neighbours(sea)) do
            if not g:isWater(n) and n.elev ~= "mountain" then n.terrain = "snow" end
        end
        assert(Frost.freezable(g, sea, false))
        local ship = g:addUnit("galley", 1, sea.id)
        Frost.freeze(g, sea)
        assert(sea.terrain == "ice" and sea.sea == "coast")
        assert(not g:isWater(sea), "ice is land to walk on")
        assert(not g:canFound({ kind = "settler", moves = 1, cell = sea.id, owner = 1 }), "no city on the ice")
        local hp = ship.hp
        Frost.crush(g, D.SUN.crush)
        assert(ship.dead or ship.hp == hp - D.SUN.crush, "the ice crushes the ship")
        local open = find(g, function(c) return c.terrain == "ocean" and Frost.besideFrozen(g, c) end)
        if open then assert(not Frost.freezable(g, open, false) and Frost.freezable(g, open, true), "the open sea last") end
    end },
    { "a river between frozen banks is walked over", function()
        local g = stilled()
        local a, b
        for _, cell in ipairs(g.cells) do
            if not a and g:passable(cell) and not cell.city then
                for _, n in ipairs(g:neighbours(cell)) do
                    if g:passable(n) and not n.city and g:riverBetween(cell, n) then a, b = cell, n break end
                end
            end
        end
        assert(a, "a river to cross")
        assert(g:fords(a, b))
        a.terrain, b.terrain = "snow", "tundra"
        assert(not g:fords(a, b), "frozen over")
        b.terrain = "grass"
        assert(g:fords(a, b), "one bank thawed: it runs")
    end },
    { "the day thirsts and the night goes cold; a cistern or a hearth spares it", function()
        local g = newGame()
        local city = settle(g)
        assert(city)
        local cell = g.cells[city.cell]
        g.turn = D.SUN.sear
        -- Put the line so the city is deep in the day, then deep in the night.
        g.cataclysm.line = { nx = 1, nz = 0, d = cell.x - 10 * D.SUN.band.sear * 30, w = 30 }
        assert(Sun.zone(g, cell) == "day")
        assert(Cat.thirst(g, city) == D.SUN.thirst.sear)
        assert(Sun.wardFor(g, city) == "cistern" and Cat.ward(g, city) == "cistern")
        assert(g:canBuild(city, "building", "cistern") or not g.players[1].techs.masonry)
        city.buildings.cistern = true
        assert(Cat.thirst(g, city) == D.SUN.thirst.sear - D.SUN.ward)
        city.buildings.cistern = nil
        g.cataclysm.line.nx = -1
        g.cataclysm.line.d = -cell.x + 10 * D.SUN.band.sear * 30
        assert(Sun.zone(g, cell) == "night")
        assert(Cat.thirst(g, city) == D.SUN.cold.sear)
        assert(Sun.wardFor(g, city) == "hearth")
        g.players[1].techs.pottery = true
        assert(g:canBuild(city, "building", "hearth"), "a hearth is built under the still sun")
        city.buildings.hearth = true
        assert(Cat.thirst(g, city) == D.SUN.cold.sear - D.SUN.ward)
        -- And nothing in the twilight.
        g.cataclysm.line.d = -cell.x
        assert(Sun.zone(g, cell) == "twilight" and Cat.thirst(g, city) == 0)
        -- A hearth only against the still sun.
        local h = Game.new({ seed = 5, wild = false, cataclysm = "heat" })
        local c2 = settle(h)
        h.players[1].techs.pottery = true
        assert(not h:canBuild(c2, "building", "hearth"))
    end },
    { "in the twilight the far sides kill", function()
        local g = stilled()
        g.turn = D.SUN.twilight
        local snow = find(g, function(c) return Sun.zone(g, c) == "night" and g:passable(c) and not c.city end)
        snow.terrain = "snow"
        local u = g:addUnit("warrior", 1, snow.id)
        local hp = u.hp
        assert(Sun.danger(g, snow, u))
        Cat.turn(g)
        assert(u.dead or u.hp < hp, "the cold bites whoever is out on the snow")
    end },
    { "the long night of the sky's falling freezes the land too", function()
        local g = Game.new({ seed = 5, wild = false, cataclysm = "sky" })
        g.turn = D.SKY.dark
        local n0 = count(g, Frost.frozen)
        for t = D.SKY.dark, D.SKY.dark + 9 do
            g.turn = t
            Cat.turn(g)
        end
        assert(count(g, Frost.frozen) >= n0 + 30, "the frost has spread")
        assert(count(g, function(c) return c.terrain == "snow" end) > 0)
    end },
    { "a whole game of the computer to the end of the world under the still sun", function()
        local g = Game.new({ seed = 11, cataclysm = "sun", allAI = true })
        local over
        for _ = 1, D.LAST_TURN + 2 do
            for _, p in ipairs(g.players) do
                if p.alive then AI.play(g, p) end
            end
            g:endTurn(AI)
            g.events = {}
            over = g:outcome()
            if over then break end
        end
        assert(over, "the game ended")
        assert(Sun.line(g))
        assert(count(g, function(c) return c.terrain == "ice" end) > 0, "the sea froze")
        assert(count(g, function(c) return c.terrain == "snow" end) > 0, "the night snowed")
        assert(count(g, function(c) return c.terrain == "desert" end) > 0, "the day dried")
    end },
    { "the great storm: cyclones form on the line, are seen coming, run along it and strike", function()
        local g = stilled()
        for t = D.SUN.still + 1, D.SUN.storm - 1 do
            g.turn = t
            Cat.turn(g)
        end
        local told = false
        for _, l in ipairs(g.log) do if l.text:find("WINDS ARE RISING") then told = true end end
        assert(told, "it is told")
        local cys = Sun.cyclones(g)
        assert(#cys >= 1, "they have formed")
        for _, cy in ipairs(cys) do
            local s = Sun.side(g, g.cells[cy.cell])
            assert(math.abs(s) <= Sun.band(g) + 1.01, "on the line")
        end
        -- Seen coming: the eye's hex and the ring round it.
        local cy = cys[1]
        assert(cy.next, "it knows where it goes")
        local eye = g.cells[cy.next]
        assert(Sun.stormAt(g, eye) == "eye")
        for _, n in ipairs(g:neighbours(eye)) do assert(Sun.stormAt(g, n)) end
        -- Whoever is out in it is hurt; the forest blown down.
        local out
        for _, n in ipairs(g:within(eye, 1)) do
            if not n.city and not g.mil[n.id] and g:passable(n) then out = n break end
        end
        local u = out and g:addUnit("warrior", 1, out.id)
        if u then assert(Sun.danger(g, out, u), "the beasts and the AI keep out of it") end
        eye.feature = (not eye.city and not g:isWater(eye)) and "forest" or eye.feature
        local from = cy.cell
        g.turn = D.SUN.storm
        Cat.turn(g)
        assert(cy.cell ~= from and g:dist(g.cells[from], g.cells[cy.cell]) <= D.SUN.speed + 1, "it moved")
        if u then assert(u.dead or u.hp < 100, "the storm hurt it") end
        -- The gales take food from every city, the twilight's too.
        local city = settle(g)
        assert(Cat.thirst(g, city) >= D.SUN.gale - D.SHELTER.stores)
    end },
    { "a cyclone strikes: the eye hurts most, the ring less, a town's people shelter", function()
        local g = stilled()
        g.turn = D.SUN.storm
        local eye = find(g, function(c) return g:passable(c) and #g:neighbours(c) == 6 end)
        local ring
        for _, n in ipairs(g:neighbours(eye)) do
            if free(g, n) and g:passable(n) then ring = n break end
        end
        local a = g:addUnit("warrior", 1, eye.id)
        local b = ring and g:addUnit("warrior", 1, ring.id)
        eye.improvement = "farm"
        Sun.strike(g, eye)
        assert(a.hp == 100 - D.SUN.eyeHit)
        if b then assert(b.hp == 100 - D.SUN.ringHit) end
    end },
}
