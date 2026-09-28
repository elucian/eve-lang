"""Check and refactor relative links between Markdown files.

usage:
  python .claude/scripts/mdlinks.py check [PATH...]
      Report broken relative links and #anchors (external URLs are skipped).
  python .claude/scripts/mdlinks.py rename OLD NEW [--git-mv] [--dry-run]
      Move a file and rewrite every Markdown link that points to it, plus the
      relative links inside the moved file itself.
"""
import argparse
import os
import re
import subprocess
import sys

from _common import die, read, rel, walk, write

# [text](target "title")  |  <a href="target">  |  <img src="target">
LINK = re.compile(r"(\]\()([^)\s]+)((?:\s+\"[^\"]*\")?\))|((?:href|src)=\")([^\"]+)(\")")
MD_HEAD = re.compile(r"^#{1,6}\s+(.*\S)")
FENCE = re.compile(r"^\s*(```|~~~)")
EXTERNAL = re.compile(r"^([a-z][a-z0-9+.-]*:|//)", re.I)


def unfenced(text):
    """Yield (lineno, line) for lines outside fenced code blocks."""
    in_fence = False
    for i, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence:
            yield i, line


def slugs(text):
    """GitHub-style heading anchors."""
    seen, out = {}, set()
    for _, line in unfenced(text):
        m = MD_HEAD.match(line)
        if not m:
            continue
        s = re.sub(r"[^\w\- ]", "", m.group(1).strip().lower()).replace(" ", "-")
        k = seen.get(s, 0)
        seen[s] = k + 1
        out.add(s if k == 0 else f"{s}-{k}")
    return out


def links(text):
    """Yield (lineno, target) for relative links."""
    for n, line in unfenced(text):
        for m in LINK.finditer(line):
            target = m.group(2) or m.group(5)
            if target and not EXTERNAL.match(target):
                yield n, target


def cmd_check(paths):
    cache, bad, count = {}, 0, 0
    for path in walk(paths, [".md"]):
        text, _ = read(path)
        base = os.path.dirname(path)
        for n, target in links(text):
            count += 1
            file_part, _, anchor = target.partition("#")
            dest = os.path.normpath(os.path.join(base, file_part)) if file_part else path
            problem = None
            if not os.path.exists(dest):
                problem = "missing file"
            elif anchor and dest.endswith(".md"):
                if dest not in cache:
                    cache[dest] = slugs(read(dest)[0])
                if anchor.lower() not in cache[dest]:
                    problem = "missing anchor"
            if problem:
                bad += 1
                print(f"{rel(path)}:{n}: {problem}: {target}")
    print(f"-- {count} relative link(s) checked, {bad} broken")
    sys.exit(1 if bad else 0)


def retarget(text, fix):
    """Rewrite link targets with fix(target) -> new target or None."""
    changed = 0

    def sub(m):
        nonlocal changed
        pre, target, post = (m.group(1), m.group(2), m.group(3)) if m.group(2) else (m.group(4), m.group(5), m.group(6))
        new = None if EXTERNAL.match(target) else fix(target)
        if new is None or new == target:
            return m.group(0)
        changed += 1
        return pre + new + post

    out = []
    in_fence = False
    for line in text.split("\n"):
        if FENCE.match(line):
            in_fence = not in_fence
        out.append(line if in_fence else LINK.sub(sub, line))
    return "\n".join(out), changed


def relink(from_dir, dest):
    return os.path.relpath(dest, from_dir or ".").replace("\\", "/")


def cmd_rename(old, new, git_mv, dry):
    old, new = os.path.normpath(old), os.path.normpath(new)
    if not os.path.isfile(old):
        die(f"{old} is not a file")
    if os.path.exists(new):
        die(f"{new} already exists")
    total = 0
    for path in walk(["."], [".md"]):
        path = os.path.normpath(path)
        text, eol = read(path)
        is_moved = path == old
        src_dir = os.path.dirname(path)
        out_dir = os.path.dirname(new) if is_moved else src_dir

        def fix(target):
            file_part, sep, anchor = target.partition("#")
            if not file_part:
                return None
            dest = os.path.normpath(os.path.join(src_dir, file_part))
            if dest == old:
                dest = new
            elif not is_moved:
                return None
            return relink(out_dir, dest) + sep + anchor

        body, n = retarget(text, fix)
        if n:
            total += n
            print(f"  {rel(path)}: {n} link(s) updated")
            if not dry:
                write(path, body, eol)
    if not dry:
        os.makedirs(os.path.dirname(new) or ".", exist_ok=True)
        if git_mv:
            subprocess.run(["git", "mv", old, new], check=True)
        else:
            os.rename(old, new)
    verb = "would move" if dry else "moved"
    print(f"mdlinks: {verb} {rel(old)} -> {new.replace(os.sep, '/')}, {total} link(s) rewritten")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("paths", nargs="*")
    r = sub.add_parser("rename")
    r.add_argument("old")
    r.add_argument("new")
    r.add_argument("--git-mv", action="store_true")
    r.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.cmd == "check":
        cmd_check(a.paths)
    else:
        cmd_rename(a.old, a.new, a.git_mv, a.dry_run)


if __name__ == "__main__":
    main()
