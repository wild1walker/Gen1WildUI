# Changelog

## 1.4.0

Follows two of its mods; everything else here is already on its newest release.
Each brings one new row, and each appears in the menu on its own — the bundle
reads every feature's schema at load, so an upstream that adds an option needs
no change here. No key was renamed or removed.

- **BATTLE MENUS** → [Gen1BattleUI](https://github.com/wild1walker/Gen1BattleUI)
  1.4.0. The level-up stat box no longer comes up over a blank chat box: the
  line announcing the level was being dismissed and cleared before the window
  was pushed, so the second screen had nothing on it saying what the numbers
  belonged to. New row: `LEVEL-UP BOX`, on.
- **POKEDEX** → [Gen1Dex](https://github.com/wild1walker/Gen1Dex) 1.5.0. A new
  catch asks for its nickname over the dex entry rather than over a blank white
  screen. New row: `NAME IN PLACE`, on.

## 1.3.0

Follows [Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) to **1.2.0**
(from 1.1.1). Everything else here is already on its newest release.

1.2.0 publishes an `actions` provider registry on the box popup, which is what
lets another mod hang a row there. `REMEMBER MOVES`, over in
[Gen1WildQOL](https://github.com/wild1walker/Gen1WildQOL) 1.4.0, is the first
thing to use it — so its `BOX REMEMBER` row needs this version of this bundle.

### Fixed

- **`mod.find` handed back the wrong shape, and cross-mod integrations went
  quietly dead.** The engine's own returns a handle — `{ id, version, exports }`
  — and mods read it that way. The bundle's registry answered with the exports
  table itself, so `box.exports` was nil and the integration simply did nothing
  rather than failing. Handles now match the engine's, `tools/build.py` writes
  the version map they carry, and the shape is pinned by a test.
- `tools/check.py` crashed instead of reporting when a Lua file's bytecode
  listing carried a non-UTF-8 byte.

## 1.2.5

**BATTLE MENUS** (Gen1BattleUI 1.2.2 → 1.3.0) — the **XP bar moves into this
bundle**, from Gen1WildQOL. It is a battle UI feature and this is the battle
UI half, and the move is what finally stops the bar lying across the move
panel: over there it was drawn by a wrapper around `battle.draw`, which runs
after every `battle.overlay` link whatever priority they carry, so it could
not be drawn over and clipped itself to `x=88` — where the *vanilla* panel
ends, while Gen1BattleUI's ends at 112. Now the bar and the grid are drawn by
one function, bar first, so the panel covers it and keeps covering it if its
width ever changes. Its row is `XP BAR`, on, under `BATTLE MENUS`.

**Update Gen1WildQOL to 1.3.0 alongside this.** That is the release that drops
its own copy; run 1.2.x of it with this and both bars draw, with the old one
back on top of the panel.

Also from that release: `panelRect` is published for anything that draws after
the battle menus and must not be drawn over, and the mod's published tile
geometry is now the table its drawing actually reads rather than a stale copy
of it.

## 1.2.4

**BATTLE MENUS** (Gen1BattleUI 1.2.1 → 1.2.2) — the type colour is in the
letters now instead of on a chip behind them, and the move names on the
buttons are coloured by their own type as well, so the grid reads as four
types at a glance and the panel says which one the cursor is on. A tile glyph
is black on transparent and `setColor` cannot reach one; a shader throws each
glyph's RGB away and keeps only its alpha, which turns the glyph into a
stencil to fill with the type's colour — the game's own font throughout, in a
different ink. The palette is darker than the familiar type colours because
these are letters on a white box rather than a field behind them. `TYPE
COLOUR` turns it off, and a host with no shaders draws them black.

## 1.2.3

**BATTLE MENUS** (Gen1BattleUI 1.2.0 → 1.2.1) — the move panel reads the name
whole again and is three rows: name, type, PP. Fourteen tiles wide, which is
the narrowest that never cuts a Gen 1 move name, and 48 pixels short of the
full width it used to run to. The EXP bar no longer lies across it: the
overlay hook now carries a priority that draws this mod's layer last. The
move's type sits on a chip in that type's own colour, and `FULL NAMES`
defaults off, so the buttons are the game's own font as before.

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
