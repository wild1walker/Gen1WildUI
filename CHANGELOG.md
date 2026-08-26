# Changelog

## 1.2.2

**BAG** (Gen1ModernBag 1.9.3 → 1.9.4) — `Hold Scroll Speed` now defaults to
`OFF`. 1.2.1 moved it from `FAST` to `NORMAL`, which halved the rate and kept
the thing that made it feel wrong: a threshold. A press either crosses it or
does not, so the same press is one row or a run of them depending on how long
a finger rests — which reads as the list moving by itself rather than as a
speed being too high. `OFF` means a press is a row; the three speeds are all
still there.

**BATTLE MENUS** (Gen1BattleUI 1.1.2 → 1.2.0) — move names print whole. The
tile font is 8 pixels a glyph and a classic cell is seven of them, against
Gen 1's twelve-glyph names, so a move menu that will not fit is drawn in Plain
Pixel — the TTF the engine already ships for its translation mode — at the
largest size whose twelve glyphs still fit the cell. A grid takes it for all
four names or none, so a party whose names all fit is unchanged, and the wide
layout never reaches for it. `FULL NAMES` turns it off.

## 1.2.1

Follows two upstream fixes, both to things a player hits in a battle.

**BAG** (Gen1ModernBag 1.9.2 → 1.9.3) — `Hold Scroll Speed` defaults to
`NORMAL` rather than `FAST`. `FAST` starts repeating after 10 frames held and
then moves a row every 2, so a press about a sixth of a second long stopped
being one step and became thirty rows a second; whether a press crossed that
threshold was a matter of how long a finger rested, which is why it read as
the Bag scrolling by itself. `NORMAL` is Gen1Recomp's own `ListMenu` cadence.
A saved choice is untouched — this moves only players who never set one.

**BATTLE MENUS** (Gen1BattleUI 1.1.0 → 1.1.1) — the move panel no longer
covers the player's own HP. It was drawn twenty tiles wide across rows 8–11,
and `DrawPlayerHUDAndHPBar` puts the name, level, HP bar, HP numbers and
underline across rows 7–11 from x=72 rightwards. It now keeps the footprint of
the vanilla `TYPE/PP` box it stands in for, which is also what keeps anything
else drawn on that side of the screen clear of it.

## 1.2.0

Adds **BATTLE MENUS**, from
[Gen1BattleUI](https://github.com/wild1walker/Gen1BattleUI) — the battle command
and move menus as four buttons in a 2x2 grid instead of a list. Tracked as a
submodule pinned to 1.1.0, like the other seven Wild mods here. It ships on.

It was the one mod in the index that was in neither bundle, which is why
installing it alongside Gen1WildUI raised no conflict: there was nothing to
conflict with. Now that the bundle carries it, `Gen1BattleUI` is in the
manifest's `conflicts` and the two are mutually exclusive, the same way the
other eight features are.

| Row | Ships |
|---|---|
| `MOVE PANEL` — the highlighted move's full name, type and PP above the grid | on |

`BATTLE MENUS` takes a relaunch to switch. The mod has no off switch of its own
to donate — `MOVE PANEL` is a setting within the grid, not a switch for it — so
the bundle gates it at load and the menu marks the row.

## 1.1.0

Adds **BATTLE INTRO**, from
[gen1recomp-widescreen-battle-intro](https://github.com/ShaneMcGovernIE/gen1recomp-widescreen-battle-intro)
by ShaneMcGovernIE — maintained in this repository from here on, like the two
in Gen1WildQOL. It ships on.

The battle intro's flash plays across the whole window instead of inside a
centred 4:3 square, and the out-of-battle poison pulse with it. Two settings
come with it, on the bundle's own screen rather than the engine's OPTIONS
screen:

| Row | Ships |
|---|---|
| `FLASHLESS INTROS` — every battle opens on the Champion fight's outward spiral | off |
| `BLACK OUTRO` — a battle ends on a slow fade to black instead of the white flash | on |

Both are the mod's own defaults, unchanged.

## 1.0.0

First release. The visual half of the Gen1Wild index, consolidated into one
installable mod.

### Features

Each of these is a row in `OPTION > GEN1WILD UI`, switched on or off by
itself, with its own settings one press of A away:

| Feature | From | Ships |
|---|---|---|
| BACKDROPS | [Gen1Arena](https://github.com/wild1walker/Gen1Arena) | on |
| POKEDEX | [Gen1Dex](https://github.com/wild1walker/Gen1Dex) | on |
| POKEMON BOX | [Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) | on |
| PARTY MENU | [Gen1Party](https://github.com/wild1walker/Gen1Party) | on |
| BAG | [Gen1ModernBag](https://github.com/wild1walker/Gen1ModernBag) | on |
| MENU LAYOUT † | [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) | on |
| MOD MANAGER † | [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu) | on |

† Carried by Gen1WildQOL as well. With both bundles installed exactly one sets
it up, and its settings live under a shared id so they do not move when the
other bundle is the one that wins.

### Notes

- Nothing here changes what any of these mods do. The source is vendored
  unmodified from each mod's own repository and re-read on every sync.
- `POKEDEX` and `POKEMON BOX` are registered before `PARTY MENU`, which reads
  both when they are present — the same order they resolve in when installed
  separately.
- `MOD MANAGER` sets three of its own rows through the engine's mod manager,
  which writes them unprefixed. The runtime keeps both spellings in step so
  those rows behave the same whether they are set from its quick menu or from
  this bundle's.
- Features in this bundle can still be found by features in
  [Gen1WildQOL](https://github.com/wild1walker/Gen1WildQOL): `Gen151` hangs
  catch hints off `Gen1Dex`, and that lookup crosses the split.
