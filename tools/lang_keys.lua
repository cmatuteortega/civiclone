-- Every English line the game can show, as the code writes it: what a
-- language's table (src/locale/<code>.lua) has to have. `luajit
-- tools/lang_keys.lua es` lists the ones the Spanish table hasn't; with no
-- language, it lists them all. tests/lang_test.lua asks the same.
--
-- The lines are found in the code's string literals: those in capitals, or
-- with a {1} for what goes in, with literals joined by `..` taken as one.
-- Some are put together from parts at run time, and are made here as the
-- game makes them (`derived`).

package.path = "./?.lua;" .. package.path

local Keys = {}

-- Files with nothing in them for the screen, or only what isn't words.
local SKIP_FILES = {
    ["src/font.lua"] = true, ["src/synth.lua"] = true, ["src/models.lua"] = true, ["src/tracer.lua"] = true,
    ["src/lang.lua"] = true, ["src/jitroom.lua"] = true, ["src/shapes.lua"] = true, ["src/save.lua"] = true,
    ["src/ui/audio.lua"] = true, ["src/ui/sea.lua"] = true, ["src/ui/sheet.lua"] = true,
    ["src/audiothread.lua"] = true,
}

-- Literals in capitals that are names, not words: the cities, the rivers,
-- the civilizations, the game's own name, and odds and ends.
local NOT_WORDS = {
    HEXTINCT = true, FPS = true, [" FPS"] = true, LC_ALL = true, LC_MESSAGES = true, LANG = true,

}

local function files()
    local out = { "main.lua" }
    for _, dir in ipairs({ "src", "src/ui" }) do
        for name in io.popen("ls " .. dir):lines() do
            local p = dir .. "/" .. name
            if name:match("%.lua$") and not SKIP_FILES[p] then out[#out + 1] = p end
        end
    end
    return out
end

local function read(p)
    local f = assert(io.open(p))
    local s = f:read("*a")
    f:close()
    return s
end

-- The code without its comments, and its string literals in order, those
-- joined by `..` (and nothing else) as one.
local function literals(src)
    local out, i, n = {}, 1, #src
    local last, lastEnd
    while i <= n do
        local c = src:sub(i, i)
        if src:sub(i, i + 3) == "--[[" then
            local e = src:find("]]", i, true)
            i = (e or n) + 2
        elseif src:sub(i, i + 1) == "--" then
            local e = src:find("\n", i, true)
            i = (e or n) + 1
        elseif c == '"' or c == "'" then
            local j, buf = i + 1, {}
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then
                    buf[#buf + 1] = src:sub(j + 1, j + 1)
                    j = j + 2
                elseif d == c then
                    break
                else
                    buf[#buf + 1] = d
                    j = j + 1
                end
            end
            local s = table.concat(buf)
            -- Joined to the one before by `..` and nothing more?
            if last and src:sub(lastEnd + 1, i - 1):match("^%s*%.%.%s*$") then
                out[#out] = out[#out] .. s
            else
                out[#out + 1] = s
            end
            last, lastEnd = s, j
            i = j + 1
        elseif src:sub(i, i + 1) == "[[" then
            local e = src:find("]]", i, true)
            i = (e or n) + 2
        else
            i = i + 1
        end
    end
    return out
end

-- The names: of the rivers, the cities, the civilizations and their
-- leaders, which are the same in every language.
local NAMES
local function names()
    if NAMES then return NAMES end
    local D = require "src.defs"
    NAMES = {}
    for _, r in ipairs(D.RIVERS) do NAMES[r] = true end
    for _, c in ipairs(D.CIVS) do
        NAMES[c.name], NAMES[c.leader] = true, true
        for _, n in ipairs(c.cities) do NAMES[n] = true end
    end
    -- The buildings' short names alone: they are shown as "short|..." only.
    for _, b in pairs(D.BUILDINGS) do if b.short ~= b.name then NAMES[b.short] = true end end
    NAMES["QUART."], NAMES.BAL, NAMES.PROD = true, true, true
    return NAMES
end

-- Is literal `s` words for the screen?
local function wordy(s)
    if NOT_WORDS[s] or names()[s] then return false end
    -- Pieces of a line put together at run time, and patterns.
    if s:find("^%^") or s:find("^ %{1%}$") or s:find("^OUR {1} ") and not s:find("[^ ]$") then return false end
    if s == "OUR {1} IS NOW " then return false end
    if s:find("{%d") then return true end
    -- Capitals, two or more together, and nothing in small letters but a
    -- line's "what it is|" (src/lang.lua).
    local body = s:gsub("^%l+|", "")
    if not body:find("%u%u") then return false end
    if body:find("%l") then return false end
    return true
end

-- How a unit dies, as the cataclysms say it ("WAS LOST TO THE SEA"): the
-- literals in calls that hand it to Cat.hurt.
local function hows(src)
    local out = {}
    for line in src:gmatch("[^\n]+") do
        local code = line:gsub("%-%-.*$", "")
        if code:find("hurt%(") or code:find("strand%(") or code:find("strandAll%(") or code:find("clear%(game") then
            for s in code:gmatch('"([^"]*)"') do
                if wordy(s) then out[#out + 1] = s end
            end
        end
    end
    return out
end

-- The lines made at run time from parts.
local function derived(add)
    local D = require "src.defs"
    for _, r in ipairs(D.RANKS) do
        add(r.name .. " {1}")
        add("OUR {1} IS NOW " .. r.name)
    end
    for _, b in pairs(D.BUILDINGS) do add("short|" .. b.short) end
    add("short|QUART.")
    for _, f in pairs(D.FOCUS) do add("short|" .. f.short) end
    for _, t in ipairs({ "DISPLAY", "INTERFACE", "AUDIO", "GAMEPLAY", "CONTROLS" }) do add(t) end
    -- Settings whose choices read as their names in capitals, and the sound's
    -- levels (src/ui/audio.lua).
    for _, s in ipairs({ "WINDOWED", "BORDERLESS", "FULLSCREEN", "DIAL", "ARC", "STRIP", "SCENE", "AUTO",
        "LOUD", "SOFT" }) do add(s) end

    -- The keys' names (src/settings.lua's NAMES).
    for _, k in ipairs({ "ENTER", "PAD ENTER", "SPACE", "TAB", "END", "HOME", "PG UP", "PG DN", "BKSP", "DEL", "INS",
        "L SHIFT", "R SHIFT", "L CTRL", "R CTRL", "L ALT", "R ALT" }) do add(k) end
end

-- Every line, as a set and in the order found.
function Keys.all()
    local set, list = {}, {}
    local function add(s)
        if not set[s] then set[s] = true list[#list + 1] = s end
    end
    for _, p in ipairs(files()) do
        local src = read(p)
        for _, s in ipairs(literals(src)) do
            if wordy(s) then add(s) end
        end
        for _, h in ipairs(hows(src)) do add("OUR {1} " .. h) end
    end
    derived(add)
    return set, list
end

-- The lines language `code`'s table hasn't.
function Keys.missing(code)
    local t = assert(require("src.lang").table(code), "no table for " .. code)
    local _, list = Keys.all()
    local out = {}
    for _, s in ipairs(list) do
        if t.words[s] == nil and not (t.same and t.same[s]) then out[#out + 1] = s end
    end
    return out
end

if arg and arg[0] and arg[0]:match("lang_keys%.lua$") then
    local list
    if arg[1] then list = Keys.missing(arg[1]) else list = select(2, Keys.all()) end
    for _, s in ipairs(list) do print(s) end
    io.stderr:write(#list .. "\n")
end

return Keys
