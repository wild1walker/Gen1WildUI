-- Gen1Dex: the Pokédex, brought up to the rest of the set.
--
-- Two registered screen replacements and one renamed START menu row.
-- Screens.resolve prefers the screens registry over the builtin module
-- (src/ui/Screens.lua), so a mod-free boot is untouched and a factory that
-- throws degrades to the builtin -- which is why every entry point here is
-- guarded rather than trusted: a Pokédex that fails to open is worse than a
-- vanilla one.
--
--   PokedexMenu    the list, with a party icon beside every entry
--   DexEntryMenu   the entry, as three pages A cycles between
--
-- plus the AREA screen behind them (area.lua): opened on a POKéMON you have
-- never met, and captioned with a line saying how to get there.  A content
-- mod that adds a spawn hands this screen the words for its own species
-- through mod.find("Gen1Dex").exports.area.provide -- the dex owns the
-- surface, and whoever placed the POKéMON owns the sentence.
--
-- and the nickname prompt after a catch (naming.lua): it is asked over the
-- screen it interrupted -- the entry the game just showed you, or the field
-- the POKéMON was caught on -- where AskName wipes to white.  The prompt is
-- the engine's own and is left exactly as it built it; only what is behind it
-- changes.
--
-- and the overworld START menu's dex row, renamed to DEX through the
-- ui.start_menu.items hook rather than by touching the menu itself.
--
-- The two sibling files are loaded rather than required because a mod cannot
-- put itself on package.path: mod:read hands back the file's source from
-- wherever the mod actually lives (an installed directory, or inside an
-- imported .zip), and load() names the chunk after that path so a syntax
-- error in list.lua reports as list.lua and not as a line in this file.
-- The same pattern the rest of the set uses.

local function loadSibling(mod, name)
  local source, readErr = mod:read(name)
  if not source then
    mod.log:error("%s is missing (%s); reinstall the mod", name,
                  tostring(readErr or "unknown read error"))
    return nil
  end
  local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s did not compile: %s", name, tostring(compileErr))
    return nil
  end
  local ok, value = pcall(chunk)
  if not ok then
    mod.log:error("%s failed to run: %s", name, tostring(value))
    return nil
  end
  return value
end

