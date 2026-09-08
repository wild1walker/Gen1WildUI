-- Gen1BillsBox on Gold: the same box, over Gold's storage.
--
-- Returns a factory: factory(mod) -> a screen table registered as an override
-- for `Gen2BoxMenu`.
--
-- ------- why this exists at all, when Gold's PC is already better than Red's
--
-- The feature stood down on Gen 2 for six releases on the grounds that "Gold
-- already has the screen this builds".  That was too generous by half, and it
-- is worth writing down what Gold actually has, because the difference is the
-- whole of this file.
--
-- `src/ui/gen2/BoxMenu.lua` is a transcription of `engine/pokemon/bills_pc.asm`
-- and it is a LIST: `.PlaceNickname` writes five nicknames from (9,4), two
-- rows apart, with a left panel carrying the front pic, the level, the gender
-- and the species of whichever one the cursor is on.  It is a good list.  It
-- is not a box: there is no grid, the party is not on screen beside it, and
-- moving a POKeMON is a four-step modal flow (`.PrepSubmenu` ->
-- `.MoveMonWOMailSubmenu` -> `.PrepInsertCursor` -> `.Joypad2`) reached from
-- a third entry on the PC menu.
--
-- What this mod builds for Red -- the party down the left, the open box as a
-- grid on the right, and a cursor that picks a POKeMON up and puts it down --
-- is exactly what neither game shipped.  So it is built here too, and it
-- REPLACES the list: `override("Gen2BoxMenu")` is the id `PcMenu` pushes for
-- all three of WITHDRAW, DEPOSIT and MOVE POKeMON, so the three verbs land on
-- one screen and there is no second entrance left to fall out of step with
-- the save.
--
-- ------- and every write is the cart's
--
-- This is the one screen in the suite where a mistake loses a POKeMON, so
-- nothing here invents a rule or writes a save field directly.  The refusals
-- and the side effects are `src/core/gen2/Boxes.lua`'s, which is the cart's:
--
--   canDeposit   the box is full / this is your last healthy POKeMON / it is
--                holding MAIL, whose letter has nowhere to live in a box
--                (sPartyMail is six structs keyed by PARTY SLOT)
--   enterBox     RestorePPOfDepositedPokemon, then status cleared and HP
--                refilled from MAXHP, because box_struct has no MON_STATUS
--                and no MON_HP
--   canWithdraw  the party is full
--   removeSlot   every letter behind a departing party mon moves up one
--
-- The one thing this screen does that the cart has no call for is SWAP -- a
-- POKeMON in hand landing on an occupied cell -- and the rules for it are
-- derived from the two above rather than guessed: a swap moves one mon each
-- way, so the box cannot overflow and the party cannot shrink, which is why
-- the capacity halves of both checks are the two that do not apply.  What
-- does apply is what a whiteout depends on: the party must still hold a
-- healthy POKeMON when the dust settles.
--
-- ------- the geometry is Red's, to the pixel
--
-- Both games draw 160x144, so the layout is not re-derived: a 5x4 grid of
-- 24x24 cells at (32,24), the party's icons at x=8 stepping 16 from y=24, and
-- the hairline between the two panes at x=28.  A player who knows this screen
-- on one cart knows it on the other.

