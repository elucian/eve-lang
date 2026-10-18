"""Benchmark of the data paths between eve and its databases (evedb/README.md section 5.5, D-187, phase 2).

It answers three questions with numbers instead of guesses:
  1. transfer: how fast do rows reach an Eve script? evedb:// column batches into a Memory table, the same into records
     (row frames), PostgreSQL protocol into records, and a local SQLite file into a Memory table;
  2. OLAP: how fast is one group-by over the whole table in DuckDB (evedb) and in SQLite?
  3. bulk load: how fast does a Memory table go into a new table of evedb (the Appender) and of SQLite?

Each operation is one run of `eve -x` (median of --repeat runs); the time of a run that only connects is subtracted, so the
numbers are the operation itself. Rows of the record paths are fewer (records are objects), and rows per second are reported.

usage: python script/evedb_bench.py [--rows 1000000] [--record-rows 100000] [--repeat 3] [--eve bin/eve.exe] [--evedb bin/evedb.exe]
needs: the build of bin/ (eve and evedb). Runs in temp/evedb_bench/.
"""
import argparse
import os
import shutil
import sqlite3
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'temp', 'evedb_bench')
PG, CTRL = 55471, 55472


def script(name, body):
    path = os.path.join(WORK, name + '.eve')
    with open(path, 'w') as f:
        f.write('primary aspect %s is\n' % name)
        f.write('  class Big = {id: Integer, region: String, amount: Real, paid: Logic} <: Memory;\n')
        f.write('  class Row = {id: Integer, region: String, amount: Real, paid: Logic} <: Record;\n')
        f.write('  class Agg = {region: String, total: Real, n: Integer} <: Record;\n')
        f.write('  process main is\n')
        for line in body.strip().split('\n'):
            f.write('    ' + line + '\n')
        f.write('  return;\nend %s;\n' % name)
    return name + '.eve'


