# F-LNG-15 Typed exceptions

Error classes with fields, `recover` by type, exit-code mapping.

*Done:* `$error` with code, message, line and job, the codes `$err_*` and the exit codes 1 to 4; a class for every code, tested with `is` and `match` inside the one `recover` region (`$error is FormatError`), `error_type(code)`, the constructors `Error(code, message)` and `DivideError(message)`, an object of a class of the program raised with `raise` keeps its class and its fields in `$error` (errors.md#error-classes, tests c61, c62, e161). `recover` has no class list and a class has no exit code: the program raises, and `over n;` ends it with a code of its own.

## Missing

Nothing.
