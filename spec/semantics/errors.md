# Errors, Recovery and Exit Codes

Status: **draft**, level 1. The codes are settled.

## Errors

An **error** is a record `{code, message, job, line}`. It is created by `raise expr;`, by a failed `expect` (code 2), by a failed `assert` (code 3) and by the run-time checks of the language. Every run-time check of the language has its own error class and its own code, so a code always names one precise error: index 0 or out of range `$err_index` 10, a missing DataMap key `$err_key` 11, division or remainder by zero `$err_divide` 12, integer overflow `$err_overflow` 13. `raise "text";` has the generic code 4 `$err_raise`. The full table of codes is in [Error codes](#error-codes). An undefined name and an operand of the wrong type are compile errors, never error values: Eve analyzes the whole script before it runs. A compile error is not an error value: the script does not run.

`raise "text";` creates an error with code 4 and that message. Functions and procedures do not handle errors; an error propagates out of them to the process that called them.

## Process

An error raised anywhere in a process (also inside a job or a called function or procedure) makes the process jump to its `recover` region, unless a function, procedure or method on the way has a `recover` of its own and handles it first (below). A process without `recover` aborts on every error.

### `recover`

`recover` sits at the end of the process, aligned with `process`, before `finalize` and `return;`. Its statements are normal statements; `$error` is available: `$error.message`, `$error.code`, `$error.job` (a string; empty outside a job). After a parallel group or a job with tasks (level 4) also `$error.errors`, the list of the errors of the tasks in the order of `start` or `spawn`, and `$error.cancelled` (`multitasking.md#errors`). It ends in one of:

| Statement | Effect |
|---|---|
| `retry;` | run the failed job again, from its declarations |
| `retry after <duration>;` | wait, then run the failed job again (level 5): `retry after 2s if $error.transient and $error.attempt < 5;` |
| `resume;` | the error is handled, the job stays failed, the process continues after its `done` |
| `abort;` | end the process, run `finalize`, pass the error to the caller |
| end of `recover` | the error is handled and the process ends normally; `finalize` runs |

`$error.attempt` (level 5) is the number of the run of the failed job: 1 for the first run, 2 after one retry. `$error.transient` is `True` for the errors that a new try can cure (a lost connection, a deadlock, a time-out). **Fatal errors:** `retry` and `resume` are refused for a `MappingError` and for a `CommitError`: the process aborts with exit code 4 (`../library/database.md#errors`). When a job fails, the database layer has rolled back its transaction before `recover` runs; the records in memory keep their values and are detached (`../library/database.md#transactions`). `$error.failed` (a `BatchError`) is the collection of the failing records `{key, reason}` of a batch. A job that ends by `rollback;` is not an error: `recover` does not run.

`retry` and `resume` need a failed job: an error outside a job can only be aborted or handled by reaching the end of `recover`. An error raised inside `recover` aborts with that error. A `retry` that always fails is a user error: the compiler does not limit retries.

### `recover` in a function, procedure or method

Level 2. A function, a procedure and a method can have a `recover` region, written like the one of a process: aligned with the keyword, at the end, before `return;`.

```eve
function half(n: Integer) => (@result: Integer) is
  let result := 100 / n;
recover
  print "recovered: {$error.message}";
  let result := -1;
return;
```

- **When it runs.** An error raised in the body, or in anything the body calls and does not handle, makes the routine jump to its `recover`. `$error` is available as in a process. The variables and the parameters of the routine, `@self` of a method and the result variables are in scope.
- **End of `recover`: the error is handled** and the routine **returns normally**. A function gives its result variables as they are at that moment: the value that `recover` or the body set, or the zero value of the type (`0`, `""`, `False`, empty collections). Nothing else changes for the caller; it never sees the error.
- **`abort;`** passes the same error to the caller, which may handle it in its own `recover` (the routine's `defer`s run first).
- **An error raised in `recover`** is the error that goes to the caller; the first error is dropped.
- **`retry` and `resume`** need a failed job (see above): in the `recover` of a routine they are a run-time error with the message `retry and resume need a failed job: a <function|procedure|method> can only handle the error or abort`.
- **`defer`** blocks of the routine run after `recover`, on every way out.
- **A `recover` does not change the kind of the routine:** a function with `recover` is still deterministic when its body is, and a safe module function stays safe. The handled error is counted in the report of the machine like any handled error.
- **Not allowed:** a **constructor**, a **generator** and a **lambda** have no `recover` (compile error, exit 65). A routine of a trait that is only a signature has none. `finalize` is not offered: `defer` does that work in a routine (a process keeps `finalize`).
- **Where it helps:** a library function that must turn a failure into a value (`rpc.dispatch` answers `-32603`), a module function that logs and goes on, a method that refuses an operation and says why.

 Grammar: `../syntax/grammar.md#procedures-functions-and-methods`.

### `finalize`

`finalize` runs once when the process ends by `return`, `over;`, `exit` in the process itself, by the end of `recover` or by `abort`: a clean way out never skips the cleanup. It does not run after `panic;` or after an unexpected stop.

## Ending the process

The exit code of a process is a small number, 0 to 5. It is not the code of an error: `$error.code` and the `$err_` constants identify the error and are never exit codes.

| Cause | Exit code | `recover` | `finalize` |
|---|---|---|---|
| end of process, `return;`, `exit;` in the process | 0 | no | yes |
| `over;` | 0 | no | yes |
| `over n;`, `exit n;` | `n` | no | yes |
| `panic;` | 1 | no, ends the whole application | no |
| failed `expect`, not recovered (or `abort`) | 2 | yes | yes |
| failed `assert`, not recovered (or `abort`) | 3 | yes | yes |
| `raise` or run-time error, not recovered (or `abort`) | 4 | yes | yes |
| unexpected stop: the user stops the program (Ctrl+C), the program is halted, a `halt` breakpoint ended with Ctrl+C or `stop`, a hard time-out or another outage, recursion too deep, out of memory | 5 | no | no |
| end of `recover` | 0 | | yes |

**A code of your own.** `over n;` and `exit n;` (G-2) store `n` as the exit code of the program; `n` is an `Integer` that is 0 or from 6 to 125, so it never clashes with the codes 1 to 5 of the machine (above) and stays below the 126 and up that shells reserve. Any other value is a run-time error (`$err_argument`). The last code stored before the program ends is used, unless an unrecovered error or `panic` ends it first: those codes (1 to 4) win.

`abort` ends with the exit code of the error it passes on (2, 3 or 4). `panic` is not an error: it ends the whole application at once. When several codes apply, the first one reached wins. The error codes are `$err_` constants in the standard library: `$err_panic` 1, `$err_expect` 2, `$err_assert` 3, `$err_raise` 4; warnings have `$wrn_` constants. Messages of the VM go to the error output; `print` and `write` go to the standard output. The command-line errors of the VM (64, 65, 66, 70) are not exit codes of a process.

## Where an error is reported

An error is reported as `file:line: error code: message`, followed by the calls that led to it, innermost first. The file is the one that holds the line: an error raised in a function of a module names the file of the module, and the call lines of a module routine end with `of <file>`; a routine of the main script has no suffix (G-1).

## Error classes

Every error code of the language has a class, and all of them are below `Error`: `IndexError` (10), `KeyError` (11), `DivideError` (12), `OverflowError` (13), `ConvertError` (14), `ParseError` (15), `NullError` (16), `ArgumentError` (17), `FileError` (20), `AccessError` (21), `IoError` (22), `ModuleError` (30), `ProcessError` (31), `MemoryError` (40), `TimeoutError` (41), `DeadlockError` (42), `OutputError` (43), `RecursionError` (44), `ParallelError` (45), `ChannelError` (46), `DatabaseError` (50), `ConnectionError` (51), `ConstraintError` (52), `ConflictError` (53), `MappingError` (54), `CommitError` (55), `FormatError` (56), `HttpError` (57), `BatchError` (58) and `SqlError` (59, below `DatabaseError`); the codes 1 to 3 have `Panic`, `ExpectError` and `AssertError`, and code 4 (`raise` without a code) is `Error` itself. The names are known in every script.

`recover` is one region: it has no list of classes. The statements inside it look at the error with `is` or with `match`; `$error is Error` is true for every error:

```eve
recover
  if $error is FormatError do
    print "bad file: {$error.message}";
  else if $error is DatabaseError do
    print "database: {$error.code}";
  else
    abort;
  done;
```

`match $error when FormatError do … when other do … done;` does the same: a class as the pattern of a `when` tests the class of the object, as `is` does. An error raised with an object of the program's own class (`raise Failure(code: 21, message: "bad")`) has that class in `$error`, not the class of its code.

`Error(code, message)` makes an error object to raise with a standard code, `raise Error(17, "bad argument");`; the other classes are made with a message, `raise DivideError("text");` (their code is the code of the class), and named arguments add fields: `raise Error(code: 20, message: "text", detail: "disk");`. Without a message the message is the name of the class.

**Codes.** The codes below 1000 are reserved for the compiler and the standard library: 1 to 9 belong to the statements of the language and 10 to 999 to the machine and the library; the table of [Error codes](#error-codes) lists them. A program uses 1000 and above, for the errors it defines itself.

`error_type(code)` gives the class of a code, or `null` when the language has no class for it (a code of the program): `error_type($err_format) == FormatError`. The program does not end with the code of an error class: it raises an error, and `over n;` ends it with a code of its own (see above).

### Errors of a program

A program defines its own errors as classes below `Error`. The class gives its code, a whole number from 1000 up, as a member with a value, and it may have fields of its own; a class below such a class keeps the code of its parent.

```eve
class Failure = {code: 1001, detail: String} <: Error;
class DiskFailure = {device: String} <: Failure;

raise Failure(message: "no space", detail: "disk");
raise DiskFailure(message: "full", device: "D:");

recover
  if $error is Failure do
    print "{$error.code} {$error.message} {$error.detail}";
  done;
```

The object has the fields `code` and `message` of every error (the message is the argument `message:`, empty without one) and its own fields, which `recover` reads from `$error`. `$error is Failure` is true for the class and for the classes below it, and `$error is Error` for every error. The unrecovered error ends the process with the exit code 4: a class has no exit code of its own, and `over n;` is the way to end with a code of your own.

The compiler checks the codes before the program runs (exit 65):

| Rule | Message holds |
|---|---|
| a class below `Error` has a code of its own or of a parent of the program | `needs a code` |
| the code of a class below `Error` is 1000 or more | `is reserved` |
| a number written in `raise (code, text)` or in `Error(code, text)` is a standard code (the table below) or the code of a class of the program | `is not an error code` |

A code that is not written as a number, such as a constant `$err_file` or a variable, is not checked by the compiler. The codes of the language are a closed list: the program does not add to them below 1000.

### Expect and assert

`expect cond;` and `assert cond;` raise `ExpectError` (code 2) and `AssertError` (code 3) when the condition is false. A message may follow the condition, with `else` or with a comma, and it is the message of the error:

```eve
expect balance >= 0 else "the balance is negative";
assert items.count() > 0, "the list is empty";
```

Without a message the error says `expect failed` or `assertion failed`.

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
| `$err_deadlock` | 42 | `Deadlock: {task} waits to {send to | receive from} {channel}`, one per waiting task |
| `$err_output` | 43 | `Output {name} is given to two tasks of the group` |
| `$err_recursion` | 44 | recursion too deep |
| `$err_parallel` | 45 | `{n} of {m} tasks failed` (level 4: a parallel group or a job with tasks; the items are in `$error.errors`, `multitasking.md#errors`) |
| `$err_channel` | 46 | `Channel {name} is closed` (level 4) |
| `$err_database` | 50 | `Database error {sqlstate} on {table}: {reason}` (level 5, `DatabaseError`) |
| `$err_connection` | 51 | `Cannot reach {host}: {reason}` (`ConnectionError`, transient) |
| `$err_constraint` | 52 | `Constraint {constraint} violated by {key}` (`ConstraintError`) |
| `$err_conflict` | 53 | `Row {key} was changed by someone else (version {version})` (`ConflictError`) |
| `$err_mapping` | 54 | `Mapping of {table} does not match the database: {differences}` (`MappingError`, fatal, exit code 4) |
| `$err_commit` | 55 | `Cannot tell if transaction {transaction} was committed` (`CommitError`, fatal) |
| `$err_format` | 56 | `Bad {format} at line {line}, column {column}: {reason}` (`FormatError`, data files) |
| `$err_http` | 57 | `HTTP {status} from {url}` (`HttpError`) |
| `$err_batch` | 58 | `{count} records of batch {batch} failed` (`BatchError`; the records are in `$error.failed`) |
| `$err_sql` | 59 | `SQL function {name} failed: {reason}` (`SqlError` <: `DatabaseError`: an error or a `NULL` for a non-nullable parameter in a `sql function`; the query stops, `../library/database.md#sql-functions`) |

Warnings do not stop the process; `warn(code, message)` reports one on the standard error as `unit:line: warning code: message` and the process goes on.

| Constant | Code | Message |
|---|---|---|
| `$wrn_assert` | 3 | `assert` failed, reported as a warning |
| `$wrn_deprecated` | 5 | `{name} is deprecated, use {other}` |
| `$wrn_truncate` | 6 | `Value {value} truncated to {type}` |
| `$wrn_unused` | 7 | `{name} is declared but never used` |
| `$wrn_hidden` | 8 | `The name {name} of {module} is hidden by {other}: the first import wins` |

### Warnings of the compiler

A warning of the compiler is written on the error output before the program runs, as `file:line:column: warning $wrn_name: message`, and does not change the exit code. Every warning has a constant `$wrn_name` with a code, so a tool can count and filter them. The list grows with the features; a new warning takes the next code and a row here. Proposed names for the next ones are in the table of the open points.

| Constant | Raised when | Test |
|---|---|---|
| `$wrn_hidden` | two imports merged by `use (*)` or `use (m(*))` give the same name; the second stays hidden ([modules.md](modules.md#import)) | c18, c44 |

## Open points

Names proposed for the warnings of the compiler, not yet raised (each needs a feature entry and a test first): `$wrn_unused` for an import, a variable or a parameter never used (code 7, exists as a constant); `$wrn_shadow` for a name that hides one of an outer scope; `$wrn_unreachable` for a statement after `return` or `abort`; `$wrn_deprecated` for a use of a library member marked deprecated (code 5); `$wrn_precision` for a `Real` converted to a `Decimal` or the other way in an assignment; `$wrn_implicit_null` for a variable read before it is assigned.

`raise` with a code and the Exception module (PRC-08, PRC-09).

### Error objects with fields

`raise` of an object (`raise Failure(code: 21, message: "bad", detail: "disk");`) makes the error with the `code` and the `message` of the object (`$err_raise`, 4, when it has no code). In `recover` the fields of the object are read from `$error` as well: `$error.detail` is `"disk"`. The fields `code`, `message`, `job` and `line` keep the values of the error. An error that is not recovered prints its message and exits with code 4.

