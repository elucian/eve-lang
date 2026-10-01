# Issues: collections.html

Page: `tutorial/collections.html` (1,577 lines). Reviewed 2026-09-28. How to answer:
[README](README.md).

## Questions

### COL-01 Ordinal values and qualifiers
"Values start with 1 or a specific number", yet `{name1:0, name2, name3}` is commented `a=2, b=3,
c=4`. Without an explicit start, is the first value 0 or 1? "When an element name starts with a
capital letter, no qualifier is needed": is that a language rule (capitalized ordinal names enter
the enclosing scope)?
**Answer:** _(open)_
Status: open

### COL-02 Collection type notation
`()Type` list, `[10]Type` / `[n,m]Type` / `[?]Type` array, `{}Type` set, and map as `{}(String,
Object)` here but `{}(Type:Type)` on classes.html. Which map notation? Is `List(v1, v2)` (the
constructor) also valid?
**Answer:** _(open)_
Status: open

### COL-03 Builders
`(expr | x in range)`, `[f(x) | x in (…)]`, `{expr | x in A and y in B}`. Is `and` the way to
combine generators? Is there a filter (`| x in A if x > 2`)?
**Answer:** _(open)_
Status: open

### COL-04 Deconstruct: `_`, `*`, `*rest`
`let x, y, _, *rest, _ :: a;` and `let x, y, *, z := a;`. `_` "consumes one element and is always
Null" and then `expect _ == Null`. Is `*` alone (skip many) different from `*rest` (collect)? Can
`_` be read at all?
**Answer:** _(open)_
Status: open

### COL-05 List operations: one canonical set
The page mixes, often contradicting its own `expect` lines:
- `<+` and `+>` as concatenation (`a <+ b`), as append/insert (`add lst <+ 'z'`), and for
  string building (`"" <+ list`);
- `+=` / `-=` "append or remove elements from the beginning";
- statements `add lst <+ 'z'`, `add queue +> "x"`, `del 'b' in lst`, `pop queue -> e`;
- `<-`, `->` "to remove one single element";
- the comment "create element at the beginning" with `expect … 'z'` at the end.

Please give the list operations of 0.1: add at the start, add at the end, remove from the start,
remove from the end, remove all equal values, concatenate. One syntax each.
**Answer:** _(open)_
Status: open

### COL-07 Array, Vector, Matrix
types.html: `[1,2,3]` is a `Vector`, `[[1,2],[2,4]]` a `Matrix`. This page: everything is an
`Array` (`class AType = []Integer <: Array`), and a matrix is an array with 2+ dimensions. Which
type names exist?
**Answer:** _(open)_
Status: open

### COL-08 Slice notation
This page slices with `[n:m]` (`base[11:14]`, `base[x: x+3]`); syntax.html says slices use
`[n..m]`. Which one? Confirm: `:=` from a slice gives a view that shares elements, `::` a copy.
**Answer:** Slices use `[n..m]`, with `$` for the end (`base[6..$]`). `[n:m]` is dropped. See D-022. View versus copy (`:=` / `::`) is still to confirm.
Status: answered (D-021, D-022, D-049: `:=` gives a view, `::` a new collection)

### COL-09 Bulk assignment with `[*]`
`zum[*] := 0;` and `base[1:5][*] := 0;`. Is `[*]` required, or does `base[1:5] := 0`
also assign all?
**Answer:** _(open)_
Status: open

### COL-10 DataSet: union and intersection operators
"Union" uses `||` (`first || {2, 4}`); "Intersection" uses `&&`; then "You can use && and &= that
will perform union" and "Operator && is overloaded … (union)" with `{} && list`. syntax.html:
`&&` intersection, `||` union, `&=` adds elements. Which operator is union, which is
intersection, and what does `&=` do?
**Answer:** _(open)_
Status: open

### COL-11 DataSet ordering
"Elements are sorted by a hash function", "sets are automatically sorted by a hash key", and "we
keep elements sorted". Is a DataSet ordered (sorted by value), or unordered? Does `print` show a
predictable order?
**Answer:** _(open)_
Status: open

### COL-12 HashMap element creation
`h('c') := 3;` (parentheses) and `animals["Toto"] := "parot"` (brackets) create elements;
`animals["birds"] += 3` alters one. Does an assignment to a missing key create it, and does `+=` on a
missing key raise an error? Brackets only?
**Answer:** _(open)_
Status: open

### COL-13 HashMap is sorted
"Collections are ordered by unique keys … binary search", keys must be "sortable". A sorted map is
not a hash map. Keep the name `HashMap`, or rename (for example `Map`)? The text also says the name
comes from "similarity with letter H", which is not the origin of the term.
**Answer:** _(open)_
Status: open

### COL-14 Object literal versus HashMap literal
`{x: 1.5, y: 2}` is an Object and `{'a': 1, 'b': 2}` a HashMap. Is the rule: unquoted identifier
keys → Object, quoted or numeric keys → HashMap? What is `{}` alone?
**Answer:** _(open)_
Status: open

