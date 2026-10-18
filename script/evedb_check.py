"""Protocol tests of evedb (evedb/README.md, section 5), written in Python from the document alone.

The client below is independent of the Zig code: it builds and reads the frames with `struct`, so a mistake in the document or in
the server shows up as a failed check. It starts `bin/evedb.exe serve --test` on a free port with a fresh data folder (and a
second server for the token and lease tests), runs the checks and stops the servers.

usage: python script/evedb_check.py [--evedb bin/evedb.exe]

The files are made in `temp/evedb_check/`. Exit status 0 when all the checks pass.
"""
import argparse
import os
import shutil
import socket
import struct
import subprocess
import sys
import time
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'temp', 'evedb_check')
failures = []

# frame types, section 5.3
HELLO, OPEN, BEGIN, QUERY, EXECUTE, COMMIT, ROLLBACK, STATUS, PING, DESCRIBE, SERVERSTAT, CLOSE, STOP, QUERYB, LOAD = range(1, 16)
OK, HELLO_OK, OPENED, RESULT, EXECUTED, TXSTATUS, PONG, DESCRIBED, SERVERSTATS, SCHEMA, BATCH, END = 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B
# wire types of a column batch, section 5.5
W_BOOL, W_INT, W_REAL, W_TEXT, W_DATE, W_TS, W_DEC, W_BLOB = range(1, 9)
ERROR = 0xFF


def check(ok, what):
    print(('ok   ' if ok else 'FAIL ') + what)
    if not ok:
        failures.append(what)


class Closed(Exception):
    pass


class Err(Exception):
    def __init__(self, cls, state, transient, msg):
        super().__init__('%s %s: %s' % (cls, state, msg))
        self.cls, self.state, self.transient, self.msg = cls, state, transient, msg


def s(text):
    b = text.encode('utf-8')
    return struct.pack('<I', len(b)) + b


def value(v):
    """Encode a parameter (section 5.2)."""
    if v is None:
        return b'\x00'
    if isinstance(v, bool):
        return b'\x01' + bytes([int(v)])
    if isinstance(v, int):
        return b'\x02' + struct.pack('<q', v)
    if isinstance(v, float):
        return b'\x03' + struct.pack('<d', v)
    if isinstance(v, str):
        return b'\x04' + s(v)
    raise TypeError(v)


class Reader:
    def __init__(self, data):
        self.d, self.p = data, 0

    def take(self, n):
        if self.p + n > len(self.d):
            raise ValueError('short')
        r = self.d[self.p:self.p + n]
        self.p += n
        return r

    def u8(self): return self.take(1)[0]
    def u16(self): return struct.unpack('<H', self.take(2))[0]
    def u32(self): return struct.unpack('<I', self.take(4))[0]
    def u64(self): return struct.unpack('<Q', self.take(8))[0]
    def str(self): return self.take(self.u32()).decode('utf-8')

    def value(self):
        tag = self.u8()
        if tag == 0: return None
        if tag == 1: return bool(self.u8())
        if tag == 2: return struct.unpack('<q', self.take(8))[0]
        if tag == 3: return struct.unpack('<d', self.take(8))[0]
        if tag == 4: return self.str()
        if tag == 5: return self.take(self.u32())
        if tag == 6: return ('decimal', self.str())
        if tag == 7: return ('instant', struct.unpack('<q', self.take(8))[0])
        if tag == 8: return ('date', struct.unpack('<i', self.take(4))[0])
        if tag == 9: return ('huge', self.str())
        if tag == 10: return ('uuid', uuid.UUID(bytes=self.take(16)))
        raise ValueError('tag %d' % tag)

    def done(self): return self.p == len(self.d)


