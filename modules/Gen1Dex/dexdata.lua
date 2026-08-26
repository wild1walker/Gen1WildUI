-- Gen1Dex: everything the two screens need to KNOW, with nothing they need
-- to DRAW.
--
-- No require, no love, no engine module: this file is a pure function of the
-- merged dataset and the save, which is what lets the suite drive it against
-- hand-built tables and assert on the answer instead of on a screenshot.
-- main.lua publishes all five builders on mod.exports for exactly that.
--
-- The screens hold no derived state of their own -- every page rebuilds from
-- here on the frame it is opened -- so a mod that registers a species, a
-- move, a machine or an evolution method after this one still shows up.

local DexData = {}

-- ------- the movelist
--
-- Two sections, in the order the printed dex prints them: what the species
-- learns by growing up, then what you can teach it.
--
-- `learned` is the species' learnset in ROM order, deduped by move: a Gen 1
-- learnset can name the same move at two levels (the level-1 block and the
-- level-up block both carry it) and printing it twice reads as a bug.  The
-- FIRST entry wins, which is the lower level, which is the one that is true.
--
-- `machines` is the tmhm list resolved through the ITEMS registry rather than
-- through a hard-coded TM table, because the machine number is a property of
-- the item, not of the move: a mod that adds TM51 adds an item whose
-- `machine` field claims a number, and this finds it with no help.  Sorted
-- TM01..TMnn then HM01..HMnn, because that is how the bag sorts them.
--
-- `stab` is carried per move so the screen can mark same-type moves without
-- re-deriving it; a screen that had to look up the type chart to draw a row
-- would be doing data work in a draw call.
local function typeOf(data, moveId)
  local mdef = data.moves and data.moves[moveId]
  if not mdef then return nil, nil end
  return (mdef.type or mdef.typeId), mdef.name
end

local function isStab(def, moveType)
  if not moveType then return false end
  for _, speciesType in ipairs(def.types or {}) do
    if speciesType == moveType then return true end
  end
  return false
end

function DexData.moves(data, def)
  data = data or {}
  def = def or {}

  local learned, seen = {}, {}
  for _, entry in ipairs(def.learnset or {}) do
    if entry.move and not seen[entry.move] then
      seen[entry.move] = true
      local moveType, name = typeOf(data, entry.move)
      learned[#learned + 1] = {
        level = entry.level, move = entry.move,
        name = name or entry.move,
        type = moveType, stab = isStab(def, moveType),
      }
    end
  end

  -- One pass over the items registry, not one per machine move: the registry
  -- is every item in the game and the tmhm list is at most a few dozen.
  local machineByMove = {}
  for _, item in pairs(data.items or {}) do
    local m = item.machine
    if m and m.kind and m.number and m.move and not machineByMove[m.move] then
      machineByMove[m.move] = m
    end
  end

  local machines = {}
  for _, moveId in ipairs(def.tmhm or {}) do
    local m = machineByMove[moveId]
    if m then
      local moveType, name = typeOf(data, moveId)
      machines[#machines + 1] = {
        kind = m.kind, number = m.number, move = moveId,
        name = name or moveId,
        type = moveType, stab = isStab(def, moveType),
      }
    end
  end
  table.sort(machines, function(a, b)
    local ka = a.kind == "HM" and 1 or 0
    local kb = b.kind == "HM" and 1 or 0
    if ka ~= kb then return ka < kb end
    if a.number ~= b.number then return a.number < b.number end
    return a.move < b.move
  end)

  return { learned = learned, machines = machines }
end

