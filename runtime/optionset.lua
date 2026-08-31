-- One options table for a dozen mods that were each written believing they
-- owned it.
--
-- Every mod in the index defines its rows with `mod.options:define`, and five
-- of them call their master switch `enabled`.  Two call a row
-- `species_colours`.  Merged naively into one bundle they would silently share
-- storage: turning off the Pokedex would turn off the party menu.  So every
-- adopted row is rewritten to `<feature>_<key>` before the engine ever sees it,
-- and each feature is handed a reader that puts its own prefix back on.  The
-- feature's own source never learns this happened -- it asks for `enabled` and
-- gets its own `enabled`.
--
-- The rewrite reaches into `visible_if` too, which names a sibling row by key
-- and would otherwise point at whichever feature happened to claim that key
-- first.

local OptionSet = {}

local SEPARATOR = "_"

local function copyRow(row)
  local out = {}
  for k, v in pairs(row) do out[k] = v end
  return out
end

local function legal(row, value)
  local kind = row.type
  if kind == "toggle" then return type(value) == "boolean" end
  if kind == "number" then return type(value) == "number" end
  if kind == "text" then return type(value) == "string" end
  if kind == "choice" then
    for _, choice in ipairs(row.choices or {}) do
      if choice[2] == value then return true end
    end
    return false
  end
  -- An unknown row type is a row this runtime has no opinion about; let it
  -- through rather than clamping it to a default it may not have.
  return true
end

