-- Gen1Party: the party menu, drawn like the rest of the set.
--
-- One registered screen replacement, and one relabelled row on the START
-- menu -- see the bottom of this file for that one.  Screens.resolve
-- prefers the screens registry over the builtin module (src/ui/Screens.lua),
-- so a mod-free boot is untouched, and a factory that throws when the screen
-- is PUSHED degrades to the builtin -- Screens.build already pcalls a
-- mod-owned `new` and falls back, which is why nothing here has to.
--
-- What this file does not do is swallow a LOAD-time failure.  Nothing is at
-- risk while the game boots: if the screen cannot be built the party menu
-- stays vanilla either way, and the only question left is whether the player
-- is told.  A mod.log:error goes to a log file nobody opens, and what is left
-- on screen is an enabled mod that changes nothing -- indistinguishable from
-- one that was never installed, which is exactly the bug report it produces.
-- Raising instead puts the reason on the loader's boot error feed and marks
-- the row enabled-but-broken in MODS (src/mods/Loader.lua _fail), which is
-- where a player looks.
--
-- The two sibling files are loaded rather than required because a mod cannot
-- put itself on package.path: mod:read hands back the file's source from
-- wherever the mod actually lives (an installed directory, or inside an
-- imported .zip), and load() names the chunk after that path so a syntax
-- error in screen.lua reports as screen.lua and not as a line in this file.

local function loadSibling(mod, name)
  local source, readErr = mod:read(name)
  if not source then
    error(("%s is missing (%s); reinstall the mod")
      :format(name, tostring(readErr or "unknown read error")), 0)
  end
  -- mod.path is the install directory, and it is decoration on the chunk name
  -- rather than something to concatenate blind: a host that does not hand one
  -- over would otherwise fail here, on the string, with nothing to say.
  local chunkName = "@" .. (mod.path and (mod.path .. "/") or "") .. name
  local chunk, compileErr = load(source, chunkName)
  if not chunk then
    error(("%s did not compile: %s"):format(name, tostring(compileErr)), 0)
  end
  local ok, value = pcall(chunk)
  if not ok then
    error(("%s failed to run: %s"):format(name, tostring(value)), 0)
  end
  if type(value) ~= "function" then
    error(("%s did not return a factory (got %s)"):format(name, type(value)), 0)
  end
  return value
end

-- ------- the START menu's row
--
-- The one thing here that is not the party screen, and the one thing that is
-- the same on both generations -- which is why it is a function rather than a
-- block inside the Gen 1 arm.
--
-- `ui.start_menu.items` is the engine's own seam for exactly this and is
-- raised by both start menus (src/ui/StartMenu.lua builds its list and hands
-- it through; src/ui/gen2/StartMenu.lua does the same), so the row is
-- relabelled in the list the engine gives us rather than by replacing
-- StartMenu -- a screen with seven submenus and a save-confirmation flow that
-- this mod has no opinion about.  next() runs FIRST and its result is
-- decorated, so another mod's row survives and no vanilla row is rebuilt by
-- hand.
--
-- The row is found by the string the engine built it from, not by position:
-- Strings keys on its English source (src/core/Strings.lua), so
-- Strings("POKéMON") here is the same value StartMenu's own Strings("POKéMON")
-- produced, under every translation and on both carts.  A row this does not
-- find is left exactly as it was.
--
-- A warning rather than a raise when there is no hook bus to wrap: unlike a
-- screen that will not build, losing this does not leave an enabled mod doing
-- nothing.  On Gen 1 the party still draws framed; on Gold the icons still
-- wear their own colours.  One menu row keeps the engine's word for it.
local function installStartMenuRow(mod)
  if not (type(mod.hooks) == "table" and type(mod.hooks.wrap) == "function") then
    mod.log:warn("no hook bus here; the START menu keeps its own word")
    return
  end
  local Strings = require("src.core.Strings")
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    if mod.options:get("start_says_party") == false then return out end
    -- ------- and the two games hand a hook different halves of the same row
    --
    -- Red translates its labels before the hook sees them, so the word on the
    -- row is the translated one.  Gold deliberately does NOT: it builds rows
    -- with `Strings.source(...)` and translates afterwards, for rows that
    -- carry `translateLabel`, "so hooks inspect the cart's stable source
    -- labels" (src/ui/gen2/StartMenu.lua).  Matching only the translated word
    -- therefore finds nothing on Gold the moment a translation is installed,
    -- and this row quietly keeps saying POKéMON.
    --
    -- Both forms are accepted, which in English is the same string twice and
    -- cannot match anything it did not match before.
    local source = Strings.source("POKéMON")
    local engineWord = Strings("POKéMON")
    for _, item in ipairs(out) do
      if type(item) == "table"
          and (item.label == engineWord or item.label == source) then
        -- Written in the shape the row is in: a row still waiting to be
        -- translated gets the source word and is translated once, rather than
        -- a translated word that would be put through the catalog twice.
        item.label = item.translateLabel and Strings.source("PARTY")
          or Strings("PARTY")
      end
    end
    return out
  end)
