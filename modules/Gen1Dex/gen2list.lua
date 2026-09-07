-- Gen1Dex: the POKéDEX LIST on Gold, Silver and Crystal.
--
-- Returns a factory: factory(mod, DexData, C) -> { new = function(game, opts) },
-- which main.lua registers over the cart's own `Gen2PokedexMenu`.
--
-- ------- why this is a screen and not the decorator list.lua is
--
-- On Red the list is a DECORATOR: `List.new` calls `Vanilla.new` and then
-- rewrites `rows`, `items`, `draw` and `onSelectKey` on the object that comes
-- back, because Red's PokedexMenu IS a ListMenu -- a cursor over an `items`
-- array with a `scroll` and a row count.
--
-- Gold's is not.  `src/ui/gen2/PokedexMenu.lua` is one 1500-line screen with a
-- `view` field ("list", "entry", "area", "option", "search", "results",
-- "unown") and its own model for each: no `items`, no `rows`, no
-- `onSelectKey`.  There is nothing there to decorate, so the list is drawn
-- here instead -- to the same design, off the same chrome.lua and the same
-- DexData, so the two games' dex lists are the same screen and not two screens
-- that resemble each other.
--
-- ------- what this does NOT take over
--
-- The cart's screen is kept and used, for everything this one does not draw:
--
--   the ENTRY     A on a POKéMON you have met
--   the AREA map  A on one you have not -- Gold's has blinking nests across
--                 both regions, which is better than the Kanto-only one Red
--                 needed built for it
--   SEARCH, OPTION and UNOWN MODE
--
-- Each is opened by building the cart's own PokedexMenu, pointing it at the
-- species this list is on, and setting the `view` it should open in.  So none
-- of them is re-implemented to stand still, and a save that has never opened
-- this mod's list still finds all of them where Gold put them.
--
-- ------- the shape of the screen
--
--   rows 0-2    the header: which view you are in, and a pip per view
--   rows 3-14   six entries, the icon column ruled off from the names
--   rows 15-17  the footer: SEEN and OWN, for the whole dex
--
-- Identical to Red's, down to the column the ball sits in, because that is the
-- point.  chrome.lua owns the boxes and the geometry; this file owns the rows.
--
-- ------- the icon
--
-- Through `PartyMenu:drawIcon`, the same call the party list makes, so a dex
-- row and a party row show the same art -- including this suite's own follower
-- sheets, which reach it through the `pokemon.icon` hook, and including the
-- colour-icon escape runtime/icons2.lua installs on that method.  A dex row is
-- a record rather than a creature, so it is drawn with the smallest stub the
-- icon path actually reads, exactly as Red's list does.

