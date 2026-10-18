# Gaps of the language found while writing the standard library (D-189)

One line per gap: what was missing or wrong, found by which module, where it should be fixed. Fix the language, never work around it in the library.

- **G-1** An error raised in a module of the standard library reports the file name of the *calling* script with the line of the module (`f03_test_module.eve:71` for a line of `lib/test.eve`). Found by `test`. Fix: the frame and the error carry the file of the code that raised.
**answer** good find and good fix.
- **G-2** The unhandled `raise "message"` ends with exit code 4; a test runner may want its own code. There is no `exit <code>` statement. Found by `test`. Decide (Q): `exit <code>;` or `$exit_code`.
**answer** No problem, enable exit <code>; and also over <code>. When you define new exit codes, add them in spec with description.
- **G-3** A user module that declares `external` cannot be bound to a native (D-191 (4)). Found by the signature files.
**answer** find a sollution.
- **G-4** *(closed by D-192: `recover` in a function, procedure and method)* A function, a procedure or a module can not catch an error: `recover` exists only at the end of a process (and aspect). A server library must turn the error of a handler into an error answer, not stop. Found by `rpc.dispatch` (a handler error propagates; `json.valid` was added so a bad text is tested before `json.parse`). Needs an author decision (Q-065): a `try` form, or `recover` in a function, or a native `call_safe`. Not decided by the model (author owns the syntax).
**answer** Enable recover region in any subprogram.
- **G-5** The collections have a thin method set in the VM: a `DataMap` has no `has`, `keys`, `values`, `get(key, default)`; the test `key in map` works. Found by `rpc`. Fix in the VM and the spec of collections before `config` and `route` need them.
**answer** Improve DataMap with proper methods.
- **G-6** `method` is a reserved word, so it can not be a parameter name (`rpc.request(id, method, params)` became `name`). Contextual keywords (D-116) would allow it. Low priority.
**answer** Enable contextual keywords.
- **G-7** *(found 2026-10-18 by `config`)* `String` had only `split`, `length`, `count` and the single-rune index: no slice `s[a..b]` (the spec says a string is indexed by runes and takes ranges), no `trim`, `upper`, `lower`, `starts_with`, `ends_with`, `contains`, `find`, `replace`. Closed by `spec/library/strings.md` and the VM on 2026-10-18 (tests a86, a87); Q-066 stays open for the regex reading.
- **G-8** *(found by `route`)* A module member with the name of a prelude module (`json`, `fs`, `time`, ...) hides that module for the whole module: `function json(...)` made `json.text(...)` inside it fail ("Function has no method 'text'"). `route.json` became `route.as_json`. Decide: reserve the names of the prelude modules, or let a qualified `prelude.json` reach them.
- **G-9** *(found by `route`)* In a string, `"{"` opens an interpolation: a literal brace needs `"\{"`; a pattern such as `{id}` must be written with escapes. Works as specified; noted because it surprised the first version.
