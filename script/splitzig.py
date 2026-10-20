#!/usr/bin/env python3
"""Split the methods of one big Zig struct into files (design-ai-context.md step A6).

Zig has no partial structs, so a group of methods becomes free functions in a new file whose first
parameter is `*App`, and the struct keeps `pub const name = mod.name;` aliases: `self.name(...)` and
`App.name(...)` still work, and so does every caller outside the file. The code before the struct
(types, menus, small helpers) moves whole into one `types` file that the struct file re-exports.

usage: python script/splitzig.py <plan.py> [--apply]
The plan file defines SRC, STRUCT, TYPES (path), CHUNKS = [(path, first_line, last_line, head_lines)],
TYPES_RANGE = (first, last), IMPORT_PREFIX (file-level imports copied to each new file).
Without --apply it only prints what it would do. Line numbers are 1-based and inclusive.
"""
import re, sys, os, subprocess

BS = chr(92)
DECL = re.compile(r'^    (pub )?(fn|const|var) (\w+)')
TOP = re.compile(r'^(pub )?(fn|const|var) (\w+)')


def load_plan(path):
    ns = {}
    exec(open(path, encoding='utf-8').read(), ns)
    return ns


def dedent(lines):
    return [l[4:] if l.startswith('    ') else l for l in lines]


def pubify(lines):
    out = []
    for l in lines:
        m = TOP.match(l)
        if m and not m.group(1):
            l = 'pub ' + l
        out.append(l)
    return out


def names_of(lines, regex):
    return [m.group(3) for l in lines for m in [regex.match(l)] if m]


def used(names, body):
    return [n for n in names if re.search(r'(?<![\w.@])' + re.escape(n) + r'\b', body)]


