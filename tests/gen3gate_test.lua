-- Headless coverage of the Gen 3 half of the generation gate in
-- runtime/bundle.lua.
--
-- FireRed, LeafGreen and Emerald are opt IN where Gold was opt out: a feature
-- runs there only when features.lua says `gen3`, because nothing written
-- against Red's screens has a GBA screen to draw on and the Gen 1 facades
-- cover FireRed thinly and Emerald not at all.  So the assertions here are:
--
--   * a feature that does not say `gen3` is not READ on a Gen 3 boot -- its
--     requires would put "requires src.battle.BattleState, which a Gen 3 game
--     never runs" on the error feed the player sees in MODS;
--   * `gen3 = true` runs the feature's own entry, and `gen3 = { entry = ... }`
--     runs the named one INSTEAD, with any other field it gives replacing the
--     feature's own for that boot;
--   * the bundle's own menu is not installed: its screens have no Gen 3
--     target, and its MODS > OPTIONS route would push a Gen 1 screen into the
--     GBA manager;
--   * and none of that leaks back: on Red and Gold a feature that also says
--     `gen3` still runs its ordinary entry.
--
-- Run:  luajit tests/gen3gate_test.lua

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

package.loaded["src.mods.ManagerState"] = { openOptions = function() end }

-- The engine's own generation probe, which is the only thing the gate reads.
local generation = 1
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  get = function()
    return ({ "red", "gold", "firered" })[generation] or "red"
  end,
  isYellow = function() return false end,
}

-- Gold's chrome, for the Gen 2 theme arm the bundle loads instead of the Gen 1
-- one.  Only the field it rewrites is needed.
package.loaded["src.ui.gen2.Chrome"] = {
  DEFAULT_BOX_PALETTE = {
    { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
  },
}

local SPEC = { id = "gen1_wild_ui", menu_label = "GEN1WILD UI",
               screen_id = "Gen1WildUI", paired_bundle = "gen1_wild_qol" }

-- Four features: one for Red and Gold only, one that runs unchanged on Gen 3,
-- one with a Gen 3 entry of its own and an adapter it drops there, and one
-- gen2_only feature that does not say gen3.  Each entry records that it RAN
-- under its own name, and the fake mod records every file the loader READ.
local function featuresFor()
  return {
    { id = "classic", dir = "Classic", entry = "main.lua", label = "CLASSIC",
      enabledKey = "enabled", default = true, priority = 100 },
    { id = "same", dir = "Same", entry = "main.lua", label = "SAME",
      enabledKey = "enabled", default = true, priority = 100, gen3 = true },
    { id = "own", dir = "Own", entry = "main.lua", label = "OWN",
      enabledKey = "enabled", default = true, priority = 100,
      adapter = "own", gen3 = { entry = "gen3.lua", adapter = false } },
    { id = "gold", dir = "Gold", entry = "main.lua", label = "GOLD",
      enabledKey = "enabled", default = true, priority = 100,
      gen2_only = true },
  }
end

local function entry(name)
  return ([[
    return function(mod)
      mod.options:define({
        { key = "enabled", type = "toggle", label = "X", default = true },
      })
      _G.__gate_ran = _G.__gate_ran or {}
      _G.__gate_ran[%q] = true
    end
  ]]):format(name)
end

local function modWithFeatures()
  local mod = fakeMod()
  local reads = {}
  local realRead = mod.read
  mod.read = function(selfMod, path)
    reads[path] = (reads[path] or 0) + 1
    return realRead(selfMod, path)
  end
  for _, name in ipairs({ "Classic", "Same", "Own", "Gold" }) do
    mod.files["modules/" .. name .. "/main.lua"] = entry(name)
  end
  mod.files["modules/Own/gen3.lua"] = entry("Own/gen3")
  mod.files["adapters/own.lua"] = [[
    return { install = function() _G.__gate_ran["adapter"] = true end }
  ]]
  return mod, reads
end

local function installAt(gen)
  generation = gen
  _G.__gate_ran = {}
  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)
  local mod, reads = modWithFeatures()
  Bundle.install(mod, SPEC, featuresFor())
  return mod, reads, _G.__gate_ran, Bundle
