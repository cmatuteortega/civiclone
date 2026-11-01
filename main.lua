-- Sepia: a small Civilization in eight shades of sepia.
--
-- A hex map traced once into a picture with a depth buffer behind it
-- (src/world.lua), by underroot's 3D method (src/tracer.lua): hexes standing
-- as tall as their ground, mountains of faceted rock, forests, and fog drawn
-- as an old paper map. Units and cities are little models painted once per
-- pose (src/models.lua) and laid over the map a pixel at a time each frame,
-- each pixel kept only where it is nearer than the map there.
--
-- Everything renders into a low-res canvas scaled up by a whole number, in
-- the eight colours of src/palette.lua and nothing else. Every sound is
-- synthesised at load, off the main thread (src/synth.lua, src/ui/audio.lua).
--
-- This file starts the game, runs each frame and lays the two pictures on
-- the window. The rules are in src/game.lua and src/ai.lua, the numbers in
-- src/defs.lua, the screen's parts in src/ui/, the player's settings in
-- src/settings.lua.

-- Room for LuaJIT's compiled code, before anything else is loaded
-- (src/jitroom.lua says why).
require "src.jitroom"

local T = require "src.tracer"
local S = require "src.ui.state"
local View = require "src.ui.view"
local Input = require "src.ui.input"
local Hud = require "src.ui.hud"
local Board = require "src.ui.board"
local Anim = require "src.ui.anim"
local O = require "src.ui.orders"
local Draw = require "src.ui.draw"
local Game = require "src.game"
local World = require "src.world"
local Font = require "src.font"
local Audio = require "src.ui.audio"
local Win = require "src.ui.windows"
local Menu = require "src.ui.menu"
local Settings = require "src.settings"
local Sea = require "src.ui.sea"
local Daylight = require "src.ui.daylight"
local Wild = require "src.ui.wild"
local Birds = require "src.ui.birds"
local Rain = require "src.ui.rain"
local Snow = require "src.ui.snow"
local SkyFx = require "src.ui.sky"
local QuakeFx = require "src.ui.quake"
local Sky = require "src.skyfall"
local Frost = require "src.frost"
local D = require "src.defs"

local floor = math.floor

for _, name in ipairs({ "mousepressed", "mousereleased", "mousemoved", "wheelmoved", "keypressed",
        "touchpressed", "touchmoved", "touchreleased" }) do
    love[name] = Input[name]
end

function love.resize(w, h)
    Menu.resized(w, h)
    View.fit()
end
-- Out of sight, the sound stops; out of focus too, if the settings say.
local visible, focused = true, true
local function away() return not visible or (Settings.get("muteAway") and not focused) end
function love.visible(v) visible = v Audio.hide(away()) end
function love.focus(f) focused = f Audio.hide(away()) end
function love.quit() Audio.stop() end

-- A new game: a new map from a new seed, traced in slices while the loading
-- bar fills, then the first turn. The world ends by the cataclysm chosen in
-- the new game window (or `--cataclysm heat|flood|sky|demons|sun|plague|quake|none`), or by none.
function S.newGame(seed)
    seed = seed or S.seedArg or (os.time() % 100000)
    S.seedArg = nil
    local kind = S.cataclysmArg or Settings.get("cataclysm")
    S.game = Game.new({ seed = seed, cataclysm = kind ~= "none" and kind or false })
    S.world = World.new(S.game)
    S.anim, S.effects, S.msgs, S.wakes = {}, {}, {}, {}
    S.selected, S.panel, S.over, S.hover = nil, nil, nil, nil
    S.pause, S.ask = false, nil
    O.resetLog()
    S.progress = 0
    S.mode = "loading"
    S.painter = coroutine.create(function() S.world:paint(coroutine.yield) end)
end

local function startPlay()
    S.mode = "play"
    View.fit()
    O.collectLog()
    local first = S.game:unitsOf(1)[1]
    if first then View.lookAt(S.game.cells[first.cell], true) end
    O.nextUnit()
end

