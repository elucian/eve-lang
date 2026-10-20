#!/usr/bin/env python3
"""Size of what an AI session reads (plan step A5, design/design-ai-context.md).

  python script/ctxsize.py            print the table
  python script/ctxsize.py --check    exit 1 when a hard limit is passed (CLAUDE.md, Zig tips, live decision files)
  python script/ctxsize.py --files    also list the Zig files without any @spec/@feature/@eve-module tag

Bytes divided by 4 is a fair guess of tokens. Skips .zig-cache, zig-pkg, zig-out, temp, nfc_data.zig.
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SKIP = {'.zig-cache', 'zig-pkg', 'zig-out', 'temp', '.git', 'node_modules'}
LIMITS = {'CLAUDE.md': 8000, 'zig_tips': 0, 'decision_file': 40000}  # decision_file: 25000 after A2b
WARN = {'zig_file_lines': 2000, 'feature_map_features_bytes': 12000}
TAG = re.compile(r'@(spec|feature|eve-module|eve-fn|eve-impl)\b')


def size(*p):
    return os.path.getsize(os.path.join(ROOT, *p))


def zig_files():
    for r, d, fs in os.walk(os.path.join(ROOT, 'code')):
        d[:] = [x for x in d if x not in SKIP]
        for f in fs:
            if f.endswith('.zig') and f != 'nfc_data.zig':
                yield os.path.join(r, f)
    for r, d, fs in os.walk(os.path.join(ROOT, 'drivers')):
        d[:] = [x for x in d if x not in SKIP]
        for f in fs:
            if f.endswith('.zig'):
                yield os.path.join(r, f)


def main(a):
    rows, bad = [], []

    def row(name, value, limit=None, unit='bytes', warn=False):
        flag = ''
        if limit is not None and value > limit:
            flag = 'WARN' if warn else 'OVER'
            if not warn:
                bad.append(name)
        rows.append((name, '%d %s' % (value, unit), ('limit %d' % limit) if limit is not None else '', flag))

    row('CLAUDE.md', size('CLAUDE.md'), LIMITS['CLAUDE.md'])
    tips = tag_files = untagged = 0
    big, no_tag = [], []
    for f in zig_files():
        text = open(f, encoding='utf8', errors='ignore').read()
        lines = text.split('\n')
        tips += sum(1 for x in lines if '// Zig tip' in x)
        big.append((len(lines), os.path.relpath(f, ROOT).replace(os.sep, '/')))
        if TAG.search(text):
            tag_files += 1
        else:
            untagged += 1
            no_tag.append(os.path.relpath(f, ROOT).replace(os.sep, '/'))
    row('Zig tip lines', tips, LIMITS['zig_tips'], 'lines')
    dd = os.path.join(ROOT, 'design', 'decision')
    for f in sorted(os.listdir(dd)):
        if f.endswith('.md'):
            row('decision/' + f, size('design', 'decision', f), LIMITS['decision_file'])
    row('design/feature_map.md (read by plan.py features)', size('design', 'feature_map.md'))
    big.sort(reverse=True)
    for n, f in big[:3]:
        row(f, n, WARN['zig_file_lines'], 'lines', warn=True)
    rows.append(('Zig files with a tag / without', '%d / %d' % (tag_files, untagged), '', ''))
    w = max(len(r[0]) for r in rows)
    for r in rows:
        print('%-*s  %-16s %-12s %s' % (w, *r))
    if '--files' in a:
        print('\nwithout @spec, @feature or @eve-module:')
        print('\n'.join('  ' + x for x in no_tag))
    if '--check' in a and bad:
        print('over the limit:', ', '.join(bad))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
