# The module `test`

Status: **draft**, level 6 (D-189). Feature: F-LIB-12 (testing module, new). Written in Eve: `lib/test.eve`. Tests: `test/level6/f03_test_module`. Registry: [registry.md](registry.md).

## What it is

A small module for the tests that a user writes in Eve. Each check prints one line, `ok <name>` or `FAIL <name>` (with the two values for `equal`), counts it, and goes on; `summary` prints the totals and raises an error when a check failed, so the process ends with a failure code and a script or a CI job sees it. It is the first big program of the standard library written in Eve (D-189): a missing feature of the language found while writing it goes to `backlog/library-gaps.md`.

```eve
from lib use (test);

primary aspect t is
  process main is
    test.check("one is positive", 1 > 0);
    test.equal("sum", 1 + 2, 3);
    test.differ("not the same", "a", "b");
    test.close("pi", 3.14159, 3.14, 0.01);
    test.summary();
  return;
end t;
```

## Members

| Member | Kind | Meaning |
|---|---|---|
| `check(name: String, ok: Logic)` | procedure | counts a pass when `ok` is `True`, a failure otherwise |
| `equal(:T)(name: String, actual: T, expected: T)` | generic procedure | a pass when `actual == expected`; a failure prints `FAIL name: expected X, got Y` |
| `differ(:T)(name: String, actual: T, other: T)` | generic procedure | a pass when the two values are not equal |
| `close(name: String, actual: Real, expected: Real, tolerance: Real)` | procedure | a pass when `abs(actual - expected) <= tolerance` |
| `passed!() => (@result: Integer)` | function | the number of passes so far |
| `failed!() => (@result: Integer)` | function | the number of failures so far |
| `summary()` | procedure | prints `<n> passed, <m> failed`; raises the error `test failed: <m> checks` (code 4, the plain `raise` of a message) when `m > 0` |

The counters are state of the module (one per process, D-068); they are read with `!` functions because they change between calls (D-087).

## Rules

- A check never stops the process: all failures are shown. Only `summary` raises.
- The output format is the one of `script/runtest.py` (`ok name` lines), so a test driver of the repository can use `test` and an `/*@expect*/` block with `contains`.
- `test` has no Zig part; it uses nothing but the language.
