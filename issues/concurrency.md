# Issues: concurrency.html

Page: `tutorial/concurrency.html` (348 lines). Reviewed 2026-09-28. How to answer:
[README](README.md).

## Questions

### CON-02 Output parameters
`@result = 0: Integer` is an output parameter; the body writes `result = …` (with `=`). Calls
pass it by position (`bar(1,2,output)`) or by name (`add(1,2, op:result)`). Is an `@` parameter
in/out (the method sees the caller's value) or out only? Is a default value (`= 0`) allowed on an
`@` parameter? (D-038: a process has `@` outputs and no result.)
**Answer:** _(open)_
Status: open

### CON-03 Parameter defaults
This page: "optional parameters use `=` with an explicit type, or `:=` with inference":
`param = value :Type`, `param := expression`. Confirm; this also answers D-029.
**Answer:** _(open)_
Status: open

### CON-04 Asynchronous methods: threads or cooperative?
"An asynchronous method runs in a secondary thread", "light weight multi-threading", and the example starts
32 consumers sharing one list. Are asynchronous methods cooperative (one OS thread, switching at `suspend`,
`resume`, `wait`), or do they run in parallel on several cores? This decides how the Zig VM is
built.
**Answer:** _(open)_
Status: open

### CON-05 Channels
"The threads communicate using one or more channels", but no channel syntax exists; the example
shares a list through `@pipeline`. Are channels part of 0.1? If asynchronous methods are parallel, what
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

### CON-08 `suspend` outside an asynchronous method
Any method becomes asynchronous when called with `start`. What happens at `suspend` in a method
that was called without `start`?
**Answer:** _(open)_
Status: open

### CON-09 `start` for methods and for processes
D-043: `start aspect.process(args);` launches an aspect process in a `parallel … fork … join` group, and
`start method(args);` launches an asynchronous method, joined by `wait all;`. Keep one keyword for the two
kinds of concurrent work, or give the method one its own word?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### CON-F1 Wrong content
- `start generator(…):` ends in `:`.
- `let result = param1 + param2;` → `result := param1 + param2;`; `print ("outout=", output)`.
- "The main thread is yielding" while `yield` is unused (syntax.html) → "suspended".
- Image `/images/asynch.svg` does not exist (file is in `/assets/images/`).
**Answer:** _(open)_

### CON-F2 Typos
multi-treding, thred, conntrol, inpur, concentions, tread, necesary, "you do create", "a a bunch",
"Routine do not have to be follow".
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

## Spec additions once answered

- `spec/syntax/declarations.md`: routine, parameters, varargs, output parameters (CON-02, 03).
- `spec/semantics/concurrency.md`: asynchronous method model, `start` / `suspend` / `resume` / `wait`,
  time-out (CON-04..08).
