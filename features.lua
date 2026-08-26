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
  },

  features = {
    -- ---- the battle screen

    {
      id = "arena",
      priority = 50,
      dir = "Gen1Arena",
      entry = "main.lua",
      label = "BACKDROPS",
      description = "2D BACKDROPS BEHIND BATTLES, PICKED BY MAP, TILESET AND HOW THE ENCOUNTER STARTED.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen1Arena", "gen1arena" },
    },

    -- ---- the menus a player lives in
    --
    -- These three share priority 1100 upstream, so they install in the order
    -- written here.  That order is load-bearing: Gen1Party optionally reads
    -- Gen1Dex and Gen1BillsBox, and needs both registered ahead of it to
    -- resolve them through the bundle registry rather than the engine.

    {
      id = "dex",
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
      priority = 520,
      dir = "Gen1ModernBag",
      entry = "main.lua",
      label = "BAG",
      description = "SEVEN POCKETS WITH AUTO-SORTING, FAVORITES, PINNED ITEMS, SEARCH AND NO CAPACITY LIMIT.",
      default = true,
      aliases = { "Gen1ModernBag", "gen1_modern_bag" },
    },

    -- ---- the menus around them

    {
      id = "menus",
      priority = 900,
      dir = "Gen1MenuManager",
      entry = "main.lua",
      label = "MENU LAYOUT",
      description = "REORDER THE START AND PC MENUS, HIDE ROWS YOU NEVER TOUCH, AND PIN FIELD MOVES TO ROWS OF THEIR OWN.",
      default = true,
      aliases = { "Gen1MenuManager" },
    },

    {
      id = "modmenu",
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
    },
  },
}
