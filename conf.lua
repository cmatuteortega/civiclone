function love.conf(t)
    t.identity = "civiclone"
    t.version = "11.4"
    t.window.title = "Civiclone"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 400
    t.window.vsync = 1
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end
