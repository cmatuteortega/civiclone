-- The settings: stepping through choices, sliders kept in range, keys bound
-- without two commands sharing one, and the file read back as it was written.

local Settings = require "src.settings"

local function eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

return {
    { "defaults", function()
        Settings.reset()
        eq(Settings.get("mode"), "windowed")
        eq(Settings.get("master"), 100)
        eq(Settings.get("grid"), true)
        eq(Settings.key("found"), "b")
    end },

    { "choices go round both ways", function()
        Settings.reset()
        eq(Settings.step("mode", 1), "borderless")
        eq(Settings.step("mode", 1), "fullscreen")
        eq(Settings.step("mode", 1), "windowed")
        eq(Settings.step("mode", -1), "fullscreen")
        eq(Settings.step("grid", 1), false)
        eq(Settings.show("grid"), "OFF")
        -- A list of the screen's own stands in for the setting's.
        Settings.set("resolution", "1280x720")
        eq(Settings.step("resolution", 1, { "1024x576", "1280x720", "1920x1080" }), "1920x1080")
    end },

    { "sliders stop at their ends, in steps", function()
        Settings.reset()
        eq(Settings.step("music", 1), 100)
        Settings.set("music", 43)
        eq(Settings.get("music"), 40)
        Settings.set("music", -20)
        eq(Settings.get("music"), 0)
        eq(Settings.step("music", -1), 0)
    end },

    { "binding a key in use swaps it", function()
        Settings.reset()
        eq(Settings.bind("found", "t"), "research")
        eq(Settings.key("found"), "t")
        eq(Settings.key("research"), "b")
        eq(Settings.commandFor("t"), "found")
        -- Escape and the arrows can't be taken.
        eq(Settings.bind("found", "escape"), false)
        eq(Settings.bind("found", "left"), false)
        eq(Settings.key("found"), "t")
        -- No key ever means two commands.
        local seen = {}
        for _, c in ipairs(Settings.COMMANDS) do
            local k = Settings.key(c.id)
            if seen[k] then error(k .. " bound twice") end
            seen[k] = true
        end
        eq(Settings.keyName("return"), "ENTER")
        eq(Settings.keyName("f11"), "F11")
    end },

    { "the file reads back as written", function()
        Settings.reset()
        Settings.set("mode", "fullscreen")
        Settings.set("resolution", "1920x1080")
        Settings.set("effects", 30)
        Settings.set("showFps", true)
        Settings.set("panSpeed", 1.5)
        Settings.bind("zoomIn", "=")
        Settings.bind("found", "k")
        Settings.setWindow("city", 0.25, 1)
        local text = Settings.serialize()
        Settings.reset()
        Settings.resetWindows()
        Settings.parse(text)
        eq(Settings.get("mode"), "fullscreen")
        eq(Settings.get("resolution"), "1920x1080")
        eq(Settings.get("effects"), 30)
        eq(Settings.get("showFps"), true)
        eq(Settings.get("panSpeed"), 1.5)
        eq(Settings.key("zoomIn"), "=")
        eq(Settings.key("found"), "k")
        eq(Settings.window("city")[1], 0.25)
        eq(Settings.window("city")[2], 1)
        eq(Settings.serialize(), text, "a second write")
    end },

    { "nonsense in the file is passed over", function()
        Settings.reset()
        Settings.resetWindows()
        Settings.parse("mode=sideways\nmaster=900\ngrid=maybe\nnope=1\nkey.found=escape\nkey.bogus=q\n"
            .. "win.unit=x,y\nmusic = 70 \n\n# a comment\nvsync=-1\n")
        eq(Settings.get("mode"), "windowed")
        eq(Settings.get("master"), 100)
        eq(Settings.get("grid"), true)
        eq(Settings.key("found"), "b")
        eq(Settings.window("unit"), nil)
        eq(Settings.get("music"), 70)
        eq(Settings.get("vsync"), -1)
    end },

    { "a tab resets alone", function()
        Settings.reset()
        Settings.set("music", 10)
        Settings.set("animSpeed", 4)
        Settings.bind("found", "k")
        Settings.reset("audio")
        eq(Settings.get("music"), 100)
        eq(Settings.get("animSpeed"), 4)
        eq(Settings.key("found"), "k")
        Settings.reset("controls")
        eq(Settings.key("found"), "b")
        Settings.reset()
    end },
}
