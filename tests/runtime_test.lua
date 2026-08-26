-- Headless coverage of the bundle runtime.
--
-- The engine is not here, so nothing about what a feature *does* can be
-- tested.  What can be, and is exactly where a bundle of a dozen mods breaks,
-- is the seam between them: that two mods calling a row `enabled` get two
-- rows, that one mod's save keys cannot land in another's, that a feature
-- switched off is not installed, and that `mod.find` still reaches a sibling
-- after the mod it named stopped being a mod.
--
-- Run:  luajit tests/runtime_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

-- ---------------------------------------------------------------- harness

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

-- A stand-in for the engine's mod object: enough of it that the runtime can
-- be exercised, and instrumented so a test can see what the runtime did.
local function fakeMod(id)
  local self
  self = {
    id = id or "gen1_wild_ui",
    path = ".",
    version = "1.0.0",
    exports = {},
    -- what the runtime asked the engine for
    defined = nil,
    stored = {},
    saved = {},
    cached = {},
    logged = {},
    hooked = {},
    events_on = {},
    screens = {},
    found = {},
  }

  -- Reads fall to a virtual filesystem first, so a test can hand the runtime
  -- a module without one existing on disk, then to the repo, so runtime/*.lua
  -- is the real thing under test.
  self.files = {}
  function self:read(path)
    if self.files[path] then return self.files[path] end
    return readFile(path)
  end

  self.options = {
    define = function(_, schema) self.defined = schema end,
    get = function(_, key) return self.stored[key] end,
    set = function(_, key, value) self.stored[key] = value end,
  }

  self.save = {
    get = function(_, key, fallback)
      local value = self.saved[key]
      if value == nil then return fallback end
      return value
    end,
    set = function(_, key, value) self.saved[key] = value end,
  }

  self.cache = {
    read = function(_, file) return self.cached[file] end,
    write = function(_, file, bytes) self.cached[file] = bytes end,
  }

  self.storage = {
    read = function(_, _game, key) return self.saved["storage:" .. key] end,
    write = function(_, _game, key, value)
      self.saved["storage:" .. key] = value
      return true
    end,
    delete = function(_, _game, key) self.saved["storage:" .. key] = nil end,
  }

  self.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    self.log[level] = function(_, format, ...)
      self.logged[#self.logged + 1] = { level = level,
        text = select("#", ...) > 0 and format:format(...) or format }
    end
  end

  self.hooks = {
    wrap = function(_, name, fn, priority)
      self.hooked[#self.hooked + 1] = { name = name, fn = fn, priority = priority }
    end,
  }

  self.events = {
    on = function(_, name, fn)
      self.events_on[#self.events_on + 1] = { name = name, fn = fn }
    end,
    once = function(_, name, fn)
      self.events_on[#self.events_on + 1] = { name = name, fn = fn, once = true }
    end,
    emit = function(_, name, payload)
      for _, entry in ipairs(self.events_on) do
        if entry.name == name then entry.fn(payload) end
      end
    end,
  }

  self.content = {
    screens = {
      register = function(_, screenId, factory)
        self.screens[screenId] = factory
      end,
    },
  }

  self.ui = {
    push = function() end,
    insertBefore = function(rows, _anchor, row)
      rows[#rows + 1] = row
      return rows
    end,
    TextBox = { new = function() return {} end },
    Font = {},
  }

  self.find = function(name)
    if type(name) ~= "string" then return nil end
    return self.found[name]
  end

  self.world = { game = nil }
  return self
end

local function load_(path, ...)
  local source = assert(readFile(path), path .. " is missing")
  local chunk = assert(load(source, "@" .. path))
  return chunk(...)
end

local OptionSet = load_("runtime/optionset.lua")
local Facade = load_("runtime/facade.lua")
local Registry = load_("runtime/registry.lua")

-- ------------------------------------------------- option key namespacing

do
  io.write("option keys are namespaced per feature\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()

  local sprint = { id = "sprint", label = "SPRINT", dir = "Gen1Sprint",
                   enabledKey = "enabled", default = true }
  local autosave = { id = "autosave", label = "AUTO SAVE", dir = "Gen1AutoSave",
                     enabledKey = "enabled", default = true }

  optionset.master(sprint)
  optionset.master(autosave)

  optionset.adopt(sprint, {
    { key = "enabled", type = "toggle", label = "SPRINT", default = true },
    { key = "speed", type = "choice", label = "SPEED", default = "2",
      choices = { { "1.5x", "1_5" }, { "2x", "2" } },
      visible_if = { key = "enabled", equals = true } },
  })
  optionset.adopt(autosave, {
    { key = "enabled", type = "toggle", label = "AUTO SAVE", default = true },
    { key = "interval", type = "number", label = "EVERY", default = 5,
      min = 1, max = 60 },
  })

  eq(#optionset.rows, 4, "four rows across two features")
  ok(optionset.byKey["sprint_enabled"], "sprint keeps its own enabled")
  ok(optionset.byKey["autosave_enabled"], "autosave keeps its own enabled")

  -- The collision this whole design exists to prevent.
  mod.stored["sprint_enabled"] = false
  mod.stored["autosave_enabled"] = true
  eq(optionset.read(mod, "sprint_enabled"), false, "sprint reads its own value")
  eq(optionset.read(mod, "autosave_enabled"), true, "autosave is unaffected")

  local speed = optionset.byKey["sprint_speed"]
  eq(speed.visible_if.key, "sprint_enabled",
     "visible_if is rewritten to the same feature's key")

  -- Out-of-vocabulary values fall back rather than reaching the feature.
  mod.stored["sprint_speed"] = "9000x"
  eq(optionset.read(mod, "sprint_speed"), "2", "an illegal choice falls back to the default")
  mod.stored["autosave_interval"] = 999
  eq(optionset.read(mod, "autosave_interval"), 60, "a number is clamped to its max")
  mod.stored["autosave_interval"] = nil
  eq(optionset.read(mod, "autosave_interval"), 5, "an unset number reads its default")
end

-- ------------------------------------------------------- default overrides

do
  io.write("bundle defaults override upstream ones\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()

  -- Gen151 ships enabled upstream; suppose the bundle wanted it off.
  local gen151 = { id = "gen151", label = "ALL 151", dir = "Gen151",
                   enabledKey = "enabled", default = false }
  optionset.master(gen151)
  optionset.adopt(gen151, {
    { key = "enabled", type = "toggle", label = "GEN151", default = true },
    { key = "rarity", type = "number", label = "RARITY %", default = 100 },
  })
  eq(optionset.read(mod, "gen151_enabled"), false,
     "the bundle's default wins over upstream's")

  -- A choice master takes its default verbatim when the value is one it offers.
  local banners = { id = "banners", label = "AREA BANNER", dir = "QualityOfLife",
                    enabledKey = "qol_location_banners", default = false }
  optionset.master(banners)
  optionset.adopt(banners, {
    { key = "qol_location_banners", type = "choice", label = "AREA BANNER",
      default = 2, choices = { { "OFF", false }, { "ON", 2 } } },
  })
  eq(optionset.read(mod, "banners_qol_location_banners"), false,
     "a choice master ships on the bundle's chosen value")

  -- A per-row override reaches a row that is not the master.
  local sound = { id = "sound", label = "SOUND", dir = "Gen1SoundQOL",
                  default = true, defaults = { alarm_cycles = 3 } }
  optionset.master(sound)
  optionset.adopt(sound, {
    { key = "alarm_cycles", type = "number", label = "CYCLES", default = 1 },
  })
  eq(optionset.read(mod, "sound_alarm_cycles"), 3, "a defaults entry overrides one row")
  eq(optionset.read(mod, "sound_enabled"), true, "a synthesized master defaults on")
end

-- --------------------------------------------------------- facade plumbing

do
  io.write("the facade keeps each feature inside its own namespace\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()
  local registry = Registry.new(mod, { paired_bundle = "gen1_wild_qol" })
  local feature = { id = "bag", label = "BAG", dir = "Gen1ModernBag" }
  optionset.master(feature)

  local context = { mod = mod, optionset = optionset, registry = registry,
                    shared = {} }
  local facade = Facade.new(feature, context)

  eq(facade.id, mod.id, "the facade shares the bundle's id, which options key on")
  ok(facade.path:find("modules/Gen1ModernBag", 1, true),
     "the facade's path points inside its own module folder")

  -- options
  facade.options:define({
    { key = "opening_pocket", type = "choice", label = "OPENS ON",
      default = "medicine", choices = { { "MEDICINE", "medicine" },
                                        { "BALLS", "balls" } } },
  })
  eq(facade.options:get("opening_pocket"), "medicine",
     "the feature reads its own raw key")
  ok(optionset.byKey["bag_opening_pocket"], "the engine sees the prefixed key")
  eq(optionset.byKey["opening_pocket"], nil, "the raw key is never registered")

  -- save
  facade.save:set("last_pocket", "balls")
  eq(mod.saved["bag.last_pocket"], "balls", "a save key is prefixed")
  eq(facade.save:get("last_pocket"), "balls", "and reads back unprefixed")
  eq(mod.saved["last_pocket"], nil, "nothing lands on the bare key")
  eq(facade.save:get("never_written", "fallback"), "fallback",
     "a default argument survives the proxy")

  -- cache and storage
  facade.cache:write("layout", "bytes")
  eq(mod.cached["bag.layout"], "bytes", "a cache file is prefixed")
  facade.storage:write(nil, "audit", "body")
  eq(mod.saved["storage:bag.audit"], "body",
     "a storage key is prefixed even though it is the second argument")

  -- logging
  facade.log:info("hello %s", "world")
  eq(mod.logged[#mod.logged].text, "[BAG] hello world",
     "log lines carry the feature name")

  -- passthrough
  facade.hooks:wrap("battle.draw", function() end)
  eq(mod.hooked[#mod.hooked].name, "battle.draw", "hooks pass straight through")
end

-- ------------------------------------------------------- hook suppression

do
  io.write("suppressed hooks are not registered\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()
  local registry = Registry.new(mod, {})
  local feature = { id = "expshare", label = "EXP SHARE", dir = "ExpShare",
                    suppress_hooks = { ["ui.options.rows"] = true } }
  local facade = Facade.new(feature, { mod = mod, optionset = optionset,
                                       registry = registry, shared = {} })

  facade.hooks:wrap("ui.options.rows", function() end)
  facade.hooks:wrap("battle.exp_award", function() end, 90)

  eq(#mod.hooked, 1, "only the unsuppressed hook reached the engine")
  eq(mod.hooked[1].name, "battle.exp_award", "and it is the right one")
  eq(mod.hooked[1].priority, 90, "with its priority intact")
end

-- --------------------------------------------------- options_changed events

do
  io.write("mod.options_changed is translated into each feature's vocabulary\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()
  local registry = Registry.new(mod, {})

  local autosave = { id = "autosave", label = "AUTO SAVE", dir = "Gen1AutoSave" }
  local sprint = { id = "sprint", label = "SPRINT", dir = "Gen1Sprint" }
  local autosaveFacade = Facade.new(autosave, { mod = mod, optionset = optionset,
                                                registry = registry, shared = {} })
  local sprintFacade = Facade.new(sprint, { mod = mod, optionset = optionset,
                                            registry = registry, shared = {} })

  local seen = {}
  autosaveFacade.events:on("mod.options_changed", function(event)
    seen[#seen + 1] = { who = "autosave", key = event.key,
                        isFacade = event.mod == autosaveFacade }
  end)
  sprintFacade.events:on("mod.options_changed", function(event)
    seen[#seen + 1] = { who = "sprint", key = event.key }
  end)

  -- The engine reports the prefixed key it actually stores, identifying the
  -- mod by object.
  mod.events:emit("mod.options_changed", { mod = mod, key = "autosave_interval" })

  eq(#seen, 1, "only the feature that owns the key is told")
  eq(seen[1].who, "autosave", "and it is the right feature")
  eq(seen[1].key, "interval", "the key arrives without the prefix")
  ok(seen[1].isFacade, "a payload naming the mod by object is pointed at the facade")

  seen = {}
  mod.events:emit("mod.options_changed", { mod = mod, key = "sprint_speed" })
  eq(#seen, 1, "the other feature's key reaches only the other feature")
  eq(seen[1].who, "sprint", "correctly routed")

  -- A payload with no key at all means "something changed"; everyone hears it.
  seen = {}
  mod.events:emit("mod.options_changed", { mod = mod })
  eq(#seen, 2, "a keyless payload reaches every feature")
end

-- --------------------------------------------------------------- mod.find

do
  io.write("mod.find still resolves siblings after bundling\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()
  local registry = Registry.new(mod, { paired_bundle = "gen1_wild_qol" })

  local gen151 = { id = "gen151", label = "ALL 151", dir = "Gen151",
                   aliases = { "Gen151" } }
  local sprint = { id = "sprint", label = "SPRINT", dir = "Gen1Sprint",
                   aliases = { "Gen1Sprint", "gen1_sprint" } }

  local sprintFacade = Facade.new(sprint, { mod = mod, optionset = optionset,
                                            registry = registry, shared = {} })
  sprintFacade.exports.active = function() return true end
  registry.register(sprint, sprintFacade.exports)

  local gen151Facade = Facade.new(gen151, { mod = mod, optionset = optionset,
                                            registry = registry, shared = {} })

  -- 1. a sibling in this bundle, by every name it goes by
  ok(gen151Facade.find("Gen1Sprint"), "a sibling resolves by its repository name")
  ok(gen151Facade.find("gen1_sprint"), "and by its upstream manifest id")
  ok(gen151Facade.find("sprint"), "and by its bundle feature id")
  eq(gen151Facade.find("Gen1Sprint"), sprintFacade.exports,
     "and what comes back is that feature's exports")

  -- 2. a feature in the paired bundle
  local dexExports = { dexForSpecies = function() end }
  mod.found["gen1_wild_qol"] = { features = { ["gen1dex"] = dexExports } }
  eq(gen151Facade.find("Gen1Dex"), dexExports,
     "a feature in the other half of the split is reached through it")

  -- 3. a genuinely external mod
  local external = { exports = {} }
  mod.found["DRAMATIC_SHAPE"] = external
  eq(gen151Facade.find("DRAMATIC_SHAPE"), external,
     "an external mod still comes from the engine")

  eq(gen151Facade.find("nothing_at_all"), nil, "an unknown name is nil, not an error")

  -- the colon-style call Gen1Follower makes
  eq(gen151Facade.find(gen151Facade, "Gen1Sprint"), sprintFacade.exports,
     "find(mod, name) works as well as find(name)")
end

-- ------------------------------------------------------ per-save storage

do
  io.write("options read from the live save first\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()
  local feature = { id = "sprint", label = "SPRINT", dir = "Gen1Sprint",
                    enabledKey = "enabled", default = true }
  optionset.master(feature)
  optionset.adopt(feature, {
    { key = "enabled", type = "toggle", label = "SPRINT", default = true },
  })

  local game = { save = { options = { modOptions = {} } }, wrote = 0 }
  function game:writeOptions() self.wrote = self.wrote + 1 end
  optionset.resolveGame = function() return game end

  eq(optionset.read(mod, "sprint_enabled"), true, "unset reads the default")

  optionset.write(mod, "sprint_enabled", false, game)
  eq(game.save.options.modOptions[mod.id]["sprint_enabled"], false,
     "a write lands in the save's own bucket")
  eq(optionset.read(mod, "sprint_enabled"), false, "and is read back immediately")
  eq(game.wrote, 1, "the save was persisted")

  -- The save beats the engine's load-time view.
  mod.stored["sprint_enabled"] = true
  eq(optionset.read(mod, "sprint_enabled"), false, "the save still wins")

  eq(optionset.enabled(mod, "sprint"), false, "enabled() agrees")
end

-- ------------------------------------------- raw keys written by the manager

do
  io.write("rows the mod manager writes unprefixed are read and written both ways\n")
  local mod = fakeMod()
  local optionset = OptionSet.new()
  local modmenu = { id = "modmenu", label = "MOD MENU", dir = "Gen1ModMenu",
                    raw_option_keys = { "sort", "hide_disabled" } }
  optionset.master(modmenu)
  optionset.adopt(modmenu, {
    { key = "sort", type = "choice", label = "SORT", default = "name",
      choices = { { "NAME", "name" }, { "CATEGORY", "category" } } },
    { key = "hide_disabled", type = "toggle", label = "HIDE OFF", default = false },
    { key = "help_line", type = "toggle", label = "HELP LINE", default = true },
  })

  local game = { save = { options = { modOptions = {} } } }
  function game:writeOptions() end
  optionset.resolveGame = function() return game end

  -- Gen1ModMenu reaching the engine's manager: an unprefixed write.
  game.save.options.modOptions[mod.id] = { sort = "category" }
  eq(optionset.read(mod, "modmenu_sort"), "category",
     "a value written unprefixed by the manager is still read")

  -- The bundle menu writing the same row: both spellings move together.
  optionset.write(mod, "modmenu_sort", "name", game)
  local bucket = game.save.options.modOptions[mod.id]
  eq(bucket["modmenu_sort"], "name", "the prefixed spelling is written")
  eq(bucket["sort"], "name", "and so is the raw one the manager will read")

  -- A row not on the list gets no raw fallback, which is the point: five of
  -- these mods call a row `enabled` and must never see each other's.
  game.save.options.modOptions[mod.id]["help_line"] = false
  eq(optionset.read(mod, "modmenu_help_line"), true,
     "a row outside the list ignores the raw spelling entirely")
end

-- ------------------------------------------------- install order vs menu order

do
  io.write("features install by priority and are listed in declaration order\n")

  -- Reproduce the sort bundle.lua does, from the same inputs, so the ordering
  -- rule is pinned by a test rather than only by a comment.  Declaration
  -- order here is the menu's; priority is each mod's own manifest value.
  local declared = {
    { id = "dex",      priority = 1100 },
    { id = "box",      priority = 1100 },
    { id = "party",    priority = 1100 },
    { id = "arena",    priority = 50 },
    { id = "modmenu",  priority = 500 },
    { id = "bag",      priority = 520 },
    { id = "menus",    priority = 900 },
  }

  local ordered = {}
  for index, feature in ipairs(declared) do
    ordered[#ordered + 1] = { feature = feature, index = index }
  end
  table.sort(ordered, function(a, b)
    local pa = a.feature.priority or 100
    local pb = b.feature.priority or 100
    if pa ~= pb then return pa < pb end
    return a.index < b.index
  end)

  local names = {}
  for i, entry in ipairs(ordered) do names[i] = entry.feature.id end
  eq(table.concat(names, ","), "arena,modmenu,bag,menus,dex,box,party",
     "installation ascends by the upstream manifest priority")

  -- The tie is what keeps Gen1Party working: it optionally reads Gen1Dex and
  -- Gen1BillsBox, so both must be registered before it.
  local position = {}
  for i, name in ipairs(names) do position[name] = i end
  ok(position.dex < position.party, "Gen1Dex installs before Gen1Party")
  ok(position.box < position.party, "Gen1BillsBox installs before Gen1Party")

  -- And the menu is unaffected: it reads the declared list.
  eq(declared[1].id, "dex", "the menu still lists features as declared")
end

-- ------------------------------------------------------ end-to-end install

do
  io.write("bundle.install handles both entry shapes and gates what is off\n")

  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)

  local mod = fakeMod()
  local ran = {}

  -- Shape one: `return function(mod) ... end`, which eleven of the twelve use.
  mod.files["modules/Returner/main.lua"] = [[
    return function(mod)
      mod.options:define({
        { key = "enabled", type = "toggle", label = "RETURNER", default = true },
        { key = "flavour", type = "choice", label = "FLAVOUR", default = "a",
          choices = { { "A", "a" }, { "B", "b" } } },
      })
      mod.exports.installed = true
      _G.__test_ran = (_G.__test_ran or 0) + 1
      _G.__test_returner = mod.options:get("flavour")
    end
  ]]

  -- Shape two: `local mod = ...`, installing at chunk scope and returning a
  -- table.  Gen1Arena is written this way, and calling its chunk with no
  -- argument would leave `mod` nil and take the whole feature down.
  mod.files["modules/ChunkArg/main.lua"] = [[
    local mod = ...
    mod.options:define({
      { key = "enabled", type = "toggle", label = "CHUNKARG", default = true },
    })
    mod.exports.installed = true
    _G.__test_ran = (_G.__test_ran or 0) + 1
    _G.__test_chunkarg = mod.id
    return {}
  ]]

  -- A feature switched off must not be run at all.
  mod.files["modules/Skipped/main.lua"] = [[
    return function(mod)
      _G.__test_skipped_ran = true
    end
  ]]

  _G.__test_ran = 0
  mod.stored["skipped_enabled"] = false

  local spec = { id = "gen1_wild_ui", menu_label = "GEN1WILD UI",
                 screen_id = "Gen1WildUI", paired_bundle = "gen1_wild_qol" }
  local features = {
    { id = "returner", dir = "Returner", entry = "main.lua", label = "RETURNER",
      enabledKey = "enabled", default = true, priority = 100 },
    { id = "chunkarg", dir = "ChunkArg", entry = "main.lua", label = "CHUNKARG",
      enabledKey = "enabled", default = true, priority = 50 },
    { id = "skipped", dir = "Skipped", entry = "main.lua", label = "SKIPPED",
      default = false, priority = 200 },
  }

  local result = Bundle.install(mod, spec, features)

  eq(_G.__test_ran, 2, "both entry shapes ran")
  eq(_G.__test_chunkarg, mod.id, "a chunk-argument mod received the facade")
  eq(_G.__test_returner, "a", "and a returned installer read its own option")
  eq(_G.__test_skipped_ran, nil, "a feature switched off was never run")
  eq(mod.exports.installed.skipped, false, "and is reported as not installed")
  eq(mod.exports.installed.returner, true, "the others are reported installed")

  -- The merged schema reached the engine exactly once, prefixed.
  ok(mod.defined, "the schema was defined")
  local byKey = {}
  for _, row in ipairs(mod.defined) do byKey[row.key] = row end
  ok(byKey["returner_enabled"], "the returner's master is prefixed")
  ok(byKey["returner_flavour"], "and so are its settings")
  ok(byKey["chunkarg_enabled"], "the chunk-arg mod's master is prefixed")
  ok(byKey["skipped_enabled"],
     "a switched-off feature still has a master row, so it can be switched on")
  eq(byKey["enabled"], nil, "no unprefixed key reached the engine")

  -- The menu registered its screens.
  ok(mod.screens["Gen1WildUI"], "the root screen is registered")
  ok(mod.screens["Gen1WildUI_returner"], "and one per feature")

  -- And the bundle published what the other half needs to find it.
  ok(mod.exports.features, "the bundle publishes its feature table")
  ok(mod.exports.features["returner"], "keyed by feature id")

  _G.__test_ran, _G.__test_chunkarg, _G.__test_returner = nil, nil, nil
  _G.__test_skipped_ran = nil
end

-- ------------------------------------------------------------------ done

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
