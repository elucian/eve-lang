# Issues: classes.html

Page: `tutorial/classes.html` (911 lines, `<title>` "Eve Classses"). Reviewed 2026-09-28, revised 2026-10-01. How to answer: [README](README.md).

Answered and applied: class forms, public and private members, constructor and `@self`, calling another constructor (D-036); multiple inheritance and unimplemented partial methods (D-039, proposed). The constructor and destructor now live inside the class body (D-036), a class closes with `end Name;` (D-037).

## Questions

### CLS-09 Generic syntax
Classes: `class GenericClass(:T) <: SuperType is`, instantiated as `new GenericClass(:Integer)(args)`. Collections: prefix forms `()Type`, `[]Type`, `{}Type`, `{}(K:V)`. Are both notations kept? Can a user class take several type parameters (`(:K, :V)`)?
**Answer:** _(open)_
Status: open

### CLS-10 Bare call statements
syntax.html: "each statement starts with a keyword". This page has bare calls:
`ClassName.change(10);`, `myCircle.print();`, `num32.add(10);`. D-036 added bare mutations (`a := a + 1;`). Are bare method calls statements, or must they use `call`? (`call` is for shell commands, D-025.)
**Answer:** _(open)_
Status: open

### CLS-11 `Type(x)` or `type(x)`
This page uses `Type(myList)`; types.html uses `type(x)`. Which name is the built-in?
**Answer:** _(open)_
Status: open

### CLS-12 Dynamic objects
"Each object can have the same or a different structure, due to the dynamic nature of Objects", and `new Object(attribute1: value1, …)` "binds values to new attributes that are not declared". Can any object gain attributes at run time, or only instances of `Object` itself? Is this in 0.1 ("a minor feature")?
**Answer:** _(open)_
Status: open

### CLS-13 Property and method with the same name
The method example declares `set sum: Integer;` and `method .sum()`. May a property and a method share a name?
**Answer:** _(open)_
Status: open

### CLS-14 Destructor timing
The class body may declare `destructor(@self) is … return;` (it replaced the `release` region). When does it run: when each object is freed, when its last reference goes away, or when the class is unloaded? May a destructor raise an error?
**Answer:** _(open)_
Status: open

### CLS-15 Adopting a trait outside the class
D-039: a class adopts traits in the inheritance list. May a type adopt a trait after its declaration, in another module (`Integer` adopting `Printable`)? That needs an extension form.
**Answer:** _(open)_
Status: open

### CLS-16 Library traits
Which traits does the library define (`Iterable`, `Comparable`, `Printable`), with which required and provided methods? (plan step S5.1a)
**Answer:** _(open)_
Status: open

### CLS-17 Constructor shape
(1) The constructor has two lists, `constructor(@self)(x, y)`, and a method has one,
`method area(@self)`. Keep the difference (it mirrors `new Number(:T)(args)`)? (2) Every constructor starts with `self := new Object();`. May the compiler create `self` from the superclass when the constructor does not assign it? (3) Chainable methods end with `return @self;`: keep it? (4) May a partial constructor-less abstract class hide a private attribute (`let self.state := 0;`)?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### CLS-F1 Comments against D-011
Indented `#` comments (`# Method to get the value`) and end-of-line `#` comments
(`num32.print();  # Output: …`) in the generic examples → `**`.
**Answer:** _(open)_

### CLS-F2 Wrong examples
- Point output: `p2 = {x:2, y:2}`, but `new Point()` uses defaults 0, 0; the printed format differs from `string()`.
- `num64.multiply(2)` on `9223372036854775807` expects `18446744073709551614`, which overflows i64.
- Optional example: `intProcessor.process(:Integer,5));` has an extra `)` and wrong arguments.
- `class ElementType = {a,b,c: Integer} <: DataSet;` describes a record; should derive from `Object`.
- `print myList ** ({1,2,3},{7,8,9})` is missing `;`.
- Prose: complementary operators "is not" and "!=" → `<>`.
- `<title>` "Eve Classses", `h1` "Eve Objects": use one name.
**Answer:** _(open)_

### CLS-F3 Typos
descendents, Employe/Emplyes, complementar, inherite, alwais, metods, necesary, propetyes, optonal, repesents, bas-class, bihaviour, SupetType, "and and", instantes, simpe, "more to left unexplained".
**Answer:** _(open)_

### CLS-F4 Authoring standard
"handle nullable values elegantly", "Benefits of Method Chaining" (generic advice), "inspired from Banyan Tree in Florida", "Eve implements all 4 OOP principles" (stated twice).
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### CLS-I1 Split the page
Classes (declaration, members, constructors, inheritance, traits) on this page; generics and Optional on their own page, next to collections.
**Answer:** _(open)_

### CLS-I2 Member table
One table: member kind (class property, class method, constructor, destructor, object attribute, object method), where declared, keyword, public form, access syntax, has `@self`.
**Answer:** _(open)_

## Spec additions once answered

- `spec/syntax/declarations.md`: class, trait, constructor, destructor, method, partial method, generic (D-036, D-037, D-039; CLS-09).
- `spec/semantics/`: visibility (D-035), object model and inheritance (D-036, D-039; CLS-12, 14, 17).
