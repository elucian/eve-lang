# Calendar

Status: **draft**, level 3. Library step L4. Written in Eve (`lib/calendar/`), over the types `Date` and `Time` of [time.md](time.md). Feature: F-LIB-03.

The calendar of the business: periods of the year, public holidays by country and business days. The dates are `Date` values of the proleptic Gregorian calendar; a country is the two letters of its code, as text. A wrong argument is `$err_argument` (17).

## Rules of import

`from lib use (calendar);` gives `calendar.quarter_of`, `calendar.easter`, `calendar.add_business_days` and the other functions of the three modules `period`, `holidays` and `business`, which can also be imported alone, `from lib/calendar use (business);`.

## Module period

| Function | Result | Meaning |
|---|---|---|
| `quarter_of(d)` | `Integer` | the quarter of the date, 1 to 4 |
| `start_of_quarter(d)`, `end_of_quarter(d)` | `Date` | the first and the last day of the quarter |
| `days_in_quarter(d)` | `Integer` | the number of days of the quarter |
| `start_of_week(d)`, `end_of_week(d)` | `Date` | the Monday and the Sunday of the ISO week |
| `start_of_month(d)`, `end_of_month(d)` | `Date` | the first and the last day of the month |
| `start_of_year(d)`, `end_of_year(d)` | `Date` | January 1 and December 31 |
| `fiscal_year(d, first_month)` | `Integer` | the fiscal year of a year that starts in `first_month` (1 to 12), named by the calendar year in which it ends: with 4, 2026-03-31 is in 2026 and 2026-04-01 in 2027 |
| `fiscal_quarter(d, first_month)` | `Integer` | the quarter, 1 to 4, of that fiscal year |

## Module holidays

| Function | Result | Meaning |
|---|---|---|
| `calendars()` | list | the calendars that exist: `DE`, `FR`, `GB`, `RO`, `US` |
| `easter(year)` | `Date` | Easter Sunday of the Western churches (Gregorian rule), 1583 and after |
| `orthodox_easter(year)` | `Date` | Easter Sunday of the Orthodox churches, as a date of the Gregorian calendar |
| `holidays(year, country)` | list of `Holiday` | the public holidays of the country in the year, in date order; a `Holiday` has `date` and `name` |
| `name_of(d, country)` | `String?` | the name of the holiday on that date, `null` when there is none |
| `is_holiday(d, country)` | `Logic` | is the date a public holiday |

The calendars are `US` (federal holidays), `GB` (England and Wales), `DE` (the holidays of the whole country), `FR` and `RO`. The days are the nominal ones: a holiday that falls on a weekend is not moved to another day, and the holidays of a region or a state are not in the list. An unknown country is `$err_argument`.

## Module business

A business day is a day that is not a Saturday or a Sunday and, when a calendar is given, not a public holiday of that calendar. The empty text as the calendar means weekends only.

| Function | Result | Meaning |
|---|---|---|
| `is_weekend(d)` | `Logic` | a Saturday or a Sunday |
| `is_business_day(d, calendar)` | `Logic` | |
| `following(d, calendar)` | `Date` | the first business day on or after the date |
| `preceding(d, calendar)` | `Date` | the last business day on or before the date |
| `add_business_days(d, n, calendar)` | `Date` | the date `n` business days after (before, for a negative `n`); the date itself does not count |
| `business_days_between(a, b, calendar)` | `Integer` | the business days from `a` up to but not including `b`; negative when `b` is the earlier |
