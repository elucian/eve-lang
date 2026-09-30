# Issues: command.html

Page: `tutorial/command.html` (163 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### CMD-01 `call` is the shell command
This page and syntax.html define `call` as running a shell command. types.html and functions.html
also use `call` for routines (see CON-01). Confirm that `call` is only for shell commands.
**Answer:** Yes, `call` is only for shell commands; the `call` before methods was removed (D-025).
Status: answered (D-025)

### CMD-02 Exit status of a shell command
`call "ls -l *.dat" +> files;` captures stdout as a list of lines. How does the script read the
command's exit code (`$status`?), and does a non-zero code raise an error?
**Answer:** _(open)_
Status: open

### CMD-03 `cd` and the working directory
`call "cd #($HOME)/test";` then `call "ls …"`. Each `call` normally runs in its own shell, so the
`cd` would be lost. Does `call "cd …"` change the VM's working directory (`$CWD`)?
**Answer:** _(open)_
Status: open

### CMD-04 `export`
"You can export Eve shared variables to the operating system using `export`." Is `export` a
keyword (it is not in the keyword table)? Syntax?
**Answer:** _(open)_
Status: open

### CMD-05 Working directory variable
This page: `$CWD`, `$HOME`. topology.html: `$OS_PWD`, `$MY_DIR`. Which names? (See TOP-08.)
**Answer:** _(open)_
Status: open

### CMD-06 `File` and `Folder` classes
"These classes are not yet designed." Are they part of 0.1, or planned for level 3?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### CMD-F1 Wrong content
- `new file: String:` and `new file: File:` end in `:` → `;`.
- "This new keyword is also a EVE CLI command".
- Typos: rigts, automaticly, demostrate, "we simple create".
**Answer:** _(open)_

## Spec additions once answered

- `spec/semantics/`: shell commands, `call`, exit status (CMD-01..04).
- `spec/library/builtins.json`: `File`, `Folder` if in 0.1 (CMD-06).
