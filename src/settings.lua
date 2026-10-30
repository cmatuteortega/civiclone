-- The player's settings: what each one may be, what it is, the keys bound to
-- each command, and where each window was left. Kept between games in a file
-- of `name=value` lines in the save folder ("settings").
--
-- No LÖVE here but the file, and that guarded: the tests read and write the
-- lines without it. What a setting does is the screen's business (the menu,
-- src/ui/menu.lua, applies the display ones; the rest are read where they
-- matter).

local Settings = {}

-- Every setting, in the order the menu shows them: its tab, its name, what it
-- may be (a list of choices, or a range for a slider) and what it starts as.
-- `show` says how a value reads; a choice without one reads as itself.
local ONOFF = { values = { true, false }, show = function(v) return v and "ON" or "OFF" end }

Settings.LIST = {
    -- Display: applied to the window at once, then kept only if the player says.
    { id = "mode", tab = "display", name = "WINDOW MODE", values = { "windowed", "borderless", "fullscreen" },
        default = "windowed", show = function(v) return v:upper() end },
    { id = "resolution", tab = "display", name = "RESOLUTION", default = "1280x720" },
    { id = "vsync", tab = "display", name = "VSYNC", values = { 1, 0, -1 }, default = 1,
        show = function(v) return ({ [1] = "ON", [0] = "OFF", [-1] = "ADAPTIVE" })[v] end },
    { id = "fps", tab = "display", name = "FRAME RATE LIMIT", values = { 0, 30, 60, 120, 144, 240 }, default = 0,
        show = function(v) return v == 0 and "NONE" or tostring(v) end },
    { id = "seaMotion", tab = "display", name = "MOVING WATER", values = ONOFF.values, show = ONOFF.show, default = true },
    { id = "showFps", tab = "display", name = "SHOW FRAME RATE", values = ONOFF.values, show = ONOFF.show, default = false },
    -- Interface.
    { id = "uiScale", tab = "interface", name = "INTERFACE SIZE", default = 0 },
    { id = "mapScale", tab = "interface", name = "MAP PIXEL SIZE", default = 0 },
    { id = "touch", tab = "interface", name = "TOUCH BUTTONS", values = { "auto", "on", "off" }, default = "auto",
        show = function(v) return v:upper() end },
    { id = "tooltips", tab = "interface", name = "HEX TOOLTIPS", values = ONOFF.values, show = ONOFF.show, default = true },
    { id = "newsTime", tab = "interface", name = "NEWS STAYS FOR", values = { 4, 8, 16, 30 }, default = 8,
        show = function(v) return v .. " SECONDS" end },
    { id = "lockWindows", tab = "interface", name = "LOCK WINDOWS", values = ONOFF.values, show = ONOFF.show, default = false },
    { id = "snapWindows", tab = "interface", name = "SNAP WINDOWS TO EDGES", values = ONOFF.values, show = ONOFF.show, default = true },
    -- Audio: each 0..100, in tens.
    { id = "master", tab = "audio", name = "MASTER VOLUME", min = 0, max = 100, step = 10, default = 100 },
    { id = "music", tab = "audio", name = "MUSIC", min = 0, max = 100, step = 10, default = 100 },
    { id = "ambience", tab = "audio", name = "AMBIENCE", min = 0, max = 100, step = 10, default = 100 },
    { id = "effects", tab = "audio", name = "EFFECTS", min = 0, max = 100, step = 10, default = 100 },
    { id = "muteAway", tab = "audio", name = "MUTE WHEN IN BACKGROUND", values = ONOFF.values, show = ONOFF.show, default = false },
    -- Gameplay.
    { id = "animSpeed", tab = "gameplay", name = "ANIMATION SPEED", values = { 1, 2, 4 }, default = 1,
        show = function(v) return ({ [1] = "NORMAL", [2] = "FAST", [4] = "FASTEST" })[v] end },
    { id = "panSpeed", tab = "gameplay", name = "CAMERA PAN SPEED", values = { 0.5, 1, 1.5, 2 }, default = 1,
        show = function(v) return ({ [0.5] = "SLOW", [1] = "NORMAL", [1.5] = "FAST", [2] = "FASTEST" })[v] end },
    { id = "edgePan", tab = "gameplay", name = "PAN AT SCREEN EDGES", values = ONOFF.values, show = ONOFF.show, default = false },
    { id = "autoCycle", tab = "gameplay", name = "AUTO-SELECT NEXT UNIT", values = ONOFF.values, show = ONOFF.show, default = true },
    { id = "follow", tab = "gameplay", name = "CAMERA FOLLOWS SELECTION", values = ONOFF.values, show = ONOFF.show, default = true },
    { id = "grid", tab = "gameplay", name = "HEX GRID", values = ONOFF.values, show = ONOFF.show, default = true },
}
Settings.BY = {}
for _, s in ipairs(Settings.LIST) do Settings.BY[s.id] = s end

