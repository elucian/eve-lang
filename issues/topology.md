# Issues: topology.html

Page: `tutorial/topology.html` (597 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### TOP-08 Built-in system variables for 0.1
The pages name `$EVE_DIR`, `$EVE_LIB`, `$MY_DIR`, `$MY_LIB`, `$MY_LOG`, `$OS_PWD`, `$error`,
`$stack`, `$trace`, `$object`, `$result`, and user ones like `$user_path`. "System constants are
capitalized". Which system variables must the VM provide in 0.1, with which types? Are OS
environment variables visible as `$NAME`?
**Answer:** Yes, environment variables are visible as $NAME. 
Status: partly done → D-031, D-052: environment variables are `$NAME` (applied); the 0.1 variable list and their types are open

### TOP-10 Aspect result and error code
An aspect "must handle its own errors, it can't raise errors; unhandled errors make the program panic".
D-043: an aspect hosts named processes (no `main`); `apply aspect.process(args);` waits, outputs travel in
`@` parameters. Does a process also return an exit code to the driver, or only the `@` outputs?
**Answer:** Because processes are now sequential, they can propagate errors. So a process can raise errors. Driver capture the exit code from panic, raise, expect and assert.
Status: done → D-052: a process can raise errors; the driver captures the exit code of panic, raise, expect and assert

## Improvements (applied only if you write "yes")

### TOP-I2 Move the REPL to command.html
The REPL and daemon sections describe the tool, not the language. Move them to command.html (or
the manual's `usage.md`), and keep topology.html about projects, scripts, regions and modules.
**Answer:** agree, move thid to /manual folder in this repository, from the tutorial.
Status: done → D-052: REPL and daemon text moved to `manual/usage.md`; topology.html keeps a pointer

## Spec additions once answered

- `spec/semantics/topology.md`: projects, scripts, modules, imports, execution (D-031, D-043).
- `spec/syntax/regions.md`: one scope per script, no regions (D-041); declarations and constants (D-031).
- `spec/semantics/scopes.md`: system variables (TOP-08), scopes of driver, aspect and module (D-043).
- `manual/usage.md`: VM modes and options (D-031).
