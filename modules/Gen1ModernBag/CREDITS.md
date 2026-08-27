# Credits

## The Bag

Gen1ModernBag is a derivative of **Modern Bag** by **FAFF0x**
(<https://github.com/FAFF0x/gen1recomp>), taken at upstream version 1.6.0.
Modern Bag is MIT licensed and the original copyright and permission notice is
carried verbatim in [`LICENSE`](LICENSE). Essentially all of what the Bag does
is upstream's work; see the README for the list of what is not.

## The item icons

The pictures under `assets/items/` are **not original work**. They are the item
icons of **[Pokémon Polished Crystal](https://github.com/Rangi42/polishedcrystal)**,
maintained by **Rangi** (Rangi42), recolored from that project's own `.pal`
data and scaled from 24 to the 16 pixels a Gen 1 list row has.

Polished Crystal's credits do not attribute the item icon set to any one
artist, so credit lands on the whole Graphics list in
[their `CREDITS.md`](https://github.com/Rangi42/polishedcrystal/blob/master/CREDITS.md),
which is the current and authoritative list and supersedes anything reproduced
here. Blue Emerald, solo993, Chamber, Lake, Neslug and Pikachu25 are credited
for sprites and icons generally and are the most likely source of much of this
set.

Polished Crystal ships no LICENSE file, so there is no explicit grant to
redistribute; what its credits establish is an ask-and-credit norm. If you
build on this mod: credit Polished Crystal by name with a link, ask upstream
before a wide release, honour any request to drop a specific asset promptly,
and do not strip this file when passing the assets along.

Some icons in that folder are **not** theirs:

- the TM and HM discs, `tm_*.png` and `hm_*.png`, which are drawn by
  `tools/make_item_icons.py` — Polished Crystal has no machine icon and
  neither does anything else, and a pocket of fifty-five identical
  four-letter rows needs one;
- `surfboard.png`, drawn by the same script and the one deliberate
  placeholder in the set: nothing anywhere has ever drawn Gen 1's SURFBOARD,
  so it is a board-shaped thing in the set's own idiom rather than a borrowed
  icon that means something else;
- `link_cable.png`, which is their ESCAPE ROPE in the red the RED CARD is
  drawn in;
- `gold_teeth.png`, which is their PEARL STRING in the gold of the GOLD LEAF.

`tools/make_item_icons.py` is where every one of those choices is written
down, including which of their icons stands in for which Gen 1 item, and it
rebuilds the whole folder from a checkout of the pack.

## Everything else

- **[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)** — the `BagMenu`,
  `ListMenu` and inventory seams this mod and its upstream are both built on.
- **[pret](https://github.com/pret)** — `pokered` and `pokecrystal`, the
  disassemblies the item constants, the list-menu geometry and the palette
  format all come from.
- **Nintendo / Creatures Inc. / GAME FREAK Inc.** — Pokémon. This is
  unofficial fan work, distributed free, with no affiliation and no
  endorsement.
