#!/usr/bin/env python3
"""Delete the `// Zig tip:` teaching comments from Zig sources (plan step A3, D-190, TD-8).

  python script/strip_zigtips.py [--apply] [--show N] <dir-or-file> ...

A tip block is a line `// Zig tip...` (any indent) plus the `//` lines that follow it at the same
indent, up to the first line that is blank, code, a `///` or `//!` doc line, or an `// @tag` line.
Every `@` tag, `///` and `//!` line is kept. A decision (D-nnn), spec path or feature id that a deleted tip names becomes a tag (`// @decision D-169`) unless the neighbouring lines already carry it. A double blank line left by a deletion is collapsed.
Without --apply it only counts (per file, and --show N prints the first N blocks).
Skips .zig-cache, zig-pkg, zig-out. LF files stay LF, CRLF stay CRLF.
"""
import os, re, sys

TIP = re.compile(r'^(\s*)// Zig tip')
CONT = re.compile(r'^(\s*)//(?![/!])(?!\s*@(eve-fn|eve-impl|eve-module|spec|feature|decision|tests?|perf|invariant|see)\b)')


def refs(text):
    """The links to the design that a tip names, as tag values: decisions, spec pages, features."""
    tags = []
    for d in re.findall(r'(?<![A-Za-z])D-\d+', text):
        tags.append('@decision ' + d)
    for sp in re.findall(r'(?<![A-Za-z])spec/[A-Za-z0-9_./-]+(?:#[A-Za-z0-9_-]+)?', text):
        tags.append('@spec ' + sp.rstrip('.,;:)'))
    for fe in re.findall(r'(?<![A-Za-z])F-[A-Z]+-\d+', text):
        tags.append('@feature ' + fe)
    seen = []
    for t in tags:
        if t not in seen:
            seen.append(t)
    return seen


def strip(lines):
    out, i, removed, blocks = [], 0, 0, []
    while i < len(lines):
        m = TIP.match(lines[i])
        if not m:
            out.append(lines[i]); i += 1; continue
        ind, j = m.group(1), i + 1
        while j < len(lines):
            c = CONT.match(lines[j]) or TIP.match(lines[j])
            if c and c.group(1) == ind:
                j += 1
            else:
                break
        blocks.append(lines[i:j]); removed += j - i
        near = ' '.join(x.strip() for x in lines[max(0, i - 4):i] + lines[j:j + 8])
        for t in refs(' '.join(lines[i:j])):
            if t not in near:
                out.append(ind + '// ' + t); removed -= 1
        i = j
        if out and out[-1].strip() == '' and i < len(lines) and lines[i].strip() == '':
            i += 1
    return out, removed, blocks


def walk(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p; continue
        for r, d, fs in os.walk(p):
            d[:] = [x for x in d if x not in ('.zig-cache', 'zig-pkg', 'zig-out')]
            for f in fs:
                if f.endswith('.zig'):
                    yield os.path.join(r, f)


def main(a):
    apply = '--apply' in a
    show = int(a[a.index('--show') + 1]) if '--show' in a else 0
    paths = [x for i, x in enumerate(a) if not x.startswith('--') and not (i and a[i - 1] == '--show')]
    tot = nf = 0
    for f in walk(paths):
        raw = open(f, 'rb').read().decode('utf8')
        nl = '\r\n' if '\r\n' in raw else '\n'
        lines = raw.split(nl)
        out, n, blocks = strip(lines)
        if not n:
            continue
        tot += n; nf += 1
        print('%5d  %s' % (n, f.replace(os.sep, '/')))
        for b in blocks[:show]:
            print('\n'.join('      | ' + x for x in b))
        if apply:
            open(f, 'wb').write(nl.join(out).encode('utf8'))
    print('%s %d lines in %d files' % ('removed' if apply else 'would remove', tot, nf))


if __name__ == '__main__':
    main(sys.argv[1:])
