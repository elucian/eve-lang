# Conformance

Status: **0.1-draft**. An implementation conforms to a level when it passes every test of that level and of the levels below it. The tests are in `test/levelN/`; this file defines how a test is written and what a runner checks (D-094, answers Q-005). The reference runner is `script/runtest.py`.

## Levels

| Level | Folder | Content |
|---|---|---|
| 1 | `test/level1/` | one script: lexical rules, types, expressions, control flow, functions, classes, errors |
| 2 | `test/level2/` | projects: aspects, lambdas and closures (D-109, D-112) |
| 3 to 7 | `test/level3/` … | modules and imports, data, parallel, database, server, web |

## Test files

- A level 1 test is one `.eve` file: `a01_name.eve`, `a02_name.eve`, … (`b01_` for level 2). The name follows the rules of identifiers (D-018). Each test checks **one feature**.
- Line 1 is the title, `# what the test shows (decision ids)`, and line 2 may name the part of the specification it covers: `** spec: semantics/control.md#loops`.
- A test is a script that uses `expect` for its logic and `print` for its output. A test that passes writes nothing to the error output.
- A **negative test** has a compile error or a lexical error on purpose and declares `"syntax_error": true` and `"exit": 65`; the implementation must refuse to run it.

## Expectations: `/*@expect … */` blocks

What a test must produce is written **in the test**, in one or more comment blocks that start with `/*@expect` and hold a JSON object. The block is an ordinary block comment for Eve; by convention it is the last thing in the file. A runner reads the blocks, merges them (a list is extended, any other key is replaced) and compares:

```eve
/*@expect
{
  "exit": 2,
  "stdout": ["before"],
  "stderr": ["expect failed"]
}
*/
```

| Key | Meaning | Default |
|---|---|---|
| `exit` | exit code of the process (errors.md) | `0` |
| `args` | command-line arguments | `[]` |
| `stdout` | the exact standard output, a string or a list of lines; line endings and trailing white space at the end are ignored | none |
| `contains` | strings that must all appear in the standard output | none |
| `stderr` | strings that must all appear in the error output (an implementation may word its messages differently, so only the parts that matter are given) | none |
| `syntax_error` | the test must be refused by the compile step (`--check`, exit 65) | `false` |
| `files` | project tests: files that must exist after the run, with their content | none |
| `state` | introspection states after the run: the map `jobs` of the process (`{"j1": "pass"}`) *(planned)* | none |
| `skip` | a reason: the test is not run on this implementation | none |
| `note` | free text | |

A test that prints must declare `stdout` or `contains`; the output of a program is part of its expectations. A negative test (`syntax_error`) is exempt: its script never runs.

## Verdicts

PASS, FAIL (wrong exit code, output or state), ERROR (the runner could not run the implementation, or a timeout) and SKIP. A conformance claim lists the spec version, the level, and the tests skipped with their reasons.

## Coverage of level 1

| Part of the specification | Tests |
|---|---|
| Script, comments, print | a01 to a05, a66 |
| Variables, constants, assignment, system variables | a06, a23, a43 to a46, a77, a80, a81 |
| Operators, literals, strings | a07 to a11, a28, a47, a48, a62, a78, a82 |
| Types, conversions, optional and variant types | a57, a59, a61 |
| Control flow | a12 to a16, a39, a49 |
| Ranges | a58, a63 |
| Collections | a17 to a22, a38 |
| Functions, procedures, parameters, process arguments | a24, a25, a56, a60, a64, a65, a71 to a74, a79 |
| Classes and methods | a26, a40 to a42, a55, a67 |
| Errors and exit codes | a29 to a37, a50 to a54, a68 to a70, a75, a76 |

Not testable at level 1: exit code 5 (unexpected stop), which needs an outside signal.

Not covered yet, waiting for decisions: lambdas and closures are level 2 (D-109), formats of interpolation (D-060, a11 is a draft), `Date`, `Time` and the operator `as` are outside level 1 (D-108; level 3, data language).

Updated by D-098 (2026-10-06, static edits, the VM was not run): the tests follow D-096 and D-097. Placeholders `\n{name % fmt}` hold a name only (a11 and every test that prints a number); a failed `assert` stops the process with code 3 (a52); `m.delete(v)` replaces the removal by value and `let m -> last;` captures (a17); `let` creates a missing name (a43, now `a43_let_creates_name`); an attribute added from outside the class is a compile error (a22, new a55); ordinals start at 1 (a16); `-2 ^ 2` is `4` (a07); a regex literal keeps its backslashes (a28); `sep` (a05); level 2 is in the current syntax and its expectations are `/*@expect*/` blocks.
