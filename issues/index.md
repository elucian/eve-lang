# Issues: index.html

Page: `tutorial/index.html` (191 lines: the topic list). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### IDX-01 Topic order
Current order: manifest, syntax, types, topology, multitasking, functions, classes, collections, control, processing, algorithms, library, command, databases, compiler. Routines are introduced in multitasking (5th, was concurrency) but used from types (3rd) on; control flow (9th) comes after classes and collections, whose examples use loops. Proposed: manifest, syntax, types, control, functions ,routines , collections, classes, topology, processing, multitasking, library, command, option, algorithms, databases, compiler. Accept, or give your order?
**Answer:** Accepted
Status: open

### IDX-02 What EVE stands for
The page says "Effective Virtual Environment". Is EVE an acronym (then the name is written "EVE"), or a name ("Eve")? Pages mix both.
**Answer:** EVE is the machine name, "eve" is the language name, "Eve" is for beginning of statement only.
Status: open

## Fixes (applied unless you write "no")

### IDX-F1 Topic list
- "guides you through 14 essential topics": the list has 15, 16 with option.html.
- option.html is not linked.
- The certification row reuses `data-topic="databases"` (T1.7).
- "modern, declarative 4th generation" (see MAN-03).
**Answer:** fix obvious
