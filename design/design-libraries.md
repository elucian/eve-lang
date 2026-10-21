# Plan: the system library and the standard library (level 6)

Status: **answered by the author 2026-10-18 (D-189)**; M5 and S9 moved out of level 6. Nothing here is decided: the choices that need the author are collected in section 9 (Q-064). Related: `tutorial/syslib.html`, `lib/README.md`, D-053, D-132, D-145, Q-024 (`design/decision/level5.md`), `spec/library/`, `design/components/eveux/README.md` §2 and §4, `design/design-service.md`.

## 0. Plan of step S15.30: the libraries, one at a time (2026-10-21, for the author's review)

Status: **accepted by the author 2026-10-21 (D-214)**; L0 and L1 are built, the others wait. One library is done at a time, each with the same recipe (section 0.5). The rest of this file (sections 1 to 16) is the earlier plan of the system and standard library for level 6; where the two disagree, this section wins after the review.

### 0.1 Where we stand (audit, 2026-10-21, probed on the machine)

| Area | Works | Missing |
|---|---|---|
| strings | `split`, `join`, `length`, `count`, `find`, `contains`, `starts_with`, `ends_with`, `trim`, `trim_start`, `trim_end`, `upper`, `lower` (ASCII), `replace`, slice `s[a..b]`, `=~` | Unicode case mapping, `reverse`, `pad`, `repeat`, `format`; `parse`/`compare` only partly |
| numbers | `+ - * / % ^`, `floor`, `ceiling`, `round`, `parse`, `decimal`, `real` | **`abs`, `min`, `max`, `sqrt` are undefined names** (the feature page said they work), integer division, `pow`, `sin`, `cos`, `log`, `exp` and every other function of mathematics, constants |
| lists and maps | `count`, `delete`, `join`, `in`, `batch`, `split`, builders; maps: `has`, `get`, `keys`, `values`, `delete` | **`sort`, `reverse`, `sum`, `min`, `max`, search on a list, `contains` on a list**, `unique`, `group_by`, zip |
| time | `time.now!`, a few formats | `time.parse` rejects ISO 8601; `Date`, `Time`, `Duration` types (S15.50) |
| modules in Zig (`lib/sys/`) | `fs`, `csv`, `json`, `txt`, `time`, `os`, `net`, `secret`, `crypto`, `database`, `checkpoint` (signature files, documented by `eve --doc`) | `path`, globbing, bytes, gzip, XML, http client (S15.51, S15.52) |
| modules in Eve (`lib/`) | `config`, `http`, `route`, `rpc`, `service`, `test` | nothing for data, mathematics, statistics, business, engineering |

### 0.2 Layout proposal

```
lib/
  sys/            the signature files of the modules written in Zig (primitives: files, sockets, clock, hashes)
  <name>.eve      a small standard module in Eve: config, http, route, rpc, service, test, ...
  <domain>/       a large library, one folder, many modules: lib/math/, lib/stats/, lib/finance/, lib/eng/, lib/data/
spec/library/<name>.md    the page of a library: only functions that have a test
```

A folder library is imported by its path, as every library path already is (`from lib/math use (trig, linear);`). One module is one file, the file name is the module name; a module calls its siblings by name. A folder has a `README.md` (not a module) that lists the modules in one line each. The standard library is searched first (`modules.md`). **Rule of thumb** (kept from section 2): a function that needs the operating system, C, bytes or a loop over many values is written in Zig behind an `external` signature; policy, composition and formulas are written in Eve, where they also test the language. **Out of scope for now:** graphics, games, sound.

### 0.3 The libraries, in the order of work

