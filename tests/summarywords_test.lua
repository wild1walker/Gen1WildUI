-- The words on Gold's SUMMARY pages: black ink on the page, not white ink in
-- a black box.
--
-- Reported twice -- "the words on the color should just be black font instead
-- of in a black box with white words" and then "No box black font on blue
-- green pink".
--
-- ------- what the cart does
--
-- Every label and number on the lower half of a stats page is printed through
-- the PAGE's own palette:
--
--     self:drawPlacements(self:pinkPlacements(), self:lowerColors())
--
-- and `lowerColors` is `{ tint, tint, tint, black }` -- the page's own pink,
-- green or blue in colour 0 and black ink in colour 3.  `Chrome.printThrough`
-- fills a `width x 8` cell of colour 0 before its first glyph, so on the cart
-- that cell is the page colour and is invisible against the page behind it.
-- Black words on a coloured page.
--
-- ------- what the theme did to it
--
-- runtime/theme2.lua substitutes its own paper into colour 0 and its own ink
-- into colour 3 of any palette handed to `printThrough`, which is right for a
-- box and wrong for a coloured page: under DARK the cell went black and the
-- letters went white.
--
-- ------- and why 0.32.86 did not fix it
--
-- The theme already carries the opt-out this needs -- `gen1wildUnthemed`,
-- written for the battle HUD, "ink on a PHOTOGRAPH rather than ink in a box".
-- 0.32.86 stamped it on `SummaryMenu.PAGE_PALETTES`, which is the wrong table:
-- those three constants are read by `drawPageSquare` and nothing else, and
-- every word on the page travels in a table `lowerColors` BUILDS FRESH on each
-- call.  A constant marked once cannot reach a table that does not exist yet,
-- so the mark never applied to a single word.
--
-- Which is why this file drives the real chain -- the real `SummaryMenu`, the
-- real theme wrap, the real `printThrough` seam -- and asserts the colours that
-- come out the far end, rather than asserting that a line of code is present.
-- The section it replaces did the latter, and passed while every label on the
-- page was still a white-on-black box.
--
-- Run:  luajit tests/summarywords_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then passed = passed + 1
  else failed = failed + 1; io.write("  FAIL  ", description, "\n") end
