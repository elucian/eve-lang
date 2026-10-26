#!/usr/bin/env python3
"""Build lib/meta/meta.db, the reference data embedded in eve.exe (design/design-meta-database.md, D-222, D-223).

  python tools/meta/build_meta.py --fetch temp/meta-src            download the sources into the folder, then build
  python tools/meta/build_meta.py --src temp/meta-src              build from sources already there
  python tools/meta/build_meta.py --tzdata DIR --cldr-core DIR --cldr-names DIR --cldr-bcp47 DIR [--out FILE]

The sources (all permissive licences):
  tzdata       the IANA time zone database, as the Python package `tzdata` (public domain): zoneinfo/tzdata.zi, zone.tab, iso3166.tab, the TZif files
  cldr-core    Unicode CLDR as JSON (Unicode licence): supplemental/territoryContainment.json, codeMappings.json
  cldr-names   CLDR localenames (the same licence): main/en/territories.json
  cldr-bcp47   CLDR keywords (the same licence): bcp47/timezone.json, the short ids of the time zones (zone.cldr)

The file is deterministic: the same sources give the same bytes. Schema version 3 (D-223; version 3 adds zone_kind and zone_span); a table or a column that was released is never
changed, new data comes as new tables or columns:

  meta_info(name, value)                   the schema version, the sources and their releases
  continent(code, name)                    seven rows: AF AN AS EU NA OC SA
  country(code, alpha3, numeric, name, continent)    the 249 officially assigned ISO 3166-1 codes; the names and the continents are CLDR's
  zone(id, name, link_of, country, position, note, rule, cldr)    a name of the time zone database; a link points to its zone; country is the place
                                           zone.tab gives to the name (null for the names that are no place: UTC, EST5EDT, Etc/GMT+5, US/Eastern)
  zone_type(zone, idx, utoff, isdst, abbr) the kinds of local time of a zone (TZif types)
  zone_transition(zone, at, idx)           the instants (UTC seconds) where a zone changes to the type idx; before the first one: the type 0
  currency(code, digits, current)          the currencies of CLDR currencyData: the digits after the decimal point (CLDR fractions, 2 by default) and whether a country uses it now
  windows_zone(name, territory, zone)      CLDR windowsZones: the IANA zone of a Windows zone name, for a territory ('001' is the default of the name)
  zone_kind(id, utoff, isdst, abbr)        derived (tools/meta/zone_spans.py): each kind of local time once
  zone_span(zone, at, kind)                derived: the spans of a zone in order, transitions then the POSIX rule to the year 2100; kind 0 at the horizon: the rule decides
"""
import argparse, io, json, os, sqlite3, struct, sys, tarfile, urllib.request, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zone_spans

SCHEMA_VERSION = 3
TZDATA_VERSION = '2026.5'
CLDR_VERSION = '49.0.0'

# the seven continents; CLDR's regions that stand for each (a country belongs to the first one that contains it)
CONTINENTS = [('AF', 'Africa', '002'), ('AN', 'Antarctica', None), ('AS', 'Asia', '142'), ('EU', 'Europe', '150'),
              ('NA', 'North America', '003'), ('OC', 'Oceania', '009'), ('SA', 'South America', '005')]


def parse_tzif(data):
    """(transitions [(at, idx)], types [(utoff, isdst, abbr)], footer) of a TZif file; the version 2 block with 64-bit times."""
    if data[:4] != b'TZif':
        raise ValueError('not a TZif file')
    ver = data[4:5]

    def counts(off):
        return struct.unpack('>6l', data[off + 20:off + 44])

    isut, isstd, leap, timecnt, typecnt, charcnt = counts(0)
    if ver == b'\0':
        raise ValueError('version 1 only')
    v1_len = timecnt * 4 + timecnt + typecnt * 6 + charcnt + leap * 8 + isstd + isut
    base = 44 + v1_len
    isut, isstd, leap, timecnt, typecnt, charcnt = counts(base)
    p = base + 44
    times = struct.unpack('>%dq' % timecnt, data[p:p + 8 * timecnt]) if timecnt else ()
    p += 8 * timecnt
    idxs = data[p:p + timecnt]
    p += timecnt
    raw_types = [struct.unpack('>lBB', data[p + 6 * i:p + 6 * i + 6]) for i in range(typecnt)]
    p += 6 * typecnt
    chars = data[p:p + charcnt]
    p += charcnt + leap * 12 + isstd + isut
    footer = data[p:].strip(b'\n').decode('ascii')
    types = []
    for utoff, isdst, ai in raw_types:
        end = chars.index(b'\0', ai)
        types.append((utoff, isdst, chars[ai:end].decode('ascii')))
    return list(zip(times, idxs)), types, footer


