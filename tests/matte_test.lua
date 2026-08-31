-- Headless coverage of the true-colour matte on screens the suite does not
-- own -- the trainer card's portrait, the summary screen's Pokemon, the Hall
-- of Fame PC, the diploma.
--
-- The bug: `PaletteFX.markTrueColor` splices a `colors = false` rect onto the
-- END of the frame's zone list and re-blits that region RAW, so a coloured
-- portrait keeps its colours.  Raw also keeps the WHITE the screen cleared its
-- page to, which is a white box on a dark page -- and no zone this suite adds
-- can reach inside a rect that re-blits over it.
--
-- The one fact that decides when any of this runs: `Renderer`'s withTrueColor
-- opens with `if not PaletteFX.honorsTrueColor() then return zoneList end`,
-- and for a Gen 1 game that is `mode == "redpp"` -- ADVANCED, and nothing
-- else.  In SGB the marks are discarded and there is no box, so there is
-- nothing to paint and nothing here should fire.
--
-- Run:  luajit tests/matte_test.lua

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

-- ------- the engine, as much of it as this touches

local fills = {}          -- every rectangle painted, in order
love = {
  graphics = {
    setColor = function(r, g, b) love.graphics.colour = { r, g, b } end,
    rectangle = function(_, x, y, w, h)
      local c = love.graphics.colour or {}
      fills[#fills + 1] = { x = x, y = y, w = w, h = h,
                            colour = { c[1], c[2], c[3] } }
    end,
  },
}

