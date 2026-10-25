# F-LIB-02 Exception module

`Error`, `Warning`, `raise`, `expect`, `assert`, `warn`, code constants.

*Partial:* `raise`, `expect`, `assert`, `$error` and the `$err_` constants are built in (`builtins.md`); there is no library file for them.

## Missing

- Built: the classes `Error` and the others with their constructors (`Error(9, "text")`), `raise (code, message)` and `warn(code, message)` (tests c61, c62).
- `expect` and `assert` with a custom message: the syntax is not decided yet.
