#!/usr/bin/env python3
"""Release notes and the progress paragraph of the manual (D-153; policy: manual/release/README.md).

  python script/relnotes.py [X.Y.Z]     write the notes of release X.Y.Z and refresh the manual
  python script/relnotes.py --manual    refresh only the progress and links of manual/README.md, from
                                        the working tree (between releases; no notes are written)
  python script/relnotes.py --check     write nothing; exit 1 on a problem (see below)

X.Y.Z defaults to the version of evevm/src/version.zig, the one `script/release.py` just set.
Files written:
  manual/release/vX.Y.Z.md    made from manual/release/template.md when missing. Afterwards only the
                              blocks between <!-- GEN:<name> --> and <!-- /GEN:<name> --> are written
                              again; the text around them (Highlights, Decisions, ...) is kept.
  manual/README.md            the blocks "progress" (tests, features, performance of the release)
                              and "links" (spec, tutorial, test readme files)
  manual/release/README.md    the block "releases" (one line per notes file)
Notes of an older or tagged release are never written: a release is a record.

Sources: plan/version_map.md (features and status), test/*/status.json (tests, as runtest.py left
them: run `python script/runtest.py all` first), test/bmark/history.json (saved ReleaseSafe runs:
run `bmark.py --save` first), and the notes of the previous release (stages before, timings before).

Stage of a feature, from its row in version_map.md:
  validated   status "✓ done": implemented (or delivered) and its tests pass
  drafted     status "partial", or "open" with tests written first ("written first" in the description)
  design      status "open" and the description names a decision (D-nnn) or a design file (*.md)
  planned     any other open feature: counted, not listed
Dropped and replaced features are left out.

--check fails when: a relative link in manual/ does not name a tracked file or folder with the exact
case (GitHub is case-sensitive: the test folders hold readme.md, not README.md); a link to the tutorial
names a page that does not exist; the notes of the current version still hold "TODO"; the list of
releases is stale.
"""
import glob
import json
import os
import re
import subprocess
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import read, write  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
MANUAL = os.path.join(ROOT, 'manual')
RELEASE = os.path.join(MANUAL, 'release')
SITE = 'https://sagecode.org/projects/eve/'
STAGES = ('validated', 'drafted', 'design')
V = r'\d+\.\d+\.\d+'


def path(*parts):
    return os.path.join(ROOT, *parts)


def vkey(v):
    return tuple(int(x) for x in v.split('.'))


def git(*args):
    r = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
    return r.stdout.strip() if r.returncode == 0 else ''


def current_version():
    m = re.search(r'pub const version = "(' + V + ')"', read(path('evevm', 'src', 'version.zig'))[0])
    return m.group(1) if m else sys.exit('relnotes: no version in evevm/src/version.zig')


# ---------------------------------------------------------------- sources

def features():
    """-> [(code, name, target version, stage or 'planned')] from the tables of version_map.md."""
    out, target = [], None
    for line in read(path('plan', 'version_map.md'))[0].split('\n'):
        m = re.match(r'## (Version \d+\.\d+)', line)
        if m:
            target = m.group(1)
        elif line.startswith('## '):
            target = None
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if not target or len(cells) < 4 or not re.fullmatch(r'F-[A-Z]+-\d+', cells[0]):
            continue
        status, desc = cells[2], ' '.join(cells[3:])
        if 'done' in status:
            stage = 'validated'
        elif status == 'partial' or (status == 'open' and 'written first' in desc):
            stage = 'drafted'
        elif status == 'open' and re.search(r'\bD-\d+|\.md\b', desc):
            stage = 'design'
        elif status == 'open':
            stage = 'planned'
        else:
            continue
        out.append((cells[0], cells[1], target, stage))
    return out


def tests():
    """-> [(label, readme path, total, passed)] for each test folder with a status.json."""
    out = []
    for folder in sorted(glob.glob(path('test', '*', 'status.json'))):
        name = os.path.basename(os.path.dirname(folder))
        data = json.load(open(folder, encoding='utf-8')).get('tests', {})
        passed = sum(1 for t in data.values() if t.get('status') == 'PASS')
        label = 'Level ' + name[5:] if name.startswith('level') else name.capitalize()
        out.append((label, tracked_readme('test/' + name), len(data), passed))
    for name in ('level%d' % n for n in range(1, 8)):          # a level with no run yet
        if not any(r[1] and ('/' + name + '/') in r[1] for r in out) and os.path.isdir(path('test', name)):
            out.append(('Level ' + name[5:], tracked_readme('test/' + name), 0, 0))
    return sorted(out, key=lambda r: (not r[0].startswith('Level'), r[0]))


