# The module `os`

Status: **draft**, level 6 ( (a), (b)). Feature: F-LIB-07. Native module (Zig), signatures in `lib/sys/os.eve`. Registry: [registry.md](registry.md).

The safe way to run another program and to read the environment. `call` (the shell statement of the language, level 3) stays; `os.run!` is the form for programs whose arguments are built from data: **no shell is involved**, so a space, a quote or `&` in an argument is just text.

| Function | Result | Meaning |
|---|---|---|
| `run!(command: String, args: List, cwd: String)`, `run!(command, args, cwd, timeout_ms: Integer)`, `run!(command, args, cwd, timeout_ms, env: Map)` | `ProcessResult` | start `command` with the arguments of the list (each element a `String`), in `cwd` (`""` = here), wait for its end, and give its status and both outputs; the standard input of the child is closed. With `timeout_ms` above 0 the child is killed when it runs longer: the status is 124 and `err` says `Time-out after N ms`. `env` is a map of `String` to `String` that is **added** to the environment of this program for the child (a name that is already set is replaced); there is no shell `export` statement (CMD-04; test `f16_os_env`) |
| `env!(name: String, default: String)` | `String` | the value of an environment variable, or `default` when it is not set |
| `hostname!()` | `String` | the name of this computer |
| `pid!()` | `Integer` | the process id of this machine |
| `platform()` | `String` | `"windows"`, `"linux"` or `"macos"` (constant for a machine) |

`ProcessResult` has the fields `status: Integer` (the exit code; 127 when the program can not be started), `out: String` and `err: String` (standard output and standard error, as text).

A program that does not start (not found, no right) gives `status` 127 and the reason in `err`; it is not an error of the language, because a script often wants to test it. An unreadable argument (not a `String`) is `$err_argument`. Permission to run programs is checked by the door of the registry design (`design-libraries.md` §10 (4)); at level 6 it allows everything.
