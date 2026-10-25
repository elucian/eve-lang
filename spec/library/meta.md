# The meta database

Status: **draft**, level 5. Step M0 (design in the plan of the project). Features: F-LIB-06. Built so far: the time zones, the countries and the continents; the tables of currencies, languages and phone numbers come in M0.2 and M0.3.

The Eve machine carries a small read only database of **reference data** that does not change with a program: the time zones of the world, and later countries, currencies, languages and calling codes. It is a SQLite file, `lib/meta/meta.db`, built from public sources by a script and read from disk at run time, from the `lib` folder beside the program. At optimization level 5 and above (variables.md#optimization-level) a background thread reads it when the run starts, and a first use that comes before the end of the read waits for it; below 5 it is read at the first use. It has two doors: the library modules (`zone`, `meta`, and the ones that follow), and plain SQL.

## The file

| Item | Rule |
|---|---|
| Content | the tables below; the release of every source is in `meta_info` |
| Sources | the IANA time zone database (public domain) and Unicode CLDR (Unicode licence) for the countries and continents; later libphonenumber (Apache 2.0) |
| Open | read only, without a copy, after the read of the file; below level 5 a script that does not use it pays nothing; at level 5 and above the read starts at every run (the choice of the tables by the compiler is not built, TD-89) |
| Replace | the environment variable `EVE_META_DB` names a file with the same tables (a newer release of the zone rules, for example); the program uses it instead of the file of `lib/meta` |
| Changes | a table and a column that were released are never changed or removed; new data comes as new tables or new columns |
| Concurrency | any number of tasks read it at the same time |

## meta.info

`meta.info(name)` gives an entry of the table `meta_info` as a `String`: `schema` (the version of the tables, `3`), `tzdata` (the release of the IANA database, such as `2026e`), `cldr` (the release of Unicode CLDR, `49.0.0`), `zones` (345 time zones), `zone_links` (253 other names), `countries` (249), `builder`. An unknown name is the error `$err_key` (11).

```eve
from lib/meta use (meta);
print meta.info("tzdata");     ** 2026e
```

## zone

The zone-aware operations of `DateTime` (its fields, its text, `at_zone`, `make`, `zone` and the parsing with a zone) use the functions `local_at` and `resolve_local` of this module: a script that uses zones gets the module as an import, as if it had written `from lib/meta use (zone);`. After its last stored transition a zone follows its rule (the POSIX form of the TZ database, read from the table `zone`); the rule is evaluated by the module `rule` of `lib/meta`, which is Eve code.

The module `zone` (`from lib/meta use (zone);`) answers questions about the time zones by name. A name is as in the IANA database (`Europe/Bucharest`, `America/New_York`, `UTC`); the names are case sensitive. 598 names: 345 zones and 253 links, which are other names of a zone (`Asia/Calcutta` is `Asia/Kolkata`). The rules include the history: before the standard time of a place its local mean time (Bucharest was `+01:44:24` in 1850), the days that were skipped, daylight saving time of the past, and the rule of the future after the last change that is known (summer time goes on by the rule of the zone to the year 9999).

| Function | Result | Meaning |
|---|---|---|
| `exists(name)` | `Logic` | is the name a zone or a link |
| `canonical(name)` | `String` | the zone that a link points to; a zone gives itself; an unknown name is `$err_argument` |
| `offset(name, at)` | `Duration` | the offset from UTC that the zone has at the `Instant` `at`, with daylight saving time (`PT3H` in Bucharest in July) |
| `abbreviation(name, at)` | `String` | the abbreviation used then: `EET`, `EEST`, `EDT`, `IST`, `+0330` |
| `is_dst(name, at)` | `Logic` | is daylight saving time in force (in Dublin the winter `GMT` is the daylight time of the database, as the database says) |
| `names()` | `List` | every name, in order |

An unknown zone is `$err_argument` (17), also an argument of another type. The first argument may also be a `Zone` value (`time.zone("Europe/Bucharest")`), which skips the search by name; the second argument may be an `Instant` or a `DateTime`. The answer for an instant on the exact second of a change is the new one (`2026-03-29T01:00:00Z` is already summer time in Bucharest).

```eve
from lib/meta use (zone);
new t := Instant.parse("2026-07-01T12:00:00Z");
print zone.offset("Europe/Bucharest", t), zone.abbreviation("Europe/Bucharest", t);   ** PT3H,EEST
print zone.canonical("Asia/Calcutta");                                                 ** Asia/Kolkata
```

### How the tables are used

A zone has a list of **types** (an offset, a flag for daylight time, an abbreviation) and a list of **transitions** (an instant and the type that starts there); before the first transition the first type applies. After the last transition the **rule** of the zone applies, a POSIX TZ text such as `EET-2EEST,M3.5.0/3,M10.5.0/4` (the last Sunday of March at 03:00 and the last Sunday of October at 04:00, in local time). A zone is read into memory the first time it is asked for, and a lookup is a binary search.

## sql

`database.connect("meta")` is the meta database as an ordinary SQLite database, read only; it needs no `eve.cfg`, and the name `meta` is reserved. A write is an error. The reference data can be joined with the data of the program:

```eve
new meta := database.connect("meta");
new rows := meta.query!(:Name)("select z.name as name from zone z where z.country = ? order by z.name", "RO");
new cc := meta.query!(:Name)("select c.name as name from country c join continent k on k.code = c.continent where k.name = 'Oceania' order by c.name");
```

| Table | Columns | Rules |
|---|---|---|
| `meta_info` | `name`, `value` | the version of the schema (`3`) and of every source: `tzdata`, `cldr` |
| `continent` | `code` (two letters), `name` | seven rows: `AF` Africa, `AN` Antarctica, `AS` Asia, `EU` Europe, `NA` North America, `OC` Oceania, `SA` South America |
| `country` | `code` (ISO 3166-1 alpha-2), `alpha3`, `numeric` (three digits, as text), `name` (English, CLDR), `continent` | the 249 codes officially assigned; `continent` is a foreign key to `continent`; the continent of a country is the region of the CLDR containment tree that holds it (so Turkey, Cyprus and Georgia are in Asia, Russia in Europe, Greenland in North America, Bouvet Island in South America); Antarctica is its own continent |
| `zone` | `id`, `name`, `link_of`, `country`, `position`, `note`, `rule`, `cldr` | a name of the time zone database. `link_of` is a foreign key to the zone a link points to. `country` is a foreign key to `country`: the place that the file `zone.tab` of the database gives to the name, null for the names that are no place (`UTC`, `EST5EDT`, `Etc/GMT+5`, `US/Eastern`). `position` is ISO 6709 (`+4426+02606`), `note` tells which part of the country when it has several zones. `rule` is the POSIX text of the future; empty when the zone has none. `cldr` is the short id of the zone in the Unicode CLDR (`robuh` for `Europe/Bucharest`, `inccu` for `Asia/Calcutta` and `Asia/Kolkata`): the names that are aliases of one zone share it, so it is not unique. |
| `zone_type` | `zone` (foreign key), `idx`, `utoff` (seconds), `isdst` (0 or 1), `abbr` | the kinds of local time of a zone |
| `zone_transition` | `zone` (foreign key), `at` (UTC seconds since 1970), `idx` | the type that starts at `at`; before the first one the type 0 applies |
| `zone_kind` | `id` (from 1), `utoff` (seconds), `isdst` (0 or 1), `abbr` | each distinct kind of local time once; derived from the types and the rules of the zones |
| `zone_span` | `zone` (foreign key), `at` (UTC seconds, the first row of a zone is the start of time), `kind` (key of `zone_kind`) | the kind in force from `at` to the `at` of the next row; derived from the transitions and from the POSIX rule of the zone, year by year to 2100; `kind` 0 on the row at 2100 of a zone that has daylight time: from there on the rule decides |

A link has a row in `zone` and none in `zone_type` and `zone_transition`: its data is that of `link_of`. The foreign keys are real: `pragma foreign_key_check` on the file gives no row, and the builder refuses to write a file that fails it. The zones of a country are `select name from zone where country = 'RO'`; its continent is `select k.name from country c join continent k on k.code = c.continent where c.code = 'RO'`.

## Loading the tables

A run copies into its connection only the tables it needs, from the file on disk. The tables are `zone`, `zone_type`, `zone_transition`, `country`, `continent` and `meta_info`.

| Source of the need | Tables |
|---|---|
| `from lib/meta use (zone)` (any module of `lib/meta`) | the tables the module reads: `zone` takes `zone`, `zone_type`, `zone_transition`; `meta` takes `meta_info`; `country` takes `country` and `continent` |
| a hint `** @meta require(zone, country)` in a comment of the script | the named tables |
| a hint `** @meta require(*)` | every table |

A hint that names a table that does not exist is a compile error (exit 65): `unknown table <name> in @meta require`. A parent is copied with its child: `zone` takes `country` and `continent`, `country` takes `continent`.

At optimization level 5 and above (variables.md#optimization-level) the copy starts in a background thread when the run starts, when the script has a need; a use that comes before its end waits for it. Below 5 nothing starts, and the copy is made at the first use. A table that a use needs and that was not copied is copied at that use. `database.connect("meta")` gives every table. The connection is read only once copied. The zone functions are Eve code (`lib/meta/zone.eve`, with the rule of the zone in `lib/meta/rule.eve`); the rows they read are kept in memory by the module.

