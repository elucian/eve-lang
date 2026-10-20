# Critical review of Eve, second round (2026-10-20)

A design review of the project as of `master` on 2026-10-20: levels 1 to 6 implemented (409 tests agree on the tree walker and on the bytecode machine), the architecture of D-198 to D-201 done, level 7 (the web, evewp) not started. It replaces the review of 2026-10-04 (commit `f6500d3`, before the VM had a data layer or a server), which is kept whole in [`../archive/review-2026-10-04/`](../archive/review-2026-10-04/README.md): its codes (`RPJ-R01`, `RNW-R02`, …) are cited by decisions and by the feature map and stay valid there.

The review is critical on purpose: praise is short, every problem comes with evidence (a file, a command, a number) and an alternative. What was read and run is listed at the end, so that a point that rests on an inference can be told from one that was measured.

## How to cite a point

Codes are `R2-<area><kind><nn>`, for example `R2-PR-D01`. They are never renumbered; an obsolete point is struck through. The `R2-` prefix keeps them apart from the first round (`R<area>-…`), from issues (`SYN-`, `CLS-`, …) and from decisions (`D-nnn`, `Q-nnn`).

| Kind | Meaning |
|---|---|
| `A` | advantage: keep it, build on it |
| `D` | disadvantage: a cost, a gap, a risk |
| `R` | recommendation: what to do about a `D` |

| Area | File | Topic |
|---|---|---|
| `FU` | [follow-up.md](follow-up.md) | what became of the 12 actions and the main points of the first round |
| `PR` | [findings.md](findings.md#process-and-tracking) | tracking, tests in CI, releases, the order of the work |
| `VM` | [findings.md](findings.md#the-machines-and-the-code) | the two engines, memory, performance, code shape |
| `SC` | [findings.md](findings.md#security-and-the-machine) | doors, permissions, login before level 7 |
| `DT` | [findings.md](findings.md#documents) | spec, manual, tutorial, issues, decisions |
| `L7` | [findings.md](findings.md#level-7) | the web level and the Eve Web Portal |

## Verdict in one paragraph

The first round asked for a spec made from the tests, a bytecode VM, a data layer and a server; levels 1 to 6 now exist, they agree on two engines, and the speed is near or above CPython on every benchmark (worst: `p3a_modules` 1.4 times Python). That is a strong position. The risks moved from the language to the **tracking and the process**: the feature map says "open" for features that have tests and code (23 of 31 features of version 0.4 and 18 of 24 of version 0.5 are marked open while levels 5 and 6 pass), nothing runs the 409 tests but the author's machine (no CI, a test binary failed once during the review and passed on the next run), the doors of the machine allow everything until a login that is planned for level 7, and level 7 depends on a WebAssembly build that has not been tried once. None of these is large work; all are cheaper to fix now than after the web level starts.

## Top 8 actions, in order

| # | Code | Action |
|---|---|---|
| 1 | `R2-PR-R01` | Make the status of a feature follow the tests: `@feature` in the test, a script that sets `done` when its tests pass, and bring the rows of versions 0.4 and 0.5 up to date |
| 2 | `R2-PR-R02` | Run `zig build test`, `runtest.py all --both` and `tagcheck.py` in CI (GitHub Actions, Windows and Linux) on every push |
| 3 | `R2-VM-R01` | Find the flaky unit test (the binary run with `--listen`) before more network tests are added |
| 4 | `R2-SC-R01` | Settle the rule for the doors: the default is loopback (`config.zig`, `http_host = "localhost"`) but the spec still marks "another address only on purpose" as proposed; test that `POST /rpc` refuses a foreign `Host` and `Origin` (a page in the user's browser can post to `localhost`), and that `vm.eval` and `os.run!` are unreachable from it until `auth` exists |
| 5 | `R2-L7-R01` | A two-day spike before level 7: the VM (or a small core) built for `wasm32`, running `hello.eve` in a page; go or no-go for D-193 |
| 6 | `R2-DT-R01` | Close or archive the open questions: 16 are open, the oldest from 2026-10-06; level 5 and 6 decision logs stay above 25 KB because of them |
| 7 | `R2-DT-R02` | Refactor `design/issues/` (24 open items about tutorial pages, which are last in the order): see `findings.md#issues-folder` |
| 8 | `R2-VM-R02` | Finish the bridge of the bytecode machine (TD-46) before the `.evb` file and before level 7 builds on it |

## What was read and run

Run on 2026-10-20: `plan.py status` and `features`, `runtest.py smoke`, `runtest.py all --both` (409 pass), `zig build test` (one failure, then a pass), `ctxsize.py`, `tagcheck.py`, `genmanual.py --check`, `bmark` table in `test/bmark/README.md`. Read: `design/README.md`, `design/feature_map.md` (rows by command), `design/phase-8-architecture.md` (head), `backlog/tech-debt.md`, `backlog/library-gaps.md`, `design/issues/README.md`, the first round's README. Not read this round: the tutorial pages, the spec pages in full, the code of the interpreter beyond its file heads. Points about those are marked "inference".
