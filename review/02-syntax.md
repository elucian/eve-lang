# 02 Syntax and lexical design (`RSY`)

## Advantages

**RSY-A01 Explicit, keyword-led blocks.** `if c do … done;`, `for x in r do … done;`, `while c do … done;`, labels and `done label;` (D-034) read well and are easy to parse with one token of lookahead. Good for teaching parsers.

**RSY-A02 Exclusive-range operators.** `a..b`, `a..<b`, `a>..b`, `a>..<b` (D-022) are precise and avoid the off-by-one ambiguity of Python's `range`. The step as a postfix `(a..b)(s)` is unusual but consistent.

**RSY-A03 One comment for code, one for documentation.** `**` to end of line and `#`/`##` at column 0 for titles make files self-describing and feed `eved` (D-053). Dropping `--` and box comments (D-011, D-014) was right.

**RSY-A04 `<>` for not-equal, `!` for effects.** Freeing `!` from negation (D-013) and using `not`, `and`, `or` words is readable and avoids `!=`/`!` confusion.

**RSY-A05 Interpolation with explicit kind.** `\s{}`, `\#{}`, `\b{}` (D-060) make the conversion visible, which helps ETL reports where the format matters.

## Disadvantages

**RSY-D01 Three closers plus mandatory indentation.** `done [label];` for blocks, `return;` for subprograms and processes, `end name;` for class/module/driver (D-037), and also 2-space indentation that is an error otherwise (D-031, D-041). The structure is stated twice; a mismatch between the two has to be reported, and the student has to learn both.

**todo** nothing, just notice now we have "do ... repeat" another way to close a block. The block closing keyword must be aligned with the opening keyword. And indentation is mandatory because my experience with python and ada/pascal and pl/sql tell me programmers are messy, and missaligning the code in python injected real bugs in production. EVE must be strict. This is a feature not a bug.

**RSY-D02 Sigils carry too many meanings.** *Applied 2026-10-05: D-079.*

| Sigil | Meanings today |
|---|---|
| `$` | system variable (`$error`), environment variable (`$HOME`), error constants (`$err_io`), exception type code (`$Type`) |
| `@` | by-reference parameter, result name (`=> (@y)`), `@self`, reference argument at the call |
| `:` | type annotation, pair (`k: v`), label (`name: job`), named argument, format separator in `\#{e:f8.2}`, `{:}` empty map |
| `!` | function with side effects (`f!()`), unsafe call, part of `!~` |
| `+>` | pipe in `call` (command.html), prepend (Q-017) |
| `is` | header terminator, type test, identity test, type comparison (D-032, D-063) |

Q-015 (where an interpolated expression ends) and Q-016 b (`name!~x`) are direct consequences.

**todo** drop !~  use not( x ~ /regex/ ) instead. Improve the /tutorial
Decision: We use instead of $, sys. assuming we will implement sys that is a system module. env. that is an environment module. @ is fine @self and @y have same minning in your example, represent reference. +> has same meaning, append something to something. "is" is an english word with different meanings in english so we can support different meanings in Eve.

**RSY-D03 Three assignment operators plus four declarators.** *Applied 2026-10-05: D-079.* `=` (expression, no inference, chains), `:=` (statement, inference), `::` (deep clone) and `let`, `set`, `def`, `new` (D-017, D-036, D-049). In parameters `=` means "default with explicit type" and `:=` "default by expression" (D-070). The same symbol has a different meaning in a declaration, a statement and a parameter list. 

**todo** You are right. "=" should do type inference same as :=, except that := will also expect an expression at the right side while "=" will expect a data literal. Is a trick to make execution faster. If "=" is follwed by an expression is worng and compiler should create a compilation warnings and convert = into := internally. Let's give some slack to user. 

**RSY-D04 1-based indexing with an end anchor.** Defensible for beginners, but every data format Eve will read (JSON arrays, CSV columns in most tools, SQL `OFFSET`, byte buffers, WASM memory) is 0-based. Each boundary needs a `+1`/`-1`, which is where ETL bugs live.

**todo** Nothing. We will have our own Json parser not depend on libraries too much. Eve is an engineering ETL. We know Computer Science has made a wrong decision and count from 0 that is not even a number. We count engineering style.

**RSY-D05 Statement-level `if` suffix and `repeat N times if`.** *Applied 2026-10-05: D-079.* `x.next() if not x.done;`, `repeat [label] [N times] [if c];` (D-045) add a second conditional grammar. `N times` counts "consecutive repeats of the same cycle", a rule no reader will guess (and D-045 itself leaves it open).

**todo** feature is dropped. Remove from examples and text.

## Antipatterns

**RSY-X01 Assignment is an expression (`=` returns its value and chains).** *Applied 2026-10-05: D-079.* D-017. This is the C mistake that `if (a = b)` made famous. Eve uses `==` for equality, so the confusion is one character away. It also forces the parser to handle `a = b = 5 : Integer`, where the type annotation binds… to what?

