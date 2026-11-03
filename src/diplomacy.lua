-- Diplomacy: who has met whom, peace and war between them, open borders and
-- alliances, what each leader thinks of the others, and the letters they
-- send one another.
--
-- Civilizations meet when one first sees a unit or a city of the other's
-- (Game:look). From then on they are at peace or at war. At peace neither
-- may attack the other, nor set foot on the other's land, unless their
-- borders are open; allies open them, and each sees what the other sees. A
-- peace holds for D.DIPLO.truce turns before war may be made again, and
-- whoever breaks a treaty is remembered for it by everyone.
--
-- What a leader thinks of another, its regard, is what it remembers of
-- them -- a gift, a refusal, a betrayal, each fading a little a turn -- and
-- how things stand between them now: at war, allies, borders pressing on
-- each other, the end of the world coming for both. The computer's leaders
-- decide by it, and by who is the stronger.
--
-- Everything one civilization asks of another goes as a letter
-- (Diplo.KINDS): an envoy's greeting, an offer of peace, a demand for
-- tribute, a plea for aid, a call to arms, refugees at the gate, a city
-- wishing to change sides. A letter to the computer is answered at once;
-- one to the player waits in their envelopes (src/ui/letters.lua) until it
-- is answered or D.DIPLO.answer turns pass, when its default answer is
-- taken.
--
-- No LÖVE here: the tests play it.

local D = require "src.defs"
local L = require "src.lang"
local Cat = require "src.cataclysm"

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local Diplo = {}

local WILD = 0

--- the state -----------------------------------------------------------------------

-- The pair's index in game.diplo.rel: a number, the same either way round.
local function key(a, b)
    if a > b then a, b = b, a end
    return a * 64 + b
end

-- game.diplo, made if a game has none: a new one's, or one kept from before
-- there was diplomacy, whose civilizations had all met and were all at war,
-- as they were then.
function Diplo.ensure(game)
    local d = game.diplo
    if d then return d end
    d = { rel = {}, mail = {}, nextMail = 1 }
    game.diplo = d
    if (game.turn or 1) > 1 then
        for a = 1, #game.players do
            for b = a + 1, #game.players do
                local r = Diplo.rel(game, a, b)
                r.met, r.war, r.since = game.turn, true, game.turn
            end
        end
    end
    return d
end

-- What stands between a and b (two civilizations): { met, war, since,
-- truce, borders, alliance, mem = { [who] = { memories } }, asked, said }.
function Diplo.rel(game, a, b)
    local d = game.diplo or Diplo.ensure(game)
    local k = key(a, b)
    local r = d.rel[k]
    if not r then
        r = { mem = { [a] = {}, [b] = {} }, asked = { [a] = {}, [b] = {} }, said = {} }
        d.rel[k] = r
    end
    return r
end

local function find(game, a, b)
    local d = game.diplo or Diplo.ensure(game)
    return d.rel[key(a, b)]
end

local function civ(game, id) return id and id ~= WILD and game.players[id] and not game.players[id].wild end

function Diplo.met(game, a, b)
    if a == b then return true end
    local r = find(game, a, b)
    return r ~= nil and r.met ~= nil
end

-- At war: the wild with everyone, and two civilizations that have said so.
function Diplo.atWar(game, a, b)
    if a == b then return false end
    if a == WILD or b == WILD or a == nil or b == nil then return true end
    local r = find(game, a, b)
    return r ~= nil and r.war == true
end

function Diplo.allied(game, a, b)
    if a == b then return false end
    local r = find(game, a, b)
    return r ~= nil and r.alliance == true
end

function Diplo.open(game, a, b)
    local r = find(game, a, b)
    return r ~= nil and (r.borders == true or r.alliance == true)
end

-- May a unit of `a`'s stand on land of `owner`'s? Its own, no one's, the
-- wild's; an enemy's; a friend's with open borders; and a civilization's it
-- has not met, whose borders it does not know are there.
function Diplo.mayEnter(game, a, owner)
    if owner == nil or owner == a or a == WILD or owner == WILD then return true end
    local r = find(game, a, owner)
    if not r or not r.met then return true end
    if r.war then return true end
    -- Shut against the plague (Diplo.quarantine), treaties or none.
    if r.shut and r.shut[owner] and game.turn < r.shut[owner] then return false end
    return r.borders or r.alliance or false
end

-- Is owner's land shut to a against the plague?
function Diplo.shutTo(game, a, owner)
    local r = find(game, a, owner)
    return r ~= nil and r.shut ~= nil and r.shut[owner] ~= nil and game.turn < r.shut[owner]
end

-- At war with anyone at all?
function Diplo.atWarWithAny(game, a)
    for b, p in ipairs(game.players) do
        if b ~= a and p.alive and Diplo.atWar(game, a, b) then return true end
    end
    return false
end

-- At war with anyone but b?
function Diplo.atWarWithAnyBut(game, a, b)
    for c, p in ipairs(game.players) do
        if c ~= a and c ~= b and p.alive and Diplo.atWar(game, a, c) then return true end
    end
    return false
end

