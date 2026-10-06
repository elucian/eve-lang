# Issues: library.html

Page: `tutorial/library.html` (217 lines, two `h1`: "Standard Library" and "System Library"). Reviewed 2026-09-28. Applied to the tutorial 2026-10-06 and retired: LIB-03 (`read(@v, prompt)` as a statement), LIB-04 (`write` and `print` signatures), LIB-05 (`error`, `warning`, `log_err`, `log_wrn`, unhandled errors), LIB-06 (escapes and `&code;`, in the Standard output section), LIB-F1 (one `h1`, input/output wording), LIB-I1 (built-in table from the spec: after version 1.0). The spec text for LIB-06 and the module `io` of `evevm/lib` are still to write; `evevm/lib/io.eve` still uses the `.name` prefix of D-085. How to answer: [README](README.md).

## Questions

### LIB-01 Built-ins for 0.1
The standard library table lists string functions (`length`, `count`, `truncate`, `fill`, `erase`, `find`, `replace`, `parse`, `trim`, `left`, `right`, `center`, `indent`, `pad`). Other pages use `format`, `floor`, `ceiling`, `round`, `random`, `sqrt`, `sum`, `type`, `split`, `join`. Which built-ins must the VM provide in 0.1? Are the string ones functions (`trim(s)`), methods (`s.trim()`), or both (COL-20)?
**Answer:** Both. If we can we implement public methods in string package and we can implement String class.
Status: answered (D-053): functions and methods; the String methods live in the string module of `evevm/lib/`, the list is still to write

### LIB-02 Mutating string functions
Strings are immutable (collections.html), but `truncate`, `fill` and `erase` "reduce the
capacity", "replace all characters". Do they return a new string?
**Answer:** Yes, they return a new string, the old string is replaced. The old references to the string are preserved. If there is no reference left, the string is mark to be removed by garbage collector.
Status: answered (D-053): to apply in the tutorial and in `evevm/lib/`

## Spec additions once answered

- `spec/library/builtins.md`, `builtins.json` (LIB-01..04).
- `spec/lexical/lexical.md`: string escapes (LIB-06).
