<!-- Template of README.md at the root of a distribution (script/dist.py). {version}, {date}, {commit}, {platform} and {zip} are replaced; this comment is removed. -->
# Eve {version} for {platform}

**Eve** is a scripting language for data processing and test automation: scripts that read and write files, databases and services, run steps in parallel, and check their own results. This package holds the Eve virtual machine and its tools, built on {date} from commit `{commit}`.

## Contents

| Folder | Holds |
|---|---|
| `bin/` | `eve.exe` (runs Eve programs, the REPL, the machine and the service), `evevm.exe` (starts a machine in its own process), `evecp.exe` (the compiler front end: check, doc, project), `evedb.exe` with `duckdb.dll` (the Eve database server), `evetx.exe` (the terminal IDE), `eveux.exe` (the graphical workbench, early draft) |
| `lib/` | the standard library of Eve; `eve` finds it beside `bin/`, so keep the two folders together |
| `manual/` | the manual: start with `manual/README.md` (usage, features, tests, performance, one page per component) |
| `tools/` | syntax colors for VS Code, Zed and Tree-sitter, and the typing aids for the symbols of Eve |
| `LICENSE` | the license of the programs |
| `TRADEMARK.md` | the use of the name and the logo of Eve |

## Install

1. Unzip the package in a folder of your choice, for example `C:\eve`. The folder `{zip}` holds everything; nothing is written elsewhere.
2. Add its `bin` folder to the `PATH` (for example `C:\eve\{zip}\bin`).
3. Open a new terminal and check: `eve -v` prints `EVE - Version: {version}`.

To uninstall, remove the folder and its line of the `PATH`.

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
