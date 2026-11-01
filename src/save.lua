-- A game kept, and taken up again: the whole of a game written to a file in
-- the save folder ("save"), and read back into the same state it was left in.
--
-- The game is one table of plain data -- cells, units, cities, players, the
-- cataclysm's marks -- with no LÖVE in it, so what is written is that table,
-- written out as Lua that builds it again. Two things in it are not data and
-- are left out: the little tables of numbers each unit, lair and
-- civilization is *of* (`def`, `civ`, from src/defs.lua, the same for every
-- game), which are hung back on by kind as the game is read, and the events
-- the screen has not taken yet, which are of this moment and not of the
-- game.
--
-- A table reached twice -- a city a dozen hexes point at, a unit both the
-- map and the list hold -- is written once and pointed at, so what comes
-- back has the same shape, one city and not a dozen copies of it. Tables
-- reached once are written where they stand.
--
-- The picture of the map (src/world.lua) is not written: it is traced again
-- from the cells as a new game's is, behind the same loading bar.
--
-- No LÖVE here but the file, and that guarded, so the tests can write a game
-- out and read it back under plain LuaJIT.

local D = require "src.defs"

local Save = {}

local floor, abs, huge = math.floor, math.abs, math.huge
local format = string.format

local FILE = "save"
local META = "save.meta"
-- The shape of what is written. A save of another one is not read.
Save.VERSION = 1

-- What is not written. `def` is the table of numbers a unit or a lair is
-- of, and a player's `civ` the one its civilization is of: both are in
-- src/defs.lua, the same for every game, and are hung back on by kind as
-- the game is read. The *game's* own `civ`, which is its civilian units hex
-- by hex, is state and is written -- hence the look at what holds the
-- field. `events` is what the screen has not taken yet: of this moment,
-- not of the game.
local function omit(parent, k)
    if k == "def" then return true end
    if k == "civ" then return parent.explored ~= nil end
    if k == "events" then return parent.cells ~= nil and parent.players ~= nil end
    return false
end

--- writing ----------------------------------------------------------------------------

-- A number as it is written: whole numbers as they are, and the rest in as
-- few figures as read back the very same number, so a game read back is the
-- same game bit for bit.
local function number(n)
    if n ~= n or n == huge or n == -huge then error("a game cannot hold " .. tostring(n)) end
    if n == floor(n) and abs(n) < 2 ^ 53 then return format("%d", n) end
    local short = format("%.14g", n)
    if tonumber(short) == n then return short end
    return format("%.17g", n)
end

local function literal(v)
    local t = type(v)
    if t == "number" then return number(v) end
    if t == "string" then return format("%q", v) end
    if t == "boolean" then return v and "true" or "false" end
    error("a game cannot hold a " .. t)
end

