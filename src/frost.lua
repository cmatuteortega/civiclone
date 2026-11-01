-- The frost: what the cold does to the land and the sea. Not a cataclysm of
-- its own but what two of them share: the endless night of the still sun
-- (src/stillsun.lua) and the long night of the sky's falling
-- (src/skyfall.lua). Each says where and how fast; this says what happens.
--
--   Land freezes a step at a time: grassland, plains, desert and marsh to
--   tundra (rimed ground, the grain killed, a farm kept but poor), then
--   tundra to snow (deep, drifted, the farm buried under it). Forests keep
--   their trees, and their ground freezes under them. Mountains are
--   snowbound already.
--
--   The sea freezes from the shore out, onto shallows beside frozen land
--   or ice already, and the open sea after: `ice`, that is land to walk on
--   now, and no water for a ship (src/defs.lua, D.TERRAIN.ice). The cell
--   keeps what water it was in `sea`. What lived in it is gone, and what
--   sails on it is crushed until it gets out.
--
--   A river between two frozen hexes freezes too and is walked over with no
--   ford (src/game.lua, Game:fords).
--
-- The game emits "terrain" for every hex that changes, and "freeze" for
-- each hex of sea that freezes. Nothing here draws.

local D = require "src.defs"
local Cat = require "src.cataclysm"

local Frost = {}

-- Is the hex frozen ground or ice?
function Frost.frozen(cell) return D.TERRAIN[cell.terrain].frozen == true end

-- Does a hearth's city own the hex (D.BUILDINGS.hearth)?
function Frost.warm(cell) return Cat.warded(cell, "hearth") end

-- Can the land here freeze a step further: land, not mountains (snowbound
-- already), not snow, not burning. A town freezes too: snow on its roofs
-- (src/models.lua), though its own hex still feeds it (Game:yield).
function Frost.chillable(game, cell)
    if game:isWater(cell) or cell.elev == "mountain" or cell.fire then return false end
    return cell.terrain ~= "snow" and cell.terrain ~= "ice"
end

-- Is any hex beside this one frozen already?
function Frost.besideFrozen(game, cell)
    for _, n in ipairs(game:neighbours(cell)) do
        if Frost.frozen(n) or n.elev == "mountain" then return true end
    end
    return false
end

-- One hex a step colder: to tundra, and tundra to snow.
function Frost.chill(game, cell)
    if cell.terrain == "tundra" then
        cell.terrain = "snow"
        if cell.improvement == "farm" then
            cell.improvement = nil
            if cell.owner then game:tell(cell.owner, "A FARM IS BURIED UNDER THE SNOW") end
        end
    else
        cell.terrain = "tundra"
        if cell.resource == "wheat" then cell.resource = nil end
    end
    -- The cold puts out the last of a heat or a flood.
    cell.scorched, cell.flood = nil, nil
    game:emit({ kind = "terrain", cell = cell.id })
end

-- Can the sea here freeze: water beside frozen land or ice already, and
-- with `open`, the open sea too (else only the shallows).
function Frost.freezable(game, cell, open)
    if not game:isWater(cell) then return false end
    if cell.terrain == "ocean" and not open then return false end
    for _, n in ipairs(game:neighbours(cell)) do
        if Frost.frozen(n) and not Frost.warm(n) then return true end
    end
    return false
end

-- A hex of sea frozen hard: ice, that is walked on and sailed no more.
function Frost.freeze(game, cell)
    cell.sea = cell.terrain
    cell.terrain = "ice"
    if cell.resource == "fish" then cell.resource = nil end
    game:emit({ kind = "freeze", cell = cell.id })
    game:emit({ kind = "terrain", cell = cell.id })
    -- The water beside it meets new ice: its shore is drawn again.
    for _, n in ipairs(game:neighbours(cell)) do
        if game:isWater(n) then game:emit({ kind = "terrain", cell = n.id }) end
    end
end

-- Has the river between two neighbouring hexes frozen over?
function Frost.riverIced(a, b)
    return Frost.frozen(a) and Frost.frozen(b)
end

-- The ships, and the beasts of the sea, the ice has closed round: hurt,
-- `amount` each, every turn until they get out.
function Frost.crush(game, amount)
    for _, u in ipairs(game.units) do
        if not u.dead and u.def.sea and game.cells[u.cell].terrain == "ice" then
            Cat.hurt(game, u, amount, "WAS CRUSHED IN THE ICE")
        end
    end
end

-- Whoever ends a turn out on the snow, away from a city, where `where`
-- (if given) says: hurt by `amount`.
function Frost.bite(game, amount, where)
    for _, cell in ipairs(game.cells) do
        if cell.terrain == "snow" and not cell.city and (not where or where(cell)) then
            for _, u in ipairs(Cat.unitsOn(game, cell)) do
                if not u.def.sea then Cat.hurt(game, u, amount, "FROZE TO DEATH") end
            end
        end
    end
end

-- How likely a hex is to freeze a step, by what holds the cold off: the
-- rivers, the coast and a hearth's land, times `w`.
function Frost.hold(game, cell, w, H)
    if game:onRiver(cell) then w = w * H.river end
    if game:coastal(cell) then w = w * H.coast end
    if Frost.warm(cell) then w = w * H.hearth end
    -- The cold creeps out from what has frozen already.
    if Frost.besideFrozen(game, cell) then w = w * 3 end
    return w
end

return Frost
