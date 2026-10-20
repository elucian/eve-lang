#!/usr/bin/env python3
"""The feature map of design/feature_map.md: a paragraph per level, a subtitle and a paragraph per feature, tables made from them.

  python script/featmap.py --write       rewrite the generated tables and counts from the level and feature sections
  python script/featmap.py --check       exit 1 when a table is stale, a feature has no Status line, or a code is used twice
  python script/featmap.py --verify      compare each Status with the results of its Tests line (test/levelN/status.json, left by runtest.py)
  python script/featmap.py --evidence    features whose status disagrees with the code tags (@feature) and the tests found
  python script/featmap.py --list [open|partial|done] [1..7|all]   one line per feature

Versions are not used in the map: a feature belongs to a level (1 to 7) or to "All levels" (tools, documents,
the bytecode machine, the release). Format of design/feature_map.md:

    ## Levels                       a generated table: level, name, status, features done, decisions, tests
    <!-- GEN:levels --> ... <!-- /GEN:levels -->
    ## Level 5: Data and database   one paragraph that describes the level
    <!-- GEN:features -->           the count and the table of the level (Code links to the subtitle below)
    <!-- /GEN:features -->
    ### F-LNG-12 Generators         one subtitle per feature
    **Status:** done
    **Tests:** level5: e23 e24      optional: the tests of the feature, ids without the rest of the name
    The paragraph: what the feature is. State, decisions, tests.

The Status line of a feature is the only place a status is written; edit it, run `--write` (the pre-commit hook does).
The status of a level is derived: planned (nothing started), in progress, done (every feature done).
Other scripts read the features through `load()`: plan.py, relnotes.py, tagcheck.py.
"""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
MAP = os.path.join(ROOT, 'design', 'feature_map.md')
CODE = r'F-[A-Z]+-\d+'
STATUS = r'(?:✓ )?(?:done|partial|open|dropped)'
LEVEL = re.compile(r'^## (?:Level (\d+)|(All levels))\b:?\s*(.*)$')
FEATURE = re.compile(r'^### (' + CODE + r') (.+?)\s*$')
STATUS_LINE = re.compile(r'^\*\*Status:\*\*\s*(' + STATUS + r')\b')
GEN = {'features': ('<!-- GEN:features -->', '<!-- /GEN:features -->'),
       'levels': ('<!-- GEN:levels -->', '<!-- /GEN:levels -->')}


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


def level_key(m):
    return m.group(1) or 'all'


def levels(text=None):
    """-> [(key, heading text, name)] in file order; key is '1'..'7' or 'all'."""
    out = []
    for ln in (text if text is not None else read()).split('\n'):
        m = LEVEL.match(ln)
        if m:
            nm = m.group(3).strip() or 'All levels'
            out.append((level_key(m), ln[3:].strip(), nm[0].upper() + nm[1:]))
    return out


def load(text=None):
    """-> [(level, code, name, status, description)] in file order, from the feature sections."""
    lines = (text if text is not None else read()).split('\n')
    out, lvl, i = [], None, 0
    while i < len(lines):
        m = LEVEL.match(lines[i])
        if m:
            lvl = level_key(m)
        elif lines[i].startswith('## '):
            lvl = None
        f = FEATURE.match(lines[i]) if lvl else None
        if f:
            code, name = f.groups()
            j = i + 1
            while j < len(lines) and lines[j].strip() == '':
                j += 1
            s = STATUS_LINE.match(lines[j]) if j < len(lines) else None
            k = j + 1
            while k < len(lines) and not lines[k].startswith('#'):
                k += 1
            desc = '\n'.join(x for x in lines[j + 1:k] if not x.startswith('**Tests:**')).strip()
            out.append((lvl, code, name, s.group(1) if s else '?', desc))
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


def level_status(rows):
    d, p, n = counts(rows)
    if n and d == n:
        return 'done'
    return 'in progress' if d or p else 'planned'


def features_block(rows):
    b, e = GEN['features']
    d, p, n = counts(rows)
    out = [b, '%d of %d features done%s.' % (d, n, ' (%d partial)' % p if p else ''), '',
           '| Code | Feature | Status |', '|---|---|---|']
    for lvl, code, name, status, desc in rows:
        out.append('| [%s](#%s) | %s | %s |' % (code, slug(code + ' ' + name), name, status))
    out.append(e)
    return '\n'.join(out)


