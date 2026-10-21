#!/usr/bin/env python3
"""evegen: the generator that joins the spec, the tests and the manual.

    python generator/evegen.py all [--check]            index + manual
    python generator/evegen.py manual [--out DIR] [--check]   the pages of the manual
    python generator/evegen.py index [--check]          spec/spec.json
    python generator/evegen.py check [-v]               the rules between spec, tests and manual
    python generator/evegen.py status [level]           features and tests in a few lines

The spec and the tests never name each other and the manual names neither: the links are the field `features`
of each test (test/<suite>/<suite>.json) and the feature files (spec/features/), and only this program reads
both. With --out the manual goes to DIR and the hand-written text is read from manual/ (a distribution never
changes the repository). --check writes nothing and exits 1 when something is out of date.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402
import check  # noqa: E402
import model  # noqa: E402
import specindex  # noqa: E402


def cmd_manual(args):
    out = args[args.index("--out") + 1] if "--out" in args else None
    stale = build.run(out=out, check="--check" in args)
    where = out or "manual"
    if "--check" in args:
        for s in stale:
            print("evegen: out of date: %s/%s" % (where, s))
        return 1 if stale else 0
    print("evegen: %s: %s" % (where, ", ".join(stale) if stale else "up to date"))
    return 0


def cmd_index(args):
    same = specindex.run(check="--check" in args)
    if "--check" in args:
        if not same:
            print("evegen: out of date: spec/spec.json")
        return 0 if same else 1
    print("evegen: spec/spec.json: %s" % ("up to date" if same else "written"))
    return 0


def cmd_status(args):
    levels = model.load_levels()
    suites = {s["suite"]: s for s in model.load_suites()}
    for lv in levels:
        if args and lv["id"] not in args and str(lv.get("level")) not in args:
            continue
        feats = lv["features"]
        done = sum(1 for f in feats if f["status"] == "done")
        t = suites.get(lv["id"], {"tests": []})["tests"]
        ok = sum(1 for x in t if x["status"] == "PASS")
        print("%-7s %2d/%2d features done, %3d/%3d tests pass  %s" % (lv["id"], done, len(feats), ok, len(t), lv["name"]))
        if args:
            for f in feats:
                print("  %-9s %-8s %s" % (f["id"], f["status"], f["name"]))
    for name in model.SPECIAL:
        if name in suites and not args:
            t = suites[name]["tests"]
            print("%-7s %3d/%3d tests pass" % (name, sum(1 for x in t if x["status"] == "PASS"), len(t)))
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, args = argv[0], argv[1:]
    if cmd == "manual":
        return cmd_manual(args)
    if cmd == "index":
        return cmd_index(args)
    if cmd == "check":
        return check.run(verbose="-v" in args)
    if cmd == "status":
        return cmd_status(args)
    if cmd == "all":
        return cmd_index(args) | cmd_manual(args)
    print("evegen: unknown command %r (python generator/evegen.py --help)" % cmd)
    return 2


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
