local VFX = {}
VFX.__index = VFX

local CAPACITY = 160

local function random(self)
    -- Keep presentation randomness out of the rules' random stream.
    self.seed = (self.seed * 16807) % 2147483647
    return self.seed / 2147483647
end

local function loadTexture(path)
    if not (love and love.filesystem and love.graphics) then
        return nil
    end
    if not love.filesystem.getInfo(path, "file") then
        return nil
    end
    local ok, texture = pcall(love.graphics.newImage, path)
    if ok then
        texture:setFilter("nearest", "nearest")
        return texture
    end
end

function VFX.new()
    local self = setmetatable({
        seed = 13859,
        particles = {},
        ambient = {},
        nextSlot = 1,
        effectsEnabled = true,
        reducedMotion = false,
        shakeTime = 0,
        shakeStrength = 0,
        shakeX = 0,
        shakeY = 0,
        hopTime = 0,
        textures = {
            bubble = loadTexture("assets/images/bubble.png"),
            sediment = loadTexture("assets/images/sediment.png"),
        },
    }, VFX)
    for i = 1, CAPACITY do
        self.particles[i] = { life = 0 }
    end
    for i = 1, 35 do
        self.ambient[i] = {
            x = random(self) * 1280,
            y = random(self) * 720,
            kind = i <= 10 and "bubble" or "sediment",
            speed = 4 + random(self) * 12,
            size = i <= 10 and 3 + random(self) * 3 or 1 + random(self),
        }
    end
    return self
end

local function emit(self, kind, count, x, y, force)
    for _ = 1, count do
        local slot
        for _ = 1, CAPACITY do
            local candidate = self.particles[self.nextSlot]
            self.nextSlot = self.nextSlot % CAPACITY + 1
            if candidate.life <= 0 then
                slot = candidate
                break
            end
        end
        if not slot then
            return
        end
        local angle = random(self) * math.pi * 2
        local speed = (25 + random(self) * 85) * force
        slot.kind, slot.x, slot.y = kind, x, y
        slot.vx = math.cos(angle) * speed
        slot.vy = math.sin(angle) * speed * 0.55 - 25
        slot.life = 0.35 + random(self) * 0.45
        slot.maxLife = slot.life
        slot.size = kind == "bubble" and 3 + random(self) * 4 or 1 + random(self) * 2
    end
end

function VFX:setOptions(reducedMotion, effectsEnabled)
    self.reducedMotion = not not reducedMotion
    self.effectsEnabled = not not effectsEnabled
    if self.reducedMotion or not self.effectsEnabled then
        self.shakeTime, self.hopTime = 0, 0
        self.shakeX, self.shakeY = 0, 0
    end
    if not self.effectsEnabled then
        for _, particle in ipairs(self.particles) do
            particle.life = 0
        end
    end
end

function VFX:impact(actor, x, y, strength)
    if not self.effectsEnabled then
        return
    end
    strength = math.max(0, math.min(strength or 1, 1.5))
    if strength == 0 then
        return
    end
    if actor == "predator" then
        emit(self, "sediment", self.reducedMotion and 4 or 16, x, y, strength)
        emit(self, "bubble", self.reducedMotion and 2 or 6, x, y, strength)
        if not self.reducedMotion then
            self.shakeTime, self.hopTime = 0.18, 0.15
            self.shakeStrength = 7 * strength
            self.shakeX = (random(self) * 2 - 1) * self.shakeStrength
            self.shakeY = (random(self) * 2 - 1) * self.shakeStrength * 0.65
        end
    else
        emit(self, "bubble", self.reducedMotion and 2 or 4, x, y, 0.45)
    end
end

function VFX:celebrate(x, y)
    if self.effectsEnabled then
        emit(self, "bubble", self.reducedMotion and 4 or 12, x, y, 0.9)
    end
end

