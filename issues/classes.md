# Issues: classes.html

Page: `tutorial/classes.html` (911 lines, `<title>` "Eve Classses"). Reviewed 2026-09-28, revised 2026-10-01. How to answer: [README](README.md).

Retired 2026-10-06: CLS-10 (a bare call is a valid statement, decision_level1 line 540; only mutations need `let`), CLS-11 (`type(x)` in lower case, D-071 TYP-16; the page now uses it), CLS-17 points 1 to 3 (constructor `=> (@self)` and `let self := Object();`, D-084; chainable methods write `=> (@self)`, D-084), CLS-F1 to F4 (comments, wrong examples, typos, authoring text: applied; the title is "Eve Classes").
Still open of CLS-17 (renamed CLS-17b below).

Answered and applied: class forms, public and private members, constructor and `@self`, calling another constructor (D-036); multiple inheritance and unimplemented partial methods (D-039, proposed). The constructor and destructor now live inside the class body (D-036), a class closes with `end Name;` (D-037).

## Questions

### CLS-09 Generic syntax
Classes: `class GenericClass(:T) <: SuperType is`, instantiated as `new GenericClass(:Integer)(args)`. Collections: prefix forms `()Type`, `[]Type`, `{}Type`, `{}(K:V)`. Are both notations kept? Can a user class take several type parameters (`(:K, :V)`)?
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

### CLS-17b Hidden state in an abstract class
May a partial class that has no constructor hide a private attribute (`let self.state := 0;`)? With D-084 the constructor builds the object up the chain, so a class without constructor is filled by name: where would the private attribute get its value?
**Answer:** _(open)_
Status: open

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
