# evecp: the compiler front end

`evecp` reads Eve source text and gives a checked syntax tree. It is a program (`bin/evecp.exe`) and, with the very same code, a part of `eve.exe`: `eve cp check a.eve` gives what `evecp check a.eve` gives, in the same text and with the same exit status. The editors (`evetx`, `eveux`) use it for live checks. It knows nothing of the interpreter or the databases; it depends only on the common part.

## What it does

| Stage | Result |
|---|---|
| lexer | the tokens of the source (words, numbers, strings, regex literals, comments) |
| parser | the syntax tree, following the grammar of the specification |
| check | the static rules: names and scopes, parameter order, private methods, the rules of overloaded subprograms |
| project link | a driver with its aspects and modules: what `apply` and `import` bring in |
| doc | `eve --doc`: one Markdown page for each `.eve` file, from its comments and declarations |
| scaffold | `eve project init <folder>` and `eve project new <name>`: the standard layout of an Eve project |

## Using it from the command line

```
evecp check script.eve...         parse and check, run nothing; exit 0, or 65 with file:line:col of each error
evecp doc lib doc                 write the documentation pages of the .eve files of lib/ into doc/
evecp project new sales           make a new project folder sales/ with its first driver
evecp project init sales          the same, but keep the files that exist
evecp outline script.eve...       the aspects, classes and subprograms of scripts, nested, with line:column
evecp symbols script.eve...       the same as one flat list: line:column, kind, name, container
evecp -v                          the version
```

`eve cp check script.eve` (also `eve cp doc`, `eve cp project new`) runs the same commands inside `eve`; `eve check script.eve` and `eve --check script.eve` are older spellings of it. An error is reported as `file:line:col: error: text`, the form that editors and the test runner read. Exit status: 0 success, 64 bad command line, 65 syntax error, 66 file not found, 73 a file or folder could not be made.

## For tools: diagnostics and outline in one call

An editor does not run commands: it links `evecp` and calls `analyze(allocator, text)`. The result has the **diagnostics** (a syntax error, or a rule of the language that the text breaks, each with line, column and message) and the **outline** (the aspect or module, its classes, traits, subprograms and tables, each with a name, a kind, a position and the symbol that contains it). A text that is Eve but breaks a rule still has its full outline; a text that is not Eve has the error and no outline, because the parser stops at its first error. `evecp outline` and `evecp symbols` print the same result. `evetx` and `eveux` use it to show errors while the person types, without starting a machine.

## A project

`project init` and `project new` make the folders `asp`, `lib`, `src`, `test`, `doc`, `db`, `data/in`, `data/out`, `log`, `meta` and `web`, the first driver `<name>.eve`, the configuration `eve.cfg`, `meta/project.json` and a `.gitignore`. A file that exists is never overwritten, so `init` can complete a project.

## Status and limits

The front end covers the language of levels 1 to 5. There is no bytecode or native code generator yet: the syntax tree goes straight to the interpreter of `evevm`. The language is defined by the [specification](https://github.com/elucian/eve-lang/blob/master/spec/index.md).
