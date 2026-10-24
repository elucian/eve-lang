#!/usr/bin/env python3
"""The Linux gate from Windows: runs the steps of .github/workflows/ci.yml in WSL on the committed HEAD.

    python script/wsl-gate.py                 install Zig if needed, clone/update ~/eve-gate in WSL, run the whole gate
    python script/wsl-gate.py --quick         skip the unit tests (conformance, bytecode, tags only)
    python script/wsl-gate.py --setup         only install Zig 0.17.0 and clone, do not run the gate
    python script/wsl-gate.py --distro NAME   the WSL distribution (default Ubuntu-24.04)

The work folder is ~/eve-gate on the Linux file system (not /mnt/c: slow, and file modes differ). The repository there
is fetched from this working copy, so local commits are tested without a push; uncommitted changes are not.
The log of the run is temp/output-linux/gate.log. Exit code 0 only when every step passed.
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZIG_VERSION = "0.17.0"   # build.zig.zon minimum_zig_version
NODE_VERSION = "22.11.0"  # LTS; the web tests only need `node`

INNER = r'''#!/usr/bin/env bash
# written by script/wsl-gate.py
set -u
SRC="@SRC@"
WORK="$HOME/eve-gate"
ZIGDIR="$HOME/zig-@ZIG@"
SHA="@SHA@"
NODEDIR="$HOME/node-@NODE@"
QUICK=@QUICK@
SETUP=@SETUP@
fail=0
step() { echo; echo "=== $1"; }
run() { local name="$1"; shift; step "$name"; if "$@"; then echo "--- PASS: $name"; else echo "--- FAIL: $name"; fail=1; fi; }

if [ ! -x "$ZIGDIR/zig" ]; then
  step "install Zig @ZIG@"
  mkdir -p "$ZIGDIR.tmp" && curl -fsSL "https://ziglang.org/download/@ZIG@/zig-x86_64-linux-@ZIG@.tar.xz" | tar -xJ -C "$ZIGDIR.tmp" --strip-components=1 || { echo "FAIL: Zig download"; exit 1; }
  mv "$ZIGDIR.tmp" "$ZIGDIR"
fi
export PATH="$ZIGDIR:$NODEDIR/bin:$PATH"
if [ ! -x "$NODEDIR/bin/node" ]; then
  step "install Node @NODE@ (the web tests)"
  mkdir -p "$NODEDIR.tmp" && curl -fsSL "https://nodejs.org/dist/v@NODE@/node-v@NODE@-linux-x64.tar.xz" | tar -xJ -C "$NODEDIR.tmp" --strip-components=1 && mv "$NODEDIR.tmp" "$NODEDIR" || echo "WARN: Node download failed"
fi
echo "zig $(zig version), python $(python3 --version 2>&1)"

git config --global --add safe.directory '*'
if [ ! -d "$WORK/.git" ]; then git clone -q "$SRC" "$WORK" || exit 1; fi
cd "$WORK" || exit 1
git fetch -q "$SRC" "$SHA" && git checkout -q -f "$SHA" || { echo "FAIL: checkout $SHA"; exit 1; }
git clean -fdxq -e zig-pkg -e .zig-cache -e temp/rel
# the *.db files are in Git LFS (D-222): lib/meta/meta.db is embedded in eve.exe and must be the real file
if command -v git-lfs >/dev/null 2>&1; then git lfs install --local >/dev/null 2>&1; git lfs pull >/dev/null 2>&1; fi
if [ -f lib/meta/meta.db ] && head -c 40 lib/meta/meta.db | grep -q "git-lfs"; then echo "FAIL: lib/meta/meta.db is a Git LFS pointer; install git-lfs in WSL (sudo apt install git-lfs) and run the gate again"; exit 1; fi
echo "commit $(git log --oneline -1)"
[ "$SETUP" = 1 ] && { echo "setup done"; exit 0; }

mkdir -p temp/output-linux
[ "$QUICK" = 1 ] || run "unit tests" zig build test --summary all
run "ReleaseSafe build" zig build -Doptimize=ReleaseSafe -p temp/rel
run "evedb build (DuckDB server)" bash -c "cd drivers/duckdb && zig build -Doptimize=ReleaseSafe -p ../../temp/rel"
EXE=temp/rel/bin/eve
run "conformance tests on both engines" python3 script/runtest.py all --both --eve "$EXE" -q
run "bytecode tests" python3 script/bctest.py --no-update --eve "$EXE"
run "tags" python3 script/tagcheck.py
run "features and links" python3 generator/evegen.py check
run "release notes" python3 script/relnotes.py --check
run "manual links" python3 script/mdlinks.py check manual
echo; [ $fail = 0 ] && echo "LINUX GATE: PASS" || echo "LINUX GATE: FAIL"
exit $fail
'''


def wsl_path(p):
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", p)
    return "/mnt/%s/%s" % (m.group(1).lower(), m.group(2).replace("\\", "/"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--distro", default="Ubuntu-24.04")
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--setup", action="store_true")
    args = ap.parse_args()

    sha = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--untracked-files=no"],
                           capture_output=True, text=True).stdout.strip()
    if dirty:
        print("note: uncommitted changes are not tested; the gate runs on commit " + sha[:7])

    out = os.path.join(ROOT, "temp", "output-linux")
    os.makedirs(out, exist_ok=True)
    script = INNER.replace("@SRC@", wsl_path(ROOT)).replace("@ZIG@", ZIG_VERSION).replace("@NODE@", NODE_VERSION).replace("@SHA@", sha)
    script = script.replace("@QUICK@", "1" if args.quick else "0").replace("@SETUP@", "1" if args.setup else "0")
    inner = os.path.join(out, "inner.sh")
    with open(inner, "w", encoding="utf-8", newline="\n") as f:
        f.write(script)

    log = os.path.join(out, "gate.log")
    cmd = ["wsl", "-d", args.distro, "--", "bash", wsl_path(inner)]
    with open(log, "w", encoding="utf-8", newline="\n") as lf:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for raw in p.stdout:
            line = raw.decode("utf-8", "replace")
            sys.stdout.write(line)
            lf.write(line)
        code = p.wait()
    print("log: " + os.path.relpath(log, ROOT))
    sys.exit(code)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
