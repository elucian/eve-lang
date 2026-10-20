#!/usr/bin/env python3
"""genmanual: the generated pages of the manual and the copies of the component docs.

Usage: python script/genmanual.py [--out DIR] [--check]

Writes, in manual/ (or in DIR):
  features.md     every feature of the version map with its stage   (template design/template/manual-features.md)
  tests.md        the summary of the last run of each test suite     (template design/template/manual-tests.md)
  performance.md  the last saved ReleaseSafe benchmark run, and the totals by version
                                                                     (template design/template/manual-performance.md)
  <component>/    a copy of code/<component>/doc/ for each name of relnotes.COMPONENTS (evevm, evecp, evecm, ...)
A page is made from its template when it does not exist; afterwards only its GEN blocks are written again
and the text around them is kept. With --out the hand-written text is read from manual/ and the pages go
to DIR: script/dist.py uses it, so a distribution never changes the repository. --check writes nothing
and exits 1 when a page or a copy is out of date.
Sources: design/version_map.md, test/*/status.json, test/bmark/history.json and test/bmark/*.eve (the
`** perf:` line), read with the functions of script/relnotes.py. The pages name no folder of the
repository, so they read the same in a distribution.
Steps: `./run.sh build manual` (the repository), `./run.sh dist` (the distribution).
"""
import filecmp
import glob
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import relnotes as R  # noqa: E402
from _common import read, write  # noqa: E402

TEMPLATES = R.path('design', 'template')
STAGE_ORDER = R.STAGES + ('planned',)


def level_key(v):
    return R.vkey(v.split()[1] + '.0')


# ---------------------------------------------------------------- features.md

def features_blocks():
    feats = R.features()
    vers = sorted({f[2] for f in feats}, key=level_key)
    rows = []
    for v in vers:
        mine = [f for f in feats if f[2] == v]
        rows.append([v] + [sum(1 for f in mine if f[3] == s) for s in STAGE_ORDER] + [len(mine)])
    rows.append(['**All**'] + ['**%d**' % sum(1 for f in feats if f[3] == s) for s in STAGE_ORDER]
                + ['**%d**' % len(feats)])
    summary = R.table(('Version', 'Validated', 'Drafted', 'Design', 'Planned', 'Total'), rows)
    parts = []
    for v in vers:
        mine = [f for f in feats if f[2] == v]
        parts.append('### %s\n\n%s' % (v, R.table(('Code', 'Feature', 'Stage'),
                                                     [('`%s`' % c, n, s) for c, n, _t, s in mine])))
    return {'summary': summary, 'list': '\n\n'.join(parts)}


# ---------------------------------------------------------------- tests.md

def suites():
    """-> [(label, {name: entry})] for each test suite with a saved status, levels first."""
    out = []
    for f in sorted(glob.glob(R.path('test', '*', 'status.json'))):
        name = os.path.basename(os.path.dirname(f))
        label = 'Level ' + name[5:] if name.startswith('level') else name.capitalize()
        out.append((label, json.load(open(f, encoding='utf-8')).get('tests', {})))
    return sorted(out, key=lambda r: (not r[0].startswith('Level'), r[0]))


