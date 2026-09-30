# Issues: syntax.html

Page: `tutorial/syntax.html` (1,329 lines, 33 sections). Reviewed 2026-09-28 against the 49 `.eve`
files in `demo/`, `pattern/` and `test/`. How to answer: [README](README.md).

Applied 2026-09-28 from the answers below: `--` comments → `**` (138 in `.eve` files, 249 in the
Eve code blocks of 14 tutorial pages); `!=` → `<>` (10 in `.eve` files, 5 in pages); test
drivers renamed `a01_driver()`, `a02_comments()`, `a03_print()`. The page prose still describes
the old rules; it is rewritten once all questions here are answered.

## Questions

### SYN-01 `process` colon
The page writes `process:`; 47 of 49 example files write `process`.
**Answer:** `process` makes sense; `:` is not required.
Status: answered

### SYN-02 Driver names and `-`
Identifiers allow letters, digits and `_`, but the tests used `driver a01-driver():`.
**Answer:** `-` is not allowed in identifier names, to avoid confusion with the `-` operator;
use `_`. `driver a01_driver()` is good enough, without `:`.
Status: answered (tests renamed)

### SYN-03 Comment forms
The page describes comments three different ways.
**Answer:** Comments are `#`, `##` and `**`. `--` and `+- -+` comments are removed. New:
`(* ... *)` for expression comments and `/* ... */` for block comments. `**` can be used at the
end of a line or indented; `#` and `##` only at the beginning of a line, without indentation.
Status: answered (follow-ups SYN-14 to SYN-18)

### SYN-04 Comment nesting
Can `/* */` nest inside `/* */`? Test a02 says "We use `/*...*/` to create nested comments".
**Answer:** 
No, nested comments are not  possible. /* .../* nested forbiden */ */ this is why we need 
expression comments (*....*)
Status: answered → D-014

### SYN-05 Not-equal operator
The page says `<>`; the examples used `!=`.
**Answer:** `<>` is the correct symbol for different. `!` is the sigil for unsafe operations.
Status: answered (follow-up SYN-19)

### SYN-06 Initializer `=`
The page says three things: `=` takes "only data literals, no expressions"; it takes "a
constant literal or an expression, but the expression is not evaluated"; and it "creates an
expression, so it can be chained: `new a = b = 1`". What may follow `=`: literals only, constant
expressions, or any expression? Is chaining kept?
**Answer:** 
let a = b = c = y : Integer; (variable assinmnet) with type declaration. 
Also =, can be used to assign values for parameters that already have a type. 
Idea is := use for type inference and is not an expression, while = do not invoke type inference and is an expression, return it's value, also := execute recursive the expression on the right while = just borrow a variable value.
Status: answered → D-017

### SYN-07 `print` form
The page writes `print "x";`, `print ("a", v);` and `print;`; test a03 writes
`print("Hello World!");`. Is `print` a statement taking an expression list, with optional
parentheses? Is `print(...)` without a space the same thing? Same for `write`.
**Answer:** print is a method. In eve, a method can be call with a list of expressions that are mapped to parameters, can even use parametters by name x = expression, y = expression, z = expression but also can have reserved parameter name separator = "?" that is default ",". If paranthesis are used, optional parameters are in second set of parameters. print (arguments) option (separator = ".") for example.
Status: answered, follow-up SYN-22

### SYN-08 Identifier rules
Max 30 characters; `_` alone is valid; a name may start with `_`; but `_` is also the protected
sigil ("not part of the identifier") and the void variable. Is 30 a hard limit? Are names
case-sensitive? Is a leading `_` part of the name or the protected sigil?
**Answer:** If _ preced a name in declaration that is a signal that variable is protected, a variable that start  "." in declaration indicate a public member. Same variable can't be public and private in same time so the identifier do not include _ or . that precede it's declaration. $ on the other hand does. It belong to identifier and is a sigil that show a system whide variable.
Status: answered → D-017 (30-character limit and case sensitivity: SYN-23)

### SYN-09 Keyword table
~100 words with duplicates (`constant`, `method`, `reset`, `add`, `del`, `pop`) and a typo
(`labe`). Missing, although the page uses them: `driver`, `module`, `aspect`, `set`, `new`,
`let`, `match`, `when`, `cycle`, `done`, `split`, `finalize`, `suspend`, `wait`, `run`, `yield`,
`is`, `in`, `not`, `and`, `or`, `xor`, `as`, `eq`. Which words are reserved in 0.1, and which
only in some regions? (Same as Q-002; the table will be generated from `keywords.json`.)
**Answer:** I agree, the table is redundant for documentation purpose, we will create the spec and then this table will be updated when the spec change. For now we update the table by removing duplicates.
Status: answered: duplicates removed; the table was rebuilt with the D-016 keywords (123 words)

