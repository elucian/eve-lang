# 05 Program structure, scopes and errors (`RST`)

## Advantages

**RST-A01 The aspect is the best idea in Eve.** D-066 and D-072: an aspect has one `main`, nothing public, inputs by value, outputs by `@`, a fresh state per `apply`, dropped at return, errors re-raised at the `apply` line, no aspect calls another aspect. That is simultaneously:

- an **isolated request handler** (per-request state, no shared mutable globals);
- a **remote procedure** (copy-in/copy-out parameters are exactly what can cross a network);
- an **ETL step** (a unit with inputs, outputs, a status and a retry policy);
- a **memory region** (everything allocated by the call dies at `return`, `RVM-R02`).

Most languages need a framework to impose this discipline; Eve has it in the grammar.

**RST-A02 Jobs with `recover` / `retry` / `resume` / `abort`.** D-020, D-030, D-063. A job is a named, restartable step with a recorded status (`jobs["name"].status`). For ETL this is better than `try/catch`: the failure policy is centralized, the steps stay linear, and `retry` is first class (network and database errors are often transient).

**RST-A03 Modules are singletons without public variables.** D-068: public members are constants, classes, functions, methods and channels. That rules out the global mutable state that makes servers unsafe.

**RST-A04 Modules do not see the host.** D-072 f: a module communicates by parameters, never by reading the importer's globals. Good for testing and reuse.

**RST-A05 Exit codes are part of the language.** 0/1/2/3/4 and error codes as exit codes (D-055) make Eve scripts first-class citizens in shells, CI and schedulers.

## Disadvantages

**RST-D01 Three script kinds, a fourth is coming.** Driver, aspect, module, plus free scripts (`#!`, D-014). The server will need a long-running entry point that is not a driver (a driver "has exactly one process, a single-thread master", D-043). Without a plan, a fifth kind will be bolted on.

**answer** make a proposal for a language suitable to create command code for eve. Python or YML or another?

**RST-D02 Only the driver may `apply` or `start`.** D-066. Safe today, but a server request handler (an aspect) that needs to call two independent services in parallel cannot; nor can an ETL step fan out. The rule prevents recursion and deadlock but also composition.

**RST-D03 Module singletons with private mutable state.** *Applied 2026-10-05: D-081.* D-068 forbids public variables but keeps private ones; a module method that changes private state, called from two parallel aspects, is a data race. D-068 adds a "proposed" rule that started aspects can't change module private variables — a rule that needs whole-program effect analysis or a run-time check on every write.

**answer** methods that use ! can modify module variables, methods that are safe to use do not have this flag. So aspects that use unsafe methods can't run in parallel.

**RST-D04 Error identity is an integer.** *Applied 2026-10-05: D-081.* `$error.code` with `$err_name` constants and ranges 1–9, 10–127, 128–255 (D-054, D-055). Codes collide across libraries, cannot carry structured data (HTTP status, SQL state, retry-after), and 255 is the ceiling because the code doubles as a process exit code.

**answer** Advice request. Solution /alternatives.

**RST-D05 `finalize` skip rules are hard to remember.** *Applied 2026-10-05: D-081.* Runs after `return`, `exit`, normal end of `recover`; skipped by `over`, `panic`, `abort` (D-055, D-063). `over` skips `finalize` but is "normal exit 0". For a server that must release connections, any path that skips cleanup is a leak.

**answer** Agree, over must trigger finalize.

**RST-D06 Import forms multiply.** *Applied 2026-10-05: D-081.* `use (m)`, `use (m as x)`, `use (m(*))`, `use (*)`, quoted and unquoted paths, `$` variables in paths (D-072). `use (*)` merges namespaces of a whole folder: a new file in the folder can break an unrelated script.

**answer** Advantage for system library. In debug mode create a warning.

## Antipatterns

**RST-X01 Exit code as error type.** *Applied 2026-10-05: D-081.* Coupling the error identity to the process exit code (D-055: "its code is also the exit code") is the Unix shell's limitation leaking into the language's error model.

**answer** Agree, the error code must not be used as exit code. THe exit code is small number 0,1,2,3,4,5. So an error must be > 0 < 5


**RST-X02 Wildcard imports into the global namespace as the way built-ins appear.** *Applied 2026-10-05: D-081.* "Standard modules enter the language this way (`print`)" (D-072). Implicit prelude via `use (*)` makes it impossible to know where a name comes from and blocks adding new library names (every addition can break a user script).

**answer** candidate for revokation. System Library is implicit imported. Other libraries can be imported by name.

**RST-X03 Cleanup that can be skipped by a normal exit.** *Applied 2026-10-05: D-081.* `over;` ends with code 0 but skips `finalize`. A clean exit that skips cleanup is a trap.

**answer** I agree (this is duplicated) over must trigger finalize.

## Recommendations

**RST-R01 Typed errors with a code, not a code alone.** `class IoError <: Error`, `class HttpError <: Error {status: Integer}`; `recover` matches by type (`when IoError do`) and reads fields. The exit code is derived (a mapping table), not identical. Codes stay as stable ids for documentation (`E1203`).

**agree** Error can have subclasses. 

**RST-R02 `finalize` always runs, except on `panic`.** *Applied 2026-10-05: D-081.* `over`, `abort`, `return`, normal end: all run `finalize`. Only a crash skips it. Add `defer` at method level for resource release close to acquisition.

**answer** define defer and make a proposal for tutorial change. We need this.

**RST-R03 A `service` entry point (server, later).** Same shape as a driver, but its `main` registers handlers and returns; the VM then runs an event loop that `apply`s an aspect per request. See `RNW-R02`. Plan it now so the driver rules (single master, only `main` starts aspects) stay true for both.

**answer** Let's define service script. That is excellent idea. Add a page that define this kind of source code.

**RST-R04 Structured fan-out inside aspects, bounded.** *Applied 2026-10-05: D-081.* Allow `parallel` in an aspect `main` with a depth limit (e.g. 2) or only for aspects marked `leaf` (which can't start others). Recursion stays impossible; composition becomes possible.

**answer** One level deep, we can limit number of leaf subprocesses to 2. Driver can span maximum 8 processes. The total number of core used is 16. Compiler will detect (partially) too many processes in the parallel blocks but will generate warnings.

**RST-R05 Modules: immutable after `initialize`, or state behind a channel/actor.** *Applied 2026-10-05: D-081.* Rule: a module's private variables can be written only in `initialize`; after that, mutable shared state lives in an explicit `Cell`/`Channel` object whose operations are atomic. Easy to check statically (no data-flow analysis).

**answer** Agree, document the sollution in tutorial, make a decision.

**RST-R06 Explicit prelude, no wildcard imports by default.** *Applied 2026-10-05: D-081.* A fixed, versioned prelude (`print`, `len`, …) is part of the spec; `use (m(*))` stays allowed for scripts but is linted in libraries; `use (*)` on a folder is removed.

**answer** yes agree

**RST-R07 Jobs as the observable unit.** Every job emits start/end/status/duration events to a pluggable log sink (`$EVE_OUT`, a server, OpenTelemetry). This turns the existing job map into ETL lineage and server tracing for free.

**answer** Document with details. Make a decision and draft a paragraph in tutorial.
