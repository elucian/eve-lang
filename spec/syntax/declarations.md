# Declarations

Status: **draft**, level 1. Grammar: [`grammar.md`](grammar.md). Each rule names the decision it comes from.

## Scripts

A script is a file. It holds an aspect, or a module, or (level 5) an Eve macro. A file has no `#!` line.

- An **aspect** is `[kind] aspect name is` … `end name;` where `kind` is `exclusive`, `concurrent` or `primary`. Without a kind word it is exclusive. The three kind words are reserved words of the same design. An aspect has a process `main`, its entry point and its only public member, and may have other processes, which are private: only the processes of the same aspect call them, by their bare names. A **module** is a script of level 3; it uses the same header and closer.
  - An **exclusive** aspect is called with `apply`, never with `start`. A command may run it alone, for testing.
  - A **concurrent** aspect is called with `apply` or `start`. It is checked for thread safety. It is called only from a primary or an exclusive aspect: a command does not run it and another concurrent aspect does not call it.
  - A **primary** aspect is designed to be executed first, by a command (`eve file.eve`), and it can run alone. **No aspect applies or starts it**: `apply` or `start` of a primary aspect is a compile error, `a primary aspect is run by a command: it can't be applied or started`. It is serial: its processes are exclusive, applied and never started, but its parallel groups start aspects. A project may hold one or several primary aspects.
