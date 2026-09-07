-- The Gold dex draws in the THEME's paper and ink, not literal white on black.
--
-- Reported against the dex list and the entry: "in dark mode those words should
-- just be white, not in white boxes ... the words on the black should be white
-- font".
--
-- Every screen in Gen1Dex draws through two colours in chrome.lua -- `C.black`
-- for the ink and `C.white` for the paper -- and both were literal.  On Red
-- that is right: its theme reverses the WHOLE FRAME afterwards through the SGB
-- zone list, so reading a palette here would reverse them twice.  Gold has no
-- such pass; its colour is per tile out of `Chrome.DEFAULT_BOX_PALETTE`, which
-- the theme rewrites in place.  So the page went dark and every label arrived
-- as a white box with black letters -- `Font.drawBox` fills its interior white
-- and `C.black` printed on top of it.
--
-- The palette is read LIVE, because the theme rewrites those four numbers on
-- core.update: a row drawn this frame has to ask this frame.  That is what the
-- second half of this file pins.
--
-- Run:  luajit tests/dexchrome_test.lua

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

local noop = function() end
local colour, boxes = nil, {}
_G.love = {
  graphics = setmetatable({}, { __index = function() return noop end }),
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  audio = {},
  window = { getMode = function() return 160, 144 end },
}
love.graphics.setColor = function(r, g, b, a) colour = { r, g, b, a } end
love.graphics.rectangle = noop

-- The engine's Font, in the one respect this file is about: drawBox takes a
-- `fill` for its interior and defaults it to WHITE.
package.loaded["src.render.Font"] = {
  draw = noop, drawCode = noop, split = function() return nil end,
  drawBox = function(tx, ty, tw, th, fill)
    boxes[#boxes + 1] = { tx = tx, ty = ty, fill = fill or { 255, 255, 255 } }
  end,
  BORDER = {},
}
package.loaded["src.ui.Theme"] = { cursor = "CURSOR", cursorHollow = "HOLLOW" }
package.loaded["src.core.Strings"] = setmetatable({ source = function(s) return s end },
  { __call = function(_, s) return s end })

-- Gold's Chrome, with the one table the theme rewrites in place.
local LIGHT = { { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 } }
local DARK  = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 255, 255, 255 } }
local box = {}
local function setPalette(from)
  for i = 1, 4 do box[i] = { from[i][1], from[i][2], from[i][3] } end
end
setPalette(LIGHT)
package.loaded["src.ui.gen2.Chrome"] = { DEFAULT_BOX_PALETTE = box }

local function slurp(path)
  local handle = assert(io.open(path), path)
  local text = handle:read("*a")
  handle:close()
  return text
end
local makeChrome = assert(load(slurp("modules/Gen1Dex/chrome.lua"),
                               "@Gen1Dex/chrome.lua"))()
local mod = { path = "modules/Gen1Dex", log = { info = noop, warn = noop },
              options = { get = function() return nil end } }

local function rgb(c)
  if not c then return "nil" end
  return ("%.2f,%.2f,%.2f"):format(c[1], c[2], c[3])
end

-- ---- Red: literal, because its theme reverses the frame after the fact

do
  local C = makeChrome(mod)
  C.black()
  eq(rgb(colour), "0.00,0.00,0.00", "on Red the ink is black")
  C.white()
  eq(rgb(colour), "1.00,1.00,1.00", "and the paper is white")
  boxes = {}
  C.headerBox()
  eq(rgb(boxes[1] and boxes[1].fill), "255.00,255.00,255.00",
     "and a box interior is white -- reading a palette here would reverse twice")
  -- Even with a dark palette sitting in Chrome, the Gen 1 arm must not read it.
  setPalette(DARK)
  C.black()
  eq(rgb(colour), "0.00,0.00,0.00", "a dark Gold palette does not reach Red")
  setPalette(LIGHT)
end

-- ---- Gold: through the palette the theme rewrites

do
  local C = makeChrome(mod, true)
  setPalette(LIGHT)
  C.black()
  eq(rgb(colour), "0.00,0.00,0.00", "on LIGHT the ink is still black")
  C.white()
  eq(rgb(colour), "1.00,1.00,1.00", "and the paper still white -- the cart's own")

  setPalette(DARK)
  C.black()
  eq(rgb(colour), "1.00,1.00,1.00",
     "on DARK the ink is WHITE, so words on the black are white")
  C.white()
  eq(rgb(colour), "0.00,0.00,0.00", "and the paper is black")

  boxes = {}
  C.headerBox()
  C.footerBox()
  eq(#boxes, 2, "both boxes are drawn")
  eq(rgb(boxes[1].fill), "0.00,0.00,0.00",
     "the header box's interior is the PAGE, not a white slab behind the title")
  eq(rgb(boxes[2].fill), "0.00,0.00,0.00", "and so is the footer's")
  -- The ink is what stands after a box, so the next label is not paper on paper.
  eq(rgb(colour), "1.00,1.00,1.00", "and the ink is left standing after it")

  -- LIVE: the theme rewrites those four numbers every frame, so a chrome built
  -- once has to follow them rather than having copied them at build.
  setPalette(LIGHT)
  C.black()
  eq(rgb(colour), "0.00,0.00,0.00", "the palette is re-read, not copied at build")
  boxes = {}
  C.headerBox()
  eq(rgb(boxes[1].fill), "255.00,255.00,255.00", "boxes follow it back too")
end

-- ---- and a build with no Gold Chrome at all falls back rather than failing

do
  local saved = package.loaded["src.ui.gen2.Chrome"]
  package.loaded["src.ui.gen2.Chrome"] = nil
  local C = makeChrome(mod, true)
  C.black()
  eq(rgb(colour), "0.00,0.00,0.00", "with no Chrome to read, black is black again")
  package.loaded["src.ui.gen2.Chrome"] = saved
end

io.write(("dexchrome: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
