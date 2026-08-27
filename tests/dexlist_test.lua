-- Headless coverage of the POKEDEX list against BOTH shapes of the engine
-- screen it is built on top of.
--
-- The vanilla dex was a `ListMenu` until gen1recomp rewrote it as a screen of
-- its own (48d8a4e).  This mod builds the vanilla screen and re-dresses it,
-- and the rewrite moved the one field it writes: `rows` went from a number
-- the list read to a METHOD the screen's own syncScroll CALLS.  Writing the
-- number over the method crashed the dex on the first cursor move --
-- `attempt to call method 'rows' (a number value)`, PokedexMenu:syncScroll --
-- which is the whole reason this suite exists.
--
-- So both shapes are stood up here, as faithfully as a headless harness can:
-- the screen's `rows`/`syncScroll`/`pageScroll`/`update` are the engine's own
-- arithmetic, and the list one is the ListMenu the mod was written against.
-- What is checked is everything decided before a pixel is drawn:
--
--   * the list opens and the cursor moves, on either shape, without throwing;
--   * six rows are what the screen scrolls by, not the engine's seven;
--   * SELECT still cycles the three views, LIST WRAPS still crosses the ends
--     and HOLD TO SCROLL still repeats -- three settings that were opts on
--     the ListMenu and are answered by this mod on the screen;
--   * a draw pass runs over a built list without reaching for `rows` as a
--     number.
--
-- Run:  luajit tests/dexlist_test.lua

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

local LIST = "modules/Gen1Dex/list.lua"

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local function strings(text, ...)
  if select("#", ...) > 0 then return (tostring(text):format(...)) end
  return text
end

-- Enough of love.graphics to let a draw pass run.  Nothing about how the
-- screen LOOKS is claimed here; what is, is that drawing it touches no field
-- that has moved.
love = {
  graphics = {
    setColor = function() end,
    rectangle = function() end,
    circle = function() end,
  },
}

package.preload["src.core.Strings"] = function() return strings end
package.preload["src.render.Font"] = function()
  return {
    draw = function() end,
    drawCode = function() end,
    drawBox = function() end,
    width = function(text) return #tostring(text) * 8 end,
  }
end
package.preload["src.render.PaletteFX"] = function()
  return {
    GRAYS = {},
    whole = function() return { "whole" } end,
    wholeNamed = function() return { "named" } end,
    monPal = function() return nil end,
    zone = function() return nil end,
    markTrueColor = function() end,
  }
end
package.preload["src.render.Assets"] = function()
  return { imageData = function() error("no assets in the harness") end }
end
package.preload["src.ui.PartyMenu"] = function()
  return { drawIcon = function() end }
end
package.preload["src.pokemon.Sprites"] = function()
  return { iconPath = function(_, _, path) return path end }
end
package.preload["src.ui.Theme"] = function()
  return { cursor = 0xED, cursorHollow = 0xEC, moreArrow = 0xEE }
end

-- ------- the two shapes of the vanilla dex
--
-- The screen the engine has now.  Its arithmetic is copied from
-- src/ui/PokedexMenu.lua rather than approximated, because the numbers are
-- the thing under test: ROWS is SEVEN here, and this mod wants six.

local ENGINE_ROWS = 7

