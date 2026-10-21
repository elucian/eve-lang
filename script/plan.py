#!/usr/bin/env python3
"""Cheap tracking of the plan: read little, find fast.

  python script/plan.py status            open steps, open questions, current focus (about 40 lines)
  python script/plan.py show D-087 [Q-035 ...]   print the full entry of a live decision or question; a settled one prints its line of the index
  python script/plan.py list              every id and title, live and settled
  python script/plan.py feature F-NET-02 [...]   a feature of spec/features: level, status, summary and page
  python script/plan.py features [open|partial|done] [1..7|all]   one line per feature (code, status, name); filter by status and level
  python script/plan.py archive [--keep K]   move settled entries from the live files to design/decision/index.md as one line each (default: keep the last 8)

Decision logs: design/decision/level<N>.md holds a preamble, the open questions and the newest decisions in
full. design/decision/index.md holds one line for each settled decision; the full text of an old one is in
the git history (`git log -S"D-087" -- design/decision`). A new D-/Q- entry is simply appended to the live
file; run `archive` now and then. The features and their status are in spec/features/*.json. Line endings are preserved.
"""
import json, re, sys, glob, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
PLAN = os.path.join(ROOT, 'design')
DEC = os.path.join(PLAN, 'decision')
EXTRA = [os.path.join(os.path.dirname(PLAN), 'code', 'evetx', 'design', 'questions.md')]  # questions kept with a component
HEAD = re.compile(r'^## ((?:D|Q)-\d+)\b(.*)$')
MARK_BEGIN, MARK_END = '<!-- index:begin -->', '<!-- index:end -->'
WITH_INDEX = False  # the active files hold only what is current; `list` prints every id


def read(path):
    raw = open(path, encoding='utf-8', newline='').read()
    return raw.replace('\r\n', '\n'), ('\r\n' if '\r\n' in raw else '\n')


def write(path, text, nl):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8', newline='').write(text.replace('\n', nl))


def split(text):
    """-> (preamble, [(id, title, body)]) ; body includes the heading line."""
    lines = text.split('\n')
    pre, entries, cur = [], [], None
    for ln in lines:
        m = HEAD.match(ln)
        if m:
            cur = [m.group(1), m.group(2).strip(), [ln]]
            entries.append(cur)
        elif cur is None:
            pre.append(ln)
        else:
            cur[2].append(ln)
    return '\n'.join(pre), [(i, t, '\n'.join(b).rstrip('\n') + '\n') for i, t, b in entries]


def strip_index(pre):
    a, b = pre.find(MARK_BEGIN), pre.find(MARK_END)
    return pre if a < 0 else pre[:a].rstrip('\n') + '\n'


def is_open(i, title, body=''):
    t = title.lower()
    if i.startswith('Q'):
        if 'evidence' in t:
            return False
        if 'answered' in t:
            return 'in part' in t
        m = re.search(r'\*\*answer:?\*\*:?[ 	]*(.*)$', body, re.I | re.M)
        return not (m and m.group(1).strip() not in ('', '_(open)_'))
    return 'proposed' in t


def one_line(i, title):
    t = re.sub(r'\s*\(\d{4}-\d\d-\d\d[^)]*\)\s*$', '', title)
    t = re.sub(r'\s*\*\([^)]*\)\*\s*$', '', t)
    return '%s %s' % (i, t[:95])


INDEX = os.path.join(DEC, 'index.md')
LEVEL_NAMES = {'1': 'single script', '2': 'project', '3': 'modules and classes', '4': 'parallel', '5': 'data and database',
               '6': 'server', '7': 'web'}


def live_files():
    return sorted(glob.glob(os.path.join(DEC, 'level*.md')))


def index_lines():
    """-> {level: [line]} of design/decision/index.md."""
    out, cur = {}, None
    if os.path.exists(INDEX):
        for ln in read(INDEX)[0].split('\n'):
            m = re.match(r'## Level (\d)', ln)
            if m:
                cur = m.group(1)
                out[cur] = []
            elif cur and ln.startswith('- '):
                out[cur].append(ln)
    return out


def write_index(lines):
    head = ['# Index of the settled decisions', '',
            'One line per decision (D) or answered question (Q) that left the live files `level1.md` .. `level7.md`. '
            'The full text is in the git history: `git log -S"D-087" -- design/decision`. The live files hold the open '
            'questions and the newest decisions in full; `python script/plan.py archive` moves a settled entry here, keeping its title only.', '']
    for n in sorted(lines):
        head += ['## Level %s: %s' % (n, LEVEL_NAMES[n]), ''] + sorted(lines[n], key=idkey) + ['']
    write(INDEX, '\n'.join(head), '\n')


