-- The line under Gold's AREA map.
--
-- Red's AREA screen has carried a caption since 0.20 -- how you catch it,
-- roughly what level, and how often -- and Gold's had nothing, because on Gold
-- the AREA page is a VIEW inside the cart's own PokedexMenu rather than the
-- TownMap screen area.lua wraps, and the wild tables underneath are a
-- different table with a different shape.
--
-- Everything this file asserts about that shape is READ OFF the engine and the
-- ROM disassembly rather than restated, because restating it is how a Gen 2
-- reader ends up pointed at a Gen 1 table: the wrong key returns nil rather
-- than an error, and nil is a caption that never draws and never says why.
--
-- Run:  luajit tests/areagen2_test.lua
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
      local probe = io.open(dir .. "/src/ui/gen2/PokedexMenu.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("area gen2: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end

-- The roamer arm reaches for src.core.gen2.Roamers through pcall, so without
-- the engine on the path it would answer nil and this file would be asserting
-- that a missing require is a missing roamer.
package.path = ENGINE .. "/?.lua;" .. package.path

local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

local src = assert(slurp("modules/Gen1Dex/gen2area.lua"),
                   "modules/Gen1Dex/gen2area.lua")

-- ---- the screen, read off the cart

local dexSrc = assert(slurp(ENGINE .. "/src/ui/gen2/PokedexMenu.lua"))

ok(dexSrc:find("function PokedexMenu:drawArea()", 1, true) ~= nil,
   "Gold draws its AREA page from PokedexMenu:drawArea -- the wrap's target")
ok(dexSrc:find('self.view = "area"', 1, true) ~= nil,
   "and AREA is a view inside the dex, not a screen of its own")
ok(dexSrc:find("function PokedexMenu:current()", 1, true) ~= nil,
   "the species under the cursor comes from screen:current()")

-- The header is the paint this strip mirrors: a full-width bar in the map
-- palette's colour 3, then an INVERTED print over it.
local header = dexSrc:match("function PokedexMenu:drawAreaHeader.-\nend")
assert(header, "could not find drawAreaHeader in the engine")
ok(header:find("GbcPalette.color(pal, 4)", 1, true) ~= nil,
   "the header's bar is the map palette's colour 3 (index 4)")
ok(header:find('G.rectangle("fill", 0, 0, Chrome.SCREEN_W * 8, 8)', 1, true) ~= nil,
   "painted full width, one row tall")
ok(header:find("Chrome.printThrough(title, 2, 0, pal, true, true)", 1, true) ~= nil,
   "and the words go over it through an INVERTED print")
for _, needle in ipairs({ "GbcPalette.color(pal, 4)",
                          'G.rectangle("fill", 0, STRIP_TY * 8, Chrome.SCREEN_W * 8, 8)',
                          "Chrome.printThrough(text, TEXT_TX, STRIP_TY, pal, true, true)" }) do
  ok(src:find(needle, 1, true) ~= nil,
     "the strip mirrors the header: " .. needle)
end

-- ---- the row the strip may have, read off the ROM's landmark table
--
-- The icon is drawn at (mark.x - 4, mark.y - 4), so the LOWEST landmark
-- decides how far up the strip has to stay.
ok(dexSrc:find("self:drawNestIcon(mark.x - 4, mark.y - 4)", 1, true) ~= nil,
   "a nest icon is drawn four pixels up and left of its landmark")

local PC do
  -- Built by appending rather than as a literal: an unset POKECRYSTAL is a nil
  -- in the middle of a list, and `ipairs` stops at it -- which is the same
  -- mistake this file catches in the caption's own parts list below.
  local candidates = { os.getenv("POKECRYSTAL") }
  for _, dir in ipairs({ "/tmp/claude-0/pc", "../pokecrystal",
                         "../../pokecrystal", "../../../pokecrystal" }) do
    candidates[#candidates + 1] = dir
  end
  for _, dir in ipairs(candidates) do
    if slurp(dir .. "/data/maps/landmarks.asm") then PC = dir break end
  end
end
-- The +8/+16 the `landmark` macro adds is the HARDWARE SPRITE offset -- OAM
-- coordinates, not screen ones -- and the extractor takes it straight back
-- off.  So the drawn y is the macro's own second argument, and re-adding the
-- sixteen here would have put the lowest icon twelve pixels off the bottom of
-- a 144-pixel screen and "proved" the strip has no room at all.
local extractor = slurp(ENGINE .. "/src/import/RomExtractorGen2.lua")
if extractor then
  ok(extractor:find("local x = self.rom:byte(symbol.bank, base) - 8", 1, true) ~= nil,
     "the extractor takes the OAM x offset back off")
  ok(extractor:find("local y = self.rom:byte(symbol.bank, base + 1) - 16", 1, true) ~= nil,
     "and the OAM y offset, so mark.y is a screen row")
end

if PC then
  local asm = slurp(PC .. "/data/maps/landmarks.asm")
  ok(asm:find("db \\1 + 8, \\2 + 16", 1, true) ~= nil,
     "the landmark macro adds the OAM offset the extractor removes")
  local lowest = 0
  for _, y in asm:gmatch("landmark%s+(-?%d+),%s*(-?%d+)") do
    y = tonumber(y)
    if y > lowest then lowest = y end
  end
  eq(lowest, 132, "the lowest landmark on either region sits at y 132")
  local iconBottom = lowest - 4 + 8
  eq(iconBottom, 136, "so the lowest icon's last pixel row is 135")
  eq(math.floor(iconBottom / 8), 17,
     "and row 17 begins exactly where it ends -- the one row the strip may have")
  eq(math.floor((lowest - 4) / 8), 16,
     "row 16 still has a nest in it, which is why the strip is not two rows")
  ok(src:find("local STRIP_TY = 17", 1, true) ~= nil,
     "so the strip takes row 17 and no other")
else
  io.write("  note: no pokecrystal checkout; the landmark bound is unchecked\n")
end

-- ---- what the cart's own nests can and cannot say

local nests = assert(slurp(ENGINE .. "/src/core/gen2/Nests.lua"))
local find = nests:match("function Nests.find.-\nend\n")
assert(find, "could not find Nests.find")
ok(find:find('{ "grass", "water" }', 1, true) ~= nil,
   "the blinking nests read grass and water")
ok(find:find("Roamers.active(slot)", 1, true) ~= nil,
   "and the roamers")
ok(find:find("fishGroups", 1, true) == nil and find:find("treeSets", 1, true) == nil,
   "and NOTHING else -- so a HEADBUTT-only species opens a blank map, which "
   .. "is the case this strip exists for")

-- ---- the tables, read off the schema

local schema = assert(slurp(ENGINE .. "/src/mods/Schemas.lua"))
ok(schema:find('encounters = "gen2Encounters"', 1, true) ~= nil,
   "Gold's wild data is data.gen2Encounters")
ok(schema:find("rates = f.map(gen2Tod, f.int(0, 255)),\n  slots = f.map(gen2Tod, f.list(gen2Slot)),",
               1, true) ~= nil,
   "a grass row is one slot table PER TIME OF DAY")
ok(schema:find('local gen2Tod = f.enum{ "MORN", "DAY", "NITE" }', 1, true) ~= nil,
   "and the three times are spelled MORN / DAY / NITE")
ok(src:find('local TOD = { "MORN", "DAY", "NITE" }', 1, true) ~= nil,
   "which is the spelling the reader uses")
ok(schema:find("map = f.opt(f.str), rate = f.int(0, 255), slots = f.list(gen2Slot),",
               1, true) ~= nil,
   "a water row is one flat slot list -- no time split")
for _, key in ipairs({ "swarmGrass", "swarmWater", "fishGroups", "trees",
                       "rocks", "treeSets", "timeFishGroups" }) do
  ok(schema:find(key, 1, true) ~= nil, "the schema carries " .. key)
  ok(src:find(key, 1, true) ~= nil, "and the reader asks for " .. key)
end
ok(schema:find("old = f.list(gen2FishSlot), good = f.list(gen2FishSlot),", 1, true) ~= nil,
   "a fish group carries one list per rod")
ok(schema:find("treeSets = f.map(f.str, f.rec{ common = f.list(gen2TreeSlot),", 1, true) ~= nil,
   "and a tree set carries common and rare")

-- The evolution row: Gold spells the target `into`, Red spells it `species`.
-- Reading Red's key here is a silent nil, which is the whole bug class.
-- Both records live in this one file, four dozen lines apart, and the two
-- spellings are the whole trap: a reader that asks for the Gen 1 key against
-- the Gen 2 table gets nil rather than an error.
ok(schema:find("species = f.id(\"pokemon\") }),", 1, true) ~= nil,
   "a Gen 1 evolution row names its target `species`")
ok(schema:find("into = f.id(\"pokemon\"),", 1, true) ~= nil,
   "a Gen 2 evolution row names it `into`")
ok(src:find("evo.into == species", 1, true) ~= nil,
   "and the reader matches on `into`, not `species`")
local evoSrc = assert(slurp(ENGINE .. "/src/core/gen2/Evolution.lua"))
for _, method in ipairs({ "EVOLVE_LEVEL", "EVOLVE_ITEM", "EVOLVE_TRADE",
                          "EVOLVE_HAPPINESS" }) do
  ok(evoSrc:find('"' .. method .. '"', 1, true) ~= nil,
     "the engine spells " .. method)
end
ok(src:find('evo.method == "EVOLVE_TRADE"', 1, true) ~= nil,
   "and so does the reader -- not Red's bare \"TRADE\"")

-- ---- the odds, read off the ROM

if PC then
  local prob = slurp(PC .. "/data/wild/probabilities.asm")
  if prob then
    local grass, water = {}, {}
    local section
    for line in prob:gmatch("[^\n]+") do
      if line:find("GrassMonProbTable:", 1, true) then section = grass end
      if line:find("WaterMonProbTable:", 1, true) then section = water end
      local pc = line:match("mon_prob%s+(%d+),")
      if pc and section then section[#section + 1] = tonumber(pc) end
    end
    eq(table.concat(grass, ","), "30,60,80,90,95,99,100",
       "Gold's seven grass slots are cumulative out of 100")
    eq(table.concat(water, ","), "60,90,100",
       "and its three water slots likewise")
    ok(src:find("local GRASS_BUCKETS = { 30, 60, 80, 90, 95, 99, 100 }", 1, true) ~= nil,
       "which is the grass table the reader carries")
    ok(src:find("local WATER_BUCKETS = { 60, 90, 100 }", 1, true) ~= nil,
       "and the water one")
  end
end

-- ---- the module itself, run

local Font = {}
-- a fixed-advance stand-in: one glyph, eight pixels, which is the vanilla
-- sheet and makes a column budget countable in bytes for the assertions below
function Font.split(text)
  local spans = {}
  for i = 1, #text do spans[i] = { from = i, to = i, code = text:byte(i) } end
  return spans
end
function Font.spansFitting(spans, budget)
  return math.min(#spans, math.floor(budget / 8))
end

local warnings = {}
local mod = {
  ui = { Font = Font },
  log = {
    warn = function(_, fmt, ...) warnings[#warnings + 1] = fmt:format(...) end,
    info = function() end,
    error = function() end,
  },
  options = { get = function(_, key) return true end },
}

local Area = assert(loadfile("modules/Gen1Dex/gen2area.lua"))()(mod, {})

eq(Area.COLS, 19, "the strip has nineteen columns")

-- A cart, in Gold's shape.
local function slot(species, level) return { species = species, level = level } end
local data = {
  pokemon = {
    RATTATA = { name = "RATTATA" },
    HERACROSS = { name = "HERACROSS" },
    TENTACOOL = { name = "TENTACOOL" },
    MAGIKARP = { name = "MAGIKARP" },
    HOOTHOOT = { name = "HOOTHOOT" },
    RAIKOU = { name = "RAIKOU" },
    CYNDAQUIL = { name = "CYNDAQUIL",
                  evolutions = { { method = "EVOLVE_LEVEL", into = "QUILAVA",
                                   level = 14 } } },
    QUILAVA = { name = "QUILAVA" },
    HAUNTER = { name = "HAUNTER",
                evolutions = { { method = "EVOLVE_TRADE", into = "GENGAR" } } },
    GENGAR = { name = "GENGAR" },
    DUNSPARCE = { name = "DUNSPARCE" },
  },
  gen2Encounters = {
    grass = {
      ROUTE_29 = { slots = {
        MORN = { slot("RATTATA", 2), slot("HOOTHOOT", 2), slot("HOOTHOOT", 3),
                 slot("HOOTHOOT", 3), slot("HOOTHOOT", 2), slot("HOOTHOOT", 2),
                 slot("HOOTHOOT", 2) },
        DAY  = { slot("RATTATA", 2), slot("HOOTHOOT", 2), slot("HOOTHOOT", 3),
                 slot("HOOTHOOT", 3), slot("HOOTHOOT", 2), slot("HOOTHOOT", 2),
                 slot("HOOTHOOT", 2) },
        NITE = { slot("HOOTHOOT", 2), slot("HOOTHOOT", 2), slot("HOOTHOOT", 3),
                 slot("HOOTHOOT", 3), slot("HOOTHOOT", 2), slot("HOOTHOOT", 2),
                 slot("RATTATA", 4) },
      } },
    },
    water = {
      ROUTE_40 = { slots = { slot("TENTACOOL", 20), slot("TENTACOOL", 25),
                             slot("MAGIKARP", 15) } },
    },
    fishGroups = {
      FISHGROUP_SHORE = { old = { { chance = 128, species = "MAGIKARP", level = 10 } },
                          good = {}, super = {} },
    },
    trees = { ROUTE_29 = "TREEMON_SET_TOWN" },
    rocks = {},
    treeSets = {
      TREEMON_SET_TOWN = { common = { { chance = 50, species = "HERACROSS", level = 10 } },
                           rare = { { chance = 50, species = "HERACROSS", level = 15 } } },
    },
  },
}
local game = { data = data, save = { pokedex = { seen = { CYNDAQUIL = true } } } }

do -- grass, restricted by time, with the tier
  -- RATTATA: slot 1 (30%) MORN and DAY, slot 7 (1%) NITE -> (30+30+1)/3 = 20.3
  eq(Area.caption(game, "RATTATA"), "GRASS Lv2-4 COMMON",
     "grass names the method, the band and how often")
end

do -- present at all three times, so the time is not worth a word
  -- HOOTHOOT is in every slot of every table, so no restriction to report
  local text = Area.caption(game, "HOOTHOOT")
  ok(text and text:find("GRASS", 1, true) == 1, "HOOTHOOT is grass")
  ok(text and text:find("MORN", 1, true) == nil,
     "a species at all three times says nothing about the hour")
end

do -- water
  eq(Area.caption(game, "TENTACOOL"), "SURF Lv20-25 COMMON",
     "water says SURF")
end

do -- water AND fishing: the map is showing the water, so the water wins
  eq(Area.caption(game, "MAGIKARP"), "SURF Lv15 UNCOMMON",
     "a species the nests already show is described where the nests show it")
end

do -- the case the strip exists for: no nest at all
  eq(Area.caption(game, "HERACROSS"), "HEADBUTT Lv10-15",
     "a HEADBUTT-only species gets the answer its blank map cannot give")
  ok(Area.caption(game, "HERACROSS"):find("RARE", 1, true) == nil,
     "and no tier, because a tree slot's odds are not a grass slot's")
end

do -- the roamers
  local text = Area.caption(game, "RAIKOU")
  eq(text, "ROAMING Lv40", "a roamer says so")
end

do -- not wild anywhere
  eq(Area.caption(game, "QUILAVA"), "EVOLVE CYNDAQUIL",
     "an evolution answers when no table does")
  ok(not Area.caption(game, "QUILAVA"):find("AT LV", 1, true),
     "and the level is dropped rather than the line truncated mid-word")
  eq(Area.caption(game, "GENGAR"), "LINK CABLE ON ?????",
     "a name the dex has not met is masked, the way every name here is")
end

do -- nobody at all
  eq(Area.caption(game, "DUNSPARCE"), nil, "no answer is nil, not a blank string")
  eq(Area.probe(game, "DUNSPARCE"), "NO RECORD REMAINS",
     "and the strip says so rather than drawing an empty bar")
end

do -- providers
  local seen = {}
  Area.provide(function(_, species)
    seen[#seen + 1] = species
    if species == "RATTATA" then return { "MY WORDS", "AND MINE" } end
    if species == "HERACROSS" then return false end
    return nil
  end, "TestMod")
  eq(Area.caption(game, "RATTATA"), "MY WORDS AND MINE",
     "a provider outranks the built-in reading")
  eq(Area.caption(game, "HERACROSS"), nil,
     "and `false` is a seal: no built-in answers in its place")
  eq(Area.probe(game, "HERACROSS"), "NO RECORD REMAINS",
     "a seal reads exactly like an ordinary blank")
  eq(Area.caption(game, "TENTACOOL"), "SURF Lv20-25 COMMON",
     "nil is no opinion and falls through")
end

do -- a provider that throws is dropped, not fatal
  Area.provide(function() error("nope", 0) end, "BrokenMod")
  eq(Area.caption(game, "TENTACOOL"), "SURF Lv20-25 COMMON",
     "a throwing provider costs its line, not the screen")
  local named = false
  for _, w in ipairs(warnings) do
    if w:find("BrokenMod", 1, true) then named = true end
  end
  ok(named, "and the mod that broke is named in the warning")
end

do -- the eighteen columns are the box's business, not the provider's
  local Solo = assert(loadfile("modules/Gen1Dex/gen2area.lua"))()(mod, {})
  Solo.provide(function() return { "A VERY LONG FIRST LINE INDEED", "SECOND" } end)
  local text = Solo.caption(game, "RATTATA")
  eq(#text, 19, "a first line past the budget is cut to it")
  eq(text, "A VERY LONG FIRST L", "at the budget, not at a guess")

  local Pair = assert(loadfile("modules/Gen1Dex/gen2area.lua"))()(mod, {})
  Pair.provide(function() return { "SUPER ROD Lv15-25", "VERY RARE" } end)
  eq(Pair.caption(game, "RATTATA"), "SUPER ROD Lv15-25",
     "and a second line that will not fit is dropped whole")
end

do -- the row is live
  local off = { ui = { Font = Font }, log = mod.log,
                options = { get = function() return false end } }
  local Off = assert(loadfile("modules/Gen1Dex/gen2area.lua"))()(off, {})
  -- the option gates the DRAW, not the reading -- exports.caption is a
  -- question another mod may ask whatever this player's menu says
  eq(Off.caption(game, "TENTACOOL"), "SURF Lv20-25 COMMON",
     "the option gates the strip, not the answer")
  ok(src:find('mod.options:get("area_hints") ~= false', 1, true) ~= nil,
     "and the draw asks the row every frame rather than capturing it")
end

-- ---- wired up

local mainSrc = assert(slurp("modules/Gen1Dex/main.lua"))
ok(mainSrc:find("area_hints = true,", 1, true) ~= nil,
   "AREA HINTS is on Gold's OPTION screen now that it does something there")
ok(mainSrc:find('loadSibling(mod, "gen2area.lua")', 1, true) ~= nil,
   "and main.lua builds the Gold arm")
local gen2Branch = mainSrc:match("if isGen2 then(.-)\n    return\n  end")
assert(gen2Branch, "could not find the isGen2 branch in main.lua")
ok(gen2Branch:find('loadSibling(mod, "gen2area.lua")', 1, true) ~= nil,
   "inside the isGen2 branch, which is the only place it can reach")
for _, key in ipairs({ "provide", "caption", "probe", "cols", "unknown" }) do
  ok(gen2Branch:find(key .. " = ", 1, true) ~= nil,
     "and publishes exports.area." .. key .. ", the same name Red publishes")
end
local areaMain = mainSrc:match("mod.exports.area = {(.-)}")
ok(areaMain ~= nil, "Red's export block is still there")

ok(src:find("local MARK = \"__gen1DexGen2Area\"", 1, true) ~= nil,
   "the wrap marks the class so a hot reload does not wrap a wrapper")
ok(src:find("if rawget(PokedexMenu, MARK) then return true end", 1, true) ~= nil,
   "and returns early when it finds its own mark")

io.write(("area gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
