local Style = require("style")
local Scene = {}
Scene.__index = Scene

Scene.opponents = {
    {
        name = "Axolotl",
        title = "TRAINER",
        intro = "Welcome, little fish! Let's practice before the show.",
        taunt = "You can do this. Watch the cards!",
    },
    {
        name = "The Host",
        title = "PELICAN",
        intro = "Relax, little contestant. Everyone gets a seat.",
        taunt = "Such a small hand. Such a large appetite.",
    },
    {
        name = "The Dealer",
        title = "SHARK",
        intro = "You remember what I asked for. Don't you?",
        taunt = "Keep your eyes on the cards, little fish.",
    },
    {
        name = "The House",
        title = "COLOSSAL SQUID",
        intro = "One last game. That was the promise.",
        taunt = "One more request. You have come so far.",
    },
}

local portraits = { "axolotl", "pelican", "shark", "squid" }
local palette = Style.colors
local guestLights = {
    { 0.24, 0.10, 0.18 },
    { 0.26, 0.14, 0.07 },
    { 0.08, 0.12, 0.25 },
    { 0.035, 0.24, 0.19 },
}

local abyssShader = [[
    extern number clock;
    extern vec3 stageLight;

    vec4 effect(vec4 tint, Image image, vec2 uv, vec2 pixel) {
        vec2 p = floor(pixel / 4.0) * 4.0 / vec2(1280.0, 720.0);
        float depth = smoothstep(0.0, 0.9, p.y);
        vec3 col = mix(vec3(0.025, 0.12, 0.18), vec3(0.009, 0.02, 0.045), depth);
        vec2 stage = (p - vec2(0.5, 0.19)) * vec2(1.8, 3.2);
        col += stageLight * exp(-dot(stage, stage) * 3.0);
        float ripple = sin(p.x * 22.0 + p.y * 5.0 + clock * 0.22);
        col += pow(max(0.0, ripple), 12.0) * vec3(0.015, 0.035, 0.045) * (1.0 - depth);
        col = floor(col * 64.0) / 64.0;
        return vec4(col, 1.0) * tint;
    }
]]

local function fitted(image, x, y, width, height)
    local scale = math.min(width / image:getWidth(), height / image:getHeight())
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(
        image,
        math.floor(x + (width - image:getWidth() * scale) / 2),
        math.floor(y + (height - image:getHeight() * scale) / 2),
        0,
        scale,
        scale
    )
end

local function diamond(x, y, size, color)
    love.graphics.setColor(color)
    love.graphics.polygon(
        "fill",
        x, y - size,
        x + size, y,
        x, y + size,
        x - size, y
    )
end

function Scene.new()
    local self = setmetatable({
        effects = true,
        reduced = false,
        clock = 0,
    }, Scene)

    local ok, shader = pcall(love.graphics.newShader, abyssShader)
    self.shader = ok and shader or nil
    self:reload()
    return self
end

function Scene:setOptions(reduced, effects, paused)
    self.reduced, self.effects, self.paused = reduced, effects, paused
end

