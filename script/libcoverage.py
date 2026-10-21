#!/usr/bin/env python3
"""Which public members of the libraries have a test (design/design-libraries.md section 0.4, rule 1).

Usage: python script/libcoverage.py [--missing] [module...]

A member is a function or procedure exported by a module of lib/sys/ (written in Zig) or lib/ (written in Eve).
It is covered when a test source in test/ calls it as `module.name(` (with or without the `!`). The report lists, for
each module, the members and the number of test files that call them. `--missing` prints only the members with no test.
Exit code 0; the report is information, the gate is the page of the library (a function is on a page only when tested).
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXPORT = re.compile(r"export\s*\(([^)]*)\)", re.S)
DECL = re.compile(r"^\s*(?:external\s+)?(?:async\s+)?(?:function|procedure)\s+([A-Za-z_][A-Za-z_0-9]*!?)", re.M)


def members(path):
    text = path.read_text(encoding="utf-8")
    exported = EXPORT.search(text)
    names = [n.strip().lstrip(".") for n in exported.group(1).split(",")] if exported else []
    declared = DECL.findall(text)
    return [n for n in names if n in declared] if names else declared


def main():
    only_missing = "--missing" in sys.argv
    wanted = [a for a in sys.argv[1:] if not a.startswith("--")]
    sources = []
    for p in (ROOT / "test").rglob("*.eve"):
        sources.append(p.read_text(encoding="utf-8", errors="replace"))
    modules = sorted(list((ROOT / "lib" / "sys").glob("*.eve")) + list((ROOT / "lib").glob("*.eve")))
    total = covered = 0
    for path in modules:
        mod = path.stem
        if wanted and mod not in wanted:
            continue
        kind = "zig" if path.parent.name == "sys" else "eve"
        rows = []
        for name in members(path):
            call = re.compile(r"\b%s\.%s\s*[(\[]" % (re.escape(mod), re.escape(name)))
            count = sum(1 for s in sources if call.search(s))
            rows.append((name, count))
        if not rows:
            continue
        total += len(rows)
        covered += sum(1 for _, c in rows if c)
        shown = [r for r in rows if not (only_missing and r[1])]
        if not shown:
            continue
        print("%s (%s): %d of %d members have a test" % (mod, kind, sum(1 for _, c in rows if c), len(rows)))
        for name, count in shown:
            print("    %-24s %s" % (name, "%d test file(s)" % count if count else "NO TEST"))
    print("members with a test: %d of %d" % (covered, total))


if __name__ == "__main__":
    main()