def levels_block(text, rows):
    b, e = GEN['levels']
    out = [b, '| Level | Name | Status | Features done | Decisions | Tests |', '|---|---|---|---|---|---|']
    for key, heading, name in levels(text):
        mine = [r for r in rows if r[0] == key]
        d, p, n = counts(mine)
        label = 'Level ' + key if key != 'all' else 'All levels'
        dec = '[level%s.md](decision/level%s.md)' % (key, key) if key != 'all' else '-'
        tst = '`test/level%s` (%s)' % (key, chr(96 + int(key))) if key != 'all' else '-'
        out.append('| [%s](#%s) | %s | %s | %d of %d | %s | %s |' % (label, slug(heading), name, level_status(mine), d, n, dec, tst))
    out.append(e)
    return '\n'.join(out)


def regenerate(text):
    rows = load(text)
    by = {}
    for r in rows:
        by.setdefault(r[0], []).append(r)
    lines = text.split('\n')
    out, i, cur = [], 0, None
    while i < len(lines):
        m = LEVEL.match(lines[i])
        if m:
            cur = level_key(m)
        for kind, (b, e) in GEN.items():
            if lines[i] == b:
                j = i
                while lines[j] != e:
                    j += 1
                out.append(features_block(by.get(cur, [])) if kind == 'features' else levels_block(text, rows))
                i = j + 1
                break
        else:
            out.append(lines[i])
            i += 1
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
    print('featmap: %d features in %d levels, %d problem(s)' % (len(rows), len(levels(text)), bad))
    return 1 if bad else 0


def tag_files():
    tagged = {}
    for r, d, fs in os.walk(os.path.join(ROOT, 'code')):
        d[:] = [x for x in d if x not in ('.zig-cache', 'zig-pkg', 'zig-out')]
        for f in fs:
            if f.endswith('.zig'):
                t = open(os.path.join(r, f), encoding='utf8', errors='ignore').read()
                for ln in t.split(chr(10)):
                    if '@feature' in ln:
                        for c in re.findall(CODE, ln):
                            tagged.setdefault(c, set()).add(os.path.relpath(os.path.join(r, f), ROOT).replace(os.sep, '/'))
    return tagged


def evidence():
    rows = load()
    tagged = tag_files()
    tests = {}
    for r, d, fs in os.walk(os.path.join(ROOT, 'test')):
        for f in fs:
            if f.endswith('.eve'):
                t = open(os.path.join(r, f), encoding='utf8', errors='ignore').read()
                for c in set(re.findall(CODE, t)):
                    tests.setdefault(c, set()).add(f)
    print('code = files with @feature in code/, tests = test files that name the feature\n')
    print('%-5s %-9s %-8s %4s %5s  %s' % ('level', 'code', 'status', 'code', 'tests', 'check'))
    for lvl, c, n, st, d in rows:
        nc, nt = len(tagged.get(c, ())), len(tests.get(c, ()))
        flag = ''
        if st in ('open', 'partial') and nc >= 1:
            flag = 'code exists: review the status'
        elif 'done' in st and nc == 0:
            flag = 'done, no code tag'
        if flag:
            print('%-5s %-9s %-8s %4d %5d  %s' % (lvl, c, st[:8], nc, nt, flag))
    print('\nfeatures without any code tag: %d of %d; with a test naming them: %d' % (
        sum(1 for r in rows if r[1] not in tagged), len(rows), sum(1 for r in rows if r[1] in tests)))
    return 0


def test_lines(text=None):
    """-> {code: [(level folder, [test ids])]} from the optional **Tests:** line of each feature section."""
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
    lv = [x for x in a if re.fullmatch(r'[1-7]|all', x)]
    for l, c, n, st, d in load():
        if (not want or any(w in st for w in want)) and (not lv or l in lv):
            print('L%-3s %-9s %-8s %s' % (l, c, st[:8], n[:70]))


def main(a):
    if '--write' in a:
        t = read(); n = regenerate(t)
        if n != t:
            write(n); print('feature_map.md: tables rewritten')
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
