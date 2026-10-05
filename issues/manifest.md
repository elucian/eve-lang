# Issues: manifest.html

Page: `tutorial/manifest.html` (268 lines). Reviewed 2026-09-28. Encoding damage fixed the same day (T1.4). How to answer: [README](README.md).

## Questions

None open (MAN-01 to MAN-04 retired 2026-10-03).

## Fixes (applied unless you write "no")

### MAN-F1 Wrong content
- Inspirations differ in three places: "Ruby, Python, Go and Java", "Ruby and Ada", "Java, C++, Ada, Pascal, and Ruby". Use one list.
- "It mitigates null pointer exceptions by employing boxed values and zero values", but `Null` exists for strings, collections and objects.
- Fibonacci: `fib(0) = fib(1) = 1`, so `fib(5)` is 8, and the text calls it "the 5th Fibonacci number"; the comment says "Fibonacci routine" and "call fib rule" for a function; result `(y:Integer)` has no `@` (D-028); `driver fibonacci:` colon (D-012).
- "Our architecture aim to optimizes".
**Answer:** Old code, need replacement. Rule belong to Bee language, Eve use methods, functions and processes.

### MAN-F2 Authoring standard
"empowers developers", "seamless data movement", "high-signal processing", "Ready to dive deeper", "unlock the full potential", "Who knows, maybe one day…".
**Answer:** Remove.

Fixes MAN-F1 and MAN-F2: done (applied 2026-10-01).
