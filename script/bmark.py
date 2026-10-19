#!/usr/bin/env python3
"""Performance watch of the Eve VM: one small benchmark per level in test/bmark/.

  python script/bmark.py [--runs N] [--save] [--check] [--eve PATH] [--level N] [--build Debug|ReleaseSafe]

Every file test/bmark/p<level><letter>_<name>.eve is run N times (default 5) with `eve -x`; the
output must match its /*@expect*/ block, otherwise the benchmark is wrong, not slow. The report
shows the median and the best time of each benchmark and the change against the last saved run.
  --save    append this run to test/bmark/history.json (do it for every version and optimization)
  Every benchmark has a twin in Python (test/bmark/ref/<name>.py): the run also reports its time and the ratio Eve / Python.
  --check   exit 1 when a benchmark is more than 25% slower than the last saved run
Every run also reports the size of eve, evevm, evecp, evetx, eveux and evedb (those found beside eve.exe) and the change of eve.exe its change against the last saved run of the same build; --save records it in history.json and in the size table of the README.
Times depend on the machine: compare runs made on the same machine. Notes per version: test/bmark/README.md.
Level 6 needs the database server: when a p6 benchmark is selected, bmark starts evedb (evedb.exe beside eve.exe) with
test/bmark/evedb.cfg, in test/bmark/, and stops it at the end; the Python twins of level 6 need psycopg2.
"""
import argparse, contextlib, glob, json, os, re, statistics, subprocess, sys, time, datetime, platform

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
PERF = os.path.join(ROOT, 'test', 'bmark')
HIST = os.path.join(PERF, 'history.json')


def expected(path):
    text = open(path, encoding='utf-8').read()
    m = re.search(r'/\*@expect(.*?)\*/', text, re.S)
    if not m:
        return None
    out = json.loads(m.group(1)).get('stdout')
    return '\n'.join(out) if isinstance(out, list) else out


class Done:
    """The result of a finished process, like subprocess.run gives, plus its peak memory in MB."""
    def __init__(self, code, out, err, peak):
        self.returncode, self.stdout, self.stderr, self.peak_mb = code, out, err, peak


def peak_memory(proc):
    """Peak memory of a finished child in MB: the peak working set on Windows, max RSS of children elsewhere."""
    try:
        if os.name == 'nt':
            import ctypes
            from ctypes import wintypes

            class PMC(ctypes.Structure):
                _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD)] + [
                    (n, ctypes.c_size_t) for n in ('PeakWorkingSetSize', 'WorkingSetSize', 'QuotaPeakPagedPoolUsage',
                                                   'QuotaPagedPoolUsage', 'QuotaPeakNonPagedPoolUsage', 'QuotaNonPagedPoolUsage',
                                                   'PagefileUsage', 'PeakPagefileUsage')]
            c = PMC()
            c.cb = ctypes.sizeof(c)
            psapi = ctypes.WinDLL('psapi')
            psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(PMC), wintypes.DWORD]
            if psapi.GetProcessMemoryInfo(wintypes.HANDLE(int(proc._handle)), ctypes.byref(c), c.cb):
                return round(c.PeakWorkingSetSize / 1048576, 1)
            return None
        import resource
        kb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        return round(kb / 1024, 1)
    except Exception:
        return None


