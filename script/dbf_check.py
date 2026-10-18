"""Tests of the DBF decoder and encoder of the machine (D-184), written in Python on purpose.

DBF is a legacy format: the machine only reads it (`eve db import`) and writes it (`eve db export`). This script makes
DBF files with the `struct` module, independently of the Zig code, runs the two commands and checks what comes out.

usage: python script/dbf_check.py [--eve bin/eve.exe]

The files are made in `temp/dbf_check/`. Exit status 0 when all the checks pass.
"""
import argparse
import datetime
import os
import shutil
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'temp', 'dbf_check')
failures = []


def check(ok, what):
    print(('ok   ' if ok else 'FAIL ') + what)
    if not ok:
        failures.append(what)


def make_dbf(path, fields, records, deleted=()):
    """fields: (name, type, length, decimals); records: list of lists of text (already formatted); deleted: row numbers."""
    header_len = 32 + 32 * len(fields) + 1
    rec_len = 1 + sum(f[2] for f in fields)
    today = datetime.date(2026, 10, 17)
    out = struct.pack('<BBBBIHH20x', 0x03, today.year - 1900, today.month, today.day, len(records), header_len, rec_len)
    for name, kind, length, dec in fields:
        out += struct.pack('<11sc4xBB14x', name.encode('ascii'), kind.encode('ascii'), length, dec)
    out += b'\r'
    for i, rec in enumerate(records):
        out += b'*' if i in deleted else b' '
        for (name, kind, length, dec), text in zip(fields, rec):
            raw = text.encode('latin-1')[:length]
            out += raw.rjust(length) if kind in 'NF' else raw.ljust(length)
    out += b'\x1a'
    with open(path, 'wb') as f:
        f.write(out)


def read_dbf(path):
    """A small independent reader: (fields, records) with the records that are not deleted."""
    data = open(path, 'rb').read()
    n, header_len, rec_len = struct.unpack('<IHH', data[4:12])
    fields = []
    for i in range((header_len - 33) // 32):
        d = data[32 + 32 * i:64 + 32 * i]
        fields.append((d[:11].split(b'\0')[0].decode('ascii'), chr(d[11]), d[16], d[17]))
    records = []
    for r in range(n):
        rec = data[header_len + r * rec_len:header_len + (r + 1) * rec_len]
        if rec[:1] == b'*':
            continue
        off = 1
        row = []
        for _, kind, length, _ in fields:
            row.append(rec[off:off + length].decode('latin-1').strip())
            off += length
        records.append(row)
    return fields, records


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    args = ap.parse_args()
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)

    def eve(*a):
        p = subprocess.run([args.eve, *a], capture_output=True, text=True, encoding='utf-8', errors='replace', cwd=WORK)
        return p.returncode, (p.stdout + p.stderr)

    # 1. a file with every type, a deleted record, blanks and a text with accents
    fields = [('NAME', 'C', 12, 0), ('QTY', 'N', 6, 0), ('PRICE', 'N', 8, 2), ('DAY', 'D', 8, 0), ('OK', 'L', 1, 0)]
    rows = [
        ['bolt', '10', '1.50', '20261001', 'T'],
        ['gone', '99', '9.99', '20260101', 'F'],
        ['caf\xe9', '', '', '', '?'],
        ['nut', '7', '0.25', '20261002', 'N'],
    ]
    make_dbf(os.path.join(WORK, 'parts.dbf'), fields, rows, deleted={1})
    code, out = eve('db', 'import', 'w.db', 'parts.dbf')
    check(code == 0 and 'imported 3 rows, 5 columns into parts' in out, 'import counts the rows that are not deleted: ' + out.strip())
    code, out = eve('db', 'sql', '-t', 'w.db', 'select NAME, QTY, PRICE, DAY, OK from parts order by rowid')
    lines = [l.split('\t') for l in out.strip().splitlines()]
    check(lines[1] == ['bolt', '10', '1.5', '2026-10-01', '1'], 'first record converted: ' + str(lines[1:2]))
    check(lines[2][0] == 'caf\u00e9', 'Latin-1 text is read as UTF-8: ' + str(lines[2][0]))
    check(lines[2][1:] == ['NULL', 'NULL', 'NULL', 'NULL'] or lines[2][1:] == ['', '', '', ''], 'blanks are NULL: ' + str(lines[2:3]))
    check(lines[3] == ['nut', '7', '0.25', '2026-10-02', '0'], 'last record converted: ' + str(lines[3:4]))
    code, out = eve('db', 'sql', '-t', 'w.db', "select name, type from pragma_table_info('parts')")
    types = dict(l.split('\t') for l in out.strip().splitlines()[1:])
    check(types == {'NAME': 'TEXT', 'QTY': 'INTEGER', 'PRICE': 'REAL', 'DAY': 'DATE', 'OK': 'BOOLEAN'}, 'types come from the file: ' + str(types))

    # 2. a second import into the same table is refused and changes nothing
    code, out = eve('db', 'import', 'w.db', 'parts.dbf')
    check(code != 0 and 'error' in out, 'a table that exists is refused')
    code, out = eve('db', 'sql', '-t', 'w.db', 'select count(*) from parts')
    check(out.strip().splitlines()[-1] == '3', 'the table is unchanged after the refusal')

    # 3. export to DBF and read it back with the independent reader
    code, out = eve('db', 'export', 'w.db', 'parts', 'back.dbf')
    check(code == 0 and os.path.exists(os.path.join(WORK, 'back.dbf')), 'export writes the file: ' + out.strip())
    f2, r2 = read_dbf(os.path.join(WORK, 'back.dbf'))
    check([f[0] for f in f2] == ['NAME', 'QTY', 'PRICE', 'DAY', 'OK'], 'the names are kept: ' + str([f[0] for f in f2]))
    check(r2[0][:2] == ['bolt', '10'] and r2[2][0] == 'nut', 'the values are written: ' + str(r2))
    check(r2[1][1] == '' and r2[1][2] == '', 'NULL is a blank cell')

    # 4. a file that is not DBF, and a file that is cut
    with open(os.path.join(WORK, 'fake.dbf'), 'wb') as f:
        f.write(b'this is not a dbf file at all, only words ' * 3)
    code, out = eve('db', 'import', 'w.db', 'fake.dbf')
    check(code != 0 and 'error' in out, 'a file that is not DBF is refused: ' + out.strip())
    whole = open(os.path.join(WORK, 'parts.dbf'), 'rb').read()
    with open(os.path.join(WORK, 'cut.dbf'), 'wb') as f:
        f.write(whole[:len(whole) - 20])
    code, out = eve('db', 'import', 'w.db', 'cut.dbf')
    check(code == 0 and 'imported 2 rows' in out, 'a cut file gives the records that are all there: ' + out.strip())

    # 5. the other formats and the refusal of a spreadsheet
    with open(os.path.join(WORK, 'c.csv'), 'w', encoding='utf-8') as f:
        f.write('id,name\n1,"a, b"\n2,"say ""hi"""\n')
    code, out = eve('db', 'import', 'w.db', 'c.csv')
    check(code == 0, 'csv imports: ' + out.strip())
    code, out = eve('db', 'sql', '-t', 'w.db', 'select name from c order by id')
    check(out.strip().splitlines()[1:] == ['a, b', 'say "hi"'], 'csv quotes are read: ' + out.strip())
    code, out = eve('db', 'import', 'w.db', 'sheet.xls')
    check(code != 0 and 'save a spreadsheet as CSV' in out, 'xls is refused with the reason')

    print('\n%d check(s) failed' % len(failures) if failures else '\nall checks passed')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
