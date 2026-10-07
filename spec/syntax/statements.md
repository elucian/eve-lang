# Statements

Status: **0.1-draft**, level 1. Grammar: [`grammar.md`](grammar.md). Control blocks (`if`, `match`, `job`, loops) are in [`../semantics/control.md`](../semantics/control.md); errors in [`../semantics/errors.md`](../semantics/errors.md).

A statement ends with `;` and may span lines. A group of statements is a block, indented by 2 spaces. A simple statement may end with the condition suffix `if expression`: `break if c;`, `raise "bad" if n < 0;`, `print "even" if n % 2 == 0;`. The suffix is not allowed after `done` or `expect`.

## Statements that bind a value

Every statement that creates or changes a value starts with a keyword, so the reader sees what it does (D-076, D-077).

### `new`

`new` creates variables and attributes. Declaration rules: [`declarations.md`](declarations.md#variables-and-constants).

```eve
new a = 5;                  ** light assignment, type Integer
new b = 5 :Real;            ** explicit type
new c := a + 2;             ** expression, type inferred
new d :: original;          ** deep copy
new self.x := x;            ** an attribute
new e <- queue;             ** capture: e gets the first element of queue and it leaves the list
```

A `new` statement may change the names it reads from (`new e <- queue;` changes `queue`), so it needs no `let` for that change. `new` on a name that exists is an error.

### `let`

`let` executes an assignment or an expression. One `let` statement may change several names. Only a **capture** (`let lst -> e;`, `let e <- lst;`) creates a name that does not exist, with the type of the element (Q-017, Q-033e); in a loop the name is created on the first pass and assigned again on the next ones. Any other `let` on a missing name is an error (D-076): `let y := 5;`. When the name holds a native value, the value is overwritten; when it holds a reference, the reference changes and the old object is released at the end of the scope. Writing `new` before the name is the explicit form: `let lst -> new e;`. A change without `let` (`x := 1;`) is a syntax error. The target may be a variable, an attribute `a.b`, an element `a[i]`, a slice `a[i..j]`, or `_`.

| Form | Meaning |
|---|---|
| `let x := e;` | assign the value of `e`; shares an object or collection, copies a native value |
| `let x :: e;` | assign a deep copy |
| `let x += e;` `-=` `*=` `/=` `%=` `^=` | combined assignment; on a collection `+=` adds and `-=` removes by value (all equal elements) |
| `let a <+ x;` `let x +> a;` | append `x` at the end of `a`; put `x` at the start of `a` |
| `let x << n;` `let x >> n;` | shift in place |
| `let x <- lst;` | remove the first element of `lst` into `x` (created when missing, also on the first pass of a loop) |
| `let lst -> y;` `let lst -> new y;` | remove the last element of `lst` into `y` |
| `let _ <- lst;` `let lst -> _;` | remove the first / last element and drop it |
| `lst.delete(v);` | remove every element equal to `v`, like `-=`; an arrow never removes by value (Q-031c, Q-033i) |
| `let f(x);` | run `f` and drop its result |

`=` is not an assignment operator after `let`: `let x = 5;` is an error (D-079).

### `set`

Creates a constant at script level; see declarations.

## Calls

A procedure is called as a statement, with or without parentheses when it has no arguments: `save(data);`, `foo;`, `print x;`. A function may be called as a statement only through `let f(x);`, which drops the result. A bare call of a class is not a statement.

`print` and `write` take a list of expressions. `print (1, 2, 3)` writes `1,2,3` and a new line; the named argument `sep:` changes the separator: `print (1, 2, 3, sep: " ");` writes `1 2 3`. `sep` goes between arguments only: a list given as one argument prints as a list, `(1,2,3)` (Q-019b). `write` adds no separator and no new line; `print;` alone ends the line. `read(@v, prompt)` reads a line.

## `expect` and `assert`

`expect condition;` fails when the condition is false: an error with code 2 (see errors.md). `assert condition;` fails with an error with code 3 (Q-031h): like any error, it makes the process jump to `recover`, and it ends the process when it is not recovered. The condition is a Logic expression; any other type is a compile error.

## Interruptions

| Statement | Effect |
|---|---|
| `break [label] [if c];` | leave the innermost loop, or the loop with that label; continue after its `done` (a `repeat` loop: after its `repeat`). `then` still runs |
| `skip [label] [if c];` | end the cycle and go to the continuation point of the loop (D-074) |
| `stop [if c];` | end the current job without error; inside a loop inside a job it ends the job |
| `exit;` | leave the subprogram or the process it is written in and give control back to the caller; in `main` of a driver the program ends with code 0, `finalize` runs; in a function, procedure or method it is an early `return` (a function keeps the results assigned so far; `defer` runs) (D-111) |
| `over;` | from any depth (also inside functions it called) end the whole process it is in at once with code 0; no `recover`; `finalize` runs; in an aspect the driver goes on after `apply` (D-081, D-111) |
| `panic;` | end the whole application at once with code 1; no `finalize` |
| `raise expr;` | create an error; the process jumps to `recover` |
| `return;` | end the subprogram or the process; carries no value |
| `pass;` | do nothing |

`break` and `skip` outside a loop, and `stop` outside a job, are compile errors. `retry`, `resume` and `abort` are valid only in `recover`.

## `return`

`return;` closes a process, function, procedure, method, constructor and destructor and ends it when it is reached. It has no value: results are assigned to the result variables (D-036). Closers in short: `done [label];` control blocks, `repeat [label];` the loop tested at the end, `return;` subprograms and processes, `end name;` scripts, classes and traits.

## Other statements of later levels

`apply`, `start` (level 2 and 4), `wait`, `defer`, `yield` (version 2), `call` (level 3). `async function` and `async procedure` declare subprograms that run as tasks (D-104). In a job, `spawn f(args);` starts a task and goes on; `await f(args);` starts one and waits for it, in serial mode. The tasks of a job share its core and give it away when they wait; the `done` of the job waits for every spawned task. `start` starts an aspect in a `parallel` group. An `async` subprogram can only be started with `spawn` or `await`. Level 4; open points: Q-035 in `decision_level4.md`.
