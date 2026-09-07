-- The YES/NO box on Gold (runtime/choicebox2.lua).
--
-- The engine is not here, so nothing about how the box LOOKS can be tested.
-- What can be, and is the whole of what this file does, is WHICH CALLS it
-- makes: the box, the two labels and the cursor have to go through the three
-- palette-aware Chrome helpers rather than through Font, and they have to go
-- through them at the same coordinates the engine's own draw uses. Get the
-- second half wrong and the box is themed and in the wrong place, which is
-- worse than the white box it replaced.
--
-- The palette matters as much as the calls. It has to be the LIVE
-- `Chrome.DEFAULT_BOX_PALETTE` -- the table runtime/theme2.lua rewrites in
-- place -- and not a copy, because a copy is a snapshot of whatever the theme
-- said on the frame it was taken. So the test rewrites that table between two
-- paints and asks the second one what it saw.
--
-- Run:  luajit tests/choicebox2_test.lua

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
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ---------------------------------------------------------------- harness

-- love.graphics, reduced to the one call the paint makes on its own.
local colors = {}
_G.love = _G.love or {}
_G.love.graphics = {
  setColor = function(r, g, b, a) colors[#colors + 1] = { r, g, b, a } end,
}

-- Gold's Chrome, recording rather than drawing.  The three helpers are the
-- ones `Chrome.paletteBox`/`printThrough`/`cursorThrough` really are: box,
-- string and cursor, each taking tile coordinates and a palette.
local Chrome, calls
local function freshChrome()
  calls = {}
  Chrome = {
    DEFAULT_BOX_PALETTE = {
      { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
    },
    paletteBox = function(tx, ty, tw, th, palette)
      calls[#calls + 1] = { what = "box", tx = tx, ty = ty, tw = tw, th = th,
                            palette = palette }
    end,
    printThrough = function(text, tx, ty, palette)
      calls[#calls + 1] = { what = "print", text = text, tx = tx, ty = ty,
                            palette = palette }
    end,
    cursorThrough = function(tx, ty, palette)
      calls[#calls + 1] = { what = "cursor", tx = tx, ty = ty,
                            palette = palette }
    end,
  }
  package.loaded["src.ui.gen2.Chrome"] = Chrome
  return Chrome
end

-- Strings is a callable table on the engine; only the call is used here.
package.loaded["src.core.Strings"] = setmetatable({}, {
  __call = function(_, text) return text end,
})

local hidden = false
package.loaded["src.battle.UIVisibility"] = {
  bottomVisible = function() return not hidden end,
}

-- The engine's own ChoiceBox, cut to the fields the paint reads plus a draw
-- to be replaced.  `drew` counts the times the ENGINE's draw ran, which is
-- how the fallback is checked.
local ChoiceBox, drew
local function freshChoiceBox()
  drew = 0
  ChoiceBox = { draw = function() drew = drew + 1 end }
  package.loaded["src.ui.ChoiceBox"] = ChoiceBox
  return ChoiceBox
end

local ChoiceBox2 = chunkOf("runtime/choicebox2.lua")

local logged
local function context()
  logged = {}
  local mod = { log = {} }
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    mod.log[level] = function(_, format, ...)
      logged[#logged + 1] = { level = level,
        text = select("#", ...) > 0 and format:format(...) or format }
    end
  end
  return { mod = mod }
end

-- Gold's default YES/NO geometry, as `src/ui/Theme.lua` gives it: a small box
-- with the two rows two apart and the cursor a tile to their left.
local function boxInstance(overrides)
  local self = {
    game = {},
    tx = 14, ty = 7, tw = 6, th = 5,
    firstItem = 1,
    index = 1,
    labels = { "YES", "NO" },
  }
  for key, value in pairs(overrides or {}) do self[key] = value end
  return self
end

local function firstOf(what)
  for _, call in ipairs(calls) do
    if call.what == what then return call end
  end
end

local function allOf(what)
  local out = {}
  for _, call in ipairs(calls) do
    if call.what == what then out[#out + 1] = call end
  end
  return out
end

-- ------------------------------------------------------------ installing

do
  io.write("installing\n")
  freshChrome()
  local class = freshChoiceBox()
  local base = class.draw

  eq(ChoiceBox2.install(context()), true, "the class is patched")
  ok(class.draw ~= base, "and its draw is not the engine's any more")
  ok(rawget(class, ChoiceBox2.PATCH_KEY), "a sentinel is left on the class")

  eq(ChoiceBox2.install(context()), false,
     "a second install is a no-op -- a hot reload must not wrap a wrap")
end

do
  io.write("a build that cannot carry it\n")
  freshChrome()
  local class = freshChoiceBox()
  local base = class.draw

  Chrome.cursorThrough = nil
  eq(ChoiceBox2.install(context()), false, "install stands down")
  eq(class.draw, base,
     "and leaves the engine's own draw alone -- a patch that would fail on "
     .. "its first frame is worse than a white box")
  ok(#logged > 0, "and says so once")
end

-- ---------------------------------------------------------------- painting

do
  io.write("what the paint asks for\n")
  freshChrome()
  local class = freshChoiceBox()
  ChoiceBox2.install(context())

  local box = boxInstance()
  class.draw(box)

  eq(drew, 0, "the engine's own draw does not run")

  local drawn = firstOf("box")
  ok(drawn ~= nil, "the box goes through Chrome.paletteBox")
  eq(drawn and drawn.tx, 14, "at the instance's own tx")
  eq(drawn and drawn.ty, 7, "and ty")
  eq(drawn and drawn.tw, 6, "and width")
  eq(drawn and drawn.th, 5, "and height")

  local labels = allOf("print")
  eq(#labels, 2, "both labels are printed")
  eq(labels[1] and labels[1].text, "YES", "YES first")
  eq(labels[1] and labels[1].tx, 16,
     "two tiles in from the box, which is where Font.draw put it")
  eq(labels[1] and labels[1].ty, 8, "on the first item's row")
  eq(labels[2] and labels[2].text, "NO", "NO second")
  eq(labels[2] and labels[2].ty, 10, "two rows below it")

  local cursor = firstOf("cursor")
  ok(cursor ~= nil, "the cursor goes through Chrome.cursorThrough")
  eq(cursor and cursor.tx, 15, "one tile left of the labels")
  eq(cursor and cursor.ty, 8, "on the row the index names")
end

do
  freshChrome()
  local class = freshChoiceBox()
  ChoiceBox2.install(context())

  class.draw(boxInstance({ index = 2 }))
  eq(firstOf("cursor").ty, 10, "index 2 puts the cursor on NO")

  -- TwoOptionMenuStrings' "blank line before the first item?" flag.
  freshChrome()
  class.draw(boxInstance({ firstItem = 2 }))
  eq(allOf("print")[1].ty, 9, "firstItem 2 moves both rows down one")
  eq(allOf("print")[2].ty, 11, "including the second")
  eq(firstOf("cursor").ty, 9, "and the cursor with them")

  -- Rows that carry their own labels rather than YES/NO.
  freshChrome()
  class.draw(boxInstance({ labels = { "NORTH", "SOUTH" } }))
  eq(allOf("print")[1].text, "NORTH", "a row's own labels are what is printed")
  eq(allOf("print")[2].text, "SOUTH", "both of them")
end

do
  io.write("the box is hidden\n")
  freshChrome()
  local class = freshChoiceBox()
  ChoiceBox2.install(context())

  hidden = true
  class.draw(boxInstance())
  eq(#calls, 0,
     "nothing is drawn -- the engine's own bottomVisible guard is kept, not "
     .. "re-decided")
  eq(drew, 0, "and the engine's draw is not reached for either")
  hidden = false
end

-- ---------------------------------------------------------------- palette

do
  io.write("the palette is the live one\n")
  freshChrome()
  local class = freshChoiceBox()
  ChoiceBox2.install(context())

  class.draw(boxInstance())
  eq(firstOf("box").palette, Chrome.DEFAULT_BOX_PALETTE,
     "the box is drawn through the table itself, not a copy of it")
  eq(firstOf("print").palette, Chrome.DEFAULT_BOX_PALETTE,
     "and so are the labels")
  eq(firstOf("cursor").palette, Chrome.DEFAULT_BOX_PALETTE,
     "and the cursor")

  -- What the theme does: overwrite the four entries IN PLACE.  A file that
  -- had copied the table at install would still be painting white.
  local live = Chrome.DEFAULT_BOX_PALETTE
  for index, color in ipairs({ { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 },
                               { 255, 255, 255 } }) do
    live[index] = color
  end
  calls = {}
  class.draw(boxInstance())
  eq(firstOf("box").palette[1][1], 0,
     "after the theme reverses those four in place, the box paints black")
  eq(firstOf("box").palette[4][1], 255, "with white ink")
end

do
  io.write("a screen with paper of its own\n")
  freshChrome()
  local class = freshChoiceBox()
  ChoiceBox2.install(context())

  -- The Pokegear's cream: Gold's answer to a screen whose BG palette 0 is not
  -- white.  TextBox honours it with exactly this fold and so does this.
  local cream = { 248, 240, 200 }
  class.draw(boxInstance({ game = {
    textboxPaper = function() return cream end,
  } }))

  local palette = firstOf("box").palette
  ok(palette ~= Chrome.DEFAULT_BOX_PALETTE,
     "the screen's own paper wins over the themed default")
  eq(palette[1], cream, "paper in the first slot")
  eq(palette[3], cream, "and the third")
  eq(palette[4][1], 0, "with black ink, which is the fold TextBox uses")

  -- A build whose textboxPaper answers nothing falls back rather than
  -- painting a box out of nil.  Only `calls` is reset here: a freshChrome()
  -- would build a table the installed closure has never seen.
  calls = {}
  class.draw(boxInstance({ game = { textboxPaper = function() return nil end } }))
  eq(firstOf("box").palette, Chrome.DEFAULT_BOX_PALETTE,
     "no paper means the themed default")

  calls = {}
  class.draw(boxInstance({ game = { textboxPaper = function() error("no") end } }))
  eq(firstOf("box").palette, Chrome.DEFAULT_BOX_PALETTE,
     "and a textboxPaper that raises does not take the box down with it")
end

-- -------------------------------------------------------- standing down

do
  io.write("a paint that raises\n")
  freshChrome()
  local class = freshChoiceBox()
  ChoiceBox2.install(context())

  Chrome.paletteBox = function() error("shader gone") end

  class.draw(boxInstance())
  eq(drew, 1, "the engine's own draw is what the player gets")
  ok(#logged > 0, "and it is reported")
  local said = #logged

  class.draw(boxInstance())
  class.draw(boxInstance())
  eq(drew, 3, "every frame after it goes straight there")
  eq(#logged, said,
     "and says nothing more -- once per session, not once per frame")
end

io.write(("choicebox2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
