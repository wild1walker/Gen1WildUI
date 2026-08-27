-- Gen1ItemInfo
--
-- Gen 1 never tells you what an item is.  The mart shows a name and a price,
-- the bag shows a name and a count, and the clerk fills the one box on the
-- screen that could have said something with "Take your time."  Item
-- descriptions arrive in Gen 2, with the PACK.
--
-- This mod writes them, and then puts them where a player is already looking:
--
--   * the mart's BUY and SELL lists, in the clerk's own box, following the
--     cursor -- which is what replaces "Take your time.";
--   * the item PC's WITHDRAW, DEPOSIT and TOSS lists, in the same box;
--   * an ABOUT row in the bag's item menu, which prints one in a text box.
--
-- and redraws those four lists in the frame the rest of the suite uses while
-- it is there, because a description needs a box to sit in and the vanilla
-- lists have no header, no margins and a money box floating in the corner.
--
--   descriptions.lua  the sentences: every item, two lines, eighteen glyphs
--   chrome.lua        the drawing kit, shared with Gen1Dex's and Gen1Party's
--   screens.lua       the mart and the item PC
--   about.lua         the bag's ABOUT row
--
-- ------- the descriptions go into the DATA, not into this mod
--
-- `mod.content.items:patch(id, { description = ... })`, which lands them on
-- `data.items[id].description` -- the field Gen 2's own extractor writes for
-- Gold and Crystal (RomExtractorGen2, ItemDescriptions), under the name it
-- writes it under.  So this mod is not the keeper of a private table that
-- only it can read: anything that wants to show an item description reads it
-- off the item, the way it would on a Gen 2 cart, whether or not this mod is
-- the thing that put it there.
--
-- Records are extensible by design (Schemas.check preserves unknown top-level
-- fields), so this needs no schema change and takes nothing away: an item
-- gains a field and keeps every one it had.
--
-- ------- every switch is live
--
-- No row here needs a relaunch.  The screens are decorated at load and each
-- one asks its option every time it draws, so turning MART SCREENS off puts
-- the engine's own draw back on the next frame rather than on the next boot.

local FEATURES = { "mart", "pc", "about" }

-- A file this mod ships, compiled in this mod's own sandbox.  mod:read plus
-- load is the documented way to reach one: a mod's directory is not on
-- package.path, and require() would only find it by accident of where the mod
-- happens to be installed.
local function part(mod, name)
  local source, readError = mod:read(name)
  if not source then
    mod.log:error("%s is missing (%s) -- reinstall the mod", name,
      tostring(readError))
    return nil
  end
  local chunk, compileError = load(source, "@" .. tostring(mod.path) .. "/" .. name)
  if not chunk then
    mod.log:error("%s did not compile: %s", name, tostring(compileError))
    return nil
  end
  local ok, value = pcall(chunk)
  if not ok then
    mod.log:error("%s failed to load: %s", name, tostring(value))
    return nil
  end
  return value
end

-- The two lines a machine gets, from the move it carries rather than from a
-- table here: fifty-five hand-written lines that all say the same thing would
-- be fifty-five chances to disagree with the move data, and a mod that
-- retunes what TM26 teaches would leave every one of them lying.
--
-- The move goes on the first line and the kind on the second, which is the
-- one arrangement that fits every move in the game.  "Teaches THUNDERBOLT."
-- is nineteen glyphs and SELFDESTRUCT's is twenty, so a line that opens with
-- the verb has to be two shapes depending on the name -- and a description
-- that is phrased one way for MEGA PUNCH and another for THUNDERBOLT reads
-- as a bug.  The bag row above it already says TM24; this says what TM24 is
-- and what a TM costs to use.
--
-- HM or TM is read off the id, which is what the engine itself does
-- everywhere it needs to know (BagMenu's toss refusal, ShopMenu's unsellable
-- check).
local function machineLine(id, moveName)
  local head = moveName .. "."
  if id:find("^HM_") then return head .. "\nAn HM. Reusable." end
  return head .. "\nA TM. Used once."
end

