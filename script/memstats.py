#!/usr/bin/env python3
"""The memory statistics of the benchmarks (design/reference_counting.md):

  python script/memstats.py [--eve PATH] [--json FILE] [--table] [--ops]

Runs every test/bmark/p[1-5]*.eve and test/bmark/mem/*.eve on both engines with EVE_MEMSTATS=1 and reads the line the heap prints
(objects made by kind, freed by count and by trace, traces, peak, safe points, zero counts, objects swept by traces).
--ops needs an `eve` built with `count_ops = true` in code/evecm/src/heap.zig (retains and releases are then counted too).
--json writes the rows; --table prints the Markdown tables used by design/reference_counting.md.
"""
import argparse, glob, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_one(eve, path, eng):
    env = dict(os.environ, EVE_MEMSTATS="1", EVE_ENGINE=eng)
    try:
        r = subprocess.run([eve, "-x", os.path.basename(path)], capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=os.path.dirname(path), env=env, timeout=120)
    except subprocess.TimeoutExpired:
        return None
    t = r.stderr
    m = re.search(r"heap: (\d+) objects made, (\d+) freed by count, (\d+) freed by trace \((\d+) traces\), (\d+) live; peak (\d+) objects, (\d+) KB", t)
    if not m:
        return None
    k = re.search(r"heap kinds: (.*)", t)
    w = re.search(r"heap work: (\d+) safe points, (\d+) zero counts pushed, (\d+) table entries scanned, (\d+) objects swept by traces(?:, (\d+) retains, (\d+) releases)?", t)
    kinds = {a: int(b) for a, b in re.findall(r"(\w+) (\d+)", k.group(1))} if k else {}
    return dict(name=os.path.basename(path)[:-4], eng=eng, made=int(m[1]), rc=int(m[2]), gc=int(m[3]), traces=int(m[4]), peak=int(m[6]), kb=int(m[7]),
                kinds=kinds, safe=int(w[1]) if w else 0, zct=int(w[2]) if w else 0, swept=int(w[4]) if w else 0,
                retains=int(w[5] or 0) if w else 0, releases=int(w[6] or 0) if w else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--eve", default=os.path.join(ROOT, "temp", "rel", "bin", "eve.exe"))
    ap.add_argument("--json")
    ap.add_argument("--table", action="store_true")
    a = ap.parse_args()
    eve = os.path.abspath(a.eve)
    files = sorted(glob.glob(os.path.join(ROOT, "test", "bmark", "p[1-5]*.eve"))) + sorted(glob.glob(os.path.join(ROOT, "test", "bmark", "mem", "*.eve")))
    rows = [r for f in files for e in ("bc", "tree") if (r := run_one(eve, f, e))]
    if a.json:
        json.dump(rows, open(a.json, "w"), indent=1)
    if a.table:
        by = {(r["name"], r["eng"]): r for r in rows}
        print("| Program | made (bc) | scopes + variables | functions | freed by count | freed by trace | traces | peak KB | made (tree) |")
        print("|---|---|---|---|---|---|---|---|---|")
        for n in dict.fromkeys(r["name"] for r in rows):
            b, t = by.get((n, "bc")), by.get((n, "tree"))
            if not b: continue
            k = b["kinds"]; sv = k.get("scope", 0) + k.get("variable", 0)
            print(f"| {n} | {b['made']:,} | {sv:,} | {k.get('func', 0):,} | {b['rc']:,} | {b['gc']:,} | {b['traces']} | {b['kb']:,} | {t['made']:,} |" if t else f"| {n} | {b['made']:,} | {sv:,} | {k.get('func', 0):,} | {b['rc']:,} | {b['gc']:,} | {b['traces']} | {b['kb']:,} | |")
    else:
        for r in rows:
            print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
