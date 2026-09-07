-- Gen1Dex on Gold, Silver and Crystal: three pages Gold does not have, added
-- to the entry screen Gold does.
--
-- Returns a factory: factory(mod, DexData) -> { install = function() end },
-- which main.lua calls instead of registering any screen at all.
--
-- ------- what this does NOT do
--
-- It does not replace the Pokedex.  Gold's is genuinely good and already
-- carries two of the three things the Gen 1 replacement was built to add: an
-- AREA screen with blinking nests, and a working search with NEW / OLD / A-Z
-- modes on SELECT.  Registering over `Gen2PokedexMenu` would mean
-- re-implementing both to stand still.
--
-- What Gold has no answer for is the third: base stats, evolutions and the
-- learnset.  Its entry is two pages of flavour text and nothing else.  So
-- that is all this adds, and it adds it to the cart's own screen.
--
-- ------- where the pages go
--
-- `DexEntryScreen_MenuActionJumptable` gives the entry four actions along row
-- 17 -- PAGE, AREA, CRY, PRNT -- and PAGE flips between the entry's two
-- pages.  So PAGE simply counts higher: 1, 2, then STATS, EVOLVES, MOVES, and
-- back to 1.
--
-- That is deliberately not a new key.  The cart already has a control that
-- means "next page", it is already on the screen, and it is already labelled.
-- A player who knows Gold presses the thing they would have pressed anyway;
-- one who does not finds it the way they find PAGE.
--
-- UP and DOWN are unbound on Gold's entry view (`PokedexMenu:update`'s entry
-- arm reads only left, right, A and B), so they scroll a page that is longer
-- than its panel -- the movelist, and EEVEE's five evolutions.
--
-- ------- what a page may draw on
--
-- Rows 11 to 15, columns 1 to 18.  That is the description panel: the entry's
-- border is `border(0, 0, 15, 18)` so the interior ends at row 15, a divider
-- runs across row 10, and the action bar is row 17.  Everything above the
-- divider -- the pic, the name, the number, the footprint, the height and the
-- weight -- is the cart's and is left alone on every page, which is what
-- makes these read as more pages of the same entry rather than as a different
-- screen wearing its frame.
--
-- Five rows by eighteen columns is not much, and it is the whole budget.  It
-- is why the stats page is two columns, why the evolution rows are one line
-- each, and why two of the three scroll.

local Gen2Dex = {}

-- The panel, in tiles.
--
-- Row 11 is the page's own name and rows 12 to 15 are its content, which is
-- four rows.  The name costs a row and earns it: Gold's page marker is two
-- tiles of "P" over a digit and its sheet has no digit past 2, so without a
-- word there the player has no way to tell STATS from EVOLVES except by what
-- is written under it.
--
-- Four rows is exactly enough for the stats page -- six stats in two columns
-- of three, then the total -- which is what set the split.
local PANEL_X, PANEL_W = 1, 18
local TITLE_Y = 11
local PANEL_Y, PANEL_H = 12, 4

-- Gold's own page marker sits at (1,9)-(2,10) and its digit tiles only go up
-- to two.  Rather than draw a "P3" the sheet has no glyph for, the marker is
-- blanked on our pages and the page NAMES itself on its first row -- which is
-- also the only label the panel has room for.
local MARKER_X, MARKER_Y, MARKER_W, MARKER_H = 1, 9, 2, 2

-- The cart's two, then ours.
local PAGES = { "dex", "dex", "stats", "evolves", "moves" }
local FIRST_OURS = 3
local LAST_PAGE = #PAGES

Gen2Dex.PAGES = PAGES
Gen2Dex.LAST_PAGE = LAST_PAGE
Gen2Dex.FIRST_OURS = FIRST_OURS

-- Which page a press moves to.  Pure, so the wrap can be checked without a
-- screen: PAGE steps forward and wraps past the last back to the first, which
-- is what Gold's own two-page toggle does with two pages.
function Gen2Dex.nextPage(page)
  local at = tonumber(page) or 1
  if at < 1 or at >= LAST_PAGE then return 1 end
  return at + 1
end

-- How many rows a page wants, so the scroll knows what it is scrolling.
-- Pure, and driven directly by the tests.
function Gen2Dex.rowCount(kind, content)
  content = content or {}
  if kind == "evolves" then return #(content.evolutions or {}) end
  if kind == "moves" then return #(content.moveRows or {}) end
  return 0
end

