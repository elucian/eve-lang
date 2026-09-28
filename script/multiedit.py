"""Apply many exact-text edits across many files in ONE call, all-or-nothing.

Replaces a series of Read+Edit round-trips. Every edit is validated first;
if any OLD block is missing or ambiguous, no file is written.
Preserves CRLF/LF and the final newline of each file.

usage: python script/multiedit.py [SPEC] [--dry-run] <<'EOF'
  (spec from SPEC file, or stdin when omitted)

Spec format (markers must start at column 0):
  @@@ FILE docs/index.md
  @@@ OLD
  exact text to find (must occur exactly once)
  @@@ NEW
  replacement text (may be empty = delete the text)
  @@@ OLD all
  text replaced at EVERY occurrence (at least one required)
  @@@ NEW
  replacement
  @@@ FILE demo/hello_world.eve
  ...
Edits within a file apply in order, each seeing the result of the previous one.
"""
import argparse
import sys

from _common import die, read, read_stdin, rel, write


def parse(spec):
    edits = {}  # file -> [(old, new, all)]
    order = []
    cur_file = None
    mode = None  # "old" | "new"
    buf = []
    pending = None  # (old, all)

    def flush():
        nonlocal buf, pending
        text = "\n".join(buf)
        if mode == "old":
            pending = (text, pending_all)
        elif mode == "new":
            if pending is None:
                die("NEW block without preceding OLD")
            edits[cur_file].append((pending[0], text, pending[1]))
            pending = None
        buf = []

    pending_all = False
    for n, line in enumerate(spec.split("\n"), 1):
        if line.startswith("@@@ "):
            parts = line[4:].strip().split(None, 1)
            kw = parts[0].upper() if parts else ""
            if kw in ("FILE", "OLD", "NEW", "END"):
                flush()
                if kw == "FILE":
                    if pending is not None:
                        die(f"line {n}: OLD without NEW")
                    cur_file = parts[1].strip() if len(parts) > 1 else die(f"line {n}: FILE needs a path")
                    if cur_file not in edits:
                        edits[cur_file] = []
                        order.append(cur_file)
                    mode = None
                elif kw == "OLD":
                    if cur_file is None:
                        die(f"line {n}: OLD before any FILE")
                    if pending is not None:
                        die(f"line {n}: OLD without NEW")
                    pending_all = len(parts) > 1 and parts[1].strip().lower() == "all"
                    mode = "old"
                elif kw == "NEW":
                    mode = "new"
                else:
                    mode = None
                continue
        if mode:
            buf.append(line)
    # A trailing newline at the end of the spec is not part of the last block.
    if mode and buf and buf[-1] == "":
        buf.pop()
    flush()
    if pending is not None:
        die("final OLD block has no NEW")
    return order, edits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec", nargs="?")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    spec = open(a.spec, encoding="utf-8").read().replace("\r\n", "\n") if a.spec else read_stdin()
    order, edits = parse(spec)
    if not order:
        die("spec contains no @@@ FILE blocks")

    results, errors = {}, []
    for path in order:
        try:
            text, eol = read(path)
        except OSError as e:
            errors.append(f"{path}: {e}")
            continue
        for i, (old, new, every) in enumerate(edits[path], 1):
            if not old:
                errors.append(f"{path} edit {i}: empty OLD")
                continue
            count = text.count(old)
            head = old.split("\n")[0][:60]
            if count == 0:
                errors.append(f"{path} edit {i}: OLD not found: {head!r}")
            elif count > 1 and not every:
                errors.append(f"{path} edit {i}: OLD occurs {count}x (add context or use 'OLD all'): {head!r}")
            else:
                text = text.replace(old, new)
                edits[path][i - 1] = (old, new, count)
        results[path] = (text, eol)

    if errors:
        print("multiedit: nothing written, " + str(len(errors)) + " problem(s):", file=sys.stderr)
        for e in errors:
            print("  ! " + e, file=sys.stderr)
        sys.exit(1)

    total = 0
    for path in order:
        text, eol = results[path]
        counts = [c for _, _, c in edits[path]]
        total += sum(counts)
        print(f"  {rel(path)}: {len(counts)} edit(s), {sum(counts)} replacement(s)")
        if not a.dry_run:
            write(path, text, eol)
    verb = "would apply" if a.dry_run else "applied"
    print(f"multiedit: {verb} {total} replacement(s) in {len(order)} file(s)")


if __name__ == "__main__":
    main()
