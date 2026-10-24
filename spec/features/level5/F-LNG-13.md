# F-LNG-13 Data types for ETL

Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid.

## Missing

- Built: `Duration` (D0), `Date` and `Time` (D1), `Zone` and `DateTime` (D2), `Rational`, `Complex`. `Bytes` and `Uuid` are undefined names today (steps D4, D5).
- One test per type and per conversion (the SQL columns of `Date`, `Time`, `Duration`, `DateTime` and `Zone` are written and read for SQLite only: TD-74).
