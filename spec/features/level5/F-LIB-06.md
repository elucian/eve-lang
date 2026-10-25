# F-LIB-06 Time and dates

`now`, parse, format, zones, durations.

## Built

-  the zone data (M0.1) and the values `Zone` and `DateTime`, the conversion of local time, the zone letters of the patterns, `local_zone!` and `today!(zone)` (D2).
-  the zone of the machine on Windows is the IANA zone of its Windows zone name (CLDR `windowsZones`, TD-79).
-  patterns for `Date`, `Time` and `Instant` (D3: `format`, `parse`, placeholders), including ISO 8601 text with an offset: `time.parse("2020-01-02T00:00:00Z", "yyyy-MM-dd'T'HH:mm:ssX")`.
-  durations (D0), dates and times of the day (D1: calendar, fields, month arithmetic, ISO weeks).
- The zone lookups read the spans of every zone from memory (tables `zone_span` and `zone_kind`, to the year 2100; the Eve code of `zone` answers beyond it).

## Missing

Nothing.
