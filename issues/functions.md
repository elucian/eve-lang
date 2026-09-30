# Issues: functions.html

Page: `tutorial/functions.html` (271 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### FUN-01 Is a function result mandatory?
Notes say "Function result is mandatory and explicit" and, two lines later, "A function can return
a result but the result is optional". Which one?
**Answer:** A function need a result, if function do not define a result is a method. Fix the specification. If a function do not have a result how can it be used in expressions? This is why.
Status: answered (D-028)

### FUN-02 Result declaration and `@`
`function name(params) => (@result:TypeName)`: the result is declared with `@`, and the body
assigns `let result := …` without `@`. syntax.html says `@` marks "receiver parameter" and
"input/output parameter | result prefix", and `$result` is "the default result when a name is not
specified". Can a function have several results? Is `$result` used when the result is unnamed?
**Answer:** Yes a function can return a list of results. In this case $result is a list. (result1, result2). The @ require the result to be a variable in the call. It force a refference. So we cant say let 2 := f(x); because 2 is not a variable but we can say let v := f(x) because  v is a variable.
Status: answered (D-028)

### FUN-03 Function purity
"A function can have input/output parameters", "can't modify a global variable", "can raise errors
but can't handle errors", "can be suspended and resumed". May a function call a routine, print,
read files? Can it contain a `job` (it "can't handle errors")?
**Answer:** A plain function is deterministic, has no side effects and calls only plain functions. A function with side effects, or not deterministic, is written `name!()` (D-027). Jobs do not handle errors, functions can't handle errors because functions are not processes. Only processes can handle errors. We need to use preconditions to avoid runtime errors if errors happen program will crash with a runtime error but error can propagate to process and process can handle it.
Status: answered (D-027, D-020)

### FUN-04 Default parameter operator
Defaults are written `name2(param := value, …)`, but declarations elsewhere use `=` for initial
values (`set a = 0`). Which operator declares a default: `:=` or `=`?
**Answer:** "=" will define a default value. ":=" is used to execute an expression.
Status: answered (D-028)

### FUN-05 Named arguments
`name2(param:arg, …)` uses the pair operator `:`. Can positional and named arguments be mixed
(processing.html does: `run aspect_name (value, value, param:value)`)? Positional first?
**Answer:** Yes, positionals goe first, if they are mandatory do not require name. Optional parameters require naming. 
Status: answered (D-028)

### FUN-06 Creating a closure
"Closures are dynamically created at runtime using `new`", but the example writes
`let closure := Function() => (@result:Integer): … return;`. Which is the closure syntax? Is
`Function` a keyword here or the type name?
**Answer:** A method creates the closure: a function enclosed in the method, sharing its state. Its name ends with `!` (D-027). Whether `Function` is the type name is still open. Yes a function is of type Function and is an object or a restricted object if the function is pure.
Status: answered (D-027, D-028)

### FUN-07 Lambda syntax
Three forms appear: `(p1, p2: Integer) => (p1 + p2);`, `(p1, p2 :Integer) => (p1 + p2):Integer;`
and `(x:Real) => floor(x * 10^decimal)/10^decimal;` (no parentheses around the body). Are the
parentheses around the body required? Where does the result type go? Can a lambda be multi-line?
**Answer:** Paranthesis are mandatory and a list of several expression will create several results. The type goes after paranthesis ():Type; or ():(Type, Type). 
Status: answered (D-028)

### FUN-08 `Lambda` versus `Function` types
`class BinEx = (p1, p2 :Integer):Integer <: Lambda;` derives from `Lambda`, which is not in the
composite types table (it has `Function`). Are `Lambda` and `Function` two types?
**Answer:** Good question. We do not define Lambda functions we define just functions, Lambda is just a notation, that create a function in a single statement from one or more expressions.
Status: answered (D-028)

### FUN-09 Routines
`routine useLambda(test :BinEx):` and `call useLambda(…)`. Functions and lambdas are explained,
but routines are not introduced on this page (only used). Where is the routine defined: this page,
processing.html, or classes.html? What distinguishes a routine from a function (side effects, no
result, `call`)? (See TYP-17.)
**Answer:** There are no routines. A subprogram without a result is a method; a function with side effects is a `!` function (D-027). Methods can return results and can be declared at module level, public (`.`) or private (`_`).
Status: answered (D-025)

### FUN-10 Anonymous functions
"A function has a name. There are no anonymous functions", but a lambda passed as an argument is
anonymous: `call useLambda((x, y) => (x + y));`. Is the rule "named functions, anonymous
lambdas"?
**Answer:** Yes, Lambda expressions can be assigned to a function identifier but if identifier is not defined, the function is just a pointer. It can be send to a input parameter that receive a pointer @param. Keyword function must be follow by an identifier.
Status: answered (D-028)

## Fixes (applied unless you write "no")

### FUN-F1 Wrong content
- "Function is executed … using the name of the function followed by semicolon" → by
  parentheses.
- `set sqr = (p1, p2 :Integer) => (p1 * p2)` computes a product; rename to `mul` or use one
  parameter.
- `useLambda` calls `test()` without the two arguments `BinEx` needs.
- Lambda-and-states example: `set decimals = 2: Integer;` sits outside any `global` region; the
  lambda reads `decimal`, the global is `decimals`; the text says "after round()" but the code uses
  `floor`; missing `;` after `print trunc(x)`.
- `driver lam_sig` has no `:`/`()` consistent with the others (D-012).
**Answer:** Ok fix this. driver need "is" keyword
Status: done (D-015, tutorial fixed)

### FUN-F2 Typos
"Result type must is declared", "when when", dynamicly, "de compiler", Sefine, "Disclaim".
**Answer:** We need to fix typos. Status: done.

## Improvements (applied only if you write "yes")

### FUN-I1 Functions, routines, lambdas, methods compared
One table: declared with, has a name, result, side effects allowed, handles errors, can be
suspended, called with (`f()`, `r();`, `start m`). Functions and methods only, see D-025.
**Answer:** Good idea. Yes.

## Spec additions once answered

- `spec/syntax/declarations.md`: function, lambda, closure, routine declarations (FUN-02, 04,
  06, 07, 09).
- `spec/semantics/`: purity and side-effect rules (FUN-03), argument binding (FUN-05).
