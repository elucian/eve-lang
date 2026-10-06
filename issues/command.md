# Issues: command.html

Page: `tutorial/command.html` (163 lines). Reviewed 2026-09-28; CMD-F1 applied 2026-10-06. How to answer: [README](README.md).

## Questions

### CMD-02 Exit status of a shell command
`call "ls -l *.dat" +> files;` captures stdout as a list of lines. How does the script read the command's exit code (`$status`?), and does a non-zero code raise an error?
**Answer:** _(open)_
Status: open

### CMD-03 `cd` and the working directory
`call "cd #($HOME)/test";` then `call "ls …"`. Each `call` normally runs in its own shell, so the `cd` would be lost. Does `call "cd …"` change the VM's working directory (`$CWD`)?
**Answer:** _(open)_
Status: open

### CMD-04 `export`
"You can export Eve shared variables to the operating system using `export`." Is `export` a keyword (it is not in the keyword table)? Syntax?
**Answer:** _(open)_
Status: open

### CMD-05 Working directory variable
This page: `$CWD`, `$HOME`. topology.html: `$OS_PWD`, `$MY_DIR`. Which names? Conflict still open: `spec/semantics/variables.md` lists both `$OS_PWD` and `$CWD` as "question"; keep one, or use the OS variable `$PWD`.
**Answer:** _(open)_
Status: open

### CMD-06 `File` and `Folder` classes
"These classes are not yet designed." Are they part of 0.1, or planned for level 3?
**Answer:** _(open)_
Status: open

## Spec additions once answered

- `spec/semantics/`: shell commands, `call`, exit status (CMD-02..04, D-025).
- `spec/library/builtins.json`: `File`, `Folder` if in 0.1 (CMD-06).
