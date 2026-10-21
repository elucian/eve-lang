<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# All levels: Tools, documents, bytecode and release

Work that does not belong to one level. The tools: the command line, the test runner, the documentation generator, the smoke test and the benchmarks; the documents: the tutorial, the compiler manual, the specification tables and the licenses; the second engine, the bytecode compiler and machine, the portable `.evb` file and the embedding API; and the road to a stable release: package manager, hardening, the compiler registry and the compiler course. A feature here is checked at every level, for example by running all levels on both engines.

| Code | Feature | Stage |
|---|---|---|
| [`F-DAT-07`](#f-dat-07-database-synchronization) | Database synchronization | planned |
| [`F-DOC-01`](#f-doc-01-tutorial-language-part) | Tutorial, language part | drafted |
| [`F-DOC-04`](#f-doc-04-compiler-manual) | Compiler manual | drafted |
| [`F-DOC-06`](#f-doc-06-compiler-course) | Compiler course | planned |
| [`F-DOC-07`](#f-doc-07-manual-generator) | Manual generator | validated |
| [`F-SPEC-07`](#f-spec-07-machine-readable-tables-with-schemas) | Machine-readable tables with schemas | validated |
| [`F-SPEC-08`](#f-spec-08-conformance-levels) | Conformance levels | drafted |
| [`F-SPEC-09`](#f-spec-09-compiler-registry-and-approval) | Compiler registry and approval | planned |
| [`F-SPEC-10`](#f-spec-10-licenses-and-trademark) | Licenses and trademark | validated |
| [`F-TLS-01`](#f-tls-01-command-line-cli) | Command line (CLI) | validated |
| [`F-TLS-05`](#f-tls-05-command-files-and-serve-mode) | Command files and serve mode | validated |
| [`F-TLS-06`](#f-tls-06-test-runner) | Test runner | validated |
| [`F-TLS-07`](#f-tls-07-documentation-generator-eve---doc) | Documentation generator `eve --doc` | validated |
| [`F-TLS-10`](#f-tls-10-package-manager) | Package manager | planned |
| [`F-TLS-16`](#f-tls-16-smoke-test) | Smoke test | validated |
| [`F-TLS-17`](#f-tls-17-benchmarks) | Benchmarks | validated |
| [`F-TLS-18`](#f-tls-18-tutorial-pages-of-the-tests) | Tutorial pages of the tests | validated |
| [`F-TLS-32`](#f-tls-32-test-tracking-files) | Test tracking files | validated |
| [`F-VM-04`](#f-vm-04-bytecode-compiler-and-vm) | Bytecode compiler and VM | drafted |
| [`F-VM-07`](#f-vm-07-portable-bytecode-file-evb) | Portable bytecode file `.evb` | planned |
| [`F-VM-08`](#f-vm-08-embedding-api) | Embedding API | planned |
| [`F-VM-10`](#f-vm-10-cross-platform-releases) | Cross-platform releases | drafted |
| [`F-VM-13`](#f-vm-13-engine-selection-and-equivalence-tests) | Engine selection and equivalence tests | validated |
| [`F-VM-14`](#f-vm-14-sampling-profiler) | Sampling profiler | validated |
| [`F-WEB-04`](#f-web-04-web-application-kit) | Web application kit | planned |

## F-DAT-07 Database synchronization

Stage: **planned**.

Keep two databases consistent (manifest).

## F-DOC-01 Tutorial, language part

Stage: **drafted**.

The topic pages reviewed and consistent with the decisions.

*Partial:* 38 topic pages and the generated pages of Phase 8 (demos, feature tests, smoke and performance); a few pages still describe old forms.

## F-DOC-04 Compiler manual

Stage: **drafted**.

Implement, usage, generated feature tables, implemented features.

*Partial:* `manual/usage.md`.

## F-DOC-06 Compiler course

Stage: **planned**.

The student track: milestones, bytecode, memory, scheduling, WASM (compiler.html).

## F-DOC-07 Manual generator

Stage: **validated**.

`generator/evegen.py` builds the manual from the features of the specification, the tracking files of the tests and the benchmark history, writes an index of the specification and checks that the spec, the tests and the manual stay apart: only the generator reads both the spec and the tests.

## F-SPEC-07 Machine-readable tables with schemas

Stage: **validated**.

JSON schemas.

## F-SPEC-08 Conformance levels

Stage: **drafted**.

Level 1 (a single script), level 2 (functions, procedures, lambdas, aspects), level 3 (modules, classes), levels 4 to 7, with the expected-output convention.

*Partial (2026-10-20):* suites of levels 1 to 6 exist and pass (see `manual/tests.md`), with a smoke test and benchmarks; level 7 has no tests; no list says which implementation passes which level (the registry, F-SPEC-09).

## F-SPEC-09 Compiler registry and approval

Stage: **planned**.

How a third-party implementation claims a spec version and a level (S6.3, S6.4).

## F-SPEC-10 Licenses and trademark

Stage: **validated**.

BUSL-1.1 code, CC BY-NC-SA 4.0 spec and documents, TRADEMARK.md.

## F-TLS-01 Command line (CLI)

Stage: **validated**.

`eve script.eve`, `--check`, `--execute`, `-h`, `-v`, `-s`, `-d`, `-x`, `-i`, `-t`, exit codes 64–66 (`manual/usage.md`).

## F-TLS-05 Command files and serve mode

Stage: **validated**.

(scheduled for removal, replaced by F-TLS-13): `.vmc` slot, workflow commands `load`, `parse`, `run`, `errors`, `ast`, `inspect`, `status`. The tests v01 to v11 were removed: no test covers it now.

## F-TLS-06 Test runner

Stage: **validated**.

 for levels, project tests, several drivers per project, `/*@expect*/` blocks, reports in JSON for the tests that fail, and the result of every run in the tracking file of the suite (F-TLS-32).

## F-TLS-07 Documentation generator `eve --doc`

Stage: **validated**.

Markdown from `**` comments and signatures, a command of the VM.

## F-TLS-10 Package manager

Stage: **planned**.

Library folders, versions, dependencies, a registry.

## F-TLS-16 Smoke test

Stage: **validated**.

16 small scripts, one feature each, in less than a second, independent of the other tests.

## F-TLS-17 Benchmarks

Stage: **validated**.

One per level with a twin in Python, a history of the runs. Levels 1 to 3 measured.

## F-TLS-18 Tutorial pages of the tests

Stage: **validated**.

`features.html` and `quality.html` generated from the tests and the benchmarks.

## F-TLS-32 Test tracking files

Stage: **validated**.

One JSON file per suite, for the levels and for the special tests (smoke, bytecode, scaffold): status, runs, failures, date and reason of every test, and the features of the specification that the test checks. The runner writes it after every run and the manual generator reads it.

## F-VM-04 Bytecode compiler and VM

Stage: **drafted**.

Register machine with 32-bit instructions. *Stage B5.2 (2026-10-19):*, `chunk.zig`; the core of level 1 is translated (numbers, text, variables, operators, `print`, `expect`, `if`, `while`, `for` over ranges, calls of the functions of the aspect), the rest runs on the tree walker through a bridge (TD-46); `p1a_arith` 64 to 26 ms, `p1b_calls` 41 to 16 ms.

*Stage B5.3 (2026-10-20):* lists, maps, sets, indexes and stores, `<+`, `.count` and `.length`, interpolation, `for` over a list, a map, a set or a string, the names of the aspect (`loadg`), the process `main` with `recover`, `retry`, `resume` and `finalize`, safe points; a fast case with the tree walker as the exact slow case (`xref`). 326 of 348 test programs run on the bytecode machine from the first line to the last; the others hold jobs, nested aspects, `panic`, private processes, lambdas and a few forms of `for` and `call` (`EVE_BC_TRACE=1` says which). *Open:* B5.4 to B5.6 (classes and closures, tasks, the data language), the typed forms of the instructions, `.evb`. Moved from level 5 to All levels.

## F-VM-07 Portable bytecode file `.evb`

Stage: **planned**.

Versioned, hashed, with debug lines and capabilities. Moved from level 7 to All levels.

## F-VM-08 Embedding API

Stage: **planned**.

The VM as a library with a C ABI (the C ABI is the contract of the embedding). Moved from level 6 to All levels.

## F-VM-10 Cross-platform releases

Stage: **drafted**.

Windows, Linux, macOS binaries from one build bumps versions.

*Partial:* Windows build, release script.

## F-VM-13 Engine selection and equivalence tests

Stage: **validated**.

`--engine tree\|bc` and `EVE_ENGINE`; `runtest.py --both` and `bmark.py --both` run every test and benchmark on both engines and require equal results; `eve --disasm` and the golden listings.

## F-VM-14 Sampling profiler

Stage: **validated**.

`EVE_PROFILE=1` prints the functions with the most samples (Windows, symbols from the `.pdb`); the optimization steps R1 to R4 were chosen with it.

*Open:* Linux and macOS.

## F-WEB-04 Web application kit

Stage: **planned**.

Service + EWP feed + browser client, deployment guide.
