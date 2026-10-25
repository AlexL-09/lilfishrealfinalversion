local Game = require("game")
local Scene = require("scene")
local VFX = require("vfx")
local Audio = require("audio")
local Style = require("style")
local Motion = require("ui_motion")
local g = love.graphics
local W, H = 1280, 720
local app = {
    screen = "title",
    time = 0,
    queue = {},
    buttons = {},
    selected = 1,
    settings = { volume = 0.65, muted = false, reduced = false, effects = true },
}
local palette = Style.colors
local scene, vfx, audio, canvas, crt
local motion = Motion.new()

local function inside(control, x, y)
    return x >= control.x and x <= control.x + control.w and y >= control.y and y <= control.y + control.h
end

local function cancelPress()
    if app.pressed then
        motion:release(app.pressed.id, false)
        app.pressed = nil
    end
end

local function tap(id)
    motion:press(id)
    motion:release(id, true)
end

local function color(tint, alpha)
    g.setColor(tint[1], tint[2], tint[3], alpha or 1)
end

local function text(value, x, y, size, tint, width, align)
    Style.text(value, x, y, size, tint, width, align)
end

local function transform()
    local windowWidth, windowHeight = g.getDimensions()
    local scale = math.min(windowWidth / W, windowHeight / H)
    return scale, (windowWidth - W * scale) / 2, (windowHeight - H * scale) / 2
end

local function pointer(x, y)
    local scale, ox, oy = transform()
    return (x - ox) / scale, (y - oy) / scale
end

local function button(label, x, y, w, h, action, enabled, accent)
    if enabled == nil then
        enabled = true
    end
    local mx, my = pointer(love.mouse.getPosition())
    local hover = enabled and mx >= x and mx <= x + w and my >= y and my <= y + h
    local id = "button:" .. app.screen .. ":" .. tostring(app.overlay) .. ":" .. x .. ":" .. y
    local animation = motion:sample(id, hover, false)
    local base = enabled and (accent or palette.teal) or { 0.22, 0.26, 0.29 }
    local fill = {}
    for i = 1, 3 do
        fill[i] = base[i] + (palette.paper[i] - base[i]) * animation.hover * 0.20
    end
    Style.panel(x, y + animation.y, w, h, fill, palette.edge, animation.press)
    if animation.flash > 0 then
        color(palette.gold, animation.flash * 0.75)
        g.rectangle("fill", x + 5, y + animation.y + 4, w - 10, 2)
    end
    local light = accent == palette.paper
        or accent == palette.mint
        or accent == palette.gold
        or accent == palette.purple
    Style.text(
        label,
        x,
        y + animation.y + math.floor((h - Style.font(16):getHeight()) / 2),
        16,
        enabled and (light and palette.ink or palette.paper) or palette.muted,
        w,
        "center",
        true
    )
    app.buttons[#app.buttons + 1] = {
        id = id,
        x = x,
        y = y,
        w = w,
        h = h,
        action = action,
        enabled = enabled,
        label = label,
        screen = app.screen,
        overlay = app.overlay,
    }
end

local function applySettings()
    vfx:setOptions(app.settings.reduced, app.settings.effects)
    motion:update(0, app.settings.reduced)
    if scene.setOptions then
        scene:setOptions(app.settings.reduced, app.settings.effects, app.overlay ~= nil)
    end
    audio:setVolume(app.settings.volume)
    audio:setMuted(app.settings.muted)
end

local function busy()
    return app.intro ~= nil or app.active ~= nil or #app.queue > 0
end

