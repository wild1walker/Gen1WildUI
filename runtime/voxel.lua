-- Which voxel mod is installed, if any, and how much of it we can use.
--
-- A voxel mod redraws the overworld as a 3D diorama and, optionally, draws the
-- battle over the map instead of over white paper.  There is not one of them:
-- the original Dramatic Shape is defunct and three maintained forks have grown
-- out of it, each under an id of its own because only one of them may run at a
-- time.  None of them is required by anything here, and the overwhelmingly
-- common case is that no voxel mod is installed at all -- so every question
-- this file answers has "no" as its cheap, silent, correct default.
--
-- What is shared across every fork is the entry point: the mod publishes
-- `exports.lib`, whose `require(name)` loads one of its internal modules by
-- name.  `OverworldBattle`, `SpriteBillboards` and `Voxel3D` are the three
-- this suite has ever wanted, and all four forks name them the same.  So the
-- id list below is only about FINDING the mod; nothing downstream branches on
-- which one was found.  A fifth fork appearing needs one line here.
--
-- ---- the handshake, and why the default matters
--
-- The one thing the forks genuinely disagree about is where the battle HUDs
-- end up.  The Dramatic Shape lineage lifts them out of the flat 160x144 GB
-- frame and composites them into the world canvas at the battle's own scale
-- and position -- `OverworldBattle.snapHUDs`, which reports whether it managed
-- it this frame (it declines on iOS, and before the first call there is no
-- answer yet).  DRAMALESS_SHAPE and potato_voxel do not do this at all: they
-- override the world behind the frame and leave the HUDs, the text box and the
-- menus exactly where the engine drew them.
--
-- That distinction decides where anything drawn NEXT TO a HUD has to go.  If
-- the HUDs moved into the world canvas, an overlay must move with them or it
-- is left behind on the flat frame, pointing at nothing.  If they did not, an
-- overlay drawn into the world canvas is the same mistake in the other
-- direction -- and that one is louder, because the world canvas is
-- window-sized and the coordinates land nowhere near the HUD.
--
-- So `snappedShot` answers "are the HUDs in the world canvas RIGHT NOW", and
-- it answers no unless something said yes.  A fork with no `snapHUDs` at all
-- never reports snapped, which is exactly right for it -- and is the case the
-- code this replaces got backwards, because it read a missing hook as
-- agreement rather than as silence.
--
-- The two keys below are a contract with the OTHER bundle and with the stable
-- twins, which may be a release behind: whichever half loads first wraps
-- `snapHUDs` once and every half reads the result off the battle.  They keep
-- their original names for that reason and must not be renamed for tidiness.

local Voxel = {}

-- Every voxel mod this suite knows how to stand beside, best-maintained
-- first.  Only one can be installed at a time -- they declare each other as
-- conflicts -- so the order is about which name to try first, not priority.
--
--   BATTLE_ART_VOXEL_FORK  absol89/DramaticShapeVoxelMod, the maintained
--                          descendant; the only one that snaps the HUDs
--   DRAMALESS_SHAPE        artyrambles/DRAMALESS_SHAPE
--   potato_voxel           ShaneMcGovernIE/potato_voxel, tuned for low-end
--                          devices
--   DRAMATIC_SHAPE         TeJota1337's original, now defunct but still
--   dramatic_shape_brick   installed; the last two are its variants, named
--   ds_fp_ceiling          in every fork's own conflicts list
Voxel.PROVIDER_IDS = {
  "BATTLE_ART_VOXEL_FORK",
  "DRAMALESS_SHAPE",
  "potato_voxel",
  "DRAMATIC_SHAPE",
  "dramatic_shape_brick",
  "ds_fp_ceiling",
}

-- Set on the battle: false once snapHUDs has been asked this frame and said
-- no, true once it has said yes.  Absent means nobody is asking.
Voxel.SNAP_STATE = "__qolDramaticShapeHudSnapped"
-- Set on the provider's own OverworldBattle table: this wrap is already in
-- place, so the other bundle must not add a second one.
Voxel.SNAP_HOOK = "__qolHudSnapHook"

-- The battle-side shot: the world canvas the 3D pass drew into, and where the
-- GB frame lands on it.  Validated in full because it is another mod's table
-- and a half-built one must read as "no shot" rather than as arithmetic on
-- nil.
local function validShot(shot)
  return type(shot) == "table"
    and shot.canvas
    and type(shot.scale) == "number" and shot.scale > 0
    and type(shot.pw) == "number"
    and type(shot.ph) == "number"
    and type(shot.lx) == "number"
    and type(shot.ly) == "number"
end

-- `mod.find` is called three ways across the index -- `find(name)`,
-- `find(mod, name)`, and through a facade that takes either -- and a mod that
-- is not installed is the ordinary case, not an error.
local function findHandle(mod, id)
  if type(mod.find) ~= "function" then return nil end
  local ok, handle = pcall(mod.find, id)
  if ok and handle then return handle end
  local okSelf, handleSelf = pcall(mod.find, mod, id)
  if okSelf and handleSelf then return handleSelf end
  return nil
end

