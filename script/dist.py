#!/usr/bin/env python3
"""Dist: build the distribution of the current version in dist/, zip it, and archive the older ones.

Usage: python script/dist.py [--no-build] [windows|linux ...]   (no platform: both)

dist/ is generated and git-ignored. Its layout:
  dist/README.md                     what the folder holds (written by this script)
  dist/eve-X.Y.Z-<platform>/         the current release of a platform (windows-x64, linux-x64), unpacked:
      README.md                      from design/template/dist-readme.md
      LICENSE, TRADEMARK.md
      bin/                           eve, evevm, evecp, evedb, evetx, eveux (.exe on Windows) and the DuckDB library (ReleaseSafe)
      lib/                           the Eve library with its docs (eve finds it at ../lib from bin/)
      manual/                        manual/ of the repository, with its generated pages and the component docs
                                     made again for this release (generator/evegen.py manual --out)
      tools/                         the editor plugins and the typing aids (no nested repositories)
  dist/eve-X.Y.Z-windows-x64.zip     the Windows folder zipped (unzip gives the folder)
  dist/eve-X.Y.Z-linux-x64.tar.gz    the Linux folder as a tar.gz, with the programs executable (cross-compiled from Windows)
  dist/SHA256SUMS.txt                the SHA-256 of the current archives (script/publish.py uploads them all)
  dist/archive/                      the archives of the older releases, and their SHA256SUMS.txt
When the version changes, the archives of the previous release move to dist/archive/ and its folder is removed;
a dist of the same version and platform replaces it. The repository is never changed.
Not in the distribution: design/, backlog/, test/, script/, spec/, code/eve/ and the source code.
`--no-build` keeps the binaries already in the release folder and stages, checks and packs again.
The Linux `eve -v` check runs in WSL when WSL is there, and is skipped with a note otherwise.
Step: `./run.sh dist`. Publishing: `./run.sh release` (script/publish.py).
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
ARCHIVE = os.path.join(DIST, "archive")
# per platform: the label of the archive, the name for people, the Zig target, the archive type,
# the suffix of the programs and the DuckDB library that ships beside evedb
PLATFORMS = {
    "windows": {"label": "windows-x64", "name": "Windows (x64)", "target": "x86_64-windows-gnu", "ext": ".zip", "exe": ".exe",
                "duckdb": "duckdb.dll"},
    "linux": {"label": "linux-x64", "name": "Linux (x64, glibc)", "target": "x86_64-linux-gnu", "ext": ".tar.gz", "exe": "",
              "duckdb": "libduckdb.so"},
}
PROGRAMS = ["eve", "evevm", "evecp", "evedb", "evetx", "eveux"]
# the folders with a build.zig: the root (eve, evevm, lib), then the parts that have their own
PARTS = [ROOT, os.path.join(ROOT, "drivers", "duckdb")] + [os.path.join(ROOT, "code", p) for p in ("evecp", "evetx", "eveux")]
EXPECTED = ["lib/config.eve", "manual/README.md", "manual/features.md", "manual/evevm/README.md", "README.md", "LICENSE"]
SKIP_NAMES = {".git", ".gitignore", "__pycache__", "node_modules", ".zig-cache", "zig-out"}
NAME = re.compile(r"eve-(\d+\.\d+\.\d+)-(windows-x64|linux-x64)(\.zip|\.tar\.gz)?$")
# the Install section of the README of the distribution ({install} of design/template/dist-readme.md)
INSTALL = {
    "windows": """1. Unzip the package in a folder of your choice, for example `C:\\eve`. The folder `{folder}` holds everything; nothing is written elsewhere.
2. Add its `bin` folder to the `PATH` (for example `C:\\eve\\{folder}\\bin`).
3. Open a new terminal and check: `eve -v` prints `EVE - Version: {version}`.

To uninstall, remove the folder and its line of the `PATH`.""",
    "linux": """1. Unpack the package in a folder of your choice, for example `mkdir -p ~/eve && tar -xzf {folder}.tar.gz -C ~/eve`. The folder `{folder}` holds everything; nothing is written elsewhere.
2. Add its `bin` folder to the `PATH` (for example `export PATH="$HOME/eve/{folder}/bin:$PATH"` in `~/.bashrc`). `evedb` finds `libduckdb.so` beside it.
3. Open a new terminal and check: `eve -v` prints `EVE - Version: {version}`.

