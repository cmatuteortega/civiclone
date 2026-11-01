local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local D = require "src.defs"

-- The wild is left off: these are the heat's rules.
local function newGame(seed) return Game.new({ seed = seed or 5, wild = false }) end

-- A flat land hex of `terrain`, no forest, river, city or coast, away from
-- everyone's units.
local function plainLand(g, terrain)
    for _, cell in ipairs(g.cells) do
        if cell.terrain == terrain and cell.elev == "flat" and not cell.feature and not cell.city and not cell.river
            and not g:coastal(cell) and not g.mil[cell.id] and not g.civ[cell.id] then
            return cell
        end
    end
end

local function forest(g)
    for _, cell in ipairs(g.cells) do
        if cell.feature == "forest" and not g.mil[cell.id] and not g.civ[cell.id] and not g:isWater(cell) then
            return cell
        end
    end
end

local function count(g, f)
    local n = 0
    for _, cell in ipairs(g.cells) do if f(cell) then n = n + 1 end end
    return n
end

return {
    { "the stages come on their turns, and none before the omen", function()
        assert(Cat.stageAt(D.HEAT.omen - 1) == nil)
        assert(Cat.stageAt(D.HEAT.omen) == "omen")
        assert(Cat.stageAt(D.HEAT.drought) == "drought")
        assert(Cat.stageAt(D.HEAT.fires + 1) == "fires")
        assert(Cat.stageAt(D.LAST_TURN) == "scorch")
        local g = newGame()
        assert(g.cataclysm and g.cataclysm.kind == "heat")
        assert(Cat.label(g) == nil)
        g.turn = D.HEAT.drought
        assert(Cat.label(g) == "DROUGHT " .. (D.LAST_TURN - D.HEAT.drought + 1))
    end },
    { "nothing dries before the drought", function()
        local g = newGame()
        local before = count(g, function(c) return c.terrain == "desert" end)
        g.turn = D.HEAT.omen
        Cat.turn(g)
        assert(count(g, function(c) return c.terrain == "desert" end) == before)
        assert(g.cataclysm.stage == "omen")
        assert(g.log[#g.log].text:find("DROUGHT"))
    end },
    { "the drought dries the land a step at a time", function()
        local g = newGame()
        local grass = { desert = count(g, function(c) return c.terrain == "desert" end),
            grass = count(g, function(c) return c.terrain == "grass" end) }
        g.turn = D.HEAT.drought
        for _ = 1, 10 do Cat.turn(g) end
        assert(count(g, function(c) return c.terrain == "desert" end) > grass.desert)
        assert(count(g, function(c) return c.terrain == "grass" end) < grass.grass)
        assert(count(g, function(c) return c.scorched end) == 0, "only the scorch bakes the desert")
    end },
    { "drying takes the farm and the grain with the land", function()
        local g = newGame()
        local cell = plainLand(g, "grass")
        cell.improvement, cell.resource = "farm", "wheat"
        Cat.dry(g, cell)
        assert(cell.terrain == "plains" and cell.improvement == "farm")
        Cat.dry(g, cell)
        assert(cell.terrain == "desert" and not cell.improvement and not cell.resource)
        Cat.dry(g, cell)
        assert(cell.scorched)
        local f = g:yield(cell)
        assert(f == 0)
    end },
    { "a farm off a river yields less in the drought, unless its city has a cistern", function()
        local g = newGame()
        local s
        for _, u in ipairs(g.units) do if u.owner == 1 and u.kind == "settler" then s = u end end
        local city = g:found(s)
        local cell
        for _, n in ipairs(g:neighbours(g.cells[city.cell])) do
            if not g:isWater(n) and n.elev == "flat" and not g:onRiver(n) and n.ownerCity == city then cell = n break end
        end
        assert(cell, "a hex to farm")
        cell.improvement, cell.feature = "farm", nil
        local wet = g:yield(cell)
        g.turn = D.HEAT.drought
        assert(g:yield(cell) == wet - D.HEAT.droughtFarm)
        city.buildings.cistern = true
        assert(g:yield(cell) == wet)
    end },
    { "cities thirst in the fires and the scorch; a cistern spares them some", function()
        local g = newGame()
        local s
        for _, u in ipairs(g.units) do if u.owner == 1 and u.kind == "settler" then s = u end end
        local city = g:found(s)
        local f0 = g:cityYield(city)
        g.turn = D.HEAT.scorch
        local f1 = g:cityYield(city)
        assert(f1 <= f0 - D.HEAT.thirst.scorch + 1, "thirst, and the drought on any farm")
        assert(Cat.thirst(g, city) == D.HEAT.thirst.scorch)
        city.buildings.cistern = true
        assert(Cat.thirst(g, city) == D.HEAT.thirst.scorch - D.HEAT.cisternThirst)
    end },
    { "a fire burns, hurts who stands in it, and burns out to stumps", function()
        local g = newGame()
        local cell = forest(g)
        local u = g:addUnit("warrior", 2, cell.id)
        g.turn = D.HEAT.fires
        Cat.ignite(g, cell)
        assert(cell.fire == D.HEAT.burn)
        local f, p, gold = g:yield(cell)
        assert(f == 0 and p == 0 and gold == 0, "a burning hex yields nothing")
        for _ = 1, D.HEAT.burn do Cat.turn(g) end
        assert(not cell.fire and cell.burnt and cell.burntForest and not cell.feature)
        assert(cell.terrain ~= "grass")
        assert(u.dead or u.hp <= 100 - D.HEAT.fireDamage * D.HEAT.burn + 1)
        assert(not Cat.flammable(g, cell), "what has burnt doesn't again")
    end },
    { "fire doesn't take in a city or on bare desert", function()
        local g = newGame()
        local s
        for _, u in ipairs(g.units) do if u.owner == 1 and u.kind == "settler" then s = u end end
        local city = g:found(s)
        assert(not Cat.flammable(g, g.cells[city.cell]))
        local sand = plainLand(g, "desert")
        if sand then assert(not Cat.flammable(g, sand)) end
    end },
    { "baked earth burns whoever ends a turn on it", function()
        local g = newGame()
        local cell = plainLand(g, "plains")
        cell.terrain, cell.scorched = "desert", true
        local u = g:addUnit("warrior", 2, cell.id)
        g.turn = D.HEAT.scorch
        Cat.turn(g)
        assert(u.hp == 100 - D.HEAT.scorchDamage)
    end },
    { "without a cataclysm nothing happens", function()
        local g = Game.new({ seed = 5, wild = false, cataclysm = false })
        assert(not g.cataclysm)
        g.turn = D.HEAT.scorch
        local before = count(g, function(c) return c.terrain == "desert" end)
        Cat.turn(g)
        assert(count(g, function(c) return c.terrain == "desert" end) == before)
        assert(Cat.label(g) == nil)
    end },
    { "with no cataclysm the game ends at the old last turn, and there are no cisterns", function()
        local g = Game.new({ seed = 5, wild = false, cataclysm = false })
        assert(g:lastTurn() == D.PLAIN_LAST_TURN)
        assert(Game.new({ seed = 5, wild = false }):lastTurn() == D.LAST_TURN)
        local s
        for _, u in ipairs(g.units) do if u.owner == 1 and u.kind == "settler" then s = u end end
        local city = g:found(s)
        g.players[1].techs.masonry = true
        assert(not g:canBuild(city, "building", "cistern"))
        assert(g:canBuild(city, "building", "walls"))
        g.turn = D.PLAIN_LAST_TURN + 1
        assert(g:outcome())
    end },
    { "an all-AI game runs through the heat death to its end", function()
        local g = Game.new({ seed = 7, allAI = true })
        local land = count(g, function(c) return not g:isWater(c) and c.elev ~= "mountain" end)
        local desert = count(g, function(c) return c.terrain == "desert" end)
        while g.turn <= D.LAST_TURN do
            AI.play(g, g.players[1])
            g:endTurn(AI)
        end
        assert(g:outcome(), "the game is over")
        assert(count(g, function(c) return c.terrain == "desert" end) > desert + land / 4, "the land has dried")
        assert(count(g, function(c) return c.burnt end) > 0, "and burnt")
        local cisterns = 0
        for _, c in ipairs(g.cities) do if c.buildings.cistern then cisterns = cisterns + 1 end end
        assert(cisterns > 0, "the AI built against it")
    end },
    { "the rivers run dry from their springs down, and a dry river holds nothing off", function()
        local g = newGame()
        local wet = count(g, function(c) return g:onRiver(c) end)
        assert(wet > 0)
        local function key(p) return math.floor(p[1] * 4 + 0.5) * 65536 + math.floor(p[2] * 4 + 0.5) end
        for _ = 1, 12 do
            Cat.failRivers(g, 2)
            -- Nothing still running flows into a dried stretch.
            local into = {}
            for _, c in ipairs(g.cells) do
                for k = 0, 5 do
                    local e = c.river and c.river[k]
                    if e then into[key(e.to)] = true end
                end
            end
            for _, c in ipairs(g.cells) do
                for k = 0, 5 do
                    local e = c.dry and c.dry[k]
                    if e then
                        assert(not into[key(e.from)], "a river dries from its spring")
                        assert(not (c.river and c.river[k]), "dry is not wet")
                    end
                end
            end
        end
        assert(count(g, function(c) return g:onRiver(c) end) < wet, "the rivers are shorter")
        local bed
        for _, c in ipairs(g.cells) do if c.dry and not g:onRiver(c) and not g:isWater(c) then bed = c break end end
        assert(bed, "a hex left by a dry bed only")
        assert(g:describe(bed):find("DRY RIVERBED"))
        local _, _, gold = g:yield(bed)
        assert(gold == D.TERRAIN[bed.terrain].gold + (bed.resource and D.RESOURCE[bed.resource].gold or 0),
            "no river's gold")
        -- Through the drought and on, they fail by themselves.
        local h = newGame()
        h.turn = D.HEAT.drought
        for _ = 1, 20 do Cat.turn(h) end
        assert(count(h, function(c) return c.dry ~= nil end) > 0)
    end },
    { "the great ebb: told, then the shallows go dry and can be walked, and the ships are moved or lost", function()
        local g = newGame()
        local coast = count(g, function(c) return c.terrain == "coast" end)
        local ship
        for _, c in ipairs(g.cells) do
            if c.terrain == "coast" and not g.mil[c.id] then ship = g:addUnit("galley", 1, c.id) break end
        end
        g.turn = D.HEAT.warn
        g.cataclysm.stage = "scorch"
        Cat.turn(g)
        assert(g.log[#g.log].text:find("DRAWING BACK") or g.log[#g.log - 1].text:find("DRAWING BACK"))
        assert(Cat.ebbIn(g) == D.HEAT.ebb - D.HEAT.warn)
        assert(count(g, function(c) return c.terrain == "saltflat" end) == 0, "not yet")
        g.turn = D.HEAT.ebb
        Cat.turn(g)
        assert(count(g, function(c) return c.terrain == "coast" and not c.lair and c.ebbed end) == 0)
        local salt = count(g, function(c) return c.terrain == "saltflat" end)
        assert(salt >= coast - count(g, function(c) return c.lair ~= nil end), "every shallow is bare")
        for _, c in ipairs(g.cells) do
            if c.terrain == "saltflat" then
                assert(g:passable(c) and not g:isWater(c), "walked on")
                assert(c.top == D.TERRAIN.saltflat.top and c.ebbed)
                assert(c.resource ~= "fish" and c.improvement ~= "boats")
            end
        end
        assert(ship.dead or g:isWater(g.cells[ship.cell]), "the ship is on the water, or lost")
        -- The deep water by the salt is shallows now, and goes dry turn by
        -- turn after.
        local before = count(g, function(c) return c.terrain == "saltflat" end)
        g.turn = D.HEAT.ebb + 1
        Cat.turn(g)
        assert(count(g, function(c) return c.terrain == "saltflat" end) == before + D.HEAT.recede)
        -- The salt burns in the scorch, as the baked earth does.
        local flat
        for _, c in ipairs(g.cells) do
            if c.terrain == "saltflat" and not g.mil[c.id] and not g.civ[c.id] and not g:onRiver(c) then flat = c break end
        end
        local u = g:addUnit("warrior", 1, flat.id)
        assert(Cat.perilous(g, flat, u))
        Cat.turn(g)
        assert(u.hp == 100 - D.HEAT.scorchDamage)
    end },
}
