"""Size of the repository: tracked files, git history, ignored folders.

usage: python script/repsize.py
  tracked files  what a checkout holds (git ls-files, nested repositories not counted)
  history        what a clone downloads (the git object store: pack + loose objects)
  ignored        build output, caches and scratch folders that git does not track
Run `git gc` to compact the history; this script only reports.
"""
import os
import subprocess

from _common import die

NESTED = "160000"  # git mode of a gitlink (a nested repository)


def git(*args):
    res = subprocess.run(["git", *args], capture_output=True, check=False)
    if res.returncode != 0:
        die(f"git {' '.join(args)} failed: {res.stderr.decode(errors='replace').strip()}")
    return res.stdout.decode("utf-8", errors="replace")


def tree_bytes(path):
    """Bytes of a file or of every file under a folder (symlinks not followed)."""
    if os.path.isfile(path) and not os.path.islink(path):
        return os.path.getsize(path)
    total = 0
    for dirpath, _dirs, files in os.walk(path):
        for name in files:
            full = os.path.join(dirpath, name)
            if not os.path.islink(full):
                try:
                    total += os.path.getsize(full)
                except OSError:
                    pass  # a file that vanished while walking
    return total


def fmt(n):
    if n >= 1 << 20:
        return f"{n / (1 << 20):8.2f} MB"
    return f"{n / (1 << 10):8.1f} KB"


def tracked():
    """Sizes of the tracked files, and the nested repositories (gitlinks) apart."""
    total, nested, by_top = 0, [], {}
    for line in git("ls-files", "-s", "-z").split("\0"):
        if not line:
            continue
        meta, path = line.split("\t", 1)
        if meta.split()[0] == NESTED:
            nested.append(path)
            continue
        size = tree_bytes(path)
        total += size
        top = path.split("/", 1)[0] if "/" in path else "(root files)"
        by_top[top] = by_top.get(top, 0) + size
    return total, nested, by_top


def history():
    """Bytes of the git object store (packs and loose objects) and of the .git folder."""
    counts = {}
    for line in git("count-objects", "-v").splitlines():
        key, _, value = line.partition(": ")
        counts[key] = int(value) if value.isdigit() else value
    store = (counts.get("size-pack", 0) + counts.get("size", 0)) * 1024
    return store, tree_bytes(os.path.join(ROOT, ".git"))


def ignored():
    """Bytes of each ignored folder or file at the top of the repository."""
    sizes = {}
    for path in git("ls-files", "-o", "-i", "--exclude-standard", "--directory").splitlines():
        path = path.rstrip("/")
        if path:
            sizes[path] = tree_bytes(os.path.join(ROOT, path))
    return sizes


def main():
    t_total, nested, by_top = tracked()
    store, git_dir = history()
    ign = ignored()

    print(f"Repository {ROOT}")
    print()
    print(f"Tracked files        {fmt(t_total)}   {len(by_top)} top-level folders")
    for top, size in sorted(by_top.items(), key=lambda kv: -kv[1])[:10]:
        print(f"  {fmt(size)}  {top}")
    if nested:
        print(f"  not counted: nested repositories {', '.join(nested)}")
    print()
    print(f"History (git objects) {fmt(store)}   .git folder {fmt(git_dir)}")
    print("  a clone downloads about the history plus the tracked files")
    print()
    print(f"Ignored (not in git) {fmt(sum(ign.values()))}")
    for path, size in sorted(ign.items(), key=lambda kv: -kv[1])[:10]:
        print(f"  {fmt(size)}  {path}")


ROOT = os.path.normpath(git("rev-parse", "--show-toplevel").strip())

if __name__ == "__main__":
    main()
