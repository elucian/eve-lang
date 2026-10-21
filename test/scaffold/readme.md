# test/scaffold: the special test of the project commands

`project init` and `project new` (F-TLS-23) make folders and files on disk, so besides the two runner tests `e54` and `e55` in `test/level5/` there is this test with a shell script, on real folders. It is a **special test**: it is not a level, it has a tracking file of its own, `scaffold.json`, and `python script/runtest.py all` does not run it. Run it on its own:

```
python script/runtest.py scaffold [--eve PATH]
```

This calls `sh test/scaffold/run.sh <eve>` (the same script can be run by hand: `sh test/scaffold/run.sh [path-to-eve]`, default `bin/eve.exe`); the verdict is the last line of the output and the exit status is 0 or 1. Run it after every change of `evevm/src/scaffold.zig` or of the `project` command.

 The script removes the old `work/` folder (ignored by git), makes the projects again and checks 43 things: the folders and files of the layout, the contents of `eve.cfg` (`db/local.db`), `meta/project.json` and `.gitignore`, that the first driver passes `eve --check`, that no project gets a `.git` of its own under this versioned folder, that a second `init` adds the missing folders and keeps the files of the author, that `init` accepts a folder that is not empty, that `new` refuses it (exit 73, nothing written), that a folder name like `my-shop` gives a driver `my_shop`, and the usage errors (exit 64). It prints `PASS` or one `FAIL:` line per failed check, and exits 0 or 1.

The `git init` of a project outside any repository can not be tested here (this folder is versioned); it was tried by hand in a temporary folder.