end

-- ------- Gold
--
-- Gold has the same bug this mod exists to fix, and has it for the same
-- reason: one palette for the whole list.
--
--     -- Every party icon OAM entry is PAL_OW_RED (data/sprite_anims/oam.asm
--     -- :315-355) and InitPartyMenuOBPals loads PartyMenuOBPals into OBJ 0
--     -- for the whole list, species and EGG alike (engine/gfx/color.asm:593
--     -- -598, :1228-1229).
--     local pals = self.palettes and self.palettes.partyMenu
--     local colors = pals and pals[1] or nil
--
-- That is `PartyMenu:drawIcon`, src/ui/gen2/PartyMenu.lua:869-873, and it is
-- Red's single MEWMON zone over all six rows written in CGB instead of SGB.
-- Six mons, one palette, on a machine that can give each of them their own.
--
-- ------- what the Gold arm is, and what it is not
--
-- It is NOT the Gen 1 screen.  Nothing here registers `Gen2PartyMenu` and
-- nothing redraws Gold's party list: that screen is the cart's, it is already
-- laid out from the ASM's own coordinates, and it already has the things the
-- Gen 1 replacement was built to add -- the HP bar per row, the held-item
-- marker, the level and the status tag.  Replacing it would be work spent to
-- arrive back where Gold started.
--
-- What moves is the four colours, and only those.  `drawIcon` reads them off
-- `self.palettes` at the moment it paints, so handing it a `palettes` whose
-- `partyMenu[1]` is THIS mon's pair -- for the length of one call, then put
-- back -- gives every row its own species colours through the cart's own
-- `GbcPalette.with`, with the icon, the bob, the held marker and the cursor
-- offset all still drawn by Gold.
--
-- The mon's pair is `Palettes.monColors`, which is where Gold's battle pics
-- get theirs, so a CHARMANDER in the party is the orange it is in a fight.
--
-- Off is the cart exactly: no substitution, `drawIcon` reads the palettes it
-- always read.
local function installGen2(mod)
  local PartyMenu = require("src.ui.gen2.PartyMenu")
  local Palettes = require("src.world.gen2.Palettes")

  -- Idempotent, and by identity rather than a flag: a hot reload runs this
  -- file again, and a wrapper around a wrapper would substitute twice and
  -- leave the second put-back holding the first one's table.
  local MARK = "__gen1PartyGen2"
  if rawget(PartyMenu, MARK) then return end

  local base = PartyMenu.drawIcon
  if type(base) ~= "function" then
    mod.log:warn("src.ui.gen2.PartyMenu has no drawIcon; SPECIES COLOURS "
      .. "stands down")
    return
  end

  -- One shadow table for the whole run, rewritten per icon.  Six allocations
  -- a frame for six rows is six more than this needs, and the table never
  -- escapes the call it is handed to.
  local shadow = { partyMenu = { nil } }

  PartyMenu.drawIcon = function(self, mon, px, py)
    local want = mod.options:get("species_colours")
    if want == false or not mon then return base(self, mon, px, py) end

    local palettes = self.palettes
    if type(palettes) ~= "table" then return base(self, mon, px, py) end

    -- An EGG has no species pair to look up and answers nil, which is the
    -- right answer rather than a fallback: the cart draws every egg in the
    -- party palette and there is no egg colour to prefer over it.
    local colors = Palettes.monColors(palettes, mon.species,
                                      mon.shiny and true or false)
    if not colors then return base(self, mon, px, py) end

    -- Everything on `palettes` except partyMenu has to stay reachable:
    -- drawIcon is not the only thing that reads it, and a shadow that carried
    -- one key would hand the rest of the screen an empty table.  __index onto
    -- the real one is what keeps that true without copying it every icon.
    shadow.partyMenu[1] = colors
    setmetatable(shadow, { __index = palettes })

    self.palettes = shadow
    local ok, problem = pcall(base, self, mon, px, py)
    self.palettes = palettes

    if not ok then error(problem, 0) end
  end

  PartyMenu[MARK] = true
  mod.log:info("the party wears its own colours")
