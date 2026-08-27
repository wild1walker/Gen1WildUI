-- The `mod` object a bundled feature is handed instead of the real one.
--
-- Every mod in the index was written as a standalone mod: it owns its options
-- table, its save bucket, its cache files, its asset root, and it looks its
-- siblings up by name through `mod.find`.  A bundle breaks all five of those
-- assumptions at once, so rather than patch a dozen upstreams, each feature
-- gets a stand-in that keeps every one of them true from the inside.
--
--   mod:read("src/x.lua")   -> modules/<Feature>/src/x.lua
--   mod.assets:path("a.png")-> modules/<Feature>/a.png
--   mod.options:get("enabled") -> <feature>_enabled
--   mod.save:get("k")       -> "<feature>.k"
--   mod.cache:read("f")     -> "<feature>.f"
--   mod.find("Gen1Dex")     -> the sibling's exports, in this bundle or the other one
--
-- Anything not listed above falls through to the real mod object untouched, so
-- hooks, events, world, ui, content and input behave exactly as they always
-- did.  That fallthrough is deliberate: it means a feature that starts using a
-- new engine API keeps working here without this file being taught about it.

local Facade = {}

-- LuaJIT keeps `unpack` global; 5.4 moved it onto `table`.  The engine runs the
-- former, but a headless test harness may not.
local unpack = unpack or table.unpack

local function joinKey(featureId, key)
  return featureId .. "." .. tostring(key)
end

