# System Variables

Status: **0.1-draft**. This file is the register of the system variables of Eve: every `$name` that the tutorial,
the decisions or the library use is listed here, with its type and meaning. **A new system variable is added
here first**, then used in a page, a test or the VM (D-071). Answers TOP-08.

## Rules

- A system variable starts with the sigil `$`. It is static and public, shared by the whole process, and needs
  no module qualifier (topology.html, syntax.html).
- **Environment.** Every OS environment variable `NAME` is visible as `$NAME` (D-031, D-052). It is a `String`.
- **Configuration.** A driver configuration file (`.cfg`) sets system variables as `$key = value` lines with Eve
  literals and `#` comments (D-031). A driver can also set one with `set $name = value;` (example: `$EVE_ASP`).
- **Library.** A library module declares the system variables it provides with `external set $name: Type;`
  (D-056), like `$error` in `evevm/lib/exception.eve`.
- **Naming.** Capital names (`$EVE_OUT`) are environment and configuration values; lowercase names (`$error`) are
  objects of the runtime and of the library. Error and warning codes are the constants `$err_name` and `$wrn_name`.

Status values in the tables: **0.1** the VM must provide it in version 0.1; **draft** described, version not
decided; **later** after 0.1 (D-050 for multitasking); **question** see [Open points](#open-points).
Column VM: what `bin/eve.exe` does today.

## Runtime objects

| Name | Type | Meaning | Status | VM | Source |
|---|---|---|---|---|---|
| `$error` | `Error` | The error being handled in `recover`: `.message`, `.code`, `.job` (label of the failed job, D-030) | 0.1 | yes | D-054, exceptions.html, control.html |
| `$stack` | `()Call` | The calls that led to the error | draft | no | exceptions.html, `lib/exception.eve` |
| `$trace` | `()Error` | The errors and warnings of the process | question | no | exceptions.html; databases.html uses it for SQL |
| `$result` | result type | The result of a function that declares no result name; a list when it has several results | draft | no | D-028, syntax.html, functions.html |
| `$object` | class | The current instance of a class | question | no | syntax.html |

## Environment and folders

| Name | Type | Meaning | Default | Status | VM | Source |
|---|---|---|---|---|---|---|
| `$NAME` | `String` | Any OS environment variable, for example `$PATH`, `$HOME` | from the OS | 0.1 | no | D-031, D-052, topology.html |
| `$EVE_DIR` | `String` | Folder of the Eve runtime | the folder of `eve.exe` | draft | no | topology.html |
| `$EVE_LIB` | `String` | Folder of the installed libraries, searched by `from … use` | `$EVE_DIR/lib` | 0.1 | no | topology.html, modules.html |
| `$EVE_ASP` | `String` | Folder of the aspects (and project libraries) of a driver | `asp`, then the project root, then `lib` | 0.1 | no | D-055, processing.html |
| `$EVE_OUT` | `String` | Output folder of the log files (`error`, `warning`) | `"out"` | 0.1 | no | D-057, topology.html, `lib/io.eve` |
| `$MY_DIR` | `String` | Folder of the running driver | | draft | no | topology.html |
| `$MY_LIB` | `String` | Library folder of the project | | question | no | topology.html |
| `$MY_LOG` | `String` | Log folder of the project | | question | no | topology.html |
| `$OS_PWD` | `String` | Current working folder | | question | no | topology.html |
| `$CWD` | `String` | Current working folder | | question | no | command.html |

## Settings

| Name | Type | Meaning | Default | Status | VM | Source |
|---|---|---|---|---|---|---|
| `$epsilon` | `Real` | Precision of comparisons between real numbers | | draft | no | algorithms.html, compiler.html, D-065 |
| `$timeout` | `Integer` | Seconds a task waits on a channel before a time-out error | `60` | later | no | CON-07, multitasking.html |
| `$cores` | `Integer` | Size of the worker pool of parallel aspects | number of hardware cores | later | no | D-047, multitasking.html |
| `$query` | `String` | The last SQL statement sent by the database module | | later | no | databases.html |

## Constants

| Name | Type | Meaning | Status | VM | Source |
|---|---|---|---|---|---|
| `$err_name` | `Integer` | Error codes: `$err_panic` 1, `$err_expect` 2, `$err_raise` 4, `$err_index` 10 … `$err_output` 43 | 0.1 (codes proposed) | codes only | D-054, exceptions.html, `lib/exception.eve` |
| `$wrn_name` | `Integer` | Warning codes: `$wrn_assert` 3, `$wrn_deprecated` 5, `$wrn_truncate` 6, `$wrn_unused` 7 | 0.1 (codes proposed) | codes only | D-054, exceptions.html |

## Not system variables

Names written with `$` in the pages that are not system variables. They stay out of the tables.

| Name | Where | What it is |
|---|---|---|
| `$user_path`, `$root_path`, `$path`, `$pro_home`, `$sys_con` | modules.html, topology.html | examples of user-defined system variables or placeholders in syntax lines |
| `$evelib` | databases.html | old spelling of `$EVE_LIB` (fix the page) |
| `$user`, `$password`, `$location` | databases.html | example configuration values of a database session |
| `$key` | topology.html | the notation of a configuration line, `$key = value` |
| `$Type`, `$ExceptionType` | processing.html, D-055 | placeholder for an `$err_name` constant in `raise ($Type, "m")` |
| `$line` | command.html | a shell variable inside a shell command string |

## Open points

Questions for the author; answers become decisions and update the tables.

1. **Working folder.** `$OS_PWD` (topology.html) and `$CWD` (command.html) mean the same. Keep one, or use the OS
   variable `$PWD` (Linux) and drop both?
2. **Project folders.** `$MY_LIB` and `$MY_LOG` overlap with `$EVE_ASP` (aspects and project libraries) and
   `$EVE_OUT` (log files). Drop them?
3. **`$trace`.** exceptions.html: the list of errors and warnings; databases.html: shows the generated SQL. One
   meaning only? Proposal: the errors list; the SQL goes to `$query`.
4. **`$object`.** Methods of a class use the parameter `@self` (classes.html). Is `$object` still needed?
5. **Types of folders.** `String`, or a `Path`/`Folder` type from the library (command.html uses `Folder($HOME/"test")`)?
6. **Writable or read-only.** Which variables may a driver change with `set` (`$EVE_ASP`, `$EVE_OUT`, `$epsilon`)?
   Can a driver create its own `$name`, as the examples with `$user_path` suggest?
