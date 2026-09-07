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
  -- ------- which arm, asked once
  --
  -- Read before the schema, because the rows differ, and before the siblings
  -- are LOADED, because on Gold most of them must not be: list.lua and
  -- entry.lua reach `PartyMenu.drawIcon` and `BattleState.askNicknameUI`,
  -- neither of which Gold has, and they register over `PokedexMenu` and
  -- `DexEntryMenu` -- two ids Gold never builds, its own being
  -- `Gen2PokedexMenu`.
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
    -- Crystal animates a POKeMON's picture when its #DEX entry opens, the way
    -- the SUMMARY page already does.  Off leaves the still picture the entry
    -- drew before.  On Gold and Silver there are no frames to play and the row
    -- changes nothing.
    { key = "dex_anim", type = "toggle", label = "DEX ANIMATION",
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
    -- Off takes the FLY row off that map's menu and nothing else: INSPECT is
    -- still there, and MAP INSPECT below still governs the menu itself.
    -- Neither toggle can switch the other off.
    -- The nickname prompt after a catch keeps the screen it interrupted --
    -- the dex entry for a species the dex has never held, the battle it was
    -- caught on for anything else -- rather than the white field AskName
    -- wipes to.  Off asks the question over the blank screen the cartridge
    -- asked it over, for anyone who wants the 1996 moment back, and it takes
    -- nothing else with it: the box, the words and the YES/NO are the
    -- engine's own either way.
    { key = "nickname_backdrop", type = "toggle", label = "NAME IN PLACE",
      default = true },
    -- A on a town-map location opens a small menu -- INSPECT, and FLY as well
    -- when there is somewhere under the cursor to fly to -- instead of the
    -- press doing one fixed thing.  INSPECT lists what lives there, richest
    -- share first, off the live encounter tables, with the dex's own caught
    -- ball and the dex's own silence about anything you have not seen.
    --
    -- All three maps, the AREA screen included: it is the same picture with a
    -- species pinned to it, the cursor is on a town while you read it, and
    -- going out to the BAG for the same map to ask what lives there was the
    -- screen being pedantic about which door you came in by.  Off leaves A
    -- exactly as it was -- nothing at all on the BAG's map, the flight on the
    -- other two.
    { key = "map_inspect", type = "toggle", label = "MAP INSPECT",
      default = true },
  }

  -- ------- the rows, per generation
  --
  -- Ten of the eleven above are settings for screens this mod REPLACES, and
  -- on Gold it replaces none of them: the list, the search, the AREA map and
  -- the nickname prompt are all the cart's there.  A row that cannot do
  -- anything is worse than a missing one -- it is a switch the player flips
  -- and watches not work -- so Gold gets the one row that governs what this
  -- mod actually adds there.
  local GEN2_ROWS = {
    gen2_pages = true,
    -- The START menu is on both cartridges, so this row always meant
    -- something here -- it was simply never installed (see installDexLabel).
    dex_label = true,
    -- The line under the AREA map.  Gold's AREA page is the cart's, but the
    -- caption under it is this mod's on both cartridges -- see gen2area.lua,
    -- which reads Gold's own encounter tables and draws one row at the very
    -- bottom of the map.  So the row means here exactly what it means on Red:
    -- off is the cartridge's AREA page and nothing else.
    area_hints = true,
    -- And the press that reaches it.  Gold refuses A on an undiscovered row
    -- exactly the way Red does, so the row means the same thing on both --
    -- with more behind it here, because on Gold AREA is an action ON the
    -- entry rather than a screen of its own, so the entry opens too.  Masked;
    -- see gen2unseen.lua.
    area_unseen = true,
    -- Crystal's front pics carry an animation and the SUMMARY page already
    -- plays it; the #DEX entry did not.  Gold and Silver caches have no
    -- `anim` row at all, so on those two the row governs nothing -- it is
    -- the CART that decides, not the generation, so a cache with animation
    -- added by a mod gets it too.  See gen2anim.lua.
    dex_anim = true,
  }

  -- The LIST's own rows: SELECT's three views, the cursor wrap and the
  -- coloured names.  They mean the same thing on both carts, but only once
  -- the list is this mod's -- so they are offered only when DEX LIST is on.
  --
  -- With Gold's own dex as the default (below), leaving them on the menu
  -- unconditionally would have put three controls there that do nothing,
  -- which is the complaint that started the Gen 2 work in the first place:
  -- "none of our start qol options are working on gen 2 like they did in
  -- gen 1".  A row that cannot act is worse than a row that is not there.
  --
  -- Read before `define`, which is fine: optionset.read answers from the
  -- player's stored settings and does not need the row to exist yet.  No
  -- stored answer means no list, which is the same test the registration
  -- below makes -- so the menu and the screen cannot disagree.
  local GEN2_LIST_ROWS = {
    view_cycle = true,
    wrap = true,
    species_colours = true,
  }

  if isGen2 then
    local listOn = mod.options:get("gen2_list") == true
    local kept = {}
    for _, row in ipairs(schema) do
      if GEN2_ROWS[row.key] or (listOn and GEN2_LIST_ROWS[row.key]) then
        kept[#kept + 1] = row
      end
    end
    -- STATS, EVOLVES and MOVES on the entry screen.  Live: the wrap reads it
    -- on every frame and every press, so OFF is Gold's own two-page entry
    -- back with nothing to relaunch.
    kept[#kept + 1] = { key = "gen2_pages", type = "toggle",
      label = "EXTRA DEX PAGES", default = true }
    -- This mod's list in place of the cart's: the icon column, the ball
    -- column, the SEEN/OWN footer and SELECT's three views.  Off is Gold's
    -- own list back, exactly as the cartridge draws it -- which is why it is
    -- a switch and not an assumption.
    --
    -- OFF by default now, because that is the dex that was asked for:
    -- "I do want to use the gold Pokedex", and then "we want to use the gold
    -- dex now, but fix some things".  Gold's own list is the better starting
    -- point on this cartridge -- it already runs the whole 251, already opens
    -- on the Johto order out of `dex.newOrder`, and already has the cart's
    -- three sorts behind SELECT, all of which this mod's list had to be taught
    -- one bug at a time.  What it needs is theming, not replacing.
    --
    -- Still a switch, and still built: a player who turned it ON keeps it,
    -- and turning it on is how the icon column and the ball column come back.
    kept[#kept + 1] = { key = "gen2_list", type = "toggle",
      label = "DEX LIST", default = false }
    schema = kept
  end

  mod.options:define(schema)

  -- ------- START SAYS DEX, which is not a Gen 1 row
  --
  -- It renames the overworld START menu's dex entry, and that menu is on both
  -- cartridges.  It used to be registered at the BOTTOM of this file, below
  -- the generation branch -- so a Gold boot returned before ever reaching it,
  -- and the row was neither offered nor installed.  One of the START menu
  -- options that "stopped working on Gen 2".
  --
  -- Declared here, above the branch, and installed by whichever arm runs.
  local function installDexLabel(option)
    mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      local out = next(game, items)
      if type(out) ~= "table" then return out end
      -- read per open rather than once at load, so flipping START SAYS DEX in
      -- the manager shows up the next time the menu is opened
      if not option("dex_label", true) then return out end
      local ok, Strings = pcall(require, "src.core.Strings")
      if not ok then return out end
      -- Both the translated word and the source one: Gold hands hooks its rows
      -- before it translates them, so the translated form alone finds nothing
      -- there once a translation is installed.  Identical strings in English.
      local vanilla, source = Strings("POKéDEX"), Strings.source("POKéDEX")
      for _, item in ipairs(out) do
        if item.label == vanilla or item.label == source then
          item.label = item.translateLabel and Strings.source("DEX")
            or Strings("DEX")
        end
      end
      return out
    end)
  end

  local DexData = loadSibling(mod, "dexdata.lua")

  -- ------- what this mod publishes
  --
  -- The whole of dexdata.lua, and it is published BEFORE the generation
  -- branch on purpose: it is pure, it reads Gen 1 and Gen 2 datasets alike
  -- (see `DexData.statKeys`), and it is this mod's public surface.  A sibling
  -- that asks for `buildStats` should get it whichever cart is running --
  -- losing it on Gold would be a silent regression for anything built on it.
  mod.exports.buildList = DexData.list
  mod.exports.buildMoves = DexData.moves
  mod.exports.buildMoveRows = DexData.moveRows
  mod.exports.buildStats = DexData.stats
  mod.exports.buildDescription = DexData.description
  mod.exports.seenSpecies = DexData.seenSpecies
  mod.exports.modeLabels = DexData.MODE_LABELS
  mod.exports.nextMode = DexData.NEXT_MODE

  if isGen2 then
    -- Gold's dex keeps its list, its search and its AREA screen; what it has
    -- no answer for is base stats, evolutions and the learnset, and that is
    -- all this adds.  See gen2.lua.
    installDexLabel(function(key, fallback)
      local value = mod.options:get(key)
      if value == nil then return fallback end
      return value
    end)

    local Gen2Dex = loadSibling(mod, "gen2.lua")
    local arm = Gen2Dex.new(mod, DexData)
    local ok, problem = pcall(arm.install)
    if not ok then
      mod.log:error("the Gold dex pages did not install: %s", tostring(problem))
    end

    -- ------- and the line under the AREA map
    --
    -- Built and published whether or not the wrap took, for the reason the
    -- Gen 1 arm gives at the same place: `provide` is how another mod hands
    -- this screen its words, and a caller that finds nothing to register with
    -- has no way to tell "absent" from "broken".  Its failure is survivable --
    -- an AREA page with blinking nests and no caption is the cartridge's own
    -- AREA page -- so this logs and carries on.
    local makeGen2Area = loadSibling(mod, "gen2area.lua")
    if type(makeGen2Area) == "function" then
      local areaOk, Area = pcall(makeGen2Area, mod, DexData)
      if areaOk and type(Area) == "table" then
        local installed, why = pcall(Area.install)
        if not installed then
          mod.log:error("the Gold AREA caption was not wrapped: %s",
                        tostring(why))
        end
        -- The same four names Red publishes, so a mod that captions a species
        -- registers once and gets both cartridges.  `cols` is one number here
        -- rather than the second line's budget, because the strip is one line.
        mod.exports.area = {
          provide = Area.provide,
          caption = Area.caption,
          probe = Area.probe,
          cols = Area.COLS,
          unknown = Area.UNKNOWN,
        }
      else
        mod.log:error("the Gold AREA caption did not build: %s", tostring(Area))
      end
    end

    -- ------- and the picture moves, where the cart has frames for it
    --
    -- Built before the pic placeholder and the mask so both wrap outside it: a
    -- species with no picture never reaches an animation, and a masked entry's
    -- question mark is not something to animate either.
    local makeAnim = loadSibling(mod, "gen2anim.lua")
    if type(makeAnim) == "function" then
      local animOk, Anim = pcall(makeAnim, mod, DexData)
      if animOk and type(Anim) == "table" then
        local installed, why = pcall(Anim.install)
        if not installed then
          mod.log:error("the #DEX animation was not wrapped: %s", tostring(why))
        end
      else
        mod.log:error("the #DEX animation did not build: %s", tostring(Anim))
      end
    end

    -- ------- the pic the cart cannot find
    --
    -- Built before the mask, so the mask's wrap sits outside this one too.
    -- `PokedexMenu:drawPic` returns silently before it draws ANYTHING when a
    -- species' picture does not resolve, which is a black square on the page
    -- and no way to tell it from the mod not being installed.  This puts the
    -- cart's own question mark there instead and says once, in the log, which
    -- link broke.  See gen2pic.lua.
    local makePic = loadSibling(mod, "gen2pic.lua")
    if type(makePic) == "function" then
      local picOk, Pic = pcall(makePic, mod, DexData)
      if picOk and type(Pic) == "table" then
        local installed, why = pcall(Pic.install)
        if not installed then
          mod.log:error("the missing-pic placeholder was not wrapped: %s",
                        tostring(why))
        end
      else
        mod.log:error("the missing-pic placeholder did not build: %s",
                      tostring(Pic))
      end
    end

    -- ------- and the press that reaches it
    --
    -- Last of the three, and deliberately: its wraps have to sit OUTSIDE the
    -- other two.  The mask works by shadowing four of the screen's own methods
    -- for the duration of one call, so it has to be the outermost wrap for the
    -- extra pages and the AREA caption to draw underneath it already masked --
    -- an inner wrap would run before the shadows were in place and name the
    -- POKeMON in the middle of a screen built to hide it.
    --
    -- Its failure is survivable and fails CLOSED: without it Gold's own dead
    -- press on an undiscovered row is back, which is the cartridge.
    local makeUnseen = loadSibling(mod, "gen2unseen.lua")
    if type(makeUnseen) == "function" then
      local unseenOk, Unseen = pcall(makeUnseen, mod, DexData)
      if unseenOk and type(Unseen) == "table" then
        local installed, why = pcall(Unseen.install)
        if not installed then
          mod.log:error("AREA ON UNSEEN was not wrapped on Gold: %s",
                        tostring(why))
        end
      else
        mod.log:error("AREA ON UNSEEN did not build on Gold: %s",
                      tostring(Unseen))
      end
    end

    -- ------- and the list, in this suite's own shape
    --
    -- Registered over the cart's `Gen2PokedexMenu`, which is the id Gold
    -- pushes.  Everything the list does not draw is handed back to the cart's
    -- own screen -- the entry, the AREA map with its blinking nests across
    -- both regions, SEARCH and UNOWN MODE -- by building one and pointing it
    -- at the species the cursor is on.  So nothing Gold has is
    -- re-implemented to stand still, and this is a list rather than a
    -- Pokédex.
    --
    -- The chrome is the same file both games' screens draw from, which is
    -- what makes this the same screen on both carts rather than two that
    -- resemble each other.  Without it the list cannot draw, so a chrome that
    -- did not build leaves Gold's own list alone.
    if mod.options:get("gen2_list") == true then
      local makeChrome = loadSibling(mod, "chrome.lua")
      local makeGen2List = loadSibling(mod, "gen2list.lua")
      local C
      if type(makeChrome) == "function" then
        -- `true` is the generation: on Gold the chrome reads the theme's
        -- live palette for its paper and ink, because nothing reverses the
        -- frame afterwards the way Red's SGB zones do.
        local chromeOk, built = pcall(makeChrome, mod, true)
        if chromeOk and type(built) == "table" then C = built end
      end
      if not (C and type(makeGen2List) == "function") then
        mod.log:warn("the shared chrome did not build; Gold keeps its own "
          .. "dex list")
      else
        local listOk, List = pcall(makeGen2List, mod, DexData, C)
        if not (listOk and type(List) == "table"
                and type(List.new) == "function") then
          mod.log:error("the Gold dex list did not build: %s", tostring(List))
        else
          -- Screens.resolve prefers the registry over the builtin module, so
          -- registering the cart's own id is what puts this list in front of
          -- it -- and a boot without this mod still finds Gold's.
          mod.content.screens:register("Gen2PokedexMenu", { new = List.new })
          mod.log:info("the POKeDEX list is this suite's on Gold")
        end
      end
    end
    return
  end

  local makeChrome = loadSibling(mod, "chrome.lua")
  local makeList = loadSibling(mod, "list.lua")
  local makeEntry = loadSibling(mod, "entry.lua")
  local makeArea = loadSibling(mod, "area.lua")
  local makeInspect = loadSibling(mod, "inspect.lua")
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
  -- INSPECT rides the town map rather than the dex, but it is the dex's
  -- question asked from the other end -- the same encounter walk, the same
  -- tiers, the same caught ball and the same silence -- so it is built here
  -- and its failure is survivable in the same way the AREA screen's is: a
  -- town map with A doing what it always did is still a town map.
  local Inspect
  if type(makeInspect) == "function" then
    local ok, built = pcall(makeInspect, mod, C)
    if ok and type(built) == "table" then
      Inspect = built
      local installed, err = pcall(Inspect.install)
      if not installed then
        mod.log:error("map INSPECT was not wrapped: %s", tostring(err))
      end
      mod.exports.inspect = {
        roster = Inspect.roster,
        mapsFor = Inspect.mapsFor,
        detail = Inspect.detail,
      }
    else
      mod.log:error("map INSPECT did not build: %s", tostring(built))
    end
  end

  local Area
  if type(makeArea) == "function" then
    -- Inspect goes in because A over the AREA map opens ITS menu; nil is
    -- allowed and means the map keeps the press it had before.
    local ok, built = pcall(makeArea, mod, C, Inspect)
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
  installDexLabel(function(key, fallback)
    return C.option(key, fallback)
  end)

  -- The pure builders, for the suite and for any mod that wants the same
  -- answers this screen is drawing without opening it.

  mod.log:info("the Pokédex has icons")
end
