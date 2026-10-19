#!/usr/bin/env python3
"""Release: publish the distribution of the version on GitHub with the gh command.

Usage: python script/publish.py [--dry-run]

It uploads dist/eve-X.Y.Z-windows-x64.zip and dist/SHA256SUMS.txt (made by script/dist.py) to a
GitHub release `vX.Y.Z`, with the notes manual/releases/vX.Y.Z.md. The release points at the commit
of the tag vX.Y.Z, which must be committed, tagged and pushed first (design/release.md, step 9).
Needs gh (GitHub CLI) logged in. `--dry-run` prints the command and changes nothing.
Step: `./run.sh release`.
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")


def die(msg):
    print(f"release: {msg}", file=sys.stderr)
    sys.exit(1)


def git(*args):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return r.returncode, r.stdout.strip()


def version():
    with open(os.path.join(ROOT, "build.zig.zon"), encoding="utf-8") as f:
        m = re.search(r'\.version = "(\d+\.\d+\.\d+)"', f.read())
    if not m:
        die("no version found in build.zig.zon")
    return m.group(1)


def main(argv):
    dry = "--dry-run" in argv
    if any(a != "--dry-run" for a in argv):
        die("usage: python script/publish.py [--dry-run]")
    ver = version()
    tag = f"v{ver}"
    zip_path = os.path.join(DIST, f"eve-{ver}-windows-x64.zip")
    sums = os.path.join(DIST, "SHA256SUMS.txt")
    notes = os.path.join(ROOT, "manual", "releases", f"{tag}.md")
    for path, what in [(zip_path, "the zip of dist/ (run ./run.sh dist)"), (sums, "SHA256SUMS.txt of dist/ (run ./run.sh dist)"),
                       (notes, f"the release notes manual/releases/{tag}.md (script/relnotes.py, then the hand-written parts)")]:
        if not os.path.isfile(path):
            die(f"missing {what}: {os.path.relpath(path, ROOT)}")
    code, status = git("status", "--porcelain")
    if code != 0 or status:
        die("the tree is not clean: commit the release first (design/release.md, step 9)")
    code, commit = git("rev-parse", "--verify", "--quiet", f"{tag}^{{commit}}")
    if code != 0:
        die(f"no tag {tag}: create it with git tag {tag} on the release commit, and push it")
    if shutil.which("gh") is None and not dry:
        die("gh (GitHub CLI) is not installed or not on the PATH: winget install GitHub.cli, then gh auth login")
    cmd = ["gh", "release", "create", tag, "--title", f"Eve {ver}", "--notes-file", notes, "--target", commit,
           zip_path, sums]
    print(" ".join(cmd))
    if dry:
        print("dry run: nothing published")
        return
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        die("gh release create failed (is the tag pushed? is gh logged in?)")
    print(f"published {tag} with {os.path.basename(zip_path)}")


if __name__ == "__main__":
    main(sys.argv[1:])
