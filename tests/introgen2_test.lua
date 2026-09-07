-- FLASHLESS INTROS and BLACK OUTRO on Gold, against the cart's own classes.
--
-- Both settings existed only on Red until now, and both had to find a
-- different seam on Gold, so this file loads the engine rather than a stub of
-- it: the whole question is what Gold's BattleTransition and World actually
-- do, and a stub is just this file agreeing with itself.
--
-- FLASHLESS INTROS.  On Red the flash is a property of the wipe, so the
-- setting is a `transition.style` hook naming the Champion's spiral.  Gold
-- does not work that way: the flash is a PHASE (`self.phase = self.trainer
-- and "pokeball" or "flash"`) and every one of its four wipes -- spin,
-- speckle, zoom, sine -- runs after it.  So the style hook is the wrong
-- lever there twice over: it would change the wipe and leave the flash, and
-- Red's "spiralout" is not one of the four anyway.  The arm shortens the
-- phase instead.
--
-- BLACK OUTRO.  Gold's return is `World:battleReturnFade`, which sets
-- `self.fade = "white"` and lets the map setup chain ramp it off.
-- `World.FADE_RAMP` already carries a `black` ramp beside the white one, so
-- the arm names the other ramp rather than drawing anything.
--
-- Run:  luajit tests/introgen2_test.lua

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

-- ---- the engine, or nothing
--
-- Same lookup as tests/modsrow_test.lua: this is one of the few tests here
-- that genuinely needs the cart's own code, and it stands down rather than
-- passing on a stub if the engine is not beside this checkout.

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    candidates[#candidates + 1] = prefix .. "/bryanthaboi/gen1recomp"
    candidates[#candidates + 1] = prefix .. "/gen1recomp"
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/BattleTransition.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("introgen2: SKIPPED -- no engine tree found "
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
love.math = { random = function(n) return n and 1 or 0 end }

require("src.core.GameVersion").set("gold")

-- ---- the two arms, read out of the shipped module
--
-- Lifted rather than retyped, so an edit that drops either one fails here.

local function shipped(what)
  local handle = assert(io.open("modules/WidescreenBattleIntro/main.lua"))
  local source = handle:read("*a")
  handle:close()
  local body = source:match("(local function " .. what .. "%(.-\n end)\n")
    or source:match("(local function " .. what .. "%(.-\nend)\n")
  assert(body, "could not find " .. what .. " in the module")
  return assert(load(body .. "\nreturn " .. what, "@" .. what))()
end

local installGen2Flashless = shipped("installGen2Flashless")
local installGen2Outro = shipped("installGen2Outro")

-- ---- FLASHLESS INTROS

local Transition = require("src.ui.gen2.BattleTransition")

-- What the cart does, before anything is installed.
local vanillaFrames = Transition.flashFrames
ok(type(vanillaFrames) == "function", "Gold has a flash phase to shorten")

-- The style hook is the WRONG lever here, and this is why: Red's flashless
-- style is not one of Gold's four, so naming it changes nothing.
eq(Transition.STYLES["spiralout"], nil,
   "Red's flashless style does not exist on Gold")
ok(Transition.STYLES.spin and Transition.STYLES.speckle
   and Transition.STYLES.zoom and Transition.STYLES.sine,
   "Gold's four wipes are the only styles it answers to")

local wanted = false
local installed = installGen2Flashless(function() return wanted end)
eq(installed, true, "the flashless arm installs on Gold")

-- A transition object thin enough to ask the question of: flashFrames reads
-- only `self.dark`, so that is all it needs.
local lit = setmetatable({ dark = false }, { __index = Transition })
local dark = setmetatable({ dark = true }, { __index = Transition })

wanted = false
eq(lit:flashFrames(), Transition.FLASH_FRAMES,
   "OFF: the full flash, exactly as the cart plays it")
eq(dark:flashFrames(), Transition.FLASH_CYCLES,
   "OFF: and the short flash in darkness, also the cart's")

wanted = true
eq(lit:flashFrames(), 0, "ON: no flash frames at all")
eq(dark:flashFrames(), 0, "ON: in darkness too")

wanted = false
eq(lit:flashFrames(), Transition.FLASH_FRAMES,
   "and the toggle is live -- flipping it back needs no relaunch")

-- Installing twice must not stack a second wrap.
eq(installGen2Flashless(function() return true end), true,
   "a second install is a no-op")
wanted = false
eq(lit:flashFrames(), Transition.FLASH_FRAMES,
   "and did not leave a second wrap reading a different toggle")

-- ---- BLACK OUTRO

local World = require("src.world.gen2.World")

ok(type(World.FADE_RAMP) == "table" and World.FADE_RAMP.black,
   "the cart already has a black ramp beside its white one")

local outroOn = false
eq(installGen2Outro(function() return outroOn end), true,
   "the outro arm installs on Gold")

-- The engine's own battleReturnFade, on a World stripped to the fields it
-- writes.  `mapSetup` nil is what it checks before starting one.
local function returned()
  local w = setmetatable({ mapSetup = nil }, { __index = World })
  w:battleReturnFade()
  return w
end

outroOn = false
local white = returned()
eq(white.fade, "white", "OFF: the cart's white return, untouched")
ok(white.mapSetup ~= nil, "and the engine really did start the fade")

outroOn = true
local black = returned()
eq(black.fade, "black", "ON: the same fade, on the black ramp")
eq(black.fadeLevel, 1, "with the engine's own level, not one of ours")
ok(black.mapSetup ~= nil and black.mapSetup.phase == "in",
   "and the engine's own map-setup chain still drives it")
ok(World.fadeRampRow("black", 1) ~= nil,
   "which the renderer can resolve to a real ramp row")

-- A fade this call did not start is not ours to recolour: battleReturnFade
-- returns early when a map setup is already running.
outroOn = true
local busy = setmetatable({ mapSetup = { phase = "out" }, fade = "white" },
                          { __index = World })
busy:battleReturnFade()
eq(busy.fade, "white", "a fade already running is left alone")

eq(installGen2Outro(function() return true end), true,
   "a second install is a no-op here too")
outroOn = false
eq(returned().fade, "white", "and did not stack a second wrap")

io.write(("introgen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
