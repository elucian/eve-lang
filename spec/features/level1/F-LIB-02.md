# F-LIB-02 Exception module

`Error`, `Warning`, `raise`, `expect`, `assert`, `warn`, code constants.

*Partial:* `raise`, `expect`, `assert`, `$error` and the `$err_` constants are built in (`builtins.md`); there is no library file for them.

## Missing

- The classes `Error` and `Warning` with their constructors (`Error(9, "text")` is an undefined name), the function `warn` and `raise(code, message)`: they belong to typed exceptions (F-LNG-15).
- `expect` and `assert` with a custom message.