-- A picture taken unattended (--shot) that fails says why and quits,
-- rather than wait on the error screen for someone to close it.
local showError = love.errorhandler
function love.errorhandler(msg)
    if S.plan then
        print(debug.traceback("Error: " .. tostring(msg), 3))
        return nil
    end
    return showError(msg)
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    -- The title-bar / taskbar icon: the same city as the builds' (assets/icon/).
    love.window.setIcon(love.image.newImageData("assets/icon/icon.png"))
    love.graphics.setLineStyle("rough")
    Sea.load()
    Daylight.load()
    local os = love.system.getOS()
    S.phone = os == "Android" or os == "iOS"
    S.touch = S.phone
    for n, a in ipairs(args or {}) do
        if a == "--seed" and tonumber(args[n + 1]) then S.seedArg = tonumber(args[n + 1]) end
        if a == "--play" then S.play = true end
        -- `--cataclysm heat|flood|sky|demons|sun|plague|quake|none`: how the world ends, whatever the new game
        -- window last had.
        if a == "--cataclysm" and args[n + 1] then S.cataclysmArg = args[n + 1] end
        -- `--touch` lays out the screen as for a phone.
        if a == "--touch" then S.touch, S.phone = true, true end
        -- For checking how it looks: `--shot file.png` takes a picture of the
        -- game a moment after it starts and quits; `--turns n` has the
        -- computer play the player's side for n turns first.
        if a == "--shot" then S.plan = { file = args[n + 1] or "shot.png", turns = 0, frames = 0 } end
        if a == "--turns" and S.plan then S.plan.turns = tonumber(args[n + 1]) or 0 end
        if a == "--select" and S.plan then S.plan.select = args[n + 1] end
        -- `--at N`: the camera over hex N once the selection is made.
        if a == "--at" and S.plan then S.plan.at = tonumber(args[n + 1]) end
        -- `--skip n`: the developer tools' skip, up to turn n, as its
        -- buttons do it.
        if a == "--skip" and S.plan then S.plan.skip = tonumber(args[n + 1]) end
        -- `--zoom n`: the board n whole steps nearer than the window's own.
        if a == "--zoom" and tonumber(args[n + 1]) then S.zoomStep = tonumber(args[n + 1]) end
        -- `--film n`: n pictures a few frames apart instead of one, named
        -- file-001.png on, to see what moves.
        if a == "--film" and S.plan then S.plan.film = tonumber(args[n + 1]) or 24 end
        -- `--next`: one more turn ended just before the picture is taken,
        -- to see it played out (the sky's stones coming down).
        if a == "--next" and S.plan then S.plan.next = true end
        -- `--hour h`: every turn played at h o'clock (0..24), to see the light.
        if a == "--hour" and tonumber(args[n + 1]) then Daylight.force = tonumber(args[n + 1]) / 24 end
        -- `--size WxH`: the window that big, for pictures of more of the map.
        if a == "--size" and args[n + 1] then S.sizeArg = { args[n + 1]:match("^(%d+)x(%d+)$") } end
        -- `--clock look`: the clock drawn so (arc, dial, strip, scene, off).
        if a == "--clock" then require("src.ui.clock").force = args[n + 1] end
        -- `--open settings:audio` (or `pause`, `newgame`, `dev`) shows a menu in the picture.
        if a == "--open" and S.plan then S.plan.open = args[n + 1] end
        -- `--sounds` writes every sound as a .wav into the save folder, and quits.
        if a == "--sounds" then
            print("wrote " .. Audio.dump())
            love.event.quit()
        end
    end
    -- Pictures are taken as the game starts, whatever the player has set.
    if not S.plan then Settings.load() end
    Menu.applyAll()
    if S.sizeArg and S.sizeArg[1] then
        love.window.setMode(tonumber(S.sizeArg[1]), tonumber(S.sizeArg[2]), { resizable = true })
        love.resize(love.graphics.getDimensions())
    end
    -- Pictures are taken in silence.
    if not S.plan then Audio.init() end
end

-- The dev plan above, a frame at a time.
local function followPlan()
    local plan = S.plan
    plan.frames = plan.frames + 1
    if plan.frames == 2 then
        local AI = require "src.ai"
        for _ = 1, plan.turns do
            AI.play(S.game, S.game.players[1])
            O.endTurn()
        end
        if plan.skip then O.skipTo(plan.skip) end
        Anim.events(S.game)
        SkyFx.flush()
        QuakeFx.flush()
        S.anim, S.effects, S.wakes = {}, {}, {}
        for _, u in ipairs(S.game.units) do u.trail = { u.cell } end
        local cap = S.game:citiesOf(1)[1]
        if plan.select == "city" and cap then O.select(cap, true)
        else
            local u = S.game:unitsOf(1)[1]
            if u then O.select(u, true) end
        end
        -- `--select port`: the player's city on the water with the most
        -- built out over it; `--select fleet`: one of the player's ships, or
        -- failing that a unit of theirs on the water.
        -- `--select harbour`: for looking at the sea's models, the player's
        -- city on the water given a harbour and a lighthouse, with a galley,
        -- a quadrireme, a soldier in a boat and fishing boats round it.
        if plan.select == "harbour" then
            local g = S.game
            local p = g.players[1]
            for _, t in ipairs({ "pottery", "sailing", "shipbuilding", "cartography" }) do p.techs[t] = true end
            -- No city on the water yet: found one on the nearest free shore.
            local coastal = false
            for _, c in ipairs(g:citiesOf(1)) do coastal = coastal or g:coastal(g.cells[c.cell]) end
            local cap = g:citiesOf(1)[1]
            if not coastal and cap then
                local best, bd
                for _, cell in ipairs(g.cells) do
                    if g:passable(cell) and g:coastal(cell) and not g.mil[cell.id] and not g.civ[cell.id] then
                        local s = g:addUnit("settler", 1, cell.id)
                        if g:canFound(s) then
                            local d = g:dist(cell, g.cells[cap.cell])
                            if not bd or d < bd then best, bd = cell, d end
                        end
                        g:removeUnit(s)
                    end
                end
                if best then
                    g:found(g:addUnit("settler", 1, best.id)).pop = 5
                    Anim.events(g)
                end
            end
            for _, c in ipairs(g:citiesOf(1)) do
                local cell = g.cells[c.cell]
                if g:coastal(cell) then
                    c.buildings.harbour, c.buildings.lighthouse = true, true
                    -- Ships a little way out, boats on the near water but off
                    -- the pier's side.
                    local kinds = { "galley", "quadrireme", "warrior" }
                    local pier = g:cell(require("src.hex").step(cell.c, cell.r, Anim.shore(g, cell) or 1))
                    local fished = false
                    for _, n in ipairs(g:within(cell, 3)) do
                        local d = g:dist(n, cell)
                        if g:isWater(n) and n.terrain == "coast" and not g.mil[n.id] and not g.civ[n.id] then
                            if d == 1 and n ~= pier and not fished then
                                n.resource, n.improvement, n.owner, fished = "fish", "boats", 1, true
                            elseif d >= 2 and #kinds > 0 then
                                g:addUnit(table.remove(kinds, 1), 1, n.id)
                            end
                        end
                    end
                    -- And the galley under way, to see its wake.
                    for _, u in ipairs(g:unitsOf(1)) do
                        if u.kind == "galley" then
                            for _, n in ipairs(g:within(g.cells[u.cell], 3)) do
                                if g:dist(n, g.cells[u.cell]) == 3 and g:canStand(u, n) and g:path(u, n.id) then
                                    g:moveTo(u, n.id)
                                    break
                                end
                            end
                        end
                    end
                    O.select(c, true)
                    break
                end
            end
            g:look(p)
            S.bordersDirty = true
        end
        if plan.select == "port" then
            local best, bv = nil, -1
            for _, c in ipairs(S.game.cities) do
                if S.game:coastal(S.game.cells[c.cell]) and S.game.players[1].explored[c.cell] then
                    local v = (c.buildings.harbour and 2 or 0) + (c.buildings.lighthouse and 2 or 0) + c.pop * 0.1
                        + (c.owner == 1 and 1 or 0)
                    if v > bv then best, bv = c, v end
                end
            end
            if best then
                if best.owner == 1 then O.select(best, true) else View.lookAt(S.game.cells[best.cell], true) end
            end
        elseif plan.select == "fleet" then
            local pick
            for _, u in ipairs(S.game:unitsOf(1)) do
                if u.def.sea then pick = u break end
                if not pick and S.game:embarked(u) then pick = u end
            end
            if pick then O.select(pick, true) end
        end
        if S.selected and plan.select ~= "port" then
            View.lookAt(S.game.cells[(S.selected.unit or S.selected.city).cell], true)
        end
        -- `--select bridge`: a city of the player's founded where the most
        -- river runs by in open country near home, grown, its bridges over,
        -- and the land round it shown, herons and all.
        if plan.select == "bridge" then
            local g, p = S.game, S.game.players[1]
            local town
            local cap = g:citiesOf(1)[1]
            local from = cap and g.cells[cap.cell] or g.cells[g:unitsOf(1)[1].cell]
            -- Where the most river runs by in open country, near home.
            local best, bv
            for _, cell in ipairs(g:within(from, 9)) do
                if g:passable(cell) and g:onRiver(cell) and not g.mil[cell.id] and not g.civ[cell.id] then
                    local st = g:addUnit("settler", 1, cell.id)
                    local v = 0
                    for _ in pairs(cell.river) do v = v + 2 end
                    for _, n in ipairs(g:neighbours(cell)) do
                        if n.feature == "forest" then v = v - 1 end
                    end
                    if g:canFound(st) and (not bv or v > bv) then best, bv = cell, v end
                    g:removeUnit(st)
                end
            end
            if best then
                town = g:found(g:addUnit("settler", 1, best.id))
                Anim.events(g)
            end
            if town then
                town.pop = 6
                local cell = g.cells[town.cell]
                for _, n in ipairs(g:within(cell, 4)) do p.explored[n.id], p.visible[n.id] = true, true end
                p.sightChanged = true
                S.selected = nil
                S.bordersDirty = true
                View.lookAt(cell, true)
            end
        end
        -- `--select river`: the camera over the hex with the most river by
        -- it (a fall, if there is one), and the land round it shown, to look
        -- at the rivers.
        if plan.select == "ford" then plan.select, plan.ford = "river", true end
        if plan.select == "river" then
            local g, p = S.game, S.game.players[1]
            local best, bv = nil, -1
            for _, cell in ipairs(g.cells) do
                local v = 0
                for _, e in pairs(cell.river or {}) do v = v + 1 + (e.fall and 2 or 0) + (e.mouth and 1 or 0) end
                if v > bv then best, bv = cell, v end
            end
            if best then
                for _, cell in ipairs(g:within(best, 5)) do p.explored[cell.id], p.visible[cell.id] = true, true end
                p.sightChanged = true
                S.selected = nil
                View.lookAt(best, true)
                -- `--select ford`: and a warrior set to wade across it a
                -- moment later.
                if plan.ford then
                    for _, n in ipairs(g:neighbours(best)) do
                        if g:passable(best) and g:passable(n) and g:fords(best, n) and not g.mil[best.id] and not g.mil[n.id] then
                            plan.wader = { unit = g:addUnit("warrior", 1, best.id), to = n.id }
                            break
                        end
                    end
                end
            end
        end
        -- `--select wild`: the camera over the hex with the most of the wild
        -- round it (beasts and lairs within three), and the land round it
        -- shown. `--select wild:serpent` (or any beast's kind, or a lair's)
        -- for the one with most of that.
        -- `--select zoo`: one of every beast and lair the land near the
        -- player's start allows, put round it, all of it shown.
        if plan.select == "zoo" then
            local g, p = S.game, S.game.players[1]
            local Beasts = require "src.beasts"
            local from = g.cells[g:unitsOf(1)[1].cell]
            local spots = g:within(from, 5)
            table.sort(spots, function(x, y) return g:dist(x, from) < g:dist(y, from) end)
            local function free(cell) return not g.mil[cell.id] and not g.civ[cell.id] and not cell.lair and not cell.city end
            for _, kind in ipairs({ "den", "cave", "hive" }) do
                for _, cell in ipairs(spots) do
                    if free(cell) and g:passable(cell) and g:dist(cell, from) >= 2 then
                        Beasts.addLair(g, kind, cell.id)
                        break
                    end
                end
            end
            for _, kind in ipairs({ "wolf", "bear", "boar", "aurochs", "horse", "croc", "serpent", "wolf" }) do
                local probe = { def = require("src.defs").BEASTS[kind], owner = g.WILD }
                for _, cell in ipairs(spots) do
                    if free(cell) and g:dist(cell, from) >= 2 and Beasts.canEnter(g, probe, cell) then
                        Beasts.spawn(g, kind, cell.id)
                        break
                    end
                end
            end
            for _, cell in ipairs(g:within(from, 6)) do p.explored[cell.id], p.visible[cell.id] = true, true end
            p.sightChanged = true
            S.selected = nil
            View.lookAt(from, true)
        end
        -- `--select skyfall`: round the player's first unit, one of every
        -- crater the sky's falling leaves (small, deep, still hot, with star
        -- iron, on hills broken flat), a small and a great stone coming, all
        -- of it shown.
        if plan.select == "skyfall" then
            local D = require "src.defs"
            local g, p = S.game, S.game.players[1]
            local from = g.cells[g:unitsOf(1)[1].cell]
            local spots = g:within(from, 4)
            table.sort(spots, function(x, y) return g:dist(x, from) < g:dist(y, from) end)
            local used = {}
            local function take(f)
                for _, cell in ipairs(spots) do
                    if not used[cell.id] and not cell.city and not g.mil[cell.id] and not g.civ[cell.id]
                        and g:dist(cell, from) >= 1 and f(cell) then
                        used[cell.id] = true
                        for _, n in ipairs(g:neighbours(cell)) do used[n.id] = used[n.id] or false end
                        return cell
                    end
                end
            end
            local function flat(cell) return not g:isWater(cell) and cell.elev == "flat" end
            g.cataclysm.kind = "sky"
            local small = take(flat)
            if small then Sky.crater(g, small, D.SKY.sink.small); small.glow, small.resource = nil, nil end
            local deep = take(flat)
            if deep then for _ = 1, 2 do Sky.crater(g, deep, D.SKY.sink.big) end; deep.glow = nil end
            local hot = take(flat)
            if hot then Sky.crater(g, hot, D.SKY.sink.big); hot.resource = "iron" end
            local hill = take(function(c) return c.elev == "hills" end)
            if hill then Sky.crater(g, hill, D.SKY.sink.small); hill.glow = nil end
            g.cataclysm.marks = {}
            local m1 = take(flat)
            if m1 then g.cataclysm.marks[m1.id] = "small" end
            local m2 = take(function(c) return not g:isWater(c) end)
            if m2 then g.cataclysm.marks[m2.id] = "big" end
            for _, cell in ipairs(g:within(from, 6)) do p.explored[cell.id], p.visible[cell.id] = true, true end
            p.sightChanged = true
            S.selected = nil
            View.lookAt(from, true)
        end
        -- `--select frozen` (or `frozen:N`, the camera on hex N): the frost
        -- round the player's first unit (src/frost.lua):
        -- tundra near, snow beyond, the trees and hills under it, a river
        -- frozen over, the shallows frozen to ice with a lead of open water
        -- left in it, all of it shown.
        local frozenAt = plan.select and plan.select:match("^frozen:?(%d*)$")
        if frozenAt then
            local g, p = S.game, S.game.players[1]
            local from = g.cells[g:unitsOf(1)[1].cell]
            for _, cell in ipairs(g:within(from, 6)) do
                local d = g:dist(cell, from)
                if not g:isWater(cell) and cell.elev ~= "mountain" and not cell.city then
                    if d >= 2 or cell.city then Frost.chill(g, cell) end
                    if d >= 3 or (d == 1 and cell.id % 2 == 0) then Frost.chill(g, cell) end
                end
            end
            for _ = 1, 3 do
                for _, cell in ipairs(g:within(from, 7)) do
                    if g:isWater(cell) and cell.id % 5 ~= 0 and Frost.freezable(g, cell, true) then Frost.freeze(g, cell) end
                end
            end
            -- A town of the player's in it keeps a hearth.
            local cap = g:citiesOf(1)[1]
            if cap then cap.buildings.hearth = true end
            for _, cell in ipairs(g:within(from, 8)) do p.explored[cell.id], p.visible[cell.id] = true, true end
            p.sightChanged = true
            S.selected = nil
            View.lookAt(g.cells[tonumber(frozenAt)] or from, true)
        end
        -- `--select world`: the whole map shown, the camera on its middle;
        -- under the still sun, on the line, where it crosses the land
        -- nearest the middle.
        if plan.select == "world" then
            local g, p = S.game, S.game.players[1]
            local mid = g.cells[math.floor(g.rows / 2) * g.cols + math.floor(g.cols / 2) + 1]
            local best, bv = mid, nil
            for _, cell in ipairs(g.cells) do
                p.explored[cell.id], p.visible[cell.id] = true, true
                local side = D.sunSide(g, cell.x, cell.z)
                if side and not g:isWater(cell) then
                    local v = math.abs(side) * 3 + g:dist(cell, mid) * 0.5
                    if not bv or v < bv then best, bv = cell, v end
                end
            end
            p.sightChanged = true
            S.selected = nil
            View.lookAt(best, true)
        end
        -- `--select abyss`: the demons round the player's first unit: their
        -- citadel risen a few hexes off with its blight about it, a rift
        -- open and another and a tentacle coming, and one of every demon,
        -- all of it shown.
        if plan.select == "abyss" then
            local D = require "src.defs"
            local Beasts = require "src.beasts"
            local Demons = require "src.demons"
            local g, p = S.game, S.game.players[1]
            g.cataclysm.kind = "demons"
            local from = g.cells[g:unitsOf(1)[1].cell]
            local spots = g:within(from, 5)
            table.sort(spots, function(x, y) return g:dist(x, from) < g:dist(y, from) end)
            local used = {}
            local function take(f, near)
                for _, cell in ipairs(spots) do
                    if not used[cell.id] and not cell.city and not cell.lair and not g.mil[cell.id] and not g.civ[cell.id]
                        and g:dist(cell, from) >= (near or 2) and f(cell) then
                        used[cell.id] = true
                        return cell
                    end
                end
            end
            local function ground(c) return g:passable(c) end
            local cit = take(function(c) return ground(c) and g:dist(c, from) >= 3 end, 3)
            if cit then
                Beasts.addLair(g, "citadel", cit.id)
                local l = cit.lair
                l.hp, l.maxHp, l.str = 230, 320, D.DEMONS.citadelStr.deep
                g.cataclysm.citadel = cit.id
                Demons.blight(g, cit)
                for _, n in ipairs(g:neighbours(cit)) do
                    if ground(n) and not n.city then Demons.blight(g, n) end
                    used[n.id] = true
                end
            end
            local rift = take(ground)
            if rift then Beasts.addLair(g, "rift", rift.id); Demons.blight(g, rift) end
            g.cataclysm.marks = {}
            local m = take(ground)
            if m then g.cataclysm.marks[m.id] = "rift" end
            local sea = take(function(c) return c.terrain == "coast" end, 1)
            if sea then g.cataclysm.marks[sea.id] = "tentacle" end
            local shore = take(function(c)
                if c.terrain ~= "coast" then return false end
                for _, n in ipairs(g:neighbours(c)) do if ground(n) then return true end end
            end, 1)
            if shore then g:addUnit("tentacle", g.WILD, shore.id).home = shore.id end
            for _, kind in ipairs({ "spider", "eye", "brood", "spider", "abyss" }) do
                local c = take(ground)
                if c then g:addUnit(kind, g.WILD, c.id).home = c.id end
            end
            for _, cell in ipairs(g:within(from, 6)) do p.explored[cell.id], p.visible[cell.id] = true, true end
            p.sightChanged = true
            S.selected = nil
            View.lookAt(from, true)
        end
        -- `--select plague`: the plague round the player's capital: the
        -- capital sick, its houses daubed, graves dug, a pyre burning
        -- beside it and the miasma over it, crows over it; a town of theirs
        -- shut nearby (founded if there is none), with a lazaret; rats
        -- running, a soldier carrying it, a farm fallow, all of it shown.
        if plan.select == "plague" then
            local Plague = require "src.plague"
            local g, p = S.game, S.game.players[1]
            g.cataclysm.kind = "plague"
            if g.turn < D.PLAGUE.fever then g.turn = D.PLAGUE.dying + 2 end
            g.cataclysm.stage = require("src.cataclysm").stage(g)
            local cap = g:citiesOf(1)[1]
            if not cap then
                for _, u in ipairs(g:unitsOf(1)) do if u.kind == "settler" then cap = g:found(u) end end
            end
            if cap then
                local from = g.cells[cap.cell]
                cap.pop = math.max(cap.pop, 6)
                g:assignWork(cap)
                Plague.infect(g, cap)
                cap.sick, cap.dead, cap.pyre = 5, 5, g.turn
                -- A second town of ours, shut, with a lazaret.
                local other
                for _, c in ipairs(g:citiesOf(1)) do if c ~= cap then other = c break end end
                if not other then
                    for _, cell in ipairs(g:within(from, 5)) do
                        if g:dist(cell, from) >= 4 and g:passable(cell) and not cell.city and not cell.lair
                            and not g.mil[cell.id] and not g.civ[cell.id] and (not cell.owner or cell.owner == 1) then
                            local s = g:addUnit("settler", 1, cell.id)
                            other = g:found(s)
                            if other then break end
                            g:removeUnit(s)
                        end
                    end
                end
                if other then
                    other.pop = math.max(other.pop, 3)
                    other.buildings.lazaret = true
                    Plague.setShut(g, other, true)
                end
                -- A farm left fallow, and rats out of it.
                local spots = g:within(from, 2)
                table.sort(spots, function(x, y) return g:dist(x, from) < g:dist(y, from) end)
                local n = 0
                for _, cell in ipairs(spots) do
                    if g:dist(cell, from) >= 1 and g:passable(cell) and not cell.city and not cell.feature
                        and cell.elev == "flat" and not cell.lair and not g.mil[cell.id] and n < 2 then
                        n = n + 1
                        cell.improvement, cell.fallow = nil, true
                        g:emit({ kind = "terrain", cell = cell.id })
                    end
                end
                local rats = 0
                for _, cell in ipairs(spots) do
                    if rats < 2 and g:dist(cell, from) == 2 and g:passable(cell) and not cell.city and not g.mil[cell.id]
                        and not cell.lair then
                        rats = rats + 1
                        local r = g:addUnit("rats", g.WILD, cell.id)
                        r.home, r.life = cap.cell, 10
                    end
                end
                for _, u in ipairs(g:unitsOf(1)) do if not u.def.civilian then u.sick = 3 break end end
                for _, cell in ipairs(g:within(from, 6)) do p.explored[cell.id], p.visible[cell.id] = true, true end
                p.sightChanged = true
                S.selected = nil
                View.lookAt(from, true)
            end
        end
        -- `--select sundering`: the sundering round the player's first unit
        -- (src/quake.lua): faults open between the hexes, the rift torn
        -- across the land a few hexes off at every step of it (cracked, a
        -- chasm, the sea pouring in, sea), a range risen, a volcano
        -- erupting with its lava, black rock and ash about it, the sea's
        -- floor come up, a quake and a wave coming, all of it shown.
        if plan.select == "sundering" or plan.select == "rift" then
            local Quake = require "src.quake"
            local Cat = require "src.cataclysm"
            local H = require "src.hex"
            local g, p = S.game, S.game.players[1]
            g.cataclysm.kind = "quake"
            local from = g.cells[g:unitsOf(1)[1].cell]
            if g.turn < D.QUAKE.rift then g.turn = D.QUAKE.fire + 2 end
            g.cataclysm.stage = Cat.stage(g)
            -- The rift, planned as the game would, and torn every step of
            -- the way: the sea end done, the far end only cracked.
            local path = Quake.planRift(g)
            if path then
                g.cataclysm.rift = {}
                for i, cell in ipairs(path) do
                    g.cataclysm.rift[i] = cell.id
                    cell.riftLine = i
                    local a, b = path[i - 1], path[i + 1]
                    if not a or not b then
                        for _, n in ipairs(g:neighbours(cell)) do
                            if g:isWater(n) then
                                if not a then a = { x = 2 * cell.x - n.x, z = 2 * cell.z - n.z } end
                                if not b then b = n end
                                break
                            end
                        end
                    end
                    cell.riftAngle = math.atan2((b or cell).z - (a or cell).z, (b or cell).x - (a or cell).x)
                end
                local n = #path
                for i, cell in ipairs(path) do
                    if not cell.city then
                        local steps = math.max(0, 4 - math.floor((i - 1) * 5 / n))
                        for _ = 1, steps do Quake.tear(g, cell) end
                    end
                end
                if plan.select == "rift" then from = path[math.floor(n / 4) + 1] end
            end
            local spots = g:within(from, 4)
            table.sort(spots, function(x, y) return g:dist(x, from) < g:dist(y, from) end)
            local used = {}
            local function take(f)
                for _, cell in ipairs(spots) do
                    if not used[cell.id] and not cell.city and not cell.riftLine and not g.mil[cell.id] and not g.civ[cell.id]
                        and g:dist(cell, from) >= 1 and f(cell) then
                        used[cell.id] = true
                        return cell
                    end
                end
            end
            -- Faults: a line of a few edges by the start.
            local c0 = take(function(c) return g:passable(c) end)
            if c0 then
                print("faults from hex " .. c0.id)
                local k, cell = 0, c0
                for _ = 1, 5 do
                    if Quake.canFault(g, cell, k) then Quake.openFault(g, cell, k) end
                    local nb = g:cell(H.step(cell.c, cell.r, (k + 1) % 6))
                    if not nb then break end
                    cell, k = nb, (k + 5) % 6
                end
            end
            if plan.select == "sundering" then
                local v = take(function(c) return g:passable(c) and c.elev ~= "flat" end)
                    or take(function(c) return g:passable(c) end)
                if v then
                    g.cataclysm.volcanoes = {}
                    v.elev, v.top = "mountain", D.TERRAIN.grass.top + D.ELEV.mountain.rise
                    v.feature, v.improvement = nil, nil
                    v.volcano = true
                    g.cataclysm.volcanoes[1] = v.id
                    g.cataclysm.marks = g.cataclysm.marks or {}
                    -- With `--next`, it erupts as the next turn begins, to
                    -- watch.
                    g:emit({ kind = "terrain", cell = v.id })
                    if plan.next then g.cataclysm.marks[v.id] = "erupt" else Quake.erupt(g, v) end
                    print("volcano at hex " .. v.id)
                    -- And older flows, cooled, and the ash's soil.
                    for _, n in ipairs(plan.next and {} or g:within(v, 2)) do
                        if g:dist(n, v) == 2 and not n.lava and not n.city and g:passable(n) and n.id % 3 == 0 then
                            n.basalt, n.ashfall = true, nil
                        elseif g:dist(n, v) == 2 and n.ashfall and n.id % 3 == 1 then
                            n.ashfall, n.soil = nil, true
                        end
                        used[n.id] = true
                    end
                end
                local up = take(function(c) return c.elev == "flat" and g:passable(c) end)
                if up then Quake.raise(g, up); Quake.raise(g, up) end
                local up2 = take(function(c) return c.elev == "flat" and g:passable(c) end)
                if up2 then Quake.raise(g, up2) end
                local shoal = take(function(c)
                    if c.terrain ~= "coast" then return false end
                    for _, n in ipairs(g:neighbours(c)) do if g:passable(n) then return true end end
                end)
                if shoal then Quake.raise(g, shoal) end
                local slid = take(function(c) return c.elev == "hills" and c.feature == "forest" end)
                if slid then slid.feature, slid.slid = nil, true end
                print("risen", up and up.id, up2 and up2.id, "shoal", shoal and shoal.id, "slid", slid and slid.id)
            end
            g.cataclysm.marks = g.cataclysm.marks or {}
            local q = take(function(c) return g:passable(c) end)
            if q then g.cataclysm.marks[q.id] = "quake" end
            local sea = take(function(c) return g:isWater(c) end)
            if sea then Quake.heave(g, sea, 3) end
            for _, cell in ipairs(g:within(from, 7)) do p.explored[cell.id], p.visible[cell.id] = true, true end
            p.sightChanged = true
            S.selected = nil
            Anim.events(g)
            SkyFx.flush()
            QuakeFx.flush()
            S.effects = {}
            View.lookAt(plan.at and g.cells[plan.at] or from, true)
        end
        -- `--select bigfall`: a great stone coming on open land beside a
        -- forest near the player's capital, the only one this turn, the
        -- camera on it (with `--next`, to watch it come down).
        if plan.select == "bigfall" then
            local g, p = S.game, S.game.players[1]
            local cap = g:citiesOf(1)[1]
            local from = g.cells[cap and cap.cell or g:unitsOf(1)[1].cell]
            local best, bd
            for _, cell in ipairs(g.cells) do
                if not g:isWater(cell) and cell.elev == "flat" and not cell.city and not cell.feature then
                    local woods = 0
                    for _, n in ipairs(g:neighbours(cell)) do if n.feature == "forest" then woods = woods + 1 end end
                    local d = g:dist(cell, from) - woods * 0.6
                    if woods > 0 and g:dist(cell, from) >= 2 and (not bd or d < bd) then best, bd = cell, d end
                end
            end
            if best then
                g.cataclysm.marks = { [best.id] = "big" }
                for _, cell in ipairs(g:within(best, 5)) do p.explored[cell.id], p.visible[cell.id] = true, true end
                p.sightChanged = true
                S.selected = nil
                View.lookAt(best, true)
            end
        end
        local wildKind = plan.select and plan.select:match("^wild:?(%a*)$")
        if wildKind then
            local g, p = S.game, S.game.players[1]
            local best, bv = nil, 0
            for _, cell in ipairs(g.cells) do
                local v = 0
                for _, n in ipairs(g:within(cell, 3)) do
                    local b = g.mil[n.id]
                    if b and b.owner == g.WILD and (wildKind == "" or b.kind == wildKind) then v = v + 2 end
                    if n.lair and (wildKind == "" or n.lair.kind == wildKind) then v = v + 3 end
                end
                if v > bv then best, bv = cell, v end
            end
            if best then
                for _, cell in ipairs(g:within(best, 4)) do p.explored[cell.id], p.visible[cell.id] = true, true end
                p.sightChanged = true
                S.selected = nil
                View.lookAt(best, true)
            end
        end
        -- `--select fire`, `scorch`, `burnt`: the camera over the hex with the
        -- most of the heat death's burning (or baked, or burnt) land round
        -- it, that land shown; `flood`, `marsh`, `silt`, `drowned` the same
        -- for the deluge's, `crater` and `glow` (fresh craters) for the sky's
        -- falling, and `mark` the hexes stones are falling on next (`heart`
        -- the heart of the comet's). `--select cistern` (or `levee`, or
        -- `shelter`): the player's capital given one, selected.
        local heat = ({ fire = "fire", scorch = "scorched", burnt = "burnt", flood = "flood", silt = "silt",
            drowned = "drowned", marsh = "marsh", crater = "crater", glow = "glow", mark = "mark",
            heart = "heart", blight = "blight", tundra = "tundra", snow = "snow", ice = "ice", frost = "frost",
            twilight = "twilight" })[plan.select or ""]
        if heat then
            local g, p = S.game, S.game.players[1]
            local best, bv = nil, 0
            for _, cell in ipairs(g.cells) do
                local v = 0
                for _, n in ipairs(g:within(cell, 2)) do
                    local m = Sky.marked(g, n)
                    if (heat == "mark" and m and m ~= "heart") or (heat == "heart" and m == "heart") then
                        v = v + (g:dist(n, cell) == 0 and 3 or 2)
                    end
                    if n[heat] or n.terrain == heat or (heat == "frost" and Frost.frozen(n)) then
                        v = v + (g:dist(n, cell) == 0 and 3 or 2)
                    end
                    -- The still sun's twilight: land on the line, the day
                    -- and the night both in sight of it.
                    if heat == "twilight" then
                        local s = D.sunSide(g, n.x, n.z)
                        if s and not g:isWater(n) then v = v + math.max(0, 1.5 - math.abs(s)) end
                        if s and Frost.frozen(n) then v = v + 0.3 end
                        if s and (n.scorched or n.terrain == "desert") then v = v + 0.3 end
                    end
                    if heat == "fire" and n.feature == "forest" then v = v + 0.5 end
                end
                if v > bv then best, bv = cell, v end
            end
            if best then
                for _, cell in ipairs(g:within(best, 5)) do p.explored[cell.id], p.visible[cell.id] = true, true end
                p.sightChanged = true
                S.selected = nil
                View.lookAt(best, true)
                print("looking at hex " .. best.id .. " on turn " .. g.turn)
            end
        end
        -- `--select cell:N`: the camera over hex N, the land round it shown,
        -- to watch one place over several pictures.
        local at = plan.select and tonumber(plan.select:match("^cell:(%d+)$"))
        if at and S.game.cells[at] then
            local g, p = S.game, S.game.players[1]
            for _, cell in ipairs(g:within(g.cells[at], 5)) do p.explored[cell.id], p.visible[cell.id] = true, true end
            p.sightChanged = true
            S.selected = nil
            View.lookAt(g.cells[at], true)
        end
        if plan.select == "cistern" or plan.select == "levee" or plan.select == "shelter" or plan.select == "hearth"
            or plan.select == "buttress" then
            local cap = S.game:citiesOf(1)[1]
            if cap then
                cap.buildings[plan.select] = true
                S.selected = nil
                View.lookAt(S.game.cells[cap.cell], true)
            end
        end
        -- `--select coast`: the camera over the explored shore nearest the
        -- player's first unit or city, to look at the sea.
        if plan.select == "coast" and S.selected then
            local from = S.game.cells[(S.selected.unit or S.selected.city).cell]
            local best, bd = nil, math.huge
            for _, cell in ipairs(S.game.cells) do
                local d = S.game:dist(cell, from)
                if cell.terrain == "coast" and S.game.players[1].explored[cell.id] and d < bd then best, bd = cell, d end
            end
            if best then View.lookAt(best, true) end
        end
        -- The pointer over the furthest hex the chosen unit can reach.
        local u = S.selected and S.selected.unit
        if u then
            local best, bd = nil, -1
            for id, r in pairs(S.game:reach(u)) do
                local d = S.game:dist(S.game.cells[id], S.game.cells[u.cell])
                if not r.through and d > bd then best, bd = S.game.cells[id], d end
            end
            if best then
                local i, j = S.world:toImage(best.x, best.top, best.z)
                S.mouse.wx, S.mouse.wy = (i - floor(S.camx)) * S.zoom, (j - floor(S.camy)) * S.zoom
                S.mouse.x, S.mouse.y = floor(S.mouse.wx / S.uz), floor(S.mouse.wy / S.uz)
            end
        end
    end
    if plan.frames == 3 and plan.open then
        local what, tab = plan.open:match("^(%a+):?(%a*)$")
        if what == "pause" then Menu.openPause() end
        if what == "settings" then Menu.openSettings(tab ~= "" and tab or nil) end
        if what == "newgame" then Menu.openNewGame() end
        if what == "dev" then Menu.openDev() end
    end
    if plan.next and plan.frames == 26 then
        local AI = require "src.ai"
        AI.play(S.game, S.game.players[1])
        S.game:endTurn(AI)
        O.collectLog()
    end
    if plan.wader and plan.frames == 60 then
        S.game:moveTo(plan.wader.unit, plan.wader.to)
    end
    if plan.film then
        local k = (plan.frames - 30) / 3
        if k >= 0 and k == math.floor(k) and k < plan.film then
            S.shot = plan.file:gsub("%.png$", "") .. ("-%03d.png"):format(k + 1)
        end
        if k >= plan.film + 1 then love.event.quit() end
        return
    end
    if plan.frames == 30 then S.shot = plan.file end
    if plan.frames == 32 then love.event.quit() end
