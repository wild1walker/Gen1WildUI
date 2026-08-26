-- Registering the screen, and decorating the instance the engine builds.
--
-- src/ui/Screens.lua resolves a screen id out of Data.screens before falling
-- back to its builtin table, and it stamps `screenId` on whatever comes
-- back, so the F10 toggle in src/core/Game.lua still recognises the
-- instance.  It also pcalls a mod factory's `new` and degrades to the
-- builtin if it throws -- which is the outermost of this mod's three ways
-- back to the vanilla screen.
--
-- Every substitution below lands on ONE instance, built fresh on each push.
-- Nothing is written back to the engine's module table, so a failure here
-- cannot outlive the screen it happened on.

local Screen = {}

-- Where the cursor was the last time the list was open, for the length of
-- this session.  Not persisted: ManagerState:goBack already restores the
-- cursor within a visit through its own backStack, and what this adds is the
-- next visit.  Deliberately not per-save -- the manager opens from the title
-- screen, before Game:adoptSave has bound a playthrough to write to.
local memory = {}

local function decorate(mod, Rows, Skin, Options, opt, state, Builtin)
  local R = Skin.newRenderer(mod, Rows, opt, Builtin)
  local broken = false
  local warned = {}
  local optionsCache = nil

  -- Read on every call rather than latched at construction, so PRESENTATION
  -- takes effect on the next frame -- the row is on this mod's own options
  -- page, which is drawn by the thing it switches off.
  local function modern()
    return not broken and opt("presentation") == "modern"
  end

  local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    mod.log:warn(fmt, ...)
  end

  -- ------- the mod list: sorting and filtering

  -- Whether each mod has an options page.  schemaFor can COMPILE a schema
  -- file for a mod that shipped one without runtime rows, so this is worth
  -- exactly one pass -- and modRows runs a few times a frame.  Dropped on
  -- refresh, and rebuilt on demand so switching the filter on while the list
  -- is open does not need one.
  local function optionsMap(self)
    if optionsCache then return optionsCache end
    local map = {}
    for _, m in ipairs(self.status and self.status.available or {}) do
      local ok, schema = pcall(self.schemaFor, self, m)
      map[m.id] = (ok and schema ~= nil) or false
    end
    optionsCache = map
    return map
  end

  local function entriesFor(self)
    local wantOptions = opt("only_options")
    local hasOptions = wantOptions and optionsMap(self) or nil
    local entries = {}
    for _, m in ipairs(self.status and self.status.available or {}) do
      entries[#entries + 1] = {
        mod = m,
        id = m.id,
        name = m.name or m.id,
        category = m.category or "OTHER",
        state = R.stateOf(self, m),
        hasOptions = hasOptions and hasOptions[m.id] or false,
      }
    end
    return entries
  end

  state.modRows = function(self)
    if not modern() then return Builtin.modRows(self) end
    local ok, rows = pcall(function()
      return Rows.arrange(entriesFor(self), {
        sort = opt("sort"),
        hide_disabled = opt("hide_disabled"),
        only_options = opt("only_options"),
        -- no heading rows: a card layout has four rows on screen and a
        -- heading would spend one of them, so the category rides on the
        -- card's own second line instead
        flat = true,
      }, mod.id)
    end)
    if ok and type(rows) == "table" and #rows > 0 then return rows end
    warnOnce("modRows", "the mod list could not be arranged (%s) -- "
      .. "keeping the engine's order", tostring(rows))
    return Builtin.modRows(self)
  end

  -- ManagerState:moveCursor clamps the list's scroll to an ELEVEN-row window
  -- (its own LIST_ROWS), which is what the previous layout drew.  The cards
  -- show four, so the list owns its clamp the same way the options page does.
  -- One-based here; the options page counts from zero.
  local function clampListScroll(cursor, scroll, total, visible)
    scroll = math.max(1, scroll or 1)
    if cursor < scroll then return cursor end
    if cursor > scroll + visible - 1 then return cursor - visible + 1 end
    local tail = math.max(1, total - visible + 1)
    if scroll > tail then return tail end
    return scroll
  end

  state.moveCursor = function(self, dir)
    local result = Builtin.moveCursor(self, dir)
    if modern() and self.screen == "list" then
      self.scroll = clampListScroll(self.cursor, self.scroll,
                                    #self:rowsForScreen(), Skin.rowCountFor(self.tab))
    end
    return result
  end

  state.goTo = function(self, screen)
    local result = Builtin.goTo(self, screen)
    if modern() and self.screen == "list" then
      self.scroll = clampListScroll(self.cursor, self.scroll,
                                    #self:rowsForScreen(), Skin.rowCountFor(self.tab))
    end
    return result
  end

  state.refresh = function(self)
    optionsCache = nil
    return Builtin.refresh(self)
  end

  -- ------- the per-mod options page

  local function decorateOptions(self, m, schema, rows)
    local byKey = {}
    for _, row in ipairs(schema) do
      if type(row) == "table" and type(row.key) == "string" then
        byKey[row.key] = row
      end
    end
    for _, row in ipairs(rows) do
      -- The engine appends this one itself, at the end of its own
      -- buildOptionRows -- keyed "__reset" rather than by its label, which
      -- Strings localizes.  It only wants the help line the other rows get.
      if row.id == "__reset" then
        row.help = "PUT BACK THE AUTHOR'S VALUES"
      end
      local source = byKey[row.id]
      if source then
        row.help = Rows.helpFor(source)
        -- optionValue answers the row default when nothing is stored, so
        -- this is "differs from what the author shipped" either way
        row.changed = Rows.changed(self:optionValue(m.id, source),
                                   source.default)
      end
    end

    return rows
  end

  state.buildOptionRows = function(self, m, schema)
    local rows = Builtin.buildOptionRows(self, m, schema)
    if not modern() or type(rows) ~= "table" then return rows end
    local ok, decorated = pcall(decorateOptions, self, m, schema, rows)
    if ok and type(decorated) == "table" then return decorated end
    warnOnce("optionRows", "the options page could not be annotated (%s) -- "
      .. "showing the rows plain", tostring(decorated))
    return rows
  end

  -- The engine clamps this page with OptionRows.clampScroll, which is sized
  -- for the four 20x4 boxes vanilla draws.  This page shows eleven rows, so
  -- it owns its own clamp.  Scroll is 0-based here, the way ManagerState:goTo
  -- and OptionRows.draw both treat it.
  local function clampOptionScroll(cursor, scroll, total, visible)
    scroll = scroll or 0
    if cursor <= scroll then return math.max(0, cursor - 1) end
    if cursor > scroll + visible then return cursor - visible end
    local tail = math.max(0, total - visible)
    if scroll > tail then return tail end
    return scroll
  end

  state.updateOptions = function(self, input)
    local result = Builtin.updateOptions(self, input)
    -- B leaves the page through goBack, which restores the LIST's scroll;
    -- re-clamping it here would corrupt it
    if modern() and self.screen == "options" then
      local rows = self.optionRows or {}
      self.scroll = clampOptionScroll(self.cursor, self.scroll, #rows,
                                      R.optionWindow())
    end
    return result
  end

  -- ------- cursor memory

  state.enter = function(self)
    Builtin.enter(self)
    if not (modern() and opt("cursor_memory") and memory.cursor) then return end
    self.tab = memory.tab or self.tab
    self.cursor = memory.cursor
    self.scroll = memory.scroll or 1
    -- the remembered row may be gone, or may now be a group heading
    self:snapCursor()
    self.scroll = clampListScroll(self.cursor, self.scroll,
                                  #self:rowsForScreen(), Skin.rowCountFor(self.tab))
  end

  state.update = function(self)
    local result = Builtin.update(self)
    if self.screen == "list" then
      memory.tab, memory.cursor, memory.scroll = self.tab, self.cursor, self.scroll
    end
    return result
  end

  -- ------- START and SELECT on the mod list
  --
  -- The manager leaves no key spare -- up and down are the cursor, left and
  -- right the tabs, A opens and B goes back -- so the sorts and filters lived
  -- only on this mod's own options page, three screens away from the list
  -- they arrange.  The two keys with slack in them trade jobs here:
  --
  --   START  opens this menu, instead of going straight to APPLY
  --   SELECT applies, instead of quick-toggling the focused mod
  --
  -- Neither job is lost.  The toggle is the first row of the menu and the
  -- cursor opens on it, so START then A is vanilla's SELECT one keypress
  -- later.  And APPLY & RESTART -- which ManagerState:pressStart is the only
  -- route to -- is now what SELECT does, by calling that same pressStart, so
  -- safe mode and the NO CHANGES notice behave exactly as they always did.
  --
  -- Only the MODS tab.  PROFILES spends both keys itself (START deletes a
  -- profile, SELECT renames one), the ERRORS tab keeps START as a second way
  -- to APPLY, and the detail screen keeps SELECT for toggling the mod it is
  -- showing.
  local function openListMenu(self)
    local Menu = mod.ui.Menu
    local items = {}

    local row = self:focusedRow()
    if row and row.mod then
      items[#items + 1] = {
        label = row.mod.enabled and "DISABLE" or "ENABLE",
        -- the engine's own toggle: it resolves the dependency closure, stages
        -- the change and raises the cascade prompt when one is needed, none
        -- of which is reimplemented here
        onSelect = function() self:beginToggle(row.mod) end,
      }
    end

    local current = opt("sort")
    for _, choice in ipairs(Options.choices("sort") or {}) do
      local label = "BY " .. tostring(choice[1])
      -- the active one is bracketed, the way this mod already marks the
      -- active tab
      items[#items + 1] = {
        label = choice[2] == current and ("[" .. label .. "]") or label,
        onSelect = function()
          self:setOption(mod.id, "sort", choice[2])
          -- the arrangement changed under the cursor, so it goes back to the
          -- top rather than to whichever mod is at its index now
          self.cursor, self.scroll = 1, 1
          self:snapCursor()
        end,
      }
    end

    local function toggle(key, label)
      local on = opt(key)
      items[#items + 1] = {
        label = label .. ": " .. (on and "ON" or "OFF"),
        onSelect = function()
          self:setOption(mod.id, key, not on)
          self.cursor, self.scroll = 1, 1
          self:snapCursor()
        end,
      }
    end
    toggle("hide_disabled", "HIDE OFF")
    toggle("only_options", "W/OPTIONS")

    self.game.stack:push(Menu.new(self.game, items, { maxVisible = 7 }))
  end

  local function onModsTab(self)
    return modern() and self.screen == "list" and self.tab == 1
  end

  state.pressStart = function(self)
    if not onModsTab(self) then return Builtin.pressStart(self) end
    local ok, err = pcall(openListMenu, self)
    if ok then return end
    warnOnce("listMenu", "the list menu could not be opened (%s) -- START "
      .. "does what it always did", tostring(err))
    return Builtin.pressStart(self)
  end

  state.quickToggle = function(self)
    if not onModsTab(self) then return Builtin.quickToggle(self) end
    -- the engine's own START: the APPLY screen when something is staged, the
    -- NO CHANGES notice when nothing is, and safe mode either way
    return Builtin.pressStart(self)
  end

  -- ------- drawing

  state.draw = function(self)
    if not modern() then return Builtin.draw(self) end
    local ok, err = pcall(R.draw, self)
    if ok then return end
    broken = true
    mod.log:error("the mod menu failed to draw (%s) -- the engine's own "
      .. "manager takes over for the rest of this visit", tostring(err))
    return Builtin.draw(self)
  end

  return state
end

Screen.decorate = decorate

function Screen.install(mod, Rows, Skin, Options, opt)
  local ok, err = pcall(function()
    mod.content.screens:register("ManagerState", {
      new = function(game)
        -- Required here rather than at load: this runs only in a real game,
        -- and a failure is caught by Screens.build's own pcall, which then
        -- builds the engine's manager instead.
        local got, Builtin = pcall(require, "src.mods.ManagerState")
        if not got or type(Builtin) ~= "table"
            or type(Builtin.new) ~= "function" then
          mod.log:error("the engine's mod manager could not be loaded (%s) "
            .. "-- leaving the screen alone", tostring(Builtin))
          error("gen1_mod_menu: no builtin manager to decorate", 0)
        end
        return decorate(mod, Rows, Skin, Options, opt, Builtin.new(game),
                        Builtin)
      end,
    })
  end)
  if not ok then
    mod.log:error("the mod menu screen could not be registered (%s) -- the "
      .. "manager stays vanilla", tostring(err))
    return false
  end
  return true
end

return Screen
