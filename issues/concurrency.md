# Issues: concurrency.html

Page: `tutorial/concurrency.html` (348 lines). Reviewed 2026-09-28. How to answer:
[README](README.md).

D-050: concurrency is not in version 1. CON-05 to CON-08 and CON-11 can wait; they don't block the 0.1 spec or the VM.
D-051: asynchronous methods (`suspend`, `resume name`, `wait all`) are removed; concurrency.html now covers parallel
groups, data rules, BSP and channels in one place.

## Questions

### CON-02 Output parameters
`@result = 0: Integer` is an output parameter; the body writes `result = …` (with `=`). Calls
pass it by position (`bar(1,2,output)`) or by name (`add(1,2, op:result)`). Is an `@` parameter
in/out (the method sees the caller's value) or out only? Is a default value (`= 0`) allowed on an
`@` parameter? (D-038: a process has `@` outputs and no result.)
**Answer:** @ indicate input/output parameter, so it can't be optional. Output parameter need a pointer and because accept values as input parameter it can't be initialized with default value. Correct examples.
Status: answered by D-048, examples corrected

### CON-03 Parameter defaults
This page: "optional parameters use `=` with an explicit type, or `:=` with inference":
`param = value :Type`, `param := expression`. Confirm; this also answers D-029.
**Answer:** Correct, we can initialize default parammeters with expressions but pragmatic usecase is type inference.
Status: open

### CON-04 Asynchronous methods: threads or cooperative?
"An asynchronous method runs in a secondary thread", "light weight multi-threading", and the example starts
32 consumers sharing one list. Are asynchronous methods cooperative (one OS thread, switching at `suspend`,
`resume`, `wait`), or do they run in parallel on several cores? This decides how the Zig VM is
built.
**Answer:** Only processes run on parallel cores using "parallel" block. The methods are cooperative methods on a single core. I need design decisions for running methods in parallel on GPU. GPU optimization is out of scope in version 1.
Status: answered by D-047 and D-051: a method called by name runs to completion on its caller's core (no cooperative
switching, `suspend` removed); methods started in a `parallel` group run on several cores; aspects run only with
`apply`. GPU is out of scope.

### CON-05 Channels
"The threads communicate using one or more channels", but no channel syntax exists; the example
shares a list through `@pipeline`. Are channels part of 0.1? If asynchronous methods are parallel, what
protects a shared list?
**Answer:** We need design details invented for creation of channels. Design is open.
Status: answered by D-051: channels are designed (`Channel(:T)`, `send`, `for x in ch`, `receive`, `close`,
`senders: n`), not in 0.1 (D-050). The pipeline example of concurrency.html solves the problems found in the
author's first producer-consumer example:
- `workers: parallel is` … `done workers;` has no `do` (D-046).
- `in` is a keyword (`for … in`) and can't name a parameter.
- `out: @Channel(:Integer)`: `@` belongs to the parameter name (`@out: Channel(:Integer)`).
- `Channel(:Integer)(capacity: 100)` without `new` is not a constructor call (D-036).
- `while element := in.receive() do`: `:=` mutates an existing variable, it does not declare one; and an element 0
  would read as false. End of stream needs its own signal, e.g. `for x in channel do`.
- Deadlock: 10,000 elements go into `partials` (capacity 1000) and nobody reads it before `done workers`. After 1000
  elements the consumers block, the producer blocks on the full `pipeline`, and the barrier never opens.
- Nobody closes `partials`, and 32 consumers can't know who should; `partials.sum()` on a channel would have to drain it.
- The consumers only copy, so the work is serial; a channel is a shared mutable object, the one thing D-047 forbids.

### CON-06 `wait` forms
`wait 10ms;`, `wait all;`, `wait [routine_name]`, and syntax.html: `wait` "interrupts the main
process for a specified time". Confirm the three forms: a duration, `all`, a routine name.
**Answer:** Correct, must be specified. Is wait a control statement? I think it can be described in processing.html
Status: partly obsolete (D-051): `wait all` and `wait name` are removed with asynchronous methods. Left: `wait 10ms;`,
a pause of the process, and whether it belongs to 0.1 (D-050).

### CON-07 Time-out
"If one routine times out, the entire application crashes. Set `$timeout`." Which unit is
`$timeout`, what is its default, and which exit code does the crash give (D-010)?
**Answer:** $timeout is 1 minute (60s), the unit of measure is seconds. It can be provided in configuration file for driver.
Status: open

### CON-08 `suspend` outside an asynchronous method
Any method becomes asynchronous when called with `start`. What happens at `suspend` in a method
that was called without `start`?
**Answer:** Good question. "start" is used to run processes in parallel on multicore processor. It does no longer run methods. Methods are run by name like statements. Just mention them and they execute, no call or keyword will tell you if they run synchronously or asynchronously. When suspended, states are saved and control is given back to caller process. If noone resume them they remain suspended until process ends. If process end and nobody is waiting, the method is terminated/killed. If wait is used, until timeout the method will stay suspended unti some other methood send a signal to unlock it. 
Status: obsolete (D-051): `suspend` is removed.

### CON-09 `start` for methods and for processes
D-043: `start aspect.process(args);` launches an aspect process in a `parallel … do … done` group, and
`start method(args);` launches an asynchronous method, joined by `wait all;`. Keep one keyword for the two
kinds of concurrent work, or give the method one its own word?
**Answer:** _(open)_
Status: answered by D-047: `start` launches only methods, in a parallel block; aspects use `apply`.

### CON-10 `@` at the call site
Examples write `start square(i, @s[i]);` and `apply reports.total(10, @sum);`, but concurrency.html also calls
`add(1,2, op:result);` without `@`. Is `@` before an output argument required, optional or wrong? D-047 needs the
element and slice forms: `@s[i]`, `@nxt[a..b]`.
**Answer:** @ is required for output parameters, it shows that a reference is required pass by refference, this enable output parameters. Otherwise the pass by value is employied even for collections that is a lower level ideomatic. Not input/output higher level abstraction.
Status: answered by D-048

### CON-11 Rules of parallel methods
D-047 and D-051 propose: inputs passed by value (D-048, copy on write); one owner for each `@` argument, except
channels; no driver globals and no nested `parallel` in a started method; `$cores` worker pool, a task waiting on a
channel gives its core away; on error, cancel the tasks not begun and raise the first error at `done`; deadlock
detected at `done`; `$timeout` on channel waits. Confirm, or change any rule.
**Answer:** _(open)_
Status: open

### CON-12 Channel details
D-051 designs channels. Still to decide: is `capacity` required or has a default; is `ch.receive(@x)` needed next
to `for x in ch`; a `select` over several channels (wait on the first that has a value); typed send-only or
receive-only parameters.
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
