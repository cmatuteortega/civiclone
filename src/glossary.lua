-- The glossary: a page for each thing the game names -- the yields, the
-- land, what is built on it, the units and their gear, the buildings, the
-- technologies, the beasts, and the ideas the rules turn on (moving,
-- fighting, borders, the fog). The help window (src/ui/help.lua) shows it,
-- and a tooltip can open it at what is under the pointer (Glossary.forCell).
--
-- Most pages are made from src/defs.lua, so a number tuned there is the
-- number shown here; the ideas are written out. A page's lines are in the
-- language of the moment, put together when they are asked for.
--
-- No LÖVE here: the tests read it.

local D = require "src.defs"
local L = require "src.lang"

local Glossary = {}

-- The kinds of page, in the order the list shows them.
Glossary.KINDS = {
    { id = "idea", name = "HOW IT WORKS" },
    { id = "yield", name = "YIELDS" },
    { id = "land", name = "THE LAND" },
    { id = "improvement", name = "IMPROVEMENTS" },
    { id = "unit", name = "UNITS" },
    { id = "building", name = "BUILDINGS" },
    { id = "tech", name = "TECHNOLOGIES" },
    { id = "beast", name = "THE WILD" },
}

local pages, byId = {}, {}

-- Adds a page: `id` to find it by, the `kind` it is listed under, its `name`
-- (English, looked up as it is shown), and `body`, a function answering its
-- lines (in English or in the language already; each is looked up).
local function page(id, kind, name, body)
    local p = { id = id, kind = kind, name = name, body = body }
    pages[#pages + 1] = p
    byId[id] = p
    return p
end

local function sorted(t, key)
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local x, y = t[a][key or "order"], t[b][key or "order"]
        if x and y and x ~= y then return x < y end
        return a < b
    end)
    return ids
end

