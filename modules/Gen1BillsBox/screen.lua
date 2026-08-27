-- Gen1BillsBox: the storage screen itself.
--
-- Returns a factory: factory(mod) -> { new = function(game) ... end }, which
-- main.lua installs over the builtin "BoxMenu" id.
--
-- ------- the shape of the screen
--
--   rows 0-2    the box header: BOX n, how full it is, and the two arrows
--   rows 3-14   the party down the left, the open box as a 5x4 grid
--   rows 15-17  one line naming what the cursor is on
--
-- 160x144 and nothing else.  Twenty cells of 24x24 and six party rows of 16
-- fill the same 96 pixels between the header and the footer, and every one of
-- those numbers is a whole count of 8-pixel tiles.  That is a hard
-- requirement rather than tidiness: an SGB palette zone is addressed in
-- tiles, so a cell that is three and a half tiles wide cannot carry one, and
-- carrying one per cell is what gives every POKeMON in the box its own
-- species colours.
--
-- ------- black lines, coloured POKeMON
--
-- Everything this screen draws itself is shade 3, the darkest DMG shade,
-- which is {0,0,0} in the grey ramp and in all 151 species palettes alike.
-- So the chrome is black under any zone, and a species palette laid over a
-- cell reaches the POKeMON in it and nothing else.  Shade 1 is the trap:
-- MEWMON, the palette the PC's other screens wear, paints it {239,156,107},
-- which is how a grey grid line comes out orange.
--
-- ------- why the slots hold party icons
--
-- Because that is the seam every icon mod already writes to.
-- `PartyMenu.drawIcon` is the engine's one canonical icon path: it folds the
-- icons registry, a species record's own `icon` field, asset overrides and
-- the `pokemon.icon` hook together, then bakes OBP0 and mirrors the frame
-- the way the hardware's OAM did.  Calling it -- rather than re-resolving
-- art here -- is what makes a menu-icon mod show up in the box for free, and
-- what keeps this screen honest when one changes.
--
-- The animation frame is chosen HERE and passed as `forceAlt` rather than
-- letting drawIcon derive it from the mon: its own speed rule reads
-- mon.stats.hp, and a Gen 1 box mon legitimately has no stat block at all
-- (box_struct stops before MON_STATS -- see Stats.ensure).  One boolean
-- avoids ever handing that path a mon it cannot measure.
--
-- ------- what a slot means
--
-- Gen 1 stores a box as a COMPACT array (src/pokemon/Boxes.lua): box[1..n]
-- with nothing after n.  That shape is untouched -- it is the save format,
-- the engine's own deposit appends to it, and it is what is left behind if
-- this mod is removed.  But it cannot express a GAP, and a grid you cannot
-- leave a gap in is not a grid: pick the second POKeMON out of six and the
-- other four slide up behind it.
--
-- So the ARRANGEMENT is kept beside the box instead, in this mod's own save
-- data: one grid cell per POKeMON, reconciled with the box on every read.
-- A POKeMON picked up leaves its cell empty, one put down lands in the cell
-- you aimed at, and the others do not move.  See "where in the grid each
-- POKeMON sits" below.
--
-- The PARTY takes gaps too, but only while you are looking at it, and by a
-- different mechanism: save.party is never sparse, only which ROW each member
-- is drawn in, and the array is kept sorted by that row.  Party order is
-- BATTLE order, so those two must never drift apart -- and keeping them
-- together means closing the screen has nothing to collapse.  See "and where
-- in the PARTY pane each one sits".
--
-- ------- the cursor
--
-- In the grid it is a triangle in the band above a POKeMON's head, pointing
-- down at it, and the same triangle hollow while that POKeMON is in your
-- hand.  In the party it is the sideways cursor at the left of the row, the
-- party menu's own $ED / $EC pair, because six rows of sixteen fill the pane
-- exactly and leave no band above a head to put an arrow in.

