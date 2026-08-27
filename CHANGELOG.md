# Changelog

## 1.10.3

**The POKEDEX crashed the moment the cursor moved.**

`src/ui/PokedexMenu.lua:116: attempt to call method 'rows' (a number value)`,
in the engine's own `syncScroll`, on the first press of UP or DOWN after the
list came up.

The vanilla dex was a `ListMenu` until gen1recomp rewrote it as a screen of
its own, and the two shapes disagree about the one field this feature has
always written. A `ListMenu` carries `rows` as a number — this list wants six
where vanilla shows seven, because the header and footer boxes took a tile row
each end — and the screen that replaced it carries `rows()` as a method its
own scroll clamp calls. Writing the six over the method left the engine
calling a number.

Which shape the engine has is now asked once, and the six rows are handed over
the way that shape asks for them. Nothing about the screen changes on a build
that still has the list.

It was never a bundle question. Installing GEN1WILD UI without GEN1WILD QOL is
where it happened to be found, but the two halves have nothing to do with this
one: the dex is carried here alone, the other half never touches
`PokedexMenu`, and the standalone
[Gen1Dex](https://github.com/wild1walker/Gen1Dex) hits it the same way. The
suite's halves stand alone, and this was the engine moving underneath all
three of them at once.

### Three settings that had gone quiet with it

The same rewrite took `wrap`, `keyRepeat` and `onSelectKey` with it — they
were `ListMenu` opts, and the screen's own update reads none of them. So
SELECT VIEWS, LIST WRAPS and HOLD TO SCROLL were three rows on the menu that
did nothing, and LEFT/RIGHT paged by the engine's seven over a list showing
six, stepping past an entry each press and never reaching the last one.

All four are answered again, as a layer over the engine's update rather than a
replacement for it: A, B and the side menu never reach it, and every key it
does take is one the engine leaves unbound here or one whose press it would
have spent doing nothing.

### How it is carried

`overlays/Gen1Dex/list.lua`, laid over the pinned submodule on the way into
`modules/` by `tools/build.py`. The fix belongs upstream and should land
there; until it does, an overlay is what keeps this bundle from shipping a
Pokédex that crashes, without editing a submodule this repository does not
own. The next sync that carries the upstream fix should delete it.

`tests/dexlist_test.lua` stands both shapes of the engine screen up headless —
the screen's `rows`/`syncScroll`/`pageScroll`/`update` arithmetic copied
rather than approximated — and drives the list through them. It fails with
exactly the reported error against the code this release fixes.

## 1.10.2

**The lift panel loses its FLOOR header.**

It earned nothing. A box of floor numbers that opens when you read a lift's
button plate, in a lift, is not ambiguous — the word only ever said what the
rows already said, and it was the most expensive thing on the box: it set the
width (nine tiles rather than the six the floors need), and it needed a run of
the top rule knocked out to make room for itself.

Without it the panel is as wide as its widest floor and no wider, which is
what a panel against the edge of the screen should be. Nothing else moves:
same two-tile row pitch, same blank row under the top border, same place
against the right edge, same scrolling for SILPH CO.

`tests/iteminfo_test.lua` now draws the panel rather than only measuring it —
a stub `love.graphics` and a recording `Font`, then assertions on what
actually reached the screen: one box, six tiles wide, five floors printed and
nothing else, sixteen pixels apart, with the cursor a column left of the
labels. It is the guard for the header coming back and for the row pitch
collapsing again, both of which the code believed it had right until someone
looked at it.

## 1.10.1

Three fixes to what 1.10.0 shipped, all found by looking at the screen.

### The lift panel was spaced wrong

Three separate mistakes, all of them the same mistake: it was drawn to a
layout of its own instead of to `src/ui/Menu.lua`'s, which is what every
boxed choice in this game is drawn by.

- **Rows were one tile apart**, not two. Nothing else in the game is spaced
  that way, and it read as a list that had been squashed to fit.
- **Choices ran from the top**, so the slack fell at the bottom. Gen 1
  anchors them to the last interior row and lets the blank row fall under the
  top border — that blank row is what keeps the first choice off the title.
- **The FLOOR label knocked out the whole top rule.** The knock-out was padded
  by a tile at each end, which is right for a sixteen-tile pocket header and,
  in a box this narrow, erased everything between the corners — leaving FLOOR
  floating between two ornaments with no frame attached to it.

The box is now sized so the word keeps a column of rule on each side of it,
and the knock-out is exactly the glyphs, the way `Menu` titles its own box.
Every floor still fits without scrolling anywhere but SILPH CO.

### The LINK CABLE had no description

It is [Gen151](https://github.com/wild1walker/Gen151)'s, registered from
Gen1WildQOL, so nothing in this bundle's table had a line for it — and it
sits on the Celadon 4F shelf beside the four stones, every one of which
explains itself. A row whose neighbours all speak and it does not looks
broken.

It is described here now. Safe either way: only ids the game actually has are
described, and Gen1WildQOL loads first, so the cable is either registered by
then or was never going to be.

### The item PC printed the menu underneath it

`WITHDRAW / DEPOSIT / TOSS / LOG OFF` is pushed **over** the Pokémon Center's
own PC menu, which stays on the stack so `B` comes back to it — and, being a
menu rather than a screen, kept drawing. Both boxes start in the same corner
and are the same width, so for as long as they were the same height nobody
saw it.

They are not the same height. The PC menu sizes itself to its rows and grows
one for `PROF.OAK's PC`, another for `<PK><MN>LEAGUE` once there is a HALL OF
FAME to read, and another for anything `MENU LAYOUT` pins there, while the
item PC's box is a fixed ten tiles. Past four rows the menu underneath
printed its last rows out from under the box on top of it, with a second
bottom border under those: a `LOG OFF` row below a `LOG OFF` row.

The covered menu is now hidden rather than drawn over, through the engine's
own `screen.render_visible`. It keeps its place on the stack and its place in
the `B` chain and comes back the moment the item PC closes — and because
nothing is painted over it, the overworld still shows around the box. The
bedroom PC, which opens with no menu under it at all, is untouched.

This one predates 1.10.0; it is what the PC has always done. It is fixed here
because ITEM INFO is what owns those screens now.

## 1.10.0

**Every item says what it is now**, and four screens that had nowhere to say it
are redrawn.

Two new features, both maintained here rather than tracked:

- **ITEM INFO** — a description for every item in the game, on the item
  itself. The mart's BUY and SELL lists carry it in the clerk's box, following
  the cursor, which is what finally replaces *Take your time.* The item PC's
  WITHDRAW, DEPOSIT and TOSS lists carry it in the same box. And the bag's item
  menu grows an **ABOUT** row that prints it.
- **ELEVATOR PANEL** — the lift's `WHICH FLOOR?` full-screen list becomes a
  small panel against the right edge with every floor on it at once, and the
  car you are standing in stays on the screen behind it.

Both ship on and both switch off live, with no relaunch.

### Where the descriptions live

On `data.items[id].description` — the field Gen 2's own extractor writes for
Gold and Crystal, under the name it writes it under. So this is not a private
table only ITEM INFO can read: anything that wants to show an item description
reads it off the item the way it would on a Gen 2 cart, whether or not this
bundle is the thing that put it there. Item records are extensible by design,
so nothing is taken away — an item gains a field and keeps every one it had.

Eighty-one are written by hand, two lines and eighteen glyphs each, which is
what a Gen 1 text box holds. The fifty-five machines are described from the
move they carry rather than by hand, so a mod that retunes what TM26 teaches
does not leave a description lying. `tests/iteminfo_test.lua` holds the line
budget: a description that would wrap to a third line is a failing build, not
a truncated sentence, because the box shows the last two lines of what it is
given and a third line would eat the first one silently.

### The chrome

The four lists get the frame the rest of the suite uses: a header box with the
title in it (and the money at a mart, where the vanilla screen floats a
separate box in the corner), the rows ruled to the same margins Gen1Dex and
Gen1Party keep, a mark at each end when there is more above or below, and the
game's own text box along the bottom.

Nothing about how any of them *works* changed. Each list is built exactly as
the engine builds it and then has `draw` and `update` swapped; the input, the
scrolling, the quantity selector, the yes/no confirm, what a purchase costs
and what a toss refuses are all the engine's own code, untouched. The mart's
BUY / SELL / QUIT counter keeps the shop showing around it, because that
screen was never opaque and seeing the room you are standing in is the best
thing about it.

## 1.9.0

The status tint is removed from the party list and the box, at the author's
request, along with the rest of the status colour work across the suite.

- **PARTY MENU** → [Gen1Party](https://github.com/wild1walker/Gen1Party) 1.7.0
- **POKEMON BOX** → [Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox)
  1.5.0

Icons draw as they always did and the palette zone under them is the species
colours again. Both mods' source is byte-identical to the release before the
tint went in, so nothing else moved with it.

`mod.publish` is gone from this bundle's runtime too. It was added for the
feature that is being removed, it never had another caller here, and the two
bundles keep their runtime byte-identical.

## 1.8.1

The status tint on a POKéMON reaches **full-colour icon art** now, in the party
list and the box.

- **PARTY MENU** → [Gen1Party](https://github.com/wild1walker/Gen1Party) 1.6.0
- **POKEMON BOX** → [Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox)
  1.4.0

It rode a palette zone, and a palette zone only reaches art that goes through
the shade-remap pass -- which full-colour art sits out **by design**, since both
mods mark their icon rect trueColor precisely so the pass does not repaint it
off its red channel. So the tint coloured nothing at all for anyone running a
full-colour icon pack. The icon is now drawn in the condition's colour as well,
which reaches both kinds of art.

The colour comes from `drawColour` in **STATUS COLOURS**
([Gen1WildQOL](https://github.com/wild1walker/Gen1WildQOL) 1.8.0), so the party,
the box and the overworld keep agreeing. **Without Gen1WildQOL 1.8.0 or later
installed there is no tint**, exactly as before.

## 1.8.0

A POKéMON in the party list or the box wears its condition: poisoned is purple,
fainted is grey, and the rest of the statuses have their own colour -- over the
species colours those cells already wear, so a poisoned CHARMANDER still reads
as a CHARMANDER.

- **PARTY MENU** → [Gen1Party](https://github.com/wild1walker/Gen1Party) 1.5.0
- **POKEMON BOX** →
  [Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) 1.3.0, on the
  grid and on the party column beside it

The colours are not defined in either. They come from **STATUS COLOURS**, the
feature in [Gen1WildQOL](https://github.com/wild1walker/Gen1WildQOL) 1.7.0 that
turns the overworld purple while you walk poisoned, and which owns one table of
what each condition looks like so these two and the stats page agree instead of
drifting apart. Both ask it; **without Gen1WildQOL installed there is no tint**
and the cells are the species colours exactly as before.

It rides the per-POKéMON zone each screen already builds, so it costs nothing
extra to draw, and full-colour art still sits out the pass untouched.

The Pokédex is deliberately not in that list: a dex entry is a page about a
*species*, so there is no condition there to show.

## 1.7.0

**This bundle no longer puts a row on the game's OPTION screen.** Its settings
live where a mod's settings live: `MODS` > `Gen1WildUI` > `OPTIONS`, which lands
on the same nested screens it always did -- every feature, each with its own
page. Nothing was removed from the menu and nothing moved inside it; only the
way in changed, and there is now one of them instead of two.

The OPTION screen is the game's own, and a bundle of a dozen mods was spending
a line of it on something the mod manager already lists.

Also follows both shared menu features:

- **MENU LAYOUT** ->
  [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) 0.2.8. Its
  `MENU MANAGER` row now sits at the **top** of the OPTION screen, above
  `SPEED`.
- **MOD MANAGER** -> [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu)
  0.9.0, which is what makes that possible. Since the engine grouped the OPTION
  screen it lays out the rows its own order names first and appends everything
  else behind them, so no mod could reach the front however it anchored itself.
  A row may now ask by carrying `top`, and rows that ask are lifted. It
  reorders what is drawn, never the flat list the hook built, and it runs
  whatever `STYLE` and `HIDE CANCEL` are set to.

The OPTION screen now reads `MENU MANAGER`, `SPEED`, `VIDEO`, `GRAPHICS`,
`AUDIO`, `PERFORMANCE`, `RULESET`, `BATTLE OPTIONS`, `EXTRAS`, `MODS`, then the
platform rows.

## 1.6.4

Fixes the OPTION screen. Both of the shared menu features moved.

- **MOD MANAGER** -> [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu)
  0.8.2. **The screen was showing the wrong rows.** With `STYLE = MODERN` and
  `HIDE CANCEL` on -- both defaults, so this was everyone -- the arrow sat on
  one row while the press edited another, and `MODS` looked like it had been
  taken off the screen entirely. The engine grouped that screen and now keeps
  two lists: the flat one the `ui.options.rows` hook builds, and the one on
  screen, where a group's members collapse into a single opener. The cursor
  counts the second; this mod's `CANCEL`-hiding decoration drew the first, so
  the two disagreed from the top row down. `MODS` is ninth in the view and
  thirtieth in the flat list, which is where it was being drawn. Both halves
  read the view now.
- **MENU LAYOUT** ->
  [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) 0.2.7. Its
  `MENU MANAGER` row is anchored to `MODS` rather than appended, so it sits
  with the other mod rows instead of last of all, behind `CONTROLS`, `DATE
  FORMAT` and the platform rows. Grouping runs after the hook and appends
  whatever the engine's own order does not name, which is what stranded it.

The top level now reads `SPEED`, `VIDEO`, `GRAPHICS`, `AUDIO`, `PERFORMANCE`,
`RULESET`, `BATTLE OPTIONS`, `EXTRAS`, `MODS`, and then the mod rows together:
`Gen1WildUI`, `Gen1WildQOL`, `MENU MANAGER`.

## 1.6.3

Follows [Gen1BattleUI](https://github.com/wild1walker/Gen1BattleUI) to 1.5.2,
which fixes a bug that only appears when **both bundles are installed**.

- **The level-up stat box came up over a blank text box again if
  [Gen1WildQOL](https://github.com/wild1walker/Gen1WildQOL)'s `EXP SHARE` was
  on** — the exact picture 1.4.0 of that mod was written to fix, back for
  anyone running the pair. It was a hook priority rather than the retiming.
  `EXP SHARE` wraps `battle.exp_award` at priority 90 and, in every mode but
  `OFF`, awards the exp itself and returns *without calling through*. The
  engine runs the highest-priority link outermost, so `BATTLE MENUS` sat inside
  it and never ran: the rows were queued exactly as vanilla queues them and
  never re-marked, which is the engine's own two screens — the line prompts, it
  clears, and the stat box arrives over an empty box.
- `BATTLE MENUS` is now the outermost link on that hook. It has to be: it calls
  through and then *reads* what the chain queued, and an inner link cannot read
  a queue built by an outer one that never called through. It costs `EXP SHARE`
  nothing — the award is still theirs, through the engine's own `applyShare`,
  so the rows are the same rows and the retiming finds them.
- A miss no longer fails silently: it logs how many level-up lines were joined,
  how many were expected, and the text it could not match. "Reached and found
  nothing" and "never reached at all" produced the same blank box and neither
  said which.

## 1.6.2

Follows [Gen1BattleUI](https://github.com/wild1walker/Gen1BattleUI) to 1.5.1,
which drops the `gen1_wild_ui` entry from its own `optional_dependencies` —
an optional dependency on this bundle that could never be satisfied, since
this bundle carries that mod as `BATTLE MENUS` and lists it in `conflicts`,
so the engine will not have both installed for it to resolve against.

No module content changed: the rebuild is byte-identical and the whole diff is
the pin and the version map `mod.find` hands out. Nothing in the menu moved.

## 1.6.1

Adds the `LICENSE` this repository never had. Every standalone mod in the suite
ships one and both bundles did not, while the index entry claimed MIT on their
behalf -- so the claim is now in the repository making it, and in the zip.

It is scoped rather than blanket: MIT over the bundling -- the loader, the
feature registry, the runtime, the adapters, the tools, the suites -- and no
claim at all over the mods carried under `modules/`, each of which keeps its
own licence file where the build put it. `BATTLE INTRO` is maintained here and
its original states no terms, so the file says that plainly and leaves them to
its author rather than assigning any.

No code changed.

## 1.6.0

Follows one of its mods; everything else here is already on its newest release.
Its three new rows appear in the menu on their own — the bundle reads every
feature's schema at load — so nothing here needed the edit. No key was renamed
or removed.

- **BATTLE MENUS** → [Gen1BattleUI](https://github.com/wild1walker/Gen1BattleUI)
  1.5.0. **The ball you throw is coloured as itself.** Under `COLORS =
  ADVANCED` every battle sprite took its colour from the SGB zone underneath
  it, so a GREAT BALL and an ULTRA BALL came out the same colour as each other
  and as the grass behind them. The toss, the wobbles and the ball resting
  through the caught text are now each ball's own — red, blue, gold, purple,
  olive — and the Pokémon Center's heal machine lights each ball in the colours
  of the ball that POKéMON was *caught* in rather than painting all six the
  same. The mono colour modes have no per-sprite colour to give and are passed
  straight through, so this is off in them whatever the rows say.
  New rows: `BALL COLOUR`, `BALL BAND` and `CENTER BALLS`, all on.

### Worth knowing before you turn CENTER BALLS on

It is the one thing in either bundle that writes to your save. Gen 1 records
nothing about what caught a POKéMON — the party struct has no ball in it, and
neither does Gen 2's — so the machine can only be told by a field the mod
invents: `mon.caughtBall`, written onto the POKéMON at catch time, only when
that field is empty and never over a value already there. It goes where the
POKéMON goes, through the box and through a trade, and it stays in the save
after an uninstall. It maps to no byte in the real Gen 1 format, so an export
to a `.sav` drops it and a round trip lights every ball red until the party
turns over. Anything caught before this installed heals as a POKE BALL.

Only-if-absent is the rule Pokeball Colors set for that field, which the
feature is ported from and can share a save with.

## 1.5.0

Follows one of its mods; everything else here is already on its newest release.
The new row appears in the menu on its own — the bundle reads every feature's
schema at load — so nothing here needed the edit. No key was renamed or removed.

- **PARTY MENU** → [Gen1Party](https://github.com/wild1walker/Gen1Party) 1.4.0.
  The popup's `SWITCH` becomes `MOVE`, and moving a POKéMON is the box's answer
  rather than the engine's: A lifts the member the cursor is on, it flashes,
  and UP and DOWN carry it through the list a row at a time with the party
  reordered under it as it goes. A lets go; B walks it home. A run of steps is
  an insertion, not an exchange — carry the fourth member to the top and the
  three it passed keep the order they had. The *battle* popup's `SWITCH` is
  left alone: there it means *send this one out*. New row: `MOVE NOT SWITCH`,
  on — off restores the engine's two picks and one exchange exactly.

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
