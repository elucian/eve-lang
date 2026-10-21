# F-STR-05 Command-line parameters of a script

`-p`/`--param` mapped to `main` parameters, `eve script.eve -h` from `** @param` comments.

*Partial:* the arguments after the script name go to `process main`; `-p` and the generated help are not implemented.

## Missing

- `-p`/`--param name=value` mapped to the parameters of `process main`: today `eve script.eve -p n=3` answers `unknown option -p`.
- `eve script.eve -h` builds the help from the `** @param` comments.
