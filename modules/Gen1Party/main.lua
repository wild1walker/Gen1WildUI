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

return function(mod)
  mod.options:define({
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
    -- A hairline between the icons and the names, the one the dex list draws,
    -- with the names moved off the icon cell to make room for it.  Ten glyphs
    -- of name need every pixel from 24 to the level column, so the air is
    -- bought with the tenth: CHARMANDER reads CHARMANDE.  Off restores the
    -- full-width name column, and the icons touch the names again.
    { key = "ruled_icons", type = "toggle", label = "RULED ICONS",
      default = true },
  })

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
  if type(mod.hooks) == "table" and type(mod.hooks.wrap) == "function" then
    local Strings = require("src.core.Strings")
    mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      local out = next(game, items)
      if type(out) ~= "table" then return out end
      if not C.option("start_says_party", true) then return out end
      local engineWord, ours = Strings("POKéMON"), Strings("PARTY")
      for _, item in ipairs(out) do
        if type(item) == "table" and item.label == engineWord then
          item.label = ours
        end
      end
      return out
    end)
  else
    mod.log:warn("no hook bus here; the START menu keeps its own word")
  end

  mod.log:info("the party wears its own colours")
end
