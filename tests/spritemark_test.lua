-- The pale box with the black ring, drawn round the player on the way into a
-- battle -- in DARK, in ADVANCED, and nowhere else.
--
-- `SpriteRenderer:draw` reports a trueColor rect for full-colour sprite art,
-- in whichever pass is current.  The battle transition is a stack state, so it
-- runs under the UI pass, and it draws the whole overworld -- sprites and all
-- -- onto the UI canvas.  Every character's cell lands in the UI rect list
-- from inside the wipe, where the renderer re-blits it raw and this theme
-- paints a ring round it.
--
-- Run:  luajit tests/spritemark_test.lua

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
local function load_(path, ...)
  return assert(load(assert(readFile(path)), "@" .. path))(...)
end

package.loaded["src.mods.ManagerState"] = { openOptions = function() end }

-- PaletteFX as the engine has it, cut down to the trueColor plumbing: a rect
-- list per pass, the mark that appends to the current one, and the question
-- the theme asks about which pass is running.
local PaletteFX = {}
local rects = { ui = {}, world = {} }
local currentPass = nil
function PaletteFX.setPass(name) currentPass = rects[name] and name or nil end
function PaletteFX.trueColorRects(name) return rects[name] or {} end
function PaletteFX.spriteRedrawPassActive() return currentPass == "world" end
function PaletteFX.honorsTrueColor() return true end
function PaletteFX.markTrueColor(x, y, w, h)
  local list = currentPass and rects[currentPass]
  if not list or w <= 0 or h <= 0 then return end
  list[#list + 1] = { colors = false, x = x, y = y, w = w, h = h }
end
package.loaded["src.render.PaletteFX"] = PaletteFX

-- SpriteRenderer, cut down to the one line that matters: a full-colour sprite
-- claims the cell it drew.
local SpriteRenderer = {}
function SpriteRenderer.draw(_, x, y) PaletteFX.markTrueColor(x, y, 16, 16) end
function SpriteRenderer.drawTile(_, _, x, y) PaletteFX.markTrueColor(x, y, 16, 8) end
package.loaded["src.render.SpriteRenderer"] = SpriteRenderer

-- Enough of love.graphics to watch the ring paint itself.
local fills = {}
love = {
  graphics = {
    setColor = function() end,
    rectangle = function(_, x, y, w, h)
      fills[#fills + 1] = { x = x, y = y, w = w, h = h }
    end,
  },
}

local OptionSet = load_("runtime/optionset.lua")
local Theme = load_("runtime/theme.lua")

local stored = {}
local lastFrame

local mod = {
  id = "ui",
  options = { define = function() end,
              get = function(_, key) return stored[key] end,
              set = function(_, key, value) stored[key] = value end },
  log = { info = function() end, warn = function() end, error = function() end },
  hooks = { wrap = function(_, name, fn)
    if name == "render.zones" then lastFrame = fn end
  end },
}
local theme = Theme.new({ mod = mod, optionset = OptionSet.new() })
theme.defineRow()
theme.write("dark")
theme.install()

-- The frame this file is about is a PAGE: "a page's art is untouched, it is
-- what the ring is for".  A skirt hides the seam between a raw-blitted mark
-- and a SHADED page, so it is painted where there is a page and nowhere else
-- -- and the screen has to be said out loud for the ring to be asked for.
do
  local page = { gen1wildTheme = true }
  if lastFrame then
    pcall(lastFrame, function(_, zones) return zones end,
          { stack = { states = { page }, top = function() return page end } },
          nil)
  end
end

local function reset()
  for _, list in pairs(rects) do
    for i = #list, 1, -1 do list[i] = nil end
  end
  for i = #fills, 1, -1 do fills[i] = nil end
  local shared = rawget(PaletteFX, "__gen1WildArtRects")
  if shared then for i = #shared, 1, -1 do shared[i] = nil end end
end

-- ------------------------------------------------- the rule, without the game

do
  io.write("a sprite cell outside the world pass is not a page's art\n")
  ok(Theme.dropsSpriteMark(1, false),
     "a mark from inside a sprite draw, in the UI pass, is dropped")
  ok(not Theme.dropsSpriteMark(1, true),
     "the same mark on the map is the one the rect was written for")
  ok(not Theme.dropsSpriteMark(0, false),
     "a page's own art in the UI pass is untouched -- that IS the seam")
  ok(not Theme.dropsSpriteMark(nil, false),
     "and an engine that cannot count sprite draws keeps every mark")
end

-- ------------------------------------------------------------- the wipe

do
  io.write("the battle transition draws the map under the UI pass\n")
  reset()
  PaletteFX.setPass("ui")
  SpriteRenderer.draw(nil, 72, 64)
  eq(#rects.ui, 0, "the player's cell never becomes a UI zone")
  eq(#fills, 0, "so there is no ring to paint round it")

  reset()
  PaletteFX.setPass("ui")
  SpriteRenderer.drawTile(nil, "fx.png", 72, 64)
  eq(#rects.ui, 0, "a loose fx tile is the same sprite and the same answer")
end

-- ------------------------------------------------------------- the map

do
  io.write("on the map the mark is doing its job and is left alone\n")
  reset()
  PaletteFX.setPass("world")
  SpriteRenderer.draw(nil, 72, 64)
  eq(#rects.world, 1, "a full-colour sprite still claims its cell")
  eq(rects.world[1].x, 72, "at the coordinates it drew at")
  eq(#fills, 0, "and the world pass has no seam, so still no ring")
end

-- -------------------------------------------------------- a page's own art

do
  io.write("a page's art is untouched: it is what the ring is for\n")
  reset()
  PaletteFX.setPass("ui")
  PaletteFX.markTrueColor(48, 24, 56, 56)
  eq(#rects.ui, 1, "the mark goes through")
  ok(#fills > 0, "and DARK paints its ring round it")
end

-- -------------------------------------------- and the counter always unwinds

do
  io.write("the sprite counter comes back down\n")
  reset()
  PaletteFX.setPass("ui")
  SpriteRenderer.draw(nil, 8, 8)
  PaletteFX.markTrueColor(48, 24, 56, 56)
  eq(#rects.ui, 1,
     "a mark after a sprite draw has finished is a page's art again")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
