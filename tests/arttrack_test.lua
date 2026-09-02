-- Recording where the art is, and ringing it, are two different jobs.
--
-- And the ring's own question is narrower than "is this frame a page".  It
-- hides the hairline a raw-blitted rect leaves along its edge -- the renderer
-- scissors each zone and rounds outward, so on a fractional-DPI display the
-- raw re-blit bleeds a sliver of whatever the canvas holds just outside the
-- mark, and inside a box that is the box's own white PAPER.  A page is only
-- one of the two ways to have something shaded under the art; the other is a
-- PANEL, and a battle's move box and the bag's item window over a fight are
-- both panels.
--
-- `watchArt` wraps `markTrueColor` and does both at the same call site, and
-- for a while it did them behind the same `if`: no skirt colour, no entry in
-- the list. That is wrong, and wrong in a way no page-level test could see.
--
-- The LIST is what `withArt` turns into the frame's ART_PAGE zone. Every
-- screen carrying true-colour art needs that zone, whether or not the screen
-- is a page. The RING is the narrower job -- it hides the seam where a
-- raw-blitted mark meets a SHADED page, so it belongs only where there is a
-- page to shade.
--
-- A battle is the case that proves they are different. It owns the frame and
-- is deliberately NOT a page (see battletheme_test.lua), it is full of marked
-- art -- the mon pics, a backdrop -- and it needs its art zone. Gating the
-- list on the skirt dropped that zone and the whole battle came back
-- unthemed: white command boxes on a dark-mode game, reported from a phone.
--
-- Run:  luajit tests/arttrack_test.lua

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

local function load_(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ------------------------------------------------------------- the harness

-- Faithful enough for watchArt, which does not ask whether a mark landed --
-- it OBSERVES, by comparing the engine's own list before and after.
local ui = {}
local FX = {
  honorsTrueColor = function() return true end,
  trueColorRects = function(name) return name == "ui" and ui or {} end,
  markTrueColor = function(x, y, w, h)
    ui[#ui + 1] = { colors = false, x = x, y = y, w = w, h = h }
  end,
  spriteRedrawPassActive = function() return false end,
}
package.preload["src.render.PaletteFX"] = function() return FX end
package.preload["src.render.SpriteRenderer"] = function() return {} end

local fills = 0
_G.love = { graphics = {
  setColor = function() end,
  rectangle = function() fills = fills + 1 end,
  getCanvas = function() end, setCanvas = function() end,
} }

local OakSpeech = {}
OakSpeech.__index = OakSpeech
package.preload["src.ui.OakSpeech"] = function() return OakSpeech end

local Theme = load_("runtime/theme.lua")

local function theme()
  local frame
  local t = Theme.new({
    mod = { id = "ui",
            log = setmetatable({}, { __index = function() return function() end end }),
            hooks = { wrap = function(_, name, fn)
              if name == "render.zones" then frame = fn end
            end },
            events = { on = function() end, once = function() end } },
    optionset = { own = function() end, read = function() return "dark" end,
                  generation = function() return 1 end },
  })
  t.install()
  return t, function(game)
    if frame then pcall(frame, function(_, z) return z end, game, nil) end
  end
end

local function gameWith(states)
  return { stack = { states = states, top = function() return states[#states] end } }
end

io.write("art is recorded wherever it is, and ringed where it has a seam\n")

-- ONE theme for both cases, on purpose. `watchArt` tags PaletteFX and refuses
-- to wrap it twice -- the same guard that stops two bundles double-ringing a
-- mark -- so a second Theme.new here would leave the FIRST theme's wrapper in
-- place and quietly test that one instead.
local t, runFrame = theme()

-- ------------------------------------------------------- a battle
do
  local battle = { isBattle = true, sgbPalettes = function() end }
  local game = gameWith({ battle })
  runFrame(game)                      -- the frame before this one

  fills = 0
  FX.markTrueColor(16, 8, 56, 56)     -- the mon
  Theme.recordBox(0, 12, 10, 6)       -- the command grid

  local out = t.apply(game, nil)
  local art, word, artPage = t.artProbe()

  eq(art, 1, "a battle's marked art is recorded even though it is not a page")
  eq(word, "dark", "and the theme knows it was dark while it happened")
  eq(artPage, false, "the frame is correctly not a page")
  eq(fills, 0, "and no ring is painted, because there is no shaded page")
  ok(out and #out == 3, "the frame keeps its art zone AND its panel")
end

-- ------------------------------------------------------- a page
do
  local page = { gen1wildTheme = true }
  local game = gameWith({ page })
  runFrame(game)

  fills = 0
  FX.markTrueColor(16, 8, 56, 56)

  t.apply(game, { { colors = { { 255, 255, 255 }, { 170, 170, 170 },
                               { 85, 85, 85 }, { 0, 0, 0 } },
                    x = 0, y = 0, w = 160, h = 144 } })
  local art = t.artProbe()
  eq(art, 1, "a page records its art too")
  ok(fills > 0, "and here the ring IS painted -- there is a seam to hide")
end

-- ------------------------------ art standing on a box, on a frame with no page
do
  -- The reported case, twice over: the coloured move type inside a battle's
  -- move box, and an item icon inside the bag's item window while a fight is
  -- underneath.  Neither frame is a page -- the battle owns it and is a
  -- picture -- but both boxes are themed as panels, so the art inside one has
  -- the same seam a page would have given it, and the same ring hides it.
  local battle = { isBattle = true, sgbPalettes = function() end }
  local game = gameWith({ battle })
  runFrame(game)

  -- the box first, the way a screen draws it: paper, then what goes on it
  Theme.recordBox(1, 11, 10, 4)             -- x 8..88, y 88..120
  fills = 0
  FX.markTrueColor(16, 96, 40, 8)           -- the type label, inside it
  ok(fills > 0, "art inside a box on a bare frame is ringed -- the box is a "
    .. "panel, and a panel is shaded")

  fills = 0
  FX.markTrueColor(16, 8, 56, 56)           -- the enemy pic, on the backdrop
  eq(fills, 0, "and the POKeMON on the backdrop is not: no box under it, so "
    .. "no seam to hide")

  t.apply(game, nil)                        -- drain the frame
end

-- ------------------------------------- a box that only clips the art
do
  local battle = { isBattle = true, sgbPalettes = function() end }
  local game = gameWith({ battle })
  runFrame(game)

  Theme.recordBox(0, 12, 20, 6)             -- x 0..160, y 96..144
  fills = 0
  FX.markTrueColor(16, 88, 16, 16)          -- straddles the box's top edge
  eq(fills, 0, "a box the art only overlaps is not what the art is standing "
    .. "on, and does not earn it a ring")

  t.apply(game, nil)
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
