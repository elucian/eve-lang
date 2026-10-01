# Issues: types.html

Page: `tutorial/types.html` (1,323 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### TYP-19 Date literals
The page gives three forms: functions `ymd()`, `dmy()`, `mdy()`; `"2023/06/15" as YMD`; and a
constants table with `YDM` = `YYYY/DD/MM`. It mentions an `era_label` (CE/AD) without syntax, and
`{year: 1066, month: 10, day: 14}` creates an object, not a `Date`. Which form is Eve 0.1?
**Answer:** Make an invetion. I will review your proposal. I suggest Date to be ab object, add a new field: era
Status: proposed (Date object with an era field, written on the page as a proposal)

## Improvements (applied only if you write "yes")

### TYP-I1 One literal table
Replace the three "Default Types" tables with one table: literal, form, default type, example,
after D-032. The spec's `types.json` generates it.
**Answer:** not agree, we postpone this. irrelevant
Status: declined (postponed)

### TYP-I2 Split the page
1,300 lines. Move Date, Time, Duration and Quick Format to a "Date and time" page (or to
library.html); keep types.html for the type system: native, primitive, composite, literals,
ranges, inference, variants.
**Answer:** agree split
Status: postponed (plan step)

## Spec additions once answered

- `spec/semantics/types.md`, `types.json`: native and primitive types, variants, subtypes, inference,
  coercion (D-032, D-036).
- `spec/lexical/lexical.md`: numeric, Unicode, symbol, string, date/time/duration literals
  (D-032; TYP-19 is open).
