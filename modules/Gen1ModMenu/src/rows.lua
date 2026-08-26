-- The list model, kept free of love and of the engine so the suite can drive
-- it directly.  Nothing here draws: it turns the manager's own mod records
-- into the ordered, filtered, labelled rows the renderer walks, in exactly
-- the shape ManagerState:modRows returns -- `{ header = true, label }` for a
-- group heading and `{ mod, label, glyph, state }` for a mod -- because the
-- cursor, the scroll clamp and activate() all read that shape and none of
-- them are ours to change.

local Rows = {}

-- Four glyphs is what the right-hand column can spend: the interior is 18
-- tiles, the cursor owns one and a mod name wants the rest.  These are also
-- the whole vocabulary the status column has, so every one of them is
-- spelled out in the legend on the ERRORS tab.
-- The whole vocabulary the status column has.  Each one is spelled out in
-- words on the mod's own detail screen, which is one A-press from the list;
-- 0.2.0 through 0.3.1 also listed them on the ERRORS tab, which turned a tab
-- named for errors into two screens of jargon once it drew in cards.
Rows.STATES = { "ON", "OFF", "STGD", "ERR", "BLKD", "SKIP" }

-- The same order of precedence ManagerState:glyphFor uses, so the column and
-- the engine's own gutter glyph can never disagree about a mod.  `flags` is
-- what the caller read off the instance: staged and skipped need methods
-- (isStaged, runsHere) that only the live screen has.
function Rows.stateOf(flags)
  flags = flags or {}
  if flags.staged then return "STGD" end
  if not flags.enabled then return "OFF" end
  if flags.skipped then return "SKIP" end
  if flags.blocked then return "BLKD" end
  if flags.errored then return "ERR" end
  return "ON"
end

-- The gutter glyph ManagerState:glyphFor would have produced for the same
-- mod.  Carried on every row so a fall back to the engine's own drawRows --
-- the VANILLA presentation, or a renderer that threw -- still marks the
-- rows it draws.
local GLYPH = { STGD = ".", OFF = "-", ERR = "!", BLKD = "?", SKIP = "-",
                ON = " " }

function Rows.glyphOf(state)
  return GLYPH[state] or " "
end

local ORDER = { ERR = 1, BLKD = 2, STGD = 3, OFF = 4, SKIP = 5, ON = 6 }

-- Case-insensitive by name, then by id.  The id tie-break is not decoration:
-- two mods can ship the same display name, and a sort that leaves them in an
-- arbitrary order moves rows under the player's cursor between refreshes.
local function byName(a, b)
  local an, bn = (a.name or ""):upper(), (b.name or ""):upper()
  if an ~= bn then return an < bn end
  return tostring(a.id) < tostring(b.id)
end

