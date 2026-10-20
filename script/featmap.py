#!/usr/bin/env python3
"""The feature map of design/version_map.md: one subtitle and one paragraph per feature, tables made from them.

  python script/featmap.py --migrate     one time: turn the old tables (Code | Feature | Status | Description) into feature sections
  python script/featmap.py --write       rewrite the generated tables and counts from the feature sections
  python script/featmap.py --check       exit 1 when a table is stale, a section has no Status line, or an anchor is not unique
  python script/featmap.py --evidence    features whose status disagrees with the code tags (@feature) and the tests found
  python script/featmap.py --verify      compare each Status with the results of its Tests line (test/levelN/status.json, left by runtest.py)
  python script/featmap.py --list [open|partial|done] [0.5]   one line per feature

Format of a version section of design/version_map.md:

    ## Version 0.4: Data and database (level 5)
    ...intro...
    <!-- GEN:features -->   the count line and the table (Code is a link to the subtitle below), written by --write
    <!-- /GEN:features -->
    Exit: ...
    ### F-LNG-12 Generators
    **Status:** open
    **Tests:** level5: e23 e24 e26        (optional: the tests of the feature, ids without the rest of the name)
    The paragraph: what the feature is. **State.** what exists, with decisions and tests.

The Status line of a feature is the only place a status is written; edit it, run `--write` (the pre-commit hook does), done.
Other scripts read the features through `load()`: plan.py, relnotes.py, tagcheck.py.
"""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
MAP = os.path.join(ROOT, 'design', 'version_map.md')
CODE = r'F-[A-Z]+-\d+'
STATUS = r'(?:✓ )?(?:done|partial|open|dropped)'
OLD_ROW = re.compile(r'^\|\s*(' + CODE + r')\s*\|\s*(.*?)\s*\|\s*(' + STATUS + r')\s*\|\s*(.*?)\s*\|\s*$')
VERSION = re.compile(r'^## Version (\d+\.\d+)\b')
FEATURE = re.compile(r'^### (' + CODE + r') (.+?)\s*$')
STATUS_LINE = re.compile(r'^\*\*Status:\*\*\s*(' + STATUS + r')\b')
GEN_BEGIN, GEN_END = '<!-- GEN:features -->', '<!-- /GEN:features -->'
OVERVIEW_ROW = re.compile(r'^(\| Version (\d+\.\d+) \|.*\| )(\d+ of \d+)( \| .*)$')


def slug(h):
    h = h.strip().lower().replace('`', '')
    h = re.sub(r'[^\w\s-]', '', h, flags=re.U)
    return re.sub(r'\s', '-', h)


def read():
    with open(MAP, encoding='utf-8', newline='') as f:
        return f.read()


