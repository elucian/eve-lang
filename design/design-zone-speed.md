# Plan: speed of the time zone functions (TD-91, TD-92)

Status: Z0 to Z4 done 2026-10-25 (section 8); revised after the answer of the author (any in-memory trick is fine if the database is the source of truth). D-229 (zones in Eve) and D-231 (DateTime calls the zone module) stay; this plan adds derived tables and caches and cuts overhead.

## 1. Baseline (ReleaseSafe, measured 2026-10-25)

- `p1i_zone_offsets` (60,000 calls of `zone.offset` from Eve): 5.5 s.
- `p1j_datetime` (60,000 `at_zone`, about 4 zone lookups each, plus `time.make` every 20th): 21.3 s, about 80 µs per lookup.
- `p1g_dates`, `p1h_time_format`: 0.13 s and 0.10 s (no region zone, unchanged).
- Native Zig before D-231: 0.35 s for 240,000 lookups, about 1.5 µs each. Target: at most 3 µs per lookup (2 times native), so `p1j` under 1 s.
- Profile of `p1i` (`EVE_PROFILE=1`): the interpreter itself (`eval` 18%, `eqlBytes` 9%, `lookup` 6%, scope create/destroy 8%), not SQL. Each lookup runs about 40 Eve statements.

## 2. Where the time goes in one lookup

1. Zig side (`metalib.zig:zoneCall`): `instantiate` of the module, `moduleMember` by name, a new String for the zone name, an argument list, a call through `invokeWith`. Done for every lookup.
2. Eve side `zone.offset`: `name_of`, `fixed_of` (string slices and comparisons, before the cache is even asked), `found` (map lookup), `seconds_of` (Real division), `local` (two cache reads, `count`, a binary search of up to 10 steps, a list built for the answer), and for the dates after the last transition `rule.local_at` (`year_of`, two `day_of`, each with several `days` and `div` calls: about 150 statements).
3. `resolve_local` calls `local_at` three to five times.

The answer of a lookup is constant between two transitions (about 6 months), and a program asks for dense or repeated instants: the data is a table of spans, not a computation.

## 3. Methods compared

| # | Method | Gain (expected) | Cost / risk | Verdict |
|---|--------|-----------------|-------------|---------|
| A | Cut the call overhead on the Zig side: keep the instantiated module and the function values of `local_at`, `resolve_local`, `exists` after the first call; pass the zone id, not a new String | 10 to 20% | tiny; the instance must be per run (modules are per run) | do first |
| B | Reorder `zone.offset`, `abbreviation`, `is_dst`: ask `found_cache` before `fixed_of`; `rule.div` with an integer division instead of `floor(a / b)` | 20 to 30% of the Eve calls | tiny, Eve only | do first |
| C | Memo of the last span per zone (Zig), in front of D | sequential instants always hit; random instants (p1i) rarely | tiny | part of D, kept only if it measures better |
| D | **Span table in memory (Zig), derived from the database:** the spans of every zone, with the years of the rule expanded to a horizon at build time (section 4); a lookup is a binary search, about 50 to 100 ns; beyond the horizon the Eve path answers | 100 to 300 times for all access patterns; both `local_at` and `resolve_local` (the second answers from the table without calling Eve) | schema change in the builder and a rebuilt `meta.db`; read-only tables, so threads read without a lock (S15.41); about 1 MB | **best, choose** |
| E | The same table as an Eve `Table` (F-DAT-05) or a sorted List with a native `search` | only if the search is native; with the interpreter binary search it stays at 5 to 10 µs | depends on F-DAT-05 (partial) | later, as a library feature |
| F | Memoization of `local(t)` by `(zone, t)` in an Eve map | weak: random instants never repeat, and the map access costs about 5 µs in the interpreter | none | reject (C covers the repeats) |
| G | A Zig `external` that computes the rules itself | like D | puts the zone algorithm back in Zig, against D-229/D-231 | reject; D keeps only a table derived from the database |
| H | Faster interpreter (TD-91: operators by enumeration, variable slots, cheaper scopes) | 2 to 3 times for all library code | large, VM track, hands-off unless asked | separate track; it also lowers the cost of the slow path |

