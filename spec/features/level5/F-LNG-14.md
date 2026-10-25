# F-LNG-14 Record types and optional values

Typed records for rows, JSON objects and messages; `T?`. *State:* records, `null` in plain fields and printing of `null` are tested; the full optional type is in `spec/library/data-language.md`.

## Missing

- Built (D6, tests e145 to e150): the default `x ?? d`, the compile-time checks of `T?` in operators, method calls and assignments, and the narrowing by `<> null` and `== null` with exit (types.md#narrowing-and-the-default).
- Built (TD-87): a `T?` argument for a plain parameter, the narrowing in `while` loops (tests e167, e168), and the `NULL` into a plain member (e169).
- The cases of `data-language.md` as tests.
