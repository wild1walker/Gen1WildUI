-- The three START-menu rows that find themselves by NAME, on both cartridges.
--
-- START SAYS PARTY, START SAYS DEX and the BOX row all work by looking for a
-- word on an existing row: POKéMON, POKéDEX, and the POKéMON/SAVE pair the BOX
-- row is inserted between.  Red hands a hook rows whose labels are already
-- translated.  Gold, deliberately, does not -- it builds rows with
-- `Strings.source(...)` and translates afterwards, "so hooks inspect the
-- cart's stable source labels" (src/ui/gen2/StartMenu.lua).
--
-- So a hook that looks only for the TRANSLATED word finds nothing on Gold the
-- moment a translation is installed: the row keeps saying POKéMON, the dex row
-- keeps its long name, and BOX falls off the bottom of the menu instead of
-- landing between POKéMON and SAVE.  In English the two forms are the same
-- string, which is why this never showed up.
--
-- The bodies under test are read out of the shipped modules rather than
-- retyped, so an edit that drops the fix fails here instead of passing against
-- a copy of the old code.
--
-- Run:  luajit tests/startrows_test.lua

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

local function slurp(path)
  local handle = assert(io.open(path), path)
  local text = handle:read("*a")
  handle:close()
  return text
end

-- ---- a Strings with a catalog in it
--
-- Real enough for this: `Strings.source` is the identity the engine's is, and
-- `Strings(x)` answers the catalog and falls through to English, which is the
-- behaviour the fall-through in Strings.get gives an uncovered entry.

local catalog = {}
local Strings = setmetatable({
  source = function(text) return text end,
}, { __call = function(_, text) return catalog[text] or text end })

package.loaded["src.core.Strings"] = Strings

-- ---- the two row shapes
--
-- Gold's, before the engine's own translate pass: source label, a value, and
-- the translateLabel flag that says the pass is still to come.  Red's: already
-- translated, a callback, no flag.

local function goldRows()
  return {
    { label = Strings.source("POKéDEX"), value = "pokedex", translateLabel = true },
    { label = Strings.source("POKéMON"), value = "pokemon", translateLabel = true },
    { label = Strings.source("PACK"), value = "pack", translateLabel = true },
    { label = Strings.source("SAVE"), value = "save", translateLabel = true },
    { label = Strings.source("OPTION"), value = "option", translateLabel = true },
  }
end

local function redRows()
  return {
    { label = Strings("POKéDEX"), onSelect = function() end },
    { label = Strings("POKéMON"), onSelect = function() end },
    { label = Strings("ITEM"), onSelect = function() end },
    { label = Strings("SAVE"), onSelect = function() end },
    { label = Strings("OPTION"), onSelect = function() end },
  }
end

