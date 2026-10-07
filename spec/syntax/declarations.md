# Declarations

Status: **0.1-draft**, level 1. Grammar: [`grammar.md`](grammar.md). Each rule names the decision it comes from (`D-nnn`, in `plan/decision_level1.md`).

## Scripts

A script is a file. Its first line decides its kind (lexical.md, File header):

- `#!…` is a **free script**: sequential statements, no `driver`, no `process`, no `return`, no subprograms, no jobs. It ends at the end of the file. A free script has one scope (D-014, D-091).
- A **driver** is `driver name is` … `end name;`. It can be run. A driver has one process, `main`, the entry point (D-037).
- An **aspect** and a **module** are scripts of level 2; they use the same header and closer.

A driver, aspect or module has **one scope** (D-041). The regions `import`, `alias`, `constant`, `global` and `globals` do not exist: everything is declared directly, in any order, indented by 2 spaces. `end name;` repeats the name of the header and is at column 1.

### Headers

A declaration header ends with the keyword `is` (D-015): `driver name is`, `process main is`, `function f(x: Integer) => (@r: Integer) is`. The `()` after a name is optional when there are no parameters. The body is indented by 2 spaces more than its header.

### Process

`process main is` … `return;` is the executable part of a driver. A process takes parameters (`process main(*args) is`); the parameters belong to the process, not to the driver (D-040). A process has no result: its outputs are `@` parameters (D-038). It can end with a `recover` region and a `finalize` region, aligned with `process`, before `return;` (see `../semantics/errors.md`). A process has access to the variables of its script.

## Variables and constants

Every declaration starts with a keyword (D-076):

| Keyword | Creates | Example |
|---|---|---|
| `new` | a variable or an object attribute | `new x := 0;` `new x = 0 :Integer;` `new copy :: original;` `new self.x := v;` |
| `set` | a constant, global to its script | `set limit = 10 :Integer;` `set (x, y, z) = 2;` |
| `def` | an alias of a name | `def Num = Integer;` |

- `=` is the **light assignment** for an initial value from a literal; the type is the type of the literal, or the type after `:`. `:=` evaluates an expression and infers the type. `=` followed by an expression that is not a literal gives a warning and is read as `:=` (D-079). `=` is not an expression and does not chain.
- The type hint comes **after** the value: `new a = 0 :Integer;`, never `new a :Integer = 0;` (D-032). Without a value a variable gets the zero value of its type (`0`, `0.0`, `""`, an empty collection), never `null` (D-080): `new n :Integer;`. A variable that may hold `null` has an optional type: `new age :Integer?;`.
- Several variables: `new a = 1, b = 2 :Integer;` is the same as `new (a = 1, b = 2) :Integer;`; one value for all: `new (a, b, c) = 5 :Integer;`; one value each: `new (a, b) = (1, 2);` (D-079).
- `::` makes a deep copy, `:=` shares the reference of an object or a collection and copies a native value (D-049). A slice by `:=` is a view; by `::` a copy.
- Redeclaring a name in the same scope is an error. Reading a name that is not declared is an error; a `let` capture creates a missing name (Q-017, Q-033e, see statements.md).
- `set` is allowed only at script level, not inside a process or a subprogram. A constant is never changed.

## Types

Every user type is declared with `class`, and `<:` names its superclass, which is mandatory (Q-029). There is no `type` keyword: `type(x)` is a library function that returns the type of a value, and `x is Integer` tests it. A range type derives from `Range`, a function type (a signature, used to check callbacks at compile time, Q-026) from `Function`, an ordinal from `Ordinal`:

```eve
class Small = (0..1)(0.1) <: Range;
class BinEx = (p1, p2: Integer): Integer <: Function;
class Color = {Red, Green, Blue} <: Ordinal;
class Level = {Low:10, High} <: Ordinal;
```

An ordinal type lists its values; the first value is 1 unless a value is given (`{Red, Green}` is `{Red:1, Green:2}`; `Low:10`, then `High` is 11); `Logic` is `{False:0, True}`. In a class declaration `{Red, Green}` declares ordinal values, an exception to the rule that a brace literal of plain values is a DataSet; `<: Ordinal` is required (Q-033g). When a module exports an ordinal, a script that imports it with `Color(*)` gets its capitalized values as constants of its own scope, reserved there; a name that starts with an upper-case letter enters the enclosing scope, any other name needs the type name (`Shade.dark`) (D-058). Type notations: `[]Integer` (array), `[10]Integer` (fixed size), `{:}(String, Integer)` (DataMap), `{Real | Integer}` (variant), `T?` (optional), `Vector(:Real)` (generic). The types are in `../semantics/types.md`.

## Functions and procedures

A subprogram outside a class is a **function** when it has a result and a **procedure** when it has none, as in Ada (D-100; it replaces the "function without result" of D-086). A function or a procedure belongs to the driver, aspect or module that declares it and is private to it unless a module exports it.

```eve
function area(w, h: Real) => (@a: Real) is
  let a := w * h;
return;
```

