-- An item icon under a pop-up lets go of the box on top of it.
--
-- `PaletteFX.markTrueColor` splices its rectangle onto the pass's zone list
-- and RE-BLITS THAT REGION RAW once the pass is composed -- after everything
-- drawn over it in the meantime.  The bag goes on drawing its rows while a
-- menu is open on them (SORT, the item actions, the TM/HM list), so a marked
-- icon under that menu came back ON TOP of it: the icon punched through the
-- box, carrying the matte's dark cell with it.
--
-- Draw order cannot fix it. The re-blit happens after all of it.
--
-- So the mark goes, and the matte goes with it -- as a pair, and that pairing
-- is the point. A matte with no mark is a dark rectangle sitting in a page,
-- and the palette pass reads those pixels as the page's INK: a hole where the
-- icon was, which is the same bug pointing the other way. The party list
-- makes the same pairing for the same reason (Gen1Party 1.8.1).
--
-- Run:  luajit tests/bagcover_test.lua

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

-- ------------------------------------------------------------- the harness

local marks, fills = {}, {}
package.preload["src.render.PaletteFX"] = function()
  return { markTrueColor = function(x, y, w, h)
             marks[#marks + 1] = { x = x, y = y, w = w, h = h }
           end }
end

_G.love = { graphics = {
  setColor = function() end,
  draw = function() end,
  rectangle = function(_, x, y, w, h) fills[#fills + 1] = { x = x, y = y, w = w, h = h } end,
  newImage = function() return {} end,
} }

local function load_(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))
end

-- icons.lua is built by a factory; feed it a mod stand-in with a theme that
-- answers DARK, which is the only mode that mattes at all.
local factory = load_("modules/Gen1ModernBag/icons.lua")()
local C = factory({
  theme = function()
    return { read = function() return "dark" end,
             matte = function() return { 0, 0, 0 } end }
  end,
  read = function() return nil end,
  log = setmetatable({}, { __index = function() return function() end end }),
})

io.write("an icon under a pop-up drops its matte and its mark together\n")

-- The list that owns the icons, and a menu standing on it.  Menu.new keeps
-- tx/ty/tw/th; the box here is the right-hand pop-up the bag opens.
local list = { name = "the bag list" }
local menu = { tx = 8, ty = 4, tw = 12, th = 10 }
local game = { stack = { states = { list, menu } } }

-- ------------------------------------------------- what the pop-up covers
do
  local covers = C.coversOf(game, list)
  ok(type(covers) == "table" and #covers == 1,
     "the menu above the list is found, and only it")
  ok(C.covered(covers, 72, 40),
     "an icon inside the menu's box counts as covered")
  ok(not C.covered(covers, 8, 40),
     "and one in the left column, clear of it, does not")
end

-- ------------------------------------------------- the covered icon
do
  marks, fills = {}, {}
  C.draw({}, 72, 40, true)
  eq(#marks, 0, "a covered icon is not marked, so nothing re-blits over the box")
  eq(#fills, 0, "and not matted either -- the pair goes together")
end

-- ------------------------------------------------- and the one that is not
do
  marks, fills = {}, {}
  C.draw({}, 8, 40, false)
  eq(#marks, 1, "an uncovered icon is still marked, which is what keeps it "
    .. "full colour")
  ok(#fills > 0, "and still matted, so its cell is the page's colour")
end

-- --------------------------------------------- nothing standing on the list
do
  local alone = { stack = { states = { list } } }
  eq(C.coversOf(alone, list), nil, "with no pop-up open there is nothing to "
    .. "cover an icon")
  ok(not C.covered(nil, 72, 40), "and no icon reads as covered")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
