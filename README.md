# Gen1WildUI

**The visual half of the [Gen1Wild](https://github.com/wild1walker/Gen1Wild)
suite, as one mod.** Seven features from seven repositories, each of which is
still its own mod with its own releases — this bundles them, it does not fork
them.

Its other half is [Gen1WildQOL](https://github.com/wild1walker/Gen1WildQOL),
which carries the quality-of-life features. The two know about each other: a
feature in one can still find a feature in the other.

## What is in it

Everything here is a row in `OPTION > GEN1WILD UI`, switched on or off by
itself. Nothing is all-or-nothing.

| Feature | From |
|---|---|
| **BACKDROPS** | [Gen1Arena](https://github.com/wild1walker/Gen1Arena) — 2D backdrops behind battles, picked by map, tileset and how the encounter started |
| **POKEDEX** | [Gen1Dex](https://github.com/wild1walker/Gen1Dex) — a Pokémon beside every entry, base stats, evolutions, the full movelist, and an AREA screen |
| **POKEMON BOX** | [Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) — Bill's PC as the box it stood in for: party left, twenty slots right |
| **PARTY MENU** | [Gen1Party](https://github.com/wild1walker/Gen1Party) — every Pokémon in its own species colours instead of six sharing one |
| **BAG** | [Gen1ModernBag](https://github.com/wild1walker/Gen1ModernBag) — seven pockets, auto-sorting, favorites, search, no capacity limit |
| **MENU LAYOUT** † | [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) — reorder the START and PC menus, hide rows, pin field moves |
| **MOD MANAGER** † | [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu) — the mod manager redrawn in the game's own OPTION-screen idiom |

All seven ship on.

† Also in [Gen1WildQOL](https://github.com/wild1walker/Gen1WildQOL). These two
are not really visual overhauls — they are the furniture everything else is
reached through — so both halves carry them and neither loses them. Install
both bundles and exactly one of them sets it up; see
[Features in both bundles](#features-in-both-bundles).

## The menu

```
OPTION
  GEN1WILD UI         CONFIGURE
    BACKDROPS         ON (CONFIGURE)     <- LEFT/RIGHT switches it
      DIAGNOSTIC      OFF                <- A opens this
      FIELD TEST      OFF
      RESET DEFAULTS
    POKEDEX           ON (CONFIGURE)
      SPECIES COLOURS ON
      AREA HINTS      ON
      ...
    PARTY MENU        ON (CONFIGURE)
    ...
```

`LEFT`/`RIGHT` switches a feature or changes a setting, `A` opens a feature's
settings or explains a row, `B` goes back. Every feature screen ends in
`RESET DEFAULTS`.

A row marked `*` needs a relaunch to take effect, and the footer says so. Every
feature here except `BACKDROPS` is in that category: their upstream mods have
no off switch of their own, so the bundle gates them at load rather than
pretending to switch something already installed.

## What is different from the standalone mods

Nothing about what they do. The source is vendored unmodified from each mod's
own repository and re-read on every sync; the bundle only decides which of them
load and where they are configured.

Two things are worth knowing:

- **`PARTY MENU` reads `POKEDEX` and `POKEMON BOX`** when they are on, the same
  way it does when the three are installed separately. Switching either off
  changes what it can show.
- **`MOD MANAGER` sets three of its own rows** (`SORT`, `HIDE OFF`,
  `W/OPTIONS`) through the engine's mod manager, which writes them without the
  bundle's prefix. The runtime keeps both spellings in step, so those rows
  behave the same whether they are set from its own quick menu or from this
  bundle's.

## Features in both bundles

`MENU LAYOUT` and `MOD MANAGER` are in Gen1WildQOL too. They are how every
other feature is reached — the START menu, the PC menu, the mod manager itself
— so neither half is the right place to put them and neither half should go
without.

Both bundles would install them twice, and neither mod guards against that:
Gen1ModMenu would wrap the manager screen around its own wrapper, and
Gen1MenuManager would apply its row order to an order it had already applied.
So the two bundles agree on who does it. The first to load claims the feature
through a table parked on a shared engine module; the second sees the claim and
stands down, and its menu row says where the settings are:

```
GEN1WILD UI
  MOD MANAGER     ON (SET UP IN GEN1WILD QOL)
```

The switch on that row is still the real switch — settings for a shared feature
are stored under `gen1_wild_shared` rather than under either bundle, so both
menus read and write the same values, and installing the other half later does
not reset anything.

Which bundle wins does not matter and is not forced: both carry the same mod
pinned at the same version. `tools/check.py` cross-checks the declaration
against the other repo when it is checked out beside this one, because getting
it wrong in one of them fails silently.

## Installing

**MODS > Import mod .zip**, using the `.zip` from
[Releases](https://github.com/wild1walker/Gen1WildUI/releases/latest). Or copy
this folder into the game's `mods/` directory.

Uninstall the standalone versions of anything above first — the manifest
declares them as conflicts, because they install the same hooks. Settings do
not carry over: they are stored under this bundle's id.

## How it stays up to date

Each feature here is a git submodule under `upstream/`, pinned to a release.
Nothing in this bundle is forked and nothing is hand-copied. (Gen1WildQOL also
has a `maintained/` tree for two features it looks after itself; the same
tooling handles both.)

```sh
git submodule update --init --recursive   # first time
python3 tools/sync.py                     # move every pin to its newest release
python3 tools/sync.py Gen1Dex             # or just one
python3 tools/sync.py --dry-run           # report, change nothing
```

`sync.py` moves the pins and rebuilds `modules/`, which is what the game reads.
Then look at the diff and commit it:

```sh
git diff --stat modules upstream
python3 tools/check.py
git add upstream modules && git commit
```

An upstream that **adds an option row** needs nothing: the schema is read at
load, so the row appears in the menu on its own. An upstream that **adds a
whole feature**, **renames an option key** or **moves its entry file** needs an
edit to `features.lua` — and `tools/check.py` fails loudly if it does.

## Layout

```
main.lua              bootstrap; loads the runtime and gets out of the way
features.lua          what is in the bundle and how each piece is switched
runtime/              how a bundle hosts a mod written to be standalone
  loader.lua            reading and loading a bundled mod's own files
  facade.lua            the `mod` object each feature is handed instead
  optionset.lua         one options table for mods that each expected to own it
  registry.lua          mod.find, across features and across both bundles
  claims.lua            who installs a feature that is in both bundles
  menu.lua              the OPTION screens
  bundle.lua            the order all of the above happens in
adapters/             per-feature bundle glue, run after a feature installs
upstream/<Repo>/      submodules; tracked, never edited here
maintained/<Dir>/     source a bundle looks after itself (none here yet)
modules/<Dir>/        built by tools/build.py; what the game loads
tools/                build.py, sync.py, check.py
tests/                headless coverage of the runtime seam
```

`modules/` is committed rather than built at install time, because a mod is
installed by copying a folder and nothing runs a build. CI rebuilds it and
fails if it differs from what is committed, so the two cannot drift.

`runtime/` is byte-identical to Gen1WildQOL's. The two bundles are the same
machine with different feature registries.

## How it works

Seven mods that were each written believing they owned the options table is the
whole problem. Two of them call a row `species_colours`; across both bundles
five call their master switch `enabled`. Merged naively they would share
storage, and turning off one feature would turn off another.

So no feature is given the real `mod` object. Each gets a facade that keeps its
assumptions true from the inside:

| It asks for | It gets |
|---|---|
| `mod:read("chrome.lua")` | `modules/<Feature>/chrome.lua` |
| `mod.options:get("species_colours")` | `<feature>_species_colours` |
| `mod.save:get("last_pocket")` | `<feature>.last_pocket` |
| `mod.cache:read("layout")` | `<feature>.layout` |
| `mod.find("Gen1Dex")` | the sibling's exports, in either bundle |

Anything the facade does not name falls through to the real mod untouched, so
hooks, events, world, UI and content behave exactly as they always did — and a
feature that starts using a new engine API keeps working without the facade
being taught about it.

`mod.find` is the interesting one. `Gen151` — over in the QOL bundle — asks for
`Gen1Dex` to hang catch hints off the Pokédex. A lookup goes to this bundle
first, then to the paired bundle through its exports, then out to the engine,
so the optional-dependency graph survives being cut in half.

There is a headless test for each of those seams:

```sh
luajit tests/runtime_test.lua
```

## Credits

Everything here is somebody's work, and mostly not mine:

- **FAFF0x** — *Modern Bag*, which `Gen1ModernBag` is a derivative of, taken at
  upstream 1.6.0. Nearly all of what that feature does is FAFF0x's work; the
  MIT notice travels with it.
- **LibertyTwins, princess-phoenix, carchagui, aveontrainer, WesleyFG,
  kWharever, worldslayer608** and **knizz** — the *Battle Backgrounds Patch FR*
  art `BACKDROPS` draws. None of it was made for this mod, and its authors ask
  that the names travel with it.
- **[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)** and
  **[pret](https://github.com/pret)** — the engine and the disassemblies all of
  it stands on.

Each vendored mod keeps its own licence file under `modules/<Feature>/`.

Contributions belong in the mod's own repository, behind its link above. Fixes
to the bundling itself belong here.
