# Plan: the system library and the standard library (level 6)

Status: **answered by the author 2026-10-18 (D-189)**; M5 and S9 moved out of level 6. Nothing here is decided: the choices that need the author are collected in section 9 (Q-064). Related: `tutorial/syslib.html`, `lib/README.md`, D-053, D-132, D-145, Q-024 (`plan/decision_level5.md`), `spec/library/`, `eveux/README.md` §2 and §4, `plan/design-service.md`.

## 1. Principles

- **Performance first, purity second.** A function is written in Zig when it is on a hot path, calls C or the operating system, or needs a secret to stay out of Eve values. Eve is used where it is fast enough, or where writing it in Eve teaches us something about the language.
- **Keep what works.** Every module of level 5 (`csv`, `json`, `txt`, `fs`, `time`, `secret`, `database`, `checkpoint`) stays in Zig as it is. No behavior change, no rewrite, no test change.
- **Minimum refactoring.** One refactor only: the string chain of `libraryCall` in `evevm/src/dlib.zig` becomes a registry (section 3). It is mechanical and the 66+63+50+42+115 tests prove it.
- **Strengthen Eve where it pays.** New modules that are *policy* (routes, rpc client, machines, jobs, pager, auth) are written in Eve on top of Zig primitives. They are the stress test of the language for level 7, and the stronger library the user asked for.
- **Emancipation.** The standard library becomes a real, versioned, tested, documented thing: a folder of `.eve` modules with a manifest, found before anything else on the library path, loaded by the same machinery as user libraries (c01 to c09), with `external` declarations as the only door to Zig (D-053).

## 2. The two libraries, defined

| | System library | Standard library |
|---|---|---|
| Written in | Zig (`evevm/src/`, `evecm`, and the binding files such as `sqlite.zig`) | Eve (`lib/*.eve`) |
| Holds | primitives: files, sockets, clock, process, keyring, hashes, drivers, parsers, formats, the `vm.*` API | policy and composition: routes, rpc, machines, jobs, pager, auth, config, log reader, test helpers, traits |
| Reached by | `external` declarations in a `.eve` module, or built in the interpreter for the hot ones | `use (module)` like any module |
| Changes | rarely, with the VM version | with the library version, without a new `eve.exe` when it only uses existing primitives |
| Tested by | unit tests in Zig plus conformity tests | conformity tests, written in Eve |

A module can be split: `http.eve` holds the Eve API (`get!`, `post!`, `Response`) and `external` primitives (`.connect`, `.send`) implemented in Zig. The user sees one module. This is the default shape for every new module.

Rule of thumb for a new function: needs the OS, C, bytes, a loop over many values, or a secret → Zig. Builds records, decides what to call, formats, retries, paginates, routes → Eve.

## 3. The one refactor: a registry for external functions

Today `libraryCall` (`evevm/src/dlib.zig:87`) is a chain of `eql(u8, module, "fs")` tests; each new module adds lines and every call pays the comparisons. Replace it with:

- a comptime table `pub const natives = [_]Native{ .{ .module = "fs", .name = "read!", .call = fsRead }, ... }`, built with `std.StaticStringMap` so lookup is a hash, not a chain;
- the same table is what `external function read!(...)` in a `.eve` file binds to: the compiler checks that every `external` has an entry and every entry has a signature, so `eve --doc` and the VM cannot disagree;
- no change to the current semantics; the existing branches become entries one for one.

Steps: (1) write the table and move `fs`, `time`, `secret`, `csv`, `json`, `txt`, `database`, `checkpoint`; (2) run all levels, Debug with `EVE_GC_VERIFY=1` and ReleaseSafe; (3) `bmark.py --check` shows no slowdown (expected: a small gain). If the check shows a slowdown, stop and keep the chain.

## 4. Audit first (step L6-LIB-0, one day)

Produce `plan/library-audit.md`, one table: module / function / today (Zig inline, Eve, missing) / planned / test. Sources: `dlib.zig`, `interp/calls.zig`, `interp/stmt.zig` (`raise`, `print`), `lib/io.eve`, `lib/exception.eve`, `syslib.html`, the spec in `spec/library/`. Two things to settle: where `io` and `exception` are implemented today (the `lib/*.eve` files are drafts; the behavior is in the interpreter), and which functions of `http` exist (client is claimed for level 5). The audit ends with the list of what to move into a `lib/` file, if anything, and the answer is allowed to be "nothing".

