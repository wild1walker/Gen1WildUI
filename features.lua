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
    -- This is the hop that keeps that working.
    paired_bundle = "gen1_wild_qol",

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
        owner = "gen1_wild_ui",
      },
    },
  },
}
