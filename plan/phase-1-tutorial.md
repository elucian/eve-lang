# Phase 1 — Tutorial

Goal: a correct, consistent tutorial that teaches Eve and points compiler authors to the spec.
Files live in `tutorial/` (scl repo; commit with `git -C tutorial …`). After every step:
`bee-ed balance` on the touched pages, then `npm run build` in `C:\Users\eluci\sage-code\scl`.

Baseline measured 2026-09-28: 17 pages, 14 sidebar JSON files, all sidebar links resolve.

### T1.1 Add the compiler implementation page `[x]`
2026-09-28: `compiler.html` + `data/compiler.json` (single-root sidebar), linked from
`index.html` (topic 15; Certification renumbered 16), from the "Read next" of `databases.html`,
and from `sitemap.xml`. `npm run build` and `npm run check` pass, with no warnings for this page.
- Keep it in step with the spec: when phase 6 adds the compiler kit, link it from this page.

### T1.2 Remove stray files `[!]` → Q-003
- `quiz.txt`, `output.log`, `databases.md` are not pages. Delete them, or salvage the quiz
  questions into a quiz page, according to Q-003.
- Done when: `ls tutorial` shows only `*.html`, `data/`, `img/`, `js/`.

### T1.3 Fix unbalanced HTML `[ ]`
- 7 pages fail `bee-ed balance`: option (stray `</div>`), syntax (unclosed `<tr>`), topology
  (2 unclosed `<th>`, 2 unclosed `<p>`), collections, functions, databases, concurrency.
- Fix the real error, not the cascade: tag counts pinpoint it (`grep -o '<tr[ >]' | wc -l`
  versus `grep -o '</tr>' | wc -l`).
- Done when: every page reports `balance …: OK`.

### T1.4 Fix encoding damage `[ ]`
- `manifest.html` has mojibake (`â€”` for an em dash, 2 places). Scan all pages for `â€`,
  `Ã`, `Â` and replace them with the intended character.
- Done when: `bee-ed search 'â€|Ã.|Â' tutorial` finds nothing.

### T1.5 Heading structure and sidebars `[ ]`
- scl rule: one `h1`; every `h2` has `h3` children; sidebar JSON mirrors this.
- Sidebar shape (checked by `npm run check` in scl): a **single root**, the page title (`h1`),
  whose `children` are the `h2` chapters, each with its `h3` sections as `children`.
  `data/compiler.json` is the reference; the other 14 Eve sidebars are still flat and each
  triggers a "not a single-root folder" warning.
- Measured: `library.html` has 2 `h1`; 57 `h2` sections across 14 pages have no `h3`.
- Per page: add real `h3` subsections (don't insert empty ones), then regenerate
  `data/<page>.json` from the headings with a script in `temp/`. Hand edits drift.
- Done when: `npm run check` shows no `projects/eve/data` warnings, and every page has one `h1`.

### T1.6 Keyword table from the spec `[ ]` (after S2.4)
- Replace the hand-made table in `syntax.html#keywords` with one generated from
  `spec/lexical/keywords.json`, grouped by category.
- Same for the operator tables (`syntax.html#operators`) after S2.5.

### T1.7 Navigation consistency `[ ]`
- "Read next" links mix `/projects/eve/classes/` and `.html` forms; use the `.html` form
  that `index.html` uses.
- `index.html`: the Certification row reuses topic number and `data-topic="databases"`. Give it
  its own number and topic id; check `sage.js` progress tracking before renaming ids.
- Chain every page to the next topic in index order; the last one returns to the index.

### T1.8 Refresh `template.html` `[ ]`
- `template.html` predates the sidebar layout (no `<aside>`, no `<main>`). Rebuild it from a
  current page (`functions.html`) so new pages start correct.

### T1.9 Link tutorial to spec `[ ]` (as spec sections land)
- Under each `h2` that has a spec counterpart, add a short "Specification:" link to the
  Markdown file on GitHub (`https://github.com/elucian/eve-lang/blob/master/spec/…`).

### T1.10 Content review, one page per session `[ ]`
Order: syntax, types, topology, control, functions, classes, collections, processing,
concurrency, library, command, databases, algorithms, manifest, option.
For each page:
- Check every rule it states against the spec; mismatches go to `decisions.md`.
- Check that every example follows the grammar (from S3.6 on, run it through the parser check).
- Apply the scl authoring standard: factual headings, no promotional adjectives, pitfalls.
