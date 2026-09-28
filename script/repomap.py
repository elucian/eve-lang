"""Compact project inventory: one line per text file (lines, EOL, title).

Use this instead of listing + opening files to learn what exists.

usage: python script/repomap.py [PATH...] [--ext .eve,.md] [--dirs]
  --dirs   only print per-directory file/line totals
"""
import argparse
import os
import re
from collections import defaultdict

from _common import is_binary, read, rel, walk

MD_HEAD = re.compile(r"^#{1,6}\s+(.*\S)")
EVE_DRIVER = re.compile(r"^(driver|module)\s+([\w.]+)")
HTML_TITLE = re.compile(r"<title>(.*?)</title>", re.I | re.S)


def title_of(path, text):
    if path.endswith(".md"):
        for line in text.split("\n"):
            m = MD_HEAD.match(line)
            if m:
                return m.group(1)
    elif path.endswith((".html", ".htm")):
        m = HTML_TITLE.search(text)
        if m:
            return m.group(1).strip()
    elif path.endswith(".eve"):
        for line in text.split("\n"):
            m = EVE_DRIVER.match(line)
            if m:
                return f"{m.group(1)} {m.group(2)}"
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--ext", help="comma-separated extensions, e.g. .eve,.md")
    ap.add_argument("--dirs", action="store_true")
    a = ap.parse_args()
    exts = [e.strip().lower() for e in a.ext.split(",")] if a.ext else None

    per_dir = defaultdict(lambda: [0, 0])
    rows = []
    for path in walk(a.paths, exts):
        if is_binary(path):
            continue
        text, eol = read(path)
        n = text.count("\n") + (0 if text.endswith("\n") or not text else 1)
        r = rel(path)
        d = per_dir[os.path.dirname(r) or "."]
        d[0] += 1
        d[1] += n
        rows.append((r, n, "crlf" if eol == "\r\n" else "lf", title_of(path, text)))

    if a.dirs:
        for d in sorted(per_dir):
            print(f"{d}/  files={per_dir[d][0]} lines={per_dir[d][1]}")
    else:
        for r, n, eol, t in rows:
            print(f"{r}  {n}L {eol}" + (f"  | {t}" if t else ""))
    print(f"-- {len(rows)} files, {sum(r[1] for r in rows)} lines")


if __name__ == "__main__":
    main()
