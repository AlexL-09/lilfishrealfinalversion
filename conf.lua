function love.conf(t)
    t.identity = "lil-fish"
    t.version = "11.5"
    t.window.title = "Lil Fish — The Last Hand"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 960
    t.window.minheight = 540
    t.window.resizable = true
    t.window.vsync = 1
    t.modules.physics = false
    t.modules.joystick = false
end