-- `flat` drops the heading rows and keeps the grouping as an ORDER instead.
-- The card layout has no cheap way to draw a heading -- a heading would cost
-- a whole card, and four cards are the whole screen -- so with cards the
-- category rides on the card's second line beside the status instead.
local function grouped(entries, groupOf, order, flat)
  local buckets, names = {}, {}
  for _, entry in ipairs(entries) do
    local name = groupOf(entry)
    if not buckets[name] then
      buckets[name] = {}
      names[#names + 1] = name
    end
    buckets[name][#buckets[name] + 1] = entry
  end
  if order then
    table.sort(names, function(a, b)
      local ra, rb = order[a] or math.huge, order[b] or math.huge
      if ra ~= rb then return ra < rb end
      return a < b
    end)
  else
    table.sort(names)
  end
  local rows = {}
  for _, name in ipairs(names) do
    local bucket = buckets[name]
    table.sort(bucket, byName)
    if not flat then rows[#rows + 1] = { header = true, label = name } end
    for _, entry in ipairs(bucket) do
      rows[#rows + 1] = { mod = entry.mod, label = entry.name or entry.id,
                          state = entry.state, category = entry.category,
                          glyph = Rows.glyphOf(entry.state) }
    end
  end
  return rows
end

local SORTS = {}

-- What the engine does, plus a stable order inside each category.  Vanilla
-- groups by category but leaves the mods in load order, so the same install
-- lists them differently after a priority change.
SORTS.category = function(entries, flat)
  return grouped(entries, function(e) return e.category or "OTHER" end, nil, flat)
end

SORTS.name = function(entries)
  local sorted = {}
  for i, entry in ipairs(entries) do sorted[i] = entry end
  table.sort(sorted, byName)
  local rows = {}
  for _, entry in ipairs(sorted) do
    rows[#rows + 1] = { mod = entry.mod, label = entry.name or entry.id,
                        state = entry.state, category = entry.category,
                        glyph = Rows.glyphOf(entry.state) }
  end
  return rows
end

SORTS.enabled = function(entries, flat)
  return grouped(entries, function(e)
    return e.state == "OFF" and "DISABLED" or "ENABLED"
  end, { ENABLED = 1, DISABLED = 2 }, flat)
end

-- Anything that wants the player's attention, first.  STGD is a problem in
-- the same sense: it is a change that has not taken effect yet.
SORTS.status = function(entries, flat)
  return grouped(entries, function(e)
    if e.state == "ERR" or e.state == "BLKD" then return "PROBLEMS" end
    if e.state == "STGD" then return "STAGED" end
    if e.state == "OFF" then return "DISABLED" end
    if e.state == "SKIP" then return "OTHER GAME" end
    return "RUNNING"
  end, { PROBLEMS = 1, STAGED = 2, RUNNING = 3, DISABLED = 4,
         ["OTHER GAME"] = 5 }, flat)
end

function Rows.sortNames()
  local names = {}
  for name in pairs(SORTS) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- `keep` is the one id a filter may never remove.  Both filters are set from
-- rows on this mod's own OPTIONS page, and that page is reached through the
-- list they filter: a filter that could hide Gen1ModMenu would be a filter
-- the player cannot undo.  Neither shipped filter can hide it on its own --
-- it is enabled, and it has options -- but the guarantee belongs in the code
-- rather than in the coincidence.
function Rows.arrange(entries, prefs, keep)
  prefs = prefs or {}
  local installed = #entries

  local kept = {}
  for _, entry in ipairs(entries) do
    local survives = true
    if entry.id ~= keep then
      if prefs.hide_disabled and entry.state == "OFF" then survives = false end
      if prefs.only_options and not entry.hasOptions then survives = false end
    end
    if survives then kept[#kept + 1] = entry end
  end

  if #kept == 0 then
    -- Inert rather than a heading when flat: with nothing to skip to,
    -- moveCursor would leave the cursor on a heading anyway, and activate()
    -- refuses an inert row just as firmly.
    local label = installed == 0 and "NO MODS INSTALLED" or "NO MODS MATCH"
    if prefs.flat then return { { inert = true, label = label } } end
    return { { header = true, label = label } }
  end

  local sort = SORTS[prefs.sort] or SORTS.category
  return sort(kept, prefs.flat)
end

-- ------- the per-mod options page

-- The engine's option schema carries no description field
-- (docs/mod-option-schema.md: key, type, label, default, choices, min, max,
-- step, maxLen, visible_if), so the help line says what the row will DO
-- rather than inventing prose the author never wrote.  Every one of these is
-- read straight off the row.
function Rows.helpFor(row)
  if type(row) ~= "table" then return nil end
  if row.type == "toggle" then return "ON / OFF" end
  if row.type == "choice" then
    local labels = {}
    for _, choice in ipairs(row.choices or {}) do
      labels[#labels + 1] = tostring(choice[1])
    end
    if #labels == 0 then return nil end
    return table.concat(labels, " / ")
  end
  if row.type == "number" then
    local low, high = row.min, row.max
    if low and high then
      local text = tostring(low) .. "-" .. tostring(high)
      if row.step and row.step ~= 1 then
        text = text .. " BY " .. tostring(row.step)
      end
      return text
    end
    return "NUMBER"
  end
  if row.type == "text" then
    if row.maxLen then return "UP TO " .. tostring(row.maxLen) .. " CHARS" end
    return "TEXT"
  end
  return nil
end

-- Whether a stored value still matches what the author shipped.  Only the
-- four renderable types reach here, so an equality test is the whole job --
-- but nil has to answer "unchanged" rather than "changed", because a row the
-- player has never touched stores nothing at all.
function Rows.changed(value, default)
  if value == nil then return false end
  return value ~= default
end

return Rows
