# List functions

Status: **draft**, level 1. Library step L1. Written in the VM, in Zig. Feature: F-LIB-03.

The functions of a `List` `( )`, an `Array` `[ ]` and, where it makes sense, a `DataSet` `{ }`. A function is called on a value, `xs.sort()`. **A function never changes the list it is called on:** it gives a new value, and `let xs := xs.sort();` replaces the old one. The changes in place are the statements of the language (`let xs <+ x`, `xs.delete(x)`, [collections.md](../semantics/collections.md#list)). The function of an `Array` gives an `Array`, of a `List` a `List`, of a `DataSet` a `List`.

An argument that is a function (`map`, `filter`, `reduce`, `any`, `all`, `by:`) is a named function or a lambda. A wrong argument, an element that does not fit, or a function that is not given is the error `$err_argument` (17).

## Functions

| Function | Result | Meaning |
|---|---|---|
| `sort()` | list | the elements in ascending order; the sort is stable (equal elements keep their order) |
| `sort(by: f)` | list | ordered by the key `f(x)` of each element |
| `sort(descending: True)` | list | in descending order; `by:` and `descending:` can be given together |
| `reverse()` | list | the elements in the opposite order |
| `sum()` | number | the sum; `0` for an empty list; an `Integer` sum that does not fit is `$err_overflow`; `Integer` and `Decimal` give a `Decimal`, a `Real` makes the sum a `Real`, a `Rational` makes it a `Rational` (exact; an overflow is `$err_overflow`) |
| `min()`, `max()` | element | the smallest or the largest; an empty list is an error |
| `contains(x)` | `Logic` | is an element equal to `x` (the test of `==`) |
| `index_of(x)` | `Integer` | the index of the first element equal to `x`, counted from 1; `0` when there is none |
| `unique()` | list | the elements without the repeated ones; the first of equal elements stays, the order is kept |
| `take(n)`, `drop(n)` | list | the first `n` elements, or all but the first `n`; `n` is a whole number, zero or more, and may be more than the length |
| `zip(other)` | list | a list of two-element lists, the elements at the same index of both lists; as long as the shorter one |
| `map(f)` | list | `f(x)` for each element |
| `filter(f)` | list | the elements for which `f(x)` is `True` |
| `reduce(start, f)` | value | `f(a, x)` for each element, from `start`; `start` for an empty list |
| `any(f)`, `all(f)` | `Logic` | is `f(x)` true for one element, or for all of them; `any` of an empty list is `False`, `all` is `True` |

The elements of `sort`, `min`, `max` and the keys of `sort(by:)` are compared with `compare`: numbers with numbers, texts with texts (by the code of the runes), symbols with symbols, instants with instants. Comparing other kinds is an error. `unique` and `contains` use `==`, which compares collections and objects by their content.

```eve
new xs := (3, 1, 2);
print xs.sort();                       ** (1,2,3)
print xs.sort(descending: True);       ** (3,2,1)
print ("bb", "a", "ccc").sort(by: (s) => (s.length()));   ** (a,bb,ccc)
print xs.map((x) => (x * 2)).sum();      ** 12
```
