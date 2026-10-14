# io

Standard output and error: write, print and the log routines (LIB-03 to LIB-05).
Draft signatures. A declaration with the keyword external is implemented in Zig by the virtual machine.

## `external .write(*args: String, sep := " ", eol := False);`

Write the arguments at the current position of stdout. No separator is added after the last
argument and no new line unless eol is True.

## `external .print(*args: String, sep := " ");`

Write the arguments to stdout, separated by sep, then a new line.

## `external .read(@v: String, prompt := "");`

Read a value from stdin into v, after showing the prompt. Used as a statement: read(v, "name:").

## `external .error(message: String);`

Write an error message to stderr.

## `external .warning(message: String);`

Write a warning message to stderr.

## `external .log_err(message: String);`

Append an error message to the error log file, in the output folder $EVE_OUT ("out" by default).
For use in the recover region of a process.

## `external .log_wrn(message: String);`

Append a warning message to the warning log file, in the output folder $EVE_OUT ("out" by default).

