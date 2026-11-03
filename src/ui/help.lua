-- Help: a window with HOW TO PLAY, a chapter at a time, and the GLOSSARY,
-- a page for everything the game names (src/glossary.lua); and the hints
-- that come up in the first games, one at a time, as there is something
-- to say.
--
-- The help key (F1 unless rebound) opens the glossary at whatever a tooltip
-- is showing (S.helpTopic, set by the HUD as it draws one), or HOW TO PLAY
-- if none is. The window is read with the keyboard as well as the mouse:
-- up and down go through the list, left and right through the chapters,
-- Tab between the two halves, the help key or Escape shuts it.
--
-- A hint stays up until it is done (the city founded, the research chosen)
-- or put away, and is never shown again; which have been shown is kept in
-- the settings (`hintsSeen`). TUTORIAL HINTS in the settings turns them off.

local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local Win = require "src.ui.windows"
local Settings = require "src.settings"
local Glossary = require "src.glossary"
local Font = require "src.font"
local L = require "src.lang"
local D = require "src.defs"

local floor, max, min = math.floor, math.max, math.min
local text, rect, button = Draw.text, Draw.rect, Draw.button

local Help = {}

local open = false
local tab = "play"      -- "play" or "glossary"
local chapter = 1
local topic             -- the glossary page shown
local scroll = 0        -- the glossary list's first row shown
local listRows = 1      -- how many rows of it fit, as last drawn
local reveal            -- the page shown to be brought to the middle of the list, once it is drawn

-- The key bound to command `cmd`, as it reads.
local function k(cmd) return L(Settings.keyName(Settings.key(cmd))) end

--- how to play ---------------------------------------------------------------------

