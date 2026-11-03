-- The HUD, on a canvas of its own at a zoom that stays put: the bar along the
-- top (treasury, science, culture, research, the turn), the latest news, the
-- selected unit's or city's panel, research, a tooltip for the hex under the
-- pointer, a minimap, and the button that ends the turn. On a touch screen,
-- buttons down the right edge for what only keys and the wheel do.
--
-- The unit's and city's panels, research and the end are windows
-- (src/ui/windows.lua): the player can drag them where they like.

local D = require "src.defs"
local Cat = require "src.cataclysm"
local Weather = require "src.weather"
local Beasts = require "src.beasts"
local H = require "src.hex"
local T = require "src.tracer"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local View = require "src.ui.view"
local O = require "src.ui.orders"
local Board = require "src.ui.board"
local Font = require "src.font"
local L = require "src.lang"
local Win = require "src.ui.windows"
local Menu = require "src.ui.menu"
local Settings = require "src.settings"
local Clock = require "src.ui.clock"
local Palette = require "src.palette"
local Plague = require "src.plague"
local Q = require "src.quarters"
local Glossary = require "src.glossary"
local Help = require "src.ui.help"
local Letters = require "src.ui.letters"
local Diplo = require "src.diplomacy"
local Loyalty = require "src.loyalty"

local floor, max, min = math.floor, math.max, math.min
local text, rect, button, icon = Draw.text, Draw.rect, Draw.button, Draw.icon

local Hud = {}

-- The touch buttons' width.
local TOUCH_W = 26

local function me() return S.game.players[1] end

local function signed(n)
    n = floor(n + 0.5)
    return n >= 0 and ("+" .. n) or tostring(n)
end

--- looking things up --------------------------------------------------------------

-- The last line of a tooltip about glossary page `id`: the key that opens
-- it. Nothing on a touch screen, where the HELP button does.
local function lookUpLine(id)
    if not id or S.touch then return nil end
    return L("{1}: MORE ABOUT {2}", L(Settings.keyName(Settings.key("help"))), Glossary.name(id))
end

