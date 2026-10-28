#!/usr/bin/env python3
"""A/B timing of two builds of eve on the benchmarks (design/reference_counting.md, design-bytecode-opt.md):

  python script/abtest.py BASE.exe NEW.exe [--runs N] [--engine bc|tree] [name ...]

Runs the programs alternately (base, new, base, new...) so a loaded machine hits both alike, and prints the minimum and the median of
each and the change. On Windows the measure is the CPU cycles of the process (QueryProcessCycleTime, in millions), which a loaded
machine does not disturb as it does the wall time; elsewhere it is the wall time in ms. A name ending in .eve and existing is run as a file. Without names: every test/bmark/p[1-5]*.eve and test/bmark/mem/*.eve.
"""
import argparse, glob, os, statistics, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def once(exe, path, eng):
    env = dict(os.environ, EVE_ENGINE=eng)
    s = time.perf_counter()
    p = subprocess.Popen([exe, "-x", os.path.basename(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=os.path.dirname(path), env=env)
    p.wait()
    if os.name == "nt":
        import ctypes
        c = ctypes.c_ulonglong(0)
        if ctypes.windll.kernel32.QueryProcessCycleTime(int(p._handle), ctypes.byref(c)):
            return c.value / 1e6
    return (time.perf_counter() - s) * 1000


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("base")
    ap.add_argument("new")
    ap.add_argument("names", nargs="*")
    ap.add_argument("--runs", type=int, default=9)
    ap.add_argument("--engine", default="bc")
    a = ap.parse_args()
    base, new = os.path.abspath(a.base), os.path.abspath(a.new)
    files = sorted(glob.glob(os.path.join(ROOT, "test", "bmark", "p[1-5]*.eve"))) + sorted(glob.glob(os.path.join(ROOT, "test", "bmark", "mem", "*.eve")))
    if a.names:
        explicit = [os.path.abspath(n) for n in a.names if n.endswith(".eve") and os.path.exists(n)]
        files = explicit or [f for f in files if any(n in os.path.basename(f) for n in a.names)]
    print(f"{'program':22} {'base min':>9} {'new min':>9} {'change':>8}   {'base med':>9} {'new med':>9} {'change':>8}")
    for f in files:
        tb, tn = [], []
        for _ in range(a.runs):
            tb.append(once(base, f, a.engine))
            tn.append(once(new, f, a.engine))
        mb, mn = min(tb), min(tn)
        db, dn = statistics.median(tb), statistics.median(tn)
        print(f"{os.path.basename(f)[:-4]:22} {mb:9.1f} {mn:9.1f} {100 * (mn - mb) / mb:+7.1f}%   {db:9.1f} {dn:9.1f} {100 * (dn - db) / db:+7.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
