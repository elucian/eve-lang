# String functions

Status: **draft**, level 6, found missing by the standard library. Written in the VM, in Zig (hot and simple). The tutorial (`strings.html`) lists `split`, `length`, `find`, `count` and `replace` as wanted and leaves the inventory to the library specification; this page is that inventory for level 6. The regular-expression forms wait for the module `regex` (planned) and.

A `String` is a sequence of runes, indexed from 1 (`semantics/types.md`). A function is called on a value, `s.trim()`, and gives a new string; a string is never changed in place.

## Slice

`s[a..b]` is the substring from rune `a` to rune `b`, both included; `s[2..-1]` runs to the end, as for a list (`syntax/expressions.md#index-slice-member`). A slice of a string is a **copy** (a string is immutable). `s[a..a-1]` is the empty string; a bound outside `1..length` is `$err_index`.

## Functions

| Function | Result | Meaning |
|---|---|---|
| `trim()` | `String` | without the white space (space, tab, CR, LF) at both ends |
| `trim_start()`, `trim_end()` | `String` | the same at one end |
| `upper()`, `lower()` | `String` | the letters in upper or lower case: ASCII, Latin-1, Latin Extended-A, Greek and Cyrillic letters change; every other rune is kept; a rune never changes the length of the text (`ß` stays `ß`) |
| `starts_with(t)`, `ends_with(t)` | `Logic` | does the string begin or end with `t` |
| `contains(t)` | `Logic` | does `t` occur in the string |
| `find(t)` | `Integer` | the index (from 1, in runes) of the first occurrence of `t`, or `0` when there is none *(proposed)* |
| `replace(old, new)` | `String` | every non-overlapping occurrence of `old` replaced by `new`, from the left; `old` must not be empty |
| `split(sep)` | `List` | already specified: the pieces between the separators |
| `length()` | `Integer` | the number of runes |
| `reverse()` | `String` | the runes in the opposite order |
| `repeat(n)` | `String` | the text `n` times; `n` is a whole number, zero or more; the result may not pass 64 MB |
| `pad_start(n)`, `pad_start(n, fill)` | `String` | the text with `fill` (one rune, a space by default) added in front until it is `n` runes long; unchanged when it is already as long |
| `pad_end(n)`, `pad_end(n, fill)` | `String` | the same at the end |
| `lines()` | `List` | the lines of the text, without the line ends (`LF` or `CR LF`); a last line end does not make an empty line |

`t`, `old` and `new` are plain text, compared rune by rune (no case folding): `"a.b".replace(".", "-")` is `"a-b"`. A value that is not a `String` is `$err_argument`. The empty string is found at index 1 by `find("")`, is contained in every string, and begins and ends every string.

## Regular expressions

The operator `=~` is the match test. The functions above do not read their argument as a pattern, even when it begins with `/`; the search and replacement by pattern are `regex.find`, `regex.replace` and `regex.count` of the module `regex` (S11, planned), so that a path such as `"/data"` is plain text in `starts_with`. This differs from the sentence of the tutorial that gives `find(pattern: Regex)`; the choice is.
