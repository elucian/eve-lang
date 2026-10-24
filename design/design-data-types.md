# Design: the types for data (step S15.50)

Status: **plan, accepted by the author on 2026-10-24** (D-221: all proposals of section 6, the printed form of a `Duration` is ISO 8601, the zone data is built into the Eve machine). D0 is built (2026-10-24). Features: F-LNG-13, F-LNG-14, F-LIB-06. Pages of the specification (drafts): `spec/library/time.md` (Date, Time, DateTime, Duration, Zone, the module `time`) and `spec/library/bytes.md` (Bytes, Uuid). `Rational` and `Complex` of the same step are done (D-217, D-218).

## 1. Where we stand (audit, 2026-10-24)

- `Instant` exists: `Value.instant`, microseconds since the epoch, `Instant.parse`, canonical text, comparison; `time.now!()`; the readers of CSV, JSON and TXT convert it (`dlib.zig`, `instant.zig`).
- A duration literal `30s`, `10ms`, `2m`, `1h` is read by `Interp.durationMs` and is a plain `Integer` of milliseconds (D-144); `within`, `wait`, `sleep`-like calls and the `$timeout` variables take that integer. `5d` is a `Decimal`.
- `Date`, `Time`, `DateTime`, `Duration` (as a type), `Bytes`, `Uuid` and `Zone` are undefined names. `Bytes` and `Stream(:Bytes)` are named in the readers' specification but no value of that type exists (files are read as `String`, `fs.read_bytes!` is untested, TD-24).
- `T?` parses; the zero value is `null`; there is no compile-time check (a `T?` used as a `T` is not an error).

## 2. Representation (everything but `Bytes` lives inside a `Value`)

`Value` is 24 bytes: a tag and 16 bytes of payload (`Decimal` and `Rational` use all 16).

| Type | Payload | Notes |
|---|---|---|
| `Date` | `i32` days since 1970-01-01 | civil-from-days / days-from-civil of Howard Hinnant, proleptic Gregorian, year 1 to 9999 |
| `Time` | `i64` microseconds since midnight | 0 to 86,399,999,999 |
| `Instant` | `i64` microseconds (exists) | |
| `DateTime` | `i64` instant + `u32` zone id | the zone id indexes a table of zones (fixed offsets are made on demand; regions come from the built-in database) |
| `Duration` | `i64` microseconds | |
| `Zone` | `u32` zone id | |
| `Uuid` | 16 bytes | |
| `Bytes` | a heap object (pointer, length), immutable, shared | counted like `String`; a slice is a view of the same block (as a `List` view) |

