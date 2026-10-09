# Errors, Recovery and Exit Codes

Status: **0.1-draft**, level 1. Sources: D-010, D-020, D-038, D-054, D-063, D-081, D-096. The codes are settled (D-109).

## Errors

An **error** is a record `{code, message, job, line}`. It is created by `raise expr;`, by a failed `expect` (code 2), by a failed `assert` (code 3, Q-031h) and by the run-time checks of the language. Every run-time check of the language has its own error class and its own code, so a code always names one precise error (D-109): index 0 or out of range `$err_index` 10, a missing DataMap key `$err_key` 11, division or remainder by zero `$err_divide` 12, integer overflow `$err_overflow` 13. `raise "text";` has the generic code 4 `$err_raise`. The full table of codes is in [Error codes](#error-codes). An undefined name and an operand of the wrong type are compile errors, never error values: Eve analyzes the whole script before it runs (D-109, D-110). A compile error is not an error value: the script does not run.

`raise "text";` creates an error with code 4 and that message. Functions and procedures do not handle errors; an error propagates out of them to the process that called them (D-028).

## Process

An error raised anywhere in a process (also inside a job or a called function or procedure) makes the process jump to its `recover` region. A process without `recover` aborts on every error.

### `recover`

`recover` sits at the end of the process, aligned with `process`, before `finalize` and `return;`. Its statements are normal statements; `$error` is available: `$error.message`, `$error.code`, `$error.job` (a string; empty outside a job). After a parallel group or a job with tasks (level 4) also `$error.errors`, the list of the errors of the tasks in the order of `start` or `spawn`, and `$error.cancelled` (`multitasking.md#errors`, D-140). It ends in one of:

| Statement | Effect |
|---|---|
| `retry;` | run the failed job again, from its declarations |
| `resume;` | the error is handled, the job stays failed, the process continues after its `done` |
| `abort;` | end the process, run `finalize`, pass the error to the caller |
| end of `recover` | the error is handled and the process ends normally; `finalize` runs |

`retry` and `resume` need a failed job: an error outside a job can only be aborted or handled by reaching the end of `recover`. An error raised inside `recover` aborts with that error. A `retry` that always fails is a user error: the compiler does not limit retries.

### `finalize`

`finalize` runs once when the process ends by `return`, `over;`, `exit` in the process itself, by the end of `recover` or by `abort`: a clean way out never skips the cleanup. It does not run after `panic;` or after an unexpected stop (D-081).

## Ending the process

The exit code of a process is a small number, 0 to 5. It is not the code of an error: `$error.code` and the `$err_` constants identify the error and are never exit codes (D-081).

| Cause | Exit code | `recover` | `finalize` |
|---|---|---|---|
| end of process, `return;`, `exit;` in the process | 0 | no | yes |
| `over;` | 0 | no | yes |
| `panic;` | 1 | no, ends the whole application | no |
| failed `expect`, not recovered (or `abort`) | 2 | yes | yes |
| failed `assert`, not recovered (or `abort`) | 3 | yes | yes |
| `raise` or run-time error, not recovered (or `abort`) | 4 | yes | yes |
| unexpected stop: the user stops the program (Ctrl+C), the program is halted, a `halt` breakpoint ended with Ctrl+C or `stop`, a hard time-out or another outage, recursion too deep, out of memory | 5 | no | no |
| end of `recover` | 0 | | yes |

`abort` ends with the exit code of the error it passes on (2, 3 or 4). `panic` is not an error: it ends the whole application at once. When several codes apply, the first one reached wins. The error codes are `$err_` constants in the standard library: `$err_panic` 1, `$err_expect` 2, `$err_assert` 3, `$err_raise` 4 (D-054, D-109, Q-031h); warnings have `$wrn_` constants. Messages of the VM go to the error output; `print` and `write` go to the standard output. The command-line errors of the VM (64, 65, 66, 70) are not exit codes of a process.

## Error codes

The constants are declared by the Exception module of the standard library. The message pattern fills the `{…}` fields with the values of the error. Codes 1 to 4 are also the exit codes of an unrecovered error (see above); the other codes are never exit codes.

| Constant | Code | Message |
|---|---|---|
| `$err_panic` | 1 | the message given to `panic` |
| `$err_expect` | 2 | `Unexpected error in line {line}`, or the custom message |
| `$err_assert` | 3 | `Assertion failed in line {line}`, or the custom message |
| `$err_raise` | 4 | `raise` without a code: the message given to `raise` |
| `$err_index` | 10 | `Index {index} is out of range {first}..{last}` |
| `$err_key` | 11 | `Key {key} not found` |
| `$err_divide` | 12 | `Division by zero` |
| `$err_overflow` | 13 | `Overflow in {operation}` |
| `$err_convert` | 14 | `Cannot convert {value} to {type}` |
| `$err_parse` | 15 | `Cannot parse {text} as {type}` |
| `$err_null` | 16 | `Null value used as {type}` |
| `$err_argument` | 17 | `Invalid argument {name}: {reason}` |
| `$err_file` | 20 | `File not found: {path}` |
| `$err_access` | 21 | `Access denied: {path}` |
| `$err_io` | 22 | `Input/output error on {path}: {reason}` |
| `$err_module` | 30 | `Module {name} not found in {library}` |
| `$err_process` | 31 | `Process {name} not found in aspect {aspect}` |
| `$err_memory` | 40 | `Out of memory while allocating {size}` |
| `$err_timeout` | 41 | `Time-out after {time}` |
| `$err_deadlock` | 42 | `Deadlock: {task} waits to {send to | receive from} {channel}`, one per waiting task (D-141) |
| `$err_output` | 43 | `Output {name} is given to two tasks of the group` |
| `$err_recursion` | 44 | recursion too deep |
| `$err_parallel` | 45 | `{n} of {m} tasks failed` (level 4: a parallel group or a job with tasks; the items are in `$error.errors`, `multitasking.md#errors`) |
| `$err_channel` | 46 | `Channel {name} is closed` (level 4, D-141) |

Warnings do not stop the process; `.warn(code, message)` reports them.

| Constant | Code | Message |
|---|---|---|
| `$wrn_assert` | 3 | `assert` failed, reported as a warning |
| `$wrn_deprecated` | 5 | `{name} is deprecated, use {other}` |
| `$wrn_truncate` | 6 | `Value {value} truncated to {type}` |
| `$wrn_unused` | 7 | `{name} is declared but never used` |

## Open points

`raise` with a code and the Exception module (PRC-08, PRC-09).
