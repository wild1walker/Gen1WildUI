-- Who answers when a bundled feature asks for one of its old neighbours.
--
-- Gen151 calls `mod.find("Gen1Dex")` to hang catch hints off the Pokedex.
-- Gen1Party calls it for Gen1BillsBox.  Standalone, those calls reached the
-- engine's mod table and got a real mod handle back.  Bundled, the neighbour is
-- no longer a mod at all -- it is a folder inside one, possibly inside the
-- *other* bundle, since the QOL and UI splits cut straight through those
-- pairings (Gen151 is QOL, Gen1Dex is UI).
--
-- So a lookup goes three places in order:
--
--   1. this bundle          -- a sibling feature, by any of its known names
--   2. the paired bundle    -- through the engine, then through its exports
--   3. the engine           -- for mods that really are external
--
-- Step 2 is what keeps the optional-dependency graph intact across the split.
-- It is deliberately late-bound: bundles load in whatever order the engine
-- picks, so the paired bundle is looked up when the question is first asked
-- rather than when this registry is built.

local Registry = {}

-- `versions` maps a module directory to the version of the mod in it, written
-- by tools/build.py.  It is optional: without it a handle simply reports no
-- version, which is what a mod that only logs it will print.
function Registry.new(mod, spec, versions)
  local self = {
    exports = {},     -- alias (lowercased) -> a handle, shaped like the engine's
    pairedId = spec.paired_bundle,
  }
  versions = versions or {}

  local function normalize(name)
    return tostring(name):lower()
  end

  -- A feature answers to every name it ever went by: its folder, its upstream
  -- manifest id and its display title.  Gen1ModernBag alone is reachable as
  -- "Gen1ModernBag" and "gen1_modern_bag" depending on who is asking.
  -- What comes back is a HANDLE, not the exports table, because that is what
  -- the engine's own mod.find returns: { id, version, exports } (Loader.lua's
  -- api.find). Mods read it that way -- Gen151 asks for `dex.exports.area`
  -- and logs `dex.version` -- so a registry that answered with the exports
  -- table directly would hand back something whose `.exports` is nil, and
  -- every cross-mod integration would go quietly dead rather than fail. It
  -- did: Gen151's Pokedex catch hints never registered inside the bundle
  -- until this was fixed.
  function self.register(feature, exports)
    local handle = {
      id = (feature.aliases and feature.aliases[1]) or feature.dir or feature.id,
      version = versions[feature.dir],
      exports = exports,
    }
    for _, alias in ipairs(feature.aliases or {}) do
      self.exports[normalize(alias)] = handle
    end
    self.exports[normalize(feature.id)] = handle
    self.exports[normalize(feature.dir)] = handle
    return handle
  end

  function self.exportsOf(name)
    return self.exports[normalize(name)]
  end

  -- The paired bundle publishes the same alias table under
  -- `exports.features`, so one hop through the engine reaches every feature
  -- it hosts.  A missing paired bundle is the ordinary case -- somebody
  -- installed one half of the pair -- and must be silent.
  function self.acrossBundles(name)
    if not self.pairedId or type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, self.pairedId)
    if not ok or not handle then
      local okSelf, handleSelf = pcall(mod.find, mod, self.pairedId)
      if not okSelf then return nil end
      handle = handleSelf
    end
    if type(handle) ~= "table" then return nil end
    local features = handle.features or (handle.exports and handle.exports.features)
    if type(features) ~= "table" then return nil end

    local found = features[normalize(name)]
    if found == nil then return nil end
    -- A bundle released before handles were introduced publishes the exports
    -- table itself. Wrap it so a caller gets the same shape either way rather
    -- than having its integration depend on which half was updated first.
    if type(found) == "table" and found.exports ~= nil then return found end
    return { id = name, version = nil, exports = found }
  end

  -- Published on the bundle's own exports so the other half can do the same
  -- lookup in reverse.
  function self.table()
    return self.exports
  end

  return self
end

return Registry
