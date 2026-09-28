# Issues: concurrency.html

Page: `tutorial/concurrency.html` (348 lines). Reviewed 2026-09-28. How to answer:
[README](README.md).

## Questions

### CON-01 Calling a routine
This page calls routines as bare statements (`foo;`, `bar(1,2,output);`, `add_numbers;`) and says
"Routine invocation is done using name of routine as a statement". types.html and functions.html
use `call swap(x, y);`, and syntax.html defines `call` as running a shell command. One answer for
CON-01, TYP-17 and CLS-10: how is a routine called?
**Answer:** _(open)_
Status: open

### CON-02 Output parameters
`@result = 0: Integer` is an output parameter; the body writes `let result = …` (with `=`). Calls
pass it by position (`bar(1,2,output)`) or by name (`add(1,2, op:result)`). Is an `@` parameter
in/out (the routine sees the caller's value) or out only? Is a default value (`= 0`) allowed on an
`@` parameter?
**Answer:** _(open)_
Status: open

### CON-03 Parameter defaults
This page: "optional parameters use `=` with an explicit type, or `:=` with inference":
`param = value :Type`, `param := expression`. Confirm; this also answers FUN-04.
**Answer:** _(open)_
Status: open

### CON-04 Coroutines: threads or cooperative?
"A coroutine can start a secondary thread", "light weight multi-threading", and the example starts
32 consumers sharing one list. Are coroutines cooperative (one OS thread, switching at `suspend`,
`resume`, `wait`), or do they run in parallel on several cores? This decides how the Zig VM is
built.
**Answer:** _(open)_
Status: open

### CON-05 Channels
"The threads communicate using one or more channels", but no channel syntax exists; the example
shares a list through `@pipeline`. Are channels part of 0.1? If coroutines are parallel, what
protects a shared list?
**Answer:** _(open)_
Status: open

### CON-06 `wait` forms
`wait 10ms;`, `wait all;`, `wait [routine_name]`, and syntax.html: `wait` "interrupts the main
process for a specified time". Confirm the three forms: a duration, `all`, a routine name.
**Answer:** _(open)_
Status: open

### CON-07 Time-out
"If one routine times out, the entire application crashes. Set `$timeout`." Which unit is
`$timeout`, what is its default, and which exit code does the crash give (D-010)?
**Answer:** _(open)_
Status: open

### CON-08 `suspend` outside a coroutine
Any routine becomes a coroutine when called with `start`. What happens at `suspend` in a routine
that was called without `start`?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### CON-F1 Wrong content
- The shoulder-thread example's main block is `routine:` → `process`; `start generator(…):` ends in
  `:`.
- `let result = param1 + param2;` → `:=`; `print ("outout=", output)`.
- "The main thread is yielding" while `yield` is unused (syntax.html) → "suspended".
- A past word replace turned "process" into "routine" in prose: "routine current batch", "you can
  routine the batch".
- Image `/images/asynch.svg` does not exist (file is in `/assets/images/`).
**Answer:** _(open)_

### CON-F2 Typos
multi-treding, thred, conntrol, inpur, concentions, tread, necesary, "you do create", "a a bunch",
"Routine do not have to be follow".
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### CON-I1 Move routines to functions.html
Routines are introduced here but used from types.html on. Move "Routines", "Side Effects" and
"Parameters" to functions.html (or a "Subprograms" page); keep this page for coroutines.
**Answer:** _(open)_

## Spec additions once answered

- `spec/syntax/declarations.md`: routine, parameters, varargs, output parameters (CON-01..03).
- `spec/semantics/concurrency.md`: coroutine model, `start` / `suspend` / `resume` / `wait`,
  time-out (CON-04..08).
