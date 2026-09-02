-- A party icon does not mark true colour under somebody else's message box.
--
-- A marked rectangle is blitted RAW: whatever is in those pixels when the
-- frame is composed, exempt from the palette pass.  That is right while the
-- icon is the last thing drawn there and a lie the moment anything covers it.
--
-- The engine covers it.  `PartyMenu:refuse` pushes a TextBox -- "<NAME> is
-- already out!", the battle switch offering the POKeMON already in the fight
-- -- and every message box in this game stands at tile row 12, y=96
-- (src/render/TextBox.lua, BOX_TY).  On the ENGINE's party screen the rows run
-- 0..96 and y=96 is exactly under the sixth of them, which is why the engine
-- never had this.  This screen has a header box, so every row moved down 24
-- and y=96 lands a row and a half INTO the body: slot 6's icon (104..120) and
-- slot 5's HP row are underneath the box, and slot 6's mark punched a 16x16
-- hole of raw white page through it -- the box's own paper, un-inverted, with
-- its black ink still on it.
--
-- So the subject here is one question -- where does the covering start -- and
-- the numbers are the point, because being wrong by a row is invisible until
-- somebody has six POKeMON and loses a battle switch.
--
-- Run:  luajit tests/partycover_test.lua

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

-- ------------------------------------------------------------- the harness

_G.love = { graphics = {
  setColor = function() end, rectangle = function() end,
  push = function() end, pop = function() end, draw = function() end,
} }

local function stub(name, value) package.preload[name] = function() return value end end
stub("src.render.Font", { draw = function() end, drawBox = function() end,
                          width = function() return 0 end,
                          split = function(s) return { s } end,
                          BORDER = {} })
stub("src.render.HudTiles", { tile = function() end, drawHPBar = function() end })
stub("src.render.PaletteFX", { GRAYS = {}, whole = function() end,
                               zone = function() end, pal = function() end,
                               monPal = function() end, shader = function() end,
                               barPalName = function() return "GREENBAR" end,
                               markTrueColor = function() end })
stub("src.ui.PartyMenu", { new = function() return {} end,
                           sgbPalettes = function() end,
                           update = function() end, drawIcon = function() end,
                           entryY = function(i) return (i - 1) * 16 end })
stub("src.pokemon.Sprites", {})
stub("src.battle.Status", { hudLabelFor = function() return "" end })
stub("src.core.Strings", setmetatable({}, { __call = function(_, s) return s end }))
stub("src.ui.Theme", {})

local Screen = load_("modules/Gen1Party/screen.lua")({ theme = function() end },
  { BODY_TOP = 24, BODY_BOTTOM = 119, HEADER_TH = 3, FOOTER_TY = 15,
    LEFT = 8, RIGHT = 152, LINE_W = 144, HEADER_TEXT_Y = 8, FOOTER_TEXT_Y = 128,
    ROW = 8, black = function() end, white = function() end,
    clear = function() end, headerBox = function() end,
    footerBox = function() end, rule = function() end,
    option = function() return true end, truncate = function(s) return s end,
    shorten = function(s) return s end, rightAlign = function() return 0 end })

local coverTop = Screen.coverTop
ok(type(coverTop) == "function", "coverTop is exposed")

-- A stack is a list; the screen is somewhere in it and things above it cover.
local function screenIn(states, self)
  return { game = { stack = { states = states } } , __self = self }
end

local function ask(states, self)
  self.game = { stack = { states = states } }
  return coverTop(self)
end

io.write("where the covering starts\n")

-- ------------------------------------------------------- nothing on top

do
  local me = {}
  eq(ask({ me }, me), nil, "alone on the stack, nothing covers")
  eq(ask({ {}, {}, me }, me), nil, "and states BELOW do not cover either")
  eq(coverTop({}), nil, "no game at all is not a crash")
  eq(coverTop({ game = {} }), nil, "nor a game with no stack")
end

-- ---------------------------------------- the engine's own message box

do
  local me = {}
  -- TextBox carries the geometry it was built with; the default is tile row
  -- 12 (src/render/TextBox.lua, BOX_TY = 12).
  eq(ask({ me, { boxTy = 12 } }, me), 96,
     "the standard message box covers from y=96")
  eq(ask({ me, {} }, me), 96,
     "and a state above that does not say where it is is assumed to be there")
end

-- ------------------------------------------------- a box that says otherwise

do
  local me = {}
  eq(ask({ me, { boxTy = 7 } }, me), 56,
     "a caller's own box is taken at its word -- the battle switch passes one")
  eq(ask({ me, { boxTy = 12 }, { boxTy = 7 } }, me), 56,
     "two boxes: the highest one is what the icons have to clear")
  eq(ask({ me, { boxTy = 7 }, { boxTy = 12 } }, me), 56,
     "in either order -- it is the topmost EDGE, not the topmost state")
end

-- --------------------------------------------------- what it means for a row
--
-- entryY(i) = BODY_TOP + (i-1)*16, and an icon is 16 tall.  Against a cover
-- at 96 that is the arithmetic the screen actually runs.
do
  local BODY_TOP, ICON = 24, 16
  local function entryY(i) return BODY_TOP + (i - 1) * ICON end
  local function covered(i, top) return entryY(i) + ICON > top end

  eq(covered(1, 96), false, "slot 1 (24..40) is clear of a box at 96")
  eq(covered(4, 96), false, "slot 4 (72..88) is clear")
  eq(covered(5, 96), true, "slot 5 (88..104) runs into it")
  eq(covered(6, 96), true, "slot 6 (104..120) is entirely under it -- the bug")

  -- Without a box up, no row is covered: the suite's own footer starts at 120
  -- and the body was sized to hold all six.
  eq(entryY(6) + ICON, 120, "slot 6 ends exactly where the footer box begins")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