-- The commands keys can be bound to, in the order the menu shows them.
-- Arrows always pan, and Escape always opens the menu: neither is listed.
Settings.COMMANDS = {
    { id = "main", name = "NEXT / END TURN", default = "return" },
    { id = "endTurn", name = "END TURN NOW", default = "end" },
    { id = "nextUnit", name = "NEXT UNIT", default = "tab" },
    { id = "research", name = "RESEARCH", default = "t" },
    { id = "capital", name = "GO TO CAPITAL", default = "h" },
    { id = "grid", name = "HEX GRID", default = "g" },
    { id = "sound", name = "SOUND LOUD/SOFT/OFF", default = "v" },
    { id = "zoomIn", name = "ZOOM IN", default = "=" },
    { id = "zoomOut", name = "ZOOM OUT", default = "-" },
    { id = "panUp", name = "PAN UP", default = "w" },
    { id = "panDown", name = "PAN DOWN", default = "s" },
    { id = "panLeft", name = "PAN LEFT", default = "a" },
    { id = "panRight", name = "PAN RIGHT", default = "d" },
    { id = "found", name = "FOUND CITY", default = "b" },
    { id = "fortify", name = "FORTIFY / WAKE", default = "f" },
    { id = "sleep", name = "SLEEP / WAKE", default = "z" },
    { id = "skip", name = "SKIP UNIT", default = "space" },
    { id = "farm", name = "BUILD FARM", default = "r" },
    { id = "mine", name = "BUILD MINE", default = "m" },
    { id = "fullscreen", name = "TOGGLE FULLSCREEN", default = "f11" },
}
Settings.COMMAND = {}
for _, c in ipairs(Settings.COMMANDS) do Settings.COMMAND[c.id] = c end

-- Keys no command may take.
Settings.RESERVED = { escape = true, up = true, down = true, left = true, right = true }

local values, keys, windows = {}, {}, {}

function Settings.reset(tab)
    for _, s in ipairs(Settings.LIST) do
        if not tab or s.tab == tab then values[s.id] = s.default end
    end
    if not tab or tab == "controls" then
        for _, c in ipairs(Settings.COMMANDS) do keys[c.id] = c.default end
    end
end
Settings.reset()

function Settings.get(id) return values[id] end

function Settings.set(id, v)
    local s = Settings.BY[id]
    if s.min then v = math.max(s.min, math.min(s.max, math.floor(v / s.step + 0.5) * s.step)) end
    values[id] = v
end

