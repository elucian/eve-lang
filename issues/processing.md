# Issues: processing.html

Page: `tutorial/processing.html` (414 lines). Reviewed 2026-09-28. How to answer:
[README](README.md).

## Questions

### PRC-02 Which interruptions run `finalize`
"`exit` or `raise` trigger the finalization region while `over` and `panic` skip it"; later
"finalize is executed except for {abort | over}" and "{exit, raise, expect} execute the
finalization region". Please fill in: for each of `return`, `exit`, `raise`, failed `expect`,
`over`, `panic`, `abort`: runs `recover`? runs `finalize`? D-038 fixed the exit codes (`over;` 0,
`panic` 1, failed `expect` 2, failed `assert` 3) and made `panic` global.
**Answer:** _(open)_
Status: partly answered by D-020 and D-038: errors go to recover; finalize runs after return, exit and abort, not after over and panic

### PRC-03 `expect` and `assert`
`expect condition, "message";` raises `AssertError`. D-010 gives a failed `expect` exit code 2
(error) and a failed `assert` exit code 3 (warning), but `assert` appears on no page. What is the
`assert` statement's syntax? Does a failed `assert` continue the process?
**Answer:** _(open)_
Status: open

### PRC-06 Recursive aspects
"The compiler will detect a recursive aspect and will fail at runtime." Compile-time error or
run-time failure?
**Answer:** _(open)_
Status: open

### PRC-07 Parallel groups
`name: parallel` … `fork` … `start aspect.process(args);` … `join name;` (D-043). Are group names
required (D-034: optional)? When one process in a group fails, are the others in the same group
stopped or awaited?
**Answer:** _(open)_
Status: partly answered by D-034 and D-043: the label is optional, a naked `join;` closes an unlabeled group; the failure of one process is open

### PRC-08 `raise` forms
Three forms: `raise $ExceptionType("message");` (a `$` type?), `raise (code, "message") if c;`,
and `raise "error" if c;` (control.html). Which are valid? Is an error code required?
**Answer:** _(open)_
Status: open

### PRC-09 The Exception module prototype
The pseudocode declares extension methods with a receiver, `method (@self:Error) .raise(…)`. That form is
valid (D-036: a typed `@self` is for extension methods outside the class). It also declares `class .Error`
twice. Keep this as an explicit "prototype, not valid Eve", or rewrite it as a module with
`class Error … end Error;`?
**Answer:** _(open)_
Status: open

### PRC-10 Process arguments from the command line
`process main(*args ()String)` here and `process main(*args: ()String)` with `eve:>start test.eve 1 2 3`
on concurrency.html (D-040: the parameters belong to the process). For the VM (`bin/eve.exe script.eve 1 2 3`):
are command-line arguments always strings, bound to the parameters of `main` by position? Can `main` declare
typed parameters (`process main(n: Integer)`) that the VM converts?
**Answer:** _(open)_
Status: open

### PRC-11 Locating aspects
"You do not import an aspect, but specify its relative path": `apply [folder/]aspect_one.run(args);`.
Relative to the driver file or to the working directory? File extension implied?
**Answer:** _(open)_
Status: open

### PRC-13 Local-scope block
`begin` is gone (D-043). It used to open a local-scope block before it started aspects. Is there still a
plain local-scope block, and with which keyword?
**Answer:** _(open)_
Status: open

### PRC-14 Aspect scope and members
D-043: an aspect hosts named processes, each with its own scope; only the driver has globals. Open points:
(1) what `.` public means in an aspect that has no shared scope (can the caller read a public member after
`apply`?); (2) can a process call a sibling process by its bare name (assumed yes); (3) are aspect-level
`let` variables initial values copied into each process (assumed yes); (4) does a process return an exit
code to its `apply` (TOP-10)?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### PRC-F1 Wrong content
- "The compiler … will fail at runtime" (see PRC-06).
- `process main(*args ()String)` missing `:`; `for arg in args loop;` extra `;`.
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

- `spec/semantics/control.md`: interruptions, recover, finalize, exit codes (PRC-02, 03, 08; D-020, D-038).
- `spec/semantics/topology.md`: aspects, `apply`, `start`, groups, recursion (PRC-06, 07, 11, 13, 14; D-042, D-043).
- `manual/usage.md`: command-line arguments (PRC-10).
