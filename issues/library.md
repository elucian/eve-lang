# Issues: library.html

Page: `tutorial/library.html` (217 lines, two `h1`: "Standard Library" and "System Library").
Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### LIB-01 Built-ins for 0.1
The standard library table lists string functions (`length`, `count`, `truncate`, `fill`, `erase`,
`find`, `replace`, `parse`, `trim`, `left`, `right`, `center`, `indent`, `pad`). Other pages use
`format`, `floor`, `ceiling`, `round`, `random`, `sqrt`, `sum`, `type`, `split`, `join`. Which
built-ins must the VM provide in 0.1? Are the string ones functions (`trim(s)`), methods
(`s.trim()`), or both (COL-20)?
**Answer:** Both. If we can we implement routines.
Status: open

### LIB-02 Mutating string functions
Strings are immutable (collections.html), but `truncate`, `fill` and `erase` "reduce the
capacity", "replace all characters". Do they return a new string?
**Answer:** _(open)_
Status: open

### LIB-03 `read`
Declared `read (String: prompt) => String;` (type before name, a result), but used as a statement:
`read (v, "input v:");` (an output variable). Which form?
**Answer:** _(open)_
Status: open

### LIB-04 `write` and `print`
`write` is declared as `routine .write(String * args, Logic:eol=True, String:sep=" ")` (type before
name; `eol` defaults to True, so it adds a new line), and "write supports only strings". syntax.html:
`write` adds no new line, no separator, and prints numbers (`write (1,2)`). What are the exact rules
of `print` and `write`: arguments, separator, new line, types accepted? Is `wrp` a parameter?
(See D-029.)
**Answer:** _(open)_
Status: open

### LIB-05 Standard error
How does a script write to stderr? No statement or routine is given. The VM and the test runner
compare stdout and stderr separately.
**Answer:** _(open)_
Status: open

### LIB-06 Escapes `\n`, `\LF`, `\CRLF`
"Make a line break using an escape `\n` or `\r`", and "write string can contain `\LF`, `\CRLF`".
collections.html uses `&code;` escapes. Which escape syntax does a double-quoted string use?
(See D-019, COL-15.)
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### LIB-F1 Wrong content
- Two `h1` headings on one page → one `h1` ("Standard Library"), "System Library" as `h2`.
- A past replace turned "input"/"output" into "read"/"write" in the prose: "standard read is stream
  data going into a program", "writes its write data", "Not all programs generate write", "In this
  the program is silent". → standard input / standard output.
- The stderr example is `module test_error:` with `process main`, but modules have no process; it
  is a copy of control.html's while_demo and shows nothing about stderr.
- "write sting", "will cause write to not sent".
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### LIB-I1 Built-in table from the spec
Generate the built-in table from `spec/library/builtins.json`: name, signature, result, errors,
since version.
**Answer:** _(open)_

## Spec additions once answered

- `spec/library/builtins.md`, `builtins.json` (LIB-01..04).
- `spec/lexical/lexical.md`: string escapes (LIB-06).
