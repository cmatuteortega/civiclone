-- The overlay laid only where it changed (src/ui/pixels.lua, P.finish) must
-- come out byte for byte as it would laid whole. Two of the module side by
-- side, the same asks each frame: one keeping what it can from the frame
-- before, the other laying all of it every frame. No LÖVE.

local ffi = require "ffi"
local T = require "src.tracer"
local S = require "src.ui.state"

-- A picture of w by h with holes, depths and, if `windows`, windows.
local function picture(w, h, seed, windows)
    local n = w * h
    local key, dep = ffi.new("uint8_t[?]", n), ffi.new("float[?]", n)
    local win = windows and ffi.new("uint8_t[?]", n) or nil
    for q = 0, n - 1 do
        local r = (q * 7919 + seed * 104729) % 97
        key[q] = r < 20 and 0 or (r % 8) + 1
        dep[q] = (r % 13) - 6
        if win then win[q] = r % 5 == 0 and 1 or 0 end
    end
    return { w = w, h = h, oi = math.floor(w / 2), oj = h - 1, key = key, dep = dep, win = win }
end

-- A board picture: no tracer, a pixel of the room a pixel of it.
local function board(w, h)
    local dep = ffi.new("float[?]", w * h)
    for q = 0, w * h - 1 do dep[q] = ((q * 31) % 23) - 11 end
    return { w = w, h = h, dep = dep, version = 0, toImage = function(_, x, y, z) return x, y, z end }
end

-- What frame `f` asks of pixels module P: much the same every frame, a few
-- things moving or blinking, near the top.
local pics
local function ask(P, f)
    for k = 1, 30 do
        P.stamp(pics[k % #pics + 1], (k * 37) % 180, (k * 53) % 130, (k % 9) - 4,
            k % 7 == 0 and T.FLASH or nil, k % 5 == 0 and 0.4 or nil)
    end
    -- One walking across, one seen through the trees, one blinking.
    P.stamp(pics[1], 10 + f % 160, 20, 2)
    P.stampThrough(pics[2], 90, 15 + (f * 3) % 25, (f % 11) - 5, f % 4 == 0 and T.FLASH or nil)
    if f % 6 < 3 then P.stamp(pics[3], 140, 30, 0) end
    -- Lines of pixels, still and moving, and marks on the water under them.
    for x = 0, 120 do P.putS((x % 8) + 1, x, 40 + (x % 3)) end
    for k = 0, 40 do P.putS(((k + f) % 8) + 1, (k * 13 + f * 5) % 200, (k * 7 + f) % 40, k % 3 == 0 and 250 or nil) end
    for k = 0, 60 do P.liftS(1 + (k + f) % 2, (k * 11) % 200, 70 + (k % 9)) end
    -- Some off the canvas, which are dropped.
    P.putS(3, -1, 5) P.putS(3, 5, 9999) P.liftS(1, -4, -4)
end

return {
    { "the overlay laid where it changed is the overlay laid whole", function()
        local was = { S.world, S.cw, S.ch, S.opx, S.overlay, S.camx, S.camy }
        local A = dofile("src/ui/pixels.lua")
        local B = dofile("src/ui/pixels.lua")
        pics = { picture(9, 14, 1, true), picture(12, 8, 2), picture(5, 5, 3), picture(20, 17, 4, true) }
        S.world = board(220, 170)
        S.cw, S.ch = 200, 150
        local n = S.cw * S.ch * 4
        local bufA, bufB = ffi.new("uint8_t[?]", n), ffi.new("uint8_t[?]", n)
        local imgA, imgB = {}, {}
        S.camx, S.camy = 3, 2
        local partial = 0
        for f = 1, 300 do
            -- Now and then the camera moves, or the board is traced again.
            if f % 50 == 0 then S.camx = S.camx + 1 end
            if f % 70 == 0 then S.world.version = S.world.version + 1 end
            S.opx, S.overlay = bufA, imgA
            A.begin() ask(A, f)
            local _, y0, _, y1 = A.finish()
            if y0 and (y1 - y0 + 1) < S.ch then partial = partial + 1 end
            S.opx, S.overlay = bufB, imgB
            B.begin() ask(B, f)
            B.finish(true)
            for q = 0, n - 1 do
                if bufA[q] ~= bufB[q] then
                    error(("frame %d: byte %d is %d laid where it changed, %d laid whole"):format(f, q, bufA[q], bufB[q]))
                end
            end
        end
        assert(partial > 100, "most frames should lay only some of the overlay again")
        S.world, S.cw, S.ch, S.opx, S.overlay, S.camx, S.camy = was[1], was[2], was[3], was[4], was[5], was[6], was[7]
    end },
}
