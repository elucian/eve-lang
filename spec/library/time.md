# Time and dates

Status: **draft**, level 5. Step S15.50. Features: F-LNG-13, F-LIB-06. Built: `Duration`, `Date`, `Time`, `Zone` and `DateTime`, the operators, the patterns and the whole module `time` of this page (steps D0 to D3, tests e120 to e137); the zone data comes from the meta database ([meta.md](meta.md)).

The types of time and the module `time`. `Instant` and `time.now!()` exist today ([data-language.md](data-language.md#data-types)); this page adds `Date`, `Time`, `DateTime` and `Duration`, the zones, the operators, and the parse and format functions. Every value is exact: no type of time holds a `Real`, no operation rounds without saying so. All of them are small (16 bytes at most) and live inside a `Value`, so a `List` of a million dates is one block of memory.

## The types

| Type | Meaning | Range and unit | Zero value | Canonical text |
|---|---|---|---|---|
| `Date` | a day of the calendar, proleptic Gregorian (ISO 8601), no zone | `0001-01-01` to `9999-12-31`; a count of days | `1970-01-01` | `2026-10-24` |
| `Time` | a time of the day, no date, no zone | `00:00:00` to `23:59:59.999999`; microseconds | `00:00:00` | `08:30:00`, `08:30:00.5`, `08:30:00.000123` (the fraction in microseconds, trailing zeros cut) |
| `Instant` | a point on the line of time, UTC | microseconds since `1970-01-01T00:00:00Z` | `1970-01-01T00:00:00Z` | `2026-10-24T08:30:00Z` |
| `DateTime` | an `Instant` seen in a zone: a date and a time with an offset | as `Instant`, with a `Zone` | `1970-01-01T00:00:00Z` | `2026-10-24T11:30:00+03:00` |
| `Duration` | a length of time, positive or negative | microseconds, about ±292,000 years | `0s` | ISO 8601: `PT1H30M`, `PT0.25S`, `-PT5S`, `PT0S` (hours without limit, never days) |
| `Zone` | a time zone: a fixed offset or a named region | `Z`, `+03:00`, `Europe/Bucharest` | `Z` | the same text |

`Instant` and `DateTime` hold the same moment: the `DateTime` adds the zone for the fields (`hour()`, `day()`) and for the text. Two `DateTime` values are equal when their instants are equal, whatever the zone. `Date` and `Time` are what a database calls `DATE` and `TIME`; `Instant` and `DateTime` are `TIMESTAMP WITH TIME ZONE`.

## Literals

A duration literal is an integer followed at once by a unit: `us`, `ms`, `s`, `m`, `h` (`250ms`, `30s`, `2m`, `1h`). Its type is `Duration`, a count of microseconds; `30s + 5` is a compile error. `within`, `wait`, `$timeout` and `set_timeout` take a `Duration`, and still an `Integer` of milliseconds (the old form). There is no day unit: `5d` is a `Decimal`. A `Date`, a `Time` and a `DateTime` have no literal: they are made by `time.date(2026, 10, 24)`, `Date.parse("2026-10-24")` and so on, so a typing error in a date is an error of the run and not a new token.

## Operators

| Expression | Type | Meaning |
|---|---|---|
| `Instant + Duration`, `Instant - Duration` | `Instant` | a moment later or earlier |
| `Instant - Instant` | `Duration` | the time between two moments |
| `DateTime + Duration`, `DateTime - Duration` | `DateTime` | the same, in the same zone; the length is exact (an hour is 3,600 seconds across a change of summer time) |
| `DateTime - DateTime` | `Duration` | the time between the two instants |
| `Time + Duration`, `Time - Duration` | `Time` | wraps round the clock: `23:30 + 1h` is `00:30` |
| `Time - Time` | `Duration` | the time from the second to the first, in (-24h, 24h) |
| `Date + Integer`, `Date - Integer` | `Date` | a number of days |
| `Date - Date` | `Integer` | the number of days from the second to the first |
| `Duration + Duration`, `Duration - Duration`, `-Duration` | `Duration` | an overflow is `$err_overflow` |
| `Duration * Integer`, `Integer * Duration`, `Duration / Integer` | `Duration` | `/` rounds toward zero to the microsecond |
| `Duration / Duration` | `Real` | how many times |
| `==`, `<>`, `<`, `<=`, `>`, `>=` | `Logic` | on two values of the same type; `Instant` with `DateTime` compares the instants; `Date` with `DateTime` is a compile error |

Months and years are not a `Duration` (their length changes): they have functions, `time.add_months`, `time.add_years`. Any other combination is the error `cannot compare` or `operator + does not apply` (compile error when the types are known). A result outside the range of the type is `$err_overflow`.

## The module `time`

| Function | Result | Meaning |
|---|---|---|
| `now!()` | `Instant` | the clock (exists) |
| `today!(zone)` | `Date` | today's date in a zone; without an argument, in the zone of the machine |
| `date(y, m, d)` | `Date` | an invalid date (`2026-02-30`) is `$err_argument` |
| `clock(h, m, s)`, `clock(h, m, s, micro)` | `Time` | |
| `zone(text)` | `Zone` | `"Z"`, `"+03:00"`, `"Europe/Bucharest"`; an unknown name is `$err_argument` |
| `at_zone(instant, zone)` | `DateTime` | the same moment seen in a zone |
| `make(date, time, zone)` | `DateTime` | a local time in a zone; a time that does not exist (the hour skipped in spring) is `$err_argument`; a time that happens twice (autumn) takes the first |
| `year(x)`, `month(x)`, `day(x)` | `Integer` | of a `Date` or a `DateTime` (also as methods: `d.year()`) |
| `hour(x)`, `minute(x)`, `second(x)`, `micro(x)` | `Integer` | of a `Time` or a `DateTime` |
| `weekday(x)` | `Integer` | 1 for Monday to 7 for Sunday (ISO) |
| `day_of_year(x)`, `iso_week(x)`, `iso_year(x)` | `Integer` | |
| `date_of(dt)`, `time_of(dt)`, `instant_of(dt)`, `zone_of(dt)`, `offset_of(dt)` | | the parts of a `DateTime`; `offset_of` is a `Duration` |
| `add_months(d, n)`, `add_years(d, n)` | `Date` | the day is kept, or cut to the end of the month (`2026-01-31` + 1 month is `2026-02-28`) |
| `start_of(x, unit)` | same type | cuts to `"year"`, `"quarter"`, `"month"`, `"week"` (Monday), `"day"`, `"hour"`, `"minute"`, `"second"` |
| `end_of_month(d)`, `days_in_month(y, m)`, `is_leap(y)` | `Date`, `Integer`, `Logic` | |
| `months_between(a, b)`, `years_between(a, b)` | `Integer` | whole months or years from `a` to `b` |
| `seconds(x)`, `millis(x)`, `micros(x)` | `Real`, `Integer`, `Integer` | the length of a `Duration` in a unit |
| `format(x, pattern)` | `String` | the text of a value by a pattern |
| `parse(text, pattern)` | the type the pattern names | reads a text by a pattern; the text must fit the pattern fully |
| `sleep(d)` | none | waits a `Duration`; gives the baton to the other tasks (as the calls of `net`) |

`Date.parse(text)`, `Time.parse(text)`, `Instant.parse(text)`, `DateTime.parse(text)` and `Duration.parse(text)` read the canonical forms of the first table and also ISO 8601 (`2020-01-02T00:00:00Z`, `2020-01-02T03:04:05.678+02:00`, `20200102` is not accepted); `Duration.parse` reads `1h30m`, `90m`, `250ms`, `PT1H30M` (ISO). A text that does not fit is `$err_parse` (15), with the column.

## Patterns

A pattern is a text of letters, as in Unicode CLDR and Java, which is what a database or a spreadsheet user knows. `time.format(x, pattern)` writes a `Date`, a `Time` or an `Instant` (as UTC); `time.parse(text, pattern)` reads one; `Date.parse(text, pattern)`, `Time.parse(text, pattern)` and `Instant.parse(text, pattern)` read and insist on the type. The methods `d.format("dd/MM/yyyy")` are the same functions. In a placeholder the text after `%` is the pattern: `"{d % dd/MM/yyyy}"` (for these three types the number formats do not apply).

| Letters | Field | Writes | Reads |
|---|---|---|---|
| `yyyy` | year | at least 4 digits, `0001` | exactly 4 digits |
| `yy` | year of two digits | `26` | `70` to `99` are 1970 to 1999, `00` to `69` are 2000 to 2069 |
| `y` | year | the digits, no padding | 1 to 4 digits |
| `MM`, `M` | month number | `10`, `10` / `3` | two digits / one or two |
| `MMM`, `MMMM` | month name in English | `Oct`, `October` | the name, upper or lower case |
| `dd`, `d` | day of the month | `05`, `5` | two digits / one or two |
| `DDD`, `D` | day of the year | `005`, `5` | three digits / one to three |
| `EEE`, `EEEE` | weekday name in English | `Sat`, `Saturday` | the name; it must fit the date (`$err_parse` otherwise) |
| `HH`, `H` | hour 0 to 23 | `08`, `8` | two digits / one or two |
| `hh`, `h` | hour 1 to 12 | `08`, `8` | with `a` |
| `a` | `AM` or `PM` | `AM`, `PM` | `AM`, `PM`, any case |
| `mm`, `m` | minute | `05`, `5` | two digits / one or two |
| `ss`, `s` | second | `07`, `7` | two digits / one or two |
| `S` repeated 1 to 9 times | fraction of the second | the first digits of the microseconds (`SSS` is milliseconds, `SSSSSS` microseconds, more than 6 pad with zeros) | exactly that many digits, up to 6 |
| `ww`, `w` | ISO week of the year | `43` | not readable |
| `Q`, `QQ` | quarter of the year | `4`, `04` | not readable |
| `X`, `XX`, `XXX` | offset | `Z` (an `Instant` is UTC) | `Z`, `+03`, `+0330`, `+03:30`, `-05:00`: any form; the offset must be within 18 hours |
| `'text'` | text | the text; `''` inside is a quote | the same text |
| any other character | itself | itself | itself |

A letter that is not in the table is the error `$err_argument` (17) with the column; so are more than 9 repeated letters and an unclosed quote. A pattern has at most 48 parts. The zone letters `V` and `z` and the names of other languages come with the zones and the locales.

**Writing:** a letter of a date on a `Time`, a letter of a time on a `Date`, or `X` on a value without a zone is `$err_argument`.

**Reading:** the text must be used completely. A number must have the digits the letters ask for (`yyyy-MM-dd` does not read `2026-1-24`); two fields without a separator are read by their widths (`yyyyMMdd`). A text that does not fit is `$err_parse` (15) with the column; a date that does not exist (`2026-02-30`) is `$err_parse`. What the pattern names decides the type of `time.parse`: date letters only give a `Date`, time letters only a `Time`, a date, a time and an offset an `Instant` (the offset is subtracted, so the answer is UTC). A date and a time without an offset name no moment: `$err_argument` (the `DateTime` of the zones will read them). A pattern with `h` needs `a`; a pattern without a year, a month and a day (or a year and `DDD`) gives no `Date`.

```eve
new d := time.date(2026, 10, 24);
print d.format("EEEE, d MMMM yyyy");                         ** Saturday, 24 October 2026
print "{d % dd/MM/yyyy}";                                    ** 24/10/2026
print Date.parse("Sat, 24 Oct 2026", "EEE, d MMM yyyy");     ** 2026-10-24
print time.parse("2026-10-24 11:05:07+03:00", "yyyy-MM-dd HH:mm:ssXXX");   ** 2026-10-24T08:05:07Z
print time.parse("8:05 PM", "h:mm a");                       ** 20:05:00
```

## Zones

A `Zone` is the name of a region of the IANA time zone database (`Europe/Bucharest`), `Z` (no offset), or a fixed offset (`+03:00`). The rules of the regions are in the meta database that is built into the Eve machine ([meta.md](meta.md)), so every machine gives the same answer, with or without zone files of its own. A run reads the spans of every region once, into memory (the instants where the offset changes, with the daylight rule expanded to the year 2100), so a lookup is a binary search; an instant after 2100, or a zone written as an offset, is answered by the rule in Eve with the same result and more time. A `DateTime` is an `Instant` seen in a `Zone`: it keeps the instant (microseconds) and the zone.

| Function | Result | Meaning |
|---|---|---|
| `time.zone(text)` | `Zone` | a name of the database (case sensitive; a link such as `Asia/Calcutta` is accepted), `Z`, or an offset `+03`, `+0330`, `+03:30`, `-05:00` within 18 hours; anything else is `$err_argument`. `Zone.parse(text)` is the same with `$err_parse` |
| `time.at_zone(x, zone)` | `DateTime` | the same moment, seen in a zone; `x` is an `Instant` or a `DateTime`; `zone` is a `Zone` or its name |
| `time.make(date, time, zone)` | `DateTime` | the local date and time in a zone. A time the clock never shows (summer time starts: 03:30 on 29 March 2026 in Bucharest, or the day skipped by Samoa) is `$err_argument`; a time it shows twice (summer time ends) is the first one |
| `time.date_of(dt)`, `time_of(dt)`, `instant_of(dt)`, `zone_of(dt)`, `offset_of(dt)` | `Date`, `Time`, `Instant`, `Zone`, `Duration` | the parts of a `DateTime` |
| `time.local_zone!()` | `Zone` | the zone of the machine: the region named by the variable `TZ` or by the link `/etc/localtime` (on Windows: the IANA zone that the Unicode CLDR gives to the Windows zone of the machine, such as `Eastern Standard Time` for `America/New_York`) when the database knows it, else the offset in force now as a fixed zone |
| `time.today!(zone)` | `Date` | the date now in a zone; without an argument the zone of the machine |

The fields (`year`, `month`, `day`, `hour`, `minute`, `second`, `micro`, `weekday`, `day_of_year`, `iso_week`, `iso_year`) of a `DateTime` are the **wall-clock** fields in its zone; `format` and the placeholders write them. The text of a `DateTime` is the local date and time with the offset, `2026-07-01T15:00:00+03:00`, `Z` for no offset, and seconds in the offset when an old local mean time has them (`+01:44:24`); the name of the region is **not** in the text (the value keeps it: `time.zone_of(dt)`). Written in CSV and JSON, a `DateTime` is that text, and a `Zone` is its name or offset; read back, a `DateTime` has the offset as a fixed zone (`DateTime.parse("2026-07-01T15:00:00+03:00[Europe/Bucharest]")` keeps the region).

**Operators.** `DateTime + Duration` and `DateTime - Duration` give a `DateTime` in the same zone; the length is exact (23 hours between two midnights on a day that starts summer time). `DateTime - DateTime`, `DateTime - Instant` and `Instant - DateTime` give a `Duration`. `==`, `<>`, `<` ... compare the **instants**: two `DateTime` values in different zones are equal when they are the same moment, and a `DateTime` and an `Instant` compare too. A `DateTime` and a `Date` do not compare, and a `Zone` has only `==` and `<>` (by name: `Asia/Calcutta` is not `Asia/Kolkata`).

**Calendar functions in a zone.** `add_months`, `add_years` and `start_of` work on the wall clock and find the instant again: the date moves and the local time stays (`2026-01-31T10:00-05:00` plus a month is `2026-02-28T10:00-05:00`); when the result falls in a time the clock skips, it moves forward by the jump (`02:30` on 8 March 2026 in New York becomes `03:30-04:00`); when the clock shows it twice, the first is taken. `start_of(dt, "day")` is midnight of the wall clock, 23 or 25 hours after the day before on a day of change. `months_between`, `weekday` and the other functions of a `Date` take a `DateTime` and use its local date.

**Reading with a zone.** `time.parse(text, pattern, zone)`, `DateTime.parse(text, pattern)` and `DateTime.parse(text, pattern, zone)` give a `DateTime` when the pattern has `VV` (a zone in the text) or a zone is given; with `XXX` in the pattern and no zone, `DateTime.parse` gives a `DateTime` at that fixed offset and `time.parse` an `Instant`. If the text has both an offset and a zone, they must agree at that moment (`$err_parse`). A local time that does not exist in the zone is `$err_parse`; one that happens twice is the first. `DateTime.parse(text)` reads `2026-07-01T15:00:00+03:00`, `...Z`, a space for the `T`, and a trailing `[Europe/Bucharest]` that must agree with the offset.

The letters `VV` (zone name) and `z` (abbreviation: `EEST`, `EST`, `+05:30` for a fixed offset) are written for a `DateTime`; the letters `X`, `XX`, `XXX` write the offset of a `DateTime` (`+03`, `+0300`, `+03:00`; `Z` for none), and `VV` is read.

## Errors

An invalid argument (month 13, 30 February, a Time of 25 hours, an unknown zone) is `$err_argument` (17); a text that does not parse `$err_parse` (15); a result outside the range of the type `$err_overflow` (13); a division of a `Duration` by zero `$err_divide` (12).

```eve
new start := time.date(2026, 1, 31);
print time.add_months(start, 1);                  ** 2026-02-28
print start + 30;                                 ** 2026-03-02
print time.weekday(start);                        ** 6 (Saturday)
new t := Instant.parse("2026-10-24T08:30:00Z");
new bucharest := time.at_zone(t, time.zone("Europe/Bucharest"));
print bucharest;                                  ** 2026-10-24T11:30:00+03:00
print bucharest - t;                              ** PT0S
print t + 90m - t;                                ** PT1H30M
```
