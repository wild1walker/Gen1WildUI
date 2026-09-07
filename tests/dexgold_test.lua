-- Gold's dex: 251 entries, opening on Johto, and a SELECT cycle with a way back.
--
-- All three were reported together -- "Pokedex is still only going to 151
-- instead of the full dex and it's not starting at 152 and when you use the
-- sorting you can't go back to normal unless you close it" -- and all three
-- come off two wrong reads of the CART's data:
--
--   * the dex bound was taken from `constants.dexSize`.  A Gold boot never
--     loads src/core/Data.lua, which is the only thing that derives that key,
--     and `data.gen2Constants` -- the table an earlier "fix" preferred -- is
--     the cart's ordered NAME LISTS and has no `dexSize` at all.  So the list
--     stopped at the `or 151` fallback, and #152 was not in it to open on.
--
--   * the dex save was handed over raw.  Red names the caught half `owned`;
--     Gold names it `caught` (PokedexMenu:rebuild reads `pokedex.caught`).
--     So nothing was ever owned, CAUGHT was always empty, and SELECT would not
--     step into an empty view -- stranding the cycle on A-Z.
--
-- So this file reads the shapes off the ENGINE rather than restating them: the
-- roster's real size, the real key `newOrder`, and the real name of the caught
-- table.  A stub would have agreed with both mistakes.
--
-- Run:  luajit tests/dexgold_test.lua
--       (needs an engine tree for the manifest; SKIPs without one)

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
      local probe = io.open(dir .. "/src/ui/gen2/PokedexMenu.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("dexgold: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end

local function slurp(path)
  local handle = assert(io.open(path), path)
  local text = handle:read("*a")
  handle:close()
  return text
end

-- ---- the shapes, read off the cart

local dexSource = slurp(ENGINE .. "/src/ui/gen2/PokedexMenu.lua")
ok(dexSource:find("save.pokedex.caught", 1, true) ~= nil,
   "the cart's dex screen reads pokedex.CAUGHT, not pokedex.owned")
ok(dexSource:find("dex.newOrder", 1, true) ~= nil,
   "and `newOrder` is the Johto order it opens on")
ok(dexSource:find("constants.dexSize", 1, true) == nil,
   "the cart's dex never counts to a dexSize constant -- it walks its entries")

local manifest = slurp(ENGINE .. "/tools/rom_manifest_gold.json")
local speciesCount = 0
do
  local body = manifest:match('"speciesOrder"%s*:%s*%[(.-)%]')
  assert(body, "speciesOrder not in rom_manifest_gold.json")
  for _ in body:gmatch('"[^"]*"') do speciesCount = speciesCount + 1 end
end
eq(speciesCount, 251, "Gold's roster is 251 species")
ok(manifest:match('"dexSize"') == nil,
   "and the cart's constants carry no dexSize, which is why reading one failed")

-- ---- the shipped list builder, with Gold's data shape

local DexData = assert(load(slurp("modules/Gen1Dex/dexdata.lua"),
                            "@Gen1Dex/dexdata.lua"))()

local pokemon = {}
for n = 1, 251 do
  pokemon["MON" .. n] = { id = "MON" .. n, name = ("M%03d"):format(n), dex = n }
end
-- The Gold shape: gen2Constants present, name lists only, NO dexSize.
local goldData = {
  pokemon = pokemon,
  gen2Constants = { speciesOrder = {}, spriteOrder = {}, mapOrder = {} },
}

do
  local build = DexData.list(goldData, { seen = {}, owned = {} }, "num")
  eq(#build.items, 251, "the numeric view runs the whole roster, not 151")
  eq(build.items[152] and build.items[152].species, "MON152",
     "and #152 is in it, which is what the Johto cursor needs to land on")
end

-- A Red-shaped dataset is unaffected: the bound is derived from the roster it
-- is given, so a 151 roster still answers 151.
do
  local red = { pokemon = {}, constants = { dexSize = 151 } }
  for n = 1, 151 do
    red.pokemon["MON" .. n] = { id = "MON" .. n, name = ("M%03d"):format(n), dex = n }
  end
  local build = DexData.list(red, { seen = {}, owned = {} }, "num")
  eq(#build.items, 151, "a 151 roster still answers 151")
end

-- ---- the save shape, and the cycle that hung off it

local source = slurp("modules/Gen1Dex/gen2list.lua")
ok(source:find("pokedex.caught or pokedex.owned", 1, true) ~= nil,
   "the Gold screen normalises `caught` onto the `owned` DexData.list asks for")

-- CAUGHT is empty when nothing is owned, which on Gold was ALWAYS.
do
  local save = { seen = { MON1 = true, MON2 = true }, owned = {} }
  eq(#DexData.list(goldData, save, "caught").items, 0,
     "with nothing owned the CAUGHT view is empty")
  ok(#DexData.list(goldData, save, "alpha").items > 0, "while A-Z has rows")
  eq(#DexData.list(goldData, save, "num").items, 251, "and POKeDEX always does")
end

-- The ring: num -> alpha -> caught -> num.  Stepping OVER an empty view is
-- what gives A-Z a way back to POKeDEX when CAUGHT has nothing in it.
eq(DexData.NEXT_MODE.num, "alpha", "SELECT goes POKeDEX -> A-Z")
eq(DexData.NEXT_MODE.alpha, "caught", "-> CAUGHT")
eq(DexData.NEXT_MODE.caught, "num", "-> and round to POKeDEX")

do
  -- The shipped walk, lifted so the skip is the real one.
  local body = source:match("(  function Screen:cycleView%(%).-\n  end)\n")
  assert(body, "could not find cycleView in gen2list.lua")
  local save = { seen = { MON1 = true }, owned = {} }
  local screen = {
    mode = "alpha",
    game = { data = goldData },
    dexSave = function() return save end,
    current = function() return nil end,
    rebuild = function(self) self.rebuilt = (self.rebuilt or 0) + 1 end,
  }
  local Screen = {}
  assert(load("local Screen, DexData, C = ...\n" .. body,
              "@Gen1Dex/gen2list.lua"))(
    Screen, DexData, { option = function() return true end })
  Screen.cycleView(screen)
  eq(screen.mode, "num",
     "SELECT on A-Z steps OVER the empty CAUGHT view and lands on POKeDEX")
  eq(screen.rebuilt, 1, "rebuilding once on the way")
end

do
  -- And with something owned it stops at CAUGHT rather than skipping it.
  local body = source:match("(  function Screen:cycleView%(%).-\n  end)\n")
  local save = { seen = { MON1 = true }, owned = { MON1 = true } }
  local screen = {
    mode = "alpha",
    game = { data = goldData },
    dexSave = function() return save end,
    current = function() return nil end,
    rebuild = function() end,
  }
  local Screen = {}
  assert(load("local Screen, DexData, C = ...\n" .. body,
              "@Gen1Dex/gen2list.lua"))(
    Screen, DexData, { option = function() return true end })
  Screen.cycleView(screen)
  eq(screen.mode, "caught", "a CAUGHT view with rows in it is not skipped")
end

io.write(("dexgold: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
