"""Print the structure of Markdown / Eve files with line numbers.

Read the outline first, then open only the line range you need
(Read with offset/limit) instead of reading whole files.

usage: python script/outline.py PATH... [--depth N]
  Markdown: headings (fenced code ignored), up to --depth levels (default 6)
  HTML:     <h1>..<h6> headings with their #id anchors, up to --depth levels
  Eve:      top-level declarations (driver, class, routine, process, ...)
"""
import argparse
import re

from _common import read, rel, walk

MD_HEAD = re.compile(r"^(#{1,6})\s+(.*\S)")
HTML_HEAD = re.compile(r"<h([1-6])([^>]*)>(.*?)</h\1\s*>", re.I)
HTML_ID = re.compile(r"\bid\s*=\s*[\"']([^\"']+)")
TAGS = re.compile(r"<[^>]+>")
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


def outline_html(text, depth):
    for i, line in enumerate(text.split("\n"), 1):
        for m in HTML_HEAD.finditer(line):
            level = int(m.group(1))
            if level > depth:
                continue
            title = TAGS.sub("", m.group(3)).strip()
            anchor = HTML_ID.search(m.group(2))
            yield i, "  " * (level - 1) + title + (f"  #{anchor.group(1)}" if anchor else "")


def outline_eve(text):
    for i, line in enumerate(text.split("\n"), 1):
        if EVE_DECL.match(line):
            yield i, line.rstrip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--depth", type=int, default=6)
    a = ap.parse_args()
    for path in walk(a.paths, [".md", ".eve", ".html", ".htm"]):
        text, _ = read(path)
        if path.endswith(".md"):
            items = list(outline_md(text, a.depth))
        elif path.endswith((".html", ".htm")):
            items = list(outline_html(text, a.depth))
        else:
            items = list(outline_eve(text))
        total = text.count("\n") + (0 if text.endswith("\n") or not text else 1)
        print(f"{rel(path)} ({total}L)")
        for n, s in items:
            print(f"  {n:>5}: {s}")


if __name__ == "__main__":
    main()
