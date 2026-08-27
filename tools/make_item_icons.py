#!/usr/bin/env python3
"""Build the 16x16 item icon set the bag, the mart and the item PC draw.

The art is Polished Crystal's, colorized from that project's own .pal data --
see CREDITS.md beside the icons.  This script only picks which of those icons
stands for which Gen 1 item, scales them to the 16 pixels a list row has, and
draws the four things Gen 1 has and Polished Crystal has no icon for: the TM
and HM discs, the LINK CABLE and the GOLD TEETH.

    python3 tools/make_item_icons.py /path/to/polishedcrystal-item-icons OUTDIR

The pack is the `24px/` folder of the colorized Polished Crystal item icons.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    sys.exit("this needs Pillow: pip install pillow")

SIZE = 16

# ------- which of the pack's icons stands for which Gen 1 item
#
# Keyed by the item id the engine uses (data.items), valued by the file name
# in the pack.  Everything obvious is itself; the rest are stand-ins, and each
# one is here because the pack has no icon for that item and the nearest thing
# reads better than a blank column:
#
#   TOWN_MAP      old_sea_map     a rolled map
#   OAKS_PARCEL   type_chart      a wrapped brown package
#   BIKE_VOUCHER  pass            a printed ticket
#   SECRET_KEY    basement_key    a key, and not one of the other two
#   POKE_FLUTE    clear_bell      the pack's one instrument
#   COIN          amulet_coin     a gold coin
#   EXP_ALL       exp_share       the same item under Gen 2's name
#   SILPH_SCOPE   silphscope2     the same item, two floors up
#   X_SPECIAL     x_sp_atk        Gen 1's SPECIAL split into two in Gen 2
#
# SURFBOARD has no entry: nothing in the pack reads as a board, and a wrong
# icon on a row is worse than none.
STANDINS = {
    "MASTER_BALL": "master_ball", "ULTRA_BALL": "ultra_ball",
    "GREAT_BALL": "great_ball", "POKE_BALL": "poke_ball",
    "SAFARI_BALL": "safari_ball",

    "POTION": "potion", "SUPER_POTION": "super_potion",
    "HYPER_POTION": "hyper_potion", "MAX_POTION": "max_potion",
    "FULL_RESTORE": "full_restore", "REVIVE": "revive",
    "MAX_REVIVE": "max_revive", "ANTIDOTE": "antidote",
    "BURN_HEAL": "burn_heal", "ICE_HEAL": "ice_heal",
    "AWAKENING": "awakening", "PARLYZ_HEAL": "paralyze_heal",
    "FULL_HEAL": "full_heal", "ETHER": "ether", "MAX_ETHER": "max_ether",
    "ELIXER": "elixir", "MAX_ELIXER": "max_elixir",

    "HP_UP": "hp_up", "PROTEIN": "protein", "IRON": "iron",
    "CARBOS": "carbos", "CALCIUM": "calcium", "RARE_CANDY": "rare_candy",
    "PP_UP": "pp_up",

    "X_ATTACK": "x_attack", "X_DEFEND": "x_defend", "X_SPEED": "x_speed",
    "X_SPECIAL": "x_sp_atk", "X_ACCURACY": "x_accuracy",
    "GUARD_SPEC": "guard_spec", "DIRE_HIT": "dire_hit",
    "POKE_DOLL": "poke_doll",

    "MOON_STONE": "moon_stone", "FIRE_STONE": "fire_stone",
    "THUNDER_STONE": "thunderstone", "WATER_STONE": "water_stone",
    "LEAF_STONE": "leaf_stone",

    "ESCAPE_ROPE": "escape_rope", "REPEL": "repel",
    "SUPER_REPEL": "super_repel", "MAX_REPEL": "max_repel",
    "BICYCLE": "bicycle", "TOWN_MAP": "old_sea_map", "POKEDEX": "pokedex",

    "OLD_ROD": "old_rod", "GOOD_ROD": "good_rod", "SUPER_ROD": "super_rod",

    "FRESH_WATER": "fresh_water", "SODA_POP": "soda_pop",
    "LEMONADE": "lemonade",

    "OAKS_PARCEL": "type_chart", "S_S_TICKET": "s_s_ticket",
    "BIKE_VOUCHER": "pass", "SECRET_KEY": "basement_key",
    "LIFT_KEY": "lift_key", "CARD_KEY": "card_key",
    "SILPH_SCOPE": "silphscope2", "POKE_FLUTE": "clear_bell",
    "ITEMFINDER": "itemfinder", "EXP_ALL": "exp_share",
    "COIN_CASE": "coin_case",

    "DOME_FOSSIL": "dome_fossil", "HELIX_FOSSIL": "helix_fossil",
    "OLD_AMBER": "old_amber", "NUGGET": "nugget", "COIN": "amulet_coin",
}

# ------- the two recolors
#
# Every icon in the pack is four colours: transparent, black, and the two
# shades of its GBC palette.  A recolor is those two shades swapped for
# another item's two, which keeps the art on a palette the rest of the set is
# already drawn from.
#
# LINK_CABLE is Gen151's, and the pack has no cable.  A coiled rope is the
# shape a cable has, so it is the rope in the LINK CABLE's own red -- the red
# the pack gives the RED CARD, which is the reddest pair it has.
#
# GOLD_TEETH is a row of round white things in the pack's PEARL STRING, which
# is what a set of teeth looks like, in the GOLD LEAF's gold.
RECOLORS = {
    "LINK_CABLE": ("escape_rope", ((239, 25, 0), (255, 82, 66))),
    "GOLD_TEETH": ("pearl_string", ((222, 148, 8), (255, 206, 66))),
}

# ------- the machines
#
# Fifty TMs and five HMs, and the pack has an icon for none of them.  They are
# drawn here instead: a disc in the colour of the move it teaches, which is
# how every generation since has drawn a TM, and how a player picks TM24 out
# of a pocket of fifty-five identical four-letter rows.
#
# Two shades per type, dark then light, on the GBC's 5-bit steps.  The types
# are Gen 1's fifteen; a machine whose move has a type nothing here names
# falls back to `tm.png` / `hm.png`, which are the NORMAL pair.
TYPE_SHADES = {
    "NORMAL":   ((168, 168, 120), (224, 224, 184)),
    "FIGHTING": ((192,  48,  40), (240, 112,  96)),
    "FLYING":   ((136, 168, 224), (192, 216, 248)),
    "POISON":   ((160,  64, 160), (216, 128, 216)),
    "GROUND":   ((216, 168,  64), (248, 216, 144)),
    "ROCK":     ((160, 128,  56), (216, 184, 112)),
    "BUG":      ((152, 184,  32), (208, 224, 120)),
    "GHOST":    ((112,  88, 152), (176, 152, 208)),
    "FIRE":     ((240, 128,  48), (248, 184, 120)),
    "WATER":    (( 80, 136, 240), (152, 192, 248)),
    "GRASS":    (( 72, 176,  88), (152, 224, 152)),
    "ELECTRIC": ((232, 192,  40), (248, 232, 144)),
    "PSYCHIC":  ((240,  88, 136), (248, 160, 192)),
    "ICE":      (( 96, 200, 208), (184, 240, 240)),
    "DRAGON":   ((112,  56, 240), (168, 136, 248)),
}

BLACK = (0, 0, 0, 255)
CLEAR = (255, 255, 255, 0)
# An HM's ring, in the same two shades the pack's own silver items are drawn in
SILVER = (216, 216, 224)


def scale(image: Image.Image) -> Image.Image:
    """24 -> 16, nearest.

    Nearest rather than a majority filter over each 1.5x1.5 source square:
    the majority keeps whichever colour covers the most of a square, which on
    this art is the black outline, and the icons came back rimmed and
    flattened -- a POKe BALL lost its white band, a POTION its cap.  Dropping
    every third row and column keeps the highlights, which is what makes a
    16-pixel icon recognisable at all.
    """
    return image.convert("RGBA").resize((SIZE, SIZE), Image.NEAREST)


def shades(image: Image.Image) -> list:
    """The two palette colours of a pack icon, darkest first."""
    counts = {}
    for pixel in image.convert("RGBA").getdata():
        if pixel[3] == 0 or pixel[:3] == (0, 0, 0):
            continue
        counts[pixel] = counts.get(pixel, 0) + 1
    return sorted(counts, key=lambda c: sum(c[:3]))


def recolor(image: Image.Image, target: tuple) -> Image.Image:
    found = shades(image)
    if len(found) != 2:
        raise SystemExit("expected a two-shade icon, got %d shades" % len(found))
    swap = {found[0]: target[0] + (255,), found[1]: target[1] + (255,)}
    out = image.convert("RGBA").copy()
    pixels = out.load()
    for y in range(out.height):
        for x in range(out.width):
            pixels[x, y] = swap.get(pixels[x, y], pixels[x, y])
    return out


# ------- the disc
#
# Drawn at 8x and area-voted down rather than plotted a pixel at a time: a
# 16-pixel circle decided by which side of a threshold one sample landed on
# comes out square-shouldered, and the vote is over four colours, so the
# result is still exactly the four an icon in this set is allowed.
SUPERSAMPLE = 8


def disc(dark: tuple, light: tuple, rim: tuple = None) -> Image.Image:
    s = SUPERSAMPLE
    n = SIZE * s
    big = Image.new("RGBA", (n, n), CLEAR)
    pixels = big.load()
    centre = (n - 1) / 2.0
    edge, body, ring = 7.5 * s, 6.4 * s, 5.5 * s
    hole, bore = 2.1 * s, 1.2 * s
    # the lit side: one source, up and to the left, which is how every icon in
    # the pack is shaded
    lit_x, lit_y, lit_r = centre - 1.3 * s, centre - 1.3 * s, 4.2 * s
    for y in range(n):
        for x in range(n):
            dx, dy = x - centre, y - centre
            distance = (dx * dx + dy * dy) ** 0.5
            if distance > edge:
                continue
            if distance > body:
                pixels[x, y] = BLACK
            elif distance < bore:
                pixels[x, y] = CLEAR
            elif distance < hole:
                pixels[x, y] = BLACK
            elif rim and distance > ring:
                pixels[x, y] = rim + (255,)
            else:
                lit = ((x - lit_x) ** 2 + (y - lit_y) ** 2) ** 0.5 < lit_r
                pixels[x, y] = (light if lit else dark) + (255,)

    out = Image.new("RGBA", (SIZE, SIZE), CLEAR)
    small = out.load()
    for oy in range(SIZE):
        for ox in range(SIZE):
            tally = {}
            for sy in range(oy * s, (oy + 1) * s):
                for sx in range(ox * s, (ox + 1) * s):
                    colour = pixels[sx, sy]
                    tally[colour] = tally.get(colour, 0) + 1
            small[ox, oy] = max(tally.items(), key=lambda kv: kv[1])[0]
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.exit(__doc__)
    pack = Path(argv[1])
    if (pack / "24px").is_dir():
        pack = pack / "24px"
    out = Path(argv[2])
    out.mkdir(parents=True, exist_ok=True)

    written = 0
    for item, source in sorted(STANDINS.items()):
        path = pack / (source + ".png")
        if not path.exists():
            sys.exit("the pack has no %s.png (for %s)" % (source, item))
        scale(Image.open(path)).save(out / (item.lower() + ".png"))
        written += 1

    for item, (source, target) in sorted(RECOLORS.items()):
        path = pack / (source + ".png")
        if not path.exists():
            sys.exit("the pack has no %s.png (for %s)" % (source, item))
        scale(recolor(Image.open(path), target)).save(out / (item.lower() + ".png"))
        written += 1

    for name, (dark, light) in sorted(TYPE_SHADES.items()):
        disc(dark, light).save(out / ("tm_" + name.lower() + ".png"))
        disc(dark, light, SILVER).save(out / ("hm_" + name.lower() + ".png"))
        written += 2
    normal = TYPE_SHADES["NORMAL"]
    disc(normal[0], normal[1]).save(out / "tm.png")
    disc(normal[0], normal[1], SILVER).save(out / "hm.png")
    written += 2

    print("wrote %d icons to %s" % (written, out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