def idkey(line):
    m = re.match(r'- ([DQ])-(\d+)', line)
    return (int(m.group(2)) * 10 + (m.group(1) == 'Q')) if m else 0


def archive(keep):
    """Move the settled entries of each live file, except the newest `keep`, to the index as one line each."""
    lines = index_lines()
    for n in '1234567':
        active = os.path.join(DEC, 'level%s.md' % n)
        if not os.path.exists(active):
            continue
        text, nl = read(active)
        pre, ents = split(text)
        recent = {id(e) for e in ents[-keep:]} if keep else set()
        moved = [e for e in ents if not is_open(*e) and id(e) not in recent]
        if not moved:
            continue
        have = {l.split()[1] for l in lines.get(n, [])}
        lines.setdefault(n, []).extend('- %s %s' % (e[0], e[1].replace('`', '')[:150]) for e in moved if e[0] not in have)
        keepents = [e for e in ents if e not in moved]
        write(active, pre.rstrip('\n') + '\n\n' + '\n'.join(e[2] for e in keepents), nl)
        print('level %s: %d kept, %d moved to the index' % (n, len(keepents), len(moved)))
    write_index(lines)


def find(id_):
    out = []
    for p in live_files() + EXTRA:
        for i, t, b in split(read(p)[0])[1]:
            if i == id_:
                out.append(b)
    if not out:
        for n, ls in index_lines().items():
            out += [l[2:] + '  (settled, level %s; full text: git log -S"%s" -- design/decision)\n' % (n, id_)
                    for l in ls if l.split()[1] == id_]
    return out


def status():
    foc = read(os.path.join(PLAN, 'README.md'))[0]
    m = re.search(r'## Current focus[^\n]*\n+(.*?)\n\n', foc, re.S)
    if m:
        print('FOCUS:', m.group(1)[:400].replace('\n', ' '))
    print('\nOPEN STEPS ([ ] open, [~] in progress, [!] blocked):')
    for p in sorted(glob.glob(os.path.join(PLAN, 'phase-*.md'))):
        for ln in read(p)[0].split('\n'):
            m = re.match(r'^### (S\d+\.\d+\w*) (.*?)\s*`\[( |~|!)\]`\s*(.*)$', ln)
            if m:
                print('  %s [%s] %s %s' % (m.group(1), m.group(3), m.group(2)[:60], m.group(4)[:70]))
    print('\nOPEN QUESTIONS / PROPOSALS:')
    for p in sorted(glob.glob(os.path.join(DEC, 'level*.md'))) + EXTRA:
        for i, t, b in split(read(p)[0])[1]:
            if is_open(i, t, b):
                print('  ' + one_line(i, t))


def feature_rows():
    """-> [(level, code, name, status, summary, page)] from spec/features/*.json."""
    out = []
    for f in sorted(glob.glob(os.path.join(ROOT, 'spec', 'features', '*.json'))):
        d = json.load(open(f, encoding='utf-8'))
        lv = 'all' if d['level'] is None else str(d['level'])
        out += [(lv, x['id'], x['name'], x['status'], x['summary'], x['doc']) for x in d['features']]
    return out


def features(a):
    want = [x for x in a if x in ('open', 'partial', 'done', 'dropped')]
    ver = [x for x in a if re.fullmatch(r'[1-7]|all', x)]
    for v, c, n, st, d, doc in feature_rows():
        if (not want or st in want) and (not ver or v in ver):
            print('L%-3s %-9s %-8s %s' % (v, c, st[:8], n[:70]))


def feature(codes):
    rows = {r[1]: r for r in feature_rows()}
    for c in codes:
        r = rows.get(c)
        print('%s: not found' % c if not r else 'Level %s  %s  [%s]  %s\n%s\npage: spec/features/%s\n' % (r[0], r[1], r[3], r[2], r[4], r[5]))


def main(a):
    if not a or a[0] in ('-h', '--help'):
        print(__doc__); return
    c = a[0]
    if c == 'status': status()
    elif c == 'list':
        for ls in index_lines().values():
            for l in ls:
                print(l[2:])
        for p in live_files() + EXTRA:
            for i, t, b in split(read(p)[0])[1]:
                print(one_line(i, t))
    elif c == 'features': features(a[1:])
    elif c == 'feature': feature(a[1:])
    elif c == 'show':
        for i in a[1:]:
            r = find(i)
            print(''.join(r) if r else '%s: not found' % i)
    elif c == 'archive':
        archive(int(a[a.index('--keep') + 1]) if '--keep' in a else 8)
    else:
        print(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
