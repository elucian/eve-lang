# Issues: collections.html

Page: `tutorial/collections.html` (now ~1,300 lines) and `tutorial/strings.html` (split from it, D-058).
Reviewed 2026-09-28; answers applied 2026-10-02 (D-058). How to answer: [README](README.md).

Retired (answered, applied to the tutorial, recorded in D-058; text in git history): COL-01, 04, 07, 08 (D-021,
D-022, D-049), 09, 10, 11, 12, 13, 17, 18, 19, 20, COL-F1 to F4, COL-I1 (page split), COL-02, 03, 14, 15 (D-059). COL-I2 (operations table per
collection) is postponed to the specification, which synthesizes it.

## Questions

### COL-05 Capture a removed element
Applied (D-060): `<-` removes the first element, `->` the last; a queue enqueues with `<+` and dequeues with `let e <- q`.
The capture forms `let e <- lst;` and `lst -> let e;` are my proposal: is a `let` inside a statement acceptable
(also `while let x in (range)`)?
**Answer:** _(open)_
Status: open

### COL-16 Interpolation formats
Applied (D-060): `\s{}`, `\#{}`, `{}` with formats (strings.html, "String interpolation and format"). Review the codes
and examples and tell me what to change.
**Answer:** _(open: review)_
Status: open

## Spec additions (pending)

- `spec/semantics/types.md` / `types.json`: collection types and notation (COL-02, 07, 13, 14; D-058).
- `spec/syntax/expressions.md`: builders, deconstruct, slices, `[*]`, absolute index (COL-03, 04, 09; D-058).
- `spec/lexical/operators.json`: collection and set operators, `=~` and `!~` (COL-05, 10, 18; D-058).
- `spec/lexical/lexical.md`: string escapes, text literals (COL-15).
- Operations table per collection (COL-I2): literal, type notation, create, add, remove, access, iterate, operators.
