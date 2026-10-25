# F-TLS-08 Formatter and linter

`eve fmt`, `eve lint`.

*Done:* `eve fmt [--check]` writes the layout of scripts (trailing white space, blank lines, line endings, the end of the file; idempotent on every file of the test folders) and `eve lint` reports unused variables, parameters, loop variables and imports, as specified in [tools.md](../../semantics/tools.md) (tests d46, d47).

## Missing

Nothing for the first version. A language server is not part of level 4.