| Step | Library | Content (proposed) | Needs |
|---|---|---|---|
| L0 **done** | audit and corrections | correct the false claims of the feature pages; one page for each existing module; the registry of section 3 | nothing |
| L1 **done** | **core**: strings, lists, maps | finish `strings.md` (Unicode case, `reverse`, `repeat`, `pad_start`, `pad_end`, `format`); lists: `sort`, `reverse`, `sum`, `min`, `max`, `index_of`, `unique`, `zip`, `take`, `drop`, `any`, `all`; maps: `merge`, `invert`; `sort` by key and with a comparator | nothing |
| L2 | **math**, folder `lib/math/` | `basic` (`abs`, `min`, `max`, `sign`, `clamp`, `pow`, `sqrt`, `cbrt`, `hypot`, integer division, `gcd`, `lcm`, `divmod`), `trig` (`sin` … `atan2`, degrees), `explog` (`exp`, `log`, `log2`, `log10`), `constants` (`pi`, `e`, `tau`), `numtheory` (`is_prime`, `factors`, `mod_pow`), `linear` (vectors, matrices: `dot`, `cross`, `transpose`, `det`, `inverse`, `solve`), `complex`, `rational`, `random` (seeded generator, `!` functions) | Real and Integer; `Rational` and `Complex` types are a question (0.6) |
| L3 | **stats**, folder `lib/stats/` | `describe` (`mean`, `median`, `mode`, `variance`, `stddev`, `quantile`, `range`, `skew`, `kurtosis`), `correlate` (covariance, Pearson, Spearman), `regress` (least squares, linear and polynomial), `distrib` (normal, binomial, Poisson, uniform: pdf, cdf, inverse), `sample` (with and without replacement, bootstrap), `histogram`, `moving` (moving average, exponential) | L1, L2 |
| L4 | **time and calendar**, `lib/time/` | `Date`, `Time`, `Duration`, zones, parse and format ISO 8601 and patterns, business days, holidays by calendar, periods (month end, quarter) | the types of S15.50 |
| L5 | **text and encoding**, `lib/text/` | `regex` (find, replace, split, groups), `unicode` (normalize, case, width), `encode` (`base64`, `hex`, `url`), `slug`, `template` (D-209: `{var}` into a file text), `diff` | L1 |
| L6 | **business**, `lib/finance/` | `money` (`Decimal` rounding modes: half-even, half-up; currency codes; allocation without losing a cent), `percent` (change, margin, markup), `interest` (simple and compound), `loan` (annuity, amortization schedule), `invest` (NPV, IRR, payback, future value), `tax` (brackets, VAT), `depreciation`, `invoice` (lines, totals, rounding by line or by total) | L1, L4, `Decimal` |
| L7 | **engineering**, `lib/eng/` | `units` (a quantity is a number with a unit; conversion tables for length, mass, time, temperature, pressure, energy, power; checked arithmetic), `constants` (CODATA), `numeric` (root finding: bisection and Newton; integration: trapezoid and Simpson; differential equations: Euler and Runge-Kutta; interpolation), `signal` (convolution, a plain DFT), `geometry` (points, lines, polygons: area, distance, intersection), `electric` (Ohm, impedance) | L2, L3 |
| L8 | **data**, `lib/data/` | `table` helpers over `Table` and records (`group_by`, `join`, `pivot`, `window`, `dedupe`, `fill`), `csvtools` (schema inference, profile), `quality` (null counts, ranges, duplicates), `stream` combinators (`map`, `filter`, `merge`, `window`, `parallel(n)`: level 5) | L1, L3, S15.50, S15.62 |
| L9 | **ids and compression** | `uuid`, `hash` helpers, `gzip`, `zip` (S15.51) | S15.51 |

Each library is a step of its own: it can be built, tested and used without the ones after it. L1 and L2 come first because the language cannot yet do `sort` or `sqrt`, and every later library needs them.

### 0.4 Rules for every library

1. **Page first.** `spec/library/<name>.md` (a folder library: `spec/library/<domain>/<module>.md`) lists the functions with signature, meaning, errors and one example. A function is on the page only when a test runs it.
2. **Failing test first.** `test/levelN/` with `** spec:` and the `features` field; the level is the level of the language the library needs (`sort` and `sqrt` level 1 to 3, `Date` level 5).
3. **Names.** Core functions on a value are methods (`xs.sort()`, `s.upper()`); a function of mathematics that takes plain numbers is a module function (`math.sqrt(x)`); the four functions already global (`floor`, `ceiling`, `round`, `type`) stay global; a function with a side effect or a possible different answer ends with `!` (`random.next!()`).
4. **Numbers.** A function works on `Integer`, `Real` and `Decimal` unless its page says otherwise; money uses `Decimal` only and never converts to `Real`; the result type is on the page.
5. **Errors.** A wrong argument is `$err_argument`, a result out of range `$err_overflow`, a division by zero `$err_divide`, a domain error (`sqrt(-1)`, `log(0)`) `$err_argument` with a message; no function returns `NaN` silently.
6. **Documentation.** Every public member has a `**` comment, so `eve --doc` writes its page; the library README lists the modules; the manual page of the library is generated.
7. **Performance.** A function on a hot path (sort, sum, statistics over a million values) is written in Zig; a benchmark with its Python twin is added for each data library (rule of section 7).
8. **Compatibility.** A released function keeps its meaning (section 7, point 8).

