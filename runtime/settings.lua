-- The settings a sealed cart would otherwise eat.
--
-- ------- the problem
--
-- A sealed cart's per-mod options are not the player's.  Loader:_applyCart
-- rebuilds `loader.modOptions` on every boot out of what the CART pins, and
-- throws the stored values away:
--
--     for id, pin in pairs(report.pins) do
--       local bucket = {}
--       for key, value in pairs(pin.options or {}) do bucket[key] = value end
--       if not report.enforced then
--         for key, value in pairs(self.modOptions[id] or {}) do ... end
--       end
--       merged[id] = bucket
--     end
--
-- `enforced` is true for any seal that is not "open", so `sealed` and
-- `sealed+` both do it.  On this cart that means every setting in the suite
-- resets on the next launch, and one of them -- WILD GREEN's PLAYER -- could
-- never take effect at all: the walker is a record read at load, and the load
-- is exactly when the choice was being discarded.
--
-- ------- why not simply unseal
--
-- Online play requires the seal, and requires it to be exactly "sealed":
-- ArenaData.profile refuses any other value and OnlinePanel lists no other
-- kind.  "open" would keep the settings and lose the arena.
--
-- ------- what this does instead
--
-- Remembers what the player chose, in this bundle's own cache -- which is
-- installation-wide and which the merge does not touch -- and puts it back
-- into `loader.modOptions` at load, before anything reads it.
--
-- Into the SAME table the engine's mod manager reads, which is what keeps
-- this from being a second source of truth: the manager, this suite's own
-- menu and the mods themselves all see one value, and it is the player's.
--
-- Nothing here changes the cart FILE, and the cart file is what online
-- matches on -- ArenaData.profile keys its fingerprint on CartStore's hash of
-- the manifest, never on the live option values.  So the seal keeps every
-- guarantee the arena asks of it.
--
-- The cart's own pins become defaults rather than locks: a pinned value is
-- what a player gets until they choose otherwise, and after that their choice
-- is what they get.  That is the trade this file IS, and it is why it is
-- limited to what the suite ships -- a cart that wants a value fixed for
-- everyone should pin it and not ship this.
--
-- ------- ordering
--
-- gen1_wild_qol is first in the cart's load_order and WILD GREEN is last, so
-- a restore done as this bundle installs lands before the mod whose option is
-- read at load time gets to read it.

local Settings = {}

local FILE = "settings.txt"

-- One line per remembered value: mod, key, type, value.  Tab-separated
-- because a key is an identifier and a value is a boolean, a number or a
-- short choice string -- none of which carry tabs -- and because the file is
-- meant to be readable by whoever finds it.
local function encode(store)
  local mods = {}
  for modId in pairs(store) do mods[#mods + 1] = modId end
  table.sort(mods)
  local out = {}
  for _, modId in ipairs(mods) do
    local keys = {}
    for key in pairs(store[modId]) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local value = store[modId][key]
      local kind = type(value)
      if kind == "boolean" or kind == "number" or kind == "string" then
        out[#out + 1] = table.concat({ modId, key, kind, tostring(value) }, "\t")
      end
    end
  end
  return table.concat(out, "\n")
end

local function decode(bytes)
  local store = {}
  if type(bytes) ~= "string" then return store end
  for line in bytes:gmatch("[^\n]+") do
    local modId, key, kind, raw = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$")
    if modId and key then
      local value
      if kind == "boolean" then value = raw == "true"
      elseif kind == "number" then value = tonumber(raw)
      elseif kind == "string" then value = raw end
      if value ~= nil then
        store[modId] = store[modId] or {}
        store[modId][key] = value
      end
    end
  end
  return store
end

function Settings.read(mod)
  local ok, bytes = pcall(function() return mod.cache:read(FILE) end)
  if not ok then return {} end
  return decode(bytes)
end

function Settings.write(mod, store)
  -- A read-only cache directory costs the memory of the choice, not the
  -- choice: the value is already live in loader.modOptions either way.
  local ok, err = pcall(function()
    return mod.cache:write(FILE, encode(store))
  end)
  if not ok and mod.log and type(mod.log.warn) == "function" then
    mod.log:warn("settings not remembered: %s", tostring(err))
  end
  return ok
end

-- The live loader, which is where an option value actually lives.
local function loaderOf(mod)
  local world = mod.world
  local game = type(world) == "table" and world.game or nil
  local loader = type(game) == "table" and game.mods or nil
  if type(loader) ~= "table" then return nil end
  return loader
end

-- Put every remembered value back.  Returns how many were restored, for the
-- suite and for the boot feed.
function Settings.restore(mod, store)
  store = store or Settings.read(mod)
  local loader = loaderOf(mod)
  if not loader then return 0 end
  loader.modOptions = loader.modOptions or {}
  local restored = 0
  for modId, bucket in pairs(store) do
    for key, value in pairs(bucket) do
      loader.modOptions[modId] = loader.modOptions[modId] or {}
      loader.modOptions[modId][key] = value
      restored = restored + 1
    end
  end
  return restored
end

-- Record every option change anyone makes, whichever screen made it: the
-- engine's mod manager, this suite's own menu, or a mod writing its own row.
-- They all end in the same event.
function Settings.watch(mod)
  if type(mod.events) ~= "table" or type(mod.events.on) ~= "function" then
    return false
  end
  local store = Settings.read(mod)
  mod.events:on("mod.options_changed", function(ev)
    if type(ev) ~= "table" then return end
    local modId = ev.mod
    -- `mod` on this event is the mod's id from the manager and the mod table
    -- itself from a facade that emitted it; both are accepted, because a
    -- setting remembered under the wrong name is a setting forgotten.
    if type(modId) == "table" then modId = modId.id end
    local key = ev.key
    if type(modId) ~= "string" or type(key) ~= "string" then return end
    local value = ev.value
    local kind = type(value)
    if kind ~= "boolean" and kind ~= "number" and kind ~= "string" then return end
    store[modId] = store[modId] or {}
    if store[modId][key] == value then return end
    store[modId][key] = value
    Settings.write(mod, store)
  end)
  return true
end

return Settings
