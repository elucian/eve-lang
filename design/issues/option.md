# Issues: option

Page: `tutorial/option.html` ("Eve Optional Symbols"). How to answer: [README](README.md). Triage of 2026-10-20: OPT-03 (the page is not in the index) moved to `backlog/tutorial.md`. Two questions are left; the suggestion is not a decision.

## Questions

### OPT-01 Symbol → ASCII table, and OPT-02 other symbols
The page lists `≠ ≤ ≥ ÷ ≈ ø π ¬ ± ^ • ¶ § ∞ √ ∫ Ω µ ∆ ∂ ∑ ∏` and says "every one of them has an ASCII alternative", giving none but `≠` = `<>`. The tutorial also uses `∅`, `≡`, `∈`, `⊤`, `⊥`, `∧`, `∨`. Which does the lexer accept? Today none: `spec/lexical/operators.json` has no `unicode` field and the lexer reads ASCII operators only.

**Suggestion (2026-10-20):** the lexer stays ASCII only; the symbols are tutorial notation, shown next to the operator they stand for, and never accepted as source. Those that match an operator get a row in a table on the page: `≠ <>`, `≤ <=`, `≥ >=`, `÷ /`, `¬ not`, `∧ and`, `∨ or`, `∈ in`, `≡ eq`, `⊤ true`, `⊥ false`, `∅ []` or `{}`. The others (`≈ ø π ± • ¶ § ∞ √ ∫ Ω µ ∆ ∂ ∑ ∏`) have no meaning in Eve and are removed from the page. Nothing changes in `operators.json`.

**Answer:** Agreed. Also for this special case, remove them from the tutorial immediatly. Remove this page option.md after the option.html is removed. Cleanup.
