# Conformance

Status: **draft**. An implementation conforms to a level when it passes every test of that level and of the levels below it. This page defines how a test is written and what a runner checks.

## Levels

| Level | Content |
|---|---|
| 1 | one script: lexical rules, types, expressions, control flow, errors |
| 2 | projects: functions, procedures, lambdas and closures, aspects |
| 3 | modules and imports, classes |
| 4 | parallel work, traits and generic classes |
| 5 | generic subprograms, the data language, the database layer |
| 6 | the machine and the server |
| 7 | the web |

The features of each level are in `features/` (one file per level). A test declares the features it checks in its tracking file (`features`, a list of feature ids), so the coverage of a feature is read from the tests, not written here.

## Test files

- A level 1 test is one `.eve` file: `a01_name.eve`, `a02_name.eve`, … (`b01_` for level 2, `c01_` for level 3, and so on). The name follows the rules of identifiers. Each test checks **one feature**.
- Line 1 is the title, `# what the test shows`, and line 2 may name the part of the specification it covers: `** spec: semantics/control.md#loops`.
- A test is a script that uses `expect` for its logic and `print` for its output. A test that passes writes nothing to the error output.
- A **negative test** has a compile error or a lexical error on purpose and declares `"syntax_error": true` and `"exit": 65`; the implementation must refuse to run it.
- A **project test** is a folder that holds a whole Eve project: the primary aspect has the name of the folder, and further primary aspects `<code>_test1.eve`, `<code>_test2.eve` are variations of the same project.

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
| `files` | project tests: files that must exist after the run, with their content (line endings and trailing white space ignored) | none |
| `bytes` | files that must hold exactly these bytes, the UTF-8 of the text: line endings, a byte order mark and trailing spaces count | none |
| `command` | the arguments of `eve` alone, with no script: the test runs one command of the machine (`["db", "proc", "list"]`) | none |
| `client` | with `command`: the command starts a machine that keeps running, and this program (`["node", "check/api.test.js"]`) is the test; its output is checked | none |
| `state` | introspection states after the run: the map `jobs` of the process (`{"j1": "pass"}`) *(planned)* | none |
| `skip` | a reason: the test is not run on this implementation | none |
| `note` | free text | |

A test that prints must declare `stdout` or `contains`; the output of a program is part of its expectations. A negative test (`syntax_error`) is exempt: its script never runs.

## Verdicts

PASS, FAIL (wrong exit code, output or state), ERROR (the runner could not run the implementation, or a timeout) and SKIP. A conformance claim lists the spec version, the level, and the tests skipped with their reasons.

## The tracking file

The result of a run is kept in one JSON file per suite (`tests.schema.json` in `schema/`): for every test its `id`, `name`, `title`, `features`, `status` (the last verdict, or `NEW`), `runs`, `failures`, `checks`, `last` (date of the last run) and `reason` (why the last run failed). Only the runner writes the verdict fields.

Not testable at level 1: exit code 5 (unexpected stop), which needs an outside signal.
