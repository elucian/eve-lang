# Issues: manifest.html

Page: `tutorial/manifest.html` (268 lines). Reviewed 2026-09-28. Encoding damage fixed the same day
(T1.4). How to answer: [README](README.md).

## Questions

### MAN-01 License answers Q-006
The page's License section sets: specification under CC BY-ND 4.0 with an explicit implementation
grant; trademark and compliance rules for the name EVE; reference code under "MIT or Apache 2.0".
Open question Q-006 (spec license) can be closed with this. Confirm, and pick one license for the
Zig VM in `evevm/` (the eve-lang repo is Apache 2.0). The text says reference code is "for example,
written in Go": change to Zig (D-006)?
**Answer:** Yes we change to Zig. 
Status: partly done: Go changed to Zig (applied); the license of the VM code is still open

### MAN-02 Static or gradual typing
"Eve utilizes a static type system" here; types.html: "Eve has a gradual-typing system … some type
errors are reported at compile time, some at run time". Which describes Eve?
**Answer:** Eve use gradual typing system. When I say static type system is not accurate. Is gradual.
Status: done: gradual typing (applied)

### MAN-03 "Declarative 4th-generation language"
The page and index.html call Eve declarative (4GL), while most of the tutorial is imperative
(statements, loops, jobs). Keep "declarative", or describe it as an imperative scripting language
with declarative parts (ranges, builders)?
**Answer:** We have not design the declarative layer. You are right, Eve is a multiparadigm language. 
Status: done: "declarative 4GL" removed, multi-paradigm (applied)

### MAN-04 Eve, Bee and Hive
"EVE environment includes two languages, Eve and Bee." Does Eve 0.1 interact with Bee at all
(calling Bee modules)? If not, mark the architecture section as a long-term vision.
**Answer:** Remove all refferences to Bee and Hive, we will make EVE stand-alone machine, not depending on other languages or libraries. We build from scratch "battery included" approach.
Status: done: Bee and Hive removed (applied)

## Fixes (applied unless you write "no")

### MAN-F1 Wrong content
- Inspirations differ in three places: "Ruby, Python, Go and Java", "Ruby and Ada", "Java, C++, Ada,
  Pascal, and Ruby". Use one list.
- "It mitigates null pointer exceptions by employing boxed values and zero values", but `Null`
  exists for strings, collections and objects.
- Fibonacci: `fib(0) = fib(1) = 1`, so `fib(5)` is 8, and the text calls it "the 5th Fibonacci
  number"; the comment says "Fibonacci routine" and "call fib rule" for a function; result
  `(y:Integer)` has no `@` (D-028); `driver fibonacci:` colon (D-012).
- "Our architecture aim to optimizes".
**Answer:** Old code, need replacement. Rule belong to Bee language, Eve use methods, functions and processes.

### MAN-F2 Authoring standard
"empowers developers", "seamless data movement", "high-signal processing", "Ready to dive deeper",
"unlock the full potential", "Who knows, maybe one day…".
**Answer:** Remove.

Fixes MAN-F1 and MAN-F2: done (applied 2026-10-01).
