# The tools `eve fmt` and `eve lint`

Status: **draft**, level 4. Feature: F-TLS-08. Both commands take files and folders: a file that ends in `.eve` as it is, a folder with its `.eve` files and those of its sub-folders (the folders that start with a dot are not read), in the order of their names. A file with a syntax error is reported as `file:line:col: error: text`, the command goes on with the other files, and the exit status is 65 when there was one.

## eve fmt

`eve fmt [--check] <file.eve | folder>...` writes each file in the layout of [lexical.md](../lexical/lexical.md#layout). The command changes the white space of the lines and nothing else; the spaces inside a line and the indentation are the author's (the parser already refuses an indentation that is not 2 spaces per level).

| Rule | Example |
|---|---|
| line endings are LF | `CRLF` and a lone `CR` become `LF` |
| no white space at the end of a line | `print 1;   ` becomes `print 1;` |
| no blank line at the start of the file, and at most one blank line in a row | three blank lines become one |
| the file ends with exactly one line ending | no blank line at the end, and a last line without a line ending gets one |
| the lines of a raw text literal (`"""` … `"""`) are data and stay as they are | the line that closes the literal ends in code, so its end is trimmed |

The command is idempotent: formatting a formatted file changes nothing. It prints `file: formatted` for each file it wrote, then `fmt: N file(s), M changed`. With `--check` nothing is written: it prints `file: not formatted` for each file that would change, then `fmt: N file(s), M not formatted`, and the exit status is 1 when there was one.

## eve lint

`eve lint <file.eve | folder>...` reports the names that are declared and never used, as `file:line:col: warning: kind 'name' is never used`, then `lint: N file(s), M warning(s)`. The exit status is 1 when there is a warning, 0 when there is none.

| Kind | Judged |
|---|---|
| `variable` | a name made by `new` or `set` in a process, function, procedure, method or generator |
| `parameter` | a parameter of a function, procedure or generator; not of a method or a constructor (a method may have to take what it does not use) and not of `process main` (the command line gives it) |
| `loop variable` | a name of the pattern of a `for` |
| `import` | an item of `from path use (…)` that is not named in the file; an import of all members (`m(*)` or `*`) is not judged |

A name is judged by its text in the routine that declares it: a name read anywhere in the routine is used, and `let x := v;` alone does not read `x` (`x += 1` and `x[1] := v` do). A name that starts with `_` is meant to be unused and is never reported. A signature without a body (`external`) is not judged. The tool errs on the side of silence: a second name with the same text hides an unused one.