return function(mod)
  mod.options:define({
    { key = "enabled", type = "toggle", label = "ITEM INFO", default = true },

    -- The mart's three screens: the BUY / SELL / QUIT counter, and the two
    -- lists behind it.
    { key = "mart", type = "toggle", label = "MART SCREENS", default = true,
      visible_if = { key = "enabled", equals = true } },
    -- WITHDRAW / DEPOSIT / TOSS ITEM.  Not the POKéMON box, which is
    -- Gen1BillsBox's, and not the PC's own menu, which is a menu and was
    -- never the undecorated part.
    { key = "pc", type = "toggle", label = "PC SCREENS", default = true,
      visible_if = { key = "enabled", equals = true } },
    -- The bag row.  Its own switch because it is the one part of this that
    -- adds something to a menu rather than redrawing one.
    { key = "about", type = "toggle", label = "BAG ABOUT", default = true,
      visible_if = { key = "enabled", equals = true } },
  })

  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  -- What every decorated screen asks before it draws, so a row switched off
  -- in the menu is off on the next frame rather than on the next boot.
  local function wants(feature)
    if option("enabled", true) ~= true then return false end
    return option(feature, true) == true
  end

  local Descriptions = part(mod, "descriptions.lua")
  if type(Descriptions) ~= "table" then
    mod.log:error("no descriptions to show; the screens are left alone")
    return
  end

  -- ------- the sentences, onto the items
  --
  -- Guarded on the id existing, because a patch to an id nothing registered
  -- would CREATE it: Registry folds a patch over a nil base, and the result
  -- is an item record with a description and no name, sitting in data.items
  -- for anything that walks it to find.  Only items this game actually has
  -- are described.

  local items = mod.content.items
  local written, skipped = 0, 0

  for id, line in pairs(Descriptions) do
    if items:get(id) then
      items:patch(id, { description = line })
      written = written + 1
    else
      skipped = skipped + 1
    end
  end

  -- Machines second, and only where the hand-written table has nothing to
  -- say, so a mod that wants a particular TM described its own way can add a
  -- row to descriptions.lua and have it win.
  local moves = mod.content.moves
  for id, def in items:each() do
    if not Descriptions[id] and type(def) == "table"
        and type(def.machine) == "table" and def.machine.move then
      local move = moves and moves:get(def.machine.move)
      local name = type(move) == "table" and move.name
      -- No move record to read a printed name off (a machine a mod added
      -- pointing at a move it has not registered yet): the id is the only
      -- name there is, and MEGA_PUNCH reads better spelled the way the game
      -- spells it than the way the constant does.
      if not name then name = (def.machine.move:gsub("_", " ")) end
      items:patch(id, { description = machineLine(id, tostring(name)) })
      written = written + 1
    end
  end

  mod.log:info("%d items described (%d ids this game does not have)",
    written, skipped)

  -- ------- reading one back
  --
  -- Off the item, never off the table above: the machines are only ever in
  -- the data, another mod may have described an item this one has never
  -- heard of, and data.items is where a Gen 2 cart would have kept it.  The
  -- table is the fallback for the one case that leaves -- a merge that did
  -- not land -- so a rolled-back patch costs the descriptions their home,
  -- not their existence.
  local function describe(game, id)
    if type(id) ~= "string" then return nil end
    local data = game and game.data
    local def = data and data.items and data.items[id]
    if type(def) == "table" and type(def.description) == "string" then
      return def.description
    end
    return Descriptions[id]
  end

  local Chrome = part(mod, "chrome.lua")
  local C = type(Chrome) == "function" and Chrome(mod) or nil
  if not C then
    mod.log:error("the drawing kit did not load; the screens are left alone")
    return
  end

  local Screens = part(mod, "screens.lua")
  if type(Screens) == "function" then
    -- `wants` is passed rather than folded into `describe`: each list asks
    -- about its own row, so MART SCREENS off has to leave the PC's three
    -- alone, and one gate for both could not tell them apart.
    local screens = Screens(mod, C, describe, wants)
    if type(screens) == "table" then screens.install() end
  end

  local About = part(mod, "about.lua")
  if type(About) == "function" then
    local about = About(mod, describe, wants)
    if type(about) == "table" then about.install() end
  end

  -- Published so a sibling can print a description without owning a copy of
  -- the table: Gen1BillsBox's box popup and Gen1ModernBag's pockets both have
  -- somewhere one would fit.
  mod.exports.describe = describe
  mod.exports.descriptions = Descriptions
  mod.exports.machineLine = machineLine
  mod.exports.features = FEATURES

  mod.log:info("every item says what it is")
end
