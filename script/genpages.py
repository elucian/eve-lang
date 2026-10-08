#!/usr/bin/env python3
"""Generate the three test pages of the tutorial from the tests of the repository (D-136).

  python script/genpages.py [--check]

  tutorial/features.html     the feature tests (the conformity tests) of every level: description and a link to each file
  tutorial/quality.html      the smoke tests, and the benchmarks with the history of the runs, one table per level

Only the part between <!-- GEN:BEGIN --> and <!-- GEN:END --> of a page is written; the text around it
is edited by hand. The sidebar of each page is data/<page>.json. A page that does not exist is made
from the shell of examples.html. `runtest.py` and `bmark.py` call this script after every run that
updates their files, so the pages follow the tests: add a test, change its first comment line (its
description) or save a benchmark run, and the pages change. The tutorial is a junction to the scl
repository: commit the pages there (`git -C tutorial ...`).
  --check   write nothing, exit 1 when a page is out of date
"""
import glob
import html
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
TEST = os.path.join(ROOT, 'test')
TUT = os.path.join(ROOT, 'tutorial')
RAW = 'https://raw.githubusercontent.com/elucian/eve-lang/master/'
TREE = 'https://github.com/elucian/eve-lang/tree/master/'
VIEW = '/roadmap/code-viewer.html?file=' + RAW
BEGIN = '<!-- GEN:BEGIN (written by script/genpages.py, do not edit) -->'
END = '<!-- GEN:END -->'
VARIATION = re.compile(r'^([a-z]\d+)_test\d+\.eve$')


def esc(text):
    """HTML text; a `word` between backticks becomes <code>word</code>."""
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', html.escape(text, quote=False))


def title_of(path):
    """The description of a test: its first comment line (# title), or the first ** note. The same rule as runtest.py."""
    note = ''
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            if line.startswith('#') and not line.startswith('#!'):
                return line.lstrip('#').strip()
            if line.startswith('**') and not note:
                note = line.lstrip('*').strip()
            if line.strip() and not line.startswith(('#', '/*', '*')):
                break
    return note


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, '/')


def level_names():
    """{1: 'the language of a single script', ...} from the table of plan/version_map.md."""
    names, versions = {}, {}
    with open(os.path.join(ROOT, 'plan', 'version_map.md'), encoding='utf-8') as f:
        for line in f:
            m = re.match(r'\|\s*(?:Level\s*)?(\d)\s*\|\s*([^|]+?)\s*\|\s*(?:Version\s*)?([0-9.]+)\s*\|', line)
            if m:
                names[int(m.group(1))] = re.sub(r'\s*\([^)]*D-\d+[^)]*\)', '', m.group(2))
                versions[int(m.group(1))] = m.group(3)
    return names, versions


def tests_of(folder):
    """The test files of a level folder: flat files, project drivers and their variations."""
    found = []
    for f in sorted(os.listdir(folder)):
        path = os.path.join(folder, f)
        if f.endswith('.eve') and os.path.isfile(path):
            found.append(path)
        elif os.path.isfile(os.path.join(path, f + '.eve')):
            found.append(os.path.join(path, f + '.eve'))
            for g in sorted(os.listdir(path)):
                m = VARIATION.match(g)
                if m and m.group(1) == f.split('_')[0] and os.path.isfile(os.path.join(path, g)):
                    found.append(os.path.join(path, g))
    return found


def code_of(path):
    name = os.path.basename(path)[:-4]
    head = name.split('_')[0]
    return head if re.fullmatch(r'[a-z]\d+', head) else '-'


def link(path, text=None):
    return '<a href="%s%s">%s</a>' % (VIEW, rel(path), text or os.path.basename(path))


def table(head, rows):
    out = ['<table class="table table-bordered table-striped">', '<thead><tr>' + ''.join('<th>%s</th>' % h for h in head) + '</tr></thead>', '<tbody>']
    out += ['<tr>' + ''.join('<td>%s</td>' % c for c in r) + '</tr>' for r in rows]
    out += ['</tbody>', '</table>']
    return '\n'.join(out)


def test_rows(folder, with_code=True):
    rows = []
    for path in tests_of(folder):
        name = os.path.basename(path)[:-4]
        kind = ' <span class="text-secondary small">(variation)</span>' if VARIATION.match(os.path.basename(path)) else ''
        cells = ['<code>%s</code>%s' % (name, kind), esc(title_of(path)), link(path)]
        if with_code:
            cells.insert(0, code_of(path))
        rows.append(cells)
    return rows


