# Issues: syntax.html

Page: `tutorial/syntax.html` (1,329 lines, 33 sections). Reviewed 2026-09-28 against the 49 `.eve` files in `demo/`, `pattern/` and `test/`. How to answer: [README](README.md).

Applied 2026-09-28 from the answers below: `--` comments → `**` (138 in `.eve` files, 249 in the Eve code blocks of 14 tutorial pages); `!=` → `<>` (10 in `.eve` files, 5 in pages); test drivers renamed `a01_driver()`, `a02_comments()`, `a03_print()`. The page prose still describes the old rules; it is rewritten once all questions here are answered.

## Specification questions (before writing `spec/`)

The page is done (2026-09-28). These answers decide how the lexical part of the spec is written: `spec/lexical/lexical.md`, `keywords.json`, `operators.json`, `delimiters.json` (plan S2.2–S2.6).

### SPEC-01 Active or reserved keywords
The table has 115 words (D-044). Many belong to database or later features (`alter`, `analyze`, `ascend`, `cursor`, `fetch`, `commit`, `rollback`, `select`, `insert`, `limit`, `offset`, `trial`, …). `keywords.json` gives each word a `status`: `stable` (used in 0.1) or `reserved` (not usable as a name, no meaning yet). Proposal: control, declaration, region and operator words are `stable`; database and unused words are `reserved`. Agree, or mark words yourself?
**Answer:** Agree
Status: answered, spec pending

### SPEC-02 Contextual keywords
`option`, `to`, `one`, `all`, `any`, `other`, `error` have a meaning only inside certain statements. Are they reserved everywhere (never a variable name), or contextual (usable as names elsewhere)? Contextual words make a lexer simpler for users but a parser harder. (Q-002)
**Answer:** everywhere reserved
Status: answered, spec pending

### SPEC-03 Free scripts
A file starting with `#!` holds sequential statements without `driver` or `process`. May it also declare globals, functions and classes? Does it end with `return;`, or at the end of the file?
**Answer:** this kind of script end at end of file, no return the return belong to process, method, function. This kind of script do not have functions or methids but it can have control statements, like loops and if statements but no jobs. Jobs are only in processes.
Status: answered, spec pending

### SPEC-04 String interpolation
The page now says `"…{name}…"` inserts a value in every double-quoted string, and `\{` writes a literal brace. Other pages use `?` with `#` placeholders (`"#s" ? x`). For the lexer: is `{…}` in a string always interpolation (so the lexer must split the string), and may `{…}` hold an expression or only a name? (D-032, COL-16)
**Answer:** {} can hold one variable name, no expressions.
Status: answered, spec pending

### SPEC-05 Indentation
Is indentation checked (an error when wrong) or a style rule? The lexer needs this now:
significant indentation adds INDENT/DEDENT tokens. (D-031, D-041: everything between a header and its `end name;` is indented by 2 spaces.)
**Answer:** Yes indentation is mandatory and is done with 2 spaces not with tabs.
Status: answered, spec pending

### SPEC-06 Spec license
MAN-01: the manifest sets CC BY-ND 4.0 for the specification, with an implementation grant. `spec/index.md` needs it. Confirm (this closes Q-006)?
**Answer:** Yes the license is establish in tutorial, each compiler has it's own license but it can't change the specification without contribution to Sage-Code specification.
Status: answered, spec pending

## Spec additions once answered

- `spec/lexical/lexical.md`: comments (D-011, D-014, D-019), identifiers (D-012, D-019), strings, sigils (D-017).
- `spec/lexical/operators.json`: D-013, D-017.
- `spec/syntax/regions.md`: `driver`, `process`, one scope per script, block closers (D-015, D-034, D-037, D-041, D-043).
