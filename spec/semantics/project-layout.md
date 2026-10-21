# Project layout

Status: **draft**, level 5. A project is a folder that holds a primary aspect, the aspects and modules it uses, its data and its configuration. The commands `project init` and `project new` make the layout.

## Folders and files

| Path | Content |
|---|---|
| `<name>.eve` | the primary aspect of the project, named like the folder |
| `eve.cfg` | the configuration of the project: the core database (`db/local.db`), the ports of the machine |
| `asp/` | the aspects that `apply` calls |
| `lib/` | the modules of the project (`from lib use (m);`) |
| `src/` | other source files |
| `db/` | the databases of the project, among them the core database `local.db` |
| `data/in/`, `data/out/` | the input files and the files the project writes |
| `log/` | the run log (`log_err`, `log_wrn`) |
| `meta/project.json` | the facts about the project that the tools keep: name, creation date |
| `test/` | the tests of the project |
| `doc/` | the documents of the project |
| `web/` | the templates and the static files of a web project |
| `.gitignore` | ignores what the project generates (`db/`, `log/`, `data/out/`) |

## `project init <folder>`

Makes the folders and the files above that do not exist. A file that exists is never overwritten, so the command can be run again on an existing project to add what is missing. The folder may be non empty. When the folder is not inside a repository, `init` runs `git init`; inside a repository it makes no `.git` of its own.

## `project new <folder>`

Like `init`, but the folder must be empty or not exist: a folder that holds files is refused (exit code 73) and nothing is written. The name of the primary aspect is the name of the folder with every character that is not allowed in a name replaced by `_` (`my-shop` gives `my_shop`), and the first aspect passes the check without changes.

## Errors

A missing or extra argument is a usage error (exit code 64).
