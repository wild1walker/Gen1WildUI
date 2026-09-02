-- The XP bar stops where this mod's own move panel starts.
--
-- The panel is drawn after the bar and covers it, and that covering is the
-- whole reason the bar was moved into Gen1BattleUI.  It settles the pixels and
-- it does NOT settle the mark: PaletteFX.markTrueColor splices a rect onto the
-- pass's zone list and re-blits its region RAW after the pass is composed --
-- after everything drawn over it in the meantime -- so a marked strip lying
-- under the panel comes back on top of it.
--
-- Two things come back, and both were reported:
--
--   * the bar's own two rows, 89 and 90, as a line across the panel's PP row,
--     which is printed at y=88.
--   * under DARK, the theme's one-pixel skirt around every UI-pass mark, whose
--     TOP edge is row 88 exactly -- a dark line along the top of the PP line.
--
-- The numbers are the point of this file, so they are asserted rather than
-- described: the panel is fourteen tiles (x < 112) and the bar runs to 147, so
-- there is always a bar left after the clip, and it never starts before 112
-- while a panel is up.
--
-- Run:  luajit tests/xpbarpanel_test.lua

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

local drawn, marks = {}, {}

_G.love = {
  graphics = {
    rectangle = function(mode, x, y, w, h)
      drawn[#drawn + 1] = { mode = mode, x = x, y = y, w = w, h = h }
    end,
    setColor = function() end,
    setShader = function() end,
    setCanvas = function() end,
    getCanvas = function() return nil end,
    draw = function() end,
    newImage = function() return nil end,
  },
}

local PaletteFX = {
  mode = "gbc",
  GRAYS = { { 0, 0, 0 }, { 85, 85, 85 }, { 170, 170, 170 }, { 255, 255, 255 } },
  markTrueColor = function(x, y, w, h)
    marks[#marks + 1] = { x = x, y = y, w = w, h = h }
  end,
  effectiveColors = function(colors) return colors end,
  permute = function(colors) return colors end,
}
package.preload["src.render.PaletteFX"] = function() return PaletteFX end
package.preload["src.render.Font"] = function()
  return { BORDER = { v = 1, h = 2, bl = 3, br = 4 },
           drawCode = function() end, split = function(s) return { s } end }
end
package.preload["src.render.HudTiles"] = function()
  return { tile = function() end, capTile = function() return 0 end }
end
package.preload["src.pokemon.Growth"] = function()
  return { expForLevel = function() return 0 end }
end

local makeXP = load_("modules/Gen1BattleUI/xpbar.lua")
local CHROME = { option = function() return true end }

-- At the level cap the bar is full, so its length is a constant rather than a
-- curve: EXP_WIDTH, 67 pixels, from x=80 to x=147.
local function stubBattle(wide)
  local battle = {
    isBattle = true,
    frame = 1,
    fx = {},
    player = { mon = { species = 1, level = 100, exp = 0, hp = 20 } },
    data = { pokemon = { { growthRate = 0 } }, constants = { levelCap = 100 },
             growth_rates = {} },
    wideLayout = function() return wide == true end,
    zoneColorsAt = function() return PaletteFX.GRAYS end,
    activeBgp = function() return nil end,
  }
  battle.game = { stack = { top = function() return battle end } }
  return battle
end

-- Grid.panelRect's own answers, quoted.  Classic moveSelect is
-- { tx = 0, ty = 8, tw = 14, th = 5 }; the wide panel is the ten tiles on the
-- right of the strip.
local CLASSIC_PANEL = { x = 0, y = 64, w = 112, h = 40 }
local WIDE_PANEL = { x = 224, y = 104, w = 80, h = 40 }

local function draw(battle, panel)
  drawn, marks = {}, {}
  local XP = makeXP({}, CHROME, panel and function() return panel end or nil)
  XP.draw(battle)
  return drawn, marks
end

local function bar(rects)
  for _, rect in ipairs(rects) do
    if rect.h == 2 then return rect end
  end
  return nil
end

io.write("the XP bar and the move panel\n")

-- ------------------------------------------------------------- no panel up

do
  local rects, marked = draw(stubBattle(false), nil)
  local rect = bar(rects)
  ok(rect ~= nil, "with no panel the bar is drawn")
  eq(rect and rect.x, 80, "at its full left end")
  eq(rect and rect.w, 67, "and its full length")
  eq(#marked, 1, "marked once")
  eq(marked[1].x, 80, "over exactly what was drawn (x)")
  eq(marked[1].w, 67, "over exactly what was drawn (w)")
end

-- --------------------------------------------------- the classic panel is up

do
  local rects, marked = draw(stubBattle(false), CLASSIC_PANEL)
  local rect = bar(rects)
  ok(rect ~= nil, "the bar is still drawn -- the panel does not reach 147")
  eq(rect and rect.x, 112, "it starts at the panel's right edge, not at 80")
  eq(rect and rect.w, 35, "and carries only the part clear of it")
  eq(rect and rect.y, 89, "on its own rows, unmoved")

  eq(#marked, 1, "and marks once")
  eq(marked[1].x, 112, "over exactly what was drawn, never under the panel")
  eq(marked[1].w, 35, "in full")

  -- The whole point.  The skirt the DARK theme paints is one pixel around the
  -- mark, so a mark starting at 80 puts a dark row at y=88 from x=79 -- across
  -- the top of the PP line, which is printed at y=88 and starts at x=8.
  local m = marked[1]
  ok(m.x >= CLASSIC_PANEL.x + CLASSIC_PANEL.w,
     "no marked pixel lies under the panel, so nothing re-blits over the PP row")
  ok(m.y >= 89 and m.y + m.h <= 91,
     "and the mark is the bar's own two rows, so its skirt cannot reach 88")
end

-- --------------------------------------------------------- the mark follows

do
  -- A mark over ground the bar did not paint is the same bug pointed the other
  -- way: the re-blit takes whatever IS there, raw, and exempts it from the
  -- palette pass.  So the two rects are the same rect, always.
  for _, panel in ipairs({ CLASSIC_PANEL, WIDE_PANEL, false }) do
    local rects, marked = draw(stubBattle(false), panel or nil)
    local rect = bar(rects)
    if rect and #marked > 0 then
      eq(marked[1].x, rect.x, "the rect marked is the rect drawn (x)")
      eq(marked[1].w, rect.w, "the rect marked is the rect drawn (w)")
    end
  end
end

-- ------------------------------------------- a panel that does not lie on it

do
  -- The wide panel is at rows 104..144 and the bar is at 89..91: nothing to
  -- clip to, and clipping anyway would cut a bar nothing was covering.
  local rects = draw(stubBattle(false), WIDE_PANEL)
  eq(bar(rects).x, 80, "a panel clear of the bar's rows does not move it")
  eq(bar(rects).w, 67, "nor shorten it")
end

do
  -- The wide layout draws its own boxed bar at rows 88..104 and its panel is
  -- below that, so this path is untouched -- asserted so a later change to the
  -- clip cannot quietly reach it.
  local rects = draw(stubBattle(true), WIDE_PANEL)
  local fill
  for _, rect in ipairs(rects) do
    if rect.h == 2 then fill = rect end
  end
  ok(fill ~= nil, "the wide bar still fills")
  eq(fill and fill.x, 208, "at the wide bar's own x, unclipped")
end

-- ------------------------------------------------------- nothing to ask, ask

do
  local rects = draw(stubBattle(false), nil)
  eq(bar(rects).x, 80, "a build with no panelRect at all still draws the bar")

  local XP = makeXP({}, CHROME, function() error("boom", 0) end)
  drawn, marks = {}, {}
  local fine = pcall(XP.draw, stubBattle(false))
  ok(fine, "and a panelRect that raises does not take the bar down")
  eq(bar(drawn) and bar(drawn).x, 80, "it draws unclipped rather than not at all")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
