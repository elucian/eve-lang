# Assessment: bytecode VM vs. a native compiler, a JIT, or AOT for `lib/`

Status: **settled** 2026-10-26 as D-241 (`decision/level6.md`): keep the bytecode, no native compiler and no JIT; AOT of `lib/` later, not scheduled; optimize the bytecode now (`design-bytecode-opt.md`).

## Short answer

A full native compiler would make scalar code (loops, arithmetic, calls) 5 to 20 times faster than the bytecode machine. It would do little for the work Eve exists for. In the benchmarks, ETL, database and HTTP time is spent in the runtime, the drivers and I/O, not in dispatch. You can get most of the value of "it makes an exe" for a few days of work by embedding the bytecode bundle in `eve.exe`.

The best ratio of gain to effort is **AOT compilation of `lib/` through Zig**. Of the three options a JIT has the worst ratio for Eve.

## What the measurements say today

Numbers are from `test/bmark/README.md` and `design/design-bytecode.md` §15:

- **Where bytecode already helps:** on the code it translates, it is about 2.5 times faster than the tree walker. `p1a_arith` goes from 108 to 43 ms and `p1b_calls` from 86 to 30 ms. About 7 ms of each run is start-up.
- **Where it is slower:** `p2c_procedures`, `p3b_objects`, `p4b_channel` and `p6d_olap_groupby` run slower on bytecode because of the bridge to the tree walker. B5.3 to B5.6 are not done.
- **Levels 5 and 6 (SQL, evedb, PostgreSQL, HTTP):** the two engines are within ±10% of each other. The interpreter is not the bottleneck there, and no compiler changes that.
- **Already beating Python:** strings, collections, tasks, channels and DB work are 0.2x to 0.7x of Python's time.

So the bytecode VM is not finished, and the bridge costs more now than dispatch does. Any compiler built today would sit on top of an unfinished engine.

## The options

| | Bundled exe (VM + `.evb` inside) | AOT for `lib/` (Eve → Zig, built at release) | Full AOT compiler of user code to exe | JIT (in 0.8 under D-201) |
|---|---|---|---|---|
| What the user gets | one exe to ship, no compile step | every program gets faster where it calls the library | the fastest programs, one native exe | faster long runs, transparently |
| Effort (one author with AI) | days to a week | 2 to 4 months | 6 to 12 months, then maintenance forever | 9 to 18 months, one backend per CPU (x64, arm64) |
| Engines to keep in agreement | none new | the native lib must match the Eve lib (`--both` covers it) | a third engine | a third engine, and the hardest to debug |
| Breaks or limits | nothing | nothing visible to users | REPL, remote apply, sandbox, WASM (see below) | W^X memory on Windows, hardened hosts, WASM (no JIT there) |
| Risk | low | medium | high | very high |

## Predicted gains over the finished bytecode machine

These are engineering estimates, not measurements. They assume B5 is complete and the 0.8 `Value` change has landed.

| Workload | Bytecode tuning (typed opcodes, superinstructions, 16-byte `Value`) | AOT for `lib/` | Full AOT | JIT |
|---|---|---|---|---|
| Scalar loops, arithmetic (`p1a`) | 1.3 to 2x | ~1x | 5 to 20x (when the types are known) | 3 to 10x |
| Calls, objects, modules (`p1b`, `p3*`) | 1.3 to 2x | ~1x | 3 to 8x | 2 to 5x |
| Strings, collections (`p1c`, `p1d`) | 1.1 to 1.3x | 1.2 to 2x | 1.2 to 2x | 1.2 to 1.5x |
| Library-heavy code (dates, finance, rows, quality) | ~1.2x | 2 to 5x on those calls | 2 to 5x | 1.5 to 3x |
| Tasks, channels (`p4*`) | ~1x | ~1x | ~1x (the scheduler sets the pace) | ~1x |
| SQL, evedb, HTTP (levels 5 and 6) | ~1x | ~1.05x | 1.0 to 1.1x | ~1x |
| Start-up (7 ms) | lower with a pre-compiled bundle | the same | ~1 to 2 ms | higher (warm-up) |