-- A tooltip's lines drawn in a box at (x, y): the first pale, the rest
-- cream, and the look-up line, if there is one, dim.
local function tipBox(lines, x, y, look)
    local bw, bh = 0, #lines * 8 + 3
    for _, l in ipairs(lines) do bw = max(bw, Font.width(l)) end
    bw = bw + 6
    rect("o", x, y, bw, bh)
    for k, l in ipairs(lines) do
        text(k == 1 and "w" or (look and k == #lines and "t" or "c"), l, x + 3, y + 2 + (k - 1) * 8)
    end
end

--- what a yield is ---------------------------------------------------------------

-- A tip for the yield whose icon and figure are in the box (x, y, w, h), if
-- the pointer is over it and nothing is in front: its name, then the lines
-- under it. `win`: the window it is in, if any (none for the top bar).
local function yieldTip(x, y, w, h, lines, win, topic)
    local mx, my = S.mouse.x, S.mouse.y
    if not Draw.inside({ x = x, y = y, w = w, h = h }, mx, my) then return end
    for k, l in ipairs(lines) do lines[k] = L(l) end
    local look = lookUpLine(topic)
    if look then lines[#lines + 1] = look end
    Win.over(function()
        -- Asked once every window is placed: whether one is in front.
        if Win.modal() or Win.dragging() then return end
        local front = Win.at(mx, my)
        if (front and front.id) ~= win then return end
        local tw = 0
        for _, l in ipairs(lines) do tw = max(tw, Font.width(l)) end
        local bw, bh = tw + 6, #lines * 8 + 3
        local bx = max(2, min(x, S.vw - bw - 2))
        local by = y + h + 2
        if by + bh > S.vh - 2 then by = max(2, y - bh - 2) end
        S.helpTopic = topic
        tipBox(lines, bx, by, look)
    end)
end

--- the top bar ---------------------------------------------------------------------

local function topBar()
    local g, p = S.game, me()
    rect("u", 0, 0, S.vw, 10)
    rect("o", 0, 10, S.vw, 1)
    S.panels[#S.panels + 1] = { x = 0, y = 0, w = S.vw, h = 11 }
    local gold, sci, cul = g:income(p)
    local x = 3
    -- Each figure's icon and text, and a tip for it under the pointer.
    local function stat(kind, ink, s, lines)
        icon(kind, x, 3, ink)
        text(ink, s, x + 7, 3)
        local w = 7 + Font.width(s)
        yieldTip(x - 1, 0, w + 2, 10, lines, nil, "yield." .. kind)
        x = x + w + 8
    end
    local units, cities = #g:unitsOf(p.id), #g:citiesOf(p.id)
    local free = 2 + cities
    stat("gold", "w", p.gold .. " (" .. signed(gold) .. ")", {
        "GOLD",
        L("{1} IN THE TREASURY, {2} A TURN", p.gold, signed(gold)),
        L("UPKEEP {1}: {2} UNITS, {3} FREE", max(0, units - free), units, free),
        "BUYS WHAT A CITY IS BUILDING",
    })
    stat("science", "c", signed(sci), {
        "SCIENCE",
        L("{1} A TURN", signed(sci)),
        "RESEARCHES TECHNOLOGIES",
    })
    stat("culture", "s", signed(cul), {
        "CULTURE",
        L("{1} A TURN", signed(cul)),
        "EACH CITY CLAIMS A NEW HEX WITH ITS OWN",
    })
    x = x + 2
    -- Research: what, how far, how long. A click opens the list.
    local label
    if p.researching then
        local t = D.TECH[p.researching]
        local turns = sci > 0 and math.ceil(max(0, t.cost - p.science) / sci) or "-"
        label = L(t.name) .. " " .. floor(p.science) .. "/" .. t.cost .. " (" .. turns .. ")"
        local goal = g:researchGoal(p)
        if goal ~= p.researching then label = label .. " > " .. L(D.TECH[goal].name) end
    elseif #g:researchable(p) > 0 then
        label = L"CHOOSE RESEARCH"
    else
        label = L"ALL KNOWN"
    end
    local w = Font.width(label) + 6
    button(label, x, 1, w, 9, function() S.panel = S.panel == "research" and nil or "research" end,
        { strong = not p.researching and #g:researchable(p) > 0 })
    -- The cataclysm, once foretold: its stage and the turns left to the
    -- world, ink on pale, after the research.
    local doom = Cat.label(g)
    local dx = x + w + 8
    if doom then
        rect("w", dx, 1, Font.width(doom) + 6, 9)
        text("o", doom, dx + 3, 3)
        dx = dx + Font.width(doom) + 14
    end
    -- The weather, while a spell lasts (src/weather.lua), and the turns
    -- left of it: pale on dark, so it is not taken for the cataclysm.
    local sky = Weather.label(g)
    if sky then
        rect("o", dx, 1, Font.width(sky) + 6, 9)
        text("w", sky, dx + 3, 3)
        dx = dx + Font.width(sky) + 14
    end
    -- The menu, at the far right.
    button("MENU", S.vw - 25, 1, 24, 9, Menu.openPause)
    local right = L("TURN {1}", g.turn) .. "  " .. D.year(g.turn)
    local rx = S.vw - Font.width(right) - 29
    text("c", right, rx, 3)
    -- Diplomacy, left of the turn: lit while letters wait on an answer
    -- (src/ui/letters.lua).
    local dl, waiting = Letters.barLabel()
    local bw = Font.width(dl) + 14
    local bx = rx - bw - 6
    if bx > dx + 4 then
        button(dl, bx, 1, bw, 9, function() S.panel = S.panel == "diplomacy" and nil or "diplomacy" end,
            { strong = waiting, icon = "letter" })
        rx = bx
    end
    -- The clock's strip, if that is its look, left of the turn.
    Clock.inBar(rx - 4)
end

--- news ----------------------------------------------------------------------------

local function messages(dt)
    local y = 14
    for k, m in ipairs(S.msgs) do
        m.t = m.t + dt
        if m.t < Settings.get("newsTime") then
            local w = Font.width(m.text)
            rect("o", 2, y - 1, w + 4, 7)
            text(k == 1 and "w" or "c", m.text, 4, y)
            y = y + 8
        end
    end
end

--- a unit's panel -------------------------------------------------------------------

local function unitPanel(u)
    local g = S.game
    local def = u.def
    local acts = O.actions(u)
    local w = 168
    -- The orders' buttons, in rows as many as they need: { a, x, row }.
    local laid, bx, row = {}, 3, 0
    for _, a in ipairs(acts) do
        local bw = Font.width(L(a.label)) + 8
        if bx > 3 and bx + bw > w - 3 then bx, row = 3, row + 1 end
        laid[#laid + 1] = { a = a, x = bx, w = bw, row = row }
        bx = bx + bw + 2
    end
    -- What it is doing, at the right of the buttons' last row, or on a row
    -- of its own if it won't fit there.
    local status = (u.sick and "CARRIES THE PLAGUE") or u.fortified and "FORTIFIED" or (u.sleep and "ASLEEP")
        or (u.dest and "ON THE MOVE") or (g:embarked(u) and "EMBARKED") or nil
    status = L(status)
    local statusRow = row
    if status and bx + Font.width(status) + 4 > w then statusRow = row + 1 end
    local h = Win.BAR + 1 + 28 + statusRow * 13
    local rank = D.rank(u.xp)
    local name = rank and L(rank.name .. " {1}", def.name) or L(def.name)
    local who = (u.owner == 1 or u.owner == g.WILD) and name or L("civ|{1} {2}", g.players[u.owner].name, name)
    Win.add({ id = "unit", title = who, w = w, h = h, x = 2, y = S.vh - h - 2,
        close = function() O.select(nil) end,
        draw = function(x, y)
            local team = Board.TEAM[g.players[u.owner].civ.look]
            rect("o", x + 3, y + 2, 9, 9)
            rect(team.fill, x + 4, y + 3, 7, 7)
            icon(u.kind, x + 5, y + 4, team.ink)
            local stats = {}
            local embarked = g:embarked(u)
            if embarked then stats[#stats + 1] = L("STR {1}", D.EMBARK.str)
            elseif def.str > 0 then stats[#stats + 1] = L("STR {1}", def.str) end
            if def.ranged then stats[#stats + 1] = L("RNG {1}/{2}", def.ranged, def.range) end
            stats[#stats + 1] = L("HP {1}", max(0, u.hp))
            stats[#stats + 1] = L("MOVES {1}/{2}", u.moves, g:maxMoves(u))
            if def.charges then stats[#stats + 1] = L("BUILDS {1}", u.charges) end
            if def.hide then stats[#stats + 1] = L"HIDE" end
            text("c", table.concat(stats, "  "), x + 15, y + 4)
            if status then text("s", status, x + w - Font.width(status) - 4, y + 18 + statusRow * 13) end
            for _, l in ipairs(laid) do
                local a = l.a
                button(a.label, x + l.x, y + 14 + l.row * 13, l.w, 11, a.fn,
                    { off = a.off or u.moves <= 0 and a.label ~= "WAKE" and a.label ~= "REFIT" })
            end
        end })
end

--- a city's panel ---------------------------------------------------------------------

local function costOf(it) return it.def.cost end

-- The build list's sections: units, what the city builds for itself, and
-- what holds the cataclysm off.
local SECTIONS = { unit = "UNITS", building = "CITY", ward = "AGAINST THE END" }
local function sectionOf(it)
    if it.kind == "unit" then return "unit" end
    return it.def.ward and "ward" or "building"
end

-- How many sections a build list has, each with a heading.
local function sectionCount(items)
    local n, last = 0, nil
    for _, it in ipairs(items) do
        local sec = sectionOf(it)
        if sec ~= last then n, last = n + 1, sec end
    end
    return n
end

-- What a unit is, for its tooltip in the build list.
local function unitSays(def, geared)
    local out = {}
    if def.str > 0 then
        local s = L("STRENGTH {1}", def.str)
        if def.ranged then s = s .. L(", RANGED {1} AT {2}", def.ranged, def.range) end
        out[#out + 1] = s
    end
    out[#out + 1] = def.sea and L("MOVES {1}, AT SEA", def.moves) or L("MOVES {1}", def.moves)
    if def.pop then out[#out + 1] = L("FOUNDS A CITY; TAKES {1} CITIZEN", def.pop) end
    if def.charges then out[#out + 1] = L("IMPROVES THE LAND {1} TIMES", def.charges) end
    if geared then out[#out + 1] = L"ITS GEAR IS CHOSEN UNDER WHAT IS BUILDING" end
    return out
end

-- The tooltip by the city's window for the build list's row under the
-- pointer: its name, then what it does.
local function buildTip(name, says, wx, rowY, topic)
    local lines = { L(name) }
    for _, l in ipairs(says) do lines[#lines + 1] = L(l) end
    local look = lookUpLine(topic)
    if look then lines[#lines + 1] = look end
    Win.over(function()
        local w = 0
        for _, l in ipairs(lines) do w = max(w, Font.width(l)) end
        local bw, bh = w + 6, #lines * 8 + 3
        local x = wx - bw - 2
        if x < 0 then x = wx + 2 end
        local y = max(12, min(rowY, S.vh - bh - 2))
        S.helpTopic = topic
        tipBox(lines, x, y, look)
    end)
end

local cityBody

-- What a band or a ship being made (or refitted) could carry, slot by
-- slot: { label, on, gear } for a row of buttons, the gear each would
-- give it.
local function gearChoices(c)
    local g, p, b = S.game, me(), c.build
    if not (b and b.gear and D.UNITS[b.id].geared) then return nil end
    local out = {}
    local function with(slot, id)
        local gear = D.copyGear(b.gear)
        gear[slot] = id
        return gear
    end
    if not D.UNITS[b.id].armed then
        out[#out + 1] = { label = L"NONE", on = b.gear.weapon == nil, gear = with("weapon", nil) }
    end
    local weapons = g:gearFor(p, b.id, "weapon")
    -- A weapon taken from the fallen stays on the list for a refit.
    if b.gear.weapon and not g:canMake(p, b.gear.weapon) then table.insert(weapons, 1, b.gear.weapon) end
    for _, id in ipairs(weapons) do
        out[#out + 1] = { label = L(D.GEAR[id].name), on = b.gear.weapon == id, gear = with("weapon", id) }
    end
    for _, id in ipairs(g:gearFor(p, b.id, "mount")) do
        out[#out + 1] = { label = L(D.GEAR[id].name), on = b.gear.mount == id,
            gear = with("mount", b.gear.mount ~= id and id or nil) }
    end
    return out
end

local function cityPanel(c)
    local g = S.game
    local mine = c.owner == 1
    local w = 150
    local items = mine and g:buildable(c) or {}
    local h = 70 + (mine and (#items * 10 + sectionCount(items) * 9 + 14 + 11) or 0) + (Cat.is(g, "plague") and Cat.stage(g) and 11 or 0)
        + (mine and gearChoices(c) and 12 or 0)
    h = min(h, S.vh - 13 - 24)
    local cap = c.capital and L" (CAPITAL)" or ""
    Win.add({ id = "city", title = c.name .. cap, w = w, h = h,
        x = S.vw - w - 2 - (S.touch and TOUCH_W + 2 or 0), y = 13,
        close = function() S.selected = nil end,
        -- What's in it is laid out from the window's top, as its title bar
        -- takes the room a heading had.
        draw = function(x, y) cityBody(c, x, y - Win.BAR - 1, w, h, mine, items) end })
end

function cityBody(c, x, y, w, h, mine, items)
    local g = S.game
    local f, p, gold, sci, cul = g:cityYield(c)
    local surplus = f - c.pop * 2
    local need = g:growthNeed(c)
    local grow
    -- Out of room (src/quarters.lua): slower, or not at all.
    local pace = Q.pace(g, c)
    if surplus > 0 and pace < 1 then surplus = surplus * pace end
    if surplus > 0 then grow = L("GROWS IN {1} TURNS", math.ceil((need - c.food) / surplus))
    elseif pace == 0 and f - c.pop * 2 > 0 then grow = L"GROWS IN NO ROOM"
    elseif surplus < 0 then grow = L"GROWS IN STARVING" else grow = L"GROWS IN STAGNANT" end

    text("c", L("CITIZENS {1}/{2}", c.pop, Q.housing(g, c)) .. "   " .. L("HP {1}", max(0, c.hp) .. "/" .. g:maxHp(c)), x + 4, y + 12)
    icon("food", x + 4, y + 20, "w")
    text("w", signed(floor(surplus * 10 + 0.5) / 10) .. "  " .. c.food .. "/" .. need .. "  " .. grow, x + 11, y + 20)
    yieldTip(x + 3, y + 19, w - 6, 7, {
        "FOOD",
        L("{1} MADE, {2} EATEN BY {3} CITIZENS", floor(f * 10 + 0.5) / 10, c.pop * 2, c.pop),
        L("{1}/{2} STORED TO GROW", c.food, need),
    }, "city")
    local line = y + 28
    icon("prod", x + 4, line, "c")
    text("c", tostring(p), x + 11, line)
    yieldTip(x + 3, line - 1, 26, 7, { "PRODUCTION", "BUILDS UNITS AND BUILDINGS" }, "city")
    icon("gold", x + 30, line, "c")
    text("c", tostring(gold), x + 37, line)
    yieldTip(x + 29, line - 1, 26, 7, { "GOLD", "GOES TO THE TREASURY" }, "city")
    icon("science", x + 56, line, "c")
    text("c", tostring(floor(sci * 10) / 10), x + 63, line)
    yieldTip(x + 55, line - 1, 30, 7, { "SCIENCE", "GOES TO RESEARCH" }, "city")
    icon("culture", x + 86, line, "c")
    text("c", tostring(cul), x + 93, line)
    yieldTip(x + 85, line - 1, w - 89, 7, {
        "CULTURE",
        L("{1}/{2} TO THE NEXT HEX", floor(c.culture), g:borderNeed(c)),
    }, "city")
    -- What it has built, in the build list's order; short names if the
    -- long ones won't fit on a line.
    local ids = {}
    for id in pairs(c.buildings) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return D.BUILDINGS[a].order < D.BUILDINGS[b].order end)
    local long, short = {}, {}
    for _, id in ipairs(ids) do
        long[#long + 1] = L(D.BUILDINGS[id].name)
        short[#short + 1] = L("short|" .. D.BUILDINGS[id].short)
    end
    local line2 = table.concat(long, " ")
    if Font.width(line2) > w - 8 then line2 = table.concat(short, " ") end
    -- Its loyalty (src/loyalty.lua): a bar, how it moves, and why.
    local tipLines, delta = Letters.loyaltyTip(c)
    local loyal = floor(Loyalty.of(c))
    local state = Loyalty.state(c)
    local ls = L("LOYALTY {1}", loyal) .. " (" .. signed(delta) .. ")"
    text(state and "w" or "c", ls, x + 4, y + 36)
    local lbx = x + 8 + Font.width(ls)
    local lbw = w - (lbx - x) - 6 - (state and Font.width(L(state)) + 4 or 0)
    rect("o", lbx, y + 37, lbw, 3)
    rect(state == "UPRISING" and "s" or (state and "c" or "w"), lbx, y + 38, max(1, floor(lbw * loyal / 100)), 1)
    if state then
        local on = state ~= "UPRISING" or floor(S.clock * 2) % 2 == 0
        text(on and "w" or "s", state, x + w - 4 - Font.width(L(state)), y + 36)
    end
    yieldTip(x + 3, y + 35, w - 6, 7, tipLines, "city", "idea.loyalty")
    text("s", #ids > 0 and line2 or "NO BUILDINGS", x + 4, y + 44)
    local yy = y + 53
    -- What the city weighs first in working its land (D.FOCUS).
    if mine then
        text("s", L"FOCUS", x + 4, yy)
        local bx = x + 8 + Font.width(L"FOCUS")
        for _, id in ipairs(D.FOCUS_ORDER) do
            local label = L("short|" .. D.FOCUS[id].short)
            local bw = Font.width(label) + 6
            button(label, bx, yy - 2, bw, 10, function() g:setFocus(c, id) end,
                { on = (c.focus or "balanced") == id })
            bx = bx + bw + 2
        end
        yy = yy + 11
    end
    -- The plague (src/plague.lua): how the town is, and its gates.
    if Cat.is(g, "plague") and Cat.stage(g) then
        local how
        if c.sick then how = L("SICK {1} TURNS", c.sick - 1)
        elseif Plague.immune(g, c) then how = L("MENDED: SPARED {1} TURNS", c.immune - g.turn)
        else how = L"WELL" end
        if c.dead then how = how .. "  " .. L("DEAD {1}", c.dead) end
        text(c.sick and "w" or "c", how, x + 4, yy)
        if mine then
            button(c.shut and "act|OPEN" or "act|SHUT", x
 + w - 34, yy - 2, 30, 10, function() Plague.setShut(g, c) end,
                { on = c.shut })
        elseif c.shut then
            text("s", L"SHUT", x + w - 4 - Font.width(L"SHUT"), yy)
        end
        yy = yy + 11
    end
    if not mine then return end
    -- What it is building, and what it could.
    if c.build then
        local def = g:buildDef(c.build)
        text("w", L(def.name) .. " " .. floor(c.prod) .. "/" .. def.cost .. " (" .. g:turnsFor(c, def.cost) .. ")", x + 4, yy)
        Draw.bar(x + 4, yy + 7, w - 50, c.prod / def.cost, "w", "o")
        local cost = g:buyCost(c)
        local can = cost and me().gold >= cost and not c.bought
        if c.build.refit and not g:refitReady(c) then can = false end
        button(L("BUY {1}", cost), x + w - 44, yy - 2, 40, 10, function() g:buy(c) end, { off = not can })
    else
        text("w", "CHOOSE WHAT TO BUILD", x + 4, yy)
    end
    yy = yy + 13
    -- What the band or ship under way carries: a button for each piece.
    local choices = gearChoices(c)
    if choices then
        local bx = x + 3
        for _, ch in ipairs(choices) do
            local bw = Font.width(ch.label) + 6
            button(ch.label, bx, yy - 1, bw, 10, function()
                local b = c.build
                if b.refit then
                    local u = g:unitById(b.refit)
                    if u then g:refit(u, ch.gear) end
                else
                    g:setBuild(c, "unit", b.id, ch.gear)
                end
            end, { on = ch.on })
            bx = bx + bw + 2
        end
        yy = yy + 12
    end
    local section
    for _, it in ipairs(items) do
        -- A heading where a section starts.
        local sec = sectionOf(it)
        if sec ~= section then
            if yy + 19 > y + h - 2 then break end
            section = sec
            local head = L(SECTIONS[sec])
            text("s", head, x + 4, yy + 2)
            rect("k", x + 6 + Font.width(head), yy + 4, w - 10 - Font.width(head), 1)
            yy = yy + 9
        end
        if yy + 10 > y + h - 2 then break end
        local cost = costOf(it)
        local on = c.build and c.build.kind == it.kind and (c.build.id == it.id or it.kind == "quarter") and not c.build.refit
        -- A band or a ship: named as such, costed as what it carries now.
        local label = L(it.def.name)
        if it.gear then
            label = L(D.UNITS[it.id].name)
            if on then cost = g:buildDef(c.build).cost end
        end
        local turns = g:turnsFor(c, cost, on and c.prod or 0)
        local note = (it.kind == "unit" and it.def.pop and c.pop <= it.def.pop) and L"NEEDS 2 POP" or L("{1}  {2}T", cost, turns)
        local hot = button(label, x + 3, yy, w - 6, 10, function()
            -- A quarter: its hex is chosen on the map.
            if it.kind == "quarter" then O.placeQuarter(c)
            elseif not on then g:setBuild(c, it.kind, it.id, it.gear) end
        end, { on = on, left = true, icon = it.kind == "unit" and it.id or it.def.icon or "city" })
        text(hot and "o" or "u", note, x + w - 5 - Font.width(note), yy + 3)
        if hot then
            local def = (it.gear and on) and g:buildDef(c.build) or it.def
            local topic = it.kind == "unit" and Glossary.forUnit(def.kind or it.id)
                or (it.kind == "building" and "building." .. it.id) or nil
            buildTip(def.name, it.kind == "unit" and unitSays(def, it.gear ~= nil) or (def.says or {}), x, yy, topic)
        end
        yy = yy + 10
    end
end

--- research ------------------------------------------------------------------------

-- The research panel: the technologies as a tree, a column for each tier
-- and a line from each to what it leads to, where the screen is wide
-- enough; else a list, a branch at a time, each indented under its root.
-- A click on one not yet learnable sets research on the way to it, the
-- rest queued (Game:researchToward). The tooltip over one says what it
-- unlocks, what it needs and what it leads to.

local NODE_H, PITCH, GAP, PAD = 19, 22, 16, 4

local function turnsFor(p, sci, cost)
    return sci > 0 and math.ceil(max(0, cost) / sci) or "-"
end

-- The way to `id` from here: { techs, science, turns }, science already
-- put by counted against the first.
local function wayTo(g, p, sci, id)
    local path, cost = g:researchPath(p, id), 0
    for _, t in ipairs(path) do cost = cost + D.TECH[t].cost end
    return #path, cost, turnsFor(p, sci, cost - p.science)
end

-- Where `id` stands: "known", "now" (under way), "queued", "can" or "locked";
-- and for one queued, its place in the queue.
local function standing(g, p, id)
    if p.techs[id] then return "known" end
    if p.researching == id then return "now" end
    for k, q in ipairs(p.queue or {}) do if q == id then return "queued", k end end
    return g:canResearch(p, id) and "can" or "locked"
end

-- Does it unlock a ward against the cataclysm foretold?
local function doomWard(g, id)
    if not Cat.stage(g) then return false end
    for _, u in ipairs(D.unlocks(id)) do
        if u.ward and u.ward ~= "any" and g:wardsOff(u) then return true end
    end
    return false
end

local function namesOf(ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = L(D.TECH[id].name) end
    return table.concat(out, ", ")
end

-- The tooltip by a technology: what it unlocks, then where it sits.
local function researchTip(g, p, sci, t, nx, ny, nw)
    local lines = { L(t.name) }
    for _, u in ipairs(D.unlocks(t.id)) do
        local line = "  " .. L(u.name)
        if u.ward and u.ward ~= "any" then line = line .. L" (WARD)" end
        lines[#lines + 1] = line
    end
    if doomWard(g, t.id) then lines[#lines + 1] = L"HOLDS OFF WHAT IS COMING" end
    if #t.needs > 0 then lines[#lines + 1] = L("NEEDS {1}", namesOf(t.needs)) end
    if #t.leads > 0 then lines[#lines + 1] = L("LEADS TO {1}", namesOf(t.leads)) end
    local st = standing(g, p, t.id)
    if st == "locked" or st == "queued" then
        local n, cost, turns = wayTo(g, p, sci, t.id)
        lines[#lines + 1] = L("THE WAY: {1} TECHS, {2} SCIENCE, {3}T", n, cost, turns)
    end
    local topic = "tech." .. t.id
    local look = lookUpLine(topic)
    if look then lines[#lines + 1] = look end
    Win.over(function()
        local w = 0
        for _, l in ipairs(lines) do w = max(w, Font.width(l)) end
        local bw, bh = w + 6, #lines * 8 + 3
        local x = nx + nw + 3
        if x + bw > S.vw then x = nx - bw - 3 end
        x = max(0, x)
        local y = max(12, min(ny, S.vh - bh - 2))
        S.helpTopic = topic
        tipBox(lines, x, y, look)
    end)
end

local function choose(g, p, id)
    if p.techs[id] then return end
    g:researchToward(p, id)
end

-- The short note on a technology's right: its cost, its place in the
-- queue, or that it is known or under way.
local function noteOf(t, st, k)
    if st == "known" then return "" end
    if st == "now" then return L"NOW" end
    if st == "queued" then return tostring(k + 1) end
    return tostring(t.cost)
end

local function nodeWidth()
    local w = 0
    for _, t in ipairs(D.TECHS) do w = max(w, Font.width(L(t.name)) + Font.width("100") + 9) end
    return w
end

local TIERS, ROWS = 0, 0
for _, t in ipairs(D.TECHS) do TIERS, ROWS = max(TIERS, t.tier), max(ROWS, t.row + 1) end

-- The tree's size, and whether the screen has room for it.
local function treeSize()
    local nw = nodeWidth()
    local w = PAD * 2 + TIERS * nw + (TIERS - 1) * GAP
    local h = Win.BAR + 4 + floor((ROWS - 1) * PITCH) + NODE_H + 4 + 12
    return w, h, nw
end
local function treeFits()
    local w, h = treeSize()
    return w <= S.vw - 4 and h <= S.vh - 14
end

-- A technology in the tree: a button with its name and note, and under
-- them a little picture for each thing it unlocks.
local function treeNode(g, p, sci, t, x, y, nw)
    local st, k = standing(g, p, t.id)
    local hot = button("", x, y, nw, NODE_H, function() choose(g, p, t.id) end,
        { on = st == "known", strong = st == "now" or st == "queued" })
    local ink = st == "locked" and "u" or "o"
    text(ink, L(t.name), x + 3, y + 3)
    local note = noteOf(t, st, k)
    text(ink, note, x + nw - 3 - Font.width(note), y + 3)
    local ix = x + 3
    for _, u in ipairs(D.unlocks(t.id)) do
        icon(u.icon, ix, y + 11, ink)
        ix = ix + 7
    end
    if doomWard(g, t.id) then
        rect("o", x + nw - 10, y + 10, 8, 7)
        icon("star", x + nw - 9, y + 11, "w")
    end
    if hot then researchTip(g, p, sci, t, x, y, nw) end
end

-- Where each technology sits in the tree, its left and top.
local function treeAt(t, x, y, nw)
    return x + PAD + (t.tier - 1) * (nw + GAP), y + 4 + floor(t.row * PITCH)
end

local function treeBody(x, y, w, nw)
    local g, p = S.game, me()
    local _, sci = g:income(p)
    -- The way being made: what is under way and queued, lines and all.
    local onWay = {}
    if p.researching then onWay[p.researching] = true end
    for _, q in ipairs(p.queue or {}) do onWay[q] = true end
    -- The lines first, under the technologies: out of the parent's right,
    -- down (or up) in the gap between the columns, into the child's left.
    -- Each parent turns at its own place in the gap, so lines from two
    -- parents never run together.
    local turnAt = {}
    for _, t in ipairs(D.TECHS) do
        local n = 0
        for _, o in ipairs(D.TECHS) do
            if o.tier == t.tier and o.row < t.row then n = n + 1 end
        end
        turnAt[t.id] = 4 + (n % 3) * 4
    end
    for pass = 1, 2 do
        for _, t in ipairs(D.TECHS) do
            for _, need in ipairs(t.needs) do
                local lit = onWay[t.id] and (onWay[need] or p.techs[need])
                if (pass == 2) == (lit and true or false) then
                    local px, py = treeAt(D.TECH[need], x, y, nw)
                    local cx, cy = treeAt(t, x, y, nw)
                    local k = lit and "w" or "n"
                    local x1, y1, y2 = px + nw, py + 9, cy + 9
                    local ex = x1 + turnAt[need]
                    rect(k, x1, y1, ex - x1 + 1, 1)
                    rect(k, ex, min(y1, y2), 1, math.abs(y2 - y1) + 1)
                    rect(k, ex, y2, cx - ex, 1)
                end
            end
        end
    end
    for _, t in ipairs(D.TECHS) do
        local nx, ny = treeAt(t, x, y, nw)
        treeNode(g, p, sci, t, nx, ny, nw)
    end
    -- At the foot, where research is making for.
    local fy = y + 4 + floor((ROWS - 1) * PITCH) + NODE_H + 4
    local goal = g:researchGoal(p)
    local line
    if goal then
        local n, cost, turns = wayTo(g, p, sci, goal)
        line = L("MAKING FOR {1}: {2} TECHS, {3} SCIENCE, {4}T", L(D.TECH[goal].name), n, cost, turns)
        if n == 1 then line = L("RESEARCHING {1}: {2} SCIENCE, {3}T", L(D.TECH[goal].name), cost, turns) end
    else
        line = L"CHOOSE A TECHNOLOGY; ONE FURTHER ON QUEUES THE WAY TO IT"
    end
    text("c", line, x + PAD, fy + 2)
end

-- The list, for a screen with no room for the tree: a branch at a time,
-- each indented by its tier with a line from its root.
local function listRow(g, p, sci, t)
    local st, k = standing(g, p, t.id)
    local note
    if st == "known" then note = L"KNOWN"
    elseif st == "now" then note = L("{1}  {2}T", t.cost, turnsFor(p, sci, t.cost - p.science))
    elseif st == "queued" then note = L("NEXT {1}", k + 1)
    elseif st == "can" then note = L("{1}  {2}T", t.cost, turnsFor(p, sci, t.cost - p.science))
    else note = L("NEEDS {1}", namesOf(t.needs)) end
    return st, note
end

local function listSize()
    local g, p = S.game, me()
    local _, sci = g:income(p)
    local w = 160
    for _, t in ipairs(D.TECHS) do
        local _, note = listRow(g, p, sci, t)
        w = max(w, (t.tier - 1) * 6 + Font.width(L(t.name)) + Font.width(note) + 22)
    end
    return min(w, S.vw - 4), Win.BAR + 4 + #D.TECHS * 11 + 4
end

local function listBody(x, y, w)
    local g, p = S.game, me()
    local _, sci = g:income(p)
    local yy = y + 4
    for _, t in ipairs(D.TECHS) do
        local st, note = listRow(g, p, sci, t)
        local ind = (t.tier - 1) * 6
        if t.tier > 1 then
            rect("n", x + 3 + ind - 4, yy - 1, 1, 6)
            rect("n", x + 3 + ind - 4, yy + 5, 3, 1)
        end
        local bx, bw = x + 3 + ind, w - 6 - ind
        local hot = button(L(t.name), bx, yy, bw, 10, function() choose(g, p, t.id) end,
            { on = st == "known", strong = st == "now" or st == "queued", left = true })
        text(st == "locked" and "u" or "o", note, bx + bw - 3 - Font.width(note), yy + 3)
        if hot then researchTip(g, p, sci, t, bx, yy, bw) end
        yy = yy + 11
    end
end

local function researchPanel()
    local tree = treeFits()
    local w, h, nw
    if tree then w, h, nw = treeSize() else w, h = listSize() end
    h = min(h, S.vh - 14)
    Win.add({ id = "research", title = "RESEARCH", w = w, h = h,
        x = floor((S.vw - w) / 2), y = max(14, floor((S.vh - h) / 2) - 10),
        close = function() S.panel = nil end,
        draw = function(x, y)
            if tree then treeBody(x, y, w, nw) else listBody(x, y, w) end
        end })
end

--- the hex under the pointer --------------------------------------------------------

local function tooltip()
    local g, cell = S.game, S.hover
    if not cell or not me().explored[cell.id] then return end
    local lines = {}
    local f, p, gold = g:yield(cell)
    local head = g:describe(cell)
    if cell.elev ~= "mountain" then head = head .. "   " .. L("{1}F {2}P {3}G", f, p, gold) end
    lines[1] = head
    local river = g:riverName(cell)
    if river then lines[#lines + 1] = L("BY THE {1}", river) end
    -- Where it lies under the still sun (src/stillsun.lua).
    local K = Cat.kindOf(g)
    local where = K and K.describe and K.describe(g, cell)
    if where then lines[#lines + 1] = where:sub(3) end
    if cell.lair then
        local l = cell.lair.def
        lines[#lines + 1] = l.sting and L"A SOLDIER CAN TAKE THEIR HONEY, AND BE STUNG"
            or L("A SOLDIER WALKING IN CLEARS IT: +{1} GOLD", l.prize.gold)
    end
    if cell.owner then
        local owner = g.players[cell.owner]
        local line = (cell.city and cell.city.name or (cell.ownerCity and cell.ownerCity.name or "")) .. " - " .. owner.name
        -- How we stand with them (src/diplomacy.lua).
        if cell.owner ~= 1 and Diplo.met(g, 1, cell.owner) then
            line = line .. " (" .. L(Diplo.stance(g, 1, cell.owner)) .. ")"
            if not Diplo.mayEnter(g, 1, cell.owner) then lines[#lines + 1] = line line = L"BORDERS CLOSED TO US" end
        end
        lines[#lines + 1] = line
        local city = cell.city
        if city and Loyalty.state(city) then
            lines[#lines + 1] = L("{1}: LOYALTY {2}", L(Loyalty.state(city)), floor(Loyalty.of(city)))
        end
    end
    if me().visible[cell.id] then
        for _, u in ipairs({ g.mil[cell.id], g.civ[cell.id] }) do
            if u and u.owner == g.WILD then
                local d = u.def
                local how = d.temper == "hostile" and "HOSTILE" or (d.temper == "neutral" and "FIGHTS IF HUNTED"
                    or (d.vermin and "BRINGS THE PLAGUE" or "SHY"))
                lines[#lines + 1] = L(d.name) .. " - " .. L(how) .. " - " .. L("STR {1}", d.str + Beasts.nightBonus(g, u))
                    .. " " .. L("{1}HP", u.hp)
                if d.night then lines[#lines + 1] = D.night(g.turn, g, cell) and L("HUNTING BY NIGHT: +{1} STRENGTH", d.night)
                    or L"STRONGER AT NIGHT" end
                if d.across then lines[#lines + 1] = L"STRIKES WHAT CROSSES ITS RIVER" end
                if d.tame then
                    lines[#lines + 1] = me().techs[d.tame] and L"COME NEXT TO THEM WITH A SOLDIER TO TAME THEM"
                        or L"HORSEBACK RIDING TAMES THEM"
                end
            elseif u and u.owner ~= 1 then
                lines[#lines + 1] = L("civ|{1} {2}", g.players[u.owner].name, u.def.name) .. " " .. L("{1}HP", u.hp)
                    .. " (" .. L(Diplo.stance(g, 1, u.owner)) .. ")"
            end
        end
    end
    local sel = S.selected and S.selected.unit
    local peace = sel and sel.owner == 1 and not sel.def.civilian and g:atPeaceWith(1, cell)
    if peace and g:dist(g.cells[sel.cell], cell) <= (sel.def.ranged and sel.def.range or 1) then
        lines[#lines + 1] = L("AT PEACE WITH {1}: ATTACKING DECLARES WAR", g.players[peace].name)
    end
    if sel and sel.owner == 1 and g:canAttack(sel, cell) then
        local dealt, taken = g:forecast(sel, cell)
        lines[#lines + 1] = L("ATTACK: DEALS ABOUT {1}, TAKES ABOUT {2}", dealt, taken)
        if not sel.def.ranged and g:riverBetween(g.cells[sel.cell], cell) then
            lines[#lines + 1] = L("ACROSS THE RIVER: -{1} STRENGTH", D.RIVER.attack)
        end
    elseif sel and sel.owner == 1 and S.hoverTurns and cell.id ~= sel.cell then
        local move = S.hoverTurns == 1 and L"MOVE: 1 TURN" or L("MOVE: {1} TURNS", S.hoverTurns)
        if g:dist(g.cells[sel.cell], cell) == 1 and not sel.def.sea and g:passable(g.cells[sel.cell]) and g:passable(cell)
            and g:fords(g.cells[sel.cell], cell) then
            move = move .. L", FORDING THE RIVER"
        end
        lines[#lines + 1] = move
    end
    local topic = Glossary.forCell(g, cell, me())
    S.helpTopic = topic
    local look = lookUpLine(topic)
    if look then lines[#lines + 1] = look end
    local w = 0
    for _, l in ipairs(lines) do w = max(w, Font.width(l)) end
    local x = floor((S.vw - w) / 2) - 3
    local y = S.vh - 9 * #lines - 4
    -- On a narrow screen it goes up, clear of the unit's panel and the turn's buttons.
    if x + w + 6 > S.vw - 118 then y = y - 42 end
    -- Clear of the windows, too, as they were last drawn: above one, or
    -- else beside it.
    local bw, bh = w + 6, #lines * 8 + 3
    local function hit(tx, ty)
        for _, r in ipairs(Win.rects or {}) do
            if tx < r.px + r.w and tx + bw > r.px and ty < r.py + r.h and ty + bh > r.py then return r end
        end
    end
    for _ = 1, 4 do
        local r = hit(x, y)
        if not r then break end
        if r.py - bh - 1 >= 12 then y = r.py - bh - 1
        elseif r.px - bw - 1 >= 0 then x = r.px - bw - 1
        elseif r.px + r.w + bw + 1 <= S.vw then x = r.px + r.w + 1
        else break end
    end
    tipBox(lines, x, y, look)
end

--- the minimap ---------------------------------------------------------------------

local MINI = { ocean = "u", coast = "n", grass = "k", plains = "t", desert = "c", marsh = "n", tundra = "s", snow = "w",
    ice = "c", saltflat = "w" }

-- The minimap's hexes as last drawn onto its canvas.
local mini = { look = {} }

local function minimap()
    local g = S.game
    local mw, mh = g.cols * 2 + 1, g.rows * 2
    local x, y = S.vw - mw - 4, S.vh - 22 - mh - 4
    rect("o", x - 2, y - 2, mw + 4, mh + 4)
    S.panels[#S.panels + 1] = { x = x - 2, y = y - 2, w = mw + 4, h = mh + 4, fn = function(mx, my)
        local c, r = floor((mx - x - (floor((my - y) / 2) % 2)) / 2), floor((my - y) / 2)
        local cell = g:cell(max(0, min(g.cols - 1, c)), max(0, min(g.rows - 1, r)))
        if cell then View.lookAt(cell) end
    end }
    local p = me()
    local night = Cat.is(g, "sun") and g.cataclysm.line and {} or nil
    if night then
        for _, cell in ipairs(g.cells) do night[cell.id] = D.sunSide(g, cell.x, cell.z) end
    end
    -- Each hex as it shows, as a number: its key, a river's speck, a town's
    -- ink. The hexes are drawn onto a canvas of their own only when one of
    -- them shows otherwise than when last drawn; the canvas is drawn every
    -- frame. (No two hexes' pixels meet, so what is drawn over a hex later,
    -- a sick town's blink, comes out as if drawn in among them.)
    local again = not mini.canvas or mini.game ~= g or mini.w ~= mw or mini.h ~= mh
    local look, IDX = mini.look, T.IDX
    for _, cell in ipairs(g.cells) do
        local v
        if p.explored[cell.id] then
            local k = cell.elev == "mountain" and "s" or MINI[cell.terrain]
            if cell.owner then k = Board.TEAM[g.players[cell.owner].civ.look].fill end
            -- Under the still sun, the night side a step darker, the
            -- twilight half so.
            local zone = night and Cat.KINDS.sun.zone(g, cell)
            if zone == "night" or (zone == "twilight" and (cell.c + cell.r) % 2 == 0 and (night[cell.id] or 0) < 0) then
                k = Palette.darker[k]
            end
            -- A river's course, a dark speck in each hex along it.
            v = IDX[k] * 4 + ((not cell.owner and g:onRiver(cell)) and 2 or 0) + (cell.city and 1 or 0)
        else
            v = (cell.c + cell.r) % 2 == 0 and -1 or -2
        end
        if look[cell.id] ~= v then look[cell.id], again = v, true end
    end
    if again then
        if not mini.canvas or mini.w ~= mw or mini.h ~= mh then
            mini.canvas = love.graphics.newCanvas(mw, mh)
            mini.canvas:setFilter("nearest", "nearest")
        end
        mini.game, mini.w, mini.h = g, mw, mh
        love.graphics.push("all")
        love.graphics.setCanvas(mini.canvas)
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 0)
        for _, cell in ipairs(g.cells) do
            local px, py = cell.c * 2 + cell.r % 2, cell.r * 2
            local v = look[cell.id]
            if v < 0 then
                rect(v == -1 and "c" or "s", px, py, 2, 2)
            else
                rect(T.KEYS[floor(v / 4)], px, py, 2, 2)
                if v % 4 >= 2 then rect("u", px + 1, py + 1, 1, 1) end
                if v % 2 == 1 then rect("o", px, py, 2, 1) end
            end
        end
        love.graphics.pop()
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(mini.canvas, x, y)
    -- A sick town blinks pale.
    if floor(S.clock * 2) % 2 == 0 then
        for _, c in ipairs(g.cities) do
            local cell = g.cells[c.cell]
            if c.sick and p.explored[cell.id] then rect("w", x + cell.c * 2 + cell.r % 2, y + cell.r * 2, 2, 2) end
        end
    end
    -- What the board shows now.
    local i0, j0 = S.camx, S.camy
    local x0, z0 = T.onLevel(i0 + S.world.i0, j0 + S.world.j0, 4)
    local x1, z1 = T.onLevel(i0 + S.cw + S.world.i0, j0 + S.ch + S.world.j0, 4)
    local fx0, fx1 = x + x0 / H.W * 2, x + x1 / H.W * 2
    local fy0, fy1 = y + z0 / H.ROW * 2 - 1, y + z1 / H.ROW * 2 - 1
    fx0, fx1 = max(x - 1, fx0), min(x + mw, fx1)
    fy0, fy1 = max(y - 1, fy0), min(y + mh, fy1)
    if fx1 > fx0 and fy1 > fy0 then Draw.frame("w", fx0, fy0, fx1 - fx0 + 1, fy1 - fy0 + 1) end
end

--- touch -----------------------------------------------------------------------------

-- What the keys and the wheel do, for fingers.
local function touchButtons()
    local x, y = S.vw - TOUCH_W - 2, 13
    local function zoom(step) View.zoom(step, love.graphics.getWidth() / 2, love.graphics.getHeight() / 2) end
    local list = {
        { "+", function() zoom(1) end },
        { "-", function() zoom(-1) end },
        { "NEXT", function() O.nextUnit(S.selected and S.selected.unit) end },
        { "HOME", function()
            local cap = S.game:citiesOf(1)[1]
            if cap then O.select(cap, true) end
        end },
        { "GRID", O.toggleGrid, S.grid },
        { "SOUND", O.cycleSound },
        { "HELP", function() Help.open(S.helpTopic) end },
    }
    for _, b in ipairs(list) do
        button(b[1], x, y, TOUCH_W, 13, b[2], { on = b[3] })
        y = y + 15
    end
end

--- the end ---------------------------------------------------------------------------

local overBody

local function gameOver()
    local g = S.game
    local w, h = 180, 64 + #g.players * 8 + 26
    h = h + Win.BAR + 1
    Win.add({ id = "over", title = "THE END", w = w, h = h,
        x = floor((S.vw - w) / 2), y = floor((S.vh - h) / 2),
        draw = function(x, y) overBody(x, y, w, h - Win.BAR - 1) end })
end

function overBody(x, y, w, h)
    local g = S.game
    love.graphics.push()
    local title = L(S.over.result == "won" and "VICTORY" or "DEFEAT")
    love.graphics.translate(x + floor((w - Font.width(title) * 2) / 2), y + 6)
    love.graphics.scale(2, 2)
    text("w", title, 0, 0)
    love.graphics.pop()
    local why = L(S.over.why)
    text("c", why, x + floor((w - Font.width(why)) / 2), y + 22)
    local yy = y + 34
    for _, p in ipairs(g.players) do
        local s = p.name .. "  " .. (p.alive and L("{1} CITIES", #g:citiesOf(p.id)) or L"DESTROYED") .. "  " .. L("SCORE {1}", g:score(p))
        text(p.id == 1 and "w" or "s", s, x + 6, yy)
        yy = yy + 8
    end
    -- Your score, part by part: what you had, and what of it lasted.
    local parts = {}
    for _, part in ipairs(g:scoreParts(me())) do
        if part[2] ~= 0 then parts[#parts + 1] = L(part[1]) .. " " .. part[2] end

    end
    local lines, line = {}, ""
    for _, bit in ipairs(parts) do
        local next = line == "" and bit or (line .. "  " .. bit)
        if Font.width(next) > w - 12 and line ~= "" then lines[#lines + 1] = line; line = bit else line = next end
    end
    if line ~= "" then lines[#lines + 1] = line end
    yy = yy + 2
    for k = 1, min(3, #lines) do
        text("c", lines[k], x + 6, yy)
        yy = yy + 8
    end
    button("NEW GAME", x + 10, y + h - 16, 76, 12, Menu.openNewGame, { strong = true })
    button("KEEP LOOKING", x + w - 86, y + h - 16, 76, 12, function() S.over.hidden = true end)
end

--- all of it -----------------------------------------------------------------------

function Hud.draw(dt)
    S.buttons, S.panels = {}, {}
    S.helpTopic = nil
    topBar()
    messages(dt)
    Letters.announce()
    Letters.drawStack()
    Clock.draw(S.touch and S.vw - TOUCH_W - 5 or S.vw - 3)
    local sel = S.selected
    if sel and sel.unit and not sel.unit.dead then unitPanel(sel.unit) end
    if sel and sel.city then cityPanel(sel.city) end
    if not (S.over and not S.over.hidden) and Settings.get("tooltips") then tooltip() end
    -- A phone's screen has no room for both the city and the minimap.
    if not (S.phone and sel and sel.city) then minimap() end
    if S.touch and not (S.over and not S.over.hidden) then touchButtons() end
    local label, fn = O.mainAction()
    if label then
        button(label, S.vw - 92, S.vh - 20, 88, 17, fn, { strong = fn ~= nil and true, off = fn == nil })
        if label ~= "END TURN" and O.canEnd() then
            button("END", S.vw - 92 - 24, S.vh - 20, 22, 17, O.endTurn)
        end
    end
    if S.panel == "research" then researchPanel() end
    Letters.draw()
    if S.over and not S.over.hidden then gameOver() end
end

-- The HUD's panels and buttons are where the pointer is: the board is not.
function Hud.covers(x, y)
    for _, r in ipairs(S.panels) do if Draw.inside(r, x, y) then return true end end
    for _, r in ipairs(S.buttons) do if Draw.inside(r, x, y) then return true end end
    return false
end

return Hud
