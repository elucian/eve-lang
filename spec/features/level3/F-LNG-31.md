# F-LNG-31 Complex numbers

The type `Complex`: the imaginary literal `i99`, a complex number written as a sum `(10 + i99)`, `+ - * /` and `^`, equality without order, printing, and the library module `complex` (`spec/semantics/types.md#complex`, `spec/library/math.md#module-complex`). Two f64; a division by zero is `$err_divide`, a result out of range `$err_overflow`.

## Missing

- The data edges: JSON and CSV output, SQL parameters and columns, command-line parameters and the checkpoint store (TD-70).
- Functions of a complex argument in `trig` (`sin`, `cos`, ...) and the roots of a polynomial.
