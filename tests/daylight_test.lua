-- Day and night: the hour each turn is played at, the sun's way across the
-- sky, and how dark it gets. No LÖVE: only the numbers the shaders are sent.

local Daylight = require "src.ui.daylight"

local function check(ok, what) if not ok then error(what, 2) end end

-- The kind of light at each turn of the first day.
local function light(turn) return Daylight.at(Daylight.hourOf(turn)) end

return {
    { "the clock only goes forward", function()
        local last = -1
        for turn = 1, 40 do
            local h = Daylight.hourOf(turn)
            check(h > last, "turn " .. turn .. " is not later than the one before")
            last = h
        end
        check(Daylight.hourOf(1 + #Daylight.HOURS) == Daylight.hourOf(1) + 1, "a day is not a whole day later")
    end },

    { "mostly day, one turn of deep night", function()
        local day, dark = 0, 0
        for turn = 1, #Daylight.HOURS do
            local a = light(turn)
            if a.exposure > -0.01 then day = day + 1 end
            if a.night > 0.99 then dark = dark + 1 end
        end
        check(day >= 4, "fewer than half the turns are in daylight")
        check(dark == 1, "not one turn of deep night but " .. dark)
    end },

    { "the first turn is as the map was drawn", function()
        local a = light(1)
        check(a.exposure == 0 and a.night == 0 and a.golden == 0, "the first turn is not plain day")
        -- The sun on the same side as the tracer's lamp: west of south.
        check(a.sun[1] < 0 and a.sun[3] > 0, "the sun is not where the lamp is")
    end },

    { "the sun rises in the east and sets in the west", function()
        local x0, y0, _, e0 = Daylight.sun(0.27)
        local x1, _, _, e1 = Daylight.sun(0.73)
        local _, y2, _, e2 = Daylight.sun(0.5)
        local _, _, _, e3 = Daylight.sun(0)
        check(x0 > 0.8 and x1 < -0.8, "the sun is not east at dawn and west at evening")
        check(e2 > 0.99 and y2 > y0, "the sun is not high at noon")
        check(e0 > 0 and e1 > 0 and e3 < -0.99, "the sun's height is wrong")
    end },

    { "sunset is gold, midnight dark and moonlit", function()
        local sunset, midnight = Daylight.at(0.73), Daylight.at(0)
        check(sunset.golden > 0.5, "no gold at sunset")
        check(midnight.night == 1 and midnight.golden == 0, "midnight is not dark")
        check(midnight.exposure < -2, "midnight is not dark enough")
    end },

    { "the light shader's numbers", function()
        local u = Daylight.uniforms(0.7)
        -- A step towards the sun is a pixel along the way it moves most.
        check(math.abs(math.max(math.abs(u.march[1]), math.abs(u.march[2])) - 1) < 1e-9, "a step is not a pixel")
        check(u.reach > 60, "the low sun's shadows are short")
        for _, v in ipairs({ u.sun, u.sunHalf, u.moon, u.moonHalf, u.lamp0, u.half0 }) do
            check(math.abs(v[1] * v[1] + v[2] * v[2] + v[3] * v[3] - 1) < 1e-9, "a direction is not of length one")
        end
    end },
}
