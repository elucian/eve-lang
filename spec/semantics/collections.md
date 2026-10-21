# Collections and objects

Status: **draft**, level 1. The collection types, their literals and the rules every program meets. The list of types is in [types.md](types.md#composite-types); the operators are in [expressions.md](../syntax/expressions.md#operators-on-collections).

## Indexes

- The first index is 1. A negative index counts from the end: `a[-1]` is the last element. Index 0 is a run-time error, `$err_index` 10.
- A range is an index too and selects a part (a slice): `v[2..3]`, `v[3..-1]`. A text takes a range as well: `s[2..4]`.
- A slice assigned with `:=` is a view of the array, with `::` a copy ([share and copy](#share-and-copy)).
- `.count()` gives the number of elements.

## List

`(1, 2, 3)`, `()`. Ordered, not sorted, the only unsorted collection. `(5,)` is a list of one element; `(5)` is the number 5 in parentheses; a trailing comma is allowed. `let a <+ x` appends, `let a +> x` puts in front; `<+` between two lists makes a new list. `a.delete(x)` removes every element equal to `x`. `let m -> last`, `let first <- m` and `new head <- q` take the last or the first element out of the list into a name (a capture), and `let _ <- m` drops it.

## Array

`[1, 2, 3]`, `[]`, one dimension; the type is written `[]Integer` or `[10]Integer` (`new z :[5]Integer` is five zeros). An element is assigned with `let v[2] := 25`; a slice is assigned in bulk with one value: `let z[2..3] := 1`.

## Matrix

`[[1, 2, 3], [4, 5, 6]]`, two dimensions; three or more make a tensor. `m[2, 3]` and `m[2][3]` are the same element. One index counts all the elements row by row (`m[5]`). `[*]` selects a whole dimension: `g[1, *]` is the first row. A range selects a part.

## DataSet

`{3, 1, 2}`, `{}`. Sorted by value, no duplicates. `in` and `not in` test membership; `||` is the union, `&&` the intersection, `-` the difference; `+=` and `-=` add and remove values. A list gives a DataSet: `{} || (1, 2, 1)` is `{1, 2}`. It prints in order: `{1,2,3}`.

## DataMap

`{"a": 1, "b": 2}`, `{1: "one"}`, `{:}` for the empty map; the type is `{:}(String, Integer)`. Sorted by key; keys are strings or numbers. An assignment to a missing key creates it (`let h["c"] := 3`), but `let h["z"] += 1` on a missing key is an error, `$err_key` 11. `"a" in h` tests a key, and `for (k: v) in h do` visits the keys in order. Methods: `has`, `get`, `keys`, `values`, `delete` ([types.md](types.md#datamap-methods)).

## Object

`{x: 1.5, y: 2}`: unquoted keys make an **object**, quoted or numeric keys make a DataMap. `p.x` reads and `let p.x := 3` changes an attribute. `==` compares all the attributes, `is` compares the object itself (`p == q` and `p is not q`). Code outside the class can not add an attribute.

## Builders

A collection can be built from a range or from another collection with an optional condition: `(x ^ 2 | x in (1, 2, 3, 4))`, `[x | x in (1..10)(3)]`, `{x * x | x in (2..6)}`, `(x | x in (1..10) and x % 2 == 0)`. A matrix builder uses two generators: `[x * y | (x, y) in (1..3) >< (1..3)]`.

## Deconstruct

`new p, r, _, *rest, _ :: n;` takes the elements of a list or an array into names: `_` skips one element, `*rest` collects the others, `*` alone skips many. The source does not change.

## Share and copy

`:=` shares a collection or an object: two names, one value (`b is a`). `::` makes a deep copy (`c is not a`). A native value (a number, a Logic, a String) is always copied. An operator with a scalar applies to every element: `a -= 1` on a list is arithmetic on each one.
