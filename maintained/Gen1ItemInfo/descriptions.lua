-- What every item in Gen 1 is, in two lines.
--
-- Gen 1 has no item descriptions.  It has a name and a price on the mart
-- shelf and a name and a count in the bag, and that is the whole of what the
-- cartridge will ever tell you about an ITEMFINDER or an X ACCURACY -- item
-- descriptions arrive in Gen 2, with the PACK.  So the sentences have to come
-- from somewhere, and this is the somewhere.
--
-- ------- the shape of a line
--
-- TWO LINES, and every line at most eighteen glyphs.  Both halves of that are
-- load-bearing:
--
--   * eighteen is what a Gen 1 text box holds (Theme.textBox.maxCols, and
--     TextBox.paginate soft-wraps on it), so a longer line does not overflow
--     -- it WRAPS, silently, into a third line;
--   * and a third line is worse than an overflow, because the footer draws
--     the LAST two lines of what it is given, the way the GB's own scrolled
--     box does.  A description that wraps to three loses its first line and
--     nobody finds out.
--
-- tests/descriptions_test.lua holds both rules, so a description added here
-- without counting is a failing build rather than a truncated sentence.
--
-- ------- the voice
--
-- Gen 2's, because that is the generation these would have shipped in: plain
-- present tense, the effect first and the flavour after, no exclamation
-- marks, and the exact numbers wherever the item has one (a POTION says 20,
-- not "some").  Names of things the game capitalises stay capitalised.
--
-- ------- what is not here
--
-- TMs and HMs, which are named after the move they carry and described from
-- it at install (see main.lua) -- fifty-five hand-written lines that all say
-- the same thing would be fifty-five chances to disagree with the move data.
--
-- The FLOOR_* ids, which are elevator buttons rather than items: nothing ever
-- carries one, and no screen this mod draws can show one.
--
-- ITEM_2C and ITEM_32, the two unused ids the ROM's table still has room for.

