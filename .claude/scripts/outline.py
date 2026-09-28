"""Print the structure of Markdown / Eve files with line numbers.

Read the outline first, then open only the line range you need
(Read with offset/limit) instead of reading whole files.

usage: python .claude/scripts/outline.py PATH... [--depth N]
  Markdown: headings (fenced code ignored), up to --depth levels (default 6)
  Eve:      top-level declarations (driver, class, routine, process, ...)
"""
import argparse
import re

from _common import read, rel, walk

MD_HEAD = re.compile(r"^(#{1,6})\s+(.*\S)")
FENCE = re.compile(r"^\s*(```|~~~)")
EVE_DECL = re.compile(
    r"^(driver|module|import|class|create|function|routine|process|"
    r"global|globals|type|recover|try)\b.*"
)


def outline_md(text, depth):
    in_fence = False
    for i, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        m = None if in_fence else MD_HEAD.match(line)
        if m and len(m.group(1)) <= depth:
            yield i, "  " * (len(m.group(1)) - 1) + m.group(2)


def outline_eve(text):
    for i, line in enumerate(text.split("\n"), 1):
        if EVE_DECL.match(line):
            yield i, line.rstrip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--depth", type=int, default=6)
    a = ap.parse_args()
    for path in walk(a.paths, [".md", ".eve"]):
        text, _ = read(path)
        items = list(outline_md(text, a.depth) if path.endswith(".md") else outline_eve(text))
        total = text.count("\n") + (0 if text.endswith("\n") or not text else 1)
        print(f"{rel(path)} ({total}L)")
        for n, s in items:
            print(f"  {n:>5}: {s}")


if __name__ == "__main__":
    main()