-- The civilizations a has met, alive.
function Diplo.known(game, a)
    local out = {}
    for b, p in ipairs(game.players) do
        if b ~= a and p.alive and Diplo.met(game, a, b) then out[#out + 1] = b end
    end
    return out
end

-- How things stand between a and b, as a word: AT WAR, ALLIES, OPEN
-- BORDERS, AT PEACE, or NOT MET.
function Diplo.stance(game, a, b)
    local r = find(game, a, b)
    if not r or not r.met then return "NOT MET" end
    if r.war then return "AT WAR" end
    if r.alliance then return "ALLIES" end
    if r.borders then return "OPEN BORDERS" end
    return "AT PEACE"
end

--- strength ------------------------------------------------------------------------

-- A civilization's might: the strength of its soldiers and ships, and a
-- little for each city it has to hold.
function Diplo.army(game, id)
    local s = 0
    for _, u in ipairs(game.units) do
        if u.owner == id and not u.def.civilian then s = s + max(1, u.def.str or 0) end
    end
    return s + 4 * #game:citiesOf(id)
end

-- How much stronger a is than b.
function Diplo.ratio(game, a, b)
    return (Diplo.army(game, a) + 5) / (Diplo.army(game, b) + 5)
end

--- regard ----------------------------------------------------------------------------

-- `who` remembers `what` of `of`: `v` more of that kind of memory (the
-- most of one kind, D.DIPLO.most either way).
function Diplo.remember(game, who, of, what, v)
    if not civ(game, who) or not civ(game, of) or who == of then return end
    local mem = Diplo.rel(game, who, of).mem
    mem[who] = mem[who] or {}
    local list = mem[who]
    for _, m in ipairs(list) do
        if m.what == what then
            m.v = max(-D.DIPLO.most, min(D.DIPLO.most, m.v + v))
            return
        end
    end
    list[#list + 1] = { what = what, v = max(-D.DIPLO.most, min(D.DIPLO.most, v)) }
end

-- The words for each kind of memory, as `who` would put it.
Diplo.MEMORIES = {
    welcomed = "WELCOMED OUR ENVOY", sentAway = "SENT OUR ENVOY AWAY", gift = "SENT US GIFTS",
    paid = "PAID OUR TRIBUTE", refused = "REFUSED OUR DEMAND", demanded = "MADE DEMANDS OF US",
    aided = "CAME TO OUR AID", deniedAid = "LEFT US IN NEED", sheltered = "SHELTERED OUR PEOPLE",
    turnedAway = "TURNED OUR PEOPLE AWAY", joined = "MARCHED WITH US", stayedOut = "BROKE THEIR OATH",
    withdrew = "WITHDREW THEIR SOLDIERS", ignored = "IGNORED OUR WARNING", betrayed = "BETRAYED US",
    warmonger = "BREAKS TREATIES", attacked = "DECLARED WAR ON US", tookCity = "TOOK OUR CITIES",
    stirred = "STIRRED OUR PEOPLE TO REVOLT", rebuffed = "REBUFFED OUR OFFER", peace = "MADE PEACE WITH US",
    fed = "SOLD US GRAIN IN THE FAMINE", hoarded = "KEPT THEIR GRAIN FROM US", quarantined = "SHUT THE SICKNESS OUT WITH US",
}

--- the runaway --------------------------------------------------------------------------

-- Each civilization's score, once a turn.
local function scoreOf(game, id)
    local d = game.diplo
    if not d.scores or d.scores.turn ~= game.turn then d.scores = { turn = game.turn } end
    local v = d.scores[id]
    if not v then
        v = game:score(game.players[id])
        d.scores[id] = v
    end
    return v
end
Diplo.scoreOf = scoreOf

-- Does `a` fear `b` as a runaway: the best score in the world, well ahead
-- of a's (D.DIPLO.runaway)?
function Diplo.runaway(game, a, b)
    local R = D.DIPLO.runaway
    if a == b or game.turn < R.from or not civ(game, a) or not civ(game, b) then return false end
    if not game.players[b].alive or not game.players[a].alive then return false end
    local sb, sa = scoreOf(game, b), scoreOf(game, a)
    for c, p in ipairs(game.players) do
        if c ~= b and p.alive and scoreOf(game, c) >= sb then return false end
    end
    return sb >= sa * R.ratio and sb >= sa + R.lead
end

-- The runaway that both a and b fear, if there is one.
function Diplo.sharedRival(game, a, b)
    for c, p in ipairs(game.players) do
        if c ~= a and c ~= b and p.alive and Diplo.runaway(game, a, c) and Diplo.runaway(game, b, c) then return c end
    end
end

-- Hexes of a's land beside b's: how hard their borders press.
local function pressing(game, a, b)
    local d = game.diplo
    d.press = d.press or {}
    local k = key(a, b) * 1000 + (game.turn % 1000)
    local n = d.press[k]
    if n then return n end
    n = 0
    for _, cell in ipairs(game.cells) do
        if cell.owner == a then
            for _, nb in ipairs(game:neighbours(cell)) do
                if nb.owner == b then n = n + 1 break end
            end
        end
    end
    d.press[k] = n
    return n
end

-- Cities of b's near cities of a's: how hard they crowd each other.
local function crowding(game, a, b)
    local n, R = 0, D.DIPLO.NOW.crowdReach
    for _, c in ipairs(game.cities) do
        if c.owner == b then
            local here = game.cells[c.cell]
            for _, o in ipairs(game.cities) do
                if o.owner == a and game:dist(here, game.cells[o.cell]) <= R then n = n + 1 break end
            end
        end
    end
    return n
end

-- What `a` thinks of `b`: the regard, and what makes it, { { words, v } }.
function Diplo.regard(game, a, b)
    local parts = {}
    local function add(words, v)
        v = floor(v + 0.5)
        if v ~= 0 then parts[#parts + 1] = { words, v } end
    end
    local r = Diplo.rel(game, a, b)
    local N = D.DIPLO.NOW
    local nature = game.players[a].civ.regard or 0
    add("THEIR NATURE", nature)
    if r.war then add("WE ARE AT WAR", N.war)
    elseif r.alliance then add("WE ARE ALLIES", N.ally)
    elseif r.borders then add("OUR BORDERS ARE OPEN", N.borders) end
    for c, p in ipairs(game.players) do
        if c ~= a and c ~= b and p.alive and Diplo.atWar(game, a, c) and Diplo.atWar(game, b, c) then
            add("WE SHARE AN ENEMY", N.enemy)
            break
        end
    end
    if not r.war and Cat.stage(game) then add("THE END DRAWS NEAR", N.doom) end
    local press = pressing(game, a, b)
    if press > 0 then add("OUR BORDERS PRESS ON EACH OTHER", -min(N.press, press)) end
    local crowd = crowding(game, a, b)
    if crowd > 0 then add("THEY CROWD OUR LANDS", -min(N.crowdMost, crowd * N.crowd)) end
    local T = Diplo.temper(game, a)
    if T.tribute and not r.war and Diplo.ratio(game, a, b) >= 1.5 then add("THEY ARE WEAK", -N.weak) end
    -- An opportunist's eye on one already fighting someone else.
    if T.pounce and not r.war and Diplo.atWarWithAnyBut(game, b, a) then add("THEY ARE BESET", -T.pounce) end
    -- Running away with the game: feared; and those who fear the same
    -- drawn together.
    if Diplo.runaway(game, a, b) then add("THEY GROW TOO STRONG", -N.tooStrong) end
    if Diplo.sharedRival(game, a, b) then add("WE SHARE A RIVAL", N.rival) end
    for _, m in ipairs(r.mem[a] or {}) do add(Diplo.MEMORIES[m.what] or m.what, m.v) end
    local total = 0
    for _, p in ipairs(parts) do total = total + p[2] end
    return max(-100, min(100, total)), parts
end

-- The row of D.DIPLO.TEMPER leader `id` decides by.
function Diplo.temper(game, id)
    return D.DIPLO.TEMPER[game.players[id].civ.temper or "calm"] or D.DIPLO.TEMPER.calm
end

function Diplo.word(v)
    for _, w in ipairs(D.DIPLO.WORDS) do
        if v <= w[1] then return w[2] end
    end
    return D.DIPLO.WORDS[#D.DIPLO.WORDS][2]
end

--- the news --------------------------------------------------------------------------

-- Told to everyone who has met both, and to both.
local function tellKnown(game, a, b, text, ...)
    for c, p in ipairs(game.players) do
        if p.alive and (c == a or c == b or (Diplo.met(game, c, a) and Diplo.met(game, c, b))) then
            game:tell(c, text, ...)
        end
    end
end

--- moving off land closed to them --------------------------------------------------------

-- Every unit of a's standing on land of b's it may not be on is moved off
-- it, to the nearest place it may stand.
function Diplo.expel(game, a, b)
    if Diplo.mayEnter(game, a, b) then return end
    local list = {}
    for _, u in ipairs(game.units) do
        if u.owner == a and game.cells[u.cell].owner == b then list[#list + 1] = u end
    end
    for _, u in ipairs(list) do
        local here = game.cells[u.cell]
        local best, bd
        for _, n in ipairs(game:within(here, 10)) do
            if n.owner ~= b and game:canStand(u, n) then
                local dist = game:dist(here, n) + n.id * 1e-6
                if not bd or dist < bd then best, bd = n, dist end
            end
        end
        local slot = game:slot(u)
        if slot[u.cell] == u then slot[u.cell] = nil end
        if best then
            u.cell = best.id
            slot[best.id] = u
            u.trail, u.dest, u.fortified = { best.id }, nil, false
            game:emit({ kind = "expel", cell = best.id, unit = u })
        else
            game:removeUnit(u)
        end
    end
    game:look(game.players[a])
end

--- meeting -------------------------------------------------------------------------------

function Diplo.meet(game, a, b)
    if not civ(game, a) or not civ(game, b) or a == b then return end
    local r = Diplo.rel(game, a, b)
    if r.met then return end
    r.met, r.war, r.since = game.turn, false, game.turn
    game:tell(a, "WE HAVE MET {1}", game.players[b].name)
    game:tell(b, "WE HAVE MET {1}", game.players[a].name)
    game:emit({ kind = "met", a = a, b = b })
    -- Each sends an envoy; the player's own goes by itself.
    if not game.players[a].human then Diplo.send(game, a, b, "greeting") end
    if not game.players[b].human then Diplo.send(game, b, a, "greeting") end
    Diplo.expel(game, a, b)
    Diplo.expel(game, b, a)
end

--- war and peace -----------------------------------------------------------------------

-- Why a war is made, as the letter gives it.
Diplo.REASONS = {
    grudge = "WE HAVE NOT FORGOTTEN WHAT YOU DID.",
    weak = "YOU ARE WEAK, AND WE ARE NOT.",
    land = "YOUR BORDERS CHOKE OURS.",
    refused = "YOU REFUSED OUR JUST DEMAND.",
    ally = "WE STAND WITH OUR ALLY.",
    player = "SO BE IT.",
}

-- a declares war on b, for `why` (a key of Diplo.REASONS). Breaking a
-- treaty -- an alliance, open borders, a truce -- is betrayal; everyone a
-- has met remembers that a breaks its word.
function Diplo.declare(game, a, b, why)
    local r = Diplo.rel(game, a, b)
    if r.war or not civ(game, a) or not civ(game, b) then return false end
    local broke = r.alliance or r.borders or (r.truce and game.turn < r.truce)
    r.met = r.met or game.turn
    r.war, r.borders, r.alliance, r.since = true, false, false, game.turn
    local M = D.DIPLO.MEMORY
    Diplo.remember(game, b, a, "attacked", M.attacked)
    if broke then
        Diplo.remember(game, b, a, "betrayed", M.betrayed)
        for c, p in ipairs(game.players) do
            if c ~= a and c ~= b and p.alive and Diplo.met(game, c, a) then
                Diplo.remember(game, c, a, "warmonger", M.warmonger)
            end
        end
    end
    tellKnown(game, a, b, "{1} HAS DECLARED WAR ON {2}", game.players[a].name, game.players[b].name)
    game:emit({ kind = "war", a = a, b = b })
    if game.players[b].human then Diplo.send(game, a, b, "war", { why = why or "grudge" }) end
    -- b's allies are called to defend it, and a's to march with it.
    for c, p in ipairs(game.players) do
        if c ~= a and c ~= b and p.alive and Diplo.allied(game, b, c) and not Diplo.atWar(game, c, a) then
            Diplo.send(game, b, c, "arms", { against = a })
        end
    end
    for c, p in ipairs(game.players) do
        if c ~= a and c ~= b and p.alive and Diplo.allied(game, a, c) and not Diplo.atWar(game, c, b) then
            Diplo.send(game, a, c, "arms", { against = b, ours = true })
        end
    end
    return true
end

function Diplo.makePeace(game, a, b)
    local r = Diplo.rel(game, a, b)
    if not r.war then return false end
    r.war, r.since, r.truce = false, game.turn, game.turn + D.DIPLO.truce
    Diplo.remember(game, a, b, "peace", D.DIPLO.MEMORY.peace)
    Diplo.remember(game, b, a, "peace", D.DIPLO.MEMORY.peace)
    tellKnown(game, a, b, "{1} AND {2} HAVE MADE PEACE", game.players[a].name, game.players[b].name)
    game:emit({ kind = "peace", a = a, b = b })
    Diplo.expel(game, a, b)
    Diplo.expel(game, b, a)
    return true
end

function Diplo.openBorders(game, a, b)
    local r = Diplo.rel(game, a, b)
    if r.war or r.borders then return false end
    r.borders = true
    tellKnown(game, a, b, "{1} AND {2} HAVE OPENED THEIR BORDERS", game.players[a].name, game.players[b].name)
    return true
end

function Diplo.ally(game, a, b)
    local r = Diplo.rel(game, a, b)
    if r.war or r.alliance then return false end
    r.alliance, r.borders = true, true
    tellKnown(game, a, b, "{1} AND {2} ARE NOW ALLIES", game.players[a].name, game.players[b].name)
    game:emit({ kind = "ally", a = a, b = b })
    -- Sworn against the runaway: it is told.
    local c = Diplo.sharedRival(game, a, b)
    if c and game.players[c].human then Diplo.send(game, a, c, "coalition", { with = b }) end
    game:look(game.players[a])
    game:look(game.players[b])
    return true
end

-- Gold from a to b, as much as a has of it.
function Diplo.pay(game, a, b, gold)
    local pa = game.players[a]
    gold = min(gold, pa.gold)
    if gold <= 0 then return 0 end
    pa.gold = pa.gold - gold
    game.players[b].gold = game.players[b].gold + gold
    return gold
end

--- refugees --------------------------------------------------------------------------

-- n of a's people, homeless, come to the nearest city of b's.
function Diplo.shelter(game, b, from, n)
    local best, bd
    for _, c in ipairs(game:citiesOf(b)) do
        local d = from and game:dist(game.cells[c.cell], game.cells[from]) or c.pop
        if not bd or d < bd then best, bd = c, d end
    end
    if not best then return nil end
    best.pop = best.pop + n
    game:assignWork(best)
    game:emit({ kind = "grow", cell = best.cell, city = best })
    return best
end

-- City `city` of `owner`'s is lost, or its people starving, under the
-- cataclysm: `n` of them go looking for a home, to the civilization their
-- leader thinks best of and is not at war with.
function Diplo.homeless(game, owner, city, n)
    if not civ(game, owner) or n < 1 then return end
    local r0 = game.diplo or Diplo.ensure(game)
    r0.fled = r0.fled or {}
    if (r0.fled[owner] or -99) > game.turn - 8 then return end
    local best, bv
    for _, b in ipairs(Diplo.known(game, owner)) do
        if not Diplo.atWar(game, owner, b) and #game:citiesOf(b) > 0 then
            local v = Diplo.regard(game, owner, b)
            if not bv or v > bv then best, bv = b, v end
        end
    end
    if not best then return end
    r0.fled[owner] = game.turn
    Diplo.send(game, owner, best, "refugees", { city = city.name, n = n, cell = city.cell })
end

--- letters -----------------------------------------------------------------------------

-- A choice in a letter: { id, label, off }; `label` English, with what goes
-- into it as `args`.
local function choice(id, label, args, off) return { id = id, label = label, args = args, off = off } end

local function leaderOf(game, id) return game.players[id].civ.leader end

-- Every kind of letter:
--   title            what it is, on the envelope's tip and the letter's head
--   lines(g, l)      what it says, each { English, args... }
--   choices(g, l)    the answers to it
--   apply(g, l, id)  what the answer does
--   ai(g, l)         the answer the computer gives
--   default          the answer taken when no answer comes in time
Diplo.KINDS = {}
local K = Diplo.KINDS

K.greeting = {
    title = "AN ENVOY ARRIVES",
    lines = function(g, l)
        return {
            { "GREETINGS, STRANGER. I AM {1} OF {2}.", leaderOf(g, l.from), g.players[l.from].name },
            { "OUR SCOUTS HAVE SEEN YOUR PEOPLE. THE LAND IS WIDE AND THE YEARS ARE FEW: LET US KNOW EACH OTHER." },
            { "UNTIL WE AGREE OTHERWISE, NEITHER OF US SETS FOOT ON THE OTHER'S LAND." },
        }
    end,
    choices = function() return { choice("welcome", "WELCOME THE ENVOY"), choice("away", "SEND THE ENVOY AWAY") } end,
    apply = function(g, l, id)
        if id == "welcome" then Diplo.remember(g, l.from, l.to, "welcomed", D.DIPLO.MEMORY.welcomed)
        else Diplo.remember(g, l.from, l.to, "sentAway", D.DIPLO.MEMORY.sentAway) end
    end,
    ai = function(g, l) return Diplo.regard(g, l.to, l.from) >= -20 and "welcome" or "away" end,
    default = "welcome",
}

K.war = {
    title = "WAR IS DECLARED",
    lines = function(g, l)
        return {
            { "{1} DECLARES WAR UPON YOU.", g.players[l.from].name },
            { Diplo.REASONS[l.args.why] or Diplo.REASONS.grudge },
            { "OUR SOLDIERS MAY NOW CROSS YOUR BORDERS, AND YOURS OURS." },
        }
    end,
    choices = function() return { choice("ok", "TO ARMS") } end,
    apply = function() end,
    ai = function() return "ok" end,
    default = "ok",
}

K.peace = {
    title = "AN OFFER OF PEACE",
    lines = function(g, l)
        return {
            { "THIS WAR HAS COST US BOTH ENOUGH. LET US LAY DOWN OUR ARMS." },
            { "A PEACE BINDS BOTH SIDES FOR {1} TURNS.", D.DIPLO.truce },
        }
    end,
    choices = function() return { choice("yes", "MAKE PEACE"), choice("no", "FIGHT ON") } end,
    apply = function(g, l, id)
        if id == "yes" then Diplo.makePeace(g, l.from, l.to)
        else Diplo.remember(g, l.from, l.to, "rebuffed", D.DIPLO.MEMORY.rebuffed) end
    end,
    ai = function(g, l) return Diplo.consider(g, l.to, l.from, "peace") and "yes" or "no" end,
    default = "no",
    still = function(g, l) return Diplo.atWar(g, l.from, l.to) end,
}

K.borders = {
    title = "OPEN ROADS",
    lines = function()
        return {
            { "LET OUR PEOPLE PASS FREELY THROUGH EACH OTHER'S LANDS." },
            { "OPEN BORDERS LET THE SOLDIERS AND SETTLERS OF EACH WALK THE OTHER'S LAND." },
        }
    end,
    choices = function() return { choice("yes", "OPEN THE BORDERS"), choice("no", "KEEP THEM CLOSED") } end,
    apply = function(g, l, id)
        if id == "yes" then Diplo.openBorders(g, l.from, l.to)
        else Diplo.remember(g, l.from, l.to, "rebuffed", D.DIPLO.MEMORY.rebuffed) end
    end,
    ai = function(g, l) return Diplo.consider(g, l.to, l.from, "borders") and "yes" or "no" end,
    default = "no",
    still = function(g, l) return not Diplo.atWar(g, l.from, l.to) and not Diplo.open(g, l.from, l.to) end,
}

K.alliance = {
    title = "A PACT OF ALLIANCE",
    lines = function()
        return {
            { "STAND WITH US, AND WE WILL STAND WITH YOU." },
            { "ALLIES SHARE WHAT THEY SEE, WALK EACH OTHER'S LAND, AND ARE CALLED TO EACH OTHER'S WARS." },
        }
    end,
    choices = function() return { choice("yes", "SWEAR THE PACT"), choice("no", "DECLINE") } end,
    apply = function(g, l, id)
        if id == "yes" then Diplo.ally(g, l.from, l.to)
        else Diplo.remember(g, l.from, l.to, "rebuffed", D.DIPLO.MEMORY.rebuffed) end
    end,
    ai = function(g, l) return Diplo.consider(g, l.to, l.from, "alliance") and "yes" or "no" end,
    default = "no",
    still = function(g, l) return not Diplo.atWar(g, l.from, l.to) and not Diplo.allied(g, l.from, l.to) end,
}

K.tribute = {
    title = "A DEMAND",
    lines = function(g, l)
        return {
            { "PAY US {1} GOLD, AND WE WILL REMEMBER YOUR WISDOM.", l.args.gold },
            { "REFUSE, AND WE WILL REMEMBER THAT TOO." },
        }
    end,
    choices = function(g, l)
        return { choice("pay", "PAY {1} GOLD", { l.args.gold }, g.players[l.to].gold < l.args.gold), choice("no", "REFUSE") }
    end,
    apply = function(g, l, id)
        local M = D.DIPLO.MEMORY
        if id == "pay" and g.players[l.to].gold >= l.args.gold then
            Diplo.pay(g, l.to, l.from, l.args.gold)
            Diplo.remember(g, l.from, l.to, "paid", M.paid)
            Diplo.remember(g, l.to, l.from, "demanded", M.demanded)
        else
            Diplo.remember(g, l.from, l.to, "refused", M.refused)
            Diplo.remember(g, l.to, l.from, "demanded", M.demanded)
            -- A strong leader makes good on the threat.
            local T = Diplo.temper(g, l.from)
            if Diplo.ratio(g, l.from, l.to) >= T.ratio and g.turn >= D.DIPLO.warFrom
                and g.turn >= (Diplo.rel(g, l.from, l.to).truce or 0) then
                Diplo.declare(g, l.from, l.to, "refused")
            end
        end
    end,
    ai = function(g, l)
        if g.players[l.to].gold >= l.args.gold and Diplo.ratio(g, l.from, l.to) >= 1.5 then return "pay" end
        return "no"
    end,
    default = "no",
    still = function(g, l) return not Diplo.atWar(g, l.from, l.to) end,
}

K.gift = {
    title = "A GIFT",
    lines = function(g, l)
        return {
            { "ACCEPT {1} GOLD AS A TOKEN OF OUR FRIENDSHIP.", l.args.gold },
            { "IT IS ALREADY IN YOUR TREASURY." },
        }
    end,
    choices = function() return { choice("ok", "THANK THEM") } end,
    apply = function() end,
    ai = function() return "ok" end,
    default = "ok",
}

K.aid = {
    title = "A PLEA FOR AID",
    lines = function(g, l)
        return {
            { "THE END IS UPON US, AND OUR PEOPLE GO HUNGRY." },
            { "SPARE US {1} GOLD, AND WE WILL NOT FORGET IT.", l.args.gold },
        }
    end,
    choices = function(g, l)
        return { choice("give", "SEND {1} GOLD", { l.args.gold }, g.players[l.to].gold < l.args.gold), choice("no", "REFUSE") }
    end,
    apply = function(g, l, id)
        local M = D.DIPLO.MEMORY
        if id == "give" and g.players[l.to].gold >= l.args.gold then
            Diplo.pay(g, l.to, l.from, l.args.gold)
            Diplo.remember(g, l.from, l.to, "aided", M.aided)
        else
            Diplo.remember(g, l.from, l.to, "deniedAid", M.deniedAid)
        end
    end,
    ai = function(g, l)
        local p = g.players[l.to]
        if Diplo.regard(g, l.to, l.from) >= 25 and p.gold >= l.args.gold + (p.civ.reserve or 80) / 2 then return "give" end
        return "no"
    end,
    default = "no",
}

K.arms = {
    title = "A CALL TO ARMS",
    lines = function(g, l)
        if l.args.ours then
            return {
                { "WE HAVE MARCHED ON {1}.", g.players[l.args.against].name },
                { "YOU SWORE TO STAND WITH US. KEEP YOUR OATH, AND MARCH WITH US." },
            }
        end
        return {
            { "{1} HAS MADE WAR ON US.", g.players[l.args.against].name },
            { "YOU SWORE TO STAND WITH US. KEEP YOUR OATH, AND MARCH WITH US." },
        }
    end,
    choices = function() return { choice("join", "JOIN THE WAR"), choice("no", "STAY OUT OF IT") } end,
    apply = function(g, l, id)
        local M = D.DIPLO.MEMORY
        if id == "join" then
            Diplo.declare(g, l.to, l.args.against, "ally")
            Diplo.remember(g, l.from, l.to, "joined", M.joined)
        else
            Diplo.remember(g, l.from, l.to, "stayedOut", M.stayedOut)
        end
    end,
    ai = function(g, l)
        if Diplo.runaway(g, l.to, l.args.against) and Diplo.regard(g, l.to, l.args.against) < 30 then return "join" end
        if Diplo.regard(g, l.to, l.from) >= 20 and Diplo.regard(g, l.to, l.args.against) < 30 then return "join" end
        return "no"
    end,
    default = "no",
    still = function(g, l)
        return g.players[l.args.against].alive and not Diplo.atWar(g, l.to, l.args.against)
            and Diplo.atWar(g, l.from, l.args.against)
    end,
}

K.refugees = {
    title = "REFUGEES AT THE GATE",
    lines = function(g, l)
        return {
            { "THE END HAS COME TO {1}, AND ITS PEOPLE HAVE NOWHERE LEFT TO GO.", l.args.city },
            { "{1} OF THEM BEG SHELTER IN YOUR CITIES.", l.args.n },
            { "TAKEN IN, THEY SWELL YOUR NEAREST CITY." },
        }
    end,
    choices = function() return { choice("take", "TAKE THEM IN"), choice("no", "TURN THEM AWAY") } end,
    apply = function(g, l, id)
        local M = D.DIPLO.MEMORY
        if id == "take" then
            local c = Diplo.shelter(g, l.to, l.args.cell, l.args.n)
            if c then
                g:tell(l.to, "{1} HAS TAKEN IN {2} REFUGEES", c.name, l.args.n)
                Diplo.remember(g, l.from, l.to, "sheltered", M.sheltered)
            end
        else
            Diplo.remember(g, l.from, l.to, "turnedAway", M.turnedAway)
        end
    end,
    ai = function(g, l) return #g:citiesOf(l.to) > 0 and "take" or "no" end,
    default = "no",
}

K.troops = {
    title = "SOLDIERS ON OUR LAND",
    lines = function()
        return {
            { "YOUR SOLDIERS GATHER IN OUR LANDS, AND OUR PEOPLE ARE AFRAID." },
            { "WE ASK THAT YOU WITHDRAW THEM." },
        }
    end,
    choices = function() return { choice("withdraw", "WITHDRAW THEM"), choice("no", "WE GO WHERE WE PLEASE") } end,
    apply = function(g, l, id)
        local M = D.DIPLO.MEMORY
        if id == "withdraw" then
            Diplo.withdraw(g, l.to, l.from)
            Diplo.remember(g, l.from, l.to, "withdrew", M.withdrew)
        else
            Diplo.remember(g, l.from, l.to, "ignored", M.ignored)
        end
    end,
    ai = function(g, l) return Diplo.regard(g, l.to, l.from) >= 0 and "withdraw" or "no" end,
    default = "no",
}

K.defect = {
    title = "A CITY WISHES TO JOIN YOU",
    lines = function(g, l)
        return {
            { "THE PEOPLE OF {1} HAVE RISEN AGAINST {2}.", l.args.city, g.players[l.from].name },
            { "THEY ASK TO BE YOURS. {1} WILL NOT FORGIVE IT.", g.players[l.from].name },
        }
    end,
    choices = function() return { choice("yes", "WELCOME THEM"), choice("no", "LEAVE THEM BE") } end,
    apply = function(g, l, id)
        local city = g:cityById(l.args.id)
        if not city then return end
        city.pleading = nil
        if id == "yes" and city.owner == l.from then g:cede(city, l.to)
        elseif city.owner == l.from then city.loyalty = D.LOYALTY.calmed end
    end,
    ai = function() return "yes" end,
    default = "no",
    still = function(g, l)
        local city = g:cityById(l.args.id)
        return city ~= nil and city.owner == l.from
    end,
    -- Written by the city's people, under their old banner.
    signed = function(g, l) return L("THE PEOPLE OF {1}", l.args.city) end,
}

K.revolt = {
    title = "A CITY IS LOST",
    lines = function(g, l)
        return {
            { "THE PEOPLE OF {1} HAVE RISEN AND GONE OVER TO US.", l.args.city },
            { "A CITY THAT IS NOT LOVED IS NOT KEPT." },
        }
    end,
    choices = function() return { choice("ok", "SO BE IT") } end,
    apply = function() end,
    ai = function() return "ok" end,
    default = "ok",
}

K.coalition = {
    title = "A PACT AGAINST YOU",
    lines = function(g, l)
        return {
            { "{1} AND {2} HAVE SWORN TO STAND TOGETHER.", g.players[l.from].name, g.players[l.args.with].name },
            { "YOU HAVE GROWN TOO GREAT FOR THE WORLD TO BEAR. WHEN ONE OF US MARCHES ON YOU, THE OTHER WILL FOLLOW." },
        }
    end,
    choices = function() return { choice("ok", "LET THEM COME") } end,
    apply = function() end,
    ai = function() return "ok" end,
    default = "ok",
}

K.citadel = {
    title = "A TRUCE AGAINST THE ABYSS",
    lines = function()
        return {
            { "THE ABYSS HAS RAISED ITS CITADEL AMONG US, AND ITS DEMONS DEVOUR OUR TOWNS AND YOURS." },
            { "WHILE IT STANDS, LET US FIGHT IT AND NOT EACH OTHER. A TRUCE OF {1} TURNS.", D.DIPLO.truce },
        }
    end,
    choices = function() return { choice("yes", "AGAINST THE ABYSS"), choice("no", "WE FIGHT ON") } end,
    apply = function(g, l, id)
        if id == "yes" then Diplo.makePeace(g, l.from, l.to)
        else Diplo.remember(g, l.from, l.to, "rebuffed", D.DIPLO.MEMORY.rebuffed) end
    end,
    ai = function(g, l)
        return (Diplo.citadelStands(g) and Diplo.regard(g, l.to, l.from) > -60) and "yes" or "no"
    end,
    default = "no",
    still = function(g, l) return Diplo.atWar(g, l.from, l.to) end,
}

-- The city of `who`'s with the most food stored, and that food.
local function granary(g, who)
    local best
    for _, c in ipairs(g:citiesOf(who)) do
        if not best or c.food > best.food then best = c end
    end
    return best, best and best.food or 0
end
Diplo.granary = granary

K.grain = {
    title = "GRAIN FOR GOLD",
    lines = function(g, l)
        return {
            { "THE FAMINE HAS COME TO {1}. OUR GRANARIES ARE DUST.", l.args.city },
            { "SELL US {1} FOOD FROM YOUR STORES, AND WE WILL PAY {2} GOLD.", l.args.food, l.args.gold },
            { "IT IS TAKEN FROM THE CITY OF YOURS WITH THE MOST STORED." },
        }
    end,
    choices = function(g, l)
        local _, food = granary(g, l.to)
        return { choice("sell", "SELL THE GRAIN", nil, food < l.args.food), choice("no", "KEEP IT") }
    end,
    apply = function(g, l, id)
        local M = D.DIPLO.MEMORY
        local from = g:cityById(l.args.id)
        local store, food = granary(g, l.to)
        if id == "sell" and store and food >= l.args.food and from and from.owner == l.from then
            store.food = store.food - l.args.food
            from.food = from.food + l.args.food
            local gold = Diplo.pay(g, l.from, l.to, l.args.gold)
            g:tell(l.to, "{1} SOLD {2} FOOD TO {3} FOR {4} GOLD", store.name, l.args.food, from.name, gold)
            g:tell(l.from, "{1} BOUGHT {2} FOOD FROM {3}", from.name, l.args.food, g.players[l.to].name)
            Diplo.remember(g, l.from, l.to, "fed", M.fed)
        else
            Diplo.remember(g, l.from, l.to, "hoarded", M.hoarded)
        end
    end,
    ai = function(g, l)
        local _, food = granary(g, l.to)
        if food >= l.args.food + 5 and Diplo.regard(g, l.to, l.from) >= -10 and not Diplo.starving(g, l.to) then return "sell" end
        return "no"
    end,
    default = "no",
    still = function(g, l)
        local c = g:cityById(l.args.id)
        return c ~= nil and c.owner == l.from and not Diplo.atWar(g, l.from, l.to)
    end,
}

K.quarantine = {
    title = "BORDERS SHUT AGAINST THE PLAGUE",
    lines = function(g, l)
        return {
            { "THE PLAGUE IS IN YOUR TOWNS. WE HAVE SHUT OUR BORDERS TO YOUR PEOPLE FOR {1} TURNS.", D.DIPLO.quarantine },
            { "SHUT YOURS TO OURS AS WELL, AND THE SICKNESS WILL HAVE NO ROAD EITHER WAY." },
        }
    end,
    choices = function() return { choice("shut", "SHUT OURS TOO"), choice("open", "KEEP OURS OPEN") } end,
    apply = function(g, l, id)
        if id == "shut" then
            Diplo.quarantine(g, l.to, l.from)
            Diplo.remember(g, l.from, l.to, "quarantined", D.DIPLO.MEMORY.quarantined)
        end
    end,
    ai = function(g, l)
        for _, c in ipairs(g:citiesOf(l.to)) do if c.sick then return "open" end end
        return "shut"
    end,
    default = "open",
}

K.rogue = {
    title = "A CITY GOES ROGUE",
    lines = function(g, l)
        return {
            { "THE PEOPLE OF {1} NO LONGER HEED YOU. THEY KEEP THEIR GRAIN, THEIR GOLD AND THEIR GATES.", l.args.city },
            { "THEIR ELDERS WILL HEAR YOU. BUY BACK THEIR GOODWILL, SEND IN SOLDIERS, OR WAIT FOR THEIR HEARTS TO TURN." },
            { "SOLDIERS COST THE CITY A CITIZEN." },
        }
    end,
    choices = function(g, l)
        local city = g:cityById(l.args.id)
        local cost = city and Diplo.rogueCost(city) or 0
        return {
            choice("pay", "PAY {1} GOLD", { cost }, g.players[l.to].gold < cost),
            choice("force", "SEND IN SOLDIERS", nil, not (city and Diplo.soldiersAt(g, city))),
            choice("wait", "WAIT"),
        }
    end,
    apply = function(g, l, id)
        local city = g:cityById(l.args.id)
        if not city or not city.rogue then return end
        local Y = D.DIPLO.rogue
        if id == "pay" and g.players[l.to].gold >= Diplo.rogueCost(city) then
            g.players[l.to].gold = g.players[l.to].gold - Diplo.rogueCost(city)
            Diplo.reclaim(g, city, Y.bought)
        elseif id == "force" and Diplo.soldiersAt(g, city) then
            city.pop = math.max(1, city.pop - 1)
            g:assignWork(city)
            Diplo.reclaim(g, city, Y.forced)
        end
    end,
    ai = function(g, l)
        local city = g:cityById(l.args.id)
        if not city then return "wait" end
        local p = g.players[l.to]
        if p.gold >= Diplo.rogueCost(city) + (p.civ.reserve or 80) / 2 then return "pay" end
        if Diplo.soldiersAt(g, city) then return "force" end
        return "wait"
    end,
    default = "wait",
    still = function(g, l)
        local c = g:cityById(l.args.id)
        return c ~= nil and c.rogue ~= nil and c.owner == l.to
    end,
    signed = function(g, l) return L("THE ELDERS OF {1}", l.args.city) end,
}

--- the cataclysm's own business ----------------------------------------------------------

function Diplo.citadelStands(game)
    local lair = require("src.demons").citadel(game)
    return lair ~= nil and (lair.hp or 0) > 0
end

-- a's land shut to b against the plague, for D.DIPLO.quarantine turns.
function Diplo.quarantine(game, a, b)
    local r = Diplo.rel(game, a, b)
    r.shut = r.shut or {}
    r.shut[a] = game.turn + D.DIPLO.quarantine
    Diplo.expel(game, b, a)
end

--- rogue cities --------------------------------------------------------------------------

function Diplo.rogueCost(city)
    local Y = D.DIPLO.rogue
    return Y.base + Y.perPop * city.pop
end

-- A soldier of the owner's in the city or beside it.
function Diplo.soldiersAt(game, city)
    for _, n in ipairs(game:within(game.cells[city.cell], 1)) do
        local m = game.mil[n.id]
        if m and m.owner == city.owner and not m.def.civilian then return m end
    end
end

-- City `city` has no loyalty left and no one to go over to: it keeps to
-- itself (src/loyalty.lua), and its elders write to its owner.
function Diplo.goRogue(game, city)
    if city.rogue then return end
    city.rogue = game.turn
    city.loyalty = 0
    city.build, city.prod = nil, 0
    game:tell(city.owner, "{1} HAS GONE ROGUE", city.name)
    game:emit({ kind = "rogue", cell = city.cell, city = city })
    Diplo.send(game, city.owner, city.owner, "rogue", { city = city.name, id = city.id })
end

-- The rogue city back in the fold, at `loyalty`.
function Diplo.reclaim(game, city, loyalty)
    city.rogue = nil
    city.loyalty = math.max(city.loyalty or 0, loyalty)
    game:tell(city.owner, "{1} HAS RETURNED TO THE FOLD", city.name)
    game:emit({ kind = "reclaimed", cell = city.cell, city = city })
end

-- Sends a letter. To the computer it is answered at once; to the player it
-- waits in the mail, and the answer is theirs. Answers the letter.
function Diplo.send(game, from, to, kind, args)
    if not civ(game, from) or not civ(game, to) then return end
    local d = game.diplo or Diplo.ensure(game)
    local l = { id = d.nextMail, turn = game.turn, from = from, to = to, kind = kind, args = args or {},
        due = game.turn + D.DIPLO.answer }
    d.nextMail = d.nextMail + 1
    -- A letter from one's own people (a rogue city's elders) asks nothing
    -- of another civilization.
    if from ~= to then
        local rel = Diplo.rel(game, from, to)
        rel.asked[from] = rel.asked[from] or {}
        rel.asked[from][kind] = game.turn
    end
    if game.players[to].human then
        d.mail[#d.mail + 1] = l
        while #d.mail > D.DIPLO.keep do
            -- The oldest that is answered goes first.
            local gone = false
            for k, m in ipairs(d.mail) do
                if m.answer then table.remove(d.mail, k) gone = true break end
            end
            if not gone then break end
        end
        game:emit({ kind = "letter", letter = l })
    else
        Diplo.answer(game, l, K[kind].ai(game, l))
    end
    return l
end

-- Is this letter still asking? One whose question has gone by (the peace
-- made already, the city taken meanwhile) is answered by events.
function Diplo.stillAsks(game, l)
    local k = K[l.kind]
    return not l.answer and (not k.still or k.still(game, l))
end

-- The letter answered, `id` one of its choices.
function Diplo.answer(game, l, id)
    if l.answer then return false end
    local k = K[l.kind]
    if k.still and not k.still(game, l) then
        l.answer, l.read = "moot", true
        return false
    end
    for _, c in ipairs(k.choices(game, l)) do
        if c.id == id and c.off then id = k.default end
    end
    l.answer, l.read = id, true
    k.apply(game, l, id)
    return true
end

-- The player's letters still waiting, oldest first.
function Diplo.waiting(game, who)
    local out = {}
    for _, l in ipairs((game.diplo or Diplo.ensure(game)).mail) do
        if l.to == who and not l.answer then
            if Diplo.stillAsks(game, l) then out[#out + 1] = l else l.answer, l.read = "moot", true end
        end
    end
    return out
end

-- The computer answers the player's letters for them, as it would its own
-- (while it plays their side: the developer tools' skip, pictures).
function Diplo.answerFor(game, who)
    for _, l in ipairs(Diplo.waiting(game, who)) do Diplo.answer(game, l, K[l.kind].ai(game, l)) end
end

function Diplo.letter(game, id)
    for _, l in ipairs((game.diplo or Diplo.ensure(game)).mail) do
        if l.id == id then return l end
    end
end

-- What a letter says, in the language of the moment.
function Diplo.says(game, l)
    local out = {}
    for _, line in ipairs(K[l.kind].lines(game, l)) do
        out[#out + 1] = L(line[1], select(2, unpack(line)))
    end
    return out
end

-- Who signs it.
function Diplo.signed(game, l)
    local k = K[l.kind]
    if k.signed then return k.signed(game, l) end
    return L("{1} OF {2}", leaderOf(game, l.from), game.players[l.from].name)
end

--- the player's own asking -------------------------------------------------------------------

-- Would `who` (the computer) agree to `kind` from `from`? And what it says.
function Diplo.consider(game, who, from, kind, args)
    local att = Diplo.regard(game, who, from)
    local r = Diplo.rel(game, who, from)
    local stage = Cat.stage(game)
    local ease = Diplo.sharedRival(game, who, from) and D.DIPLO.runaway.ease or 0
    -- A leader who keeps to themself opens up only to a close friend.
    local closed = Diplo.temper(game, who).closed
    if kind == "peace" then
        if not r.war then return false, "WE ARE NOT AT WAR." end
        -- Not with the one running away with the world.
        if Diplo.runaway(game, who, from) and Diplo.atWarWithAnyBut(game, from, who) then
            return false, "NOT UNTIL YOU ARE BROUGHT LOW."
        end
        if Diplo.citadelStands(game) and att > -60 then return true, "AGAINST THE ABYSS, THEN. TOGETHER." end
        if game.turn - (r.since or 0) < 5 then return false, "IT IS TOO SOON. LET THE BLOOD DRY FIRST." end
        if Diplo.ratio(game, who, from) < 1.3 or att > -30 or stage then return true, "ENOUGH. LET THERE BE PEACE." end
        return false, "NOT WHILE WE ARE WINNING."
    elseif kind == "borders" then
        if r.war then return false, "NOT WHILE WE ARE AT WAR." end
        if att >= (closed or 5) - ease then return true, "OUR ROADS ARE OPEN TO YOU." end
        if closed then return false, "WE KEEP TO OURSELVES." end
        return false, "WE DO NOT WANT YOUR SOLDIERS ON OUR LAND."
    elseif kind == "alliance" then
        if r.war then return false, "NOT WHILE WE ARE AT WAR." end
        if not (r.borders or r.alliance) and ease == 0 then return false, "OPEN YOUR BORDERS TO US FIRST." end
        if att >= max(35, closed or 0) - ease then return true, "WE ARE ONE. WHAT YOU SEE, WE SEE." end
        if closed then return false, "WE KEEP TO OURSELVES." end
        return false, "WE DO NOT TRUST YOU ENOUGH FOR THAT."
    elseif kind == "tribute" then
        local gold = args and args.gold or 0
        if game.players[who].gold < gold then return false, "WE HAVE NOTHING TO GIVE." end
        if Diplo.ratio(game, from, who) >= 1.5 then return true, "TAKE IT, AND LEAVE US BE." end
        return false, "COME AND TAKE IT, IF YOU CAN."
    end
    return false, "NO."
end

-- What the player can ask: { kind, label, off, why }.
function Diplo.asks(game, a, b)
    local r = Diplo.rel(game, a, b)
    local p = game.players[a]
    local out = {}
    if r.war then
        out[#out + 1] = { kind = "peace", label = Diplo.citadelStands(game) and "TRUCE AGAINST THE ABYSS" or "OFFER PEACE" }
    else
        local truce = r.truce and game.turn < r.truce
        out[#out + 1] = { kind = "war", label = "DECLARE WAR", off = truce and true or nil,
            why = truce and L("A TRUCE HOLDS {1} TURNS MORE", r.truce - game.turn) or nil }
        if not (r.borders or r.alliance) then out[#out + 1] = { kind = "borders", label = "OPEN BORDERS" } end
        if not r.alliance then out[#out + 1] = { kind = "alliance", label = "ALLIANCE" } end
        out[#out + 1] = { kind = "gift", label = L("GIFT {1}", D.DIPLO.gift), off = p.gold < D.DIPLO.gift or nil }
        out[#out + 1] = { kind = "tribute", label = "DEMAND TRIBUTE" }
    end
    return out
end

-- The tribute the player would ask of b.
function Diplo.tributeOf(game, b)
    return max(10, min(100, floor(game.players[b].gold * 0.3 / 5) * 5))
end

-- The player (a) asks b: done at once, as the computer answers. Answers
-- whether it was agreed, and what b says to it.
function Diplo.propose(game, a, b, kind)
    local r = Diplo.rel(game, a, b)
    local M = D.DIPLO.MEMORY
    local ok, says
    if kind == "war" then
        if r.truce and game.turn < r.truce then return false, "A TRUCE HOLDS." end
        ok = Diplo.declare(game, a, b, "player")
        says = "THEN WE WILL MEET ON THE FIELD."
    elseif kind == "gift" then
        local gold = Diplo.pay(game, a, b, D.DIPLO.gift)
        ok = gold > 0
        if ok then Diplo.remember(game, b, a, "gift", gold * M.gift) end
        says = ok and "A GENEROUS GIFT. WE WILL REMEMBER IT." or "YOU HAVE NOTHING TO GIVE."
    elseif kind == "tribute" then
        local gold = Diplo.tributeOf(game, b)
        ok, says = Diplo.consider(game, b, a, "tribute", { gold = gold })
        Diplo.remember(game, b, a, "demanded", M.demanded)
        if ok then Diplo.pay(game, b, a, gold) end
        r.asked[a] = r.asked[a] or {}
        r.asked[a].tribute = game.turn
    else
        ok, says = Diplo.consider(game, b, a, kind)
        if ok then
            if kind == "peace" then Diplo.makePeace(game, a, b)
            elseif kind == "borders" then Diplo.openBorders(game, a, b)
            elseif kind == "alliance" then Diplo.ally(game, a, b) end
        end
    end
    r.said[b] = { text = says, turn = game.turn, ok = ok }
    if not ok and kind ~= "war" then game:tell(a, "{1} REFUSES", game.players[b].name) end
    return ok, says
end

-- a's soldiers out of b's land (asked to, and agreed).
function Diplo.withdraw(game, a, b)
    local r = Diplo.rel(game, a, b)
    local was = r.borders
    r.borders = false
    local ally = r.alliance
    r.alliance = false
    Diplo.expel(game, a, b)
    r.borders, r.alliance = was, ally
end

--- the computer's leaders ----------------------------------------------------------------

local function asked(game, a, b, kind, wait)
    local r = Diplo.rel(game, a, b)
    local t = r.asked[a] and r.asked[a][kind]
    return t and game.turn - t < (wait or D.DIPLO.cooldown)
end

local function soldiersIn(game, a, b)
    local n = 0
    for _, u in ipairs(game.units) do
        if u.owner == a and not u.def.civilian and game.cells[u.cell].owner == b then n = n + 1 end
    end
    return n
end

-- The hungriest city of id's that is starving, if one is.
local function starving(game, id)
    local worst, wv
    for _, c in ipairs(game:citiesOf(id)) do
        local f = game:cityYield(c)
        local v = f - c.pop * 2
        if v < 0 and (not wv or v < wv) then worst, wv = c, v end
    end
    return worst
end
Diplo.starving = starving

local function sickIn(game, id)
    for _, c in ipairs(game:citiesOf(id)) do if c.sick then return true end end
    return false
end

-- What the computer's leader `p` does with the others this turn: make war
-- or peace, ask for open borders or an alliance, give, demand, plead.
function Diplo.think(game, p)
    local a = p.id
    local T = Diplo.temper(game, a)
    local rng = game.rng
    local soldiers, cities = 0, #game:citiesOf(a)
    for _, u in ipairs(game.units) do
        if u.owner == a and not u.def.civilian and not u.def.scout then soldiers = soldiers + 1 end
    end
    local stage = Cat.stage(game)
    for _, b in ipairs(Diplo.known(game, a)) do
        local r = Diplo.rel(game, a, b)
        local att = Diplo.regard(game, a, b)
        local ratio = Diplo.ratio(game, a, b)
        local rival = Diplo.sharedRival(game, a, b)
        local ease = rival and D.DIPLO.runaway.ease or 0
        local hungry = stage and stage ~= "omen" and starving(game, a)
        if r.war then
            local long = game.turn - (r.since or 0) >= 8
            local runaway = Diplo.runaway(game, a, b)
            if Diplo.citadelStands(game) and not runaway and not asked(game, a, b, "citadel", 8) then
                -- The abyss first: a truce to raze its citadel.
                Diplo.send(game, a, b, "citadel")
            elseif long and not runaway and not asked(game, a, b, "peace", 6) and (ratio < 0.9 or att > -20 or stage)
                and rng:random() < 0.4 then
                Diplo.send(game, a, b, "peace")
            end
        elseif hungry and att >= -10 and p.gold >= 15 and not asked(game, a, b, "grain", 6)
            and select(2, granary(game, b)) >= D.DIPLO.grain.food then
            -- The famine: grain bought from a neighbour with some to spare.
            local G = D.DIPLO.grain
            Diplo.send(game, a, b, "grain", { food = G.food, gold = min(G.gold, p.gold), city = hungry.name, id = hungry.id })
        elseif Cat.is(game, "plague") and stage and stage ~= "omen" and Diplo.open(game, a, b)
            and not Diplo.shutTo(game, b, a) and sickIn(game, b) and not sickIn(game, a) then
            -- The plague: the healthy shut their land to the sick.
            Diplo.quarantine(game, a, b)
            Diplo.send(game, a, b, "quarantine")
        else
            local war = T.war - (stage and 15 or 0)
            -- Against the runaway, the coalition's might counts together.
            if Diplo.runaway(game, a, b) then
                local might = Diplo.army(game, a)
                for c, q in ipairs(game.players) do
                    if c ~= a and c ~= b and q.alive and Diplo.allied(game, a, c) and Diplo.runaway(game, c, b) then
                        might = might + Diplo.army(game, c)
                    end
                end
                ratio = (might + 5) / (Diplo.army(game, b) + 5)
            end
            -- To an opportunist, one already at war is half again weaker.
            if T.pounce and Diplo.atWarWithAnyBut(game, b, a) then ratio = ratio * 1.5 end
            if game.turn >= D.DIPLO.warFrom and game.turn >= (r.truce or 0) and not r.alliance
                and att <= war and ratio >= T.ratio and soldiers >= 2 + cities
                and not Diplo.atWarWithAny(game, a) and rng:random() < T.chance then
                local why = att <= -40 and "grudge" or (pressing(game, a, b) > 3 and "land" or "weak")
                Diplo.declare(game, a, b, why)
            elseif T.tribute and ratio >= 1.5 and att < 5 and game.players[b].gold >= 40
                and game.turn >= D.DIPLO.warFrom and not asked(game, a, b, "tribute", 20) then
                Diplo.send(game, a, b, "tribute", { gold = Diplo.tributeOf(game, b) })
            elseif rival and not r.alliance and att >= max(40, T.closed or 0) - ease and not asked(game, a, b, "alliance", 8) then
                -- Against the runaway, straight to an alliance.
                Diplo.send(game, a, b, "alliance")
            elseif not T.closed and not (r.borders or r.alliance) and att >= (T.friends or 20) - ease
                and game.turn >= D.DIPLO.friendsFrom
                and not asked(game, a, b, "borders") then
                Diplo.send(game, a, b, "borders")
            elseif not T.closed and r.borders and not r.alliance and att >= 40 - ease
                and not asked(game, a, b, "alliance", 15) then
                Diplo.send(game, a, b, "alliance")
            elseif att >= (T.gift or 30) and p.gold > (p.civ.reserve or 80) + 60 and not asked(game, a, b, "gift", 25) then
                local gold = Diplo.pay(game, a, b, D.DIPLO.gift)
                if gold > 0 then
                    Diplo.remember(game, b, a, "gift", gold * D.DIPLO.MEMORY.gift)
                    Diplo.send(game, a, b, "gift", { gold = gold })
                end
            elseif stage and stage ~= "omen" and att >= 15 and (starving(game, a) or p.gold < 20)
                and not asked(game, a, b, "aid", 15) then
                Diplo.send(game, a, b, "aid", { gold = D.DIPLO.aid })
            elseif r.borders and not r.alliance and soldiersIn(game, b, a) >= 3 and not asked(game, a, b, "troops") then
                Diplo.send(game, a, b, "troops")
            end
        end
    end
end

--- the turn ----------------------------------------------------------------------------

-- Once a turn: memories fade, and letters left too long take their default
-- answer.
function Diplo.turn(game)
    local d = game.diplo or Diplo.ensure(game)
    d.press = nil
    for _, r in pairs(d.rel) do
        for _, list in pairs(r.mem) do
            for k = #list, 1, -1 do
                local m = list[k]
                local fade = m.what == "betrayed" and D.DIPLO.fade / 2 or D.DIPLO.fade
                if m.v > 0 then m.v = max(0, m.v - fade) else m.v = min(0, m.v + fade) end
                if m.v == 0 then table.remove(list, k) end
            end
        end
    end
    for _, l in ipairs(d.mail) do
        if not l.answer and game.turn > l.due then
            if Diplo.stillAsks(game, l) then
                l.late = true
                Diplo.answer(game, l, K[l.kind].default)
                if #K[l.kind].choices(game, l) > 1 then
                    game:tell(l.to, "THE LETTER FROM {1} WENT UNANSWERED", game.players[l.from].name)
                end
            else
                l.answer, l.read = "moot", true
            end
        end
    end
end

return Diplo
