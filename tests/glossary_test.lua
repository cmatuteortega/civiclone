-- The glossary (src/glossary.lua): a page for everything the game names,
-- and the page a tooltip opens for a hex.

local Glossary = require "src.glossary"
local Game = require "src.game"
local D = require "src.defs"
local L = require "src.lang"

return {
    { "every page has a name, a kind listed, and lines", function()
        local kinds = {}
        for _, k in ipairs(Glossary.KINDS) do kinds[k.id] = true end
        for _, p in ipairs(Glossary.pages) do
            assert(kinds[p.kind], p.id .. ": its kind is not listed")
            assert(Glossary.name(p.id) ~= "", p.id .. ": no name")
            local lines = Glossary.lines(p.id)
            assert(#lines > 0, p.id .. ": no lines")
            for _, l in ipairs(lines) do assert(type(l) == "string" and l ~= "", p.id .. ": an empty line") end
        end
    end },
    { "every technology, building, form and beast has a page", function()
        for _, t in ipairs(D.TECHS) do assert(Glossary.get("tech." .. t.id), t.id) end
        for id in pairs(D.BUILDINGS) do assert(Glossary.get("building." .. id), id) end
        for id in pairs(D.FORMS) do assert(Glossary.forUnit(id), id) end
        for id in pairs(D.BEASTS) do assert(Glossary.forUnit(id), id) end
        assert(Glossary.forUnit("settler") and Glossary.forUnit("builder"))
    end },
    { "a unit's page has its numbers as the rules put them together", function()
        L.set("en")
        local lines = table.concat(Glossary.lines("unit.horsearcher"), "\n")
        local def = D.unitDef("band", { weapon = "bow", mount = "horse" })
        assert(lines:find(("STRENGTH %d, MOVES %d"):format(def.str, def.moves), 1, true), lines)
        assert(lines:find(("COSTS %d PRODUCTION"):format(def.cost), 1, true), lines)
    end },
    { "every hex of a map opens a page, whatever is on it", function()
        local g = Game.new({ seed = 7 })
        local me = g.players[1]
        for _, cell in ipairs(g.cells) do
            local id = Glossary.forCell(g, cell, me)
            assert(id and Glossary.get(id), "no page for hex " .. cell.id)
        end
        -- What stands on a hex comes before the land under it.
        local u = g:unitsOf(1)[1]
        for id in pairs(me.visible) do me.visible[id] = nil end
        me.visible[u.cell] = true
        -- The soldier, if one shares the hex.
        local top = g.mil[u.cell] or g.civ[u.cell]
        assert(Glossary.forCell(g, g.cells[u.cell], me) == Glossary.forUnit(top.kind))
    end },
    { "the pages read in Spanish too", function()
        L.set("es")
        local ok, err = pcall(function()
            for _, p in ipairs(Glossary.pages) do Glossary.lines(p.id) end
            assert(Glossary.name("yield.food") == "COMIDA")
        end)
        L.set("en")
        assert(ok, err)
    end },
}
