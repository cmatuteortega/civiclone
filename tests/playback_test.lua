-- The others' turn played back a part at a time (src/ui/playback.lua): the
-- rules mark where each part begins, in order, and the playback lets each
-- player's units move only once their part has come.

local Game = require "src.game"
local AI = require "src.ai"
local Settings = require "src.settings"
local Play = require "src.ui.playback"

return {
    { "the turn is marked where each civilization, the wild and the cataclysm begin", function()
        local g = Game.new({ seed = 4, cataclysm = "sky" })
        AI.play(g, g.players[1])
        for k = #g.events, 1, -1 do g.events[k] = nil end
        g:endTurn(AI)
        local order = {}
        for _, e in ipairs(g.events) do
            if e.kind == "phase" then order[#order + 1] = tostring(e.who) end
        end
        local want = {}
        for k = 2, #g.players do want[#want + 1] = tostring(k) end
        want[#want + 1] = tostring(Game.WILD)
        want[#want + 1] = "cataclysm"
        assert(table.concat(order, ",") == table.concat(want, ","), table.concat(order, ","))
    end },
    { "units move on the screen only once their part has come", function()
        Settings.reset()
        Play.start()
        assert(Play.active())
        assert(Play.released(1), "the player's own move at once")
        assert(not Play.released(2) and not Play.released(Game.WILD))
        Play.begin(2)
        assert(Play.released(2) and not Play.released(3))
        -- A part waits for what it started, then a moment if it was seen.
        Play.saw()
        Play.update(0.1, true)
        assert(not Play.done(true))
        Play.update(0.05, false)
        assert(not Play.done(false), "a moment after what was seen")
        Play.update(Play.BEAT, false)
        assert(Play.done(false))
        -- Nothing seen: on at once. Never held longer than LONGEST.
        Play.begin(3)
        assert(Play.done(false))
        Play.update(Play.LONGEST, true)
        assert(Play.done(true))
        Play.begin("cataclysm")
        assert(Play.released(Game.WILD) and Play.released(99), "everyone moves in the cataclysm's part")
        Play.stop()
        assert(not Play.active() and Play.released(3))
    end },
    { "quick turns play nothing back", function()
        Settings.reset()
        Settings.set("quickTurns", true)
        Play.start()
        assert(not Play.active() and Play.released(2))
        Settings.reset()
    end },
}
