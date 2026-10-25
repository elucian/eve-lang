# Built-in names

Status: **draft**, level 1. Features: F-LIB-01, F-LIB-02.

These names need no import and no library file: the virtual machine provides them. A later version may write some of them in a library module that the machine loads on its own; the names and the rules below do not change when that happens.

## Output, input and logs

| Name | Form | Meaning |
|---|---|---|
| `print` | statement `print a, b, sep: " ";` | write the arguments separated by `sep`, then a new line ([statements.md](../syntax/statements.md#calls)) |
| `write` | statement | the same, with no new line |
| `read` | function `read(prompt)` | write the optional prompt, read one line of the standard input and give it as a `String` without its line end; `null` at the end of the input |
| `error` | function `error(text)` | write a line on the standard error and go on |
| `warning` | function `warning(text)` | the same, for a warning |
| `warn` | function `warn(code, message)` | write `unit:line: warning code: message` on the standard error and go on ([errors.md](../semantics/errors.md#error-classes)) |
| `error_type` | function `error_type(code)` | the class of an error code (`FormatError` for 56), `null` when the language has none |
| `log_err` | function `log_err(text)` | add an error line to the run log of the process (`recover` region) |
| `log_wrn` | function `log_wrn(text)` | the same, for a warning |

`read` gives `String?`: `new line := read("name: "); if line == null …`. The tests give the standard input; without one it is empty, so `read` gives `null` at once.

## Errors

`raise`, `expect` and `assert` are statements ([errors.md](../semantics/errors.md)). The error of the process is `$error` (fields `code`, `message`, `line`, `job`); the codes are the constants `$err_name` and `$wrn_name` of [errors.md](../semantics/errors.md#error-codes). Error classes with fields, `recover` by type and a function `warn` belong to typed exceptions and are not part of the built-in names yet.
