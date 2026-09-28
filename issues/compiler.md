# Issues: compiler.html

Page: `tutorial/compiler.html` (303 lines, added by T1.1). Reviewed 2026-09-28 against decisions
D-004 to D-013. How to answer: [README](README.md).

## Questions

### CMP-01 Mention the official implementation
D-006 and D-007 make the Zig VM (`evevm/`, `bin/eve.exe`) the official implementation. Should this
page say so, link the manual, and add Zig to the "Recommended Languages" table? The manifest also
says reference code is "written in Go".
**Answer:** _(open)_
Status: open

### CMP-02 Test runner and exit codes
Should the "Conformance Levels" section describe `script/runtest.py` (D-009) as the way to test any
implementation (`--eve <path>`), and list the exit codes of D-010?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### CMP-F1 Lexer section is out of date
It explains `--` end-of-line and `+---- … ----+` box comments, removed by D-011, and does not
mention `#`, `##`, `(* … *)`. Rewrite once SYN-04, SYN-16 and SYN-17 are answered; mention the
`(*` / vararg `*` ambiguity as a lexer pitfall.
**Answer:** _(open)_

### CMP-F2 Examples
`driver hello_world:` → no colon (D-012). Test file names follow SYN-14.
**Answer:** _(open)_
