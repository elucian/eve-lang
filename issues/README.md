# Tutorial Issues

One file per tutorial page (`tutorial/<page>.html` → `issues/<page>.md`): questions for the author
and proposed improvements, found by the page-by-page review (plan step T1.10).

## How to answer

Edit the file. Write your answer under the issue's `Answer:` line, replacing `_(open)_`. Short
answers are fine ("yes", "use `<>`", "drop it"). To reject a proposed fix, write "no" and why.

```
### SYN-05 Not-equal operator
...
**Answer:** `<>` only. `!` is the sigil for unsafe operations.
```

When a file is answered, Claude:

1. turns settled answers into decisions in `plan/decisions.md`;
2. fixes the page (the tutorial is edited in the scl repo);
3. adds the rules to the specification in `spec/`, after asking any follow-up questions;
4. marks each issue: `Status: open` → `answered` → `done`.

Issue ids are stable: `SYN-01` stays `SYN-01` even when issues are added or closed. An issue that
depends on another points to it (`see SYN-03`).

## Kinds

| Kind | Meaning |
|---|---|
| **Question** | The page contradicts itself, the examples, or the spec. Needs an answer. |
| **Fix** | An error with one obvious correction: typo, broken HTML, wrong example. Applied unless you write "no". |
| **Improve** | A suggestion for structure or clarity. Applied only if you write "yes". |

## Pages

In index order (index.html first). Totals: 160 questions.

| Page | File | Questions | Fixes / improvements | Answered |
|---|---|---|---|---|
| index.html | [index.md](index.md) | 2 | 1 | 0 |
| manifest.html | [manifest.md](manifest.md) | 4 | 2 | 0 |
| syntax.html | [syntax.md](syntax.md) | 30 | 9 | 33 |
| types.html | [types.md](types.md) | 22 | 6 | 0 |
| topology.html | [topology.md](topology.md) | 16 | 6 | 0 |
| control.html | [control.md](control.md) | 16 | 5 | 7 |
| functions.html | [functions.md](functions.md) | 10 | 3 | 0 |
| classes.html | [classes.md](classes.md) | 14 | 6 | 0 |
| collections.html | [collections.md](collections.md) | 20 | 6 | 0 |
| processing.html | [processing.md](processing.md) | 13 | 4 | 2 |
| concurrency.html | [concurrency.md](concurrency.md) | 8 | 3 | 0 |
| library.html | [library.md](library.md) | 6 | 2 | 0 |
| command.html | [command.md](command.md) | 6 | 1 | 0 |
| databases.html | [databases.md](databases.md) | 4 | 3 | 0 |
| algorithms.html | [algorithms.md](algorithms.md) | 2 | 2 | 0 |
| option.html | [option.md](option.md) | 3 | 0 | 0 |
| compiler.html | [compiler.md](compiler.md) | 2 | 2 | 0 |
| template.html | [template.md](template.md) | 0 | 1 | 0 |

## Questions that span pages

Some questions recur; one answer closes all of them:

| Topic | Issues |
|---|---|
| Placeholders and escapes in strings | SYN-12, TYP-15, COL-15, COL-16, LIB-06 |
| Calling a routine: bare, `call`, shell | TYP-17, CLS-10, CON-01, CMD-01 |
| Exit codes and interruptions | SYN-13, TOP-09, PRC-01, PRC-02, PRC-03, CON-07 |
| Result and output parameters (`@`) | FUN-02, CON-02, ALG-02 |
| Parameter defaults `=` / `:=` | FUN-04, CON-03 |
| System variables | TOP-08, CMD-05 |
| `print` and `write` | SYN-07, LIB-04 |
| Public / private members | SYN-08, CLS-02 |
| Block colons and closers | SYN-11, CTL-01, CTL-04, CTL-08 |
| Broken `/images/` links | CTL-F1, COL-F2, PRC-F1, CON-F1 |
