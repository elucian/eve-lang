# Issues: multitasking.html

Page: `tutorial/multitasking.html`, named `concurrency.html` until D-067 (2026-10-03); the items below quote the old name. Since D-146 (2026-10-08) the subject is split again: `multitasking.html` covers the tasks of a job (async, spawn, await) and `concurrency.html` covers parallel groups, channels and thread safety; the items about groups and channels now concern `concurrency.html`. Reviewed 2026-09-28. Retired 2026-10-06: CON-07 (`$timeout` is 60 seconds, set in the driver configuration file, on the page), CON-F1 and CON-F2 (applied). Retired: CON-02 and CON-10 (D-048), CON-03 (D-070), CON-04, CON-05, CON-08 and CON-09 (D-047, D-051, D-066); methods and their parameters moved to `methods.html` (D-069). How to answer: [README](README.md).

D-050: concurrency is not in version 1. CON-05 to CON-08 and CON-11 can wait; they don't block the 0.1 spec or the VM. D-051: asynchronous methods (`suspend`, `resume name`, `wait all`) are removed; concurrency.html now covers parallel groups, data rules, BSP and channels in one place.

## Questions

### CON-06 `wait` forms
`wait 10ms;`, `wait all;`, `wait [routine_name]`, and syntax.html: `wait` "interrupts the main process for a specified time". Confirm the three forms: a duration, `all`, a routine name.
**Answer:** Correct, must be specified. Is wait a control statement? I think it can be described in processing.html
Status: partly obsolete (D-051); `wait 10ms;` is in the statement table of syntax.html, but processing.html does not describe it yet: `wait all` and `wait name` are removed with asynchronous methods. Left: `wait 10ms;`, a pause of the process, and whether it belongs to 0.1 (D-050).

### CON-11 Rules of parallel methods
D-047 and D-051 propose: inputs passed by value (D-048, copy on write); one owner for each `@` argument, except channels; no driver globals and no nested `parallel` in a started method; `$cores` worker pool, a task waiting on a channel gives its core away; on error, cancel the tasks not begun and raise the first error at `done`; deadlock detected at `done`; `$timeout` on channel waits. Confirm, or change any rule.
**Answer:** _(open)_
Status: open

### CON-12 Channel details
D-051 designs channels. Still to decide: is `capacity` required or has a default; is `ch.receive(@x)` needed next to `for x in ch`; a `select` over several channels (wait on the first that has a value); typed send-only or receive-only parameters.
**Answer:** _(open)_
Status: open

## Spec additions once answered

- `spec/syntax/declarations.md`: routine, parameters, varargs, output parameters (CON-02, 03).
- `spec/semantics/concurrency.md`: asynchronous method model, `start` / `suspend` / `resume` / `wait`, time-out (CON-04..08).
