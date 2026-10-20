#!/usr/bin/env python3
"""Split a Zig file of free functions into files by concern (design-ai-context.md step A6).

Companion of splitzig.py (that one splits the methods of a struct). Here every top-level declaration
stays a free function or constant: a chunk of the source moves to a new file, all moved and kept
declarations become `pub`, and each file gets `const name = other_m.name;` for the names it uses from
another file. Callers of the original file keep working: the original re-exports nothing, so only
files that imported the original need `pub const` lines, listed in REEXPORT (a name, or `*` for all
public names that moved).

usage: python script/splitfree.py <plan.py> [--apply]
The plan defines SRC, MODDIR (folder of the new files, relative to the folder of SRC),
CHUNKS = [(name, first_line, last_line, head_lines)], IMPORT_LINES = (first, last) of the file-level
imports, REEXPORT. Line numbers are 1-based and inclusive; a chunk starts at its first doc comment.
"""
import re, sys, os, subprocess

NL = chr(10)
TOP = re.compile(r'^(pub )?(fn|const|var) (\w+)')
BARE = lambda n: re.compile(r'(?<![\w.@"])' + re.escape(n) + r'\b(?!\s*:)')


def main():
    plan = {}
    exec(open(sys.argv[1], encoding='utf-8').read(), plan)
    apply = '--apply' in sys.argv
    src_path = plan['SRC']
    src = open(src_path, encoding='utf-8').read().split('\n')
    root = os.path.dirname(src_path)
    stem = os.path.splitext(os.path.basename(src_path))[0]
    i0, i1 = plan['IMPORT_LINES']
    imports = src[i0 - 1:i1]
    sub_imports = [l.replace('@import("', '@import("../') if '@import("' in l and not l.split('@import("')[1].startswith(('std', 'builtin', 'vaxis', 'ide', 'help_', 'eve_zon')) else l for l in imports]

    chunks = []
    for (name, a, b, head) in plan['CHUNKS']:
        while a > 2 and re.match(r'(///|// @)', src[a - 2]):
            a -= 1
        chunks.append([name, a, b, head])
    for k in range(len(chunks) - 1):
        if chunks[k + 1][1] <= chunks[k][2]:
            chunks[k][2] = chunks[k + 1][1] - 1

    owner = {}  # top-level name -> module name (stem for the core)
    for i, l in enumerate(src, 1):
        m = TOP.match(l)
        if not m:
            continue
        mod = stem
        for (name, a, b, _) in chunks:
            if a <= i <= b:
                mod = name
        owner[m.group(3)] = mod
    import_names = {m.group(3) for l in imports for m in [TOP.match(l)] if m}

    def pub(lines):
        return [('pub ' + l) if (TOP.match(l) and not l.startswith('pub ')) else l for l in lines]

    def aliases(body, mod):
        used = []
        for n, o in owner.items():
            if o != mod and n not in import_names and BARE(n).search(body):
                used.append('const %s = %s_m.%s;' % (n, o, n))
        return used

    def keep_imports(body):
        # an import stays when the body uses it, or when a kept import is built from it (fixpoint)
        text = body
        kept = set()
        changed = True
        while changed:
            changed = False
            for l in sub_imports:
                m = TOP.match(l)
                if m and l not in kept and BARE(m.group(3)).search(text):
                    kept.add(l)
                    text += NL + l.split('=', 1)[1]
                    changed = True
        return [l for l in sub_imports if l in kept]

    files = {}
    taken = set()
    groups = {}
    for (name, a, b, head) in chunks:
        groups.setdefault(name, []).append((a, b, head))
    for name, parts in groups.items():
        lines = []
        for (a, b, head) in parts:
            part = src[a - 1:b]
            while part and part[-1].strip() == '':
                part.pop()
            lines += part + ['']
            taken.update(range(a, b + 1))
        head = parts[0][2]
        body = NL.join(pub(lines)).rstrip(NL)
        mods = sorted({owner[n] for n in owner if owner[n] != name and BARE(n).search(body) and n not in import_names})
        mod_imports = ['const %s_m = @import("%s");' % (m, ('../%s.zig' % stem) if m == stem else ('%s.zig' % m)) for m in mods]
        out = NL.join(head) + NL + NL.join(keep_imports(body)) + NL + NL.join(mod_imports) + NL + NL.join(aliases(body, name)) + NL + NL + body + NL
        files[os.path.join(root, plan['MODDIR'], name + '.zig')] = out

    core = [l for i, l in enumerate(src, 1) if i not in taken]
    core_body = '\n'.join(pub(core))
    mods = sorted({o for n, o in owner.items() if o != stem and BARE(n).search(core_body) and n not in import_names})
    mod_imports = ['const %s_m = @import("%s/%s.zig");' % (m, plan['MODDIR'], m) for m in mods]
    core_aliases = aliases(core_body, stem)
    # the core file: the imports stay where they are; the module imports and aliases follow them
    k = i1 - sum(1 for t in taken if t < i1)
    core_lines = core_body.split('\n')
    core_lines[k:k] = mod_imports + core_aliases
    reexp = plan.get('REEXPORT', [])
    if reexp:
        core_lines += ['', '// the names that other files take from here'] + ['pub const %s = %s_m.%s;' % (n, owner[n], n) for n in sorted(owner) if owner[n] != stem and (reexp == ['*'] or n in reexp)]
    files[src_path] = '\n'.join(core_lines)
    for p, t in files.items():
        print('%-60s %6d lines' % (p, t.count('\n')))
        if apply:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'w', encoding='utf-8', newline='\n') as f:
                f.write(t)
    if apply:
        subprocess.run(['zig', 'fmt'] + list(files), check=False)


main()
