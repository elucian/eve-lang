#!/usr/bin/env python3
"""Cheap tracking of the plan: read little, find fast.

  python script/plan.py status            open steps, open questions, current focus (about 60 lines)
  python script/plan.py show D-087 [Q-035 ...]   print the full entry (active file or archive)
  python script/plan.py list              every id and title, active and archived (the files hold no index)
  python script/plan.py archive [N] [--keep K]   move settled entries to plan/archive/ (default: keep the last 8)

Decision logs: plan/decision_level<N>.md holds a preamble, an index of EVERY id (one line each),
the open questions and the newest decisions in full. plan/archive/decision_level<N>.md holds the
full text of the settled ones. A new D-/Q- entry is simply appended to the active file; run
`archive` now and then. `show` finds an id in either place. Line endings are preserved.
"""
import re, sys, glob, os

PLAN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'plan')
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


def paths(n):
    return (os.path.join(PLAN, 'decision_level%s.md' % n),
            os.path.join(PLAN, 'archive', 'decision_level%s.md' % n))


def rebuild(n, keep=None):
    active, arch = paths(n)
    text, nl = read(active)
    pre, ents = split(text)
    pre = strip_index(pre)
    old_arch = split(read(arch)[0])[1] if os.path.exists(arch) else []
    if keep is not None:
        recent = {id(e) for e in ents[-keep:]} if keep else set()
        moved = [e for e in ents if not is_open(*e) and id(e) not in recent]
        ents = [e for e in ents if e not in moved] if moved else ents
        if moved:
            arch_text = '# Archive of decision_level%s.md: settled entries, full text\n\n' % n
            write(arch, arch_text + '\n'.join(e[2] for e in old_arch + moved), '\r\n' if os.name == 'nt' and False else nl)
            old_arch += moved
    idx = [] if not WITH_INDEX else [MARK_BEGIN, '## Index (every id; full text: `python script/plan.py show ID`)', '']
    where = {id(e): 'A' for e in ents}
    allents = sorted(old_arch + ents, key=lambda e: int(e[0][2:]) * 10 + (e[0][0] == 'Q'))
    for e in allents:
        mark = '*' if (e in ents and is_open(*e)) else ('' if e in ents else '~')
        idx.append('- %s%s' % (one_line(e[0], e[1]), ' [open]' if mark == '*' else ''))
    idx += [MARK_END, ''] if WITH_INDEX else []
    body = pre.rstrip('\n') + '\n\n' + '\n'.join(idx) + '\n' + '\n'.join(e[2] for e in ents)
    write(active, body, nl)
    print('level %s: %d active, %d archived' % (n, len(ents), len(old_arch)))


def find(id_):
    out = []
    for p in sorted(glob.glob(os.path.join(PLAN, 'decision_level*.md')) + glob.glob(os.path.join(PLAN, 'archive', '*.md'))):
        for i, t, b in split(read(p)[0])[1]:
            if i == id_:
                out.append(b)
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
    for p in sorted(glob.glob(os.path.join(PLAN, 'decision_level*.md'))):
        for i, t, b in split(read(p)[0])[1]:
            if is_open(i, t, b):
                print('  ' + one_line(i, t))


def main(a):
    if not a or a[0] in ('-h', '--help'):
        print(__doc__); return
    c = a[0]
    if c == 'status': status()
    elif c == 'list':
        for p in sorted(glob.glob(os.path.join(PLAN, 'decision_level*.md')) + glob.glob(os.path.join(PLAN, 'archive', '*.md'))):
            for i, t, b in split(read(p)[0])[1]:
                print(one_line(i, t))
    elif c == 'show':
        for i in a[1:]:
            r = find(i)
            print(''.join(r) if r else '%s: not found' % i)
    elif c in ('index', 'archive'):
        keep = None
        if c == 'archive':
            keep = int(a[a.index('--keep') + 1]) if '--keep' in a else 8
        rest = [x for i, x in enumerate(a[1:], 1) if x.isdigit() and a[i - 1] != '--keep']
        ns = rest or ['1', '2']
        for n in ns:
            rebuild(n, keep)
    else:
        print(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
