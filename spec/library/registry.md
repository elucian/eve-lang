# The library registry

Status: **0.1-draft**, level 6 (D-189, D-190). Features: F-LIB-01 (standard library), F-LIB-10 (encryption and hashing), F-SPEC-06. Plan: `plan/design-libraries.md`. Audit: `plan/library-audit.md`.

## Two libraries

| | System library | Standard library |
|---|---|---|
| Written in | the language of the implementation (Zig for the reference VM) | Eve, in `lib/*.eve` |
| Holds | primitives: files, sockets, clock, process, keyring, hashes, drivers, parsers, `vm.*` | policy and composition: routes, rpc, machines, jobs, pager, config, log, test |
| Reached by | an `external` declaration, or an interpreter fast path | `use (module)` |

An implementation may write any function of either library natively, **if the Eve-visible behavior and the signature are the same**. Performance decides where a function lives, never the specification.

## A module is a file

`lib/<name>.eve` declares `module <name> is`. A member is public only if the module lists it in `export (…)` (D-085); the old prefix `.` is gone. A member written `external function name(…) => (…);` has a signature and no body: the implementation provides the body (D-053, D-056). Visibility words `public`, `protected`, `private` belong to the members of a class (D-085), not to module functions.

A signature file is documentation and the source of `eve --doc` and `help`; the compiler does not load it (the modules of `natives` are values of the prelude), and its parser support for `external function` in a module is not written yet (the grammar has only the stored-procedure form, D-166). Until it is, `script/libcheck.py` is the check of the file. A module of natives is therefore a **signature file**: it documents the module without changing how it runs; type-checking calls against it comes when the parser reads `external function`.

## Registry rules

- (1) **Every `external` has exactly one native entry** in the implementation, keyed by `module` and `name`; a missing entry is an error when the module is loaded (not when the function is called).
- (2) **Every native entry has a signature** in a `lib/<module>.eve`; `eve --doc` and `help` list the module from the signature file.
- (3) **The name of a function that gives another value at each call ends with `!`** (D-087): `time.now!`, `fs.read!`.
- (4) **Errors** are raised with the codes of the `exception` module, so one `recover` handles them.
- (5) **A native module never prints a `Secret`** (see `semantics/types.md`, Secret).

## Search order

1. the standard library in Eve: the folder `lib/` beside the program (`<prefix>/lib` for `<prefix>/bin/eve.exe`) or `$EVE_STDLIB`; the folder `lib/sys/` holds signature files and is never imported;
2. the folders of `$EVE_LIB_PATH`;
3. the `lib/` of the project.

A project module cannot shadow a standard module by its name; it needs an alias in `use` (test `c03_import_alias`). The implicit imports are a fixed, versioned list: `io`, `exception` ; the traits `Iterable`, `Stream`, `Comparable` and `Printable` are part of the language, see `../syntax/declarations.md#traits-and-generic-classes`.

## Version

`lib/version.json` holds `{"library": "<X.Y.Z>", "requires_eve": "<X.Y.Z>"}`. Until 1.0 the library version equals the version of the machine. A function that has shipped never changes its meaning; a change is a new name, and the old one is deprecated for one version.

## Modules of the system library at level 6

| Module | Feature | State | Page |
|---|---|---|---|
| `io`, `exception` | F-LIB-01 | in the interpreter; signature files | (this page) |
| `fs`, `csv`, `json`, `txt`, `time`, `secret`, `database`, `checkpoint` | F-DAT-xx | implemented (level 5); signature files at level 6 | `data-language.md`, `database.md` |
| `crypto`, `os` | F-LIB-10, F-LIB-07 | implemented (M2, 2026-10-18) | [crypto.md](crypto.md), [os.md](os.md) |
| string functions (`trim`, `find`, `replace`, slice, ...) | F-LIB-03 | implemented (2026-10-18, G-7) | [strings.md](strings.md) |
| `regex` | F-LIB-03 | planned (M6) | to write |
| `gzip` (module; the readers already inflate `.gz`) | F-LIB-09 | postponed (TD-24) | |
| `net`, `ws`, `ewp` | F-NET-02, F-NET-03 | planned (M3, M4) | to write |
| `keyring`, `oidc`, `auth` | F-NET-07 | **level 7** (D-189) | |
| outbound TLS in `http` | F-DAT-02 | **level 9, backlog** (D-189) | |

## Modules of the standard library in Eve at level 6

| Module | Feature | State | Page |
|---|---|---|---|
| `test` | F-LIB-12 | implemented (M2, 2026-10-18) | [test.md](test.md) |
| `config` | F-TLS-12 | implemented (M2, 2026-10-18) | [config.md](config.md) |
