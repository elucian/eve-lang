# F-LNG-30 Rational numbers

The type `Rational`: the literal `3\4`, exact `+ - * /` and `^`, exact comparison, printing, and the library module `rational` (`spec/semantics/types.md#rational`, `spec/library/math.md#module-rational`). Two 64-bit integers in lowest terms; an overflow is `$err_overflow`, never a rounding. Speed: the benchmark `p1e_rational` compares it with Python's `fractions` (10 to 15 times faster).

## Missing

- The data edges: JSON and CSV output, SQL parameters and columns, command-line parameters and the checkpoint store (TD-68).
- `%` and a fractional power are errors; fractions beyond 64 bits are `$err_overflow` (TD-69).
