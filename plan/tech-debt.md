# Technical debt

Recorded as the work goes (author's word, 2026-10-18): when a shortcut, a gap or a postponed piece is left behind, add one line here with its origin, so the plan can cover it later. Format: id, what, why left, where it shows, when to pay (level or milestone). Remove a line when it is paid, with the commit.

| Id | Debt | Why left | Where | Pay |
|---|---|---|---|---|
| TD-1 | `libraryCall` registry is by module; each handler still switches on the function name | no speed gain from a per-function table; D-189 (3) | `evevm/src/dlib.zig` `natives` | only if a function is measured hot |
| TD-2 | Externals of a user module are not bound to the natives (c31 is a run-time error); the standard modules in `lib/sys/` are documentation and are checked by `script/libcheck.py`, not by the compiler | the natives take unevaluated argument nodes, a routine call has values (D-191 (4)) | `evecp/src/parser.zig`, `evevm/src/interp/calls.zig` `runRoutine` | M3, when the first Eve module needs a native of its own |
| TD-3 | `lib/sys/io.eve` and `lib/sys/exception.eve` use forms the parser cannot read (`*args`, `@v`, `external set $error`) | they document statements of the language | `lib/sys/` | with the spec pages of `io` and `exception` |
| TD-4 | The legacy prefix `.` for public members is still accepted by `eve --doc` | D-191 (2) | `evecp/src/doc.zig` `startsDeclaration` (`@legacy retire`) | when no file starts a declaration with `.`; tutorial last |
| TD-5 | `crypto` has no symmetric encryption (AEAD) and no password hashing (scrypt, pbkdf2) | needed only by login (level 7) | `evevm/src/syslib.zig` | level 7 with `auth` |
| TD-6 | Errors raised in a standard module show the file of the calling script with the line of the module (G-1) | frames do not carry the file | `plan/library-gaps.md` | M3 or when diagnostics are worked on |
| TD-7 | No `exit <code>` statement; the `test` module ends the process with code 4 (G-2) | needs a decision | `plan/library-gaps.md` | Q to the author |
| TD-8 | The Zig modules still carry the old `// Zig tip:` teaching comments; only touched code has the AI tags (D-190) | improve on the go | `evecm/`, `evecp/`, `evevm/`, `cmd/`, `evedb/`, `evetx/` | on touch |
| TD-9 | `os.run!` collects the output after the end (a long program streams nothing); no time-out; no cancel with `vm.cancel` | first version | `evevm/src/syslib.zig` `run` | M3 with the `timeout:` option of every waiting call |
| TD-10 | The permission door `it.allow(...)` of `design-libraries.md` §10 (4) is not written; `fs`, `os` call the system directly | level 6 allows everything (D-189) | `evevm/src/dlib.zig`, `syslib.zig` | F-NET-05 |
| TD-11 | The outbound TLS client of `http` (level 9) and the reverse-proxy documentation (level 8) | D-189 (4) | `plan/backlog.md` | level 8, 9 |
| TD-12 | `bmark.py --check` compares with the history saved on 2026-10-13, so every run reads +30% to +50% on this machine | the history was made on another load | `test/bmark/history.json` | next `bmark.py --save` at a release |
| TD-13 (paid by D-192, remove at the next review) | `rpc.dispatch` does not turn a handler error into a `-32603` answer (G-4) | no way to catch an error in Eve code; waits for Q-065 | `lib/rpc.eve` | when Q-065 is answered |
| TD-14 | `rpc` builds and reads lines only; no connection yet (needs `net`) | M3 goes in steps | `lib/rpc.eve` | M3 step 2 |
| TD-15 | The SQL highlighter of evetx still colors a `/* ... */` comment on its own line only (no state across lines or wrapped pieces); Eve code was fixed on 2026-10-18 | not asked yet | `evetx/src/view.zig` `drawSql` | reuse `Scan`/`Carry` for SQL when a SQL tab needs it |
| TD-16 | The Zed extension (`tools/zed-eve`) was checked with the Tree-sitter CLI only, not loaded in Zed; the grammar `rev` is a local commit; no bracket matching, indents, outline | the author tests editors by hand | `tools/zed-eve/README.md` | when the grammar gets its own repository |
| TD-17 | The VS Code plugin of `tools/TODO-vscode-plugin.md` is still a todo; it could reuse `gen_zed.py`'s word lists for a TextMate grammar | order of work | `tools/` | after level 6 |