-- `k=` as it is written inside a table.
local function field(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k .. "=" end
    return "[" .. literal(k) .. "]="
end

-- `.k` or `[k]`, as it is written after the name of a table.
local function index(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then return "." .. k end
    return "[" .. literal(k) .. "]"
end

-- A table's keys in a settled order -- numbers first, each in order -- so
-- that the same game always writes the same file, whatever order the
-- language happens to hand its tables back in.
local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    return keys
end

-- Every table in `v`, in the order they are first met, and which of them are
-- met more than once (or hold themselves): those are written on their own and
-- pointed at. Anything a game may not hold is refused here, where the way to
-- it can still be named.
local function walk(v, seen, many, stack, all, path)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == huge or v == -huge then error(path .. " is " .. tostring(v)) end
        return
    end
    if t ~= "table" then
        if t ~= "string" and t ~= "boolean" then error(path .. " is a " .. t) end
        return
    end
    if stack[v] or seen[v] then many[v] = true return end
    seen[v] = true
    stack[v] = true
    all[#all + 1] = v
    for k in pairs(v) do
        if type(k) ~= "string" and type(k) ~= "number" then
            error(path .. " is keyed by a " .. type(k))
        end
    end
    for _, k in ipairs(sortedKeys(v)) do
        if not omit(v, k) then walk(v[k], seen, many, stack, all, path .. "." .. tostring(k)) end
    end
    stack[v] = nil
end

-- Is the table a list, 1..n with nothing missing and nothing else?
local function listLength(t)
    local n = #t
    if n == 0 then return 0 end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) then return nil end
        count = count + 1
    end
    if count ~= n then return nil end
    for k = 1, n do if t[k] == nil then return nil end end
    return n
end

function Save.encode(game)
    local seen, many, all = {}, {}, {}
    walk(game, seen, many, {}, all, "game")
    many[game] = true
    local id, shared = {}, {}
    for _, t in ipairs(all) do
        if many[t] then
            shared[#shared + 1] = t
            id[t] = #shared
        end
    end

    local out = { "local r={}" }
    for k = 1, #shared do out[#out + 1] = "r[" .. k .. "]={}" end

    -- A value as it is written: a table met once where it stands, one met
    -- more than once as the name it was given.
    local write
    local function inline(t)
        local parts, n = {}, listLength(t)
        for k = 1, n or 0 do parts[#parts + 1] = write(t[k]) end
        for _, k in ipairs(sortedKeys(t)) do
            if not (n and type(k) == "number" and k >= 1 and k <= n) and not omit(t, k) then
                parts[#parts + 1] = field(k) .. write(t[k])
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    write = function(v)
        if type(v) ~= "table" then return literal(v) end
        if id[v] then return "r[" .. id[v] .. "]" end
        return inline(v)
    end

    for k, t in ipairs(shared) do
        local n = listLength(t)
        for i = 1, n or 0 do out[#out + 1] = "r[" .. k .. "][" .. i .. "]=" .. write(t[i]) end
        for _, key in ipairs(sortedKeys(t)) do
            if not (n and type(key) == "number" and key >= 1 and key <= n) and not omit(t, key) then
                out[#out + 1] = "r[" .. k .. "]" .. index(key) .. "=" .. write(t[key])
            end
        end
    end
    out[#out + 1] = "return r[1]"
    return table.concat(out, "\n") .. "\n"
end

--- reading ----------------------------------------------------------------------------

-- The written game, run with nothing of the language to hand: it builds
-- tables and nothing else, so there is nothing for it to reach.
local function compile(text)
    if setfenv then
        local f = loadstring(text, "save")
        if f then setfenv(f, {}) end
        return f
    end
    return load(text, "save", "t", {})
end

-- The tables of numbers left out as it was written, hung back on by kind.
function Save.relink(g)
    local Game = require "src.game"
    local Rng = require "src.rng"
    local Beasts = require "src.beasts"
    setmetatable(g, Game)
    if g.rng then setmetatable(g.rng, Rng) end
    g.events = {}
    g.log = g.log or {}
    for _, p in pairs(g.players or {}) do
        p.civ = p.wild and Beasts.player().civ or D.CIVS[p.id]
        if not p.civ then error("a game of a kind this one does not know") end
    end
    for _, u in ipairs(g.units or {}) do
        u.def = D.UNITS[u.kind] or D.BEASTS[u.kind]
        if not u.def then error("no such unit as " .. tostring(u.kind)) end
    end
    for _, l in ipairs(g.lairs or {}) do
        l.def = D.LAIRS[l.kind]
        if not l.def then error("no such lair as " .. tostring(l.kind)) end
    end
    return g
end

function Save.decode(text)
    local chunk = compile(text)
    if not chunk then return nil, "the save cannot be read" end
    local ok, g = pcall(chunk)
    if not ok or type(g) ~= "table" or type(g.cells) ~= "table" or not g.turn then
        return nil, "the save is not a game"
    end
    local fine, why = pcall(Save.relink, g)
    if not fine then return nil, tostring(why) end
    return g
end

--- the file ----------------------------------------------------------------------------

-- What the title screen shows about the game waiting: its turn, its
-- cataclysm and the seed it was made from. Kept beside the game, as plain
-- lines, so the title does not have to read a whole game to say what it is.
local function meta(game)
    return table.concat({
        "version=" .. Save.VERSION,
        "turn=" .. game.turn,
        "cataclysm=" .. (game.cataclysm and game.cataclysm.kind or "none"),
        "seed=" .. (game.seed or 0),
        "cities=" .. #(game:citiesOf(1) or {}),
    }, "\n") .. "\n"
end

local function parseMeta(text)
    local out = {}
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^(%w+)=(.*)$")
        if k then out[k] = tonumber(v) or v end
    end
    return out
end

local function has(name)
    return love and love.filesystem and love.filesystem.getInfo(name) ~= nil
end

-- Is there a game to take up again?
function Save.exists() return has(FILE) and has(META) end

-- What it is: { turn, cataclysm, seed, cities }, or nil. Read once and
-- kept: the title screen asks every frame.
local kept, asked = nil, false
function Save.info()
    if asked then return kept end
    asked = true
    kept = nil
    if Save.exists() then
        local text = love.filesystem.read(META)
        local m = text and parseMeta(text)
        if m and m.version == Save.VERSION and m.turn then kept = m end
    end
    return kept
end

-- Writes the game over whatever was kept. Squeezed if the engine can; the
-- first line says which it is, and is there to be read either way.
function Save.write(game)
    if not (love and love.filesystem) then return false end
    local body = Save.encode(game)
    local head, data = "hextinct 1 text\n", body
    local ok, packed = pcall(function()
        return love.data.compress("string", "zlib", body, 9)
    end)
    if ok and packed then head, data = "hextinct 1 zlib\n", packed end
    local wrote = pcall(love.filesystem.write, FILE, head .. data)
    if not wrote then return false end
    asked = false
    return (pcall(love.filesystem.write, META, meta(game)))
end

-- The game kept, ready to be played, or nil and why not.
function Save.read()
    if not Save.exists() then return nil, "there is no game kept" end
    local raw = love.filesystem.read(FILE)
    if not raw then return nil, "the save cannot be read" end
    local head, body = raw:match("^([^\n]*)\n(.*)$")
    if not head then return nil, "the save cannot be read" end
    local kind = head:match("^hextinct 1 (%a+)$")
    if not kind then return nil, "the save was kept by another version" end
    if kind == "zlib" then
        local ok, text = pcall(function()
            return love.data.decompress("string", "zlib", body)
        end)
        if not ok or not text then return nil, "the save cannot be opened" end
        body = text
    end
    return Save.decode(body)
end

-- Throws the kept game away: once it is over, there is nothing to take up.
function Save.clear()
    asked = false
    if not (love and love.filesystem) then return end
    pcall(love.filesystem.remove, FILE)
    pcall(love.filesystem.remove, META)
end

return Save