-- The next (or, with dir -1, the last) of a setting's choices, round and round;
-- a slider a step up or down, stopping at its ends. `list` stands in for the
-- setting's own choices where they depend on the screen (sizes, resolutions).
function Settings.step(id, dir, list)
    local s = Settings.BY[id]
    if s.min then
        Settings.set(id, values[id] + dir * s.step)
        return values[id]
    end
    list = list or s.values
    local at = 1
    for k, v in ipairs(list) do if v == values[id] then at = k end end
    values[id] = list[(at - 1 + dir) % #list + 1]
    return values[id]
end

-- How a setting's value reads.
function Settings.show(id, v)
    local s = Settings.BY[id]
    if v == nil then v = values[id] end
    if s.show then return s.show(v) end
    if s.min then return tostring(v) end
    return tostring(v):upper()
end

--- keys -----------------------------------------------------------------------------

function Settings.key(cmd) return keys[cmd] end

-- Does key `k` (a LÖVE key name) mean command `cmd`?
function Settings.is(cmd, k) return keys[cmd] == k end

-- The command key `k` is bound to, if any.
function Settings.commandFor(k)
    for _, c in ipairs(Settings.COMMANDS) do if keys[c.id] == k then return c.id end end
end

-- Binds key `k` to command `cmd`. A command that had it gets `cmd`'s old key,
-- so no key means two things and nothing is left without one. Answers the
-- command that swapped, if one did, or false if the key may not be bound.
function Settings.bind(cmd, k)
    if Settings.RESERVED[k] then return false end
    local other = Settings.commandFor(k)
    if other and other ~= cmd then keys[other] = keys[cmd] end
    keys[cmd] = k
    return other ~= cmd and other or nil
end

-- How a key name reads on screen: "SPACE", "ENTER", "F11", "=".
local NAMES = { ["return"] = "ENTER", kpenter = "PAD ENTER", space = "SPACE", tab = "TAB", ["end"] = "END",
    home = "HOME", pageup = "PG UP", pagedown = "PG DN", backspace = "BKSP", delete = "DEL", insert = "INS",
    lshift = "L SHIFT", rshift = "R SHIFT", lctrl = "L CTRL", rctrl = "R CTRL", lalt = "L ALT", ralt = "R ALT" }
function Settings.keyName(k)
    if not k then return "-" end
    return NAMES[k] or k:upper()
end

--- windows ----------------------------------------------------------------------------

-- Where window `id` was left, as a fraction of the room the screen leaves it
-- across and down (so it stays put through a resize), or nil for its own place.
function Settings.window(id) return windows[id] end
function Settings.setWindow(id, fx, fy) windows[id] = fx and { fx, fy } or nil end
function Settings.resetWindows() windows = {} end

--- the file ---------------------------------------------------------------------------

local function encode(v)
    if type(v) == "boolean" then return v and "true" or "false" end
    return tostring(v)
end

local function decode(s, like)
    if type(like) == "boolean" then
        if s == "true" then return true elseif s == "false" then return false end
        return nil
    end
    if type(like) == "number" then return tonumber(s) end
    return s
end

-- Is v one a setting may be? Choices from its list, sliders in range; the
-- screen-dependent ones (sizes, resolution) checked when they're applied.
local function allowed(s, v)
    if v == nil then return false end
    if s.min then return v >= s.min and v <= s.max end
    if not s.values then return true end
    for _, x in ipairs(s.values) do if x == v then return true end end
    return false
end

function Settings.serialize()
    local out = {}
    for _, s in ipairs(Settings.LIST) do out[#out + 1] = s.id .. "=" .. encode(values[s.id]) end
    for _, c in ipairs(Settings.COMMANDS) do out[#out + 1] = "key." .. c.id .. "=" .. keys[c.id] end
    local ids = {}
    for id in pairs(windows) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        out[#out + 1] = ("win.%s=%.4f,%.4f"):format(id, windows[id][1], windows[id][2])
    end
    return table.concat(out, "\n") .. "\n"
end

-- Reads lines as serialize() writes them; anything unknown or out of range is
-- passed over, leaving that setting as it was.
function Settings.parse(text)
    for line in text:gmatch("[^\r\n]+") do
        local name, v = line:match("^%s*([%w%._]+)%s*=%s*(.-)%s*$")
        if name then
            local cmd = name:match("^key%.(.+)$")
            local win = name:match("^win%.(.+)$")
            if cmd then
                if Settings.COMMAND[cmd] and v ~= "" and not Settings.RESERVED[v] then Settings.bind(cmd, v) end
            elseif win then
                local fx, fy = v:match("^([%d%.]+),([%d%.]+)$")
                fx, fy = tonumber(fx), tonumber(fy)
                if fx and fy then windows[win] = { math.min(1, fx), math.min(1, fy) } end
            elseif Settings.BY[name] then
                local s = Settings.BY[name]
                local x = decode(v, s.default)
                if allowed(s, x) then values[name] = x end
            end
        end
    end
end

local FILE = "settings"

function Settings.load()
    if not (love and love.filesystem) then return false end
    local text = love.filesystem.getInfo(FILE) and love.filesystem.read(FILE)
    if text then
        Settings.parse(text)
        return true
    end
    -- Before there were settings there was the sound level alone.
    local old = tonumber(love.filesystem.getInfo("sound") and love.filesystem.read("sound"))
    if old then Settings.set("master", old * 100) end
    return false
end

function Settings.save()
    if not (love and love.filesystem) then return false end
    return pcall(love.filesystem.write, FILE, Settings.serialize())
end

return Settings
