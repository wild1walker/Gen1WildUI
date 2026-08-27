#!/usr/bin/env python3
"""Assemble modules/ from upstream/ and maintained/.

A feature's source lives in one of two places, and which one says who looks
after it:

    upstream/<Repo>/     a submodule pinned to a release.  Somebody else's
                         mod, tracked, never edited here.  tools/sync.py moves
                         the pin; the source is whatever they published.
    maintained/<Dir>/    source this repository looks after itself.  Edited
                         here, and nothing syncs it from anywhere.
    modules/<Dir>/       what the game reads, written by this script.

Most features are the first kind.  The two that are not were originally other
people's mods and are now maintained here -- see `maintained` in features.lua,
and the credits in README.md, which stay either way.

modules/ is committed rather than generated at install time, because a mod is
installed by copying a folder or importing a .zip and neither runs a build.
Committing it also means an upstream bump shows up as a reviewable diff in this
repo rather than as a submodule pointer nobody can read.

modules/ is committed rather than generated at install time, because a mod is
installed by copying a folder or importing a .zip and neither runs a build.
Committing it also means an upstream bump shows up as a reviewable diff in this
repo rather than as a submodule pointer nobody can read.

CI runs this and fails if the result differs from what is committed, so the two
can never drift.

Usage:
    python3 tools/build.py            rebuild modules/ in place
    python3 tools/build.py --check    fail if modules/ is not what a build gives
"""

from __future__ import annotations

import argparse
import filecmp
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = ROOT / "upstream"
MAINTAINED = ROOT / "maintained"
OVERLAYS = ROOT / "overlays"
MODULES = ROOT / "modules"
FEATURES = ROOT / "features.lua"

# Repository furniture: real in the source repo, dead weight inside a mod the
# game loads.  Dropped on the way in.
EXCLUDE_DIRS = {
    ".git", ".github", "tests", "tools", "docs", "site", "images",
    "__pycache__", ".vscode",
}
EXCLUDE_FILES = {
    # A submodule checkout carries `.git` as a *file* holding a gitdir
    # pointer, not a directory, so excluding the directory name is not
    # enough -- and copying it makes git treat modules/<Dir> as an embedded
    # repository and commit a gitlink instead of the files.
    ".git", ".gitignore", ".gitattributes", ".gitmodules",
    ".luarc.json", ".modkitignore", ".gen1wild",
    "mod.card", "manifest.json",
    "convert.py", "palettize.py", "recolor.py",
}

# Not excluded, and worth saying why, because they were: `build.lua` and
# `bench.lua` read like build furniture and are not.  Gen1WildQOL learned
# this the hard way -- Gen151 ships both as RUNTIME modules and gives up on
# the whole feature when build.lua is missing, so stripping it switched ALL
# 151 off on every install while its options row still said it was on.  No
# mod tracked here ships either file today; the rule is kept the same in both
# bundles so a future one cannot inherit the outage.  A .lua file in a mod's
# root is mod code; a real build script in these repositories is Python under
# tools/, which EXCLUDE_DIRS and EXCLUDE_SUFFIXES already drop.
EXCLUDE_SUFFIXES = {".py", ".ps1", ".sh", ".yml", ".yaml"}

# Documentation worth carrying: a licence and an attribution notice travel with
# the code they cover, and several of these mods are other people's work.
KEEP_DOCS = {
    "LICENSE", "LICENSE.md", "LICENCE", "COPYING",
    "THIRD_PARTY_NOTICES.md", "CREDITS.md", "NOTICE",
}