function Scene:reload()
    self.images = {}

    -- Use fish-idle.png for the player instead of the drawn placeholder.
    local names = { "room", "fins", "card-back", "fish-idle" }

    for _, predator in ipairs(portraits) do
        names[#names + 1] = predator .. "-idle"
        names[#names + 1] = predator .. "-threat"
    end

    for _, name in ipairs(names) do
        local path = "assets/images/" .. name .. ".png"
        if love.filesystem.getInfo(path, "file") then
            local ok, image = pcall(love.graphics.newImage, path)
            if ok then
                self.images[name] = image
            end
        end
    end

    self.finQuads = nil
    local fins = self.images.fins

    if fins then
        local width, height = fins:getDimensions()
        self.finQuads = {
            love.graphics.newQuad(0, 0, width / 2, height, width, height),
            love.graphics.newQuad(width / 2, 0, width / 2, height, width, height),
        }
    end
end

function Scene:drawAbyss(time, encounter)
    local g = love.graphics
    local light = guestLights[encounter or 1]

    if self.effects and not self.reduced and not self.paused then
        self.clock = time or 0
    end

    if self.effects and self.shader then
        self.shader:send("clock", self.clock)
        self.shader:send("stageLight", light)
        g.setShader(self.shader)
        g.setColor(1, 1, 1)
        g.rectangle("fill", 0, 0, 1280, 720)
        g.setShader()
    else
        for y = 0, 719, 8 do
            local depth = math.min(1, y / 650)
            g.setColor(
                0.025 - depth * 0.016,
                0.12 - depth * 0.10,
                0.18 - depth * 0.135
            )
            g.rectangle("fill", 0, y, 1280, 8)
        end
    end

    if self.images.room then
        fitted(self.images.room, 0, 0, 1280, 720)
    end

    for i = 0, 4 do
        local x = i * 310 - 180
            + math.floor(math.sin(self.clock * 0.18 + i) * 12 / 4) * 4

        g.setColor(0.38, 0.61, 0.72, 0.035)
        g.polygon("fill", x, 10, x + 48, 10, x + 360, 384, x + 140, 384)
    end

    g.setColor(light[1], light[2], light[3], 0.14)
    g.polygon("fill", 532, 10, 748, 10, 960, 346, 320, 346)

    g.setColor(0.025, 0.065, 0.08)
    g.polygon(
        "fill",
        8, 340, 140, 324, 310, 346, 660, 332,
        950, 344, 1140, 324, 1272, 344, 1272, 404, 8, 404
    )

    for _, plant in ipairs({
        { 36, 168 },
        { 112, 128 },
        { 224, 112 },
        { 330, 208 },
        { 944, 196 },
        { 1044, 108 },
        { 1168, 144 },
        { 1236, 180 },
    }) do
        local x, height = plant[1], plant[2]

        for stem = -1, 1 do
            local root = x + stem * 12

            for y = 0, height - math.abs(stem) * 28, 8 do
                local sway = math.floor(
                    math.sin(y / 42 + self.clock * 0.65 + x)
                    * (4 + y / 20) / 4
                ) * 4

                g.setColor(
                    stem == 0 and 0.045 or 0.035,
                    stem == 0 and 0.18 or 0.11,
                    stem == 0 and 0.17 or 0.13
                )
                g.rectangle("fill", root + sway, 360 - y, 8, 12)

                if y % 32 == 0 then
                    g.rectangle("fill", root + sway - 8, 356 - y, 8, 4)
                    g.rectangle("fill", root + sway + 8, 348 - y, 8, 4)
                end
            end
        end
    end

    g.setColor(palette.ink)
    g.rectangle("fill", 0, 0, 1280, 8)
    g.rectangle("fill", 0, 712, 1280, 8)
    g.rectangle("fill", 0, 0, 8, 720)
    g.rectangle("fill", 1272, 0, 8, 720)

    g.setColor(palette.edge)
    g.rectangle("fill", 8, 8, 1264, 2)
    g.rectangle("fill", 8, 710, 1264, 2)
end

function Scene:drawTable()
    local g = love.graphics

    g.setColor(0.025, 0.04, 0.065)
    g.polygon("fill", 0, 384, 76, 346, 1204, 346, 1280, 384, 1280, 720, 0, 720)

    g.setColor(0.24, 0.10, 0.085)
    g.polygon("fill", 8, 392, 82, 354, 1198, 354, 1272, 392, 1272, 712, 8, 712)

    g.setColor(palette.gold)
    g.polygon("fill", 20, 394, 90, 362, 1190, 362, 1260, 394, 1260, 706, 20, 706)

    g.setColor(0.045, 0.09, 0.085)
    g.polygon("fill", 26, 398, 94, 368, 1186, 368, 1254, 398, 1254, 700, 26, 700)

    g.setColor(0.105, 0.22, 0.20)
    g.polygon("fill", 32, 404, 98, 376, 1182, 376, 1248, 404, 1248, 694, 32, 694)

    for y = 410, 690, 8 do
        g.setColor(0.02, 0.08, 0.08, 0.11)
        g.rectangle("fill", 32, y, 1216, 2)
    end

    for row = 0, 9 do
        for col = 0, 37 do
            local x = 48 + col * 32 + row % 2 * 16
            local y = 402 + row * 30

            g.setColor(0.60, 0.76, 0.57, 0.07)
            g.rectangle("fill", x, y, 2, 2)
            g.rectangle("fill", x + 4, y + 4, 2, 2)
        end
    end

    for _, x in ipairs({ 54, 1226 }) do
        for y = 434, 666, 58 do
            diamond(x, y, 4, palette.gold)
        end
    end

    g.setColor(0.92, 0.64, 0.32, 0.045)
    g.polygon("fill", 380, 376, 900, 376, 1110, 694, 170, 694)
end

local function drawPredator(encounter, impact)
    local g = love.graphics
    g.push("all")
    g.translate(440, 88 + (impact > 0 and 4 or 0))
    g.scale(4, 3)

    if encounter == 1 then
        g.setColor(0.79, 0.43, 0.57)
        g.rectangle("fill", 30, 12, 40, 24)
        g.rectangle("fill", 36, 32, 28, 10)

        for _, x in ipairs({ 24, 70 }) do
            for y = 12, 28, 8 do
                g.rectangle("fill", x, y, 6, 4)
            end
        end

        g.setColor(palette.pink)
        g.rectangle("fill", 36, 38, 6, 7)
        g.rectangle("fill", 58, 38, 6, 7)

        g.setColor(palette.ink)
        g.rectangle("fill", 40, 20, 3, 3)
        g.rectangle("fill", 57, 20, 3, 3)
        g.rectangle("fill", 47, 28, 6, 2)
    else
        g.setColor(0.43, 0.49, 0.51)
        g.polygon(
            "fill",
            4, 13, 24, 22, 38, 13, 48, 13,
            52, 0, 64, 14, 78, 16, 96, 25,
            81, 36, 38, 38, 24, 29, 4, 38, 10, 25
        )

        g.setColor(0.81, 0.81, 0.70)
        g.polygon("fill", 29, 29, 58, 29, 94, 25, 81, 36, 38, 38)

        g.setColor(palette.ink)
        g.polygon("fill", 65, 28, 90, 28, 82, 34, 68, 34)
        g.rectangle("fill", 76, 20, 3, 3)

        for x = 67, 83, 4 do
            g.setColor(palette.paper)
            g.polygon("fill", x, 28, x + 3, 28, x + 1, 31)
        end

        g.setColor(0.25, 0.30, 0.32)
        for x = 50, 58, 4 do
            g.rectangle("fill", x, 21, 1, 6)
        end

        g.polygon("fill", 42, 31, 55, 33, 45, 42)
    end

    g.pop()
end

function Scene:drawGuest(encounter, impact)
    local g = love.graphics
    local guest = Scene.opponents[encounter]

    Style.text(
        guest.name:upper() .. "  /  " .. guest.title,
        474, 28, 14, palette.paper, 332, "center", true
    )

    g.push("all")
    local clipX, clipY = g.transformPoint(396, 70)
    local clipRight, clipBottom = g.transformPoint(884, 240)
    g.setScissor(clipX, clipY, clipRight - clipX, clipBottom - clipY)

    local predator = portraits[encounter]
    local image = (impact or 0) > 0 and self.images[predator .. "-threat"] or nil
    image = image or self.images[predator .. "-idle"]

    if image then
        fitted(image, 400, 76, 480, 160)
    elseif encounter == 4 then
        Style.text("SQUID SPRITE PENDING", 400, 140, 16, palette.muted, 480, "center")
    else
        drawPredator(encounter, impact or 0)
    end

    g.pop()
end

function Scene:drawFins()
    local g = love.graphics
    local flutter = math.floor(math.sin(self.clock * 1.8) * 2)

    for side = 1, 2 do
        g.push("all")
        g.translate(side == 1 and 16 or 1264, 546 + flutter)
        g.scale(side == 1 and 1 or -1, 1)

        if self.finQuads then
            local fins = self.images.fins
            local width, height = fins:getDimensions()
            local scale = math.min(62 / (width / 2), 92 / height)
            g.setColor(1, 1, 1)

            local x = side == 1 and 0 or width / 2 * scale
            g.draw(
                fins,
                self.finQuads[side],
                x, 0, 0,
                side == 1 and scale or -scale,
                scale
            )
        else
            g.scale(2, 2)
            g.setColor(palette.ink)
            g.polygon("fill", 0, 42, 2, 8, 6, 0, 13, 3, 21, 9, 28, 18, 31, 28, 28, 36, 17, 42, 7, 46)

            g.setColor(palette.gold)
            g.polygon("fill", 2, 40, 4, 9, 7, 3, 13, 6, 20, 12, 26, 20, 28, 28, 25, 34, 16, 39, 7, 43)

            g.setColor(palette.pink)
            for _, tip in ipairs({
                { 7, 7 }, { 13, 10 }, { 19, 16 }, { 24, 23 }, { 25, 30 },
            }) do
                g.polygon("fill", 3, 40, tip[1], tip[2], tip[1] + 1, tip[2] + 2)
            end

            g.setColor(palette.paper)
            g.rectangle("fill", 6, 9, 1, 9)
        end

        g.pop()
    end
end

function Scene:drawWorld(state, impact)
    love.graphics.push("all")
    self:drawTable()

    if not state.hidePortrait then
        local encounter = math.max(1, math.min(#Scene.opponents, state.encounter or 1))
        love.graphics.push("all")
        love.graphics.translate(200, -10)
        love.graphics.scale(0.9, 0.9)
        self:drawGuest(encounter, impact)
        love.graphics.pop()
    end

    self:drawFins()
    love.graphics.pop()
end

function Scene:drawPlayer(x, y, scale)
    local g = love.graphics
    scale = scale or 1

    -- Draw the supplied fish sprite instead of the procedural placeholder.
    local fish = self.images["fish-idle"]
    if fish then
        fitted(
            fish,
            x - 40 * scale,
            y - 32 * scale,
            80 * scale,
            64 * scale
        )
        return
    end

    -- Fallback if fish-idle.png is missing.
    g.push("all")
    g.translate(math.floor(x), math.floor(y))
    g.scale(3 * scale, 3 * scale)

    g.setColor(palette.ink)
    g.polygon("fill", -19, -9, -10, -5, -5, -9, 7, -8, 14, 0, 7, 8, -5, 9, -10, 5, -19, 9)

    g.setColor(palette.gold)
    g.polygon("fill", -17, -6, -9, -2, -4, -6, 6, -5, 11, 0, 6, 5, -4, 6, -9, 2, -17, 6)

    g.setColor(palette.pink)
    g.polygon("fill", -3, 3, 3, 2, -1, 7)

    g.setColor(palette.paper)
    g.rectangle("fill", 5, -4, 3, 3)

    g.setColor(palette.ink)
    g.rectangle("fill", 7, -3, 1, 2)

    g.pop()
end

local function cinemaCaption(title, caption)
    local g = love.graphics

    g.setColor(palette.ink)
    g.rectangle("fill", 0, 0, 1280, 76)
    g.rectangle("fill", 0, 592, 1280, 128)

    Style.text(title, 100, 18, 20, palette.gold, 900, "left", false)
    Style.text(caption, 100, 620, 20, palette.paper, 1080, "center")
end

function Scene:drawOpening(time)
    local g = love.graphics
    local shot = time < 2 and 1 or time < 4.4 and 2 or 3
    local drift = self.reduced and 0 or math.sin(time * 1.5) * 6

    g.push("all")

    if shot == 1 then
        g.push("all")
        g.translate(470, 125)
        g.scale(0.65, 0.65)
        self:drawTable()
        g.pop()

        self:drawPlayer(280 + (self.reduced and 0 or time * 28), 335 + drift, 0.75)
    elseif shot == 2 then
        self:drawPlayer(
            640,
            335 + drift,
            self.reduced and 3.6 or 3.4 + (time - 2) * 0.15
        )
    else
        self:drawTable()
        g.push("all")
        g.translate(200, 70)
        g.scale(0.9, 0.9)
        self:drawGuest(1, 0)
        g.pop()

        self:drawPlayer(360 + (self.reduced and 0 or (time - 4.4) * 26), 330 + drift, 1.25)
    end

    local titles = {
        "SOMEWHERE BELOW THE SURFACE",
        "THE LITTLE GUY",
        "A SEAT AT THE TABLE",
    }

    local captions = {
        "A very big show. A (very very) small contestant.",
        "Small fins. A little bit of hope. That's you.",
        "Welcome, little fish. Let's learn the game.",
    }

    cinemaCaption(titles[shot], captions[shot])
    g.pop()
end

function Scene:drawEnding(time)
    local g = love.graphics
    time = math.max(0, math.min(6, time or 0))

    if self.reduced then
        time = time < 2 and 0 or time < 4.6 and 4 or 6
    end

    local pull = math.max(0, math.min(1, (time - 1.6) / 2.2))
    local shrink = 1 - math.max(0, math.min(1, (time - 3.8) / 0.8))
    local fishX = 360 + 540 * pull
    local fishY = 454 - 124 * pull - math.sin(pull * math.pi) * 36
    local reach = math.max(0, math.min(1, (time - 0.6)))
    local tipX = 900 + (fishX - 900) * reach
    local tipY = 370 + (fishY - 370) * reach

    g.push("all")
    g.setColor(0.015, 0.035, 0.045, 0.6)
    g.rectangle("fill", 0, 0, 1280, 720)

    g.push("all")

    if time >= 1.6 and time < 3.8 then
        local zoom = self.reduced and 1.25 or 1.25 + pull * 0.15
        g.translate(520, 350)
        g.scale(zoom, zoom)
        g.translate(-fishX, -fishY)
    elseif time >= 3.8 and time < 4.6 then
        g.translate(640, 350)
        g.scale(1.8, 1.8)
        g.translate(-900, -330)
    end

    -- The grabbing arms remain visible with supplied portraits.
    g.setColor(0.13, 0.085, 0.17)
    g.polygon("fill", 868, 330, tipX - 36, tipY - 10, tipX - 30, tipY + 28, 920, 362)

    g.setColor(0.37, 0.20, 0.35)
    g.polygon("fill", 876, 336, tipX - 26, tipY, tipX - 22, tipY + 18, 910, 354)

    for i = 1, 6 do
        local part = i / 7
        g.setColor(palette.pink)
        g.rectangle(
            "fill",
            math.floor(890 + (tipX - 890) * part),
            math.floor(346 + (tipY - 346) * part),
            8, 8
        )
    end

    local squid = self.images["squid-threat"] or self.images["squid-idle"]

    if squid then
        fitted(squid, 736, 108, 328, 440)
    else
        g.push("all")
        g.translate(900, 330)
        g.scale(4, 4)

        g.setColor(0.13, 0.085, 0.17)
        g.polygon("fill", 0, -58, -30, -25, -22, -4, -16, 8, 16, 8, 22, -4, 30, -25)

        g.setColor(0.40, 0.22, 0.37)
        g.polygon("fill", 0, -54, -25, -25, -18, -4, -13, 6, 13, 6, 18, -4, 25, -25)
        g.polygon("fill", -25, -34, -39, -17, -21, -22)
        g.polygon("fill", 25, -34, 39, -17, 21, -22)

        for i = 1, 8 do
            local x = (i - 4.5) * 4

            g.setColor(i % 2 == 0 and 0.40 or 0.30, 0.18, 0.32)
            g.polygon(
                "fill",
                x, 4, x + 4, 4,
                x * 1.8 + 8, 38 + math.abs(x),
                x * 1.8 + 2, 42 + math.abs(x)
            )

            g.setColor(palette.pink)
            g.rectangle("fill", x * 1.5 + 2, 27 + math.abs(x), 2, 3)
        end

        for _, x in ipairs({ -16, 8 }) do
            g.setColor(palette.paper)
            g.rectangle("fill", x, -14, 8, 8)

            g.setColor(palette.ink)
            g.rectangle("fill", x + 1, -12, 3, 5)
        end

        g.setColor(palette.ink)
        g.polygon("fill", -7, 0, 0, -5, 7, 0, 0, 11)
        g.pop()
    end

    if time < 4.6 then
        self:drawPlayer(fishX, fishY, shrink)
    end

    g.pop()

    if time >= 4.6 then
        g.setColor(0.01, 0.02, 0.03, math.min(0.8, (time - 4.6) / 1.4 * 0.8))
        g.rectangle("fill", 0, 0, 1280, 720)
    end

    cinemaCaption(
        "THE LAST HAND",
        time < 1.6 and "That's my last one for the day. Wrap it up camera crew we're done here." or "You were always on the menu."
    )

    g.pop()
end

return Scene