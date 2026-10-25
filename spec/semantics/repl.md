# The prompt (REPL)

Status: **draft**, level 3. Feature: F-TLS-03.

## Prompt lines

At the prompt a line is a command of `eve` (`help` lists them) or a line of Eve code. A line of Eve code is a statement or an expression; the variables that the lines declare live in one scope for the whole session, so a variable of one line is seen by the next. An expression is printed; a statement runs. `print x;` and `print x` both print the value of `x`.

| Line | Result |
|---|---|
| `new x := 5;` | declares `x` for the session |
| `x + 1` | prints the value (`6`) |
| `print x * 2;` | prints `10` |
| `print nosuch;` | an error: `error 4: undefined name 'nosuch'`; the session goes on |

The lines are checked when they run, not before: the static checks of a script (`check`) do not see the names of the other lines. A line with a syntax error prints the error and the session goes on.