- Any aspect may `apply` or `start` another aspect, by its name, with these checks (compile errors, exit 65): no aspect calls itself and no chain of calls comes back to an aspect already in it (`aspect a calls itself`, `a calls b calls a`); the chain of aspects is at most three levels deep, the first being the aspect run by a command; a call of a private process of another aspect, or `a.p` with a dot on an aspect, is not allowed. Only the call of an aspect makes a level, never a call of a private process.
- An **Eve macro** is a file of level 5 that holds shared declarations and several aspects, exactly one of them primary ([below](#eve-macro-level-5)).

An aspect or a module has **one scope**. The regions `import`, `alias`, `constant`, `global` and `globals` do not exist: everything is declared directly, in any order, indented by 2 spaces. `end name;` repeats the name of the header and is at column 1.

The aspect run by a command is the root of the run: its state is the scope of the run, its `main` takes the command-line arguments, and the modules it imports are bound to it. Every other aspect has its own state, created at each call and dropped when its `main` returns. The private processes of an aspect work on the state of that call. A private process that is **started** (in a concurrent aspect) uses only the thread-safe names of its aspect: atomic variables, channels, constants and the functions that the compiler proves thread safe; any other name is a compile error that names it.

### Headers

A declaration header ends with the keyword `is`: `aspect name is`, `process main is`, `function f(x: Integer) => (@r: Integer) is`. The `()` after a name is optional when there are no parameters. The body is indented by 2 spaces more than its header.

### Process

A function, a procedure and a method may end with a `recover` region too, before `return;` (`../semantics/errors.md#recover-in-a-function-procedure-or-method`). `process main is` … `return;` is the executable part of an aspect. A process takes parameters (`process main(*args) is`); the parameters belong to the process, not to the aspect. A process has no result: its outputs are `@` parameters. It can end with a `recover` region and a `finalize` region, aligned with `process`, before `return;` (see `../semantics/errors.md`). A process has access to the variables of its script.

## Variables and constants

Every declaration starts with a keyword:

| Keyword | Creates | Example |
|---|---|---|
| `new` | a variable or an object attribute | `new x := 0;` `new x = 0 :Integer;` `new copy :: original;` `new self.x := v;` |
| `set` | a constant, global to its script | `set limit = 10 :Integer;` `set (x, y, z) = 2;` |
| `def` | an alias of a name | `def Num = Integer;` |

- `=` is the **light assignment** for an initial value from a literal; the type is the type of the literal, or the type after `:`. `:=` evaluates an expression and infers the type. `=` followed by an expression that is not a literal gives a warning and is read as `:=`. `=` is not an expression and does not chain.
- The type hint comes **after** the value: `new a = 0:Integer;`, never `new a:Integer = 0;`. Without a value a variable gets the zero value of its type (`0`, `0.0`, `""`, an empty collection), never `null`: `new n:Integer;`. A variable that may hold `null` has an optional type: `new age:Integer?;`.
- Several variables: `new a = 1, b = 2:Integer;` is the same as `new (a = 1, b = 2):Integer;`; one value for all: `new (a, b, c) = 5:Integer;`; one value each: `new (a, b) = (1, 2);`.
- `::` makes a deep copy, `:=` shares the reference of an object or a collection and copies a native value. A slice by `:=` is a view; by `::` a copy.
- Redeclaring a name in the same scope is an error, except overloaded subprograms (level 5, `#overloading`). Reading a name that is not declared is an error; a `let` capture creates a missing name (see statements.md).
- `set` is allowed only at script level, not inside a process or a subprogram. A constant is never changed.

## Types

Every user type is declared with `class`, and `<:` names its superclass, which is mandatory. There is no `type` keyword: `type(x)` is a library function that returns the type of a value, and `x is Integer` tests it. A range type derives from `Range`, a function type (a signature, used to check callbacks at compile time) from `Function`, an ordinal from `Ordinal`:

```eve
class Small = (0..1)(0.1) <: Range;
class BinEx = (p1, p2: Integer): Integer <: Function;
class Color = {Red, Green, Blue} <: Ordinal;
class Level = {Low:10, High} <: Ordinal;
```

An ordinal type lists its values; the first value is 1 unless a value is given (`{Red, Green}` is `{Red:1, Green:2}`; `Low:10`, then `High` is 11); `Logic` is `{False:0, True}`. In a class declaration `{Red, Green}` declares ordinal values, an exception to the rule that a brace literal of plain values is a DataSet; `<: Ordinal` is required. When a module exports an ordinal, a script that imports it with `Color(*)` gets its capitalized values as constants of its own scope, reserved there; a name that starts with an upper-case letter enters the enclosing scope, any other name needs the type name (`Shade.dark`). Type notations: `[]Integer` (array), `[10]Integer` (fixed size), `{:}(String, Integer)` (DataMap), `{Real | Integer}` (variant), `T?` (optional), `Vector(:Real)` (generic). The types are in `../semantics/types.md`.

## Functions and procedures

A subprogram is a **function** when it has a result and a **procedure** when it has none, as in Ada (it replaces the "function without result" of). A function or a procedure belongs to the aspect or module that declares it and is private to it unless a module exports it.

```eve
function area(w, h: Real) => (@a: Real) is
  let a := w * h;
return;
```

| Kind | Declaration | Rule |
|---|---|---|
| plain function | `function f(…) => (@r: T) is` | has a result, is deterministic, changes nothing |
| non-deterministic function | `function f!(…) => (@r: T) is` | has a result that can differ for the same arguments (random, time, a closure that counts); every function that creates a closure |
| procedure | `procedure p(…) is` | has no result; does work (prints, writes, changes `@` parameters or module state); called as a statement; needs no `!` |

`function` without a result list and `procedure` with one are compile errors. A procedure is called as a statement, with or without parentheses when it has no arguments (`foo;`).

- The result is written `=> (@name: Type)`; `@` makes it a reference; the result variable is assigned in the body; `return;` carries no value. Several results: `=> (@q: Integer, @r: Integer)`.
- A plain function and a `!` function can not change a global, a module variable or a parameter, and can not call a procedure. A procedure may call any function or procedure.
- Parameters: one list of values. A first list of types in front of it makes a generic function, procedure, method or process, `function largest(:T <: Comparable)(items: ()T) => (@result: T)`; at the call the types are inferred or written, `largest(xs)`, `largest(:Integer)(xs)`; a lambda has no type list (level 5). `name: Type` is mandatory; `name = value:Type` or `name:= expression` is optional with a default; `*name` collects the rest (vararg); `@name` is an input/output reference and has no default. Parameters after a vararg are optional and are named at the call.
- Order: a mandatory parameter may follow an optional one (typically an `@` parameter); the call must then name it (`add(1, 2, op: @result)`). Every `@` parameter is input/output; there are no pure output parameters.
- At the call, positional arguments come first; an optional parameter is named with `:` (`greet("Eve", greeting: "Hi")`); an `@` parameter needs `@` on the argument (`swap(@a, @b)`).
- Without `@` an argument is passed by value, collections included (like `::`).
- Functions and procedures do not handle errors: an error propagates to the process.
- `print`, `write`, `read` are library procedures, called as statements.
- A procedure never ends with `!`: it is made for side effects and is never deterministic; `procedure p!()` is a compile error.
- **No references to procedures**. A procedure is not a value: it can't be passed as an argument, stored in a variable or returned, and there are no procedure types. A callback is always a function; a function type derives from `Function`: `class BinEx = (p1, p2: Integer): Integer <: Function;`.
- **Closures**. A closure is a function declared inside a function or a procedure; it is never a procedure. A function that creates a closure always ends with `!` (`function make_counter!(first: Integer) => (@next!: Function)`), even when it could be called deterministic: these higher-order functions are not optimized. A procedure can create several closures and give them out through `@` output parameters (`procedure make_pair(first: Integer, @up!: Function, @down!: Function)`). The enclosed function has the name of the result or output parameter it fills.

## Classes and objects

A class declares the attributes of its signature, its supertype and, between `is` and `end Name;`, its constructor, destructor and methods:

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
- **Construction.** A class is called like a function: `new p:= Point(1, 2);`. The constructor result is `@self`, whose type is the class. Its first statement builds the object: `let self:= Object();` for a class derived from `Object`, `let self:= Superclass(args);` for a subclass. The object is allocated once at the root of the chain. Using `self` before it is built, building it twice, or replacing it is a compile error.
- A class without a constructor is filled by name: `new c := Circle(name: "wheel", radius: 2.5);`.
- **Methods** belong to a class: declared in its body, or outside it as an extension method whose first parameter is `@self` with the class type. A method receives the object as `@self` (no type inside the body). A chainable method has `=> (@self)`.
- **Visibility** is a word in front of the declaration: `public`, `protected` (the class and its subclasses), `private` (the default). The attributes of the signature are public.
- `let self.x:= v;` sets an attribute of the signature; `new self.extra:= v;`, in a constructor or a method, creates another one, which is private. Code outside the class can not add an attribute: `new p.z:= 7;` is an error.
- **Destructor** (CLS-14). `destructor(@self) is … return;`, one per class, public to nobody (it is only run by the machine). It runs **once** per object, when the last reference to the object is released, at the next safe point of the region, and for the objects that are still alive at the end of the run; when several objects are freed together the newest runs first. A class runs its own destructor and then the destructors of its parent classes, child first. An error raised in a destructor is dropped and the free goes on; a destructor that keeps a reference to `self` cancels the free. An object that only the tracing collector finds (a reference cycle) runs its destructor before it is freed.
- **Names of a class** (CLS-13). A property and a method of one class may not share a name (compile error, exit 65); several methods may share a name (overloading).
- **Private attributes and constants** (CLS-17b). `new self.extra:= v;` is allowed only in a class that has a constructor (a class without one is filled by name, so nothing would set the attribute): otherwise a compile error. A class constant is declared with `set` in the class body, also in a partial (abstract) class: `set sides = 4:Integer;`; it is evaluated once, when the class is declared, and read as `ClassName.NAME`.
- **A class hosts only methods** (replaces for functions). A `function` or a `procedure` in a class body is a compile error; a helper of the class is a private method, or a function declared outside the class. The methods may use lambda expressions.
- **Class variables** (clarification of). "Only methods" restricts subprograms, not data: a class can hold private variables, the class variables. The constructor and every method of the class reach them as `ClassName.VarName`. Code outside the class, such as a function or a procedure, can not read or write them directly: the class offers accessor methods. A class variable is declared with `set` in the class body (`private set count: Integer;`), as in the tutorial page Classes.
- **Only a method binds the object.** `@self` is the parameter of a method (in the class body or outside it, as an extension method). A function or a procedure can not have `@self`, and so can not be bound to a class: `function total(@self: Point) => (...)` is a compile error.
- **Methods are not values**. There are no references to methods and no method type: a method can't be passed as an argument, stored or returned, and it is never a callback. A lambda that calls the method is passed instead: `shapes.map((s) => (s.area()))`.
- Extension methods are static: they never change the class, can not hide a method of the class, see only its public members, and are visible only in the scripts that declare or import them.
- Generators belong to level 5 (level 5). Traits, abstract classes and generic classes are level 4, below.

## Traits and generic classes

Level 4. Grammar: `grammar.md#traits-and-generic-classes-level-4`. Compile errors (exit 65): a missing required method, `{class} does not implement {method}` (d21); an abstract class created outside a subclass constructor, `{class} is abstract` (d23); two traits that provide the same method, `{class} must write {method}: it comes from {trait} and {trait}`.

```eve
trait Printable is
  method describe(@self) => (@result: String);   ** required: a signature that ends with ;
  method show(@self) is                           ** provided: has a body
    print self.describe();
  return;
end Printable;

class Point = {x: Integer, y: Integer} <: (Object, Printable) is
  public method describe(@self) => (@result: String) is
    let result := "({self.x}, {self.y})";
  return;
end Point;
```

- **Trait.** `trait Name is … end Name;` holds required methods (a signature that ends with `;`) and provided methods (with a body, which may call the required ones through `self`). A trait has no attributes, no constructor and no instances. Every method of a trait is public. A trait is a type: `new p: Printable := pt;`, `pt is Printable`.
- **Adopting.** After `<:` comes one class, then the traits, in parentheses: `<: (Object, Printable, Comparable)`. A method of the class wins over a provided method. When two traits provide a method with the same name, the class must write it. A class that can be created must implement every required method: a missing one is a compile error that names the class and the method.
- **Abstract class.** A class with at least one required method (a `method` signature that ends with `;`) is abstract. Its constructor is called only as the first statement of a subclass constructor (`let self := Shape(name);`); a call anywhere else is a compile error.
- **Generic class.** `class Box(:T) = {item: T} <: Object is` declares a type parameter `T`, used in the attributes and the methods. The type argument is always written when an object is made: `new b:= Box(:Integer)(5);`, like `Channel(:Integer)(capacity: 10)` and `Atomic(:Integer)`. There is no inference in level 4. **Several type parameters** are written in the same list (CLS-09): `class Pair(:K,:V) = {key: K, value: V} <: Object is`, made as `Pair(:String,:Integer)(key: "a", value: 1)`; the prefix forms of the collections (`()Type`, `{}(K:V)`) are the notation of the library and are not available to a user class. A constraint is written `(:T <: Comparable)`: the type argument must adopt the trait.
- **Library traits** of level 4: `Iterable(:T)` (what `for` reads), `Stream(:T) <: Iterable(:T)` (`../semantics/multitasking.md#streams-and-batches`), `Comparable` (`method compare(@self, other) => (@result: Integer);`, negative, zero or positive) and `Printable` (`method describe(@self) => (@result: String);`, used by `print` and by `{x}` in a string). The basic types adopt `Comparable` and `Printable` in the library.
- Not in level 4: generic functions, procedures, methods and processes, overloading (next section).
- **Adopting a trait outside the class** (CLS-15). A type adopts a trait where the type was not declared, for example a basic type or a class of another module: `adopt Describable for Integer is … end adopt;`. The block writes every method that the trait requires, and no method that the trait does not have; the methods are extension methods of the type, so they are visible only in the unit that declares or imports them and see only the public members. The provided methods of the trait become methods of the type too, `x is Describable` is true for the type, and the type can be a type argument of `(:T <: Describable)`. The trait is written before the block.
- **Where the library traits live** (CLS-16). `Iterable`, `Stream`, `Comparable` and `Printable` are known to the language as listed above; they may be written as Eve files of the library, and the library adds traits as it grows (plan step S5.1a).

## Generic subprograms and overloading

Level 5. Grammar: `grammar.md#generic-subprograms-and-overloading-level-5`. Compile errors (exit 65) and their messages: `can not infer the type T of make` (e15), `a lambda has no type list` (e14), `ambiguous call of f` (e08, e09), `no signature of half matches` (e10), `report is both a function and a procedure` (e11), `half is declared twice with the same signature` (e12).

```eve
function largest(:T <: Comparable)(items: ()T) => (@result: T) is
  let result := items[1];
  for x in items do
    let result := x if x.compare(result) > 0;
  done;
return;

function half(x: Integer) => (@result: Integer) is    ** overloaded by the type of x
  new h := x / 2 :Integer;
  let result := h;
return;
function half(x: Real) => (@result: Real) is
  let result := x / 2.0;
return;

print largest((3, 9, 2));               ** 9: T is inferred, Integer
print largest(:String)(("b", "c"));     ** c: T is written
print half(8), half(9.0);               ** 4,4.5
```

### Generic subprograms

- **Two parameter lists.** A function, a procedure, a method or a process may have a first list of types before its list of values: `function largest(:T)(items: ()T)`, `procedure show_all(:T)(items: ()T)`, `method tagged(:U)(@self, tag: U)`, `process main(:T)(data: ()T)`. The type list follows the name (and the `!` of a function); the value list follows the type list. A subprogram without a type list has one list, as before.
- **Type parameters.** Each is written `:Name` and may have a constraint `:Name <: Trait`; the type argument must adopt the trait. Inside the subprogram the name is a type: in the parameters, the results, the declarations and `is` tests.
- **The call.** The type list at the call is optional: `largest(numbers)` infers `T` from the types of the arguments; `largest(:Integer)(numbers)` writes it. Written types are all given, in order. A type that can not be inferred from the arguments must be written, otherwise a compile error: `can not infer the type T of make`. The expected type of the result does not infer a type parameter.
- **Methods.** A method of a generic class uses the type of its class (`T`) and may have its own type list (`:U`): `b.tagged(1)`, `b.tagged(:String)("box")`. A method of a plain class may have a type list too.
- **Processes.** The process `main` of an aspect may have a type list; `apply` infers it or writes it: `apply sorter(rows);`, `apply sorter(:Row)(rows);`. The process `main` of a driver has no type list: nothing calls it.
- **No generic lambda.** A lambda has no type list: `(:T)(x: T) => (x)` is a compile error, `a lambda has no type list`. Work that depends on the type is written as overloaded functions (below).
- **No self-calling lambda**. `(…)(…)` after a name is a type list followed by the arguments; after a lambda it is a compile error (`expressions.md#index-slice-member`).

### Overloading

- **Shared names**. Several functions, several procedures or several methods of a class may have the same name when their signatures differ. Redeclaring a name in the same scope is still an error for every other declaration.
- **Signature.** The number of parameters and the type of each parameter, and for a function also the type of its result. The names of the parameters, their defaults and the `@` marks are not part of it. Two declarations with the same signature are a compile error: `half is declared twice with the same signature`.
- **Compile time.** The signature is selected at compile time, never at run time by the type of a value. The candidates are the declarations whose parameters accept the arguments (number, types, defaults, varargs, named arguments). When candidates differ only by the type of the result, the type expected at the call decides: a type hint (`new n := unit() :Integer;`), the type of the target of `let`, the type of the parameter that receives the value, or the result of the enclosing function.
- **Unique.** The call must identify exactly one signature. Two candidates are a compile error, `ambiguous call of f`, also when they come from defaults or varargs (`f(x: Integer)` and `f(x: Integer, y := 1)` for `f(5)`), or from a result type that the call does not fix (`print unit();`). No candidate is a compile error: `no signature of half matches`.
- **Functions and procedures.** A function and a procedure never share a name: `report is both a function and a procedure`.
- **Methods with and without a result.** A method without a result and a method with a result may share a name and the same parameters: they are different methods. A call as a statement selects the method without a result, `c.step();`; a call in an expression selects the method with a result, `print c.step();`. An extension method may overload a method of the class with another signature; one with the same signature is a compile error, as it would replace it.
- **Overloading and generics.** A generic subprogram and plain ones may share a name; a plain one whose parameters fit the arguments exactly wins over the generic one.
- **Not overloaded:** processes (an aspect has one), constructors, lambdas and function variables (one value per name).

## Generators (level 5)

Level 5, feature F-LNG-12. Grammar: `grammar.md#generators-level-5`.

A **generator** is a subprogram that produces its values one at a time. It is declared with the keyword `generator`, like a function or a method, and has exactly one result, the value it produces:

```eve
generator count_to(n: Integer) => (@x: Integer) is
  for i in (1..n) do
    let x := i;           ** set the result
    yield;                ** give x to the caller, wait here
  done;
return;                   ** no more values
```

- `yield;` gives the current value of the result to the caller and suspends the generator. `yield expression;` is the short form of `let x := expression; yield;`. `yield` is allowed only in the body of a generator, and **only in the body itself**: in a function, a method, a lambda, a process, or in a subprogram that a generator calls, it is a compile error (Eve has no coroutines). `return;` ends the generator.
- A call of a generator does not run its body: it creates a **generator object** of the core class `Generator(:T)`, where `T` is the type of the result. The body runs when the caller asks for a value: a `for` loop takes the values one by one, a comprehension collects them, `g.next()` runs to the next `yield` and gives `True` (and a new `g.value`) or `False` when the body has returned; `g.done` is `True` after the return or after `g.close()`. Reading `g.value` before the first `next()` is an error. A generator object is also an `Iterable(:T)`.
- Calling a generator is deterministic, so its name has no `!`. A generator called as a statement, `count_to(5);`, is a compile error: its values would be lost.
- **Lazy:** the arguments are evaluated when the object is created; the body begins at the first request. **State:** the parameters and the local variables live in the object between two requests, and are dropped when the body returns, at `close()`, or when nobody refers to the object any more. A `for` loop left with `break` closes its generator.
- A generator has inputs only, by value: no `@` parameter other than its result. A generator object is never copied and can't be an argument of `apply` or `start`: it belongs to the process that made it.
- An error raised in the body ends the generator and is raised in the caller, at the `next()` or at the `for` line.
- A generator can be declared where a function or a method can: in a class (`public generator walk(@self) => (@node: Node) is … return;`), in a module (exported with `export`), or private to an aspect. A generator exported by a module must be thread safe.

Compile errors (exit code 65): `**yield outside a generator**` (in a function, a method, a lambda or a process); a generator with no result or with more than one; `generator {name} **called as a statement**`.

## Table declaration (level 5)

A class that derives from `Record` is a row type; a `table` declaration binds it to a table of a named connection. It keeps classes plain: the class holds the fields, the declaration says where the rows live, and one class can have several (a CSV file, a staging table, a remote table). Grammar: `grammar.md#database-declarations-and-statements-level-5`; clauses, the mapping rules and the methods of a table: `../library/database.md#the-table-declaration`.

```eve
class Customer = {id: Integer, name: String, city: String?, version: Integer} <: Record;

table customers: Customer in "sales" is
  key (id);
  generated (id);
  version version;
  column name as "cust_name";
end customers;
```

`table` is declared in an aspect, a module or an Eve macro, like a class; `customers` is an object of the library class `Table(:Customer)`. A record class may declare methods; `validate(@self)` runs before every write.

## Eve macro (level 5)

Level 5. Grammar: `grammar.md#eve-macro-level-5`. An **Eve macro** is one self-contained file that holds **shared declarations** and any number of **aspects**, exactly one of them a **primary aspect**. A small job, also a parallel one, needs no project folder and no `asp/`.

```eve
# pipeline: two workers in parallel, one file

class Result = {name :String, count :Integer} <: Object is
  constructor(name = "" :String, count = 0 :Integer) => (@self) is
    let self := Object();
    let self.name := name;
    let self.count := count;
  return;
end Result;

concurrent aspect job_worker_1 is
  process main(@res: Result) is
    let res := Result("worker 1", 10);
  return;
end job_worker_1;

concurrent aspect job_worker_2 is
  process main(@res: Result) is
    let res := Result("worker 2", 20);
  return;
end job_worker_2;

# the primary aspect: run by a command, it starts the parallel tasks
primary aspect pipeline is
  process main is
    new r1 := Result();
    new r2 := Result();
    p_exec: parallel
    do
      start job_worker_1(@r1);
      start job_worker_2(@r2);
    done p_exec;
    print "{r1.name}: {r1.count}, {r2.name}: {r2.count}";
  return;
end pipeline;
```

- **Kind.** No keyword marks a macro: a file with several top-level aspects, or with an aspect and other top-level declarations, is a macro. A file with a single aspect is an aspect, as before. `eve pipeline.eve` runs `process main` of its primary aspect, which takes the command-line arguments.
- **Primary aspect.** A macro has exactly one `primary aspect`. It is the entry point and the root of the run; no aspect of the file applies or starts it.
- **Line 1.** There is no `#!` line. A macro may start with a `#` title (`../lexical/lexical.md`, File header).
- **Top level.** The top-level declarations are written at column 1, in any order (one scope per file): shared declarations (`class`, `function`, `procedure`, `method`, `set`, `new`, `def`, `from … use`) and aspects (`exclusive`, `concurrent` or `primary`). Style: shared declarations first, then the other aspects, the primary aspect last. A statement outside a declaration (`print`, `let`, `if`, …) is a compile error: `a statement outside a declaration in a macro`.
- **Shared declarations.** Every top-level declaration that is not an aspect is shared by all the declarations of the file. The primary aspect and the exclusive aspects use them freely, also the variables: they run alone, so they change a shared variable safely.
- **Concurrent aspects.** A concurrent aspect uses only the thread-safe shared names: constants (`set`), classes, atomic variables (`Atomic(:T)`, `../library/atomic.md`) and channels, and functions, procedures and methods that the compiler proves thread safe, as for a direct module. Using another shared variable, or calling a subprogram that reaches one, is a compile error that names it: `the concurrent aspect 'adder' uses 'count', which is not thread safe`, `… calls 'bump', which is not thread safe`. A shared function that reads an atomic variable is stochastic and is named with `!`, as in a managed module.
- **Aspects.** Each aspect keeps its own scope and state: it sees the shared declarations and no variable of another aspect. `apply` and `start` follow the rules of `../semantics/aspects.md` and `../semantics/multitasking.md`; the calls between the aspects of a macro count as levels like any other.
- **Name lookup.** An aspect named in `apply` or `start` is searched first among the aspects of the macro, then in `asp/` and the project root. An aspect of the macro with the name of an aspect file of the project is a compile error: `aspect worker is declared in the macro and in asp/worker.eve`.
- **Self-contained.** The aspects of a macro are private to it: no other script can `apply` or `start` them. A macro can not be imported and exports nothing; `export` in a macro is a compile error.
- **Compile errors (exit 65).** `a macro has only one primary aspect` (two); `a macro needs a primary aspect` (none); `a primary aspect is run by a command: it can't be applied or started`; `a statement outside a declaration in a macro` (e22); `'x' is already declared in this scope` (a top-level name declared twice); the thread-safety errors above (e19, e20).

## Imports and modules (level 3)

`from lib use (a, b);` imports names; `export (a, b);` lists the public members of a module. A module holds declarations and the regions import, export, initialize, recover and finalize; a free statement is an error in a module, and an aspect can not be imported. The whole chapter (members, life cycle, import forms, search path, libraries) is in [../semantics/modules.md](../semantics/modules.md); the grammar is in [grammar.md](grammar.md#modules-and-imports-level-3).
