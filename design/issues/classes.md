# Issues: classes

Pages: `tutorial/objects.html`, `classes.html`, `partials.html`, `generics.html` (split on 2026-10-06, D-091). How to answer: [README](README.md). Triage of 2026-10-20: CLS-12 is closed (see the ledger in the README); CLS-I1 and CLS-I2 moved to `backlog/tutorial.md`; the six questions below are still open and each has a **Suggestion** to accept, change or reject on the `Answer:` line. A suggestion is not a decision.

## Questions

### CLS-09 Several type parameters
Generic classes are decided (`class Box(:T) = {item: T} <: Object is`, `new b := Box(:Integer)(5);`, `spec/syntax/declarations.md#traits-and-generic-classes`, tests d24 and e01 to e04). Not written anywhere: can a user class take several type parameters (`(:K, :V)`), and are the prefix forms `()Type`, `[]Type`, `{}Type`, `{}(K:V)` only the notation of the library collections?

**Suggestion (2026-10-20):** yes to several parameters, written in the same list as one (`class Pair(:K, :V) = {first: K, second: V} <: Object is`, used as `Pair(:String, :Integer)(...)`); the prefix forms stay notation of the library collections and are not available to user classes. First check whether `test/level5/e01` to `e04` already use two parameters in a function: the rule should be the same.

**Answer:** _(open)_

Status: open

### CLS-13 Property and method with the same name
The method example declares `set sum: Integer;` and `method .sum()`. May a property and a method share a name?

**Suggestion (2026-10-20):** no, a compile error (exit 65, "a property and a method of `Name` are both called `sum`"). Several methods may share a name (overloading, D-149), but an attribute and a method may not: `self.sum` and `self.sum()` would read alike on a page and the checker would have to guess. Needs one test in `test/level3`.

**Answer:** _(open)_

Status: open

### CLS-14 Destructor timing
The class body may declare `destructor(@self) is … return;` (`spec/syntax/declarations.md`, grammar `destructor`). When does it run? May it raise an error? **State of the VM:** no destructor is run today (`grep destructor code/evevm/src` finds nothing, and no test uses one), so this is a design question and a missing feature.

**Suggestion (2026-10-20):** it runs when the last reference is released, at the next safe point of the region (D-151), and for what is left at the `done` of the job or the process; objects freed together run in reverse order of creation. A destructor may not raise: an error in it is written as a warning to the log and the free goes on. Objects that only the tracing collector finds (cycles) get their destructor when it frees them. A test `c4x_destructor` would fix the order.

**Answer:** _(open)_

Status: open

### CLS-15 Adopting a trait outside the class
D-039: a class adopts traits in the inheritance list. May a type adopt a trait after its declaration, in another module (`Integer` adopting `Printable`)? `spec/syntax/declarations.md` already says: "not in version 0.3 … version 0.4".

**Suggestion (2026-10-20):** keep it for version 0.4 as written, with the rule of the extension methods (`spec/semantics/modules.md#extension-methods`): the adoption is made in a module and is visible only where that module is imported, so two libraries cannot clash. The form (keyword, position) is yours to give; none is proposed here.

**Answer:** _(open)_

Status: open

### CLS-16 Library traits
Which traits does the library define, with which required and provided methods? **Largely answered:** `spec/syntax/declarations.md#traits-and-generic-classes` lists `Iterable(:T)`, `Stream(:T) <: Iterable(:T)`, `Comparable` (`compare`) and `Printable`. What remains is plan step S5.1a: they exist in the specification but not as Eve source.

**Suggestion (2026-10-20):** close the question and keep S5.1a as the work item: write the four traits as Eve files in `lib/sys/` (checked by `script/libcheck.py`) so that they are ordinary traits and not names known by the checker.

**Answer:** _(open)_

Status: open

### CLS-17b Hidden state in an abstract class
May a partial class that has no constructor hide a private attribute (`let self.state := 0;`)? With D-084 the constructor builds the object up the chain, so a class without a constructor is filled by name: where would the private attribute get its value?

**Suggestion (2026-10-20):** a private attribute needs a constructor in the same class: without one, the checker reports "private attribute `state` of `Name` has no constructor to set it" (exit 65). The simplest rule, and it keeps D-084 intact.

**Answer:** _(open)_

Status: open
