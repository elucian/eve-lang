# 08 Static review of evevm against the spec (2026-10-07)

Scope: `evevm/src/lexer.zig`, `parser.zig`, `ast.zig`, `interp.zig` (tree-walking interpreter, 5.9k lines) read against `spec/` (D-093 to D-111). Baseline on level 1: 16 pass, 66 fail, almost all with exit 65 (the parser refuses the new syntax). Findings are grouped by the part that must change; each is closed when the test that shows it passes.

## Lexer
- L1 `digits` accepts `_`: `1_000` must be a lexical error (a78, Q-013).
- L2 No exponent: `1.5e3`, `2e-3` (a09, D-095).
- L3 Missing operators `+>` (prepend, D-107) and `+-` (tolerance of `=~`, D-079); stale `!~` (does not exist, D-079).
- L4 A name can't end with `!` (`next!`, `count!()`; functions that are not deterministic, D-087).
- L5 An indented `#` falls through as a symbol; the spec makes it a lexical error (Q-016).

## Parser (the grammar is the one of D-036, before D-076)
- P1 Declarations: the parser declares with `let`/`set`; the spec has `new` (variable, with `=`, `:=`, `::`, `<-`, deconstruction, `name: Type`), `set` (constant), `let` (change only, D-104: a capture creates a missing name). `new` is a reserved word that no statement accepts.
- P2 Missing statements and keywords: `procedure`, `exit`, `stop`, `assert`, `defer`, `pass`, `def`, `public`/`protected`/`private`, `destructor`, `other` in `match`, `one`/`all`, labels in front of `loop`, `match`, `while`, `for` and `done label;`.
- P3 Parameters: no vararg `*name`, no `:=` default, a shared type (`a, b: Integer`) gives the type to `b` only; `name = value :Type`; a second parameter list (the constructor `(@self)(fields)`) must go (D-029); `(@self)` result of a constructor.
- P4 Interpolation: the old `\s{}`, `\#{}`, `\b{}` with `:` for the format; the spec (D-102) has `{name}` and `{name % format}`, `\{` and `\}` for braces, a bare brace that is not a placeholder is a lexical error; a string that starts with `/` is a raw regex literal (D-097).
- P5 Expressions: `-2 ^ 2` must be 4 (the unary minus applies first, Q-030) but `unary` calls `unary` under `power`; `+>`, `+-` missing; `<+`, `<-`, `->` are parsed as the loosest binary operators of an expression, the spec has them as modifiers of `let` (and expression forms); the step of a range as a postfix `(0..10)(2)`; `eq`, `is not` fine.
- P6 Classes: the shape is only `{members}`; the spec has ordinals `{Red, Green}`, ranges, function types; the superclass `<:` is mandatory (Q-029); `end Name;`.
- P7 `process name(params) is`: the process takes parameters (D-040); `process` declarations and statements may be mixed, with `recover`/`finalize`; `return;` can be written inside a block (exit rules D-111).
- P8 `reserved` lists 40 words; `spec/lexical/keywords.json` has 73. The list must come from the spec.

## Interpreter
- I1 No analysis before the run. D-110: an undefined name, a wrong operand type, a redeclaration, `let` of an undeclared name, a procedure used as a value, a bad placeholder, a mandatory parameter after optional ones given by position are compile errors (exit 65, nothing printed). The interpreter finds them at run time, after output (a68).
- I2 Exit codes (D-081, D-111): `over` returns without `finalize` (must run it) and ends only the current scope; `exit` is missing; an unhandled error exits with `it.err_code` (must be 4; 2 for `expect`, 3 for `assert`); `abort` in `recover` skips `finalize`; `$error.line` missing; no code 5.
- I3 Error classes and codes (D-109): index, key, division, overflow must set `$err_index` 10, `$err_key` 11, `$err_divide` 12, `$err_overflow` 13 and the `$err_*` constants must exist; `raise "x"` is code 4.
- I4 `procedure`/`function` rules (D-100, D-101, D-106): result lists, `@` by reference, named-after-optional, vararg, `defer`.
- I5 System variables: `set $epsilon`, a driver's own `$name` (D-109).
- I6 `exec` has no case for `defer`, `stop`, `exit`, `assert`, `pass`.

## Plan
Work test by test (a01 to a82). A failing test is checked against the spec: a wrong test is fixed, a right one fixes the VM. The static analysis of I1 is a new pass, `check.zig`, between the parser and the interpreter.

## Result (2026-10-07)
All findings are closed: level 1 passes 82 of 82 on `bin/eve.exe`. The parser follows `spec/syntax/grammar.md` (new/let/set, procedures, parameters, placeholders, labels, match one/all/other); `check.zig` is the new static pass of I1; exit codes, error codes, `over`/`exit`/`defer` and the jobs map follow D-081, D-109 to D-111. Fixed in the tests: a80 (a capture in a loop does not create a name that outlives the loop). Fixed in the runner: a negative test that prints is not asked for an expected output. Known limits: Text is recognized by the address of the literal; Decimal and Float are `f64`; Huge is `i64`; visibility is checked statically only for typed variables.
