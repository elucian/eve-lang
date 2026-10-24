# F-LIB-06 Time and dates

`now`, parse, format, zones, durations.

## Missing

- Built: the zone data (M0.1) and the values `Zone` and `DateTime`, the conversion of local time, the zone letters of the patterns, `local_zone!` and `today!(zone)` (D2).
- The zone of the machine on Windows is a fixed offset (TD-79).
- Built: patterns for `Date`, `Time` and `Instant` (D3: `format`, `parse`, placeholders), including ISO 8601 text with an offset: `time.parse("2020-01-02T00:00:00Z", "yyyy-MM-dd'T'HH:mm:ssX")`.
- Built: durations (D0), dates and times of the day (D1: calendar, fields, month arithmetic, ISO weeks).
