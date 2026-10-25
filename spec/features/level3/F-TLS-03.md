# F-TLS-03 Interactive interpreter

Evaluate Eve statements and expressions typed at the prompt, keep the session scope (`semantics/repl.md#prompt-lines`, test c60).

*State:* statements and expressions run in one session scope; `print` at the prompt is the Eve statement; the checks of a line are the run-time checks.

## Missing

- The static checks of a line before it runs.
