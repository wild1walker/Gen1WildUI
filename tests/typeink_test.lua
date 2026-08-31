-- The type colour on a move button, and what a themed box does to it.
--
-- The bug, from a phone screenshot of a DARK battle: TACKLE, RAZOR LEAF,
-- LEECH SEED and VINE WHIP all printed in the same light grey.  Three of
-- those are GRASS and should be green.
--
-- The cause is not the ink.  A type ink is a real RGB colour drawn onto the
-- canvas by a tint shader, and it survived for as long as it did because a
-- classic battle hands the renderer NO ZONE LIST: with nothing to colorize,
-- Renderer:blitCanvas blits the canvas raw and the letters keep their colour.
-- UI THEME = DARK paints a panel over every box a battle draws -- which is
-- how the command grid goes dark at all -- and a panel is a four-shade
-- palette.  The letters are then read as four shades off their RED channel
-- and repainted, so every type lands on whichever grey its red channel picked.
--
-- No palette can carry an arbitrary colour, so the fix leaves the palette:
-- matte the label's rectangle, lift the ink halfway to white so a table
-- written for black-on-white reads on black, and markTrueColor the rectangle
-- so the raw re-blit shows what was drawn.
--
-- Run:  luajit tests/typeink_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

-- ------- the engine, as much of it as this touches

local fills, colour = {}, nil
love = {
  graphics = {
    setColor = function(r, g, b) colour = { r, g, b } end,
    rectangle = function(_, x, y, w, h)
      fills[#fills + 1] = { x = x, y = y, w = w, h = h,
                            colour = { colour[1], colour[2], colour[3] } }
    end,
    print = function() end,
    setFont = function() end,
    getFont = function() return nil end,
    setShader = function() end,
    getShader = function() return nil end,
    newShader = function() return { send = function() end } end,
  },
}