def read_zi(path):
    """(zones, links, release) from tzdata.zi: the names of the 'Z' lines, the (target, link) pairs of the 'L' lines, the release."""
    zones, links, release = [], [], ''
    with open(path, encoding='utf-8') as f:
        for line in f:
            if line.startswith('# version '):
                release = line.split()[2]
            elif line.startswith('Z '):
                zones.append(line.split()[1])
            elif line.startswith('L '):
                _, target, name = line.split()
                links.append((target, name))
    return zones, links, release


def read_tab(path, columns):
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            parts = line.rstrip('\n').split('\t')
            parts += [''] * (columns - len(parts))
            rows.append(parts[:columns])
    return rows


def load_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def continents_of(containment, codes):
    """{country code: continent code}: walk the CLDR containment tree down from each continent region."""
    tree = containment['supplemental']['territoryContainment']
    assigned = {}

    def walk(region, cont):
        for child in tree.get(region, {}).get('_contains', []):
            if len(child) == 2 and child.isalpha():
                assigned.setdefault(child, cont)
            else:
                walk(child, cont)

    for cont, _, region in CONTINENTS:
        if region:
            walk(region, cont)
    assigned['AQ'] = 'AN'
    missing = sorted(c for c in codes if c not in assigned)
    if missing:
        raise SystemExit('no continent for %s' % ', '.join(missing))
    return assigned


SCHEMA = """
create table meta_info (name text primary key, value text not null) without rowid;
create table continent (
  code text primary key check (length(code) = 2),
  name text not null unique
) without rowid;
create table country (
  code text primary key check (length(code) = 2),
  alpha3 text not null unique check (length(alpha3) = 3),
  numeric text not null unique check (length(numeric) = 3),
  name text not null unique,
  continent text not null references continent(code)
) without rowid;
create index country_by_continent on country (continent);
create table zone (
  id integer primary key,
  name text not null unique,
  link_of integer references zone(id),
  country text references country(code),
  position text,
  note text,
  rule text not null default '',
  cldr text
);
create index zone_by_cldr on zone (cldr);
create table currency (
  code text primary key check (length(code) = 3),
  digits integer not null,
  current integer not null check (current in (0, 1))
) without rowid;
create table windows_zone (
  name text not null,
  territory text not null,
  zone text not null,
  primary key (name, territory)
) without rowid;
create index zone_by_country on zone (country);
create table zone_type (
  zone integer not null references zone(id),
  idx integer not null,
  utoff integer not null,
  isdst integer not null,
  abbr text not null,
  primary key (zone, idx)
) without rowid;
create table zone_transition (
  zone integer not null references zone(id),
  at integer not null,
  idx integer not null,
  primary key (zone, at)
) without rowid;
"""
SCHEMA += zone_spans.SCHEMA


