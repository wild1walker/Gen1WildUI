-- The one edit outside the mod manager itself: the CANCEL line on the game's
-- own OPTION screen.
--
-- It is gated on STYLE, so putting that row back on VANILLA puts the whole
-- mod back -- this included -- rather than only its drawing.
--
-- The START menu's row is not touched.  src/ui/StartMenu.lua already puts
-- one there, labelled MODS and wired to the manager, and 0.2.0 through 0.7.2
-- renamed it to MOD MENU.  MODS is what the rest of the game calls them and
-- what the header of the screen it opens says, so the rename was a second
-- name for one thing.  The engine's row stands as the engine wrote it, and
-- a translation of MODS now reaches the START menu the way it always could.

local Menus = {}

local function active(opt, key)
  return opt("presentation") == "modern" and opt(key)
end

-- ------- the game's OPTION screen
--
-- CANCEL is not one of the rows: src/ui/OptionsMenu.lua appends it after the
-- ui.options.rows hook and draws it as OptionRows' fixed bottom line, which
-- is what stops a mod from orphaning the exit.  It is also not the only exit
-- -- B and START both leave, with the same sound and the same pop -- so what
-- it costs is a line of the screen for a second way out of a menu every
-- other menu in the game leaves with B.
--
-- Removing it means owning this screen's drawing, which is why the update
-- wrapper below never touches input.  The engine's own update runs first and
-- in full, every time; all that happens afterwards is that a cursor parked
-- on the row that is no longer drawn gets moved onto one that is.  A bug in
-- here can misplace the cursor.  It cannot take away the way out.
function Menus.installOptionsScreen(mod, Skin, opt)
  local ok, err = pcall(function()
    mod.content.screens:register("OptionsMenu", {
      new = function(game, ...)
        local got, Builtin = pcall(require, "src.ui.OptionsMenu")
        if not got or type(Builtin) ~= "table"
            or type(Builtin.new) ~= "function" then
          mod.log:error("the engine's OPTION screen could not be loaded (%s) "
            .. "-- leaving it alone", tostring(Builtin))
          error("gen1_mod_menu: no builtin options menu to decorate", 0)
        end
        local state = Builtin.new(game, ...)
        local broken = false

        -- ------- rows that asked for the top
        --
        -- Since the engine grouped this screen it lays out the rows its own
        -- ORDER names first -- the group openers, then MODS -- and appends
        -- everything it does not name after them.  A row added through the
        -- ui.options.rows hook is never named there, so no mod can reach the
        -- top of the list on its own however it anchors itself.
        --
        -- A row may now ask, by carrying `top = true`.  Those are lifted to
        -- the front of the view in the order they were already in, and
        -- everything else keeps its own order behind them.  This runs whatever
        -- STYLE and HIDE CANCEL are set to: it is the list's order, not its
        -- drawing, and a row that asked for the top should not move because a
        -- different row stopped being hidden.
        --
        -- `view` is what the screen shows and what the cursor counts; `rows`
        -- is the flat list the hook built and is left exactly as it was, so a
        -- mod reading it still sees what it handed over.
        local view = state.view
        if type(view) == "table" then
          local first, rest = {}, {}
          for _, row in ipairs(view) do
            local bucket = (type(row) == "table" and row.top) and first or rest
            bucket[#bucket + 1] = row
          end
          if #first > 0 then
            local reordered = {}
            for _, row in ipairs(first) do reordered[#reordered + 1] = row end
            for _, row in ipairs(rest) do reordered[#reordered + 1] = row end
            state.view = reordered
          end
        end

        local function on()
          return not broken and active(opt, "hide_cancel")
        end

        state.update = function(self, dt)
          local before = self.index
          local result = Builtin.update(self, dt)
          if not on() then return result end
          -- `view`, not `rows`.  Since the engine grouped this screen, `rows`
          -- is the flat list the ui.options.rows hook built and `view` is what
          -- is actually on screen -- group openers standing in for their
          -- members -- and the cursor indexes `view`.  Measuring the flat list
          -- here made `n` the wrong number: the clamp below never fired,
          -- because an index into a 17-row view is never past a 34-row list.
          local rows = self.view or self.rows or {}
          local n = #rows
          -- CANCEL is index n+1 and is no longer drawn, so the cursor is put
          -- back on a row that is: wrapping to the top if it arrived going
          -- down, and to the last row if it arrived going up, which is what
          -- the visible rows do between themselves.
          if n > 0 and (self.index or 1) > n then
            self.index = (before == n) and 1 or n
            self.scroll = Skin.clampPlainScroll(self.index, self.scroll, n)
          end
          return result
        end

        state.draw = function(self)
          if not on() then return Builtin.draw(self) end
          -- `view` again, and for the visible half of the same reason: the
          -- engine draws `self.view or self.rows`, so drawing `rows` here put
          -- the flat list under a cursor counting the grouped one.  Every row
          -- on screen was then somebody else's -- the arrow on RULESET while
          -- the press edited whatever view[9] happened to be -- and MODS,
          -- ninth in the view, sat thirtieth in the list nobody could reach.
          local drew, drawErr = pcall(Skin.drawPlainRows, mod.ui, self.game,
            self.view or self.rows or {}, self.index, self.scroll or 0)
          if drew then return end
          broken = true
          mod.log:error("the OPTION screen failed to draw (%s) -- the "
            .. "engine's own takes it back, CANCEL and all", tostring(drawErr))
          return Builtin.draw(self)
        end

        return state
      end,
    })
  end)
  if not ok then
    mod.log:error("the OPTION screen was left alone (%s)", tostring(err))
    return false
  end
  return true
end

function Menus.install(mod, Skin, opt)
  return Menus.installOptionsScreen(mod, Skin, opt)
end

return Menus
