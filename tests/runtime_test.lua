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

-- runtime/claims.lua parks its table on an engine module, and the engine is
-- not here.  Stand one in, so the sharing tests exercise the real lookup
-- rather than only its fallback.
package.loaded["src.mods.ManagerState"] = { openOptions = function() end }

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

  -- Gen151 iterates what define() hands back to build its own validation
  -- table, so the return value has to be the schema, in the feature's own
  -- unprefixed vocabulary.
  local returned = facade.options:define({
    { key = "placeCry", type = "toggle", label = "PLACE CRY", default = true },
  })
  eq(type(returned), "table", "define returns a table")
  eq(#returned, 1, "with the rows in it")
  eq(returned[1].key, "placeCry", "still under the key the feature wrote")
  ok(optionset.byKey["bag_placeCry"], "while the engine got the prefixed one")
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

  -- What comes back must be a HANDLE, not the exports table. The engine's own
  -- mod.find returns { id, version, exports }, and mods read it that way:
  -- Gen151 asks for `dex.exports.area` and logs `dex.version`. A registry
  -- that answered with the exports table would hand back something whose
  -- `.exports` is nil, and every cross-mod integration would go quietly dead
  -- instead of failing. That is exactly what happened until it was fixed, so
  -- the shape is pinned here.
  local handle = gen151Facade.find("Gen1Sprint")
  eq(type(handle), "table", "a lookup returns a table")
  eq(handle.exports, sprintFacade.exports, "with the exports under .exports")
  eq(type(handle.exports.active), "function", "reachable the way a mod reads it")
  ok(handle.id, "carrying an id")
  eq(handle.exports.exports, nil, "and not the exports table wearing itself")

  -- 1. a sibling in this bundle, by every name it goes by
  ok(gen151Facade.find("Gen1Sprint"), "a sibling resolves by its repository name")
  ok(gen151Facade.find("gen1_sprint"), "and by its upstream manifest id")
  ok(gen151Facade.find("sprint"), "and by its bundle feature id")
  eq(gen151Facade.find("Gen1Sprint").exports, sprintFacade.exports,
     "and what comes back carries that feature's exports")

  -- 2. a feature in the paired bundle
  local dexExports = { dexForSpecies = function() end }
  mod.found["gen1_wild_qol"] = { features = { ["gen1dex"] = dexExports } }
  eq(gen151Facade.find("Gen1Dex").exports, dexExports,
     "a feature in the other half of the split is reached through it")

  -- 3. a genuinely external mod
  local external = { exports = {} }
  mod.found["DRAMATIC_SHAPE"] = external
  eq(gen151Facade.find("DRAMATIC_SHAPE"), external,
     "an external mod still comes from the engine")

  eq(gen151Facade.find("nothing_at_all"), nil, "an unknown name is nil, not an error")

  -- A paired bundle released before handles existed publishes the exports
  -- table itself; it is wrapped so the caller sees one shape either way.
  mod.found["gen1_wild_qol"] = { features = { ["gen1party"] = { colours = true } } }
  local wrapped = gen151Facade.find("Gen1Party")
  eq(type(wrapped), "table", "an older paired bundle still resolves")
  eq(wrapped.exports.colours, true, "and its exports are reachable the same way")

  -- the colon-style call Gen1Follower makes
  eq(gen151Facade.find(gen151Facade, "Gen1Sprint").exports, sprintFacade.exports,
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

-- ------------------------------------------- features carried by both bundles

do
  io.write("a feature in both bundles is installed by exactly one of them\n")

  local Claims = load_("runtime/claims.lua")

  local claims, host = Claims.table()
  ok(claims, "a shared claim table was found")
  ok(host, "parked on an engine module (" .. tostring(host) .. ")")

  -- Both bundles requiring the module get the same table; that is the whole
  -- mechanism, so prove it rather than assume it.
  local again = Claims.table()
  eq(again, claims, "requiring it again returns the same table")

  local feature = {
    id = "modmenu", label = "MOD MANAGER", dir = "Gen1ModMenu",
    shared = { claim = "gen1wild_mod_menu", storage = "gen1_wild_shared",
               owner = "gen1_wild_ui" },
  }

  local qol = fakeMod("gen1_wild_qol")
  local ui = fakeMod("gen1_wild_ui")

  -- Whoever loads first takes it.
  local firstMine, firstHolder = Claims.take(qol, feature, claims)
  ok(firstMine, "the first bundle to load claims the feature")
  eq(firstHolder, nil, "and is not told to stand down")

  local secondMine, secondHolder = Claims.take(ui, feature, claims)
  eq(secondMine, false, "the second bundle does not install it again")
  eq(secondHolder, "gen1_wild_qol", "and is told who did")

  -- Re-entering is idempotent: the holder claiming again still holds it.
  local againMine = Claims.take(qol, feature, claims)
  ok(againMine, "the holder re-claiming its own feature still installs")

  -- The order is symmetric: whichever loads first wins.
  local fresh = {}
  ok(Claims.take(ui, feature, fresh), "loaded the other way round, UI claims it")
  eq(Claims.take(qol, feature, fresh), false, "and QOL stands down")

  -- With no shared table at all the two bundles cannot talk, so the declared
  -- owner is the only one that installs.  A double install is the failure
  -- worth avoiding; a missing feature is the lesser one.
  ok(Claims.take(ui, feature, nil), "with no shared table the owner installs")
  eq(Claims.take(qol, feature, nil), false, "and the non-owner stands down")

  -- A feature with no owner declared falls back to installing, because
  -- nothing else in the bundle is shared and there is nothing to collide with.
  local solo = { id = "sprint", label = "SPRINT", dir = "Gen1Sprint",
                 shared = { claim = "solo" } }
  ok(Claims.take(qol, solo, nil), "an unowned shared feature installs anyway")
end

do
  io.write("a shared feature's settings do not move when the winner does\n")

  -- The point of `shared.storage`: install one bundle, set the row, install
  -- the other, and the setting is still there even though a different bundle
  -- is now the one hosting the feature.
  local feature = {
    id = "modmenu", label = "MOD MANAGER", dir = "Gen1ModMenu",
    shared = { claim = "gen1wild_mod_menu", storage = "gen1_wild_shared" },
  }

  local game = { save = { options = { modOptions = {} } } }
  function game:writeOptions() end

  local function bundleFor(id)
    local mod = fakeMod(id)
    local optionset = OptionSet.new()
    optionset.resolveGame = function() return game end
    optionset.master(feature)
    optionset.adopt(feature, {
      { key = "sort", type = "choice", label = "SORT", default = "name",
        choices = { { "NAME", "name" }, { "CATEGORY", "category" } } },
    })
    return mod, optionset
  end

  local qolMod, qolOptions = bundleFor("gen1_wild_qol")
  qolOptions.write(qolMod, "modmenu_sort", "category", game)

  eq(game.save.options.modOptions["gen1_wild_shared"]["modmenu_sort"], "category",
     "the value is stored under the shared id, not the bundle's")
  eq(game.save.options.modOptions["gen1_wild_qol"], nil,
     "nothing was written to the bundle's own bucket")

  -- The other bundle, loading later and hosting the feature this time.
  local uiMod, uiOptions = bundleFor("gen1_wild_ui")
  eq(uiOptions.read(uiMod, "modmenu_sort"), "category",
     "the other bundle reads the same value back")

  -- The master switch is shared too, so either menu's row is the same switch.
  uiOptions.write(uiMod, "modmenu_enabled", false, game)
  eq(qolOptions.read(qolMod, "modmenu_enabled"), false,
     "switching it off in one bundle switches it off in the other")

  -- A feature that is not shared keeps its own bundle's bucket.
  local plain = { id = "sprint", label = "SPRINT", dir = "Gen1Sprint" }
  qolOptions.master(plain)
  qolOptions.adopt(plain, {
    { key = "speed", type = "choice", label = "SPEED", default = "2",
      choices = { { "2x", "2" }, { "3x", "3" } } },
  })
  qolOptions.write(qolMod, "sprint_speed", "3", game)
  eq(game.save.options.modOptions["gen1_wild_qol"]["sprint_speed"], "3",
     "an unshared row still lives under its own bundle")
  eq(game.save.options.modOptions["gen1_wild_shared"]["sprint_speed"], nil,
     "and not in the shared bucket")
end

-- ------------------------------- both bundles loading, as the player has them

do
  io.write("with both bundles installed the shared feature installs once\n")

  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)

  local sharedFeatureSource = [[
    return function(mod)
      mod.options:define({
        { key = "sort", type = "choice", label = "SORT", default = "name",
          choices = { { "NAME", "name" }, { "CATEGORY", "category" } } },
      })
      _G.__test_shared_installs = (_G.__test_shared_installs or 0) + 1
      _G.__test_shared_by = mod.id
    end
  ]]

  local ownFeatureSource = [[
    return function(mod)
      mod.options:define({
        { key = "flavour", type = "toggle", label = "FLAVOUR", default = true },
      })
    end
  ]]

  local function bundleOf(id, label, screen, paired, ownDir)
    local mod = fakeMod(id)
    mod.files["modules/Shared/main.lua"] = sharedFeatureSource
    mod.files["modules/" .. ownDir .. "/main.lua"] = ownFeatureSource
    local spec = { id = id, menu_label = label, screen_id = screen,
                   paired_bundle = paired }
    local features = {
      { id = "own", dir = ownDir, entry = "main.lua", label = "OWN",
        default = true, priority = 100 },
      { id = "shared", dir = "Shared", entry = "main.lua", label = "SHARED",
        default = true, priority = 500,
        shared = { claim = "test_shared_feature",
                   storage = "gen1_wild_shared",
                   owner = "gen1_wild_ui" } },
    }
    return mod, spec, features
  end

  _G.__test_shared_installs = 0

  -- The engine loads QOL first: its manifest priority is lower.
  local qolMod, qolSpec, qolFeatures =
    bundleOf("gen1_wild_qol", "GEN1WILD QOL", "Gen1WildQOL", "gen1_wild_ui", "Sprint")
  Bundle.install(qolMod, qolSpec, qolFeatures)

  local uiMod, uiSpec, uiFeatures =
    bundleOf("gen1_wild_ui", "GEN1WILD UI", "Gen1WildUI", "gen1_wild_qol", "Arena")
  Bundle.install(uiMod, uiSpec, uiFeatures)

  eq(_G.__test_shared_installs, 1,
     "the shared feature was installed exactly once across both bundles")
  eq(_G.__test_shared_by, "gen1_wild_qol", "by whichever loaded first")

  eq(qolMod.exports.installed.shared, true, "the winner reports it installed")
  eq(uiMod.exports.installed.shared, false, "the other reports it did not")
  eq(uiMod.exports.deferred.shared, "gen1_wild_qol",
     "and names who did, so the menu can say so")
  eq(qolMod.exports.deferred.shared, nil, "the winner defers nothing")

  -- Each bundle's own features are unaffected by any of this.
  eq(qolMod.exports.installed.own, true, "the QOL bundle's own feature installed")
  eq(uiMod.exports.installed.own, true, "and so did the UI bundle's")

  -- Both bundles still carry the master row, so the switch is reachable from
  -- either menu -- and both point at the same stored value.
  local function keys(defined)
    local out = {}
    for _, row in ipairs(defined) do out[row.key] = true end
    return out
  end
  ok(keys(qolMod.defined)["shared_enabled"], "the winner defines the master row")
  ok(keys(uiMod.defined)["shared_enabled"],
     "and so does the bundle that stood down, so its menu has the switch")
  ok(keys(qolMod.defined)["shared_sort"], "only the winner defines the settings")
  eq(keys(uiMod.defined)["shared_sort"], nil,
     "the other has no schema for them, having never run the feature")

  _G.__test_shared_installs, _G.__test_shared_by = nil, nil
end

-- ------------------------------------- two shared features, claimed apart

do
  io.write("MENU LAYOUT and MOD MANAGER are claimed independently\n")

  local Claims = load_("runtime/claims.lua")

  -- The two real shared features, with the claim keys features.lua gives
  -- them. They are both in both bundles, and each must be settled on its own:
  -- a shared claim key would let one feature lock the other out.
  local menus = {
    id = "menus", label = "MENU LAYOUT", dir = "Gen1MenuManager",
    shared = { claim = "gen1wild_menu_manager", storage = "gen1_wild_shared",
               owner = "gen1_wild_ui" },
  }
  local modmenu = {
    id = "modmenu", label = "MOD MANAGER", dir = "Gen1ModMenu",
    shared = { claim = "gen1wild_mod_menu", storage = "gen1_wild_shared",
               owner = "gen1_wild_ui" },
  }

  ok(menus.shared.claim ~= modmenu.shared.claim,
     "the two features do not share a claim key")

  local qol = fakeMod("gen1_wild_qol")
  local ui = fakeMod("gen1_wild_ui")
  local table_ = {}

  -- QOL loads first and takes both, because it declares both.
  ok(Claims.take(qol, menus, table_), "QOL claims MENU LAYOUT")
  ok(Claims.take(qol, modmenu, table_), "and MOD MANAGER as well")

  -- UI, loading second, defers both -- and neither claim interferes with the
  -- other's answer.
  local menusMine, menusHolder = Claims.take(ui, menus, table_)
  local modMine, modHolder = Claims.take(ui, modmenu, table_)
  eq(menusMine, false, "UI defers MENU LAYOUT")
  eq(menusHolder, "gen1_wild_qol", "to whoever took it")
  eq(modMine, false, "and defers MOD MANAGER")
  eq(modHolder, "gen1_wild_qol", "likewise")

  -- Claiming one must never settle the other. If the two shared a key, this
  -- is the assertion that would fail: MOD MANAGER would come back already
  -- held on a table where only MENU LAYOUT had been claimed.
  local partial = {}
  ok(Claims.take(qol, menus, partial), "claiming MENU LAYOUT on a fresh table")
  ok(Claims.take(ui, modmenu, partial),
     "leaves MOD MANAGER free for the other bundle to take")
  eq(partial["gen1wild_menu_manager"], "gen1_wild_qol", "each key records its own holder")
  eq(partial["gen1wild_mod_menu"], "gen1_wild_ui", "independently of the other")
end

-- --------------------------------------------- the cards the shipped list uses
--
-- Both halves of the suite declare the same cards in the same order, because
-- either half can end up hosting the merged menu (runtime/menu.lua) and a
-- player who opens GEN1WILD UI should not get a differently-ordered version of
-- the screen GEN1WILD QOL would have shown.  The literal below is that
-- agreement written down; the other half's suite carries the same one, so
-- editing one repo's cards without the other fails here.

do
  io.write("every feature names one of the cards, and both halves agree on them\n")

  local registry = load_("features.lua")
  local groups = registry.spec.groups
  ok(type(groups) == "table", "the spec declares its cards")

  local declared, order = {}, {}
  for i, group in ipairs(groups or {}) do
    declared[group.id] = group.label
    order[i] = group.id
  end
  eq(table.concat(order, ","), "general,pokemon,battle,items,save,interface",
     "the cards, in the order both halves draw them")

  -- The labels are drawn on the card, so they are part of the agreement too.
  -- They are the plain names for what is on them: a player looking for the
  -- battle settings should not have to guess which invented phrase means
  -- "battle".
  eq(declared.general, "GENERAL", "a card says the plain name of what is on it")
  eq(declared.interface, "INTERFACE", "and so does the last one")

  -- Every card carries the line the menu prints under it.  A card with no
  -- description is a card that explains nothing about what is behind it.
  for _, group in ipairs(groups or {}) do
    ok(type(group.description) == "string" and group.description ~= "",
       group.id .. " says what is on it")
  end

  local homeless = {}
  for _, feature in ipairs(registry.features) do
    if not (feature.group and declared[feature.group]) then
      homeless[#homeless + 1] = feature.id
    end
  end
  eq(table.concat(homeless, ","), "",
     "every shipped feature sits on a card rather than loose on the top level")

  -- The card the other loaded mods go under is built by the menu, not declared
  -- here; a group of the same id would shadow it.
  ok(declared.other_mods == nil, "nothing declares the card the menu reserves")
end

-- ------------------------- the settings a sealed cart would otherwise eat
--
-- Loader:_applyCart rebuilds loader.modOptions on every boot out of what the
-- CART pins and throws the stored values away, for any seal that is not
-- "open".  Online requires the seal ("sealed" exactly), so unsealing is not
-- the answer -- the answer is to remember what the player chose somewhere the
-- merge does not reach, and put it back before anything reads it.
--
-- Back into the SAME table the mod manager reads, which is what stops this
-- being a second source of truth.

do
  io.write("a player's settings survive the cart's seal\n")

  local Settings = load_("runtime/settings.lua")

  -- a cache that behaves like the engine's: bytes in, bytes out, and empty
  -- until something writes it
  local files = {}
  local handlers = {}
  local logged = {}
  local loader = { modOptions = {} }
  local mod = {
    id = "gen1_wild_qol",
    cache = {
      read = function(_, name) return files[name] end,
      write = function(_, name, bytes) files[name] = bytes return true end,
    },
    events = { on = function(_, name, fn)
      handlers[name] = handlers[name] or {}
      table.insert(handlers[name], fn)
    end },
    log = { info = function() end,
            warn = function(_, f) logged[#logged + 1] = tostring(f) end },
    world = { game = { mods = loader } },
  }
  local function emit(name, ev)
    for _, fn in ipairs(handlers[name] or {}) do fn(ev) end
  end

  ok(Settings.watch(mod), "the bundle listens for option changes")

  -- the player changes three things, on three different mods, through
  -- whichever screen -- they all end in the same event
  emit("mod.options_changed", { mod = "wild_green", key = "player", value = "red" })
  emit("mod.options_changed", { mod = "gen1_wild_qol", key = "sprint_speed", value = 3 })
  emit("mod.options_changed", { mod = "gen1_wild_ui", key = "arena_enabled", value = false })
  ok(files["settings.txt"] ~= nil, "and remembers them outside the option table")

  -- ...and now the cart boots: the seal has replaced every pinned mod's
  -- options with what it pins, which here is one value and nothing else
  loader.modOptions = { wild_green = { ribbon = true } }

  local restored = Settings.restore(mod)
  eq(restored, 3, "every remembered value is put back")
  eq(loader.modOptions.wild_green.player, "red",
     "including the one the seal made impossible: PLAYER survives the boot")
  eq(loader.modOptions.wild_green.ribbon, true,
     "and the cart's own pin is left alone where the player never touched it")
  eq(loader.modOptions.gen1_wild_qol.sprint_speed, 3, "a number comes back a number")
  eq(loader.modOptions.gen1_wild_ui.arena_enabled, false,
     "and false comes back false rather than missing")

  -- into loader.modOptions, which is what the engine's own mod manager reads
  -- (ManagerState:modOptionsTable -> options.modOptions) -- so the manager,
  -- this suite's menu and the mods themselves cannot disagree
  ok(loader.modOptions.wild_green.player == "red",
     "and it is the table every screen reads, so none of them disagree")

  -- an unchanged value is not rewritten: the cache is touched when a choice
  -- is made, not on every event that echoes one
  local before = files["settings.txt"]
  files["settings.txt"] = "TOUCHED"
  emit("mod.options_changed", { mod = "wild_green", key = "player", value = "red" })
  eq(files["settings.txt"], "TOUCHED", "re-choosing the same value writes nothing")
  files["settings.txt"] = before

  -- the event carries the mod TABLE from a facade and the id from the
  -- manager; a setting remembered under the wrong name is one forgotten
  emit("mod.options_changed", { mod = { id = "wild_green" }, key = "name", value = false })
  local reread = Settings.read(mod)
  eq(reread.wild_green.name, false, "an event carrying the mod table is understood too")

  -- a read-only cache costs the memory of the choice, not the choice
  files = setmetatable({}, { __newindex = function() error("read-only", 0) end })
  emit("mod.options_changed", { mod = "wild_green", key = "player", value = "green" })
  ok(#logged > 0, "a cache that cannot be written says so rather than raising")

  -- and with no game yet there is no loader to restore into, which is a
  -- no-op rather than a crash on a host that loads mods before the game
  local orphan = { id = "x", cache = mod.cache, world = {},
                   log = mod.log, events = mod.events }
  eq(Settings.restore(orphan, { a = { b = 1 } }), 0,
     "with no loader to write to, nothing is restored and nothing raises")
end

-- ------------------------------------------------------------------ done


-- --------------------------------------------------------------- UI THEME

local Theme = load_("runtime/theme.lua")

-- The zone lists the hook has to tell apart, in the shapes the states that
-- build them actually return.
local function greysZone()
  return { colors = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 },
                      { 0, 0, 0 } }, x = 0, y = 0, w = 160, h = 144 }
end

local function menuZones()
  -- a black-and-white page with a species-coloured icon panel on it, which is
  -- what the party menu returns
  return {
    greysZone(),
    { colors = { { 255, 255, 255 }, { 255, 200, 100 }, { 180, 90, 20 },
                 { 0, 0, 0 } }, x = 16, y = 24, w = 16, h = 16 },
  }
end

local function overworldZones()
  -- terrain palettes, never whole-screen greys
  return {
    { colors = { { 255, 239, 255 }, { 148, 222, 148 }, { 82, 148, 82 },
                 { 0, 0, 0 } }, x = 0, y = 0, w = 160, h = 144 },
  }
end

local function titleZones()
  return {
    { colors = { { 255, 255, 255 }, { 230, 197, 0 }, { 148, 156, 148 },
                 { 41, 99, 181 } }, x = 0, y = 0, w = 160, h = 64 },
    { colors = { { 255, 255, 255 }, { 247, 247, 140 }, { 140, 189, 82 },
                 { 173, 0, 33 } }, x = 0, y = 64, w = 160, h = 16 },
  }
end

local function hex(c) return ("%02x%02x%02x"):format(c[1], c[2], c[3]) end

-- A theme instance over a real optionset, so reads and writes go the way they
-- go in a running game.
local function themeOver(mod)
  local optionset = OptionSet.new()
  local theme = Theme.new({ mod = mod, optionset = optionset })
  theme.defineRow()
  return theme, optionset
end

do
  io.write("a screen the suite registers is one of ours\n")
  -- The bug: SELECT MENU, the layout editor and everything else this bundle
  -- registers stayed white in a dark game.  The theme knows a page two ways --
  -- a marker on the instance, or one of the engine's own UI classes -- and a
  -- screen a mod registers is neither: a plain table with no class to match.
  -- So the registry marks them, once, instead of a list here that rots.
  local Facade = load_("runtime/facade.lua")

  local registered = {}
  local screens = {
    register = function(self, id, factory) registered[id] = factory end,
  }
  local mod = fakeMod()
  mod.content = { screens = screens }

  local facade = Facade.new({ id = "only", dir = "Only" },
                            { mod = mod, shared = {} })

  facade.content.screens:register("Opaque", {
    new = function() return { isOpaque = true, what = "a page" } end,
  })
  facade.content.screens:register("Overlay", {
    new = function() return { what = "a box over the map" } end,
  })

  local page = registered["Opaque"].new()
  ok(page.gen1wildTheme ~= nil,
    "an opaque screen is marked, so the theme takes it as the page")
  eq(page.what, "a page", "and the instance is otherwise the feature's own")

  -- The limit is the whole safety of this: the marker makes the theme
  -- synthesise a whole-screen page when the state declares no palettes, which
  -- over a map would darken the map with the box.
  local overlay = registered["Overlay"].new()
  eq(overlay.gen1wildTheme, nil,
    "a screen that is not opaque is left alone -- it reaches the theme as a "
    .. "panel or not at all")

  -- and a screen that already says what it is keeps its own answer
  facade.content.screens:register("Named", {
    new = function() return { isOpaque = true, gen1wildTheme = "settings" } end,
  })
  eq(registered["Named"].new().gen1wildTheme, "settings",
    "a screen that names itself is not overwritten")

  -- the registry is otherwise untouched
  facade.content.screens:register("Plain", "not a factory")
  eq(registered["Plain"], "not a factory",
    "and anything that is not a factory goes through as it came")
end

do
  io.write("the theme only answers for pages\n")
  local mod = fakeMod()
  local theme = themeOver(mod)

  eq(theme.read(), "light", "LIGHT is the default")

  local zones = menuZones()
  eq(theme.apply({}, zones), zones, "LIGHT hands the list straight back")
  eq(hex(zones[1].colors[1]), "ffffff", "...unchanged")

  theme.write("dark")
  eq(theme.read(), "dark", "and the row remembers")

  -- With no stack to walk, the list itself is all there is to go on, and
  -- neither of these is a page: one is a map's terrain palette and the other
  -- is the title screen's lettered bands.
  local world = overworldZones()
  theme.apply({}, world)
  eq(hex(world[1].colors[1]), "ffefff",
    "the overworld's terrain palette is not a page")

  local title = titleZones()
  theme.apply({}, title)
  eq(hex(title[1].colors[4]), "2963b5",
    "and neither is the title screen")
end

do
  io.write("DARK swaps the two, everywhere on the page\n")
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  local zones = theme.apply({}, menuZones())
  eq(hex(zones[1].colors[1]), "000000", "paper is black")
  eq(hex(zones[1].colors[4]), "ffffff", "ink is white")
  eq(hex(zones[1].colors[2]), "555555", "and the two shades between swap")
  eq(hex(zones[1].colors[3]), "aaaaaa", "...both ways")

  -- the icon panel goes with it, or a white-grounded icon would be a hole
  -- punched in a black page
  eq(hex(zones[2].colors[1]), "000000", "a panel inside the page reverses too")
  eq(hex(zones[2].colors[4]), "ffffff", "...ground for ink")

  -- art is not a palette
  local withArt = menuZones()
  withArt[#withArt + 1] = { colors = false, x = 8, y = 8, w = 32, h = 32 }
  local out = theme.apply({}, withArt)
  eq(out[3].colors, false, "a true-colour rect is left exactly as it came")
end

do
  io.write("a theme never writes into the list it was handed\n")
  -- The zone tables belong to the state that built them.  Every screen in this
  -- suite builds fresh, but a screen somebody adds later might hand back a
  -- list it keeps -- and a cached list written into is a screen that flickers,
  -- reversed on one frame and reversed back on the next, from a symptom nobody
  -- could trace.  So the transform is a pure function of its input.
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  local kept = menuZones()
  local out = theme.apply({}, kept)
  ok(out ~= kept, "the list that comes back is a new list")
  ok(out[1] ~= kept[1], "...of new zones")
  eq(hex(kept[1].colors[1]), "ffffff", "and the one handed in is untouched")

  -- the same list twice, which is what a screen that caches would do
  local again = theme.apply({}, kept)
  eq(hex(again[1].colors[1]), "000000",
    "so the same list themed twice is dark both times, not dark then light")
end

-- ------- the game's own screens
--
-- This is the regression the first version of UI THEME needed and did not
-- have.  The gate used to ask whether the zone list opened on whole-screen
-- DMG greys, on the theory that a black-and-white page asks for the identity
-- palette.  No screen in the engine does: OptionsMenu, ListMenu, ManagerState,
-- NamingScreen and TrainerCard all ask for MEWMON, the Pokedex asks for
-- BROWNMON, the party menu for GREENBAR.  So DARK declined every screen in
-- the game and the OPTION row moved a setting that changed nothing.
--
-- The stubs below are the shapes those screens really have: a class, an
-- instance of it on the stack, and a named palette that is not grey.
local function engineClass(path)
  local class = {}
  class.__index = class
  package.loaded[path] = nil
  package.preload[path] = function() return class end
  return class
end

-- PAL_MEWMON as the SGB pack carries it: off-white paper, the screen's hue in
-- the middle, near-black ink.  Every background palette in the pack is built
-- this way, which is what makes reversing one a dark page.
local function mewmonZones()
  return { { colors = { { 255, 239, 255 }, { 255, 132, 132 },
                        { 132, 0, 0 }, { 0, 0, 0 } },
             x = 0, y = 0, w = 160, h = 144 } }
end

do
  io.write("the game's own screens are pages, though none of them asks for grey\n")
  local OptionsMenu = engineClass("src.ui.OptionsMenu")
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  local options = setmetatable({ sgbPalettes = true }, OptionsMenu)
  local game = { stack = { states = { options } } }

  local out = theme.apply(game, mewmonZones())
  eq(hex(out[1].colors[1]), "000000",
    "the OPTION screen's paper goes black -- the bug the user reported was "
    .. "this line coming back ffefff")
  eq(hex(out[1].colors[4]), "ffefff", "and its ink goes to the paper it had")
  eq(hex(out[1].colors[2]), "840000",
    "with the screen's own hue kept in the shades between, which is what "
    .. "reversing a palette buys over painting a black rectangle")

  -- and the frame it was handed is still the frame it was handed
  local handed = mewmonZones()
  theme.apply(game, handed)
  eq(hex(handed[1].colors[1]), "ffefff", "the state's own list is untouched")
end

do
  io.write("a page that declares no palettes gets one made for it\n")
  -- The bag, the shops, Bill's box and the PC are not states: each builds a
  -- ListMenu and pushes THAT, and ListMenu does declare a palette.  But a
  -- screen that declares none inherits whatever is underneath -- and it is
  -- opaque, so those zones are colouring a map nobody can see.  Transforming
  -- them would invert the world; the page is made instead.
  local ListMenu = engineClass("src.ui.ListMenu")
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  local world = { sgbPalettes = true }
  local list = setmetatable({}, ListMenu)
  local game = { stack = { states = { world, list } } }

  local out = theme.apply(game, overworldZones())
  eq(#out, 1, "the map's zone list does not come through")
  eq(out[1].w, 160, "a whole-screen page is made instead")
  eq(out[1].h, 144, "...the size of the screen")
  eq(hex(out[1].colors[1]), "000000", "black paper")
  eq(hex(out[1].colors[4]), "ffffff", "white ink")
end

do
  io.write("the walk stops at whatever owns the frame\n")
  local ListMenu = engineClass("src.ui.ListMenu")
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  -- a text box over the map owns no palettes, so the map still owns the
  -- frame -- and the map is not a page
  local world = { sgbPalettes = true }
  local textbox = {}
  local zones = overworldZones()
  eq(theme.apply({ stack = { states = { world, textbox } } }, zones), zones,
    "an overlay with nothing to say does not make the overworld a page")
  eq(hex(zones[1].colors[1]), "ffefff", "...and nothing was written into it")

  -- the same overlay over a page leaves the page themed, which is what keeps
  -- a confirm box from flashing the OPTION screen back to white
  local list = setmetatable({ sgbPalettes = true }, ListMenu)
  local out = theme.apply({ stack = { states = { list, textbox } } },
                          mewmonZones())
  eq(hex(out[1].colors[1]), "000000",
    "but an overlay over a page is stepped over")

  -- a page under something that owns the frame ITSELF is not on screen
  local battle = { sgbPalettes = true }
  local under = overworldZones()
  eq(theme.apply({ stack = { states = { list, battle } } }, under), under,
    "and a page buried under a screen that owns the frame is not the frame")
end

do
  io.write("DARK proves the page is dark before it uses it\n")
  -- Reversing works because every SGB background palette darkest-ends in
  -- near-black.  A page that does not -- the suite's own screens open on the
  -- player's outfit ramp -- reverses into a washed pastel, which is a second
  -- light mode rather than a dark one.  So the reversal has to measure dark
  -- or the page falls back to plain black-on-white.
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  local pastel = { { 0xea, 0xf6, 0xea }, { 0xa8, 0xd0, 0xa8 },
                   { 0x6a, 0x9a, 0x6a }, { 0x8a, 0xb0, 0x8a } }
  local screen = { gen1wildTheme = "settings", sgbPalettes = true }
  local out = theme.apply({ stack = { states = { screen } } },
    { { colors = pastel, x = 0, y = 0, w = 160, h = 144 } })
  eq(hex(out[1].colors[1]), "000000",
    "a page whose darkest colour is not dark falls back to black paper")
  eq(hex(out[1].colors[4]), "ffffff", "and white ink")
end

do
  io.write("a menu box over the map is themed by its own rectangle\n")
  -- The bug this is for: START > OPTION said DARK and the START menu behind
  -- it was still white.  A menu box owns no palettes, so the engine hands the
  -- frame to the map underneath -- and the map is not a page, quite rightly,
  -- so the theme declined the whole frame and the menu with it.  A panel is
  -- themed by its rect and nothing else, which is what lets a white menu go
  -- black over a map that does not move.
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  -- src/ui/Menu.lua keeps its box in tx/ty/tw/th, in tiles, and computes it in
  -- Menu.new.  The START menu is the default: 10 tiles in, 10 wide.
  local world = { sgbPalettes = true }
  local start = { tx = 10, ty = 0, tw = 10, th = 12 }
  local zones = overworldZones()
  local out = theme.apply({ stack = { states = { world, start } } }, zones)

  eq(#out, 2, "the map's own zone, and one for the menu")
  eq(hex(out[1].colors[1]), "ffefff", "the map is not touched")
  eq(out[2].x, 80, "the panel starts where the box starts, in pixels")
  eq(out[2].y, 0, "...top edge")
  eq(out[2].w, 80, "and is as wide as the box")
  eq(out[2].h, 96, "...and as tall")
  eq(hex(out[2].colors[1]), "000000", "a dark menu is a black box")
  eq(hex(out[2].colors[4]), "ffffff", "with white type in it")

  -- and the caller's list is still the caller's list
  eq(#zones, 1, "the frame's own zone list was not written into")
end

do
  io.write("a panel is only ever an overlay\n")
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  -- A page that happens to carry a box of its own is themed as a PAGE.
  -- Painting its box again would be a second coat at best, and a box over its
  -- own content at worst.
  local page = { gen1wildTheme = "settings", sgbPalettes = true,
                 tx = 2, ty = 2, tw = 16, th = 12 }
  local out = theme.apply({ stack = { states = { page } } }, menuZones())
  eq(#out, 2, "the page is themed, and no panel is added for its own box")

  -- but a menu stacked ON that page still gets one
  local over = { tx = 0, ty = 0, tw = 8, th = 6 }
  local stacked = theme.apply({ stack = { states = { page, over } } },
                              menuZones())
  eq(#stacked, 3, "a box on top of a page is a panel")
  eq(stacked[3].w, 64, "...its own rectangle")

  -- a state with no box and no palettes contributes nothing either way
  local bare = {}
  local plain = theme.apply({ stack = { states = { page, bare } } },
                            menuZones())
  eq(#plain, 2, "and a state with no rectangle is not a panel")
end

do
  io.write("a screen with several boxes says where they are\n")
  local mod = fakeMod()
  local theme = themeOver(mod)
  theme.write("dark")

  -- The bag draws two windows over the map, so tx/ty/tw/th on the state
  -- cannot describe it.  A screen that knows better says so.
  local world = { sgbPalettes = true }
  local bag = {
    gen1wildThemePanels = function()
      return { { x = 0, y = 16, w = 96, h = 96 },
               { x = 96, y = 0, w = 64, h = 144 } }
    end,
  }
  local out = theme.apply({ stack = { states = { world, bag } } },
                          overworldZones())
  eq(#out, 3, "the map, and one zone per window")
  eq(out[2].w, 96, "the first window")
  eq(out[3].x, 96, "and the second")

  -- a screen whose panels raise must not take the frame down with it
  bag.gen1wildThemePanels = function() error("nope") end
  local survived = theme.apply({ stack = { states = { world, bag } } },
                               overworldZones())
  eq(#survived, 1, "a screen that raises simply contributes no panels")
end

do
  io.write("the matte is what a true-colour rectangle sits on\n")
  -- markTrueColor blits a rectangle RAW so a coloured icon keeps its colours.
  -- Raw means the white page under it stays white too, which is the white box
  -- behind every icon on a dark screen.  A screen paints this colour into the
  -- rectangle before it draws the art, and the box goes with the page.
  local mod = fakeMod()
  local theme = themeOver(mod)

  eq(hex(theme.matte()), "ffffff",
    "under LIGHT it is white, which is what every screen drew before this "
    .. "existed -- so a build with no theme pays nothing for the call")

  theme.write("dark")
  eq(hex(theme.matte()), "000000", "and under DARK it is the dark page")
end

do
  io.write("a theme that raises stands down instead of taking the frame\n")
  -- This hook runs on every frame of every screen, and it is the only thing
  -- in the bundle that does.  A theme is decoration: if it raises, the right
  -- outcome is the frame it was handed in the colours it already had.

  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)

  local mod = fakeMod()
  mod.files["modules/Only/main.lua"] = [[
    return function(mod)
      mod.options:define({
        { key = "enabled", type = "toggle", label = "ONLY", default = true },
      })
    end
  ]]
  Bundle.install(mod, { id = "gen1_wild_ui", menu_label = "GEN1WILD UI",
                        screen_id = "Gen1WildUI",
                        paired_bundle = "gen1_wild_qol" }, {
    { id = "only", dir = "Only", entry = "main.lua", label = "ONLY",
      enabledKey = "enabled", default = true, priority = 100 },
  })

  local wrap
  for _, hooked in ipairs(mod.hooked) do
    if hooked.name == "render.zones" then wrap = hooked.fn end
  end
  ok(wrap ~= nil, "render.zones is wrapped")

  -- a state whose themeZones raises is already handled; this is the harder
  -- case -- a stack that raises when it is walked at all
  local hostile = setmetatable({}, { __index = function() error("no") end })
  local zones = menuZones()
  local out
  ok(pcall(function()
    out = wrap(function(_, z) return z end, { stack = hostile }, zones)
  end), "a game the theme cannot read does not take the frame down")
  eq(out, zones, "and the frame is handed on exactly as it came")

  -- and it stays stood down rather than raising once per frame forever
  local second = wrap(function(_, z) return z end, { stack = hostile }, zones)
  eq(second, zones, "the second frame is handed on too")
end

do
  io.write("the theme is a row on the game's own OPTION screen\n")

  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)

  local mod = fakeMod()
  mod.files["modules/Only/main.lua"] = [[
    return function(mod)
      mod.options:define({
        { key = "enabled", type = "toggle", label = "ONLY", default = true },
      })
    end
  ]]
  local spec = { id = "gen1_wild_ui", menu_label = "GEN1WILD UI",
                 screen_id = "Gen1WildUI", paired_bundle = "gen1_wild_qol" }
  Bundle.install(mod, spec, {
    { id = "only", dir = "Only", entry = "main.lua", label = "ONLY",
      enabledKey = "enabled", default = true, priority = 100 },
  })

  local wrap
  for _, hooked in ipairs(mod.hooked) do
    if hooked.name == "ui.options.rows" then wrap = hooked.fn end
  end
  ok(wrap ~= nil, "ui.options.rows is wrapped")

  local rows = wrap(function(_, r) return r end, { save = { options = {} } }, {})
  local themeRow
  for _, row in ipairs(rows) do
    if row.id == "gen1wild_ui_theme" then themeRow = row end
  end
  ok(themeRow ~= nil, "and puts UI THEME on the OPTION screen")
  eq(themeRow and themeRow.label, "UI THEME", "under that name")
  eq(themeRow and themeRow.value(), "LIGHT", "starting on LIGHT")

  local game = { save = { options = {} } }
  themeRow.step(game, 1)
  eq(themeRow.value(), "DARK", "one press right is DARK")
  themeRow.step(game, 1)
  eq(themeRow.value(), "LIGHT", "and it wraps -- two values, not three")
  themeRow.step(game, -1)
  eq(themeRow.value(), "DARK", "left goes the other way")

  -- one row, not two: the other half of the suite may have added it already
  local twice = wrap(function(_, r) return r end, game, rows)
  local count = 0
  for _, row in ipairs(twice) do
    if row.id == "gen1wild_ui_theme" then count = count + 1 end
  end
  eq(count, 1, "a second pass adds no second row")
end

do
  io.write("the suite's own screens say they are ours\n")

  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)

  local mod = fakeMod()
  mod.files["modules/Only/main.lua"] = [[
    return function(mod)
      mod.options:define({
        { key = "enabled", type = "toggle", label = "ONLY", default = true },
      })
    end
  ]]
  local spec = {
    id = "gen1_wild_ui", menu_label = "GEN1WILD UI", screen_id = "Gen1WildUI",
    paired_bundle = "gen1_wild_qol",
    groups = {
      { id = "battle", label = "BATTLES" },
      { id = "items", label = "ITEMS" },
    },
  }
  Bundle.install(mod, spec, {
    { id = "only", dir = "Only", entry = "main.lua", label = "ONLY",
      group = "battle", enabledKey = "enabled", default = true,
      priority = 100 },
  })

  local factory = mod.screens["Gen1WildUI"]
  ok(factory ~= nil, "the suite's root screen is registered")
  local screen = factory.new({ save = { options = {} } })
  ok(screen.gen1wildTheme ~= nil,
    "and marks itself as one of ours -- it opens on MEWMON, not on the "
    .. "greys, so nothing else would recognise it as a page")

  -- and the marker alone is enough: the theme takes any state that carries
  -- it, without a table of names to keep current
  local theme = themeOver(fakeMod())
  theme.write("dark")
  local out = theme.apply({ stack = { states = { screen } } }, menuZones())
  eq(hex(out[1].colors[1]), "000000", "so a screen that says so is themed")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
