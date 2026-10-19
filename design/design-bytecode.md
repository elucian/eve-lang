<!--# Bytecode design-->

Status: **answered** 2026-10-19: the author answered Q-B1 to Q-B9 (settled as D-201); the stages wait for the order of the work (level 5 and 6 blockers first). Step S8.12 of `phase-8-architecture.md`, step B5 of `design-packages.md` §10. Builds on RVM-R01, R03 and R05 of `review/07-vm.md`, D-144 (baton tasks), D-151 (reference counted heap), D-163 (modules), D-194 (order of the work). The answers of the author are in §13 and in D-201 (`decision/level6.md`).

## 1. Goal and the steering rule

The goal is a VM that runs Eve faster and with less memory than the tree walker, in a form that can be saved (`.evb`), shipped to another machine, checked before it runs, and stopped and continued (generators, parked tasks) without an operating-system thread per task.

The author asked that **the refactoring is steered toward the bytecode**. The rule for every refactor and optimization from now until B5 is done:

> A change is worth doing now if it removes work from the tree walker **and** the bytecode emitter or VM would need it anyway. A change that only makes the tree walker faster, and that the bytecode would throw away, waits.

§4 lists the changes that pass this test, in order. Each is measured with `bmark.py` before and after (D-196: a refactor and an optimization start with a measure) and keeps all levels green on the tree walker, so the bytecode never starts from a moving base.

## 2. What the tree walker costs today

These are facts from the code (2026-10-19), they are what the bytecode removes.

| Cost | Where | Effect |
|---|---|---|
| Variables are found by **name**: a linear walk of the chain of scopes, comparing strings | `Scope.find` in `comp/evecm/src/value.zig`, `Interp.lookup` | every read and write of a variable is a string search; deeper scopes cost more; this is the first planned optimization ("slot-resolved variables") |
| Operators are **strings**: `apply(it, op: []const u8, ...)` compares the operator with up to twenty literals in a row | `interp/expr.zig` `apply` | an `a + b` of two integers passes through a chain of `eql` calls before it adds |
| Number literals are **parsed at every evaluation**: suffixes, commas, durations, then the conversion | `interp/expr.zig` `number` | a literal in a loop is parsed again each turn |
| Every statement pays for the **scratch mark, the debugger test, the hook test, the cancel test and the line store** | `interp/stmt.zig` `exec`, `tick` | fixed cost per statement, even with no debugger |
| Control flow is a **Zig error** (`Signal`): `break`, `skip`, `over`, `raise`, `retry`... unwind the Zig stack | `value.zig` `Signal` | a loop that ends with `break` pays an error return through every frame; a call frame is a Zig frame, so depth is limited by the thread stack |
| A task or a generator is an **operating-system thread** that hands the baton to the next | `evevm/src/task.zig`, `interp/generators.zig`, `interp/parallel.zig` | creating a task costs a thread (p4c: 250 groups of 4 tasks take 130 ms); a generator needs two threads' worth of switching per `yield` |
| A function value is a **node and a scope** (`Func{ node, closure }`); a call binds parameters by name in a new `Scope` with a `std.ArrayList` of bindings | `value.zig` `Func`, `interp/calls.zig` `bindParams`, `runRoutine` | an allocation and a string-keyed table per call |
| `Value` is a tagged union with **24 bytes at least** (a string is a 16-byte slice and a tag); `int`, `nat`, `byte`, `short`, `huge` are five tags for the same `i64` | `value.zig` `Value` | memory traffic; to be measured in R0 (§4) |
| The syntax tree lives in `evecm` and is **reached by the runtime** (`Class.node`, `Module.node`, `Func.node`, the database layer reads nodes) | `value.zig`, `ast.zig` | the runtime cannot run without the parser's data; the `.evb` file can not exist until the runtime stops needing nodes |

Benchmarks to move (`test/bmark/README.md`, ReleaseSafe, against the Python twins): `p1a_arith` 3.5x, `p1b_calls` 1.9x, `p3a_modules` 2.5x, `p3b_objects` 2.3x, `p4a_parallel_sum` 2.9x, `p4e_garbage` 2.3x. The rest are at or below 1.5x.

## 3. The target

### 3.1 Pipeline

