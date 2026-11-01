-- The map's picture laid again only where it has changed (World:build after
-- World:refreshAll, and as the player's sight changes) must come out as it
-- would laid whole. No LÖVE: its pictures are stood in for by plain memory.

local ffi = require "ffi"
local Game = require "src.game"
local AI = require "src.ai"
local Cat = require "src.cataclysm"
local D = require "src.defs"

local function stub()
    local was = love
    love = {
        image = { newImageData = function(w, h)
            local buf = ffi.new("uint8_t[?]", w * h * 4)
            return { getFFIPointer = function() return buf end, release = function() end }
        end },
        graphics = { newImage = function() return { setFilter = function() end, replacePixels = function() end } end },
    }
    return function() love = was end
end

-- A small map some turns into the sky's falling, traced.
local function world()
    local World = require "src.world"
    local g = Game.new({ seed = 3, cols = 16, rows = 12, cataclysm = "sky" })
    while g.turn < D.SKY.bombard do
        AI.play(g, g.players[1])
        g:endTurn(AI)
    end
    for k = #g.events, 1, -1 do g.events[k] = nil end
    local w = World.new(g)
    w:paint()
    return g, w
end

-- Both pictures, as they are now.
local function snap(w)
    local n = w.w * w.h * 4
    local a, b = ffi.new("uint8_t[?]", n), ffi.new("uint8_t[?]", n)
    ffi.copy(a, w.px, n)
    ffi.copy(b, w.mpx, n)
    return a, b, n
end

-- Lays the whole picture again and says how many bytes differ from now.
local function differs(w, me, grid)
    local a, b, n = snap(w)
    w.shown = nil
    w:build(me.explored, me.visible, grid)
    local d = 0
    for i = 0, n - 1 do
        if a[i] ~= w.px[i] or b[i] ~= w.mpx[i] then d = d + 1 end
    end
    return d
end

return {
    { "the picture laid again where the land and the sight change is the picture laid whole", function()
        local restore = stub()
        local ok, err = pcall(function()
            local g, w = world()
            local me = g.players[1]
            w:build(me.explored, me.visible, false)
            local changed = 0
            for _ = 1, 4 do
                -- Stones fall, craters cool, units walk: the land and the
                -- sight change.
                AI.play(g, me)
                g:endTurn(AI)
                local ids, seen = {}, {}
                for _, e in ipairs(g.events) do
                    if e.kind == "terrain" and not seen[e.cell] then
                        seen[e.cell] = true
                        ids[#ids + 1] = e.cell
                    end
                end
                for k = #g.events, 1, -1 do g.events[k] = nil end
                changed = changed + #ids
                -- Some built now, the rest a few at a time.
                w:queue(ids)
                w:work(0)
                while w:busy() do w:work(0) end
                w:build(me.explored, me.visible, false)
                assert(differs(w, me, false) == 0, "laid again after turn " .. g.turn)
            end
            assert(changed > 0, "the land changed")
            -- A craterless hex struck: built again, and its old solids gone
            -- from every bin.
            local cell
            for _, c in ipairs(g.cells) do
                if not g:isWater(c) and not c.city and not c.crater then cell = c break end
            end
            require("src.skyfall").crater(g, cell, 2)
            w:refreshAll({ cell.id })
            w:build(me.explored, me.visible, false)
            assert(differs(w, me, false) == 0, "laid again after a crater")
            for _, list in ipairs(w.bins) do
                for _, s in ipairs(list) do assert(not s.dead, "a dead solid left in a bin") end
            end
            -- The sight changing: hexes seen and lost.
            local n = 0
            for id = 1, #g.cells, 5 do
                if me.explored[id] then
                    me.visible[id] = not me.visible[id] or nil
                    n = n + 1
                end
            end
            assert(n > 0)
            w:build(me.explored, me.visible, false)
            assert(differs(w, me, false) == 0, "laid again as the sight changed")
            -- The grid on and off.
            w:build(me.explored, me.visible, true)
            assert(differs(w, me, true) == 0, "laid again with the grid")
            assert(Cat.is(g, "sky"))
        end)
        restore()
        if not ok then error(err, 0) end
    end },
}
