# F-STR-05 Command-line parameters of a script

`-p`/`--param` mapped to `main` parameters, `eve script.eve -h` from `** @param` comments.

*Done:* the texts after the script name and `-p name=value` go to the parameters of `process main`, converted to their types; `-h` after the script prints its help; a missing parameter is exit 64 (`aspects.md`). `-p` is not sent to a machine with `-loc` or `-rem` (level 6).
