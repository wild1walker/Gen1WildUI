-- MOVE carries a POKeMON through Gold's party, instead of swapping two.
--
-- Gold's own move is an EXCHANGE.  `beginSwitch` parks a '▷', `updateSwitch`
-- walks the cursor, and A runs `finishSwitch`, whose whole reorder is
--
--     party[from], party[to] = party[to], party[from]
--
-- The difference from Red's carry only shows past one row: carrying the
-- fourth member to the top should leave the three it passed in the order they
-- were already in, and a swap trades the ends and leaves the middle alone.
-- So the first thing this file does is READ that line off the cart, because
-- an assertion about "the cart swaps" written against a stub that swaps
-- proves nothing at all.
--
-- The rest is the contract of ./gen2carry.lua: that a step is
-- an adjacent exchange, that a run of them is an insertion, that the cursor
-- and the held marker ride the POKeMON rather than staying on a row, that the
-- mail pairs with every step and only when the list IS the save's party, that
-- B walks it home exactly however far it went, and that the carried row
-- flashes.
--
-- Run:  luajit tests/partycarry_gen2_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then passed = passed + 1
  else failed = failed + 1; io.write("  FAIL  ", description, "\n") end
end
local function eq(actual, expected, description)
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end
local function order(party)
  local names = {}
  for i = 1, #party do names[i] = party[i].name end
  return table.concat(names, ",")