```
source ──lexer/parser──▶ syntax tree ──check (+ resolve)──▶ resolved tree ──emit──▶ Chunk(s) ──▶ .evb file
                                                                                       │
                                                                          evevm: load + verify + run
```

- **evecp** owns everything left of the chunk: lexer, parser, check, the new **resolve** pass (slots, captures, operator ids, constants), overload resolution, and the **emitter**. `ast.zig` moves from `evecm` to `evecp` at the end (§9, R7).
- **evecm** owns what both sides share: the instruction set (`op.zig`), the `Chunk` and `.evb` layout (`chunk.zig`), the values and the heap.
- **evevm** owns the VM: loader, verifier, frames, dispatch loop, natives. After B5 it does not import `ast.zig`.

The tree walker stays, as a second engine (`--engine tree`), until every level passes on the bytecode VM and one release has shipped (§10). It is the **oracle** of the tests: the same program must print the same bytes on both.

### 3.2 Register machine, not stack machine

Proposal: a **register machine** in the style of Lua 5. Each function has a fixed number of registers (`nregs`, computed by the emitter); a call takes a window of the value stack; instructions name their operands as register numbers.

Why register and not stack:
- `a := b + c` is one instruction (`add r_a, r_b, r_c`) instead of four (`push b; push c; add; store a`). Fewer dispatches is the largest cost in an interpreter loop, and it is what makes `p1a_arith` fast.
- Locals are registers, so the slot resolution of R2 is exactly the register allocation: no second pass.
- Cost: the emitter is a little harder (a register allocator for temporaries), which is small work for a language with structured control flow and no goto.

### 3.3 Instruction encoding

32-bit instructions, fixed width, in a `[]u32`:

```
 31      24 23     16 15      8 7       0
+----------+---------+---------+---------+
|    C     |    B    |    A    |   op    |     iABC   three registers or small operands
+----------+---------+---------+---------+
|        Bx (16 bits)           |    A    |   op    |   iABx    one register and a constant index or jump
+----------+---------+---------+---------+
```

- `op` is a `u8` enum (`Op`, at most 256). A (and B, C) are registers 0 to 255 of the frame; a function needing more registers fails to compile with a clear error (a limit, to lift by a `wide` prefix later, TD entry when it is first met).
- Jumps are signed offsets in `sBx` (±32 K instructions); a longer jump uses `jmpw` with the next word as a 32-bit offset.
- Dispatch uses the labeled `switch` of Zig (`sw: switch (op) { .add => { ...; continue :sw next(); } }`), which the compiler turns into threaded dispatch. A computed-goto-like loop with no `Signal` return in the hot path.
- Register values are `Value` (§3.4). Integer and real instructions come in **typed forms** (`addi`, `addr`) that the emitter picks when the checker knows both types, and a **generic form** (`add`) that tests the tags. A typed form skips the tag test but keeps an overflow check (`err_overflow` exists).

### 3.4 Values

The bytecode VM keeps the `Value` union of `evecm` as it is, **in R0 to R6**: changing the value layout touches the database layer, the libraries and every test, and is a separate decision (Q-B6). What the refactor does now to `Value` is measure it (`@sizeOf`), and group the five `i64` integer tags behind one tag plus a width in a later step if the measure shows the memory cost. Reference counting stays (D-151): the VM calls `retain` when a register is written with a counted value, `release` when it is overwritten and when the frame ends (a `clear` of the window). `EVE_GC_VERIFY=1` must work on the bytecode VM from the first stage.

### 3.5 Frames and the stack

- One **value stack** per task (`[]Value`, grown by doubling, never moved while a native holds a pointer into it: natives receive a slice and copy what they keep).
- One **call frame record** per call: `{ func: *Code, pc: u32, base: u32, ret_reg: u8, handlers: u16, defer_mark: u32 }` on a separate frame stack. Both stacks are plain arrays owned by the task. **A call does not recurse in Zig**: `call` pushes a frame and continues the loop; `ret` pops. Depth is limited by memory and by a counter that raises `StackOverflow`, not by the thread stack.
- Because a frame is data, **a task is its two stacks and a state**. Parking a task (channel full, `wait`, `sleep`, `yield`) saves nothing: the loop simply returns `.park` to the scheduler and resumes later at the same `pc`. This is what lets §6 drop the thread per task.