def write(text):
    with open(MAP, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def load(text=None):
    """-> [(version, code, name, status, description)] in file order, from the feature sections."""
    lines = (text if text is not None else read()).split('\n')
    out, ver, i = [], None, 0
    while i < len(lines):
        m = VERSION.match(lines[i])
        if m:
            ver = m.group(1)
        elif lines[i].startswith('## '):
            ver = None
        f = FEATURE.match(lines[i]) if ver else None
        if f:
            code, name = f.groups()
            j = i + 1
            while j < len(lines) and lines[j].strip() == '':
                j += 1
            s = STATUS_LINE.match(lines[j]) if j < len(lines) else None
            k = j + 1
            while k < len(lines) and not lines[k].startswith('#'):
                k += 1
            desc = '\n'.join(lines[j + 1:k]).strip()
            out.append((ver, code, name, s.group(1) if s else '?', desc))
            i = k
            continue
        i += 1
    return out


def all_codes(text=None):
    """Every feature code of the map: the sections and the table of dropped features."""
    t = text if text is not None else read()
    return {r[1] for r in load(t)} | set(re.findall(r'^\|\s*(' + CODE + r')\s*\|', t, re.M))


def counts(rows):
    done = sum(1 for r in rows if 'done' in r[3])
    part = sum(1 for r in rows if r[3] == 'partial')
    return done, part, len(rows)


def table_block(rows):
    d, p, n = counts(rows)
    out = [GEN_BEGIN, '%d of %d features done%s.' % (d, n, ' (%d partial)' % p if p else ''), '',
           '| Code | Feature | Status |', '|---|---|---|']
    for ver, code, name, status, desc in rows:
        out.append('| [%s](#%s) | %s | %s |' % (code, slug(code + ' ' + name), name, status))
    out.append(GEN_END)
    return '\n'.join(out)


def regenerate(text):
    rows = load(text)
    by = {}
    for r in rows:
        by.setdefault(r[0], []).append(r)
    lines = text.split('\n')
    out, i = [], 0
    while i < len(lines):
        if lines[i] == GEN_BEGIN:
            j = i
            while lines[j] != GEN_END:
                j += 1
            # the version of the section is the last "## Version" line written so far
            ver = next(VERSION.match(x).group(1) for x in reversed(out) if VERSION.match(x))
            out.append(table_block(by.get(ver, [])))
            i = j + 1
            continue
        m = OVERVIEW_ROW.match(lines[i])
        if m and m.group(2) in by:
            d, p, n = counts(by[m.group(2)])
            lines[i] = '%s%d of %d%s' % (m.group(1), d, n, m.group(4))
        out.append(lines[i])
        i += 1
    return '\n'.join(out)


def migrate(text):
    lines = text.split('\n')
    out, i = [], 0
    while i < len(lines):
        m = VERSION.match(lines[i])
        if not m:
            out.append(lines[i]); i += 1; continue
        j = i + 1
        while j < len(lines) and not lines[j].startswith('## '):
            j += 1
        sec = lines[i:j]
        rows, body, placed = [], [], False
        k = 0
        while k < len(sec):
            r = OLD_ROW.match(sec[k])
            if sec[k].startswith('| Code | Feature | Status | Description |'):
                k += 2          # header and separator
                if not placed:
                    body.append(GEN_BEGIN); body.append(GEN_END); placed = True
                continue
            if r:
                rows.append(r.groups()); k += 1; continue
            if re.match(r'^\d+ of \d+ features done', sec[k]):
                k += 1
                if k < len(sec) and sec[k] == '':
                    k += 1
                continue
            body.append(sec[k]); k += 1
        while body and body[-1] == '':
            body.pop()
        out.extend(body)
        for code, name, status, desc in rows:
            out += ['', '### %s %s' % (code, name), '', '**Status:** %s' % status, '']
            d = desc.strip()
            cut = re.search(r'\s\*(?:Partial|Done|Open|Not done|State)\b', d)
            if cut and cut.start() > 40:
                out += [d[:cut.start()].strip(), '', d[cut.start():].strip()]
            else:
                out.append(d)
        out.append('')
        i = j
    return '\n'.join(out)


def check():
    text = read()
    bad = 0
    rows = load(text)
    seen = set()
    for r in rows:
        if r[3] == '?':
            print('no Status line: %s' % r[1]); bad += 1
        if r[1] in seen:
            print('twice: %s' % r[1]); bad += 1
        seen.add(r[1])
    if regenerate(text) != text:
        print('stale tables: run python script/featmap.py --write'); bad += 1
    print('featmap: %d features, %d problem(s)' % (len(rows), bad))
    return 1 if bad else 0


def evidence():
    import subprocess
    rows = load()
    tagged = {}
    for r, d, fs in os.walk(os.path.join(ROOT, 'code')):
        d[:] = [x for x in d if x not in ('.zig-cache', 'zig-pkg', 'zig-out')]
        for f in fs:
            if f.endswith('.zig'):
                t = open(os.path.join(r, f), encoding='utf8', errors='ignore').read()
                for ln in t.split('\n'):
                    if '@feature' in ln:
                        for c in re.findall(CODE, ln):
                            tagged.setdefault(c, set()).add(os.path.relpath(os.path.join(r, f), ROOT).replace(os.sep, '/'))
    tests = {}
    for r, d, fs in os.walk(os.path.join(ROOT, 'test')):
        for f in fs:
            if f.endswith('.eve'):
                t = open(os.path.join(r, f), encoding='utf8', errors='ignore').read()
                for c in set(re.findall(CODE, t)):
                    tests.setdefault(c, set()).add(os.path.relpath(os.path.join(r, f), ROOT).replace(os.sep, '/'))
    print('code = files with @feature in code/, tests = test files that name the feature\n')
    print('%-5s %-9s %-8s %4s %5s  %s' % ('ver', 'code', 'status', 'code', 'tests', 'check'))
    for ver, c, n, st, d in rows:
        nc, nt = len(tagged.get(c, ())), len(tests.get(c, ()))
        flag = ''
        if st in ('open', 'partial') and nc >= 2:
            flag = 'code exists: review the status'
        elif 'done' in st and nc == 0:
            flag = 'done, no code tag'
        if flag:
            print('%-5s %-9s %-8s %4d %5d  %s' % (ver, c, st[:8], nc, nt, flag))
    print('\nfeatures without any code tag: %d of %d; with a test naming them: %d' % (
        sum(1 for r in rows if r[1] not in tagged), len(rows), sum(1 for r in rows if r[1] in tests)))
    return 0


def test_lines(text=None):
    """-> {code: [(level, [test ids])]} from the optional **Tests:** line of each feature section."""
    out, code = {}, None
    for ln in (text if text is not None else read()).split(chr(10)):
        f = FEATURE.match(ln)
        if f:
            code = f.group(1)
        elif ln.startswith('## '):
            code = None
        elif code and ln.startswith('**Tests:**'):
            for part in ln[len('**Tests:**'):].split(';'):
                lvl, _, ids = part.partition(':')
                out.setdefault(code, []).append((lvl.strip(), ids.split()))
    return out


def verify():
    import json
    rows = {r[1]: r for r in load()}
    bad = 0
    for code, groups in test_lines().items():
        total = passed = 0
        missing = []
        for lvl, ids in groups:
            p = os.path.join(ROOT, 'test', lvl, 'status.json')
            tests = json.load(open(p, encoding='utf-8')).get('tests', {}) if os.path.exists(p) else {}
            for i in ids:
                hit = [t for t in tests if t == i or t.startswith(i + '_')]
                if not hit:
                    missing.append(lvl + ':' + i); continue
                total += 1
                passed += 1 if all(tests[t].get('status') == 'PASS' for t in hit) else 0
        st = rows[code][3] if code in rows else '?'
        msg = ''
        if missing:
            msg = 'no such test: ' + ' '.join(missing)
        elif passed < total and 'done' in st:
            msg = 'status is done but %d test(s) fail' % (total - passed)
        elif passed == total and st == 'open':
            msg = 'all tests pass: the status can be partial or done'
        if msg:
            bad += 1
        print('%-9s %-8s %2d/%2d pass  %s' % (code, st[:8], passed, total, msg))
    print('featmap: %d feature(s) with a Tests line, %d to review' % (len(test_lines()), bad))
    return 1 if bad else 0


def listing(a):
    want = [x for x in a if x in ('open', 'partial', 'done', 'dropped')]
    ver = [x for x in a if re.fullmatch(r'\d+\.\d+', x)]
    for v, c, n, st, d in load():
        if (not want or any(w in st for w in want)) and (not ver or v in ver):
            print('%s  %-9s %-8s %s' % (v, c, st[:8], n[:70]))


def main(a):
    if '--migrate' in a:
        write(regenerate(migrate(read()))); print('migrated: %d features' % len(load()))
    elif '--write' in a:
        t = read(); n = regenerate(t)
        if n != t:
            write(n); print('version_map.md: tables rewritten')
    elif '--check' in a:
        return check()
    elif '--evidence' in a:
        return evidence()
    elif '--verify' in a:
        return verify()
    elif '--list' in a:
        listing(a)
    else:
        print(__doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