return function(mod, DexData, C)
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local Theme = require("src.ui.Theme")

  local ROWS = 6
  local ROW_H = 16
  local ROW_TOP = C.BODY_TOP             -- 24
  local CURSOR_X = 0
  local ICON_X = 8
  local ICON = 16
  local RULE_X = 26
  local LABEL_X = 32
  -- The label is one glyph row on a two-tile icon, so it sits on the icon's
  -- middle rather than its top edge -- the same offset Red's row uses.
  local TEXT_DY = 4
  -- Fourteen glyphs is 112 pixels ending at 144, six clear of the ball column.
  local LABEL_GLYPHS = 14
  local BALL_X, BALL_R = 150, 3.5

  local Screen = {}
  Screen.__index = Screen

  -- ------- the cart's screen, for everything this one hands back
  --
  -- Built on demand rather than held: the cart's constructor reads the save,
  -- and one built at open time would show a dex the player has since added to.
  -- The cart's module BY NAME, and deliberately not through `Screens`.
  --
  -- `Screens.build` resolves through the registry first, and this mod has
  -- registered ITSELF over `Gen2PokedexMenu` -- so asking Screens for that id
  -- built another copy of this list rather than the cart's screen.  Every A
  -- press stacked one more, and B peeled one off, which is why the dex could
  -- not be closed: it was never one screen refusing to leave, it was a pile of
  -- them.
  local function cartScreen(game, opts, species, view)
    local ok, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (ok and type(PokedexMenu) == "table"
            and type(PokedexMenu.new) == "function") then
      return nil
    end
    local built, screen = pcall(PokedexMenu.new, game, opts)
    if not (built and type(screen) == "table") then return nil end
    screen.screenId = screen.screenId or "Gen2PokedexMenu"
    if view then screen.view = view end
    if species then
      local order = screen.order and screen:order() or {}
      for i, id in ipairs(order) do
        if id == species then screen.index = i break end
      end
      if screen.ensureVisible then pcall(screen.ensureVisible, screen) end
    end
    return screen
  end

  -- ------- the icon
  --
  -- drawIcon wants a MON and a dex row has a species.  With `isEgg` unset and
  -- no item, the path reads `mon.species` and nothing else.
  local stubs = {}
  local function stubFor(species)
    local hit = stubs[species]
    if not hit then
      hit = { species = species, hp = 1, stats = { hp = 1 }, level = 1 }
      stubs[species] = hit
    end
    return hit
  end

  local function iconMenu(self)
    if self.iconHost then return self.iconHost end
    local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
    if not (ok and type(PartyMenu) == "table"
            and type(PartyMenu.drawIcon) == "function") then
      return nil
    end
    local data = self.game and self.game.data or {}
    -- The fields drawIcon's path actually reads, and no more: the icon
    -- registry, the party-menu palette, its own cache and the clock the two
    -- frames bob on.
    self.iconHost = setmetatable({
      game = self.game,
      icons = data.gen2Icons,
      palettes = data.gen2Palettes,
      iconCache = {},
      clock = 0,
    }, { __index = PartyMenu })
    return self.iconHost
  end

  -- ------- the rows

  function Screen.new(game, opts)
    opts = opts or {}
    local self = setmetatable({}, Screen)
    self.screenId = "Gen2PokedexMenu"
    self.game = game
    self.save = opts.save or (game and game.save)
    self.onClose = opts.onClose
    self.opts = opts
    self.mode = "num"
    self.index = 1
    self.scroll = 0
    self.clock = 0
    self:rebuild()
    self:openOnJohto()
    return self
  end

  -- ------- where the cursor starts
  --
  -- Not on 001.  This is Gold: the dex being filled starts at CHIKORITA, and
  -- the cart's own screen opens on its Johto ordering for exactly that reason
  -- (`wLastDexMode` defaults to NEW).  The numbered view here is national
  -- order, which is the right list to read -- Kanto is still in it, one scroll
  -- up -- but the wrong place to be put down.
  --
  -- Which species that is comes from the cart's own table rather than the
  -- number 152: `newOrder` is the Johto dex in Johto order, so its first entry
  -- IS the first entry of this dex, whatever a dataset has done to the roster.
  -- Falling back to row one, which is where it used to start.
  function Screen:openOnJohto()
    local data = self.game and self.game.data
    local dex = data and data.gen2Pokedex
    local first = dex and dex.newOrder and dex.newOrder[1]
    if type(first) ~= "string" then return end
    for i, item in ipairs(self.items) do
      if item.species == first then
        self.index = i
        self:clampScroll()
        return
      end
    end
  end

  -- Gold keeps the dex under `save.pokedex`, and the two cartridges name the
  -- second half of it DIFFERENTLY.  Red's is `owned`; Gold's is `caught` --
  -- the cart's own screen reads `save.pokedex.caught` (PokedexMenu:rebuild),
  -- and so does its save writer.  `DexData.list` is Red's, so it asks for
  -- `owned`, and handing it Gold's table raw meant `savedOwned` was always
  -- empty: no POKeMON was ever OWNED on Gold.
  --
  -- Three things came off that one nil.  No ball marker beside anything the
  -- player had actually caught; the CAUGHT view always empty; and -- because
  -- `cycleView` refused to step INTO an empty view -- SELECT dead-ended on
  -- POKeDEX A-Z with no way back to POKeDEX except closing the screen.
  -- Reported as "when you use the sorting you can't go back to normal unless
  -- you close it".
  --
  -- Normalised here rather than in DexData.list, so the Gen 1 arm keeps
  -- reading exactly the table it always did.
  function Screen:dexSave()
    local pokedex = self.save and self.save.pokedex
    if type(pokedex) ~= "table" then return nil end
    return {
      seen = pokedex.seen,
      owned = pokedex.caught or pokedex.owned,
    }
  end

  function Screen:rebuild(keepSpecies)
    local build = DexData.list(self.game and self.game.data,
                               self:dexSave(), self.mode)
    self.items = build.items or {}
    self.seen, self.owned = build.seen or 0, build.owned or 0
    self.title = DexData.MODE_LABELS[self.mode]
    if keepSpecies then
      for i, item in ipairs(self.items) do
        if item.species == keepSpecies then self.index = i break end
      end
    end
    if self.index > #self.items then self.index = math.max(1, #self.items) end
    if self.index - self.scroll > ROWS then self.index = self.index end
    self:clampScroll()
  end

  function Screen:clampScroll()
    if self.index - self.scroll > ROWS then
      self.scroll = self.index - ROWS
    elseif self.index <= self.scroll then
      self.scroll = self.index - 1
    end
    if self.scroll < 0 then self.scroll = 0 end
  end

  function Screen:current()
    return self.items[self.index]
  end

  function Screen:close()
    local game = self.game
    if self.onClose then return self.onClose() end
    if game and game.stack and game.stack.pop then game.stack:pop() end
  end

  -- ------- input
  --
  -- The keys Red's list answers, and the two the cart's list answers that this
  -- one hands on: SELECT is the view cycle here (Red's), and START opens the
  -- cart's own SEARCH, which this screen does not replace.

  function Screen:move(delta)
    if #self.items == 0 then return end
    local next_ = self.index + delta
    if next_ < 1 then
      next_ = C.option("wrap", true) and #self.items or 1
    elseif next_ > #self.items then
      next_ = C.option("wrap", true) and 1 or #self.items
    end
    self.index = next_
    self:clampScroll()
  end

  -- SELECT walks the three views.  An empty one is STEPPED OVER rather than
  -- stopped at -- an empty list answers nothing but A and B, so landing in one
  -- would strand the cycle, but refusing to move ALSO stranded it: with
  -- nothing owned, CAUGHT was empty, and A-Z's only exit was into it.  So the
  -- walk carries on round the ring and gives up only if it arrives back where
  -- it started, which is the one case where every other view really is empty.
  function Screen:cycleView()
    if not C.option("view_cycle", true) then return end
    local data, save = self.game and self.game.data, self:dexSave()
    local mode = self.mode
    for _ = 1, #DexData.MODES do
      mode = DexData.NEXT_MODE[mode]
      if type(mode) ~= "string" or mode == self.mode then return end
      local build = DexData.list(data, save, mode)
      if #(build.items or {}) > 0 then
        local keep = self:current() and self:current().species
        self.mode = mode
        self:rebuild(keep)
        return
      end
    end
  end

  function Screen:open(view)
    local item = self:current()
    if not item then return end
    local screen = cartScreen(self.game, self.opts, item.species, view)
    if not screen then return end
    local game = self.game
    if game and game.stack and game.stack.push then
      -- The cart's screen owns its own B: give it one that comes back here
      -- rather than out of the dex entirely.
      screen.onClose = function()
        if game.stack and game.stack.pop then game.stack:pop() end
      end
      game.stack:push(screen)
    end
  end

  function Screen:choose()
    local item = self:current()
    if not item then return end
    -- A on a POKéMON you have never met opens the AREA map rather than
    -- refusing, which is the whole reason Red's list wires one: this is the
    -- screen a player opens to find out where something lives.
    self:open(item.seen and "entry" or "area")
  end

  function Screen:update(dt)
    -- The host's clock is set per ROW at draw time (only the row being read
    -- bobs), so it is deliberately not synced here.
    self.clock = (self.clock or 0) + 1
    local input = self.game and self.game.input
    if not input then return end
    if input:wasPressed("up") then self:move(-1) end
    if input:wasPressed("down") then self:move(1) end
    if input:wasPressed("left") then self:move(-ROWS) end
    if input:wasPressed("right") then self:move(ROWS) end
    if input:wasPressed("select") then self:cycleView() end
    if input:wasPressed("start") then self:open("search") end
    if input:wasPressed("a") then self:choose() end
    if input:wasPressed("b") then self:close() end
  end

  -- ------- drawing

  -- ------- one icon, and the two things Red's row does that Gold's does not
  --
  -- ONLY THE ROW UNDER THE CURSOR MOVES.  `PartyMenu:iconFor` reads the frame
  -- off the menu's own clock -- `floor(clock / ICON_FRAME_STEPS) % 2` -- so a
  -- clock that ticks every frame bobs every icon on the screen at once, which
  -- is six POKeMON walking on the spot in a list nobody asked to animate.  The
  -- clock is therefore set PER ROW: the live one for the row being read, and
  -- zero for the rest, which is frame 0, the standing frame.
  --
  -- AND AN UNDISCOVERED ONE IS BLACK.  Red's row asks `PartyMenu.drawIcon` to
  -- paint in the caller's colour, because Red's "never sets a colour of its
  -- own" (list.lua's note) -- so `setColor(0,0,0,1)` takes every pixel's RGB
  -- to zero, leaves its alpha alone, and a silhouette of the exact shape falls
  -- out for free.
  --
  -- Gold's does set one.  `G.setColor(1, 1, 1, 1)` runs immediately before the
  -- paint (src/ui/gen2/PartyMenu.lua:895), so the tint was wiped on the way in
  -- and every entry came out fully lit whether it had been met or not.  So the
  -- silhouette is drawn here instead, off the same image and the same frame
  -- `drawIcon` would have used, and deliberately WITHOUT the party palette:
  -- the shader is what a black tint would be fighting, and a mask does not
  -- need one.
  function Screen:drawIcon(species, x, y, dim, selected)
    local host = iconMenu(self)
    if not host then return end
    host.clock = selected and self.clock or 0
    local G = love.graphics
    if not dim then
      pcall(host.drawIcon, host, stubFor(species), x, y)
      G.setColor(1, 1, 1, 1)
      return
    end
    local ok, image, frame = pcall(host.iconFor, host, stubFor(species))
    if not (ok and image) then return end
    local iw, ih = image:getDimensions()
    G.setColor(0, 0, 0, 1)
    G.draw(image, G.newQuad(0, (frame or 0) * 16, 16, 16, iw, ih), x, y)
    G.setColor(1, 1, 1, 1)
  end

  -- DexData.list already builds the row: `label` is the number and the name
  -- (or "-----" for one never met), `ball` is set when it is owned, and
  -- `seen` is what decides whether the icon is drawn or silhouetted.
  function Screen:drawRow(item, y, selected)
    self:drawIcon(item.species, ICON_X, y, not item.seen, selected)
    C.black()
    local textY = y + TEXT_DY
    Font.draw(C.truncate(item.label, LABEL_GLYPHS), LABEL_X, textY)
    if item.ball then
      -- The ball in a column of its own: a column answers "what do I still
      -- need" at a glance and a scatter of them does not.
      local by = textY + 3
      love.graphics.circle("fill", BALL_X, by, BALL_R)
      C.white()
      love.graphics.rectangle("fill", BALL_X - BALL_R, by - 0.5, BALL_R * 2, 1)
      C.black()
      love.graphics.circle("fill", BALL_X, by, 1.2)
    end
    if selected then
      C.black()
      Font.drawCode(Theme.cursor, CURSOR_X, textY)
    end
  end

  function Screen:draw()
    C.clear()
    C.headerBox()
    C.black()
    Font.draw(Strings(tostring(self.title or "")), C.LEFT, C.HEADER_TEXT_Y)
    local views = DexData.MODES
    local width = C.pipsWidth(#views)
    local active = 1
    for i, name in ipairs(views) do
      if name == self.mode then active = i end
    end
    C.pips(C.RIGHT - width, C.HEADER_TEXT_Y + 2, #views, active)

    -- the icon column, ruled off from the names
    C.rule(RULE_X, ROW_TOP, 1, ROWS * ROW_H)

    for row = 1, ROWS do
      local item = self.items[self.scroll + row]
      if item then
        self:drawRow(item, ROW_TOP + (row - 1) * ROW_H,
                     self.scroll + row == self.index)
      end
    end

    C.footerBox()
    C.black()
    -- Fixed three-digit fields keep this at 17 glyphs, under the 18-column
    -- wrap a footer goes through.
    Font.draw(Strings("SEEN %3d  OWN %3d", self.seen, self.owned),
              C.LEFT, C.FOOTER_TEXT_Y)
  end

  -- The cart's own screen answers both, and a page that fills the window has
  -- to say so or it is drawn in a centred 4:3 square.
  function Screen:drawsWidescreen() return true end
  function Screen:wantsFillScale() return true end

  return { new = Screen.new }
end
