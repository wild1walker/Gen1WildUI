-- Gen1BattleUI on Gold: the command menu and the move menu, as four buttons.
--
-- Returns a factory: factory(mod, C) -> { install, owns, draw, geometry }.
--
-- ------- what Gold already had, and what it did not
--
-- The reason this module was Gen 1 only for its whole life is that Gold ships
-- the half of it that matters most: `BattleState:drawPanel` lays the four
-- commands out at `col = ((i - 1) % 2) * spacing` and
-- `row = floor((i - 1) / 2) * 2` (src/ui/gen2/BattleState.lua), which IS the
-- 2x2 this mod builds for Red out of Red's four-row list.  The grid was
-- already there in the numbers, and `battle.move_grid_navigation` was already
-- wired, so LEFT and RIGHT already knew how to cross one.
--
-- What was not there is the FRAME.  Gold draws one box across the right of
-- the strip and prints four words inside it, and its MOVE menu is a plain
-- four-row list in a box of its own -- so both read as text in a window
-- rather than as buttons.  Reported twice: "still no updated battle ui like
-- we have for Gen 1 with the 2x2 selections", and then "moves still aren't in
-- the 2x2 tiles with the move coloring".
--
-- So this is the frame, on both menus:
--
--   four 10x3 boxes tiling rows 12-17, the same CLASSIC_BOXES the Gen 1 arm
--   uses, because Gold's bottom strip is the same twenty tiles by six;
--
--   and over the move grid, the panel -- the highlighted move's name whole,
--   its type in the type's own colour, and its PP -- at (0,8), which is
--   within a tile of where Gold's own MoveInfoBox sat and covers what that
--   box covered.
--
-- ------- and nothing about what the menus DO
--
-- `menuIndex`, `moveIndex` and `moveSwapIndex` are still the cart's, still
-- mean what they meant, and are still moved by the cart's own input handling.
-- The labels are still `BattleState:menuLabels()` and the cart's own move
-- names, so a translation keeps answering and the <PK><MN> ligature is still
-- the ligature.  Nothing is replaced: the strip is asked not to draw
-- (battle.bottom_ui_visible) and the buttons go down in the seam the engine
-- already has for exactly this (battle.overlay, which runs last, in the
-- 160x144 space).
--
-- ------- how a colour survives a theme here, and why it is not Red's way
--
-- Red has to LEAVE the palette pass to keep a type colour: its theme paints a
-- four-shade panel over every box a battle draws, so a real RGB colour under
-- one comes back as whichever grey its red channel landed on, and C.onDark
-- has to claim the letters' rectangle and have the renderer re-blit it raw.
--
-- Gen 2 themes the other way round -- each draw is handed its own four
-- numbers, and there is no pass afterwards -- so a glyph stencilled by
-- C.inked is never in a palette pass to begin with and its colour survives on
-- its own.  What does not survive is legibility: TYPE_INK is written dark
-- because it was written for black ink on a white box, and on a dark one
-- those same inks are unreadable.  So the ink is lifted with C.vivid when the
-- box is dark, and "is the box dark" is read off the live box palette's own
-- ink rather than asked of the theme -- that palette IS what the theme
-- changes, so reading it cannot disagree with it.
--
-- Every label goes through the same stencil for the same reason: a tile glyph
-- is black on transparent and ignores setColor, so on a DARK box the only way
-- to print a label in the theme's light ink AND centre it on a pixel is to
-- supply the RGB through the shader.  Chrome's own printThrough would do the
-- colour but only on the tile grid.
--
-- ------- what it stands clear of
--
-- THE BUG CONTEST MENU.  ContestBattleMenuHeader is the same grid moved out
-- to menu_coords 2, 12 because its third label is "PARKBALL" and the count
-- PrintNum writes after it -- eleven glyphs where a 10-tile box has seven.
-- It keeps the cart's own box.
--
-- THE MESSAGE.  Gold prints "<MON> what will you do?" into the left of the
-- strip and opens the menu over the right of it.  Four buttons tile the whole
-- strip, so the prompt goes -- exactly as it goes on Red, where the same four
-- buttons cover the same box.

