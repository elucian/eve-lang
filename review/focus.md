# Focus: make the tutorial good enough and feature complete

Status 2026-10-05. The tutorial comes first (`plan/README.md`, "Current focus"): it gives the complete vision of Eve and will shape the architecture of the interpreter. Parked until the author says go: the specification, the test suites, the VM (`evevm/`) and `demo/`.

Each item has a code (`F1`, `F2`, …) so it can be cited. Answer the questions on the `**Answer:**` lines; every batch is drafted as a decision (`D-nnn`) for review before any page changes.

## A. Review answers that are decided but not yet in the tutorial

From `review/04-subprograms-classes.md`. They change classes and subprograms on several pages, so they go first: the work of B and C builds on them. F2 is done (D-084); F1 and F3 are done (D-085).

**F1 Keyword `generator`** (RSB-R03, RSB-X02). **Done: D-085** (2026-10-05), applied in multitasking, functions, syntax and the highlighters. A generator is declared with its own keyword: `generator count_to(n: Integer) => (@x: Integer) is … return;`. It replaces the rule of D-067 that a method containing `yield` is a generator. Pages: multitasking, functions, syntax.
**Answer:**
Confirmed. Implement in tutorial and mark done.

**F2 Construction** (RSB-D03, RSB-R04). **Solution found and applied: D-084** (2026-10-05). The constructor is a subprogram whose result is the new object: `constructor(name: String) => (@self) is … return;`. Its first statement is the construction: `let self := Object();` at the root, `let self := Shape(name);` in a subclass. The object is constructed up the chain: allocated once by `Object()` with the memory of the target class (the class of the outermost call, `new c := Circle(…)`), then handed down; each constructor has its own `self`, its own result, and they refer to the same object. A class without a constructor is filled by name. For the compiler every constructor is an ordinary function returning an object, with the target class as its one hidden argument: correct and implementable. Taught in classes.html, section Construction.
Still open: an implicit `self` in methods inside a class body (RSB-D03). Today `@self` in the parameter list tells an object method from a class method; with an implicit `self`, how would a class method (no object) be marked?
**Answer:**
Solution fond and implemented. 

**F3 Visibility by English words** (RSB-X01, RSB-R05). **Done: D-085** (2026-10-05): `public`, `protected`, `private` in classes; `export (…)` in modules; module level holds functions and extension methods. The open points of D-085 are answered by D-086: every subprogram outside a class is a function, with or without result; a function without result needs no `!`; Methods move after Classes and are about extension methods. Words instead of the prefixes `.` (public) and `_` (protected, extension); `!` stays for unsafe functions and methods. This is the largest change: `.` marks every public member in modules, classes and examples, on almost every page.
Questions: the words for (a) public members: `public`? (b) private members: the default, without a word? (c) protected class members: `protected`? (d) extension methods: `extend` or `extension`?
**Answer:**
Yes, Eve is verbose, use public/private/protectd for methods defined inside a class. At module level we define functions and extension methods.  At module level we use "export" that is simetric to "import" so modules can export members, including classes, functions and extension methods. Extension methods can be used only inside the aspect or module that define them. Exported methods can be used in aspects that import modules having the extensions.

## B. Pages missing or out of date

**F4 databases.html** (RIO-D02, RTU-S01). Rewrite the page from `plan/design-database.md`. Before that, answer the 8 questions at the end of the design note; the two that shape the page: the engine of the Eve database (SQLite embedded, or an engine of our own) and parallel writes with their own connection.
**Answer:**

**F5 New pages for the data client** (`review/10-tutorial-plan.md`, phase T1). Without them the tutorial has no ETL story between Strings and Databases:
- Files and Paths (`files.html`): `fs`, `path`, text and bytes, lines as a stream, globbing;
- Data Formats (`formats.html`): JSON into DataMap and records, CSV with a header, round trips;
- Streams (`streams.html`): `Stream(:T)`, batches, back-pressure, dataflow operators;
- HTTP Client (`http.html`): requests, JSON bodies, errors, time-outs, tokens as secrets;
- ETL Pipelines (`etl.html`): extract, transform, load with jobs, checkpoints, the run log.

Question: all five pages, in this order, placed between Strings and Databases in the index?
**Answer:**

**F6 library.html.** The standard library page still shows the old built-in list. It should list the modules and what each holds: `io`, `exception`, `fs`, `path`, `json`, `csv`, `http`, `time`, `database`, `task`, with links to their pages.
**Answer:**

## C. Page-by-page review (plan step T1.10)

**F7 Full review of the remaining pages.** 15 of 20 pages never had the full review: classes, collections, processing, multitasking, library, command, databases, algorithms, manifest, option, compiler, modules, methods, strings, exceptions. A review checks every example against the current decisions (D-074 to D-083 changed many), finds old dialect and gaps, and writes open questions into `issues/<page>.md`.
Question: which order? Proposal: classes, collections, processing, multitasking, then the others.
**Answer:**

## D. Open questions from earlier drafts

**F8 Small open points**, each one line:
- the name of the 128-bit integer, `Huge` (D-080);
- the class names of the standard errors, `IoError`, `KeyError`, … (D-081);
- the order of levels 4 and 5: parallel before database, or database first (`plan/version_map.md`);
- the time types, Instant and DateTime (`plan/decision_level3.md`).
**Answer:**

## Suggested order

F1–F3 done; next F4, then F5 and F6, then F7 page by page. F8 any time.
