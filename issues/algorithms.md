# Issues: algorithms.html

Page: `tutorial/algorithms.html` (99 lines: one `sqrt` example). Reviewed 2026-09-28. How to answer:
[README](README.md).

## Questions

### ALG-01 Purpose of the page
The page has one section ("Precision") with one example. Expand it into an algorithms page
(sorting, searching, recursion, iteration in Eve), merge the example into functions.html, or drop
the page from the index?
**Answer:** _(open)_
Status: open

### ALG-02 Native types in signatures
`function sqrt(x: f64, p = $epsilon :f32) => (z = 1.0 :f64)` uses native types in a script
(D-032) and a result with a default value and no `@` (D-028). Is a result default value allowed?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### ALG-F1 Wrong example
- `1^-2`, `1^-3`, `1^-10`, `1^-14` are all 1; the intent is `10^-2` etc.
- `repeat if` on a `loop` without `cycle` (see D-033, D-034).
- The precision loop stops when `z*z - x <= p`, but Newton's method approaches from above, so
  the check is fine only for positive errors; state it or use `abs`.
- The function is named `sqrt`, which hides a built-in of the same name (LIB-01).
**Answer:** _(open)_

### ALG-F2 Authoring standard
"We believe…", "Our strive is to create efficient software…".
**Answer:** _(open)_
