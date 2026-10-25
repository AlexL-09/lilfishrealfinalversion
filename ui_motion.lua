local Motion = {}
Motion.__index = Motion

local function position(state)
    state.y = state.press * 5 - state.hover * 2 - state.selected * 6
end

local function settle(state)
    state.press = state.held and 1 or 0
    state.hover, state.selected = state.hoverTarget, state.selectedTarget
    state.pressVelocity, state.hoverVelocity, state.selectedVelocity = 0, 0, 0
    position(state)
end

local function stateFor(self, id)
    local state = self.states[id]
    if not state then
        if self.count >= 64 then
            local oldestId, oldestTime
            for key, candidate in pairs(self.states) do
                if not oldestTime or candidate.lastSeen < oldestTime then
                    oldestId, oldestTime = key, candidate.lastSeen
                end
            end
            self.states[oldestId] = nil
            self.count = self.count - 1
        end
        state = {
            y = 0,
            press = 0,
            hover = 0,
            selected = 0,
            flash = 0,
            pressVelocity = 0,
            hoverVelocity = 0,
            selectedVelocity = 0,
            hoverTarget = 0,
            selectedTarget = 0,
            held = false,
        }
        self.states[id] = state
        self.count = self.count + 1
    end
    state.lastSeen = self.time
    return state
end

function Motion.new()
    return setmetatable({ states = {}, count = 0, time = 0, reducedMotion = false }, Motion)
end

function Motion:sample(id, hovered, selected)
    local state = stateFor(self, id)
    state.hoverTarget = hovered and 1 or 0
    state.selectedTarget = selected and 1 or 0
    if self.reducedMotion then
        settle(state)
    end
    return state
end

function Motion:press(id)
    local state = stateFor(self, id)
    state.held, state.press, state.pressVelocity = true, 1, 0
    state.flash = 0
    position(state)
end

function Motion:release(id, activated)
    local state = stateFor(self, id)
    state.held = false
    if activated then
        state.flash = 1
    end
    if self.reducedMotion then
        settle(state)
    end
end

local function spring(value, velocity, target, stiffness, damping, dt, minimum, maximum)
    velocity = velocity + ((target - value) * stiffness - velocity * damping) * dt
    value = value + velocity * dt
    if value < minimum then
        return minimum, 0
    end
    if value > maximum then
        return maximum, 0
    end
    if math.abs(value - target) < 0.0001 and math.abs(velocity) < 0.001 then
        return target, 0
    end
    return value, velocity
end

function Motion:update(dt, reducedMotion)
    dt = math.max(0, math.min(dt, 0.1))
    self.time = self.time + dt
    self.reducedMotion = not not reducedMotion
    local steps = math.max(1, math.ceil(dt * 240))
    local step = dt / steps
    for id, state in pairs(self.states) do
        if self.time - state.lastSeen > 1 then
            self.states[id] = nil
            self.count = self.count - 1
        else
            state.flash = math.max(0, state.flash - dt * 6)
            if self.reducedMotion then
                settle(state)
            else
                for _ = 1, steps do
                    if state.held then
                        state.press, state.pressVelocity = 1, 0
                    else
                        state.press, state.pressVelocity =
                            spring(state.press, state.pressVelocity, 0, 520, 30, step, -0.08, 1)
                    end
                    state.hover, state.hoverVelocity =
                        spring(state.hover, state.hoverVelocity, state.hoverTarget, 400, 40, step, 0, 1)
                    state.selected, state.selectedVelocity =
                        spring(state.selected, state.selectedVelocity, state.selectedTarget, 400, 40, step, 0, 1)
                end
                position(state)
            end
        end
    end
end

function Motion:clear()
    self.states, self.count = {}, 0
end

function Motion.selfTest()
    local motion = Motion.new()
    local state = motion:sample("card:1", false, false)
    motion:press("card:1")
    assert(state.press == 1 and state.y == 5, "press must be visible before update")
    motion:release("card:1", true)
    assert(state.flash == 1 and not state.held)
    local rebounded = false
    for _ = 1, 120 do
        motion:sample("card:1", false, false)
        motion:update(1 / 120, false)
        assert(state.y == state.y and math.abs(state.y) < 12)
        assert(state.press >= -0.08 and state.press <= 1)
        if state.press < 0 then
            rebounded = true
        end
    end
    assert(rebounded and math.abs(state.y) < 0.001 and state.flash == 0)
    motion:update(0, true)
    state = motion:sample("card:1", true, true)
    assert(state.y == -8 and state.hover == 1 and state.selected == 1)
    motion:press("card:1")
    assert(state.y == -3 and state.press == 1)
    motion:release("card:1", false)
    assert(state.y == -8 and state.press == 0)
    motion:sample("card:1", false, false)
    assert(state.y == 0)
    for i = 1, 200 do
        motion:sample("button:" .. i, false, false)
    end
    assert(motion.count == 64, "control state pool must be bounded")
    for _ = 1, 12 do
        motion:update(0.1, false)
    end
    assert(motion.count == 0, "unused controls must expire")
    motion:press("button:restart")
    motion:clear()
    assert(motion.count == 0 and next(motion.states) == nil)
    local function afterRelease(fps)
        local animation = Motion.new()
        animation:sample("test", true, true)
        animation:press("test")
        animation:release("test", true)
        for _ = 1, math.floor(fps / 5) do
            animation:sample("test", true, true)
            animation:update(1 / fps, false)
        end
        return animation:sample("test", true, true).y
    end
    assert(math.abs(afterRelease(30) - afterRelease(60)) < 0.001)
    assert(math.abs(afterRelease(60) - afterRelease(120)) < 0.001)
    return true
end

return Motion
