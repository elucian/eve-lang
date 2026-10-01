# Issues: classes.html

Page: `tutorial/classes.html` (899 lines, `<title>` "Eve Classses"). Reviewed 2026-09-28. How to
answer: [README](README.md).

## Questions

### CLS-01 Class declaration forms
The page uses six forms:
`class X = {a, b: Integer} <: Object;` (no body), `class X = {…} <: Object:` + body + `return;`,
`class X <: Object:` (no attributes), `class BaseType = {attribute};` (no supertype),
`class NewType += {new_attribute} <: (A, B):` (`+=`), and `class Printable:` (no supertype, no
attributes). With D-012 dropping header colons, how does the parser know that a body follows:
the `;` versus no `;`? What does `+=` mean in a class header (add attributes to the inherited
ones)? Is a supertype required?
**Answer:** yes, if ";" follow after supertype, there is missing body. Otherwise, "is" keyword must follow to define the class body. += will add attributes to the NewType.
Status: open

### CLS-02 Public and private members
This page: public classes and members start with `.` (`class .Name`, `set .last`,
`method .change`), private ones with a lowercase letter. syntax.html: `_` is the "protected member
sigil". Which rule holds? Is `.name` the declaration only, with access by plain `obj.name`?
**Answer:** Yes, the . indicate that can be used with dot notation by the object or by the class name if is a class variable. If is not self.var,
Status: open

### CLS-03 Where object methods live
Methods in the class body are class (static) methods without `@self`; object methods are declared
inside the constructor, as closures. Constructors are declared outside the class body. Confirm this
model: it differs from most languages, so the spec must state it exactly.
**Answer:** Correct, we flat the design by allowing constructor to be outside of the class declaration. Usuallt is one class per file, but Eve allow multiple classes in a module.
Status: open

### CLS-04 Attribute access in constructors
The examples write `let self.x := x;` for public attributes; the inheritance pattern writes
`let attribute := param1;` ("standard public attribute", no `self.`); hidden state is
`new self.state := 0;`. The text says public attributes are initialized with `let` and private
ones created with `new`. Is `self.` required? Is a private attribute any attribute created with
`new self.name`?
**Answer:** Yes, self.name create an object attribute that is private to object. Public attributes belong to class therefore no "self" these are declared in class body using ".".
Status: open

### CLS-05 `@self` versus `self`, and `return @self;`
The constructor declares `=> (@self: Point)`, the body uses `self.x`, a release region takes
`release(@self: Point)`, lists add `@self`, and chainable methods end with `return @self;`,
although `return` elsewhere only closes a declaration. When is `@` written? Is `return <value>;`
allowed?
**Answer:** No, is a mistake. We need to assign self := when we create the self. Becasue self is explicit declared with @ we can assign a value to it.

### CLS-06 Calling another constructor
Three forms: `let self = Point(other.x, other.y);`, `super(name);`, and
`let Circle := ShapeConstructor(name);`. Which is the way to call the super-constructor or another
overload? Is `super` a keyword?
**Answer:** No super is not a constructor name we must use superclass constructor name. It usually is the name of superclass, if implemented by convention.
Status: open

### CLS-07 Multiple inheritance conflicts
`<: (AbstractType, BaseType)` inherits from several classes. When two supertypes define the same
attribute or method, which wins, or is it a compile error?
**Answer:** _(open)_
Status: open

### CLS-08 Unimplemented partial methods
A partial method is a signature ending in `;`. One example says "this method signature needs
implementation, otherwise the result is Null". Is a missing implementation a compile error, or does
it return `Null` at run time?
**Answer:** _(open)_
Status: open

### CLS-09 Generic syntax
Classes: `class GenericClass(:T) <: SuperType`, instantiated as `GenericClass(:Integer)(args)`.
Collections: prefix forms `()Type`, `[]Type`, `{}Type`, `{}(K:V)`. Are both notations kept? Can a
user class take several type parameters (`(:K, :V)`)?
**Answer:** _(open)_
Status: open

### CLS-10 Bare call statements
syntax.html: "each statement starts with a keyword". This page has bare calls:
`ClassName.change(10);`, `myCircle.print();`, `num32.add(10);`, `super(name);`. Are bare method
calls statements, or must they use `call`?
**Answer:** _(open)_
Status: open

### CLS-11 `Type(x)` or `type(x)`
This page uses `Type(myList)`; types.html uses `type(x)`. Which name is the built-in?
**Answer:** _(open)_
Status: open

### CLS-12 Dynamic objects
"Each object can have the same or a different structure, due to the dynamic nature of Objects", and
`Object(attribute1: value1, …)` "binds values to new attributes that are not declared". Can any
object gain attributes at run time, or only instances of `Object` itself? Is this in 0.1 ("a minor
feature")?
**Answer:** _(open)_
Status: open

### CLS-13 Property and method with the same name
The method example declares `set sum: Integer;` and `method .sum()`. May a property and a method
share a name?
**Answer:** _(open)_
Status: open

### CLS-14 Class release region
Two forms: a `release` region inside the class body (after the declarations), and
`release(@self: Point):` with a parameter. When does `release` run: when each object is freed, or
when the class is unloaded?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### CLS-F1 Comments against D-011
Indented `#` comments (`# Method to get the value`) and end-of-line `#` comments
(`num32.print();  # Output: …`) in the generic examples → `**`.
**Answer:** _(open)_

### CLS-F2 Wrong examples
- Point output: `p2 = {x:2, y:2}`, but `Point()` uses defaults 0, 0; the printed format differs from
  `string()`.
- `num64.multiply(2)` on `9223372036854775807` expects `18446744073709551614`, which overflows i64.
- Optional example: `intProcessor.process(:Integer,5));` has an extra `)` and wrong arguments;
  `new` statements sit in the driver before `process`.
- `class ElementType = {a,b,c: Integer} <: DataSet;` describes a record; should derive from
  `Object`.
- `print myList ** ({1,2,3},{7,8,9})` is missing `;`.
- Prose: complementary operators "is not" and "!=" → `<>`.
- `<title>` "Eve Classses", `h1` "Eve Objects": use one name.
**Answer:** _(open)_

### CLS-F3 Typos
descendents, Employe/Emplyes, complementar, inherite, alwais, metods, necesary, propetyes, optonal,
comstructor, repesents, bas-class, bihaviour, partal, SupetType, budy, "and and", instantes, simpe,
"more to left unexplained".
**Answer:** _(open)_

### CLS-F4 Authoring standard
"handle nullable values elegantly", "Benefits of Method Chaining" (generic advice), "inspired from
Banyan Tree in Florida", "Eve implements all 4 OOP principles" (stated twice).
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### CLS-I1 Split the page
Classes (declaration, members, constructors, inheritance, partials) on this page; generics and
Optional on their own page, next to collections.
**Answer:** _(open)_

### CLS-I2 Member table
One table: member kind (class property, class method, attribute, object method), where declared,
keyword, public form, access syntax, has `@self`.
**Answer:** _(open)_

## Spec additions once answered

- `spec/syntax/declarations.md`: class, constructor, method, partial, generic (CLS-01, 05, 06, 08,
  09).
- `spec/semantics/`: visibility (CLS-02), object model (CLS-03, 04, 12, 14), inheritance (CLS-07).