-- Clamp a scroll offset to a row count.  Separated for the same reason
-- `bleedRects` is in the arena: this is the part with the off-by-ones in it,
-- and it needs no window.
function Gen2Dex.clampScroll(offset, rows, visible)
  visible = visible or PANEL_H
  local most = math.max(0, (rows or 0) - visible)
  offset = math.max(0, math.min(tonumber(offset) or 0, most))
  return offset
end

function Gen2Dex.new(mod, DexData)
  local self = {}

  local Chrome, Strings, TypeChart
  do
    local ok, found = pcall(require, "src.ui.gen2.Chrome")
    Chrome = ok and found or nil
    local okS, foundS = pcall(require, "src.core.Strings")
    Strings = okS and foundS or function(text) return text end
    local okT, foundT = pcall(require, "src.battle.TypeChart")
    TypeChart = okT and foundT or nil
  end

  -- ------- reading the species
  --
  -- Everything on these three pages comes out of dexdata.lua, which is a pure
  -- function of the merged dataset -- so the Gold arm and the Gen 1 arm are
  -- reading the same code, and the two pages cannot drift apart about what a
  -- base stat is or which evolution a species has.
  --
  -- Cached per species, because `drawEntryBody` runs every frame and the
  -- movelist walk is a pass over the items registry.  Keyed on the species
  -- id, cleared when the dataset changes underneath (a content mod's hot
  -- reload), and never big: one entry per mon the player has looked at.
  local cache, cacheData = {}, nil

  local function contentFor(game, species)
    local data = game and game.data
    if not (data and species) then return nil end
    if cacheData ~= data then cache, cacheData = {}, data end
    local hit = cache[species]
    if hit then return hit end

    local def = data.pokemon and data.pokemon[species]
    if not def then return nil end

    local save = game.save
    local okStats, stats = pcall(DexData.stats, data, def, save)
    local okMoves, moves = pcall(DexData.moves, data, def)
    local rows = {}
    if okMoves and moves then
      local okRows, built = pcall(DexData.moveRows, moves)
      if okRows and type(built) == "table" then rows = built end
    end

    hit = {
      def = def,
      stats = okStats and stats or { stats = {}, bst = 0, evolutions = {} },
      moveRows = rows,
    }
    hit.evolutions = hit.stats.evolutions or {}
    cache[species] = hit
    return hit
  end

  self.contentFor = contentFor

  -- ------- drawing
  --
  -- Through the screen's own helpers rather than through Chrome directly:
  -- `screen:text` prints inverted through the dex's palette and `screen:blank`
  -- clears to the same paper those strings are drawn on, so a page written
  -- this way is in the dex's colours without knowing what they are.

  local function blankPanel(screen)
    screen:blank(PANEL_X, TITLE_Y, PANEL_W, PANEL_H + 1)
    screen:blank(MARKER_X, MARKER_Y, MARKER_W, MARKER_H)
  end

  -- Right-aligned within a field ending at `xEnd` (exclusive), which is how
  -- a number belongs in a column of numbers.  Chrome's own right-print, with
  -- the inversion the dex draws everything through.
  local function printRight(screen, text, xEnd, y)
    if Chrome and Chrome.printRightThrough then
      local palette = screen.gfx and screen.gfx.palette
      if palette then
        Chrome.printRightThrough(tostring(text), xEnd, y, palette, true)
        return
      end
    end
    -- No chrome to right-align with: left-print it rather than drop it.
    screen:text(tostring(text), xEnd - #tostring(text), y)
  end

  -- ---- STATS
  --
  -- Six stats and their total in five rows, which needs two columns: three
  -- stats each side, and the total on the row below with the panel to itself.
  --
  -- The Gen 1 page prints numbers and no bars, and says why at length: a bar
  -- wide enough to read costs pixels the column has not got, and a number you
  -- can compare is worth more than a bar you cannot.  That argument is
  -- stronger here, not weaker -- this panel is eighteen tiles wide against
  -- that page's whole body -- so this page prints numbers too, and the two
  -- read the same way.
  local STAT_COL_X = { 1, 10 }
  local STAT_COL_END = { 9, 19 }

  local function drawStats(screen, content)
    local stats = content.stats.stats or {}
    for index, stat in ipairs(stats) do
      -- Down the left column first, then down the right: reading order, and
      -- it keeps HP/ATK/DEF together the way every other screen prints them.
      local column = index <= 3 and 1 or 2
      local y = PANEL_Y + ((index - 1) % 3)
      screen:text(stat.key, STAT_COL_X[column], y)
      printRight(screen, stat.value or 0, STAT_COL_END[column], y)
    end

    -- The total, on the fourth row under both columns.
    local y = PANEL_Y + 3
    screen:text(Strings("TOTAL"), STAT_COL_X[1], y)
    printRight(screen, content.stats.bst or 0, STAT_COL_END[2], y)
  end

  -- ---- EVOLVES
  --
  -- One line per evolution: how, then what.  EEVEE has five here where it had
  -- three on Red, which is exactly why this is a page of its own rather than
  -- a corner of the stats one, and why it scrolls.
  local function drawEvolves(screen, content, scroll)
    local rows = content.evolutions or {}
    if #rows == 0 then
      screen:text(Strings("NO EVOLUTION"), PANEL_X, PANEL_Y)
      return
    end
    for slot = 1, PANEL_H do
      local row = rows[slot + scroll]
      if row then
        local y = PANEL_Y + slot - 1
        -- The method on the left, the species on the right, because the
        -- species is the answer and the right edge is where the eye lands
        -- after reading the method.  A name is at most ten glyphs and the
        -- longest method label is "LEVEL 20 ATK>DEF", so the two are printed
        -- from their own ends and meet in the middle rather than being
        -- packed into one string that might not fit.
        screen:text(row.label or "", PANEL_X, y)
        printRight(screen, row.name or "", PANEL_X + PANEL_W, y)
      end
    end
  end

  -- ---- MOVES
  --
  -- dexdata.lua's own rows, headings included, so the LEARNED and TM/HM
  -- sections are the same sections the Gen 1 page shows in the same order.
  local function drawMoves(screen, content, scroll)
    local rows = content.moveRows or {}
    if #rows == 0 then
      screen:text(Strings("NO MOVES"), PANEL_X, PANEL_Y)
      return
    end
    for slot = 1, PANEL_H do
      local row = rows[slot + scroll]
      if row then
        screen:text(row.text or "", PANEL_X, PANEL_Y + slot - 1)
      end
    end
  end

  local DRAW = { stats = drawStats, evolves = drawEvolves, moves = drawMoves }
  local TITLE = { stats = "STATS", evolves = "EVOLVES", moves = "MOVES" }

  -- What a page is called, printed where Gold's page digit was.  Two tiles is
  -- not enough for a word, so the title goes on the divider row's left end
  -- instead -- which is blank on our pages because the marker is.
  self.title = function(kind) return TITLE[kind] end

  -- The whole of a page, from the screen and its scroll.  Guarded by the
  -- caller; this raises rather than swallowing, so a broken page is reported
  -- once and stood down from rather than drawn wrong every frame.
  function self.drawPage(screen, kind, content, scroll)
    blankPanel(screen)
    local draw = DRAW[kind]
    if not draw then return end
    screen:text(Strings(TITLE[kind] or ""), PANEL_X, TITLE_Y)
    -- A page longer than its panel says so, on the title row's right end,
    -- because there is nothing else on the screen to tell a player that UP
    -- and DOWN do anything here.
    local rows = Gen2Dex.rowCount(kind, content)
    if rows > PANEL_H then
      printRight(screen, ("%d/%d"):format(
        math.min(rows, (scroll or 0) + PANEL_H), rows),
        PANEL_X + PANEL_W, TITLE_Y)
    end
    draw(screen, content, scroll or 0)
  end

  -- ------- installing
  --
  -- Two wraps on Gold's own class, both idempotent by identity so a hot
  -- reload does not wrap a wrapper -- which would double-count every PAGE
  -- press and scroll twice per key.
  local MARK = "__gen1DexGen2"

  function self.install()
    local ok, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (ok and type(PokedexMenu) == "table") then
      mod.log:warn("no src.ui.gen2.PokedexMenu; the extra dex pages stand down")
      return false
    end
    if rawget(PokedexMenu, MARK) then return true end

    local baseUpdate = PokedexMenu.update
    local baseDraw = PokedexMenu.drawEntryBody
    if type(baseUpdate) ~= "function" or type(baseDraw) ~= "function" then
      mod.log:warn("src.ui.gen2.PokedexMenu has no update/drawEntryBody; the "
        .. "extra dex pages stand down")
      return false
    end

    -- Whether the feature is on, asked every time rather than captured: the
    -- row is live, so turning it off is Gold's own two-page entry back with
    -- no relaunch.
    local function enabled()
      return mod.options:get("gen2_pages") ~= false
    end

    -- One place that knows what page a screen is on and what is on it, so
    -- the update arm and the draw arm cannot disagree.
    -- An entry the dex has never met is opened by gen2unseen.lua with its
    -- name, its kind, its footprint and its cry all taken away.  Base stats,
    -- what it evolves into and every move it learns would put the whole
    -- POKeMON back on the screen the mask exists to keep it off -- so our
    -- three pages are simply not there for it, and PAGE goes back to being
    -- the cart's own toggle between two blank description pages.
    --
    -- Asked here rather than at the two call sites so the update arm and the
    -- draw arm cannot disagree about it, which is what `pageKind` is for.
    local function seenHere(screen)
      local row = type(screen.current) == "function" and screen:current() or nil
      return row ~= nil and row.seen == true
    end

    local function pageKind(screen)
      local page = screen.page or 1
      if page < FIRST_OURS then return nil end
      if not seenHere(screen) then return nil end
      return PAGES[page]
    end

    PokedexMenu.update = function(screen, dt)
      -- `seenHere` belongs in this bail as well as in `pageKind`: without it
      -- the page counter below would still step PAGE round all five, and an
      -- unseen entry would answer three presses with nothing visible before
      -- coming back to a page it draws.
      if not enabled() or screen.view ~= "entry" or screen.newEntry
          or not seenHere(screen) then
        screen.gen1dexScroll = 0
        return baseUpdate(screen, dt)
      end

      local kind = pageKind(screen)
      local input = screen.game and screen.game.input

      -- UP and DOWN are unbound on Gold's entry, so they are ours to scroll
      -- with -- and only on a page that has something to scroll.
      if kind and input then
        local row = screen:current()
        local content = row and contentFor(screen.game, row.species)
        if content then
          local rows = Gen2Dex.rowCount(kind, content)
          if rows > PANEL_H then
            local moved = false
            if input:wasPressed("down") then
              screen.gen1dexScroll = (screen.gen1dexScroll or 0) + 1
              moved = true
            elseif input:wasPressed("up") then
              screen.gen1dexScroll = (screen.gen1dexScroll or 0) - 1
              moved = true
            end
            screen.gen1dexScroll =
              Gen2Dex.clampScroll(screen.gen1dexScroll, rows, PANEL_H)
            if moved then return end
          end
        end
      end

      -- The page counter itself.
      --
      -- A is NOT intercepted.  Gold's four entry actions are a file-local
      -- (`ENTRY_ACTIONS`, not a member of the class), so there is no honest
      -- way to ask which one the cursor is on -- and no need to.  PAGE is the
      -- only one of the four that moves `self.page`, so the cart is left to
      -- run the press and the page is read afterwards: if it moved, that was
      -- PAGE, and the flip it made between 1 and 2 is replaced with the next
      -- step round ours.
      --
      -- That holds for every page.  From 1 the cart goes to 2, from 2 to 1,
      -- and from any of ours to 2 -- all of which differ from where they
      -- started, so the move is always seen.  AREA, CRY, PRNT and B leave the
      -- page alone and fall through untouched.
      local before = screen.page
      local result = baseUpdate(screen, dt)
      if screen.page ~= before then
        if screen.view == "entry" then
          screen.page = Gen2Dex.nextPage(before)
        end
        screen.gen1dexScroll = 0
      end
      return result
    end

    -- Reported once and then stood down from, the way the theme is: this runs
    -- on every frame of the entry screen, and a broken extra page should cost
    -- the page rather than the dex.
    local broken = false

    PokedexMenu.drawEntryBody = function(screen, row, entry)
      local kind = enabled() and not screen.newEntry and pageKind(screen)
      if not kind or broken then return baseDraw(screen, row, entry) end

      -- The cart's own body first: the frame, the pic, the name, the number,
      -- the footprint, the height and the weight, and the action bar.  Then
      -- the description panel is cleared and ours goes in its place, so
      -- everything above the divider is Gold's on every page.
      baseDraw(screen, row, entry)

      local content = contentFor(screen.game, row and row.species)
      if not content then return end

      local okDraw, problem = pcall(function()
        self.drawPage(screen, kind, content, screen.gen1dexScroll or 0)
      end)
      if not okDraw then
        broken = true
        mod.log:warn("the extra dex pages stood down for this session: %s",
                     tostring(problem))
      end
    end

    PokedexMenu[MARK] = true
    mod.log:info("STATS, EVOLVES and MOVES added to Gold's dex entry")
    return true
  end

  return self
end

return Gen2Dex