local function enqueue(events)
    for _, event in ipairs(events or {}) do
        app.queue[#app.queue + 1] = event
    end
end

local function legalSelection()
    local lesson = Game.lesson(app.state)
    if lesson and lesson.rank then
        app.selected = lesson.rank
        return
    end
    local ranks = Game.legalRanks(app.state)
    for _, rank in ipairs(ranks) do
        if rank == app.selected then
            return
        end
    end
    app.selected = ranks[1] or 1
end

local function startRun(seed)
    cancelPress()
    motion:clear()
    app.seed = seed or (os.time() + math.floor(love.timer.getTime() * 1000)) % 2147483646 + 1
    app.state = Game.new(app.seed)
    app.screen, app.overlay, app.active = "play", nil, nil
    app.queue, app.log, app.message = {}, {}, "A practice table. A (definetely) friendly guy."
    app.dialogue = Scene.opponents[1].intro
    app.selected, app.rewardSelection = 1, 1
    app.intro, app.devour = 0, nil
    vfx = VFX.new()
    applySettings()
    audio:setPlaying(true)
    enqueue(app.state.openingEvents)
    legalSelection()
end

local function act(fn, ...)
    if busy() or app.overlay then
        return
    end
    local events, err = fn(app.state, ...)
    if not events then
        app.message = err or "Choose a rank in your hand."
        return
    end
    enqueue(events)
    legalSelection()
end

local function advance()
    if busy() then
        return
    end
    local events, err = Game.nextEncounter(app.state)
    if not events then
        app.message = err
        return
    end
    app.queue, app.active, app.log, app.rewardSelection = {}, nil, {}, 1
    enqueue(events)
    app.dialogue = Scene.opponents[app.state.encounter].intro
    app.message = "The lights come back on. Someone else is in the chair."
    legalSelection()
end

local function retryEncounter()
    if busy() or app.overlay then
        return
    end
    local events, err = Game.retryEncounter(app.state)
    if not events then
        app.message = err
        return
    end
    cancelPress()
    motion:clear()
    app.queue, app.active, app.log, app.rewardSelection = {}, nil, {}, 1
    app.intro, app.devour = nil, nil
    app.dialogue = Scene.opponents[app.state.encounter].intro
    app.message = "A fresh hand. Same opponent. Your powers stay with you."
    vfx = VFX.new()
    applySettings()
    enqueue(events)
    legalSelection()
end

local function addLog(message)
    app.log[#app.log + 1] = message
    if #app.log > 3 then
        table.remove(app.log, 1)
    end
end

local function beginEvent(event)
    local duration = 0.20
    if event.type == "request" then
        app.message = (event.actor == "player" and "You ask" or "The predator asks")
            .. " for "
            .. tostring(event.rank)
            .. "s."
        addLog((event.actor == "player" and "YOU" or "THEM") .. "  >  " .. tostring(event.rank))
        duration = 0.34
    elseif event.type == "transfer" then
        app.message = "Yes. " .. tostring(event.count or 1) .. " card(s) change fins."
        duration = event.actor == "enemy" and 0.47 or 0.35
    elseif event.type == "draw" then
        app.message = "Go fish. " .. (event.actor == "player" and "You draw." or "They draw.")
        duration = event.actor == "enemy" and 0.47 or 0.35
    elseif event.type == "set" then
        app.message = (event.actor == "player" and "Your" or "Their") .. " set of " .. tostring(event.rank) .. "s."
      
        vfx:celebrate(640, 430)
        duration = 0.40
    elseif event.type == "damage" then
        app.message = (event.actor == "player" and "You lose " or "The predator loses ")
            .. tostring(event.amount)
            .. " HP."
        if event.source == "bite" then
            app.dialogue = "Careful. That was a very confident guess."
        end
        duration = 0.35
    elseif event.type == "victory" then
        app.message = app.state.encounter == 1 and "Practice complete! You're ready for the big guys."
            or "You won your seat at the next table."
      
        duration = 0.5
    elseif event.type == "defeat" then
        app.message = "The house would like to thank you for playing."
    
        duration = 0.5
    elseif event.type == "betrayal" then
        app.message = "The empty health bar fills again. The squid never agreed to lose."
        app.dialogue = "The house always wins, little guy."
        duration = 1.5
    elseif event.type == "devour" then
        app.message = "You were always on the menu, little guy."
        app.devour, duration = 0, 6
    
    elseif event.type == "power" or event.type == "reward" then
        app.message = Game.powers[event.power].name .. (event.type == "reward" and " joins your run." or " activates!")
    elseif event.type == "peek" then
        app.message = "Keen Eye: the opponent holds " .. event.rank .. "s."
        duration = 0.5
    elseif event.type == "heal" then
        app.message = "Second Wind restores " .. event.amount .. " HP."
    end
    app.active = { event = event, elapsed = 0, duration = duration, contacted = false }
end

local function updateEvents(dt)
    if not app.active then
        if #app.queue > 0 then
            beginEvent(table.remove(app.queue, 1))
        elseif app.state.phase == "enemy" then
            local events, err = Game.enemyTurn(app.state)
            if not events then
                error(err)
            end
            enqueue(events)
            legalSelection()
        end
    end
    local active = app.active
    if not active then
        return
    end
    active.elapsed = active.elapsed + dt
    local event = active.event
    if (event.type == "transfer" or event.type == "draw") and not active.contacted then
        local contact = event.actor == "enemy" and 0.22 or 0.13
        if active.elapsed >= contact then
            active.contacted = true
            vfx:impact(event.actor == "enemy" and "predator" or "player", 776, 300, 1)
            
        end
    end
    if active.elapsed >= active.duration then
        app.active = nil
    end
end

local function countRanks(cards)
    local counts = {}
    for i = 1, 8 do
        counts[i] = 0
    end
    for _, rank in ipairs(cards) do
        counts[rank] = counts[rank] + 1
    end
    return counts
end
local pipLayouts = {
    { { 50, 72 } },
    { { 50, 43 }, { 50, 101 } },
    { { 50, 43 }, { 50, 72 }, { 50, 101 } },
    { { 34, 43 }, { 66, 43 }, { 34, 101 }, { 66, 101 } },
    { { 34, 43 }, { 66, 43 }, { 50, 72 }, { 34, 101 }, { 66, 101 } },
    { { 34, 43 }, { 66, 43 }, { 34, 72 }, { 66, 72 }, { 34, 101 }, { 66, 101 } },
    { { 34, 43 }, { 66, 43 }, { 50, 58 }, { 34, 72 }, { 66, 72 }, { 34, 101 }, { 66, 101 } },
    { { 34, 43 }, { 66, 43 }, { 50, 58 }, { 34, 72 }, { 66, 72 }, { 50, 87 }, { 34, 101 }, { 66, 101 } },
}

local function card(rank, count, x, y, selected, disabled)
    local mx, my = pointer(love.mouse.getPosition())
    local hover = not disabled and mx >= x and mx <= x + 100 and my >= y - 10 and my <= y + 144
    local id = "card:" .. rank
    local animation = motion:sample(id, hover, selected)
    local cardY = y + animation.y
    for i = math.min(count - 1, 3), 1, -1 do
        Style.panel(x + i * 2, cardY + i * 3, 100, 144, { 0.76, 0.76, 0.69 }, palette.ink)
    end
    Style.panel(x, cardY, 100, 144, palette.paper, selected and palette.gold or palette.ink, animation.press)
    local suit = (rank - 1) % 4 + 1
    local faceColor = (suit == 1 or suit == 3) and { 0.69, 0.22, 0.21 } or { 0.12, 0.22, 0.27 }
    Style.text(rank, x + 8, cardY + 3, 16, faceColor, nil, nil, false)
    Style.pip(suit, x + 10, cardY + 33, 1, faceColor)
    for _, point in ipairs(pipLayouts[rank]) do
        Style.pip(suit, x + point[1] - 7, cardY + point[2] - 7, 2, faceColor)
    end
    g.push("all")
    g.translate(x + 100, cardY + 144)
    g.scale(-1, -1)
    Style.text(rank, 8, 3, 16, faceColor, nil, nil, false)
    Style.pip(suit, 10, 33, 1, faceColor)
    g.pop()
    if count > 1 then
        Style.panel(x + 30, cardY + 130, 40, 25, palette.deep, palette.deep)
        text("x" .. count, x + 30, cardY + 131, 12, palette.paper, 40, "center")
    end
    if selected then
        color(palette.gold)
        g.rectangle("fill", x + 22, cardY + 162, 56, 3, 1, 1)
    end
    if not disabled then
        app.buttons[#app.buttons + 1] = {
            id = id,
            x = x,
            y = y - 10,
            w = 100,
            h = 154,
            enabled = true,
            screen = app.screen,
            overlay = app.overlay,
            action = function()
                app.selected = rank
            end,
        }
    end
end

local function drawPlayedCard()
    local active = app.active
    if not active or (active.event.type ~= "transfer" and active.event.type ~= "draw") then
        return
    end
    local event, elapsed = active.event, active.elapsed
    local isEnemy = event.actor == "enemy"
    local y = 264
    if not app.settings.reduced then
        if isEnemy then
            if elapsed < 0.12 then
                y = 206 - 22 * elapsed / 0.12
            elseif elapsed < 0.22 then
                y = 184 + 80 * ((elapsed - 0.12) / 0.10) ^ 2
            end
        elseif elapsed < 0.13 then
            y = 470 - 206 * elapsed / 0.13
        end
    end
    local image = scene.images and scene.images["card-back"]
    Style.cardBack(740, y, 72, 104)
    if image then
        color({ 1, 1, 1 })
        g.draw(image, 744, y + 4, 0, 64 / image:getWidth(), 96 / image:getHeight())
    end
end

local function drawWorld()
    g.push("all")
    g.setCanvas(canvas)
    g.clear(0.06, 0.09, 0.12, 1)
    local sx, sy = vfx:offset()
    g.translate(sx, sy)
    local impact = app.active and app.active.contacted and 1 or 0
    scene:setOptions(app.settings.reduced, app.settings.effects, app.overlay ~= nil)
    scene:drawAbyss(app.time, app.screen == "play" and app.state.encounter or 1)
    vfx:drawAmbient()
    if app.screen == "play" and app.intro then
        scene:drawOpening(app.intro)
    elseif app.screen == "play" and app.devour then
        scene:drawEnding(app.devour)
    else
        scene:drawWorld(app.screen == "play" and app.state or { encounter = 1, hidePortrait = true }, impact)
    end
    if app.screen == "play" and not app.intro and not app.devour then
        local backs = math.min(#app.state.enemy, 5)
        local image = scene.images["card-back"]
        for i = 1, backs do
            local x, y = 776 + (i - (backs + 1) / 2) * 27, 250 - vfx:hop()
            Style.cardBack(x - 22, y, 44, 64)
            if image then
                color({ 1, 1, 1 })
                g.draw(image, x - 19, y + 3, 0, 38 / image:getWidth(), 58 / image:getHeight())
            end
        end
        drawPlayedCard()
    end
    vfx:drawBursts()
    g.pop()
end

local function hud()
    local state = app.state
    local lesson = Game.lesson(state)
    local status, instruction, accent = "ROUND OVER", "HAND COMPLETE", palette.gold
    if busy() then
        status, instruction = "Game is in session", "CARDS IN MOTION"
    elseif state.phase == "ask" then
        status, instruction, accent = "YOUR TURN", "CHOOSE A RANK", palette.teal
    elseif state.phase == "choice" then
        status, instruction, accent = "PUSH OR BANK", "SUCCESS " .. state.streak, palette.pink
    elseif state.phase == "enemy" then
        status, instruction, accent = "THEIR TURN", "WATCH THE TABLE", palette.pink
    end

    Style.panel(24, 24, 260, 320, { 0.26, 0.24, 0.21 }, { 0.49, 0.39, 0.27 })
    text("LIL FISH", 42, 32, 28, palette.paper)
    color(palette.pink)
    g.rectangle("fill", 242, 48, 12, 8, 2, 2)
    text("LIVE", 223, 66, 12, palette.muted, 50, "center")
    Style.panel(40, 92, 228, 88, { 0.09, 0.27, 0.27 }, palette.ink)
    text("YOUR HEALTH", 54, 104, 14, palette.muted)
    text(state.playerHP, 185, 94, 40, palette.paper, 68, "center")
    for i = 1, 6 do
        color(i <= state.playerHP and palette.teal or palette.edge)
        g.rectangle("fill", 54 + (i - 1) * 32, 158, 24, 5)
    end
    Style.panel(40, 194, 104, 76, palette.deep, palette.ink)
    Style.panel(158, 194, 110, 76, palette.deep, palette.ink)
    text(state.encounter == 1 and "LESSON" or "BOSS", 40, 198, 12, palette.muted, 104, "center")
    text("STREAK", 158, 198, 12, palette.muted, 110, "center")
    text(state.encounter == 1 and "INTRO" or ((state.encounter - 1) .. " / 3"), 40, 226, 20, palette.gold, 104, "center")
    text(state.streak, 158, 222, 28, state.pushed and palette.pink or palette.paper, 110, "center")
    button("INFO", 40, 290, 104, 38, function()
        app.overlay = "help"
    end, true, palette.gold)
    button("OPTIONS", 158, 290, 110, 38, function()
        app.overlay = "settings"
    end, true, palette.gold)

    Style.panel(938, 142, 100, 70, palette.deep, palette.edge)
    text("HP LEFT", 942, 146, 12, palette.muted, 92, "center")
    text(state.enemyHP, 942, 169, 28, palette.pink, 92, "center")
    text(lesson and ("TRAINING " .. state.tutorial .. " / " .. #Game.lessons) or status, 346, 32, 16, accent, 230, "left")
    text(state.encounter == 1 and "Practice with me. Then face the (mafia) bosses!" or (app.dialogue or ""), 410, 207, 14, palette.paper, 640, "center")
    text("LAST REQUESTS", 1090, 42, 12, palette.muted, 160, "center")
    if #app.log == 0 then
        text("-", 1090, 78, 14, palette.muted, 160, "center")
    end
    for i, line in ipairs(app.log) do
        text(line, 1090, 70 + i * 28, 14, line:sub(1, 3) == "YOU" and palette.paper or palette.pink, 160, "center")
    end
    if #state.powers > 0 then
        button("POWERS", 1090, 220, 160, 32, function()
            app.overlay = "powers"
        end, true, palette.gold)
        for i, id in ipairs(state.powers) do
            local power, y = Game.powers[id], 262 + (i - 1) * 58
            local status = id == "blood_in_the_water" and (state.playerHP <= 3 and "ACTIVE" or "AT 3 HP")
                or state.used[id] and "USED" or "READY"
            Style.panel(1090, y, 160, 50, palette.deep, palette.edge)
            text(power.icon, 1097, y + 7, 16, palette.gold, 28, "center")
            text(power.short, 1128, y + 2, 12, palette.paper, 116)
            text(status, 1128, y + 25, 12, status == "USED" and palette.muted or palette.mint, 116)
        end
    end
    if Game.hasPower(state, "keen_eye") then
        if state.peeked then
            text("REVEALED: " .. state.peeked .. "s", 1090, 182, 12, palette.gold, 160, "center")
        else
            button("PEEK  [P]", 1090, 178, 160, 32, function()
                act(Game.peek)
            end, not busy() and not app.overlay and state.phase == "ask" and not state.used.keen_eye and #state.enemy > 0, palette.mint)
        end
    end
    text(#state.enemy .. " CARDS", 696, 316, 12, palette.muted, 160, "center")

    local heading = busy() and instruction
        or state.phase == "choice" and "PUSH YOUR LUCK?"
        or state.phase == "ask" and ("ASK FOR " .. app.selected .. "s")
        or instruction
    text(heading, 340, 374, 28, state.phase == "choice" and palette.gold or palette.paper, 730, "center")
    text(app.message or "", 340, 418, 14, palette.muted, 730, "center")
    text(instruction .. "  /  YOUR HAND", 340, 438, 12, palette.muted)
    text(#state.player .. " CARDS", 900, 438, 12, palette.muted, 170, "right")
    local locked = busy() or app.overlay ~= nil or state.phase ~= "ask"
    local counts, ranks = countRanks(state.player), Game.legalRanks(state)
    local step = math.min(112, 648 / math.max(1, #ranks - 1))
    local start = 332 + (748 - (100 + step * (#ranks - 1))) / 2
    for i, rank in ipairs(ranks) do
        card(rank, counts[rank], start + (i - 1) * step, 470, rank == app.selected, locked)
    end
    local deckImage = scene.images["card-back"]
    for i = 3, 0, -1 do
        Style.cardBack(1130 + i * 2, 462 + i * 3, 94, 136)
    end
    if deckImage then
        color({ 1, 1, 1 })
        g.draw(deckImage, 1136, 468, 0, 82 / deckImage:getWidth(), 124 / deckImage:getHeight())
    end
    text(#state.deck .. " LEFT", 1114, 614, 12, palette.muted, 130, "center")

    local hint = ""
    if busy() then
        hint = "Cards are moving. Watch the table."
    elseif state.phase == "ask" then
        hint = state.streak > 0 and "A miss costs 1 HP. Complete a set on your streak for 3 damage."
            or "Choose a rank. Collect four to deal 2 damage."
        button("ASK  [ENTER]", 562, 638, 286, 46, function()
            act(Game.ask, app.selected)
        end, counts[app.selected] > 0, palette.teal)
    elseif state.phase == "choice" then
        hint = "Bank your turn safely, or push again and risk a bite."
        button("BANK  [SPACE]", 444, 638, 246, 46, function()
            act(Game.bank)
        end, not lesson or lesson.action == "bank", palette.teal)
        button("PUSH  [ENTER]", 710, 638, 246, 46, function()
            act(Game.push)
        end, not lesson or lesson.action == "push", palette.pink)
    end
    text(lesson and "AXOLOTL'S TIP" or "YOUR MOVE", 64, 428, 14, palette.gold, 210, "center")
    text(lesson and (busy() and "Watch the table. Your next tip is coming!" or lesson.text) or hint, 64, 470, 12, palette.muted, 210, "center")
end

local function drawTitle()
    text("THE UNDERWATER GAME SHOW", 100, 138, 14, palette.gold)
    text("LIL FISH", 94, 174, 64, palette.paper)
    text("THE LAST HAND", 102, 282, 28, palette.pink)
    text("Three bosses. One little contestant.", 104, 382, 16, palette.paper)
    text("Learn with Axolotl. Enter the show. Make it home.", 104, 430, 14, palette.muted)
    button("TAKE YOUR SEAT  [ENTER]", 104, 475, 510, 52, function()
        startRun()
    end, true, palette.teal)
    button("HOW TO PLAY", 104, 543, 240, 46, function()
        app.overlay = "help"
    end, true, palette.pink)
    button("SETTINGS", 374, 543, 240, 46, function()
        app.overlay = "settings"
    end, true, palette.gold)
    g.push("all")
    g.translate(795, 194)
    g.rotate(-0.12)
    Style.cardBack(0, 0, 140, 202)
    g.pop()
    g.push("all")
    g.translate(901, 230)
    g.rotate(0.10)
    g.scale(1.4, 1.4)
    card(7, 1, 0, 0, false, true)
    g.pop()
    text("SMALL FINS. HIGH STAKES.", 735, 480, 14, palette.paper, 430, "center")
    text("M  mute    /    F6  reduced motion    /    F7  effects", 104, 662, 12, palette.muted)
end

local function outcome()
    local state = app.state
    if busy() or (state.phase ~= "won" and state.phase ~= "lost" and state.phase ~= "eaten") then
        return
    end
    color({ 0.03, 0.05, 0.08 }, 0.9)
    g.rectangle("fill", 0, 0, W, H)
    app.buttons = {}
    local options = Game.rewardOptions(state)
    if options then
        text("CHOOSE A POWERUP", 160, 100, 40, palette.mint, 960, "center")
        text(Scene.opponents[state.encounter].name .. "'s reward. Keep one power for this run.", 160, 180, 16, palette.paper, 960, "center")
        for i, id in ipairs(options) do
            local power, x = Game.powers[id], 160 + (i - 1) * 504
            local selected = app.rewardSelection == i
            Style.panel(x, 250, 456, 300, palette.deep, selected and palette.gold or palette.edge)
            Style.panel(x + 20, 272, 48, 48, palette.ink, palette.gold)
            text(power.icon, x + 20, 276, 20, palette.gold, 48, "center")
            text(power.name:upper(), x + 82, 280, 20, palette.paper, 354)
            text(power.text, x + 24, 350, 16, palette.muted, 408)
            button("TAKE POWER  [" .. i .. "]", x + 48, 482, 360, 46, function()
                act(Game.chooseReward, id)
            end, true, selected and palette.gold or palette.teal)
        end
        text("1 / 2 or LEFT / RIGHT to select. ENTER to confirm.", 160, 584, 16, palette.paper, 960, "center")
        text("Limited uses refresh each duel. Powers reset on a new run.", 160, 628, 14, palette.muted, 960, "center")
        return
    end
    local won, eaten = state.phase == "won", state.phase == "eaten"
    text(
        eaten and "THE HOUSE ALWAYS WINS." or won and (state.encounter == 1 and "PRACTICE COMPLETE!" or "YOU KEEP YOUR SEAT.") or "THANK YOU FOR PLAYING.",
        160,
        238,
        40,
        won and palette.mint or palette.pink,
        960,
        "center"
    )
    text(
        eaten and "The colossal squid takes its last contestant."
            or won and (state.encounter == 1 and "Well done, little fish! Start the show with full health."
                or "The next guest is waiting. Recover 2 HP and keep going.")
            or "Take a fresh hand against the same opponent. Keep your powers.",
        220,
        315,
        20,
        palette.paper,
        840,
        "center"
    )
    if won then
        local reward = state.powers[state.encounter]
        if reward then
            text("POWER GAINED: " .. Game.powers[reward].name:upper(), 220, 366, 14, palette.gold, 840, "center")
        end
        button(
            state.encounter == 1 and "START THE SHOW  [ENTER]" or "NEXT PREDATOR  [ENTER]",
            390,
            400,
            500,
            54,
            advance,
            true
        )
    else
        button("RETRY OPPONENT  [ENTER]", 390, 400, 500, 54, retryEncounter, true)
    end
    button("RETURN TO TITLE", 440, 477, 400, 40, function()
        app.screen = "title"
        audio:setPlaying(false)
    end, true, palette.paper)
end

local function overlay()
    if not app.overlay then
        return
    end
    color({ 0.02, 0.04, 0.06 }, 0.94)
    g.rectangle("fill", 0, 0, W, H)
    if app.overlay == "powers" then
        text("YOUR RUN POWERS", 170, 85, 40, palette.mint)
        for i, id in ipairs(app.state.powers) do
            local power, y = Game.powers[id], 175 + (i - 1) * 130
            text(power.icon .. "  " .. power.name:upper(), 175, y, 20, palette.gold)
            text(power.text, 175, y + 45, 16, palette.paper, 930)
        end
        text("Limited uses refresh each duel. Powers reset on a new run.", 175, 565, 14, palette.muted)
    elseif app.overlay == "help" then
        text("HOW TO STAY OFF THE MENU", 170, 100, 40, palette.mint)
        local rules = {
            "1. Select a rank in your hand. Ask for every matching opponent card.",
            "2. Four matching cards make a set: deal 2 damage.",
            "3. After success, BANK safely or PUSH for another request.",
            "4. On success #2 and beyond, completed sets deal 3 damage.",
            "5. A pushed miss bites for 1 HP. Any miss draws and ends your turn.",
            "6. Predators ask once per turn. Their requests reveal their cards.",
            "7. Practice with Axolotl, then beat three bosses. Boss wins heal 2 HP.",
        }
        for i, line in ipairs(rules) do
            text(line, 175, 183 + (i - 1) * 47, 20, palette.paper)
        end
        text("1–8 select a rank  ·  ENTER ask / push  ·  SPACE bank  ·  ESC pause", 175, 548, 16, palette.muted)
        text("Choose a power after each early victory. P uses Keen Eye.", 175, 581, 14, palette.gold)
    else
        text(app.screen == "play" and "THE SHOW IS PAUSED" or "SETTINGS", 245, 105, 40, palette.paper)
        if app.seed then
            text("SEED  " .. app.seed, 250, 164, 12, palette.muted)
        end
        text("MASTER VOLUME  " .. math.floor(app.settings.volume * 100 + 0.5) .. "%", 250, 205, 20)
        button("−", 850, 198, 64, 42, function()
            app.settings.volume = math.max(0, app.settings.volume - 0.1)
            applySettings()
        end)
        button("+", 930, 198, 64, 42, function()
            app.settings.volume = math.min(1, app.settings.volume + 0.1)
            applySettings()
        end)
        button("MUTE  " .. (app.settings.muted and "ON" or "OFF") .. "  [M]", 250, 275, 744, 48, function()
            app.settings.muted = not app.settings.muted
            applySettings()
        end, true, palette.paper)
        button("REDUCED MOTION  " .. (app.settings.reduced and "ON" or "OFF") .. "  [F6]", 250, 345, 744, 48, function()
            app.settings.reduced = not app.settings.reduced
            applySettings()
        end, true, palette.mint)
        button("VISUAL EFFECTS  " .. (app.settings.effects and "ON" or "OFF") .. "  [F7]", 250, 415, 744, 48, function()
            app.settings.effects = not app.settings.effects
            applySettings()
        end, true, palette.pink)
        if app.screen == "play" then
            button("HOW TO PLAY", 250, 488, 350, 40, function()
                app.overlay = "help"
            end, true, palette.paper)
            button("RETURN TO TITLE", 620, 488, 374, 40, function()
                app.screen = "title"
                app.overlay = nil
                audio:setPlaying(false)
            end, true, palette.purple)
        end
    end
    button("BACK  [ESC]", 440, 610, 400, 48, function()
        app.overlay = nil
    end, true)
end

function love.load(args)
    g.setDefaultFilter("nearest", "nearest")
    scene, vfx, audio = Scene.new(), VFX.new(), Audio.new()
    canvas = g.newCanvas(W, H)
    local ok, shader = pcall(
        g.newShader,
        [[
        extern number time;
        vec4 effect(vec4 tint, Image image, vec2 uv, vec2 pixel) {
            float edge = pow(abs(uv.x - 0.5) * 2.0, 6.0);
            uv.x += sin(uv.y * 70.0 + time * 0.5) * 0.001 * edge;
            vec4 c = Texel(image, uv);
            float shift = 0.0012 * edge;
            c.r = Texel(image, uv + vec2(shift,0.0)).r;
            c.b = Texel(image, uv - vec2(shift,0.0)).b;
            c.rgb *= 0.965 + 0.035 * cos(uv.y * 720.0 * 3.14159265);
            vec2 v = uv * (1.0-uv);
            c.rgb *= 0.72 + 0.28 * pow(16.0*v.x*v.y,0.22);
            return c * tint;
        }
    ]]
    )
    crt = ok and shader or nil
    applySettings()
    audio:setPlaying(false)
    for _, arg in ipairs(args or {}) do
        if arg == "--smoke-test" then
            app.smoke = true
            startRun(271828)
        end
    end
end

function love.update(dt)
    dt = math.min(dt, 0.1)
    motion:update(dt, app.settings.reduced)
    if not app.overlay and not app.settings.reduced then
        app.time = app.time + dt
    end
    if app.overlay then
        return
    end
    vfx:update(dt)
    audio:update(dt)
    if app.screen == "play" then
        if app.intro then
            app.intro = app.intro + dt
            if app.intro >= 7 then app.intro = nil end
        else
            updateEvents(dt)
        end
        if app.devour then app.devour = math.min(6, app.devour + dt) end
        
    end
    if app.smoke then
        app.smokeTime = (app.smokeTime or 0) + dt
        if not busy() and app.state.phase == "ask" then
            local lesson = Game.lesson(app.state)
            act(Game.ask, lesson and lesson.rank or Game.legalRanks(app.state)[1])
        elseif not busy() and app.state.phase == "choice" then
            local lesson = Game.lesson(app.state)
            act(lesson and lesson.action == "push" and Game.push or Game.bank)
        elseif not busy() and app.state.phase == "won" then
            local options = Game.rewardOptions(app.state)
            if options then act(Game.chooseReward, options[1]) else advance() end
        elseif not busy() and (app.state.phase == "lost" or app.state.phase == "eaten") then
            print("LIL_FISH_SMOKE_OK phase=" .. app.state.phase)
            love.event.quit(0)
        end
        if app.smokeTime > 180 then
            error("Smoke test did not finish")
        end
    end
end

function love.draw()
    app.buttons = {}
    g.clear(0.025, 0.035, 0.05, 1)
    drawWorld()
    local scale, ox, oy = transform()
    g.push("all")
    g.translate(ox, oy)
    g.scale(scale)
    color({ 1, 1, 1 })
    if app.settings.effects and crt then
        crt:send("time", app.time)
        g.setShader(crt)
    end
    g.setBlendMode("alpha", "premultiplied")
    g.draw(canvas)
    g.setBlendMode("alpha")
    g.setShader()
    if app.screen == "title" then
        drawTitle()
    else
        if app.intro then
            button("SKIP  [ENTER]", 1030, 18, 218, 38, function() app.intro = nil end, true, palette.paper)
        elseif not app.devour then
            hud()
        end
        outcome()
    end
    if app.overlay then
        app.buttons = {}
        overlay()
    end
    g.pop()
end

function love.mousepressed(x, y, mouseButton)
    if mouseButton ~= 1 then
        return
    end
    x, y = pointer(x, y)
    for i = #app.buttons, 1, -1 do
        local control = app.buttons[i]
        if
            control.enabled
            and control.screen == app.screen
            and control.overlay == app.overlay
            and inside(control, x, y)
        then
            cancelPress()
            app.pressed = { id = control.id, screen = app.screen, overlay = app.overlay }
            motion:press(control.id)
           
            return
        end
    end
end

function love.mousereleased(x, y, mouseButton)
    if mouseButton ~= 1 or not app.pressed then
        return
    end
    x, y = pointer(x, y)
    local held = app.pressed
    app.pressed = nil
    local activate
    if held.screen == app.screen and held.overlay == app.overlay then
        for _, control in ipairs(app.buttons) do
            if control.id == held.id and control.enabled and inside(control, x, y) then
                activate = control.action
                break
            end
        end
    end
    motion:release(held.id, activate ~= nil)
    
    if activate then
        app.buttons = {}
        activate()
    end
end

function love.focus(focused)
    if not focused then
        cancelPress()
    end
end

function love.keypressed(key)
    cancelPress()
    if key == "o" then
    print("key DETECTED")
    if app.state then
        app.state.encounter = 4
        app.state.playerHP = 6
        app.state.phase = "playing"
        local events = Game.debugStartFinal(app.state)
        app.queue = {}
        app.active = nil
        app.log = {}
        app.intro = nil
        app.devour = nil
        app.rewardSelection = 1
        app.dialogue = Scene.opponents[4].intro
        app.message = "Developer shortcut: final squid."
        vfx = VFX.new()
        applySettings()
        enqueue(events)
        legalSelection()
    end
    return
end
    if key == "m" then
        app.settings.muted = not app.settings.muted
        applySettings()
        return
    end
    if key == "f6" then
        app.settings.reduced = not app.settings.reduced
        applySettings()
        return
    end
    if key == "f7" then
        app.settings.effects = not app.settings.effects
        applySettings()
        return
    end
    if key == "f5" then
        scene:reload()
        audio:reload()
        vfx = VFX.new()
        applySettings()
        return
    end
    if key == "escape" then
        if app.overlay then
            app.overlay = nil
        else
            app.overlay = "settings"
        end
        return
    end
    if app.overlay then
        return
    end
    if app.screen == "play" and app.intro then
        if key == "return" or key == "space" then app.intro = nil end
        return
    end
    if key == "return" or key == "space" then
        local shortcut = key == "return" and "[ENTER]" or "[SPACE]"
        for _, control in ipairs(app.buttons) do
            if control.enabled and control.label and control.label:find(shortcut, 1, true) then
                tap(control.id)
                break
            end
        end
    end
    if app.screen == "title" then
        if key == "return" then
            startRun()
        end
        return
    end
    if busy() then
        return
    end
    local state = app.state
    local options = Game.rewardOptions(state)
    if options then
        if key == "1" or key == "left" then
            app.rewardSelection = 1
        elseif key == "2" or key == "right" then
            app.rewardSelection = 2
        elseif key == "return" then
            act(Game.chooseReward, options[app.rewardSelection])
        end
        return
    end
    if key == "p" then
        act(Game.peek)
        return
    end
    if key == "return" then
        if state.phase == "ask" then
            act(Game.ask, app.selected)
        elseif state.phase == "choice" then
            act(Game.push)
        elseif state.phase == "won" then
            advance()
        elseif state.phase == "lost" or state.phase == "eaten" then
            retryEncounter()
        end
    elseif key == "space" and state.phase == "choice" then
        act(Game.bank)
    elseif tonumber(key) and tonumber(key) >= 1 and tonumber(key) <= 8 and state.phase == "ask" then
        local rank = tonumber(key)
        for _, legal in ipairs(Game.legalRanks(state)) do
            if legal == rank then
                app.selected = rank
                tap("card:" .. rank)
            end
        end
    end
end
