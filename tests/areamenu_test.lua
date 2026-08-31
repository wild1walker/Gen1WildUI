-- A on the AREA map, which used to close it.
--
-- The AREA screen is the town map with a species pinned to it.  The map you
-- open from the BAG answers A with a menu -- INSPECT, and FLY when there is
-- somewhere under the cursor to fly to -- and this one answered it by
-- closing, which is the one thing A should not mean on a map you are reading.
-- The cursor is sitting on a town while you read it, and "what else lives
-- here" is the question a player has with the map already open; going out to
-- the BAG for the same picture to ask it was the screen being pedantic about
-- which door you came in by.
--
-- So there is ONE menu with two callers.  `Inspect.offer` is it, and the AREA
-- screen's own FLY is handed to it as an extra row rather than derived inside
-- it: this map only flies when the FIELD MOVE opened it and the engine
-- narrowed `locs` for it, and the AREA screen has to ask the party and the
-- map it is standing on instead.
--
-- Run:  luajit tests/areamenu_test.lua

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

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ------------------------------------------------- as much engine as it takes

local Font = {
  draw = function() end, drawBox = function() end, drawCode = function() end,
  width = function(t) return #t * 8 end,
  split = function(t)
    local o = {}
    for i = 1, #t do o[i] = { from = i, to = i } end
    return o
  end,
  spansFitting = function(spans) return #spans end,
}

