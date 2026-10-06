# Tutorial Issues

One file per tutorial page (`tutorial/<page>.html` → `issues/<page>.md`): questions for the author and proposed improvements, found by the page-by-page review (plan step T1.10).

Lost in the list? Start with the [priority list](PRIORITY.md).

## How to answer

Edit the file. Write your answer under the issue's `Answer:` line, replacing `_(open)_`. Short answers are fine ("yes", "use `<>`", "drop it"). To reject a proposed fix, write "no" and why.

```
### SYN-05 Not-equal operator
...
**Answer:** `<>` only. `!` is the sigil for unsafe operations.
```

When a file is answered, Claude:

1. turns settled answers into decisions in `plan/decision_level1.md` or `plan/decision_level2.md`;
2. fixes the page (the tutorial is edited in the scl repo);
3. adds the rules to the specification in `spec/`, after asking any follow-up questions;
4. marks each issue: `Status: open` → `answered` → `done`.

Issue ids are stable: `CLS-09` stays `CLS-09` even when issues are added or closed. An issue that depends on another points to it (`see CLS-09`).

## Kinds

| Kind | Meaning |
|---|---|
| **Question** | The page contradicts itself, the examples, or the spec. Needs an answer. |
| **Fix** | An error with one obvious correction: typo, broken HTML, wrong example. Applied unless you write "no". |
| **Improve** | A suggestion for structure or clarity. Applied only if you write "yes". |

## Pages

In index order (index.html first). Open items on 2026-10-06: 28 open questions, 3 open fixes or improvements, 6 answered questions waiting for the spec (syntax.md) and 2 for the library. An item is removed when its answer is applied to the tutorial and recorded in `plan/decision_levelN.md`; the ids of removed items are retired (their text is in the git history before 2026-10-06). Spec work still points to the decisions.

| Page | File | Open questions | Open fixes / improvements |
|---|---|---|---|
| index.html | [index.md](index.md) | 0 | 0 |
| manifest.html | [manifest.md](manifest.md) | 0 | 0 |
| syntax.html | [syntax.md](syntax.md) | 6 (answered, spec pending) | 0 |
| types.html, datetime.html | [types.md](types.md) | 1 | 0 |
| topology.html | [topology.md](topology.md) | 0 | 0 |
| control.html | [control.md](control.md) | 0 | 0 |
| functions.html | [functions.md](functions.md) | 0 | 0 |
| classes.html | [classes.md](classes.md) | 7 | 2 |
| collections.html | [collections.md](collections.md) | 2 | 0 |
| processing.html | [processing.md](processing.md) | 0 (PRC-10: VM and manual only) | 0 |
| multitasking.html | [multitasking.md](multitasking.md) | 3 | 0 |
| library.html | [library.md](library.md) | 0 (LIB-01, LIB-02: answered, library and spec pending) | 0 |
| command.html | [command.md](command.md) | 5 | 0 |
| databases.html | [databases.md](databases.md) | 4 (ask again after the rewrite, F4) | 0 |
| algorithms.html | [algorithms.md](algorithms.md) | 2 | 0 |
| option.html | [option.md](option.md) | 3 | 0 |
| compiler.html | [compiler.md](compiler.md) | 1 | 1 |
| template.html | [template.md](template.md) | 0 | 0 |

## Questions that span pages

Some questions recur; one answer closes all of them:

| Topic | Issues |
|---|---|
| Placeholders and escapes in strings | COL-15, COL-16, LIB-06 |
| Exit codes and interruptions | PRC-02, CON-07 |
| Result and output parameters (`@`) | ALG-02 (CON-02 retired, D-048) |
| System variables | TOP-08, CMD-05 |
| Class model (destructor, traits) | CLS-14 to CLS-16, CLS-17b |
| Broken `/images/` links | COL-F2, PRC-F1, CON-F1 |
