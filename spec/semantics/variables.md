# System Variables

Status: **draft**. This file is the register of the system variables of Eve: every `$name` that the language or the library defines is listed here, with its type and meaning. **A new system variable is added here first**, then used in a page, a test or the VM. Answers TOP-08.

## Rules

- A system variable starts with the sigil `$`. It is static and public, shared by the whole process, and needs no module qualifier.
- **Environment.** Every OS environment variable `NAME` is visible as `$NAME`. It is a `String`.
- **Configuration.** A configuration file (`.cfg`), given to a run with `-e file.cfg` or `--setup file.cfg` or loaded by the REPL command `setup file.cfg`, sets system variables as `$key = value` lines. A value is an Integer, a Real (`2.5`), a Logic (`True`, `False`) or a String in double quotes (a backslash escapes a quote, a backslash, `n` or `t`); a line may end with a `#` comment, and a line that starts with `#` or is blank is ignored. The variables are read-only in the script. A file that is missing (exit 66) or has a bad line (exit 65, the message names the file and the line) stops the run before it starts. The machine files `eve.cfg` and `evedb.cfg` have another format (`key = value`, see the machine page). That aspect can also set one with `set $name = value;` (example: `$EVE_ASP`).
- **Library.** A library module declares the system variables it provides with `external set $name: Type;`, like `$error` in `code/evevm/lib/exception.eve`.
- **Naming.** Capital names (`$EVE_OUT`) are environment and configuration values; lowercase names (`$error`) are objects of the runtime and of the library. Error and warning codes are the constants `$err_name` and `$wrn_name`.