## 5. System library: what to add (Zig)

Ordered by dependency. Each item has a feature code, a test in `test/level6/`, and a benchmark when it is on a hot path.

| # | Module | Primitives | Feature | Notes |
|---|---|---|---|---|
| S1 | `crypto` | `sha256`, `sha512`, `blake3`?, `hmac`, `random_bytes`, `base64`, `hex`, constant-time compare, `aead` (AES-GCM or ChaCha20-Poly1305), `pbkdf2`/`scrypt` for passwords | F-LIB-10 | `std.crypto` of Zig 0.16, no C. Hashing a file in streaming mode is the benchmark. |
| S2 | `net` | TCP client and server, Unix socket, accept loop with a thread per connection (the machine already does this), timeouts, byte streams as `Stream` | F-NET-02, F-NET-03 | Reuse what `machine.zig` and `channel.zig` already have; expose, do not rewrite. |
| S3 | `ws` | WebSocket server framing (RFC 6455): handshake, text and binary frames, ping/pong, close | F-NET-08 | Needed by eveux live logs. Zig, because it is byte work. |
| S4 | `ewp` | the framed binary protocol: frame, flow control credit, resumable stream | F-NET-03 | Only framing and credit in Zig. Calls and idempotency are Eve (E4). |
| S5 | `keyring` | Windows Credential Manager, Linux Secret Service (D-Bus), macOS Keychain later; `get`, `set`, `delete` of a `Secret` | F-NET-07 | OS calls, so Zig. `Secret` never prints (existing rule). |
| S6 | `os` | `run(command, args, cwd:)` without a shell, exit code, output; environment; pid; signals; `exe_path`; hostname | Q-024 (a) | The shell `call` stays a statement. |
| S7 | `proc` | service control and the pid file used by `eve -s` (exposed, not new code) | F-TLS-30 | Small. |
| S8 | `http` server primitives | parse a request, write a response, chunked and streaming bodies, static file send with `Range` | F-NET-02 | The routing is Eve (E1). The parser is Zig for speed. |
| S9 | `tls` (client only, **level 9, backlog**, D-189) | use the Zig standard TLS client for outbound `https://` | F-DAT-02 | The machine has **no TLS server** (decision in `decision_level6.md`, reverse proxy). The client for `http.get!("https://...")` is a separate question, see Q-064 (d). |
| S10 | `zip`/`gz` | inflate and deflate, tar, zip read and write | F-LIB-xx | `.gz` is already read on the fly by the data readers; expose it as a module. |
| S11 | `regex` | a regular expression engine (RE2-like, linear time) | new | Check first whether it exists. ETL needs it. Zig, because it is a hot loop. |
| S12 | `oidc` support | JWT verify (needs S1), JWKS fetch (needs http), PKCE | F-NET-07 | Decoding and signature check in Zig; the flow is Eve (E5). |

Already in Zig and **kept**: `csv`, `json`, `txt`, `fs`, `time`, `secret`, `database` (SQLite), `checkpoint`, the `postgres://` and `evedb://` drivers, `Atomic`, `Channel`, the debugger, the machine API. They get a signature file (section 7) so they are documented and listed, not rewritten.

## 6. Standard library: what to add (Eve)

Each module is a `lib/<name>.eve` with `**` comments (so `eve --doc` writes its page), a test, and `external` only for the Zig primitives of section 5. All can be written without a new keyword; where Eve lacks something, the module is the test case that reveals it (record in `plan/library-gaps.md`, fix in the language, never work around, as eveux says).

