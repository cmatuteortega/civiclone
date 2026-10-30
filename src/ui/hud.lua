-- The HUD, on a canvas of its own at a zoom that stays put: the bar along the
-- top (treasury, science, culture, research, the turn), the latest news, the
-- selected unit's or city's panel, research, a tooltip for the hex under the
-- pointer, a minimap, and the button that ends the turn. On a touch screen,
-- buttons down the right edge for what only keys and the wheel do.
--
-- The unit's and city's panels, research and the end are windows
-- (src/ui/windows.lua): the player can drag them where they like.

local D = require "src.defs"
local H = require "src.hex"
local T = require "src.tracer"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local View = require "src.ui.view"
local O = require "src.ui.orders"
local Board = require "src.ui.board"
local Font = require "src.font"
local Win = require "src.ui.windows"
local Menu = require "src.ui.menu"
local Settings = require "src.settings"

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

--- the top bar ---------------------------------------------------------------------

local function topBar()
    local g, p = S.game, me()
    rect("u", 0, 0, S.vw, 10)
    rect("o", 0, 10, S.vw, 1)
    S.panels[#S.panels + 1] = { x = 0, y = 0, w = S.vw, h = 11 }
    local gold, sci, cul = g:income(p)
    local x = 3
    icon("gold", x, 3, "w")
    text("w", p.gold .. " (" .. signed(gold) .. ")", x + 7, 3)
    x = x + 7 + Font.width(p.gold .. " (" .. signed(gold) .. ")") + 8
    icon("science", x, 3, "c")
    text("c", signed(sci), x + 7, 3)
    x = x + 7 + Font.width(signed(sci)) + 8
    icon("culture", x, 3, "s")
    text("s", signed(cul), x + 7, 3)
    x = x + 7 + Font.width(signed(cul)) + 10
    -- Research: what, how far, how long. A click opens the list.
    local label
    if p.researching then
        local t = D.TECH[p.researching]
        local turns = sci > 0 and math.ceil(max(0, t.cost - p.science) / sci) or "-"
        label = t.name .. " " .. floor(p.science) .. "/" .. t.cost .. " (" .. turns .. ")"
    elseif #g:researchable(p) > 0 then
        label = "CHOOSE RESEARCH"
    else
        label = "ALL KNOWN"
    end
    local w = Font.width(label) + 6
    button(label, x, 1, w, 9, function() S.panel = S.panel == "research" and nil or "research" end,
        { strong = not p.researching and #g:researchable(p) > 0 })
    -- The menu, at the far right.
    button("MENU", S.vw - 25, 1, 24, 9, Menu.openPause)
    local right = "TURN " .. g.turn .. "  " .. D.year(g.turn)
    text("c", right, S.vw - Font.width(right) - 29, 3)
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
    local w, h = 168, Win.BAR + 1 + 28
    local who = u.owner == 1 and def.name or (g.players[u.owner].name .. " " .. def.name)
    Win.add({ id = "unit", title = who, w = w, h = h, x = 2, y = S.vh - h - 2,
        close = function() O.select(nil) end,
        draw = function(x, y)
            local team = Board.TEAM[g.players[u.owner].civ.look]
            rect("o", x + 3, y + 2, 9, 9)
            rect(team.fill, x + 4, y + 3, 7, 7)
            icon(u.kind, x + 5, y + 4, team.ink)
            local stats = {}
            if def.str > 0 then stats[#stats + 1] = "STR " .. def.str end
            if def.ranged then stats[#stats + 1] = "RNG " .. def.ranged .. "/" .. def.range end
            stats[#stats + 1] = "HP " .. max(0, u.hp)
            stats[#stats + 1] = "MOVES " .. u.moves .. "/" .. def.moves
            if def.charges then stats[#stats + 1] = "BUILDS " .. u.charges end
            text("c", table.concat(stats, "  "), x + 15, y + 4)
            local status = u.fortified and "FORTIFIED" or (u.sleep and "ASLEEP") or (u.dest and "ON THE MOVE") or nil
            if status then text("s", status, x + w - Font.width(status) - 4, y + 18) end
            local bx = x + 3
            for _, a in ipairs(acts) do
                local bw = Font.width(a.label) + 8
                button(a.label, bx, y + 14, bw, 11, a.fn, { off = a.off or u.moves <= 0 and a.label ~= "WAKE" })
                bx = bx + bw + 2
            end
        end })
end

--- a city's panel ---------------------------------------------------------------------

local function costOf(it) return it.def.cost end

local cityBody

local function cityPanel(c)
    local g = S.game
    local mine = c.owner == 1
    local w = 150
    local items = mine and g:buildable(c) or {}
    local h = 62 + (mine and (#items * 10 + 14) or 0)
    h = min(h, S.vh - 13 - 24)
    local cap = c.capital and " (CAPITAL)" or ""
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
    if surplus > 0 then grow = math.ceil((need - c.food) / surplus) .. " TURNS"
    elseif surplus < 0 then grow = "STARVING" else grow = "STAGNANT" end
    text("c", "CITIZENS " .. c.pop .. "   HP " .. max(0, c.hp) .. "/" .. g:maxHp(c), x + 4, y + 12)
    icon("food", x + 4, y + 20, "w")
    text("w", signed(surplus) .. "  " .. c.food .. "/" .. need .. "  GROWS IN " .. grow, x + 11, y + 20)
    local line = y + 28
    icon("prod", x + 4, line, "c")
    text("c", tostring(p), x + 11, line)
    icon("gold", x + 30, line, "c")
    text("c", tostring(gold), x + 37, line)
    icon("science", x + 56, line, "c")
    text("c", tostring(floor(sci * 10) / 10), x + 63, line)
    icon("culture", x + 86, line, "c")
    text("c", tostring(cul), x + 93, line)
    local built = {}
    for _, id in ipairs({ "monument", "granary", "library", "market", "walls" }) do
        if c.buildings[id] then built[#built + 1] = D.BUILDINGS[id].name end
    end
    text("s", #built > 0 and table.concat(built, " ") or "NO BUILDINGS", x + 4, y + 36)
    if not mine then return end
    -- What it is building, and what it could.
    local yy = y + 45
    if c.build then
        local def = c.build.kind == "unit" and D.UNITS[c.build.id] or D.BUILDINGS[c.build.id]
        text("w", def.name .. " " .. floor(c.prod) .. "/" .. def.cost .. " (" .. g:turnsFor(c, def.cost) .. ")", x + 4, yy)
        Draw.bar(x + 4, yy + 7, w - 50, c.prod / def.cost, "w", "o")
        local cost = g:buyCost(c)
        local can = cost and me().gold >= cost and not c.bought
        button("BUY " .. cost, x + w - 44, yy - 2, 40, 10, function() g:buy(c) end, { off = not can })
    else
        text("w", "CHOOSE WHAT TO BUILD", x + 4, yy)
    end
    yy = yy + 13
    for _, it in ipairs(items) do
        if yy + 10 > y + h - 2 then break end
        local cost = costOf(it)
        local on = c.build and c.build.kind == it.kind and c.build.id == it.id
        local turns = g:turnsFor(c, cost, on and c.prod or 0)
        local note = (it.kind == "unit" and it.def.pop and c.pop <= it.def.pop) and "NEEDS 2 POP" or (cost .. "  " .. turns .. "T")
        local hot = button(it.def.name, x + 3, yy, w - 6, 10, function()
            g:setBuild(c, it.kind, it.id)
        end, { on = on, left = true, icon = it.kind == "unit" and it.id or "city" })
        text(hot and "o" or "u", note, x + w - 5 - Font.width(note), yy + 3)
        yy = yy + 10
    end
end

--- research ------------------------------------------------------------------------

local researchBody

local function researchPanel()
    local w, h = 200, 22 + #D.TECHS * 12
    Win.add({ id = "research", title = "RESEARCH", w = w, h = h,
        x = floor((S.vw - w) / 2), y = max(14, floor((S.vh - h) / 2) - 10),
        close = function() S.panel = nil end,
        draw = function(x, y) researchBody(x, y - Win.BAR - 1, w) end })
end

function researchBody(x, y, w)
    local g, p = S.game, me()
    local yy = y + 14
    local _, sci = g:income(p)
    for _, t in ipairs(D.TECHS) do
        local known = p.techs[t.id]
        local can = g:canResearch(p, t.id)
        local label = t.name .. " - " .. t.gives
        local note
        if known then note = "KNOWN"
        elseif can then note = t.cost .. "  " .. (sci > 0 and math.ceil(max(0, t.cost - p.science) / sci) or "-") .. "T"
        else
            local needs = {}
            for _, n in ipairs(t.needs) do needs[#needs + 1] = D.TECH[n].name end
            note = "NEEDS " .. table.concat(needs, ", ")
        end
        local hot = button(label, x + 3, yy, w - 6, 11, function()
            p.researching = t.id
            S.panel = nil
        end, { off = not can, on = p.researching == t.id or known, left = true })
        text(can and (hot and "o" or "u") or "k", note, x + w - 5 - Font.width(note), yy + 3)
        yy = yy + 12
    end
end

--- the hex under the pointer --------------------------------------------------------

local function tooltip()
    local g, cell = S.game, S.hover
    if not cell or not me().explored[cell.id] then return end
    local lines = {}
    local f, p, gold = g:yield(cell)
    local head = g:describe(cell)
    if cell.elev ~= "mountain" then head = head .. "   " .. f .. "F " .. p .. "P " .. gold .. "G" end
    lines[1] = head
    if cell.owner then
        local owner = g.players[cell.owner]
        lines[#lines + 1] = (cell.city and cell.city.name or (cell.ownerCity and cell.ownerCity.name or "")) .. " - " .. owner.name
    end
    if me().visible[cell.id] then
        for _, u in ipairs({ g.mil[cell.id], g.civ[cell.id] }) do
            if u and u.owner ~= 1 then
                lines[#lines + 1] = g.players[u.owner].name .. " " .. u.def.name .. " " .. u.hp .. "HP"
            end
        end
    end
    local sel = S.selected and S.selected.unit
    if sel and sel.owner == 1 and g:canAttack(sel, cell) then
        local dealt, taken = g:forecast(sel, cell)
        lines[#lines + 1] = "ATTACK: DEALS ABOUT " .. dealt .. ", TAKES ABOUT " .. taken
    elseif sel and sel.owner == 1 and S.hoverTurns and cell.id ~= sel.cell then
        lines[#lines + 1] = "MOVE: " .. S.hoverTurns .. (S.hoverTurns == 1 and " TURN" or " TURNS")
    end
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
    rect("o", x, y, w + 6, #lines * 8 + 3)
    for k, l in ipairs(lines) do text(k == 1 and "w" or "c", l, x + 3, y + 2 + (k - 1) * 8) end
end

--- the minimap ---------------------------------------------------------------------

local MINI = { ocean = "u", coast = "n", grass = "k", plains = "t", desert = "c" }

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
    for _, cell in ipairs(g.cells) do
        local px, py = x + cell.c * 2 + cell.r % 2, y + cell.r * 2
        if p.explored[cell.id] then
            local k = cell.elev == "mountain" and "s" or MINI[cell.terrain]
            if cell.owner then k = Board.TEAM[g.players[cell.owner].civ.look].fill end
            rect(k, px, py, 2, 2)
            if cell.city then rect("o", px, py, 2, 1) end
        else
            rect((cell.c + cell.r) % 2 == 0 and "c" or "s", px, py, 2, 2)
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
    local w, h = 180, 64 + #g.players * 8
    h = h + Win.BAR + 1
    Win.add({ id = "over", title = "THE END", w = w, h = h,
        x = floor((S.vw - w) / 2), y = floor((S.vh - h) / 2),
        draw = function(x, y) overBody(x, y, w, h - Win.BAR - 1) end })
end

function overBody(x, y, w, h)
    local g = S.game
    love.graphics.push()
    local title = S.over.result == "won" and "VICTORY" or "DEFEAT"
    love.graphics.translate(x + floor((w - Font.width(title) * 2) / 2), y + 6)
    love.graphics.scale(2, 2)
    text("w", title, 0, 0)
    love.graphics.pop()
    text("c", S.over.why, x + floor((w - Font.width(S.over.why)) / 2), y + 22)
    local yy = y + 34
    for _, p in ipairs(g.players) do
        local s = p.name .. "  " .. (p.alive and (#g:citiesOf(p.id) .. " CITIES") or "DESTROYED") .. "  SCORE " .. g:score(p)
        text(p.id == 1 and "w" or "s", s, x + 6, yy)
        yy = yy + 8
    end
    button("NEW GAME", x + 10, y + h - 16, 76, 12, function() S.newGame() end, { strong = true })
    button("KEEP LOOKING", x + w - 86, y + h - 16, 76, 12, function() S.over.hidden = true end)
end

--- all of it -----------------------------------------------------------------------

function Hud.draw(dt)
    S.buttons, S.panels = {}, {}
    topBar()
    messages(dt)
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
    if S.over and not S.over.hidden then gameOver() end
end

-- The HUD's panels and buttons are where the pointer is: the board is not.
function Hud.covers(x, y)
    for _, r in ipairs(S.panels) do if Draw.inside(r, x, y) then return true end end
    for _, r in ipairs(S.buttons) do if Draw.inside(r, x, y) then return true end end
    return false
end

return Hud
