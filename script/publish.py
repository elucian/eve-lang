#!/usr/bin/env python3
"""Release: publish the distribution of the version on GitHub with the gh command.

Usage: python script/publish.py [--dry-run] [--prerelease]

It uploads the archives listed in dist/SHA256SUMS.txt (eve-X.Y.Z-windows-x64.zip, eve-X.Y.Z-linux-x64.tar.gz,
made by script/dist.py) and that file to a GitHub release `vX.Y.Z`, with the notes manual/releases/vX.Y.Z.md. The release points at the commit
of the tag vX.Y.Z, which must be committed, tagged and pushed first (design/release.md, step 9).
Needs gh (GitHub CLI) logged in. `--dry-run` prints the command and changes nothing. `--prerelease` marks the
release as a pre-release on GitHub and titles it "Eve X.Y.Z (alpha)": an early build, not the latest stable release.
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
    pre = "--prerelease" in argv
    if any(a not in ("--dry-run", "--prerelease") for a in argv):
        die("usage: python script/publish.py [--dry-run] [--prerelease]")
    ver = version()
    tag = f"v{ver}"
    sums = os.path.join(DIST, "SHA256SUMS.txt")
    notes = os.path.join(ROOT, "manual", "releases", f"{tag}.md")
    for path, what in [(sums, "SHA256SUMS.txt of dist/ (run ./run.sh dist)"),
                       (notes, f"the release notes manual/releases/{tag}.md (script/relnotes.py, then the hand-written parts)")]:
        if not os.path.isfile(path):
            die(f"missing {what}: {os.path.relpath(path, ROOT)}")
    with open(sums, encoding="utf-8") as f:
        archives = [os.path.join(DIST, line.split()[1]) for line in f if line.strip()]
    if not archives or any(f"-{ver}-" not in os.path.basename(a) for a in archives):
        die(f"dist/SHA256SUMS.txt does not list the archives of {ver} (run ./run.sh dist)")
    for path in archives:
        if not os.path.isfile(path):
            die(f"missing the archive {os.path.relpath(path, ROOT)} (run ./run.sh dist)")
    code, status = git("status", "--porcelain")
    if code != 0 or status:
        die("the tree is not clean: commit the release first (design/release.md, step 9)")
    code, commit = git("rev-parse", "--verify", "--quiet", f"{tag}^{{commit}}")
    if code != 0:
        die(f"no tag {tag}: create it with git tag {tag} on the release commit, and push it")
    if shutil.which("gh") is None and not dry:
        die("gh (GitHub CLI) is not installed or not on the PATH: winget install GitHub.cli, then gh auth login")
    title = f"Eve {ver} (alpha)" if pre else f"Eve {ver}"
    cmd = ["gh", "release", "create", tag, "--title", title, "--notes-file", notes, "--verify-tag"] + \
        (["--prerelease"] if pre else []) + archives + [sums]
    print(" ".join(cmd))
    if dry:
        print("dry run: nothing published")
        return
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        die("gh release create failed (is the tag pushed? is gh logged in?)")
    print(f"published {tag} with {', '.join(os.path.basename(a) for a in archives)}")


if __name__ == "__main__":
    main(sys.argv[1:])