-- `mod.find` is called three different ways across the index: `mod.find(name)`,
-- `mod.find(mod, name)` and `pcall(mod.find, mod, name)`.  Take whichever
-- argument is the string.
local function nameFrom(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  return nil
end

-- feature: the registry entry { id, label, dir, entry, ... }
-- context: { mod, optionset, registry, loader }
function Facade.new(feature, context)
  local mod = context.mod
  local optionset = context.optionset
  local root = "modules/" .. feature.dir .. "/"

  local facade = {}

  -- ---- identity
  --
  -- `mod.id` stays the *bundle's* id on purpose.  Features use it for two
  -- things: addressing their bucket in `save.options.modOptions[mod.id]`, and
  -- filtering the engine's `mod.options_changed` event by `ev.mod`.  Both are
  -- correct against the bundle id -- the options really do live in the
  -- bundle's bucket now, and the change event really is emitted for the
  -- bundle -- and the key collisions that sharing a bucket would normally
  -- cause are already prevented by prefixing.
  facade.id = mod.id
  facade.path = tostring(mod.path) .. "/modules/" .. feature.dir
  facade.version = feature.version or mod.version
  facade.exports = {}

  -- `mod.exports` is how a feature reaches its SIBLINGS: the bundle registers
  -- it in runtime/registry.lua under every name the feature answers to, and a
  -- sibling asks by name through mod.find.  That is the right shape for one
  -- bundled mod talking to another, and the wrong shape for a feature whose
  -- API is meant for the world outside: reaching it from another mod means
  -- knowing that this bundle exists, that it keeps a registry, and what the
  -- feature's folder is called -- three facts about our plumbing that nothing
  -- out there should have to learn.
  --
  -- `mod.publish` puts a value on the BUNDLE's own exports, where the engine's
  -- own mod.find already looks:
  --
  --     local qol = mod.find("gen1_wild_qol")
  --     local api = qol and qol.exports and qol.exports.statusColours
  --
  -- Two names cannot be published by two features: the second is refused and
  -- says so, because silently winning would make which mod answers depend on
  -- feature order.  Nothing about the bundle's own exports is overwritable
  -- either -- `features`, `bundle` and the rest are the runtime's.
  function facade.publish(name, value)
    if type(name) ~= "string" or name == "" then
      mod.log:error("[%s] publish needs a name", feature.label)
      return false
    end
    local taken = context.published or {}
    context.published = taken
    if taken[name] and taken[name] ~= feature.id then
      mod.log:error("[%s] will not publish %q: %s published it first",
        feature.label, name, tostring(taken[name]))
      return false
    end
    if mod.exports[name] ~= nil and taken[name] == nil then
      mod.log:error("[%s] will not publish %q: the bundle already exports it",
        feature.label, name)
      return false
    end
    taken[name] = feature.id
    mod.exports[name] = value
    return true
  end

  -- A scratch table shared by every feature in the bundle.  It exists for the
  -- one case where two features genuinely need the same object rather than one
  -- each: the QOL battle overlay host, which the XP bar and the caught marker
  -- both draw into and which should wrap `battle.draw` once rather than twice.
  facade.shared = context.shared

  -- ---- filesystem

  function facade:read(path)
    return mod:read(root .. tostring(path))
  end

  facade.assets = setmetatable({}, {
    __index = function(_, name)
      local real = mod.assets and mod.assets[name]
      if name == "path" and type(real) == "function" then
        return function(_, p) return real(mod.assets, root .. tostring(p)) end
      end
      if type(real) == "function" then
        return function(_, ...) return real(mod.assets, ...) end
      end
      return real
    end,
  })

  -- ---- options

  local function optionKey(key)
    return optionset.prefixed(feature.id, tostring(key))
  end

  facade.options = {
    -- Returns the schema it was handed, which is what the engine does and
    -- what Gen151 relies on: it iterates the return value to build its own
    -- key -> row map for validating stored values, and would silently get an
    -- empty map -- and skip that validation -- if handed anything else.  The
    -- rows come back with their *original* keys, because that is the
    -- vocabulary the feature reads and writes in.
    define = function(selfOrSchema, maybeSchema)
      local schema = maybeSchema
      if schema == nil then schema = selfOrSchema end
      optionset.adopt(feature, schema)
      return schema
    end,
    get = function(selfOrKey, maybeKey)
      local key = maybeKey
      if key == nil then key = selfOrKey end
      if type(key) ~= "string" then return nil end
      return optionset.read(mod, optionKey(key))
    end,
    set = function(selfOrKey, maybeKeyOrValue, maybeValue)
      local key, value = maybeKeyOrValue, maybeValue
      if type(selfOrKey) == "string" then key, value = selfOrKey, maybeKeyOrValue end
      if type(key) ~= "string" then return nil end
      if mod.options and type(mod.options.set) == "function" then
        return mod.options:set(optionKey(key), value)
      end
      return nil
    end,
  }

  -- ---- per-feature save / cache / storage
  --
  -- Three separate stores, all keyed by strings a feature picked without
  -- knowing anyone else existed: Gen1ModernBag writes "last_pocket",
  -- Gen1Follower writes "selected_slot", Gen1AutoSave writes numbered
  -- checkpoint slots.  Prefixing keeps them apart, and it does so without the
  -- features knowing -- they read back exactly what they wrote.

  local function keyedProxy(realTable, keyPosition)
    if not realTable then return nil end
    return setmetatable({}, {
      __index = function(_, name)
        local real = realTable[name]
        if type(real) ~= "function" then return real end
        return function(_, ...)
          local count = select("#", ...)
          local args = { ... }
          if type(args[keyPosition]) == "string" then
            args[keyPosition] = joinKey(feature.id, args[keyPosition])
          end
          return real(realTable, unpack(args, 1, count))
        end
      end,
    })
  end

  -- save:get(key, default) / save:set(key, value) -- key is first
  facade.save = keyedProxy(mod.save, 1)
  -- cache:read(file) / cache:write(file, bytes) -- file is first
  facade.cache = keyedProxy(mod.cache, 1)
  -- storage:read(game, key) / write(game, key, v) / delete(game, key) -- key is second
  facade.storage = keyedProxy(mod.storage, 2)

  -- ---- logging
  --
  -- Twelve features logging into one mod's log with no attribution is a log
  -- nobody can act on.  Every line gets its feature's name in front of it.

  facade.log = setmetatable({}, {
    __index = function(_, level)
      local real = mod.log and mod.log[level]
      if type(real) ~= "function" then return real end
      return function(_, format, ...)
        return real(mod.log, "[" .. feature.label .. "] " .. tostring(format), ...)
      end
    end,
  })

  -- ---- hooks
  --
  -- A feature may have its config surfaced by the bundle's own menu instead of
  -- by the rows it used to insert on the engine OPTIONS screen.  Listing that
  -- hook in `suppress_hooks` drops its registration rather than patching the
  -- upstream file, so the setting has exactly one home in the UI.

  local suppressed = feature.suppress_hooks or {}

  facade.hooks = setmetatable({}, {
    __index = function(_, name)
      local real = mod.hooks and mod.hooks[name]
      if type(real) ~= "function" then return real end
      return function(_, hookName, ...)
        if suppressed[hookName] then
          mod.log:info("[%s] %s not registered: the bundle draws that row itself",
            feature.label, tostring(hookName))
          return nil
        end
        return real(mod.hooks, hookName, ...)
      end
    end,
  })

  -- ---- events
  --
  -- One event needs translating on the way in: `mod.options_changed`.  Three
  -- features listen for it, and each filters the payload against what it
  -- believes its own identity and its own option keys are.  Unpatched, they
  -- would see the bundle's identity and sixty prefixed keys, and every one of
  -- their filters would fall the wrong way -- Gen1AutoSave would never notice
  -- its interval changing, Gen1Follower would never resize a follower.
  --
  -- The payload is rewritten into the feature's own vocabulary: keys that
  -- belong to another feature are dropped outright, this feature's keys have
  -- their prefix taken off, and a payload identifying the mod by object rather
  -- than by id is pointed at the facade.  Identification by id needs no work,
  -- since the facade deliberately shares the bundle's id.

  local OPTIONS_CHANGED = "mod.options_changed"

  local function translateOptionsChanged(callback)
    local prefix = feature.id .. "_"
    return function(payload, ...)
      if type(payload) ~= "table" then return callback(payload, ...) end

      if type(payload.key) == "string" then
        if payload.key:sub(1, #prefix) ~= prefix then return end
      end

      local translated = {}
      for k, v in pairs(payload) do translated[k] = v end
      if type(payload.key) == "string" then
        translated.key = payload.key:sub(#prefix + 1)
      end
      if payload.mod == mod then translated.mod = facade end
      return callback(translated, ...)
    end
  end

  facade.events = setmetatable({}, {
    __index = function(_, name)
      local real = mod.events and mod.events[name]
      if type(real) ~= "function" then return real end
      return function(_, eventName, callback, ...)
        if eventName == OPTIONS_CHANGED and type(callback) == "function" then
          callback = translateOptionsChanged(callback)
        end
        return real(mod.events, eventName, callback, ...)
      end
    end,
  })

  -- ---- cross-mod lookup
  --
  -- Gen151 asks for Gen1Dex, Gen1Party asks for Gen1BillsBox, Gen1ModernBag
  -- asks for gen1_modern_ui.  Bundling breaks every one of those: the sibling
  -- is no longer a mod the engine can find by name -- it is a folder inside
  -- one.  So resolution goes local first (a feature in this bundle), then
  -- across (a feature in the paired bundle, reached through its exports), then
  -- out to the engine for genuinely external mods.

  function facade.find(a, b)
    local name = nameFrom(a, b)
    if not name then return nil end

    local sibling = context.registry.exportsOf(name)
    if sibling then return sibling end

    local paired = context.registry.acrossBundles(name)
    if paired then return paired end

    if type(mod.find) == "function" then
      local ok, handle = pcall(mod.find, name)
      if ok and handle then return handle end
      local okSelf, handleSelf = pcall(mod.find, mod, name)
      if okSelf then return handleSelf end
    end
    return nil
  end

  -- ---- everything else
  --
  -- events, world, ui, content, input, game, registered, manifest, state and
  -- whatever the engine grows next, straight through to the real object.
  return setmetatable(facade, {
    __index = function(_, name)
      local value = mod[name]
      if type(value) == "function" then
        -- Preserve colon-call semantics: the feature calls facade:thing(), so
        -- rebind the receiver to the real mod.
        return function(receiver, ...)
          if receiver == facade then return value(mod, ...) end
          return value(receiver, ...)
        end
      end
      return value
    end,
  })
end

return Facade
