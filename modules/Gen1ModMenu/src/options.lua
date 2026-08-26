-- Every Gen1ModMenu behaviour is a row here, and every row ships with the
-- least-surprising default spelled out next to it.  The schema is handed to
-- mod.options:define, which is what draws the rows in
-- MODS > Gen1ModMenu > OPTIONS -- the very screen this mod redraws, so these
-- rows are the first thing the new presentation is judged on.
--
-- Row shapes are the four the engine renders: toggle, choice, number, text.
-- `choices` are { label, value } pairs; `visible_if` only hides a menu row,
-- it never changes the stored value, so a hidden row still reads back the
-- value the player last chose.
--
-- Sort and filter live here rather than on a button because the manager
-- leaves no key free: the list already spends up and down on the cursor,
-- left and right on the tabs (ManagerState:adjustOrTab), A on open, B on
-- back, START on apply and SELECT on the quick toggle.

local Options = {}

Options.schema = {
  -- ------- presentation

  -- The way back out from inside the mod itself.  A skin that draws
  -- something the player cannot read is still a skin they have to navigate
  -- to switch off, so VANILLA is one row away and hands every screen back to
  -- the engine's own renderer untouched.
  { key = "presentation", type = "choice", label = "STYLE",
    default = "modern",
    choices = {
      { "MODERN", "modern" },
      { "VANILLA", "vanilla" },
    } },

  -- ------- the mod list

  { key = "sort", type = "choice", label = "SORT BY", default = "category",
    choices = {
      { "CATEGORY", "category" },
      { "NAME", "name" },
      { "ENABLED", "enabled" },
      { "PROBLEMS", "status" },
    },
    visible_if = { key = "presentation", equals = "modern" } },

  { key = "hide_disabled", type = "toggle", label = "HIDE OFF",
    default = false,
    visible_if = { key = "presentation", equals = "modern" } },

  { key = "only_options", type = "toggle", label = "WITH OPTIONS",
    default = false,
    visible_if = { key = "presentation", equals = "modern" } },

  -- ------- the per-mod options page

  -- RESET DEFAULTS is not a row here: the engine appends one of its own at
  -- the end of every options page (src/mods/ManagerState.lua
  -- buildOptionRows), and 0.1.0 through 0.3.0 shipped a second one beside
  -- it.  All this mod adds to the engine's is the help line below.
  { key = "help_line", type = "toggle", label = "HELP LINE", default = true,
    visible_if = { key = "presentation", equals = "modern" } },

  -- ------- the menus outside the manager

  -- START ROW was here through 0.7.2, switching the START menu's row between
  -- MODS and MOD MENU.  The row is the engine's own and reads MODS again, so
  -- there is nothing left for a toggle to choose between.  A stored value is
  -- ignored; there is nothing to migrate.

  -- CANCEL on the game's OPTION screen.  B and START already leave that
  -- menu, so the row is a second exit rather than the only one -- but it is
  -- the engine's belt-and-braces, so it is a row here and not a decision.
  { key = "hide_cancel", type = "toggle", label = "HIDE CANCEL",
    default = true,
    visible_if = { key = "presentation", equals = "modern" } },

  -- ------- everywhere

  { key = "cursor_memory", type = "toggle", label = "KEEP CURSOR",
    default = true,
    visible_if = { key = "presentation", equals = "modern" } },
}

-- key -> row, so the reader can fall back to a default and validate a choice
-- against the values the schema actually offers.
local byKey = {}
for _, row in ipairs(Options.schema) do byKey[row.key] = row end

local function legal(row, value)
  if row.type == "toggle" then return type(value) == "boolean" end
  if row.type == "number" then return type(value) == "number" end
  if row.type == "choice" then
    for _, choice in ipairs(row.choices) do
      if choice[2] == value then return true end
    end
    return false
  end
  return true
end

-- A reader rather than raw mod.options:get calls.  A stored value can be
-- anything -- an older version's vocabulary, a hand-edited options file --
-- and this mod reads its own options from inside the draw path of the one
-- screen a player uses to fix a broken mod.  Anything out of vocabulary
-- falls back to the row default, and every default here is the vanilla
-- answer or the safe one.
-- The choices a row offers, for anywhere that needs to show them outside the
-- options page -- the START menu on the mod list builds its rows from this,
-- so the two can never disagree about what the sorts are called.
function Options.choices(key)
  return (byKey[key] or {}).choices
end

function Options.reader(mod)
  return function(key)
    local row = byKey[key]
    if not row then return nil end
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok then return row.default end
    if value == nil or not legal(row, value) then return row.default end
    if row.type == "number" then
      if row.min then value = math.max(row.min, value) end
      if row.max then value = math.min(row.max, value) end
    end
    return value
  end
end

return Options
