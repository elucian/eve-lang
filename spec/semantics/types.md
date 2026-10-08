# Types

Status: **0.1-draft**, level 1. Sources: D-021 to D-024, D-032, D-049, D-058 to D-060, D-079, D-080. The Date, Time and Duration types are not part of level 1 (D-108).

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
| `Rune` | one Unicode code point (32 bits, up to U+10FFFF) | `'a'`, `U+0061` | `''` (`nil`) |
| `String` | immutable UTF-8 text | `"text"` | `""` |
| `Text` | mutable text | `"""…"""`, `<text>…</text>` | `""""""` |
| `Null` | the type of `null` | `null` | |

- A decimal literal without a point is an Integer (never negative: `-5` is the operator `-` on `5`); with a point a Real. A suffix (`b w n z r f d`) gives another type; hexadecimal literals take no suffix (D-080). Native types `u8 … u64`, `i8 … i64`, `f32`, `f64` are reserved for core libraries.
- A real literal may have an exponent (`1.5e3`, `2e-3`): it is always a Real. `"1,000,000"z` is a number: a string followed by a type suffix. `Rational` (`3\4`) and `Complex` are not in version 1 (D-080, D-032).
- `nil` is the empty rune `''`, a value of `Rune`. `Null` is a type and `null` its only value; no object exists, nothing is allocated. `0`, `""`, `''`, `()`, `[]`, `{}` are values, not null. A variable without a value gets the zero value of its type, never `null`. A variable that may be null has an optional type, `T?`.
- Names are case sensitive: `Null` and `null` are different names.

## Conversions

- There is no implicit conversion between numeric types except widening in arithmetic: Integer with Real gives Real. `/` always gives a Real.
- `new x = a / b :Integer;` and `Integer.parse("3.7")` convert as the developer asked: the decimals are dropped, there is no run-time error; a debug mode warns "possible data loss" with the line (D-080).
- `parse` coerces to the type of the target. `s <+ 1` appends a number as text. `as` formats a value (version 2).

## Composite types

| Type | Literal | Notes |
|---|---|---|
| `List` | `(1, 2, 3)`, `()` | ordered, not sorted; the only unsorted collection; `(x,)` has one element |
| `Array` | `[1, 2, 3]`, `[]` | one dimension; type `[]Integer`, `[10]Integer` |
| `Matrix`, `Tensor` | `[[1, 2], [3, 4]]` | two dimensions; three or more; row-major; a tensor is an array of matrices |
| `DataSet` | `{1, 2, 3}`, `{}` | sorted by value, no duplicates |
| `DataMap` | `{"k": 1}`, `{:}` | sorted by key; keys are strings or numbers; may nest; type `{:}(String, Integer)` |
| `Object` | `{x: 1}` | unquoted keys; code outside the class can not add an attribute (Q-031k) |
| `Range` | `(1..5)`, `(0..1)(0.1)` | a value, not an array; not a number |
| `Ordinal` | `{Red, Green, Blue}` | named values; the first is 1 unless a value is given (Q-029) |
| `Function` | | a function is an object of type `Function`; a signature is a class derived from it |

| variant | `{Real \| Integer}` | holds one of the listed types; takes the type of the value assigned |

- A collection is indexed from 1; the length is `.count()`.
- `:=` shares a collection or an object; `::` copies it deeply; a native value is always copied (D-049).
- A collection printed shows its type: `(1,2,3)` list, `[1,2,3]` array, `{1,2,3}` DataSet, `{"a":1}` DataMap, `{x:1}` object; strings and runes are quoted inside a collection; no spaces (D-063, Q-019b). A Real prints in the shortest form that reads back (`3.5`, `0.25`; a whole Real prints without a point).
- `Object` is the root class. `type(x)` gives the type of a value; `x is Type` tests it.

## Strings

- A string is immutable; indexing gives runes; `+` concatenates two strings; `*` replicates; `<+` and `+>` append and prepend, also a number converted to text.
- Interpolation: `{name}` inserts the value of a name, written by its type; a placeholder holds a name, never an expression; an optional format follows `%`: `{n % i5}`; a literal brace is `\{` or `\}` (lexical.md, D-102; the format rules are a draft, D-060).
- `s =~ "/regex/flags"` matches a regular expression; level 1 requires a subset: literals, `.`, `^`, `$`, classes `[a-z]`, `\d \w \s`, `* + ?`, `|`. The pattern is a regex literal, a string that starts with `/` and keeps its backslashes (Q-018, lexical.md); it is a `String`, and a concatenation that starts with `/` is a pattern too.

## Zero values and optional types

`new n :Integer;` is `0`; `new a, b :Integer;` gives `0` to both (Q-031a). `new age :Integer?;` may hold `null`; a plain `Integer` never does. Comparing a plain value with `null` is allowed and false.

| Type | Zero value |
|---|---|
| `Byte` `Short` `Integer` `Natural` `Huge` | `0` |
| `Real` `Float` | `0.0` |
| `Decimal` | `0d` |
| `Rune` | `nil` (`''`) |
| `Logic` | `False` |
| an ordinal | its first value (Q-033f) |
| `Time`, `Duration` | 0 milliseconds |
| `String`, `Text` | `""` |
| `List`, `Array`, `DataSet`, `DataMap` | `()`, `[]`, `{}`, `{:}`; an array with a fixed size holds the zero value of its element type in every place |
| an object or a record | every attribute holds its zero value |
