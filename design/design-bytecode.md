<!--# Bytecode design-->

Status: **answered** 2026-10-19: the author answered Q-B1 to Q-B9 (settled as D-201); the stages wait for the order of the work (level 5 and 6 blockers first). Step S8.12 of `phase-8-architecture.md`, step B5 of `design-packages.md` §10. Builds on RVM-R01, R03 and R05 of `archive/review-2026-10-04/07-vm.md`, D-144 (baton tasks), D-151 (reference counted heap), D-163 (modules), D-194 (order of the work). The answers of the author are in §13 and in D-201 (`decision/level6.md`).

## 1. Goal and the steering rule

The goal is a VM that runs Eve faster and with less memory than the tree walker, in a form that can be saved (`.evb`), shipped to another machine, checked before it runs, and stopped and continued (generators, parked tasks) without an operating-system thread per task.

The author asked that **the refactoring is steered toward the bytecode**. The rule for every refactor and optimization from now until B5 is done:

> A change is worth doing now if it removes work from the tree walker **and** the bytecode emitter or VM would need it anyway. A change that only makes the tree walker faster, and that the bytecode would throw away, waits.

§4 lists the changes that pass this test, in order. Each is measured with `bmark.py` before and after (D-196: a refactor and an optimization start with a measure) and keeps all levels green on the tree walker, so the bytecode never starts from a moving base.

## 2. What the tree walker costs today

These are facts from the code (2026-10-19), they are what the bytecode removes.

| Cost | Where | Effect |
|---|---|---|
| Variables are found by **name**: a linear walk of the chain of scopes, comparing strings | `Scope.find` in `code/evecm/src/value.zig`, `Interp.lookup` | every read and write of a variable is a string search; deeper scopes cost more; this is the first planned optimization ("slot-resolved variables") |
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
- **A nested run has a stack of its own** (B5.3b): when the tree walker calls a routine of the machine while a run waits, the waiting stack is set aside and the nested run takes a spare one; the stack of a run moves only at its own calls, so the loop keeps its register pointer.
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

Tables, `sql` blocks, `sql function` and stored procedures keep their text in the constant pool and run through the existing `db` module by native calls (`sqlrun`, `tablefield`, `ormstore`...). Nothing in `code/evevm/src/db/` needs the syntax tree after the move except where it reads `Node` today (`orm.zig`, `importer.zig`); those places are listed by R7 (§9) and receive a plain description (`TableDef`, fields and types) built by the emitter instead of a node.

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

About 90 instructions. Names are proposals; the final list is in `code/evecm/src/op.zig` with the `@spec` tags.

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
- **Stability**: `format version` changes with the encoding; `spec version` is the Eve version the source follows (D-138 ties both to the feature map). A VM refuses a higher format version and may read lower ones for one release.
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
| **B5.2** (done 2026-10-19, see §15) | `op.zig`, `chunk.zig`, a disassembler, the emitter for **expressions, `var`, `print`, `if`, `while`, `for` over ranges, plain function calls** (level 1 core), and the VM loop for them. `eve cp --disasm`. | `a01` to `a12` of level 1 pass with `--engine bc`; the unit tests of the emitter and the loop pass |
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
| R7 (the tree leaves the runtime) touches the database layer, the debugger, the libraries | B5.1 | list every use first (`grep -rn "\.node" code/evevm`), change one holder at a time, run the suite after each |
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

**Q-B2. Which version?** `design-packages.md` §3 says the bytecode comes "in 0.0.6", `spec/features/` puts F-VM-04 and F-VM-07 in Version 0.7 (D-138), and the note "move bytecode in version 6" is in `phase-8-architecture.md`. Proposal: the ladder (B5.0, B5.1) in the current version, B5.2 to B5.6 in the next one with the tree walker as the default, B5.7 to B5.9 in the version that `spec/features/` names for the `.evb` file (0.7).
**Answer:** Agree. Correct the design-packages version.

