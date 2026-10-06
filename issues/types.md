# Issues: types.html

Page: `tutorial/types.html` (about 1,320 lines after the split). Reviewed 2026-09-28. Retired 2026-10-06: TYP-I1 (declined: postponed), TYP-I2 (done: Date, Time, Duration and Quick Format are now `datetime.html`, "Eve Date and Time"). How to answer: [README](README.md).

## Questions

### TYP-19 Date literals
The page gives three forms: functions `ymd()`, `dmy()`, `mdy()`; `"2023/06/15" as YMD`; and a constants table with `YDM` = `YYYY/DD/MM`. It mentions an `era_label` (CE/AD) without syntax, and `{year: 1066, month: 10, day: 14}` creates an object, not a `Date`. Which form is Eve 0.1?
**Answer:** Make an invetion. I will review your proposal. I suggest Date to be ab object, add a new field: era
Status: proposed (Date object with an era field, written on the page as a proposal)

## Spec additions once answered

- `spec/semantics/types.md`, `types.json`: native and primitive types, variants, subtypes, inference, coercion (D-032, D-036).
- `spec/lexical/lexical.md`: numeric, Unicode, symbol, string, date/time/duration literals (D-032; TYP-19 is open).