local pushed = {}
local menus = {}
local Menu = {
  new = function(_, items, opts)
    local menu = { items = items, opts = opts }
    menus[#menus + 1] = menu
    return menu
  end,
}

local options = { map_inspect = true, area_fly = true, area_hints = true }
local warned = {}
local mod = {
  ui = { Font = Font, Menu = Menu, Theme = {},
         TextBox = { soundOpts = function() return nil end } },
  options = { get = function(_, key) return options[key] end },
  log = { warn = function(_, text) warned[#warned + 1] = text end,
          error = function() end, info = function() end },
}

package.loaded["src.render.Font"] = Font
package.loaded["src.core.Sound"] = { play = function() end }
package.loaded["src.world.Map"] = {
  isFlyTown = function() return true end,
  isOutside = function() return true end,
}
package.loaded["src.core.FieldDefaults"] = { field = function() return {} end }
love = { graphics = { setColor = function() end, rectangle = function() end,
                      draw = function() end } }

-- TownMap, as far as this reaches into it: a constructor that hands back a
-- screen with the fields the wrap reads, and an update that records that the
-- engine's own got the press -- which on the AREA screen is the close.
local closed = 0
local TownMap = {}
TownMap.__index = TownMap
function TownMap.new(game, opts)
  local screen = setmetatable({
    game = game,
    mode = "grid",
    bg = { cursor = {} },
    nests = {},
    sel = 1,
    blink = 0,
    locs = { { name = "PALLET TOWN", x = 4, y = 11 },
             { name = "VIRIDIAN CITY", x = 4, y = 9 } },
    nestSpecies = opts and opts.nestSpecies,
  }, TownMap)
  screen.byMap = { PALLET_TOWN = screen.locs[1], VIRIDIAN_CITY = screen.locs[2] }
  return screen
end
function TownMap.update() closed = closed + 1 end
package.loaded["src.ui.TownMap"] = TownMap

local C = chunkOf("modules/Gen1Dex/chrome.lua")(mod)
local Inspect = chunkOf("modules/Gen1Dex/inspect.lua")(mod, C)
local Area = chunkOf("modules/Gen1Dex/area.lua")(mod, C, Inspect)
Inspect.install()
Area.install()

-- ------------------------------------------------------------ a cartridge

local data = {
  pokemon = { PIDGEY = { name = "PIDGEY", dex = 16 } },
  maps = { PALLET_TOWN = {}, VIRIDIAN_CITY = {} },
  field = {
    flyOrder = { "PALLET_TOWN", "VIRIDIAN_CITY" },
    flyWarps = { PALLET_TOWN = true, VIRIDIAN_CITY = true },
  },
  encounters = {},
}

-- A stack with the overworld at the bottom, which is what a dex opened from
-- the START menu is standing on.
local function stackWith(overworld)
  local stack = { states = { overworld } }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function overworldThatFlies()
  local ow = { map = { def = {} }, flew = nil }
  function ow:partyKnows(move) return move == "FLY" end
  function ow:flyTo(mapId) self.flew = mapId end
  return ow
end

local function keys(...)
  local down = {}
  for _, key in ipairs({ ... }) do down[key] = true end
  return { wasPressed = function(_, key) return down[key] or false end }
end

-- A screen as the dex opens it, with the overworld under it and the hint up.
local function areaScreen(overworld)
  local game = {
    data = data,
    save = { pokedex = { seen = { PIDGEY = true }, owned = {} },
             visited = { PALLET_TOWN = true, VIRIDIAN_CITY = true } },
    overworld = overworld,
  }
  game.stack = stackWith(overworld)
  game.input = keys()
  local screen = TownMap.new(game, { nestSpecies = "PIDGEY" })
  game.stack:push(screen)
  return screen, game
end

local function press(screen, game, ...)
  game.input = keys(...)
  screen:update(0)
end

local function labelsOf(menu)
  local out = {}
  for i, item in ipairs(menu.items or {}) do out[i] = item.label end
  return table.concat(out, " ")
end

-- ---------------------------------------------------------------- the tests

io.write("the first A is still the hint coming down\n")
do
  menus, closed = {}, 0
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  eq(#menus, 0, "the press that dismisses the hint opens nothing")
  eq(closed, 0, "and it does not reach the engine's own A either")
end

io.write("and the second opens the map's menu instead of closing it\n")
do
  menus, closed = {}, 0
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")                        -- hint down
  press(screen, game, "a")                        -- the press under test
  eq(closed, 0, "the AREA map does not close on A any more")
  eq(#menus, 1, "it opens the map's menu")
  if menus[1] then
    eq(labelsOf(menus[1]), "FLY INSPECT",
      "FLY first, because the cursor is over somewhere you can fly to")
    eq(menus[1].opts and menus[1].opts.cancelable, true,
      "and B backs out of it, then closes the map the way it always did")
  end
end

io.write("INSPECT asks about the town under the cursor\n")
do
  menus = {}
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  press(screen, game, "right")                    -- nothing to the right
  press(screen, game, "up")                       -- VIRIDIAN is north
  eq(screen.sel, 2, "the cursor moved by direction, the way this map steers")
  press(screen, game, "a")
  local menu = menus[#menus]
  ok(menu ~= nil, "the menu came up over VIRIDIAN")
  if menu then
    local inspect
    for _, item in ipairs(menu.items) do
      if item.label == "INSPECT" then inspect = item end
    end
    ok(inspect ~= nil, "with an INSPECT row on it")
    if inspect then
      inspect.onSelect()
      local screenPushed = game.stack:top()
      ok(screenPushed ~= nil and screenPushed ~= menu,
        "which pushes a list of what lives there")
      eq(screenPushed and screenPushed.place, "VIRIDIAN CITY",
        "the town the cursor was on, not the one the map opened on")
    end
  end
end

io.write("FLY off the menu leaves every screen above the overworld behind\n")
do
  menus = {}
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  press(screen, game, "a")
  local fly
  for _, item in ipairs(menus[#menus].items) do
    if item.label == "FLY" then fly = item end
  end
  ok(fly ~= nil, "the FLY row is there")
  if fly then
    fly.onSelect()
    eq(ow.flew, "PALLET_TOWN", "and it takes off for the town under the cursor")
    eq(game.stack:top(), ow, "with the map, the menu and the dex left behind")
  end
end

io.write("nowhere to fly to is a menu with one row, not a closed map\n")
do
  menus, closed = {}, 0
  local ow = overworldThatFlies()
  function ow:partyKnows() return false end       -- no FLY in the party
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  press(screen, game, "a")
  eq(closed, 0, "still does not close")
  eq(#menus, 1, "still opens")
  if menus[1] then
    eq(labelsOf(menus[1]), "INSPECT", "with the row that does not need a party")
  end
end

io.write("MAP INSPECT off gives the press back to the flight\n")
do
  -- The two toggles are independent: this one takes away the menu and not the
  -- flight, and FLY FROM AREA takes away the flight and not the menu.
  menus, closed = {}, 0
  options.map_inspect = false
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  press(screen, game, "a")
  eq(#menus, 0, "no menu")
  eq(ow.flew, "PALLET_TOWN", "the direct flight A was before the menu existed")
  options.map_inspect = true
end

io.write("and with both off A closes the map, the way vanilla did\n")
do
  menus, closed = {}, 0
  options.map_inspect, options.area_fly = false, false
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  press(screen, game, "a")
  eq(#menus, 0, "nothing opened")
  eq(ow.flew, nil, "nothing flew")
  eq(closed, 1, "and the press went through to the engine's own A")
  options.map_inspect, options.area_fly = true, true
end

io.write("FLY FROM AREA off leaves the menu, minus its flight\n")
do
  menus, closed = {}, 0
  options.area_fly = false
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  press(screen, game, "a")
  eq(#menus, 1, "the menu still opens")
  if menus[1] then eq(labelsOf(menus[1]), "INSPECT", "without the FLY row") end
  options.area_fly = true
end

io.write("START still puts the hint back\n")
do
  menus = {}
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  press(screen, game, "a")
  press(screen, game, "start")
  press(screen, game, "a")
  eq(#menus, 0, "the hint is up again, so A takes it down rather than opening")
end

io.write("nothing under the cursor is a press handed back, not swallowed\n")
do
  menus, closed = {}, 0
  local ow = overworldThatFlies()
  local screen, game = areaScreen(ow)
  screen.locs = {}
  press(screen, game, "a")
  press(screen, game, "a")
  eq(#menus, 0, "there is nothing to ask about")
  eq(closed, 1, "so A means what it meant")
end

io.write(("\narea menu: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