# ------------------------------------------------------------------------------------------ pages
# One or two words for the title of a level; the full description is the paragraph under it (plan/version_map.md).
LEVEL_TITLES = {1: 'Scripts', 2: 'Subprograms', 3: 'Modules', 4: 'Parallel', 5: 'Data', 6: 'Server', 7: 'Web'}


def gen_tests():
    names, versions = level_names()
    out, side = [], []
    total = 0
    for n in range(1, 8):
        folder = os.path.join(TEST, 'level%d' % n)
        tests = tests_of(folder) if os.path.isdir(folder) else []
        total += len(tests)
        sid = 'level-%d' % n
        title = 'Level %d: %s' % (n, LEVEL_TITLES.get(n, ''))
        side.append((title, sid))
        out.append('<h2 id="%s">%s</h2>' % (sid, esc(title)))
        topic = names.get(n, '')
        topic = topic[:1].upper() + topic[1:]
        count = '%d tests' % len(tests) if tests else 'no tests yet'
        out.append('<p>%s. Version %s, %s. <a href="%stest/level%d" target="_blank" rel="noopener noreferrer nofollow">The folder on GitHub</a>.</p>' % (esc(topic), versions.get(n, ''), count, TREE, n))
        if tests:
            out.append(table(['Code', 'Test', 'What it checks', 'Source'], test_rows(folder)))
        out.append('')
    return '\n'.join(out), side, total


def gen_quality():
    """One page, two parts: the smoke test (h2), the performance (h2) and its history (h2, one h3 per level)."""
    out, side = [], []
    # ---- the smoke test
    rows = test_rows(os.path.join(TEST, 'smoke'))
    out.append('<h2 id="smoke">Smoke Test</h2>')
    out.append('<p>The quick check that the machine and the language are sane: %d scripts, one feature each, in less than a second. Run it with <code>python script/runtest.py smoke</code>.</p>' % len(rows))
    out.append(table(['Code', 'Test', 'What it checks', 'Source'], rows))
    out.append('')
    side.append(('Smoke Test', 'smoke', []))
    # ---- the performance
    hist = json.load(open(os.path.join(TEST, 'bmark', 'history.json'), encoding='utf-8'))

    def last(build):
        runs = [h for h in hist if h.get('build') == build]
        return runs[-1] if runs else None

    rel_run, dbg_run = last('ReleaseSafe'), last('Debug')
    files = sorted(glob.glob(os.path.join(TEST, 'bmark', 'p[0-9]*.eve')))
    rows = []
    for path in files:
        name = os.path.basename(path)[:-4]
        with open(path, encoding='utf-8') as f:
            m = re.search(r'\*\* perf: (.*)', f.read())
        what = m.group(1).strip() if m else ''
        r = rel_run['results'].get(name) if rel_run else None
        d = dbg_run['results'].get(name) if dbg_run else None
        py = rel_run.get('python', {}).get(name) if rel_run else None
        rows.append([name[1], '<code>%s</code>' % name, esc(what),
                     '%.0f ms' % r['median_ms'] if r else '-', '%.0f ms' % py if py else '-',
                     '%.1fx' % (r['median_ms'] / py) if r and py else '-',
                     '%.0f ms' % d['median_ms'] if d else '-', link(path, 'source')])
    out.append('<h2 id="performance">Performance</h2>')
    out.append('<p>A small benchmark for each level, with a twin in Python. Median of %s runs of the last saved ReleaseSafe measure (%s), the Python twin and the Debug build. Run them with <code>python script/bmark.py</code>; add <code>--save</code> to record a run.</p>' % (rel_run['runs'] if rel_run else '-', rel_run['date'] if rel_run else '-'))
    out.append(table(['Level', 'Benchmark', 'What it measures', 'Eve', 'Python', 'Eve / Python', 'Debug', 'Source'], rows))
    out.append('')
    side.append(('Performance', 'performance', []))
    # ---- the history: one table for each level
    out.append('<h2 id="history">History</h2>')
    out.append('<p>The total of the median times of the benchmarks of the level, for every saved run, newest first. One table for each level; compare only runs of the same build on the same machine.</p>')
    kids = []
    levels = sorted({os.path.basename(f)[1] for f in files})
    for lv in levels:
        names = [os.path.basename(f)[:-4] for f in files if os.path.basename(f)[1] == lv]
        hrows = []
        for h in reversed(hist):
            times = [h['results'].get(n) for n in names]
            if not any(times):
                continue
            total = sum(t['median_ms'] for t in times if t)
            hrows.append([h['date'], h['build'], h['version'], h.get('commit', ''), '%.0f ms' % total])
        out.append('<h3 id="history-level-%s">Level %s</h3>' % (lv, lv))
        out.append(table(['Date', 'Build', 'Version', 'Commit', 'Total'], hrows))
        out.append('')
        kids.append(('Level %s' % lv, 'history-level-%s' % lv, []))
    side.append(('History', 'history', kids))
    return '\n'.join(out), side, len(rows)


