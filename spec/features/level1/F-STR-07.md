# F-STR-07 System variables

The register (`$error`, environment names such as `$HOME`, `$epsilon`, `$err_`/`$wrn_` constants).

*Done:* `$error`, `$epsilon`, `$OS_PWD`, the `$err_`/`$wrn_` constants and every environment name `$NAME` (a String, read when used) work; `$EVE_HOME`, `$EVE_LIB`, `$EVE_LIB_PATH`, `$EVE_CORE_DB` and `$EVE_OUT` are read-only Strings (the environment variable of the same name wins, then the default of the table), `$EVE_DIR` (the folder of the runtime) and `$EVE_ASP` (`asp`).

## Missing

Nothing.