end

function love.update(dt)
    Menu.throttle()
    if S.play then S.play = nil S.newGame() end
    dt = math.min(dt, 1 / 20)
    S.clock = S.clock + dt
    S.dt = dt
    Sea.update(dt)
    Audio.hide(away())
    Audio.update(dt)
    Menu.update(dt)
    S.menuOpen = Menu.open() or Win.modal()
    if S.mode == "loading" then
        local t0 = love.timer.getTime()
        while coroutine.status(S.painter) ~= "dead" and love.timer.getTime() - t0 < 1 / 30 do
            local ok, p = coroutine.resume(S.painter)
            if not ok then error(p) end
            S.progress = p or 1
        end
        if coroutine.status(S.painter) == "dead" then
            S.painter = nil
            startPlay()
        end
        return
    end
    if S.mode ~= "play" then return end
    if S.plan then followPlan() end
    View.update(dt)
    Anim.update(S.game, dt * Settings.get("animSpeed"))
    Daylight.update(dt)
    Wild.update(dt)
    Birds.update(dt)
    Rain.update(dt)
    Snow.update(dt)
    SkyFx.update(dt)
    QuakeFx.update(dt)
    -- The hexes changed, built again a few at a time, so a turn's worth
    -- does not stop the game for a moment.
    S.world:work(1 / 160, love.timer.getTime)
    Input.findHover()
    if not S.over then
        local result, why = S.game:outcome()
        if result then S.over = { result = result, why = why } end
    end
    O.collectLog()
