#!/usr/bin/env python3
"""Performance watch of the Eve VM: one small benchmark per level in test/perf/.

  python script/perf.py [--runs N] [--save] [--check] [--eve PATH] [--level N] [--build Debug|ReleaseSafe]

Every file test/perf/p<level><letter>_<name>.eve is run N times (default 5) with `eve -x`; the
output must match its /*@expect*/ block, otherwise the benchmark is wrong, not slow. The report
shows the median and the best time of each benchmark and the change against the last saved run.
  --save    append this run to test/perf/history.json (do it for every version and optimization)
  --check   exit 1 when a benchmark is more than 25% slower than the last saved run
Times depend on the machine: compare runs made on the same machine. Notes per version: test/perf/README.md.
"""
import argparse, glob, json, os, re, statistics, subprocess, sys, time, datetime, platform

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
PERF = os.path.join(ROOT, 'test', 'perf')
HIST = os.path.join(PERF, 'history.json')


def expected(path):
    text = open(path, encoding='utf-8').read()
    m = re.search(r'/\*@expect(.*?)\*/', text, re.S)
    if not m:
        return None
    out = json.loads(m.group(1)).get('stdout')
    return '\n'.join(out) if isinstance(out, list) else out


def run_once(eve, path):
    t = time.perf_counter()
    r = subprocess.run([eve, '-x', path], capture_output=True, text=True, cwd=ROOT)
    return (time.perf_counter() - t) * 1000, r


def git_short():
    try:
        return subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    except OSError:
        return ''


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--runs', type=int, default=5)
    ap.add_argument('--save', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    ap.add_argument('--level', type=int)
    ap.add_argument('--build', default='Debug', help='how the VM was built: Debug (zig build -p ..) or ReleaseSafe; runs are compared with the same build')
    a = ap.parse_args()
    a.eve = os.path.abspath(a.eve)
    ver = subprocess.run([a.eve, '--version'], capture_output=True, text=True).stdout.strip().split()[-1]
    files = sorted(glob.glob(os.path.join(PERF, 'p[0-9]*.eve')))
    if a.level:
        files = [f for f in files if os.path.basename(f).startswith('p%d' % a.level)]
    hist = json.load(open(HIST, encoding='utf-8')) if os.path.exists(HIST) else []
    same = [h for h in hist if h.get('build', 'Debug') == a.build]
    last = same[-1]['results'] if same else {}
    results, bad = {}, []
    for f in files:
        name = os.path.basename(f)[:-4]
        want = expected(f)
        times = []
        for _ in range(a.runs):
            ms, r = run_once(a.eve, f)
            if r.returncode != 0 or (want is not None and r.stdout.strip().replace('\r', '') != want.strip()):
                print('%s: WRONG OUTPUT (exit %d): %s' % (name, r.returncode, (r.stdout + r.stderr).strip()[:120]))
                bad.append(name)
                break
            times.append(ms)
        if times:
            results[name] = {'median_ms': round(statistics.median(times), 1), 'min_ms': round(min(times), 1)}
    print('Eve %s (%s build), %d runs each, %s' % (ver, a.build, a.runs, platform.platform()))
    print('%-22s %9s %9s %9s' % ('benchmark', 'median ms', 'best ms', 'vs last'))
    slow = []
    for name, r in results.items():
        prev = last.get(name)
        delta = ''
        if prev:
            pct = (r['median_ms'] - prev['median_ms']) / prev['median_ms'] * 100
            delta = '%+.0f%%' % pct
            if pct > 25:
                slow.append(name)
        print('%-22s %9.1f %9.1f %9s' % (name, r['median_ms'], r['min_ms'], delta))
    for lvl in sorted({n[1] for n in results}):
        tot = sum(r['median_ms'] for n, r in results.items() if n[1] == lvl)
        ptot = sum(last[n]['median_ms'] for n in results if n[1] == lvl and n in last)
        print('level %s total %.1f ms%s' % (lvl, tot, (' (%+.0f%%)' % ((tot - ptot) / ptot * 100)) if ptot else ''))
    if a.save and not bad:
        hist.append({'date': datetime.datetime.now().strftime('%Y-%m-%d %H:%M'), 'version': ver, 'build': a.build, 'commit': git_short(),
                     'machine': platform.processor() or platform.machine(), 'runs': a.runs, 'results': results})
        json.dump(hist, open(HIST, 'w', encoding='utf-8', newline='\n'), indent=1)
        print('saved to test/perf/history.json')
    if bad or (a.check and slow):
        if slow:
            print('SLOWER than the last run by more than 25%:', ', '.join(slow))
        sys.exit(1)


if __name__ == '__main__':
    main()
