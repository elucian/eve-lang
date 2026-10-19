#!/usr/bin/env python3
"""Golden listings of the bytecode: `eve --disasm test/bytecode/<name>.eve` must give test/bytecode/<name>.lst.

  python script/bctest.py [--eve PATH] [--update]

A change of the emitter shows as a diff of listings; read it, then write the new listings with --update.
"""
import argparse, glob, os, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    ap.add_argument('--update', action='store_true')
    a = ap.parse_args()
    bad = 0
    for src in sorted(glob.glob(os.path.join(ROOT, 'test', 'bytecode', '*.eve'))):
        golden = src[:-4] + '.lst'
        rel = os.path.relpath(src, ROOT).replace(os.sep, '/')
        p = subprocess.run([os.path.abspath(a.eve), '--disasm', rel], cwd=ROOT, capture_output=True, text=True)
        got = p.stdout.replace('\r\n', '\n')
        if a.update:
            open(golden, 'w', encoding='utf-8', newline='\n').write(got)
            print('written ' + os.path.relpath(golden, ROOT))
            continue
        want = open(golden, encoding='utf-8').read() if os.path.exists(golden) else None
        if want == got and p.returncode == 0:
            print('PASS  ' + rel)
        else:
            bad += 1
            print('FAIL  ' + rel + ('' if want is not None else '  (no golden listing: run with --update)'))
    print('bytecode listings: %s' % ('%d differ' % bad if bad else 'all equal'))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
