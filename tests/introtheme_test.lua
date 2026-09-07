-- The intro goes dark, page and portraits, checked against the CART's own
-- OakSpeech.
--
-- Reported as "Prof Oak speech isn't dark mode" -- the same complaint the Gen 1
-- arm already answers for `src.ui.OakSpeech`, arriving on Gold.
--
-- This one is engine-backed rather than stubbed, because the whole fix turns
-- on two things the cart owns and a stub would simply agree with:
--
--   * `OakSpeech:drawPanel` opens with a HARDCODED white fill, not a palette,
--     so the PAGE_MODULES entry alone cannot reach it;
--   * its portraits go through `GbcPalette.with`, whose shade 0 is opaque and
--     white for a trainer palette, so on a dark page they arrive on a white
--     plate unless the draw is keyed.
--
-- Both are read off the engine here.  If a later engine gives the screen a
-- named paper seam, or draws its pics keyed already, the assertions below are
-- what say so.
--
-- Run:  luajit tests/introtheme_test.lua

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
      local probe = io.open(dir .. "/src/ui/gen2/OakSpeech.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("introtheme: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

-- ---- a recording canvas

local noop = function() end
local painted = {}   -- every rectangle drawn, with the colour standing at the time
local colour = { 1, 1, 1, 1 }

_G.love = {
  timer = { getTime = function() return 0 end },
  audio = {},
  window = { getMode = function() return 160, 144 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = setmetatable({}, { __index = function() return noop end }),
}
love.graphics.setColor = function(r, g, b, a) colour = { r, g, b, a or 1 } end
love.graphics.getColor = function() return colour[1], colour[2], colour[3], colour[4] end
love.graphics.rectangle = function(mode, x, y, w, h)
  painted[#painted + 1] = {
    mode = mode, x = x, y = y, w = w, h = h,
    r = colour[1], g = colour[2], b = colour[3],
  }
end
for _, name in ipairs({ "getShader", "getCanvas", "getScissor", "getFont" }) do
  love.graphics[name] = function() return nil end
end
love.graphics.newQuad = function() return {} end

require("src.core.GameVersion").set("crystal")

local function chunkOf(path)
  local handle = assert(io.open(path))
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local Theme2 = chunkOf("runtime/theme2.lua")
local Chrome = require("src.ui.gen2.Chrome")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local TextBox = require("src.render.TextBox")
local GbcPalette = require("src.render.GbcPalette")

-- ---- the two shapes the fix rests on, read off the engine

do
  local named = false
  for _, path in ipairs(Theme2.PAGES) do
    if path == "src.ui.gen2.OakSpeech" then named = true end
  end
  ok(named, "the intro is on the themed list")

  -- It owns the frame, which is why nothing else can paint under it.
  eq(OakSpeech.isOpaque, true, "and it is an opaque page, not an overlay")

  -- The seam the ground wrap needs: a full-page fill and no paper accessor.
  eq(type(OakSpeech.drawPanel), "function", "drawPanel is where the page is painted")
  eq(OakSpeech.paperColor, nil,
     "and there is no named paper seam to wrap instead")

  -- The seam the portrait wrap needs.
  eq(type(GbcPalette.with), "function", "GbcPalette.with is the plain remap")
  eq(type(GbcPalette.keyedWith), "function", "and keyedWith is the same draw, keyed")
end

-- ---- the theme

local stored = { ui_theme = "dark" }
local wrapped = {}
local mod = {
  id = "gen1_wild_ui",
  log = setmetatable({}, { __index = function() return noop end }),
  hooks = { wrap = function(_, name, fn) wrapped[name] = fn end },
  events = { on = noop, once = noop },
}
local optionset = {
  generation = function() return 2 end,
  read = function(_, key) return stored[key] end,
  write = function(_, key, value) stored[key] = value; return true end,
  own = noop,
}
Theme2.forgetClasses()
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

local speech = setmetatable({}, OakSpeech)
local page = setmetatable({}, TextBox)
local function tick(states)
  return frame(function() end, { stack = { states = states } }, 1 / 60)
end

-- ---- the walk: the speech is a page, and the box it speaks through is not

eq(palette(), WHITE, "the cart's own palette to begin with")
tick({ speech })
eq(palette(), DARK, "the speech alone goes dark")
-- OakSpeech:sayText pushes a TextBox for every line Oak says, so this is the
-- stack for all but a handful of the intro's frames.
tick({ speech, page })
eq(palette(), DARK,
   "and so does the page Oak is read on -- the walk steps over the text box "
   .. "and finds the speech underneath")

-- ---- the ground

local function groundOf()
  painted = {}
  OakSpeech.drawPanel(setmetatable({}, OakSpeech))
  for _, r in ipairs(painted) do
    if r.mode == "fill" and r.x == 0 and r.y == 0 and r.w == 160 and r.h == 144 then
      return ("%.3f,%.3f,%.3f"):format(r.r, r.g, r.b)
    end
  end
  return "no full-page fill"
end

tick({ speech })
eq(groundOf(), "0.000,0.000,0.000",
   "the page behind Oak is the theme's paper, not the cart's white")

-- ---- the portraits
--
-- Observed from inside the call: drawPic asks the pic for its dimensions
-- before it reaches GbcPalette, so this is the remap that will be in force.

local seen
local pic = { getDimensions = function()
  seen = (GbcPalette.with == GbcPalette.keyedWith) and "keyed" or "plain"
  return 56, 56
end }

local function remapDuring(name)
  seen = nil
  OakSpeech[name](setmetatable({ pic = pic, picColors = {},
    playerIcon = { image = pic, colors = {} } }, OakSpeech))
  return seen
end

tick({ speech })
eq(remapDuring("drawPic"), "keyed",
   "Oak is drawn with shade 0 keyed out, so the page carries it and not a "
   .. "white plate")

-- ---- and LIGHT is the cart back, all three

stored.ui_theme = "light"
tick({ speech, page })
eq(palette(), WHITE, "LIGHT puts the palette back")
eq(groundOf(), "1.000,1.000,1.000", "and the page behind Oak is white again")
eq(remapDuring("drawPic"), "plain", "and his portrait is the cart's own remap")

io.write(("introtheme: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
