<!--# Multitasking design-->

Status: **approved** 2026-10-03 as D-067, with the answers of section 6. Answers Q-021. The tutorial chapter `concurrency.html` is renamed `multitasking.html`. Builds on D-066 (aspects) and D-051 (channels). Generators and the module `task` are in the tutorial now and specified in version 2.

## 1. Principles

- **Multitasking** is the name of the chapter and of the topic: several pieces of work make progress together. The words "concurrency", "coroutine" and "async" are not used in Eve.
- Eve has **two tools**, one for each kind of work:

  | Tool | Kind of work | Cores | Switch points | Language feature |
  |---|---|---|---|---|
  | Parallel aspects | computing, and waiting on input/output | several | none visible: the VM decides | `parallel`, `start` (D-066) |
  | Generators | producing values one by one, cooperative steps | one, the caller's | `yield`, written by the programmer | `yield` |

- **No coroutines.** A generator is suspended only at a `yield` in its own body and always gives control back to its caller. Nothing else in the language can be suspended. There is no `async`, `await` or `suspend`, and a method never needs a mark because it may wait.
- Methods and functions run in serial mode, on the core of their caller (D-066).

## 2. Parallel aspects

As in D-066: the driver starts aspects in a `parallel` group; inputs by value, one owner for each `@` output, `done` is the barrier; BSP, pipelines with channels. One addition:

- **A waiting aspect gives its core away.** A started aspect that waits for input/output (file, network, database, `wait 10ms;`) or on a channel releases its worker thread to another task, and continues when the wait is over. This extends the channel rule of D-051. It is done by the VM and is invisible in the language: the code of the aspect is plain sequential code.
- Effect: a group can start more aspects than there are cores, and overlap their waits. Calling 50 services is one group of 50 started aspects on a few cores. Inside one aspect, input/output is still sequential.

## 3. Generators

### 3.1 Declaration

A generator is a **method whose body contains `yield`**. It declares exactly one result, the value it produces. A function can't contain `yield` (a function has no state, D-026, D-027).

```eve
** produce the numbers 1 to n, one at a time
method count_to(n: Integer) => (@x: Integer) is
  for i in (1..n) do
    yield i;          ** x := i, give x to the caller, wait here
  done;
return;               ** no more values
```

- `yield expression;` assigns the result and suspends. `yield;` gives the current value of the result.
- `return;` ends the generator: the consumer sees that there are no more values.
- A generator can be infinite (`loop do … yield …; repeat;`): the consumer decides when to stop.
- A generator can be a method of a class: `method walk(@self) => (@node: Node) is …`.

### 3.2 Use

A call of a generator does not run its body. It creates a **generator object**, an instance of the core class `Generator(:T)` where `T` is the type of the result. The body runs only when a value is requested.

```eve
** 1. the for loop drives the generator
for v in count_to(5) do
  print v;                         ** 1 2 3 4 5
done;

** 2. a comprehension collects the values
let squares := (v * v | v in count_to(5));   ** (1, 4, 9, 16, 25)

** 3. a generator object driven by hand
let g := count_to(3);              ** no new: new is for the objects of a class
while g.next() do                  ** run to the next yield; False after return
  print g.value;                   ** the last value given by yield
done;
```

`Generator(:T)` members:

| Member | Meaning |
|---|---|
| `g.next()` | run the body to the next `yield`: `True` and a new `g.value`; `False` when the body has returned |
| `g.value` | the last value given by `yield`; reading it before the first `next()` is an error |
| `g.done` | `True` after the body has returned or after `close()` |
| `g.close()` | stop the generator early and drop its state |

A plain statement call, `count_to(5);`, is a compiler error: a generator is used in a `for`, a comprehension or assigned to a variable.

### 3.3 Rules

1. **One level.** `yield` is allowed only in the body of the generator method itself: not in a method or function it calls, not in a lambda, not in a process. A method called by the generator runs to completion. A generator that needs the values of another one loops over it and yields them again: `for c in child.walk() do yield c; done;`. This rule is what keeps generators from being coroutines.
2. **Lazy.** The arguments are evaluated when the generator object is created; the body begins at the first `next()`.
3. **State.** The parameters and local variables live in the generator object between two `yield`s. They are dropped when the body returns, at `close()`, or when the object is no longer referenced. A `for` loop left with `break` closes its generator.
4. **Parameters.** Inputs only, passed by value. A generator can't have `@` input/output parameters other than its result: a reference kept across `yield` could outlive the variable it points to.
5. **Errors.** An error raised in the body ends the generator (`done` becomes `True`) and is raised in the consumer, at the `next()` or the `for` line. A generator has no `recover`; the process of the consumer handles the error, like for any method.
6. **One consumer.** A generator object is not copied. Passing it to a method shares the same object (like a channel). It can't be an argument of `apply` or `start`: it belongs to one process and one core.

