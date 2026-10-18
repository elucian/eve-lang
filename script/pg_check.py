"""Tests of the PostgreSQL face of evedb and of the Eve driver for PostgreSQL (evedb/README.md, sections 5A and 5B).

The checks use two independent client libraries of PostgreSQL: psycopg2 (libpq, the C library of PostgreSQL itself, simple query
protocol) and pg8000 (pure Python, extended protocol). Then an Eve script with `postgres://` in its eve.cfg talks to the same
server, and the two start forms of `eve` are tried: `eve db serve evedb.cfg` and `eve -s -db --serve evedb.cfg`.

usage: python script/pg_check.py [--evedb bin/evedb.exe] [--eve bin/eve.exe]
needs: pip install psycopg2-binary pg8000

Runs in `temp/pg_check/`. Exit status 0 when all the checks pass.
"""
import argparse
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'temp', 'pg_check')
failures = []


def check(ok, what):
    print(('ok   ' if ok else 'FAIL ') + what)
    if not ok:
        failures.append(what)


class Server:
    """evedb started with a configuration file; the ports are read from its first lines."""

    def __init__(self, exe, cfg_text, name='evedb.cfg'):
        self.cfg = os.path.join(WORK, name)
        with open(self.cfg, 'w') as f:
            f.write(cfg_text)
        self.p = subprocess.Popen([exe, 'serve', '--config', self.cfg], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=WORK)
        self.pg = self.control = None
        for _ in range(1 if 'control_port = off' in cfg_text else 2):
            line = self.p.stdout.readline()
            if 'postgres on port' in line:
                self.pg = int(line.split('port')[1].split()[0])
            elif 'listening on port' in line:
                self.control = int(line.split('port')[1].split()[0])
        assert self.pg, 'evedb did not start'

    def stop(self, exe):
        if self.control:
            subprocess.run([exe, 'stop', '--connect', '127.0.0.1:%d' % self.control], capture_output=True)
        try:
            self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.p.kill()
        return self.p.returncode


