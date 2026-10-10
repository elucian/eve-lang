# Lexical Structure

Status: **0.1-draft**. This file defines how Eve source text is split into tokens: everything a lexer needs. The grammar (`../syntax/grammar.md`) starts from the tokens defined here. Keywords, operators and delimiters are tables in `keywords.json`, [`operators.json`](operators.json) and [`delimiters.json`](delimiters.json); this file gives the rules they follow.

Words in this document: **must** and **must not** mark a requirement for every implementation; **may** marks a free choice. A rule marked *(proposed)* is not yet decided by the author; it is listed in [Open points](#open-points).

## Source text

- A source file is UTF-8 text. Its name ends with `.eve`.
- A line ends with LF or CR LF. Both are valid, also in the same file. A lone CR is not a line end.
- A statement ends with `;`, not with the end of the line, so a statement may span several lines.
- A tab is white space, but it must not appear in the indentation of a line (see [Layout](#layout)).
- The only white space characters are space, tab, CR and LF. Any other control character outside a comment or a literal is a lexical error.
- A file should be saved without a byte order mark. A UTF-8 BOM at the very start of a file is ignored (Q-016a); removing it is the job of a formatter.
- Names, keywords and operators are ASCII. Unicode may appear in comments, in string literals and in rune literals.

## Tokens

The lexer reads the longest sequence of characters that forms a token. Tokens are separated by white space or by the start of another kind of token. The token classes are:

| Class | Examples |
|---|---|
| identifier | `x`, `Point`, `this_is_ok`, `$error` |
| keyword | `driver`, `let`, `done` |
| number literal | `0`, `123`, `0x1F`, `0b101`, `0.5`, `12.50d`, `255b` |
| rune literal | `'a'`, `''`, `U+03B2` |
| string literal | `"text"`, `"""text"""` |
| operator | `+`, `:=`, `..<`, `and` |
| delimiter | `(` `)` `[` `]` `{` `}` `,` `;` `:` `.` |

Comments and white space are not tokens: they separate tokens and are dropped before parsing.

```ebnf
token       = identifier | keyword | number | rune | string | operator | delimiter ;
white-space = " " | tab | CR | LF ;
```

## File header

The first line says what kind of file it is.

| First line | Meaning |
|---|---|
| `#!` followed by the interpreter path, for example `#!/usr/bin/env eve` | Shebang. The file is a **free script**: sequential statements, no driver, no process. Only a file whose first line starts with `#!` can be a free script. A `#!` file that declares a `driver` at the top level is an **Eve macro** instead (D-152, `../syntax/declarations.md#eve-macro-level-5`). |
| `# title` | Title of a driver, an aspect, a module or an Eve macro. |
| `## subtitle` | Subtitle. |
| `**` … | A comment, for example a row of stars above a block comment. |

`#!` is an interpreter directive only in the first two characters of the file. On any other line, `#!` is an ordinary `#` comment. All header lines are comments: a parser may ignore them, except that it needs the first line to decide whether the file is a free script (a `#!` file without a top-level `driver`).

## Comments

| Form | Starts | Ends | Spans lines | Nests | Use |
|---|---|---|---|---|---|
| `#!` | line 1, indentation 0 | end of line | no | no | shebang |
| `#` | indentation 0 only | end of line | no | no | title |
| `##` | indentation 0 only | end of line | no | no | subtitle |
| `**` | anywhere outside a literal | end of line | no | no | line and end-of-line notes |
| `(** … **)` | inside an expression | the first `**)` | yes | no | expression comment |
| `/* … */` | anywhere outside a literal | the first `*/` | yes | no | block comment, disabled code |

Rules:

1. `#` starts a comment only at indentation 0 (the first character of the line). Indentation is significant in Eve, and `#` has no other use, so a `#` anywhere else is a lexical error (Q-016d). A line that starts with more than two `#` is a comment too.
2. `**` starts a comment wherever it appears outside a string, a rune or another comment, including indentation 0 and the first line. The power operator is `^`, never `**`. A row of stars `*****` is a `**` comment.
3. `(**` starts an expression comment and `**)` ends it. It may span lines. `(*` followed by anything but `*` is not a comment: it is the delimiter `(` and the operator `*`, as in `f(*args)`.
4. `/*` starts a block comment, closed by the first `*/`. Block comments do not nest: in `/* a /* b */ c */` the comment ends after `b` and `c */` is source text, which is an error.
5. Inside a comment every character is ignored, including quotes and other comment markers. Inside a string or a rune literal, comment markers are ordinary characters.
6. Text after the `return;` or `end name;` that closes a script may be a comment.
7. `//`, `--` and boxed `+--- … ---+` are not comments in Eve.

Example:

```eve
# comments in Eve
/*-----------------------------------------------
  A block comment can describe the whole script.
-----------------------------------------------*/
driver comment_demo is

  process main is
    ** a note on its own line
    let a = 0, b = 1 :Integer;
    a := a + b * (** first factor **) (a - 1); ** end-of-line note
  return;
end comment_demo;
```

## Identifiers

```ebnf
identifier = letter , { letter | digit | "_" } ;       (* see the rules below *)
sysname    = "$" , identifier ;                       (* system variable or constant *)
letter     = "a".."z" | "A".."Z" ;
digit      = "0".."9" ;
```

- An identifier starts with a letter and has at most 42 characters. Longer names are a lexical error.
- It is made of ASCII letters, digits and underscores. It must not end with `_` and must not contain `__`.
- Names are case-sensitive: `Point` and `point` are two names.
- `-` is not part of a name: `a-b` is `a - b`.
- `_` alone is the **void variable**: it accepts any value and discards it (it is always `null`).
- A reserved keyword (see `keywords.json`) must not be used as an identifier. A **contextual keyword** (`contextual: true`, D-116) is a keyword only at the places where the grammar expects it and is an ordinary name everywhere else: `new one := 1;` is valid, `match x one` is the option. Prefer a contextual keyword to a reserved one whenever the grammar allows it.
- By convention a type, a class and an ordinal value start with an upper-case letter; the language gives one meaning to this convention: the elements of an Ordinal whose names start with an upper-case letter are known in the scope where the Ordinal is visible, without a qualifier. `Null` (the type) and `null` (its value) are different names (D-080).

Valid: `x`, `a1`, `thisIsOK`, `this_is_ok`, `_`. Invalid: `1st`, `not_valid_`, `two__underscores`, `file-name`.

### Prefixes, sigils and suffix

A **prefix** is written in a declaration and is not part of the name. A **sigil** or **suffix** is part of the name and is always written. Visibility is not a prefix: it is the word `public`, `protected` or `private` (D-085).

| Symbol | Kind | Meaning |
|---|---|---|
| `*` | prefix | vararg parameter: `*args`; in a deconstruct, `*` skips many elements and `*rest` collects them |
| `@` | prefix | input/output parameter, named result, or `@self`; at a call, an argument passed by reference |
| `$` | sigil | system-wide variable or constant: `$error`, `$HOME`, `$err_raise` |
| `!` | suffix | a non-deterministic function (`random!()`, D-087) or an unsafe method (D-081) |

## Keywords

Eve reserves English words. The reserved words of 0.1 are listed with a description in [`keywords.json`](keywords.json) (D-094); the words of the levels 2 to 7 are reserved from level 1. A keyword can not be used as an identifier. `True` and `False` are predefined constants of type `Logic`; `null` is a value; none of them is a keyword. `print`, `write` and `read` are library functions, not keywords.

## Literals

### Integer and Natural

```ebnf
integer = digit , { digit } ;                         (* type Integer *)
natural = ( "0x" , hex , { hex } ) | ( "0b" , bit , { bit } ) ;   (* type Natural *)
hex     = digit | "a".."f" | "A".."F" ;
bit     = "0" | "1" ;
```

A decimal literal is an `Integer` (also when it is not negative). A literal that starts with `0x` or `0b` is a `Natural`. A sign is not part of the literal: `-5` is the unary operator `-` applied to `5`. A literal that does not fit its type is a lexical error (`Integer`: up to 9223372036854775807; `Natural`: up to 18446744073709551615).

**Suffix.** A base-10 literal may end with a letter that gives its type (D-080): `d` Decimal (`12.50d`), `r` Real (`5r`), `f` Float (`1.5f`), `b` Byte (`255b`), `w` Short (`11w`), `n` Natural (`42n`), `z` Huge (`-9000000000000000000z`, name to confirm). A hexadecimal literal takes no suffix, because `b`, `d` and `f` are hexadecimal digits; `0b` is the Byte zero and `0b0` the binary zero.

### Real

```ebnf
real = digit , { digit } , "." , digit , { digit } ;  (* type Real *)
```

A real literal has digits on both sides of the point: `0.5`, `9.9`. `1.` and `.5` are not literals. The lexer reads `1..5` as `1`, `..`, `5`. The number of decimals is significant in a range literal: `(0..1)(0.1)` has the precision of one decimal. `1/2` is not a literal: it is a division and returns a `Real`.

**Exponent (Q-013).** A real literal may end with an exponent: `1.5e3`, `2e-3`, `2E5` (`e` or `E`, an optional sign, digits). A literal with an exponent is always a `Real` (a double). The digit separator `_` is not accepted (`1_000` is a lexical error). A large number is written as a string followed at once by a type suffix: `"1,000,000"z`, `"12,500.75"d`; the commas are digit separators, and the suffix makes it a number literal, not a string.

### Rational

`3\4` is a `Rational` and belongs to version 2 (D-080): a version 1 implementation reports it as not supported.

### Rune

```ebnf
rune    = "'" , ( char | escape ) , "'" | "''" | unicode ;
unicode = "U+" , hex , hex , hex , hex , [ hex ] , [ hex ] ;    (* 4 to 6 digits *)
```

A rune literal holds one Unicode code point (stored in 4 bytes): `'a'`, `'β'`, `'\n'`. `''` is the empty rune, named `nil`; it is not `null`. `U+HHHH` to `U+HHHHHH` (4 to 6 hexadecimal digits, case-insensitive, up to `U+10FFFF`) is a rune literal with no quotes: `U+03B2` is `'β'`. A rune literal with more than one code point is a lexical error (`'one'` is an error: use `"one"`).

### String

```ebnf
string = '"' , { char | escape | interpolation } , '"' ;
```

A string literal is UTF-8 text between double quotes. It ends on the same line unless it is a text literal. The empty string is `""`.

**Escape sequences.** Inside `"…"` and `'…'` a backslash starts an escape. Any other character after `\` is a lexical error.

| Escape | Meaning |
|---|---|
| `\\` | backslash |
| `\"` | double quote |
| `\'` | single quote |
| `\{` `\}` | a literal brace: an unescaped brace in a string always belongs to a placeholder (D-102) |
| `\n` `\r` `\t` | line feed, carriage return, tab |
| `\0` | the NUL character |
| `{U+H…}` | Unicode code point, 1 to 6 hexadecimal digits: `{U+03B2}` is β (D-119) |
| `&name;` | HTML character reference: `&alpha;` is α |
| `\&` | the ampersand |

Not all Unicode characters have an HTML name, so `{U+H…}` (a rune literal in a placeholder, D-120) and `&name;` are both valid. The numeric references `&#N;` and `&#xH;` do not exist (D-119). The ampersand itself is written `\&` or `&amp;`; both forms are supported. A `&` that does not start a character reference is an ordinary character.

**Interpolation (D-102, D-120).** A string inserts values with placeholders: a name or a literal in braces, with an optional format after the format operator `%`:

```ebnf
interpolation = "{" , ( member | literal ) , [ "%" , format ] , "}" ;   (* spaces are allowed around % *)
member        = [ "$" ] , name , { "." , name | "[" , index , "]" } ;
index         = bound , [ ".." , bound ] ;                      (* an element, or a part by a range *)
bound         = [ "-" ] , integer | name | string ;             (* a quoted key: its quotes are not escaped *)
literal       = number | string | symbol | boolean | list | ... ;   (* any literal of the language *)
```

| Form | Inserts |
|---|---|
| `{name}` | the value of the name, written by its type: a string as it is, a number in digits, a boolean as `True` or `False` |
| `{name % format}` | the value with a format; the codes allowed depend on the type of the value |
| `{literal}` | the literal, written by its type: `{399}`, `{"test"}`, `{(1,2,3)}`, `{'x'}`, `{True}`, `{U+03B1}` |
| `\{` `\}` | a literal brace |

In a string literal every unescaped `{` opens a placeholder; a `{` that does not open a valid placeholder (`"{1, 2}"`, `"{}"`, `"{a + b}"`) and a lone `}` are lexical errors, so a literal brace is always written `\{` or `\}`. A placeholder holds a **name**, a **literal** or a **simple expression** (Q-015, Q-033a, D-120, D-121): `{n + 1}`, `{a * 2 - 1}`, `{s.length()}`, `{a > 2}`, `{s + "!"}`. A statement, an assignment or a lambda is not allowed. `%` always starts the format, so an expression that needs it is written in parentheses: `{((n + 1) % 3)}`. A literal is any literal of the language: `{399}`, `{"test"}`, `{(a, b, c)}`, `{'x'}`, `{True}`, `{U+03B1}` (the rune of that code point). **The quotes of a literal inside the braces are not escaped**: the string ends at the first `"` outside the braces, and a brace or a `%` inside a quoted text of a placeholder does not count. A name is: a variable, a constant, a system variable (`{$HOME}`), an attribute path (`{p.x}`, `{self.value}`), or a member selected with brackets: an element (`{a[1]}`, `{a[-1]}`, `{a[i]}`, `{m[key]}`, `{m["key"]}`) or a part by a range (`{a[2..4]}`). An index is an integer, a name, a quoted key or a range; the quotes of a key are written as they are.  Inside a placeholder `%` is the format operator and has no other meaning: `{n % i5}`. The `format` has its own rules, defined in `../library/format.md` (pending). `{U+H…}` is a rune literal like any other (D-119); `\xHH` and `\u{…}` do not exist. The text literal and the regex literal are raw: they have no placeholders and their braces need no escape. The older forms `\s{…}`, `\n{…}`, `\b{…}`, `\#{…}`, `#s`, `#n`, `#{…}`, the format after `:` and the template operator `?` do not exist; `#` is used only in comments.

**Text literal.** `"""…"""` is a text literal on several lines. It is raw: there are no escape sequences and no interpolation; double quotes need no escape. The closing `"""` is alone on its line, and the number of spaces before it is the indentation that the compiler removes from every line of the text. The line break after the opening quotes and the one before the closing quotes are not part of the text (Q-014). A text literal has the type `Text`. The tag forms `<text>`, `<xml>`, `<html>`, `<data>` and `<code>` also create a `Text` literal, with the same rule for the first and the last line break *(their syntax is not specified yet)*.

**Regex literal (Q-018).** A string literal whose first character after the opening quote is `/` is a regex literal: `"/\sis\s/g"`. It is raw: a backslash and the character after it are kept as they are, there are no escape sequences and no interpolation (`\s{2}` is two spaces of the pattern, and `{2}` a count, not a placeholder); the only escape is `\"`, which gives `"`, so `\\"` is a kept `\\` followed by the closing quote. A regex literal has the type `String`, like any string: it can be stored, passed and concatenated; the rule only decides how the lexer reads the literal. Every string literal that starts with `/` follows it, file paths and routes included: a value is inserted by concatenation, `"/data/" + name`. A regular expression is written `/pattern/flags`; the right operand of `=~` is used as a pattern when its value starts with `/`, also when it was built by concatenation (`"/\s" + word + "\\s/"`: only the first part is a regex literal).

### Constants

`True` and `False` are the constants of type `Logic`. `null` is the only value of the type `Null` and means that no object exists. `nil` is the empty rune `''`. There is no lexical form for a date or a time: they are made with `parse()` or with an object literal and a type hint. A **duration** (level 4) is an integer followed at once by a unit, `ms`, `s`, `m` or `h`: `10ms`, `30s`, `2m`, `1h`; its type is `Duration` (`../semantics/multitasking.md#durations`, D-144).

### Collection delimiters

| Delimiters | Literal |
|---|---|
| `( … )` | list: `(1, 2, 3)`; `()` is the empty list; `(x)` is a grouping, the list of one element is `(x,)` (D-063) |
| `[ … ]` | array or matrix: `[1, 2, 3]`, `[[1, 2], [3, 4]]` |
| `{ … }` | ordinal, DataSet, DataMap or Object: `{}` is the empty DataSet, `{:}` the empty DataMap |

A brace literal with unquoted keys is an Object, with quoted or numeric keys a DataMap, with plain values a DataSet.

After a value, `[ … ]` is an index. A matrix or a tensor takes one index per dimension, either separated by commas in one pair of brackets or in one pair of brackets each: `m[x, y]` is `m[x][y]` and `t[x, y, z]` is `t[x][y][z]` (D-064). An index is a number (negative counts from the end, `-1` is the last, D-079), a range or `*` (the whole dimension), so `m[1..5][3]` is column 3 of the first 5 rows and `m[3][1..5]` the first 5 columns of row 3. A single index on a matrix or tensor, `m[k]`, is the absolute row-major index. Elements are separated by commas; a trailing comma is allowed: `(a, b, c,)` and `(a,)` are lists (Q-016).

## Operators and punctuation

Eve uses ASCII symbols. The lexer reads the longest operator that matches (`..<` before `..`, `<-` before `<`), so write a space where two operators meet: `a < -1`, not `a<-1`.

```text
Three symbols : ..<  >..  >..<
Two symbols   : ==  <>  =>  <=  >=  :>  <:  ..  &&  ||  ><  =~  +-
Modifiers     : ::  :=  +=  -=  *=  /=  %=  ^=  +>  <+  >>  <<
List arrows   : ->  <-
One symbol    : , : . ; = ? % ^ * - + / < > & | ! @ $
Word operators: and  or  xor  not  is  in  eq  as  if  else
```

- The modifiers `&=` and `|=` do not exist.
- `?` is the open end of a range or an array: `(0..?)`, `[?]Integer`. It is not an operator.
- `->` and `<-` remove the last and the first element of a list (and `<+`, `+>` add at the end and at the start).
- `&&` is intersection and `||` is union of sets; `=~` is the approximate match (a regular expression, or a number within a tolerance); `!~` does not exist (D-079); `+-` builds the range `b - t .. b + t`.
- `><` is the cartesian product, one token: not `>` followed by `<`. The compiler reports a hint when its operands are not collections or ranges, because it is easy to confuse with `<>` (not equal).
- Operator meaning, arity, precedence and associativity are in [`operators.json`](operators.json).
- `;` ends a statement. `,` separates elements and arguments. `:` is a type hint, a label or a pair `key:value`.

## Layout

Eve is a free-format language for the lexer, but the parser requires a layout (details in
`../syntax/regions.md`):

- Everything between a script header and its `end name;` is indented by exactly **2 spaces** per level. Another indent is an error. A tab in the indentation is an error.
- Only the script header, `end name;` and the comments before the header start at indentation 0.
- A statement may span lines; the `;` ends it.

## Lexical errors

A conforming implementation reports a lexical error for: an invalid UTF-8 sequence; an identifier longer than 42 characters, ending in `_` or containing `__`; an unknown escape sequence (outside a regex literal and a text literal); an unterminated string, rune, block comment or expression comment; a rune literal with more than one code point; a number that does not fit its type; a `#` that is not at indentation 0; a brace in a string that does not open a placeholder `{name [% format]}`, or a lone `}`; a control character; a tab in indentation; `U+` followed by fewer than 4 or more than 6 hex digits, or a value above `U+10FFFF`.

## Open points

These rules were added by the specification writer and wait for confirmation; the numbered questions are in [`plan/decision_level1.md`](../../plan/decision_level1.md).

| Point | Question |
|---|---|