### 3.4 Cooperative multitasking with generators

Generators are also the cooperative tasks of Eve. Each generator is a task, each `yield` is a point where it lets the others run. A loop in the caller, or a library scheduler, gives the turns. No new language feature.

```eve
# two tasks take turns on one core
driver ping_pong is
  method ping(n: Integer) => (@step: Integer) is
    for i in (1..n) do
      print "ping";
      yield i;                       ** let the other task run
    done;
  return;

  method pong(n: Integer) => (@step: Integer) is
    for i in (1..n) do
      print "pong";
      yield i;
    done;
  return;

  process main is
    let a := ping(3);
    let b := pong(3);
    while not (a.done and b.done) do
      a.next() if not a.done;
      b.next() if not b.done;
    done;                            ** ping pong ping pong ping pong
  return;
end ping_pong;
```

Library help (module `task`, not a keyword; documented now, implemented in version 2): `task.round_robin(tasks)` runs a list of generators in turns until all are done; `task.until(g, condition)` runs one until a condition holds.

### 3.5 Generators and channels

A generator runs on the core of its consumer, so it can't feed a started aspect directly (rule 6). To stream the values of a generator to parallel workers, a started producer aspect creates the generator and sends its values into a channel: `for v in source() do jobs.send(v); done;`.

## 4. Chapter `multitasking.html`

1. Introduction: two tools, the table of section 1, no coroutines.
2. Methods, side effects, parameters (kept from `concurrency.html`).
3. Generators: declaration, use, rules, cooperative tasks.
4. Parallel aspects: model, groups, data rules, errors, workers (with "a waiting aspect gives its core away").
5. Bulk Synchronous Parallel.
6. Channels and pipelines.
7. Choosing a model: the table gets two rows, "Generator" (lazy sequences, streams in one process) and "Cooperative tasks" (interleaved steps on one core, deterministic, no locks).

The closure generator of `functions.html` (D-027) is kept as a closure example and points to Generators.

## 5. Effects on the language

- Keyword `yield`: from "reserved, unused" to used. `suspend` stays removed.
- Core library: class `Generator(:T)`; module `task` (proposed).
- Exceptions: a new code for "generator value read before next()" and "yield outside a generator method" (compile time).
- Spec: `spec/semantics/concurrency.md` (step S4.5) becomes `multitasking.md`.
- Tests: generators are single-threaded, so they can have level 1 tests even if parallel aspects wait (D-050).
- VM: the current tree-walking interpreter runs a body with the Zig call stack, so it can't stop in the middle of a nested loop and continue later. A generator needs its own saved position: either the interpreter keeps an explicit stack of statements for a generator body, or the compiler rewrites the body into a state machine. Rule 1 (one level) makes both possible without a second stack.

## 6. Questions for the author

1. **Version 1:** are generators in version 1? They need no threads, but they need the VM work of section 5.
**answer** we design generators now and put them in tutorial but postpone the speecification for version 2.
2. **Declaration:** a method is a generator because its body contains `yield` (as above, like Python), or it is marked in the header, for example `=> (@x: Generator(:Integer))`? Recommendation: by `yield`, the compiler reports a plain call as an error, so the reader is never surprised.
**answer** Because is using yield, is a method become generator. 

3. **`yield expression;`** as a short form of `x := expression; yield;`: keep both forms?
**answer** We favor explicit over implicit. I would say result := expression, where result is defined by the method => symbol, then yield; But for charm we can use yield expression; we can support both.

4. **`new`:** `let g := new count_to(3);` (as above, a generator object is an object) or `let g := count_to(3);`?
We reserve "new" for objects. We use let g := count(3) is more simple, and is like functional programming, Eve is already a bit functional.
5. **Library `task`:** add `round_robin` and `until` now, or leave cooperative scheduling to examples?
**answer** document in tutorial this feature. We implement it later in version 2.

6. **Rename:** confirm `concurrency.html` → `multitasking.html`, and `issues/concurrency.md` → `issues/multitasking.md` (CON ids kept).
**answer** yes.
