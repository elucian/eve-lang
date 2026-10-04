# Tutorial Issues

One file per tutorial page (`tutorial/<page>.html` → `issues/<page>.md`): questions for the author
and proposed improvements, found by the page-by-page review (plan step T1.10).

Lost in the list? Start with the [priority list](PRIORITY.md).

## How to answer

Edit the file. Write your answer under the issue's `Answer:` line, replacing `_(open)_`. Short
answers are fine ("yes", "use `<>`", "drop it"). To reject a proposed fix, write "no" and why.

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

Issue ids are stable: `CLS-09` stays `CLS-09` even when issues are added or closed. An issue that
depends on another points to it (`see CLS-09`).

## Kinds

| Kind | Meaning |
|---|---|
| **Question** | The page contradicts itself, the examples, or the spec. Needs an answer. |
| **Fix** | An error with one obvious correction: typo, broken HTML, wrong example. Applied unless you write "no". |
| **Improve** | A suggestion for structure or clarity. Applied only if you write "yes". |

## Pages

In index order (index.html first). Open items on 2026-10-01: 86 questions. An item is removed when its
answer is applied to the tutorial and recorded in `plan/decision_levelN.md`; the ids of removed items are retired
(their text is in the git history before 2026-10-01). Spec work still points to the decisions.

| Page | File | Open questions | Open fixes / improvements | Retired |
|---|---|---|---|---|
| index.html | [index.md](index.md) | 2 | 1 | 0 |
| manifest.html | [manifest.md](manifest.md) | 4 | 2 | 0 |
| syntax.html | [syntax.md](syntax.md) | 6 | 0 | 33 |
| types.html | [types.md](types.md) | 1 | 2 | 25 |
| topology.html | [topology.md](topology.md) | 2 | 1 | 19 |
| control.html | [control.md](control.md) | 0 | 0 | 21 |
| functions.html | [functions.md](functions.md) | 0 | 0 | 13 |
| classes.html | [classes.md](classes.md) | 9 | 6 | 8 |
| collections.html | [collections.md](collections.md) | 2 | 0 | 21 |
| processing.html | [processing.md](processing.md) | 10 | 4 | 4 |
| multitasking.html | [multitasking.md](multitasking.md) | 8 | 2 | 5 |
| library.html | [library.md](library.md) | 6 | 2 | 0 |
| command.html | [command.md](command.md) | 5 | 1 | 1 |
| databases.html | [databases.md](databases.md) | 4 | 3 | 0 |
| algorithms.html | [algorithms.md](algorithms.md) | 2 | 2 | 0 |
| option.html | [option.md](option.md) | 3 | 0 | 0 |
| compiler.html | [compiler.md](compiler.md) | 2 | 2 | 0 |
| template.html | [template.md](template.md) | 0 | 1 | 0 |

## Questions that span pages

Some questions recur; one answer closes all of them:

| Topic | Issues |
|---|---|
| Placeholders and escapes in strings | COL-15, COL-16, LIB-06 |
| Exit codes and interruptions | PRC-02, PRC-03, CON-07 |
| Result and output parameters (`@`) | ALG-02 (CON-02 retired, D-048) |
| System variables | TOP-08, CMD-05 |
| `start`, `apply` and processes | PRC-07, PRC-14, TOP-10, CON-09 |
| Class model (constructor, traits) | CLS-14 to CLS-17 |
| Broken `/images/` links | COL-F2, PRC-F1, CON-F1 |
