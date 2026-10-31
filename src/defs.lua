-- The numbers: terrain and what it yields, units, buildings, technologies and
-- the civilizations. Close to Civilization VI's where it has one, smaller
-- where a short game wants it.

local D = {}

D.COLS, D.ROWS = 34, 22
D.LAST_TURN = 150

-- Each land hex is a base (grass, plains, desert) at an elevation (flat,
-- hills, mountains), and maybe has a forest on it. Water is coast or ocean.
-- `top`: how high the hex stands, in room units.
D.TERRAIN = {
    ocean = { name = "OCEAN", food = 1, prod = 0, gold = 0, water = true, top = -2 },
    coast = { name = "COAST", food = 1, prod = 0, gold = 1, water = true, top = -2 },
    grass = { name = "GRASSLAND", food = 2, prod = 0, gold = 0, top = 4 },
    plains = { name = "PLAINS", food = 1, prod = 1, gold = 0, top = 4 },
    desert = { name = "DESERT", food = 0, prod = 0, gold = 0, top = 4 },
}
D.ELEV = {
    flat = { name = "", food = 0, prod = 0, move = 1, defense = 0, rise = 0 },
    hills = { name = "HILLS", food = 0, prod = 1, move = 2, defense = 3, rise = 5 },
    mountain = { name = "MOUNTAINS", food = 0, prod = 0, impassable = true, defense = 0, rise = 6 },
}
D.FEATURE = {
    forest = { name = "FOREST", food = 0, prod = 1, move = 2, defense = 3 },
}
D.RESOURCE = {
    wheat = { name = "WHEAT", food = 1, prod = 0, gold = 0 },
    stone = { name = "STONE", food = 0, prod = 1, gold = 0 },
    gems = { name = "GEMS", food = 0, prod = 0, gold = 3 },
    fish = { name = "FISH", food = 1, prod = 0, gold = 0 },
}
-- Rivers run along the edges between hexes (src/mapgen.lua). Crossing one
-- takes all a unit's moves, unless a city's bridge carries it over; one
-- attacking across it strikes weaker. Every hex on a river yields a gold
-- more, and a farm on one a food more.
D.RIVER = { gold = 1, farmFood = 1, attack = 5 }
-- Their names, given out at random.
D.RIVERS = {
    "ASHBURN", "SEDGEWATER", "OSIER", "FALLOW", "TAMBER", "WILLOWMERE", "BRACKEN", "SALLOW",
    "RUSHMOOR", "LARKSPUR", "UMBER", "HOLLOWAY", "MARL", "TEASEL",
}

-- What a builder can make, and where.
D.IMPROVEMENT = {
    farm = { name = "FARM", food = 1, prod = 0, key = "R" },
    mine = { name = "MINE", food = 0, prod = 2, key = "M", tech = "mining" },
    boats = { name = "FISHING BOATS", food = 1, prod = 0, key = "N", tech = "sailing" },
}

-- Units. `str` is melee strength (or how well it stands when it is attacked),
-- `ranged` and `range` a ranged unit's shot, `moves` its movement points.
-- `pop`: a settler takes a citizen with it. `sea`: a ship, that sails the
-- coast (and the ocean, after Cartography) and is built only by a city on
-- the water.
D.UNITS = {
    settler = { name = "SETTLER", cost = 70, str = 0, moves = 2, sight = 2, civilian = true, pop = 1, order = 1 },
    builder = { name = "BUILDER", cost = 45, str = 0, moves = 2, sight = 2, civilian = true, charges = 3, order = 2 },
    warrior = { name = "WARRIOR", cost = 40, str = 20, moves = 2, sight = 2, order = 3 },
    scout = { name = "SCOUT", cost = 30, str = 10, moves = 3, sight = 3, order = 4 },
    slinger = { name = "SLINGER", cost = 35, str = 5, ranged = 15, range = 2, moves = 2, sight = 2, order = 5 },
    archer = { name = "ARCHER", cost = 60, str = 15, ranged = 25, range = 2, moves = 2, sight = 2, tech = "archery", order = 6 },
    spearman = { name = "SPEARMAN", cost = 65, str = 25, moves = 2, sight = 2, tech = "bronze", order = 7 },
    horseman = { name = "HORSEMAN", cost = 80, str = 36, moves = 4, sight = 2, tech = "horses", order = 8 },
    swordsman = { name = "SWORDSMAN", cost = 90, str = 35, moves = 2, sight = 2, tech = "iron", order = 9 },
    galley = { name = "GALLEY", cost = 65, str = 25, moves = 3, sight = 2, sea = true, tech = "sailing", order = 10 },
    quadrireme = { name = "QUADRIREME", cost = 110, str = 20, ranged = 25, range = 2, moves = 3, sight = 2, sea = true,
        tech = "shipbuilding", order = 11 },
}