end
local function eq(actual, expected, description)
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    for _, name in ipairs({ "gen1recompog", "gen1recomp", "bryanthaboi/gen1recomp" }) do
      candidates[#candidates + 1] = prefix .. "/" .. name
    end
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/SummaryMenu.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("summarywords: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local t = handle:read("*a") handle:close() return t
end

-- ---- the seam, read off the cart

local sumSrc = assert(slurp(ENGINE .. "/src/ui/gen2/SummaryMenu.lua"))
ok(sumSrc:find("self:drawPlacements(self:pinkPlacements(), self:lowerColors())",
               1, true) ~= nil,
   "the pink page prints its words through lowerColors()")
ok(sumSrc:find("self:drawPlacements(self:greenPlacements(), self:lowerColors())",
               1, true) ~= nil,
   "and so does the green")
ok(sumSrc:find("self:drawPlacements(self:bluePlacements(), self:lowerColors())",
               1, true) ~= nil,
   "and the blue")
ok(sumSrc:find("return { tint, tint, tint, { 0, 0, 0 } }", 1, true) ~= nil,
   "lowerColors BUILDS a table -- the page tint as paper, black as ink")
ok(sumSrc:find("SummaryMenu.PAGE_PALETTES = PAGE_PALETTES", 1, true) ~= nil,
   "PAGE_PALETTES is published, which is the table 0.32.86 marked")
do
  -- The whole reason marking that one did nothing: it is read in one place,
  -- and that place is not where any word goes.
  local users = 0
  for _ in sumSrc:gmatch("PAGE_PALETTES%[") do users = users + 1 end
  eq(users, 1, "PAGE_PALETTES is indexed exactly once in the whole file")
  ok(sumSrc:find("self:drawPageSquare(tx, 5, i == self.page, PAGE_PALETTES[i])",
                 1, true) ~= nil,
     "...by drawPageSquare, the three swatches over the page arrows -- so a "
     .. "mark on it could never reach a label")
end

-- ---------------------------------------------------------------- harness

local noop = function() end
local function anytbl() return setmetatable({}, { __index = function() return noop end }) end
love = { graphics = setmetatable({ newQuad = function() return {} end },
    { __index = function() return noop end }),
  audio = anytbl(), filesystem = anytbl(), window = anytbl(),
  timer = { getTime = function() return 0 end } }

-- Gold's Chrome, with the one field the theme rewrites and the one call the
-- words travel through.  `seen` is the palette the base print RECEIVES, which
-- is the whole question: what colour does the cell behind a label end up.
local seen
local Chrome = {
  DEFAULT_BOX_PALETTE = {
    { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
  },
  printThrough = function(_text, _tx, _ty, palette) seen = palette end,
  printRightThrough = function(_text, _tx, _ty, palette) seen = palette end,
  cursorThrough = function(_tx, _ty, palette) seen = palette end,
  print = noop, SCREEN_W = 20,
}
package.loaded["src.ui.gen2.Chrome"] = Chrome

local SummaryMenu = require("src.ui.gen2.SummaryMenu")

local mod = {
  id = "gen1_wild_ui",
  log = { info = noop, warn = noop, error = noop },
  options = { get = function() return nil end },
  hooks = { wrapped = {}, wrap = function(h, name, fn) h.wrapped[name] = fn end },
}
local optionset = {
  generation = function() return 1 end,
  read = function() return nil end,
  write = function() return true end,
  own = noop,
}

local Theme2 = assert(load(assert(slurp("runtime/theme2.lua")), "@theme2.lua"))()
local theme = Theme2.new({ mod = mod, optionset = optionset })
ok(pcall(theme.install), "the theme installs over Gold's Chrome")
ok(Chrome.printThrough ~= nil, "and printThrough is still there")

local Cutout2 = assert(load(assert(slurp("runtime/cutout2.lua")), "@cutout2.lua"))()
local cut = Cutout2.new({ mod = mod })
ok(pcall(cut.install), "and the page arm installs over the SUMMARY")

-- DARK, written into the very table the theme themes.  `live` IS
-- Chrome.DEFAULT_BOX_PALETTE, so this is the theme being ON, not a mock of it.
local function setDark()
  Chrome.DEFAULT_BOX_PALETTE[1] = { 0, 0, 0 }
  Chrome.DEFAULT_BOX_PALETTE[2] = { 0, 0, 0 }
  Chrome.DEFAULT_BOX_PALETTE[3] = { 255, 255, 255 }
  Chrome.DEFAULT_BOX_PALETTE[4] = { 255, 255, 255 }
end
local function rgb(c)
  if type(c) ~= "table" then return tostring(c) end
  return ("%d,%d,%d"):format(c[1], c[2], c[3])
end

-- ---- the control: the theme really is on

do
  setDark()
  seen = nil
  Chrome.printThrough("SAVE", 1, 1, { { 255, 255, 255 }, { 255, 255, 255 },
                                      { 255, 255, 255 }, { 0, 0, 0 } })
  ok(seen ~= nil, "an ordinary box palette reaches the print")
  eq(rgb(seen[1]), "0,0,0",
     "and DARK puts its paper in colour 0 -- so the substitution is LIVE, and "
     .. "the page assertions below are not passing because nothing happened")
  eq(rgb(seen[4]), "255,255,255", "and its ink in colour 3")
end

-- ---- the three pages

local PAGES = {
  { page = 1, name = "pink",  tint = "255,156,255" },
  { page = 2, name = "green", tint = "173,255,115" },
  { page = 3, name = "blue",  tint = "140,255,255" },
}

for _, entry in ipairs(PAGES) do
  setDark()
  local screen = setmetatable({ page = entry.page }, SummaryMenu)
  local colors = screen:lowerColors()
  eq(rgb(colors[1]), entry.tint,
     ("the %s page's own colour is what lowerColors calls paper"):format(entry.name))

  seen = nil
  Chrome.printThrough("ATTACK", 1, 9, colors)
  ok(seen ~= nil, ("a %s-page label reaches the print"):format(entry.name))
  eq(rgb(seen[1]), entry.tint,
     ("the cell behind it stays the %s page's colour -- no box"):format(entry.name))
  eq(rgb(seen[4]), "0,0,0",
     ("and the letters stay BLACK on the %s page"):format(entry.name))

  -- The right-aligned numbers -- the stat values, the PP counts, EXP -- go
  -- through the other call, and it is wrapped too.
  seen = nil
  Chrome.printRightThrough("15", 18, 10, screen:lowerColors())
  eq(rgb(seen[1]), entry.tint, "the numbers keep the page colour too")
  eq(rgb(seen[4]), "0,0,0", "...and their black ink")
end

-- ---- and the page above the divider is left alone

do
  setDark()
  seen = nil
  Chrome.printThrough("CHIKORITA", 1, 1, { { 255, 255, 255 }, { 255, 255, 255 },
                                           { 255, 255, 255 }, { 0, 0, 0 } })
  eq(rgb(seen[1]), "0,0,0",
     "the upper half is an ordinary themed page and stays that way -- the "
     .. "name and level are white on black, as they were")
end

-- ---- LIGHT changes nothing on the pages, because nothing was changed for it

do
  Chrome.DEFAULT_BOX_PALETTE[1] = { 255, 255, 255 }
  Chrome.DEFAULT_BOX_PALETTE[2] = { 255, 255, 255 }
  Chrome.DEFAULT_BOX_PALETTE[3] = { 255, 255, 255 }
  Chrome.DEFAULT_BOX_PALETTE[4] = { 0, 0, 0 }
  local screen = setmetatable({ page = 2 }, SummaryMenu)
  seen = nil
  Chrome.printThrough("MOVE", 1, 9, screen:lowerColors())
  eq(rgb(seen[1]), "173,255,115", "under LIGHT the green page is still green")
  eq(rgb(seen[4]), "0,0,0", "and still black-lettered")
end

-- ---- the mark is on the table the words travel in

do
  local screen = setmetatable({ page = 1 }, SummaryMenu)
  local a = screen:lowerColors()
  local b = screen:lowerColors()
  ok(a ~= b, "lowerColors hands back a NEW table each call")
  eq(a.gen1wildUnthemed, true, "and each one carries the opt-out")
  eq(b.gen1wildUnthemed, true, "...every time, not just the first")

  local themeSrc = assert(slurp("runtime/theme2.lua"))
  ok(themeSrc:find('local marked = "gen1wildUnthemed"', 1, true) ~= nil,
     "which is the mark the theme actually reads")
  ok(themeSrc:find("if palette == live or palette[marked] then return palette end",
                   1, true) ~= nil,
     "and a marked palette is handed back untouched")
end

io.write(("summarywords: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
