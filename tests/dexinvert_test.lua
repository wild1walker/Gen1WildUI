-- An INVERTED print reads the palette backwards, and the theme has to hand it
-- over pre-reversed.
--
-- Reported against Gold's own Pokedex: every row came out as a WHITE BAR with
-- black dashes in it, on a page that was otherwise correctly dark.
--
-- `invert` is not a decoration on these calls, it is the whole of how that
-- screen is white on black.  Pokedex_LoadInvertedFont xors both bitplanes of
-- the font, so a glyph pixel of shade s arrives as shade 3 - s, and Chrome
-- answers it by reading the palette backwards:
--
--     if invert then pal = { pal[4], pal[3], pal[2], pal[1] } end
--
-- So on an inverted print pal[1] -- the cell printThrough fills behind the
-- string -- is the palette's colour THREE and the glyphs take colour ZERO.
-- Substituting paper into 0 and ink into 3 without knowing that puts the ink
-- in the cell and the paper in the letters: the white-box bug this
-- substitution exists to fix, arriving through the one screen that reads its
-- palette the other way up.
--
-- The reversal is read off the ENGINE here rather than restated, because
-- restating it is exactly the mistake being fixed.
--
-- Run:  luajit tests/dexinvert_test.lua
--       (needs an engine tree; SKIPs without one)

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
    for _, name in ipairs({ "gen1recompog", "gen1recomp", "bryanthaboi/gen1recomp" }) do
      candidates[#candidates + 1] = prefix .. "/" .. name
    end
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/Chrome.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("dexinvert: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end

local function slurp(path)
  local handle = assert(io.open(path), path)
  local text = handle:read("*a")
  handle:close()
  return text
end

-- ---- the reversal, read off the cart

local chromeSrc = slurp(ENGINE .. "/src/ui/gen2/Chrome.lua")
ok(chromeSrc:find("pal = { pal[4], pal[3], pal[2], pal[1] }", 1, true) ~= nil,
   "an inverted print reverses the palette, i -> 5-i")
ok(chromeSrc:find("function Chrome.printThrough(text, tx, ty, palette, invert, raw)",
                  1, true) ~= nil,
   "and `invert` is the argument straight after the palette")
ok(chromeSrc:find("function Chrome.cursorThrough(tx, ty, palette, invert, hollow, raw)",
                  1, true) ~= nil,
   "on the cursor too")

-- The cell behind the string is pal[1], which the reversal makes colour 3.
ok(chromeSrc:find("local paper = pal[1] or { 255, 255, 255 }", 1, true) ~= nil,
   "and the cell printThrough fills is pal[1]")

-- ---- the shipped reshade, lifted

local src = slurp("runtime/theme2.lua")
local body = src:match("(      local function reshade%(palette, invert%).-\n      end)\n")
assert(body, "could not find reshade in runtime/theme2.lua")

local PAPER, INK = { 0, 0, 0 }, { 255, 255, 255 }
local live = { PAPER, PAPER, PAPER, INK }
local vanilla = { { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 } }
local function same(a, b)
  for i = 1, 4 do
    local x, y = a[i], b[i]
    if x[1] ~= y[1] or x[2] ~= y[2] or x[3] ~= y[3] then return false end
  end
  return true
end
local reshade = assert(load(
  "local live, vanilla, same, marked = ...\n" .. body .. "\nreturn reshade",
  "@theme2.lua"))(live, vanilla, same, "gen1wildUnthemed")

-- The dex's own palette: white on black, the cart's.
local DEX = { { 255, 255, 255 }, { 200, 200, 200 }, { 100, 100, 100 }, { 0, 0, 0 } }
local function rgb(c) return ("%d,%d,%d"):format(c[1], c[2], c[3]) end
-- What the engine does to a palette on the way in.
local function reversed(p) return { p[4], p[3], p[2], p[1] } end

do
  -- A NORMAL print: no reversal, so the cell is entry 1 and the glyphs are 4.
  local out = reshade(DEX, nil)
  eq(rgb(out[1]), rgb(PAPER), "normal: the cell is the theme's paper")
  eq(rgb(out[4]), rgb(INK), "normal: the glyphs are the theme's ink")
end

do
  -- An INVERTED print: the engine reverses what it is handed, so what matters
  -- is the palette AFTER that reversal.
  local out = reversed(reshade(DEX, true))
  eq(rgb(out[1]), rgb(PAPER),
     "inverted: after the cart's own reversal the cell is still the paper")
  eq(rgb(out[4]), rgb(INK),
     "inverted: and the glyphs are still the ink")
end

do
  -- The bug, stated: reshading without the flag, then letting the cart
  -- reverse it, is a WHITE cell with BLACK letters -- the white bar.
  local naive = reversed(reshade(DEX, nil))
  eq(rgb(naive[1]), rgb(INK),
     "ignoring the flag puts the INK in the cell, which is the white bar")
  eq(rgb(naive[4]), rgb(PAPER), "and the paper in the letters")
end

do
  -- LIGHT is the cart back, both ways round.
  local lightLive = { { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 } }
  local r = assert(load("local live, vanilla, same, marked = ...\n" .. body
    .. "\nreturn reshade", "@theme2.lua"))(lightLive, vanilla, same, "gen1wildUnthemed")
  eq(r(DEX, true), DEX, "LIGHT hands an inverted palette straight back")
  eq(r(DEX, nil), DEX, "and a normal one")
end

do
  -- A palette that has opted out stays opted out either way round.
  local out = { { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 }, { 4, 4, 4 },
                gen1wildUnthemed = true }
  eq(reshade(out, true), out, "an unthemed palette is untouched when inverted")
  eq(reshade(out, nil), out, "and when not")
end

-- ---- and the wraps actually pass the flag on

for _, name in ipairs({ "printThrough", "printRightThrough", "cursorThrough" }) do
  ok(src:find("reshade(palette, invert)", 1, true) ~= nil,
     "the wraps hand `invert` to the reshade")
  ok(src:find("Chrome." .. name .. " = function", 1, true) ~= nil,
     name .. " is wrapped")
end

io.write(("dexinvert: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