def fail(message: str) -> "NoReturn":  # type: ignore[valid-type]
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_registry() -> list[dict]:
    """Pull the feature list out of features.lua.

    features.lua is Lua, not data, and this script has no Lua to run it with.
    It only needs four fields per entry, all of which are written as plain
    `key = "value"` lines, so a narrow scan is enough -- and a great deal less
    fragile than teaching this script to parse Lua.
    """
    if not FEATURES.exists():
        fail("features.lua not found")
    text = FEATURES.read_text(encoding="utf-8")

    features: list[dict] = []
    current: dict | None = None
    depth = 0
    in_features = False

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("features = {"):
            in_features = True
            continue
        if not in_features:
            continue

        depth += stripped.count("{") - stripped.count("}")

        if stripped.startswith("{") and current is None:
            current = {}
            continue

        for key in ("id", "dir", "entry", "upstream", "label"):
            token = f'{key} = "'
            if stripped.startswith(token):
                value = stripped[len(token):].split('"', 1)[0]
                if current is not None:
                    current[key] = value

        if stripped.startswith("},") and current:
            if "dir" in current:
                features.append(current)
            current = None

    if not features:
        fail("features.lua listed no features -- has its format changed?")
    return features


def submodule_paths() -> dict[str, Path]:
    """Map a submodule's directory name to its path on disk."""
    if not UPSTREAM.exists():
        return {}
    return {p.name: p for p in sorted(UPSTREAM.iterdir()) if p.is_dir()}


def maintained_paths() -> dict[str, Path]:
    """Map a maintained feature's directory name to its path on disk."""
    if not MAINTAINED.exists():
        return {}
    return {p.name: p for p in sorted(MAINTAINED.iterdir()) if p.is_dir()}


def should_copy(path: Path, relative: Path) -> bool:
    for part in relative.parts[:-1]:
        if part in EXCLUDE_DIRS:
            return False
    name = path.name
    if name in KEEP_DOCS:
        return True
    if name in EXCLUDE_FILES:
        return False
    if path.suffix in EXCLUDE_SUFFIXES:
        return False
    # Markdown that is not a licence is README furniture.
    if path.suffix == ".md" and name not in KEEP_DOCS:
        return False
    return True


def copy_tree(source: Path, destination: Path) -> int:
    copied = 0
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if any(part.startswith(".") for part in relative.parts[:-1]):
            continue
        if not should_copy(path, relative):
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied += 1
    return copied


def upstream_version(source: Path) -> str | None:
    manifest = source / "manifest.json"
    if not manifest.exists():
        # Gen1ModernBag nests its mod one folder down.
        candidates = sorted(source.glob("*/manifest.json"))
        if not candidates:
            return None
        manifest = candidates[0]
    try:
        return str(json.loads(manifest.read_text(encoding="utf-8")).get("version"))
    except (json.JSONDecodeError, OSError):
        return None


def resolve_source(repo_dir: Path) -> Path:
    """The folder inside the submodule that actually holds the mod.

    Most of these repos put manifest.json at the root.  Gen1ModernBag puts the
    mod in a `gen1_modern_bag/` subfolder and keeps README artwork at the root,
    so the manifest is what is searched for rather than assumed.
    """
    if (repo_dir / "manifest.json").exists():
        return repo_dir
    nested = sorted(repo_dir.glob("*/manifest.json"))
    if nested:
        return nested[0].parent
    return repo_dir


def git_revision(path: Path) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=False,
        )
        return out.stdout.strip() or "unknown"
    except OSError:
        return "unknown"


