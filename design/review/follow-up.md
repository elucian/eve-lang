# Follow-up of the first round (2026-10-04)

Each of the 12 actions of the first round, with what the tree shows on 2026-10-20. The evidence is a file or a row of `design/version_map.md` (`python script/plan.py feature F-XXX-nn`). Codes `R2-FU-nn` are the numbers of the old actions.

| # | Old code | Action | Status | Evidence |
|---|---|---|---|---|
| 1 | `RPJ-R01` | Syntax moratorium for 0.1 | not found | no decision mentions a moratorium (`grep -il moratorium design/decision/*`); the syntax kept changing through D-179 and D-192, which the author may have wanted |
| 2 | `RPJ-R02` | EBNF from the parser; the spec as the source of rules | done | `spec/syntax/grammar.md` checked against the tests by `script/grammarcheck.py`; `spec/` has lexical, syntax, semantics and library pages |
| 3 | `RSY-R01` | One block-terminator story | done by keeping the closers | files end with `end name;` and `return;`; no indentation rule (inference from the examples and the file shape in `design/dev-guide.md`) |
| 4 | `RTY-R01` | `Decimal`, `Instant`, `Bytes`, records | partly | `code/evecm/src/decimal.zig`, `instant.zig`, records and `table` in level 5; no `Bytes` type in `spec/semantics/types.md` |
| 5 | `RTY-R03` | Conversions fail loudly; no `"a" + 1` | done | `code/evecp/src/check.zig` refuses a string added to a number (D-080) |
| 6 | `RVM-R01` | Bytecode VM before generators and parallel work | in progress, late | generators and parallel groups were built on the tree walker; the register machine (D-201) covers the core and bridges the rest (TD-46); F-VM-04 `partial`, F-VM-07 `.evb` open |
| 7 | `RVM-R02` | One arena per aspect call | not taken, other design | D-151: reference counting, a tracing collector as backup, regions freed at `done`; `p4e_garbage` shows 6 MB peak |
| 8 | `RIO-R01` | The 0.1 standard library surface | done and more | `lib/` and 15 pages in `spec/library/` (fs, json, csv, http, database, os, net, route, rpc, …) |
| 9 | `RNW-R01` | The aspect as the unit of distribution | open | F-NET-04 remote apply is `open`; the machine runs scripts remotely through `vm.*`, not an `apply … at <machine>` |
| 10 | `RNW-R03` | HTTP for the web, EWP for Eve-to-Eve | half | HTTP server and client exist (`service`, `http`, level 6); F-NET-03 EWP is `open` (only the EWP-db control port of `drivers/duckdb`) |
| 11 | `RNW-R06` | The VM compiled to WebAssembly first | open | F-VM-09 `open`; never tried (see `R2-L7-R01`) |
| 12 | `RNW-R08` | Capabilities per project, granted per aspect | open | F-NET-05 `open`; TD-10: `fs` and `os` call the system directly (see `R2-SC-R01`) |

Score: 4 done, 3 partly or late, 1 taken another way, 3 open (all three belong to the network and web levels), 1 not found.

## Points of the first round that changed

- `RVM-D*` (speed): the fear of a slow tree walker is gone. Every benchmark is between 0.0 and 1.4 times the time of the CPython twin (`test/bmark/README.md`), the bytecode machine is 2 to 2.5 times faster than the walker on arithmetic and calls (`p1a_arith` 64 ms against 26 ms).
- `RPJ-D*` (process): the spec now follows the tests as the author ordered (D-194); the weak point moved from "no spec" to "the tracking is out of date" (`R2-PR-D01`).
- `RNW-D*` (security): capabilities and login are still open (rows 9 and 12); see `R2-SC-D01` (inference: the points of the first round were not re-read one by one).
