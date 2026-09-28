# Issues: types.html

Page: `tutorial/types.html` (1,323 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### TYP-01 Native types in scripts
The page says native types (`i8`…`i64`, `u8`…`u64`, `f32`, `f64`) are "not usually necessary in
Eve scripts", but examples declare `:i64`. May a script declare native variables, or only core
libraries? Is the list complete (no `i128`, no `f16`)?
**Answer:** _(open)_
Status: open

### TYP-02 Primitive type sizes
The primitive table conflicts with itself and the rest of the page:
- `Short`: range written `0x0000..0xFFFF`, but min `-2^15`. Signed 16-bit?
- `Duration`: "0..2^16" in the table; later "32 bits, internally milliseconds, almost 20 days",
  "(1..2^16) milliseconds" (65 seconds) and "an alias for Short integer i32".
- `Ordinal`: "named Short integers", range `0..2^16-1` (unsigned).
- `Real`: min written `-n`.

What are the size, signedness and unit of `Short`, `Ordinal` and `Duration`?
**Answer:** _(open)_
Status: open

### TYP-03 Which numeric types exist in 0.1
The categories table lists `Float`, `Rational`, `Complex` and `Range` as numbers, but the
primitive table has none of them. `Rational` is "q64" with "variable precision" and "fixed
precision arithmetic". Are `Float`, `Rational` and `Complex` part of 0.1? What is a `Rational`
(fraction of two integers, or fixed-point decimal)?
**Answer:** _(open)_
Status: open

### TYP-04 Literal → default type
The "Default Types" tables contradict the rest of the page:
- `0b1010101` → `Binary`, `U+0001` → `Word`, `U-FFFFFFFF` → `Binary`: `Binary` and `Word`
  are not defined anywhere; the Unicode section says `U+` literals are `Symbol`.
- `""` → `Text` and `''` → `String`, but elsewhere `"..."` is `String` and `'...'` is `Symbol`.
- `[1, 2, 3]` → `Vector[Byte]`, although `1` alone is `Integer`.
- `0x9ABCDEF` → `Natural`, but `9` → `Integer`.
- `1/2` is "Single number" in one table; the example assigns `1/2` to a `Real`.

Please confirm the type of each literal: decimal, negative, hex, binary, real, `1/2`, `U+…`,
`'a'`, `"a"`, `()`, `[]`, `{}`, `(1,2)`, `[1,2]`, `{1,2}`, `{a:1}`.
**Answer:** _(open)_
Status: open

### TYP-05 Unicode literal forms
`U+HHHH` (4 hex digits) and `U-HHHHHH` (6 digits, up to `U+FFFFFF`), but the literal table shows
`U-FFFFFFFF` (8 digits). Unicode ends at `U+10FFFF`. Keep two forms, or one form `U+` with 4 to 6
digits?
**Answer:** _(open)_
Status: open

### TYP-06 Empty symbol `''`
"Symbols have initial value NIL, equivalent to `''`". Is `''` a valid literal? Is `NIL` a
keyword, or the same thing as `Null`?
**Answer:** _(open)_
Status: open

### TYP-07 Declaration order: value and type
syntax.html writes `new a = 0 :Integer;` (value, then type). This page also writes
`new x :Integer = 5;` (type, then value) and `new time1, time2, time3: Time;`. Which order is
canonical? Is the other accepted? Is there a space before `:`?
**Answer:** _(open)_
Status: open

### TYP-08 `let` with a type
`let native_value :i64 = x.value();` declares a type in a `let`, although `let` alters an
existing variable. Error in the example, or can `let` declare?
**Answer:** _(open)_
Status: open

### TYP-09 Named processes
Examples write `process boxing_demo:`, `process main`, `process print_type:`. Can a process have
a name? Is that a different construct from the driver's `process`?
**Answer:** _(open)_
Status: open

### TYP-10 Range and domain brackets
Ranges are written `(0..5)`, but `class Small = [0..1:0.1] <: Range;` uses brackets, and
syntax.html distinguishes "Domain `[n..m]`" from "Range `(n..m)`". Is a domain a separate type?
What does `[..]` mean?
**Answer:** _(open)_
Status: open

### TYP-11 Decimal range precision
"The number of zeros establishes the precision": `0.001 in (0.00..1.00)` is true but
`0.001 in (0.0..1.0)` is false. Confirm this rule. With no ratio, is membership exact
(`0.05 in (0.0..1.0)` false)?
**Answer:** _(open)_
Status: open

### TYP-12 Subtype declaration syntax
Ranges, ordinals and variants are declared as `class R5 = (0..5) <: Range;`,
`class Logic = {False:0, True} <: Ordinal;`, `class Number = {Integer | Real | Null} <: Variant;`.
Is `class Name = literal <: Base;` the general form for these? A variant is also written inline:
`set v, x, t: {Real | Integer};`. Are both allowed?
**Answer:** _(open)_
Status: open

### TYP-13 Integer division
`1 / 2` gives a `Real` (0.5). Does `/` always return `Real`, even for `4 / 2`? Is there an
integer division operator?
**Answer:** _(open)_
Status: open

### TYP-14 `parse` losing precision
`let v := parse("200.02");` into an `Integer` "makes v = 200, decimal .02 is lost". Elsewhere
Real → Integer is an error and only safe coercion is done. Should this `parse` fail?
**Answer:** _(open)_
Status: open

### TYP-15 Template placeholders
This page formats with `?` and `#`: `"type of i is #s" ? i.type()`, `"Year: #" ? date1.year`.
syntax.html interpolates with braces: `"param1: {a}"`. Which placeholder syntax is Eve? What do
`#` and `#s` mean? (See SYN-12.)
**Answer:** _(open)_
Status: open

### TYP-16 Type checks: `type(x) is T`, `x.type()`, `x is T`
The page uses `type(x) is Integer`, `ls.type()` and `x is Null`. syntax.html says `is` checks
"data type | reference identity". Is `x is Integer` valid? Is `type()` both a function and a
method?
**Answer:** _(open)_
Status: open

### TYP-17 `call` for routines
`call swap(x, y);` calls a routine, but syntax.html defines `call` as "execute a shell command in
synchronous mode". Which is it, or both?
**Answer:** _(open)_
Status: open

### TYP-18 `Logic` versus `Byte` for True/False
`class Logic = {False:0, True} <: Ordinal;` and also `set False = 0b0 :Byte;`. Which is right?
Are `True` and `False` keywords or constants of `Logic`?
**Answer:** _(open)_
Status: open

### TYP-19 Date literals
The page gives three forms: functions `ymd()`, `dmy()`, `mdy()`; `"2023/06/15" as YMD`; and a
constants table with `YDM` = `YYYY/DD/MM`. It mentions an `era_label` (CE/AD) without syntax, and
`{year: 1066, month: 10, day: 14}` creates an object, not a `Date`. Which form is Eve 0.1?
**Answer:** _(open)_
Status: open

### TYP-20 Time and Duration
- `T12 = "hhhh:mm:ss,999ms"` and `T24 = "hhhh:mm:ssxx, 999ms"` look swapped and use `hhhh`.
- Examples use invalid values (`"00:23:63"`, minute 63) and expect `time1.h == 23` for
  `"00:23:63"`.
- Duration literals `{y, d, m, s, ms}`: is `m` minutes or months? A year does not fit in the
  stated range.

What are the Time format, the Duration range and unit, and the Duration literal suffixes?
**Answer:** _(open)_
Status: open

### TYP-21 `as` operator
`as` converts a string into a date/time (`"…" as T24`) and also formats values for printing
("quick format", `EUR`/`USA` number formats). Is it one operator in both directions?
**Answer:** _(open)_
Status: open

### TYP-22 Operator dispatch
"Operators are functions … dispatch uses the left operand first." Is this a language rule (the
spec states it) or an implementation note?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### TYP-F1 Native type table
"number of bytes: {8, 16, 32, 64}" should be bits. "Signed integers: {u8, u16, u32, u64}" should
be `{i8, i16, i32, i64}`. "Native types are implemented by operating system" → by the hardware.
**Answer:** _(open)_

### TYP-F2 Broken examples
- `//` comments in the date example → `**`.
- `let x = 10;` (variant example) → `let x := 10;`; `expect type(x) = type(y);` → `==`.
- Missing `;` after `let a := (10,11,12)`, `let a += "4"`, `expect type(r.age) is Integer`,
  `print type(t)`, `print ('0'..'5')`.
- `set True = Ob1` (letter O) → `0b1`.
- Hash-map example declares `:DataSet`, has key `'ley2'`, and reads `t.key` / `t.value`.
- Coercion notes end in ":" with nothing after ("Implicit conversion is possible and safe :").
- Prose: "You can use False and True with == or !=" and "Relation operators {…, !=}" → `<>`.
- "Date object contains four fields: year, month, day" → three.
- "Composite: String — Real quote delimited" → double quote.
- "Real is Real-precision 64-bit" → double-precision.
**Answer:** _(open)_

### TYP-F3 Typos
convetion, Maxim/Minim, ocupy, tey, automaticly, inititialized, easly, controled, Ratiobal,
"are are", impicit, equaly, Multi-dimensiona, "make sens", decimaL, loosing, heyword, fo,
gradial, subtipe, VNamme, tefine, variabt, nulable, milissecond, higer, "Eve can constants",
"can be ready using", rise (raise).
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### TYP-I1 One literal table
Replace the three "Default Types" tables with one table: literal, form, default type, example,
after TYP-04. The spec's `types.json` generates it.
**Answer:** _(open)_

### TYP-I2 Split the page
1,300 lines. Move Date, Time, Duration and Quick Format to a "Date and time" page (or to
library.html); keep types.html for the type system: native, primitive, composite, literals,
ranges, inference, variants.
**Answer:** _(open)_

### TYP-I3 Pitfalls
Real → Integer needs `floor`/`round`/`ceiling`; `/` returns Real; `is` does not compare values;
range precision comes from the number of zeros.
**Answer:** _(open)_

## Spec additions once answered

- `spec/semantics/types.md`, `types.json`: native and primitive types (TYP-01..03), variants,
  subtypes (TYP-12), inference, coercion (TYP-13, 14).
- `spec/lexical/lexical.md`: numeric, Unicode, symbol, string, date/time/duration literals
  (TYP-04..06, 19, 20).
