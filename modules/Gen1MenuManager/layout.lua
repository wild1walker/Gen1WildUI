-- The layout model: how a START menu row is named, how a saved order is
-- applied to a live row list, and how the whole thing survives a round trip
-- through mod.save (a table) and mod.cache (bytes).
--
-- Row identity is the hard problem here.  The engine's rows carry a label and
-- nothing else (src/ui/StartMenu.lua builds bare { label, onSelect, keepOpen }
-- descriptors), so the label IS the handle -- except for the trainer-card row,
-- whose label is the player's name and therefore differs per save.  That one
-- is matched against save.player.name and keyed "@PLAYER" instead.
--
-- Consequence worth knowing: labels come from Strings(), so a translation mod
-- changes them.  A stale key then matches nothing, its row falls into the
-- unplaced tail, and the menu renders in engine order.  That is the intended
-- degrade -- never a missing row.

local M = {}

M.VERSION = 1
M.PLAYER = "@PLAYER"
M.PLAYER_PC = "@PLAYERPC"
M.MANAGER = "@MANAGER"
M.PIN_PREFIX = "P:"
M.LABEL_PREFIX = "L:"

-- Hiding is guarded by a caller-supplied protected set rather than a constant
-- here, because what must survive depends on what other routes exist: with
-- the SELECT shortcut on, the manager row is ordinary and can be hidden; with
-- it off, the row IS the route and has to stay.  main.lua decides.
M.PROTECTED = {}