**Q-B3. Is the tree walker kept?** After B5.8 either keep it as the reference engine (a slower oracle for the tests, a few thousand lines to maintain) or remove it. Proposal: keep it until the end of version 0.7, then decide.
**Answer:** We keep it as a reference. Once the code is stabile there will be no maintenance to do. Maybe we find other good reasons to keep it.

**Q-B4. One file or many?** A project as one `.evb` bundle, or one per module with an index.
**Answer:** Yes, one single project bundle. Eve projects are usually small. 

**Q-B5. The JIT.** Your answer to RVM-R01 was "I thought we implement a kind of JIT". Proposal: no JIT in B5. The bytecode is the step that makes a later JIT (or a typed fast path) possible, because it gives the types and the slots a JIT needs. A JIT would be a design of its own after version 0.7.
**Answer:** Agree, postpone JIT to version 0.8. **Changed by D-241 (2026-10-26):** no JIT; the bytecode is optimized by the bands of `design-bytecode-opt.md`, and AOT of `lib/` comes later.

**Q-B6. Change `Value` now or later?** The measure of R0 decides. Proposal: later; the five integer tags and the 24-byte size are measured first.
**Answer:** Agree, change it later version 8

**Q-B7. Tail calls and deep recursion.** The bytecode VM has no Zig stack limit on call depth. Proposal: a limit of the depth by configuration (default one million frames), `StackOverflow` as a language error; no tail calls in the first version.
**Answer:** Agree, tail call optimization comes in version 10.

**Q-B8. The targets of §11.** Are these the numbers to commit to?
**Answer:** Sounds good +10% is fine in this phase, if we avoid the risky and expensive ones. We stop optimization after 4 if good enaugh is achieved at this stage.

**Q-B9. Order of the ladder.** Start with R0 and R1 (operators and literals as data), then R2 (slots). Do you want R2 first because it is the largest gain, or the order of §4?
**Answer:** In order. 1, 2, test, 4 test. 

## 14. Not in this design

A JIT; running tasks on several cores (D-183, Q-061); regions per aspect call and per job (RVM-R02); changes to the `Value` layout (Q-B6); WebAssembly as a target of the compiler (the Eve Web framework of `code/evewp`; it compiles from the same chunk, later); the data structures of RVM-R04 (hash index for `Map`, columnar `Table`), which are independent of the bytecode and stay in the optimization list of rank 5.
**answer** add to back-log for further optimizatons with a note.

## 15. State of the work

**B5.2, 2026-10-19.** The pipeline runs end to end: `code/evecm/src/op.zig` (the instructions), `chunk.zig` (the chunk and its listing), `code/evecp/src/emit.zig` (the emitter), `code/evevm/src/bcvm.zig` (the machine); `eve --engine bc -x file.eve` (or `EVE_ENGINE=bc`), `eve --disasm file.eve` for the listing, `python script/runtest.py N --engine bc` (reports in `temp/output-bc`, never the status files). Every level and the smoke tests pass on the bytecode machine (408 of 408 tests), but not all natively: the emitter translates what it knows and **leaves the rest to the tree walker through a bridge**.

