-- Headless coverage of the party menu's Gold arm (modules/Gen1Party/main.lua).
--
-- Gold has the same bug this mod was written for: `PartyMenu:drawIcon` colours
-- every row out of `self.palettes.partyMenu[1]`, so six mons share one palette
-- (src/ui/gen2/PartyMenu.lua:869-873).  The arm hands `drawIcon` a `palettes`
-- whose `partyMenu[1]` is THIS mon's pair, for the length of one call.
--
-- What a headless harness can check is exactly the contract of that swap:
-- which palette the cart's own drawIcon ends up reading, that everything else
-- on `palettes` is still reachable while it does, that `self.palettes` is the
-- caller's own table again afterwards -- on the raising path too -- and that
-- the Gen 1 screen is never built here.
--
-- Run:  luajit tests/partygen2_test.lua

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

-- Gold's party menu, reduced to the one method the arm wraps.  `seen` records
-- what the cart's own drawIcon would have coloured with.
local PartyMenu = {}
local seen

PartyMenu.drawIcon = function(self, mon, px, py)
  local pals = self.palettes and self.palettes.partyMenu
  seen = {
    colors = pals and pals[1] or nil,
    -- the rest of `palettes` has to still be reachable from inside the call
    hpBar = self.palettes and self.palettes.hpBar or nil,
    mon = mon, px = px, py = py,
  }
end

local BASE_DRAW = PartyMenu.drawIcon

-- Gold's palette helper.  Only monColors is reached.
local CHARMANDER = { { 255, 255, 255 }, { 222, 110, 0 }, { 148, 58, 0 },
                     { 0, 0, 0 } }
local SHINY_CHARMANDER = { { 255, 255, 255 }, { 240, 200, 0 },
                           { 160, 120, 0 }, { 0, 0, 0 } }

local Palettes = {
  monColors = function(data, species, shiny)
    if species ~= "CHARMANDER" then return nil end
    return shiny and SHINY_CHARMANDER or CHARMANDER
  end,
}

local generation = 2

package.loaded["src.ui.gen2.PartyMenu"] = PartyMenu
package.loaded["src.world.gen2.Palettes"] = Palettes
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  get = function() return generation == 2 and "gold" or "red" end,
  isYellow = function() return false end,
}
package.loaded["src.core.Strings"] = setmetatable({}, {
  __call = function(_, text) return text end,
})

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local install = chunkOf("modules/Gen1Party/main.lua")

local function fakeMod(stored)
  local self
  self = {
    id = "gen1_wild_ui",
    path = ".",
    defined = nil,
    warnings = 0,
    read = function(_, name)
      -- WHICH siblings each arm asks for, by name.  The Gen 1 arm asks for
      -- chrome.lua and screen.lua; the Gold arm asks for gen2panel.lua and
      -- must never reach either of the other two -- they read
      -- PartyMenu.drawIcon and .sgbPalettes off the Gen 1 module, which are
      -- nil on a Gold boot.  Every read answers nil here, which is also how
      -- the degrade is exercised: a panel that will not load must leave the
      -- mod installed rather than take the boot down.
      self.readAsked = (self.readAsked or 0) + 1
      self.reads = self.reads or {}
      self.reads[name] = (self.reads[name] or 0) + 1
      return nil, "not in this test"
    end,
    log = {
      info = function() end,
      warn = function() self.warnings = self.warnings + 1 end,
      error = function() end,
    },
    options = {
      define = function(_, schema) self.defined = schema end,
      get = function(_, key) return stored[key] end,
      set = function(_, key, value) stored[key] = value end,
    },
    hooks = { wrapped = {}, wrap = function(h, name, fn)
      h.wrapped[name] = fn
    end },
    content = { screens = { registered = {}, register = function(s, id, v)
      s.registered[id] = v
    end } },
  }
  self.hooks.wrapped = {}
  self.content.screens.registered = {}
  return self
end

local function screenWith(palettes)
  return { palettes = palettes }
end

local function paletteName(colors)
  if colors == CHARMANDER then return "CHARMANDER" end
  if colors == SHINY_CHARMANDER then return "SHINY" end
  return tostring(colors)
end

-- ------------------------------------------------------------ the schema

do
  PartyMenu.drawIcon = BASE_DRAW
  PartyMenu.__gen1PartyGen2 = nil
  local stored = {}
  local mod = fakeMod(stored)
  install(mod)

  local keys = {}
  for _, row in ipairs(mod.defined or {}) do keys[row.key] = true end
  ok(keys.species_colours, "SPECIES COLOURS is offered on Gold")
  ok(keys.start_says_party, "so is START: PARTY -- Gold's start menu says "
     .. "POKeMON too, and ui.start_menu.items is raised there")
  ok(keys.ruled_icons,
     "RULED ICONS is offered on Gold as of 0.32.28: the frame puts a rule "
     .. "between the icons and the names there too, and off puts the "
     .. "engine's own icon slide back")
  -- This row used to be fenced off from Gold, on the reasoning that moving a
  -- member there is MOVE POKéMON in the PC rather than a row on this popup.
  -- That reading was wrong: `GetMonSubmenuItems` puts SWITCH on the popup on
  -- Gold too (src/ui/gen2/PartyMenu.lua:252), and A on it runs `beginSwitch`.
  -- So the row has a switch to change after all, and as of 0.32.89
  -- gen2carry.lua changes it -- see tests/partycarry_gen2_test.lua.
  ok(keys.live_move,
     "MOVE NOT SWITCH is offered on Gold: its popup has a SWITCH row too")

  eq(next(mod.content.screens.registered), nil,
     "no screen is registered: the Gold arm replaces one METHOD on the "
     .. "cart's party list, not the screen")
  eq((mod.reads or {})["gen2panel.lua"], 1,
     "the Gold frame is read there")
  eq((mod.reads or {})["gen2carry.lua"], 1,
     "...and so is the carry, as of 0.32.89")
  eq((mod.reads or {})["screen.lua"], nil,
     "the Gen 1 screen is never even READ on Gold -- it reaches "
     .. "PartyMenu.drawIcon and .sgbPalettes, which are nil there")
  eq((mod.reads or {})["chrome.lua"], nil, "and neither is its drawing kit")
  ok(type(mod.hooks.wrapped["ui.start_menu.items"]) == "function",
     "the START menu row is still installed, because that hook is raised on "
     .. "both generations")
