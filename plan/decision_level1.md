# Decisions, level 1: project and single script

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

The log is split in two files. Ids are shared and keep counting across both (an id not found here is in the other file); a new entry goes to the file of its topic:

- [decision_level1.md](decision_level1.md): the project (formats, repositories, licenses, the VM, tests) and the language of a single script (lexical rules, control flow, types, collections, functions, classes, errors in a driver). Matches `test/level1`.
- [decision_level2.md](decision_level2.md): programs made of several files: processes, aspects, modules and imports, libraries, multitasking and parallel aspects. Matches `test/level2`.
- Levels 3 to 7 (data, parallel, database, server, web): [decision_level3.md](decision_level3.md), [decision_level4.md](decision_level4.md), [decision_level5.md](decision_level5.md), [decision_level6.md](decision_level6.md), [decision_level7.md](decision_level7.md); the table of all levels is in decision_level3.md and [version_map.md](version_map.md).

## D-039 Traits, abstract classes, partial methods (2026-10-01, proposed)
Proposed by the model after reviewing the partials section of classes.html. Awaiting author confirmation. Touches CLS-07 and CLS-08.
- Problem: "partial" meant trait, interface, abstract class and prototype constructor at once; a partial constructor carried state, so multiple inheritance had attribute conflicts; an unimplemented method returned `Null` at run time.
- Vocabulary: a **partial method** is a signature ending in `;`. An **abstract class** is a class with at least one partial method. A **trait** is `trait Name is … end Name;`.
- Trait: no attributes, properties, constructor or destructor (no state, no instances). It holds required methods (partial) and provided methods (with a body, which may call the required ones through `@self`). `@self` is untyped and means the adopting class. A trait can be generic (`trait Comparable(:T)`) and can be used as a type (`let p: Printable := c;`, `x is Printable`). `trait` is a keyword; it closes with `end` (D-037).
- Abstract class: has attributes and a constructor, cannot be created with `new`; only a subclass constructor calls it, by its name (`self := new Shape(name);`). The partial constructor is removed.
- Inheritance list `<: (A, B, …)`: at most one superclass that carries state (default `Object`), any number of traits (CLS-07). A method of the class wins over a trait method; two traits that provide the same method need an explicit implementation in the class, otherwise a compile error.
- A class with a constructor must implement every inherited partial method: a missing one is a compile error, never `Null` (CLS-08).
- The `for` loop uses the library trait `Iterable`.
- Applied to classes.html (partials section rewritten), syntax.html (keyword `trait`), collections.html.
- Open: adopting a trait for an existing type outside its declaration (an extension, in another module), for example `Integer` adopting `Printable`; and the exact list of library traits (`Iterable`, `Comparable`, `Printable`).
- Todo: library traits `Iterable`, `Comparable`, `Printable`: step S5.1a in `plan/phase-5-conformance.md`.

## D-106 Order of parameters: a mandatory parameter after optional ones is named at the call (2026-10-07)
Author answer to Q-036; replaces the order rule of D-105.
- Every `@` parameter is an input/output parameter; there are no pure output parameters.
- A mandatory parameter may be declared after optional parameters (typically `@op`), but the call must give it by name: `add(1, 2, op: @result)`; `add(1, 2, @result)` is an error. Mandatory parameters before the first optional one stay positional.
- Confirmed by the author the same day: such parameters can't be positional; after optional parameters they must be called with names. That's all.
- Applied: `subprograms.html` (Optional, Order, by reference), `declarations.md`.

## D-107 The list stays after `+>` and before `<+` (2026-10-07)
Author answer to Q-017: the operators are suggestive arrows, so the direction tells the side. `x +> lst` puts `x` in front of the list (the list is after the arrow); `lst <+ x` appends `x` (the list is before the arrow). This is the proposal of Q-017 and what the spec and tests already used (`operators.json`, `statements.md`, a10); only the rule is added to `expressions.md` and collections.html.

## D-108 Date, Time and `as` are outside level 1 (2026-10-07)
Author agreed with the proposal. `Date`, `Time` and the operator `as` (format and conversion) are left to level 3, the data language (version 0.2, "Decimal, time, records"). The word `as` stays reserved in `keywords.json`, so the level 1 grammar is closed without them and no level 1 test covers them. Applied: `spec/conformance/README.md`. The tutorial page datetime.html keeps the examples.

## D-109 Error codes, system variables, lambdas and closures (2026-10-07)
Author answers for level 1.
- **Error codes.** Accepted as drafted in exceptions.html (D-054): `$err_panic` 1, `$err_expect` 2, `$err_assert` 3, `$err_raise` 4, `$err_index` 10, `$err_key` 11, `$err_divide` 12, `$err_overflow` 13 …; warnings `$wrn_deprecated` 5, `$wrn_truncate` 6, `$wrn_unused` 7. Rule: one code for one defined error, so index, key, division and overflow have their own error codes (`$error.code`); a35 to a37 check them. **Correction (same day, author):** exit codes are not error codes (D-081). The exit codes are 0 end/`over`, 1 `panic`, 2 failed `expect`, 3 failed `assert`, 4 any other unhandled error, 5 unexpected stop (Ctrl+C, halted or timed-out program, outage). `over;` runs `finalize`. My first version of `errors.md` had lost D-081 (unhandled error "with the code of the error", `over` skipping `finalize`, no code 5); fixed in `errors.md`, `statements.md`, `keywords.json`, a33, a51, compiler.html, exceptions.html.
- An undefined name and an operand of the wrong type are compile errors: see D-110.
- **System variables.** A driver can set `$epsilon` and any other system variable, and can define its own `$name` variables (variables.md, point 6 closed).
- **Lambdas and closures belong to level 2**, not level 1 (conformance/README.md).
- **`exit;` ends with code 0**, like `return` (author, same day); `finalize` runs. Closes the open point of D-010.

## D-110 Eve is a compiler: names and types are checked before the run (2026-10-07)
Author answer. Eve first analyzes the whole script, it does not interpret line by line like Python. An undefined name and an operand of the wrong type are **compile errors**: the script does not start, the VM reports the message and exits with 65 (as a44, a45, a47); they are never error values, can't be caught by `recover` and have no `$err_` code. Applied: `errors.md` (the list of run-time errors no longer has them).

## D-111 `exit` leaves the current subprogram or process; `over` ends the whole process (2026-10-07)
Author question and answers. Since `over` runs `finalize` (D-081), the two statements had no difference.
- **`exit;`** leaves the subprogram or process it is written in and gives control back to the caller: an early `return` in a function, procedure or method (a function keeps the results assigned so far; `defer` runs); in `main` of a driver the program ends with code 0 and `finalize` runs; in the main process of an aspect it ends the aspect.
- **`over;`** ends the whole process it is in, from any depth (also from a function that the process called), with code 0; no `recover`, `finalize` runs. In an aspect the driver continues after `apply`; in the driver the program ends.
- `panic;` stays the abnormal end of the whole application (code 1, no `finalize`).
- Applied: `statements.md`, `keywords.json`, `errors.md`, syntax.html, processing.html; tests a69 (`exit` in a procedure) and a70 (`over` from a procedure).
