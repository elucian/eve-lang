# Errors, Recovery and Exit Codes

Status: **0.1-draft**, level 1. Sources: D-010, D-020, D-038, D-054, D-063, D-096. Rules marked *(proposed)* wait for the author (D-054).

## Errors

An **error** is a record `{code, message, job, line}`. It is created by `raise expr;`, by a failed `expect` (code 2), by a failed `assert` (code 3, Q-031h) and by the run-time checks of the language. The checks that raise an error with code 4 (Q-031g): index 0 or out of range, a missing DataMap key, division or remainder by zero, an undefined name, an operand of the wrong type, integer overflow. A compile error is not an error value: the script does not run.

`raise "text";` creates an error with code 4 and that message. Functions and procedures do not handle errors; an error propagates out of them to the process that called them (D-028).

## Process

An error raised anywhere in a process (also inside a job or a called function or procedure) makes the process jump to its `recover` region. A process without `recover` aborts on every error.

### `recover`

`recover` sits at the end of the process, aligned with `process`, before `finalize` and `return;`. Its statements are normal statements; `$error` is available: `$error.message`, `$error.code`, `$error.job` (a string; empty outside a job). It ends in one of:

| Statement | Effect |
|---|---|
| `retry;` | run the failed job again, from its declarations |
| `resume;` | the error is handled, the job stays failed, the process continues after its `done` |
| `abort;` | end the process, run `finalize`, pass the error to the caller |
| end of `recover` | the error is handled and the process ends normally; `finalize` runs |

`retry` and `resume` need a failed job: an error outside a job can only be aborted or handled by reaching the end of `recover`. An error raised inside `recover` aborts with that error. A `retry` that always fails is a user error: the compiler does not limit retries.

### `finalize`

`finalize` runs once when the process ends by `return`, by `exit`, by the end of `recover` or by `abort`. It does not run after `over;` or `panic;`.

## Ending the process

| Cause | Exit code | `recover` | `finalize` |
|---|---|---|---|
| end of process, `return;`, `exit;` | 0 | no | yes |
| `over;` | 0 | no | no |
| `panic;` | 1 | no | no |
| failed `expect` (no `recover`, or `abort`) | 2 | yes | on abort |
| failed `assert` (no `recover`, or `abort`) | 3 | yes | on abort |
| unhandled error | the code of the error | yes | on abort |
| end of `recover` | 0 | | yes |

`panic` is not an error: it ends the whole application at once. When several codes apply, the first one reached wins. The codes are `$err_` constants in the standard library: `$err_panic` 1, `$err_expect` 2, `$err_assert` 3, `$err_raise` 4 (D-054, Q-031h); warnings have `$wrn_` constants. Messages of the VM go to the error output; `print` and `write` go to the standard output.

## Open points

The code of `exit`; the codes above 4 (D-054); `raise` with a code and the Exception module (PRC-08, PRC-09).
