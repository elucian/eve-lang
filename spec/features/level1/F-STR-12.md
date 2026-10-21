# F-STR-12 Exit code of the program

`over n;` and `exit n;` give the exit code: 0, or 6 to 125 (1 to 5 belong to the machine); anything else is `$err_argument` (`spec/semantics/errors.md#ending-the-process`).
