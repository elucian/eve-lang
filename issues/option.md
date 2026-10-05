# Issues: option.html

Page: `tutorial/option.html` (94 lines, "Eve Optional Symbols"). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### OPT-01 Symbol → ASCII table
The page lists `≠ ≤ ≥ ÷ ≈ ø π ¬ ± ^ • ¶ § ∞ √ ∫ Ω µ ∆ ∂ ∑ ∏` and says "every one of them has an ASCII alternative", but gives none except `≠` = `<>`. Please give the ASCII form of each, for example `≤` `<=`, `≥` `>=`, `÷` `/`, `¬` `not`, `π` `PI`?, `√` `sqrt`?, `∞` ?. Which have no meaning in 0.1 (`¶`, `§`, `∫`, `Ω`, `µ`, `∂`)? `^` is already ASCII.
**Answer:** _(open)_
Status: open

### OPT-02 Other symbols used by the tutorial
syntax.html uses `∅` (empty collection) and mentions `≡` (`eq`), `∈` (`in`); types.html uses `⊤`, `⊥`, `∧`, `∨`. Are any of these accepted by the lexer?
**Answer:** _(open)_
Status: open

### OPT-03 Not in the index
option.html is not linked from index.html (T1.7). Where does it belong in the topic order?
**Answer:** _(open)_
Status: open

## Spec additions once answered

- `spec/lexical/operators.json`: an `unicode` field per operator (OPT-01, 02).
