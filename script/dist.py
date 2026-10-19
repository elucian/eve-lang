#!/usr/bin/env python3
"""Dist: build the distribution of the current version in dist/, zip it, and archive the older ones.

Usage: python script/dist.py [--no-build]

dist/ is generated and git-ignored. Its layout:
  dist/README.md                     what the folder holds (written by this script)
  dist/eve-X.Y.Z-windows-x64/        the current release, unzipped:
      README.md                      from design/template/dist-readme.md
      LICENSE, TRADEMARK.md
      bin/                           eve.exe, evevm.exe, evedb.exe, evetx.exe, eveux.exe, duckdb.dll (ReleaseSafe)
      lib/                           the Eve library with its docs (eve finds it at ../lib from bin/)
      manual/                        manual/ of the repository, with its generated pages and the component docs
                                     made again for this release (script/genmanual.py --out)
      tools/                         the editor plugins and the typing aids (no nested repositories)
  dist/eve-X.Y.Z-windows-x64.zip     that folder zipped (unzip gives the folder)
  dist/SHA256SUMS.txt                the SHA-256 of the current zip (script/publish.py uploads both)
  dist/archive/                      the zips of the older releases, and their SHA256SUMS.txt
When the version changes, the zip of the previous release moves to dist/archive/ and its folder is removed;
a dist of the same version replaces the current release. The repository is never changed.
Not in the distribution: design/, backlog/, test/, script/, spec/, comp/eve/ and the source code.
`--no-build` keeps the binaries already in the release folder and stages, checks and zips again.
Step: `./run.sh dist` (Windows only for now). Publishing: `./run.sh release` (script/publish.py).
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
ARCHIVE = os.path.join(DIST, "archive")
PLATFORM = ("windows-x64", "Windows (x64)")
# the folders with a build.zig: the root (eve, evevm, lib), then the parts that have their own
PARTS = [ROOT, os.path.join(ROOT, "drivers", "duckdb")] + [os.path.join(ROOT, "comp", p) for p in ("evecp", "evetx", "eveux")]
EXPECTED = ["bin/eve.exe", "bin/evevm.exe", "bin/evecp.exe", "bin/evedb.exe", "bin/evetx.exe", "bin/eveux.exe", "bin/duckdb.dll",
            "lib/config.eve", "manual/README.md", "manual/features.md", "manual/evevm/README.md", "README.md", "LICENSE"]
SKIP_NAMES = {".git", ".gitignore", "__pycache__", "node_modules", ".zig-cache", "zig-out"}
NAME = re.compile(r"eve-(\d+\.\d+\.\d+)-" + PLATFORM[0] + r"(\.zip)?$")


def die(msg):
    print(f"dist: {msg}", file=sys.stderr)
    sys.exit(1)


def version():
    with open(os.path.join(ROOT, "build.zig.zon"), encoding="utf-8") as f:
        m = re.search(r'\.version = "(\d+\.\d+\.\d+)"', f.read())
    if not m:
        die("no version found in build.zig.zon")
    return m.group(1)


def vkey(v):
    return tuple(int(x) for x in v.split("."))


def run(cmd, cwd):
    print(f"$ {' '.join(cmd)}   (in {os.path.relpath(cwd, ROOT)})", flush=True)
    if subprocess.run(cmd, cwd=cwd).returncode != 0:
        die(f"failed: {' '.join(cmd)} (in {cwd})")


def git(*args):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def archive_older(ver):
    """Move the zip of every other version to dist/archive/ and remove its folder."""
    for entry in sorted(os.listdir(DIST)) if os.path.isdir(DIST) else []:
        m = NAME.match(entry)
        if not m or m.group(1) == ver:
            continue
        path = os.path.join(DIST, entry)
        if m.group(2):
            os.makedirs(ARCHIVE, exist_ok=True)
            dst = os.path.join(ARCHIVE, entry)
            if os.path.exists(dst):
                os.remove(dst)
            shutil.move(path, dst)
            with open(os.path.join(ARCHIVE, "SHA256SUMS.txt"), "a", encoding="utf-8", newline="\n") as f:
                f.write(f"{sha256(dst)}  {entry}\n")
            print(f"archived: dist/archive/{entry}")
        else:
            shutil.rmtree(path)
            print(f"removed: dist/{entry}/ (older release)")


def ignore(folder, names):
    # a nested git repository (a submodule) is not part of the distribution
    return [n for n in names if n in SKIP_NAMES or n.endswith(".pack") or os.path.exists(os.path.join(folder, n, ".git"))]


def copy_folder(name, rel):
    dst = os.path.join(rel, name)
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(os.path.join(ROOT, name), dst, ignore=ignore)


def stage(ver, rel, folder):
    # lib/ with its docs (the build copies only the .eve files), tools/, and the manual of the repository
    for name in ["lib", "tools", "manual"]:
        copy_folder(name, rel)
    # the generated pages and the component docs, made again for this release, in the release folder only
    run([sys.executable, os.path.join(ROOT, "script", "genmanual.py"), "--out", os.path.join(rel, "manual")], ROOT)
    shutil.copyfile(os.path.join(ROOT, "comp", "LICENSE"), os.path.join(rel, "LICENSE"))
    shutil.copyfile(os.path.join(ROOT, "TRADEMARK.md"), os.path.join(rel, "TRADEMARK.md"))
    with open(os.path.join(ROOT, "design", "template", "dist-readme.md"), encoding="utf-8") as f:
        text = re.sub(r"\A(?:<!--.*?-->\n)+", "", f.read(), flags=re.S)
    for key, value in {"version": ver, "date": date.today().isoformat(), "commit": git("rev-parse", "--short", "HEAD") or "?",
                       "platform": PLATFORM[1], "zip": folder}.items():
        text = text.replace("{" + key + "}", value)
    with open(os.path.join(rel, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    # debug symbols are not part of the distribution
    for f in os.listdir(os.path.join(rel, "bin")):
        if f.endswith(".pdb"):
            os.remove(os.path.join(rel, "bin", f))


def check(ver, rel):
    for name in EXPECTED:
        if not os.path.isfile(os.path.join(rel, name)):
            die(f"missing in the release: {name} (run without --no-build, or build that part)")
    out = subprocess.run([os.path.join(rel, "bin", "eve.exe"), "-v"], capture_output=True, text=True)
    if out.returncode != 0 or ver not in out.stdout + out.stderr:
        die(f"eve -v does not show version {ver}: {out.stdout.strip()} {out.stderr.strip()}")
    print(f"eve -v: {(out.stdout or out.stderr).strip()}")


def zip_release(rel, folder):
    zip_path = os.path.join(DIST, folder + ".zip")
    if os.path.exists(zip_path):
        os.remove(zip_path)
    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for dirpath, dirnames, filenames in os.walk(rel):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_NAMES)
            for f in sorted(filenames):
                full = os.path.join(dirpath, f)
                z.write(full, folder + "/" + os.path.relpath(full, rel).replace(os.sep, "/"))
                count += 1
    digest = sha256(zip_path)
    with open(os.path.join(DIST, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"{digest}  {os.path.basename(zip_path)}\n")
    print(f"zip: dist/{os.path.basename(zip_path)} ({count} files, {os.path.getsize(zip_path) / (1 << 20):.1f} MB)")
    print(f"sha256: {digest}")


def write_index(ver, folder):
    older = sorted((NAME.match(f).group(1) for f in os.listdir(ARCHIVE) if NAME.match(f)), key=vkey, reverse=True) \
        if os.path.isdir(ARCHIVE) else []
    lines = ["# Eve distributions", "",
             "Generated by `script/dist.py` (`./run.sh dist`); this folder is not under version control.", "",
             "## Current release", "",
             f"Eve **{ver}** for {PLATFORM[1]}, made on {date.today().isoformat()}:", "",
             f"- `{folder}/`: the release, unzipped (start with its `README.md`)",
             f"- `{folder}.zip`: the same, to publish (`./run.sh release`)",
             "- `SHA256SUMS.txt`: the SHA-256 of the zip", "",
             "## Older releases", ""]
    lines += [f"- `archive/eve-{v}-{PLATFORM[0]}.zip`" for v in older] or ["None yet."]
    if older:
        lines += ["", "Their SHA-256 sums are in `archive/SHA256SUMS.txt`."]
    with open(os.path.join(DIST, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main(argv):
    if any(a != "--no-build" for a in argv):
        die("usage: python script/dist.py [--no-build]")
    ver = version()
    folder = f"eve-{ver}-{PLATFORM[0]}"
    rel = os.path.join(DIST, folder)
    print(f"distribution of Eve {ver}, {PLATFORM[1]}")
    os.makedirs(DIST, exist_ok=True)
    # what an older layout of dist/ left at its top (bin/, lib/, manual/, tools/ directly in dist/)
    for old in ["bin", "lib", "manual", "tools"]:
        shutil.rmtree(os.path.join(DIST, old), ignore_errors=True)
    archive_older(ver)
    if "--no-build" not in argv:
        shutil.rmtree(rel, ignore_errors=True)
        os.makedirs(rel)
        for part in PARTS:
            run(["zig", "build", "-Doptimize=ReleaseSafe", "-p", rel], part)
    elif not os.path.isdir(os.path.join(rel, "bin")):
        die(f"--no-build: no binaries in dist/{folder}/bin; run without --no-build first")
    stage(ver, rel, folder)
    check(ver, rel)
    zip_release(rel, folder)
    write_index(ver, folder)
    print(f"done: dist/{folder}/ and its zip; publish with ./run.sh release (script/publish.py)")


if __name__ == "__main__":
    main(sys.argv[1:])