local drawn = {}
package.preload["src.render.Font"] = function()
  return {
    draw = function(text, x, y) drawn[#drawn + 1] = { text, x, y } end,
    drawCode = function() end,
    drawBox = function() end,
    width = function(text) return #tostring(text) * 8 end,
  }
end

local PaletteFX
PaletteFX = {
  mode = "redpp",
  marks = {},
  honorsTrueColor = function() return PaletteFX.mode == "redpp" end,
  markTrueColor = function(x, y, w, h)
    PaletteFX.marks[#PaletteFX.marks + 1] = { x = x, y = y, w = w, h = h }
  end,
}
package.preload["src.render.PaletteFX"] = function() return PaletteFX end

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ------- the mod, as the bundle hands it over

local themeValue = "dark"
local theme = {
  read = function() return themeValue end,
  matte = function()
    if themeValue == "light" then return { 255, 255, 255 } end
    return { 0, 0, 0 }
  end,
}

local hasTheme = true
local mod = {
  options = { get = function() return true end },
  theme = function() return hasTheme and theme or nil end,
}

local C = chunkOf("modules/Gen1BattleUI/chrome.lua")(mod)

local GRASS = C.typeInk("GRASS")
local function reset()
  fills, drawn, PaletteFX.marks = {}, {}, {}
end

-- ---------------------------------------------------------------- the tests

io.write("the ink table is the dark one, written for a white box\n")
do
  ok(GRASS ~= nil, "GRASS has an ink")
  ok(GRASS[2] > GRASS[1] and GRASS[2] > GRASS[3], "and it is green")
  ok(GRASS[1] + GRASS[2] + GRASS[3] < 3 * 160,
    "and dark, which is the whole reason it cannot be used as it is on black")
  eq(C.typeInk("GRASS_TYPE"), GRASS,
    "the id is read with its _TYPE suffix off, because that is what a move "
    .. "definition carries")
  eq(C.typeInk("BUBBLEGUM"), nil, "a type this does not know has no ink")
end

io.write("on a dark box the rectangle is matted, lifted and marked\n")
do
  reset()
  local rect = { x = 16, y = 96, w = 48, h = 8 }
  local ink, mark = C.onDark(GRASS, rect)

  ok(ink ~= nil, "the label is claimed")
  eq(#fills, 1, "and its rectangle is painted once")
  eq(fills[1].x, 16, "where the letters go")
  eq(fills[1].w, 48, "...at their width")
  eq(fills[1].colour[1], 0, "in the theme's matte, which under DARK is black")
  -- Wound up to full strength rather than mixed toward white: mixing takes
  -- the saturation out and every type converges on the same pale wash, which
  -- is what 0.29.3 shipped and what the sage-green LEECH SEED was.
  eq(ink[2], 255, "the brightest channel is wound all the way up")
  ok(ink[2] > ink[1] and ink[2] > ink[3], "and it is still the green one")
  local function ratio(c) return c[1] / c[2], c[3] / c[2] end
  local r0, b0 = ratio(GRASS)
  local r1, b1 = ratio(ink)
  ok(math.abs(r0 - r1) < 0.001 and math.abs(b0 - b1) < 0.001,
    "the channel ratios are untouched, which is what keeps the hue exactly "
    .. "the hue the table chose")
  ok(ink[1] + ink[2] + ink[3] > 3 * 128, "and it reads on black")

  eq(#PaletteFX.marks, 0, "nothing is marked before the letters are down")
  mark()
  eq(#PaletteFX.marks, 1, "and exactly one rectangle after")
  eq(PaletteFX.marks[1].x, 16, "the one that was painted")
  eq(PaletteFX.marks[1].w, 48, "...at the same width")
  eq(PaletteFX.marks[1].h, 8, "...and height")
end

io.write("and nowhere else: LIGHT, no theme, or a mode that drops the mark\n")
do
  reset()
  themeValue = "light"
  eq(C.onDark(GRASS, { x = 0, y = 0, w = 8, h = 8 }), nil,
    "LIGHT keeps the white box and the dark ink it was written for")
  eq(#fills, 0, "and paints nothing")
  themeValue = "dark"

  reset()
  hasTheme = false
  eq(C.onDark(GRASS, { x = 0, y = 0, w = 8, h = 8 }), nil,
    "a build with no theme is untouched")
  hasTheme = true

  reset()
  PaletteFX.mode = "gbc"
  eq(C.onDark(GRASS, { x = 0, y = 0, w = 8, h = 8 }), nil,
    "SGB discards the mark, so a matte there would be a hole in the button")
  eq(#fills, 0, "...and none is painted")
  PaletteFX.mode = "redpp"
end

io.write("a label with no ink is never claimed\n")
do
  reset()
  eq(C.onDark(nil, { x = 0, y = 0, w = 8, h = 8 }), nil, "no ink, no claim")
  eq(C.onDark(false, { x = 0, y = 0, w = 8, h = 8 }), nil,
    "and the option being off reads as false rather than nil")
  eq(C.onDark(GRASS, { x = 0, y = 0, w = 0, h = 8 }), nil,
    "an empty rectangle is not a label")
  eq(#fills, 0, "none of which paints anything")
end

io.write("drawing a move button carries all of it\n")
do
  reset()
  C.drawLabel({ text = "VINE WHIP", ink = GRASS }, 8, 96, 56)
  eq(#drawn, 1, "the label is printed")
  eq(#fills, 1, "on a matte of its own")
  eq(#PaletteFX.marks, 1, "and the rectangle is marked once it is down")
  eq(PaletteFX.marks[1].h, C.ROW, "one row of the tile font tall")

  reset()
  C.drawLabel({ text = "VINE WHIP" }, 8, 96, 56)
  eq(#drawn, 1, "a label with no type still prints")
  eq(#fills, 0, "and claims nothing")
  eq(#PaletteFX.marks, 0, "and marks nothing")
end

io.write(("\ntype ink: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