def build(tzdata, cldr_core, cldr_names, cldr_bcp47, out):
    zoneinfo = os.path.join(tzdata, 'zoneinfo')
    zones, links, release = read_zi(os.path.join(zoneinfo, 'tzdata.zi'))
    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.executescript('pragma page_size = 4096; pragma journal_mode = off; pragma foreign_keys = on;')
    db.executescript(SCHEMA)

    # continents and countries
    names = load_json(os.path.join(cldr_names, 'main', 'en', 'territories.json'))['main']['en']['localeDisplayNames']['territories']
    codes_map = load_json(os.path.join(cldr_core, 'supplemental', 'codeMappings.json'))['supplemental']['codeMappings']
    iso = [(r[0], r[1]) for r in read_tab(os.path.join(zoneinfo, 'iso3166.tab'), 2)]
    cont_of = continents_of(load_json(os.path.join(cldr_core, 'supplemental', 'territoryContainment.json')), [c for c, _ in iso])
    db.executemany('insert into continent values (?, ?)', [(c, n) for c, n, _ in CONTINENTS])
    for code, iso_name in iso:
        cm = codes_map[code]
        db.execute('insert into country values (?, ?, ?, ?, ?)', (code, cm['_alpha3'], cm['_numeric'], names.get(code, iso_name), cont_of[code]))

    # time zones
    ids = {}
    span_rows = []
    for name in sorted(zones):
        data = open(os.path.join(zoneinfo, *name.split('/')), 'rb').read()
        trans, types, footer = parse_tzif(data)
        cur = db.execute('insert into zone (name, rule) values (?, ?)', (name, footer))
        zid = cur.lastrowid
        ids[name] = zid
        db.executemany('insert into zone_type values (?, ?, ?, ?, ?)', [(zid, i, u, d, a) for i, (u, d, a) in enumerate(types)])
        db.executemany('insert into zone_transition values (?, ?, ?)', [(zid, at, idx) for at, idx in trans])
        span_rows.append((zid, trans, types, footer))
    target_of = {name: target for target, name in links}
    for target, name in sorted(links, key=lambda l: l[1]):
        t = target
        while t in target_of and t not in ids:
            t = target_of[t]
        if t not in ids:
            raise SystemExit('link %s -> %s: no zone %s' % (name, target, t))
        db.execute('insert into zone (name, link_of) values (?, ?)', (name, ids[t]))
    nkinds, nspans, spans = zone_spans.write(db, span_rows)
    checked = zone_spans.check({n: spans[i] for n, i in ids.items()})
    print('zone_span: %d kinds, %d spans; %s' % (nkinds, nspans, ('%d instants agree with zoneinfo' % checked) if checked >= 0 else 'zoneinfo has no data: not checked'))
    # the short id of CLDR (bcp47/timezone.json): "robuh" for Europe/Bucharest; every alias that the database has gets it (several names, one id)
    short = 0
    for key, v in load_json(os.path.join(cldr_bcp47, 'bcp47', 'timezone.json'))['keyword']['u']['tz'].items():
        if key.startswith('_') or not isinstance(v, dict):
            continue
        for alias in v.get('_alias', '').split():
            short += db.execute('update zone set cldr = ? where name = ?', (key, alias)).rowcount
    print('zone.cldr: %d names have a short id' % short)
    # the currencies and the digits of their smallest unit (supplemental/currencyData.json)
    cdata = load_json(os.path.join(cldr_core, 'supplemental', 'currencyData.json'))['supplemental']['currencyData']
    fractions = cdata['fractions']
    current, seen = set(), set()
    for entries in cdata['region'].values():
        for entry in entries:
            for code, v in entry.items():
                seen.add(code)
                if '_to' not in v:
                    current.add(code)
    default_digits = int(fractions['DEFAULT']['_digits'])
    for code in sorted(seen):
        digits = int(fractions.get(code, {}).get('_digits', default_digits))
        db.execute('insert into currency values (?, ?, ?)', (code, digits, 1 if code in current else 0))
    # the Windows names of the zones (supplemental/windowsZones.json): the zone of the machine on Windows
    wz = load_json(os.path.join(cldr_core, 'supplemental', 'windowsZones.json'))['supplemental']['windowsZones']['mapTimezones']
    for m in wz:
        z = m['mapZone']
        first = z['_type'].split()[0]
        if db.execute('select count(*) from zone where name = ?', (first,)).fetchone()[0] != 1:
            raise SystemExit('windowsZones: %s is not a name of the time zone database' % first)
        db.execute('insert into windows_zone values (?, ?, ?)', (z['_other'], z['_territory'], first))
    # the place of a name: zone.tab (country, position, name, note); every name of zone.tab is a zone or a link of the database
    placed = 0
    for country, position, name, note in read_tab(os.path.join(zoneinfo, 'zone.tab'), 4):
        cur = db.execute('update zone set country = ?, position = ?, note = ? where name = ?', (country, position, note or None, name))
        if cur.rowcount != 1:
            raise SystemExit('zone.tab: no name %s' % name)
        placed += 1
    db.executemany('insert into meta_info values (?, ?)', [
        ('schema', str(SCHEMA_VERSION)),
        ('tzdata', release),
        ('cldr', load_json(os.path.join(cldr_core, 'package.json'))['version']),
        ('zones', str(len(zones))),
        ('zone_links', str(len(links))),
        ('span_horizon', str(zone_spans.SPAN_HORIZON)),
        ('countries', str(len(iso))),
        ('builder', 'tools/meta/build_meta.py'),
    ])
    db.commit()
    bad = db.execute('pragma foreign_key_check').fetchall()
    if bad:
        raise SystemExit('foreign key errors: %r' % bad[:5])
    db.execute('vacuum')
    db.close()
    return release, len(zones), len(links), len(iso), placed


