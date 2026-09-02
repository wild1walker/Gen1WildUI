-- Gen1ItemInfo: the mart and the item PC, redrawn.
--
-- Returns a factory: factory(mod, C, describe, wants, icons) -> { install = fn }.
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
-- By `kind` where there is one: PlayerPC passes "pc_item_withdraw" /
-- "pc_item_deposit" / "pc_item_toss" and those three are named outright.
--
-- ShopMenu names neither of its two.  This file used to say that ListMenu
-- "falls back to the title and the mart lists arrive as BUY and SELL", and it
-- does fall back to the title -- but ShopMenu passes nil for that as well
-- (`ListMenu.new(game, nil, items, {...})`), so both lists arrive with no
-- kind at all and went undecorated for as long as that sentence stood.  They
-- are recognised by their `money` callback instead; see MART below.
--
-- Anything else falls straight through untouched, which is most lists in the
-- game -- the bag, the box, the dex, the move learner.
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

return function(mod, C, describe, wants, icons)
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
  --
  -- ------- and `title`, because the engine passes none
  --
  -- `C.header` was written to print `list.title`, and every screen in this set
  -- arrives with that nil: `PlayerPC` opens all three of its lists with
  -- `ListMenu.new(game, nil, ...)` (PlayerPC.lua:98/144/176) and `ShopMenu`
  -- does the same for BUY and SELL.  Nobody noticed at a mart, where the
  -- header still carries the money on the right; at a PC the box came up with
  -- a border and nothing in it.
  --
  -- So the name lives with the kind.  These are the PlayerPC MENU's own row
  -- labels, word for word (PlayerPC.lua:224-226), because the header's job is
  -- to say which of those four rows you are standing in -- and the menu itself
  -- is still on the stack underneath, just not drawn.
  --
  -- ------- and `noCancel`
  --
  -- The `CANCEL` row is the $ff terminator, and it is on the cartridge for a
  -- reason that has not applied since: `home/list_menu.asm` watches PAD_A and
  -- PAD_B alike, so B has ALWAYS left one of these lists.  The row is a second
  -- way to do what B does, and on a screen with three items it is a quarter of
  -- the list.
  --
  -- Dropped rather than hidden: the engine's `leftOnCancel` only ever calls
  -- `list:close()`, which is what B does a line later in `ListMenu:update`, so
  -- there is no behaviour to keep -- and a row drawn but not selectable would
  -- be worse than either.
  --
  -- ------- and why the mart has two entries where it used to have one
  --
  -- One `MART` table was right for as long as neither list said anything a
  -- header could print.  Now that the header carries a name, they need telling
  -- apart -- and the engine names neither, so it comes off what they DO.
  --
  -- `onSelectKey` is the sell list's and only the sell list's: SELECT picks a
  -- row up and a second SELECT swaps the two, which is `swap_items.asm`
  -- reordering the bag (ShopMenu.lua:157-169).  There is nothing to reorder in
  -- a shop's stock, so BUY passes none.  Behaviour rather than content --
  -- a row's `price` would have said the same thing until an empty sell list
  -- came up with only its CANCEL row on it.
  local MART = { feature = "mart", money = true, title = "BUY" }
  local MART_SELL = { feature = "mart", money = true, title = "SELL" }
  local KINDS = {
    ["BUY"]              = MART,
    ["SELL"]             = MART_SELL,
    ["pc_item_withdraw"] = { feature = "pc", title = "WITHDRAW ITEM",
                             noCancel = true },
    ["pc_item_deposit"]  = { feature = "pc", title = "DEPOSIT ITEM",
                             noCancel = true },
    ["pc_item_toss"]     = { feature = "pc", title = "TOSS ITEM",
                             noCancel = true },
  }

  -- ------- and the two the engine does not name
  --
  -- `ListMenu.new(game, title, items, opts)` stamps `kind = opts.kind or
  -- title`, and `ShopMenu` passes NEITHER: `ListMenu.new(game, nil, items,
  -- {...})`, twice, with no `kind` in its opts.  Both mart lists therefore
  -- arrive with `kind = nil`, `KINDS[nil]` misses, and BUY and SELL fall
  -- through undecorated -- no icons, no header, and no description in the
  -- clerk's box, which is what a player reported.  The item PC names its
  -- three, which is exactly why only the mart went quiet.
  --
  -- The paragraph at the top of this file says the mart lists "arrive as BUY
  -- and SELL".  That is what a title fallback would give; it is not what this
  -- engine passes, and the two named keys above have been dead letters.  They
  -- stay, because a build that DOES name them is still right.
  --
  -- What a mart list is, rather than what it is called: `opts.money` is a
  -- function.  `ShopMenu` is the only caller of `ListMenu.new` in the engine
  -- that passes one -- BoxMenu, BagMenu and the battle's item list all pass
  -- `itemBox` without it -- so the signature is exact, and unlike a title it
  -- survives translation. BUY and SELL take the same entry, so nothing here
  -- needs to tell them apart.
  --
  -- Recorded under this mod's own key rather than by writing `list.kind`:
  -- that field is the engine's, and a mod that renames somebody else's screen
  -- to be recognised by its own code has made the next reader's job harder.
  local OWN_KIND = "__gen1ItemInfoKind"

  local function kindOf(list)
    if type(list) ~= "table" then return nil end
    return KINDS[list.kind] or rawget(list, OWN_KIND)
  end

  local function markMart(list, opts)
    if type(list) ~= "table" or KINDS[list.kind] then return end
    if type(opts) ~= "table" or type(opts.money) ~= "function" then return end
    list[OWN_KIND] = type(opts.onSelectKey) == "function" and MART_SELL or MART
  end

  -- One marker per patched module, so a second install (a dev hot reload, or
  -- both bundles somehow getting this far) wraps nothing twice.
  local LIST_PATCH = "__gen1ItemInfoListMenu"
  local SHOP_PATCH = "__gen1ItemInfoShopMenu"
  local PC_PATCH = "__gen1ItemInfoPlayerPC"

  -- Stamped on the item PC's own menu, so the hook below can tell which
  -- state on the stack is the one doing the covering.
  local PC_MENU = "__gen1ItemInfoPlayerPCMenu"

  -- ------- the header's number

  local function money(game)
    return ("¥%d"):format((game.save and game.save.money) or 0)
  end

  -- What the header says.  The list's own title where a build gives it one --
  -- so an engine that starts naming these is taken at its word -- and the
  -- kind's otherwise.
  local function headerTitle(list)
    local own = list and list.title
    if type(own) == "string" and own ~= "" then return Strings(own) end
    local kind = kindOf(list)
    local named = kind and kind.title
    if type(named) == "string" and named ~= "" then return Strings(named) end
    return ""
  end

  local function headerRight(list)
    local kind = kindOf(list)
    if kind and kind.money then return money(list.game) end
    return nil
  end

  local function switchedOn(list)
    local kind = kindOf(list)
    if not kind then return false end
    return wants(kind.feature)
  end

  -- ------- the draw

  -- Icons are a row of their own in the menu, so a player who wants the
  -- screens and not the pictures can have that -- and a build with no icons
  -- to load (a partial install, a stripped package) draws the rows it always
  -- drew rather than a column of gaps.
  local function withIcons()
    return icons ~= nil and wants("icons")
  end

  local function draw(self)
    C.clear()
    C.header(headerTitle(self), headerRight(self))

    local pictures = withIcons()
    local labelX = pictures and C.ICON_LABEL_X or C.LABEL_X

    local rows = self.rows or C.ROWS
    if #self.items == 0 then
      Font.draw(Strings("Nothing here."), labelX, C.rowY(1))
    end

    for row = 1, rows do
      local i = self.scroll + row
      local item = self.items[i]
      if not item then break end
      local y = C.rowY(row)
      local right = item.right
      -- The label's budget is what is left after the price or the count,
      -- plus a tile of clearance so the two can never touch.  ListMenu's own
      -- full-screen branch keeps the same gap.  With an icon the number is on
      -- the line below and takes nothing from the name (see chrome.lua).
      local budget = C.RIGHT - labelX
      local rightY = y
      if right then
        if pictures then
          rightY = y + C.RIGHT_SUB_Y
        else
          budget = budget - Font.width(right) - 8
        end
      end
      if pictures then
        -- Drawn before the label, not after: an icon is opaque where it is
        -- inked and the label is a tile clear of it either way, but a row
        -- whose art arrives late would flicker over its own name on the
        -- frame a pocket changes under it.
        --
        -- ICON_DY is what lines the picture up with the word beside it; see
        -- chrome.lua.
        icons.drawFor(self.game, item.value, C.ICON_X, y + C.ICON_DY)
        C.iconRule(y)
      end
      Font.draw(C.fit(item.label, budget), labelX, y)
      if right then
        Font.draw(right, C.rightAlign(right, C.RIGHT), rightY)
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

  -- ------- the row that says what B says
  --
  -- Taken out once, at construction.  `PlayerPC:refreshRow` only ever removes
  -- rows and re-clamps the cursor, and the list is rebuilt every time the
  -- screen opens, so there is nothing to keep taking it out of.
  local function dropCancel(list)
    local items = list.items
    if type(items) ~= "table" then return end
    for i = #items, 1, -1 do
      if type(items[i]) == "table" and items[i].cancel then
        table.remove(items, i)
      end
    end
    list.index = math.max(1, math.min(list.index or 1, #items))
    if type(list.clampScroll) == "function" then pcall(list.clampScroll, list) end
  end

  -- ------- and telling the theme what this screen is
  --
  -- These lists are opened with `messageBox = true`, and `ListMenu.new` reads
  -- that as `itemBox` -- which sets `isOpaque = false` and `sgbPalettes =
  -- false` (ListMenu.lua:132-137).  Both are true of the box the ENGINE draws:
  -- a partial window with the map showing round it, keeping whatever palette
  -- was already up.
  --
  -- Neither is true of this one.  `draw` opens with `C.clear()`, a fill of the
  -- whole 160x144, and the screen is a page from that point on.  Leaving the
  -- engine's two flags in place said the opposite to everything that reads
  -- them: the stack went on drawing the map underneath a screen that covers
  -- it, and Gen1WildUI's DARK -- which stopped counting an item box as a page
  -- in 1.26.2, correctly, because the bag's really is a box on somebody else's
  -- screen -- themed the boxes here and left the cleared page between them
  -- white.  A white plate behind the count and a white band under the list, on
  -- a black screen.
  --
  -- Said once per frame from `update`, and again here so the first frame after
  -- the push is already right.  `gen1wildTheme` is nil rather than false when
  -- the feature is off: the theme's test is `~= nil`, so false would still
  -- claim the frame.
  local function ownsTheFrame(list, own)
    list.gen1wildTheme = own or nil
    list.isOpaque = own or false
  end

  local function decorate(list)
    local baseUpdate, baseDraw = list.update, list.draw
    if type(baseUpdate) ~= "function" or type(baseDraw) ~= "function" then
      return list
    end

    local kind = kindOf(list)
    if kind and kind.noCancel then dropCancel(list) end
    ownsTheFrame(list, switchedOn(list))

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
      -- ITEM PC SCREENS is a live option, so what this screen IS follows it
      -- rather than being decided when the list was built.
      local own = switchedOn(self)
      ownsTheFrame(self, own)
      if not own then return end
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

  -- ------- the PC menu underneath the item PC
  --
  -- WITHDRAW / DEPOSIT / TOSS / LOG OFF is pushed OVER the Pokemon Center's
  -- own PC menu, which stays on the stack with keepOpen rows so B comes back
  -- to it -- and, being a menu rather than a screen, keeps drawing.  Both
  -- boxes start at the top left corner and both are sixteen tiles wide, so
  -- for as long as they were the same height nobody saw it.
  --
  -- They are not the same height.  The PC menu sizes itself to its rows
  -- (`th = #items * 2 + 2`) and it grows one for PROF.OAK's PC, another for
  -- <PK><MN>LEAGUE once there is a HALL OF FAME to read, and another for
  -- anything MENU LAYOUT pins there -- while the item PC's box is a fixed
  -- ten tiles.  Past four rows the menu underneath is taller than the box on
  -- top of it and its last rows print out from under the bottom border,
  -- along with a second bottom border under those.  A LOG OFF row below a
  -- LOG OFF row.
  --
  -- The fix is to stop drawing it, not to draw over it.  Painting a white
  -- rectangle where it used to be would leave a white patch across the
  -- overworld -- and the overworld showing around the box is the point of a
  -- menu that is not opaque.  `screen.render_visible` is the engine's own
  -- answer: the state stays on the stack, keeps its place in the B-chain and
  -- comes back the moment the item PC pops, and only its render is skipped.
  --
  -- Anything non-opaque below the item PC's menu is hidden, not just a menu,
  -- because anything else down there is in exactly the same position.  The
  -- overworld is opaque, so it is never the thing that gets hidden -- which
  -- is what keeps the bedroom PC (opts.direct, opened with no PC menu under
  -- it at all) drawing the room behind it.
  local function coveredByPlayerPC(state)
    if type(state) ~= "table" or state.isOpaque then return false end
    if rawget(state, PC_MENU) then return false end
    local game = state.game
    local states = game and game.stack and game.stack.states
    if type(states) ~= "table" then return false end
    local below = false
    for i = 1, #states do
      if states[i] == state then
        below = true
      elseif below and type(states[i]) == "table"
          and rawget(states[i], PC_MENU) then
        return true
      end
    end
    return false
  end

  local function patchPlayerPC()
    local ok, PlayerPC = pcall(require, "src.ui.PlayerPC")
    if not ok or type(PlayerPC) ~= "table"
        or type(PlayerPC.new) ~= "function" then
      mod.log:warn("src.ui.PlayerPC is not what this build expects; its menu "
        .. "keeps whatever is drawing under it")
      return false
    end
    if rawget(PlayerPC, PC_PATCH) then return true end

    -- How many item PC menus are live.  Only an optimisation -- the scan
    -- above is what actually decides -- so a count that drifts costs a few
    -- comparisons a frame and never a wrong answer.  It is here because
    -- registering this hook at all switches the engine off its "nobody is
    -- listening" fast path for every state of every frame, and the game is
    -- not standing at a PC for almost all of them.
    local open = 0

    local baseNew = PlayerPC.new
    PlayerPC.new = function(game, opts)
      local menu = baseNew(game, opts)
      if type(menu) == "table" then
        menu[PC_MENU] = true
        open = open + 1
      end
      return menu
    end
    PlayerPC[PC_PATCH] = true

    mod.events:on("screen.popped", function(payload)
      local state = payload and payload.state
      if type(state) == "table" and rawget(state, PC_MENU) then
        open = math.max(0, open - 1)
      end
    end)

    mod.hooks:wrap("screen.render_visible", function(nextLink, state)
      local visible = nextLink(state)
      if visible == false or open <= 0 or not wants("pc") then
        return visible
      end
      if coveredByPlayerPC(state) then return false end
      return visible
    end)
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
      if type(list) ~= "table" then return list end
      markMart(list, opts)
      if not kindOf(list) then return list end
      local decorated, result = pcall(decorate, list)
      -- A screen that will not decorate is still a screen: hand back the
      -- engine's own rather than nothing at all.
      if not decorated then
        mod.log:warn("%s did not decorate (%s); it keeps its own chrome",
          tostring(list.kind or "mart list"), tostring(result))
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
    local pc = patchPlayerPC()
    return lists and shop and pc
  end

  -- exported for the tests, which drive the draw against a stub game rather
  -- than a booted one
  M.decorate = decorate
  M.headerRight = headerRight
  M.switchedOn = switchedOn
  M.markMart = markMart
  M.kindOf = kindOf
  M.withIcons = withIcons
  M.coveredByPlayerPC = coveredByPlayerPC
  M.headerTitle = headerTitle
  M.dropCancel = dropCancel
  M.ownsTheFrame = ownsTheFrame
  M.PC_MENU = PC_MENU
  M.KINDS = KINDS

  return M
end
