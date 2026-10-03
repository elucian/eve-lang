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
**Answer:** abord do not run finalize. return is happening alwais with code 0, = expect error code is 2, assert error code is 3. raise will create error code 4 by default if not specified by error object, exception object has form {code:x, message:y} so code is the exit code and the exception code.
Status: done (tutorial) → D-055: abort skips finalize; table of interruptions and exit codes on the page; spec pending

### PRC-03 `expect` and `assert`
`expect condition, "message";` raises `AssertError`. D-010 gives a failed `expect` exit code 2
(error) and a failed `assert` exit code 3 (warning), but `assert` appears on no page. What is the
`assert` statement's syntax? Does a failed `assert` continue the process?
**Answer:** Yes, failed assert generate warning message and try to continue the process. expect create an exception. Later, the program may crash but at least we have some warnings that can help us decide why program crash unexpectedly. 
Status: done (tutorial) → D-055: failed assert warns and continues, expect raises

### PRC-06 Recursive aspects
"The compiler will detect a recursive aspect and will fail at runtime." Compile-time error or
run-time failure?
**Answer:** The text is wrong. Processes can't be recursive but methods can be recursive. Now processes can be apply, aspects can't be run or executed only the processes inside can be executed.
Status: done (tutorial) → D-055: processes are not recursive, methods can be; an aspect is not executed, its processes are

### PRC-07 Parallel groups
`name: parallel` … `do` … `start method(args);` … `done name;` (D-043, D-046, D-047). Are group names
required (D-034: optional)? When one process in a group fails, are the others in the same group
stopped or awaited? 
**Answer:** only one parallel group can be executed one time, because waiting is happening automaticly at the end of parallel block. When one thread fail, the other will continue. When all done or some with errors, the synchronization done will fail and trigger the recover region or finalize region if no recover region is present.
Status: done (tutorial) → D-055: one group at a time, the others go on, `done` waits then raises; details in CON-11

### PRC-08 `raise` forms
Three forms: `raise ExceptionType("message");` (a `$` type?), `raise (code, "message") if c;`,
and `raise "error" if c;` (control.html). Which are valid? Is an error code required?
**Answer:** error code is 4 by default, all forms are valid. even raise {code:23, message:"error"} is allowed because exception is and object. $ExceptionType is a constant exception code but ExceptionType is a constructor, it will create an exception. raise is a method that is overloaded.
Status: done (tutorial) → D-055: all forms valid, default code 4

### PRC-09 The Exception module prototype
The pseudocode declares extension methods with a receiver, `method (@self:Error) .raise(…)`. That form is
valid (D-036: a typed `@self` is for extension methods outside the class). It also declares `class .Error`
twice. Keep this as an explicit "prototype, not valid Eve", or rewrite it as a module with
`class Error … end Error;`?
**Answer:** Rewrite, tune the standard library to allow Error class function properly.
Status: done (tutorial) → D-055: class Error rewritten on exceptions.html; `evevm/lib` module still to write

### PRC-10 Process arguments from the command line
`process main(*args ()String)` here and `process main(*args: ()String)` with `eve:>start test.eve 1 2 3`
on concurrency.html (D-040: the parameters belong to the process). For the VM (`bin/eve.exe script.eve 1 2 3`):
are command-line arguments always strings, bound to the parameters of `main` by position? Can `main` declare
typed parameters (`process main(n: Integer)`) that the VM converts?
**Answer:** yes, parameter name will be supported using -p if parameter is short and --param if parameter name is  long. In comments above main, the convention will say ** @param x: "description of parameter" so if a command is issued: run test.eve -h it will display the help automaticly generated from comments or if no comments are provided will just list the parameters. Parameters can be any eve literal, they will be parsed and converted to data.
Status: partly done → D-055: documented in the tutorial; the VM and `manual/usage.md` still to do

### PRC-11 Locating aspects
"You do not import an aspect, but specify its relative path": `apply [folder/]aspect_one.run(args);`.
Relative to the driver file or to the working directory? File extension implied?
**Answer:** Good question. We should import aspects but not using import, that will search in lib folder, $EVE_LIB, let's create like "lib" default aspect path "asp", if a project do not have "asp" or "lib" folder, aspects and libraries are located in root folder of project. So aspects can be specified with folder in front, if folder is not present the aspect will be located in root first then in lib folder. We can specify $EVE_ASP in the driver: set $EVE_ASP to specific value. This will be also used to search the library. 
Status: done (tutorial) → D-055: `asp` folder, root, `lib`; `$EVE_ASP`

### PRC-13 Local-scope block
`begin` is gone (D-043). It used to open a local-scope block before it started aspects. Is there still a
plain local-scope block, and with which keyword?
**Answer:** The aspect scope exist is implicit singleton scope of the aspect, after the imports statements, after the constants we declare variables then methods then processes, but the order do not matter, once we implement hoisting. 
Status: done (tutorial) → D-055: implicit singleton scope, hoisting

### PRC-14 Aspect scope and members
D-043: an aspect hosts named processes, each with its own scope; only the driver has globals. Open points:
(1) what `.` public means in an aspect that has no shared scope (can the caller read a public member after
`apply`?); (2) can a process call a sibling process by its bare name (assumed yes); (3) are aspect-level
`let` variables initial values copied into each process (assumed yes); (4) does a process return an exit
code to its `apply` (TOP-10)?
**Answer:** Aspect is a singletone. Once initialized using Apply, a scope exist and is not destroy automaticly. We create a new keyword to free up the aspect from memory; reset aspect_name; and reset all; These are self explanatory. Two ways to clear memory for one or all aspects.
Status: done (tutorial) → D-055: singleton aspect, `reset name;` and `reset all;`. Replaced by D-066: no public
members, one process `main`, state created by each `apply` and dropped at return, `reset` removed.

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