def expect_error(fn, code=None):
    try:
        fn()
    except Exception as e:
        got = getattr(e, 'pgcode', None)
        if got is None and e.args and isinstance(e.args[0], dict):
            got = e.args[0].get('C')
        return (code is None or got == code), '%s %s' % (got, str(e).splitlines()[0][:90])
    return False, 'no error'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--evedb', default=os.path.join(ROOT, 'bin', 'evedb.exe'))
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    args = ap.parse_args()
    evedb, eve = os.path.abspath(args.evedb), os.path.abspath(args.eve)
    try:
        import psycopg2
        import pg8000.native
    except ImportError:
        print('needs: pip install psycopg2-binary pg8000')
        return 2
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)

    # ---------------------------------------------------------------- md5 login, a database of the configuration file
    srv = Server(evedb, 'port = 0\ncontrol_port = 0\nuser = "eve"\npassword = "s3cret"\nauth = "md5"\ntest = true\ndatabase "shop" = "data/shop.duckdb"\n')
    try:
        port = srv.pg
        ok, why = expect_error(lambda: psycopg2.connect(host='127.0.0.1', port=port, user='eve', password='wrong', dbname='shop'))
        check(ok, 'a wrong password is refused: ' + why)
        ok, why = expect_error(lambda: psycopg2.connect(host='127.0.0.1', port=port, user='eve', password='s3cret', dbname='nope'))
        check(ok, 'a database that is not in the configuration is refused: ' + why)
        c = psycopg2.connect(host='127.0.0.1', port=port, user='eve', password='s3cret', dbname='shop')
        check(c.server_version >= 160000, 'libpq logs in with md5 and reads the server version: %d' % c.server_version)
        cur = c.cursor()
        cur.execute('create table items (id bigint primary key, name varchar not null, price decimal(10,2), ok boolean, day date, ts timestamp, raw blob)')
        cur.execute('insert into items values (%s, %s, %s, %s, %s, %s, %s)', (1, "bolt's", 12.5, True, '2026-10-17', '2026-10-17 08:00:00', psycopg2.Binary(b'\x01\x02')))
        check(cur.rowcount == 1, 'INSERT answers its row count: %d' % cur.rowcount)
        cur.execute('insert into items (id, name) values (2, %s), (3, %s)', ('nut', 'washer'))
        c.commit()
        cur.execute('select id, name, price, ok, day, ts, raw from items order by id')
        rows = cur.fetchall()
        import datetime
        import decimal
        check(rows[0][:6] == (1, "bolt's", decimal.Decimal('12.50'), True, datetime.date(2026, 10, 17), datetime.datetime(2026, 10, 17, 8, 0)), 'the values come back with their PostgreSQL types: %r' % (rows[0][:6],))
        check(bytes(rows[0][6]) == b'\x01\x02', 'bytea travels as \\x hex')
        check(rows[1][2] is None and cur.description[0].name == 'id' and cur.description[0].type_code == 20, 'NULL, the column names and the type number of bigint (20)')
        ok, why = expect_error(lambda: cur.execute("insert into items (id, name) values (1, 'dup')"), '23000')
        check(ok, 'a duplicate key is SQLSTATE 23000: ' + why)
        ok, why = expect_error(lambda: cur.execute('select 1'), '25P02')
        check(ok, 'after an error the transaction is aborted until ROLLBACK (25P02): ' + why)
        c.rollback()
        cur.execute('select count(*) from items')
        check(cur.fetchone()[0] == 3, 'ROLLBACK ends the failed transaction and the table keeps its 3 rows')
        cur.execute("update items set price = 1 where id > 1")
        check(cur.rowcount == 2, 'UPDATE answers 2')
        c.rollback()
        cur.execute('select count(*) from items where price = 1')
        check(cur.fetchone()[0] == 0, 'a rolled back UPDATE leaves nothing')
        cur.execute('show transaction isolation level')
        check(cur.fetchone()[0] == 'read committed', 'SHOW answers the settings drivers ask for')
        cur.execute("select 1; select 'a;b' as t")
        check(cur.fetchone() == ('a;b',), 'two statements in one query; a ; inside a text is not a separator')
        ok, why = expect_error(lambda: cur.execute('select * from nowhere'), '42P01')
        check(ok, 'a missing table is 42P01: ' + why)
        c.rollback()
        # faults through SQL
        c.autocommit = True
        cur.execute("pragma eve_fault('conflict', 'items')")
        ok, why = expect_error(lambda: cur.execute('update items set price = 2 where id = 2'), '40001')
        check(ok, 'pragma eve_fault works through the PostgreSQL port: 40001 ' + why)
        c.close()

        # pg8000: the extended protocol
        p = pg8000.native.Connection('eve', host='127.0.0.1', port=port, database='shop', password='s3cret')
        rows = p.run('select id, name from items where id = :i', i=2)
        check(rows == [[2, 'nut']], 'pg8000 (extended protocol: Parse, Bind, Describe, Execute, Sync) binds a parameter: %r' % rows)
        p.run('insert into items (id, name, price) values (:i, :n, :p)', i=4, n='pin', p=0.5)
        check(p.row_count == 1, 'pg8000 insert answers 1')
        rows = p.run('select name, price from items where id = :i', i=4)
        check(rows[0][0] == 'pin' and float(rows[0][1]) == 0.5, 'and reads it back: %r' % rows)
        ok, why = expect_error(lambda: p.run('select * from nowhere'))
        check(ok, 'pg8000 gets the error: ' + why)
        check(p.run('select 41 + 1') == [[42]], 'and the connection works after the error (Sync ends the failed batch)')
        p.close()

        # the Eve driver
        proj = os.path.join(WORK, 'proj')
        os.makedirs(proj)
        with open(os.path.join(proj, 'eve.cfg'), 'w') as f:
            f.write('database "shop" = "postgres://eve:s3cret@127.0.0.1:%d/shop"\n' % port)
        with open(os.path.join(proj, 'pg.eve'), 'w') as f:
            f.write('''primary aspect pg is
  class Item = {id: Integer, name: String, price: Decimal?, ok: Logic?} <: Record;
  process main is
    new shop := database.connect("shop");
    print shop.execute!("insert into items (id, name, price, ok) values (?, ?, ?, ?)", 10, "it's", 7.25d, True);
    for i in shop.query!(:Item)("select id, name, price, ok from items where id >= ? order by id", 4) do
      print "{i.id} {i.name} {i.price} {i.ok}";
    done;
    print shop.query_one!(:Item)("select * from items where name = ?", "nut").id;
    shop.close();
  return;
end pg;
''')
        r = subprocess.run([eve, '-x', 'pg.eve'], capture_output=True, text=True, cwd=proj)
        lines = r.stdout.splitlines()
        check(r.returncode == 0 and lines == ['1', '4 pin 0.50 null', "10 it's 7.25 True", '2'], 'an Eve script reads and writes through postgres:// (exit %d): %r %s' % (r.returncode, lines, r.stderr.strip()[:200]))
        with open(os.path.join(proj, 'pgjob.eve'), 'w') as f:
            f.write('''primary aspect pgjob is
  process main is
    new shop := database.connect("shop");
    add: job
    do
      shop.execute!("insert into items (id, name) values (20, 'in a job')");
      rollback;
    done add;
    print jobs["add"].status;
    print shop.execute!("delete from items where id = 20");
  return;
end pgjob;
''')
        r = subprocess.run([eve, '-x', 'pgjob.eve'], capture_output=True, text=True, cwd=proj)
        check(r.returncode == 0 and r.stdout.strip().splitlines() == ['rolled back', '0'], 'a rollback of a job undoes the insert on the PostgreSQL connection: %r %s' % (r.stdout, r.stderr.strip()[:200]))
    finally:
        code = srv.stop(evedb)
        check(code == 0, 'evedb stops with status 0 (%s)' % code)

    # ---------------------------------------------------------------- trust and password modes, no test mode
    srv = Server(evedb, 'port = 0\ncontrol_port = off\nuser = "eve"\npassword = "pw"\nauth = "password"\n', 'pw.cfg')
    try:
        ok, why = expect_error(lambda: psycopg2.connect(host='127.0.0.1', port=srv.pg, user='eve', password='bad', dbname='x'))
        check(ok, 'auth = password refuses a wrong password: ' + why)
        ok, why = expect_error(lambda: psycopg2.connect(host='127.0.0.1', port=srv.pg, user='eve', password='pw', dbname='missing'))
        check(ok and 'does not exist' in why, 'outside test mode a database file that does not exist is refused: ' + why)
    finally:
        srv.p.kill()
        srv.p.wait()

    # ---------------------------------------------------------------- the two start forms of eve
    cfg = os.path.join(WORK, 'svc.cfg')
    with open(cfg, 'w') as f:
        f.write('port = 55491\ncontrol_port = 55492\ntest = true\ndatabase "demo" = "data/demo.duckdb"\n')
    run = os.path.join(WORK, 'run')
    os.makedirs(run)
    env = dict(os.environ, TMPDIR=run, TEMP=run, XDG_RUNTIME_DIR=run)
    r = subprocess.run([eve, '-s', '-db', '--serve', 'svc.cfg'], capture_output=True, text=True, cwd=WORK, env=env, timeout=30)
    check(r.returncode == 0 and r.stdout == '' and r.stderr == '', 'eve -s -db --serve svc.cfg: status 0, silent (%r %r)' % (r.stdout, r.stderr))
    try:
        c = psycopg2.connect(host='127.0.0.1', port=55491, user='eve', dbname='demo')
        cur = c.cursor()
        cur.execute('select 6 * 7')
        check(cur.fetchone()[0] == 42, 'the service answers on port 55491')
        c.close()
    except Exception as e:
        check(False, 'the service answers: %s' % e)
    r = subprocess.run([eve, '-s', '-db', '--serve', 'svc.cfg'], capture_output=True, text=True, cwd=WORK, env=env, timeout=30)
    check(r.returncode == 75 and 'runs already' in r.stderr, 'a second start says the server runs already (75): %r' % r.stderr.strip())
    check(os.path.exists(os.path.join(run, 'evedb-svc.log')), 'the log is <runtime>/evedb-svc.log')
    subprocess.run([evedb, 'stop', '--connect', '127.0.0.1:55492'], capture_output=True)
    time.sleep(1)
    fg = subprocess.Popen([eve, 'db', 'serve', 'svc.cfg'], cwd=WORK, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    first = fg.stdout.readline()
    check('postgres on port 55491' in first, 'eve db serve svc.cfg runs evedb in the foreground: %s' % first.strip())
    subprocess.run([evedb, 'stop', '--connect', '127.0.0.1:55492'], capture_output=True)
    try:
        fg.wait(timeout=10)
        check(fg.returncode == 0, 'and ends with the status of evedb (%s)' % fg.returncode)
    except subprocess.TimeoutExpired:
        fg.kill()
        check(False, 'eve db serve did not end after evedb stop')

    print('\n%d check(s) failed' % len(failures) if failures else '\nall checks passed')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
