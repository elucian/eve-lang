# F-LNG-13 Data types for ETL

Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid.

## Missing

- Built: `Duration` (D0), `Date` and `Time` (D1), `Zone` and `DateTime` (D2), `Rational`, `Complex`, and `Bytes` (D4: the value, hex and Base64, slices, search, `fs.read_bytes!`; tests e139 to e141). `Uuid` (D5: parse, canonical text, versions 3, 4, 5 and 7, namespaces, `instant`; tests e142 to e144; the SQL and JSON mappings are TD-86). `T?` is D6.
- One test per type and per conversion (the SQL columns of `Date`, `Time`, `Duration`, `DateTime` and `Zone` are written and read for SQLite only: TD-74).
