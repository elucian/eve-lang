# Critical review of Eve (2026-10-04)

A design review of the whole project as of commit `f6500d3`: language (tutorial + decisions D-001 to D-073), specification, tests, the Zig VM, process and licensing. The future target the review measures against: **Eve as a client-server platform for internet ETL**. Today's work is the client: the VM that runs scripts, reads and writes data and calls services. Later comes a server that speaks an efficient protocol and serves data or HTML like a web server, with Eve, HTML and WebAssembly.

The review is deliberately critical. Praise is kept short and specific; problems come with evidence (decision ids, files) and an alternative.

## How to cite a point

Every point has a stable code `R<area>-<kind><nn>`, for example `RSY-X02`. Codes are never renumbered; a point that becomes obsolete is struck through, not deleted. The `R` prefix keeps them apart from the issue ids (`SYN-`, `TYP-`, `TOP-`, …) and from decisions (`D-nnn`, `Q-nnn`).

| Kind | Meaning |
|---|---|
| `A` | advantage of the current design: keep it, build on it |
| `D` | disadvantage: a cost, a gap, or a risk |
| `X` | antipattern: a known-bad practice, in the language or in the process |
| `R` | recommendation: an alternative design, better than the current one |

| Area | File | Topic |
|---|---|---|
| `RPJ` | [01-project.md](01-project.md) | process, spec, tests, decisions, licensing, positioning |
| `RSY` | [02-syntax.md](02-syntax.md) | lexical rules, sigils, closers, assignment, keywords |
| `RTY` | [03-types-data.md](03-types-data.md) | types, collections, numbers, text, data types for ETL |
| `RSB` | [04-subprograms-classes.md](04-subprograms-classes.md) | functions, methods, `!`, `@`, generators, classes, traits |
| `RST` | [05-structure-errors.md](05-structure-errors.md) | driver, aspect, module, imports, scopes, jobs, `recover` |
| `RMT` | [06-multitasking.md](06-multitasking.md) | parallel aspects, channels, generators, scheduling |
| `RVM` | [07-vm.md](07-vm.md) | the Zig VM: interpreter, memory, values, bytecode, WASM |
| `RIO` | [08-data-io-etl.md](08-data-io-etl.md) | files, formats, databases, the ETL model |
| `RNW` | [09-client-server-web.md](09-client-server-web.md) | client/server architecture, protocol, HTTP, HTML, WebAssembly, security |
| `RTU` | [10-tutorial-plan.md](10-tutorial-plan.md) | the plan to extend the tutorial with these features |

## Verdict in one paragraph

Eve has one genuinely strong idea that most scripting languages lack: the **aspect**, an isolated unit of work with copy-in parameters, owned `@` outputs, per-call state, a job/`recover`/`retry` error model and a barrier-based `parallel` block. That is exactly the shape of a server request handler, a remote procedure and an ETL step, so the client-server future fits the language better than its current documentation suggests (`RST-A01`, `RNW-A01`). The weaknesses are elsewhere: a syntax overloaded with sigils and three closers on top of mandatory indentation (`RSY-X01`, `RSY-D01`), a type system without the data types ETL lives on (Decimal, Timestamp, Bytes, Record — `RTY-D01`), a standard library that does not exist yet (`RIO-D01`), a spec that lags behind tests and the VM (`RPJ-X01`), and a decision rate (≈70 decisions in 6 days, loop syntax revised five times) that no tutorial reader or second implementer can follow (`RPJ-X02`).

## Top 12 actions, in order

| # | Code | Action |
|---|---|---|
| 1 | `RPJ-R01` | Freeze the core syntax for 0.1 (a "syntax moratorium"); new ideas go to a 0.2 backlog |
| 2 | `RPJ-R02` | Write the EBNF from the existing parser now; make the spec, not the tests, the source of rules |
| 3 | `RSY-R01` | Pick one block terminator story: closers *or* significant indentation, not both |
| 4 | `RTY-R01` | Add `Decimal`, `Timestamp`/`Instant` with time zone, `Bytes`, `Record`/schema types |
| 5 | `RTY-R03` | Make `parse` and conversions fail loudly; remove silent decimal loss and `"a" + 1` |
| 6 | `RVM-R01` | Move from tree walking to a bytecode VM before generators and parallel work |
| 7 | `RVM-R02` | One arena per aspect call: the language already gives the lifetime for free |
| 8 | `RIO-R01` | Specify the 0.1 standard library surface: `fs`, `path`, `json`, `csv`, `http`, `db` |
| 9 | `RNW-R01` | Treat an aspect as the unit of distribution: local `apply` and remote `apply` share one contract |
| 10 | `RNW-R03` | Use HTTP for the web, and a small framed binary protocol (EWP) for Eve-to-Eve data streams |
| 11 | `RNW-R06` | Compile the VM itself to WebAssembly first; ship portable bytecode, not source |
| 12 | `RNW-R08` | Capabilities (fs, net, db, shell) declared per project and granted per aspect |

## What was read

`README.md`, `plan/` (README, both decision logs, `design-multitasking.md`, `design-issues.md`, phase files), `spec/` tree, tutorial pages (index, manifest, databases, processing, topology, command, library, multitasking, types and classes in part), `evevm/` layout, `interp.zig` header and types, `lib/io.eve`, level 1 and level 2 tests. Points that rely on an inference rather than a quote say so.
