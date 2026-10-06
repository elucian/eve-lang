# Issue priority

Where to spend your answers first. Rewritten 2026-10-06 from the open items in this folder; the earlier list (2026-10-01) was mostly answered and applied. The tutorial comes first (`review/focus.md`); the VM and the test suites are paused, so ranking by "blocks the VM" no longer applies.
Answer in the issue files as usual (see [README](README.md)); this page only orders the work.

**Counts (2026-10-06):** 28 open questions, 3 open fixes or improvements, 6 answered SPEC questions waiting for the spec, 2 library answers waiting for `evevm/lib` and the spec.

## 1. Class model (7 questions)

[classes.md](classes.md): CLS-09 generic syntax, CLS-12 dynamic objects, CLS-13 property and method with one name, CLS-14 destructor timing, CLS-15 adopting a trait outside the class, CLS-16 library traits, CLS-17b hidden state in an abstract class; CLS-I1 split the page, CLS-I2 member table. The class pages changed most in D-084 to D-087, so these answers shape the next rewrite of `classes.html` and `methods.html`.

## 2. Collections and strings (2)

COL-05 (capture a removed element with `let` inside a statement), COL-16 (interpolation formats: review the page).

## 3. Shell commands, options, compiler (9)

CMD-02 to CMD-06 (exit status, `cd`, `export`, working-folder variable, `File` and `Folder`; CMD-05 is the same question as in [spec/semantics/variables.md](../spec/semantics/variables.md)), OPT-01 to OPT-03 (symbol table, other symbols, where the page belongs in the index), CMP-02 and CMP-F3 (test runner and the out-of-date conformance table).

## 4. Algorithms, types, multitasking (6)

ALG-01 (purpose of the page), ALG-02 (native types in signatures, result default value), TYP-19 (review the Date proposal), CON-06, CON-11, CON-12 (not in 0.1, D-050).

## 5. Databases (4)

DB-01 to DB-04: wait for the answers to `plan/design-database.md` and the rewrite of the page (focus F4), then ask again.

## 6. Spec work with no question left

SPEC-01 to SPEC-06 in [syntax.md](syntax.md), LIB-01 and LIB-02, the spec text for LIB-06 and PRC-10 (`manual/usage.md`).
