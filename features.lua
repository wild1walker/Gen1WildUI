-- What is in Gen1WildUI, and how each piece is switched.
--
-- This is the whole of the bundle's configuration.  Adding a mod to the visual
-- half is an entry here plus a submodule; nothing in runtime/ changes.
--
-- Fields:
--   id           the option prefix and the menu screen suffix.  Never change
--                one after release: it is what the player's stored settings
--                are keyed on.
--   dir          the folder under modules/, written by tools/build.py
--   entry        the upstream mod's own entry chunk, from its manifest
--   label        the row in the menu
--   description  shown on A when the feature has no settings of its own
--   group        which folder card in `spec.groups` this feature's row sits
--                on.  A feature naming no card, or one that is not declared,
--                gets a plain row on the top level instead of being hidden.
--   enabledKey   the upstream option row that already acts as a master
--                switch.  Present means the switch is live -- the feature's
--                own code reads it every time it acts, so OFF is the
--                untouched game with no relaunch.  Absent means the bundle
--                synthesizes a switch and gates installation with it, which
--                takes a relaunch to change.
--   default      what that switch ships as
--   defaults     bundle-level overrides for any upstream row's default
--   aliases      every name a sibling might call this feature by, for
--                mod.find
--   priority     the upstream manifest's own load priority.  Features install
--                in ascending priority, ties in declaration order -- which is
--                the order these mods were built and tested against.  It is
--                deliberately independent of the order they are written here,
--                which is the order the menu reads them in.
--   shared       this feature is carried by both bundles.  Exactly one may
--                install it, so the first to load claims it and the other
--                stands down; `storage` is the id its settings live under, so
--                they do not move when the winner does.  See runtime/claims.lua.
--   adapter      a file under adapters/, run after the feature installs
--   suppress_hooks  engine hooks the feature must not register, because the
--                bundle surfaces that setting itself
--   raw_option_keys  rows this feature writes by calling the engine's mod
--                manager, which does not know about prefixes

