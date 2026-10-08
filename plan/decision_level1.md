# Decisions, level 1: project and single script

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

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
- Applied: `statements.md`, `keywords.json`, `errors.md`, syntax.html, processing.html; tests b35 (`exit` in a procedure) and b36 (`over` from a procedure).

## D-115 Grammar checked against the examples (S3.6, 2026-10-08)
The EBNF of `spec/syntax/grammar.md` is now converted to a Lark grammar and run on the examples by `python script/grammarcheck.py` (needs `pip install lark`). Result: **139 of 139 files of `test/level1/` and `test/level2/` behave as the tests expect**: every other file parses, every file whose `/*@expect*/` says `"syntax_error": true` is refused or, when the error is semantic, accepted by the grammar and refused by the later checks (24 files, see Q-037 h). First run: 109 of 139. `pattern/` and `tutorial/demo/` do not parse yet: they use modules, `from … use`, `generator` and `parallel` (levels 3 and 4) and the legacy regions.
- **Gaps of the grammar, fixed** (each one came from an example or from the prose of the spec): the rules `members`, `names`, `lambda`, `property` and `variable-stmt` were used but not defined; `new a, b :Integer;`; array types with several dimensions `[2, 2]Integer`; the open end on the left `(?..0)` and on the right `(0..?)`; `(k: v)` in a `for`; trailing comma in lists, arrays and braces; `*rest` in a deconstruction; a rune as the key of a map; extension methods outside a class; `new self.x`; `set $epsilon = 0.5;`; `let lst -> new f;`; `apply folder/name();`; a lambda as an argument; `@result!` and `new a! := …`.
- **Removed:** `property` (attributes are in the signature of the class) and `variable-stmt` (`new` is a declaration and a statement).
- **Changed in a test:** `a76_overflow` named a variable `one`, a reserved word; renamed to `unit` (Q-037 c).
- **Q-037 Syntax points found by the check (answered 2026-10-08 → D-117).** The grammar accepts them as *(proposed)*, or reflects the tests; each needs a yes or a no:
  - (a) Types of a list and of a DataSet: `()Integer` and `{}Integer` (tests b39, b18), by symmetry with `[]Integer`.
  **answer** Correct assumption. Accepted.
  - (b) `<+` and `+>` as expressions that return a new list (a10, a17); `operators.json` calls them modifiers and leaves their precedence open. The grammar puts them at the level of `+` and `-`. 
  **answer** Perfect assumption. Accepted.
  - (c) ~~`one`, `all` and `other` are reserved words, but they are common names.~~ Answered: contextual (D-116).
  **answer** Correct, whenrever possible additional words of a statement are contextual.
  - (d) A variable that holds a stochastic function ends with `!` (`new a! := make_counter!(0); a!();`, b19) and so does a result name (`@next!`).
  **answer** Only is the result is a function.
  - (e) ~~`$error.job`: `job` is a keyword used as an attribute.~~ Answered with (c): `job` is contextual (D-116).
  **answer** job is not contextual, it is a reserved keyword like "if" and "match" and "parallel".
  - (f) `self` is an ordinary name, not a keyword, but `new self.x` is allowed only with it.
  **answer** `self` is reserved name, when used must represent the current object, and is going to be very confusing if used with other meaning.
  - (g) `defer` is level 1 in the test a74 and a later level in `statements.md` (moved to level 2 by D-122).
  **answer** Accepted.
  - (h) 24 tests carry `"syntax_error": true` for errors that the grammar does not see (undefined name, wrong type, redeclaration, missing argument…). The key means "refused by the compile step". Rename it `compile_error`, or keep it?
  **answer** syntax_error is correct. We do not have a compiler we have a virtual machine that parse and execute. So, the term is better as it is.

## D-118 A scalar operator applies to every element of a List or Array (2026-10-08)
Author request. `list op scalar` with `+ - * / % ^ < > <= >= =~` applies the operator to each element: `let a += 5;` on `(1, 2, 3, 4)` gives `(6, 7, 8, 9)` (in place), `a * 2` returns a new collection of the same kind. This **replaces** the old meaning of `+=` (append) and `-=` (remove by value) on a List or Array: append is `<+`, removal is `.delete(v)`. Strings are not bulk: arithmetic with a string element or scalar is an error (build a new collection with a loop); a regular expression `list =~ "/re/"` is the exception, it returns booleans. `==` and `<>` stay whole-collection comparisons. DataSet and DataMap keep `+=`/`-=` as add and remove (a bulk update could merge elements). Consistency (author, same day): appending an element or an object is always `<+`, never `+`. Not done, to be confirmed: scalar on the left (`2 * lst`), bulk on DataMap values, `in`/`is`. Tests a83, a84; a17 changed. VM: `Interp.broadcast`.

