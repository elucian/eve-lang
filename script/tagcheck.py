#!/usr/bin/env python3
"""Check the AI tags of the Zig sources (plan step A4, D-190, design/design-ai-context.md).

  python script/tagcheck.py [files or folders]     default: code/ and drivers/
  python script/tagcheck.py --untagged             also list the files without any tag
  python script/tagcheck.py --staged               only the Zig files staged in git (for the pre-commit hook)

Reports, one line each:
  bad-spec     `@spec path#anchor` whose file does not exist, or whose anchor is no heading of that file
  bad-feature  `@feature F-XXX-nn` that is not a row of design/version_map.md
  bad-decision `@decision D-nnn` that is in no decision file (live or archive)
  no-head      a file whose first lines have no `//! @eve-module`
The exit code is 1 when a bad-* line is printed; no-head and --untagged are information.
Anchors follow GitHub: lower case, spaces to `-`, punctuation dropped.
"""
import os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SKIP = {'.zig-cache', 'zig-pkg', 'zig-out', 'temp', '.git'}
TAG = re.compile(r'//[/!]?\s*@(spec|feature|decision)\s+(.*)$')
ANY = re.compile(r'@(spec|feature|eve-module|eve-fn|eve-impl)\b')


def slug(h):
    h = re.sub(r'`', '', h.strip().lower())
    h = re.sub(r'[^\w\s-]', '', h, flags=re.U)
    return re.sub(r'\s', '-', h)


_anchors = {}


def anchors(path):
    if path not in _anchors:
        full = os.path.join(ROOT, path)
        out = None
        if os.path.isfile(full):
            out = set()
            for ln in open(full, encoding='utf8', errors='ignore'):
                m = re.match(r'#{1,6}\s+(.*)', ln)
                if m:
                    out.add(slug(m.group(1)))
                for a in re.findall(r'<a (?:name|id)="([^"]+)"', ln):
                    out.add(a)
        _anchors[path] = out
    return _anchors[path]


def known_features():
    s = set()
    for ln in open(os.path.join(ROOT, 'design', 'version_map.md'), encoding='utf8'):
        m = re.match(r'\|\s*(F-[A-Z]+-\d+)\s*\|', ln)
        if m:
            s.add(m.group(1))
    return s


def known_decisions():
    s = set()
    for r, d, fs in os.walk(os.path.join(ROOT, 'design', 'decision')):
        for f in fs:
            if f.endswith('.md'):
                for ln in open(os.path.join(r, f), encoding='utf8', errors='ignore'):
                    m = re.match(r'## ((?:D|Q)-\d+)\b', ln)
                    if m:
                        s.add(m.group(1))
    return s


def files(args):
    if '--staged' in args:
        out = subprocess.check_output(['git', 'diff', '--cached', '--name-only', '--diff-filter=AM'], cwd=ROOT, text=True)
        for f in out.split():
            if f.endswith('.zig') and not f.endswith('nfc_data.zig'):
                yield os.path.join(ROOT, f)
        return
    paths = [x for x in args if not x.startswith('--')] or [os.path.join(ROOT, 'code'), os.path.join(ROOT, 'drivers')]
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for r, d, fs in os.walk(p):
            d[:] = [x for x in d if x not in SKIP]
            for f in fs:
                if f.endswith('.zig') and f != 'nfc_data.zig':
                    yield os.path.join(r, f)


def main(a):
    feats, decs = known_features(), known_decisions()
    bad = nohead = untagged = 0
    for f in files(a):
        rel = os.path.relpath(f, ROOT).replace(os.sep, '/')
        text = open(f, encoding='utf8', errors='ignore').read()
        lines = text.split('\n')
        for n, ln in enumerate(lines, 1):
            for kind, vals in TAG.findall(ln):
              for val in re.findall(r'[A-Za-z0-9_./#-]+[A-Za-z0-9_/#]', vals.split(' (')[0].split(': ')[0]):
                if kind == 'spec':
                    path, _, anc = val.partition('#')
                    an = anchors(path)
                    if an is None:
                        print('%s:%d bad-spec %s (no such file)' % (rel, n, val)); bad += 1
                    elif anc and anc not in an:
                        print('%s:%d bad-spec %s (no such anchor)' % (rel, n, val)); bad += 1
                elif kind == 'feature' and val not in feats:
                    print('%s:%d bad-feature %s' % (rel, n, val)); bad += 1
                elif kind == 'decision' and val not in decs:
                    print('%s:%d bad-decision %s' % (rel, n, val)); bad += 1
        if not any('@eve-module' in x for x in lines[:12]):
            nohead += 1
            if '--untagged' in a and not ANY.search(text):
                untagged += 1
                print('%s: untagged' % rel)
    print('tagcheck: %d bad tags, %d files without a module head, %d without any tag' % (bad, nohead, untagged))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