### 0.5 The recipe of one library step

1. **Design (author reviews):** the page in `spec/library/`, with the list of functions and the open questions; the feature entry in `spec/features/`.
2. **Tests:** failing tests for every function and every error.
3. **Code:** Zig primitive or Eve module; the registry entry (section 3).
4. **Docs and tags:** `**` comments, `@spec` and `@feature` tags, `eve --doc` output, the library README line.
5. **Gate:** `zig build test`, `runtest.py all --both`, `bctest.py`, `evegen check`, `bmark.py --check` for a hot path, the Linux gate.
6. **Close:** the feature status, the step marked in `phase-1-5-stabilize.md`, tech debt recorded.

### 0.6 Questions for the author (Q-072 to Q-077, answered 2026-10-21 → D-214)

- **Q-072 Layout.** Is `lib/<domain>/` (a folder next to `sys/`, imported with `from lib/math use (trig)`) the shape you want for a large library? Or one flat module per file with a prefix (`math_trig.eve`)? 
**answer** yes, subfolders for domain/subdomains: lib/math/trig etc 
- **Q-073 Where the basic functions live.** `abs`, `min`, `max`, `sqrt` are promised by the feature page as global names like `floor`. Keep a small global set (`abs`, `min`, `max`, `sqrt`, `pow`) and put the rest in `math.`; or only `math.`? 
**answer** Only math.
- **Q-074 Types.** Does Eve get the types `Rational` and `Complex` (the lexical page already names `Rational`), and a `Quantity` type for units (L7)? Or are they classes of the libraries (`math.Complex`, `eng.Quantity`) written in Eve?
**answer** Rational and Quantity are types, Complex are all types.

- **Q-075 Random.** A seeded generator in Eve (`random.next!()`, reproducible in a test) or the operating system source? Proposal: both; the seed makes a test deterministic.
**answer** Agree, a seaded generator and one that is not seaded, If user use unseaded generator, the output can't be predicted but data type can be predicted. Use {type} notation to specify a = {Integer} for example or a = {String} or {Any} for any value.

- **Q-076 Order.** Is the order L1 core, L2 math, L3 stats, L4 time, L5 text, L6 business, L7 engineering, L8 data, L9 ids the one you want? Which library is the first one for you after L1 and L2?
**answer** yes good

- **Q-077 Reference sources.** For statistics, finance and units, may the pages follow a published standard (ISO 80000 for units and quantities, ISO 4217 for currency codes, Excel/ODF names for the financial functions `NPV`, `IRR`, `PMT`), so a user finds the name they know?
**answer**
Yes. Adopting established standards for EVE’s standard library design maximizes discoverability and reduces cognitive load for data-centric developers.

Units and Quantities (ISO 80000): Adhering to ISO 80000 ensures unambiguous unit symbols, scaling prefixes, and dimensional consistency across ETL data transformations.

Currency Codes (ISO 4217): Using standard three-letter currency codes (USD, EUR, RON) is mandatory for financial data pipelines and multi-currency ledger processing.

Financial Functions (NPV, IRR, PMT): Following Excel and OpenDocument Format (ODF) naming and argument conventions aligns with existing enterprise modeling expectations, allowing analysts to map formulas directly without learning proprietary nomenclature.

### 0.7 State (2026-10-21)

