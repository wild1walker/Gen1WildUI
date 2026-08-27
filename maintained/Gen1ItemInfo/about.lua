-- Gen1ItemInfo: ABOUT, in the bag.
--
-- Returns a factory: factory(mod, describe, wants) -> { install = fn }.
--
-- ------- what it is
--
-- Press A on an item in the bag and Gen 1 offers USE and TOSS.  This adds a
-- third row -- ABOUT -- which prints what the item is in the game's own text
-- box.  Every item in the bag has one, TMs and HMs included.
--
-- ------- why it hangs off Menu rather than off the bag
--
-- The item options box is built inside `BagMenu.new`'s onChoose closure and
-- handed to nobody, the same way the mart's lists are.  It could be reached
-- by wrapping `BagMenu.new` and then wrapping the list's onChoose -- except
-- that the bag is the one screen in this game with two of them: Gen1ModernBag
-- adds a second options menu on START (SORT / FAVORITE / PIN / MOVE ITEM),
-- and an item you can read about from one press and not the other is worse
-- than not adding the row at all.
--
-- So the rule is about POSITION, not about which mod built the menu: a Menu
-- opened directly over the bag list is a menu ABOUT the item under the bag's
-- cursor, whoever opened it, and it gets an ABOUT row.  The stack is what
-- answers that -- at the moment `Menu.new` runs, the menu has not been pushed
-- yet, so the top of the stack is still the list the player pressed on.
--
-- It also means this needs to know nothing about Gen1ModernBag, and keeps
-- working if the bag is switched off, replaced, or upgraded underneath it.
--
-- ------- with one exception, which position alone cannot see
--
-- A menu row can open a SECOND menu, and Menu pops itself before running a
-- row's onSelect -- so by the time the second one is built, the bag list is
-- back on top and it looks exactly like the first.  Gen1ModernBag's tools
-- menu does this: SORT opens the pocket's sort-order picker, which is about
-- the pocket and not about the item, and would otherwise grow an ABOUT row of
-- its own.
--
-- A submenu is recognised as one by WHERE IT IS OPENED FROM rather than by
-- what is in it: every row of a menu this added a row to runs inside a flag,
-- and a menu built while that flag is up is a submenu of a menu already
-- offered ABOUT.  Which stays true of a sort picker, a filter picker or
-- anything else a bag mod hangs off its own menu, without this file knowing
-- any of their names.
--
-- ------- where the row goes
--
-- Before CANCEL when there is one, and last when there is not.  Never first:
-- the cursor opens on row one, and the row a player reaches for without
-- looking must stay the row it has always been.
--
-- A caller that sized its own box gets that size adjusted, because Menu
-- anchors its choices to the BOTTOM interior row and lets slack fall under
-- the top edge (draw_start_menu.asm, and the comment in Menu:draw).  Adding
-- a row to a box that was measured for two pushes the first choice up
-- through the border instead of growing the box -- BagMenu passes th = 5 for
-- USE and TOSS, so ABOUT needs it to be 7.  A box that let Menu measure it
-- is measured again with the new row in it and needs nothing; a box that was
-- already reaching the bottom of the screen moves up instead of growing past
-- the edge.
--
-- ------- the one item with no ABOUT row
--
-- The BICYCLE, because pressing A on it never opens an options box at all:
-- StartMenu_Item jumps straight to .useOrTossItem for it and the engine's
-- BagMenu follows (src/ui/BagMenu.lua, "the BICYCLE never gets the option
-- box").  Adding one would mean taking the shortcut away, which is a change
-- to how the bike is ridden in exchange for a sentence about a bike.

return function(mod, describe, wants)
  local Menu = mod.ui.Menu
  local TextBox = mod.ui.TextBox
  local Strings = require("src.core.Strings")

  local M = {}

  local PATCH = "__gen1ItemInfoMenu"
  local LABEL = "ABOUT"
  local ROW_STEP = 2            -- Menu's own default, in tiles

  -- The item the bag's cursor is on, or nil if the thing under this menu is
  -- not a bag.  `kind` is what BagMenu stamps on its list ("bag"); a cancel
  -- row carries no value and is not an item.
  local function bagItem(game)
    local stack = game and game.stack
    local top = type(stack) == "table" and stack.top and stack:top()
    if type(top) ~= "table" or top.kind ~= "bag" then return nil end
    local item = top.items and top.items[top.index or 1]
    if type(item) ~= "table" or item.cancel then return nil end
    return item.value
  end

  -- A row of a menu this added ABOUT to is running.  Anything it opens is a
  -- submenu of that menu, not a second menu about the item.  A plain flag is
  -- enough: menus are opened synchronously from inside onSelect, on one
  -- thread, and the flag is restored on the way out whether the row returned
  -- or raised.
  local nested = false

  local function guard(row)
    local onSelect = row.onSelect
    if type(onSelect) ~= "function" then return end
    row.onSelect = function(...)
      local was = nested
      nested = true
      local ok, err = pcall(onSelect, ...)
      nested = was
      -- rethrown with level 0 so the message keeps the position it was
      -- raised at rather than gaining this line's
      if not ok then error(err, 0) end
    end
  end

  local function alreadyThere(items)
    for _, row in ipairs(items) do
      if type(row) == "table" and row.label == LABEL then return true end
    end
    return false
  end

  -- Both spellings, because a CANCEL row reaches here two ways: through
  -- Strings, which is what the engine's own menus do, and as a plain literal,
  -- which is what a mod's rows tend to be.
  local function isCancel(label)
    return label == "CANCEL" or label == Strings("CANCEL")
  end

  local function insertAt(items)
    for i, row in ipairs(items) do
      if type(row) == "table" and isCancel(row.label) then return i end
    end
    return #items + 1
  end

  -- A menu is drawn from ty to ty + th - 1 and the screen ends at row 17, so
  -- a box that was already reaching the bottom has to move UP by the row this
  -- adds rather than grow past the edge.  Gen1ModernBag's tools menu is
  -- exactly that case: five rows from row 5 ends on row 16, and a sixth would
  -- have ended on row 18.  Only a menu this actually added a row to is moved.
  local ROWS = 18

  local function keepOnScreen(menu)
    if type(menu) ~= "table" then return menu end
    local ty, th = tonumber(menu.ty), tonumber(menu.th)
    if not (ty and th) then return menu end
    if ty + th > ROWS then menu.ty = math.max(0, ROWS - th) end
    return menu
  end

  -- Pushed rather than opened by the row itself, because Menu pops itself
  -- around onSelect (the row is not keepOpen): the box comes down, the
  -- sentence goes up, and A on it lands back in the bag.  Which is the
  -- reading order -- an options box left standing over its own answer is a
  -- box in the way.
  local function show(game, text)
    game.stack:push(TextBox.new(game, text))
  end

  function M.install()
    if type(Menu) ~= "table" or type(Menu.new) ~= "function" then
      mod.log:warn("src.ui.Menu is not what this build expects; the bag "
        .. "keeps USE and TOSS alone")
      return false
    end
    if rawget(Menu, PATCH) then return true end

    local baseNew = Menu.new
    Menu.new = function(game, items, opts)
      local added = false
      if wants("about") and not nested and type(items) == "table"
          and #items > 0 and not alreadyThere(items) then
        local id = bagItem(game)
        local text = id and describe(game, id)
        if text then
          table.insert(items, insertAt(items), {
            label = LABEL,
            onSelect = function() show(game, text) end,
          })
          added = true
          -- every row that was already here, so whatever one of them opens
          -- is not offered ABOUT a second time
          for _, row in ipairs(items) do
            if row.label ~= LABEL then guard(row) end
          end
          -- only a box that named its own height needs correcting; one that
          -- let Menu.new measure it is measured again with the new row in it
          if type(opts) == "table" and type(opts.th) == "number" then
            opts.th = opts.th + (opts.rowStep or ROW_STEP)
          end
        end
      end
      local menu = baseNew(game, items, opts)
      if added then return keepOnScreen(menu) end
      return menu
    end
    Menu[PATCH] = true
    return true
  end

  -- exported for the tests
  M.bagItem = bagItem
  M.insertAt = insertAt
  M.keepOnScreen = keepOnScreen
  M.nested = function() return nested end
  M.LABEL = LABEL

  return M
end
