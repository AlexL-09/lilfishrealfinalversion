local Game = {}
local bossHP = { 4, 6, 8, 8 }
local phases = { ask = true, choice = true, enemy = true, won = true, lost = true, eaten = true }

Game.rewards = {
    { "bubble_shield", "second_wind" },
    { "keen_eye", "deep_pockets" },
    { "sharp_teeth", "blood_in_the_water" },
}
Game.powers = {
    bubble_shield = { name = "Bubble Shield", short = "SHIELD", icon = "O", text = "Ignore the first bite from a pushed miss each duel." },
    second_wind = { name = "Second Wind", short = "WIND", icon = "+", text = "Your first completed set each duel heals 1 HP, up to 6." },
    keen_eye = { name = "Keen Eye", short = "KEEN EYE", icon = "?", text = "Press P before asking to reveal an opponent rank. Once per duel." },
    deep_pockets = { name = "Deep Pockets", short = "POCKETS", icon = "2", text = "Your first miss each duel draws two cards instead of one." },
    sharp_teeth = { name = "Sharp Teeth", short = "TEETH", icon = "^", text = "Your first completed set each duel deals +1 damage." },
    blood_in_the_water = { name = "Blood in the Water", short = "BLOOD", icon = "!", text = "Your sets deal +1 damage while you have 3 HP or less." },
}

function Game.hasPower(state, id)
    for _, power in ipairs(state.powers) do
        if power == id then return true end
    end
    return false
end

function Game.rewardOptions(state)
    if state.phase == "won" and not state.powers[state.encounter] then
        return Game.rewards[state.encounter]
    end
end

Game.lessons = {
    { action = "ask", rank = 1, text = "Ask for 1s. Four matching cards make a set and deal 2 damage." },
    { action = "push", text = "Nice set! PUSH to ask again. A set on success #2 deals 3 damage." },
    { action = "ask", rank = 2, text = "Ask for 2s. Try a risky guess: a pushed miss costs 1 HP." },
    { action = "ask", rank = 3, text = "Go fish! You drew a card. Now ask for 3s to try again." },
    { action = "bank", text = "BANK ends your turn safely. Watch how I ask for your cards." },
    { action = "ask", rank = 3, text = "Ask for 3s. A normal miss draws safely. Your draw can finish a set!" },
}

function Game.lesson(state)
    return Game.lessons[state.tutorial]
end

local function learn(state, action, rank)
    local lesson = Game.lesson(state)
    if not lesson then
        return true
    end
    if lesson.action ~= action or lesson.rank ~= rank then
        return false, lesson.text
    end
    state.tutorial = state.tutorial + 1
    return true
end

