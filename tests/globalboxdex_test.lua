-- The POKeDEX hears about a POKeMON that came out of the GLOBAL BOX.
--
-- Reported twice.  The first time as "moving things with box does not update
-- dex", which put `registerReceived` on the withdrawal.  The second time, after
-- that shipped, from a Crystal player: "is there a way to make pokemon that
-- come from global box count to pokedex caught?"
--
-- The withdrawal was registering on Gold -- as SEEN.  Red keeps the second set
-- as `pokedex.owned` and Gold keeps it as `pokedex.caught`, and the first fix
-- only knew Red's name.  So this drives both shapes, each the way its engine
-- builds a fresh save (src/core/SaveData.lua and src/core/gen2/Save.lua), and
-- the sweep that credits the POKeMON already taken out before the fix.
--
-- The shipped globalpane.lua and globalbox.lua are loaded, not copies.
--
-- Run:  luajit tests/globalboxdex_test.lua

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

local function chunk(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))
end

local generation = 2
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  get = function() return generation == 2 and "crystal" or "red" end,
}

local mod = {
  id = "gen1_wild_ui_nightly",
  save = { get = function() return nil end, set = function() end },
  log = setmetatable({}, { __index = function() return function() end end }),
}

local GlobalBox = chunk("modules/Gen1BillsBox/globalbox.lua")()
local Pane = chunk("modules/Gen1BillsBox/globalpane.lua")()(mod, GlobalBox)

-- What a fresh save carries, generation by generation.
local function goldSave()
  return { pokedex = { seen = {}, caught = {} }, party = {}, boxes = {} }
end
local function redSave()
  return { pokedex = { seen = {}, owned = {} }, party = {}, boxes = {} }
end

do
  io.write("a withdrawal on Gold is CAUGHT, not only seen\n")
  generation = 2
  local game = { save = goldSave() }
  ok(Pane.registerReceived(game, { species = 155 }), "it registers")
  eq(game.save.pokedex.seen[155], true, "seen")
  eq(game.save.pokedex.caught[155], true,
     "and caught -- Gold's own name for the set the first fix wrote as `owned`")
  eq(game.save.pokedex.owned, nil, "and no Red-shaped set is invented")
end

do
  io.write("a withdrawal on Red is OWNED, as before\n")
  generation = 1
  local game = { save = redSave() }
  ok(Pane.registerReceived(game, { species = "PIKACHU" }), "it registers")
  eq(game.save.pokedex.seen.PIKACHU, true, "seen")
  eq(game.save.pokedex.owned.PIKACHU, true, "and owned")
  eq(game.save.pokedex.caught, nil, "and no Gold-shaped set is invented")
end

do
  io.write("an EGG is neither, until it hatches\n")
  generation = 2
  local game = { save = goldSave() }
  eq(Pane.registerReceived(game, { species = 172, isEgg = true }), false,
     "an EGG is refused")
  eq(game.save.pokedex.seen[172], nil, "not seen")
  eq(game.save.pokedex.caught[172], nil, "not caught")
end

do
  io.write("a save with no dex is left without one\n")
  local game = { save = {} }
  eq(Pane.registerReceived(game, { species = 1 }), false, "nothing to write to")
  eq(game.save.pokedex, nil, "and nothing created")
  eq(Pane.registerHeld({}), 0, "the sweep agrees")
  eq(Pane.registerHeld(nil), 0, "and survives no save at all")
end

do
  io.write("the sweep credits what a Gold save already holds\n")
  generation = 2
  local save = goldSave()
  -- Two taken out of the GLOBAL BOX before the fix: SEEN and nothing else.
  save.pokedex.seen[25] = true
  save.pokedex.seen[133] = true
  save.party = { { species = 25 }, { species = 155 } }
  save.boxes = {
    [1] = { { species = 133 }, { species = 172, isEgg = true } },
    [3] = { { species = 155 } },
  }
  save.pokedex.seen[155], save.pokedex.caught[155] = true, true
  eq(Pane.registerHeld(save), 2,
     "two species newly caught: the party's PIKACHU and box 1's EEVEE")
  eq(save.pokedex.caught[25], true, "PIKACHU, from the party")
  eq(save.pokedex.caught[133], true, "EEVEE, from a box")
  eq(save.pokedex.caught[172], nil, "the EGG beside it is left for its hatch")
  eq(save.pokedex.seen[172], nil, "and not even seen")
  eq(Pane.registerHeld(save), 0, "and a second load finds nothing to do")
end

do
  io.write("the sweep on a Red save writes OWNED\n")
  generation = 1
  local save = redSave()
  save.party = { { species = "MEW" } }
  save.boxes = { { { species = "ODDISH" } }, {} }
  eq(Pane.registerHeld(save), 2, "both")
  eq(save.pokedex.owned.MEW and save.pokedex.owned.ODDISH, true, "owned")
  eq(save.pokedex.seen.MEW and save.pokedex.seen.ODDISH, true, "and seen")
end

-- ------- wired to the load, and only on the two generations it understands

