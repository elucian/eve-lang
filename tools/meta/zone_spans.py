"""@spec spec/library/meta.md#sql  @feature F-LIB-06  @decision D-229  @tests test/level5/e162_zone_spans
The derived zone tables of lib/meta/meta.db (design/design-zone-speed.md section 4): zone_kind and zone_span.

  zone_kind(id, utoff, isdst, abbr)   each distinct kind of local time once, ids from 1
  zone_span(zone, at, kind)           the spans of a zone in order: from `at` (UTC seconds) to the `at` of the next row, the kind in force;
                                      the first row of a zone is at SPAN_NEVER (the start of time). The spans come from the transitions of
                                      the zone, then from its POSIX rule (the footer of the TZif file) year by year to the horizon. The last
                                      row of a zone whose rule has daylight time is at the horizon with kind 0: beyond it the rule decides
                                      (lib/meta/rule.eve). A zone that ends with a fixed offset has no such row.

The expansion follows lib/meta/rule.eve exactly (the same year of an instant, the same days, the same tests), so that the tables and the Eve code give the same answer;
test/level5 and the differential test of the VM check it. Only zone tables are written here: the data is the tzdata of the build.
"""
import random

SPAN_NEVER = -(1 << 62)
HORIZON_YEAR = 2100
SPAN_HORIZON = None  # set below: seconds of HORIZON_YEAR-01-01T00:00:00Z


