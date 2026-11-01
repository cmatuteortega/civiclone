-- The letters and icons drawn out of one picture (src/ui/sheet.lua) must
-- light the very pixels a box for each lit pixel would. No LÖVE: its
-- drawing is stood in for by a set of the pixels lit.

local ffi = require "ffi"

-- A love.graphics that notes which pixels a 1x1 box or a quad of the
-- picture lights, white over nothing being lit.
local function stub(lit)
    local was = love
    local function data(w, h)
        local buf = ffi.new("uint8_t[?]", w * h * 4)
        return { w = w, h = h, buf = buf,
            setPixel = function(_, x, y, r, g, b, a) buf[(y * w + x) * 4 + 3] = a > 0 and 255 or 0 end }
    end
    love = {
        image = { newImageData = data },
        graphics = {
            newImage = function(d) return { d = d, setFilter = function() end } end,
            newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
            rectangle = function(mode, x, y, w, h)
                assert(mode == "fill" and w == 1 and h == 1)
                lit[#lit + 1] = x .. "," .. y
            end,
            draw = function(img, q, x, y)
                local d = img.d
                for v = 0, q.h - 1 do
                    for u = 0, q.w - 1 do
                        if d.buf[((q.y + v) * d.w + q.x + u) * 4 + 3] > 0 then lit[#lit + 1] = (x + u) .. "," .. (y + v) end
                    end
                end
            end,
            setColor = function() end,
        },
    }
    return function() love = was end
end

local function same(a, b)
    table.sort(a)
    table.sort(b)
    return table.concat(a, " ") == table.concat(b, " ")
end

return {
    { "every letter from the picture is the letter a pixel at a time", function()
        local Font = require "src.font"
        local text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 :.-/!?+',;() ÁÉÍÓÚÜÑ áéíóúüñ"
        local viaSheet, viaBoxes = {}, {}
        local restore = stub(viaSheet)
        Font.print(text, 7, 9)
        restore()
        -- Not a whole pixel: laid a box at a time, so laid shifted the same.
        restore = stub(viaBoxes)
        Font.print(text, 7.5, 9)
        restore()
        for k, p in ipairs(viaBoxes) do
            local x, y = p:match("^(.-),(.-)$")
            viaBoxes[k] = math.floor(tonumber(x)) .. "," .. y
        end
        assert(#viaSheet > 300, "the letters lit pixels")
        assert(same(viaSheet, viaBoxes), "the same pixels both ways")
    end },
    { "every icon from the picture is the icon a pixel at a time", function()
        local Draw = require "src.ui.draw"
        for name, g in pairs(Draw.ICONS) do
            local viaSheet, viaBoxes = {}, {}
            local restore = stub(viaSheet)
            Draw.icon(name, 3, 4, "o")
            restore()
            for r = 1, 5 do
                for c = 1, 5 do
                    if g[r]:sub(c, c) == "#" then viaBoxes[#viaBoxes + 1] = (3 + c - 1) .. "," .. (4 + r - 1) end
                end
            end
            assert(same(viaSheet, viaBoxes), name)
        end
    end },
}
