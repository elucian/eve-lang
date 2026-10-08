# Aspects

Status: **0.1-draft**, level 2 (a project of a driver and its aspects). Sources: D-066, D-072, D-090, D-112, D-113. Tests: `test/level2` (b01 to b09, b10 to b17 planned). Modules, imports and libraries are level 3; `parallel` and `start` are level 4.

## What an aspect is

An aspect is a script file that holds one process, `main`, and the declarations that `main` needs. A driver runs it with `apply` and waits. An aspect has the same shape as a driver (see `../syntax/declarations.md`, Scripts), with a mandatory kind word before `aspect`:

```eve
# sum: two inputs, one output
exclusive aspect sum is
  process main(a, b :Integer, @total :Integer) is
    let total := a + b;
  return;
end sum;
```

- **Kind word (D-090, D-130).** The kind word is optional: an aspect without it is `exclusive`. `exclusive aspect` runs alone, in serial mode, started by `apply`. `concurrent aspect` may also be started in a parallel group (level 4); at level 2 it is applied like the other kind, and the compiler check for thread safety is a level 4 rule. `aspect` alone is a compile error (exit 65).
- **One process, named `main`.** An aspect has exactly one process and its name is always `main`. A second process, or another name, is a compile error. `main` is implicit: it is not public.
- **Encapsulated.** Nothing in an aspect is public, and the dot operator is never applied to an aspect. Data goes in by the parameters of `main` and comes out by its `@` parameters.
- **File name.** The file is `<name>.eve` and the name in the header and in `end name;` is the same (D-018).

## Declarations of an aspect

An aspect declares, directly in its body and in any order (the declarations are hoisted): constants, variables, functions, procedures, then the process. Class declarations across files are level 3.

- **Aspect-level variables** are shared by `main` and by the functions and procedures of the same aspect, and by nobody else. They are not visible to the driver.
- **Functions and procedures** follow the rules of level 1 (`declarations.md`, Functions and procedures). They run serially on the core of their caller. A plain function is deterministic and changes nothing; a `!` function may differ for the same arguments; a procedure does work and may read and change the aspect-level variables (D-087).
- The aspect can't read a variable of the driver. The driver's variables reach the aspect only through arguments.

## `apply`

```ebnf
apply-stmt  = "apply" , { name , "/" } , name-path , "(" , [ arguments ] , ")" ;
argument    = [ name , ":" ] , [ "@" ] , expression
            | "*" , expression ;                           (* spread *)
```

`apply name(args);` runs `main` of the aspect `name` and the caller waits. The parentheses are written even when there is no argument. Only the `main` process of a driver may `apply`. An aspect that contains `apply` is a compile error, so aspects can't call one another, and recursion between aspects is impossible (D-066).

### Finding the aspect

`name` is the file name without the extension. The path may carry a folder: `apply folder/name()`. The search order is:

1. the folder written in the call, relative to the folder of the driver;
2. the aspect folder `asp/` of the project (`$EVE_ASP`, which the driver may set);
3. the project root (the folder of the driver).

An aspect that is not found is a compile error, exit 65, naming the folders that were searched. (Searching `lib/` is a level 3 rule.)

### Arguments

The arguments follow the rules of subprograms (D-028, D-105, D-106): by position, by name (`title: "B"`), with default values for optional parameters, and a mandatory parameter after optional ones is given by name. Rules checked **before the run** (exit 65):

- a missing mandatory argument, too many positional arguments, an unknown parameter name, a parameter given twice;
- an argument whose type does not fit the parameter;
- `@` on an argument whose parameter is not an `@` parameter, or an `@` parameter without `@` at the call.

**Spreading (Q-022 c).** `*list` in the argument list gives the elements of a list, one by one, as positional arguments: `apply add3(1, *xs);`. `*map` gives the pairs of a map as named arguments: the keys must be symbols (or strings) named like the parameters, `apply add3(a: 10, *m);` with `m := {'b': 20, 'c': 30}`. The elements are matched after the explicit arguments. An element that does not fit is the same error as a wrong explicit argument; for a spread that is known only at run time it is raised as an error when the call runs (the code is open, point 3).

