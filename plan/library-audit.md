# Library audit (M0 of `plan/design-libraries.md`, D-189)

Date 2026-10-18. Source: `evevm/src/dlib.zig`, `evevm/src/interp/{calls,stmt,datatypes}.zig`, `lib/*.eve`, `spec/library/*.md`, `tutorial/syslib.html`. Read the code, not run: no test was executed for this audit.

## Findings

1. **`io` and `exception` are language statements, not library calls.** `print`, `write`, `raise` are parser nodes executed by `interp/stmt.zig` (`print`, `raise`); `log_err` and `log_wrn` are special-cased in `interp/calls.zig:60`. `lib/io.eve` and `lib/exception.eve` are draft signatures that nothing loads. Decision: they stay in the interpreter (hot path); the `.eve` files become signature files (documentation and type information only).
2. **Library calls are one chain** `libraryCall` (`evevm/src/dlib.zig:87`), entered from `interp/calls.zig:215` when the receiver is a type name. Modules in it: `database` (`connect`), `csv`/`json`/`txt` (`read!`, `write`), `fs`, `checkpoint`, `time` (`now!`), `secret` (`get`). Connection methods are in `connectionCall`.
3. **`fs` functions today:** `append`, `exists!`, `extension`, `join`, `lines!`, `list!`, `make_dir`, `move`, `name`, `parent`, `read!`, `read_bytes!`, `remove`, `size!`, `write`, `write_bytes`. Missing against `syslib.html`: glob, copy, stat (times, kind), temp files, `watch`.
4. **`time`:** only `now!`. Missing: `sleep`, formats, zones, `Instant` arithmetic as module functions (the types exist in `evecm/src/instant.zig`).
5. **Not implemented at all:** `http` (client; the spec `spec/library/data-language.md` says "TLS is on for https", which conflicts with D-189 (outbound TLS is level 9): the spec text must say "https: level 9"), `os`, `task`, `crypto`, `net`, `ws`, `ewp`, `keyring`, `regex`, `test`.
6. **Machine API and doors** (`machine.zig`, `channel.zig`, `daemon.zig`, `service.zig`, `client.zig`) are Zig and not reachable from Eve code. E2 `rpc` and E3 `machines` need `net` primitives first.
7. **Spec files:** `spec/library/` has only `atomic.md`, `data-engines.md`, `data-language.md`, `database.md`, `machine.md`. There is no spec page for `io`, `exception`, `fs`, `time`, `secret`, `os`, `http`, `crypto`, `net`, `route`, `rpc`, `test`, `regex`. Priority order (D-190) says the spec comes before the code: **new spec pages are the next work**, see "Next steps".
8. **Comments:** `dlib.zig` has `// Zig tip:` teaching blocks and no tags. The first touched file (M1) gets the AI tags of CLAUDE.md.

## Table

| Module | Where today | Functions today | Plan | Spec page | Test |
|---|---|---|---|---|---|
| io | interpreter (stmt, calls) | print, write, read?, error, warning, log_err, log_wrn | keep; signature file `lib/io.eve` | missing | level 1 |
| exception | interpreter | raise, expect, assert, warn, `$error`, `$stack` | keep; signature file | `spec/semantics`? (check) | level 1, 2 |
| fs | `dlib.zig fsCall` | 16 (finding 3) | keep; add glob, copy, stat, tmp | `data-language.md` partly | level 5 e-series |
| csv, json, txt | `dlib.zig` | read!, write | keep | `data-language.md` | level 5 |
| time | `dlib.zig` | now! | add sleep!, format | `datetime` in tutorial only | level 5 |
| secret | `datatypes.zig` | get | keep | `database.md`? | level 5 |
| database, checkpoint | `dlib.zig` + `evedb`, `sqlite.zig` | connect, transactions, procs | keep | `database.md` | level 5, 6 f01 f02 |
| os | none | none | S6 | new | f04 |
| crypto | none | none | S1 | new | f03 |
| test | none | none | E11 | new | f07 |
| regex | none | none | S11 | new | new |
| net, ws, ewp | none (machine code in Zig) | none | S2 to S4 | new | f08 to f11 |
| route, service, rpc, machines, remote | none | none | E1 to E4 | `machine.md` partly | f08, f09, f12 |
| keyring, oidc, auth | none | none | **level 7** (D-189) | none | none |
| tls (outbound) | none | none | **level 9 backlog** | n/a | n/a |

## Next steps (in the order of D-190)

1. **Plan:** done (`design-libraries.md`, D-189, D-190, this audit).
2. **Spec:** write `spec/library/` pages in this order, each with the signatures, errors, examples and the feature code: `registry.md` (how `external` binds, the search order, the version), `os.md`, `crypto.md`, `test.md`, `regex.md`, `config.md`, `traits.md`; fix the TLS line of `data-language.md`. Later: `net.md`, `rpc.md`, `route.md`.
3. **Tests and implementation:** M1 (registry and signature files), then M2.
4. Manual, then tutorial.
