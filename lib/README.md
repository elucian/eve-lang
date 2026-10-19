# Eve standard library

The library of the Eve virtual machine (D-053). Most of it is written in Eve; only the primitives that need
the machine (input and output, memory, the operating system) are native. A declaration with the keyword
`external` in front (`external function print(...)`) keeps only the signature: the virtual machine, written in Zig,
provides the body. The compiler creates the external library; the signature is all we keep here.

| Module | Contents | Status |
|---|---|---|
| [`sys/io.eve`](sys/io.eve) | `write`, `print`, `read`, `error`, `warning`, `log_err`, `log_wrn` | draft signatures |
| [`sys/exception.eve`](sys/exception.eve) | `Error`, `Warning`, `raise`, `expect`, `assert`, `warn`, the constants `$err_name` and `$wrn_name` | draft |

## Rules

- One module per file; the file name is the module name (topology.html, Modules).
- A member is public only if the module lists it in `export (…)` (D-085; the prefix `.` is gone). Everything else is private. A native member is written `external function name(…) => (…);` with no body (D-056).
- Every public member has a comment block right above its signature, lines starting with `**`.
  The first comment lines of the file, above the `module` header, are the summary of the module.
- The documentation is generated from these comments and the signatures, never written twice:
  see [`doc/`](doc/README.md).

## Output

`write` and `print` send text to stdout. `write` adds no new line by default; `print` adds one (LIB-04).
`error` and `warning` send text to stderr. `log_err` and `log_wrn` do not print: they write to log files in the
output folder, `out` by default, or the folder in the system variable `$EVE_OUT`. When a driver ends with an unhandled error, the machine writes the
last error to stderr: with the call stack in debug mode, only the message otherwise (LIB-05).

## Documentation

Run `zig build doc` in `comp/evevm/`: it runs `eve --doc lib doc` (D-082), which reads `lib/*.eve`
and writes one Markdown page for each module into `doc/`. The generator is the `doc` command of `eve` (source `comp/evecp/src/doc.zig`).
