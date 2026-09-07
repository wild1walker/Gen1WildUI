-- Headless coverage of the PACK's Gold arm (modules/Gen1ModernBag/gen2.lua).
--
-- Gold's PACK builds a pocket's rows in one method and this arm rearranges
-- them: filter, sort, float the pinned.  All three are pure functions of a row
-- list, which is exactly the part that can be wrong and none of which needs a
-- screen -- so all three are driven directly here.
--
-- The stability of the sort is the assertion worth having.  `rebuild` runs on
-- every pocket switch AND every quantity change, so two items with the same
-- count that swap places each time would flicker under the cursor while you
-- toss a stack.  `table.sort` is not stable, which is why there is a
-- tiebreaker at all.
--
-- Run:  luajit tests/baggen2_test.lua

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

local Bag = load_("modules/Gen1ModernBag/gen2.lua")

-- A row in the shape `PackMenu:rebuild` writes.
local function row(id, name, count)
  return { id = id, name = name, count = count }
end

local function ids(rows)
  local out = {}
  for i, r in ipairs(rows or {}) do out[i] = r.id end
  return table.concat(out, " ")
end

-- ---------------------------------------------------------------- the sort

do
  io.write("sorting a pocket\n")

  local rows = {
    row("SUPER_POTION", "SUPER POTION", 3),
    row("ANTIDOTE", "ANTIDOTE", 10),
    row("POTION", "POTION", 3),
  }

  eq(ids(Bag.sortRows(rows, "CUSTOM")),
     "SUPER_POTION ANTIDOTE POTION",
     "CUSTOM is the absence of a rule: the cart's own order, untouched")
  eq(ids(Bag.sortRows(rows, nil)),
     "SUPER_POTION ANTIDOTE POTION",
     "and so is a mode nobody recognises")

  eq(ids(Bag.sortRows(rows, "ALPHA")),
     "ANTIDOTE POTION SUPER_POTION",
     "A-Z sorts on the NAME the cart put on the row, not the id")

  eq(ids(Bag.sortRows(rows, "QUANTITY")),
     "ANTIDOTE SUPER_POTION POTION",
     "QUANTITY is most first -- which is what 'how many have I got' asks")

  -- The one with teeth: SUPER POTION and POTION both have three, and they
  -- must not trade places between rebuilds.
  local once = ids(Bag.sortRows(rows, "QUANTITY"))
  local twice = ids(Bag.sortRows(Bag.sortRows(rows, "QUANTITY"), "QUANTITY"))
  eq(twice, once,
     "the sort is STABLE: two items on the same count keep the order they "
     .. "were in, so nothing flickers under the cursor as a stack is tossed")

  eq(ids(Bag.sortRows({}, "ALPHA")), "", "an empty pocket sorts to nothing")

  -- A row the cart built oddly is sorted, not crashed on.
  local odd = { { id = "X" }, row("A", "A", 1) }
  ok(pcall(Bag.sortRows, odd, "ALPHA"), "a row with no name does not raise")
  ok(pcall(Bag.sortRows, odd, "QUANTITY"), "nor one with no count")
end

-- -------------------------------------------------------------- the search

do
  io.write("searching a pocket\n")

  local rows = {
    row("POTION", "POTION", 1),
    row("SUPER_POTION", "SUPER POTION", 1),
    row("ANTIDOTE", "ANTIDOTE", 1),
  }

  eq(ids(Bag.filterRows(rows, "")), ids(rows), "an empty query filters nothing")
  eq(ids(Bag.filterRows(rows, nil)), ids(rows), "and neither does no query")

  eq(ids(Bag.filterRows(rows, "POTION")), "POTION SUPER_POTION",
     "a substring on the NAME, so POTION finds SUPER POTION too")
  eq(ids(Bag.filterRows(rows, "potion")), "POTION SUPER_POTION",
     "and it is case-insensitive")
  eq(ids(Bag.filterRows(rows, "ANTI")), "ANTIDOTE", "a prefix works")
  eq(ids(Bag.filterRows(rows, "ZZZ")), "", "and a miss is empty, not an error")

  -- The needle is matched literally: an item name is not a Lua pattern, and a
  -- player typing a dot should not match every character.
  local dotted = { row("X", "A.B", 1), row("Y", "AXB", 1) }
  eq(ids(Bag.filterRows(dotted, "A.B")), "X",
     "the query is a literal, not a pattern -- '.' matches a dot and nothing "
     .. "else")
end

-- ---------------------------------------------------------------- the pins