end

local function rowsOf(mod)
  local byKey = {}
  for _, row in ipairs(mod.defined or {}) do byKey[row.key] = row end
  return byKey
end

local function hookNames(mod)
  local names = {}
  for _, hooked in ipairs(mod.hooked) do names[hooked.name] = true end
  return names
end

-- ------------------------------------------------------------- on Gen 3

do
  io.write("on FireRed\n")
  local mod, reads, ran = installAt(3)

  eq(ran.Classic, nil, "a feature that does not say gen3 does not run")
  eq(reads["modules/Classic/main.lua"], nil,
     "and its chunk is never READ, so nothing it requires reaches the "
     .. "boot error feed")
  eq(ran.Gold, nil, "nor does a gen2_only one")
  ok(ran.Same, "gen3 = true runs the feature's own entry")
  ok(ran["Own/gen3"], "gen3 = { entry = ... } runs the Gen 3 entry")
  eq(ran.Own, nil, "and NOT the ordinary one")
  eq(reads["modules/Own/main.lua"], nil, "which is never read")
  eq(ran.adapter, nil, "adapter = false drops the adapter for this boot")

  eq(mod.exports.installed.classic, nil,
     "the absent feature is not reported at all")
  eq(mod.exports.installed.same, true, "SAME is reported installed")
  eq(mod.exports.installed.own, true, "so is OWN")

  local rows = rowsOf(mod)
  eq(rows.classic_enabled, nil, "no master row for a feature that is not here")
  ok(rows.same_enabled and rows.own_enabled,
     "and one each for the two that are -- FireRed's MOD OPTIONS lists them")

  eq(next(mod.screens), nil,
     "no screens: the registry has no Gen 3 target")
  local names = hookNames(mod)
  eq(names["ui.options.rows"], nil, "no OPTION-screen door")
  eq(names["ui.start_menu.items"], nil,
     "and no START-menu reroute: on Gen 3 MODS opens FireRed's own manager")
  -- The route is laid when mods.loaded fires; fire it and look.
  local ManagerState = { openOptions = function() return "the manager's own" end }
  package.loaded["src.mods.ManagerState"] = ManagerState
  mod.events.emit(nil, "mods.loaded", {})
  eq(rawget(ManagerState, "__modOptionScreenRoutes"), nil,
     "and no MODS > OPTIONS route, which would push a Gen 1 screen into the "
     .. "GBA manager")
  eq(ManagerState.openOptions(), "the manager's own",
     "so the manager opens its own options list")
  eq(names["render.zones"], nil, "no Gen 1 theme")
  eq(names["core.update"], nil, "and no Gen 2 one")
end

-- -------------------------------------------------------- Red and Gold

do
  io.write("on Red and Gold the gen3 field changes nothing\n")
  local _, reads, ran = installAt(1)
  ok(ran.Classic and ran.Same and ran.Own,
     "on Red all three non-Gold features run their ordinary entry")
  eq(ran["Own/gen3"], nil, "the Gen 3 entry does not")
  eq(reads["modules/Own/gen3.lua"], nil, "and is not read")
  ok(ran.adapter, "and the adapter is still installed")

  local _, _, ranGold = installAt(2)
  ok(ranGold.Classic and ranGold.Same and ranGold.Own and ranGold.Gold,
     "on Gold all four run")
  eq(ranGold["Own/gen3"], nil, "and the Gen 3 entry does not")
end

-- ---------------------------------------------- the API's own generation

do
  io.write("a host whose GameVersion cannot say\n")
  -- An engine GameVersion that cannot answer leaves the mod API's own
  -- `generation` to decide.
  local saved = package.loaded["src.core.GameVersion"]
  package.loaded["src.core.GameVersion"] = {}
  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)
  _G.__gate_ran = {}
  local mod = modWithFeatures()
  mod.generation = 3
  Bundle.install(mod, SPEC, featuresFor())
  ok(_G.__gate_ran["Own/gen3"] and not _G.__gate_ran.Classic,
     "mod.generation = 3 is a Gen 3 boot")
  package.loaded["src.core.GameVersion"] = saved
end

io.write(("gen3 gate: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