| Kind | Declaration | Rule (D-087) |
|---|---|---|
| plain function | `function f(…) => (@r: T) is` | has a result, is deterministic, changes nothing |
| non-deterministic function | `function f!(…) => (@r: T) is` | has a result that can differ for the same arguments (random, time, a closure that counts); every function that creates a closure (D-101) |
| procedure | `procedure p(…) is` | has no result; does work (prints, writes, changes `@` parameters or module state); called as a statement; needs no `!` |

`function` without a result list and `procedure` with one are compile errors. A procedure is called as a statement, with or without parentheses when it has no arguments (`foo;`).

- The result is written `=> (@name: Type)`; `@` makes it a reference; the result variable is assigned in the body; `return;` carries no value (D-036). Several results: `=> (@q: Integer, @r: Integer)`.
- A plain function and a `!` function can not change a global, a module variable or a parameter, and can not call a procedure. A procedure may call any function or procedure.
- Parameters: one list, never two (D-029). `name: Type` is mandatory; `name = value :Type` or `name := expression` is optional with a default (D-070); `*name` collects the rest (vararg); `@name` is an input/output reference and has no default (D-048). Parameters after a vararg are optional and are named at the call.
- Order: mandatory parameters come first and optional parameters follow; a mandatory parameter after an optional one is a compile error (D-105).
- At the call, positional arguments come first; an optional parameter is named with `:` (`greet("Eve", greeting: "Hi")`); an `@` parameter needs `@` on the argument (`swap(@a, @b)`).
- Without `@` an argument is passed by value, collections included (like `::`).
- Functions and procedures do not handle errors: an error propagates to the process (D-028).
- `print`, `write`, `read` are library procedures, called as statements (D-086, D-100).
- A procedure never ends with `!`: it is made for side effects and is never deterministic; `procedure p!()` is a compile error (D-101).
- **No references to procedures** (D-101). A procedure is not a value: it can't be passed as an argument, stored in a variable or returned, and there are no procedure types. A callback is always a function; a function type derives from `Function`: `class BinEx = (p1, p2: Integer): Integer <: Function;`.
- **Closures** (D-101). A closure is a function declared inside a function or a procedure; it is never a procedure. A function that creates a closure always ends with `!` (`function make_counter!(first: Integer) => (@next!: Function)`), even when it could be called deterministic: these higher-order functions are not optimized. A procedure can create several closures and give them out through `@` output parameters (`procedure make_pair(first: Integer, @up!: Function, @down!: Function)`). The enclosed function has the name of the result or output parameter it fills (Q-033d).

## Classes and objects

A class declares the attributes of its signature, its supertype and, between `is` and `end Name;`, its constructor, destructor and methods (D-036, D-037, D-084, D-085):

```eve
class Point = {x, y :Real} <: Object is
  constructor(x = 0, y = 0 :Real) => (@self) is
    let self := Object();
    let self.x := x;
    let self.y := y;
  return;

  public method move(@self, dx, dy :Real) is
    let self.x += dx;
    let self.y += dy;
  return;
end Point;
```

- A class without a body ends its header with `;`. A class with a body closes with `end Name;`.
- **Construction.** A class is called like a function: `new p := Point(1, 2);` (D-076). The constructor result is `@self`, whose type is the class. Its first statement builds the object: `let self := Object();` for a class derived from `Object`, `let self := Superclass(args);` for a subclass. The object is allocated once at the root of the chain. Using `self` before it is built, building it twice, or replacing it is a compile error.
- A class without a constructor is filled by name: `new c := Circle(name: "wheel", radius: 2.5);`.
- **Methods** belong to a class: declared in its body, or outside it as an extension method whose first parameter is `@self` with the class type. A method receives the object as `@self` (no type inside the body). A chainable method has `=> (@self)`.
- **Visibility** is a word in front of the declaration: `public`, `protected` (the class and its subclasses), `private` (the default). The attributes of the signature are public.
- `let self.x := v;` sets an attribute of the signature; `new self.extra := v;`, in a constructor or a method, creates another one, which is private. Code outside the class can not add an attribute: `new p.z := 7;` is an error (Q-031k).
- A destructor is `destructor(@self) is … return;`.
- **Functions in a class.** A class body may declare functions, and its methods may use lambda expressions. The functions are private to the class, can't be exported and are called by the methods of the class without a qualifier. A class can't host procedures: a `procedure` in a class body is a compile error (D-103).
- **Methods are not values** (D-103). There are no references to methods and no method type: a method can't be passed as an argument, stored or returned, and it is never a callback. A lambda that calls the method is passed instead: `shapes.map((s) => (s.area()))`.
- Extension methods are static: they never change the class, can not hide a method of the class, see only its public members, and are visible only in the scripts that declare or import them (D-086).
- Traits, abstract classes, generics and generators belong to version 2 (D-039, D-087).

## Imports and modules (level 2)

`from lib use (a, b);` imports names; `export (a, b);` lists the public members of a module (D-041, D-085). See `decision_level2.md`.
