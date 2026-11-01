-- The turn played back a part at a time, as a strategy game does, rather than
-- all at once. The rules play the whole of the others' turn the moment the
-- player ends theirs (src/game.lua), and mark where each part begins with a
-- "phase" event: each civilization in turn, then the wild, then the
-- cataclysm. The screen takes the events up to the next mark
-- (src/ui/anim.lua), lets what they start finish (the walks, the blows, the
-- stones), waits a moment if anything was seen, and goes on to the next.
-- The player has their turn back then; the hour turns once the stones and
-- quakes it set going have played out too (src/ui/daylight.lua).
--
-- Whoever has not had their part yet stands where they stood: their units'
-- walks are held back until it comes. Units the player cannot see do not
-- walk at all; they are put where they end up.
--
-- With QUICK TURNS on (src/settings.lua), there are no parts: everything is
-- taken at once, and the others' units are put where they end up.
--
-- Nothing here draws or plays; it keeps where the playback is.

local S = require "src.ui.state"
local Settings = require "src.settings"

local Play = {}

-- The pause after a part in which something was seen, and the longest a
-- part may hold the next back, in seconds.
Play.BEAT = 0.2
Play.LONGEST = 4

local active = false
local released = {}   -- the players whose part has come
local after = false   -- the cataclysm's part has come: everyone may move
local clock = 0       -- seconds since this part began
local seen = false    -- something in this part was seen
local idle = 0        -- seconds since this part's last movement ended

-- Quick turns: no parts, and the others' units put where they end up.
function Play.quick()
    return Settings.get("quickTurns") == true
end

-- The player has ended their turn: what follows is played back. Not for
-- pictures taken unattended (--shot), which play it all at once as before.
function Play.start()
    active = not Play.quick() and S.plan == nil
    released, after = { [1] = true }, false
    clock, seen, idle = 0, false, 0
end

-- Being played back now?
function Play.active() return active end

-- All of it played back (or nothing to play): the hour may turn.
function Play.stop() active, after = false, false end

-- The part of player or step `who` ("cataclysm") begins.
function Play.begin(who)
    if who == "cataclysm" then after = true else released[who] = true end
    clock, seen, idle = 0, false, 0
end

-- Is the cataclysm still playing out on the screen (`calm` false)? The hour
-- does not turn while it is, nor while the turn is played back.
local calm = true
function Play.settle(c) calm = c end
function Play.holding() return active or not calm end

-- May the units of player `owner` move on the screen yet?
function Play.released(owner)
    return not active or after or released[owner] == true
end

-- Something in this part was seen: a walk, a blow.
function Play.saw() seen = true end

-- Time passing, and whether what this part started (`busy`) is still going.
function Play.update(dt, busy)
    if not active then return end
    clock = clock + dt
    if busy then idle = 0 else idle = idle + dt end
end

-- Has this part played out, so the next may begin?
function Play.done(busy)
    if clock >= Play.LONGEST then return true end
    if busy then return false end
    return not seen or idle >= Play.BEAT
end

return Play