Arithmetic is integer arithmetic with overflow checks (`$err_overflow`); nothing uses `f64`. Calendar code is in `code/evecm/src/calendar.zig` (days, fields, ISO weeks, month arithmetic, pure functions, unit tests against known dates and against Python's `datetime` for 100,000 random days), the zone rules in `code/evecm/src/zone.zig`, the pattern engine in `code/evecm/src/timefmt.zig`, `Uuid` and `Bytes` in `uuid.zig` and `bytes.zig`. The natives of the module `time` follow the shape of `mathlib.zig`: `compute` on values, so the fast call of D-220 applies.

## 3. Steps (each: page, failing tests, code, docs; the gate of `design-libraries.md` 0.5)

| Step | Content | Tests |
|---|---|---|
| D0 | `Duration` as a type (microseconds): the literals `us ms s m h`, operators, `time.seconds`, printing; the places that read the old integer (`within`, `wait`, timeouts, `sleep`) accept a `Duration` and the old integer for one release (warning `$wrn_deprecated`) | the tests of level 4 pass unchanged; new tests of the operators |
| D1 | `Date` and `Time`: `calendar.zig`, `time.date`, `clock`, fields, `add_months`, `start_of`, canonical text, `parse`, comparison, SQL and the readers (CSV, JSON, TXT) | one test per function, 20 known dates (leap years, 1900, 2000, 2100), a property test against Python |
| D2 | `Zone` and `DateTime`: fixed offsets, then the built-in region database (`zone.zig`), `at_zone`, `make`, gaps and overlaps of summer time | the zones of the test list: UTC, Europe/Bucharest, America/New_York, Asia/Kolkata (+05:30), Australia/Lord_Howe (30 minutes of summer time), Pacific/Apia (the lost day of 2011) |
| D3 | patterns: `format`, `parse(text, pattern)`, `{d % yyyy-MM-dd}` | round trips for every letter; the errors with a column |
| D4 | `Bytes`: heap object, slices, hex, Base64, text, search; `fs.read_bytes!`, `crypto` with `Bytes`, `Stream(:Bytes)`; the SQL and JSON mapping | round trip of a binary file; a hash of 100 MB without a copy |
| D5 | `Uuid`: parse, v4, v7, v3/v5, ordering; SQL mapping | the RFC 9562 test vectors |
| D6 | `T?`: the compile-time rules of section 5 | negative tests (exit 65) for every rule, positive tests for the narrowing |

Order: D0, D1, D3 (for `Date`), D2, D4, D5, D6. L4 (the library `lib/time/`: business days, holidays, periods) needs D0 to D3.

## 4. Performance

A `Date` or a `Time` operation is one integer operation; the conversion between days and fields is about 20 ns (a few divisions by constants). A benchmark `p1g_dates` (a year of days: fields, `add_months`, weekday, formatting a million dates) with a Python twin (`datetime.date`) goes in with D1, and the rule of D-196 holds: measure before and after.

## 5. The optional type `T?` (D6)

Today a value that may be `null` is not checked. The proposal (not decided):

1. A variable, parameter or field of type `T` never holds `null`: `let x := null;` for a `T` is a compile error; an assignment from a `T?` expression is a compile error unless the expression was tested.
2. **Narrowing:** after `if x <> null do`, inside the block `x` has the type `T`; the same after `if x == null do return; done;` for the rest of the block, in a `while x <> null` body, and on the right of `x <> null and ...`.
3. A `T?` in an arithmetic or comparison operator, as a method receiver (`x.length()`) or as an argument for a `T` parameter, is a compile error until it is narrowed.
4. **Default:** `x ?? d` gives `x` when it is not null and `d` otherwise; the type is `T` when `d` is a `T`.
5. `null` printed is `null`; a column that is `NULL` read into a `T` field is the error `$err_null` (16) with the name of the field, into a `T?` field it is `null`.

## 6. Questions for the author (all answered 2026-10-24 → D-221: the proposal of each is accepted)

- **Q-081 Literals of Date, Time and DateTime.** The page proposes none: `time.date(2026, 10, 24)`, `Date.parse("2026-10-24")`. Do you want a literal (for example `2026-10-24d`... the suffix `d` is the Decimal), or a form that does not clash with the lexer (`#2026-10-24#`, `date"2026-10-24"`)?
- **Q-082 Duration is a type.** Today `30s` is an `Integer` of milliseconds. The page makes it a `Duration` of microseconds (so `30s + 5` is an error and `10s * 3` and `end - start` mean something). The old integer is accepted by `within` and `wait` for a release. Agreed? Or keep milliseconds as `Integer` and add the type only for `Instant - Instant`?
- **Q-083 Date and days.** `Date + 7` adds seven days and `Date - Date` is an `Integer` of days (the proposal). The alternative is `Date + 7d`-like typed durations (`Duration` has no day unit because `5d` is a Decimal). Agreed with integers?
- **Q-084 Pattern letters.** `yyyy-MM-dd HH:mm:ss` (Unicode/Java/spreadsheet) or `%Y-%m-%d %H:%M:%S` (C, Python, `strftime`)? The proposal is the first.
- **Q-085 Zone data.** Built into `eve.exe` (a release of the IANA database, about 100 to 400 KB depending on the form; the same answer on every machine, the data ages with the release) or read from the operating system (nothing on Windows without a download)? The proposal is built in, updated at each release.
- **Q-086 DateTime equality and text.** Equal when the instants are equal (the proposal), and the canonical text has the offset (`+03:00`) and not the region name; the region is kept by the value (`zone_of(dt)`) but is not written. Agreed?
- **Q-087 Bytes.** Index from 1 as a `List` (the proposal) or from 0 as the draft of `data-language.md` says ("indexed from zero")? A literal: none (the proposal), or `0x"dead"`-like?
- **Q-088 Uuid versions.** v4, v7, v3 and v5 (the proposal). Is v1/v6 (MAC address and time) wanted? I propose not.
- **Q-089 Optional types.** Are the rules of section 5 right, and is `??` the operator you want for the default?
- **Q-090 Printing a Duration.** `1h30m`, `250ms`, `0us` (the proposal), or the ISO form `PT1H30M`? **Answer: ISO 8601**, `PT1H30M`, `PT0.25S`, `PT0S`.