return {
  spec = {
    id = "gen1_wild_ui",
    menu_label = "GEN1WILD UI",
    screen_id = "Gen1WildUI",
    -- Gen151 lives in the QOL bundle and wants Gen1Dex, which lives here.
    -- This is the hop that keeps that working -- and MENU LAYOUT's hop to the
    -- SELECT menu's row registry, which is published by EASY HM USE over
    -- there under the alias FieldMenu.
    --
    -- THE NIGHTLY ID, not the stable one.  Forking the two bundles renamed
    -- them both, and this line kept pointing at `gen1_wild_qol` -- a mod the
    -- nightly cart does not install.  Every lookup from this side across to
    -- that one failed silently, which is exactly what a registry lookup does
    -- when it cannot find the mod: nothing, quietly.  The SELECT menu was not
    -- arrangeable because the manager never found the registry to join.
    --
    -- tools/check.py said so on every run -- "Gen1WildQOL not on disk;
    -- cross-check skipped" -- and that line was read as the cross-check being
    -- unavailable in a single-bundle checkout rather than as this being
    -- wrong.  The other half had already been updated: the QOL bundle names
    -- `gen1_wild_ui_nightly`.
    paired_bundle = "gen1_wild_qol",

    -- Mods the cart pins that get a door of their own at the top of the
    -- menu, rather than sitting under OTHER MODS with the mods a player
    -- installed themselves.
    --
    -- Wild Green's player recolour is the whole reason the cart is called
    -- what it is, and reaching it read WILD GREEN > OTHER MODS > MAKE IT
    -- GREEN > the row -- three doors deep, behind the repository's name
    -- rather than the setting's.  `label` is what the settings ARE.
    --
    -- Both halves declare the same list, for the same reason both declare
    -- the same cards below: either can end up hosting the merged menu.  An
    -- id that is not loaded simply has no row.
    -- Both ids, because a nightly cart pins the nightly Wild Green and
    -- somebody running this bundle beside the stable mod has the other one.
    -- An id that is not loaded has no schema and so has no row; listing both
    -- costs a lookup and saves a door being missing on one of the two.
    adopted = {
      { mod = "wild_green_nightly", label = "PLAYER",
        description = "WHAT YOUR CHARACTER WEARS, THE NAMES THE GAME OFFERS, "
          .. "AND THE TITLE SCREEN." },
      { mod = "wild_green", label = "PLAYER",
        description = "WHAT YOUR CHARACTER WEARS, THE NAMES THE GAME OFFERS, "
          .. "AND THE TITLE SCREEN." },
    },

    -- The folder cards the menu nests its rows under, in the order they are
    -- drawn.  Both halves of the suite declare the same six, because either
    -- half can end up hosting the merged menu and it should read the same way
    -- round whichever one the player opened.  A card with nothing in it is not
    -- drawn, so a half that has no features for a card simply does not show it.
    groups = {
      { id = "general",   label = "GENERAL",
        description = "MOVING AROUND, AND THE THINGS THE GAME DOES ON ITS OWN." },
      { id = "pokemon",   label = "POKEMON",
        description = "THE POKEMON THEMSELVES AND THE SCREENS ABOUT THEM." },
      { id = "battle",    label = "BATTLE",
        description = "WHAT A BATTLE LOOKS LIKE AND HOW IT PLAYS." },
      { id = "items",     label = "ITEMS",
        description = "THE BAG, THE MART, AND WHAT EVERY ITEM IS FOR." },
      { id = "save",      label = "SAVE",
        description = "SAVING, AND PICKING UP WHERE YOU LEFT OFF." },
      { id = "interface", label = "INTERFACE",
        description = "THE MENUS AND SCREENS EVERYTHING ELSE IS REACHED THROUGH." },
    },
  },

  features = {
    -- ---- the battle screen

    {
      id = "arena",
      group = "battle",
      priority = 50,
      dir = "Gen1Arena",
      entry = "main.lua",
      label = "BACKDROPS",
      description = "2D BACKDROPS BEHIND BATTLES, PICKED BY MAP, TILESET AND HOW THE ENCOUNTER STARTED.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen1Arena", "gen1arena" },
      -- Runs on Gold, Silver and Crystal.
      --
      -- The seam there is cleaner than Red's: the battle field is one
      -- `Chrome.clear()` call, the first line of `BattleState:drawPanel`
      -- (src/ui/gen2/BattleState.lua:4246) and the only one in the file, so
      -- the backdrop goes in ahead of that instead of behind Red's
      -- geometry-matched `love.graphics.rectangle` shim.
      --
      -- What made this look like a content problem is that the art is named
      -- after Kanto.  It is not drawn for Kanto.  All twenty backdrops are
      -- FireRed TERRAIN scenes -- grass, forest, cave, sea, pond, beach,
      -- craggy, snow, ice cave, desert, volcano -- and Johto is made of the
      -- same terrain.  What was Kanto-specific was the ASSIGNMENT, and that
      -- is a table.
      --
      -- Two of the three inputs are better here than on Red, because Gold's
      -- map header carries what Red made this mod guess: `environment` says
      -- whether a map is a town, a route, a cave or a room, so an unmapped
      -- tileset still lands somewhere right; and the roof colours are in the
      -- data, so a town variant is generated rather than hand-listed.
      --
      -- See modules/Gen1Arena/main.lua for the three tables and
      -- tools/make_gen2_towns.py for the town recolours.
    },

    {
      id = "widescreen",
      group = "battle",
      priority = 100,
      dir = "WidescreenBattleIntro",
      entry = "main.lua",
      label = "BATTLE INTRO",
      description = "THE BATTLE INTRO FLASH ACROSS THE WHOLE WINDOW INSTEAD OF A CENTRED 4:3 SQUARE, PLUS FLASHLESS INTROS AND A FADE TO BLACK.",
      default = true,
      aliases = { "widescreen_battle_intro", "WidescreenBattleIntro" },
      -- Originally ShaneMcGovernIE's gen1recomp-widescreen-battle-intro,
      -- maintained here now rather than tracked: the source is under
      -- maintained/WidescreenBattleIntro and edits go straight in.
      maintained = true,
      -- It keeps its two settings in the save's own options rather than in a
      -- mod.options schema, so the bundle does not try to move their storage
      -- -- the adapter mirrors the rows onto the bundle's screen and the
      -- upstream registration is suppressed, so each has one home.
      adapter = "widescreen",
      suppress_hooks = { ["ui.options.rows"] = true },
      -- Runs on Gold, Silver and Crystal -- for its two SETTINGS, not for
      -- the widescreen.
      --
      -- The widescreen half is Red's problem and stays there.  Gold's battle
      -- already fills the window (`BattleState:drawsWidescreen` answers true,
      -- src/ui/gen2/BattleState.lua:317) and Gold never calls Renderer at all,
      -- so the endFrame overlay and the poison-pulse bands have nothing to fix
      -- and nowhere to attach.  The module stands both down on a Gen 2 boot.
      --
      -- FLASHLESS INTROS and BLACK OUTRO are a different matter: neither is
      -- about aspect ratio, both were missing on Gold, and both are reachable
      -- there once you stop looking for Red's seam.
      --
      -- The flash on Red is a property of the WIPE -- the spiral defs carry no
      -- flash flag -- so the setting is a `transition.style` hook.  On Gold it
      -- is a PHASE every transition runs before its wipe, and all four of
      -- Gold's wipes run after it, so no style names a flashless intro there
      -- (and Red's "spiralout" is not among the four at all -- it would fall
      -- back to the vanilla select and change nothing).  The Gen 2 arm shortens
      -- the phase instead.
      --
      -- The white flash out of a battle is `Transition.battleReturn` on Red and
      -- `World:battleReturnFade` on Gold, and Gold's is the better seam: it
      -- picks a ramp out of `World.FADE_RAMP`, which already carries `black`
      -- beside `white`.  So BLACK OUTRO on Gold draws nothing of its own -- it
      -- names the other ramp and the cart's own fade plays in black.
      --
      -- See modules/WidescreenBattleIntro/main.lua for both.
      
    },

    {
      id = "battlemenus",
      group = "battle",
      priority = 1100,
      dir = "Gen1BattleUI",
      entry = "main.lua",
      label = "BATTLE MENUS",
      description = "THE BATTLE COMMAND AND MOVE MENUS AS FOUR BUTTONS IN A 2X2 GRID INSTEAD OF A LIST, PLUS THE BATTLE XP BAR.",
      -- No master row of its own to donate: MOVE PANEL is a setting within
      -- the grid, not a switch for it, and the mod is the grid. So the
      -- bundle synthesizes one and gates installation with it, which is why
      -- this row takes a relaunch and carries the menu's asterisk.
      default = true,
      aliases = { "Gen1BattleUI" },
      -- Both games, and they get very different amounts of it.
      --
      -- Gold shipped most of what this mod was built to add to Red, and the
      -- feature gate said so for six releases:
      --
      --   The 2x2 LAYOUT: `BattleState:drawPanel` lays its menu labels out at
      --   `col = ((i - 1) % 2) * spacing` and `row = floor((i - 1) / 2) * 2`
      --   (src/ui/gen2/BattleState.lua), which is the grid this mod builds
      --   for Red out of Red's four-row list.
      --
      --   The XP bar: Gold has one, animates it, and plays the cart's own
      --   Sfx_ExpBar and Sfx_HitEndOfExpBar while it fills.
      --
      --   The move menu: Gold's list carries a MoveInfoBox with the type and
      --   the PP of the highlighted move, which is what Red's arm has to
      --   build its own panel for.
      --
      -- What Gold did not ship is the FRAME.  Its four commands are four
      -- words in one box, not four buttons -- which is what "still no updated
      -- battle ui like we have for Gen 1 with the 2x2 selections" was about.
      -- So the Gold arm is that and nothing else: four boxes over the cart's
      -- one, with the cart's own labels and the cart's own cursor in them.
      -- See modules/Gen1BattleUI/gen2grid.lua.
    },

    -- ---- the menus a player lives in
    --
    -- These three share priority 1100 upstream, so they install in the order
    -- written here.  That order is load-bearing: Gen1Party optionally reads
    -- Gen1Dex and Gen1BillsBox, and needs both registered ahead of it to
    -- resolve them through the bundle registry rather than the engine.

    {
      id = "dex",
      group = "pokemon",
      priority = 1100,
      dir = "Gen1Dex",
      entry = "main.lua",
      label = "POKEDEX",
      description = "THE POKEDEX WITH A POKEMON BESIDE EVERY ENTRY, BASE STATS, EVOLUTIONS, MOVES AND AN AREA SCREEN.",
      default = true,
      aliases = { "Gen1Dex" },
      -- Runs on Gold, Silver and Crystal -- as three extra pages on the
      -- cart's own entry screen rather than as a replacement dex.
      --
      -- Gold's Pokedex is good, and already carries two of the three things
      -- this mod was built to add to Red's: an AREA screen with blinking
      -- nests, and a working search with NEW / OLD / A-Z on SELECT.  What it
      -- has no answer for is the third -- base stats, evolutions and the
      -- learnset -- so that is all the Gold arm adds, and it adds it where
      -- the cart already has a control that means "next page": PAGE counts on
      -- past its two into STATS, EVOLVES and MOVES.
      --
      -- Everything above the entry's divider stays the cart's on every page,
      -- so they read as more of the same entry rather than a second screen
      -- wearing its frame.  See modules/Gen1Dex/gen2.lua.
      --
      -- The AREA page is the cart's too, with one row added at the very bottom
      -- of the map: how you catch it, roughly what level, and -- where Gold's
      -- tables can say so -- at what hour and how often.  The blinking nests
      -- read grass, water and the roamers and nothing else, so a HEADBUTT-only
      -- POKeMON opens a page with an empty map, and that line is the only
      -- thing on the screen that can tell the player why.  AREA HINTS turns it
      -- off.  See modules/Gen1Dex/gen2area.lua.
      --
      -- And A on an undiscovered row opens that entry, where the cartridge
      -- refuses -- which is the same AREA ON UNSEEN row Red has, with more
      -- behind it, because on Gold AREA is an action ON the entry.  The name,
      -- the kind, the footprint and the cry are all withheld and the pic stays
      -- the question mark, so what opens is the number, an empty frame and the
      -- nest map.  See modules/Gen1Dex/gen2unseen.lua.
    },

    {
      id = "box",
      group = "pokemon",
      priority = 1100,
      dir = "Gen1BillsBox",
      entry = "main.lua",
      label = "POKEMON BOX",
      description = "REPLACES BILL'S PC WITH A REAL BOX: THE PARTY LEFT, TWENTY SLOTS RIGHT, AND A CURSOR THAT CARRIES A POKEMON.",
      default = true,
      aliases = { "Gen1BillsBox" },
      -- Gen 1 only, because Gold already has the screen this builds.
      --
      -- This mod exists because Red's Bill's PC is a text list: WITHDRAW,
      -- DEPOSIT, a name at a time, no picture, no party beside it.  Gold's is
      -- a box -- `src/ui/gen2/BoxMenu.lua`, transcribed from
      -- engine/pokemon/bills_pc.asm -- with the box name in its own panel,
      -- five nicknames down the right, and a left panel carrying the front
      -- pic, the level, the gender and the species of whatever the cursor is
      -- on.  MOVE POKéMON is there too, walking the party and the box the way
      -- _MovePKMNWithoutMail does.
      --
      -- ------- and that verdict was too generous by half
      --
      -- Gold's storage is a LIST.  `.PlaceNickname` writes five nicknames
      -- from (9,4), two rows apart, with a left panel carrying the front
      -- pic, the level, the gender and the species of whichever one the
      -- cursor is on.  It is a good list.  It is not a box: there is no
      -- grid, the party is not on screen beside it, and moving a POKeMON is
      -- a four-step modal flow reached from a third row on the PC menu.
      --
      -- The thing this mod builds -- the party down the left, the open box
      -- as a grid on the right, and a cursor that picks a POKeMON up and
      -- puts it down -- is what NEITHER game shipped.  So it runs on Gold
      -- too, and it replaces the list: `Gen2BoxMenu` is the id PcMenu pushes
      -- for all three of WITHDRAW, DEPOSIT and MOVE POKéMON, so the three
      -- verbs land on one screen and the PC menu keeps one door onto it.
      --
      -- Every write is the cart's own -- src/core/gen2/Boxes.lua's refusals
      -- and its two tails, enterBox and the withdraw heal -- because this is
      -- the one screen in the suite where a mistake loses a POKéMON.  See
      -- modules/Gen1BillsBox/gen2screen.lua.
    },

    {
      id = "party",
      group = "pokemon",
      priority = 1100,
      dir = "Gen1Party",
      entry = "main.lua",
      label = "PARTY MENU",
      description = "EVERY POKEMON IN ITS OWN SPECIES COLOURS INSTEAD OF ALL SIX SHARING ONE.",
      default = true,
      aliases = { "Gen1Party" },
    },

    {
      id = "bag",
      group = "items",
      priority = 520,
      dir = "Gen1ModernBag",
      entry = "main.lua",
      label = "BAG",
      description = "SEVEN POCKETS WITH AUTO-SORTING, FAVORITES, PINNED ITEMS, SEARCH AND NO CAPACITY LIMIT.",
      default = true,
      aliases = { "Gen1ModernBag", "gen1_modern_bag" },
      -- Runs on Gold, Silver and Crystal -- as three additions to the
      -- cart's own PACK rather than as a replacement bag.
      --
      -- Gold's PACK already has the two biggest things this mod gives Red's:
      -- pockets, with the cart's own tab strip, and a description under the
      -- list with a TM showing its MOVE's description.  What is left is how a
      -- pocket's list is BUILT, and that is one method -- `PackMenu:rebuild`
      -- -- so SORT, SEARCH and PIN happen after it and before the draw.
      --
      -- The capacity limit needed nothing at all: that patch is on
      -- `src.inventory.Bag`, which is shared, and Gold's own PackMenu orders
      -- its rows through it.
      --
      -- FAVOURITES is the one thing that did not port: on Red it is a virtual
      -- POCKET, and Gold's tab strip is four fixed pockets from the cart's own
      -- table.  PIN does the half of it that fits.  See
      -- modules/Gen1ModernBag/gen2.lua.
    },

    -- ---- the screens nothing else had got to
    --
    -- Two mods rather than one, because they are two things.  ITEM INFO is
    -- about items -- what they are, and the three screens that had nowhere to
    -- say it.  ELEVATOR PANEL is about a lift.  Folding the lift into a mod
    -- named for items would have made both names lie.
    --
    -- Both install last, and on purpose.  Each one wraps a widget
    -- constructor rather than overriding a screen id -- there is no id on a
    -- mart list, a PC list or a lift panel to override -- so going on late
    -- puts their wrapper on the outside of anything an earlier feature
    -- wrapped, and an earlier feature that replaces one of those widgets
    -- outright is still the thing they decorate.

    {
      id = "iteminfo",
      group = "items",
      priority = 1200,
      dir = "Gen1ItemInfo",
      entry = "main.lua",
      label = "ITEM INFO",
      description = "WHAT EVERY ITEM IS, IN THE MART, IN THE ITEM PC AND ON AN ABOUT ROW IN THE BAG -- AND THOSE SCREENS REDRAWN TO HAVE SOMEWHERE TO PUT IT.",
      enabledKey = "enabled",
      default = true,
      maintained = true,
      aliases = { "Gen1ItemInfo" },
      -- Gen 1 only, because Gold prints these already.
      --
      -- The whole of ITEM INFO is "these three screens have nowhere to say
      -- what an item is, so redraw them until they do".  On Gold all three
      -- say it out of the box: `PackMenu:description` and
      -- `MartMenu:description` both print the item's line under the list, and
      -- both substitute a TM's MOVE description for the TM's own.  The text
      -- is the cart's -- RomExtractorGen2 pulls `ItemDescriptions` straight
      -- out of the ROM -- so it is not even the same text this mod had to
      -- write for Red, it is the real thing.
      gen1_only = true,
    },

    {
      id = "elevator",
      group = "interface",
      priority = 1200,
      dir = "Gen1Elevator",
      entry = "main.lua",
      label = "ELEVATOR PANEL",
      description = "THE LIFT'S WHICH FLOOR? LIST AS A SMALL PANEL AGAINST THE EDGE, WITH THE CAR STILL ON THE SCREEN BEHIND IT.",
      enabledKey = "enabled",
      default = true,
      maintained = true,
      aliases = { "Gen1Elevator" },
      -- Gen 1 only, because Gold's lift is already the panel.
      --
      -- Red's WHICH FLOOR? is a full-screen list with the car gone behind it,
      -- which is the thing this mod fixes.  Gold's is two boxes transcribed
      -- from Elevator_AskWhichFloor: a "Now on:" panel at the top left and a
      -- four-row scrolling list at `menu_coords 12, 1, 18, 9` -- against the
      -- right edge, small, with the elevator still on the screen behind it
      -- (src/ui/gen2/ElevatorMenu.lua).
      --
      -- Same layout, same reasoning, already in the cart.
      gen1_only = true,
    },

    -- ---- the furniture
    --
    -- These two are in Gen1WildQOL as well, and deliberately.  They are not
    -- really visual overhauls: they are how every other feature is reached.
    -- A player who installs only the QOL half should not lose the mod manager
    -- redraw, and one who installs only this half should not lose it either
    -- -- so both carry them, and runtime/claims.lua makes sure only one of
    -- them ever installs one.
    --
    -- Their settings are stored under `gen1_wild_shared` rather than under
    -- either bundle, so which one won is invisible to the player.

    {
      id = "menus",
      group = "interface",
      priority = 900,
      dir = "Gen1MenuManager",
      entry = "main.lua",
      label = "MENU LAYOUT",
      description = "REORDER THE START AND PC MENUS, HIDE ROWS YOU NEVER TOUCH, AND PIN FIELD MOVES TO ROWS OF THEIR OWN.",
      default = true,
      aliases = { "Gen1MenuManager" },
      shared = {
        claim = "gen1wild_menu_manager",
        storage = "gen1_wild_shared",
        -- The fork renamed the bundles; this names one of them, so it is
        -- renamed too.  Same class of stale id as the paired_bundle this
        -- fork carried for eleven releases, and the same consequence in
        -- miniature: the fallback only runs when no engine module can hold
        -- the claim table, and with a name neither nightly bundle answers to
        -- BOTH stand down and the feature goes missing rather than being
        -- installed twice.  tools/check.py fails on a name no bundle here
        -- carries.
        owner = "gen1_wild_ui",
      },
    },

    {
      id = "modmenu",
      group = "interface",
      priority = 500,
      dir = "Gen1ModMenu",
      entry = "main.lua",
      label = "MOD MANAGER",
      description = "THE MOD MANAGER REDRAWN IN THE GAME'S OWN OPTION-SCREEN IDIOM, WITH SORTING AND FILTERS.",
      default = true,
      aliases = { "Gen1ModMenu", "gen1_mod_menu" },
      -- These three are set from this mod's own in-game quick menu, which
      -- goes through the engine manager's setOption and therefore writes
      -- them unprefixed.  Naming them keeps both spellings in step; see
      -- runtime/optionset.lua.
      raw_option_keys = { "sort", "hide_disabled", "only_options" },
      shared = {
        claim = "gen1wild_mod_menu",
        storage = "gen1_wild_shared",
        -- The fork renamed the bundles; this names one of them, so it is
        -- renamed too.  Same class of stale id as the paired_bundle this
        -- fork carried for eleven releases, and the same consequence in
        -- miniature: the fallback only runs when no engine module can hold
        -- the claim table, and with a name neither nightly bundle answers to
        -- BOTH stand down and the feature goes missing rather than being
        -- installed twice.  tools/check.py fails on a name no bundle here
        -- carries.
        owner = "gen1_wild_ui",
      },
    },
  },
}
