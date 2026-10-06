# Issues: algorithms.html

Page: `tutorial/algorithms.html` (99 lines: one `sqrt` example). Reviewed 2026-09-28; fixes ALG-F1 and ALG-F2 applied 2026-10-06 (`root` with `10^-2`, `abs` in the loop, authoring sentences removed). How to answer: [README](README.md).

## Questions

### ALG-01 Purpose of the page
The page has one section ("Precision") with one example. Expand it into an algorithms page (sorting, searching, recursion, iteration in Eve), merge the example into functions.html, or drop the page from the index?
**Answer:** _(open)_
Status: open

### ALG-02 Native types in signatures
`function sqrt(x: f64, p = $epsilon :f32) => (z = 1.0 :f64)` uses native types in a script (D-032) and a result with a default value and no `@` (D-028). Is a result default value allowed?
**Answer:** _(open)_
Status: open
