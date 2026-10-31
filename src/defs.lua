-- The numbers: terrain and what it yields, units, buildings, technologies and
-- the civilizations. Close to Civilization VI's where it has one, smaller
-- where a short game wants it.

local D = {}

D.COLS, D.ROWS = 34, 22
-- The game ends as the cataclysm does (src/cataclysm.lua, D.HEAT): when
-- this turn is played out, the highest score wins.
D.LAST_TURN = 160

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

-- The wild: animals that are on the map for the rules, not only the screen
-- (src/beasts.lua). They belong to no civilization (owner 0, Game.WILD),
-- fight as units do and leave something to whoever kills them.
--
-- `temper`: "hostile" goes for anyone near, "neutral" minds its own business
-- until it is struck and then goes for whoever struck it, "shy" runs from
-- anyone near. `lives`: where it walks -- "land", "river" (land on a
-- river, never leaving it) or "ocean". `leash`: how far from its home it
-- strays. `sense`: how near someone must be for it to notice. `loot`: what
-- killing it brings, to the killer (gold) or to their city nearest (food,
-- culture). `night`: strength added in the turns played in the dark, and a
-- hex more it notices from. `across`: strikes only across a river.
D.BEASTS = {
    wolf = { name = "WOLF", str = 16, moves = 2, sight = 2, temper = "hostile", lives = "land", leash = 3, sense = 2,
        night = 6, loot = { gold = 15 }, beast = true },
    bear = { name = "BEAR", str = 30, moves = 1, sight = 2, temper = "hostile", lives = "land", leash = 2, sense = 2,
        loot = { gold = 25, culture = 5 }, beast = true },
    croc = { name = "CROCODILE", str = 22, moves = 1, sight = 1, temper = "hostile", lives = "river", leash = 2, sense = 1,
        across = true, loot = { gold = 20 }, beast = true },
    serpent = { name = "SEA SERPENT", str = 38, moves = 3, sight = 2, temper = "hostile", lives = "ocean", leash = 5,
        sense = 3, sea = true, loot = { gold = 60 }, beast = true },
    boar = { name = "WILD BOAR", str = 18, moves = 2, sight = 2, temper = "neutral", lives = "land", leash = 2, sense = 1,
        loot = { food = 10, gold = 5 }, beast = true },
    aurochs = { name = "AUROCHS", str = 28, moves = 1, sight = 2, temper = "neutral", lives = "land", leash = 2, sense = 1,
        loot = { food = 25, culture = 4 }, beast = true },
    horse = { name = "WILD HORSES", str = 8, moves = 3, sight = 2, temper = "shy", lives = "land", leash = 3, sense = 2,
        loot = { food = 6 }, tame = "horses", beast = true },
}
-- Lairs: a den, a cave or a hive on a hex, which the beasts come out of
-- (one every `every` turns, up to `keep` of them about) until someone walks
-- in with no beast there to stop them and clears it, for `prize`. A hive
-- stings whoever comes in (`sting` damage, never to death) and gives honey.
D.LAIRS = {
    den = { name = "WOLF DEN", beast = "wolf", keep = 2, every = 10, prize = { gold = 40 } },
    cave = { name = "BEAR CAVE", beast = "bear", keep = 1, every = 14, prize = { gold = 50, culture = 10 } },
    hive = { name = "WILD BEES", sting = 20, prize = { gold = 15, food = 15 } },
}
-- How many of each the map starts with, per 100 hexes of land (or of ocean,
-- for the serpents), and how near a civilization's start any may be.
D.WILD = {
    dens = 1.4, caves = 0.8, hives = 1.0,
    boar = 1.6, aurochs = 0.9, horse = 1.0, croc = 1.2, serpent = 1.2,
    clear = 4,      -- no lair or beast this near a start or a city
    herds = 12,     -- turns between new herds wandering in where there are too few
    heal = 10,
}
-- The hour each turn is played at (src/ui/daylight.lua draws by it): part of
-- a day, 0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset. Past 1 is the
-- next day. The dark is before 0.24 and after 0.76.
D.HOURS = { 0.55, 0.66, 0.73, 0.775, 1.0, 1.235, 1.31, 1.43 }
function D.night(turn)
    local h = D.HOURS[(turn - 1) % #D.HOURS + 1] % 1
    return h < 0.24 or h > 0.76
end

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
    -- Against the heat (D.HEAT): the land the city owns dries slower, its
    -- farms keep their food through the drought, fire spreads onto its
    -- hexes less, and its people thirst less.
    cistern = { name = "CISTERN", short = "CIST.", cost = 70, cool = true, tech = "masonry", order = 8 },
}

-- The heat death: the cataclysm that ends the game (src/cataclysm.lua).
-- Each stage begins on its turn and lasts until the next; the game ends
-- with turn D.LAST_TURN.
D.HEAT = {
    omen = 90,         -- the warning
    drought = 100,     -- the land dries: grass to plains to desert
    fires = 120,       -- forests and fields catch fire
    scorch = 140,      -- desert bakes hard and burns whoever stands on it
    -- How many hexes dry a step each turn, in each stage, and how many
    -- hexes of desert bake hard in the scorch.
    dry = { drought = 4, fires = 6, scorch = 8 },
    bake = 6,
    -- How much likelier a hex is to dry than another: beside the desert
    -- already, and the hexes that hold out (a river, the coast, hills, a
    -- cistern's city).
    near = 6, river = 0.25, coast = 0.5, hills = 0.5, cistern = 0.25,
    droughtFarm = 1,   -- food a farm off a river loses from the drought on
    -- Thirst: food every city loses a turn, in each stage; a cistern spares
    -- it `cisternThirst` of that.
    thirst = { fires = 2, scorch = 4 },
    cisternThirst = 2,
    -- Fires: how many start a turn somewhere hot, how long one burns, the
    -- chance it spreads to each forest, and each field or meadow, beside it.
    ignite = { fires = 2, scorch = 4 },
    burn = 3,
    spreadForest = 0.4, spreadField = 0.08,
    cisternFire = 0.5, -- the chance of spreading onto a cistern's land, times this
    fireDamage = 25,   -- to a unit in a burning hex, each turn
    cityBurn = 20,     -- to a city, for each burning hex beside it
    scorchDamage = 10, -- to a unit on baked earth (off a river), each turn
}

-- Technologies, in the order the list shows them.
D.TECHS = {
    { id = "pottery", name = "POTTERY", cost = 25, needs = {}, gives = "GRANARY" },
    { id = "mining", name = "MINING", cost = 25, needs = {}, gives = "MINES" },
    { id = "archery", name = "ARCHERY", cost = 35, needs = {}, gives = "ARCHER" },
    { id = "masonry", name = "MASONRY", cost = 40, needs = { "mining" }, gives = "WALLS, CISTERN" },
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