local function screenShape()
  local M = {}
  M.__index = M
  M.isOpaque = true

  function M.new(game, opts)
    local self = setmetatable({}, M)
    self.game = game
    self.onCancel = opts and opts.onCancel
    self.index, self.scroll = 1, 0
    self.items = {}
    self.footer = ""
    return self
  end

  function M:rows() return math.min(ENGINE_ROWS, #self.items) end

  function M:syncScroll()
    local rows = self:rows()
    if rows == 0 then
      self.index, self.scroll = 1, 0
      return
    end
    self.index = math.max(1, math.min(#self.items, self.index))
    if self.index - self.scroll > rows then self.scroll = self.index - rows end
    if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
  end

  function M:pageScroll(dir)
    local n = #self.items
    if n < ENGINE_ROWS then return end
    local row = self.index - self.scroll
    local scroll = math.max(0, math.min(n - ENGINE_ROWS,
                                        self.scroll + dir * ENGINE_ROWS))
    self.scroll = scroll
    self.index = math.min(n, scroll + row)
  end

  function M:close() end

  function M:update()
    local input = self.game.input
    if #self.items == 0 then return end
    if input:wasPressed("up") then
      self.index = self.index - 1
    elseif input:wasPressed("down") then
      self.index = self.index + 1
    elseif input:wasPressed("left") then
      self:pageScroll(-1)
    elseif input:wasPressed("right") then
      self:pageScroll(1)
    elseif input:wasPressed("b") then
      return
    elseif input:wasPressed("a") then
      self.onChoose(self.items[self.index], self)
      return
    end
    self:syncScroll()
  end

  M.onChoose = function() end
  return M
end

-- The ListMenu the dex used to be: `rows` a plain number, and wrap,
-- key-repeat and SELECT read straight off the instance.
local function listShape()
  local M = {}
  M.__index = M

  function M.new(game, opts)
    local self = setmetatable({}, M)
    self.game = game
    self.onCancel = opts and opts.onCancel
    self.index, self.scroll = 1, 0
    self.items = {}
    self.rows = ENGINE_ROWS
    self.footer = ""
    return self
  end

  function M:close() end
  function M:update() end
  return M
end

local function withVanilla(shape)
  package.loaded["src.ui.PokedexMenu"] = nil
  package.preload["src.ui.PokedexMenu"] = function() return shape() end
end

-- ------- what the mod is handed

local SPECIES = 151

local function dexData()
  local D = {
    MODES = { "num", "alpha", "caught" },
    MODE_LABELS = { num = "POKéDEX", alpha = "A-Z", caught = "CAUGHT" },
    NEXT_MODE = { num = "alpha", alpha = "caught", caught = "num" },
  }
  function D.list(_, _, mode)
    local items = {}
    -- the caught view is the short one, so a mode change really does resize
    local count = (mode == "caught") and 4 or SPECIES
    for i = 1, count do
      items[i] = {
        label = ("%03d MON%d"):format(i, i),
        species = "mon" .. i,
        seen = true,
        value = "mon" .. i,
      }
    end
    return { items = items, seen = count, owned = count }
  end
  return D
end

local function chrome(options)
  return {
    BODY_TOP = 24, LEFT = 8, RIGHT = 152,
    HEADER_TEXT_Y = 8, FOOTER_TEXT_Y = 128,
    option = function(key, default)
      local value = (options or {})[key]
      if value == nil then return default end
      return value
    end,
    clear = function() end,
    white = function() end,
    black = function() end,
    rule = function() end,
    headerBox = function() end,
    footerBox = function() end,
    pips = function() end,
    pipsWidth = function(n) return n * 8 end,
    truncate = function(text) return text end,
  }
end

local function fakeMod()
  local logged = {}
  return {
    log = {
      info = function(_, ...) logged[#logged + 1] = { "info", ... } end,
      warn = function(_, ...) logged[#logged + 1] = { "warn", ... } end,
      error = function(_, ...) logged[#logged + 1] = { "error", ... } end,
    },
    logged = logged,
  }
end

-- One frame's worth of input.  `wasPressed` is a QUESTION, not a queue --
-- src/core/Input.lua answers it out of a table the frame boundary clears, so
-- two readers on one frame both see the press.  That is load-bearing here:
-- the layer this mod puts over the screen's update asks about UP and DOWN and
-- then hands the same frame to the engine's update, which asks again.
local function input()
  local self = { pressed = {}, down = {} }
  function self:wasPressed(key) return self.pressed[key] and true or false end
  function self:isDown(key) return self.down[key] and true or false end
  function self:press(key) self.pressed[key] = true end
  function self:hold(key) self.down[key] = true end
  function self:release(key) self.down[key] = nil end
  function self:endFrame() self.pressed = {} end
  return self
end

-- One frame: the screen updates, then the presses age out of the input.
local function frame(list)
  list:update(0)
  list.game.input:endFrame()
end

local function fakeGame()
  return {
    input = input(),
    data = { pokemon = {}, icons = nil },
    save = { pokedex = { seen = {}, owned = {} } },
    stack = { states = {}, push = function() end, top = function() end,
              pop = function() end },
  }
end

local function build(shape, options)
  withVanilla(shape)
  local mod = fakeMod()
  local factory = chunkOf(LIST)
  local screen = factory(mod, dexData(), chrome(options), nil)
  local game = fakeGame()
  return screen.new(game, {}), game, mod
end

-- ------------------------------------------- the screen the engine has now

do
  local list, game = build(screenShape)

  eq(type(list.rows), "function",
     "on the rewritten screen `rows` stays the method its syncScroll calls")
  eq(list:rows(), 6, "and answers this mod's six rows, not the engine's seven")

  -- The crash, exactly as it was reported: open the dex, press a direction.
  game.input:press("down")
  local moved, err = pcall(frame, list)
  ok(moved, "a cursor move no longer throws: " .. tostring(err))
  eq(list.index, 2, "and the cursor moved one row")

  -- Six visible rows means the seventh entry is what first scrolls the page.
  for _ = 1, 5 do
    game.input:press("down")
    frame(list)
  end
  eq(list.index, 7, "seven presses reach the seventh entry")
  eq(list.scroll, 1, "and the page has scrolled by exactly one row")
end

-- ------- an empty view

do
  local list = build(screenShape)
  list.items = {}
  eq(list:rows(), 0, "an empty list shows no rows")
  local fine = pcall(list.syncScroll, list)
  ok(fine, "and clamping one does not divide by its length")
end

-- ------- SELECT still cycles the views

do
  local list, game = build(screenShape)
  eq(list.dexMode(), "num", "the list opens in the numbered view")

  game.input:press("select")
  frame(list)
  eq(list.dexMode(), "alpha", "SELECT moves to the next view")

  game.input:press("select")
  frame(list)
  eq(list.dexMode(), "caught", "and the next")
  eq(#list.items, 4, "which is a shorter list")
  eq(list:rows(), 4, "so fewer rows are on the screen")

  game.input:press("select")
  frame(list)
  eq(list.dexMode(), "num", "and back round to the first")
end

do
  local list, game = build(screenShape, { view_cycle = false })
  game.input:press("select")
  frame(list)
  eq(list.dexMode(), "num", "SELECT VIEWS off leaves SELECT unbound")
end

-- ------- LIST WRAPS

do
  local list, game = build(screenShape)
  game.input:press("up")
  frame(list)
  eq(list.index, SPECIES, "UP on the first row crosses to the last")
  eq(list.scroll, SPECIES - 6, "with the page taken to the bottom")

  game.input:press("down")
  frame(list)
  eq(list.index, 1, "and DOWN on the last comes back to the first")
  eq(list.scroll, 0, "with the page back at the top")
end

do
  local list, game = build(screenShape, { wrap = false })
  game.input:press("up")
  frame(list)
  eq(list.index, 1, "LIST WRAPS off leaves the cursor on the first row")
end

-- ------- HOLD TO SCROLL

do
  local list, game = build(screenShape)
  game.input:press("down")
  game.input:hold("down")
  frame(list)
  eq(list.index, 2, "the press itself moves one row")

  -- sixteen frames of delay, then one row every four
  for _ = 1, 16 do frame(list) end
  eq(list.index, 3, "a held key starts repeating after the delay")
  for _ = 1, 4 do frame(list) end
  eq(list.index, 4, "and keeps going at the repeat rate")

  game.input:release("down")
  for _ = 1, 8 do frame(list) end
  eq(list.index, 4, "letting go stops it")
end

do
  local list, game = build(screenShape, { hold_scroll = false })
  game.input:press("down")
  game.input:hold("down")
  for _ = 1, 40 do frame(list) end
  eq(list.index, 2, "HOLD TO SCROLL off moves once and stays there")
end

-- ------- LEFT/RIGHT page by what is on the screen

do
  local list, game = build(screenShape)
  game.input:press("right")
  frame(list)
  eq(list.index, 7, "RIGHT pages by the six rows the screen shows")
  game.input:press("left")
  frame(list)
  eq(list.index, 1, "and LEFT pages back by the same six")
end

-- ------- a draw pass

do
  local list = build(screenShape)
  local drew, err = pcall(list.draw, list)
  ok(drew, "the list draws: " .. tostring(err))
  local zoned, zones = pcall(list.sgbPalettes, list, list.game)
  ok(zoned and zones ~= nil, "and hands back palette zones for its rows")
end

-- ------------------------------------------- the ListMenu it used to be

do
  local list, game = build(listShape)

  eq(list.rows, 6, "on a build whose dex is still a ListMenu `rows` stays a number")
  eq(list.wrap, true, "and wrap is the field the list reads")
  eq(list.keyRepeat, true, "and so is key-repeat")
  eq(type(list.onSelectKey), "function", "with SELECT its own field")

  -- Nothing is layered over that list's update: it answers these itself.
  game.input:press("select")
  frame(list)
  eq(list.dexMode(), "num",
     "the ListMenu's own update is left to route SELECT, not wrapped")
end

-- ---------------------------------------------------------------- report

io.write(("\ndex list: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
