-- The bundle's own OPTION screens.
--
-- A bundle of a dozen mods that dumped a dozen mods' worth of rows onto one
-- flat list would be worse than the twelve mods it replaced.  So the rows are
-- nested the way the game's own OPTION screen nests its own: a screenful of
-- folder cards, each card a handful of related rows, each row switched ON or
-- OFF right there, and that row's settings one press of A away.
--
--   OPTION
--     WILD GREEN            21 MODS       -- A opens:
--       OUT IN THE WORLD    ALL 4 ON      -- A opens:
--         SPRINT            ON (CONFIGURE)  -- A opens:
--           HOLD            B
--           SPRINT SPEED    2x
--           BIKE SPEED      2x
--           RESET DEFAULTS
--         EASY HM USE       ON (CONFIGURE)
--         AREA BANNER       3 SECONDS
--         ELEVATOR PANEL    ON
--       YOUR POKEMON        ALL 6 ON
--       BATTLES             4 OF 5 ON
--       ...
--       OTHER MODS          2 MODS
--
-- Four rows fit on a screen, so the tier earns itself: thirteen features flat
-- was four screenfuls of scrolling, and six cards is one and a half with three
-- or four rows behind each.  The cards are declared in features.lua as
-- `spec.groups` and a feature names its card with `group`; a feature that
-- names no card, or names one that is not declared, keeps its old place as a
-- plain row on the top level.  A bundle that declares no cards at all gets the
-- flat list it always had.
--
-- Three things are gathered onto that one screen, and each is here because
-- without it the player has to go looking somewhere else for a setting:
--
--   1. This bundle's features, from the merged option schema -- so a row a mod
--      adds upstream shows up here on the next sync without this file changing.
--
--   2. The other half of the suite's features.  Gen1WildQOL and Gen1WildUI are
--      one suite split in two for the index's sake, and a player who installed
--      both had to remember which half owned which setting.  Each bundle
--      publishes a description of its own menu (`mod.exports.menu`) and renders
--      the other's features beside its own, delegating the switch to the bundle
--      that owns it and pushing that bundle's own settings screen on A.
--      Whichever half is opened shows the whole suite; with one half installed
--      the lookup finds nothing and the menu is that half's own.
--
--   3. Every other mod that is loaded and has options -- the rest of what a
--      cart pins, and anything the player installed themselves.  Those rows are
--      built from the schema the loader captured when the mod called
--      mod.options:define, which is the same schema the mod manager's own
--      per-mod page is built from; this is that page, reached from here instead
--      of from three screens inside MODS.
--
-- The chrome is the engine's own -- src.ui.OptionRows on Red/Blue/Yellow,
-- src.ui.gen2.Chrome on Gold -- so the screens are drawn in the same idiom as
-- the OPTION screen they hang off, rather than in a look of their own.

local Menu = {}

local GEN2_VISIBLE_ROWS = 7
-- Gold's own OptionsMenu puts its value column at 11, which suits values like
-- ON and STEREO.  These are longer ("ON (CONFIGURE)"), so they start earlier.
local GEN2_VALUE_TX = 4

local RESET_ROW = "__reset_defaults"

-- The row this bundle puts on the game's own OPTION screen.  One id, shared by
-- both halves deliberately: whichever loads first adds the row and the other
-- finds it already there and leaves it alone, so a player with both halves
-- installed gets one door rather than two identical ones.
local OPTION_ROW_ID = "gen1wild_options"
-- The theme row's own id, shared between the two halves for the same reason
-- the door's is: either half can be the one installed, and two identical rows
-- on the OPTION screen is worse than one.
local THEME_ROW_ID = "gen1wild_ui_theme"

-- The card the other loaded mods go under, and the screen that renders one of
-- them.  The mods are not known until a game is running, so there is one screen
-- id for all of them and the mod being configured is a push argument.  A bundle
-- must not declare a group of this id in features.lua: this card would shadow
-- it.
local OTHER_CARD = "other_mods"

local OPTION_TYPES = { toggle = true, choice = true, number = true }

local function labelForValue(row, value)
  if row.type == "toggle" then
    return value and "ON" or "OFF"
  end
  if row.type == "choice" then
    for _, choice in ipairs(row.choices or {}) do
      if choice[2] == value then return tostring(choice[1]) end
    end
    return tostring(value)
  end
  if row.type == "number" then
    return tostring(value) .. (row.suffix and (" " .. row.suffix) or "")
  end
  return tostring(value)
end

