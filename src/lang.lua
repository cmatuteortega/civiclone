-- The words on the screen in the player's language. English is written in
-- the code as it is shown; every other language is a table from those
-- English lines to its own (src/locale/<code>.lua). So a line is its own key,
-- and one with nothing in the table is shown in English rather than not at
-- all.
--
--   local L = require "src.lang"
--   L"NEW GAME"                         --> "PARTIDA NUEVA"
--   L("{1} WAS FOUNDED", city.name)     --> "SE FUNDÓ AURUM"
--
-- What goes into a line ({1}, {2}, ...) is looked up too, so a unit's or a
-- building's name comes out in the same language as the line around it; a
-- name the table hasn't (a city's, a number) comes out as it is. A line may
-- agree with what goes into it: {1:O/A} is "O" if the word put in for {1} is
-- masculine and "A" if feminine, as the language's table says (`fem`).
--
-- No LÖVE here: the rules (src/game.lua and the cataclysms) word their news
-- with it too, and the tests run without LÖVE.

local Lang = {}

-- The languages, in the order the setting goes round them, each with its
-- name as it is written in itself.
Lang.LIST = { "en", "es" }
Lang.NAMES = { en = "ENGLISH", es = "ESPAÑOL" }

local code, words, fem = "en", nil, nil
local loaded = {}

local function load(c)
    if c == "en" then return nil end
    if loaded[c] == nil then
        local ok, t = pcall(require, "src.locale." .. c)
        loaded[c] = ok and t or false
    end
    return loaded[c] or nil
end

-- Sets the language by its code ("en", "es"); one there's no table for is
-- English.
function Lang.set(c)
    local t = load(c)
    if c ~= "en" and not t then c = "en" end
    code = c
    words = t and t.words
    fem = t and t.fem or {}
end

function Lang.get() return code end

-- The table of a language, for the tests.
function Lang.table(c) return load(c) end

-- One word or line, in the language now; as it is where there's none. A
-- line may start with what it is, in small letters and a bar ("short|FOOD",
-- the focus's button, not the yield), where the same English is two things
-- in another language; that part is never shown.
local function word(s)
    if type(s) ~= "string" then return s end
    local out = words and words[s] or s
    if out:find("|", 1, true) then out = out:gsub("^%l+|", "") end
    return out
end

Lang.word = word

-- `s` in the language now, with what goes into it.
local function tr(s, ...)
    if s == nil then return nil end
    local out = word(s)
    local n = select("#", ...)
    if n == 0 then return out end
    local args = { ... }
    for i = 1, n do
        local a = args[i]
        if type(a) == "number" then args[i] = tostring(a)
        elseif type(a) == "string" then args[i] = word(a)
        else args[i] = tostring(a) end
    end
    out = out:gsub("{(%d+):([^/}]*)/([^}]*)}", function(i, m, f)
        local a = args[tonumber(i)]
        return (a and fem and fem[a]) and f or m
    end)
    out = out:gsub("{(%d+)}", function(i) return args[tonumber(i)] or "" end)
    return out
end


return setmetatable(Lang, { __call = function(_, s, ...) return tr(s, ...) end })
