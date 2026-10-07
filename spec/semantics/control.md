# Control Flow

Status: **0.1-draft**, level 1. Syntax: [`../syntax/grammar.md`](../syntax/grammar.md). Sources: D-016, D-020, D-030, D-033, D-034, D-074.

## General pattern

A control block has declarations, a transition keyword, executable statements, optional clauses and a terminator:

```text
[label:] <control>
  declarations (local scope)
<transition>
  statements
[clauses]
<terminator>
```

A block with a label closes with `done label;`, one without with `done;` (D-034). `if` has no label. `done job`, `done match`, `done loop` and `done if` do not exist. A statement that is a jump point (`job`) requires a label; the others may have one.

## `if`

```eve
if a > b do
  print "a";
else if a == b do
  print "equal";
else
  print "b";
done;
```

The condition must be a Logic value. Exactly one branch runs. `if` and its branches open no scope: a variable created in a branch belongs to the enclosing scope. Not-taken branches do not run their `new`.

## `match`

```eve
match n
  when (1..5) do print "low";
  when 6, 7 do print "mid";
  when other do print "out";
then
  print "done";
done;
```

- `match s one` (the default) runs only the first `when` whose value matches; `match s all` runs every matching `when`.
- A `when` lists values, or a range, or an ordinal name. Values are compared with `==`; a range with `in`.
- `when other do` runs only when no other `when` matched. `then` runs after the match for any path, including `other`.
- Declarations written before the first `when` live in the scope of the match. A compiler warns when an ordinal selector has no `when other` and not all values are covered.

## Loops

There are three loops (D-074). The optional header `[label:] loop` followed by declarations belongs to a `while` or `for` loop: its declarations live in the loop scope, survive all iterations and are visible in `then` and `else`.

```eve
while c do … done;                   ** tested at the start
for x in r do … done;                ** visits a range or a collection
[label:] loop do … repeat [label] [while c];   ** tested at the end: the body runs at least once
```

| Loop | Rules |
|---|---|
| `while c do` | the condition is checked before every cycle; `else` runs only if the condition was false the first time; `then` runs every time the loop ends, also after `break` |
| `for x in r do` | `r` is a range or a collection (a trait `Iterable` in version 2); `x` is created for the loop and is visible in `then`, not after `done`; a collection is not changed while it is visited; a pattern `(k, v)` deconstructs a pair; a DataMap is visited in key order |
| `loop … do … repeat;` | `repeat` closes the loop; `repeat while c;` goes on while `c` is true, tested after the body; a bare `repeat;` loops until `break`; no `else`, no `then` |

- `break [label] [if c];` leaves the loop (an outer loop with its label).
- `skip [label] [if c];` goes to the continuation point: in a `for` the next element; in a `while` the test of the condition; in a `repeat` loop the test at the end (a bare `repeat;` starts the next cycle).
- A `new` in the body is created again at every cycle; what must survive is declared in the `loop` header.
- An infinite loop is `loop do … repeat;` left with `break`, or `while True do`; a constant `True` condition gets no warning.

## Job

A job is a labeled block of a process, at the top level of the process (not in a function, a procedure, a method or another job):

```eve
c1: job
  new n = 0;
do
  …
  stop if done_early;
done c1;
```

A job passes at `done` or `stop` and fails when an error is raised in it, also by a function or a procedure it calls. The process keeps the state in the map `jobs["name"]`: `.status` (`"none"` before it ran, `"pass"`, `"fail"`), `.error`, `.line`. The recover region reads `$error.job`, the label of the failed job. Nothing is reported automatically.

## Scope summary

| Block | Opens a scope |
|---|---|
| `if`, ladder | no |
| `match` | yes: the part before the first `when` |
| `job` | yes: the declarations before `do` |
| `while`, `for`, `loop` | the header declarations, once; the body, at every cycle |
| a `for` without header | only its control variable |

## Parallel

`parallel` groups of aspects belong to level 4 and are not part of level 1.
