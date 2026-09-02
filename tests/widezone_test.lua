-- Where the GB frame is, and who is allowed to ask loosely.
--
-- A classic 160x144 screen opened over a WIDE battle is CENTRED by the engine
-- before the render.zones hook sees anything: Game.lua computes
-- classicOffset = (uiWidth - 160) / 2 and runs centerClassicZones over the
-- zone owner's list.  So a page's own whole-screen zone arrives at x = 72.
-- Demanding x = 0 made every such page fall through to a synthesised zone
-- built at 0 -- themed at 0..160 while drawn at 72..232.
--
-- 0.32.9 fixed that by widening the one test both callers shared, and broke
-- battles: `basePage` is a GUESS made when nothing on the stack claimed to be
-- a page, and a guess that accepts a 160-wide band at any x will accept a
-- band belonging to a picture.  See tests/battletheme_test.lua.
--
-- So there are two questions now and this file is about the line between them.
--
-- Run:  luajit tests/widezone_test.lua

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

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

local Theme = load_("runtime/theme.lua")

-- The engine's own arithmetic, quoted (src/core/Game.lua).
local function classicOffset(width) return math.floor((width - 160) / 2) end

local atOrigin = { x = 0, y = 0, w = 160, h = 144 }
local centred  = { x = 72, y = 0, w = 160, h = 144 }

io.write("the offset the engine applies\n")
eq(classicOffset(304), 72, "a wide battle centres a classic screen by 72")
eq(classicOffset(160), 0, "and a classic frame does not move it")

io.write("the STRICT question, which basePage asks\n")
do
  ok(Theme.isWhole(atOrigin), "the frame at the origin is the whole frame")
  ok(not Theme.isWhole(centred),
     "and a centred one is NOT -- basePage is a guess and must stay narrow")
  ok(not Theme.isWhole({ x = 0, y = 0, w = 304, h = 144 }),
     "a wide battle's own zone is not the GB frame")
end

io.write("the LOOSE question, which only pageZones asks\n")
do
  ok(type(Theme.wholeAt) == "function", "wholeAt is published")
  eq(Theme.wholeAt(atOrigin), 0, "the frame at the origin is found, at 0")
  eq(Theme.wholeAt(centred), 72, "and the centred one is found, at 72")

  eq(Theme.wholeAt({ x = 0, y = 0, w = 304, h = 144 }), nil,
     "a 304-wide list is not the GB frame at any x")
  eq(Theme.wholeAt({ x = 0, y = 8, w = 160, h = 136 }), nil,
     "nor is a band inside one")
  eq(Theme.wholeAt({ x = 0, y = 0, w = 160 }), nil, "nor a zone missing a side")
  eq(Theme.wholeAt(nil), nil, "and nothing is nothing")
  eq(Theme.wholeAt({ x = "72", y = 0, w = 160, h = 144 }), nil,
     "nor a zone whose x is not a number")
end

io.write("and the two do not collapse back into one\n")
do
  -- The property 0.32.9 lost.  If these ever agree on the centred frame, a
  -- picture can be guessed into a page again.
  ok(Theme.wholeAt(centred) ~= nil and not Theme.isWhole(centred),
     "loose finds the centred frame; strict refuses it")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
