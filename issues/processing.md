# Issues: processing.html

Page: `tutorial/processing.html` (414 lines). Reviewed 2026-09-28. How to answer:
[README](README.md).

## Questions

### PRC-01 `abort`
The job pattern starts with `abort if condition;`: "silent stop, do not execute finalization or
recovery". `abort` is not in the keyword table. Is it a keyword, and how does it differ from `over`
and `exit`? Which exit code (D-010)?
**Answer:** _(open)_
Status: answered → D-020: abort is used only in recover; preconditions use over 1

### PRC-02 Which interruptions run `finalize`
"`exit` or `raise` trigger the finalization region while `over` and `panic` skip it"; later
"finalize is executed except for {abort | over}" and "{exit, raise, expect} execute the
finalization region". Please fill in: for each of `return`, `exit`, `raise`, failed `expect`,
`over`, `panic`, `abort`: runs `recover`? runs `finalize`? exit code?
**Answer:** _(open)_
Status: partly answered by D-020: errors go to recover; finalize runs after return, exit and abort, not after over and panic; exit codes open

### PRC-03 `expect` and `assert`
`expect condition, "message";` raises `AssertError`. D-010 gives a failed `expect` exit code 2
(error) and a failed `assert` exit code 3 (warning), but `assert` appears on no page. What is the
`assert` statement's syntax? Does a failed `assert` continue the process?
**Answer:** _(open)_
Status: open

### PRC-04 `catch` versus `recover`
Jobs catch errors with `catch …` (control.html); processes have a `recover` region. "In recover,
the user can detect which job failed." How: `$error.job`, the job name as an object? Can `recover`
resume after the failing job?
**Answer:** _(open)_
Status: answered → D-020: jobs have no catch; recover reads $error.job and ends with retry, resume or abort

### PRC-05 `run`: synchronous or asynchronous
syntax.html: `run` "executes an aspect in asynchronous mode". This page: `run` blocks the driver
("synchronous call") unless it is inside `split … join`. Which is it? Can the argument list omit
parentheses (`run aspect_name argument_value;`)?
**Answer:** _(open)_
Status: answered → D-016: apply name to (args); waits for the aspect; begin inside fork starts it asynchronously

### PRC-06 Recursive aspects
"The compiler will detect a recursive aspect and will fail at runtime." Compile-time error or
run-time failure?
**Answer:** _(open)_
Status: open

### PRC-07 Parallel groups
`begin group1: … split: run a; run b; join group1;`. syntax.html: `begin` = local scope, `split` =
run async, `join` = end of `begin`. Are `begin` names required? When one aspect in a group fails,
are the others in the same group stopped or awaited?
**Answer:** _(open)_
Status: partly answered → D-016: name: parallel … fork … begin … join name; failure of one aspect still open

### PRC-08 `raise` forms
Three forms: `raise $ExceptionType("message");` (a `$` type?), `raise (code, "message") if c;`,
and `raise "error" if c;` (control.html). Which are valid? Is an error code required?
**Answer:** _(open)_
Status: open

### PRC-09 The Exception module prototype
The pseudocode declares methods with a receiver: `method (@self:Error) .raise(…)`, unlike
classes.html where object methods live in constructors. It also declares `class .Error` twice.
Keep this as an explicit "prototype, not valid Eve", or rewrite it in the classes.html syntax?
**Answer:** _(open)_
Status: open

### PRC-10 Driver arguments from the command line
`driver process_call(*args ()String)` here and `driver test(*args: ()String)` with
`eve:>start test.eve 1 2 3` on concurrency.html. For the VM (`bin/eve.exe script.eve 1 2 3`): are
command-line arguments always strings, bound to the driver's parameters by position? Can a driver
declare typed parameters (`driver d(n: Integer)`) that the VM converts?
**Answer:** _(open)_
Status: open

### PRC-11 Locating aspects
"You do not import an aspect, but specify its relative path": `run [folder/]aspect_one(args)`.
Relative to the driver file or to the working directory? File extension implied?
**Answer:** _(open)_
Status: open

### PRC-12 `apply` forms
The page had `apply aspect_name to (args);` and `apply [folder/]aspect_one(arguments);`. The second
form was normalized to `apply [folder/]aspect_one to (arguments);`. Is `to` required, or is
`apply name(args)` also valid?
**Answer:** _(open)_
Status: open

### PRC-13 `begin` changed meaning
`begin` used to open a local-scope block; now it starts an aspect asynchronously inside `fork`.
Is there still a plain local-scope block, and with which keyword?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### PRC-F1 Wrong content
- "The compiler … will fail at runtime" (see PRC-06).
- `driver process_call(*args ()String)` missing `:`; `for arg in args loop;` extra `;`.
- `set a = 0.00;` has no type; `a := 1/0` is Real division (may give infinity, not an error).
- Image `/images/parallel_system.svg` does not exist (file is in `/assets/images/`).
- "When the project finish the local variables are released" → the process.
- "He can abort the program" → the developer.
**Answer:** _(open)_

### PRC-F2 Typos
crate (create), prematurly, succesfully, sigle, othe, THerefore, alwais, metods, Nots, inlcuding,
jons, immediatly, automaticly, anothe, "to not have", intreruption, fialization, "ca be", "a
argument".
**Answer:** _(open)_

### PRC-F3 Authoring standard
"We think this process structure provides a robust framework…" and its four-item benefits list;
"prevent catastrophic defects".
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### PRC-I1 Interruption table
The table from PRC-02 on the page, with exit codes from D-010.
**Answer:** _(open)_

## Spec additions once answered

- `spec/semantics/control.md`: interruptions, recover, finalize, exit codes (PRC-01..04, 08).
- `spec/semantics/topology.md`: aspects, `run`, groups, recursion (PRC-05..07, 11).
- `manual/usage.md`: command-line arguments (PRC-10).