- **L0.** The false claim of the feature page F-LIB-03 is corrected; `spec/library/README.md` is the index of the libraries; `python script/libcoverage.py` lists the members of every module and the number of test files that call each (`--missing`: 10 of 80 members have no test: `http.read_request!`, `respond`, `reason`; `route.add`, `status`, `find`, `dispatch`; `service.handle`; `fs.read_bytes!`; `json.valid`); the registry of section 3 already exists (`natives` in `dlib.zig`, checked by `script/libcheck.py`).
- **L1.** `spec/library/lists.md` (sort, reverse, sum, min, max, contains, index_of, unique, take, drop, zip, map, filter, reduce, any, all), `maps.md` (merge, invert) and the additions of `strings.md` (reverse, repeat, pad_start, pad_end, lines, Unicode upper and lower for Latin-1, Latin Extended-A, Greek and Cyrillic); code in `code/evevm/src/interp/corelib.zig`; tests a106 to a109. A function never changes its receiver.
- **Next.** L2 mathematics (`lib/math/`: Q-073 says only `math.`; `Rational`, `Quantity` and `Complex` are types of the language, a language feature with its own tests), together with the placeholders `{Integer}`, `{String}`, `{Any}` in the expected output of the test runner for the library `random`.

## 1. Principles

- **Performance first, purity second.** A function is written in Zig when it is on a hot path, calls C or the operating system, or needs a secret to stay out of Eve values. Eve is used where it is fast enough, or where writing it in Eve teaches us something about the language.
- **Keep what works.** Every module of level 5 (`csv`, `json`, `txt`, `fs`, `time`, `secret`, `database`, `checkpoint`) stays in Zig as it is. No behavior change, no rewrite, no test change.
- **Minimum refactoring.** One refactor only: the string chain of `libraryCall` in `code/evevm/src/dlib.zig` becomes a registry (section 3). It is mechanical and the 66+63+50+42+115 tests prove it.
- **Strengthen Eve where it pays.** New modules that are *policy* (routes, rpc client, machines, jobs, pager, auth) are written in Eve on top of Zig primitives. They are the stress test of the language for level 7, and the stronger library the user asked for.
- **Emancipation.** The standard library becomes a real, versioned, tested, documented thing: a folder of `.eve` modules with a manifest, found before anything else on the library path, loaded by the same machinery as user libraries (c01 to c09), with `external` declarations as the only door to Zig (D-053).

## 2. The two libraries, defined

| | System library | Standard library |
|---|---|---|
| Written in | Zig (`code/evevm/src/`, `evecm`, and the binding files such as `sqlite.zig`) | Eve (`lib/*.eve`) |
| Holds | primitives: files, sockets, clock, process, keyring, hashes, drivers, parsers, formats, the `vm.*` API | policy and composition: routes, rpc, machines, jobs, pager, auth, config, log reader, test helpers, traits |
| Reached by | `external` declarations in a `.eve` module, or built in the interpreter for the hot ones | `use (module)` like any module |
| Changes | rarely, with the VM version | with the library version, without a new `eve.exe` when it only uses existing primitives |
| Tested by | unit tests in Zig plus conformity tests | conformity tests, written in Eve |

A module can be split: `http.eve` holds the Eve API (`get!`, `post!`, `Response`) and `external` primitives (`.connect`, `.send`) implemented in Zig. The user sees one module. This is the default shape for every new module.

Rule of thumb for a new function: needs the OS, C, bytes, a loop over many values, or a secret → Zig. Builds records, decides what to call, formats, retries, paginates, routes → Eve.

## 3. The one refactor: a registry for external functions

Today `libraryCall` (`code/evevm/src/dlib.zig:87`) is a chain of `eql(u8, module, "fs")` tests; each new module adds lines and every call pays the comparisons. Replace it with:

- a comptime table `pub const natives = [_]Native{ .{ .module = "fs", .name = "read!", .call = fsRead }, ... }`, built with `std.StaticStringMap` so lookup is a hash, not a chain;
- the same table is what `external function read!(...)` in a `.eve` file binds to: the compiler checks that every `external` has an entry and every entry has a signature, so `eve --doc` and the VM cannot disagree;
- no change to the current semantics; the existing branches become entries one for one.

Steps: (1) write the table and move `fs`, `time`, `secret`, `csv`, `json`, `txt`, `database`, `checkpoint`; (2) run all levels, Debug with `EVE_GC_VERIFY=1` and ReleaseSafe; (3) `bmark.py --check` shows no slowdown (expected: a small gain). If the check shows a slowdown, stop and keep the chain.