local function labels(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.label end
  return table.concat(out, ",")
end

local function indexOf(rows, label)
  for i, row in ipairs(rows) do if row.label == label then return i end end
end

-- ---- the shipped bodies

local function extract(path, pattern, what)
  local body = slurp(path):match(pattern)
  assert(body, ("could not find %s in %s"):format(what, path))
  return body
end

-- START SAYS PARTY: the wrap, with `mod` and `Strings` supplied
local partyWrap do
  local body = extract("modules/Gen1Party/main.lua",
    "(mod%.hooks:wrap%(\"ui%.start_menu%.items\".-\n  end%))",
    "the START SAYS PARTY wrap")
  local captured
  local mod = {
    hooks = { wrap = function(_, _, fn) captured = fn end },
    options = { get = function() return true end },
    log = { warn = function() end },
  }
  assert(load("local mod, Strings = ...\n" .. body,
              "@Gen1Party/main.lua"))(mod, Strings)
  partyWrap = assert(captured, "the party wrap did not register")
end

-- START SAYS DEX: the whole installer now, rather than the wrap inside it.
--
-- It moved into `installDexLabel` so both cartridges can install it -- it used
-- to sit below the generation branch, where a Gold boot never reached it -- so
-- the installer is what is lifted, and it is called with the option reader it
-- takes.  Indented one level deeper than the wraps above, hence the four
-- spaces in the close.
local dexWrap do
  local body = extract("modules/Gen1Dex/main.lua",
    "(  local function installDexLabel%(option%).-\n  end)\n",
    "the START SAYS DEX installer")
  local captured
  local mod = { hooks = { wrap = function(_, _, fn) captured = fn end } }
  -- `mod` is the installer's own upvalue in the module; supplied here.
  assert(load("local mod = ...\n" .. body
              .. "\ninstallDexLabel(function() return true end)",
              "@Gen1Dex/main.lua"))(mod)
  dexWrap = assert(captured, "the dex wrap did not register")
end

-- the BOX row's placement
local insertBoxRow do
  local body = extract("modules/Gen1BillsBox/main.lua",
    "(local function insertBoxRow.-\n  end)\n",
    "insertBoxRow")
  insertBoxRow = assert(load(
    "local Strings = ...\n" .. body .. "\nreturn insertBoxRow",
    "@Gen1BillsBox/main.lua"))(Strings)
end

local function passThrough(_, items) return items end

-- ---- English: the two forms are one string, and nothing may change
--
-- This is the half that is already shipping, so it is the half a fix must not
-- disturb.

catalog = {}

do
  local rows = partyWrap(passThrough, {}, goldRows())
  eq(indexOf(rows, "PARTY"), 2, "Gold: POKéMON becomes PARTY, in place")
  local red = partyWrap(passThrough, {}, redRows())
  eq(indexOf(red, "PARTY"), 2, "Red: unchanged by the fix")

  local dex = dexWrap(passThrough, {}, goldRows())
  eq(indexOf(dex, "DEX"), 1, "Gold: POKéDEX becomes DEX")
  eq(indexOf(dexWrap(passThrough, {}, redRows()), "DEX"), 1, "Red: the same")

  local boxed = insertBoxRow(goldRows(), { label = "BOX" })
  eq(indexOf(boxed, "BOX"), 3, "Gold: BOX lands after POKéMON")
  eq(indexOf(insertBoxRow(redRows(), { label = "BOX" })), nil,
     "sanity: indexOf needs a label")
  eq(indexOf(insertBoxRow(redRows(), { label = "BOX" }), "BOX"), 3,
     "Red: BOX lands after POKéMON too")
end

-- ---- and now with a translation loaded, which is where Gold used to fail

catalog = {
  ["POKéMON"] = "ÉQUIPE",
  ["POKéDEX"] = "POKéDEX FR",
  ["SAVE"] = "SAUVER",
  ["PARTY"] = "ÉQUIPE",
  ["DEX"] = "DEX FR",
}

do
  -- Gold's rows still carry the SOURCE words at this point, because the
  -- engine's translate pass has not run yet.
  local rows = goldRows()
  eq(rows[2].label, "POKéMON", "Gold hands the hook the source word")

  rows = partyWrap(passThrough, {}, rows)
  ok(indexOf(rows, "POKéMON") == nil,
     "Gold, translated: the POKéMON row was found and renamed")
  eq(rows[2].label, "PARTY",
     "and renamed to the SOURCE word, for the engine's pass to translate once")
  eq(rows[2].translateLabel, true, "the row keeps its translate flag")

  local dex = dexWrap(passThrough, {}, goldRows())
  eq(dex[1].label, "DEX", "Gold, translated: the dex row was found and renamed")

  local boxed = insertBoxRow(goldRows(), { label = "BOX" })
  eq(indexOf(boxed, "BOX"), 3,
     "Gold, translated: BOX still lands between POKéMON and SAVE")
  eq(#boxed, 6, "and was inserted, not appended twice")

  -- Red's rows arrive already translated, and must still be found.
  local red = partyWrap(passThrough, {}, redRows())
  eq(red[2].label, "ÉQUIPE",
     "Red, translated: renamed to the TRANSLATED word, which is all it gets")
  eq(indexOf(insertBoxRow(redRows(), { label = "BOX" }), "BOX"), 3,
     "Red, translated: BOX still lands after POKéMON")
end

-- ---- a menu with neither anchor still gets its BOX row

catalog = {}
do
  local bare = { { label = "SOMETHING ELSE" } }
  local boxed = insertBoxRow(bare, { label = "BOX" })
  eq(indexOf(boxed, "BOX"), 2, "with no anchor at all, BOX goes on the end")
end

io.write(("startrows: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
