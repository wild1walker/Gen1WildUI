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

function Registry.new(mod, spec)
  local self = {
    exports = {},     -- alias (lowercased) -> that feature's exports table
    pairedId = spec.paired_bundle,
  }

  local function normalize(name)
    return tostring(name):lower()
  end

  -- A feature answers to every name it ever went by: its folder, its upstream
  -- manifest id and its display title.  Gen1ModernBag alone is reachable as
  -- "Gen1ModernBag" and "gen1_modern_bag" depending on who is asking.
  function self.register(feature, exports)
    for _, alias in ipairs(feature.aliases or {}) do
      self.exports[normalize(alias)] = exports
    end
    self.exports[normalize(feature.id)] = exports
    self.exports[normalize(feature.dir)] = exports
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
    return features[normalize(name)]
  end

  -- Published on the bundle's own exports so the other half can do the same
  -- lookup in reverse.
  function self.table()
    return self.exports
  end

  return self
end

return Registry