## 4. Audit first (step L6-LIB-0, one day)

Produce `design/library-audit.md`, one table: module / function / today (Zig inline, Eve, missing) / planned / test. Sources: `dlib.zig`, `interp/calls.zig`, `interp/stmt.zig` (`raise`, `print`), `lib/io.eve`, `lib/exception.eve`, `syslib.html`, the spec in `spec/library/`. Two things to settle: where `io` and `exception` are implemented today (the `lib/*.eve` files are drafts; the behavior is in the interpreter), and which functions of `http` exist (client is claimed for level 5). The audit ends with the list of what to move into a `lib/` file, if anything, and the answer is allowed to be "nothing".

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

Each module is a `lib/<name>.eve` with `**` comments (so `eve --doc` writes its page), a test, and `external` only for the Zig primitives of section 5. All can be written without a new keyword; where Eve lacks something, the module is the test case that reveals it (record in `backlog/library-gaps.md`, fix in the language, never work around, as eveux says).

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
8. **Compatibility.** A function that ships in a release is never changed in meaning; a change is a new name and the old one is deprecated for one version (policy line in `design/release.md`).
9. **Performance.** A benchmark and a Python twin for any module on a data path: `p6e_json_rpc`, `p6f_route_throughput`, `p6g_sha256_file`, `p6h_ws_frames`, `p6i_pager`. Rule of D-151 applies: no leak under `EVE_GC_VERIFY=1`.

## 8. Milestones

| M | Content | Exit test |
|---|---|---|
| M0 | audit (section 4), Q-064 answered | `design/library-audit.md` committed |
| M1 | registry (section 3) and signature files of the kept modules | all levels pass; `bmark --check` ok; `eve --doc` lists the 8 modules |
| M2 **done 2026-10-18** | S1 `crypto`, S6 `os`, E6 `config`, E11 `test`, the string functions (G-7); `traits` were already in the language (spec only); `gz` postponed (TD-24) | `f03_test_module`, `f04_crypto`, `f05_os`, `f08_config`, `a86`, `a87` |
| M3 **done 2026-10-18** | S2 `net`, `http` (in Eve, not Zig: measured, TD-30), E2 `rpc`, E1 `route`/`service` | `f09_net`, `f10_route_hello`, `f11_rpc_roundtrip`, `f12_service_close`, benchmark `p6e` |
| M4 | S3 `ws`, S4 `ewp`, E4 `remote`, E10 `streams` | `f10_ws_stream`, `f11_ewp_resume`, `f12_remote_apply` |
| M5 (**level 7**, D-189) | S5 `keyring`, S12 `oidc`, E5 `auth`, E3 `machines` | `f13_login_two_machines` (the exit criterion of level 6: one by single sign-on, one by token, reconnect from the keyring) |
| M6 | E7 `jobs`, E8 `log`, E9 `pager`, S11 `regex` | `f14_jobs`, `f15_pager_1m_rows`, `f16_log_follow` |
| M7 | level 7 gate: E12 `html`, E13 `syntax`; a vertical slice of eveux (list machines, follow one log) | `g01_eveux_slice`; list of gaps in `backlog/library-gaps.md` |

Order inside a milestone is free. Each milestone ends with: `runtest.py all` on ReleaseSafe, `bmark.py --check`, the status mark of the features in `spec/features/`.

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

M1 is done in part: the registry (`natives` in `code/evevm/src/dlib.zig`, one hash lookup per module; all levels give the same results as before, 371 pass and the same 5 failures that were failing before the change; `bmark.py` shows no slowdown), signature files `lib/{fs,time,secret,csv,json,txt,checkpoint,database}.eve`, the spec page `spec/library/registry.md`, and `script/libcheck.py`, which fails when a signature file and the native table disagree (it found the two files that were missing). The rest of this section is what the design gains from that experience.

