#!/usr/bin/env python3
"""Make the sample tables of test/project: DBF files in data/ and SQLite files in db/.

They are there to try the structure dialog, the table views and SQL of evetx by hand:

  data/customers.dbf   8 records (one deleted), 6 fields: N, C, C, N with decimals, D, L
  data/orders.dbf      12 records, 6 fields
  data/empty.dbf       one field, no records (to append rows, to change the structure)
  db/shop.db           SQLite: tables customers, orders, items and the view big_orders
  db/empty.db          SQLite with no table (to create one)

Run from the root of the repository (needs bin/eve.exe for the SQLite files):  python script/mk_project_fixtures.py
The files are plain data; running the script again makes them again.
"""
import datetime
import os
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, 'test', 'project')
EVE = os.path.join(ROOT, 'bin', 'eve.exe')


def field(name, kind, length, dec=0):
    return name.encode().ljust(11, b'\0') + kind.encode() + b'\0' * 4 + bytes([length, dec]) + b'\0' * 14


def dbf(path, fields, rows, deleted=()):
    """fields: (name, kind, length, decimals); rows: lists of text values, in the order of the fields."""
    record_len = 1 + sum(f[2] for f in fields)
    header_len = 32 + 32 * len(fields) + 1
    today = datetime.date.today()
    out = bytearray(bytes([3, today.year % 100, today.month, today.day]))
    out += struct.pack('<I', len(rows)) + struct.pack('<HH', header_len, record_len) + b'\0' * 20
    for f in fields:
        out += field(*f)
    out += b'\r'
    for i, row in enumerate(rows):
        out += b'*' if i in deleted else b' '
        for f, v in zip(fields, row):
            text = str(v)
            if f[1] in 'NF':
                text = text.rjust(f[2])
            else:
                text = text.ljust(f[2])
            out += text[:f[2]].encode('latin-1', 'replace')
    out += b'\x1a'
    with open(path, 'wb') as fh:
        fh.write(out)
    print('wrote', os.path.relpath(path, ROOT), len(rows), 'records')


customers = [
    (1, 'Ann Baker', 'Boston', '1200.50', '20240105', 'T'),
    (2, 'Bob Stone', 'Chicago', '300.00', '20240212', 'T'),
    (3, 'Cy Moreno', 'Denver', '0.00', '20240318', 'F'),
    (4, 'Dee Park', 'Boston', '4500.75', '20240422', 'T'),
    (5, 'Eli Rossi', 'Austin', '99.99', '20240530', 'F'),
    (6, 'Fay Chen', 'Seattle', '780.00', '20240611', 'T'),
    (7, 'Gus Novak', 'Denver', '15.25', '20240719', 'T'),
    (8, 'Hal Weiss', 'Chicago', '2210.10', '20240802', 'T'),
]
dbf(os.path.join(PROJECT, 'data', 'customers.dbf'),
    [('ID', 'N', 5, 0), ('NAME', 'C', 20, 0), ('CITY', 'C', 15, 0), ('CREDIT', 'N', 10, 2), ('JOINED', 'D', 8, 0), ('ACTIVE', 'L', 1, 0)],
    customers, deleted=(4,))

products = [('keyboard', 45.00), ('mouse', 19.90), ('monitor', 189.00), ('cable', 4.50), ('dock', 129.00)]
orders = []
for n in range(12):
    p = products[n % len(products)]
    orders.append((1000 + n, 1 + n % 8, p[0], 1 + n % 4, '%.2f' % p[1], '2024%02d%02d' % (1 + n % 12, 3 + n)))
dbf(os.path.join(PROJECT, 'data', 'orders.dbf'),
    [('ORDER_ID', 'N', 6, 0), ('CUST_ID', 'N', 5, 0), ('PRODUCT', 'C', 20, 0), ('QTY', 'N', 4, 0), ('PRICE', 'N', 9, 2), ('DAY', 'D', 8, 0)],
    orders)
dbf(os.path.join(PROJECT, 'data', 'empty.dbf'), [('CODE', 'C', 10, 0)], [])


def sqlite(path, script):
    if os.path.exists(path):
        os.remove(path)
    result = subprocess.run([EVE, 'db', 'sql', path, script], capture_output=True, text=True)
    if 'error:' in result.stdout:
        sys.exit(result.stdout)
    print('wrote', os.path.relpath(path, ROOT))


rows_c = ',\n'.join("(%d, '%s', '%s', %s)" % (c[0], c[1], c[2], c[3]) for c in customers)
rows_o = ',\n'.join("(%d, %d, '%s', %d, %s)" % (o[0], o[1], o[2], o[3], o[4]) for o in orders)
sqlite(os.path.join(PROJECT, 'db', 'shop.db'), """
create table customers (id integer primary key, name text not null, city text, credit real default 0);
insert into customers values %s;
create table orders (order_id integer primary key, cust_id integer not null, product text, qty integer default 1, price real);
insert into orders values %s;
create table items (sku text primary key, title text not null, stock integer default 0);
insert into items values ('KB-01', 'keyboard', 14), ('MS-02', 'mouse', 40), ('MN-03', 'monitor', 6), ('CB-04', 'cable', 120), ('DK-05', 'dock', 9);
create view big_orders as select order_id, product, qty * price as total from orders where qty * price > 100;
""" % (rows_c, rows_o))
sqlite(os.path.join(PROJECT, 'db', 'empty.db'), 'pragma user_version = 1;')
