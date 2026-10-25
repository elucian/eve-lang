# F-LNG-15 Typed exceptions

Error classes with fields, `recover` by type, exit-code mapping.

*State:* `$error` with code, message, line and job, the codes `$err_*`, exit codes 1 to 4; an object of a class raised with `raise` gives its code and message, and its fields are read from `$error` in `recover` (`errors.md#error-objects-with-fields`, tests e161). `exception.eve` is a draft that the VM does not load.

## Missing

- `recover` by type: the syntax is not decided yet.
- Mapping of a class to an exit code: the policy is not decided yet.
- `exception.eve` is not loaded.