def run(eve, file, repeat):
    times, out = [], ''
    for _ in range(repeat):
        t0 = time.perf_counter()
        r = subprocess.run([eve, '-x', file], cwd=WORK, capture_output=True, text=True)
        times.append(time.perf_counter() - t0)
        if r.returncode != 0:
            raise SystemExit('%s failed: %s %s' % (file, r.stdout, r.stderr))
        out = r.stdout.strip()
    return statistics.median(times), out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rows', type=int, default=1_000_000)
    ap.add_argument('--record-rows', type=int, default=100_000)
    ap.add_argument('--repeat', type=int, default=3)
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    ap.add_argument('--evedb', default=os.path.join(ROOT, 'bin', 'evedb.exe'))
    a = ap.parse_args()
    eve, evedb = os.path.abspath(a.eve), os.path.abspath(a.evedb)
    N, R = a.rows, a.record_rows
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    with open(os.path.join(WORK, 'evedb.cfg'), 'w') as f:
        f.write('port = %d\ncontrol_port = %d\ntest = true\ndatabase "wh" = "data/wh.duckdb"\n' % (PG, CTRL))
    with open(os.path.join(WORK, 'eve.cfg'), 'w') as f:
        f.write('database "wh" = "evedb://127.0.0.1:%d/wh"\n' % CTRL)
        f.write('database "pg" = "postgres://eve@127.0.0.1:%d/wh"\n' % PG)
        f.write('database "lite" = "sqlite://data/lite.db"\n')
    os.makedirs(os.path.join(WORK, 'data'))
    # the same table in SQLite, made by Python
    lite = sqlite3.connect(os.path.join(WORK, 'data', 'lite.db'))
    lite.execute('create table big (id integer primary key, region text, amount real, paid integer)')
    regions = ['north', 'south', 'east', 'west']
    lite.executemany('insert into big values (?, ?, ?, ?)', ((i, regions[i % 4], i * 1.5, i % 2) for i in range(N)))
    lite.commit()
    lite.close()

    srv = subprocess.Popen([evedb, 'serve', '--config', 'evedb.cfg'], cwd=WORK, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    srv.stdout.readline()
    srv.stdout.readline()
    results = []
    try:
        prep = script('prep', '''
new wh := database.connect("wh");
wh.execute!("drop table if exists big");
wh.execute!("create table big as select i::bigint as id, ['north','south','east','west'][(i % 4)::integer + 1] as region, i * 1.5::double as amount, i % 2 = 1 as paid from range({N}) t(i)");
print "ready";'''.replace('{N}', str(N)))
        run(eve, prep, 1)
        base_ev, _ = run(eve, script('base_ev', 'new wh := database.connect("wh");\nprint "x";'), a.repeat)
        base_pg, _ = run(eve, script('base_pg', 'new pg := database.connect("pg");\nprint "x";'), a.repeat)
        base_lite, _ = run(eve, script('base_lite', 'new lite := database.connect("lite");\nprint "x";'), a.repeat)

        def bench(label, name, body, rows, base):
            t, out = run(eve, script(name, body), a.repeat)
            op = max(t - base, 1e-6)
            results.append((label, rows, op, rows / op, out.splitlines()[-1] if out else ''))

        sel = 'select id, region, amount, paid from big'
        bench('transfer: evedb:// column batches -> Memory', 'tr_ev_mem', 'new wh := database.connect("wh");\nnew b := Big();\nprint b.store(wh, "%s");' % sel, N, base_ev)
        bench('transfer: SQLite file -> Memory', 'tr_lite_mem', 'new lite := database.connect("lite");\nnew b := Big();\nprint b.store(lite, "%s");' % sel, N, base_lite)
        bench('transfer: evedb:// row frames -> records', 'tr_ev_rec', 'new wh := database.connect("wh");\nprint wh.query!(:Row)("%s where id < %d").count();' % (sel, R), R, base_ev)
        bench('transfer: PostgreSQL protocol -> records', 'tr_pg_rec', 'new pg := database.connect("pg");\nprint pg.query!(:Row)("%s where id < %d").count();' % (sel, R), R, base_pg)
        bench('transfer: SQLite file -> records', 'tr_lite_rec', 'new lite := database.connect("lite");\nprint lite.query!(:Row)("%s where id < %d").count();' % (sel, R), R, base_lite)
        agg = 'select region, sum(amount) as total, count(*) as n from big group by region order by region'
        bench('OLAP group-by: DuckDB (evedb)', 'olap_ev', 'new wh := database.connect("wh");\nprint wh.query!(:Agg)("%s").count();' % agg, N, base_ev)
        bench('OLAP group-by: SQLite', 'olap_lite', 'new lite := database.connect("lite");\nprint lite.query!(:Agg)("%s").count();' % agg, N, base_lite)
        # bulk load: store first (measured above), then load; the store time is subtracted
        t_store_ev = [r for r in results if r[0].startswith('transfer: evedb:// column')][0][2]
        bench('bulk load: Memory -> evedb (Appender)', 'load_ev', 'new wh := database.connect("wh");\nwh.execute!("drop table if exists big2");\nnew b := Big();\nb.store(wh, "%s");\nprint b.load(wh, "big2");' % sel, N, base_ev + t_store_ev)
        t_store_lite = [r for r in results if r[0].startswith('transfer: SQLite file -> Memory')][0][2]
        bench('bulk load: Memory -> SQLite', 'load_lite', 'new lite := database.connect("lite");\nlite.execute!("drop table if exists big2");\nnew b := Big();\nb.store(lite, "%s");\nprint b.load(lite, "big2");' % sel, N, base_lite + t_store_lite)
    finally:
        subprocess.run([evedb, 'stop', '--connect', '127.0.0.1:%d' % CTRL], capture_output=True)
        try:
            srv.wait(timeout=10)
        except subprocess.TimeoutExpired:
            srv.kill()

    print('\nrows: %d (records: %d), median of %d runs, connect time subtracted\n' % (N, R, a.repeat))
    print('| Operation | Rows | Seconds | Rows per second |')
    print('|---|---|---|---|')
    for label, rows, sec, rps, _ in results:
        print('| %s | %d | %.3f | %s |' % (label, rows, sec, '{:,.0f}'.format(rps)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