do
  io.write("Gen1BillsBox runs the sweep when a save loads\n")
  local source = assert(io.open("modules/Gen1BillsBox/main.lua")):read("*a")
  ok(source:find('mod.events:on("save.loaded"', 1, true) ~= nil,
     "it listens for save.loaded")
  ok(source:find("pane.registerHeld", 1, true) ~= nil, "and calls the sweep")
  ok(source:find("gen ~= 1 and gen ~= 2", 1, true) ~= nil,
     "and never on Gen 3, whose dex is a pair of bit arrays")
end

-- ------- a pick-up that is put back is not a catch
--
-- The screen holds a POKeMON taken off a GLOBAL page in hand until it lands in
-- the party or a box, and B or closing the screen puts it back through
-- `untake`.  A pick-up credits the dex at once (it has to: a POKeMON can go
-- straight into the party), so a put-back has to take back what it credited
-- -- or picking one up and changing your mind marks it caught.  A real
-- Session, against a store stood in for so the cells are plain tables.

local function fakeStore()
  local cells = {}
  local Store = setmetatable({
    genOf = function() return generation end,
    readAll = function() return {} end,
    cellsOf = function(bucket) bucket.cells = bucket.cells or {} return bucket.cells end,
    view = function() return {} end,
    remember = function() end,
    at = function(_, _, cell) return cells[cell] end,
    withdraw = function(_, _, _, _, cell)
      local entry = cells[cell]
      cells[cell] = nil
      return entry, { id = "t" .. cell, cell = cell, entry = entry }
    end,
    restore = function(_, ticket)
      cells[ticket.cell] = ticket.entry
      return true
    end,
    liveKey = function() return "live" end,
    ensureBucket = function() return {} end,
    reconcile = function() return 0, 0 end,
  }, { __index = GlobalBox })
  return Store, cells
end

local function sessionWith(save, mons)
  local Store, cells = fakeStore()
  for i, mon in ipairs(mons) do cells[i] = { mon = mon } end
  local pane = chunk("modules/Gen1BillsBox/globalpane.lua")()(mod, Store)
  local game = { save = save }
  return pane.open(game), game
end

do
  io.write("a POKeMON picked up and put back is not caught\n")
  generation = 2
  local session, game = sessionWith(goldSave(), { { species = 155 } })
  local dex = game.save.pokedex
  local mon, ticket = session:take(game, 1, 1)
  ok(mon ~= nil, "it can be picked up")
  eq(dex.caught[155], true, "in hand, it is caught -- it may go straight into the party")
  ok(session:untake(ticket), "and put back")
  eq(dex.caught[155], nil, "put back, it is not caught after all")
  eq(dex.seen[155], true, "but it was seen, and stays seen")
end

do
  io.write("one that is kept stays caught\n")
  generation = 2
  local session, game = sessionWith(goldSave(), { { species = 155 } })
  session:take(game, 1, 1)
  -- placed in the party: the screen never calls untake again
  eq(game.save.pokedex.caught[155], true, "kept, it is caught")
end

do
  io.write("two of one species: the dex follows the last one put back\n")
  generation = 2
  local session, game = sessionWith(goldSave(), { { species = 1 }, { species = 1 } })
  local dex = game.save.pokedex
  local _, first = session:take(game, 1, 1)
  local _, second = session:take(game, 1, 2)
  session:untake(second)
  eq(dex.caught[1], true, "one still out of the box: still caught")
  session:untake(first)
  eq(dex.caught[1], nil, "both back: not caught")

  local _, again = session:take(game, 1, 1)
  local _, kept = session:take(game, 1, 2)
  session:untake(again)
  eq(dex.caught[1], true, "and one kept keeps it caught")
  ok(kept ~= nil, "(the kept one)")
end

do
  io.write("a species already caught is never uncaught\n")
  generation = 2
  local save = goldSave()
  save.pokedex.caught[25], save.pokedex.seen[25] = true, true
  local session, game = sessionWith(save, { { species = 25 } })
  local _, ticket = session:take(game, 1, 1)
  session:untake(ticket)
  eq(game.save.pokedex.caught[25], true, "it was caught before the pick-up")
end

do
  io.write("and on Red, OWNED the same way\n")
  generation = 1
  local session, game = sessionWith(redSave(), { { species = 7 } })
  local _, ticket = session:take(game, 1, 1)
  eq(game.save.pokedex.owned[7], true, "in hand, owned")
  session:untake(ticket)
  eq(game.save.pokedex.owned[7], nil, "put back, not owned")
  eq(game.save.pokedex.seen[7], true, "still seen")
end

do
  io.write("the sweep records an UNOWN's letter on Gold\n")
  generation = 2
  local registered = {}
  package.loaded["src.core.gen2.Unown"] = {
    registerCatch = function(save, mon)
      if mon.species == 201 then registered[#registered + 1] = mon.letter end
      return true
    end,
  }
  local save = goldSave()
  save.party = { { species = 201, letter = "B" } }
  save.boxes = { { { species = 201, letter = "K" }, { species = 201, isEgg = true } } }
  Pane.registerHeld(save)
  eq(table.concat(registered, ","), "B,K",
     "each Unown in the party and the boxes is handed to the cart's own record")

  generation = 1
  registered = {}
  local red = redSave()
  red.party = { { species = 201, letter = "B" } }
  Pane.registerHeld(red)
  eq(#registered, 0, "and on Red the Gen 2 module is never asked")
  package.loaded["src.core.gen2.Unown"] = nil
end

io.write(("global box dex: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
