-- What a pinned row can be.
--
-- Every entry here maps to a call on the SUPPORTED surface: mod.world
-- (src/world/WorldAPI.lua) for the field actions, mod.ui.push for the TOWN
-- MAP screen.  Nothing reaches into BagMenu, whose use-flow (useItem, useOn,
-- pickTargetAndUse) is file-local and exported nowhere, and nothing requires
-- an engine module -- so the mod needs no "engine_internals" permission and
-- the manager never shows the player a PATCHES ENGINE CODE badge.
--
-- The cost of that discipline: ITEMFINDER and the POKe FLUTE are not here.
-- Their behavior lives inside ItemEffects' result dispatch with no seam
-- around it, and reimplementing it would mean duplicating engine logic that
-- can drift.  They stay in the bag.
--
-- OWNERSHIP vs READINESS.  `owned` decides whether a row exists and is
-- answered from save state alone.  It deliberately does NOT call
-- world:availableFieldActions(), because that gates on
-- stack:top() == overworld: true when START is pressed from the field, false
-- when a submenu's onCancel re-opens the menu (StartMenu's `reopen`).  Using
-- it for visibility would make pinned rows vanish on the way back from the
-- bag.  Readiness is left to useFieldAction, which does its own gating at the
-- moment of use -- and by then Menu has already popped itself, so the world
-- is on top again.
--
-- LABELS.  `label` names the thing the pin comes from -- the item or the
-- move -- and is what the editor lists the pin under.  An entry may also
-- carry `menuLabel` for the row the player sees on the menu itself, for the
-- one case where the row does something the item name does not describe.
-- main.lua reaches for menuLabel only while the SHORT NAMES option is on, so
-- a player who wants the game's own names can have them back.  Both take
-- (mod, game) and both go through pcall at their call sites, so a label that
-- errors costs the row its name, not the menu.

local M = {}

-- data.field.hmBadges, with src/world/FieldDefaults.lua's literal as the
-- fallback for a cache imported before the constant existed.
local HM_BADGES = {
  CUT = "CASCADEBADGE", SURF = "SOULBADGE", STRENGTH = "RAINBOWBADGE",
  FLY = "THUNDERBADGE", FLASH = "BOULDERBADGE",
}

local function badgeFor(game, moveId)
  local field = game and game.data and game.data.field
  local entry = field and field.hmBadges and field.hmBadges[moveId]
  if type(entry) == "table" and entry.badge then return entry.badge end
  return HM_BADGES[moveId]
end

local function hasItem(game, id)
  local inventory = game and game.save and game.save.inventory
  return (inventory and (inventory[id] or 0) > 0) or false
end

local function hasBadge(game, badgeId)
  if not badgeId then return true end
  local inventory = game and game.save and game.save.inventory
  return (inventory and inventory[badgeId] ~= nil) or false
end

local function partyKnows(game, moveId)
  local party = game and game.save and game.save.party or {}
  for _, mon in ipairs(party) do
    for _, move in ipairs(mon.moves or {}) do
      if move.id == moveId then return true end
    end
  end
  return false
end

local function itemName(mod, game, id)
  local def = (game and game.data and game.data.items and game.data.items[id])
    or mod.content.items:get(id)
  return (def and def.name) or id:gsub("_", " ")
end

local function moveName(mod, game, id)
  local def = (game and game.data and game.data.moves and game.data.moves[id])
    or mod.content.moves:get(id)
  return (def and def.name) or id:gsub("_", " ")
end

-- A move-driven field action: owned once some party member knows it and the
-- badge (if any) is in the bag.
local function fieldMove(id, moveId, action)
  return {
    id = id,
    -- the WorldAPI action id, so main.lua can cross-check readiness against
    -- availableFieldActions without re-deriving the mapping
    action = action,
    label = function(mod, game) return moveName(mod, game, moveId) end,
    owned = function(game)
      return partyKnows(game, moveId) and hasBadge(game, badgeFor(game, moveId))
    end,
    run = function(mod, game)
      local world = mod.world
      if not world then return nil, "no world" end
      return world:useFieldAction(action)
    end,
  }
end

local function rod(id, itemId)
  return {
    id = id,
    action = "fish",
    label = function(mod, game) return itemName(mod, game, itemId) end,
    owned = function(game) return hasItem(game, itemId) end,
    run = function(mod, game)
      local world = mod.world
      if not world then return nil, "no world" end
      return world:useFieldAction("fish", { rod = itemId })
    end,
  }
end

M.catalog = {
  -- The row this whole mod started as: TOWN MAP without the bag detour.
  -- Screens.push("TownMap") is exactly what BagMenu does on the "townmap"
  -- result, and TownMap.new reads its own data, so there is nothing to pass.
  --
  -- The only entry with a menuLabel: the live row opens the map screen
  -- rather than handing you the item, and "MAP" says that in a menu whose
  -- rows are one word apiece.  The editor keeps the item name, which is what
  -- a player scanning the pin list recognises from the bag -- and SHORT NAMES
  -- off puts the item name on the menu row too.
  {
    id = "townmap",
    label = function(mod, game) return itemName(mod, game, "TOWN_MAP") end,
    menuLabel = function() return "MAP" end,
    owned = function(game) return hasItem(game, "TOWN_MAP") end,
    run = function(mod, game)
      mod.ui.push(game, "TownMap")
      return true
    end,
  },
  {
    id = "bicycle",
    action = "bicycle",
    label = function(mod, game) return itemName(mod, game, "BICYCLE") end,
    owned = function(game) return hasItem(game, "BICYCLE") end,
    run = function(mod, game)
      local world = mod.world
      if not world then return nil, "no world" end
      return world:useFieldAction("bicycle")
    end,
  },
  -- FLY needs a destination, so WorldAPI exposes it separately from the
  -- immediate actions.  TownMap's fly mode pops itself BEFORE calling onFly
  -- (src/ui/TownMap.lua), which is what lets flyTo pass its own
  -- acceptsMenuInput check -- the world is back on top by then.
  {
    id = "fly",
    label = function(mod, game) return moveName(mod, game, "FLY") end,
    owned = function(game)
      return partyKnows(game, "FLY") and hasBadge(game, badgeFor(game, "FLY"))
    end,
    run = function(mod, game)
      local world = mod.world
      if not world then return nil, "no world" end
      if not world:canFly() then return nil, "fly unavailable" end
      mod.ui.push(game, "TownMap", { fly = true, onFly = function(mapId)
        world:flyTo(mapId)
      end })
      return true
    end,
  },
  rod("old_rod", "OLD_ROD"),
  rod("good_rod", "GOOD_ROD"),
  rod("super_rod", "SUPER_ROD"),
  fieldMove("cut", "CUT", "cut"),
  fieldMove("surf", "SURF", "surf"),
  fieldMove("strength", "STRENGTH", "strength"),
  fieldMove("flash", "FLASH", "flash"),
  -- DIG and TELEPORT are TM moves, not HMs: no badge gate.
  fieldMove("dig", "DIG", "dig"),
  fieldMove("teleport", "TELEPORT", "teleport"),
}

function M.byId(id)
  for _, entry in ipairs(M.catalog) do
    if entry.id == id then return entry end
  end
  return nil
end

return M