PAGES = {
    'features': ('Eve Feature Tests', 'Eve Feature Tests', gen_tests,
              'The feature tests of Eve (the conformity tests), by level. Every test is a script (or a project folder) with its expected output in a comment block at the end: a driver passes when the machine prints exactly that and ends with the expected exit code. Each row shows what the test checks, taken from the first comment line of the file, and a link to the file in the code viewer. The tests are the specification that an implementation must pass: <code>python script/runtest.py all</code> runs them, and <a href="/projects/eve/quality.html">Smoke Test and Performance</a> have their own page.'),
    'quality': ('Eve Smoke Test and Performance', 'Eve Smoke Test & Performance', gen_quality,
                'The checks of the machine that are not feature tests. The <b>smoke test</b> is the quick check that the machine and the language are sane: each script is a driver with small functions and very simple <code>expect</code> lines, <code>True</code> is <code>True</code>, <code>0 == 0</code>. It does not depend on the feature tests, and it shows that the program compiles, parses and has no contradiction. The <b>performance</b> benchmarks check that the machine stays fast while features are added: each has a twin in Python, and the history of the runs shows every change.'),
}


def shell(title, h1, intro, page):
    """A new page made from the shell of examples.html."""
    src = open(os.path.join(TUT, 'examples.html'), encoding='utf-8', newline='').read().replace('\r\n', '\n')
    head = src[:src.index('<h1 id=')]
    head = re.sub(r'<title>.*?</title>', '<title>%s</title>' % html.escape(title), head)
    tail = src[src.index('<!-- Footer -->'):]
    return '%s<h1 id="%s">%s</h1>\n\n<div class="alert alert-secondary shadow-sm">%s</div>\n\n%s\n%s\n%s\n\n%s' % (head, page, html.escape(h1), intro, BEGIN, '', END, tail)


def write_if_changed(path, text, check):
    old = open(path, encoding='utf-8', newline='').read() if os.path.isfile(path) else None
    nl = '\r\n' if old and '\r\n' in old else '\n'
    new = text.replace('\r\n', '\n').replace('\n', nl)
    if old == new:
        return False
    if not check:
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(new)
    return True


def tree(items):
    """The sidebar entries: (title, id, children) tuples, as many levels as there are (h1, h2, h3)."""
    out = []
    for it in items:
        t, i = it[0], it[1]
        node = {'title': t, 'link': '#' + i}
        if len(it) > 2 and it[2]:
            node['children'] = tree(it[2])
        out.append(node)
    return out


def generate(check=False):
    """Write the pages. Returns the list of the files that changed (or would change)."""
    if not os.path.isfile(os.path.join(TUT, 'examples.html')):
        return []
    changed = []
    for page, (title, h1, fn, intro) in PAGES.items():
        body, side, count = fn()
        path = os.path.join(TUT, page + '.html')
        if os.path.isfile(path):
            text = open(path, encoding='utf-8', newline='').read().replace('\r\n', '\n')
        else:
            text = shell(title, h1, intro, page)
        a, b = text.index(BEGIN), text.index(END) + len(END)
        text = text[:a] + BEGIN + '\n' + body + '\n' + END + text[b:]
        if write_if_changed(path, text, check):
            changed.append(path)
        data = [{'title': html.unescape(h1), 'link': '#' + page, 'children': tree(side)}]
        if write_if_changed(os.path.join(TUT, 'data', page + '.json'), json.dumps(data, indent=2, ensure_ascii=False) + '\n', check):
            changed.append(os.path.join(TUT, 'data', page + '.json'))
    return changed


def main():
    check = '--check' in sys.argv
    changed = generate(check)
    for p in changed:
        print(('out of date: ' if check else 'written: ') + rel(p))
    if check and changed:
        sys.exit(1)


if __name__ == '__main__':
    main()