### Results

The only way to get data back is an `@` parameter of `main`. `apply sum(2, 3, @t);` passes the variable `t` by reference: it is both input and output (D-106). The variable must exist; the aspect changes it with `let`. When `main` ends normally the driver sees the final value, also when `main` ended with `over;`.

## State per call

Each `apply` creates the state of the aspect, with its aspect-level declarations, and drops it when `main` returns or the call ends by an error. A second `apply` sees nothing of the first: `new calls = 0 :Integer;` at aspect level starts at 0 at every call. There is no `reset`, and no memory of the aspect between calls. Methods that an aspect attaches to a class (level 3) are part of this state and disappear with it (D-113).

## Errors across `apply`

| In the aspect | In the driver |
|---|---|
| an error with no `recover` in `main` | the aspect ends, `finalize` of the aspect runs, and the error is raised again at the `apply` line of the driver; the driver's `recover` reads it in `$error` |
| an error recovered in the aspect | the driver never sees it |
| `main` returns | code 0, the driver goes on after `apply` |
| `over;` | the aspect ends (its `finalize` runs); the driver goes on after `apply` |
| `panic;` | the whole application ends with exit code 1, memory is freed (no `recover`, no `finalize` of the driver) |
| `abort` in the `recover` of the aspect | passes the error on, as in the first row |

`over;` in the **driver** ends the program. `$error.code` and `$error.message` are those of the original error.

### Position and stack trace (D-113)

`$error.line` is the line of the original `raise` (or of the failed check), counted in the file of the aspect, not the line of `apply`. `$error.unit` is the name of the unit that holds that line (the aspect, or the function or procedure in it). `$error.trace` is a list of frames, innermost first; a frame has `unit`, `kind`, `line` and, for a block, `label`.

An error that nobody recovers is printed on the error output, the error first, then one line per frame, in order of call:

```
error 22: disk full
  line 5 in function load
  line 5 in aspect fail
  line 5 in job nightly
```

The frame of a function or procedure reads `line x in function y` or `line x in procedure y`; the aspect frame reads `line z in aspect name`; the hosting block (`job`, `parallel`, a labelled loop) reads `in job label`, `in parallel label`, `in loop label`. The exit code is the code of the error (`errors.md`).

## Log files (D-114)

`log_err(text)` and `log_wrn(text)` write the run log, in the output folder `$EVE_OUT` (default `out/`): one file per date, `run-log-<date>.json` (`<date>` is `YYYY-MM-DD`, in UTC, as is `time`), for errors and warnings together. The file is a JSON array with one object per run; a new run is appended at the end. A run that writes nothing adds nothing.

```json
[
  {"run": 1, "time": "14:30:05", "script": "b09_log_files",
   "messages": [
     {"type": "warning", "line": 4, "unit": "b09_log_files", "level": 0, "message": "low memory"},
     {"type": "error", "line": 7, "unit": "b09_log_files", "level": 0, "message": "disk full"}
   ]}
]
```

`type` is `"error"` for `log_err` and `"warning"` for `log_wrn`. `line` and `unit` are those of the call (as in the trace above); `level` is the depth in the stack of calls, 0 for `main`. The file is meant for a tool that makes an HTML report (not written yet).

## Not in level 2

Modules, `from … use`, libraries and the library search path (level 3); `parallel`, `start`, `done`, channels and the thread-safety check of `concurrent` (level 4); the machine and its commands (level 6).

## Open points

1. The meaning of `level` in a log message (call depth) is proposed, to confirm.
2. Names `$error.unit` and `$error.trace` are proposed here from D-113 and must be added to `variables.md` when the author confirms them.
3. The error code of a spread that doesn't fit at run time is not in the register of error codes (D-109): to add.
4. The search order puts the folder of the call before `asp/`; D-112 only fixes `asp/` as the default folder.
