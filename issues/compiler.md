# Issues: compiler.html

Page: `tutorial/compiler.html` (303 lines, added by T1.1). Reviewed 2026-09-28 against decisions D-004 to D-013. Retired 2026-10-06: CMP-01 (the page names the Zig VM as the official implementation and lists Zig), CMP-F1 (lexer section now follows D-011, D-014, D-019), CMP-F2 (examples already use `driver … is`). How to answer: [README](README.md).

## Questions

### CMP-02 Test runner and exit codes
Should the "Conformance Levels" section describe `script/runtest.py` (D-009) as the way to test any implementation (`--eve <path>`), and list the exit codes of D-010?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### CMP-F3 Conformance table is out of date
The "Conformance Levels" section lists three levels with `a01_`, `b01_` and `c01_` files. The repository now has `test/level1` to `test/level7` plus `test/vm`; a level-2 test is a folder (D-073) and each level has a `status.json`. Rewrite the table from `test/readme.md` and `plan/version_map.md`.
**Answer:** _(open)_