function M.isPin(key)
  return type(key) == "string" and key:sub(1, #M.PIN_PREFIX) == M.PIN_PREFIX
end

function M.pinKey(id) return M.PIN_PREFIX .. id end

function M.pinId(key)
  if not M.isPin(key) then return nil end
  return key:sub(#M.PIN_PREFIX + 1)
end

function M.empty()
  return { v = M.VERSION, order = {}, hidden = {}, pins = {} }
end

-- Tolerant of anything mod.save hands back: a missing table, a table from a
-- future version, a half-written one.  Never raises, always returns a layout.
function M.normalize(raw)
  local out = M.empty()
  if type(raw) ~= "table" then return out end
  if type(raw.order) == "table" then
    local seen = {}
    for _, key in ipairs(raw.order) do
      if type(key) == "string" and key ~= "" and not seen[key] then
        seen[key] = true
        out.order[#out.order + 1] = key
      end
    end
  end
  if type(raw.hidden) == "table" then
    for key, on in pairs(raw.hidden) do
      if type(key) == "string" and on then out.hidden[key] = true end
    end
  end
  if type(raw.pins) == "table" then
    for key, on in pairs(raw.pins) do
      if type(key) == "string" and on then out.pins[key] = true end
    end
  end
  return out
end

-- The key for one live row.  `index` disambiguates two rows that share a
-- label (two mods can both append "QUESTS"): the first keeps the bare key,
-- later ones get a "#n" suffix, assigned in list order so the mapping is
-- stable as long as the row set is.
local function keyForLabel(label, taken)
  local base = M.LABEL_PREFIX .. tostring(label)
  if not taken[base] then
    taken[base] = 1
    return base
  end
  taken[base] = taken[base] + 1
  return base .. "#" .. taken[base]
end

-- Parallel array of keys for a live row list.
function M.keysFor(items, playerName)
  local keys, taken = {}, {}
  local usedPlayer, usedPlayerPc = false, false
  for i, item in ipairs(items) do
    local label = item.label
    if type(item.mmKey) == "string" and item.mmKey ~= "" then
      -- Rows this mod synthesizes carry their own key, which is why a pin's
      -- identity survives a translation mod renaming its label.
      keys[i] = item.mmKey
    elseif type(item.id) == "string" and item.id ~= "" then
      -- Gold's PC rows carry a stable id beside the label
      -- (src/ui/gen2/ItemPcMenu.lua ENTRIES), which beats a label on every
      -- count: it is neither localized nor rewritten mid-playthrough.
      keys[i] = "I:" .. item.id
    elseif not usedPlayer and playerName and playerName ~= ""
        and label == playerName then
      -- the START menu's trainer-card row
      usedPlayer = true
      keys[i] = M.PLAYER
    elseif not usedPlayerPc and playerName and playerName ~= ""
        and type(label) == "string"
        and label:sub(1, #playerName) == playerName
        and label:sub(#playerName + 1):upper() == "'S PC" then
      -- the PC menu's own item-storage row, labelled "<name>'s PC"
      usedPlayerPc = true
      keys[i] = M.PLAYER_PC
    else
      keys[i] = keyForLabel(label, taken)
    end
  end
  return keys
end

-- Apply a layout to a live row list.
--
--   1. every live row is keyed
--   2. rows named by layout.order are emitted in that order
--   3. rows the order never mentions -- a mod installed since the layout was
--      written, a row that only appears with a full party -- are appended in
--      engine order, so a new row is always reachable
--   4. hidden rows are dropped, except protected ones and except when
--      dropping would leave nothing
--
-- Returns the new list plus a snapshot (key -> label, in display order) the
-- editor screen reads so it never has to rebuild the menu itself.
function M.apply(items, layout, playerName, protected)
  protected = protected or M.PROTECTED
  local keys = M.keysFor(items, playerName)
  local byKey, order = {}, {}
  for i, item in ipairs(items) do
    byKey[keys[i]] = item
    order[#order + 1] = keys[i]
  end

  local out, emitted = {}, {}
  local function emit(key)
    local item = byKey[key]
    if not item or emitted[key] then return end
    emitted[key] = true
    if layout.hidden[key] and not protected[key] then return end
    out[#out + 1] = item
  end

  for _, key in ipairs(layout.order) do emit(key) end
  for _, key in ipairs(order) do emit(key) end

  -- A menu with no rows cannot be escaped by any means the player has, so an
  -- over-eager hide set degrades to "nothing hidden" rather than a soft-lock.
  -- The PC needs this least -- the engine appends LOG OFF after the hook, so
  -- its exit is never ours to lose -- and the START menu needs it most.
  if #out == 0 then
    for _, key in ipairs(order) do out[#out + 1] = byKey[key] end
  end

  local snapshot = {}
  for _, key in ipairs(layout.order) do
    if byKey[key] then
      snapshot[#snapshot + 1] = { key = key, label = byKey[key].label }
    end
  end
  local inSnapshot = {}
  for _, row in ipairs(snapshot) do inSnapshot[row.key] = true end
  for _, key in ipairs(order) do
    if not inSnapshot[key] then
      snapshot[#snapshot + 1] = { key = key, label = byKey[key].label }
    end
  end

  return out, snapshot
end

-- Rewrite layout.order so it matches the order the player just arranged.
-- Keys the editor did not show (a row from a save the player is not in) keep
-- their relative position at the end rather than being dropped.
function M.reorder(layout, keys)
  local known = {}
  for _, key in ipairs(keys) do known[key] = true end
  local order = {}
  for _, key in ipairs(keys) do order[#order + 1] = key end
  for _, key in ipairs(layout.order) do
    if not known[key] then order[#order + 1] = key end
  end
  layout.order = order
  return layout
end

-- ------- the cache template
--
-- mod.save is per playthrough (Concepts: Save Model), which is right for the
-- truth but wrong for a preference: nobody wants to rebuild their menu on
-- every new file.  So the same layout is also written to mod.cache, which is
-- installation-scoped, and a save with no layout of its own seeds from it.
-- The save always wins once it exists.
--
-- Line format, because mod.cache takes bytes and the serializer is engine
-- private.  Keys and labels can contain anything except a newline.

local function sortedKeys(set)
  local keys = {}
  for key in pairs(set) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

function M.encode(layout)
  -- The O block is an ordered list and must not be sorted (table.sort is not
  -- stable, so "compare equal" would still permute it).  Only the two SETS
  -- are sorted, and only so the bytes are deterministic across writes.
  local lines = { "Gen1MenuManager " .. M.VERSION }
  for _, key in ipairs(layout.order) do lines[#lines + 1] = "O" .. key end
  for _, key in ipairs(sortedKeys(layout.hidden)) do
    lines[#lines + 1] = "H" .. key
  end
  for _, key in ipairs(sortedKeys(layout.pins)) do
    lines[#lines + 1] = "P" .. key
  end
  return table.concat(lines, "\n")
end

function M.decode(bytes)
  if type(bytes) ~= "string" then return nil end
  local out = M.empty()
  local first = true
  for line in bytes:gmatch("[^\n]+") do
    if first then
      first = false
      if not line:match("^Gen1MenuManager ") then return nil end
    else
      local tag, key = line:sub(1, 1), line:sub(2)
      if key ~= "" then
        if tag == "O" then out.order[#out.order + 1] = key
        elseif tag == "H" then out.hidden[key] = true
        elseif tag == "P" then out.pins[key] = true end
      end
    end
  end
  return M.normalize(out)
end

return M
