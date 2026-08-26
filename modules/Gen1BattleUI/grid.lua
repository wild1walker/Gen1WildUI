-- Gen1BattleUI: where the four buttons go, and what goes in them.
--
-- Returns a factory: factory(mod, C) -> { owns, draw, gridNavigation }.
--
-- ------- what this replaces
--
-- The engine draws the battle's bottom strip in one function per layout --
-- BattleState:drawTextArea for the classic 160x144 screen, WideBattle's own
-- drawTextArea for the 304x144 one -- and both open by drawing a box across
-- the whole strip and then printing into it.  The command menu is four words
-- in one box with a hand beside the current one; the classic move menu is a
-- list of four, one per line.  This mod leaves both functions alone and does
-- not replace either: it asks the engine not to draw the strip while the
-- menus are up (battle.bottom_ui_visible), and draws its own into the seam
-- the engine already has for exactly this (battle.overlay, which runs last,
-- in the same coordinates, under both layouts).
--
-- Nothing about what the menus DO is touched.  menuIndex, moveIndex and
-- mimicIndex are still the engine's, still mean what they meant, and are
-- still moved by the engine's own input handling -- which already reads the
-- command menu as a 2x2 (col = (i-1)%2, row = (i-1)//2), and reads the move
-- menu as one when battle.move_grid_navigation says so.  So the grid was
-- already there in the numbers; this is the drawing catching up with it.
--
-- ------- the two layouts get there differently
--
-- A Game Boy text box spends its first and last tile row on the border, so a
-- box with one 8-pixel line of text in it is three tile rows, and two rows of
-- buttons is six.
--
--   CLASSIC has six.  Rows 12-17, twenty tiles wide: four 10x3 boxes tile it
--           exactly, each one a button with a border of its own.
--
--   WIDE has five.  Rows 13-17, and six do not fit in five without eating a
--        row of battlefield.  So instead of four boxes it is one box ruled
--        into four cells with its own border glyphs -- five rows being
--        exactly border, text, rule, text, border.  Same grid, same cells,
--        one shared frame instead of four.
--
-- Both end at the same place: four cells, each one tile row of text, each
-- with its first interior tile kept for the hand so that nothing shifts
-- sideways when the cursor arrives.
--
-- ------- and the move panel
--
-- Two by two inside 160 pixels costs move names their width: a classic cell
-- has seven glyphs of label where the vanilla list had fourteen, so
-- THUNDERBOLT arrives as THUNDER.  The panel above the grid buys some of that
-- back -- nine glyphs, plus the type and the PP, which the vanilla list never
-- showed at once -- and it buys only some, because it keeps the footprint of
-- the vanilla box it replaces and the player's own HUD is what lives in the
-- pixels either side of it.  See PANEL.  The wide layout's cells are twelve
-- glyphs and need none of this; it gets the panel anyway, because a mod that
-- reads differently on the other layout is two mods.

return function(mod, C)
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local TypeChart = require("src.battle.TypeChart")

  local Grid = {}

  -- The three phases whose bottom strip is a menu rather than a message.
  -- Everything else -- and above all "messages" -- is left exactly as the
  -- engine draws it, which is what makes dialogue take the strip back on its
  -- own: it is still the engine's text box, in the engine's own box, and the
  -- buttons are simply not drawn while it is up.
  local OWNED = { menu = true, moveSelect = true, mimicSelect = true }

  -- The engine calls the visibility hook every frame on its way to drawing
  -- the strip, so the last answer the REST of the chain gave is always fresh
  -- by the time the overlay runs.  Kept off the battle object and behind weak
  -- keys: a finished battle should not be held alive by this.
  local upstream = setmetatable({}, { __mode = "k" })

  function Grid.rememberUpstream(battle, visible)
    upstream[battle] = visible ~= false
  end

  -- ------- whose strip is it
  --
  -- The phase alone does not mean the menu is on screen.  A battle with a
  -- screen open above it is still a battle whose strip is being drawn, and
  -- claiming it would hide the prompts that screen puts there: the visibility
  -- hook is inherited by every text box above the battle
  -- (src/battle/UIVisibility.lua), so a false meant for our own menu would
  -- take the party menu's "Do what with X?" with it.
  --
  -- Being top of the stack is the question actually being asked, and it is
  -- the same one the wide layout asks itself before anchoring its HUD.
  local function isTop(battle)
    local stack = battle.game and battle.game.stack
    if not (stack and stack.top) then return true end
    return stack:top() == battle
  end

  function Grid.owns(battle)
    if type(battle) ~= "table" or not battle.isBattle then return false end
    if not OWNED[battle.phase] then return false end
    if not isTop(battle) then return false end
    return true
  end

  -- ------- and the third state: parked
  --
  -- ITEM does not leave the menu, it opens the bag ON it.  The bag's list is
  -- the one list in the game that is not a screen of its own -- itemBox in
  -- src/ui/ListMenu.lua, isOpaque = false, "a partial box the map stays
  -- visible around" -- and it is sixteen tiles at (4,2), so it stops at y=103
  -- and the strip underneath it is still on screen.  What the engine draws
  -- there is an empty text box, because openItems sets phase to "messages"
  -- with nothing to say; what should be there is the menu it was opened from,
  -- still showing, with the hand left hollow on ITEM the way every list in
  -- this game marks the row it is acting on.
  --
  -- This state is NOT claimed, and that is the whole design of it.  Returning
  -- false for the battle would take the bag's own text boxes down with it --
  -- "How many?", the YES/NO, the use message -- because every box above a
  -- battle inherits the battle's answer (src/battle/UIVisibility.lua).  So
  -- the engine keeps drawing its empty box and the buttons are drawn OVER it
  -- in the overlay, which lands in the same pixels: the four button boxes
  -- tile exactly the twenty-by-six that empty box occupies.
  --
  -- PKMN is the same code path and is never seen down it: PartyMenu is opaque
  -- (src/ui/PartyMenu.lua), so the stack stops drawing at it and the battle
  -- underneath -- this overlay included -- never runs at all.
  function Grid.parked(battle)
    if type(battle) ~= "table" or not battle.isBattle then return false end
    if battle.phase ~= "messages" then return false end
    -- the menu is what we come back to, which is what makes it still the menu
    if battle.afterQueue ~= "menu" then return false end
    if isTop(battle) then return false end
    -- An empty text box is one thing to draw over; a box with words in it is
    -- the box doing its own job, and buttons over the top of it would take
    -- the words away.  Same three the engine tests before printing into it.
    if battle.current or battle.animPlaying or battle.msgHold then return false end
    local index = battle.menuIndex
    return type(index) == "number" and index >= 1 and index <= 4
  end

  -- ------- the words
  --
  -- Through Strings, with the context the site being replaced used, so a
  -- translation keeps answering.  The classic layout keys its three commands
  -- on the "battle" context and the wide layout does not; that difference is
  -- the engine's, and copying it is what keeps both looking up what they
  -- looked up before.

  local function word(key, ctx)
    if ctx then return Strings(key, ctx) end
    return Strings(key)
  end

  local function commandLabels(battle, ctx)
    if battle.safari then
      -- DisplayBattleMenu prints wNumSafariBalls straight after the label,
      -- two digits, space padded (engine/battle/core.asm:2074-2079).
      return {
        { text = Strings("BALLx") .. ("%2d"):format(battle.safari.balls or 0) },
        { text = Strings("BAIT") },
        { text = Strings("THROW ROCK") },
        { text = word("RUN", ctx) },
      }
    end
    return {
      { text = word("FIGHT", ctx) },
      { codes = C.PKMN },
      { text = word("ITEM", ctx) },
      { text = word("RUN", ctx) },
    }
  end

  -- Four labels whatever the party has: an empty slot prints '-', the way
  -- the vanilla list does (engine/battle/misc.asm:37), and an id with no
  -- definition behind it -- a mod-injected move -- prints raw rather than
  -- bringing the battle down.
  local function moveLabels(battle, moves)
    local out = {}
    for i = 1, 4 do
      local move = moves and moves[i]
      if move then
        local def = battle.data and battle.data.moves and battle.data.moves[move.id]
        out[i] = { text = def and def.name or tostring(move.id),
                   ink = C.option("type_colour", true)
                         and C.typeInk(def and def.type) or nil }
      else
        out[i] = { text = "-" }
      end
    end
    return out
  end

  local function moveDef(battle, move)
    if not move then return nil end
    return battle.data and battle.data.moves and battle.data.moves[move.id]
  end

  local function maxPP(def, move)
    if not def then return 0 end
    return def.pp + (move.ppUps or 0) * math.floor(def.pp / 5)
  end

  local function ppText(def, move)
    if not (def and move) then return nil end
    return ("PP %2d/%2d"):format(move.pp or 0, maxPP(def, move))
  end

  local function typeText(def)
    if not (def and def.type) then return nil end
    local ok, name = pcall(TypeChart.displayName, def.type)
    return ok and name or nil
  end

  -- ------- the cells
  --
  -- Every cell is a tile row of interior with its first tile kept for the
  -- hand, so labelX is one tile in from handX and labelW is what is left.
  -- Reserving the column whether or not the hand is there is what stops the
  -- three unselected labels from sliding sideways as the cursor moves.

  -- What a cell leaves for its label: its interior tiles less the one kept
  -- for the hand.  Named because faceFor needs them BEFORE the cells are
  -- built -- classicGrid draws its boxes as it goes, and the panel has to be
  -- drawn under them with the face already decided.
  local CLASSIC_LABEL_W = 7 * 8        -- a 10-tile box: 8 interior, 1 hand
  local WIDE_LABEL_W = 12 * 8          -- the 29-tile move box
  local WIDE_FULL_LABEL_W = 16 * 8     -- the 38-tile one, narrower column

  local function cell(firstTile, lastTile, tileRow)
    return {
      handX = firstTile * 8,
      textY = tileRow * 8,
      labelX = (firstTile + 1) * 8,
      labelW = (lastTile - firstTile) * 8,
    }
  end

  -- CLASSIC: four 10x3 boxes tiling rows 12-17.
  local CLASSIC_BOXES = { { 0, 12 }, { 10, 12 }, { 0, 15 }, { 10, 15 } }

  local function classicGrid()
    local cells = {}
    for i, box in ipairs(CLASSIC_BOXES) do
      local tx, ty = box[1], box[2]
      C.box(tx, ty, 10, 3)
      -- tx..tx+9 is the box; tx and tx+9 are its border columns, so the
      -- interior is tx+1..tx+8 -- the hand's tile and seven of label.
      cells[i] = cell(tx + 1, tx + 8, ty + 1)
    end
    return cells
  end

  -- WIDE: one box, ruled into four.  `dividerCol` is the interior tile the
  -- vertical rule lands on; the cells are what is left either side of it.
  local function wideGrid(tx, ty, tw, dividerCol)
    C.box(tx, ty, tw, 5)
    C.quarter(tx, ty, tw, 5, dividerCol)
    local first = { tx + 1, dividerCol + 1 }
    local last = { dividerCol - 1, tx + tw - 2 }
    local cells = {}
    for i = 1, 4 do
      local col = (i - 1) % 2
      local row = math.floor((i - 1) / 2)
      cells[i] = cell(first[col + 1], last[col + 1], ty + 1 + row * 2)
    end
    return cells
  end

  -- ------- filling them in

  -- The small face is chosen for the WHOLE grid or for none of it.  Deciding
  -- per label would leave GUST in the game's own font beside THUNDERSHOCK in
  -- another one, in the same four boxes -- which reads as a rendering fault
  -- rather than as a choice.  So: if every name fits the tile font, nothing
  -- changes and the grid is vanilla to the pixel; if any name does not, they
  -- all move together.
  local function faceFor(width, labels)
    if not C.option("full_names", true) then return nil end
    if not width then return nil end
    local needed = false
    for i = 1, 4 do
      local label = labels[i]
      if label and label.text and C.width(label.text) > width then
        needed = true
        break
      end
    end
    if not needed then return nil end
    return C.small(width)
  end

  local function fill(cells, labels, selected, swap, small)
    for i = 1, 4 do
      local c, label = cells[i], labels[i]
      if c and label then
        C.drawLabel(label, c.labelX, c.textY, c.labelW, small)
      end
    end
    -- The filled hand replaces the hollow swap marker when they share a cell:
    -- PlaceMenuCursor writes the filled one into the tilemap over it
    -- (home/window.asm:184-185), and drawCode blits black on transparent, so
    -- stacking the two would merge them into one smear (#814).
    if swap and swap ~= selected and cells[swap] then
      C.drawHand(C.SWAP, cells[swap].handX, cells[swap].textY)
    end
    -- No selected cell is the parked case: the hollow marker is on the
    -- command whose screen is open, and there is no filled hand anywhere
    -- because the cursor is not in this grid any more.
    if selected and cells[selected] then
      C.drawHand(C.HAND, cells[selected].handX, cells[selected].textY)
    end
  end

  -- The old-man / PROF.OAK catch demo has no player behind the menu and no
  -- input either: DisplayBattleMenu's scripted hand sits on FIGHT for eighty
  -- frames and then on ITEM (engine/battle/core.asm:2038-2049).  Slots 1 and
  -- 3, which is what those two are in a 2x2.
  local function selectedCommand(battle)
    if battle.demo then
      return (battle.demoTimer or 0) <= 80 and 1 or 3
    end
    return battle.menuIndex or 1
  end

  -- ------- the move panel
  --
  -- Classic: full width, sitting flush on top of the grid.  The vanilla
  -- TYPE/PP box is at (0,8) and the vanilla Mimic list at (0,7), and the
  -- engine clips the player's picture to whichever of those rows is in play
  -- while it is up -- so a panel starting on the same row covers exactly what
  -- vanilla covered, which is why these two are one row apart.

  -- The panel is three rows -- name, type, PP, each on its own line -- and
  -- stops fourteen tiles in, at x=111.
  --
  -- Fourteen is the smallest width that still prints a move name whole.
  -- Twelve interior tiles is twelve glyphs of the game's own font, and Gen 1's
  -- longest names -- THUNDERSHOCK, QUICK ATTACK, SELFDESTRUCT -- are exactly
  -- twelve.  Narrower reads better and cuts names, and a cut name is the one
  -- thing this panel exists to prevent, so narrower is wrong however much
  -- tidier it looks.
  --
  -- It is still 48 pixels short of the full width it used to run to, which is
  -- what keeps the EXP bar another mod draws under the player's HUD -- from
  -- about x=98 -- mostly beside the panel rather than across it.  The last
  -- stretch of that bar does still cross the PP row, in white space to the
  -- right of the numbers; closing that gap entirely would mean cutting names.
  --
  -- mimicSelect keeps its own wider box: WHICH TECHNIQUE? is sixteen glyphs
  -- and has to go somewhere.
  local PANEL = {
    moveSelect = { tx = 0, ty = 8, tw = 14, th = 5 },
    mimicSelect = { tx = 0, ty = 7, tw = 18, th = 6 },
  }

  local function drawClassicPanel(battle, moves, selected, small)
    local spec = PANEL[battle.phase]
    if not spec then return end
    C.box(spec.tx, spec.ty, spec.tw, spec.th)

    local x, width = (spec.tx + 1) * 8, (spec.tw - 2) * 8
    local rows = {}
    for i = 1, spec.th - 2 do rows[i] = (spec.ty + i) * 8 end

    -- Lines are filled top-down and a line with nothing to say is skipped
    -- rather than left blank, so a move with no type behind it (a mod's, or
    -- an id with no definition) closes the gap instead of printing a hole.
    local line = 1
    local function put(text, small)
      if not text or not rows[line] then return end
      if small then
        C.drawSmall(small,
          C.shortenWith(function(t) return C.smallWidth(small, t) end,
                        text, width), x, rows[line])
      else
        C.black()
        Font.draw(C.shorten(text, width), x, rows[line])
      end
      line = line + 1
    end

    local move = moves and moves[selected]
    local def = moveDef(battle, move)

    if battle.phase == "mimicSelect" then put(Strings("WHICH TECHNIQUE?")) end
    -- The panel reads the name whole, in the game's own font.  That is what
    -- the twelve interior tiles are for -- see PANEL -- so nothing here
    -- shortens and nothing here changes face.
    put(def and def.name or (move and tostring(move.id)) or "-", small)

    -- A disabled slot says so instead of showing what it would have cost:
    -- the vanilla panel does the same (engine/battle/core.asm, PrintMenuItem).
    if battle.phase ~= "mimicSelect" and battle.player
       and battle.player.disabledSlot == selected then
      put(Strings("disabled!"))
      return
    end
    -- The type is printed in its own colour -- the letters, not a field
    -- behind them.  See C.inked for how a tile glyph is coloured at all.
    local type_ = typeText(def)
    if type_ and rows[line] then
      local text, ty = C.shorten(type_, width), rows[line]
      local ink = C.option("type_colour", true) and C.typeInk(def and def.type)
      C.inked(ink, function() Font.draw(text, x, ty) end)
      line = line + 1
    end
    put(ppText(def, move))
  end

  -- Wide: the panel the wide layout already had, in the place it already
  -- had it -- ten tiles on the right of the strip, PP over type.
  local function drawWidePanel(battle, moves, selected)
    C.box(28, 13, 10, 5)
    local move = moves and moves[selected]
    local def = moveDef(battle, move)
    if not def then return end
    if battle.phase ~= "mimicSelect" and battle.player
       and battle.player.disabledSlot == selected then
      C.black()
      Font.draw(C.shorten(Strings("disabled!"), 64), 232, 112)
      return
    end
    local pp, type_ = ppText(def, move), typeText(def)
    C.black()
    if pp then Font.draw(C.shorten(pp, 64), 232, 112) end
    if type_ then
      local text = C.shorten(type_, 64)
      local ink = C.option("type_colour", true) and C.typeInk(def.type)
      C.inked(ink, function() Font.draw(text, 232, 128) end)
    end
  end

  -- ------- the two layouts

  local function drawClassic(battle, parked)
    if parked then
      fill(classicGrid(), commandLabels(battle, "battle"),
           nil, battle.menuIndex)
      return
    end
    if battle.phase == "menu" then
      fill(classicGrid(), commandLabels(battle, "battle"),
           selectedCommand(battle))
      return
    end
    local mimic = battle.phase == "mimicSelect"
    local moves = mimic and battle.mimicMoves or battle.player.curMoves
    local selected = (mimic and battle.mimicIndex or battle.moveIndex) or 1
    -- One face for the whole screen, and it is the CELLS' face: sized from
    -- the panel instead, the same name would come out larger up there than
    -- on the button it describes.
    local labels = moveLabels(battle, moves)
    local small = faceFor(CLASSIC_LABEL_W, labels)
    if C.option("move_panel", true) then
      drawClassicPanel(battle, moves, selected, small)
    end
    fill(classicGrid(), labels, selected,
         not mimic and battle.moveSwapIndex or nil, small)
  end

  local function drawWide(battle, parked)
    if battle.phase == "menu" or parked then
      -- parked puts the hollow marker on the command whose screen is open and
      -- no filled hand anywhere; the live menu is the other way round.
      local hand, mark
      if parked then mark = battle.menuIndex else hand = selectedCommand(battle) end
      if battle.safari then
        -- The safari menu has no prompt to make room for -- the ball count
        -- rides in the menu itself -- so it takes the whole strip.
        fill(wideGrid(0, 13, 38, 18), commandLabels(battle), hand, mark)
        return
      end
      -- The prompt on the left, the buttons on the right, splitting the
      -- thirty-eight tiles evenly rather than 20/18: an even split is what
      -- puts the vertical rule in the middle of the button box, so the two
      -- columns come out the same width.
      C.box(0, 13, 19, 5)
      if not battle.demo then
        -- makeOldManDemo parks the wild mon in battle.player as a
        -- placeholder, so naming it here would print "What will PIKACHU do?"
        -- over Oak's scripted throw (#557).  The classic layout never names
        -- anyone in the demo either.
        local tail = Strings(" do?")
        local who = C.shorten(battle.player and battle.player.name or "",
                              136 - C.width(tail))
        C.black()
        Font.draw(Strings("What will"), 8, 112)
        Font.draw(who .. tail, 8, 128)
      end
      fill(wideGrid(19, 13, 19, 28), commandLabels(battle), hand, mark)
      return
    end
    local mimic = battle.phase == "mimicSelect"
    local moves = mimic and battle.mimicMoves or battle.player.curMoves
    local selected = (mimic and battle.mimicIndex or battle.moveIndex) or 1
    local swap = not mimic and battle.moveSwapIndex or nil
    -- Without the panel there is nothing to leave ten tiles for, and a strip
    -- that stops short of the screen edge is a hole in the frame rather than
    -- a saving: the grid takes the whole width back instead.
    if not C.option("move_panel", true) then
      local labels = moveLabels(battle, moves)
      local small = faceFor(WIDE_FULL_LABEL_W, labels)
      fill(wideGrid(0, 13, 38, 18), labels, selected, swap, small)
      return
    end
    local labels = moveLabels(battle, moves)
    fill(wideGrid(0, 13, 29, 14), labels, selected, swap,
         faceFor(WIDE_LABEL_W, labels))
    drawWidePanel(battle, moves, selected)
  end

  function Grid.draw(battle)
    local parked = Grid.parked(battle)
    if not (Grid.owns(battle) or parked) then return end
    -- Another mod that has hidden the battle's bottom layer -- a cutscene, a
    -- screenshot mode -- meant it, and a menu drawn over the top of that is
    -- this mod losing an argument it should not have been in.
    if upstream[battle] == false then return end
    -- Only the move grids read curMoves; the command grid and the parked one
    -- are four fixed words and do not care whether there is a party at all.
    if not parked and battle.phase ~= "menu"
       and not (battle.player and battle.player.curMoves) then
      return
    end
    if battle:wideLayout() then
      drawWide(battle, parked)
    else
      drawClassic(battle, parked)
    end
    C.white()
  end

  -- The classic layout's move list is navigated up and down; its 2x2 is
  -- navigated in four directions, which is what this hook is for and what the
  -- wide layout already answers on its own.
  function Grid.gridNavigation(battle)
    return Grid.owns(battle) and battle.phase ~= "menu"
  end

  -- Published so the suite can assert against the numbers this file draws
  -- from rather than against a screenshot, and so a mod that wants to sit
  -- beside these buttons can find out where they are.  Tile coordinates
  -- throughout, matching Font.drawBox.
  Grid.geometry = {
    classic = {
      boxes = CLASSIC_BOXES, boxW = 10, boxH = 3,
      handTiles = 1, labelTiles = 7,
      -- the vanilla box each panel stands in for, in tile coordinates
      panel = { moveSelect = { tx = 0, ty = 8, tw = 11, th = 5 },
                mimicSelect = { tx = 0, ty = 7, tw = 18, th = 6 } },
    },
    wide = {
      row = 13, th = 5,
      prompt = { tx = 0, tw = 19 },
      command = { tx = 19, tw = 19, divider = 28, labelTiles = 7 },
      moves = { tx = 0, tw = 29, divider = 14, labelTiles = 12 },
      movesFull = { tx = 0, tw = 38, divider = 18 },
      safari = { tx = 0, tw = 38, divider = 18 },
      panel = { tx = 28, tw = 10 },
    },
  }

  return Grid
end
