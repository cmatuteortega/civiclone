-- Letters and diplomacy on the screen (the rules are src/diplomacy.lua).
--
-- A letter for the player comes as an envelope, dropped into a stack down
-- the left of the screen under the news: cream paper folded over, sealed in
-- the colours of whoever sent it, a declaration of war edged in ink, a pip
-- blinking on one that wants an answer. A click opens it as a sheet of
-- parchment: the sender's seal and name, the date, what they say, how
-- things stand between you, their signature and motto, and the answers.
--
-- The diplomacy window (P, or DIPLOMACY in the top bar) has a row for each
-- civilization: its leader, how you stand, what they think of you and why,
-- their might against yours, and what you can ask of them; under them, the
-- letters of late, to be read again.

local D = require "src.defs"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Font = require "src.font"
local L = require "src.lang"
local Win = require "src.ui.windows"
local Board = require "src.ui.board"
local Menu = require "src.ui.menu"
local Audio = require "src.ui.audio"
local Diplo = require "src.diplomacy"
local Loyalty = require "src.loyalty"

local floor, max, min, sin = math.floor, math.max, math.min, math.sin
local text, rect, button = Draw.text, Draw.rect, Draw.button

local Letters = {}

local function g() return S.game end
local function teamOf(id) return Board.TEAM[g().players[id].civ.look] end

--- little pictures -------------------------------------------------------------------

-- A wax seal 5 across, in a civilization's colours.
local function seal(x, y, team)
    rect("o", x + 1, y, 3, 5)
    rect("o", x, y + 1, 5, 3)
    rect(team.fill, x + 1, y + 1, 3, 3)
    if team.band then rect(team.band, x + 1, y + 2, 3, 1) end
end

-- A big seal for the letter's head, 13 across, with the banner's mark.
local function bigSeal(x, y, team)
    rect("o", x + 3, y, 7, 13)
    rect("o", x + 1, y + 1, 11, 11)
    rect("o", x, y + 3, 13, 7)
    rect(team.fill, x + 3, y + 1, 7, 11)
    rect(team.fill, x + 2, y + 2, 9, 9)
    rect(team.fill, x + 1, y + 3, 11, 7)
    if team.band then rect(team.band, x + 1, y + 3, 11, 1) rect(team.band, x + 1, y + 9, 11, 1) end
    Draw.icon("city", x + 4, y + 4, team.ink)
end

Letters.W, Letters.H = 21, 14

-- An envelope at (x, y), 21 by 14: paper with a shadow under it, the
-- lower folds, the flap folded down over them and the sender's seal on its
-- point. `war`: edged in ink. `hot`: the pointer is on it.
local function envelope(x, y, l, hot)
    local war = l.kind == "war" or l.kind == "revolt"
    local W, H = Letters.W, Letters.H
    rect("o", x + 1, y + 1, W, H)
    rect("o", x, y, W, H)
    rect(hot and "w" or "c", x + 1, y + 1, W - 2, H - 2)
    -- The lower folds, from the bottom corners up to the middle.
    for i = 0, 5 do
        rect("t", x + 1 + i, y + H - 2 - floor(i * 0.8), 1, 1)
        rect("t", x + W - 2 - i, y + H - 2 - floor(i * 0.8), 1, 1)
    end
    -- The flap: a triangle a shade darker, down to the seal.
    for i = 0, 7 do
        local w = W - 2 - 2 * i - 2
        if w > 0 then
            rect(war and (hot and "k" or "n") or (hot and "c" or "s"), x + 2 + i, y + 1 + i, w, 1)
            rect("t", x + 1 + i, y + 1 + i, 1, 1)
            rect("t", x + W - 2 - i, y + 1 + i, 1, 1)
        end
    end
    if war then
        Draw.frame("u", x + 1, y + 1, W - 2, H - 2)
        rect("u", x + 1, y + H - 3, W - 2, 1)
    end
    seal(x + 8, y + 6, teamOf(l.from))
end

--- the stack -------------------------------------------------------------------------

local arrived = {}       -- when each letter's envelope first showed, by id
local heard = {}         -- the letters already announced, by id

-- The player's envelopes: letters still waiting on them, oldest first.
function Letters.stack()
    if not g() then return {} end
    return Diplo.waiting(g(), 1)
end

