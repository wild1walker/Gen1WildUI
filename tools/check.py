#!/usr/bin/env python3
"""The bundle's own checks.

Runs without the engine, so it can say nothing about whether a feature
*behaves*.  What it can prove is everything structural, which is where a
bundle of a dozen independent mods actually goes wrong:

  * every Lua file compiles
  * every feature in features.lua points at a file that exists in modules/
  * no two features share an id, a directory entry, or an alias
  * no two option keys collide once prefixed
  * every adapter and overlay a feature names is present
  * every file a module loads by name survived the build
  * the manifest agrees with the changelog

Usage:  python3 tools/check.py [--quiet]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "modules"
UPSTREAM = ROOT / "upstream"
MAINTAINED = ROOT / "maintained"
ADAPTERS = ROOT / "adapters"
OVERLAYS = ROOT / "overlays"
FEATURES = ROOT / "features.lua"
MANIFEST = ROOT / "manifest.json"
CHANGELOG = ROOT / "CHANGELOG.md"

FIELD = re.compile(r'(\w+)\s*=\s*"([^"]*)"')


class Problems:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def lua_binary() -> str | None:
    for candidate in ("luajit", "lua5.1", "lua"):
        if shutil.which(candidate):
            return candidate
    return None


def check_lua_syntax(problems: Problems, quiet: bool) -> int:
    binary = lua_binary()
    if binary is None:
        problems.warn("no lua interpreter found; syntax not checked")
        return 0

    flag = "-bl" if binary == "luajit" else "-p"
    checked = 0
    for path in sorted(ROOT.rglob("*.lua")):
        if any(part in {".git", "upstream", ".build-check"} for part in path.parts):
            continue
        # errors="replace": `luajit -bl` dumps a bytecode listing, and a
        # constant carrying a non-UTF-8 byte -- Gen1Remember's POKeMON glyph
        # is one -- comes through raw. Decoding that strictly crashed the
        # whole check on a file that compiles perfectly well. Only the exit
        # code and the first line of any error are read from this.
        result = subprocess.run(
            [binary, flag, str(path)] if binary == "luajit"
            else ["luac", "-p", str(path)],
            capture_output=True, text=True, errors="replace", check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip().splitlines()
            problems.error(f"{path.relative_to(ROOT)}: {detail[0] if detail else 'did not compile'}")
        checked += 1
    if not quiet:
        print(f"  lua syntax: {checked} files")
    return checked


def parse_features(problems: Problems) -> list[dict]:
    return _parse(FEATURES, problems)


def _parse(path: Path, problems: Problems) -> list[dict]:
    """Scan features.lua for the fields this checker needs.

    Deliberately a scan and not a parser: the file is Lua and this is Python.
    A field it cannot see is a field it does not check, which is the right
    failure mode for a lint.
    """
    if not path.exists():
        problems.error(f"{path.name} is missing")
        return []

    text = path.read_text(encoding="utf-8")
    start = text.find("features = {")
    if start < 0:
        problems.error(f"{path.name} has no `features = {{` table")
        return []

    features: list[dict] = []
    current: dict | None = None
    aliases: list[str] = []
    depth = 0

    for raw in text[start:].splitlines():
        line = raw.split("--", 1)[0] if not raw.strip().startswith("--") else ""
        stripped = line.strip()
        if not stripped:
            continue

        opens, closes = stripped.count("{"), stripped.count("}")

        if current is None and stripped.startswith("{"):
            current = {"aliases": []}
            depth = opens - closes
            continue

        if current is not None:
            for key, value in FIELD.findall(stripped):
                if key in {"id", "dir", "entry", "label", "adapter", "description"}:
                    current.setdefault(key, value)
            if "aliases = {" in stripped:
                current["aliases"].extend(re.findall(r'"([^"]+)"', stripped))
            if "enabledKey" in stripped:
                match = re.search(r'enabledKey\s*=\s*"([^"]+)"', stripped)
                if match:
                    current["enabledKey"] = match.group(1)
            if re.search(r"maintained\s*=\s*true", stripped):
                current["maintained"] = True
            for field in ("claim", "storage", "owner"):
                match = re.search(field + r'\s*=\s*"([^"]+)"', stripped)
                if match:
                    current.setdefault("shared", {})[field] = match.group(1)

            depth += opens - closes
            if depth <= 0:
                if "id" in current and "dir" in current:
                    features.append(current)
                current = None
                depth = 0

    if not features:
        problems.error(f"{path.name} listed no features")
    return features


def check_features(problems: Problems, features: list[dict], quiet: bool) -> None:
    seen_ids: dict[str, str] = {}
    seen_aliases: dict[str, str] = {}

    for feature in features:
        fid = feature["id"]
        label = feature.get("label", fid)

        if fid in seen_ids:
            problems.error(
                f"feature id {fid!r} used by both {seen_ids[fid]} and {label}; "
                "ids are what stored settings are keyed on and must be unique")
        seen_ids[fid] = label

        if not re.fullmatch(r"[a-z][a-z0-9_]*", fid):
            problems.error(f"{label}: id {fid!r} should be lowercase letters, "
                           "digits and underscores")

        entry = feature.get("entry", "main.lua")
        path = MODULES / feature["dir"] / entry
        if not path.exists():
            problems.error(f"{label}: entry {path.relative_to(ROOT)} does not exist "
                           "(run tools/build.py, or check `dir`/`entry`)")

        # The engine accepts two entry shapes and this bundle hosts both.
        # A third one -- a chunk that returns something the runtime cannot
        # use -- would install nothing and say so only in the log, so it is
        # caught here instead.
        try:
            body = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            body = ""
        if body:
            returns_installer = re.search(r"^return function\s*\(", body, re.M)
            takes_chunk_arg = re.search(r"^local\s+\w+\s*=\s*\.\.\.", body, re.M)
            if not returns_installer and not takes_chunk_arg:
                problems.warn(
                    f"{label}: {entry} neither returns an install function nor "
                    "reads its mod from `...`; the runtime will assume it "
                    "installed itself at chunk scope")

        adapter = feature.get("adapter")
        if adapter:
            adapter_path = ADAPTERS / f"{adapter}.lua"
            if not adapter_path.exists():
                problems.error(f"{label}: adapter {adapter_path.relative_to(ROOT)} "
                               "does not exist")

        for alias in feature.get("aliases", []):
            key = alias.lower()
            if key in seen_aliases and seen_aliases[key] != label:
                problems.error(
                    f"alias {alias!r} claimed by both {seen_aliases[key]} and "
                    f"{label}; mod.find would resolve it arbitrarily")
            seen_aliases[key] = label

    if not quiet:
        print(f"  features:   {len(features)} declared, "
              f"{len(seen_aliases)} aliases")


def check_option_keys(problems: Problems, features: list[dict], quiet: bool) -> None:
    """Prove the prefixing actually separates every mod's rows.

    The whole reason the runtime prefixes option keys is that five of these
    mods call their master switch `enabled`.  This re-derives the prefixed keys
    from the vendored source and fails if two of them still land on the same
    string -- which would mean one mod silently reading another's setting.
    """
    define = re.compile(r'key\s*=\s*"([a-zA-Z0-9_]+)"')
    owners: dict[str, str] = {}
    total = 0

    for feature in features:
        directory = MODULES / feature["dir"]
        if not directory.exists():
            continue
        keys: set[str] = set()
        for path in sorted(directory.rglob("*.lua")):
            try:
                keys.update(define.findall(path.read_text(encoding="utf-8",
                                                          errors="ignore")))
            except OSError:
                continue
        for key in sorted(keys):
            prefixed = f"{feature['id']}_{key}"
            total += 1
            label = feature.get("label", feature["id"])
            if prefixed in owners and owners[prefixed] != label:
                problems.error(
                    f"option key {prefixed!r} would be written by both "
                    f"{owners[prefixed]} and {label}")
            owners[prefixed] = label

    if not quiet:
        print(f"  option keys: {total} scanned, {len(owners)} distinct after prefixing")


def check_sources(problems: Problems, features: list[dict], quiet: bool) -> None:
    """Every feature's source is tracked or maintained, and exactly one.

    The distinction is who looks after the code. A `dir` under upstream/ is a
    submodule -- somebody else's mod, pinned to a release, never edited here.
    A `dir` under maintained/ is source this repository owns. Both at once is
    ambiguous and neither means the build has nothing to copy, so both are
    errors rather than something build.py discovers later.
    """
    tracked, owned = 0, 0

    for feature in sorted(features, key=lambda f: f["id"]):
        label = feature.get("label", feature["id"])
        directory = feature.get("dir")
        if not directory:
            continue

        in_upstream = (UPSTREAM / directory).is_dir()
        in_maintained = (MAINTAINED / directory).is_dir()
        declared = feature.get("maintained") is True

        if in_upstream and in_maintained:
            problems.error(
                f"{label}: {directory!r} is both a submodule under upstream/ "
                "and a directory under maintained/; it can only be one")
        elif not in_upstream and not in_maintained:
            problems.error(
                f"{label}: {directory!r} is under neither upstream/ nor "
                "maintained/ (a submodule that is not checked out? run "
                "git submodule update --init --recursive)")
        elif in_maintained:
            owned += 1
            if not declared:
                problems.error(
                    f"{label}: source is under maintained/ but features.lua "
                    "does not say `maintained = true`; sync.py and the README "
                    "read that flag, not the directory")
        else:
            tracked += 1
            if declared:
                problems.error(
                    f"{label}: features.lua says `maintained = true` but the "
                    f"source is the submodule upstream/{directory}, which "
                    "sync.py will keep moving")

    if not quiet:
        print(f"  sources:    {tracked} tracked, {owned} maintained here")


def check_module_reads(problems: Problems, quiet: bool) -> None:
    """Every Lua file a module names in its code is actually in modules/.

    A mod cannot `require` its own files -- its directory is not on
    package.path -- so the supported route is `mod:read("x.lua")` plus load,
    which most features here wrap in a one-line helper and then call with a
    bare filename.  Both ends answer nil for a file that is not there, and
    every one of these helpers reports that to the log and carries on
    without, which is a silent feature outage.

    The bundle has had one: build.py used to strip `build.lua` as build
    furniture, and Gen151 -- which loads build.lua at install and returns
    early without it -- switched itself off on every install while its
    options row still said ALL 151 was on.  This is the check that would
    have said so.

    Comments are cut first, because these files cite engine paths
    (src/ui/Screens.lua) in prose by the dozen and none of those are ours to
    find.  What is left is any "....lua" literal in live code, resolved
    against the module's own directory.
    """
    literal = re.compile(r'"([\w][\w./+-]*\.lua)"')
    checked, missing = 0, 0

    def strip_comments(body: str) -> str:
        """Drop --line and --[[block]] comments, leaving string literals alone."""
        out, i, n = [], 0, len(body)
        while i < n:
            ch = body[i]
            if ch in "\"'":
                quote, j = ch, i + 1
                while j < n and body[j] != quote:
                    j += 2 if body[j] == "\\" else 1
                out.append(body[i:j + 1])
                i = j + 1
            elif body.startswith("--", i):
                if body.startswith("--[[", i):
                    close = body.find("]]", i)
                    i = n if close < 0 else close + 2
                else:
                    stop = body.find("\n", i)
                    i = n if stop < 0 else stop
            else:
                out.append(ch)
                i += 1
        return "".join(out)

    for directory in sorted(p for p in MODULES.iterdir() if p.is_dir()):
        for source in sorted(directory.rglob("*.lua")):
            try:
                body = source.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for wanted in literal.findall(strip_comments(body)):
                checked += 1
                if not (directory / wanted).exists():
                    missing += 1
                    problems.error(
                        f"{source.relative_to(ROOT)} names {wanted!r}, which is "
                        f"not in modules/{directory.name}/ -- a feature that "
                        "loads it will log and switch itself off (is "
                        "tools/build.py excluding it?)")

    if not quiet:
        print(f"  reads:      {checked} named files, {missing} missing")


def check_shared(problems: Problems, features: list[dict], quiet: bool) -> None:
    """A feature carried by both bundles has to be declared the same in both.

    The claim key is what stops the two bundles installing it twice, and the
    storage id is what stops its settings moving when the other bundle wins.
    Get either wrong in one repo and the failure is silent: two mod managers
    wrapped around each other, or a menu layout that resets when the player
    installs the other half. So the declaration here is checked against the
    paired bundle's, when that repo is a sibling on disk.
    """
    shared = {f["id"]: f for f in features if f.get("shared")}
    if not shared:
        if not quiet:
            print("  shared:     none declared")
        return

    claimed_by: dict[str, str] = {}
    for fid, feature in sorted(shared.items()):
        declaration = feature["shared"]
        label = feature.get("label", fid)
        for field in ("claim", "storage"):
            if field not in declaration:
                problems.error(
                    f"{label}: shared features need a {field!r}; without it "
                    "the two bundles cannot agree on "
                    + ("which of them installs it"
                       if field == "claim" else "where its settings live"))

        # Two shared features sharing a claim key is a copy-paste bug that
        # does not fail loudly: the first feature to claim it locks the
        # second one out of the *other* bundle, so whichever bundle loses
        # the race silently ships one feature short.
        claim = declaration.get("claim")
        if claim:
            if claim in claimed_by and claimed_by[claim] != label:
                problems.error(
                    f"{label} and {claimed_by[claim]} both claim {claim!r}; "
                    "each shared feature needs its own claim key or one of "
                    "them will never install")
            claimed_by[claim] = label

    # The paired bundle, if it is checked out beside this one.
    paired_name = "Gen1WildUI" if ROOT.name == "Gen1WildQOL" else "Gen1WildQOL"
    paired = ROOT.parent / paired_name / "features.lua"
    if not paired.exists():
        if not quiet:
            print(f"  shared:     {len(shared)} declared "
                  f"({paired_name} not on disk; cross-check skipped)")
        return

    other_problems = Problems()
    other = {f["id"]: f for f in _parse(paired, other_problems) if f.get("shared")}

    for fid, feature in sorted(shared.items()):
        label = feature.get("label", fid)
        twin = other.get(fid)
        if twin is None:
            problems.error(
                f"{label}: declared shared here but {paired_name} has no "
                f"feature {fid!r}; a shared feature must be in both bundles")
            continue
        for field in ("claim", "storage"):
            mine = feature["shared"].get(field)
            theirs = twin["shared"].get(field)
            if mine != theirs:
                problems.error(
                    f"{label}: shared.{field} is {mine!r} here and "
                    f"{theirs!r} in {paired_name}; they must match")
        if feature.get("dir") != twin.get("dir"):
            problems.error(
                f"{label}: built from {feature.get('dir')!r} here and "
                f"{twin.get('dir')!r} in {paired_name}")

    if not quiet:
        print(f"  shared:     {len(shared)} declared, cross-checked "
              f"against {paired_name}")


def check_options_screen(problems: Problems, quiet: bool) -> None:
    """One row on the game's own OPTION screen, and one only.

    The bundle used to put none there, on the grounds that a mod's settings
    live under MODS.  That was right for a mod and wrong for a suite: a
    player looking for the run button looks in OPTIONS, and MODS >
    GEN1WILD QOL > OPTIONS > SPRINT is three screens and a guess about
    which half owns it.  So the whole suite hangs off one row, and the MODS
    route still lands on the same screens for anyone who goes that way.

    Both halves add that row, so it carries a shared id and each half
    checks for it before inserting: two identical doors onto the same menu
    is the failure this guards.  Losing the MODS route is the other.

    A feature the bundle carries may still register its own row -- that is
    the upstream mod's business, and `suppress_hooks` is how a feature
    whose rows the bundle draws itself stands down.  This looks only at the
    bundle's own runtime.
    """
    menu = ROOT / "runtime" / "menu.lua"
    if not menu.exists():
        problems.error("runtime/menu.lua is missing")
        return
    body = menu.read_text(encoding="utf-8", errors="replace")
    code = "\n".join(line.split("--", 1)[0] for line in body.splitlines())

    wraps = code.count('"ui.options.rows"')
    if wraps == 0:
        problems.error("runtime/menu.lua no longer puts the suite on the "
                       "OPTION screen, which is the only door a player who "
                       "has not been told about MODS will find")
    elif wraps > 1:
        problems.error(f"runtime/menu.lua wraps ui.options.rows {wraps} "
                       "times; one row, once")

    if 'OPTION_ROW_ID = "gen1wild_options"' not in code:
        problems.error("runtime/menu.lua does not use the shared OPTION row "
                       "id, so both halves would add a door of their own")
    elif "existing.id == OPTION_ROW_ID" not in code:
        problems.error("runtime/menu.lua does not check for the other half's "
                       "row before adding its own; two identical doors")

    if "ManagerState" not in code or "openOptions" not in code:
        problems.error("runtime/menu.lua no longer routes MODS > this bundle "
                       "> OPTIONS, which players who learned that route "
                       "still use")
    if not quiet:
        print("  options:    one shared row on the OPTION screen; "
              "MODS route intact")


def check_manifest(problems: Problems, quiet: bool) -> None:
    if not MANIFEST.exists():
        problems.error("manifest.json is missing")
        return
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        problems.error(f"manifest.json is not valid JSON: {exc}")
        return

    for field in ("id", "name", "version", "api", "entry"):
        if field not in manifest:
            problems.error(f"manifest.json has no {field!r}")

    entry = manifest.get("entry", "main.lua")
    if not (ROOT / entry).exists():
        problems.error(f"manifest entry {entry!r} does not exist")

    version = str(manifest.get("version", ""))
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        problems.error(f"manifest version {version!r} is not X.Y.Z")
    elif CHANGELOG.exists():
        body = CHANGELOG.read_text(encoding="utf-8")
        if not re.search(r"^##\s*\[?" + re.escape(version) + r"\]?", body, re.M):
            problems.error(f"CHANGELOG.md has no heading for {version}")

    if not quiet:
        print(f"  manifest:   {manifest.get('id')} {version}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    problems = Problems()
    if not args.quiet:
        print("checking the bundle")

    check_lua_syntax(problems, args.quiet)
    features = parse_features(problems)
    check_features(problems, features, args.quiet)
    check_option_keys(problems, features, args.quiet)
    check_sources(problems, features, args.quiet)
    check_module_reads(problems, args.quiet)
    check_shared(problems, features, args.quiet)
    check_options_screen(problems, args.quiet)
    check_manifest(problems, args.quiet)

    for warning in problems.warnings:
        print(f"warning: {warning}", file=sys.stderr)
    for error in problems.errors:
        print(f"error: {error}", file=sys.stderr)

    if problems.errors:
        print(f"\n{len(problems.errors)} problem(s).", file=sys.stderr)
        return 1
    if not args.quiet:
        print("\nall checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
