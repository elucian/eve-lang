# generator: the program that joins the spec, the tests and the manual

Three parts of the repository are kept apart on purpose:

| Part | Holds | May name |
|---|---|---|
| `spec/` | the language: rules, data tables, and the **features** (`spec/features/`) | only itself |
| `test/` | the tests and, per suite, a tracking file `test/<suite>/<suite>.json` | the spec (the field `features` of a test, and `** spec:` lines) |
| `manual/` | what a user reads | neither the spec nor the tests |

Only `generator/` reads both the spec and the tests, so it is the one place where they meet. The manual is made from them and is independent of both: its pages link to no spec page and no test, and a distribution ships the manual alone.

## Commands

```
python generator/evegen.py all [--check]                 index + manual
python generator/evegen.py manual [--out DIR] [--check]  the pages of the manual
python generator/evegen.py index [--check]               spec/spec.json
python generator/evegen.py check [-v]                    the rules between spec, tests and manual
python generator/evegen.py status [level]                features and tests in a few lines
```

`--check` writes nothing and exits 1 when something is out of date. `--out DIR` writes the manual to a folder (the distribution) and reads the hand-written text from `manual/`.

## What it reads

- `spec/features/level1.json` .. `level7.json`, `all.json`: the features of each level (`id`, `name`, `status`, `summary`, `doc`, `spec`) and `spec/features/<level>/<id>.md`, the page of each feature. The schema is `spec/schema/features.schema.json`.
- `test/<suite>/<suite>.json` for the levels and the special suites (`smoke`, `bytecode`, `scaffold`): written by `script/runtest.py`. A test names the features it checks in `features`. The schema is `spec/schema/tests.schema.json`.
- `spec/lexical/*.json`: keywords, operators and delimiters.
- `test/bmark/history.json` and the `** perf:` lines of `test/bmark/*.eve`: the benchmarks.
- `code/<component>/doc/` and `drivers/<name>/doc/`: the user documents of the components, copied into the manual.

## What it writes

| Output | Made from |
|---|---|
| `spec/spec.json` | every page of the spec: title, status, summary, size and the sections with their line, so a program reads one section with an offset and a limit; the data files; the feature files; the features that refer to each page |
| `manual/features.md`, `tests.md`, `performance.md` | **template pages** (`generator/templates/`): made when missing; afterwards only the `<!-- GEN:name -->` blocks are written again and the hand-written text around them is kept |
| `manual/levels/levelN.md`, `all.md` | the features of the level with their stage and text, each with a short example from a passing test, and what it prints (generated whole) |
| `manual/reference/keywords.md`, `operators.md`, `delimiters.md` | `spec/lexical/*.json` (generated whole) |
| `manual/<component>/`, `manual/drivers/<name>/` | a copy of the `doc/` folder |

The stage of a feature in the manual comes from its status: `done` is *validated*, `partial` is *drafted*, `open` is *planned*. Decision ids, paths of the repository and spec anchors are dropped from the text that goes into the manual.

## What `check` verifies

- every feature has a page with text, the ids are unique and well formed, and the `spec` references name pages and anchors that exist;
- every feature id named by a test exists; every test of a tracking file has a source file and every test file is in its tracking file;
- the spec names no design document, no decision, no question and no test; the manual links to no spec page and no test;
- `spec/spec.json` and the generated pages of the manual are up to date.

Warnings (`-v`): a `done` feature that no test names, a test that names no feature.

## Adding a feature

1. Add the feature to the file of its level in `spec/features/` (id, name, status, summary, `doc`) and write its page.
2. Write the test, and put the feature id in the `features` of the test in its tracking file (the runner keeps the field when it rewrites the file).
3. `python generator/evegen.py all`, then `python generator/evegen.py check`.

## Files

`evegen.py` the commands. `model.py` the readers. `manual.py` the pages. `build.py` writing and comparing. `specindex.py` the spec index. `check.py` the rules. `templates/` the template pages. Python 3, standard library only.