end

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  -- Two layouts: this mod standing on its own beside a checkout, and the same
  -- file inside a bundle several directories down.  Both are listed rather
  -- than guessed, because a locator that finds nothing SKIPS the file, and a
  -- silently skipped suite reports a pass it never earned.
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    for _, name in ipairs({ "gen1recompog", "gen1recomp", "bryanthaboi/gen1recomp" }) do
      candidates[#candidates + 1] = prefix .. "/" .. name
    end
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/PartyMenu.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("partycarry: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end

local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local t = handle:read("*a") handle:close() return t
end

-- ---- the cart's move, read off the cart

local partySrc = assert(slurp(ENGINE .. "/src/ui/gen2/PartyMenu.lua"),
  "src/ui/gen2/PartyMenu.lua is missing")

ok(partySrc:find("function PartyMenu:updateSwitch(input)", 1, true) ~= nil,
   "the move loop is updateSwitch(input) -- the seam this mod wraps")
ok(partySrc:find("function PartyMenu:drawIcon(mon, px, py)", 1, true) ~= nil,
   "and the icon draw is drawIcon(mon, px, py) -- the seam the flash wraps")
ok(partySrc:find("party[from], party[to] = party[to], party[from]", 1, true) ~= nil,
   "the cart's finishSwitch is an EXCHANGE, not a carry")
ok(partySrc:find("Mail.swapSlots(self.save, from, to)", 1, true) ~= nil,
   "and it pairs sPartyMail across the two slots")
ok(partySrc:find("if self.save and self.save.party == party then", 1, true) ~= nil,
   "...only when the list it moved IS the save's party")
ok(partySrc:find("self:playSfxTwice(\"Sfx_SwitchPokemon\")", 1, true) ~= nil,
   "letting go plays Sfx_SwitchPokemon twice")
ok(partySrc:find("self.switchFrom == i", 1, true) ~= nil,
   "the held row is drawn from switchFrom, so the marker follows it")

-- ---------------------------------------------------------------- harness

local warnings, infos = {}, {}
local options = { live_move = true }
local mod = {
  log = {
    warn = function(_, fmt, ...) warnings[#warnings + 1] = tostring(fmt):format(...) end,
    info = function(_, fmt, ...) infos[#infos + 1] = tostring(fmt):format(...) end,
  },
  options = { get = function(_, key) return options[key] end },
}

-- Gold's menu, reduced to the two methods the arm wraps.  `finishSwitch` is
-- the cart's own line, copied verbatim from the source asserted above -- so a
-- test that says "the base swaps" is saying what the cart says.
local baseCalls, drawn = {}, {}
local PartyMenu = {}
function PartyMenu:finishSwitch()
  local from, to = self.switchFrom, self.index
  self.switchFrom = nil
  if not (from and to) or from == to then return end
  local party = self.party
  party[from], party[to] = party[to], party[from]
end
function PartyMenu:updateSwitch(input)
  baseCalls[#baseCalls + 1] = true
  local total = #self.party
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
  elseif input:wasPressed("b") then
    self.switchFrom = nil
  elseif input:wasPressed("a") then
    self:finishSwitch()
  end
end
function PartyMenu:drawIcon(mon, px, py)
  drawn[#drawn + 1] = { mon = mon, px = px, py = py }
end
function PartyMenu:playSfxTwice(name) self.sfx = name end
-- The cart's own iconX, copied from the line asserted above: it answers "is
-- this the selected row" and, being an argument to the drawIcon call, runs
-- immediately before the draw it belongs to.  Present here because the mod
-- wraps it, and a stub without it would let a wrap that never installed pass.
function PartyMenu:iconX(index) return index == self.index and 8 or 0 end
local BASE_UPDATE, BASE_DRAW = PartyMenu.updateSwitch, PartyMenu.drawIcon
local BASE_ICONX = PartyMenu.iconX

local mailPairs = {}
local Mail = {
  swapSlots = function(save, a, b)
    mailPairs[#mailPairs + 1] = { save = save, a = a, b = b }
  end,
}

package.loaded["src.ui.gen2.PartyMenu"] = PartyMenu
package.loaded["src.core.gen2.Mail"] = Mail

local factory = assert(load(assert(slurp("modules/Gen1Party/gen2carry.lua")),
  "@gen2carry.lua"))()
local carry = factory(mod)
ok(type(carry.install) == "function", "the file builds an arm with install()")
ok(type(carry.step) == "function", "...and exposes step(), the whole rule")
eq(carry.install(), true, "it installs over Gold's PartyMenu")
ok(PartyMenu.updateSwitch ~= BASE_UPDATE, "updateSwitch is wrapped")
ok(PartyMenu.drawIcon ~= BASE_DRAW, "drawIcon is wrapped")
ok(PartyMenu.iconX ~= BASE_ICONX,
   "and so is iconX -- the seam that says which row is being drawn")
eq(carry.install(), true, "installing twice is not an error")
local wrapped = PartyMenu.updateSwitch
eq(carry.install() and PartyMenu.updateSwitch, wrapped,
   "...and does not wrap the wrap")

-- ---- the rule, on its own

do
  local party = { { name = "A" }, { name = "B" }, { name = "C" } }
  eq(carry.step(party, 2, -1, 3), 1, "a step returns where the mon landed")
  eq(order(party), "B,A,C", "and one step is an adjacent exchange")
  eq(carry.step(party, 1, -1, 3), 1, "a step off the top goes nowhere")
  eq(order(party), "B,A,C", "...and moves nothing")
  eq(carry.step(party, 3, 1, 3), 3, "nor off the bottom -- no wrap in a carry")
  eq(order(party), "B,A,C", "...and moves nothing there either")
end

-- ---------------------------------------------------------------- the carry

local function press(button)
  return { wasPressed = function(_, name) return name == button end }
end
local function screenOf(names)
  local party = {}
  for i, name in ipairs(names) do party[i] = { name = name } end
  local save = { party = party }
  return setmetatable({ party = party, save = save, index = 1, clock = 0 },
    { __index = PartyMenu })
end

-- The whole complaint, in one sequence: the fourth member walks to the top.
do
  mailPairs = {}
  local screen = screenOf({ "A", "B", "C", "D", "E" })
  screen.index, screen.switchFrom = 4, 4
  screen:updateSwitch(press("up"))
  eq(order(screen.party), "A,B,D,C,E", "one press moves it one row")
  eq(screen.index, 3, "the cursor rides the POKeMON")
  eq(screen.switchFrom, 3, "...and so does the '▷' on the held row")
  screen:updateSwitch(press("up"))
  screen:updateSwitch(press("up"))
  eq(order(screen.party), "D,A,B,C,E",
     "three presses INSERT it at the top -- the passed rows keep their order")
  ok(order(screen.party) ~= "D,B,C,A,E",
     "...which is not what the cart's exchange would have left")
  eq(screen.index, 1, "the cursor arrived with it")
  eq(#mailPairs, 3, "the letter paired on every step, not once at the end")
  eq(mailPairs[1].a .. "->" .. mailPairs[1].b, "4->3", "first pair is 4,3")
  eq(mailPairs[3].a .. "->" .. mailPairs[3].b, "2->1", "last pair is 2,1")
  eq(mailPairs[1].save, screen.save, "and it is the save's mail that moved")

  -- A lets go, and commits nothing, because every step already did.
  local before = order(screen.party)
  screen:updateSwitch(press("a"))
  eq(order(screen.party), before, "A changes no order -- the carry already did")
  eq(screen.switchFrom, nil, "and the POKeMON is put down")
  eq(screen.sfx, "Sfx_SwitchPokemon", "with the cart's own sound")
end

-- Down, and the edges.
do
  local screen = screenOf({ "A", "B", "C" })
  screen.index, screen.switchFrom = 1, 1
  screen:updateSwitch(press("down"))
  screen:updateSwitch(press("down"))
  eq(order(screen.party), "B,C,A", "DOWN carries it to the bottom")
  eq(screen.index, 3, "cursor with it")
  screen:updateSwitch(press("down"))
  eq(order(screen.party), "B,C,A",
     "and the bottom is the bottom -- a carried mon does not wrap to slot 1")
  eq(screen.index, 3, "the cursor does not wrap either")
end

-- B puts it back, exactly, however far it went.
do
  mailPairs = {}
  local screen = screenOf({ "A", "B", "C", "D", "E" })
  local origin = order(screen.party)
  screen.index, screen.switchFrom = 5, 5
  for _ = 1, 4 do screen:updateSwitch(press("up")) end
  eq(order(screen.party), "E,A,B,C,D", "carried from the bottom to the top")
  screen:updateSwitch(press("b"))
  eq(order(screen.party), origin, "B restores the party it started as")
  eq(screen.index, 5, "and the cursor goes home with it")
  eq(screen.switchFrom, nil, "the POKeMON is put down")
  eq(#mailPairs, 8, "the letter walked home too, a pair per row")
end

-- A list that is not the save's party has no mail to carry.
do
  mailPairs = {}
  local screen = screenOf({ "A", "B", "C" })
  screen.save = { party = { { name = "elsewhere" } } }
  screen.index, screen.switchFrom = 3, 3
  screen:updateSwitch(press("up"))
  eq(order(screen.party), "A,C,B", "a battle copy still reorders")
  eq(#mailPairs, 0, "...but sPartyMail is keyed to the SAVE's slots, untouched")
end

-- Nothing in hand is the cart's business, not ours.
do
  baseCalls = {}
  local screen = screenOf({ "A", "B", "C" })
  screen.index = 2
  screen:updateSwitch(press("up"))
  eq(#baseCalls, 1, "with no POKeMON held, the cart's own loop runs")
  eq(screen.index, 1, "and it walks the cursor the way it always did")
end

-- Off, the cart is the cart.
do
  options.live_move = false
  baseCalls = {}
  local screen = screenOf({ "A", "B", "C", "D" })
  screen.index, screen.switchFrom = 4, 4
  screen:updateSwitch(press("up"))
  screen:updateSwitch(press("up"))
  screen:updateSwitch(press("up"))
  eq(#baseCalls, 3, "MOVE NOT SWITCH off hands every press to the cart")
  eq(order(screen.party), "A,B,C,D", "...which moves nothing until A")
  screen:updateSwitch(press("a"))
  eq(order(screen.party), "D,B,C,A", "and then EXCHANGES the ends")
  options.live_move = true
end

-- ---------------------------------------------------------------- the flash

do
  local screen = screenOf({ "A", "B", "C" })
  screen.switchFrom = 2

  local function frames(row)
    local lit, dark = 0, 0
    for clock = 0, 47 do
      screen.clock, screen.gen1wildCarryRow = clock, row
      drawn = {}
      screen:drawIcon(screen.party[row], 0, 0)
      if #drawn == 1 then lit = lit + 1 else dark = dark + 1 end
    end
    return lit, dark
  end

  local lit, dark = frames(2)
  eq(lit, 32, "the carried row is lit for sixteen of every twenty-four frames")
  eq(dark, 16, "...and dark for eight -- it blinks, twice as long lit as dark")

  lit, dark = frames(1)
  eq(lit, 48, "a row that is not in your hand never blinks")
  eq(dark, 0, "...it is simply drawn")

  screen.switchFrom = nil
  lit, dark = frames(2)
  eq(lit, 48, "and with nothing held, nothing flashes at all")

  options.live_move = false
  screen.switchFrom = 2
  lit, dark = frames(2)
  eq(lit, 48, "MOVE NOT SWITCH off draws every frame, the cart's way")
  options.live_move = true
end

-- ---- the row that records which icon is being drawn

--
-- Owned by this file rather than borrowed.  It used to read the field the
-- Gen1Wild bundle's runtime/icons2.lua sets at this same seam -- so installed
-- on its own, with no bundle, nothing set it and the carried POKeMON never
-- flashed: the one visible half of MOVE, missing, on exactly the installs with
-- no bundle to fall back on.  So the assertion is behavioural: what matters is
-- that the row arrives and the icon blinks, not that a line of code exists.
do
  ok(partySrc:find("self:drawIcon(mon, self:iconX(i)", 1, true) ~= nil,
     "the cart calls iconX(i) in the drawIcon line, so that index IS the row "
     .. "the next draw paints")

  local screen = screenOf({ "A", "B", "C" })
  screen:iconX(2)
  eq(screen.gen1wildCarryRow, 2,
     "and this mod records it there itself, with no bundle to help")

  screen.switchFrom = 2
  screen.clock = 20               -- the dark half of the cycle
  drawn = {}
  screen:iconX(2)
  screen:drawIcon(screen.party[2], 0, 0)
  eq(#drawn, 0, "so a carried POKeMON goes dark with nothing else installed")
  screen.clock = 0
  screen:iconX(2)
  screen:drawIcon(screen.party[2], 0, 0)
  eq(#drawn, 1, "...and lights again")
end

-- ---- and it is wired into the Gold arm

do
  local main = assert(slurp("modules/Gen1Party/main.lua"))
  ok(main:find("gen2carry.lua", 1, true) ~= nil,
     "the Gold arm loads gen2carry.lua")
  ok(main:find("mod.exports.gen2carry = built", 1, true) ~= nil,
     "...and publishes it")
  ok(main:find('key = "live_move"', 1, true) ~= nil,
     "the MOVE NOT SWITCH row exists")
  local schema = main:match('schema%[#schema %+ 1%] = { key = "live_move".-}')
  ok(schema ~= nil, "...as a schema row")
  ok(not main:find('if not isGen2 then\n%s*%-%- The popup'),
     "...and is no longer fenced off from Gold")
end

io.write(("partycarry: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