| # | Module | Content | Uses | Feature |
|---|---|---|---|---|
| E1 | `route` and `service` | route table, `Request`, `Response`, path parameters, static files, one state per request, middleware as aspects | S2, S8, E2 | F-NET-02, F-STR-08, F-TLS-14 |
| E2 | `rpc` | JSON-RPC 2.0 client and server over `json`, error mapping to `$err_*`, batch, notification | json, net | F-NET-08 |
| E3 | `machines` | `connect`, `select`, `run`, `send`, `stat`, `disconnect` on a remote machine; a `Machine` class | E2, E5 | F-TLS-13, F-TLS-26, F-NET-09 |
| E4 | `remote` | remote apply with deadline and idempotency key, retry | S4, E2 | F-NET-04 |
| E5 | `auth` | users, roles, sessions, tokens, login by password, by token, by OIDC flow; keyring use | S1, S5, S12 | F-NET-06, F-NET-07 |
| E6 | `config` | read `eve.cfg` and `eve.env`, layered defaults, typed access | fs | F-TLS-12 |
| E7 | `jobs` | schedule, list, follow a run, resume from a checkpoint (client of the machine API) | E2 | F-TLS-21 |
| E8 | `log` | structured log lines, a reader that follows a file, rotation | fs | `io`, F-TLS-21 |
| E9 | `pager` | `Page(:T)`, cursors, reading a query page by page, back-pressure over `Stream(:T)` | database | eveux §2 |
| E10 | `streams` | combinators over `Stream(:T)` and `Channel(:T)`: map, filter, merge, batch, rate limit | task | level 4, eveux |
| E11 | `test` | `assert_eq`, fixtures, `expect_error`, a runner that prints the result in the format of `runtest.py`; so users test their own libraries | exception | new, future development |
| E12 | `html` | the `HTML` type, escaping by context, templates, components | none | F-WEB-01 (level 7) |
| E13 | `syntax` | tokenizers for Eve, SQL, JSON, XML, HTML for the editor of eveux; may call a Zig scanner if slow | regex | F-TLS-19 (level 7) |
| E14 | `traits` | `Iterable`, `Comparable`, `Printable`, `Stream` as library traits (D-145), `Atomic(:T)` (D-132) | none | S5.1a |

If a module in this list turns out slow in Eve, the hot part moves to Zig behind the same `external` signature; users do not see the change.

## 7. Emancipation of the standard library

The work that turns "a folder with two drafts" into a real library:

1. **Layout.** `lib/` at the root is the standard library: one module per file, the file name is the module name (already the rule). Submodules in subfolders (`lib/net/ws.eve`) only if a name conflict forces it.
2. **Native signature files.** For each module kept in Zig (`fs`, `csv`, `json`, `txt`, `time`, `secret`, `database`, `checkpoint`), a `lib/<name>.eve` of `external` declarations plus `**` comments, **no body**. Behavior does not change: the interpreter keeps its fast path (section 3 registry binds to it). The gain: `eve --doc` documents them, the compiler type-checks calls against real signatures, `help` lists them, and the audit table is generated from these files instead of kept by hand.
3. **Search order.** The standard library is searched first, then `$EVE_LIB_PATH`, then the project (already in D-112; add a test that a user module named `fs` cannot shadow the standard one without an explicit alias).
4. **Implicit imports.** Keep the fixed versioned list of D-053 (`io`, `exception`); add to it only `traits`. Everything else is `use`.
5. **Version.** `lib/version.json` with the library version and the minimum `eve` version; `eve --version` prints both; a project may pin it in `meta/project.json`. Library version = VM version until 1.0.
6. **Docs.** `eve --doc lib doc` is run by the test runner and fails on a public member without a comment. Pages go to the manual; `syslib.html` lists the modules from the generated table (no hand-written status column).
7. **Tests.** Every public function has a conformity test in `test/level6/` (or the level it belongs to) and, for Eve modules, a unit test with E11 once it exists. The runner reports library coverage: public members with a test / all.
8. **Compatibility.** A function that ships in a release is never changed in meaning; a change is a new name and the old one is deprecated for one version (policy line in `manual/release/README.md`).
9. **Performance.** A benchmark and a Python twin for any module on a data path: `p6e_json_rpc`, `p6f_route_throughput`, `p6g_sha256_file`, `p6h_ws_frames`, `p6i_pager`. Rule of D-151 applies: no leak under `EVE_GC_VERIFY=1`.

## 8. Milestones

| M | Content | Exit test |
|---|---|---|
| M0 | audit (section 4), Q-064 answered | `plan/library-audit.md` committed |
| M1 | registry (section 3) and signature files of the kept modules | all levels pass; `bmark --check` ok; `eve --doc` lists the 8 modules |
| M2 | S1 `crypto`, S6 `os`, S10 `gz`, E6 `config`, E14 `traits`, E11 `test` | `f03_crypto`, `f04_os`, `f05_config`, `f06_traits`, `f07_test_module` |
| M3 | S2 `net`, S8 http primitives, E2 `rpc`, E1 `route`/`service` | `f08_route_hello`, `f09_rpc_roundtrip` (client and server projects on localhost); finishes F-NET-02 and F-STR-08 |
| M4 | S3 `ws`, S4 `ewp`, E4 `remote`, E10 `streams` | `f10_ws_stream`, `f11_ewp_resume`, `f12_remote_apply` |
| M5 (**level 7**, D-189) | S5 `keyring`, S12 `oidc`, E5 `auth`, E3 `machines` | `f13_login_two_machines` (the exit criterion of level 6: one by single sign-on, one by token, reconnect from the keyring) |
| M6 | E7 `jobs`, E8 `log`, E9 `pager`, S11 `regex` | `f14_jobs`, `f15_pager_1m_rows`, `f16_log_follow` |
| M7 | level 7 gate: E12 `html`, E13 `syntax`; a vertical slice of eveux (list machines, follow one log) | `g01_eveux_slice`; list of gaps in `plan/library-gaps.md` |