return function(mod, C)
  local Gen2 = {}

  local okChrome, Chrome = pcall(require, "src.ui.gen2.Chrome")
  if not (okChrome and type(Chrome) == "table"
          and type(Chrome.box) == "function") then
    error("no src.ui.gen2.Chrome to draw the battle menu with", 0)
  end
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local TypeChart
  do
    local okType, found = pcall(require, "src.battle.TypeChart")
    if okType and type(found) == "table" then TypeChart = found end
  end

  -- The three phases whose bottom strip is a menu rather than a message.
  local OWNED = { menu = "command_grid", moves = "move_grid" }

  -- Four 10x3 boxes tiling rows 12-17.  tx..tx+9 is the box and tx / tx+9 are
  -- its border columns, so the interior is tx+1..tx+8: one tile kept for the
  -- hand and seven of label.  The hand's column is reserved whether or not
  -- the hand is in it, which is what stops the other three labels from
  -- sliding sideways as the cursor moves.
  local BOXES = { { 0, 12 }, { 10, 12 }, { 0, 15 }, { 10, 15 } }
  local BOX_W, BOX_H = 10, 3
  local LABEL_W = 7 * 8

  -- Flush on top of the grid: the panel's bottom border row IS the buttons'
  -- top border row, which is what makes the two read as one piece of chrome
  -- rather than as two boxes that happen to touch.  Fourteen wide is the
  -- smallest that still prints a move name whole -- twelve interior tiles,
  -- and Gen 2's longest names (DYNAMICPUNCH, THUNDERSHOCK) are twelve.
  local PANEL = { tx = 0, ty = 8, tw = 14, th = 5 }

  function Gen2.geometry()
    local cells = {}
    for i, box in ipairs(BOXES) do
      cells[i] = {
        box = { x = box[1] * 8, y = box[2] * 8, w = BOX_W * 8, h = BOX_H * 8 },
        handX = (box[1] + 1) * 8,
        labelX = (box[1] + 2) * 8,
        textY = (box[2] + 1) * 8,
        labelW = LABEL_W,
      }
    end
    return cells
  end

  function Gen2.panelRect()
    return { x = PANEL.tx * 8, y = PANEL.ty * 8,
             w = PANEL.tw * 8, h = PANEL.th * 8 }
  end

  -- ------- the live ink

  local function palette()
    local pal = Chrome.DEFAULT_BOX_PALETTE
    if type(pal) ~= "table" then return nil end
    return pal
  end

  -- The colour a label is printed in when it has no colour of its own: the
  -- box palette's own ink, so LIGHT prints black and DARK prints white and
  -- neither has to be told which one is up.
  local function boxInk()
    local pal = palette()
    local ink = pal and pal[4]
    if type(ink) ~= "table" then return { 0, 0, 0 } end
    return ink
  end

  -- ...and whether that ink is the LIGHT one, which is the same question as
  -- "is the paper under it dark".
  local function onDark()
    local ink = boxInk()
    return (ink[1] + ink[2] + ink[3]) > 384
  end

  local function typeInkFor(def)
    if not C.option("type_colour", true) then return nil end
    local shade = C.typeInk(def and def.type)
    if not shade then return nil end
    if onDark() then return C.vivid(shade) end
    return shade
  end

  -- ------- the words

  local function moveDef(state, move)
    if not move then return nil end
    local data = state.game and state.game.data
    return data and data.moves and data.moves[move.id]
  end

  local function typeText(state, def)
    if not (def and def.type and TypeChart
            and type(TypeChart.displayName) == "function") then
      return nil
    end
    local data = state.game and state.game.data
    local ok, name = pcall(TypeChart.displayName, def.type, data)
    return ok and name or nil
  end

  local function ppText(move)
    if not move then return nil end
    return ("PP %2d/%2d"):format(move.pp or 0, move.maxPp or 0)
  end

  local function disabled(state, move)
    local fighter = state.battle and state.battle.player
    if not (fighter and move and state.battle
            and type(state.battle.moveDisabled) == "function") then
      return false
    end
    local ok, yes = pcall(state.battle.moveDisabled, state.battle, fighter,
                          move.id)
    return ok and yes and true or false
  end

  -- Four labels whatever the party has: an empty slot prints '-', the way the
  -- cart's own list does, and an id with no definition behind it -- a
  -- mod-injected move -- prints raw rather than bringing the battle down.
  local function moveLabels(state, moves)
    local out = {}
    for i = 1, 4 do
      local move = moves and moves[i]
      if move then
        local def = moveDef(state, move)
        out[i] = { text = def and def.name or tostring(move.id),
                   ink = typeInkFor(def) }
      else
        out[i] = { text = "-" }
      end
    end
    return out
  end

  local function commandLabels(state)
    local labels = state:menuLabels()
    local out = {}
    for i = 1, 4 do out[i] = { text = tostring(labels[i] or "") } end
    return out
  end

  -- ------- drawing

  -- One label, centred in the pixels the cell has left after the hand's
  -- column, stencilled in `ink`.  `small` is the narrow face, used only when
  -- the caller has decided this grid's names do not fit the game's own.
  local function drawLabel(label, x, y, width, small)
    local ink = label.ink or boxInk()
    if small and label.text then
      local text = C.shortenWith(
        function(t) return C.smallWidth(small, t) end, label.text, width)
      local w = C.smallWidth(small, text)
      local lx = x + math.max(0, math.floor((width - w) / 2))
      -- A TTF glyph really is drawn in the current colour, so the small face
      -- needs no shader: setting the ink is enough.
      C.inkBytes(ink)
      local prev = love.graphics.getFont and love.graphics.getFont()
      love.graphics.setFont(small.font)
      love.graphics.print(tostring(text), lx, y + (small.yOffset or 0))
      if prev then love.graphics.setFont(prev) end
      C.white()
      return
    end
    local text = C.shorten(label.text, width)
    local w = C.width(text)
    local lx = x + math.max(0, math.floor((width - w) / 2))
    C.inked(ink, function() Font.draw(text, lx, y) end)
    C.white()
  end

  -- The small face is chosen for the WHOLE grid or for none of it: THUNDER.
  -- in the game's own font beside THUNDERSHOCK in another one, in the same
  -- four boxes, reads as a rendering fault rather than as a choice.
  local function faceFor(labels)
    if not C.option("full_names", false) then return nil end
    local needed = false
    for i = 1, 4 do
      local label = labels[i]
      if label and label.text and C.width(label.text) > LABEL_W then
        needed = true
        break
      end
    end
    if not needed then return nil end
    return C.small(LABEL_W)
  end

  local function fill(labels, selected, swap, small)
    local pal = palette()
    for i, box in ipairs(BOXES) do
      local tx, ty = box[1], box[2]
      Chrome.box(tx, ty, BOX_W, BOX_H)
      local label = labels[i]
      if label then
        drawLabel(label, (tx + 2) * 8, (ty + 1) * 8, LABEL_W, small)
      end
    end
    -- The hands last, over the boxes and the labels alike, and the filled one
    -- last of all: PlaceMenuCursor writes it into the tilemap OVER the hollow
    -- marker, so a slot that is both held and selected shows one hand and not
    -- a smear of two.
    if swap and swap ~= selected and BOXES[swap] then
      Chrome.cursorThrough(BOXES[swap][1] + 1, BOXES[swap][2] + 1, pal, nil,
                           true)
    end
    if selected and BOXES[selected] then
      Chrome.cursorThrough(BOXES[selected][1] + 1, BOXES[selected][2] + 1, pal)
    end
  end

  -- The panel: name, type, PP, each on its own line.  A line with nothing to
  -- say is skipped rather than left blank, so a move with no type behind it
  -- -- a mod's, or an id with no definition -- closes the gap instead of
  -- printing a hole.
  local function drawPanel(state, moves, selected, small)
    Chrome.box(PANEL.tx, PANEL.ty, PANEL.tw, PANEL.th)
    local x, width = (PANEL.tx + 1) * 8, (PANEL.tw - 2) * 8
    local rows = {}
    for i = 1, PANEL.th - 2 do rows[i] = (PANEL.ty + i) * 8 end

    local line = 1
    local function put(text, ink, face)
      if not text or not rows[line] then return end
      drawLabel({ text = text, ink = ink }, x, rows[line], width, face)
      line = line + 1
    end

    local move = moves and moves[selected]
    local def = moveDef(state, move)
    -- The panel reads the name whole, in the game's own font.  That is what
    -- the twelve interior tiles are for -- see PANEL -- so nothing here
    -- shortens and nothing here changes face unless the buttons did.
    put(def and def.name or (move and tostring(move.id)) or "-", nil, small)

    -- A disabled slot says so instead of showing what it would have cost,
    -- which is what the cart's own MoveInfoBox does.
    if disabled(state, move) then
      put(Strings("Disabled!"))
      return
    end
    put(typeText(state, def), typeInkFor(def))
    put(ppText(move))
  end

  -- ------- whose strip it is

  local function isTop(state)
    local stack = state.game and state.game.stack
    if not (stack and stack.top) then return true end
    local ok, top = pcall(stack.top, stack)
    if not ok then return true end
    return top == state
  end

  -- Deliberately narrow: one of the two menus, on top of the stack, outside a
  -- contest, with that menu's own option on.  Every other phase -- above all
  -- "messages" -- is left exactly as the cart draws it, which is the whole of
  -- how dialogue takes the strip back.
  function Gen2.owns(state)
    if type(state) ~= "table" then return false end
    local option = OWNED[state.phase]
    if not option then return false end
    if state.contest then return false end
    if not state.battle then return false end
    if mod.options:get(option) == false then return false end
    if state.phase == "menu" and type(state.menuLabels) ~= "function" then
      return false
    end
    if state.phase == "moves" and type(state.playerMoves) ~= "function" then
      return false
    end
    return isTop(state)
  end

  function Gen2.draw(state)
    if not Gen2.owns(state) then return end
    if state.phase == "menu" then
      fill(commandLabels(state), state.menuIndex or 1)
      C.white()
      return
    end
    local moves = state:playerMoves()
    local selected = state.moveIndex or 1
    local labels = moveLabels(state, moves)
    -- One face for the whole screen, and it is the CELLS' face: sized from
    -- the panel instead, the same name would come out larger up there than on
    -- the button it describes.
    local small = faceFor(labels)
    if C.option("move_panel", true) then
      drawPanel(state, moves, selected, small)
    end
    fill(labels, selected, state.moveSwapIndex, small)
    C.white()
  end

  function Gen2.install()
    -- next() runs first and its answer is kept: a mod that has already hidden
    -- the battle's bottom layer means it.
    mod.hooks:wrap("battle.bottom_ui_visible", function(next, state)
      local visible = next(state)
      if not Gen2.owns(state) then return visible end
      return false
    end)

    -- Gold's move list is navigated up and down; a 2x2 is navigated in four
    -- directions, and the cart already knows how -- it just has to be told
    -- that this one is a grid.
    mod.hooks:wrap("battle.move_grid_navigation", function(next, state)
      local upstream = next(state)
      if type(state) == "table" and state.phase == "moves"
         and Gen2.owns(state) then
        return true
      end
      return upstream
    end)

    -- Draw-only, and last.  A throw here is a frame with no menu on it rather
    -- than a crash, so it is caught: there is no version of "the battle
    -- stops" that is better than "the buttons are missing and the log says
    -- why".  The priority matches the Gen 1 arm's for the same reason -- a
    -- chain is run highest-first and outermost, and this link draws AFTER
    -- next(), so the highest priority is the one drawn on top.
    mod.hooks:wrap("battle.overlay", function(next, state)
      next(state)
      local ok, problem = pcall(Gen2.draw, state)
      if not ok and mod.log and type(mod.log.warn) == "function" then
        mod.log:warn("Gen1BattleUI could not draw the battle menu: %s",
                     tostring(problem))
      end
    end, 5000)
  end

  return Gen2
end
