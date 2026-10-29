-- Dice and noise that need nothing of LÖVE, so a map made from a seed is the
-- same map under the tests as in the game.

local floor = math.floor

local Rng = {}
Rng.__index = Rng

-- Park and Miller's minimal standard generator: small, and exact in doubles.
function Rng.new(seed)
    local s = floor(seed or 1) % 2147483646 + 1
    return setmetatable({ s = s }, Rng)
end

-- As math.random: nothing for [0, 1), one number for 1..n, two for a..b.
function Rng:random(a, b)
    self.s = self.s * 16807 % 2147483647
    local f = (self.s - 1) / 2147483646
    if not a then return f end
    if not b then return floor(f * a) + 1 end
    return floor(f * (b - a + 1)) + a
end

function Rng:pick(list) return list[self:random(#list)] end

-- Value noise: a lattice of random heights, smoothly joined, summed over a
-- few octaves. Answers 0..1.
function Rng.noise(seed)
    local function lattice(x, y, o)
        local n = math.sin(x * 127.1 + y * 311.7 + o * 74.7 + seed * 0.001) * 43758.5453
        return n - floor(n)
    end
    local function smooth(t) return t * t * (3 - 2 * t) end
    local function value(x, y, o)
        local x0, y0 = floor(x), floor(y)
        local fx, fy = smooth(x - x0), smooth(y - y0)
        local a, b = lattice(x0, y0, o), lattice(x0 + 1, y0, o)
        local c, d = lattice(x0, y0 + 1, o), lattice(x0 + 1, y0 + 1, o)
        return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
    end
    return function(x, y, octaves)
        local sum, amp, total, f = 0, 1, 0, 1
        for o = 1, octaves or 4 do
            sum = sum + value(x * f, y * f, o) * amp
            total = total + amp
            amp, f = amp * 0.5, f * 2
        end
        return sum / total
    end
end

return Rng