end

--- the title and the loading bar ------------------------------------------------

-- The paper map the fog is drawn as, for behind the title: hex outlines,
-- squashed as the board's are, on cream.
local function hexField()
    Draw.rect("c", 0, 0, S.vw, S.vh)
    Draw.color("t")
    local R, sq = 9, T.SE
    local w, rowStep = R * math.sqrt(3), R * 1.5
    local function line(x0, y0, x1, y1)
        local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        for k = 0, n do
            local f = k / math.max(1, n)
            love.graphics.rectangle("fill", floor(x0 + (x1 - x0) * f), floor(y0 + (y1 - y0) * f), 1, 1)
        end
    end
    for r = -1, floor(S.vh / (rowStep * sq)) + 1 do
        for c = -1, floor(S.vw / w) + 1 do
            local cx, cy = c * w + (r % 2) * w / 2, r * rowStep * sq
            -- Three edges a hex, so each is drawn once: north-west, north-east, east.
            for _, e in ipairs({ 4, 5, 0 }) do
                local a0, a1 = math.rad(60 * e - 30), math.rad(60 * e + 30)
                line(cx + R * math.cos(a0), cy + R * math.sin(a0) * sq, cx + R * math.cos(a1), cy + R * math.sin(a1) * sq)
            end
        end
    end
