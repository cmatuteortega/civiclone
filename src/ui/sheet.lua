-- Little patterns of lit pixels (the letters, the icons) drawn out of one
-- picture made once, a quad each, rather than as a box a pixel for every lit
-- pixel: the same pixels in the colour set, white in the picture times the
-- colour being the colour, but one draw for a letter instead of one for each
-- of its pixels, and LÖVE puts the draws of one picture together.

local Sheet = {}

local floor, max = math.floor, math.max

-- What is to be in the picture: by any key, the rows of a pattern ("#" lit),
-- how much of each row is read (w by h), and how many rows of it stand above
-- where it is drawn from.
local wanted, order = {}, {}
local image, quads

function Sheet.add(key, rows, w, h, top)
    if not wanted[key] then order[#order + 1] = key end
    wanted[key] = { rows = rows, w = w, h = h, top = top or 0 }
    image = nil
end

local function build()
    local cw, ch = 0, 0
    for _, key in ipairs(order) do
        cw, ch = max(cw, wanted[key].w), max(ch, wanted[key].h)
    end
    -- Side by side, a pixel apart.
    local W = max(1, #order * (cw + 1))
    local data = love.image.newImageData(W, ch)
    quads = {}
    for n, key in ipairs(order) do
        local p, x0 = wanted[key], (n - 1) * (cw + 1)
        for r = 1, p.h do
            local row = p.rows[r]
            for c = 1, p.w do
                if row:sub(c, c) == "#" then data:setPixel(x0 + c - 1, r - 1, 1, 1, 1, 1) end
            end
        end
        quads[key] = { love.graphics.newQuad(x0, 0, p.w, p.h, W, ch), p.top }
    end
    image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
end

-- Draws the pattern `key` in the colour set, its top left (below the rows
-- standing above) at (x, y), whole pixels. Answers whether there was one.
function Sheet.draw(key, x, y)
    if not image then build() end
    local q = quads[key]
    if not q then return false end
    love.graphics.draw(image, q[1], x, y - q[2])
    return true
end

return Sheet