-- A sound for each new letter: a horn for war, paper for the rest.
function Letters.announce()
    if not g() then return end
    for _, l in ipairs(Letters.stack()) do
        if not heard[l.id] then
            heard[l.id] = true
            Audio.play(l.kind == "war" and "horn" or "page")
        end
    end
end

-- A game started or taken up: what is waiting is not news.
function Letters.reset()
    arrived, heard = {}, {}
    for _, l in ipairs(Letters.stack()) do heard[l.id] = true end
    S.letter = nil
end

function Letters.open(l)
    S.letter = l and l.id
    if l then
        l.read = true
        Audio.play("page")
    end
end

local function tip(lines, x, y)
    local bw, bh = 0, #lines * 8 + 3
    for _, l in ipairs(lines) do bw = max(bw, Font.width(l)) end
    bw = bw + 6
    x = max(2, min(x, S.vw - bw - 2))
    y = max(12, min(y, S.vh - bh - 2))
    rect("o", x, y, bw, bh)
    for k, l in ipairs(lines) do text(k == 1 and "w" or "c", l, x + 3, y + 2 + (k - 1) * 8) end
end

-- Hovering over (x, y, w, h), with nothing in front: lines in a box.
local function hoverTip(x, y, w, h, lines, win)
    local mx, my = S.mouse.x, S.mouse.y
    if not Draw.inside({ x = x, y = y, w = w, h = h }, mx, my) then return end
    Win.over(function()
        if Win.modal() or Win.dragging() then return end
        local front = Win.at(mx, my)
        if (front and front.id) ~= win then return end
        tip(lines, x + w + 3, y)
    end)
end

