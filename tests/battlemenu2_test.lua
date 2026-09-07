-- The battle command menu on Gold, as four buttons.
--
-- Gold already lays its four commands out as a 2x2 -- `col = ((i-1)%2)*
-- spacing`, `row = floor((i-1)/2)*2` -- which is why this mod was Gen 1 only
-- for its whole life.  What it does not do is FRAME them: the four words sit
-- in one box across the right of the strip, so the grid reads as a block of
-- text rather than as four buttons.  That is what "still no updated battle ui
-- like we have for Gen 1 with the 2x2 selections" was about.
--
-- So the Gold arm is the frame and only the frame, and these cases are about
-- how narrowly it claims the strip: the command menu, on top of the stack,
-- outside a contest, with the option on.  Everything else -- a message, a
-- move list, the bug contest's eleven-glyph third label -- keeps the cart's
-- own box, and a claim that leaked into any of them would take a text box
-- away from a player mid-sentence.
--
-- Run:  luajit tests/battlemenu2_test.lua

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
  local source = handle:read("*a")
  handle:close()
  return source
end

-- ------------------------------------------------------------- the harness

package.loaded["src.core.GameVersion"] = {
  generation = function() return 2 end,
  get = function() return "gold" end,
  isYellow = function() return false end,
}

local boxes, prints, cursors, inks

-- The shared font module, which is where every glyph on this screen comes
-- from on both generations.  `draw` records what was printed and where; the
-- INK is whatever C.inked had bound at the time, which is the whole subject
-- of half the cases below.
local currentColor, currentTint

