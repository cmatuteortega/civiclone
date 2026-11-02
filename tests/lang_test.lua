-- The words in other languages (src/lang.lua, src/locale/).

local L = require "src.lang"
local Font = require "src.font"
local Keys = dofile("tools/lang_keys.lua")

local function placeholders(s)
    local out = {}
    for n in s:gmatch("{(%d+)") do out[n] = true end
    return out
end

-- Runs `fn` in language `code`, and back to English after, come what may.
local function inLang(code, fn)
    L.set(code)
    local ok, err = pcall(fn)
    L.set("en")
    if not ok then error(err, 0) end
end

local tests = {
    { "English is the code's own words, with what goes into them", function()
        L.set("en")
        assert(L"NEW GAME" == "NEW GAME")
        assert(L("{1} WAS FOUNDED", "AURUM") == "AURUM WAS FOUNDED")
        assert(L("civ|{1} {2}", "UMBRA", "WARRIOR") == "UMBRA WARRIOR", "the part before the bar is never shown")
        assert(L("MOVES {1}/{2}", 2, 3) == "MOVES 2/3")
        assert(L("A LINE NO TABLE HAS") == "A LINE NO TABLE HAS")
    end },
    { "a language there's no table for is English", function()
        L.set("xx")
        assert(L.get() == "en" and L"NEW GAME" == "NEW GAME")
    end },
    { "Spanish: lines, what goes into them, and agreeing with it", function()
        inLang("es", function()
            assert(L"NEW GAME" == "NUEVA PARTIDA")
            assert(L("{1} WAS FOUNDED", "AURUM") == "SE HA FUNDADO AURUM", "a city's name stays as it is")
            assert(L("civ|{1} {2}", "UMBRA", "WARRIOR") == "GUERRERO DE UMBRA", "and the order is the language's")
            assert(L("OUR {1} WAS KILLED", "WARRIOR") == "HAN MATADO A NUESTRO GUERRERO")
            assert(L("OUR {1} WAS KILLED", "GALLEY") == "HAN MATADO A NUESTRA GALERA", "agrees with a feminine word")
            assert(L("{1} BUILT A {2}", "AURUM", "LIBRARY") == "AURUM HA CONSTRUIDO UNA BIBLIOTECA")
            assert(L("{1} BUILT A {2}", "AURUM", "GRANARY") == "AURUM HA CONSTRUIDO UN GRANERO")
            assert(L("VETERAN {1}", "SPEARMAN") == "PIQUERO VETERANO")
            assert(L"act|SHUT" == "CERRAR" and L"SHUT" == "CERRADA", "one English word, two Spanish")
            assert(L(L"NEW GAME") == "NUEVA PARTIDA", "a line in the language already stays")
            assert(L("A LINE NO TABLE HAS") == "A LINE NO TABLE HAS", "a line it hasn't is shown in English")
        end)
    end },
}

for _, code in ipairs(L.LIST) do
    if code ~= "en" then
        local t = L.table(code)
        tests[#tests + 1] = { code .. ": every line the game shows is in the table", function()
            local missing = Keys.missing(code)
            assert(#missing == 0, #missing .. " missing, the first: " .. tostring(missing[1]))
        end }
        tests[#tests + 1] = { code .. ": looking a line up again changes nothing", function()
            -- Draw.text looks up whatever it is given, translated or not.
            for en, s in pairs(t.words) do
                local again = t.words[s]
                assert(again == nil or again == s, ("%q -> %q -> %q"):format(en, s, tostring(again)))
            end
        end }
        tests[#tests + 1] = { code .. ": every letter is in the font", function()
            for _, s in pairs(t.words) do
                for ch in s:gsub("{[^}]*}", ""):gmatch(Font.CHAR) do
                    assert(Font.has(ch), ("no %q in the font, in %q"):format(ch, s))
                end
            end
        end }
        tests[#tests + 1] = { code .. ": what goes into a line goes in, and nothing else", function()
            for en, s in pairs(t.words) do
                local want, got = placeholders(en), placeholders(s)
                for n in pairs(got) do assert(want[n], ("{%s} in %q, not in %q"):format(n, s, en)) end
                for n in pairs(want) do assert(got[n], ("{%s} of %q left out of %q"):format(n, en, s)) end
            end
        end }
        tests[#tests + 1] = { code .. ": the names of places and peoples are no one's words", function()
            local D = require "src.defs"
            for _, r in ipairs(D.RIVERS) do assert(not t.words[r], r) end
            for _, c in ipairs(D.CIVS) do
                assert(not t.words[c.name], c.name)
                for _, n in ipairs(c.cities) do assert(not t.words[n], n) end
            end
        end }
    end
end

-- Every cataclysm played to its end in Spanish, the computer on every side:
-- its news is all in Spanish, and all of it put together.
tests[#tests + 1] = { "es: whole games' news, every cataclysm", function()
    local Game = require "src.game"
    local AI = require "src.ai"
    local D = require "src.defs"
    local Cat = require "src.cataclysm"
    local words = L.table("es").words
    inLang("es", function()
        for kind in pairs(Cat.KINDS) do
            local g = Game.new({ seed = 3, allAI = true, cataclysm = kind })
            while g.turn <= D.LAST_TURN do
                AI.play(g, g.players[1])
                g:endTurn(AI)
            end
            assert(g.turn > D.LAST_TURN)
            for _, m in ipairs(g.log) do
                assert(not m.text:find("{%d"), kind .. ": not put together: " .. m.text)
                assert(not words[m.text], kind .. ": left in English: " .. m.text)
                -- A line put together from parts left in English shows its
                -- little words.
                local padded = " " .. m.text .. " "
                for _, w in ipairs({ " THE ", " WAS ", " HAS ", " OUR ", " IS ", " OF ", " AND " }) do
                    assert(not padded:find(w, 1, true), kind .. ": English in: " .. m.text)
                end

            end
            -- And the hover's words for every hex.
            for _, cell in ipairs(g.cells) do
                local s = g:describe(cell)
                for part in s:gmatch("[^ ]+") do assert(not part:find("{%d"), s) end
            end
        end
    end)
end }

return tests
