-- The POKeDEX list on Gold: this suite's screen, over the cart's id.
--
-- Red's list is a DECORATOR -- `List.new` calls the engine's own PokedexMenu
-- and rewrites `rows`, `items`, `draw` and `onSelectKey` on what comes back,
-- because Red's dex IS a ListMenu.  Gold's is not: it is one screen with a
-- `view` field and its own model for each of list / entry / area / search /
-- unown, with no `items` and no `rows` to decorate.  So the list is drawn
-- rather than decorated, off the same chrome.lua and the same DexData.
--
-- What this file pins is the part that is easy to get wrong when a screen is
-- rewritten rather than ported: that it reads Gold's save shape, that it
-- hands back to the cart for everything it does not draw, and that A on a
-- POKeMON you have never met opens the AREA map rather than refusing.
--
-- Run:  luajit tests/dexlist_gen2_test.lua

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

-- ---- enough LOVE and engine for the screen to build and draw

local noop = function() end
_G.love = {
  graphics = setmetatable({}, { __index = function() return noop end }),
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  timer = { getTime = function() return 0 end },
  audio = {},
  window = { getMode = function() return 160, 144 end },
}
for _, name in ipairs({ "getColor", "getShader", "getCanvas", "getScissor", "getFont" }) do
  love.graphics[name] = function() return nil end
