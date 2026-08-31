-- The editor's SELECT page, and when there is one at all.
--
-- The SELECT context arranges a menu this mod does not build: Gen1WildQOL's
-- EASY HM USE does, and hands the rows round through a registry this mod
-- joins at mods.loaded.  On a build without that mod there is no such menu --
-- not an empty one, an absent one -- and the page was still in the cycle.
--
-- What that looked like from the player's chair is why this test exists.
-- LEFT or RIGHT off the PC page landed on a page reading NOTHING TO ARRANGE
-- and PRESS SELECT FIRST; pressing SELECT there did nothing, because the
-- empty page answers only the keys that leave it; and pressing SELECT in the
-- overworld did nothing either, because the mod that puts a menu there was
-- not installed.  Two dead keys and a page that cannot be filled reads as
-- "the menu manager broke", and was reported as exactly that.
--
-- So: no registry, no page.  Join the registry and the page is there, with
-- the catalog's rows on it before that menu has ever been opened.
--
-- Run:  luajit tests/selectpage_test.lua

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
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

-- Enough engine for the manager to install: it registers a screen, defines
-- options, wraps two hooks and asks for one event.  None of that draws.
package.loaded["src.render.PaletteFX"] = { markTrueColor = function() end }

local function fakeMod()
  local self
  self = {
    id = "gen1_wild_ui",
    path = ".",
    stored = {}, saved = {}, cached = {},
    screens = {}, events_on = {}, logged = {},
    found = {},
  }

  function self:read(path)
    return readFile("modules/Gen1MenuManager/" .. path)
  end

  self.options = {
    define = function() end,
    get = function(_, key)
      local value = self.stored[key]
      if value == nil then return true end
      return value
    end,
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
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    self.log[level] = function(_, format, ...)
      self.logged[#self.logged + 1] = { level = level,
        text = select("#", ...) > 0 and format:format(...) or format }
    end
  end
  self.hooks = { wrap = function() end }
  self.events = {
    once = function(_, name, fn)
      self.events_on[#self.events_on + 1] = { name = name, fn = fn }
    end,
    on = function() end,
    emit = function(_, name)
      for _, entry in ipairs(self.events_on) do
        if entry.name == name then entry.fn() end
      end
    end,
  }
  self.content = {
    screens = { register = function(_, id, factory) self.screens[id] = factory end },
  }
  self.ui = {
    push = function() end,
    insertBefore = function(rows, _anchor, row) rows[#rows + 1] = row; return rows end,
    Font = { split = function(text) return { text } end },
    Theme = {},
  }
  self.find = function(name) return self.found[name] end
  self.world = { game = nil }
  return self
end

local function install(mod)
  local source = assert(readFile("modules/Gen1MenuManager/main.lua"))
  local chunk = assert(load(source, "@modules/Gen1MenuManager/main.lua"))
  chunk()(mod)
  mod.events:emit("mods.loaded")
  return mod.screens["Gen1MenuManagerEditor"]
end

local function fakeGame()
  return {
    input = { wasPressed = function() return false end },
    data = { items = {}, moves = {} },
    stack = {},
    save = { player = { name = "RED" } },
  }
end

-- The registry EASY HM USE publishes, reduced to the two functions the
-- manager actually calls.
local function fieldMenuHandle(catalog)
  return {
    id = "FieldMenu",
    exports = {
      fieldMenu = {
        provide = function() return function() end end,
        catalog = catalog and function()
          return { { id = "fly", label = "FLY" },
                   { id = "cancel", label = "CANCEL" } }
        end or nil,
      },
    },
  }
end

-- ------------------------------------------------ no registry, no page

do
  io.write("without the field menu there is no SELECT page\n")
  local mod = fakeMod()
  local factory = install(mod)
  ok(factory ~= nil, "the editor is registered anyway")

  local screen = factory.new(fakeGame(), {})
  eq(#screen.keys, 2, "the cycle is START and PC only")
  ok(screen.keys[1] == "start" and screen.keys[2] == "pc",
     "and in that order")

  -- The row that opens the editor on the field menu cannot exist here, but a
  -- saved layout or a stale caller could still name the context.
  local asked = factory.new(fakeGame(), { context = "select" })
  eq(asked.key, "start", "asking for the dead page lands on START")

  local silent = true
  for _, entry in ipairs(mod.logged) do
    if entry.text:find("SELECT") then silent = false end
  end
  ok(silent, "and nothing is logged about a menu the player does not have")
end

-- ------------------------------------------------ with the registry

do
  io.write("with the field menu the page is there before it is opened\n")
  local mod = fakeMod()
  mod.found["FieldMenu"] = fieldMenuHandle(true)
  local factory = install(mod)

  local screen = factory.new(fakeGame(), { context = "select" })
  eq(screen.key, "select", "the editor opens on the page it was asked for")
  eq(#screen.keys, 3, "and the cycle has all three menus")

  -- The catalog is the whole point: these rows are arrangeable before that
  -- menu has ever been on screen.
  -- Two, not three: the manager's own MENU MGR row is declared to the real
  -- registry through provide(), which folds it into the catalog it hands
  -- back.  This stub answers with its own list only, so what is counted here
  -- is exactly what the catalog offered.
  eq(#screen.entries, 2, "the catalog's rows are on the page")
  local labels = {}
  for _, entry in ipairs(screen.entries) do labels[entry.label] = true end
  ok(labels["FLY"], "FLY is listed without standing outdoors")
  ok(labels["CANCEL"], "so is CANCEL")
  ok(screen.entries[1].absent, "marked as not on offer where the player is")
end

-- ------------------------------------------------ a registry without a catalog

do
  io.write("an older field menu still gets its page\n")
  local mod = fakeMod()
  mod.found["FieldMenu"] = fieldMenuHandle(false)
  local factory = install(mod)

  local screen = factory.new(fakeGame(), { context = "select" })
  eq(screen.key, "select", "joined is joined, catalog or not")
  eq(#screen.keys, 3, "the page is in the cycle")
  -- Nothing to list until the menu has been opened once, which is what
  -- PRESS SELECT FIRST is for -- and here it is true.
  eq(#screen.entries, 0, "and it is empty until that menu is built")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
