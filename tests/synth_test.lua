-- The sounds: every effect, loop and layer of the music renders, is never
-- silent and never more than full scale, and the layers of the music are all
-- exactly as long as each other, so that they loop in step.

local Synth = require "src.synth"

local abs, floor = math.abs, math.floor

local function check(name)
    local out, n = Synth.render(Synth.def(name))
    assert(n > 0, name)
    local peak = 0
    for i = 0, n - 1 do
        local s = out[i]
        assert(s == s, name .. ": not a number at " .. i)
        peak = math.max(peak, abs(s))
    end
    assert(peak > 0.1, name .. ": silent")
    assert(peak <= 1, name .. ": past full scale")
    return n
end

local function names(t)
    local list = {}
    for name in pairs(t) do list[#list + 1] = name end
    table.sort(list)
    return list
end

return {
    { "every effect renders", function()
        for _, name in ipairs(names(Synth.DEFS)) do
            assert(check(name) < Synth.RATE * 6, name .. ": too long for an effect")
        end
    end },
    { "every loop renders, a whole number of its slow swells long", function()
        for _, name in ipairs(names(Synth.LOOPS)) do
            local def = Synth.LOOPS[name]
            local n = check(name)
            assert(n == floor(def.len * Synth.RATE) - floor(def.loop * Synth.RATE)
                or n == floor((def.len + def.loop) * Synth.RATE) - floor(def.loop * Synth.RATE), name)
        end
    end },
    { "the layers of the music are all one length", function()
        for k = 0, #Synth.LAYERS do
            assert(check(k) == Synth.LENGTH * Synth.RATE, "layer " .. k)
        end
    end },
    { "the same sound renders the same each time", function()
        local a, n = Synth.render(Synth.def("sea"))
        local b = Synth.render(Synth.def("sea"))
        for i = 0, n - 1, 97 do assert(a[i] == b[i]) end
    end },
}
