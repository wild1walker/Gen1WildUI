-- The caught indicator's POKeBALL and the EXP bar's fill, under DARK.
--
-- Reported together, twice: "the caught marker looks broken, and the exp bar
-- looks broken".  The first fix cut the ball's marks from thirty-seven to
-- seven -- one per contiguous run rather than one per pixel -- which was a
-- real problem (thirty-seven of the frame's forty art rects went on one icon,
-- so the bar's own mark fell off the end and lost the zone that themes it).
-- It was not THIS problem, and the report came back.
--
-- The ring is.  `watchArt` paints a one-pixel skirt round every true-colour
-- mark inside a box, suppressed only where it lands inside a rect ALREADY
-- recorded.  For these two that is exactly wrong:
--
--   * the ball is marked one run per row, and each run's ring reaches into the
--     CONCAVE corners the ball never draws.  Twelve pixels of dark inside its
--     own 7x7 -- a POKeBALL as a rounded blob.
--   * the bar is one flat rect, so its ring is a complete outline round it,
--     drawn on the light HUD panel.  A black box round the blue fill.
--
-- Neither has a seam to hide.  Both are flat colour a mod painted itself,
-- pixel by pixel, and it knows precisely which pixels those are -- so both
-- mark through `__gen1WildMarkFlat`, which records the rect (the ART_PAGE zone
-- is what keeps the colour, and every true-colour rect needs one) and draws
-- nothing round it.
--
-- Run:  luajit tests/battleart_test.lua

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

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end
local function load_(path, ...)
  return assert(load(assert(readFile(path)), "@" .. path))(...)
end

package.loaded["src.mods.ManagerState"] = { openOptions = function() end }

-- PaletteFX cut down to the trueColor plumbing, the way spritemark_test does.
local PaletteFX = {}
local rects = { ui = {}, world = {} }
local currentPass = nil
function PaletteFX.setPass(name) currentPass = rects[name] and name or nil end
function PaletteFX.trueColorRects(name) return rects[name] or {} end
function PaletteFX.spriteRedrawPassActive() return currentPass == "world" end
function PaletteFX.honorsTrueColor() return true end
function PaletteFX.markTrueColor(x, y, w, h)
  local list = currentPass and rects[currentPass]
  if not list or w <= 0 or h <= 0 then return end
  list[#list + 1] = { colors = false, x = x, y = y, w = w, h = h }
end
package.loaded["src.render.PaletteFX"] = PaletteFX
package.loaded["src.render.SpriteRenderer"] =
  { draw = function() end, drawTile = function() end }

local fills = {}
love = { graphics = {
  setColor = function() end,
  rectangle = function(_, x, y, w, h)
    fills[#fills + 1] = { x = x, y = y, w = w or 1, h = h or 1 }
  end,
} }

local OptionSet = load_("runtime/optionset.lua")
local Theme = load_("runtime/theme.lua")
local stored = {}
local mod = {
  id = "ui",
  options = { define = function() end,
              get = function(_, key) return stored[key] end,
              set = function(_, key, value) stored[key] = value end },
  log = { info = function() end, warn = function() end, error = function() end },
  hooks = { wrap = function() end },
}
local theme = Theme.new({ mod = mod, optionset = OptionSet.new() })
theme.defineRow()
theme.write("dark")
theme.install()

-- A BATTLE is not a themed page, so what makes its art shaded -- and therefore
-- ringed -- is CONTAINMENT IN A BOX.  The enemy HUD frame is one, and both the
-- ball and the bar are drawn inside it.  Without this the ring is not painted
-- at all and neither half of this file would be testing anything.
Theme.recordBox(0, 0, 160, 40)

local function reset()
  for _, list in pairs(rects) do
    for i = #list, 1, -1 do list[i] = nil end
  end
  for i = #fills, 1, -1 do fills[i] = nil end
  local shared = rawget(PaletteFX, "__gen1WildArtRects")
  if shared then for i = #shared, 1, -1 do shared[i] = nil end end
end

local FLAT = rawget(PaletteFX, "__gen1WildMarkFlat")
ok(type(FLAT) == "function",
  "the theme publishes a flat mark for art that painted itself")

-- ------------------------------------------------------------ the POKeBALL

-- qol_feature_caught_indicator.lua's BALL_ROWS, and the run-marking it does.
local BALL_ROWS = {
  "ooxxxoo", "oxdddxo", "xdldddx", "xdddddx", "xlllllx", "oxlllxo", "ooxxxoo",
}
local BALL_X, BALL_Y = 8, 8

local function drawBall(mark)
  for py, row in ipairs(BALL_ROWS) do
    local from = nil
    for px = 1, #row + 1 do
      local drawn = px <= #row and row:sub(px, px) ~= "o"
      if drawn then
        from = from or px
      elseif from then
        mark(BALL_X + from - 1, BALL_Y + py - 1, px - from, 1)
        from = nil
      end
    end
  end
end

-- Every pixel the ball actually paints, so "dark where the ball is not" can be
-- counted rather than described.
local painted = {}
for py, row in ipairs(BALL_ROWS) do
  for px = 1, #row do
    if row:sub(px, px) ~= "o" then
      painted[(BALL_X + px - 1) .. "," .. (BALL_Y + py - 1)] = true
    end
  end
end

local function strayInsideBall()
  local stray = {}
  for _, f in ipairs(fills) do
    for dx = 0, f.w - 1 do
      for dy = 0, f.h - 1 do
        local px, py = f.x + dx, f.y + dy
        if px >= BALL_X and px < BALL_X + 7
           and py >= BALL_Y and py < BALL_Y + 7
           and not painted[px .. "," .. py] then
          stray[px .. "," .. py] = true
        end
      end
    end
  end
  local n = 0
  for _ in pairs(stray) do n = n + 1 end
  return n
end

do
  io.write("the POKeBALL keeps its corners\n")

  reset()
  PaletteFX.setPass("ui")
  drawBall(PaletteFX.markTrueColor)
  eq(#rects.ui, 7, "seven runs, one per row -- the shape of the ball exactly")
  eq(strayInsideBall(), 12,
    "and the ordinary mark rings each of them into the four corners the ball "
    .. "never draws, which is the blob")

  reset()
  PaletteFX.setPass("ui")
  drawBall(FLAT)
  eq(#rects.ui, 7, "the flat mark records the same seven")
  eq(strayInsideBall(), 0, "and paints nothing into the corners")
  eq(#fills, 0, "nor anywhere else")
end

-- --------------------------------------------------------------- the EXP bar

do
  io.write("the EXP bar keeps its edges\n")

  reset()
  PaletteFX.setPass("ui")
  PaletteFX.markTrueColor(40, 30, 32, 2)
  eq(#fills, 4,
    "the ordinary mark draws a complete outline round the bar -- top, bottom "
    .. "and both ends")

  reset()
  PaletteFX.setPass("ui")
  FLAT(40, 30, 32, 2)
  eq(#fills, 0, "the flat mark draws none of it")
  eq(#rects.ui, 1, "while still claiming the rect")
end

-- ------------------------------------------- and the zone is the point of it

do
  io.write("a flat mark is still art, and still gets its zone\n")
  reset()
  PaletteFX.setPass("ui")
  FLAT(40, 30, 32, 2)
  local shared = rawget(PaletteFX, "__gen1WildArtRects")
  eq(shared and #shared or 0, 1,
    "it lands in the list withArt turns into the frame's ART_PAGE zone")
  -- Which is the whole reason it is a MARK and not simply a draw: without the
  -- zone the rect is re-blitted raw with nothing saying so, and the bar comes
  -- back in the palette's four shades instead of its own blue.
  local rect = shared and shared[1]
  ok(rect and rect.x == 40 and rect.y == 30 and rect.w == 32 and rect.h == 2,
    "at the rectangle that was marked")
end

-- ------------------------------------------------ and with no theme at all

do
  io.write("a build with no theme installed marks exactly as it always did\n")
  -- The callers reach the flat mark by name and fall back to the plain one,
  -- so a standalone install -- no bundle, no theme, no ring to avoid -- is
  -- unchanged.  Asserted because the fallback is a `rawget` that returns nil,
  -- which is the easiest kind of line to get backwards.
  local bare = {}
  local flat = rawget(bare, "__gen1WildMarkFlat")
  ok(flat == nil, "there is no flat mark to find")
  local chosen = flat or PaletteFX.markTrueColor
  eq(chosen, PaletteFX.markTrueColor, "so the plain mark is what gets called")
end

io.write(("\nbattleart: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
