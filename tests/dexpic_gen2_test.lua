-- The dex entry's pic when the cart cannot find one.
--
-- Reported as "the sprite is missing", on an entry whose name, kind, number,
-- footprint and action bar were all correct.  Measured off the screenshot
-- rather than judged: the seven-by-seven block where the picture goes was
-- 118,608 pixels of exactly one value, (0,0,0), and the whole 160x144 frame
-- carried three colours -- paper, ink and the dex sheet's orange.  The
-- POKeMON's own two palette colours were not on the screen anywhere.
--
-- Only one path in `drawPic` produces that, and this file pins it: the early
-- return for a missing image comes BEFORE the plate is filled, so a species
-- whose picture does not resolve draws nothing at all and leaves the page
-- around it untouched -- which looks exactly like the mod not being installed.
--
-- Run:  luajit tests/dexpic_gen2_test.lua
--       (needs an engine tree; SKIPs without one)

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
  io.write("dex pic gen2: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end

local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local text = handle:read("*a") handle:close() return text
end

local dexSrc = assert(slurp(ENGINE .. "/src/ui/gen2/PokedexMenu.lua"))
local src = assert(slurp("modules/Gen1Dex/gen2pic.lua"))

-- ---- the silent early return, read off the cart

local pic = dexSrc:match("function PokedexMenu:drawPic.-\nend\n")
assert(pic, "could not find drawPic in the engine")
ok(pic:find("if not image then return end", 1, true) ~= nil,
   "drawPic returns silently when the picture does not resolve")
local cut = pic:find("if not image then return end", 1, true)
local plate = pic:find('G.rectangle("fill", tx * 8, ty * 8, 7 * 8, 7 * 8)', 1, true)
ok(cut and plate and cut < plate,
   "and it returns BEFORE the plate is filled -- so nothing at all is drawn, "
   .. "which is the uniform black square that was reported")
ok(pic:find("image = self:questionMark()", 1, true) ~= nil,
   "an unseen row takes the question mark instead")
ok(pic:find("colors = self.gfx and self.gfx.questionMarkPalette", 1, true) ~= nil,
   "in the question-mark palette -- the cart's own way of saying it has none")
ok(dexSrc:find("function PokedexMenu:picFor(species)", 1, true) ~= nil,
   "picFor is a method, so the wrap can ask the same question the cart asks")
ok(dexSrc:find("local path = def and def.spriteFront", 1, true) ~= nil,
   "and it resolves through def.spriteFront")

-- The same field the battle draws from, which is why the cause is not obvious
-- and why this ships a diagnostic rather than a guess.
local battleSrc = assert(slurp(ENGINE .. "/src/ui/gen2/BattleState.lua"))
ok(battleSrc:find("local path = def and (back and def.spriteBack or def.spriteFront)",
                  1, true) ~= nil,
   "a battle pic comes from the very same spriteFront")

-- ---- and the plate arm that used to sit on top of this is gone

local themeSrc = assert(slurp("runtime/theme2.lua"))
ok(themeSrc:find("PokedexMenu.drawPic", 1, true) == nil,
   "theme2 no longer repaints the pic's plate -- it answered a complaint that "
   .. "was never made, and it made a missing pic indistinguishable from paper")
ok(themeSrc:find("__gen1wildDexPlate", 1, true) == nil, "and its mark is gone")

-- ---- the module, run

local drawn = {}
local PokedexMenu = {}
PokedexMenu.__index = PokedexMenu
package.loaded["src.ui.gen2.PokedexMenu"] = PokedexMenu
function PokedexMenu:picFor(species)
  return (self.pokemon[species] or {}).spriteFront and "IMAGE" or nil
end
function PokedexMenu:drawPic(row, tx, ty, ownColors)
  drawn[#drawn + 1] = ("%s seen=%s own=%s"):format(
    row.species, tostring(row.seen), tostring(ownColors))
  return "drawn"
end

local warnings = {}
local mod = {
  log = { warn = function(_, f, ...) warnings[#warnings + 1] = f:format(...) end,
          info = function() end, error = function() end },
  options = { get = function() return nil end },
}
local Pic = assert(loadfile("modules/Gen1Dex/gen2pic.lua"))()(mod, {})
eq(Pic.install(), true, "it installs")
eq(Pic.install(), true, "and is idempotent")

local function screen(pokemon)
  return setmetatable({ pokemon = pokemon }, PokedexMenu)
end

do -- a pic that resolves is none of this file's business
  drawn = {}
  local s = screen({ PIDGEY = { spriteFront = "front.png" } })
  eq(s:drawPic({ species = "PIDGEY", seen = true }, 1, 1, true), "drawn",
     "a species with a picture draws it")
  eq(drawn[1], "PIDGEY seen=true own=true", "untouched, seen and all")
end

do -- a pic that does not resolve gets the cart's own placeholder
  drawn = {}
  warnings = {}
  local s = screen({ PIDGEY = {} })
  s:drawPic({ species = "PIDGEY", seen = true }, 1, 1, true)
  eq(drawn[1], "PIDGEY seen=false own=true",
     "a species with no picture is handed to the cart as UNSEEN, so the cart "
     .. "draws its own question mark rather than this file drawing anything")
  eq(#warnings, 1, "and it says so once")
  ok(warnings[1]:find("has no spriteFront", 1, true) ~= nil,
     "naming which of the three links broke")
  s:drawPic({ species = "PIDGEY", seen = true }, 1, 1, true)
  eq(#warnings, 1, "once per species, not once per frame")
end

do -- the row is not mutated: `seen` is the dex's own record
  local row = { species = "PIDGEY", seen = true, caught = true }
  screen({ PIDGEY = {} }):drawPic(row, 1, 1, true)
  eq(row.seen, true, "the row handed in still says it was seen")
end

do -- the three links, named apart
  eq(Pic.report(nil, "PIDGEY"), "the dex has no `pokemon` table at all",
     "no table at all")
  ok(Pic.report({}, "PIDGEY"):find("no row for `PIDGEY`", 1, true) ~= nil,
     "a key that does not match")
  ok(Pic.report({ PIDGEY = {} }, "PIDGEY"):find("has no spriteFront", 1, true) ~= nil,
     "a row with no sprite")
  ok(Pic.report({ PIDGEY = { spriteFront = "a.png" } }, "PIDGEY")
       :find("did not load", 1, true) ~= nil,
     "and a sprite that would not load")
end

do -- a whole sheet missing does not become 251 log lines
  -- Its own class, because the arm counts per INSTALL and the one above has
  -- already reported PIDGEY -- installing a second arm over a class that
  -- carries the mark is a no-op, so it would have been the first arm's
  -- counter answering, four species in.
  local M = {}
  M.__index = M
  package.loaded["src.ui.gen2.PokedexMenu"] = M
  function M:picFor() return nil end
  function M:drawPic() return "drawn" end
  warnings = {}
  local P = assert(loadfile("modules/Gen1Dex/gen2pic.lua"))()(mod, {})
  eq(P.install(), true, "a fresh class takes its own arm")
  local s = setmetatable({ pokemon = {} }, M)
  for i = 1, 20 do
    s:drawPic({ species = "MON" .. i, seen = true }, 1, 1, true)
  end
  eq(#warnings, 6, "five species, then one line saying there are more")
  ok(warnings[6]:find("a sheet rather than a species", 1, true) ~= nil,
     "and it names the shape of that failure")
  package.loaded["src.ui.gen2.PokedexMenu"] = PokedexMenu
end

do -- an unseen row is left entirely alone: it is already the question mark
  drawn = {}
  warnings = {}
  screen({}):drawPic({ species = "MEW", seen = false }, 1, 1, true)
  eq(drawn[1], "MEW seen=false own=true", "handed straight through")
  eq(#warnings, 0, "with nothing to report -- the cart has an answer for it")
end

package.loaded["src.ui.gen2.PokedexMenu"] = nil

-- ---- wired up

local mainSrc = assert(slurp("modules/Gen1Dex/main.lua"))
local branch = mainSrc:match("if isGen2 then(.-)\n    return\n  end")
assert(branch, "could not find the isGen2 branch")
ok(branch:find('loadSibling(mod, "gen2pic.lua")', 1, true) ~= nil,
   "main.lua builds it on Gold")
local pic_at = branch:find('loadSibling(mod, "gen2pic.lua")', 1, true)
local unseen_at = branch:find('loadSibling(mod, "gen2unseen.lua")', 1, true)
ok(pic_at and unseen_at and pic_at < unseen_at,
   "before the mask, so the mask's wrap stays the outermost of them all")

io.write(("dex pic gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
