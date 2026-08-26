-- Gen1WildUI -- the visual half of the Gen1Wild suite, as one mod.
--
-- Nothing in here knows what any particular feature does.  This file is the
-- bootstrap and nothing else: it loads the runtime, hands it the feature
-- registry in features.lua, and gets out of the way.  Which mods are in the
-- bundle, what they are called and how they are switched is a data question,
-- answered in features.lua; how a bundle hosts a mod written to be standalone
-- is answered in runtime/.
--
-- The two-step load below is the only part worth explaining.  A mod's
-- `require` is sandboxed to engine modules and other mods' exports, so this
-- mod cannot require its own files.  The supported route is mod:read + load,
-- which is what runtime/loader.lua wraps -- but loading the loader is itself
-- the thing the loader does, so it is bootstrapped by hand here, once, and
-- everything after it goes through the real one.

local RUNTIME = "runtime/"

return function(mod)
  -- The hand-rolled bootstrap.  Deliberately noisy on failure: if this cannot
  -- read its own files the install is broken, and a player should be told
  -- that rather than left with a mod that quietly does nothing.
  local function bootstrap(path)
    local source, readError = mod:read(path)
    if not source then
      mod.log:error("cannot read %s (%s) -- reinstall Gen1WildUI",
        path, tostring(readError))
      return nil
    end
    local chunk, compileError = load(source, "@" .. tostring(mod.path) .. "/" .. path)
    if not chunk then
      mod.log:error("%s did not compile: %s", path, tostring(compileError))
      return nil
    end
    return chunk
  end

  local loaderChunk = bootstrap(RUNTIME .. "loader.lua")
  if not loaderChunk then return end
  local okLoader, Loader = pcall(loaderChunk)
  if not okLoader or type(Loader) ~= "table" then
    mod.log:error("runtime/loader.lua did not return a loader: %s", tostring(Loader))
    return
  end

  local loader = Loader.new(mod)

  local function loadRuntime(name)
    return loader.run(RUNTIME .. name .. ".lua")
  end

  local registry = loader.run("features.lua")
  if type(registry) ~= "table" or type(registry.features) ~= "table" then
    mod.log:error("features.lua did not return a feature registry")
    return
  end

  -- runtime/bundle.lua takes the runtime loader as its chunk argument, for the
  -- same reason this file had to bootstrap one: it cannot require its
  -- siblings either.
  local Bundle = loader.run(RUNTIME .. "bundle.lua", loadRuntime)
  if type(Bundle) ~= "table" or type(Bundle.install) ~= "function" then
    mod.log:error("runtime/bundle.lua did not return a bundle installer")
    return
  end

  Bundle.install(mod, registry.spec, registry.features)
end
