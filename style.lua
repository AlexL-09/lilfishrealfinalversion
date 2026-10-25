local Style = {}
local g = love.graphics
Style.colors = {
    ink = { 0.035, 0.045, 0.065 },
    deep = { 0.10, 0.15, 0.16 },
    edge = { 0.31, 0.39, 0.39 },
    paper = { 0.98, 0.96, 0.88 },
    muted = { 0.72, 0.80, 0.77 },
    teal = { 0.19, 0.68, 0.63 },
    pink = { 0.96, 0.43, 0.37 },
    mint = { 0.68, 0.85, 0.69 },
    purple = { 0.63, 0.52, 0.71 },
    gold = { 0.88, 0.66, 0.37 },
}
local sizes = { [12] = 24, [14] = 24, [16] = 32, [20] = 40, [28] = 48, [40] = 64, [64] = 112 }
local fonts = {}

function Style.font(size)
    local pixels = sizes[size] or math.max(24, math.floor((size + 4) / 8) * 8)
    if not fonts[pixels] then
        local ok, face = pcall(g.newFont, "assets/fonts/PixelPurl.ttf", pixels, "mono", 1)
        if not ok then
            face = g.newFont(pixels, "mono", 1)
        end
        if face.setFilter then
            face:setFilter("nearest", "nearest")
        end
        if face.setLineHeight then
            face:setLineHeight(1)
        end
        fonts[pixels] = face
    end
    return fonts[pixels], pixels
end

function Style.text(value, x, y, size, c, width, align, shadow)
    local face, pixels = Style.font(size or 16)
    g.setFont(face)
    value = tostring(value)
        :gsub("×", "x")
        :gsub("—", "-")
        :gsub("–", "-")
        :gsub("−", "-")
        :gsub("·", "/")
        :gsub("Ö", "O")
        :gsub("’", "'")
    local function draw(dx, dy)
        if width then
            g.printf(value, math.floor(x + dx), math.floor(y + dy), width, align or "left")
        else
            g.print(value, math.floor(x + dx), math.floor(y + dy))
        end
    end
    if shadow == true or (shadow ~= false and pixels >= 48) then
        g.setColor(0.025, 0.035, 0.06, 0.65)
        draw(1, 1)
    end
    c = c or Style.colors.paper
    g.setColor(c[1], c[2], c[3], c[4] or 1)
    draw(0, 0)
end

function Style.panel(x, y, w, h, fill, border, pressed)
    fill, border = fill or Style.colors.deep, border or Style.colors.edge
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    g.setColor(0.025, 0.035, 0.045, 0.8)
    g.rectangle("fill", x + 2, y + math.max(2, 7 - math.max(0, pressed or 0) * 5), w, h, 8, 8)
    g.setColor(border)
    g.rectangle("fill", x, y, w, h, 8, 8)
    g.setColor(fill)
    g.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 6, 6)
    g.setColor(1, 1, 1, 0.09)
    g.rectangle("fill", x + 7, y + 2, w - 14, 2)
end

local suits = {
    { "0110110", "1111111", "1111111", "0111110", "0011100", "0001000" },
    { "0001000", "0011100", "0111110", "1111111", "1111111", "0101010", "0011100" },
    { "0001000", "0011100", "0111110", "1111111", "0111110", "0011100", "0001000" },
    { "0011100", "0011100", "1101011", "1111111", "1101011", "0001000", "0011100" },
}

function Style.pip(suit, x, y, scale, c)
    g.setColor(c)
    for row, line in ipairs(suits[suit]) do
        for col = 1, #line do
            if line:sub(col, col) == "1" then
                g.rectangle("fill", math.floor(x + (col - 1) * scale), math.floor(y + (row - 1) * scale), scale, scale)
            end
        end
    end
end

function Style.cardBack(x, y, w, h)
    g.push("all")
    g.translate(x, y)
    g.scale(w / 100, h / 144)
    Style.panel(0, 0, 100, 144, Style.colors.paper, Style.colors.ink)
    g.setColor(0.12, 0.29, 0.31)
    g.rectangle("fill", 6, 6, 88, 132, 5, 5)
    g.setColor(0.37, 0.55, 0.53)
    for row = 0, 7 do
        for col = 0, 4 do
            local dx, dy = 14 + col * 18 + (row % 2) * 8, 12 + row * 16
            if dx < 89 then
                g.polygon("line", dx, dy, dx + 5, dy + 6, dx, dy + 12, dx - 5, dy + 6)
            end
        end
    end
    g.setColor(Style.colors.paper)
    g.polygon("fill", 50, 36, 80, 72, 50, 108, 20, 72)
    g.setColor(0.12, 0.29, 0.31)
    g.polygon("fill", 32, 72, 41, 63, 61, 63, 70, 72, 61, 81, 41, 81)
    g.polygon("fill", 33, 72, 25, 64, 25, 80)
    g.setColor(Style.colors.paper)
    g.rectangle("fill", 60, 68, 3, 3)
    g.pop()
end

return Style
