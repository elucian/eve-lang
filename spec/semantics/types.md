# Types

Status: **draft**, level 1. The Date, Time and Duration types are not part of level 1.

Eve is gradually typed: a declaration may give a type (`:Integer`) or leave it to inference. The type of a variable never changes, except a variant (below). A native type is used only by core libraries; scripts use the primitive types.

## Native and primitive types

| Type | Size | Literal | Zero value |
|---|---|---|---|
| `Logic` | ordinal `{False, True}` | `True`, `False` | `False` |
| `Byte` | u8 | `255b` | `0b` |
| `Short` | i16 | `11w` | `0` |
| `Integer` | i64 | `42` | `0` |
| `Natural` | u64 | `0x2A`, `0b101`, `42n` | `0` |
| `Huge` *(name to confirm)* | i128 | `-9000000000000000000z` | `0` |
| `Real` | f64, IEEE-754 double | `3.14`, `5r` | `0.0` |
| `Float` | f32, IEEE-754 single | `1.5f` | `0.0` |
| `Decimal` | exact base 10 | `12.50d` | `0d` |
| `Rational` | exact fraction, two i64 in lowest terms | `3\4` | `0` (`0\1`) |
| `Complex` | two f64: real part and imaginary part | `(10 + i99)` | `(0 + i0)` |
| `Date`, `Time`, `Duration` | a day, a time of the day, a length of time ([../library/time.md](../library/time.md)) | none, made by `time.date(...)`; `30s` for a `Duration` | `1970-01-01`, `00:00:00`, `0s` |
| `Rune` | one Unicode code point (32 bits, up to U+10FFFF) | `'a'`, `U+0061` | `''` (`nil`) |
| `String` | immutable UTF-8 text | `"text"` | `""` |
| `Text` | mutable text | `"""…"""`, `<text>…</text>` | `""""""` |
| `Null` | the type of `null` | `null` | |

- A decimal literal without a point is an Integer (never negative: `-5` is the operator `-` on `5`); with a point a Real. A suffix (`b w n z r f d`) gives another type; hexadecimal literals take no suffix. Native types `u8 … u64`, `i8 … i64`, `f32`, `f64` are reserved for core libraries.
- A real literal may have an exponent (`1.5e3`, `2e-3`): it is always a Real. `"1,000,000"z` is a number: a string followed by a type suffix. `Rational` (`3\4`) and `Complex` (`(10 + i99)`) are described below.
- `nil` is the empty rune `''`, a value of `Rune`. `Null` is a type and `null` its only value; no object exists, nothing is allocated. `0`, `""`, `''`, `()`, `[]`, `{}` are values, not null. A variable without a value gets the zero value of its type, never `null`. A variable that may be null has an optional type, `T?`.
- Names are case sensitive: `Null` and `null` are different names.

## Rational

A `Rational` is an exact fraction: a numerator and a denominator of 64 bits, kept in lowest terms with a positive denominator, so `2\6 == 1\3` and the sign is on the numerator. The literal is digits, a backslash and digits: `3\4`; a negative fraction is the operator `-` on the literal (`-3\4`). A denominator of zero in a literal (`1\0`) is the error `$err_divide` (12) when the literal is evaluated.

