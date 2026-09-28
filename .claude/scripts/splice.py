"""Line-range editing: replace / insert / delete lines by number.

Saves tokens when rewriting a block: you send only the NEW text, never the
old text. Preserves CRLF/LF and the final newline (unlike `bee-ed apply`).

usage:
  python .claude/scripts/splice.py FILE replace A B [--expect TXT] [--from PATH] <<'EOF'
  python .claude/scripts/splice.py FILE insert N    [--expect TXT] [--from PATH] <<'EOF'
  python .claude/scripts/splice.py FILE delete A B  [--expect TXT]

  Lines are 1-based and inclusive. `insert N` inserts AFTER line N (0 = top).
  New text comes from stdin (heredoc) or --from PATH.
  --expect TXT  abort unless line A (or N) contains TXT - guards stale line numbers.
  --dry-run     show the resulting region without writing.
Prints the edited region with 2 lines of context so no re-read is needed.
"""
import argparse

from _common import die, read, read_stdin, rel, write

CONTEXT = 2
MAX_SHOW = 40


def new_lines(a):
    text = open(a.src, encoding="utf-8").read().replace("\r\n", "\n") if a.src else read_stdin()
    if text.endswith("\n"):
        text = text[:-1]
    return text.split("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("op", choices=["replace", "insert", "delete"])
    ap.add_argument("start", type=int)
    ap.add_argument("end", type=int, nargs="?")
    ap.add_argument("--expect")
    ap.add_argument("--from", dest="src")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    text, eol = read(a.file)
    final_nl = text.endswith("\n")
    lines = text[:-1].split("\n") if final_nl else text.split("\n")
    total = len(lines)

    if a.op == "insert":
        if a.end is not None:
            die("insert takes a single line number N")
        if not 0 <= a.start <= total:
            die(f"insert position {a.start} outside 0..{total}")
        lo, hi = a.start, a.start  # slice [lo:hi] is empty -> pure insertion
        guard = a.start
    else:
        if a.end is None:
            die(f"{a.op} needs A B")
        if not 1 <= a.start <= a.end <= total:
            die(f"range {a.start}-{a.end} outside 1..{total}")
        lo, hi = a.start - 1, a.end
        guard = a.start

    if a.expect is not None:
        if guard < 1 or a.expect not in lines[guard - 1]:
            got = lines[guard - 1] if guard >= 1 else "<top of file>"
            die(f"--expect failed at line {guard}: {got!r}")

    repl = [] if a.op == "delete" else new_lines(a)
    out = lines[:lo] + repl + lines[hi:]
    body = "\n".join(out) + ("\n" if final_nl else "")

    removed = hi - lo
    print(f"splice {rel(a.file)}: {a.op} -{removed} +{len(repl)} lines ({total} -> {len(out)})"
          + (" [dry-run]" if a.dry_run else ""))
    first = max(0, lo - CONTEXT)
    last = min(len(out), lo + len(repl) + CONTEXT)
    shown = out[first:last]
    if len(shown) > MAX_SHOW:
        shown = shown[:MAX_SHOW // 2] + ["..."] + shown[-MAX_SHOW // 2:]
        print("\n".join(shown))
    else:
        for i, line in enumerate(shown, first + 1):
            print(f"{i:>5}: {line}")
    if not a.dry_run:
        write(a.file, body, eol)


if __name__ == "__main__":
    main()
