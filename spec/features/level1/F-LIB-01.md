# F-LIB-01 Console I/O

`print`, `write`, `read`, `error`, `warning`, `log_err`, `log_wrn`.

*Partial:* `print`, `write`, `log_err` and `log_wrn` (run log), `error` and `warning` (standard error) work; `read(@v, prompt)` reads a line (end of input: `$err_io`); `io.eve` is a draft.

## Missing

- `read` at the end of input: the error `$err_io` stands in until the author decides on an end-of-input value.
- `lib/sys/io.eve` is a draft the VM does not load: load it, or remove it and state in the library page that the names are built in.