local PaletteFX          -- forward, so the closures below can see it
PaletteFX = {
  mode = "redpp",
  marks = {},
  honorsTrueColor = function() return PaletteFX.mode == "redpp" end,
  markTrueColor = function(x, y, w, h)
    PaletteFX.marks[#PaletteFX.marks + 1] = { x = x, y = y, w = w, h = h }
  end,
}
package.preload["src.render.PaletteFX"] = function() return PaletteFX end

local Matte = chunkOf("runtime/matte.lua")

-- ------- the theme, as the bundle hands it over

local themeValue = "dark"
local theme = {
  read = function() return themeValue end,
  matte = function()
    if themeValue == "light" then return { 255, 255, 255 } end
    return { 0, 0, 0 }
  end,
}

local warned = {}
local context = {
  theme = theme,
  mod = { log = { warn = function(_, text, ...) warned[#warned + 1] = text end } },
}

-- A screen that draws two things and marks one of them.
local drawn
local function screenDraw(self)
  drawn = drawn + 1
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)     -- its page
  PaletteFX.markTrueColor(104, 4, 40, 40)             -- its portrait
end

local function reset()
  fills, drawn, PaletteFX.marks, warned = {}, 0, {}, {}
end

local function wrapped(fn)
  return Matte.new(context).wrap(fn or screenDraw)
end

-- ---------------------------------------------------------------- the tests

io.write("the matte paints under the art, and the art is drawn again on it\n")
do
  reset()
  wrapped()({})

  eq(drawn, 2, "the screen draws twice: once to learn where the art goes, "
    .. "once for real on top of the matte")
  eq(#PaletteFX.marks, 1,
    "and marks its rectangle exactly once -- the recording pass stands in "
    .. "for markTrueColor rather than doubling it")

  -- page, matte, page again.  The matte is the middle one, and it is the
  -- rectangle the screen marked rather than the whole page.
  eq(#fills, 3, "two pages and one matte")
  eq(fills[2].x, 104, "the matte is where the art is")
  eq(fills[2].y, 4, "...both axes")
  eq(fills[2].w, 40, "and the size the art is")
  eq(fills[2].h, 40, "...both axes")
  eq(fills[2].colour[1], 0, "under DARK it is black")
  eq(fills[2].colour[3], 0, "...on every channel")
end

io.write("and only in ADVANCED, because only ADVANCED honours the marks\n")
do
  -- In SGB the renderer discards every true-colour rect, the art goes through
  -- the shade pass with the rest of the screen, and there is no box to fix.
  reset()
  PaletteFX.mode = "gbc"
  wrapped()({})
  eq(drawn, 1, "an SGB boot draws once, the way it always did")
  eq(#fills, 1, "and paints no matte")
  eq(#PaletteFX.marks, 1, "the screen still marks; the renderer is what drops it")
  PaletteFX.mode = "redpp"
end

io.write("nor under LIGHT, nor with no theme at all\n")
do
  reset()
  themeValue = "light"
  wrapped()({})
  eq(drawn, 1, "LIGHT draws once")
  eq(#fills, 1, "and paints nothing extra: the page is already white")
  themeValue = "dark"

  reset()
  local bare = Matte.new({ theme = nil, mod = context.mod })
  bare.wrap(screenDraw)({})
  eq(drawn, 1, "a build with no theme draws once")
  eq(#fills, 1, "...and is untouched")
end

io.write("a screen that marks nothing is drawn once and left alone\n")
do
  reset()
  local plain = function(self)
    drawn = drawn + 1
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  wrapped(plain)({})
  eq(drawn, 1, "the recording pass IS the frame when it finds no art")
  eq(#fills, 1, "so nothing is drawn twice and nothing is painted over")
end

io.write("a screen that raises is still a drawn screen\n")
do
  reset()
  local hostile = function(self)
    drawn = drawn + 1
    if drawn == 1 then error("half way through") end
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  local out = wrapped(hostile)
  ok(pcall(out, {}), "the wrapper does not take the frame down")
  eq(drawn, 2, "it draws the screen again plainly instead of leaving it half done")
  eq(#warned, 1, "and says so once")
end

io.write("marks are restored even when the recording pass raises\n")
do
  reset()
  local real = PaletteFX.markTrueColor
  local hostile = function() drawn = drawn + 1; error("no") end
  pcall(wrapped(hostile), {})
  eq(PaletteFX.markTrueColor, real,
    "markTrueColor is the engine's own again, or every screen after this one "
    .. "would silently stop marking")
end

-- ------------------------------------------------ the title screen's ground

-- The title is the one page this suite darkens by PAINTING rather than by
-- reversing: `TitleState:draw` opens with a white fill of the whole screen,
-- so a matte painted before it is painted over by it.  The fill is served
-- black instead, the copyright row is left white for the theme to reverse,
-- and a true-colour rectangle then re-blits a page that is already black --
-- no white box, and nothing drawn twice.

local function titleDraw(self)
  drawn = drawn + 1
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)     -- the page
  if self.menuOpen then return end
  PaletteFX.markTrueColor(82, 80, 16, 16)             -- the figure
end

io.write("the title screen's page is painted black under the art\n")
do
  reset()
  local title = {}
  Matte.new(context).wrapTitle(titleDraw)(title)

  eq(drawn, 1, "drawn ONCE -- this is the page, not a matte, so there is "
    .. "nothing to learn from a first pass")
  -- No love.image here, so no bake took: the copyright art could not be
  -- turned over, and a row whose letters are still dark is not painted black.
  eq(#fills, 2, "the one full-screen fill is served as two")
  eq(fills[1].colour[1], 0, "the page is black")
  eq(fills[1].h, 136, "...down to the copyright row and no further")
  eq(fills[2].colour[1], 1, "and that row is left white")
  eq(fills[2].y, 136, "...where the copyright line is drawn")
  eq(fills[2].h, 8, "...one row of it")
  eq(#PaletteFX.marks, 1, "the figure still marks, exactly once")
  eq(PaletteFX.marks[1].x, 82, "...its own rectangle, untouched")
  eq(title.__gen1WildDarkGround, true,
    "and the state carries the frame's flag, which is what tells the theme "
    .. "to pin colour 3 rather than reverse the bands")
end

io.write("...in every display mode, because it is a page and not a mark\n")
do
  reset()
  PaletteFX.mode = "gbc"
  local title = {}
  Matte.new(context).wrapTitle(titleDraw)(title)
  eq(#fills, 2, "SGB gets the black page too")
  eq(fills[1].colour[1], 0, "...black")
  eq(title.__gen1WildDarkGround, true, "and the flag with it")
  PaletteFX.mode = "redpp"
end

io.write("with the CONTINUE menu open it is left alone\n")
do
  -- There is no art on that screen -- MainMenu's ClearScreen wipes the logo,
  -- the mon and the figure -- so the frame is an ordinary page and
  -- Theme.COVERED_PAGES reverses it.  A black ground would reverse to white.
  reset()
  local title = { menuOpen = true }
  Matte.new(context).wrapTitle(titleDraw)(title)
  eq(#fills, 1, "one fill, the screen's own")
  eq(fills[1].colour[1], 1, "still white")
  eq(title.__gen1WildDarkGround, nil, "and no flag, so the theme reverses it")
end

io.write("nor under LIGHT\n")
do
  reset()
  themeValue = "light"
  local title = {}
  Matte.new(context).wrapTitle(titleDraw)(title)
  eq(#fills, 1, "the page is white, which is what it always was")
  eq(title.__gen1WildDarkGround, nil, "and nothing is flagged")
  themeValue = "dark"
end

io.write("and the real rectangle is back even when the screen raises\n")
do
  reset()
  local real = love.graphics.rectangle
  local hostile = function(self)
    drawn = drawn + 1
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    if drawn == 1 then error("half way through") end
  end
  local out = Matte.new(context).wrapTitle(hostile)
  ok(pcall(out, {}), "the wrapper does not take the frame down")
  eq(love.graphics.rectangle, real,
    "love.graphics.rectangle is the engine's own again, or every screen "
    .. "after this one would draw through a shim that is not theirs")
  eq(#warned, 1, "and it says so once")
end

io.write("the skirts are laid down again once the screen has finished\n")
do
  -- Wild Green marks the title figure BEFORE calling the draw, because that
  -- draw reads self.player at its top -- and the draw opens with a
  -- full-screen fill, which wipes the skirt the mark just painted.  The
  -- figure kept its hairline while the mon, marked from inside the draw, did
  -- not.  Laying the rings down again after the screen has finished is safe:
  -- a ring is outside the art's own rectangle by construction.
  reset()
  local repainted = 0
  local withSkirts = {
    theme = theme,
    mod = context.mod,
  }
  withSkirts.theme = setmetatable(
    { paintSkirts = function() repainted = repainted + 1 end },
    { __index = theme })
  local title = {}
  Matte.new(withSkirts).wrapTitle(titleDraw)(title)
  eq(repainted, 1, "once, after the page and the art are down")

  reset()
  repainted = 0
  local hostile = function(self)
    drawn = drawn + 1
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    error("half way through")
  end
  pcall(Matte.new(withSkirts).wrapTitle(hostile), {})
  eq(repainted, 0, "and not over a frame that raised part way through")
end

io.write("the screens it patches are the ones that mark and are themed\n")
do
  -- A screen that marks nothing has nothing to matte; a screen the theme
  -- leaves alone is still on white paper, where a white box is invisible.
  local named = {}
  for _, path in ipairs(Matte.SCREENS) do named[path] = true end
  ok(named["src.ui.TrainerCard"], "the trainer card's portrait")
  ok(named["src.ui.SummaryMenu"], "the summary screen's POKeMON")
  ok(named["src.ui.LeaguePC"], "the Hall of Fame PC")
  ok(named["src.ui.Diploma"], "the diploma")
  ok(named["src.ui.DexEntryMenu"],
    "and the engine's dex entry, for the build with POKEDEX switched off")
end

io.write(("\nmatte: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