Order: A and B (measure), then D with C inside (measure), compare with the baseline; H is not needed for the zones if D reaches the target.

## 4. Schema optimization

The author's answer (2026-10-25): every trick is fine if the database is the source of truth and the work happens in memory; invariant facts (7 days, 12 months) may be literals, zone data may not.

The whole zone data is small: 598 zones (345 with own data, 253 links), 17,057 transitions, 1,599 types. Everything fits in about 1 MB of flat arrays, so the plan loads it **once, whole**, with plain queries, not per zone on first use. Changes to the schema (made by `tools/meta/build_meta.py`, which derives them from tzdata; the IANA tables stay the source):

1. **Table `zone_span` (derived at build time).** One row per span: `(zone, from, wall_from, kind)`. `from` is the UTC start, `wall_from = from + utoff` is the start in local time (so a local time is found by the same binary search and `resolve_local` needs no calls); the end of a span is the `from` of the next row. It holds the transitions joined with their type, and the **years of the POSIX rule expanded from the last transition to a horizon (2100)**, computed at build time by the same algorithm as `rule.eve` (a check in the builder compares both). About 17,000 plus 25,000 rows. After this the rule of a zone is read only for instants beyond the horizon, and `rule.eve` leaves the hot path.
2. **Table `zone_kind` (derived).** `(id, utoff, isdst, abbr)` once for each distinct combination (a few hundred for all the zones), so a span row is three integers and the abbreviation strings are shared.
3. **Dense ids.** The `Zone` value keeps the integer id of the database row (`zone.id`, 1..598) as its slot; a link gets the spans of its target at build time, so the lookup of a link costs nothing. The id is **not stable between versions of the file** (it is checked against `meta_info`), so it is never written to a file or a checkpoint: the IANA name is the external key. This replaces the registration table (`slots`, `zones` in `metalib.zig`) by an array indexed by id.
4. **A code for the zone by convention?** For speed it adds nothing once ids are dense: the name is turned into an id once, when a `Zone` is made or parsed, and every later lookup uses the id. A stable code only pays for storage and exchange (a 16-bit field in a binary format, a short key in a URL). The convention that exists is the **CLDR short id** (`robuh` for Europe/Bucharest, stable by CLDR policy, in `bcp47/timezone.xml`); the repo already reads CLDR and needs the same source for the Windows names (TD-79). Proposal: add the column `zone.cldr` (text, unique, null when none) with TD-79; do not invent a code of our own.
5. **Literals that never change** stay in Zig and Eve: 7 days in a week, 12 months, 86,400 seconds in a day, 146,097 days in 400 years, the length of the months (a jump table in Zig). Nothing of zone data (offsets, rules, abbreviations, transition instants) is a literal anywhere.

Memory form in Zig (`zonespans.zig`): for all zones one array `from: []i64`, one `wall_from: []i64`, one `kind: []u16`, an index `start[zone]..start[zone+1]`, and the array of kinds. A lookup is an upper-bound search over the range of the zone and a read of the kind: about 50 to 100 ns, no allocation, no Eve call. The tables are read-only after the load (done once on the background thread, then published), so the threads of S15.41 read without a lock. An instant beyond the horizon, or a table not loaded, falls back to `zone.local_at` in Eve: the slow path stays correct.

## 5. Steps (each with a measure before and after, D-196)

1. **Z0 baseline.** Run `bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --check` and record the timings of section 1; add a benchmark `p1k_zone_dense` (one instant per second over a day in 3 zones, the pattern of a log) next to the random one of `p1i`; time e131.
2. **Z1 = A + B** (call overhead, order of the tests in `zone.offset`). Keep only if the gain is 20% or more. It also speeds the slow path of Z3.
3. **Z2 schema.** `build_meta.py` writes `zone_span` and `zone_kind`; the builder compares the expanded rule with `rule.eve` on every zone and 100,000 instants; `lib/meta/meta.db` is rebuilt (Git LFS; record the size change); the version goes to `meta_info`; `meta_need.zig` gets the two tables (`zone_transition` and `zone_type` stay for the slow path).
4. **Z3 memory tables.** `zonespans.zig` loads the two tables with one query each in the background load; `metalib.localAt` and `resolveLocal` read them; the `Zone` value uses the database id. Compare three variants on the benchmarks and keep the simplest that reaches the target: (a) binary search only, (b) binary search with the memo of the last span, (c) a per-zone year index (an array from year to first span, then a short scan).
5. **Z4 checks.** Differential test: for every zone and 1,000,000 random instants (1850 to 2200) plus every transition instant and its neighbours, the tables equal the slow path (`zone.local_at` without the tables, a switch for the test only); `resolve_local` the same on local times around each transition. Existing tests: e129 to e137, e130, e131, e158, `runtest.py all --both`, `bctest.py`, `zig build test`, `evegen check`.
6. **Z5 records.** Close TD-91 and TD-92 with the numbers; `spec/library/meta.md` follows (the tables are an implementation detail; only the horizon and the slower path beyond it are worth a note); if the target is missed, the interpreter track H is next.

