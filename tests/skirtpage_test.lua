-- A skirt hides a seam.  No seam, no skirt.
--
-- The skirt is the one-pixel ring DARK paints round a true-colour mark.  It
-- earns its place on a themed page: the mark re-blits its rect untouched, the
-- page around it went through the palette pass, and the join between the two
-- shows without it.
--
-- On a screen the theme LEAVES ALONE there is no shaded page, so there is no
-- seam -- and the ring is then the only thing the player sees.  Reported as
-- black boxes round Oak, the rival and the NIDORINO through the whole intro,
-- on a white screen, in DARK.
--
-- Those screens are not themed on purpose: Theme.PAGES leaves out "the screens
-- that are pictures rather than pages -- the intro, Oak's speech, the Hall of
-- Fame".  What still reached them is the mark itself: OakSpeech.lua:726 draws
-- the portrait with love.graphics.draw and calls markTrueColor on its whole
-- rect, OUTSIDE SpriteRenderer -- so `dropsSpriteMark`, which needs a sprite
-- depth above zero, never sees it and never drops it.
--
-- Run:  luajit tests/skirtpage_test.lua

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

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

-- ------------------------------------------------------------- the harness

-- The skirt asks PaletteFX two things before it answers, so without one the
-- test would pass by accident on a nil that has nothing to do with pages.
package.preload["src.render.PaletteFX"] = function()
  return {
    honorsTrueColor = function() return true end,
    markTrueColor = function() end,
    trueColorRects = function() return {} end,
  }
end

-- The theme matches a page by its CLASS, so the test needs the same table the
-- theme will resolve `src.ui.OakSpeech` to.
local OakSpeech = {}
OakSpeech.__index = OakSpeech
package.preload["src.ui.OakSpeech"] = function() return OakSpeech end

local Theme = load_("runtime/theme.lua")

-- `render.zones` is where the theme is handed the game, and the skirt reads
-- the stack live from it.  The stub keeps the handler so a test can run a
-- frame the way the engine would.
local function theme(mode)
  local frame
  local t = Theme.new({
    mod = { id = "gen1_wild_ui_nightly",
            log = setmetatable({}, { __index = function() return function() end end }),
            hooks = { wrap = function(_, name, fn)
              if name == "render.zones" then frame = fn end
            end },
            events = { on = function() end, once = function() end } },
    optionset = {
      own = function() end,
      read = function() return mode end,
      generation = function() return 1 end,
    },
  })
  -- `self.skirt` is built by install(), not by new(): it is part of wiring the
  -- theme to the engine, and so is the `render.zones` wrap that feeds it.
  t.install()
  return t, function(game)
    if frame then pcall(frame, function(_, zones) return zones end, game, nil) end
  end
end

local function gameWith(states)
  return { stack = { states = states, top = function() return states[#states] end } }
end

-- A page: the theme's own marker is the shortest way to be one.
local function page() return { gen1wildTheme = true } end

-- Oak's speech: it owns the frame, draws a picture, and is in none of
-- Theme.PAGES.  The theme walks the stack and comes back with nothing.
local function picture() return { sgbPalettes = function() end } end

io.write("a skirt only where there is a seam\n")

-- ------------------------------------------------- the reported case
do
  -- Asked of `onPage` rather than of `skirt`, because the two jobs at that
  -- call site are separate now: `skirt` answers "what colour would a ring be
  -- in this theme", and `onPage` answers "is there a page to ring against".
  -- Gating the colour itself also stopped the art being RECORDED, which cost
  -- every battle its art zone -- see arttrack_test.lua, which asserts the
  -- ring is not painted here by counting the fills.
  local t, runFrame = theme("dark")
  runFrame(gameWith({ picture() }))
  ok(not t.onPage(),
     "no ring round a portrait on a screen the theme does not theme")
end

-- --------------------------------------- and the one it must not break
do
  local t, runFrame = theme("dark")
  runFrame(gameWith({ page() }))
  local colour = t.skirt()
  ok(type(colour) == "table" and #colour >= 3,
     "a themed page still gets its skirt, which is what hides the seam")
end

-- ------------------------------------------------- a page over a picture
do
  -- The naming screen is a page and IS themed, so its portrait keeps the ring
  -- it needs.  This is the case the fix must leave exactly as it was.
  local t, runFrame = theme("dark")
  runFrame(gameWith({ picture(), page() }))
  ok(t.skirt() ~= nil, "a page standing on a picture is still a page")
end

-- ------------------------------------------------------------ and LIGHT
do
  local t, runFrame = theme("light")
  runFrame(gameWith({ page() }))
  ok(t.skirt() == nil, "LIGHT paints no skirt at all, page or not")
end

-- ------------------------------------------- before any frame has run
do
  -- markTrueColor can fire before the first `render.zones` of the session.
  -- Nothing is known about the screen yet, so the answer is no ring rather
  -- than a ring on a guess.
  local t = theme("dark")
  ok(not t.onPage(), "and no ring before the first frame is understood")
end

-- ------------------------------------------- Oak's speech is a page now
do
  -- The screen the whole intro is: it owns the frame (sgbPalettes returns
  -- wholeNamed "MEWMON") and draws portraits on it, so by the picture rule it
  -- was left white all the way through DARK -- the first thing a new game
  -- shows, and the one screen the theme never reached.
  --
  -- It is a page now, and the two things that follow from that are the whole
  -- fix.  A page is themed, so the background goes dark; and `onPage` answers
  -- yes, which is what lets runtime/matte.lua paint the page colour under the
  -- portrait's mark.  Without the second the first is a white box on a dark
  -- page, which is worse than what it replaced.
  local oak = { sgbPalettes = function() end }
  setmetatable(oak, OakSpeech)

  local t, runFrame = theme("dark")
  runFrame(gameWith({ oak }))
  ok(t.onPage(), "Oak's speech counts as a page, so the matte will run on it")

  -- and the ring, which is wanted here: on a dark page it is the seam guard
  -- it was written to be, and it is invisible against the page it guards.
  ok(t.skirt() ~= nil, "and its portrait keeps the skirt a shaded page needs")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
