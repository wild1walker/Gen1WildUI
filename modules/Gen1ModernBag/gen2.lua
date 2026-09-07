-- Gen1ModernBag on Gold, Silver and Crystal: what the cart's PACK does not do.
--
-- Returns a factory: factory(mod) -> { install = function() end }, which
-- main.lua calls instead of registering a bag of its own.
--
-- ------- what this does NOT do
--
-- It does not replace the PACK.  Gold's already has the two biggest things
-- this mod gives Red's: pockets -- ITEMS, POKe BALLS, KEY ITEMS, TM/HM, with
-- the cart's own tab strip -- and a description under the list, with a TM
-- showing its MOVE's description rather than the TM's.  Red has neither.
--
-- What is left is how a pocket's list is BUILT, and that is one method:
--
--     function PackMenu:rebuild()      src/ui/gen2/PackMenu.lua:292
--
-- It reads `save.inventory` through `Bag.order`, keeps what belongs to the
-- open pocket, and writes `self.rows`.  Everything this file does happens
-- after that and before the draw: filter the rows, sort them, float the
-- pinned ones.  The cart still owns the selection, the quantity flow, the
-- item submenu's own actions, the tab strip and every pixel of the drawing.
--
-- ------- the four, and where each one went
--
--   no capacity limit   NOTHING TO DO.  The Gen 1 arm patches `Bag.add` and
--                       `Bag.capacity`, and `src/inventory/Bag.lua` is shared
--                       -- Gold's own PackMenu requires it (PackMenu.lua:13)
--                       and calls `Bag.order` through it.  So the patch was
--                       already generation-agnostic, and it lifts a CHECK
--                       rather than changing a layout: `save.inventory` is an
--                       id-to-count table on both carts either way.
--
--   sorting             a mode per pocket, applied to `self.rows`.
--
--   pinned items        floated to the top of their own pocket, which is what
--                       pinning means on a screen with fixed tabs.
--
--   search              a filter on `self.rows`, with the query typed on
--                       Gold's own naming screen.
--
-- ------- and the one that did not port
--
-- FAVOURITES, on Red, is a POCKET -- a virtual tab holding whatever you put
-- in it.  Gold's tab strip is four fixed pockets drawn from the cart's own
-- `POCKETS`, and a fifth would mean replacing the strip, which is the one
-- thing this arm exists to avoid.  PIN does the half of it that fits: an item
-- you want at hand is at the top of the pocket it already lives in.
--
-- ------- the keys
--
-- Gold's PACK reads left/right (pockets), up/down (cursor), A (submenu), B
-- (out) and SELECT (the cart's own item move).  START is the only key it does
-- not read, so START is where SORT and SEARCH go.
--
-- PIN goes on the item submenu instead, because it is a thing you do to ONE
-- item and that menu is the cart's own idiom for exactly that.  Only one row
-- is added, and that is a limit rather than a preference: the submenu box is
-- drawn upward from row 11 or 12 at two rows an entry
-- (`PackMenu:drawSubmenu`), so a sixth entry is the last one that fits on the
-- screen and the cart already uses five.

local BagGen2 = {}

-- Shared with the Gen 1 arm, deliberately: the same two save keys, in the
-- mod's own store, so a player who moves a save between carts finds the
-- pockets in the order they left them and the same things pinned.
local PINNED_KEY = "pinned_items"
local SORT_KEY = "pocket_sort"

-- CUSTOM is not a rule, it is the absence of one: leave `self.rows` exactly as
-- the cart built them.  On TM/HM that means the cart's own tmhmKey order,
-- which is `engine/items/tmhm.asm:341` and is already the right answer -- so
-- it is the default there and A-Z is the default everywhere else.
local SORT_MODES = { "CUSTOM", "ALPHA", "QUANTITY" }
local SORT_LABELS = {
  CUSTOM = "CUSTOM", ALPHA = "A-Z", QUANTITY = "QUANTITY",
}

BagGen2.SORT_MODES = SORT_MODES
BagGen2.SORT_LABELS = SORT_LABELS

function BagGen2.defaultSort(pocketId)
  return pocketId == "TM_HM" and "CUSTOM" or "ALPHA"
end

-- The next mode in the ring, so SORT is one press rather than a picker.
function BagGen2.nextSort(mode)
  local at = 1
  for i, id in ipairs(SORT_MODES) do
    if id == mode then at = i break end
  end
  return SORT_MODES[(at % #SORT_MODES) + 1]
end

-- ------- the three passes
--
-- All pure, all driven by the tests, and all in the order they are applied:
-- a search narrows what there is, a sort arranges what is left, and the pins
-- float to the top of that.  Sorting before filtering would do the same work
-- on rows nobody is going to see.

-- Case-insensitive substring, on the name the cart already put on the row.
-- Matching the NAME rather than the id is what makes "POTION" find SUPER
-- POTION, and what makes a translated game searchable in its own language.
function BagGen2.filterRows(rows, query)
  if type(query) ~= "string" or query == "" then return rows end
  local needle = query:upper()
  local out = {}
  for _, row in ipairs(rows or {}) do
    local name = tostring(row.name or row.id or ""):upper()
    if name:find(needle, 1, true) then out[#out + 1] = row end
  end
  return out
end

-- A stable sort, because two items with the same count must not swap places
-- every time the pocket is rebuilt -- which is every frame a quantity changes.
-- `table.sort` is not stable, so the original index is the last tiebreak.
local function stableBy(rows, less)
  local order = {}
  for i, row in ipairs(rows) do order[i] = { row = row, at = i } end
  table.sort(order, function(a, b)
    if less(a.row, b.row) then return true end
    if less(b.row, a.row) then return false end
    return a.at < b.at
  end)
  local out = {}
  for i, entry in ipairs(order) do out[i] = entry.row end
  return out
end

function BagGen2.sortRows(rows, mode)
  rows = rows or {}
  if mode == "ALPHA" then
    return stableBy(rows, function(a, b)
      return tostring(a.name or a.id or ""):upper()
           < tostring(b.name or b.id or ""):upper()
    end)
  elseif mode == "QUANTITY" then
    -- Most first, which is what the question "how many do I have" wants.
    return stableBy(rows, function(a, b)
      return (tonumber(a.count) or 0) > (tonumber(b.count) or 0)
    end)
  end
  -- CUSTOM, and anything unrecognised: the cart's own order, untouched.
  return rows
end

-- Pinned rows to the top, in the order they were pinned, and everything else
-- after them in the order the sort left it.  Stable on both sides.
function BagGen2.floatPinned(rows, pinnedIndex)
  if type(pinnedIndex) ~= "table" or not next(pinnedIndex) then return rows end
  local top, rest = {}, {}
  for _, row in ipairs(rows or {}) do
    if pinnedIndex[row.id] then top[#top + 1] = row else rest[#rest + 1] = row end
  end
  if #top == 0 then return rows end
  table.sort(top, function(a, b)
    return (pinnedIndex[a.id] or 0) < (pinnedIndex[b.id] or 0)
  end)
  for _, row in ipairs(rest) do top[#top + 1] = row end
  return top
end

-- The whole of it, in one call, so the wrap below is one line and the order
-- of the three passes is stated once.
function BagGen2.arrange(rows, opts)
  opts = opts or {}
  local out = BagGen2.filterRows(rows, opts.query)
  out = BagGen2.sortRows(out, opts.sort)
  return BagGen2.floatPinned(out, opts.pinned)
end

-- id -> position, from the stored list, so `floatPinned` can order by when a
-- thing was pinned without walking the list per row.
function BagGen2.indexOf(list)
  local out = {}
  for i, id in ipairs(list or {}) do
    if type(id) == "string" and out[id] == nil then out[id] = i end
  end
  return out
end

-- Toggle an id in a stored order, returning the new list.  Pure, so the two
-- halves of "is it pinned" and "pin it" cannot disagree.
function BagGen2.togglePinned(list, id)
  local out = {}
  local removed = false
  for _, existing in ipairs(list or {}) do
    if existing == id then removed = true else out[#out + 1] = existing end
  end
  if not removed then out[#out + 1] = id end
  return out, not removed
end

function BagGen2.new(mod)
  local self = {}

  -- ------- the stored preferences
  --
  -- Read through the mod's own save store, which is where the Gen 1 arm keeps
  -- them under the same two keys.  Held in memory for the life of the screen
  -- and written back on change, because `rebuild` runs on every pocket switch
  -- and every quantity change.
  local pinnedList, sorts

  local function load()
    local okPinned, storedPinned = pcall(mod.save.get, mod.save, PINNED_KEY, {})
    local okSorts, storedSorts = pcall(mod.save.get, mod.save, SORT_KEY, {})
    pinnedList = {}
    if okPinned and type(storedPinned) == "table" then
      for _, id in ipairs(storedPinned) do
        if type(id) == "string" then pinnedList[#pinnedList + 1] = id end
      end
    end
    sorts = {}
    if okSorts and type(storedSorts) == "table" then
      for pocket, mode in pairs(storedSorts) do
        if type(pocket) == "string" and SORT_LABELS[mode] then
          sorts[pocket] = mode
        end
      end
    end
  end

  local function ensure()
    if not pinnedList then load() end
  end

  local function sortFor(pocketId)
    ensure()
    return sorts[pocketId] or BagGen2.defaultSort(pocketId)
  end

  local function setSort(pocketId, mode)
    ensure()
    sorts[pocketId] = mode
    pcall(mod.save.set, mod.save, SORT_KEY, sorts)
  end

  local function pinnedIndex()
    ensure()
    return BagGen2.indexOf(pinnedList)
  end

  local function togglePin(id)
    ensure()
    local out, pinned = BagGen2.togglePinned(pinnedList, id)
    pinnedList = out
    pcall(mod.save.set, mod.save, PINNED_KEY, pinnedList)
    return pinned
  end

  self.sortFor, self.setSort = sortFor, setSort
  self.pinnedIndex, self.togglePin = pinnedIndex, togglePin
  self.reload = load

  local function enabled()
    return mod.options:get("gen2_pack") ~= false
  end

  -- ------- installing

  local MARK = "__gen1BagGen2"

  function self.install()
    local ok, PackMenu = pcall(require, "src.ui.gen2.PackMenu")
    if not (ok and type(PackMenu) == "table") then
      mod.log:warn("no src.ui.gen2.PackMenu; the pack additions stand down")
      return false
    end
    if rawget(PackMenu, MARK) then return true end

    local baseRebuild = PackMenu.rebuild
    local baseSubmenuRows = PackMenu.submenuRows
    local baseChoose = PackMenu.chooseSubmenu
    local baseUpdate = PackMenu.update
    if type(baseRebuild) ~= "function" or type(baseSubmenuRows) ~= "function"
        or type(baseChoose) ~= "function" or type(baseUpdate) ~= "function" then
      mod.log:warn("src.ui.gen2.PackMenu is not the shape this expects; the "
        .. "pack additions stand down")
      return false
    end

    -- ---- the list
    --
    -- Reported once and stood down from, the way the theme is: this runs on
    -- every pocket switch, and a broken arrangement should cost the
    -- arrangement rather than the bag.
    local broken = false

    PackMenu.rebuild = function(screen, ...)
      baseRebuild(screen, ...)
      if broken or not enabled() then return end
      local okArrange, problem = pcall(function()
        local pocketId = screen:pocket().id
        screen.rows = BagGen2.arrange(screen.rows, {
          query = screen.gen1bagQuery,
          sort = sortFor(pocketId),
          pinned = pinnedIndex(),
        })
        -- The cursor was clamped against the pre-arrangement list; the rows
        -- may now be fewer, so it is clamped again against what is actually
        -- there.  CANCEL is `#rows + 1`, which is why this is not `#rows`.
        screen.index = math.max(1, math.min(screen.index, #screen.rows + 1))
        screen:ensureVisible()
      end)
      if not okArrange then
        broken = true
        mod.log:warn("the pack additions stood down for this session: %s",
                     tostring(problem))
      end
    end

    -- ---- PIN, on the cart's own per-item menu
    --
    -- Appended rather than inserted, so USE stays the default the cursor
    -- opens on (`db 1 ; default option`) and every existing muscle memory is
    -- unchanged.  Never in a battle: the battle submenu is USE / QUIT and
    -- arranging the bag is not a thing to be doing mid-fight.
    PackMenu.submenuRows = function(screen, itemId, ...)
      local rows = baseSubmenuRows(screen, itemId, ...)
      if not enabled() or broken then return rows end
      if type(rows) ~= "table" then return rows end
      if screen.inBattle and screen:inBattle() then return rows end
      -- Five is the cart's longest menu and six is the last that fits on the
      -- screen; anything already at six is left alone rather than pushed off
      -- the top.
      if #rows >= 6 then return rows end
      local out = {}
      for i, id in ipairs(rows) do out[i] = id end
      -- The label IS the id: `drawSubmenu` prints `SUBMENU_LABEL[id] or id`,
      -- so a row named for what it does needs no entry in the cart's table.
      out[#out + 1] = pinnedIndex()[itemId] and "UNPIN" or "PIN"
      return out
    end

    PackMenu.chooseSubmenu = function(screen, ...)
      local menu = screen.submenu
      local id = menu and menu.rows and menu.rows[menu.index]
      if id == "PIN" or id == "UNPIN" then
        local row = menu.row
        if row and row.id then togglePin(row.id) end
        screen.submenu = nil
        screen:rebuild()
        return
      end
      return baseChoose(screen, ...)
    end

    -- ---- SORT and SEARCH, on the one key the cart does not read
    PackMenu.update = function(screen, ...)
      if not enabled() or broken then return baseUpdate(screen, ...) end
      local input = screen.game and screen.game.input
      -- Only on the plain list: not over the submenu, not mid-message, and
      -- not while the cart's own item move is armed.
      local busy = screen.submenu or screen.message or screen.switching
        or (screen.inBattle and screen:inBattle())
      if input and not busy and input:wasPressed("start") then
        local okStart = pcall(self.openMenu, screen)
        if okStart then return end
      end
      return baseUpdate(screen, ...)
    end

    PackMenu[MARK] = true
    mod.log:info("SORT, SEARCH and PIN added to Gold's PACK")
    return true
  end

  -- ------- the START menu
  --
  -- Three rows, on the cart's own Menu so it looks like every other small
  -- menu in the game.  SEARCH's third row only appears while a search is
  -- live, because CLEAR with nothing to clear is a row that does nothing.
  function self.openMenu(screen)
    local game = screen.game
    if not (game and mod.ui and mod.ui.Menu) then return end

    local pocketId = screen:pocket().id
    local items = {
      {
        label = ("SORT: %s"):format(SORT_LABELS[sortFor(pocketId)] or "?"),
        onSelect = function()
          setSort(pocketId, BagGen2.nextSort(sortFor(pocketId)))
          screen:rebuild()
        end,
      },
      {
        label = "SEARCH",
        onSelect = function() self.askQuery(screen) end,
      },
    }
    if screen.gen1bagQuery then
      items[#items + 1] = {
        label = "CLEAR SEARCH",
        onSelect = function()
          screen.gen1bagQuery = nil
          screen:rebuild()
        end,
      }
    end

    local height = #items * 2 + 2
    game.stack:push(mod.ui.Menu.new(game, items, {
      tx = 20 - 14, ty = 18 - height, tw = 14, th = height,
    }))
  end

  -- The query itself, typed on Gold's own naming screen -- the cart's
  -- keyboard, in the cart's own idiom, rather than a text field of ours.
  --
  -- ------- who takes the keyboard back down
  --
  -- The screen does not take itself down.  `NamingScreen:accept` calls
  -- `onDone(name)` and returns, and all five of the cart's own callers pop it
  -- from inside that callback (NamePick:118, BattleState:3719, BoxMenu:699,
  -- World:3180 and World:7706).  This one did not, and that was not a
  -- cosmetic slip -- it was the only way off the screen:
  --
  --   B on Gold's naming screen is DELETE, not cancel.  The `.b` arm is
  --   `deleteCharacter` and the comment beside it says so: "the only way out
  --   is END (or an empty name, which callers treat as keep the default)".
  --
  --   `onCancel` is stored by NamingScreen.new and then called by nothing at
  --   all, so the empty handler this used to pass was never going to run.
  --
  -- So SEARCH opened a keyboard with no exit: B ate the query one letter at a
  -- time, END confirmed and left the screen standing, and the filter it had
  -- just applied was to a PACK the player could no longer see.  One missing
  -- pop, and both halves of the bug.
  function self.askQuery(screen)
    local game = screen.game
    local okScreens, Screens = pcall(require, "src.ui.Screens")
    if not (okScreens and Screens and Screens.push) then return end

    -- By identity rather than a bare pop: if anything else has been pushed
    -- over the keyboard, that is the thing a bare pop would take, and this
    -- would trade a stuck keyboard for a missing screen.
    local keyboard
    local function dismiss()
      local stack = game and game.stack
      if not (stack and keyboard and type(stack.top) == "function") then return end
      if stack:top() ~= keyboard then return end
      stack:pop()
    end

    keyboard = Screens.push(game, "Gen2NamingScreen", {
      prompt = "SEARCH FOR?",
      maxLength = 10,
      initial = screen.gen1bagQuery or "",
      onDone = function(text)
        dismiss()
        -- Nothing typed clears the search -- which is also the way out.  END
        -- on an empty query is the cancel this screen does not otherwise
        -- have, and it is the reading the cart already gives an empty name.
        screen.gen1bagQuery = (text ~= "" and text) or nil
        screen:rebuild()
      end,
    })
  end

  return self
end

return BagGen2