Order inside a milestone is free. Each milestone ends with: `runtest.py all` on ReleaseSafe, `bmark.py --check`, the status mark of the features in `plan/version_map.md`.

## 9. Q-064: questions for the author

- (a) **The rule of section 2** (Zig for primitives and hot paths, Eve for policy, a module may be split in two with `external`): confirm, or change it.
**answer** Agree.
- (b) **Signature files for the Zig modules** (section 7, point 2): do you want `lib/fs.eve`, `lib/csv.eve` and so on, with no bodies, so the Zig modules are documented and type-checked like the others? The cost is small and nothing changes in behavior.
**answer** This is exactly right. Agree.
- (c) **The registry refactor** (section 3): accept it as the single refactor, with the condition that `bmark --check` shows no loss?
**answer** a small loss in performance is acceptable.
- (d) **Outbound HTTPS**: the machine has no TLS server (reverse proxy), but should the `http` client call `https://` URLs with the Zig standard TLS client (S9)? Needed to call OIDC providers and public APIs.
**answer** 
Implementation Recommendations
Keep EVEUX as an HTTP-only Server locally: Allow the EVE backend daemon to run on [http://127.0.0.1](http://127.0.0.1) for local development and execution. This avoids embedding complex TLS termination logic inside the language runtime. (Level7)

Mandate a Reverse Proxy for Production: Deploy behind Nginx, Caddy, or Cloudflare Tunnels when exposing EVEUX externally or integrating with production OIDC providers. Caddy is particularly effective here due to automated TLS certificate provisioning.(Level8 - add to backlog for later implementation)

Isolate Outbound vs. Inbound: Use Zig's standard TLS client (std.http.Client with TLS) strictly for outbound calls to external APIs and OIDC issuers, while keeping inbound traffic handled by the deployment environment's proxy.(Level9 - backlog tech dept until Zig reach mature level)


- (e) **Names**: `net`, `ws`, `ewp`, `crypto`, `keyring`, `rpc`, `route` and `service`, `machines`, `remote`, `auth`, `config`, `jobs`, `log`, `pager`, `streams`, `test`, `html`, `syntax`. Rename any you dislike; Q-024 (a) already fixed `io`, `exception`, `fs`, `time`, `secret`, `database`, `http`, `csv`, `json`, `txt`, `os`.
**answer** very good names
- (f) **`test` module and `regex`** in level 6 (as in the table) or later?
**answer** Level6 - very important feature 

- (g) **Order**: is M3 (routes and rpc) before M5 (login) right, given that the exit criterion of the level is the login of two machines?
**answer** Until level 7, no login is necesary for connecting two machines. Level 6 is not production ready and we need only local testing. On Level 7, we add remote Linux machine for testing everything and simulate a production environment. So yes it is right.

## 10. Design improvements after M1 (2026-10-18)

M1 is done in part: the registry (`natives` in `evevm/src/dlib.zig`, one hash lookup per module; all levels give the same results as before, 371 pass and the same 5 failures that were failing before the change; `bmark.py` shows no slowdown), signature files `lib/{fs,time,secret,csv,json,txt,checkpoint,database}.eve`, the spec page `spec/library/registry.md`, and `script/libcheck.py`, which fails when a signature file and the native table disagree (it found the two files that were missing). The rest of this section is what the design gains from that experience.

- **(1) One contract, checked by a script.** `libcheck.py` enforces rules 1 and 2 of `registry.md` (every `external` has a native, every native module has a signature file). Run it in `zig build test` and in `runtest.py all` (to do). The table is by module, not by function: a function table adds code and no speed, because the handlers already switch on the name. Go to a table by function only for a function that is measured to be hot.
- **(2) Layers with a rule of direction.** Layer 0: the interpreter (`io`, `exception`, the types). Layer 1: system modules (Zig). Layer 2: standard modules (Eve). A module may use only a lower layer or its own `external`s. This keeps `rpc` from importing `machines`, and lets a module in Layer 2 move to Zig without a change for its users.
- **(3) One rule for options, errors, time and size.** Every function that waits (net, http, os, rpc, remote) takes `timeout:` as a `Duration`, default from `eve.cfg`; a time-out raises `TimeoutError`; a lost connection `ConnectionError` (transient, can be retried by `retry`); a bad argument `$err_argument`. Sizes are in bytes (`Natural`), instants are `Instant` (UTC), durations are `Duration`; no module takes seconds as a bare number. A function that gives another value at each call ends with `!` (D-087).
- **(4) One door for permissions, designed now.** `fs`, `os`, `net` and `database` call a single check, `it.allow(.fs_write, path)` in the interpreter, before they touch the system. At level 6 the check allows everything (no login, D-189) and records the call in the statement log; F-NET-05 later fills it with the rules of the project. Adding the door afterwards would touch every function of every module.
- **(5) Streams are the shape of big data.** A function that can return many values returns a `Stream(:T)` (`fs.lines!`, `csv.read!`, `net` connections, `ws` frames, `pager`), never a list, and takes back-pressure from `for`. A list-returning twin (`fs.list!`) is for small results only and says so in its comment.
- **(6) Secrets stay out of Eve values.** `crypto` returns bytes and `Secret` is a type, not a String: keys are `Secret`, the keyring (level 7) hands out `Secret`, `net` and `http` accept a `Secret` for a header and never print it (the rule of `data-language.md`).
- **(7) The standard library tests itself.** E11 `test` is built first of the Eve modules (M2) and every later Eve module uses it, so the library is also the first big program written in Eve; a missing language feature goes to `plan/library-gaps.md` the day it is found.
- **(8) Docs from the signature files only.** `eve --doc lib` is the single source of the reference pages and of `help`; the tags in the `**` head of a signature file (`@spec`, `@feature`, `@decision`, `@tests`) are the same as the tags of the Zig comments, so one `grep -rn "@feature F-LIB-04" lib evevm` finds the signature, the native and the test.
- **(9) Gaps found in the audit to close before level 7:** `fs` glob, copy, stat, temp files; `time.sleep!`, formats, zones; `http` (client without TLS); `os.run`; `task` (worker pool, with the generators). Each gets a line in the spec page first (D-190).

Next steps in the order of D-190: spec pages `os.md`, `crypto.md`, `test.md`, `regex.md`, `config.md`, `traits.md` (with the signatures and the errors); then the failing tests `f03` to `f07`; then the code of M2.

## 11. State of M2 (2026-10-18)

- **Standard library in Eve is real:** `lib/*.eve` is found beside the program (`<prefix>/lib`, installed by `zig build -p <prefix>`; `$EVE_STDLIB` overrides) and searched before `$EVE_LIB_PATH`; `lib/sys/` keeps the signature files, never imported. First module: `test` (E11), test `f03_test_module`.
- **System modules done:** `crypto` (S1: sha256, sha512, sha256_file!, hmac_sha256, hex and base64 codecs, random_hex!, same) and `os` (S6: run!, env!, hostname!, pid!, platform) in `evevm/src/syslib.zig`; tests `f04_crypto`, `f05_os`. Not yet in `crypto`: AEAD encryption and password hashing (scrypt/pbkdf2).
- **Left in M2:** S10 `gz` (the readers already inflate `.gz`), E6 `config`, E14 `traits` (`Iterable`, `Comparable`, `Printable` already exist in the interpreter; the task is their signature and spec page). The test numbers f06 to f07 are free for them.
- **Gaps found:** `plan/library-gaps.md` (G-1 to G-3).

## 12. State of M3 (2026-10-18), step 1

- Done: `json.parse`, `json.text`, `json.valid` (native, `spec/library/data-language.md`, test `f06_json_text`); the Eve module `rpc` (`request`, `notify`, `reply`, `failure`, `dispatch`, `result_of`; `spec/library/rpc.md`, test `f07_rpc`).
- Found: G-4 (an error can not be caught in Eve code; Q-065), G-5 (thin collection methods), G-6 (`method` reserved). Debt: TD-13, TD-14.
- Next steps of M3: `net` (TCP client and server, Zig; spec first), the HTTP primitives (S8), then `route` and `service` in Eve, whose handler design waits for Q-065.