end

-- ------------------------------------------------------- the substitution

do
  PartyMenu.drawIcon = BASE_DRAW
  PartyMenu.__gen1PartyGen2 = nil
  local stored = { species_colours = true }
  local mod = fakeMod(stored)
  install(mod)

  ok(PartyMenu.drawIcon ~= BASE_DRAW, "drawIcon is wrapped")

  local partyPalette = { { 9, 9, 9 }, { 9, 9, 9 }, { 9, 9, 9 }, { 9, 9, 9 } }
  local hpBar = { good = "green" }
  local palettes = { partyMenu = { partyPalette }, hpBar = hpBar }
  local screen = screenWith(palettes)

  seen = nil
  PartyMenu.drawIcon(screen, { species = "CHARMANDER" }, 8, 4)
  eq(paletteName(seen.colors), "CHARMANDER",
     "a CHARMANDER is coloured with CHARMANDER's own pair, not the party's one")
  eq(seen.hpBar, hpBar,
     "and the rest of `palettes` is still reachable inside the call -- the "
     .. "shadow is __index'd onto the real table, not a copy of one key")
  eq(seen.px, 8, "the cart's own x is passed through")
  eq(seen.py, 4, "and its y")
  ok(rawequal(screen.palettes, palettes),
     "afterwards `self.palettes` is the caller's own table again")

  seen = nil
  PartyMenu.drawIcon(screen, { species = "CHARMANDER", shiny = true }, 0, 0)
  eq(paletteName(seen.colors), "SHINY", "a shiny takes the shiny pair")

  -- An EGG, and anything else the table has no row for, answers nil -- and
  -- nil is the RIGHT answer rather than a fallback: the cart draws every egg
  -- in the party palette and there is no egg colour to prefer over it.
  seen = nil
  PartyMenu.drawIcon(screen, { species = "EGG" }, 0, 0)
  eq(seen.colors, partyPalette, "an EGG keeps the cart's own party palette")

  seen = nil
  PartyMenu.drawIcon(screen, nil, 0, 0)
  eq(seen.colors, partyPalette, "so does an empty slot")

  -- Off is the cart exactly.
  stored.species_colours = false
  seen = nil
  PartyMenu.drawIcon(screen, { species = "CHARMANDER" }, 0, 0)
  eq(seen.colors, partyPalette,
     "OFF is the cart exactly: drawIcon reads the palettes it always read")
end

-- ------------------------------------------------------------ put back

do
  -- The cart's own drawIcon raising mid-paint is the case that decides
  -- whether `self.palettes` is left holding the shadow for the whole rest of
  -- the screen.  Wrapped around a drawIcon that always raises, so the put-back
  -- is the only thing under test.
  local exploding = { drawIcon = function() error("boom", 0) end }
  package.loaded["src.ui.gen2.PartyMenu"] = exploding
  install(fakeMod({ species_colours = true }))

  local palettes = { partyMenu = { { { 1, 1, 1 } } } }
  local screen = screenWith(palettes)

  local okCall = pcall(exploding.drawIcon, screen, { species = "CHARMANDER" },
                       0, 0)
  ok(not okCall, "a raising drawIcon still raises -- it is not swallowed")
  ok(rawequal(screen.palettes, palettes),
     "but `self.palettes` is put back first, so the rest of the screen is "
     .. "not left drawing through the shadow")

  package.loaded["src.ui.gen2.PartyMenu"] = PartyMenu
end

-- --------------------------------------------------------- idempotence

do
  PartyMenu.drawIcon = BASE_DRAW
  PartyMenu.__gen1PartyGen2 = nil
  local mod = fakeMod({ species_colours = true })
  install(mod)
  local once = PartyMenu.drawIcon
  install(fakeMod({ species_colours = true }))
  ok(rawequal(PartyMenu.drawIcon, once),
     "installing twice -- a hot reload -- does not wrap the wrapper, which "
     .. "would substitute twice and put back the wrong table")
end

-- ------------------------------------------------------------- Gen 1

do
  generation = 1
  PartyMenu.drawIcon = BASE_DRAW
  PartyMenu.__gen1PartyGen2 = nil
  local mod = fakeMod({})
  -- The Gen 1 arm loads its two siblings through mod:read, which this harness
  -- refuses -- so it raises, and raising is the point: it proves the Gen 1
  -- path was taken rather than the Gold one.
  local okRun = pcall(install, mod)
  ok(not okRun, "on Gen 1 the screen is built, and a missing sibling raises")
  ok((mod.readAsked or 0) > 0, "having actually asked for chrome.lua")
  ok(rawequal(PartyMenu.drawIcon, BASE_DRAW),
     "and Gold's drawIcon is untouched on a Gen 1 boot")

  local keys = {}
  for _, row in ipairs(mod.defined or {}) do keys[row.key] = true end
  ok(keys.ruled_icons and keys.live_move,
     "with all four rows back, because the screen they configure is there")
  generation = 2
end

io.write(("party gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
