-- Free placement in Gold's box, and the hole the party keeps until you close it.
--
-- Reported as "In the box I can't have empty spots and free place them like I
-- should be able to", "my party isn't doing the keep hole behavior until
-- closed like Gen 1", and -- the same defect seen from the other side --
-- "Box is still doing the wrong animation".
--
-- ------- why a compact array is not a grid
--
-- Gold stores a box the way Red does: `save.boxes[i]` is a plain array,
-- `#` is the count, and the cart's own deposit appends.  That array cannot
-- express a GAP.  This screen used to say the array WAS the grid -- cells
-- 1..count full, the rest empty -- so putting a POKeMON down in cell 12 of an
-- empty box appended it to the list and it appeared in cell 1.
--
-- The Gen 1 screen solved this years ago by keeping the ARRANGEMENT beside the
-- box in the mod's own save data, reconciled on every read
-- (modules/Gen1BillsBox/screen.lua, "where in the grid each POKeMON sits").
-- The save format is untouched; what is added is one cell number per POKeMON.
-- This file drives the Gold port of that, and the party's screen-local
-- counterpart, against the real `src/core/gen2/Boxes` and `src/core/gen2/Mail`.
--
-- ------- and why it was also the animation
--
-- The carried POKeMON used to be drawn as a SECOND PASS on top of the grid,
-- while the grid was still drawing whatever the cursor's cell held underneath:
-- two icons in one cell, one blinking through the other.  It is now drawn BY
-- the grid, in place of the cell's occupant, which is what Gen 1 does -- so
-- the assertions about placement and the assertions about drawing are the same
-- fix seen twice.
--
-- Run:  luajit tests/boxfree_gen2_test.lua

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
      local probe = io.open(dir .. "/src/core/gen2/Boxes.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("boxfree: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local t = handle:read("*a") handle:close() return t
end

-- ---- the save format, read off the cart

local boxSrc = assert(slurp(ENGINE .. "/src/core/gen2/Boxes.lua"))
ok(boxSrc:find("save.boxes[index] = save.boxes[index] or {}", 1, true) ~= nil,
   "a Gold box IS a plain array on the save")
ok(boxSrc:find("return #Boxes.box(save, index)", 1, true) ~= nil,
   "...counted with `#`, so it cannot hold a gap -- which is the whole reason "
   .. "the arrangement is kept beside it")

local mailSrc = assert(slurp(ENGINE .. "/src/core/gen2/Mail.lua"))
ok(mailSrc:find("function Mail.removeSlot(save, slot)", 1, true) ~= nil,
   "the cart shifts sPartyMail UP when a party member leaves")
ok(mailSrc:find("function Mail.insertSlot", 1, true) == nil,
   "...and has no insert counterpart, because nothing in the cart ever "
   .. "inserts into the middle of a party -- this screen does, so it "
   .. "carries the inverse itself")

-- ---------------------------------------------------------------- harness

local noop = function() end
local function anytbl() return setmetatable({}, { __index = function() return noop end }) end
love = { graphics = setmetatable({ newQuad = function() return {} end },
    { __index = function() return noop end }),
  audio = anytbl(), filesystem = anytbl(), window = anytbl(),
  timer = { getTime = function() return 0 end } }

local PartyMenu = require("src.ui.gen2.PartyMenu")
local Mail = require("src.core.gen2.Mail")

-- The colour-icon runtime, because the "only the hovered one walks" rule lives
-- there and the box is the screen that has to say WHICH one is hovered.
local Icons2 = assert(load(assert(slurp("runtime/icons2.lua")),
  "@icons2.lua"))()

local bucket = {}
local mod = {
  path = "modules/Gen1BillsBox",
  log = { warn = noop, info = noop, error = noop },
  options = { get = function() return nil end },
  save = {
    get = function(_, key, default)
      local v = bucket[key]
      if v == nil then return default end
      return v
    end,
    set = function(_, key, value) bucket[key] = value end,
  },
  content = { screens = anytbl() },
  hooks = anytbl(),
}
ok(pcall(Icons2.install, { mod = mod }), "the colour-icon runtime installs")

local Screen = assert(load(assert(slurp("modules/Gen1BillsBox/gen2screen.lua")),
  "@gen2screen.lua"))()(mod)
ok(type(Screen.new) == "function", "the Gold box screen builds")

local function mon(name) return
  { species = "PIDGEY", nickname = name, level = 5, hp = 10, maxHp = 10 } end

local function newScreen(boxNames, partyNames)
  bucket.cells2 = nil
  local box = {}
  for i, n in ipairs(boxNames or {}) do box[i] = mon(n) end
  local party = {}
  for i, n in ipairs(partyNames or {}) do party[i] = mon(n) end
  local save = { currentBox = 1, party = party, boxes = { box } }
  local game = { save = save, data = {},
                 input = { wasPressed = function() return false end } }
  local screen = Screen.new(game, { save = save })
  return screen, save
end

local function gridOf(screen)
  local cells = screen:boxCells(screen.boxIndex)
  local out = {}
  for c = 1, 20 do out[c] = cells[c] and cells[c].nickname or "-" end
  return table.concat(out, " ")
end
local function rowsOf(screen)
  local cells = screen:partyCells()
  local out = {}
  for r = 1, 6 do out[r] = cells[r] and cells[r].nickname or "-" end
  return table.concat(out, " ")
end
local function listOf(t)
  local out = {}
  for i = 1, #t do out[i] = t[i].nickname end
  return table.concat(out, ",")
end

-- ------------------------------------------------------------ free placement

do
  local screen, save = newScreen({ "A", "B", "C", "D" })
  eq(gridOf(screen), "A B C D - - - - - - - - - - - - - - - -",
     "a box with no arrangement yet reads as the compact one")

  screen.pane, screen.boxSlot = "box", 2
  screen:grab()
  eq(screen.held and screen.held.mon.nickname, "B", "B is lifted out")
  eq(gridOf(screen), "A - C D - - - - - - - - - - - - - - - -",
     "the cell it left is EMPTY -- the rest do not slide up behind it")
  eq(#save.boxes[1], 3, "and the cart's own list is one shorter")

  screen.boxSlot = 12
  screen:place()
  eq(gridOf(screen), "A - C D - - - - - - - B - - - - - - - -",
     "it lands in the cell you aimed at, not at the end of the list")
  eq(screen.held, nil, "and it is out of your hand")
  eq(#save.boxes[1], 4, "the cart's list is whole again")
  ok(listOf(save.boxes[1]):find("B") ~= nil,
     "...and still holds B -- the save format is untouched")
end

-- The gap survives the screen, because a gap in storage is a decision.
do
  local screen, save = newScreen({ "A", "B", "C" })
  screen.pane, screen.boxSlot = "box", 2
  screen:grab()
  screen.boxSlot = 20
  screen:place()
  local layout = gridOf(screen)
  screen:close()

  local game = { save = save, data = {},
                 input = { wasPressed = function() return false end } }
  local again = Screen.new(game, { save = save })
  eq(gridOf(again), layout, "the arrangement is still there when it reopens")
  eq(gridOf(again), "A - C - - - - - - - - - - - - - - - - B",
     "...cell 20 and all")
end

-- Reconciled against anything that touched the box behind this screen's back.
do
  local screen, save = newScreen({ "A", "B", "C" })
  screen.pane, screen.boxSlot = "box", 2
  screen:grab()
  screen.boxSlot = 10
  screen:place()
  eq(gridOf(screen), "A - C - - - - - - B - - - - - - - - - -", "a gap at 2")

  -- A catch overflows into the box while nobody is looking.
  save.boxes[1][#save.boxes[1] + 1] = mon("X")
  eq(gridOf(screen), "A X C - - - - - - B - - - - - - - - - -",
     "an extra POKeMON takes the lowest free cell rather than being lost")

  -- And something takes two away.
  table.remove(save.boxes[1])
  table.remove(save.boxes[1])
  local shown = 0
  for _, cell in pairs(screen:boxCells(screen.boxIndex)) do
    if cell then shown = shown + 1 end
  end
  eq(shown, #save.boxes[1],
     "the grid never shows more POKeMON than the box holds")
end

-- A cell claimed twice, or off the grid, is thrown away rather than trusted.
do
  local screen = newScreen({ "A", "B", "C" })
  bucket.cells2 = { ["1"] = { 5, 5, 99 } }
  local shown = 0
  for _, cell in pairs(screen:boxCells(1)) do if cell then shown = shown + 1 end end
  eq(shown, 3, "three POKeMON are still all reachable")
  local cells = bucket.cells2["1"]
  eq(#cells, 3, "the arrangement is repaired to one entry per POKeMON")
  ok(cells[1] == 5 and cells[2] ~= 5 and cells[3] ~= 5,
     "the first claim on cell 5 keeps it; the duplicate and the out-of-range "
     .. "cell are replaced with free ones")
end

-- A swap exchanges two PLACES, rather than appending one of them.
do
  local screen = newScreen({ "A", "B", "C" })
  screen.pane, screen.boxSlot = "box", 1
  screen:grab()
  screen.boxSlot = 3
  screen:place()
  eq(gridOf(screen), "C B A - - - - - - - - - - - - - - - - -",
     "A and C trade cells")
end

-- ---------------------------------------------------------------- the party

do
  local screen, save = newScreen({}, { "P1", "P2", "P3" })
  screen.pane, screen.partySlot = "party", 2
  screen:grab()
  eq(rowsOf(screen), "P1 - P3 - - -", "the row it left is empty")
  eq(listOf(save.party), "P1,P3", "and save.party is never sparse")

  screen.partySlot = 5
  screen:place()
  eq(rowsOf(screen), "P1 - P3 - P2 -",
     "the hole stays while you are looking at it")
  eq(listOf(save.party), "P1,P3,P2",
     "and the array is kept SORTED BY ROW -- party order is battle order, so "
     .. "the list and the screen can never disagree about who leads")
  eq(#save.party, 3, "nothing was added or lost")

  -- Closing is the collapse: there is nothing to collapse.
  screen:close()
  eq(listOf(save.party), "P1,P3,P2",
     "closing changes nothing, because the array was already the list it "
     .. "looked like")
  eq(#save.party, 3, "still three")
end

-- The letters move with the POKeMON.
do
  local screen, save = newScreen({}, { "P1", "P2", "P3" })
  local letters = Mail.state(save).party
  letters[1] = { author = "one" }
  letters[3] = { author = "three" }

  screen.pane, screen.partySlot = "party", 2
  screen:grab()
  screen.partySlot = 6
  screen:place()
  eq(listOf(save.party), "P1,P3,P2", "P2 is last in the array now")
  local at = {}
  for i = 1, #save.party do at[save.party[i].nickname] = Mail.state(save).party[i] end
  eq(at.P1 and at.P1.author, "one", "P1 still holds its own letter")
  eq(at.P3 and at.P3.author, "three",
     "and so does P3, which changed party index when P2 moved past it")
end

-- ---------------------------------------------------------------- drawing

do
  local screen, save = newScreen({ "A", "B", "C", "D" })
  screen.icons = screen.icons or nil
  ok(screen.icons ~= nil, "the screen borrows a PartyMenu as its icon renderer")

  -- Record every icon draw and the frame it asked for.
  local drawn
  local IMG = { getDimensions = function() return 16, 32 end }
  PartyMenu.iconIdFor = function() return "ICON_X" end
  screen.icons.icons = { icons = { ICON_X = { image = "p.png" } } }
  package.loaded["src.render.Assets"].image = function() return IMG end
  require("src.pokemon.Sprites").iconPath = function(_, _, p) return p or "p.png" end
  local realDraw = PartyMenu.drawIcon
  PartyMenu.drawIcon = function(menu, m, px, py, ...)
    local _, frame = menu:iconFor(m)
    drawn[#drawn + 1] = { nick = m and m.nickname, frame = frame,
                          animate = menu.gen1wildAnimate }
    return realDraw(menu, m, px, py, ...)
  end

  local function paint()
    drawn = {}
    screen:drawGrid()
    return drawn
  end

  screen.pane, screen.boxSlot = "box", 2
  screen.ticks = 8            -- clock 16: an animating icon is on frame 1
  screen.icons.clock = screen.ticks * 2
  local frames = paint()
  eq(#frames, 4, "four POKeMON, four icons")
  for _, entry in ipairs(frames) do
    if entry.nick == "B" then
      eq(entry.animate, true, "the icon under the cursor walks")
      eq(entry.frame, 1, "...on the frame the clock is up to")
    else
      eq(entry.animate, false, ("%s stands still"):format(entry.nick))
      eq(entry.frame, 0, ("...on frame 0, the pose the cart rests on"):format())
    end
  end

  -- Now pick one up and stand it over an occupied cell.
  screen.boxSlot = 2
  screen:grab()
  screen.boxSlot = 4
  frames = paint()
  local names = {}
  for _, entry in ipairs(frames) do names[entry.nick] = entry end
  eq(#frames, 3, "three icons, not four: the carried POKeMON REPLACES the "
     .. "one in the cell it is over, rather than being drawn on top of it")
  eq(names.B ~= nil, true, "the carried POKeMON is the one drawn there")
  eq(names.D, nil, "and the cell's own occupant is hidden under it")
  eq(names.B and names.B.animate, true,
     "a POKeMON in your hand keeps walking")

  -- The flash is a skipped draw, not a second icon.
  screen.ticks = 20           -- past FLASH_ON, the dark half of the cycle
  screen.icons.clock = screen.ticks * 2
  frames = paint()
  eq(#frames, 2, "on the dark half of the flash it is simply not drawn")
  local stillThere = false
  for _, entry in ipairs(frames) do
    if entry.nick == "B" then stillThere = true end
  end
  eq(stillThere, false, "...and nothing else is drawn in its place")

  PartyMenu.drawIcon = realDraw
end

-- The screen no longer carries a second drawing pass for the held POKeMON.
do
  local src = assert(slurp("modules/Gen1BillsBox/gen2screen.lua"))
  ok(src:find("function Screen:drawHeld", 1, true) == nil,
     "drawHeld is gone -- the grid draws the carried POKeMON itself")
  ok(src:find("function Screen:monDrawnAt", 1, true) ~= nil,
     "...through monDrawnAt, the way the Gen 1 screen does")
  local gen1 = assert(slurp("modules/Gen1BillsBox/screen.lua"))
  ok(gen1:find("function Screen:monDrawnAt", 1, true) ~= nil,
     "which is the same name it has there, because it is the same rule")
end

-- ---------------------------------------------------------------- sorting

do
  local screen, save = newScreen({ "C", "A", "B" })
  screen.pane, screen.boxSlot = "box", 2
  screen:grab()
  screen.boxSlot = 15
  screen:place()
  eq(gridOf(screen), "C - B - - - - - - - - - - - A - - - - -",
     "a box with a gap in it")

  screen:sortBox("name")
  eq(gridOf(screen), "A B C - - - - - - - - - - - - - - - - -",
     "a sort closes the box up into cells 1..n")
  eq(listOf(save.boxes[1]), "A,B,C", "and the cart's list is in that order")

  ok(screen:canUndoSort(), "the sort can be undone")
  screen:undoSort()
  eq(gridOf(screen), "C - B - - - - - - - - - - - A - - - - -",
     "UNDO puts the gaps back, not just the order")
end

-- Releasing takes the right entry out of the arrangement.
do
  local screen, save = newScreen({ "A", "B", "C", "D" })
  screen.pane, screen.boxSlot = "box", 1
  screen:grab()
  screen.boxSlot = 10
  screen:place()
  eq(gridOf(screen), "- B C D - - - - - A - - - - - - - - - -", "A sits at 10")

  screen.boxSlot = 2
  screen:doRelease()
  eq(gridOf(screen), "- - C D - - - - - A - - - - - - - - - -",
     "B is gone and NOBODY else moved -- the arrangement lost B's entry, not "
     .. "its last one")
  eq(listOf(save.boxes[1]), "C,D,A", "and the cart's list lost B")
end

io.write(("boxfree: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