### SYN-10 Operator set and precedence
Listed but never described: `->`, `<-`, `#(...)`. Unclear: `%` as "scalar operator", `-` as
"string concatenation", `<<` / `>>` as both shift and modifier, `&&` / `||` as set operators and
`&=`. Which operators are in 0.1, and what do these mean? What is the precedence order (highest
first) and associativity? The spec's `operators.json` needs it.
**Answer:** Operators << >> are shift modifiers. They modify in place a value. -> <- are reserved unclear operators will be clarified later. Just say (reserved unused)
Status: answered → D-017 (precedence still needed: SYN-24)

### SYN-11 Block closers
"A block ends with `return`, `repeat` or `done`", but `join` and `resolve` also close blocks.
List every block opener with its closer, for example `match … done`, `cycle … repeat`,
`job … resolve`, `split … join`, `begin … ?`.
**Answer:** I have modified the control.html and processing.html that clarify the structure of control statements and replace run with apply
Status: answered → D-016

### SYN-12 String templates and escapes
`print "param1: {a}"` interpolates; `?` is "template find & replace". Does every `"..."`
interpolate `{name}`? How is a literal `{` written? Which escape sequences exist (`\n`, `\"`)?
Can `'...'` hold more than one character?
**Answer:** Literal { } must be escaped in string patterns \{ \}, provide a comprehensive list for escape sequence, my tutorial is now incomplete.
Status: answered, follow-up SYN-20

### SYN-13 `over` and `panic` codes
D-010 has `over` = 0 and `over 1` = 1. Can `over` take any code (`over 5;`)? The page says
`panic` gives "status > 0": which code? And `exit`?
**Answer:** establish a table with exit codes and add to the table when discover new exit codes
Status: answered: D-010 is the exit-code table; new codes are added there as they appear

### SYN-14 Test file names
The page says the file name equals the driver name (`hello.eve` holds `driver hello`). The
drivers are now `a01_driver`, but the files are still `a01-driver.eve`, and `test/readme.md`
sets the convention `a01-feature.eve`. Rename the files to `a01_driver.eve` and change the
convention?
**Answer:** yes, the convetion is the file name do not use "-" use underscore we need to rename the files.
Status: done → D-018 (files renamed)

### SYN-15 Parentheses after a driver name
`driver a01_driver()` has `()`; `demo/hello_world.eve` has `driver hello:`. Are `()` required
when a driver takes no parameters? No () are not required but we replace : with jeyword is, so paranthesis are not required but keyword "is" will be required. Same convention for memthods and functions. 
**Answer:** _(open)_
Status: done → D-015

### SYN-16 `#` versus `##`, and `**` at column 0
What is the difference between `#` and `##` (title and subtitle)? Many files have `**` at the
start of a line without indentation (for example the `*****` banner in test a01, and
`** main process` right under `process`). Is `**` allowed at column 0? 
**Answer:** No, a script must start with a title or subtitle #! is for she bang, ## is for subtitle and # is for title if the file is not a script but a driver program. Notice if a script is not a driver, it can hold just ececution statements and do not need a process statement. It can be a free script only if it start with #! It is a sequential script that may execute some expressions and some operations sequential.
Status: answered → D-014, follow-up SYN-21

### SYN-17 `(* ... *)` and the vararg `*`
`*` is the vararg prefix in parameter lists, so `f(*args)` starts with `(*`. How does the lexer
tell `(*args)` from an expression comment `(* note *)`? Options: require a space, `(* ` ; or use
another pair. May `(* *)` span lines?
**Answer:** You are right, if we do not have a special symbol for expression comments then we need nested `/* ... */` block comments and I do not want nested block comments so we need to replace `(* ... *)` with `(** ... **)`, user must remove both stars to get the comments, and is also bold by MD spec. Yes, expression comments can span multiple lines.
Status: done → D-014

### SYN-18 Remaining box comments
Six files still have `+- -+` box comments: `demo/assign_demo.eve`, `demo/comment_demo.eve`,
`demo/fibonacci.eve`, `demo/syntax_elements.eve`, `pattern/declaration.eve`,
`test/level1/a02-comments.eve` (plus boxes in tutorial examples). Convert them to `/* ... */`, or
to `#` lines?
**Answer:** Replace globar using ed tool +- with /* and -+ with */ users are accustom with this notation in all languages. We only deviate from // to `**` to match MD convention.
Status: done → D-014 (6 .eve files, 6 boxes in syntax/topology examples)

