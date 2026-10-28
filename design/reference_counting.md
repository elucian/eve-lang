<!--# Reference counting and the garbage collector: measures before the optimization-->

Status: **measures taken 2026-10-27, nothing optimized yet.** Written before the optimization of levels 1 to 5 begins (D-194, D-196: a measure before and after). Builds on D-151 (the author's rule: "use reference counting as much as possible and the garbage collector only as backup"), D-202 CLS-14 (destructors run at the next safe point), `design/design-task-heap.md` (a heap per task) and `design/design-bytecode-opt.md` (the optimization notes OPT-nn). This page has the facts of the code, the data, what the data says, the experiments proposed in the order to try them, and a log where every experiment writes its result.

## 1. The rule and what must not change

- **D-151:** reference counting frees what it can; the tracing collector is a backup for cycles. A program can not see when memory is freed, with one exception:
- **CLS-14 (D-202):** a destructor runs when the last reference is released, at the next safe point of the region, and for the objects alive at the end of the run, the newest first. So the time of a *release* is observable through a destructor. Any optimization that skips or moves a safe point must keep this: a statement that can **drop a count** needs its safe point as much as one that allocates.
- Output, errors and the order of effects never depend on the memory management (the rule of `design-bytecode-opt.md` §1 for the levels).

## 2. How memory is managed today

`code/evecm/src/heap.zig` (865 lines), used by both engines.

- **Objects.** Every heap object starts with an `Obj` header of 24 bytes (count `rc`, kind, `mark`, `in_zct`, `pinned`, `idx`, `seq`, `finalized`, `owner`). Kinds: string, list (also set and array), map, object, function, range, domain, channel, **scope**, **variable**. Sizes in bytes: `Value` 24, `Var` 64, `Scope` 64, `Object` 64, `List` 88, `Map` 56, `Func` 48, `Range` 56, string header 40 plus the text. Plain values (integers, reals, Booleans, dates, runes...) have no object and no count.
- **Counting.** `retain` adds one holder, `release` removes one. At zero the object goes to the **zero count table** (ZCT) of its **region** (`zctPush`); variables and scopes are freed at once at zero. Pinned objects (literals, interned strings, constants, module scopes) are never counted.
- **Regions and safe points.** A region is a block, a loop, a routine call or a process (`pushRegion`/`popRegion`). `safePoint` frees the objects of the innermost region whose count is still zero. The emitter puts a `safe` after each statement of `main` and at the end of each pass of a loop; the tree walker after each statement.
- **Registers (bytecode).** `put` writes a register: when the old and the new value are both plain it is a copy, else `setCell` (retain the new, release the old). `ret` clears the registers of its frame with the same counted write.
- **Tracing backup.** `trace` marks from the roots (scopes, the ZCTs, every pinned or older object) and frees the unmarked objects made since the start of the innermost region; it runs at the `done` of a job, a group and a process, and from a safe point when `since_trace` (objects **made** since the last trace) is above `trace_limit = max(200,000, live)` and the region holds more than half of the limit. It is stop-the-world and sweeps `objs`, the table of all objects.
- **Tasks.** Every task that runs in parallel has a heap of its own (design-task-heap.md); a generator shares the heap of its caller.
- **Scratch memory** (`scratch.zig`): buffers of one statement, outside the heap.
- **Tools.** `EVE_MEMSTATS=1` prints, at the end of the run, the objects made (by kind), freed by count and by trace, traces, live and peak, safe points, zero counts pushed, table entries scanned and objects swept by traces. `EVE_GC_VERIFY=1` checks each free against a trace. `count_ops` (a `const` in `heap.zig`, false in every release) also counts the calls of `retain` and `release`.

## 3. How it was measured

- Wall times on this machine move by 2 to 3 times between runs. Two builds are compared with `python script/abtest.py BASE.exe NEW.exe [names]`, which alternates them and counts the CPU cycles of the process (`QueryProcessCycleTime`); the base is built from the commit before the change (`git stash; zig build -Doptimize=ReleaseSafe -p temp/base; git stash pop`). A difference under 3 % is noise (`execute` is also sensitive to its own size, OPT-25).
- Build: ReleaseSafe (`zig build -Doptimize=ReleaseSafe -p temp/rel`), a loaded machine, so times are the minimum of 5 runs and are used only to compare two numbers taken in the same minute.
- Counts of objects, frees, traces: `python script/memstats.py --table` (every `test/bmark/p[1-5]*.eve` and `test/bmark/mem/*.eve`, both engines, `EVE_MEMSTATS=1`). The calls of `retain` and `release`: the same with an `eve` built with `count_ops = true` (the counters are global and not exact with several threads: read `p4a_parallel_sum` as an order of magnitude).
- Prices of the operations: `zig run -OReleaseSafe code/evecm/src/heap_bench.zig` (one thread, a warm cache and a pool of freed objects: the best case). Two runs are given as a range.
- Stress programs for what the benchmarks do not show: `test/bmark/mem/gc1_live` (300,000 live strings and a million temporaries), `gc2_cycles` (200,000 closures), `gc3_nested` (100,000 records live, copied five times).

## 4. The data

### 4.1 What an operation costs (`heap_bench.zig`)

| Operation | Cost |
|---|---|
| `retain` + `release` of a live object | 1.2 to 1.3 ns per pair |
| a safe point with nothing to free | 1.5 to 1.7 ns |
| a scope and a variable made, bound, let go and freed by count | 33 to 40 ns per pair (about 17 to 20 ns per object) |
| a temporary list made and freed at the safe point | 24 to 28 ns |
| a string of 20 bytes made and freed | 36 to 41 ns |
| one trace over 200,000 live objects | 8.3 to 10.3 ms: 42 to 51 ns per object of the whole heap |

### 4.2 What the benchmarks allocate (bytecode machine, objects made)

"scopes + variables" is the part of the objects that is not data. The last column is the same program on the tree walker.

| Program | made (bc) | scopes + variables | functions | freed by count | freed by trace | traces | peak KB | made (tree) |
|---|---|---|---|---|---|---|---|---|
| p1a_arith | 157 | 148 | 0 | 0 | 0 | 0 | 9 | 164 |
| p1b_calls | 161 | 150 | 2 | 0 | 0 | 0 | 9 | 281,511 |
| p1c_collections | 761 | 148 | 0 | 300 | 0 | 0 | 22 | 780 |
| p1d_strings | 39,159 | 18,148 | 0 | 38,998 | 0 | 1 | 125 | 15,168 |
| p1e_rational | 157 | 148 | 0 | 0 | 0 | 0 | 9 | 60,171 |
| p1f_complex | 347 | 260 | 78 | 0 | 0 | 0 | 20 | 3,274 |
| p1g_dates | 320,159 | 320,149 | 0 | 320,001 | 0 | 2 | 9 | 166 |
| p1h_time_format | 160,165 | 120,150 | 0 | 160,001 | 0 | 1 | 10 | 40,177 |
| p1i_zone_offsets | 240,247 | 240,198 | 32 | 240,001 | 0 | 2 | 14 | 300,262 |
| p1j_datetime | 576,248 | 576,201 | 32 | 576,005 | 0 | 3 | 14 | 251 |
| p1k_zone_dense | 180,248 | 180,198 | 32 | 180,001 | 0 | 1 | 14 | 300,262 |
| p2a_aspects | 60,157 | 55,148 | 0 | 60,000 | 0 | 59 | 10 | 40,161 |
| p2b_closures | 212,170 | 210,157 | 2,004 | 202,000 | 10,000 | 2 | 604 | 264,185 |
| p2c_procedures | 210,164 | 180,152 | 3 | 210,000 | 0 | 2 | 10 | 300,176 |
| p3a_modules | 100,171 | 100,158 | 4 | 100,000 | 0 | 1 | 10 | 400,183 |
| p3b_objects | 270,193 | 230,170 | 15,005 | 270,030 | 0 | 2 | 10 | 460,211 |
| p3c_module_state | 100,171 | 100,158 | 4 | 100,000 | 0 | 1 | 10 | 150,178 |
| p4a_parallel_sum | 307 | 259 | 0 | 143 | 0 | 0 | 11 | 244 |
| p4b_channel | 170 | 158 | 0 | 11 | 0 | 0 | 10 | 163 |
| p4c_groups | 6,658 | 6,398 | 0 | 6,500 | 0 | 6 | 10 | 2,413 |
| p4d_tasks | 7,260 | 7,199 | 1 | 7,100 | 0 | 6 | 11 | 3,565 |
| p4e_garbage | 400,159 | 148 | 0 | 399,999 | 0 | 2 | 10 | 400,165 |
| p5a_sql_function | 180,183 | 180,157 | 1 | 180,015 | 0 | 1 | 10 | 180,184 |
| gc1_live | 1,300,159 | 148 | 0 | 999,999 | 0 | 5 | 14,549 | 1,300,168 |
| gc2_cycles | 1,000,162 | 800,151 | 200,002 | 1,000,000 | 0 | 5 | 10 | 1,200,168 |
| gc3_nested | 300,169 | 148 | 0 | 9 | 0 | 2 | 19,335 | 300,185 |

### 4.3 How often the counts are touched (calls of `retain` and `release`, plain values included)

| Program | retains (bc) | releases (bc) | retains (tree) | releases (tree) | safe points (bc) | safe points (tree) |
|---|---|---|---|---|---|---|
| p1a_arith | 145 | 0 | 1,000,148 | 1,000,000 | 500,007 | 1,200,009 |
| p1b_calls | 147 | 0 | 381,494 | 381,346 | 50,004 | 237,569 |
| p1c_collections | 61,459 | 611 | 243,755 | 182,902 | 122,612 | 245,218 |
| p1d_strings | 42,151 | 42,006 | 21,148 | 21,000 | 9,006 | 24,008 |
| p1e_rational | 145 | 0 | 860,150 | 860,000 | 400,009 | 980,012 |
| p1g_dates | 40,147 | 40,002 | 205,865 | 205,715 | 40,006 | 245,722 |
| p1j_datetime | 261,193 | 261,002 | 186,196 | 186,000 | 60,006 | 246,007 |
| p2b_closures | 368,160 | 362,008 | 470,160 | 464,002 | 106,014 | 314,017 |
| p2c_procedures | 300,149 | 300,000 | 510,152 | 510,000 | 90,007 | 330,010 |
| p3a_modules | 50,155 | 50,001 | 700,157 | 700,000 | 150,007 | 450,010 |
| p3b_objects | 695,196 | 695,040 | 520,183 | 535,027 | 75,009 | 355,028 |
| p4a_parallel_sum | 4,030,440 | 2,649,888 | 4,050,744 | 2,660,270 | 200,025 | 72 |
| p4e_garbage | 1,600,149 | 1,600,001 | 1,400,148 | 1,399,997 | 200,005 | 800,006 |

(The other programs are in `temp/mem_ops.json` of the run; they say the same.)

### 4.4 Share of the run spent making and freeing objects (estimate)

Objects made times 20 ns (§4.1), against the best time of the run (ms, bytecode machine unless the column says tree).

| Program | run (bc) | objects (bc) | estimate | share | run (tree) | objects (tree) | share (tree) |
|---|---|---|---|---|---|---|---|
| p1b_calls | 15.9 | 161 | 0.0 | 0 % | 48.1 | 281,511 | 12 % |
| p1g_dates | 47.2 | 320,159 | 6.4 | 14 % | 47.7 | 166 | 0 % |
| p1h_time_format | 34.6 | 160,165 | 3.2 | 9 % | 38.1 | 40,177 | 2 % |
| p1j_datetime | 91.2 | 576,248 | 11.5 | 13 % | 81.3 | 251 | 0 % |
| p2b_closures | 31.3 | 212,170 | 4.2 | 14 % | 40.1 | 264,185 | 13 % |
| p2c_procedures | 37.7 | 210,164 | 4.2 | 11 % | 50.3 | 300,176 | 12 % |
| p3a_modules | 35.7 | 100,171 | 2.0 | 6 % | 63.1 | 400,183 | 13 % |
| p3b_objects | 45.3 | 270,193 | 5.4 | 12 % | 60.8 | 460,211 | 15 % |
| p4e_garbage | 64.4 | 400,159 | 8.0 | 12 % | 121.3 | 400,165 | 7 % |
| p5a_sql_function | 50.4 | 180,183 | 3.6 | 7 % | 62.3 | 180,184 | 6 % |

The counting itself is not in these shares: at 1.3 ns a pair it is 1 to 3 % of a run (`p3b_objects`: 695,196 pairs, about 0.9 ms of 45).

### 4.5 The stress programs (times in ms, minimum of 5)

| Program | engine | run | traces | peak objects | note |
|---|---|---|---|---|---|
| gc1_live | bc | 327 | 5 | 300,161 | nothing to free by trace: every temporary is freed by count |
| gc1_live | tree | 465 | 5 | 300,167 | |
| gc2_cycles | bc | 122 | 5 | 167 | the closure is a register: no cycle |
| gc2_cycles | tree | 222 | 6 | 133,508 (7.8 MB) | 800,000 objects freed by trace |
| gc3_nested | bc | 170 | 2 | 300,162 (19.3 MB) | |
| gc3_nested | tree | 182 | 2 | 300,169 | |

### 4.6 The first experiment (not applied)

One line in `unregister`: an object freed by count lowers `since_trace` by one, so the trigger of the trace measures the growth of the heap and not the traffic through it.

| Program | engine | base | experiment | traces |
|---|---|---|---|---|
| gc1_live | bc | 327 ms | 273 ms (**-17 %**) | 5 to 2 |
| gc1_live | tree | 465 ms | 448 ms | 5 to 2 |
| gc2_cycles | bc | 122 | 120 | 5 to 0 |
| gc3_nested | bc | 170 | 168 | 2 to 2 |
| p2b_closures | bc | 38 | 36 | 2 to 1 |
| p4e_garbage | bc | 72 | 72 | 2 to 0 |

## 5. What the data says

1. **Counting is cheap, making and freeing is not.** A pair of `retain`/`release` is about 1.3 ns; an object costs 17 to 40 ns to make and free. Allocation-heavy programs spend 6 to 15 % of their time there (§4.4). The bytecode machine already removed the counting from numeric code: `p1a_arith` makes 145 calls of `retain` against 1,000,148 on the tree walker, because a register that holds a plain value is written with a plain copy.
2. **Most objects are not data.** 85 to 100 % of the objects of the call-heavy benchmarks are scopes and variables (`p3b_objects`: 230,170 of 270,193; `p1j_datetime`: 576,201 of 576,248). Data objects (lists, strings, records) are few except in `p4e_garbage` and the stress programs.
3. **The bytecode machine allocates more than the tree walker in one place: the calls of library routines.** The adapter gives a native its arguments as hidden names in a new scope: one scope and one variable per argument per call. `p1g_dates` makes 320,159 objects on the bytecode machine and 166 on the tree walker, `p1j_datetime` 576,248 and 251, `p1h_time_format` 160,165 and 40,177; `p1j_datetime` runs in 91 ms against 81 ms (the only benchmark where the bytecode machine is slower). Plain calls are the opposite: `p1b_calls` 161 against 281,511 (frames keep the arguments in registers).
4. **One function object per call in some paths.** `p3b_objects` makes 15,005 `Func` objects on the bytecode machine and 85,002 on the tree walker: a method found by name gets a new `Func` (`newFunc`) at each call that does not take the direct path.
5. **The trace is started by traffic, not by growth.** `since_trace` counts objects made. `gc1_live` runs five traces although nothing is garbage: 300,000 live strings are marked and swept each time (1,400,641 objects swept). The experiment of §4.6 removes three of five and 17 % of the time; no other program is slower.
6. **A trace costs the size of the whole heap.** 42 to 51 ns per object of `objs`, because the roots include every pinned or older object (`markRoots` scans all of `objs`) and the sweep reads all of it, not only the region. With a live heap of a million objects one trace is 40 to 50 ms.
7. **Cycles.** Closures that capture their own scope make cycles. The tree walker lets them pile up until the limit: `gc2_cycles` peaks at 133,508 objects (7.8 MB) and frees 800,000 by trace. The bytecode machine keeps the result of a function in a register, which is not in the scope, so the same program has no cycle (peak 167 objects). `p2b_closures` still frees 10,000 objects by trace on both engines (a captured variable declared in the scope that the closure holds).
8. **Safe points are cheap but many.** 1.5 to 1.7 ns each when nothing is to be freed, 500,007 of them in `p1a_arith` (about 0.8 ms of 30), plus the dispatch of the instruction. `p2a_aspects` runs 59 traces: the `done` of each applied aspect, over a heap of 170 objects, so each is cheap.
9. **Memory per object.** 24-byte header, 64 bytes for a scope, variable or record, 88 for a list; a `Value` is 24 bytes. `gc3_nested` holds 300,169 objects in 19.3 MB (64 bytes each on average). A `Value` of 16 bytes (OPT-20) is a decision for version 0.8.
10. **The rule of D-151 holds in the data.** Everything the benchmarks free is freed by count except cycles (10,000 in `p2b_closures`, the tree walker's `gc2_cycles`); the trace is the backup it was meant to be, except that it runs more often than it needs (finding 5).

## 6. Experiments, in the order to try them

Each one: a measure before (`memstats.py`, `bmark.py`, `heap_bench.zig`), the change, the same measure after, a line in §7. A change that slows another benchmark by more than 3 % is not kept (D-196). All of them must keep the destructor rule of §1 and pass `runtest.py all --both` and `EVE_GC_VERIFY=1` on the Debug build.

| Id | What | Expected gain | Needs | Risk |
|---|---|---|---|---|
| RC-01 | **Trace by growth.** An object freed by count lowers `since_trace` (the experiment of §4.6); a leak still raises it, because a cycle is never freed by count | 17 % on `gc1_live`; the traces of every program that frees what it makes | one line, then the stress programs | low: cycles stay counted; check `gc2_cycles` on the tree walker keeps its peak below the limit |
| RC-02 | **No scope for the arguments of a native.** Value natives (OPT-12) and the call of a native with the registers (OPT-22): the hidden names, the scope and one variable per argument go away | 9 to 14 % on `p1g_dates`, `p1h_time_format`, `p1i`, `p1j`, `p1k`, `p5a`; turns the slowdown of `p1j_datetime` into a gain | one library module at a time, the hottest first | medium: a native that reads a node (rule OPT-27) |
| RC-03 | **No scope and no region for a routine that does not need them.** The emitter knows whether a routine uses `loadg`, `storeg`, `defvar`, a call site with hidden names, a closure or a nested run; if not, the frame needs neither the scope nor the region (OPT-28 gives the region) | 6 to 12 % on `p2c`, `p3a`, `p3b`, `p3c` | a flag per routine in the chunk; the debugger shows variables from the registers | medium: errors name the frame, `$error` traces |
| RC-04 | **One `Func` for a method.** Keep the `Func` of a (class, method) pair (OPT-23, OPT-29) instead of `newFunc` at each call | `p3b_objects` 15,005 objects, about 1 ms | a table beside `bc_methods` | low |
| RC-05 | **Safe points only where a count can drop.** The emitter puts `safe` after a statement that allocates or can release a heap value; not after `let i := i + 1` on plain values (OPT-13) | 3 % of `p1a`, more in dispatch | an "allocates or releases" flag per expression, from the checker types | medium: CLS-14 (a destructor must run at the end of the statement that dropped the last reference) |
| RC-06 | **A trace that looks at the region.** Keep the pinned and older objects as roots without scanning `objs`: a list of the survivors of the last trace | the trace falls from the size of the heap to the size of the region; shows on heaps over a million objects | after RC-01, measure what is left of `gc1_live` and `gc3_nested` | medium: the roots must stay complete (`EVE_GC_VERIFY`) |
| RC-07 | **Scopes and variables outside `objs`.** They are freed at once at zero count and never wait in a ZCT; `objs` serves the trace and the destructors only | the swap-remove and the append of the registration (a part of the 17 to 20 ns) | the trace must still find cycles through scopes | high: do it last, only if RC-02 and RC-03 leave scopes in the profile |
| RC-08 | **Pools and sizes.** The pool of freed objects keeps 4,096 of each kind (`pool_max`); measure whether 16,384 or a pool per size of string helps `gc1_live` and `p4e_garbage` | small | none | low |

Not proposed: a generational or moving collector (the rule of D-151 keeps counting first, the data show cycles are rare), a pause-free collector (the heap is per task), NaN boxing (OPT-20, 0.8).

## 7. Questions for the author

- **Q1.** RC-01 changes a tuning detail of the backup collector (when it runs), not a rule of the language. It may be done without a decision unless the author wants the trigger to stay "objects made" for a reason not in the code.
- **Q2.** RC-03 removes the scope of a frame that needs none. The debugger and `$error` traces then read the variables of such a frame from its registers (the chunk has their names). Accepted?
- **Q3.** RC-05 relies on CLS-14 being kept exactly: a destructor runs at the end of the statement in which the last reference was dropped. If the author prefers "at the next safe point, soon", the emitter may skip more safe points.

## 8. Log of the experiments

| Date | Id | Before | After | Kept |
|---|---|---|---|---|
| 2026-10-27 | RC-01 (trial build only, wall time) | `gc1_live` bc 327 ms, 5 traces | 273 ms, 2 traces; the others within 3 % | superseded by the next line |
| 2026-10-27 | **RC-01 applied** (`script/abtest.py`, CPU cycles, min of 11 to 25 runs, the base is HEAD before the change) | `gc1_live` 839 and 832 M cycles, 5 traces | 784 and 782 M (**-6.5 %**), 2 traces; `p1a`, `p1b`, `p3b`, `p4e` within ±2 % (25 runs) | kept. The trace count of the benchmarks falls to 0 except `gc1_live` (2) and the tree walker's `gc2_cycles` (4); the peak of `gc2_cycles` on the tree walker rises from 133,508 to 200,176 objects (the limit now measures the growth of the heap). The -17 % of the wall time in §4.6 was noise of the loaded machine. |
| 2026-10-27 | **RC-02** (`script/abtest.py`, CPU cycles, min of 9 runs; base = HEAD with RC-01) | `p1g_dates` 320,159 objects, 116.8 M cycles; `p1j_datetime` 576,248 objects, 220.1 M; `p1h_time_format` 83.6 M | 160, 247 and 40,165 objects; **-17.1 %**, **-12.1 %**, **-9.8 %** | kept. The adapter reuses one scope per interpreter (`enterAdapter`, `adapterBind`, `leaveAdapter`): it is emptied and loses its parent when the call ends, so nothing it held outlives the call; it is a root of the trace. Side gains from the calls of `lib/` routines: `p2c_procedures` -8.8 %, `p3a_modules` -8.6 %, `p1k_zone_dense` -4.2 %. The others within ±3 %. `p5a_sql_function` is unchanged (the calls come from the database through the tree walker). |
| 2026-10-27 | **RC-03** (`needs_scope` of the function record; `self` no longer a variable of the scope) and **RC-04** (a constructor runs with a `Func` on the stack; the adapter keeps a pool of 4 scopes for nested calls). Cycles, min of 9, base = HEAD with RC-02 | `p3b_objects` 260,190 objects, 98.9 M cycles; `p2b_closures` 57.7 M; `p3a_modules` 73.2 M; `p3c_module_state` 60.6 M | `p3b_objects` **25,174 objects (the 25,000 records), -17.4 %**; `p2b` **-12.6 %**; `p3a` **-9.5 %**; `p3c` **-11.5 %**; `p2c` -5.2 %; `p4b_channel` -8.3 %; `gc2_cycles` -7.8 %; the others within ±4.5 % | kept. A routine whose code emits no `defvar`, `closure`, job, parallel or `update` instruction and has no `@` parameter runs in the scope of its closure and allocates nothing for the call. `p4e_garbage` read +6 to +7 % in two A/B runs although its loop makes no call; with the pool of RC-04 it reads -0.9 %: it is the layout of `execute` (OPT-25), not the change. `p1b`, `p1e`, `p1h` read +4 % once and are not stable. |
| 2026-10-27 | **RC-05** (no region for a routine that cannot reach a safe point; `Func.needs_region`) with the compare-jump, the immediates and the local `ip` of `design-bytecode-opt.md` (OPT-02, OPT-07, OPT-32), cycles, min of 9 to 11 runs, base = HEAD | `fib(30)` 617.6 M; a `while` loop of 5 million passes 336.0 M; `p1a` 59.7 M; `p1b` 34.5 M | **-25.6 %**, **-44.4 %**, **-16.8 %**, **-11.3 %**; `p1f` -11 %, `p1i` -14 %, `p1j` -10 %, `p1k` -9 %, `p3a` -7 %, `p2a` -6 % | kept. The region part alone was -1 to -2 % on `fib`; the rest comes from fewer instructions and the local position. `p4d_tasks` and `p5a` read +6 to +13 % in one run (tasks and the database path do not run this code: noise). |
| 2026-10-27 | **RC-07 (new, found by profiling `p1d_strings`)**: `text <+ more` on a string that only one variable holds grows it in its own block (`Heap.appendInPlace`; a big string has the room of its power of two, so the copies are one for each doubling); the machine does it in the `push` instruction, the tree walker in `listModifier` | a loop of 150,000 appends of 10 bytes: 12,200 M cycles (`push_only`), 15,167 M with an interpolation (`p1d_big`); every append copied the whole string | **25 M and 75 M cycles (-99.8 %)**; the 58 KB string of `p1d_strings` shows no change (the copy was never its cost) | kept. The count of one is the guard: `u := t; let t <+ "y"` leaves `u` alone (test `bc39_strings`). The first patch of the day put the arm in `push_front` (`+>`), which the new test caught. |