function VFX:update(dt)
    dt = math.max(0, dt)
    if not self.effectsEnabled then
        return
    end
    if not self.reducedMotion then
        for _, particle in ipairs(self.ambient) do
            particle.y = (particle.y - particle.speed * dt) % 720
            particle.x = (particle.x + particle.speed * 0.15 * dt) % 1280
        end
    end
    for _, particle in ipairs(self.particles) do
        if particle.life > 0 then
            particle.life = math.max(0, particle.life - dt)
            particle.x = particle.x + particle.vx * dt
            particle.y = particle.y + particle.vy * dt
            particle.vy = particle.vy - 12 * dt
        end
    end
    self.hopTime = math.max(0, self.hopTime - dt)
    self.shakeTime = math.max(0, self.shakeTime - dt)
    local amplitude = self.shakeStrength * (self.shakeTime / 0.18) ^ 2
    self.shakeX = (random(self) * 2 - 1) * amplitude
    self.shakeY = (random(self) * 2 - 1) * amplitude * 0.65
end

function VFX:offset()
    return self.shakeX, self.shakeY
end

function VFX:hop()
    return math.sin((1 - self.hopTime / 0.15) * math.pi) * 4 * (self.hopTime > 0 and 1 or 0)
end

local function drawParticle(self, particle, alpha)
    local graphics = love.graphics
    if particle.kind == "bubble" then
        graphics.setColor(0.68, 0.89, 0.85, alpha)
    else
        graphics.setColor(0.91, 0.78, 0.62, alpha)
    end
    local texture = self.textures[particle.kind]
    if texture then
        local width, height = texture:getDimensions()
        graphics.draw(
            texture,
            particle.x,
            particle.y,
            0,
            particle.size / width,
            particle.size / height,
            width / 2,
            height / 2
        )
    else
        local x, y = math.floor(particle.x / 2) * 2, math.floor(particle.y / 2) * 2
        if particle.kind == "bubble" then
            local size = math.max(6, math.floor(particle.size) * 2)
            graphics.rectangle("fill", x + 2, y, size - 4, 2)
            graphics.rectangle("fill", x + 2, y + size - 2, size - 4, 2)
            graphics.rectangle("fill", x, y + 2, 2, size - 4)
            graphics.rectangle("fill", x + size - 2, y + 2, 2, size - 4)
            graphics.setColor(0.96, 1, 0.94, alpha)
            graphics.rectangle("fill", x + 2, y + 2, 2, 2)
        else
            graphics.rectangle("fill", x, y, 2, 2)
        end
    end
end

function VFX:drawAmbient()
    if not self.effectsEnabled then
        return
    end
    love.graphics.push("all")
    for _, particle in ipairs(self.ambient) do
        drawParticle(self, particle, particle.kind == "bubble" and 0.55 or 0.20)
    end
    love.graphics.pop()
end

function VFX:drawBursts()
    if not self.effectsEnabled then
        return
    end
    love.graphics.push("all")
    for _, particle in ipairs(self.particles) do
        if particle.life > 0 then
            drawParticle(self, particle, particle.life / particle.maxLife * 0.8)
        end
    end
    love.graphics.pop()
end

function VFX:stats()
    local bursts = 0
    for _, particle in ipairs(self.particles) do
        if particle.life > 0 then
            bursts = bursts + 1
        end
    end
    return { bursts = bursts, ambient = self.effectsEnabled and #self.ambient or 0, capacity = CAPACITY }
end

function VFX.selfTest()
    local effects = VFX.new()
    assert(effects:stats().ambient == 35)
    effects:impact("player", 640, 400)
    assert(effects:stats().bursts == 4)
    local x, y = effects:offset()
    assert(x == 0 and y == 0 and effects:hop() == 0)
    effects:impact("predator", 640, 400)
    assert(effects:stats().bursts == 26)
    effects:update(0.075)
    assert(effects:hop() > 0)
    for _ = 1, 20 do
        effects:impact("predator", 640, 400)
    end
    assert(effects:stats().bursts == CAPACITY)
    effects:update(1)
    assert(effects:stats().bursts == 0 and effects:hop() == 0)
    x, y = effects:offset()
    assert(x == 0 and y == 0)
    effects:setOptions(true, true)
    effects:impact("predator", 640, 400)
    assert(effects:stats().bursts == 6 and effects:hop() == 0)
    x, y = effects:offset()
    assert(x == 0 and y == 0)
    effects:setOptions(false, false)
    effects:impact("predator", 640, 400)
    effects:celebrate(640, 400)
    assert(effects:stats().bursts == 0 and effects:stats().ambient == 0)
    effects:setOptions(false, true)
    effects:celebrate(640, 400)
    assert(effects:stats().bursts == 12 and effects:stats().ambient == 35)
    return true
end

return VFX