-- Glyphs, not bytes: `<PK><MN>` is ONE word the font has no letters for and
-- TWO glyphs wide, so a stub that measured it by its eight bytes would report
-- it as too wide for a cell it actually fits in.  The real Font.width walks
-- the same spans.
local function glyphs(text)
  local out, i = {}, 1
  text = tostring(text or "")
  while i <= #text do
    local open = text:find("<", i, true)
    if open == i then
      local close = text:find(">", i, true)
      if close then
        out[#out + 1] = text:sub(i, close)
        i = close + 1
      else
        out[#out + 1] = text:sub(i, i)
        i = i + 1
      end
    else
      out[#out + 1] = text:sub(i, i)
      i = i + 1
    end
  end
  return out
end

package.loaded["src.render.Font"] = {
  BORDER = { h = 1, v = 2 },
  PLAINPIXEL = "plainpixel.ttf",
  width = function(text) return #glyphs(text) * 8 end,
  advanceOf = function() return 8 end,
  split = function(text)
    local spans, at = {}, 0
    for _, glyph in ipairs(glyphs(text)) do
      at = at + #glyph
      spans[#spans + 1] = { to = at }
    end
    return spans
  end,
  draw = function(text, x, y)
    prints[#prints + 1] = { text = text, x = x, y = y,
                            ink = currentTint or currentColor }
    return #glyphs(text) * 8
  end,
  drawCode = function() end,
  drawBox = function() end,
}
package.loaded["src.core.Strings"] = setmetatable({
  source = function(s) return s end,
}, { __call = function(_, s) return s end })
package.loaded["src.battle.TypeChart"] = {
  displayName = function(id) return tostring(id):gsub("_TYPE$", "") end,
}
package.loaded["src.ui.Theme"] = { cursor = 0xED, cursorHollow = 0xEC }

_G.love = _G.love or {}
-- The stencil.  A tile glyph is black on transparent and setColor cannot
-- reach it, so the only way a label is ever coloured is a shader that keeps
-- the glyph's alpha and supplies the RGB itself -- which means the ink a case
-- wants to read is the TINT that was sent, not the draw colour.
local SHADER = {}
SHADER.send = function(_, name, value)
  if name == "tint" then currentTint = value end
end

love.graphics = {
  setColor = function(r, g, b) currentColor = { r, g, b } end,
  getColor = function() return 1, 1, 1, 1 end,
  setShader = function(shader) if not shader then currentTint = nil end end,
  getShader = function() return nil end,
  getFont = function() return nil end,
  setFont = function() end,
  print = function(text, x, y)
    prints[#prints + 1] = { text = text, x = x, y = y, ink = currentColor,
                            small = true }
  end,
  rectangle = function() end,
  newShader = function() return SHADER end,
  newFont = function() return nil end,
}

local Chrome = {
  DEFAULT_BOX_PALETTE = {
    { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
  },
  box = function(tx, ty, tw, th)
    boxes[#boxes + 1] = { tx = tx, ty = ty, tw = tw, th = th }
  end,
  printThrough = function(text, tx, ty)
    prints[#prints + 1] = { text = text, tx = tx, ty = ty }
    return #tostring(text) * 8
  end,
  cursorThrough = function(tx, ty, palette, invert, hollow)
    cursors[#cursors + 1] = { tx = tx, ty = ty, hollow = hollow or false }
  end,
}
Chrome.cursor = function(tx, ty, hollow)
  return Chrome.cursorThrough(tx, ty, Chrome.DEFAULT_BOX_PALETTE, nil, hollow)
end
package.loaded["src.ui.gen2.Chrome"] = Chrome

local mod = {
  id = "gen1_wild_ui",
  path = "modules/Gen1BattleUI",
  exports = {},
  stored = {},
  hooked = {},
  logged = {},
}
mod.read = function(_, name)
  return slurp("modules/Gen1BattleUI/" .. name)
end
mod.options = {
  define = function(_, rows) mod.rows = rows end,
  get = function(_, key) return mod.stored[key] end,
  set = function(_, key, value) mod.stored[key] = value end,
}
mod.log = {}
for _, level in ipairs({ "info", "warn", "error", "debug" }) do
  mod.log[level] = function(_, format, ...)
    mod.logged[#mod.logged + 1] = select("#", ...) > 0
      and tostring(format):format(...) or tostring(format)
  end
end
mod.hooks = {
  wrap = function(_, name, fn, priority)
    mod.hooked[name] = { fn = fn, priority = priority }
  end,
}

assert(load(slurp("modules/Gen1BattleUI/main.lua"),
            "@modules/Gen1BattleUI/main.lua"))()(mod)

-- The labels are the cart's, ligature and all: `<PK><MN>` is two glyphs of
-- charmap and not the four letters it is spelled with here.
local LABELS = { "FIGHT", "<PK><MN>", "PACK", "RUN" }

-- Four moves, the second of them long enough to need cutting to a cell and
-- the fourth an empty slot.
local MOVES = {
  { id = "TACKLE", pp = 30, maxPp = 35 },
  { id = "THUNDERSHOCK", pp = 10, maxPp = 30 },
  { id = "GROWL", pp = 40, maxPp = 40 },
}
local MOVE_DATA = {
  TACKLE = { name = "TACKLE", type = "NORMAL_TYPE" },
  THUNDERSHOCK = { name = "THUNDERSHOCK", type = "ELECTRIC_TYPE" },
  GROWL = { name = "GROWL", type = "NORMAL_TYPE" },
}

local function screen(opts)
  opts = opts or {}
  local self = {
    phase = opts.phase or "menu",
    battle = opts.battle ~= false
      and { wild = true, player = { name = "PIKA" },
            moveDisabled = function(_, _, id) return id == opts.disabled end }
      or nil,
    menuIndex = opts.menuIndex or 1,
    moveIndex = opts.moveIndex or 1,
    moveSwapIndex = opts.moveSwapIndex,
    contest = opts.contest,
  }
  self.menuLabels = function() return LABELS end
  self.playerMoves = function() return MOVES end
  self.game = { data = { moves = MOVE_DATA } }
  if opts.covered then
    local other = {}
    self.game.stack = { top = function() return other end }
  end
  return self
end

local function overlay(state)
  boxes, prints, cursors = {}, {}, {}
  local hook = mod.hooked["battle.overlay"]
  hook.fn(function() end, state)
end

-- What ink a printed string was drawn in, as a 0-255 triple: C.inked has no
-- shader here, so what it leaves on the colour is what it decided.
local function inkAt(text)
  for _, printed in ipairs(prints) do
    if printed.text == text and printed.ink then
      return { printed.ink[1] * 255, printed.ink[2] * 255,
               printed.ink[3] * 255 }
    end
  end
  return nil
end

local function printed(text)
  for _, entry in ipairs(prints) do
    if entry.text == text then return entry end
  end
  return nil
end

local function visible(state)
  local hook = mod.hooked["battle.bottom_ui_visible"]
  return hook.fn(function() return true end, state)
end

-- ---------------------------------------------------------------- installed

do
  io.write("the Gold arm installs\n")
  ok(mod.hooked["battle.bottom_ui_visible"], "the strip is asked for")
  ok(mod.hooked["battle.overlay"], "and the buttons are drawn on the overlay")
  eq(mod.hooked["battle.overlay"].priority, 5000,
     "last on the chain, so nothing else on the overlay draws over them")
  ok(not mod.hooked["battle.exp_award"],
     "and none of the Gen 1 machinery is installed: Gold has its own XP bar, "
     .. "its own level-up box and its own move panel")

  local keys = {}
  for _, row in ipairs(mod.rows or {}) do keys[row.key] = row end
  ok(keys.command_grid, "COMMAND GRID is the one row")
  eq(keys.command_grid and keys.command_grid.default, true, "and it is on")
  ok(keys.move_grid, "and MOVE GRID beside it")
  ok(keys.type_colour, "with the type colour it takes to be worth having")
  ok(not keys.xp_bar,
     "and no XP BAR row, because Gold has one of its own and animates it "
     .. "with the cart's own fill sound")
  ok(not keys.ball_colour,
     "nor a ball-colour one, which is Gen 1 sprite machinery")
end

-- ------------------------------------------------------------- the four boxes

do
  io.write("four boxes tiling the strip\n")
  overlay(screen())
  eq(#boxes, 4, "one box per command")

  -- Rows 12-17, twenty tiles wide: four 10x3 boxes tile it exactly, which is
  -- the same CLASSIC_BOXES the Gen 1 arm draws.
  local wanted = { { 0, 12 }, { 10, 12 }, { 0, 15 }, { 10, 15 } }
  for i, want in ipairs(wanted) do
    eq(boxes[i] and boxes[i].tx, want[1], ("box %d starts in its column"):format(i))
    eq(boxes[i] and boxes[i].ty, want[2], ("box %d on its row"):format(i))
    eq(boxes[i] and boxes[i].tw, 10, ("box %d is ten wide"):format(i))
    eq(boxes[i] and boxes[i].th, 3, ("box %d is three tall"):format(i))
  end

  eq(#prints, 4, "and one label per box")
  ok(printed("FIGHT"), "the cart's own words")
  ok(printed("<PK><MN>"),
     "including the ligature, which is what makes it fit")
  -- tx..tx+9 is the box and tx / tx+9 are its border columns, so the interior
  -- is tx+1..tx+8: the hand's tile and seven of label.  FIGHT is five glyphs
  -- in seven, so it is centred one glyph in from the label column.
  eq(printed("FIGHT") and printed("FIGHT").x, 2 * 8 + 8,
     "the label clears the hand's column and is centred in what is left")
  eq(printed("FIGHT") and printed("FIGHT").y, 13 * 8,
     "on the box's interior row")
  eq(printed("RUN") and printed("RUN").y, 16 * 8, "and the bottom row's on it")
  ok((printed("RUN") and printed("RUN").x or 0) >= 12 * 8,
     "with the right column's labels in the right column")
end

do
  io.write("the labels take the theme's ink\n")
  overlay(screen())
  eq(inkAt("FIGHT") and inkAt("FIGHT")[1], 0,
     "black on the cart's own white box")

  -- The theme rewrites Chrome.DEFAULT_BOX_PALETTE in place, and this file
  -- reads the ink back off it rather than asking the theme -- that palette IS
  -- what the theme changes, so reading it cannot disagree with it.
  local vanilla = Chrome.DEFAULT_BOX_PALETTE
  Chrome.DEFAULT_BOX_PALETTE = {
    { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 255, 255, 255 },
  }
  overlay(screen())
  eq(inkAt("FIGHT") and inkAt("FIGHT")[1], 255,
     "and white on a dark one -- a button is a BOX, and a theme owns a box's "
     .. "paper as well as its ink, so it can flip both and stay legible")
  Chrome.DEFAULT_BOX_PALETTE = vanilla
end

do
  io.write("the hand\n")
  overlay(screen({ menuIndex = 3 }))
  eq(#cursors, 1, "one hand")
  eq(cursors[1] and cursors[1].tx, 1,
     "in the column the label leaves for it, so nothing shifts sideways as "
     .. "the cursor moves")
  eq(cursors[1] and cursors[1].ty, 16, "on the row of the command it is on")
end

-- ---------------------------------------------------------- the move grid

do
  io.write("the moves in the same four boxes\n")
  overlay(screen({ phase = "moves", moveIndex = 2 }))
  -- Four buttons and the panel over them.
  eq(#boxes, 5, "four buttons and the panel")
  eq(boxes[1] and boxes[1].tx, 0, "the panel goes down first, under the grid")
  eq(boxes[1] and boxes[1].ty, 8, "at (0,8), where Gold's MoveInfoBox sat")
  eq(boxes[1] and boxes[1].tw, 14,
     "fourteen wide -- twelve interior tiles, which is the longest move name "
     .. "Gen 2 has")
  eq(boxes[2] and boxes[2].ty, 12, "and the buttons after it")

  ok(printed("TACKLE"), "each move on its own button")
  ok(printed("GROWL"), "including the third")
  ok(printed("-"), "and an empty slot prints '-' rather than nothing")

  eq(#cursors, 1, "one hand")
  eq(cursors[1] and cursors[1].tx, 11, "on the move the cursor is on")
  eq(cursors[1] and cursors[1].ty, 13, "in its own box")
end

do
  io.write("the type, in the type's own colour\n")
  overlay(screen({ phase = "moves", moveIndex = 2 }))
  -- The panel reads the highlighted move: its name whole, its type, its PP.
  ok(printed("ELECTRIC"), "the panel names the type")
  ok(printed("PP 10/30"), "and prints its PP")
  local ink = inkAt("ELECTRIC")
  ok(ink and (ink[1] > 100 and ink[3] < 60),
     "in ELECTRIC's own ink rather than in black")
  -- THUNDERSHOCK is twelve glyphs and the cell has seven, so the button reads
  -- the cut name -- and it is still ELECTRIC's ink that cuts it.
  local cut
  for _, entry in ipairs(prints) do
    -- The top-right button, whose label column starts at (10+2)*8.
    if (entry.x or 0) >= 96 and tostring(entry.text):match("^THUNDE") then
      cut = entry
    end
  end
  ok(cut, "the button prints the name it has room for, cut to the cell")
  ok(cut and cut.text ~= "THUNDERSHOCK",
     "which is not the whole name -- twelve glyphs in seven -- and is why "
     .. "the panel above reads it whole")
  ok(cut and cut.ink and cut.ink[1] * 255 > 100,
     "and the button's own letters take the same colour")
end

do
  io.write("the same colours on a dark box\n")
  local vanilla = Chrome.DEFAULT_BOX_PALETTE
  Chrome.DEFAULT_BOX_PALETTE = {
    { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 255, 255, 255 },
  }
  overlay(screen({ phase = "moves", moveIndex = 2 }))
  local ink = inkAt("ELECTRIC")
  -- TYPE_INK is written dark because it was written for black ink on a white
  -- box.  On a dark one those same inks are unreadable, so they are wound up
  -- to full strength with the hue left exactly where it was.
  ok(ink and math.max(ink[1], ink[2], ink[3]) > 250,
     "wound up to full strength, so the letters are readable")
  ok(ink and ink[3] < ink[1],
     "with the hue untouched -- still ELECTRIC, not a grey")
  Chrome.DEFAULT_BOX_PALETTE = vanilla
end

do
  io.write("TYPE COLOUR off\n")
  mod.stored.type_colour = false
  overlay(screen({ phase = "moves", moveIndex = 2 }))
  eq(inkAt("ELECTRIC") and inkAt("ELECTRIC")[1], 0,
     "the type prints in the box's own ink")
  mod.stored.type_colour = nil
end

do
  io.write("a disabled move says so\n")
  overlay(screen({ phase = "moves", moveIndex = 2,
                   disabled = "THUNDERSHOCK" }))
  ok(printed("Disabled!"),
     "instead of showing what it would have cost, which is what the cart's "
     .. "own MoveInfoBox does")
  ok(not printed("PP 10/30"), "and the PP line is not printed under it")
end

do
  io.write("the held move's marker\n")
  overlay(screen({ phase = "moves", moveIndex = 2, moveSwapIndex = 3 }))
  eq(#cursors, 2, "the hollow marker and the filled hand")
  eq(cursors[1] and cursors[1].hollow, true,
     "the hollow one first, so the filled hand covers it if they share a cell")
  eq(cursors[2] and cursors[2].hollow, false, "and the hand over it")

  overlay(screen({ phase = "moves", moveIndex = 3, moveSwapIndex = 3 }))
  eq(#cursors, 1,
     "one hand where they DO share a cell -- stacking the two glyphs merges "
     .. "them into a smear")
end

do
  io.write("MOVE PANEL off\n")
  mod.stored.move_panel = false
  overlay(screen({ phase = "moves" }))
  eq(#boxes, 4, "the four buttons take the strip and nothing sits over them")
  mod.stored.move_panel = nil
end

do
  io.write("MOVE GRID off\n")
  mod.stored.move_grid = false
  eq(visible(screen({ phase = "moves" })), true, "Gold's own list comes back")
  overlay(screen({ phase = "moves" }))
  eq(#boxes, 0, "and nothing is drawn over it")
  eq(mod.hooked["battle.move_grid_navigation"].fn(function() return false end,
     screen({ phase = "moves" })), false,
     "and LEFT/RIGHT stop crossing, because it is a list again")
  mod.stored.move_grid = nil
end

do
  io.write("the grid navigation\n")
  eq(mod.hooked["battle.move_grid_navigation"].fn(function() return false end,
     screen({ phase = "moves" })), true,
     "the cart already knows how to navigate a 2x2; it just has to be told "
     .. "that this one is a grid")
  eq(mod.hooked["battle.move_grid_navigation"].fn(function() return false end,
     screen({ phase = "menu" })), false,
     "and the command menu was never a list, so it is not asked")
end

-- ------------------------------------------------------- what it stands clear of

do
  io.write("whose strip it is\n")
  eq(visible(screen()), false, "the command menu's strip is ours")

  eq(visible(screen({ phase = "messages" })), true,
     "a message keeps the engine's own text box, which is the whole of how "
     .. "dialogue takes the strip back")
  overlay(screen({ phase = "messages" }))
  eq(#boxes, 0, "and no buttons are drawn under it")

  eq(visible(screen({ phase = "moves" })), false,
     "and the move menu's is ours too")

  eq(visible(screen({ contest = { balls = 20 } })), true,
     "and so does the bug contest, whose third label is PARKBALL and a count "
     .. "-- eleven glyphs where a 10-tile box has seven")
  overlay(screen({ contest = { balls = 20 } }))
  eq(#boxes, 0, "no buttons over it either")

  eq(visible(screen({ covered = true })), true,
     "and a battle with a screen open above it is not the one being asked "
     .. "about")

  eq(visible({ phase = "menu" }), true,
     "nor is a state that is not a battle at all")
end

do
  io.write("COMMAND GRID off\n")
  mod.stored.command_grid = false
  eq(visible(screen()), true, "the cart's own menu box comes back")
  overlay(screen())
  eq(#boxes, 0, "and nothing is drawn over it")
  mod.stored.command_grid = nil
end

-- ------------------------------------------------------------- the geometry

do
  io.write("the published geometry\n")
  local cells = mod.exports.geometry()
  eq(#cells, 4, "four cells")
  eq(cells[1].box.x, 0, "in pixels, for a neighbour that wants to clip")
  eq(cells[1].box.w, 80, "ten tiles")
  eq(cells[4].textY, 16 * 8, "and the last row's baseline")
  eq(cells[1].labelW, 56, "seven glyphs of label per button")
  ok(type(mod.exports.owns) == "function",
     "and whether the strip is claimed is answerable without drawing one")
end

io.write(("battle menu gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
