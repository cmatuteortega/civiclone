-- A sheet of the demons' models (src/models.lua) painted on their own, no LÖVE
-- needed: `luajit tools/demon_sheet.lua` from the game's folder writes
-- /tmp/sheet/sheet.ppm. Rows: spider, brood mother, eye, tentacle, Eye of the
-- Abyss (poses 0-4, then two more facings); beasts and a warrior to compare;
-- rift, citadel, den, cave; a town without and with a sanctum.
package.path = "./?.lua;" .. package.path
local M = require "src.models"
local T = require "src.tracer"
local Palette = require "src.palette"
local rgb = {}
for i, row in ipairs(Palette.list) do
  local s = row[2]
  rgb[i] = { tonumber(s:sub(1,2),16), tonumber(s:sub(3,4),16), tonumber(s:sub(5,6),16) }
end
local rows = {}
local function row(label, pics) rows[#rows + 1] = { label = label, pics = pics } end
for _, k in ipairs({ "spider", "brood", "eye", "tentacle", "abyss" }) do
  local pics = {}
  for pose = 0, 4 do pics[#pics + 1] = M.beast(k, 1, pose) end
  pics[#pics + 1] = M.beast(k, 0, 0)
  pics[#pics + 1] = M.beast(k, 3, 0)
  row(k, pics)
end
row("compare", { M.beast("wolf", 1, 0), M.beast("bear", 1, 0), M.beast("serpent", 1, 0), M.beast("croc", 1, 0), M.unit("warrior", "light", 1, 0) })
row("lairs", { M.lair("rift"), M.lair("citadel"), M.lair("den"), M.lair("cave") })
row("city", { M.city("light", 6, false, {}, nil, nil, { biome = "grass" }), M.city("light", 6, false, { sanctum = true }, nil, nil, { biome = "grass" }) })
local pad = 6
local W, H = 0, pad
for _, r in ipairs(rows) do
  local w, h = pad, 0
  for _, p in ipairs(r.pics) do w = w + p.w + pad; h = math.max(h, p.h) end
  r.h = h; W = math.max(W, w); H = H + h + pad
end
local img = {}
local bg = { rgb[T.IDX.k][1], rgb[T.IDX.k][2], rgb[T.IDX.k][3] }
for n = 1, W * H do img[n] = bg end
local y = pad
for _, r in ipairs(rows) do
  local x = pad
  for _, p in ipairs(r.pics) do
    local oy = y + r.h - p.h
    for pj = 0, p.h - 1 do for pi = 0, p.w - 1 do
      local k = p.key[pj * p.w + pi]
      if k ~= 0 then img[(oy + pj) * W + x + pi + 1] = rgb[k] end
    end end
    x = x + p.w + pad
  end
  y = y + r.h + pad
end
local f = (os.execute("mkdir -p /tmp/sheet") and io.open("/tmp/sheet/sheet.ppm", "wb"))
f:write(("P6\n%d %d\n255\n"):format(W, H))
local out = {}
for n = 1, W * H do local c = img[n]; out[#out + 1] = string.char(c[1], c[2], c[3]) end
f:write(table.concat(out)); f:close()
print(W, H)