end


return function(mod)
  -- ------- which arm
  --
  -- Asked before anything else, for two reasons.
  --
  -- The Gold arm must not LOAD the Gen 1 screen: screen.lua reaches
  -- `PartyMenu.drawIcon` and `PartyMenu.sgbPalettes`, and on a Gold boot
  -- `src.ui.PartyMenu` resolves to the Gen2Compat facade over Gold's class,
  -- which has neither -- both read nil.  It would also register under
  -- `PartyMenu`, an id Gold never builds (its own is `Gen2PartyMenu`), so it
  -- would be a screen nothing could ever push, built out of two nils.
  --
  -- And two of the four rows below are settings for that screen.  A row that
  -- cannot do anything is worse than a missing one: it is a switch the player
  -- flips and watches not work.
  local isGen2 = false
  do
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    if ok and type(GameVersion) == "table"
        and type(GameVersion.generation) == "function" then
      local okCall, generation = pcall(GameVersion.generation)
      isGen2 = okCall and generation == 2
    end
  end

  local schema = {
    -- Every POKeMON in the party in its own species colours, over the plain
    -- grey ramp.  Off restores the vanilla answer exactly -- the GREENBAR
    -- base and the single MEWMON zone laid over all six icons at once -- for
    -- anyone who wants the 1996 screen with nothing changed but the margins.
    { key = "species_colours", type = "toggle", label = "SPECIES COLOURS",
      default = true },
    -- The START menu's row for this screen says POKeMON, which is the word
    -- the cart uses and is also most of the word on the row above it.  PARTY
    -- names the screen it opens.  Off leaves the engine's own word alone.
    { key = "start_says_party", type = "toggle", label = "START: PARTY",
      default = true },
  }

  -- A hairline between the icons and the names, the one the dex list draws,
  -- with the names moved off the icon cell to make room for it.  Ten glyphs
  -- of name need every pixel from 24 to the digits beside them, so the air is
  -- bought with the tenth: CHARMANDER reads CHARMANDE.  Off restores the
  -- full-width name column, and the icons touch the names again.
  --
  -- On both generations as of 0.32.28.  It used to be a Gen 1 row on the
  -- grounds that Gold's names already sit off the icon cell, and that was
  -- true of the UNSELECTED rows only: `PartyMenu:iconX` slides the selected
  -- icon eight pixels right, into the very gap the claim was about, so the
  -- row you are looking at is the one row where the art touches the name.
  -- Off there also puts the slide back, which is the cue the rule replaces.
  schema[#schema + 1] = { key = "ruled_icons", type = "toggle",
    label = "RULED ICONS", default = true }

  -- The one row that is a setting for the Gen 1 screen, and so exists only
  -- where that screen does: on Gold, moving a member is MOVE POKéMON in the
  -- PC (_MovePKMNWithoutMail) rather than a row on this popup.
  -- The popup's SWITCH row, and what pressing it does.  On: the row says
  -- MOVE, and A lifts that member -- it flashes, UP and DOWN carry it through
  -- the list a row at a time, and the party is reordered under it as it goes,
  -- which is how Gen1BillsBox moves one.  Off restores the engine's own
  -- SWITCH: two picks over a list that does not move, and one exchange when
  -- the second lands.
  --
  -- Offered on BOTH cartridges now.  It was Gen 1 only for as long as Gold
  -- kept its own swap, and gen2carry.lua is that same behaviour over Gold's
  -- own move mode -- so the row means the same thing on both and reads the
  -- same key.
  schema[#schema + 1] = { key = "live_move", type = "toggle",
    label = "MOVE NOT SWITCH", default = true }

  mod.options:define(schema)

  if isGen2 then
    installGen2(mod)
    -- and the frame.  Loaded here rather than at the top of the file for the
    -- reason every sibling is: a mod cannot put itself on package.path, so
    -- mod:read is what finds it -- and a Gen 1 boot must not pay for reading
    -- a file whose every line is about Gold.
    --
    -- Guarded rather than raised, and that is the difference between this and
    -- screen.lua below.  A Gen 1 boot with no screen.lua has an enabled mod
    -- that changes nothing, which is worth the boot error feed.  A Gold boot
    -- with no frame still has the species colours and the START menu's row --
    -- it is the cart's party list, which is what every build before 0.32.28
    -- had -- so a panel that will not load is a warning, not a broken mod.
    local okPanel, panel = pcall(loadSibling, mod, "gen2panel.lua")
    if okPanel and type(panel) == "function" then
      local built = panel(mod)
      if type(built) == "table" and type(built.install) == "function" then
        local ranOk, problem = pcall(built.install)
        if ranOk then
          mod.exports.gen2panel = built
        else
          mod.log:warn("the party keeps the cart's frame: %s", tostring(problem))
        end
      end
    else
      mod.log:warn("gen2panel.lua did not load; the party keeps the cart's "
        .. "frame: %s", tostring(panel))
    end
    -- ------- and MOVE carries rather than swaps
    --
    -- Its own arm, and its own failure: a party that keeps the cart's swap is
    -- the party every build before this one had, so this is a warning rather
    -- than a broken screen.  See gen2carry.lua.
    local okCarry, carry = pcall(loadSibling, mod, "gen2carry.lua")
    if okCarry and type(carry) == "function" then
      local built = carry(mod)
      if type(built) == "table" and type(built.install) == "function" then
        local ranOk, problem = pcall(built.install)
        if ranOk then
          mod.exports.gen2carry = built
        else
          mod.log:warn("MOVE keeps the cart's swap: %s", tostring(problem))
        end
      end
    else
      mod.log:warn("gen2carry.lua did not load; MOVE keeps the cart's swap: %s",
        tostring(carry))
    end
    installStartMenuRow(mod)
    return
  end

  local makeChrome = loadSibling(mod, "chrome.lua")
  local makeScreen = loadSibling(mod, "screen.lua")

  local C = makeChrome(mod)
  if type(C) ~= "table" then
    error(("chrome.lua did not build the drawing kit (got %s)"):format(type(C)),
          0)
  end

  local screen = makeScreen(mod, C)
  if not (type(screen) == "table" and type(screen.new) == "function") then
    error("screen.lua did not build the party screen", 0)
  end

  mod.content.screens:register("PartyMenu", screen)
  mod.exports.geometry = screen.geometry

  -- ------- the START menu's row
  --
  -- The one thing here that is not the party screen.  ui.start_menu.items is
  -- the engine's own seam for exactly this (src/ui/StartMenu.lua builds its
  -- list and hands it through), so the row is relabelled in the list the
  -- engine gives us rather than by replacing StartMenu -- a screen with seven
  -- submenus and a save-confirmation flow that this mod has no opinion about.
  -- next() runs FIRST and its result is decorated, so another mod's row
  -- survives and no vanilla row is rebuilt by hand.
  --
  -- The row is found by the string the engine built it from, not by position:
  -- Strings keys on its English source (src/core/Strings.lua), so
  -- Strings("POKéMON") here is the same value StartMenu's own
  -- Strings("POKéMON") produced, under every translation.  A row this does
  -- not find is left exactly as it was.
  --
  -- A warning rather than a raise when there is no hook bus to wrap: unlike a
  -- screen that will not build, losing this does not leave an enabled mod
  -- doing nothing.  The party still draws framed; one menu row keeps the
  -- engine's word for it.
  installStartMenuRow(mod)

  mod.log:info("the party wears its own colours")
end