**todo** drop feature. Instead we use: new (a, b, c) = 5:Integer; or new (a, b, c) = 1; (new feature, = allow type inference)

**RSY-X02 Overloaded words with context-dependent meaning.** `resume` (recover action, and earlier coroutine), `repeat` (closer, then removed, then a jump), `start` (aspect, earlier async method), `is` (four meanings). Reusing a word after it was removed with another meaning (D-045 reuses `repeat`) breaks every reader who learned the old one.

**todo** nothing, we solved this problem by creating a back_log. We will clean the mistakes one by one.

**RSY-X03 Formatting mini-language inside strings borrowed from Fortran.** `\#{m:3i4}`, `fW.D`, repeat counts. Fortran edit descriptors are not known by the target audience (Python, JS, SQL users), and D-060 marks it as "proposed by the model".

**todo** Nothing, we use the best conventions, regardless if they are invented in Fortran or Python. We cound on new generation of developers who will use AI to generate EVE code. At first, developers need to learn this minilanguage but when AI is trained to do it, user will describe before learning.

**RSY-X04 Reserved words for undesigned features.** See `RPJ-X04`.

## Recommendations

**RSY-R01 One block story.** Option A (recommended for a data DSL): keep keywords and closers, drop the indentation *error* (make it a formatter rule, `eve fmt`). Option B: significant indentation, drop `done`/`end`. Either halves the rules. If closers stay, merge `end name;` and `return;` for declarations: `end` closes every declaration (driver, aspect, module, class, method, function, process), `done` closes every statement block, and `return` becomes only a statement that leaves a subprogram early.

**todo** Proposal rejected. return <expression>; is not in design. yield <expression> is in design. return is an imperative statement that end an executable block. process, method, function. "end" is used to end a declaration container. done or repeat the "do" block. I think this is readable and resonable.

**RSY-R02 One meaning per sigil.**

| Sigil | Proposal |
|---|---|
| `$` | system and environment only (`$error`, `$env.HOME`); error codes become `Error.io` constants of a module |
| last index | keyword `last` (`a[last]`, `a[last - 1]`), or 0-based with negative indexes |
| `@` | by reference only; `self` becomes a plain parameter name, result names lose `@` |
| `:` | type and pair; labels written `label name:`… or `job name is` |
| format | after `|` or `%` inside `{}`: `"{price % 10.2f}"` |

**todo** partial agree. 
$ already discussed  {env, err, sys} become linraries in EVE that expose constants. Eve constants can start with lowercase letters, we do not enforce in compiler a rule
@self is a reference to the object is there for consistency. Result is an output parameter it must show @ that is the secret of explicit declaration of result. With : in format I agree. Let's use % instead.


**RSY-R03 Assignment as a statement only; two declarators.** *Rejected 2026-10-04: the author keeps `new` (declare) and `let` (execute), D-076.* `let x = e` (immutable binding, inferred), `var x = e` (mutable), `x = e` mutation statement, `copy(x)` or `x.clone()` for deep copy. If `:=` must stay for the community's taste, keep exactly: `let x := e` declare, `x := e` mutate, no `=` assignment at all, `::` only as clone.

**answer** Rejected proposal. let means "rulling, allow, make" the bias of "let" create immutables is not real, just learned. The real "set" is creating immutable variables in Eve, already established. var, is an invented word, does not exist in English, we use English words. "new" is very clear it will create a new object or variable. We keep {=} a light weight assign for data literals and := or :: two heavy assignments for expressions/cloning. We use == for boolean expression. I think will work.

**RSY-R04 Interpolation: one form, Python/Rust-style format spec.** `"{expr}"` with `\{` escape, `"{x:>10.2}"` format. Keep `\s{}`/`\#{}` only if the kind matters to the type checker; otherwise the type of `expr` already says it.

**answer** We escape "\{}" with \s \# for type checking.

**RSY-R05 Decide 0-based vs 1-based by data boundaries, not by beginners.** For an ETL/web language, 0-based plus `a[-1]` for the last element is the common ground of JSON, JavaScript, SQL drivers and WASM. If 1-based stays, the standard library must convert at every boundary and say so in each API.

**answer** A price we must pay for wrong engineering done before us. I want to give suveranity back to users. Comprehensive design and truth over biast. The zer based index was invented to improve performance, not it back-fire. 

**RSY-R06 A formatter and a linter, not lexical errors, for style.** Column rules for `#`, 2-space indentation, identifier length 42 (D-019) belong in `eve fmt` / `eve lint`. Lexical errors should be reserved for ambiguity.

**rejected** User must learn to write correct code. Is a bad habit to change user's code with tools. User must change every line of code by hand or use proper tools to generate correct code.
