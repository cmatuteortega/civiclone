-- The numbers: terrain and what it yields, units, buildings, technologies and
-- the civilizations. Close to Civilization VI's where it has one, smaller
-- where a short game wants it.

local D = {}

D.COLS, D.ROWS = 34, 22
-- The game ends as the cataclysm does (src/cataclysm.lua, D.HEAT): when
-- this turn is played out, the highest score wins. A game with no
-- cataclysm ends sooner, as games did before there was one.
D.LAST_TURN = 160
D.PLAIN_LAST_TURN = 150

-- Each land hex is a base (grass, plains, desert) at an elevation (flat,
-- hills, mountains), and maybe has a forest on it. Water is coast or ocean.
-- `top`: how high the hex stands, in room units.
D.TERRAIN = {
    ocean = { name = "OCEAN", food = 1, prod = 0, gold = 0, water = true, top = -2 },
    coast = { name = "COAST", food = 1, prod = 0, gold = 1, water = true, top = -2 },
    grass = { name = "GRASSLAND", food = 2, prod = 0, gold = 0, top = 4 },
    plains = { name = "PLAINS", food = 1, prod = 1, gold = 0, top = 4 },
    desert = { name = "DESERT", food = 0, prod = 0, gold = 0, top = 4 },
    -- Only the long rains make it (D.FLOOD): sodden lowland, reeds and
    -- standing pools, heavy going and no good for a farm.
    marsh = { name = "MARSH", food = 1, prod = 0, gold = 0, top = 4, move = 1, noFarm = true },
    -- Only the cold makes these (src/frost.lua): the endless night of the
    -- still sun (D.SUN) and the long night of the sky's falling (D.SKY).
    -- Frozen ground, rimed and hard, where little will grow; then snow, deep
    -- and drifted, that buries a farm and slows whoever wades it; and the
    -- sea frozen hard enough to walk on, `ice`, that no ship can sail and
    -- no city stand on.
    tundra = { name = "TUNDRA", food = 1, prod = 0, gold = 0, top = 4, frozen = true },
    snow = { name = "SNOW", food = 0, prod = 0, gold = 0, top = 4, move = 1, noFarm = true, frozen = true },
    ice = { name = "SEA ICE", food = 0, prod = 0, gold = 0, top = -2, noFarm = true, noCity = true, frozen = true,
        sea = true },
    -- Only the heat death's great ebb makes it (D.HEAT): the sea's floor
    -- left bare as the sea draws back, a crust of salt over dried mud,
    -- low in the hollow where the water stood. It is walked on, and burns.
    saltflat = { name = "SALT FLAT", food = 0, prod = 0, gold = 1, top = 0, noFarm = true, noCity = true },
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
    -- Only the sky's falling leaves it (D.SKY): the iron of a fallen star,
    -- black and heavy, in the crater it made.
    iron = { name = "STAR IRON", food = 0, prod = 2, gold = 1 },
    -- Only the sundering leaves it (D.QUAKE): black glass where the lava
    -- cooled fast, for blades and for trade.
    obsidian = { name = "OBSIDIAN", food = 0, prod = 1, gold = 2 },
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
-- What else a builder can do to the land (Game:worksFor): each takes all its
-- moves and one of its builds, as an improvement does.
--   chop   fells a forest inside its borders: the wood, `prod` production,
--          goes to the city whose land it is, and stumps are left.
--   clear  cuts a firebreak: the grass, the grain and the farm cut and burnt
--          back, so that nothing there can catch fire again (a farm built on
--          it again can).
--   douse  beats out the fires on its hex and beside it: each burns `turns`
--          less, and one by a river, the coast or a cistern's city goes out.
--          A fire put out burns out, as it would have.
--   mend   heals one thing the cataclysm did to its hex: the blight burnt off
--          (only out of every rift's and the citadel's reach), baked earth
--          watered back to plains (by a river or in a cistern's city's
--          land), black rock broken up (its obsidian lost), a cold crater
--          filled (not one with star iron in it), the ash dug in (the soil
--          rich at once), a marsh drained to grassland (`marshTech`).
D.WORKS = {
    chop = { name = "CHOP", prod = 20 },
    clear = { name = "FIREBREAK" },
    douse = { name = "DOUSE", turns = 2 },
    mend = { name = "MEND", marshTech = "masonry" },
}

-- Units. A city trains four things: a settler, a builder, a band and a
-- ship. What a band or a ship is comes from what it carries (D.GEAR): a
-- band with a bow is an archer, with a bow on a horse a horse archer, and
-- with nothing a scout. `str` is melee strength (or how well it stands when
-- it is attacked), `ranged` and `range` a ranged unit's shot, `moves` its
-- movement points. `pop`: a settler takes a citizen with it. `sea`: a ship,
-- that sails the coast (and the ocean, after Cartography) and is built only
-- by a city on the water. `bare`: what a band with no weapon is instead
-- (lighter, and seeing further). `armed`: it always carries a weapon.
D.UNITS = {
    settler = { name = "SETTLER", cost = 70, str = 0, moves = 2, sight = 2, civilian = true, pop = 1, order = 1 },
    builder = { name = "BUILDER", cost = 45, str = 0, moves = 2, sight = 2, civilian = true, charges = 3, order = 2 },
    band = { name = "BAND", cost = 30, str = 10, moves = 2, sight = 2, order = 3, geared = true,
        bare = { moves = 3, sight = 3 } },
    ship = { name = "SHIP", cost = 45, str = 15, moves = 3, sight = 2, sea = true, tech = "sailing", order = 4,
        geared = true, armed = true },
}

-- What a band or a ship carries, a piece in each `slot`. `cost`: production
-- on top of the unit's own. A weapon sets `str` (and `ranged`/`range`); a
-- mount or armour adds `plus` to it, and a mount sets `moves`. `tech`: what
-- has to be known to give it out (taken from the fallen, it needs nothing).
-- `replaces`: once it can be given out, the piece it names no longer is --
-- the bow the sling, the spear the club and the sword the spear. `loot`:
-- only ever taken, never made. `form`: what a unit carrying it is called,
-- on foot and (`mounted`) on a horse.
D.GEAR = {
    club = { name = "CLUB", slot = "weapon", unit = "band", cost = 10, str = 20, order = 1,
        form = "warrior", mounted = "horseman" },
    sling = { name = "SLING", slot = "weapon", unit = "band", cost = 5, str = 5, ranged = 15, range = 2, order = 2,
        form = "slinger", mounted = "mountedslinger" },
    bow = { name = "BOW", slot = "weapon", unit = "band", cost = 30, str = 15, ranged = 25, range = 2, order = 3,
        tech = "archery", replaces = "sling", form = "archer", mounted = "horsearcher" },
    spear = { name = "SPEAR", slot = "weapon", unit = "band", cost = 35, str = 25, order = 4,
        tech = "bronze", replaces = "club", form = "spearman", mounted = "lancer" },
    sword = { name = "SWORD", slot = "weapon", unit = "band", cost = 60, str = 35, order = 5,
        tech = "iron", replaces = "spear", form = "swordsman", mounted = "knight" },
    horse = { name = "HORSE", slot = "mount", unit = "band", cost = 40, plus = 10, moves = 4, order = 6,
        tech = "horses" },
    hide = { name = "BEAR HIDE", slot = "armour", unit = "band", cost = 0, plus = 3, order = 7, loot = true },
    ram = { name = "RAM", slot = "weapon", unit = "ship", cost = 20, str = 25, order = 8, form = "galley" },
    bolt = { name = "BOLT THROWER", slot = "weapon", unit = "ship", cost = 65, str = 20, ranged = 25, range = 2,
        order = 9, tech = "shipbuilding", form = "quadrireme" },
}
D.SLOTS = { "weapon", "mount", "armour" }
-- What took each piece's place: D.GEAR_REPLACED_BY.sling == "bow".
D.GEAR_REPLACED_BY = {}
for id, g in pairs(D.GEAR) do
    if g.replaces then D.GEAR_REPLACED_BY[g.replaces] = id end
end
-- What a band is called with no weapon, on foot and on a horse.
D.BARE = { form = "scout", mounted = "rider" }
-- Every form a unit can take, by its name, and what it is and carries:
-- D.FORMS.archer == { unit = "band", gear = { weapon = "bow" } }. A unit's
-- `kind` is its form (or "settler" or "builder"), so it can be looked up
-- by what it is called.
D.FORMS = { scout = { unit = "band", gear = {} }, rider = { unit = "band", gear = { mount = "horse" } } }
for id, g in pairs(D.GEAR) do
    if g.form then D.FORMS[g.form] = { unit = g.unit, gear = { weapon = id } } end
    if g.mounted then D.FORMS[g.mounted] = { unit = g.unit, gear = { weapon = id, mount = "horse" } } end
end
-- Their names, as the news and the panels say them.
D.FORM_NAMES = {
    scout = "SCOUT", rider = "RIDER", warrior = "WARRIOR", horseman = "HORSEMAN", slinger = "SLINGER",
    mountedslinger = "MOUNTED SLINGER", archer = "ARCHER", horsearcher = "HORSE ARCHER", spearman = "SPEARMAN",
    lancer = "LANCER", swordsman = "SWORDSMAN", knight = "KNIGHT", galley = "GALLEY", quadrireme = "QUADRIREME",
}

-- The form of a unit of `unit` ("band", "ship", ...) carrying `gear`.
function D.formOf(unit, gear)
    local base = D.UNITS[unit]
    if not base.geared then return unit end
    gear = gear or {}
    local w = gear.weapon and D.GEAR[gear.weapon]
    local mounted = gear.mount ~= nil
    if not w then return mounted and D.BARE.mounted or D.BARE.form end
    return mounted and w.mounted or w.form
end

-- What a unit of `unit` carrying `gear` is: its numbers put together, kept
-- once for each way of carrying. `kind` is its form, `unit` and `gear` what
-- it was made from.
local defs = {}
function D.unitDef(unit, gear)
    local base = assert(D.UNITS[unit], unit)
    if not base.geared then return base end
    gear = gear or {}
    local key = unit .. ":" .. (gear.weapon or "") .. ":" .. (gear.mount or "") .. ":" .. (gear.armour or "")
    local def = defs[key]
    if def then return def end
    def = {}
    for k, v in pairs(base) do def[k] = v end
    def.bare, def.geared, def.armed = nil, nil, nil
    def.unit, def.gear = unit, { weapon = gear.weapon, mount = gear.mount, armour = gear.armour }
    def.kind = D.formOf(unit, gear)
    def.name = D.FORM_NAMES[def.kind] or def.kind:upper()
    local w = gear.weapon and D.GEAR[gear.weapon]
    if w then
        def.str, def.ranged, def.range = w.str, w.ranged, w.range
        def.cost = def.cost + w.cost
    elseif base.bare then
        for k, v in pairs(base.bare) do def[k] = v end
        def.scout = true
    end
    for _, slot in ipairs({ "mount", "armour" }) do
        local g = gear[slot] and D.GEAR[gear[slot]]
        if g then
            def.str = def.str + (g.plus or 0)
            def.cost = def.cost + g.cost
            if g.moves then def.moves = g.moves end
        end
    end
    def.mounted = gear.mount ~= nil or nil
    def.hide = gear.armour ~= nil or nil
    defs[key] = def
    return def
end

-- A unit's own copy of what it carries.
function D.copyGear(g)
    return { weapon = g and g.weapon, mount = g and g.mount, armour = g and g.armour }
end

-- The gear's cost alone, on top of the unit's own.
function D.gearCost(gear)
    local n = 0
    for _, slot in ipairs(D.SLOTS) do
        local g = gear and gear[slot] and D.GEAR[gear[slot]]
        if g then n = n + g.cost end
    end
    return n
end

-- Rank, from the fights a unit has come through (`xp`): kept by the unit
-- whatever it carries, so a band that has seen much stays worth keeping.
-- An attack it lives through is a point, a kill two.
D.RANKS = {
    { xp = 3, name = "VETERAN", str = 2 },
    { xp = 8, name = "ELITE", str = 4 },
}
function D.rank(xp)
    local r
    for _, k in ipairs(D.RANKS) do if (xp or 0) >= k.xp then r = k end end
    return r
end

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
        loot = { gold = 25, culture = 5, gear = "hide" }, beast = true },
    croc = { name = "CROCODILE", str = 22, moves = 1, sight = 1, temper = "hostile", lives = "river", leash = 2, sense = 1,
        across = true, loot = { gold = 20 }, beast = true },
    serpent = { name = "SEA SERPENT", str = 38, moves = 3, sight = 2, temper = "hostile", lives = "ocean", leash = 5,
        sense = 3, sea = true, loot = { gold = 60 }, beast = true },
    boar = { name = "WILD BOAR", str = 18, moves = 2, sight = 2, temper = "neutral", lives = "land", leash = 2, sense = 1,
        loot = { food = 10, gold = 5 }, beast = true },
    aurochs = { name = "AUROCHS", str = 28, moves = 1, sight = 2, temper = "neutral", lives = "land", leash = 2, sense = 1,
        loot = { food = 25, culture = 4 }, beast = true },
    horse = { name = "WILD HORSES", str = 8, moves = 3, sight = 2, temper = "shy", lives = "land", leash = 3, sense = 2,
        loot = { food = 6 }, tame = "horses", beast = true },    -- The demons' (src/demons.lua): owned by the wild too, but they belong
    -- to no lair's leash and go for the towns. `demon`: one of them, drawn
    -- ink-black with pale eyes so it is never taken for a beast. `drags`: it
    -- pulls a civilian or anyone in a boat under at a blow. `shore`: it
    -- lives in the coast's water beside the land and never moves (its one
    -- move is for its blow).
    spider = { name = "HELL SPIDER", str = 22, moves = 3, sight = 2, temper = "demon", lives = "land", leash = 3, sense = 5,
        night = 4, loot = { gold = 10, glory = 0.5 }, demon = true },
    eye = { name = "GIANT EYE", str = 16, ranged = 28, range = 2, moves = 2, sight = 3, temper = "demon", lives = "land",
        leash = 3, sense = 5, loot = { gold = 16, culture = 4, glory = 1 }, demon = true },
    tentacle = { name = "TENTACLE", str = 30, moves = 1, sight = 1, temper = "demon", lives = "shore", leash = 0, sense = 1,
        sea = true, drags = true, loot = { gold = 15, glory = 1 }, demon = true },
    brood = { name = "BROOD MOTHER", str = 44, moves = 2, sight = 2, temper = "demon", lives = "land", leash = 4, sense = 9,
        night = 4, loot = { gold = 40, culture = 8, glory = 2 }, demon = true },
    abyss = { name = "EYE OF THE ABYSS", str = 58, moves = 1, sight = 3, temper = "demon", lives = "land", leash = 99,
        sense = 99, loot = { gold = 150, culture = 40, glory = 10 }, demon = true, boss = true },
    -- The plague's (src/plague.lua): a swarm of rats out of a sick town's
    -- granaries, that runs for the towns still well and brings the sickness
    -- into them. `vermin`: it plays in the plague's turn, not the wild's,
    -- and fights no one.
    rats = { name = "PLAGUE RATS", str = 8, moves = 2, sight = 2, temper = "vermin", lives = "land", leash = 6, sense = 6,
        loot = { gold = 4 }, vermin = true },
}
-- Lairs: a den, a cave or a hive on a hex, which the beasts come out of
-- (one every `every` turns, up to `keep` of them about) until someone walks
-- in with no beast there to stop them and clears it, for `prize`. A hive
-- stings whoever comes in (`sting` damage, never to death) and gives honey.
D.LAIRS = {
    den = { name = "WOLF DEN", beast = "wolf", keep = 2, every = 10, prize = { gold = 40 } },
    cave = { name = "BEAR CAVE", beast = "bear", keep = 1, every = 14, prize = { gold = 50, culture = 10 } },
    hive = { name = "WILD BEES", sting = 20, prize = { gold = 15, food = 15 } },
    -- The demons' (src/demons.lua): a rift torn in the ground, and their one
    -- capital, the citadel, which stands `hp` and must be beaten down before
    -- anyone can walk in and raze it. Neither sends out beasts as a den does.
    rift = { name = "RIFT", demon = true, prize = { gold = 30, culture = 8, glory = 2 } },
    citadel = { name = "CITADEL OF THE ABYSS", demon = true, citadel = true, prize = { gold = 150, culture = 40, glory = 10 } },
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

-- How far room point (x, z) is into the day of the still sun (D.SUN), in
-- hexes across: above 0 the day side of the line the dark ends on, below
-- it the night's. Nil before the sun has stood still.
function D.sunSide(game, x, z)
    local c = game and game.cataclysm
    local line = c and c.kind == "sun" and c.line
    if not line then return nil end
    return (x * line.nx + z * line.nz - line.d) / line.w
end

-- The hour turn `turn` is played at, counting whole days (src/ui/daylight.lua
-- draws by it). Under the still sun (D.SUN) the days grow long from its
-- omen on, the sun crossing less of the sky each turn, until it comes to
-- noon and stops there.
function D.hour(turn, game)
    local n, hours = turn - 1, D.HOURS
    if game and game.cataclysm and game.cataclysm.kind == "sun" and turn > D.SUN.omen then
        local h0 = D.hour(D.SUN.omen)
        local noon = math.ceil(h0 - 0.2) + 0.5
        local f = math.min(1, (turn - D.SUN.omen) / (D.SUN.still - D.SUN.omen))
        return h0 + (noon - h0) * (1 - (1 - f) * (1 - f))
    end
    return math.floor(n / #hours) + hours[n % #hours + 1]
end

-- Is it dark on turn `turn`? On hex `cell`, if given: where the sun has
-- stood still (D.SUN) it is always night on its night side, never on its
-- day side, and the twilight between is dusk.
function D.night(turn, game, cell)
    -- In the long night of the sky's falling (D.SKY) the sun never rises.
    if game and game.cataclysm and game.cataclysm.kind == "sky" and turn >= D.SKY.dark then return true end
    if cell then
        local s = D.sunSide(game, cell.x, cell.z)
        if s then return s < 0 end
    end
    local h = D.hour(turn, game) % 1
    return h < 0.24 or h > 0.76
end

-- A land unit on the water rows across it in a boat: embarked. It moves as
-- far as this, stands this strong whatever it is, and cannot attack.
-- Stepping from the land onto the water, or back, takes all its moves.
D.EMBARK = { moves = 3, str = 10 }

-- Buildings: what each adds to its city every turn. `icon` and `says` are
-- how the city's build list shows it: the icon on its row, the lines in the
-- tooltip over it.
D.BUILDINGS = {
    monument = { name = "MONUMENT", short = "MON.", cost = 50, culture = 2, order = 1,
        icon = "culture", says = { "+2 CULTURE" } },
    granary = { name = "GRANARY", short = "GRAN.", cost = 65, food = 2, tech = "pottery", order = 2,
        icon = "food", says = { "+2 FOOD" } },
    library = { name = "LIBRARY", short = "LIB.", cost = 90, science = 2, tech = "writing", order = 3,
        icon = "science", says = { "+2 SCIENCE" } },
    market = { name = "MARKET", short = "MKT.", cost = 100, gold = 4, tech = "currency", order = 4,
        icon = "gold", says = { "+4 GOLD" } },
    walls = { name = "WALLS", short = "WALLS", cost = 80, defense = 10, hp = 100, tech = "masonry", order = 5, icon = "shield",
        says = {
            "+10 DEFENSE, +100 HP",
            "SHOOTS THE WEAKEST ENEMY IN REACH",
        } },
    -- Only a city on the water: each worked water hex yields this much more.
    harbour = { name = "HARBOUR", short = "HARB.", cost = 90, seaFood = 1, coastal = true, tech = "shipbuilding", order = 6,
        icon = "food", says = { "+1 FOOD FROM EACH WORKED WATER HEX" } },
    lighthouse = { name = "LIGHTHOUSE", short = "LIGHT.", cost = 80, seaGold = 1, sight = 4, coastal = true, tech = "cartography",
        order = 7, icon = "gold",
        says = {
            "+1 GOLD FROM EACH WORKED WATER HEX",
            "THE CITY SEES 4 HEXES AWAY",
        } },
    -- Against the heat (D.HEAT): the land the city owns dries slower, its
    -- farms keep their food through the drought, fire spreads onto its
    -- hexes less, and its people thirst less.
    -- Under the still sun (D.SUN) it holds off the endless day as well.
    cistern = { name = "CISTERN", short = "CIST.", cost = 70, ward = { heat = true, sun = true }, tech = "masonry",
        order = 8, icon = "star",
        says = {
            "AGAINST THE HEAT AND THE ENDLESS DAY:",
            "ITS LAND DRIES SLOWER AND BURNS LESS,",
            "ITS FARMS KEEP THEIR FOOD, ITS PEOPLE THIRST LESS",
        } },
    -- Against the deluge (D.FLOOD): banks of earth faced with stone round
    -- the city's land. Its land floods and sours to marsh less, the sea
    -- can't take it, the city takes no harm from the water beside it, and
    -- its people sicken less.
    -- In the sundering (D.QUAKE) it keeps the waves out of the city.
    levee = { name = "LEVEE", short = "LEVEE", cost = 70, ward = { flood = true, quake = true }, tech = "masonry",
        order = 9, icon = "star",
        says = {
            "AGAINST THE DELUGE AND THE WAVES:",
            "ITS LAND FLOODS LESS, THE SEA CANNOT TAKE IT,",
            "ITS PEOPLE SICKEN LESS",
        } },
    -- Against any cataclysm (D.SHELTER): cellars dug under the city, roofed
    -- with turf, where its people hide and its grain is kept. Built only
    -- when the world is ending, and the one ward the sky's falling has.
    shelter = { name = "SHELTER", short = "SHELT.", cost = 60, ward = "any", tech = "mining", order = 10, icon = "star",
        says = {
            "AGAINST ANY CATACLYSM:",
            "HALF THE HARM OF ITS BLOWS,",
            "STORES THAT SPARE FOOD IN THE HARD TURNS",
        } },
    -- Against the demons (D.DEMONS): a ring of carved standing stones and a
    -- lamp kept burning. No rift opens on the city's land and the blight
    -- never takes it, the city shoots the demons near it even without walls,
    -- and its people dread less.
    sanctum = { name = "SANCTUM", short = "SANCT.", cost = 70, ward = "demons", tech = "writing", order = 11, icon = "star",
        says = {
            "AGAINST THE DEMONS:",
            "NO RIFT OPENS ON ITS LAND, NO BLIGHT,",
            "IT SHOOTS DEMONS NEAR IT, ITS PEOPLE DREAD LESS",
        } },
    -- Against the endless night of the still sun (D.SUN): a kiln-house of
    -- stone with a tall chimney, its fire never let go out, and the city's
    -- peat and wood stacked by it. The land the city owns freezes slower,
    -- its farms keep their food through the night, and its people go less
    -- cold.
    -- In the long night of the sky's falling (D.SKY) it does as much.
    hearth = { name = "HEARTH", short = "HEARTH", cost = 70, ward = { sun = true, sky = true }, tech = "pottery",
        order = 12, icon = "star",
        says = {
            "AGAINST THE ENDLESS NIGHT AND THE COLD:",
            "ITS LAND FREEZES SLOWER, ITS FARMS KEEP",
            "THEIR FOOD, ITS PEOPLE GO LESS COLD",
        } },
    -- Against the plague (D.PLAGUE): a house of the sick outside the
    -- houses of the well, long and low, its beds in a row and a herb garden
    -- by it. Fewer of the city's sick die, they mend sooner, the well stay
    -- well longer after, and its people go hungry less.
    lazaret = { name = "LAZARET", short = "LAZAR.", cost = 70, ward = "plague", tech = "writing", order = 13, icon = "star",
        says = {
            "AGAINST THE PLAGUE:",
            "FEWER OF ITS SICK DIE AND THEY MEND SOONER,",
            "THE WELL STAY WELL LONGER",
        } },
    -- Against the sundering (D.QUAKE): the city's walls and halls shored up
    -- with stone buttresses and braced with timber. A quake does it half
    -- the harm and never brings a building down, kills half as many of its
    -- people, no fault opens on its land, and its people fear less.
    buttress = { name = "BUTTRESS", short = "BUTTR.", cost = 70, ward = "quake", tech = "masonry", order = 14, icon = "star",
        says = {
            "AGAINST THE SUNDERING:",
            "HALF THE HARM FROM A QUAKE, NO BUILDING FALLS,",
            "HALF AS MANY DIE, NO FAULT OPENS ON ITS LAND",
        } },
}

-- The shelter, against whatever ends the world: a city with one takes only
-- `harm` of the cataclysm's blows (a stone from the sky, a fire or a flood
-- beside it, the surge), and its stores spare it `stores` food a turn of
-- the thirst, the fever or the cold (`skyStores` of the cold, the sky's
-- own ward). A stone that falls on it kills none of its people.
D.SHELTER = { harm = 0.5, stores = 1, skyStores = 2 }

-- The weather (src/weather.lua): short spells of rain and storm that come
-- and go over the whole map. After `calm` turns of fair weather, each turn
-- the clouds gather with chance `chance` (from turn `from`), and the spell
-- begins the turn after. A spell is `stormChance` likely to be a storm:
-- `lead` turns of rain, `storm` turns of storm (a range), then `tail` of
-- rain; otherwise `rain` turns of rain (a range).
--   clouds the sky `overcast` (the shaders' cloud), and word of what comes.
--   rain   farms yield `farmFood` more food; each fire burning goes out
--          with chance `douse` a turn, and the heat's own fires don't start.
--   storm  as rain, and mines yield `mineProd` less production, fishing
--          boats `boatsFood` less food (they stay in harbour), every unit
--          sees `blind` hexes less (never under 1), and each ship out at sea
--          loses `shipHit` health a turn, each unit in a boat `boatHit`,
--          unless in port: within `haven` hexes of a city of its own, or
--          `harbour` hexes of one with a harbour.
-- Once a cataclysm begins the sky is its own, but in the stages in `open`
-- (those that burn) the weather goes on: rain only, `cataclysmChance` as
-- often.
D.WEATHER = {
    from = 6, calm = 5, chance = 0.12, stormChance = 0.35,
    rain = { 3, 5 }, lead = 1, storm = { 2, 3 }, tail = 1,
    farmFood = 1, mineProd = 1, boatsFood = 1, blind = 1,
    overcast = 0.6, douse = 0.5,
    shipHit = 25, boatHit = 35, haven = 1, harbour = 3,
    cataclysmChance = 0.5,
    open = {
        heat = { omen = true, drought = true, fires = true },
        sky = { omen = true, starfall = true, bombard = true },
        quake = { omen = true, tremors = true, rift = true, fire = true },
    },
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
    -- The rivers fail: how many stretches of river (an edge between two
    -- hexes each) dry up a turn, in each stage, from the springs down. A
    -- dry river is a bed of cracked mud: no gold, no water for the farms,
    -- no ford, and the land by it dries as fast as any.
    riverDry = { drought = 1, fires = 2, scorch = 3 },
    riverCistern = 0.25, -- how likely a cistern's river is to fail, times this
    -- The great ebb: told on `warn`, on `ebb` the sea draws back from every
    -- shore at once, its shallows left as salt flats that can be walked
    -- on, and the deep water beside them shallows; after it, `recede` more
    -- hexes of the shallows go dry each turn. A land unit that ends a turn
    -- on a salt flat in the scorch loses `scorchDamage`, as on baked earth.
    warn = 144, ebb = 150, recede = 4,
}

-- The deluge: the other way the world can end (src/flood.lua), on the same
-- turns as the heat death and to the same last turn.
D.FLOOD = {
    omen = 90,         -- the warning
    rains = 100,       -- the land grows wet: desert to plains to grass, and lowland to marsh
    floods = 120,      -- the rivers burst their banks
    sea = 140,         -- the sea rises over the low coasts
    -- How many hexes grow a step wetter each turn, in each stage.
    wet = { rains = 4, floods = 5, sea = 6 },
    -- How much likelier a hex is to go to marsh beside water already (a
    -- river, the sea, the marsh), and on a levee's land.
    near = 6, levee = 0.25,
    rainFarm = 1,      -- food a farm gains from the rains on
    -- Floods: how many start a turn on the rivers, how long one lies, the
    -- chance it spreads to a river hex beside it no higher, and to other
    -- low land; a forest (roots), silt (flooded before) and a levee's land
    -- take it less.
    burst = { floods = 2, sea = 3 },
    last = 3,
    spreadRiver = 0.35, spreadLand = 0.08,
    forest = 0.5, silted = 0.3, leveeFlood = 0.25,
    floodDamage = 20,  -- to a unit in a flooded hex, each turn
    cityFlood = 15,    -- to a city with no levee, for each flooded hex beside it
    siltFood = 1,      -- what the flood leaves: this much more food, for good
    -- Fever: food every city loses a turn, in each stage; a levee spares it
    -- `leveeFever` of that.
    fever = { floods = 2, sea = 4 },
    leveeFever = 2,
    -- The sea: how many hexes of low land it takes each turn, lowest first
    -- (the n-th lowest is `low`^n as likely as the lowest), and what it does
    -- to a city with no levee on the shore.
    rise = 3, low = 0.85,
    surge = 10,
    -- The great flood: told on `warn`, the sea rises over the land in two
    -- steps, the first terrace (`levels[1]` high, the lowland) on `great`,
    -- the second (`levels[2]`, the upland) on `second`: every hex of flat
    -- land no higher than that, joined to the sea, is taken, and every
    -- city on it sunk with all that stood there, its ruins left under the
    -- water. Only the hills and mountains stand out of it. A levee holds
    -- its city through the first, not the second.
    warn = 144, great = 150, second = 155,
    levels = { 4, 6 },
}

-- The sky falls: the third way the world can end (src/skyfall.lua), on the
-- same turns as the others and to the same last turn. Every stone is seen
-- coming: its hex is marked the turn before it falls.
D.SKY = {
    omen = 90,         -- the comet is seen
    starfall = 100,    -- small stones fall
    bombard = 120,     -- and big ones, and the dust starts to hide the sun
    dark = 140,        -- the long night: the sun is never seen again
    -- How many stones fall a turn, in each stage, and how many of them are
    -- big (a part); how much likelier one is to fall on land than on water.
    fall = { starfall = 3, bombard = 6, dark = 4 },
    big = { starfall = 0, bombard = 0.5, dark = 0.4 },
    land = 1.6,
    -- What a stone does to a unit on its hex, and to a city there (`city`)
    -- in HP; a big one hurts what is beside it too (`near`, `nearCity`) and
    -- kills `pop` of a city's people.
    hit = { small = 35, big = 70 }, city = { small = 20, big = 50 },
    near = 15, nearCity = 10, pop = 1,
    -- How far each crater sinks its hex (room units; hills are flattened and
    -- mountains broken to hills first), never below `floor` nor below a
    -- river along it. A crater yields `craterFood` less, nothing while it is
    -- still hot (`glow` turns), and holds star iron one time in `iron`.
    sink = { small = 1, big = 2 }, floor = 0.5,
    craterFood = 1, glow = 2, iron = 0.3,
    burn = 0.5,        -- the chance a stone sets a forest beside it alight
    -- The cold, as the dust hides the sun: food every city loses a turn, in
    -- each stage. In the long night every farm yields `darkFarm` less.
    cold = { bombard = 2, dark = 4 },
    darkFarm = 1,
    -- A hearth (D.BUILDINGS.hearth) spares a city `hearth` food of the
    -- cold, and keeps its farms' food through the long night.
    hearth = 2,
    -- The heart of the comet: told on `heartWarn`, it falls on `heart`, on a
    -- hex and the six round it. The middle sinks `heartSink`, the ring
    -- `ringSink`; what stands in the middle takes `heartHit`, in the ring
    -- `ringHit`, two hexes out `shock`; a city in the middle loses `heartPop`
    -- of its people and is left with 1 HP, one in the ring takes `ringCity`.
    heartWarn = 144, heart = 150,
    heartSink = 4, ringSink = 2,
    heartHit = 100, ringHit = 60, shock = 25,
    heartPop = 0.5, ringCity = 80,
    -- The long night's frost (src/frost.lua): how many hexes of land freeze
    -- a step a turn, and how many of the sea's shallows freeze to ice.
    frost = { dark = 5 }, freeze = { dark = 2 },
}

-- The demons: the fourth way the world can end (src/demons.lua), on the
-- same turns as the others and to the same last turn. The first that fights
-- back: what holds it off is an army as much as a building.
D.DEMONS = {
    omen = 90,         -- the blood moon; on turn 99 the citadel's ground is seen marked
    rifts = 100,       -- the citadel rises, and rifts open in the land
    deep = 120,        -- tentacles rise out of the sea by the shore
    hellgate = 140,    -- the brood mothers come, and the Eye of the Abyss
    -- The citadel, the demons' one capital: how far it stands from every
    -- city (at least), its strength and HP in each stage (it grows), what it
    -- heals a turn, how far its blight reaches, how often it sends a demon
    -- out and how many of its own it keeps about.
    citadelFrom = 5,
    citadelStr = { rifts = 26, deep = 34, hellgate = 44 },
    citadelHp = { rifts = 200, deep = 260, hellgate = 320 },
    citadelHeal = 15,
    citadelReach = { rifts = 2, deep = 3, hellgate = 4 },
    citadelEvery = { rifts = 3, deep = 2, hellgate = 2 },
    citadelKeep = { rifts = 3, deep = 5, hellgate = 7 },
    citadelHit = 15,   -- to every unit beside it, each turn
    -- Rifts: the chance one opens a turn, how many may be open at once, how
    -- near a city it may open, how often it sends a demon out, how many of
    -- its own it keeps about and how far its blight reaches. Each is seen
    -- coming the turn before.
    rift = { rifts = 0.35, deep = 0.5, hellgate = 0.6 },
    riftMax = { rifts = 4, deep = 6, hellgate = 8 },
    riftFrom = { rifts = 3, deep = 2, hellgate = 2 },
    riftEvery = { rifts = 4, deep = 3, hellgate = 3 },
    riftKeep = { rifts = 2, deep = 2, hellgate = 3 },
    riftReach = { rifts = 1, deep = 2, hellgate = 2 },
    -- Tentacles: how many rise a turn by the shore, how many may be up at
    -- once, and how many turns one stays before it sinks. Seen coming the
    -- turn before. With nothing to strike it wrecks what is beside it by
    -- `wreck`.
    tentacles = { deep = 1, hellgate = 2 },
    tentacleMax = { deep = 4, hellgate = 7 },
    tentacleLife = 8,
    wreck = 0.35,
    -- The blight: how many hexes each rift (and the citadel, `citadelSpread`)
    -- blights a turn within its reach, what it does to a unit standing on
    -- it, and the chance a blighted hex out of every reach heals a turn.
    spread = 2, citadelSpread = 3,
    blightDamage = 10,
    heal = 0.2,
    -- Dread: food every city loses a turn, in each stage; a sanctum spares
    -- it `sanctumDread`.
    dread = { rifts = 1, deep = 3, hellgate = 6 },
    sanctumDread = 2,
    -- The Eye of the Abyss: told on `eyeWarn`, it comes out of the citadel
    -- on `eye`, if the citadel still stands.
    eyeWarn = 144, eye = 150,
}

-- The still sun: the fifth way the world can end (src/stillsun.lua), on the
-- same turns as the others and to the same last turn. The days grow long
-- and the sun stops, and stays where it stopped: one side of the world is
-- in day for good and the other in night, and a band of twilight lies
-- between. Where the line falls, and which way, is chosen as it stops, a
-- new one every game: nobody can know their side before.
D.SUN = {
    omen = 90,         -- the days grow long: the clock slows
    still = 100,       -- the sun stands still: the endless day, the endless night
    sear = 120,        -- the day burns and the night freezes the sea
    twilight = 140,    -- the last twilight: the band narrows, and the far sides kill
    -- How far the twilight reaches either side of the line, in hexes, in
    -- each stage: it narrows. Where the line falls: through land, at a
    -- point between `from` and `to` of the land's breadth that way.
    band = { still = 3, sear = 2.5, twilight = 1.5 },
    from = 0.3, to = 0.7,
    -- The day side: how many hexes dry a step a turn (as the heat's do,
    -- grass to plains to desert), how many of its deserts bake hard in the
    -- twilight, and how many fires start a turn. A hex `deep` hexes or
    -- more into the day is as likely to dry as any can be; nearer the line,
    -- less. A cistern's land, the rivers, the coast and the hills hold out.
    dry = { still = 4, sear = 6, twilight = 8 },
    bake = 5,
    ignite = { sear = 2, twilight = 3 },
    deep = 5,
    -- The night side, the same: how many hexes freeze a step a turn
    -- (to tundra, then snow), and how many hexes of sea freeze to ice, the
    -- shallows first, the open sea only in the twilight. A hearth's land,
    -- the rivers and the coast hold out.
    frost = { still = 4, sear = 6, twilight = 8 },
    freeze = { sear = 3, twilight = 5 },
    river = 0.3, coast = 0.6, hearth = 0.25,
    -- What it costs a city, in food a turn: thirst on the day side (a
    -- cistern spares `ward` of it), cold on the night side (a hearth
    -- spares as much). Nothing in the twilight.
    thirst = { sear = 2, twilight = 4 },
    cold = { sear = 2, twilight = 4 },
    ward = 2,
    -- A farm off a river in the day, or any farm in the night, yields this
    -- much less food.
    farm = 1,
    -- In the twilight, a unit that ends a turn on baked earth off a river,
    -- or out on the snow, takes this; a ship (or a beast of the sea) the
    -- ice closes round takes `crush` a turn, until it gets out.
    scorchDamage = 10, frostbite = 10, crush = 25,
    -- The great storm: told on `warn`, the turn before `storm` the heat of
    -- the day and the cold of the night meet on the line in `cyclones[1]`
    -- cyclones, and from `storm` on they run along it, `speed` hexes a
    -- turn, each for `life` turns; while fewer than `cyclones[2]` blow, a
    -- new one forms `form` of the turns. Each is seen coming the turn
    -- before: its eye's hex and the six round it. What stands in the eye
    -- takes `eyeHit`, in the ring `ringHit` (ships and boats `sea` times
    -- that); a city `eyeCity` or `ringCity`. A forest is blown down
    -- (`blowDown`), a farm, a mine or the boats wrecked (`wreck`). And
    -- the gales take `gale` food a turn from every city, the twilight's
    -- too.
    warn = 144, storm = 150,
    cyclones = { 3, 5 }, form = 0.5, life = { 6, 9 }, speed = 2,
    eyeHit = 40, ringHit = 20, sea = 1.5, eyeCity = 30, ringCity = 15,
    blowDown = { eye = 0.6, ring = 0.3 }, wreck = { eye = 0.45, ring = 0.2 },
    gale = 2,
}

-- The plague: the sixth way the world can end (src/plague.lua), on the
-- same turns as the others and to the same last turn. The one that goes
-- from town to town: it is carried, by people walking and by rats, and the
-- way to keep it out is to keep them out.
D.PLAGUE = {
    omen = 90,         -- the crows gather; on turn 99 the first sick town is seen
    fever = 100,       -- the first town falls sick, and it spreads
    dying = 120,       -- the great dying: faster, a second outbreak, rats
    dance = 140,       -- the dance of death; on `great` the great pestilence
    -- How many towns fall sick as each stage begins (the first, and a
    -- second, elsewhere, far from the first).
    seeds = { fever = 1, dying = 1 },
    -- And now and then another, from over the sea: the chance a turn.
    flare = { fever = 0.04, dying = 0.08, dance = 0.1 },
    -- From a sick town to a well one: the chance a turn, in each stage, for
    -- a town within `reach` (half as likely for each hex further than 3),
    -- more where both are on a river or both on the coast (`water`), far
    -- less if either is shut (`shut`). A town that has mended can't catch
    -- it again for `immunity` turns.
    spread = { fever = 0.12, dying = 0.18, dance = 0.24 },
    reach = 7, water = 1.6, shut = 0.12, immunity = 14,
    -- People: a unit that ends a turn in a sick town catches it by
    -- `catchIn`, beside one by `catchBy`, beside rats by `catchRats`, and
    -- carries it for `carry` turns, losing `sickHp` a turn (it can die of
    -- it). Walking into or beside a well town it brings it in by `bring`.
    -- A settler that carries it founds a sick town.
    catchIn = 0.5, catchBy = 0.12, catchRats = 0.3, carry = 5, sickHp = 6,
    bring = { fever = 0.3, dying = 0.4, dance = 0.5 },
    -- A sick town: the chance a turn one of its people dies (never the
    -- last), and that a death leaves one of its farms fallow; the chance it
    -- mends a turn, once sick `mendAfter` turns. A lazaret halves the deaths
    -- (`lazaretDeath`) and adds `lazaretMend` to the mending.
    death = { fever = 0.3, dying = 0.45, dance = 0.6 },
    fallow = 0.5,
    mend = { fever = 0.1, dying = 0.08, dance = 0.06 },
    mendAfter = 6,
    lazaretDeath = 0.5, lazaretMend = 0.12,
    -- Food a town loses a turn: the sick (`sick`), and the well from fear
    -- (`fear`); a lazaret spares `ward` of it. A sick or shut town doesn't
    -- grow, and a shut one makes no gold.
    sick = { fever = 1, dying = 2, dance = 3 },
    fear = { dying = 1, dance = 2 },
    ward = 1,
    -- Rats: the chance a turn a sick town sends a swarm out, in each stage,
    -- how many may be out at once, the chance a turn one beside a well
    -- town brings the sickness in, and how many turns a swarm lives. A
    -- farm with rats on it yields no food.
    rats = { dying = 0.3, dance = 0.45 },
    ratMax = { dying = 4, dance = 7 },
    ratBite = 0.35, ratLife = 12,
    -- The great pestilence: told on `warn`, on `great` every sick town loses
    -- `greatLoss` of its people (`lazaretLoss` with a lazaret), and every
    -- well town within `reach` of one that isn't shut falls sick.
    warn = 144, great = 150, greatLoss = 1 / 3, lazaretLoss = 1 / 5,
}

-- The sundering: the seventh way the world can end (src/quake.lua), on the
-- same turns as the others and to the same last turn. The land itself
-- breaks: quakes, faults that open between the hexes, a rift the sea comes
-- in by, mountains thrown up, volcanoes and the waves.
D.QUAKE = {
    omen = 90,         -- the ground trembles; on turn 99 the great rift is seen
    tremors = 100,     -- quakes, and faults open between the hexes
    rift = 120,        -- the rift tears the land apart and the sea comes in; ranges rise
    fire = 140,        -- the volcanoes wake, and the waves come
    -- Quakes: how many strike a turn, in each stage (each seen coming the
    -- turn before, its hex marked), how far each reaches, and what it does:
    -- to a unit within its reach (`hit` at its heart, `near` round it), to
    -- a city (`city` at its heart, `nearCity` round it), the chance it
    -- brings one of a city's buildings down (`fall`) or kills one of its
    -- people (`kill`), and the chance it wrecks a mine or a farm (`wreck`)
    -- or brings a forest down on a hill (`slide`).
    quakes = { omen = 0, tremors = 1, rift = 2, fire = 2 },
    reach = { tremors = 1, rift = 2, fire = 2 },
    hit = 30, near = 12, city = 30, nearCity = 12,
    fall = 0.35, kill = 0.4, wreck = 0.35, slide = 0.3,
    -- Faults: how many edges each quake cracks open between the hexes near
    -- it, and how many more open a turn anywhere along the lines already
    -- open. No one walks across an open fault.
    faults = { tremors = 2, rift = 1, fire = 1 },
    spread = { tremors = 1, rift = 1, fire = 1 },
    -- The rift: told on the omen's last turn, from the sea across the land.
    -- Each turn of the rift and the fire it opens `riftStep` hexes further,
    -- and every hex of it goes cracked, then a chasm, then the sea comes
    -- in, then it is sea (`riftTurns` turns at each step).
    riftLen = { 7, 13 }, riftStep = { rift = 1, fire = 2 }, riftTurns = 2,
    -- The ranges: two places where the land is pressed together, told as
    -- the rift begins. Each turn `uplift` hexes along them rise a step
    -- (shallows to new land, flat to hills, hills to mountains).
    ranges = 2, rangeLen = { 4, 7 }, uplift = { rift = 2, fire = 3 },
    -- Volcanoes: how many wake as the fire begins (the mountains likeliest),
    -- the chance each erupts a turn (seen coming the turn before), how far
    -- its lava runs, and how long a hex of it burns and lies hot. Ash falls
    -- `ashReach` round it and lies `ashTurns`: a farm under it yields
    -- `ashFarm` less, and the ash leaves the land richer (`soil`).
    volcanoes = 3, erupt = 0.4, flow = 2, lavaTurns = 3, lavaHit = 40, lavaCity = 25,
    ashReach = 2, ashTurns = 4, ashFarm = 1, soil = 1, obsidian = 0.3,
    -- The waves: the chance a turn, in each stage, the sea far out heaves
    -- (seen coming the turn before: the sea draws back), how many hexes of
    -- the shore each takes, what it does to a unit on them or a ship by
    -- them, and to a city by the shore (`levee` spares it); the water lies
    -- `waveTurns`.
    waves = { rift = 0.25, fire = 0.5 }, waveLen = { 4, 8 },
    waveHit = 40, waveCity = 30, waveTurns = 2,
    -- Fear: food every city loses a turn, in each stage; a buttress spares
    -- it `ward`.
    fear = { tremors = 2, rift = 4, fire = 6 }, ward = 2,
    -- The great quake: told on `warn`, on `great` the whole rift opens to
    -- the sea at once, every city shakes and a great wave runs round
    -- every shore; every city loses `greatPop` of its people (none with a
    -- buttress, half with a shelter). Quakes strike `nearTowns` times
    -- likelier for every city within two hexes.
    warn = 144, great = 150, greatCity = 40, greatPop = 0.25, nearTowns = 2,
}

-- Technologies, in the order the list shows them.
D.TECHS = {
    { id = "pottery", name = "POTTERY", cost = 25, needs = {}, gives = "GRANARY, HEARTH" },
    { id = "mining", name = "MINING", cost = 25, needs = {}, gives = "MINES, SHELTER" },
    { id = "archery", name = "ARCHERY", cost = 35, needs = {}, gives = "BOW" },
    { id = "masonry", name = "MASONRY", cost = 40, needs = { "mining" }, gives = "WALLS, CISTERN, LEVEE, BUTTRESS" },
    { id = "writing", name = "WRITING", cost = 50, needs = { "pottery" }, gives = "LIBRARY, SANCTUM, LAZARET" },
    { id = "bronze", name = "BRONZE WORKING", cost = 55, needs = { "mining" }, gives = "SPEAR" },
    { id = "horses", name = "HORSEBACK RIDING", cost = 60, needs = { "archery" }, gives = "HORSE" },
    { id = "currency", name = "CURRENCY", cost = 80, needs = { "writing" }, gives = "MARKET" },
    { id = "iron", name = "IRON WORKING", cost = 100, needs = { "bronze" }, gives = "SWORD" },
    { id = "sailing", name = "SAILING", cost = 40, needs = { "pottery" }, gives = "SHIPS, EMBARKING, FISHING BOATS" },
    { id = "shipbuilding", name = "SHIPBUILDING", cost = 70, needs = { "sailing" }, gives = "BOLT THROWER, HARBOUR" },
    { id = "cartography", name = "CARTOGRAPHY", cost = 90, needs = { "shipbuilding" }, gives = "OCEAN, LIGHTHOUSE" },
}
D.TECH = {}
for _, t in ipairs(D.TECHS) do D.TECH[t.id] = t end

-- A city's focus: how it weighs food, production and gold in choosing the
-- hexes its citizens work. `balanced` is what a city does unless told.
D.FOCUS = {
    balanced = { name = "BALANCED", short = "BAL", food = 2.2, prod = 2, gold = 1 },
    food = { name = "FOOD", short = "FOOD", food = 4, prod = 1, gold = 0.5 },
    prod = { name = "PRODUCTION", short = "PROD", food = 1.2, prod = 4, gold = 0.5 },
}
D.FOCUS_ORDER = { "balanced", "food", "prod" }

-- The score at the end: what a civilization has, and what of it lasted.
-- `kept`: up to this many for the share of its people at their most it still
-- has. `land`: each hex of its land that still gives food. `ward`: each city
-- standing at the end with a ward against the cataclysm in it.
D.SCORE = {
    city = 5, citizen = 2, tech = 2, explored = 0.05,
    kept = 20, land = 0.25, ward = 3,
}

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

-- A city's quarters (src/quarters.lua): the hexes it spills over into.
-- Its middle houses `home` citizens and each quarter `each` more; at its
-- housing it grows at `slow` the pace, and `over` past it not at all.
-- A quarter is built as anything is, on a hex of the city's own land beside
-- one of its hexes and within `reach` of its middle, for `cost[n]` the nth;
-- `most` at most. One an enemy stands in is sacked and houses no one till
-- `mend` turns after it is left.
D.QUARTER = {
    home = 6, each = 5, most = 3,
    slow = 0.25, over = 2,
    cost = { 60, 90, 120 },
    reach = 2,
    mend = 3,
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
-- How a civilization leans when the computer plays it (src/ai.lua): the
-- technologies it is the likelier to pick, each so many times as likely as
-- one not named, and the gold it keeps back once the cataclysm is foretold,
-- buying its wards with the rest. Nocta is for war and keeps a war chest;
-- Tess is a builder and spends it on walls against the end.
D.CIVS = {
    { name = "AURELIA", leader = "YOU", look = "light", reserve = 80,
        cities = { "AURUM", "SOLACE", "BRIGHTWATER", "ASHFORD", "LUMEN", "HALCYON", "MERIDIAN", "DAWNHOLD" } },
    { name = "UMBRA", leader = "QUEEN NOCTA", look = "dark", reserve = 160,
        leaning = { archery = 4, bronze = 4, horses = 4, iron = 4 },
        cities = { "NOCTIS", "DUSKMERE", "GLOAMING", "CINDERFALL", "SHADEHALL", "EVENFORD", "MIRKWALL" } },
    { name = "VARRO", leader = "KING TESS", look = "stripe", reserve = 40,
        leaning = { pottery = 4, mining = 3, masonry = 4, writing = 4, currency = 3, sailing = 3 },
        cities = { "TESSERA", "BANDHOLM", "STRIATA", "LATTICE", "GRATEFORD", "CHEVRON", "ZIGRATH" } },
}

-- The calendar: a year for each turn, faster early.
function D.year(turn)
    local y = -4000 + (turn - 1) * 40
    if turn > 50 then y = -4000 + 49 * 40 + (turn - 50) * 25 end
    if turn > 100 then y = -4000 + 49 * 40 + 50 * 25 + (turn - 100) * 20 end
    local L = require "src.lang"
    if y < 0 then return L("{1} BC", -y) end
    return L("{1} AD", y == 0 and 1 or y)

end

return D
