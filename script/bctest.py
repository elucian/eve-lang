#!/usr/bin/env python3
"""The bytecode special tests (test/bytecode, test/readme.md "Bytecode tests"):

  python script/bctest.py [--eve PATH] [--update] [--listings]

1. golden listings: `eve --disasm test/bytecode/<name>.eve` must give test/bytecode/<name>.lst. A change of the emitter shows
   as a diff of listings; read it, then write the new listings with --update. The count of pieces that the emitter still
   leaves to the tree walker (evalx, execx; TD-46) is printed for each test: it should only go down.
2. the programs of the folder run on the bytecode machine and give the output and the exit code of their /*@expect*/ block
   (`python script/runtest.py bytecode`), unless --listings.

Every other test of the repository runs on the tree walker only (`runtest.py all`); the benchmarks run on the bytecode machine.
"""
import argparse, glob, os, re, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def undocumented():
    """Instructions of op.zig that design/components/evecm/doc/instructions.md does not name."""
    src = open(os.path.join(ROOT, 'code', 'evecm', 'src', 'op.zig'), encoding='utf-8').read()
    body = src[src.index('pub const Op = enum(u8) {'):src.index('// @eve-impl one instruction word')]
    ops = re.findall(r'^    ([a-z_]+),$', body, re.M)
    doc = open(os.path.join(ROOT, 'design', 'components', 'evecm', 'doc', 'instructions.md'), encoding='utf-8').read()
    return [o for o in ops if '`' + o + '`' not in doc]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    ap.add_argument('--update', action='store_true')
    ap.add_argument('--listings', action='store_true', help='only the golden listings, do not run the programs')
    ap.add_argument('--no-update', action='store_true', help='do not update the tracking file of the bytecode tests (CI)')
    a = ap.parse_args()
    bad = 0
    miss = undocumented()
    if miss:
        bad += 1
        print('FAIL  design/components/evecm/doc/instructions.md does not name: ' + ', '.join(miss))
    for src in sorted(glob.glob(os.path.join(ROOT, 'test', 'bytecode', '*.eve'))):
        golden = src[:-4] + '.lst'
        if '(no listing)' in open(src, encoding='utf-8').read(400):
            continue          # `eve --disasm` refuses the script (a class, TD-46): only the run is tested
        rel = os.path.relpath(src, ROOT).replace(os.sep, '/')
        p = subprocess.run([os.path.abspath(a.eve), '--disasm', rel], cwd=ROOT, capture_output=True, text=True)
        got = p.stdout.replace('\r\n', '\n')
        if a.update:
            open(golden, 'w', encoding='utf-8', newline='\n').write(got)
            print('written ' + os.path.relpath(golden, ROOT))
            continue
        want = open(golden, encoding='utf-8').read() if os.path.exists(golden) else None
        if want == got and p.returncode == 0:
            print('PASS  %s  (%d piece(s) on the tree walker)' % (rel, len(re.findall(r'[ ](?:evalx|execx)[ ]', got))))
        else:
            bad += 1
            print('FAIL  ' + rel + ('' if want is not None else '  (no golden listing: run with --update)'))
    print('bytecode listings: %s' % ('%d differ' % bad if bad else 'all equal'))
    if not a.update and not a.listings:
        run = subprocess.run([sys.executable, os.path.join(ROOT, 'script', 'runtest.py'), 'bytecode', '--eve', os.path.abspath(a.eve), '-q'] + (['--no-update'] if a.no_update else []), cwd=ROOT)
        bad += run.returncode != 0
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