end

local function bigText(k, s, cx, y, scale)
    love.graphics.push()
    love.graphics.translate(floor(cx - Font.width(s) * scale / 2), y)
    love.graphics.scale(scale, scale)
    Draw.text(k, s, 0, 0)
    love.graphics.pop()
end

local function title()
    hexField()
    local cx = floor(S.vw / 2)
    local y = floor(S.vh / 2) - 56
    Draw.rect("o", cx - 130, y - 10, 260, 124)
    Draw.frame("k", cx - 128, y - 8, 256, 120)
    bigText("o", "SEPIA", cx + 1, y + 1, 4)
    bigText("w", "SEPIA", cx, y, 4)
    local sub = "BUILD AN EMPIRE ON A MAP OF SEPIA HEXES"
    Draw.text("c", sub, cx - floor(Font.width(sub) / 2), y + 26)
    Draw.button("NEW GAME", cx - 40, y + 38, 80, 14, Menu.openNewGame, { strong = true })
    Draw.button("SETTINGS", cx - 40, y + 54, 39, 12, Menu.openSettings)
    Draw.button("QUIT", cx + 1, y + 54, 39, 12, function() love.event.quit() end)
    local help = S.touch and {
        "TAP: SELECT, OR SEND THE CHOSEN UNIT THERE",
        "DRAG: PAN   PINCH: ZOOM",
        "THE BUTTONS DOWN THE RIGHT: ZOOM, NEXT UNIT,",
        "CAPITAL, HEX GRID AND SOUND",
    } or (function()
        -- As the keys are bound now.
        local function k(cmd) return Settings.keyName(Settings.key(cmd)) end
        return {
            "LEFT CLICK: SELECT   RIGHT CLICK: MOVE OR ATTACK",
            "DRAG, ARROWS OR " .. k("panUp") .. k("panLeft") .. k("panDown") .. k("panRight") .. ": PAN   WHEEL: ZOOM   "
                .. k("grid") .. ": GRID   " .. k("research") .. ": RESEARCH",
            k("main") .. ": NEXT   " .. k("endTurn") .. ": END TURN   " .. k("skip") .. ": SKIP",
            k("found") .. ": FOUND CITY   " .. k("fortify") .. ": FORTIFY   " .. k("farm") .. ": FARM   "
                .. k("mine") .. ": MINE   " .. k("capital") .. ": CAPITAL",
            k("sound") .. ": SOUND   ESC: MENU   DRAG A WINDOW BY ITS TITLE",
        }
    end)()
    for k, l in ipairs(help) do Draw.text("t", l, cx - floor(Font.width(l) / 2), y + 76 + (k - 1) * 7) end
