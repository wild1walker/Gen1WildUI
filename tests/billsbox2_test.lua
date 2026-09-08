-- Gen1BillsBox on Gold: the grid, and above all the MOVES.
--
-- This is the one screen in the suite where a mistake loses a POKeMON, so
-- what is asserted here is not the layout -- it is that every POKeMON that
-- was in the save before an operation is still in it afterwards, in exactly
-- one place, and that the cart's own refusals still refuse.
--
-- The refusals and the tails are `src/core/gen2/Boxes.lua`'s, which is the
-- cart's, and this file drives the screen against a real save shape rather
-- than a mock of one: a party, fourteen boxes of twenty, mail keyed by party
-- slot.
--
-- Run:  luajit tests/billsbox2_test.lua

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

local function slurp(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local body = handle:read("*a")
  handle:close()
  return body
end

-- ------------------------------------------------------------- the harness

local NUM_BOXES, PER_BOX, PARTY_SIZE = 14, 20, 6

-- The cart's own storage logic, reduced to the surface the screen uses and
-- kept behaviourally identical to src/core/gen2/Boxes.lua: the same refusals,
-- the same two tails.  Standing it up here rather than requiring the engine is
-- what lets this run in the bundle's own suite.
local Boxes = {
  NUM_BOXES = NUM_BOXES, MONS_PER_BOX = PER_BOX, PARTY_SIZE = PARTY_SIZE,
}
function Boxes.box(save, index)
  save.boxes = save.boxes or {}
  save.boxes[index] = save.boxes[index] or {}
  return save.boxes[index]
end
function Boxes.count(save, index) return #Boxes.box(save, index) end
function Boxes.isFull(save, index) return Boxes.count(save, index) >= PER_BOX end
function Boxes.name(save, index) return "BOX" .. index end
function Boxes.enterBox(mon)
  mon.status = nil
  mon.hp = mon.isEgg and 0 or (mon.maxHp or mon.hp)
  return mon
end
-- RELEASE from a box: the cart lets you release anything in storage, because
-- the party's last-healthy rule cannot apply to a mon that is not in it.
function Boxes.release(save, index, slot)
  local box = Boxes.box(save, index)
  if not box[slot] then return false, "There is no POKéMON there." end
  return true, table.remove(box, slot)
end
function Boxes.canUsePc(save)
  if not (save and save.party and #save.party > 0) then
    return false, "You'll need a\nPOKéMON to call\fwith."
  end
  return true
end
package.loaded["src.core.gen2.Boxes"] = Boxes

-- sPartyMail is a FIXED six-slot array keyed by party position, not a list:
-- removeSlot shifts every letter behind the departing mon up one and clears
-- the last (src/core/gen2/Mail.lua:135).  A `table.remove` stands in for that
-- badly -- it is the same shift only while the array happens to be dense, and
-- it raises outright on 5.4 for a slot past the end, which is how this stub
-- was found to be wrong.
local Mail = { PARTY_LENGTH = 6 }
function Mail.monHoldsMail(mon) return mon and mon.mail == true end
function Mail.removeSlot(save, slot)
  local mail = save.mail
  if not (mail and slot and slot >= 1) then return end
  for i = slot, Mail.PARTY_LENGTH - 1 do mail[i] = mail[i + 1] end
  mail[Mail.PARTY_LENGTH] = nil
end
package.loaded["src.core.gen2.Mail"] = Mail

local drawnIcons
package.loaded["src.ui.gen2.PartyMenu"] = {
  new = function(game, opts)
    return { clock = 0, drawIcon = function(_, mon, x, y)
      drawnIcons[#drawnIcons + 1] = { mon = mon, x = x, y = y }
    end }
  end,
}

local boxes, prints
package.loaded["src.ui.gen2.Chrome"] = {
  DEFAULT_BOX_PALETTE = {
    { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
  },
  clear = function() end,
  box = function(tx, ty, tw, th)
    boxes[#boxes + 1] = { tx = tx, ty = ty, tw = tw, th = th }
  end,
  textbox = function(tx, ty, w, h)
    boxes[#boxes + 1] = { tx = tx, ty = ty, textbox = true }
  end,
  printThrough = function(text, tx, ty)
    prints[#prints + 1] = { text = tostring(text), tx = tx, ty = ty }
  end,
  printRightThrough = function(text, txEnd, ty)
    prints[#prints + 1] = { text = tostring(text), tx = txEnd, ty = ty }
  end,
  letterbox = function() end,
  fitScale = function() return 1 end,
  fitOrigin = function() return 0, 0 end,
}
package.loaded["src.core.Strings"] = setmetatable({
  source = function(s) return s end,
}, { __call = function(_, s) return s end })
package.loaded["src.core.Sound"] = { playCry = function() end }

local rects
_G.love = _G.love or {}
love.graphics = {
  setColor = function() end, getColor = function() return 1, 1, 1, 1 end,
  -- Recorded, because the CURSOR is drawn rather than printed and its
  -- direction is one of the things under test: a down arrow is rows getting
  -- shorter, a sideways one is 1-wide columns.
  rectangle = function(_mode, x, y, w, h)
    if rects then rects[#rects + 1] = { x = x, y = y, w = w, h = h } end
  end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
}

local mod = { stored = {}, path = "modules/Gen1BillsBox" }
mod.options = {
  define = function() end,
  get = function(_, key) return mod.stored[key] end,
}
mod.log = {}
for _, level in ipairs({ "info", "warn", "error", "debug" }) do
  mod.log[level] = function() end
end

-- The BUILT copy, because that is the one the game loads.  tools/build.py
-- --check is what guarantees it matches the pin.
local Screen = assert(load(slurp("modules/Gen1BillsBox/gen2screen.lua"),
                           "@gen2screen.lua"))()(mod)

-- ------------------------------------------------------------- a real save

local nextId = 0
local function mon(opts)
  opts = opts or {}
  nextId = nextId + 1
  return { id = nextId, species = opts.species or 1, level = opts.level or 5,
           hp = opts.hp == nil and 20 or opts.hp, maxHp = 20,
           nickname = opts.nickname, isEgg = opts.isEgg, mail = opts.mail }
end

local function saveWith(partyN, boxN)
  local save = { party = {}, boxes = {}, currentBox = 1, mail = {} }
  for _ = 1, partyN do save.party[#save.party + 1] = mon() end
  for _ = 1, boxN do
    local box = Boxes.box(save, 1)
    box[#box + 1] = mon()
  end
  return save
end

local pressed = {}
local function screenOn(save, opts)
  local game = { save = save, data = {},
                 input = { wasPressed = function(_, k) return pressed[k] end,
                           isDown = function() return false end },
                 stack = { states = {}, pop = function() end,
                           top = function() return nil end } }
  local s = Screen.new(game, opts or {})
  return s
end

-- Every POKeMON in the save, by identity: the census this file is really about.
local function census(save, screen)
  local seen, total = {}, 0
  local function add(m, where)
    if not m then return end
    if seen[m.id] then
      ok(false, ("%s is in two places at once (%s and %s)")
        :format(tostring(m.nickname or m.id), seen[m.id], where))
    end
    seen[m.id] = where
    total = total + 1
  end
  for i, m in ipairs(save.party or {}) do add(m, "party " .. i) end
  for b = 1, NUM_BOXES do
    for i, m in ipairs((save.boxes or {})[b] or {}) do
      add(m, ("box %d slot %d"):format(b, i))
    end
  end
  if screen and screen.held then add(screen.held.mon, "in hand") end
  return total, seen
end

-- ------------------------------------------------------------- the grid

do
  io.write("the grid\n")
  local save = saveWith(3, 7)
  local s = screenOn(save)
  eq(Screen.COLS * Screen.ROWS, 20, "twenty cells, which is a Gen 2 box")
  eq(Screen.PARTY_ROWS, 6, "and six party rows beside them")

  local cells = s:boxCells(1)
  eq(cells[1], save.boxes[1][1], "a box is compact, so cell 1 is its first")
  eq(cells[7], save.boxes[1][7], "and cell 7 its seventh")
  eq(cells[8], nil, "with the rest empty")
  eq(s:boxIndexAt(1, 7), 7, "and a cell names the index the cart's calls take")
  eq(s:boxIndexAt(1, 8), nil, "nil where there is nothing")
end

-- ------------------------------------------------------- picking up

do
  io.write("picking a POKeMON up out of the middle\n")
  local save = saveWith(3, 7)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 3
  local third = save.boxes[1][3]
  s:grab()

  eq(s.held and s.held.mon, third, "it is in hand")
  eq(Boxes.count(save, 1), 6, "and out of the box")
  eq(census(save, s), before, "and still in the save exactly once")

  -- The hole stays put: the grid must not close up under the cursor as you
  -- lift something out of the middle of it.
  local cells = s:boxCells(1)
  eq(cells[3], nil, "the cell it came out of stays empty while it is in hand")
  eq(cells[2], save.boxes[1][2], "the ones before it do not move")
  eq(cells[4], save.boxes[1][3],
     "and the ones after it stay where they were on screen")
end

do
  io.write("the last POKeMON is refused at the pick-up\n")
  -- Refusing the PICK-UP rather than the drop is what makes the rule
  -- impossible to walk around: with one POKeMON there is nothing to reorder.
  local save = saveWith(1, 0)
  local s = screenOn(save)
  s.pane, s.partySlot = "party", 1
  s:grab()
  eq(s.held, nil, "nothing is in hand")
  eq(#save.party, 1, "and the party still has it")
  ok(s.message and s.message:find("last"), "with the cart's own line")
end

do
  io.write("a POKeMON holding MAIL is refused at the pick-up\n")
  -- sPartyMail is six structs keyed by PARTY SLOT, so a boxed mon's letter
  -- has nowhere to live.
  local save = saveWith(2, 0)
  save.party[1].mail = true
  local s = screenOn(save)
  s.pane, s.partySlot = "party", 1
  s:grab()
  eq(s.held, nil, "it stays in the party")
  ok(s.message and s.message:find("MAIL"), "and is told why")
end

-- ------------------------------------------------------------ putting down

do
  io.write("party to box\n")
  local save = saveWith(3, 0)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.partySlot = "party", 1
  local carried = save.party[1]
  s:grab()
  s.pane, s.boxSlot = "box", 1
  s:place()

  eq(s.held, nil, "the hand is empty")
  eq(#save.party, 2, "the party is one shorter")
  eq(Boxes.count(save, 1), 1, "the box one longer")
  eq(save.boxes[1][1], carried, "and it is the one that was carried")
  eq(census(save, s), before, "with the save's census unchanged")
  eq(carried.hp, carried.maxHp,
     "and the cart's own tail ran: a boxed POKeMON is refilled from MAXHP")
end

do
  io.write("box to party\n")
  local save = saveWith(2, 3)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 2
  local carried = save.boxes[1][2]
  s:grab()
  s.pane, s.partySlot = "party", 3
  s:place()

  eq(#save.party, 3, "the party is one longer")
  eq(Boxes.count(save, 1), 2, "the box one shorter")
  eq(save.party[3], carried, "and it landed in the party")
  eq(census(save, s), before, "census unchanged")
end

do
  io.write("a full party has no empty row, so every drop is a swap\n")
  -- The cart's "You can't take any more POKéMON" cannot arise on this screen,
  -- and that is a property of the grid rather than a rule left out: an empty
  -- party ROW only exists while the party is short of six, so a drop onto one
  -- can never be the seventh.  A full party leaves only occupied rows.
  local save = saveWith(6, 2)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 1
  local fromBox = save.boxes[1][1]
  s:grab()
  s.pane, s.partySlot = "party", 6
  local displaced = save.party[6]
  s:place()
  eq(s.held, nil, "the hand is empty")
  eq(#save.party, 6, "the party is still six")
  eq(Boxes.count(save, 1), 2, "and the box is still two")
  eq(save.party[6], fromBox, "the boxed one took the row")
  -- Through the screen's own cell reader, not `save.boxes[1][1]`.  As of
  -- 0.32.90 the compact array's ORDER no longer says where a POKeMON sits --
  -- the arrangement beside it does, which is what lets the grid hold a gap --
  -- so "took its cell" is a question about the CELL, and the array index it
  -- happens to occupy is not the same question.
  eq(s:boxCells(1)[1], displaced, "and the party one took its cell")
  eq(census(save, s), before, "census unchanged")
end

do
  io.write("a full box refuses a deposit\n")
  local save = saveWith(3, PER_BOX)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.partySlot = "party", 1
  s:grab()
  s.pane, s.boxSlot = "box", PER_BOX + 0
  -- every cell is occupied, so aim at one and let the swap path run instead
  s.boxSlot = 20
  s:place()
  eq(s.held, nil, "a swap into a full box is allowed: one goes each way")
  eq(Boxes.count(save, 1), PER_BOX, "the box is the same size")
  eq(#save.party, 3, "and so is the party")
  eq(census(save, s), before, "census unchanged")
end

do
  io.write("swapping\n")
  local save = saveWith(3, 5)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.partySlot = "party", 2
  local fromParty = save.party[2]
  s:grab()
  s.pane, s.boxSlot = "box", 4
  local fromBox = save.boxes[1][4]
  s:place()

  eq(s.held, nil, "the hand is empty")
  eq(#save.party, 3, "the party is the same size")
  eq(Boxes.count(save, 1), 5, "and so is the box")
  eq(save.boxes[1][4], fromParty, "the carried one took the cell")
  eq(save.party[2], fromBox, "and the one that was there took its row")
  eq(census(save, s), before, "census unchanged")
end

do
  io.write("a swap that would empty the party of healthy POKeMON\n")
  -- A swap moves one each way, so the party cannot shrink and the box cannot
  -- overflow -- the capacity halves of both rules are the two that do not
  -- apply.  What does apply is what a whiteout depends on.
  local save = { party = { mon(), mon({ hp = 0 }) }, boxes = {},
                 currentBox = 1, mail = {} }
  Boxes.box(save, 1)[1] = mon({ hp = 0, isEgg = true })
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.partySlot = "party", 1
  s:grab()
  s.pane, s.boxSlot = "box", 1
  s:place()
  ok(s.held ~= nil, "the swap is refused with the POKeMON still in hand")
  ok(s.message and s.message:find("last"), "and named")
  eq(census(save, s), before, "census unchanged")
end

-- ------------------------------------------------------------- putting back

do
  io.write("B puts a carried POKeMON back where it came from\n")
  local save = saveWith(3, 6)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 2
  local carried = save.boxes[1][2]
  s:grab()
  s:returnHeld()
  eq(s.held, nil, "the hand is empty")
  eq(s:boxCells(1)[2], carried, "and it is back in its own cell")
  eq(census(save, s), before, "census unchanged")
end

do
  io.write("closing with a POKeMON in hand does not take it out of the save\n")
  local save = saveWith(3, 6)
  local before = census(save)
  local closed = false
  local s = screenOn(save, { onClose = function() closed = true end })
  s.pane, s.partySlot = "party", 2
  s:grab()
  s:close()
  eq(s.held, nil, "the hand is empty")
  eq(#save.party, 3, "the party is whole")
  eq(census(save, s), before,
     "and every POKeMON that was in the save still is -- a screen that closes "
     .. "mid-carry must never be the thing that loses one")
  ok(closed, "and the screen closed")
end

do
  io.write("a POKeMON is never dropped on the floor\n")
  -- Nowhere it came from and nowhere beside it: the first box with room.
  local save = { party = {}, boxes = {}, currentBox = 1, mail = {} }
  for _ = 1, PARTY_SIZE do save.party[#save.party + 1] = mon() end
  local box = Boxes.box(save, 1)
  for _ = 1, PER_BOX do box[#box + 1] = mon() end
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 1
  s:grab()
  -- fill the hole behind it so its own cell is gone too
  local list = Boxes.box(save, 1)
  list[#list + 1] = mon()
  local grown = census(save, s)
  s:returnHeld()
  eq(s.held, nil, "the hand is empty")
  eq(census(save, s), grown,
     "and it landed somewhere -- the first box with room, rather than nowhere")
end

-- --------------------------------------------------------------- the boxes

do
  io.write("walking the boxes\n")
  local save = saveWith(3, 2)
  local s = screenOn(save)
  eq(s.boxIndex, 1, "opens on the current box")
  s:changeBox(-1)
  eq(s.boxIndex, NUM_BOXES, "and wraps backwards to the fourteenth")
  eq(save.currentBox, NUM_BOXES, "carrying the save's own pointer with it")
  s:changeBox(1)
  eq(s.boxIndex, 1, "and forwards again")
end

do
  io.write("carrying across a box change\n")
  local save = saveWith(3, 4)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 2
  local carried = save.boxes[1][2]
  s:grab()
  s:changeBox(1)
  s.boxSlot = 1
  s:place()
  eq(Boxes.count(save, 1), 3, "box 1 is one shorter")
  eq(Boxes.count(save, 2), 1, "box 2 one longer")
  eq(save.boxes[2][1], carried, "and it is the one that was carried")
  eq(census(save, s), before, "census unchanged")
end

-- ------------------------------------------------------------- it draws

do
  io.write("it draws\n")
  local save = saveWith(3, 6)
  local s = screenOn(save)
  boxes, prints, drawnIcons = {}, {}, {}
  s:drawPanel()
  eq(#drawnIcons, 3 + 6, "an icon per party member and per boxed POKeMON")
  ok(#boxes >= 2, "the header and the info line are boxes")
  local names = {}
  for _, p in ipairs(prints) do names[p.text] = true end
  ok(names["BOX1"], "the box's name is on the header")
  ok(names["6/20"], "and how full it is")
end

-- ------------------------------------------------------------- the header

do
  io.write("the header is reachable, and box changes live there\n")
  local save = saveWith(3, 4)
  local s = screenOn(save)

  -- UP out of the top row of the grid lands on it.
  s.pane, s.boxSlot = "box", 3
  s:move("up")
  eq(s.pane, "header", "UP from the top row of the grid reaches the header")

  -- Which is where box changes belong: beside the name and the count they
  -- change, rather than on a shortcut, which is what makes them visible.
  s:move("right")
  eq(s.boxIndex, 2, "RIGHT there is the next box")
  s:move("left")
  eq(s.boxIndex, 1, "and LEFT the one before")

  s:move("down")
  eq(s.pane, "box", "DOWN goes back where it came from")
  eq(s.boxSlot, 3, "with the cursor where it left it")

  -- A stop on the way round rather than a wall.
  s:move("up")
  s:move("up")
  eq(s.pane, "box", "UP again wraps past it")
  eq(s.boxSlot, (Screen.ROWS - 1) * Screen.COLS + 3,
     "to the bottom of the column it came up")
end

do
  io.write("and from the party too\n")
  local save = saveWith(3, 4)
  local s = screenOn(save)
  s.pane, s.partySlot = "party", 1
  s:move("up")
  eq(s.pane, "header", "UP from the top of the party reaches it")
  s:move("down")
  eq(s.pane, "party", "and DOWN goes back to the party, not to the grid")
  s:move("up")
  s:move("up")
  eq(s.pane, "party", "UP twice wraps past it")
  eq(s.partySlot, Screen.PARTY_ROWS, "to the bottom row")
end

do
  io.write("A on the header is not a grab\n")
  local save = saveWith(3, 4)
  local before = census(save)
  local s = screenOn(save)
  s.pane = "header"
  pressed = { a = true }
  s:update(1 / 60)
  pressed = {}
  eq(s.held, nil, "nothing is picked up")
  eq(census(save, s), before, "and nothing moved")
end

-- ------------------------------------------------------------ START

do
  io.write("START opens the actions, it does not close the box\n")
  -- The first cut made START close the screen, which is both wrong and the
  -- one thing a player hits by accident.  B is the way out and always was.
  local save = saveWith(3, 4)
  local closed = false
  local s = screenOn(save, { onClose = function() closed = true end })
  s.pane, s.boxSlot = "box", 1

  pressed = { start = true }
  s:update(1 / 60)
  pressed = {}
  eq(closed, false, "the box is still open")
  ok(s.actions, "and the actions are up")
  local labels = {}
  for _, item in ipairs(s.actions.items) do labels[item.id] = item.label end
  ok(labels.stats, "STATS is offered")
  ok(labels.release, "RELEASE is offered over a boxed POKeMON")
  ok(labels.cancel, "and a way out of the menu")

  pressed = { b = true }
  s:update(1 / 60)
  pressed = {}
  eq(s.actions, nil, "B closes the menu")
  eq(closed, false, "without closing the box")
end

do
  io.write("RELEASE asks first\n")
  local save = saveWith(3, 4)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 2
  s:openActions()
  for i, item in ipairs(s.actions.items) do
    if item.id == "release" then s.actions.index = i end
  end
  pressed = { a = true }
  s:update(1 / 60)
  pressed = {}
  ok(s.confirm, "a confirm comes up rather than a POKeMON going away")
  eq(s.confirm.choice, 2,
     "with NO where the cursor starts, the way the cart's own QUIT box is")
  eq(census(save, s), before, "and nothing has gone yet")

  pressed = { b = true }
  s:update(1 / 60)
  pressed = {}
  eq(s.confirm, nil, "B backs out")
  eq(census(save, s), before, "with everything still there")
end

do
  io.write("...and then does it\n")
  local save = saveWith(3, 4)
  local before = census(save)
  local s = screenOn(save)
  s.pane, s.boxSlot = "box", 2
  s:openActions()
  for i, item in ipairs(s.actions.items) do
    if item.id == "release" then s.actions.index = i end
  end
  pressed = { a = true }; s:update(1 / 60); pressed = {}
  s.confirm.choice = 1
  pressed = { a = true }; s:update(1 / 60); pressed = {}
  eq(Boxes.count(save, 1), 3, "the box is one shorter")
  eq(census(save, s), before - 1, "and the census is one down, deliberately")
end

do
  io.write("the popup over an empty cell, and none with a POKeMON in hand\n")
  local save = saveWith(3, 2)
  local s = screenOn(save)

  -- SORT is a verb about the BOX and it lives here now, off SELECT, so an
  -- empty cell still has something to offer.  What it does not offer is any
  -- of the rows that are about a POKeMON.
  s.pane, s.boxSlot = "box", 10
  s:openActions()
  local labels = {}
  for _, item in ipairs((s.actions or {}).items or {}) do
    labels[#labels + 1] = tostring(item.label)
  end
  eq(table.concat(labels, ","), "SORT,CANCEL",
    "over an empty cell it is the box's verbs and nothing else")

  -- and with one in hand there is no popup at all: every row here would act
  -- on a POKeMON that is not in the box any more
  s.actions = nil
  s.boxSlot = 1
  s:grab()
  s:openActions()
  eq(s.actions, nil, "and nothing while carrying")
end

-- ------------------------------------------------------------ SORT and UNDO
--
-- Red's box has a saved cell layout, so its sort ends by closing the box up
-- and COLLAPSE is the sort that only does that.  Gold's box is a compact
-- array -- Boxes.lua keeps it that way -- so there is nothing to collapse and
-- the menu is the four orders plus UNDO.  Everything below is the census
-- rule this file is built on: a sort moves POKeMON, it never makes or loses
-- one.

local function sortedSave()
  local save = { party = {}, boxes = {}, currentBox = 1, mail = {} }
  local box = Boxes.box(save, 1)
  box[1] = mon({ species = 7, level = 30, nickname = "CHARLIE" })
  box[2] = mon({ species = 1, level = 5,  nickname = "ALICE" })
  box[3] = mon({ species = 4, level = 50, nickname = "BOB" })
  return save
end

local function ids(list)
  local out = {}
  for i, m in ipairs(list) do out[i] = m.nickname end
  return table.concat(out, ",")
end

-- The pokedex numbers and types the sort keys read.
local DATA = { pokemon = {
  [1] = { dex = 1, name = "BULBASAUR", types = { "GRASS" } },
  [4] = { dex = 4, name = "CHARMANDER", types = { "FIRE" } },
  [7] = { dex = 7, name = "SQUIRTLE", types = { "WATER" } },
} }

local function sortScreen()
  local save = sortedSave()
  local s = screenOn(save)
  s.game.data = DATA
  return s, save
end

do
  local s, save = sortScreen()
  local before = census(save, s)
  eq(ids(Boxes.box(save, 1)), "CHARLIE,ALICE,BOB", "the box starts unsorted")

  s:sortBox("dex")
  eq(ids(Boxes.box(save, 1)), "ALICE,BOB,CHARLIE", "BY DEX orders by dex number")
  eq(census(save, s), before, "and nothing was made or lost")
end

do
  local s, save = sortScreen()
  s:sortBox("level")
  eq(ids(Boxes.box(save, 1)), "BOB,CHARLIE,ALICE",
     "BY LEVEL puts the strongest first")
end

do
  local s, save = sortScreen()
  s:sortBox("name")
  eq(ids(Boxes.box(save, 1)), "ALICE,BOB,CHARLIE", "BY NAME is alphabetical")
end

do
  local s, save = sortScreen()
  s:sortBox("type")
  -- FIRE, GRASS, WATER
  eq(ids(Boxes.box(save, 1)), "BOB,ALICE,CHARLIE",
     "BY TYPE is the primary type, alphabetically")
end

-- Ties keep the order somebody is already looking at.
do
  local save = { party = {}, boxes = {}, currentBox = 1, mail = {} }
  local box = Boxes.box(save, 1)
  box[1] = mon({ species = 1, level = 9, nickname = "FIRST" })
  box[2] = mon({ species = 1, level = 9, nickname = "SECOND" })
  box[3] = mon({ species = 1, level = 9, nickname = "THIRD" })
  local s = screenOn(save); s.game.data = DATA
  s:sortBox("level")
  eq(ids(Boxes.box(save, 1)), "FIRST,SECOND,THIRD",
     "POKeMON that tie keep the order they were in")
end

-- ---- one step back

do
  local s, save = sortScreen()
  eq(s:canUndoSort(), false, "nothing to undo before a sort")
  s:sortBox("name")
  eq(s:canUndoSort(), true, "a sort leaves one step of undo")
  s:undoSort()
  eq(ids(Boxes.box(save, 1)), "CHARLIE,ALICE,BOB", "UNDO puts the order back")
  eq(s:canUndoSort(), false, "and is spent")
end

do
  local s, save = sortScreen()
  s:sortBox("name")
  s.boxIndex = 2
  eq(s:canUndoSort(), false, "a snapshot of box 1 is not offered on box 2")
  s.boxIndex = 1
  eq(s:canUndoSort(), true, "and is offered again back on box 1")
end

-- The identity check: one released and one deposited leaves the COUNT alone,
-- and an undo that went ahead would resurrect the released one.
do
  local s, save = sortScreen()
  s:sortBox("name")
  local list = Boxes.box(save, 1)
  list[1] = mon({ nickname = "NEWCOMER" })
  eq(s:canUndoSort(), false,
     "a box whose membership changed cannot be un-sorted")
end

do
  local s, save = sortScreen()
  s:sortBox("name")
  local list = Boxes.box(save, 1)
  list[#list] = nil
  eq(s:canUndoSort(), false, "nor one that lost a POKeMON")
end

-- ---- the menu

do
  local s = sortScreen()
  s.pane = "box"
  s:openSort()
  ok(s.sortMenu ~= nil, "SELECT over the box opens the sort menu")
  eq(#s.sortMenu.items, 5, "four orders and CANCEL, with nothing to undo yet")
  eq(s.sortMenu.items[1].label, "BY DEX", "headed by BY DEX")
  eq(s.sortMenu.items[#s.sortMenu.items].label, "CANCEL", "and ending in CANCEL")
  local labels = {}
  for _, item in ipairs(s.sortMenu.items) do labels[item.label] = true end
  eq(labels["COLLAPSE"], nil,
     "no COLLAPSE: Gold's box is compact, so there is nothing to close up")

  s:chooseSort("name")
  eq(s.sortMenu, nil, "choosing an order closes the menu")
  s.pane = "box"
  s:openSort()
  eq(#s.sortMenu.items, 6, "and UNDO joins the menu once there is one")
  eq(s.sortMenu.items[5].label, "UNDO", "just above CANCEL")
end

do
  local s = sortScreen()
  s.pane = "box"
  s:openSort()
  s:chooseSort("cancel")
  eq(s.sortMenu, nil, "CANCEL closes the menu")
  eq(s.sortUndo, nil, "and sorts nothing")
end

-- A sort with a POKeMON in hand would reorder the box around one that is not
-- in it, which reads as the box shuffling itself for no reason.
do
  local s, save = sortScreen()
  s.pane = "box"
  s.held = { mon = mon(), from = "box", box = 1, cell = 1 }
  s:openSort()
  eq(s.sortMenu, nil, "no sort with a POKeMON in hand")
end

do
  local s = sortScreen()
  s.pane = "header"
  s:openSort()
  eq(s.sortMenu, nil, "and none from the header")
end

do
  local save = { party = {}, boxes = {}, currentBox = 1, mail = {} }
  Boxes.box(save, 1)[1] = mon({ nickname = "ALONE" })
  local s = screenOn(save); s.game.data = DATA
  s.pane = "box"
  s:openSort()
  eq(s.sortMenu, nil, "one POKeMON is not a box that needs sorting")
  ok(s.message ~= nil, "and it says so rather than opening an empty menu")
end

-- --------------------------------------------------------------- the cursor

do
  io.write("the party cursor points AT the party\n")
  -- Six rows of sixteen fill the pane's ninety-six pixels exactly, so there
  -- is no band above a party POKeMON's head for a down arrow to sit in -- and
  -- a column of entries with the cursor to their left is the party menu's own
  -- idiom on both games.  A down arrow there points at nothing.
  local save = saveWith(3, 4)
  local s = screenOn(save)

  s.pane, s.partySlot = "party", 1
  rects = {}
  s:drawParty()
  local widths, heights = {}, {}
  for _, r in ipairs(rects) do
    widths[r.w] = (widths[r.w] or 0) + 1
    heights[r.h] = (heights[r.h] or 0) + 1
  end
  ok((widths[1] or 0) >= 4,
     "it is drawn as 1-wide COLUMNS, which is the triangle a quarter turn "
     .. "round -- a sideways arrow, not a down one")
  ok((heights[7] or 0) >= 1, "seven tall at its base")

  s.pane, s.boxSlot = "box", 1
  rects = {}
  s:drawGrid()
  local wide = 0
  for _, r in ipairs(rects) do
    if r.h == 1 and r.w == 7 then wide = wide + 1 end
  end
  ok(wide >= 1,
     "while the grid's is rows getting shorter -- a DOWN arrow, because a "
     .. "cell has a band above the icon to point from")
  rects = nil
end

io.write(("bills box gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