## D-116 Prefer contextual keywords to reserved keywords (2026-10-08)
Author decision, answers Q-037 (c) and (e): **whenever the grammar allows it, a keyword is contextual**, not reserved. A contextual keyword is a keyword only at the places where the grammar expects it; everywhere else it is an ordinary name (`new one := 1;` is valid, `match x one` is the option). **Correction (D-117):** `job` is not contextual, it stays reserved like `if`, `match` and `parallel`; `$error.job` is the one place where the grammar allows it after a dot.
- A new keyword is first considered as contextual. It stays reserved only when its position cannot tell it from a name: the words that start a statement or a declaration (`new`, `let`, `if`, `match`, `return`, `apply`, `defer`, `class`, `function`…), the words that close a block (`done`, `end`, `repeat`), and the operator words (`and`, `or`, `not`, `is`, `in`…).
- Applied: `keywords.json` marks eight words `contextual: true`: `all`, `one`, `other` (options of `match` and `when`), `exclusive`, `concurrent` (before `aspect`), `public`, `protected`, `private` (at the start of a class member). The schema has the new optional field; `lexical.md` states the rule; the grammar needs no special case for `.job` any more; `script/grammarcheck.py` reads the flag and accepts these words as names.
- `a76_overflow` uses `one` as a variable again; the VM already read it as a name, and the grammar check and the VM test pass.
- To do: the keyword tables of the tutorial (`syntax.html`), when they are regenerated from `keywords.json`, show the column; the words of the levels 3 to 7 (`start`, `wait`, `call`, `yield`, `parallel`, `trait`, `generator`, `export`, `use`, `from`) are reserved today and are candidates to become contextual when their level is specified.

## D-117 Answers to Q-037: syntax points found by the grammar check (2026-10-08)
Author answers, written under each point of Q-037 in D-115. Applied to `grammar.md`, `keywords.json`, `statements.md`.
- **(a) Types of a list and of a DataSet** are `()Integer` and `{}Integer`, like `[]Integer`. Accepted.
- **(b) `<+` and `+>` as expressions** return a new list, at the level of `+` and `-`. Accepted.
- **(c) Contextual words.** Accepted, with the rule of D-116: whenever possible the additional words of a statement are contextual.
- **(d) A name ends with `!` only if its value is a function** (`new a! := make_counter!(0);`). The grammar writes `name!` for any variable; the check that the value is a function belongs to the semantic checks (a compile error otherwise).
- **(e) `job` is reserved**, not contextual, like `if`, `match` and `parallel`. The keyword is allowed after a dot only for `$error.job`.
- **(f) `self` is a reserved word.** It names the current object only. `keywords.json` lists it (declaration); the grammar takes it as the start of a name path (`self.x`, `let self := Object();`) and not as a declarable name: `new self := …` and a parameter named `self` are refused.
- **(g) `defer` belongs to level 1.** `statements.md` documents it (a registered statement runs when the subprogram ends, in reverse order); `keywords.json`: stable.
- **(h) `syntax_error` stays** the key of a negative test. Eve has a virtual machine that parses and executes, not a separate compiler, so "refused before the run" is a syntax error for the tests.
- `python script/grammarcheck.py`: 139 of 139 files still behave as expected after the change.
- **Numeric references removed.** `&#N;` and `&#xH;` no longer exist; `{U+H…}` is the one numeric form. `&name;` stays. Replaces the numeric part of Q-014.

## D-120 A placeholder holds a name or any literal; its quotes are not escaped (2026-10-08)
Author decision. `{399}`, `{"test"}`, `{(a,b,c)}`, `{'x'}`, `{True}` and `{U+03B1}` work in a string: a placeholder holds a name (D-102) or a literal, written by its type. Inside the braces a double quote is not escaped (`"{m["b"]}"`); the lexer follows the braces and the quoted text in them, so the string closes at the first `"` outside the braces. A literal brace or a `%` inside a quoted text of a placeholder is not special, but a quoted text is an ordinary string: its own braces are escaped (`{"\}"}`). Operators and calls are still not allowed (Q-015). `{U+03B1}` is no special form: it is the rune literal U+03B1 inserted by its value, which makes the D-119 notation free. The old `\"` in a placeholder is still read. Regex literals (a string starting with `/`) have no placeholders and are not affected.

## D-121 Simple expressions in placeholders (2026-10-08)
Author decision, extends D-120. A placeholder holds a name, a literal or a **simple expression**: operators, comparisons, logical operators, member selection and calls, such as `{n + 1}`, `{a * 2 - 1}`, `{s.length()}`, `{a > 2}`, `{s + "!"}`. The VM already parsed any expression; this decision makes it the rule. `%` always starts the format: a remainder or any expression that needs `%` is written in parentheses around the whole placeholder content, `{((n + 1) % 3)}`. Statements, assignments and lambdas are not expressions of a placeholder.