- **(1) One contract, checked by a script.** `libcheck.py` enforces rules 1 and 2 of `registry.md` (every `external` has a native, every native module has a signature file). Run it in `zig build test` and in `runtest.py all` (to do). The table is by module, not by function: a function table adds code and no speed, because the handlers already switch on the name. Go to a table by function only for a function that is measured to be hot.
- **(2) Layers with a rule of direction.** Layer 0: the interpreter (`io`, `exception`, the types). Layer 1: system modules (Zig). Layer 2: standard modules (Eve). A module may use only a lower layer or its own `external`s. This keeps `rpc` from importing `machines`, and lets a module in Layer 2 move to Zig without a change for its users.
- **(3) One rule for options, errors, time and size.** Every function that waits (net, http, os, rpc, remote) takes `timeout:` as a `Duration`, default from `eve.cfg`; a time-out raises `TimeoutError`; a lost connection `ConnectionError` (transient, can be retried by `retry`); a bad argument `$err_argument`. Sizes are in bytes (`Natural`), instants are `Instant` (UTC), durations are `Duration`; no module takes seconds as a bare number. A function that gives another value at each call ends with `!` (D-087).
- **(4) One door for permissions, designed now.** `fs`, `os`, `net` and `database` call a single check, `it.allow(.fs_write, path)` in the interpreter, before they touch the system. At level 6 the check allows everything (no login, D-189) and records the call in the statement log; F-NET-05 later fills it with the rules of the project. Adding the door afterwards would touch every function of every module.
- **(5) Streams are the shape of big data.** A function that can return many values returns a `Stream(:T)` (`fs.lines!`, `csv.read!`, `net` connections, `ws` frames, `pager`), never a list, and takes back-pressure from `for`. A list-returning twin (`fs.list!`) is for small results only and says so in its comment.
- **(6) Secrets stay out of Eve values.** `crypto` returns bytes and `Secret` is a type, not a String: keys are `Secret`, the keyring (level 7) hands out `Secret`, `net` and `http` accept a `Secret` for a header and never print it (the rule of `data-language.md`).
- **(7) The standard library tests itself.** E11 `test` is built first of the Eve modules (M2) and every later Eve module uses it, so the library is also the first big program written in Eve; a missing language feature goes to `backlog/library-gaps.md` the day it is found.
- **(8) Docs from the signature files only.** `eve --doc lib` is the single source of the reference pages and of `help`; the tags in the `**` head of a signature file (`@spec`, `@feature`, `@decision`, `@tests`) are the same as the tags of the Zig comments, so one `grep -rn "@feature F-LIB-04" lib evevm` finds the signature, the native and the test.
- **(9) Gaps found in the audit to close before level 7:** `fs` glob, copy, stat, temp files; `time.sleep!`, formats, zones; `http` (client without TLS); `os.run`; `task` (worker pool, with the generators). Each gets a line in the spec page first (D-190).

Next steps in the order of D-190: spec pages `os.md`, `crypto.md`, `test.md`, `regex.md`, `config.md`, `traits.md` (with the signatures and the errors); then the failing tests `f03` to `f07`; then the code of M2.

## 11. State of M2 (2026-10-18)

- **Standard library in Eve is real:** `lib/*.eve` is found beside the program (`<prefix>/lib`, installed by `zig build -p <prefix>`; `$EVE_STDLIB` overrides) and searched before `$EVE_LIB_PATH`; `lib/sys/` keeps the signature files, never imported. First module: `test` (E11), test `f03_test_module`.
- **System modules done:** `crypto` (S1: sha256, sha512, sha256_file!, hmac_sha256, hex and base64 codecs, random_hex!, same) and `os` (S6: run!, env!, hostname!, pid!, platform) in `code/evevm/src/syslib.zig`; tests `f04_crypto`, `f05_os`. Not yet in `crypto`: AEAD encryption and password hashing (scrypt/pbkdf2).
- **Left in M2:** S10 `gz` (the readers already inflate `.gz`), E6 `config`, E14 `traits` (`Iterable`, `Comparable`, `Printable` already exist in the interpreter; the task is their signature and spec page). The test numbers f06 to f07 are free for them.
- **Gaps found:** `backlog/library-gaps.md` (G-1 to G-3).

## 12. State of M3 (2026-10-18), step 1

