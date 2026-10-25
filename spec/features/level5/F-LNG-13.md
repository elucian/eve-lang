# F-LNG-13 Data types for ETL

Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid.

## Missing

- Built: `Duration` (D0), `Date` and `Time` (D1), `Zone` and `DateTime` (D2), `Rational`, `Complex`, and `Bytes` (D4: the value, hex and Base64, slices, search, `fs.read_bytes!`; tests e139 to e141). `Uuid` is undefined today (D5); `T?` is D6.
- One test per type and per conversion (the SQL columns of `Date`, `Time`, `Duration`, `DateTime` and `Zone` are written and read for SQLite only: TD-74).
