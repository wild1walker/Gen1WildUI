-- Gold's dex entry for a POKeMON you have never met: opened, and masked.
--
-- Reported against the Gold dex: "I should be able to click on an undiscovered
-- mon and see their page but have the info replaced with dashes, and I should
-- be able to look at the area map for the undiscovered and see their nest, but
-- no spoilers anywhere, like how we did Gen 1.  And their picture can stay
-- the ?"
--
-- Two halves, and the second is the one worth testing hardest.  Opening the
-- entry is four lines.  Making sure that entry does not NAME the POKeMON is
-- the feature: the cart draws its name, its kind, its footprint and its cry
-- from four different places, our own three extra pages would put its base
-- stats and its whole movelist on the same screen, and PRNT reads the name off
-- the species table rather than through `monName` -- so masking the screen
-- would not have masked the printout.
--
-- Every one of those five is read off the ENGINE below, not restated, because
-- a mask written from memory hides the parts you remembered.
--
-- Run:  luajit tests/dexunseen_gen2_test.lua
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
  io.write("dex unseen gen2: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end

local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

local dexSrc = assert(slurp(ENGINE .. "/src/ui/gen2/PokedexMenu.lua"))
local src = assert(slurp("modules/Gen1Dex/gen2unseen.lua"))
local gen2Src = assert(slurp("modules/Gen1Dex/gen2.lua"))

-- ---- the press the cartridge refuses

ok(dexSrc:find("-- Pokedex_UpdateMainScreen's .a returns unless the mon has been seen.",
               1, true) ~= nil,
   "the cart's list arm returns unless the row has been SEEN")
ok(dexSrc:find("if row and row.seen then\n      self.view = \"entry\"", 1, true) ~= nil,
   "so an undiscovered row is a dead press, with nothing to fall through from")
ok(dexSrc:find("self:playCry(row.species)", 1, true) ~= nil,
   "and opening the entry cries the species -- the loudest name it has")

-- ---- the five places a name gets out

-- 1. the list's own token for a row it will not name
ok(dexSrc:find('self:text("-----", 1, ty)', 1, true) ~= nil,
   "the cart prints five dashes for an unseen row in the LIST")
ok(src:find('self.UNSEEN = "-----"', 1, true) ~= nil,
   "and the entry masks with the same five, so the two screens agree")

-- 2/3. the entry's name and kind
local body = dexSrc:match("function PokedexMenu:drawEntryBody.-\nend\n")
assert(body, "could not find drawEntryBody in the engine")
ok(body:find("self:text(self:monName(row.species), 9, 3)", 1, true) ~= nil,
   "the entry draws the name through self:monName -- shadowable on the instance")
ok(body:find('self:text(entry.kind or "", 9, 5)', 1, true) ~= nil,
   "and the kind straight off the entry -- so the entry is masked as data")
ok(src:find("out.kind = self.UNSEEN", 1, true) ~= nil, "which maskEntry does")

-- 4. the footprint
ok(body:find("self:drawFootprint(row.species, 18, 1)", 1, true) ~= nil,
   "the footprint is a method call too, so it is shadowed rather than erased")

-- 5. PRNT, which does NOT go through monName
local printEntry = dexSrc:match("function PokedexMenu:printEntry.-\nend\n")
assert(printEntry, "could not find printEntry in the engine")
ok(printEntry:find("self.pokemon[row.species].name", 1, true) ~= nil,
   "PRNT reads the name off the species table, NOT through monName -- so "
   .. "masking the screen would not have masked the printout")
ok(src:find("screen.printEntry = function() end", 1, true) ~= nil,
   "which is why PRNT is stood down whole rather than masked")

-- and the AREA header, which is the screen the player came for
ok(dexSrc:find("self:drawAreaHeader(Strings(NEST_TITLE, self:monName(row.species)))",
               1, true) ~= nil,
   "the AREA header names the species through monName as well")

-- ---- what was ALREADY masked, and is therefore not this file's business

local pic = dexSrc:match("function PokedexMenu:drawPic.-\nend\n")
assert(pic, "could not find drawPic")
ok(pic:find("image = self:questionMark()", 1, true) ~= nil,
   "an unseen row already draws the question mark, whatever the caller asked")
ok(src:find("PokedexMenu.drawPic", 1, true) == nil,
   "so this file never wraps drawPic -- the ? stays, as asked")
-- gen2pic.lua wraps drawPic, to put the cart's own question mark where a
-- picture would not resolve -- and it hands an unseen row straight through,
-- because the cart already draws the question mark for one.  So the ? an
-- undiscovered entry shows is the cart's, reached by the cart's own path.
local picSrc = assert(slurp("modules/Gen1Dex/gen2pic.lua"))
ok(picSrc:find("if not (row and row.seen and row.species) then", 1, true) ~= nil,
   "and the one arm that does wrap it hands an unseen row straight through")
ok(body:find("if not row.caught then", 1, true) ~= nil,
   "and height, weight and the description already stop at CAUGHT")

-- ---- our own three pages, which would put the whole POKeMON back

ok(gen2Src:find("local function seenHere(screen)", 1, true) ~= nil,
   "gen2.lua asks whether the row was seen")
ok(gen2Src:find("if not seenHere(screen) then return nil end", 1, true) ~= nil,
   "and pageKind refuses STATS, EVOLVES and MOVES on an unseen entry")
ok(gen2Src:find("or not seenHere(screen) then", 1, true) ~= nil,
   "and the page COUNTER stops there too, so PAGE stays the cart's toggle")

-- ---- the module, run against a stand-in of the cart's own class

local PokedexMenu = {}
PokedexMenu.__index = PokedexMenu
local log = {}
package.loaded["src.ui.gen2.PokedexMenu"] = PokedexMenu

-- The five things the real class does that this file cares about.
function PokedexMenu:current() return self.rows[self.index] end
function PokedexMenu:monName(species)
  return (self.pokemon[species] or {}).name or species
end
function PokedexMenu:drawFootprint(species) log[#log + 1] = "foot:" .. species end
function PokedexMenu:playCry(species) log[#log + 1] = "cry:" .. tostring(species) end
function PokedexMenu:printEntry() log[#log + 1] = "print:" .. self:current().species end

function PokedexMenu:update()
  local input = self.game.input
  if self.view == "list" then
    if input:wasPressed("a") then
      local row = self:current()
      if row and row.seen then
        self.view, self.page = "entry", 1
        self:playCry(row.species)
      end
    end
    return "list"
  end
  if self.view == "entry" and input:wasPressed("a") then
    local action = self.entryAction
    if action == "AREA" then self.view = "area"
    elseif action == "CRY" then self:playCry(self:current().species)
    elseif action == "PRNT" then self:printEntry() end
  end
  return "entry"
end

function PokedexMenu:drawEntryBody(row, entry)
  log[#log + 1] = "name:" .. self:monName(row.species)
  log[#log + 1] = "kind:" .. tostring(entry.kind)
  log[#log + 1] = "text:" .. tostring(entry.text)
  self:drawFootprint(row.species)
  return "entry-drawn"
end

function PokedexMenu:drawArea()
  log[#log + 1] = "nest:" .. self:monName(self:current().species)
  return "area-drawn"
end

local warnings = {}
local function makeMod(get)
  return {
    log = {
      warn = function(_, fmt, ...) warnings[#warnings + 1] = fmt:format(...) end,
      info = function() end, error = function() end,
    },
    options = { get = function(_, key) return get and get(key) end },
  }
end

local Unseen = assert(loadfile("modules/Gen1Dex/gen2unseen.lua"))()(makeMod(), {})
eq(Unseen.UNSEEN, "-----", "the mask is the cart's own five dashes")
eq(Unseen.install(), true, "it installs over the class")
eq(Unseen.install(), true, "and is idempotent -- a second install wraps nothing")

local pressed
local function screen(index)
  return setmetatable({
    view = "list", index = index, page = 1, entryAction = "PAGE",
    rows = { { species = "PIDGEY", seen = true, caught = true },
             { species = "MEW", seen = false, caught = false } },
    pokemon = { PIDGEY = { name = "PIDGEY" }, MEW = { name = "MEW" } },
    game = { input = { wasPressed = function(_, key) return key == pressed end } },
  }, PokedexMenu)
end
local SEEN, UNSEEN = 1, 2

do -- the press
  log = {}
  local s = screen(UNSEEN)
  pressed = "a"
  s:update()
  eq(s.view, "entry", "A on an undiscovered row opens the entry")
  eq(s.page, 1, "on page one")
  eq(#log, 0, "and says nothing -- no cry on the way in")
end

do -- a seen row is the cart's, cry and all
  log = {}
  local s = screen(SEEN)
  pressed = "a"
  s:update()
  eq(s.view, "entry", "A on a row you have met still opens the entry")
  eq(log[1], "cry:PIDGEY", "and still cries it")
end

do -- the entry, masked
  log = {}
  local s = screen(UNSEEN)
  s.view = "entry"
  eq(s:drawEntryBody(s:current(), { kind = "NEW SPECIE", text = "SO RARE" }),
     "entry-drawn", "the cart's own body still draws")
  eq(log[1], "name:-----", "with the name masked")
  eq(log[2], "kind:-----", "the kind masked")
  eq(log[3], "text:nil", "the description gone")
  eq(log[4], nil, "and no footprint -- a silhouette is a portrait")
  eq(rawget(s, "monName"), nil, "the shadow is taken back off afterwards")
  eq(rawget(s, "drawFootprint"), nil, "all four of them")
  eq(s:monName("MEW"), "MEW", "so the class method answers again")
end

do -- a seen entry is untouched
  log = {}
  local s = screen(SEEN)
  s:drawEntryBody(s:current(), { kind = "TINYBIRD", text = "IT FLIES" })
  eq(log[1], "name:PIDGEY", "a POKeMON you have met is named")
  eq(log[2], "kind:TINYBIRD", "with its kind")
  eq(log[4], "foot:PIDGEY", "and its footprint")
end

do -- the AREA map: the nests are the point, the name is not
  log = {}
  local s = screen(UNSEEN)
  s.view = "area"
  eq(s:drawArea(), "area-drawn", "the nest map draws for an undiscovered mon")
  eq(log[1], "nest:-----", "under a masked header")
  log = {}
  local seen = screen(SEEN)
  seen.view = "area"
  seen:drawArea()
  eq(log[1], "nest:PIDGEY", "and a met one keeps its own")
end

do -- CRY and PRNT, from inside the masked entry
  log = {}
  local s = screen(UNSEEN)
  s.view, s.entryAction, pressed = "entry", "CRY", "a"
  s:update()
  eq(#log, 0, "CRY is silent on an undiscovered entry")
  s.entryAction = "PRNT"
  s:update()
  eq(#log, 0, "and PRNT does not print it")
  s.entryAction = "AREA"
  s:update()
  eq(s.view, "area", "AREA still works -- it is what the entry was opened for")
  eq(rawget(s, "playCry"), nil, "and the shadows come back off after update too")
end

do -- the row is live and gates the press
  local Off = assert(loadfile("modules/Gen1Dex/gen2unseen.lua"))()(
    makeMod(function(key) return key == "area_unseen" and false or nil end), {})
  -- installed over the already-wrapped class; the mark makes it a no-op, so
  -- this drives the wrap that IS installed through a mod whose row is off
  eq(Off.install(), true, "a second arm finds the class already wrapped")
end

do -- the mask failing must not become the leak it exists to prevent
  local M = {}
  M.__index = M
  package.loaded["src.ui.gen2.PokedexMenu"] = M
  function M:current() return self.rows[self.index] end
  function M:monName(s) return s end
  function M:drawFootprint() end
  function M:playCry() end
  function M:printEntry() end
  function M:update() return "base-update" end
  function M:drawArea() error("kaboom", 0) end
  function M:drawEntryBody() error("kaboom", 0) end

  local Boom = assert(loadfile("modules/Gen1Dex/gen2unseen.lua"))()(makeMod(), {})
  eq(Boom.install(), true, "it installs over the broken class")
  local s = setmetatable({
    view = "area", index = 1, rows = { { species = "MEW", seen = false } },
    game = { input = { wasPressed = function() return false end } },
  }, M)

  eq(s:drawArea(), nil, "a throwing draw is caught rather than crashing the dex")
  eq(rawget(s, "monName"), nil, "and the shadows are still put back")
  eq(s.view, "list", "the screen the player was standing in is sent back out")
  local named = false
  for _, w in ipairs(warnings) do
    if w:find("AREA ON UNSEEN stood down", 1, true) then named = true end
  end
  ok(named, "and it says so once")

  -- Stood down now.  The cartridge's own screen is NOT the safe fallback here:
  -- it is the name, the kind, the footprint and the cry this file exists to
  -- withhold, reached through a press the cartridge does not allow.
  s.view = "entry"
  eq(s:drawEntryBody({ species = "MEW", seen = false }, {}), nil,
     "a stood-down mask draws nothing rather than the unmasked body")
  eq(s:drawArea(), nil, "and nothing on the nest map either")
  s.view = "list"
  pressed = "a"
  s.game.input.wasPressed = function(_, key) return key == "a" end
  eq(s:update(), "base-update", "the press goes back to the cartridge's own")
  eq(s.view, "list", "which refuses it, so the entry cannot be opened again")

  -- and a row that HAS been seen is unaffected by any of it
  s.rows[1].seen = true
  eq(s:update(), "base-update", "a seen row is the cart's either way")
end

package.loaded["src.ui.gen2.PokedexMenu"] = nil

-- ---- wired up

local mainSrc = assert(slurp("modules/Gen1Dex/main.lua"))
local gen2Branch = mainSrc:match("if isGen2 then(.-)\n    return\n  end")
assert(gen2Branch, "could not find the isGen2 branch in main.lua")
ok(gen2Branch:find('loadSibling(mod, "gen2unseen.lua")', 1, true) ~= nil,
   "main.lua builds the Gold arm inside the generation branch")
ok(mainSrc:find("area_unseen = true,", 1, true) ~= nil,
   "AREA ON UNSEEN is on Gold's OPTION screen now that it does something there")

-- The order is load-bearing: the mask shadows the screen's own methods, so it
-- has to be the OUTERMOST wrap or the pages and the caption draw before the
-- shadows are in place.
local pages = gen2Branch:find('loadSibling(mod, "gen2.lua")', 1, true)
local area = gen2Branch:find('loadSibling(mod, "gen2area.lua")', 1, true)
local unseen = gen2Branch:find('loadSibling(mod, "gen2unseen.lua")', 1, true)
ok(pages and area and unseen and pages < area and area < unseen,
   "and builds it LAST, so its wrap is the outermost of the three")

io.write(("dex unseen gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