-- The movelist as the rows the MOVES page prints, section headings included,
-- so pagination counts the headings it is going to draw rather than the moves
-- it started from.  Each row carries the move it came from (nil on a heading)
-- so the drawer can colour a STAB chip without matching its own label back.
--
-- The widths are a budget, not a style.  A move row is drawn at x=16 with a
-- 5-pixel STAB chip in the margin before it, which leaves 17 glyphs before
-- the right edge at 152.  "L%-3d %s" spends five of them on the level and
-- twelve on the name, and twelve is the longest move name in the game
-- (THUNDERSHOCK).  "%s%02d %s" spends five on the machine and the same twelve
-- on the name.  Both land exactly on 152.
function DexData.moveRows(list)
  list = list or { learned = {}, machines = {} }
  local rows = {}
  if #(list.learned or {}) > 0 then
    rows[#rows + 1] = { text = "LEARNED", heading = true }
    for _, e in ipairs(list.learned) do
      rows[#rows + 1] = { text = ("L%-3d %s"):format(e.level or 0, e.name),
                          move = e }
    end
  end
  if #(list.machines or {}) > 0 then
    rows[#rows + 1] = { text = "TM/HM", heading = true }
    for _, m in ipairs(list.machines) do
      rows[#rows + 1] = { text = ("%s%02d %s"):format(m.kind, m.number, m.name),
                          move = m }
    end
  end
  if #rows == 0 then rows[1] = { text = "NO MOVES.", heading = true } end
  return rows
end

-- ------- base stats, BST and evolutions
--
-- The five Gen 1 stats in the order the summary screen prints them, their
-- sum, and the species' evolutions labelled through the MERGED
-- evolution_methods registry rather than by matching on method names here:
-- a mod that adds an evolution method ships a describe() with it, and asking
-- the registry is what makes that method's label appear on this page for
-- free.  A method with no describe() falls back to its own id, which is ugly
-- but true, and never blank.
local STAT_KEYS = {
  { key = "HP", field = "hp" },
  { key = "ATK", field = "attack" },
  { key = "DEF", field = "defense" },
  { key = "SPD", field = "speed" },
  { key = "SPC", field = "special" },
}

function DexData.stats(data, def)
  data = data or {}
  def = def or {}
  local bs = def.baseStats or {}
  local stats, bst = {}, 0
  for _, spec in ipairs(STAT_KEYS) do
    local value = bs[spec.field] or 0
    stats[#stats + 1] = { key = spec.key, value = value }
    bst = bst + value
  end

  local evolutions = {}
  for _, evo in ipairs(def.evolutions or {}) do
    local method = data.evolution_methods and data.evolution_methods[evo.method]
    local label = evo.method
    if method and method.describe then
      local ok, described = pcall(method.describe, evo, data)
      if ok and type(described) == "string" and described ~= "" then
        label = described
      end
    end
    local target = data.pokemon and data.pokemon[evo.species]
    evolutions[#evolutions + 1] = {
      method = evo.method, label = label, species = evo.species,
      name = (target and target.name) or evo.species,
    }
  end

  return { stats = stats, bst = bst, evolutions = evolutions }
end

-- ------- the dex description
--
-- Reimplemented rather than borrowed from src/ui/DexEntryMenu: the vanilla
-- pager is a local in that file and only its RENDERER is public, and this
-- screen prints the lines into its own panel rather than over the vanilla
-- page.  The splitting rules are the ROM's: \f starts a new page
-- (home/text.asm <PAGE>), \v is a line break inside one, and the last line of
-- the last page gains the full stop <DEXEND> printed for it.
--
-- Ownership gates the text exactly as vanilla gates it -- a species you have
-- only SEEN shows its picture and its number and nothing else -- because that
-- is the one rule the Pokédex has ever had.
function DexData.description(data, def, owned)
  if not owned then return nil end
  local e = (def or {}).dexEntry or {}
  local text = e.text and data and data.text and data.text[e.text] or nil
  if not text or text == "" then return nil end
  local pages = {}
  for chunk in (text .. "\f"):gmatch("(.-)\f") do
    local lines = {}
    for line in (chunk:gsub("\v", "\n") .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
    if #lines > 0 then pages[#pages + 1] = lines end
  end
  if #pages == 0 then return nil end
  local last = pages[#pages]
  last[#last] = last[#last] .. "."
  return pages
end

-- ------- the list
--
-- Three views over the same 151 slots.  The counts are always the WHOLE
-- dex's, in every view, because "SEEN 47 OWN 12" is a fact about your dex and
-- not about the filter you are looking through it with.
--
-- Every item carries `species` even when the slot is blank, which the vanilla
-- list does not: the blank row still draws an icon here -- blacked out -- and
-- an icon needs a species to resolve.  `value` keeps the vanilla meaning
-- (nil = A does nothing on this row), so the side menu is untouched.
DexData.MODES = { "num", "alpha", "caught" }
DexData.MODE_LABELS = {
  num = "POKéDEX",
  alpha = "POKéDEX A-Z",
  caught = "POKéDEX CAUGHT",
}
DexData.NEXT_MODE = { num = "alpha", alpha = "caught", caught = "num" }

function DexData.list(data, save, mode)
  data = data or {}
  save = save or { seen = {}, owned = {} }
  local savedSeen = save.seen or {}
  local savedOwned = save.owned or {}

  local byDex = {}
  for _, def in pairs(data.pokemon or {}) do
    if def.dex then byDex[def.dex] = def end
  end

  local constants = data.constants or {}
  local numFmt = ("%%0%dd"):format(constants.dexDigits or 3)
  local entries, seen, owned = {}, 0, 0
  for n = 1, constants.dexSize or 151 do
    local def = byDex[n]
    if def then
      local isOwned = savedOwned[def.id] and true or false
      local has = isOwned or (savedSeen[def.id] and true or false)
      if has then seen = seen + 1 end
      if isOwned then owned = owned + 1 end
      if mode == "num"
          or (mode == "alpha" and has)
          or (mode == "caught" and isOwned) then
        entries[#entries + 1] = { def = def, n = n, has = has, owned = isOwned }
      end
    end
  end

  if mode == "alpha" then
    -- by name, then by number, so two species sharing a name (NIDORAN)
    -- always come out in the same order rather than in hash order
    table.sort(entries, function(a, b)
      if a.def.name ~= b.def.name then return a.def.name < b.def.name end
      return a.n < b.n
    end)
  end

  local items = {}
  for _, e in ipairs(entries) do
    items[#items + 1] = {
      label = (numFmt .. " %s"):format(e.n, e.has and e.def.name or "-----"),
      ball = e.owned or nil,
      value = e.has and e.def.id or nil,
      species = e.def.id,
      seen = e.has,
      owned = e.owned,
    }
  end

  return { items = items, seen = seen, owned = owned, mode = mode }
end

-- The species that have been SEEN, in dex order: what UP/DOWN steps through
-- on the entry screen.  Owned implies seen, so one test covers both.
function DexData.seenSpecies(data, save)
  local pokedex = save or {}
  local savedSeen = pokedex.seen or {}
  local savedOwned = pokedex.owned or {}
  local species = {}
  for id, def in pairs((data or {}).pokemon or {}) do
    if def.dex and (savedSeen[id] or savedOwned[id]) then
      species[#species + 1] = id
    end
  end
  table.sort(species, function(a, b)
    local da, db = data.pokemon[a].dex, data.pokemon[b].dex
    if da ~= db then return da < db end
    return a < b
  end)
  return species
end

return DexData