### 3.6 Variables, captures and the three kinds of scope

Today's `Scope` is the only kind. The resolver (R2) splits it in three and gives each a fast path:

| Kind | Storage | Instructions |
|---|---|---|
| **Local** of a function or block | a register of the frame | none: the operand of the instruction is the register |
| **Captured local** (read or written by a closure, a lambda, a nested routine, or a `start`ed aspect) | a heap cell `Var` (it exists already: `Var` is a reference counted cell with `constant`), held in the register as a `cell` value | `getcell`, `setcell`; the closure holds its cells in an array (`upvals`) copied at `closure` creation |
| **Module and aspect state** (`export`, `private` variables of a module; the `unit` scope of an aspect) | an array of cells in the `Module` or aspect instance, addressed by index | `getmod`, `setmod` (index into the module's table; a call to another module's export is `getext` by an index fixed at link time) |

The checker already knows which names are captured (it reports undefined names and visibility); the resolver adds the decision "boxed or not" to each `var_decl`. Semantics preserved: `:=` shares a collection, native values are copied (D-049); a captured variable is shared by every closure that sees it, as the `Var` cells are today.

### 3.7 Control flow and errors

| Eve | Bytecode |
|---|---|
| `if`, `while`, `repeat`, `for`, `match`, `break`, `skip`, `over` | conditional and unconditional jumps; `for` over a range or list uses `forprep`/`forloop` (counter in registers, no iterator object for ranges and lists; an iterator register for sets, maps, tables and generators) |
| `raise`, a failing native or instruction | the loop **returns an error object to its own unwinder**, not a Zig error: it looks in the function's **handler table** `[(pc_from, pc_to, handler_pc, kind)]` for a `recover`, else pops the frame and repeats |
| `recover`, `retry`, `resume`, `abort`, `stop` | a handler entry per `recover` block; `retry` is a jump to the start of the guarded block after the defers ran; `resume` a jump after the failing statement (the handler table stores the resume pc); `abort` and `stop` unwind to the process or the job frame (marked `boundary`) |
| `defer` | `defer r` pushes a closure on the frame's defer list; at `ret` and during unwinding the VM runs it (the `runDefers(mark)` of today, driven by `defer_mark`) |
| `job`, `rollback`, `commit` | `jobbegin`, `jobend`, `jobrollback` instructions around the body; the unwinder knows a `job` boundary and calls rollback (the `JobRollback` signal of today) |
| `Panic`, `Exit`, `Cancel` | not catchable: the unwinder passes through every handler to the boundary |
| Errors with a code, a line and a trace (`Report`, D-113) | the line table (§7) gives the line at the failing `pc`; the trace is built from the frame stack, innermost first, as today |

The tick work (§2) becomes one **flag test per backward jump and per call** (`it.hook_pending`, a single byte set by the debugger, the cancel flag and the step budget), not a test per statement.

### 3.8 Calls

- A **call site** is `call A, B, C`: callee in register A (a `func` value), B arguments in the next registers, C results wanted. Named and optional arguments (D-106) are resolved by the emitter into positions when the callee is known (overload resolution is already `evecp/overload.zig`); a call through a function value with named arguments uses `callnamed` with a table of names in the constant pool.
- `@` parameters (by reference, with write-back of an element `@s[i]`): the emitter allocates a `Var` cell for the argument and the call copies back at `ret` as `writeBack` does today.
- A **natives** table replaces the lookup by name of `dlib`/`syslib`/`netlib`: the library is linked at load time, each `external` name becomes an index into the native table (`callnat idx`). An unknown native is a load error, not a run error. A native has the signature `fn (vm: *Vm, args: []Value, out: *Value) Signal!void` that exists today in `dlib.zig` in spirit; the adapter is generated in R5.
- **Methods and objects**: `Class` gets a method table indexed by an id the resolver gives each method name (`callm`), with the inline cache of the last class seen in the instruction's spare word. Overloading stays resolved at compile time when types are known, and at run time through the same `overload` module when not.
- **Tail position** is not optimized in the first version (Q-B7).

### 3.9 Generators, tasks and the scheduler

This is the main gain over the tree walker, and the reason RVM-R01 asked for the bytecode.

