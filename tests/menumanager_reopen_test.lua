-- Putting the START menu back after the layout editor.
--
-- The editor is reached FROM the START menu and has to put it back on the way
-- out, and that one call is the whole subject of this file, because getting it
-- wrong on Gold produces a menu that cannot be escaped.
--
-- Red's `StartMenu.new(game)` takes the game and nothing else: it builds every
-- row's `onSelect` itself, and the engine's own way in is a bare
-- `Screens.push(Game, "StartMenu")`.  Gold's is `StartMenu.new(game, opts)`
-- and takes `onChoose` and `onClose` as PUSH OPTIONS -- so the same bare push
-- there builds a menu whose `choose` ends in `if self.onChoose then` and whose
-- `close` ends in `if self.onClose then`.  Both are nil.  Nothing opens, and B
-- and START do not shut it: the rows draw, the cursor moves, and the only way
-- out is a soft reset.
--
-- So the assertion is not "a screen was pushed".  It is WHICH call was made:
-- the game's own opener where there is one, and only the learned screen id
-- where there is not.
--
-- Run:  luajit tests/menumanager_reopen_test.lua

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

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

-- Gold, so the rows and the arms that are Gold's only are reachable.  Red's
-- cases below take it away again.
package.loaded["src.core.GameVersion"] = {
  generation = function() return 2 end,
}

-- ------------------------------------------------------------- the harness

local DIR = "modules/Gen1MenuManager"

