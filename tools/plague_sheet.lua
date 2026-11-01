-- A sheet of the plague's models (src/models.lua) painted on their own, no
-- LÖVE needed: `luajit tools/plague_sheet.lua` from the game's folder writes
-- /tmp/sheet/plague.ppm. Rows: the rats (poses 0-4, then two more facings)
-- beside a wolf and a warrior to compare; a shut town's flag as it waves, a
-- pyre, a fallow farm's ruin beside a farm; a town well, sick (daubed with
-- crosses), its dead buried, and with a lazaret.
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
local rats = {}
for pose = 0, 4 do rats[#rats + 1] = M.beast("rats", 1, pose) end
rats[#rats + 1] = M.beast("rats", 0, 0)
rats[#rats + 1] = M.beast("rats", 3, 0)
rats[#rats + 1] = M.beast("wolf", 1, 0)
rats[#rats + 1] = M.unit("warrior", "light", 1, 0)
row("rats", rats)
local things = {}
for pose = 0, M.FLAG_POSES - 1 do things[#things + 1] = M.plagueFlag(pose) end
things[#things + 1] = M.pyre()
things[#things + 1] = M.farm(M.FARM_LAYOUTS[1])
things[#things + 1] = M.farmRuin(M.FARM_LAYOUTS[1])
row("things", things)
local site = { biome = "grass" }
row("city", {
  M.city("light", 6, false, {}, nil, nil, site),
  M.city("light", 6, false, {}, nil, nil, site, { marked = true, graves = 0 }),
  M.city("light", 3, false, {}, nil, nil, site, { marked = true, graves = 6 }),
  M.city("dark", 5, false, { lazaret = true }, nil, nil, site, { marked = true, graves = 3 }),
  M.city("stripe", 4, false, {}, nil, nil, { biome = "plains" }, { marked = true, graves = 3 }),
})
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
local f = (os.execute("mkdir -p /tmp/sheet") and io.open("/tmp/sheet/plague.ppm", "wb"))
f:write(("P6\n%d %d\n255\n"):format(W, H))
local out = {}
for n = 1, W * H do local c = img[n]; out[#out + 1] = string.char(c[1], c[2], c[3]) end
f:write(table.concat(out)); f:close()
print(W, H)