To uninstall, remove the folder and its line of `~/.bashrc`. The programs are built for x64 with glibc (any current distribution; not Alpine).""",
}


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
        if m.group(3):
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


def stage(ver, rel, folder, plat):
    # lib/ with its docs (the build copies only the .eve files), tools/, and the manual of the repository
    for name in ["lib", "tools", "manual"]:
        copy_folder(name, rel)
    # the generated pages and the component docs, made again for this release, in the release folder only
    run([sys.executable, os.path.join(ROOT, "generator", "evegen.py"), "manual", "--out", os.path.join(rel, "manual")], ROOT)
    shutil.copyfile(os.path.join(ROOT, "code", "LICENSE"), os.path.join(rel, "LICENSE"))
    shutil.copyfile(os.path.join(ROOT, "TRADEMARK.md"), os.path.join(rel, "TRADEMARK.md"))
    with open(os.path.join(ROOT, "design", "template", "dist-readme.md"), encoding="utf-8") as f:
        text = re.sub(r"\A(?:<!--.*?-->\n)+", "", f.read(), flags=re.S)
    text = text.replace("{install}", INSTALL[plat])
    info = PLATFORMS[plat]
    for key, value in {"version": ver, "date": date.today().isoformat(), "commit": git("rev-parse", "--short", "HEAD") or "?",
                       "platform": info["name"], "folder": folder, "exe": info["exe"], "duckdb": info["duckdb"]}.items():
        text = text.replace("{" + key + "}", value)
    with open(os.path.join(rel, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    # debug symbols are not part of the distribution
    for f in os.listdir(os.path.join(rel, "bin")):
        if f.endswith(".pdb"):
            os.remove(os.path.join(rel, "bin", f))


def wsl_path(path):
    drive, rest = os.path.splitdrive(os.path.abspath(path))
    return "/mnt/" + drive[0].lower() + rest.replace("\\", "/")


def check(ver, rel, plat):
    info = PLATFORMS[plat]
    for name in EXPECTED + [f"bin/{p}{info['exe']}" for p in PROGRAMS] + [f"bin/{info['duckdb']}"]:
        if not os.path.isfile(os.path.join(rel, name)):
            die(f"missing in the release: {name} (run without --no-build, or build that part)")
    if plat == "windows":
        cmd = [os.path.join(rel, "bin", "eve.exe"), "-v"]
    elif shutil.which("wsl.exe") or shutil.which("wsl"):
        cmd = ["wsl.exe", "--", "sh", "-c", f"chmod +x '{wsl_path(os.path.join(rel, 'bin'))}'/* && '{wsl_path(os.path.join(rel, 'bin', 'eve'))}' -v"]
    else:
        print("eve -v: skipped (no WSL to run the Linux build)")
        return
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0 or ver not in out.stdout + out.stderr:
        die(f"eve -v does not show version {ver}: {out.stdout.strip()} {out.stderr.strip()}")
    print(f"eve -v: {(out.stdout or out.stderr).strip()}")


def release_files(rel):
    for dirpath, dirnames, filenames in os.walk(rel):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_NAMES)
        for f in sorted(filenames):
            full = os.path.join(dirpath, f)
            yield full, os.path.relpath(full, rel).replace(os.sep, "/")


def tar_modes(info):
    # files written on Windows carry no Unix modes: the programs of bin/ (no extension) get 755, the rest 644
    name = info.name.split("/", 1)[-1]
    executable = name.startswith("bin/") and "." not in os.path.basename(name)
    info.mode = 0o755 if info.isdir() or executable else 0o644
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    return info


def pack_release(rel, folder, plat):
    path = os.path.join(DIST, folder + PLATFORMS[plat]["ext"])
    if os.path.exists(path):
        os.remove(path)
    count = 0
    if plat == "windows":
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for full, name in release_files(rel):
                z.write(full, folder + "/" + name)
                count += 1
    else:
        with tarfile.open(path, "w:gz", compresslevel=9) as t:
            for full, name in release_files(rel):
                t.add(full, folder + "/" + name, filter=tar_modes)
                count += 1
    print(f"archive: dist/{os.path.basename(path)} ({count} files, {os.path.getsize(path) / (1 << 20):.1f} MB)")


def current_archives(ver):
    return sorted(f for f in os.listdir(DIST) if (m := NAME.match(f)) and m.group(1) == ver and m.group(3))


def write_sums(ver):
    with open(os.path.join(DIST, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
        for name in current_archives(ver):
            digest = sha256(os.path.join(DIST, name))
            f.write(f"{digest}  {name}\n")
            print(f"sha256: {digest}  {name}")


def write_index(ver):
    older = sorted({f for f in os.listdir(ARCHIVE) if NAME.match(f)}, key=lambda f: vkey(NAME.match(f).group(1)), reverse=True) \
        if os.path.isdir(ARCHIVE) else []
    lines = ["# Eve distributions", "",
             "Generated by `script/dist.py` (`./run.sh dist`); this folder is not under version control.", "",
             "## Current release", "",
             f"Eve **{ver}**, made on {date.today().isoformat()}; each archive has its unpacked folder beside it "
             "(start with its `README.md`):", ""]
    lines += [f"- `{name}`" for name in current_archives(ver)]
    lines += ["- `SHA256SUMS.txt`: the SHA-256 of the archives (`./run.sh release` publishes them)", "",
              "## Older releases", ""]
    lines += [f"- `archive/{name}`" for name in older] or ["None yet."]
    if older:
        lines += ["", "Their SHA-256 sums are in `archive/SHA256SUMS.txt`."]
    with open(os.path.join(DIST, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main(argv):
    plats = [a for a in argv if a != "--no-build"] or list(PLATFORMS)
    if any(p not in PLATFORMS for p in plats):
        die("usage: python script/dist.py [--no-build] [windows|linux ...]")
    ver = version()
    os.makedirs(DIST, exist_ok=True)
    # what an older layout of dist/ left at its top (bin/, lib/, manual/, tools/ directly in dist/)
    for old in ["bin", "lib", "manual", "tools"]:
        shutil.rmtree(os.path.join(DIST, old), ignore_errors=True)
    archive_older(ver)
    for plat in plats:
        info = PLATFORMS[plat]
        folder = f"eve-{ver}-{info['label']}"
        rel = os.path.join(DIST, folder)
        print(f"distribution of Eve {ver}, {info['name']}")
        if "--no-build" not in argv:
            shutil.rmtree(rel, ignore_errors=True)
            os.makedirs(rel)
            for part in PARTS:
                run(["zig", "build", "-Doptimize=ReleaseSafe", f"-Dtarget={info['target']}", "-p", rel], part)
        elif not os.path.isdir(os.path.join(rel, "bin")):
            die(f"--no-build: no binaries in dist/{folder}/bin; run without --no-build first")
        stage(ver, rel, folder, plat)
        check(ver, rel, plat)
        pack_release(rel, folder, plat)
    write_sums(ver)
    write_index(ver)
    print("done: the folders and archives of dist/; publish with ./run.sh release (script/publish.py)")


if __name__ == "__main__":
    main(sys.argv[1:])
