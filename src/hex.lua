-- Hex geometry: pointy-topped hexes in rows, every odd row pushed half a hex
-- east ("odd-r"), as Civilization lays its map out.
--
-- A cell is (c, r), column and row from 0. Distances and lines are worked in
-- cube coordinates, where a hex step is one along one of three axes.
--
-- In the room a hex is R units from its middle to a corner. Direction k
-- (0..5) is the neighbour across edge k: 0 east, then on round clockwise as
-- seen from above with z south -- 1 south-east, 2 south-west, 3 west,
-- 4 north-west, 5 north-east. Edge k's normal points at 60k degrees.

local sqrt, floor, abs, max = math.sqrt, math.floor, math.abs, math.max

local H = {}

H.R = 14
local R = H.R
local SQ3 = sqrt(3)
H.W = SQ3 * R      -- a hex across its flats
H.APOTHEM = H.W / 2
H.ROW = 1.5 * R    -- from one row's middles to the next's

-- The room point at the middle of cell (c, r).
function H.center(c, r)
    return H.W * (c + 0.5 * (r % 2)) + H.W / 2, H.ROW * r + R
end

-- The room size of a map of cols x rows.
function H.size(cols, rows)
    return H.W * (cols + 0.5), H.ROW * (rows - 1) + 2 * R
end

local ODD = {
    [0] = { { 1, 0 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 } },
    [1] = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, -1 } },
}

-- The neighbour of (c, r) in direction k (0..5).
function H.step(c, r, k)
    local o = ODD[r % 2][k + 1]
    return c + o[1], r + o[2]
end

-- Cube coordinates of a cell, and back.
function H.cube(c, r)
    local x = c - (r - r % 2) / 2
    return x, -x - r, r
end
function H.fromCube(x, _, z)
    return x + (z - z % 2) / 2, z
end

function H.distance(c0, r0, c1, r1)
    local x0, y0, z0 = H.cube(c0, r0)
    local x1, y1, z1 = H.cube(c1, r1)
    return max(abs(x0 - x1), abs(y0 - y1), abs(z0 - z1))
end

-- The cube nearest a fractional cube point.
local function round(x, y, z)
    local rx, ry, rz = floor(x + 0.5), floor(y + 0.5), floor(z + 0.5)
    local dx, dy, dz = abs(rx - x), abs(ry - y), abs(rz - z)
    if dx > dy and dx > dz then rx = -ry - rz
    elseif dy > dz then ry = -rx - rz
    else rz = -rx - ry end
    return rx, ry, rz
end

-- The cell a room point (x, z) is over.
function H.at(x, z)
    x, z = x - H.W / 2, z - R
    local q = (SQ3 / 3 * x - z / 3) / R
    local rr = (2 / 3 * z) / R
    return H.fromCube(round(q, -q - rr, rr))
end

-- How far a room point (x, z) is inside the edge of the hex centred at
-- (cx, cz): 0 on the edge, the apothem at the middle.
function H.inset(x, z, cx, cz)
    local dx, dz = abs(x - cx), abs(z - cz)
    -- Folded into one sixth: the east edge and the south-east one.
    local e = H.APOTHEM - dx
    local se = H.APOTHEM - (dx * 0.5 + dz * SQ3 / 2)
    return e < se and e or se
end

-- The six corners of a hex, from the one between edges 5 and 0 (north-east)
-- on round: edge k runs from corner k to corner k + 1 (as indices, k + 1 to
-- k + 2).
function H.corners(cx, cz)
    local out = {}
    for k = 0, 5 do
        local a = math.rad(60 * k - 30)
        out[k + 1] = { cx + R * math.cos(a), cz + R * math.sin(a) }
    end
    return out
end

-- Every cell within n steps of (c, r), itself first, nearest first.
function H.range(c, r, n)
    local out = {}
    local x0, y0, z0 = H.cube(c, r)
    for d = 0, n do
        for dx = -d, d do
            for dy = max(-d, -dx - d), math.min(d, -dx + d) do
                local dz = -dx - dy
                if max(abs(dx), abs(dy), abs(dz)) == d then
                    local cc, rr = H.fromCube(x0 + dx, y0 + dy, z0 + dz)
                    out[#out + 1] = { cc, rr }
                end
            end
        end
    end
    return out
end

-- The direction from (c0, r0) to its neighbour (c1, r1), or nil.
function H.dirTo(c0, r0, c1, r1)
    for k = 0, 5 do
        local c, r = H.step(c0, r0, k)
        if c == c1 and r == r1 then return k end
    end
end

return H
