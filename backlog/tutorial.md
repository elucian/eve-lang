# Tutorial backlog

Items about the wording and layout of tutorial pages, moved here from `design/issues/` on 2026-10-20 (the tutorial is rank 10 of the order, D-194). Nothing here needs the author's answer; each is applied when the page is worked on. A language question never goes here: it is a `Q-nnn` in `design/decision/`.

| Id | Page | What | Source |
|---|---|---|---|
| TB-1 | `classes.html` | Split the page: classes (declaration, members, constructors, inheritance, traits) on one page, generics and Optional on their own next to collections (the split of D-091 did part of it: check what is left) | CLS-I1 |
| TB-2 | `classes.html` | One member table: kind (class property, class method, constructor, destructor, object attribute, object method), where declared, keyword, public form, access syntax, has `@self` | CLS-I2 |
| TB-3 | `option.html` | The page is not linked from `index.html`; decide its place in the topic order, or fold it into the page of operators. Add the ASCII table once OPT-01 is answered | OPT-03 |
| TB-4 | `strings.html` | Review the interpolation codes and examples against `spec/lexical/lexical.md` (interpolation: a name or a literal in braces, format after `%`) | COL-16 |
| TB-5 | `compiler.html` | The "Conformance Levels" section lists three levels with `a01_`, `b01_`, `c01_` files; rewrite it from `test/readme.md` and `design/version_map.md` (levels 1 to 7, a `status.json` per level), and say that `script/runtest.py --eve <path>` tests any implementation and list the exit codes (D-009, D-010) | CMP-02, CMP-F3 |
| TB-6 | `processing.html` | Command-line parameters: `-p` and `--param`, help generated from the comments above `main` (author's answer to PRC-10). The VM side is F-STR-05 (`partial`); the manual side is `manual/usage.md`, which does not describe it yet | PRC-10 |
| TB-7 | `command.html` | After CMD-04 and CMD-05 are answered: remove the sentence about `export`, use `$OS_PWD`, show `os.run!` with `cwd`, `status` and `out` for the exit status and the captured output | CMD-02 to CMD-06 |
| TB-8 | `datetime.html` | The `Date` type exists (`spec/library/data-language.md#time-types`); the era field asked for in TYP-19 is not specified. Mention it as "not in 0.4" or ask again | TYP-19 |
