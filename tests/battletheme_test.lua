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

-- The theme matches a page by CLASS, so the test has to be the same table
-- `src.ui.ListMenu` resolves to when Theme.PAGES is walked.
local ListMenu = {}
ListMenu.__index = ListMenu
package.preload["src.ui.ListMenu"] = function() return ListMenu end

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

-- ------------------------- a page opened ON a battle keeps the battle's art
do
  -- The bag, in a fight. A ListMenu has no palettes of its own, so the zone
  -- list handed to the theme still belongs to the battle underneath -- and a
  -- battle's list is `colors = false`, a RAW blit, which is how its backdrop
  -- and its POKeMON keep their colours.
  --
  -- Synthesising a whole-screen page over that threw the raw list away and
  -- read the fight through four greys: reported as the bag turning everything
  -- behind it black and white. A page that brought no palettes of its own must
  -- not paint over art it did not draw; its own boxes are themed as panels
  -- either way.
  local t = theme("dark")
  local bag = { gen1wildTheme = true }        -- a page, and no sgbPalettes
  local raw = { { colors = false, x = 0, y = 0, w = 160, h = 144 } }
  local out = t.apply(gameWith({ battleState(), bag }), raw)

  ok(out and out[1], "the frame still has a zone list")
  eq(out and out[1] and out[1].colors, false,
     "and the battle's raw blit is still raw, so the fight keeps its colours")
end

-- --------------------------- and the BAG in a battle, which is the real one
do
  -- The case above hand-builds a page and a raw list. The bag is neither.
  --
  -- `src.ui.ListMenu` is in Theme.PAGES, and rightly: the shop's list, the
  -- PC's and the prize counter's are each a screen of their own. The bag's is
  -- not, and ListMenu says so itself when `itemBox` is set
  -- (ListMenu.lua:132-137): `isOpaque = false`, so what is behind it is still
  -- on screen, and `sgbPalettes = false`, so it brought no palette and the one
  -- already up stays. That is a BOX ON somebody else's screen -- a panel, the
  -- same thing the START menu is on the map.
  --
  -- And the screen underneath is the fight, which hands the theme NO zone
  -- list at all: `BattleState:sgbPalettes` returns nil for the classic
  -- layout, and an empty list is the engine's "blit this frame in the colours
  -- it was drawn in" (Renderer:blitCanvas -- no zones, no shader). Counting
  -- the bag as a page synthesised a whole-screen palette over exactly that,
  -- and the backdrop and the POKeMON went through four greys: reported as the
  -- item menu in battle turning the background black and white.
  local t = theme("dark")
  local bag = setmetatable({ itemBox = true, isOpaque = false,
                             sgbPalettes = false }, ListMenu)
  Theme.recordBox(4, 2, 16, 11)               -- the item window
  local out = t.apply(gameWith({ battleState(), bag }), nil)

  ok(out and out[1], "the frame is given a zone list to hang the box on")
  eq(out and out[1] and out[1].colors, false,
     "and it opens RAW, so the fight behind the bag keeps its colours")

  local panel
  for _, zone in ipairs(out or {}) do
    if type(zone.colors) == "table" and zone.x == 32 and zone.w == 128 then
      panel = zone
    end
  end
  ok(panel, "the bag's own window is still themed, as a panel on that frame")
end

-- ------------------------------------- and a list that is NOT the bag's
do
  -- The same class, opened the other way: no itemBox, so it is opaque and it
  -- carries the generic whole-screen palette. That is a page and must stay
  -- one -- the shop, the item PC, the prize counter.
  local t = theme("dark")
  local shop = setmetatable({ isOpaque = true,
                              sgbPalettes = function() end }, ListMenu)
  local zones = { { colors = GREYS, x = 0, y = 0, w = 160, h = 144 } }
  local out = t.apply(gameWith({ shop }), zones)
  local page = firstColors(out)
  ok(page and page ~= GREYS and page[1] and page[1][1] < 96,
     "a full-screen list is still a page, and DARK still reverses it")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