-- The stack down the left, under the news: each envelope dropped in and
-- settling, one wanting an answer nudging now and then.
function Letters.drawStack()
    local list = Letters.stack()
    if #list == 0 then return end
    local x, y = 3, 66
    local step = Letters.H + 4
    local most = max(1, floor((S.vh - 120 - y) / step))
    for k, l in ipairs(list) do
        if k > most then
            text("w", "+" .. (#list - most), x + 3, y + 2)
            break
        end
        arrived[l.id] = arrived[l.id] or S.clock
        local t = S.clock - arrived[l.id]
        -- Falling in from above, a little bounce at the end.
        local drop = 0
        if t < 0.5 then drop = -floor((1 - t / 0.5) ^ 2 * 50) end
        if t >= 0.5 and t < 0.7 then drop = -floor(sin((t - 0.5) / 0.2 * math.pi) * 3) end
        local asks = #Diplo.KINDS[l.kind].choices(g(), l) > 1
        -- One that asks hops every few seconds until it is answered.
        if asks and t > 1 and (S.clock + l.id * 0.37) % 3 < 0.18 then drop = drop - 1 end
        local ey = y + drop
        local r = { x = x, y = ey, w = Letters.W, h = Letters.H, fn = function() Letters.open(l) end, label = "envelope" }
        S.buttons[#S.buttons + 1] = r
        local hot = Draw.inside(r, S.mouse.x, S.mouse.y)
        envelope(x, ey, l, hot)
        if not l.read and floor(S.clock * 2) % 2 == 0 then
            rect("o", x + Letters.W - 2, ey - 2, 4, 4)
            rect("w", x + Letters.W - 1, ey - 1, 2, 2)
        end
        local p = g().players[l.from]
        hoverTip(x, ey, Letters.W, Letters.H, {
            L("A LETTER FROM {1}", L("{1} OF {2}", p.civ.leader, p.name)),
            L(Diplo.KINDS[l.kind].title),
            asks and L("AN ANSWER IS WANTED IN {1} TURNS", max(0, l.due - g().turn + 1)) or L"CLICK TO READ",
        }, nil)
        y = y + step
    end
end

--- a letter ----------------------------------------------------------------------------

-- A regard as a bar from -100 to 100, marked at nothing.
local function regardBar(x, y, w, v)
    rect("o", x, y, w, 3)
    local mid = x + floor(w / 2)
    local to = mid + floor(v / 100 * (w / 2 - 1))
    if to >= mid then rect("w", mid, y + 1, max(1, to - mid), 1) else rect("u", to, y + 1, mid - to, 1) end
    rect("s", mid, y, 1, 3)
end

local function regardLines(a, b)
    local v, parts = Diplo.regard(g(), a, b)
    local lines = { L("{1} THINKS OF YOU: {2} ({3})", g().players[a].civ.leader, L(Diplo.word(v)), (v > 0 and "+" or "") .. v) }
    for _, p in ipairs(parts) do lines[#lines + 1] = (p[2] > 0 and "+" or "") .. p[2] .. "  " .. L(p[1]) end
    if #parts == 0 then lines[#lines + 1] = L"NOTHING YET, ONE WAY OR THE OTHER" end
    return lines
end

local function letterWindow()
    local l = S.letter and Diplo.letter(g(), S.letter)
    if not l then S.letter = nil return end
    local K = Diplo.KINDS[l.kind]
    local p = g().players[l.from]
    local w = min(204, S.vw - 8)
    local cols = floor((w - 16) / 4)
    local body = {}
    for _, s in ipairs(Diplo.says(g(), l)) do
        for _, line in ipairs(Font.wrap(s, cols)) do body[#body + 1] = line end
        body[#body + 1] = false
    end
    if body[#body] == false then body[#body] = nil end
    local choices = K.choices(g(), l)
    local waiting = Diplo.stillAsks(g(), l)
    local h = Win.BAR + 1 + 22 + #body * 7 + 4 + 22 + 20 + 18
    Win.add({ id = "letter", title = K.title, w = w, h = h,
        x = floor((S.vw - w) / 2), y = max(14, floor((S.vh - h) / 2) - 16),
        close = function() S.letter = nil end,
        draw = function(x, y, ww, hh)
            -- The parchment, with a ruled edge.
            rect("c", x + 2, y + 1, ww - 4, hh - 3)
            Draw.frame("s", x + 3, y + 2, ww - 6, hh - 5)
            for dx = x + 5, x + ww - 6, 3 do rect("w", dx, y + 1, 1, 1) end
            -- The head: the seal, who sends it, and when.
            bigSeal(x + 7, y + 6, teamOf(l.from))
            text("o", L("FROM {1}", L("{1} OF {2}", p.civ.leader, p.name)), x + 24, y + 7)
            text("n", L("TURN {1}", l.turn) .. "  " .. D.year(l.turn), x + 24, y + 15)
            for dx = x + 7, x + ww - 8, 2 do rect("t", dx, y + 23, 1, 1) end
            local yy = y + 27
            for _, line in ipairs(body) do
                if line then text("o", line, x + 8, yy) yy = yy + 7 else yy = yy + 3 end
            end
            yy = yy + 4
            -- How things stand: the stance, the regard, the might of each.
            local st = Diplo.stance(g(), l.to, l.from)
            local v = Diplo.regard(g(), l.from, l.to)
            rect("t", x + 7, yy - 2, ww - 14, 20)
            Draw.frame("s", x + 7, yy - 2, ww - 14, 20)
            text("o", L(st), x + 10, yy + 1)
            local rw = L("REGARD: {1}", L(Diplo.word(v)))
            text("o", rw, x + 10 + Font.width(L(st)) + 8, yy + 1)
            regardBar(x + ww - 64, yy + 2, 52, v)
            hoverTip(x + 7, yy - 2, ww - 14, 9, regardLines(l.from, l.to), "letter")
            local mine, theirs = Diplo.army(g(), l.to), Diplo.army(g(), l.from)
            text("u", L("THEIR CITIES {1}   THEIR MIGHT {2}   YOURS {3}", #g():citiesOf(l.from), theirs, mine), x + 10, yy + 9)
            yy = yy + 22
            -- The signature and motto, to the right.
            local sign = "- " .. Diplo.signed(g(), l)
            text("o", sign, x + ww - 10 - Font.width(sign), yy)
            if not K.signed then
                local motto = '"' .. L(p.civ.motto or "") .. '"'
                text("n", motto, x + ww - 10 - Font.width(motto), yy + 8)
            end
            -- The answers, or the answer given.
            local by = y + hh - 17
            if waiting then
                local bx = x + 8
                for k, c in ipairs(choices) do
                    local label = c.args and L(c.label, unpack(c.args)) or L(c.label)
                    local bw = Font.width(label) + 10
                    button(label, bx, by, bw, 12, function()
                        Diplo.answer(g(), l, c.id)
                        Audio.play(c.id == "join" and "horn" or "click")
                        -- On to the next waiting, if there is one.
                        local next = Letters.stack()[1]
                        S.letter = next and next.id or nil
                        if next then next.read = true end
                    end, { strong = k == 1, off = c.off })
                    bx = bx + bw + 4
                end
            else
                local said
                for _, c in ipairs(choices) do
                    if c.id == l.answer then said = c.args and L(c.label, unpack(c.args)) or L(c.label) end
                end
                local what = said and L("ANSWERED: {1}", said) or L"IT IS PAST ANSWERING"
                if l.late then what = L"LEFT UNANSWERED" end
                text("n", what, x + 9, by + 3)
            end
        end })
end

--- the diplomacy window --------------------------------------------------------------------

local BADGE = {
    ["AT WAR"] = { "o", "w" }, ["ALLIES"] = { "w", "o" }, ["OPEN BORDERS"] = { "s", "o" },
    ["AT PEACE"] = { "k", "o" }, ["NOT MET"] = { "n", "c" },
}

local function badge(word, x, y)
    local b = BADGE[word] or BADGE["AT PEACE"]
    local s = L(word)
    local w = Font.width(s) + 6
    rect("o", x - 1, y - 1, w + 2, 9)
    rect(b[1], x, y, w, 7)
    text(b[2], s, x + 3, y + 1)
    return w
end

local function ask(b, a)
    local game = g()
    local name = game.players[b].name
    if a.kind == "war" then
        local r = Diplo.rel(game, 1, b)
        local broke = r.alliance or r.borders
        Menu.ask(broke and L("BREAK YOUR WORD AND DECLARE WAR ON {1}? EVERYONE WILL REMEMBER IT.", name)
            or L("DECLARE WAR ON {1}?", name), "DECLARE WAR", function()
            Diplo.propose(game, 1, b, "war")
            Audio.play("horn")
        end)
        return
    end
    local ok = Diplo.propose(game, 1, b, a.kind)
    Audio.play(ok and "city" or "deny")
end

local ROW = 50

local function diplomacyWindow()
    local game = g()
    local others = {}
    for k = 2, #game.players do
        if game.players[k].alive or Diplo.met(game, 1, k) then others[#others + 1] = k end
    end
    local mail = {}
    local all = game.diplo and game.diplo.mail or {}
    for k = #all, 1, -1 do
        if all[k].to == 1 and #mail < 5 then mail[#mail + 1] = all[k] end
    end
    local w = min(248, S.vw - 6)
    local h = Win.BAR + 1 + #others * ROW + 14 + max(1, #mail) * 9 + 6
    Win.add({ id = "diplomacy", title = "DIPLOMACY", w = w, h = h,
        x = floor((S.vw - w) / 2), y = max(14, floor((S.vh - h) / 2) - 10),
        close = function() S.panel = nil end,
        draw = function(x, y, ww)
            local yy = y + 3
            for _, b in ipairs(others) do
                local p = game.players[b]
                local met = Diplo.met(game, 1, b)
                if not met then
                    rect("o", x + 4, yy + 1, 13, 13)
                    rect("n", x + 5, yy + 2, 11, 11)
                    text("c", "?", x + 9, yy + 5)
                    text("c", "AN UNKNOWN PEOPLE", x + 22, yy + 2)
                    text("s", "NOT YET MET", x + 22, yy + 10)
                    hoverTip(x + 4, yy, ww - 8, 18, { L"NOT YET MET", L"SEE A UNIT, A CITY OR THE LAND OF THEIRS TO MEET THEM" }, "diplomacy")
                elseif not p.alive then
                    bigSeal(x + 4, yy + 1, teamOf(b))
                    text("s", L("{1} OF {2}", p.civ.leader, p.name), x + 22, yy + 2)
                    text("s", "DESTROYED", x + 22, yy + 10)
                else
                    bigSeal(x + 4, yy + 1, teamOf(b))
                    text("w", L("{1} OF {2}", p.civ.leader, p.name), x + 22, yy + 2)
                    local st = Diplo.stance(game, 1, b)
                    badge(st, x + ww - 6 - Font.width(L(st)) - 6, yy + 1)
                    -- What they think of us, and why, under the pointer.
                    local v = Diplo.regard(game, b, 1)
                    local word = L(Diplo.word(v)) .. " " .. ((v > 0 and "+" or "") .. v)
                    text("c", word, x + 22, yy + 10)
                    regardBar(x + 26 + Font.width(word), yy + 11, 50, v)
                    hoverTip(x + 20, yy + 9, Font.width(word) + 60, 7, regardLines(b, 1), "diplomacy")
                    local might = L("CITIES {1}  MIGHT {2}  YOURS {3}", #game:citiesOf(b), Diplo.army(game, b), Diplo.army(game, 1))
                    text("s", might, x + ww - 6 - Font.width(might), yy + 10)
                    -- What can be asked of them, in a second row if it
                    -- will not go in one.
                    local bx, by = x + 22, yy + 19
                    for _, a in ipairs(Diplo.asks(game, 1, b)) do
                        local label = L(a.label)
                        local bw = Font.width(label) + 6
                        if bx + bw > x + ww - 4 and bx > x + 22 then bx, by = x + 22, by + 12 end
                        button(label, bx, by, bw, 10, function() ask(b, a) end,
                            { off = a.off, strong = a.kind == "peace" })
                        if a.why then hoverTip(bx, by, bw, 10, { a.why }, "diplomacy") end
                        if a.kind == "tribute" and not a.off then
                            hoverTip(bx, by, bw, 10, { L("ASK {1} GOLD OF THEM", Diplo.tributeOf(game, b)),
                                L"THE WEAK PAY; THE STRONG REMEMBER IT" }, "diplomacy")
                        end
                        bx = bx + bw + 2
                    end
                    -- What they said last, at the end of the buttons' row
                    -- if it fits there, else under them.
                    local said = Diplo.rel(game, 1, b).said[b]
                    if said and game.turn - said.turn <= 1 then
                        local q = '"' .. L(said.text) .. '"'
                        if bx + 4 + Font.width(q) <= x + ww - 4 then text(said.ok and "w" or "c", q, bx + 4, by + 3)
                        else text(said.ok and "w" or "c", q, x + 22, by + 13) end
                    end
                end
                yy = yy + ROW
                rect("n", x + 3, yy - 5, ww - 6, 1)
            end
            text("s", "LETTERS", x + 5, yy)
            yy = yy + 9
            if #mail == 0 then text("n", "NONE YET", x + 5, yy) end
            for _, l in ipairs(mail) do
                local K = Diplo.KINDS[l.kind]
                local waiting = Diplo.stillAsks(game, l)
                local s = L("TURN {1}", l.turn) .. "  " .. game.players[l.from].name .. ": " .. L(K.title)
                local r = { x = x + 4, y = yy - 1, w = ww - 8, h = 8, fn = function() Letters.open(l) end, label = "" }
                S.buttons[#S.buttons + 1] = r
                local hot = Draw.inside(r, S.mouse.x, S.mouse.y)
                if hot then rect("n", r.x, r.y, r.w, r.h) end
                seal(x + 5, yy, teamOf(l.from))
                text(waiting and "w" or (hot and "c" or "s"), s, x + 13, yy + 1)
                if waiting then text("w", "!", x + ww - 9, yy + 1) end
                yy = yy + 9
            end
        end })
end

--- all of it -------------------------------------------------------------------------------

-- The windows, drawn with the HUD's (src/ui/hud.lua).
function Letters.draw()
    if not g() then return end
    if S.panel == "diplomacy" then diplomacyWindow() end
    if S.letter then letterWindow() end
end

-- A word for the top bar's button: DIPLOMACY, and how many letters wait.
function Letters.barLabel()
    local n = #Letters.stack()
    if n > 0 then return L("DIPLOMACY ({1})", n), true end
    return L"DIPLOMACY", false
end

-- For the city's panel: its loyalty, a word for how it is, and the lines
-- of what moves it.
function Letters.loyaltyTip(city)
    local game = g()
    local delta, parts = Loyalty.parts(game, city)
    local lines = { "LOYALTY", L("{1}/100, {2} A TURN", floor(Loyalty.of(city)), (delta >= 0 and "+" or "") .. delta) }
    for _, p in ipairs(parts) do lines[#lines + 1] = (p[2] > 0 and "+" or "") .. p[2] .. "  " .. L(p[1]) end
    lines[#lines + 1] = L("UNDER {1}: UNREST, A QUARTER LESS OF ALL BUT FOOD", D.LOYALTY.unrest)
    lines[#lines + 1] = L("UNDER {1}: UPRISING, HALF. AT 0 IT GOES OVER TO ANOTHER", D.LOYALTY.uprising)
    return lines, delta
end

return Letters
