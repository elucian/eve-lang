# String functions

Status: **draft**, level 6 (D-189), found missing by the standard library (`backlog/library-gaps.md` G-7). Written in the VM, in Zig (hot and simple). Tests: `test/level1/a86_string_slice`, `a87_string_functions`. The tutorial (`strings.html`) lists `split`, `length`, `find`, `count` and `replace` as wanted and leaves the inventory to the library specification; this page is that inventory for level 6. The regular-expression forms wait for the module `regex` (planned) and Q-066.

A `String` is a sequence of runes, indexed from 1 (`semantics/types.md`). A function is called on a value, `s.trim()`, and gives a new string; a string is never changed in place.

## Slice

`s[a..b]` is the substring from rune `a` to rune `b`, both included; `s[2..-1]` runs to the end, as for a list (`syntax/expressions.md#index-slice-member`). A slice of a string is a **copy** (a string is immutable). `s[a..a-1]` is the empty string; a bound outside `1..length` is `$err_index`.

## Functions

| Function | Result | Meaning |
|---|---|---|
| `trim()` | `String` | without the white space (space, tab, CR, LF) at both ends |
| `trim_start()`, `trim_end()` | `String` | the same at one end |
| `upper()`, `lower()` | `String` | the ASCII letters in upper or lower case; other runes are kept *(proposed: full Unicode case mapping later)* |
| `starts_with(t)`, `ends_with(t)` | `Logic` | does the string begin or end with `t` |
| `contains(t)` | `Logic` | does `t` occur in the string |
| `find(t)` | `Integer` | the index (from 1, in runes) of the first occurrence of `t`, or `0` when there is none *(proposed)* |
| `replace(old, new)` | `String` | every non-overlapping occurrence of `old` replaced by `new`, from the left; `old` must not be empty |
| `split(sep)` | `List` | already specified: the pieces between the separators |
| `length()` | `Integer` | the number of runes |

`t`, `old` and `new` are plain text, compared rune by rune (no case folding): `"a.b".replace(".", "-")` is `"a-b"`. A value that is not a `String` is `$err_argument`. The empty string is found at index 1 by `find("")`, is contained in every string, and begins and ends every string.

## Regular expressions

The operator `=~` is the match test. The functions above do not read their argument as a pattern, even when it begins with `/`; the search and replacement by pattern are `regex.find`, `regex.replace` and `regex.count` of the module `regex` (S11, planned), so that a path such as `"/data"` is plain text in `starts_with`. This differs from the sentence of the tutorial that gives `find(pattern: Regex)`; the choice is Q-066.
