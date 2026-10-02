#!/usr/bin/env python3
"""Release: bump the version label everywhere, then build and test the VM.

Usage: python script/release.py [patch|minor|major|X.Y.Z] [--dry-run]

The current version is read from evevm/src/version.zig (`pub const version`). The default bump is
patch. These labels are rewritten, keeping each file's line endings:
  evevm/src/version.zig   pub const version = "X.Y.Z";   (shown by `eve -v`)
  evevm/build.zig.zon     .version = "X.Y.Z",
  evevm/README.md         Version: **X.Y.Z**
  README.md               Version <strong>X.Y.Z</strong>
Then it runs `zig build -p ..` and `zig build test` in evevm/. It does not commit or tag:
review `git diff`, then commit and tag yourself (the command is printed).
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
V = r"\d+\.\d+\.\d+"
# (file, regex with the version in group 2, replacement template with {} for the version)
LABELS = [
    ("evevm/src/version.zig", rf'(pub const version = ")({V})(")'),
    ("evevm/build.zig.zon", rf'(\.version = ")({V})(")'),
    ("evevm/README.md", rf"(Version: \*\*)({V})(\*\*)"),
    ("README.md", rf"(Version <strong>)({V})(</strong>)"),
]


def die(msg):
    sys.exit(f"release: {msg}")


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8", newline="") as f:
        return f.read()


def bump(current, how):
    major, minor, patch = map(int, current.split("."))
    if how == "major":
        return f"{major + 1}.0.0"
    if how == "minor":
        return f"{major}.{minor + 1}.0"
    if how == "patch":
        return f"{major}.{minor}.{patch + 1}"
    if re.fullmatch(V, how):
        return how
    die(f"unknown bump {how!r}: use patch, minor, major or X.Y.Z")


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    if len(args) > 1 or any(a in ("-h", "--help") for a in args):
        print(__doc__)
        return
    m = re.search(LABELS[0][1], read(LABELS[0][0]))
    if not m:
        die("no version found in evevm/src/version.zig")
    old = m.group(2)
    new = bump(old, args[0] if args else "patch")

    # Check every label first: nothing is written when one is missing or out of step.
    for rel, pat in LABELS:
        found = re.findall(pat, read(rel))
        if len(found) != 1:
            die(f"{rel}: expected one version label, found {len(found)}")
        if found[0][1] != old:
            die(f"{rel}: label is {found[0][1]}, version.zig says {old}; fix it by hand first")
    print(f"release: {old} -> {new}" + ("  (dry run)" if dry else ""))
    if dry:
        return
    saved = {rel: read(rel) for rel, _ in LABELS}
    for rel, pat in LABELS:
        text = re.sub(pat, lambda g: g.group(1) + new + g.group(3), saved[rel])
        with open(os.path.join(ROOT, rel), "w", encoding="utf-8", newline="") as f:
            f.write(text)
        print(f"  {rel}")

    evevm = os.path.join(ROOT, "evevm")
    for cmd in (["zig", "build", "-p", ".."], ["zig", "build", "test"]):
        print("  " + " ".join(cmd))
        if subprocess.run(cmd, cwd=evevm).returncode:
            for rel, text in saved.items():      # roll back: a failed release leaves nothing changed
                with open(os.path.join(ROOT, rel), "w", encoding="utf-8", newline="") as f:
                    f.write(text)
            die("build or tests failed, labels restored to " + old + ". On Windows, "
                "'AccessDenied' on bin/eve.exe means an eve REPL is still running: quit it first.")
    print(f"done. Review, then:\n  git commit -am 'Release {new}' && git tag v{new}")


if __name__ == "__main__":
    main()
