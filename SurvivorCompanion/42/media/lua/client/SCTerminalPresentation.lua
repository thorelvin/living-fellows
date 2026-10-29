-- SPDX-License-Identifier: MIT
-- Pure terminal geometry, phosphor palettes and simulated 1993 POST frames.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalPresentation = {}
local P = SC.TerminalPresentation
local function rounded(value) return math.floor(value + 0.5) end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function color(r, g, b, a) return { a or 1, r, g, b } end
local function palette(body, title, dark)
    dark[1] = 1
    return { emma = body, input = color(0.78 + body[2] * 0.20,
        0.78 + body[3] * 0.20, 0.78 + body[4] * 0.20), system = title, title = title,
        border = title, background = dark, alert = color(1, 0.76, 0.33),
        critical = color(1, 0.42, 0.42) }
end
P.THEMES = {
    green = palette(color(0.65, 0.90, 0.55), color(0.78, 0.96, 0.65), color(0.015, 0.035, 0.018, 0.98)),
    sand = palette(color(0.90, 0.82, 0.64), color(0.96, 0.86, 0.66), color(0.045, 0.033, 0.014, 0.98)),
    aqua = palette(color(0.55, 0.90, 0.85), color(0.71, 0.96, 0.92), color(0.010, 0.035, 0.038, 0.98)),
    purple = palette(color(0.82, 0.68, 0.96), color(0.93, 0.81, 1), color(0.032, 0.014, 0.045, 0.98)),
}
P.PALETTE_VERSION = 2
function P.themeFor(seed, brand)
    -- A separate deterministic draw avoids coupling rarity to password locks.
    local draw = (seed * 48271) % 2147483647
    draw = (draw * 48271) % 2147483647
    if draw % 100 == 0 then return "purple" end
    local canonical=SC.TerminalBrands and SC.TerminalBrands.canonical(brand) or brand
    local curated=SC.TerminalBusinessData and SC.TerminalBusinessData.NEW[canonical]
    local paired = curated and curated.theme or SC.TerminalBrands and SC.TerminalBrands.PALETTES
        and SC.TerminalBrands.PALETTES[canonical]
    if paired and P.THEMES[paired] then return paired end
    return ({ "green", "sand", "aqua" })[draw % 3 + 1]
end
function P.colors(theme) return P.THEMES[theme] or P.THEMES.green end

function P.textHeight(viewportHeight, nativeHeight)
    return math.max(nativeHeight or 16, rounded(clamp(viewportHeight * 40 / 1080, 28, 88)))
end

function P.layout(viewport, fontHeight, charWidth, inputHeight)
    local fh, cw = math.max(8, fontHeight), math.max(4, charWidth)
    local unit = fh / 16
    local pad = math.max(8, rounded(16 * unit))
    local width, height = viewport.width, viewport.height
    local skin = P.frameLayout(width, height)
    local screen = skin.screen
    local canvas = math.min(screen.width, rounded(116 * cw + pad * 4))
    local inset = screen.x + math.floor((screen.width - canvas) / 2)
    local left, right = inset + pad, inset + canvas - pad
    local row = fh + math.max(2, rounded(2 * unit))
    local titleY = screen.y + math.floor(pad / 2)
    local titleHeight = titleY + row
    local brandHeight = row * 2
    -- The logo shares the two-line header instead of taking a third block.
    if screen.height < row * 12 then brandHeight = 0 end
    local top = titleY + (brandHeight > 0 and row * 2 or row) + math.floor(pad / 2)
    local entryHeight = math.max(row + math.max(4, rounded(6 * unit)), (inputHeight or fh) + math.floor(pad / 2))
    local entryY = screen.y + screen.height - pad - entryHeight
    local hintY = entryY - row - math.max(2, rounded(4 * unit))
    local bottom = hintY - math.max(4, rounded(8 * unit))
    local side = 0
    local sideMinimum = 22 * cw + pad * 2
    if canvas >= 42 * cw + sideMinimum + pad * 3 then
        side = rounded(math.max(sideMinimum, math.floor(canvas * 0.28)))
    end
    local contentWidth = math.max(cw * 8, right - left - side)
    local logoWidth = math.min(rounded(210 * unit), math.floor(canvas * 0.30))
    local logoRight = right - row - math.floor(pad / 2)
    return { x = viewport.x or 0, y = viewport.y or 0,
        width = width, height = height, pad = pad, row = row, unit = unit,
        left = left, right = right, canvasWidth = canvas,
        titleY = titleY, titleHeight = titleHeight, brandHeight = brandHeight, top = top,
        bottom = math.max(top + row, bottom), side = side, contentWidth = contentWidth,
        columns = math.max(8, math.floor(contentWidth / cw)),
        entryY = entryY, entryHeight = entryHeight, hintY = hintY,
        logo = { x = logoRight - logoWidth,
            y = titleY, width = logoWidth,
            height = brandHeight },
        viewport = viewport, skin = skin, screen = screen }
end

P.SKIN = { width = 1586, height = 992,
    xCuts = { 0, 320, 1260, 1586 }, yCuts = { 0, 420, 780, 992 },
    screenBounds = { 220, 175, 1370, 785 }, glassBounds = { 180, 140, 1408, 820 } }
