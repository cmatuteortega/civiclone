-- The clock: each turn of the day has its own name. No LÖVE: names only.

local Daylight = require "src.ui.daylight"
local Clock = require "src.ui.clock"

local function check(ok, what) if not ok then error(what, 2) end end

return {
    { "each turn of a day is called by its own name", function()
        local want = { "NOON", "AFTERNOON", "SUNSET", "DUSK", "MIDNIGHT", "DAWN", "MORNING", "LATE MORNING" }
        for k, hr in ipairs(Daylight.HOURS) do
            check(Clock.name(hr) == want[k], ("turn %d of the day (%.3f) is %s, not %s"):format(k, hr, Clock.name(hr), want[k]))
        end
    end },
}