Status values in the tables: **0.1** (the first release) the VM must provide it from level 1; **draft** described, level not decided; **later** after level 1 ( for multitasking); **question** see [Open points](#open-points). Column VM: what `bin/eve.exe` does today.

## Runtime objects

| Name | Type | Meaning | Status | VM | Source |
|---|---|---|---|---|---|
| `$error` | `Error` | The error being handled in `recover`: `.message`, `.code`, `.line`, `.job` (label of the failed job); also the error of an aspect at the `apply` line | 0.1 | yes, no `.line` | |
| `$stack` | `()Call` | The calls that led to the error | draft | no | `lib/exception.eve` |
| `$trace` | `()Error` | The errors and warnings of the process | question | no | a database module may use it for SQL |
| `$result` | result type | The result of a function that declares no result name; a list when it has several results | draft | no | |
| `$object` | class | The current instance of a class | question | no | — |

## Environment and folders

| Name | Type | Meaning | Default | Status | VM | Source |
|---|---|---|---|---|---|---|
| `$NAME` | `String` | Any OS environment variable, for example `$PATH`, `$HOME` | from the OS | 0.1 | no | |
| `$EVE_DIR` | `String` | Folder of the Eve runtime | the folder of `eve.exe` | 0.1 | no | test a116 |
| `$EVE_HOME` | `String` | The home of a project: the folder that every relative path of an import is relative to | the folder of the aspect run by the command | draft | no | |
| `$EVE_LIB` | `String` | The `lib` folder of the project, its local library, searched by `from … use` | `lib`, relative to `$EVE_HOME` | 0.1 | no | |
| `$EVE_LIB_PATH` | `String` | The folders where external modules are installed, separated like the `PATH` of the operating system, for example `/eve/modules/<module_name>`; they may be in different folders, installed from GitHub with `npm install` | empty | draft | no | |
| `$EVE_ASP` | `String` | Folder of the aspects (and project libraries) of a project | `asp`, then the project root, then `lib` (the value is `asp`; the search order is in aspects.md) | 0.1 | no | test a116 |
| `$EVE_CORE_DB` | `String` | The core database of the project: a SQLite file in its `db/` folder with the logs of the ETL runs, the checkpoints, the metadata and the data of the Eve UX (never ETL data); the name is set in `eve.cfg` (key `core_db`) | `db/local.db`, relative to `$EVE_HOME` | draft | no | |
| `$EVE_OUT` | `String` | Output folder of the log files (`error`, `warning`) | `"out"` | 0.1 | no |, `lib/io.eve` |
| `$MY_DIR` | `String` | Folder of the running aspect | | draft | no | — |
| `$MY_LIB` | `String` | Library folder of the project | | question | no | — |
| `$MY_LOG` | `String` | Log folder of the project | | question | no | — |
| `$OS_PWD` | `String` | Current working folder of the program, read-only; a program started with `os.run!` runs in another folder through its `cwd` argument, not by changing this value | | 0.1 | yes |, CMD-05, test a93 |

## Settings

| Name | Type | Meaning | Default | Status | VM | Source |
|---|---|---|---|---|---|---|
| `$epsilon` | `Real` | Precision of comparisons between real numbers | | draft | no | |
| `$timeout` | `Integer` | Seconds a task waits on a channel before a time-out error; an aspect may shadow it | `60` | later | no | CON-07 |
| `$cores` | `Integer` | Size of the worker pool of parallel aspects, at most 16 | number of hardware cores | later | no | |
| `$max_parallel` | `Integer` | Aspects one parallel group of a primary aspect may start | `8` | later | no | |
| `$query` | `String` | The last SQL statement sent by the database module | | later | no | — |
| `$isolation` | `String` | Isolation of the transactions of a job: `"read committed"`, `"repeatable read"`, `"serializable"`, `"snapshot"`; set in the declarations of a job | the default of the database | draft | no | |
| `$lock_timeout` | `Duration` | How long a statement waits for a lock before a transient `TimeoutError`; set in a job | `5s` | draft | no | |
| `$read_only` | `Logic` | A job opens read-only transactions: one consistent snapshot, no locks where the database allows | `False` | draft | no | |
| `$trace` | `Logic` | In debug mode prints every SQL statement with its parameters (secrets masked) and its duration | `False` | draft | no | — |

## Constants

| Name | Type | Meaning | Status | VM | Source |
|---|---|---|---|---|---|
| `$err_name` | `Integer` | Error codes: `$err_panic` 1, `$err_expect` 2, `$err_assert` 3, `$err_raise` 4, `$err_index` 10 … `$err_recursion` 44 | 0.1 | codes only |, `lib/exception.eve` |
| `$wrn_name` | `Integer` | Warning codes: `$wrn_deprecated` 5, `$wrn_truncate` 6, `$wrn_unused` 7 | 0.1 | codes only | |

## Not system variables

Names written with `$` in the pages that are not system variables. They stay out of the tables.

| Name | Where | What it is |
|---|---|---|
| `$user_path`, `$root_path`, `$path`, `$pro_home`, `$sys_con` | examples | examples of user-defined system variables or placeholders in syntax lines |
| `$evelib` | old examples | old spelling of `$EVE_LIB` |
| `$user`, `$password`, `$location` | examples | example configuration values of a database session |
| `$key` | notation | the notation of a configuration line, `$key = value` |
| `$Type`, `$ExceptionType` | | placeholder for an `$err_name` constant in `raise ($Type, "m")` |
| `$line` | examples | a shell variable inside a shell command string |

## Optimization level

The optimization level of a run is a whole number from 0 to 10. Higher levels spend more time compiling and less time running: a low level suits a small, quick script, a high level a large project that runs for a long time on a server. The implicit level is 1, the lowest.

| Source | Rule |
|---|---|
| `-O n` on the command line (`--optimization n`) | the level; it has priority over the configuration file |
| `optimization = n` in `eve.cfg` | the level when the command line does not give one |
| the script | can not set it: `$optimization` is read only |

A value that is not a whole number from 0 to 10 is a usage error (exit 64). The script reads the level as `$optimization`, an `Integer`, and the level decides what the machine does with the meta database (`lib/meta/`, the tables that the script needs are loaded in memory at levels 5 to 10; below 5 they are read from the file when used). The loading rules are in the library pages when they are built.

## Open points

Questions for the author; answers become decisions and update the tables.

1. ~~**Working folder.**~~ Settled: `$OS_PWD` stays, `$CWD` is dropped.
2. **Project folders.** `$MY_LIB` and `$MY_LOG` overlap with `$EVE_ASP` (aspects and project libraries) and `$EVE_OUT` (log files). Drop them?
3. **`$trace`.** One use is the list of errors and warnings; another is the generated SQL. One meaning only? Proposal: the errors list; the SQL goes to `$query`.
4. **`$object`.** Methods of a class use the parameter `@self`. Is `$object` still needed?
5. **Types of folders.** `String`, or a `Path`/`Folder` type from the library (an example uses `Folder($HOME/"test")`)?
6. ~~Writable or read-only.~~ Answered: a primary aspect can set `$epsilon` and any other system variable, and can define its own `$name` variables.
