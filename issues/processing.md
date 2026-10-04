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