def tests_blocks():
    rows, failing, last = [], [], ''
    all_total = all_pass = 0
    for label, data in suites():
        passed = sum(1 for t in data.values() if t.get('status') == 'PASS')
        dates = [t.get('last', '') for t in data.values() if t.get('last')]
        when = max(dates)[:10] if dates else '-'
        last = max(last, max(dates)) if dates else last
        rows.append((label, len(data), passed, len(data) - passed,
                     '%d%%' % (100 * passed // len(data)) if data else '-', when))
        all_total += len(data)
        all_pass += passed
        for name, t in sorted(data.items()):
            if t.get('status') != 'PASS':
                failing.append((label, '`%s`' % name, t.get('status', '?'), t.get('title', ''),
                                t.get('reason', '') or '-'))
    rows.append(('**All**', '**%d**' % all_total, '**%d**' % all_pass, '**%d**' % (all_total - all_pass),
                 '**%d%%**' % (100 * all_pass // all_total) if all_total else '-', ''))
    summary = ('%d of %d tests pass; last run %s.\n\n' % (all_pass, all_total, last[:16] or 'never')
               + R.table(('Suite', 'Tests', 'Pass', 'Fail', '%', 'Last run'), rows))
    fail = (R.table(('Suite', 'Test', 'Status', 'What it tests', 'Reason'), failing) if failing
            else 'None: every test of the last run passes.')
    return {'summary': summary, 'failing': fail}


# ---------------------------------------------------------------- performance.md

def descriptions():
    out = {}
    for f in glob.glob(R.path('test', 'bmark', '*.eve')):
        for line in read(f)[0].split('\n'):
            m = re.match(r'\s*\*\*\s*perf:\s*(.*)', line)
            if m:
                out[os.path.splitext(os.path.basename(f))[0]] = m.group(1).strip()
                break
    return out


def ratio(eve, py):
    return '%.1fx' % (eve / py) if py else '-'


def performance_blocks():
    runs = R.runs()
    if not runs:
        none = 'No saved ReleaseSafe benchmark run yet.'
        return {'summary': none, 'benchmarks': none, 'results': none, 'history': none}
    run = runs[-1]
    levels = R.per_level(run)
    size = run.get('exe_bytes')
    head = ('Run of %s, version %s (commit `%s`)%s.' % (run['date'], run['version'], run.get('commit', '?'),
            ', `eve.exe` %.1f MB' % (size / (1 << 20)) if size else ''))
    summary = head + '\n\n' + R.table(
        ('Benchmarks', 'Eve', 'Python', 'Eve / Python'),
        [('Level %d' % lv, R.ms(e), R.ms(p) if p else '-', ratio(e, p)) for lv, (e, p) in sorted(levels.items())])
    desc = descriptions()
    names = sorted(run.get('results', {}))
    benchmarks = R.table(('Benchmark', 'Level', 'What it measures'),
                         [('`%s`' % n, n[1] if re.match(r'p\d', n) else '-', desc.get(n, '')) for n in names])
    rows = []
    for name in names:
        res = run['results'][name]
        py = run.get('python', {}).get(name)
        rows.append(('`%s`' % name, R.ms(res['median_ms']), R.ms(py) if py else '-',
                     ratio(res['median_ms'], py), '%.1f MB' % res['peak_mb'] if res.get('peak_mb') else '-'))
    results = R.table(('Benchmark', 'Eve', 'Python', 'Eve / Python', 'Peak memory'), rows)
    last_of = {}
    for r in runs:
        last_of[r['version']] = r
    hist = []
    for v in sorted(last_of, key=R.vkey):
        r = last_of[v]
        eve = sum(x['median_ms'] for x in r.get('results', {}).values())
        py = sum(r.get('python', {}).get(n, 0) for n in r.get('results', {}))
        hist.append((v, r['date'][:10], len(r.get('results', {})), R.ms(eve), R.ms(py) if py else '-', ratio(eve, py)))
    history = ('The last saved run of each version; the set of benchmarks grows with the versions.\n\n'
               + R.table(('Version', 'Date', 'Benchmarks', 'Eve total', 'Python total', 'Eve / Python'), hist))
    return {'summary': summary, 'benchmarks': benchmarks, 'results': results, 'history': history}


# ---------------------------------------------------------------- writing

PAGES = [('features.md', 'manual-features.md', features_blocks),
         ('tests.md', 'manual-tests.md', tests_blocks),
         ('performance.md', 'manual-performance.md', performance_blocks)]


def page_text(name, template, blocks):
    src = os.path.join(R.MANUAL, name)
    if os.path.exists(src):
        text, eol = read(src)
    else:
        text, eol = read(os.path.join(TEMPLATES, template))
        text = re.sub(r'\A(?:<!--.*?-->\n)+', '', text, flags=re.S)   # the comment that explains the template
    for block, body in blocks().items():
        text = R.put(text, block, body)
    return text, eol


def same_tree(a, b):
    if not os.path.isdir(b):
        return False
    cmp = filecmp.dircmp(a, b)
    if cmp.left_only or cmp.right_only or cmp.diff_files or cmp.funny_files:
        return False
    return all(same_tree(os.path.join(a, d), os.path.join(b, d)) for d in cmp.common_dirs)


def main(argv):
    out, check = R.MANUAL, '--check' in argv
    if '--out' in argv:
        i = argv.index('--out')
        if i + 1 >= len(argv):
            sys.exit('genmanual: --out needs a folder')
        out = os.path.abspath(argv[i + 1])
    stale = []
    for name, template, blocks in PAGES:
        text, eol = page_text(name, template, blocks)
        dst = os.path.join(out, name)
        old = read(dst)[0] if os.path.exists(dst) else None
        if old != text:
            stale.append(name)
            if not check:
                os.makedirs(out, exist_ok=True)
                write(dst, text, eol)
    copies = [(R.path('code', c, 'doc'), os.path.join(out, c), c) for c in R.COMPONENTS]
    copies += [(R.path('drivers', d, 'doc'), os.path.join(out, 'drivers', d), 'drivers/' + d) for d in R.DRIVERS]
    for src, dst, comp in copies:
        if not os.path.isdir(src):
            continue
        if not same_tree(src, dst):
            stale.append(comp + '/')
            if not check:
                shutil.rmtree(dst, ignore_errors=True)
                shutil.copytree(src, dst)
    where = os.path.relpath(out, R.ROOT).replace('\\', '/')
    if check:
        for s in stale:
            print('genmanual: out of date: %s/%s' % (where, s))
        return 1 if stale else 0
    print('genmanual: %s: %s' % (where, ', '.join(stale) if stale else 'up to date'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
