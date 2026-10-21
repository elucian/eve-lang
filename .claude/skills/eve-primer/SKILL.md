---
name: eve-primer
description: Learn Eve fast for this repo. Use before writing or editing Eve code (tests in test/, library in lib/, examples), or when you need to find which spec page, decision or test defines a language rule.
---

# Eve primer

Eve is a scripting language for data processing and test automation. The reference engine is the tree walker in `code/evevm/`; run a file with `bin/eve.exe file.eve` (or `temp/rel/bin/eve.exe`, see the `eve-test-loop` skill).

## The shape of a file

```
# one-line title; the next line may carry  ** spec: syntax/statements.md#new
primary aspect a06_new_set_let is
  set limit = 10 :Integer;        ** set: a constant
  new counter := 0;               ** new: a variable (":=" infers the type, "= v :Type" states it)

  process main is
    let counter += 2;             ** a change always starts with let
    expect counter == 2;          ** expect: the assertion that tests use
    return;
  end main;
end a06_new_set_let;
```

- Every statement ends with `;`. Blocks end with `end <name>;`. A process ends with `return;` before its `end`.
- Comments: `#`/`##` at column 0, `**` to end of line, `(** ... **)`, `/* ... */`.
- Top level is an `aspect` (`primary`, `exclusive`, `concurrent`), a `module`, or a `macro`. A free script with `#!` is no longer valid (D-179). Declarations: `new`, `set`, `let`, `class`, `trait`, `function`, `process`, `import`, `export`, `apply`.
- Contextual keywords are preferred over reserved ones (D-116): do not add a reserved word without a decision.
- The author owns the syntax: never replace a form with your own proposal. Raise a question with `python script/plan.py` / `design/decision/` instead.

## Find the rule, not the guess

| You need | Go to |
|---|---|
| The grammar | `spec/syntax/grammar.md`, `statements.md`, `expressions.md`, `declarations.md` |
| Tokens, keywords, operators | `spec/lexical/` (`keywords.json`, `operators.json`) |
| Types, semantics | `spec/semantics/`; library in `spec/library/` and `lib/` |
| A worked example of a feature | `grep -rl "<keyword>" test/level*/` ; tests are named after the rule (`a06_new_set_let.eve`) |
| Why a rule is what it is | `python script/plan.py show D-nnn` (never read `design/decision/level*.md` whole) |
| Is the feature built | `python script/plan.py feature F-XXX-nn`, `plan.py features open 6` |
| The parser or checker code | `grep -rn "@spec spec/syntax/statements.md#let" code/` (tags link code to spec) |

Levels (`spec/features/`): 1 a single script, 2 a project (subprograms, aspects), 3 modules and classes, 4 parallel processing, 5 data and database (macros tests are here too), 6 the Eve machine and the server, 7 the web. `test/smoke/` is a quick sample of all; `test/bytecode/` tests the bytecode machine only.

## Expectations in tests

A test is a `.eve` file (or a folder) in `test/levelN/`; what it must print or fail with lives in `/*@expect*/` blocks (`test/readme.md`, "A test is a .eve file"). A negative test names the error text it expects (for instance `has no process main`). Copy the nearest existing test before writing a new one, and add the failing test before the feature (D-194 order).

## Before you change the language

1. A plan entry and a failing test first (`design/dev-guide.md`, by section: `python script/outline.py design/dev-guide.md`).
2. Parser: `code/evecp/src/parser.zig` (core) and `code/evecp/src/parser/*.zig` (expressions, statements, classes, modules, aspects). Checker: `check.zig`, `overload.zig`. Interpreter: `code/evevm/src/interp.zig` and `interp/`.
3. Spec follows the tests; manual after the spec; tutorial last.