return function(mod)
  local Boxes = require("src.pokemon.Boxes")
  local Font = require("src.render.Font")
  local Menu = require("src.ui.Menu")
  local Party = require("src.pokemon.Party")
  local PartyMenu = require("src.ui.PartyMenu")
  local Screens = require("src.ui.Screens")
  local Sprites = require("src.pokemon.Sprites")
  local Stats = require("src.pokemon.Stats")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local Theme = require("src.ui.Theme")

  -- ------- geometry

  -- ------- everything here is a whole number of 8-pixel tiles
  --
  -- Not for tidiness: an SGB palette zone is ADDRESSED in tiles
  -- (PaletteFX.zone takes tile coordinates), so a cell that is three and a
  -- half tiles wide cannot carry one at all.  Giving every POKeMON on this
  -- screen its own species colours is what forces 24 rather than 26, and it
  -- is the whole reason the grid moved right by two pixels.
  local COLS, ROWS = 5, 4
  local CELL_W, CELL_H = 24, 24         -- 3x3 tiles
  local GRID_X, GRID_Y = 32, 24         -- tile 4, tile row 3

  local PARTY_ROWS = Party.MAX          -- 6
  local PARTY_H = 16                    -- 2 tile rows
  local PARTY_X, PARTY_Y = 8, 24        -- the icon column; the cursor sits at 0
  local RULE_X = 28                     -- the hairline between the two panes

  -- ------- the one place the cell has no slack
  --
  -- A cell is 24 wide with its own rule at 0 and its neighbour's at 24, so
  -- what the eye reads as the cell is the 23 pixels between them.
  --
  -- Horizontally that is roomy: a 16-pixel icon sits 3 in from one side and 4
  -- from the other, which is as centred as sixteen gets inside twenty-three.
  --
  -- Vertically it is not, and this is worth spelling out because getting it
  -- wrong once already cost a release.  The column has to hold a gap, the
  -- 4-pixel cursor, a gap, the 16-pixel icon and a gap, in 23 pixels -- three
  -- pixels of slack for three gaps.  Spending them anywhere but 1/1/1 takes a
  -- gap to zero, and the two that must not go to zero are the ends: an arrow
  -- with no gap above it is drawn ON the rule and reads as a smear on the
  -- grid rather than as a cursor, and an icon with no gap below it sits on the
  -- next rule.  1.0.4 spent all three on centring the icon and lost the arrow
  -- into the line above it.
  --
  -- So the icon is NOT vertically centred, deliberately: it is one pixel off
  -- the bottom rule with the cursor's band above it, which is the only
  -- arrangement that leaves every edge clear.
  local ICON = 16
  local ICON_DX = math.floor((CELL_W - ICON) / 2)   -- 4
  local ICON_DY = 7

  -- The cursor: a solid triangle pointing down at whatever is under it, and
  -- the same triangle hollow while a POKeMON is in hand.  Drawn rather than
  -- printed because the charmap has a down arrow ($EE) but no hollow twin of
  -- it -- the hollow/filled PAIR only exists for the sideways cursor.
  --
  -- Centred on the ICON rather than on the cell, because "above them" is what
  -- it is pointing at, and so the two stay together if either ever moves.
  local ARROW_DX = ICON_DX + math.floor((ICON - 7) / 2)  -- 8
  local ARROW_DY = 2

  local HEADER_TH = 3                   -- tiles
  local INFO_TY = 15                    -- tiles
  local INFO_TEXT_Y = (INFO_TY + 1) * 8 -- 128
  local TEXT_LEFT, TEXT_RIGHT = 8, 152

  -- Every pixel this screen draws itself is shade 3, the darkest of the four
  -- DMG shades.  That is what keeps the chrome BLACK: shade 3 is {0,0,0} in
  -- the grey ramp, in MEWMON, and in all 151 species palettes alike
  -- (data/palettes_gbc.lua), so a species zone laid over a cell colours the
  -- POKeMON in it and cannot touch the lines around it.  Shade 1 is the
  -- opposite -- MEWMON paints it {239,156,107} -- which is exactly how a
  -- grey grid line came out orange.
  local BLACK = { 0, 0, 0 }

  -- ui.list_menu's own hold-to-scroll cadence (src/ui/ListMenu.lua), in
  -- fixed steps, so a held direction here moves at the speed a held
  -- direction moves everywhere else in the game.
  local REPEAT_DELAY, REPEAT_RATE = 16, 5

  -- how many steps between the two icon frames; the party menu picks 5, 16
  -- or 32 off the mon's HP bar colour, and a storage grid has no bar to read
  local ANIM_STEPS = 8

  -- A POKeMON in your hand flashes.  Four shades cannot dim one, so it blinks
  -- the way everything on a Game Boy blinks: lit twice as long as it is dark,
  -- because the thing flashing is the thing you are trying to look at, but
  -- quick enough to read as a flash rather than as something switching on and
  -- off.  Sixteen steps lit and eight dark, at the engine's sixty a second.
  local FLASH_PERIOD, FLASH_ON = 24, 16

  -- One counter drives both, wrapped at a common multiple so neither jumps
  -- when it turns over.
  local TICKS = 240

  -- ------- options, read live so the manager's rows take effect at once

  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  -- ------- small helpers

  local function ink(shade)
    love.graphics.setColor(shade[1], shade[2], shade[3], 1)
  end

  -- ------- one arrow, three directions
  --
  -- The cursor in the grid, the box header's two arrows and the header's own
  -- selector are all THE SAME TRIANGLE, drawn on whichever axis is asked for:
  -- a long edge of 7 tapering to a point over 4.  They used to be two
  -- different shapes plus a font glyph, and the glyph was the worst of the
  -- three -- it sits inside an 8x8 cell with its own padding, so it could not
  -- be lined up with a triangle drawn beside it however the coordinates were
  -- nudged.
  --
  -- Hollow leaves the long edge and the two tapering sides, which is what
  -- reads as "outlined" rather than "smaller" at this size.
  local ARROW_LONG, ARROW_SHORT = 7, 4

  local function arrow(x, y, dir, hollow)
    for i = 0, ARROW_SHORT - 1 do
      local span = ARROW_LONG - i * 2
      local whole = not hollow or span <= 2 or i == 0
      if dir == "down" then
        local left = x + i
        if whole then
          love.graphics.rectangle("fill", left, y + i, span, 1)
        else
          love.graphics.rectangle("fill", left, y + i, 1, 1)
          love.graphics.rectangle("fill", left + span - 1, y + i, 1, 1)
        end
      else
        -- the same triangle a quarter turn round: columns instead of rows
        local px = dir == "right" and (x + i) or (x + ARROW_SHORT - 1 - i)
        if whole then
          love.graphics.rectangle("fill", px, y + i, 1, span)
        else
          love.graphics.rectangle("fill", px, y + i, 1, 1)
          love.graphics.rectangle("fill", px, y + i + span - 1, 1, 1)
        end
      end
    end
  end

  -- ------- the two pop-ups
  --
  -- Both of them are Menus, and Menu draws two things ONTO its own frame
  -- rather than inside it.  This takes both off the parent draw and puts
  -- them back where they belong; every Menu this screen pushes with a title
  -- or a scrollbar goes through here.
  --
  -- The title it writes at the very top of the border tile, so the glyphs'
  -- first pixel row lands on the single white pixel the frame keeps outside
  -- its rule and the letters read as touching the edge of the pop-up.  It is
  -- blanked before the parent draw and redrawn a pixel lower, with the same
  -- white-out Menu would have punched -- exactly as wide as the title, which
  -- is why the titles are padded a space each side: without that the rule
  -- runs into the first and last letter.  The row it gains at the bottom is
  -- the blank one under the top edge, so nothing else moves.
  --
  -- The "more below" glyph it sits on the bottom BORDER row, over the frame's
  -- own bottom rule and one tile from its corner.  The parent is handed a
  -- list that stops at the last visible row -- nothing left to point at, no
  -- glyph -- and the arrow is redrawn as this mod's own triangle in the spare
  -- interior column, clear of every edge.
  local function popup(menu)
    local baseDraw = menu.draw
    local title = menu.title
    local titleWidth = title and #Font.split(title) * 8 or 0
    local views = {}
    menu.draw = function(m)
      local all = m.items
      if m.maxVisible then
        local view = views[m.scroll]
        if not view then
          view = {}
          for i = 1, math.min(#all, m.scroll + m.maxVisible) do view[i] = all[i] end
          views[m.scroll] = view
        end
        m.items = view
      end
      m.title = nil
      local ok, err = pcall(baseDraw, m)
      m.items, m.title = all, title
      if not ok then error(err, 0) end

      if title then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", (m.tx + 3) * 8, m.ty * 8, titleWidth, 8)
        ink(BLACK)
        Font.draw(title, (m.tx + 3) * 8, m.ty * 8 + 1)
      end
      if m.maxVisible and m.scroll + m.maxVisible < #all then
        ink(BLACK)
        arrow((m.tx + m.tw - 2) * 8, (m.ty + m.th - 2) * 8 + 2, "down")
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    return menu
  end

  local function play(game, id)
    if not (game and game.data) then return end
    pcall(function() require("src.core.Sound").play(game.data, id) end)
  end

  local function cry(game, species)
    if not (game and game.data and species) then return end
    pcall(function() require("src.core.Sound").playCry(game.data, species) end)
  end

  local function follower()
    local ok, module = pcall(require, "src.world.PikachuFollower")
    if ok and type(module) == "table" then return module end
    return nil
  end

  local function defOf(game, mon)
    local pokemon = game.data and game.data.pokemon
    return mon and pokemon and pokemon[mon.species] or nil
  end

  local function nameOf(game, mon)
    if not mon then return "" end
    local def = defOf(game, mon)
    return mon.nickname or (def and def.name) or tostring(mon.species)
  end

  local function textOf(game)
    return (game.data and game.data.text) or {}
  end

  -- ------- which icons are full-colour art, and why it matters
  --
  -- The SGB pass this screen asks for remaps four DMG shades to four colours,
  -- keyed off each pixel's RED channel.  Run authored full-colour art through
  -- that and it does not come out recoloured, it comes out DESTROYED: an
  -- orange pixel has red near 1.0, lands on shade 0, and is painted the
  -- palette's white.  That is the whole of the reported bug -- BEEDRILL's
  -- orange going white, IVYSAUR's teal going green.
  --
  -- The engine's answer is PaletteFX.markTrueColor: a marked rect is appended
  -- to the zone list as a colours == false zone and re-blit with no shader
  -- over the colourised pass (Renderer's withTrueColor).  But nothing in
  -- PartyMenu.drawIcon marks anything -- the screens that draw full-colour art
  -- mark it themselves (SummaryMenu, TrainerCard, HallOfFame all do), and the
  -- party menu's own icons are marked by whichever mod supplied them.  This
  -- screen never did, which is why its icons were wrong from 1.0.0 on while
  -- the party menu's next door were right.
  --
  -- So decide per icon, and decide it the only way that cannot be fooled by
  -- HOW the art arrived (the icons registry, a species record's own `icon`, an
  -- asset override, the pokemon.icon hook): resolve what drawIcon will resolve,
  -- then look at the pixels.
  --
  -- A built-in icon CLASS is never full colour whatever file it points at,
  -- because drawIcon bakes those through obpIcon, which flattens every pixel
  -- to a grey keyed off its red channel.  Only a mod's own image -- an entry
  -- table rather than an icon name -- reaches the screen untouched.
  local iconColour = setmetatable({}, { __mode = "k" })  -- mon -> info
  local pathColour = {}                                  -- path -> info

  -- The same resolution order as PartyMenu.drawIcon, from the same public
  -- tables, so this cannot disagree with what is actually drawn.
  local function resolveIcon(game, mon)
    local icons = game.data and game.data.icons
    if not icons then return nil, nil end
    local def = defOf(game, mon)
    local entry = (icons.bySpecies and icons.bySpecies[mon.species])
      or (def and def.icon)
    local name, path
    if type(entry) == "string" then
      name = entry
      path = icons.icons and icons.icons[entry]
    elseif type(entry) == "table" then
      path = entry.image
    end
    if not path then
      name = def and def.dex and icons.byDex and icons.byDex[def.dex]
      path = name and icons.icons and icons.icons[name]
    end
    -- Sprites.iconPath raises pokemon.icon with the live mon, which is how a
    -- shiny tells itself apart from an ordinary one of its species
    local ok, hooked = pcall(Sprites.iconPath, game.data, mon, path,
                             { name = name })
    if ok then path = hooked end
    return name, path
  end

  -- Does this file carry a colour a grey ramp cannot?  Read once per path and
  -- remembered, because it is a property of the file.
  local function scanPath(path)
    local info = pathColour[path]
    if info ~= nil then return info end
    info = { colour = false, w = ICON, h = ICON }
    pcall(function()
      local data = require("src.render.Assets").imageData(path)
      local w, h = data:getDimensions()
      info.w, info.h = w, h
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local r, g, b, a = data:getPixel(x, y)
          if a > 0 and (math.abs(r - g) > 0.02 or math.abs(g - b) > 0.02) then
            info.colour = true
            return
          end
        end
      end
    end)
    pathColour[path] = info
    return info
  end

  -- nil when the icon is ordinary DMG art (colour it with a species zone), or
  -- the rect drawIcon will cover when it is full colour (mark it and leave it
  -- alone).  drawIcon takes a 16x16 frame out of a taller sheet and draws
  -- anything shorter whole, at whatever size the file is.
  local function fullColourRect(game, mon)
    if not mon then return nil end
    local hit = iconColour[mon]
    if hit == nil then
      local name, path = resolveIcon(game, mon)
      if not path or name then
        hit = false
      else
        local info = scanPath(path)
        hit = info.colour
          and { w = info.h > ICON and ICON or info.w,
                h = info.h > ICON and ICON or info.h }
          or false
      end
      iconColour[mon] = hit
    end
    return hit or nil
  end

  -- ------- where in the grid each POKeMON sits
  --
  -- Gen 1 stores a box as a COMPACT array (src/pokemon/Boxes.lua): box[1..n]
  -- with nothing after n.  That is the save format, it is what the engine's
  -- own deposit appends to, and it is what is left behind if this mod is ever
  -- removed -- so it stays exactly as it is.
  --
  -- What it cannot express is a GAP, and a grid you cannot leave a gap in is
  -- not really a grid: pick the second POKeMON out of six and the other four
  -- slide up behind it.  So the arrangement is kept beside the box rather
  -- than in it: `cells[j]` is the grid cell that `box[j]` sits in, one entry
  -- per POKeMON, stored in this mod's own save data.
  --
  -- The two are reconciled on EVERY read, which is what makes this safe to
  -- bolt onto a shared save.  Anything else may add to a box behind this
  -- screen's back -- a catch overflowing into it, another mod, an imported
  -- .sav -- and the arrangement simply grows to match: extra POKeMON take the
  -- lowest free cells, extra cells are dropped, and a cell that is out of
  -- range or claimed twice is thrown away.  The worst case is that the
  -- arrangement resets to the compact one nobody could see a gap in anyway.
  local SLOTS = COLS * ROWS

  local function layoutFor(save, boxNumber)
    local store = mod.save:get("cells")
    if type(store) ~= "table" then store = {} end
    -- one key shape whatever a serializer did with the number
    local key = tostring(boxNumber)
    local cells = store[key]
    if type(cells) ~= "table" then cells = store[boxNumber] end
    if type(cells) ~= "table" then cells = {} end
    store[boxNumber] = nil

    local list = Boxes.ensure(save)[boxNumber] or {}
    local seen, clean = {}, {}
    for j = 1, #cells do
      local cell = tonumber(cells[j])
      if cell and cell % 1 == 0 and cell >= 1 and cell <= SLOTS
          and not seen[cell] then
        seen[cell] = true
        clean[#clean + 1] = cell
      end
    end
    while #clean > #list do
      seen[clean[#clean]] = nil
      clean[#clean] = nil
    end
    local free = 1
    while #clean < #list do
      while seen[free] do free = free + 1 end
      seen[free] = true
      clean[#clean + 1] = free
    end

    store[key] = clean
    mod.save:set("cells", store)
    return clean
  end

  local function boxIndexAt(save, boxNumber, cell)
    local cells = layoutFor(save, boxNumber)
    for j = 1, #cells do
      if cells[j] == cell then return j end
    end
    return nil
  end

  local function boxMonAt(save, boxNumber, cell)
    local j = boxIndexAt(save, boxNumber, cell)
    if not j then return nil end
    return Boxes.ensure(save)[boxNumber][j]
  end

  -- Out of the box AND out of the arrangement, so the cell it was in is now
  -- an empty one rather than a place the rest slide into.
  local function boxTake(save, boxNumber, cell)
    local j = boxIndexAt(save, boxNumber, cell)
    if not j then return nil end
    table.remove(layoutFor(save, boxNumber), j)
    return table.remove(Boxes.ensure(save)[boxNumber], j)
  end

  -- Appended to both, which is why the compact array's ORDER never has to
  -- mean anything: the cell beside it is what says where the POKeMON is.
  local function boxPut(save, boxNumber, cell, mon)
    local list = Boxes.ensure(save)[boxNumber]
    local cells = layoutFor(save, boxNumber)
    list[#list + 1] = mon
    cells[#cells + 1] = cell
  end

  local function boxReplace(save, boxNumber, cell, mon)
    local j = boxIndexAt(save, boxNumber, cell)
    if not j then return nil end
    local list = Boxes.ensure(save)[boxNumber]
    local was = list[j]
    list[j] = mon
    return was
  end

  -- ------- sorting a box
  --
  -- Every sort ENDS the same way -- the box closed up into cells 1..n -- so
  -- COLLAPSE is just the sort that changes no order, and the others are that
  -- plus a reordering.  Which is also why COLLAPSE has to sort by the current
  -- CELL first: the compact array's order stopped meaning anything the moment
  -- gaps existed, so "keep what I can see, just close it up" is a sort like
  -- any other.
  --
  -- Every comparison falls back to the current cell, which makes each one
  -- stable in the way that matters to someone looking at it: POKeMON that tie
  -- keep the order they were already in.  table.sort is not itself stable, so
  -- the cell is carried alongside and used as the last word rather than hoped
  -- for.
  local SORT_LABELS = {
    { "COLLAPSE", "collapse" },
    { "BY DEX", "dex" },
    { "BY LEVEL", "level" },
    { "BY NAME", "name" },
    { "BY TYPE", "type" },
  }

  local function sortKey(game, mode, entry)
    local mon = entry.mon
    local def = defOf(game, mon)
    if mode == "dex" then return (def and def.dex) or math.huge end
    -- strongest first, which is what a box is usually being tidied for
    if mode == "level" then return -(tonumber(mon.level) or 0) end
    if mode == "name" then return nameOf(game, mon) end
    -- the primary type, alphabetically: the data carries type names rather
    -- than the cart's numbering, so there is no other order to honour
    if mode == "type" then
      local types = def and def.types
      return tostring(types and types[1] or "")
    end
    return entry.cell
  end

  -- Is this box still holding exactly the POKeMON the snapshot was taken of?
  -- Identity, not count: one released and one caught leaves the count alone
  -- and would otherwise let UNDO resurrect the released one.
  local function sameMembers(list, snapshot)
    if #list ~= #snapshot then return false end
    local left = {}
    for _, mon in ipairs(snapshot) do left[mon] = (left[mon] or 0) + 1 end
    for _, mon in ipairs(list) do
      local n = left[mon]
      if not n or n == 0 then return false end
      left[mon] = n - 1
    end
    return true
  end

  -- ------- and where in the PARTY pane each one sits
  --
  -- The same idea, and deliberately not the same mechanism.
  --
  -- A box's arrangement is SAVED, because a box is storage and a gap you left
  -- there is a decision.  The party's is not: it lives on the screen object,
  -- so it is gone the moment you close the box and the party is a list of six
  -- again -- which is what the rest of the game reads it as, every frame,
  -- everywhere.
  --
  -- So save.party is never sparse.  What is sparse is only which ROW each of
  -- its members is drawn in, and the array is kept SORTED BY THAT ROW after
  -- every change.  That last part is the whole safety of it: party order is
  -- BATTLE order -- party[1] is who you send out -- so an arrangement that let
  -- the visual order and the array order drift apart would quietly change who
  -- leads.  Sorted, the two can never disagree, and closing the screen needs
  -- to do nothing at all to "collapse" the party: it was already the list it
  -- looks like.
  local function partyRowsOf(screen)
    local list = screen:listFor("party")
    local rows = screen.partyRow
    -- trust it or rebuild it; there is no third state worth carrying, because
    -- nothing but this screen moves the party while this screen is open
    local ok = type(rows) == "table" and #rows == #list
    if ok then
      local last = 0
      for j = 1, #rows do
        local row = rows[j]
        if type(row) ~= "number" or row <= last or row > PARTY_ROWS then
          ok = false
          break
        end
        last = row
      end
    end
    if not ok then
      rows = {}
      for j = 1, #list do rows[j] = j end
      screen.partyRow = rows
    end
    return rows
  end

  local function partyIndexAtRow(screen, row)
    local rows = partyRowsOf(screen)
    for j = 1, #rows do
      if rows[j] == row then return j end
    end
    return nil
  end

  local function partyMonAtRow(screen, row)
    local j = partyIndexAtRow(screen, row)
    if not j then return nil end
    return screen:listFor("party")[j]
  end

  local function partyTake(screen, row)
    local j = partyIndexAtRow(screen, row)
    if not j then return nil end
    table.remove(partyRowsOf(screen), j)
    return table.remove(screen:listFor("party"), j)
  end

  -- Inserted at its SORTED position, not appended: that is what keeps the
  -- array order and the visual order the same thing.
  local function partyPut(screen, row, mon)
    local rows = partyRowsOf(screen)
    local at = #rows + 1
    for j = 1, #rows do
      if rows[j] > row then at = j break end
    end
    table.insert(rows, at, row)
    table.insert(screen:listFor("party"), at, mon)
  end

  local function partyReplace(screen, row, mon)
    local j = partyIndexAtRow(screen, row)
    if not j then return nil end
    local list = screen:listFor("party")
    local was = list[j]
    list[j] = mon
    return was
  end

  -- ------- the screen

  local Screen = {}
  Screen.__index = Screen

  -- A full-screen replacement: nothing under it draws, and the PC's own menu
  -- waits underneath for the B that closes this.
  Screen.isOpaque = true

  -- opts.onCancel is the engine's own start-menu idiom: every vanilla submenu
  -- takes one and calls it on B so the START menu comes back
  -- (RedisplayStartMenu, and `reopen` in src/ui/StartMenu.lua).  The PC pushes
  -- this screen with no opts at all, so B there still just uncovers the PC's
  -- own menu, which was already waiting underneath.
  function Screen.new(game, opts)
    Boxes.ensure(game.save)
    local self = setmetatable({}, Screen)
    self.game = game
    self.onCancel = type(opts) == "table" and opts.onCancel or nil
    -- "box" | "party" | "header"
    self.pane = option("startPane", "box") == "party" and "party" or "box"
    -- the pane the header came from, so DOWN goes back where you were
    self.lastPane = self.pane
    self.boxSlot = 1                 -- 1..20, the cell the cursor is on
    self.partySlot = 1               -- 1..6
    self.held = nil                  -- { mon, pane, index, box }
    self.blink = 0
    self.holdDir, self.holdFrames = nil, 0
    -- whether the party changed while this screen was open, which is the
    -- only reason to disturb the follower on the way out
    self.partyTouched = false
    -- one row per party member, in order, rebuilt fresh every time the screen
    -- opens -- a gap in the party is a working arrangement, not a decision to
    -- keep
    -- one step of undo for the last sort, for as long as this screen is open
    self.sortUndo = nil
    self.partyRow = {}
    for j = 1, #(game.save.party or {}) do self.partyRow[j] = j end
    return self
  end

  -- ------- colour
  --
  -- Two rules, and the screen falls out of them.
  --
  -- The BASE is the plain four DMG greys, so everything this screen draws
  -- itself -- boxes, grid, arrows, text, all shade 3 -- comes out black on
  -- white.  A named palette here does not: MEWMON, which is what the PC's
  -- other screens wear, paints shade 1 a salmon {239,156,107}, so a grey
  -- grid line under it is an orange grid line.
  --
  -- Then EACH POKeMON GETS ITS OWN, the way the battle screen and the summary
  -- screen give a mon its species palette.  Twenty-six zones is the point of
  -- the whole tile-aligned layout above: the Game Boy could show four
  -- palettes at once and this shows a box's worth.  A species palette is
  -- white / hue / hue / black, so laying one over a whole cell recolours the
  -- POKeMON and leaves the black lines around it alone.
  --
  -- Answering at all is not optional: this screen is opaque, so with no
  -- opinion of its own the topmost state that HAS one is the overworld
  -- underneath, and the box would come out wearing the map's palette.
  -- ------- the status tint
  --
  -- Gen1WildQOL's STATUS COLOURS feature owns one table of "what does this
  -- condition look like", so the box, the party and the dex all wear the same
  -- purple for poison and the same grey for fainted rather than three tables
  -- drifting apart.  It is asked here rather than copied; without that mod
  -- installed there is no tint and the cell is the species colours exactly as
  -- before.
  --
  -- Memoised only when found.  A negative is re-probed, because load order is
  -- not this mod's to know and a permanent no would be decided by whichever of
  -- us loaded first.
  local statusApi
  local function statusColours()
    if statusApi then return statusApi end
    local ok, found = pcall(function() return mod.find("gen1_wild_qol") end)
    local api = ok and found and found.exports and found.exports.statusColours
    if type(api) == "table" then statusApi = api end
    return statusApi
  end

  -- The condition as a draw colour, from the same mod that owns the palette
  -- one.  A palette zone reaches only art that goes through the shade-remap
  -- pass, and a full-colour icon pack sits that pass out by design -- so the
  -- zone below tints nothing at all for anyone running one.  Drawing the icon
  -- in a colour reaches both: LOVE multiplies an image by the current colour,
  -- so white is the untouched icon and this shifts its hue while keeping its
  -- own light and dark.  nil means draw it as it is.
  local function statusDrawColour(mon)
    if type(mon) ~= "table" then return nil end
    local api = statusColours()
    if not api or type(api.drawColour) ~= "function" then return nil end
    local ok, colour = pcall(api.drawColour, mon)
    if not ok or type(colour) ~= "table" then return nil end
    return colour
  end

  local function statusTinted(colors, mon)
    if not colors or type(mon) ~= "table" then return colors end
    local api = statusColours()
    if not api then return colors end
    local live = api.active
    if type(live) == "function" and not live() then return colors end
    local ok, key = pcall(api.keyFor, mon)
    if not ok or not key then return colors end
    local applied
    ok, applied = pcall(api.apply, colors, key)
    if not ok or type(applied) ~= "table" then return colors end
    return applied
  end

  function Screen:sgbPalettes(game)
    local ok, zones = pcall(function()
      local P = require("src.render.PaletteFX")
      local out = { P.whole(P.GRAYS) }

      local function paint(mon, tx1, ty1, tx2, ty2)
        if not mon then return end
        -- full-colour art is re-blit unshaded over this pass, so a species
        -- palette under it would be paint nobody ever sees
        if fullColourRect(game, mon) then return end
        local colors = statusTinted(P.monPal(game.data, mon.species), mon)
        local zone = colors and P.zone(colors, tx1, ty1, tx2, ty2)
        if zone then out[#out + 1] = zone end
      end

      -- the party icons, two tiles square each
      for i = 1, PARTY_ROWS do
        local ty = (PARTY_Y + (i - 1) * PARTY_H) / 8
        paint(self:monDrawnAt("party", i), PARTY_X / 8, ty,
              PARTY_X / 8 + 1, ty + 1)
      end

      -- the grid, three tiles square each
      for slot = 1, COLS * ROWS do
        local tx = (GRID_X + ((slot - 1) % COLS) * CELL_W) / 8
        local ty = (GRID_Y + math.floor((slot - 1) / COLS) * CELL_H) / 8
        paint(self:monDrawnAt("box", slot), tx, ty, tx + 2, ty + 2)
      end

      return out
    end)
    return ok and zones or nil
  end

  -- ------- the lists

  function Screen:listFor(pane)
    if pane == "party" then
      self.game.save.party = self.game.save.party or {}
      return self.game.save.party
    end
    return Boxes.active(self.game.save)
  end

  function Screen:capacityFor(pane)
    return pane == "party" and Party.MAX or Boxes.CAPACITY
  end

  function Screen:slotIndex(pane)
    return pane == "party" and self.partySlot or self.boxSlot
  end

  function Screen:monAt(pane)
    if pane == "party" then return partyMonAtRow(self, self.partySlot) end
    local save = self.game.save
    return boxMonAt(save, save.currentBox, self.boxSlot)
  end

  -- Which POKeMON is actually SHOWN in a given slot, which is not always the
  -- one the list holds: a carried POKeMON rides the cursor and covers the
  -- slot it is over.  Drawing and the palette pass both read this, so the
  -- colours can never come from a different POKeMON than the pixels.
  function Screen:monDrawnAt(pane, slot)
    if self.held and self.pane == pane and self:slotIndex(pane) == slot then
      return self.held.mon
    end
    if pane == "party" then return partyMonAtRow(self, slot) end
    local save = self.game.save
    return boxMonAt(save, save.currentBox, slot)
  end

  -- ------- talking to the player
  --
  -- The refusals are the game's own extracted lines in the game's own text
  -- box, at the coordinates every other refusal uses.  The PC session runs
  -- silent (BIT_NO_MENU_BUTTON_SOUND), so every box here says so.

  function Screen:say(text)
    self.game.stack:push(TextBox.new(self.game, text, nil, { noSound = true }))
  end

  -- ------- movement

  local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
  end

  -- Crossing between the panes lands where the eye already is: the row's
  -- centre line, resolved into the other pane's slot height.
  function Screen:toParty(row)
    local centre = GRID_Y + row * CELL_H + CELL_H / 2
    self.partySlot = clamp(math.floor((centre - PARTY_Y) / PARTY_H) + 1,
                           1, PARTY_ROWS)
    self.pane = "party"
  end

  function Screen:toBox(slot)
    local centre = PARTY_Y + (slot - 1) * PARTY_H + PARTY_H / 2
    local row = clamp(math.floor((centre - GRID_Y) / CELL_H), 0, ROWS - 1)
    self.boxSlot = row * COLS + 1
    self.pane = "box"
  end

  function Screen:moveBox(dir)
    local col = (self.boxSlot - 1) % COLS
    local row = math.floor((self.boxSlot - 1) / COLS)
    if dir == "left" then
      if col == 0 then self:toParty(row) else self.boxSlot = self.boxSlot - 1 end
    elseif dir == "right" then
      -- the party is off the left edge, so the right edge wraps within the
      -- row rather than stepping to the next box: box changes belong to the
      -- header, where they are visible
      self.boxSlot = col == COLS - 1 and (self.boxSlot - col) or (self.boxSlot + 1)
    elseif dir == "up" then
      if row == 0 then
        self.lastPane = "box"
        self.pane = "header"
      else
        self.boxSlot = self.boxSlot - COLS
      end
    elseif dir == "down" then
      self.boxSlot = row == ROWS - 1 and (col + 1) or (self.boxSlot + COLS)
    end
  end

  function Screen:moveParty(dir)
    if dir == "right" then
      self:toBox(self.partySlot)
    elseif dir == "up" then
      if self.partySlot == 1 then
        self.lastPane = "party"
        self.pane = "header"
      else
        self.partySlot = self.partySlot - 1
      end
    elseif dir == "down" then
      self.partySlot = self.partySlot < PARTY_ROWS and (self.partySlot + 1) or 1
    end
    -- LEFT out of the party is the screen edge and does nothing
  end

  function Screen:changeBox(delta)
    local save = self.game.save
    local count = Boxes.COUNT
    save.currentBox = ((save.currentBox - 1 + delta) % count) + 1
  end

  function Screen:moveHeader(dir)
    if dir == "left" then
      self:changeBox(-1)
    elseif dir == "right" then
      self:changeBox(1)
    elseif dir == "down" then
      self.pane = self.lastPane
    elseif dir == "up" then
      -- UP again wraps past the header to the bottom of the pane it came
      -- from, so the header is a stop on the way round rather than a wall
      if self.lastPane == "party" then
        self.partySlot = PARTY_ROWS
        self.pane = "party"
      else
        self.boxSlot = (ROWS - 1) * COLS + ((self.boxSlot - 1) % COLS) + 1
        self.pane = "box"
      end
    end
  end

  function Screen:move(dir)
    if self.pane == "header" then return self:moveHeader(dir) end
    if self.pane == "party" then return self:moveParty(dir) end
    return self:moveBox(dir)
  end

  -- ------- picking up and putting down

  -- The one deposit the game refuses outright: Yellow's sleeping starter
  -- Pikachu (engine/pokemon/bills_pc.asm's _SleepingPikachuText2 arm).  It is
  -- asked about the mon that is actually crossing party -> box, whichever
  -- half of a swap that is.
  function Screen:refusesDeposit(mon)
    local Follower = follower()
    if not (Follower and mon) then return false end
    local ok, disabled = pcall(Follower.isFollowingDisabled, self.game.overworld)
    if not (ok and disabled) then return false end
    local okStarter, starter =
      pcall(Follower.isStarterPikachu, self.game.save, mon)
    if not (okStarter and starter) then return false end
    self:say(textOf(self.game)._SleepingPikachuText2
      or Strings("There isn't any\nresponse..."))
    return true
  end

  -- What a move owes the engine at each end.  Both are the vanilla PC's own
  -- tail work: add_mon.asm's _MoveMon recomputes a box mon's stats on its way
  -- into the party (without which an imported .sav can reach the party menu
  -- with mon.stats nil), and bills_pc.asm bumps PIKAHAPPY_DEPOSITED going the
  -- other way.
  function Screen:transfer(mon, fromPane, toPane)
    if fromPane == toPane then return end
    -- one of the two panes is the party, so any crossing is a party change
    self.partyTouched = true
    if toPane == "party" then
      Stats.ensure(defOf(self.game, mon), mon)
    else
      local Follower = follower()
      if Follower and Follower.modifyHappiness then
        pcall(Follower.modifyHappiness, self.game.save, "DEPOSITED", mon)
      end
    end
  end

  function Screen:grab()
    local save = self.game.save
    if self.pane == "party" then
      local list = self:listFor("party")
      local row = self.partySlot
      local mon = partyMonAtRow(self, row)
      if not mon then return end
      -- The party may not be emptied, exactly as the vanilla PC refuses the
      -- last mon.  Refusing the PICK-UP rather than the drop is what makes the
      -- rule impossible to walk around: with one POKeMON there is nothing to
      -- reorder either.
      if #list <= 1 then
        self:say(textOf(self.game)._CantDepositLastMonText
          or Strings("You can't deposit\nthe last POKéMON!"))
        return
      end
      -- the row it came out of stays empty for as long as this screen is
      -- open; save.party is compact throughout, so the party is already the
      -- list it will look like again the moment the screen closes
      partyTake(self, row)
      self.partyTouched = true
      self.held = { mon = mon, pane = "party", row = row }
      return
    end

    local cell = self.boxSlot
    local mon = boxMonAt(save, save.currentBox, cell)
    if not mon then return end
    -- the box does NOT close up: the cell this came out of stays empty, and
    -- the POKeMON around it stay where they were
    boxTake(save, save.currentBox, cell)
    self.held = { mon = mon, pane = "box", box = save.currentBox, cell = cell }
  end

  function Screen:place()
    local held = self.held
    if not held then return end
    local save = self.game.save
    local pane = self.pane

    local target
    if pane == "party" then
      target = partyMonAtRow(self, self.partySlot)
    else
      target = boxMonAt(save, save.currentBox, self.boxSlot)
    end

    -- Ask before anything moves, so a refusal leaves the POKeMON in hand
    -- rather than half-placed.  A swap is a deposit and a withdrawal at once,
    -- and only one of the two halves can be crossing party -> box.
    if pane == "box" and held.pane == "party" then
      if self:refusesDeposit(held.mon) then return end
    elseif target and pane == "party" and held.pane == "box" then
      if self:refusesDeposit(target) then return end
    end

    if target then
      -- SWAP: the carried POKeMON takes the slot, the one that was there goes
      -- back to where the carried one came from -- its exact cell, if that was
      -- a box.  No count changes, so no capacity question, which is why a full
      -- party and a full box can still trade.
      if pane == "party" then
        partyReplace(self, self.partySlot, held.mon)
      else
        boxReplace(save, save.currentBox, self.boxSlot, held.mon)
      end
      if held.pane == "party" then
        partyPut(self, held.row, target)
      else
        boxPut(save, held.box, held.cell, target)
      end
      self:transfer(held.mon, held.pane, pane)
      self:transfer(target, pane, held.pane)
    else
      -- Defensive, and deliberately so.  The grid has exactly as many cells as
      -- the list has room (twenty, and six), so a list at capacity has no
      -- empty cell left to aim at and every drop into a full one is the swap
      -- above -- this arm cannot be reached in ordinary play.  It stands for
      -- the save that arrives over capacity anyway (an import, another mod's
      -- deposit) so that the answer there is the game's own refusal rather
      -- than a twenty-first POKeMON the box cannot show.
      local count, capacity
      if pane == "party" then
        count, capacity = #self:listFor("party"), Party.MAX
      else
        count, capacity = #Boxes.ensure(save)[save.currentBox], Boxes.CAPACITY
      end
      if count >= capacity then
        local t = textOf(self.game)
        self:say(pane == "party"
          and (t._CantTakeMonText
            or Strings("You can't take\nany more POKéMON.\fDeposit POKéMON\nfirst."))
          or (t._BoxFullText
            or Strings("Oops! This Box is\nfull of POKéMON.")))
        return
      end
      if pane == "party" then
        -- lands in the row you aimed at, and the array is re-sorted around it
        -- so the order you can see is the order a battle will use
        partyPut(self, self.partySlot, held.mon)
      else
        -- the box does not: it lands in the cell you aimed at, and the cursor
        -- is already on it
        boxPut(save, save.currentBox, self.boxSlot, held.mon)
      end
      self:transfer(held.mon, held.pane, pane)
    end

    self.held = nil
    if option("placeCry", true) then cry(self.game, held.mon.species) end
  end

  -- B with something in hand: back where it came from, in the slot it came
  -- from, in the box it came from.  There is no cell on this screen where
  -- the way out disappears, and no way to leave holding a POKeMON.
  function Screen:returnHeld()
    local held = self.held
    if not held then return end
    self.held = nil
    if held.pane == "party" then
      partyPut(self, held.row, held.mon)
      self.partyTouched = true
    else
      boxPut(self.game.save, held.box, held.cell, held.mon)
    end
  end

  -- ------- SORT

  function Screen:sortBox(mode)
    local game = self.game
    local save = game.save
    local boxNumber = save.currentBox
    local list = Boxes.ensure(save)[boxNumber]
    local cells = layoutFor(save, boxNumber)

    -- one step of undo, and only for this box: changing box while a snapshot
    -- is held would otherwise offer to restore another box's order
    local snapshot = { box = boxNumber, mons = {}, cells = {} }
    for j = 1, #list do
      snapshot.mons[j] = list[j]
      snapshot.cells[j] = cells[j]
    end

    local order = {}
    for j = 1, #list do order[j] = { mon = list[j], cell = cells[j] } end
    for _, entry in ipairs(order) do
      entry.key = sortKey(game, mode, entry)
    end
    table.sort(order, function(a, b)
      if a.key ~= b.key then return a.key < b.key end
      return a.cell < b.cell
    end)

    for j = 1, #order do
      list[j] = order[j].mon
      cells[j] = j
    end
    for j = #order + 1, #cells do cells[j] = nil end

    self.sortUndo = snapshot
  end

  function Screen:canUndoSort()
    local undo = self.sortUndo
    if not undo or undo.box ~= self.game.save.currentBox then return false end
    return sameMembers(Boxes.ensure(self.game.save)[undo.box], undo.mons)
  end

  function Screen:undoSort()
    if not self:canUndoSort() then return end
    local undo = self.sortUndo
    self.sortUndo = nil
    local save = self.game.save
    local list = Boxes.ensure(save)[undo.box]
    local cells = layoutFor(save, undo.box)
    for j = 1, #undo.mons do
      list[j] = undo.mons[j]
      cells[j] = undo.cells[j]
    end
    for j = #undo.mons + 1, #cells do cells[j] = nil end
  end

  -- SELECT over the box.  Refused with a POKeMON in hand, because a sort that
  -- reordered the box around one that is not in it reads as the box shuffling
  -- itself for no reason.
  --
  -- A bordered pop-up rather than a screen: this is the same kind of thing as
  -- the per-POKeMON rows START opens, so it is the same widget with the same
  -- chrome, anchored to the bottom the way the party menu's own submenu is
  -- (`Font.drawBox(9, 17 - n * 2 - 1, ...)` in src/ui/PartyMenu.lua), and
  -- headed SORT the way the box list is headed CHANGE BOX.  The title costs
  -- no rows: Menu writes it INTO the top border it was going to draw anyway.
  function Screen:openSortMenu()
    if self.held then return end
    local game = self.game
    local items = {}
    for _, row in ipairs(SORT_LABELS) do
      local mode = row[2]
      items[#items + 1] = {
        label = Strings(row[1]),
        value = mode,
        onSelect = function() self:sortBox(mode) end,
      }
    end
    if self:canUndoSort() then
      items[#items + 1] = {
        label = Strings("UNDO"),
        value = "undo",
        onSelect = function() self:undoSort() end,
      }
    end
    items[#items + 1] = { label = Strings("CANCEL"), value = "cancel" }

    -- Menu grows its own width to the widest label; the height is the vanilla
    -- two rows per item plus the border, and the box hangs from the bottom
    -- edge so it never covers the header telling you which box you are sorting.
    local th = #items * 2 + 2
    game.stack:push(popup(Menu.new(game, items, {
      tx = 8, ty = math.max(0, 18 - th), tw = 12, th = th, noSound = true,
      title = " " .. Strings("SORT") .. " ",
    })))
  end

  -- ------- the submenu, the box list, and RELEASE

  function Screen:openSummary(mon)
    -- status_screen.asm derives a box mon's stats on the way in; do it here
    -- so the summary is handed a mon it can draw either way
    Stats.ensure(defOf(self.game, mon), mon)
    Screens.push(self.game, "SummaryMenu", mon)
  end

  -- bills_pc.asm BillsPCRelease: confirm, then "Bye [MON]!".  Offered in the
  -- box pane only, which is where the vanilla PC offers it -- RELEASE
  -- POKeMON never listed the party.
  function Screen:release()
    local game = self.game
    local cell = self.boxSlot
    local boxNumber = game.save.currentBox
    local mon = boxMonAt(game.save, boxNumber, cell)
    if not mon then return end
    local t = textOf(game)
    local name = nameOf(game, mon)

    local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
    local okYellow, isYellow = false, false
    if okVersion then okYellow, isYellow = pcall(GameVersion.isYellow) end
    local player = game.save.player
    if okYellow and isYellow and player and mon.species == "PIKACHU"
        and mon.otId == player.id and mon.ot == player.name then
      cry(game, mon.species)
      self:say(((t._PikachuUnhappyText
        or Strings("%s looks\nunhappy about it!", name))
        :gsub("{RAM:wNameBuffer}", name)))
      return
    end

    game.stringBuffer = name
    game.stack:push(TextBox.new(game,
      (t._OnceReleasedText
        or Strings("Once released,\n%s is\ngone forever. OK?", name))
        :gsub("{RAM:wStringBuffer}", name), nil, {
      defaultNo = true, noSound = true,
      choice = function(yes)
        if not yes then return end
        -- re-read: the box is live and the confirm ran a frame later
        if boxMonAt(game.save, boxNumber, cell) ~= mon then return end
        boxTake(game.save, boxNumber, cell)
        cry(game, mon.species)
        game.stack:push(TextBox.new(game,
          ((t._MonWasReleasedText
            or Strings("%s was\nreleased outside.\fBye %s!", name, name))
            :gsub("{RAM:wStringBuffer}", name)), nil, { noSound = true }))
      end,
    }))
  end

  -- ------- what another mod gets to put in the popup
  --
  -- The per-mon popup is the one place in this screen where another mod has
  -- something to say that this one cannot know.  A mod that can do something
  -- TO a POKeMON -- teach it a move it forgot, rename it, read it out to a
  -- companion app -- wants the row where the player already goes looking for
  -- verbs, and the alternative is that it reaches in and patches this file's
  -- internals from the outside.  So it is asked instead:
  --
  --   local box = mod.find("Gen1BillsBox")
  --   if box then
  --     box.exports.actions.provide(function(game, mon, pane)
  --       return { { label = "REMEMBER",
  --                  onSelect = function() ... end } }   -- add these rows
  --       -- or nil                                      -- nothing to add
  --     end, mod.id)
  --   end
  --
  -- Providers are asked in the order they registered and every one of them
  -- contributes: unlike a caption, where one answer wins, a popup is a list
  -- and two mods with a row each should both get one.  Rows land between
  -- this screen's own verbs and CANCEL, so CANCEL stays last -- it is where
  -- the player's thumb expects the way out to be, and a mod's row must not
  -- be able to move it.
  --
  -- `pane` is "party" or "box", so a provider can offer a row on one side
  -- and not the other.  A provider that throws is dropped and reported
  -- rather than taking the popup down with it: a mod that cannot build a row
  -- is a missing row, not a box you cannot open.
  local providers = {}

  -- Tolerates actions:provide(fn) as well as the documented
  -- actions.provide(fn), the way the loader's own mod.find does -- the caller
  -- is another mod's code and the colon is an easy slip to make.  Hands back
  -- a function that unregisters it again.
  --
  -- `owner` is optional and should be the calling mod's id.  A mod's entry
  -- chunk runs again on every hot reload and every profile switch, and this
  -- registry outlives that: without an owner the second load stacks a second
  -- provider closed over the FIRST load's tables, and the stale one answers.
  -- With it, the new registration replaces the old.
  local function provide(first, second, third)
    local fn, owner = first, second
    if type(first) == "table" then fn, owner = second, third end
    if type(fn) ~= "function" then
      mod.log:warn("an action provider that is not a function was ignored")
      return function() end
    end
    local entry = { fn = fn, owner = owner }
    if owner ~= nil then
      for i, candidate in ipairs(providers) do
        if candidate.owner == owner then table.remove(providers, i) break end
      end
    end
    providers[#providers + 1] = entry
    return function()
      for i, candidate in ipairs(providers) do
        if candidate == entry then table.remove(providers, i) return end
      end
    end
  end

  -- Every registered provider's rows for this POKeMON, flattened, in
  -- registration order.  Exported alongside provide() so the suite can ask
  -- what the popup would grow without opening one.
  local function providedRows(game, mon, pane)
    local rows = {}
    local i = 1
    while i <= #providers do
      local entry = providers[i]
      local ok, answer = pcall(entry.fn, game, mon, pane)
      if not ok then
        mod.log:warn("the action provider from %s failed (%s); it is dropped "
          .. "rather than asked again", tostring(entry.owner or "a mod"),
          tostring(answer))
        table.remove(providers, i)
      else
        i = i + 1
        if type(answer) == "table" then
          for _, entry2 in ipairs(answer) do
            -- a row with no label would draw as a blank the cursor can still
            -- land on, which reads as a broken popup rather than a missing row
            if type(entry2) == "table" and entry2.label then
              rows[#rows + 1] = entry2
            end
          end
        end
      end
    end
    return rows
  end

  -- START over a POKeMON.  The vanilla PC's own per-mon rows
  -- (bills_pc.asm DisplayDepositWithdrawMenu) minus the verbs the cursor has
  -- taken over: WITHDRAW and DEPOSIT are what A already does.
  function Screen:openActions()
    if self.held or self.pane == "header" then return end
    local pane = self.pane
    local mon = self:monAt(pane)
    if not mon then return end
    local items = {
      { label = Strings("STATS"), keepOpen = true,
        onSelect = function() self:openSummary(mon) end },
    }
    if pane == "box" then
      items[#items + 1] = { label = Strings("RELEASE"),
        onSelect = function() self:release() end }
    end
    -- another mod's rows, between this screen's verbs and the way out
    for _, row in ipairs(providedRows(self.game, mon, pane)) do
      items[#items + 1] = row
    end
    items[#items + 1] = { label = Strings("CANCEL") }
    -- The vanilla three rows put the box's bottom edge exactly on the last
    -- tile row (ty 10 + th 8 = 18), so a fourth row from a provider would
    -- have run it off the bottom of the screen.  It hangs from the bottom
    -- edge instead, the way CHANGE BOX does, which keeps the POKeMON the
    -- popup is about visible above it however many rows it grows to.  Menu
    -- widens itself to the widest label already, so a long row needs nothing
    -- here.
    local th = #items * 2 + 2
    self.game.stack:push(Menu.new(self.game, items,
      { tx = 9, ty = math.max(0, 18 - th), tw = 11, th = th,
        noSound = true }))
  end

  -- A on the header.  The vanilla CHANGE BOX list, without its save prompt:
  -- this engine keeps all twelve boxes in one save file (src/pokemon/
  -- Boxes.lua), so the "data will be saved" step the cart needed to swap a
  -- SRAM bank has nothing left to do.
  --
  -- A bordered pop-up, like SORT and like the rows START opens: ui.list_menu
  -- draws its default mode as a bare 160x144 fill with no frame at all (only
  -- its itemBox mode has a border, and that is the bag's fixed four-row
  -- geometry), so a decorated twelve-row list has to be a Menu.
  local BOX_LIST_VISIBLE = 6

  function Screen:openBoxList()
    local game = self.game
    local boxes = Boxes.ensure(game.save)
    local items = {}
    for i = 1, Boxes.COUNT do
      -- Menu draws one label per row and has no second column, so how full
      -- a box is goes into the label -- fixed width, so the counts line up
      -- under each other the way ui.list_menu's right column did.
      items[#items + 1] = {
        label = Strings("%sBOX %2d %2d/%d",
          i == game.save.currentBox and "*" or " ", i,
          #boxes[i], Boxes.CAPACITY),
        value = i,
        onSelect = function() game.save.currentBox = i end,
      }
    end

    -- Twelve rows at the vanilla two tiles each would need 26 of the 18 tile
    -- rows there are, so the box shows six and scrolls; it hangs from the
    -- bottom edge, which leaves the header naming the open box uncovered.
    --
    -- The width is one tile more than the labels need (Menu grows a box to
    -- widest + 3 and never past what it is handed), which buys the spare
    -- interior column on the right that the scroll arrow lives in.
    local th = BOX_LIST_VISIBLE * 2 + 2
    local menu = Menu.new(game, items, {
      tx = 3, ty = math.max(0, 18 - th), tw = 17, th = th,
      maxVisible = BOX_LIST_VISIBLE,
      -- Menu whites out exactly as many tiles as the title is wide and puts
      -- it straight onto the top rule, so an unpadded title has the rule
      -- running into its first and last letter.  The padding is added here
      -- rather than inside the string so the catalog key stays the words.
      title = " " .. Strings("CHANGE BOX") .. " ",
      noSound = true,
    })
    -- open on the box you are in rather than on BOX 1: with only half the
    -- list visible, starting anywhere else hides where you are
    menu.index = game.save.currentBox
    menu:clampScroll()

    game.stack:push(popup(menu))
  end

  -- ------- input

  local DIRECTIONS = { "up", "down", "left", "right" }

  function Screen:direction()
    local input = self.game.input
    for _, dir in ipairs(DIRECTIONS) do
      if input:wasPressed(dir) then
        self.holdDir, self.holdFrames = dir, 0
        return dir
      end
    end
    if not option("holdMove", true) then return nil end
    local dir = self.holdDir
    if not dir then return nil end
    -- the headless harness drives wasPressed only; a missing isDown simply
    -- means no repeat, never an error
    if type(input.isDown) ~= "function" or not input:isDown(dir) then
      self.holdDir, self.holdFrames = nil, 0
      return nil
    end
    self.holdFrames = self.holdFrames + 1
    local after = self.holdFrames - REPEAT_DELAY
    if after >= 0 and after % REPEAT_RATE == 0 then return dir end
    return nil
  end

  function Screen:close()
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end

  -- Buttons are read BEFORE the held direction, not after.  A repeat tick and
  -- a real button press can land on the same step, and the direction is the
  -- one of the two that can be asked for again a frame later.
  function Screen:update()
    self.blink = (self.blink + 1) % TICKS
    local input = self.game.input

    if input:wasPressed("a") then
      if self.pane == "header" then
        self:openBoxList()
      elseif self.held then
        self:place()
      else
        self:grab()
      end
    elseif input:wasPressed("b") then
      if self.held then
        self:returnHeld()
      else
        play(self.game, "Turn_Off_PC")
        self:close()
      end
    elseif input:wasPressed("start") then
      self:openActions()
    elseif input:wasPressed("select") then
      -- SELECT belongs to the BOX: it opens SORT.  From the party it is still
      -- the shortcut across the middle of the screen, which makes the pair
      -- read as one key -- SELECT gets you to the box, SELECT again tidies it
      -- -- and costs nothing, because LEFT and RIGHT already cross the panes.
      if self.pane == "party" then
        self.pane, self.lastPane = "box", "box"
      else
        self:openSortMenu()
      end
    else
      local dir = self:direction()
      if dir then self:move(dir) end
    end
  end

  -- StateStack calls this on pop and only on pop -- a screen pushed ON TOP
  -- (the summary) does not fire it -- so it is exactly "the player is done".
  function Screen:exit()
    -- belt and braces: B already refuses to leave with a POKeMON in hand,
    -- but a stack teardown from anywhere else must not drop one either
    self:returnHeld()
    if not self.partyTouched then return end
    -- The follower is spawned once and then left alone (it is rebuilt on
    -- PikachuFollower.onMapEntered), so a party changed from inside a menu
    -- leaves the old POKeMON walking behind you until you change maps.
    -- viaMapLoad = false is the mid-map respawn the engine already uses for
    -- a bike dismount: behind the player, not under him.
    local game = self.game
    local ow = game.overworld
    if not ow then return end
    local Follower = follower()
    if Follower and type(Follower.onMapEntered) == "function" then
      pcall(Follower.onMapEntered, game, ow, nil, false)
    end
    -- Wilds of Kanto keeps its own trailing entities rather than riding
    -- PikachuFollower, so the engine call above rebuilds something that was
    -- never on screen.  Reached through mod.find, not a manifest dependency:
    -- with that mod absent this is one nil check.
    local okHandle, handle = pcall(mod.find, "overworld_wild_spawns")
    if not okHandle or not handle or not handle.exports then return end
    if type(handle.exports.syncAll) == "function" then
      pcall(handle.exports.syncAll, game, ow)
    end
  end

  -- ------- drawing

  function Screen:animAlt()
    return math.floor(self.blink / ANIM_STEPS) % 2 == 1
  end

  -- lit for the first stretch of each cycle, dark for the rest
  function Screen:flashOn()
    return (self.blink % FLASH_PERIOD) < FLASH_ON
  end

  function Screen:drawIcon(mon, x, y, selected)
    if not mon then return end
    -- White is "draw it as it is"; a status replaces it with the colour that
    -- condition wears, which reaches full-colour art as well as the palette
    -- zone does not.
    local tint = statusDrawColour(mon)
    if tint then
      love.graphics.setColor(tint[1], tint[2], tint[3], 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    pcall(PartyMenu.drawIcon, self.game, mon, x, y, false, 0,
          selected and self:animAlt() or false)
    -- full-colour art must sit out the shade remap, or the pass repaints it
    -- off its red channel and an orange POKeMON comes out white
    local rect = fullColourRect(self.game, mon)
    if rect then
      pcall(function()
        require("src.render.PaletteFX").markTrueColor(x, y, rect.w, rect.h)
      end)
    end
  end

  function Screen:drawHeader()
    local game = self.game
    ink(BLACK)
    Font.drawBox(0, 0, 20, HEADER_TH)
    ink(BLACK)
    -- the two box arrows and the selector between them: same shape, same
    -- height, same row, so they line up by construction rather than by luck
    arrow(8, 8, "left")
    arrow(148, 8, "right")
    if self.pane == "header" then arrow(16, 8, "right") end
    Font.draw(Strings("BOX %d", game.save.currentBox), 24, 8)
    local count = ("%d/%d"):format(#Boxes.active(game.save), Boxes.CAPACITY)
    Font.draw(count, 144 - Font.width(count), 8)
  end

  -- The party keeps the SIDEWAYS cursor rather than the grid's down arrow,
  -- and not for want of trying: six rows of sixteen fill the pane's ninety-six
  -- pixels exactly, so there is no band above a party POKeMON's head to put an
  -- arrow in.  A column of entries with the cursor to their left is the party
  -- menu's own idiom anyway, down to the glyph pair -- $ED filled, $EC hollow
  -- while something is in hand.
  function Screen:drawParty()
    for i = 1, PARTY_ROWS do
      local y = PARTY_Y + (i - 1) * PARTY_H
      local selected = self.pane == "party" and self.partySlot == i
      local carried = selected and self.held ~= nil
      if not (carried and not self:flashOn()) then
        self:drawIcon(self:monDrawnAt("party", i), PARTY_X, y, selected)
      end
      if selected then
        ink(BLACK)
        Font.drawCode(self.held and Theme.cursorHollow or Theme.cursor,
                      0, y + 4)
      end
    end
    ink(BLACK)
    love.graphics.rectangle("fill", RULE_X, PARTY_Y, 1, PARTY_ROWS * PARTY_H)
  end

  function Screen:drawGrid()
    -- Ruled as a TABLE, not as twenty separate frames: adjacent frames put two
    -- black columns between neighbouring cells, and at this size that reads as
    -- a thick smudge rather than a grid.  Six verticals and four horizontals,
    -- one pixel each.  The bottom is left open because the footer box's own
    -- border sits immediately under it and closes the grid for free.
    ink(BLACK)
    local height = ROWS * CELL_H
    for col = 0, COLS do
      love.graphics.rectangle("fill", GRID_X + col * CELL_W, GRID_Y, 1, height)
    end
    for row = 0, ROWS - 1 do
      love.graphics.rectangle("fill", GRID_X, GRID_Y + row * CELL_H,
                              COLS * CELL_W + 1, 1)
    end

    for slot = 1, COLS * ROWS do
      local x = GRID_X + ((slot - 1) % COLS) * CELL_W
      local y = GRID_Y + math.floor((slot - 1) / COLS) * CELL_H
      local selected = self.pane == "box" and self.boxSlot == slot
      local carried = selected and self.held ~= nil
      if not (carried and not self:flashOn()) then
        self:drawIcon(self:monDrawnAt("box", slot), x + ICON_DX, y + ICON_DY,
                      selected)
      end
      if selected then
        -- the cursor sits in the band over the POKeMON's head and points at
        -- it; hollow says the POKeMON under it is the one in your hand
        ink(BLACK)
        arrow(x + ARROW_DX, y + ARROW_DY, "down", self.held ~= nil)
      end
    end
  end

  -- One line, naming what the cursor is on.  The strings are the game's own:
  -- "Move to where?" is the party menu's swap prompt and "Choose a POKeMON."
  -- its resting one.
  function Screen:drawInfo()
    local game = self.game
    ink(BLACK)
    Font.drawBox(0, INFO_TY, 20, 3)
    ink(BLACK)
    if self.held then
      Font.draw(Strings("Move to where?"), TEXT_LEFT, INFO_TEXT_Y)
      return
    end
    if self.pane == "header" then
      Font.draw(Strings("CHANGE BOX"), TEXT_LEFT, INFO_TEXT_Y)
      return
    end
    local mon = self:monAt(self.pane)
    if not mon then
      Font.draw(textOf(game)._PartyMenuNormalText
        or Strings("Choose a POKéMON."), TEXT_LEFT, INFO_TEXT_Y)
      return
    end
    Font.draw(nameOf(game, mon), TEXT_LEFT, INFO_TEXT_Y)
    local level = Strings(":L%d", mon.level or 0)
    Font.draw(level, TEXT_RIGHT - Font.width(level), INFO_TEXT_Y)
  end

  function Screen:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    self:drawHeader()
    self:drawParty()
    self:drawGrid()
    self:drawInfo()
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- Forget every box's arrangement, which compacts them all back to the
  -- order the save itself is in.  The suite starts each case with it, and it
  -- is the honest way out for anything that ever finds the arrangement
  -- disagreeing with a save it did not come from -- nothing is lost, because
  -- the arrangement was never where the POKeMON live.
  mod.exports.forgetGrid = function() mod.save:set("cells", {}) end

  -- `actions` is the popup's extension point (see provide, above); main.lua
  -- puts it on mod.exports so another mod can reach it through mod.find.
  return { new = Screen.new,
           actions = { provide = provide, rows = providedRows } }
end
