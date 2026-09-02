-- Standing beside a voxel mod, and standing beside none.
--
-- A voxel mod is optional here in the strongest sense: almost nobody has one,
-- so the answer this file cares most about is the silent no.  What it drives
-- is runtime/voxel.lua, which is pure Lua and takes its `mod` object as an
-- argument, so every case below is a stub mod and a plain call -- no engine,
-- no love, no battle.
--
-- The case that matters most is the one this file was written for.  There are
-- four voxel forks and only the Dramatic Shape lineage lifts the battle HUDs
-- onto its world canvas; DRAMALESS_SHAPE and potato_voxel leave them in the
-- flat GB frame.  Code that read "this fork has no snapHUDs" as agreement
-- rather than as silence drew the overlays onto a window-sized canvas at
-- 160x144 coordinates, which is nowhere near the HUD.  So: a provider with no
-- handshake never reports snapped, and neither does one that has not been
-- asked yet.
--
-- Run:  luajit tests/voxel_test.lua

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

local Voxel = load_("runtime/voxel.lua")

-- ------------------------------------------------------------- the harness

-- A stub engine `mod`.  `installed` maps a mod id to the handle its find
-- answers with; everything else is not installed.  `finds` counts the sweeps,
-- which is how memoisation is checked.
local function stubMod(installed)
  local self = { finds = 0, loadedCallbacks = {} }
  self.find = function(a, b)
    local id = type(a) == "string" and a or b
    self.finds = self.finds + 1
    return installed and installed[id] or nil
  end
  self.events = {
    once = function(_, name, callback)
      if name == "mods.loaded" then
        self.loadedCallbacks[#self.loadedCallbacks + 1] = callback
      end
    end,
  }
  self.fireModsLoaded = function()
    for _, callback in ipairs(self.loadedCallbacks) do callback() end
  end
  return self
end

-- A voxel mod, shaped the way all four forks are shaped: a handle carrying
-- `exports.lib`, whose `require(name)` hands back one of its internal modules.
local function stubProvider(modules)
  return {
    id = "stub",
    exports = {
      lib = {
        require = function(name)
          local value = modules[name]
          if value == nil then error("no module " .. tostring(name), 0) end
          return value
        end,
      },
    },
  }
end

-- The battle-side shot: a world canvas and where the GB frame lands on it.
-- `NONE` rather than nil for a field being taken AWAY: a nil in the overrides
-- table is a key `pairs` never visits, so it would silently leave the default
-- in place and the case would pass without testing anything.
local NONE = {}
local function stubShot(overrides)
  local shot = { canvas = {}, scale = 4, pw = 640, ph = 576, lx = 0, ly = 20 }
  for key, value in pairs(overrides or {}) do
    if value == NONE then value = nil end
    shot[key] = value
  end
  return shot
end

io.write("voxel provider\n")

-- --------------------------------------------------------- nothing installed

do
  local mod = stubMod(nil)
  local voxel = Voxel.new(mod)
  eq(voxel.id(), nil, "no voxel mod installed: no provider")
  eq(voxel.require("OverworldBattle"), nil, "and no module to require")
  eq(voxel.snapsHuds(), false, "and nothing snaps the HUDs")
  eq(voxel.installHudSnapHook(), false, "and there is no hook to install")
  eq(voxel.snappedShot({ dramaticShapeShot = stubShot() }), nil,
     "and a battle carrying a shot from nowhere is still not snapped")
end

-- ------------------------------------------------ every fork is found by id

do
  ok(#Voxel.PROVIDER_IDS >= 6, "the id list covers the whole family")
  for _, id in ipairs(Voxel.PROVIDER_IDS) do
    local provider = stubProvider({ Voxel3D = "voxel3d" })
    local voxel = Voxel.new(stubMod({ [id] = provider }))
    eq(voxel.id(), id, id .. " is found")
    eq(voxel.require("Voxel3D"), "voxel3d", id .. " answers require")
  end
end

do
  -- `mod.find` is called both ways across the index; a mod that only answers
  -- the receiver form must still be found.
  local provider = stubProvider({ Voxel3D = "voxel3d" })
  local mod = stubMod(nil)
  mod.find = function(a, b)
    if type(a) == "string" then error("this one wants a receiver", 0) end
    return b == "potato_voxel" and provider or nil
  end
  eq(Voxel.new(mod).id(), "potato_voxel", "find(mod, name) is tried as well")
end

do
  local mod = stubMod({ potato_voxel = { id = "x", exports = {} } })
  eq(Voxel.new(mod).id(), nil, "a handle with no exports.lib is not a provider")

  mod = stubMod({ potato_voxel = { id = "x", exports = { lib = {} } } })
  eq(Voxel.new(mod).id(), nil, "and neither is a lib with no require")
end

do
  local voxel = Voxel.new(stubMod({ potato_voxel = stubProvider({}) }))
  eq(voxel.require("NotThere"), nil,
     "a module the fork does not carry is nil, not a raise")
end

-- -------------------------------------------------------------- memoisation

do
  local mod = stubMod({ DRAMALESS_SHAPE = stubProvider({ A = 1 }) })
  local voxel = Voxel.new(mod)
  voxel.id(); voxel.id(); voxel.require("A")
  -- Two ids tried before the hit, and a miss costs two calls rather than one:
  -- `find(name)` and `find(mod, name)` are both real call shapes in the index
  -- and a mod that is not installed answers neither.  Three in total, then the
  -- provider is remembered and no further asking happens.
  eq(mod.finds, 3, "a hit is swept for once and then remembered")
end

do
  -- A miss before mods.loaded is not remembered: the voxel mod may simply not
  -- have been reached yet.  After it, asking again is pointless and stops.
  local installed = {}
  local mod = stubMod(installed)
  local voxel = Voxel.new(mod)
  eq(voxel.id(), nil, "nothing installed yet")
  installed.potato_voxel = stubProvider({ A = 1 })
  eq(voxel.id(), "potato_voxel", "a mod that loads later is still found")

  installed = {}
  mod = stubMod(installed)
  voxel = Voxel.new(mod)
  voxel.id()
  mod.fireModsLoaded()
  voxel.id()
  local sweeps = mod.finds
  voxel.id(); voxel.id()
  eq(mod.finds, sweeps, "once every mod has loaded, a miss stops being asked")
end

-- ------------------------------------------------------- the shot, validated

io.write("the shot\n")

do
  local voxel = Voxel.new(stubMod(nil))
  ok(voxel.shot({ dramaticShapeShot = stubShot() }) ~= nil,
     "a complete shot is a shot")
  eq(voxel.shot({}), nil, "a battle with no shot has none")
  eq(voxel.shot("not a battle"), nil, "and neither has a non-battle")
  eq(voxel.shot({ dramaticShapeShot = stubShot({ canvas = NONE }) }), nil,
     "a shot with no canvas is not one")
  eq(voxel.shot({ dramaticShapeShot = stubShot({ scale = 0 }) }), nil,
     "nor one at zero scale")
  eq(voxel.shot({ dramaticShapeShot = stubShot({ ly = "twenty" }) }), nil,
     "nor one whose geometry is not numbers")
end

-- ------------------------------------------------------------ the handshake

io.write("the HUD handshake\n")

do
  -- potato_voxel and DRAMALESS_SHAPE: the battle is a 3D scene, the HUDs are
  -- not on it.  This is the case the code this replaces got backwards.
  local voxel = Voxel.new(stubMod({
    potato_voxel = stubProvider({ OverworldBattle = { shot = function() end } }),
  }))
  local battle = { dramaticShapeShot = stubShot() }
  eq(voxel.snapsHuds(), false, "a fork with no snapHUDs does not snap them")
  eq(voxel.installHudSnapHook(), false, "so there is no hook to install")
  ok(voxel.shot(battle) ~= nil, "the battle still has a shot")
  eq(voxel.snappedShot(battle), nil,
     "but it is NOT snapped -- the overlay draws in the GB frame")
end

do
  local snapped = true
  local calls = 0
  local OverworldBattle = {
    snapHUDs = function() calls = calls + 1; return snapped end,
  }
  local voxel = Voxel.new(stubMod({
    BATTLE_ART_VOXEL_FORK = stubProvider({ OverworldBattle = OverworldBattle }),
  }))
  local battle = { dramaticShapeShot = stubShot() }

  eq(voxel.snapsHuds(), true, "the Dramatic Shape lineage does snap them")
  eq(voxel.snappedShot(battle), nil,
     "before the first snap of a battle there is no answer, so: not snapped")

  eq(voxel.installHudSnapHook(), "hooked", "the wrap goes on")
  eq(voxel.installHudSnapHook(), "already",
     "and the other bundle finds it there rather than adding a second")

  OverworldBattle.snapHUDs(battle)
  eq(calls, 1, "the fork's own snapHUDs still runs")
  ok(voxel.snappedShot(battle) ~= nil, "snapped: the overlay follows the HUD")

  snapped = false
  OverworldBattle.snapHUDs(battle)
  eq(voxel.snappedShot(battle), nil,
     "declined this frame (iOS does): back to the GB frame")

  snapped = true
  OverworldBattle.snapHUDs(battle)
  battle.dramaticShapeShot = nil
  eq(voxel.snappedShot(battle), nil,
     "and a battle that loses its shot is not snapped whatever was recorded")
end

do
  -- A fork whose snapHUDs raises must not take the battle down with it, and
  -- must not leave a stale yes behind either.
  local OverworldBattle = { snapHUDs = function() error("boom", 0) end }
  local voxel = Voxel.new(stubMod({
    DRAMATIC_SHAPE = stubProvider({ OverworldBattle = OverworldBattle }),
  }))
  local battle = { dramaticShapeShot = stubShot() }
  voxel.installHudSnapHook()
  local raised = not pcall(OverworldBattle.snapHUDs, battle)
  ok(raised, "the raise still travels to whoever called it")
  eq(voxel.snappedShot(battle), nil, "and the battle is left not snapped")
end

-- ------------------------------------------------------------ the transform

io.write("the HUD transform\n")

-- The fork's own published geometry, quoted: HUD_RECT is the player's block
-- in GB pixels as the engine draws it, snapRects is where that block was put
-- on the world canvas.  The numbers below are absol89's arithmetic for a shot
-- at scale 4 -- hs = scale - 1 = 3, px = pw - (72 + 88) * hs = 160 -- so a
-- transform read out of the two lands on them.
local function fork(hudScale)
  local HUD_RECT = { enemy = { 8, 0, 80, 32 }, player = { 72, 56, 88, 40 } }
  return {
    HUD_RECT = HUD_RECT,
    snapHUDs = function() return true end,
    snapRects = function(shot)
      local s = shot.scale
      local hs = hudScale or math.max(1, s - 1)
      local p = HUD_RECT.player
      local e = HUD_RECT.enemy
      local px = shot.pw - (p[1] + p[3]) * hs
      return {
        enemy = { (2 - e[1]) * hs + e[1] * hs, shot.ly + e[2] * s,
                  e[3] * hs, e[4] * hs },
        player = { px + p[1] * hs, shot.ly + p[2] * s, p[3] * hs, p[4] * hs },
      }
    end,
  }
end

do
  local voxel = Voxel.new(stubMod({
    BATTLE_ART_VOXEL_FORK = stubProvider({ OverworldBattle = fork() }),
  }))
  local shot = stubShot()
  local toWorld, scale = voxel.hudTransform(shot, "player")
  ok(toWorld ~= nil, "the transform is available")
  eq(scale, 3, "at the HUD's own scale, which is not the battle's")

  local x, y = toWorld(72, 56)
  eq(x, 376, "the HUD's own corner lands on the rect's corner (x)")
  eq(y, 244, "the HUD's own corner lands on the rect's corner (y)")

  -- Where the XP bar's left end sits: GB (80, 89), eight pixels in and
  -- thirty-three down from the block's corner.
  x, y = toWorld(80, 89)
  eq(x, 400, "the bar's left end follows the HUD (x)")
  eq(y, 343, "the bar's left end follows the HUD (y)")
end

do
  -- HUD SCALE = OG pins the HUD to the window fit rather than the battle
  -- zoom.  Nothing here knows that setting exists; it reads the rect.
  local voxel = Voxel.new(stubMod({
    BATTLE_ART_VOXEL_FORK = stubProvider({ OverworldBattle = fork(4) }),
  }))
  local toWorld, scale = voxel.hudTransform(stubShot(), "player")
  eq(scale, 4, "a fork that retunes its HUD scale is followed, not guessed")
  local x = toWorld(80, 56)
  eq(x, 288 + 32, "and the mapping moves with it")
end

do
  local voxel = Voxel.new(stubMod({
    potato_voxel = stubProvider({ OverworldBattle = { snapHUDs = function() end } }),
  }))
  eq(voxel.hudTransform(stubShot(), "player"), nil,
     "a fork that snaps but publishes no geometry gets no transform")
  eq(Voxel.new(stubMod(nil)).hudTransform(stubShot(), "player"), nil,
     "and neither does no voxel mod at all")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
