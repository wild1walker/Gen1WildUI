-- Gen1ItemInfo: the mart and the item PC, redrawn.
--
-- Returns a factory: factory(mod, C, describe) -> { install = fn }.
--
-- ------- decorated, not replaced
--
-- Four of the five screens here are `ListMenu` instances the engine builds
-- and hands to nobody: ShopMenu makes the BUY and SELL lists inside local
-- functions, and PlayerPC makes WITHDRAW / DEPOSIT / TOSS inside its own.
-- There is no screen id on any of them and no hook that reaches them, so the
-- only way in is `ListMenu.new` itself.
--
-- Which is fine, because taking that door does NOT mean rewriting the
-- screens.  Every instance is built exactly as the engine builds it and then
-- has two of its methods swapped: `draw`, for the chrome, and `update`, for
-- the footer.  Everything else -- the input, the scrolling, the quantity
-- selector, the yes/no confirm, what a purchase costs, what a toss refuses,
-- the `Withdrew POTION.` line -- is the engine's own code, untouched, and
-- stays that way when it changes.
--
-- The alternative was `screens:override("ShopMenu")` plus a copy of
-- ShopMenu.lua and PlayerPC.lua carried here, which is four hundred lines of
-- transaction logic re-derived so that a header box could move.  Gen1BillsBox
-- overrides its screen because it genuinely replaces the box with a different
-- thing; this replaces no behaviour at all.
--
-- ------- how a list is recognised
--
-- By `kind`, which the engine already stamps for exactly this reason:
-- PlayerPC passes "pc_item_withdraw" / "pc_item_deposit" / "pc_item_toss",
-- and ShopMenu passes none, so ListMenu falls back to the title and the mart
-- lists arrive as "BUY" and "SELL".  Anything else falls straight through
-- untouched, which is most lists in the game -- the bag, the box, the dex,
-- the move learner.
--
-- ------- and the footer
--
-- The bottom box is the clerk's, and it stays the clerk's.  What this takes
-- is the IDLE line: `Take your time.` at a mart and nothing at all in a PC,
-- neither of which was ever telling anybody anything.  A description goes
-- there instead, and it changes as the cursor moves.
--
-- The rule for when to write is two-part and both halves are needed:
--
--   * the cursor moved -- the description always follows the cursor, even
--     over a message, because a player who has just moved is asking about
--     the row they moved to;
--   * or the footer is back to the line it idles on -- which is how the
--     description returns after `Here you are! Thank you!` clears, without
--     stepping on it while it is still up.
--
-- The idle line is captured from the list's own opts at construction rather
-- than named here, so a localized `_PokemartBuyingGreetingText` is still
-- recognised as the idle line and still replaced.

