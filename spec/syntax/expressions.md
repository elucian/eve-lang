# Expressions

Status: **0.1-draft**, level 1. Grammar: [`grammar.md`](grammar.md). Operator table: [`../lexical/operators.json`](../lexical/operators.json). Types of the operands: [`../semantics/types.md`](../semantics/types.md).

An expression has a value and a type. Round parentheses group: `(x)` is the value of `x`, not a list; the list of one element is `(x,)` (D-063). The type of an expression is inferred.

## Precedence

Operators on a higher row bind tighter; operators on one row go from left to right, except `^` (D-019, D-079).

| Level | Operators |
|---|---|
| 1 | `.` `()` `[]` member, call, index |
| 2 | unary `-`, `not`: applied before `^`, so `-2 ^ 2` is `(-2) ^ 2 = 4` (Q-030) |
| 3 | `^` (right to left) |
| 4 | `*` `/` `%` |
| 5 | `+` `-` |
| 6 | `..` `..<` `>..` `>..<` `+-` `><` |
| 7 | `<<` `>>` |
| 8 | `&&` |
| 9 | `\|\|` |
| 10 | `==` `<>` `<` `>` `<=` `>=` `=~` `is` `in` `eq` (and the forms with `not`) |
| 11 | `and` |
| 12 | `xor` |
| 13 | `or` |
| 14 | `a if c else b` |

A `-` with no operand on its left is the unary minus and binds tighter than `^`; a `-` with an operand on its left is the subtraction: `4 - 2 ^ 2` is `0` and `4 - -2 ^ 2` is `4 - (-2) ^ 2`, also `0`. The negative of a power is written `-(2 ^ 2)` (Q-030, author decision: Eve differs here from most languages).

The relations do not chain: `a < b < c` is a compile error; write `a < b and b < c`, or `b in (a>..<c)`. `and` and `or` evaluate the right operand only when needed.

## Arithmetic

- `+ - * % ^` on two Integers give an Integer; with a Real the result is Real. `/` always gives a Real (`9 / 3` is `3.0`); `new x = a / b :Integer;` converts it (D-032, D-080). Integer overflow is an error.
- `%` is the remainder, with the sign of the left operand. `^` is the power; `**` is a comment.
- Division or remainder by zero is an error with code 4, also for `Real` and `Float`: there is no infinity and no NaN (Q-019a). A `Rational` with a zero denominator, `1\0`, is not supported.
- `+` on two strings concatenates. `+` between a string and a number is a compile-time type error; `s <+ 1` appends the number as text (D-080).
- `*` between a string and an Integer replicates the string: `"ab" * 3` is `"ababab"`.

## Comparison and logic

- `==` and `<>` compare values; on objects and collections the comparison is deep. Numbers of different numeric types are compared by value (`9 / 3 == 3` is true); any other operands of different types are never equal. `<` `>` `<=` `>=` compare numbers, runes and strings (by code point).
- `is` compares references: `a is b` is true when both name the same object; on native values it is false. `x is Type` tests a type. `x is Null` tests the type, `x == null` the value (D-080). `eq` is true when value and type are the same.
- `and`, `or`, `xor`, `not` take Logic values; `not`, `is not`, `not in`, `not eq` are negations. `True` and `False` are the constants of type Logic, with the values 1 and 0.
- `a if c else b` evaluates `c` first, then only the chosen branch; it chains: `a if c1 else b if c2 else d`. It needs parentheses when it is an argument or an initial value.
- `=~` is the approximate match: `s =~ "/regex/flags"` for a string (the right operand is a pattern when its value starts with `/`; a literal that starts with `/` is raw, Q-018), `x =~ b +- t` for a number within the tolerance `t`, `x =~ b` within `$epsilon` (D-079). `==` is the exact one. There is no `!~` and no `~`.

## Ranges

| Form | Interval |
|---|---|
| `a..b` | [a, b] |
| `a..<b` | [a, b) |
| `a>..b` | (a, b] |
| `a>..<b` | (a, b) |
| `b +- t` | [b - t, b + t] |
| `(a..b)(s)` | the range with a step `s`; the number of decimals of the step sets the precision |
| `(0..?)` `(?..0)` | an open end |

A range is a value, not an array; there is no `[1..10]` (D-022, D-023). It is used in `for`, `in`, `when`, a builder and as an index. `a >< b` is the cartesian product of two collections or ranges: pairs in row-major order, the left operand is the outer loop (D-024).

## Index, slice, member

- Collections are indexed **from 1** (D-021). `a[-1]` is the last element and `a[-x]` is `a[N + 1 - x]`; `a[0]` and an index outside `-N..N` are errors with code 4 (D-079).
- A slice is a range as index: `a[2..4]`, `a[1..-1]` (all), `a[2..-2]`. By `:=` it is a view, by `::` a copy (D-049). A string is indexed by runes.
- A matrix or tensor takes one index per dimension, in one pair of brackets or one pair each: `m[x, y]` is `m[x][y]`; an index is a number, a range or `*` (all of the dimension). A single index `m[k]` is the absolute row-major index (D-064).
- On a DataMap `h["k"]` reads a key; a missing key is an error with code 4. Assigning to a missing key creates it (D-058).
- `object.name` reads an attribute; `Class.name` a class member; `module.name` an exported member. Code outside a class can not add an attribute to an object: `new p.z := 7;` is a compile error (Q-019h, Q-031k).
- A call applies to a name or to a lambda in parentheses: `((x) => (x * 2))(5)` creates an anonymous function and calls it. An anonymous function can not call itself (Q-025a). A function has one parameter list (D-029); its optional parameters are named at the call.

## Literals and builders

- Number, rune, string and text literals: `../lexical/lexical.md`.
- `(1, 2, 3)` List; `[1, 2, 3]` Array; `{1, 2, 3}` DataSet (sorted, no duplicates); `{"a": 1}` DataMap (quoted or numeric keys); `{a: 1}` Object (names as keys); `()` empty List; `[]` empty Array; `{}` empty DataSet; `{:}` empty DataMap (D-058, D-080).
- A builder takes values from generators and an optional condition joined by `and`: `[x * x | x in (1..10) and x % 2 == 0]`, `[(x, y) | (x, y) in (1..3) >< (1..3)]`. The brackets decide the collection (D-023, D-059).
- A **deconstruct** assigns the elements of a collection to several names: `new (a, b, *rest) := lst;`; `_` drops one element and `*` skips many (D-058).

## Operators on collections

| Operator | List / Array | DataSet | DataMap |
|---|---|---|---|
| `+` or `<+` | concatenate / append | union | merge |
| `+=` `-=` | add at the end / remove by value (every equal element) | add / remove | add pair / remove key |
| `<+` `+>` | append at the end / put in front (`x +> lst`) | | |
| `<-` `->` | remove the first / last element | | |
| `.delete(v)` | remove every element equal to `v` | remove `v` | remove the key `v` |
| `in` | membership | membership | key membership |
| `\|\|` `&&` `-` | | union, intersection, difference | |
| `.count()` | number of elements | | |

As a statement, `let a <+ b;` appends `b` to `a`; `new a <+ b;` creates a new list `a` that holds `b`, and is an error when `a` exists (Q-019d). As an expression, `a <+ b` returns a new collection *(proposed)*. An arrow never removes by value: `lst.delete(v)` does (Q-031c). The list of methods is in `../library/builtins.md` (pending).