def runs():
    try:
        return [r for r in json.load(open(path('test', 'bmark', 'history.json'), encoding='utf-8'))
                if r.get('build') == 'ReleaseSafe']
    except OSError:
        return []


def run_of(version):
    found = [r for r in runs() if r.get('version') == version]
    return found[-1] if found else None


def per_level(run):
    """-> {level: (eve ms, python ms or None)} summed over the benchmarks p<level>x_*."""
    out = {}
    for name, res in run.get('results', {}).items():
        m = re.match(r'p(\d)', name)
        if not m:
            continue
        eve, py = out.get(int(m.group(1)), (0.0, 0.0))
        p = run.get('python', {}).get(name)
        out[int(m.group(1))] = (eve + res['median_ms'], None if (p is None or py is None) else py + p)
    return out


# ---------------------------------------------------------------- tracked files and links

_TRACKED = None


def tracked():
    global _TRACKED
    if _TRACKED is None:
        # tracked files, and new files not yet committed (but not the ignored ones: tutorial/, temp/)
        _TRACKED = set(git('ls-files', '--cached', '--others', '--exclude-standard').split('\n'))
    return _TRACKED


def tracked_readme(folder):
    for f in sorted(tracked()):
        if f.lower() == folder.lower() + '/readme.md':
            return f
    return None


def link(target, text, here='manual'):
    """A Markdown link from a file of folder `here` to the tracked file `target`."""
    return '[%s](%s)' % (text, os.path.relpath(path(target), path(here)).replace('\\', '/'))


# ---------------------------------------------------------------- previous release

def notes_files():
    out = []
    for f in glob.glob(os.path.join(RELEASE, 'v*.md')):
        m = re.fullmatch(r'v(' + V + r')\.md', os.path.basename(f))
        if m:
            out.append(m.group(1))
    return sorted(out, key=vkey)


def previous(version):
    older = [v for v in notes_files() if vkey(v) < vkey(version)]
    return older[-1] if older else None


def stages_in(version):
    text = read(os.path.join(RELEASE, 'v%s.md' % version))[0]
    block = re.search(r'<!-- GEN:stages[^>]*-->(.*?)<!-- /GEN:stages -->', text, re.S)
    out = {}
    for line in (block.group(1) if block else '').split('\n'):
        cells = [c.strip().strip('`') for c in line.strip().strip('|').split('|')]
        if len(cells) >= 4 and re.fullmatch(r'F-[A-Z]+-\d+', cells[0]):
            out[cells[0]] = cells[3]
    return out


# ---------------------------------------------------------------- blocks

def table(head, rows):
    out = ['| ' + ' | '.join(head) + ' |', '|' + '---|' * len(head)]
    out += ['| ' + ' | '.join(str(c) for c in r) + ' |' for r in rows]
    return '\n'.join(out)


def ms(x):
    return '%d ms' % round(x)


def change(now, before):
    if not before:
        return '-'
    d = (now - before) / before * 100
    return '%+.0f%%' % d + (' (faster)' if d <= -5 else ' (slower)' if d >= 5 else '')


def perf_rows(version, prev_version):
    run = run_of(version)
    if not run:
        return None, None
    base = run_of(prev_version) if prev_version else None
    if not base:          # no previous notes: compare with the last run of an older version
        older = [r for r in runs() if vkey(r['version']) < vkey(version)]
        base = older[-1] if older else None
    now, before = per_level(run), per_level(base) if base else {}
    rows = []
    for lv in sorted(now):
        eve, py = now[lv]
        ratio = '%.1fx' % (eve / py) if py else '-'
        rows.append(('Level %d' % lv, ms(eve), ms(py) if py else '-', ratio,
                     change(eve, before.get(lv, (0, 0))[0]) if before else '-'))
    return (run, base), rows


def gen_head(version, prev):
    commit = git('rev-parse', '--short', 'HEAD') or '?'
    prev_text = link('manual/release/v%s.md' % prev, prev, 'manual/release') if prev else 'none (first notes)'
    return '\n'.join([
        '| Release | Date | Commit | Previous release |',
        '|---|---|---|---|',
        '| %s | %s | `%s` | %s |' % (version, date.today().isoformat(), commit, prev_text)])