-- `ids` is for tests; everything else takes the list above.
function Voxel.new(mod, ids)
  local self = {}
  local providerIds = ids or Voxel.PROVIDER_IDS
  local foundId, foundLib = nil, nil
  -- A miss is only worth remembering once every mod has had a chance to
  -- load.  Before that, a voxel mod that simply has not been reached yet
  -- would be cached as absent for the rest of the session.
  local settled = false

  if mod and mod.events and type(mod.events.once) == "function" then
    pcall(mod.events.once, mod.events, "mods.loaded", function()
      settled = true
    end)
  end

  -- The resolved provider's id and lib, or nil twice.  Silent either way.
  function self.provider()
    if foundLib then return foundId, foundLib end
    for _, id in ipairs(providerIds) do
      local handle = findHandle(mod, id)
      local lib = handle and handle.exports and handle.exports.lib
      if type(lib) == "table" and type(lib.require) == "function" then
        foundId, foundLib = id, lib
        return foundId, foundLib
      end
    end
    if settled then
      -- Nothing is installed and nothing more is going to be: stop asking.
      providerIds = {}
    end
    return nil, nil
  end

  -- The id of the voxel mod in play, for a log line or a bench row.
  function self.id()
    local id = self.provider()
    return id
  end

  -- One of the provider's internal modules, or nil.  Never raises: these are
  -- another mod's chunks and a fork is free to have dropped one.
  function self.require(name)
    local _, lib = self.provider()
    if not lib then return nil end
    local ok, value = pcall(lib.require, name)
    if ok then return value end
    return nil
  end

  -- Whether the provider in play moves the HUDs into the world canvas at all.
  -- False for a fork that leaves them in the GB frame, and false with no
  -- provider.
  function self.snapsHuds()
    local OverworldBattle = self.require("OverworldBattle")
    return type(OverworldBattle) == "table"
      and type(OverworldBattle.snapHUDs) == "function"
  end

  -- Wrap `snapHUDs` so its answer is readable off the battle.  Returns
  -- "hooked" when this call installed it, "already" when the other bundle got
  -- there first, and false when there is nothing to hook -- which covers both
  -- "no voxel mod" and "this fork does not snap", deliberately without
  -- distinguishing them to the caller: the drawing rule is the same for both.
  function self.installHudSnapHook()
    local OverworldBattle = self.require("OverworldBattle")
    if type(OverworldBattle) ~= "table"
       or type(OverworldBattle.snapHUDs) ~= "function" then
      return false
    end
    if rawget(OverworldBattle, Voxel.SNAP_HOOK) then return "already" end
    local snapHUDs = OverworldBattle.snapHUDs
    OverworldBattle.snapHUDs = function(battle, ...)
      -- Cleared before the call, not after: snapHUDs can fail part way and
      -- return nothing, and a stale `true` from the previous frame would
      -- leave an overlay drawing into a canvas the HUDs are no longer on.
      if battle then battle[Voxel.SNAP_STATE] = false end
      local snapped = snapHUDs(battle, ...)
      if battle then battle[Voxel.SNAP_STATE] = snapped == true end
      return snapped
    end
    OverworldBattle[Voxel.SNAP_HOOK] = true
    return "hooked"
  end

  -- The validated shot on this battle, whoever put it there.  Present under
  -- every fork that draws the battle in 3D, including the ones that leave the
  -- HUDs alone -- so this is the right question for "is the battle a 3D
  -- scene" and the WRONG one for "where do I draw".
  function self.shot(battle)
    if type(battle) ~= "table" then return nil end
    local shot = rawget(battle, "dramaticShapeShot")
    if not validShot(shot) then return nil end
    return shot
  end

  -- The shot, but only while the HUDs are genuinely on it.  This is the
  -- question anything drawn beside a HUD must ask.  nil means "draw where you
  -- always drew", which is correct with no voxel mod, with a fork that does
  -- not snap, on a platform where snapping declined, and on the frames before
  -- the first snap of a battle.
  function self.snappedShot(battle)
    local shot = self.shot(battle)
    if not shot then return nil end
    if rawget(battle, Voxel.SNAP_STATE) ~= true then return nil end
    return shot
  end

  -- Where a point in the flat GB frame lands on the world canvas, once the
  -- HUDs have been snapped onto it -- for an overlay that has to follow a HUD
  -- there.
  --
  -- Derived from the provider's OWN published numbers rather than from a copy
  -- of its arithmetic: `HUD_RECT[side]` is the block as the engine draws it in
  -- GB pixels, `snapRects(shot)[side]` is where that same block was put on the
  -- canvas.  One is the other transformed, so the two together ARE the
  -- transform, and it keeps holding when the fork retunes its own layout --
  -- which it does: HUD SCALE alone gives the HUD a scale the rest of the
  -- battle does not share.
  --
  -- Returns a mapping function and that scale, or nil if this fork does not
  -- publish both halves.
  function self.hudTransform(shot, side)
    local OverworldBattle = self.require("OverworldBattle")
    if type(OverworldBattle) ~= "table"
       or type(OverworldBattle.snapRects) ~= "function"
       or type(OverworldBattle.HUD_RECT) ~= "table" then
      return nil
    end
    local gb = OverworldBattle.HUD_RECT[side]
    if type(gb) ~= "table" or type(gb[1]) ~= "number"
       or type(gb[2]) ~= "number" or type(gb[3]) ~= "number"
       or gb[3] == 0 then
      return nil
    end
    local ok, rects = pcall(OverworldBattle.snapRects, shot)
    local rect = ok and type(rects) == "table" and rects[side]
    if type(rect) ~= "table" or type(rect[1]) ~= "number"
       or type(rect[2]) ~= "number" or type(rect[3]) ~= "number" then
      return nil
    end
    local scale = rect[3] / gb[3]
    if not (scale > 0) then return nil end
    local originX, originY, gbX, gbY = rect[1], rect[2], gb[1], gb[2]
    return function(x, y)
      return originX + (x - gbX) * scale, originY + (y - gbY) * scale
    end, scale
  end

  return self
end

return Voxel
