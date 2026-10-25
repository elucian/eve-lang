# F-LIB-05 Data formats

JSON and CSV read/write, decode into records; later XML, Parquet. *State:* JSON, JSON lines, CSV (options, rejects, encodings) and fixed-width text work; XML and Parquet are not done.

## Missing

- Built: round trips of CSV and JSON records (e153); the write side of TXT is tested by e37 and e82.
- XML and Parquet move to the backlog unless the author asks.
