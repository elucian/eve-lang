# F-TLS-23 New project

`project init <folder>` and `project new <folder>`: `init` also works on an existing project and never overwrites; `new` fails on a non-empty folder. Makes `db`, `log`, `meta`, `data/in`, `data/out`, `test`, `asp`, `lib`, `src`, `doc`, `web`, the files `<name>.eve`, `eve.cfg`, `meta/project.json` and a `.gitignore`, and runs `git init` outside a repository.

*Partial:* done and tested (`code/evevm/src/scaffold.zig`); the writer of the minimal fallback log is not written.
