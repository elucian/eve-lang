# Lexical Structure

Status: **0.1-draft**. This file defines how Eve source text is split into tokens: everything a lexer needs.
The grammar (`../syntax/grammar.md`) starts from the tokens defined here.
Keywords, operators and delimiters are tables in `keywords.json`,
[`operators.json`](operators.json) and [`delimiters.json`](delimiters.json); this file gives the rules they follow.

Words in this document: **must** and **must not** mark a requirement for every implementation; **may** marks a
free choice. A rule marked *(proposed)* is not yet decided by the author; it is listed in [Open points](#open-points).

## Source text

- A source file is UTF-8 text. Its name ends with `.eve`.
- A line ends with LF or CR LF. Both are valid, also in the same file. A lone CR is not a line end.
- A statement ends with `;`, not with the end of the line, so a statement may span several lines.
- A tab is white space, but it must not appear in the indentation of a line (see [Layout](#layout)).
- The only white space characters are space, tab, CR and LF. Any other control character outside a comment or a
  literal is a lexical error.
- Names, keywords and operators are ASCII. Unicode may appear in comments, in string literals and in symbol literals.

## Tokens

The lexer reads the longest sequence of characters that forms a token. Tokens are separated by white space or
by the start of another kind of token. The token classes are:

| Class | Examples |
|---|---|
| identifier | `x`, `Point`, `this_is_ok`, `$error` |
| keyword | `driver`, `let`, `done` |
| number literal | `0`, `123`, `0x1F`, `0b101`, `0.5`, `3\4` |
| symbol literal | `'a'`, `''`, `U+03B2` |
| string literal | `"text"`, `"""text"""` |
| operator | `+`, `:=`, `..<`, `and` |
| delimiter | `(` `)` `[` `]` `{` `}` `,` `;` `:` `.` |

Comments and white space are not tokens: they separate tokens and are dropped before parsing.

```ebnf
token       = identifier | keyword | number | symbol | string | operator | delimiter ;
white-space = " " | tab | CR | LF ;
```

## File header

The first line says what kind of file it is.

| First line | Meaning |
|---|---|
| `#!` followed by the interpreter path, for example `#!/usr/bin/env eve` | Shebang. The file is a **free script**: sequential statements, no driver, no process. Only a file whose first line starts with `#!` can be a free script. |
| `# title` | Title of a driver, an aspect or a module. |
| `## subtitle` | Subtitle. |
| `**` … | A comment, for example a row of stars above a block comment. |

`#!` is an interpreter directive only in the first two characters of the file. On any other line, `#!` is an ordinary
`#` comment. All header lines are comments: a parser may ignore them, except that it needs the first line to
decide whether the file is a free script.

## Comments

| Form | Starts | Ends | Spans lines | Nests | Use |
|---|---|---|---|---|---|
| `#!` | line 1, column 1 | end of line | no | no | shebang |
| `#` | column 1 only | end of line | no | no | title |
| `##` | column 1 only | end of line | no | no | subtitle |
| `**` | anywhere outside a literal | end of line | no | no | line and end-of-line notes |
| `(** … **)` | inside an expression | the first `**)` | yes | no | expression comment |
| `/* … */` | anywhere outside a literal | the first `*/` | yes | no | block comment, disabled code |

Rules:

1. `#` starts a comment only in column 1 (the first character of the line, with no indentation). A `#` anywhere else
   is a lexical error. A line that starts with more than two `#` is a comment too.
2. `**` starts a comment wherever it appears outside a string, a symbol or another comment, including column 1 and
   the first line. The power operator is `^`, never `**`. A row of stars `*****` is a `**` comment.
3. `(**` starts an expression comment and `**)` ends it. It may span lines. `(*` followed by anything but `*` is
   not a comment: it is the delimiter `(` and the operator `*`, as in `f(*args)`.
4. `/*` starts a block comment, closed by the first `*/`. Block comments do not nest: in `/* a /* b */ c */` the
   comment ends after `b` and `c */` is source text, which is an error.
5. Inside a comment every character is ignored, including quotes and other comment markers. Inside a string or a
   symbol literal, comment markers are ordinary characters.
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
- `_` alone is the **void variable**: it accepts any value and discards it (it is always Null).
- A keyword (see `keywords.json`) must not be used as an identifier.
- By convention a type, a class and an ordinal value start with an upper-case letter; the language gives one
  meaning to this convention: the elements of an Ordinal whose names start with an upper-case letter are known in
  the scope where the Ordinal is visible, without a qualifier.

Valid: `x`, `a1`, `thisIsOK`, `this_is_ok`, `_`. Invalid: `1st`, `not_valid_`, `two__underscores`, `file-name`.

### Prefixes, sigils and suffix

A **prefix** is written in a declaration and is not part of the name. A **sigil** or **suffix** is part of the name
and is always written.

| Symbol | Kind | Meaning |
|---|---|---|
| `*` | prefix | vararg parameter: `*args`; in a deconstruct, `*` skips many elements and `*rest` collects them |
| `@` | prefix | input/output parameter, named result, or `@self`; at a call, an argument passed by reference |
| `_` | prefix | protected member, in its declaration |
| `.` | prefix | public member, in its declaration |
| `$` | sigil | system-wide variable or constant: `$error`, `$HOME`, `$err_raise` |
| `!` | suffix | a function or method that may raise, has side effects or is not deterministic: `name!()` |

A member can not be public and protected at the same time, so `_` and `.` never belong to the name.
A `$` followed by an identifier character starts a system name; a bare `$` inside `[ ]` is the index of the last
element (`a[$]`, `a[$ - 1]`).

The suffix `!` must follow the last character of the identifier with no space. The operator `!~` (does not match)
must be separated from the identifier before it by white space *(proposed)*.

## Keywords

Eve reserves English words. The reserved words of 0.1 are listed in `keywords.json`
(pending, step S2.4). Some words are reserved for later versions and can not be used as identifiers either.
`True`, `False` and `Null` are predefined constants, not keywords.

## Literals

### Integer and Natural

```ebnf
integer = digit , { digit } ;                         (* type Integer *)
natural = ( "0x" , hex , { hex } ) | ( "0b" , bit , { bit } ) ;   (* type Natural *)
hex     = digit | "a".."f" | "A".."F" ;
bit     = "0" | "1" ;
```

A decimal literal is an `Integer` (also when it is not negative). A literal that starts with `0x` or `0b` is a `Natural`.
A sign is not part of the literal: `-5` is the unary operator `-` applied to `5`. A literal that does not fit its type
is a lexical error (`Integer`: up to 9223372036854775807; `Natural`: up to 18446744073709551615).

### Real

```ebnf
real = digit , { digit } , "." , digit , { digit } ;  (* type Real *)
```

A real literal has digits on both sides of the point: `0.5`, `9.9`. `1.` and `.5` are not literals. The lexer reads `1..5` as
`1`, `..`, `5`. The number of decimals is significant in a range literal: `(0..1)(0.1)` has the precision of one decimal.
`1/2` is not a literal: it is a division and returns a `Real`.

### Rational

```ebnf
rational = integer , "\" , integer ;                  (* type Rational, no spaces *)
```

`3\4` is a `Rational`: two integers separated by a backslash. Its evaluation is postponed until a value is needed.

### Symbol

```ebnf
symbol  = "'" , ( char | escape ) , "'" | "''" | unicode ;
unicode = "U+" , hex , hex , hex , hex , [ hex ] , [ hex ] ;    (* 4 to 6 digits *)
```

A symbol literal holds one Unicode code point (stored in 4 bytes): `'a'`, `'β'`, `'\n'`. `''` is the empty symbol,
named NIL; it is not Null. `U+HHHH` to `U+HHHHHH` (4 to 6 hexadecimal digits, case-insensitive, up to `U+10FFFF`)
is a symbol literal with no quotes: `U+03B2` is `'β'`. A symbol literal with more than one code point is a lexical error.

### String

```ebnf
string = '"' , { char | escape | interpolation } , '"' ;
```

A string literal is UTF-8 text between double quotes. It ends on the same line unless it is a text literal. The empty
string is `""`.

**Escape sequences.** Inside `"…"` and `'…'` a backslash starts an escape. Any other character after `\` is a lexical error.

| Escape | Meaning |
|---|---|
| `\\` | backslash |
| `\"` | double quote |
| `\'` | single quote |
| `\{` `\}` | the brace itself |
| `\n` `\r` `\t` | line feed, carriage return, tab |
| `\0` | the NUL character |
| `\xHH` | code point 00 to FF, two hexadecimal digits |
| `\u{H…}` | Unicode code point, 1 to 6 hexadecimal digits: `\u{3B2}` is β |
| `&name;` | HTML character reference: `&alpha;` is α (also `&#N;` and `&#xH;` *(proposed)*) |

Not all Unicode characters have an HTML name, so `\u{…}` and `&name;` are both valid. A `&` that does not start
a character reference is an ordinary character *(proposed)*.

**Interpolation.** A string may insert values with escapes that start with a backslash and a letter, like `\u{…}`:

```ebnf
interpolation = ( "\s{" | "\#{" | "\b{" ) , expression , [ ":" , format ] , "}" ;
```

| Form | Inserts |
|---|---|
| `\s{expr}` | any expression, as a string |
| `\#{expr}` | a number |
| `\b{expr}` | a boolean: `True` or `False` |

The `format` has its own rules, defined in `../library/format.md` (pending). The expression ends at the first
`:` or `}` that is not inside brackets or a nested literal; to use the pair operator `:` inside, write it in parentheses
*(proposed)*. The older forms `#s`, `#n`, `#{…}`, `{name}` and the template operator `?` do not exist.

**Text literal.** `"""…"""` is a text literal on several lines. It is raw: there are no escape sequences and no
interpolation; double quotes need no escape. The closing `"""` is alone on its line, and the number of spaces before it is
the indentation that the compiler removes from every line of the text. The line break after the opening quotes and the one
before the closing quotes are not part of the text *(proposed)*. The type of a text literal (`String` or `Text`) is
open (Q-014).

**Regular expression.** A regular expression is a string literal whose content starts with `/` and ends with `/flags`:
`"/\sis\s/g"`. It is an ordinary string for the lexer; the right operand of `=~` and `!~` is read as a pattern when it starts with `/`.
The double quote inside a pattern must be escaped with `\"`.

### Constants

`True` and `False` are the constants of type `Logic`. `Null` means no value. `NIL` is the empty symbol `''`.
There is no lexical form for a date, a time or a duration: they are made with `parse()` or with an object literal and a
type hint.

### Collection delimiters

| Delimiters | Literal |
|---|---|
| `( … )` | list: `(1, 2, 3)`; `()` is the empty list; `(x)` is a list of one element, never a grouping of an expression |
| `[ … ]` | array, vector or matrix: `[1, 2, 3]`, `[[1, 2], [3, 4]]` |
| `{ … }` | ordinal, DataSet, HashMap or Object: `{}` is the empty DataSet, `{:}` the empty HashMap |

A brace literal with unquoted keys is an Object, with quoted or numeric keys a HashMap, with plain values a DataSet.

After a value, `[ … ]` is an index. A matrix or a tensor takes one index per dimension, either separated by commas in one
pair of brackets or in one pair of brackets each: `m[x, y]` is `m[x][y]` and `t[x, y, z]` is `t[x][y][z]` (D-064). An index
is a number, `$` (the last), a range or `*` (the whole dimension), so `m[1..5][3]` is column 3 of the first 5 rows and
`m[3][1..5]` the first 5 columns of row 3. A single index on a matrix or tensor, `m[k]`, is the absolute row-major index.
Elements are separated by commas; a trailing comma is not allowed *(proposed)*.

## Operators and punctuation

Eve uses ASCII symbols. The lexer reads the longest operator that matches (`..<` before `..`, `<-` before `<`),
so write a space where two operators meet: `a < -1`, not `a<-1`.

```text
Three symbols : ..<  >..  >..<
Two symbols   : ==  <>  =>  <=  >=  :>  <:  ..  &&  ||  ><  =~  !~
Modifiers     : ::  :=  +=  -=  *=  /=  %=  ^=  +>  <+  >>  <<
List arrows   : ->  <-
One symbol    : , : . ; = ? % ^ * - + / < > & | ! @ $
Word operators: and  or  xor  not  is  in  eq  as  if  else
```

- The modifiers `&=` and `|=` do not exist.
- `?` is the open end of a range or an array: `(0..?)`, `[?]Integer`. It is not an operator.
- `->` and `<-` remove the last and the first element of a list (and `<+`, `+>` add at the end and at the start).
- `&&` is intersection and `||` is union of sets; `=~` is regex match and `!~` is not match.
- `><` is the cartesian product, one token: not `>` followed by `<`. The compiler reports a hint when its operands are not
  collections or ranges, because it is easy to confuse with `<>` (not equal).
- Operator meaning, arity, precedence and associativity are in [`operators.json`](operators.json).
- `;` ends a statement. `,` separates elements and arguments. `:` is a type hint, a label or a pair `key:value`.

## Layout

Eve is a free-format language for the lexer, but the parser requires a layout (details in
`../syntax/regions.md`):

- Everything between a script header and its `end name;` is indented by exactly **2 spaces** per level.
  Another indent is an error. A tab in the indentation is an error.
- Only the script header, `end name;` and the comments before the header start in column 1.
- A statement may span lines; the `;` ends it.

## Lexical errors

A conforming implementation reports a lexical error for: an invalid UTF-8 sequence; an identifier longer than 42 characters,
ending in `_` or containing `__`; an unknown escape sequence; an unterminated string, symbol, block comment or expression
comment; a symbol literal with more than one code point; a number that does not fit its type; a `#` that is not in column 1;
a control character; a tab in indentation; `U+` followed by fewer than 4 or more than 6 hex digits, or a value above `U+10FFFF`.

## Open points

These rules were added by the specification writer and wait for confirmation; the numbered questions are in
[`plan/decisions.md`](../../plan/decisions.md).

| Point | Question |
|---|---|
| Scientific notation (`1.5e3`), digit separators (`1_000`) | Q-013 |
| `&name;` forms, writing a literal `&name;`, type of `"""…"""`, line breaks of a text literal | Q-014 |
| End of the expression in `\s{expr:format}` | Q-015 |
| BOM, `!~` against the `!` suffix, trailing comma, a `#` in a position other than column 1 | Q-016 |