class Client:
    def __init__(self, port, token='', hello=True):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout=10)
        self.stream = 0
        if hello:
            self.hello(token)

    def send_raw(self, data):
        self.sock.sendall(data)

    def send(self, kind, payload=b''):
        self.stream += 1
        self.sock.sendall(struct.pack('<IBI', len(payload) + 5, kind, self.stream) + payload)
        return self.stream

    def recv_exact(self, n):
        buf = b''
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise Closed()
            buf += chunk
        return buf

    def recv(self):
        (n,) = struct.unpack('<I', self.recv_exact(4))
        body = self.recv_exact(n)
        return body[0], struct.unpack('<I', body[1:5])[0], body[5:]

    def call(self, kind, payload=b''):
        sid = self.send(kind, payload)
        t, stream, p = self.recv()
        if t == ERROR:
            r = Reader(p)
            raise Err(r.str(), r.str(), bool(r.u8()), r.str())
        assert stream == sid, 'the answer carries the stream of its request'
        return t, p

    def hello(self, token=''):
        t, p = self.call(HELLO, b'EWPD' + struct.pack('<H', 1) + s('python-check') + s(token))
        r = Reader(p)
        self.version, self.server, self.test_mode = r.u16(), r.str(), r.u8()

    def open(self, name):
        t, p = self.call(OPEN, s(name) + struct.pack('<I', os.getpid()))
        r = Reader(p)
        self.session, self.lease = r.u64(), r.u32()
        return self.session

    def begin(self, txid=None, read_only=False):
        txid = txid or uuid.uuid4().bytes
        self.call(BEGIN, txid + bytes([0, int(read_only)]))
        return txid

    def commit(self, txid): self.call(COMMIT, txid)
    def rollback(self, txid): self.call(ROLLBACK, txid)

    def status(self, txid):
        t, p = self.call(STATUS, txid)
        return p[0]

    def execute(self, sql, params=()):
        t, p = self.call(EXECUTE, s(sql) + struct.pack('<I', len(params)) + b''.join(value(x) for x in params))
        assert t == EXECUTED
        return struct.unpack('<q', p)[0]

    def query(self, sql, params=(), limit=0):
        t, p = self.call(QUERY, s(sql) + struct.pack('<I', len(params)) + b''.join(value(x) for x in params) + struct.pack('<I', limit))
        assert t == RESULT
        r = Reader(p)
        cols = [(r.str(), r.str()) for _ in range(r.u16())]
        rows = [[r.value() for _ in cols] for _ in range(r.u32())]
        truncated = bool(r.u8())
        assert r.done()
        return cols, rows, truncated

    def ping(self):
        t, p = self.call(PING)
        return struct.unpack('<I', p)[0]

    def describe(self, table):
        t, p = self.call(DESCRIBE, s(table))
        r = Reader(p)
        return [(r.str(), r.str(), r.str(), bool(r.u8()), bool(r.u8())) for _ in range(r.u16())]

    def serverstat(self):
        t, p = self.call(SERVERSTAT)
        r = Reader(p)
        return r.u32(), r.u32(), r.u32(), r.u64(), r.u64()

    def queryb(self, sql, params=()):
        """A query answered with column batches: (columns as (name, wire type), rows as lists)."""
        sid = self.send(QUERYB, s(sql) + struct.pack('<I', len(params)) + b''.join(value(x) for x in params) + struct.pack('<I', 0))
        cols, rows, batches = None, [], 0
        while True:
            t, stream, p = self.recv()
            if t == ERROR:
                r = Reader(p)
                raise Err(r.str(), r.str(), bool(r.u8()), r.str())
            assert stream == sid
            r = Reader(p)
            if t == SCHEMA:
                cols = [(r.str(), r.u8()) for _ in range(r.u16())]
            elif t == BATCH:
                batches += 1
                n = r.u32()
                columns = []
                for _, w in cols:
                    valid = r.take((n + 7) // 8) if r.u8() == 1 else None
                    if w == W_BOOL:
                        vals = [b != 0 for b in r.take(n)]
                    elif w in (W_INT, W_DATE, W_TS):
                        vals = list(struct.unpack('<%dq' % n, r.take(8 * n)))
                    elif w == W_REAL:
                        vals = list(struct.unpack('<%dd' % n, r.take(8 * n)))
                    else:
                        offs = struct.unpack('<%dI' % (n + 1), r.take(4 * (n + 1)))
                        data = r.take(offs[-1])
                        vals = [data[offs[i]:offs[i + 1]] if w == W_BLOB else data[offs[i]:offs[i + 1]].decode('utf-8') for i in range(n)]
                    if valid is not None:
                        vals = [v if (valid[i // 8] >> (i % 8)) & 1 else None for i, v in enumerate(vals)]
                    columns.append(vals)
                rows.extend(list(x) for x in zip(*columns)) if columns else None
                assert r.done()
            elif t == END:
                total = r.u64()
                assert total == len(rows), (total, len(rows))
                self.batches = batches
                return cols, rows

    def load(self, table, cols, rows, create=True, batch=1000):
        """A bulk load: the head, the batches and the end, pipelined; the answer is the number of rows."""
        head = s(table) + bytes([1 if create else 0]) + struct.pack('<H', len(cols)) + b''.join(s(n) + bytes([w]) for n, w in cols)
        self.stream += 1
        sid = self.stream
        def frame(kind, payload):
            self.sock.sendall(struct.pack('<IBI', len(payload) + 5, kind, sid) + payload)
        frame(LOAD, head)
        for start in range(0, len(rows), batch):
            part = rows[start:start + batch]
            n = len(part)
            body = struct.pack('<I', n)
            for k, (_, w) in enumerate(cols):
                vals = [row[k] for row in part]
                if any(v is None for v in vals):
                    bits = bytearray((n + 7) // 8)
                    for i, v in enumerate(vals):
                        if v is not None:
                            bits[i // 8] |= 1 << (i % 8)
                    body += b'\x01' + bytes(bits)
                else:
                    body += b'\x00'
                if w == W_BOOL:
                    body += bytes(1 if v else 0 for v in vals)
                elif w in (W_INT, W_DATE, W_TS):
                    body += struct.pack('<%dq' % n, *[v or 0 for v in vals])
                elif w == W_REAL:
                    body += struct.pack('<%dd' % n, *[v or 0.0 for v in vals])
                else:
                    data = [(v.encode('utf-8') if isinstance(v, str) else (v or b'')) for v in vals]
                    offs = [0]
                    for d in data:
                        offs.append(offs[-1] + len(d))
                    body += struct.pack('<%dI' % (n + 1), *offs) + b''.join(data)
            frame(BATCH, body)
        frame(END, b'')
        t, stream, p = self.recv()
        if t == ERROR:
            r = Reader(p)
            raise Err(r.str(), r.str(), bool(r.u8()), r.str())
        assert t == EXECUTED and stream == sid
        return struct.unpack('<q', p)[0]

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def expect_err(fn, cls=None, state=None, transient=None):
    try:
        fn()
    except Err as e:
        ok = (cls is None or e.cls == cls) and (state is None or e.state == state) and (transient is None or e.transient == transient)
        return ok, '%s %s transient=%s %s' % (e.cls, e.state, e.transient, e.msg.splitlines()[0])
    except Closed:
        return False, 'connection closed'
    return False, 'no error'


def dropped(fn):
    """True when the server closed the connection instead of answering."""
    try:
        fn()
    except Closed:
        return True
    except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError, socket.timeout):
        return True
    return False


class Server:
    def __init__(self, exe, data, *extra):
        self.p = subprocess.Popen([exe, 'serve', '--port', '0', '--control-port', '0', '--data', data, *extra], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.port = self.pg_port = None
        for _ in range(2):
            line = self.p.stdout.readline()
            assert 'on port' in line, line
            number = int(line.split('port')[1].split()[0])
            if 'postgres' in line:
                self.pg_port = number
            else:
                self.port = number
        assert self.port and self.pg_port

    def stop(self):
        try:
            c = Client(self.port, token=os.environ.get('EVEDB_CHECK_TOKEN', ''))
            c.call(STOP)
            c.close()
        except Exception:
            pass
        try:
            self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.p.kill()
        return self.p.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--evedb', default=os.path.join(ROOT, 'bin', 'evedb.exe'))
    args = ap.parse_args()
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    srv = Server(args.evedb, os.path.join(WORK, 'data'), '--test')
    try:
        run_checks(srv)
    finally:
        code = srv.stop()
        check(code == 0, 'the stop frame ends the server with exit status 0 (got %s)' % code)
    run_token_and_lease(args.evedb)
    print('\n%d check(s) failed' % len(failures) if failures else '\nall checks passed')
    return 1 if failures else 0


def run_checks(srv):
    port = srv.port
    # --- the handshake
    c = Client(port)
    check(c.version == 1 and c.server.startswith('evedb') and c.test_mode == 1, 'HELLO_OK: version 1, the server name, test mode on: %s' % c.server)
    c.close()
    c = Client(port, hello=False)
    ok, why = expect_err(lambda: c.call(OPEN, s('x') + struct.pack('<I', 0)), 'ProtocolError')
    check(ok, 'a frame before HELLO is a ProtocolError: ' + why)
    check(dropped(lambda: c.call(PING)), 'and the connection is closed')
    c.close()
    c = Client(port, hello=False)
    ok, why = expect_err(lambda: c.call(HELLO, b'XXXX' + struct.pack('<H', 1) + s('x') + s('')), 'ProtocolError')
    check(ok, 'a wrong magic is a ProtocolError: ' + why)
    c.close()
    c = Client(port, hello=False)
    c.send_raw(struct.pack('<I', 16 * 1024 * 1024 + 6) + b'\x01')
    try:
        t, st, p = c.recv()
        check(t == ERROR and Reader(p).str() == 'ProtocolError', 'a frame larger than 16 MiB is refused with a ProtocolError')
    except Closed:
        check(True, 'a frame larger than 16 MiB closes the connection')
    c.close()
    c = Client(port)
    ok, why = expect_err(lambda: c.call(QUERY, s('select 1') + struct.pack('<II', 0, 0)), 'ProtocolError')
    check(ok, 'QUERY before OPEN is a ProtocolError: ' + why)
    c.close()
    c = Client(port)
    ok, why = expect_err(lambda: c.open('../evil'), 'ProtocolError')
    check(ok, 'a database name that leaves the folder is refused: ' + why)
    c.close()

    # --- statements and values
    a = Client(port)
    a.open('shop')
    check(a.lease == 30000, 'OPENED: the lease is 30000 ms: %s' % a.lease)
    a.execute('create table items (id bigint primary key, name varchar not null, price decimal(10,2), qty integer, ok boolean, day date, ts timestamp, big hugeint, raw blob, uid uuid, ratio double)')
    n = a.execute("insert into items values (?, ?, 12.50, ?, ?, '2026-10-17', '2026-10-17 08:00:00', 170141183460469231731687303715884105727, '\\x01\\x02'::blob, '00112233-4455-6677-8899-aabbccddeeff', ?)", (1, 'bolt', 7, True, 2.5))
    check(n == 1, 'EXECUTE answers the rows changed: %s' % n)
    cols, rows, trunc = a.query('select id, name, price, qty, ok, day, ts, big, raw, uid, ratio, null as nothing from items')
    types = [t for _, t in cols]
    check(types == ['Integer', 'String', 'Decimal', 'Integer', 'Logic', 'Date', 'Instant', 'Huge', 'Bytes', 'Uuid', 'Real', 'Integer'], 'the columns carry the Eve types: %s' % types)
    r = rows[0]
    check(r[0] == 1 and r[1] == 'bolt' and r[3] == 7 and r[4] is True and r[10] == 2.5 and r[11] is None, 'integer, string, integer, boolean, real and null values: %s' % (r[:5],))
    check(r[2] == ('decimal', '12.50'), 'a decimal travels as its text: %s' % (r[2],))
    check(r[5] == ('date', 20743), 'a date is days since 1970-01-01: %s' % (r[5],))
    check(r[6] == ('instant', 1792224000000000), 'an instant is micro seconds since 1970: %s' % (r[6],))
    check(r[7] == ('huge', '170141183460469231731687303715884105727'), 'a huge number travels as its text')
    check(r[8] == b'\x01\x02', 'bytes travel as bytes')
    check(r[9] == ('uuid', uuid.UUID('00112233-4455-6677-8899-aabbccddeeff')), 'a uuid travels as 16 bytes')
    for i in range(2, 6):
        a.execute('insert into items (id, name) values (?, ?)', (i, 'n%d' % i))
    cols, rows, trunc = a.query('select id from items order by id', limit=3)
    check(len(rows) == 3 and trunc, 'the row limit cuts the result and sets the truncated flag')
    cols, rows, trunc = a.query('select id from items order by id')
    check(len(rows) == 5 and not trunc, 'without a limit all the rows come')
    ok, why = expect_err(lambda: a.execute('insert into items (id, name) values (1, ?)', ('dup',)), 'ConstraintError', '23000', False)
    check(ok, 'a duplicate key is a ConstraintError 23000: ' + why)
    ok, why = expect_err(lambda: a.query('select * from nowhere'), 'DatabaseError', '42P01', False)
    check(ok, 'a missing table is 42P01: ' + why)
    ok, why = expect_err(lambda: a.query('selec 1'), 'DatabaseError', '42601', False)
    check(ok, 'a syntax error is 42601: ' + why)
    check(a.ping() == 30000, 'PING answers the lease')
    d = a.describe('items')
    check(d[0] == ('id', 'Integer', 'BIGINT', False, True) and d[1][:2] == ('name', 'String') and d[1][3] is False and d[2][1] == 'Decimal', 'DESCRIBE: names, Eve types, nullable and key: %s' % (d[:3],))
    ok, why = expect_err(lambda: a.describe('nope'), 'DatabaseError', '42P01')
    check(ok, 'DESCRIBE of a missing table is 42P01: ' + why)

    # --- transactions
    t1 = a.begin()
    a.execute('insert into items (id, name) values (100, ?)', ('rolled',))
    ok, why = expect_err(lambda: a.begin(), 'ProtocolError')
    check(ok, 'a second BEGIN in a session is a ProtocolError: ' + why)
    b = Client(port)
    b.open('shop')
    check(b.status(t1) == 3, 'STATUS of a transaction that is open in another session is 3 (in progress)')
    check(b.query('select count(*) from items where id = 100')[1][0][0] == 0, 'another session does not see the open transaction')
    a.rollback(t1)
    check(a.query('select count(*) from items where id = 100')[1][0][0] == 0, 'ROLLBACK removes the rows')
    check(b.status(t1) == 1, 'STATUS after a rollback is 1 (rolled back)')
    t2 = a.begin()
    a.execute('insert into items (id, name) values (101, ?)', ('kept',))
    a.commit(t2)
    check(b.query('select count(*) from items where id = 101')[1][0][0] == 1, 'COMMIT makes the rows visible to others')
    check(b.status(t2) == 0, 'STATUS after a commit is 0 (committed): the id is in eve_tx')
    check(b.status(uuid.uuid4().bytes) == 1, 'STATUS of an unknown id is 1')
    ro = a.begin(read_only=True)
    ok, why = expect_err(lambda: a.execute('insert into items (id, name) values (102, ?)', ('x',)), 'DatabaseError')
    check(ok, 'a read only transaction refuses a write: ' + why)
    a.rollback(ro)

    # --- a real conflict between two transactions
    t3 = a.begin()
    t4 = b.begin()
    a.execute('update items set qty = 1 where id = 2')
    ok, why = expect_err(lambda: b.execute('update items set qty = 2 where id = 2'), 'ConflictError', '40001', True)
    check(ok, 'two transactions that update one row conflict: ConflictError 40001, transient: ' + why)
    b.rollback(t4)
    a.commit(t3)

    # --- faults
    ok, why = expect_err(lambda: a.execute("pragma eve_fault('drop', 'nowhere')"), 'DatabaseError', '42601')
    check(ok, 'a fault with a bad point is refused: ' + why)
    a.execute("pragma eve_fault('conflict', 'items')")
    ok, why = expect_err(lambda: a.execute('update items set qty = 9 where id = 3'), 'ConflictError', '40001', True)
    check(ok, 'fault conflict: the next statement on the table fails: ' + why)
    check(a.execute('update items set qty = 9 where id = 3') == 1, 'and the fault fires once')
    a.execute("pragma eve_fault('deadlock')")
    ok, why = expect_err(lambda: a.query('select 1'), 'DeadlockError', '40P01', True)
    check(ok, 'fault deadlock: ' + why)
    tc = a.begin()
    a.execute('insert into items (id, name) values (200, ?)', ('cf',))
    a.execute("pragma eve_fault('commit_fail')")
    ok, why = expect_err(lambda: a.commit(tc), 'CommitError', None, True)
    check(ok, 'fault commit_fail: the commit fails: ' + why)
    check(a.query('select count(*) from items where id = 200')[1][0][0] == 0, 'and the transaction was rolled back')
    check(b.status(tc) == 1, 'STATUS says rolled back')
    # drop before the commit: nothing is committed
    d1 = Client(port)
    d1.open('shop')
    td = d1.begin()
    d1.execute('insert into items (id, name) values (201, ?)', ('drop-before',))
    d1.execute("pragma eve_fault('drop', 'before_commit')")
    check(dropped(lambda: d1.commit(td)), 'fault drop before_commit: the server closes the connection without an answer')
    d1.close()
    time.sleep(0.3)
    check(b.status(td) == 1 and b.query('select count(*) from items where id = 201')[1][0][0] == 0, 'the doubt is resolved: rolled back, no row')
    # drop after the commit: the commit is real
    d2 = Client(port)
    d2.open('shop')
    te = d2.begin()
    d2.execute('insert into items (id, name) values (202, ?)', ('drop-after',))
    d2.execute("pragma eve_fault('drop', 'after_commit')")
    check(dropped(lambda: d2.commit(te)), 'fault drop after_commit: the connection closes before the answer')
    d2.close()
    time.sleep(0.3)
    check(b.status(te) == 0 and b.query('select count(*) from items where id = 202')[1][0][0] == 1, 'the doubt is resolved: STATUS says committed and the row is there')
    # drop at execute and at begin
    d3 = Client(port)
    d3.open('shop')
    d3.execute("pragma eve_fault('drop', 'execute')")
    check(dropped(lambda: d3.execute('select 1')), 'fault drop execute closes the connection')
    d3.close()
    d4 = Client(port)
    d4.open('shop')
    d4.execute("pragma eve_fault('drop', 'begin')")
    check(dropped(lambda: d4.begin()), 'fault drop begin closes the connection')
    d4.close()
    a.execute("pragma eve_fault('status_unknown')")
    check(a.status(t2) == 2, 'fault status_unknown: STATUS answers 2')
    check(a.status(t2) == 0, 'and only once')
    a.execute("pragma eve_fault('delay', 300)")
    t0 = time.time()
    a.ping()
    check(time.time() - t0 >= 0.25, 'fault delay: each frame waits (%.2f s)' % (time.time() - t0))
    a.close()
    e = Client(port)
    e.open('shop')
    e.execute("pragma eve_fault('lease_expire')")
    time.sleep(1.0)
    ok, why = expect_err(lambda: e.ping(), 'LeaseExpired', '08003', True)
    check(ok, 'fault lease_expire: the next frame says LeaseExpired: ' + why)
    e.close()
    # scope all
    f1 = Client(port)
    f1.open('shop')
    f1.execute("pragma eve_fault('deadlock', '', 'all')")
    g1 = Client(port)
    g1.open('shop')
    ok, why = expect_err(lambda: g1.query('select 1'), 'DeadlockError')
    check(ok, 'a fault of scope all fires in another session: ' + why)
    f1.close()
    g1.close()

    # --- column batches (section 5.5): the fast path of eve
    cols, rows = b.queryb("select i::bigint as id, i * 0.5 as half, 'n' || i::varchar as name, i % 2 = 0 as even, case when i % 5 = 0 then null else i::integer end as five, date '2026-01-01' + i::integer as day, timestamp '2026-01-01 00:00:00' as ts, (i::decimal(10,2) / 4) as q from range(5000) t(i) order by i")
    check([c[1] for c in cols] == [W_INT, W_DEC, W_TEXT, W_BOOL, W_INT, W_DATE, W_TS, W_REAL], 'QUERYB: the schema names the wire types: %s' % [c[1] for c in cols])
    check(len(rows) == 5000 and b.batches >= 2, 'QUERYB: 5000 rows in %d batches (one per DuckDB chunk)' % b.batches)
    check(rows[7] == [7, '3.5', 'n7', False, 7, 20461, 1767225600000000, 1.75], 'QUERYB: the values of row 7: %r' % (rows[7],))
    check(rows[10][4] is None and rows[4999][0] == 4999, 'QUERYB: a NULL in the bitmap, and the last row')
    n = b.load('fast', [('id', W_INT), ('name', W_TEXT), ('price', W_REAL), ('ok', W_BOOL), ('day', W_DATE), ('raw', W_BLOB)],
               [[i, ('row %d' % i) if i % 7 else None, i / 8, i % 3 == 0, 20000 + i, b'\x00\xff'] for i in range(2500)])
    check(n == 2500, 'LOAD: 2500 rows appended in 3 batches through the Appender (%s)' % n)
    _, back = b.queryb('select id, name, price, ok, day, raw from fast where id in (0, 7, 2499) order by id')
    check(back == [[0, None, 0.0, True, 20000, b'\x00\xff'], [7, None, 0.875, False, 20007, b'\x00\xff'], [2499, None, 312.375, True, 22499, b'\x00\xff']], 'LOAD then QUERYB: the rows come back as they were sent: %r' % (back,))
    ok, why = expect_err(lambda: b.load('fast', [('id', W_INT)], [[1]]), 'DatabaseError')
    check(ok, 'LOAD into a table that exists, with create, is refused: ' + why)
    check(b.ping() == 30000, 'and the connection is in step after the refused load (the batches were drained)')
    n = b.load('fast', [('id', W_INT), ('name', W_TEXT), ('price', W_REAL), ('ok', W_BOOL), ('day', W_DATE), ('raw', W_BLOB)], [[9000, 'x', 1.0, True, 1, b'']], create=False)
    check(n == 1 and b.query('select count(*) from fast')[1][0][0] == 2501, 'LOAD without create appends to the table')
    tl = b.begin()
    b.load('fast', [('id', W_INT), ('name', W_TEXT), ('price', W_REAL), ('ok', W_BOOL), ('day', W_DATE), ('raw', W_BLOB)], [[9001, 'y', 1.0, True, 1, b'']], create=False)
    b.rollback(tl)
    check(b.query('select count(*) from fast')[1][0][0] == 2501, 'a LOAD inside a transaction is undone by ROLLBACK')

    # --- the statement log
    cols, rows, _ = b.query("select sql from eve_log.statements where kind = 'insert' and tbl = 'items' order by seq")
    texts = [r[0] for r in rows]
    check(any('values (100, ?)' in t for t in texts) and len(texts) >= 8, 'the statement log keeps the statements, also of a transaction that rolled back: %d inserts' % len(texts))
    cols, rows, _ = b.query("select count(*) from eve_log.statements where sql like 'pragma eve_fault%'")
    check(rows[0][0] == 0, 'a fault statement is not logged')
    st = b.serverstat()
    check(st[0] >= 1 and st[1] >= 1 and st[3] > 10 and st[4] > 0, 'SERVERSTAT: databases, sessions, statements, uptime: %s' % (st,))
    b.close()


def run_token_and_lease(exe):
    data = os.path.join(WORK, 'data2')
    srv = Server(exe, data, '--token', 'sesame', '--lease', '1')
    os.environ['EVEDB_CHECK_TOKEN'] = 'sesame'
    try:
        ok, why = expect_err(lambda: Client(srv.port, token='wrong'), 'AuthError', '28000')
        check(ok, 'a wrong token is refused: ' + why)
        c = Client(srv.port, token='sesame')
        check(c.test_mode == 0, 'the token is accepted and test mode is off')
        c.open('prod')
        check(c.lease == 1000, 'the lease follows --lease: %s' % c.lease)
        ok, why = expect_err(lambda: c.execute("pragma eve_fault('drop', 'begin')"), 'DatabaseError', '42501')
        check(ok, 'pragma eve_fault is refused outside test mode: ' + why)
        c.execute('create table k (id bigint primary key)')
        t = c.begin()
        c.execute('insert into k values (1)')
        time.sleep(2.0)
        ok, why = expect_err(lambda: c.ping(), 'LeaseExpired')
        check(ok, 'a lease that runs out answers LeaseExpired: ' + why)
        c.close()
        d = Client(srv.port, token='sesame')
        d.open('prod')
        check(d.query('select count(*) from k')[1][0][0] == 0, 'and the open transaction was rolled back')
        check(d.status(t) == 1, 'STATUS of the rolled back transaction is 1')
        d.close()
        keep = Client(srv.port, token='sesame')
        keep.open('prod')
        for _ in range(4):
            time.sleep(0.5)
            keep.ping()
        check(True, 'PING keeps a session alive past its lease (2 s with a lease of 1 s)')
        keep.close()
    finally:
        code = srv.stop()
        check(code == 0, 'the second server stops with exit status 0 (got %s)' % code)


if __name__ == '__main__':
    sys.exit(main())
