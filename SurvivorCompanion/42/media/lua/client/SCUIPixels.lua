-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.UIPixels = SC.UIPixels or {}
local Pixels = SC.UIPixels

-- Every symbol is an original, deterministic bitmap drawn with ISUI rectangles.
Pixels.bitmaps = {
    companion = {
        "..###..",
        ".#####.",
        "..###..",
        ".#####.",
        "#######",
        "##.#.##",
        ".##.##.",
        ".##.##.",
    },
    heart = {
        ".##.##.",
        "#######",
        "#######",
        ".#####.",
        "..###..",
        "...#...",
    },
    chevronLeft = {
        "...#.",
        "..##.",
        ".###.",
        "..##.",
        "...#.",
    },
    chevronRight = {
        ".#...",
        ".##..",
        ".###.",
        ".##..",
        ".#...",
    },
    grip = {
        "#.#.#",
        ".....",
        "#.#.#",
        ".....",
        "#.#.#",
    },
}

function Pixels.measure(name, scale)
    local bitmap = Pixels.bitmaps[name]
    if not bitmap then
        return 0, 0
    end
    local pixelScale = math.max(1, math.floor(tonumber(scale) or 1))
    return string.len(bitmap[1]) * pixelScale, #bitmap * pixelScale
end

function Pixels.draw(element, name, x, y, scale, red, green, blue, alpha)
    local bitmap = Pixels.bitmaps[name]
    if not element or not bitmap then
        return
    end
    local pixelScale = math.max(1, math.floor(tonumber(scale) or 1))
    local r = tonumber(red) or 1
    local g = tonumber(green) or 1
    local b = tonumber(blue) or 1
    local a = tonumber(alpha) or 1
    for row = 1, #bitmap do
        local line = bitmap[row]
        for column = 1, string.len(line) do
            if string.sub(line, column, column) == "#" then
                element:drawRect(
                    x + ((column - 1) * pixelScale),
                    y + ((row - 1) * pixelScale),
                    pixelScale,
                    pixelScale,
                    a,
                    r,
                    g,
                    b
                )
            end
        end
    end
end

return Pixels
