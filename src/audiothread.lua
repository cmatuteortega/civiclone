-- The sound worker: renders every sound, loop and layer of the music it is
-- asked for (src/synth.lua) and hands the SoundData back, so the main thread
-- never waits on the synth.
require "love.filesystem"
require "love.sound"
local Synth = require "src.synth"

local jobs, done = love.thread.getChannel("synth.jobs"), love.thread.getChannel("synth.done")
while true do
    local name = jobs:demand()
    if name == "quit" then return end
    done:push({ name = name, data = Synth.make(name) })
end