local function emit(events, kind, actor, fields)
    local event = fields or {}
    event.type, event.actor = kind, actor
    events[#events + 1] = event
end

local function activate(state, id, events)
    state.used[id] = true
    emit(events, "power", "player", { power = id })
end

function Game.chooseReward(state, id)
    local options = Game.rewardOptions(state)
    if not options or (id ~= options[1] and id ~= options[2]) then
        return nil, "Choose one of the offered powers after a victory"
    end
    state.powers[state.encounter] = id
    return { { type = "reward", actor = "player", power = id } }
end

local function random(state, limit)
    state.rng = state.rng * 48271 % 2147483647
    return state.rng % limit + 1
end

local function count(hand, rank)
    local total = 0
    for _, card in ipairs(hand) do
        if card == rank then
            total = total + 1
        end
    end
    return total
end

local function removeRank(hand, rank)
    local taken = 0
    for i = #hand, 1, -1 do
        if hand[i] == rank then
            table.remove(hand, i)
            taken = taken + 1
        end
    end
    return taken
end

local function damage(state, actor, amount, source, events)
    local key = actor == "player" and "playerHP" or "enemyHP"
    state[key] = math.max(0, state[key] - amount)
    emit(events, "damage", actor, { amount = amount, source = source })
    if state[key] == 0 then
        if state.encounter == #bossHP then
            if actor == "enemy" then
                state.enemyHP = bossHP[state.encounter]
                emit(events, "betrayal", "enemy")
                local health = state.playerHP
                state.playerHP = 0
                emit(events, "damage", "player", { amount = health, source = "devour" })
            end
            state.phase, state.peeked = "eaten", nil
            emit(events, "devour", "enemy")
            return false
        end
        state.phase = actor == "player" and "lost" or "won"
        emit(events, actor == "player" and "defeat" or "victory", "player")
        return false
    end
    return true
end

local function collect(state, actor, amount, events)
    for rank = 1, 8 do
        if count(state[actor], rank) == 4 then
            local setDamage = amount
            if actor == "player" then
                if Game.hasPower(state, "sharp_teeth") and not state.used.sharp_teeth then
                    setDamage = setDamage + 1
                    activate(state, "sharp_teeth", events)
                end
                if Game.hasPower(state, "blood_in_the_water") and state.playerHP <= 3 then
                    setDamage = setDamage + 1
                    emit(events, "power", "player", { power = "blood_in_the_water" })
                end
            end
            removeRank(state[actor], rank)
            state.books[#state.books + 1] = { actor = actor, rank = rank }
            if actor == "player" then
                state.knowledge[rank] = nil
            end
            emit(events, "set", actor, { rank = rank, count = 4, amount = setDamage })
            if actor == "player" and Game.hasPower(state, "second_wind") and not state.used.second_wind then
                activate(state, "second_wind", events)
                local healed = math.min(1, 6 - state.playerHP)
                state.playerHP = state.playerHP + healed
                emit(events, "heal", "player", { amount = healed })
            end
            if not damage(state, actor == "player" and "enemy" or "player", setDamage, actor, events) then
                return false
            end
        end
    end
    if #state.player == 0 then
        state.knowledge = {}
    end
    return true
end

local function draw(state, actor, number, events)
    for _ = 1, math.min(number, #state.deck) do
        local rank = table.remove(state.deck)
        state[actor][#state[actor] + 1] = rank
        emit(events, "draw", actor, { rank = rank, count = 1 })
        if not collect(state, actor, 2, events) then return false end
    end
    return true
end

local function turn(state, actor, events)
    state.streak, state.pushed = 0, false
    if #state[actor] == 0 then
        if not draw(state, actor, 3, events) then
            return
        end
        if #state[actor] == 0 then
            actor = actor == "player" and "enemy" or "player"
            assert(#state[actor] > 0, "A living duel must have cards remaining")
        end
    end
    state.phase = actor == "player" and "ask" or "enemy"
    emit(events, "turn", actor)
end

local function setup(state)
    state.deck, state.player, state.enemy, state.books = {}, {}, {}, {}
    state.knowledge, state.streak, state.pushed = {}, 0, false
    state.used, state.peeked = {}, nil
    state.enemyHP = bossHP[state.encounter]
    state.phase = "ask"
    if state.encounter == 1 then
        state.tutorial = 1
        state.player = { 1, 1, 1, 2, 2, 3, 3 }
        state.enemy = { 1, 3, 4, 4, 5, 5, 6 }
        for rank = 2, 8 do
            for _ = 1, 4 - count(state.player, rank) - count(state.enemy, rank) do
                state.deck[#state.deck + 1] = rank
            end
        end
        -- Put both remaining 2s on top: the pupil draws one, then the trainer draws one.
        table.sort(state.deck, function(a, b) return a > b end)
        return { { type = "turn", actor = "player" } }
    end
    state.tutorial = nil
    for rank = 1, 8 do
        for _ = 1, 4 do
            state.deck[#state.deck + 1] = rank
        end
    end
    for i = #state.deck, 2, -1 do
        local j = random(state, i)
        state.deck[i], state.deck[j] = state.deck[j], state.deck[i]
    end
    for _ = 1, 7 do
        state.player[#state.player + 1] = table.remove(state.deck)
        state.enemy[#state.enemy + 1] = table.remove(state.deck)
    end
    local events = {}
    if collect(state, "player", 2, events) and collect(state, "enemy", 2, events) then
        turn(state, "player", events)
    end
    return events
end

function Game.new(seed)
    seed = seed or 1
    assert(type(seed) == "number" and seed == seed and math.abs(seed) < math.huge, "Seed must be a finite number")
    seed = math.floor(seed) % 2147483646 + 1
    local state = { seed = seed, rng = seed, encounter = 1, playerHP = 6, powers = {} }
    state.openingEvents = setup(state)
    return state
end

function Game.legalRanks(state)
    local ranks = {}
    for rank = 1, 8 do
        if count(state.player, rank) > 0 then
            ranks[#ranks + 1] = rank
        end
    end
    return ranks
end

function Game.peek(state)
    if state.phase ~= "ask" or not Game.hasPower(state, "keen_eye") or state.used.keen_eye or #state.enemy == 0 then
        return nil, "Keen Eye reveals a rank once per duel, before asking"
    end
    local events = {}
    state.peeked = state.enemy[random(state, #state.enemy)]
    activate(state, "keen_eye", events)
    emit(events, "peek", "player", { rank = state.peeked })
    return events
end

function Game.ask(state, rank)
    if state.phase ~= "ask" then
        return nil, "You cannot ask right now"
    end
    if type(rank) ~= "number" or rank % 1 ~= 0 or rank < 1 or rank > 8 or count(state.player, rank) == 0 then
        return nil, "Ask for a rank in your hand"
    end
    local allowed, err = learn(state, "ask", rank)
    if not allowed then
        return nil, err
    end
    state.peeked = nil
    local events = {}
    state.knowledge[rank] = true
    emit(events, "request", "player", { rank = rank })
    local taken = removeRank(state.enemy, rank)
    if taken > 0 then
        for _ = 1, taken do
            state.player[#state.player + 1] = rank
        end
        emit(events, "transfer", "player", { rank = rank, count = taken })
        state.streak = state.streak + 1
        if not collect(state, "player", state.streak >= 2 and 3 or 2, events) then
            return events
        end
        if #state.player == 0 then
            turn(state, "enemy", events)
        else
            state.phase = "choice"
        end
    else
        if state.pushed then
            if Game.hasPower(state, "bubble_shield") and not state.used.bubble_shield then
                activate(state, "bubble_shield", events)
            elseif not damage(state, "player", 1, "bite", events) then
                return events
            end
        end
        local number = 1
        if Game.hasPower(state, "deep_pockets") and not state.used.deep_pockets then
            activate(state, "deep_pockets", events)
            number = 2
        end
        if draw(state, "player", number, events) then
            turn(state, "enemy", events)
        end
    end
    return events
end

function Game.push(state)
    if state.phase ~= "choice" then
        return nil, "Push only after a successful request"
    end
    local allowed, err = learn(state, "push")
    if not allowed then
        return nil, err
    end
    state.phase, state.pushed = "ask", true
    return {}
end

function Game.bank(state)
    if state.phase ~= "choice" then
        return nil, "Bank only after a successful request"
    end
    local allowed, err = learn(state, "bank")
    if not allowed then
        return nil, err
    end
    local events = {}
    turn(state, "enemy", events)
    return events
end

function Game.enemyTurn(state)
    if state.phase ~= "enemy" then
        return nil, "It is not the predator's turn"
    end
    local candidates, bestKnown, bestCount = {}, -1, -1
    for rank = 1, 8 do
        local number = count(state.enemy, rank)
        if number > 0 then
            local known = state.knowledge[rank] and 1 or 0
            if known > bestKnown or (known == bestKnown and number > bestCount) then
                candidates, bestKnown, bestCount = { rank }, known, number
            elseif known == bestKnown and number == bestCount then
                candidates[#candidates + 1] = rank
            end
        end
    end
    assert(#candidates > 0, "Enemy turn requires a nonempty hand")
    local rank = candidates[random(state, #candidates)]
    local events = {}
    emit(events, "request", "enemy", { rank = rank })
    local taken = removeRank(state.player, rank)
    state.knowledge[rank] = nil
    if #state.player == 0 then
        state.knowledge = {}
    end
    if taken > 0 then
        for _ = 1, taken do
            state.enemy[#state.enemy + 1] = rank
        end
        emit(events, "transfer", "enemy", { rank = rank, count = taken })
        if not collect(state, "enemy", 2, events) then
            return events
        end
    elseif not draw(state, "enemy", 1, events) then
        return events
    end
    turn(state, "player", events)
    return events
end

function Game.nextEncounter(state)
    if state.phase ~= "won" then
        return nil, "Win the current duel first"
    end
    if Game.rewardOptions(state) then
        return nil, "Choose a power before the next duel"
    end
    if state.encounter == #bossHP then
        return nil, "The house never lets its final contestant leave"
    end
    state.playerHP = state.encounter == 1 and 6 or math.min(6, state.playerHP + 2)
    state.encounter = state.encounter + 1
    return setup(state)
end

function Game.retryEncounter(state)
    if state.phase ~= "lost" and state.phase ~= "eaten" then
        return nil, "Finish the current duel before retrying"
    end
    state.playerHP = 6
    return setup(state)
end

function Game.debugStartFinal(state)
    state.encounter = #bossHP
    state.playerHP = 6
    return setup(state)
end

function Game.assertValid(state)
    assert(phases[state.phase], "Invalid phase")
    assert(state.encounter >= 1 and state.encounter <= #bossHP, "Invalid encounter")
    assert(state.playerHP >= 0 and state.playerHP <= 6, "Invalid player health")
    assert(state.enemyHP >= 0 and state.enemyHP <= bossHP[state.encounter], "Invalid enemy health")
    assert(state.streak >= 0 and state.streak % 1 == 0, "Invalid streak")
    for tier, id in pairs(state.powers) do
        local options = Game.rewards[tier]
        assert(options and (id == options[1] or id == options[2]), "Invalid reward")
        assert(tier <= state.encounter and (tier == 1 or state.powers[tier - 1]), "Rewards must be earned in order")
    end
    for id in pairs(state.used) do
        assert(Game.hasPower(state, id), "Unowned power was used")
    end
    local totals = {}
    for rank = 1, 8 do
        totals[rank] = 0
    end
    for _, key in ipairs({ "deck", "player", "enemy" }) do
        for _, rank in ipairs(state[key]) do
            assert(type(rank) == "number" and rank % 1 == 0 and rank >= 1 and rank <= 8, "Invalid card")
            totals[rank] = totals[rank] + 1
        end
    end
    local booked = {}
    for _, book in ipairs(state.books) do
        assert(book.actor == "player" or book.actor == "enemy", "Invalid set owner")
        assert(totals[book.rank] and not booked[book.rank], "Invalid or duplicate set")
        booked[book.rank] = true
        totals[book.rank] = totals[book.rank] + 4
    end
    for rank = 1, 8 do
        assert(totals[rank] == 4, "Card conservation failed for rank " .. rank)
        assert(count(state.player, rank) < 4 and count(state.enemy, rank) < 4, "Uncollected set")
        if state.knowledge[rank] then
            assert(count(state.player, rank) > 0, "Stale predator knowledge")
        end
    end
    if state.phase == "eaten" then
        assert(state.encounter == #bossHP and state.playerHP == 0 and state.enemyHP > 0, "The squid consumes the final contestant")
    elseif state.phase == "lost" then
        assert(state.playerHP == 0, "Defeat requires zero player health")
        assert(state.encounter < #bossHP, "Final defeats must reach the eating scene")
    elseif state.phase == "won" then
        assert(state.encounter < #bossHP, "The final boss cannot be beaten")
        assert(state.enemyHP == 0 and state.playerHP > 0, "Victory requires a defeated predator")
    else
        assert(state.playerHP > 0 and state.enemyHP > 0, "Living duel requires positive health")
        assert(#state[state.phase == "enemy" and "enemy" or "player"] > 0, "Active hand is empty")
    end
    return true
end

return Game
