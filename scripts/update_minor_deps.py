#!/usr/bin/env python3
"""Raise in-major dependency ranges after a publish cooldown.

Mirrors the Paluma Trails / crag-stats nightly job: only rewrite constraint
files (`pubspec.yaml`, `package.json`). Lockfiles are refreshed afterwards so
CI can still install; they are not the intentional edit surface.

For Dart/Flutter packages the rules match npm-check-updates `--target semver`:
- major >= 1: stay on the same major (`^1.2.3` may become `^1.9.0`)
- 0.x: stay on the same minor (`^0.14.4` may become `^0.14.9`)

Versions published within COOLDOWN_DAYS are skipped so a hijacked release has
time to be yanked before it reaches a homeserver image.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_COOLDOWN_DAYS = 3

DART_PACKAGES = (
    (ROOT / "pubspec.yaml", ["flutter", "pub"]),
)

NODE_PACKAGES = (
    ROOT / "scripts" / "branding" / "package.json",
    ROOT / "scripts" / "web_smoke" / "package.json",
)

CARET_LINE = re.compile(
    r"^(\s*)([\w.]+):\s*(\^)([0-9][0-9A-Za-z.+-]*)\s*(#.*)?$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cooldown-days",
        type=int,
        default=DEFAULT_COOLDOWN_DAYS,
        help="Skip versions younger than this many days (default: %(default)s)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned edits without writing files",
    )
    return parser.parse_args()


def semver_tuple(version: str) -> tuple[int, int, int]:
    core = version.split("+", 1)[0].split("-", 1)[0]
    parts = core.split(".")
    nums = []
    for part in parts[:3]:
        nums.append(int(part) if part.isdigit() else 0)
    while len(nums) < 3:
        nums.append(0)
    return nums[0], nums[1], nums[2]


def allowed_upper(current: str) -> tuple[int, int | None]:
    """Return (major, minor_or_None) bound for --target semver."""
    major, minor, _ = semver_tuple(current)
    if major == 0:
        return 0, minor
    return major, None


def version_allowed(candidate: str, current: str) -> bool:
    c_major, c_minor, _ = semver_tuple(candidate)
    a_major, a_minor = allowed_upper(current)
    if c_major != a_major:
        return False
    if a_minor is not None and c_minor != a_minor:
        return False
    return semver_tuple(candidate) > semver_tuple(current)


def fetch_package(name: str) -> dict:
    url = f"https://pub.dev/api/packages/{name}"
    request = urllib.request.Request(
        url, headers={"User-Agent": "glowing-waffle-deps"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def newest_cooled(
    name: str, current: str, cooldown: timedelta, now: datetime
) -> str | None:
    try:
        payload = fetch_package(name)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"  skip {name}: could not fetch pub.dev ({error})", file=sys.stderr)
        return None

    best: str | None = None
    for entry in payload.get("versions", []):
        version = entry.get("version")
        if not version or "-" in version.split("+", 1)[0]:
            continue  # skip prereleases
        if not version_allowed(version, current):
            continue
        published = entry.get("published")
        if not published:
            continue
        published_at = datetime.fromisoformat(published.replace("Z", "+00:00"))
        if now - published_at < cooldown:
            continue
        if best is None or semver_tuple(version) > semver_tuple(best):
            best = version
    return best


def update_pubspec(
    path: Path, cooldown: timedelta, now: datetime, dry_run: bool
) -> bool:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    changed = False
    in_deps = False
    print(f"\n{path.relative_to(ROOT)}")
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped in ("dependencies:", "dev_dependencies:"):
            in_deps = True
            continue
        if in_deps and stripped and not line[:1].isspace() and ":" in stripped:
            # Top-level key ended the dependency block (e.g. flutter:).
            if not stripped.startswith("#"):
                in_deps = False
        if not in_deps:
            continue
        match = CARET_LINE.match(line.rstrip("\n"))
        if not match:
            continue
        indent, name, caret, current, comment = match.groups()
        if name in ("flutter", "sdk"):
            continue
        best = newest_cooled(name, current, cooldown, now)
        if best is None:
            print(f"  {name}: ^{current} (unchanged)")
            continue
        if best == current:
            print(f"  {name}: ^{current} (unchanged)")
            continue
        suffix = f" {comment}" if comment else ""
        new_line = f"{indent}{name}: {caret}{best}{suffix}\n"
        print(f"  {name}: ^{current} -> ^{best}")
        if not dry_run:
            lines[index] = new_line
        changed = True
    if changed and not dry_run:
        path.write_text("".join(lines), encoding="utf-8")
    return changed


def sync_lock(pubspec: Path, pub_cmd: list[str]) -> None:
    cwd = pubspec.parent
    print(f"  syncing lockfile in {cwd.relative_to(ROOT)} …")
    subprocess.run([*pub_cmd, "get"], cwd=cwd, check=True)


def update_node_package(path: Path, cooldown_days: int, dry_run: bool) -> bool:
    if not path.exists():
        return False
    print(f"\n{path.relative_to(ROOT)}")
    before = path.read_text(encoding="utf-8")
    # Without --upgrade, ncu only prints; with it, it rewrites package.json.
    # (There is no --dry-run flag on npm-check-updates@23.)
    upgrade_flag = "--upgrade" if not dry_run else ""
    cmd = (
        f'npx --yes npm-check-updates@23.1.1 --target semver '
        f'--cooldown {cooldown_days} {upgrade_flag} '
        f'--packageFile "{path}"'
    )
    try:
        subprocess.run(cmd, cwd=ROOT, check=True, shell=True)
    except subprocess.CalledProcessError as error:
        print(f"  warning: npm-check-updates failed ({error})", file=sys.stderr)
        return False
    after = path.read_text(encoding="utf-8")
    changed = before != after
    if dry_run:
        print("  (dry-run; package.json not written)")
        return False
    if changed:
        print("  package.json updated")
    else:
        print("  unchanged")
    return changed


def main() -> int:
    args = parse_args()
    cooldown = timedelta(days=args.cooldown_days)
    now = datetime.now(timezone.utc)
    any_changed = False

    for pubspec, pub_cmd in DART_PACKAGES:
        if not pubspec.exists():
            print(f"missing {pubspec}", file=sys.stderr)
            return 2
        if update_pubspec(pubspec, cooldown, now, args.dry_run):
            any_changed = True
            if not args.dry_run:
                sync_lock(pubspec, pub_cmd)

    for node_package in NODE_PACKAGES:
        if update_node_package(node_package, args.cooldown_days, args.dry_run):
            any_changed = True

    if not any_changed:
        print("\nNo in-major dependency ranges to raise.")
        return 0
    print("\nConstraint files updated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