def build(destination: Path) -> list[str]:
    features = read_registry()
    tracked = submodule_paths()
    owned = maintained_paths()

    wanted: dict[str, list[dict]] = {}
    for feature in features:
        wanted.setdefault(feature["dir"], []).append(feature)

    lines: list[str] = []
    missing: list[str] = []
    versions_seen: dict[str, str] = {}

    for directory, entries in sorted(wanted.items()):
        repo_dir = tracked.get(directory)
        owned_dir = owned.get(directory)

        if repo_dir is not None and owned_dir is not None:
            fail(f"{directory} is both a submodule under upstream/ and a "
                 "directory under maintained/; it can only be one. Delete "
                 "whichever is not the source of truth.")

        if owned_dir is not None:
            # Maintained here: the source is the source, no overlay step and
            # no version to read off a manifest that is not there.
            target = destination / directory
            if target.exists():
                shutil.rmtree(target)
            count = copy_tree(owned_dir, target)
            names = ", ".join(sorted(e.get("label", e["id"]) for e in entries))
            versions_seen[directory] = upstream_version(owned_dir) or "maintained"
            lines.append(
                f"{directory:<18} {'maintained':>10}  {'':<9} "
                f"{count:>3} files              {names}"
            )
            continue

        if repo_dir is None or not any(repo_dir.iterdir()):
            missing.append(directory)
            continue

        source = resolve_source(repo_dir)
        target = destination / directory
        if target.exists():
            shutil.rmtree(target)
        count = copy_tree(source, target)

        overlay = OVERLAYS / directory
        overlaid = 0
        if overlay.exists():
            overlaid = copy_tree(overlay, target)

        version = upstream_version(repo_dir) or "?"
        versions_seen[directory] = version
        revision = git_revision(repo_dir)
        names = ", ".join(sorted(e.get("label", e["id"]) for e in entries))
        lines.append(
            f"{directory:<18} {version:>10}  {revision:<9} "
            f"{count:>3} files +{overlaid} overlay   {names}"
        )

    for stray in destination.rglob(".git"):
        fail(f"{stray} was copied into the build; git would record a gitlink "
             "instead of the files. This is a bug in should_copy().")

    # A dir -> version map for the runtime. mod.find hands back a handle
    # shaped like the engine's, and the engine's carries the found mod's
    # version; without this the bundle could not fill that field in, and a
    # mod that logs it (Gen151 does, when Gen1Dex is too old to have the
    # surface it wants) would print nil.
    lines_out = ["-- Written by tools/build.py. The version of the mod in each",
                 "-- modules/<dir>, for the handles runtime/registry.lua hands to",
                 "-- mod.find. Do not edit; rebuild.", "return {"]
    for directory in sorted(versions_seen):
        lines_out.append('  ["%s"] = %s,' % (directory, json.dumps(versions_seen[directory])))
    lines_out.append("}")
    (destination / "versions.lua").write_text("\n".join(lines_out) + "\n",
                                              encoding="utf-8")

    if missing:
        fail(
            "no source for: "
            + ", ".join(sorted(missing))
            + "\neither the submodule is not checked out (run: git submodule "
              "update --init --recursive) or features.lua names a `dir` that "
              "exists under neither upstream/ nor maintained/"
        )
    return lines


def trees_differ(left: Path, right: Path) -> list[str]:
    """Every path that differs between two trees, as repo-relative strings."""
    differences: list[str] = []

    def walk(a: Path, b: Path, prefix: Path) -> None:
        comparison = filecmp.dircmp(str(a), str(b))
        for name in comparison.left_only:
            differences.append(str(prefix / name) + " (only in committed)")
        for name in comparison.right_only:
            differences.append(str(prefix / name) + " (only in rebuilt)")
        for name in comparison.diff_files:
            differences.append(str(prefix / name) + " (contents differ)")
        for name in comparison.common_dirs:
            walk(a / name, b / name, prefix / name)

    if not left.exists():
        return ["modules/ has never been built"]
    walk(left, right, Path("modules"))
    return differences


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true",
                        help="fail if modules/ differs from a fresh build")
    args = parser.parse_args()

    if args.check:
        staging = ROOT / ".build-check"
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir()
        try:
            build(staging)
            differences = trees_differ(MODULES, staging)
        finally:
            shutil.rmtree(staging, ignore_errors=True)

        if differences:
            print("modules/ is out of date with upstream/:", file=sys.stderr)
            for entry in differences[:40]:
                print(f"  {entry}", file=sys.stderr)
            if len(differences) > 40:
                print(f"  ... and {len(differences) - 40} more", file=sys.stderr)
            print("\nrun: python3 tools/build.py && git add modules", file=sys.stderr)
            return 1
        print("modules/ matches upstream/")
        return 0

    if MODULES.exists():
        shutil.rmtree(MODULES)
    MODULES.mkdir()
    lines = build(MODULES)
    print(f"built modules/ from {len(lines)} sources\n")
    for line in lines:
        print("  " + line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