- A **generator** is a function value whose call creates a `Gen` object holding a task-less pair of stacks; `yield` stores the value and returns `.yielded` from the loop; the next read of the generator re-enters the loop at the saved `pc`. No thread, no baton.
- A **task** (`start`, `spawn`, a `job`'s async procedures) is a pair of stacks and a state. The scheduler of D-144 keeps its order of creation, its progress counter and its deadlock detection, and becomes a plain loop: `while (ready) { run(task) until .park or .done }`. The result is still deterministic (spec/semantics/multitasking.md#determinism) and now **runs on one thread**, which also removes the "interpreter is not thread safe" argument.
- A blocking native (channel send or receive, `wait`, `sleep`, a socket read) returns `.park` with the reason (`Wait` of `task.zig` is kept); the scheduler marks the task and the loop resumes at the same instruction.
- Real parallelism on several cores (D-183, Q-061) is **not** part of B5; the design leaves room: a task owns its stacks and its heap region, so a later step can run groups on worker threads with channels as the only shared objects.

### 3.10 The database layer and `sql`

Tables, `sql` blocks, `sql function` and stored procedures keep their text in the constant pool and run through the existing `db` module by native calls (`sqlrun`, `tablefield`, `ormstore`...). Nothing in `comp/evevm/src/db/` needs the syntax tree after the move except where it reads `Node` today (`orm.zig`, `importer.zig`); those places are listed by R7 (§9) and receive a plain description (`TableDef`, fields and types) built by the emitter instead of a node.

## 4. The refactoring ladder (do these first, on the tree walker)

Each step passes all levels on the tree walker, has a before and after measure, and states what it gives the bytecode. Nothing in this ladder is thrown away.

| Step | Change | Gives the bytecode | Expected effect on the tree walker |
|---|---|---|---|
| **R0** (done 2026-10-19) | Measure: `@sizeOf(Value)`, the `Node` count and depth per benchmark (`ast.Stats` exists), a profile of `p1a`/`p1b`/`p3b` (where the time goes), the peak memory. Record in `test/bmark/README.md` as the base of the bytecode. | the base line, and the proof that a step helped | none |
| **R1** (done 2026-10-19: `p1a_arith` 195 to 75 ms, `p1b_calls` 62 to 45 ms) | **Operators and literals become data at parse time**: `Node` gets `op: Op` (an enum of the operators, `u8`) and a pre-converted literal (`lit: Value`-like constant: integer, real, decimal, duration, symbol, string). `apply` switches on the enum. | `Op` is the operand of `add`, `lt`...; the constant pool is the table of the literals; `number()` is split once into a function that the emitter calls | `p1a` faster: no string chain, no re-parse |
| **R2** (done in part 2026-10-19: text comparisons removed, full slots postponed to the emitter, see `test/bmark/README.md`) | **Slot resolution in `check.zig`** (planned already, "slot-resolved variables waits for the final scope rules"): each `name`, `var_decl`, `assign` and `param` node receives `(depth, index)` or a register number; each function gets `nlocals`; captured variables are marked. `Scope` keeps its list for the dynamic cases (`$epsilon`, the REPL, `eval` of text) and the fast path reads by index. | the register allocation of the emitter *is* this pass; the capture analysis of §3.6 | `p1a`, `p1b`, `p3a`, `p3b`, `p2b` faster: no string search |
| **R3** (measured 2026-10-19: no gain, dropped) | **The statement prologue is cheap**: the debugger, hook, cancel and step counters are tested by one flag (`it.slow`), set only when one of them is on; the scratch `mark`/`release` happens per statement that needs it (an expression statement, a print), not for every statement. | the "one flag per backward jump and per call" of §3.7 | every benchmark a little faster |
| **R4** (partial 2026-10-19: needs R2) | **Calls without a `Scope` allocation for plain functions**: with R2, a call frame is an array of `Var` or `Value` of `nlocals` taken from a per-task stack; `bindParams` writes into it. | the frame layout of §3.5 | `p1b`, `p2c`, `p3b` faster |
| **R5** | **The library behind an index**: `external` names and `dlib`/`syslib`/`netlib` functions are registered in one table (`name`, `id`, `fn`) and called by id; a name resolves to its id once, at link time (check or load). | `callnat idx` and the load-time link | small; removes string compares in library calls |
| **R6** | **Errors and signals as data where it is cheap**: `break`, `skip`, `over` in loops become a returned status of `execBlock` (an enum), not a Zig error; `raise` keeps `Signal` in the tree walker. | the jumps of §3.7 | `break` in a hot loop faster |
| **R7** | **The tree leaves the runtime**: `Func`, `Class`, `Module`, `Started`, `GenState` hold a `*Code` (a description: name, params, kind, body) instead of `*const Node`, built from the node by a function in `evecp`; the tree walker reads the same description and keeps the node for its body. After this, `evevm` imports `ast` only for the tree walker's files. `ast.zig` moves to `evecp` when the last use outside the tree walker is gone. | the loader needs no node; the `.evb` can carry the same descriptions | none (neutral), a large mechanical change |
| **R8** | **A test engine switch**: `eve --engine tree|bc` (and `EVE_ENGINE`), `runtest.py --engine`, and a mode `--both` that runs the two and compares the bytes of the output and the exit code. Until the bytecode exists, `bc` is an error "not built". | the equivalence test of §10 from the first instruction | none |

R1, R2, R3 and R4 are the largest gain for the least work and are worth doing on their own account (rank 5, optimize). R7 is the risky one and is done last of the ladder, when the bytecode is nearly ready to take over.

## 5. Instruction set (first version)

About 90 instructions. Names are proposals; the final list is in `comp/evecm/src/op.zig` with the `@spec` tags.

| Group | Instructions |
|---|---|
| Load and store | `move`, `loadk` (constant), `loadnil`, `loadtrue`, `loadfalse`, `loadint` (small immediate), `getmod`, `setmod`, `getcell`, `setcell`, `newcell`, `getext` |
| Arithmetic (generic) | `add sub mul div mod pow idiv neg`, string and list `concat`, `append`, set operations `union inter diff` |
| Arithmetic (typed) | `addi subi muli ... addr subr mulr ...`, `cmpi*`, `cmpr*` with overflow checks |
| Compare and logic | `eq ne lt le gt ge`, `approx` (`=~`), `in`, `is`, `not`, `and`, `or`, `xor` (the short-circuit forms are jumps) |
| Jumps | `jmp`, `jmpw`, `jt`, `jf`, `jnil`, test-and-jump forms of each comparison (`jlt a b off`) |
| Loops | `forprep`, `forloop` (ranges), `iterinit`, `iternext` (list, set, map, table, generator), `rangemake` |
| Collections | `newlist`, `newarray`, `newset`, `newmap`, `getidx`, `setidx`, `getfield`, `setfield`, `slice`, `spread`, `len`, `listappend` |
| Objects and classes | `newobj`, `getattr`, `setattr`, `callm`, `isclass`, `constructor` |
| Calls | `call`, `callnamed`, `callnat`, `callm`, `callvalue`, `ret`, `retmulti`, `closure`, `tailcall` (reserved) |
| Strings and formats | `interp n` (build a string from n registers), `fmt` (with a format constant), `strlen` |
| Errors | `raise`, `assert`, `expect`, `panic`, `defer`, `jobbegin`, `jobend`, `jobrollback`, `handler` (entries are in the table, not in the code) |
| Tasks | `start`, `spawn`, `await`, `wait`, `yield`, `groupbegin`, `groupend`, `send`, `receive`, `close` |
| Data | `sqlrun`, `tablefield`, `tableupdate`, `commit`, `rollback`, `ormstore`, `ormload` (all natives behind an opcode only if profiling shows the native table is slow) |
| Debug | `line` is **not** an instruction: the line table maps `pc` to line (§7) |

## 6. Memory

- **Constants** (strings, numbers, SQL text, names) live in the chunk's pool, which the loader maps once; a `str` value that comes from the pool points into it and is never freed (the `staticStr` of today).
- **The heap and reference counting are unchanged** (D-151). A register is a holder: writing counts, overwriting releases, the frame's exit clears the window. This is the `setVar` rule moved to registers. `EVE_GC_VERIFY=1` runs on the bytecode VM in R-stage B (§9).
- **Scratch memory** (`scratch.zig`: what a statement puts there is freed when it ends) maps to a **temporary region of the frame**: the registers above the locals. They are cleared at the end of the statement that used them only when they hold counted values (the emitter knows: it emits `clear a b` after a statement that left a counted temporary).
- **Regions per aspect call and per job** (RVM-R02) are not in B5. They are a later optimization that the frame record makes possible (`frame.region`).

## 7. The `.evb` file (RVM-R05)

A chunk file, binary, little endian, no pointers, every offset a `u32` from the start.

```
header      magic "EVEB" (4) | format version u16 | spec version u16 | flags u32 (debug lines present, ...)
            | capabilities u64 (bit set: fs, net, db, sql, tty, tasks, ...) | hash of the sections (SHA-256, 32 bytes)
            | section table: (kind u8, offset u32, size u32) x n
CONST       strings (length-prefixed UTF-8), integers, reals, decimals, durations, instants, name lists
FUNCS       one entry per function: name id, kind (function, procedure, process, method, constructor, generator, lambda, job),
            nparams, nregs, nupvals, flags (async, external, sql, private), code offset and length, handler table, defer table
CODE        the u32 instructions of all functions
TYPES       classes (name, parent, traits, fields, method table), ordinals, traits, table definitions (D-100 range), aspects (inputs, outputs, state)
MODULES     the module table: name, exports (name, kind, index), imports with the version required
DEBUG       the line table per function ((pc, line) pairs, delta coded), the names of locals and registers (for the debugger), the source file name and hash
NATIVES     the names of the externals used, in the order of the `callnat` indexes (resolved at load)
```

Rules:
- The **loader verifies** before running: magic, versions, hash, section bounds, every jump target inside its function, every register below `nregs`, every constant index below the pool size, every native name known, the capabilities allowed by the machine (a chunk that needs `net` on a machine that forbids it does not load). Verification is linear; a verified chunk runs with no bounds checks on registers in a release build, with them in a debug build.
- A **project** compiles to one `.evb` per module plus an index (`project.evx`: the modules, their versions, the entry aspect) or to one bundle; Q-B4.
- **Stability**: `format version` changes with the encoding; `spec version` is the Eve version the source follows (D-138 ties both to the version map). A VM refuses a higher format version and may read lower ones for one release.
- **Source maps**: DEBUG keeps the file name and line; `eve cp --compile --strip` removes DEBUG and the names of locals, with the consequence that traces lose lines (the code number stays).
- `eve cp --compile f.eve [-o f.evb]`, `eve vm f.evb`, `eve cp --disasm f.evb` (a readable listing with the pc, instruction, operands and the line), `eve cp --check` unchanged.

## 8. Debugging and tools

- **Breakpoints and stepping**: the line table gives the instructions of each line; a breakpoint is set by a **bit in a per-function bitmap** tested only when `it.slow` is on (R3), which the debugger sets. No instruction patching, so a chunk stays hashable. `debugger.zig` changes its hook from "before this node" to "before this pc"; the commands do not change.
- **Variables for the debugger and the machine API** (`vm.eval`, `vm.inspect`): DEBUG carries the name of each register and its live range; `vm.inspect` reads them from the frame stack.
- **`vm.eval` of an expression** compiles the text to a temporary chunk in the context of the frame (the emitter is in `evecp`, which `evevm` already imports since S8.1 to S8.7).
- **The REPL** compiles one statement at a time into a chunk and runs it; module scope variables live in the module table, so they survive.
- **Profile**: `EVE_PROFILE=1` counts instructions by opcode and by function (a counter array incremented when the flag is on), for the benchmark notes.

## 9. Stages

Each stage ends with: all tests of the levels reached pass on **both** engines (R8), `bmark.py --check` shows no slowdown above 25% on the tree walker, a paragraph in `test/bmark/README.md`, and the tech debt it created in `backlog/tech-debt.md`.

| Stage | Content | Done when |
|---|---|---|
| **B5.0** (ladder) | R0 to R6 of §4 | benchmarks improved or equal; the base line recorded; all levels green |
| **B5.1** (ladder) | R7 and R8: the runtime holds descriptions, not nodes; `ast.zig` in `evecp`; the engine switch | `zig build test` and the suite green; `evevm` has no `ast` import outside the tree walker folder |
| **B5.2** | `op.zig`, `chunk.zig`, a disassembler, the emitter for **expressions, `var`, `print`, `if`, `while`, `for` over ranges, plain function calls** (level 1 core), and the VM loop for them. `eve cp --disasm`. | `a01` to `a12` of level 1 pass with `--engine bc`; the unit tests of the emitter and the loop pass |
| **B5.3** | The rest of level 1: strings, lists, maps, sets, ranges, formats, `match`, `defer`, errors (`raise`, `recover`, `retry`, `resume`), the library through `callnat` | level 1 66/66 on both engines, byte-identical output |
| **B5.4** | Level 2 and 3: aspects, closures and cells, procedures with `@`, modules, classes, objects, traits, overloading, extension methods | levels 2 and 3 on both engines; `EVE_GC_VERIFY=1` clean |
| **B5.5** | Level 4: the scheduler without threads, `start`, `spawn`, channels, groups, `within`, `on error cancel`, generators | level 4 on both engines; `p4*` not slower than the thread version, `p4c` faster |
| **B5.6** | Level 5 and 6: the data language, tables, `sql`, `sql function`, procedures, the databases, the machine API on the bytecode VM, the debugger | levels 5 and 6 on both engines; the smoke tests |
| **B5.7** | The `.evb` file: writer, loader, verifier, `eve vm f.evb`, `--strip`, the capabilities; a file made on one machine runs on another (the exit test of version 0.7) | `.evb` round trip on every test: compile, save, load, run, same output; corrupted files are refused |
| **B5.8** | Default engine switched to the bytecode; the tree walker stays one release as `--engine tree`; the documents (B7 of `design-packages.md`): spec of the file, manual page, `usage.md` | one release; then the tree walker is removed or kept as the reference (Q-B3) |
| **B5.9** | Embedding (version 0.7): the C ABI over the bytecode VM (RVM-R07), `wasm32-wasi` build (RVM-R06) | a C program runs a chunk; the VM builds for WASI |

## 10. Tests

- **Two engines, one expectation.** The `/*@expect*/` blocks of the tests are the oracle. `runtest.py --engine bc` and `--both` (R8): `--both` runs each test twice and also compares the two outputs with each other, which finds a difference even where the expectation is loose (a map order, a trace line).
- **Unit tests in Zig** next to each piece: an emitter test per construct (source → listing as text, compared with an expected listing), a loop test per instruction group (a hand-built chunk and its result), a verifier test per refusal (a chunk with a jump out of range must fail to load).
- **Golden listings**: `test/bytecode/*.eve` with `*.lst` (the disassembly). A change to the emitter shows up as a diff of listings that the author can read; updated deliberately with `--update`.
- **Equivalence fuzz**: a small generator of random expressions and statements of level 1 (integers, reals, strings, lists), run on both engines; any difference is a bug. It lives in `script/` and runs on demand, not in the suite.
- **GC verify**: `EVE_GC_VERIFY=1 python script/runtest.py all --engine bc` on the Debug build at the end of every stage from B5.3.
- **Performance gate**: `bmark.py --engine bc`; the history keeps the two engines in separate columns; the targets of §11.

## 11. Targets

To be confirmed by the author (Q-B8) after R0 gives the base line. The proposal, for ReleaseSafe against the Python twins:

| Benchmark | Now (Eve / Python) | Target with the bytecode |
|---|---|---|
| `p1a_arith` | 3.5x | at most 1.0x |
| `p1b_calls` | 1.9x | at most 1.0x |
| `p3a_modules`, `p3b_objects` | 2.5x, 2.3x | at most 1.5x |
| `p4a_parallel_sum`, `p4e_garbage` | 2.9x, 2.3x | at most 1.8x |
| `p4c_groups`, `p4d_tasks` | 1.1x | at most 0.7x (no threads) |
| any other | at most 1.5x | no benchmark above 2x |
| Memory (peak, `bmark.py`) | as reported | not above the tree walker |
| `eve.exe` size | as reported | growth of at most 20% for the whole of B5 |

## 12. Risks

| Risk | Where | Answer |
|---|---|---|
| Two engines diverge in a corner (map order, error text, a trace) | B5.2 to B5.8 | `--both` from the first instruction; the tree walker is the oracle until B5.8; a difference is fixed in the bytecode unless the tree walker is the one that is wrong (then both, and a test) |
| A value freed too early or leaked in registers | B5.2 to B5.6 | `EVE_GC_VERIFY=1` at each stage; the rule "a register is a holder" has one implementation (`setReg`) |
| The emitter and the checker disagree on scope or capture | R2, B5.4 | one pass decides (R2 in `check.zig`); the emitter reads the decision, never recomputes it |
| R7 (the tree leaves the runtime) touches the database layer, the debugger, the libraries | B5.1 | list every use first (`grep -rn "\.node" comp/evevm`), change one holder at a time, run the suite after each |
| Generators and tasks without threads change the order of output | B5.5 | determinism is a spec rule: the scheduler keeps the order of creation; the `p4*` tests and the level 4 suite are the check |
| Natives that block (sockets, `sleep`, database calls) | B5.5, B5.6 | a native either completes, or returns `.park` with a wake condition; a native that blocks a thread (a plain socket read) is wrapped, and its latency is measured |
| Register limit of 255 per function | B5.2 | an error with the function name; the `wide` prefix when first met |
| The `Value` layout is the real cost, not the dispatch | R0 | the profile of R0 says; if so, Q-B6 becomes the first thing to decide, before B5.2 |
| `.evb` frozen too early | B5.7 | the format version is checked; the format is documented only at B5.8 |
| Scope creep: JIT, parallel cores, regions | all | out of B5 (§14) |

## 13. Questions for the author

Answer under each point; the answers become decisions.

**Q-B1. Register machine or stack machine?** Proposal: register machine (§3.2).
**Answer:** Agree. Register machine.

**Q-B2. Which version?** `design-packages.md` §3 says the bytecode comes "in 0.0.6", `version_map.md` puts F-VM-04 and F-VM-07 in Version 0.7 (D-138), and the note "move bytecode in version 6" is in `phase-8-architecture.md`. Proposal: the ladder (B5.0, B5.1) in the current version, B5.2 to B5.6 in the next one with the tree walker as the default, B5.7 to B5.9 in the version that `version_map.md` names for the `.evb` file (0.7).
**Answer:** Agree. Correct the design-packages version.

**Q-B3. Is the tree walker kept?** After B5.8 either keep it as the reference engine (a slower oracle for the tests, a few thousand lines to maintain) or remove it. Proposal: keep it until the end of version 0.7, then decide.
**Answer:** We keep it as a reference. Once the code is stabile there will be no maintenance to do. Maybe we find other good reasons to keep it.

**Q-B4. One file or many?** A project as one `.evb` bundle, or one per module with an index.
**Answer:** Yes, one single project bundle. Eve projects are usually small. 

**Q-B5. The JIT.** Your answer to RVM-R01 was "I thought we implement a kind of JIT". Proposal: no JIT in B5. The bytecode is the step that makes a later JIT (or a typed fast path) possible, because it gives the types and the slots a JIT needs. A JIT would be a design of its own after version 0.7.
**Answer:** Agree, postpone JIT to version 0.8

**Q-B6. Change `Value` now or later?** The measure of R0 decides. Proposal: later; the five integer tags and the 24-byte size are measured first.
**Answer:** Agree, change it later version 8

**Q-B7. Tail calls and deep recursion.** The bytecode VM has no Zig stack limit on call depth. Proposal: a limit of the depth by configuration (default one million frames), `StackOverflow` as a language error; no tail calls in the first version.
**Answer:** Agree, tail call optimization comes in version 10.

**Q-B8. The targets of §11.** Are these the numbers to commit to?
**Answer:** Sounds good +10% is fine in this phase, if we avoid the risky and expensive ones. We stop optimization after 4 if good enaugh is achieved at this stage.

**Q-B9. Order of the ladder.** Start with R0 and R1 (operators and literals as data), then R2 (slots). Do you want R2 first because it is the largest gain, or the order of §4?
**Answer:** In order. 1, 2, test, 4 test. 

## 14. Not in this design

A JIT; running tasks on several cores (D-183, Q-061); regions per aspect call and per job (RVM-R02); changes to the `Value` layout (Q-B6); WebAssembly as a target of the compiler (the Eve Web framework of `comp/evewp`; it compiles from the same chunk, later); the data structures of RVM-R04 (hash index for `Map`, columnar `Table`), which are independent of the bytecode and stay in the optimization list of rank 5.
**answer** add to back-log for further optimizatons with a note.