- **Natively translated:** numbers, text, `True`, `False`, `null`, local variables, the operators `+ - * / % == <> < <= > >=` (integer fast path, the rest through `applyOp`), `and`, `or`, `not`, unary minus, every other binary operator through `binx`, `new`, `set`, `let` (also the compound forms, collections in place), `print`, `write`, `expect`, `if`, `while`, `for` over integer and rune ranges, `break`, `skip`, `over`, `exit`, calls of the functions and procedures of the aspect with positional arguments, typed declarations of Integer, Real, String and Logic.
- **The bridge:** `evalx` (an expression) and `execx` (a statement) run a piece of the tree on the tree walker. The variables it names are copied into a scope before and, for a statement, back into their registers after. A piece with a jump out of it, a lambda, a task, `defer` or a `panic` can not be bridged: the routine that holds it stays with the tree walker as a whole (a call of it is bridged), and when `process main` itself can not be translated the whole program runs on the tree walker (`EVE_BC_TRACE=1` says why).
- **Not natively yet** (so they run on the tree walker): collections and strings (`xs[i]`, methods, interpolation), `match`, `repeat`, classes and objects, modules, overloaded routines, `recover` and `finalize`, tasks and jobs, the data language. These are the work of B5.3 to B5.6; each translated construct removes bridged pieces, and the bridge goes away with the last one (an `.evb` file can not hold a tree).
- **Speed, ReleaseSafe, `p1a_arith` and `p1b_calls`:** 70 and 46 ms on the tree walker, 26 and 15 ms on the bytecode machine. The other benchmarks run on the tree walker still (their time is unchanged).
- **B5.3a done (2026-10-26):** the `call` instruction (§16.3, `test/bytecode/bc23_calls`). A call that is not a direct `callf` of a translated routine computes its callee or receiver and its arguments in registers; a plain function value, a module function and a routine of the aspect left to the tree walker are called with the values (`invokeWith`); every other callee goes to the tree walker through the adapter. Literals and names outside the registers stay as nodes in the site (no register, no hidden variable); a callee or receiver that is such a name is read by the machine from the node (`call_named`); the window of a call starts at the destination when it is the last temporary (no `move` after the call); the arguments of a call are in contiguous registers (a latent bug of `callf` with an argument that keeps a temporary, `f(-x, y)`). Census: bridged pieces 2,872 to 930, programs entirely on the bytecode machine 42 to 137. Speed (minimum of the CPU cycles of 9 alternated runs against d77ed0c, a loaded machine): `p3a_modules` -19%, `p1k_zone_dense` -19%, `p3c_module_state` -18%, `p1f_complex` -17%, `p2c_procedures` -16%, `p1g_dates` -14%, `p1i_zone_offsets` -10%, the others within ±3%. The adapter alone (a native that reads nodes, `time.parse`) is 3% slower than the bridge was; value natives remove it (OPT-12). Equivalence sweep 628 of 628, `bctest.py` 25 of 25.
- **B5.3b done (2026-10-26):** routines by themselves (§16.2, `test/bytecode/bc24_routines`). A function or procedure is compiled on its first call (`compileRoutine`) and kept in a table of the root interpreter by declaration (`bc_routines`, compiled or refused); the routines of the aspect compiled with `main` are entered in the same table. Both engines call it: a `call` of such a routine pushes a frame in the loop (no Zig recursion), a call of the tree walker (`invokeWith`) runs it in a nested run. Each frame of a routine has a scope below the closure of the routine (free names through `loadg` and the new `storeg`) and a **region**, as `execBlock` gives the body of a routine in the tree walker: without it the safe points of a loop in the routine freed the temporaries of the tree walker's expression that called it (found by `c100_data_quality`; `EVE_GC_VERIFY=1` is clean on every level). A nested run has a **stack of its own** (`bc_waiting`, `bc_spare` of the interpreter; each task has its own stacks), so the stack of a waiting run never moves and the loop keeps its register pointer (a pointer taken again at every instruction made `p1a_arith` 24% slower). New instructions `zero` (the zero value of a result type without a literal one: 105 routines were refused for it) and `storeg`; literal defaults of parameters; private processes are left to `apply`; `over` in any routine ends the process (the `Over` signal). Kept with the tree walker: methods, lambdas, generators, `async` routines, `sql function` (DuckDB calls it from its threads), routines with a type list, a non-literal default, an `@` parameter, a nested routine, `recover` or `defer`. Census: 277 routines compiled at their first call, 34 refused; refused programs 86 to 84. Speed against d77ed0c (minimum of CPU cycles, 9 runs): `p3a_modules` -47%, `p1k_zone_dense` -35%, `p1i_zone_offsets` -28%, `p3c_module_state` -23%, `p2c_procedures` -22%, `p1f_complex` -14%, `p1g_dates` -6%; `p1b_calls` +5% (a region per call, OPT-28) and `p1h_time_format` +5% (the adapter, OPT-12); the others within ±3%. Sweep 629 of 629 on both engines, `bctest.py` 26 of 26.
- **B5.3c, first part (2026-10-26):** new instructions `field` (object attribute and module member, the tree walker for the rest), `loadrune`, `loadnum`, `exitcode`, `raise`, `failmsg` (the message of `expect`/`assert`, computed only on failure) and `declmark` (D-213: a mark register per declaration of a loop body, cleared before the loop, the second cycle fails with the message of the tree walker); loops carry their label, so a labelled `break`/`skip` is a jump (`test/bytecode/bc25_level1_rest`). Census: bridged pieces 941 to 305 (`evalx field` 370, `evalx num` 190 and `evalx chr` 71 gone), refused programs 84 to 80, programs entirely on the bytecode machine 136 to 232. Sweep 629 of 629 on both engines, `bctest.py` 27 of 27. Not measured yet with `bmark.py`.
- **B5.3c, second part (2026-10-26):** `match` (`matchpat`, `matcheq`; the subject and the hit flag are hidden locals, every pattern of an arm is evaluated as in the tree walker), `repeat`, declarations of one name with no value (`zero`), with `::` (`clone`) or with a type that converts the value (`declty`), ranges as values (`range`) and object literals (`new_obj`, `obj_set`) (`test/bytecode/bc26_match`). Census: bridged pieces 305 to 251, `execx var_decl` 68 to 39, `repeat_` no longer refused. Sweep 631 of 631 on both engines. Left in level 1: `apply` (needs the write-back of `@`, B5.4b), special indexes (views, matrices, `$`, `*`), field assignment `let p.x := v`, `for` over a stepped range, deconstructing declarations, `capture`, `builder`.
- **B5.3c, third part (2026-10-26):** field assignment `let o.f := v` / `::` on a variable in a register (`setfield`), `capture` (`let l -> x`, `let x <- l`, `new x <- l`: `capture`), the conditional expression `a if c else b`, and `new x :T;` with no operator text (`test/bytecode/bc27_fields`). Census: bridged pieces 251 to 204, programs entirely on the bytecode machine 241 to 258. Sweep 632 of 632 on both engines. The special indexes (43 pieces: `m[i, j]`, `v[a..b]` views, `$`, `*`, `m[i][j]` on matrices, slice assignment) need the index machinery on values instead of nodes (`evalIdx` evaluates `$` against the object): that is the next piece, with the builders `[x | x in ...]` (9) and the deconstructing `new` (10).
- **B5.3c, fourth part (2026-10-27):** the indexes on values: `indexv`, `index_setv` and `dim` (`test/bytecode/bc28_indexes`). The machine computes the indexes in registers and `interp/indexval.zig` indexes with them (`a[i, j]`, slices and views, `*`, `$` of the only index, chains `a[i][j]` merged on a matrices, strings, Bytes, maps, compound assignment `let a[i] += v`); the node versions of `collections.zig` stay for the tree walker and retire with it. `$` is allowed only as the only index of a bracket (elsewhere the tree walker keeps the form). The indexes of a chain are evaluated before the first one is applied (the tree walker evaluates each group when it applies it): a difference only for an error or a side effect in a later group. The unary operators now release their temporary (a latent bug that made the next argument of a call or of brackets non-contiguous). Census: bridged pieces 204 to 151, `evalx index` 43 to 0, programs entirely on the bytecode machine 258 to 265. Sweep 633 of 633 on both engines. Found in the tree walker: `let m[*, 3] += 100` changes a copy of the column, not the matrix (the compound assignment on a slice); both engines agree, a bug to fix on both (TD entry).
- **B5.3c, fifth part (2026-10-27):** builders `[f(x) | x in src and c]` and set builders (`iterlist` then the loop of `iterprep`/`iterloop`), counting loops with excluded ends (`step`), `while` with a header and with `else`, `repeat` with a header, `x =~ c +- t` (`near`), `new x <- l` (the parser's `none` third child means an explicit `new`) (`test/bytecode/bc29_builders`). Census: bridged pieces 151 to 136, programs entirely on the bytecode machine 265 to 271, refused 80 to 79. Sweep 634 of 634 on both engines. What is left of level 1 is made of forms that need B5.4b: `apply` (60), calls with `@`, a lambda or a spread (27 + 18), `assign` of `^=` and `+>` (4), builders over `><` or with a tuple pattern (1), the `=~` forms with a regular expression (7), `print` with `sep:` (1), deconstructing `new` (10), an implicit `let x -> e` (4).
- **B5.4b, first part (2026-10-27):** `apply name(args)` is a `call` site of kind `apply`, and an `@x` argument on a variable in a register is passed as a reference to a hidden name of the adapter whose final value is written back to the register when the call returns (`NameReg.back`, bit `call_ref` of C; the call then never takes the direct paths) (`test/bytecode/bc30_apply`). Census: bridged pieces 136 to 68, programs entirely on the bytecode machine 271 to 321. Sweep 634 of 634. This is a copy in and out through the adapter, not a cell: it keeps the machine out of the closures; the cells for lambdas and nested routines (`newcell`, `closure`) are the second part. Element references `@s[i]` and `@` on a name outside the registers still go to the tree walker.
- **B5.4b, `^=` and `+>` (2026-10-27):** `augment` takes `pow` (`^=`) and `push_front` is the front of `push`; bridged pieces 68 to 65. What is left of the 65: calls with a lambda, a spread or a type list (27), deconstructing `new` (10), `expr_stmt` with a spread or a bare name (8), `=~` with a regular expression (7), an implicit `let x -> e` (4), `wait` (2), `apply` with a spread (2). The refusals (79 programs) are `parallel` (27), `job` (25), nested aspects (7), lambdas (6+6) and a process with parameters (4): lambdas need the cells of the second part of B5.4b, `parallel` and `job` are B5.5.
- **B5.4b, second part: lambdas (2026-10-27):** `closure` makes the function value of a lambda with the current scope as closure, and the locals of a routine that its lambdas name (`analyzeCaptures`: a parameter or a plain `new`/`set`, declared once) are defined in the scope of the routine with `defvar` instead of getting a register, so the lambda finds them by name and the routine reads and writes them as any name outside the registers (`loadg`, `storeg`, the bridge scope chain): this is the semantics of the tree walker, without cells in registers. A routine with such variables is compiled alone (it has a scope per call); in the aspect it stays a function value, not a `callf`. A lambda runs on the tree walker for now (it is not a routine of the table). Refused: a captured name declared twice, a loop variable, a builder pattern or a deconstruction that a lambda names. Census: refused programs 79 to 74 (lambda refusals 12 to 0), programs entirely on the bytecode machine 323 to 328 (`test/bytecode/bc31_lambdas`). Sweep 635 of 635.
- **B5.5, first part: jobs and groups (2026-10-27):** `job` and `parallel` blocks are native (`jobbegin`/`jobclose`, `parbegin`/`parclose`, `signal`, `commit`; `start` and `spawn` are call sites of kind `apply` with a task bit) (`test/bytecode/bc32_jobs`). The run loop is now `run` (the frames and the handlers) around `execute`: an error in a block goes to the handler of the innermost open block of the run, which lets go of the frames above it and continues at the `jobclose` or `parclose` with the error kept; the end instruction runs `jobFinish` or `parFinish` (the code of the tree walker's `job` and `parallelGroup`, now shared). The tasks still run on the threads of today, each with its own stacks; the outputs `@x` of tasks keep one cell per variable in the block (the duplicate-output rule of D-140 holds) and are copied to registers at `done`; a jump out of a block (`break`, `exit`) is refused for now. Census: refused programs 74 to 19, programs entirely on the bytecode machine 328 to 352. Sweep 636 of 636 on both engines.
- **B5.5, second part: pulling loops, `panic`, `await`, `main` with parameters (2026-10-27):** `for` over a range value, a channel, a generator or a stream pulls one element at a time (`iterprep`/`iterloop`), a map, a set, a string or a table is listed once, so the loop never goes to the tree walker any more and a `break` or `skip` in any loop is native (before, a loop over a variable with a jump in the body was refused); `iterend` closes a generator or a stream when the loop ends (a stream writes its rejects then; the paths of a stream are now copied, because the registers that held them are reused). Difference with the tree walker: the close happens before the `after` block of the loop, not after it, and an error or a `return` that leaves the loop does not close (the generators end with the program; TD-46). `panic` is `signal` 2, `await f()` is the call, `main(a, b)` takes the command-line arguments with the binding rule of routines (`bc33_iterate`). A vararg parameter (`*args`) is native (the positional arguments that are left, as a list; a call of such a routine is never direct). A receiver with a lambda (`f(x, (v) => v).count()`, `f(..)[1].amount`) no longer sends the program to the tree walker: the `field` slow case sees the receiver's value under a hidden name instead of evaluating it again; the `count`/`length` shortcut is not used for a call as receiver. Census: refused programs 9 to 7 (all nested aspects). Nested aspects (`exclusive aspect add_step`, macros) are declared by the tree walker before the machine starts, like classes; `apply add_step(3)` runs their process on the tree walker through the adapter. No program is refused any more (census: 369 native, 69 with bridged pieces). Calls with written types (`Channel(:Integer)(capacity: 10)`, `first(:String)(xs)`) and calls with a checker-chosen overload are call sites of kind `builtin` (the tree walker evaluates the call node with the hidden argument names); `let name <+ v` on a name outside the registers pushes at once on a list or a set and leaves the rest (tables) to the tree walker with the value under a hidden name; `new a, b :Integer;` and `new s :[5]Integer;` give each name the zero of the type. Census: bridged pieces 111 to 32 (`=~` with a regex 7, deconstructing `new` 5, `capture` 4, `expr_stmt` 4, `wait` 4, `apply_stmt` 2); programs entirely on the bytecode machine 416. `a ?? b` is native (`jnn`), `wait` is an instruction, and deconstructing `new` (`new q, r := f();`, `new (u, v) = 7;`, `new p, *rest, t := xs;`) is `unpack`, which binds registers by the rule of `declareStatement` (a declaration with a type stays with the tree walker). Bridged pieces 32 to 16: `capture` into a name that may not exist (4), `expr_stmt` with a spread or a bare name (4), `apply` with a spread (2), `update` (2), `print` with `sep:` (1), a builder over `><` (1), `for (k: v) in` (1), a multi-line text (1).
- **B5.4a, first part: methods (2026-10-27):** a method of a class (a routine whose first parameter is `@self`) is compiled alone on its first call and runs on the machine when it has a receiver (`bcvm.runRoutine` takes `recv`): `self` is register 0 (also the variable `self` of the scope, for lambdas and the tree walker), the other parameters follow, a call without a receiver stays with the tree walker. `let o.f op= v` on a variable in a register is native (`field`, `augment`, `setfield` with C = 1: nothing is stored when a list or a set changed in place). `eve --disasm` lists the methods of the classes after `main` (`test/bytecode/bc34_methods`). Constructors run on the machine too (`self` is their result register; `constructClass` calls `bcvm.runRoutine`; `p3b_objects` 85 ms on both engines, alternated runs, loaded machine). Not yet: destructors, extension methods on values, a direct frame for a method call (the call still goes through `callMethod` and a nested run), the cache of the class (OPT-11). `p3b_objects` equal to the tree walker (60 ms, minimum of 5 runs; 79 ms before `self` became a register and the compound assignment of a field native). Sweep 639 of 639 on both engines.
- **R8 done (2026-10-19):** `python script/runtest.py all --both` (or one level, `smoke`) runs every test on both engines; it passes when both pass and agree on exit code, output and error output (408 of 408). `python script/bmark.py --both` does the same for the benchmarks and saves the BCode column.

## 16. The plan of B5.3 to B5.6 (2026-10-26)

The stages of §9 were written by construct ("the rest of level 1", "levels 2 and 3"). The measure below shows that the bridge is not spread over many constructs: it is almost all **calls**. The plan is reordered around that fact. The optimization levels and the notes on future optimization are in `design/design-bytecode-opt.md`.

### 16.1 The measure (the census)

`python script/bccensus.py` runs `eve --disasm` on every program of `test/level1` to `test/level7` and `test/bmark` (a test in its own folder counts once) and counts what goes to the tree walker. The base line is commit d77ed0c (2026-10-26); the second column is after B5.3a:

| Measure | Base | After B5.3a |
|---|---|---|
| Programs entirely on the bytecode machine | 42 | 137 |
| Programs on the bytecode machine with bridged pieces | 310 | 215 |
| Programs the emitter refuses (they run entirely on the tree walker) | 86 | 86 |
| Bridged pieces (`evalx`, `execx`) | 2,872 | 930 |
| of which calls (`evalx call`) | 2,044 (71%) | 27 (overloads chosen by the checker, lambdas, `@`, spreads, type lists) |
| fields `x.f` | 274 | 370 (they were inside the calls before) |
| expression statements | 182 | 18 |
| numbers with a unit, runes, declarations, `apply`, indexes, assignments, ranges, `match` and the rest | 372 | 515 (most were inside calls before) |
| `call` instructions | none | 2,502 (method 2,012, builtin 487, value 3) |

Programs refused, by reason (base and after, the same): `parallel` 26, `job` 25, a nested aspect 7, a call form 6, `lambda` 6, a process with parameters 4, a process other than `main` 3, `panic` 2, a declaration in a loop body 2, a `for` form 2, `repeat` 1, `exit n` 1, a labelled `break` 1. The 86 "not a program" files are the tests of syntax and check errors.

### 16.2 The pivot: the unit of the bridge is the routine, not the expression

Today a routine is either translated whole or left to the tree walker, and **only `main` and the routines of the same aspect** are candidates; everything a translated routine can not express is an `evalx`/`execx` piece. The new rule:

- **Every routine is compiled alone, on its first call**: a function, a procedure, a method, a constructor, a module routine (the Eve library of `lib/` included), a lambda, a process. The result is kept for the declaration (compiled, refused, or not tried) so the work is done once per run.
- **Calls cross the engines both ways.** A bytecode `call` of a translated routine pushes a frame (no Zig recursion, §3.5); of a refused one, it calls `invokeWith` of the tree walker with the values of the registers. A tree walker call of a translated routine runs it on the bytecode machine in a new window of the value stack, above the top. The engine of one routine never changes the result of another.
- **Free names go through the closure scope.** A routine runs with its closure as the scope of the machine: a name that is not a register is read with `loadg` and written with `storeg` by name (the slow path), exactly as the tree walker sees it. The optimization levels make that fast later (an inline cache of the `*Var` per instruction, `design-bytecode-opt.md`), without a change of semantics.
- **The bridge shrinks to a fallback for rare forms**, and the cost of a refused routine is one call of the tree walker, not a copy of the variables in and out for every piece.

Why: it turns "levels 2 and 3" (modules, methods, closures, processes) into "compile one more routine", it puts the Eve library on the bytecode machine at once (most calls are calls of `lib/` routines), and it keeps every step small and measured by the census.

### 16.3 Calls: the `call` instruction

`call A B C` with a second word `site Bx`: the callee (or the receiver of a method) is in register A, the B arguments in A+1 to A+B, the result goes to A. C is the kind; Bx indexes the table of call sites of the chunk (the call node for messages and the adapter, the name of a method or a built-in, the names of named arguments).

| Kind | The source | What the machine does |
|---|---|---|
| `value` | `f(x)` where `f` is a variable, a parameter, a name of the aspect or a function value | a `func`: `invokeWith` (a translated routine gets a frame once B5.3b is done); a class, a type or a range: `callValue` through the adapter |
| `method` | `x.m(...)` | a module receiver: its member, then as `value`; anything else (objects, strings, lists, maps, streams, tables, connections, overloads): `callMethod` through the adapter |
| `builtin` | `round(x)`, `type(x)`, `upper(s)`: a name that is neither a register nor a routine | `call` of the tree walker through the adapter |

**The adapter** (`argNodes`): the natives of the library read their arguments as syntax nodes (`design-packages.md`, the `Native` convention). Until they take values (R5), the machine binds the values of the argument registers to hidden names (`$1`, `$2`, ...) in a new scope and gives the native a list of name nodes (a named argument is a `pair` node over a name node). The native evaluates the names and sees the same values, in the same order, as if the tree walker had evaluated the arguments. Kept by the emitter for the tree walker: a lambda as an argument, `@x` references (they need a cell, B5.4b), `*spread`, a type list `f(:T)(...)`, and a call whose overload the checker chose (`n.sel`).

Order of evaluation, as in the tree walker: the callee or the receiver first, then the arguments from left to right. `it.stmt_call` is set for a call that is a statement (the choice between a procedure and a function of the same name, D-149).

### 16.4 The sub-stages

Each sub-stage ends with: `python script/bctest.py` green, `python script/runtest.py all --both` green (the equivalence sweep of §10), the census lower, `bmark.py --check` without a slowdown, a paragraph in `test/bmark/README.md` and §15.

| Sub-stage | Content | Done when |
|---|---|---|
| **B5.3a** (done 2026-10-26) | `call` (kinds `value`, `method`, `builtin`), the adapter, procedure calls as statements, `script/bccensus.py` | the 2,044 `evalx call` pieces below 150 (what is left: lambdas, `@`, spreads, type lists): 27 |
| **B5.3b** (done 2026-10-26) | Mixed mode by routine (§16.2): a routine carries its compiled index; the machine is re-entrant (a window above the top); a routine of the aspect that is refused is called, not bridged; `storeg` | the `a process other than main` refusals gone (the `call` refusals are calls with a lambda: B5.4b); every routine counted as compiled or refused by `bccensus.py --routines` |
| **B5.3c** (first part done 2026-10-26: fields, runes, number forms, `raise`, `exit n`/`over n`, `assert`/`expect` with a message, labelled `break`/`skip`, declarations in a loop body; left: `match`, `repeat`, general `var_decl`, `apply`, ranges as values, `for` forms) | The rest of level 1: fields `x.f`, runes (`chr`), number forms with a unit (`evalx num`), `match`, `repeat`, `raise`, `expect` and `assert` with a message, `exit n`, `over n`, labelled `break`/`skip`, declarations in a loop body (a per-loop mark that fails at the second cycle, D-213), ranges as values | level 1 programs without `evalx`/`execx` except the calls kept by §16.3 |
| **B5.4a** | Methods and objects natively: `self`, fields of objects, constructors, a method call with the class of the last call cached in the instruction; extension methods; overloads resolved by the checker (`n.sel`) | `p3b_objects` on the bytecode machine without bridge; level 3 pieces below 30 |
| **B5.4b** | Captured variables: the resolver marks the locals that a lambda or a nested routine names; those live in cells (`newcell`, `getcell`, `setcell`); `closure` makes a function value; `@` arguments (a cell and the write-back of `writeBack`) | lambdas and `@` calls native; `p2b_closures`, `p2c_procedures` without bridge |
| **B5.4c** | Modules: module routines compile on their first call (`lib/` included); module state through `getmod`/`setmod` by index once the resolver gives the indexes (by name with `loadg`/`storeg` before) | `p3a_modules`, `p3c_module_state` native; the census counts the routines of `lib/` |
| **B5.5** | Level 4 as in §3.9: `start`, `spawn`, groups, channels, generators, `wait`, `within`, `parallel`, `job` on the bytecode; the scheduler without threads comes **after** the constructs are native (first they keep the threads of today, each with its own value stack) | the `job` and `parallel` refusals gone; `p4*` not slower |
| **B5.6** | Levels 5 and 6: tables, `sql`, `sql function`, procedures, the machine API and the debugger hooks by pc (§8) | the census at zero pieces and zero refusals; the bridge removed (TD-46 closed); B5.7 can write an `.evb` |

### 16.5 What does not change

The tree walker stays the oracle (D-201). The `/*@expect*/` blocks of the conformance tests are the specification; the bytecode tests of `test/bytecode/` show each instruction group and keep their golden listings. Values, messages, error codes and the order of output are those of the tree walker; a difference is a bug of the bytecode unless the sweep shows the tree walker is wrong (then both are fixed, with a test).
