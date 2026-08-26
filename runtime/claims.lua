-- Which bundle installs a feature that is in both of them.
--
-- Gen1ModMenu and Gen1MenuManager are not really "visual" or "quality of
-- life" -- they are the furniture every other feature is seen through. A
-- player who installs only Gen1WildQOL should not lose the mod manager
-- redraw, and one who installs only Gen1WildUI should not lose it either. So
-- both bundles carry them.
--
-- Which means both bundles would install them, twice, and neither mod guards
-- against that: Gen1ModMenu would wrap the manager screen around its own
-- wrapper, and Gen1MenuManager would apply its row order to an order it had
-- already applied. This is the thing that stops it.
--
-- The mechanism is a claim table parked on an engine module. Requiring the
-- same module from two different mods returns the same table -- that is how
-- `require` works, and this engine's mods already rely on it: unxpected-uxp's
-- Quality of Life patches `ManagerState.openOptions` and leaves a marker on
-- ManagerState so a second mod doing the same thing can see it. This is the
-- same trick, used for the same reason.
--
-- First bundle to load claims the feature and installs it. The second sees
-- the claim and stands down. Which one wins does not matter and is not worth
-- forcing: both carry the same feature pinned at the same version, and the
-- feature's settings are stored under a bundle-independent id (see
-- `shared.storage` in features.lua) so they do not move when the winner does.

local Claims = {}

-- Engine modules stable enough to park a field on, most-appropriate first.
-- ManagerState is the natural home -- it is the mod manager, which is what
-- most of this is about -- but any module both bundles can require will do,
-- because all that is needed is one table they agree on.
local HOSTS = {
  "src.mods.ManagerState",
  "src.ui.Screens",
  "src.core.GameVersion",
}

local FIELD = "__gen1WildSharedClaims"

-- Returns the shared table and the module it lives on, or nil if no module
-- could be found to hold it.
function Claims.table()
  for _, name in ipairs(HOSTS) do
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then
      local existing = rawget(module, FIELD)
      if type(existing) == "table" then return existing, name end
      local created = {}
      local assigned = pcall(function() module[FIELD] = created end)
      if assigned and rawget(module, FIELD) == created then
        return created, name
      end
    end
  end
  return nil, nil
end

-- Decide whether this bundle should install a shared feature.
--
-- Returns true to install, or false plus the id of the bundle that got there
-- first. The claim is taken as a side effect of saying yes, which is what
-- makes this safe without a lock: mods load one after another on one thread,
-- so there is no window between looking and claiming.
function Claims.take(mod, feature, claims)
  local key = (feature.shared and feature.shared.claim) or feature.id

  if not claims then
    -- No module would hold the table, so the two bundles cannot talk. Fall
    -- back to the statically declared owner: it is the one answer that
    -- cannot double-install, which is the failure worth avoiding. The other
    -- bundle stands down even if the owner is not installed, so the feature
    -- goes missing rather than being applied twice -- and says so in the log.
    local owner = feature.shared and feature.shared.owner
    if owner and owner ~= mod.id then return false, owner end
    return true, nil
  end

  local holder = claims[key]
  if holder ~= nil and holder ~= mod.id then return false, holder end
  claims[key] = mod.id
  return true, nil
end

return Claims
