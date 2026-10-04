# Issue priority

Where to spend your answers first. Written 2026-10-01 from the `Status:` lines of the files in this folder.
Answer in the issue files as usual (see [README](README.md)); this page only orders the work.

**Update 2026-10-02:** the six library issues are answered (D-053). Tutorial page and spec still to update.

**Counts (2026-10-01):** 64 open, 5 partial, 19 closed (done, answered, obsolete or declined). Items answered and applied
earlier were removed from the files (ids retired), so they are not counted here.

**How the order was chosen.** The Zig VM must pass test levels 1 to 3 first (print, strings, control,
functions, collections, errors). An issue ranks high when the VM or the spec can't be written without the
answer, and when one answer closes several issues. Concurrency is not in 0.1 (D-050), so it ranks low.

## Counts by area

| Priority | Area | Page / file | Open | Partial | Closed |
|---|---|---|---|---|---|
| 1 | Library: input, output, built-ins | [library](library.md) | 0 | 0 | 6 |
| 1 | Errors, exit codes, processes | [processing](processing.md), [topology](topology.md) | 8 | 3 | 2 |
| 1 | Strings and collections | [collections](collections.md) | 18 | 0 | 1 |
| 1 | Spec to write (already answered) | [syntax](syntax.md) | 0 | 0 | 6 |
| 2 | Functions and parameters | [algorithms](algorithms.md), CON-02, CON-03 in [multitasking](multitasking.md) | 3 | 0 | 1 |
| 2 | Classes and traits | [classes](classes.md) | 9 | 0 | 0 |
| 2 | Types | [types](types.md) | 1 | 1 | 1 |
| 3 | Control flow | [control](control.md) | 0 | 0 | 0 |
| 3 | Multitasking (not in 0.1) | [multitasking](multitasking.md) | 3 | 1 | 5 |
| 4 | Shell commands | [command](command.md) | 5 | 0 | 0 |
| 4 | Databases | [databases](databases.md) | 4 | 0 | 0 |
| 4 | Compiler page, manifest, index | [compiler](compiler.md), [manifest](manifest.md), [index](index.md) | 4 | 1 | 3 |
| 4 | Options, templates | [option](option.md), [template](template.md) | 3 | 0 | 0 |

`control.md`, `functions.md` and `template.md` have no open item: those pages are settled.

## Priority 1: blocks the VM and the first tests

One answer closes several issues in each group.

1. **Strings: placeholders, escapes, text.** COL-15, COL-16, LIB-06 (COL-17, 19, 20 answered, D-058).
   Every test uses `print` with strings, so this comes first.
2. **Input and output.** LIB-03 `read`, LIB-04 `write` and `print`, LIB-05 standard error.
   These decide the `.out` files of the conformance tests.
3. **Built-ins for 0.1.** LIB-01 (the list), LIB-02 (mutating string functions), TOP-08 (system variables, the
   rest of it). They define what the VM must contain.
4. **Errors and exit codes.** PRC-02 (`finalize`), PRC-03 (`expect` and `assert`), PRC-08 (`raise` forms),
   PRC-09 (Exception module). They give the exit codes in `expect.json`.
5. **Collections core.** COL-02, COL-05 (map notation, list operation doubts; COL-01, 07 answered, D-058). Test levels 2 and 3 use them.
6. **Write the spec for the answered items.** SPEC-01 to SPEC-06: no question left, only work. This is the
   cheapest progress in the folder.

## Priority 2: next, once the core runs

7. **Functions.** ALG-02 (native types in signatures), CON-03 (parameter defaults), ALG-01. Small, and they
   unblock the function tests.
8. **Class model.** CLS-09 (generics), CLS-10, CLS-11, CLS-17 (constructor shape), then CLS-12 to CLS-16.
9. **Collections, the rest.** COL-03 (filter clause), COL-14 (object attributes); the rest answered, D-058.
10. **Processes and aspects.** PRC-06, PRC-10, PRC-11, PRC-13, PRC-14, PRC-07 (partial).
11. **Types.** TYP-19 date literals, TYP-I1, TYP-I2.

## Priority 3: not in 0.1

12. **Multitasking.** CON-07 time-out, CON-11 rules of parallel methods, CON-12 channel details, CON-06
    (partial). Defer all of it until the VM runs sequential programs (D-050).

## Priority 4: cheap or independent

13. **Shell commands.** CMD-02 to CMD-06 (exit status, `cd`, `export`, `File` and `Folder`). CMD-05 is
    part of TOP-08.
14. **Databases.** DB-01 to DB-04. Needs the library first.
15. **Compiler page.** CMP-01 and CMP-02: answer in one line each, and the page is finished.
16. **Manifest.** MAN-01: choose the license of the VM code.
17. **Index and options.** IDX-01, IDX-02, OPT-01 to OPT-03.

## Suggested next session

Answer the six issues of priority 1, groups 1 and 2 (COL-15, COL-16, LIB-06, LIB-03, LIB-04, LIB-05).
They unlock the first `print` tests. Then do SPEC-01 to SPEC-06 for the spec work.
