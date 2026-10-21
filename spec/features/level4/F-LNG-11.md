# F-LNG-11 Traits, abstract classes, generics

`trait`, required methods, abstract classes, `class Name(:T)` with `Box(:Integer)(5)`, constraints `(:T <: Comparable)`, library traits `Iterable`, `Stream`, `Comparable`, `Printable`. Moved from Version 0.2 to Level 4.

*Partial:* traits, abstract classes, generic classes with erased type arguments and the library traits work; a constraint is not checked yet, generic functions wait for Version 0.4.

## Missing

- The constraint `(:T <: Comparable)` is not checked: a violation must be a compile error, exit 65.
- Generic functions wait for Version 0.4 (backlog).
