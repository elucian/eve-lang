"""The census of the bridge of the bytecode machine (design/design-bytecode.md §16.1):

  python script/bccensus.py [--eve PATH] [--files] [dir ...]

For every program of test/level1 to test/level7 and test/bmark (or the folders given), `eve --disasm` tells what the
emitter translates. The report counts:

- the programs that run entirely on the bytecode machine, those with pieces on the tree walker, and those the emitter
  refuses (the whole program runs on the tree walker), with the reason of each refusal;
- the bridged pieces (`evalx`, `execx`) by the kind of node: this number should only go down (TD-46);
- the `call` instructions by kind (`value`, `method`, `builtin`): calls whose arguments the machine computes; a
  `method` or `builtin` call still runs the native or the routine of the tree walker (the adapter, §16.3).

--files writes one line per program to temp/bccensus.txt (state, count, path).
--routines also runs each program on the bytecode machine with EVE_BC_TRACE=1 and counts the routines compiled at their first
call (design-bytecode.md §16.2: modules, `lib/`, routines the tree walker calls) and those refused, by reason.
"""
import argparse
import collections
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["test/level1", "test/level2", "test/level3", "test/level4", "test/level5", "test/level6", "test/level7", "test/bmark"]


def programs(dirs):
    for d in dirs:
        for f in sorted(glob.glob(os.path.join(ROOT, d, "*.eve")) + glob.glob(os.path.join(ROOT, d, "*", "*.eve"))):
            # a test in its own folder is the file named like the folder
            parent = os.path.basename(os.path.dirname(f))
            if os.path.dirname(os.path.dirname(f)) != os.path.join(ROOT, d) or parent == os.path.splitext(os.path.basename(f))[0]:
                yield f


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--eve", default=os.path.join(ROOT, "bin", "eve.exe"))
    ap.add_argument("--files", action="store_true")
    ap.add_argument("--routines", action="store_true")
    ap.add_argument("dirs", nargs="*")
    args = ap.parse_args()
    eve = os.path.abspath(args.eve)
    refused = collections.Counter()
    pieces = collections.Counter()
    calls = collections.Counter()
    state = collections.Counter()
    lines = []
    for f in programs(args.dirs or DIRS):
        r = subprocess.run([eve, "--disasm", f], capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ROOT)
        out = r.stdout + r.stderr
        rel = os.path.relpath(f, ROOT).replace("\\", "/")
        if r.returncode == 70:
            m = re.search(r"bytecode: (.*)", out)
            refused[(m.group(1) if m else "?").strip()] += 1
            state["refused"] += 1
            lines.append(f"refused\t-\t{rel}")
            continue
        if r.returncode != 0:
            state["not a program (a syntax or check error)"] += 1
            continue
        n = 0
        for m in re.finditer(r"\b(evalx|execx)\s.*tree walker: (\w+)", out):
            pieces[m.group(1) + " " + m.group(2)] += 1
            n += 1
        for m in re.finditer(r"\bcall\s+r\d+ args \d+ (\w+)", out):
            calls[m.group(1)] += 1
        state["bridged" if n else "native"] += 1
        lines.append(f"{'bridged' if n else 'native'}\t{n}\t{rel}")
    total = sum(pieces.values())
    print("programs: " + ", ".join(f"{k} {v}" for k, v in state.items()))
    print(f"bridged pieces: {total}")
    for k, v in pieces.most_common(30):
        print(f"  {v:5}  {k}")
    print(f"call instructions: {sum(calls.values())} (" + ", ".join(f"{k} {v}" for k, v in calls.most_common()) + ")")
    if refused:
        print("refused programs, by reason:")
        for k, v in refused.most_common():
            print(f"  {v:5}  {k}")
    if args.routines:
        compiled, rejected = set(), collections.Counter()
        env = dict(os.environ, EVE_ENGINE="bc", EVE_BC_TRACE="1")
        for f in programs(args.dirs or DIRS):
            try:
                r = subprocess.run([eve, "-x", os.path.basename(f)], capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=os.path.dirname(f), env=env, timeout=60)
            except subprocess.TimeoutExpired:
                continue
            for m in re.finditer(r"bytecode: compiled (\w+ [\w!?]+)", r.stderr):
                compiled.add(m.group(1))
            for m in re.finditer(r"bytecode: the tree walker runs (\w+ [\w!?]+): (.*?) \(line", r.stderr):
                if m.group(1) != "this program":
                    rejected[(m.group(1), re.sub(r"\d+", "n", m.group(2)))] = 1
        reasons = collections.Counter(why for (_, why) in rejected)
        print(f"routines compiled at their first call: {len(compiled)}; refused: {len(rejected)}")
        for k, v in reasons.most_common(20):
            print(f"  {v:5}  {k}")
    if args.files:
        os.makedirs(os.path.join(ROOT, "temp"), exist_ok=True)
        with open(os.path.join(ROOT, "temp", "bccensus.txt"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
