#!/usr/bin/env python3
"""Check the library registry against the signature files (D-189, spec/library/registry.md rule 1 and 2).

Usage: python script/libcheck.py

For every lib/sys/<module>.eve that has `external` members and whose module is in the `natives` table of
code/evevm/src/dlib.zig (handlers also in syslib.zig): each `external function|procedure name` must appear as a quoted string "name" in dlib.zig, and each
module in `natives` must have a lib/sys/<module>.eve. Modules that live in the interpreter (io, exception)
are skipped: they are not in `natives`. Exit 1 on any mismatch.
"""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
zig_dlib = (root / "code/evevm/src/dlib.zig").read_text(encoding="utf-8")
zig = zig_dlib + (root / "code/evevm/src/syslib.zig").read_text(encoding="utf-8") + (root / "code/evevm/src/netlib.zig").read_text(encoding="utf-8")
table = re.search(r"natives = std\.StaticStringMap\(Native\)\.initComptime\(\.\{(.*?)\}\);", zig, re.S)
natives = set(re.findall(r'\.\{\s*"([a-z_]+)"', table.group(1))) if table else set()
math_modules = ("basic", "explog", "trig", "numtheory", "linear", "random", "rational", "complex", "time", "zone", "meta")  # signatures in lib/math/, natives in mathlib.zig (an enum of names)
mathlib = "".join((root / "code/evevm/src" / n).read_text(encoding="utf-8") for n in ("mathlib.zig", "linearlib.zig", "randomlib.zig", "rationallib.zig", "complexlib.zig", "timelib.zig", "metalib.zig"))
bad = []
total = [0]
for m in sorted(natives):
    f = root / "lib" / "sys" / f"{m}.eve"
    for alt in (root / "lib" / f"{m}.eve", root / "lib" / "math" / f"{m}.eve", root / "lib" / "meta" / f"{m}.eve"):
        if not f.exists() and m in math_modules and alt.exists():
            f = alt
    if not f.exists():
        bad.append(f"module {m}: in natives, no lib/sys/{m}.eve")
        continue
    text = f.read_text(encoding="utf-8")
    for name in re.findall(r"external\s+(?:function|procedure)\s+([A-Za-z_][A-Za-z_0-9]*!?)", text):
        total[0] += 1
        if f'"{name}"' not in zig and not (m in math_modules and re.search(r'(?<![A-Za-z_0-9])' + re.escape(name) + r'(?![A-Za-z_0-9])', mathlib)):
            bad.append(f"{m}.{name}: in lib/sys/{m}.eve, no native \"{name}\" in dlib.zig")
for f in sorted((root / "lib" / "sys").glob("*.eve")):
    m = f.stem
    if m not in natives and m not in ("io", "exception"):
        bad.append(f"lib/sys/{m}.eve: module not in natives (and not an interpreter module)")
print(f"libcheck: {len(natives)} native modules, {total[0]} externals checked")
for b in bad:
    print("  FAIL", b)
sys.exit(1 if bad else 0)
