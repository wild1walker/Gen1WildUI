-- START > MODS has to reach the suite, on both cartridges.
--
-- With the suite installed, MODS is the door to its settings, not to a list of
-- zips, so runtime/menu.lua retargets that one row.  On Red the retarget is a
-- line: the rows there carry `onSelect` and the engine runs whatever is on the
-- row.  Gold's rows carry a `value` instead, and `StartMenu:choose` dispatches
-- onSelect ONLY when `value == nil` -- so a callback installed beside a live
-- value is read by nobody, and the row keeps going to the cart's own list.
--
-- That is the third place in this suite the same difference has bitten: the
-- menu manager's rows, autosave's QUIT, and this.  So the test is written
-- against the ENGINE's own StartMenu rather than a stub of it -- a stub that
-- dispatches onSelect unconditionally is a stub that agrees with the bug.
--
-- Run:  luajit tests/modsrow_test.lua

package.path = "./?.lua;" .. package.path

-- ---- and the engine tree, which this one test genuinely needs
--
-- Every other test here stubs the engine.  This one cannot: the whole subject
-- is a dispatch rule that lives in `StartMenu:choose`, and a stub written by
-- the same hand that misread the rule would agree with the misreading.  So it
-- loads the cart's own screen, and if the engine is not beside this checkout
-- it says so and stands down rather than passing on a stub.
local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    candidates[#candidates + 1] = prefix .. "/bryanthaboi/gen1recomp"
    candidates[#candidates + 1] = prefix .. "/gen1recomp"
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/StartMenu.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("modsrow: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

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

-- ---- enough LOVE for the menu to build

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

require("src.core.GameVersion").set("gold")

-- ---- the hook bus, wired the way the engine wires it

local chains = {}
local hooks = { chains = chains }
function hooks:call(name, vanilla, ...)
  local chain = chains[name]
  if not chain then return vanilla(...) end
  local function step(i)
    local link = chain[i]
    if not link then return function(...) return vanilla(...) end end
    return function(...) return link.fn(step(i + 1), ...) end
  end
  return step(1)(...)
end
local events = { listeners = {} }
function events:emit() end
require("src.mods.Runtime").install(events, hooks, nil)

-- ---- the retarget, lifted from runtime/menu.lua
--
-- Read out of the shipped file rather than retyped, so an edit there that
-- drops the fix fails here instead of passing against a copy of the old code.

local function shippedRetarget()
  local handle = assert(io.open("runtime/menu.lua"))
  local source = handle:read("*a")
  handle:close()
  -- there is more than one wrap on this hook in the file; the MODS one is
  -- the wrap that mentions rootScreenId
  local body
  for candidate in source:gmatch("mod%.hooks:wrap%(\"ui%.start_menu%.items\".-\n    end%)") do
    if candidate:find("rootScreenId", 1, true) then body = candidate end
  end
  assert(body and body:find("rootScreenId", 1, true),
         "could not find the MODS retarget in runtime/menu.lua")
  return body
end

local opened = 0
local mod = {
  hooks = { wrap = function(_, name, fn, priority)
    chains[name] = chains[name] or {}
    table.insert(chains[name], { fn = fn, priority = priority or 0 })
  end },
  ui = { push = function() opened = opened + 1 end },
}
local rootScreenId = "Gen1WildUiRoot"
local chunk = assert(load(
  "local mod, rootScreenId = ...\n" .. shippedRetarget(),
  "@runtime/menu.lua:MODS"))
chunk(mod, rootScreenId)

-- ---- and a real Gold START menu to press A on

local StartMenu = require("src.ui.gen2.StartMenu")

local function goldMenu()
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  local fellThrough = {}
  local game = {
    stack = stack,
    -- what puts a MODS row on the menu at all (StartMenu:availability)
    modStatus = { available = { { id = "something" } } },
    save = {
      player = { name = "GOLD" }, party = { { species = 1 } },
      engineFlags = {}, inventory = {}, options = {},
    },
  }
  local menu = StartMenu.new(game, {
    save = game.save,
    onChoose = function(id) fellThrough[#fellThrough + 1] = id end,
  })
  stack:push(menu)
  return menu, fellThrough
end

local menu, fellThrough = goldMenu()

local row
for i, item in ipairs(menu.items) do
  if type(item.label) == "string" and item.label:upper() == "MODS" then row = i end
end
ok(row ~= nil, "Gold's menu has a MODS row to retarget")

local item = menu.items[row]
ok(type(item.onSelect) == "function", "the retarget put a callback on it")
eq(item.value, nil, "and cleared the value, which is what Gold dispatches on")

-- press A exactly the way Chrome.List does
menu.list.index = row
menu.list.onChoose(menu.list.items[row].value, row)

eq(opened, 1, "A on MODS opens the suite's own settings")
eq(#fellThrough, 0, "and does not fall through to the cart's list of zips")

-- ---- the row is still the row: place, name, and one retarget only

eq(menu.items[row].label, "MODS", "the entry keeps its name")
ok(row > 1 and row < #menu.items, "and its place in the middle of the menu")
eq(menu.items[row].__gen1wildRouted, true, "flagged, so the other half leaves it be")

-- The flag is the thing that keeps two installed halves from routing twice.
local again = { { label = "MODS", value = "mods", __gen1wildRouted = true } }
local out = hooks:call("ui.start_menu.items", function(_, items) return items end,
                       {}, again)
eq(out[1].value, "mods", "an entry the other half already routed is left alone")
eq(out[1].onSelect, nil, "and not given a second callback")

-- ---- Red is untouched: no value there to clear
--
-- The same wrap, over a Gen 1 shaped row, has to leave a working row working.

local redRow = { label = "MODS", onSelect = function() end }
local red = hooks:call("ui.start_menu.items", function(_, items) return items end,
                       {}, { redRow })
eq(red[1].value, nil, "a Red row has no value before or after")
ok(type(red[1].onSelect) == "function", "and still has a callback to run")

io.write(("modsrow: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
