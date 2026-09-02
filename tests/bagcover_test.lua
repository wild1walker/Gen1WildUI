-- An item icon lets go of the part of itself a pop-up is standing on.
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
-- WHAT LETS GO IS THE COVERED PART, not the cell.  1.13.0 dropped the pair
-- for the whole 16x16 the moment a box touched any of it, and these boxes are
-- anchored to the right edge and open at whatever width their longest row
-- needs -- so one that reaches into the icon column usually stops part-way
-- across it.  The strip still showing then had no mark on it and was read
-- through the page's four shades: reported as the items going greyscale as
-- soon as a pop-up opened.
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

local quads = {}
local draws = {}
_G.love = { graphics = {
  setColor = function() end,
  draw = function(_, a, b, c)
    -- draw(image, x, y) or draw(image, quad, x, y)
    if type(a) == "table" and a.quad then
      draws[#draws + 1] = { x = b, y = c, w = a.w }
    else
      draws[#draws + 1] = { x = a, y = b, w = 16 }
    end
  end,
  rectangle = function(_, x, y, w, h) fills[#fills + 1] = { x = x, y = y, w = w, h = h } end,
  newImage = function() return {} end,
  newQuad = function(_, _, w, h)
    local q = { quad = true, w = w, h = h }
    quads[#quads + 1] = q
    return q
  end,
} }

-- images answer getDimensions, which is what the sliver needs
local function image() return { getDimensions = function() return 16, 16 end } end

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

io.write("an icon lets go of exactly the part a pop-up stands on\n")

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

-- ------------------------------------------------- how much of a cell shows
do
  local covers = C.coversOf(game, list)
  eq(C.visible(covers, 8, 40), 16, "a cell clear of the box shows all of itself")
  eq(C.visible(covers, 72, 40), 0, "one the box opens on top of shows none")
  eq(C.visible(covers, 56, 40), 8,
     "and one the box's left edge lands in the middle of shows the half "
     .. "beside it")
  eq(C.visible(covers, 56, 8), 16,
     "a cell beside the box but above it is not covered at all")
  eq(C.visible(nil, 56, 40), 16, "and with no pop-up open, every cell is whole")
end

-- ------------------------------------------------- the covered icon
do
  marks, fills, draws = {}, {}, {}
  C.draw(image(), 72, 40, C.coversOf(game, list))
  eq(#marks, 0, "an icon the box stands on is not marked, so nothing re-blits "
    .. "over the box")
  eq(#fills, 0, "and not matted either -- the pair goes together")
  eq(#draws, 0, "and not drawn: there is no pixel of it to draw")
end

-- --------------------------------------------- the one the box HALF covers
do
  -- The case 1.13.0 got wrong. The strip beside the box is still on the page
  -- and still has to be marked, or it is an icon read through four greys --
  -- which is what "the items all turn greyscale when I open the pop-up" was.
  marks, fills, draws = {}, {}, {}
  C.draw(image(), 56, 40, C.coversOf(game, list))
  eq(#marks, 1, "the strip beside the box is marked, so it keeps its colours")
  eq(marks[1] and marks[1].w, 8, "and the mark stops where the box starts")
  eq(marks[1] and marks[1].h, 16, "the full height of the row, which the box "
    .. "does not clip")
  eq(#fills, 1, "the matte is laid under exactly that strip")
  eq(fills[1] and fills[1].w, 8, "and no wider, or it is ink under the box")
  eq(#draws, 1, "and the icon is drawn once")
  eq(draws[1] and draws[1].w, 8, "as the slab that shows, not the whole cell")
end

-- ------------------------------------------------- and the one that is not
do
  marks, fills, draws = {}, {}, {}
  C.draw(image(), 8, 40, C.coversOf(game, list))
  eq(#marks, 1, "an uncovered icon is still marked, which is what keeps it "
    .. "full colour")
  eq(marks[1] and marks[1].w, 16, "over the whole cell")
  ok(#fills > 0, "and still matted, so its cell is the page's colour")
  eq(draws[1] and draws[1].w, 16, "and drawn whole, with no quad to cut it")
end

-- --------------------------------------------- nothing standing on the list
do
  local alone = { stack = { states = { list } } }
  eq(C.coversOf(alone, list), nil, "with no pop-up open there is nothing to "
    .. "cover an icon")
  ok(not C.covered(nil, 72, 40), "and no icon reads as covered")

  marks, fills, draws = {}, {}, {}
  C.draw(image(), 72, 40, nil)
  eq(#marks, 1, "so the icon there is marked like any other")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
