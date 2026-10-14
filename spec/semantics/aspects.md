# Aspects

Status: **0.1-draft**, level 2 (a project of a primary aspect and the aspects it calls). Sources: D-066, D-072, D-090, D-112, D-113, D-179 to D-182. Tests: `test/level2` (b01 to b09, b10 to b17 planned). Modules, imports and libraries are level 3; `parallel` and `start` are level 4.

## What an aspect is

An aspect is a script file that holds a process `main`, its entry point, the other processes it needs (private), and the declarations of them all. An aspect is the one kind of script that runs; the word `driver` is not a keyword (D-179). The header has a kind word before `aspect` (see `../syntax/declarations.md`, Scripts):

```eve
# sum: two inputs, one output
exclusive aspect sum is
  process main(a, b :Integer, @total :Integer) is
    let total := a + b;
  return;
end sum;
```

- **Kind word (D-090, D-130, D-181).** `exclusive`, `concurrent` and `primary` are reserved words of the same design. The kind word is optional: an aspect without it is `exclusive`. An `exclusive aspect` runs alone, in serial mode, called with `apply`; `start` of it is a compile error. A `concurrent aspect` is called with `apply` or with `start` in a parallel group (level 4); at level 2 it is applied like the other kind, and the thread-safety check is a level 4 rule. A `primary aspect` is designed to be executed first, by a command; **no aspect applies or starts it** (compile error `a primary aspect is run by a command: it can't be applied or started`); it is serial.
- **The entry point (D-179).** Every aspect has a process `main`; an aspect without one is a compile error that lists its processes. `main` is the only public process: it is the process that `apply name(args)` and `start name(args)` run, and the process that a command runs.
- **Private processes.** Every other process of an aspect is private. Only the processes of the same aspect call it, by its bare name: `apply prepare(10);` inside the aspect. A private process works on the state of the call of its aspect. It is applied in an exclusive or primary aspect, and applied or started in a concurrent aspect; a started private process uses only the thread-safe names of its aspect (`../syntax/declarations.md#scripts`, `multitasking.md`). A call of a private process is not a call of an aspect and never makes a level.
- **Encapsulated.** The dot operator is never applied to an aspect: `worker.ingest(…)` is a compile error. Data goes in by the parameters of `main` and comes out by its `@` parameters.
- **Run by a command (D-182).** `eve file.eve` runs the `main` of a primary aspect, or of an exclusive aspect for testing; the arguments after the file go to the parameters of `main`. A command does not run a concurrent aspect, and only a primary or an exclusive aspect calls one (D-183). The aspect run by a command is the root of the run.
- **File name.** The file is `<name>.eve` and the name in the header and in `end name;` is the same (D-018).

## Declarations of an aspect

An aspect declares, directly in its body and in any order (the declarations are hoisted): constants, variables, functions, procedures, then the process. Class declarations across files are level 3.

- **Aspect-level variables** are shared by the processes and by the functions and procedures of the same aspect, and by nobody else. They are not visible to the aspect that calls it.
- **Functions and procedures** follow the rules of level 1 (`declarations.md`, Functions and procedures). They run serially on the core of their caller. A plain function is deterministic and changes nothing; a `!` function may differ for the same arguments; a procedure does work and may read and change the aspect-level variables (D-087).
- The aspect can't read a variable of the aspect that calls it. The variables of the caller reach the aspect only through arguments.

## `apply`

```ebnf
apply-stmt  = "apply" , { name , "/" } , name-path , "(" , [ arguments ] , ")" ;
argument    = [ name , ":" ] , [ "@" ] , expression
            | "*" , expression ;                           (* spread *)
```

`apply name(args);` runs `main` of the aspect `name` and the caller waits. The parentheses are written even when there is no argument. Any aspect may `apply` another aspect (D-179, D-180), with three limits, compile errors with exit 65: an aspect does not call itself and no chain of calls comes back to an aspect already in it, so recursion between aspects is impossible (the message prints the chain: `a calls b calls a`); the chain is at most three levels deep (the aspect run by a command, an aspect it calls, an aspect called from there, which calls no other aspect); a primary aspect is never the target. Only the call of an aspect makes a level; `apply prepare(…)` of a private process does not.

