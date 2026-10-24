# Design: the meta database (reference data in a SQLite file)

Status: **accepted** (2026-10-24, D-222; the data is not compressed and every `.db` file is in Git LFS), from the author's idea: use the SQLite that is already in the machine to hold universal reference data (countries, time zones, phone prefixes, currencies...), so the libraries need less code and read precomputed data. It becomes step **M0**, before D2 (zones) of `design-data-types.md`.

## 1. What is measured

- SQLite is linked into `eve.exe` already (`code/evevm/src/db/sqlite.zig`, the amalgamation, 3.54): a database in the machine costs **no new code**. `sqlite3_deserialize` opens a database that lives in memory, read only, without a copy: the file can be embedded in the executable with `@embedFile`.
- The IANA time zone database, release **2026.5** (`pip download tzdata` worked on this machine): 598 zone names, 345 different zones (253 names are links), **346 KB** as compiled TZif files, **105 KB** as the compact source `tzdata.zi` (about 25 KB compressed); `zone.tab` (zone to country, with the position) 19 KB; `iso3166.tab` (country codes and names) 5 KB. The operating system of this machine has no zone files at all (Windows): without built-in data a zone function can not work here.
- Countries, currencies, languages and calling codes are a few thousand rows: well under 200 KB with an index.
- So the whole meta database is about **0.3 to 0.6 MB**. It is kept populated and uncompressed (D-222): embedded as it is, opened without a copy; its weight is in Git LFS, which keeps every version of the file outside the history of the sources.

## 2. The idea in one picture

```
tools/meta/build_meta.py  ---(IANA tzdata, CLDR, libphonenumber, ISO lists)--->  lib/meta/meta.db   (committed, read only, versioned)
                                                                                      |
                              @embedFile  --->  eve.exe  --- first use --->  sqlite3_deserialize (zero copy, read only)
                              $EVE_HOME/meta.db (optional, newer data without a new Eve)  overrides the embedded one
                                                                                      |
         SQL:  database.connect("meta")  ->  the user joins the reference data with his own tables
         Eve:  lib/meta/country.eve, phone.eve, currency.eve, zone.eve ...  ->  thin natives with prepared statements and caches
         Zones: the transitions of a zone are read once into a sorted array; a conversion is a binary search (tens of nanoseconds), not a query
```

## 3. Why it helps, and what it does not do

Helps:
1. **Less code.** The zone engine does not need a rule compiler (`zic`): the builder expands the rules into transitions up to 2100 and keeps the POSIX rule of the last year (`EET-2EEST,M3.5.0/3,M10.5.0/4`) for later; the engine is a binary search and a small evaluator for that rule. No Zig tables of countries, currencies or codes.
2. **Joinable data.** An ETL author writes `select o.*, c.name, c.currency from orders o join meta.country c on c.alpha2 = o.country`: the reference data is just another database.
3. **Updates without a new release.** The time zone rules change several times a year (governments move summer time). A file `meta.db` beside the project overrides the embedded one; `meta.info` says which release is in use.
4. **One format** for later tables: units (L7 `eng`), currencies and their digits (L6 `finance`), public holidays (L4 calendars), media types, HTTP status text, character sets, well-known ports.

Does not do:
- **Algorithms stay code**: the calendar, the patterns, the arithmetic of `Date`, `Rational`, `Complex`. Only data that changes or is a table moves.
- It is **not faster per lookup** than a Zig array (a prepared statement is about 1 to 3 microseconds). Anything called per element in a loop (a zone conversion over a million rows) must be loaded in memory once per run; the library modules do that.
- The executable gets **bigger by the size of the data** (about 0.3 to 0.6 MB): the gain is in code, in maintenance and in SQL access, not in bytes.

## 4. Content of version 1 (what the next steps need)

