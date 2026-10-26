# Data tools

Status: **draft**, level 3. Library step L8. Written in Eve (`lib/data/`). Feature: F-LIB-03.

Tools for rows of data that a program holds in lists: records of a class, maps, or plain values. A key or a value is chosen by a function, usually a lambda: `(s) => (s.city)`. A wrong argument is `$err_argument` (17).

## Rules of import

`from lib use (data);` gives the functions of the four modules `rows`, `quality`, `infer` and `stream` as members of `data` and the modules themselves (`data.rows`, `data.stream` ...); a module can be imported alone, `from lib/data use (rows);`.

## Module rows

A key is a `String` or a whole number. A map keeps its keys sorted, so the groups come out in the order of their keys.

| Function | Result | Meaning |
|---|---|---|
| `group_by(items, key)` | `DataMap` | a map from each key to the list of its rows, in the order of the rows |
| `count_by(items, key)` | `DataMap` | the number of rows for each key |
| `sum_by(items, key, value)` | `DataMap` | the sum of the value for each key; the sum keeps the type of the values (a `Decimal` stays exact) |
| `join(left, right, left_key, right_key, combine)` | list | the inner join: `combine(l, r)` makes the row for each left row and each right row with the same key, in the order of the left rows, then of the right rows |
| `left_join(left, right, left_key, right_key, combine)` | list | the same, and a left row without a match is combined with `null` |
| `pivot(items, row_key, column_key, value)` | `DataMap` | a map from each row key to a map from each column key to the sum of the values |
| `dedupe(items, key)` | list | the rows without repeated keys: the first row of each key stays, the order is kept |
| `top(items, n, key)` | list | the `n` rows with the largest key, the largest first |
| `window(values, size, f)` | list | `f` applied to each run of `size` consecutive values; `count - size + 1` results |
| `fill_null(values, default)` | list | every `null` replaced by the default |
| `forward_fill(values)` | list | every `null` replaced by the last value before it; the nulls at the start stay |

## Module quality

| Function | Result | Meaning |
|---|---|---|
| `nulls(values)` | `Integer` | the number of nulls |
| `completeness(values)` | `Real` | the share of values that are not null, from 0 to 1; an empty list is 1 |
| `profile(values)` | `DataMap` | `count`, `nulls`, `distinct` (the different values that are not null), `kind` (the type name of the values that are not null, `"mixed"` for several, `"empty"` for none), and `min` and `max` for numbers or texts of one kind (`null` otherwise) |
| `duplicates(values)` | list | the values that appear more than once, each once, sorted (the values are of one kind) |
| `outliers(values, k)` | list | the numbers more than `k` interquartile ranges (1.5 by default) below the first quartile or above the third, in their order; nulls are ignored |

## Module infer

| Function | Result | Meaning |
|---|---|---|
| `split_line(line, separator)` | list | the cells of one line of CSV text; the separator (`,` by default) splits, a cell in double quotes may hold the separator, and a doubled quote means one quote |
| `parse(text, separator)` | list | the rows of a CSV text as lists of cells; empty lines are dropped |
| `type_of(cell)` | `String` | `"Integer"`, `"Real"`, `"Logic"` (`True`, `False`, `true`, `false`), `"Date"` (`2026-10-26`), `"String"`, or `"null"` for an empty cell |
| `columns(table)` | list of `Column` | the columns of a table given as rows of cells, the first row being the names; a `Column` has `name`, `type`, `nullable` and `distinct`. Integer cells with Real cells make `Real`; any other mix makes `String`; a column with no cells that are not empty is `String` |

## Module stream

A combinator is a generator: it reads its source and gives its values one at a time, only when a loop or `next()` asks for one, so a pipeline never holds the whole data and an infinite source is read only as far as it is needed. A source is a list or a generator.

| Function | Result | Meaning |
|---|---|---|
| `map(source, f)`, `filter(source, f)` | generator | `f(x)` for each value, and the values for which `f(x)` is `True` |
| `take(source, n)`, `drop(source, n)` | generator | the first `n` values (the source is not read beyond them), and the values after the first `n` |
| `chain(first, second)` | generator | the values of the first source, then of the second |
| `numbered(source)` | generator | each value with its number from 1, as a pair `(number, value)` |
| `sliding(source, size)` | generator | the lists of `size` consecutive values |
| `merge(first, second, f)` | generator | the merge of two sources sorted by the key `f(x)`; for equal keys the first source comes first |
| `collect(source)` | list | the values of a source as a list |