### Finding the aspect

`name` is the file name without the extension. The path may carry a folder: `apply folder/name()`. The search order is:

0. in an Eve macro, the aspects declared in the file itself (level 5, D-152, `../syntax/declarations.md#eve-macro-level-5`);
1. the folder written in the call, relative to the folder of the project;
2. the aspect folder `asp/` of the project (`$EVE_ASP`, which the primary aspect may set);
3. the project root (the folder of the primary aspect).

An aspect that is not found is a compile error, exit 65, naming the folders that were searched. (Searching `lib/` is a level 3 rule.)

### Arguments

The arguments follow the rules of subprograms (D-028, D-105, D-106): by position, by name (`title: "B"`), with default values for optional parameters, and a mandatory parameter after optional ones is given by name. Rules checked **before the run** (exit 65):

- a missing mandatory argument, too many positional arguments, an unknown parameter name, a parameter given twice;
- an argument whose type does not fit the parameter;
- `@` on an argument whose parameter is not an `@` parameter, or an `@` parameter without `@` at the call.

**Spreading (Q-022 c).** `*list` in the argument list gives the elements of a list, one by one, as positional arguments: `apply add3(1, *xs);`. `*map` gives the pairs of a map as named arguments: the keys must be symbols (or strings) named like the parameters, `apply add3(a: 10, *m);` with `m := {'b': 20, 'c': 30}`. The elements are matched after the explicit arguments. An element that does not fit is the same error as a wrong explicit argument; for a spread that is known only at run time it is raised as an error when the call runs (the code is open, point 3).

### Results

The only way to get data back is an `@` parameter of `main`. `apply sum(2, 3, @t);` passes the variable `t` by reference: it is both input and output (D-106). The variable must exist; the aspect changes it with `let`. When `main` ends normally the caller sees the final value, also when `main` ended with `over;`.

## State per call

Each `apply` of an aspect creates the state of the aspect, with its aspect-level declarations, and drops it when `main` returns or the call ends by an error. A second `apply` sees nothing of the first: `new calls = 0 :Integer;` at aspect level starts at 0 at every call. There is no `reset`, and no memory of the aspect between calls. The private processes called during one call share that state. Methods that an aspect attaches to a class (level 3) are part of this state and disappear with it (D-113).

## Errors across `apply`

| In the aspect | In the caller |
|---|---|
| an error with no `recover` in `main` | the aspect ends, `finalize` of the aspect runs, and the error is raised again at the `apply` line of the caller; the `recover` of the caller reads it in `$error` |
| an error recovered in the aspect | the caller never sees it |
| `main` returns | code 0, the caller goes on after `apply` |
| `over;` | the aspect ends (its `finalize` runs); the caller goes on after `apply` |
| `panic;` | the whole application ends with exit code 1, memory is freed (no `recover`, no `finalize` of the caller) |
| `abort` in the `recover` of the aspect | passes the error on, as in the first row |

`over;` in the aspect run by a command ends the program. `$error.code` and `$error.message` are those of the original error.

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

## Compile errors of the calls (D-179 to D-183)

All are reported before the run, exit 65.

| Mistake | Message | Test |
|---|---|---|
| a file starts with `#!` | `a file has no #! line: Eve has no free scripts` | a04 |
| `apply` or `start` of a primary aspect | `a primary aspect is run by a command: it can't be applied or started` | b45, e109 |
| a chain of calls comes back to an aspect | `ping calls pong calls ping` | b47 |
| an aspect applies itself | `again calls itself` | b48 |
| a fourth level of aspects | `{chain} is more than three levels deep` | b49 |
| the dot on an aspect | `the dot is never applied to an aspect` | b52 |
| an aspect without `main` is called | `{name} has no process main` | b53 |
| `from lib use (x)` where `x` is an aspect | `'x' is an aspect: an aspect can't be imported` | c24 |
| a concurrent aspect run by a command or called from a concurrent aspect | `a concurrent aspect is called from a primary or an exclusive aspect` | d39, d40 |

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
