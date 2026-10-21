# F-STR-07 System variables

The register (`$error`, environment names such as `$HOME`, `$epsilon`, `$err_`/`$wrn_` constants).

*Partial:* `$error`, `$epsilon`, `$OS_PWD`, the `$err_`/`$wrn_` constants and every environment name `$NAME` (a String, read when used) work; `$EVE_*` are undefined.

## Missing

- `$EVE_HOME`, `$EVE_LIB`, `$EVE_LIB_PATH`, `$EVE_CORE_DB` are undefined names in a script.
- One test per `$EVE_*` variable.