| Table | Content | Source | Used by |
|---|---|---|---|
| `meta_info` | name, value: the schema version, the release of each source, the date of the build | the builder | `meta.info` |
| `zone` | id, name (`Europe/Bucharest`), the POSIX rule of the future, `link_of` for the 253 aliases, `country` (foreign key to `country`), position, note | IANA (`zone.tab`) | D2 |
| `zone_transition` | zone id, instant (UTC seconds), offset in seconds, summer time flag, abbreviation; sorted, to 2100 | IANA | D2 |
| `continent` | code (two letters), name | CLDR | `country` |
| `country` | alpha-2 (the key), alpha-3, numeric, English name, continent (foreign key) | ISO 3166 list of the IANA database, CLDR | `zone`, `country` library |
| `country` | alpha-2, alpha-3, numeric, English name, official name, calling code, capital, continent, currency, languages, the national number format | ISO 3166, CLDR, libphonenumber | `country`, `phone` |
| `currency` | alpha-3, numeric, name, symbol, digits (`JPY` 0, `EUR` 2, `BHD` 3), countries | ISO 4217, CLDR | L6 `finance` |
| `language` | alpha-2, alpha-3, name | ISO 639, CLDR | `country` |
| `phone_region` | region, calling code, national prefix, the patterns of the numbers (digits, mobile or not), examples | libphonenumber | `phone` |

Later versions add tables, never change a column (a compatibility rule, like a released function).

## 5. Layout in the repository

```
tools/meta/build_meta.py        the builder: downloads the sources of a named release (or reads a folder), writes the database; documented, run by hand a few times a year
lib/meta/README.md              the modules of the library meta and the tables
lib/meta/meta.db                the generated file, committed in Git LFS (about 0.3 to 0.6 MB; a new version per release of the sources)
lib/meta/country.eve, phone.eve, currency.eve, zone.eve, language.eve      the modules (signatures; the bodies are native or SQL)
spec/library/meta.md            the page: tables, functions, rules
code/evevm/src/metalib.zig      open (embedded or override), prepared statements, caches
```

## 6. Rules

1. The database is **read only** (`SQLITE_DESERIALIZE_READONLY`, `immutable`): no task can change it, any number of tasks read it; each interpreter has a connection of its own.
2. It is opened **on first use**: a script that does not use `meta` pays nothing at start.
3. Every row of the data is **reproducible** from the sources named in `meta_info`; the builder is deterministic (the same sources give the same bytes), and a test compares the embedded file with `meta.info`.
4. The licences of the sources are permissive and are kept in the page: IANA (public domain), Unicode CLDR (Unicode licence), libphonenumber (Apache 2.0). The lists of ISO standards are facts; names come from CLDR. Not used: `pycountry` and the `iso-codes` package (LGPL).
5. A function of a library that reads the meta database says so in its page (`source: meta.country`), so the data of an answer can be traced.

## 7. Steps

| Step | Content | Tests |
|---|---|---|
| M0.1 | the builder for the zones only (IANA 2026.5): `zone`, `zone_transition`, `zone_country`; the embedding and the opening in `metalib.zig`; `database.connect("meta")` read only | the transitions of 20 zones against Python's `zoneinfo`, 100 instants each |
| M0.2 | countries, currencies, languages from CLDR; the modules `country`, `currency`, `language` | the rows against the sources; round trips of the codes |
| M0.3 | phone regions from libphonenumber; `phone.parse`, `phone.format`, `phone.region` | the examples of the metadata |
| then D2 | `Zone`, `DateTime` over `zone_transition` | zones against Python for 100,000 random instants |

## 8. Questions for the author (all answered 2026-10-24 → D-222; Q-094: not compressed, `*.db` in Git LFS)

- **Q-091 Direction.** One embedded read-only SQLite file `meta.db`, readable as the database `meta` and through the modules `lib/meta/`, with an optional override file. Agreed?
- **Q-092 Sources.** IANA tzdata, Unicode CLDR and libphonenumber (all permissive), built by a script that stays in the repository and whose output is committed. Agreed? Or generate the file at build time (then the build needs Python)?
- **Q-093 Content of version 1.** The tables of section 4. Add now, or in later versions: public holidays by country (a big and political table: proposal later), units of measure (L7), media types and ports (small, proposal later)?
- **Q-094 Size.** Embedded as compressed bytes and unpacked on first use (smaller executable, about 10 ms at the first use) or uncompressed (zero copy)? The proposal is compressed.
- **Q-095 Folder.** `lib/meta/` as in your idea, with the generated file inside it, and the builder in `tools/meta/`. Agreed?
- **Q-096 Order.** M0.1 (zones) first, then D2 on top of it, then M0.2 and M0.3. Agreed?