def days_from_civil(y, m, d):
    """Days since 1970-01-01 of a civil date (Howard Hinnant, as rule.eve `days`)."""
    y -= m <= 2
    era = y // 400
    yoe = y - era * 400
    doy = (153 * (m + (-3 if m > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def year_of(z0):
    z = z0 + 719468
    era = z // 146097
    doe = z - era * 146097
    yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp = (5 * doy + 2) // 153
    m = mp + 3 if mp < 10 else mp - 9
    return yoe + era * 400 + (1 if m <= 2 else 0)


SPAN_HORIZON = days_from_civil(HORIZON_YEAR, 1, 1) * 86400


def leap(y):
    return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


def weekday(z):
    return (z + 4) % 7


def _name_at(s, p):
    if s[p] == '<':
        p = s.index('>', p) + 1
        return p
    while p < len(s) and s[p] >= 'A' and s[p] not in '+-,':
        p += 1
    return p


def _time_at(s, p):
    sign = 1
    if s[p] == '-':
        sign, p = -1, p + 1
    if s[p] == '+':
        p += 1
    parts = [0]
    while p < len(s) and s[p] in '0123456789:':
        if s[p] == ':':
            parts.append(0)
        else:
            parts[-1] = parts[-1] * 10 + int(s[p])
        p += 1
    weights = (3600, 60, 1)
    return sign * sum(g * weights[k] for k, g in enumerate(parts)), p


def _change_at(s, p):
    kind, a, b, c = 3, 0, 0, 0
    if s[p] == 'M':
        kind = 1
        p += 1
        vals = []
        for _ in range(3):
            v = 0
            while p < len(s) and s[p].isdigit():
                v = v * 10 + int(s[p])
                p += 1
            p += 1
            vals.append(v)
        a, b, c = vals
        p -= 1
    elif s[p] == 'J':
        kind = 2
        p += 1
    if kind != 1:
        while p < len(s) and s[p] not in '/,':
            a = a * 10 + int(s[p])
            p += 1
    secs = 7200
    if p < len(s) and s[p] == '/':
        secs, p = _time_at(s, p + 1)
    return (kind, a, b, c, secs), p


def _bare(name):
    return name[1:-1] if len(name) > 2 and name[0] == '<' else name


def parse_rule(text):
    """(std name, std offset, dst name, dst offset, on change, off change); dst name '' when the rule has no daylight time."""
    p = 0
    e = _name_at(text, p)
    std_name = _bare(text[p:e])
    t, p = _time_at(text, e)
    std_off = -t
    if p >= len(text):
        return (std_name, std_off, '', 0, None, None)
    e2 = _name_at(text, p)
    dst_name = _bare(text[p:e2])
    p = e2
    dst_off = std_off + 3600
    if text[p] != ',':
        t2, p = _time_at(text, p)
        dst_off = -t2
    on, p = _change_at(text, p + 1)
    off, _ = _change_at(text, p + 1)
    return (std_name, std_off, dst_name, dst_off, on, off)


def _day_of(ch, y):
    kind, a, b, c, _ = ch
    jan1 = days_from_civil(y, 1, 1)
    if kind == 2:
        return jan1 + a - 1 + (1 if leap(y) and a >= 60 else 0)
    if kind == 3:
        return jan1 + a
    first = days_from_civil(y, a, 1)
    nxt = days_from_civil(y, a + 1, 1) if a < 12 else days_from_civil(y + 1, 1, 1)
    day = first + (c - weekday(first)) % 7 + 7 * (b - 1)
    while day >= nxt:
        day -= 7
    return day


def _bounds(r, y):
    return (_day_of(r[4], y) * 86400 + r[4][4] - r[1], _day_of(r[5], y) * 86400 + r[5][4] - r[3])


def rule_state(r, t):
    """(utoff, isdst, abbr) of the rule at the UTC instant t, as rule.local_at."""
    if r[2] == '':
        return (r[1], 0, r[0])
    y = year_of((t + r[1]) // 86400)
    s, e = _bounds(r, y)
    inside = (t >= s and t < e) if s < e else (t >= s or t < e)
    return (r[3], 1, r[2]) if inside else (r[1], 0, r[0])


def spans_of(trans, types, footer):
    """The spans [(at, kind)] of a zone, kind a (utoff, isdst, abbr) tuple or None for 'the rule decides' (after the horizon)."""
    kinds = [(u, 1 if d else 0, a) for u, d, a in types]
    rule = parse_rule(footer) if footer else None
    out = []
    if not trans:
        if rule is None:
            return [(SPAN_NEVER, kinds[0])]
        if rule[2] != '':
            raise SystemExit('a zone with a daylight rule and no transition: not expected')
        return [(SPAN_NEVER, rule_state(rule, 0))]
    out.append((SPAN_NEVER, kinds[0]))
    for at, idx in trans:
        out.append((at, kinds[idx]))
    if rule is None:
        return out
    last = trans[-1][0]
    out.pop()  # from the last transition on, the rule decides
    if rule[2] == '':
        out.append((last, rule_state(rule, last)))
        return out
    # the instants where the rule may change, from the year of the last transition to the horizon
    y0 = year_of((last + rule[1]) // 86400) - 1
    cand = set()
    for y in range(y0, HORIZON_YEAR + 2):
        cand.update(_bounds(rule, y))
    cur = rule_state(rule, last)
    out.append((last, cur))
    for b in sorted(c for c in cand if last < c < SPAN_HORIZON):
        st = rule_state(rule, b)
        if st != rule_state(rule, b - 1):
            out.append((b, st))
            cur = st
    out.append((SPAN_HORIZON, None))
    return out


def merge_equal(spans):
    """Drops a span that has the kind of the one before it."""
    out = []
    for at, k in spans:
        if out and out[-1][1] == k:
            continue
        out.append((at, k))
    return out


SCHEMA = """
create table zone_kind (
  id integer primary key,
  utoff integer not null,
  isdst integer not null,
  abbr text not null,
  unique (utoff, isdst, abbr)
);
create table zone_span (
  zone integer not null references zone(id),
  at integer not null,
  kind integer not null,
  primary key (zone, at)
) without rowid;
"""


def write(db, zone_rows):
    """Writes zone_kind and zone_span. zone_rows: [(zone id, transitions, types, footer)] of the zones that have their own data."""
    all_spans = {}
    kinds = set()
    for zid, trans, types, footer in zone_rows:
        sp = merge_equal(spans_of(trans, types, footer))
        all_spans[zid] = sp
        kinds.update(k for _, k in sp if k is not None)
    kind_id = {}
    for i, k in enumerate(sorted(kinds), 1):
        kind_id[k] = i
        db.execute('insert into zone_kind values (?, ?, ?, ?)', (i, k[0], k[1], k[2]))
    n = 0
    for zid in sorted(all_spans):
        rows = [(zid, at, 0 if k is None else kind_id[k]) for at, k in all_spans[zid]]
        db.executemany('insert into zone_span values (?, ?, ?)', rows)
        n += len(rows)
    return len(kind_id), n, all_spans


def check(names_to_spans, rounds=300, seed=1):
    """Compares the spans with Python's zoneinfo (the same tzdata) on random instants and around every change: returns the number of instants checked, or -1 when zoneinfo has no data."""
    import bisect
    from datetime import datetime, timedelta, timezone
    try:
        import zoneinfo
        zoneinfo.ZoneInfo('Europe/Bucharest')
    except Exception:
        return -1
    rnd = random.Random(seed)
    epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
    checked = 0
    for name, sp in names_to_spans.items():
        zi = zoneinfo.ZoneInfo(name)
        ats = [a for a, _ in sp]
        probes = [rnd.randrange(-2208988800, SPAN_HORIZON) for _ in range(rounds)]
        for a, _ in sp[1:]:
            if a < SPAN_HORIZON:
                probes += [a - 1, a, a + 1]
        for t in probes:
            k = sp[bisect.bisect_right(ats, t) - 1][1]
            if k is None:
                continue
            got = int((epoch + timedelta(seconds=t)).astimezone(zi).utcoffset().total_seconds())
            if got != k[0]:
                raise SystemExit('zone_span: %s at %d: table %d, zoneinfo %d' % (name, t, k[0], got))
            checked += 1
    return checked