-- Each chapter: its name, and its paragraphs, put together with the keys
-- as they are bound now.
Help.CHAPTERS = {
    { "THE GOAL", function() return {
        L("BUILD AN EMPIRE OF CITIES, AND KEEP IT THROUGH THE END OF THE WORLD. AT TURN {1} THE HIGHEST SCORE WINS; DESTROYING EVERY RIVAL WINS SOONER.", D.LAST_TURN),
        "THE WORLD ENDS AS CHOSEN FOR THE GAME. THE CATACLYSM IS FORETOLD SOME TURNS IN, AND GROWS WORSE STAGE BY STAGE.",
    } end },
    { "THE FIRST TURNS", function() return {
        L("YOU START WITH A SETTLER AND A FEW UNITS. SELECT THE SETTLER WITH A LEFT CLICK AND PRESS {1} TO FOUND YOUR CAPITAL WHERE IT STANDS. BY A RIVER OR THE COAST IS GOOD.", k("found")),
        L("THEN CHOOSE WHAT TO RESEARCH ({1}), AND WHAT THE CITY BUILDS: CLICK IT.", k("research")),
    } end },
    { "MOVING", function() return {
        "SELECT A UNIT, THEN RIGHT CLICK A HEX TO SEND IT THERE. THE PALE HEXES ARE WHERE IT CAN GET THIS TURN; A LINE SHOWS ITS WAY, AND A NUMBER THE TURNS IT WILL TAKE.",
        L("{1} GOES TO THE NEXT UNIT THAT NEEDS ORDERS. {2} FORTIFIES A SOLDIER, {3} PUTS A UNIT TO SLEEP, {4} SKIPS IT FOR THE TURN.",
            k("main"), k("fortify"), k("sleep"), k("skip")),
        L("DRAG THE MAP, OR USE THE ARROWS OR {1}, TO LOOK AROUND. THE WHEEL ZOOMS.",
            k("panUp") .. k("panLeft") .. k("panDown") .. k("panRight")),
    } end },
    { "CITIES", function() return {
        "A CITY WORKS THE BEST HEXES AROUND IT FOR FOOD, PRODUCTION AND GOLD, ONE A CITIZEN. FOOD GROWS IT; PRODUCTION BUILDS WHAT YOU CHOOSE IN ITS WINDOW.",
        "TRAIN SETTLERS TO FOUND MORE CITIES, AT LEAST 4 HEXES APART, AND BUILDERS TO MAKE FARMS AND MINES. BUY WHAT IS SLOW WITH GOLD.",
        L("{1} GOES TO YOUR CAPITAL.", k("capital")),
    } end },
    { "RESEARCH", function() return {
        L("SCIENCE RESEARCHES ONE TECHNOLOGY AT A TIME. {1} OPENS THE TREE: CLICK ONE TO RESEARCH IT, OR ONE FURTHER ON TO QUEUE THE WAY TO IT.", k("research")),
        "TECHNOLOGIES BRING NEW GEAR FOR YOUR SOLDIERS, NEW BUILDINGS AND IMPROVEMENTS, AND THE WARDS AGAINST THE END.",
    } end },
    { "UNITS AND GEAR", function() return {
        "A CITY TRAINS SETTLERS, BUILDERS, BANDS AND SHIPS. WHAT A BAND IS COMES FROM WHAT IT CARRIES: A CLUB MAKES A WARRIOR, A BOW AN ARCHER; ON A HORSE, A HORSEMAN OR A HORSE ARCHER.",
        L("CHOOSE THE GEAR UNDER WHAT THE CITY IS BUILDING. A BAND IN ONE OF YOUR CITIES CAN BE REFITTED WITH BETTER: {1}.", k("refit")),
    } end },
    { "FIGHTING", function() return {
        "WITH A SOLDIER SELECTED, PUT THE POINTER ON AN ENEMY: THE TOOLTIP FORECASTS THE DAMAGE BOTH WAYS. RIGHT CLICK TO ATTACK.",
        "HILLS, FOREST AND FORTIFYING MAKE A DEFENDER STRONGER; WOUNDED UNITS FIGHT WEAKER. A UNIT THAT RESTS HEALS.",
        "BEASTS ROAM THE WILD ROUND THEIR LAIRS. A SOLDIER WALKING INTO A LAIR WITH NO BEAST THERE CLEARS IT, FOR GOLD.",
    } end },
    { "DIPLOMACY", function() return {
        L("{1} OPENS DIPLOMACY: EACH LEADER YOU HAVE MET, HOW THINGS STAND, AND WHAT TO ASK OF THEM. THE POINTER ON ANYTHING THERE SAYS WHAT IT MEANS.", k("diplomacy")),
        "AT PEACE NEITHER MAY ENTER THE OTHER'S LAND. OPEN BORDERS LET BOTH CROSS; ALLIES ALSO SHARE WHAT THEY SEE AND ARE CALLED TO EACH OTHER'S WARS.",
        "REGARD, -100 TO 100, IS WHAT A LEADER REMEMBERS OF YOU, FADING IN TIME, AND HOW THINGS STAND NOW. THE HIGHER, THE MORE THEY AGREE TO.",
        "MIGHT IS AN ARMY'S STRENGTH: THE WEAK PAY TRIBUTE TO ONE HALF AGAIN AS MIGHTY. WAR ON ONE YOU HAVE A TREATY WITH IS BETRAYAL, AND ALL REMEMBER IT.",
        "LEADERS WRITE TO YOU, AND A LETTER LEFT TOO LONG IS ANSWERED FOR YOU. EACH HAS A TEMPER: SOME ARE QUICK TO WAR, SOME WOULD RATHER BUILD.",
    } end },
    { "THE END OF THE WORLD", function() return {
        "ONCE THE CATACLYSM IS FORETOLD, THE TOP BAR SAYS ITS STAGE AND THE TURNS LEFT, AND THE NEWS SAYS WHAT IT DOES.",
        "BUILD ITS WARDS IN YOUR CITIES: EACH SPARES ITS CITY THE WORST, AND A CITY THAT KEEPS ONE TO THE END SCORES MORE. KEEP YOUR PEOPLE ALIVE: THEY ARE THE SCORE.",
    } end },
    { "THE SCREEN", function() return {
        "ALONG THE TOP: YOUR GOLD, SCIENCE AND CULTURE, THE RESEARCH AND THE TURN. TOP LEFT: THE NEWS. ALONG THE BOTTOM: THE HEX UNDER THE POINTER, THE SELECTED UNIT OR CITY, THE MINIMAP AND THE TURN'S BUTTON.",
        "WINDOWS ARE DRAGGED BY THEIR TITLES; A DOUBLE CLICK ON ONE PUTS IT BACK.",
    } end },
    { "KEYS", function()
        if S.touch then return {
            "TAP: SELECT, OR SEND THE CHOSEN UNIT THERE",
            "DRAG: PAN   PINCH: ZOOM",
            "THE BUTTONS DOWN THE RIGHT: ZOOM, NEXT UNIT, CAPITAL, HEX GRID, SOUND AND HELP.",
        } end
        local out = { "LEFT CLICK: SELECT   RIGHT CLICK: MOVE OR ATTACK" }
        for _, c in ipairs(Settings.COMMANDS) do out[#out + 1] = L(c.name) .. ": " .. k(c.id) end
        out[#out + 1] = L"ESC: MENU"
        return out, true
    end },
    { "LOOKING THINGS UP", function() return {
        L("PUT THE POINTER ON ANYTHING AND PRESS {1}: THE GLOSSARY OPENS AT IT. THE TOOLTIP'S LAST LINE SAYS WHAT IT WILL OPEN.", k("help")),
        "HINTS COME UP IN YOUR FIRST GAMES. TURN THEM OFF OR ON IN SETTINGS, GAMEPLAY.",
        "THE PIXEL POINTER AND ITS SIZE, AND THICKER HEX OUTLINES, ARE IN SETTINGS, INTERFACE.",
    } end },
}

--- opening and closing ---------------------------------------------------------------

function Help.isOpen() return open end

-- Opens the window: at glossary page `at` if there is one, else at HOW TO
-- PLAY where it was left.
function Help.open(at)
    open = true
    if at and Glossary.get(at) then
        tab, topic = "glossary", at
        reveal = true
    else
        tab = "play"
    end
end

function Help.close() open = false end

-- Opens it at what the tooltip is showing, or shuts it if it is up.
function Help.toggle()
    if open then Help.close() else Help.open(S.helpTopic) end
end

--- the glossary's list -----------------------------------------------------------------

-- The list's rows: a heading for each kind, then its pages.
local rows, rowsLang
local function listOf()
    if rows and rowsLang == L.get() then return rows end
    rows, rowsLang = {}, L.get()
    for _, kind in ipairs(Glossary.KINDS) do
        rows[#rows + 1] = { head = kind.name }
        for _, p in ipairs(Glossary.ofKind(kind.id)) do rows[#rows + 1] = { id = p.id } end
    end
    return rows
end

local function rowOf(id)
    for n, r in ipairs(listOf()) do if r.id == id then return n end end
end

-- Scrolls the list so the page shown is in it; `middle`: in the middle of it.
function Help.reveal(middle)
    local n = rowOf(topic)
    if not n then return end
    if middle then scroll = n - floor(listRows / 2) - 1
    elseif n - 1 < scroll then scroll = max(0, n - 2)
    elseif n > scroll + listRows then scroll = n - listRows end
    scroll = max(0, min(#listOf() - listRows, scroll))
end

local function clampScroll()
    scroll = max(0, min(#listOf() - listRows, scroll))
end

-- The next page of the glossary (dir 1) or the last (dir -1), past the headings.
local function stepTopic(dir)
    local list = listOf()
    local n = rowOf(topic) or 0
    repeat n = n + dir until n < 1 or n > #list or list[n].id
    if list[n] then topic = list[n].id Help.reveal() end
end

-- The wheel, over the window: scrolls the list.
function Help.wheel(dy)
    if not open then return false end
    if tab == "glossary" then
        scroll = scroll - dy * 3
        clampScroll()
    end
    return true
end

-- A key, while the window is up. Answers whether it took it.
function Help.key(key)
    if not open then return false end
    -- The window and the sound go on as ever.
    if Settings.is("fullscreen", key) or Settings.is("sound", key)
        or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then return false end
    if key == "escape" or Settings.is("help", key) then Help.close() return true end
    if key == "tab" then tab = tab == "play" and "glossary" or "play" return true end
    local nch = #Help.CHAPTERS
    if tab == "play" then
        if key == "up" or key == "left" then chapter = max(1, chapter - 1)
        elseif key == "down" or key == "right" or key == "return" or key == "space" then chapter = min(nch, chapter + 1) end
    else
        if key == "up" then stepTopic(-1)
        elseif key == "down" then stepTopic(1)
        elseif key == "pageup" then scroll = scroll - listRows clampScroll()
        elseif key == "pagedown" then scroll = scroll + listRows clampScroll() end
    end
    return true
end

--- drawing -----------------------------------------------------------------------------

-- Paragraphs wrapped to `chars`, from (x, y), no lower than `bottom`; a gap
-- between paragraphs unless `tight`. Answers where it got to.
local function paragraphs(list, x, y, chars, bottom, ink, tight)
    for _, para in ipairs(list) do
        for _, line in ipairs(Font.wrap(L(para), chars)) do
            if y + 6 > bottom then return y end
            text(ink or "c", line, x, y)
            y = y + 8
        end
        if not tight then y = y + 3 end
    end
    return y
end

local LIST_W = 96

local function playBody(x, y, w, h)
    local bottom = y + h
    -- The chapters down the left.
    local bh = min(11, floor(h / #Help.CHAPTERS))
    for n, ch in ipairs(Help.CHAPTERS) do
        button(ch[1], x + 3, y + (n - 1) * bh, LIST_W, bh - 1, function() chapter = n end, { on = n == chapter, left = true })
    end
    local tx = x + LIST_W + 9
    local chars = floor((x + w - tx - 3) / 4)
    local ch = Help.CHAPTERS[chapter]
    text("w", ch[1], tx, y + 1)
    rect("n", tx, y + 8, x + w - tx - 4, 1)
    local list, tight = ch[2]()
    paragraphs(list, tx, y + 12, chars, bottom, "c", tight)
end

local function glossaryBody(x, y, w, h)
    local list = listOf()
    if not topic then topic = list[2].id end
    local rowH = 11
    listRows = max(1, floor(h / rowH))
    clampScroll()
    if reveal then Help.reveal(true) reveal = nil end
    -- The list, a window onto it.
    rect("o", x + 2, y - 1, LIST_W + 2, h + 1)
    for n = scroll + 1, min(#list, scroll + listRows) do
        local r = list[n]
        local ry = y + (n - scroll - 1) * rowH
        if r.head then
            text("t", r.head, x + 4, ry + 2)
        else
            local name = Font.cut(Glossary.name(r.id), floor((LIST_W - 8) / 4))
            button(name, x + 3, ry, LIST_W, rowH - 1, function() topic = r.id end, { on = r.id == topic, left = true })
        end
    end
    -- How far down the list is: a bar in the list's right edge.
    if #list > listRows then
        local bh = max(4, floor(h * listRows / #list))
        local by = y + floor((h - bh) * scroll / max(1, #list - listRows))
        rect("k", x + LIST_W + 2, by, 1, bh)
    end
    -- The page.
    local tx = x + LIST_W + 9
    local chars = floor((x + w - tx - 3) / 4)
    local p = Glossary.get(topic)
    text("w", Glossary.name(topic), tx, y + 1)
    for _, kind in ipairs(Glossary.KINDS) do
        if kind.id == p.kind then
            local s = L(kind.name)
            text("k", s, x + w - 4 - Font.width(s), y + 1)
        end
    end
    rect("n", tx, y + 8, x + w - tx - 4, 1)
    paragraphs(Glossary.lines(topic), tx, y + 12, chars, y + h, "c")
end

local function helpWindow()
    local top = S.mode == "play" and 11 or 0
    local w = min(340, S.vw - 4)
    local h = min(232, S.vh - top - 4)
    Win.add({
        id = "help", title = "HELP", w = w, h = h, modal = true,
        x = floor((S.vw - w) / 2), y = top + floor((S.vh - top - h) / 2),
        close = Help.close,
        draw = function(x, y, ww, hh)
            local tw = floor((ww - 6) / 2)
            button("HOW TO PLAY", x + 3, y + 2, tw - 1, 11, function() tab = "play" end, { on = tab == "play" })
            button("GLOSSARY", x + 3 + tw, y + 2, tw - 1, 11, function()
                tab = "glossary"
                Help.reveal()
            end, { on = tab == "glossary" })
            rect("o", x + 2, y + 14, ww - 4, 1)
            local bodyY, footY = y + 18, y + hh - 18
            if tab == "play" then playBody(x, bodyY, ww, footY - bodyY - 2)
            else glossaryBody(x, bodyY, ww, footY - bodyY - 2) end
            rect("o", x + 2, footY, ww - 4, 1)
            local by = y + hh - 15
            if tab == "play" then
                local n = #Help.CHAPTERS
                button("< BACK", x + 4, by, 44, 12, function() chapter = max(1, chapter - 1) end, { off = chapter <= 1 })
                button("NEXT >", x + 50, by, 44, 12, function() chapter = min(n, chapter + 1) end, { off = chapter >= n })
                text("k", chapter .. "/" .. n, x + 100, by + 4)
            else
                local s = L("{1}: LOOK UP WHAT IS UNDER THE POINTER", k("help"))
                text("k", Font.cut(s, floor((ww - 74) / 4)), x + 5, by + 4)
            end
            button("DONE", x + ww - 64, by, 60, 12, Help.close, { strong = true })
        end,
    })
end

--- hints ---------------------------------------------------------------------------------

local function me() return S.game and S.game.players[1] end

local function owns(g, p, pred)
    for _, u in ipairs(g:unitsOf(p.id)) do if pred(u) then return true end end
    return false
end

-- Each hint: `when` it is worth saying, when it is `done` (and goes, never
-- to come back), and what it says.
Help.HINTS = {
    { id = "found",
        when = function(g, p) return #g:citiesOf(p.id) == 0 and owns(g, p, function(u) return u.kind == "settler" end) end,
        done = function(g, p) return #g:citiesOf(p.id) > 0 end,
        says = function() return L("SELECT YOUR SETTLER WITH A LEFT CLICK AND PRESS {1} TO FOUND YOUR FIRST CITY. RIGHT CLICK A HEX TO MOVE IT FIRST.", k("found")) end },
    { id = "research",
        when = function(g, p) return #g:citiesOf(p.id) > 0 and not p.researching and #g:researchable(p) > 0 end,
        done = function(g, p) return p.researching ~= nil end,
        says = function() return L("CHOOSE SOMETHING TO RESEARCH: CLICK CHOOSE RESEARCH IN THE TOP BAR, OR PRESS {1}.", k("research")) end },
    { id = "city",
        when = function(g, p) return #g:citiesOf(p.id) > 0 end,
        done = function() return S.selected ~= nil and S.selected.city ~= nil end,
        says = function() return "CLICK YOUR CITY TO SEE WHAT IT IS BUILDING, AND CHOOSE SOMETHING ELSE IF YOU LIKE." end },
    { id = "turn",
        when = function(g, p) return #g:citiesOf(p.id) > 0 and p.researching ~= nil end,
        done = function(g) return g.turn >= 4 end,
        says = function() return L("{1} GOES TO THE NEXT UNIT THAT NEEDS ORDERS, AND ENDS THE TURN WHEN NONE DO. SO DOES THE BUTTON AT THE BOTTOM RIGHT.", k("main")) end },
    { id = "builder",
        when = function(g, p) return owns(g, p, function(u) return u.kind == "builder" end) end,
        says = function() return L("A BUILDER IMPROVES YOUR LAND: ON A HEX OF YOURS, {1} BUILDS A FARM, AND {2} A MINE ON HILLS ONCE YOU KNOW MINING.", k("farm"), k("mine")) end },
    { id = "enemy",
        when = function(g, p)
            for _, u in ipairs(g.units) do
                if u.owner ~= p.id and not u.dead and not u.def.civilian and p.visible[u.cell] then return true end
            end
        end,
        says = function() return "SOMEONE ELSE IS NEAR. WITH A SOLDIER SELECTED, PUT THE POINTER ON THEM TO SEE WHAT A FIGHT WOULD COST; RIGHT CLICK TO ATTACK. ANOTHER CIVILIZATION MUST BE AT WAR WITH YOU FIRST." end },
    { id = "letter",
        when = function(g, p) return #require("src.diplomacy").waiting(g, p.id) > 0 end,
        done = function() return S.letter ~= nil end,
        says = function() return L("A LETTER HAS COME. CLICK THE ENVELOPE AT THE LEFT TO READ IT AND ANSWER. {1} OPENS DIPLOMACY.", k("diplomacy")) end },
    { id = "doom",
        when = function(g) return require("src.cataclysm").label(g) ~= nil end,
        says = function() return "THE END IS FORETOLD: THE TOP BAR SAYS ITS STAGE AND THE TURNS LEFT. RESEARCH AND BUILD ITS WARDS TO SPARE YOUR CITIES THE WORST." end },
    { id = "lookup",
        when = function(g) return g.turn >= 3 end,
        says = function() return L("PUT THE POINTER ON ANYTHING AND PRESS {1} TO LOOK IT UP. WITH NOTHING UNDER IT, {1} OPENS HOW TO PLAY.", k("help")) end },
}

local current         -- the hint up now
local checked = -1    -- when the hints were last looked over

local function seen()
    local out = {}
    for id in (Settings.get("hintsSeen") or ""):gmatch("[^,]+") do out[id] = true end
    return out
end

local function markSeen(id)
    local s = seen()
    if s[id] then return end
    local v = Settings.get("hintsSeen") or ""
    Settings.set("hintsSeen", v == "" and id or (v .. "," .. id))
    Settings.save()
end

-- Puts the hint away, never to come back.
function Help.dismiss()
    if current then markSeen(current.id) end
    current = nil
end

-- All the hints away for good: the setting off.
local function noMore()
    Help.dismiss()
    Settings.set("hints", false)
    Settings.save()
end

-- Every hint to be shown again (the setting turned back on).
function Help.resetHints()
    Settings.set("hintsSeen", "")
    current = nil
end

-- Each frame while playing: done with the hint up, or time for another?
function Help.update()
    -- Pictures taken unattended (--shot) show a hint only when asked to,
    -- and keep nothing.
    if S.plan then return end
    local g, p = S.game, me()
    if S.mode ~= "play" or not g or not p or S.over or not Settings.get("hints") then
        if not Settings.get("hints") then current = nil end
        return
    end
    if current then
        if current.done and current.done(g, p) then Help.dismiss() end
        return
    end
    -- Looked over twice a second, not every frame.
    if S.clock - checked < 0.5 then return end
    checked = S.clock
    local s = seen()
    for _, h in ipairs(Help.HINTS) do
        if not s[h.id] and h.when(g, p) then
            if h.done and h.done(g, p) then markSeen(h.id)
            else current = h break end
        end
    end
end

-- A hint by its id, up now whatever has been seen (for pictures of it).
function Help.show(id)
    for _, h in ipairs(Help.HINTS) do if h.id == id then current = h end end
end

local function hintWindow()
    local h0 = current
    local w = min(170, S.vw - 4)
    local lines = Font.wrap(L(h0.says()), floor((w - 10) / 4))
    local h = Win.BAR + 1 + 4 + #lines * 8 + 17
    Win.add({
        id = "hint", title = "HINT", w = w, h = h,
        x = floor((S.vw - w) / 2), y = 14,
        close = Help.dismiss,
        draw = function(x, y, ww, hh)
            for n, l in ipairs(lines) do text("w", l, x + 5, y + 3 + (n - 1) * 8) end
            local by = y + hh - 14
            button("GOT IT", x + 4, by, 50, 11, Help.dismiss, { strong = true })
            button("NO MORE HINTS", x + ww - 66, by, 62, 11, noMore)
        end,
    })
end

--- all of it -------------------------------------------------------------------------------

function Help.draw()
    if current and S.mode == "play" and not S.over then hintWindow() end
    if open then helpWindow() end
end

return Help
