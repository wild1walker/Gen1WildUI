-- Menu Manager: arrange the START menu and the Pokémon Center PC menu.
--
-- The shape of this mod is a wrap on ui.start_menu.items (and one on
-- ui.pc.items) that runs OUTERMOST.  Hooks:call walks the chain from index 1
-- and Hooks:wrap sorts it by priority descending (src/mods/Hooks.lua), so a
-- high hook priority puts this link first, its next() returns the list every
-- other mod and the engine already finished building, and only then is that
-- list rearranged.  A mod's appended row becomes arrangeable instead of stuck
-- wherever it landed.
--
-- Which is the opposite of cookbook R31: the recipe for ADDING a row inserts
-- before calling next.  Rearranging one has to act after.  (The shipped
-- example_dexnav uses the after form for the same reason.)

local SCREEN = "Gen1MenuManagerEditor"

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s missing from %s -- reinstall the mod", name, mod.path)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s did not compile: %s", name, tostring(err))
    return nil
  end
  local ok, value = pcall(chunk)
  if not ok then
    mod.log:error("%s failed to run: %s", name, tostring(value))
    return nil
  end
  return value
end

return function(mod)
  local Layout = loadSibling(mod, "layout.lua")
  local Pins = loadSibling(mod, "pins.lua")
  local makeScreen = loadSibling(mod, "screen.lua")
  if not (Layout and Pins and makeScreen) then return end

  mod.options:define({
    -- SELECT while a managed menu is open.  The engine leaves SELECT unbound
    -- there: the START menu's wMenuWatchedKeys mask is PAD_DOWN | PAD_UP |
    -- PAD_START | PAD_B | PAD_A (engine/menus/draw_start_menu.asm) and
    -- src/ui/Menu.lua reads up, down, a, b and start only -- so nothing is
    -- being taken away from the vanilla menu to make room for this.
    { key = "select_shortcut", type = "toggle", label = "SELECT OPENS",
      default = true },
    -- The manager's own row.  It can be hidden like any other, but only
    -- while SELECT OPENS is on: something has to remain that reaches the
    -- editor, and if the shortcut is off, the row is that something.
    { key = "menu_row", type = "toggle", label = "MENU ROW", default = true },
    { key = "pc_row", type = "toggle", label = "PC ROW", default = true },
    -- A pin whose action cannot run right now (BICYCLE indoors, SURF facing
    -- land) is dropped rather than shown and refused, because refusing would
    -- mean inventing a message the ROM does not have.
    { key = "hide_unusable", type = "toggle", label = "HIDE UNUSABLE",
      default = true },
    -- The mod's own shorter name for a pinned row, where it has one -- today
    -- just the town map, whose row opens the map screen rather than handing
    -- you the item and so reads MAP.  Off puts every pin back on the name
    -- the game itself uses, which is what the editor lists either way.
    { key = "short_names", type = "toggle", label = "SHORT NAMES",
      default = true },
  })

  -- ------- persistence
  --
  -- mod.save is the truth and it is per playthrough: Game:adoptSave rebinds
  -- loader.modSave to this save's modData on every NEW GAME and CONTINUE
  -- (src/core/Game.lua:1178), so a layout is read fresh on each menu build
  -- and never cached across a save switch.  mod.cache holds the same layout
  -- as an installation-wide template, and a save with none of its own seeds
  -- from it -- which is what stops a new file from starting over.
  --
  -- The two menus get separate layouts under separate keys.  They share no
  -- rows, and one arrangement should not be disturbed by the other.

  local function makeContext(spec)
    local ctx = {
      title = spec.title, emptyHint = spec.emptyHint, pins = spec.pins,
      snapshot = {}, sourceRows = nil, menu = nil,
    }

    function ctx.load()
      local stored = mod.save:get(spec.saveKey)
      if stored ~= nil then return Layout.normalize(stored) end
      local ok, bytes = pcall(function() return mod.cache:read(spec.cacheFile) end)
      local seeded = ok and bytes and Layout.decode(bytes)
      return seeded or Layout.empty()
    end

    function ctx.save(layout)
      mod.save:set(spec.saveKey, layout)
      -- The template is a convenience; the save already holds the truth, so a
      -- read-only cache directory must not cost the player their arrangement.
      local ok, err = pcall(function()
        return mod.cache:write(spec.cacheFile, Layout.encode(layout))
      end)
      if not ok then
        mod.log:warn("layout template not written: %s", tostring(err))
      end
    end

    -- What may not be hidden right now.  With the SELECT shortcut on, nothing
    -- is: every row is ordinary, the manager row included, because SELECT
    -- still reaches the editor from an otherwise empty menu.  Turn the
    -- shortcut off and the manager row becomes the only route, so it locks.
    function ctx.protected()
      if mod.options:get("select_shortcut") then return {} end
      return { [Layout.MANAGER] = true }
    end

    return ctx
  end

  local contexts = {
    start = makeContext({
      saveKey = "layout", cacheFile = "layout.txt", pins = true,
      title = "START MENU", emptyHint = "OPEN START FIRST",
    }),
    pc = makeContext({
      saveKey = "pc_layout", cacheFile = "pc_layout.txt", pins = false,
      title = "PC MENU", emptyHint = "OPEN A PC FIRST",
    }),
  }

  mod.content.screens:register(SCREEN, {
    new = makeScreen(mod, Layout, Pins, contexts).new,
  })

  -- ------- finding the live menu instance
  --
  -- Both menus are src/ui/Menu.lua instances that keep the row list they were
  -- built from as `self.items`.  That table is the one this mod just
  -- returned, so identity on it names the instance exactly -- no guessing
  -- from push order, which would be wrong for the PC anyway: openPC pushes a
  -- TextBox first and only opens the menu from its onDone.
  --
  -- Two things come out of holding the instance: the screen id to re-open the
  -- START menu with (learned rather than hardcoded, because Gold's is
  -- "Gen2StartMenu" and the Gen 1 literal would resolve to Red's module), and
  -- somewhere to hang the SELECT shortcut.

  local pending = {}
  local startMenuId = nil

  local function openEditor(game, ctx, key, onCancel)
    mod.ui.push(game, SCREEN, { context = key, onCancel = onCancel })
  end

  local function attach(game, state, ctx, key)
    ctx.menu = state
    if key == "start" then
      local id = state.screenId
      if type(id) == "string" and id ~= "" then startMenuId = id end
    end

    local baseUpdate = state.update
    if type(baseUpdate) ~= "function" then return end
    state.update = function(selfState, dt)
      if mod.options:get("select_shortcut")
          and game.input and game.input:wasPressed("select") then
        if key == "start" then
          -- the START menu closes behind its rows (Menu pops itself before
          -- onSelect), so the shortcut does the same and re-opens after
          game.stack:pop()
          openEditor(game, ctx, key, function()
            if startMenuId then mod.ui.push(game, startMenuId) end
          end)
        else
          -- the PC menu stays open under its sub-screens (keepOpen), so the
          -- editor sits on top of it and ctx.refresh rebuilds it on the way
          -- back out
          openEditor(game, ctx, key, nil)
        end
        return
      end
      return baseUpdate(selfState, dt)
    end
  end

  mod.events:on("screen.pushed", function(ev)
    local state = ev and ev.state
    if not state or not state.items then return end
    for key, ctx in pairs(contexts) do
      local want = pending[key]
      if want ~= nil and state.items == want then
        pending[key] = nil
        attach(ctx.game, state, ctx, key)
        return
      end
    end
  end)

  -- ------- rebuilding a live PC menu
  --
  -- Menu sizes its box from the row count at construction (openPC passes
  -- th = #items * 2 + 2), so hiding a row while the menu is on screen has to
  -- resize it too or the border no longer matches its contents.

  function contexts.pc.refresh()
    local ctx = contexts.pc
    local menu, rows = ctx.menu, ctx.sourceRows
    if not (menu and rows) then return end
    local ok, arranged = pcall(function()
      local player = ctx.game and ctx.game.save and ctx.game.save.player
      local list, snapshot = Layout.apply(rows, ctx.load(),
        player and player.name, ctx.protected())
      ctx.snapshot = snapshot
      return list
    end)
    if not ok or type(arranged) ~= "table" then return end
    -- LOG OFF was appended by the engine AFTER the hook, so it is in
    -- menu.items but not in the arranged list; carry it across rather than
    -- dropping the way out of the PC.
    local known = {}
    for _, row in ipairs(rows) do known[row] = true end
    for _, row in ipairs(menu.items) do
      if not known[row] then arranged[#arranged + 1] = row end
    end
    menu.items = arranged
    menu.th = #arranged * (menu.rowStep or 2) + 2
    menu.index = math.min(menu.index or 1, math.max(1, #arranged))
    if menu.clampScroll then menu:clampScroll() end
  end

  -- ------- the hooks

  local function arrange(key, game, built, extraRows)
    local ctx = contexts[key]
    ctx.game = game
    local ok, result = pcall(function()
      local layout = ctx.load()
      local rows = {}
      for _, item in ipairs(built) do rows[#rows + 1] = item end
      for _, item in ipairs(extraRows or {}) do rows[#rows + 1] = item end

      local player = game and game.save and game.save.player
      local arranged, snapshot = Layout.apply(rows, layout,
        player and player.name, ctx.protected())
      ctx.snapshot = snapshot
      ctx.sourceRows = rows
      pending[key] = arranged
      return arranged
    end)
    if not ok then
      mod.log:error("layout not applied to %s: %s -- keeping the built order",
                    key, tostring(result))
      return built
    end
    return result
  end

  local function managerRow(game, key, keepOpen)
    return {
      mmKey = Layout.MANAGER,
      label = "MENU MGR",
      keepOpen = keepOpen or nil,
      onSelect = function()
        openEditor(game, contexts[key], key, key == "start" and function()
          -- vanilla submenus return to the START menu on B
          -- (RedisplayStartMenu); this is StartMenu's own `reopen`
          if startMenuId then mod.ui.push(game, startMenuId) end
        end or nil)
      end,
    }
  end

  -- ------- pinned rows (START menu only: a pin is a field action, and the
  -- overworld is not reachable from inside a PC)

  local function pinRows(game, layout)
    local rows = {}
    for _, entry in ipairs(Pins.catalog) do
      local key = Layout.pinKey(entry.id)
      if layout.pins[key] then
        local ok, owned = pcall(entry.owned, game)
        if ok and owned then
          -- entry.label is the item or move the pin comes from -- the name
          -- the editor lists it under, and the one SHORT NAMES off hands
          -- back.  menuLabel is the mod's own shorter row name (pins.lua).
          local labelFn = entry.label
          if entry.menuLabel and mod.options:get("short_names") then
            labelFn = entry.menuLabel
          end
          local gotLabel, label = pcall(labelFn, mod, game)
          rows[#rows + 1] = {
            -- keysFor honours mmKey, so a pin keeps one identity whatever its
            -- label localizes to and never collides with an engine row
            mmKey = key,
            label = gotLabel and label or entry.id,
            action = entry.action,
            onSelect = function()
              local ran, result, reason = pcall(entry.run, mod, game)
              if not ran then
                mod.log:warn("pin %s failed: %s", entry.id, tostring(result))
              elseif not result and reason then
                mod.log:info("pin %s unavailable: %s", entry.id, tostring(reason))
              end
            end,
          }
        end
      end
    end
    if not mod.options:get("hide_unusable") then return rows end

    -- availableFieldActions is stack-sensitive: it needs the overworld on top,
    -- which holds when START is pressed from the field but NOT when a
    -- submenu's onCancel re-opens the menu (StartMenu's `reopen`).  So an
    -- empty answer means "cannot tell" and every row stays -- never the other
    -- way round, or a pin would blink out of existence on the way back from
    -- the bag.
    local world = mod.world
    if not world then return rows end
    local ok, actions = pcall(world.availableFieldActions, world)
    if not ok or type(actions) ~= "table" or #actions == 0 then return rows end
    local ready = {}
    for _, action in ipairs(actions) do ready[action.id] = true end

    local filtered = {}
    for _, row in ipairs(rows) do
      -- Only pins that ARE field actions can be judged this way; TOWN MAP
      -- pushes a screen and FLY answers through canFly, so both are kept.
      if not row.action or ready[row.action] then
        filtered[#filtered + 1] = row
      end
    end
    return filtered
  end

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local built = next(game, items)
    if type(built) ~= "table" then return built end
    local extra = {}
    if mod.options:get("menu_row") then
      extra[#extra + 1] = managerRow(game, "start", false)
    end
    local ok, layout = pcall(contexts.start.load)
    for _, row in ipairs(ok and pinRows(game, layout) or {}) do
      extra[#extra + 1] = row
    end
    return arrange("start", game, built, extra)
  end, 1000)

  mod.hooks:wrap("ui.pc.items", function(next, game, items)
    local built = next(game, items)
    if type(built) ~= "table" then return built end
    local extra = {}
    if mod.options:get("pc_row") then
      -- keepOpen, like every other PC row: the PC session stays up behind its
      -- sub-screens (src/world/OverworldController.lua openPC), and B in the
      -- editor lands back on the PC rather than logging off.
      extra[#extra + 1] = managerRow(game, "pc", true)
    end
    return arrange("pc", game, built, extra)
  end, 1000)

  -- A third route in, and the one that survives everything: the OPTION menu.
  -- OptionsMenu appends CANCEL after this hook, so the exit stays last.
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local built = next(game, rows)
    if type(built) ~= "table" then return built end
    built[#built + 1] = {
      id = "Gen1MenuManager",
      label = "MENU MANAGER",
      activate = function(g) openEditor(g, contexts.start, "start", nil) end,
    }
    return built
  end)
end