-- A land unit on the water rows across it in a boat: embarked. It moves as
-- far as this, stands this strong whatever it is, and cannot attack.
-- Stepping from the land onto the water, or back, takes all its moves.
D.EMBARK = { moves = 3, str = 10 }

-- Buildings: what each adds to its city every turn.
D.BUILDINGS = {
    monument = { name = "MONUMENT", short = "MON.", cost = 50, culture = 2, order = 1 },
    granary = { name = "GRANARY", short = "GRAN.", cost = 65, food = 2, tech = "pottery", order = 2 },
    library = { name = "LIBRARY", short = "LIB.", cost = 90, science = 2, tech = "writing", order = 3 },
    market = { name = "MARKET", short = "MKT.", cost = 100, gold = 4, tech = "currency", order = 4 },
    walls = { name = "WALLS", short = "WALLS", cost = 80, defense = 10, hp = 100, tech = "masonry", order = 5 },
    -- Only a city on the water: each worked water hex yields this much more.
    harbour = { name = "HARBOUR", short = "HARB.", cost = 90, seaFood = 1, coastal = true, tech = "shipbuilding", order = 6 },
    lighthouse = { name = "LIGHTHOUSE", short = "LIGHT.", cost = 80, seaGold = 1, sight = 4, coastal = true, tech = "cartography",
        order = 7 },
}

-- Technologies, in the order the list shows them.
D.TECHS = {
    { id = "pottery", name = "POTTERY", cost = 25, needs = {}, gives = "GRANARY" },
    { id = "mining", name = "MINING", cost = 25, needs = {}, gives = "MINES" },
    { id = "archery", name = "ARCHERY", cost = 35, needs = {}, gives = "ARCHER" },
    { id = "masonry", name = "MASONRY", cost = 40, needs = { "mining" }, gives = "WALLS" },
    { id = "writing", name = "WRITING", cost = 50, needs = { "pottery" }, gives = "LIBRARY" },
    { id = "bronze", name = "BRONZE WORKING", cost = 55, needs = { "mining" }, gives = "SPEARMAN" },
    { id = "horses", name = "HORSEBACK RIDING", cost = 60, needs = { "archery" }, gives = "HORSEMAN" },
    { id = "currency", name = "CURRENCY", cost = 80, needs = { "writing" }, gives = "MARKET" },
    { id = "iron", name = "IRON WORKING", cost = 100, needs = { "bronze" }, gives = "SWORDSMAN" },
    { id = "sailing", name = "SAILING", cost = 40, needs = { "pottery" }, gives = "GALLEY, EMBARKING, FISHING BOATS" },
    { id = "shipbuilding", name = "SHIPBUILDING", cost = 70, needs = { "sailing" }, gives = "QUADRIREME, HARBOUR" },
    { id = "cartography", name = "CARTOGRAPHY", cost = 90, needs = { "shipbuilding" }, gives = "OCEAN, LIGHTHOUSE" },
}
D.TECH = {}
for _, t in ipairs(D.TECHS) do D.TECH[t.id] = t end

-- Cities.
D.CITY = {
    hp = 200,
    str = 12,          -- plus 2 a citizen, plus walls
    heal = 20,
    workRadius = 3,
    claimRadius = 1,   -- what a new city owns
    borderCost = 10,   -- culture for the first new hex; each costs more
    palace = { food = 0, prod = 2, gold = 5, science = 2, culture = 1 },
    rangedRange = 2,
}

-- Combat, as Civilization VI has it: damage = 30 * e^(difference / 25),
-- times a little luck.
D.COMBAT = {
    base = 30,
    scale = 25,
    fortify = 4,
    healField = 10, healHome = 15, healCity = 20,
}

-- Civilizations: the player first. `look` is how their people are painted
-- (src/models.lua): light cloth, dark cloth, or striped.
D.CIVS = {
    { name = "AURELIA", leader = "YOU", look = "light",
        cities = { "AURUM", "SOLACE", "BRIGHTWATER", "ASHFORD", "LUMEN", "HALCYON", "MERIDIAN", "DAWNHOLD" } },
    { name = "UMBRA", leader = "QUEEN NOCTA", look = "dark",
        cities = { "NOCTIS", "DUSKMERE", "GLOAMING", "CINDERFALL", "SHADEHALL", "EVENFORD", "MIRKWALL" } },
    { name = "VARRO", leader = "KING TESS", look = "stripe",
        cities = { "TESSERA", "BANDHOLM", "STRIATA", "LATTICE", "GRATEFORD", "CHEVRON", "ZIGRATH" } },
}

-- The calendar: a year for each turn, faster early.
function D.year(turn)
    local y = -4000 + (turn - 1) * 40
    if turn > 50 then y = -4000 + 49 * 40 + (turn - 50) * 25 end
    if turn > 100 then y = -4000 + 49 * 40 + 50 * 25 + (turn - 100) * 20 end
    if y < 0 then return (-y) .. " BC" end
    return (y == 0 and 1 or y) .. " AD"
end

return D
