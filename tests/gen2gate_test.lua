-- Headless coverage of the generation gate in runtime/bundle.lua.
--
-- The gate is four lines and it carries the whole Gen 2 story, so it is worth
-- a test of its own: a feature marked `gen1_only` must not be installed on a
-- Gold boot, and -- the half that actually matters -- its entry chunk must
-- never be READ there.
--
-- That second assertion is the one with consequences.  Eight features in the
-- visual half and three in the quality-of-life half are Gen 1 only, and
-- several of them reach members Gold does not have (`BattleState.newWild`,
-- `PartyMenu.drawIcon`, `PartyMenu.sgbPalettes`, `OverworldState.drawWorld`)
-- or require modules Gold never runs.  A require for a Gen 1-only module the
-- adapter does not serve puts a line on the boot error feed the player sees
-- in MODS (src/mods/Loader.lua:179-191) -- so "not installed" is not enough
-- on its own.  The chunk must not run at all, and the gate is upstream of
-- `loader.chunk` precisely so that it does not.
--
-- `modkit gen2check` cannot see any of this: it is a static scan of every
-- file in the package and knows nothing about features.lua.  It reports those
-- members as findings, and this is the test that says why that is expected.
--
-- Run:  luajit tests/gen2gate_test.lua

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
  get = function() return generation == 2 and "gold" or "red" end,
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

-- Three features: one for both generations, one Gen 1 only, one Gen 2 only.
-- Each records that its chunk RAN, and the fake mod records every file the
-- loader asked to READ -- which is the assertion with teeth.
local function featuresFor()
  return {
    { id = "both", dir = "Both", entry = "main.lua", label = "BOTH",
      enabledKey = "enabled", default = true, priority = 100 },
    { id = "onlyone", dir = "OnlyOne", entry = "main.lua", label = "ONLY ONE",
      enabledKey = "enabled", default = true, priority = 100,
      gen1_only = true },
    { id = "onlytwo", dir = "OnlyTwo", entry = "main.lua", label = "ONLY TWO",
      enabledKey = "enabled", default = true, priority = 100,
      gen2_only = true },
  }
end

local function modWithFeatures()
  local mod = fakeMod()
  local reads = {}
  local realRead = mod.read
  mod.read = function(selfMod, path)
    reads[path] = (reads[path] or 0) + 1
    return realRead(selfMod, path)
  end
  for _, name in ipairs({ "Both", "OnlyOne", "OnlyTwo" }) do
    mod.files["modules/" .. name .. "/main.lua"] = ([[
      return function(mod)
        mod.options:define({
          { key = "enabled", type = "toggle", label = "%s", default = true },
        })
        _G.__gate_ran = _G.__gate_ran or {}
        _G.__gate_ran[%q] = true
      end
    ]]):format(name:upper(), name)
  end
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
  return mod, reads, _G.__gate_ran
end

-- ------------------------------------------------------------- on Gen 1

do
  io.write("the generation gate\n")
  local mod, reads, ran = installAt(1)

  ok(ran.Both, "a feature for both generations runs on Red")
  ok(ran.OnlyOne, "and so does a gen1_only one")
  eq(ran.OnlyTwo, nil, "a gen2_only feature does not")
  eq(reads["modules/OnlyTwo/main.lua"], nil,
     "and its chunk is never even read")

  eq(mod.exports.installed.both, true, "BOTH is reported installed")
  eq(mod.exports.installed.onlyone, true, "so is ONLY ONE")
  eq(mod.exports.installed.onlytwo, nil,
     "and ONLY TWO is not reported at all -- it is not a feature of this boot")

  local byKey = {}
  for _, row in ipairs(mod.defined or {}) do byKey[row.key] = row end
  ok(byKey.onlyone_enabled, "a gen1_only feature has its master row here")
  eq(byKey.onlytwo_enabled, nil,
     "and a gen2_only one has no row: a switch that cannot do anything is "
     .. "worse than a missing one")
end

-- ------------------------------------------------------------- on Gold

do
  local mod, reads, ran = installAt(2)

  ok(ran.Both, "a feature for both generations runs on Gold")
  ok(ran.OnlyTwo, "and so does a gen2_only one")
  eq(ran.OnlyOne, nil, "a gen1_only feature does not")

  -- The one that matters.
  eq(reads["modules/OnlyOne/main.lua"], nil,
     "and its chunk is NEVER READ -- so its requires never run, and nothing "
     .. "it reaches for can land on the boot error feed")

  eq(mod.exports.installed.onlyone, nil, "it is not reported at all")
  eq(mod.exports.installed.both, true, "the shared feature still installs")

  local byKey = {}
  for _, row in ipairs(mod.defined or {}) do byKey[row.key] = row end
  eq(byKey.onlyone_enabled, nil, "a gen1_only feature has no row on Gold")
  ok(byKey.onlytwo_enabled, "and a gen2_only one does")
end

-- --------------------------------------------------------- which theme

-- Only the visual half carries a theme; the quality-of-life half runs the same
-- runtime with no theme.lua beside it, and this file is shared between them.
if readFile("runtime/theme.lua") then
  -- The bundle picks the theme by generation, and the two are different
  -- mechanisms rather than two settings of one -- so picking the wrong one is
  -- a theme that silently never fires.  Checked through what each arm leaves
  -- on the mod: the Gen 2 arm rides `core.update`, the Gen 1 arm rides
  -- `render.zones`.
  generation = 2
  local Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)
  local function hookNames(mod)
    local names = {}
    for _, entry in ipairs(mod.hooked) do names[entry.name] = true end
    return names
  end

  local mod = modWithFeatures()
  Bundle.install(mod, SPEC, {})
  local gold = hookNames(mod)
  ok(gold["core.update"],
     "on Gold the theme rides core.update, which runs before the frame draws")
  eq(gold["render.zones"], nil,
     "and NOT render.zones, which on Gold fires after the page is painted "
     .. "and carries no zones to reverse")

  generation = 1
  Bundle = load_("runtime/bundle.lua", function(name)
    return load_("runtime/" .. name .. ".lua")
  end)
  local mod1 = modWithFeatures()
  Bundle.install(mod1, SPEC, {})
  local red = hookNames(mod1)
  ok(red["render.zones"],
     "on Red the theme rides render.zones, the SGB palette pass")
  eq(red["core.update"], nil, "and not core.update")
end

io.write(("gen2 gate: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