def gen_progress(version, feats, test_rows, here):
    rows = [(link(readme, label, here) if readme else label, total, passed,
             '%d%%' % (100 * passed // total) if total else '-') for label, readme, total, passed in test_rows]
    total = sum(r[2] for r in test_rows)
    passed = sum(r[3] for r in test_rows)
    vers = sorted({f[2] for f in feats}, key=lambda v: vkey(v.split()[1] + '.0'))
    frows = []
    for v in vers:
        mine = [f for f in feats if f[2] == v]
        frows.append([v] + [sum(1 for f in mine if f[3] == s) for s in STAGES + ('planned',)] + [len(mine)])
    frows.append(['**All**'] + ['**%d**' % sum(1 for f in feats if f[3] == s) for s in STAGES + ('planned',)]
                 + ['**%d**' % len(feats)])
    return '\n'.join([
        '**Tests.** %d of %d conformance and smoke tests pass (the status that `script/runtest.py` saved):' % (passed, total),
        '', table(('Tests', 'Total', 'Pass', '%'), rows), '',
        '**Features.** By target version and stage (stages: %s):' % link('manual/release/README.md', 'policy', here),
        '', table(('Version', 'Validated', 'Drafted', 'Design', 'Planned', 'Total'), frows)])


def gen_performance(version, prev, here):
    pair, rows = perf_rows(version, prev)
    bm = link('test/bmark/README.md', 'test/bmark/README.md', here)
    if not rows:
        return ('TODO: no saved ReleaseSafe benchmark run of %s. Run `python script/bmark.py --build ReleaseSafe '
                '--eve temp/rel/bin/eve.exe --save`, then this script again. Benchmarks: %s.' % (version, bm))
    run, base = pair
    since = 'version %s (%s)' % (base['version'], base['date'][:10]) if base else 'nothing (first run)'
    return '\n'.join([
        'Total median time of the benchmarks of each level, ReleaseSafe build, run of %s (commit `%s`), '
        'against the twins in Python and against %s. Notes by version and history: %s.'
        % (run['date'], run.get('commit', '?'), since, bm),
        '', table(('Benchmarks', 'Eve', 'Python', 'Eve / Python', 'Change'), rows)])


def gen_changes(version, prev, feats):
    before = stages_in(prev) if prev else {}
    rows = []
    for code, name, target, stage in feats:
        if stage == 'planned':
            continue
        old = before.get(code, 'planned' if prev else '-')
        if old != stage:
            rows.append(('`%s`' % code, name, target, old, '**%s**' % stage))
    if not rows:
        return 'No feature changed stage since %s.' % prev
    intro = ('Every feature that changed stage since %s.' % prev if prev else
             'First notes: every feature that is designed, drafted or validated.')
    return intro + '\n\n' + table(('Code', 'Feature', 'Target', 'Before', 'Now'), rows)


def gen_stages(feats):
    rows = [('`%s`' % c, n, t, s) for c, n, t, s in feats if s != 'planned']
    return ('The stage of every feature at this release (read by the notes of the next release; '
            'planned features are not listed).\n\n' + table(('Code', 'Feature', 'Target', 'Stage'), rows))


def gen_links(here):
    spec = [('spec/README.md', 'Specification: conventions'), ('spec/index.md', 'Specification: contents'),
            ('spec/conformance/README.md', 'Conformance tests: format')]
    tests = [('test/readme.md', 'Tests: how to run them')]
    for f in sorted(tracked()):
        m = re.fullmatch(r'test/([^/]+)/readme\.md', f, re.I)
        if m and m.group(1) != 'bmark':          # the benchmarks have their own line below
            tests.append((f, 'Tests: ' + ('level ' + m.group(1)[5:] if m.group(1).startswith('level')
                                          else m.group(1))))
    tut = [('index.html', 'Tutorial: topics'), ('features.html', 'Tutorial: feature tests'),
           ('quality.html', 'Tutorial: smoke test and performance'), ('vm.html', 'Tutorial: the Eve VM')]
    out = ['- ' + link(f, t, here) for f, t in spec + tests if f in tracked()]
    out += ['- [%s](%s%s)' % (t, SITE, p) for p, t in tut]
    out += ['- ' + link('test/bmark/README.md', 'Performance: benchmarks and notes by version', here),
            '- ' + link('plan/version_map.md', 'Versions and features', here)]
    return '\n'.join(out)


def gen_releases():
    vs = notes_files()[::-1]
    if not vs:
        return 'No release notes yet.'
    return '\n'.join('- [%s](v%s.md)' % (v, v) for v in vs)


def put(text, name, body):
    pat = re.compile(r'(<!-- GEN:%s[^>]*-->\n).*?(<!-- /GEN:%s -->)' % (name, name), re.S)
    if not pat.search(text):
        sys.exit('relnotes: block GEN:%s missing' % name)
    return pat.sub(lambda m: m.group(1) + body.rstrip('\n') + '\n' + m.group(2), text)


# ---------------------------------------------------------------- check

def check_links():
    bad = []
    low = {}
    for f in tracked():
        parts = f.split('/')
        for i in range(1, len(parts) + 1):
            low.setdefault('/'.join(parts[:i]).lower(), set()).add('/'.join(parts[:i]))
    exact = set(x for s in low.values() for x in s)
    for md in glob.glob(os.path.join(MANUAL, '**', '*.md'), recursive=True):
        text = read(md)[0]
        here = os.path.dirname(md)
        for m in re.finditer(r'\]\(([^)\s]+)\)', text):
            target = m.group(1).split('#')[0]
            where = os.path.relpath(md, ROOT).replace('\\', '/')
            if target.startswith(SITE):
                page = target[len(SITE):]
                if os.path.isdir(path('tutorial')) and page and page not in os.listdir(path('tutorial')):
                    bad.append('%s: tutorial page not found: %s' % (where, page))
                continue
            if not target or re.match(r'[a-z]+:', target):
                continue
            rel = os.path.relpath(os.path.normpath(os.path.join(here, target)), ROOT).replace('\\', '/')
            if rel not in exact:
                hint = low.get(rel.lower())
                bad.append('%s: %s%s' % (where, target, ' (case: %s)' % sorted(hint)[0] if hint else ' (missing)'))
    return bad


def write_manual(intro, version, prev):
    """The blocks progress and links of manual/README.md."""
    mtext, meol = read(os.path.join(MANUAL, 'README.md'))
    progress = (intro + gen_progress(version, features(), tests(), 'manual') + '\n\n**Performance.** '
                + gen_performance(version, prev, 'manual'))
    mtext = put(mtext, 'progress', progress)
    mtext = put(mtext, 'links', gen_links('manual'))
    write(os.path.join(MANUAL, 'README.md'), mtext, meol)
    print('wrote manual/README.md (progress, links)')


# ---------------------------------------------------------------- main

def main(args):
    if any(a in ('-h', '--help') for a in args):
        print(__doc__)
        return 0
    check, manual_only = '--check' in args, '--manual' in args
    rest = [a for a in args if a not in ('--check', '--manual')]
    version = rest[0] if rest else current_version()
    if not re.fullmatch(V, version):
        sys.exit('relnotes: %r is not a version X.Y.Z' % version)

    if check:
        problems = check_links()
        notes = os.path.join(RELEASE, 'v%s.md' % version)
        if os.path.exists(notes) and 'TODO' in read(notes)[0]:
            problems.append('manual/release/v%s.md: still holds TODO' % version)
        rtext = read(os.path.join(RELEASE, 'README.md'))[0]
        if put(rtext, 'releases', gen_releases()) != rtext:
            problems.append('manual/release/README.md: the list of releases is stale (run relnotes.py)')
        for p in problems:
            print(p)
        print('relnotes: %d problem(s)' % len(problems))
        return 1 if problems else 0

    if manual_only:
        last = notes_files()[-1] if notes_files() else None
        record = link('manual/release/v%s.md' % last, 'release notes %s' % last) if last else 'no release notes yet'
        write_manual('State of the working tree on %s, version %s, not a release; last release: %s.\n\n'
                     % (date.today().isoformat(), version, record), version, last)
        return 0
    newer = [v for v in notes_files() if vkey(v) > vkey(version)]
    if newer:
        sys.exit('relnotes: notes of %s exist; the notes of %s are a record and stay as they are' % (newer[-1], version))
    if git('tag', '--list', 'v' + version):
        sys.exit('relnotes: v%s is tagged: its notes are a record and stay as they are' % version)
    feats, test_rows, prev = features(), tests(), previous(version)

    notes = os.path.join(RELEASE, 'v%s.md' % version)
    if os.path.exists(notes):
        text, eol = read(notes)
    else:
        text, eol = read(os.path.join(RELEASE, 'template.md'))
        text = text.replace('X.Y.Z', version)
        text = re.sub(r'\A(?:<!--.*?-->\n)+', '', text, flags=re.S)   # the comment that explains the template
    here = 'manual/release'
    text = put(text, 'head', gen_head(version, prev))
    text = put(text, 'changes', gen_changes(version, prev, feats))
    text = put(text, 'progress', gen_progress(version, feats, test_rows, here))
    text = put(text, 'performance', gen_performance(version, prev, here))
    text = put(text, 'links', gen_links(here))
    text = put(text, 'stages', gen_stages(feats))
    write(notes, text, eol)
    print('wrote manual/release/v%s.md' % version)

    write_manual('Progress at release %s (%s); full record: %s.\n\n'
                 % (version, date.today().isoformat(), link('manual/release/v%s.md' % version, 'release notes %s' % version)),
                 version, prev)

    rtext, reol = read(os.path.join(RELEASE, 'README.md'))
    write(os.path.join(RELEASE, 'README.md'), put(rtext, 'releases', gen_releases()), reol)
    print('wrote manual/release/README.md (releases)')
    if 'TODO' in text:
        print('next: replace every TODO of manual/release/v%s.md, then `python script/relnotes.py --check`' % version)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
