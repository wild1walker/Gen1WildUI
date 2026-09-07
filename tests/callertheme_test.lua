-- A phone call goes dark, checked against the CART's own classes.
--
-- tests/theme2_test.lua already covers this with stubs, and stubs are the
-- right tool there -- the walk is the subject and a stub states it exactly.
-- This file is the other half: it loads `src.ui.gen2.CallerBox` and
-- `src.render.TextBox` for real, builds the stack a call actually makes, and
-- runs the shipped theme over it.
--
-- The reason is that everything about this fix is a claim about SHAPES the
-- engine owns, and a stub cannot be wrong about them in the same direction the
-- code is:
--
--   * the caller strip is pushed as a stack state, so `pageOf` can see it;
--   * its metatable is the module the themed list names, so the match lands;
--   * the text page a call is read on is `src.render.TextBox`, which the
--     furniture list names -- so the walk steps over it and finds the strip
--     underneath rather than stopping there.
--
-- If the cart ever moves any of those, the stub test keeps passing and this
-- one does not.
--
-- Run:  luajit tests/callertheme_test.lua

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

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    candidates[#candidates + 1] = prefix .. "/bryanthaboi/gen1recomp"
    candidates[#candidates + 1] = prefix .. "/gen1recomp"
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/CallerBox.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("callertheme: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

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

local function chunkOf(path)
  local handle = assert(io.open(path))
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local Theme2 = chunkOf("runtime/theme2.lua")
local Chrome = require("src.ui.gen2.Chrome")
local CallerBox = require("src.ui.gen2.CallerBox")
local TextBox = require("src.render.TextBox")

-- ---- the three shapes the fix rests on

do
  local named = false
  for _, path in ipairs(Theme2.PAGES) do
    if path == "src.ui.gen2.CallerBox" then named = true end
  end
  ok(named, "the caller strip is on the themed list")

  local box = CallerBox.new("PROF.ELM", nil)
  eq(getmetatable(box), CallerBox,
     "and a real one wears that module as its metatable")
  eq(box.isOpaque, false,
     "it is a strip over the world, not a page that owns the screen")
end

-- ---- the theme, run over the stack a call actually makes

local stored = { ui_theme = "dark" }
local wrapped = {}
local mod = {
  id = "gen1_wild_ui",
  log = setmetatable({}, { __index = function() return noop end }),
  hooks = { wrap = function(_, name, fn) wrapped[name] = fn end },
  events = { on = noop, once = noop },
}
local optionset = {
  generation = function() return 1 end,
  read = function(_, key) return stored[key] end,
  write = function(_, key, value) stored[key] = value; return true end,
  own = noop,
}
local theme = Theme2.new({ mod = mod, optionset = optionset })
theme.install()
local frame = wrapped["core.update"]
ok(frame ~= nil, "the theme wrapped the frame")

local function palette()
  local out = {}
  for i = 1, 4 do
    local c = Chrome.DEFAULT_BOX_PALETTE[i]
    out[i] = ("%d,%d,%d"):format(c[1], c[2], c[3])
  end
  return table.concat(out, " | ")
end
local WHITE = "255,255,255 | 255,255,255 | 255,255,255 | 0,0,0"
local DARK = "0,0,0 | 0,0,0 | 0,0,0 | 255,255,255"

local strip = CallerBox.new("PROF.ELM", nil)
local page = setmetatable({}, TextBox)
local function tick(states)
  return frame(function() end, { stack = { states = states } }, 1 / 60)
end

eq(palette(), WHITE, "the cart's own palette to begin with")

-- RingTwice_StartCall pushes the strip; the RING page comes after it.
tick({ strip })
eq(palette(), DARK, "the strip alone goes dark")

tick({ strip, page })
eq(palette(), DARK,
   "and so does the RING page that is read over it -- the walk steps over the "
   .. "text box and finds the strip underneath")

-- The page the call's own script prints, after the strip has been taken down.
tick({ page })
eq(palette(), DARK,
   "a text page left over the world is themed too: the walk carries it")

tick({})
eq(palette(), WHITE, "and a bare overworld is left exactly alone")

stored.ui_theme = "light"
tick({ strip, page })
eq(palette(), WHITE, "LIGHT is the cart's call back, both boxes")

io.write(("callertheme: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