### SYN-19 The `!` sigil
Where does `!` go for unsafe operations: before a name (`!name`), after it (`name!()`), or
before a statement? What makes an operation unsafe (raw memory, system calls, unchecked
conversion)? Is it an identifier sigil like `$` (part of the name) or a prefix? 
**Answer:** name!() will be easy to explain. It can be a function or a method that can raise exceptions or have a secondary effect or unsafe effect like modify a global variable or breack the rules in some way to bypass the safety checks.
Status: answered → D-017

### SYN-20 Escape sequences (proposal)
You asked for a complete list. Proposal for double-quoted strings, to confirm or edit:

| Escape | Meaning |
|---|---|
| `\` | backslash |
| `\"` | double quote |
| `\'` | single quote (also inside `'...'`) |
| `\{` `\}` | literal braces in string patterns |
| `\n` | line feed (LF) |
| `\r` | carriage return (CR) |
| `\t` | horizontal tab |
| `\0` | NUL character |
| `\xHH` | byte / code point 00..FF, two hex digits |
| `\u{H…}` | Unicode code point, 1 to 6 hex digits (`\u{3B2}` = β) |

Any other `\` + character is a lexical error. This replaces the `&code;` escapes (collections.html)
and `\LF`, `\CRLF` (library.html). Single-quoted symbols accept the same escapes. Triple-quoted
text `"""…"""` accepts no escapes (raw), so HTML, CSV and regex text can be pasted as is.
**Answer:** Sounds good
Status: answered → D-019

### SYN-21 `**` at column 0
SYN-16: a file starts with `#!`, `#` or `##`. Many examples also put `**` at column 0, e.g. a
comment line between regions (`** define global states` before `global`), or a banner of stars.
Is `**` allowed at column 0 after the first line, or must it be indented (then these become `##`)?
**Answer:** Yes ** can be used in any position including first line. For example a program can start with a row of ***** and a block comment.
Status: answered → D-019

### SYN-22 `print` call syntax
SYN-07: `print` is a method; arguments map to parameters, by position or by name (`x = expr`),
and optional parameters go in a second parameter set: `print (arguments) option (separator = ".")`.
Is `option` a keyword? Are these all valid: `print "x";`, `print ("a", v);`, `print("a");`,
`print;` (new line only)? Is the second set only for `print` and `write`, or for any method?
**Answer:** option is a new keyword that assign by name optional parameters defined as a second set of parameters for any method. methid name(*vararc) option (params). 
Status: answered → D-019

### SYN-23 Identifier length and case
SYN-08 is answered for `_`, `.`, `$`. Still open: is 30 characters a hard limit? Are names
case-sensitive (`Point` and `point` two names)?
**Answer:** Yes case sensitive, let's use 42 characters for identifiers.
Status: answered → D-019

### SYN-24 Operator precedence
SYN-10 settled `<<`, `>>`, `->`, `<-`. For `operators.json` and the precedence table (SYN-I3):
types.html gives `{not, and, or, xor}` and "relation operators have higher precedence than
logic operators". Proposal, highest first: `.` `()` `[]` · unary `-` `not` · `^` (right) ·
`*` `/` `%` · `+` `-` · `..` · `<<` `>>` · `&&` · `||` · `==` `<>` `<` `>` `<=` `>=` `~` `is` `in`
`eq` · `and` · `xor` · `or` · `if … else` (ternary). Accept or correct?
**Answer:** sounds good we can modify later.
Status: answered → D-019

## Fixes (applied unless you write "no")

### SYN-F1 HTML errors
Duplicate `<tr>` at line 1020 (why `bee-ed balance` fails); `<pre class="fixed">…</code></pre>`
at line 909 closes a `<code>` never opened.
**Answer:** _(open)_
Status: done (syntax.html now passes bee-ed balance)

