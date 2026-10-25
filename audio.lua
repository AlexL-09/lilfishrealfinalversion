
local Audio = {}
Audio.__index = Audio

local function call(source, method, ...)
    if not source then
        return false
    end
    return pcall(source[method], source, ...)
end

function Audio.new()
    local self = setmetatable({
        volume = 0.7,
        muted = false,
        playing = false,
        mainmusic = nil
    }, Audio)

    local ok, source = pcall(
        love.audio.newSource,
        "assets/audio/mainmusic.mp3",
        "stream"
    )

    if ok then
        self.mainmusic = source
        call(self.mainmusic, "setLooping", true)
        self:applyVolume()
        self:setPlaying(true)
    end

    return self
end

function Audio:applyVolume()
    local volume = self.muted and 0 or self.volume
    call(self.mainmusic, "setVolume", volume * 0.05)
end

function Audio:setPlaying(playing)
    if type(playing) ~= "boolean" then
        return
    end

    self.playing = playing

    if playing then
        call(self.mainmusic, "play")
    else
        call(self.mainmusic, "stop")
    end
end

function Audio:setVolume(volume)
    if type(volume) ~= "number" or volume ~= volume
        or volume == math.huge or volume == -math.huge then
        return
    end

    self.volume = math.max(0, math.min(1, volume))
    self:applyVolume()
end

function Audio:setMuted(muted)
    if type(muted) ~= "boolean" then
        return
    end

    self.muted = muted
    self:applyVolume()
end

function Audio:stop()
    self:setPlaying(false)
end

function Audio:update(dt)
end

function Audio:play(cue)
    -- no sfx because we took too long
    return false
end

return Audio