function OptionSet.new()
  local self = {
    rows = {},        -- in definition order, exactly what the engine is given
    byKey = {},       -- prefixed key -> rewritten row
    groups = {},      -- feature id -> { feature, rows = { prefixed row, ... } }
    order = {},       -- feature ids, in registration order
    resolveGame = nil,-- set by the bundle; the live game, when there is one
    -- prefixed key -> unprefixed key, for the handful of rows a feature
    -- writes through the engine's own mod manager rather than through
    -- mod.options.  See `raw_option_keys` in adopt().
    rawFallback = {},
    -- prefixed key -> the id its value is stored under, when that is not the
    -- bundle's own.  A feature carried by both bundles stores its settings
    -- under a shared id so they stay put when the other bundle is the one
    -- that installs it.  See `shared.storage` in features.lua.
    storageId = {},
  }

  function self.prefixed(featureId, key)
    return featureId .. SEPARATOR .. key
  end

  local function group(feature)
    local existing = self.groups[feature.id]
    if existing then return existing end
    local created = { feature = feature, rows = {}, masterKey = nil }
    self.groups[feature.id] = created
    self.order[#self.order + 1] = feature.id
    return created
  end

  -- The master switch every feature gets, whether or not its own schema has
  -- one.  A feature that already ships an `enabled`-style row donates it:
  -- reusing that row means the switch is the one the feature's own code
  -- already consults every frame, so it takes effect the moment it is
  -- flipped.  A feature without one gets a synthesized row instead, and that
  -- one gates installation at load, which is why the menu labels it as
  -- taking effect on the next launch.
  function self.master(feature)
    local g = group(feature)
    if g.masterKey then return g.masterKey end

    local key = self.prefixed(feature.id, feature.enabledKey or "enabled")
    g.masterKey = key
    g.masterIsLive = feature.enabledKey ~= nil
    if feature.shared and feature.shared.storage then
      self.storageId[key] = feature.shared.storage
    end

    if not feature.enabledKey then
      local row = {
        key = key,
        type = "toggle",
        label = feature.label,
        default = feature.default ~= false,
      }
      self.rows[#self.rows + 1] = row
      self.byKey[key] = row
      g.synthesizedMaster = row
    end
    return key
  end

  -- A row the BUNDLE owns rather than a feature.
  --
  -- Unprefixed, because there is no feature to prefix it with and nothing to
  -- collide with: the prefix exists to keep a dozen mods that each called
  -- their switch `enabled` apart, and the bundle is not one of them.  It
  -- lands in the same schema every other row lands in, so it is stored, read,
  -- defaulted, validated and remembered across a sealed cart's option reset
  -- exactly like the rest -- runtime/settings.lua works by key and needs no
  -- teaching about it.
  --
  -- It belongs to no group, so the menu does not draw it under a feature's
  -- card; whoever defines it is responsible for putting it somewhere a player
  -- can reach.
  function self.own(row)
    if type(row) ~= "table" or type(row.key) ~= "string" then return nil end
    if self.byKey[row.key] then return row.key end
    local copy = copyRow(row)
    self.rows[#self.rows + 1] = copy
    self.byKey[copy.key] = copy
    return copy.key
  end

  -- Take one feature's schema and fold it in.  Returns nothing: the feature
  -- talks to its rows through the reader, never through this table.
  function self.adopt(feature, schema)
    if type(schema) ~= "table" then return end
    local g = group(feature)
    local overrides = feature.defaults or {}
    local rawKeys = {}
    for _, key in ipairs(feature.raw_option_keys or {}) do rawKeys[key] = true end

    for _, incoming in ipairs(schema) do
      if type(incoming) == "table" and type(incoming.key) == "string" then
        local row = copyRow(incoming)
        local raw = incoming.key
        row.key = self.prefixed(feature.id, raw)

        -- A bundle-level default beats the upstream one.  This is how Gen151
        -- ships enabled inside the bundle while its own repo ships it off,
        -- without carrying a patch against upstream source.
        if overrides[raw] ~= nil then row.default = overrides[raw] end

        -- Gen1ModMenu is the mod manager, and sets three of its own rows by
        -- calling the manager's `setOption(modId, key, value)` -- which
        -- writes the *unprefixed* key into the bundle's bucket, because the
        -- manager has no idea this mod is one of twelve.  Left alone, those
        -- three rows would be written in one place and read from another.
        --
        -- Naming them here makes the runtime read both spellings and write
        -- both, so it does not matter which path set a value.  It is
        -- deliberately a per-feature opt-in list rather than a blanket raw
        -- fallback: a blanket one would undo the prefixing entirely for the
        -- five mods that all call a row `enabled`.
        if rawKeys[raw] then self.rawFallback[row.key] = raw end
        if feature.shared and feature.shared.storage then
          self.storageId[row.key] = feature.shared.storage
        end

        -- `visible_if = { key = "enabled", equals = true }` means *this
        -- feature's* enabled, always.
        if type(row.visible_if) == "table" and type(row.visible_if.key) == "string" then
          local condition = {}
          for k, v in pairs(row.visible_if) do condition[k] = v end
          condition.key = self.prefixed(feature.id, condition.key)
          row.visible_if = condition
        end

        if self.byKey[row.key] then
          -- Same feature defining the same key twice.  Last definition wins,
          -- matching what a single mod calling define twice would get.
          for i, existing in ipairs(self.rows) do
            if existing.key == row.key then self.rows[i] = row break end
          end
        else
          self.rows[#self.rows + 1] = row
        end
        self.byKey[row.key] = row

        -- The donated master row is the feature's switch, not one of its
        -- settings, so it is kept out of the feature's own row list -- the
        -- menu draws it one level up.
        if row.key == g.masterKey then
          g.masterRow = row
          -- The bundle's shipped state for a donated master.  A boolean is
          -- read as on/off whatever the row's type; anything else has to be a
          -- value the row actually offers, or it is ignored in favour of
          -- upstream's own default -- a master row nobody can select is worse
          -- than one shipped the wrong way round.
          if overrides[raw] == nil and feature.default ~= nil then
            if row.type == "toggle" then
              row.default = feature.default ~= false
            elseif legal(row, feature.default) then
              row.default = feature.default
            end
          end
        else
          g.rows[#g.rows + 1] = row
        end
      end
    end
  end

  -- ---- storage
  --
  -- Mod options are a per-save thing in this engine: the live values sit in
  -- `save.options.modOptions[<mod id>]`, and `mod.options:get` is the
  -- load-time view of them.  Reads consult the save first so a row changed in
  -- the menu takes effect on the very next frame rather than on the next
  -- launch, and fall back through the engine's view to the row's own default.

  local function bucketOf(container, modId)
    if type(container) ~= "table" then return nil end
    container.modOptions = container.modOptions or {}
    container.modOptions[modId] = container.modOptions[modId] or {}
    return container.modOptions[modId]
  end

  local writes = 0

  local function liveGame()
    if type(self.resolveGame) ~= "function" then return nil end
    local ok, game = pcall(self.resolveGame)
    if ok then return game end
    return nil
  end

  -- Read a prefixed key with the row's own default as the floor.  A stored
  -- value can be anything -- an older version's vocabulary, a hand-edited
  -- options file, a value written before a choice list was narrowed -- and a
  -- feature that divided by a garbage string would be a crash out in the
  -- overworld.  Out-of-vocabulary reads fall back to the row default.
  function self.read(mod, key)
    local row = self.byKey[key]
    local storedUnder = self.storageId[key] or mod.id

    local value
    local game = liveGame()
    local options = game and game.save and game.save.options
    if type(options) == "table" and type(options.modOptions) == "table" then
      local bucket = options.modOptions[storedUnder]
      if type(bucket) == "table" then value = bucket[key] end
    end
    if value == nil and mod.options and type(mod.options.get) == "function" then
      value = mod.options:get(key)
    end

    local raw = self.rawFallback[key]
    if value == nil and raw then
      if type(options) == "table" and type(options.modOptions) == "table" then
        local bucket = options.modOptions[storedUnder]
        if type(bucket) == "table" then value = bucket[raw] end
      end
      if value == nil and mod.options and type(mod.options.get) == "function" then
        value = mod.options:get(raw)
      end
    end

    if not row then return value end
    if value == nil or not legal(row, value) then return row.default end
    if row.type == "number" then
      if row.min then value = math.max(row.min, value) end
      if row.max then value = math.min(row.max, value) end
    end
    return value
  end

  -- Write one row and persist it.  Both stores are updated: the save, which is
  -- what every read above sees first, and the engine's own view, so a value
  -- survives into the next launch even if the save is written by some path
  -- that does not carry modOptions.
  -- ------- a token a reader can cache against
  --
  -- `self.read` is not free -- it walks the live game's save, the mod's own
  -- option store and the row's fallbacks -- and a caller that asks it many
  -- times a frame wants to ask it once.  It cannot just remember the answer:
  -- a value can be written from the bundle's own menu, from the OTHER
  -- bundle's menu through `mod.exports.optionWrite`, or from the test bench,
  -- and none of those three goes through the same door.
  --
  -- They all go through THIS one.  The number changes on every write, so a
  -- cache that stores it beside its answer is exact rather than merely
  -- fresh-ish, and no caller has to know who else can write.
  function self.generation()
    return writes
  end

  function self.write(mod, key, value, game)
    writes = writes + 1
    game = game or liveGame()
    local options = game and game.save and game.save.options
    local raw = self.rawFallback[key]
    local storedUnder = self.storageId[key] or mod.id
    local bucket = bucketOf(options, storedUnder)
    if bucket then
      bucket[key] = value
      if raw then bucket[raw] = value end
    end
    if game and type(game.mods) == "table" then
      local mirror = bucketOf(game.mods, storedUnder)
      if mirror then mirror[key] = value end
    end
    if mod.options and type(mod.options.set) == "function" then
      pcall(function() mod.options:set(key, value) end)
      if raw then pcall(function() mod.options:set(raw, value) end) end
    end
    if game then
      -- Gen 1's Game spells this writeOptions; Gold's Game2 spells it
      -- persistOptions.
      if type(game.writeOptions) == "function" then
        pcall(function() game:writeOptions() end)
      elseif type(game.persistOptions) == "function" then
        pcall(function() game:persistOptions() end)
      end
    end
    return value
  end

  function self.enabled(mod, featureId)
    local g = self.groups[featureId]
    if not g or not g.masterKey then return false end
    return self.read(mod, g.masterKey) ~= false
  end

  -- Hand the whole merged schema to the engine.  One call, once, after every
  -- feature has been adopted: `define` is the engine's chance to seed defaults
  -- and draw rows, and calling it per feature would leave earlier features
  -- undefined while later ones installed.
  function self.define(mod)
    mod.options:define(self.rows)
  end

  return self
end

return OptionSet