function P.frameLayout(width, height)
    local source = P.SKIN
    local scale = math.min(width / source.width, height / source.height) * 0.75
    local dx = { 0, rounded(source.xCuts[2] * scale), rounded(width - (source.width - source.xCuts[3]) * scale), width }
    local dy = { 0, rounded(source.yCuts[2] * scale), rounded(height - (source.height - source.yCuts[3]) * scale), height }
    local function project(value, cuts, target)
        local index = value < cuts[2] and 1 or value < cuts[3] and 2 or 3
        return target[index] + (value - cuts[index]) / (cuts[index+1] - cuts[index])
            * (target[index+1] - target[index])
    end
    local function rect(left, top, right, bottom)
        local x, y = project(left, source.xCuts, dx), project(top, source.yCuts, dy)
        return { x = x, y = y, width = project(right, source.xCuts, dx) - x,
            height = project(bottom, source.yCuts, dy) - y }
    end
    local screen, glass = source.screenBounds, source.glassBounds
    local result = { patches = {}, glow = math.max(1, math.min(3, rounded(height / 1080))),
        -- Measured against the generated frame. Keep text away from rounded lips.
        screen = rect(screen[1],screen[2],screen[3],screen[4]),
        glass = rect(glass[1],glass[2],glass[3],glass[4]) }
    for row = 1, 3 do
        for column = 1, 3 do
            -- Never draw the centre cell: the live display stays fully clear.
            if row ~= 2 or column ~= 2 then
                result.patches[#result.patches + 1] = { x = dx[column], y = dy[row],
                    width = dx[column+1] - dx[column], height = dy[row+1] - dy[row],
                    sourceX = source.xCuts[column], sourceY = source.yCuts[row],
                    sourceWidth = source.xCuts[column+1] - source.xCuts[column],
                    sourceHeight = source.yCuts[row+1] - source.yCuts[row] }
            end
        end
    end
    return result
end

function P.fitImage(sourceWidth, sourceHeight, box)
    if sourceWidth <= 0 or sourceHeight <= 0 or box.width <= 0 or box.height <= 0 then return nil end
    local scale = math.min(box.width / sourceWidth, box.height / sourceHeight)
    local width, height = sourceWidth * scale, sourceHeight * scale
    return { x = rounded(box.x + (box.width - width) / 2),
        y = rounded(box.y + (box.height - height) / 2), width = width, height = height }
end

function P.headerLogoBox(layout, brand, cw)
    local original = layout.logo
    if brand ~= "_camp" then return original end
    local right = original.x + original.width
    local available = math.max(0, right - layout.left - layout.pad - cw * 25)
    local width = math.min(300 * layout.unit, layout.canvasWidth * 0.34, available)
    return { x = right - width, y = original.y, width = width, height = original.height }
end

function P.logoStyle(theme, box, unit)
    local colors = P.colors(theme)
    local inset = rounded(6 * unit)
    return { box = { x = box.x + inset, y = box.y + inset,
        width = math.max(0, box.width - inset * 2),
        height = math.max(0, box.height - inset * 2) },
        -- Keep brand hues, with the same gentle tube tint and brightness as text.
        alpha = 0.78, r = 0.84 + colors.title[2] * 0.16,
        g = 0.84 + colors.title[3] * 0.16, b = 0.84 + colors.title[4] * 0.16,
        ink = colors.title, corner = math.max(3, rounded(5 * unit)) }
end

P.BIOS_MS = 1400
P.BOOT_MS = P.BIOS_MS + 3200
function P.biosFrame(elapsed)
    elapsed = tonumber(elapsed) or 0
    if elapsed ~= elapsed or math.abs(elapsed) == math.huge then elapsed = 0 end
    elapsed = math.max(0, elapsed)
    return { reveal = clamp(elapsed / 750, 0, 1),
        progress = clamp(elapsed / P.BIOS_MS, 0, 1), active = elapsed < P.BIOS_MS }
end
function P.bootFrame(elapsed, seed)
    local complete = elapsed >= P.BOOT_MS
    elapsed = math.max(0, elapsed - P.BIOS_MS)
    local ram = ({ 2048, 4096, 8192 })[seed % 3 + 1]
    local lines = { "LARCHFIELD BUSINESS MACHINES", "Personal System / 486", "Firmware 1.07   06/14/93", "" }
    if elapsed >= 250 then
        lines[#lines + 1] = string.format("%05d KB  OK", math.floor(ram * clamp((elapsed - 250) / 1350, 0, 1) / 64) * 64)
    end
    if elapsed >= 1700 then lines[#lines + 1] = "Keyboard ............ OK" end
    if elapsed >= 2000 then lines[#lines + 1] = "Video adapter ....... OK" end
    if elapsed >= 2300 then lines[#lines + 1] = "Fixed disk .......... READY" end
    if elapsed >= 2600 then lines[#lines + 1] = "Loading LARCH/OS 2.4..." end
    if elapsed >= 2900 then lines[#lines + 1] = "Starting local EMMA service..." end
    lines[#lines + 1] = math.floor(elapsed / 350) % 2 == 0 and "_" or " "
    return lines, complete
end
