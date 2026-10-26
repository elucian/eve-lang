# Text and encoding

Status: **draft**, level 3. Library step L5. Written in Eve (`lib/text/`), with two native modules, `regex` and `unicode`, behind `external` declarations. Feature: F-LIB-03.

The functions of a `String` (`trim`, `find`, `replace`, `split` ...) are in [strings.md](strings.md); this page is what a program needs around them: encodings, slugs, templates, differences, regular expressions and Unicode. A wrong argument is `$err_argument` (17).

## Rules of import

`from lib use (text);` gives the functions of the six modules `encode`, `slug`, `template`, `diff`, `regex` and `unicode` as members of `text` (`text.base64(s)`, `text.slug(s)`, `text.fill(t, m)`), and the modules `text.encode`, `text.diff`, `text.regex`, `text.template` and `text.unicode`; a module can be imported alone, `from lib/text use (encode);`. The names `regex` and `unicode` are also known without an import, and the operator `=~` uses the engine of `regex`.

## Module encode

A `String` is encoded as its UTF-8 bytes; a text that is not valid UTF-8 is `$err_argument`.

| Function | Result | Meaning |
|---|---|---|
| `hex(s)`, `from_hex(t)` | `String` | the bytes as lower-case hexadecimal, and back (an odd length or a bad digit is `$err_argument`) |
| `base64(s)`, `from_base64(t)` | `String` | Base64 with padding (RFC 4648), and back |
| `base64url(s)`, `from_base64url(t)` | `String` | the Base64 of URLs (`-` and `_`, no padding), and back; the padding may be present or not |
| `url(s)` | `String` | percent encoding (RFC 3986): the letters, the digits and `- . _ ~` stay, every other rune is `%XX` for each of its bytes |
| `from_url(t)` | `String` | the bytes of the `%XX` codes; a `%` not followed by two hexadecimal digits is `$err_argument` |

## Module slug

| Function | Result | Meaning |
|---|---|---|
| `ascii(text)` | `String` | the letters with marks of the Latin alphabets written with plain letters (`Łódź` is `Lodz`); `ß` is `ss`, `æ` and `œ` are `ae` and `oe`; any other rune stays |
| `slug(text)`, `slug(text, separator)` | `String` | lower case, the marks removed, each run of runes that are not a letter or a digit one separator (`-` by default), none at the ends |

## Module template

A template is a text with holes written `{name}`, as a template file is (a text literal of the program has the same holes, filled in place). There are no loops and no conditions: the program builds a fragment and puts it in a hole. In a literal the braces are written `\{` and `\}`.

| Function | Result | Meaning |
|---|---|---|
| `names(text)` | list | the names of the holes, in order of first use; the spaces around a name do not count |
| `fill(text, values)` | `String` | the text with each hole replaced by the value of its name in the map, written as `print` writes it; two braces in a row are one brace |

A name that the map does not have is `$err_key` (11); a brace that is not closed, a hole without a name and a closing brace that closes no hole are `$err_argument`. A value is inserted as it is: the program escapes it first when the template is HTML.

## Module diff

| Function | Result | Meaning |
|---|---|---|
| `lines(a, b)` | list of `Edit` | the edits that turn the lines of `a` into the lines of `b`, in order; an `Edit` has `op` (`=` in both, `-` only in `a`, `+` only in `b`) and `line`; the common lines are a longest common subsequence |
| `unified(a, b)` | `String` | the edits as lines: two spaces before a common line, `- ` before a removed line, `+ ` before an added line |
| `equal(a, b)` | `Logic` | are the two texts the same line by line (a last line end does not count) |

## Module regex

The syntax is the one of RE2, and the time is linear in the length of the text and the size of the pattern: no pattern takes exponential time. The pattern is written as a regex literal, `"/pattern/flags"`, in which the backslash is kept as written ([lexical.md](../lexical/lexical.md#string)); a pattern text that does not start with `/` is read as the pattern itself.

| Syntax | Meaning |
|---|---|
| `a`, `\.`, `\n`, `\t`, `\xHH`, `\x{H...}` | a rune; a backslash before a punctuation mark is that mark |
| `.` | any rune except a line end (with the flag `s`: any rune) |
| `[abc]`, `[a-z]`, `[^a-z]`, `[\d_]` | a class of runes |
| `\d`, `\w`, `\s`, `\D`, `\W`, `\S` | digit, word rune, white space (ASCII, as in RE2) and their complements |
| `^`, `$` | the start and the end of the text (of a line with the flag `m`) |
| `\b`, `\B` | a boundary of a word, and the absence of one |
| `(...)`, `(?:...)`, `(?P<name>...)` | a group that is numbered, a group that is not, a group with a name (the name is not used) |
| `a|b` | one or the other |
| `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}` | repeats, greedy; a `?` after them makes them lazy; a count is at most 1000 |

The flags are the letters after the closing `/`: `i` ignores the case (ASCII, Latin-1, Greek and Cyrillic), `m` lets `^` and `$` stand at the line ends, `s` lets `.` match a line end, and `g` is accepted and ignored. A pattern that is not good, or a text and a pattern whose product is too large, is `$err_argument`.

| Function | Result | Meaning |
|---|---|---|
| `is_match(text, pattern)` | `Logic` | does the pattern match somewhere in the text |
| `matches(text, pattern)` | `Logic` | does it match the whole text |
| `find(text, pattern)` | `DataMap?` | the first match, or `null`: the keys `start` and `end` (the first and the last rune of the match, counted from 1), `text`, and `groups`, the text of each group in order, `null` for a group that took no part |
| `find_all(text, pattern)` | list | every match that does not overlap the one before, as the maps of `find`; an empty match moves on by one rune |
| `replace(text, pattern, replacement)` | `String` | every match replaced; in the replacement `$0` is the match, `$1` to `$9` the groups and `$$` a dollar |
| `split(text, pattern)` | list | the pieces between the matches; an empty match splits nothing |

The operator `=~` of the language is the test `is_match` with the same patterns: `"this is" =~ "/^th(is|at) is$/"`.

## Module unicode

| Function | Result | Meaning |
|---|---|---|
| `nfc(text)` | `String` | the text in normal form C: a letter and its marks are one rune when Unicode has one |
| `is_nfc(text)` | `Logic` | is the text in normal form C |
| `width(text)` | `Integer` | the columns of a terminal: 2 for a wide rune (Chinese, Japanese, Korean, most emoji), 0 for a combining mark and a control rune, 1 for any other |