-- Enough of the engine's mod object for the entry chunk to install against,
-- instrumented where the assertions are: what was pushed, and what was logged.
local function fakeMod()
  local self = {
    id = "gen1_wild_qol",
    path = DIR,
    exports = {},
    stored = { select_shortcut = true, menu_row = true, pc_row = true },
    saved = {},
    hooks_by_name = {},
    listeners = {},
    screens = {},
    pushed = {},
    logged = {},
  }

  function self:read(name) return readFile(DIR .. "/" .. name) end

  -- define is called more than once: the Gold-only rows are appended in a
  -- second call rather than declared with the rest, so they accumulate.
  self.rows = {}
  self.options = {
    define = function(_, rows)
      for _, row in ipairs(rows or {}) do self.rows[#self.rows + 1] = row end
    end,
    -- The engine's store answers the row's DECLARED DEFAULT for a key
    -- nobody has written, and a stub that answers nil instead hides every
    -- bug about a default-off row.
    get = function(_, key)
      local value = self.stored[key]
      if value ~= nil then return value end
      for _, row in ipairs(self.rows) do
        if row.key == key then return row.default end
      end
      return nil
    end,
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
  self.cache = { read = function() end, write = function() end }
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    self.log[level] = function(_, format, ...)
      self.logged[#self.logged + 1] = select("#", ...) > 0
        and format:format(...) or format
    end
  end
  self.hooks = {
    wrap = function(_, name, fn) self.hooks_by_name[name] = fn end,
  }
  self.events = {
    on = function(_, name, fn)
      self.listeners[name] = self.listeners[name] or {}
      table.insert(self.listeners[name], fn)
    end,
    once = function(_, name, fn)
      self.listeners[name] = self.listeners[name] or {}
      table.insert(self.listeners[name], fn)
    end,
  }
  self.content = {
    screens = {
      register = function(_, id, factory) self.screens[id] = factory end,
    },
  }
  self.ui = {
    push = function(_game, id, opts)
      self.pushed[#self.pushed + 1] = { id = id, opts = opts }
      return opts
    end,
  }
  self.world = { game = nil }
  self.find = function() return nil end
  return self
end

local function install(mod)
  local source = assert(readFile(DIR .. "/main.lua"), "main.lua is missing")
  assert(load(source, "@" .. DIR .. "/main.lua"))()(mod)
  return mod
end

-- The two shapes of game.  Gold's has `openStartMenu`; Red's has no such
-- method at all, which is what the fallback is keyed on.
-- A stack that actually stacks, because half of what is asserted below is
-- about how many START menus are on it.
local function fakeStack()
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function goldGame()
  local game = { save = { player = { name = "GOLD" } }, opened = 0, items = {} }
  game.stack = fakeStack()
  -- Game2:openStartMenu, reduced to the two things this file is about: it
  -- pushes a menu, and the menu it pushes carries the two callbacks.
  game.openStartMenu = function(self)
    self.opened = self.opened + 1
    self.stack:push({
      screenId = "Gen2StartMenu",
      onClose = function() self.stack:pop() end,
      onChoose = function(id) self:openStartMenuItem(id) end,
    })
  end
  game.openStartMenuItem = function(self, id) self.items[#self.items + 1] = id end
  return game
end

local function redGame()
  local game = { save = { player = { name = "RED" } } }
  game.stack = fakeStack()
  return game
end

-- Walk the START menu hook the way the engine does, find the manager's own
-- row, and run it -- which is what opens the editor and hands it the onCancel
-- that has to put the menu back.
-- The live menu the engine hands over on screen.pushed.  A real Gold one
-- carries both callbacks, because Game2:openStartMenu supplied them.
local function liveStartMenu(game, rows)
  return {
    screenId = "Gen2StartMenu", items = rows, update = function() end,
    onClose = function() game.stack:pop() end,
    onChoose = function(id) game:openStartMenuItem(id) end,
  }
end

local function editorCancelFor(mod, game)
  local hook = mod.hooks_by_name["ui.start_menu.items"]
  assert(type(hook) == "function", "the START menu hook was never wrapped")

  local vanilla = {
    { label = "POKeDEX", value = "pokedex" },
    { label = "PACK", value = "pack" },
    { label = "SAVE", value = "save" },
  }
  local rows = hook(function(_g, items) return items end, game, vanilla)

  local manager
  for _, row in ipairs(rows) do
    if row.label == "MENU MGR" then manager = row end
  end
  assert(manager, "the manager's own row is not on the menu")

  local before = #mod.pushed
  manager.onSelect(game)
  local push = mod.pushed[#mod.pushed]
  assert(#mod.pushed > before and push.id == "Gen1MenuManagerEditor",
         "the editor was not opened")
  return push.opts and push.opts.onCancel, rows
end

-- ------------------------------------------------------------------ Gold

do
  io.write("on Gold\n")
  local mod = install(fakeMod())
  local game = goldGame()

  local cancel, rows = editorCancelFor(mod, game)
  ok(type(cancel) == "function", "the editor is handed a way back")

  -- The engine learns the id from the live menu; give it Gold's, so the
  -- fallback path is available and the test can prove it is NOT the one taken.
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = liveStartMenu(game, rows) })
  end

  local pushes = #mod.pushed
  cancel()

  eq(game.opened, 1,
     "the GAME is asked to open its own menu -- which is the only call that "
     .. "supplies onChoose and onClose")
  eq(#mod.pushed, pushes,
     "and the screen id is not pushed behind its back: a bare push builds a "
     .. "menu that opens nothing and does not close")
  eq(#mod.logged, 0, "with nothing to report")
end

do
  io.write("on Gold, when the opener raises\n")
  local mod = install(fakeMod())
  local game = goldGame()
  local cancel, rows = editorCancelFor(mod, game)
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = liveStartMenu(game, rows) })
  end

  game.openStartMenu = function() error("no world") end
  cancel()

  local last = mod.pushed[#mod.pushed]
  eq(last and last.id, "Gen2StartMenu",
     "the learned id is the fallback -- a menu that opens nothing still "
     .. "beats no menu at all")
  ok(#mod.logged > 0, "and the failure is reported rather than swallowed")
end

-- --------------------------------------------- the menu it was opened FROM

do
  io.write("on Gold, the stale menu under the editor\n")
  -- Red's Menu pops itself before a row's onSelect; Gold's StartMenu:choose
  -- does not.  So on Gold the editor opens ON TOP of a live START menu, and a
  -- re-open that does not drop it leaves two identical menus stacked -- B
  -- pops one, the other is still there, and it reads as "you can't close it".
  local mod = install(fakeMod())
  local game = goldGame()

  local cancel, rows = editorCancelFor(mod, game)
  local menu = liveStartMenu(game, rows)
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = menu })
  end
  -- the state of the world when the editor is open: the menu is still under it
  game.stack:push(menu)
  eq(#game.stack.states, 1, "the menu the editor was opened from is on the stack")

  cancel()
  eq(game.opened, 1, "the game opens its own menu")
  eq(#game.stack.states, 1,
     "and there is exactly ONE menu afterwards -- the stale one is dropped "
     .. "rather than left under the new one")
  local top = game.stack:top()
  ok(top ~= menu,
     "and it is the NEW one: the menu under the editor was built from the "
     .. "layout the player just changed, so reusing it would show the old "
     .. "order")
  ok(type(top.onClose) == "function", "which closes")
  ok(type(top.onChoose) == "function", "and opens its rows")
end

do
  io.write("on Gold, the fallback carries the two callbacks\n")
  local mod = install(fakeMod())
  local game = goldGame()
  local cancel, rows = editorCancelFor(mod, game)
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = liveStartMenu(game, rows) })
  end

  game.openStartMenu = function() error("no world") end
  cancel()

  local push = mod.pushed[#mod.pushed]
  eq(push and push.id, "Gen2StartMenu", "the learned id is pushed")
  local opts = push and push.opts
  ok(type(opts) == "table", "with options, not bare")
  ok(opts and type(opts.onChoose) == "function",
     "carrying onChoose, or its rows would open nothing")
  ok(opts and type(opts.onClose) == "function",
     "and onClose, or B and START would not shut it")
  if opts then
    opts.onChoose("pack")
    eq(game.items[1], "pack", "and the synthesized onChoose is the game's own")
  end
end

do
  io.write("on Gold, a menu that arrives with neither\n")
  -- The backstop.  This mod's hook runs on construction, so EVERY Gold start
  -- menu reaches attach() -- whoever pushed it.  A menu with neither callback
  -- cannot be left by any means the player has, so the two nils are filled in
  -- rather than reported and left.
  local mod = install(fakeMod())
  local game = goldGame()
  local _, rows = editorCancelFor(mod, game)
  local inert = { screenId = "Gen2StartMenu", items = rows,
                  update = function() end }
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = inert })
  end
  ok(type(inert.onClose) == "function", "it is given a way out")
  ok(type(inert.onChoose) == "function", "and a way in")
  inert.onChoose("pokedex")
  eq(game.items[1], "pokedex", "wired to the game's own opener")
  ok(#mod.logged >= 2, "and both repairs are reported rather than silent")
end

do
  io.write("on Gold, a menu that arrived properly is left alone\n")
  local mod = install(fakeMod())
  local game = goldGame()
  local _, rows = editorCancelFor(mod, game)
  local menu = liveStartMenu(game, rows)
  local close, choose = menu.onClose, menu.onChoose
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = menu })
  end
  eq(menu.onClose, close, "its own onClose is not replaced")
  eq(menu.onChoose, choose, "nor its onChoose")
  eq(#mod.logged, 0, "and there is nothing to report")
end

-- ---------------------------------------------------------- the row hints

do
  io.write("Gold's row descriptions\n")
  -- Gold's START menu carries a second box in the bottom-left describing the
  -- row under the cursor -- two lines per entry, on every frame the menu is
  -- open.  Red has nothing of the sort.
  local mod = install(fakeMod())
  local game = goldGame()
  local _, rows = editorCancelFor(mod, game)

  local keys = {}
  for _, row in ipairs(mod.rows or {}) do keys[row.key] = row end
  ok(keys.row_hints, "ROW HINTS is offered on Gold")
  eq(keys.row_hints and keys.row_hints.default, false,
     "and it is OFF by default, which is a departure from the cart: the box "
     .. "covers a tenth of the screen and arranging the menu is what this "
     .. "feature is for")

  -- Off: the descriptions go, through the cart's own field.
  local menu = liveStartMenu(game, rows)
  menu.showDescription = true
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = menu })
  end
  eq(menu.showDescription, false,
     "with the row off, the live menu stops drawing them -- the same field "
     .. "Gold's own MENU ACCOUNT sets, read by StartMenu:draw every frame")

  -- On: it stands down rather than forcing them back, so the cart's own
  -- MENU ACCOUNT is still the switch that gives them.
  mod.stored.row_hints = true
  local off = liveStartMenu(game, rows)
  off.showDescription = false
  local on = liveStartMenu(game, rows)
  on.showDescription = true
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = off })
    fn({ state = on })
  end
  eq(off.showDescription, false,
     "with the row ON, a player who turned MENU ACCOUNT off keeps it off")
  eq(on.showDescription, true, "and one who left it on keeps them")
  mod.stored.row_hints = nil