def main():
    plan = load_plan(sys.argv[1])
    apply = '--apply' in sys.argv
    src = open(plan['SRC'], encoding='utf-8').read().split('\n')
    L = lambda a, b: src[a - 1:b]
    # a chunk starts at its first doc comment or tag line, not between the comment and the function
    fixed = []
    for (rel, a, b, head) in plan['CHUNKS']:
        while a > 2 and re.match(r'    (///|// @)', src[a - 2]):
            a -= 1
        fixed.append([rel, a, b, head])
    for k in range(len(fixed) - 1):
        fixed[k][2] = fixed[k + 1][1] - 1 if fixed[k + 1][1] <= fixed[k][2] else fixed[k][2]
    plan['CHUNKS'] = [tuple(c) for c in fixed]
    root = os.path.dirname(plan['SRC'])
    st_first = next(i for i, l in enumerate(src, 1) if l.replace('pub ', '', 1).startswith('const %s = struct {' % plan['STRUCT']))
    tr0, tr1 = plan['TYPES_RANGE']

    # the types file: everything between the imports and the struct, made public
    types_lines = pubify(L(tr0, tr1))
    type_names = names_of(types_lines, TOP)
    types_rel = plan['TYPES']
    types_mod = os.path.splitext(os.path.basename(types_rel))[0]

    prefix = plan['IMPORT_PREFIX']
    prefix_names = [m.group(3) for l in prefix for m in [TOP.match(l)] if m]
    sub_prefix = [re.sub(r'@import\("(\w+\.zig)"\)', lambda m: '@import("../' + m.group(1) + '")', l) for l in prefix]

    # every decl of the struct, wherever it goes: a bare use of one inside a moved method becomes `App.name`
    st_last = next(i for i in range(st_first, len(src)) if src[i].startswith('};'))
    struct_decls = set(names_of(src[st_first:st_last], DECL))

    def code_spans(l):
        # the parts of a line that are code: not a string, a character literal or a comment
        if l.lstrip().startswith(('//', BS * 2)):
            return []
        spans, i, start, n = [], 0, 0, len(l)
        while i < n:
            c = l[i]
            if c == '/' and l[i:i + 2] == '//':
                break
            if c == '"' or c == chr(39):
                spans.append((start, i))
                j = i + 1
                while j < n and l[j] != c:
                    j += 2 if l[j] == BS else 1
                i = start = j + 1
                continue
            i += 1
        else:
            spans.append((start, n))
            return spans
        spans.append((start, i))
        return spans

    def qualify(lines):
        pat = re.compile(r'(?<![\w.@])(' + '|'.join(sorted(map(re.escape, struct_decls), key=len, reverse=True)) + r')\b(?!\s*:)')
        out = []
        for l in lines:
            res, last = [], 0
            for (x, y) in code_spans(l):
                res.append(l[last:x])
                seg = l[x:y]

                def sub(m, seg=seg):
                    pre = seg[:m.start()].rstrip()
                    if pre.endswith(('fn', 'const', 'var')):
                        return m.group(0)
                    return plan['STRUCT'] + '.' + m.group(1)
                res.append(pat.sub(sub, seg))
                last = y
            res.append(l[last:])
            out.append(''.join(res))
        return out

    files = {}  # path -> text
    aliases = {}  # chunk first line -> alias lines
    struct_name = plan['STRUCT']
    for (rel, a, b, head) in plan['CHUNKS']:
        body_src = L(a, b)
        decls = names_of(body_src, DECL)
        body = pubify(qualify(dedent(body_src)))
        while body and body[-1].strip() == '':
            body.pop()
        text = '\n'.join(body)
        mod = os.path.splitext(os.path.basename(rel))[0]
        imports = list(sub_prefix)
        imports.append('const %s = @import("../%s.zig").%s;' % (struct_name, os.path.splitext(os.path.basename(plan['SRC']))[0], struct_name))
        tn = used(type_names, text)
        if tn:
            imports.append('const %s = @import("%s.zig");' % (types_mod, types_mod))
            imports += ['const %s = %s.%s;' % (n, types_mod, n) for n in tn]
        # file-level names the struct file keeps (imports) are copied through IMPORT_PREFIX; drop the unused ones
        keep = []
        probe = text
        changed = True
        while changed:
            changed = False
            for l in imports:
                m = TOP.match(l)
                nm = m.group(3) if m else None
                if l in keep:
                    continue
                if nm is None or nm in ('ide', 'vaxis') or nm == struct_name or nm == types_mod or re.search(r'(?<![\w.@])' + re.escape(nm) + r'\b', probe):
                    keep.append(l)
                    probe += chr(10) + l.split('=', 1)[-1]
                    changed = True
        keep = [l for l in imports if l in keep]
        out = '\n'.join(head) + '\n' + '\n'.join(keep) + '\n\n' + text + '\n'
        files[os.path.join(root, rel)] = out
        al = []
        for n in decls:
            al.append('    pub const %s = %s_m.%s;' % (n, mod, n))
        aliases[a] = (b, al, mod, rel)

    # the struct file: imports, re-exports of the types, the struct with aliases in place of the chunks
    new = []
    i = 1
    chunk_starts = aliases
    new_imports = []
    while i <= len(src):
        if i == tr0:
            for n in type_names:
                new.append('pub const %s = %s.%s;' % (n, types_mod, n))
            i = tr1 + 1
            continue
        if i in chunk_starts:
            b, al, mod, rel = chunk_starts[i]
            new.append('    // ------------------------------------------------------------ %s' % rel)
            new += al
            i = b + 1
            continue
        new.append(src[i - 1])
        i += 1
    # imports of the new modules go right after the last file-level import
    idx = max(k for k, l in enumerate(new) if l.startswith('const ') and '@import' in l and k < 40)
    mods = ['const %s_m = @import("%s");' % (m, r) for (_, (_, _, m, r)) in sorted(aliases.items())]
    mods.insert(0, 'const %s = @import("%s");' % (types_mod, plan['TYPES']))
    new[idx + 1:idx + 1] = mods

    types_text = '\n'.join(plan['TYPES_HEAD']) + '\n' + '\n'.join(sub_prefix) + '\n\n' + '\n'.join(types_lines) + '\n'
    files[os.path.join(root, types_rel)] = types_text
    files[plan['SRC']] = '\n'.join(new)
    for p, t in files.items():
        print('%-60s %6d lines' % (p, t.count('\n')))
        if apply:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'w', encoding='utf-8', newline='\n') as f:
                f.write(t)
    if apply:
        subprocess.run(['zig', 'fmt'] + list(files), check=False)


main()
