-- Room for LuaJIT's compiled code, set once before the rest is loaded (by
-- main.lua, and by the tests and tools that trace the map).
--
-- LuaJIT keeps at most `maxtrace` compiled traces in `maxmcode` kilobytes of
-- machine code (1000 and 512 by default). The game outgrows that: the map's
-- tracer, the painting of models, the AI and every cataclysm's rules each
-- want their own traces. When the room is full LuaJIT throws every trace
-- away and starts again, so the hot loops spend most of their time being
-- recompiled or interpreted: tracing the map ran six times slower, and it
-- got worse the longer a game went on, as more of the rules came into play.

local ok, opt = pcall(require, "jit.opt")
if ok and jit and jit.status() then
    opt.start("maxtrace=10000", "maxmcode=32768")
end

return true
