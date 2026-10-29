function love.conf(t)
    t.identity = "civiclone"
    -- The running engine, on purpose: the field only decides whether LÖVE
    -- opens its "Compatibility Warning" box on a mismatch, and this ships on
    -- two engines -- 11.x on desktop, 12.0 in the Android build.
    t.version = love._version
    t.window.title = "Civiclone"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 400
    -- On a phone the whole screen, with no status bar over the HUD.
    t.window.fullscreen = love._os == "Android" or love._os == "iOS"
    t.window.fullscreentype = "desktop"
    -- Real pixels, not points: the zoom is picked off the short edge in pixels
    -- (src/ui/view.lua), and a retina phone should get the zoom its pixels earn.
    t.window.highdpi = true
    t.window.usedpiscale = false
    t.window.vsync = 1
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end
