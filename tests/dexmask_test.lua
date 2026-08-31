-- A name the dex has not earned, and the one place that kept printing it.
--
-- The AREA screen is reachable for a POKeMON the dex has never met -- the
-- AREA ON UNSEEN row, and an evolution the entry screen is showing -- and its
-- header printed "CHARIZARD UNKNOWN" over the map.  The rest of that screen
-- is careful: the caption says EVOLVE CHARMELEON AT LV36 and names only what
-- you have already got.  The header handed over the answer.
--
-- ...and so did the CAPTION, which that paragraph used to hold up as the
-- careful one.  "the caption says EVOLVE CHARMELEON AT LV36 and names only
-- what you have already got" was simply not true: `fromEvolution` read the
-- species table raw, so a player who had met a WARTORTLE in the wild and
-- never a SQUIRTLE got "EVOLVE SQUIRTLE AT LV16" printed under a header that
-- refused to name it.
--
-- So the token and the predicate live in the shared chrome, once, for every
-- screen that prints a species it might not have met -- and every one of them
-- goes through it, which is what the last block here holds.
--
-- Run:  luajit tests/dexmask_test.lua

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

-- Enough of a font to measure with.  `area.lua` clamps every caption line to
-- the box's width in glyphs, so the split/measure pair has to answer; nothing
-- here draws, and every line under test is well inside the budget.
local Font = {
  draw = function() end, drawBox = function() end, drawCode = function() end,
  width = function(t) return #t * 8 end,
  split = function(t)
    local o = {}
    for i = 1, #t do o[i] = { from = i, to = i } end
    return o
  end,
  -- a real measure, because the header's whole job is deciding whether a
  -- line fits: eight pixels a glyph, and no more of them than the budget
  spansFitting = function(spans, pixels)
    return math.min(#spans, math.floor((pixels or 0) / 8))
  end,
}

package.preload["src.render.Font"] = function() return Font end

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local mod = { options = { get = function() return true end },
              log = { warn = function() end, info = function() end },
              ui = { Font = Font, Theme = {}, Menu = {} } }
local C = chunkOf("modules/Gen1Dex/chrome.lua")(mod)

local data = { pokemon = {
  CHARMELEON = { name = "CHARMELEON", dex = 5 },
  CHARIZARD  = { name = "CHARIZARD",  dex = 6 },
} }

-- ---------------------------------------------------------------- the tests

io.write("a species you have met is named\n")
do
  local save = { pokedex = { seen = { CHARMELEON = true }, owned = {} } }
  eq(C.seenName(save, data, "CHARMELEON"), "CHARMELEON",
    "seen is enough -- you have stood in front of one")
end

io.write("and one you have not is not\n")
do
  local save = { pokedex = { seen = { CHARMELEON = true }, owned = {} } }
  eq(C.seenName(save, data, "CHARIZARD"), C.UNSEEN,
    "the AREA header said CHARIZARD UNKNOWN over the map; it says ????? now")
  eq(C.UNSEEN, "?????", "the same token the INSPECT list prints")
end

io.write("owning one counts as having met it\n")
do
  -- The dex sets both, but a save restored from an older build may carry only
  -- one -- and a POKeMON in the box is one you have met whatever seen says.
  local save = { pokedex = { seen = {}, owned = { CHARIZARD = true } } }
  eq(C.seenName(save, data, "CHARIZARD"), "CHARIZARD", "owned implies seen")
end

io.write("and a save with no dex has met nothing\n")
do
  eq(C.seenName({}, data, "CHARMELEON"), C.UNSEEN, "no pokedex table")
  eq(C.seenName(nil, data, "CHARMELEON"), C.UNSEEN, "no save at all")
end

io.write("a species the data does not know still answers\n")
do
  -- A mod's species, or a dex renumbered out from under a save: the id is
  -- the best name there is, and it is still masked until it is met.
  local save = { pokedex = { seen = { MISSINGNO = true }, owned = {} } }
  eq(C.seenName(save, data, "MISSINGNO"), "MISSINGNO",
    "the id stands in for a name the data has not got")
  eq(C.seenName({ pokedex = { seen = {}, owned = {} } }, data, "MISSINGNO"),
    C.UNSEEN, "and is masked when it has not been met")
  eq(C.seenName(save, nil, "MISSINGNO"), "MISSINGNO", "no data table either")
end

-- ------------------------------------------- and the caption, which lied

io.write("the evolution hint masks the POKeMON it names\n")
do
  -- The AREA screen is reachable for something never met, and for a species
  -- with no wild encounters the caption falls back to the evolution table:
  -- "EVOLVE <from> AT LV<n>".  `from` is a species like any other and has to
  -- earn its name the same way.
  local Area = chunkOf("modules/Gen1Dex/area.lua")(mod, C)
  local evoData = { pokemon = {
    SQUIRTLE  = { name = "SQUIRTLE",  dex = 7,
                  evolutions = { { species = "WARTORTLE", level = 16 } } },
    WARTORTLE = { name = "WARTORTLE", dex = 8 },
  } }

  local metBoth = { pokedex = { seen = { SQUIRTLE = true, WARTORTLE = true },
                                owned = {} } }
  local lines = Area.caption({ data = evoData, save = metBoth }, "WARTORTLE")
  eq(lines and lines[1], "EVOLVE SQUIRTLE",
    "a SQUIRTLE you have met is named")
  eq(lines and lines[2], "AT LV16", "and the level is not a secret either")

  -- the reported case: a WARTORTLE in the wild, no SQUIRTLE ever
  local metOne = { pokedex = { seen = { WARTORTLE = true }, owned = {} } }
  lines = Area.caption({ data = evoData, save = metOne }, "WARTORTLE")
  eq(lines and lines[1], "EVOLVE " .. C.UNSEEN,
    "one you have not met is masked, exactly as the header masks it")
  eq(lines and lines[2], "AT LV16",
    "the shape of the answer is still owed: something evolves into this at 16")
end

-- --------------------------------------------- and the header, which also lied

io.write("the nest header masks a POKeMON you have not met\n")
do
  -- The header has two lines to choose between, and only one of them was
  -- masked.  With no nests it says "<NAME> UNKNOWN" and that line is always
  -- ours; with nests it says "<NAME>'s NEST" and that line was handed back to
  -- the engine whenever it fitted -- and TownMap.lua:440 builds it off the
  -- species table raw.  Nil means "the engine's line is the line we would
  -- draw", which stopped being true the moment the name could be masked.
  --
  -- And it is the nest line that most species have: looking up where
  -- something lives BEFORE you have met it is what the AREA ON UNSEEN row is
  -- for, so the masked case and the common case are the same case.
  local Area = chunkOf("modules/Gen1Dex/area.lua")(mod, C)
  local nestData = { pokemon = { PIDGEY = { name = "PIDGEY", dex = 16 } } }
  local function header(seen, nests, species, data)
    local screen = {
      game = { data = data or nestData,
               save = { pokedex = { seen = seen, owned = {} } } },
      nests = nests,
    }
    return Area.header(screen, species or "PIDGEY")
  end

  eq(header({}, { {} }), "?????'s NEST",
    "a PIDGEY you have never met does not get named over its own nests")
  eq(header({ PIDGEY = true }, { {} }), nil,
    "and one you have met is the engine's own line, left alone the way it was")

  eq(header({}, {}), "????? UNKNOWN",
    "the line with no nests under it was masked already, and still is")
  eq(header({ PIDGEY = true }, {}), "PIDGEY UNKNOWN",
    "which is not a mask, it is the screen saying it has no answer")

  -- The measure is still the measure: 19 columns, and a name long enough to
  -- overflow is shortened whether or not it is masked.  No Gen 1 name is,
  -- but a mod's species can be, and that is what this line is for.
  local longData = { pokemon = { VERYLONGNAMEDMON = { name = "VERYLONGNAMEDMON" } } }
  eq(header({ VERYLONGNAMEDMON = true }, { {} }, "VERYLONGNAMEDMON", longData),
    "VERYLONGNAMEDMON's ",
    "twenty-three glyphs is not nineteen, so the line becomes ours and is cut")
end

io.write(("\ndex mask: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
