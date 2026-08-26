#!/usr/bin/env python3
"""Bring the bundle up to date with the mods it tracks.

This is the whole update story for the tracked half of the bundle.  Those
features live in their own repositories, pinned here as submodules; this moves
the pins to the newest release each mod has published, rebuilds modules/, and
reports what moved so the diff can be read before it is committed.

Features under maintained/ are not tracked and are not touched: this repository
looks after their source itself, so there is nothing to sync them from.  They
are listed at the end of a run so a `sync` that reports fewer repositories than
features.lua has is not a surprise.

    python3 tools/sync.py                  every feature, to its latest release
    python3 tools/sync.py Gen1Sprint       just that one
    python3 tools/sync.py --to-main        track each repo's default branch
    python3 tools/sync.py --dry-run        report, change nothing

Releases are preferred over branch tips because that is what the standalone
mods ask players to install, and what their own CI has gated.  --to-main is
there for testing an upstream change before it is cut.

Nothing here commits.  Read the diff, then commit it.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = ROOT / "upstream"
MAINTAINED = ROOT / "maintained"

SEMVER_TAG = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def git(*args: str, cwd: Path | None = None, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=str(cwd) if cwd else None,
        capture_output=True, text=True, check=False,
    )
    if check and result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        raise SystemExit(f"error: git {' '.join(args)}: {message}")
    return result.stdout.strip()


def submodules() -> list[Path]:
    if not UPSTREAM.exists():
        raise SystemExit("error: upstream/ not found; run git submodule update --init")
    return [p for p in sorted(UPSTREAM.iterdir()) if (p / ".git").exists()]


def maintained() -> list[str]:
    """Directory names this repository looks after itself."""
    if not MAINTAINED.exists():
        return []
    return [p.name for p in sorted(MAINTAINED.iterdir()) if p.is_dir()]


def latest_release_tag(repo: Path) -> str | None:
    """The highest vX.Y.Z tag, which is what these repos release under."""
    git("fetch", "--tags", "--quiet", "origin", cwd=repo, check=False)
    versions: list[tuple[tuple[int, int, int], str]] = []
    for tag in git("tag", "-l", cwd=repo, check=False).splitlines():
        match = SEMVER_TAG.match(tag.strip())
        if match:
            versions.append((tuple(int(p) for p in match.groups()), tag.strip()))
    if not versions:
        return None
    versions.sort()
    return versions[-1][1]


def default_branch(repo: Path) -> str:
    head = git("symbolic-ref", "--quiet", "refs/remotes/origin/HEAD",
               cwd=repo, check=False)
    if head:
        return head.rsplit("/", 1)[-1]
    for candidate in ("main", "master", "dev"):
        if git("rev-parse", "--verify", "--quiet", f"origin/{candidate}",
               cwd=repo, check=False):
            return candidate
    return "main"


def describe(repo: Path) -> str:
    tag = git("describe", "--tags", "--exact-match", cwd=repo, check=False)
    if tag:
        return tag
    return git("rev-parse", "--short", "HEAD", cwd=repo, check=False) or "unknown"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("only", nargs="*",
                        help="submodule directory names; default is all of them")
    parser.add_argument("--to-main", action="store_true",
                        help="track each repository's default branch instead of "
                             "its newest release")
    parser.add_argument("--dry-run", action="store_true",
                        help="report what would move without moving it")
    args = parser.parse_args()

    repos = submodules()
    owned = maintained()

    if args.only:
        wanted = set(args.only)
        repos = [r for r in repos if r.name in wanted]
        unknown = wanted - {r.name for r in repos}
        # Naming a maintained feature is a reasonable mistake to make, so say
        # what it actually is rather than "no such submodule".
        asked_for_owned = sorted(unknown & set(owned))
        if asked_for_owned:
            raise SystemExit(
                "error: " + ", ".join(asked_for_owned) + " "
                + ("is" if len(asked_for_owned) == 1 else "are")
                + " maintained in this repository, not tracked; there is "
                  "nothing to sync it from. Edit maintained/"
                + asked_for_owned[0] + "/ directly.")
        if unknown - set(owned):
            raise SystemExit(
                f"error: no such submodule: {', '.join(sorted(unknown - set(owned)))}")
    if not repos:
        raise SystemExit("error: nothing to sync")

    moved: list[tuple[str, str, str]] = []
    unchanged: list[str] = []

    for repo in repos:
        # Fetch before describing: a fresh shallow clone has no tags, so
        # describing it first labels a repository that is exactly on its
        # release with a bare SHA and the run reads as though everything
        # moved.
        git("fetch", "--quiet", "origin", cwd=repo, check=False)
        git("fetch", "--tags", "--quiet", "origin", cwd=repo, check=False)
        before = describe(repo)

        if args.to_main:
            branch = default_branch(repo)
            target = f"origin/{branch}"
            label = branch
        else:
            tag = latest_release_tag(repo)
            if tag is None:
                branch = default_branch(repo)
                target = f"origin/{branch}"
                label = f"{branch} (no releases)"
            else:
                target, label = tag, tag

        head = git("rev-parse", "HEAD", cwd=repo, check=False)
        wanted_sha = git("rev-parse", f"{target}^{{commit}}", cwd=repo, check=False)

        if not wanted_sha:
            print(f"  {repo.name:<18} could not resolve {target}; left at {before}")
            continue

        if head == wanted_sha:
            unchanged.append(f"{repo.name} @ {before}")
            continue

        if args.dry_run:
            moved.append((repo.name, before, label))
            continue

        git("checkout", "--quiet", "--detach", wanted_sha, cwd=repo)
        moved.append((repo.name, before, label))

    print(f"{'unchanged' if args.dry_run else 'synced'}: "
          f"{len(unchanged)} already current, {len(moved)} "
          f"{'would move' if args.dry_run else 'moved'}\n")

    for name in unchanged:
        print(f"  = {name}")
    for name, before, after in moved:
        print(f"  > {name:<18} {before} -> {after}")

    if owned and not args.only:
        print("\nmaintained here, not tracked (nothing to sync):")
        for name in owned:
            print(f"  ~ {name}")

    if not moved:
        print("\nnothing to do.")
        return 0

    if args.dry_run:
        print("\ndry run; nothing changed.")
        return 0

    print("\nrebuilding modules/ ...")
    result = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "build.py")],
        cwd=str(ROOT), check=False)
    if result.returncode != 0:
        return result.returncode

    print(
        "\nNext:\n"
        "  git diff --stat modules upstream    what actually changed\n"
        "  python3 tools/check.py              the bundle's own checks\n"
        "  git add upstream modules && git commit\n"
        "\nIf an upstream added an option row, it appears in the bundle menu on\n"
        "its own -- the schema is read at load. If it added a whole feature,\n"
        "or renamed an option key, features.lua needs the edit."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
