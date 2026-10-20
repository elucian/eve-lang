# Issues: command

Page: `tutorial/command.html`. How to answer: [README](README.md). Triage of 2026-10-20: CMD-02, CMD-03 and CMD-06 are closed by `os.run!` and the `fs` module (ledger in the README). Two questions are left, with a **Suggestion** each; a suggestion is not a decision.

## Questions

### CMD-04 `export`
"You can export Eve shared variables to the operating system using `export`." `export` is a keyword, but of the modules (`export (LIMIT, tick);`, `spec/semantics/modules.md`), not of the shell. How does a script give variables to a program it starts?

**Suggestion (2026-10-20):** no shell `export` statement. A program gets variables as an argument: add an `env` map to `os.run!` (`os.run!(command, args, cwd, env)`), logged as library gap G-10. The tutorial sentence is then removed.

**Answer:** _(open)_

Status: open

### CMD-05 Working directory variable
`$CWD`, `$HOME` on this page; `$OS_PWD`, `$MY_DIR` in `spec/semantics/variables.md`, where `$OS_PWD` and `$CWD` are both marked "question" (open point 1 there).

**Suggestion (2026-10-20):** keep `$OS_PWD`, drop `$CWD`. The names then follow the families already in the table: `$EVE_*` for the runtime and the project, `$MY_*` for the running aspect, `$OS_*` for the system. It is read-only; a program runs in another folder through the `cwd` argument of `os.run!`, not by changing a global (this is also the answer to the closed CMD-03).

**Answer:** _(open)_

Status: open
