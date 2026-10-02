# Issues: collections.html

Page: `tutorial/collections.html` (now ~1,300 lines) and `tutorial/strings.html` (split from it, D-058).
Reviewed 2026-09-28; answers applied 2026-10-02 (D-058). How to answer: [README](README.md).

Retired (answered, applied to the tutorial, recorded in D-058; text in git history): COL-01, 04, 07, 08 (D-021,
D-022, D-049), 09, 10, 11, 12, 13, 17, 18, 19, 20, COL-F1 to F4, COL-I1 (page split). COL-I2 (operations table per
collection) is postponed to the specification, which synthesizes it.

## Questions

### COL-02 Map type notation
Answered: `List(...)` is optional, `(x)` is a one-element list, `{}` is the empty set and `{:}` the empty map (D-058).
Still open: the page uses `{}(String, Object)` for a map type while classes.html uses `{}(Type:Type)`. Which one is Eve?
**Answer:** _(open)_
Status: open

### COL-03 Builders: filter
Answered: generators combine with `and`; prefer open-ended ranges such as `(2>..n)` (D-058).
Still open: is there a filter clause (`| x in A if x > 2`), or only ranges and `and`?
**Answer:** _(open)_
Status: open

### COL-05 List operations: remaining doubts
The examples were rewritten by the author and corrected for `expect` names and comments. Still unclear:
- `a <+ b` gives `('a','b','1','3')` (append at the end). What is the reverse form: `b +> a` (inserts `a` before `b`,
  giving the same list as `a <+ b`) or `b <+ a` (what the page now says)? Which side is the list in `+>`?
- `lst -= lst[1]` removes the element at position 1, but `-=` with a value removes all equal values (so `'b' -= lst` and
  `lst -= lst[1]` would behave the same on a value). How do we remove by position: `lst -= lst[1]` as the page says,
  a method, or `del lst[1]`?
**Answer:** _(open)_
Status: open

### COL-14 Object attributes and the empty object
Answered: unquoted keys make an Object, quoted or numeric keys a HashMap; `{}` is an empty DataSet, `{:}` an empty
HashMap (D-058). With `&=` removed (D-058), the page now creates attributes by assignment (`object.x := 1;`).
Still open: is that right? And what is the empty Object: `let object :Object;` (Null), or a literal?
**Answer:** _(open)_
Status: open

### COL-15 String escapes
Answered: String is immutable, Text is a different mutable type (D-058).
Still open: are `&code;` escapes (`&alpha;`) the Eve escape mechanism, or does Eve use `\n` and `\u{...}`? (See D-019.)
**Answer:** _(open)_
Status: open

### COL-16 Placeholders and formats
The author does not know yet: import the Fortran-style formats (`"#(3i4)"`) and adapt them. Needs a proposal from the
model for the `print` / `format` specification, with the forms `"#{expr}"`, `"{a}"`, `"#n"`, `"#s"` compared (D-019, D-032).
**Answer:** _(open: proposal pending)_
Status: open

## Spec additions (pending)

- `spec/semantics/types.md` / `types.json`: collection types and notation (COL-02, 07, 13, 14; D-058).
- `spec/syntax/expressions.md`: builders, deconstruct, slices, `[*]`, absolute index (COL-03, 04, 09; D-058).
- `spec/lexical/operators.json`: collection and set operators, `=~` and `!~` (COL-05, 10, 18; D-058).
- `spec/lexical/lexical.md`: string escapes, text literals (COL-15).
- Operations table per collection (COL-I2): literal, type notation, create, add, remove, access, iterate, operators.