For a typical Eve program (read data, change it, write it), I expect a full AOT compiler to make the whole run **1.1 to 1.5 times faster**. A numeric-kernel benchmark would show 10x, but users rarely run that kind of code.

## Limitations you would accept with a full compiler to exe

1. **Multitasking.** Tasks and generators park at any blocking call (the baton model of D-144, `.park` in `bcvm`). Native code needs stackful coroutines (one stack per task, with a context switch written per OS and CPU) or a CPS/state-machine transform of every routine that can block. This is the hardest part, and it is the "stabilize multitasking" work you just did, done a second time.
2. **The machine model of level 6.** Remote apply (S6.8), the verifier and the capabilities sandbox (S6.7) work because bytecode is portable and can be checked before it runs. Native code can't be verified the same way: a machine would have to trust signed binaries, which is a different security model.
3. **REPL, debugger, hot reload.** These stay on the VM. So the compiler adds a third engine (it does not replace one), and the tests need a `--three` mode.
4. **WASM and evewp.** The web plan (S7.0) compiles "from the same chunk". A native compiler is a separate path.
5. **Build time and toolchain.** Emitting Zig (the realistic way, since the runtime is Zig) means users need the Zig toolchain (about 50 to 80 MB), and builds take seconds to minutes instead of milliseconds. Zig changes between versions, so the emitted code breaks on each upgrade.
6. **Dynamic edges of the language.** Untyped documents from `open(source)`, arguments "whose class is not known at compile time" (`types.md`), and `sql function` callbacks from DuckDB threads all fall back to boxed `Value` code. Most of the 10x then goes away.
7. **Per-platform release work.** Every OS and CPU becomes its own target to test, and size budgets apply per exe (`eve.exe` is already 4.2 MB).

## Why a JIT is the weakest option here

A JIT pays off for long, hot, numeric loops in programs nobody compiles in advance, as in JavaScript or Lua. Eve programs are short scripts bound to the database or I/O, and its strengths are safety and verification. A JIT adds executable memory (a target for security reviews and blocked on some hardened Windows hosts) and a backend per CPU, and it can't run in WASM. A copy-and-patch template JIT is the cheapest kind, but it gives only 1.5 to 3x over a good register VM. Typed opcodes plus the `Value` change get you most of that.

## Why AOT for `lib/` is the best bet

- **Fixed and tested:** the library is known at release time and covered by the conformance tests. No user ever waits for a build.
- **Keeps the policy:** D-229 keeps the library in Eve, and AOT lets it run at Zig speed.
- **Works for everyone:** every program gains, and nothing in REPL, sandbox, remote apply or WASM changes.
- **Doubles as a prototype:** the emitter (resolved tree → Zig) is the front half of a full AOT compiler. If the gains on `lib/` are good, you will have measurements before committing to the full compiler.

## Value of your work

What makes Eve worth adopting: it is a data and test DSL, it ships as one binary, and it has verified, sandboxed and remote execution, with database speed that already beats Python. "Compiles to native" is a strong marketing line. In practice it competes with Go and Rust on their ground, and moves effort away from levels 5 to 7, where Eve is different. The bytecode VM is not a "simple" step to grow out of. It is what makes `.evb` shipping, verification, the sandbox and WASM possible.

## Recommended order

1. **Finish B5.3 to B5.6** so the bridge goes away. That removes today's slowdowns.
2. **Add `eve build --exe`:** the runtime with the project bundle appended. You get the exe for days of work.
3. **Typed opcodes and the `Value` layout change** (already planned for 0.8).
4. **AOT for `lib/` through Zig, in place of the JIT in 0.8.** Measure it on `p1g` to `p1j` and on the L6 to L9 library tests.
5. **Decide on full AOT for user code** only after step 4, with profiles from real ETL scripts.

Step 4 would change D-201 (it settled "JIT in version 0.8"). That decision is yours, so I have not edited anything. I can write this up as a question in `design/decision/` with the options above if you want.