local function stepValue(row, value, dir)
  if row.type == "toggle" then return not value end
  if row.type == "choice" then
    local choices = row.choices or {}
    if #choices == 0 then return value end
    local index = 1
    for i, choice in ipairs(choices) do
      if choice[2] == value then index = i break end
    end
    return choices[((index - 1 + dir) % #choices) + 1][2]
  end
  if row.type == "number" then
    local step = row.step or 1
    local next_ = (tonumber(value) or row.default or 0) + step * dir
    local min, max = row.min, row.max
    if min and max then
      if next_ > max then next_ = min elseif next_ < min then next_ = max end
    elseif min and next_ < min then next_ = min
    elseif max and next_ > max then next_ = max
    end
    return next_
  end
  return value
end

-- feature.description is a sentence; the engine's TextBox wants it broken into
-- lines it can fit, with \f between pages.  Anything already carrying a newline
-- is assumed to be written for the box already and is left alone.
local function asTextBox(text)
  text = tostring(text or "")
  if text:find("[\n\f]") then return text end
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    local candidate = (line == "") and word or (line .. " " .. word)
    if #candidate > 17 then
      lines[#lines + 1] = line
      line = word
    else
      line = candidate
    end
  end
  if line ~= "" then lines[#lines + 1] = line end

  local pages, page = {}, {}
  for _, entry in ipairs(lines) do
    page[#page + 1] = entry
    if #page == 2 then
      pages[#pages + 1] = table.concat(page, "\n")
      page = {}
    end
  end
  if #page > 0 then pages[#pages + 1] = table.concat(page, "\n") end
  return table.concat(pages, "\f")
end

-- The menu's labels are the game's: capitals, and no lower case to fall back
-- on in the font.  A mod's manifest name is written for a launcher list.
local function asMenuLabel(text, fallback)
  text = tostring(text or "")
  if text == "" then return fallback end
  return (text:upper():gsub("[^%u%d%s%-%.%(%)&']", " "):gsub("%s+", " "))
end

-- ---------------------------------------------------------------------------
-- The other loaded mods, read through the loader the mod manager reads.
--
-- game.mods is the loader: `optionSchemas` is what each mod passed to
-- mod.options:define, and `modOptions` is the live value table the manager
-- writes through.  Everything here is the manager's own arithmetic
-- (ManagerState optionValue / setOption), done against the same two tables, so
-- a row set here and a row set there are the same row.
-- ---------------------------------------------------------------------------

local Other = {}

function Other.loader(game)
  local loader = game and game.mods
  if type(loader) ~= "table" then return nil end
  return loader
end

function Other.schema(game, modId)
  local loader = Other.loader(game)
  local schemas = loader and loader.optionSchemas
  local schema = type(schemas) == "table" and schemas[modId] or nil
  return type(schema) == "table" and schema or nil
end

-- Every mod that is loaded, has options and is not one of ours.  `skip` is the
-- set of ids the suite already renders as features of its own.
function Other.mods(game, skip)
  local loader = Other.loader(game)
  if not loader or type(loader.status) ~= "function" then return {} end
  local ok, status = pcall(loader.status, loader)
  if not ok or type(status) ~= "table" then return {} end

  -- A cart's pins first and in the cart's own order, because that is the order
  -- the player's setup was built in; then anything else that is loaded, so a
  -- mod installed by hand is never unreachable from here.
  local report = status.cart
  local rank = (type(report) == "table" and type(report.rank) == "table")
    and report.rank or {}

  local out = {}
  for _, manifest in ipairs(status.loaded or {}) do
    local id = manifest.id
    if type(id) == "string" and not skip[id] and Other.schema(game, id) then
      out[#out + 1] = {
        id = id,
        label = asMenuLabel(manifest.name, id),
        description = manifest.description,
        pinned = rank[id],
      }
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = a.pinned or math.huge, b.pinned or math.huge
    if ra ~= rb then return ra < rb end
    return a.label < b.label
  end)
  return out
end

function Other.read(game, modId, row)
  local loader = Other.loader(game)
  local stored = loader and type(loader.modOptions) == "table"
    and loader.modOptions[modId] or nil
  local value = type(stored) == "table" and stored[row.key] or nil
  if value == nil then
    local options = game and game.save and game.save.options
    local bucket = type(options) == "table" and type(options.modOptions) == "table"
      and options.modOptions[modId] or nil
    if type(bucket) == "table" then value = bucket[row.key] end
  end
  if value == nil then value = row.default end
  return value
end

function Other.write(game, modId, key, value)
  local options = game and game.save and game.save.options
  if type(options) == "table" then
    options.modOptions = options.modOptions or {}
    options.modOptions[modId] = options.modOptions[modId] or {}
    options.modOptions[modId][key] = value
  end
  local loader = Other.loader(game)
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[modId] = loader.modOptions[modId] or {}
    loader.modOptions[modId][key] = value
  end
  if game then
    if type(game.writeOptions) == "function" then
      pcall(function() game:writeOptions() end)
    elseif type(game.persistOptions) == "function" then
      pcall(function() game:persistOptions() end)
    end
  end
  -- The event the mod itself listens for.  Without it a mod that caches its
  -- options would keep the value it read at boot, which is the difference
  -- between a row that works from the manager and one that only looks like it
  -- works from here.
  if loader and loader.events and type(loader.events.emit) == "function" then
    pcall(function()
      loader.events:emit("mod.options_changed",
        { mod = modId, key = key, value = value })
    end)
  end
  return value
end

-- ---------------------------------------------------------------------------

function Menu.new(context)
  local mod = context.mod
  local optionset = context.optionset
  local spec = context.spec
  local features = context.features

  local self = {}
  local rootScreenId = spec.screen_id
  -- token -> { was = <installed at boot>, key = ..., bundle = <exports or nil> }
  local restartPending = {}

  local function featureScreenId(featureId)
    return rootScreenId .. "_" .. featureId
  end
  local function groupScreenId(groupId)
    return rootScreenId .. "__" .. groupId
  end
  local otherModScreenId = rootScreenId .. "__mod"

  local function read(key) return optionset.read(mod, key) end
  local function write(game, key, value) return optionset.write(mod, key, value, game) end

  -- The cards, in the order features.lua declares them.  Both halves declare
  -- the same set so that a merged menu reads the same way whichever half is
  -- hosting it; a card with nothing in it is not drawn.
  local groups = {}
  local declaredGroup = {}
  for _, group in ipairs(spec.groups or {}) do
    if type(group) == "table" and type(group.id) == "string" then
      groups[#groups + 1] = group
      declaredGroup[group.id] = group
    end
  end

  -- ---- mods the suite gives a door of their own
  --
  -- A mod that is not a feature of either half still lands in this menu,
  -- under OTHER MODS -- which is right for a mod the player installed
  -- themselves and wrong for one the CART pins as part of what the game is.
  -- Wild Green's player recolour is the second kind: it is the reason the
  -- cart is called what it is, and reaching it meant WILD GREEN > OTHER MODS
  -- > MAKE IT GREEN > the row, three doors deep and behind a name that is
  -- the repository's rather than the setting's.
  --
  -- `spec.adopted` names those.  Each entry gives the mod's id, the label the
  -- card wears -- what the settings ARE, not what the mod is called -- and
  -- its description.  The card is the same `mod` row OTHER MODS builds, so
  -- it opens the same screen and writes through the same loader; what
  -- changes is where it sits and what it is called.
  --
  -- Both halves declare the same list, for the same reason both declare the
  -- same cards: either can end up hosting the merged menu.  An id that is
  -- not loaded simply has no card, so a cart that drops one of these is a
  -- menu with one fewer row rather than a dead end.
  local adopted = {}
  local adoptedId = {}
  for _, entry in ipairs(spec.adopted or {}) do
    if type(entry) == "table" and type(entry.mod) == "string" then
      adopted[#adopted + 1] = entry
      adoptedId[entry.mod] = entry
    end
  end

  -- ---- the other half of the suite
  --
  -- Late-bound on purpose: the two bundles load in whatever order the engine
  -- picks, so the sibling is looked up when the menu is first drawn rather than
  -- when it is built.  A miss is not cached, so a sibling that loads afterwards
  -- is still picked up.
  local siblingCache = nil

  local function sibling()
    if siblingCache then return siblingCache end
    local paired = spec.paired_bundle
    if type(paired) ~= "string" or type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, paired)
    if not ok or type(handle) ~= "table" then
      local okSelf, handleSelf = pcall(mod.find, mod, paired)
      if not okSelf or type(handleSelf) ~= "table" then return nil end
      handle = handleSelf
    end
    local exports = handle.exports
    if type(exports) ~= "table" then exports = handle end
    local descriptor = exports.menu
    if type(descriptor) ~= "table" or type(descriptor.features) ~= "table" then
      -- A sibling released before this existed. Nothing to merge; its own menu
      -- still works, and the deferred rows below still say where to find it.
      return nil
    end
    if type(exports.optionValue) ~= "function"
        or type(exports.optionWrite) ~= "function" then
      return nil
    end
    siblingCache = { exports = exports, descriptor = descriptor }
    return siblingCache
  end

  -- ---- reading and writing a feature's master switch, ours or theirs

  local function entryRead(entry)
    if entry.bundle then
      local ok, value = pcall(entry.bundle.optionValue, entry.key)
      if ok then return value end
      return nil
    end
    return read(entry.key)
  end

  local function entryWrite(game, entry, value)
    if entry.bundle then
      pcall(entry.bundle.optionWrite, entry.key, value, game)
      return value
    end
    return write(game, entry.key, value)
  end

  -- ---- the per-feature settings screen

  -- `visible_if = { key = ..., equals = ... }` hides a row whose governing row
  -- is set some other way -- Gen151 hides its nine content rows behind its own
  -- master, Gen1Sprint hides the sprint rows when sprinting is off.  Hiding
  -- never changes the stored value, so a row that comes back shows what the
  -- player last chose.  The rows are recomputed per screen build, which is why
  -- turning a governing row is reflected the moment the screen redraws.
  local function visible(row)
    local condition = row.visible_if
    if type(condition) ~= "table" or type(condition.key) ~= "string" then
      return true
    end
    if condition.equals ~= nil then
      return read(condition.key) == condition.equals
    end
    if condition.not_equals ~= nil then
      return read(condition.key) ~= condition.not_equals
    end
    return true
  end

  local function featureRows(feature, game)
    local group = optionset.groups[feature.id]
    local rows = {}
    if not group then return rows end
    for _, row in ipairs(group.rows) do
      if visible(row) then
        rows[#rows + 1] = {
          kind = "option",
          key = row.key,
          row = row,
          label = row.label or row.key,
          description = row.description or row.help,
        }
      end
    end
    -- Rows a feature keeps outside the option schema entirely.  Exp Share is
    -- the case: it stores its mode in the save's own options rather than in
    -- mod options, and drives them through cycle functions instead of a
    -- schema, so its adapter contributes rows in that shape instead.
    local custom = context.customRows and context.customRows[feature.id]
    if type(custom) == "function" then
      local ok, extra = pcall(custom)
      if ok and type(extra) == "table" then
        for _, entry in ipairs(extra) do
          local show = true
          if type(entry.visible) == "function" then
            local okVisible, visibleNow = pcall(entry.visible, game)
            show = okVisible and visibleNow ~= false
          end
          if show then
            rows[#rows + 1] = {
              kind = "custom",
              key = entry.id or entry.label,
              label = entry.label,
              description = entry.description,
              value = entry.value,
              step = entry.step,
            }
          end
        end
      end
    end

    if #rows > 0 then
      rows[#rows + 1] = {
        kind = "action",
        key = RESET_ROW,
        label = "RESET DEFAULTS",
        description = "PUTS EVERY ROW ON\nTHIS SCREEN BACK\fTO THE VALUE IT\nSHIPPED WITH.",
      }
    end
    return rows
  end

  -- ---- another mod's settings screen, from the schema the loader captured

  local function otherModRows(modId, game)
    local schema = Other.schema(game, modId)
    local rows = {}
    if not schema then return rows end

    local byKey = {}
    for _, row in ipairs(schema) do
      if type(row) == "table" and type(row.key) == "string" then byKey[row.key] = row end
    end
    local function shown(row)
      local condition = row.visible_if
      if condition == nil then return true end
      if type(condition) ~= "table" or type(condition.key) ~= "string" then
        return false
      end
      local dependency = byKey[condition.key] or { key = condition.key }
      local value = Other.read(game, modId, dependency)
      if condition.equals ~= nil then return value == condition.equals end
      if condition.not_equals ~= nil then return value ~= condition.not_equals end
      return false
    end

    for _, row in ipairs(schema) do
      if type(row) == "table" and type(row.key) == "string" and row.key ~= ""
          and OPTION_TYPES[row.type] and shown(row) then
        rows[#rows + 1] = {
          kind = "mod_option",
          modId = modId,
          key = row.key,
          row = row,
          label = row.label or row.key,
          description = row.description or row.help,
        }
      end
    end
    if #rows > 0 then
      rows[#rows + 1] = {
        kind = "action",
        key = RESET_ROW,
        label = "RESET DEFAULTS",
        description = "PUTS EVERY ROW ON\nTHIS SCREEN BACK\fTO THE VALUE IT\nSHIPPED WITH.",
      }
    end
    return rows
  end

  -- ---- the feature list, this bundle's and the other half's

  local function localEntries()
    local rows = {}
    for _, feature in ipairs(features) do
      local group = optionset.groups[feature.id]
      if group and group.masterKey then
        rows[#rows + 1] = {
          kind = "feature",
          id = feature.id,
          -- Restart-pending is tracked per bundle as well as per feature: the
          -- merged menu carries rows from both halves, and MENU LAYOUT is a
          -- row on both.
          tokenId = mod.id .. ":" .. feature.id,
          feature = feature,
          key = group.masterKey,
          row = optionset.byKey[group.masterKey],
          label = feature.label,
          description = feature.description,
          group = feature.group,
          screenId = featureScreenId(feature.id),
          liveToggle = feature.live_toggle == true,
          installed = feature.installed == true,
          -- A feature the other bundle installed has no settings rows here:
          -- its schema was never adopted, because it was never run. The
          -- switch is still real -- it is stored under a shared id, so it is
          -- the same switch the other bundle reads -- and that is what this
          -- row offers.
          deferredTo = context.deferred and context.deferred[feature.id],
          hasSettings = #(group.rows or {}) > 0
            or type(context.customRows and context.customRows[feature.id]) == "function",
        }
      end
    end
    return rows
  end

  local function siblingEntries()
    local other = sibling()
    if not other then return {} end
    local rows = {}
    for _, feature in ipairs(other.descriptor.features) do
      if type(feature) == "table" and type(feature.master_key) == "string" then
        rows[#rows + 1] = {
          kind = "feature",
          id = feature.id,
          tokenId = tostring(other.descriptor.bundle) .. ":" .. tostring(feature.id),
          bundle = other.exports,
          bundleId = other.descriptor.bundle,
          key = feature.master_key,
          row = feature.row,
          label = feature.label,
          description = feature.description,
          group = feature.group,
          screenId = feature.screen_id,
          liveToggle = feature.live_toggle == true,
          installed = feature.installed == true,
          hasSettings = feature.has_settings == true,
        }
      end
    end
    return rows
  end

  -- One list, deduplicated by feature id.  MENU LAYOUT and MOD MANAGER are in
  -- both halves and exactly one of them installs each (runtime/claims.lua), so
  -- both halves have a row for them and only one of those rows has the settings
  -- behind it.  The row that can configure wins; the other is the same switch
  -- either way, since a shared feature stores under a shared id.
  local function allEntries()
    local byId, order = {}, {}
    local function add(entry)
      local existing = byId[entry.id]
      if existing == nil then
        byId[entry.id] = entry
        order[#order + 1] = entry.id
      elseif existing.deferredTo and not entry.deferredTo then
        byId[entry.id] = entry
      end
    end
    for _, entry in ipairs(localEntries()) do add(entry) end
    for _, entry in ipairs(siblingEntries()) do add(entry) end
    local out = {}
    for _, id in ipairs(order) do out[#out + 1] = byId[id] end
    return out
  end

  -- ---- the cards

  -- A master that is one of its feature's own rows rather than a synthesized
  -- toggle -- the area banner's duration, the caught marker's style -- is off
  -- at whatever value its own schema spells OFF, not at `false`.
  local function entryOn(entry)
    local value = entryRead(entry)
    if value == false then return false end
    if entry.row and entry.row.type and entry.row.type ~= "toggle" then
      return labelForValue(entry.row, value) ~= "OFF"
    end
    return true
  end

  local function cardLabel(members)
    local on, total = 0, 0
    for _, member in ipairs(members) do
      total = total + 1
      if entryOn(member) then on = on + 1 end
    end
    if total == 0 then return "" end
    if on == 0 then return "ALL OFF" end
    if on == total then return ("ALL %d ON"):format(total) end
    return ("%d OF %d ON"):format(on, total)
  end

  local function groupMembers(groupId, entries)
    local out = {}
    for _, entry in ipairs(entries) do
      if entry.group == groupId then out[#out + 1] = entry end
    end
    return out
  end

  -- The ids the suite already speaks for, so the OTHER MODS card does not list
  -- this bundle, the other half, or anything either of them absorbed.
  local function suiteIds()
    local skip = { [mod.id] = true }
    -- an adopted mod has a card of its own; listing it again under OTHER
    -- MODS would be the same settings behind two different names
    for id in pairs(adoptedId) do skip[id] = true end
    if type(spec.paired_bundle) == "string" then skip[spec.paired_bundle] = true end
    local other = sibling()
    if other and type(other.descriptor.bundle) == "string" then
      skip[other.descriptor.bundle] = true
    end
    return skip
  end

  local function rootRows(game)
    local entries = allEntries()
    local rows = {}

    -- First, above the cards and above everything else.  These are the rows
    -- the cart is FOR -- the player's own colour before the dozen switches
    -- about how the menus behave -- so they open on the first line rather
    -- than after six folders and a list of other people's mods.
    for _, entry in ipairs(adopted) do
      if Other.schema(game, entry.mod) then
        rows[#rows + 1] = {
          kind = "mod",
          modId = entry.mod,
          key = entry.mod,
          label = entry.label or entry.mod,
          description = entry.description,
        }
      end
    end

    for _, group in ipairs(groups) do
      local members = groupMembers(group.id, entries)
      if #members > 0 then
        rows[#rows + 1] = {
          kind = "card",
          key = groupScreenId(group.id),
          screenId = groupScreenId(group.id),
          -- what the card IS, as declared in features.lua, kept beside the
          -- screen id it opens.  The id is a string this file built and is not
          -- meant to be taken apart again, so anything that wants to know what
          -- a card opens reads this rather than parsing the address.
          groupId = group.id,
          label = group.label or group.id,
          description = group.description,
          members = members,
        }
      end
    end

    -- Anything that named no card, or named one this bundle does not declare:
    -- a plain row on the top level rather than a feature the player cannot find.
    for _, entry in ipairs(entries) do
      if not (entry.group and declaredGroup[entry.group]) then
        rows[#rows + 1] = entry
      end
    end

    local others = Other.mods(game, suiteIds())
    if #others > 0 then
      rows[#rows + 1] = {
        kind = "card",
        key = OTHER_CARD,
        screenId = groupScreenId(OTHER_CARD),
        label = "OTHER MODS",
        description = "EVERY OTHER MOD THAT IS LOADED AND HAS SETTINGS OF ITS OWN.",
        mods = others,
      }
    end

    -- The mod manager itself, last.  This screen took the OPTION screen's
    -- MODS row and the START menu's MODS entry, because with the suite
    -- installed those are the door to the suite's settings rather than to a
    -- list of zips -- so the list of zips has to be here, or it is nowhere.
    -- One press further in, which is where somebody who came to enable and
    -- disable mods rather than to change a setting was heading anyway.
    rows[#rows + 1] = {
      kind = "manager",
      key = "__mod_manager",
      label = "MOD MANAGER",
      description = "TURN MODS ON AND OFF, AND IMPORT A MOD ZIP.",
    }

    return rows
  end

  local function cardRows(groupId, game)
    if groupId == OTHER_CARD then
      local rows = {}
      for _, entry in ipairs(Other.mods(game, suiteIds())) do
        rows[#rows + 1] = {
          kind = "mod",
          modId = entry.id,
          key = entry.id,
          label = entry.label,
          description = entry.description,
        }
      end
      return rows
    end
    return groupMembers(groupId, allEntries())
  end

  -- A feature whose master switch only gates installation cannot come to life
  -- mid-session, so saying ON when nothing is installed would be a lie.  It
  -- reads ON* until the game is relaunched, and the footer says why.
  local BUNDLE_NAMES = {
    gen1_wild_qol = "GEN1WILD QOL",
    gen1_wild_ui = "GEN1WILD UI",
    gen1_wild_ui = "GEN1WILD UI",
    gen1_wild_qol = "GEN1WILD QOL",
  }

  local function masterLabel(entry)
    local value = entryRead(entry)
    local on = value ~= false
    local pending = restartPending[entry.tokenId]

    if entry.deferredTo then
      return (on and "ON" or "OFF") .. " (SET UP IN "
        .. (BUNDLE_NAMES[entry.deferredTo] or "THE OTHER BUNDLE") .. ")"
    end

    -- A feature whose master is one of its own rows and is not a plain toggle
    -- -- the area banner's master is its duration -- says what it is set to
    -- rather than just ON, because the value is the interesting part.
    local base
    if entry.row and entry.row.type and entry.row.type ~= "toggle" then
      base = labelForValue(entry.row, value)
    elseif not on then
      base = "OFF"
    else
      base = entry.hasSettings and "ON (CONFIGURE)" or "ON"
    end

    if pending ~= nil and pending.was ~= on then return base .. " *" end
    return base
  end

  local function valueLabel(entry, game)
    if entry.kind == "feature" then return masterLabel(entry) end
    if entry.kind == "card" then
      if entry.mods then return ("%d MODS"):format(#entry.mods) end
      return cardLabel(entry.members or {})
    end
    if entry.kind == "mod" then return "CONFIGURE" end
    if entry.kind == "manager" then
      local loader = Other.loader(game)
      local ok, status = false, nil
      if loader and type(loader.status) == "function" then
        ok, status = pcall(loader.status, loader)
      end
      local n = (ok and type(status) == "table") and #(status.available or {}) or 0
      return ("%d INSTALLED"):format(n)
    end
    if entry.kind == "action" then return "" end
    if entry.kind == "mod_option" then
      return labelForValue(entry.row, Other.read(game, entry.modId, entry.row))
    end
    if entry.kind == "custom" then
      if type(entry.value) ~= "function" then return "" end
      local ok, label = pcall(entry.value, game)
      return ok and tostring(label or "") or ""
    end
    return labelForValue(entry.row, read(entry.key))
  end

  -- ---- screen factory, shared by every screen here

  local function makeScreen(screenId, buildRows)
    return function(game, opts)
      local screen = {
        screenId = screenId,
        game = game,
        entries = buildRows(game, opts),
        index = 1,
        scroll = 0,
        isOpaque = true,
        isModOptions = true,
        -- One of ours.  runtime/theme.lua reads this off the instance: a
        -- screen that names itself does not have to be recognised by its
        -- class, and these screens have no engine class to be recognised by.
        --
        -- It also opts the page into being themed at all.  The theme's rule
        -- is "a whole-screen zone of the four DMG greys is a black-and-white
        -- page"; this one opens on MEWMON instead, deliberately, and would be
        -- the one screen in the suite a dark mode did not reach.
        gen1wildTheme = "settings",
      }

      screen.rows = screen.entries

      -- What this screen would print in the value column for a row.  The draw
      -- path is the only other reader, and it needs love; a test that wants to
      -- know whether a card says ALL 4 ON does not.
      function screen:valueOf(entry)
        return valueLabel(entry, self.game)
      end

      -- Rows are rebuilt every frame rather than once on push, because a row
      -- can govern whether its neighbours are drawn at all: Gen151's CABLE
      -- SOUND belongs to TRADE EVOS on the same screen, and Exp Share's
      -- PERCENT rows exist only in CUSTOM.  Turning the governing row has to
      -- take the others with it on the next frame, not on the next visit.
      local function refresh(s)
        s.entries = buildRows(s.game, opts)
        s.rows = s.entries
        if #s.entries == 0 then return false end
        if s.index > #s.entries then s.index = #s.entries end
        if s.index < 1 then s.index = 1 end
        return true
      end

      function screen:sgbPalettes(g)
        local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
        if ok and PaletteFX and PaletteFX.wholeNamed then
          return PaletteFX.wholeNamed(g.data, "MEWMON")
        end
        return nil
      end

      local function activate(entry)
        if entry.kind == "card" then
          mod.ui.push(screen.game, entry.screenId)
        elseif entry.kind == "mod" then
          mod.ui.push(screen.game, otherModScreenId, { modId = entry.modId })
        elseif entry.kind == "manager" then
          mod.ui.push(screen.game, "ManagerState")
        elseif entry.kind == "feature" then
          if entry.deferredTo then
            local where = BUNDLE_NAMES[entry.deferredTo] or "THE OTHER BUNDLE"
            self.showText(screen.game,
              entry.label .. " IS INSTALLED BY " .. where
              .. ", WHICH IS ALSO INSTALLED. ITS SETTINGS ARE THERE. THE "
              .. "SWITCH ON THIS ROW IS THE SAME SWITCH.")
          elseif not (entry.hasSettings and entry.screenId) then
            self.showText(screen.game, entry.description)
          elseif entryRead(entry) ~= false then
            mod.ui.push(screen.game, entry.screenId)
          else
            self.showText(screen.game,
              "SWITCH " .. entry.label .. " ON\nTO CONFIGURE IT.")
          end
        elseif entry.kind == "action" and entry.key == RESET_ROW then
          for _, other in ipairs(screen.entries) do
            if other.kind == "option" then
              write(screen.game, other.key, other.row.default)
            elseif other.kind == "mod_option" then
              Other.write(screen.game, other.modId, other.key, other.row.default)
            end
          end
          -- Custom rows are deliberately left alone: their storage is not
          -- this bundle's to reset.
        else
          self.showText(screen.game, entry.description or entry.label)
        end
      end

      local function step(entry, dir)
        if entry.kind == "action" or entry.kind == "card"
            or entry.kind == "mod" or entry.kind == "manager" then
          return
        end
        if entry.kind == "custom" then
          if type(entry.step) == "function" then
            pcall(entry.step, screen.game, dir)
          end
          return
        end
        if entry.kind == "mod_option" then
          local current = Other.read(screen.game, entry.modId, entry.row)
          Other.write(screen.game, entry.modId, entry.key,
            stepValue(entry.row, current, dir))
          return
        end
        if entry.kind == "feature" then
          local current = entryRead(entry)
          -- Record the state the feature was actually installed in the first
          -- time its switch is moved, so the footer can say whether the
          -- session matches the setting.
          if restartPending[entry.tokenId] == nil and not entry.liveToggle then
            restartPending[entry.tokenId] = {
              was = entry.installed == true,
              key = entry.key,
              bundle = entry.bundle,
            }
          end
          entryWrite(screen.game, entry, stepValue(entry.row, current, dir))
          return
        end
        local current = read(entry.key)
        write(screen.game, entry.key, stepValue(entry.row, current, dir))
      end

      function screen:update()
        if not refresh(self) then self.game.stack:pop() return end
        local input = self.game.input
        local entry = self.entries[self.index]
        if not entry then self.game.stack:pop() return end

        if input:wasPressed("up") then
          self.index = (self.index - 2) % #self.entries + 1
        elseif input:wasPressed("down") then
          self.index = self.index % #self.entries + 1
        elseif input:wasPressed("left") then
          step(entry, -1)
        elseif input:wasPressed("right") then
          step(entry, 1)
        elseif input:wasPressed("a") then
          activate(entry)
        elseif input:wasPressed("b") then
          self.game.stack:pop()
        end

        if context.isGen2 then
          if self.index <= self.scroll then
            self.scroll = self.index - 1
          elseif self.index > self.scroll + GEN2_VISIBLE_ROWS then
            self.scroll = self.index - GEN2_VISIBLE_ROWS
          end
          self.scroll = math.max(0, math.min(self.scroll,
            math.max(0, #self.entries - GEN2_VISIBLE_ROWS)))
        else
          local ok, OptionRows = pcall(require, "src.ui.OptionRows")
          if ok and OptionRows and OptionRows.clampScroll then
            self.scroll = OptionRows.clampScroll(
              self.index, self.scroll, #self.entries, nil)
          end
        end
      end

      -- The engine's OptionRows wants rows carrying a `value(game)`; build that
      -- view fresh each frame so a row reflects a write made on this one.
      local function drawable()
        local out = {}
        for i, entry in ipairs(screen.entries) do
          out[i] = {
            id = entry.key,
            label = entry.label,
            key = entry.key,
            value = function() return valueLabel(entry, screen.game) end,
          }
        end
        return out
      end

      local function footerFor(entry)
        if not entry then return "B:BACK" end
        if entry.kind == "card" or entry.kind == "mod"
            or entry.kind == "manager" then
          return "A:OPEN B:BACK"
        end
        if entry.kind == "feature" then
          if entry.deferredTo then return "A:INFO B:BACK" end
          if entryRead(entry) ~= false and entry.hasSettings and entry.screenId then
            return "A:CONFIGURE B:BACK"
          end
          return "A:INFO B:BACK"
        end
        if entry.kind == "action" then return "A:RESET B:BACK" end
        return "A:INFO B:BACK"
      end

      local function anyRestartPending()
        for _, pending in pairs(restartPending) do
          local value
          if pending.bundle then
            local ok, got = pcall(pending.bundle.optionValue, pending.key)
            value = ok and got or nil
          else
            value = read(pending.key)
          end
          if (value ~= false) ~= pending.was then return true end
        end
        return false
      end

      local function drawGen1(s)
        local OptionRows = require("src.ui.OptionRows")
        local Font = require("src.render.Font")
        OptionRows.draw(s.game, drawable(), s.index, s.scroll)
        love.graphics.setColor(0, 0, 0, 1)
        local footer = anyRestartPending() and "* RESTART TO APPLY"
          or footerFor(s.entries[s.index])
        Font.draw(footer, 8, 136)
        love.graphics.setColor(1, 1, 1, 1)
      end

      local function drawGen2(s)
        local Chrome = require("src.ui.gen2.Chrome")
        Chrome.textbox(0, 0, Chrome.SCREEN_W - 2, Chrome.SCREEN_H - 2)
        local rows = drawable()
        for slot = 1, math.min(GEN2_VISIBLE_ROWS, #rows) do
          local i = slot + s.scroll
          local row = rows[i]
          if row then
            local labelY = 2 + (slot - 1) * 2
            Chrome.print(row.label, 2, labelY)
            Chrome.print(":", GEN2_VALUE_TX - 1, labelY + 1)
            Chrome.print(row.value() or "", GEN2_VALUE_TX, labelY + 1)
          end
        end
        Chrome.cursor(1, 2 + (s.index - s.scroll - 1) * 2)
        if s.scroll + GEN2_VISIBLE_ROWS < #rows then
          local Font = require("src.render.Font")
          love.graphics.setColor(0, 0, 0, 1)
          Font.drawCode(Chrome.DOWN_ARROW, 8, (2 + GEN2_VISIBLE_ROWS * 2 - 1) * 8)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end

      screen.draw = context.isGen2 and drawGen2 or drawGen1
      return screen
    end
  end

  function self.showText(game, text)
    if not (mod.ui and mod.ui.TextBox) then return end
    game.stack:push(mod.ui.TextBox.new(game, asTextBox(text)))
  end

  -- ---- what the other half renders this bundle's features from

  function self.descriptor()
    local out = {
      bundle = mod.id,
      label = spec.menu_label,
      screen_id = rootScreenId,
      features = {},
    }
    for _, feature in ipairs(features) do
      local group = optionset.groups[feature.id]
      -- A feature this bundle stood down from is the other half's to render:
      -- it is that half that installed it and that half that has its rows.
      local handedOver = context.deferred and context.deferred[feature.id]
      if group and group.masterKey and not handedOver then
        out.features[#out.features + 1] = {
          id = feature.id,
          label = feature.label,
          description = feature.description,
          group = feature.group,
          master_key = group.masterKey,
          row = optionset.byKey[group.masterKey],
          screen_id = featureScreenId(feature.id),
          has_settings = #(group.rows or {}) > 0
            or type(context.customRows and context.customRows[feature.id]) == "function",
          live_toggle = feature.live_toggle == true,
          installed = feature.installed == true,
        }
      end
    end
    return out
  end

  -- ---- registration

  function self.install()
    mod.content.screens:register(rootScreenId, {
      new = makeScreen(rootScreenId, rootRows),
      isModOptions = true,
    })
    for _, group in ipairs(groups) do
      local id = groupScreenId(group.id)
      mod.content.screens:register(id, {
        new = makeScreen(id, function(game) return cardRows(group.id, game) end),
        isModOptions = true,
      })
    end
    mod.content.screens:register(groupScreenId(OTHER_CARD), {
      new = makeScreen(groupScreenId(OTHER_CARD),
        function(game) return cardRows(OTHER_CARD, game) end),
      isModOptions = true,
    })
    for _, feature in ipairs(features) do
      local id = featureScreenId(feature.id)
      mod.content.screens:register(id, {
        new = makeScreen(id, function(game) return featureRows(feature, game) end),
        isModOptions = true,
      })
    end
    -- One screen for every other mod, because which mods those are is not
    -- known until a game is running.  Which one it is showing is a push
    -- argument, so two of them can be open at once without sharing state.
    mod.content.screens:register(otherModScreenId, {
      new = makeScreen(otherModScreenId, function(game, opts)
        local modId = type(opts) == "table" and opts.modId or nil
        if type(modId) ~= "string" then return {} end
        return otherModRows(modId, game)
      end),
      isModOptions = true,
    })

    -- ---- the door
    --
    -- One row on the game's own OPTION screen.  The bundle used to put none
    -- there on the grounds that a mod's settings belong under MODS, and that
    -- was right for a mod and wrong for this: a player looking for the run
    -- button looks in OPTIONS, and MODS > GEN1WILD QOL > OPTIONS is three
    -- screens and a guess about which half owns it.  So the whole suite hangs
    -- off one row here, and the MODS route below still lands on the same
    -- screens for anyone who goes that way.
    --
    -- The row is named after the cart when a cart is running -- WILD GREEN is
    -- what the player installed and what the launcher calls it -- and after
    -- this bundle when one half is installed on its own, where calling it
    -- WILD GREEN would be naming something that is not there.
    local function doorLabel(game)
      local loader = Other.loader(game)
      local report = loader and type(loader.cartStatus) == "function"
        and select(2, pcall(loader.cartStatus, loader)) or nil
      if type(report) == "table" and report.pins and report.pins[mod.id] then
        local title = asMenuLabel(report.title, nil)
        if title and title ~= "" then return title end
      end
      return spec.menu_label
    end

    -- ---- and the theme
    --
    -- A row of its own on the game's own OPTION screen rather than a row
    -- inside the suite's menu, because that is where it was asked for and
    -- where it belongs: START > OPTION > UI THEME is one press further than
    -- the brightness slider on any device made this century, and a player
    -- looking for a dark mode looks in OPTIONS.  It is also the one setting
    -- in the suite that is not about a feature -- turning it off does not
    -- turn anything off -- so it has no card to sit under.
    --
    -- It cycles LIGHT / DARK like every other value row on that screen, and
    -- takes effect on the next frame: the theme is read by the render hook
    -- rather than settled at load.
    local function themeRow()
      local theme = context.theme
      if not theme then return nil end
      return {
        id = THEME_ROW_ID,
        label = "UI THEME",
        value = function() return theme.label() end,
        step = function(g, dir)
          theme.step(dir or 1, g)
          return true
        end,
      }
    end

    mod.hooks:wrap("ui.options.rows", function(nextLink, game, rows)
      local out = nextLink(game, rows)
      if type(out) ~= "table" then return out end

      -- The theme row goes in first and is answered separately from the door
      -- below: either half of the suite may already have added one, and the
      -- door's own dedupe below returns early, which would leave the theme
      -- unadded on the half that lost that race.
      local haveTheme = false
      for _, existing in ipairs(out) do
        if existing.id == THEME_ROW_ID then haveTheme = true end
      end
      if not haveTheme then
        local row = themeRow()
        if row then out[#out + 1] = row end
      end

      -- The other half may have got here first: one door, not two.
      for _, existing in ipairs(out) do
        if existing.id == OPTION_ROW_ID then return out end
      end
      local row = {
        id = OPTION_ROW_ID,
        label = doorLabel(game),
        -- `group` is what the engine's own OPTION screen marks a folder card
        -- with, and this is one: it opens onto rows rather than cycling.
        group = true,
        value = function()
          local count = #allEntries()
          for _ in ipairs(Other.mods(game, suiteIds())) do count = count + 1 end
          return ("%d MODS"):format(count)
        end,
        activate = function(g) mod.ui.push(g, rootScreenId) end,
      }
      -- IN PLACE OF MODS, not beside it.  MODS is where a player looking for
      -- mod settings goes, and with this suite installed almost everything
      -- they will find there is this suite's -- so the row that says MODS and
      -- opens a manager is the wrong answer to the question they are asking.
      -- This one is the right answer, and it takes that slot.
      --
      -- The manager is not lost.  It is a row of its own on the screen below
      -- (see managerRow), which is one press further in and where somebody
      -- who actually wants to enable and disable mods is going anyway.
      --
      -- Appended if some other mod already took the MODS row away, so nothing
      -- here can orphan the entry.
      local at = #out + 1
      for i, existing in ipairs(out) do
        if existing.id == "mods" then
          at = i
          table.remove(out, i)
          break
        end
      end
      table.insert(out, at, row)
      return out
    end)

    -- And the START menu's MODS entry, for the same reason: with the suite
    -- installed, that is the door to the suite's settings and not to a list
    -- of zips.  Retargeted rather than removed -- the entry keeps its name
    -- and its place, it just arrives somewhere more useful.
    mod.hooks:wrap("ui.start_menu.items", function(nextLink, game, items)
      local out = nextLink(game, items)
      if type(out) ~= "table" then return out end
      for _, item in ipairs(out) do
        -- By id where the engine gives one, by label otherwise: another mod
        -- may have rebuilt the entry, and MODS is what it reads either way.
        -- The flag is what keeps the other half of the suite from routing an
        -- entry this half already routed.
        local isMods = item and not item.__gen1wildRouted
          and (item.id == "mods"
               or (type(item.label) == "string" and item.label:upper() == "MODS"))
        if isMods then
          item.__gen1wildRouted = true
          item.onSelect = function() mod.ui.push(game, rootScreenId) end
          break
        end
      end
      return out
    end)

    -- MODS > <bundle> > OPTIONS should land on these screens rather than on
    -- the manager's generic schema list, which would show all sixty rows flat
    -- with no idea which feature owns which.
    mod.events:once("mods.loaded", function()
      local ok, ManagerState = pcall(require, "src.mods.ManagerState")
      if not ok or type(ManagerState) ~= "table" then return end
      local routes = rawget(ManagerState, "__modOptionScreenRoutes")
      if not routes then
        routes = {}
        local openOptions = ManagerState.openOptions
        ManagerState.openOptions = function(state, manifest)
          local screenId = manifest and routes[manifest.id]
          if screenId then
            return require("src.ui.Screens").push(state.game, screenId)
          end
          return openOptions(state, manifest)
        end
        ManagerState.__modOptionScreenRoutes = routes
      end
      routes[mod.id] = rootScreenId
    end)
  end

  -- Called by the bundle once each feature has been installed (or skipped), so
  -- the menu can tell a switch that needs a relaunch from one that does not.
  function self.noteInstalled(feature, installed)
    feature.installed = installed
    -- A feature the other bundle owns is not pending anything here: this
    -- bundle was never going to install it, so an asterisk would be
    -- describing a relaunch that changes nothing on this side.
    if context.deferred and context.deferred[feature.id] then return end
    if not feature.live_toggle then
      local group = optionset.groups[feature.id]
      if group and group.masterKey then
        restartPending[mod.id .. ":" .. feature.id] = {
          was = installed,
          key = group.masterKey,
        }
      end
    end
  end

  return self
end

return Menu
