# evecp: the compiler front end

`evecp` reads Eve source text and gives a checked syntax tree. It is a module of `eve.exe`, not a program of its own: `eve` uses it before it runs a script, and the editors (`evetx`, `eveux`) will use it for live checks. It knows nothing of the interpreter or the databases; it depends only on `evecm`.

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
eve --check script.eve            parse and check, run nothing; exit 0, or 65 with file:line:col of each error
eve --doc lib doc                 write the documentation pages of the .eve files of lib/ into doc/
eve project new sales             make a new project folder sales/ with its first driver
```

An error is reported as `file:line:col: error: text`, the form that editors and the test runner read.

## A project

`project init` and `project new` make the folders `asp`, `lib`, `src`, `test`, `doc`, `db`, `data/in`, `data/out`, `log`, `meta` and `web`, the first driver `<name>.eve`, the configuration `eve.cfg`, `meta/project.json` and a `.gitignore`. A file that exists is never overwritten, so `init` can complete a project.

## Status and limits

The front end covers the language of levels 1 to 5. There is no bytecode or native code generator yet: the syntax tree goes straight to the interpreter of `evevm`. The language is defined by the [specification](https://github.com/elucian/eve-lang/blob/master/spec/index.md).
