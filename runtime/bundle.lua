-- Turning a list of features into one loaded mod.
--
-- The order matters and is not obvious, so it is spelled out:
--
--   1. every feature's master switch is registered, before anything is run.
--      The switch has to exist before it can be consulted, and it is
--      consulted to decide whether to run the feature at all.
--   2. features are run, in registry order, each against its own facade.
--      Running a feature is what makes it define its options and install its
--      hooks -- upstream mains do both in one call and cannot be split.
--   3. the merged schema is handed to the engine, once.
--   4. the menu is built from whatever ended up in the schema.
--
-- A feature that fails at any point is logged, marked, and skipped.  Eleven
-- working features and one that says why it is missing beats twelve that do
-- not load.

-- The one thing this file cannot do for itself is load its own siblings: a
-- mod's `require` does not reach into its own folder.  main.lua passes in the
-- function that does.
local loadRuntime = ...

local Bundle = {}

local function detectGen2()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok or type(GameVersion) ~= "table" then return false end
  if type(GameVersion.generation) ~= "function" then return false end
  local okCall, generation = pcall(GameVersion.generation)
  return okCall and generation == 2
end

function Bundle.install(mod, spec, features)
  local Loader = assert(loadRuntime("loader"), "runtime/loader.lua did not load")
  local OptionSet = assert(loadRuntime("optionset"), "runtime/optionset.lua did not load")
  local Facade = assert(loadRuntime("facade"), "runtime/facade.lua did not load")
  local Registry = assert(loadRuntime("registry"), "runtime/registry.lua did not load")
  local Menu = assert(loadRuntime("menu"), "runtime/menu.lua did not load")
  local Claims = assert(loadRuntime("claims"), "runtime/claims.lua did not load")
  -- Optional for the same reason Settings is: a tree built before this file
  -- existed should lose the themes rather than the boot.
  local Theme = loadRuntime("theme")
  local Matte = loadRuntime("matte")
  -- Optional, and deliberately so: a bundle installed outside a sealed cart
  -- needs none of it, and a tree built before this file existed should lose
  -- the remembering rather than the boot.
  local Settings = loadRuntime("settings")
  -- Optional for the same reason, and absent is the ordinary case anyway:
  -- with no voxel mod installed this resolves to nothing and every feature
  -- that asks gets a silent no.
  local VoxelRuntime = loadRuntime("voxel")

  -- Before anything reads an option.  A sealed cart has just replaced every
  -- pinned mod's options with what it pins (Loader:_applyCart), so what the
  -- player chose is put back here -- into the same table the mod manager
  -- reads, so nothing ends up with two answers.  This bundle is first in the
  -- cart's load order, which is what puts it ahead of the mod whose option is
  -- read at load time.
  if type(Settings) == "table" then
    local ok, restored = pcall(Settings.restore, mod)
    if ok and (restored or 0) > 0 then
      mod.log:info("%d remembered setting(s) put back after the cart's seal",
                   restored)
    end
    pcall(Settings.watch, mod)
  end

  local loader = Loader.new(mod)
  local optionset = OptionSet.new()
  -- Optional: absent on a tree built before build.py wrote it, in which case
  -- handles simply carry no version.
  local versions = loader.run("modules/versions.lua")
  local registry = Registry.new(mod, spec, type(versions) == "table" and versions or nil)

  optionset.resolveGame = function()
    return (mod.world and mod.world.game) or mod.game
  end

  local context = {
    mod = mod,
    spec = spec,
    optionset = optionset,
    registry = registry,
    loader = loader,
    isGen2 = detectGen2(),
    shared = {},
    -- Which voxel mod is installed, if any.  Built once for the bundle: the
    -- lookup is memoised in there, so a dozen features asking costs one
    -- `mod.find` sweep rather than a dozen.
    voxel = type(VoxelRuntime) == "table" and VoxelRuntime.new(mod) or nil,
    -- feature id -> function returning rows an adapter wants on that
    -- feature's screen, for settings that do not live in the option schema.
    customRows = {},
  }

  -- ---- 1. master switches first

  local active = {}
  for _, feature in ipairs(features) do
    if feature.gen2_only and not context.isGen2 then
      -- nothing
    elseif feature.gen1_only and context.isGen2 then
      -- nothing
    else
      optionset.master(feature)
      feature.live_toggle = feature.enabledKey ~= nil
      active[#active + 1] = feature
    end
  end

  -- ---- 1b. installation order
  --
  -- Menu order and load order are different questions and are answered
  -- separately.  features.lua is written in the order the menu should read --
  -- related features next to each other, the ones most players touch first at
  -- the top -- while installation follows each mod's own manifest priority,
  -- because that is the order these mods were built and tested against.
  -- Gen1Arena hooks the battle screen at 50 and Gen1Party redraws the party
  -- at 1100; swapping them because one reads better in a list would be a
  -- silent behaviour change.
  --
  -- A stable sort, so features sharing a priority keep a fixed order -- which
  -- is how Gen1Party still finds Gen1Dex and Gen1BillsBox registered ahead of
  -- it.
  --
  -- `install_seq` is what fixes it, and it exists so the two orders can move
  -- independently.  Declaration order was doing both jobs, which meant moving
  -- a row up the menu silently reordered installation among every feature
  -- sharing its priority -- a behaviour change bought by an unrelated edit,
  -- and one nothing would have reported.  A feature that carries the field is
  -- installed at that rank whatever line it is written on; one that does not
  -- falls back to declaration order, so a bundle that has never needed to
  -- reorder its menu is unaffected.

  local loadOrder = {}
  for index, feature in ipairs(active) do
    loadOrder[#loadOrder + 1] = { feature = feature, index = index }
  end
  table.sort(loadOrder, function(a, b)
    local pa = a.feature.priority or 100
    local pb = b.feature.priority or 100
    if pa ~= pb then return pa < pb end
    local sa = a.feature.install_seq or a.index
    local sb = b.feature.install_seq or b.index
    if sa ~= sb then return sa < sb end
    return a.index < b.index
  end)

  -- ---- 1c. features carried by both bundles
  --
  -- Gen1ModMenu and Gen1MenuManager are in both halves, because they are the
  -- furniture the rest is seen through and neither half should lose them.
  -- Exactly one bundle may install one, and neither mod guards against being
  -- installed twice, so the claim is taken here -- before anything runs --
  -- and a bundle that loses it treats the feature as somebody else's.

  local claims = Claims.table()
  local deferred = {}
  for _, feature in ipairs(active) do
    if feature.shared then
      local mine, holder = Claims.take(mod, feature, claims)
      if not mine then
        deferred[feature.id] = holder or "the other bundle"
        feature.deferred_to = deferred[feature.id]
      end
    end
  end

  -- ---- 2. run each feature
  --
  -- A feature whose switch is its own option row is always installed: its own
  -- code reads that row every time it acts, so the switch is live and turning
  -- it off is the untouched game.  A feature without one is gated here
  -- instead, and turning it on takes a relaunch -- which is what the menu's
  -- asterisk is telling the player.

  local installed = {}
  for _, ordered in ipairs(loadOrder) do
    local feature = ordered.feature
    local wanted = true
    if deferred[feature.id] then
      wanted = false
    elseif not feature.live_toggle then
      local key = optionset.groups[feature.id].masterKey
      local stored = optionset.read(mod, key)
      wanted = stored ~= false
    end

    if not wanted then
      if deferred[feature.id] then
        mod.log:info("[%s] installed by %s; not installing it twice",
          feature.label, tostring(deferred[feature.id]))
      else
        mod.log:info("[%s] off; not installed", feature.label)
      end
      installed[feature.id] = false
    else
      local facade = Facade.new(feature, context)
      local entry = "modules/" .. feature.dir .. "/" .. (feature.entry or "main.lua")
      local chunk, reason = loader.chunk(entry)
      local ok = false
      if chunk then
        -- The engine accepts two entry shapes and mods in this bundle use
        -- both, so both are supported here rather than one being quietly
        -- broken:
        --
        --   return function(mod) ... end   -- eleven of the twelve
        --   local mod = ...                -- Gen1Arena, which installs at
        --                                  -- chunk scope and returns a table
        --
        -- Passing the facade as the chunk argument satisfies the second and
        -- is ignored by the first, so the only thing left to decide is
        -- whether the return value is an installer or the mod's exports.
        local ranOk, value = pcall(chunk, facade)
        if not ranOk then
          mod.log:error("[%s] entry chunk failed: %s", feature.label, tostring(value))
        elseif type(value) == "function" then
          local installOk, installError = pcall(value, facade)
          if installOk then
            ok = true
          else
            mod.log:error("[%s] failed to install: %s", feature.label, tostring(installError))
          end
        else
          -- Nothing to call: the chunk installed itself on the way past.
          ok = true
        end
      else
        mod.log:error("[%s] not loaded: %s", feature.label, tostring(reason))
      end

      if ok then
        -- An adapter is this bundle's own code, run after the upstream
        -- feature and against the same facade: it is where a bundle-specific
        -- default is seeded or a screen is rewired, without editing vendored
        -- source.
        if feature.adapter then
          local adapter = loader.run("adapters/" .. feature.adapter .. ".lua")
          if type(adapter) == "table" and type(adapter.install) == "function" then
            local adapterOk, adapterError = pcall(adapter.install, facade, context, feature)
            if not adapterOk then
              mod.log:error("[%s] adapter failed: %s", feature.label, tostring(adapterError))
            end
          end
        end
        registry.register(feature, facade.exports)
      end
      installed[feature.id] = ok
    end
  end

  -- ---- 2b. the UI theme
  --
  -- Before the schema is handed over, because its row goes into that schema,
  -- and after the features have run, because its `render.zones` hook should
  -- sit outside theirs -- a feature that adds zones of its own has added them
  -- by the time the theme swaps their colours.
  local theme
  if type(Theme) == "table" and type(Theme.new) == "function" then
    local ok, built = pcall(Theme.new, context)
    if ok and type(built) == "table" then
      local installed, problem = pcall(built.install)
      if installed then
        theme = built
        context.theme = built
        -- and the one thing a zone cannot reach: the white page inside a
        -- true-colour rectangle, on the screens this suite does not own.
        -- After the theme, because it reads the theme; guarded separately,
        -- because a themed build with no mattes is a build with white boxes
        -- on four screens and a themed build with no theme is a build with
        -- no themes at all.
        if type(Matte) == "table" and type(Matte.new) == "function" then
          local madeOk, mattes = pcall(Matte.new, context)
          if madeOk and type(mattes) == "table" then
            local mattedOk, problem = pcall(mattes.install)
            if not mattedOk then
              mod.log:warn("true-colour mattes not installed: %s",
                           tostring(problem))
            end
            -- and the title screen, whose white page is the same problem
            -- reached from the other side: painted rather than repaired.
            -- Guarded on its own so a screen that will not patch does not
            -- take the other four down with it.
            local groundOk, groundProblem = pcall(mattes.installTitle)
            if not groundOk then
              mod.log:warn("title ground not installed: %s",
                           tostring(groundProblem))
            end
          else
            mod.log:warn("true-colour mattes not built: %s", tostring(mattes))
          end
        end
      else
        mod.log:warn("UI theme not installed: %s", tostring(problem))
      end
    else
      mod.log:warn("UI theme not built: %s", tostring(built))
    end
  end

  -- ---- 3. one schema, once

  optionset.define(mod)

  -- ---- 4. the menu

  local menu = Menu.new({
    mod = mod,
    spec = spec,
    optionset = optionset,
    features = active,
    isGen2 = context.isGen2,
    customRows = context.customRows,
    deferred = deferred,
    theme = theme,
  })
  for _, feature in ipairs(active) do
    menu.noteInstalled(feature, installed[feature.id] == true)
  end
  menu.install()

  -- ---- what the other half of the pair can see

  mod.exports.features = registry.table()
  mod.exports.bundle = spec.id
  mod.exports.installed = installed
  mod.exports.deferred = deferred
  -- What the theme's last frame saw: boxes recorded, panels produced, zones
  -- handed in.  Published for the nightly bench and nothing else -- a build
  -- with no theme answers three zeroes rather than nothing, so a caller never
  -- has to know whether the theme installed.
  mod.exports.themeProbe = function()
    if type(theme) ~= "table" or type(theme.probe) ~= "function" then
      return 0, 0, 0
    end
    local ok, boxes, panels, zones = pcall(theme.probe)
    if not ok then return 0, 0, 0 end
    return boxes or 0, panels or 0, zones or 0
  end

  -- And the one the box-screen ring is being chased with: how many
  -- true-colour rects the last frame that had any carried, and what the theme
  -- called itself while it carried them.
  mod.exports.themeArtProbe = function()
    if type(theme) ~= "table" or type(theme.artProbe) ~= "function" then
      return 0, "-", false
    end
    local ok, count, word, page = pcall(theme.artProbe)
    if not ok then return 0, "-", false end
    return count or 0, word or "-", page and true or false
  end

  -- Which voxel mod this bundle found, and whether that one moves the battle
  -- HUDs onto its world canvas -- the one thing the forks disagree about and
  -- the thing everything drawn beside a HUD turns on.  Published as a
  -- diagnostic rather than for anything here: nothing in the bundle reads it,
  -- and a build standing beside no voxel mod answers nil rather than nothing,
  -- so a caller never has to know whether the resolver is there.
  mod.exports.voxelProbe = function()
    if type(context.voxel) ~= "table" then return nil, false end
    local okId, id = pcall(context.voxel.id)
    local okSnap, snaps = pcall(context.voxel.snapsHuds)
    return okId and id or nil, (okSnap and snaps) == true
  end

  mod.exports.optionValue = function(key) return optionset.read(mod, key) end
  -- The writing half of the pair, so the other bundle's menu can move a switch
  -- that lives over here rather than only reading it.  Both halves render both
  -- halves' features (runtime/menu.lua), and a row that could be read but not
  -- turned would be worse than not showing it at all.
  mod.exports.optionWrite = function(key, value, game)
    return optionset.write(mod, key, value, game)
  end
  -- What this bundle's features are, in the shape the other half's menu draws
  -- them in: label, card, master row, and the id of the settings screen this
  -- bundle registered for each.  Built after noteInstalled, so `installed`
  -- reports what actually happened this boot.
  mod.exports.menu = menu.descriptor()

  local count, handedOver = 0, 0
  for _, ok in pairs(installed) do if ok then count = count + 1 end end
  for _ in pairs(deferred) do handedOver = handedOver + 1 end
  if handedOver > 0 then
    mod.log:info("%s: %d of %d features installed, %d left to the other bundle",
      spec.menu_label, count, #active, handedOver)
  else
    mod.log:info("%s: %d of %d features installed", spec.menu_label, count, #active)
  end

  return { optionset = optionset, registry = registry, menu = menu }
end

return Bundle
