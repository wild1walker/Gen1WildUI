-- Crystal's animated front pics, on the #DEX entry.
--
-- The engine already drives them in one place -- `src/ui/gen2/SummaryMenu.lua`
-- starts a `MonAnimView`, steps it once per update and draws the frame it
-- hands back -- and the #DEX had no animation code at all.  `MonAnimView` is a
-- general runner (the egg hatch, the evolution and the trade all start one),
-- so the entry simply starts one too.
--
-- Gold and Silver caches carry no `anim` row, so `MonAnimView.start` gives
-- back nil there and every line of the arm is a no-op: the CART decides, not
-- the generation, which is why there is no per-cart branch.
--
-- Run:  luajit tests/dexanim_gen2_test.lua
--       (needs an engine tree; SKIPs without one)

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(c, d)
  if c then passed = passed + 1 else failed = failed + 1
    io.write("  FAIL  ", d, "\n") end
end
local function eq(a, b, d)
  if a ~= b then d = ("%s (got %s, wanted %s)"):format(d, tostring(a), tostring(b)) end
  ok(a == b, d)
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
      local probe = io.open(dir .. "/src/render/MonAnimView.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("dex anim gen2: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

local function slurp(path)
  local h = io.open(path) if not h then return nil end
  local t = h:read("*a") h:close() return t
end

-- ---- the runner, and the summary's use of it, read off the engine

local viewSrc = assert(slurp(ENGINE .. "/src/render/MonAnimView.lua"))
ok(viewSrc:find("function MonAnimView.start(def, mon, scene, imageFn, onCry)",
                1, true) ~= nil,
   "MonAnimView.start takes a species def, a mon, a scene and a loader")
ok(viewSrc:find("local data = MonAnimView.animData(def, mon)", 1, true) ~= nil,
   "and the frames come off def.anim")
ok(viewSrc:find("if not (data and data.tiles and imageFn) then return nil end",
                1, true) ~= nil,
   "so a cache with no anim row gives back nil -- Gold and Silver, untouched")

local sumSrc = assert(slurp(ENGINE .. "/src/ui/gen2/SummaryMenu.lua"))
ok(sumSrc:find('MonAnimView.start(\n    mon and self.pokemon and self.pokemon[mon.species], mon, "menu",',
               1, true) ~= nil,
   "the SUMMARY starts one with the \"menu\" scene")
ok(sumSrc:find("if anim:step() then self.picAnim = nil end", 1, true) ~= nil,
   "steps it once per update and drops it when the scene ends")

local dexSrc = assert(slurp(ENGINE .. "/src/ui/gen2/PokedexMenu.lua"))
ok(dexSrc:find("anim", 1, true) == nil,
   "and the #DEX has no animation code of its own at all")
-- The placement the swap has to respect.
ok(dexSrc:find("local tiles = math.floor(image:getWidth() / 8)", 1, true) ~= nil,
   "drawPic works its padding out from the picture's WIDTH")

local src = assert(slurp("modules/Gen1Dex/gen2anim.lua"))
ok(src:find("size == still:getWidth()", 1, true) ~= nil,
   "so a frame of another size is refused rather than drawn a tile off")
ok(src:find('mod.options:get("dex_anim")', 1, true) ~= nil,
   "and the row is read live")

-- ---- driven against the real class

local drawn = {}
local STILL = { getWidth = function() return 56 end,
                getDimensions = function() return 56, 56 end }
local SHEET = { getWidth = function() return 56 end,
                getDimensions = function() return 56, 392 end }
local QUAD = { quad = true }
love = { graphics = setmetatable({
    draw = function(a) drawn[#drawn + 1] =
      (a == STILL and "STILL") or (a == SHEET and "SHEET") or "?" end,
    rectangle = function() end, setColor = function() end,
    setShader = function() end },
  { __index = function() return function() end end }),
  audio = setmetatable({}, { __index = function() return function() end end }),
  filesystem = setmetatable({}, { __index = function() return function() end end }),
  timer = { getTime = function() return 0 end } }

local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local MonAnimView = require("src.render.MonAnimView")
local steps = 0
MonAnimView.start = function(def)
  if not (def and def.anim) then return nil end
  return { frame = function() return SHEET, QUAD, 56 end,
           step = function() steps = steps + 1; return steps >= 3 end }
end

local Anim = assert(loadfile("modules/Gen1Dex/gen2anim.lua"))()(
  { options = { get = function() return nil end },
    log = { warn = function() end, info = function() end } }, {})
eq(Anim.install(), true, "the arm installs over the cart's class")
eq(Anim.install(), true, "and is idempotent")

local screen = setmetatable({ view = "list", picCache = {}, palettes = {},
  gfx = {}, index = 1,
  rows = { { species = "CHIKORITA", seen = true } },
  pokemon = { CHIKORITA = { name = "CHIKORITA", spriteFront = "f.png",
                            anim = { tiles = 7 } } },
  game = { input = { wasPressed = function() return false end } } }, PokedexMenu)
screen.picFor = function() return STILL end

screen.view = "entry"
screen:update(0.016)
ok(screen.gen1dexAnim ~= nil, "opening the entry starts the animation")

drawn = {}
screen:drawPic(screen.rows[1], 1, 1, true)
eq(drawn[1], "SHEET", "the ENTRY draws the animation frame in the still's place")

drawn = {}
screen:drawPic(screen.rows[1], 1, 1)
eq(drawn[1], "STILL",
   "the LISTING is left alone -- its pic changes on every cursor step, so an "
   .. "animation there never finishes starting")

screen:update(0.016)
screen:update(0.016)
ok(screen.gen1dexAnim == nil, "the runner says when the scene ends")
drawn = {}
screen:drawPic(screen.rows[1], 1, 1, true)
eq(drawn[1], "STILL", "and the entry settles on the base picture")

do -- a cart with no frames is untouched
  local plain = setmetatable({ view = "entry", picCache = {}, palettes = {},
    gfx = {}, index = 1,
    rows = { { species = "PIDGEY", seen = true } },
    pokemon = { PIDGEY = { name = "PIDGEY", spriteFront = "f.png" } },
    game = { input = { wasPressed = function() return false end } } }, PokedexMenu)
  plain.picFor = function() return STILL end
  plain:update(0.016)
  ok(plain.gen1dexAnim == nil, "a species with no anim row starts nothing")
  drawn = {}
  plain:drawPic(plain.rows[1], 1, 1, true)
  eq(drawn[1], "STILL", "and its entry draws the still, exactly as before")
end

io.write(("dex anim gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