return function(mod, globalPane)
  local Boxes = require("src.core.gen2.Boxes")
  local Chrome = require("src.ui.gen2.Chrome")
  local Mail = require("src.core.gen2.Mail")
  local PartyMenu = require("src.ui.gen2.PartyMenu")
  local Strings = require("src.core.Strings")

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true

  -- ------- layout, Red's own (modules/Gen1BillsBox/screen.lua)

  local COLS, ROWS = 5, 4
  local CELL_W, CELL_H = 24, 24
  local GRID_X, GRID_Y = 32, 24
  local SLOTS = COLS * ROWS

  local PARTY_ROWS = 6
  local PARTY_H = 16
  local PARTY_X, PARTY_Y = 8, 24
  local RULE_X = 28

  local ICON = 16
  local ICON_DX = math.floor((CELL_W - ICON) / 2)
  -- Not vertically centred, and deliberately: the column holds a gap, the
  -- 4-pixel cursor, a gap, the icon and a gap in 23 pixels.  Spending the
  -- three spare anywhere but 1/1/1 takes an end gap to zero, and an arrow
  -- with no gap above it is drawn ON the rule.  See Red's screen.lua.
  local ICON_DY = 7
  local ARROW_DX = ICON_DX + math.floor((ICON - 7) / 2)
  local ARROW_DY = 2

  local HEADER_TH = 3
  local INFO_TY = 15

  local REPEAT_DELAY, REPEAT_RATE = 16, 5
  local FLASH_PERIOD, FLASH_ON = 24, 16
  local TICKS = 240

  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  -- ------- drawing primitives
  --
  -- Through Chrome rather than Font, so UI THEME reaches this screen the way
  -- it reaches every other Gold page: the box palette is rewritten in place
  -- once a frame and `Chrome.box` / `Chrome.printThrough` read it at call
  -- time.  The rules and the cursor are the one thing drawn by hand, and they
  -- take the palette's INK so they go light on a dark page with the text.

  local function palette()
    return Chrome.DEFAULT_BOX_PALETTE
  end

  local function inkColor()
    local pal = palette()
    local ink = type(pal) == "table" and pal[4]
    if type(ink) ~= "table" then return 0, 0, 0 end
    return (ink[1] or 0) / 255, (ink[2] or 0) / 255, (ink[3] or 0) / 255
  end

  local function line(x, y, w, h)
    local r, g, b, a = love.graphics.getColor()
    local ir, ig, ib = inkColor()
    love.graphics.setColor(ir, ig, ib, 1)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(r, g, b, a)
  end

  -- A solid triangle, and the same triangle hollow while a POKeMON is in
  -- hand.  Drawn rather than printed because the charmap has a down arrow but
  -- no hollow twin of it -- the hollow/filled PAIR only exists sideways.
  --
  -- Two directions, and which one goes where is not decoration.  The grid
  -- points DOWN because a cell has a band above the icon to point from.  The
  -- party points RIGHT, because six rows of sixteen fill the pane's
  -- ninety-six pixels exactly and there is no band above a party POKeMON's
  -- head to put an arrow in -- and because a column of entries with the
  -- cursor to their left is the party menu's own idiom on both games.  The
  -- first cut of this screen used the down arrow for both and it read as
  -- pointing at nothing.
  local ARROW_LONG, ARROW_SHORT = 7, 4

  local function arrow(x, y, dir, hollow)
    local r, g, b, a = love.graphics.getColor()
    local ir, ig, ib = inkColor()
    love.graphics.setColor(ir, ig, ib, 1)
    for i = 0, ARROW_SHORT - 1 do
      local span = ARROW_LONG - i * 2
      local whole = not hollow or span <= 2 or i == 0
      if dir == "down" then
        if whole then
          love.graphics.rectangle("fill", x + i, y + i, span, 1)
        else
          love.graphics.rectangle("fill", x + i, y + i, 1, 1)
          love.graphics.rectangle("fill", x + i + span - 1, y + i, 1, 1)
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
    love.graphics.setColor(r, g, b, a)
  end

  -- ------- what the save holds

  local function partyOf(save) return (save and save.party) or {} end

  -- ------- only the icon under the cursor walks
  --
  -- `PartyMenu:iconFor` picks the frame off the screen's own clock:
  --
  --     local frame = math.floor(self.clock / ICON_FRAME_STEPS) % 2
  --
  -- so every icon drawn through it flips between its two frames at once, all
  -- twenty cells stepping together.  Red's box animates the one under the
  -- cursor and leaves the rest standing still, and that is what this screen
  -- says with `gen1wildAnimate` around each draw.
  --
  -- The rule that READS that flag has to live here.  It used to live only in
  -- the Gen1Wild bundle's runtime/icons2.lua, which is fine inside the bundle
  -- and is nothing at all on a standalone install: nothing honoured the flag,
  -- so every cell in the box flipped together -- the "sprites flipping back
  -- and forth" this screen exists to stop.  Installed once, on the class,
  -- and marked: the bundle's copy of the same rule may sit on top of it, and
  -- two idempotent wraps that both rest an unhovered icon on frame 0 agree.
  local ICON_RULE = "__gen1BoxIconRule"
  local function installIconRule()
    if rawget(PartyMenu, ICON_RULE) then return end
    local baseIconFor = PartyMenu.iconFor
    if type(baseIconFor) ~= "function" then return end
    PartyMenu.iconFor = function(menu, mon, ...)
      local image, frame = baseIconFor(menu, mon, ...)
      -- Frame 0 is the one the cart rests on, so a still icon is the icon the
      -- cart would draw between flips rather than a second pose.
      if image and not menu.gen1wildAnimate then return image, 0 end
      return image, frame
    end
    PartyMenu[ICON_RULE] = true
  end

  local function boxList(save, index) return Boxes.box(save, index) end

  -- ------- where in the grid each POKeMON sits
  --
  -- Gold stores a box as a COMPACT array, exactly as Red does
  -- (src/core/gen2/Boxes.lua: `save.boxes[index]`, `#` for the count).  That
  -- is the save format, it is what the cart's own deposit appends to, and it
  -- is what is left behind if this mod is ever removed -- so it stays exactly
  -- as it is.
  --
  -- What it cannot express is a GAP, and a grid you cannot leave a gap in is
  -- not really a grid: pick the second POKeMON out of six and the other four
  -- slide up behind it.  Reported as "I can't free place my Pokemon".
  --
  -- This screen used to say the compact array WAS the arrangement -- cells
  -- 1..count full, the rest empty, with one hole while something was in hand.
  -- That is why a POKeMON put down in cell 12 of an empty box appeared in
  -- cell 1: `place` appended to the list, and the list was the grid.
  --
  -- So the arrangement is kept beside the box rather than in it, which is what
  -- the Gen 1 screen has always done (modules/Gen1BillsBox/screen.lua, "where
  -- in the grid each POKeMON sits"): `cells[j]` is the grid cell that
  -- `list[j]` sits in, one entry per POKeMON, in this mod's own save data.
  -- Same idea, same reconciliation, a different key -- the two carts never
  -- share a save, and a key of their own means neither can ever read the
  -- other's arrangement even if one did.
  --
  -- The two are reconciled on EVERY read, which is what makes this safe to
  -- bolt onto a shared save.  Anything else may add to a box behind this
  -- screen's back -- a catch overflowing into it, another mod, an imported
  -- save -- and the arrangement simply grows to match: extra POKeMON take the
  -- lowest free cells, extra cells are dropped, and a cell that is out of
  -- range or claimed twice is thrown away.  The worst case is that the
  -- arrangement resets to the compact one nobody could see a gap in anyway.
  local LAYOUT_KEY = "cells2"

  -- Optional, and the fallback is not a nicety: `mod.save` is absent on a tree
  -- built before it existed and on a bundle installed outside a sealed cart,
  -- and a storage screen that ERRORS is a storage screen you cannot get your
  -- POKeMON out of.  So a missing store degrades to one that lives for this
  -- session: the grid still takes gaps, they are simply forgotten when the
  -- game closes rather than remembered.
  -- Keyed by the SAVE, and weakly, so two saves opened in one session cannot
  -- read each other's arrangement and a closed one is not held alive by this.
  -- One table for the whole fallback would be the same bug in a quieter place:
  -- a box's gaps belong to the save the box is in.
  local sessionStores = setmetatable({}, { __mode = "k" })

  local function backing()
    local box = mod.save
    if type(box) == "table" and type(box.get) == "function"
        and type(box.set) == "function" then
      return box
    end
    return nil
  end

  local function readStore(save)
    local box = backing()
    if not box then
      local store = sessionStores[save or sessionStores]
      if type(store) ~= "table" then
        store = {}
        sessionStores[save or sessionStores] = store
      end
      return store
    end
    local ok, store = pcall(box.get, box, LAYOUT_KEY)
    -- A store that is simply not written yet is an EMPTY one.
    if not ok or type(store) ~= "table" then return {} end
    return store
  end

  local function writeStore(save, store)
    local box = backing()
    if not box or not pcall(box.set, box, LAYOUT_KEY, store) then
      sessionStores[save or sessionStores] = store
    end
  end

  local function layoutFor(save, boxNumber)
    local store = readStore(save)
    if type(store) ~= "table" then store = {} end
    -- one key shape whatever a serializer did with the number
    local key = tostring(boxNumber)
    local cells = store[key]
    if type(cells) ~= "table" then cells = store[boxNumber] end
    if type(cells) ~= "table" then cells = {} end
    store[boxNumber] = nil

    local list = boxList(save, boxNumber)
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
    writeStore(save, store)
    return clean
  end

  -- The compact index the cell stands for, which is what every call that
  -- touches the cart's own list takes.  nil for an empty cell.
  local function boxIndexAtCell(save, boxNumber, cell)
    local cells = layoutFor(save, boxNumber)
    for j = 1, #cells do
      if cells[j] == cell then return j end
    end
    return nil
  end

  local function boxMonAt(save, boxNumber, cell)
    local j = boxIndexAtCell(save, boxNumber, cell)
    if not j then return nil end
    return boxList(save, boxNumber)[j]
  end

  -- Out of the box AND out of the arrangement, so the cell it was in is now
  -- an empty one rather than a place the rest slide into.
  local function boxTake(save, boxNumber, cell)
    local j = boxIndexAtCell(save, boxNumber, cell)
    if not j then return nil end
    table.remove(layoutFor(save, boxNumber), j)
    return table.remove(boxList(save, boxNumber), j)
  end

  -- Appended to both, which is why the compact array's ORDER never has to
  -- mean anything: the cell beside it is what says where the POKeMON is.
  local function boxPut(save, boxNumber, cell, mon)
    local list = boxList(save, boxNumber)
    local cells = layoutFor(save, boxNumber)
    list[#list + 1] = mon
    cells[#cells + 1] = cell
  end

  local function boxReplace(save, boxNumber, cell, mon)
    local j = boxIndexAtCell(save, boxNumber, cell)
    if not j then return nil end
    local list = boxList(save, boxNumber)
    local was = list[j]
    list[j] = mon
    return was
  end

  -- The lowest free cell, for a POKeMON that has to land SOMEWHERE and has no
  -- cell of its own to land in -- an overflow put-back, or a box whose
  -- arrangement is full because the list is.
  local function freeCell(save, boxNumber)
    local cells = layoutFor(save, boxNumber)
    local taken = {}
    for j = 1, #cells do taken[cells[j]] = true end
    for cell = 1, SLOTS do
      if not taken[cell] then return cell end
    end
    return nil
  end

  -- ------- the GLOBAL pages
  --
  -- Past BOX 14 the header keeps going: GLOBAL 1, and one more page every time
  -- the last one fills.  The store behind them is shared with every other save
  -- on this installation, a plain RED's included (globalbox.lua), and the whole
  -- of what is different about them follows from that:
  --
  --   * no gaps -- the cell another cartridge's POKeMON sits in is not this
  --     save's to record, so the pages are the union in order and always
  --     closed up.  One put down lands in the first free cell and the cursor
  --     follows it there.
  --   * no swap, no sort, no release.  A swap re-sorts the page under your
  --     hand; a sort would be this save deciding the order of POKeMON in other
  --     people's saves; and "gone forever" is not a thing this save gets to
  --     decide about a POKeMON living in another one.
  --
  -- The Gen 1 screen carries the same layer, function for function
  -- (modules/Gen1BillsBox/screen.lua): the two storage models underneath are
  -- nothing like each other, but the shared store is one store and a page of
  -- it has to behave the same on both cartridges.

  local function globalSession(screen)
    return screen and screen.global or nil
  end

  local function onGlobal(screen)
    return screen ~= nil and screen.globalPage ~= nil
      and globalSession(screen) ~= nil
  end

  local function globalPages(screen)
    local session = globalSession(screen)
    if not session then return 0 end
    local ok, pages = pcall(session.pages, session)
    return (ok and tonumber(pages)) or 0
  end

  local function pageMonAt(screen, cell)
    if not onGlobal(screen) then
      return boxMonAt(screen.save, screen.boxIndex, cell)
    end
    local session = globalSession(screen)
    local ok, mon = pcall(session.at, session, screen.globalPage, cell)
    return ok and mon or nil
  end

  local function pageCount(screen)
    if not onGlobal(screen) then
      return Boxes.count(screen.save, screen.boxIndex)
    end
    local session = globalSession(screen)
    local ok, count = pcall(session.countOn, session, screen.globalPage)
    return (ok and tonumber(count)) or 0
  end

  local function pageCapacity(screen)
    if not onGlobal(screen) then return Boxes.MONS_PER_BOX end
    local session = globalSession(screen)
    local ok, capacity = pcall(session.capacity, session)
    return (ok and tonumber(capacity)) or Boxes.MONS_PER_BOX
  end

  local function pageName(screen)
    if not onGlobal(screen) then
      return Boxes.name(screen.save, screen.boxIndex)
    end
    return Strings("GLOBAL %d", screen.globalPage)
  end

  -- ------- and where in the PARTY pane each one sits
  --
  -- The same idea, and deliberately not the same mechanism -- again the Gen 1
  -- screen's, for the reason it gives there.
  --
  -- A box's arrangement is SAVED, because a box is storage and a gap you left
  -- there is a decision.  The party's is not: it lives on the screen object,
  -- so it is gone the moment you close the box and the party is a list of six
  -- again -- which is what the rest of the game reads it as, every frame,
  -- everywhere.  That is the "keep the hole until you close it" behaviour, and
  -- it is why closing the screen has nothing to collapse.
  --
  -- So save.party is never sparse.  What is sparse is only which ROW each of
  -- its members is drawn in, and the array is kept SORTED BY THAT ROW after
  -- every change.  That last part is the whole safety of it: party order is
  -- BATTLE order -- party[1] is who you send out -- so an arrangement that let
  -- the visual order and the array order drift apart would quietly change who
  -- leads.  Sorted, the two can never disagree.
  --
  -- sPartyMail is keyed by party SLOT, so every insert and remove here goes
  -- through the cart's own Mail calls at the same index, exactly as `grab`
  -- already did.
  local function partyRowsOf(screen)
    local list = partyOf(screen.save)
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
    return partyOf(screen.save)[j]
  end

  local function partyTake(screen, row)
    local j = partyIndexAtRow(screen, row)
    if not j then return nil end
    table.remove(partyRowsOf(screen), j)
    return table.remove(partyOf(screen.save), j)
  end

  -- Inserted at its SORTED position, not appended: that is what keeps the
  -- array order and the visual order the same thing.  Returns the party index
  -- it landed at, which is the slot its mail has to move to.
  local function partyPut(screen, row, mon)
    local rows = partyRowsOf(screen)
    local at = #rows + 1
    for j = 1, #rows do
      if rows[j] > row then at = j break end
    end
    table.insert(rows, at, row)
    table.insert(partyOf(screen.save), at, mon)
    return at
  end

  -- The inverse of `Mail.removeSlot`, which the cart has no name for because
  -- the cart never inserts into the MIDDLE of a party -- every addition it
  -- makes appends.  This screen does insert in the middle, because a POKeMON
  -- put back in row 2 of a party of four belongs at party index 2, so the
  -- letters below it have to move back down or each one lands on the wrong
  -- POKeMON.  Built out of Mail's own state and length rather than a second
  -- copy of the table.
  local function mailInsertSlot(save, slot)
    -- PARTY_ROWS is the same six, and standing in for a Mail that does not
    -- name its own length keeps this from being the line that takes the box
    -- down: the shift is what matters, not where the constant came from.
    local length = tonumber(Mail.PARTY_LENGTH) or PARTY_ROWS
    if not (slot and slot >= 1 and slot <= length) then return end
    local ok, state = pcall(Mail.state, save)
    local party = ok and type(state) == "table" and state.party or nil
    if type(party) ~= "table" then return end
    for i = length, slot + 1, -1 do
      party[i] = party[i - 1]
    end
    party[slot] = nil
  end

  local function partyFreeRow(screen)
    local rows = partyRowsOf(screen)
    local taken = {}
    for j = 1, #rows do taken[rows[j]] = true end
    for row = 1, PARTY_ROWS do
      if not taken[row] then return row end
    end
    return nil
  end

  local function nameOf(screen, mon)
    if not mon then return "" end
    if mon.isEgg then return Strings("EGG") end
    if mon.nickname and mon.nickname ~= "" then return mon.nickname end
    local data = screen.game and screen.game.data
    local def = data and data.pokemon and data.pokemon[mon.species]
    return (def and def.name) or tostring(mon.species or "?")
  end

  -- ------- moving a POKeMON, through the cart's own rules
  --
  -- `intoBox` and `intoParty` are the two tails the cart runs at each end of
  -- a move: a mon entering storage has its PP restored and its status and HP
  -- reset from MAXHP, and one entering the party is healed the same way the
  -- withdraw arm heals it.  Both are Boxes' own, called rather than copied.

  local function intoBox(mon) return Boxes.enterBox(mon) end

  local function intoParty(mon)
    if not mon then return mon end
    mon.status = nil
    mon.statusTurns = nil
    if mon.isEgg then mon.hp = 0 else mon.hp = mon.maxHp or mon.hp end
    return mon
  end

  local function healthyAfter(party, leaving, arriving)
    local n = 0
    for _, mon in ipairs(party) do
      if mon ~= leaving and (mon.hp or 0) > 0 then n = n + 1 end
    end
    -- A boxed POKeMON arrives healed, so it counts unless it is an egg.
    if arriving and not arriving.isEgg then n = n + 1 end
    return n
  end

  -- ------- the screen

  function Screen.new(game, opts)
    opts = opts or {}
    local self = setmetatable({}, Screen)
    self.game = game
    self.save = opts.save or (game and game.save)
    self.mode = opts.mode or "withdraw"
    self.onClose = opts.onClose
    self.boxIndex = (self.save and self.save.currentBox) or 1
    self.pane = option("startPane", "box") == "party" and "party" or "box"
    -- Which pane the header was reached FROM, so DOWN goes back to it.
    self.lastPane = self.pane
    self.boxSlot = 1
    self.partySlot = 1
    self.held = nil
    self.ticks = 0
    self.hold = nil
    self.message = nil
    -- The engine's own party-menu icon path, so per-species icons, the
    -- `pokemon.icon` hook and any icon replacement mod land in the box
    -- exactly as they land in the party.  Built with an empty party: it is
    -- used as a renderer, never as a list.
    installIconRule()
    local ok, icons = pcall(PartyMenu.new, game, { party = {}, save = self.save })
    self.icons = ok and icons or nil
    -- The GLOBAL pages, opened once here rather than per frame: opening a
    -- session reads and decodes every save on the installation and reconciles
    -- this one against what the others have claimed.  nil when the feature is
    -- off or failed to load, and every page* call above already reads that as
    -- "this screen has fourteen boxes".
    self.globalPage = nil
    self.global = nil
    -- what SELECT has marked, in the order it was marked
    self.picked = {}
    if type(globalPane) == "function" then
      local pane = globalPane()
      if pane then
        local okPane, session = pcall(pane.open, game)
        if okPane and type(session) == "table" then
          self.global = session
        else
          mod.log:warn("the GLOBAL BOX did not open (%s); the cartridge's own "
            .. "boxes are unaffected", tostring(session))
        end
      end
    end
    return self
  end

  -- ------- a message, and the pages it is written in
  --
  -- "\f" is the engine's page break and every refusal in this mod is written
  -- with it: two lines, then a break, then two more.  Red's arm gets that for
  -- free -- it says through the engine's own TextBox, which pages.  This
  -- screen draws its own message box and did not, so it printed the first line
  -- before the first "\n" and then EVERYTHING ELSE on the second line, page
  -- breaks and all, straight off the right edge of the screen.
  --
  -- Reported as "the words don't fit in the pop up", with a refusal reading
  -- "YELLOW must be importe" and no way to see the rest of it.
  local function messagePages(text)
    local pages = {}
    for page in tostring(text):gmatch("[^\f]+") do pages[#pages + 1] = page end
    if #pages == 0 then pages[1] = "" end
    return pages
  end

  function Screen:say(text)
    self.message = text
    self.messagePage = 1
  end

  function Screen:messageLines()
    local pages = messagePages(self.message)
    local page = pages[self.messagePage or 1] or ""
    local first, second = page:match("^([^\n]*)\n?(.*)$")
    return first or "", second or "", #pages
  end

  function Screen:close()
    -- A POKeMON in hand goes back where it came from rather than out of the
    -- save with the screen.
    self:returnHeld()
    if self.save then self.save.currentBox = self.boxIndex end
    if self.onClose then self.onClose() end
  end

  -- ------- what is in each cell
  --
  -- Straight off the two arrangements above, which is the whole of the
  -- change: a cell holds whatever the layout says sits there, and every other
  -- cell is empty -- including the ones between POKeMON.  Lifting one out
  -- removes its entry, so the cell it left is simply an empty cell like any
  -- other and nothing slides up behind it.

  function Screen:boxCells(index)
    local cells = {}
    for cell = 1, SLOTS do
      cells[cell] = onGlobal(self) and pageMonAt(self, cell)
        or boxMonAt(self.save, index, cell)
    end
    return cells
  end

  -- The compact index a cell stands for, which is what the cart's own calls
  -- take.  nil for an empty cell.
  function Screen:boxIndexAt(index, cell)
    return boxIndexAtCell(self.save, index, cell)
  end

  function Screen:partyCells()
    local cells = {}
    for row = 1, PARTY_ROWS do
      cells[row] = partyMonAtRow(self, row)
    end
    return cells
  end

  function Screen:partyIndexAt(row)
    return partyIndexAtRow(self, row)
  end

  -- What is DRAWN in a cell, which is not always what is stored in it: the
  -- POKeMON in your hand is drawn in the cell the cursor is on, in place of
  -- whatever is there, exactly as the Gen 1 screen draws it
  -- (modules/Gen1BillsBox/screen.lua, `monDrawnAt`).
  --
  -- This screen used to draw the carried POKeMON as a separate pass ON TOP of
  -- the grid, so the cursor cell showed two icons stacked -- the cell's own
  -- occupant standing still underneath and the carried one blinking over it.
  -- That is the "wrong animation": one POKeMON in your hand, drawn as two.
  function Screen:monDrawnAt(pane, slot)
    local held = self.held
    if held and self.pane == pane then
      local at = pane == "party" and self.partySlot or self.boxSlot
      if at == slot then return held.mon end
    end
    if pane == "party" then return partyMonAtRow(self, slot) end
    return pageMonAt(self, slot)
  end

  function Screen:monUnder()
    if self.pane == "party" then
      return self:partyCells()[self.partySlot]
    end
    return self:boxCells(self.boxIndex)[self.boxSlot]
  end

  -- ------- picking up

  function Screen:grab()
    if self.held then return end
    if self.pane == "party" then
      local row = self.partySlot
      local index = self:partyIndexAt(row)
      local party = partyOf(self.save)
      local mon = index and party[index]
      if not mon then return end
      -- Refused at the PICK-UP rather than at the drop, which is what makes
      -- the rule impossible to walk around: with one POKeMON in the party
      -- there is nothing to reorder either.
      if #party <= 1 then
        return self:say(Strings("You can't deposit\nthe last POKéMON!"))
      end
      if Mail.monHoldsMail(mon) then
        return self:say(Strings("Remove MAIL."))
      end
      partyTake(self, row)
      Mail.removeSlot(self.save, index)
      self.held = { mon = mon, from = "party", row = row }
      return
    end
    -- A GLOBAL page hands back a TICKET as well as the POKeMON, and the ticket
    -- is the only way back: out of your OWN outbox it is a removal, out of
    -- another save's it is a claim, and undoing the two is not the same move.
    if onGlobal(self) then
      local session = globalSession(self)
      local mon, ticket = session:take(self.game, self.globalPage, self.boxSlot)
      if not mon then
        if ticket and ticket ~= "empty_cell" then
          self:say(session:refusalText(ticket))
        end
        return
      end
      self.held = { mon = mon, from = "box", global = true, ticket = ticket }
      return
    end
    if not self:boxIndexAt(self.boxIndex, self.boxSlot) then return end
    local mon = boxTake(self.save, self.boxIndex, self.boxSlot)
    if not mon then return end
    self.held = { mon = mon, from = "box", box = self.boxIndex,
                  cell = self.boxSlot }
  end

  -- ------- putting down
  --
  -- Everything is asked BEFORE anything moves, so a refusal leaves the
  -- POKeMON in hand rather than half-placed.

  function Screen:refuse(pane, target)
    local held = self.held
    local mon = held.mon
    local party = partyOf(self.save)
    if pane == "box" and held.from == "party" then
      if Mail.monHoldsMail(mon) then return Strings("Remove MAIL.") end
      if not target and Boxes.isFull(self.save, self.boxIndex) then
        return Strings("The BOX is full.")
      end
      if healthyAfter(party, nil, target) < 1 then
        return Strings("You can't deposit\nthe last POKéMON!")
      end
    elseif pane == "party" and held.from == "box" then
      -- No "the party is full" arm, and its absence is the point rather than
      -- an omission: an empty party ROW only exists while the party is short
      -- of six, so a drop onto one can never be the seventh POKeMON.  A full
      -- party leaves only occupied rows, and every one of those is a SWAP --
      -- one in, one out, so the party is the same size afterwards.
      if target and Mail.monHoldsMail(target) then
        return Strings("Remove MAIL.")
      end
      if target and healthyAfter(party, target, mon) < 1 then
        return Strings("You can't deposit\nthe last POKéMON!")
      end
    elseif pane == "box" and held.from == "box"
        and not target and Boxes.isFull(self.save, self.boxIndex) then
      return Strings("The BOX is full.")
    end
    return nil
  end

  function Screen:place()
    local held = self.held
    if not held then return end
    local pane = self.pane
    local party = partyOf(self.save)

    local target, targetIndex
    if pane == "party" then
      targetIndex = self:partyIndexAt(self.partySlot)
      target = targetIndex and party[targetIndex]
    elseif onGlobal(self) then
      target = pageMonAt(self, self.boxSlot)
    else
      targetIndex = self:boxIndexAt(self.boxIndex, self.boxSlot)
      target = targetIndex and boxList(self.save, self.boxIndex)[targetIndex]
    end

    -- ---- onto a GLOBAL page
    --
    -- Two arms and no third.  A POKeMON that CAME from a global page goes back
    -- through its own ticket, into the cell it came out of, whatever cell the
    -- cursor is on -- the pages are a shared queue and there is nothing here
    -- to rearrange.  Anything else is a deposit, which lands in the first free
    -- cell for the same reason; the cursor follows it so the move is visible.
    if pane == "box" and onGlobal(self) then
      local session = globalSession(self)
      if held.global then
        session:untake(held.ticket)
        self.held = nil
        local page, cell = session:locate(held.ticket and held.ticket.id)
        if page then self.globalPage, self.boxSlot = page, cell end
        return
      end
      if held.from == "party" and healthyAfter(party, held.mon, nil) < 1 then
        return self:say(Strings("You can't deposit\nthe last POKéMON!"))
      end
      -- the cart's own into-storage tail runs BEFORE the box copies it, so
      -- what is stored is a stored POKeMON and not a party one.  `put` is the
      -- only place the conversion happens, and it converts before it stores --
      -- so a refusal leaves the box untouched and the POKeMON in hand, and
      -- asking first would only be Convert run twice.  The cell the cursor is
      -- on is not part of it: the pages are a queue with no gaps, so a deposit
      -- lands in the first free cell wherever it was aimed and the cursor
      -- follows it there.
      -- three returns on the way out and only the first says whether it
      -- worked: `put` answers index, page, cell -- or nil and a reason, whose
      -- reason would read as a perfectly good page number if the index were
      -- thrown away.
      local index, page, cell = session:put(self.game, intoBox(held.mon))
      if not index then return self:say(session:refusalText(page)) end
      self.globalPage, self.boxSlot = page, cell
      self.held = nil
      if option("placeCry", true) then
        pcall(function()
          require("src.core.Sound").playCry(self.game.data, held.mon.species)
        end)
      end
      return
    end

    -- A POKeMON carried OUT of a global page cannot swap: the POKeMON it would
    -- displace has to go back where the carried one came from, and "where it
    -- came from" is a cell in somebody else's save.
    if held.global and target then
      return self:say(Strings("There's a POKéMON\nthere already!"))
    end

    local refusal = self:refuse(pane, target)
    if refusal then return self:say(refusal) end

    -- The carried POKeMON lands first, then the one it displaced goes back to
    -- where the carried one came from -- which is a CELL now, not the end of
    -- a list, so a swap really does exchange the two places rather than
    -- appending one of them.
    --
    -- An empty cell is the case that was broken: this used to append to the
    -- cart's list, and the list was the grid, so a POKeMON put down in cell 12
    -- of an empty box appeared in cell 1.  It lands in the cell you aimed at.
    if target then
      local sent
      if pane == "party" then
        sent = partyTake(self, self.partySlot)
        Mail.removeSlot(self.save, targetIndex)
        local at = partyPut(self, self.partySlot, intoParty(held.mon))
        mailInsertSlot(self.save, at)
      else
        sent = boxReplace(self.save, self.boxIndex, self.boxSlot,
                          intoBox(held.mon))
      end
      if held.from == "party" then
        local at = partyPut(self, held.row, intoParty(sent))
        mailInsertSlot(self.save, at)
      else
        -- held.global never reaches here: a carried shared POKeMON refuses
        -- an occupied cell above, because there is no cell of its own to send
        -- the displaced one back to.
        boxPut(self.save, held.box, held.cell, intoBox(sent))
      end
    else
      if pane == "party" then
        local at = partyPut(self, self.partySlot, intoParty(held.mon))
        mailInsertSlot(self.save, at)
      else
        boxPut(self.save, self.boxIndex, self.boxSlot, intoBox(held.mon))
      end
    end
    self.held = nil
    if option("placeCry", true) then
      pcall(function()
        require("src.core.Sound").playCry(self.game.data,
          (target or held.mon).species)
      end)
    end
  end

  function Screen:returnHeld()
    local held = self.held
    if not held then return end
    self.held = nil
    if held.global then
      local session = globalSession(self)
      if session then session:untake(held.ticket) end
      return
    end
    if held.from == "party" then
      local party = partyOf(self.save)
      if #party < Boxes.PARTY_SIZE then
        local row = partyIndexAtRow(self, held.row) == nil and held.row
          or partyFreeRow(self)
        local at = partyPut(self, row or held.row, intoParty(held.mon))
        mailInsertSlot(self.save, at)
        return
      end
    end
    local box = held.box or self.boxIndex
    local list = boxList(self.save, box)
    if #list < Boxes.MONS_PER_BOX then
      -- Its own cell if that is still empty -- it usually is, it is the one it
      -- was lifted out of -- and otherwise the lowest free one.
      local cell = held.cell
      if not cell or boxMonAt(self.save, box, cell) then
        cell = freeCell(self.save, box)
      end
      if cell then
        boxPut(self.save, box, cell, intoBox(held.mon))
        return
      end
    end
    -- Nowhere it came from and nowhere beside it: the first box with room.
    -- A POKeMON is never dropped on the floor.
    for index = 1, Boxes.NUM_BOXES do
      if not Boxes.isFull(self.save, index) then
        local cell = freeCell(self.save, index)
        if cell then
          boxPut(self.save, index, cell, intoBox(held.mon))
          return
        end
      end
    end
    local party = partyOf(self.save)
    local at = partyPut(self, partyFreeRow(self) or PARTY_ROWS,
                        intoParty(held.mon))
    mailInsertSlot(self.save, at)
  end

  -- ------- moving about

  -- One ring: BOX 1 .. BOX 14, then GLOBAL 1 .. GLOBAL n, then round to BOX 1.
  -- The global pages are counted fresh on every step, because the last one is
  -- always empty and a deposit into it opens another.
  function Screen:changeBox(delta)
    local pages = globalPages(self)
    local count = Boxes.NUM_BOXES + pages
    local at = self.globalPage and (Boxes.NUM_BOXES + self.globalPage)
      or self.boxIndex
    at = ((at - 1 + delta) % count) + 1
    if at > Boxes.NUM_BOXES then
      self.globalPage = at - Boxes.NUM_BOXES
      return
    end
    self.globalPage = nil
    self.boxIndex = at
    if self.save then self.save.currentBox = at end
  end

  -- The header is a stop on the way round rather than a wall: UP out of the
  -- top of either pane lands on it, DOWN goes back where it came from, and UP
  -- again wraps past it to the bottom of that pane.  Box changes live here,
  -- beside the name and the count they change, rather than on a shortcut --
  -- which is what makes them visible.
  function Screen:moveHeader(dir)
    if dir == "left" then
      self:changeBox(-1)
    elseif dir == "right" then
      self:changeBox(1)
    elseif dir == "down" then
      self.pane = self.lastPane
    elseif dir == "up" then
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
    if self.pane == "party" then
      if dir == "up" then
        if self.partySlot == 1 then
          self.lastPane = "party"
          self.pane = "header"
        else
          self.partySlot = self.partySlot - 1
        end
      elseif dir == "down" then
        self.partySlot = self.partySlot < PARTY_ROWS and self.partySlot + 1 or 1
      elseif dir == "right" then
        self.pane = "box"
      end
      return
    end
    local col = (self.boxSlot - 1) % COLS
    local row = math.floor((self.boxSlot - 1) / COLS)
    if dir == "left" then
      if col == 0 then self.pane = "party" return end
      col = col - 1
    elseif dir == "right" then
      -- the party is off the left edge, so the right edge wraps within the
      -- row rather than stepping to the next box: box changes belong to the
      -- header, where they are visible
      col = col == COLS - 1 and 0 or col + 1
    elseif dir == "up" then
      if row == 0 then
        self.lastPane = "box"
        self.pane = "header"
        return
      end
      row = row - 1
    elseif dir == "down" then
      row = row < ROWS - 1 and row + 1 or 0
    end
    self.boxSlot = row * COLS + col + 1
  end

  -- ------- the actions pop-up
  --
  -- START on Red opens the verbs the vanilla PC put on its own menu -- STATS,
  -- and RELEASE for a boxed POKeMON.  The first cut of this arm made START
  -- CLOSE the screen, which is both wrong and the one thing a player will hit
  -- by accident: reported as "clicking start closes the box instead of giving
  -- me my options".  B is the way out and always was.
  --
  -- Drawn here rather than pushed as a screen because it is modal over this
  -- one: a pop-up that owned the stack would take the box off the display
  -- behind it, and the whole point of the verbs is that you can still see
  -- what they are about.
  local function actionsFor(screen)
    if screen.held then return nil end
    local mon = screen:monUnder()
    local items = {}
    if mon then
      items[#items + 1] = { label = Strings("STATS"), id = "stats" }
    end
    -- SEND, on the box pane only.  The PARTY half of this screen keeps its own
    -- row bookkeeping and its own mail slots; a row that reached round both to
    -- empty save.party would leave each describing a POKeMON that is not
    -- there.  The party MENU has SEND, and here the cursor can carry one onto
    -- a GLOBAL page anyway.
    if mon and screen.pane == "box" and not onGlobal(screen) then
      local session = globalSession(screen)
      if session and not session:refusalFor(screen.game, mon) then
        items[#items + 1] = { label = Strings("SEND"), id = "send" }
      end
    end
    if mon and screen.pane == "box" and not onGlobal(screen) then
      items[#items + 1] = { label = Strings("RELEASE"), id = "release" }
    end
    -- and the verbs about the BOX rather than about one POKeMON.  SORT came
    -- here off SELECT, which is the marking key now.
    if screen.pane == "box" and not onGlobal(screen) then
      items[#items + 1] = { label = Strings("SORT"), id = "sort" }
      if screen:canUndoSort() then
        items[#items + 1] = { label = Strings("UNDO"), id = "undo" }
      end
    end
    -- START on an EMPTY cell with no box verbs is a wasted press.  Over a
    -- POKeMON it always opens, even when CANCEL is the only row.
    if not (items[1] or mon) then return nil end
    items[#items + 1] = { label = Strings("CANCEL"), id = "cancel" }
    return items
  end

  -- ------- picking several up at once
  --
  -- SELECT used to open SORT.  SORT is a verb about the whole box, so it has
  -- moved to the popup START opens, where the other verbs already are -- and
  -- SELECT is free for what a grid of twenty actually wants: marking.
  --
  -- The same key, the same rules and the same drawing as Red's screen
  -- (modules/Gen1BillsBox/screen.lua, "picking several up at once"), because a
  -- player who learns it on one cartridge should not have to learn it again on
  -- the other.  What differs underneath is only which calls take and put.
  local function markIndex(screen, page, cell)
    for i, entry in ipairs(screen.picked or {}) do
      if entry.cell == cell and entry.global == page.global
         and entry.box == page.box then
        return i
      end
    end
    return nil
  end

  local function currentPage(screen)
    return { global = screen.globalPage ~= nil,
             box = screen.globalPage or screen.boxIndex }
  end

  function Screen:toggleMark()
    if self.held or self.pane ~= "box" then return end
    self.picked = self.picked or {}
    local page = currentPage(self)
    local at = markIndex(self, page, self.boxSlot)
    if at then table.remove(self.picked, at) return end
    local mon = pageMonAt(self, self.boxSlot)
    if not mon then return end
    self.picked[#self.picked + 1] = {
      mon = mon, cell = self.boxSlot, global = page.global, box = page.box,
    }
  end

  function Screen:markedAt(slot)
    if not (self.picked and self.picked[1]) then return false end
    return markIndex(self, currentPage(self), slot) ~= nil
  end

  function Screen:clearMarks()
    local had = self.picked and self.picked[1] ~= nil
    self.picked = {}
    return had and true or false
  end

  function Screen:placeMarks()
    local picked = self.picked or {}
    if not picked[1] then return false end
    local page = currentPage(self)
    local session = globalSession(self)

    local moving = {}
    for _, entry in ipairs(picked) do
      if not (entry.global == page.global and entry.box == page.box) then
        moving[#moving + 1] = entry
      end
    end
    if not moving[1] then self:clearMarks() return true end

    local room = pageCapacity(self) - pageCount(self)
    if room < #moving then
      self:say(Strings("The BOX is full."))
      return false
    end

    -- A global page's own rules, asked of ALL of them before one is taken:
    -- half a mark deposited and half refused is what this avoids.
    if page.global and session then
      for _, entry in ipairs(moving) do
        local refusal = session:refusalFor(self.game, entry.mon)
        if refusal then
          self:say(session:refusalText(refusal))
          return false
        end
      end
    end

    local taken, tickets = {}, {}
    local function putBack()
      for i = #taken, 1, -1 do
        local entry = moving[i]
        if entry.global then
          if session then session:untake(tickets[i]) end
        else
          boxPut(self.save, entry.box, entry.cell, taken[i])
        end
      end
    end

    for i, entry in ipairs(moving) do
      local mon, ticket
      if entry.global then
        if not session then putBack() return false end
        mon, ticket = session:take(self.game, entry.box, entry.cell)
        if not mon then
          putBack()
          self:say(session:refusalText(ticket))
          return false
        end
      else
        mon = boxTake(self.save, entry.box, entry.cell)
        if not mon then putBack() return false end
      end
      taken[i], tickets[i] = mon, ticket
    end

    for _, mon in ipairs(taken) do
      if page.global then
        local index, why = session:put(self.game, intoBox(mon))
        if not index then
          self:say(session:refusalText(why))
          return false
        end
      else
        local cell = freeCell(self.save, page.box)
        if not cell then putBack() return false end
        boxPut(self.save, page.box, cell, intoBox(mon))
      end
    end

    self:clearMarks()
    if option("placeCry", true) and taken[1] then
      pcall(function()
        require("src.core.Sound").playCry(self.game.data, taken[1].species)
      end)
    end
    return true
  end

  -- ------- SEND, from the box
  --
  -- The party menu's SEND takes a POKeMON out of the PARTY -- it asks whether
  -- the party can spare it and it removes it from save.party.  Handing a BOXED
  -- POKeMON to that would deposit it in the GLOBAL BOX and leave the original
  -- where it was: one POKeMON, two places.  So the box's SEND is the box's
  -- own, and it is the move the cursor already makes.
  function Screen:sendToGlobal(cell)
    local session = globalSession(self)
    if not (session and self.pane == "box" and not onGlobal(self)) then return end
    local mon = boxMonAt(self.save, self.boxIndex, cell)
    if not mon then return end
    local refusal = session:refusalFor(self.game, mon)
    if refusal then return self:say(session:refusalText(refusal)) end
    local taken = boxTake(self.save, self.boxIndex, cell)
    if not taken then return end
    local index, why = session:put(self.game, intoBox(taken))
    if not index then
      boxPut(self.save, self.boxIndex, cell, taken)
      return self:say(session:refusalText(why))
    end
  end

  -- ------- sorting a box, and one step back
  --
  -- Red's box has a SAVED cell layout: a gap you left in it is a decision, so
  -- every sort there ends by closing the box up into cells 1..n and COLLAPSE
  -- is the sort that only does that.  Gold's box is a COMPACT array -- the
  -- cart's own Boxes.lua keeps it that way and the only hole this screen ever
  -- shows is the transient one under a POKeMON in hand -- so there is nothing
  -- to collapse, and COLLAPSE is not on the menu.  It is not a feature that
  -- was dropped; it is a feature Gold's storage does not have a use for.
  --
  -- Everything else is Red's, key for key, including the tie-break: table.sort
  -- is not stable, so the position each POKeMON is already in is carried
  -- alongside and used as the last word.  POKeMON that tie keep the order
  -- somebody is looking at.
  local SORT_LABELS = {
    { "BY DEX", "dex" },
    { "BY LEVEL", "level" },
    { "BY NAME", "name" },
    { "BY TYPE", "type" },
  }

  local function sortKey(screen, mode, entry)
    local mon = entry.mon
    local data = screen.game and screen.game.data
    local def = data and data.pokemon and data.pokemon[mon.species]
    if mode == "dex" then return (def and def.dex) or math.huge end
    -- strongest first, which is what a box is usually being tidied for
    if mode == "level" then return -(tonumber(mon.level) or 0) end
    if mode == "name" then return nameOf(screen, mon) end
    -- the primary type, alphabetically: the data carries type names rather
    -- than the cart's numbering, so there is no other order to honour
    if mode == "type" then
      local types = def and def.types
      return tostring(types and types[1] or "")
    end
    return entry.at
  end

  -- Is this box still holding exactly the POKeMON the snapshot was taken of?
  -- Identity, not count: one released and one deposited leaves the count alone
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

  function Screen:sortBox(mode)
    local list = boxList(self.save, self.boxIndex)
    if not list or #list < 2 then return end

    -- One step, and only for this box: changing box while a snapshot is held
    -- would otherwise offer to restore another box's order.
    local snapshot = { box = self.boxIndex, mons = {} }
    for j = 1, #list do snapshot.mons[j] = list[j] end

    local order = {}
    for j = 1, #list do order[j] = { mon = list[j], at = j } end
    -- Every comparison falls back to the CELL the POKeMON is currently in,
    -- not its index in the array: with gaps the two are different orders, and
    -- the one a player means by "keep what I can see" is the one on screen.
    local where = layoutFor(self.save, self.boxIndex)
    for _, entry in ipairs(order) do
      entry.key = sortKey(self, mode, entry)
      entry.cell = where[entry.at] or entry.at
    end
    table.sort(order, function(a, b)
      if a.key ~= b.key then return a.key < b.key end
      return a.cell < b.cell
    end)

    for j = 1, #order do list[j] = order[j].mon end
    -- Every sort ENDS the same way -- the box closed up into cells 1..n --
    -- which is also what makes COLLAPSE a sort like any other rather than a
    -- special case: with gaps in the grid the compact array's order stopped
    -- meaning anything, so "keep what I can see, just close it up" has to be
    -- expressed as an order too.  Recorded on the snapshot so UNDO can put the
    -- gaps back.
    local cells = layoutFor(self.save, self.boxIndex)
    snapshot.cells = {}
    for j = 1, #cells do snapshot.cells[j] = cells[j] end
    for j = 1, #cells do cells[j] = j end
    self.sortUndo = snapshot
  end

  function Screen:canUndoSort()
    local undo = self.sortUndo
    if not undo or undo.box ~= self.boxIndex then return false end
    local list = boxList(self.save, undo.box)
    return list ~= nil and sameMembers(list, undo.mons)
  end

  function Screen:undoSort()
    if not self:canUndoSort() then return end
    local undo = self.sortUndo
    self.sortUndo = nil
    local list = boxList(self.save, undo.box)
    for j = 1, #undo.mons do list[j] = undo.mons[j] end
    -- The gaps come back with the order; a sort that closed the box up and an
    -- UNDO that left it closed would be an undo you can see is incomplete.
    if type(undo.cells) == "table" then
      local cells = layoutFor(self.save, undo.box)
      for j = 1, #cells do cells[j] = undo.cells[j] or j end
    end
  end

  -- SELECT over the box.  Refused with a POKeMON in hand, because a sort that
  -- reordered the box around one that is not in it reads as the box shuffling
  -- itself for no reason.
  --
  -- SELECT rather than another row on START's menu, which is where Red puts
  -- it: START's rows are what you do to ONE POKeMON and a sort is what you do
  -- to the box.  SELECT was a third way to change box here -- L, R and the
  -- header's LEFT/RIGHT are the other two and all of them stay -- so nothing
  -- is lost by giving it the job it has on Red.
  function Screen:openSort()
    -- A sort rewrites the order of a box.  The GLOBAL pages are the union of
    -- every save's outbox in the order the POKeMON were sent, and that order
    -- is what makes a page and a cell mean the same thing on both cartridges
    -- -- so there is nothing here this save is entitled to reorder.
    if onGlobal(self) then return end
    if self.held or self.pane == "header" then return end
    local list = boxList(self.save, self.boxIndex)
    if not list or #list < 2 then
      return self:say(Strings("There is nothing\nto sort."))
    end
    local items = {}
    for _, row in ipairs(SORT_LABELS) do
      items[#items + 1] = { label = Strings(row[1]), id = row[2] }
    end
    if self:canUndoSort() then
      items[#items + 1] = { label = Strings("UNDO"), id = "undo" }
    end
    items[#items + 1] = { label = Strings("CANCEL"), id = "cancel" }
    self.sortMenu = { items = items, index = 1 }
  end

  function Screen:chooseSort(id)
    self.sortMenu = nil
    if not id or id == "cancel" then return end
    if id == "undo" then return self:undoSort() end
    self:sortBox(id)
  end

  function Screen:openActions()
    if self.held or self.pane == "header" then return end
    local items = actionsFor(self)
    if not items then return end
    self.actions = { items = items, index = 1 }
  end

  function Screen:openStats()
    local mon = self:monUnder()
    if not mon then return end
    local game = self.game
    if not (game and game.stack) then return end
    local ok, Screens = pcall(require, "src.ui.Screens")
    if not (ok and type(Screens) == "table") then return end
    -- The cart's own summary, exactly as its BoxMenu opens one.
    if not pcall(Screens.get, game, "Gen2SummaryMenu") then return end
    pcall(Screens.push, game, "Gen2SummaryMenu", {
      mon = mon, save = self.save,
      onClose = function() game.stack:pop() end,
    })
  end

  -- RELEASE is the one thing on this screen that destroys a POKeMON, so it
  -- asks first and NO is where the cursor starts -- the same defaultNo the
  -- cart's own QUIT box uses, and for the same reason.
  function Screen:askRelease()
    local mon = self:monUnder()
    if not (mon and self.pane == "box") then return end
    self.confirm = { mon = mon, choice = 2,
                     text = Strings("Release this\nPOKéMON?") }
  end

  function Screen:doRelease()
    -- RELEASE is the cartridge's own verb over the cartridge's own storage.  A
    -- POKeMON on a GLOBAL page may be sitting in another save entirely, and
    -- "gone forever" is not a thing this save gets to decide about one.  The
    -- row is not offered there; this is the second lock, because the first is
    -- a menu and menus can be reached in more than one way.
    if onGlobal(self) then return end
    local index = self:boxIndexAt(self.boxIndex, self.boxSlot)
    if not index then return end
    -- Copied BEFORE the release, because reconciliation cannot tell which
    -- POKeMON left: it only sees a list one shorter and drops the arrangement's
    -- LAST entry, which would slide every POKeMON after the released one into
    -- its neighbour's cell.  So the entry that goes is named here, and put back
    -- only if the cart's own release actually happened.
    local cells = layoutFor(self.save, self.boxIndex)
    local kept = {}
    for j = 1, #cells do
      if j ~= index then kept[#kept + 1] = cells[j] end
    end
    local ok = Boxes.release(self.save, self.boxIndex, index)
    if not ok then return end
    local store = readStore(self.save)
    if type(store) == "table" then
      store[tostring(self.boxIndex)] = kept
      writeStore(self.save, store)
    end
    self:say(Strings("Released."))
  end

  function Screen:chooseAction(id)
    local cell = self.boxSlot
    self.actions = nil
    if id == "stats" then return self:openStats() end
    if id == "send" then return self:sendToGlobal(cell) end
    if id == "release" then return self:askRelease() end
    if id == "sort" then return self:openSort() end
    if id == "undo" then return self:undoSort() end
  end

  -- ------- input

  local DIRECTIONS = { "up", "down", "left", "right" }

  function Screen:update(_dt)
    self.ticks = (self.ticks + 1) % TICKS
    -- The borrowed renderer's clock is driven from this screen's own counter,
    -- AT ITS OWN RATE -- `iconFor` flips frames every ICON_FRAME_STEPS = 16,
    -- and that is the cadence a Gold POKeMON walks at.
    --
    -- It used to be doubled, to match the Gen 1 box's ANIM_STEPS = 8 on the
    -- grounds that a storage grid next to a party list should not disagree
    -- with it.  The number was borrowed from the wrong screen.  Red's box
    -- animates by MIRRORING one frame the way the hardware's OAM did, and
    -- eight steps of a mirror reads as a shuffle; Gold's icons are a two-pose
    -- WALK, and eight steps of that is simply the walk at double speed.  The
    -- party list this grid actually sits beside is Gold's, at sixteen -- and
    -- this screen draws a party column of its own, so the same POKeMON was
    -- walking at one speed here and another in PARTY MENU.
    --
    -- 240 ticks is fifteen whole frame-flips, so the walk does not jump when
    -- the counter turns over.  The flash reads `self.ticks` directly and is
    -- unaffected either way.
    if self.icons then self.icons.clock = self.ticks end
    local input = self.game and self.game.input
    if not input then return end

    if self.message then
      -- A or B turns the page, and turns past the last one to dismiss it --
      -- the same two buttons the cart's own text box advances on.
      if input:wasPressed("a") or input:wasPressed("b") then
        local _, _, pages = self:messageLines()
        local next = (self.messagePage or 1) + 1
        if next > pages then
          self.message, self.messagePage = nil, nil
        else
          self.messagePage = next
        end
      end
      return
    end

    if self.confirm then
      if input:wasPressed("up") or input:wasPressed("down") then
        self.confirm.choice = self.confirm.choice == 1 and 2 or 1
      elseif input:wasPressed("a") then
        local yes = self.confirm.choice == 1
        self.confirm = nil
        if yes then self:doRelease() end
      elseif input:wasPressed("b") then
        self.confirm = nil
      end
      return
    end

    if self.sortMenu then
      local list = self.sortMenu
      if input:wasPressed("up") then
        list.index = list.index > 1 and list.index - 1 or #list.items
      elseif input:wasPressed("down") then
        list.index = list.index < #list.items and list.index + 1 or 1
      elseif input:wasPressed("a") then
        local item = list.items[list.index]
        self:chooseSort(item and item.id)
      elseif input:wasPressed("b") or input:wasPressed("select") then
        self.sortMenu = nil
      end
      return
    end

    if self.actions then
      local list = self.actions
      if input:wasPressed("up") then
        list.index = list.index > 1 and list.index - 1 or #list.items
      elseif input:wasPressed("down") then
        list.index = list.index < #list.items and list.index + 1 or 1
      elseif input:wasPressed("a") then
        local item = list.items[list.index]
        self:chooseAction(item and item.id)
      elseif input:wasPressed("b") or input:wasPressed("start") then
        self.actions = nil
      end
      return
    end

    for _, dir in ipairs(DIRECTIONS) do
      if input:wasPressed(dir) then
        self.hold = { dir = dir, at = 0 }
        self:move(dir)
      end
    end
    -- Hold to keep moving, at ui.list_menu's own cadence, so a held direction
    -- here moves at the speed a held direction moves everywhere else.
    if self.hold and option("holdMove", true) then
      local down = input.isDown and input:isDown(self.hold.dir)
      if down then
        self.hold.at = self.hold.at + 1
        if self.hold.at >= REPEAT_DELAY
            and (self.hold.at - REPEAT_DELAY) % REPEAT_RATE == 0 then
          self:move(self.hold.dir)
        end
      else
        self.hold = nil
      end
    end

    if input:wasPressed("l") then self:changeBox(-1) end
    if input:wasPressed("r") then self:changeBox(1) end
    -- SELECT marks.  It used to open SORT, which is a verb about the whole box
    -- and now lives in the popup START opens, beside the other verbs.
    if input:wasPressed("select") then self:toggleMark() end

    if input:wasPressed("a") then
      -- A on the header is not a grab: there is nothing under it to pick up,
      -- and LEFT/RIGHT are what it is for.
      if self.pane == "header" then return end
      if self.held then
        self:place()
      elseif self.picked and self.picked[1] and self.pane == "box" then
        -- Something is marked, so A is about the MARK: put all of it here.
        self:placeMarks()
      else
        self:grab()
      end
    elseif input:wasPressed("b") then
      -- B undoes the marks before it undoes anything else: leaving the screen
      -- with six POKeMON marked and nothing said about it is how a player
      -- loses track of what they were doing.
      if self.held then self:returnHeld()
      elseif self:clearMarks() then return
      else self:close() end
    elseif input:wasPressed("start") then
      self:openActions()
    end
  end

  -- ------- drawing

  function Screen:drawHeader()
    Chrome.box(0, 0, 20, HEADER_TH)
    -- The two box arrows and the selector between them: same shape, same
    -- height, same row, so they line up by construction rather than by luck.
    arrow(8, 8, "left")
    arrow(148, 8, "right")
    if self.pane == "header" then arrow(16, 8, "right") end
    Chrome.printThrough(tostring(pageName(self)), 3, 1, palette())
    Chrome.printRightThrough(("%d/%d"):format(pageCount(self),
                                              pageCapacity(self)),
                             18, 1, palette())
  end

  -- Lit for the first stretch of each cycle, dark for the rest.
  function Screen:flashOn()
    return (self.ticks % FLASH_PERIOD) < FLASH_ON
  end

  -- One icon, in the cell it belongs to.  `monDrawnAt` already puts the
  -- carried POKeMON in the cell under the cursor in place of whatever is
  -- there, so the flash is done by SKIPPING that draw on the dark half rather
  -- than by painting a second icon over the first -- which is the Gen 1
  -- screen's arrangement, and the reason its box never shows two POKeMON in
  -- one cell.
  --
  -- The cursor's POKeMON walks whether or not it is in your hand: it is the
  -- one you are looking at either way, and a carried POKeMON that stopped
  -- walking the moment you lifted it is the thing that read as the wrong
  -- animation.
  function Screen:drawCell(mon, x, y, selected)
    if not (mon and self.icons) then return end
    -- Only the icon under the cursor walks; see runtime/icons2.lua.  This
    -- screen borrows a PartyMenu purely as an icon renderer, so it never
    -- reaches the engine's own `iconX` and has to say so itself.
    self.icons.gen1wildAnimate = selected and true or false
    pcall(self.icons.drawIcon, self.icons, mon, x, y)
  end

  function Screen:drawParty()
    for row = 1, PARTY_ROWS do
      local y = PARTY_Y + (row - 1) * PARTY_H
      local selected = self.pane == "party" and self.partySlot == row
      local carried = selected and self.held ~= nil
      if not (carried and not self:flashOn()) then
        self:drawCell(self:monDrawnAt("party", row), PARTY_X, y, selected)
      end
      if self.pane == "party" and self.partySlot == row then
        -- In the gutter to the LEFT of the icon, pointing at it: six rows of
        -- sixteen fill the pane exactly, so there is no band above a party
        -- POKeMON's head for a down arrow to sit in.
        arrow(0, y + 4, "right", self.held ~= nil)
      end
    end
  end

  function Screen:drawGrid()
    -- The rules first, so an icon is never drawn under one.
    for col = 0, COLS do
      line(GRID_X + col * CELL_W, GRID_Y, 1, ROWS * CELL_H)
    end
    for row = 0, ROWS do
      line(GRID_X, GRID_Y + row * CELL_H, COLS * CELL_W + 1, 1)
    end
    for cell = 1, SLOTS do
      local col = (cell - 1) % COLS
      local row = math.floor((cell - 1) / COLS)
      local x = GRID_X + col * CELL_W
      local y = GRID_Y + row * CELL_H
      local selected = self.pane == "box" and self.boxSlot == cell
      local carried = selected and self.held ~= nil
      if not (carried and not self:flashOn()) then
        self:drawCell(self:monDrawnAt("box", cell), x + ICON_DX, y + ICON_DY,
                      selected)
      end
      if self:markedAt(cell) then
        -- A marked cell wears a filled square in its top-left corner, the way
        -- Red's does: the cursor already means "here", and a cell can be both.
        line(x + 2, y + 2, 3, 3)
      end
      if selected then
        arrow(x + ARROW_DX, y + ARROW_DY, "down", self.held ~= nil)
      end
    end
  end

  -- `drawHeld` used to live here: a second pass that drew the carried POKeMON
  -- ON TOP of the grid at the cursor's pixels, while `drawGrid` was still
  -- drawing whatever the cell itself held underneath.  Two icons in one cell,
  -- one of them blinking through the other.  The carried POKeMON is now drawn
  -- BY the grid, in place of the cell's occupant -- see `monDrawnAt` -- so
  -- there is nothing left for a second pass to do.

  function Screen:drawInfo()
    Chrome.box(0, INFO_TY, 20, 18 - INFO_TY)
    local mon = (self.held and self.held.mon) or self:monUnder()
    if not mon then return end
    Chrome.printThrough(nameOf(self, mon), 1, INFO_TY + 1, palette())
    if not mon.isEgg then
      Chrome.printRightThrough(("<LV>%d"):format(mon.level or 1), 19,
                               INFO_TY + 1, palette())
    end
  end

  -- Hung from the bottom edge rather than centred, so the POKeMON the verbs
  -- are about stays visible above it however many rows it grows to.
  function Screen:drawActions()
    local list = self.actions
    if not list then return end
    local th = #list.items * 2 + 2
    local ty = math.max(0, 18 - th)
    Chrome.box(9, ty, 11, th)
    for i, item in ipairs(list.items) do
      local row = ty + 1 + (i - 1) * 2
      if i == list.index then
        Chrome.cursorThrough(10, row, palette())
      end
      Chrome.printThrough(tostring(item.label), 11, row, palette())
    end
  end

  -- The same widget as START's rows, headed the way the box list is headed:
  -- Chrome.box draws the border either way, and the title costs no row.
  function Screen:drawSortMenu()
    local list = self.sortMenu
    if not list then return end
    local th = #list.items * 2 + 2
    local ty = math.max(0, 18 - th)
    Chrome.box(8, ty, 12, th)
    Chrome.printThrough(" " .. Strings("SORT") .. " ", 9, ty, palette())
    for i, item in ipairs(list.items) do
      local row = ty + 1 + (i - 1) * 2
      if i == list.index then
        Chrome.cursorThrough(9, row, palette())
      end
      Chrome.printThrough(tostring(item.label), 10, row, palette())
    end
  end

  function Screen:drawConfirm()
    local confirm = self.confirm
    if not confirm then return end
    Chrome.textbox(0, 12, 18, 4)
    local first, second =
      tostring(confirm.text):match("^([^\n]*)\n?(.*)$")
    Chrome.printThrough(first or "", 1, 14, palette())
    Chrome.printThrough(second or "", 1, 16, palette())
    Chrome.box(14, 7, 6, 5)
    Chrome.printThrough(Strings("YES"), 16, 8, palette())
    Chrome.printThrough(Strings("NO"), 16, 10, palette())
    Chrome.cursorThrough(15, confirm.choice == 1 and 8 or 10, palette())
  end

  function Screen:drawPanel()
    Chrome.clear()
    self:drawHeader()
    line(RULE_X, GRID_Y, 1, ROWS * CELL_H)
    self:drawParty()
    self:drawGrid()
    self:drawInfo()
    self:drawActions()
    self:drawSortMenu()
    self:drawConfirm()
    if self.message then
      Chrome.textbox(0, 12, 18, 4)
      local first, second = self:messageLines()
      Chrome.printThrough(first, 1, 14, palette())
      Chrome.printThrough(second, 1, 16, palette())
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  function Screen:draw()
    self:drawPanel()
  end

  function Screen:drawWidescreen(winW, winH)
    local G = love.graphics
    Chrome.letterbox(winW, winH, 1, 1, 1)
    local scale = Chrome.fitScale(winW, winH)
    G.push()
    G.translate(Chrome.fitOrigin(winW, winH, scale))
    G.scale(scale, scale)
    self:drawPanel()
    G.pop()
  end

  Screen.SLOTS = SLOTS
  Screen.COLS = COLS
  Screen.ROWS = ROWS
  Screen.PARTY_ROWS = PARTY_ROWS

  return Screen
end