## 6. Questions for the author

- **Q-A: answered 2026-10-25.** A cache in memory built from the database is fine; no zone data as literals; invariant literals are fine. To be recorded as a decision with the next number.
- **Q-B:** A native `List.search` (lower bound on a sorted list) as a library function (method E)? Not needed for the zones now.
**answer** sounds good implement.
- **Q-C:** The horizon of the expanded rules: 2100? Later years use the rule in Eve (slower, correct). A larger horizon costs about 400 rows per 100 years for all the zones with a rule.
**answer** 2100 is optimal
- **Q-D:** The column `zone.cldr` (CLDR short id) with TD-79, and no code of our own: agreed?
**answer** Agree, I'm glad you found it.
## 7. Not measured yet

This plan is from a reading of `zone.eve`, `rule.eve`, `metalib.zig`, the schema in `tools/meta/build_meta.py` and two timings; the gains of section 3 are estimates, to be replaced by the measures of Z1 and Z3.

## 8. Result (2026-10-25, ReleaseSafe, median of 3 runs)

| Benchmark | Before | Z1 (A + B) | Z3 (spans) |
|---|---|---|---|
| `p1i_zone_offsets` (random instants, `zone.offset`) | 4.1 s | 2.8 to 4.2 s | 0.33 s |
| `p1j_datetime` (`at_zone` and fields) | 21.7 s | 19.3 s | 0.15 s |
| `p1k_zone_dense` (new, consecutive seconds) | 6.6 s | 5.3 s | 0.32 s |
| e131 (240,000 lookups) | tens of seconds (limit 120 s) | | 1.2 s |

What was built, and where it differs from the plan:

- **Z1** gave 11 to 20%, below the 20% bar on `p1j`; the function cache of A stays in `metalib.zig` (`zoneFn`) and serves the slow path. The reorder of B was dropped: the externals of Z3 replace it.
- **Schema (Z2):** `zone_span(zone, at, kind)` and `zone_kind`, schema version 3 (36,841 spans, 591 kinds; the file grew from 389 KB to 987 KB). `wall_from` was dropped: the Zig code finds a local time from the neighbouring spans by the same algorithm as `resolve_local`, so the column was not needed. A link has no rows: the table `target` maps it to its zone at load time. The dense ids of section 4 point 3 already exist (the slot of a `Zone` value is an array index); they only needed `Entry.db_id`.
- **Memory tables (Z3):** `zonespans.zig` (binary search, about 100 ns), loaded once at the first lookup; the lookups of Zig (`localAt`, `resolveLocal`, `zoneIdOf`) and three Eve externals (`span_offset`, `span_dst`, `span_abbr` in `zone.eve`) read them. The memo of the last span (C) and the year index were not needed: the plain search reaches the target. Beyond the horizon, and for names written as offsets, the Eve code answers (TD-93).
- **Checks (Z4):** the builder compares the spans with Python's `zoneinfo` on 212,673 instants; the test e162 (20 zones, every day of 1999, 2024 and 2090 at four local times) and a run over all 598 zones (170 instants each, local times in 100 of them) give the same sums with and without `EVE_ZONE_SLOW=1`; `runtest.py all --both` 556 of 556; `bctest.py`, `zig build test`, `tagcheck.py`, `evegen check` pass; the benchmarks of levels 2 to 5 did not change.
