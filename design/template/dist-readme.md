<!-- Template of README.md at the root of a distribution (script/dist.py). {version}, {date}, {commit}, {platform}, {folder}, {exe}, {duckdb} and {install} are replaced; this comment is removed. -->
# Eve {version} for {platform}

**Eve** is a scripting language for data processing and test automation: scripts that read and write files, databases and services, run steps in parallel, and check their own results. This package holds the Eve virtual machine and its tools, built on {date} from commit `{commit}`.

## Contents

| Folder | Holds |
|---|---|
| `bin/` | `eve{exe}` (runs Eve programs, the REPL, the machine and the service), `evevm{exe}` (starts a machine in its own process), `evecp{exe}` (the compiler front end: check, doc, project), `evedb{exe}` with `{duckdb}` (the Eve database server), `evetx{exe}` (the terminal IDE), `eveux{exe}` (the graphical workbench, early draft) |
| `lib/` | the standard library of Eve; `eve` finds it beside `bin/`, so keep the two folders together |
| `manual/` | the manual: start with `manual/README.md` (usage, features, tests, performance, one page per component) |
| `tools/` | syntax colors for VS Code, Zed and Tree-sitter, and the typing aids for the symbols of Eve |
| `LICENSE` | the license of the programs |
| `TRADEMARK.md` | the use of the name and the logo of Eve |

## Install

{install}

## First steps

Save this program as `hello.eve` (the name of the aspect is the name of the file):

```
primary aspect hello is
  process main is
    print "Hello World!";
  return;
end hello;
```

Then:

```
eve hello.eve                 run it
eve --check hello.eve         check it without running it (evecp check hello.eve does the same)
eve                           the REPL: type help, then quit
eve project new shop          a new project folder with the standard layout
evetx shop                    open it in the terminal IDE
```

## Learn more

- The manual in this package: `manual/README.md`
- The tutorial: https://sagecode.org/projects/eve/index.html
- The specification of the language: https://github.com/elucian/eve-lang/blob/master/spec/index.md
- The source and the issues: https://github.com/elucian/eve-lang