- Done: `json.parse`, `json.text`, `json.valid` (native, `spec/library/data-language.md`, test `f06_json_text`); the Eve module `rpc` (`request`, `notify`, `reply`, `failure`, `dispatch`, `result_of`; `spec/library/rpc.md`, test `f07_rpc`).
- Found: G-4 (an error can not be caught in Eve code; Q-065), G-5 (thin collection methods), G-6 (`method` reserved). Debt: TD-13, TD-14.
- Next steps of M3: `net` (TCP client and server, Zig; spec first), the HTTP primitives (S8), then `route` and `service` in Eve, whose handler design waits for Q-065.

## 13. Round-up of M2 (2026-10-18)

- **Done:** `test` (Eve), `crypto` and `os` (Zig), `config` (Eve, `f08_config`), the string functions and the string slice in the VM (`a86_string_slice`, `a87_string_functions`; found missing while writing `config`, G-7), `json.parse/text/valid` and `rpc` (M3 step 1), `recover` in a function (D-192).
- **Not done, with reason:** `gz` as a module (the readers already inflate `.gz`; a module with `gzip.open!` and writers is TD-24); `traits` needs no module, they are part of the language and `registry.md` points to `declarations.md`; AEAD and password hashing wait for login (level 7, TD-5).
- **Open questions for the author:** Q-066 (string functions are plain text; regex in the module `regex`), D-192 (2) to (4) to confirm, Q-064 answered.
- **Lesson:** each Eve module written so far found a gap in the language or the VM (G-1, G-4 to G-7). M3 will find more; the rule stays: fix the language, do not work around it.

## 14. State of M3 (2026-10-18), step 2: `net`

- Done: the system module `net` (`net.listen!`, `net.connect!`, `Listener`, `Socket`; `spec/library/net.md`, `code/evevm/src/netlib.zig`, test `f09_net`): a server and its clients run as tasks of one script. Found: the sockets of Zig 0.16 on Windows are AFD handles, so readiness polling with `WSAPoll` fails; a blocking call runs on a helper thread polled with `waitFor` (TD-28).
- Next in M3: the HTTP protocol in Eve over `net` (`http`: request, response, client `get!` and `post!`), then `route` and `service`, and the test `f10_route_hello`.

## 15. State of M3 (2026-10-18), step 3: HTTP, routes and service in Eve

- Done: `http` (Request, HttpResponse, `read_request!`, `respond`, `get!`, `post!`), `route` (route table, patterns with `{name}`, `Reply`, 404/405/500) and `service` (`handle`, `serve`), all in Eve over `net`; test `f10_route_hello` runs a server with five routes and a client in one script (`spec/library/http.md`, `route.md`). The `recover` of a function (D-192) is what makes a failing handler a 500.
- Found: G-8 (a module member named like a prelude module hides it), G-9, and again G-6 (`method`). Debt: TD-29, TD-30.
- Left in M3: the exit test with a machine on one port and a client project on another (`f11_two_machines`), the performance benchmark `p6e`, and the status marks of F-NET-02 and F-STR-08 in `spec/features/`.

## 16. Round-up of M3 (2026-10-18)

- **Done:** `net` (Zig), `json.parse/text/valid`, `rpc`, `http`, `route`, `service` (Eve), `recover` in functions (D-192). A server with routes and a client run as tasks of one script (`f10`), JSON-RPC 2.0 goes over HTTP between them (`f11`), a service ends when its listener is closed (`f12`). 399 of 399 tests pass.
- **Decision of the session:** `http` stayed in Eve. The benchmark `p6e_http_requests` (300 requests) takes 0.54 s in Eve against 0.90 s for the Python twin in the bmark run; the first version, which polled with sleeps, took 7 s (24 ms a request on Windows) and was replaced by the scheduler state `io` and a wake-up from the helper thread.
- **Not done:** the exit test with two machines (`f13`, needs `machines`, level 7 login), keep-alive and one task for each connection (TD-29, M4), time-outs (TD-27), `eve --api` (F-TLS-15).
- **Gaps found:** G-4 (closed by D-192), G-5, G-6, G-7 (closed), G-8, G-9; questions open for the author: Q-066, D-192 (2) to (4), G-8.
- **Next, M4:** `ws` (WebSocket framing), `ewp` (framed protocol, credit, resume), `remote` (apply with deadline and idempotency key), `streams`; spec first.