end

-- ------------------------------------------------------------------- Red

do
  io.write("on Red\n")
  package.loaded["src.core.GameVersion"] = {
    generation = function() return 1 end,
  }
  local mod = install(fakeMod())
  local game = redGame()

  local keys = {}
  for _, row in ipairs(mod.rows or {}) do keys[row.key] = row end
  ok(not keys.row_hints,
     "ROW HINTS is not offered, because Red's START menu has no descriptions "
     .. "to turn off and a row that cannot do anything is worse than a "
     .. "missing one")

  local cancel, rows = editorCancelFor(mod, game)
  for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
    fn({ state = { screenId = "StartMenu", items = rows,
                   update = function() end } })
  end

  local pushes = #mod.pushed
  cancel()

  eq(#mod.pushed, pushes + 1, "one screen is pushed")
  local last = mod.pushed[#mod.pushed]
  eq(last and last.id, "StartMenu",
     "and it is the learned id, unchanged -- Red's StartMenu.new takes the "
     .. "game and nothing else, so the bare push IS the engine's own call")
  eq(#mod.logged, 0, "with nothing to report")
end

do
  io.write("before the menu has ever been seen\n")
  -- No screen.pushed yet, so no id has been learned.  On Red that leaves
  -- nothing to do; the point is that it does not raise.
  local mod = install(fakeMod())
  local game = redGame()
  local cancel = editorCancelFor(mod, game)
  local pushes = #mod.pushed
  local fine = pcall(cancel)
  ok(fine, "the way back does not raise with no id learned")
  eq(#mod.pushed, pushes, "and pushes nothing")
end

io.write(("menumanager reopen: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