do
  io.write("pinning an item\n")

  local rows = {
    row("A", "A", 1), row("B", "B", 1), row("C", "C", 1), row("D", "D", 1),
  }

  eq(ids(Bag.floatPinned(rows, {})), ids(rows), "nothing pinned changes nothing")
  eq(ids(Bag.floatPinned(rows, nil)), ids(rows), "and neither does no table")

  eq(ids(Bag.floatPinned(rows, Bag.indexOf({ "C" }))), "C A B D",
     "a pinned item goes to the top of its pocket")

  -- Pinned rows keep the order they were PINNED in, not the order they were
  -- in the pocket: the list is the record of what you asked for first.
  eq(ids(Bag.floatPinned(rows, Bag.indexOf({ "D", "B" }))), "D B A C",
     "two pinned keep the order they were pinned in")

  eq(ids(Bag.floatPinned(rows, Bag.indexOf({ "Z" }))), ids(rows),
     "a pin on something not in this pocket floats nothing")

  -- The rest keep the order the sort left them in.
  eq(ids(Bag.floatPinned({ row("B", "B", 1), row("A", "A", 1) },
                          Bag.indexOf({ "A" }))), "A B",
     "and everything else keeps the order it arrived in")
end

-- --------------------------------------------------------------- toggling

do
  io.write("toggling a pin\n")

  local list, pinned = Bag.togglePinned({}, "POTION")
  eq(table.concat(list, " "), "POTION", "pinning adds it")
  eq(pinned, true, "and says so")

  list, pinned = Bag.togglePinned(list, "POTION")
  eq(table.concat(list, " "), "", "pinning again takes it off")
  eq(pinned, false, "and says that too")

  list = Bag.togglePinned({ "A", "B", "C" }, "B")
  eq(table.concat(list, " "), "A C", "unpinning from the middle keeps the rest")

  list = Bag.togglePinned({ "A" }, "B")
  eq(table.concat(list, " "), "A B", "and a new pin goes on the end")

  -- indexOf is what floatPinned orders by, so a duplicate must not shift it.
  local index = Bag.indexOf({ "A", "B", "A" })
  eq(index.A, 1, "indexOf keeps the FIRST position of a duplicate")
  eq(index.B, 2, "and the rest are unmoved")
end

-- ------------------------------------------------------------ the sort ring

do
  io.write("the sort ring\n")
  eq(Bag.defaultSort("ITEM"), "ALPHA", "a normal pocket opens A-Z")
  eq(Bag.defaultSort("TM_HM"), "CUSTOM",
     "TM/HM opens CUSTOM, because the cart already sorts that pocket by its "
     .. "own tmhmKey and that is the right answer")

  eq(Bag.nextSort("CUSTOM"), "ALPHA", "CUSTOM -> A-Z")
  eq(Bag.nextSort("ALPHA"), "QUANTITY", "A-Z -> QUANTITY")
  eq(Bag.nextSort("QUANTITY"), "CUSTOM", "and QUANTITY wraps back")
  eq(Bag.nextSort(nil), "ALPHA", "an unset mode steps off the first")
  eq(Bag.nextSort("NONSENSE"), "ALPHA", "as does one nobody recognises")
end

-- ------------------------------------------------------- all three at once

do
  io.write("filter, then sort, then float\n")

  local rows = {
    row("SUPER_POTION", "SUPER POTION", 1),
    row("POTION", "POTION", 9),
    row("ANTIDOTE", "ANTIDOTE", 5),
    row("MAX_POTION", "MAX POTION", 2),
  }

  -- The order of the three passes is the contract: a search narrows what
  -- there is, the sort arranges what is left, and the pins float to the top
  -- of that.
  eq(ids(Bag.arrange(rows, { query = "POTION", sort = "ALPHA",
                             pinned = Bag.indexOf({ "SUPER_POTION" }) })),
     "SUPER_POTION MAX_POTION POTION",
     "the search drops ANTIDOTE, A-Z orders the rest, and the pin tops it")

  eq(ids(Bag.arrange(rows, {})), ids(rows),
     "no query, no sort and no pins is the cart's own list, untouched")

  -- A pin on something the search excluded must not drag it back in.
  eq(ids(Bag.arrange(rows, { query = "ANTI",
                             pinned = Bag.indexOf({ "POTION" }) })),
     "ANTIDOTE",
     "a pinned item the search excluded stays excluded -- the filter runs "
     .. "first, and a search that showed things it filtered out would be a "
     .. "search that lies")
end

io.write(("bag gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
