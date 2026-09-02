-- Where the XP bar lands when a voxel mod is running.
--
-- The bar sits under the player's HUD, and a voxel mod of the Dramatic Shape
-- lineage lifts that HUD out of the flat 160x144 frame and composites it into
-- its own window-sized world canvas.  A bar that stays behind is a blue line
-- on a frame the HUD has left; a bar that follows when the HUD did NOT move is
-- 160x144 coordinates on a window-sized canvas, which is worse, and is what
-- the two forks that leave the HUDs alone would have got.
--
-- So there are three answers, not two, and all three are here: draw in the
-- frame, draw on the canvas, draw nothing.  What is checked is the rectangle
-- -- where it is, how big, on which surface, and whether it was marked true
-- colour, which is only ever right in the frame.
--
-- Run:  luajit tests/xpbarvoxel_test.lua

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

-- ------------------------------------------------------------- the harness

-- Every rectangle, with the canvas it went onto, and every true-colour mark.
local drawn, marks, canvas, canvasLog = {}, {}, nil, {}

_G.love = {
  graphics = {
    rectangle = function(mode, x, y, w, h)
      drawn[#drawn + 1] = { mode = mode, x = x, y = y, w = w, h = h,
                            canvas = canvas }
    end,
    setColor = function() end,
    setShader = function() end,
    setCanvas = function(target)
      canvas = target
      canvasLog[#canvasLog + 1] = target
    end,
    getCanvas = function() return canvas end,
    draw = function() end,
    newImage = function() return nil end,
  },
}

local PaletteFX = {
  mode = "gbc",
  GRAYS = { { 0, 0, 0 }, { 85, 85, 85 }, { 170, 170, 170 }, { 255, 255, 255 } },
  markTrueColor = function(x, y, w, h)
    marks[#marks + 1] = { x = x, y = y, w = w, h = h }
  end,
  effectiveColors = function(colors) return colors end,
  permute = function(colors) return colors end,
}
package.preload["src.render.PaletteFX"] = function() return PaletteFX end
package.preload["src.render.Font"] = function()
  return { BORDER = { v = 1, h = 2, bl = 3, br = 4 },
           drawCode = function() end,
           split = function(s) return { s } end }
end
package.preload["src.render.HudTiles"] = function()
  return { tile = function() end, capTile = function() return 0 end }
end
package.preload["src.pokemon.Growth"] = function()
  return { expForLevel = function() return 0 end }
end

-- The player's mon is at the level cap, so the bar is full and its length is
-- a constant rather than a curve: EXP_WIDTH, 67 pixels, seeded on the first
-- frame it is drawn.
local function stubBattle(shot, snapped)
  local battle = {
    isBattle = true,
    frame = 1,
    fx = {},
    player = { mon = { species = 1, level = 100, exp = 0, hp = 20 } },
    data = { pokemon = { { growthRate = 0 } }, constants = { levelCap = 100 },
             growth_rates = {} },
    dramaticShapeShot = shot,
    wideLayout = function() return false end,
    zoneColorsAt = function() return PaletteFX.GRAYS end,
    activeBgp = function() return nil end,
  }
  battle.game = { stack = { top = function() return battle end } }
  if snapped ~= nil then battle.__qolDramaticShapeHudSnapped = snapped end
  return battle
end

local function stubShot()
  return { canvas = "WORLD", scale = 4, pw = 640, ph = 576, lx = 0, ly = 20 }
end

-- The fork's own published geometry -- see tests/voxel_test.lua, which drives
-- the transform itself; this file only needs it to answer.
local function overworldBattle(withGeometry)
  local HUD_RECT = { enemy = { 8, 0, 80, 32 }, player = { 72, 56, 88, 40 } }
  local self = { snapHUDs = function() return true end }
  if withGeometry then
    self.HUD_RECT = HUD_RECT
    self.snapRects = function(shot)
      local s, p = shot.scale, HUD_RECT.player
      local hs = math.max(1, s - 1)
      local px = shot.pw - (p[1] + p[3]) * hs
      return { player = { px + p[1] * hs, shot.ly + p[2] * s,
                          p[3] * hs, p[4] * hs } }
    end
  end
  return self
end

local Voxel = load_("runtime/voxel.lua")

local function stubMod(providerId, modules)
  local mod = {
    find = function(a, b)
      local id = type(a) == "string" and a or b
      if providerId and id == providerId then
        return { id = id, exports = { lib = {
          require = function(name)
            local value = modules[name]
            if value == nil then error("no module", 0) end
            return value
          end,
        } } }
      end
      return nil
    end,
    events = { on = function() end, once = function() end },
  }
  mod.voxel = Voxel.new(mod)
  return mod
end

local makeXP = load_("modules/Gen1BattleUI/xpbar.lua")
local CHROME = { option = function() return true end }

local function draw(mod, battle)
  drawn, marks, canvasLog = {}, {}, {}
  canvas = nil
  local XP = makeXP(mod, CHROME)
  XP.draw(battle)
  return drawn, marks
end

-- The bar itself is the two-pixel-tall rectangle; the burst throws
-- eight-by-eight dots and is not what is being placed here.
local function bar(rects)
  for _, rect in ipairs(rects) do
    if rect.h == 2 or rect.h == 6 then return rect end
  end
  return nil
end

io.write("the XP bar under a voxel mod\n")

-- ------------------------------------------------------- no voxel mod at all

do
  local rects, marked = draw(stubMod(nil, {}), stubBattle(nil))
  local rect = bar(rects)
  ok(rect ~= nil, "with no voxel mod the bar is drawn")
  eq(rect and rect.x, 80, "in the frame, at the classic x")
  eq(rect and rect.y, 89, "and the classic y")
  eq(rect and rect.w, 67, "at its full length")
  eq(rect and rect.canvas, nil, "on the frame, not on any canvas")
  ok(#marked > 0, "and marked true colour, which is a frame-pass thing")
end

-- ------------------- a voxel mod that leaves the HUDs where the engine drew

do
  -- potato_voxel and DRAMALESS_SHAPE: the battle IS a 3D scene -- there is a
  -- shot on it -- and the HUDs are still in the flat frame.  This is the case
  -- that would have put the bar on the far side of a window-sized canvas.
  local mod = stubMod("potato_voxel", { OverworldBattle = { shot = function() end } })
  local rects, marked = draw(mod, stubBattle(stubShot()))
  local rect = bar(rects)
  ok(rect ~= nil, "the bar is still drawn")
  eq(rect and rect.x, 80, "in the frame, unmoved (x)")
  eq(rect and rect.y, 89, "in the frame, unmoved (y)")
  eq(rect and rect.canvas, nil, "and NOT onto the world canvas")
  ok(#marked > 0, "still marked, because it is still in the frame pass")
end

-- ------------------------------------------- the HUDs are on the world canvas

do
  local OverworldBattle = overworldBattle(true)
  local mod = stubMod("BATTLE_ART_VOXEL_FORK",
                      { OverworldBattle = OverworldBattle })
  mod.voxel.installHudSnapHook()
  local battle = stubBattle(stubShot())
  OverworldBattle.snapHUDs(battle)

  local rects, marked = draw(mod, battle)
  local rect = bar(rects)
  ok(rect ~= nil, "the bar is drawn")
  eq(rect and rect.canvas, "WORLD", "onto the voxel mod's world canvas")
  eq(rect and rect.x, 400, "at the HUD's own place on it (x)")
  eq(rect and rect.y, 343, "at the HUD's own place on it (y)")
  eq(rect and rect.w, 201, "its length scaled with the HUD")
  eq(rect and rect.h, 6, "and its thickness too")
  eq(#marked, 0, "nothing marked: that list belongs to the 160x144 pass")
  eq(canvas, nil, "and the canvas is put back when it is done")
end

-- -------------------------------- snapped, but the fork publishes no geometry

do
  local OverworldBattle = overworldBattle(false)
  local mod = stubMod("DRAMATIC_SHAPE", { OverworldBattle = OverworldBattle })
  mod.voxel.installHudSnapHook()
  local battle = stubBattle(stubShot())
  OverworldBattle.snapHUDs(battle)

  local rects = draw(mod, battle)
  eq(bar(rects), nil,
     "the bar stands down rather than guessing where the HUD went")
  eq(#rects, 0, "nothing at all is drawn")
end

-- ------------------------------------------- the answer is per frame, not per mod

do
  local OverworldBattle = overworldBattle(true)
  local mod = stubMod("BATTLE_ART_VOXEL_FORK",
                      { OverworldBattle = OverworldBattle })
  mod.voxel.installHudSnapHook()
  local battle = stubBattle(stubShot())

  local rects = draw(mod, battle)
  eq(bar(rects) and bar(rects).canvas, nil,
     "before the first snap of a battle the bar stays in the frame")

  OverworldBattle.snapHUDs(battle)
  rects = draw(mod, battle)
  eq(bar(rects) and bar(rects).canvas, "WORLD", "after it, it follows")
end

-- ------------------------------------ the paint raises on the world canvas

-- This is the one path in this file that has never run in a real game, and
-- the comment above drawSnappedExpBar makes a promise about it: the canvas
-- goes back even when the paint raises, so a bar that fails on one frame
-- cannot leave the whole battle drawing into the voxel mod's world image.
--
-- The error still travels, on purpose.  Gen1BattleUI's `battle.overlay` wrap
-- pcalls XP.draw and warns (main.lua), so a raise here costs the XP bar and
-- nothing else -- which is the difference between this and 0.32.3, where an
-- unguarded raise in that same hook took the entire battle UI down.
--
-- Both halves are asserted rather than trusted: the error gets out, and the
-- canvas is still put back on the way.
do
  local OverworldBattle = overworldBattle(true)
  local mod = stubMod("BATTLE_ART_VOXEL_FORK",
                      { OverworldBattle = OverworldBattle })
  mod.voxel.installHudSnapHook()
  local battle = stubBattle(stubShot())
  OverworldBattle.snapHUDs(battle)

  local XP = makeXP(mod, CHROME)
  drawn, marks, canvasLog = {}, {}, {}
  canvas = nil

  local sound = love.graphics.rectangle
  love.graphics.rectangle = function() error("the paint failed", 0) end
  local drew, problem = pcall(XP.draw, battle)
  love.graphics.rectangle = sound

  eq(drew, false, "a raising paint is not swallowed")
  eq(problem, "the paint failed", "and the error that gets out is its own")
  eq(canvas, nil, "the world canvas is put back even so")
  eq(canvasLog[1], "WORLD", "having been set to the world canvas first")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