return {
  -- ------- POKé BALLS

  MASTER_BALL   = "The best BALL. It\nnever misses.",
  ULTRA_BALL    = "A BALL with a\nbetter catch rate.",
  GREAT_BALL    = "A BALL with a good\ncatch rate.",
  POKE_BALL     = "A BALL thrown to\ncatch a POKéMON.",
  SAFARI_BALL   = "The BALL used in\nthe SAFARI ZONE.",

  -- ------- healing

  POTION        = "Restores 20 HP to\none POKéMON.",
  SUPER_POTION  = "Restores 50 HP to\none POKéMON.",
  HYPER_POTION  = "Restores 200 HP to\none POKéMON.",
  MAX_POTION    = "Fully restores the\nHP of one POKéMON.",
  FULL_RESTORE  = "Fully restores HP\nand cures status.",
  REVIVE        = "Revives a fainted\nPOKéMON. Half HP.",
  MAX_REVIVE    = "Revives a fainted\nPOKéMON. Full HP.",

  ANTIDOTE      = "Cures a POKéMON of\npoisoning.",
  BURN_HEAL     = "Heals a POKéMON of\na burn.",
  ICE_HEAL      = "Defrosts a frozen\nPOKéMON.",
  AWAKENING     = "Wakes a sleeping\nPOKéMON.",
  PARLYZ_HEAL   = "Frees a POKéMON\nfrom paralysis.",
  FULL_HEAL     = "Cures every status\nproblem.",

  ETHER         = "Restores 10 PP to\none move.",
  MAX_ETHER     = "Fully restores the\nPP of one move.",
  ELIXER        = "Restores 10 PP to\nevery move.",
  MAX_ELIXER    = "Fully restores the\nPP of every move.",

  -- ------- vitamins

  HP_UP         = "Raises the HP of\none POKéMON.",
  PROTEIN       = "Raises the ATTACK\nof one POKéMON.",
  IRON          = "Raises the DEFENSE\nof one POKéMON.",
  CARBOS        = "Raises the SPEED\nof one POKéMON.",
  CALCIUM       = "Raises the SPECIAL\nof one POKéMON.",
  RARE_CANDY    = "Raises a POKéMON's\nlevel by one.",
  PP_UP         = "Raises the max PP\nof one move.",

  -- ------- battle items

  X_ATTACK      = "Raises ATTACK\nduring one battle.",
  X_DEFEND      = "Raises DEFENSE\nduring one battle.",
  X_SPEED       = "Raises SPEED\nduring one battle.",
  X_SPECIAL     = "Raises SPECIAL\nduring one battle.",
  X_ACCURACY    = "Raises accuracy\nduring one battle.",
  GUARD_SPEC    = "Blocks stat drops\nduring one battle.",
  DIRE_HIT      = "Raises critical\nhits for a battle.",
  POKE_DOLL     = "Throw it to flee a\nwild POKéMON.",

  -- ------- evolution stones
  --
  -- One shape for all five: what it looks like, then what it does.  Which is
  -- the only honest thing to say about a stone -- the cartridge never tells
  -- you which POKéMON it is for either.

  MOON_STONE    = "A moon-like stone.\nEvolves POKéMON.",
  FIRE_STONE    = "A fire-red stone.\nEvolves POKéMON.",
  THUNDER_STONE = "A humming stone.\nEvolves POKéMON.",
  WATER_STONE   = "A sea-blue stone.\nEvolves POKéMON.",
  LEAF_STONE    = "A leaf-like stone.\nEvolves POKéMON.",

  -- ------- getting about

  ESCAPE_ROPE   = "A rope that pulls\nyou out of a cave.",
  REPEL         = "Keeps weak POKéMON\naway 100 steps.",
  SUPER_REPEL   = "Keeps weak POKéMON\naway 200 steps.",
  MAX_REPEL     = "Keeps weak POKéMON\naway 250 steps.",
  BICYCLE       = "A folding bike\nfaster than a run.",
  SURFBOARD     = "Ride it over the\nwater's surface.",
  TOWN_MAP      = "A handy map of\nall of KANTO.",
  POKEDEX       = "A device that\nrecords POKéMON.",

  -- ------- fishing

  OLD_ROD       = "An old fishing rod\nfor weak POKéMON.",
  GOOD_ROD      = "A good fishing rod\nfor better fish.",
  SUPER_ROD     = "The best fishing\nrod there is.",

  -- ------- drinks

  FRESH_WATER   = "Pure water. It\nrestores 50 HP.",
  SODA_POP      = "A fizzy drink. It\nrestores 60 HP.",
  LEMONADE      = "A sweet drink. It\nrestores 80 HP.",

  -- ------- key items

  OAKS_PARCEL   = "A parcel for PROF.\nOAK from a MART.",
  S_S_TICKET    = "A ticket aboard\nthe S.S.ANNE.",
  BIKE_VOUCHER  = "Trade it at the\nBIKE SHOP.",
  SECRET_KEY    = "The key to the\nCINNABAR GYM.",
  LIFT_KEY      = "The key to the\nROCKET lift.",
  CARD_KEY      = "A card key that\nopens SILPH doors.",
  GOLD_TEETH    = "False teeth lost\nby the WARDEN.",
  SILPH_SCOPE   = "It unmasks a ghost\nin POKéMON TOWER.",
  POKE_FLUTE    = "A flute that wakes\nsleeping POKéMON.",
  ITEMFINDER    = "It finds items\nhidden nearby.",
  EXP_ALL       = "Shares EXP with\nthe whole party.",
  COIN_CASE     = "It holds up to\n9999 GAME COINS.",

  -- ------- fossils and the things you sell

  DOME_FOSSIL   = "A shell fossil of\nan old POKéMON.",
  HELIX_FOSSIL  = "A spiral fossil of\nan old POKéMON.",
  OLD_AMBER     = "Ancient amber with\nDNA still in it.",
  NUGGET        = "A nugget of pure\ngold. Sells high.",
  COIN          = "A coin used at the\nGAME CORNER.",

  -- ------- badges
  --
  -- Never in the bag -- Bag.order filters them out and the trainer card is
  -- where they are looked at -- but they are items on the item table, and a
  -- description that says what a badge actually DOES is worth having wherever
  -- something chooses to show one.  The boosts are this engine's
  -- (Damage.BADGE_BOOSTS), not the cartridge's memory of them, and the field
  -- moves are FieldDefaults' gates.

  BOULDERBADGE  = "BROCK's BADGE.\nATTACK up. FLASH.",
  CASCADEBADGE  = "MISTY's BADGE.\nCUT works outside.",
  THUNDERBADGE  = "SURGE's BADGE.\nDEFENSE up. FLY.",
  RAINBOWBADGE  = "ERIKA's BADGE.\nSTRENGTH outside.",
  SOULBADGE     = "KOGA's BADGE.\nSPEED up. SURF.",
  MARSHBADGE    = "SABRINA's BADGE.\nTraded mons obey.",
  VOLCANOBADGE  = "BLAINE's BADGE.\nSPECIAL goes up.",
  EARTHBADGE    = "GIOVANNI's BADGE.\nEvery mon obeys.",
}