### COL-15 String escapes and `Text`
Double-quoted strings replace HTML-like `&code;` escapes; triple-quoted `"""…"""` literals strip
the indentation of the closing quotes; "A Text has a different internal representation". Are
`&code;` escapes the Eve escape mechanism (instead of `\n`)? Is `Text` a separate type from
`String`? (See D-019.)
**Answer:** _(open)_
Status: open

### COL-16 Placeholders again
This page uses `"#{str}"` interpolation and `"#n"`, `"#s"` with `?`; syntax.html uses `"{a}"`;
matrix printing uses Fortran-like `"#(3i4)"`. One answer (D-019, D-032) covers this: which
forms are Eve?
**Answer:** _(open)_
Status: open

### COL-17 Symbol and number concatenation
`'a' + 1` gives `"a1"` and `1 + 'a'` gives `"1a"` (implicit number → string), while types.html says
only safe coercion is implicit. Keep this rule? Does `"a" + 1` work too?
**Answer:** _(open)_
Status: open

### COL-18 Regex operators and `!`
Regex match uses `~` and not-match `!~`. D-013 makes `!` the unsafe-operation sigil and `<>` the
not-equal operator. What is the "not like" operator now (`not (s ~ r)`, `<~`, other)? Regex
literals are strings `"/…/g"`: is a string starting with `/` always a regex on the right of `~`?
**Answer:** _(open)_
Status: open

### COL-19 Strings immutable
"Strings are immutable", but the example is titled "shared mutable strings" and `str += ':'`
creates a new string. Confirm: strings are immutable values; the assignment rebinds.
**Answer:** _(open)_
Status: open

### COL-20 Method call on a type
"`"test".split()` is equivalent to `String.split("test")`". Is this a general rule: every method can
be called on the class with the object as first argument?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### COL-F1 "Real quotes"
"Real quotes", "Real quoted strings", "Real quote delimited" (here, types.html, syntax.html): a
past replace of "Double" → "Real" hit the word "double quote". → "double quotes" on every page.
**Answer:** _(open)_

### COL-F2 Wrong examples
- Ordinal comments `a=2, b=3, c=4` for values starting at 0.
- `let d := b +> b;` then `expect c == …` (should be `d`, `b +> a`?); `expect a == …` in list_alter.
- `add queue +> ('z','y')` and `expect queue == ('z', 'y', 'x')` missing `;`;
  `set queue := ()Symbol` assigns a type.
- `function list_join:` without parameters or result; `process list_split` fills `lst` but
  declares `list`, and compares strings to `(1,2,3)`.
- `zum`/`zoom`, `zum[0]` with 1-based indexes, `expect zoom = […]` uses `=`.
- `[2^8]Symbol` "Array of 255 Symbols" (256); `array_name4` declared twice.
- Row-major loop `while (i < x)` skips the last element; `matrix.extend` vs `matrx`;
  `matrx(i,j)=i*10+j` has no `let`, uses `()` and `=`.
- `let point = {x:1.5, x:1.5}` repeats `x`; `btr == ''` → `:=`; `let str1 = "test":` ends in `:`.
- `print ("----------")`, `test -= {1,3}`, `expect str1 == "0123456789"` missing `;`.
- `expect test == {1,2,2,4,5}` shows a duplicate in a set.
- String builders text says operators `>+` and `+<`; the code uses `+>` and `<+`.
- Prose "{ ==, !=, <, … }" → `<>`.
- Broken HTML: "middle of the list./p>".
- Image `/images/row-major.svg` does not exist (file is in `/assets/images/`).
**Answer:** _(open)_

### COL-F3 Typos
brackedts, forsee, "bu maybe", Forst, "form 0", traves, "Dure to better cash management", rever,
missconception, "Extraact severa lelements", connecte, optput, parot, recommand, necesary, Trics,
Sytrings, tripple, semicolumn, asign, usinc, pruduct, ration, "Te example", "loose references".
**Answer:** _(open)_

### COL-F4 Authoring standard
"Eve is a cool language. True?" (example string), "you should never use this process" (full
scan), "Regular expressions are powerful but difficult to master".
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### COL-I1 Split the page
Strings and regular expressions (~350 lines) to their own page; collections keep Ordinal, List,
Array/Matrix, DataSet, HashMap, Object.
**Answer:** _(open)_

### COL-I2 Operations table per collection
For each collection: literal, type notation, create, add, remove, access, iterate, operators.
Generated from the spec once COL-05, 10, 12 are answered.
**Answer:** _(open)_

## Spec additions once answered

- `spec/semantics/types.md` / `types.json`: collection types and notation (COL-02, 07, 13, 14).
- `spec/syntax/expressions.md`: builders, deconstruct, slices, indexing (COL-03, 04, 06, 08, 09).
- `spec/lexical/operators.json`: collection and set operators (COL-05, 10, 18).
- `spec/lexical/lexical.md`: string escapes, text literals (COL-15).