end

local function loading()
    hexField()
    local cx, cy = floor(S.vw / 2), floor(S.vh / 2)
    local s = "SURVEYING THE LAND"
    Draw.rect("o", cx - 70, cy - 14, 140, 26)
    Draw.text("w", s, cx - floor(Font.width(s) / 2), cy - 9)
    Draw.bar(cx - 60, cy + 2, 120, S.progress or 0, "w", "n")
    Draw.bar(cx - 60, cy + 3, 120, S.progress or 0, "c", "n")
end

function love.draw()
    love.graphics.setCanvas(S.ui)
    love.graphics.clear(0, 0, 0, 0)
    S.buttons, S.panels = {}, {}
    if S.mode == "title" then
        title()
    elseif S.mode == "loading" then
        loading()
    else
        Board.banners()
        Hud.draw(S.dt or 0)
    end
    -- The windows over all the rest, and the menus over them.
    Menu.draw()
    Win.flush()
    Menu.drawFps()
    if S.mode == "play" then Board.draw() end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.clear(T.RGB[T.IDX.o])
    -- The board shaking under a quake (src/ui/quake.lua), whole pixels of it.
    local shake = S.mode == "play" and S.shake
    local sx, sy = shake and shake[1] * S.zoom or 0, shake and shake[2] * S.zoom or 0
    if S.mode == "play" then love.graphics.draw(S.canvas, sx, sy, 0, S.zoom, S.zoom) end
    love.graphics.draw(S.ui, 0, 0, 0, S.uz, S.uz)
    if S.shot then
        local file = S.shot
        love.graphics.captureScreenshot(function(img)
            img:encode("png", file)
            print("saved " .. love.filesystem.getSaveDirectory() .. "/" .. file)
        end)
        S.shot = nil
    end
end
