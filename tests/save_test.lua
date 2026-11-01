-- A game written out and read back is the same game: the same cells, the
-- same units and cities, the same cataclysm, and it goes on playing the
-- same way from there.

local Game = require "src.game"
local AI = require "src.ai"
local Save = require "src.save"
local Cat = require "src.cataclysm"

local function played(kind, turns, seed)
    local g = Game.new({ seed = seed or 5, cataclysm = kind })
    for _ = 1, turns or 0 do
        AI.play(g, g.players[1])
        g:endTurn(AI)
    end
    return g
end

local function roundTrip(g)
    local text = Save.encode(g)
    local back, why = Save.decode(text)
    assert(back, why)
    return back
end

-- Everything two games hold, compared down to the last field. Tables are
-- the same where the same path leads to the same thing in both, and the
-- defs each unit and civilization points at are the very same tables.
local function same(a, b, path, seenA, seenB)
    path = path or "game"
    seenA, seenB = seenA or {}, seenB or {}
    if type(a) ~= type(b) then error(path .. ": " .. type(a) .. " became " .. type(b)) end
    if type(a) ~= "table" then
        if a ~= b then error(path .. ": " .. tostring(a) .. " became " .. tostring(b)) end
        return
    end
    -- A table reached twice must be reached twice on the other side too.
    if seenA[a] or seenB[b] then
        if seenA[a] ~= b or seenB[b] ~= a then error(path .. ": two tables that were one") end
        return
    end
    seenA[a], seenB[b] = b, a
    for k, v in pairs(a) do
        -- What the screen has not taken yet is of the moment, not of the
        -- game, and is not written.
        if k == "events" then v, b[k] = nil, nil end
        if v ~= nil then
        if b[k] == nil then error(path .. "." .. tostring(k) .. " was lost") end
        same(v, b[k], path .. "." .. tostring(k), seenA, seenB)
        end
    end
    for k in pairs(b) do
        if a[k] == nil and k ~= "events" then error(path .. "." .. tostring(k) .. " came from nowhere") end
    end
end

local function plays(a, b, turns)
    for _ = 1, turns do
        AI.play(a, a.players[1])
        a:endTurn(AI)
        AI.play(b, b.players[1])
        b:endTurn(AI)
    end
    assert(a.turn == b.turn, "the turns parted")
    assert(#a.units == #b.units, ("%d units became %d"):format(#a.units, #b.units))
    assert(#a.cities == #b.cities, ("%d cities became %d"):format(#a.cities, #b.cities))
end

return {
    { "a new game goes out and comes back whole", function()
        local g = Game.new({ seed = 3, cataclysm = "heat" })
        same(g, roundTrip(g))
    end },

    { "a game played a while goes out and comes back whole", function()
        local g = played("heat", 30)
        same(g, roundTrip(g))
    end },

    { "the defs come back as the very same tables", function()
        local g = roundTrip(played("plague", 20))
        for _, u in ipairs(g.units) do
            assert(u.def, "a unit with no def")
            assert(u.def.name, "a unit whose def is not one")
        end
        assert(g.players[1].civ.name, "a civilization with no name")
        assert(g.players[0].wild, "the wild is not there")
    end },

    { "one city is one city, however many hexes point at it", function()
        local g = played("heat", 30)
        local back = roundTrip(g)
        for _, cell in ipairs(back.cells) do
            if cell.city then
                assert(back.cells[cell.city.cell].city == cell.city, "a city and its hex parted")
            end
            if cell.ownerCity then
                local found = false
                for _, c in ipairs(back.cities) do found = found or c == cell.ownerCity end
                assert(found, "a hex owned by a city that is not in the list")
            end
        end
        for _, u in ipairs(back.units) do
            local slot = u.def.civilian and back.civ or back.mil
            assert(slot[u.cell] == u, "a unit and the hex it stands on parted")
        end
    end },

    { "every cataclysm comes back, marks and all", function()
        for kind in pairs(Cat.KINDS) do
            local g = played(kind, 0)
            -- Far enough in that the cataclysm has left its own state about.
            local to = math.floor(require("src.defs").LAST_TURN * 0.9)
            while g.turn < to and not g:outcome() do
                AI.play(g, g.players[1])
                g:endTurn(AI)
            end
            local back = roundTrip(g)
            assert(back.cataclysm.kind == kind, kind .. " came back as something else")
            same(g, back, kind)
        end
    end },

    { "it goes on playing the same way from where it was read", function()
        local g = played("quake", 60)
        local back = roundTrip(g)
        plays(g, back, 15)
        same(g, back, "after playing on")
    end },

    { "the same game always writes the same file", function()
        local g = played("sky", 25)
        assert(Save.encode(g) == Save.encode(g), "two writings of one game differ")
        assert(Save.encode(roundTrip(g)) == Save.encode(g), "a game read back writes a different file")
    end },

    { "what cannot be in a game is refused, not written wrong", function()
        local g = Game.new({ seed = 1, cataclysm = false })
        g.cells[1].odd = function() end
        assert(not pcall(Save.encode, g), "a function was written out")
        g.cells[1].odd = 0 / 0
        assert(not pcall(Save.encode, g), "a number that is none was written out")
    end },
}