def fetch(dest):
    """Download the sources of the pinned releases into `dest`; returns the three folders."""
    os.makedirs(dest, exist_ok=True)
    tz = os.path.join(dest, 'tzdata')
    if not os.path.isdir(os.path.join(tz, 'zoneinfo')):
        meta = json.load(urllib.request.urlopen('https://pypi.org/pypi/tzdata/%s/json' % TZDATA_VERSION))
        url = [u['url'] for u in meta['urls'] if u['filename'].endswith('.whl')][0]
        with zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(url).read())) as z:
            z.extractall(dest)
    folders = [tz]
    for pkg in ('cldr-core', 'cldr-localenames-modern', 'cldr-bcp47'):
        d = os.path.join(dest, pkg)
        if not os.path.isdir(d):
            blob = urllib.request.urlopen('https://registry.npmjs.org/%s/-/%s-%s.tgz' % (pkg, pkg, CLDR_VERSION)).read()
            with tarfile.open(fileobj=io.BytesIO(blob), mode='r:gz') as t:
                for m in t.getmembers():
                    m.name = m.name.split('/', 1)[1] if '/' in m.name else m.name
                    if m.name and not m.name.startswith(('..', '/')):
                        t.extract(m, d)
        folders.append(d)
    return folders


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--fetch', metavar='DIR', help='download the sources into DIR, then build')
    ap.add_argument('--src', metavar='DIR', help='the folder that --fetch filled')
    ap.add_argument('--tzdata')
    ap.add_argument('--cldr-core')
    ap.add_argument('--cldr-names')
    ap.add_argument('--cldr-bcp47')
    ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'lib', 'meta', 'meta.db'))
    a = ap.parse_args()
    if a.fetch:
        tz, core, names, bcp = fetch(a.fetch)
    elif a.src:
        tz, core, names, bcp = (os.path.join(a.src, 'tzdata'), os.path.join(a.src, 'cldr-core'), os.path.join(a.src, 'cldr-localenames-modern'), os.path.join(a.src, 'cldr-bcp47'))
    elif a.tzdata and a.cldr_core and a.cldr_names and a.cldr_bcp47:
        tz, core, names, bcp = a.tzdata, a.cldr_core, a.cldr_names, a.cldr_bcp47
    else:
        ap.error('give --fetch DIR, --src DIR, or --tzdata, --cldr-core, --cldr-names and --cldr-bcp47')
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    release, nz, nl, nc, placed = build(tz, core, names, bcp, a.out)
    print('tzdata %s: %d zones, %d links, %d placed in a country; %d countries -> %s (%d bytes)' % (release, nz, nl, placed, nc, a.out, os.path.getsize(a.out)))


if __name__ == '__main__':
    main()
