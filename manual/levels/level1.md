<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Level 1: The language of a single script

A script that runs from its first line to its last, with no user subprograms and no classes. It has declarations and assignment, expressions and operators, control flow, strings with interpolation, the primitive types and the collections, and jobs with error recovery. This level is the core of the lexical and syntactic specification, the first lexer and parser, and the tree-walking interpreter, which stay the reference for the bytecode machine.

| Code | Feature | Stage |
|---|---|---|
| [`F-LIB-01`](#f-lib-01-console-io) | Console I/O | drafted |
| [`F-LIB-02`](#f-lib-02-exception-module) | Exception module | drafted |
| [`F-LIB-13`](#f-lib-13-datamap-methods) | DataMap methods | validated |
| [`F-LNG-01`](#f-lng-01-script-shapes) | Script shapes | validated |
| [`F-LNG-02`](#f-lng-02-declarations-and-assignment) | Declarations and assignment | validated |
| [`F-LNG-03`](#f-lng-03-expressions-and-operators) | Expressions and operators | validated |
| [`F-LNG-04`](#f-lng-04-control-flow) | Control flow | validated |
| [`F-LNG-05`](#f-lng-05-jobs-and-error-recovery) | Jobs and error recovery | validated |
| [`F-LNG-06`](#f-lng-06-primitive-types) | Primitive types | validated |
| [`F-LNG-07`](#f-lng-07-collections) | Collections | validated |
| [`F-LNG-08`](#f-lng-08-strings-and-interpolation) | Strings and interpolation | validated |
| [`F-SPEC-01`](#f-spec-01-lexical-specification) | Lexical specification | validated |
| [`F-SPEC-02`](#f-spec-02-grammar-ebnf) | Grammar (EBNF) | validated |
| [`F-SPEC-03`](#f-spec-03-core-semantics) | Core semantics | drafted |
| [`F-STR-05`](#f-str-05-command-line-parameters-of-a-script) | Command-line parameters of a script | drafted |
| [`F-STR-07`](#f-str-07-system-variables) | System variables | drafted |
| [`F-STR-12`](#f-str-12-exit-code-of-the-program) | Exit code of the program | validated |
| [`F-VM-01`](#f-vm-01-lexer-and-parser) | Lexer and parser | validated |
| [`F-VM-02`](#f-vm-02-tree-walking-interpreter) | Tree-walking interpreter | validated |

## F-LIB-01 Console I/O

Stage: **drafted**.

`print`, `write`, `read`, `error`, `warning`, `log_err`, `log_wrn`.

*Partial:* `print`, `write`, `log_err` and `log_wrn` (run log), `error` and `warning` (standard error) work; `read` is missing; `io.eve` is a draft.

An example that runs, and what it prints:

```eve
# print writes a string and a new line; no import is needed
primary aspect a03_print is
  process main is
    print "Hello World!";
    print("Hello again!");
  return;
end a03_print;
```

```text
Hello World!
Hello again!
```

## F-LIB-02 Exception module

Stage: **drafted**.

`Error`, `Warning`, `raise`, `expect`, `assert`, `warn`, code constants.

*Partial:* `raise`, `expect`, `assert` and the `$err_` constants are in the interpreter; `exception.eve` is a draft that is not loaded.

## F-LIB-13 DataMap methods

Stage: **validated**.

`has`, `get(k)`, `get(k, default)`, `keys`, `values`, `delete`. `method` is a contextual word, usable as a name.

An example that runs, and what it prints:

```eve
# DataMap methods: has, get, keys, values, delete (G-5)
primary aspect a88_datamap_methods is
  process main is
    new m:= {"b": 2, "a": 1};
    print m.has("a");
    print m.has("z");
    print m.keys;
    print m.values;
    print m.get("b");
    print m.get("z", 0);
    print m.get("z");
    m.delete("a");
    print m.count;
    print m.keys;
    for k in m.keys do
      print "{k}={m[k]}";
    done;
  return;
end a88_datamap_methods;
```

```text
True
False
("a","b")
(1,2)
2
0
null
1
("b")
b=2
```

## F-LNG-01 Script shapes

Stage: **validated**.

Aspect with `process main`, title/subtitle header, comments; no free script and no `#!`.

An example that runs, and what it prints:

```eve
# print writes a string and a new line; no import is needed
primary aspect a03_print is
  process main is
    print "Hello World!";
    print("Hello again!");
  return;
end a03_print;
```

```text
Hello World!
Hello again!
```

## F-LNG-02 Declarations and assignment

Stage: **validated**.

`let`, `set`, `:=`, `=`, `::` clone, views.

An example that runs, and what it prints:

```eve
# let changes names and creates the ones that are missing, by type inference
primary aspect a43_let_creates_name is
  process main is
    new lst:= (1, 2, 3);
    let lst -> e;                ** e does not exist: let creates it with the last element
    expect e == 3;
    expect lst == (1, 2);
    let lst -> new f;            ** the explicit form
    expect f == 2;
    print e, f;
  return;
end a43_let_creates_name;
```

```text
3,2
```

## F-LNG-03 Expressions and operators

Stage: **validated**.

Arithmetic, logic, comparison, ranges, membership, precedence.

An example that runs, and what it prints:

```eve
# numeric operators and their precedence
primary aspect a07_arithmetic is
  process main is
    expect 1 + 2 == 3;
    expect 7 - 10 == -3;
    expect 6 * 7 == 42;
    expect 17 % 5 == 2;
    expect 2 ^ 10 == 1024;

    ** the division returns a Real
    expect 7 / 2 == 3.5;
    expect 9 / 3 == 3;
    expect type(9 / 3) is Real;
    expect type(2 + 3) is Integer;
    expect type(2 + 0.5) is Real;

    ** precedence: ^ then * / % then + -
    expect 2 + 3 * 4 == 14;
    expect (2 + 3) * 4 == 20;
    expect 1 + 2 * 3 ^ 2 == 19;
    expect 10 - 4 - 3 == 3;      ** left to right
    expect 2 ^ 3 ^ 2 == 512;     ** the power goes right to left
    expect -3 + 5 == 2;

    ** the unary minus applies before ^; with a term on its left - is the subtraction
    expect -2 ^ 2 == 4;
    expect 4 - 2 ^ 2 == 0;
    expect 4 - -2 ^ 2 == 0;
    expect -(2 ^ 2) == -4;
    print 7 / 2;
    print 2 ^ 10;
  return;
end a07_arithmetic;
```

```text
3.5
1024
```

## F-LNG-04 Control flow

Stage: **validated**.

`if`, `match`, `while`, `for`, `loop … repeat [while c]`, labels, `break`, `skip`.

An example that runs, and what it prints:

```eve
# if, else if, else and the conditional statement
primary aspect a12_if is
  process main is
    new n:= 7;
    if n < 5 do
      print "small";
    else if n < 10 do
      print "medium";
    else
      print "large";
    done;

    ** an if opens no scope and can be nested
    if n > 0 do
      if n % 2 == 0 do
        print "positive even";
      else
        print "positive odd";
      done;
      new inside:= 1;
    done;
    expect inside == 1;          ** the branch created it in the parent scope

    print "n is odd" if (n % 2 <> 0);
    print "n is even" if (n % 2 == 0);
    new size:= ("big" if n > 5 else "small");
    print size;
  return;
end a12_if;
```

```text
medium
positive odd
n is odd
big
```

## F-LNG-05 Jobs and error recovery

Stage: **validated**.

Jobs, `recover` with `retry`/`resume`/`abort`, `finalize`, `raise`, `expect`, `over`, `panic`, exit codes.

An example that runs, and what it prints:

```eve
# over ends the process it is in with exit code 0
primary aspect a30_over is
  process main is
    print "start";
    over;
    print "never";
  return;
end a30_over;
```

```text
start
```

## F-LNG-06 Primitive types

Stage: **validated**.

Integer, Natural, Real, Logic, Symbol, String, ordinals, type checks with `is`. *Rational, Duration, Time, Date not yet.*

An example that runs, and what it prints:

```eve
# numeric operators and their precedence
primary aspect a07_arithmetic is
  process main is
    expect 1 + 2 == 3;
    expect 7 - 10 == -3;
    expect 6 * 7 == 42;
    expect 17 % 5 == 2;
    expect 2 ^ 10 == 1024;

    ** the division returns a Real
    expect 7 / 2 == 3.5;
    expect 9 / 3 == 3;
    expect type(9 / 3) is Real;
    expect type(2 + 3) is Integer;
    expect type(2 + 0.5) is Real;

    ** precedence: ^ then * / % then + -
    expect 2 + 3 * 4 == 14;
    expect (2 + 3) * 4 == 20;
    expect 1 + 2 * 3 ^ 2 == 19;
    expect 10 - 4 - 3 == 3;      ** left to right
    expect 2 ^ 3 ^ 2 == 512;     ** the power goes right to left
    expect -3 + 5 == 2;

    ** the unary minus applies before ^; with a term on its left - is the subtraction
    expect -2 ^ 2 == 4;
    expect 4 - 2 ^ 2 == 0;
    expect 4 - -2 ^ 2 == 0;
    expect -(2 ^ 2) == -4;
    print 7 / 2;
    print 2 ^ 10;
  return;
end a07_arithmetic;
```

```text
3.5
1024
```

## F-LNG-07 Collections

Stage: **validated**.

List, Array, Matrix, DataSet, HashMap, Object, slices, builders, deconstruction.

An example that runs, and what it prints:

```eve
# DataSet: sorted unique values, union, intersection, difference
primary aspect a20_dataset is
  process main is
    new a:= {3, 1, 2, 3};
    expect a == {1, 2, 3};       ** no duplicates
    expect 2 in a;
    expect 5 not in a;

    expect ({1, 2, 3} || {3, 4}) == {1, 2, 3, 4};
    expect ({1, 2, 3} && {2, 3, 4}) == {2, 3};
    expect ({1, 2, 3, 4} - {3, 4, 5}) == {1, 2};

    let a += {9};
    expect a == {1, 2, 3, 9};
    let a -= {1, 9};
    expect a == {2, 3};
    let a:= {};
    expect a == {};

    ** a list gives a DataSet
    expect ({} || (1, 2, 1, 2, 3)) == {1, 2, 3};
    expect ((1, 2, 3, 4) && (2, 3, 4, 5)) == {2, 3, 4};

    ** a builder
    expect {x * x | x in (2..6)} == {4, 9, 16, 25, 36};

    ** a DataSet prints in order
    new s:= {3, 1, 2};
    print s;
  return;
end a20_dataset;
```

```text
{1,2,3}
```

## F-LNG-08 Strings and interpolation

Stage: **validated**.

Escapes, text literal `"""`, placeholders `{name}`, `{literal}`, simple expressions and formats `{n % i5}`, code points `{U+H}`, HTML entities `&name;`, regular expressions (subset).

An example that runs, and what it prints:

```eve
# a text literal is raw and keeps the line breaks; the indentation of the closing quotes is removed
primary aspect a27_text_literal is
  process main is
    new text:= """
    "Opportunity is missed by most people
    because it is dressed in overalls
    and looks like work."
    """;
    expect type(text) is Text;
    print text;
  return;
end a27_text_literal;
```

```text
"Opportunity is missed by most people
because it is dressed in overalls
and looks like work."
```

## F-SPEC-01 Lexical specification

Stage: **validated**.

Tokens, comments, literals, escapes, placeholders, keywords, operators, delimiters as Markdown + JSON (`keywords.json`; code points `{U+H}`; checked by).

## F-SPEC-02 Grammar (EBNF)

Stage: **validated**.

Declarations, statements, expressions, modules and imports, checked against every `.eve` test by (199 of 199 files of levels 1 to 4 and the smoke test).

## F-SPEC-03 Core semantics

Stage: **drafted**.

Types, scopes, control flow, jobs and `recover`, topology, collections and objects.

*Partial:* `semantics/` has variables, types, control, errors, aspects, modules and data-types (a proposal); scopes, topology and collections are missing.

## F-STR-05 Command-line parameters of a script

Stage: **drafted**.

`-p`/`--param` mapped to `main` parameters, `eve script.eve -h` from `** @param` comments.

*Partial:* the arguments after the script name go to `process main`; `-p` and the generated help are not implemented.

## F-STR-07 System variables

Stage: **drafted**.

The register (`$error`, environment names such as `$HOME`, `$epsilon`, `$err_`/`$wrn_` constants).

*Partial:* `$error`, `$epsilon`, `$OS_PWD`, the `$err_`/`$wrn_` constants and every environment name `$NAME` (a String, read when used) work; `$EVE_*` are undefined.

An example that runs, and what it prints:

```eve
# a primary aspect can set a system variable and define its own $name
primary aspect a77_system_variable is
  set $epsilon = 0.5;
  set $mine = 7;

  process main is
    expect 1.0 =~ 1.3;           ** within $epsilon
    expect not (1.0 =~ 2.0);
    expect $mine == 7;
    expect $epsilon == 0.5;
    print $mine;
  return;
end a77_system_variable;
```

```text
7
```

## F-STR-12 Exit code of the program

Stage: **validated**.

`over n;` and `exit n;` give the exit code: 0, or 6 to 125 (1 to 5 belong to the machine); anything else is `$err_argument`.

An example that runs, and what it prints:

```eve
# exit ends the process without error and runs finalize
primary aspect a50_exit is
  process main is
    print "work";
    exit;
    print "never";
  finalize
    print "finalize";
  return;
end a50_exit;
```

```text
work
finalize
```

## F-VM-01 Lexer and parser

Stage: **validated**.

Source to syntax tree, errors with file, line and column (`lexer.zig`, `parser.zig`).

## F-VM-02 Tree-walking interpreter

Stage: **validated**.

Runs levels 1 to 3, the smoke test and the benchmarks (`interp.zig`, `project.zig`); 193 tests.