-- "+2 FOOD, +1 PRODUCTION" from a table of yields; nothing if all are 0.
local function yields(t)
    local out = {}
    for _, k in ipairs({ { "food", "FOOD" }, { "prod", "PRODUCTION" }, { "gold", "GOLD" } }) do
        local n = t[k[1]] or 0
        if n ~= 0 then out[#out + 1] = L("{1} {2}", (n > 0 and "+" or "") .. n, k[2]) end
    end
    return table.concat(out, ", ")
end

local function techName(id) return id and D.TECH[id] and L(D.TECH[id].name) end

--- how it works -----------------------------------------------------------------

page("idea.turns", "idea", "TURNS", function() return {
    "MOVE YOUR UNITS AND SET YOUR CITIES TO WORK, THEN END THE TURN. THE RIVALS, THE WILD AND THE CATACLYSM TAKE THEIRS, AND A NEW TURN BEGINS.",
    "THE BIG BUTTON AT THE BOTTOM RIGHT GOES TO WHATEVER NEEDS ORDERS NEXT, AND ENDS THE TURN WHEN NOTHING DOES.",
} end)

page("idea.cities", "idea", "CITIES", function() return {
    L("A SETTLER FOUNDS A CITY ON LAND, AT LEAST {1} HEXES FROM ANY OTHER. YOUR FIRST IS YOUR CAPITAL.", 4),
    L("EACH CITIZEN WORKS ONE HEX OF THE CITY'S LAND WITHIN {1}, AND EATS {2} FOOD.", D.CITY.workRadius, 2),
    "A CITY BUILDS ONE THING AT A TIME WITH ITS PRODUCTION. CLICK IT TO CHOOSE WHAT, OR TO BUY IT WITH GOLD.",
} end)

page("idea.growth", "idea", "GROWTH", function() return {
    "FOOD LEFT OVER AFTER THE CITIZENS EAT FILLS THE CITY'S STORE. A FULL STORE ADDS A CITIZEN; AN EMPTY ONE LOSES ONE.",
    L("A CITY'S MIDDLE HOUSES {1} CITIZENS. PAST THAT IT NEEDS QUARTERS, EACH HOUSING {2} MORE.", D.QUARTER.home, D.QUARTER.each),
} end)

page("idea.borders", "idea", "BORDERS", function() return {
    "A NEW CITY OWNS THE HEXES AROUND IT. ITS CULTURE CLAIMS ONE HEX MORE AT A TIME, EACH COSTING MORE THAN THE LAST.",
    "ONLY YOUR OWN LAND CAN BE WORKED, FARMED OR MINED.",
    "ANOTHER CIVILIZATION'S LAND IS CLOSED TO YOUR UNITS WHILE YOU ARE AT PEACE, UNLESS YOUR BORDERS ARE OPEN.",
} end)

page("idea.movement", "idea", "MOVEMENT", function() return {
    "ENTERING A HEX COSTS 1 MOVE, 1 MORE FOR HILLS AND 1 MORE FOR FOREST. MOUNTAINS CANNOT BE ENTERED.",
    "A UNIT WITH ALL ITS MOVES CAN ALWAYS TAKE ONE STEP. A HEX TOO FAR FOR THIS TURN BECOMES AN ORDER IT KEEPS UNTIL IT ARRIVES.",
    "ONE SOLDIER AND ONE CIVILIAN MAY SHARE A HEX.",
} end)

page("idea.combat", "idea", "COMBAT", function() return {
    "RIGHT CLICK AN ENEMY BESIDE A SOLDIER TO ATTACK. THE TOOLTIP FORECASTS THE DAMAGE BOTH WAYS FIRST.",
    "THE STRONGER SIDE DEALS MORE. HILLS, FOREST AND FORTIFYING HELP THE DEFENDER; WOUNDS WEAKEN BOTH. RANGED UNITS SHOOT 2 HEXES AND TAKE NOTHING BACK.",
    "A MELEE UNIT THAT BEATS A CITY DOWN TO 0 TAKES IT.",
} end)

page("idea.strength", "idea", "STRENGTH", function() return {
    "HOW HARD A UNIT HITS AND HOW WELL IT STANDS. A BAND'S COMES FROM ITS WEAPON, A HORSE AND ITS RANK.",
    "EVERY 10 HP IT HAS LOST TAKES 1 OFF IT.",
} end)

page("idea.hp", "idea", "HP", function() return {
    L("HIT POINTS: EVERY UNIT HAS 100, A CITY {1}. AT 0 A UNIT DIES.", D.CITY.hp),
    L("A UNIT THAT RESTS A TURN HEALS {1} IN THE FIELD, {2} IN YOUR LAND AND {3} IN A CITY.",
        D.COMBAT.healField, D.COMBAT.healHome, D.COMBAT.healCity),
} end)

page("idea.fortify", "idea", "FORTIFY", function() return {
    L("A FORTIFIED SOLDIER STANDS {1} STRONGER UNTIL IT MOVES, ATTACKS OR IS ATTACKED, AND IS NOT ASKED FOR ORDERS.", D.COMBAT.fortify),
} end)

page("idea.upkeep", "idea", "UPKEEP", function() return {
    "YOU HAVE 2 UNITS FREE, AND 1 MORE FOR EACH CITY. EACH UNIT PAST THAT COSTS 1 GOLD A TURN.",
} end)

page("idea.rivers", "idea", "RIVERS", function() return {
    L("EVERY HEX ON A RIVER YIELDS {1} GOLD MORE, AND A FARM ON ONE {2} FOOD MORE.", D.RIVER.gold, D.RIVER.farmFood),
    L("CROSSING A RIVER TAKES ALL A UNIT'S MOVES, UNLESS A CITY'S BRIDGE CARRIES IT. ATTACKING ACROSS ONE: -{1} STRENGTH.", D.RIVER.attack),
} end)

page("idea.fog", "idea", "FOG OF WAR", function() return {
    "YOU SEE AROUND YOUR UNITS AND CITIES, AND ALL YOUR OWN LAND. LAND SEEN BEFORE IS DRAWN A SHADE DARKER, ITS UNITS HIDDEN; LAND NEVER SEEN IS AN OLD PAPER MAP.",
} end)

page("idea.cataclysm", "idea", "THE CATACLYSM", function() return {
    "THE WORLD IS ENDING, IN THE WAY CHOSEN FOR THE GAME. ONCE IT IS FORETOLD THE TOP BAR SAYS ITS STAGE AND THE TURNS LEFT.",
    "EACH CATACLYSM HAS ITS WARDS: BUILDINGS THAT SPARE A CITY THE WORST OF IT. CITIES STILL STANDING WITH ONE AT THE END ARE WORTH MORE.",
} end)

page("idea.winning", "idea", "WINNING", function() return {
    "DESTROY EVERY RIVAL, OR HOLD EVERY CAPITAL. OR LAST TO THE END WITH THE HIGHEST SCORE: CITIES, PEOPLE KEPT, GOOD LAND, WARDS, TECHNOLOGIES AND THE MAP EXPLORED.",
    "YOU LOSE IF YOUR LAST CITY FALLS, OR A RIVAL SCORES MORE AT THE END.",
} end)

page("idea.diplomacy", "idea", "DIPLOMACY", function() return {
    "YOU MEET ANOTHER CIVILIZATION WHEN YOU FIRST SEE A UNIT, A CITY OR THE LAND OF THEIRS. FROM THEN ON YOU ARE AT PEACE OR AT WAR.",
    "AT PEACE NEITHER MAY ATTACK THE OTHER, NOR WALK THE OTHER'S LAND. OPEN BORDERS LET BOTH PASS. ALLIES ALSO SHARE WHAT THEY SEE, AND ARE CALLED TO EACH OTHER'S WARS.",
    L("A PEACE HOLDS {1} TURNS BEFORE WAR MAY BE MADE AGAIN. BREAKING OPEN BORDERS OR AN ALLIANCE IS BETRAYAL, AND EVERYONE REMEMBERS IT.", D.DIPLO.truce),
    "EACH LEADER'S REGARD FOR YOU IS WHAT THEY REMEMBER OF YOU, FADING WITH TIME, AND HOW THINGS STAND NOW: WAR, CROWDED BORDERS, AN ENEMY SHARED, THE END COMING FOR ALL. DIPLOMACY, IN THE TOP BAR, SHOWS IT ALL.",
    L("FROM TURN {1}, WHOEVER RUNS AWAY WITH THE GAME IS FEARED. THOSE WHO FEAR THE SAME LEADER ALLY READILY AGAINST IT, MARCH TOGETHER, AND MAKE NO PEACE WITH IT WHILE IT FIGHTS THE OTHER.", D.DIPLO.runaway.from),
    "THE CATACLYSM BRINGS ITS OWN DEALS: A TRUCE TO RAZE THE ABYSS'S CITADEL, GRAIN SOLD FOR GOLD IN THE FAMINE, BORDERS SHUT AGAINST THE PLAGUE, AND REFUGEES FROM THE DROWNED AND THE STARVING.",
} end)

page("idea.letters", "idea", "LETTERS", function() return {
    "WHAT ANOTHER LEADER ASKS OF YOU COMES AS A LETTER: AN ENVELOPE IN THE STACK AT THE LEFT, SEALED IN THEIR COLOURS. CLICK IT TO READ IT AND ANSWER.",
    L("A LETTER LEFT UNANSWERED {1} TURNS TAKES ITS DEFAULT ANSWER, USUALLY NO. YOUR ANSWERS ARE REMEMBERED.", D.DIPLO.answer),
    "ENVOYS, OFFERS OF PEACE, OPEN BORDERS AND ALLIANCE, DEMANDS FOR TRIBUTE, GIFTS, PLEAS FOR AID, CALLS TO ARMS, REFUGEES FROM THE CATACLYSM, AND CITIES WISHING TO JOIN YOU.",
    "AND FROM YOUR OWN PEOPLE: THE ELDERS OF A CITY GONE ROGUE.",
} end)

page("idea.loyalty", "idea", "LOYALTY", function() return {
    L("A CITY'S LOYALTY RUNS FROM 0 TO 100. ITS OWN PEOPLE AND YOUR CITIES WITHIN {1} HEXES PULL IT UP; A FOREIGNER'S CITIES THERE PULL IT DOWN, THE NEARER AND BIGGER THE HARDER.", D.LOYALTY.radius),
    "THE CAPITAL, A GARRISON AND A WARD AGAINST THE END STEADY IT. HUNGER, THE PLAGUE, AN ENEMY AT THE GATES, A NEW CONQUEST AND DREAD OF THE END WEAR IT DOWN.",
    L("UNDER {1} A CITY IS IN UNREST AND MAKES A QUARTER LESS OF ALL BUT FOOD; UNDER {2}, IN UPRISING, HALF. AT 0 IT GOES OVER TO THE CIVILIZATION PULLING HARDEST ON IT.", D.LOYALTY.unrest, D.LOYALTY.uprising),
    L("WITH NO ONE TO GO OVER TO, IT GOES ROGUE: IT KEEPS ALL BUT ITS FOOD AND BUILDS NOTHING. ITS ELDERS WRITE: PAY THEM, SEND IN SOLDIERS AT A CITIZEN'S COST, OR WAIT UNTIL ITS LOYALTY CLIMBS BACK TO {1}.", D.LOYALTY.uprising),
} end)

--- the yields ---------------------------------------------------------------------

page("yield.food", "yield", "FOOD", function() return {
    "GROWS CITIES. EACH CITIZEN EATS 2 A TURN; WHAT IS LEFT FILLS THE STORE TOWARDS THE NEXT CITIZEN.",
    "GRASSLAND, FARMS, FISH AND WHEAT GIVE MOST.",
} end)
page("yield.prod", "yield", "PRODUCTION", function() return {
    "BUILDS WHAT A CITY IS MAKING: UNITS, BUILDINGS AND QUARTERS.",
    "HILLS, FORESTS AND MINES GIVE MOST.",
} end)
page("yield.gold", "yield", "GOLD", function() return {
    "BUYS WHAT A CITY IS BUILDING, AND PAYS THE UPKEEP OF UNITS PAST THE FREE ONES.",
    "RIVERS, THE COAST, GEMS AND MARKETS GIVE IT.",
} end)
page("yield.science", "yield", "SCIENCE", function() return {
    "RESEARCHES TECHNOLOGIES, ONE AT A TIME. EACH CITIZEN GIVES SOME, AND LIBRARIES MORE.",
} end)
page("yield.culture", "yield", "CULTURE", function() return {
    "EACH CITY'S OWN CULTURE CLAIMS IT NEW HEXES. MONUMENTS GIVE IT.",
} end)

--- the land ---------------------------------------------------------------------

local LAND_SAYS = {
    ocean = "DEEP WATER: ONLY SHIPS SAIL IT, AND ONLY AFTER CARTOGRAPHY.",
    coast = "SHALLOW WATER BY THE LAND. SHIPS SAIL IT; AFTER SAILING, LAND UNITS EMBARK ONTO IT.",
    grass = "THE BEST LAND FOR FOOD.",
    plains = "FOOD AND PRODUCTION BOTH.",
    desert = "BARREN, BUT GOOD ON A RIVER.",
    marsh = "SODDEN LOWLAND THE LONG RAINS LEAVE. NO FARM WILL STAND ON IT.",
    tundra = "FROZEN GROUND, WHERE LITTLE GROWS.",
    snow = "DEEP DRIFTS THAT BURY FARMS AND SLOW WHOEVER WADES THEM.",
    ice = "THE SEA FROZEN HARD ENOUGH TO WALK ON. NO SHIP SAILS IT.",
    saltflat = "THE SEA'S FLOOR LEFT BARE. NO CITY STANDS ON IT.",
}

for _, id in ipairs(sorted(D.TERRAIN, "name")) do
    local t = D.TERRAIN[id]
    page("terrain." .. id, "land", t.name, function()
        local out = {}
        if LAND_SAYS[id] then out[#out + 1] = LAND_SAYS[id] end
        local y = yields(t)
        out[#out + 1] = L("YIELDS {1}", y ~= "" and y or L"NOTHING")
        if t.move then out[#out + 1] = L("COSTS {1} MORE TO ENTER", t.move) end
        return out
    end)
end

page("elev.hills", "land", "HILLS", function() return {
    L("YIELDS {1}", yields(D.ELEV.hills)),
    L("COSTS {1} MORE TO ENTER", D.ELEV.hills.move - 1),
    L("DEFENDERS ON HILLS: +{1} STRENGTH. A UNIT ON HILLS SEES 1 FURTHER.", D.ELEV.hills.defense),
} end)
page("elev.mountain", "land", "MOUNTAINS", function() return {
    "NO UNIT CAN ENTER THEM, AND NO CITY WORKS THEM. THEY BLOCK THE VIEW.",
} end)
page("feature.forest", "land", "FOREST", function() return {
    L("YIELDS {1}", yields(D.FEATURE.forest)),
    "COSTS 1 MORE TO ENTER",
    L("DEFENDERS IN FOREST: +{1} STRENGTH.", D.FEATURE.forest.defense),
    L("A BUILDER CAN CHOP IT IN YOUR LAND: {1} PRODUCTION FOR THE CITY.", D.WORKS.chop.prod),
} end)

local RESOURCE_SAYS = {
    iron = "THE IRON OF A FALLEN STAR, LEFT IN ITS CRATER.",
    obsidian = "BLACK GLASS WHERE THE LAVA COOLED.",
}
for _, id in ipairs(sorted(D.RESOURCE, "name")) do
    local r = D.RESOURCE[id]
    page("resource." .. id, "land", r.name, function()
        local out = {}
        if RESOURCE_SAYS[id] then out[#out + 1] = RESOURCE_SAYS[id] end
        out[#out + 1] = L("A RESOURCE: {1} MORE WHERE IT LIES", yields(r))
        return out
    end)
end

--- improvements ---------------------------------------------------------------------

local IMPROVEMENT_SAYS = {
    farm = "ON GRASS, PLAINS OR DESERT IN YOUR LAND. ON A RIVER, 1 FOOD MORE.",
    mine = "ON HILLS IN YOUR LAND.",
    boats = "ON FISH IN YOUR WATERS.",
}
for _, id in ipairs(sorted(D.IMPROVEMENT, "name")) do
    local m = D.IMPROVEMENT[id]
    page("improvement." .. id, "improvement", m.name, function()
        local out = { L("A BUILDER MAKES IT: {1}", yields(m)) }
        if IMPROVEMENT_SAYS[id] then out[#out + 1] = IMPROVEMENT_SAYS[id] end
        if m.tech then out[#out + 1] = L("NEEDS {1}", techName(m.tech)) end
        return out
    end)
end

--- units ------------------------------------------------------------------------------

page("unit.settler", "unit", "SETTLER", function() return {
    "FOUNDS A CITY WHERE IT STANDS.",
    L("COSTS {1} PRODUCTION AND A CITIZEN; ONLY A CITY OF 2 OR MORE TRAINS ONE.", D.UNITS.settler.cost),
} end)
page("unit.builder", "unit", "BUILDER", function() return {
    "MAKES FARMS, MINES AND FISHING BOATS, CHOPS FORESTS AND MENDS THE LAND.",
    L("COSTS {1} PRODUCTION. {2} BUILDS, THEN IT IS GONE.", D.UNITS.builder.cost, D.UNITS.builder.charges),
} end)

local FORM_ORDER = { "scout", "warrior", "slinger", "archer", "spearman", "swordsman", "rider", "horseman",
    "mountedslinger", "horsearcher", "lancer", "knight", "galley", "quadrireme" }
for _, id in ipairs(FORM_ORDER) do
    if D.FORMS[id] and D.FORM_NAMES[id] then
        page("unit." .. id, "unit", D.FORM_NAMES[id], function()
            -- Its numbers as the rules put them together.
            local f = D.FORMS[id]
            local def = D.unitDef(f.unit, f.gear)
            local weapon, mount = D.GEAR[f.gear.weapon], D.GEAR[f.gear.mount]
            local out = {}
            if def.sea then out[#out + 1] = "A SHIP. A CITY ON THE WATER BUILDS IT, AFTER SAILING."
            elseif not weapon then out[#out + 1] = "A BAND WITH NO WEAPON: LIGHT AND FAR-SEEING, FOR EXPLORING."
            else out[#out + 1] = L("A BAND CARRYING A {1}", weapon.name) end
            if mount then out[#out + 1] = "ON A HORSE" end
            out[#out + 1] = L("STRENGTH {1}, MOVES {2}", def.str, def.moves)
            if def.ranged then out[#out + 1] = L("SHOOTS {1} HEXES AT STRENGTH {2}", def.range, def.ranged) end
            out[#out + 1] = L("COSTS {1} PRODUCTION", def.cost)
            local needs = {}
            for _, g in ipairs({ weapon, mount }) do if g and g.tech then needs[#needs + 1] = techName(g.tech) end end
            if #needs > 0 then out[#out + 1] = L("NEEDS {1}", table.concat(needs, ", ")) end
            return out
        end)
    end
end

--- buildings -------------------------------------------------------------------------

for _, id in ipairs(sorted(D.BUILDINGS)) do
    local b = D.BUILDINGS[id]
    page("building." .. id, "building", b.name, function()
        local out = {}
        for _, s in ipairs(b.says or {}) do out[#out + 1] = s end
        if b.ward then out[#out + 1] = "A WARD AGAINST THE CATACLYSM: BUILT ONLY WHEN IT COMES." end
        if b.coastal then out[#out + 1] = "ONLY IN A CITY ON THE WATER" end
        out[#out + 1] = L("COSTS {1} PRODUCTION", b.cost)
        if b.tech then out[#out + 1] = L("NEEDS {1}", techName(b.tech)) end
        return out
    end)
end

--- technologies ---------------------------------------------------------------------

for _, t in ipairs(D.TECHS) do
    page("tech." .. t.id, "tech", t.name, function()
        local out = { L("COSTS {1} SCIENCE", t.cost) }
        if #t.needs > 0 then
            local n = {}
            for _, id in ipairs(t.needs) do n[#n + 1] = techName(id) end
            out[#out + 1] = L("NEEDS {1}", table.concat(n, ", "))
        end
        local u = {}
        for _, x in ipairs(D.unlocks(t.id)) do u[#u + 1] = L(x.name) end
        if #u > 0 then out[#out + 1] = L("OPENS {1}", table.concat(u, ", ")) end
        return out
    end)
end

--- the wild --------------------------------------------------------------------------

local TEMPER = {
    hostile = "HOSTILE: IT HUNTS ANYONE NEAR ITS LAIR.",
    neutral = "IT FIGHTS ONLY IF HUNTED.",
    shy = "SHY: IT FLEES.",
    demon = "A DEMON OF THE ABYSS: IT GOES FOR THE TOWNS.",
    vermin = "IT BRINGS THE PLAGUE INTO THE TOWNS IT REACHES, AND FIGHTS NO ONE.",
}
for _, id in ipairs(sorted(D.BEASTS, "name")) do
    local b = D.BEASTS[id]
    page("beast." .. id, "beast", b.name, function()
        local out = { TEMPER[b.temper] or "" }
        out[#out + 1] = L("STRENGTH {1}, MOVES {2}", b.str, b.moves)
        if b.night then out[#out + 1] = L("HUNTING BY NIGHT: +{1} STRENGTH", b.night) end
        if b.across then out[#out + 1] = "STRIKES WHAT CROSSES ITS RIVER" end
        if b.tame then out[#out + 1] = L("{1} TAMES THEM", techName(b.tame)) end
        if b.loot and b.loot.gold then out[#out + 1] = L("KILLING IT GIVES {1} GOLD", b.loot.gold) end
        return out
    end)
end

--- looking pages up -----------------------------------------------------------------

Glossary.pages = pages

function Glossary.get(id) return byId[id] end

-- A page's name, in the language now.
function Glossary.name(id)
    local p = byId[id]
    return p and L(p.name) or ""
end

-- A page's lines, in the language now.
function Glossary.lines(id)
    local p = byId[id]
    if not p then return {} end
    local out = {}
    for _, s in ipairs(p.body()) do out[#out + 1] = L(s) end
    return out
end

-- The pages of a kind, in order: the ideas, yields, units and technologies
-- as written (simplest first), the rest by their names in the language now.
local AS_WRITTEN = { idea = true, yield = true, unit = true, tech = true }
function Glossary.ofKind(kind)
    local out = {}
    for _, p in ipairs(pages) do if p.kind == kind then out[#out + 1] = p end end
    if not AS_WRITTEN[kind] then
        local names = {}
        for _, p in ipairs(out) do names[p] = L(p.name) end
        table.sort(out, function(x, y) return names[x] < names[y] end)
    end
    return out
end

-- The page for a unit of kind `kind` (its form, or "settler", or a beast's).
function Glossary.forUnit(kind)
    if byId["unit." .. kind] then return "unit." .. kind end
    if byId["beast." .. kind] then return "beast." .. kind end
end

-- The page most worth opening for hex `cell` as `g` shows it to player
-- `me`: what stands on it if it can be seen, else what is built or lies
-- there, else the land.
function Glossary.forCell(g, cell, me)
    if not cell then return nil end
    if me and me.visible[cell.id] then
        for _, u in ipairs({ g.mil[cell.id], g.civ[cell.id] }) do
            local id = u and Glossary.forUnit(u.kind)
            if id then return id end
        end
    end
    if cell.improvement and byId["improvement." .. cell.improvement] then return "improvement." .. cell.improvement end
    if cell.resource and byId["resource." .. cell.resource] then return "resource." .. cell.resource end
    if cell.elev == "mountain" then return "elev.mountain" end
    if cell.feature and byId["feature." .. cell.feature] then return "feature." .. cell.feature end
    if cell.elev == "hills" then return "elev.hills" end
    if byId["terrain." .. cell.terrain] then return "terrain." .. cell.terrain end
end

return Glossary
