# System Variables

Status: **0.1-draft**. This file is the register of the system variables of Eve: every `$name` that the language or the library defines is listed here, with its type and meaning. **A new system variable is added here first**, then used in a page, a test or the VM (D-071). Answers TOP-08.

## Rules

- A system variable starts with the sigil `$`. It is static and public, shared by the whole process, and needs no module qualifier.
- **Environment.** Every OS environment variable `NAME` is visible as `$NAME` (D-031, D-052). It is a `String`.
- **Configuration.** A driver configuration file (`.cfg`) sets system variables as `$key = value` lines with Eve literals and `#` comments (D-031). A driver can also set one with `set $name = value;` (example: `$EVE_ASP`).
- **Library.** A library module declares the system variables it provides with `external set $name: Type;` (D-056), like `$error` in `evevm/lib/exception.eve`.
- **Naming.** Capital names (`$EVE_OUT`) are environment and configuration values; lowercase names (`$error`) are objects of the runtime and of the library. Error and warning codes are the constants `$err_name` and `$wrn_name`.

Status values in the tables: **0.1** the VM must provide it in version 0.1; **draft** described, version not decided; **later** after 0.1 (D-050 for multitasking); **question** see [Open points](#open-points). Column VM: what `bin/eve.exe` does today.

## Runtime objects

| Name | Type | Meaning | Status | VM | Source |
|---|---|---|---|---|---|
| `$error` | `Error` | The error being handled in `recover`: `.message`, `.code`, `.line`, `.job` (label of the failed job, D-030); also the error of an aspect at the `apply` line (D-072) | 0.1 | yes, no `.line` | D-054 |
| `$stack` | `()Call` | The calls that led to the error | draft | no | `lib/exception.eve` |
| `$trace` | `()Error` | The errors and warnings of the process | question | no | a database module may use it for SQL |
| `$result` | result type | The result of a function that declares no result name; a list when it has several results | draft | no | D-028 |
| `$object` | class | The current instance of a class | question | no | — |

## Environment and folders

| Name | Type | Meaning | Default | Status | VM | Source |
|---|---|---|---|---|---|---|
| `$NAME` | `String` | Any OS environment variable, for example `$PATH`, `$HOME` | from the OS | 0.1 | no | D-031, D-052 |
| `$EVE_DIR` | `String` | Folder of the Eve runtime | the folder of `eve.exe` | draft | no | — |
| `$EVE_HOME` | `String` | The home of a project: the folder that every relative path of an import is relative to (D-131) | the folder of the driver | draft | no | D-131 |
| `$EVE_LIB` | `String` | The `lib` folder of the project, its local library, searched by `from … use` | `lib`, relative to `$EVE_HOME` | 0.1 | no | D-131 |
| `$EVE_LIB_PATH` | `String` | The folders where external modules are installed, separated like the `PATH` of the operating system, for example `/eve/modules/<module_name>`; they may be in different folders, installed from GitHub with `npm install` | empty | draft | no | D-131 |
| `$EVE_ASP` | `String` | Folder of the aspects (and project libraries) of a driver | `asp`, then the project root, then `lib` | 0.1 | no | D-055 |
| `$EVE_OUT` | `String` | Output folder of the log files (`error`, `warning`) | `"out"` | 0.1 | no | D-057, `lib/io.eve` |
| `$MY_DIR` | `String` | Folder of the running driver | | draft | no | — |
| `$MY_LIB` | `String` | Library folder of the project | | question | no | — |
| `$MY_LOG` | `String` | Log folder of the project | | question | no | — |
| `$OS_PWD` | `String` | Current working folder | | question | no | — |
| `$CWD` | `String` | Current working folder | | question | no | — |

## Settings

| Name | Type | Meaning | Default | Status | VM | Source |
|---|---|---|---|---|---|---|
| `$epsilon` | `Real` | Precision of comparisons between real numbers | | draft | no | D-065 |
| `$timeout` | `Integer` | Seconds a task waits on a channel before a time-out error; an aspect may shadow it | `60` | later | no | CON-07, D-081 |
| `$cores` | `Integer` | Size of the worker pool of parallel aspects, at most 16 | number of hardware cores | later | no | D-047, D-081 |
| `$max_parallel` | `Integer` | Aspects one parallel group of the driver may start | `8` | later | no | D-081 |
| `$query` | `String` | The last SQL statement sent by the database module | | later | no | — |

## Constants

| Name | Type | Meaning | Status | VM | Source |
|---|---|---|---|---|---|
| `$err_name` | `Integer` | Error codes: `$err_panic` 1, `$err_expect` 2, `$err_assert` 3, `$err_raise` 4, `$err_index` 10 … `$err_recursion` 44 | 0.1 | codes only | D-054, `lib/exception.eve` |
| `$wrn_name` | `Integer` | Warning codes: `$wrn_deprecated` 5, `$wrn_truncate` 6, `$wrn_unused` 7 | 0.1 | codes only | D-054 |

## Not system variables

Names written with `$` in the pages that are not system variables. They stay out of the tables.

| Name | Where | What it is |
|---|---|---|
| `$user_path`, `$root_path`, `$path`, `$pro_home`, `$sys_con` | examples | examples of user-defined system variables or placeholders in syntax lines |
| `$evelib` | old examples | old spelling of `$EVE_LIB` |
| `$user`, `$password`, `$location` | examples | example configuration values of a database session |
| `$key` | notation | the notation of a configuration line, `$key = value` |
| `$Type`, `$ExceptionType` | D-055 | placeholder for an `$err_name` constant in `raise ($Type, "m")` |
| `$line` | examples | a shell variable inside a shell command string |

## Open points

Questions for the author; answers become decisions and update the tables.

1. **Working folder.** `$OS_PWD` and `$CWD` mean the same. Keep one, or use the OS variable `$PWD` (Linux) and drop both?
2. **Project folders.** `$MY_LIB` and `$MY_LOG` overlap with `$EVE_ASP` (aspects and project libraries) and `$EVE_OUT` (log files). Drop them?
3. **`$trace`.** One use is the list of errors and warnings; another is the generated SQL. One meaning only? Proposal: the errors list; the SQL goes to `$query`.
4. **`$object`.** Methods of a class use the parameter `@self`. Is `$object` still needed?
5. **Types of folders.** `String`, or a `Path`/`Folder` type from the library (an example uses `Folder($HOME/"test")`)?
6. ~~Writable or read-only.~~ Answered (D-109): a driver can set `$epsilon` and any other system variable, and can define its own `$name` variables.
