-- A battle is not a page, and DARK must leave it alone.
--
-- This is the test that was missing when 0.32.9 shipped, and it is the shape
-- the two tests that shipped with it were not.  Those drove `wholeAt` and
-- `worldTaken` in isolation -- hand-built zone tables, a stubbed renderer --
-- and both passed while battles came out greyscale and garbled with no text
-- box and no move menu.  What neither did was run a BATTLE's own zone list
-- through `Theme.apply` and look at what came back.
--
-- The rule the theme rests on: a page is a screen that OWNS the frame and is
-- ink on paper, so reversing its palette is the whole of dark mode.  A battle
-- owns the frame and is a PICTURE -- backdrop, mon pics, coloured HP bars --
-- and reversing it turns the fight inside out.  `pageState` is supposed to
-- walk the stack and refuse it: a state that owns the zones and is not a page
-- ends the walk with nothing.
--
-- `basePage` is the third way in, and the one to be careful with: "a list that
-- opens on whole-screen greys is a black-and-white page whoever built it".
-- Whatever `isWhole` accepts, a battle must not satisfy that.
--
-- Run:  luajit tests/battletheme_test.lua

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

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

local Theme = load_("runtime/theme.lua")

-- ------------------------------------------------------------- the harness

local GREYS = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 },
                { 0, 0, 0 } }
local GREENBAR = { { 255, 255, 255 }, { 120, 230, 120 }, { 30, 160, 30 },
                   { 0, 0, 0 } }

local function theme(mode)
  return Theme.new({
    mod = { id = "gen1_wild_ui_nightly",
            log = setmetatable({}, { __index = function() return function() end end }),
            hooks = { wrap = function() end },
            events = { on = function() end, once = function() end } },
    optionset = {
      own = function() end,
      read = function() return mode end,
      generation = function() return 1 end,
    },
  })
end

-- A state that owns the frame's zones -- `sgbPalettes` is the engine's own
-- test for that -- and is not one of Theme.PAGES.  That is a battle, the
-- overworld, the title screen: a picture.
local function battleState()
  return { isBattle = true, sgbPalettes = function() end }
end

local function gameWith(states)
  return { stack = { states = states, top = function() return states[#states] end } }
end

-- What the theme did to the first zone: the colours it will paint with.
local function firstColors(out)
  return out and out[1] and out[1].colors or nil
end

io.write("DARK leaves a battle alone\n")

-- ------------------------------- a classic battle declares NO palettes
do
  -- src/battle/BattleState.lua: `sgbPalettes` returns nil unless the layout is
  -- wide.  So the engine's zone walk stops AT the battle -- it owns the frame
  -- -- and hands this hook nothing at all.
  local t = theme("dark")
  local out = t.apply(gameWith({ battleState() }), nil)
  eq(out, nil, "a classic battle owns the frame and declares no zones")
end

-- ------------------------------------------- a wide battle declares its own
do
  -- WideBattle.zones(): 304x144, and `colors = false` -- a RAW blit, not a
  -- palette.  Neither shape can be mistaken for a 160x144 page however
  -- `isWhole` is written, which is the property that has to hold.
  local t = theme("dark")
  local zones = { { colors = false, x = 0, y = 0, w = 304, h = 144 } }
  local out = t.apply(gameWith({ battleState() }), zones)
  eq(out, zones, "a wide battle's raw-blit list is handed straight back")

  -- ...and its monochrome form, which IS greys over the whole 304.
  local GRAYS_WIDE = { { colors = GREYS, x = 0, y = 0, w = 304, h = 144 } }
  eq(t.apply(gameWith({ battleState() }), GRAYS_WIDE), GRAYS_WIDE,
     "and so is the mono one, because 304 is not the GB frame")
end

-- ------------------ the trap the wide-layout fix must not spring
do
  -- Widening `isWhole` to find a frame CENTRED over a wide battle -- which a
  -- page opened there needs -- must not let a 160-wide band belonging to
  -- something that is not a page satisfy basePage.  A battle that somehow
  -- owns such a list is still a picture.
  local t = theme("dark")
  local zones = {
    { colors = GREYS, x = 72, y = 0, w = 160, h = 144 },
    { colors = GREENBAR, x = 120, y = 96, w = 48, h = 8 },
  }
  local out = t.apply(gameWith({ battleState() }), zones)
  eq(out, zones, "a battle owning a 160-wide list at x=72 is STILL not a page")
end

io.write("and LIGHT changes nothing at all\n")
do
  local t = theme("light")
  local zones = { { colors = GREYS, x = 0, y = 0, w = 160, h = 144 } }
  eq(t.apply(gameWith({ battleState() }), zones), zones,
     "a light frame is the caller's list, whatever is on the stack")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