end
love.graphics.newQuad = function() return {} end
-- Declared above the closure that writes it: a name used before its `local` is
-- a GLOBAL there, which is the shape tools/check.py fails on.
local lastColor
local blitted = {}
love.graphics.setColor = function(r, g, b, a) lastColor = { r, g, b, a } end
love.graphics.draw = function(_image, _quad, x, y)
  blitted[#blitted + 1] = { x = x, y = y, color = lastColor }
end

local drawn = {}
package.loaded["src.render.Font"] = {
  draw = function(text, x, y) drawn[#drawn + 1] = { text = text, x = x, y = y } end,
  drawCode = function(code, x, y) drawn[#drawn + 1] = { code = code, x = x, y = y } end,
  drawBox = noop,
  BORDER = {},
}
package.loaded["src.ui.Theme"] = { cursor = "CURSOR", cursorHollow = "HOLLOW" }
package.loaded["src.core.Strings"] = setmetatable({
  source = function(s) return s end,
}, { __call = function(_, s, ...)
  if select("#", ...) > 0 then return string.format(s, ...) end
  return s
end })

-- Gold's PartyMenu, in the two respects this screen has to work around:
--
--   iconFor derives the frame from the menu's OWN clock, so a clock that ticks
--   every frame bobs every icon in the list at once.
--   drawIcon sets G.setColor(1,1,1,1) immediately before painting
--   (src/ui/gen2/PartyMenu.lua:895), which wipes any tint the caller set --
--   Red's never does, which is why the tint silhouette works there and not
--   here.
local iconCalls = {}
local ICON_FRAME_STEPS = 8
package.loaded["src.ui.gen2.PartyMenu"] = {
  iconFor = function(self, mon)
    return { getDimensions = function() return 16, 32 end },
      math.floor((self.clock or 0) / ICON_FRAME_STEPS) % 2
  end,
  drawIcon = function(self, mon, px, py)
    love.graphics.setColor(1, 1, 1, 1)
    iconCalls[#iconCalls + 1] = {
      species = mon and mon.species, x = px, y = py,
      frame = math.floor((self.clock or 0) / ICON_FRAME_STEPS) % 2,
    }
  end,
}

-- The CART's own dex module, by name.
--
-- Deliberately not `Screens`: this mod registers itself over
-- `Gen2PokedexMenu`, and `Screens.build` resolves the registry first -- so
-- asking Screens for that id built another copy of this list rather than the
-- cart's screen.  Every A press stacked one more and B peeled one off, which
-- is why the dex could not be closed.  A stub on Screens would have kept
-- passing through all of that.
local pushed = {}
local builtScreens = {}
package.loaded["src.ui.gen2.PokedexMenu"] = {
  new = function(_game, _opts)
    local screen = { view = "list", index = 1,
                     order = function() return { "BULBASAUR", "CHARMANDER" } end }
    builtScreens[#builtScreens + 1] = screen
    return screen
  end,
}
-- Present, and never the thing that answers: if the screen ever goes back to
-- asking Screens for its own id, this fails loudly instead of nesting.
package.loaded["src.ui.Screens"] = {
  build = function(_game, id)
    error("the list asked Screens for '" .. tostring(id)
      .. "', which resolves to itself", 2)
  end,
}

local function slurp(path)
  local handle = assert(io.open(path))
  local text = handle:read("*a")
  handle:close()
  return text
end
local function chunkOf(path)
  return assert(load(slurp(path), "@" .. path))()
end

local mod = {
  path = "modules/Gen1Dex",
  log = { info = noop, warn = noop, error = noop },
  options = { get = function(_, key)
    if key == "wrap" then return true end
    if key == "view_cycle" then return true end
    return nil
  end },
}

local DexData = chunkOf("modules/Gen1Dex/dexdata.lua")
local C = chunkOf("modules/Gen1Dex/chrome.lua")(mod)
local List = chunkOf("modules/Gen1Dex/gen2list.lua")(mod, DexData, C)

ok(type(List.new) == "function", "the Gold list builds")

-- ---- a Gold save
--
-- Gold keeps the dex under `save.pokedex`, not at the top level the way Red
-- does.  A list that read the Gen 1 shape would mask every entry on the cart
-- it was written for.

-- Gold's shape.  The two `dexSize` values below are deliberately SMALLER than
-- the roster beside them: the bound is derived from the roster and only raised
-- by a declared dexSize, never lowered by one, so neither of these can cut the
-- list short.  On the real cart there is no dexSize to read at all --
-- `data.gen2Constants` is the ordered name lists -- which is what stopped the
-- Johto dex at Kanto.  tests/dexgold_test.lua checks that against the engine.
local DATA = {
  constants = { dexSize = 2, dexDigits = 3 },
  gen2Constants = { dexSize = 4, dexDigits = 3 },
  gen2Pokedex = { newOrder = { "CHARMANDER", "SQUIRTLE" } },
  pokemon = {
    BULBASAUR  = { id = "BULBASAUR",  dex = 1, name = "BULBASAUR" },
    IVYSAUR    = { id = "IVYSAUR",    dex = 2, name = "IVYSAUR" },
    CHARMANDER = { id = "CHARMANDER", dex = 3, name = "CHARMANDER" },
    SQUIRTLE   = { id = "SQUIRTLE",   dex = 4, name = "SQUIRTLE" },
  },
}

local function scene()
  drawn, iconCalls, pushed, builtScreens = {}, {}, {}, {}
  blitted = {}
  local game = {
    data = DATA,
    -- Gold's OWN key for the caught half is `caught` -- its dex screen reads
    -- `save.pokedex.caught` (PokedexMenu:rebuild).  Written that way here so
    -- this fixture cannot agree with the bug it is meant to catch: handing
    -- DexData.list Gold's table raw left `owned` nil, so nothing was ever
    -- caught, CAUGHT was always empty, and SELECT could not get back out of
    -- A-Z.  The screen normalises it in `dexSave`.
    save = { pokedex = { seen = { CHARMANDER = true }, caught = { BULBASAUR = true } } },
    input = { wasPressed = function() return false end },
    stack = { push = function(_, s) pushed[#pushed + 1] = s end,
              pop = function() end },
  }
  game.stack.push = function(self, s) pushed[#pushed + 1] = s end
  return List.new(game, {}), game
end

do
  local screen = scene()
  eq(screen.screenId, "Gen2PokedexMenu",
     "it answers to the id Gold's START menu pushes")
  eq(#screen.items, 4, "every slot is a row, met or not")
  eq(screen.seen, 2, "SEEN counts the owned one too")
  eq(screen.owned, 1, "OWN counts only the caught")
end

-- ---- the rows say what has been met and what has not

do
  local screen = scene()
  eq(screen.items[1].label, "001 BULBASAUR", "a caught POKeMON is named")
  ok(screen.items[1].ball, "and carries the ball")
  eq(screen.items[3].label, "003 CHARMANDER", "a seen one is named")
  ok(not screen.items[3].ball, "with no ball")
  eq(screen.items[2].label, "002 -----",
     "one never met is masked, and still holds its slot")
  ok(not screen.items[2].seen, "and knows it has not been met")
  eq(screen.items[2].species, "IVYSAUR",
     "while still carrying the species, so AREA can open on it")
end

-- ---- SELECT cycles the three views

do
  local screen = scene()
  eq(screen.mode, "num", "it opens on the numbered view")
  screen:cycleView()
  eq(screen.mode, "alpha", "SELECT goes to A-Z")
  eq(#screen.items, 2, "which lists only what has been met")
  screen:cycleView()
  eq(screen.mode, "caught", "then to caught")
  eq(#screen.items, 1, "which lists only what has been caught")
  screen:cycleView()
  eq(screen.mode, "num", "and round")
end

-- An empty view would strand SELECT: an empty list answers nothing but A and
-- B, so there would be no way back out of it.
do
  drawn, iconCalls, pushed, builtScreens = {}, {}, {}, {}
  blitted = {}
  local game = {
    data = DATA,
    save = { pokedex = { seen = {}, owned = {} } },
    input = { wasPressed = function() return false end },
    stack = { push = noop, pop = noop },
  }
  local screen = List.new(game, {})
  screen:cycleView()
  eq(screen.mode, "num", "a view with nothing in it is not entered")
end

-- ---- A hands back to the cart, in the right view

do
  local screen = scene()
  screen.index = 1                       -- BULBASAUR, caught
  screen:choose()
  eq(#builtScreens, 1, "A builds the cart's own screen")
  eq(builtScreens[1].screenId, "Gen2PokedexMenu", "which is the cart's dex")
  eq(builtScreens[1].view, "entry", "opened on the ENTRY for one you have met")
  eq(builtScreens[1].index, 1, "pointed at the POKeMON the cursor was on")
  eq(#pushed, 1, "and pushed over this list")
end

do
  local screen = scene()
  screen.index = 2                       -- IVYSAUR, never met
  screen:choose()
  eq(builtScreens[1].view, "area",
     "A on one you have never met opens the AREA map rather than refusing")
end

do
  local screen = scene()
  screen.index = 2
  screen:open("search")
  eq(builtScreens[1].view, "search",
     "and SEARCH is the cart's own, not re-implemented here")
end

-- ---- the cursor walks and wraps

do
  local screen = scene()
  -- from the top, rather than from wherever the Johto opening put it
  screen.index = 1
  screen:move(1)
  eq(screen.index, 2, "DOWN steps a row")
  screen.index = 1
  screen:move(-1)
  eq(screen.index, 4, "UP off the top wraps to the end")
  screen:move(1)
  eq(screen.index, 1, "and DOWN off the end wraps back")
end

-- ---- it draws: an icon per row, and the footer

do
  local screen = scene()
  screen:draw()
  -- Every row gets art: the two that have been met through the cart's own
  -- icon path, the two that have not as masks (see the silhouette block
  -- below) -- so the count is the two paths together, and no row is skipped.
  eq(#iconCalls + #blitted, 4, "an icon is drawn for every row on screen")
  eq(iconCalls[1].species, "BULBASAUR", "the first row's own species")
  eq(#blitted, 2, "and the two never met are drawn too, rather than skipped")

  local footer
  for _, d in ipairs(drawn) do
    if type(d.text) == "string" and d.text:find("SEEN") then footer = d.text end
  end
  eq(footer, "SEEN   2  OWN   1",
     "the footer counts the whole dex in fixed three-digit fields")
end

-- ---- an entry never met is BLACKED OUT
--
-- Red gets this for free: its PartyMenu.drawIcon paints in the caller's
-- colour, so setColor(0,0,0,1) takes every pixel's RGB to zero, leaves the
-- alpha alone, and a silhouette of the exact shape falls out.  Gold's sets
-- G.setColor(1,1,1,1) immediately before painting, so the tint was wiped on
-- the way in and every entry came out fully lit.

do
  local screen = scene()
  screen:draw()

  -- The two that have been met go through drawIcon; the two that have not are
  -- blitted here instead, so they can be tinted.
  local lit = {}
  for _, call in ipairs(iconCalls) do lit[call.species] = true end
  ok(lit.BULBASAUR, "a caught POKeMON is drawn through the cart's own icon path")
  ok(lit.CHARMANDER, "and so is a seen one")
  ok(not lit.IVYSAUR, "one never met is not: it would come back fully lit")

  eq(#blitted, 2, "the two never met are drawn here, as masks")
  for _, mark in ipairs(blitted) do
    eq(("%d,%d,%d"):format(mark.color[1] * 255, mark.color[2] * 255,
                           mark.color[3] * 255),
       "0,0,0", "and each is drawn black")
    eq(mark.color[4], 1, "at full alpha, so it is a silhouette and not a ghost")
  end
end

-- ---- and only the row under the cursor moves
--
-- iconFor reads the frame off the menu's own clock, so one clock ticking every
-- frame bobs all six at once.  It is set per row instead: the live one for the
-- row being read, zero -- the standing frame -- for the rest.

do
  local screen = scene()
  -- far enough in for the two-frame bob to have turned over
  for _ = 1, 9 do screen:update(1 / 60) end
  screen.index = 3                      -- CHARMANDER, which has been seen
  screen:draw()

  local byName = {}
  for _, call in ipairs(iconCalls) do byName[call.species] = call end
  eq(byName.CHARMANDER.frame, 1, "the row being read is on its second frame")
  eq(byName.BULBASAUR.frame, 0, "every other row is standing still")
end

do
  local screen = scene()
  screen.index = 1
  screen:draw()
  local byName = {}
  for _, call in ipairs(iconCalls) do byName[call.species] = call end
  eq(byName.BULBASAUR.frame, 0,
     "and a fresh screen starts standing rather than mid-stride")
end

-- Moving the cursor moves which one is animating, and nothing else.
do
  local screen = scene()
  for _ = 1, 9 do screen:update(1 / 60) end
  screen.index = 1
  screen:draw()
  local first = {}
  for _, call in ipairs(iconCalls) do first[call.species] = call.frame end
  eq(first.BULBASAUR, 1, "the first row bobs while it is the one being read")

  iconCalls = {}
  screen.index = 3
  screen:draw()
  local second = {}
  for _, call in ipairs(iconCalls) do second[call.species] = call.frame end
  eq(second.BULBASAUR, 0, "and stops the moment the cursor leaves it")
  eq(second.CHARMANDER, 1, "while the row it moved to takes over")
end

-- ---- the whole dex, not Kanto's half of it
--
-- This block used to say the bound came from `data.gen2Constants.dexSize`,
-- and it was wrong on both halves: a Gold boot never loads src/core/Data.lua,
-- which is the only thing that derives `dexSize`, and `data.gen2Constants` is
-- the cart's ordered NAME LISTS -- it has no such key.  So the list fell to
-- `or 151` and stopped at Kanto.  See tests/dexgold_test.lua, which checks
-- both of those against the engine rather than restating them.
--
-- The bound is the UNION now: the roster's own highest dex number against any
-- dexSize a dataset declares.  Deriving from the roster is what
-- src/core/Data.lua does for Gen 1, and for its own stated reason -- "a
-- dataset with a different roster gets the right upper bound without 151 being
-- written down anywhere".

do
  local screen = scene()
  eq(#screen.items, 4,
     "the list runs the whole roster, not Kanto's half of it")
  eq(screen.items[4].species, "SQUIRTLE", "so the last slot is really there")

  -- The Gen 1 arm answers the same, because the roster is the same: with the
  -- Gen 2 tables gone there is no gen2Constants to prefer and no dexSize of 4
  -- to read, and the four species are still four species.
  local red = {}
  for k, v in pairs(DATA) do red[k] = v end
  red.gen2Constants = nil
  red.gen2Pokedex = nil
  local build = DexData.list(red, { seen = {}, owned = {} }, "num")
  eq(#build.items, 4, "on Red the roster is still the answer")
end

-- ---- and the cursor opens on the dex you are filling
--
-- Not 001.  Gold's own screen opens on its Johto ordering (wLastDexMode
-- defaults to NEW), and the first entry of that ordering is where this one is
-- put down -- read off the cart's own newOrder rather than the number 152, so
-- a dataset that changed the roster still lands right.

do
  local screen = scene()
  eq(screen.items[screen.index].species, "CHARMANDER",
     "the cursor opens on the first entry of the cart's Johto order")
  ok(screen.index > 1, "which is not the top of the national list")
  eq(screen.items[1].species, "BULBASAUR",
     "and Kanto is still there, one scroll up")
end

do
  -- A cart with no Johto ordering to read leaves the cursor where it was.
  local bare = {}
  for k, v in pairs(DATA) do bare[k] = v end
  bare.gen2Pokedex = nil
  drawn, iconCalls, pushed, builtScreens = {}, {}, {}, {}
  blitted = {}
  local game = {
    data = bare,
    save = { pokedex = { seen = {}, owned = { BULBASAUR = true } } },
    input = { wasPressed = function() return false end },
    stack = { push = noop, pop = noop },
  }
  local screen = List.new(game, {})
  eq(screen.index, 1, "with no Johto order the cursor starts at the top")
end

io.write(("dexlist_gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