### SYN-F2 Wrong content
Regions table lists `initialize` twice. Example "Assign: by value" starts with
`// making a clone` (not an Eve comment). "logic OR (}} = union)" should be `||`. Fragment
comment "create and initialize a,y,z" should be `x,y,z`.
**Answer:** _(open)_
Status: done (duplicate initialize removed, // → **, || fixed, x,y,z)

### SYN-F3 Typos
simbol, alredy, staticly, paranthesis, declarstive, semicolumn, thes, enaugh, anu, begging,
Iput, Reminder (remainder), breackpoint, intrerupt, "Eve us ASCII", "tem", "a another".
**Answer:** _(open)_
Status: done (page rewritten)

### SYN-F4 Authoring standard
Drop promotional or off-topic sentences: "We believe you'll find Eve enjoyable to learn",
"Computer was invented in England during WW2", "a modern hybrid language", and the GitHub-drift
disclaimer inside "Globals example".
**Answer:** _(open)_
Status: done

## Improvements (applied only if you write "yes")

### SYN-I1 Lexical rules first
Order the page: source text, comments, identifiers, literals, operators, then statements and
regions. Comments are described in three places today.
**Answer:** Yes consolidate and reorder for a logic introduction and consistency.
Status: done: lexical rules first (source text, comments, identifiers, delimiters, operators), then keywords, declarations, expressions, statements

### SYN-I2 One comments table
Columns: form, where it may start, spans lines, nests, example.
**Answer:** yes
Status: done: #comment-forms

### SYN-I3 Operator precedence table
Depends on SYN-10.
**Answer:** yes
Status: done: #precedence (D-019)

### SYN-I4 Pitfalls section
`is` is always false on native values (use `==`); `:=` shares a reference for objects (use `::`
to copy); `**` starts a comment, so power is `^`.
**Answer:** yes
Status: done: #pitfalls

### SYN-I5 Section id
`operator-keyboard` should be `operator-keywords` (update sidebar JSON and links).
**Answer:** yes
Status: done: #operator-keywords; sidebar data/syntax.json regenerated (single root)

## Specification questions (before writing `spec/`)

The page is done (2026-09-28). These answers decide how the lexical part of the spec is written:
`spec/lexical/lexical.md`, `keywords.json`, `operators.json`, `delimiters.json` (plan S2.2–S2.6).

### SPEC-01 Active or reserved keywords
The table has 123 words. Many belong to database or later features (`alter`, `analyze`, `ascend`,
`cursor`, `fetch`, `commit`, `rollback`, `select`, `insert`, `limit`, `offset`, `trial`, …).
`keywords.json` gives each word a `status`: `stable` (used in 0.1) or `reserved` (not usable as a
name, no meaning yet). Proposal: control, declaration, region and operator words are `stable`;
database and unused words are `reserved`. Agree, or mark words yourself?
**Answer:** Agree
Status: open

### SPEC-02 Contextual keywords
`option`, `to`, `one`, `all`, `any`, `other`, `error` have a meaning only inside certain statements.
Are they reserved everywhere (never a variable name), or contextual (usable as names elsewhere)?
Contextual words make a lexer simpler for users but a parser harder. (Q-002)
**Answer:** everywhere reserved
Status: open

### SPEC-03 Free scripts
A file starting with `#!` holds sequential statements without `driver` or `process`. May it also
declare globals, functions and classes? Does it end with `return;`, or at the end of the file?
**Answer:** this kind of script end at end of file, no return the return belong to process, method, function. This kind of script do not have functions or methids but it can have control statements, like loops and if statements but no jobs. Jobs are only in processes.
Status: open

### SPEC-04 String interpolation
The page now says `"…{name}…"` inserts a value in every double-quoted string, and `\{` writes a
literal brace. Other pages use `?` with `#` placeholders (`"#s" ? x`). For the lexer: is `{…}` in a
string always interpolation (so the lexer must split the string), and may `{…}` hold an expression
or only a name? (TYP-15, COL-16)
**Answer:** {} can hold one variable name, no expressions.
Status: open

### SPEC-05 Indentation
TOP-01: is indentation checked (an error when wrong) or a style rule? The lexer needs this now:
significant indentation adds INDENT/DEDENT tokens.
**Answer:** Yes indentation is mandatory and is done with 2 spaces not with tabs.
Status: open

### SPEC-06 Spec license
MAN-01: the manifest sets CC BY-ND 4.0 for the specification, with an implementation grant.
`spec/index.md` needs it. Confirm (this closes Q-006)?
**Answer:** Yes the license is establish in tutorial, each compiler has it's own license but it can't change the specification without contribution to Sage-Code specification.
Status: open

## Spec additions once answered

- `spec/lexical/lexical.md`: comments (SYN-03, 04, 16, 17), identifiers (SYN-02, 08), strings
  (SYN-12), sigils (SYN-19).
- `spec/lexical/operators.json`: SYN-05, SYN-10.
- `spec/syntax/regions.md`: `driver`, `process` (SYN-01, 02, 15), block closers (SYN-11).
