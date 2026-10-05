# 04 Functions, methods, classes (`RSB`)

## Advantages

**RSB-A01 Purity is part of the signature.** A plain function is deterministic and has no side effects; `f!()` marks effects or randomness; a method may always have effects (D-025, D-027). This is a real effect system in miniature: it lets a compiler memoize, parallelize and cache pure functions, and lets a server run pure transforms anywhere.

**RSB-A02 Explicit in/out parameters.** `@` at the declaration *and* at the call (D-048) shows at the call site what can change. By-value arguments for everything else make data flow local.

**RSB-A03 Generators are one level deep.** D-067: `yield` only in the generator's own body, no coroutines. This keeps the VM simple and the reasoning local, and still covers lazy streams — the most common ETL need.

**RSB-A04 Traits instead of multiple inheritance of state.** D-039 (proposed): at most one stateful superclass plus stateless traits, missing methods are compile errors. Modern and safe.

**answer** Agree!

**RSB-A05 Extension methods are module-private.** D-072: `method _name(@self: Class …)` cannot leak into other modules, avoiding the "monkey patching" problems of Ruby.

## Disadvantages

**RSB-D01 Function vs method vs `!` function vs closure vs generator.** Five kinds of subprogram with different rules: functions must return a result, methods may not; a function that calls a method must be `!`; a closure is a `!` function enclosed in a method; a generator is a method that contains `yield`. The method/function split is *effectful vs pure*, which `!` already expresses. Two mechanisms for one idea.

**todo** Agree, there are differences, methods can't be assigned to variables as pointers. Functions can be anonymous and can be called imediatly using ()(). Methods hold state, functions are state-less.


**RSB-D02 Result parameters with `@` names.** `function fib(n: Integer) => (@y: Integer)` then `y := …; return;` (manifest example). This is Pascal/Ada style; it prevents `return expr;` and makes early returns verbose. D-036 also says `return` carries no value.

**answer** I want to prevent early returns, we have: exit, abort, over, other inreruptions that can cause early return. We calculate result in several places and we can override the result several times before the final result is established. Then we can issue exit for early return instead of exit expression; or return at the end. I think my logic is sound.

**RSB-D03 Constructor syntax with two parameter lists and self-assignment.** `constructor(@self)(x = 0 …) is self := new Object(); …` (D-036). Assigning `self` inside a constructor, and creating the superclass part with `new`, is unusual and error-prone (what if the constructor forgets?). D-029 says "one parameter list, never two", which the constructor contradicts.

**answer** Right. I want a solution to this. Keyword new will create the pointer to @self. Self is created, and is magic. We do not need to define @self for constructors, because constructors are already build in classes body. So we know @self type. We can just use self. as reserved keyword. So my attempt to create explicit declaration and creation of objects failed. We do it like Java do this. @self is necesary only in extension methods that are created ourside of class declaration. Like in Python. We keep class body as small as possible and define methods to extend the class.

**RSB-D04 Class header mixes record and class syntax.** `class Point = {x, y :Real} <: Object is … end Point;`. Fine, but the databases page still uses the pre-D-036 forms (`let self.location = location;` as attribute creation), so readers see two dialects.

**answer** Both ways are legit. We can define a class using short hend form {} without a body, we can later attach methods to it. Or we can add new attributes to it to extend the class in a constructor of a superclass. 

## Antipatterns

**RSB-X01 Signalling by naming convention (`!`, `_`, `.`).** Effects (`!`), protection (`_`), publicity (`.`) and extension (`_` at module level, D-072) are all one-character prefixes/suffixes on names. `_` means *protected* in a class and *extension, module-private* at module level. A reader must know the context to read a name. Keywords (`pub`, `ext`) or annotations cost a few characters and remove the ambiguity.

**answer** I agree, let's use new keywords we already use "external" so what you think "ext" means extended or external? let's use full english qualifiers instead of conventions "." "_" but we keep ! to define unsafe functions. 

**RSB-X02 Generator detection by body content.** "A method becomes a generator because its body contains `yield`" (D-067). Python's experience: adding one `yield` deep in a long method silently changes every caller (the call no longer runs the body). D-067 mitigates by making a statement call an error, but `let g := f();` still changes meaning. The header should say it.

**answer** agree, let's use method!() for this kind of method. Is a special method and user need to pay attention to it when it uses this kind of method. Is a hiher order method. Also a method that span closures, should use ! suffix.

## Recommendations

**RSB-R01 One subprogram kind, effects in the signature.** `fn name(params) -> T` for everything; pure by default; `fn! name` (or an `effects` clause) for side effects; a missing result type means "no result". This removes the function/method distinction and keeps the purity guarantee. If both keywords stay, at least define `method` = `fn!` formally so the spec has one rule.

**answer** The suggestion sound interesting. method is a keyword, fn! is an invented keyword not present in specification. fn! does not exist. What is it? We use ! in the name like: function name!(), that is totally a different thing. Proposal is rejected.

**RSB-R02 Return values by expression.** Allow `return expr;` and an anonymous result type `=> Integer`. Keep named results as an option for several outputs.

**answer** We have discuss this before. We do whatever we can to accomodate this design or die. 

**RSB-R03 Mark generators in the header.** `method count_to(n: Integer) yields Integer is` or `=> Stream(:Integer)`. The VM learns the frame kind at compile time (it needs to anyway, `RVM-R01`).

**answer** we create a new keyword: generator that is for this kind of subprogram.

**RSB-R04 Constructors as ordinary initializers.** `init(x = 0, y = 0 :Real) is self.x := x; … end;`, the object already exists when `init` runs, `super.init(...)` (or `Shape.init`) for the parent. No assignment to `self`.

**answer** In this case, a class that can be inherited need an init method, I do not like this. Better we call constructor using Let instead of New. That is a signal that the @self object is alredy created and need modifications. Superclass will not create the object. But isn't this the default constructor behaviour? The object is already assigned by new keyword: New x := Constructor(params). 

**RSB-R05 Visibility by keyword.** `pub method write(...)`, `ext method (s: String) shout()`; prefixes `.` and `_` retire. This also simplifies the lexer (a leading `.` is no longer a token ambiguity with member access).

**answer** I agree.

**RSB-R06 Effect classes that the server can enforce.** Split `!` into capabilities the VM checks: `io`, `net`, `db`, `shell`, `random`, `time`. A pure function can run on the client, the server or in WASM; an `net` method only where the capability is granted (`RNW-R08`).

**answer** Need details, make a document to explain.