return function(mod, C, describe, wants)
  local Font = mod.ui.Font
  local Menu = mod.ui.Menu
  local Theme = mod.ui.Theme
  local Strings = require("src.core.Strings")

  local M = {}

  -- The five lists this mod draws, and which option row switches each one.
  -- A kind that is not in here is a list this mod has no opinion about and
  -- never touches.
  --
  -- `money` is the only header number, and only at a mart.  A PC header could
  -- have carried the stacks it is holding out of the fifty it takes -- which
  -- is a number the cartridge never showed and the screen has room for -- but
  -- not next to WITHDRAW ITEM: thirteen glyphs from the left margin end
  -- exactly where a right-aligned "12/50" begins, and a mod that retunes
  -- pcItemCap into three digits overlaps it outright.  Three sibling screens
  -- where the number appears on two of them reads as a bug, so it appears on
  -- none.  BUY and SELL are four glyphs and have the room to spare.
  local KINDS = {
    ["BUY"]              = { feature = "mart", money = true },
    ["SELL"]             = { feature = "mart", money = true },
    ["pc_item_withdraw"] = { feature = "pc" },
    ["pc_item_deposit"]  = { feature = "pc" },
    ["pc_item_toss"]     = { feature = "pc" },
  }

  -- One marker per patched module, so a second install (a dev hot reload, or
  -- both bundles somehow getting this far) wraps nothing twice.
  local LIST_PATCH = "__gen1ItemInfoListMenu"
  local SHOP_PATCH = "__gen1ItemInfoShopMenu"

  -- ------- the header's number

  local function money(game)
    return ("¥%d"):format((game.save and game.save.money) or 0)
  end

  local function headerRight(list)
    local kind = KINDS[list.kind]
    if kind and kind.money then return money(list.game) end
    return nil
  end

  local function switchedOn(list)
    local kind = KINDS[list.kind]
    if not kind then return false end
    return wants(kind.feature)
  end

  -- ------- the draw

  local function draw(self)
    C.clear()
    C.header(Strings(self.title or ""), headerRight(self))

    local rows = self.rows or C.ROWS
    if #self.items == 0 then
      Font.draw(Strings("Nothing here."), C.LABEL_X, C.rowY(1))
    end

    for row = 1, rows do
      local i = self.scroll + row
      local item = self.items[i]
      if not item then break end
      local y = C.rowY(row)
      local right = item.right
      -- The label's budget is what is left after the price or the count,
      -- plus a tile of clearance so the two can never touch.  ListMenu's own
      -- full-screen branch keeps the same gap.
      local budget = C.RIGHT - C.LABEL_X
      if right then budget = budget - Font.width(right) - 8 end
      Font.draw(C.fit(item.label, budget), C.LABEL_X, y)
      if right then
        Font.draw(right, C.rightAlign(right, C.RIGHT), y)
      end
      if i == self.index then
        C.cursor(y)
      elseif self.swapIndex == i then
        -- ▷ marks the row a SELECT swap picked up (the sell list reorders
        -- the bag the same way the bag itself does)
        Font.drawCode(Theme.cursorHollow, C.CURSOR_X, y)
      end
    end

    C.black()
    if self.scroll > 0 then C.mark(C.MARK_X, C.MARK_UP_Y, true) end
    if self.scroll + rows < #self.items then
      C.mark(C.MARK_X, C.MARK_DOWN_Y)
    end

    C.textBox(self.footer)
    C.white()
  end

  -- ------- the footer

  local function decorate(list)
    local baseUpdate, baseDraw = list.update, list.draw
    if type(baseUpdate) ~= "function" or type(baseDraw) ~= "function" then
      return list
    end

    -- The line the screen sits at when nothing is happening: the mart's
    -- greeting, or nothing at all in a PC.  Captured, not named, so a
    -- localized greeting is still the one recognised.
    local idle = list.footer
    local mine, lastIndex = nil, nil

    list.rows = C.ROWS
    list.draw = function(self)
      if not switchedOn(self) then return baseDraw(self) end
      return draw(self)
    end
    list.update = function(self, dt)
      baseUpdate(self, dt)
      if not switchedOn(self) then return end
      local item = self.items and self.items[self.index]
      local text = item and describe(self.game, item.value)
      if text and (self.index ~= lastIndex or self.footer == idle
                   or self.footer == mine) then
        self.footer, mine = text, text
      end
      lastIndex = self.index
    end
    return list
  end

  -- ------- the mart's own first screen
  --
  -- BUY / SELL / QUIT, which is a Menu rather than a list and needs a
  -- different treatment for a reason worth stating: it is the only screen in
  -- this set that is NOT opaque.  Vanilla floats two boxes over the shop
  -- interior and lets the map show around them, and that is the best thing
  -- about the screen -- you are standing at a counter and you can see it.
  --
  -- So nothing is cleared here.  The header box replaces the floating money
  -- box, the menu drops three rows to sit under it, and the shop still shows
  -- through beside them.
  local function patchShop()
    local ok, ShopMenu = pcall(require, "src.ui.ShopMenu")
    if not ok or type(ShopMenu) ~= "table"
        or type(ShopMenu.new) ~= "function" then
      mod.log:warn("src.ui.ShopMenu is not what this build expects; the "
        .. "mart's first screen keeps its own chrome")
      return false
    end
    if rawget(ShopMenu, SHOP_PATCH) then return true end

    local baseNew = ShopMenu.new
    ShopMenu.new = function(game, stock, onQuit)
      local menu = baseNew(game, stock, onQuit)
      if type(menu) ~= "table" then return menu end
      local baseTy, baseDraw = menu.ty, menu.draw
      menu.draw = function(self)
        if not wants("mart") then
          self.ty = baseTy
          return baseDraw(self)
        end
        -- under the header band; Menu works its rows out from ty and th, so
        -- moving the box moves the choices with it
        self.ty = C.HEADER_TH
        C.header(Strings("MART"), money(self.game))
        C.textBox(self.footer)
        Menu.draw(self)
        C.white()
      end
      return menu
    end
    ShopMenu[SHOP_PATCH] = true
    return true
  end

  -- ------- the four lists

  local function patchLists()
    local ListMenu = mod.ui.ListMenu
    if type(ListMenu) ~= "table" or type(ListMenu.new) ~= "function" then
      mod.log:warn("src.ui.ListMenu is not what this build expects; the mart "
        .. "and PC lists keep their own chrome")
      return false
    end
    if rawget(ListMenu, LIST_PATCH) then return true end

    local baseNew = ListMenu.new
    ListMenu.new = function(game, title, items, opts)
      local list = baseNew(game, title, items, opts)
      if type(list) ~= "table" or not KINDS[list.kind] then return list end
      local decorated, result = pcall(decorate, list)
      -- A screen that will not decorate is still a screen: hand back the
      -- engine's own rather than nothing at all.
      if not decorated then
        mod.log:warn("%s did not decorate (%s); it keeps its own chrome",
          tostring(list.kind), tostring(result))
        return list
      end
      return result
    end
    ListMenu[LIST_PATCH] = true
    return true
  end

  function M.install()
    local lists = patchLists()
    local shop = patchShop()
    return lists and shop
  end

  -- exported for the tests, which drive the draw against a stub game rather
  -- than a booted one
  M.decorate = decorate
  M.headerRight = headerRight
  M.switchedOn = switchedOn
  M.KINDS = KINDS

  return M
end