return function(mod)
  mod.options:define({
    -- Every POKéMON on the screen in its own species colours, over the plain
    -- grey ramp -- which is what makes the icons worth having and what the
    -- rest of this set looks like.  Off puts the vanilla dex brown back and
    -- asks for no zones at all, for anyone who wants the 1996 screen with the
    -- icons added and nothing else changed.
    { key = "species_colours", type = "toggle", label = "SPECIES COLOURS",
      default = true },
    -- SELECT on the list cycles numbered / A-Z / caught.  The engine leaves
    -- SELECT unbound on the dex list, so this takes nothing away: ListMenu
    -- only reads it when a screen supplies an onSelectKey.
    { key = "view_cycle", type = "toggle", label = "SELECT VIEWS",
      default = true },
    -- UP/DOWN on the entry's first two pages walks the species you have seen.
    -- Off leaves those keys dead there, which is what the vanilla page does.
    { key = "step_species", type = "toggle", label = "UP/DOWN SPECIES",
      default = true },
    -- UP on the first row and DOWN on the last cross to the other end. 151
    -- rows is a long way to hold a key when the one you want is at the far
    -- end, and the counts in the footer say where you are the whole time.
    { key = "wrap", type = "toggle", label = "LIST WRAPS", default = true },
    { key = "hold_scroll", type = "toggle", label = "HOLD TO SCROLL",
      default = true },
    -- The overworld START menu's dex row reads DEX rather than POKéDEX.
    -- Off hands the engine's row back exactly as it built it, for anyone who
    -- wants the 1996 menu with the dex screens changed and nothing else.
    { key = "dex_label", type = "toggle", label = "START SAYS DEX",
      default = true },
    -- A on an entry you have never met opens AREA on it, where vanilla
    -- refuses.  Off hands that press back to the engine, which is to say it
    -- does nothing at all -- the setting for anyone who would rather find
    -- the ones they have not met the hard way.
    { key = "area_unseen", type = "toggle", label = "AREA ON UNSEEN",
      default = true },
    -- The line under the AREA map: how you catch it, roughly what level, and
    -- how often.  Off leaves the AREA screen exactly as the cartridge drew
    -- it, blinking nests and nothing else -- and takes the caption away from
    -- any mod that registered one, because a player who turned hints off
    -- turned them off.
    { key = "area_hints", type = "toggle", label = "AREA HINTS",
      default = true },
    -- A over a town you can FLY to, on the AREA map, IS a flight.  The
    -- screen is the town map; if the party can fly and the cursor is over
    -- somewhere flyable, making you close it and come back through the START
    -- menu to reach the same map is the screen being pedantic about which
    -- door you came in by.  Off leaves A closing the screen, which is what it
    -- did before -- and it closes it anyway whenever a flight is not
    -- available, so nothing is ever swallowed.
    { key = "area_fly", type = "toggle", label = "FLY FROM AREA",
      default = true },
    -- The nickname prompt after a catch keeps the screen it interrupted --
    -- the dex entry for a species the dex has never held, the battle it was
    -- caught on for anything else -- rather than the white field AskName
    -- wipes to.  Off asks the question over the blank screen the cartridge
    -- asked it over, for anyone who wants the 1996 moment back, and it takes
    -- nothing else with it: the box, the words and the YES/NO are the
    -- engine's own either way.
    { key = "nickname_backdrop", type = "toggle", label = "NAME IN PLACE",
      default = true },
  })

  local DexData = loadSibling(mod, "dexdata.lua")
  local makeChrome = loadSibling(mod, "chrome.lua")
  local makeList = loadSibling(mod, "list.lua")
  local makeEntry = loadSibling(mod, "entry.lua")
  local makeArea = loadSibling(mod, "area.lua")
  local makeNaming = loadSibling(mod, "naming.lua")
  if not DexData then return end

  -- The chrome is shared by both screens, so it is built once and handed to
  -- each: a header box on the list that sits a pixel off the one on the entry
  -- reads as two mods rather than one.  Without it neither screen can draw,
  -- so this is the one failure that takes the whole Pokédex back to vanilla.
  local C
  if type(makeChrome) == "function" then
    local ok, built = pcall(makeChrome, mod)
    if ok and type(built) == "table" then C = built end
  end
  if not C then
    mod.log:error("the shared chrome did not build; leaving the vanilla dex")
    return
  end

  -- The AREA surface, built before the list because the list wires its rows
  -- into it.  Its own failure is survivable in a way the chrome's is not: no
  -- caption strip and no AREA on an unseen entry still leaves a Pokédex that
  -- draws, so this logs and carries on rather than returning.
  local Area
  if type(makeArea) == "function" then
    local ok, built = pcall(makeArea, mod, C)
    if ok and type(built) == "table" then
      Area = built
      local installed, err = pcall(Area.install)
      if not installed then
        mod.log:error("the AREA screen was not wrapped: %s", tostring(err))
      end
      -- Published whether or not the wrap took, because provide() is how
      -- another mod hands this screen its words and a caller that finds
      -- nothing to register with has no way to tell "absent" from "broken".
      mod.exports.area = {
        provide = Area.provide,
        caption = Area.caption,
        probe = Area.probe,
        -- the budget the SECOND line has, which is the tight one: the box
        -- puts its blinking prompt in that line's last column.  Published so
        -- a provider can decide what to leave out rather than have the box
        -- cut it off mid-word.
        cols = Area.CAPTION_COLS,
        -- what the box says when nothing answers, so a mod can read it rather
        -- than guess at it -- and match it, if it wants a blank of its own to
        -- be indistinguishable from an ordinary one
        unknown = Area.UNKNOWN,
      }
    else
      mod.log:error("the AREA screen did not build: %s", tostring(built))
    end
  end

  -- Registered independently: a failure building one screen leaves the other
  -- installed and the broken one on the builtin, rather than taking the whole
  -- Pokédex down with it.
  if type(makeList) == "function" then
    local ok, screen = pcall(makeList, mod, DexData, C, Area)
    if ok and type(screen) == "table" and type(screen.new) == "function" then
      mod.content.screens:register("PokedexMenu", screen)
    else
      mod.log:error("the dex list did not build: %s", tostring(screen))
    end
  end

  -- Narrowed to `new` on the way into the registry: the screens record is
  -- typed as exactly that one field, and the entry factory hands back a
  -- sibling seam beside it (Entry.recent, for the nickname backdrop below).
  local Entry
  if type(makeEntry) == "function" then
    local ok, screen = pcall(makeEntry, mod, DexData, C)
    if ok and type(screen) == "table" and type(screen.new) == "function" then
      Entry = screen
      mod.content.screens:register("DexEntryMenu", { new = screen.new })
    else
      mod.log:error("the dex entry did not build: %s", tostring(screen))
    end
  end

  -- The nickname prompt after a catch, asked over the screen it interrupted
  -- rather than over a blank white field.  Survivable in the same way the
  -- AREA screen is and for the same reason: the prompt is the engine's own
  -- either way, so a backdrop that will not install leaves the question the
  -- cartridge asked, on the screen the cartridge asked it on.  It is built
  -- with the entry screen because the page half of it keeps up the instance
  -- that page was drawn from.
  if Entry and type(makeNaming) == "function" then
    local ok, naming = pcall(makeNaming, mod, C, Entry)
    if ok and type(naming) == "table" then
      local installed, err = pcall(naming.install)
      if not installed then
        mod.log:error("the nickname prompt was not wrapped: %s", tostring(err))
      end
    else
      mod.log:error("the nickname backdrop did not build: %s", tostring(naming))
    end
  end

  -- The START menu row that opens the list reads DEX rather than POKéDEX.
  -- The engine builds that row as Strings("POKéDEX") and runs the finished
  -- list through ui.start_menu.items before the menu opens
  -- (src/ui/StartMenu.lua), so the row is renamed on the way past rather
  -- than by rebuilding the menu: its onSelect, its position and every other
  -- row are left exactly as the engine made them.  next() first and then
  -- decorate, so a mod that inserts a row of its own still gets one.
  --
  -- Matched on the looked-up label rather than on the English literal, so a
  -- translation mod's row is still the row that gets renamed -- and the new
  -- label goes through Strings too, so that mod can name it in its own
  -- language.  Nothing else that says POKéDEX moves: the SAVE panel's dex
  -- count and the list's own header are separate text.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    -- read per open rather than once at load, so flipping START SAYS DEX in
    -- the manager shows up the next time the menu is opened
    if not C.option("dex_label", true) then return out end
    local ok, Strings = pcall(require, "src.core.Strings")
    if not ok then return out end
    local vanilla, short = Strings("POKéDEX"), Strings("DEX")
    for _, item in ipairs(out) do
      if item.label == vanilla then item.label = short end
    end
    return out
  end)

  -- The pure builders, for the suite and for any mod that wants the same
  -- answers this screen is drawing without opening it.
  mod.exports.buildList = DexData.list
  mod.exports.buildMoves = DexData.moves
  mod.exports.buildMoveRows = DexData.moveRows
  mod.exports.buildStats = DexData.stats
  mod.exports.buildDescription = DexData.description
  mod.exports.seenSpecies = DexData.seenSpecies
  mod.exports.modeLabels = DexData.MODE_LABELS
  mod.exports.nextMode = DexData.NEXT_MODE

  mod.log:info("the Pokédex has icons")
end
