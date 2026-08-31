-- Headless coverage of the party screen's side of UI THEME.
--
-- Two things, and both are geometry, which is exactly what a headless harness
-- can check: that the screen marks itself as one the theme should recognise,
-- and that the zones it returns for itself -- a species palette on each
-- Pokemon's icon cell, an HP bar palette on the line under it -- still land on
-- the tile rows they are meant to.  Those are the zones DARK reverses and the
-- ones a matte has to sit under.
--
-- Run:  luajit tests/partytheme_test.lua

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

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

love = {
  graphics = {
    setColor = function() end,
    rectangle = function() end,
    circle = function() end,
    push = function() end, pop = function() end,
    setScissor = function() end,
  },
}

local function strings(text, ...)
  if select("#", ...) > 0 then return (tostring(text):format(...)) end
  return text
end

package.preload["src.core.Strings"] = function() return strings end
package.preload["src.render.Font"] = function()
  return { draw = function() end, drawCode = function() end,
           drawBox = function() end,
           width = function(t) return #tostring(t) * 8 end }
end
package.preload["src.render.HudTiles"] = function() return {} end
package.preload["src.pokemon.Sprites"] = function()
  return { iconPath = function(_, _, path) return path end }
end
package.preload["src.battle.Status"] = function()
  return { label = function() return nil end }
end
package.preload["src.ui.Theme"] = function()
  return { cursor = 0xED, cursorHollow = 0xEC, moreArrow = 0xEE }
end
package.preload["src.render.Assets"] = function()
  return { imageData = function() error("no assets in the harness") end }
end

-- The species palettes the screen asks for, in the shape PaletteFX returns:
-- an off-white paper, the species' light and dark, then black.
local MONPAL = {
  BULBASAUR = { { 255, 239, 255 }, { 0x63, 0xc8, 0x4a },
                { 0x21, 0x73, 0x21 }, { 0, 0, 0 } },
  CHARMANDER = { { 255, 239, 255 }, { 0xf8, 0x68, 0x20 },
                 { 0xb0, 0x28, 0x28 }, { 0, 0, 0 } },
}

package.preload["src.render.PaletteFX"] = function()
  return {
    GRAYS = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 },
              { 0, 0, 0 } },
    whole = function(colors)
      return { colors = colors, x = 0, y = 0, w = 160, h = 144 }
    end,
    -- tile coordinates, inclusive, the way the engine addresses a zone
    zone = function(colors, tx1, ty1, tx2, ty2)
      return { colors = colors, tx1 = tx1, ty1 = ty1, tx2 = tx2, ty2 = ty2 }
    end,
    wholeNamed = function() return nil end,
    pal = function(_, name)
      if name == "GREENBAR" then
        return { { 255, 239, 255 }, { 0x31, 0xa2, 0x31 },
                 { 0x18, 0x51, 0x18 }, { 0, 0, 0 } }
      end
      return nil
    end,
    monPal = function(_, species) return MONPAL[species] end,
    barPalName = function() return "GREENBAR" end,
    markTrueColor = function() end,
  }
end

-- The vanilla party menu, as much of it as the factory touches: a constructor
-- that hands back an instance, and the three methods it replaces.
package.preload["src.ui.PartyMenu"] = function()
  local M = {}
  M.__index = M
  M.isOpaque = true
  function M.new(game, opts)
    return setmetatable({ game = game, index = 1,
                          party = (opts or {}).party }, M)
  end
  function M:sgbPalettes() return nil end
  function M:draw() end
  function M:update() end
  M.drawIcon = function() end
  return M
end

-- ------- the mod facade and the drawing kit

local options = { species_colours = true, ruled_icons = true,
                  live_move = true }
local mod = {
  options = { get = function(_, key) return options[key] end },
  log = { warn = function() end, info = function() end },
  cache = {},
}

local C = chunkOf("modules/Gen1Party/chrome.lua")(mod)
C.option = function(key, fallback)
  local value = options[key]
  if value == nil then return fallback end
  return value
end

local factory = chunkOf("modules/Gen1Party/screen.lua")(mod, C)
ok(type(factory) == "table" and type(factory.new) == "function",
   "the party screen builds")

-- ------- a party to look at

local PARTY = {
  { species = "BULBASAUR", hp = 20, stats = { hp = 20 } },
  { species = "CHARMANDER", hp = 5, stats = { hp = 20 } },
}
local game = { data = {}, save = { party = PARTY } }

-- ---------------------------------------------------------------- the tests

io.write("the party screen says it is one of ours\n")
do
  local menu = factory.new(game, {})
  ok(menu.gen1wildTheme ~= nil,
     "the instance marks itself, so UI THEME finds it without matching the "
     .. "engine's class")
end

io.write("and its icons still claim their own cells\n")
do
  -- The screen's own zones are what the theme leaves alone: a Pokemon's icon
  -- keeps its species palette and the HP bar keeps its green.  0.5.0 put a
  -- coloured card under each of these for COLORFUL; COLORFUL is gone and the
  -- zones under test here are the ones that were always the screen's.
  local menu = factory.new(game, {})
  local own = menu:sgbPalettes(game)
  ok(type(own) == "table" and own[1] ~= nil, "the screen returns its zones")

  local iconAt, barAt
  for _, zone in ipairs(own) do
    if zone.tx1 == 1 and zone.tx2 == 2 then iconAt = iconAt or zone end
    if zone.tx1 == 6 and zone.tx2 == 11 then barAt = barAt or zone end
  end
  ok(iconAt ~= nil, "an icon cell per POKeMON, in cols 1-2")
  ok(barAt ~= nil, "and an HP bar zone, in cols 6-11")
  eq(iconAt and iconAt.ty1, 3, "the first icon is on the first body row")
  eq(barAt and barAt.ty1, 4, "and the bar on the line under it")
end

io.write(("\nparty theme: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