def run_once(eve, path, bc=False):
    t = time.perf_counter()
    env = dict(os.environ)
    if bc:
        env['EVE_ENGINE'] = 'bc'
    else:
        env.pop('EVE_ENGINE', None)
    # the folder of the benchmarks is the working folder: its eve.cfg names the database of the level 5 benchmarks
    p = subprocess.Popen([eve, '-x', path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=PERF, env=env)
    out, err = p.communicate()
    ms = (time.perf_counter() - t) * 1000
    return ms, Done(p.returncode, out, err, peak_memory(p))


EVEDB_NATIVE = 55462  # control_port of test/bmark/evedb.cfg


@contextlib.contextmanager
def evedb_server(eve, needed):
    """Run evedb (beside eve) with test/bmark/evedb.cfg while the level 6 benchmarks and their twins run."""
    if not needed:
        yield
        return
    exe = os.path.join(os.path.dirname(eve), 'evedb.exe' if os.name == 'nt' else 'evedb')
    if not os.path.exists(exe):
        sys.exit('level 6 needs %s: build it in drivers/duckdb/ with zig build -p ../..' % exe)
    srv = subprocess.Popen([exe, 'serve', '--config', 'evedb.cfg'], cwd=PERF, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for _ in range(2):  # evedb prints one ready line per port
        line = srv.stdout.readline()
        if not line:
            sys.exit('evedb did not start (is a port of test/bmark/evedb.cfg taken?)')
    try:
        yield
    finally:
        subprocess.run([exe, 'stop', '--connect', '127.0.0.1:%d' % EVEDB_NATIVE], capture_output=True)
        try:
            srv.wait(timeout=10)
        except subprocess.TimeoutExpired:
            srv.kill()


README = os.path.join(PERF, 'README.md')
PLANNED = {2: 'import of a module, `apply` of an aspect, a call through an extension method',
           3: 'read and parse a CSV and a JSON file, decimal arithmetic, optional values',
           4: 'a parallel group of aspects, a channel with 100,000 messages, a stream',
           5: 'insert and select 10,000 rows in the Eve database',
           6: 'evedb: column batches, bulk load, records over PostgreSQL, OLAP group-by',
           7: 'render an HTML template 1,000 times'}


def describe(path):
    m = re.search(r'\*\* perf: (.*)', open(path, encoding='utf-8').read())
    return m.group(1).strip() if m else ''


def put_block(name, rows):
    """Replace the lines between <!-- name:begin --> and <!-- name:end --> in the README."""
    text = open(README, encoding='utf-8', newline='').read()
    b, e = '<!-- %s:begin -->' % name, '<!-- %s:end -->' % name
    if b not in text:
        return
    nl = '\r\n' if '\r\n' in text else '\n'
    i, j = text.index(b) + len(b), text.index(e)
    open(README, 'w', encoding='utf-8', newline='').write(text[:i] + nl + nl.join(rows) + nl + text[j:])


def update_readme(hist):
    """Rewrite the generated tables of the README: what each benchmark measures, the latest ReleaseSafe results, the totals per run."""
    rel = [h for h in hist if h.get('build') == 'ReleaseSafe']
    last = rel[-1]['results'] if rel else {}
    py = rel[-1].get('python', {}) if rel else {}
    files = sorted(glob.glob(os.path.join(PERF, 'p[0-9]*.eve')))
    what = ['| Benchmark | What it measures |', '|---|---|']
    res = ['| Benchmark | Eve | BCode | Python | EVE/PT | Mem |', '|---|---|---|---|---|---|']
    for lvl in range(1, 8):
        what.append('| **Level %d** | |' % lvl)
        res.append('| **Level %d** | | | | | |' % lvl)
        mine = [f for f in files if os.path.basename(f).startswith('p%d' % lvl)]
        for f in mine:
            n = os.path.basename(f)[:-4]
            what.append('| `%s` | %s |' % (n, describe(f)))
            if n in last:
                r = last[n]
                res.append('| `%s` | %.0f ms | %s | %s | %s | %s |' % (n, r['median_ms'], ('%.0f ms' % r['bc_ms']) if 'bc_ms' in r else '-',
                           ('%.0f ms' % py[n]) if n in py else '-', ('%.1fx' % (r['median_ms'] / py[n])) if n in py else '-',
                           ('%.1f MB' % r['peak_mb']) if 'peak_mb' in r else '-'))
            else:
                res.append('| `%s` | not measured | - | - | - | - |' % n)
        if not mine:
            what.append('| planned | %s |' % PLANNED[lvl])
            res.append('| planned | | | | | |')
    put_block('bench', what)
    put_block('results', res)
    shown = hist[-SHOWN:]
    levels = [l for l in range(1, 8) if any(n[1] == str(l) for h in shown for n in h['results'])]
    runs = ['| Version | Date | ' + ' | '.join('Level %d' % l for l in levels) + ' |', '|---|---|' + '---|' * len(levels)]
    for h in shown:
        cells = []
        for lvl in levels:
            t = [r['median_ms'] for n, r in h['results'].items() if n[1] == str(lvl)]
            cells.append('%.0f ms' % sum(t) if t else '-')
        runs.append('| %s | %s | %s |' % (h['version'], h['date'][:10], ' | '.join(cells)))
    put_block('runs', runs)


def run_reference(name, runs):
    """Median time in ms of the same benchmark written in Python (test/bmark/ref/<name>.py), or None."""
    path = os.path.join(PERF, 'ref', name + '.py')
    if not os.path.exists(path):
        return None
    times = []
    for _ in range(runs):
        t = time.perf_counter()
        r = subprocess.run([sys.executable, path], capture_output=True, text=True, cwd=ROOT)
        if r.returncode != 0:
            return None
        times.append((time.perf_counter() - t) * 1000)
    return round(statistics.median(times), 1)


def git_short():
    try:
        return subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    except OSError:
        return ''


SHOWN = 2      # runs shown in the README tables (size, totals per run)
VERSIONS = 5   # versions kept in history.json


def prune(hist):
    """Keep the last VERSIONS versions; of an older version only its last run of each build, of the newest version its last two."""
    order = []
    for h in hist:
        if h['version'] not in order:
            order.append(h['version'])
    keep = order[-VERSIONS:]
    out, count = [], {}
    for h in reversed(hist):
        v = h['version']
        if v not in keep:
            continue
        k = (v, h.get('build', 'Debug'))
        count[k] = count.get(k, 0) + 1
        if count[k] <= (2 if v == keep[-1] else 1):
            out.append(h)
    return out[::-1]


PROGRAMS = ['eve', 'evevm', 'evecp', 'evetx', 'eveux', 'evedb']


def program_sizes(eve):
    """Size in bytes of each program of the build, found beside eve.exe (a missing one is left out)."""
    d = os.path.dirname(eve)
    out = {}
    for p in PROGRAMS:
        f = os.path.join(d, p + os.path.splitext(eve)[1])
        if os.path.exists(f):
            out[p] = os.path.getsize(f)
    return out


def update_size_table(hist):
    """Rewrite the table between the size markers of the README: one column per saved run, one row per program."""
    runs, prev = [], {}
    for h in hist:
        sz = dict(h.get('sizes', {}))
        if 'exe_bytes' in h:
            sz.setdefault('eve', h['exe_bytes'])
        if not sz:
            continue
        b = h.get('build', 'Debug')
        old = prev.get(b)
        change = '%+.1f%%' % ((sz['eve'] - old) / old * 100) if old and 'eve' in sz else '-'
        if 'eve' in sz:
            prev[b] = sz['eve']
        runs.append((h, sz, change))
    runs = runs[-SHOWN:]
    rows = ['| Version | ' + ' | '.join(h['version'] for h, _, _ in runs) + ' |', '|---|' + '---|' * len(runs),
            '| Date | ' + ' | '.join(h['date'][:10] for h, _, _ in runs) + ' |',
            '| Build | ' + ' | '.join(h.get('build', 'Debug') for h, _, _ in runs) + ' |',
            '| Commit | ' + ' | '.join(h.get('commit', '-') for h, _, _ in runs) + ' |']
    for p in PROGRAMS:
        rows.append('| %s | ' % p + ' | '.join(('%s KB' % format(round(sz[p] / 1024), ',')) if p in sz else '-' for _, sz, _ in runs) + ' |')
    rows.append('| eve change | ' + ' | '.join(c for _, _, c in runs) + ' |')
    put_block('size', rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--runs', type=int, default=5)
    ap.add_argument('--save', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    ap.add_argument('--level', type=int)
    ap.add_argument('--engine', choices=['tree', 'bc'], default='tree', help='the engine of the VM (design/design-bytecode.md); a bc run alone can not be saved')
    ap.add_argument('--both', action='store_true', help='run every benchmark on the tree walker and on the bytecode machine: the BCode column, and the two outputs must be equal')
    ap.add_argument('--build', default='Debug', help='how the VM was built: Debug (zig build -p . at the root) or ReleaseSafe; runs are compared with the same build')
    a = ap.parse_args()
    a.eve = os.path.abspath(a.eve)
    if a.engine == 'bc':
        if a.save:
            sys.exit('bmark: a bytecode run alone is not saved: use --both')
        os.environ['EVE_ENGINE'] = 'bc'
    ver = subprocess.run([a.eve, '--version'], capture_output=True, text=True).stdout.strip().split()[-1]
    files = sorted(glob.glob(os.path.join(PERF, 'p[0-9]*.eve')))
    if a.level:
        files = [f for f in files if os.path.basename(f).startswith('p%d' % a.level)]
    hist = json.load(open(HIST, encoding='utf-8')) if os.path.exists(HIST) else []
    same = [h for h in hist if h.get('build', 'Debug') == a.build]
    last = same[-1]['results'] if same else {}
    results, bad = {}, []
    server = evedb_server(a.eve, any(os.path.basename(f).startswith('p6') for f in files))
    server.__enter__()
    for f in files:
        name = os.path.basename(f)[:-4]
        want = expected(f)
        times, peaks = [], []
        for _ in range(a.runs):
            ms, r = run_once(a.eve, f)
            if r.peak_mb:
                peaks.append(r.peak_mb)
            if r.returncode != 0 or (want is not None and r.stdout.strip().replace('\r', '') != want.strip()):
                print('%s: WRONG OUTPUT (exit %d): %s' % (name, r.returncode, (r.stdout + r.stderr).strip()[:120]))
                bad.append(name)
                break
            times.append(ms)
        if times:
            results[name] = {'median_ms': round(statistics.median(times), 1), 'min_ms': round(min(times), 1)}
            if peaks:
                results[name]['peak_mb'] = max(peaks)
        if a.both and times and name not in bad:
            # the bytecode machine: the same output, and its time
            bc_times, tree_out = [], r.stdout.strip().replace('\r', '')
            for _ in range(a.runs):
                ms, r2 = run_once(a.eve, f, bc=True)
                same_out = r2.stdout.strip().replace('\r', '') == tree_out
                if r2.returncode != 0 or not same_out or (want is not None and r2.stdout.strip().replace('\r', '') != want.strip()):
                    print('%s: THE ENGINES DIFFER (bytecode exit %d): %s' % (name, r2.returncode, (r2.stdout + r2.stderr).strip()[:120]))
                    bad.append(name)
                    break
                bc_times.append(ms)
            if bc_times:
                results[name]['bc_ms'] = round(statistics.median(bc_times), 1)
                results[name]['bc_min_ms'] = round(min(bc_times), 1)
    print('Eve %s (%s build), %d runs each, %s' % (ver, a.build, a.runs, platform.platform()))
    exe_bytes = os.path.getsize(a.eve)
    old_exe = next((h['exe_bytes'] for h in reversed(same) if 'exe_bytes' in h), None)
    print('size of eve.exe: %s bytes (%.0f KB)%s' % (format(exe_bytes, ','), exe_bytes / 1024,
          (', %+.1f%% against the last saved run' % ((exe_bytes - old_exe) / old_exe * 100)) if old_exe else ', no earlier size saved'))
    print('sizes: ' + ', '.join('%s %s KB' % (k, format(round(v / 1024), ',')) for k, v in program_sizes(a.eve).items()))
    refs = {n: run_reference(n, a.runs) for n in results}
    server.__exit__(None, None, None)
    print('%-22s %9s %9s %9s %7s %9s %9s %7s %8s' % ('benchmark', 'median ms', 'best ms', 'bcode ms', 'bc/tree', 'vs last', 'python ms', 'eve/py', 'peak MB'))
    slow = []
    for name, r in results.items():
        prev = last.get(name)
        delta = ''
        if prev:
            pct = (r['median_ms'] - prev['median_ms']) / prev['median_ms'] * 100
            delta = '%+.0f%%' % pct
            if pct > 25:
                slow.append(name)
        py = refs.get(name)
        print('%-22s %9.1f %9.1f %9s %7s %9s %9s %7s %8s' % (name, r['median_ms'], r['min_ms'], '%.1f' % r['bc_ms'] if 'bc_ms' in r else '-',
                                                    '%.2fx' % (r['median_ms'] / r['bc_ms']) if r.get('bc_ms') else '-', delta, '%.1f' % py if py else '-',
                                                    '%.1fx' % (r['median_ms'] / py) if py else '-', r.get('peak_mb', '-')))
    for lvl in sorted({n[1] for n in results}):
        tot = sum(r['median_ms'] for n, r in results.items() if n[1] == lvl)
        ptot = sum(last[n]['median_ms'] for n in results if n[1] == lvl and n in last)
        bct = sum(r['bc_ms'] for n, r in results.items() if n[1] == lvl and 'bc_ms' in r)
        print('level %s total %.1f ms%s%s' % (lvl, tot, (' (%+.0f%% against the last run)' % ((tot - ptot) / ptot * 100)) if ptot else '',
              ', bytecode %.1f ms' % bct if bct else ''))
    if a.save and not bad:
        hist.append({'date': datetime.datetime.now().strftime('%Y-%m-%d %H:%M'), 'version': ver, 'build': a.build, 'commit': git_short(), 'exe_bytes': exe_bytes, 'sizes': program_sizes(a.eve),
                     'machine': platform.processor() or platform.machine(), 'runs': a.runs, 'results': results, 'python': {n: v for n, v in refs.items() if v}})
        hist = prune(hist)
        json.dump(hist, open(HIST, 'w', encoding='utf-8', newline='\n'), indent=1)
        update_readme(hist)
        update_size_table(hist)
        print('saved to test/bmark/history.json, table of the README updated')
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import genpages
            for p in genpages.generate():
                print('genpages: ' + os.path.relpath(p, ROOT).replace(os.sep, '/'))
        except Exception as e:
            print('genpages: not updated (%s)' % e)
    if bad or (a.check and slow):
        if slow:
            print('SLOWER than the last run by more than 25%:', ', '.join(slow))
        sys.exit(1)


if __name__ == '__main__':
    main()