- **Printing.** `1\3 + 1\6` prints `1\2`; a whole value prints as the integer (`6\3` prints `2`). `type(x)` is `Rational`.
- **Operators.** `+ - * /` and `^` with a whole exponent are exact. An `Integer` in the other operand is converted (`1\3 + 1` is `4\3`); `/` of two Rationals is a Rational, `/` of two Integers stays a `Real` (`9 / 3` is `3.0`; write `9\1 / 3` or `9\3` for a fraction). With a `Real` or a `Float` the result is a `Real`. With a `Decimal` it is the error `$err_argument` (17): money never meets a fraction by accident. `%` is not defined.
- **Comparison.** `== != < <= > >=` are exact, also between a Rational and an Integer; with a `Real` the Rational is converted to a `Real` first.
- **Limits.** A numerator or a denominator that does not fit in 64 bits after reduction is `$err_overflow` (13); there is no silent rounding. The intermediate products are computed in 128 bits, so a result that fits is never lost.
- **Declaration.** `new x = 5 :Rational;` converts the Integer; the zero value is `0`. `floor`, `ceiling` and `round` give an `Integer` (`round` takes halves away from zero). The library module `rational` ([../library/math.md](../library/math.md#module-rational)) builds fractions from a `Real` or a text and takes them apart.

## Complex

A `Complex` is a number with a real part and an imaginary part, two `Real` (f64). There is one new literal, the **imaginary literal**: the letter `i` and a number written together, `i99`, `i2.5`, `i1e3`, a pure imaginary number (`0 + 99i`). A complex number is an expression that adds a real number and an imaginary one, written in parentheses by custom: `(10 + i99)`. `i1` is the imaginary unit. A name such as `i1` or `i99` is therefore never a variable: write `n1` or `idx` instead; `i` and `index` are names as before.

- **Printing.** The form of the literal: `(10 + i99)`, `(3 - i4)`, `(0.5 + i1)`; a whole part prints without a point. `type(z)` is `Complex`.
- **Operators.** `+ - * /` and `^` work on a Complex and on a Complex with an `Integer`, a `Real`, a `Float` or a `Rational` (the plain number is a Complex with an imaginary part of zero). `^` with a whole exponent is repeated multiplication (exact for whole parts, `(1 + i1) ^ 4` is `(-4 + i0)`); any other exponent is `exp(b * log(a))`. Dividing by zero is `$err_divide` (12); a result that is not finite (an overflow of a part) is `$err_overflow` (13). With a `Decimal` the operators give the error `$err_argument` (17), at compile time when the types are known.
- **Comparison.** `==` and `<>` compare the two parts exactly. A Complex has no order: `< <= > >=` are a compile error, or `cannot compare` at run time.
- **Declaration.** `new z :Complex;` starts at `(0 + i0)`; `new z = 2 :Complex;` converts a real number. The module `complex` ([../library/math.md](../library/math.md#module-complex)) takes numbers apart and has the functions: modulus, argument, conjugate, polar form, `exp`, `log`, `sqrt`, `pow`. `abs(z)` of module `basic` is the modulus.

## Conversions

- There is no implicit conversion between numeric types except widening in arithmetic: Integer with Real gives Real. `/` always gives a Real.
- `new x = a / b:Integer;` and `Integer.parse("3.7")` convert as the developer asked: the decimals are dropped, there is no run-time error; a debug mode warns "possible data loss" with the line.
- `parse` coerces to the type of the target. `s <+ 1` appends a number as text. `as` formats a value (version 2).

## Composite types

| Type | Literal | Notes |
|---|---|---|
| `List` | `(1, 2, 3)`, `()` | ordered, not sorted; the only unsorted collection; `(x,)` has one element |
| `Array` | `[1, 2, 3]`, `[]` | one dimension; type `[]Integer`, `[10]Integer` |
| `Matrix`, `Tensor` | `[[1, 2], [3, 4]]` | two dimensions; three or more; row-major; a tensor is an array of matrices |
| `DataSet` | `{1, 2, 3}`, `{}` | sorted by value, no duplicates |
| `DataMap` | `{"k": 1}`, `{:}` | sorted by key; keys are strings or numbers; may nest; type `{:}(String, Integer)` |
| `Object` | `{x: 1}` | unquoted keys; code outside the class can not add an attribute |
| `Range` | `(1..5)`, `(0..1)(0.1)` | a value, not an array; not a number |
| `Ordinal` | `{Red, Green, Blue}` | named values; the first is 1 unless a value is given |
| `Function` | | a function is an object of type `Function`; a signature is a class derived from it |

| variant | `{Real \| Integer}` | holds one of the listed types; takes the type of the value assigned |

- A collection is indexed from 1; the length is `.count()`.
- `:=` shares a collection or an object; `::` copies it deeply; a native value is always copied.
- A collection printed shows its type: `(1,2,3)` list, `[1,2,3]` array, `{1,2,3}` DataSet, `{"a":1}` DataMap, `{x:1}` object; strings and runes are quoted inside a collection; no spaces. A Real prints in the shortest form that reads back (`3.5`, `0.25`; a whole Real prints without a point).
- `Object` is the root class. `type(x)` gives the type of a value; `x is Type` tests it.

The types of the files that a program loads and parses (`JSON`, `CSV`, `TXT`, `XML`, `HTML`, `HTMT`) are described in [data-types.md](data-types.md) (proposal, level 3).

### DataMap methods

| Method | Result |
|---|---|
| `m.has(k)` | `Logic`: the key is in the map (same as `k in m`) |
| `m.get(k)` | the value of `k`, or `null` when the key is missing (`m[k]` raises `$err_key` instead) |
| `m.get(k, d)` | the value of `k`, or `d` when the key is missing |
| `m.keys()` | a `List` of the keys, in key order |
| `m.values()` | a `List` of the values, in key order |
| `m.delete(k)` | removes the entry; nothing happens when the key is missing |
| `m.count()` | the number of entries |



## Strings

- A string is immutable; indexing gives runes; `+` concatenates two strings; `*` replicates; `<+` and `+>` append and prepend, also a number converted to text.
- Interpolation: `{name}` inserts the value of a name, written by its type; a placeholder holds a name, a literal or a simple expression; an optional format follows `%`: `{n % i5}`; a literal brace is `\{` or `\}` (lexical.md; the format rules are a draft).
- `s =~ "/regex/flags"` matches a regular expression; level 1 requires a subset: literals, `.`, `^`, `$`, classes `[a-z]`, `\d \w \s`, `* + ?`, `|`. The pattern is a regex literal, a string that starts with `/` and keeps its backslashes (lexical.md); it is a `String`, and a concatenation that starts with `/` is a pattern too.

## Zero values and optional types

`new n:Integer;` is `0`; `new a, b:Integer;` gives `0` to both. `new age:Integer?;` may hold `null`; a plain `Integer` never does. Comparing a plain value with `null` is allowed and false.

| Type | Zero value |
|---|---|
| `Byte` `Short` `Integer` `Natural` `Huge` | `0` |
| `Real` `Float` | `0.0` |
| `Decimal` | `0d` |
| `Rune` | `nil` (`''`) |
| `Logic` | `False` |
| an ordinal | its first value |
| `Time` | `00:00:00` |
| `Duration` | `0s` (printed `PT0S`) |
| `String`, `Text` | `""` |
| `List`, `Array`, `DataSet`, `DataMap` | `()`, `[]`, `{}`, `{:}`; an array with a fixed size holds the zero value of its element type in every place |
| an object or a record | every attribute holds its zero value |

## Narrowing and the default

A value of an optional type `T?` may be `null`, and a plain `T` never is. The checker (before the run, exit 65) keeps the two apart:

| Rule | Example | Error |
|---|---|---|
| a `T?` name is not an operand of `+ - * / % ^` or an order (`< > <= >=`) until it is tested | `new n :Integer?; print n + 1;` | `n may be null` |
| a method called on a `T?` name needs a test first | `new s :String?; print s.length();` | `s may be null` |
| a plain type never takes `null` | `new n :Integer; let n := null;` | `n is not optional` |
| a `T?` name is not an argument of a plain `T` parameter until it is tested | `twice(n)` with `n :Integer?` | `n may be null` |
| a test against null narrows the name to its plain type in the block it guards | `if s <> null do print s.length(); done;` | none |
| a test in the condition of a `while` narrows the name in the loop body | `while n <> null do print twice(n); ... done;` | none |
| the right side of `and` sees the name as plain after `s <> null` | `if s <> null and s.length() > 2 do ... done;` | none |
| the branches after `if s == null` see the name as plain | `if s == null do ... else print s.length(); done;` | none |
| after `if s == null do exit; done;` the rest of the block sees the name as plain | | none |

The narrowing lasts only inside its block: after the block the name may be null again. Equality and inequality with `null` need no test (`n == null` is allowed on any value).

`x ?? d` is the default of an optional value: `x` when it is not `null`, else `d`. It binds looser than `or`, groups to the right (`null ?? 0 ?? 9` is `0`), and `d` is evaluated only when `x` is `null`. Its type is the plain type of `x`.

A `NULL` that the data layer reads into a plain member of a record (a column of a query, a JSON value) is the run-time error `$err_null` (16) for SQL and `$err_format` (56) for CSV and JSON files; an optional member takes it as `null`.

## Static checks

Before the run the checker refuses a value of one basic type given where another basic type is declared (exit 65, `syntax_error`). The basic types are `String` (and `Text`), `Logic`, the numbers, `Duration`, `Date`, `Time`, `DateTime`, `Instant`, `Bytes`, `Uuid` and `Zone`. The numbers convert to each other, so an `Integer` may be given to a `Real` parameter.

| Where | Example | Message |
|---|---|---|
| an assignment to a declared variable | `new n = 0 :Integer; let n := "text";` | `n is Integer, and the value is String` |
| an argument of a function or procedure | `twice("four")` for `x: Integer` | `argument 1 of twice is String, but the parameter is Integer` |
| a result (the `@result` of a function) | `let result := "text";` for `=> (@result: Integer)` | `result is Integer, and the value is String` |
| a declaration with a value | `new n = "text" :Integer;` | `n is Integer, and the value is String` |

A class, a list, an optional type (`T?`, see `#narrowing-and-the-default`) and a name without a known type are not checked by this rule.

